import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/muscle_group_body_part.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../exercises/models/exercise.dart';
import '../../../personal_records/domain/pr_detection_service.dart';
import '../../../rpg/domain/celebration_queue.dart';
import '../../../rpg/domain/rank_curve.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/providers/rpg_progress_provider.dart';
import '../../../rpg/ui/widgets/body_part_localization.dart';
import '../../domain/conditioning_charge.dart';
import '../../domain/post_session_choreographer.dart';
import '../../domain/reward_tier.dart';
import '../../domain/session_cardio_summary.dart';
import '../../domain/session_lift_summary.dart';
import '../../models/active_workout_state.dart';
import '../../providers/workout_history_providers.dart';
import '../../utils/cardio_format.dart';
import '../../utils/set_filters.dart';
import 'post_session_state.dart';

/// Params for [PostSessionController].
///
/// Carried through the GoRouter `state.extra` envelope so we don't need
/// to round-trip via Riverpod-cached side state. The post-session route
/// is push-only + ephemeral (mockup §5 + WIP.md acceptance #7).
class PostSessionParams {
  const PostSessionParams({
    required this.queueResult,
    required this.prResult,
    required this.exerciseNames,
    required this.totalXpEarned,
    required this.bpXpDeltas,
    required this.bpProgressFractionPre,
    required this.bpRankBefore,
    required this.bpVitalityBefore,
    required this.bpFirstAwakening,
    required this.priorFinishedWorkoutCount,
    required this.durationMinutes,
    required this.setsCount,
    required this.tonnageTons,
    required this.l10n,
    this.exercises = const [],
  });

  final CelebrationQueueResult queueResult;
  final PRDetectionResult? prResult;
  final Map<String, String> exerciseNames;
  final int totalXpEarned;
  final Map<BodyPart, int> bpXpDeltas;

  /// Pre-finish per-body-part rank-progress fraction (`xpInRank /
  /// xpToNext`, clamped to [0, 1]). Captured by
  /// [FinishWorkoutCoordinator] from `rpgProgressProvider` BEFORE
  /// awaiting `notifier.finishWorkout()` — same `ref`-lifetime contract
  /// as [bpRankBefore] (post-await reads would either throw or see the
  /// post-save snapshot, both of which break the B2 tally-cut beat).
  ///
  /// Drives the B2 tally-cut bars' starting position: each per-BP bar
  /// animates from the user's prior rank-progress fraction up to the
  /// post-finish fraction the controller derives from the refreshed
  /// snapshot. Restores the mockup §3 Variant A storyboard's "watch
  /// your prior progress get added to" beat.
  ///
  /// Body parts the user has never trained server-side have no row in
  /// the snapshot and so are absent from this map; the controller
  /// falls back to a sane default (typically 0.0) for those when
  /// projecting the B2 cuts. PR 33c finding-005.
  final Map<BodyPart, double> bpProgressFractionPre;

  /// Pre-finish per-body-part rank snapshot. Captured by
  /// [FinishWorkoutCoordinator] from `rpgProgressProvider` BEFORE
  /// awaiting `notifier.finishWorkout()`. Plumbed through to
  /// [PostSessionState.bpRankBefore] so the Mission Debrief can render
  /// accurate multi-rank-jump arrows (`Rank 5 → 8`). Phase 31 Blocker 1.
  final Map<BodyPart, int> bpRankBefore;

