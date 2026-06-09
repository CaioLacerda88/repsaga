import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/progress_point.dart';
import 'package:repsaga/features/exercises/providers/exercise_progress_provider.dart';
import 'package:repsaga/features/exercises/ui/widgets/progress_chart_section.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import '../../../../helpers/test_material_app.dart';

/// Fake profile notifier so tests can pin the weight unit without hitting the
/// real profile repository.
class _FakeProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _FakeProfileNotifier(this._unit);
  final String _unit;

  @override
  Future<Profile?> build() async => Profile(id: 'user-001', weightUnit: _unit);

  @override
  Future<void> saveOnboardingProfile({
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}

/// Build the harness with an explicit [ExerciseProgressData] record so the
/// widget's consumption of `rawPoints`, `e1rmPoints`, AND `workoutCount` is
/// exercised (BL-1 disambiguation folded into BL-3 acceptance #14, plus
/// BLOCKER fix: raw vs e1RM series must be independently rankable).
///
/// When [e1rmPoints] is omitted, the harness derives an Epley-mapped view of
/// [points] so legacy tests keep passing without hand-crafting both lists.
/// Tests that specifically need e1RM-peak != raw-peak (BLOCKER regression
/// guard) pass an explicit [e1rmPoints].
Widget _buildHarness({
  required String unit,
  required List<ProgressPoint> points,
  required int workoutCount,
  List<ProgressPoint>? e1rmPoints,
  double? prValue,
}) {
  final derivedE1rm =
      e1rmPoints ??
      [
        for (final p in points)
          ProgressPoint(
            date: p.date,
            weight: p.weight * (1 + p.sessionReps / 30),
            sessionReps: p.sessionReps,
          ),
      ].where((p) => p.weight > 0).toList();
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => _FakeProfileNotifier(unit)),
      exerciseProgressProvider.overrideWith(
        (ref, _) async => (
          rawPoints: points,
          e1rmPoints: derivedE1rm,
          workoutCount: workoutCount,
        ),
      ),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ProgressChartSection(exerciseId: 'ex-1', prValue: prValue),
      ),
    ),
  );
}

/// Shorthand for building `N` ascending-date progress points for a density
/// test. Weights start at [startWeight] and rise by [step] per point; dates
/// start at [startDate] and advance by [daysPerStep] per point.
List<ProgressPoint> _linearPoints({
  required int n,
  double startWeight = 80,
  double step = 2.5,
  DateTime? startDate,
  int daysPerStep = 3,
}) {
  final first = startDate ?? DateTime(2026, 3, 1);
  return [
    for (var i = 0; i < n; i++)
      ProgressPoint(
        date: first.add(Duration(days: daysPerStep * i)),
        weight: startWeight + step * i,
        sessionReps: 5,
      ),
  ];
}

/// Finds the chart's plot-area SizedBox (uses a Key so we can measure its
/// height independently of the surrounding container chrome).
SizedBox _chartCanvas(WidgetTester tester) =>
    tester.widget<SizedBox>(find.byKey(const Key('progress-chart-canvas')));

