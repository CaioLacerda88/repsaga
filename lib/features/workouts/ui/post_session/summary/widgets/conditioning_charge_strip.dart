import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../../../../../rpg/domain/body_part_hues.dart';
import '../../../../../rpg/models/body_part.dart';
import '../../../../domain/conditioning_charge.dart';
import '../../cuts/charge_rune.dart';

/// "Conditioning charged" debrief beat — a per-body-part rune charge strip
/// (Phase Vitality-2, user-locked mockup `docs/phase-vitality2-mockups.html`).
///
/// Replaces the single aggregate teal bar. Each trained part with charge
/// data gets a row: a hue-segmented vertical charge rune (filled to the
/// part's AFTER charge level) + the part label (in its identity hue) + a
/// state-aware trailing element — `▲ +N%` for a gainer (same hue) or the
/// held-at-peak word "MÁX" (textDimAA) for a maxed part. Gainer rows sort
/// first (delta-desc); MÁX/held rows sort after. Capped at 4 rows + a
/// "+N more recharged" footer.
///
/// **States** (from [ConditioningCharge]):
///  * gainers + held → delta-ordered rune rows, MÁX rows below.
///  * all-maxed (`allHeld`) → an "all at peak" line above the MÁX rows.
///  * guard (`alreadyChargedToday`) → a single descriptive "already charged
///    today" line, no rune rows.
///
/// **Fill-only safety contract.** The rune never drains or reddens — it only
/// ever fills toward the after level. Copy is past-tense descriptive; there
/// is no decay countdown anywhere (Phase-39 / ToS aligned).
///
/// **Decoupling Rule 2.** All copy is injected pre-localized; the part
/// labels are resolved by the screen layer and passed in via [bodyPartLabels].
class ConditioningChargeStrip extends StatefulWidget {
  const ConditioningChargeStrip({
    super.key,
    required this.charge,
    required this.bodyPartLabels,
    required this.eyebrowLabel,
    required this.deltaLabel,
    required this.maxLabel,
    required this.moreLabel,
    required this.allAtPeakLabel,
    required this.alreadyChargedTodayLabel,
    this.animate = true,
  });

  /// The per-bp charge model. `charge.shouldRender` gates whether this
  /// widget is mounted at all (the section decides); this widget assumes it
  /// has something to show.
  final ConditioningCharge charge;

  /// Pre-resolved body-part display labels keyed by part.
  final Map<BodyPart, String> bodyPartLabels;

  /// Pre-localized bare "Conditioning" eyebrow (uppercased here).
  final String eyebrowLabel;

  /// Pre-localized "+N%" delta builder for a gainer row.
  final String Function(int pct) deltaLabel;

  /// Pre-localized "MÁX" held word (already uppercased).
  final String maxLabel;

  /// Pre-localized "+N more recharged" overflow footer builder.
  final String Function(int count) moreLabel;

  /// Pre-localized "all at peak" line (all-maxed session).
  final String allAtPeakLabel;

  /// Pre-localized "already charged today" guard-state line.
  final String alreadyChargedTodayLabel;

  /// Drives the staggered rune fill. Disabled in tests that assert the
  /// final rendered state without pumping the clock (rune mounts fully lit).
  final bool animate;

  /// Number of segments in a rune. Public for tests.
  static const int runeSegments = 4;

  /// Max gainer/held rows shown before the "+N more" footer.
  static const int maxRows = 4;

  /// Per-row fill duration (animation hook). Public for tests.
  static const Duration fillDuration = Duration(milliseconds: 600);

  @override
  State<ConditioningChargeStrip> createState() =>
      _ConditioningChargeStripState();
}