  /// Pre-finish per-body-part vitality `(ewma, peak, refPeak)` snapshot.
  /// Captured by [FinishWorkoutCoordinator] from `rpgProgressProvider`
  /// BEFORE awaiting `notifier.finishWorkout()` (same `ref`-lifetime
  /// contract as [bpRankBefore]). Threaded to
  /// [PostSessionState.conditioningCharge] as the BEFORE side of the
  /// "Conditioning charged" debrief beat; the controller derives the AFTER
  /// side from the post-save snapshot it reads in `_buildInitial`. The
  /// `refPeak` (`vitality_ref_peak`, decaying reference peak) is the charge-
  /// fraction denominator. Body parts the user has never charged
  /// (`refPeak == 0`) or never trained server-side are absent — the per-bp
  /// roll-up excludes them. Phase Vitality-2.
  final Map<BodyPart, ({double ewma, double peak, double refPeak})>
  bpVitalityBefore;
  final Set<BodyPart> bpFirstAwakening;
  final int priorFinishedWorkoutCount;
  final int durationMinutes;
  final int setsCount;
  final double tonnageTons;

  /// Pre-finish snapshot of the workout's exercises + sets. Captured by
  /// [FinishWorkoutCoordinator] BEFORE `await notifier.finishWorkout()`
  /// disposes the active-workout State. Drives `topLifts` projection on
  /// `PostSessionState`. Defaults empty so legacy test fixtures and
  /// pass-through flows that don't need the debrief table can omit it.
  ///
  /// Phase 31 Pass 1.
  final List<ActiveWorkoutExercise> exercises;

  /// The active `AppLocalizations` instance from the route container's
  /// context. Passed in so the controller resolves body-part labels
  /// + class-name labels once at build time, then the cut widgets read
  /// them as plain strings (Decoupling Rule 2).
  final AppLocalizations l10n;
}

/// Post-session state machine (Decoupling Rule 4 — separated from
/// rendering).
///
/// **Why a ChangeNotifier + not a Riverpod family Notifier:** Riverpod 3
/// dropped the manual `StateNotifierProvider` family API; the codegen
/// `@riverpod` family form requires hashable params (the `AppLocalizations`
/// instance + the `PostSessionParams` aggregate are not hashable). The
/// post-session controller is genuinely screen-scoped state — it lives
/// for the duration of one route push and disposes when the screen pops.
/// A plain `ChangeNotifier` owned by the screen's State (with `initState` /
/// `dispose` as the lifecycle anchor) satisfies the separation-of-concerns
/// requirement without dragging in Riverpod plumbing the framework doesn't
/// readily support.
///
/// The Riverpod [Ref] is injected so the controller can read other
/// providers (`rpgProgressProvider`, `workoutCountProvider`) without
/// becoming an island.
class PostSessionController extends ChangeNotifier {
  PostSessionController({required this.ref, required this.params}) {
    _state = _buildInitial();
  }

  /// [WidgetRef] is the screen's State `ref`. Used to read other providers
  /// (`rpgProgressProvider`, `workoutCountProvider`) and invalidate them
  /// from CONTINUAR. Accepts WidgetRef (not bare Ref) because the
  /// controller is constructed inside the screen's `initState` where
  /// only WidgetRef is in scope.
  final WidgetRef ref;
  final PostSessionParams params;

  late PostSessionState _state;
  PostSessionState get state => _state;

