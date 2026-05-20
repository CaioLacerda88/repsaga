import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../../../core/data/json_helpers.dart';
import '../../../core/exceptions/app_exception.dart';
import '../models/body_part.dart';
import '../models/body_part_progress.dart';
import '../models/xp_event.dart';

/// Read-shape returned by the `character_state` view.
///
/// Computed server-side from `body_part_progress` excluding cardio (the v1
/// strength tracks only). The `record_set_xp` RPC and `backfill_rpg_v1`
/// procedure both update the underlying rows, so this view is always
/// consistent with the per-body-part state on the same read.
class CharacterState {
  const CharacterState({
    required this.userId,
    required this.characterLevel,
    required this.maxRank,
    required this.minRank,
    required this.lifetimeXp,
  });

  factory CharacterState.fromJson(Map<String, dynamic> json) => CharacterState(
    userId: requireField<String>(json, 'user_id'),
    characterLevel: requireInt(json, 'character_level'),
    maxRank: requireInt(json, 'max_rank'),
    minRank: requireInt(json, 'min_rank'),
    lifetimeXp: requireDouble(json, 'lifetime_xp'),
  );

  /// Default state for a brand-new user (no rows in `body_part_progress`).
  /// The view returns no rows for such a user, so the repository
  /// short-circuits to this constant rather than throwing.
  static const CharacterState empty = CharacterState(
    userId: '',
    characterLevel: 1,
    maxRank: 1,
    minRank: 1,
    lifetimeXp: 0,
  );

  final String userId;
  final int characterLevel;
  final int maxRank;
  final int minRank;
  final double lifetimeXp;
}

/// Read-only gateway for the Phase 18a RPG tables.
///
/// All writes happen server-side inside the `record_set_xp` RPC (called
/// transitively from `save_workout`) or the `backfill_rpg_v1` procedure.
/// The repository surface is read-only by design — there is no client-callable
/// "award XP" path: a set's XP is a deterministic function of the set's
/// `(weight, reps, exercise)` plus the user's prior peaks/sessions, and the
/// server is the single writer.
///
/// **Why no `recordSetXp(setId)` method here:** `save_workout` already calls
/// `record_set_xp` per inserted set in the same transaction. Exposing it in
/// Dart would invite double-awarding via misuse. The backfill driver
/// ([runBackfill]) is the only client-initiated write, and it's
/// idempotency-protected by the `(user_id, set_id)` UNIQUE INDEX.
class RpgRepository extends BaseRepository {
  RpgRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  // -------------------------------------------------------------------------
  // Per-body-part progress
  // -------------------------------------------------------------------------

