import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/history_week_header.dart';

import '../../../../../helpers/test_material_app.dart';

void main() {
  group('HistoryWeekHeader', () {
    testWidgets('renders week label, sets roll-up, and XP total', (
      tester,
    ) async {
      await tester.pumpWidget(
        TestMaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: HistoryWeekHeader(
              weekLabel: 'Week of May 18',
              rollupSetsLabel: '12 sets',
              xpValue: 340,
            ),
          ),
        ),
      );

      expect(find.text('Week of May 18'), findsOneWidget);
      expect(find.text('12 sets'), findsOneWidget);
      expect(find.text('+340 XP'), findsOneWidget);
    });

    testWidgets('header sits at section-heading register height', (
      tester,
    ) async {
      await tester.pumpWidget(
        TestMaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: HistoryWeekHeader(
              weekLabel: 'Week of May 18',
              rollupSetsLabel: '8 sets',
              xpValue: 120,
            ),
          ),
        ),
      );

      // 52dp — section-heading register, one tier above the 48dp input
      // default. See PR #285 Important 9: the prior 48dp height read as a
      // chip/input row, not a heading; bumping to 52dp gives the strip
      // the depth of a section divider.
      final headerFinder = find.byType(HistoryWeekHeader);
      final size = tester.getSize(headerFinder);
      expect(size.height, HistoryWeekHeader.height);
      expect(HistoryWeekHeader.height, 52);
    });
  });

  group('WeekHeaderDelegate', () {
    test('minExtent == maxExtent == 52 (section-heading register)', () {
      const delegate = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      // See PR #285 Important 9 for the 48→52 bump rationale.
      expect(delegate.minExtent, 52);
      expect(delegate.maxExtent, 52);
    });

    test('shouldRebuild returns false on identical totals', () {
      const a = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      const b = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      expect(a.shouldRebuild(b), isFalse);
    });

    test('shouldRebuild returns true on changed XP', () {
      const a = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      const b = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 200,
      );
      expect(a.shouldRebuild(b), isTrue);
    });

    test('shouldRebuild returns true on changed week label', () {
      const a = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      const b = WeekHeaderDelegate(
        weekLabel: 'Week of May 25',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      expect(a.shouldRebuild(b), isTrue);
    });

    test('shouldRebuild returns true on changed sets roll-up', () {
      const a = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      const b = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '12 sets',
        xpValue: 100,
      );
      expect(a.shouldRebuild(b), isTrue);
    });
  });
}
