/// Golden-image regression coverage for [PostSessionSummaryPanel] at the
/// 360dp canonical viewport.
///
/// **Why this file exists.** The 2026-05-23 on-device visual verification
/// gate (Galaxy S25 Ultra) surfaced two regressions in the summary panel
/// that no unit / widget test caught:
///   1. SafeArea floor missing — content overlapped status bar + gesture
///      nav on Android edge-to-edge devices that report 0 inset.
///   2. Default Material `FilledButton` styling + emoji glyphs baked into
///      ARB labels visually broke Concept B grammar.
///
/// Goldens lock the visual contract per mockup §5 final summary frames so
/// future regressions of this class surface at `flutter test` time rather
/// than at on-device verification time.
///
/// **Tag:** `golden` — excluded from `make test` / CI per the dart_test.yaml
/// policy (host-platform font shaping divergence makes byte-exact goldens
/// unreliable cross-host). Run locally:
///
/// ```bash
/// make test-golden
/// # or
/// flutter test --tags golden test/widget/features/workouts/ui/post_session/
/// ```
///
/// To re-bake after an intentional visual change:
///
/// ```bash
/// flutter test --tags golden --update-goldens \
///   test/widget/features/workouts/ui/post_session/summary/post_session_summary_panel_golden_test.dart
/// ```
///
/// **Coverage matrix** (mockup §5 states grouped by composition shape):
///   * `s2_baseline` — no hooks, no rows, no share CTA. The tightest
///     possible layout (most common state, sets the benchmark).
///   * `s5_rank_up_with_overflow` — share CTA + rank-up overflow row.
///     Verifies the body-part-hued overflow card composition.
///   * `s8_title_with_equip` — share CTA + title EQUIP row. Verifies the
///     two-button (EQUIP + later) layout.
///   * `s10_max_combo` — share CTA + rank-up overflow + title EQUIP.
///     The fullest layout — pins the row ordering rule (rank-up before
///     title-equip, both before the share CTA + CONTINUE rail).
@Tags(['golden'])
library;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/data/share_image_renderer.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/providers/share_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_renderer.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_localizations.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/next_step_hook.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/post_session_summary_panel.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/title_equip_row.dart';

import '../../../../../../helpers/test_material_app.dart';
import '../../../../../../helpers/tolerant_golden_comparator.dart';

