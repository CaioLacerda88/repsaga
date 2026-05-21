"""
Generates JSON fixtures from the canonical Python XP simulation for Dart/SQL
parity tests.

Run:   python test/fixtures/generate_rpg_fixtures.py
Output: test/fixtures/rpg_xp_fixtures.json

This file is the SINGLE source of truth for both Python and Dart XP
calculations under Phase 29 v2 + 29.6. PR 2 (Dart + SQL) will gate on a
1e-4 parity match against this fixture.

Generated sections:

  meta                   — locked formula constants for cross-platform asserts
  intensity_lookup       — reps → intensity_mult table (with NF bonus cases)
  volume_load            — weight × reps → volume_load + base_xp
  strength_mult          — current/peak clamp behavior
  novelty_mult           — session_volume → exp decay
  cap_mult               — weekly_volume → 1.0 / 0.3 step
  difficulty_mult_lookup — slug → composite multiplier
  bodyweight_load_ratio  — slug → ratio (Phase 29 v2 Ref #5)
  implied_tier           — gender-aware per-lift tier interpolation
  abs_strength_premium   — Phase 29.6 Path C premium curve
  tier_diff_mult         — Pokemon Gen 5 mult table
  overload_mult          — in-band PR reward table
  frequency_mult         — 7d-window session-count table
  rank_curve             — Refinement #6 piecewise XP cumulative
  vitality               — EWMA trajectory
  character_level        — Σ ranks → char level
  set_xp_v2              — Phase 29 v2 + 29.6 ORACLE matrix (PR 2 1e-4 gate)
  attribution            — exercise → body-part split
  legacy_archetype_replay — Phase 24c parity (preserved)
"""

from __future__ import annotations

import json
import math
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SIM_PATH = os.path.join(ROOT, 'tasks', 'rpg-xp-simulation.py')


