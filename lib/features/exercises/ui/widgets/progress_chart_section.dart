import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/date_format.dart';
import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reward_accent.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../models/progress_point.dart';
import '../../providers/exercise_progress_provider.dart';

/// PR ring accent color — the hollow gold ring drawn on the all-time-PR
/// dot. `FlDotPainter` callbacks have no `BuildContext`, so the widget-
/// tree `RewardAccent.of(context)` lookup is unavailable here; we read
/// the static alias and carry the opt-out marker on the preceding line.
// ignore: reward_accent — FlDotPainter has no BuildContext ancestor
const Color _prRingAccent = RewardAccent.color;

/// Primary metric for the progress chart.
///
/// `e1RM` is the default — an Epley-normalized view that stays honest through
/// programming switches (5×5 → 3×10 won't look like a drop). `weight` shows
/// the raw max working-set weight per day and is used by lifters who only
/// care about the plate count.
enum ChartMetric { e1rm, weight }

/// Per-exercise weight-over-time chart.
///
/// Renders inline inside the exercise detail screen. Read-only glance
/// surface: no tooltips, no zoom, no pan. See `tasks/backlog.md` BL-3 for
/// the converged PO + UX spec — anti-generic-AI constraints (no gradient
/// fill, no bezier, no card shadow, hollow PR ring with gold outer) are
/// non-negotiable and tested in
/// `test/widget/features/exercises/widgets/progress_chart_section_test.dart`.
///
/// [prValue] — optional all-time PR weight threaded from
/// `exercisePRsProvider`. When in Weight mode AND a dot's y matches, the
/// gold PR ring anchors there (celebrates the all-time PR). Otherwise the
/// ring falls back to the in-window peak.
class ProgressChartSection extends ConsumerStatefulWidget {
  const ProgressChartSection({
    super.key,
    required this.exerciseId,
    this.prValue,
  });

  final String exerciseId;
  final double? prValue;

  /// Plot-area height when the series is sparse (fewer than 4 points). A
  /// taller canvas around 3 dots looks empty; 120dp keeps it proportional.
  static const double _canvasSparse = 120;

  /// Plot-area height for mid / rich series (4+ points).
  static const double _canvasDense = 200;

  /// Left reserved axis width for the 3 y-axis ticks + unit suffix.
  static const double _yAxisReservedWidth = 36;

  static const double _lineWidth = 3;
  static const double _dotRadius = 4;

  /// PR ring geometry — intentionally larger than the plain 8dp dots so the
  /// ring pops. Inner hollow circle 5dp + 2dp stroke + 3dp outer gap → total
  /// 10dp diameter (2dp delta vs plain dots).
  static const double _prRingInnerRadius = 5;
  static const double _prRingStroke = 2;
  static const double _prRingOuterGap = 3;

  @override
  ConsumerState<ProgressChartSection> createState() =>
      _ProgressChartSectionState();
}

class _ProgressChartSectionState extends ConsumerState<ProgressChartSection> {
  TimeWindow _window = TimeWindow.last30Days;
  ChartMetric _metric = ChartMetric.e1rm;

  @override
  void didUpdateWidget(covariant ProgressChartSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset window + metric to defaults whenever the host rebuilds with a
    // different exercise — guarantees per-exercise isolation.
    if (oldWidget.exerciseId != widget.exerciseId) {
      _window = TimeWindow.last30Days;
      _metric = ChartMetric.e1rm;
    }
  }

