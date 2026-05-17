import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../../../core/data/json_helpers.dart';
import '../models/body_part.dart';
import '../models/title.dart';

/// Body-part catalog asset path. The legacy (Phase 18c) v1 catalog —
/// 78 entries, every entry implicitly `kind: body_part`. The loader injects
/// `kind: body_part` per entry before calling [Title.fromJson] for backward
/// compat with the original schema.
const String kTitlesCatalogAsset = 'assets/rpg/titles_v1.json';

/// Character-level catalog asset path (Phase 18e). Seven entries spanning
/// character levels 10..148. Every entry MUST include `"kind": "character_level"`
/// in the JSON envelope.
const String kCharacterLevelTitlesCatalogAsset =
    'assets/rpg/titles_character_level.json';

/// Cross-build catalog asset path (Phase 18e). Five entries — one per
/// trigger predicate in [CrossBuildTitleEvaluator]. Every entry MUST include
/// `"kind": "cross_build"` in the JSON envelope.
const String kCrossBuildTitlesCatalogAsset =
    'assets/rpg/titles_cross_build.json';

/// Read-shape returned by `earned_titles` SELECT. Lightweight value class
/// (not Freezed) — the table only ever produces this exact shape and the UI
/// consumes [Title] for display, not this row directly.
class EarnedTitleRow {
  const EarnedTitleRow({
    required this.userId,
    required this.titleId,
    required this.earnedAt,
    required this.isActive,
  });

  factory EarnedTitleRow.fromJson(Map<String, dynamic> json) {
    return EarnedTitleRow(
      userId: requireField<String>(json, 'user_id'),
      titleId: requireField<String>(json, 'title_id'),
      earnedAt: requireDateTime(json, 'earned_at'),
      // `is_active` is NOT NULL with default `false` in the schema; treat
      // missing/null as `false` and let a wrong-type drift surface via
      // `optionalField`'s typed exception.
      isActive: optionalField<bool>(json, 'is_active') ?? false,
    );
  }

  final String userId;
  final String titleId;
  final DateTime earnedAt;
  final bool isActive;
}

/// Repository for the title catalog (asset) and the user's earned titles
/// (`earned_titles` table).
///
/// **Catalog vs earned-titles split:**
///   * The catalog is immutable shipped JSON — slug + body part + rank
///     threshold per entry. Display copy lives in `app_*.arb` keyed by slug.
///     Loaded lazily and cached in-process.
///   * Earned-titles are per-user rows persisted in Postgres. The
///     `record_set_xp` RPC inserts rows server-side when a rank threshold
///     is crossed (Phase 18a wiring). The client SELECTs them; equip toggle
///     UPDATEs `is_active` (UNIQUE INDEX `earned_titles_one_active` enforces
///     the at-most-one invariant).
///
/// **Why no `insertEarnedTitle` here:** v1 wires title persistence
/// server-side inside `record_set_xp`. Exposing a client INSERT path would
/// invite double-awarding on retried saves. The detector's purpose is to
/// drive the *celebration overlay* — the durable record was already written
/// by the time `record_set_xp` returned its deltas.
class TitlesRepository extends BaseRepository {
  TitlesRepository(
    supabase.SupabaseClient client, {
    AssetBundle? bundle,
    super.recoveryRecorder,
  }) : _client = client,
       _bundle = bundle ?? rootBundle;

  /// Test-only factory that constructs a repository wired ONLY to the asset
  /// bundle (no Supabase client). The unit tests for the threshold-table
  /// integrity assertion use this to read the JSON catalog without a Supabase
  /// connection. The Supabase-dependent methods will throw [StateError] if
  /// called against this instance.
  @visibleForTesting
  factory TitlesRepository.forAssetBundleOnly({AssetBundle? bundle}) {
    return TitlesRepository(_ThrowingSupabaseClient(), bundle: bundle);
  }

  final supabase.SupabaseClient _client;
  final AssetBundle _bundle;

  /// In-process cache. Populated on first [loadCatalog] call and reused for
  /// the rest of the app lifetime — the catalog never mutates at runtime.
  static List<Title>? _catalogCache;

