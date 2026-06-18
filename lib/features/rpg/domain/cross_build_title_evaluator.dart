import '../models/body_part.dart';
import '../models/title.dart';

/// Pure evaluator for the five cross-build distinction predicates (spec §10.3).
///
/// **Why a free-standing evaluator instead of a method on [Title]:** the JSON
/// catalog drives the slug+trigger metadata, but the predicate logic — AND/OR
/// across multiple body parts, ratio comparisons, "all six within 30%" — is
/// not expressible in JSON. Keeping the predicates here makes the v1 → v2
/// evolution path clean: cardio gets its own predicate alongside `iron_bound`
/// without touching the JSON envelope schema.
///
/// **Why pure / static:** identical to [`ClassResolver`](class_resolver.dart) —
/// the input is fully described by the rank map and the output is fully
/// determined by it. Pure functions are testable without a Riverpod
/// container, and the celebration-event builder can call this from any
/// snapshot pair without conditioning on the call site.
///
/// **Cardio (Phase 38f):** cardio is now a real earning track, so the cardio
/// cross-build conditions are live. `iron_bound` regained its low-cardio
/// condition (`cardio ≤ 10`) and two new cardio cross-build titles ship:
/// `the_forged_wind` (all six strength ≥ 60 AND cardio ≥ 60) and
/// `storm_tempered` (cardio ≥ 60 AND all six strength ≥ 30). All cardio
/// conditions use integer arithmetic so the Dart predicate stays bit-identical
/// to the SQL `evaluate_cross_build_titles_for_user` mirror (migration 00081).
class CrossBuildTitleEvaluator {
  const CrossBuildTitleEvaluator._();

  /// Floor every cross-build trigger requires before it can fire. Below this
  /// floor, the user is still consolidating and earning a structural title
  /// would feel unearned — every predicate gates on at least Rank 30 in some
  /// dimension.
  ///
  /// `iron_bound` and `saga_forged` use higher floors (60); `even_handed`
  /// uses 30. The min across all five is 30, so this is also the
  /// "any predicate could fire" lower bound.
  static const int evenHandedMinRank = 30;

  /// Spread fraction for `even_handed` — every body part must be within 30%
  /// of the max rank. Mirrors [`ClassResolver.ascendantSpreadFraction`] but
  /// at a higher minimum-rank floor (30 vs 5) so the title represents
  /// sustained balance rather than entry-level distribution.
  static const double evenHandedSpreadFraction = 0.30;