void main() {
  late GoldenFileComparator previousComparator;

  setUpAll(() {
    // Use the project-wide tolerant comparator so cross-host text shaping
    // drift (Windows DirectWrite vs Linux freetype) within the 3% noise
    // floor doesn't fail the test. Real visual regressions paint diffs
    // well above the tolerance.
    previousComparator = goldenFileComparator;
    final basedir = (goldenFileComparator as LocalFileComparator).basedir;
    goldenFileComparator = TolerantGoldenFileComparator(
      basedir.resolve('post_session_summary_panel_golden_test.dart'),
    );
  });

  tearDownAll(() {
    goldenFileComparator = previousComparator;
  });

  /// Canonical phone viewport for the golden harness.
  ///
  /// 360 logical px wide × 760 logical px tall matches the "baseline
  /// Android phone" breakpoint the visual verification protocol pins
  /// (see `feedback_visual_verification_must_not_defer_bugs.md`).
  const viewport = Size(360, 760);

  /// Pre-resolved next-step hook formatter — mirrors what the screen
  /// layer wires for pt-BR (the locale the visual-gate run used).
  String formatHook(NextStepHookKind hook) => switch (hook) {
    NextRankHook(:final bodyPart, :final xpToNextRank, :final nextRank) =>
      'Faltam $xpToNextRank XP\npara ${bodyPart.dbValue} rank $nextRank.',
    NextLevelHook(:final ranksToNextLevel, :final nextLevel) =>
      'Faltam $ranksToNextLevel ranks\npara nível $nextLevel.',
    PrDetailHook(:final exerciseName) => exerciseName,
  };

  Widget host(Widget panel) {
    return ProviderScope(
      overrides: [
        // The share CTA is a ConsumerStatefulWidget; it needs the
        // share-controller graph available even when goldens don't tap it.
        shareServiceProvider.overrideWithValue(
          ShareService(
            imagePicker: (_) async => null,
            fileShareSink: (_, {text}) async =>
                throw UnimplementedError('not exercised in goldens'),
            permissionRequester: (_) async =>
                throw UnimplementedError('not exercised in goldens'),
            permissionStatusReader: (_) async =>
                throw UnimplementedError('not exercised in goldens'),
          ),
        ),
        shareImageRendererProvider.overrideWithValue(_StubRenderer()),
      ],
      child: TestMaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            // Edge-to-edge insets emulating Android 15 — status bar 24dp,
            // gesture nav 24dp. Verifies the `SafeArea(minimum:)` floor
            // still respects real insets when they ARE reported.
            padding: EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFF0D0319),
            body: panel,
          ),
        ),
      ),
    );
  }

  const fakeShareStrings = ShareCardStrings(
    wordmark: 'REPSAGA',
    variantAXpText: '+618 XP',
    variantAPrText: null,
    variantBBpEyebrow: 'Peito',
    variantBClassName: 'BULWARK',
    variantBPrTag: null,
    variantBLift: '',
    variantBBpSub: '',
    variantBXpSub: '+618 XP',
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
    previewMinimal: 'Mínimo',
    previewBold: 'Destaque',
    previewRetake: 'Refazer',
    previewShare: 'Compartilhar',
    wordmark: 'REPSAGA',
    permissionDenied: 'Permissão negada',
    permissionPermanentlyDenied: 'Permissão bloqueada',
    renderError: 'Erro ao gerar imagem',
    openSettings: 'Abrir configurações',
  );

  final sharePayload = SharePayload.fromPostSessionState(
    tier: RewardTier.thresholdAnticipatory,
    queueResult: CelebrationQueue.build(events: const []),
    prResult: const PRDetectionResult(newRecords: [], isFirstWorkout: false),
    bpXpDeltas: const {BodyPart.chest: 618},
    bpRankAfter: const {BodyPart.chest: 19},
    bpProgressFractionAfter: const {BodyPart.chest: 0.5},
    exerciseNames: const {},
    totalXp: 618,
    characterClassSlug: 'bulwark',
  );

  Widget baseline({
    bool hasShareCta = false,
    Widget? titleEquipRow,
    Widget? rankUpOverflow,
    NextStepHookKind? hook,
    Color? eyebrowColor,
  }) {
    return PostSessionSummaryPanel(
      sagaLabel: 'Saga 47',
      durationSetsLabel: '38 min · 14 séries',
      tonnageLabel: '5.8 ton',
      nextStepEyebrow: 'Próximo passo',
      nextStepHook: hook,
      nextStepEyebrowColor: eyebrowColor,
      continueLabel: 'CONTINUAR',
      shareLabel: 'Compartilhar saga',
      sharePayload: hasShareCta ? sharePayload : null,
      shareCardStrings: hasShareCta ? fakeShareStrings : null,
      shareLocalizations: hasShareCta ? fakeShareLocalizations : null,
      hasShareCta: hasShareCta,
      titleEquipRow: titleEquipRow,
      rankUpOverflow: rankUpOverflow,
      onContinue: () {},
      nextStepHookFormatter: formatHook,
    );
  }

  testWidgets('S2 baseline · pin the tightest summary composition', (
    tester,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      host(
        baseline(
          hook: const NextRankHook(
            bodyPart: BodyPart.chest,
            xpToNextRank: 168,
            nextRank: 18,
          ),
          eyebrowColor: const Color(0xFFF472B6), // bodyPartChest
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PostSessionSummaryPanel),
      matchesGoldenFile('goldens/post_session_summary_panel_s2_baseline.png'),
    );
  });

  testWidgets('S5 rank-up · pin the overflow card composition + share CTA', (
    tester,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      host(
        baseline(
          hasShareCta: true,
          rankUpOverflow: const RankUpOverflowRow(
            bodyPart: BodyPart.chest,
            bodyPartLabel: 'Peito',
            newRank: 17,
            headerLabel: '+1 RANK · ABRIR SAGA',
          ),
          hook: const NextRankHook(
            bodyPart: BodyPart.chest,
            xpToNextRank: 240,
            nextRank: 19,
          ),
          eyebrowColor: const Color(0xFFF472B6),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PostSessionSummaryPanel),
      matchesGoldenFile(
        'goldens/post_session_summary_panel_s5_rank_up_overflow.png',
      ),
    );
  });

  testWidgets('S8 title · pin the EQUIP row composition + share CTA', (
    tester,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      host(
        baseline(
          hasShareCta: true,
          titleEquipRow: TitleEquipRow(
            eyebrowLabel: 'Novo título',
            titleName: 'Pilar de Ferro',
            equipLabel: 'EQUIPAR',
            laterLabel: 'depois',
            equippedLabel: 'Equipado ✓',
            onEquipPressed: () async {},
          ),
          hook: const NextRankHook(
            bodyPart: BodyPart.chest,
            xpToNextRank: 120,
            nextRank: 21,
          ),
          eyebrowColor: const Color(0xFFF472B6),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PostSessionSummaryPanel),
      matchesGoldenFile(
        'goldens/post_session_summary_panel_s8_title_equip.png',
      ),
    );
  });

  testWidgets(
    'S10 max combo · pin the fullest summary (rank-up + title + share)',
    (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        host(
          baseline(
            hasShareCta: true,
            rankUpOverflow: const RankUpOverflowRow(
              bodyPart: BodyPart.legs,
              bodyPartLabel: 'Pernas',
              newRank: 14,
              headerLabel: '+1 RANK · ABRIR SAGA',
            ),
            titleEquipRow: TitleEquipRow(
              eyebrowLabel: 'Novo título',
              titleName: 'Pilar de Ferro',
              equipLabel: 'EQUIPAR',
              laterLabel: 'depois',
              equippedLabel: 'Equipado ✓',
              onEquipPressed: () async {},
            ),
            hook: const NextLevelHook(ranksToNextLevel: 4, nextLevel: 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(PostSessionSummaryPanel),
        matchesGoldenFile(
          'goldens/post_session_summary_panel_s10_max_combo.png',
        ),
      );
    },
  );
}

class _StubRenderer implements ShareImageRenderer {
  @override
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    int jpegQuality = 88,
  }) async {
    throw UnimplementedError('renderer not exercised in golden harness');
  }
}