  /// Visible-for-test reset hook. Production code never calls this — the
  /// `@visibleForTesting` annotation keeps it out of IDE autocomplete in
  /// app code while staying available to widget/unit tests that need a
  /// fresh asset read between cases.
  @visibleForTesting
  static void debugResetCatalogCache() {
    _catalogCache = null;
  }

  // ---------------------------------------------------------------------------
  // Catalog
  // ---------------------------------------------------------------------------

  /// Load the merged v1 title catalog (90 entries: 78 body-part + 7
  /// character-level + 5 cross-build) from the shipped assets. Cached after
  /// the first call. Throws [FlutterError] from `rootBundle` if any asset
  /// is missing — that would be a build-time bug (catalog not in pubspec.yaml).
  ///
  /// **Schema dispatch.** Every entry deserializes through [Title.fromJson]
  /// which discriminates on the `kind` field. The legacy `titles_v1.json`
  /// predates the discriminator (Phase 18c); the loader injects
  /// `"kind": "body_part"` per entry before deserialization. New catalogs
  /// (`titles_character_level.json`, `titles_cross_build.json`) carry the
  /// `kind` field explicitly.
  ///
  /// **Why a single merged list:** consumers (titles screen, detector,
  /// celebration overlay) operate on the union shape and pattern-match per
  /// variant. Splitting into three lists would force every consumer to know
  /// about the storage layout. The catalog cache is process-scoped so the
  /// merge cost is paid exactly once.
  Future<List<Title>> loadCatalog() async {
    final cached = _catalogCache;
    if (cached != null) return cached;

    final entries = <Title>[
      ..._loadBodyPart(await _bundle.loadString(kTitlesCatalogAsset)),
      ..._loadDiscriminated(
        await _bundle.loadString(kCharacterLevelTitlesCatalogAsset),
      ),
      ..._loadDiscriminated(
        await _bundle.loadString(kCrossBuildTitlesCatalogAsset),
      ),
    ];

    _catalogCache = List<Title>.unmodifiable(entries);
    return _catalogCache!;
  }