def _load_sim():
    import importlib.util
    spec = importlib.util.spec_from_file_location('rpg_sim', SIM_PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules['rpg_sim'] = mod
    spec.loader.exec_module(mod)
    return mod


sim = _load_sim()


# ---------------------------------------------------------------------------
# Primitive lookup tables
# ---------------------------------------------------------------------------

def fx_intensity_lookup():
    cases = []
    for reps in [1, 2, 3, 4, 5, 7, 8, 10, 12, 13, 15, 16, 20, 25]:
        cases.append({'reps': reps,
                      'intensity_mult': sim.intensity_for_reps(reps),
                      'intensity_with_nf': sim.intensity_with_near_failure(reps, True)})
    return cases


def fx_volume_load():
    cases = []
    for w, r in [(0, 8), (1, 1), (5, 5), (20, 8), (60, 5), (100, 8), (140, 3), (200, 1)]:
        vl = max(sim.VOLUME_LOAD_FLOOR, w * r)
        base = vl ** sim.VOLUME_EXPONENT
        cases.append({
            'weight_kg': w, 'reps': r,
            'volume_load': vl, 'base_xp': base,
        })
    return cases


def fx_strength_mult():
    cases = []
    for weight, peak in [(100, 100), (110, 100), (70, 100), (50, 100),
                         (30, 100), (10, 100), (50, 0)]:
        if peak <= 0:
            mult = 1.0
        else:
            mult = max(sim.STRENGTH_MULT_FLOOR, min(1.0, weight / peak))
        cases.append({'weight_kg': weight, 'peak_load': peak, 'strength_mult': mult})
    return cases


def fx_novelty_mult():
    cases = []
    for sv in [0, 1, 5, 10, 15, 20, 30, 50]:
        cases.append({'session_volume_for_body_part': sv,
                      'novelty_mult': math.exp(-sv / sim.NOVELTY_DENOMINATOR)})
    return cases


def fx_cap_mult():
    cases = []
    for wv in [0, 10, 14.99, 15, 15.01, 20, 30]:
        cm = sim.OVER_CAP_MULTIPLIER if wv >= sim.WEEKLY_CAP_SETS else 1.0
        cases.append({'weekly_volume_for_body_part': wv, 'cap_mult': cm})
    return cases


def fx_difficulty_mult_lookup():
    """Subset of the canonical DIFFICULTY_MULT_BY_SLUG table — includes the
    slugs hit by the v2 fixture matrix + the floor/ceiling literals."""
    slugs = sorted({
        'barbell_bench_press', 'barbell_squat', 'deadlift', 'overhead_press',
        'barbell_bent_over_row', 'lat_pulldown', 'pull_up', 'barbell_curl',
        'tricep_pushdown', 'lateral_raise', 'leg_press', 'walking_lunges',
        'plank', 'leg_raise', 'machine_chest_press', 'seated_row',
        'leg_extension', 'leg_curl', 'romanian_deadlift', 'push_press',
        'push_up', 'pistol_squat', 'incline_barbell_bench_press',
    })
    out = []
    for s in slugs:
        out.append({'slug': s, 'difficulty_mult': sim.difficulty_mult_for_slug(s)})
    out.append({'slug': '_floor_explicit', 'difficulty_mult': sim.DIFFICULTY_MULT_FLOOR})
    out.append({'slug': '_ceiling_explicit', 'difficulty_mult': sim.DIFFICULTY_MULT_CEILING})
    out.append({'slug': '_unmapped_default', 'difficulty_mult': sim.difficulty_mult_for_slug('not_a_real_slug')})
    return out


def fx_bodyweight_load_ratio():
    """Phase 29 v2 Ref #5 — per-exercise BW load fraction."""
    return [{'slug': slug, 'ratio': ratio}
            for slug, ratio in sorted(sim.BODYWEIGHT_LOAD_RATIO.items())]


# ---------------------------------------------------------------------------
# Phase 29 v2 + 29.6 mid-level helpers
# ---------------------------------------------------------------------------

def fx_implied_tier():
    """Gender-aware per-lift implied tier oracle.

    PR 2's `lib/features/rpg/domain/implied_tier.dart` must match these
    interpolated values to 1e-4.
    """
    cases = []
    scenarios = [
        # (exercise, weight, reps, bodyweight, female, label)
        ('bench', 100, 5, 80, False, 'M bench 100x5 @80kg'),
        ('bench', 180, 3, 95, False, 'M bench 180x3 @95kg (Elite Path C)'),
        ('squat', 140, 5, 80, False, 'M squat 140x5 @80kg'),
        ('deadlift', 200, 5, 80, False, 'M deadlift 200x5 @80kg'),
        ('overhead_press', 60, 5, 80, False, 'M ohp 60x5 @80kg'),
        ('row', 90, 8, 80, False, 'M row 90x8 @80kg'),
        ('curl', 20, 12, 80, False, 'M curl 20x12 @80kg'),
        ('leg_press', 200, 10, 80, False, 'M leg_press 200x10 @80kg (discount 0.65)'),
        ('incline_bench', 80, 5, 80, False, 'M incline 80x5 @80kg (discount 0.90)'),
        ('bench', 45, 8, 60, True, 'F bench 45x8 @60kg'),
        ('squat', 70, 8, 60, True, 'F squat 70x8 @60kg'),
        ('deadlift', 85, 6, 60, True, 'F deadlift 85x6 @60kg'),
        ('overhead_press', 30, 8, 60, True, 'F ohp 30x8 @60kg'),
        ('row', 40, 8, 60, True, 'F row 40x8 @60kg'),
        ('curl', 10, 12, 60, True, 'F curl 10x12 @60kg'),
        ('bench', 0, 5, 80, False, 'M zero-weight (clamps to floor)'),
        ('bench', 300, 1, 80, False, 'M huge-weight (clamps to ceiling)'),
    ]
    for exercise, w, r, bw, f, label in scenarios:
        tier = sim.implied_tier(exercise, w, r, bw, female=f)
        cases.append({
            'label': label,
            'exercise': exercise, 'weight_kg': w, 'reps': r,
            'bodyweight_kg': bw, 'female': f,
            'implied_tier': tier,
        })
    return cases


def fx_abs_strength_premium():
    """Phase 29.6 Path C — abs_strength_premium curve."""
    cases = []
    for tier in [0, 15, 25, 30, 35, 40, 45, 50, 55, 60, 65, 75]:
        frac = sim.abs_strength_premium_frac(tier)
        prem = sim.abs_strength_premium(tier)
        cases.append({
            'lift_implied_tier': tier,
            'frac': frac,
            'abs_strength_premium': prem,
        })
    return cases


def fx_tier_diff_mult():
    """Pokemon Gen 5 adaptation — implied tier vs current rank."""
    cases = []
    for implied, rank in [
        (1, 1), (5, 1), (10, 1), (15, 5), (20, 10), (25, 15),
        (28, 1), (30, 5), (35, 25), (45, 35), (45, 1), (55, 1),
        (5, 15), (5, 25), (5, 35), (5, 45), (0, 1),
    ]:
        cases.append({
            'lift_implied_tier': implied,
            'current_rank': rank,
            'tier_diff_mult': sim.tier_diff_mult(rank, implied),
        })
    return cases


def fx_overload_mult():
    """Ref #2 — in-band PR reward."""
    cases = []
    scenarios = [
        # (exercise, weight, reps, prior_best, expected_mult, label)
        ('bench', 100, 5, None, 1.0, 'no prior → 1.00'),
        ('bench', 100, 5, (100, 5), 1.0, 'tie weight tie reps → 1.00'),
        ('bench', 105, 5, (100, 5), 1.15, 'weight up → 1.15'),
        ('bench', 100, 6, (100, 5), 1.10, 'reps up at same weight → 1.10'),
        ('bench', 95, 6, (100, 5), 1.05, 'reps up but weight down → 1.05'),
        ('bench', 100, 4, (100, 5), 1.0, 'weight tie + reps down → no overload'),
        # Cross-band: band hop is treated as no prior (different band's PR row)
        ('bench', 100, 3, (100, 8), 1.0, 'cross-band (no prior in heavy band) → 1.00'),
    ]
    for exercise, w, r, prior, expected, label in scenarios:
        bbb = {}
        if prior is not None:
            bbb[(exercise, sim.rep_band(prior[1]))] = prior
        mult, _ = sim.overload_mult(exercise, w, r, bbb)
        cases.append({
            'label': label,
            'exercise': exercise, 'weight_kg': w, 'reps': r,
            'prior_best_in_band': list(prior) if prior else None,
            'rep_band': sim.rep_band(r),
            'overload_mult': mult,
            'expected_mult': expected,
        })
    return cases


def fx_frequency_mult():
    """Ref #3 — 7d-window session-count → multiplier."""
    cases = []
    for count in [1, 2, 3, 4, 5, 6, 10]:
        cases.append({'session_count': count, 'frequency_mult': sim.frequency_mult(count)})
    return cases


def fx_near_failure_inference():
    """Ref #4 — target_reps × NF_TARGET_THRESHOLD threshold."""
    cases = []
    for actual, target in [
        (8, 8),    # at target → not NF
        (7, 8),    # one under (87.5%) → not NF (just above 0.85 threshold)
        (6, 8),    # 75% → NF
        (5, 8),    # well under → NF
        (12, 10),  # over target → not NF
        (8, None), # no target → not NF
        (8, 0),    # zero target → not NF
    ]:
        cases.append({
            'actual_reps': actual,
            'target_reps': target,
            'near_failure': sim.inferred_near_failure(actual, target),
        })
    return cases


def fx_rank_curve():
    """Refinement #6 piecewise: geometric ranks 1-20, linear 21+."""
    cumulative = {}
    for n in range(1, 100):
        cumulative[str(n)] = sim.xp_for_rank(n)
    lookups = []
    for total in [0, 59, 60, 277, 278, 813, 814, 3068, 3069, 8916, 8917,
                  63430, 63431, 100000, 200000, 500000, 1000000]:
        lookups.append({'total_xp': total, 'rank': sim.rank_for_xp(total)})
    milestones = []
    for n in [1, 2, 5, 10, 15, 20, 21, 30, 50, 65, 80, 99]:
        milestones.append({'rank': n, 'cumulative_xp': sim.xp_for_rank(n)})
    return {
        'cumulative': cumulative,
        'lookups': lookups,
        'milestones': milestones,
        'breakpoint': sim.RANK_CURVE_BREAKPOINT,
        'linear_xp_per_rank': sim.LINEAR_XP_PER_RANK,
    }


def fx_vitality():
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
            'week': week, 'weekly_volume': wv,
            'ewma': ewma, 'peak': peak,
            'pct': (ewma / peak) if peak > 0 else 0.0,
        })
    return {
        'alpha_up': alpha_up,
        'alpha_down': alpha_down,
        'tau_up_weeks': sim.VITALITY_TAU_UP_WEEKS,
        'tau_down_weeks': sim.VITALITY_TAU_DOWN_WEEKS,
        'rebuild_then_decay_trajectory': trajectory,
    }


