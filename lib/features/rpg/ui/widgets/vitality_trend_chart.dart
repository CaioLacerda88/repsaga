import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/stats_deep_dive_state.dart';
import '../utils/vitality_state_styles.dart';

/// Per-body-part Vitality % trend chart for `/saga/stats`.
///
/// Renders six lines (one per active body part) over the same X-axis. The
/// **selected** body part is drawn in its `bodyPartColor` at full saturation,
/// 2.5sp stroke, with a terminal dot + percent label at the right edge. The
/// other five lines render as ghost color (each body-part's identity color at
/// 35% opacity, 1sp stroke — the UX-critic amendment that locks the visual
/// hierarchy: one figure-line, five identity-tinted ground-lines).
///
/// **Hybrid X-axis (per amendment #2):**
///   * `<30 days` of activity → narrow window from earliest activity to today,
///     left label = `"<n> day(s) ago"`, right label = "Today".
///   * `>=30 days` of activity → rolling 90-day window, left label =
///     `"90 days ago"`, right label = "Today".
///
/// **Anti-pattern locks (per UX critic):**
///   * No grid lines (anti-pattern lock #1) — the chart is a lyrical line, not
///     a quantitative ledger.
///   * No tooltip / no touch interaction (`LineTouchData(enabled: false)`).
///   * Y-axis fixed 0..100 — every line shares the same vertical scale so
///     "Chest at 80%" reads visually identical on this chart and on the
///     vitality table below.
///   * Two Y labels only (0% and 100%) — the spec is "two anchors, no scale".
///   * `FlBorderData(show: false)` — no chart frame.
///
/// **Animation:** fl_chart automatically interpolates between successive
/// [LineChartData] instances over 200ms when the underlying spots change.
/// Selecting a different body part rebuilds with a different
/// `selectedBodyPart` — the chart cross-fades the saturation/stroke values
/// without bespoke `AnimationController` plumbing.
class VitalityTrendChart extends StatelessWidget {
  const VitalityTrendChart({
    super.key,
    required this.trendByBodyPart,
    required this.selectedBodyPart,
    required this.windowStart,
    required this.windowEnd,
    required this.useNarrowWindow,
  });

  /// Per-body-part daily traces. Body parts that don't appear in the map
  /// (or appear with an empty list) render as a flat-zero line.
  final Map<BodyPart, List<TrendPoint>> trendByBodyPart;

  /// The body part whose line is drawn vivid + terminal-dot.
  final BodyPart selectedBodyPart;

  /// Inclusive left edge of the X-axis (UTC midnight).
  final DateTime windowStart;

  /// Inclusive right edge of the X-axis ("today" UTC midnight).
  final DateTime windowEnd;

  /// True when the window is < 30 days (the user's first month).
  /// Drives the left X-axis label between "N days ago" and "90 days ago".
  final bool useNarrowWindow;

  /// Total chart height, including X-axis labels.
  static const double chartHeight = 200;

  /// Plain line stroke — used for the selected body part.
  static const double _selectedLineWidth = 2.5;

  /// Ghost line stroke — used for the five unselected body parts.
  static const double _ghostLineWidth = 1.0;

  /// Ghost line opacity — Phase 26c: 35% alpha applied to each line's
  /// body-part identity color so the six lines on the chart line up with
  /// the six row dots on the vitality table below (was a single textDim
  /// ghost at 30% alpha pre-26c).
  static const double _ghostOpacity = 0.35;

  /// Reserved horizontal space for the Y-axis labels (`0%`, `100%`).
  static const double _yAxisReservedWidth = 28;

  /// Reserved vertical space for the X-axis labels.
  static const double _xAxisReservedHeight = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spanDays = windowEnd.difference(windowStart).inDays;
    // Guard against degenerate empty window — shouldn't happen but a 0-span
    // would make `xMax = 0` and crash the FlSpot rasteriser.
    final xMax = spanDays <= 0 ? 1.0 : spanDays.toDouble();

    final selectedColor =
        VitalityStateStyles.bodyPartColor[selectedBodyPart] ??
        AppColors.hotViolet;

    // Build the line series per body part. Selected goes last so its dots
    // paint on top of the ghost lines.
    final lineBars = <LineChartBarData>[];
    LineChartBarData? selectedBar;
    double? terminalPctForLabel;

