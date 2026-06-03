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
    final tapTarget = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.title)),
              const Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );

    if (semanticIdentifier == null) return tapTarget;

    // Cluster: semantics-identifier-pair-rule — container:true +
    // explicitChildNodes:true wrap the actual tap target (Material →
    // InkWell). Without them the AOM silently drops the
    // flt-semantics-identifier attribute on rebuild, and the inner Text
    // would merge up into the same node (cluster: aom-label-text-merge).
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: semanticIdentifier!,
      child: tapTarget,
    );
  }
}
