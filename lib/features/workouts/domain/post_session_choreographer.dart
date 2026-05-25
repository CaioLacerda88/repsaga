import '../../personal_records/domain/pr_detection_service.dart';
import '../../rpg/domain/celebration_queue.dart';
import '../../rpg/models/body_part.dart';
import '../../rpg/models/celebration_event.dart';
import 'pr_score.dart';
import 'reward_tier.dart';

/// One frame of the post-session cinematic.
///
/// Discriminated union so the screen's `AnimatedSwitcher` can render the
/// correct cut widget per variant. **Pure data:** no widgets, no
/// `BuildContext`, no Riverpod — the choreographer produces this list
/// and the screen layer renders.
sealed class PostSessionCut {
  const PostSessionCut();
}

/// Beat 1 — the XP slam + tier-aware copy. Always the first cut.
class B1XpCut extends PostSessionCut {
  const B1XpCut({
    required this.tier,
    required this.totalXp,
    required this.newCharacterLevel,
    required this.baselineCopyVariant,
  });

  final RewardTier tier;
  final int totalXp;

  /// Non-null when the queue carried a [LevelUpEvent] OR when the
  /// max-combo state's level-up should be announced. Used by the Max
  /// variant copy "NÍVEL 23. A SAGA CONTINUA.".
  final int? newCharacterLevel;

  /// Only meaningful when `tier == RewardTier.baseline`.
  final BaselineCopyVariant baselineCopyVariant;
}

/// Beat 2 single-BP cut (Variant A — focused session, exactly 1 BP).
class B2SingleBpCut extends PostSessionCut {
  const B2SingleBpCut({
    required this.bodyPart,
    required this.xpEarned,
    required this.progressFractionAfter,
    required this.rankAfter,
    required this.isFirstAwakening,
  });

  final BodyPart bodyPart;
  final int xpEarned;
  final double progressFractionAfter;
  final int rankAfter;

  /// True when this body part transitioned from "never trained" to
  /// "trained" this session. Drives the "Peito · Desperto" eyebrow per
  /// mockup §5 State 1.
  final bool isFirstAwakening;
}

/// Beat 2 sequential dominant cut (Variant B — exactly 2 BPs, this is the
/// first cut). 1000ms hold.
class B2SequentialDominantCut extends PostSessionCut {
  const B2SequentialDominantCut({
    required this.bodyPart,
    required this.xpEarned,
    required this.progressFractionAfter,
  });

  final BodyPart bodyPart;
  final int xpEarned;
  final double progressFractionAfter;
}

/// Beat 2 sequential secondary cut (Variant B — exactly 2 BPs, this is the
/// second cut). 800ms hold.
class B2SequentialSecondaryCut extends PostSessionCut {
  const B2SequentialSecondaryCut({
    required this.bodyPart,
    required this.xpEarned,
    required this.progressFractionAfter,
  });

  final BodyPart bodyPart;
  final int xpEarned;
  final double progressFractionAfter;
}

/// Beat 2 cascade cut (Variant C — 3+ BPs). Hero BP at top + cascade rows
/// below. Truncates at 4 rows with "+N mais" pill when ≥6 BPs trained.
class B2CascadeCut extends PostSessionCut {
  const B2CascadeCut({
    required this.heroBodyPart,
    required this.heroXp,
    required this.heroProgressFractionAfter,
    required this.cascadeRows,
    required this.truncatedCount,
  });

  final BodyPart heroBodyPart;
  final int heroXp;
  final double heroProgressFractionAfter;

  /// Up to 4 rows in the cascade below the hero. Mockup §3 Variant C.
  final List<CascadeRow> cascadeRows;

  /// Count of body parts NOT shown in [cascadeRows] (renders as
  /// "+N mais" pill). Zero when all trained BPs fit.
  final int truncatedCount;
}

class CascadeRow {
  const CascadeRow({required this.bodyPart, required this.xpEarned});
  final BodyPart bodyPart;
  final int xpEarned;
}

