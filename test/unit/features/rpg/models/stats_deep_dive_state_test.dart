import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';

void main() {
  group('VolumePeakRow — extended history fields', () {
    test(
      'should expose all extended fields (volume basis, peak-load delta, weeks of history)',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 105.0,
          peakLoadKg: 92.5,
          peakLoadKg30dAgo: 87.5,
          previousWeekVolumeSets: 16,
          fourWeekMeanVolumeSets: 14.5,
          peakEwma30dAgo: 101.8,
          weeksOfHistory: 9,
        );
        expect(row.weeklyVolumeSets, 12);
        expect(row.peakEwma, 105.0);
        expect(row.peakLoadKg, 92.5);
        expect(row.peakLoadKg30dAgo, 87.5);
        expect(row.previousWeekVolumeSets, 16);
        expect(row.fourWeekMeanVolumeSets, 14.5);
        expect(row.peakEwma30dAgo, 101.8);
        expect(row.weeksOfHistory, 9);
      },
    );

    test(
      'should default optional nullables to null and peakLoadKg + weeksOfHistory to 0',
      () {
        // Optional nullables omitted entirely — proves the model's
        // "no-data" contract is the default, not something the caller
        // must explicitly opt into.
        const row = VolumePeakRow(weeklyVolumeSets: 0, peakEwma: 0);
        expect(row.peakLoadKg, 0);
        expect(row.peakLoadKg30dAgo, isNull);
        expect(row.previousWeekVolumeSets, isNull);
        expect(row.fourWeekMeanVolumeSets, isNull);
        expect(row.peakEwma30dAgo, isNull);
        expect(row.weeksOfHistory, 0);
      },
    );
  });

  group('VolumeDeltaView.fromRow', () {
    test('should return suppressed state when weeksOfHistory < 2', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 5,
        peakEwma: 0,
        weeksOfHistory: 1,
      );
      final view = VolumeDeltaView.fromRow(row);
      expect(view.state, VolumeDeltaState.suppressed);
      expect(view.basis, isNull);
    });

    test(
      'should use previousWeek basis with 3 weeks of history; under-target when current < prev',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 0,
          previousWeekVolumeSets: 16,
          weeksOfHistory: 3,
        );
        final view = VolumeDeltaView.fromRow(row);
        expect(view.state, VolumeDeltaState.underTarget);
        expect(view.delta, -4);
        expect(view.basis, VolumeDeltaBasis.previousWeek);
      },
    );

    test(
      'should use fourWeekMean basis with 8 weeks; over-target when current > mean',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 18,
          peakEwma: 0,
          fourWeekMeanVolumeSets: 14.5,
          weeksOfHistory: 8,
        );
        final view = VolumeDeltaView.fromRow(row);
        expect(view.state, VolumeDeltaState.overTarget);
        expect(view.delta, closeTo(3.5, 0.01));
        expect(view.basis, VolumeDeltaBasis.fourWeekMean);
      },
    );

    test('should return met state on exact equality (no rounding gap)', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 14,
        peakEwma: 0,
        previousWeekVolumeSets: 14,
        weeksOfHistory: 3,
      );
      final view = VolumeDeltaView.fromRow(row);
      expect(view.state, VolumeDeltaState.met);
      expect(view.delta, 0);
    });

    test(
      'should return met state on the four-week-mean path even with tiny float drift',
      () {
        // Provider's `sum / 4.0` produces IEEE754 doubles. A user whose
        // mean is "exactly 14" can come through as 14.0 or
        // 14.000000000000002 in practice — the half-set tolerance catches
        // both as met.
        const row = VolumePeakRow(
          weeklyVolumeSets: 14,
          peakEwma: 0,
          fourWeekMeanVolumeSets: 14.000000000000002, // simulated drift
          weeksOfHistory: 8,
        );
        final view = VolumeDeltaView.fromRow(row);
        expect(view.state, VolumeDeltaState.met);
      },
    );
  });

  group('PeakDeltaView.fromRow', () {
    test('should return suppressed state when peakLoadKg30dAgo is null', () {
      // Use a non-zero weeklyVolumeSets so the trigger is unambiguously
      // peakLoadKg30dAgo == null, not "zero sets".
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 105,
        peakLoadKg: 92.5,
        weeksOfHistory: 8,
      );
      final view = PeakDeltaView.fromRow(row);
      expect(view.state, PeakDeltaState.suppressed);
    });

    test(
      'should return up state with positive delta when heaviest lift increased',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 105,
          peakLoadKg: 92.5,
          peakLoadKg30dAgo: 87.5,
          weeksOfHistory: 8,
        );
        final view = PeakDeltaView.fromRow(row);
        expect(view.state, PeakDeltaState.up);
        expect(view.delta, closeTo(5.0, 0.01));
      },
    );

    test(
      'should return flat state when heaviest lift dropped (deload week is not a failure)',
      () {
        // Phase 27 L10: actual lift weight is NOT monotonic — a user on a
        // deload week legitimately lifts less than the month prior.
        // Rendering a red ▼ on those weeks punishes intentional
        // periodization, so we flatten instead.
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 100,
          peakLoadKg: 80.0,
          peakLoadKg30dAgo: 92.5,
          weeksOfHistory: 8,
        );
        final view = PeakDeltaView.fromRow(row);
        expect(view.state, PeakDeltaState.flat);
      },
    );

    test(
      'should return flat state when heaviest lift is unchanged in the month',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 100,
          peakLoadKg: 80.0,
          peakLoadKg30dAgo: 80.0,
          weeksOfHistory: 8,
        );
        final view = PeakDeltaView.fromRow(row);
        expect(view.state, PeakDeltaState.flat);
      },
    );
  });
}