  String _windowLabel(TimeWindow w, AppLocalizations l10n) => switch (w) {
    TimeWindow.last30Days => l10n.chartWindowDays30,
    TimeWindow.last90Days => l10n.chartWindowDays90,
    TimeWindow.allTime => l10n.chartWindowAllTime,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncData = ref.watch(
      exerciseProgressProvider(
        ExerciseProgressKey(exerciseId: widget.exerciseId, window: _window),
      ),
    );
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    final l10n = AppLocalizations.of(context);

    return asyncData.when(
      loading: () => _ChartCard(
        child: SizedBox(
          height: ProgressChartSection._canvasDense,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      error: (_, _) => _ChartCard(
        child: _TrendRow(
          metric: _metric,
          window: _window,
          onWindowChanged: (w) => setState(() => _window = w),
          onMetricChanged: (m) => setState(() => _metric = m),
          trendText: l10n.couldNotLoadProgress,
          trendColor: theme.colorScheme.onSurface.withValues(alpha: 0.70),
          windowLabel: _windowLabel(_window, l10n),
          weightUnit: weightUnit,
        ),
      ),
      data: (data) {
        return _ChartBody(
          rawPoints: data.rawPoints,
          e1rmPoints: data.e1rmPoints,
          workoutCount: data.workoutCount,
          window: _window,
          metric: _metric,
          weightUnit: weightUnit,
          prValue: widget.prValue,
          windowLabel: _windowLabel(_window, l10n),
          onWindowChanged: (w) => setState(() => _window = w),
          onMetricChanged: (m) => setState(() => _metric = m),
        );
      },
    );
  }
}

/// Assemble the chart body from the resolved data. Responsible for:
/// - picking the active series (e1RM vs raw Weight),
/// - computing the trend copy + color,
/// - handing the series to [_LineChart],
/// - or rendering the 0-data empty state when there's nothing to plot.
class _ChartBody extends StatelessWidget {
  const _ChartBody({
    required this.rawPoints,
    required this.e1rmPoints,
    required this.workoutCount,
    required this.window,
    required this.metric,
    required this.weightUnit,
    required this.prValue,
    required this.windowLabel,
    required this.onWindowChanged,
    required this.onMetricChanged,
  });

  final List<ProgressPoint> rawPoints;
  final List<ProgressPoint> e1rmPoints;
  final int workoutCount;
  final TimeWindow window;
  final ChartMetric metric;
  final String weightUnit;
  final double? prValue;
  final String windowLabel;
  final ValueChanged<TimeWindow> onWindowChanged;
  final ValueChanged<ChartMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface70 = theme.colorScheme.onSurface.withValues(alpha: 0.70);

    // Zero-data empty state — render the dashed-ish container and leave
    // the window/metric toggles off (no data to toggle between). Guard on
    // workoutCount only: a workoutCount > 0 with both series empty means the
    // user logged something unchartable (bodyweight-only / all warmups) and
    // should see the "N workouts logged" copy, not the first-log empty state
    // (review IMPORTANT #1).
    if (workoutCount == 0) {
      return _ChartCard(
        child: Container(
          key: const Key('progress-chart-empty-container'),
          height: 100,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Semantics(
            container: true,
            identifier: 'exercise-detail-chart-empty',
            child: Text(
              AppLocalizations.of(context).logFirstSetToTrack,
              style: theme.textTheme.bodyMedium?.copyWith(color: onSurface70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Pick the pre-ranked series for the current metric. No inline Epley
    // re-mapping: the provider already built an e1RM-ranked series (whose
    // per-day peak can differ from the raw-weight peak, e.g. 100×10 beats
    // 110×3 on e1RM). See [ExerciseProgressData] for the review BLOCKER.
    final sourcePoints = metric == ChartMetric.e1rm ? e1rmPoints : rawPoints;
    final series = _buildSeries(sourcePoints, window: window);

    final locale = Localizations.localeOf(context).languageCode;
    // Trend copy per acceptance #6.
    final (trendText, trendColor) = _buildTrendCopy(
      series: series,
      workoutCount: workoutCount,
      weightUnit: weightUnit,
      windowLabel: windowLabel,
      theme: theme,
      l10n: AppLocalizations.of(context),
      locale: locale,
    );

    // No plottable series but workouts exist → render the toggles + copy
    // without a chart. Happens when `points.length == 1` (all on same day).
    if (series.length < 2) {
      return _ChartCard(
        child: _TrendRow(
          metric: metric,
          window: window,
          onWindowChanged: onWindowChanged,
          onMetricChanged: onMetricChanged,
          trendText: trendText,
          trendColor: trendColor,
          windowLabel: windowLabel,
          weightUnit: weightUnit,
          canvas: series.length == 1
              ? _singlePointCanvas(theme, series.single, weightUnit, locale)
              : null,
        ),
      );
    }

    final canvasHeight = series.length < 4
        ? ProgressChartSection._canvasSparse
        : ProgressChartSection._canvasDense;

    // PR ring anchor: prefer the all-time prValue if it matches a visible
    // dot in Weight mode, otherwise the peak of the visible series.
    final ringAnchor = _resolveRingAnchor(series, metric, prValue);

    return _ChartCard(
      child: _TrendRow(
        metric: metric,
        window: window,
        onWindowChanged: onWindowChanged,
        onMetricChanged: onMetricChanged,
        trendText: trendText,
        trendColor: trendColor,
        windowLabel: windowLabel,
        weightUnit: weightUnit,
        canvas: SizedBox(
          key: const Key('progress-chart-canvas'),
          height: canvasHeight,
          child: _LineChart(
            points: series,
            ringAnchorIndex: ringAnchor.index,
            ringAnchorValue: ringAnchor.value,
            weightUnit: weightUnit,
          ),
        ),
      ),
    );
  }

  /// Single-point series — render a soft pill with the value instead of a
  /// lonely dot floating in whitespace.
  Widget _singlePointCanvas(
    ThemeData theme,
    ProgressPoint point,
    String weightUnit,
    String locale,
  ) {
    return SizedBox(
      key: const Key('progress-chart-canvas'),
      height: ProgressChartSection._canvasSparse,
      child: Center(
        child: Text(
          AppNumberFormat.weightWithUnit(
            point.weight,
            locale: locale,
            unit: weightUnit,
          ),
          style: AppTextStyles.numeric.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Reusable card chrome — the dark container behind every non-loading state.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('progress-chart-card'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// Trend copy + window toggle + compact metric cycle, all on one row. The
/// metric toggle is a subordinate `TextButton` that cycles e1RM ↔ Weight on
/// tap — a full `SegmentedButton<ChartMetric>` would dominate the sparse
/// 120dp canvas. Trend copy takes `Expanded` and may wrap to 2 lines on very
/// narrow widths rather than truncate.
class _TrendRow extends StatelessWidget {
  const _TrendRow({
    required this.metric,
    required this.window,
    required this.onWindowChanged,
    required this.onMetricChanged,
    required this.trendText,
    required this.trendColor,
    required this.windowLabel,
    required this.weightUnit,
    this.canvas,
  });

  final ChartMetric metric;
  final TimeWindow window;
  final ValueChanged<TimeWindow> onWindowChanged;
  final ValueChanged<ChartMetric> onMetricChanged;
  final String trendText;
  final Color trendColor;
  final String windowLabel;
  final String weightUnit;

  /// The chart canvas (or a single-point summary). When `null`, no plot area
  /// renders — used by the error + same-day-N-workouts states.
  final Widget? canvas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final metricLabel = metric == ChartMetric.e1rm
        ? l10n.chartMetricE1rm
        : l10n.chartMetricWeight;
    // Announce the *next* state in the Semantics label so screen readers
    // hear the affordance, not the current value. Computed inline per
    // review NIT #1 — no need to lift to a local.
    final nextMetricLabel = metric == ChartMetric.e1rm
        ? l10n.chartMetricWeight
        : l10n.chartMetricE1rm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                trendText,
                style: theme.textTheme.bodyMedium?.copyWith(color: trendColor),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<TimeWindow>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment(
                  value: TimeWindow.last30Days,
                  label: Text(l10n.last30Days),
                ),
                ButtonSegment(
                  value: TimeWindow.last90Days,
                  label: Text(l10n.last90Days),
                ),
                ButtonSegment(
                  value: TimeWindow.allTime,
                  label: Text(l10n.allTime),
                ),
              ],
              selected: {window},
              onSelectionChanged: (s) => onWindowChanged(s.first),
            ),
            const SizedBox(width: 4),
            // Subordinate metric cycle — one label, one tap, one style step
            // down from the window segments.
            Semantics(
              label: l10n.switchMetricTo(nextMetricLabel),
              button: true,
              child: TextButton(
                onPressed: () => onMetricChanged(
                  metric == ChartMetric.e1rm
                      ? ChartMetric.weight
                      : ChartMetric.e1rm,
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.70,
                  ),
                  textStyle: theme.textTheme.labelSmall,
                ),
                child: Text(metricLabel),
              ),
            ),
          ],
        ),
        if (canvas != null) ...[const SizedBox(height: 12), canvas!],
      ],
    );
  }
}

/// The actual fl_chart line renderer with labeled Y-axis + X-axis dates +
/// PR ring overlay.
class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.points,
    required this.ringAnchorIndex,
    required this.ringAnchorValue,
    required this.weightUnit,
  });

  final List<ProgressPoint> points;

  /// Index of the dot (in the visible series) where the PR ring should
  /// render. `-1` when no valid anchor.
  final int ringAnchorIndex;

  /// The y-value at the ring anchor — surfaced in a Semantics label so
  /// tests can assert which dot the ring follows (all-time vs in-window).
  final double ringAnchorValue;

  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final locale = Localizations.localeOf(context).languageCode;

    // Y-range: pad = max(span × 0.15, maxValue × 0.10) — per acceptance #3.
    final weights = points.map((p) => p.weight).toList();
    final rawMin = weights.reduce((a, b) => a < b ? a : b);
    final rawMax = weights.reduce((a, b) => a > b ? a : b);
    final span = rawMax - rawMin;
    final pad = [
      span * 0.15,
      rawMax * 0.10,
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    final yMin = (rawMin - pad).clamp(0, double.infinity).toDouble();
    final yMax = rawMax + pad;
    final yMid = yMin + (yMax - yMin) / 2;

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].weight),
    ];
    final xMax = (points.length - 1).toDouble();

