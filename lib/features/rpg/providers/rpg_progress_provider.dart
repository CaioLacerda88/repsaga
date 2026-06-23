import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../data/peak_loads_repository.dart';
import '../data/rpg_repository.dart';
import '../models/body_part.dart';
import '../models/body_part_progress.dart';

// ---------------------------------------------------------------------------
// DI seams
// ---------------------------------------------------------------------------

/// Single instance of the RPG repository.
final rpgRepositoryProvider = Provider<RpgRepository>((ref) {
  return RpgRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Single instance of the peak-loads repository.
final peakLoadsRepositoryProvider = Provider<PeakLoadsRepository>((ref) {
  return PeakLoadsRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

// ---------------------------------------------------------------------------
// UI-shaped roll-up
// ---------------------------------------------------------------------------

/// Combined snapshot the saga screen consumes:
///   * One row per active body part (filled in with rank-1/0-XP placeholders
///     for tracks the user hasn't touched yet so the UI can render six tiles
///     unconditionally).
///   * The derived [CharacterState] view roll-up.
///
/// Cardio is intentionally returned in [byBodyPart] when present (so a future
/// 18b cardio surface can read it via the same provider) but excluded from
/// [activeProgress], which only emits the six v1 strength tracks in the
/// canonical [activeBodyParts] order.
class RpgProgressSnapshot {
  const RpgProgressSnapshot({
    required this.byBodyPart,
    required this.characterState,
  });

  /// Empty roll-up for unauthenticated/loading states. Every active body
  /// part is at rank 1, 0 XP — matches the SQL default-row shape.
  static const RpgProgressSnapshot empty = RpgProgressSnapshot(
    byBodyPart: <BodyPart, BodyPartProgress>{},
    characterState: CharacterState.empty,
  );

  /// Body part → progress row. Only contains rows that exist server-side
  /// — body parts a user has never trained are absent. Use [progressFor]
  /// to read with placeholder fallback.
  final Map<BodyPart, BodyPartProgress> byBodyPart;

  /// Roll-up from the `character_state` view.
  final CharacterState characterState;

  /// Rows for the six v1 strength tracks in canonical [activeBodyParts]
  /// order, with placeholder rows substituted for tracks that have no
  /// server row yet. The saga screen iterates this list directly.
  List<BodyPartProgress> get activeProgress {
    return activeBodyParts.map(progressFor).toList(growable: false);
  }

  /// Read the row for [bodyPart], substituting a "fresh user" placeholder
  /// (rank 1, 0 XP) when the server has no row. The `userId` field on the
  /// placeholder is empty — UI must not echo it back.
  BodyPartProgress progressFor(BodyPart bodyPart) {
    final existing = byBodyPart[bodyPart];
    if (existing != null) return existing;
    return BodyPartProgress(
      userId: '',
      bodyPart: bodyPart,
      totalXp: 0,
      rank: 1,
      vitalityEwma: 0,
      vitalityPeak: 0,
      vitalityRefPeak: 0,
      lastEventAt: null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

// ---------------------------------------------------------------------------
// AsyncNotifier — the saga screen's data root
// ---------------------------------------------------------------------------

/// Per-user snapshot of RPG state (per-body-part progress + character roll-up).
///
/// Two consumers in v1:
///   * Phase 18b: home/saga LVL line + per-body-part rank chips.
///   * Phase 18c: post-workout celebration screen reads
///     [RpgProgressNotifier.refreshAfterSave] to render the rank-up
///     overlay against fresh state.
///
/// Writes happen server-side (via `save_workout` → `record_set_xp`). After a
/// workout save, callers MUST invoke [refreshAfterSave] so the watching UI
/// rebuilds against the new server snapshot.
final rpgProgressProvider =
    AsyncNotifierProvider<RpgProgressNotifier, RpgProgressSnapshot>(
      RpgProgressNotifier.new,
    );

class RpgProgressNotifier extends AsyncNotifier<RpgProgressSnapshot> {
  RpgRepository get _repo => ref.read(rpgRepositoryProvider);

  @override
  Future<RpgProgressSnapshot> build() async {
    return _load();
  }

  Future<RpgProgressSnapshot> _load() async {
    final rows = await _repo.getAllBodyPartProgress();
    final characterState = await _repo.getCharacterState();

    final map = <BodyPart, BodyPartProgress>{
      for (final row in rows) row.bodyPart: row,
    };
    return RpgProgressSnapshot(byBodyPart: map, characterState: characterState);
  }

  /// Re-fetch the snapshot from the server. Called by the workout save flow
  /// after `save_workout` returns — the RPC writes happen inside the same
  /// transaction so by the time it returns, the new state is durable.
  ///
  /// Returns the freshly-fetched snapshot directly so callers can use it
  /// without racing against any concurrent in-flight [build] that might
  /// overwrite [state] with pre-save data after this method returns.
  ///
  /// Idempotent: calling twice with no intervening writes produces the
  /// same snapshot. Idempotency-via-comparison: callers don't need a
  /// guard flag.
  Future<RpgProgressSnapshot> refreshAfterSave() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(_load);
    state = result;
    return result.value ?? RpgProgressSnapshot.empty;
  }

  /// Driver for the migration-scheduled retroactive backfill. Called once
  /// per user post-deploy from the app-startup gate (Phase 18b adds the
  /// gate; v1 ships only the server side).
  ///
  /// On success, invalidates self so the UI picks up the new rows.
  Future<void> runBackfill() async {
    await _repo.runBackfill();
    ref.invalidateSelf();
  }
}
