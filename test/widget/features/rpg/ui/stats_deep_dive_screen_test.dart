/// Widget tests for [StatsDeepDiveScreen].
///
/// The screen composes the trend chart, the live Vitality table, and the
/// per-body-part Volume + Carga pico blocks into a single scroll view.
/// These tests verify the composition contract:
///   * Correct heading per hybrid window (90-day vs short).
///   * Six VitalityTable rows + one VitalityTrendChart + one
///     VolumePeakBlock per active body part all render.
///   * Tapping a vitality row drives the trend chart's selected line.
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
import 'package:repsaga/features/rpg/providers/cardio_decay_explainer_dismissal_provider.dart';
import 'package:repsaga/features/rpg/providers/stats_provider.dart';
import 'package:repsaga/features/rpg/ui/stats_deep_dive_screen.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';
import 'package:repsaga/features/rpg/ui/widgets/cardio_decay_explainer_banner.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_explainer_sheet.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_table.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_trend_chart.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_trend_chart_legend.dart';
import 'package:repsaga/features/rpg/ui/widgets/volume_peak_block.dart';

import '../../../../helpers/test_material_app.dart';

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile _profile;
  @override
  Future<Profile?> build() async => _profile;
}

/// Hive-free stub for the one-time cardio-decay explainer dismissal flag.
/// Mirrors the production notifier's API without touching Hive so the screen
/// tests stay backend-free.
class _StubCardioDecayDismissal extends CardioDecayExplainerDismissalNotifier {
  _StubCardioDecayDismissal(this._initial);
  final bool _initial;
  @override
  bool build() => _initial;
  @override
  Future<void> markDismissed() async {
    state = true;
  }
}

/// A canonical "user with 90 days of activity" state — six body parts trained
/// to varying degrees.
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
      // Phase 38e: the provider emits a 7th cardio row alongside the six
      // strength tracks.
      VitalityTableRow(
        bodyPart: BodyPart.cardio,
        pct: 0.58,
        state: VitalityState.active,
        rank: 3,
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
    earliestActivity: earliest,
    windowStart: earliest,
    windowEnd: t,
  );
}