    // Evenly-spaced x-label indices: ≤8 → first + last; >8 → first + mid + last.
    final labelIndices = points.length <= 8
        ? {0, points.length - 1}
        : {0, points.length ~/ 2, points.length - 1};
    // Per-dot date labels when the series is short (<10 points).
    final showAllDateLabels = points.length < 10;

    final ring = ringAnchorIndex >= 0
        ? _RingSemanticsLabel(value: ringAnchorValue, unit: weightUnit)
        : null;

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: xMax == 0 ? 1 : xMax,
        minY: yMin,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            final isMid = (value - yMid).abs() < 0.0001;
            return FlLine(
              color: onSurface.withValues(alpha: isMid ? 0.08 : 0.05),
              strokeWidth: 1,
            );
          },
          checkToShowHorizontalLine: (value) {
            // Render at yMin, yMid, yMax.
            final tolerance = (yMax - yMin) * 0.001;
            return (value - yMin).abs() < tolerance ||
                (value - yMid).abs() < tolerance ||
                (value - yMax).abs() < tolerance;
          },
          horizontalInterval: (yMax - yMin) / 2,
        ),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: ProgressChartSection._yAxisReservedWidth,
              interval: (yMax - yMin) / 2,
              getTitlesWidget: (value, meta) {
                // Only label the three ticks (min / mid / max).
                final tolerance = (yMax - yMin) * 0.01;
                final isTick =
                    (value - yMin).abs() < tolerance ||
                    (value - yMid).abs() < tolerance ||
                    (value - yMax).abs() < tolerance;
                if (!isTick) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    AppNumberFormat.weightWithUnit(
                      value,
                      locale: locale,
                      unit: weightUnit,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false, reservedSize: 0),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false, reservedSize: 0),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                final shouldShow =
                    showAllDateLabels || labelIndices.contains(i);
                if (!shouldShow) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    AppDateFormat.monthDay(points[i].date, locale: locale),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: primary,
            barWidth: ProgressChartSection._lineWidth,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, index) {
                if (index == ringAnchorIndex) {
                  return _PrRingPainter(
                    primary: primary,
                    ringColor: _prRingAccent,
                    innerRadius: ProgressChartSection._prRingInnerRadius,
                    strokeWidth: ProgressChartSection._prRingStroke,
                    outerGap: ProgressChartSection._prRingOuterGap,
                  );
                }
                return FlDotCirclePainter(
                  radius: ProgressChartSection._dotRadius,
                  color: primary,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );

    if (ring == null) return chart;
    // Wrap in a Semantics node that carries the ring anchor value — the
    // widget tests rely on this to assert whether the ring follows
    // `prValue` or the in-window peak.
    return Stack(children: [chart, ring]);
  }
}

