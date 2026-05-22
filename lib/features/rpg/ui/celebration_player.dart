import 'package:flutter/material.dart';

import '../domain/celebration_queue.dart';
import '../models/title.dart' as rpg;

/// Sequential player for the post-workout celebration queue.
///
/// **Path A pivot (PR 29.5, 2026-05-22).** This player previously
/// dispatched each [CelebrationEvent] to a [ThinFlashOverlay] (400ms
/// hue-flash) during the workout-finish flow. On-device verification on
/// Galaxy S25 Ultra (PR 29.5 review pass 3) surfaced that the
/// architecture only supports session-finish event emission — events are
/// computed from a pre-vs-post session diff inside the
/// `record_session_xp_batch` chain, not per-set. So the "mid-workout"
/// flashes fired ~200ms before the Phase 30 post-session cinematic
/// ceremony mounted (same moment, same attentional context). The
/// mockup §4½ "dual-loop" thesis only holds with TRUE per-set firing;
/// without it the flash layer is redundant pre-roll for the cinematic
/// that fires 4 seconds later.
///
/// Decision: kill the flash layer entirely. The post-session ceremony
/// (Phase 30, PR 30a, Beats 1–5) carries the full celebration for ALL
/// events. The five legacy mid-workout overlay widgets retired in
/// PR 29.5 (Concept B grammar incompatibility) are NOT replaced; the
/// events skip the flash layer entirely and pass through to the
/// post-session screen.
///
/// **What this player does now:**
///   * Returns [CelebrationPlayResult.notTapped] immediately.
///   * Renders no UI; does not insert any [OverlayEntry]; does not
///     touch the [Navigator] stack.
///   * Preserves the public [CelebrationPlayer.play] signature so
///     [CelebrationOrchestrator] keeps compiling without a callsite
///     change. The orchestrator's other responsibilities (saga-intro
///     wait, rank-up pulse-write side effect) are unchanged.
///
/// **What survives for PR 30a's consumption:**
///   * [CelebrationEvent.personalRecord] variant — Beat 4 will consume.
///   * [CelebrationQueue.SlotPolicy] enum + `slotPolicyFor` — drives
///     post-session event ordering / coalescing.
///   * [`CelebrationOverflowCard`] / [`RankUpOverflowFlipbook`] — the
///     overflow surface lives in the file system but no longer mounts
///     mid-workout. PR 30a integrates it into Beat 4 or removes it
///     entirely depending on the design call.
///
/// **Why a pass-through and not a removed file:** keeping the type +
/// public method shape stable means [CelebrationOrchestrator] does not
/// need a structural rewrite for PR 29.5. The orchestrator's other
/// responsibilities (saga-intro wait, rank-up pulse-write) are
/// unchanged. PR 30a will replace this pass-through with the
/// post-session screen mount.

/// Result value for [CelebrationPlayer.play].
///
/// The bool is the only field today; the class shape leaves room for
/// future signals (e.g., title equipped during sheet, overflow body
/// parts list) without breaking the call site. After the Path A pivot
/// (PR 29.5) the player no longer renders UI mid-workout, so the
/// `userTappedOverflow` field is always `false` from this call. The
/// post-session screen (PR 30a) will own the overflow surface and
/// produce its own outcome value when it lands.
class CelebrationPlayResult {
  const CelebrationPlayResult({required this.userTappedOverflow});

  /// True when the user explicitly tapped the overflow card during this
  /// playback. After the Path A pivot this is always `false` from
  /// [CelebrationPlayer.play] — the post-session screen (PR 30a) will
  /// surface the overflow affordance and own its own outcome value.
  final bool userTappedOverflow;

  static const CelebrationPlayResult notTapped = CelebrationPlayResult(
    userTappedOverflow: false,
  );

  static const CelebrationPlayResult tapped = CelebrationPlayResult(
    userTappedOverflow: true,
  );
}

class CelebrationPlayer {
  const CelebrationPlayer._();

  /// Play the celebration queue against [context].
  ///
  /// **Path A pivot (PR 29.5):** this method no longer renders any UI.
  /// It returns [CelebrationPlayResult.notTapped] synchronously (wrapped
  /// in an already-completed Future so the existing `await` at the call
  /// site remains valid). The post-session screen (PR 30a) consumes
  /// [CelebrationQueueResult] directly and carries the full celebration
  /// for every event variant.
  ///
  /// **Why arguments are accepted but ignored:** preserving the public
  /// signature means [CelebrationOrchestrator] keeps compiling without
  /// a callsite change. PR 30a will replace this pass-through with the
  /// post-session screen mount and at that point can refactor the
  /// orchestrator's call shape too.
  ///
  /// [hasPriorEarnedTitles] and [onEquipTitle] are retained as
  /// `@Deprecated` parameters so existing callers that still pass them
  /// continue to compile. They are documented dead arguments — the
  /// EQUIP affordance migrates to the post-session summary panel in
  /// PR 30a. Both deprecation markers + the call-site arguments will be
  /// removed together in PR 30c.
  static Future<CelebrationPlayResult> play(
    BuildContext context, {
    required CelebrationQueueResult result,
    required List<rpg.Title> catalog,
    @Deprecated(
      'Unused — EQUIP affordance migrated to PR 30a (post-session '
      'summary panel). Will be removed in PR 30c.',
    )
    bool hasPriorEarnedTitles = false,
    @Deprecated(
      'Unused — EQUIP affordance migrated to PR 30a (post-session '
      'summary panel). Will be removed in PR 30c.',
    )
    Future<void> Function(rpg.Title title)? onEquipTitle,
  }) {
    // Path A: no UI is rendered mid-workout. The post-session screen
    // (PR 30a) consumes `result` directly. Return synchronously via a
    // pre-completed Future so the caller's `await` still works.
    return Future<CelebrationPlayResult>.value(CelebrationPlayResult.notTapped);
  }
}
