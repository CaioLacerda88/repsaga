// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import 'body_part.dart';

part 'title.freezed.dart';
part 'title.g.dart';

/// A title catalog entry.
///
/// **Why a sealed Freezed union (Phase 18e):** v1 ships three structurally
/// different title kinds — per-body-part (78 entries), character-level (7),
/// cross-build (5) — and each kind has a different "trigger metadata" shape.
/// A sealed union surfaces that distinction in the type system: every consumer
/// of [Title] is forced (by exhaustive `switch`) to handle each variant or
/// explicitly opt out. A single nullable-everything record would let a future
/// contributor silently drop the new variants on the floor at the title
/// detector or the titles-screen filter.
///
/// **Why `slug` is on the base:** slug is the forever-stable join key with
/// `earned_titles.title_id` in Postgres. Editorial revisions to display copy
/// ship by editing the `.arb` files — never by renaming a slug. Keeping
/// `slug` on the base makes "look up by slug across every catalog" a
/// trivial linear scan rather than a per-variant filter.
///
/// **Display copy is NOT on this model.** `name` and `flavor` resolve through
/// `AppLocalizations` keyed by [slug]:
///   * `title_{slug}_name`
///   * `title_{slug}_flavor`
///
/// This keeps the catalog pt-BR coverage in `app_pt.arb` (Brazilian gym voice,
/// not literal translation) and the structural data in the shipped JSON
/// catalogs (`titles_v1.json`, `titles_character_level.json`,
/// `titles_cross_build.json`).
///
/// **JSON envelope:** every catalog entry carries a `kind` discriminator
/// (`body_part`, `character_level`, `cross_build`) that drives Freezed's
/// auto-generated [fromJson]. The legacy (Phase 18c) `titles_v1.json` predates
/// the discriminator and is loaded via [TitlesRepository.loadCatalog] which
/// injects `"kind": "body_part"` per entry before deserialization for backward
/// compat. New catalogs always include the field.
@Freezed(unionKey: 'kind', unionValueCase: FreezedUnionCase.snake)
sealed class Title with _$Title {
  /// Per-body-part ladder entry (78 entries, every 5 ranks per body part).
  ///
  /// `(slug, body_part, rank_threshold)` is stable forever — renaming or
  /// re-thresholding a title would orphan everyone who unlocked it.
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Title.bodyPart({
    required String slug,
    required BodyPart bodyPart,
    required int rankThreshold,
  }) = BodyPartTitle;

  /// Character-level title (7 entries: lvl 10, 25, 50, 75, 100, 125, 148).
  ///
  /// Awarded when [characterLevel] crosses [levelThreshold] in the half-open
  /// interval `(oldLevel, newLevel]` — same boundary semantics as the
  /// per-body-part ladder, applied to character level instead of body-part
  /// rank.
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Title.characterLevel({
    required String slug,
    required int levelThreshold,
  }) = CharacterLevelTitle;

  /// Cross-build distinction title (5 entries: Pillar-Walker, Broad-Shouldered,
  /// Even-Handed, Iron-Bound, Saga-Forged). Awarded when the user's full rank
  /// distribution satisfies a structural predicate (spec §10.3).
  ///
  /// The actual predicate lives in
  /// [`CrossBuildTitleEvaluator`](../domain/cross_build_title_evaluator.dart) —
  /// JSON cannot express the AND/OR/threshold logic cleanly, so the catalog
  /// only stores the [triggerId] as the bridge between the slug and the Dart
  /// predicate. This keeps editorial control of which cross-build titles are
  /// active in the JSON (you can disable a slug by deleting it from the
  /// catalog without code changes), while the predicate evolution stays in
  /// version-controlled Dart.
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Title.crossBuild({
    required String slug,
    required CrossBuildTriggerId triggerId,
  }) = CrossBuildTitle;

  factory Title.fromJson(Map<String, dynamic> json) => _$TitleFromJson(json);
}

/// Identifier for the five cross-build trigger predicates (spec §10.3).
///
/// **Why an enum and not a free-form string:** the JSON catalog drives this
/// value; a typo there would silently drop a title from detection. An enum
/// gives us a compile-time round-trip — the loader rejects unknown tokens
/// at parse time, and every consumer of [CrossBuildTitle.triggerId] is
/// forced (by exhaustive switch) to handle every variant.
///
/// Token mapping (snake_case for JSON parity):
///   * `pillar_walker` — Legs >= 40 AND Legs >= 2x Arms
///   * `broad_shouldered` — Chest+Back+Shoulders >= 2x(Legs+Core), all upper >= 30
///   * `even_handed` — All 6 within 30% of max at Rank 30+
///   * `iron_bound` — Chest >= 60 AND Back >= 60 AND Legs >= 60 AND cardio <= 10
///     (Phase 38f tightened the predicate with a low-cardio condition — future
///     awards only; already-earned `iron_bound` rows are never revoked)
///   * `saga_forged` — All 6 ranks >= 60
///   * `the_forged_wind` — All 6 strength ranks >= 60 AND cardio >= 60 (38f)
///   * `storm_tempered` — Cardio >= 60 AND all 6 strength ranks >= 30 (38f)
@JsonEnum(fieldRename: FieldRename.snake)
enum CrossBuildTriggerId {
  pillarWalker,
  broadShouldered,
  evenHanded,
  ironBound,
  sagaForged,
  theForgedWind,
  stormTempered;

  /// Token used in JSON catalogs and (when needed) the SQL backfill payload.
  /// snake_case to mirror the body-part dbValues and `earned_titles.title_id`
  /// slug conventions.
  String get dbValue => switch (this) {
    CrossBuildTriggerId.pillarWalker => 'pillar_walker',
    CrossBuildTriggerId.broadShouldered => 'broad_shouldered',
    CrossBuildTriggerId.evenHanded => 'even_handed',
    CrossBuildTriggerId.ironBound => 'iron_bound',
    CrossBuildTriggerId.sagaForged => 'saga_forged',
    CrossBuildTriggerId.theForgedWind => 'the_forged_wind',
    CrossBuildTriggerId.stormTempered => 'storm_tempered',
  };

  /// Reverse lookup. Throws on unknown tokens — a JSON typo is a build-time
  /// catalog bug, not a graceful-fallback case.
  static CrossBuildTriggerId fromDbValue(String value) {
    for (final id in CrossBuildTriggerId.values) {
      if (id.dbValue == value) return id;
    }
    throw ArgumentError.value(
      value,
      'CrossBuildTriggerId.dbValue',
      'unknown trigger token',
    );
  }
}
