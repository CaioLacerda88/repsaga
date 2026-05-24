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
/// **Text-only refinement (UX pass 2.5, 2026-05-24).** Pass 2 paired the
/// localized label with a `skip_next` glyph at 16dp. User + UX-critic
/// review converged on dropping the icon: the abyss-panel chrome + hard
/// edge + uppercase letter-spaced label already signals affordance, and
/// the 16dp glyph competed with the typography instead of adding semantic
/// weight. Removing the icon required bumping vertical padding 12→14dp
/// to keep the ≥40dp tap target (icon was contributing 16dp of intrinsic
/// row height) and pinning font weight to `w700` so the text-only pill
/// reads as affordance, not body label.
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
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  // Hard rectangle (no border-radius) — Concept B grammar.
                  // Abyss-tinted panel at 75% alpha mirrors the cascade-row
                  // chrome adopted in Bug G; reads as part of the
                  // cinematic frame, not as a Material widget pasted on
                  // top.
                  color: Color(0xBF0D0319), // AppColors.abyss @ 75% alpha.
                ),
                child: Padding(
                  // 14h / 14v padding lifts the tap target to ≥40dp tall
                  // in the text-only design (UX pass 2.5, 2026-05-24).
                  // Row height = label 11sp × 1.2 line ≈ 13.2dp →
                  // total ≈ 13.2 + 2×14 = 41.2dp. Pass 2 used 12v because
                  // the 16dp icon dominated the intrinsic row height
                  // (40 = 16 + 2×12); dropping the icon required bumping
                  // vertical padding to keep the contract.
                  // Memory: feedback_tap_target_measurement — Flutter's
                  // MaterialTapTargetSize.padded default doesn't apply to
                  // raw GestureDetectors, so we size up explicitly.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Text(
                    label,
                    style: AppTextStyles.label.copyWith(
                      // Tighter letter-spacing than the token default so
                      // the 4-char Portuguese label ("PULAR") doesn't read
                      // as letter-mosaic at 11sp. Weight pinned w700 so
                      // the text-only pill reads as affordance, not body
                      // label — UX-critic 2026-05-24.
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.16 * 11,
                      color: AppColors.textCream,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
