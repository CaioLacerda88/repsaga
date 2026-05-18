import '../../rpg/models/body_part.dart';

/// Returns the set of body parts that this set should "count" toward in the
/// Engajamento section.
///
/// **Set-counting rule (locked, spec line 483):** the primary body part of
/// a set is the body part with the **maximum** `xp_attribution` share. If
/// two or more body parts tie at the max (strict equality, no tolerance),
/// each tied body part is credited with the set.
///
/// `attribution` keys are `BodyPart.dbValue` strings (matches
/// `exercises.xp_attribution` JSONB on the DB side). Cardio keys are
/// dropped — the 6-bar Engajamento view excludes cardio (v1).
///
/// Returns an empty set if the attribution is empty, all shares are
/// non-positive, or every winning body part is cardio.
Set<BodyPart> primaryBodyPartsForSet(Map<String, num> attribution) {
  if (attribution.isEmpty) return const {};

  double maxShare = -1;
  final winners = <BodyPart>{};
  attribution.forEach((key, value) {
    final share = value.toDouble();
    if (share <= 0) return;
    final bp = BodyPart.tryFromDbValue(key);
    if (bp == null) return;
    if (bp == BodyPart.cardio) return; // v1: cardio excluded from rendering
    if (share > maxShare) {
      maxShare = share;
      winners
        ..clear()
        ..add(bp);
    } else if (share == maxShare) {
      // Strict equality: 0.50 == 0.50 ties; 0.501 != 0.499 does not.
      winners.add(bp);
    }
  });
  return winners;
}

/// Aggregated weekly counts of "primary-attribution sets" per body part.
///
/// `done` = sets the user actually completed this week.
/// `planned` = sets currently in the bucket's routines, summed across all
/// uncompleted bucket entries (the work the user has committed to).
///
/// The widget renders `plannedFor` as the bar denominator and `doneFor` as
/// the filled portion. `plannedFor` is guaranteed to be >= `doneFor` (see
/// the [from] factory): a user who over-performs vs their plan still has
/// the bar read full, not less than the work they actually did.
class WeeklyEngagement {
  const WeeklyEngagement._(this._done, this._plannedTotals);

  /// Build from raw per-body-part done + planned counts. `plannedTotals`
  /// in the returned object is `max(donePerBp, plannedPerBp)` so the bar
  /// invariant `doneFor <= plannedFor` always holds.
  factory WeeklyEngagement.from({
    required Map<BodyPart, int> done,
    required Map<BodyPart, int> planned,
  }) {
    final totals = <BodyPart, int>{};
    for (final bp in BodyPart.values) {
      if (bp == BodyPart.cardio) continue; // v1: cardio excluded
      final d = done[bp] ?? 0;
      final p = planned[bp] ?? 0;
      totals[bp] = d > p ? d : p;
    }
    return WeeklyEngagement._(Map.of(done), totals);
  }

  /// Empty engagement (no data) — used by providers as a loading/initial value.
  static const WeeklyEngagement empty = WeeklyEngagement._({}, {});

  final Map<BodyPart, int> _done;
  final Map<BodyPart, int> _plannedTotals;

  int doneFor(BodyPart bp) => _done[bp] ?? 0;
  int plannedFor(BodyPart bp) => _plannedTotals[bp] ?? 0;
}
