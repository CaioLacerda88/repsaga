/// Widget tests for [CardioEntryRow] (Phase 38e post-session debrief).
///
/// Behavior, not wiring: each test asserts the visible ledger row — teal
/// dot, activity name, duration hero, optional dim distance/pace suffix —
/// and that the crowded all-segments case at 320dp scales down rather than
/// overflowing. No PR / heroGold ever appears.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/cardio_entry_row.dart';

Widget _harness(Widget child, {double width = 360}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('CardioEntryRow — content', () {
    testWidgets('renders activity name + duration hero', (tester) async {
      await tester.pumpWidget(
        _harness(
          const CardioEntryRow(
            activityName: 'Treadmill',
            durationLabel: '28:45',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Treadmill'), findsOneWidget);
      expect(find.text('28:45'), findsOneWidget);
      // Teal leading dot present.
      expect(find.byKey(const ValueKey('cardio-row-hue-dot')), findsOneWidget);
    });

    testWidgets('shows the distance + pace dim suffix when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const CardioEntryRow(
            activityName: 'Treadmill',
            durationLabel: '28:45',
            distanceSuffix: '5.2 km',
            paceSuffix: '5:31/km',
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('5.2 km'), findsOneWidget);
      expect(find.textContaining('5:31/km'), findsOneWidget);
    });

    testWidgets('omits the suffix entirely when no distance/pace', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const CardioEntryRow(
            activityName: 'Jump Rope',
            durationLabel: '12:00',
          ),
        ),
      );
      await tester.pump();

      // Only the duration hero — no middot suffix group.
      expect(find.text('12:00'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });
  });

  group('CardioEntryRow — no reward chrome', () {
    testWidgets('duration hero is teal (never heroGold), no PR pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const CardioEntryRow(
            activityName: 'Rowing Machine',
            durationLabel: '24:00',
            distanceSuffix: '5.0 km',
          ),
        ),
      );
      await tester.pump();

      final duration = tester.widget<Text>(find.text('24:00'));
      expect(duration.style?.color, AppColors.bodyPartCardio);
      // No PR copy / heroGold leaks onto a cardio row.
      expect(find.text('PR'), findsNothing);
      expect(find.text('RECORDE'), findsNothing);
    });
  });

  group('CardioEntryRow — 320dp crowded case', () {
    testWidgets('all-segments long duration scales down, no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const CardioEntryRow(
            activityName: 'Treadmill Interval Session',
            durationLabel: '1:02:30',
            distanceSuffix: '12.4 km',
            paceSuffix: '5:02/km',
          ),
          width: 320,
        ),
      );
      await tester.pump();

      // The FittedBox(scaleDown) absorbs the crowded value group instead of
      // overflowing the row.
      expect(tester.takeException(), isNull);
      expect(find.text('1:02:30'), findsOneWidget);
      expect(find.byType(FittedBox), findsOneWidget);
    });
  });
}
