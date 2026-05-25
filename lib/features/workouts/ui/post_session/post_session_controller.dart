import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../personal_records/domain/pr_detection_service.dart';
import '../../../rpg/domain/celebration_queue.dart';
import '../../../rpg/domain/rank_curve.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/providers/rpg_progress_provider.dart';
import '../../../rpg/ui/widgets/body_part_localization.dart';
import '../../domain/post_session_choreographer.dart';
import '../../domain/reward_tier.dart';
import '../../providers/workout_history_providers.dart';
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
    required this.bpFirstAwakening,
    required this.priorFinishedWorkoutCount,
    required this.durationMinutes,
    required this.setsCount,
    required this.tonnageTons,
    required this.l10n,
  });

  final CelebrationQueueResult queueResult;
  final PRDetectionResult? prResult;
  final Map<String, String> exerciseNames;
  final int totalXpEarned;
  final Map<BodyPart, int> bpXpDeltas;
  final Map<BodyPart, double> bpProgressFractionPre;
  final Set<BodyPart> bpFirstAwakening;
  final int priorFinishedWorkoutCount;
  final int durationMinutes;
  final int setsCount;
  final double tonnageTons;

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
    for (final bp in params.bpXpDeltas.keys) {
      final row = progress.byBodyPart[bp];
      bpRankAfter[bp] = row?.rank ?? 1;
      final totalXp = row?.totalXp ?? 0.0;
      bpProgressAfter[bp] = RankCurve.progressFraction(totalXp, row?.rank ?? 1);
    }

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

    final bodyPartLabels = <BodyPart, String>{
      for (final bp in BodyPart.values)
        bp: localizedBodyPartName(bp, params.l10n),
    };

    final sagaNumber = params.priorFinishedWorkoutCount + 1;

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
    );
  }

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
