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
/// **Visibility retune (UX pass 2, 2026-05-23).** Pass 1 shipped a ghost
/// icon at low alpha (`AppColors.textDim`, 22dp, no chrome). On-device
/// verification confirmed users never even noticed the button existed
/// before the cut advanced. This pass redesigns to a hard-rectangle
/// abyss-panel pill — the same chrome grammar the cascade-row panels
/// adopted in Bug G. Still no Material ripple, no border, no border-radius
/// (Concept B grammar — mockup §0).
///
/// **Chrome strip + icon restore (UX pass 2.6, 2026-05-24).** Pass 2.5
/// dropped the icon, but on-device review brought it back: the chevron
/// is a stronger affordance-signal than text alone (universal "advance"
/// glyph). At the same time the abyss-panel chrome got stripped — the
/// label+icon pair already reads as a tappable element without a box,
/// and the box was the heaviest piece of Material-style chrome on an
/// otherwise pure Concept B canvas. Final composition: padded row of
/// `label` + 6dp gap + `skip_next` glyph, both in `textCream`, no
/// background, no border. Trust contrast.
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
/// **L10n parameterization (memory: feedback_widget_l10n_parameterization).**
/// The button takes the localized label as a constructor argument — the
/// screen layer resolves `AppLocalizations.of(context).cinematicSkipLabel`
/// and threads it down. Keeps this widget unit-testable without an l10n
/// harness; the ARB-key decision lives at the screen layer.
///
/// **Accessibility.** Wrapped in a `Semantics` node with `button: true`,
/// `label: 'Skip cinematic'`, and `identifier: 'post-session-skip-btn'`
/// so screen-readers + Playwright E2E selectors have a stable handle.
class CinematicSkipButton extends StatelessWidget {
  const CinematicSkipButton({
    super.key,
    required this.onSkip,
    required this.label,
  });

  final VoidCallback onSkip;

  /// Localized button label — e.g. "PULAR" (pt) or "SKIP" (en). Already
  /// uppercased by the ARB key (matches the `AppTextStyles.label`
  /// letter-spaced eyebrow casing convention).
  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        // Inset only by the top + right system region — the cut canvas
        // itself stays edge-to-edge above (Stack composition in the host
        // screen). Keeps the status bar / camera notch from overlapping
        // the pill on tall-aspect Android devices.
        bottom: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            button: true,
            label: 'Skip cinematic',
            identifier: 'post-session-skip-btn',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSkip,
              child: Padding(
                // 14h / 12v padding lifts the tap target to ≥40dp tall.
                // Row height = max(label 11sp × 1.2 line ≈ 13.2dp,
                // icon 16dp) = 16dp → total = 16 + 2×12 = 40dp exact.
                // Memory: feedback_tap_target_measurement — Flutter's
                // MaterialTapTargetSize.padded default doesn't apply to
                // raw GestureDetectors, so we size up explicitly.
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.label.copyWith(
                        // Tighter letter-spacing than the token default so
                        // the 4-char Portuguese label ("PULAR") doesn't
                        // read as letter-mosaic at 11sp. Weight pinned
                        // w700 so the chrome-less label reads as
                        // affordance, not body copy.
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.16 * 11,
                        color: AppColors.textCream,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.skip_next,
                      size: 16,
                      color: AppColors.textCream,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
