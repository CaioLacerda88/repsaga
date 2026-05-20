import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Bottom sheet explaining the set-counting rule used by Engajamento.
///
/// Triggered by the ⓘ icon on `EngajamentoSection`. Pure-text content — no
/// inputs. The screen layer resolves the localized title + body via
/// AppLocalizations before calling [show] so the widget stays l10n-agnostic
/// and unit-testable without an l10n harness.
class EngagementExplainerSheet extends StatelessWidget {
  const EngagementExplainerSheet({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => EngagementExplainerSheet(title: title, body: body),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTextStyles.title.copyWith(
              color: AppColors.textCream,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textDim,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
