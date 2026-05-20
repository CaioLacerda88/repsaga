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
                          // Countdown text — routed through AppTextStyles.numeric
                          // so the digits carry tabular figures (FontFeature
                          // .tabularFigures()). Without tabular figures the
                          // countdown's 1/2/3/4 glyphs render at proportional
                          // widths and the digits would visibly jitter on the
                          // 00:30 → 00:29 → 00:28 ticks. Phase 28a forbid-w900
                          // gate replaced the prior `fontWeight: w900` override
                          // (Rajdhani only bundles up to w700, so w900 was a
                          // silent nearest-match anyway).
                          Text(
                            timeText,
                            style: AppTextStyles.numeric.copyWith(
                              fontSize: 72,
                              height: 1.0,
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
                        style: AppTextStyles.title.copyWith(
                          fontSize: 20,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // -30s / Skip / +30s button row.
                  //
                  // Wrap controls in an opaque GestureDetector to prevent
                  // taps on buttons from bubbling to the outer dismiss handler.
                  //
                  // **Button sizing — content-driven, NOT fixed-width
                  // (PR-5 device-feedback fix).**
                  //
                  // Pre-fix: each button was wrapped in `SizedBox(width: 64,
                  // height: 56)`. On a real Samsung S25 Ultra (and likely
                  // other Android OEMs with font rendering different from
                  // Chromium's), `+30s` wrapped to two lines — TextButton's
                  // default 16dp horizontal padding ate ~32dp of the 64dp
                  // box, and `+30s` at `titleMedium @ w700` (the `+` glyph
                  // is wider than `-`) didn't fit in the remaining ~32dp.
                  // Playwright at 360dp Chromium did NOT catch this.
                  //
                  // The brittle fix would be to bump the SizedBox width to
                  // 76dp. That works for current copy + font, but breaks if:
                  //   - the user has Android system font scaling >100%
                  //   - copy ever changes (e.g. localized "+30s" → wider)
                  //   - a future button shape needs more chrome
                  //
                  // Correct fix: drop the SizedBox entirely. TextButton sizes
                  // to its content + its own padding. We enforce the WCAG
                  // 48dp tap-target floor via `minimumSize: Size(48, 48)` on
                  // the button's style. The buttons end up slightly
                  // asymmetric in width (`-30s` narrower than `+30s` because
                  // `-` is narrower than `+`) but visually match because
                  // the gutter between them is constant. Total row width
                  // adapts to font scale + copy automatically; never wraps.
                  GestureDetector(
                    onTap: () {},
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: l10n.subtract30Semantics,
                          button: true,
                          child: TextButton(
                            onPressed: () => ref
                                .read(restTimerProvider.notifier)
                                .adjustTime(-30),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: theme.colorScheme.onSurface,
                              backgroundColor: AppColors.textCream.withValues(
                                alpha: 0.12,
                              ),
                              textStyle: AppTextStyles.title.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('-30s'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: l10n.skipRestSemantics,
                          button: true,
                          child: TextButton(
                            onPressed: () =>
                                ref.read(restTimerProvider.notifier).skip(),
                            style: TextButton.styleFrom(
                              // Skip is the primary action — wider min so it
                              // reads as the dominant CTA in the row.
                              minimumSize: const Size(120, 48),
                              foregroundColor: theme.colorScheme.onSurface,
                              textStyle: AppTextStyles.title.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                            ),
                            child: Text(l10n.skip),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: l10n.add30Semantics,
                          button: true,
                          child: TextButton(
                            onPressed: () => ref
                                .read(restTimerProvider.notifier)
                                .adjustTime(30),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: theme.colorScheme.onSurface,
                              backgroundColor: AppColors.textCream.withValues(
                                alpha: 0.12,
                              ),
                              textStyle: AppTextStyles.title.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('+30s'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dismiss hint copy removed 2026-05-12 (Phase 23 UI/UX
                  // REV-3 — mechanic-instructive filler). The
                  // `restTimerDismiss` Semantics label on the outer scrim
                  // already exposes the dismiss affordance to screen
                  // readers, and the visible -30s / Skip / +30s controls
                  // (plus the scrim-as-tap-target) carry the affordance
                  // for sighted users. The trailing SizedBox(24) and the
                  // hint Text were removed together — the controls row's
                  // intrinsic spacing on the bottom of the column is
                  // sufficient.
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