def fx_character_level():
    cases = []
    scenarios = [
        ({'chest': 1, 'back': 1, 'legs': 1, 'shoulders': 1, 'arms': 1, 'core': 1}, 1),
        ({'chest': 5, 'back': 5, 'legs': 5, 'shoulders': 5, 'arms': 5, 'core': 5}, 7),
        ({'chest': 20, 'back': 20, 'legs': 20, 'shoulders': 20, 'arms': 20, 'core': 20}, 29),
        ({'chest': 50, 'back': 50, 'legs': 50, 'shoulders': 50, 'arms': 50, 'core': 50}, 74),
        ({'chest': 99, 'back': 99, 'legs': 99, 'shoulders': 99, 'arms': 99, 'core': 99}, 148),
    ]
    for ranks, expected in scenarios:
        cases.append({'ranks': ranks, 'character_level': expected,
                      'computed': sim.character_level(ranks)})
    return cases


# ---------------------------------------------------------------------------
# PR 2 ORACLE — set_xp_v2 matrix (Phase 29 v2 + 29.6)
# ---------------------------------------------------------------------------

def _compute_oracle_set_xp(scenario):
    """Run a single fixture row through the locked sim and capture the full
    11-multiplier chain. Returns the per-bp award + every intermediate value
    so PR 2's Dart + SQL can pin every step of the math.
    """
    exercise = scenario['exercise']
    weight = scenario['weight_kg']
    reps = scenario['reps']
    bodyweight = scenario['bodyweight_kg']
    female = scenario['female']
    slug = scenario.get('slug') or sim.SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
    difficulty_mult = scenario.get('difficulty_mult')
    if difficulty_mult is None:
        difficulty_mult = sim.difficulty_mult_for_slug(slug)

    # Per-set state carried by the scenario (deterministic — no rng)
    novelty_count = defaultdict(float, scenario.get('novelty_count', {}))
    weekly_count = defaultdict(float, scenario.get('weekly_count', {}))
    peak_loads = {exercise: scenario.get('peak_load', weight)}
    current_ranks = scenario.get('current_ranks', {})
    bp_session_count = scenario.get('bp_session_count', {})
    best_by_band = {}
    prior = scenario.get('prior_best_in_band')
    if prior:
        best_by_band[(exercise, sim.rep_band(prior[1]))] = tuple(prior)
    near_failure_flag = scenario.get('near_failure', False)
    target_reps = scenario.get('target_reps')

    awarded, vol, components, _ = sim.compute_set_xp(
        exercise, weight, reps,
        novelty_count, weekly_count, peak_loads,
        difficulty_mult=difficulty_mult,
        bodyweight_kg=bodyweight,
        slug=slug,
        current_ranks=current_ranks,
        best_by_band=best_by_band,
        bp_session_count=bp_session_count,
        near_failure=near_failure_flag,
        female=female,
        target_reps=target_reps,
    )
    set_xp_total = sum(awarded.values())
    return awarded, set_xp_total, vol, components


