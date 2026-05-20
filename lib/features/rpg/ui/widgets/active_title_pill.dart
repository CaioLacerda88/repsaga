import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';

/// Small pill that renders the user's currently equipped title.
///
/// Renders [SizedBox.shrink] when `title` is null — the slot is hidden, not
/// replaced by a placeholder, per spec §13.1. Phase 18b ships with no
/// titles equipped (the [activeTitleProvider] stub returns null), so this
/// widget is effectively dormant until 18c lands the title catalog +
/// equip flow.
class ActiveTitlePill extends StatelessWidget {
  const ActiveTitlePill({super.key, required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = title;
    if (t == null || t.isEmpty) return const SizedBox.shrink();

    // BUG-024: cap width and ellipsize so long pt-BR titles
    // ("Forjado em Ferro" etc.) cannot push the pill past the safe area or
    // clip horizontally. 220dp matches roughly 24-26 characters at this
    // type size — enough headroom for every catalog title in en+pt while
    // still clamping pathological cases (custom titles in a future phase).
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(
            color: AppColors.hotViolet.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
        ),
        child: Text(
          t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label.copyWith(color: AppColors.hotViolet),
        ),
      ),
    );
  }
}
