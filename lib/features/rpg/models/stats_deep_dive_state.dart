// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import 'body_part.dart';
import 'vitality_state.dart';

part 'stats_deep_dive_state.freezed.dart';

/// State shape consumed by the `/saga/stats` deep-dive screen (Phase 18d.2).
///
/// Composed by [statsProvider] from `body_part_progress` (current EWMA +
/// peak), `xp_events` (90-day reconstruction window), `exercise_peak_loads`
/// (peak loads list), and the user-exercise lookup needed to resolve names
/// + muscle groups for the per-body-part peak-loads grouping.
///
/// **Why a top-level state class instead of separate providers per section:**
/// the screen's six sections share the same temporal window — earliest
/// activity gates the chart's X-axis _and_ informs the empty-state for the
/// volume/peak table _and_ informs the peak-loads grouping. Composing once
/// at provider time avoids three round-trips of cross-section coordination
/// in the UI.
@freezed
abstract class StatsDeepDiveState with _$StatsDeepDiveState {
  const factory StatsDeepDiveState({
    /// One row per active body part, in [activeBodyParts] canonical order.
    /// Drives both the live Vitality table and the chart's selection set.
    required List<VitalityTableRow> vitalityRows,

    /// Reconstructed daily trace per body part, oldest → newest. Empty list
    /// for body parts the user has never trained (rendered as a flat-zero
    /// line by the chart). All non-empty lists share the same length and the
    /// same date sequence as [windowStart] → [windowEnd].
    required Map<BodyPart, List<TrendPoint>> trendByBodyPart,

    /// Per-body-part volume-and-peak row for the secondary table.
    required Map<BodyPart, VolumePeakRow> volumePeakByBodyPart,

    /// Per-body-part peak-loads list (grouped + sorted), sourced from
    /// `exercise_peak_loads` joined with `exercises.muscle_group`. Body parts
    /// with no recorded peaks are absent from the map. The ExpansionTile
    /// section shows the empty state when the map is empty.
    required Map<BodyPart, List<PeakLoadRow>> peakLoadsByBodyPart,

    /// Timestamp of the user's earliest `xp_event`. `null` for users who
    /// have never recorded a set. Drives the hybrid X-axis decision.
    required DateTime? earliestActivity,

    /// Inclusive start of the trend chart window (UTC midnight).
    required DateTime windowStart,

    /// Inclusive end of the trend chart window — always "today" UTC midnight.
    required DateTime windowEnd,
  }) = _StatsDeepDiveState;

  const StatsDeepDiveState._();

  /// Day-0 / loading-failed fallback. Six untested rows, empty trend lines,
  /// empty peaks. Identity invariant: rendering this state must produce a
  /// laid-out screen with no overflow / no null-deref.
  ///
  /// 2026-05-04 untested patch: rows ship with [VitalityState.untested]
  /// (peak == 0; ratio undefined) so the table renders `—` for the
  /// percentage and "Uncharted — log a set to begin." for the marginalia
  /// copy — distinct from a `0%` "fully decayed" read.
  factory StatsDeepDiveState.empty() {
    final now = DateTime.now();
    return StatsDeepDiveState(
      vitalityRows: [
        for (var i = 0; i < activeBodyParts.length; i++)
          VitalityTableRow(
            bodyPart: activeBodyParts[i],
            pct: 0,
            state: VitalityState.untested,
            rank: 1,
          ),
      ],
      trendByBodyPart: {
        for (final bp in activeBodyParts) bp: const <TrendPoint>[],
      },
      volumePeakByBodyPart: {
        for (final bp in activeBodyParts)
          bp: const VolumePeakRow(weeklyVolumeSets: 0, peakEwma: 0),
      },
      peakLoadsByBodyPart: const {},
      earliestActivity: null,
      windowStart: now.subtract(const Duration(days: 90)),
      windowEnd: now,
    );
  }

  /// True when [windowStart] is the user's earliest activity (history <30
  /// days). Drives the heading copy + X-axis label for the chart.
  ///
  /// Threshold rule: history `< 30` days → narrow window; history `>= 30`
  /// days → 90-day window. Chosen so the boundary day-30 user gets the
  /// "stable" 90-day surface (their first month of trace is still visible
  /// on the left of the chart but is no longer the entire surface).
  bool get useNarrowWindow {
    if (earliestActivity == null) return false;
    final daysSinceFirst = windowEnd.difference(earliestActivity!).inDays;
    return daysSinceFirst < 30;
  }

  /// Total days spanned by the trend chart. 90 in standard mode; smaller
  /// in narrow mode.
  int get windowSpanDays => windowEnd.difference(windowStart).inDays;
}

/// One row in the live Vitality table (six rows total).
@freezed
abstract class VitalityTableRow with _$VitalityTableRow {
  const factory VitalityTableRow({
    required BodyPart bodyPart,

    /// 0..1 ratio. Renders as `(pct * 100).round()%`.
    required double pct,
    required VitalityState state,
    required int rank,
  }) = _VitalityTableRow;
}

/// One sample on the trend chart — daily granularity.
@freezed
abstract class TrendPoint with _$TrendPoint {
  const factory TrendPoint({
    required DateTime date,

    /// 0..1 ratio relative to the body part's lifetime peak EWMA.
    required double pct,
  }) = _TrendPoint;
}

/// One row in the per-body-part Volume & Peak table.
@freezed
abstract class VolumePeakRow with _$VolumePeakRow {
  const factory VolumePeakRow({
    /// Set count attributed to this body part over the last 7 days.
    required int weeklyVolumeSets,

    /// Lifetime peak EWMA — never decreases. Rendered with tabular figures.
    required double peakEwma,
  }) = _VolumePeakRow;
}

/// One row in the per-exercise Peak Loads section.
@freezed
abstract class PeakLoadRow with _$PeakLoadRow {
  const factory PeakLoadRow({
    /// Localized display name fetched via `fn_exercises_localized`.
    required String exerciseName,
    required double peakWeight,
    required int peakReps,

    /// Epley-style 1RM estimate. Null when peakReps == 0 (bodyweight /
    /// non-loaded peaks) so the UI can suppress the "1RM est." label.
    required double? estimated1RM,
  }) = _PeakLoadRow;
}

/// Convenience: derive [BodyPart] count of active rows for tests/UI gates.
extension StatsActiveBodyPartCount on StatsDeepDiveState {
  /// Number of body parts with at least one recorded peak.
  int get activeBodyPartCount =>
      vitalityRows.where((r) => r.pct > 0 || r.rank > 1).length;
}