def _persona_session_scenarios():
    """Produce a matrix of (persona × session_index × variation) fixture rows.

    For each of the 13 personas we generate scenarios approximating their
    session 1, session 6, session 12 state — peak loads, weekly counts, and
    current ranks are sampled from a deterministic forward simulation rather
    than picked by hand, so the oracle reflects what compute_set_xp() actually
    sees in production replay.
    """
    scenarios = []

    # Drive each persona forward and snapshot state at the requested sessions
    for persona_key, persona in sim.PERSONAS.items():
        # Replay the persona's simulation manually so we can capture state
        # at each session boundary. Mirror simulate_persona's per-set loop
        # but pause to emit fixture rows at sessions 1, 6, 12.
        capture_sessions = {1, 6, 12}

        xp_pool = {p: 0.0 for p in sim.BODY_PARTS}
        weights = dict(persona.starting_weights)
        peak_loads = dict(persona.starting_weights)
        best_by_band = {}
        schedule = sim.WEEK_SCHEDULES_PANEL[persona.schedule_key]
        reps_scheme = persona.reps_scheme or sim.DEFAULT_REPS_PANEL
        session_num = 0
        smurf_done = False

        # Track per-week state so weekly_count + bp_session match what
        # compute_set_xp would see.
        weeks_done = 0
        weekly_count = defaultdict(float)
        bp_session = defaultdict(int)

        weeks_to_walk = 4  # session 12 happens at week ~3 for 3×/wk personas

        for week in range(1, weeks_to_walk + 1):
            weeks_done += 1
            weekly_count = defaultdict(float)
            bp_session = defaultdict(int)
            prog = (
                sim._tapered_progression(persona.progression_pct, persona.half_life_weeks, week)
                if persona.tapering else persona.progression_pct
            )
            for day in schedule:
                session_num += 1
                for bp in sim.SESSION_BODY_PARTS.get(day, set()):
                    bp_session[bp] += 1
                novelty_count = defaultdict(float)

                # If this is a capture session, emit a fixture row using the
                # FIRST exercise of the day (representative) before consuming
                # the session for state advancement.
                capture_now = session_num in capture_sessions

                for ex_idx, (exercise, n_sets) in enumerate(sim.DAY_TEMPLATES_PANEL[day]):
                    r = reps_scheme.get(exercise, sim.DEFAULT_REPS_PANEL.get(exercise, 5))
                    diff_m = sim.difficulty_mult_for_alias(exercise)
                    real_slug = sim.SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)

                    if capture_now and ex_idx == 0:
                        # Emit a fixture row reflecting the CURRENT state.
                        # Use the first set of this exercise as the captured set.
                        cr = {p: sim.rank_for_xp(xp_pool[p]) for p in sim.BODY_PARTS}
                        w = weights.get(exercise, 1.0)
                        # Build a deep copy of state so capture is non-destructive
                        prior_in_band = best_by_band.get((exercise, sim.rep_band(r)))
                        scenarios.append({
                            'name': f'{persona_key}_session{session_num}',
                            'persona_key': persona_key,
                            'session_index': session_num,
                            'exercise': exercise,
                            'slug': real_slug,
                            'weight_kg': round(w, 4),
                            'reps': r,
                            'bodyweight_kg': persona.bodyweight_kg,
                            'female': persona.female,
                            'difficulty_mult': diff_m,
                            'peak_load': peak_loads.get(exercise, w),
                            'novelty_count': {},
                            'weekly_count': dict(weekly_count),
                            'current_ranks': cr,
                            'bp_session_count': dict(bp_session),
                            'prior_best_in_band': list(prior_in_band) if prior_in_band else None,
                            'near_failure': False,
                            'target_reps': r,
                        })

                    # Process all sets to advance state for next capture
                    w = weights.get(exercise, 1.0)
                    for _ in range(n_sets):
                        cr = {p: sim.rank_for_xp(xp_pool[p]) for p in sim.BODY_PARTS}
                        awarded, _, _comp, best_by_band = sim.compute_set_xp(
                            exercise, w, r, novelty_count, weekly_count, peak_loads,
                            difficulty_mult=diff_m,
                            bodyweight_kg=persona.bodyweight_kg,
                            slug=real_slug,
                            current_ranks=cr,
                            best_by_band=best_by_band,
                            bp_session_count=bp_session,
                            near_failure=False,
                            female=persona.female,
                        )
                        for bp2, xp in awarded.items():
                            xp_pool[bp2] += xp

            # Apply progression after week
            for ex in weights:
                weights[ex] *= (1.0 + prog)

    return scenarios