  PostSessionState _buildInitial() {
    final tier = RewardTier.derive(
      queueResult: params.queueResult,
      priorFinishedWorkoutCount: params.priorFinishedWorkoutCount,
      hasPersonalRecord: params.prResult?.hasNewRecords ?? false,
    );

    final progress =
        ref.read(rpgProgressProvider).value ?? RpgProgressSnapshot.empty;

    final bpRankAfter = <BodyPart, int>{};
    final bpProgressAfter = <BodyPart, double>{};
    // AFTER-side vitality snapshot for the "Conditioning charged" beat —
    // read from the POST-save `rpgProgressProvider` snapshot (PR 1 makes
    // `save_workout` recompute vitality in-txn, so by the time
    // `refreshAfterSave()` resolves these rows carry the rebuilt ewma).
    // Reads the REAL refreshed provider value, never a local guess
    // (cluster: optimistic-ui-vs-async-provider).
    final bpVitalityAfter =
        <BodyPart, ({double ewma, double peak, double refPeak})>{};
    for (final bp in params.bpXpDeltas.keys) {
      final row = progress.byBodyPart[bp];
      bpRankAfter[bp] = row?.rank ?? 1;
      final totalXp = row?.totalXp ?? 0.0;
      bpProgressAfter[bp] = RankCurve.progressFraction(totalXp, row?.rank ?? 1);
      if (row != null) {
        bpVitalityAfter[bp] = (
          ewma: row.vitalityEwma,
          peak: row.vitalityPeak,
          refPeak: row.vitalityRefPeak,
        );
      }
    }

    // Per-body-part conditioning charge (clamp(ewma/refPeak) per trained
    // bp, ordered delta-desc). Renders whenever any trained bp has charge
    // data (so an all-maxed session still shows) OR the once-per-day guard
    // blocked the step (surfaces "já carregado hoje"); hides only on true
    // day-zero / no-charge-data.
    final conditioningCharge = ConditioningCharge.fromSnapshots(
      trainedBodyParts: params.bpXpDeltas.keys,
      before: params.bpVitalityBefore,
      after: bpVitalityAfter,
    );

    // SINGLE charge source: the cinematic B2 rune end-cap reads the SAME
    // per-bp charge the summary rune strip renders — derived here from the
    // one `conditioningCharge` model above, never recomputed (no drift).
    // A bp absent from this map has no charge data; its B2 cut renders
    // without the rune (the fuse is additive). Phase Vitality-2 S4.
    final bpCharge =
        <BodyPart, ({double afterPct, bool isMax, int deltaPercent})>{
          for (final part in conditioningCharge.parts)
            part.bodyPart: (
              afterPct: part.afterPct,
              isMax: part.isMax,
              deltaPercent: part.deltaPercentInt,
            ),
        };

    final levelUpEvent = params.queueResult.queue
        .whereType<LevelUpEvent>()
        .firstOrNull;
    final newCharacterLevel = levelUpEvent?.newLevel;

    final cuts = PostSessionChoreographer.build(
      tier: tier,
      queueResult: params.queueResult,
      bpXpDeltas: params.bpXpDeltas,
      bpRankAfter: bpRankAfter,
      bpProgressFractionAfter: bpProgressAfter,
      bpFirstAwakening: params.bpFirstAwakening,
      bpCharge: bpCharge,
      prResult: params.prResult,
      exerciseNames: params.exerciseNames,
      newCharacterLevel: newCharacterLevel,
      priorFinishedWorkoutCount: params.priorFinishedWorkoutCount,
      totalXpEarned: params.totalXpEarned,
    );

    BodyPart? dominantBp;
    if (params.bpXpDeltas.isNotEmpty) {
      final sorted = params.bpXpDeltas.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      dominantBp = sorted.first.key;
    }

    int? dominantNextRank;
    int? dominantXpToNextRank;
    if (dominantBp != null) {
      final row = progress.byBodyPart[dominantBp];
      final rank = row?.rank ?? 1;
      final totalXp = row?.totalXp ?? 0.0;
      final remaining = RankCurve.xpToNextRank(totalXp, rank).round();
      if (remaining > 0) {
        dominantNextRank = rank + 1;
        dominantXpToNextRank = remaining;
      }
    }

    int? ranksToNextLevel;
    int? nextLevel;
    if (newCharacterLevel != null) {
      var activeRankSum = 0;
      var activeCount = 0;
      for (final bp in activeBodyParts) {
        final row = progress.byBodyPart[bp];
        activeRankSum += row?.rank ?? 1;
        activeCount += 1;
      }
      final ranksSinceLevelBase =
          (activeRankSum - activeCount) - (newCharacterLevel - 1) * 4;
      final remaining = 4 - ranksSinceLevelBase;
      ranksToNextLevel = remaining < 1 ? 1 : (remaining > 4 ? 4 : remaining);
      nextLevel = newCharacterLevel + 1;
    }

    // The cardio entry uses the conditioning STAT label (`cardioTrackLabel`
    // = "Conditioning") so the cardio rank-up celebration eyebrow reads
    // "CONDITIONING", matching the Saga rail + vitality table. The generic
    // `localizedBodyPartName(cardio)` returns "Cardio" (the exercise-picker
    // muscle-group name), which is the wrong register for this stat surface.
    // Per the `cardioTrackLabel` dartdoc. Strength parts keep their
    // muscle-group name. Cluster: slug-rendered-as-display-name.
    final bodyPartLabels = <BodyPart, String>{
      for (final bp in BodyPart.values)
        bp: bp == BodyPart.cardio
            ? params.l10n.cardioTrackLabel
            : localizedBodyPartName(bp, params.l10n),
    };

    final sagaNumber = params.priorFinishedWorkoutCount + 1;

    final topLifts = _projectTopLifts(
      exercises: params.exercises,
      prResult: params.prResult,
      exerciseNames: params.exerciseNames,
    );

    // Count of exercises that had at least one completed working set.
    // Drives the "+N more exercises" footer in the S2 Mission Debrief
    // (rendered when this count exceeds `topLifts.length`).
    var totalExercisesTrained = 0;
    for (final entry in params.exercises) {
      if (completedWorkingSets(entry.sets).isNotEmpty) {
        totalExercisesTrained++;
      }
    }

    // Phase 38d — did this session include a completed cardio entry? Cardio
    // earns no `BodyPart.cardio` XP delta (its XP path is separate from the
    // strength `bpXpDeltas`), so the only reliable signal is the pre-finish
    // exercise snapshot. Gates the one-time post-session "set your age"
    // nudge in the screen layer.
    final hadCardio = params.exercises.any(
      (e) => e.cardioSession?.isCompleted ?? false,
    );

    // Phase 38e — project completed cardio entries for the S2 Mission Debrief
    // ledger. Unit-agnostic (raw meters / seconds + canonical per-km pace);
    // the section/screen format to the profile distance unit at paint time.
    final cardioEntries = _projectCardioEntries(
      exercises: params.exercises,
      exerciseNames: params.exerciseNames,
    );

    // Defensive: for any BP that earned XP but is missing from
    // `params.bpRankBefore` (e.g. legacy fixtures, pre-Blocker-1 callers),
    // fall back to `bpRankAfter - 1` clamped to 1. The fallback only ever
    // takes effect on test fixtures that don't exercise the multi-rank-
    // jump path — production always plumbs the snapshot through the
    // coordinator.
    final bpRankBeforeResolved = <BodyPart, int>{
      for (final bp in params.bpXpDeltas.keys)
        bp:
            params.bpRankBefore[bp] ??
            ((bpRankAfter[bp] ?? 1) - 1).clamp(1, 999),
    };

    return PostSessionState(
      tier: tier,
      queueResult: params.queueResult,
      prResult: params.prResult,
      cuts: cuts,
      cutIndex: 0,
      showSummary: cuts.isEmpty,
      bodyPartLabels: bodyPartLabels,
      exerciseNames: params.exerciseNames,
      bpProgressFractionAfter: bpProgressAfter,
      bpXpDeltas: Map.unmodifiable(params.bpXpDeltas),
      bpRankAfter: Map.unmodifiable(bpRankAfter),
      bpRankBefore: Map.unmodifiable(bpRankBeforeResolved),
      topLifts: List.unmodifiable(topLifts),
      cardioEntries: List.unmodifiable(cardioEntries),
      totalExercisesTrained: totalExercisesTrained,
      totalXpEarned: params.totalXpEarned,
      priorFinishedWorkoutCount: params.priorFinishedWorkoutCount,
      sagaNumber: sagaNumber,
      durationMinutes: params.durationMinutes,
      setsCount: params.setsCount,
      tonnageTons: params.tonnageTons,
      dominantBodyPart: dominantBp,
      dominantXpToNextRank: dominantXpToNextRank,
      dominantNextRank: dominantNextRank,
      ranksToNextLevel: ranksToNextLevel,
      nextLevel: nextLevel,
      hadCardio: hadCardio,
      conditioningCharge: conditioningCharge,
    );
  }

