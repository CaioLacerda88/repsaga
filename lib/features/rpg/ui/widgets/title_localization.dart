import '../../../../l10n/app_localizations.dart';

/// Localized display copy for a single title.
class TitleCopy {
  const TitleCopy({required this.name, required this.flavor});
  final String name;
  final String flavor;
}

/// Slug → localized name + flavor lookup. Mirrors `assets/rpg/titles_v1.json`.
///
/// **Why a switch instead of reflection or a `Map<String, Function>`:**
///   * `flutter gen-l10n` generates one getter per arb key — `String get
///     title_chest_r5_initiate_of_the_forge_name => …`. Dart has no
///     compile-time reflection, and tear-off references would force the
///     codegen output to expose every getter as a static field.
///   * A switch is exhaustively maintained: when a new title slug ships in
///     `titles_v1.json`, the integration test in
///     `titles_repository_test.dart` locks the catalog count at 106. Any
///     missing case here would surface immediately as a runtime fallback,
///     and during dev as a missing arb key (build-time error).
///   * Performance: O(n) on a hot path is fine because the catalog is 106
///     entries and the post-workout half-sheet is rendered at most once
///     per finish.
///
/// Returns null for unknown slugs — callers (e.g. titles screen) decide
/// whether to skip the row or render a "(unknown title)" placeholder.
TitleCopy? localizedTitleCopy(String slug, AppLocalizations l10n) {
  switch (slug) {
    case 'chest_r5_initiate_of_the_forge':
      return TitleCopy(
        name: l10n.title_chest_r5_initiate_of_the_forge_name,
        flavor: l10n.title_chest_r5_initiate_of_the_forge_flavor,
      );
    case 'chest_r10_plate_bearer':
      return TitleCopy(
        name: l10n.title_chest_r10_plate_bearer_name,
        flavor: l10n.title_chest_r10_plate_bearer_flavor,
      );
    case 'chest_r15_forge_marked':
      return TitleCopy(
        name: l10n.title_chest_r15_forge_marked_name,
        flavor: l10n.title_chest_r15_forge_marked_flavor,
      );
    case 'chest_r20_iron_chested':
      return TitleCopy(
        name: l10n.title_chest_r20_iron_chested_name,
        flavor: l10n.title_chest_r20_iron_chested_flavor,
      );
    case 'chest_r25_anvil_heart':
      return TitleCopy(
        name: l10n.title_chest_r25_anvil_heart_name,
        flavor: l10n.title_chest_r25_anvil_heart_flavor,
      );
    case 'chest_r30_forge_born':
      return TitleCopy(
        name: l10n.title_chest_r30_forge_born_name,
        flavor: l10n.title_chest_r30_forge_born_flavor,
      );
    case 'chest_r40_bulwark_chested':
      return TitleCopy(
        name: l10n.title_chest_r40_bulwark_chested_name,
        flavor: l10n.title_chest_r40_bulwark_chested_flavor,
      );
    case 'chest_r50_forge_plated':
      return TitleCopy(
        name: l10n.title_chest_r50_forge_plated_name,
        flavor: l10n.title_chest_r50_forge_plated_flavor,
      );
    case 'chest_r60_anvil_forged':
      return TitleCopy(
        name: l10n.title_chest_r60_anvil_forged_name,
        flavor: l10n.title_chest_r60_anvil_forged_flavor,
      );
    case 'chest_r70_forge_heart':
      return TitleCopy(
        name: l10n.title_chest_r70_forge_heart_name,
        flavor: l10n.title_chest_r70_forge_heart_flavor,
      );
    case 'chest_r80_heart_of_forge':
      return TitleCopy(
        name: l10n.title_chest_r80_heart_of_forge_name,
        flavor: l10n.title_chest_r80_heart_of_forge_flavor,
      );
    case 'chest_r90_forge_untouched':
      return TitleCopy(
        name: l10n.title_chest_r90_forge_untouched_name,
        flavor: l10n.title_chest_r90_forge_untouched_flavor,
      );
    case 'chest_r99_the_anvil':
      return TitleCopy(
        name: l10n.title_chest_r99_the_anvil_name,
        flavor: l10n.title_chest_r99_the_anvil_flavor,
      );

    case 'back_r5_lattice_touched':
      return TitleCopy(
        name: l10n.title_back_r5_lattice_touched_name,
        flavor: l10n.title_back_r5_lattice_touched_flavor,
      );
    case 'back_r10_wing_marked':
      return TitleCopy(
        name: l10n.title_back_r10_wing_marked_name,
        flavor: l10n.title_back_r10_wing_marked_flavor,
      );
    case 'back_r15_rope_hauler':
      return TitleCopy(
        name: l10n.title_back_r15_rope_hauler_name,
        flavor: l10n.title_back_r15_rope_hauler_flavor,
      );
    case 'back_r20_lat_crowned':
      return TitleCopy(
        name: l10n.title_back_r20_lat_crowned_name,
        flavor: l10n.title_back_r20_lat_crowned_flavor,
      );
    case 'back_r25_talon_backed':
      return TitleCopy(
        name: l10n.title_back_r25_talon_backed_name,
        flavor: l10n.title_back_r25_talon_backed_flavor,
      );
    case 'back_r30_wing_spread':
      return TitleCopy(
        name: l10n.title_back_r30_wing_spread_name,
        flavor: l10n.title_back_r30_wing_spread_flavor,
      );
    case 'back_r40_lattice_hauled':
      return TitleCopy(
        name: l10n.title_back_r40_lattice_hauled_name,
        flavor: l10n.title_back_r40_lattice_hauled_flavor,
      );
    case 'back_r50_wing_crowned':
      return TitleCopy(
        name: l10n.title_back_r50_wing_crowned_name,
        flavor: l10n.title_back_r50_wing_crowned_flavor,
      );
    case 'back_r60_lattice_spread':
      return TitleCopy(
        name: l10n.title_back_r60_lattice_spread_name,
        flavor: l10n.title_back_r60_lattice_spread_flavor,
      );
    case 'back_r70_wing_storm':
      return TitleCopy(
        name: l10n.title_back_r70_wing_storm_name,
        flavor: l10n.title_back_r70_wing_storm_flavor,
      );
    case 'back_r80_wing_of_storms':
      return TitleCopy(
        name: l10n.title_back_r80_wing_of_storms_name,
        flavor: l10n.title_back_r80_wing_of_storms_flavor,
      );
    case 'back_r90_sky_lattice':
      return TitleCopy(
        name: l10n.title_back_r90_sky_lattice_name,
        flavor: l10n.title_back_r90_sky_lattice_flavor,
      );
    case 'back_r99_the_lattice':
      return TitleCopy(
        name: l10n.title_back_r99_the_lattice_name,
        flavor: l10n.title_back_r99_the_lattice_flavor,
      );

    case 'legs_r5_ground_walker':
      return TitleCopy(
        name: l10n.title_legs_r5_ground_walker_name,
        flavor: l10n.title_legs_r5_ground_walker_flavor,
      );
    case 'legs_r10_stone_stepper':
      return TitleCopy(
        name: l10n.title_legs_r10_stone_stepper_name,
        flavor: l10n.title_legs_r10_stone_stepper_flavor,
      );
    case 'legs_r15_pillar_apprentice':
      return TitleCopy(
        name: l10n.title_legs_r15_pillar_apprentice_name,
        flavor: l10n.title_legs_r15_pillar_apprentice_flavor,
      );
    case 'legs_r20_pillar_walker':
      return TitleCopy(
        name: l10n.title_legs_r20_pillar_walker_name,
        flavor: l10n.title_legs_r20_pillar_walker_flavor,
      );
    case 'legs_r25_quarry_strider':
      return TitleCopy(
        name: l10n.title_legs_r25_quarry_strider_name,
        flavor: l10n.title_legs_r25_quarry_strider_flavor,
      );
    case 'legs_r30_mountain_strider':
      return TitleCopy(
        name: l10n.title_legs_r30_mountain_strider_name,
        flavor: l10n.title_legs_r30_mountain_strider_flavor,
      );
    case 'legs_r40_stone_strider':
      return TitleCopy(
        name: l10n.title_legs_r40_stone_strider_name,
        flavor: l10n.title_legs_r40_stone_strider_flavor,
      );
    case 'legs_r50_mountain_footed':
      return TitleCopy(
        name: l10n.title_legs_r50_mountain_footed_name,
        flavor: l10n.title_legs_r50_mountain_footed_flavor,
      );
    case 'legs_r60_mountain_rooted':
      return TitleCopy(
        name: l10n.title_legs_r60_mountain_rooted_name,
        flavor: l10n.title_legs_r60_mountain_rooted_flavor,
      );
    case 'legs_r70_pillar_footed':
      return TitleCopy(
        name: l10n.title_legs_r70_pillar_footed_name,
        flavor: l10n.title_legs_r70_pillar_footed_flavor,
      );
    case 'legs_r80_pillar_of_storms':
      return TitleCopy(
        name: l10n.title_legs_r80_pillar_of_storms_name,
        flavor: l10n.title_legs_r80_pillar_of_storms_flavor,
      );
    case 'legs_r90_mountain_untouched':
      return TitleCopy(
        name: l10n.title_legs_r90_mountain_untouched_name,
        flavor: l10n.title_legs_r90_mountain_untouched_flavor,
      );
    case 'legs_r99_the_pillar':
      return TitleCopy(
        name: l10n.title_legs_r99_the_pillar_name,
        flavor: l10n.title_legs_r99_the_pillar_flavor,
      );

    case 'shoulders_r5_burden_tester':
      return TitleCopy(
        name: l10n.title_shoulders_r5_burden_tester_name,
        flavor: l10n.title_shoulders_r5_burden_tester_flavor,
      );
    case 'shoulders_r10_yoke_apprentice':
      return TitleCopy(
        name: l10n.title_shoulders_r10_yoke_apprentice_name,
        flavor: l10n.title_shoulders_r10_yoke_apprentice_flavor,
      );
    case 'shoulders_r15_sky_reach':
      return TitleCopy(
        name: l10n.title_shoulders_r15_sky_reach_name,
        flavor: l10n.title_shoulders_r15_sky_reach_flavor,
      );
    case 'shoulders_r20_atlas_touched':
      return TitleCopy(
        name: l10n.title_shoulders_r20_atlas_touched_name,
        flavor: l10n.title_shoulders_r20_atlas_touched_flavor,
      );
    case 'shoulders_r25_sky_vaulter':
      return TitleCopy(
        name: l10n.title_shoulders_r25_sky_vaulter_name,
        flavor: l10n.title_shoulders_r25_sky_vaulter_flavor,
      );
    case 'shoulders_r30_yoke_crowned':
      return TitleCopy(
        name: l10n.title_shoulders_r30_yoke_crowned_name,
        flavor: l10n.title_shoulders_r30_yoke_crowned_flavor,
      );
    case 'shoulders_r40_atlas_carried':
      return TitleCopy(
        name: l10n.title_shoulders_r40_atlas_carried_name,
        flavor: l10n.title_shoulders_r40_atlas_carried_flavor,
      );
    case 'shoulders_r50_sky_yoked':
      return TitleCopy(
        name: l10n.title_shoulders_r50_sky_yoked_name,
        flavor: l10n.title_shoulders_r50_sky_yoked_flavor,
      );
    case 'shoulders_r60_sky_vaulted':
      return TitleCopy(
        name: l10n.title_shoulders_r60_sky_vaulted_name,
        flavor: l10n.title_shoulders_r60_sky_vaulted_flavor,
      );
    case 'shoulders_r70_sky_held':
      return TitleCopy(
        name: l10n.title_shoulders_r70_sky_held_name,
        flavor: l10n.title_shoulders_r70_sky_held_flavor,
      );
    case 'shoulders_r80_sky_sundered':
      return TitleCopy(
        name: l10n.title_shoulders_r80_sky_sundered_name,
        flavor: l10n.title_shoulders_r80_sky_sundered_flavor,
      );
    case 'shoulders_r90_sky_untouched':
      return TitleCopy(
        name: l10n.title_shoulders_r90_sky_untouched_name,
        flavor: l10n.title_shoulders_r90_sky_untouched_flavor,
      );
    case 'shoulders_r99_the_atlas':
      return TitleCopy(
        name: l10n.title_shoulders_r99_the_atlas_name,
        flavor: l10n.title_shoulders_r99_the_atlas_flavor,
      );

    case 'arms_r5_vein_stirrer':
      return TitleCopy(
        name: l10n.title_arms_r5_vein_stirrer_name,
        flavor: l10n.title_arms_r5_vein_stirrer_flavor,
      );
    case 'arms_r10_iron_fingered':
      return TitleCopy(
        name: l10n.title_arms_r10_iron_fingered_name,
        flavor: l10n.title_arms_r10_iron_fingered_flavor,
      );
    case 'arms_r15_sinew_drawn':
      return TitleCopy(
        name: l10n.title_arms_r15_sinew_drawn_name,
        flavor: l10n.title_arms_r15_sinew_drawn_flavor,
      );
    case 'arms_r20_marrow_cleaver':
      return TitleCopy(
        name: l10n.title_arms_r20_marrow_cleaver_name,
        flavor: l10n.title_arms_r20_marrow_cleaver_flavor,
      );
    case 'arms_r25_steel_sleeved':
      return TitleCopy(
        name: l10n.title_arms_r25_steel_sleeved_name,
        flavor: l10n.title_arms_r25_steel_sleeved_flavor,
      );
    case 'arms_r30_sinew_sworn':
      return TitleCopy(
        name: l10n.title_arms_r30_sinew_sworn_name,
        flavor: l10n.title_arms_r30_sinew_sworn_flavor,
      );
    case 'arms_r40_iron_knuckled':
      return TitleCopy(
        name: l10n.title_arms_r40_iron_knuckled_name,
        flavor: l10n.title_arms_r40_iron_knuckled_flavor,
      );
    case 'arms_r50_steel_forged':
      return TitleCopy(
        name: l10n.title_arms_r50_steel_forged_name,
        flavor: l10n.title_arms_r50_steel_forged_flavor,
      );
    case 'arms_r60_sinew_bound':
      return TitleCopy(
        name: l10n.title_arms_r60_sinew_bound_name,
        flavor: l10n.title_arms_r60_sinew_bound_flavor,
      );
    case 'arms_r70_iron_sleeved':
      return TitleCopy(
        name: l10n.title_arms_r70_iron_sleeved_name,
        flavor: l10n.title_arms_r70_iron_sleeved_flavor,
      );
    case 'arms_r80_sinew_of_storms':
      return TitleCopy(
        name: l10n.title_arms_r80_sinew_of_storms_name,
        flavor: l10n.title_arms_r80_sinew_of_storms_flavor,
      );
    case 'arms_r90_iron_untouched':
      return TitleCopy(
        name: l10n.title_arms_r90_iron_untouched_name,
        flavor: l10n.title_arms_r90_iron_untouched_flavor,
      );
    case 'arms_r99_the_sinew':
      return TitleCopy(
        name: l10n.title_arms_r99_the_sinew_name,
        flavor: l10n.title_arms_r99_the_sinew_flavor,
      );

    case 'core_r5_spine_tested':
      return TitleCopy(
        name: l10n.title_core_r5_spine_tested_name,
        flavor: l10n.title_core_r5_spine_tested_flavor,
      );
    case 'core_r10_core_forged':
      return TitleCopy(
        name: l10n.title_core_r10_core_forged_name,
        flavor: l10n.title_core_r10_core_forged_flavor,
      );
    case 'core_r15_pillar_spined':
      return TitleCopy(
        name: l10n.title_core_r15_pillar_spined_name,
        flavor: l10n.title_core_r15_pillar_spined_flavor,
      );
    case 'core_r20_iron_belted':
      return TitleCopy(
        name: l10n.title_core_r20_iron_belted_name,
        flavor: l10n.title_core_r20_iron_belted_flavor,
      );
    case 'core_r25_stonewall':
      return TitleCopy(
        name: l10n.title_core_r25_stonewall_name,
        flavor: l10n.title_core_r25_stonewall_flavor,
      );
    case 'core_r30_diamond_spine':
      return TitleCopy(
        name: l10n.title_core_r30_diamond_spine_name,
        flavor: l10n.title_core_r30_diamond_spine_flavor,
      );
    case 'core_r40_anchor_belted':
      return TitleCopy(
        name: l10n.title_core_r40_anchor_belted_name,
        flavor: l10n.title_core_r40_anchor_belted_flavor,
      );
    case 'core_r50_stone_cored':
      return TitleCopy(
        name: l10n.title_core_r50_stone_cored_name,
        flavor: l10n.title_core_r50_stone_cored_flavor,
      );
    case 'core_r60_marrow_carved':
      return TitleCopy(
        name: l10n.title_core_r60_marrow_carved_name,
        flavor: l10n.title_core_r60_marrow_carved_flavor,
      );
    case 'core_r70_stone_spined':
      return TitleCopy(
        name: l10n.title_core_r70_stone_spined_name,
        flavor: l10n.title_core_r70_stone_spined_flavor,
      );
    case 'core_r80_spine_of_storms':
      return TitleCopy(
        name: l10n.title_core_r80_spine_of_storms_name,
        flavor: l10n.title_core_r80_spine_of_storms_flavor,
      );
    case 'core_r90_marrow_untouched':
      return TitleCopy(
        name: l10n.title_core_r90_marrow_untouched_name,
        flavor: l10n.title_core_r90_marrow_untouched_flavor,
      );
    case 'core_r99_the_spine':
      return TitleCopy(
        name: l10n.title_core_r99_the_spine_name,
        flavor: l10n.title_core_r99_the_spine_flavor,
      );

    // Phase 38f — cardio body-part ladder (13 rungs).
    case 'cardio_r5_first_stride':
      return TitleCopy(
        name: l10n.title_cardio_r5_first_stride_name,
        flavor: l10n.title_cardio_r5_first_stride_flavor,
      );
    case 'cardio_r10_breath_found':
      return TitleCopy(
        name: l10n.title_cardio_r10_breath_found_name,
        flavor: l10n.title_cardio_r10_breath_found_flavor,
      );
    case 'cardio_r15_wind_touched':
      return TitleCopy(
        name: l10n.title_cardio_r15_wind_touched_name,
        flavor: l10n.title_cardio_r15_wind_touched_flavor,
      );
    case 'cardio_r20_pace_keeper':
      return TitleCopy(
        name: l10n.title_cardio_r20_pace_keeper_name,
        flavor: l10n.title_cardio_r20_pace_keeper_flavor,
      );
    case 'cardio_r25_long_strider':
      return TitleCopy(
        name: l10n.title_cardio_r25_long_strider_name,
        flavor: l10n.title_cardio_r25_long_strider_flavor,
      );
    case 'cardio_r30_wind_drawn':
      return TitleCopy(
        name: l10n.title_cardio_r30_wind_drawn_name,
        flavor: l10n.title_cardio_r30_wind_drawn_flavor,
      );
    case 'cardio_r40_tempo_sworn':
      return TitleCopy(
        name: l10n.title_cardio_r40_tempo_sworn_name,
        flavor: l10n.title_cardio_r40_tempo_sworn_flavor,
      );
    case 'cardio_r50_wind_crowned':
      return TitleCopy(
        name: l10n.title_cardio_r50_wind_crowned_name,
        flavor: l10n.title_cardio_r50_wind_crowned_flavor,
      );
    case 'cardio_r60_breath_forged':
      return TitleCopy(
        name: l10n.title_cardio_r60_breath_forged_name,
        flavor: l10n.title_cardio_r60_breath_forged_flavor,
      );
    case 'cardio_r70_wind_runner':
      return TitleCopy(
        name: l10n.title_cardio_r70_wind_runner_name,
        flavor: l10n.title_cardio_r70_wind_runner_flavor,
      );
    case 'cardio_r80_stride_of_storms':
      return TitleCopy(
        name: l10n.title_cardio_r80_stride_of_storms_name,
        flavor: l10n.title_cardio_r80_stride_of_storms_flavor,
      );
    case 'cardio_r90_wind_untouched':
      return TitleCopy(
        name: l10n.title_cardio_r90_wind_untouched_name,
        flavor: l10n.title_cardio_r90_wind_untouched_flavor,
      );
    case 'cardio_r99_the_stride':
      return TitleCopy(
        name: l10n.title_cardio_r99_the_stride_name,
        flavor: l10n.title_cardio_r99_the_stride_flavor,
      );

    // Phase 18e — character-level titles (7 entries: lvl 10..148).
    case 'wanderer':
      return TitleCopy(
        name: l10n.title_wanderer_name,
        flavor: l10n.title_wanderer_flavor,
      );
    case 'path_trodden':
      return TitleCopy(
        name: l10n.title_path_trodden_name,
        flavor: l10n.title_path_trodden_flavor,
      );
    case 'path_sworn':
      return TitleCopy(
        name: l10n.title_path_sworn_name,
        flavor: l10n.title_path_sworn_flavor,
      );
    case 'path_forged':
      return TitleCopy(
        name: l10n.title_path_forged_name,
        flavor: l10n.title_path_forged_flavor,
      );
    case 'saga_scribed':
      return TitleCopy(
        name: l10n.title_saga_scribed_name,
        flavor: l10n.title_saga_scribed_flavor,
      );
    case 'saga_bound':
      return TitleCopy(
        name: l10n.title_saga_bound_name,
        flavor: l10n.title_saga_bound_flavor,
      );
    case 'saga_eternal':
      return TitleCopy(
        name: l10n.title_saga_eternal_name,
        flavor: l10n.title_saga_eternal_flavor,
      );
    // Phase 38f — the cardio-inclusive level cap (level 172).
    case 'saga_unending':
      return TitleCopy(
        name: l10n.title_saga_unending_name,
        flavor: l10n.title_saga_unending_flavor,
      );

    // Phase 18e — cross-build distinction titles (5 entries).
    case 'pillar_walker':
      return TitleCopy(
        name: l10n.title_pillar_walker_name,
        flavor: l10n.title_pillar_walker_flavor,
      );
    case 'broad_shouldered':
      return TitleCopy(
        name: l10n.title_broad_shouldered_name,
        flavor: l10n.title_broad_shouldered_flavor,
      );
    case 'even_handed':
      return TitleCopy(
        name: l10n.title_even_handed_name,
        flavor: l10n.title_even_handed_flavor,
      );
    case 'iron_bound':
      return TitleCopy(
        name: l10n.title_iron_bound_name,
        flavor: l10n.title_iron_bound_flavor,
      );
    case 'saga_forged':
      return TitleCopy(
        name: l10n.title_saga_forged_name,
        flavor: l10n.title_saga_forged_flavor,
      );
    // Phase 38f — cardio cross-build triangle.
    case 'the_forged_wind':
      return TitleCopy(
        name: l10n.title_the_forged_wind_name,
        flavor: l10n.title_the_forged_wind_flavor,
      );
    case 'storm_tempered':
      return TitleCopy(
        name: l10n.title_storm_tempered_name,
        flavor: l10n.title_storm_tempered_flavor,
      );
  }
  return null;
}