def _rep_variation_scenarios():
    """Cover the rep grid (1, 3, 5, 8, 12, 15, 20) with neutral state."""
    scenarios = []
    cases = [
        ('bench', 100, 80, False, 'barbell_bench_press'),
        ('squat', 140, 80, False, 'barbell_squat'),
        ('deadlift', 200, 80, False, 'deadlift'),
        ('bench', 45, 60, True, 'barbell_bench_press'),
        ('squat', 70, 60, True, 'barbell_squat'),
    ]
    for exercise, weight, bw, female, slug in cases:
        for reps in [1, 3, 5, 8, 12, 15, 20]:
            scenarios.append({
                'name': f'{slug}_w{weight}_r{reps}_{"f" if female else "m"}',
                'persona_key': None,
                'session_index': None,
                'exercise': exercise,
                'slug': slug,
                'weight_kg': weight,
                'reps': reps,
                'bodyweight_kg': bw,
                'female': female,
                'difficulty_mult': sim.difficulty_mult_for_slug(slug),
                'peak_load': weight,
                'novelty_count': {},
                'weekly_count': {},
                'current_ranks': {},
                'bp_session_count': {},
                'prior_best_in_band': None,
                'near_failure': False,
                'target_reps': reps,
            })
    return scenarios


def _boundary_scenarios():
    """Pin edge cases: zero weight, ceiling difficulty, cap exceeded, NF flag,
    overload PR, bodyweight load semantics, female tier, rank 1 vs high.
    """
    base = {
        'name': '', 'persona_key': None, 'session_index': None,
        'exercise': 'bench', 'slug': 'barbell_bench_press',
        'weight_kg': 100, 'reps': 5, 'bodyweight_kg': 80, 'female': False,
        'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press'),
        'peak_load': 100, 'novelty_count': {}, 'weekly_count': {},
        'current_ranks': {}, 'bp_session_count': {},
        'prior_best_in_band': None, 'near_failure': False, 'target_reps': 5,
    }

    def derive(name, **kw):
        s = dict(base)
        s['name'] = name
        s.update(kw)
        return s

    scenarios = [
        derive('boundary_bench_peak_fresh'),
        derive('boundary_bench_deload_70', weight_kg=70, peak_load=100),
        derive('boundary_bench_floor_under', weight_kg=30, peak_load=100),  # strength floor
        derive('boundary_past_weekly_cap',
               slug='deadlift', exercise='deadlift', difficulty_mult=sim.difficulty_mult_for_slug('deadlift'),
               weekly_count={'back': 18, 'legs': 18, 'core': 18, 'arms': 18}),
        derive('boundary_high_rep_endurance', reps=20, slug='leg_curl', exercise='leg_curl',
               difficulty_mult=sim.difficulty_mult_for_slug('leg_curl')),
        derive('boundary_one_rm_ceiling', reps=1, weight_kg=140, peak_load=130,
               slug='push_press', exercise='bench',
               difficulty_mult=sim.difficulty_mult_for_slug('push_press')),
        # Bodyweight-as-load: pull_up @70kg user
        derive('boundary_bodyweight_pure_pullup', weight_kg=0, reps=8, peak_load=0,
               slug='pull_up', exercise='pullup', bodyweight_kg=70,
               difficulty_mult=sim.difficulty_mult_for_slug('pull_up')),
        # Weighted bodyweight: dips with +20kg
        derive('boundary_bodyweight_weighted_dips', weight_kg=20, reps=5, peak_load=20,
               slug='dips', exercise='dips', bodyweight_kg=80,
               difficulty_mult=sim.difficulty_mult_for_slug('dips')),
        # Near-failure flag
        derive('boundary_near_failure_flag', near_failure=True),
        # Near-failure inferred from target shortfall
        derive('boundary_near_failure_inferred', reps=5, target_reps=8),  # 5 < 8*0.85=6.8
        # Overload PR in heavy band
        derive('boundary_overload_pr_weight_up', weight_kg=110, peak_load=100,
               prior_best_in_band=[100, 5]),
        # Overload PR reps up at same weight
        derive('boundary_overload_pr_reps_up', weight_kg=100, peak_load=100,
               reps=6, prior_best_in_band=[100, 5]),
        # Frequency boost — 3rd session this week
        derive('boundary_frequency_3rd_session', bp_session_count={'chest': 3}),
        # tier_diff_mult — punching up
        derive('boundary_tier_diff_punching_up', weight_kg=180, peak_load=180,
               current_ranks={'chest': 1}),
        # tier_diff_mult — high rank trained set
        derive('boundary_tier_diff_high_rank', current_ranks={'chest': 40}),
        # Female bench
        derive('boundary_female_bench', weight_kg=45, reps=8, peak_load=45,
               bodyweight_kg=60, female=True, target_reps=8),
        # Female deadlift
        derive('boundary_female_deadlift', slug='deadlift', exercise='deadlift',
               weight_kg=85, reps=6, peak_load=85, bodyweight_kg=60, female=True, target_reps=6,
               difficulty_mult=sim.difficulty_mult_for_slug('deadlift')),
        # Elite Path C — absolute strength premium maxed
        derive('boundary_elite_path_c_bench', weight_kg=180, reps=3, peak_load=180,
               bodyweight_kg=95, target_reps=3),
        # Pre-floor implied tier (premium=1.0)
        derive('boundary_low_tier_no_premium', weight_kg=40, reps=8, peak_load=40,
               bodyweight_kg=80, target_reps=8),
        # User-created slug (unmapped)
        derive('boundary_unmapped_default',
               slug='custom_unmapped_slug', difficulty_mult=1.0,
               exercise='bench'),
    ]
    return scenarios


