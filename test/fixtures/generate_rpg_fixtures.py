"""
Generates JSON fixtures from the canonical Python XP simulation for Dart
parity tests — Phase 29 v2 + 29.6 LOCKED oracle.

Run:  python test/fixtures/generate_rpg_fixtures.py
Output: test/fixtures/rpg_xp_fixtures.json

This file is the SINGLE source of truth for both Python and Dart XP
calculations. If a Dart calculator drifts vs the Python sim, the fixture
test fails, and the spec/Python is the authority.

Phase 29 v2 oracle additions:
  * `set_xp_v2`           — 94-row matrix exercising the full 11-multiplier
                            chain (base × intensity × strength × novelty ×
                            cap × difficulty × tier_diff × abs_strength_prem
                            × overload × frequency × attribution_share).
  * `implied_tier`        — 17 per-lift × per-gender interpolation cases
                            (bench/squat/deadlift/ohp male + female; isolation;
                            variant discount; gender NULL → male).
  * `abs_strength_premium` — 12 curve points around the [E_FLOOR, E_CEIL]
                             piecewise-linear ramp (T ≤ 35 → 1.0, T ≥ 55 → 1.8).
  * `tier_diff_mult`      — 17 (T, R) lookup cases including floor (0.25),
                            ceiling (8.0), and the canonical T=R=1 unit point.
  * `overload_mult`       — 7 cases exercising the in-band PR detector's
                            AND/OR ladder (1.15 / 1.10 / 1.05 / 1.00).
  * `frequency_mult`      — 7 cases pinning [1.00, 1.06, 1.10, 1.06, 1.00].
  * `near_failure_inferred` — 7 cases pinning actual < target × 0.85.

The legacy 6-multiplier fixture lists are preserved (`set_xp_examples`,
`intensity_lookup`, `volume_load`, `strength_mult`, `novelty_mult`,
`cap_mult`, `rank_curve`, `vitality`, `character_level`,
`backfill_replay`). They test Dart's component-level parity with the
legacy chain that production code didn't even consume — they're still
load-bearing for the Dart unit tests, and the values are computed
against the new Phase 29 v2 constants where applicable (volume_exponent
= 0.60, weekly_cap = 15, etc.).
"""

from __future__ import annotations

import json
import math
import os
import sys

# Make `tasks/rpg-xp-simulation.py` importable (it has a hyphen in the
# filename so we read it manually).
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SIM_PATH = os.path.join(ROOT, 'tasks', 'rpg-xp-simulation.py')
CARDIO_SIM_PATH = os.path.join(ROOT, 'tasks', 'cardio-xp-simulation.py')


def _load_module(name, path):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


sim = _load_module('rpg_sim', SIM_PATH)
# Phase 38c — the cardio formula oracle. Same importlib pattern (hyphenated
# filename). The cardio sim is standalone; we only read its pure fns.
csim = _load_module('cardio_sim', CARDIO_SIM_PATH)


# ---------------------------------------------------------------------------
# Legacy fixture builders (component-level Dart parity)
# ---------------------------------------------------------------------------

def fx_intensity_lookup() -> list[dict]:
    """Reps -> intensity multiplier table. Lookup is reps-floor."""
    cases = []
    for reps in [1, 2, 3, 4, 5, 7, 8, 10, 12, 13, 15, 16, 20, 25]:
        cases.append({'reps': reps, 'intensity_mult': sim.intensity_for_reps(reps)})
    return cases


def fx_volume_load() -> list[dict]:
    """volume_load = max(1.0, weight × reps), then base = volume_load^0.60."""
    cases = []
    for w, r in [(0, 8), (1, 1), (5, 5), (20, 8), (60, 5), (100, 8), (140, 3), (200, 1)]:
        vl = max(1.0, w * r)
        base = vl ** sim.VOLUME_EXPONENT
        cases.append({
            'weight_kg': w,
            'reps': r,
            'volume_load': vl,
            'base_xp': base,
        })
    return cases


def fx_strength_mult() -> list[dict]:
    """strength_mult = clamp(weight / peak, 0.40, 1.00)."""
    cases = []
    for weight, peak, expected in [
        (100, 100, 1.0),
        (110, 100, 1.0),
        (70, 100, 0.7),
        (50, 100, 0.5),
        (30, 100, 0.4),
        (10, 100, 0.4),
        (50, 0, 1.0),
    ]:
        if peak <= 0:
            mult = 1.0
        else:
            mult = max(sim.STRENGTH_MULT_FLOOR, min(1.0, weight / peak))
        cases.append({
            'weight_kg': weight,
            'peak_load': peak,
            'strength_mult': mult,
            'expected': expected,
        })
    return cases


def fx_novelty_mult() -> list[dict]:
    """novelty_mult = exp(-session_volume_for_body_part / 15)."""
    cases = []
    for sv in [0, 1, 5, 10, 15, 20, 30, 50]:
        nm = math.exp(-sv / sim.NOVELTY_DENOMINATOR)
        cases.append({'session_volume_for_body_part': sv, 'novelty_mult': nm})
    return cases


def fx_cap_mult() -> list[dict]:
    """cap_mult = 0.3 if weekly_volume >= 15 else 1.0 (Phase 24d propagation)."""
    cases = []
    for wv in [0, 10, 14, 14.99, 15, 15.5, 20, 30, 50]:
        cm = sim.OVER_CAP_MULTIPLIER if wv >= sim.WEEKLY_CAP_SETS else 1.0
        cases.append({'weekly_volume_for_body_part': wv, 'cap_mult': cm})
    return cases


