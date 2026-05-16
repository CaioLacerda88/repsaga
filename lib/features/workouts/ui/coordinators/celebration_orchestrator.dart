import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/providers/auth_providers.dart';
import '../../../rpg/data/rank_up_pulse_local_storage.dart';
import '../../../rpg/domain/celebration_queue.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/providers/earned_titles_provider.dart';
import '../../../rpg/providers/rank_up_pulse_provider.dart';
import '../../../rpg/ui/celebration_player.dart';
import '../../../rpg/ui/saga_intro_gate.dart';

/// Outcome of [CelebrationOrchestrator.play].
///
/// Carries the only signal the caller needs to pick a post-celebration
/// route — `userTappedOverflow`. Other celebration-screen interactions
/// (title equipped, etc.) are handled internally by [CelebrationPlayer]
/// and don't cross this boundary.
typedef CelebrationOutcome = ({bool userTappedOverflow});

/// Orchestrates the post-finish celebration playback.
///
/// **Why a separate type:** the play method's contract has three load-
/// bearing invariants that need to live somewhere with explicit narrative:
///   1. Saga-intro must dismiss BEFORE celebration overlays render
///      (BUG-012). Wrapped in a 5s `.timeout()` (BUG-039 defensive fix —
///      see comment on the await).
///   2. Provider reads must happen BEFORE the await — the screen's State
///      may be disposed during the wait, invalidating its `ref`.
///   3. The 200ms gap between intro dismiss and the first celebration
///      frame so the eye doesn't get a hard cut.
///
/// Inlining this back into `_FinishWorkoutCoordinator` would entangle
/// these timing rules with the broader save/PR/nav orchestration; pulling
/// it out keeps each block testable in isolation.
class CelebrationOrchestrator {
  const CelebrationOrchestrator();

