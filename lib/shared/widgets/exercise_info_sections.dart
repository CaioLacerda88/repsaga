import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Renders an "ABOUT" section header with the exercise description text.
///
/// Collapses to nothing when [description] is null or empty.
class ExerciseDescriptionSection extends StatelessWidget {
  const ExerciseDescriptionSection({super.key, required this.description});

  final String? description;

  @override
  Widget build(BuildContext context) {
    if (description == null || description!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context).aboutSection,
          style: AppTextStyles.sectionHeader.copyWith(
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description!,
          // P9: body prose at full opacity — the description is not
          // metadata, it's primary content.
          style: AppTextStyles.body.copyWith(color: onSurface),
        ),
      ],
    );
  }
}

/// Renders a "FORM TIPS" section header with a bulleted list of tips.
///
/// Splits [formTips] on `\n`, trims each line, and filters out empty lines.
/// Collapses to nothing when [formTips] is null or empty after filtering.
class ExerciseFormTipsSection extends StatelessWidget {
  const ExerciseFormTipsSection({super.key, required this.formTips});

  final String? formTips;

  @override
  Widget build(BuildContext context) {
    if (formTips == null || formTips!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final tips = formTips!
        .split(RegExp(r'\n|\\n'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tips.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context).formTipsSection,
          style: AppTextStyles.sectionHeader.copyWith(
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(tips.length, (index) {
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // P9: neutral circular bullet in primary, full opacity.
                // Supersedes the earlier check_circle_outline which read
                // as a "done" checkmark rather than a simple list marker.
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tips[index],
                    style: AppTextStyles.body.copyWith(color: onSurface),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