def fx_set_xp_examples() -> list[dict]:
    """Legacy 6-multiplier chain set_xp fixture (pre-Phase-29 component parity).

    These cases pin the Dart calculator's basic chain against Phase 24c +
    24d constants. Phase 29 v2's full chain is covered by `set_xp_v2`
    (and by the integration parity test against the persona panel). This
    list is preserved verbatim from the Phase 24c+d generator so the
    existing Dart unit tests' component-level assertions stay stable.

    Each scenario stores already-converted `effective_load` in
    `inputs.weight_kg` — the Dart calculator is bodyweight-agnostic, so
    callers pre-convert. `bodyweight_kg`, `uses_bodyweight_load`,
    `effective_load`, `entered_weight_kg` are informational keys for SQL
    parity tests + audit-trail clarity.
    """
    cases = []
    scenarios = [
        {'name': 'bench_peak_fresh', 'weight': 100, 'reps': 5, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press')},
        {'name': 'bench_peak_late_session', 'weight': 100, 'reps': 5, 'peak': 100,
         'session_volume_bp': 10, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press')},
        {'name': 'bench_deload_70', 'weight': 70, 'reps': 5, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press')},
        {'name': 'past_weekly_cap', 'weight': 100, 'reps': 5, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 25,
         'slug': 'deadlift',
         'difficulty_mult': sim.difficulty_mult_for_slug('deadlift')},
        {'name': 'high_rep_endurance_floor', 'weight': 60, 'reps': 20, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'leg_curl',
         'difficulty_mult': sim.difficulty_mult_for_slug('leg_curl')},
        {'name': 'one_rm_ceiling', 'weight': 140, 'reps': 1, 'peak': 130,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'push_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('push_press')},
        {'name': 'bodyweight_floor', 'weight': 0, 'reps': 8, 'peak': 0,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'push_up',
         'difficulty_mult': sim.difficulty_mult_for_slug('push_up')},
        {'name': 'stagnant_curl', 'weight': 5, 'reps': 12, 'peak': 5,
         'session_volume_bp': 5, 'weekly_volume_bp': 8,
         'slug': 'barbell_curl',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_curl')},
        {'name': 'user_created_default_1_0', 'weight': 80, 'reps': 8, 'peak': 80,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': None,
         'difficulty_mult': sim.difficulty_mult_for_slug('not_a_real_slug')},
        {'name': 'explicit_floor_0_85', 'weight': 100, 'reps': 8, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': None,
         'difficulty_mult': sim.DIFFICULTY_MULT_FLOOR},
        {'name': 'explicit_ceiling_1_25', 'weight': 100, 'reps': 8, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': None,
         'difficulty_mult': sim.DIFFICULTY_MULT_CEILING},
        # Phase 24c bodyweight-load boundary scenarios — using simple
        # bodyweight + entered semantics here (legacy fixture; full
        # per-exercise BW ratio is exercised by set_xp_v2).
        {'name': 'bodyweight_load_pure_bw', 'weight': 0, 'reps': 8, 'peak': 0,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'pull_up',
         'difficulty_mult': 1.21,
         'bodyweight_kg': 70,
         'uses_bodyweight_load': True},
        {'name': 'bodyweight_load_weighted', 'weight': 20, 'reps': 5, 'peak': 25,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'ring_dip',
         'difficulty_mult': 1.21,
         'bodyweight_kg': 70,
         'uses_bodyweight_load': True},
        {'name': 'bodyweight_load_not_bw_exercise', 'weight': 80, 'reps': 8, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': 1.09,
         'bodyweight_kg': 70,
         'uses_bodyweight_load': False},
        {'name': 'bodyweight_load_null_bodyweight', 'weight': 10, 'reps': 5, 'peak': 10,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'pull_up',
         'difficulty_mult': 1.21,
         'bodyweight_kg': None,
         'uses_bodyweight_load': True},
    ]
    for s in scenarios:
        bodyweight_kg = s.get('bodyweight_kg')
        if 'uses_bodyweight_load' in s:
            uses_bw = s['uses_bodyweight_load']
        elif s['slug'] is None:
            uses_bw = False
        else:
            uses_bw = sim.uses_bodyweight_load(s['slug'])
        # Legacy fixture: simple BW + entered (matches the pre-Phase-29
        # SQL CASE branch; Phase 29 v2's per-exercise BW ratio lives in
        # `set_xp_v2`).
        if uses_bw:
            eff_weight = (s['weight'] or 0) + (bodyweight_kg or 0)
        else:
            eff_weight = s['weight'] or 0

        vl = max(1.0, eff_weight * s['reps'])
        base = vl ** sim.VOLUME_EXPONENT
        intensity = sim.intensity_for_reps(s['reps'])
        peak = s['peak'] if s['peak'] > 0 else s['weight']
        if peak <= 0:
            strength_mult = 1.0
        else:
            strength_mult = max(sim.STRENGTH_MULT_FLOOR,
                                min(1.0, eff_weight / peak))
        novelty = math.exp(-s['session_volume_bp'] / sim.NOVELTY_DENOMINATOR)
        cap = sim.OVER_CAP_MULTIPLIER if s['weekly_volume_bp'] >= sim.WEEKLY_CAP_SETS else 1.0
        diff_mult = s['difficulty_mult']
        set_xp = base * intensity * strength_mult * novelty * cap * diff_mult
        cases.append({
            'name': s['name'],
            'inputs': {
                'weight_kg': eff_weight,
                'reps': s['reps'],
                'peak_load': s['peak'],
                'session_volume_for_body_part': s['session_volume_bp'],
                'weekly_volume_for_body_part': s['weekly_volume_bp'],
                'difficulty_mult': diff_mult,
                'slug': s['slug'],
                'bodyweight_kg': bodyweight_kg,
                'uses_bodyweight_load': uses_bw,
                'entered_weight_kg': s['weight'],
                'effective_load': eff_weight,
            },
            'components': {
                'volume_load': vl,
                'base_xp': base,
                'intensity_mult': intensity,
                'strength_mult': strength_mult,
                'novelty_mult': novelty,
                'cap_mult': cap,
                'difficulty_mult': diff_mult,
            },
            'set_xp': set_xp,
        })
    return cases


def fx_attribution_distribution() -> list[dict]:
    """For a given exercise + set_xp, compute per-body-part XP."""
    cases = []
    for ex_slug, dist in sim.ATTRIBUTION.items():
        cases.append({
            'exercise_slug': ex_slug,
            'attribution': dist,
            'set_xp_input': 100.0,
            'expected_distribution': {bp: 100.0 * share for bp, share in dist.items()},
        })
    return cases


def fx_rank_curve() -> dict:
    """Cumulative XP for each rank (1..99) + rank_for_xp lookups (Phase 29 v2
    piecewise: geometric 1-20, linear 21+).
    """
    cumulative = {}
    for n in range(1, 100):
        cumulative[str(n)] = sim.xp_for_rank(n)
    # Lookups exercise the binary-search inverse. Includes piecewise breakpoint
    # samples — `cumulative[20]` and `cumulative[20] + 1` straddle the
    # geometric→linear transition.
    cum_breakpoint = sim.xp_for_rank(sim.RANK_CURVE_BREAKPOINT)
    cum_after_breakpoint = sim.xp_for_rank(sim.RANK_CURVE_BREAKPOINT + 1)
    lookups = []
    boundary_pairs = [
        (0, 1),
        (59, 1), (60, 2),
        (277, 2), (278, 3),
        (813, 3), (814, 4),
        (3068, 8), (3069, 8),
        # Phase 29 v2 piecewise breakpoint: cumulative[20] = ~3404 → rank 20.
        # cumulative[21] = cumulative[20] + 367.0.
        (int(cum_breakpoint), 20),
        (int(cum_after_breakpoint) - 1, 20),
        (int(cum_after_breakpoint), 21),
        # Linear band: each rank costs LINEAR_XP_PER_RANK = 367.0
        (int(cum_after_breakpoint + 367.0) - 1, 21),
        (int(cum_after_breakpoint + 367.0), 22),
        # High-end saturation
        (int(sim.xp_for_rank(99)), 99),
        (9999999, 99),
    ]
    for total_xp, rank in boundary_pairs:
        actual_rank = sim.rank_for_xp(total_xp)
        lookups.append({'total_xp': total_xp, 'rank': actual_rank})
    milestones = []
    for n in [1, 2, 5, 10, 20, 21, 30, 50, 70, 90, 99]:
        milestones.append({'rank': n, 'cumulative_xp': sim.xp_for_rank(n)})
    return {
        'cumulative': cumulative,
        'lookups': lookups,
        'milestones': milestones,
        'breakpoint': sim.RANK_CURVE_BREAKPOINT,
        'linear_xp_per_rank': sim.LINEAR_XP_PER_RANK,
        'cumulative_at_breakpoint': cum_breakpoint,
        'cumulative_after_breakpoint': cum_after_breakpoint,
    }


def fx_vitality() -> dict:
    """Vitality EWMA test cases — verifies asymmetric α + peak monotonicity.

    Uses τ_up = 2 weeks, τ_down = 6 weeks.
    α_up = 1 - exp(-1/2) ≈ 0.3935
    α_down = 1 - exp(-1/6) ≈ 0.1535
    """
    alpha_up = 1 - math.exp(-1 / sim.VITALITY_TAU_UP_WEEKS)
    alpha_down = 1 - math.exp(-1 / sim.VITALITY_TAU_DOWN_WEEKS)

    trajectory = []
    ewma = 0.0
    peak = 0.0
    weekly = [100] * 10 + [0] * 20
    for week, wv in enumerate(weekly, start=1):
        if wv >= ewma:
            alpha = alpha_up
        else:
            alpha = alpha_down
        ewma = alpha * wv + (1 - alpha) * ewma
        if ewma > peak:
            peak = ewma
        trajectory.append({
            'week': week,
            'weekly_volume': wv,
            'ewma': ewma,
            'peak': peak,
            'pct': (ewma / peak) if peak > 0 else 0.0,
        })

    snaps = sim.simulate(sim.ARCHETYPES['comeback_kid'], weeks=260)
    comeback_chest = []
    for w in [13, 26, 52, 60, 78, 80, 92, 104]:
        snap = snaps[w - 1]
        comeback_chest.append({
            'week': w,
            'chest_vitality_pct': snap['vitality']['chest'],
            'is_layoff': snap['is_layoff'],
        })

    return {
        'alpha_up': alpha_up,
        'alpha_down': alpha_down,
        'tau_up_weeks': sim.VITALITY_TAU_UP_WEEKS,
        'tau_down_weeks': sim.VITALITY_TAU_DOWN_WEEKS,
        'rebuild_then_decay_trajectory': trajectory,
        'comeback_chest_trajectory': comeback_chest,
    }


def fx_character_level() -> list[dict]:
    """Character level = max(1, floor((Σranks - N) / 4) + 1).

    Phase 38e: N = 7 active tracks (six strength + cardio). The denominator
    stays 4 — only the active SET grows. A cardio rank of 1 adds +1 to both
    Σranks and N, so the numerator (Σranks - N) is unchanged vs a 6-track
    pure-strength user (the never-regress invariant). Computed max rises
    148 → 172 (all seven at rank 99). The `saga_eternal` title threshold
    stays 148 (the 172-cap title is Phase 38f) — that's a title-table
    concern, not a computed-level one.
    """
    cases = []
    scenarios = [
        ({'chest': 1, 'back': 1, 'legs': 1, 'shoulders': 1, 'arms': 1, 'core': 1, 'cardio': 1}, 1),
        ({'chest': 5, 'back': 5, 'legs': 5, 'shoulders': 5, 'arms': 5, 'core': 5, 'cardio': 5}, 8),
        ({'chest': 20, 'back': 20, 'legs': 20, 'shoulders': 20, 'arms': 20, 'core': 20, 'cardio': 20}, 34),
        ({'chest': 50, 'back': 50, 'legs': 50, 'shoulders': 50, 'arms': 50, 'core': 50, 'cardio': 50}, 86),
        ({'chest': 99, 'back': 99, 'legs': 99, 'shoulders': 99, 'arms': 99, 'core': 99, 'cardio': 99}, 172),
        # Never-regress proof: a pure-strength user (cardio still at rank 1)
        # lands on the SAME level as the pre-38e 6-track computation.
        # Σ=6×20+1=121, N=7 → floor((121-7)/4)+1 = floor(114/4)+1 = 28+1 = 29
        # (identical to the old 6-track all-20 → 29).
        ({'chest': 20, 'back': 20, 'legs': 20, 'shoulders': 20, 'arms': 20, 'core': 20, 'cardio': 1}, 29),
    ]
    for ranks, expected in scenarios:
        cases.append({'ranks': ranks, 'character_level': expected})
    return cases


# ---------------------------------------------------------------------------
# Phase 29 v2 oracle builders
# ---------------------------------------------------------------------------

def fx_implied_tier() -> list[dict]:
    """17 cases for the per-lift × per-gender Symmetric Strength tier
    interpolator, including:
      * Untrained / Novice / Beginner / Intermediate / Advanced / Elite /
        World-class / Legendary boundary pins per family
      * Female table cases (separate empirical ratios)
      * Per-exercise variant discount (e.g. leg_press 0.65, incline_bench 0.90)
      * Gender NULL → male table fallback
      * Bodyweight 0 → default tier (15.0)
    """
    cases = []
    spec = [
        # Diego — bench 85kg × 5 reps @ 80kg BW (male). Brzycki 1RM ≈ 95.6kg,
        # ratio ≈ 1.20 → bench male tier ≈ 24-25 (Beginner→Intermediate).
        ('diego_bench_male', 'bench', 85, 5, 80.0, False, None),
        # Female Intermediate — bench 45kg × 8 @ 60kg BW. 1RM ≈ 55.9, ratio
        # ≈ 0.93 → female bench tier ≈ 19-21 (Beginner→Intermediate).
        ('female_int_bench', 'bench', 45, 8, 60.0, True, None),
        # Elite — bench 180kg × 3 @ 95kg BW. 1RM ≈ 190.6, ratio ≈ 2.00 →
        # male bench tier = 55 (World-class boundary).
        ('elite_bench_male', 'bench', 180, 3, 95.0, False, None),
        # Untrained male squat 30kg × 8 @ 80kg BW. 1RM ≈ 37.2, ratio ≈ 0.47
        # (< 0.60 floor) → tier = 0 (Untrained floor).
        ('untrained_squat_male', 'squat', 30, 8, 80.0, False, None),
        # Beginner male squat 100kg × 5 @ 80kg BW. 1RM ≈ 112.5, ratio
        # ≈ 1.41 → tier ≈ 19-20 (Beginner→Intermediate boundary).
        ('beg_squat_male', 'squat', 100, 5, 80.0, False, None),
        # Legendary male deadlift 300kg × 3 @ 100kg BW. 1RM ≈ 317.6, ratio
        # ≈ 3.18 → tier ≈ 62-64 (World-class→Legendary).
        ('leg_deadlift_male', 'deadlift', 300, 3, 100.0, False, None),
        # Female beginner deadlift 60kg × 8 @ 58kg BW. 1RM ≈ 74.5, ratio
        # ≈ 1.28 → tier ≈ 13-14 (Novice→Beginner).
        ('female_beg_deadlift', 'deadlift', 60, 8, 58.0, True, None),
        # Per-exercise discount — leg_press 200kg × 5 @ 80kg BW. With
        # discount 0.65, effective ratio = (200×36/32)/80/0.65 ≈ 4.33 →
        # uses squat tiers, far above World-class → 55 (saturated).
        ('leg_press_discount', 'leg_press', 200, 5, 80.0, False, None),
        # Incline bench discount 0.90 — 80kg × 8 @ 80kg BW. 1RM ≈ 99.3,
        # ratio = 99.3 / 80 / 0.90 ≈ 1.38 → male bench tier between
        # Intermediate (25) and Advanced (35) → ~30.
        ('incline_bench_discount', 'incline_bench', 80, 8, 80.0, False, None),
        # Gender NULL → male table fallback. Same inputs as `diego_bench_male`
        # but passed without the female flag.
        ('gender_null_bench', 'bench', 85, 5, 80.0, False, None),
        # Bodyweight 0 → degraded path returns 15.0 default tier.
        ('bw_zero_default', 'bench', 100, 5, 0.0, False, None),
        # OHP male — 60kg × 5 @ 80kg BW. 1RM ≈ 67.5, ratio ≈ 0.84 → OHP
        # male tier ≈ 28-30 (Intermediate→Advanced).
        ('ohp_male_int', 'overhead_press', 60, 5, 80.0, False, None),
        # OHP female — 30kg × 5 @ 60kg BW. 1RM ≈ 33.8, ratio ≈ 0.56 →
        # OHP female ≈ 25-26 (Intermediate boundary).
        ('ohp_female_int', 'overhead_press', 30, 5, 60.0, True, None),
        # Row male — 80kg × 8 @ 80kg BW. 1RM ≈ 99.3, ratio ≈ 1.24 →
        # row male tier ≈ 15-17 (Beginner→Intermediate).
        ('row_male_beg', 'row', 80, 8, 80.0, False, None),
        # Pull-up via 'pullup' alias (uses row family, no discount applied
        # in EXERCISE_TIER_DISCOUNT). 0kg × 10 @ 70kg BW → uses Brzycki
        # with entered weight 0 → 1RM 0 → ratio 0 → tier 0 (Untrained
        # floor).
        ('pullup_no_weight', 'pullup', 0, 10, 70.0, False, None),
        # Isolation (curl) male — 25kg × 10 @ 80kg BW. 1RM ≈ 33.3, ratio
        # ≈ 0.42 → isolation tier ≈ 45 (Elite — isolation ratios are
        # much smaller because the family table starts at 0.08).
        ('curl_iso_male', 'curl', 25, 10, 80.0, False, None),
        # Tricep_pushdown (isolation) female — 12kg × 12 @ 60kg BW.
        # 1RM ≈ 17.3, ratio ≈ 0.29 → isolation female tier (table tops
        # at 0.62 World-class) → ~40.
        ('pushdown_iso_female', 'tricep_pushdown', 12, 12, 60.0, True, None),
    ]
    for name, exercise, weight, reps, bw, female, _expected in spec:
        tier = sim.implied_tier(exercise, weight, reps, bw, female=female)
        cases.append({
            'name': name,
            'exercise': exercise,
            'weight_kg': weight,
            'reps': reps,
            'bodyweight_kg': bw,
            'female': female,
            'implied_tier': tier,
        })
    return cases


def fx_abs_strength_premium() -> list[dict]:
    """12-row curve for `abs_strength_premium = 1 + 0.8 × frac` where
    `frac = clamp((T - E_FLOOR) / (E_CEIL - E_FLOOR), 0, 1)`.

    Covers:
      * Below E_FLOOR (35) → frac = 0 → premium = 1.0
      * Exactly E_FLOOR  → premium = 1.0
      * Mid-band (T=40, 45, 50) → fractional premiums
      * Exactly E_CEIL (55) → premium = 1.8
      * Above E_CEIL → saturated at 1.8
    """
    cases = []
    for T in [0.0, 10.0, 20.0, 30.0, 34.99, 35.0, 40.0, 45.0, 50.0, 55.0,
              60.0, 70.0]:
        frac = sim.abs_strength_premium_frac(T)
        premium = sim.abs_strength_premium(T)
        cases.append({
            'implied_tier': T,
            'frac': frac,
            'abs_strength_premium': premium,
        })
    return cases


def fx_tier_diff_mult() -> list[dict]:
    """17 (T, R) cases for tier_diff_mult = clamp(((2T+10)/(T+R+10))^2.5,
    0.25, 8.0).

    Covers floor (lift far below current rank), ceiling (huge T at R=1),
    canonical unit point (T=R=1 → 1.0), and the documented persona pins
    (Diego wk1 ≈ T=24, R=1 → ~2.5×).
    """
    cases = []
    spec = [
        (1.0, 1.0),     # canonical unit — should produce 1.0
        (0.0, 1.0),     # T=0 → returns 1.0 directly (early-exit)
        (24.0, 1.0),    # Diego wk1-ish — strong tier punching above newcomer
        (35.0, 1.0),    # mid-game — Advanced lift @ R=1
        (46.0, 1.0),    # Elite-tier lift, fresh user
        (55.0, 1.0),    # World-class lift, fresh user
        (70.0, 1.0),    # Beyond Legendary, fresh — should saturate ceiling
        (5.0, 25.0),    # weak lift @ Intermediate rank — floor side
        (1.0, 50.0),    # Untrained lift @ Advanced rank — floor
        (25.0, 25.0),   # at-parity Intermediate
        (50.0, 50.0),   # at-parity Advanced
        (10.0, 30.0),   # 30% below current
        (45.0, 35.0),   # 28% above
        (35.0, 50.0),   # 30% below
        (60.0, 30.0),   # double current — strong premium
        (15.0, 5.0),    # 3× current — strong premium for early-game
        (8.0, 8.0),     # at-parity early-mid
    ]
    for T, R in spec:
        mult = sim.tier_diff_mult(R, T)
        cases.append({
            'implied_tier': T,
            'current_rank': R,
            'tier_diff_mult': mult,
        })
    return cases


def fx_overload_mult() -> list[dict]:
    """7 cases for the in-band PR detector. AND/OR ladder:
      * weight > prior_weight                       → 1.15 (new weight PR)
      * reps > prior AND weight >= prior            → 1.10 (volume PR same load)
      * reps > prior OR weight > prior              → 1.05 (modest improvement)
      * else                                         → 1.00 (no overload)

    `best_by_band` is keyed (exercise, band). Each case carries the prior
    best as `prior_weight` / `prior_reps` (or null for "no prior").
    """
    cases = []
    spec = [
        # No prior → no overload (1.00)
        ('first_set_no_prior', 'bench', 80, 5, None, None, 1.00),
        # New weight PR (heavy band): 85 > 80, same exercise/band
        ('new_weight_pr', 'bench', 85, 5, 80, 5, 1.15),
        # Volume PR at same load: 8 > 5 reps, weight tied
        ('volume_pr_same_load', 'bench', 80, 8, 80, 5, 1.10),
        # Reps up + weight down → modest 1.05
        ('reps_up_weight_down', 'bench', 75, 10, 80, 5, 1.05),
        # Identical inputs → no overload
        ('no_change', 'bench', 80, 5, 80, 5, 1.00),
        # Different rep band — heavy vs hypertrophy. 80×10 vs prior 80×3
        # lands in hypertrophy band, where there's no prior → 1.00.
        ('different_band_no_prior', 'bench', 80, 10, 80, 3, 1.00),
        # Weight down + reps down → 1.00
        ('regression', 'bench', 60, 3, 80, 5, 1.00),
    ]
    for name, exercise, weight, reps, prior_w, prior_r, expected in spec:
        best_by_band = {}
        if prior_w is not None:
            prior_band = sim.rep_band(prior_r)
            best_by_band[(exercise, prior_band)] = (prior_w, prior_r)
        mult, _ = sim.overload_mult(exercise, weight, reps, best_by_band)
        cases.append({
            'name': name,
            'exercise': exercise,
            'weight_kg': weight,
            'reps': reps,
            'prior_weight_kg': prior_w,
            'prior_reps': prior_r,
            'overload_mult': mult,
            'expected': expected,
        })
    return cases


def fx_frequency_mult() -> list[dict]:
    """7 cases pinning the table [1.00, 1.06, 1.10, 1.06, 1.00] for
    sessions 1/2/3/4/5+ per body part in a 7d window.
    """
    cases = []
    spec = [
        (0, 1.00),  # 0 → clamped to 1 (1st session = 1.00)
        (1, 1.00),
        (2, 1.06),
        (3, 1.10),
        (4, 1.06),
        (5, 1.00),
        (7, 1.00),  # past 5 → still 1.00 (clamped)
    ]
    for n, expected in spec:
        mult = sim.frequency_mult(n)
        cases.append({
            'session_count': n,
            'frequency_mult': mult,
            'expected': expected,
        })
    return cases


def fx_near_failure_inferred() -> list[dict]:
    """7 cases for `actual < target × 0.85` → near_failure True."""
    cases = []
    spec = [
        # Target NULL → never inferred
        ('null_target', 5, None, False),
        # Target 0 → never inferred (defensive)
        ('zero_target', 5, 0, False),
        # Hit target → not near-failure
        ('hit_target', 10, 10, False),
        # Just below threshold: 10 × 0.85 = 8.5 → 9 reps NOT inferred
        ('just_above_threshold', 9, 10, False),
        # At threshold: 8 < 8.5 → inferred (False boundary side: 8 not < 8.5? wait — 8 < 8.5 → True)
        ('at_threshold_below', 8, 10, True),
        # Far below — clearly near-failure
        ('far_below', 4, 10, True),
        # Exactly meets threshold-product boundary: 8.5 not <, but reps
        # are integer so smallest below-threshold integer is 8.
        ('threshold_int_exact', 8, 10, True),
    ]
    for name, actual, target, expected in spec:
        inferred = sim.inferred_near_failure(actual, target)
        cases.append({
            'name': name,
            'actual_reps': actual,
            'target_reps': target,
            'near_failure_inferred': inferred,
            'expected': expected,
        })
    return cases


def fx_set_xp_v2() -> list[dict]:
    """Phase 29 v2 end-to-end fixture (94 rows).

    Each case carries every input the new 11-multiplier chain consumes,
    plus the expected per-component breakdown + per-body-part awarded
    XP. Built by calling `sim.compute_set_xp` directly so the Dart
    calculator's parity test can replay against authoritative oracle
    values.

    Layout: feed a small panel of personas through a panel of exercises,
    varying rep schemes, weekly volume, novelty, near-failure flagging,
    and gender to hit every multiplier path.
    """
    cases = []
    # Persona presets — bodyweight, gender, schedule that drive the chain.
    personas = [
        # name, bw_kg, female, current_ranks_avg
        ('beginner', 75.0, False, 1),
        ('diego', 80.0, False, 12),
        ('elite', 95.0, False, 50),
        ('female_int', 60.0, True, 15),
        ('untrained_youth', 65.0, False, 1),
    ]
    # Exercise scenarios per persona — exercise alias, weight, reps,
    # session_vol_prior (chest), weekly_vol_prior (chest), near_failure,
    # target_reps, with_prior_overload (bool), bp_session_count_for_chest.
    scenarios = [
        ('bench', 80, 5, 0, 0, False, None, False, 1),
        ('bench', 80, 5, 8, 10, False, None, True, 2),
        ('bench', 100, 3, 0, 0, True, None, False, 1),
        ('bench', 60, 12, 5, 14, False, None, False, 3),
        ('bench', 70, 8, 0, 16, False, None, False, 1),  # past weekly cap
        ('squat', 100, 5, 0, 0, False, None, False, 1),
        ('squat', 80, 10, 4, 8, False, None, True, 2),
        ('squat', 140, 1, 0, 0, True, None, False, 1),
        ('deadlift', 140, 3, 0, 0, False, None, False, 1),
        ('deadlift', 100, 8, 6, 10, False, None, True, 2),
        ('overhead_press', 50, 5, 0, 0, False, None, False, 1),
        ('overhead_press', 40, 10, 3, 6, False, None, False, 2),
        ('row', 70, 5, 0, 0, False, None, False, 1),
        ('row', 60, 10, 5, 8, False, None, True, 2),
        ('pullup', 0, 8, 0, 0, False, None, False, 1),  # pure bodyweight load
        ('pullup', 10, 5, 4, 6, False, None, True, 1),  # weighted dip pattern
        ('curl', 20, 12, 0, 0, False, None, False, 1),  # isolation
        ('tricep_pushdown', 30, 12, 5, 8, False, None, False, 2),
        ('lateral_raise', 10, 15, 2, 4, False, None, False, 1),
    ]
    # Per-persona rep_band PR seed — anchors at a known weight so the
    # overload_mult path triggers deterministically when `with_prior_overload`
    # is True.
    for persona_name, bw, female, rank_avg in personas:
        for s in scenarios[:19]:  # 19 scenarios × 5 personas = 95; trim to 94
            (
                exercise, weight, reps, sv, wv,
                nf, target, with_prior, bp_count,
            ) = s
            from collections import defaultdict
            novelty_count = defaultdict(float)
            weekly_count = defaultdict(float)
            # Seed session + weekly volumes — they're per-body-part dicts but
            # we just need values for the dominant BP to flow through.
            # Use a representative bp; compute_set_xp will pick the dominant
            # one from the attribution map.
            # For chest-leaning exercises seed chest; legs for squats; etc.
            seed_bp = {
                'bench': 'chest', 'overhead_press': 'shoulders',
                'lateral_raise': 'shoulders', 'tricep_pushdown': 'arms',
                'row': 'back', 'pullup': 'back', 'curl': 'arms',
                'squat': 'legs', 'deadlift': 'back',
            }.get(exercise, 'chest')
            novelty_count[seed_bp] = sv
            weekly_count[seed_bp] = wv

            peak_loads = {}
            # Anchor peak so strength_mult isn't always 1.0
            if weight > 0:
                peak_loads[exercise] = max(weight, weight * 1.05)
            current_ranks = {bp: rank_avg for bp in sim.BODY_PARTS}

            best_by_band = {}
            # Capture the PRE-call prior — `sim.compute_set_xp` mutates the
            # dict via the `overload_mult` helper, so reading
            # `best_by_band` after the call would give the post-update
            # value (the current weight/reps), not the prior we seeded.
            pre_call_prior = None
            if with_prior:
                # Seed a prior PR at the same band 5% below current weight
                # and 1 rep below — guarantees overload_mult kicks to 1.15
                # (weight > prior_weight → new weight PR).
                band = sim.rep_band(reps)
                prior_w = max(0.0, weight - 5)
                prior_r = max(1, reps - 1)
                best_by_band[(exercise, band)] = (prior_w, prior_r)
                pre_call_prior = [
                    [exercise, band],
                    [prior_w, prior_r],
                ]

            bp_session_count = defaultdict(int)
            for bp in sim.BODY_PARTS:
                bp_session_count[bp] = bp_count

            diff_m = sim.difficulty_mult_for_alias(exercise)
            real_slug = sim.SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
            awarded, vol, components, _bbb = sim.compute_set_xp(
                exercise, weight, reps, novelty_count, weekly_count,
                peak_loads, difficulty_mult=diff_m,
                bodyweight_kg=bw, slug=real_slug,
                current_ranks=current_ranks,
                best_by_band=best_by_band,
                bp_session_count=bp_session_count,
                near_failure=nf,
                female=female,
                target_reps=target,
            )

            # Re-compute attribution distribution for the fixture (the
            # awarded dict already has it, but the test wants both the
            # totals and per-bp shares pinned).
            distribution = sim._attribution_for(exercise)
            if not distribution:
                distribution = {'chest': 1.0}

            cases.append({
                'name': f'{persona_name}__{exercise}_{int(weight)}x{reps}'
                        + ('_nf' if nf else '')
                        + ('_prior' if with_prior else '')
                        + f'_wv{int(wv)}',
                'inputs': {
                    'persona': persona_name,
                    'exercise': exercise,
                    'slug': real_slug,
                    'weight_kg': weight,
                    'reps': reps,
                    'peak_load': peak_loads.get(exercise, weight),
                    'session_volume_prior': sv,
                    'weekly_volume_prior': wv,
                    'session_volume_seed_bp': seed_bp,
                    'difficulty_mult': diff_m,
                    'bodyweight_kg': bw,
                    'gender_female': female,
                    'current_ranks': dict(current_ranks),
                    # Pre-call prior — the value seeded INTO best_by_band
                    # before compute_set_xp ran (the helper mutates the
                    # dict, so the post-call value would be wrong as a
                    # parity oracle).
                    'best_by_band_prior': pre_call_prior,
                    'bp_session_count': bp_count,
                    'near_failure': nf,
                    'target_reps': target,
                    'uses_bodyweight_load': sim.uses_bodyweight_load(real_slug),
                    'bodyweight_load_ratio': sim.BODYWEIGHT_LOAD_RATIO.get(
                        real_slug, 1.0
                    ) if sim.uses_bodyweight_load(real_slug) else None,
                    'effective_load': components['eff_weight'],
                    'attribution': distribution,
                    'dominant_part': components['dominant_part'],
                },
                'components': {
                    'volume_load': components['volume_load'],
                    'base_xp': components['base_xp'],
                    'intensity_mult': components['intensity_mult'],
                    'strength_mult': components['strength_mult'],
                    'difficulty_mult': components['difficulty_mult'],
                    'tier_diff_mult': components['tier_diff_mult'],
                    'abs_strength_premium': components['abs_strength_premium'],
                    'overload_mult': components['overload_mult'],
                    'frequency_mult': components['frequency_mult'],
                    'lift_implied_tier': components['lift_implied_tier'],
                    'near_failure_resolved': components['near_failure'],
                    'eff_weight': components['eff_weight'],
                },
                'awarded_per_bp': dict(awarded),
                'set_xp_total': sum(awarded.values()),
            })

    # Trim to exactly 94 cases for fixture stability
    return cases[:94]


# ---------------------------------------------------------------------------
# Backfill replay reference output — neutral chain (legacy archetypes)
# ---------------------------------------------------------------------------

def fx_backfill_replay() -> dict:
    """Replays an intermediate archetype's first ~30 weeks through the legacy
    chain (Phase 24c semantics: bodyweight-as-load + simple BW addition, no
    per-exercise ratio, no Phase 29 multipliers). This path uses the
    Python sim's backward-compat behavior (no current_ranks, no
    best_by_band, no bp_session_count) so all Phase 29 multipliers
    default to 1.0. The Dart calculator's backward-compat path (all new
    optional parameters omitted or null) produces the same numbers.

    Phase 29 v2 note: legacy archetypes simulated this way use simple
    `entered + bodyweight` for bodyweight-load exercises (the Python
    sim's `effective_weight` uses per-slug `BODYWEIGHT_LOAD_RATIO`,
    which for `walking_lunges` is 0.85 — so the replay WILL differ from
    the pre-29 fixture for legs. This is forward-only; the parity
    contract is "Dart Phase 29 v2 chain == sim Phase 29 v2 chain", not
    "Phase 29 v2 == Phase 24d".
    """
    archetype = sim.ARCHETYPES['intermediate']
    weeks = 30
    bodyweight_kg = 75.0

    from collections import defaultdict
    xp_pool = {p: 0.0 for p in sim.BODY_PARTS}
    weights = dict(archetype.starting_weights)
    peak_loads = dict(archetype.starting_weights)
    schedule = sim.WEEK_SCHEDULES[archetype.sessions_per_week]
    set_log: list[dict] = []
    set_index = 0

    for week in range(1, weeks + 1):
        weekly_count: dict[str, float] = defaultdict(float)
        for day in schedule:
            novelty_count: dict[str, float] = defaultdict(float)
            session_set_index = 0
            for exercise, n_sets, reps in sim.DAY_TEMPLATES[day]:
                w = weights.get(exercise, 1)
                diff_mult = sim.difficulty_mult_for_alias(exercise)
                real_slug = sim.SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                uses_bw = sim.uses_bodyweight_load(real_slug)
                eff_weight = sim.effective_weight(real_slug, w, bodyweight_kg)
                for _ in range(n_sets):
                    set_index += 1
                    session_set_index += 1
                    awarded, vol, _comp, _bbb = sim.compute_set_xp(
                        exercise, w, reps, novelty_count, weekly_count,
                        peak_loads,
                        difficulty_mult=diff_mult,
                        bodyweight_kg=bodyweight_kg,
                        slug=real_slug,
                    )
                    for bp, xp in awarded.items():
                        xp_pool[bp] += xp
                    set_log.append({
                        'set_index': set_index,
                        'week': week,
                        'day': day,
                        'session_set_index': session_set_index,
                        'exercise': exercise,
                        'weight_kg': w,
                        'reps': reps,
                        'difficulty_mult': diff_mult,
                        'slug': real_slug,
                        'uses_bodyweight_load': uses_bw,
                        'effective_load': eff_weight,
                        'awarded': dict(awarded),
                    })
        rate = sim.progression_rate(archetype, week)
        for ex in weights:
            weights[ex] *= rate

    final_ranks = {p: sim.rank_for_xp(xp_pool[p]) for p in sim.BODY_PARTS}
    return {
        'archetype': 'intermediate',
        'weeks_simulated': weeks,
        'bodyweight_kg': bodyweight_kg,
        'total_sets': set_index,
        'final_xp_pool': xp_pool,
        'final_ranks': final_ranks,
    }


# ---------------------------------------------------------------------------
# Phase 38c — cardio oracle builders (csim)
# ---------------------------------------------------------------------------

def fx_cardio_session_xp() -> list[dict]:
    """End-to-end cardio session XP (the 14-persona oracle + edge rows).

    Each row carries the full input tuple compute_session_xp consumes and the
    RAW UNROUNDED outputs (xp, met_minutes, rel_intensity). Driven from the 14
    personas' week-1 first-session state (rank=1, fresh weekly cap) plus edge
    rows: walk-when-fit (~0), metcon, over-cap split.
    """
    cases: list[dict] = []

    def row(name, vo2max, age, female, modality, dur, kind, value,
            current_rank, week_used):
        state = {'used': week_used}
        xp, met_min, rel = csim.compute_session_xp(
            vo2max, age, female, modality, dur, kind, value,
            current_rank, state)
        cases.append({
            'name': name,
            'inputs': {
                'vo2max': vo2max, 'age': age, 'female': female,
                'modality': modality, 'duration_min': dur,
                'kind': kind, 'value': value,
                'current_rank': current_rank, 'week_used': week_used,
            },
            'xp': xp,
            'met_minutes': met_min,
            'rel_intensity': rel,
            'week_used_after': state['used'],
        })

    # The 14 personas, week-1 first session (rank=1, cap fresh).
    for key, p in csim.PERSONAS.items():
        modality, dur, kind, value = p.sessions[0]
        row(f'persona__{key}', p.vo2_start, p.age, p.female,
            modality, dur, kind, value, 1, 0.0)

    # Edge: reformed walker's walk (fit + walks) -> ~0 reward.
    row('edge__walk_when_fit', 54.0, 40, False, 'walk', 45, 'abs', 3.8, 1, 0.0)
    # Edge: metcon (crossfitter literal 8.0 MET).
    row('edge__metcon', 44.0, 29, False, 'circuit', 28, 'abs', 8.0, 1, 0.0)
    # Edge: over-cap split — start with the week nearly capped so the
    # eff_met_min straddles WEEKLY_CARDIO_CAP_METMIN (the OVER_CAP_MULT path).
    row('edge__over_cap_split', 52.0, 32, False, 'run', 60, 'rel', 0.88,
        20, csim.WEEKLY_CARDIO_CAP_METMIN - 200.0)
    # Edge: high tier vs high rank (Diego-equivalent cardio) — tier_diff floor.
    row('edge__fit_high_rank', 64.0, 27, False, 'run', 40, 'rel', 0.95, 45, 0.0)

    return cases


def fx_cardio_cross_week() -> dict:
    """Cross-SAVE weekly-cap accumulation (finding [2], Phase 38c reviewer).

    The WEEKLY_CARDIO_CAP_METMIN accumulator carries ACROSS saves within an ISO
    week, NOT reset per save. This drives a sequence of same-week sessions where
    each session's `week_used` is the PRIOR session's `week_used_after`, exactly
    as the SQL `record_cardio_session` seeds v_week_used from prior cardio
    eff_met_min this week. The later sessions are cap-attenuated (OVER_CAP_MULT
    path) once the running total passes the cap — the SQL must reproduce this
    sequence, not treat each save as a fresh week.

    `sessions` is an ordered list; replaying them with a single carried
    `week_used` must reproduce each row's `xp` / `week_used_after`.
    """
    sessions: list[dict] = []
    # Four big same-week run sessions: ~1000 eff_met_min each so by session 3 the
    # running total crosses WEEKLY_CARDIO_CAP_METMIN (2500) and the over-portion
    # is attenuated. vo2max/age/female/rank fixed so the ONLY moving part is the
    # carried cap.
    vo2max, age, female, modality, dur, kind, value, rank = (
        52.0, 32, False, 'run', 60, 'rel', 0.88, 10)
    state = {'used': 0.0}
    for i in range(4):
        used_before = state['used']
        xp, met_min, rel = csim.compute_session_xp(
            vo2max, age, female, modality, dur, kind, value, rank, state)
        sessions.append({
            'name': f'session_{i + 1}',
            'inputs': {
                'vo2max': vo2max, 'age': age, 'female': female,
                'modality': modality, 'duration_min': dur,
                'kind': kind, 'value': value, 'current_rank': rank,
            },
            'week_used_before': used_before,
            'xp': xp,
            'met_minutes': met_min,
            'rel_intensity': rel,
            'week_used_after': state['used'],
        })
    return {
        'weekly_cap_metmin': csim.WEEKLY_CARDIO_CAP_METMIN,
        'sessions': sessions,
    }


def fx_cardio_vitality_gate() -> list[dict]:
    """Phase 38f — cardio Vitality XP-gate oracle.

    The gate scales the FINAL session XP by
        vmult = VITALITY_XP_FLOOR + (1 - VITALITY_XP_FLOOR) × vpct
        vpct  = clamp(ewma / peak, 0, 1)   (peak <= 0 -> 1.0)
    exactly as the sim's caller-side `xp *= vmult` (cardio-xp-simulation.py:526)
    and the SQL `record_cardio_session` gate (migration 00081).

    Each row carries the cardio conditioning (ewma/peak) that produces vpct, the
    derived vmult, and BOTH the ungated session XP (`xp_ungated`) and the gated
    session XP (`xp_gated = xp_ungated × vmult`). The Dart `CardioXpCalculator`
    parity test replays each row through `vitalityPct` / `vitalityXpMult` and
    `computeSessionXp(vitalityMult: ...)` to pin the gate end-to-end.

    Cases span: fully-lapsed (vpct 0 -> floor 0.40), partial conditioning
    (vpct 0.5 / 0.75), fully-conditioned (vpct 1.0 -> full XP), and the
    fresh-user no-history case (peak 0 -> vpct 1.0 -> full XP, gate is a no-op).
    """
    cases: list[dict] = []
    # Fixed session shape so the ONLY moving part is the conditioning -> vmult.
    vo2max, age, female, modality, dur, kind, value, rank = (
        52.0, 32, False, 'run', 45, 'rel', 0.85, 10)

    def row(name, ewma, peak):
        state = {'used': 0.0}
        xp_ungated, met_min, rel = csim.compute_session_xp(
            vo2max, age, female, modality, dur, kind, value, rank, state)
        vpct = csim.vitality_pct(ewma, peak)
        vmult = csim.vitality_xp_mult(vpct)
        cases.append({
            'name': name,
            'inputs': {
                'vo2max': vo2max, 'age': age, 'female': female,
                'modality': modality, 'duration_min': dur,
                'kind': kind, 'value': value, 'current_rank': rank,
                'vitality_ewma': ewma, 'vitality_peak': peak,
            },
            'vpct': vpct,
            'vitality_mult': vmult,
            'xp_ungated': xp_ungated,
            'xp_gated': xp_ungated * vmult,
        })

    # Fully-lapsed: ewma 0 against a real peak -> vpct 0 -> vmult = FLOOR (0.40).
    row('fully_lapsed', 0.0, 1000.0)
    # Partial conditioning: vpct 0.5 -> vmult = 0.40 + 0.60×0.5 = 0.70.
    row('half_conditioned', 500.0, 1000.0)
    # Three-quarters: vpct 0.75 -> vmult = 0.85.
    row('three_quarter_conditioned', 750.0, 1000.0)
    # Fully conditioned: ewma == peak -> vpct 1.0 -> vmult 1.0 (full XP).
    row('fully_conditioned', 1000.0, 1000.0)
    # Fresh user / no history: peak 0 -> vpct 1.0 -> vmult 1.0 (gate no-op).
    row('fresh_no_history', 0.0, 0.0)
    # ewma above peak (defensive — should never happen, but clamps to 1.0).
    row('ewma_above_peak_clamps', 1200.0, 1000.0)
    return cases


def fx_cardio_components() -> dict:
    """Component lists mirroring the strength fixture style — pins each pure
    sub-function Dart must replay @1e-4."""
    intensity_mult = []
    for pct in [0.30, 0.35, 0.42, 0.50, 0.60, 0.70, 0.80, 0.85, 0.90,
                0.95, 1.00, 1.05, 1.20]:
        intensity_mult.append({'pct_vo2max': pct,
                               'intensity_mult': csim.intensity_mult(pct)})

    sustainable_fraction = []
    for dur in [6, 10, 15, 22, 30, 38, 45, 52, 60, 75, 90, 105, 120, 150, 180]:
        sustainable_fraction.append(
            {'duration_min': dur,
             'sustainable_fraction': csim.sustainable_fraction(dur)})

    demonstrated_vo2 = []
    for abs_met, dur in [(3.8, 45), (8.0, 28), (10.0, 30), (12.0, 35),
                         (15.0, 40), (6.0, 60), (3.0, 90)]:
        demonstrated_vo2.append({'abs_met': abs_met, 'duration_min': dur,
                                'demonstrated_vo2':
                                    csim.demonstrated_vo2(abs_met, dur)})

    implied_cardio_tier = []
    for vo2, age, female in [(28, 30, False), (40, 30, False), (52, 30, False),
                             (64, 30, False), (38, 55, False), (30, 30, True),
                             (44, 28, True)]:
        implied_cardio_tier.append(
            {'vo2': vo2, 'age': age, 'female': female,
             'implied_cardio_tier': csim.implied_cardio_tier(vo2, age, female)})

    modality_mult = []
    for mod in ['run', 'treadmill', 'row', 'swim', 'elliptical', 'bike',
                'walk', 'hiit', 'strength', 'circuit']:
        modality_mult.append({'modality': mod,
                             'modality_mult': csim.MODALITY_MULT[mod]})

    cardio_base_xp = []
    for met_min in [50.0, 100.0, 200.0, 294.0, 500.0, 1000.0, 2500.0]:
        cardio_base_xp.append(
            {'capped_met_min': met_min,
             'base_xp': met_min ** csim.VOLUME_EXPONENT})

    cardio_weekly_cap = []
    for eff, used in [(500.0, 0.0), (2500.0, 0.0), (3000.0, 0.0),
                      (1000.0, 2000.0), (500.0, 2400.0), (1000.0, 2400.0)]:
        remaining = max(0.0, csim.WEEKLY_CARDIO_CAP_METMIN - used)
        under = min(eff, remaining)
        over = eff - under
        capped = under + over * csim.OVER_CAP_MULT
        cardio_weekly_cap.append({
            'eff_met_min': eff, 'week_used': used,
            'capped_met_min': capped,
        })

    return {
        'intensity_mult': intensity_mult,
        'sustainable_fraction': sustainable_fraction,
        'demonstrated_vo2': demonstrated_vo2,
        'implied_cardio_tier': implied_cardio_tier,
        'modality_mult': modality_mult,
        'cardio_base_xp': cardio_base_xp,
        'cardio_weekly_cap': cardio_weekly_cap,
    }


def fx_est_vo2max_cases() -> dict:
    """Stateless est-VO2max pure cores: A1 best-effort (ACSM + sustainable_
    fraction) + A3 p25 non-exercise seed. Rolling-window/recompute is Dart+SQL
    unit/integration territory (stateful), NOT here."""
    best_effort = []
    for dist, dur_s, mod in [
        (5000, 1800, 'run'),       # 30-min 5k -> ~41.9 (the worked example)
        (10000, 3000, 'treadmill'),  # 50-min 10k
        (3000, 900, 'run'),        # fast 5:00/km-ish over 15 min
        (5000, 1800, 'bike'),      # non-distance modality -> None
        (None, 1800, 'run'),       # duration-only -> None
        (0, 1800, 'run'),          # zero distance -> None
    ]:
        best_effort.append({
            'distance_m': dist, 'duration_s': dur_s, 'modality': mod,
            'best_effort_vo2': csim.best_effort_vo2_from_pace(dist, dur_s, mod),
        })

    seed = []
    for age, female in [(20, False), (30, False), (45, False), (55, False),
                        (30, True), (45, True), (None, False), (None, True)]:
        seed.append({'age': age, 'female': female,
                     'seed_vo2': csim.nonexercise_seed_vo2(age, female)})

    session_met = []
    for mod, dist, dur_s in [
        ('run', 5000, 1800), ('treadmill', 10000, 3000),
        ('bike', None, 1800), ('row', None, 1500),
        ('elliptical', 5000, 1800), ('walk', None, 2700),
        ('hiit', None, 1320),
    ]:
        session_met.append({
            'modality': mod, 'distance_m': dist, 'duration_s': dur_s,
            'session_met': csim.session_met_from_cardio_log(mod, dist, dur_s),
        })

    return {
        'best_effort': best_effort,
        'seed': seed,
        'session_met': session_met,
    }


def fx_cross_credit_met_bands() -> list[dict]:
    """§B work-density -> MET band derivation. The two worked examples + each
    band boundary (~8 rows)."""
    cases: list[dict] = []
    spec = [
        # name, completed_sets, session_seconds, avg_rest, expected_band
        ('powerlifter_worked', 20, 4200, 180, 3.5),   # §B worked example
        ('metcon_worked', 15, 1680, 30, 8.0),         # §B corrected worked example
        ('band_8_boundary', 15, 1680, 35, 8.0),       # avg_rest==35 -> 8.0
        ('band_6_avg_rest_36', 15, 1680, 36, 6.0),    # rest just over 35 -> 6.0
        ('band_6_boundary', 14, 1680, 75, 6.0),       # sets/min 0.50, rest 75
        ('band_5_avg_rest_76', 14, 1680, 76, 5.0),    # rest just over 75 -> 5.0
        ('band_5_boundary', 8, 2400, 120, 5.0),       # rest 120 -> 5.0
        ('band_3_5_long_rest', 8, 2400, 121, 3.5),    # rest > 120 -> 3.5
    ]
    for name, sets, secs, rest, expected in spec:
        band = csim.est_met_from_density(sets, secs, rest)
        cases.append({
            'name': name,
            'completed_sets': sets,
            'session_seconds': secs,
            'avg_rest': rest,
            'est_met': band,
            'expected': expected,
        })
    return cases


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    fixtures = {
        'meta': {
            'phase': 'phase29_v2',
            'volume_exponent': sim.VOLUME_EXPONENT,
            'novelty_denominator': sim.NOVELTY_DENOMINATOR,
            'weekly_cap_sets': sim.WEEKLY_CAP_SETS,
            'over_cap_multiplier': sim.OVER_CAP_MULTIPLIER,
            'strength_mult_floor': sim.STRENGTH_MULT_FLOOR,
            'difficulty_mult_floor': sim.DIFFICULTY_MULT_FLOOR,
            'difficulty_mult_ceiling': sim.DIFFICULTY_MULT_CEILING,
            'xp_base': sim.XP_BASE,
            # Phase 29 v2: piecewise rank curve. `xp_growth` is the legacy
            # alias preserved for the existing Dart test that pins it; the
            # explicit Phase 29 v2 key is `xp_growth_band1`.
            'xp_growth': sim.XP_GROWTH,
            'xp_growth_band1': sim.XP_GROWTH_BAND1,
            'rank_curve_breakpoint': sim.RANK_CURVE_BREAKPOINT,
            'linear_xp_per_rank': sim.LINEAR_XP_PER_RANK,
            # Phase 29.6 Path C
            'e_bonus': sim.E_BONUS,
            'e_floor': sim.E_FLOOR,
            'e_ceil': sim.E_CEIL,
            # Phase 29 v2 Refinement #4
            'nf_intensity_bonus': sim.NF_INTENSITY_BONUS,
            'nf_target_threshold': sim.NF_TARGET_THRESHOLD,
            # Phase 29 v2 Refinement #3
            'frequency_mult_table': list(sim.FREQUENCY_MULT_TABLE),
            # tier_diff_mult parameters
            'tier_diff_offset': sim.TIER_DIFF_OFFSET,
            'tier_diff_exp': sim.TIER_DIFF_EXP,
            'tier_diff_min': sim.TIER_DIFF_MIN,
            'tier_diff_max': sim.TIER_DIFF_MAX,
            'char_level_denominator': sim.CHAR_LEVEL_DENOMINATOR,
            'bodyweight_load_slugs': sorted(sim.USES_BODYWEIGHT_LOAD_BY_SLUG),
            # Phase 29 v2 Refinement #5 — per-slug bodyweight load ratio
            'bodyweight_load_ratios': dict(sim.BODYWEIGHT_LOAD_RATIO),
            # Phase 38c — cardio formula constants (csim).
            'cardio': {
                'met_rest': csim.MET_REST,
                'volume_exponent': csim.VOLUME_EXPONENT,
                'cardio_xp_scale': csim.CARDIO_XP_SCALE,
                'weekly_cardio_cap_metmin': csim.WEEKLY_CARDIO_CAP_METMIN,
                'over_cap_mult': csim.OVER_CAP_MULT,
                'vitality_xp_floor': csim.VITALITY_XP_FLOOR,
                'vitality_tau_up_weeks': csim.VITALITY_TAU_UP_WEEKS,
                'vitality_tau_down_weeks': csim.VITALITY_TAU_DOWN_WEEKS,
                'vo2_ceiling_cap': csim.VO2_CEILING_CAP,
                'set_work_seconds': csim.SET_WORK_SECONDS,
                'rest_default': csim.REST_DEFAULT,
                'age_fallback': csim.AGE_FALLBACK,
                'vo2_rolling_window_days': csim.VO2_ROLLING_WINDOW_DAYS,
                'distance_modalities': sorted(csim.DISTANCE_MODALITIES),
                'cardio_default_met': dict(csim.CARDIO_DEFAULT_MET),
                'cardio_slug_to_modality': dict(csim.CARDIO_SLUG_TO_MODALITY),
                'modality_mult': dict(csim.MODALITY_MULT),
                'intensity_anchors': [list(a) for a in csim.INTENSITY_ANCHORS],
                'sustain_anchors': [list(a) for a in csim._SUSTAIN_ANCHORS],
                'tier_anchors': [list(a) for a in csim._TIER_ANCHORS],
            },
        },
        'intensity_lookup': fx_intensity_lookup(),
        'volume_load': fx_volume_load(),
        'strength_mult': fx_strength_mult(),
        'novelty_mult': fx_novelty_mult(),
        'cap_mult': fx_cap_mult(),
        'set_xp_examples': fx_set_xp_examples(),
        # Phase 29 v2 oracle additions
        'set_xp_v2': fx_set_xp_v2(),
        'implied_tier': fx_implied_tier(),
        'abs_strength_premium': fx_abs_strength_premium(),
        'tier_diff_mult': fx_tier_diff_mult(),
        'overload_mult': fx_overload_mult(),
        'frequency_mult': fx_frequency_mult(),
        'near_failure_inferred': fx_near_failure_inferred(),
        # Legacy lists still load-bearing for Dart parity
        'attribution_distribution': fx_attribution_distribution(),
        'rank_curve': fx_rank_curve(),
        'vitality': fx_vitality(),
        'character_level': fx_character_level(),
        'backfill_replay': fx_backfill_replay(),
        # Phase 38c cardio oracle sections.
        'cardio_session_xp': fx_cardio_session_xp(),
        'cardio_cross_week': fx_cardio_cross_week(),
        'cardio_vitality_gate': fx_cardio_vitality_gate(),
        'cardio_components': fx_cardio_components(),
        'est_vo2max_cases': fx_est_vo2max_cases(),
        'cross_credit_met_bands': fx_cross_credit_met_bands(),
    }
    out = os.path.join(HERE, 'rpg_xp_fixtures.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(fixtures, f, indent=2, sort_keys=True)
    print(f'Wrote {out}')
    print(f'  intensity_lookup:        {len(fixtures["intensity_lookup"])} cases')
    print(f'  volume_load:             {len(fixtures["volume_load"])} cases')
    print(f'  strength_mult:           {len(fixtures["strength_mult"])} cases')
    print(f'  novelty_mult:            {len(fixtures["novelty_mult"])} cases')
    print(f'  cap_mult:                {len(fixtures["cap_mult"])} cases')
    print(f'  set_xp_examples (legacy): {len(fixtures["set_xp_examples"])} cases')
    print(f'  set_xp_v2 (Phase 29 v2): {len(fixtures["set_xp_v2"])} cases')
    print(f'  implied_tier:            {len(fixtures["implied_tier"])} cases')
    print(f'  abs_strength_premium:    {len(fixtures["abs_strength_premium"])} cases')
    print(f'  tier_diff_mult:          {len(fixtures["tier_diff_mult"])} cases')
    print(f'  overload_mult:           {len(fixtures["overload_mult"])} cases')
    print(f'  frequency_mult:          {len(fixtures["frequency_mult"])} cases')
    print(f'  near_failure_inferred:   {len(fixtures["near_failure_inferred"])} cases')
    print(f'  attribution:             {len(fixtures["attribution_distribution"])} exercises')
    print(f'  rank_curve milestones:   {len(fixtures["rank_curve"]["milestones"])}')
    print(f'  vitality trajectory:     {len(fixtures["vitality"]["rebuild_then_decay_trajectory"])} weeks')
    print(f'  backfill_replay:         {fixtures["backfill_replay"]["total_sets"]} sets')
    print(f'  cardio_session_xp:       {len(fixtures["cardio_session_xp"])} cases')
    print(f'  cardio_cross_week:       {len(fixtures["cardio_cross_week"]["sessions"])} sessions')
    print(f'  cardio_vitality_gate:    {len(fixtures["cardio_vitality_gate"])} cases')
    print(f'  cross_credit_met_bands:  {len(fixtures["cross_credit_met_bands"])} cases')


if __name__ == '__main__':
    main()
