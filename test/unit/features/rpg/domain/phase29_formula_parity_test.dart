// Phase 29 v2 + 29.6 formula parity — top-level summary test.
//
// The per-helper fixture-driven assertions live in
// `xp_calculator_test.dart` and `implied_tier_test.dart`. This file
// pins the discoverability invariant: the fixture exposes a fixed set
// of Phase 29 v2 oracle sections, with the row counts the PR brief
// locked. If a future regen accidentally drops a section or shrinks
// a matrix, the test fails fast here — before a helper-level parity
// test would (because the helper test would just iterate an empty
// list and pass vacuously).
//
// Counts pinned (from the brief):
//   set_xp_v2:              94
//   implied_tier:           17
//   abs_strength_premium:   12
//   tier_diff_mult:         17
//   overload_mult:          7
//   frequency_mult:         7
//   near_failure_inferred:  7

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadFixtures() {
  final file = File('test/fixtures/rpg_xp_fixtures.json');
  if (!file.existsSync()) {
    throw StateError(
      'rpg_xp_fixtures.json missing — run '
      '`python test/fixtures/generate_rpg_fixtures.py` first.',
    );
  }
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late final Map<String, dynamic> fixtures;

  setUpAll(() {
    fixtures = _loadFixtures();
  });

  group('Phase 29 v2 fixture — section row counts', () {
    test('all Phase 29 v2 sections present in regenerated fixture', () {
      const requiredSections = {
        'set_xp_v2',
        'implied_tier',
        'abs_strength_premium',
        'tier_diff_mult',
        'overload_mult',
        'frequency_mult',
        'near_failure_inferred',
      };
      for (final section in requiredSections) {
        expect(
          fixtures.containsKey(section),
          isTrue,
          reason:
              'fixture missing Phase 29 v2 section "$section" — regenerate '
              'with `python test/fixtures/generate_rpg_fixtures.py`',
        );
      }
    });

    test('set_xp_v2 has exactly 94 rows (PR brief lock)', () {
      expect((fixtures['set_xp_v2'] as List).length, 94);
    });

    test('implied_tier has exactly 17 rows', () {
      expect((fixtures['implied_tier'] as List).length, 17);
    });

    test('abs_strength_premium has exactly 12 rows', () {
      expect((fixtures['abs_strength_premium'] as List).length, 12);
    });

    test('tier_diff_mult has exactly 17 rows', () {
      expect((fixtures['tier_diff_mult'] as List).length, 17);
    });

    test('overload_mult has exactly 7 rows', () {
      expect((fixtures['overload_mult'] as List).length, 7);
    });

    test('frequency_mult has exactly 7 rows', () {
      expect((fixtures['frequency_mult'] as List).length, 7);
    });

    test('near_failure_inferred has exactly 7 rows', () {
      expect((fixtures['near_failure_inferred'] as List).length, 7);
    });
  });

  // Phase 38c — cardio oracle sections. Same discoverability invariant: a
  // future regen that drops a cardio section or shrinks a matrix fails fast
  // here, before the cardio helper parity test passes vacuously over an empty
  // list.
  //
  // Counts pinned:
  //   cardio_session_xp:        18  (14 personas + 4 edge rows)
  //   cross_credit_met_bands:    8
  //   cardio_components sub-lists: intensity_mult 13, sustainable_fraction 15,
  //     demonstrated_vo2 7, implied_cardio_tier 7, modality_mult 10,
  //     cardio_base_xp 7, cardio_weekly_cap 6
  //   est_vo2max_cases sub-lists: best_effort 6, seed 8, session_met 7
  group('Phase 38c cardio fixture — section row counts', () {
    test('all cardio sections present in regenerated fixture', () {
      const requiredSections = {
        'cardio_session_xp',
        'cardio_components',
        'est_vo2max_cases',
        'cross_credit_met_bands',
      };
      for (final section in requiredSections) {
        expect(
          fixtures.containsKey(section),
          isTrue,
          reason:
              'fixture missing Phase 38c cardio section "$section" — '
              'regenerate with '
              '`python test/fixtures/generate_rpg_fixtures.py`',
        );
      }
    });

    test('cardio_session_xp has exactly 18 rows', () {
      expect((fixtures['cardio_session_xp'] as List).length, 18);
    });

    test('cross_credit_met_bands has exactly 8 rows', () {
      expect((fixtures['cross_credit_met_bands'] as List).length, 8);
    });

    test('cardio_components sub-lists have the locked row counts', () {
      final cc = fixtures['cardio_components'] as Map<String, dynamic>;
      expect((cc['intensity_mult'] as List).length, 13);
      expect((cc['sustainable_fraction'] as List).length, 15);
      expect((cc['demonstrated_vo2'] as List).length, 7);
      expect((cc['implied_cardio_tier'] as List).length, 7);
      expect((cc['modality_mult'] as List).length, 10);
      expect((cc['cardio_base_xp'] as List).length, 7);
      expect((cc['cardio_weekly_cap'] as List).length, 6);
    });

    test('est_vo2max_cases sub-lists have the locked row counts', () {
      final ev = fixtures['est_vo2max_cases'] as Map<String, dynamic>;
      expect((ev['best_effort'] as List).length, 6);
      expect((ev['seed'] as List).length, 8);
      expect((ev['session_met'] as List).length, 7);
    });
  });

  group('Phase 38c cardio fixture — meta keys', () {
    test('meta.cardio carries the locked cardio constants', () {
      final meta = fixtures['meta'] as Map<String, dynamic>;
      expect(meta.containsKey('cardio'), isTrue);
      final cardio = meta['cardio'] as Map<String, dynamic>;
      const requiredKeys = {
        'met_rest',
        'volume_exponent',
        'cardio_xp_scale',
        'weekly_cardio_cap_metmin',
        'over_cap_mult',
        'vo2_ceiling_cap',
        'set_work_seconds',
        'rest_default',
        'age_fallback',
        'vo2_rolling_window_days',
        'distance_modalities',
        'cardio_default_met',
        'cardio_slug_to_modality',
        'modality_mult',
        'intensity_anchors',
        'sustain_anchors',
        'tier_anchors',
      };
      for (final key in requiredKeys) {
        expect(
          cardio.containsKey(key),
          isTrue,
          reason: 'meta.cardio key "$key" missing — regenerate fixture',
        );
      }
    });

    test('locked cardio literal values', () {
      final cardio =
          (fixtures['meta'] as Map<String, dynamic>)['cardio']
              as Map<String, dynamic>;
      expect(cardio['met_rest'], 3.5);
      expect(cardio['volume_exponent'], 0.60);
      expect(cardio['cardio_xp_scale'], 3.5);
      expect(cardio['weekly_cardio_cap_metmin'], 2500.0);
      expect(cardio['over_cap_mult'], 0.30);
      expect(cardio['vo2_ceiling_cap'], 90.0);
      expect(cardio['set_work_seconds'], 30);
      expect(cardio['rest_default'], 90);
      expect(cardio['age_fallback'], 35);
      expect(cardio['vo2_rolling_window_days'], 42);
    });
  });

  group('Phase 29 v2 fixture — meta keys', () {
    test('meta carries Phase 29 v2 constants', () {
      final meta = fixtures['meta'] as Map<String, dynamic>;
      // Sanity: every new key the helpers consume.
      const requiredKeys = {
        'xp_base',
        'xp_growth_band1',
        'rank_curve_breakpoint',
        'linear_xp_per_rank',
        'e_bonus',
        'e_floor',
        'e_ceil',
        'nf_intensity_bonus',
        'nf_target_threshold',
        'frequency_mult_table',
        'tier_diff_offset',
        'tier_diff_exp',
        'tier_diff_min',
        'tier_diff_max',
        'bodyweight_load_ratios',
      };
      for (final key in requiredKeys) {
        expect(
          meta.containsKey(key),
          isTrue,
          reason: 'meta key "$key" missing — regenerate fixture',
        );
      }
    });

    test('locked literal values', () {
      final meta = fixtures['meta'] as Map<String, dynamic>;
      expect(meta['xp_base'], 60);
      expect(meta['xp_growth_band1'], 1.10);
      expect(meta['rank_curve_breakpoint'], 20);
      expect(meta['linear_xp_per_rank'], 367.0);
      expect(meta['e_bonus'], 0.8);
      expect(meta['e_floor'], 35.0);
      expect(meta['e_ceil'], 55.0);
      expect(meta['nf_intensity_bonus'], 0.10);
      expect(meta['nf_target_threshold'], 0.85);
      expect(meta['frequency_mult_table'], [1.00, 1.06, 1.10, 1.06, 1.00]);
    });
  });
}
