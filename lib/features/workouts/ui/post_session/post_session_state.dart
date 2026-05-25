// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../personal_records/domain/pr_detection_service.dart';
import '../../../rpg/domain/celebration_queue.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../domain/post_session_choreographer.dart';
import '../../domain/reward_tier.dart';

part 'post_session_state.freezed.dart';

/// Runtime state for the post-session screen (Decoupling Rule 4 —
/// separated from rendering).
///
/// Driven by `PostSessionController`. The screen reads this snapshot
/// to render the appropriate cut for the current [cutIndex] OR the
/// summary panel when [showSummary] is true.
@freezed
abstract class PostSessionState with _$PostSessionState {
  const factory PostSessionState({
    required RewardTier tier,
    required CelebrationQueueResult queueResult,
    required PRDetectionResult? prResult,
    required List<PostSessionCut> cuts,

    /// Current cut index. `0..cuts.length-1` plays cuts; `cuts.length` is
    /// the summary panel.
    required int cutIndex,

    /// Set true to fast-forward to the summary panel (long-press skip).
    required bool showSummary,

    /// Pre-resolved per-(BodyPart, locale) labels. The controller resolves
    /// these once via `localizedBodyPartName` so the cut widgets stay
    /// l10n-harness-free (Decoupling Rule 2 +
    /// `feedback_widget_l10n_parameterization`).
    required Map<BodyPart, String> bodyPartLabels,

    /// Pre-resolved exercise display names keyed by exercise id.
    required Map<String, String> exerciseNames,

    /// Post-session XP-progress fraction within current rank for every BP
    /// that earned XP this session. Stored so `SharePayload.fromPostSessionState`
    /// can project the dominant BP's progress fraction into the share card.
    required Map<BodyPart, double> bpProgressFractionAfter,

    /// Post-finish total XP earned.
    required int totalXpEarned,

    /// Prior-finished workout count (pre-this-finish). Drives day-zero
    /// detection + baseline copy alternation seed.
    required int priorFinishedWorkoutCount,

    /// Saga number for the summary panel (current finished workout count).
    required int sagaNumber,

    /// Total session duration in minutes.
    required int durationMinutes,

    /// Total completed working sets.
    required int setsCount,

    /// Total tonnage in tons (kg total / 1000).
    required double tonnageTons,

    /// Dominant BP after the session (for the summary next-step hook).
    required BodyPart? dominantBodyPart,

    /// XP remaining to reach the next rank on the dominant BP.
    required int? dominantXpToNextRank,

    /// The dominant BP's next rank.
    required int? dominantNextRank,

    /// Ranks remaining to next character level (non-null when a level-up
    /// fired or in the max-combo state).
    required int? ranksToNextLevel,

    /// Next character level value.
    required int? nextLevel,
  }) = _PostSessionState;
}

/// Whether the cinematic is complete (summary panel showing).
extension PostSessionStateX on PostSessionState {
  bool get isPlayingCinematic => !showSummary && cutIndex < cuts.length;

  /// Returns true when the queue or PR result indicates the share CTA
  /// should render on the summary panel.
  bool get hasShareCta {
    if (prResult != null && prResult!.hasNewRecords) return true;
    for (final e in queueResult.queue) {
      if (e is RankUpEvent || e is TitleUnlockEvent || e is ClassChangeEvent) {
        return true;
      }
    }
    return false;
  }
}