class _ConditioningChargeStripState extends State<ConditioningChargeStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ConditioningChargeStrip.fillDuration,
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_eyebrow(), const SizedBox(height: 12), ..._body()],
    );
  }

  Widget _eyebrow() {
    return Row(
      children: [
        Text(
          '⚡ ${widget.eyebrowLabel.toUpperCase()}',
          style: AppTextStyles.label.copyWith(
            fontSize: 11,
            letterSpacing: 0.2 * 11,
            color: AppColors.bodyPartCardio,
          ),
        ),
      ],
    );
  }

  List<Widget> _body() {
    // Guard state — the once-per-day step was already taken. Descriptive,
    // rest-positive copy instead of rune rows (never vanishes the beat).
    if (widget.charge.alreadyChargedToday) {
      return [
        Text(
          widget.alreadyChargedTodayLabel,
          style: AppTextStyles.body.copyWith(
            fontSize: 13,
            color: AppColors.textDimAA,
            height: 1.5,
          ),
        ),
      ];
    }

    final parts = widget.charge.parts;
    final visible = parts.take(ConditioningChargeStrip.maxRows).toList();
    final overflow = parts.length - visible.length;

    return [
      // All-maxed session: a positive "everything stayed charged" line above
      // the MÁX rows (no ▲ gainers anywhere).
      if (widget.charge.allHeld)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            widget.allAtPeakLabel,
            style: AppTextStyles.label.copyWith(
              fontSize: 12,
              letterSpacing: 0.06 * 12,
              color: AppColors.bodyPartCardio,
            ),
          ),
        ),
      for (final part in visible)
        _ChargeRow(
          charge: part,
          label: widget.bodyPartLabels[part.bodyPart] ?? part.bodyPart.dbValue,
          deltaLabel: widget.deltaLabel,
          maxLabel: widget.maxLabel,
          progress: _controller,
          animate: widget.animate,
        ),
      if (overflow > 0)
        Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 2),
          child: Text(
            widget.moreLabel(overflow),
            style: AppTextStyles.body.copyWith(
              fontSize: 12.5,
              letterSpacing: 0.02 * 12.5,
              color: AppColors.textDim,
            ),
          ),
        ),
    ];
  }
}

/// One per-body-part rune row: hue rune + hue label + (`▲ +N%` | "MÁX").
class _ChargeRow extends StatelessWidget {
  const _ChargeRow({
    required this.charge,
    required this.label,
    required this.deltaLabel,
    required this.maxLabel,
    required this.progress,
    required this.animate,
  });

  final BodyPartCharge charge;
  final String label;
  final String Function(int pct) deltaLabel;
  final String maxLabel;
  final Animation<double> progress;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final hue = BodyPartHues.hueFor(charge.bodyPart);
    final isMax = charge.isMax;
    final trailingText = isMax ? maxLabel : deltaLabel(charge.deltaPercentInt);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'conditioning-charge-row-${charge.bodyPart.dbValue}',
      // Explicit label so the sibling Text widgets don't merge into a
      // newline-joined AOM name (cluster: aom-label-text-merge).
      label: '$label · $trailingText',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _Rune(hue: hue, afterPct: charge.afterPct, progress: progress),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.title.copyWith(fontSize: 14, color: hue),
              ),
            ),
            const SizedBox(width: 12),
            if (isMax)
              Text(
                maxLabel,
                style: AppTextStyles.numericSmall.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.16 * 11,
                  color: AppColors.textDimAA,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '▲',
                    style: AppTextStyles.numeric.copyWith(
                      fontSize: 11,
                      color: hue,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    deltaLabel(charge.deltaPercentInt),
                    style: AppTextStyles.numeric.copyWith(
                      fontSize: 15,
                      letterSpacing: 0.01 * 15,
                      color: hue,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 4-segment vertical charge rune, filled bottom-up to the part's after
/// charge level in its hue. Lit segments animate in via [progress]; unlit
/// segments read as a dim track. Fill-only — never drains.
///
/// Delegates the segment rendering to the shared [ChargeRune] primitive so
/// the summary strip and the cinematic B2 rune end-cap read identically.
class _Rune extends StatelessWidget {
  const _Rune({
    required this.hue,
    required this.afterPct,
    required this.progress,
  });

  final Color hue;
  final double afterPct;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final litTarget = litSegmentsForFraction(
      afterPct,
      totalSegments: ConditioningChargeStrip.runeSegments,
    );

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        // Staggered fill: at t each successive segment lights as the fill
        // crosses its threshold. Cheap, deterministic, and at t=1 every
        // target segment is lit (test asserts the t=1 state).
        final litNow = (litTarget * progress.value).ceil().clamp(0, litTarget);
        return ChargeRune(
          hue: hue,
          litSegments: litNow,
          totalSegments: ConditioningChargeStrip.runeSegments,
        );
      },
    );
  }
}