  /// Evaluate every cross-build trigger and return the slugs that fire for
  /// the given rank distribution.
  ///
  /// [ranks] is keyed by [BodyPart]; missing entries default to rank 1
  /// (matches the SQL default-row + [`RpgProgressSnapshot.progressFor`]
  /// contract). The cardio entry feeds the cardio cross-build conditions
  /// (Phase 38f): `iron_bound` (cardio ≤ 10), `the_forged_wind` /
  /// `storm_tempered` (cardio ≥ 60).
  ///
  /// Returns slugs in catalog order ([CrossBuildTriggerId.values] order):
  /// `pillar_walker, broad_shouldered, even_handed, iron_bound, saga_forged,
  /// the_forged_wind, storm_tempered`. The detector's idempotency guard
  /// (`alreadyEarnedSlugs`) deduplicates against the persisted record set.
  static List<String> evaluate(Map<BodyPart, int> ranks) {
    // Project to active body parts only, defaulting missing entries to
    // rank 1 (matches the resolver convention).
    int rank(BodyPart bp) => ranks[bp] ?? 1;

    final chest = rank(BodyPart.chest);
    final back = rank(BodyPart.back);
    final legs = rank(BodyPart.legs);
    final shoulders = rank(BodyPart.shoulders);
    final arms = rank(BodyPart.arms);
    final core = rank(BodyPart.core);
    final cardio = rank(BodyPart.cardio);

    final fired = <String>[];

    if (_pillarWalker(legs: legs, arms: arms)) {
      fired.add(CrossBuildTriggerId.pillarWalker.dbValue);
    }
    if (_broadShouldered(
      chest: chest,
      back: back,
      shoulders: shoulders,
      legs: legs,
      core: core,
    )) {
      fired.add(CrossBuildTriggerId.broadShouldered.dbValue);
    }
    if (_evenHanded(
      chest: chest,
      back: back,
      legs: legs,
      shoulders: shoulders,
      arms: arms,
      core: core,
    )) {
      fired.add(CrossBuildTriggerId.evenHanded.dbValue);
    }
    if (_ironBound(chest: chest, back: back, legs: legs, cardio: cardio)) {
      fired.add(CrossBuildTriggerId.ironBound.dbValue);
    }
    if (_sagaForged(
      chest: chest,
      back: back,
      legs: legs,
      shoulders: shoulders,
      arms: arms,
      core: core,
    )) {
      fired.add(CrossBuildTriggerId.sagaForged.dbValue);
    }
    if (_theForgedWind(
      chest: chest,
      back: back,
      legs: legs,
      shoulders: shoulders,
      arms: arms,
      core: core,
      cardio: cardio,
    )) {
      fired.add(CrossBuildTriggerId.theForgedWind.dbValue);
    }
    if (_stormTempered(
      chest: chest,
      back: back,
      legs: legs,
      shoulders: shoulders,
      arms: arms,
      core: core,
      cardio: cardio,
    )) {
      fired.add(CrossBuildTriggerId.stormTempered.dbValue);
    }

    return fired;
  }

  /// `pillar_walker` — Legs ≥ 40 AND Legs ≥ 2 × Arms.
  ///
  /// "Walks on legs, not arms" — the lifter who chases lower-body strength.
  /// Both conditions matter: a lifter with legs 40 and arms 25 is
  /// chest-dominant by the spread, not pillar-walking.
  static bool _pillarWalker({required int legs, required int arms}) {
    if (legs < 40) return false;
    return legs >= 2 * arms;
  }

  /// `broad_shouldered` — Chest+Back+Shoulders ≥ 1.6 × (Legs+Core) AND every
  /// upper-body track ≥ 30.
  ///
  /// **BUG-015 rebalance (2026-05-02, PO call):** the original 2× ratio was
  /// effectively unreachable for any lifter who trained legs at all (Chest 50
  /// + Back 50 + Shoulders 50 → upper 150 → required Legs+Core ≤ 75, i.e.
  /// Legs ≤ ~65). The PO audit found the typical Brazilian academy lifter
  /// runs push/pull 3-4×/week + legs 1×/week, and 1.6× catches that profile
  /// while still reading as a genuine upper-body specialist (a 50/50 split
  /// still routes elsewhere). Comparison uses integer arithmetic
  /// (`upper * 10 >= lower * 16`) to avoid float drift at the boundary —
  /// the Dart predicate must match the SQL mirror in
  /// `00043_cross_build_titles_backfill.sql` exactly.
  static bool _broadShouldered({
    required int chest,
    required int back,
    required int shoulders,
    required int legs,
    required int core,
  }) {
    if (chest < 30) return false;
    if (back < 30) return false;
    if (shoulders < 30) return false;
    final upper = chest + back + shoulders;
    final lower = legs + core;
    // 1.6× via integer arithmetic — equivalent to `upper >= 1.6 * lower`
    // without floating-point error at the boundary.
    return upper * 10 >= lower * 16;
  }