/// Beat 2 elevated cut (Variant D — rank-up fusion). Bar fills past 100%
/// → reset → rank slam. 1100ms hold.
class B2ElevatedRankUpCut extends PostSessionCut {
  const B2ElevatedRankUpCut({
    required this.bodyPart,
    required this.newRank,
    required this.xpEarnedForBodyPart,
  });

  final BodyPart bodyPart;
  final int newRank;
  final int xpEarnedForBodyPart;
}

/// Beat 3 PR cut (single OR multi). Hero PR + up to 3 pill rows + "+N mais".
class B3PrCut extends PostSessionCut {
  const B3PrCut({
    required this.heroExerciseName,
    required this.heroWeightKg,
    required this.heroReps,
    required this.pillRows,
    required this.truncatedPillCount,
  });

  final String heroExerciseName;
  final double heroWeightKg;
  final int heroReps;

  /// Up to 3 pill rows for additional PRs. Mockup §4 PR multi.
  final List<PrPillRow> pillRows;

  /// PR count not shown in [pillRows] (renders as "+N mais" pill).
  final int truncatedPillCount;
}

class PrPillRow {
  const PrPillRow({
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
  });
  final String exerciseName;
  final double weightKg;
  final int reps;
}

/// Beat 3 title-unlock cut. Hue-typed flood — no white flash.
class B3TitleCut extends PostSessionCut {
  const B3TitleCut({required this.titleSlug, required this.variant});
  final String titleSlug;
  final TitleCutVariant variant;
}

/// Drives the flood color for the title cut. Mockup §4 Title:
/// `BP-title` → body-part hue; `crossBuild` → hotViolet;
/// `characterLevel` → heroGold.
enum TitleCutVariant { bodyPartTyped, crossBuild, characterLevel }

/// Beat 3 class-change cut. Full Concept B 1.5s ceremony.
class B3ClassChangeCut extends PostSessionCut {
  const B3ClassChangeCut({required this.toClassSlug});
  final String toClassSlug;
}

/// Choreographs the post-session cut sequence (Decoupling Rule 1 — pure).
///
/// Given a workout-finish snapshot, returns the ordered [List]<[PostSessionCut]>
/// the screen renders via `AnimatedSwitcher`. Mockup §5 State 1-10 storyboards
/// are the implementation guide; each test fixture in
/// `post_session_choreographer_test.dart` pins one state's cut count + cut
/// types + dominant-BP selection.
///
/// **No Riverpod, no `BuildContext`, no IO.** Unit-testable from a plain
/// `flutter test` without harness.
class PostSessionChoreographer {
  const PostSessionChoreographer._();

  /// Maximum cascade rows below the hero before truncation. Mockup §3
  /// Variant C: "If 5–6 BPs trained, cascade still works — top 1 hero +
  /// cascade list up to 4 rows (truncation at 4 with '+N mais' pill)."
  static const int maxCascadeRows = 4;

  /// Maximum PR pills shown in the multi-PR roll-up before truncation.
  /// Mockup §4 PR multi: "Three pills max on the roll-up; a 5+-PR session
  /// shows 3 pills + '+N mais' pill."
  static const int maxPrPillRows = 3;