def fx_set_xp_v2():
    """PR 2 ORACLE — Phase 29 v2 + 29.6 set_xp matrix.

    PR 2's Dart `XpCalculator.computeSetXpV2` and the new SQL RPC must match
    each row's `set_xp` + `xp_per_body_part` to 1e-4 absolute.
    """
    out = []
    scenarios = (
        _persona_session_scenarios()
        + _rep_variation_scenarios()
        + _boundary_scenarios()
    )
    for sc in scenarios:
        awarded, total, vol, components = _compute_oracle_set_xp(sc)
        out.append({
            'name': sc['name'],
            'inputs': {
                'persona_key': sc['persona_key'],
                'session_index': sc['session_index'],
                'exercise': sc['exercise'],
                'slug': sc['slug'],
                'weight_kg': sc['weight_kg'],
                'reps': sc['reps'],
                'bodyweight_kg': sc['bodyweight_kg'],
                'female': sc['female'],
                'difficulty_mult': sc['difficulty_mult'],
                'peak_load': sc['peak_load'],
                'novelty_count': sc.get('novelty_count', {}),
                'weekly_count': sc.get('weekly_count', {}),
                'current_ranks': sc.get('current_ranks', {}),
                'bp_session_count': sc.get('bp_session_count', {}),
                'prior_best_in_band': sc.get('prior_best_in_band'),
                'near_failure': sc.get('near_failure', False),
                'target_reps': sc.get('target_reps'),
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
                'eff_weight': components['eff_weight'],
                'dominant_part': components['dominant_part'],
                'near_failure_effective': components['near_failure'],
            },
            'xp_per_body_part': awarded,
            'set_xp': total,
        })
    return out


