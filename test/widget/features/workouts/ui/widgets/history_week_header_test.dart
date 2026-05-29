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

    testWidgets('header sits at 48dp tall', (tester) async {
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

      // Find the Container hosting the row + padding. Its rendered height
      // is the explicit 48dp constraint passed in the widget.
      final headerFinder = find.byType(HistoryWeekHeader);
      final size = tester.getSize(headerFinder);
      expect(size.height, 48);
    });
  });

  group('WeekHeaderDelegate', () {
    test('minExtent == maxExtent == 48', () {
      const delegate = WeekHeaderDelegate(
        weekLabel: 'Week of May 18',
        rollupSetsLabel: '5 sets',
        xpValue: 100,
      );
      expect(delegate.minExtent, 48);
      expect(delegate.maxExtent, 48);
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
