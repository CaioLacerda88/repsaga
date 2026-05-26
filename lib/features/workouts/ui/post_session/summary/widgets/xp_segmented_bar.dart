import 'package:flutter/material.dart';

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

/// Horizontal segmented XP bar for the S2 Mission Debrief.
///
/// Renders a **16dp-tall** bar with proportional segments (one per body
/// part that earned XP this session), separated by 2dp gaps that expose
/// the underlying abyss backing. Each segment is a plain hue block —
/// labels were dropped per UX-critic round-3 (2026-05-26): on-device the
/// reverse-printed BP names crowded narrow segments and added visual
/// noise above the per-BP rank delta rows that already carry the
/// labeling.
///
/// **Layout:**
///   * 16dp segmented bar — `Row` of `Expanded(flex: segment.xp)` blocks
///     painted with `ColoredBox(color: segment.hue)`.
///   * 2dp `SizedBox` gaps between segments.
///
/// **Defensive cases (render nothing):**
///   * [segments] is empty.
///   * Total XP across segments is 0.
///
/// Callers must decide whether to omit the bar at the parent layer when
/// these branches fire — the widget's `0×0` collapse keeps test fixtures
/// safe but a missing-bar surface design decision belongs upstream.
class XpSegmentedBar extends StatelessWidget {
  const XpSegmentedBar({super.key, required this.segments});

  /// Segments to render. Order is preserved — the caller decides the
  /// painting order (typically XP descending).
  final List<XpBarSegment> segments;

  /// Bar height (mockup §S2 spec, round-3 bump). Public for tests; do not
  /// override at call sites — the design grammar locks 16dp.
  static const double barHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final totalXp = segments.fold<int>(0, (sum, s) => sum + s.xp);
    if (totalXp <= 0) return const SizedBox.shrink();

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'mission-debrief-xp-bar',
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: segments[i].xp,
                child: _XpBarSegmentBlock(hue: segments[i].hue),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One segment block — a hue-tinted `ColoredBox` filling its `Expanded`
/// slot. Pure visual identity; no inner text per UX-critic round-3.
class _XpBarSegmentBlock extends StatelessWidget {
  const _XpBarSegmentBlock({required this.hue});

  final Color hue;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: hue, child: const SizedBox.expand());
  }
}
