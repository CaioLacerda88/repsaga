import 'dart:math' as math;

/// Rank curve — Phase 29 v2 Refinement #6 piecewise.
///
/// ```
/// ranks 1-20  (geometric):  cumulative(n) = 60 × (1.10^(n-1) - 1) / 0.10
/// ranks 21-99 (linear):     cumulative(n) = cumulative(20) + (n - 20) × 367.0
/// ```
///
/// The breakpoint at rank 20 is the dividing line between the "newcomer
/// onboarding curve" (geometric, compounding) and the "long-tail steady
/// state" (linear, predictable). 367.0 XP per rank above 20 is a LITERAL
/// constant — derived `60 × 1.10^19 ≈ 366.957` would compound float
/// rounding at high ranks, so the persisted value is locked. Pinned by
/// the parity test: `cumulativeXpForRank(21) - cumulativeXpForRank(20)
/// == 367.0` exactly.
///
/// The cumulative curve is precomputed for ranks 1..99 — the lookup
/// table is loaded once at startup and never recomputed. The function
/// form is kept for tests + sanity checks.
class RankCurve {
  const RankCurve._();

  /// Visible rank cap. The underlying XP formula keeps growing past this
  /// via the linear band; the UI clamps at 99.
  static const int maxRank = 99;

  /// Base — XP needed for rank 2 (the first rank-up).
  static const double xpBase = 60.0;

  /// Geometric growth factor for the band 1-20 (Refinement #6).
  /// Legacy alias `xpGrowth` is kept for the existing constants-parity
  /// test that asserts against `fixtures.meta.xp_growth`.
  static const double xpGrowth = 1.10;

  /// Explicit Phase 29 v2 name for the geometric growth factor (band 1).
  /// Same value as [xpGrowth] — both exposed to make the call-site
  /// intent self-documenting.
  static const double xpGrowthBand1 = 1.10;

  /// Phase 29 v2 — piecewise breakpoint. Ranks 1..20 use the geometric
  /// curve; ranks 21..99 use the linear band.
  static const int xpGrowthBreakpoint = 20;

  /// Phase 29 v2 — flat XP cost per rank in the linear band (above
  /// [xpGrowthBreakpoint]).
  ///
  /// LITERAL 367.0 — intentionally NOT derived from
  /// `60 × 1.10^19 ≈ 366.957`. The derived float would compound rounding
  /// at high ranks across the 4 parity sites (Python sim / fixture /
  /// Dart / SQL), so the persisted constant is the rounded integer
  /// `367.0` shared by every implementation.
  static const double linearXpPerRank = 367.0;

  /// XP delta `xp_to_next(n)` — XP to advance from rank `n` to rank `n + 1`.
  ///
  /// Phase 29 v2 piecewise: within the geometric band, grows by 1.10×
  /// each rank. At the breakpoint and above, it's the flat
  /// [linearXpPerRank].
  static double xpToNext(int rank) {
    assert(rank >= 1, 'rank must be >= 1');
    if (rank >= xpGrowthBreakpoint) return linearXpPerRank;
    return xpBase * math.pow(xpGrowthBand1, rank - 1).toDouble();
  }

  /// Cumulative XP at the start of rank `n` (Phase 29 v2 piecewise).
  ///
  /// `cumulativeXpForRank(1) == 0` — every user starts at rank 1 with 0
  /// XP. The breakpoint values:
  ///   `cumulativeXpForRank(20) ≈ 3069.55`
  ///   `cumulativeXpForRank(21) = cumulativeXpForRank(20) + 367.0`
  static double cumulativeXpForRank(int rank) {
    assert(rank >= 1, 'rank must be >= 1');
    if (rank == 1) return 0.0;
    if (rank <= xpGrowthBreakpoint) {
      // Geometric sum: 60 × (1.10^(n-1) - 1) / 0.10
      final geom = math.pow(xpGrowthBand1, rank - 1).toDouble();
      return xpBase * (geom - 1) / (xpGrowthBand1 - 1);
    }
    // Linear band: pivot at the breakpoint's geometric cumulative + flat
    // per-rank cost.
    final atBreakpoint = _cumulativeAtBreakpoint;
    return atBreakpoint + (rank - xpGrowthBreakpoint) * linearXpPerRank;
  }

