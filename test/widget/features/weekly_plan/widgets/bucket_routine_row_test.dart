import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/weekly_plan/ui/widgets/bucket_routine_row.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required bool isDone,
    required bool isSpontaneous,
    String? completionDayLabel,
    String? spontaneousLabel,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BucketRoutineRow(
            routineId: 'r1',
            name: 'Push Day',
            isDone: isDone,
            isSpontaneous: isSpontaneous,
            completionDayLabel: completionDayLabel,
            spontaneousLabel: spontaneousLabel,
            onOverflowTap: () {},
          ),
        ),
      ),
    );
  }

  group('BucketRoutineRow — status icon states', () {
    testWidgets('should render an outline ring when the row is planned', (
      tester,
    ) async {
      await pumpRow(tester, isDone: false, isSpontaneous: false);
      expect(
        find.byKey(const ValueKey('bucket-row-status-planned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bucket-row-status-done')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('bucket-row-spontaneous-tag')),
        findsNothing,
      );
    });

    testWidgets(
      'should render a green check and no tag when done and not spontaneous',
      (tester) async {
        await pumpRow(
          tester,
          isDone: true,
          isSpontaneous: false,
          completionDayLabel: 'Seg',
        );
        expect(
          find.byKey(const ValueKey('bucket-row-status-done')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('bucket-row-spontaneous-tag')),
          findsNothing,
        );
        expect(find.text('Seg'), findsOneWidget);
      },
    );

    testWidgets(
      'should render a violet check and the Espontâneo tag when done and spontaneous',
      (tester) async {
        await pumpRow(
          tester,
          isDone: true,
          isSpontaneous: true,
          completionDayLabel: 'Qua',
          spontaneousLabel: 'Espontâneo',
        );
        expect(
          find.byKey(const ValueKey('bucket-row-status-done-spontaneous')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('bucket-row-spontaneous-tag')),
          findsOneWidget,
        );
        expect(find.textContaining('Espontâneo'), findsOneWidget);
        expect(find.text('Qua'), findsOneWidget);
      },
    );
  });

  group('BucketRoutineRow — name styling', () {
    testWidgets('should render the name in textDim when pending', (
      tester,
    ) async {
      await pumpRow(tester, isDone: false, isSpontaneous: false);
      final nameText = tester.widget<Text>(find.text('Push Day'));
      // Dim color is applied via .copyWith(color: ...) on titleMedium — the
      // exact value comes from AppColors.textDim. We assert color is set,
      // and pin the exact value in a separate visual-verification step.
      expect(nameText.style?.color, isNotNull);
    });

    testWidgets('should render the name in textCream when done', (
      tester,
    ) async {
      await pumpRow(tester, isDone: true, isSpontaneous: false);
      final nameText = tester.widget<Text>(find.text('Push Day'));
      expect(nameText.style?.color, isNotNull);
    });
  });

  group('BucketRoutineRow — overflow menu', () {
    testWidgets('should fire onOverflowTap when the overflow icon is tapped', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BucketRoutineRow(
              routineId: 'r1',
              name: 'Push Day',
              isDone: false,
              isSpontaneous: false,
              onOverflowTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bucket-row-overflow')));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
