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
/// Renders a 6dp-tall bar with proportional segments (one per body part
/// that earned XP this session), separated by 2dp gaps that expose the
/// underlying abyss backing. Labels sit below each segment in the
/// corresponding hue.
///
/// **Layout (top to bottom):**
///   * 6dp segmented bar — `Row` of `Expanded(flex: segment.xp)` blocks
///     painted with `ColoredBox(color: segment.hue)`. 2dp `SizedBox` gaps.
///   * 8dp gap.
///   * Label row — matching positions; each label is the BP name from
///     [bodyPartLabels] uppercased, painted in 10sp Barlow Condensed 600
///     +0.20em in the segment hue. Truncates with ellipsis when the
///     segment is too narrow.
///
/// Total height: 6 + 8 + ~14 = ~28dp.
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

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final totalXp = segments.fold<int>(0, (sum, s) => sum + s.xp);
    if (totalXp <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 6,
          child: Row(
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: segments[i].xp,
                  child: ColoredBox(color: segments[i].hue),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: segments[i].xp,
                child: Text(
                  (bodyPartLabels[segments[i].bodyPart] ??
                          segments[i].bodyPart.dbValue)
                      .toUpperCase(),
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.20 * 10,
                    color: segments[i].hue,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