  /// `even_handed` — Every active rank within 30% of max AND every rank ≥ 30.
  ///
  /// Mirrors [`ClassResolver`]'s Ascendant predicate at a higher rank floor
  /// — the title is the persistent-balance reward, where the class is the
  /// snapshot-balance reward. A lifter can be Ascendant from rank 5+ but
  /// only Even-Handed once every track reaches 30.
  static bool _evenHanded({
    required int chest,
    required int back,
    required int legs,
    required int shoulders,
    required int arms,
    required int core,
  }) {
    if (chest < evenHandedMinRank) return false;
    if (back < evenHandedMinRank) return false;
    if (legs < evenHandedMinRank) return false;
    if (shoulders < evenHandedMinRank) return false;
    if (arms < evenHandedMinRank) return false;
    if (core < evenHandedMinRank) return false;
    final values = [chest, back, legs, shoulders, arms, core];
    final maxRank = values.reduce((a, b) => a > b ? a : b);
    final minRank = values.reduce((a, b) => a < b ? a : b);
    final spread = (maxRank - minRank) / maxRank;
    return spread <= evenHandedSpreadFraction;
  }

  /// `iron_bound` — Chest ≥ 60 AND Back ≥ 60 AND Legs ≥ 60 AND cardio ≤ 10.
  ///
  /// "The big-three of strength training" — the powerlifter heuristic. Each
  /// of the three big lifts must independently clear rank 60; this is a
  /// per-track threshold, not a sum (a chest-90/back-30/legs-60 lifter is
  /// not iron-bound).
  ///
  /// **Phase 38f — low-cardio condition restored.** With cardio now a real
  /// earning track, `iron_bound` regains its spec condition that the lifter's
  /// cardio is low (rank ≤ 10): the title is the strength-pure powerlifter
  /// distinction, so a runner who also benches/squats/deadlifts heavy routes
  /// to `the_forged_wind` instead. This tightening is FUTURE-awards-only —
  /// `earned_titles` is append-only and the SQL backfill never revokes an
  /// already-earned `iron_bound`.
  static bool _ironBound({
    required int chest,
    required int back,
    required int legs,
    required int cardio,
  }) {
    return chest >= 60 && back >= 60 && legs >= 60 && cardio <= 10;
  }

  /// `saga_forged` — Every active rank ≥ 60.
  ///
  /// The end-game prestige title. By the time every track is at rank 60
  /// the user has been training consistently for many months — this title
  /// signals "I have done the work" rather than any specific build shape.
  static bool _sagaForged({
    required int chest,
    required int back,
    required int legs,
    required int shoulders,
    required int arms,
    required int core,
  }) {
    return chest >= 60 &&
        back >= 60 &&
        legs >= 60 &&
        shoulders >= 60 &&
        arms >= 60 &&
        core >= 60;
  }

  /// `the_forged_wind` — All six strength tracks ≥ 60 AND cardio ≥ 60
  /// (Phase 38f).
  ///
  /// The complete-athlete apex: `saga_forged` (every strength track has done
  /// the work) PLUS a fully-forged cardio engine. "Iron that runs" — the
  /// lifter who never traded the lungs for the bar.
  static bool _theForgedWind({
    required int chest,
    required int back,
    required int legs,
    required int shoulders,
    required int arms,
    required int core,
    required int cardio,
  }) {
    return chest >= 60 &&
        back >= 60 &&
        legs >= 60 &&
        shoulders >= 60 &&
        arms >= 60 &&
        core >= 60 &&
        cardio >= 60;
  }

  /// `storm_tempered` — Cardio ≥ 60 AND all six strength tracks ≥ 30
  /// (Phase 38f).
  ///
  /// The cardio-led counterpart to `iron_bound`: a fully-forged cardio engine
  /// with broad-but-not-elite strength across every track. "Tempered, not
  /// narrowed" — the endurance athlete who kept the iron in the mix rather
  /// than letting strength wither.
  static bool _stormTempered({
    required int chest,
    required int back,
    required int legs,
    required int shoulders,
    required int arms,
    required int core,
    required int cardio,
  }) {
    return cardio >= 60 &&
        chest >= 30 &&
        back >= 30 &&
        legs >= 30 &&
        shoulders >= 30 &&
        arms >= 30 &&
        core >= 30;
  }