  /// Project the session's exercises into ranked [SessionLiftSummary] rows.
  ///
  /// **Ranking (mirrors `PostSessionChoreographer._buildPrCut`):**
  ///   1. `xpContribution` descending.
  ///   2. Alphabetical exercise name ascending (deterministic tiebreak).
  ///
  /// Returns at most [_maxTopLifts] rows. The "+N more exercises" footer
  /// the screen renders is derived by comparing the returned list's length
  /// against the total exercises trained — that comparison lives in the
  /// widget layer, not here.
  ///
  /// **Peak set selection per exercise** mirrors the shared `prScore` rule
  /// (`weight × reps`). Ties broken by max weight then max reps. Returns
  /// `(0, 0)` when an exercise has no completed working sets — those
  /// exercises are dropped from the result (no point rendering a 0×0 row).
  ///
  /// **`xpContribution` is an approximation** (Pass 1):
  ///   * Per-set volume = `(weight ?? 0) × (reps ?? 0)`.
  ///   * Per-exercise volume share toward each BP is weighted by the
  ///     exercise's `xpAttribution` map (or 1.0 to the muscle-group-derived
  ///     BP when attribution is null — matches the engagement-counting
  ///     fallback in `primaryBodyPartsForSet`).
  ///   * The total volume across all sets serves as the relative ranking
  ///     key. Volume preserves order for the sort + top-K policy, which
  ///     is all the field drives in Pass 3.
  ///   * A precise per-exercise XP attribution would require the
  ///     finisher's RPC return shape to surface per-exercise XP; Pass 3
  ///     can refine if the mockup demands the exact XP value visible on
  ///     the row.
  static List<SessionLiftSummary> _projectTopLifts({
    required List<ActiveWorkoutExercise> exercises,
    required PRDetectionResult? prResult,
    required Map<String, String> exerciseNames,
  }) {
    if (exercises.isEmpty) return const [];

    final prExerciseIds = <String>{
      if (prResult != null)
        for (final r in prResult.newRecords) r.exerciseId,
    };

    final rows = <SessionLiftSummary>[];
    for (final entry in exercises) {
      final exercise = entry.workoutExercise.exercise;
      if (exercise == null) continue;
      final exerciseId = entry.workoutExercise.exerciseId;
      final workingSets = completedWorkingSets(entry.sets);
      if (workingSets.isEmpty) continue;

      // Peak set — max by prScore (weight × reps), tiebreak max weight,
      // then max reps. Stable selection so re-projecting the same data
      // produces the same row.
      double bestScore = -1;
      double bestWeight = 0;
      int bestReps = 0;
      double totalVolume = 0;
      for (final set in workingSets) {
        final w = set.weight ?? 0;
        final r = (set.reps ?? 0).toDouble();
        final score = w * r;
        totalVolume += score;
        if (score > bestScore ||
            (score == bestScore && w > bestWeight) ||
            (score == bestScore && w == bestWeight && r > bestReps)) {
          bestScore = score;
          bestWeight = w;
          bestReps = r.round();
        }
      }
      if (bestScore < 0) continue;

      // Dominant BP for this exercise — max share in xpAttribution, or
      // fall back to MuscleGroup → BodyPart mapping. Defensive: if both
      // resolve to null (cardio + no attribution), skip the row.
      final bodyPart = _dominantBodyPartFor(exercise);
      if (bodyPart == null) continue;

      rows.add(
        SessionLiftSummary(
          exerciseId: exerciseId,
          exerciseName: exerciseNames[exerciseId] ?? exercise.name,
          bodyPart: bodyPart,
          peakWeightKg: bestWeight,
          peakReps: bestReps,
          // Approximation — see method doc. Round to int so the sort key
          // is integer-valued (matches the field type on the model).
          xpContribution: totalVolume.round(),
          isPR: prExerciseIds.contains(exerciseId),
        ),
      );
    }

    rows.sort((a, b) {
      final cmp = b.xpContribution.compareTo(a.xpContribution);
      if (cmp != 0) return cmp;
      return a.exerciseName.compareTo(b.exerciseName);
    });

    if (rows.length <= _maxTopLifts) return rows;
    return rows.sublist(0, _maxTopLifts);
  }

