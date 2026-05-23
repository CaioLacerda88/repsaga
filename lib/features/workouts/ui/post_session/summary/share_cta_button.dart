import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import 'post_session_summary_panel.dart' show PostSessionCinematicButton;

/// Placeholder share CTA for PR 30a — shows a "coming soon" snackbar when
/// tapped. PR 30b replaces this with the real share pipeline (camera /
/// gallery / preview / native share sheet).
///
/// **Decoupling Rule 2.** Labels arrive pre-localized via constructor.
///
/// **Visual contract.** Rendered as a [PostSessionCinematicButton] with
/// `surface2` background, `textCream` foreground, and a leading
/// `Icons.camera_alt_outlined` glyph — matches mockup §5 final summary
/// frames (Rajdhani 600 tracked label, hard edges, icon-not-emoji per
/// 2026-05-23 visual gate fix).
class ShareCtaButton extends StatelessWidget {
  const ShareCtaButton({
    super.key,
    required this.label,
    required this.comingSoonMessage,
  });

  /// CTA label, e.g. "Compartilhar saga" (no glyph baked in — the camera
  /// icon renders as a leading Material icon).
  final String label;

  /// Snackbar copy shown on tap during 30a, e.g. "Em breve".
  final String comingSoonMessage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-share-cta',
      child: PostSessionCinematicButton(
        label: label,
        backgroundColor: AppColors.surface2,
        foregroundColor: AppColors.textCream,
        leadingIcon: Icons.camera_alt_outlined,
        onPressed: () => _showComingSoon(context),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(comingSoonMessage),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
