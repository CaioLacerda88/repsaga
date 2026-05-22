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
