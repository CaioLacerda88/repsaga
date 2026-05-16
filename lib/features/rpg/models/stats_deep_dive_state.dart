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

    /// Set count for the body part during the 7 days BEFORE the current
    /// week. Used by `VolumePeakBlock` to render the "vs semana passada"
    /// delta when the user has 2–4 weeks of history. Null when the user
    /// has < 2 weeks of history (the delta string is suppressed).
    int? previousWeekVolumeSets,

    /// Rolling 4-week mean of weekly set counts (excluding the current
    /// in-progress week). Used by `VolumePeakBlock` to render the "vs média
    /// (4 sem)" delta when the user has 5+ weeks of history. Null when the
    /// user has < 5 weeks of history.
    double? fourWeekMeanVolumeSets,

    /// Persisted EWMA value as of 30 days ago. Used by `VolumePeakBlock`
    /// to render the monthly peak delta with the `30D` badge. Null when
    /// the user has < 30 days of history.
    double? peakEwma30dAgo,

    /// Distinct ISO-week count covered by the user's xp_events for this
    /// body part. Drives the volume-delta string choice:
    ///   * 0–1 weeks → no delta line (suppressed)
    ///   * 2–4 weeks → "X vs semana passada" (uses [previousWeekVolumeSets])
    ///   * 5+ weeks  → "X vs média (4 sem)"  (uses [fourWeekMeanVolumeSets])
    @Default(0) int weeksOfHistory,
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

/// Encodes the renderable state of a body-part's weekly-volume delta line
/// for `VolumePeakBlock` (Phase 26c). The widget switches on [state] and
/// renders the matching string + color; this type centralizes the rule so
/// the widget stays pure presentation.
///
/// Phase 26c locked decisions:
///   * `0–1 weeks` of history → suppressed (no delta line rendered).
///   * `2–4 weeks` → compare against `previousWeekVolumeSets`.
///   * `5+ weeks` → compare against `fourWeekMeanVolumeSets`.
///   * Under-target → red (`vitalityLow`).
///   * Over-target → amber (`warning`) — explicitly NOT green; amber says
///     "noted, you decide" without prescribing more volume.
///   * Exactly met → green (`vitalityHigh`) with a filled `●` bullet.
enum VolumeDeltaState { suppressed, underTarget, met, overTarget }

/// Which historical basis the volume delta was computed against. Drives
/// the localized "vs semana passada" / "vs média (4 sem)" string in the
/// widget.
enum VolumeDeltaBasis { previousWeek, fourWeekMean }

@freezed
abstract class VolumeDeltaView with _$VolumeDeltaView {
  const factory VolumeDeltaView({
    required VolumeDeltaState state,

    /// Signed delta: `weeklyVolumeSets - basisValue`. Negative for
    /// under-target, positive for over-target, 0 for met. Always 0 for
    /// [VolumeDeltaState.suppressed].
    @Default(0) double delta,

    /// Which basis was used. Null for [VolumeDeltaState.suppressed].
    VolumeDeltaBasis? basis,
  }) = _VolumeDeltaView;

  const VolumeDeltaView._();

  /// Compute the view-state for [row]. Pure function — no l10n / no
  /// widget tree access. Localized strings are picked at the widget
  /// layer using [basis] as the discriminator.
  factory VolumeDeltaView.fromRow(VolumePeakRow row) {
    if (row.weeksOfHistory < 2) {
      return const VolumeDeltaView(state: VolumeDeltaState.suppressed);
    }
    final useFourWeekMean = row.weeksOfHistory >= 5;
    final basis = useFourWeekMean
        ? VolumeDeltaBasis.fourWeekMean
        : VolumeDeltaBasis.previousWeek;
    final basisValue = useFourWeekMean
        ? (row.fourWeekMeanVolumeSets ?? 0)
        : (row.previousWeekVolumeSets ?? 0).toDouble();
    final delta = row.weeklyVolumeSets - basisValue;
    final state = delta == 0
        ? VolumeDeltaState.met
        : delta < 0
        ? VolumeDeltaState.underTarget
        : VolumeDeltaState.overTarget;
    return VolumeDeltaView(state: state, delta: delta, basis: basis);
  }
}

/// Encodes the renderable state of a body-part's monthly peak-EWMA delta
/// line for `VolumePeakBlock` (Phase 26c). Always-monthly with the `30D`
/// badge in the rendered widget.
enum PeakDeltaState { suppressed, up, flat }

@freezed
abstract class PeakDeltaView with _$PeakDeltaView {
  const factory PeakDeltaView({
    required PeakDeltaState state,
    @Default(0) double delta,
  }) = _PeakDeltaView;

  const PeakDeltaView._();

  /// Compute the view-state for [row]. Pure function.
  ///
  /// Peak EWMA is documented monotonic-non-decreasing in the model — it's
  /// a lifetime peak watermark. A negative delta indicates data drift
  /// (clock skew, manual fixup); render as flat (no arrow) rather than
  /// down. Zero delta also flattens — no monthly movement to surface.
  factory PeakDeltaView.fromRow(VolumePeakRow row) {
    final prior = row.peakEwma30dAgo;
    if (prior == null) {
      return const PeakDeltaView(state: PeakDeltaState.suppressed);
    }
    final delta = row.peakEwma - prior;
    if (delta <= 0) {
      return const PeakDeltaView(state: PeakDeltaState.flat);
    }
    return PeakDeltaView(state: PeakDeltaState.up, delta: delta);
  }
}
