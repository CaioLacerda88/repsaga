// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_cardio_summary.freezed.dart';

/// One cardio row of the S2 Mission Debrief ledger (Phase 38e).
///
/// Sibling of [SessionLiftSummary] — pure, pre-resolved data for a single
/// completed cardio entry. The debrief section renders these alongside the
/// strength lift rows so a mixed session reads as one coherent ledger.
///
/// **Decoupling Rule 1 (pure data).** No widgets, no `BuildContext`, no
/// Riverpod. Composed once by `PostSessionController._buildInitial()` from
/// the pre-finish exercise snapshot's completed [CardioSession]s.
///
/// Field rationale:
///   * [exerciseId] — stable join key (forever-stable, localization-free —
///     same rule as [SessionLiftSummary.exerciseId]).
///   * [activityName] — pre-resolved localized exercise name ("Treadmill" /
///     "Esteira"), rendered verbatim (`feedback_widget_l10n_parameterization`).
///   * [durationSeconds] — the hero numeral. Formatted via `CardioFormat`
///     at the widget layer (the widget owns the `m:ss` rendering).
///   * [distanceM] — optional distance in canonical METERS. Null when not
///     logged (e.g. jump rope); the widget omits the distance suffix.
///   * [paceSecondsPerKm] — optional pace, seconds per km, derived at
///     projection time only when both duration and distance are present.
///     Null otherwise; the widget omits the pace suffix. Kept canonical
///     (per-km) so the widget converts to the display unit at paint time.
///
/// No PR field — cardio never earns a PR flag / heroGold (that scarcity
/// token stays reserved for strength PRs).
@freezed
abstract class SessionCardioSummary with _$SessionCardioSummary {
  const factory SessionCardioSummary({
    required String exerciseId,
    required String activityName,
    required int durationSeconds,
    double? distanceM,
    double? paceSecondsPerKm,
  }) = _SessionCardioSummary;
}