  /// Build the cinematic sequence.
  ///
  /// **Inputs (all snapshot data):**
  ///   * [tier] — from [RewardTier.derive].
  ///   * [queueResult] — celebration queue.
  ///   * [bpXpDeltas] — `{BodyPart: xpEarnedThisSession}`. From the post-
  ///     vs-pre snapshot diff (or from the active workout's set log when
  ///     available). Empty BPs are omitted.
  ///   * [bpRankAfter] — `{BodyPart: rankAfterSave}` for each BP in
  ///     [bpXpDeltas].
  ///   * [bpProgressFractionAfter] — `{BodyPart: 0.0-1.0}` rank-progress
  ///     fraction after the save.
  ///   * [bpFirstAwakening] — BPs that crossed "never trained" → "trained"
  ///     this session. Empty in the common path.
  ///   * [prResult] — `PRDetectionResult` from the finish flow. `null` or
  ///     `hasNewRecords == false` means no PR cut fires.
  ///   * [exerciseNames] — `{exerciseId: localizedName}` for the PR cut
  ///     hero + pill rows.
  ///   * [newCharacterLevel] — non-null when the queue carried a
  ///     [LevelUpEvent] (drives B1's "NÍVEL X." copy via the Max variant).
  ///   * [priorFinishedWorkoutCount] — drives the baseline copy
  ///     alternation seed.
  static List<PostSessionCut> build({
    required RewardTier tier,
    required CelebrationQueueResult queueResult,
    required Map<BodyPart, int> bpXpDeltas,
    required Map<BodyPart, int> bpRankAfter,
    required Map<BodyPart, double> bpProgressFractionAfter,
    required Set<BodyPart> bpFirstAwakening,
    required PRDetectionResult? prResult,
    required Map<String, String> exerciseNames,
    required int? newCharacterLevel,
    required int priorFinishedWorkoutCount,
    required int totalXpEarned,
  }) {
    final cuts = <PostSessionCut>[];

    // ── Beat 1: always present ─────────────────────────────────────────
    cuts.add(
      B1XpCut(
        tier: tier,
        totalXp: totalXpEarned,
        newCharacterLevel: newCharacterLevel,
        baselineCopyVariant: tier.baselineCopyVariant(
          priorFinishedWorkoutCount: priorFinishedWorkoutCount,
        ),
      ),
    );

    // ── Beat 2: skipped entirely on class-change-only state (State 9). ─
    //
    // Mockup §5 State 9: "Beat 2 is skipped entirely — running BP cards
    // before a class change dilutes its identity-defining gravity."
    //
    // Class change WITH rank-up (e.g. max-combo State 10) keeps B2 as
    // an elevated rank-up cut — the rank-up is the load-bearing BP beat.
    final hasClassChange = queueResult.queue.any((e) => e is ClassChangeEvent);
    final rankUpEvents = queueResult.queue.whereType<RankUpEvent>().toList();
    final hasRankUp = rankUpEvents.isNotEmpty;
    final skipBeat2 = hasClassChange && !hasRankUp;

    if (!skipBeat2) {
      _appendBeat2(
        cuts: cuts,
        bpXpDeltas: bpXpDeltas,
        bpRankAfter: bpRankAfter,
        bpProgressFractionAfter: bpProgressFractionAfter,
        bpFirstAwakening: bpFirstAwakening,
        rankUpEvents: rankUpEvents,
        prResult: prResult,
      );
    }

    // ── Beat 3: max 2 cuts. ───────────────────────────────────────────
    //
    // Mockup §4 invariants:
    //   - Rank-up is absorbed by B2 elevated (no separate B3 cut).
    //   - Level-up is absorbed by B1 copy (no separate B3 cut).
    //   - Remaining B3 event types: PR, title, class change.
    //   - PR + class change is the only legitimate two-cut B3 combo
    //     (PR first as escalation, class change last as scene-ender).
    //   - Title + class change → title becomes a 1s non-bleed pill on top
    //     of the class-change overlay (not a separate cut). Title's
    //     summary-panel EQUIP row covers the rest.

    final hasPr = prResult != null && prResult.hasNewRecords;
    if (hasPr) {
      cuts.add(_buildPrCut(prResult, exerciseNames));
    }

    final titleEvents = queueResult.queue
        .whereType<TitleUnlockEvent>()
        .toList();
    if (titleEvents.isNotEmpty && !hasClassChange) {
      // Title-only OR title+PR: show a B3 title cut. When class-change also
      // fires, the title becomes a non-bleed pill on the class-change cut —
      // do NOT add a B3 title cut.
      // For 30a we render the first title; multi-title surfaces on the
      // summary panel (mockup §5 State 8 shows single-title flow only).
      cuts.add(_buildTitleCut(titleEvents.first));
    }

    if (hasClassChange) {
      final cc = queueResult.queue.whereType<ClassChangeEvent>().first;
      cuts.add(B3ClassChangeCut(toClassSlug: cc.toClass.slug));
    }

    return cuts;
  }

