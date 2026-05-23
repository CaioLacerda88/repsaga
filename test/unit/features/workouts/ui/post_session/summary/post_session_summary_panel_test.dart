import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/next_step_hook.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/post_session_summary_panel.dart';

void main() {
  Widget panel({
    String? sagaLabel,
    String? durationSetsLabel,
    String? tonnageLabel,
    NextStepHookKind? nextStepHook,
    bool hasShareCta = false,
    Widget? titleEquipRow,
    Widget? rankUpOverflow,
    VoidCallback? onContinue,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PostSessionSummaryPanel(
          sagaLabel: sagaLabel ?? 'Saga 47',
          durationSetsLabel: durationSetsLabel ?? '38 min · 14 séries',
          tonnageLabel: tonnageLabel ?? '5.8 ton',
          nextStepEyebrow: 'Próximo passo',
          nextStepHook: nextStepHook,
          continueLabel: 'CONTINUAR',
          shareLabel: 'Compartilhar saga',
          shareComingSoonMessage: 'Em breve',
          hasShareCta: hasShareCta,
          titleEquipRow: titleEquipRow,
          rankUpOverflow: rankUpOverflow,
          onContinue: onContinue ?? () {},
          nextStepHookFormatter: (h) => switch (h) {
            NextRankHook(
              :final bodyPart,
              :final xpToNextRank,
              :final nextRank,
            ) =>
              'Faltam $xpToNextRank XP para ${bodyPart.dbValue} rank $nextRank.',
            NextLevelHook(:final ranksToNextLevel, :final nextLevel) =>
              'Faltam $ranksToNextLevel ranks para nível $nextLevel.',
            PrDetailHook(:final exerciseName) => exerciseName,
          },
        ),
      ),
    );
  }

  testWidgets('renders saga label, duration, tonnage, and CONTINUAR baseline', (
    tester,
  ) async {
    await tester.pumpWidget(panel());
    expect(find.text('Saga 47'), findsOneWidget);
    expect(find.text('38 min · 14 séries'), findsOneWidget);
    expect(find.text('5.8 ton'), findsOneWidget);
    // CONTINUE label is uppercased by the cinematic button per mockup spec.
    expect(find.text('CONTINUAR'), findsOneWidget);
  });

  testWidgets('CONTINUAR carries the forward-arrow Material icon', (
    tester,
  ) async {
    await tester.pumpWidget(panel());
    // The trailing icon contract is the Concept-B visual signal that the
    // CTA advances the user. Asserts pin the icon, not the rendered emoji
    // (mockup §5 final frames — visual-gate fix 2026-05-23).
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });

  testWidgets(
    'omits the share CTA when hasShareCta is false (baseline / day-zero / level-up)',
    (tester) async {
      await tester.pumpWidget(panel());
      expect(find.text('COMPARTILHAR SAGA'), findsNothing);
      // Camera icon is the share-CTA visual contract; should not render
      // when the CTA itself is hidden.
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    },
  );

  testWidgets(
    'renders the share CTA when hasShareCta is true (PR / rank-up / title / class-change)',
    (tester) async {
      await tester.pumpWidget(panel(hasShareCta: true));
      // The cinematic button uppercases the label internally per mockup
      // §5 grammar — the test asserts on the rendered (uppercase) glyph
      // run, not on the raw constructor input.
      expect(find.text('COMPARTILHAR SAGA'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    },
  );

  testWidgets('next-step hook renders pre-resolved text when provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel(
        nextStepHook: const NextRankHook(
          bodyPart: BodyPart.chest,
          xpToNextRank: 240,
          nextRank: 2,
        ),
      ),
    );
    expect(find.text('Próximo passo'.toUpperCase()), findsOneWidget);
    expect(find.text('Faltam 240 XP para chest rank 2.'), findsOneWidget);
  });

  testWidgets('next-step hook is hidden when null', (tester) async {
    await tester.pumpWidget(panel());
    expect(find.text('Próximo passo'.toUpperCase()), findsNothing);
  });

  testWidgets('CONTINUAR tap invokes onContinue callback exactly once', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(panel(onContinue: () => calls += 1));
    await tester.tap(find.text('CONTINUAR'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('titleEquipRow renders when supplied (mockup §5 State 8)', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel(titleEquipRow: const Text('TITLE_EQUIP_PLACEHOLDER')),
    );
    expect(find.text('TITLE_EQUIP_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('rankUpOverflow renders when supplied (mockup §5 State 6)', (
    tester,
  ) async {
    await tester.pumpWidget(
      panel(rankUpOverflow: const Text('OVERFLOW_PLACEHOLDER')),
    );
    expect(find.text('OVERFLOW_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets(
    'share CTA tap shows the coming-soon snackbar (30a placeholder behavior)',
    (tester) async {
      await tester.pumpWidget(panel(hasShareCta: true));
      await tester.tap(find.text('COMPARTILHAR SAGA'));
      await tester.pump(); // start the snackbar
      expect(find.text('Em breve'), findsOneWidget);
    },
  );
}