  /// Project the session's COMPLETED cardio entries into
  /// [SessionCardioSummary] rows for the S2 Mission Debrief ledger (Phase
  /// 38e). Preserves the workout's exercise order. Drops incomplete entries
  /// (only "Concluir cardio"-tapped sessions persist + surface). Pace is
  /// derived canonically (seconds-per-km) only when a positive distance is
  /// present; the widget layer converts to the display unit.
  static List<SessionCardioSummary> _projectCardioEntries({
    required List<ActiveWorkoutExercise> exercises,
    required Map<String, String> exerciseNames,
  }) {
    final rows = <SessionCardioSummary>[];
    for (final entry in exercises) {
      final cardio = entry.cardioSession;
      if (cardio == null || !cardio.isCompleted) continue;
      final exerciseId = entry.workoutExercise.exerciseId;
      rows.add(
        SessionCardioSummary(
          exerciseId: exerciseId,
          activityName:
              exerciseNames[exerciseId] ??
              entry.workoutExercise.exercise?.name ??
              exerciseId,
          durationSeconds: cardio.durationSeconds,
          distanceM: cardio.distanceM,
          paceSecondsPerKm: CardioFormat.paceSecondsPerKm(
            durationSeconds: cardio.durationSeconds,
            distanceM: cardio.distanceM,
          ),
        ),
      );
    }
    return rows;
  }