  /// All body-part rows for the current user, including cardio when it has
  /// been touched. Returns an empty list for a brand-new user.
  ///
  /// Guarded by RLS — the SELECT policy on `body_part_progress` filters to
  /// `user_id = auth.uid()`, so callers don't need to pass the user id.
  Future<List<BodyPartProgress>> getAllBodyPartProgress() {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return const <BodyPartProgress>[];

      final rows = await _client
          .from('body_part_progress')
          .select()
          .order('body_part');

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(BodyPartProgress.fromJson)
          .toList(growable: false);
    });
  }

  /// Single body-part row, or `null` if the user has never trained that body
  /// part. UI can substitute a "rank 1, 0 XP" placeholder client-side.
  Future<BodyPartProgress?> getBodyPartProgress(BodyPart bodyPart) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final row = await _client
          .from('body_part_progress')
          .select()
          .eq('body_part', bodyPart.dbValue)
          .maybeSingle();

      if (row == null) return null;
      return BodyPartProgress.fromJson(row);
    });
  }

  // -------------------------------------------------------------------------
  // Character state (derived view)
  // -------------------------------------------------------------------------

  /// The roll-up view: character level, max/min rank, lifetime XP. Returns
  /// [CharacterState.empty] for a brand-new user (the view yields no rows
  /// when there are no body_part_progress entries).
  Future<CharacterState> getCharacterState() {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return CharacterState.empty;

      final row = await _client.from('character_state').select().maybeSingle();

      if (row == null) return CharacterState.empty;
      return CharacterState.fromJson(row);
    });
  }

  // -------------------------------------------------------------------------
  // XP events
  // -------------------------------------------------------------------------

  /// Most recent XP events for the current user, newest first.
  ///
  /// Used by the saga screen replay (Phase 18c) and audit/debug surfaces.
  /// Limit defaults to 50 — consumers that need more should paginate via
  /// [olderThan] (cursor on `occurred_at`).
  Future<List<XpEvent>> getRecentXpEvents({
    int limit = 50,
    DateTime? olderThan,
  }) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return const <XpEvent>[];

      var query = _client.from('xp_events').select();
      if (olderThan != null) {
        query = query.lt('occurred_at', olderThan.toIso8601String());
      }
      final rows = await query
          .order('occurred_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(XpEvent.fromJson)
          .toList(growable: false);
    });
  }

  /// XP events for a single workout session, ordered chronologically.
  ///
  /// Drives the post-workout celebration replay (Phase 18c) — the sequence
  /// of body-part XP awards within a saved workout, in the order the sets
  /// were performed.
  Future<List<XpEvent>> getXpEventsForSession(String sessionId) {
    return mapException(() async {
      final rows = await _client
          .from('xp_events')
          .select()
          .eq('session_id', sessionId)
          .order('occurred_at');

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(XpEvent.fromJson)
          .toList(growable: false);
    });
  }

  // -------------------------------------------------------------------------
  // Peak load per body part (Phase 27 L10)
  // -------------------------------------------------------------------------

  /// Heaviest single-set weight (kg) lifted per body part within the window
  /// `(endDate - days, endDate]`. Returns one entry per body part with at
  /// least one non-zero-weight set in the window; absent body parts mean
  /// the user has not trained that body part with weight in the window.
  ///
  /// Uses the `peak_load_per_body_part(p_user_id, p_days, p_end_date)` RPC
  /// (migration 00064). Powers the post-Phase-27 "Carga pico" column on
  /// the stats deep-dive screen, replacing the pre-Phase-27
  /// EWMA-rendered-as-kg mislabel.
  ///
  /// **Attribution rule.** A set counts toward body part X iff the parent
  /// exercise's `xp_attribution -> X` is strictly positive. This matches
  /// the existing weekly-volume "any non-zero attribution counts" rule.
  ///
  /// Returns an empty map for an unauthenticated client (mirrors the
  /// repository's other guards).
  Future<Map<BodyPart, double>> getPeakLoadPerBodyPart({
    required int days,
    DateTime? endDate,
  }) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return const <BodyPart, double>{};

      final params = <String, dynamic>{'p_user_id': user.id, 'p_days': days};
      if (endDate != null) {
        params['p_end_date'] = endDate.toUtc().toIso8601String();
      }
      final raw = await _client.rpc('peak_load_per_body_part', params: params);

      // PostgREST serializes `RETURNS TABLE` as a List<Map>. Skip rows
      // with unknown body-part tokens defensively — a future cardio peak
      // entry would arrive here before the UI is ready for it.
      final rows = (raw as List).cast<Map<String, dynamic>>();
      final out = <BodyPart, double>{};
      for (final row in rows) {
        final token = row['body_part'] as String?;
        final weight = row['peak_load_kg'];
        if (token == null || weight == null) continue;
        final bp = BodyPart.tryFromDbValue(token);
        if (bp == null) continue;
        out[bp] = (weight as num).toDouble();
      }
      return out;
    });
  }

  // -------------------------------------------------------------------------
  // Backfill driver
  // -------------------------------------------------------------------------

  /// Run the chunked retroactive backfill for the current user.
  ///
  /// **Architecture (the chunking model):** the SQL `backfill_rpg_v1`
  /// function processes ONE chunk per invocation and returns
  /// `(processed, total_processed, is_complete)`. This Dart driver loops
  /// over it until `is_complete = true`. Each invocation is its own PG
  /// transaction (PostgREST wraps every RPC call in a txn), so when the
  /// call returns, the chunk has committed durably.
  ///
  /// Why a client-side loop instead of a server-side one? Postgres
  /// forbids `COMMIT` inside a SECURITY DEFINER procedure, and PostgREST
  /// always invokes RPCs inside an implicit transaction — so a procedure
  /// with internal chunked commits would fail with "invalid transaction
  /// termination". Inverting the loop into the client preserves all the
  /// chunking + advisory-lock + checkpoint semantics without that
  /// restriction.
  ///
  /// Per-chunk semantics on the server:
  ///   * Acquires `pg_advisory_xact_lock` keyed on the user id (per-user
  ///     serialization — concurrent calls for the same user block until
  ///     the active chunk finishes).
  ///   * Wipes prior `xp_events` / `body_part_progress` /
  ///     `exercise_peak_loads` rows for this user on the FIRST chunk
  ///     only (`sets_processed = 0`).
  ///   * Replays up to 500 sets in chronological order, computing XP
  ///     against the v1 formula.
  ///   * Skips already-processed sets via the
  ///     `xp_events(user_id, set_id)` UNIQUE INDEX
  ///     (idempotency-via-comparison, not via-flag).
  ///   * Marks `backfill_progress.completed_at` when the chunk
  ///     underflows (no more sets to process).
  ///
  /// Resume-after-kill: if this driver is killed mid-loop, the cursor on
  /// `backfill_progress` is durable. The next call resumes from wherever
  /// the last committed chunk left off.
  ///
  /// Returns the total number of sets processed across all chunks.
  /// Throws [DatabaseException] on PG-side failures — callers should
  /// treat the operation as retriable and surface a "we'll try again"
  /// message rather than blocking the user on it.
  ///
  /// [chunkSize] is exposed for tests; production callers should leave
  /// it at the default of 500 (matches the spec's tuning target).
  Future<int> runBackfill({int chunkSize = 500}) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const AuthException('Not authenticated', code: 'no_session');
      }

      var totalProcessed = 0;
      // Hard cap on iterations to prevent a runaway loop in the face of
      // a server-side bug. 5000 chunks × 500 sets = 2.5M sets, far above
      // any plausible single-user history.
      const maxIterations = 5000;
      for (var i = 0; i < maxIterations; i++) {
        final result = await _client.rpc(
          'backfill_rpg_v1',
          params: {'p_user_id': user.id, 'p_chunk_size': chunkSize},
        );
        final row = _firstRow(result);
        final isComplete = optionalField<bool>(row, 'out_is_complete') ?? false;
        final processedRaw = optionalField<num>(row, 'out_total_processed');
        totalProcessed = processedRaw?.toInt() ?? 0;
        if (isComplete) {
          return totalProcessed;
        }
      }
      // Defensive — should never hit this for a real user.
      throw const DatabaseException(
        'backfill_rpg_v1 did not converge',
        code: 'backfill_runaway',
      );
    });
  }

  /// Extracts the first row from a PostgREST RPC result that returns a
  /// `RETURNS TABLE` shape. PostgREST serializes such results as a list
  /// of maps even when the function returns a single row.
  Map<String, dynamic> _firstRow(dynamic result) {
    if (result is List && result.isNotEmpty) {
      final first = result.first;
      if (first is! Map) {
        throw const DatabaseException(
          'backfill_rpg_v1 returned a non-Map row',
          code: 'json_wrong_type',
        );
      }
      return Map<String, dynamic>.from(first);
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw const DatabaseException(
      'backfill_rpg_v1 returned an unexpected payload',
      code: 'backfill_bad_payload',
    );
  }

  /// Read the backfill checkpoint row, or null if backfill has never been
  /// invoked for this user. UI uses `completed_at` to decide whether to
  /// show "syncing your saga..." messaging.
  Future<BackfillProgress?> getBackfillProgress() {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final row = await _client
          .from('backfill_progress')
          .select()
          .maybeSingle();

      if (row == null) return null;
      return BackfillProgress.fromJson(row);
    });
  }
}

/// Lightweight value class for the `backfill_progress` checkpoint table.
///
/// Not Freezed because the table is internal to the migration/backfill flow
/// (no UI rebuilds key off it) and the structure is unlikely to evolve.
class BackfillProgress {
  const BackfillProgress({
    required this.userId,
    this.lastSetId,
    this.lastSetTs,
    required this.setsProcessed,
    required this.startedAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory BackfillProgress.fromJson(Map<String, dynamic> json) {
    return BackfillProgress(
      userId: requireField<String>(json, 'user_id'),
      lastSetId: optionalField<String>(json, 'last_set_id'),
      lastSetTs: optionalDateTime(json, 'last_set_ts'),
      setsProcessed: requireInt(json, 'sets_processed'),
      startedAt: requireDateTime(json, 'started_at'),
      updatedAt: requireDateTime(json, 'updated_at'),
      completedAt: optionalDateTime(json, 'completed_at'),
    );
  }

  final String userId;
  final String? lastSetId;
  final DateTime? lastSetTs;
  final int setsProcessed;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isComplete => completedAt != null;
}