  /// Compute the cross-build progress hint for [slug] from the current rank
  /// distribution (BUG-014, Cluster 3).
  ///
  /// **Why this lives on the evaluator:** the predicate threshold logic IS
  /// the gap-math source of truth. The hint surface in [`titles_screen`] would
  /// otherwise have to mirror every floor and ratio inline — duplicating
  /// `iron_bound`'s "≥ 60" floor in two places lets one drift past the other.
  /// Keeping the gap math next to the predicate means a future re-spec
  /// (e.g. raise `iron_bound` to ≥ 65) updates the hint automatically.
  ///
  /// Returns null when:
  ///   * [slug] is unknown (unrecognized cross-build trigger).
  ///   * The predicate is already satisfied — the title should already be
  ///     awarded; rendering "0 more rank in X" would be misleading. The UI
  ///     falls back to a "predicate satisfied" copy (race window between
  ///     award and UI refresh).
  ///
  /// **Per-predicate gap surfacing rules (PO call):**
  ///   * `pillar_walker` — single body-part gap (legs to floor 40). The
  ///     ratio condition is harder to surface as a number; the floor is
  ///     the user-meaningful gate.
  ///   * `broad_shouldered` — surface the smallest gap among the three
  ///     upper guards (chest/back/shoulders) to floor 30. The ratio
  ///     condition is the soft gate; the per-track floor is what users
  ///     actually grind.
  ///   * `even_handed` — single body part furthest from floor 30. The
  ///     spread condition is binary at the per-track level.
  ///   * `iron_bound` — smallest gap among (chest/back/legs) to floor 60.
  ///   * `saga_forged` — single body part furthest from floor 60.
  ///
  /// Pure / static for the same reasons as [evaluate]: no Riverpod, no
  /// async, no IO. Unit-testable in isolation.
  static CrossBuildHint? gapHintFor(String slug, Map<BodyPart, int> ranks) {
    int rank(BodyPart bp) => ranks[bp] ?? 1;

    switch (slug) {
      case 'pillar_walker':
        // Surface only the legs floor gap. The 2x-arms ratio is harder to
        // express as "X more rank" since the user's path could either lift
        // legs or ignore arms.
        final legs = rank(BodyPart.legs);
        if (legs >= 40) return null;
        return CrossBuildHint(bodyPart: BodyPart.legs, gap: 40 - legs);

      case 'broad_shouldered':
        // Smallest gap among chest/back/shoulders to the floor 30.
        return _smallestGapAmong(
          ranks: ranks,
          parts: const [BodyPart.chest, BodyPart.back, BodyPart.shoulders],
          floor: 30,
        );

      case 'even_handed':
        // Single body part furthest from floor 30.
        return _largestGapAmong(
          ranks: ranks,
          parts: const [
            BodyPart.chest,
            BodyPart.back,
            BodyPart.legs,
            BodyPart.shoulders,
            BodyPart.arms,
            BodyPart.core,
          ],
          floor: 30,
        );

      case 'iron_bound':
        // Smallest gap among the big three to the floor 60. The cardio ≤ 10
        // condition is a ceiling, not a grind-toward floor — it isn't
        // surfaced as a "X more rank" hint (the user earns iron_bound by
        // NOT building cardio, which has no positive gap to close).
        return _smallestGapAmong(
          ranks: ranks,
          parts: const [BodyPart.chest, BodyPart.back, BodyPart.legs],
          floor: 60,
        );

      case 'saga_forged':
        // Single body part furthest from floor 60.
        return _largestGapAmong(
          ranks: ranks,
          parts: const [
            BodyPart.chest,
            BodyPart.back,
            BodyPart.legs,
            BodyPart.shoulders,
            BodyPart.arms,
            BodyPart.core,
          ],
          floor: 60,
        );

      case 'the_forged_wind':
        // Single body part (incl. cardio) furthest from floor 60.
        return _largestGapAmong(
          ranks: ranks,
          parts: const [
            BodyPart.chest,
            BodyPart.back,
            BodyPart.legs,
            BodyPart.shoulders,
            BodyPart.arms,
            BodyPart.core,
            BodyPart.cardio,
          ],
          floor: 60,
        );

      case 'storm_tempered':
        // Cardio gates at floor 60; the six strength tracks at floor 30.
        // Surface the single worst gap, weighting cardio's higher floor by
        // comparing each part against its own floor.
        return _largestGapToMixedFloor(
          ranks: ranks,
          partFloors: const {
            BodyPart.cardio: 60,
            BodyPart.chest: 30,
            BodyPart.back: 30,
            BodyPart.legs: 30,
            BodyPart.shoulders: 30,
            BodyPart.arms: 30,
            BodyPart.core: 30,
          },
        );

      default:
        return null;
    }
  }

