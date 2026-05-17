import '../models/body_part.dart';

/// Discriminator for the three title kinds in [TitleThresholdsTable].
enum TitleThresholdKind { bodyPart, characterLevel, crossBuild }

/// Single row in the canonical Dart-side title threshold table.
///
/// * [slug] is the join key shared with `earned_titles.title_id`, the JSON
///   catalog files, and the SQL `title_catalog_v1` VALUES list embedded
///   inside the XP RPCs.
/// * [kind] selects which other fields are populated:
///     - [TitleThresholdKind.bodyPart] → [bodyPart] + [threshold] (rank).
///     - [TitleThresholdKind.characterLevel] → [threshold] (level), [bodyPart] null.
///     - [TitleThresholdKind.crossBuild] → both null; predicate lives in
///       `cross_build_title_evaluator.dart`.
class TitleThresholdEntry {
  const TitleThresholdEntry({
    required this.slug,
    required this.kind,
    this.bodyPart,
    this.threshold,
  });

  final String slug;
  final TitleThresholdKind kind;
  final BodyPart? bodyPart;
  final int? threshold;
}

/// Canonical Dart-side mirror of the v1 title catalog (90 entries:
/// 78 body-part + 7 character-level + 5 cross-build).
///
/// This table is the source of truth the XP RPC migrations reflect into the
/// `title_catalog_v1` VALUES list embedded inside `record_set_xp` and
/// `record_session_xp_batch`. The integrity test in
/// `test/unit/features/rpg/data/title_thresholds_table_test.dart` fails the
/// suite if this table and the JSON catalog (`assets/rpg/titles_*.json`)
/// drift apart row-for-row.
///
/// **Ordering:** entries are sorted by slug ascending within each kind block
/// so the table hashes deterministically across machines.
abstract final class TitleThresholdsTable {
  static const List<TitleThresholdEntry> all = [
    // ─── Body-part (78 entries, sorted by slug) ───────────────────────────
    TitleThresholdEntry(
      slug: 'arms_r10_iron_fingered',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 10,
    ),
    TitleThresholdEntry(
      slug: 'arms_r15_sinew_drawn',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 15,
    ),
    TitleThresholdEntry(
      slug: 'arms_r20_marrow_cleaver',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 20,
    ),
    TitleThresholdEntry(
      slug: 'arms_r25_steel_sleeved',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'arms_r30_sinew_sworn',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 30,
    ),
    TitleThresholdEntry(
      slug: 'arms_r40_iron_knuckled',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 40,
    ),
    TitleThresholdEntry(
      slug: 'arms_r50_steel_forged',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'arms_r5_vein_stirrer',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 5,
    ),
    TitleThresholdEntry(
      slug: 'arms_r60_sinew_bound',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 60,
    ),
    TitleThresholdEntry(
      slug: 'arms_r70_iron_sleeved',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 70,
    ),
    TitleThresholdEntry(
      slug: 'arms_r80_sinew_of_storms',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 80,
    ),
    TitleThresholdEntry(
      slug: 'arms_r90_iron_untouched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 90,
    ),
    TitleThresholdEntry(
      slug: 'arms_r99_the_sinew',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.arms,
      threshold: 99,
    ),
    TitleThresholdEntry(
      slug: 'back_r10_wing_marked',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 10,
    ),
    TitleThresholdEntry(
      slug: 'back_r15_rope_hauler',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 15,
    ),
    TitleThresholdEntry(
      slug: 'back_r20_lat_crowned',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 20,
    ),
    TitleThresholdEntry(
      slug: 'back_r25_talon_backed',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'back_r30_wing_spread',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 30,
    ),
    TitleThresholdEntry(
      slug: 'back_r40_lattice_hauled',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 40,
    ),
    TitleThresholdEntry(
      slug: 'back_r50_wing_crowned',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'back_r5_lattice_touched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 5,
    ),
    TitleThresholdEntry(
      slug: 'back_r60_lattice_spread',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 60,
    ),
    TitleThresholdEntry(
      slug: 'back_r70_wing_storm',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 70,
    ),
    TitleThresholdEntry(
      slug: 'back_r80_wing_of_storms',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 80,
    ),
    TitleThresholdEntry(
      slug: 'back_r90_sky_lattice',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 90,
    ),
    TitleThresholdEntry(
      slug: 'back_r99_the_lattice',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.back,
      threshold: 99,
    ),
    TitleThresholdEntry(
      slug: 'chest_r10_plate_bearer',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 10,
    ),
    TitleThresholdEntry(
      slug: 'chest_r15_forge_marked',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 15,
    ),
    TitleThresholdEntry(
      slug: 'chest_r20_iron_chested',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 20,
    ),
    TitleThresholdEntry(
      slug: 'chest_r25_anvil_heart',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'chest_r30_forge_born',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 30,
    ),
    TitleThresholdEntry(
      slug: 'chest_r40_bulwark_chested',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 40,
    ),
    TitleThresholdEntry(
      slug: 'chest_r50_forge_plated',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'chest_r5_initiate_of_the_forge',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 5,
    ),
    TitleThresholdEntry(
      slug: 'chest_r60_anvil_forged',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 60,
    ),
    TitleThresholdEntry(
      slug: 'chest_r70_forge_heart',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 70,
    ),
    TitleThresholdEntry(
      slug: 'chest_r80_heart_of_forge',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 80,
    ),
    TitleThresholdEntry(
      slug: 'chest_r90_forge_untouched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 90,
    ),
    TitleThresholdEntry(
      slug: 'chest_r99_the_anvil',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 99,
    ),
    TitleThresholdEntry(
      slug: 'core_r10_core_forged',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 10,
    ),
    TitleThresholdEntry(
      slug: 'core_r15_pillar_spined',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 15,
    ),
    TitleThresholdEntry(
      slug: 'core_r20_iron_belted',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 20,
    ),
    TitleThresholdEntry(
      slug: 'core_r25_stonewall',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'core_r30_diamond_spine',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 30,
    ),
    TitleThresholdEntry(
      slug: 'core_r40_anchor_belted',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 40,
    ),
    TitleThresholdEntry(
      slug: 'core_r50_stone_cored',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'core_r5_spine_tested',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 5,
    ),
    TitleThresholdEntry(
      slug: 'core_r60_marrow_carved',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 60,
    ),
    TitleThresholdEntry(
      slug: 'core_r70_stone_spined',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 70,
    ),
    TitleThresholdEntry(
      slug: 'core_r80_spine_of_storms',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 80,
    ),
    TitleThresholdEntry(
      slug: 'core_r90_marrow_untouched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 90,
    ),
    TitleThresholdEntry(
      slug: 'core_r99_the_spine',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.core,
      threshold: 99,
    ),
    TitleThresholdEntry(
      slug: 'legs_r10_stone_stepper',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 10,
    ),
    TitleThresholdEntry(
      slug: 'legs_r15_pillar_apprentice',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 15,
    ),
    TitleThresholdEntry(
      slug: 'legs_r20_pillar_walker',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 20,
    ),
    TitleThresholdEntry(
      slug: 'legs_r25_quarry_strider',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'legs_r30_mountain_strider',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 30,
    ),
    TitleThresholdEntry(
      slug: 'legs_r40_stone_strider',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 40,
    ),
    TitleThresholdEntry(
      slug: 'legs_r50_mountain_footed',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'legs_r5_ground_walker',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 5,
    ),
    TitleThresholdEntry(
      slug: 'legs_r60_mountain_rooted',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 60,
    ),
    TitleThresholdEntry(
      slug: 'legs_r70_pillar_footed',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 70,
    ),
    TitleThresholdEntry(
      slug: 'legs_r80_pillar_of_storms',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 80,
    ),
    TitleThresholdEntry(
      slug: 'legs_r90_mountain_untouched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 90,
    ),
    TitleThresholdEntry(
      slug: 'legs_r99_the_pillar',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.legs,
      threshold: 99,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r10_yoke_apprentice',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 10,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r15_sky_reach',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 15,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r20_atlas_touched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 20,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r25_sky_vaulter',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r30_yoke_crowned',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 30,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r40_atlas_carried',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 40,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r50_sky_yoked',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r5_burden_tester',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 5,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r60_sky_vaulted',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 60,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r70_sky_held',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 70,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r80_sky_sundered',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 80,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r90_sky_untouched',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 90,
    ),
    TitleThresholdEntry(
      slug: 'shoulders_r99_the_atlas',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.shoulders,
      threshold: 99,
    ),

    // ─── Character-level (7 entries, sorted by slug) ──────────────────────
    TitleThresholdEntry(
      slug: 'path_forged',
      kind: TitleThresholdKind.characterLevel,
      threshold: 75,
    ),
    TitleThresholdEntry(
      slug: 'path_sworn',
      kind: TitleThresholdKind.characterLevel,
      threshold: 50,
    ),
    TitleThresholdEntry(
      slug: 'path_trodden',
      kind: TitleThresholdKind.characterLevel,
      threshold: 25,
    ),
    TitleThresholdEntry(
      slug: 'saga_bound',
      kind: TitleThresholdKind.characterLevel,
      threshold: 125,
    ),
    TitleThresholdEntry(
      slug: 'saga_eternal',
      kind: TitleThresholdKind.characterLevel,
      threshold: 148,
    ),
    TitleThresholdEntry(
      slug: 'saga_scribed',
      kind: TitleThresholdKind.characterLevel,
      threshold: 100,
    ),
    TitleThresholdEntry(
      slug: 'wanderer',
      kind: TitleThresholdKind.characterLevel,
      threshold: 10,
    ),

    // ─── Cross-build (5 entries, sorted by slug) ──────────────────────────
    TitleThresholdEntry(
      slug: 'broad_shouldered',
      kind: TitleThresholdKind.crossBuild,
    ),
    TitleThresholdEntry(
      slug: 'even_handed',
      kind: TitleThresholdKind.crossBuild,
    ),
    TitleThresholdEntry(
      slug: 'iron_bound',
      kind: TitleThresholdKind.crossBuild,
    ),
    TitleThresholdEntry(
      slug: 'pillar_walker',
      kind: TitleThresholdKind.crossBuild,
    ),
    TitleThresholdEntry(
      slug: 'saga_forged',
      kind: TitleThresholdKind.crossBuild,
    ),
  ];
}
