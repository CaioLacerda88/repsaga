import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/conditioning_charge.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/conditioning_charge_strip.dart';

const _labels = <BodyPart, String>{
  BodyPart.chest: 'Peito',
  BodyPart.back: 'Costas',
  BodyPart.legs: 'Pernas',
  BodyPart.shoulders: 'Ombros',
  BodyPart.arms: 'Braços',
  BodyPart.core: 'Core',
  BodyPart.cardio: 'Cardio',
};

Future<void> _pumpStrip(
  WidgetTester tester,
  ConditioningCharge charge, {
  bool animate = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: ConditioningChargeStrip(
              charge: charge,
              bodyPartLabels: _labels,
              eyebrowLabel: 'Condicionamento',
              deltaLabel: (pct) => '+$pct%',
              maxLabel: 'MÁX',
              moreLabel: (count) => '+$count mais recarregados',
              allAtPeakLabel: '✓ Tudo no pico — condicionamento mantido',
              alreadyChargedTodayLabel:
                  'Já carregado hoje. Veja a carga na sua Saga.',
              animate: animate,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Count lit rune segments by their DecoratedBox boxShadow (lit segments
/// carry a hue glow, unlit ones don't).
int _litSegments(WidgetTester tester) {
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((d) {
    final deco = d.decoration as BoxDecoration;
    return deco.boxShadow != null && deco.boxShadow!.isNotEmpty;
  }).length;
}

void main() {
  group('ConditioningChargeStrip', () {
    testWidgets('renders the bare eyebrow', (tester) async {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.core],
        before: const {BodyPart.core: (ewma: 40, peak: 100, refPeak: 100)},
        after: const {BodyPart.core: (ewma: 64, peak: 100, refPeak: 100)},
      );
      await _pumpStrip(tester, charge);
      expect(find.textContaining('CONDICIONAMENTO'), findsOneWidget);
    });

    testWidgets('gainer rows show delta + label + lit runes', (tester) async {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.core, BodyPart.back],
        before: const {
          BodyPart.core: (ewma: 40, peak: 100, refPeak: 100), // +24
          BodyPart.back: (ewma: 60, peak: 100, refPeak: 100), // +17
        },
        after: const {
          BodyPart.core: (ewma: 64, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 77, peak: 100, refPeak: 100),
        },
      );
      await _pumpStrip(tester, charge);

      expect(find.text('Core'), findsOneWidget);
      expect(find.text('Costas'), findsOneWidget);
      expect(find.text('+24%'), findsOneWidget);
      expect(find.text('+17%'), findsOneWidget);
      // No MÁX word on a pure-gainer strip.
      expect(find.text('MÁX'), findsNothing);
      // Runes are lit (mounted at final state with animate:false). Core at
      // 64% → 3 of 4, back at 77% → 3 of 4 → 6 lit segments total.
      expect(_litSegments(tester), 6);
    });

    testWidgets('MÁX row shows MÁX + full rune, never +0', (tester) async {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.back, BodyPart.legs],
        before: const {
          BodyPart.back: (ewma: 60, peak: 100, refPeak: 100), // +17 gainer
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100), // maxed
        },
        after: const {
          BodyPart.back: (ewma: 77, peak: 100, refPeak: 100),
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
        },
      );
      await _pumpStrip(tester, charge);

      expect(find.text('MÁX'), findsOneWidget);
      expect(find.text('+17%'), findsOneWidget);
      // Never a dead +0 on the maxed part.
      expect(find.text('+0%'), findsNothing);
      // Legs maxed → 4 lit; back 77% → 3 lit → 7 lit total.
      expect(_litSegments(tester), 7);
    });

    testWidgets('all-maxed session renders the all-at-peak line + MÁX rows', (
      tester,
    ) async {
      const charge = ConditioningCharge(
        parts: [
          BodyPartCharge(
            bodyPart: BodyPart.legs,
            beforePct: 1.0,
            afterPct: 1.0,
          ),
          BodyPartCharge(
            bodyPart: BodyPart.cardio,
            beforePct: 1.0,
            afterPct: 1.0,
          ),
        ],
        // Distinguish from the guard branch by leaving the guard flag off so
        // the all-at-peak line (not the guard copy) renders.
        alreadyChargedToday: false,
      );
      await _pumpStrip(tester, charge);

      expect(
        find.text('✓ Tudo no pico — condicionamento mantido'),
        findsOneWidget,
      );
      expect(find.text('MÁX'), findsNWidgets(2));
      expect(find.text('Pernas'), findsOneWidget);
      expect(find.text('Cardio'), findsOneWidget);
    });

    testWidgets('guard state renders the already-charged line, no rune rows', (
      tester,
    ) async {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest, BodyPart.back],
        before: const {
          BodyPart.chest: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 33, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.chest: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 33, peak: 100, refPeak: 100),
        },
      );
      expect(charge.alreadyChargedToday, isTrue);
      await _pumpStrip(tester, charge);

      expect(find.textContaining('Já carregado hoje'), findsOneWidget);
      // No per-bp rune rows in the guard state.
      expect(find.bySemanticsLabel(RegExp('Peito')), findsNothing);
      expect(find.text('Costas'), findsNothing);
    });

    testWidgets('overflow shows +N more recharged after 4 rows', (
      tester,
    ) async {
      // 6 gainers → 4 rows shown + "+2 mais recarregados".
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [
          BodyPart.core,
          BodyPart.back,
          BodyPart.arms,
          BodyPart.chest,
          BodyPart.shoulders,
          BodyPart.legs,
        ],
        before: const {
          BodyPart.core: (ewma: 40, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.arms: (ewma: 58, peak: 100, refPeak: 100),
          BodyPart.chest: (ewma: 60, peak: 100, refPeak: 100),
          BodyPart.shoulders: (ewma: 62, peak: 100, refPeak: 100),
          BodyPart.legs: (ewma: 64, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.core: (ewma: 64, peak: 100, refPeak: 100), // +24
          BodyPart.back: (ewma: 72, peak: 100, refPeak: 100), // +17
          BodyPart.arms: (ewma: 72, peak: 100, refPeak: 100), // +14
          BodyPart.chest: (ewma: 72, peak: 100, refPeak: 100), // +12
          BodyPart.shoulders: (ewma: 72, peak: 100, refPeak: 100), // +10
          BodyPart.legs: (ewma: 72, peak: 100, refPeak: 100), // +8
        },
      );
      await _pumpStrip(tester, charge);

      expect(find.text('+2 mais recarregados'), findsOneWidget);
      // Only the top 4 gainers render as rows.
      expect(find.text('+24%'), findsOneWidget);
      expect(find.text('+8%'), findsNothing); // 6th, overflowed
    });

    testWidgets('per-row identifiers are present (one per visible row)', (
      tester,
    ) async {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.core, BodyPart.back],
        before: const {
          BodyPart.core: (ewma: 40, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 60, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.core: (ewma: 64, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 77, peak: 100, refPeak: 100),
        },
      );
      await _pumpStrip(tester, charge);

      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      final identifiers = semantics
          .map((s) => s.properties.identifier)
          .where(
            (id) => id != null && id.startsWith('conditioning-charge-row-'),
          )
          .toList();
      expect(
        identifiers,
        containsAll(<String>[
          'conditioning-charge-row-core',
          'conditioning-charge-row-back',
        ]),
      );
    });

    testWidgets('runes fully lit at final state with animate:false '
        '(rendered output, not controller internals)', (tester) async {
      // A maxed part that still stepped (not guard-blocked) so the rune rows
      // render: legs climbed to 100% this session.
      const charge = ConditioningCharge(
        parts: [
          BodyPartCharge(
            bodyPart: BodyPart.legs,
            beforePct: 0.8,
            afterPct: 1.0,
          ),
        ],
        alreadyChargedToday: false,
      );
      // Maxed → 4 of 4 segments lit, asserted WITHOUT pumping the clock.
      await _pumpStrip(tester, charge, animate: false);
      expect(_litSegments(tester), 4);
    });
  });
}
