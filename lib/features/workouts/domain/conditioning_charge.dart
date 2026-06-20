import '../../rpg/models/body_part.dart';

/// Aggregate before/after conditioning charge for the post-session
/// "Conditioning charged" debrief beat (Phase Vitality PR 2).
///
/// **What it is.** Vitality is a per-body-part EWMA of recent training
/// volume — a "charge" / rune that REBUILDS toward a 7-day peak at save time
/// (PR 1 made the recompute happen in `save_workout`), and decays only over
/// days (never depletes in-session). Per-bp charge fraction is
/// `clamp(ewma / peak, 0, 1)`; a bp the user has never charged
/// (`peak == 0`) has an undefined fraction and is excluded from the roll-up.
///
/// The beat reports a single aggregate (Variant A, user-locked design):
/// the MEAN of the per-bp charge fractions across the body parts TRAINED
/// this session (the bps that earned XP). It carries the BEFORE snapshot
/// (pre-finish) and the AFTER snapshot (post-`refreshAfterSave`) so the
/// widget can render a two-tone "was → now" charge bar counting up
/// rightward.
///
/// **Decoupling Rule 1 (pure data).** No widgets, no `BuildContext`,
/// no provider reads — the controller computes the two fractions from the
/// pre/post snapshots and hands this object to the widget layer.
class ConditioningCharge {
  const ConditioningCharge({required this.beforePct, required this.afterPct});

  /// Aggregate charge fraction BEFORE the session (mean of per-bp
  /// `clamp(ewma/peak, 0, 1)` over the trained bps), in `[0, 1]`.
  final double beforePct;

  /// Aggregate charge fraction AFTER the session (same roll-up against the
  /// post-save snapshot), in `[0, 1]`.
  final double afterPct;

  /// Honest delta in percentage points, clamped at 0 — vitality only
  /// rebuilds at save time, so a same-day re-save (guarded server-side)
  /// or a numerically-flat recompute reads as a no-op, never a drop.
  double get deltaPct => (afterPct - beforePct).clamp(0.0, 1.0);

  /// Integer delta for the "+N%" label.
  int get deltaPercentInt => (deltaPct * 100).round();

  /// Whether the beat should render. Hides gracefully when there is no
  /// honest forward movement to show (no trained bp with charge data, or a
  /// delta that rounds to 0% — day-zero, a fully-charged plateau, or a
  /// same-day re-save).
  bool get shouldRender => deltaPercentInt > 0;

  /// Compute the aggregate before/after charge from raw pre/post vitality
  /// snapshots, restricted to [trainedBodyParts].
  ///
  /// [before] / [after] map each body part to its `(ewma, peak)` pair. A bp
  /// absent from a map, or present with `peak <= 0`, contributes no charge
  /// fraction on that side (undefined ratio). The aggregate on each side is
  /// the mean over the trained bps that HAVE a defined fraction on that
  /// side; when a side has no defined fraction at all, it reads 0.0 (the
  /// `shouldRender` gate then hides the beat unless the other side lifts it
  /// above 0%).
  ///
  /// Returns a charge whose [shouldRender] is false when [trainedBodyParts]
  /// is empty.
  static ConditioningCharge fromSnapshots({
    required Iterable<BodyPart> trainedBodyParts,
    required Map<BodyPart, ({double ewma, double peak})> before,
    required Map<BodyPart, ({double ewma, double peak})> after,
  }) {
    final trained = trainedBodyParts.toSet();
    return ConditioningCharge(
      beforePct: _meanCharge(trained, before),
      afterPct: _meanCharge(trained, after),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditioningCharge &&
          other.beforePct == beforePct &&
          other.afterPct == afterPct;

  @override
  int get hashCode => Object.hash(beforePct, afterPct);

  static double _meanCharge(
    Set<BodyPart> trained,
    Map<BodyPart, ({double ewma, double peak})> snapshot,
  ) {
    var sum = 0.0;
    var n = 0;
    for (final bp in trained) {
      final row = snapshot[bp];
      if (row == null || row.peak <= 0) continue;
      sum += (row.ewma / row.peak).clamp(0.0, 1.0);
      n += 1;
    }
    if (n == 0) return 0.0;
    return sum / n;
  }
}
