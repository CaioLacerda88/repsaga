import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../../../../../rpg/models/body_part.dart';

/// One segment of the [XpSegmentedBar] — body-part identity + XP weight +
/// hue. Each segment paints as a `ColoredBox` with width ∝ `xp / totalXp`.
///
/// **Decoupling Rule 1 (pure data).** No widgets, no `BuildContext`.
@immutable
class XpBarSegment {
  const XpBarSegment({
    required this.bodyPart,
    required this.hue,
    required this.xp,
  });

  final BodyPart bodyPart;
  final Color hue;
  final int xp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XpBarSegment &&
          other.bodyPart == bodyPart &&
          other.hue == hue &&
          other.xp == xp;

  @override
  int get hashCode => Object.hash(bodyPart, hue, xp);
}

/// Horizontal segmented XP bar for the S2 Mission Debrief (Phase 31 Pass 3).
///
/// Renders a **14dp-tall** bar with proportional segments (one per body
/// part that earned XP this session), separated by 2dp gaps that expose
/// the underlying abyss backing. Each segment's BP name renders INSIDE
/// the colored block (reverse-printed in `abyss` so the dark text rides
/// on the hue background — locked design grammar per
/// `docs/post-phase-30-design-exploration.html` § Surface 2 mockup).
///
/// **Layout:**
///   * 14dp segmented bar — `Row` of `Expanded(flex: segment.xp)` blocks
///     painted with `ColoredBox(color: segment.hue)`. Each block holds
///     a centered Text label (BP name uppercased) in `abyss` color.
///     Narrow segments (< ~24dp paint width) drop their label so
///     overflow never bleeds — `OverflowBox` trick not needed because
///     the Text uses `TextOverflow.ellipsis` and `maxLines: 1` with a
///     `softWrap: false` for tighter clipping.
///   * 2dp `SizedBox` gaps between segments.
///
/// **Phase 31 device-fix (Bug B):** pre-fix the bar was a 6dp-tall row
/// with labels in a separate row below. On the device the 6dp height
/// was effectively invisible against the abyss background — the user
/// couldn't see the hue blocks. Per the mockup spec the bar is 14dp
/// with labels reverse-printed inside. This commit aligns the
/// implementation with the locked mockup.
///
/// **Defensive cases (render nothing):**
///   * [segments] is empty.
///   * Total XP across segments is 0.
///
/// Callers must decide whether to omit the bar at the parent layer when
/// these branches fire — the widget's `0×0` collapse keeps test fixtures
/// safe but a missing-bar surface design decision belongs upstream.
class XpSegmentedBar extends StatelessWidget {
  const XpSegmentedBar({
    super.key,
    required this.bodyPartLabels,
    required this.segments,
  });

  /// Per-BP localized name lookup. Already-localized strings (Decoupling
  /// Rule 2 — widget never reads `AppLocalizations.of(context)`).
  final Map<BodyPart, String> bodyPartLabels;

  /// Segments to render. Order is preserved — the caller decides the
  /// painting order (typically XP descending).
  final List<XpBarSegment> segments;

  /// Bar height (mockup §S2 spec). Public for tests; do not override at
  /// call sites — the design grammar locks 14dp.
  static const double barHeight = 14.0;

  /// Minimum paint-width a segment needs before its label renders. Below
  /// this threshold the label drops (the colored block still paints so
  /// the BP's XP contribution stays visible — just unlabeled).
  static const double _minLabelSegmentWidth = 24.0;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final totalXp = segments.fold<int>(0, (sum, s) => sum + s.xp);
    if (totalXp <= 0) return const SizedBox.shrink();

    // LayoutBuilder gives us the bar's actual paint width so we can
    // decide per-segment whether the label fits. A 1xp segment in a
    // 1001xp total renders at ~0.4dp wide on a 412dp viewport — far
    // below readable width; dropping the label keeps the block clean.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'mission-debrief-xp-bar',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Subtract the 2dp gap widths from the available space so
          // segment-width estimates match the laid-out reality.
          final gapCount = segments.length - 1;
          final paintableWidth = (constraints.maxWidth - gapCount * 2.0).clamp(
            0.0,
            double.infinity,
          );
          return SizedBox(
            height: barHeight,
            child: Row(
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: segments[i].xp,
                    child: _XpBarSegmentBlock(
                      hue: segments[i].hue,
                      label:
                          (bodyPartLabels[segments[i].bodyPart] ??
                                  segments[i].bodyPart.dbValue)
                              .toUpperCase(),
                      estimatedWidth: paintableWidth * segments[i].xp / totalXp,
                      minLabelWidth: _minLabelSegmentWidth,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One segment block — a hue-tinted `ColoredBox` with the BP label
/// reverse-printed inside in `abyss`. Drops the label when the
/// estimated paint width falls below [minLabelWidth] so narrow
/// segments don't visually clutter or overflow.
class _XpBarSegmentBlock extends StatelessWidget {
  const _XpBarSegmentBlock({
    required this.hue,
    required this.label,
    required this.estimatedWidth,
    required this.minLabelWidth,
  });

  final Color hue;
  final String label;
  final double estimatedWidth;
  final double minLabelWidth;

  @override
  Widget build(BuildContext context) {
    final showLabel = estimatedWidth >= minLabelWidth;
    return ColoredBox(
      color: hue,
      child: showLabel
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.20 * 10,
                    color: AppColors.abyss,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