  /// Play the celebration queue against [rootContext] and return the
  /// outcome.
  ///
  /// All [ref] reads happen synchronously up-front (before the saga-intro
  /// await) — see comment block on the wait for the lifecycle reasoning.
  ///
  /// Returns `CelebrationOutcome(userTappedOverflow: false)` when:
  ///   * The user is somehow not authenticated (defensive).
  ///   * `rootContext` becomes unmounted between the intro wait and the
  ///     player invocation (process exit).
  ///   * The user does not tap the overflow card (auto-dismiss / no
  ///     overflow card present).
  Future<CelebrationOutcome> play({
    required BuildContext rootContext,
    required WidgetRef ref,
    required CelebrationQueueResult celebration,
  }) async {
    // BUG-012 (Cluster 3) sequencing — saga intro overlay must
    // complete BEFORE celebration overlays render. If the intro is
    // already dismissed (returning user, Hive flag set), the
    // sequencer's future resolves immediately and we proceed
    // without delay. If it's still up (first workout for a fresh
    // user), we wait for the BEGIN tap, then a 200ms gap so the
    // eye doesn't get a hard cut between the intro dismiss and
    // the first celebration frame.
    //
    // Cluster-3 review (2026-05-02): a 5s timeout is layered on
    // top of the wait. The active-workout screen is rendered
    // OUTSIDE the shell route (no SagaIntroGate above it), so
    // there are paths — most notably "fresh user signs in →
    // immediately starts a workout without ever returning to
    // home" — where the gate never gets a chance to mount, never
    // kicks the retro backfill, and therefore never resolves the
    // sequencer. Without the timeout, the await blocks forever
    // and the celebration queue is silently dropped (the regression
    // qa-engineer caught: 17 E2E tests timing out at finishWorkout()).
    // 5 s is generous enough that a real intro dismiss path
    // (BEGIN tap on a slow device) still falls inside the window
    // — typical fresh-user dismissal completes in ~1-2 s.
    //
    // CRITICAL — provider reads must happen BEFORE the await. The
    // notifier transitioned to AsyncData(null) inside finishWorkout(),
    // which causes ActiveWorkoutScreen.build to swap this body out
    // for the CircularProgressIndicator scaffold ON THE NEXT FRAME.
    // That dispose runs while we're awaiting the sequencer, so any
    // post-await `ref.read(...)` would throw a StateError on a
    // disposed ConsumerStatefulWidget. Snapshotting these now keeps
    // the celebration code path independent of this State's lifecycle
    // — celebrations play on rootContext (root navigator), not on
    // this body's context, and the data they need is captured before
    // we yield.
    final userId = ref.read(currentUserIdProvider);
    final priorEarned = ref.read(earnedTitlesProvider).value ?? const [];
    final hasPriorEarnedTitles = priorEarned.isNotEmpty;
    final catalog = ref.read(titleCatalogProvider).value ?? const [];
    final pulseStorage = ref.read(rankUpPulseLocalStorageProvider);

    if (userId != null) {
      await SagaIntroSequencer.waitForIntroDismissed(userId).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          developer.log(
            'SagaIntroSequencer timed out — proceeding with '
            'celebration without intro dismissal signal',
            name: 'CelebrationPlayer',
          );
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // Mounted check on rootContext (NOT `mounted` — this body's
    // State has likely been disposed during the await above; see
    // capture comment). rootContext is the root navigator's context
    // which stays alive for the full app session, so this guard
    // only fires if the app is being torn down (process exit).
    if (!rootContext.mounted) {
      return (userTappedOverflow: false);
    }
    final celebrationResult = await CelebrationPlayer.play(
      rootContext, // ignore: use_build_context_synchronously — root navigator context stays alive for full app session; intentionally used across async gaps (see rootContext capture comment above)
      result: celebration,
      catalog: catalog,
      hasPriorEarnedTitles: hasPriorEarnedTitles,
      onEquipTitle: (title) async {
        // Use ProviderScope.containerOf(rootContext) instead of
        // `ref` because this callback fires inside CelebrationPlayer
        // after _ActiveWorkoutScreenState may be disposed (invalidating
        // the ConsumerStatefulWidget's ref). rootContext is the root
        // navigator's context which stays alive for the full app
        // session.
        final container = ProviderScope.containerOf(rootContext);
        final repo = container.read(titlesRepositoryProvider);
        await repo.equipTitle(title.slug);
        container.invalidate(earnedTitlesProvider);
        container.invalidate(equippedTitleSlugProvider);
      },
    );
    // Phase 26b: write 24h pulse-window trigger timestamps for every
    // rank-up that played in the celebration. BodyPartRankRow reads
    // isPulsing() to decide whether to render the glow-ring overlay.
    // Done AFTER play() returns so the pulse only starts after the user
    // has actually seen the celebration — pulsing before dismissal would
    // duplicate signal.
    await recordRankUpPulses(result: celebration, pulseStorage: pulseStorage);

    return (userTappedOverflow: celebrationResult.userTappedOverflow);
  }

  /// Writes a pulse-trigger timestamp to [pulseStorage] for every
  /// [RankUpEvent] in [result]'s queue. The 24h dot-pulse window starts
  /// when this fires; `BodyPartRankRow` reads `isPulsing()` to decide
  /// whether to render the glow-ring overlay.
  ///
  /// **Known limitation (Phase 26b plan, Task 10):** the [OverflowPayload]
  /// only carries a count of rank-ups that didn't fit in the celebration
  /// queue — the body parts aren't preserved. Those rank-ups DO NOT pulse.
  /// Acceptable for v1 because overflow scenarios are rare (user must
  /// rank up 4+ body parts in a single workout). If overflow becomes
  /// common enough to warrant pulsing, extend [OverflowPayload] to carry
  /// `List<BodyPart>` and update this helper.
  ///
  /// Public for testing — production callers go through [play].
  static Future<void> recordRankUpPulses({
    required CelebrationQueueResult result,
    required RankUpPulseLocalStorage pulseStorage,
  }) async {
    for (final event in result.queue.whereType<RankUpEvent>()) {
      await pulseStorage.recordRankUp(event.bodyPart);
    }
  }
}