    for (final bp in activeBodyParts) {
      final points = trendByBodyPart[bp] ?? const <TrendPoint>[];
      final spots = _buildSpots(
        points: points,
        windowStart: windowStart,
        spanDays: spanDays,
      );
      final isSelected = bp == selectedBodyPart;

      if (isSelected) {
        selectedBar = LineChartBarData(
          spots: spots,
          isCurved: false,
          color: selectedColor,
          barWidth: _selectedLineWidth,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: spots.isNotEmpty,
            // Draw the terminal dot only — every other dot is suppressed so
            // the line reads as a continuous gesture, not a connect-the-dots
            // exercise.
            getDotPainter: (spot, percent, bar, index) {
              if (index != spots.length - 1) {
                // Suppression dot — zero-radius, fully transparent. Using
                // Colors.transparent keeps us out of the hardcoded-color
                // sweep without inventing a new palette token for an
                // invisible primitive.
                return FlDotCirclePainter(
                  radius: 0,
                  color: Colors.transparent,
                  strokeWidth: 0,
                );
              }
              return FlDotCirclePainter(
                radius: 4.5,
                color: selectedColor,
                strokeWidth: 0,
              );
            },
          ),
          belowBarData: BarAreaData(show: false),
        );
        if (spots.isNotEmpty) terminalPctForLabel = spots.last.y;
      } else {
        // Phase 26c (Task 7): ghost lines now carry their OWN body-part
        // identity color at 35% alpha (was a single textDim ghost pre-26c).
        // Lines up the six chart lines with the six identity-colored row
        // dots on the vitality table below it.
        final ghostColor =
            (VitalityStateStyles.bodyPartColor[bp] ?? AppColors.textDim)
                .withValues(alpha: _ghostOpacity);
        lineBars.add(
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: ghostColor,
            barWidth: _ghostLineWidth,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }
    if (selectedBar != null) lineBars.add(selectedBar);

    return Semantics(
      container: true,
      identifier: 'vitality-trend-chart',
      label: 'vitality trend chart',
      child: SizedBox(
        height: chartHeight,
        child: Stack(
          children: [
            LineChart(
              LineChartData(
                minX: 0,
                maxX: xMax,
                // L9 round 2: both top AND bottom now carry headroom because
                // ghost lines at exactly 0% (untrained or zero-vitality body
                // parts) and exactly 100% (peaking body parts like
                // Braços-100% in the launch screenshot) draw flush against
                // the chart's visual edges and read as "ugly borders" no
                // matter how the frame/grid is configured. Pushing the
                // plot range to -8..108 keeps the 0 and 100 axis labels
                // anchored (the Y-titles widget filters to value == 0 / 100
                // explicitly so the labels don't shift), while the lines
                // themselves render visibly INSIDE the plot area with
                // breathing room. `clipData: FlClipData.all()` keeps them
                // from leaking into the surrounding padding.
                minY: -8,
                maxY: 108,
                // L18.2: leave the RIGHT side unclipped so the selected
                // line's 4.5dp terminal dot can extend past the plot
                // boundary into the 24dp outer right padding (which is
                // still on-screen). With `FlClipData.all()` the dot was
                // sliced in half at the plot's right edge — the user
                // surfaces it as "the dot is cut at the phone screen."
                // Left/top/bottom stay clipped so the original L9 fix
                // (ghost lines bleeding past the plot frame) holds.
                clipData: const FlClipData(
                  top: true,
                  bottom: true,
                  left: true,
                  right: false,
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _yAxisReservedWidth,
                      interval: 100,
                      getTitlesWidget: (value, meta) {
                        // Only label 0 and 100; every other tick is silent.
                        if (value != 0 && value != 100) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${value.round()}%',
                            // Y-axis percentage — numeric data, Rajdhani.
                            style: AppTextStyles.numeric.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDim,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _xAxisReservedHeight,
                      interval: xMax,
                      getTitlesWidget: (value, meta) {
                        // Two labels only: left edge (windowStart) + right
                        // edge (today). The middle of the X-axis is silent
                        // by design — anti-pattern lock #1 (no grid) means
                        // the user reads "rough left" → "rough right" with
                        // the line itself doing the math.
                        if (value == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _leftLabel(l10n: l10n, spanDays: spanDays),
                              style: AppTextStyles.label.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.12 * 10,
                                color: AppColors.textDim,
                              ),
                            ),
                          );
                        }
                        if (value == xMax) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l10n.chartXLabelToday,
                              style: AppTextStyles.label.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.12 * 10,
                                color: AppColors.textDim,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: lineBars,
              ),
              // Phase 26c: 180ms (was 200ms) per locked-decision tween spec.
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            ),
            // Terminal % label — anchored by the chart's data-coordinate-to-
            // pixel mapping is impractical from outside fl_chart, so we
            // approximate by floating the label at the right edge at the
            // height proportional to terminalPctForLabel. Suppressed when
            // the selected series has no data (a body part the user has
            // never trained in this window — the line is flat at 0 and a
            // "0%" label adds nothing).
            if (terminalPctForLabel != null && terminalPctForLabel > 0)
              _TerminalPctLabel(
                pct: terminalPctForLabel,
                color: selectedColor,
                yAxisReservedWidth: _yAxisReservedWidth,
                xAxisReservedHeight: _xAxisReservedHeight,
              ),
          ],
        ),
      ),
    );
  }

