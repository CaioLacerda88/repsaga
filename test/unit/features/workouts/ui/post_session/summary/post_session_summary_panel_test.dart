import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/workouts/data/share_image_renderer.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/providers/share_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_renderer.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_localizations.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/next_step_hook.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/post_session_summary_panel.dart';

void main() {
  const fakeShareStrings = ShareCardStrings(
    wordmark: 'REPSAGA',
    achievementFrameClassName: 'BULWARK',
    achievementFrameSagaEyebrow: 'SAGA 76',
    achievementFrameXpHero: '+618 XP',
    achievementFrameLiftDetail: null,
    achievementFrameHasPr: false,
    achievementFrameBpRank: 'Peito · Rank 19',
    discreetEyebrow: 'Peito · Rank 19',
    discreetHero: '+618',
    discreetHeroSubLabel: 'XP',
    discreetPrLine: null,
    discreetPrDetail: null,
  );

  const fakeShareLocalizations = ShareLocalizations(
    sheetTitle: 'Compartilhar saga',
    takePhoto: 'Tirar foto',
    fromGallery: 'Escolher da galeria',
    noPhoto: 'Sem foto · só a saga',
    previewRetake: 'Refazer',
    previewShare: 'Compartilhar',
    wordmark: 'REPSAGA',
    permissionDenied: 'Permissão negada',
    permissionPermanentlyDenied: 'Permissão bloqueada',
    renderError: 'Erro ao gerar imagem',
    openSettings: 'Abrir configurações',
  );

  SharePayload buildSharePayload({bool hasRankUp = true}) {
    return SharePayload.fromPostSessionState(
      tier: RewardTier.thresholdAnticipatory,
      queueResult: CelebrationQueue.build(
        events: hasRankUp
            ? const [
                CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 19),
              ]
            : const [],
      ),
      prResult: const PRDetectionResult(newRecords: [], isFirstWorkout: false),
      bpXpDeltas: const {BodyPart.chest: 618},
      bpRankAfter: const {BodyPart.chest: 19},
      bpProgressFractionAfter: const {BodyPart.chest: 0.5},
      exerciseNames: const {},
      totalXp: 618,
      characterClassSlug: 'bulwark',
    );
  }

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
    return ProviderScope(
      overrides: [
        shareServiceProvider.overrideWithValue(
          ShareService(
            imagePicker: (_) async => null,
            fileShareSink: (_, {text}) async =>
                throw UnimplementedError('not exercised'),
            permissionRequester: (_) async => throw UnimplementedError(),
            permissionStatusReader: (_) async => throw UnimplementedError(),
          ),
        ),
        shareImageRendererProvider.overrideWithValue(_StubRenderer()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PostSessionSummaryPanel(
            sagaLabel: sagaLabel ?? 'Saga 47',
            durationSetsLabel: durationSetsLabel ?? '38 min · 14 séries',
            tonnageLabel: tonnageLabel ?? '5.8 ton',
            nextStepEyebrow: 'Próximo passo',
            nextStepHook: nextStepHook,
            continueLabel: 'CONTINUAR',
            shareLabel: 'Compartilhar saga',
            sharePayload: hasShareCta ? buildSharePayload() : null,
            shareCardStrings: hasShareCta ? fakeShareStrings : null,
            shareLocalizations: hasShareCta ? fakeShareLocalizations : null,
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

  testWidgets('omits the share CTA when hasShareCta is false', (tester) async {
    await tester.pumpWidget(panel());
    expect(find.text('COMPARTILHAR SAGA'), findsNothing);
    // Camera icon is the share-CTA visual contract; should not render
    // when the CTA itself is hidden.
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
  });

  testWidgets('renders the share CTA when hasShareCta is true', (tester) async {
    await tester.pumpWidget(panel(hasShareCta: true));
    // The cinematic button uppercases the label internally per mockup
    // §5 grammar — the test asserts on the rendered (uppercase) glyph
    // run, not on the raw constructor input.
    expect(find.text('COMPARTILHAR SAGA'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
  });

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

  testWidgets('share CTA tap opens the share sheet (PR 30b wired behavior)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareServiceProvider.overrideWithValue(
            ShareService(
              imagePicker: (_) async => null,
              fileShareSink: (_, {text}) async => throw UnimplementedError(),
              permissionRequester: (_) async => PermissionStatus.granted,
              permissionStatusReader: (_) async => PermissionStatus.granted,
            ),
          ),
          shareImageRendererProvider.overrideWithValue(_StubRenderer()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PostSessionSummaryPanel(
              sagaLabel: 'Saga 47',
              durationSetsLabel: '38 min · 14 séries',
              tonnageLabel: '5.8 ton',
              nextStepEyebrow: 'Próximo passo',
              nextStepHook: null,
              continueLabel: 'CONTINUAR',
              shareLabel: 'Compartilhar saga',
              sharePayload: buildSharePayload(),
              shareCardStrings: fakeShareStrings,
              shareLocalizations: fakeShareLocalizations,
              hasShareCta: true,
              onContinue: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('COMPARTILHAR SAGA'));
    // refreshCameraPermission is async — pump to let it settle.
    await tester.pumpAndSettle();

    // The bottom sheet renders the title from ShareLocalizations.
    expect(find.text('Compartilhar saga'), findsOneWidget);
    // And the three picker rows.
    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Escolher da galeria'), findsOneWidget);
    expect(find.text('Sem foto · só a saga'), findsOneWidget);
  });
}

class _StubRenderer implements ShareImageRenderer {
  @override
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    int jpegQuality = 88,
  }) async {
    throw UnimplementedError('renderer not exercised in summary panel tests');
  }
}