/// Invisible Semantics node that carries the ring anchor value. Rendered as
/// a zero-sized overlay so it doesn't affect layout — its only purpose is
/// to be discoverable by widget tests.
class _RingSemanticsLabel extends StatelessWidget {
  const _RingSemanticsLabel({required this.value, required this.unit});

  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Positioned(
      left: 0,
      top: 0,
      child: Semantics(
        label: AppLocalizations.of(
          context,
        ).prMarkerAt(_formatWeight(value, locale), unit),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

/// Custom dot painter for the PR dot: hollow primary-stroke circle with a
/// gold outer ring. Three layers — gold outer ring, hollow primary inner,
/// 1.5dp solid anchor fill — picked so the ring pops at 10dp total while
/// plain dots stay at 8dp (2dp delta). No fill on the stroked circles so
/// the line underneath is never obscured.
class _PrRingPainter extends FlDotPainter {
  const _PrRingPainter({
    required this.primary,
    required this.ringColor,
    required this.innerRadius,
    required this.strokeWidth,
    required this.outerGap,
  });

  final Color primary;
  final Color ringColor;
  final double innerRadius;
  final double strokeWidth;

  /// Radial gap between the inner hollow circle and the gold outer ring.
  final double outerGap;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    // Gold outer ring — sits outside the inner hollow circle by `outerGap`.
    canvas.drawCircle(
      offsetInCanvas,
      innerRadius + strokeWidth + outerGap,
      Paint()
        ..color = ringColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
    // Inner hollow primary circle.
    canvas.drawCircle(
      offsetInCanvas,
      innerRadius,
      Paint()
        ..color = primary
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
    // Tiny filled dot so the location is visually anchored even at small
    // sizes (keeps the ring from reading as a lonely circle).
    canvas.drawCircle(
      offsetInCanvas,
      1.5,
      Paint()
        ..color = primary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  Size getSize(FlSpot spot) =>
      Size.fromRadius(innerRadius + strokeWidth + outerGap);

  @override
  Color get mainColor => primary;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [
    primary,
    ringColor,
    innerRadius,
    strokeWidth,
    outerGap,
  ];
}

// -----------------------------------------------------------------------------
// Pure helpers — kept at file scope so widget tests exercise them too.
// -----------------------------------------------------------------------------

/// Apply window-dependent aggregation to the pre-ranked series.
///
/// The caller has already picked the correct source list (raw-weight vs
/// e1RM-ranked — see [ExerciseProgressData]), so this helper is now just
/// the weekly-max collapse: allTime window with > 30 points → weekly-max
/// (ISO-week start anchor) to keep the chart legible. Smaller series pass
/// through unchanged.
List<ProgressPoint> _buildSeries(
  List<ProgressPoint> source, {
  required TimeWindow window,
}) {
  if (window == TimeWindow.allTime && source.length > 30) {
    return _weeklyMax(source);
  }
  return source;
}

/// Group [points] by ISO week (Mon-anchored) and keep the max-weight point
/// per week. Result is sorted ascending by week-anchor date.
List<ProgressPoint> _weeklyMax(List<ProgressPoint> points) {
  final byWeek = <DateTime, ProgressPoint>{};
  for (final p in points) {
    // ISO week anchor: subtract (weekday - 1) days from the date.
    final anchor = DateTime(
      p.date.year,
      p.date.month,
      p.date.day,
    ).subtract(Duration(days: p.date.weekday - 1));
    final existing = byWeek[anchor];
    if (existing == null || p.weight > existing.weight) {
      byWeek[anchor] = ProgressPoint(
        date: anchor,
        weight: p.weight,
        sessionReps: p.sessionReps,
      );
    }
  }
  return byWeek.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

/// Resolve the PR ring anchor. In Weight mode, if [prValue] matches a dot's
/// weight, anchor there (all-time PR wins). Otherwise, anchor at the peak
/// of the visible series.
({int index, double value}) _resolveRingAnchor(
  List<ProgressPoint> series,
  ChartMetric metric,
  double? prValue,
) {
  if (series.isEmpty) return (index: -1, value: 0);

  if (metric == ChartMetric.weight && prValue != null) {
    for (var i = 0; i < series.length; i++) {
      if ((series[i].weight - prValue).abs() < 0.0001) {
        return (index: i, value: series[i].weight);
      }
    }
  }

  // Fall back to the in-series peak.
  var peakIndex = 0;
  for (var i = 1; i < series.length; i++) {
    if (series[i].weight > series[peakIndex].weight) peakIndex = i;
  }
  return (index: peakIndex, value: series[peakIndex].weight);
}

/// Build the trend copy and its color per acceptance #6. Returns `(text,
/// color)` so the caller can apply the right style in one place.
(String, Color) _buildTrendCopy({
  required List<ProgressPoint> series,
  required int workoutCount,
  required String weightUnit,
  required String windowLabel,
  required ThemeData theme,
  required AppLocalizations l10n,
  required String locale,
}) {
  final neutral = theme.colorScheme.onSurface.withValues(alpha: 0.70);

  if (workoutCount == 0) {
    return (l10n.logFirstSetToTrack, neutral);
  }
  if (workoutCount == 1) {
    return (l10n.oneWorkoutLoggedKeepGoing, neutral);
  }
  if (series.length < 2) {
    // N workouts (N≥2) but all aggregate to one point → no trend direction.
    return (l10n.workoutsLoggedKeepGoing(workoutCount), neutral);
  }

  final delta = series.last.weight - series.first.weight;
  if (delta == 0) {
    return (
      l10n.holdingSteadyAt(
        _formatWeight(series.last.weight, locale),
        weightUnit,
      ),
      neutral,
    );
  }
  if (delta > 0) {
    return (
      l10n.trendUp(_formatWeight(delta, locale), weightUnit, windowLabel),
      theme.colorScheme.primary,
    );
  }
  // delta < 0 — neutral color per acceptance #6 (no red for deloads).
  return (
    l10n.trendDown(_formatWeight(delta.abs(), locale), weightUnit, windowLabel),
    neutral,
  );
}

/// Format a weight number with up to one decimal place, using the given
/// [locale]'s decimal separator (dot in en, comma in pt).
String _formatWeight(double value, String locale) {
  return AppNumberFormat.weight(value, locale: locale);
}
