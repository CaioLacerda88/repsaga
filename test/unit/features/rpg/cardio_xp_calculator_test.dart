// Phase 38c cardio formula parity — replays the cardio oracle sections of
// `rpg_xp_fixtures.json` against the Dart `CardioXpCalculator`, `EstVo2max`,
// and `CrossCredit` pure cores.
//
// Behavior pinned (not wiring): every row asserts the EXACT XP / MET / VO₂ /
// MET-band value the Python oracle produced, at the locked tolerances:
//   * Dart ↔ Python (this file): 1e-4 absolute.
// The 14-persona oracle drives `cardio_session_xp`; component sub-functions are
// pinned by `cardio_components`; est-VO₂max pure cores by `est_vo2max_cases`;
// the cross-credit derivation by `cross_credit_met_bands`.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/cardio_xp_calculator.dart';
import 'package:repsaga/features/rpg/domain/est_vo2max.dart';

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
  const eps = 1e-4;

  setUpAll(() {
    fixtures = _loadFixtures();
  });

  // -------------------------------------------------------------------------
  // End-to-end session XP (the 14-persona oracle + edge rows).
  // -------------------------------------------------------------------------
  group('computeSessionXp — cardio_session_xp fixture parity', () {
    test('every cardio_session_xp case matches within $eps absolute', () {
      final cases = fixtures['cardio_session_xp'] as List<dynamic>;
      expect(cases.length, 18, reason: 'expected 18 cardio_session_xp rows');

      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final name = c['name'] as String;
        final inputs = c['inputs'] as Map<String, dynamic>;

        final result = CardioXpCalculator.computeSessionXp(
          vo2max: (inputs['vo2max'] as num).toDouble(),
          age: inputs['age'] as int,
          female: inputs['female'] as bool,
          modality: inputs['modality'] as String,
          durationMin: (inputs['duration_min'] as num).toDouble(),
          kind: inputs['kind'] as String,
          value: (inputs['value'] as num).toDouble(),
          currentRank: (inputs['current_rank'] as num).toDouble(),
          weekUsedMetMin: (inputs['week_used'] as num).toDouble(),
        );

        expect(
          result.sessionXp,
          closeTo((c['xp'] as num).toDouble(), eps),
          reason: 'xp mismatch for $name',
        );
        expect(
          result.metMinutes,
          closeTo((c['met_minutes'] as num).toDouble(), eps),
          reason: 'met_minutes mismatch for $name',
        );
        expect(
          result.relIntensity,
          closeTo((c['rel_intensity'] as num).toDouble(), eps),
          reason: 'rel_intensity mismatch for $name',
        );
        expect(
          result.weekUsedAfter,
          closeTo((c['week_used_after'] as num).toDouble(), eps),
          reason: 'week_used_after mismatch for $name',
        );
      }
    });

    test('cardio_cross_week — weekly cap carries across saves, attenuating '
        'later sessions (finding [2])', () {
      final cw = fixtures['cardio_cross_week'] as Map<String, dynamic>;
      final sessions = cw['sessions'] as List<dynamic>;
      expect(sessions, hasLength(4), reason: 'expected 4 cross-week sessions');

      // Replay the sequence with a SINGLE carried accumulator — exactly the
      // semantics the SQL seed query reconstructs from prior cardio events this
      // ISO week. Each session's week_used_before must equal the running total.
      var weekUsed = 0.0;
      var prevXp = double.infinity;
      var sawAttenuation = false;
      for (final raw in sessions) {
        final s = raw as Map<String, dynamic>;
        final name = s['name'] as String;
        final inputs = s['inputs'] as Map<String, dynamic>;

        expect(
          weekUsed,
          closeTo((s['week_used_before'] as num).toDouble(), eps),
          reason:
              '$name: carried week_used must equal the oracle week_used_before',
        );

        final result = CardioXpCalculator.computeSessionXp(
          vo2max: (inputs['vo2max'] as num).toDouble(),
          age: inputs['age'] as int,
          female: inputs['female'] as bool,
          modality: inputs['modality'] as String,
          durationMin: (inputs['duration_min'] as num).toDouble(),
          kind: inputs['kind'] as String,
          value: (inputs['value'] as num).toDouble(),
          currentRank: (inputs['current_rank'] as num).toDouble(),
          weekUsedMetMin: weekUsed,
        );

        expect(
          result.sessionXp,
          closeTo((s['xp'] as num).toDouble(), eps),
          reason: '$name: xp mismatch',
        );
        expect(
          result.weekUsedAfter,
          closeTo((s['week_used_after'] as num).toDouble(), eps),
          reason: '$name: week_used_after mismatch',
        );

        // Once the running total crosses the cap, the over-portion is
        // attenuated → later identical sessions earn strictly LESS XP. This is
        // the behavior that would be invisible if the cap reset per save.
        if (result.sessionXp < prevXp - eps) sawAttenuation = true;
        prevXp = result.sessionXp;
        weekUsed = result.weekUsedAfter;
      }

      expect(
        sawAttenuation,
        isTrue,
        reason:
            'identical sessions must earn LESS once the carried weekly cap '
            'engages — proving cross-save accumulation, not a per-save reset',
      );
    });

    test('walk-when-fit edge demonstrates ~0 reward (thesis gate)', () {
      // The reformed-runner walk row: a VO₂-54 athlete walking earns trivial
      // XP — the un-farmable property, asserted on the actual value.
      final cases = fixtures['cardio_session_xp'] as List<dynamic>;
      final walk = cases.firstWhere(
        (c) => (c as Map)['name'] == 'edge__walk_when_fit',
      );
      final metcon = cases.firstWhere(
        (c) => (c as Map)['name'] == 'edge__metcon',
      );
      expect(
        ((walk as Map)['xp'] as num).toDouble(),
        lessThan(((metcon as Map)['xp'] as num).toDouble()),
        reason: 'a fit person walking must earn less than a metcon',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Component sub-functions.
  // -------------------------------------------------------------------------
  group('cardio_components fixture parity', () {
    test('intensity_mult matches within $eps', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['intensity_mult']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          CardioXpCalculator.intensityMult((r['pct_vo2max'] as num).toDouble()),
          closeTo((r['intensity_mult'] as num).toDouble(), eps),
          reason: 'intensity_mult at pct ${r['pct_vo2max']}',
        );
      }
    });

    test('sustainable_fraction matches within $eps', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['sustainable_fraction']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          CardioXpCalculator.sustainableFraction(
            (r['duration_min'] as num).toDouble(),
          ),
          closeTo((r['sustainable_fraction'] as num).toDouble(), eps),
          reason: 'sustainable_fraction at ${r['duration_min']} min',
        );
      }
    });

    test('demonstrated_vo2 matches within $eps', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['demonstrated_vo2']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          CardioXpCalculator.demonstratedVo2(
            (r['abs_met'] as num).toDouble(),
            (r['duration_min'] as num).toDouble(),
          ),
          closeTo((r['demonstrated_vo2'] as num).toDouble(), eps),
          reason:
              'demonstrated_vo2 at met ${r['abs_met']} dur '
              '${r['duration_min']}',
        );
      }
    });

    test('implied_cardio_tier matches within $eps', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['implied_cardio_tier']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          CardioXpCalculator.impliedCardioTier(
            (r['vo2'] as num).toDouble(),
            r['age'] as int,
            r['female'] as bool,
          ),
          closeTo((r['implied_cardio_tier'] as num).toDouble(), eps),
          reason: 'implied_cardio_tier vo2 ${r['vo2']} age ${r['age']}',
        );
      }
    });

    test('modality_mult matches exactly', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['modality_mult']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          CardioXpCalculator.modalityMultFor(r['modality'] as String),
          closeTo((r['modality_mult'] as num).toDouble(), eps),
          reason: 'modality_mult ${r['modality']}',
        );
      }
    });

    test('cardio_base_xp (capped_met_min^0.60) matches within $eps', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['cardio_base_xp']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        // base_xp = capped_met_min ^ 0.60. Pin the exponent directly by
        // reconstructing it from cappedMetMin — coupling it to a full
        // computeSessionXp call would only obscure which factor diverged.
        final capped = (r['capped_met_min'] as num).toDouble();
        expect(
          _pow(capped, CardioXpCalculator.volumeExponent),
          closeTo((r['base_xp'] as num).toDouble(), eps),
          reason: 'cardio_base_xp at capped $capped',
        );
      }
    });

    test('cardio_weekly_cap split matches within $eps', () {
      final rows =
          (fixtures['cardio_components']
                  as Map<String, dynamic>)['cardio_weekly_cap']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        final eff = (r['eff_met_min'] as num).toDouble();
        final used = (r['week_used'] as num).toDouble();
        final remaining = (CardioXpCalculator.weeklyCardioCapMetMin - used)
            .clamp(0.0, double.infinity);
        final under = eff < remaining ? eff : remaining;
        final over = eff - under;
        final capped = under + over * CardioXpCalculator.overCapMult;
        expect(
          capped,
          closeTo((r['capped_met_min'] as num).toDouble(), eps),
          reason: 'cardio_weekly_cap eff $eff used $used',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // est-VO₂max pure cores.
  // -------------------------------------------------------------------------
  group('est_vo2max_cases fixture parity', () {
    test('best_effort_vo2_from_pace matches within $eps (null preserved)', () {
      final rows =
          (fixtures['est_vo2max_cases'] as Map<String, dynamic>)['best_effort']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        final result = EstVo2max.bestEffortVo2FromPace(
          distanceM: (r['distance_m'] as num?)?.toDouble(),
          durationS: (r['duration_s'] as num?)?.toDouble(),
          modality: r['modality'] as String,
        );
        final expected = r['best_effort_vo2'];
        if (expected == null) {
          expect(
            result,
            isNull,
            reason:
                'best_effort should be null for ${r['modality']} '
                'dist ${r['distance_m']}',
          );
        } else {
          expect(
            result,
            closeTo((expected as num).toDouble(), eps),
            reason: 'best_effort for ${r['modality']} dist ${r['distance_m']}',
          );
        }
      }
    });

    test('nonexercise_seed_vo2 (p25 anchor) matches within $eps', () {
      final rows =
          (fixtures['est_vo2max_cases'] as Map<String, dynamic>)['seed']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          EstVo2max.nonexerciseSeedVo2(
            age: r['age'] as int?,
            female: r['female'] as bool,
          ),
          closeTo((r['seed_vo2'] as num).toDouble(), eps),
          reason: 'seed age ${r['age']} female ${r['female']}',
        );
      }
    });

    test('session_met_from_cardio_log matches within $eps', () {
      final rows =
          (fixtures['est_vo2max_cases'] as Map<String, dynamic>)['session_met']
              as List<dynamic>;
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        expect(
          EstVo2max.sessionMetFromCardioLog(
            modality: r['modality'] as String,
            distanceM: (r['distance_m'] as num?)?.toDouble(),
            durationS: (r['duration_s'] as num?)?.toDouble(),
          ),
          closeTo((r['session_met'] as num).toDouble(), eps),
          reason: 'session_met ${r['modality']} dist ${r['distance_m']}',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Rolling best-of-window (stateful — NOT in the oracle, own assertions).
  // -------------------------------------------------------------------------
  group('rollingStandingVo2max — best-of-window + seed floor', () {
    test('best qualifying effort lifts the estimate above the seed', () {
      final estimate = EstVo2max.rollingStandingVo2max(
        seedVo2: 35.9,
        qualifyingBestEfforts: const [38.0, 41.9, 40.1],
      );
      expect(estimate, closeTo(41.9, eps));
    });

    test('estimate never drops below the non-exercise seed', () {
      final estimate = EstVo2max.rollingStandingVo2max(
        seedVo2: 35.9,
        qualifyingBestEfforts: const [30.0, 28.0],
      );
      expect(estimate, closeTo(35.9, eps));
    });

    test('no qualifying efforts keeps the estimate at the seed', () {
      final estimate = EstVo2max.rollingStandingVo2max(
        seedVo2: 42.0,
        qualifyingBestEfforts: const [],
      );
      expect(estimate, closeTo(42.0, eps));
    });
  });

  // -------------------------------------------------------------------------
  // Cross-credit work-density → MET band derivation.
  // -------------------------------------------------------------------------
  group('cross_credit_met_bands fixture parity', () {
    test('every band derivation matches the oracle exactly', () {
      final rows = fixtures['cross_credit_met_bands'] as List<dynamic>;
      expect(rows.length, 8, reason: 'expected 8 cross_credit_met_bands rows');
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        final band = CrossCredit.estMetFromDensity(
          completedSets: r['completed_sets'] as int,
          sessionSeconds: (r['session_seconds'] as num).toDouble(),
          avgRest: (r['avg_rest'] as num).toDouble(),
        );
        expect(
          band,
          (r['est_met'] as num).toDouble(),
          reason: 'cross-credit band mismatch for ${r['name']}',
        );
        // Oracle self-check: the fixture also pins the expected band literal.
        expect(
          band,
          (r['expected'] as num).toDouble(),
          reason: 'fixture self-check for ${r['name']}',
        );
      }
    });
  });
}

double _pow(double x, double y) => math.pow(x, y).toDouble();
