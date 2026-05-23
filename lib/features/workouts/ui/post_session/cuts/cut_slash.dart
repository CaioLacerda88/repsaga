import 'dart:math' as math;
import 'dart:ui';

/// Renders the Concept B cut slash — a single thin geometric line
/// (mockup `docs/post-session-screen-mockup-v2.html:920-927`):
///
/// ```css
/// .flash .flash-slash {
///   position: absolute;
///   top: 28%;
///   left: -10%;
///   right: -10%;
///   height: 2px;
///   transform: rotate(-8deg);
/// }
/// ```
///
/// All 7 post-session cut painters share this primitive (the same CSS rule
/// drives every variant). Per-variant `color` + `alpha` is owned by the
/// caller — the geometry stays identical so the visual rhythm reads as one
/// repeated cinematic mark, not seven inconsistent shapes.
///
/// User feedback (on-device, 2026-05-23): "the line that cuts the screen is
/// wide, different from the designs. Can you make the line look more like a
/// line?" — the previous implementation drew a parallelogram quadrilateral
/// spanning ~22% of screen height; this helper restores the spec'd 2dp line.
void paintCutSlash(
  Canvas canvas,
  Size size, {
  required Color color,
  required double alpha,
}) {
  final paint = Paint()
    ..color = color.withValues(alpha: alpha)
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.butt;

  const angleRad = -8 * math.pi / 180;
  final overshoot = size.width * 0.10;
  final halfLen = (size.width + 2 * overshoot) / 2;
  final cx = size.width / 2;
  final cy = size.height * 0.28;
  final dx = halfLen * math.cos(angleRad);
  final dy = halfLen * math.sin(angleRad);

  canvas.drawLine(Offset(cx - dx, cy - dy), Offset(cx + dx, cy + dy), paint);
}