  /// Build the pixel-aligned spots for a body part's daily trace. We map each
  /// [TrendPoint] to `x = days-since-windowStart`, `y = pct * 100`. Points
  /// outside the window are filtered out (defensive — the provider should
  /// already trim to window).
  ///
  /// Empty inputs (the user has never trained this body part in the window,
  /// or all known points fall outside the window) return an empty spot list
  /// so fl_chart paints nothing for that bar. The L9 fix: the previous
  /// fallback emitted a `[(0, 0), (spanDays, 0)]` flat-zero baseline which
  /// fl_chart rendered as a horizontal line at y=0 spanning the full chart
  /// width — read as an "ugly bottom border" frame artifact on the deep-dive
  /// screen. Returning empty is safe: fl_chart's `drawBarLine` is a no-op on
  /// empty spots, the bar still occupies its slot in `lineBarsData` so per-
  /// body-part ordering stays stable, and selection swaps continue to find
  /// the right bar by color.
  static List<FlSpot> _buildSpots({
    required List<TrendPoint> points,
    required DateTime windowStart,
    required int spanDays,
  }) {
    if (points.isEmpty) {
      return const <FlSpot>[];
    }
    final spots = <FlSpot>[];
    for (final p in points) {
      final dayOffset = p.date.difference(windowStart).inDays;
      if (dayOffset < 0 || dayOffset > spanDays) continue;
      spots.add(FlSpot(dayOffset.toDouble(), p.pct * 100));
    }
    return spots;
  }

  /// Pick the left-edge X-axis label per the hybrid-window rule. We compute
  /// from [spanDays] rather than peeking at [useNarrowWindow] alone so the
  /// "1 day ago" / "N days ago" pluralization stays attached to the actual
  /// span, not a separate variable that could drift.
  String _leftLabel({required AppLocalizations l10n, required int spanDays}) {
    if (!useNarrowWindow) {
      return l10n.chartXLabel90DaysAgo;
    }
    return l10n.chartXLabelDaysAgo(spanDays);
  }
}

/// Floating "% terminal" label rendered at the right edge of the chart, above
/// the selected line's terminal dot. Lives outside [VitalityTrendChart] as a
/// dedicated widget so the LayoutBuilder closure can close over a
/// non-nullable [pct] value (Dart can't promote a nullable instance field
/// across a closure boundary in [VitalityTrendChart.build]).
class _TerminalPctLabel extends StatelessWidget {
  const _TerminalPctLabel({
    required this.pct,
    required this.color,
    required this.yAxisReservedWidth,
    required this.xAxisReservedHeight,
  });

  /// The terminal Y-value (already in the 0..100 chart space).
  final double pct;
  final Color color;
  final double yAxisReservedWidth;
  final double xAxisReservedHeight;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Plot area excludes the left + bottom reserved sizes.
          final plotWidth = constraints.maxWidth - yAxisReservedWidth;
          final plotHeight = constraints.maxHeight - xAxisReservedHeight;
          // Map % → vertical pixel offset within the plot area (top = 100%,
          // bottom = 0%). Label sits ~22dp above the dot.
          final dotY = plotHeight * (1 - (pct / 100));
          return Stack(
            children: [
              Positioned(
                left: yAxisReservedWidth + plotWidth - 36,
                top: (dotY - 22).clamp(0, plotHeight - 18),
                child: Text(
                  '${pct.round()}%',
                  // Route through `AppTextStyles.numeric` per the
                  // typography call-site rule (memory:
                  // `project_design_language_typography`). The pre-L13.4
                  // build raw-instantiated `TextStyle(fontFamily:
                  // 'Rajdhani', ...)` here; the L13.4 shadow halo
                  // extension preserved that anti-pattern. Now reaches
                  // the same Rajdhani 700 tabular figures via the
                  // sanctioned entry point, with the chart-specific
                  // overrides (smaller 14sp size, per-body-part color,
                  // tight 1.0 line height) layered via `copyWith`. The
                  // L18.2 multi-pass abyss-colored halo (three Shadow
                  // passes) masks the chart line where it passes behind
                  // the label — without it the line and label (same
                  // body-part color) visually merge whenever the line
                  // is flat near the label's Y position.
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 14,
                    color: color,
                    height: 1,
                    shadows: const [
                      Shadow(color: AppColors.abyss, blurRadius: 3),
                      Shadow(color: AppColors.abyss, blurRadius: 3),
                      Shadow(color: AppColors.abyss, blurRadius: 3),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
