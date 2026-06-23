import '../../rpg/models/body_part.dart';

/// Per-body-part conditioning charge for the post-session "Conditioning
/// charged" debrief beat (Phase Vitality-2).
///
/// **What it is.** Vitality is a per-body-part EWMA of recent training
/// volume — a "charge" / rune that REBUILDS at save time and decays only
/// over days (never depletes in-session). The charge FRACTION of a body
/// part is `clamp(ewma / refPeak, 0, 1)`, where `refPeak` is the *decaying
/// reference peak* (`vitality_ref_peak`, a 21-day half-life rolling max) —
/// NOT the monotonic all-time `vitality_peak`. The rolling denominator is
/// what makes a detrained user's comeback session read big instead of
/// rounding to 0% against a frozen all-time max.
///
/// **Why per-bp, not aggregate.** The old aggregate mean collapsed all
/// trained parts into a single `+N%`, which (1) diluted real gains with
/// already-maxed parts contributing `+0` and (2) hid the whole beat below a
/// sub-1% aggregate delta. This model carries an ORDERED list of
/// [BodyPartCharge] — one row per trained part with charge data — so the
/// rune-strip widget can show each part's own gain in its own hue.
///
/// **Decoupling Rule 1 (pure data).** No widgets, no `BuildContext`, no
/// provider reads — the controller computes the per-bp charges from the
/// pre/post snapshots and hands this object to the widget layer.
class ConditioningCharge {
  const ConditioningCharge({
    required this.parts,
    required this.alreadyChargedToday,
  });

  /// Per-body-part charge rows, ordered for display: gainers first by
  /// delta descending, then held/MÁX rows (no positive gain). Only parts
  /// that HAVE charge data (`refPeak > 0`) appear here.
  final List<BodyPartCharge> parts;

  /// True when EVERY trained body part with charge data shows an exactly
  /// flat EWMA (`before.ewma == after.ewma`) — the server's once-per-day
  /// vitality guard blocked the step (2nd+ same-day save, or a save after
  /// the nightly cron already advanced today's charge). The widget renders
  /// the "já carregado hoje" guard state instead of per-bp rows. Honest:
  /// the charge WAS already banked today, never a loss.
  final bool alreadyChargedToday;

  /// A body part whose charge rounds to 100% after the session
  /// (`afterPct >= 0.995`). Held at peak — the widget shows "MÁX", never a
  /// dead `+0`.
  bool get hasMaxedParts => parts.any((p) => p.isMax);

  /// True when there are charge rows but NONE of them gained (all held at
  /// their prior level / at peak). Drives the "all at peak" copy line —
  /// distinct from [alreadyChargedToday] (which is the server-guard state).
  bool get allHeld =>
      parts.isNotEmpty && parts.every((p) => p.deltaPercentInt == 0);

  /// Whether the beat should render. Renders whenever ANY trained bp has
  /// charge data (so an all-maxed session still shows "everything stayed
  /// charged"), OR when the once-per-day guard blocked the step (so the
  /// beat surfaces the honest "already charged today" state instead of
  /// silently vanishing). Hides only on true day-zero / no-charge-data.
  bool get shouldRender => parts.isNotEmpty || alreadyChargedToday;

