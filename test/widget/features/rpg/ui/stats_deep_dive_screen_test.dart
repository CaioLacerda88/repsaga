/// Widget tests for [StatsDeepDiveScreen] — Phase 18d.2.
///
/// The screen composes the live Vitality table, the trend chart, the volume
/// & peak secondary table, and the peak loads section into a single scroll
/// view. These tests verify the composition contract:
///   * Correct heading per hybrid window (90-day vs short).
///   * Six VitalityTable rows + one VitalityTrendChart + the volume/peak
///     section + the peak-loads section all render.
///   * Tapping a vitality row drives the trend chart's selected line.
///   * Empty peak-loads map renders the empty-state copy.
///   * Sentinel: zero numeric Vitality % numbers leak from the screen onto
///     the character sheet (handled by a sibling test file).
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/stats_provider.dart';
import 'package:repsaga/features/rpg/ui/stats_deep_dive_screen.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';
import 'package:repsaga/features/rpg/ui/widgets/peak_loads_table.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_table.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_trend_chart.dart';

import '../../../../helpers/test_material_app.dart';

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile _profile;
  @override
  Future<Profile?> build() async => _profile;
}

/// A canonical "user with 90 days of activity" state — six body parts trained
/// to varying degrees, three peaks under chest, none under shoulders.
StatsDeepDiveState _canonicalState({
  DateTime? earliestActivity,
  DateTime? today,
}) {
  final t = today ?? DateTime.utc(2026, 4, 30);
  final earliest = earliestActivity ?? t.subtract(const Duration(days: 90));
  return StatsDeepDiveState(
    vitalityRows: const [
      VitalityTableRow(
        bodyPart: BodyPart.chest,
        pct: 0.92,
        state: VitalityState.radiant,
        rank: 6,
      ),
      VitalityTableRow(
        bodyPart: BodyPart.back,
        pct: 0.55,
        state: VitalityState.active,
        rank: 4,
      ),
      VitalityTableRow(
        bodyPart: BodyPart.legs,
        pct: 0.35,
        state: VitalityState.active,
        rank: 3,
      ),
      VitalityTableRow(
        bodyPart: BodyPart.shoulders,
        pct: 0,
        state: VitalityState.dormant,
        rank: 1,
      ),
      VitalityTableRow(
        bodyPart: BodyPart.arms,
        pct: 0.20,
        state: VitalityState.fading,
        rank: 2,
      ),
      VitalityTableRow(
        bodyPart: BodyPart.core,
        pct: 0.71,
        state: VitalityState.radiant,
        rank: 5,
      ),
    ],
    trendByBodyPart: {
      for (final bp in activeBodyParts)
        bp: [
          TrendPoint(date: earliest, pct: 0.0),
          TrendPoint(date: t, pct: 0.5),
        ],
    },
    volumePeakByBodyPart: {
      for (final bp in activeBodyParts)
        bp: const VolumePeakRow(weeklyVolumeSets: 12, peakEwma: 1234.0),
    },
    peakLoadsByBodyPart: const {
      BodyPart.chest: [
        PeakLoadRow(
          exerciseName: 'Bench Press',
          peakWeight: 100,
          peakReps: 5,
          estimated1RM: 116.7,
        ),
      ],
    },
    earliestActivity: earliest,
    windowStart: earliest,
    windowEnd: t,
  );
}

Widget _wrap({
  required StatsDeepDiveState state,
  String weightUnit = 'kg',
  BodyPart? initialBodyPart,
}) {
  final stubProfile = Profile(
    id: 'test-user',
    weightUnit: weightUnit,
    locale: 'en',
    createdAt: DateTime.utc(2026, 1, 1),
  );
  return ProviderScope(
    overrides: [
      statsProvider.overrideWith((ref) async => state),
      profileProvider.overrideWith(() => _StubProfileNotifier(stubProfile)),
    ],
    child: TestMaterialApp(
      home: StatsDeepDiveScreen(initialBodyPart: initialBodyPart),
    ),
  );
}