  static void _appendBeat2({
    required List<PostSessionCut> cuts,
    required Map<BodyPart, int> bpXpDeltas,
    required Map<BodyPart, int> bpRankAfter,
    required Map<BodyPart, double> bpProgressFractionAfter,
    required Set<BodyPart> bpFirstAwakening,
    required List<RankUpEvent> rankUpEvents,
    required PRDetectionResult? prResult,
  }) {
    // Defensive: if there are no per-BP deltas, there's nothing to render
    // (e.g. a synthetic test fixture). Skip B2 silently rather than emit
    // an empty cut.
    if (bpXpDeltas.isEmpty) return;

    // Dominant BP selection: highest XP → highest current rank → alphabetical
    // (mockup §3 Variant C "Dominant BP selection").
    final sortedBps = bpXpDeltas.keys.toList()
      ..sort((a, b) {
        final xpCmp = bpXpDeltas[b]!.compareTo(bpXpDeltas[a]!);
        if (xpCmp != 0) return xpCmp;
        final rankCmp = (bpRankAfter[b] ?? 1).compareTo(bpRankAfter[a] ?? 1);
        if (rankCmp != 0) return rankCmp;
        return a.dbValue.compareTo(b.dbValue);
      });

    // Variant D (elevated rank-up): when any rank-up fires, the top-ranked
    // rank-up gets the elevated treatment regardless of co-occurring PR
    // (mockup §5 State 10 max-combo: "rank-up promotes to B2 elevated").
    //
    // When 3+ BPs trained AND a rank-up exists, mockup §5 State 6 shows
    // the cascade FIRST, then the elevated rank-up. State 5 (single BP +
    // rank-up) is just the elevated cut.
    final hasPr = prResult != null && prResult.hasNewRecords;
    if (rankUpEvents.isNotEmpty) {
      // Pick the top rank-up (highest newRank — same ordering the
      // celebration queue applies).
      final topRankUp = rankUpEvents.reduce(
        (a, b) => a.newRank >= b.newRank ? a : b,
      );

      if (sortedBps.length >= 3) {
        cuts.add(
          _buildCascadeCut(sortedBps, bpXpDeltas, bpProgressFractionAfter),
        );
      }
      cuts.add(
        B2ElevatedRankUpCut(
          bodyPart: topRankUp.bodyPart,
          newRank: topRankUp.newRank,
          xpEarnedForBodyPart: bpXpDeltas[topRankUp.bodyPart] ?? 0,
        ),
      );
      return;
    }

    // PR-anchored single-BP B2 (no rank-up): focus on the dominant BP
    // (PR's home muscle bubbles to the top via the XP-descending sort
    // because the PR exercise's sets are the highest XP contributors).
    // Mockup §5 State 3: "Beat 2 stays at 1 BP (the PR's muscle) when a PR
    // fires." This holds because we render only the dominant BP.
    if (hasPr) {
      final dominant = sortedBps.first;
      cuts.add(
        B2SingleBpCut(
          bodyPart: dominant,
          xpEarned: bpXpDeltas[dominant]!,
          progressFractionAfter: bpProgressFractionAfter[dominant] ?? 0.0,
          rankAfter: bpRankAfter[dominant] ?? 1,
          isFirstAwakening: bpFirstAwakening.contains(dominant),
        ),
      );
      return;
    }

    // No PR, no rank-up — pick by BP count.
    if (sortedBps.length == 1) {
      // Variant A
      final bp = sortedBps.first;
      cuts.add(
        B2SingleBpCut(
          bodyPart: bp,
          xpEarned: bpXpDeltas[bp]!,
          progressFractionAfter: bpProgressFractionAfter[bp] ?? 0.0,
          rankAfter: bpRankAfter[bp] ?? 1,
          isFirstAwakening: bpFirstAwakening.contains(bp),
        ),
      );
    } else if (sortedBps.length == 2) {
      // Variant B (sequential — dominant first, secondary second)
      final dominant = sortedBps[0];
      final secondary = sortedBps[1];
      cuts.add(
        B2SequentialDominantCut(
          bodyPart: dominant,
          xpEarned: bpXpDeltas[dominant]!,
          progressFractionAfter: bpProgressFractionAfter[dominant] ?? 0.0,
        ),
      );
      cuts.add(
        B2SequentialSecondaryCut(
          bodyPart: secondary,
          xpEarned: bpXpDeltas[secondary]!,
          progressFractionAfter: bpProgressFractionAfter[secondary] ?? 0.0,
        ),
      );
    } else {
      // Variant C (cascade)
      cuts.add(
        _buildCascadeCut(sortedBps, bpXpDeltas, bpProgressFractionAfter),
      );
    }
  }

