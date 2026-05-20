import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';

/// Full-width tappable codex row — replaces Material `Chip`s for the three
/// secondary navigation entries on the character sheet (Stats / Titles /
/// History).
///
/// **Why not chips:** chips read as filter selection, not navigation. The
/// kickoff lock turned them into full-width rows with a right chevron so the
/// affordance reads unambiguously as "tap to drill in". One row per intent,
/// stacked vertically, all the same width — consistency, not a visual menu.
class CodexNavRow extends StatelessWidget {
  const CodexNavRow({
    super.key,
    required this.label,
    required this.onTap,
    this.semanticIdentifier,
  });

  final String label;
  final VoidCallback onTap;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.title)),
          const Icon(Icons.chevron_right, color: AppColors.textDim),
        ],
      ),
    );

    final wrapped = semanticIdentifier == null
        ? inner
        : Semantics(identifier: semanticIdentifier, child: inner);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: onTap,
        child: wrapped,
      ),
    );
  }
}