  /// Highest rank whose cumulative XP threshold `totalXp` has reached.
  /// Caps at [maxRank]. Negative or zero XP returns 1.
  static int rankForXp(num totalXp) {
    if (totalXp <= 0) return 1;
    if (totalXp >= _cumulativeTable[maxRank - 1]) return maxRank;
    var lo = 0;
    var hi = _cumulativeTable.length - 1;
    var answer = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulativeTable[mid] <= totalXp) {
        answer = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return answer + 1;
  }

  /// XP earned within the user's current rank.
  static double xpInRank(num totalXp, int rank) {
    final base = cumulativeXpForRank(rank);
    final delta = totalXp - base;
    return delta < 0 ? 0 : delta.toDouble();
  }

  /// XP remaining to reach the next rank. At [maxRank] returns 0.
  static double xpToNextRank(num totalXp, int rank) {
    if (rank >= maxRank) return 0;
    final inRank = xpInRank(totalXp, rank);
    final to = xpToNext(rank);
    final remaining = to - inRank;
    return remaining < 0 ? 0 : remaining;
  }

  /// Progress fraction within the current rank — clamped to [0, 1].
  /// At maxRank returns 1.0.
  static double progressFraction(num totalXp, int rank) {
    if (rank >= maxRank) return 1.0;
    final inRank = xpInRank(totalXp, rank);
    final to = xpToNext(rank);
    if (to <= 0) return 0;
    final p = inRank / to;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }

  // ---- precomputed cumulative table ----------------------------------------

  /// Precomputed `cumulativeXpForRank(20)` — used by the linear-band
  /// branch of [cumulativeXpForRank] to avoid recomputing the geometric
  /// sum for every rank > 20. Identical math; just memoized.
  static final double _cumulativeAtBreakpoint =
      _computeCumulativeAtBreakpoint();

  static double _computeCumulativeAtBreakpoint() {
    final geom = math.pow(xpGrowthBand1, xpGrowthBreakpoint - 1).toDouble();
    return xpBase * (geom - 1) / (xpGrowthBand1 - 1);
  }

  /// `_cumulativeTable[i]` = `cumulativeXpForRank(i + 1)`. Length 99.
  static final List<double> _cumulativeTable = List<double>.unmodifiable(
    List<double>.generate(maxRank, (i) => cumulativeXpForRank(i + 1)),
  );

  /// Read-only view of the precomputed cumulative table.
  static List<double> get cumulativeTable => _cumulativeTable;
}

/// Character Level (spec §7).
///
/// `character_level = max(1, floor((Σ active_ranks - N_active) / 4) + 1)`
///
/// Phase 38e: `N_active = 7` (chest, back, legs, shoulders, arms, core,
/// cardio). The denominator stays 4. Adding cardio increases both Σ ranks
/// and N_active by the SAME amount when cardio is at rank 1 (`+1` to the
/// sum, `+1` to N), so the numerator `Σ ranks − N` is unchanged for a
/// pure-strength user — their level never regresses. Computed max rises
/// 148 → 172 (all seven at rank 99).
int characterLevel(
  Map<String, int> ranks, {
  List<String> activeKeys = _activeKeys,
}) {
  var total = 0;
  var n = 0;
  for (final key in activeKeys) {
    final r = ranks[key];
    if (r == null) continue;
    total += r;
    n += 1;
  }
  if (n == 0) return 1;
  final lvl = ((total - n) ~/ 4) + 1;
  return lvl < 1 ? 1 : lvl;
}

const List<String> _activeKeys = [
  'chest',
  'back',
  'legs',
  'shoulders',
  'arms',
  'core',
  'cardio',
];
