import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Discoverability affordance for the skip-to-summary gesture on
/// [PostSessionScreen] (PR 30a UX pass, 2026-05-23).
///
/// The long-press skip gesture is already wired via the screen's outer
/// `GestureDetector(onLongPress:)`. The long-press is undiscoverable — no
/// user thinks to long-press a passive-looking cinematic. This button
/// surfaces the same `skipToSummary()` route via an explicit tap target
/// in the top-right corner.
///
/// **Concept B grammar (mockup §0):** no Material ripple, no fill, no
/// border, no tooltip. A ghost icon at low alpha — present enough to be
/// discoverable, restrained enough to disappear into the cinematic
/// chrome.
///
/// **Long-press preserved.** The existing `_handleLongPress` route on
/// [PostSessionScreen] is intentionally not removed — some users may have
/// learned the gesture from prior sessions. Both gestures route to the
/// same `controller.skipToSummary()`.
///
/// **Visibility contract.** The host screen composes this button in
/// `_buildCinematic` only — when the summary panel mounts, the button
/// unmounts (the summary has its own CONTINUAR CTA, which is the
/// canonical forward action there).
///
/// **Accessibility.** Wrapped in a `Semantics` node with `button: true`,
/// `label: 'Skip cinematic'`, and `identifier: 'post-session-skip-btn'`
/// so screen-readers + Playwright E2E selectors have a stable handle.
class CinematicSkipButton extends StatelessWidget {
  const CinematicSkipButton({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        // Inset only by the top + right system region — the cut canvas
        // itself stays edge-to-edge above (Stack composition in the host
        // screen).
        bottom: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, right: 12),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            button: true,
            label: 'Skip cinematic',
            identifier: 'post-session-skip-btn',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSkip,
              child: const Padding(
                // Pad the tap target to honor Material's 48dp minimum
                // hit-region without rendering any chrome around the
                // icon itself (Concept B: no ripple, no fill).
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.skip_next,
                  size: 22,
                  color: AppColors.textDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
