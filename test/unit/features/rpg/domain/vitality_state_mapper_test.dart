import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/vitality_state_mapper.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';

/// Canonical mapper boundary tests.
///
/// Pins the §8.4 contract (with the 2026-05-04 untested patch):
///   * `peak == 0`     → untested (via `fromVitality` only — `fromPercent`
///                       never returns untested because the ratio is
///                       already in hand)
///   * `pct == 0`      → dormant  (peak > 0, fully decayed)
///   * `(0, 0.30]`     → fading
///   * `(0.30, 0.70]`  → active
///   * `(0.70, 1.00]`  → radiant
///
/// **Pure-domain contract (BUG-035).** This test file imports zero
/// Flutter packages — neither `dart:ui`, nor `flutter/painting.dart`, nor
/// `AppLocalizations`. The mapper itself was scrubbed of those
/// dependencies as part of the architecture-leak fix; if a future change
/// re-introduces a Flutter import to the domain, this file should fail to
/// load (or its imports should leak) — that's the structural canary the
/// split exists to provide. Color resolution + localized copy now live
/// in `vitality_state_styles_test.dart` (sibling file under
/// `test/unit/features/rpg/ui/utils/`).
void main() {
  group('VitalityStateMapper.fromPercent — boundaries', () {
    test('exactly 0 → dormant', () {
      expect(VitalityStateMapper.fromPercent(0), VitalityState.dormant);
    });

    test('0 + ε → fading (just above zero)', () {
      expect(VitalityStateMapper.fromPercent(0.001), VitalityState.fading);
      expect(VitalityStateMapper.fromPercent(0.0000001), VitalityState.fading);
    });

    test('exactly 0.30 → fading (right-edge inclusive)', () {
      expect(VitalityStateMapper.fromPercent(0.30), VitalityState.fading);
    });

    test('0.30 + ε → active', () {
      expect(VitalityStateMapper.fromPercent(0.3001), VitalityState.active);
      expect(VitalityStateMapper.fromPercent(0.30000001), VitalityState.active);
    });

    test('exactly 0.70 → active (right-edge inclusive)', () {
      expect(VitalityStateMapper.fromPercent(0.70), VitalityState.active);
    });

    test('0.70 + ε → radiant', () {
      expect(VitalityStateMapper.fromPercent(0.7001), VitalityState.radiant);
      expect(
        VitalityStateMapper.fromPercent(0.70000001),
        VitalityState.radiant,
      );
    });

    test('exactly 1.0 → radiant', () {
      expect(VitalityStateMapper.fromPercent(1.0), VitalityState.radiant);
    });

    test('above 1.0 (defensive) → radiant', () {
      // Floating-point overshoot from numeric(14,4) round-trips. The mapper
      // must not split into a fifth state for "over peak" — Vitality is
      // capped at peak by definition (spec §8.1 clamp).
      expect(VitalityStateMapper.fromPercent(1.01), VitalityState.radiant);
      expect(VitalityStateMapper.fromPercent(2.0), VitalityState.radiant);
    });

    test('negative (defensive) → dormant', () {
      // pct < 0 should never occur (clamp in VitalityCalculator.percentage),
      // but the mapper handles it gracefully.
      expect(VitalityStateMapper.fromPercent(-0.1), VitalityState.dormant);
    });

    test('boundary constants match spec §8.4', () {
      expect(VitalityStateMapper.fadingMaxPct, 0.30);
      expect(VitalityStateMapper.activeMaxPct, 0.70);
    });
  });

  group('VitalityStateMapper.fromVitality — ewma+peak normalisation', () {
    test('peak == 0 collapses to untested regardless of ewma', () {
      // 2026-05-04 untested patch: peak == 0 is the "ratio undefined"
      // branch — the body part has never been trained and the ewma/peak
      // ratio is mathematically undefined. The dedicated
      // [VitalityState.untested] state lets the UI render `—` instead of
      // the misleading `0%` that reads as a failure grade. Even a non-zero
      // EWMA against a zero peak (defensive case — should never happen in
      // practice) collapses to untested.
      expect(
        VitalityStateMapper.fromVitality(ewma: 0, peak: 0),
        VitalityState.untested,
      );
      expect(
        VitalityStateMapper.fromVitality(ewma: 100, peak: 0),
        VitalityState.untested,
      );
    });

    test('ewma == 0 with peak > 0 → dormant (fully decayed)', () {
      // pct = 0/peak = 0 → dormant boundary. Distinct from untested:
      // peak > 0 means the user trained this body part at least once
      // and has since fallen completely off the path. Genuine 0% ratio.
      // This is a regression pin for the 2026-05-04 untested patch — the
      // peak > 0 case must NOT collapse into untested.
      expect(
        VitalityStateMapper.fromVitality(ewma: 0, peak: 1000),
        VitalityState.dormant,
      );
      expect(
        VitalityStateMapper.fromVitality(ewma: 0, peak: 10),
        VitalityState.dormant,
      );
    });

    test(
      'ewma > 0 with peak > 0 still maps via fromPercent (regression pin)',
      () {
        // Existing math unchanged — adding the untested variant must not
        // perturb the four-state mapping for any peak > 0 case. pct = 0.20
        // sits inside the fading band (0, 0.30].
        expect(
          VitalityStateMapper.fromVitality(ewma: 2, peak: 10),
          VitalityState.fading,
        );
      },
    );

    test('half of peak → active (boundary mid-band)', () {
      expect(
        VitalityStateMapper.fromVitality(ewma: 50, peak: 100),
        VitalityState.active,
      );
      expect(
        VitalityStateMapper.fromVitality(ewma: 5000, peak: 10000),
        VitalityState.active,
      );
    });

    test('80% of peak → radiant (real-world spec §13.3 example)', () {
      // Spec §13.3 sample: chest EWMA 8420, peak 9850 → pct ≈ 0.855 → radiant.
      expect(
        VitalityStateMapper.fromVitality(ewma: 8420, peak: 9850),
        VitalityState.radiant,
      );
    });
  });

  group('VitalityStateMapper.fromPercent — never returns untested', () {
    test(
      'every Vitality state EXCEPT untested is reachable via fromPercent',
      () {
        // Structural pin: fromPercent is the trend-chart / mean-vitality
        // path where the ratio is already known to be defined (peak > 0).
        // Adding the untested variant must not bleed into that path —
        // untested is reachable only through fromVitality(peak: 0).
        final reachable = <VitalityState>{
          VitalityStateMapper.fromPercent(0),
          VitalityStateMapper.fromPercent(0.15),
          VitalityStateMapper.fromPercent(0.5),
          VitalityStateMapper.fromPercent(0.9),
        };
        expect(reachable.contains(VitalityState.untested), isFalse);
      },
    );
  });
}
