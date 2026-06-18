import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Shared chrome for the two optional cardio input fields (distance / RPE on
/// the active card; target time / target distance in the routine builder):
/// surface2 fill, hair border, small uppercase label, ≥52dp tap target.
///
/// Extracted from `cardio_entry_card.dart` so the active logging card and the
/// routine builder share ONE implementation (no clone drift). Pair-rule
/// Semantics (cluster: semantics-identifier-pair-rule + semantics-button-
/// missing) sits on the actual tap target.
class CardioField extends StatelessWidget {
  const CardioField({
    required this.identifier,
    required this.semanticsLabel,
    required this.label,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String identifier;
  final String semanticsLabel;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: identifier,
      label: semanticsLabel,
      button: true,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(kRadiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSm),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hair),
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 10,
                      color: AppColors.textCream.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `+ adicionar` ghost — the invite-not-nag affordance for an empty optional
/// field (the locked mockup grammar: never nag with `0.0 km`).
class GhostValue extends StatelessWidget {
  const GhostValue({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.bodySmall.copyWith(fontSize: 13));
  }
}

/// `<ACTIVITY> · CARDIO` eyebrow line — teal-dim label register, mapped from
/// the exercise slug. Unknown / user-created cardio slugs fall back to the
/// bare "CARDIO" eyebrow (never a raw slug — cluster:
/// slug-rendered-as-display-name).
class CardioEyebrow extends StatelessWidget {
  const CardioEyebrow({required this.slug, super.key});

  final String? slug;

  static String? _activityLabel(String? slug, AppLocalizations l10n) {
    return switch (slug) {
      'treadmill' => l10n.cardioActivityRunning,
      'rowing_machine' => l10n.cardioActivityRowing,
      'stationary_bike' || 'assault_bike' => l10n.cardioActivityCycling,
      'jump_rope' => l10n.cardioActivityJumpRope,
      'elliptical' => l10n.cardioActivityElliptical,
      'sled_push' || 'sled_drag' => l10n.cardioActivitySled,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activity = _activityLabel(slug, l10n);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        activity != null
            ? l10n.cardioEyebrow(activity)
            : l10n.cardioEyebrowGeneric,
        style: AppTextStyles.label.copyWith(
          color: AppColors.bodyPartCardio.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