def fx_attribution_distribution():
    """For a given exercise + set_xp, compute per-body-part XP."""
    cases = []
    for ex_slug, dist in sorted(sim.ATTRIBUTION.items()):
        cases.append({
            'exercise_slug': ex_slug,
            'attribution': dist,
            'set_xp_input': 100.0,
            'expected_distribution': {bp: 100.0 * share for bp, share in dist.items()},
        })
    return cases


# ---------------------------------------------------------------------------
# Persona panel result snapshot — for product-engineering checks
# ---------------------------------------------------------------------------

def fx_persona_panel():
    """Snapshot of the 13-persona panel final state at week 12."""
    out = []
    for pk in sim.PANEL_ORDER:
        snaps = sim.simulate_persona(pk, weeks=12)
        final = snaps[-1]
        lo, hi = sim.PANEL_TARGET_BANDS[pk]
        ar = sim.avg_active_rank(final)
        out.append({
            'persona_key': pk,
            'persona_name': sim.PERSONAS[pk].name,
            'character_level': final['character_level'],
            'avg_active_rank': ar,
            'cumulative_xp': final['cumulative_xp'],
            'ranks': final['ranks'],
            'target_band_lo': lo,
            'target_band_hi': hi,
            'pass': lo <= ar <= hi,
        })
    return out


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    fixtures = {
        'meta': {
            'phase': 'Phase 29 v2 + 29.6 LOCKED',
            'volume_exponent': sim.VOLUME_EXPONENT,
            'novelty_denominator': sim.NOVELTY_DENOMINATOR,
            'weekly_cap_sets': sim.WEEKLY_CAP_SETS,
            'over_cap_multiplier': sim.OVER_CAP_MULTIPLIER,
            'strength_mult_floor': sim.STRENGTH_MULT_FLOOR,
            'volume_load_floor': sim.VOLUME_LOAD_FLOOR,
            'difficulty_mult_floor': sim.DIFFICULTY_MULT_FLOOR,
            'difficulty_mult_ceiling': sim.DIFFICULTY_MULT_CEILING,
            'xp_base': sim.XP_BASE,
            'xp_growth_band1': sim.XP_GROWTH_BAND1,
            'rank_curve_breakpoint': sim.RANK_CURVE_BREAKPOINT,
            'linear_xp_per_rank': sim.LINEAR_XP_PER_RANK,
            'char_level_denominator': sim.CHAR_LEVEL_DENOMINATOR,
            'e_bonus': sim.E_BONUS,
            'e_floor': sim.E_FLOOR,
            'e_ceil': sim.E_CEIL,
            'nf_intensity_bonus': sim.NF_INTENSITY_BONUS,
            'nf_target_threshold': sim.NF_TARGET_THRESHOLD,
            'frequency_mult_table': list(sim.FREQUENCY_MULT_TABLE),
            'tier_diff_offset': sim.TIER_DIFF_OFFSET,
            'tier_diff_exp': sim.TIER_DIFF_EXP,
            'tier_diff_max': sim.TIER_DIFF_MAX,
            'tier_diff_min': sim.TIER_DIFF_MIN,
            'rep_band_heavy_max': sim.REP_BAND_HEAVY_MAX,
            'rep_band_strength_max': sim.REP_BAND_STRENGTH_MAX,
            'rep_band_hypertrophy_max': sim.REP_BAND_HYPERTROPHY_MAX,
            'bodyweight_load_slugs': sorted(sim.USES_BODYWEIGHT_LOAD_BY_SLUG),
        },
        'intensity_lookup': fx_intensity_lookup(),
        'volume_load': fx_volume_load(),
        'strength_mult': fx_strength_mult(),
        'novelty_mult': fx_novelty_mult(),
        'cap_mult': fx_cap_mult(),
        'difficulty_mult_lookup': fx_difficulty_mult_lookup(),
        'bodyweight_load_ratio': fx_bodyweight_load_ratio(),
        'implied_tier': fx_implied_tier(),
        'abs_strength_premium': fx_abs_strength_premium(),
        'tier_diff_mult': fx_tier_diff_mult(),
        'overload_mult': fx_overload_mult(),
        'frequency_mult': fx_frequency_mult(),
        'near_failure_inference': fx_near_failure_inference(),
        'rank_curve': fx_rank_curve(),
        'vitality': fx_vitality(),
        'character_level': fx_character_level(),
        'attribution_distribution': fx_attribution_distribution(),
        'set_xp_v2': fx_set_xp_v2(),
        'persona_panel': fx_persona_panel(),
    }
    out = os.path.join(HERE, 'rpg_xp_fixtures.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(fixtures, f, indent=2, sort_keys=True)
    print(f'Wrote {out}')
    print(f'  set_xp_v2 (PR 2 oracle): {len(fixtures["set_xp_v2"])} rows')
    print(f'  implied_tier: {len(fixtures["implied_tier"])} cases')
    print(f'  abs_strength_premium: {len(fixtures["abs_strength_premium"])} cases')
    print(f'  tier_diff_mult: {len(fixtures["tier_diff_mult"])} cases')
    print(f'  overload_mult: {len(fixtures["overload_mult"])} cases')
    print(f'  frequency_mult: {len(fixtures["frequency_mult"])} cases')
    print(f'  near_failure_inference: {len(fixtures["near_failure_inference"])} cases')
    print(f'  rank_curve milestones: {len(fixtures["rank_curve"]["milestones"])}')
    print(f'  persona_panel: {len(fixtures["persona_panel"])} personas')
    passes = sum(1 for p in fixtures['persona_panel'] if p['pass'])
    print(f'  persona_panel PASS: {passes}/{len(fixtures["persona_panel"])}')


if __name__ == '__main__':
    main()
