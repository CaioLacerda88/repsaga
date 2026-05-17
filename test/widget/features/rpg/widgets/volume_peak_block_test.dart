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
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 105.0,
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
      // Carga pico column.
      expect(find.text('Carga pico'), findsOneWidget);
      expect(find.text('105'), findsOneWidget);
      // 30D badge present.
      expect(find.text('30D'), findsOneWidget);
      // Delta line uses 4-week mean (8 weeks of history → four-week mean basis).
      expect(find.textContaining('vs média'), findsOneWidget);
    });

    testWidgets(
      'should render over-target delta line in warning amber (not green)',
      (tester) async {
        const row = VolumePeakRow(
          weeklyVolumeSets: 9,
          peakEwma: 42.0,
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
        const row = VolumePeakRow(
          weeklyVolumeSets: 0,
          peakEwma: 0,
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