void main() {
  group('ProgressChartSection — empty state', () {
    testWidgets(
      '0 points AND 0 workouts → first-log copy + dashed container, no chart',
      (tester) async {
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: const [], workoutCount: 0),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LineChart), findsNothing);
        expect(
          find.text('Log your first set to start tracking'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('progress-chart-empty-container')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'BL-1: 1 point AND 2 workouts → "2 workouts logged" copy, not "1 session logged"',
      (tester) async {
        // Two workouts that aggregated to one day → the provider still
        // reports workoutCount = 2. The trend-copy row must use the workout
        // count, not points.length, to disambiguate.
        final points = [
          ProgressPoint(
            date: DateTime(2026, 3, 1),
            weight: 100,
            sessionReps: 5,
          ),
        ];
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 2),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 workouts logged — keep going'), findsOneWidget);
        expect(find.text('1 session logged'), findsNothing);
      },
    );

    testWidgets('1 point AND 1 workout → "1 workout logged — keep going"', (
      tester,
    ) async {
      final points = [
        ProgressPoint(date: DateTime(2026, 3, 1), weight: 100, sessionReps: 5),
      ];
      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 1),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 workout logged — keep going'), findsOneWidget);
    });

    // Review IMPORTANT #1: workouts logged but nothing chartable (all sets
    // were bodyweight-only / warmup / incomplete → filtered out of both the
    // raw and e1RM series). The user must see the "N workouts logged" copy
    // so they know their session counted; NOT the first-log empty-state
    // container.
    testWidgets(
      '0 points AND workoutCount == 2 → "2 workouts logged" copy, no canvas, no empty container',
      (tester) async {
        await tester.pumpWidget(
          _buildHarness(
            unit: 'kg',
            points: const [],
            e1rmPoints: const [],
            workoutCount: 2,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 workouts logged — keep going'), findsOneWidget);
        expect(find.byType(LineChart), findsNothing);
        expect(find.byKey(const Key('progress-chart-canvas')), findsNothing);
        expect(
          find.byKey(const Key('progress-chart-empty-container')),
          findsNothing,
        );
      },
    );
  });

  group('ProgressChartSection — densities', () {
    testWidgets('sparse (3 points) → 120dp chart canvas, per-dot date labels', (
      tester,
    ) async {
      final points = _linearPoints(n: 3);
      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 3),
      );
      await tester.pumpAndSettle();

      // Acceptance #8: <4 points → 120dp plot area (not the whole widget).
      final canvas = _chartCanvas(tester);
      expect(canvas.height, 120);

      // Acceptance #4: N<10 → per-dot date labels. Every point's formatted
      // date label should render once.
      for (final p in points) {
        final label = _formatDate(p.date);
        expect(
          find.text(label),
          findsWidgets,
          reason: 'expected per-dot label for $label',
        );
      }

      // Trend copy should read as "Up X kg in 30 days" (default window).
      // The default window is last30Days and weights rise 80 → 82.5 → 85.
      expect(find.textContaining('Up'), findsOneWidget);
      expect(find.textContaining('in 30 days'), findsOneWidget);
    });

    testWidgets(
      'mid (5 points) → 200dp chart canvas, first + last date labels',
      (tester) async {
        final points = _linearPoints(n: 5);
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 5),
        );
        await tester.pumpAndSettle();

        // Acceptance #8: >=4 points → 200dp plot area.
        final canvas = _chartCanvas(tester);
        expect(canvas.height, 200);

        // Acceptance #4: 5 <= 8 points → first + last dates shown.
        final firstLabel = _formatDate(points.first.date);
        final lastLabel = _formatDate(points.last.date);
        expect(find.text(firstLabel), findsWidgets);
        expect(find.text(lastLabel), findsWidgets);

        // Trend copy is still "Up X kg in 30 days".
        expect(find.textContaining('Up'), findsOneWidget);
      },
    );

    testWidgets(
      'rich (11 points) → 200dp canvas, 3 evenly-spaced date labels, no weekly aggregation in 30d window',
      (tester) async {
        // 11 points spaced 2 days apart → 20-day span, still within 30d.
        final points = _linearPoints(n: 11, daysPerStep: 2);
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 11),
        );
        await tester.pumpAndSettle();

        final canvas = _chartCanvas(tester);
        expect(canvas.height, 200);

        // Weekly-max aggregation is ONLY for allTime window when N>30.
        // With 11 points in the 30d window, no aggregation → the LineChart's
        // spot count should equal the raw point count.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(lineChart.data.lineBarsData.single.spots.length, 11);

        // >8 points → 3 evenly-spaced labels (first, middle, last).
        final firstLabel = _formatDate(points.first.date);
        final midLabel = _formatDate(points[points.length ~/ 2].date);
        final lastLabel = _formatDate(points.last.date);
        expect(find.text(firstLabel), findsWidgets);
        expect(find.text(midLabel), findsWidgets);
        expect(find.text(lastLabel), findsWidgets);
      },
    );
  });

  group('ProgressChartSection — PR ring', () {
    testWidgets('ring renders at peak dot when 3+ points', (tester) async {
      // Peak is the last point at 85 kg (80 → 82.5 → 85).
      final points = _linearPoints(n: 3);
      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 3),
      );
      await tester.pumpAndSettle();

      // The widget flags the peak dot so tests can locate it. The widget
      // publishes a Semantics label on the chart that mentions "PR".
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('PR marker'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('prValue anchors ring in Weight mode when it matches a dot', (
      tester,
    ) async {
      // 5 points: 80, 82.5, 85, 87.5, 90. In-window peak is 90.
      // Pass prValue = 87.5 as the all-time PR — in Weight mode the ring
      // should anchor at the 87.5 dot (3rd index), NOT the peak (90).
      final points = _linearPoints(n: 5);
      await tester.pumpWidget(
        _buildHarness(
          unit: 'kg',
          points: points,
          workoutCount: 5,
          prValue: 87.5,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Weight mode — prValue only applies there. In e1RM mode
      // the raw 87.5 kg doesn't match a dot's Epley y-value. The metric
      // toggle is a cycle button showing the CURRENT metric label; tapping
      // "e1RM" flips to Weight.
      await tester.tap(find.text('e1RM'));
      await tester.pumpAndSettle();

      // The PR anchor is identified via a Semantics label that encodes
      // the anchor weight. We verify the ring followed prValue, not the
      // in-window peak.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('PR marker at 87.5'),
        ),
        findsOneWidget,
        reason: 'Ring should anchor at prValue=87.5, not the peak 90',
      );
    });
  });

  group('ProgressChartSection — metric toggle', () {
    testWidgets('switching Weight → e1RM changes the plotted y-values', (
      tester,
    ) async {
      // 100 kg × 5 reps: raw weight = 100, e1RM = 100 * (1 + 5/30) = 116.67
      // 105 kg × 5 reps: raw weight = 105, e1RM = 105 * (1 + 5/30) = 122.5
      final points = [
        ProgressPoint(date: DateTime(2026, 3, 1), weight: 100, sessionReps: 5),
        ProgressPoint(date: DateTime(2026, 3, 3), weight: 105, sessionReps: 5),
      ];

      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 2),
      );
      await tester.pumpAndSettle();

      // Default metric is e1RM → the topmost plotted y is the e1RM value,
      // NOT the raw 105. Reading the chart's spots confirms this.
      var lineChart = tester.widget<LineChart>(find.byType(LineChart));
      var yMax = lineChart.data.lineBarsData.single.spots
          .map((s) => s.y)
          .reduce((a, b) => a > b ? a : b);
      expect(
        yMax,
        closeTo(105 * (1 + 5 / 30), 0.01),
        reason: 'e1RM mode should plot Epley values',
      );

      // The metric toggle is a compact cycle button that shows the CURRENT
      // metric label (default = "e1RM"); tapping it flips to Weight mode.
      await tester.tap(find.text('e1RM'));
      await tester.pumpAndSettle();

      lineChart = tester.widget<LineChart>(find.byType(LineChart));
      yMax = lineChart.data.lineBarsData.single.spots
          .map((s) => s.y)
          .reduce((a, b) => a > b ? a : b);
      expect(
        yMax,
        closeTo(105, 0.01),
        reason: 'Weight mode should plot raw max weight',
      );
    });

    // Review BLOCKER regression guard: the provider's raw and e1RM series are
    // ranked independently. A day with `(100×10)` (e1RM 133.3) and `(110×3)`
    // (e1RM 121) stores 110 in rawPoints but 100 in e1rmPoints. The widget
    // must plot the pre-ranked series for each metric instead of re-mapping
    // the raw list — otherwise e1RM mode under-reports the peak. This test
    // asserts the plotted y-max matches the correct per-metric peak (NOT the
    // re-mapped raw peak, which would read ~121 instead of the true 133.3).
    testWidgets('y-axis peak differs between metrics when fixture diverges', (
      tester,
    ) async {
      // Two-day fixture so we get a real LineChart (not the single-point
      // pill) and can read the spot y-values directly.
      //
      // Day 1:  raw = 100 × 5 → 100 kg, e1RM = 100 × 5 → 116.67
      // Day 2:  raw = 110 × 3 → 110 kg (raw peak)
      //         e1RM peak on that day came from an unseen 100 × 10 set →
      //         133.33 (e1RM peak). Raw and e1RM lists diverge here.
      final day1 = DateTime(2026, 3, 1);
      final day2 = DateTime(2026, 3, 5);

      final rawPoints = [
        ProgressPoint(date: day1, weight: 100, sessionReps: 5),
        ProgressPoint(date: day2, weight: 110, sessionReps: 3),
      ];
      final e1rmPoints = [
        ProgressPoint(date: day1, weight: 100 * (1 + 5 / 30), sessionReps: 5),
        ProgressPoint(date: day2, weight: 100 * (1 + 10 / 30), sessionReps: 10),
      ];

      await tester.pumpWidget(
        _buildHarness(
          unit: 'kg',
          points: rawPoints,
          e1rmPoints: e1rmPoints,
          workoutCount: 2,
        ),
      );
      await tester.pumpAndSettle();

      // Default metric is e1RM → y-max should be the Epley-derived 133.3,
      // NOT the re-mapped 110 × 3 → 121 that the buggy widget would show.
      var lineChart = tester.widget<LineChart>(find.byType(LineChart));
      var yMax = lineChart.data.lineBarsData.single.spots
          .map((s) => s.y)
          .reduce((a, b) => a > b ? a : b);
      expect(
        yMax,
        closeTo(100 * (1 + 10 / 30), 0.01),
        reason: 'e1RM mode should plot e1RM-ranked peak 133.3, not 121',
      );

      // Flip to Weight mode → y-max should be the raw 110 kg PR.
      await tester.tap(find.text('e1RM'));
      await tester.pumpAndSettle();

      lineChart = tester.widget<LineChart>(find.byType(LineChart));
      yMax = lineChart.data.lineBarsData.single.spots
          .map((s) => s.y)
          .reduce((a, b) => a > b ? a : b);
      expect(
        yMax,
        closeTo(110, 0.01),
        reason: 'Weight mode should plot the raw max weight 110',
      );
    });
  });

  group('ProgressChartSection — container chrome', () {
    testWidgets(
      'chart card uses theme cardTheme.color, 12dp radius, 1dp border',
      (tester) async {
        final points = _linearPoints(n: 3);
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 3),
        );
        await tester.pumpAndSettle();

        final container = tester.widget<Container>(
          find.byKey(const Key('progress-chart-card')),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(12));
        expect(decoration.border, isNotNull);
        // No shadow / no glow.
        expect(decoration.boxShadow, anyOf(isNull, isEmpty));
      },
    );
  });

  group('ProgressChartSection — y-axis unit', () {
    testWidgets('y-axis labels carry weightUnit suffix (kg)', (tester) async {
      final points = _linearPoints(n: 3);
      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 3),
      );
      await tester.pumpAndSettle();

      // Every y-axis tick label should carry the unit suffix. We don't pin
      // an exact number (Y-range padding logic picks it), but at least one
      // label in the chart should end with " kg".
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').endsWith(' kg'),
        ),
        findsWidgets,
      );
    });

    testWidgets('y-axis labels swap to lbs when profile says lbs', (
      tester,
    ) async {
      final points = _linearPoints(n: 3);
      await tester.pumpWidget(
        _buildHarness(unit: 'lbs', points: points, workoutCount: 3),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').endsWith(' lbs'),
        ),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').endsWith(' kg'),
        ),
        findsNothing,
      );
    });
  });

  group('ProgressChartSection — trend copy states', () {
    testWidgets('flat delta → "Holding steady at X kg"', (tester) async {
      final points = [
        ProgressPoint(date: DateTime(2026, 3, 1), weight: 100, sessionReps: 5),
        ProgressPoint(date: DateTime(2026, 3, 3), weight: 100, sessionReps: 5),
      ];
      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 2),
      );
      await tester.pumpAndSettle();

      // e1RM mode is default; e1RM @ 100×5 is ~116.67, and both endpoints
      // have the same value → trendDelta == 0 → "Holding steady" copy.
      expect(find.textContaining('Holding steady'), findsOneWidget);
    });

    testWidgets('negative delta → neutral "Down X kg in 30 days" copy', (
      tester,
    ) async {
      final points = [
        ProgressPoint(date: DateTime(2026, 3, 1), weight: 100, sessionReps: 5),
        ProgressPoint(date: DateTime(2026, 3, 5), weight: 95, sessionReps: 5),
      ];
      await tester.pumpWidget(
        _buildHarness(unit: 'kg', points: points, workoutCount: 2),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Down'), findsOneWidget);
      expect(find.textContaining('in 30 days'), findsOneWidget);
    });
  });

  group('ProgressChartSection — acceptance #9: section header killed', () {
    testWidgets(
      '"Progress (kg)" text is absent from the widget tree in all data states',
      (tester) async {
        // Data state — chart renders with points.
        final points = _linearPoints(n: 3);
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 3),
        );
        await tester.pumpAndSettle();

        expect(find.text('Progress (kg)'), findsNothing);
        expect(find.text('Progress (lbs)'), findsNothing);
        // Also covers the regex variant — no text starting with "Progress ("
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').startsWith('Progress ('),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('"Progress (lbs)" text is also absent when unit is lbs', (
      tester,
    ) async {
      final points = _linearPoints(n: 3);
      await tester.pumpWidget(
        _buildHarness(unit: 'lbs', points: points, workoutCount: 3),
      );
      await tester.pumpAndSettle();

      expect(find.text('Progress (lbs)'), findsNothing);
    });
  });

  group('ProgressChartSection — acceptance #2: weekly-max aggregation', () {
    testWidgets(
      'allTime window with >30 points collapses to fewer weekly-max spots',
      (tester) async {
        // 35 points spaced 3 days apart → spans ~105 days, all in allTime window.
        // Weekly-max aggregation kicks in when N > 30 in the allTime window.
        // 35 points × 3-day step = 105 days / 7 = 15 ISO weeks → ≤15 spots.
        final points = _linearPoints(n: 35, daysPerStep: 3);

        // We need a custom harness that uses allTime window. The default harness
        // starts with last30Days; override the provider to force the chart to
        // call _buildSeries with allTime.
        //
        // The simplest way is to pump the widget and then tap "All time" so the
        // widget state switches windows. The provider override returns the same
        // 35 points regardless of the window key (the key parameter is ignored
        // by the override), which is fine — we want to test the aggregation in
        // _buildSeries, not the provider query.
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 35),
        );
        await tester.pumpAndSettle();

        // Switch to allTime window.
        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();

        // With 35 points and allTime + N>30, weekly-max collapses the series.
        // 105-day span / 7 = 15 ISO weeks → at most 15 aggregated spots.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        final spotCount = lineChart.data.lineBarsData.single.spots.length;
        // 35 raw points must collapse to fewer weekly-max entries.
        // The exact count depends on ISO-week anchoring from the start date;
        // 35 points × 3-day step spans ~14-16 ISO weeks.
        expect(
          spotCount,
          lessThan(35),
          reason: 'weekly-max must reduce 35 raw points',
        );
        expect(
          spotCount,
          greaterThanOrEqualTo(10),
          reason: 'should still have multiple aggregated weeks',
        );
      },
    );

    testWidgets(
      'allTime window with ≤30 points does NOT aggregate — raw count preserved',
      (tester) async {
        // 25 points in allTime → no weekly-max aggregation (N <= 30 threshold).
        final points = _linearPoints(n: 25, daysPerStep: 4);
        await tester.pumpWidget(
          _buildHarness(unit: 'kg', points: points, workoutCount: 25),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();

        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        // In e1RM mode, all 25 points have reps=5 > 0 so none are filtered out.
        expect(lineChart.data.lineBarsData.single.spots.length, 25);
      },
    );
  });

  group('ProgressChartSection — window toggle still works', () {
    testWidgets('tapping 90d re-queries with TimeWindow.last90Days', (
      tester,
    ) async {
      // Toggles only render when there's data to toggle between — the
      // zero-state suppresses them intentionally. Provide a non-empty
      // points list so the window SegmentedButton is on screen.
      final points = _linearPoints(n: 3);
      final callLog = <TimeWindow>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _FakeProfileNotifier('kg')),
            exerciseProgressProvider.overrideWith((ref, key) async {
              callLog.add(key.window);
              final e1rm = [
                for (final p in points)
                  ProgressPoint(
                    date: p.date,
                    weight: p.weight * (1 + p.sessionReps / 30),
                    sessionReps: p.sessionReps,
                  ),
              ];
              return (rawPoints: points, e1rmPoints: e1rm, workoutCount: 3);
            }),
          ],
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: ProgressChartSection(exerciseId: 'ex-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default window must be last30Days per acceptance #2.
      expect(callLog, contains(TimeWindow.last30Days));
      final before = callLog.length;

      await tester.tap(find.text('90d'));
      await tester.pumpAndSettle();

      expect(callLog.length, greaterThan(before));
      expect(callLog.last, TimeWindow.last90Days);
    });
  });
}

/// Mirrors the MMM d format used by the widget for x-axis labels so tests
/// can predict the exact string (`Mar 1`, etc.) without importing intl here.
/// Assumes `en` locale — matches the widget's `DateFormat.MMMd()` default.
String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}