  static B2CascadeCut _buildCascadeCut(
    List<BodyPart> sortedBps,
    Map<BodyPart, int> bpXpDeltas,
    Map<BodyPart, double> bpProgressFractionAfter,
  ) {
    final hero = sortedBps.first;
    final remaining = sortedBps.skip(1).toList();
    final visible = remaining.take(maxCascadeRows).toList();
    final truncated = remaining.length - visible.length;

    return B2CascadeCut(
      heroBodyPart: hero,
      heroXp: bpXpDeltas[hero]!,
      heroProgressFractionAfter: bpProgressFractionAfter[hero] ?? 0.0,
      cascadeRows: [
        for (final bp in visible)
          CascadeRow(bodyPart: bp, xpEarned: bpXpDeltas[bp]!),
      ],
      truncatedCount: truncated,
    );
  }

  static B3PrCut _buildPrCut(
    PRDetectionResult prResult,
    Map<String, String> exerciseNames,
  ) {
    // Hero PR selection: highest weight × reps. Deterministic tiebreak:
    // alphabetical exercise name. Mockup §5 State 4 script.
    final records = [...prResult.newRecords];
    records.sort((a, b) {
      final aScore = prScore(a);
      final bScore = prScore(b);
      final cmp = bScore.compareTo(aScore);
      if (cmp != 0) return cmp;
      // Tiebreak by exercise name (alphabetical, deterministic).
      final aName = exerciseNames[a.exerciseId] ?? a.exerciseId;
      final bName = exerciseNames[b.exerciseId] ?? b.exerciseId;
      return aName.compareTo(bName);
    });

    final hero = records.first;
    final rest = records.skip(1).toList();
    final pills = rest.take(maxPrPillRows).toList();
    final truncated = rest.length - pills.length;

    return B3PrCut(
      heroExerciseName: exerciseNames[hero.exerciseId] ?? hero.exerciseId,
      heroWeightKg: hero.value,
      heroReps: hero.reps ?? 0,
      pillRows: [
        for (final pr in pills)
          PrPillRow(
            exerciseName: exerciseNames[pr.exerciseId] ?? pr.exerciseId,
            weightKg: pr.value,
            reps: pr.reps ?? 0,
          ),
      ],
      truncatedPillCount: truncated,
    );
  }

  static B3TitleCut _buildTitleCut(TitleUnlockEvent event) {
    // Variant selection by slug prefix is heuristic — the title catalog
    // would supply the variant in a richer model, but for 30a we ship a
    // simple prefix-based rule that covers the three catalog families
    // (body-part / character-level / cross-build). The summary panel
    // resolves the catalog entry separately for the EQUIP row's display.
    //
    // **Why a slug-prefix heuristic and not a catalog lookup:** the
    // choreographer is pure (no Riverpod / no catalog provider). A future
    // refactor that wires the title catalog through can replace this with
    // a richer payload — and the test suite will catch the regression
    // because the variant currently asserts directly on the slug shape.
    final slug = event.slug;
    final TitleCutVariant variant;
    if (slug.startsWith('level_') ||
        slug.startsWith('character_level_') ||
        slug.startsWith('lvl_')) {
      variant = TitleCutVariant.characterLevel;
    } else if (slug.startsWith('pillar_walker') ||
        slug.startsWith('broad_shouldered') ||
        slug.startsWith('even_handed') ||
        slug.startsWith('iron_bound') ||
        slug.startsWith('saga_forged')) {
      variant = TitleCutVariant.crossBuild;
    } else {
      // Body-part titles dominate the catalog (78/90 entries).
      variant = TitleCutVariant.bodyPartTyped;
    }
    return B3TitleCut(titleSlug: slug, variant: variant);
  }
}