  /// Compute the per-bp charges from raw pre/post vitality snapshots,
  /// restricted to [trainedBodyParts].
  ///
  /// [before] / [after] map each body part to its `(ewma, peak, refPeak)`
  /// record. A bp absent from a map, or present with `refPeak <= 0` on the
  /// AFTER side, has no defined charge fraction and is EXCLUDED from
  /// [parts] (no charge data to show).
  ///
  /// [alreadyChargedToday] is true when there is at least one trained bp
  /// with charge data AND every such bp's EWMA is exactly unchanged
  /// (`before.ewma == after.ewma`) — the server guard signal.
  static ConditioningCharge fromSnapshots({
    required Iterable<BodyPart> trainedBodyParts,
    required Map<BodyPart, ({double ewma, double peak, double refPeak})> before,
    required Map<BodyPart, ({double ewma, double peak, double refPeak})> after,
  }) {
    final trained = trainedBodyParts.toSet();
    final charges = <BodyPartCharge>[];
    var anyData = false;
    var allFlat = true;

    for (final bp in trained) {
      final a = after[bp];
      // No AFTER row, or no reference peak → undefined fraction, excluded.
      if (a == null || a.refPeak <= 0) continue;
      anyData = true;

      final b = before[bp];
      final beforePct = (b == null || b.refPeak <= 0)
          ? 0.0
          : (b.ewma / b.refPeak).clamp(0.0, 1.0);
      final afterPct = (a.ewma / a.refPeak).clamp(0.0, 1.0);

      // The guard signal is per-bp exact EWMA equality. A single bp that
      // actually stepped means the session was NOT guard-blocked.
      final bewma = b?.ewma;
      if (bewma == null || bewma != a.ewma) allFlat = false;

      charges.add(
        BodyPartCharge(bodyPart: bp, beforePct: beforePct, afterPct: afterPct),
      );
    }

    // Ordering: gainers first (delta desc), then held/MÁX rows. Stable on
    // the body-part enum order as the tiebreak so the strip is deterministic.
    charges.sort((x, y) {
      final byDelta = y.deltaPercentInt.compareTo(x.deltaPercentInt);
      if (byDelta != 0) return byDelta;
      return x.bodyPart.index.compareTo(y.bodyPart.index);
    });

    return ConditioningCharge(
      parts: charges,
      alreadyChargedToday: anyData && allFlat,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditioningCharge &&
          other.alreadyChargedToday == alreadyChargedToday &&
          _listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(alreadyChargedToday, Object.hashAll(parts));

  static bool _listEquals(List<BodyPartCharge> a, List<BodyPartCharge> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One body part's before/after conditioning charge. Pure data —
/// rendered by the rune-strip widget as a hue-segmented rune + label +
/// state-aware delta (`▲ +N%` for a gainer, MÁX for a held-at-peak part).
class BodyPartCharge {
  const BodyPartCharge({
    required this.bodyPart,
    required this.beforePct,
    required this.afterPct,
  });

  final BodyPart bodyPart;

  /// Charge fraction BEFORE the session (`clamp(ewma/refPeak, 0, 1)`),
  /// `[0, 1]`. The rune's prior fill level.
  final double beforePct;

  /// Charge fraction AFTER the session, `[0, 1]`. The rune fills to this
  /// level in the part's hue.
  final double afterPct;

  /// Held at peak — the after charge rounds to 100% (`>= 0.995`). The widget
  /// shows "MÁX" + a full rune instead of a delta, never a dead `+0`.
  bool get isMax => afterPct >= 0.995;

  /// Held below peak — the part was trained (it HAS charge data) but its
  /// EWMA stayed flat or stepped DOWN within the session (`deltaPercentInt`
  /// floored to 0) WHILE sitting below peak (`!isMax`). Happens when a part
  /// is trained with below-its-average weekly volume so the rolling EWMA
  /// dips. The widget shows the past-tense "Held" / "Mantido" word with the
  /// rune at the part's CURRENT level — NEVER the forbidden dead `▲ +0%`.
  ///
  /// **Three-way classification.** Every charged row is exactly one of:
  /// a gainer (`deltaPercentInt > 0`), [isMax] (at peak), or [isHeld]
  /// (trained, flat/below-peak). These are mutually exclusive and exhaustive
  /// over the rows in [ConditioningCharge.parts].
  bool get isHeld => !isMax && deltaPercentInt == 0;

  /// Honest forward delta in percentage points, clamped at 0 (vitality only
  /// rebuilds at save time — a numerically-flat or decayed snapshot reads as
  /// a no-op, never a drop).
  ///
  /// **+1% floor for a real gain.** When there is a genuine positive EWMA
  /// step that would otherwise round DOWN to `+0%`, the delta is floored to
  /// 1 so a part that actually charged never displays "+0". A truly flat
  /// part (no gain) stays at 0 (and renders as MÁX or a held row, never
  /// "+0%").
  int get deltaPercentInt {
    final raw = afterPct - beforePct;
    if (raw <= 0) return 0;
    final rounded = (raw * 100).round();
    return rounded == 0 ? 1 : rounded;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyPartCharge &&
          other.bodyPart == bodyPart &&
          other.beforePct == beforePct &&
          other.afterPct == afterPct;

  @override
  int get hashCode => Object.hash(bodyPart, beforePct, afterPct);
}