  /// Smallest positive gap among [parts] to [floor]. Returns null if every
  /// part already clears the floor (predicate satisfied along this axis).
  static CrossBuildHint? _smallestGapAmong({
    required Map<BodyPart, int> ranks,
    required List<BodyPart> parts,
    required int floor,
  }) {
    BodyPart? best;
    int? bestGap;
    for (final bp in parts) {
      final r = ranks[bp] ?? 1;
      if (r >= floor) continue;
      final gap = floor - r;
      if (bestGap == null || gap < bestGap) {
        bestGap = gap;
        best = bp;
      }
    }
    if (best == null || bestGap == null) return null;
    return CrossBuildHint(bodyPart: best, gap: bestGap);
  }

  /// Largest positive gap among [parts] to [floor] — the body part the
  /// user is furthest from on this predicate. Returns null if every part
  /// already clears the floor.
  static CrossBuildHint? _largestGapAmong({
    required Map<BodyPart, int> ranks,
    required List<BodyPart> parts,
    required int floor,
  }) {
    BodyPart? worst;
    int? worstGap;
    for (final bp in parts) {
      final r = ranks[bp] ?? 1;
      if (r >= floor) continue;
      final gap = floor - r;
      if (worstGap == null || gap > worstGap) {
        worstGap = gap;
        worst = bp;
      }
    }
    if (worst == null || worstGap == null) return null;
    return CrossBuildHint(bodyPart: worst, gap: worstGap);
  }

  /// Largest positive gap across [partFloors] where each body part has its
  /// OWN floor (Phase 38f — `storm_tempered` mixes cardio's floor 60 with the
  /// strength tracks' floor 30). Returns null if every part already clears
  /// its respective floor.
  static CrossBuildHint? _largestGapToMixedFloor({
    required Map<BodyPart, int> ranks,
    required Map<BodyPart, int> partFloors,
  }) {
    BodyPart? worst;
    int? worstGap;
    for (final entry in partFloors.entries) {
      final r = ranks[entry.key] ?? 1;
      if (r >= entry.value) continue;
      final gap = entry.value - r;
      if (worstGap == null || gap > worstGap) {
        worstGap = gap;
        worst = entry.key;
      }
    }
    if (worst == null || worstGap == null) return null;
    return CrossBuildHint(bodyPart: worst, gap: worstGap);
  }
}

