import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/workouts/domain/post_session_choreographer.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/session_lift_summary.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_state.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/mission_debrief_localizations.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/mission_debrief_section.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/lift_row.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/xp_segmented_bar.dart';

/// Walks every `TextSpan` under [richTextFinder] and returns true if any
/// span's `text` (recursively) equals [expected]. Needed because
/// `find.text()` only matches `Text.data`, not `Text.rich`'s nested spans.
bool _hasRichTextSpan(WidgetTester tester, String expected) {
  bool walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text == expected) return true;
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (walk(child)) return true;
      }
    }
    return false;
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    if (walk(richText.text)) return true;
  }
  return false;
}

/// Fixed BP label lookup for fixtures. Matches the controller's projection.
const _bodyPartLabels = <BodyPart, String>{
  BodyPart.chest: 'Peito',
  BodyPart.back: 'Costas',
  BodyPart.legs: 'Pernas',
  BodyPart.shoulders: 'Ombros',
  BodyPart.arms: 'Braços',
  BodyPart.core: 'Core',
  BodyPart.cardio: 'Cardio',
};

MissionDebriefLocalizations _ptLocalizations() {
  return MissionDebriefLocalizations(
    debriefEyebrow: 'Relatório da sessão',
    moreLifts: (count) =>
        count == 1 ? '+1 outro exercício' : '+$count outros exercícios',
    nextTargetEyebrow: 'Próximo passo',
    nextTargetBody: (xp, bp, n) => 'Faltam $xp XP\npara $bp rank $n.',
    prFlag: 'PR',
    rankLabel: (rank) => 'Rank $rank',
    rankUpArrow: (from, to) => 'Rank $from → $to',
    weightUnit: 'kg',
    xpEarnedLabel: 'XP GANHO',
  );
}

MissionDebriefLocalizations _enLocalizations() {
  return MissionDebriefLocalizations(
    debriefEyebrow: 'Session report',
    moreLifts: (count) =>
        count == 1 ? '+1 more exercise' : '+$count more exercises',
    nextTargetEyebrow: 'Next',
    nextTargetBody: (xp, bp, n) => '$xp XP left\nfor $bp rank $n.',
    prFlag: 'PR',
    rankLabel: (rank) => 'Rank $rank',
    rankUpArrow: (from, to) => 'Rank $from → $to',
    weightUnit: 'kg',
    xpEarnedLabel: 'XP EARNED',
  );
}

