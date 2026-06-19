import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Density variants for [CardioField].
///
/// [compact] is the original (and active-card) size — a 52dp slot with an
/// 18sp value. [large] is the routine-builder variant (Phase 38h): a taller
/// 64dp slot with a 22sp hero value so the target reads as the card's
/// headline. The opt-in default is [compact] so the shared widget never
/// changes the active [CardioEntryCard] (blast-radius rule).
enum CardioFieldSize {
  compact(minHeight: 52, valueFontSize: 18),
  large(minHeight: 64, valueFontSize: 22);

  const CardioFieldSize({required this.minHeight, required this.valueFontSize});

  /// Min slot height — the tap-target floor for the field.
  final double minHeight;

  /// Font size the call site should apply to the filled value [Text] so the
  /// hero numeral matches the slot density.
  final double valueFontSize;
}

/// Shared chrome for the two optional cardio input fields (distance / RPE on
/// the active card; target time / target distance in the routine builder):
/// surface2 fill, hair border, small uppercase label, density-driven tap
/// target.
///
/// Extracted from `cardio_entry_card.dart` so the active logging card and the
/// routine builder share ONE implementation (no clone drift). Pair-rule
/// Semantics (cluster: semantics-identifier-pair-rule + semantics-button-
/// missing) sits on the actual tap target.
///
/// [size] defaults to [CardioFieldSize.compact] — the active-card density.
/// The routine builder opts into [CardioFieldSize.large]; the active card
/// must NOT pass [size] so it renders byte-identically to before (Phase 38h
/// blast-radius rule, pinned by a widget test).
///
/// When [showEditAffordance] is true a small edit (pencil) glyph is overlaid
/// in the top-right corner — the "this filled value is tappable" cue for the
/// routine builder's target slots (Phase 38h 3a). The empty state keeps the
/// `+ add` ghost as its affordance and does not show the pencil.
class CardioField extends StatelessWidget {
  const CardioField({
    required this.identifier,
    required this.semanticsLabel,
    required this.label,
    required this.onTap,
    required this.child,
    this.size = CardioFieldSize.compact,
    this.showEditAffordance = false,
    super.key,
  });

  final String identifier;
  final String semanticsLabel;
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final CardioFieldSize size;
  final bool showEditAffordance;

  @override
  Widget build(BuildContext context) {
    final inner = Column(
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
    );

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
            constraints: BoxConstraints(minHeight: size.minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hair),
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: ExcludeSemantics(
              child: showEditAffordance
                  ? Stack(
                      children: [
                        inner,
                        const Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.edit,
                            size: 16,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    )
                  : inner,
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