Widget _wrap({
  required StatsDeepDiveState state,
  String weightUnit = 'kg',
  BodyPart? initialBodyPart,
  bool explainerDismissed = false,
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
      // Hive-free dismissal stub: defaults to NOT-dismissed so the explainer
      // shows; flip per-test to assert the dismissed branch.
      cardioDecayExplainerDismissalProvider.overrideWith(
        () => _StubCardioDecayDismissal(explainerDismissed),
      ),
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

    testWidgets(
      'should compose 3 sections (trend chart + vitality table + per-body-part volume blocks)',
      (tester) async {
        // Stretch the surface so the long ListView fits without scrolling.
        await tester.binding.setSurfaceSize(const Size(400, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrap(state: _canonicalState()));
        await tester.pumpAndSettle();

        expect(find.byType(VitalityTable), findsOneWidget);
        expect(find.byType(VitalityTrendChart), findsOneWidget);
        // One VolumePeakBlock per active body part (six in v1).
        expect(
          find.byType(VolumePeakBlock),
          findsNWidgets(activeBodyParts.length),
        );
        // Both `_SectionHeader` headings render through the screen (uppercased
        // at the call site). The Live Vitality heading anchors the chart→table
        // junction added in c59ef2a; without an assertion the heading could
        // silently regress without a failing test.
        expect(find.text('LIVE VITALITY'), findsOneWidget);
        expect(find.text('VOLUME & PEAK'), findsOneWidget);
      },
    );

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
      // Tall surface so the Legs row is on-screen for the tap (the chart
      // legend + decay explainer banner added below the chart push the table
      // down past the default 600dp fold).
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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

      // Tap the Legs row in the vitality table (the VolumePeakBlock further
      // down also renders a "Legs" label, so scope the finder to the table).
      await tester.tap(
        find.descendant(
          of: find.byType(VitalityTable),
          matching: find.text('Legs'),
        ),
      );
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

    testWidgets('renders empty-state defaults without throwing', (
      tester,
    ) async {
      // Day-0 user — six dormant rows, empty trends. Widget must lay out
      // without overflow / null-deref.
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
      testWidgets('preselects the body part from the constructor arg', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(state: _canonicalState(), initialBodyPart: BodyPart.back),
        );
        await tester.pumpAndSettle();

        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        final bars = lineChart.data.lineBarsData;

        // Exactly one bar is the selected line (barWidth 2.5dp). The rest
        // are ghost lines (1.0dp). Stroke width is the selection contract;
        // this assertion stays stable across future color-treatment changes
        // (e.g. 26c may render ghosts as same-hue + reduced alpha).
        final selectedBars = bars.where((b) => b.barWidth > 2.0).toList();
        expect(selectedBars, hasLength(1));

        // The selected bar's color is bodyPartColor[BodyPart.back].
        expect(
          selectedBars.single.color,
          VitalityStateStyles.bodyPartColor[BodyPart.back],
        );
      });

      testWidgets('falls back to chest when initialBodyPart is null', (
        tester,
      ) async {
        // No initialBodyPart → legacy default of BodyPart.chest.
        await tester.pumpWidget(_wrap(state: _canonicalState()));
        await tester.pumpAndSettle();

        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        final bars = lineChart.data.lineBarsData;
        final selectedBars = bars.where((b) => b.barWidth > 2.0).toList();
        expect(selectedBars, hasLength(1));
        expect(
          selectedBars.single.color,
          VitalityStateStyles.bodyPartColor[BodyPart.chest],
        );
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

    group('vitality explainer icons', () {
      testWidgets(
        'should open the explainer sheet when the trend-section ⓘ is tapped',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_wrap(state: _canonicalState()));
          await tester.pumpAndSettle();

          final icon = find.byKey(const ValueKey('vitality-trend-info-icon'));
          expect(icon, findsOneWidget);

          await tester.tap(icon);
          await tester.pumpAndSettle();

          expect(find.byType(VitalityExplainerSheet), findsOneWidget);
        },
      );

      testWidgets(
        'should open the same explainer sheet when the live-vitality ⓘ is tapped',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_wrap(state: _canonicalState()));
          await tester.pumpAndSettle();

          final icon = find.byKey(const ValueKey('vitality-table-info-icon'));
          expect(icon, findsOneWidget);

          await tester.tap(icon);
          await tester.pumpAndSettle();

          expect(find.byType(VitalityExplainerSheet), findsOneWidget);
        },
      );

      testWidgets(
        'should NOT render an info icon on the Volume & peak section header',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_wrap(state: _canonicalState()));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('volume-peak-info-icon')),
            findsNothing,
          );
        },
      );
    });

    // -------------------------------------------------------------------------
    // Phase 38e-bis — trend legend + one-time cardio decay explainer
    // -------------------------------------------------------------------------
    group('cardio decay explainer + legend (Phase 38e-bis)', () {
      testWidgets('renders the trend chart legend', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrap(state: _canonicalState()));
        await tester.pumpAndSettle();

        expect(find.byType(VitalityTrendChartLegend), findsOneWidget);
        // The 7th chip reads as the cardio track in teal.
        expect(find.text('CONDITIONING'), findsOneWidget);
      });

      testWidgets('shows the explainer banner when not dismissed', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(400, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _wrap(state: _canonicalState(), explainerDismissed: false),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CardioDecayExplainerBanner), findsOneWidget);
        expect(
          find.text(
            'Cardio conditioning decays faster than strength — '
            'train it weekly to hold the line.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('hides the explainer banner when already dismissed', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(400, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _wrap(state: _canonicalState(), explainerDismissed: true),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CardioDecayExplainerBanner), findsNothing);
      });

      testWidgets(
        'tapping the X dismisses the banner and it stays gone (one-time)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            _wrap(state: _canonicalState(), explainerDismissed: false),
          );
          await tester.pumpAndSettle();

          // Visible to start.
          expect(find.byType(CardioDecayExplainerBanner), findsOneWidget);

          // Tap the X → markDismissed flips the watched flag → rebuild omits
          // the banner.
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();

          expect(find.byType(CardioDecayExplainerBanner), findsNothing);
        },
      );

      testWidgets(
        'cardio vitality row shows the decay subtitle on the screen',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 2000));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_wrap(state: _canonicalState()));
          await tester.pumpAndSettle();

          expect(find.text('Conditioning fades in ~3 weeks'), findsOneWidget);
        },
      );
    });
  });
}
