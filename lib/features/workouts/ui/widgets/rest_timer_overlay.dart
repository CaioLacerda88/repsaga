import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/notifiers/rest_timer_notifier.dart';

/// Full-screen overlay displayed when the rest timer is active.
///
/// Watches [restTimerProvider] directly -- no props needed. Auto-dismisses
/// when the timer reaches zero and triggers haptic feedback on completion.
class RestTimerOverlay extends ConsumerStatefulWidget {
  const RestTimerOverlay({super.key});

  @override
  ConsumerState<RestTimerOverlay> createState() => _RestTimerOverlayState();
}

class _RestTimerOverlayState extends ConsumerState<RestTimerOverlay> {
  @override
  void initState() {
    super.initState();
    // Listen for timer completion to fire haptic feedback and auto-dismiss.
    // Using listenManual in initState fires exactly once per transition,
    // avoiding the re-fire risk of side effects inside build().
    ref.listenManual(restTimerProvider, (previous, next) {
      if (next != null && !next.isActive && next.remainingSeconds == 0) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) ref.read(restTimerProvider.notifier).stop();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final timerState = ref.watch(restTimerProvider);

    if (timerState == null) return const SizedBox.shrink();

    final minutes = timerState.remainingSeconds ~/ 60;
    final seconds = timerState.remainingSeconds % 60;
    final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Semantics(
      // Family 3 (AW-EX-F-BR1-06) — outer dismiss scrim a11y. The scrim's
      // tap-to-dismiss was previously unlabeled in the AOM; screen-reader
      // users had no way to discover or invoke the dismiss action. Wrapping
      // the outer GestureDetector in a labelled `Semantics(button:, label:)`
      // surfaces the affordance without changing the dismiss handler or
      // the existing `HitTestBehavior.opaque` (PR #175).
      //
      // **Pair-rule** (`container: true` + `explicitChildNodes: true`,
      // see lessons.md PR #152): without these, the outer Semantics
      // merges its label with EVERY descendant — countdown, exercise
      // name, dismiss-hint Text, and the -30 / Skip / +30 buttons all
      // collapse into a single tappable AOM node, and the inner
      // `liveRegion: true` annotation on the countdown is silently
      // promoted to the merged blob (so screen readers re-announce the
      // whole thing on every tick). The pair creates a hard boundary so
      // the dismiss button is its own node and the inner Semantics
      // (countdown, controls) keep their identities.
      container: true,
      explicitChildNodes: true,
      button: true,
      label: l10n.restTimerDismiss,
      child: GestureDetector(
        // `HitTestBehavior.opaque` prevents taps from propagating to widgets
        // beneath the scrim. Without it, dismissing the timer also fires the
        // handler of whatever is under the tap point. Symmetric with the
        // inner control-row detector below.
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(restTimerProvider.notifier).stop(),
        child: Material(
          // Full-screen rest-timer scrim. abyss (#0D0319) at ~87% alpha — dark
          // enough to dim the underlying workout screen without being fully opaque.
          color: AppColors.abyss.withValues(alpha: 0.87),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    // Family 3 (AW-EX-F-BR1-06) — `liveRegion: true` causes
                    // screen readers to announce every tick of the
                    // countdown. Without it, the user hears the initial
                    // time and is then stranded with no audio feedback as
                    // the rest period elapses. Cadence-shaping (announce
                    // only on minute boundaries) is intentionally skipped
                    // — accept the verbosity until a screen-reader user
                    // reports excess chatter.
                    //
                    // `container: true` is paired with the outer
                    // `explicitChildNodes: true` so this Semantics emits
                    // its OWN AOM node (otherwise the engine folds it into
                    // the parent dismiss-button merge and the live region
                    // is silently promoted to the entire scrim — a
                    // screen-reader would re-announce every label on
                    // every tick).
                    container: true,
                    liveRegion: true,
                    label: l10n.restTimerRemaining(timeText),
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Progress ring
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: CircularProgressIndicator(
                              value: 1.0 - timerState.progress,
                              strokeWidth: 8,
                              backgroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          // Countdown text
                          Text(
                            timeText,
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    // Surfacing the exercise name in the AOM tells the
                    // screen-reader user which exercise they're resting
                    // between sets of. The Text widget alone produces a
                    // semantic node, but the explicit Semantics wrapper
                    // (with `container: true`, paired with the outer
                    // `explicitChildNodes: true`) makes the label its own
                    // boundary so it shows up in the AOM separately from
                    // the dismiss-scrim merge.
                    container: true,
                    label: timerState.exerciseName ?? l10n.restTimerLabel,
                    child: ExcludeSemantics(
                      // The Text already emits its own semantic node, so
                      // wrapping it without ExcludeSemantics would
                      // double-announce the exercise name. Suppress the
                      // inner emission and let the outer Semantics own the
                      // AOM contract.
                      child: Text(
                        timerState.exerciseName ?? l10n.restTimerLabel,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // -30s / Skip / +30s button row
                  // Wrap controls in an opaque GestureDetector to prevent
                  // taps on buttons from bubbling to the outer dismiss handler.
                  GestureDetector(
                    onTap: () {},
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: l10n.subtract30Semantics,
                          button: true,
                          child: SizedBox(
                            width: 64,
                            height: 56,
                            child: TextButton(
                              onPressed: () => ref
                                  .read(restTimerProvider.notifier)
                                  .adjustTime(-30),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                backgroundColor: AppColors.textCream.withValues(
                                  alpha: 0.12,
                                ),
                                textStyle: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('-30s'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: l10n.skipRestSemantics,
                          button: true,
                          child: SizedBox(
                            width: 120,
                            height: 56,
                            child: TextButton(
                              onPressed: () =>
                                  ref.read(restTimerProvider.notifier).skip(),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                textStyle: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              child: Text(l10n.skip),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: l10n.add30Semantics,
                          button: true,
                          child: SizedBox(
                            width: 64,
                            height: 56,
                            child: TextButton(
                              onPressed: () => ref
                                  .read(restTimerProvider.notifier)
                                  .adjustTime(30),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                backgroundColor: AppColors.textCream.withValues(
                                  alpha: 0.12,
                                ),
                                textStyle: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('+30s'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // The outer dismiss-scrim Semantics already exposes
                  // "Dismiss rest timer" to the AOM (see L70). The visual
                  // hint Text below is for sighted users only — without
                  // ExcludeSemantics, `explicitChildNodes: true` on the
                  // outer Semantics promotes this Text to its own AOM node,
                  // and screen-reader users hear both the outer button
                  // label AND a redundant "Tap anywhere to dismiss" leaf.
                  // Same pattern as the exercise-name fix above.
                  ExcludeSemantics(
                    // PR-5 — dismiss hint α bumped 0.3 -> 0.6 for readable
                    // contrast against the near-black abyss scrim
                    // (`abyss #0D0319 @ 87%`). Pre-fix the hint was
                    // essentially invisible — users had to discover the
                    // tap-anywhere dismiss by accident. 0.6 sits below
                    // body-text full strength so the hint stays a hint
                    // (not a competing CTA) while clearing the AA floor.
                    child: Text(
                      l10n.tapToDismiss,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