  /// Resolve an exercise to its dominant body part for debrief grouping.
  ///
  /// Lookup priority:
  ///   1. `xpAttribution` max-share token (matches the engagement
  ///      attribution rule in `primaryBodyPartsForSet`).
  ///   2. `MuscleGroup` → `BodyPart` mapping via [muscleGroupToBodyPart].
  ///   3. `null` (cardio + no attribution — caller drops the row).
  static BodyPart? _dominantBodyPartFor(Exercise exercise) {
    final attribution = exercise.xpAttribution;
    if (attribution != null && attribution.isNotEmpty) {
      double bestShare = 0;
      BodyPart? winner;
      attribution.forEach((key, value) {
        final share = value.toDouble();
        if (share <= 0) return;
        final bp = BodyPart.tryFromDbValue(key);
        if (bp == null || bp == BodyPart.cardio) return;
        if (share > bestShare) {
          bestShare = share;
          winner = bp;
        }
      });
      if (winner != null) return winner;
    }
    return muscleGroupToBodyPart(exercise.muscleGroup);
  }

  /// Maximum lift rows surfaced in the S2 Mission Debrief table per WIP
  /// locked-decision #2 (top 4 + "+N more" footer on 5+ exercise sessions).
  static const int _maxTopLifts = 4;

  /// Advance to the next cut. When the index reaches `cuts.length`, flip
  /// [PostSessionState.showSummary] true.
  void advance() {
    final next = _state.cutIndex + 1;
    if (next >= _state.cuts.length) {
      _state = _state.copyWith(showSummary: true);
    } else {
      _state = _state.copyWith(cutIndex: next);
    }
    notifyListeners();
  }

  /// Fast-forward to the summary panel (long-press skip).
  void skipToSummary() {
    if (_state.showSummary) return;
    _state = _state.copyWith(showSummary: true);
    notifyListeners();
  }

  /// Invalidate the workout count provider so a subsequent reading
  /// reflects this finish. Called by the screen's CONTINUAR handler.
  void onContinue() {
    ref.invalidate(workoutCountProvider);
  }
}
