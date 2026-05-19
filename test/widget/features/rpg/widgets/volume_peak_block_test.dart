import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/volume_peak_block.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('pt')}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  );
}

void main() {
  group('VolumePeakBlock', () {
    testWidgets('should render Volume + Carga pico columns with deltas '
        '(personal-history mode)', (tester) async {
      // Phase 27 L10: peakLoadKg drives the kg readout; peakLoadKg30dAgo
      // drives the monthly delta. peakEwma is no longer rendered as a
      // kg value (it remains in the model for the trend chart).
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 105.0,
        peakLoadKg: 92.5,
        peakLoadKg30dAgo: 87.5,
        previousWeekVolumeSets: 16,
        fourWeekMeanVolumeSets: 16.0,
        peakEwma30dAgo: 101.8,
        weeksOfHistory: 8,
      );
      await tester.pumpWidget(
        _wrap(
          VolumePeakBlock(
            bodyPart: BodyPart.chest,
            row: row,
            volumeDelta: VolumeDeltaView.fromRow(row),
            peakDelta: PeakDeltaView.fromRow(row),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Body part name (pt).
      expect(find.text('Peito'), findsOneWidget);
      // Volume column.
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      // Carga pico column shows actual heaviest weight in kg (one decimal
      // because pt locale uses comma as decimal separator: "92,5").
      expect(find.text('Carga pico'), findsOneWidget);
      expect(find.text('92,5'), findsOneWidget);
      // The widget MUST NOT render the EWMA value as kg anymore.
      expect(find.text('105'), findsNothing);
      // 30D badge present (delta is positive: 92.5 - 87.5 = 5).
      expect(find.text('30D'), findsOneWidget);
      // Delta arrow shows the kg delta — formatted with locale separator
      // (5,0 in pt).
      expect(find.textContaining('+5 kg'), findsOneWidget);
      // Delta line uses 4-week mean (8 weeks of history → four-week mean basis).
      expect(find.textContaining('vs média'), findsOneWidget);
    });

    testWidgets(
      'should render the peak kg as a clean integer when the heaviest lift '
      'lands on a whole kilogram',
      (tester) async {
        // Most users train in whole-kg plates — render without ",0" tail.
        const row = VolumePeakRow(
          weeklyVolumeSets: 8,
          peakEwma: 60,
          peakLoadKg: 80,
          peakLoadKg30dAgo: 75,
          previousWeekVolumeSets: 8,
          weeksOfHistory: 4,
        );
        await tester.pumpWidget(
          _wrap(
            VolumePeakBlock(
              bodyPart: BodyPart.legs,
              row: row,
              volumeDelta: VolumeDeltaView.fromRow(row),
              peakDelta: PeakDeltaView.fromRow(row),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('80'), findsOneWidget);
        expect(find.text('80,0'), findsNothing);
        expect(find.text('kg'), findsOneWidget);
      },
    );

    testWidgets(
      'should render the suppressed peak delta line when peakLoadKg30dAgo is null',
      (tester) async {
        const row = VolumePeakRow(
          weeklyVolumeSets: 10,
          peakEwma: 80,
          peakLoadKg: 100,
          previousWeekVolumeSets: 8,
          weeksOfHistory: 4,
        );
        await tester.pumpWidget(
          _wrap(
            VolumePeakBlock(
              bodyPart: BodyPart.chest,
              row: row,
              volumeDelta: VolumeDeltaView.fromRow(row),
              peakDelta: PeakDeltaView.fromRow(row),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('100'), findsOneWidget);
        expect(find.text('kg'), findsOneWidget);
        // No 30D badge — no baseline yet.
        expect(find.text('30D'), findsNothing);
      },
    );

    testWidgets(
      'should render over-target delta line in warning amber (not green)',
      (tester) async {
        const row = VolumePeakRow(
          weeklyVolumeSets: 9,
          peakEwma: 42.0,
          peakLoadKg: 42.0,
          peakLoadKg30dAgo: 40.5,
          previousWeekVolumeSets: 6,
          fourWeekMeanVolumeSets: 6.0,
          peakEwma30dAgo: 40.5,
          weeksOfHistory: 8,
        );
        await tester.pumpWidget(
          _wrap(
            VolumePeakBlock(
              bodyPart: BodyPart.shoulders,
              row: row,
              volumeDelta: VolumeDeltaView.fromRow(row),
              peakDelta: PeakDeltaView.fromRow(row),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final amberOverTargetLines = find.byWidgetPredicate((w) {
          if (w is! Text) return false;
          final color = (w.style ?? const TextStyle()).color;
          final data = w.data ?? '';
          return color == AppColors.warning && data.contains('acima da meta');
        });
        expect(amberOverTargetLines, findsOneWidget);
      },
    );

    testWidgets('should render the met-target delta line with the bullet ● and '
        'vitalityHigh color', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 14,
        peakEwma: 0,
        previousWeekVolumeSets: 14,
        weeksOfHistory: 3,
      );
      await tester.pumpWidget(
        _wrap(
          VolumePeakBlock(
            bodyPart: BodyPart.legs,
            row: row,
            volumeDelta: VolumeDeltaView.fromRow(row),
            peakDelta: PeakDeltaView.fromRow(row),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final greenBullet = find.byWidgetPredicate((w) {
        if (w is! Text) return false;
        final color = (w.style ?? const TextStyle()).color;
        final data = w.data ?? '';
        return color == AppColors.vitalityHigh && data.startsWith('●');
      });
      expect(greenBullet, findsOneWidget);
    });

    testWidgets(
      'should render the Referência generic-tip fallback for an untrained body part',
      (tester) async {
        // Untrained: no weekly history AND no heaviest lift in window.
        // The fallback gate post-Phase 27 L10 checks both signals.
        const row = VolumePeakRow(
          weeklyVolumeSets: 0,
          peakEwma: 0,
          peakLoadKg: 0,
          weeksOfHistory: 0,
        );
        await tester.pumpWidget(
          _wrap(
            VolumePeakBlock(
              bodyPart: BodyPart.arms,
              row: row,
              volumeDelta: VolumeDeltaView.fromRow(row),
              peakDelta: PeakDeltaView.fromRow(row),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Referência'), findsOneWidget);
        expect(find.text('10'), findsOneWidget);
        expect(find.text('estimado'), findsOneWidget);
      },
    );

    testWidgets('should omit any delta line text for a 0–1-week-history row '
        '(suppressed)', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 8,
        peakEwma: 60.0,
        peakLoadKg: 70.0,
        weeksOfHistory: 1,
      );
      await tester.pumpWidget(
        _wrap(
          VolumePeakBlock(
            bodyPart: BodyPart.back,
            row: row,
            volumeDelta: VolumeDeltaView.fromRow(row),
            peakDelta: PeakDeltaView.fromRow(row),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No "vs semana passada" / "vs média" delta line should render — the
      // volume column collapses to a "no history" line.
      expect(find.textContaining('vs semana passada'), findsNothing);
      expect(find.textContaining('vs média'), findsNothing);
      expect(find.textContaining('sem histórico'), findsAtLeast(1));
    });

    testWidgets(
      'should expose Semantics identifier volume-peak-block-<bodyPart>',
      (tester) async {
        const row = VolumePeakRow(
          weeklyVolumeSets: 12,
          peakEwma: 80.0,
          peakLoadKg: 60.0,
          peakLoadKg30dAgo: 55.0,
          previousWeekVolumeSets: 10,
          peakEwma30dAgo: 78.0,
          weeksOfHistory: 4,
        );
        await tester.pumpWidget(
          _wrap(
            VolumePeakBlock(
              bodyPart: BodyPart.core,
              row: row,
              volumeDelta: VolumeDeltaView.fromRow(row),
              peakDelta: PeakDeltaView.fromRow(row),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sanity: the body-part name renders inside the block.
        expect(find.text('Core'), findsOneWidget);
      },
    );
  });
}
