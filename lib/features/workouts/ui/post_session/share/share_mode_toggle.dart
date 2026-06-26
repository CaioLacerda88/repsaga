import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/share_mode.dart';

/// Two-segment toggle for the Phase 39 share content mode — Bestiary
/// (creature) vs Clean Flex (stats), spec §7.
///
/// **Orthogonal to the photo/discreet axis.** This switches the BOTTOM
/// content block only; the photo-hero + 7-hue rail + wordmark chassis is
/// shared across both. The user can flip modes freely on the preview screen;
/// the parent persists the chosen mode as the new default.
///
/// **Decoupling Rule 2.** Both segment labels arrive pre-localized; the
/// widget never reads `AppLocalizations.of(context)`.
class ShareModeToggle extends StatelessWidget {
  const ShareModeToggle({
    super.key,
    required this.mode,
    required this.bestiaryLabel,
    required this.cleanFlexLabel,
    required this.onChanged,
  });

  /// Currently-selected mode (drives the highlighted segment).
  final ShareMode mode;

  /// Pre-localized "Bestiary" segment label.
  final String bestiaryLabel;

  /// Pre-localized "Clean Flex" segment label.
  final String cleanFlexLabel;

  /// Selection callback. `null` disables the toggle (e.g. while busy).
  final ValueChanged<ShareMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'share-mode-toggle',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            _Segment(
              identifier: 'share-mode-toggle-bestiary',
              label: bestiaryLabel,
              selected: mode == ShareMode.bestiary,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(ShareMode.bestiary),
            ),
            _Segment(
              identifier: 'share-mode-toggle-clean-flex',
              label: cleanFlexLabel,
              selected: mode == ShareMode.cleanFlex,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(ShareMode.cleanFlex),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.identifier,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String identifier;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: identifier,
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.primaryViolet : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(
                  color: selected ? AppColors.textCream : AppColors.textDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
