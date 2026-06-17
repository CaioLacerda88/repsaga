import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Slim teal-hairline explainer banner shown once on the stats deep-dive
/// screen (Phase 38e-bis). States the two-speed Vitality decay rule (cardio
/// τ=3wk vs strength τ=6wk) in words — the cardio row's per-row subtitle and
/// the 7th teal chart line carry the same signal visually, but the rule itself
/// is taught here in prose, once.
///
/// **Localization (per `feedback_widget_l10n_parameterization`):** the widget
/// takes its [message] + [dismissLabel] as params rather than reading
/// `AppLocalizations.of(context)` itself, so its widget tests stay
/// l10n-harness-free and the ARB-key choice lives at the screen layer.
///
/// **One-time gating lives at the call site**, not here: the screen watches
/// [cardioDecayExplainerDismissalProvider] and simply omits this widget once
/// the flag is set. This widget is a pure presentation surface — it renders
/// when mounted and fires [onDismiss] when the X is tapped.
class CardioDecayExplainerBanner extends StatelessWidget {
  const CardioDecayExplainerBanner({
    super.key,
    required this.message,
    required this.dismissLabel,
    required this.onDismiss,
  });

  /// The teaching copy (`l10n.statsCardioDecayExplainer`).
  final String message;

  /// Accessibility label for the dismiss (X) button
  /// (`l10n.statsCardioDecayExplainerDismiss`).
  final String dismissLabel;

  /// Fired when the user taps the X. The call site persists the one-time
  /// dismissal and rebuilds without this banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // Teal-hairline chrome (mockup `.stats-explainer`): faint teal fill +
    // 28%-alpha teal border, rounded. The leading glyph + text read teal /
    // near-cream so the band stays in the cardio register without shouting.
    const teal = AppColors.bodyPartCardio;
    return Semantics(
      container: true,
      identifier: 'cardio-decay-explainer',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.fromLTRB(13, 11, 6, 11),
        decoration: BoxDecoration(
          color: teal.withValues(alpha: 0.05),
          border: Border.all(color: teal.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.autorenew, size: 16, color: teal),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                // Optically center the single-glyph icon against the multi-
                // line text block by nudging the text down a hair.
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textCream.withValues(alpha: 0.84),
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: dismissLabel,
              child: InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 16, color: AppColors.textDim),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