/// Locked-row stat-line breakdown for [`CrossBuildTitleEvaluator`] (BUG-014).
///
/// Returns the (body-part, current-rank, floor) tuples the titles screen
/// should render as a structured chip — e.g.
/// `[(chest, 42, 60), (back, 60, 60), (legs, 60, 60)]` for `iron_bound`.
///
/// Per-slug breakdown (locked):
///   * `pillar_walker` — single tuple: legs vs 40
///   * `broad_shouldered` — three tuples: chest/back/shoulders vs 30
///   * `even_handed` — six tuples (every active body part) vs 30
///   * `iron_bound` — three tuples: chest/back/legs vs 60
///   * `saga_forged` — six tuples (every active body part) vs 60
///
/// Returns an empty list for unknown slugs so the UI can render a neutral
/// fallback without a null-check at every call site.
List<CrossBuildStat> crossBuildStatsFor(String slug, Map<BodyPart, int> ranks) {
  int rank(BodyPart bp) => ranks[bp] ?? 1;
  CrossBuildStat stat(BodyPart bp, int floor) =>
      CrossBuildStat(bodyPart: bp, current: rank(bp), floor: floor);

  switch (slug) {
    case 'pillar_walker':
      return [stat(BodyPart.legs, 40)];
    case 'broad_shouldered':
      return [
        stat(BodyPart.chest, 30),
        stat(BodyPart.back, 30),
        stat(BodyPart.shoulders, 30),
      ];
    case 'even_handed':
      return [
        for (final bp in const [
          BodyPart.chest,
          BodyPart.back,
          BodyPart.legs,
          BodyPart.shoulders,
          BodyPart.arms,
          BodyPart.core,
        ])
          stat(bp, 30),
      ];
    case 'iron_bound':
      return [
        stat(BodyPart.chest, 60),
        stat(BodyPart.back, 60),
        stat(BodyPart.legs, 60),
      ];
    case 'saga_forged':
      return [
        for (final bp in const [
          BodyPart.chest,
          BodyPart.back,
          BodyPart.legs,
          BodyPart.shoulders,
          BodyPart.arms,
          BodyPart.core,
        ])
          stat(bp, 60),
      ];
    case 'the_forged_wind':
      // Phase 38f — all seven active tracks (six strength + cardio) vs 60.
      return [
        for (final bp in const [
          BodyPart.chest,
          BodyPart.back,
          BodyPart.legs,
          BodyPart.shoulders,
          BodyPart.arms,
          BodyPart.core,
          BodyPart.cardio,
        ])
          stat(bp, 60),
      ];
    case 'storm_tempered':
      // Phase 38f — cardio vs 60, the six strength tracks vs 30.
      return [
        stat(BodyPart.cardio, 60),
        for (final bp in const [
          BodyPart.chest,
          BodyPart.back,
          BodyPart.legs,
          BodyPart.shoulders,
          BodyPart.arms,
          BodyPart.core,
        ])
          stat(bp, 30),
      ];
    default:
      return const <CrossBuildStat>[];
  }
}

/// One body-part bucket in a structured cross-build stat-line.
class CrossBuildStat {
  const CrossBuildStat({
    required this.bodyPart,
    required this.current,
    required this.floor,
  });

  final BodyPart bodyPart;

  /// User's current rank for this body part. Always >= 1 (rank ladder
  /// floors at 1; default-row rank is 1).
  final int current;

  /// Predicate floor for this body part on the cross-build trigger that
  /// owns this stat. Constant per (slug, body-part) tuple.
  final int floor;

  /// Whether the user has already cleared the floor for this body-part
  /// component of the predicate. The chip highlights cleared vs gapped
  /// stats with the same textDim color but different opacity (cleared =
  /// brighter).
  bool get isCleared => current >= floor;
}

/// Result of [`CrossBuildTitleEvaluator.gapHintFor`] — the body part the UI
/// should call out and the rank delta to surface.
///
/// **Why a value class instead of a record:** the UI passes this through
/// the localization layer (`localizedBodyPartName(bodyPart, l10n)`) and
/// embeds the gap into the ICU placeholder. A typed class with named
/// fields reads better at the call site than a positional record, and
/// stays cheap (`const` constructor, value equality).
class CrossBuildHint {
  const CrossBuildHint({required this.bodyPart, required this.gap});

  /// The body part to surface in the hint copy. The localizer turns this
  /// into the locale-correct string ("peito" / "chest", etc.).
  final BodyPart bodyPart;

  /// Positive rank delta the user must close. Always > 0 — when every
  /// floor is cleared, [`gapHintFor`] returns null instead of a zero-gap
  /// hint.
  final int gap;

  @override
  bool operator ==(Object other) =>
      other is CrossBuildHint && other.bodyPart == bodyPart && other.gap == gap;

  @override
  int get hashCode => Object.hash(bodyPart, gap);

  @override
  String toString() =>
      'CrossBuildHint(bodyPart: ${bodyPart.dbValue}, gap: $gap)';
}