PostSessionState _buildState({
  required List<SessionLiftSummary> topLifts,
  required Map<BodyPart, int> bpXpDeltas,
  required Map<BodyPart, int> bpRankAfter,
  Map<BodyPart, int>? bpRankBefore,
  int totalExercisesTrained = 0,
  CelebrationQueueResult? queueResult,
  BodyPart? dominantBodyPart,
  int? dominantXpToNextRank,
  int? dominantNextRank,
}) {
  final inferredDominant =
      dominantBodyPart ??
      (bpXpDeltas.isEmpty
          ? null
          : (bpXpDeltas.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key);
  // Default: assume a single-rank gain so the legacy fixtures that don't
  // exercise the multi-rank-jump path still produce a sensible Mission
  // Debrief arrow. Multi-rank fixtures override this explicitly.
  final rankBefore =
      bpRankBefore ??
      <BodyPart, int>{
        for (final entry in bpRankAfter.entries)
          entry.key: (entry.value - 1).clamp(1, 999),
      };
  return PostSessionState(
    tier: RewardTier.baseline,
    queueResult: queueResult ?? CelebrationQueue.build(events: const []),
    prResult: null,
    cuts: const <PostSessionCut>[],
    cutIndex: 0,
    showSummary: true,
    bodyPartLabels: _bodyPartLabels,
    exerciseNames: const {},
    bpProgressFractionAfter: const {},
    bpXpDeltas: bpXpDeltas,
    bpRankAfter: bpRankAfter,
    bpRankBefore: rankBefore,
    topLifts: topLifts,
    totalExercisesTrained: totalExercisesTrained == 0
        ? topLifts.length
        : totalExercisesTrained,
    totalXpEarned: bpXpDeltas.values.fold<int>(0, (a, b) => a + b),
    priorFinishedWorkoutCount: 47,
    sagaNumber: 48,
    durationMinutes: 38,
    setsCount: 14,
    tonnageTons: 5.8,
    dominantBodyPart: inferredDominant,
    dominantXpToNextRank: dominantXpToNextRank ?? 120,
    dominantNextRank: dominantNextRank ?? 12,
    ranksToNextLevel: null,
    nextLevel: null,
  );
}

Future<void> _pumpDebrief(
  WidgetTester tester, {
  required PostSessionState state,
  MissionDebriefLocalizations? localizations,
  String? classLabel,
  Size viewport = const Size(360, 1200),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MissionDebriefSection(
              state: state,
              localizations: localizations ?? _ptLocalizations(),
              classLabel: classLabel,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MissionDebriefSection', () {
    testWidgets(
      'baseline session (no PR, no rank-up, 1 BP, 3 lifts) renders eyebrow + '
      '3 lift rows + 1-segment XP bar + 1 BP delta row + next-target callout',
      (tester) async {
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'supino',
              exerciseName: 'Supino reto',
              bodyPart: BodyPart.chest,
              peakWeightKg: 80,
              peakReps: 8,
              xpContribution: 640,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'cross',
              exerciseName: 'Crossover',
              bodyPart: BodyPart.chest,
              peakWeightKg: 25,
              peakReps: 12,
              xpContribution: 300,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'inclinado',
              exerciseName: 'Supino inclinado',
              bodyPart: BodyPart.chest,
              peakWeightKg: 60,
              peakReps: 10,
              xpContribution: 600,
              isPR: false,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 618},
          bpRankAfter: const {BodyPart.chest: 18},
        );

        await _pumpDebrief(tester, state: state);

        // Eyebrow.
        expect(find.text('RELATÓRIO DA SESSÃO'), findsOneWidget);
        // 3 lift rows.
        expect(find.byType(LiftRow), findsNWidgets(3));
        // No PR flag.
        expect(find.text('PR'), findsNothing);
        // No "+N more" footer.
        expect(find.textContaining('outros exercícios'), findsNothing);
        expect(find.textContaining('outro exercício'), findsNothing);
        // XP bar visible (one segment).
        expect(find.byType(XpSegmentedBar), findsOneWidget);
        // Per-BP delta row — "Rank 18" (no rank-up). Lives inside the
        // Text.rich on the delta row so we walk TextSpan children.
        expect(_hasRichTextSpan(tester, 'Rank 18'), isTrue);
        // Next-target callout.
        expect(find.text('PRÓXIMO PASSO'), findsOneWidget);
        expect(find.textContaining('rank 12'), findsOneWidget);
      },
    );

    testWidgets('PR session: 1 PR row shows heroGold + PR flag; others plain', (
      tester,
    ) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'supino',
            exerciseName: 'Supino reto',
            bodyPart: BodyPart.chest,
            peakWeightKg: 95,
            peakReps: 5,
            xpContribution: 800,
            isPR: true,
          ),
          SessionLiftSummary(
            exerciseId: 'cross',
            exerciseName: 'Crossover',
            bodyPart: BodyPart.chest,
            peakWeightKg: 25,
            peakReps: 12,
            xpContribution: 300,
            isPR: false,
          ),
          SessionLiftSummary(
            exerciseId: 'inclinado',
            exerciseName: 'Supino inclinado',
            bodyPart: BodyPart.chest,
            peakWeightKg: 60,
            peakReps: 10,
            xpContribution: 600,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {BodyPart.chest: 618},
        bpRankAfter: const {BodyPart.chest: 18},
      );

      await _pumpDebrief(tester, state: state);

      expect(find.byType(LiftRow), findsNWidgets(3));
      // One PR flag.
      expect(find.text('PR'), findsOneWidget);
    });

    testWidgets('multi-PR session: both PR rows tagged', (tester) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'supino',
            exerciseName: 'Supino reto',
            bodyPart: BodyPart.chest,
            peakWeightKg: 95,
            peakReps: 5,
            xpContribution: 800,
            isPR: true,
          ),
          SessionLiftSummary(
            exerciseId: 'inclinado',
            exerciseName: 'Supino inclinado',
            bodyPart: BodyPart.chest,
            peakWeightKg: 70,
            peakReps: 8,
            xpContribution: 600,
            isPR: true,
          ),
          SessionLiftSummary(
            exerciseId: 'cross',
            exerciseName: 'Crossover',
            bodyPart: BodyPart.chest,
            peakWeightKg: 25,
            peakReps: 12,
            xpContribution: 300,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {BodyPart.chest: 618},
        bpRankAfter: const {BodyPart.chest: 18},
      );

      await _pumpDebrief(tester, state: state);

      expect(find.text('PR'), findsNWidgets(2));
    });

    testWidgets('rank-up session: BP delta row shows arrow grammar', (
      tester,
    ) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'remada',
            exerciseName: 'Remada curvada',
            bodyPart: BodyPart.back,
            peakWeightKg: 70,
            peakReps: 8,
            xpContribution: 560,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {BodyPart.back: 500},
        bpRankAfter: const {BodyPart.back: 12},
        queueResult: CelebrationQueue.build(
          events: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 12),
          ],
        ),
      );

      await _pumpDebrief(tester, state: state);

      // Rank-up arrow grammar instead of "Rank 12".
      expect(_hasRichTextSpan(tester, 'Rank 11 → 12'), isTrue);
      expect(_hasRichTextSpan(tester, 'Rank 12'), isFalse);
    });

    testWidgets(
      'multi-rank-jump session (rank 5 → 8): arrow renders true endpoints, '
      'not rankAfter - 1',
      (tester) async {
        // Phase 31 Blocker 1 regression — pre-fix the row would render
        // "Rank 7 → 8" (derived as rankAfter - 1). With `bpRankBefore`
        // persisted on the state, the arrow surfaces the true pre-session
        // endpoint regardless of how many ranks the session crossed.
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'supino',
              exerciseName: 'Supino reto',
              bodyPart: BodyPart.chest,
              peakWeightKg: 95,
              peakReps: 5,
              xpContribution: 900,
              isPR: true,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 900},
          bpRankBefore: const {BodyPart.chest: 5},
          bpRankAfter: const {BodyPart.chest: 8},
          queueResult: CelebrationQueue.build(
            events: const [
              CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 8),
            ],
          ),
        );

        await _pumpDebrief(tester, state: state);

        expect(_hasRichTextSpan(tester, 'Rank 5 → 8'), isTrue);
        // Pre-fix grammar must NOT leak through.
        expect(_hasRichTextSpan(tester, 'Rank 7 → 8'), isFalse);
      },
    );

    testWidgets(
      '5+ exercise session: top 4 lift rows + "+1 outro exercício" footer (pt)',
      (tester) async {
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'a',
              exerciseName: 'Supino',
              bodyPart: BodyPart.chest,
              peakWeightKg: 80,
              peakReps: 8,
              xpContribution: 640,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'b',
              exerciseName: 'Crossover',
              bodyPart: BodyPart.chest,
              peakWeightKg: 25,
              peakReps: 12,
              xpContribution: 300,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'c',
              exerciseName: 'Inclinado',
              bodyPart: BodyPart.chest,
              peakWeightKg: 60,
              peakReps: 10,
              xpContribution: 600,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'd',
              exerciseName: 'Voador',
              bodyPart: BodyPart.chest,
              peakWeightKg: 40,
              peakReps: 12,
              xpContribution: 480,
              isPR: false,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 618},
          bpRankAfter: const {BodyPart.chest: 18},
          totalExercisesTrained: 5,
        );

        await _pumpDebrief(tester, state: state);

        expect(find.byType(LiftRow), findsNWidgets(4));
        expect(find.text('+1 outro exercício'), findsOneWidget);
      },
    );

    testWidgets(
      '5+ exercise session multi-locale plural: "+2 more exercises" in en',
      (tester) async {
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'a',
              exerciseName: 'Bench',
              bodyPart: BodyPart.chest,
              peakWeightKg: 80,
              peakReps: 8,
              xpContribution: 640,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'b',
              exerciseName: 'Crossover',
              bodyPart: BodyPart.chest,
              peakWeightKg: 25,
              peakReps: 12,
              xpContribution: 300,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'c',
              exerciseName: 'Incline bench',
              bodyPart: BodyPart.chest,
              peakWeightKg: 60,
              peakReps: 10,
              xpContribution: 600,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'd',
              exerciseName: 'Flyes',
              bodyPart: BodyPart.chest,
              peakWeightKg: 40,
              peakReps: 12,
              xpContribution: 480,
              isPR: false,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 618},
          bpRankAfter: const {BodyPart.chest: 18},
          totalExercisesTrained: 6,
        );

        await _pumpDebrief(
          tester,
          state: state,
          localizations: _enLocalizations(),
        );

        expect(find.text('+2 more exercises'), findsOneWidget);
      },
    );

    testWidgets('multi-BP session: 4-segment XP bar + 4 per-BP delta rows', (
      tester,
    ) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'supino',
            exerciseName: 'Supino',
            bodyPart: BodyPart.chest,
            peakWeightKg: 80,
            peakReps: 8,
            xpContribution: 640,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {
          BodyPart.chest: 400,
          BodyPart.back: 200,
          BodyPart.legs: 100,
          BodyPart.arms: 50,
        },
        bpRankAfter: const {
          BodyPart.chest: 18,
          BodyPart.back: 12,
          BodyPart.legs: 9,
          BodyPart.arms: 14,
        },
      );

      await _pumpDebrief(tester, state: state);

      // 4 segments in the bar.
      final segments = tester
          .widgetList<XpSegmentedBar>(find.byType(XpSegmentedBar))
          .single;
      expect(segments.segments.length, 4);

      // 4 per-BP delta rows. Each rank text lives inside a Text.rich.
      expect(_hasRichTextSpan(tester, 'Rank 18'), isTrue);
      expect(_hasRichTextSpan(tester, 'Rank 12'), isTrue);
      expect(_hasRichTextSpan(tester, 'Rank 9'), isTrue);
      expect(_hasRichTextSpan(tester, 'Rank 14'), isTrue);
    });

    testWidgets(
      'PR 32g — long debrief (6 BPs trained) renders a 6-segment XP bar '
      'at 320dp without RenderFlex overflow',
      (tester) async {
        // Phase 32 PR 32g — pins the worst-case Mission Debrief layout:
        // every active body part trained in one session at the tightest
        // production viewport. The XpSegmentedBar grew from 4 (multi-BP
        // baseline) → 6 segments; verifies no Row overflow + that every
        // segment lays out.
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'a',
              exerciseName: 'Bench',
              bodyPart: BodyPart.chest,
              peakWeightKg: 80,
              peakReps: 8,
              xpContribution: 640,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'b',
              exerciseName: 'Row',
              bodyPart: BodyPart.back,
              peakWeightKg: 70,
              peakReps: 8,
              xpContribution: 560,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'c',
              exerciseName: 'Squat',
              bodyPart: BodyPart.legs,
              peakWeightKg: 100,
              peakReps: 5,
              xpContribution: 500,
              isPR: false,
            ),
            SessionLiftSummary(
              exerciseId: 'd',
              exerciseName: 'OHP',
              bodyPart: BodyPart.shoulders,
              peakWeightKg: 50,
              peakReps: 8,
              xpContribution: 400,
              isPR: false,
            ),
          ],
          bpXpDeltas: const {
            BodyPart.chest: 640,
            BodyPart.back: 560,
            BodyPart.legs: 500,
            BodyPart.shoulders: 400,
            BodyPart.arms: 200,
            BodyPart.core: 100,
          },
          bpRankAfter: const {
            BodyPart.chest: 12,
            BodyPart.back: 11,
            BodyPart.legs: 10,
            BodyPart.shoulders: 9,
            BodyPart.arms: 6,
            BodyPart.core: 4,
          },
        );

        await _pumpDebrief(
          tester,
          state: state,
          viewport: const Size(320, 1600),
        );

        // No RenderFlex overflow on the tightest production viewport.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Long Mission Debrief (6 BPs trained) overflowed at 320dp. '
              'Phase 32 PR 32g regression guard — see audit §3.4 "Long '
              'Mission Debrief 6-BP layout".',
        );
        // 6 segments laid out (one per active BP).
        final segments = tester
            .widgetList<XpSegmentedBar>(find.byType(XpSegmentedBar))
            .single;
        expect(segments.segments.length, 6);
      },
    );

    testWidgets('320dp viewport: 4 lift rows still render without overflow', (
      tester,
    ) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'a',
            exerciseName: 'Supino',
            bodyPart: BodyPart.chest,
            peakWeightKg: 80,
            peakReps: 8,
            xpContribution: 640,
            isPR: false,
          ),
          SessionLiftSummary(
            exerciseId: 'b',
            exerciseName: 'Inclinado',
            bodyPart: BodyPart.chest,
            peakWeightKg: 60,
            peakReps: 10,
            xpContribution: 600,
            isPR: false,
          ),
          SessionLiftSummary(
            exerciseId: 'c',
            exerciseName: 'Voador',
            bodyPart: BodyPart.chest,
            peakWeightKg: 40,
            peakReps: 12,
            xpContribution: 480,
            isPR: false,
          ),
          SessionLiftSummary(
            exerciseId: 'd',
            exerciseName: 'Crossover',
            bodyPart: BodyPart.chest,
            peakWeightKg: 25,
            peakReps: 12,
            xpContribution: 300,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {BodyPart.chest: 618},
        bpRankAfter: const {BodyPart.chest: 18},
        totalExercisesTrained: 5,
      );

      await _pumpDebrief(tester, state: state, viewport: const Size(320, 1200));

      // No layout overflow.
      expect(tester.takeException(), isNull);
      // Section still renders (4 rows + footer).
      expect(find.byType(LiftRow), findsNWidgets(4));
      expect(find.text('+1 outro exercício'), findsOneWidget);
    });

    testWidgets(
      'no-XP defensive: empty bpXpDeltas drops the XP bar + delta rows',
      (tester) async {
        final state = _buildState(
          topLifts: const [],
          bpXpDeltas: const {},
          bpRankAfter: const {},
          dominantBodyPart: BodyPart.chest,
        );

        // Manually override dominantBodyPart since helper infers from
        // bpXpDeltas which is empty here.
        final overridden = state.copyWith(
          dominantBodyPart: BodyPart.chest,
          dominantXpToNextRank: 120,
          dominantNextRank: 12,
        );

        await _pumpDebrief(tester, state: overridden);

        expect(find.byType(XpSegmentedBar), findsNothing);
        expect(find.byType(LiftRow), findsNothing);
      },
    );

    // -------------------------------------------------------------------------
    // Phase 31 round-2 Bugs F + G — XP hero block + structural divider
    // -------------------------------------------------------------------------

    testWidgets(
      'XP hero block: renders "+{totalXp} XP EARNED · CLASS_LABEL" as the '
      'first child (Phase 31 round-2 Bug F)',
      (tester) async {
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'supino',
              exerciseName: 'Supino reto',
              bodyPart: BodyPart.chest,
              peakWeightKg: 95,
              peakReps: 5,
              xpContribution: 800,
              isPR: true,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 340},
          bpRankAfter: const {BodyPart.chest: 18},
        );

        await _pumpDebrief(
          tester,
          state: state,
          localizations: _enLocalizations(),
          classLabel: 'Iron Sentinel',
        );

        // Hero numeric — "+340".
        expect(find.text('+340'), findsOneWidget);
        // Eyebrow label — pre-uppercased "XP EARNED".
        expect(find.text('XP EARNED'), findsOneWidget);
        // Class accent — uppercased at the call site by the widget.
        expect(find.text('IRON SENTINEL'), findsOneWidget);
      },
    );

    testWidgets(
      'XP hero block: hides when totalXpEarned == 0 (defensive — keeps the '
      'section self-safe outside the upstream sets > 0 gate)',
      (tester) async {
        final state = _buildState(
          topLifts: const [],
          bpXpDeltas: const {},
          bpRankAfter: const {},
          dominantBodyPart: BodyPart.chest,
        );
        final overridden = state.copyWith(
          dominantBodyPart: BodyPart.chest,
          dominantXpToNextRank: 120,
          dominantNextRank: 12,
        );

        await _pumpDebrief(
          tester,
          state: overridden,
          localizations: _enLocalizations(),
          classLabel: 'Iron Sentinel',
        );

        // No XP hero numeric.
        expect(find.text('+0'), findsNothing);
        // No "XP EARNED" eyebrow.
        expect(find.text('XP EARNED'), findsNothing);
      },
    );

    testWidgets('XP hero block: hides the class accent when classLabel is null '
        '(Initiate / day-zero — right column collapses cleanly)', (
      tester,
    ) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'supino',
            exerciseName: 'Supino',
            bodyPart: BodyPart.chest,
            peakWeightKg: 80,
            peakReps: 8,
            xpContribution: 640,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {BodyPart.chest: 200},
        bpRankAfter: const {BodyPart.chest: 4},
      );

      await _pumpDebrief(
        tester,
        state: state,
        localizations: _enLocalizations(),
        // classLabel intentionally omitted (Initiate path).
      );

      // Numeric + eyebrow still present.
      expect(find.text('+200'), findsOneWidget);
      expect(find.text('XP EARNED'), findsOneWidget);
      // Class accent absent — the right column collapses to the Spacer.
      // Negative pin via a known class string the test would otherwise
      // surface.
      expect(find.text('IRON SENTINEL'), findsNothing);
    });

    testWidgets('XP hero block: 320dp viewport does not overflow the Row '
        '(Phase 31 round-2 Bug F regression guard)', (tester) async {
      final state = _buildState(
        topLifts: const [
          SessionLiftSummary(
            exerciseId: 'supino',
            exerciseName: 'Supino',
            bodyPart: BodyPart.chest,
            peakWeightKg: 80,
            peakReps: 8,
            xpContribution: 640,
            isPR: false,
          ),
        ],
        bpXpDeltas: const {BodyPart.chest: 999},
        bpRankAfter: const {BodyPart.chest: 18},
      );

      await _pumpDebrief(
        tester,
        state: state,
        localizations: _enLocalizations(),
        classLabel: 'Iron Sentinel',
        viewport: const Size(320, 1200),
      );

      // No layout overflow on the tightest production viewport.
      expect(tester.takeException(), isNull);
      // Hero still renders.
      expect(find.text('+999'), findsOneWidget);
    });

    testWidgets(
      'XP hero block: longest realistic copy at 320dp does not overflow '
      '(round-3 36sp regression guard — "+10000 XP GANHO · DESBRAVADOR")',
      (tester) async {
        // Round-3 bumped the hero numeral from 22sp → 36sp, the eyebrow
        // from 11sp → 12sp, the class accent from 10sp → 11sp, and the
        // gap between numeric and eyebrow from 4dp → 6dp. The worst-case
        // intra-Row width grows materially; this guard pins that even
        // the longest realistic combination ("+10000" + "XP GANHO" +
        // longest pt class name "DESBRAVADOR") fits the tightest
        // production viewport without a RenderFlex overflow.
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'supino',
              exerciseName: 'Supino',
              bodyPart: BodyPart.chest,
              peakWeightKg: 80,
              peakReps: 8,
              xpContribution: 9000,
              isPR: false,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 10000},
          bpRankAfter: const {BodyPart.chest: 40},
        );

        await _pumpDebrief(
          tester,
          state: state,
          // pt localizations carry the "XP GANHO" eyebrow which is wider
          // than the en "XP EARNED" — pin the worst-case.
          localizations: _ptLocalizations(),
          // "Desbravador" is the longest pt class name (11 chars,
          // uppercases to "DESBRAVADOR").
          classLabel: 'Desbravador',
          viewport: const Size(320, 1200),
        );

        expect(
          tester.takeException(),
          isNull,
          reason:
              'No RenderFlex overflow on the tightest production viewport '
              'with the longest realistic XP + class-name combination.',
        );
        // All three text slots still render — verifies they were laid
        // out, not silently elided.
        expect(find.text('+10000'), findsOneWidget);
        expect(find.text('XP GANHO'), findsOneWidget);
        expect(find.text('DESBRAVADOR'), findsOneWidget);
      },
    );

    testWidgets(
      'structural divider renders between rank-delta rows and next-target '
      'callout (Phase 31 round-2 Bug G — visually separates blocks)',
      (tester) async {
        final state = _buildState(
          topLifts: const [
            SessionLiftSummary(
              exerciseId: 'supino',
              exerciseName: 'Supino',
              bodyPart: BodyPart.chest,
              peakWeightKg: 80,
              peakReps: 8,
              xpContribution: 640,
              isPR: false,
            ),
          ],
          bpXpDeltas: const {BodyPart.chest: 200},
          bpRankAfter: const {BodyPart.chest: 18},
        );

        await _pumpDebrief(tester, state: state);

        // Find the section's Column children and locate the Divider that
        // sits before the "PRÓXIMO PASSO" eyebrow. The Mission Debrief
        // owns ONE Divider — the structural rule above the next-target
        // callout.
        expect(
          find.byType(Divider),
          findsOneWidget,
          reason:
              'A Divider must render between the rank-delta rows and the '
              'next-target callout when both blocks are visible.',
        );
        // Next-target eyebrow is what the divider precedes.
        expect(find.text('PRÓXIMO PASSO'), findsOneWidget);
      },
    );
  });
}