  /// Legacy v1 catalog loader. Each entry is `(slug, body_part,
  /// rank_threshold)` without a `kind` field; we inject `body_part` so
  /// [Title.fromJson] dispatches to [BodyPartTitle.fromJson]. Adding `kind`
  /// to the JSON file would also work but rewriting the asset is a lossy
  /// editorial change — keeping the asset stable means git blame on a
  /// title's slug stays meaningful.
  static Iterable<Title> _loadBodyPart(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['titles'] as List).cast<Map<String, dynamic>>();
    return list.map((entry) {
      // Defensive: don't mutate the caller's map (the asset bundle gives us
      // a fresh decode per call so it's safe in practice, but copying keeps
      // the loader honest under future caching changes).
      final withKind = <String, dynamic>{'kind': 'body_part', ...entry};
      return Title.fromJson(withKind);
    });
  }

  /// Discriminated catalog loader (character-level, cross-build). Each entry
  /// already carries `kind` per the Phase 18e schema; we just defer to
  /// [Title.fromJson] which routes to the right factory.
  static Iterable<Title> _loadDiscriminated(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['titles'] as List).cast<Map<String, dynamic>>();
    return list.map(Title.fromJson);
  }

  /// Lookup a single catalog entry by slug across every variant. Returns
  /// null if the slug is unknown — the caller decides whether that's a
  /// data-integrity error (server returned a slug we don't ship) or a
  /// graceful fallback (UI reading a row from a future catalog version).
  Future<Title?> lookupBySlug(String slug) async {
    final catalog = await loadCatalog();
    for (final t in catalog) {
      if (t.slug == slug) return t;
    }
    return null;
  }

  /// All body-part catalog entries for [bodyPart], ascending by
  /// `rankThreshold`. The titles screen renders one section per body part
  /// using this.
  ///
  /// Filters to [BodyPartTitle] — character-level and cross-build entries
  /// don't have a body part and are surfaced via separate sections on the
  /// titles screen.
  Future<List<Title>> forBodyPart(BodyPart bodyPart) async {
    final catalog = await loadCatalog();
    final filtered =
        catalog
            .whereType<BodyPartTitle>()
            .where((t) => t.bodyPart == bodyPart)
            .toList()
          ..sort((a, b) => a.rankThreshold.compareTo(b.rankThreshold));
    return filtered;
  }

  // ---------------------------------------------------------------------------
  // Earned titles (Postgres)
  // ---------------------------------------------------------------------------

  /// All earned-title rows for the current user. Ordered by `earned_at`
  /// ascending so the titles screen can render in unlock chronology.
  /// Returns an empty list for an unauthenticated session.
  Future<List<EarnedTitleRow>> getEarnedTitles() {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return const <EarnedTitleRow>[];

      final rows = await _client
          .from('earned_titles')
          .select()
          .order('earned_at');

      // supabase_flutter v2 already types `select()` as `List<Map<String,
      // dynamic>>` — no `as List` cast needed.
      return rows.map(EarnedTitleRow.fromJson).toList(growable: false);
    });
  }

  /// Currently equipped title slug, or null if none equipped. Read off the
  /// UNIQUE INDEX-protected `is_active = true` row.
  Future<String?> getActiveTitleSlug() {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final row = await _client
          .from('earned_titles')
          .select('title_id')
          .eq('is_active', true)
          .maybeSingle();

      if (row == null) return null;
      return requireField<String>(row, 'title_id');
    });
  }

  /// Equip a title. Clears any prior `is_active = true` row, then upserts the
  /// new row — INSERT if the title has never been equipped/earned, UPDATE if it
  /// already has a row. The UNIQUE INDEX `earned_titles_one_active` enforces the
  /// at-most-one-active invariant across both the clear and the upsert.
  ///
  /// **Why UPSERT instead of plain UPDATE:** Phase 18a planned server-side
  /// title-row creation inside `record_set_xp`, but that code path was never
  /// implemented (migration 00041 adds the INSERT RLS policy that makes this
  /// safe). The first time a user equips a title from the celebration overlay
  /// there is no pre-existing `earned_titles` row — the UPSERT creates it.
  ///
  /// **Race safety:** a concurrent equip from another device would surface a
  /// `23505` from the UPSERT's ON CONFLICT clause if two INSERTs race on the
  /// same primary key, which `mapException` translates to [DatabaseException].
  /// The UNIQUE INDEX is the real safety net; the two-statement implementation
  /// is the v1 approach pending a server-side `equip_title(title_id)` RPC
  /// (Phase 18d).
  Future<void> equipTitle(String slug) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return;

      // Clear any current active flag (no-op if there isn't one).
      await _client
          .from('earned_titles')
          .update({'is_active': false})
          .eq('user_id', user.id)
          .eq('is_active', true);

      // Upsert the new active row. INSERT if no row exists for this title yet
      // (first equip from the celebration overlay), UPDATE otherwise.
      await _client.from('earned_titles').upsert({
        'user_id': user.id,
        'title_id': slug,
        'is_active': true,
      }, onConflict: 'user_id,title_id');
    });
  }

  /// Unequip the currently active title (if any). Used by the character
  /// sheet's "remove title" affordance — keeps the lifetime unlock log
  /// intact while clearing the equipped state.
  Future<void> unequipActiveTitle() {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return;

      await _client
          .from('earned_titles')
          .update({'is_active': false})
          .eq('user_id', user.id)
          .eq('is_active', true);
    });
  }
}

/// Throwing stub used by [TitlesRepository.forAssetBundleOnly]. Any method
/// invocation surfaces a [StateError] — tests using the asset-only factory
/// must not exercise Supabase code paths. We cannot use a real
/// `SupabaseClient` here because instantiating one requires a URL + anon key
/// and would attempt network setup at construction time.
class _ThrowingSupabaseClient implements supabase.SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'TitlesRepository.forAssetBundleOnly: Supabase methods are not available',
  );
}
