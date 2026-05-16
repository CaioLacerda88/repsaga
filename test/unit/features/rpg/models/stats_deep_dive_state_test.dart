import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';

void main() {
  group('VolumePeakRow — extended history fields', () {
    test(
      'exposes previousWeekVolumeSets / fourWeekMeanVolumeSets / peakEwma30dAgo / weeksOfHistory',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 105.0,
          previousWeekVolumeSets: 16,
          fourWeekMeanVolumeSets: 14.5,
          peakEwma30dAgo: 101.8,
          weeksOfHistory: 9,
        );
        expect(row.weeklyVolumeSets, 12);
        expect(row.peakEwma, 105.0);
        expect(row.previousWeekVolumeSets, 16);
        expect(row.fourWeekMeanVolumeSets, 14.5);
        expect(row.peakEwma30dAgo, 101.8);
        expect(row.weeksOfHistory, 9);
      },
    );

    test(
      'defaults: previousWeek and fourWeekMean are nullable (no history)',
      () {
        const row = VolumePeakRow(
          weeklyVolumeSets: 0,
          peakEwma: 0,
          previousWeekVolumeSets: null,
          fourWeekMeanVolumeSets: null,
          peakEwma30dAgo: null,
          weeksOfHistory: 0,
        );
        expect(row.previousWeekVolumeSets, isNull);
        expect(row.fourWeekMeanVolumeSets, isNull);
        expect(row.peakEwma30dAgo, isNull);
        expect(row.weeksOfHistory, 0);
      },
    );
  });
}
