import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/radii.dart';

/// Slim, in-context "set your age" nudge shown under the post-session
/// summary after a cardio session when the user has no birth date on file
/// (Phase 38d, mockup §5/§6).
///
/// **Not a modal.** A violet-hairline banner sitting below the session
/// result — one line + "Set age" + a dismiss ✕. Invite, not nag.
///
/// **Decoupling Rule 2** — every string is injected pre-localized; the
/// screen layer resolves ARB keys. This widget renders layout only, keeping
/// it l10n-harness-free in tests.
class AgePromptBanner extends StatelessWidget {
  const AgePromptBanner({
    super.key,
    required this.message,
    required this.setAgeLabel,
    required this.dismissSemanticsLabel,
    required this.onSetAge,
    required this.onDismiss,
  });

  /// One-line invitation copy (pre-localized).
  final String message;

  /// "Set age" CTA label (pre-localized).
  final String setAgeLabel;

  /// Accessibility label for the dismiss (✕) affordance (pre-localized).
  final String dismissSemanticsLabel;

  /// Opens the AgeEditorSheet.
  final VoidCallback onSetAge;

  /// Records the never-show-again flag + removes the banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      identifier: 'post-session-age-prompt',
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.hotViolet.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(kRadiusMd),
          border: Border.all(
            color: AppColors.hotViolet.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.wb_sunny_outlined,
              color: AppColors.hotViolet,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textCream.withValues(alpha: 0.86),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // "Set age" CTA — 48dp tap-target floor via the InkWell padding.
            Semantics(
              container: true,
              button: true,
              identifier: 'post-session-age-prompt-cta',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(kRadiusSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  onTap: onSetAge,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 14,
                    ),
                    child: Text(
                      setAgeLabel.toUpperCase(),
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.hotViolet,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              container: true,
              button: true,
              identifier: 'post-session-age-prompt-dismiss',
              label: dismissSemanticsLabel,
              child: IconButton(
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
