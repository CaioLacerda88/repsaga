import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Placeholder share CTA for PR 30a — shows a "coming soon" snackbar when
/// tapped. PR 30b replaces this with the real share pipeline (camera /
/// gallery / preview / native share sheet).
///
/// **Decoupling Rule 2.** Labels arrive pre-localized via constructor.
class ShareCtaButton extends StatelessWidget {
  const ShareCtaButton({
    super.key,
    required this.label,
    required this.comingSoonMessage,
  });

  /// CTA label, e.g. "📷 Compartilhar saga".
  final String label;

  /// Snackbar copy shown on tap during 30a, e.g. "Em breve".
  final String comingSoonMessage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => _showComingSoon(context),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.surface2,
          foregroundColor: AppColors.textCream,
        ),
        child: Text(label),
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