void main() {
  group('StatsDeepDiveScreen', () {
    testWidgets('shows the AppBar title from l10n', (tester) async {
      await tester.pumpWidget(_wrap(state: _canonicalState()));
      await tester.pumpAndSettle();

      // Stats — short, the screen header form.
      expect(find.widgetWithText(AppBar, 'Stats'), findsOneWidget);
    });

    testWidgets('composes all four sections (table + chart + volume + peaks)', (
      tester,
    ) async {
      // Stretch the surface so the long ListView fits without scrolling.
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(state: _canonicalState()));
      await tester.pumpAndSettle();

      expect(find.byType(VitalityTable), findsOneWidget);
      expect(find.byType(VitalityTrendChart), findsOneWidget);
      expect(find.byType(PeakLoadsTable), findsOneWidget);
      // All four section headings render through `_SectionHeader` (uppercased
      // at the call site). The Live Vitality heading anchors the chart→table
      // junction added in c59ef2a; without an assertion the heading could
      // silently regress without a failing test.
      expect(find.text('LIVE VITALITY'), findsOneWidget);
      expect(find.text('VOLUME & PEAK'), findsOneWidget);
      expect(find.text('PEAK LOADS'), findsOneWidget);
    });

    testWidgets('uses the 90-day heading when window >= 30 days', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(state: _canonicalState()));
      await tester.pumpAndSettle();

      // 90-day heading rendered in uppercase by the section header.
      expect(find.text('90-DAY VITALITY TREND'), findsOneWidget);
      // Ensure the short variant is NOT used.
      expect(find.text('VITALITY TREND'), findsNothing);
    });

    testWidgets('uses the short heading when narrow-window mode is active', (
      tester,
    ) async {
      final today = DateTime.utc(2026, 4, 30);
      // 12 days of history — narrow window.
      final earliest = today.subtract(const Duration(days: 12));
      await tester.pumpWidget(
        _wrap(
          state: _canonicalState(today: today, earliestActivity: earliest),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('VITALITY TREND'), findsOneWidget);
      expect(find.text('90-DAY VITALITY TREND'), findsNothing);
      // X-axis label confirms narrow mode.
      expect(find.text('12 days ago'), findsOneWidget);
    });

    testWidgets('tapping a vitality row drives the trend chart selected line', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(state: _canonicalState()));
      await tester.pumpAndSettle();

      // Initial selection: chest.
      var chart = tester.widget<LineChart>(find.byType(LineChart));
      var chestVivid = chart.data.lineBarsData
          .where(
            (b) => b.color == VitalityStateStyles.bodyPartColor[BodyPart.chest],
          )
          .length;
      expect(chestVivid, 1);

      // Tap the Legs row.
      await tester.tap(find.text('Legs'));
      await tester.pumpAndSettle();

      chart = tester.widget<LineChart>(find.byType(LineChart));
      final legsVivid = chart.data.lineBarsData
          .where(
            (b) => b.color == VitalityStateStyles.bodyPartColor[BodyPart.legs],
          )
          .length;
      expect(legsVivid, 1);
      // Chest line is back to the ghost color now.
      chestVivid = chart.data.lineBarsData
          .where(
            (b) => b.color == VitalityStateStyles.bodyPartColor[BodyPart.chest],
          )
          .length;
      expect(chestVivid, 0);
    });

    testWidgets('empty peak-loads map renders the localized empty copy', (
      tester,
    ) async {
      // Stretch the surface so the empty-state copy lands inside the viewport.
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final base = _canonicalState();
      final state = StatsDeepDiveState(
        vitalityRows: base.vitalityRows,
        trendByBodyPart: base.trendByBodyPart,
        volumePeakByBodyPart: base.volumePeakByBodyPart,
        peakLoadsByBodyPart: const {},
        earliestActivity: base.earliestActivity,
        windowStart: base.windowStart,
        windowEnd: base.windowEnd,
      );
      await tester.pumpWidget(_wrap(state: state));
      await tester.pumpAndSettle();

      expect(find.text('No peaks recorded yet.'), findsOneWidget);
    });

    testWidgets('renders empty-state defaults without throwing', (
      tester,
    ) async {
      // Day-0 user — six dormant rows, empty trends, empty peaks. Widget
      // must lay out without overflow / null-deref.
      await tester.pumpWidget(_wrap(state: StatsDeepDiveState.empty()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Six rows in the live Vitality table — every active body part.
      expect(find.byType(VitalityTable), findsOneWidget);
      // The 90-day heading is shown when earliestActivity is null
      // (useNarrowWindow returns false on null earliestActivity).
      expect(find.text('90-DAY VITALITY TREND'), findsOneWidget);
    });

    group('initialBodyPart constructor arg', () {
      testWidgets(
        'opens with the trend chart pre-selected to initialBodyPart',
        (tester) async {
          await tester.pumpWidget(
            _wrap(state: _canonicalState(), initialBodyPart: BodyPart.back),
          );
          await tester.pumpAndSettle();

          // Back is the vivid line, not chest — same assertion shape as the
          // "tapping a vitality row drives the trend chart" test above.
          final chart = tester.widget<LineChart>(find.byType(LineChart));
          final backVivid = chart.data.lineBarsData
              .where(
                (b) =>
                    b.color == VitalityStateStyles.bodyPartColor[BodyPart.back],
              )
              .length;
          expect(backVivid, 1);
          final chestVivid = chart.data.lineBarsData
              .where(
                (b) =>
                    b.color ==
                    VitalityStateStyles.bodyPartColor[BodyPart.chest],
              )
              .length;
          expect(chestVivid, 0);
        },
      );

      testWidgets('falls back to chest when initialBodyPart is null', (
        tester,
      ) async {
        // No initialBodyPart → legacy default of BodyPart.chest.
        await tester.pumpWidget(_wrap(state: _canonicalState()));
        await tester.pumpAndSettle();

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        final chestVivid = chart.data.lineBarsData
            .where(
              (b) =>
                  b.color == VitalityStateStyles.bodyPartColor[BodyPart.chest],
            )
            .length;
        expect(chestVivid, 1);
      });
    });

    testWidgets('exposes saga-stats-screen Semantics identifier', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(state: _canonicalState()));
      await tester.pumpAndSettle();

      final semantics = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(StatsDeepDiveScreen),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => s.properties.identifier == 'saga-stats-screen')
          .toList();
      expect(semantics.length, 1);
    });
  });
}
