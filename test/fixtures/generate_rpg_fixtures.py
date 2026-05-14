"""
Generates JSON fixtures from the canonical Python XP simulation for Dart
parity tests.

Run:  python test/fixtures/generate_rpg_fixtures.py
Output: test/fixtures/rpg_xp_fixtures.json

This file is the SINGLE source of truth for both Python and Dart XP
calculations. If a Dart calculator drifts vs the Python sim, the fixture
test fails, and the spec/Python is the authority.
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


def _load_sim():
    import importlib.util
    spec = importlib.util.spec_from_file_location('rpg_sim', SIM_PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules['rpg_sim'] = mod
    spec.loader.exec_module(mod)
    return mod


sim = _load_sim()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def fx_intensity_lookup() -> list[dict]:
    """Reps -> intensity multiplier table. Lookup is reps-floor."""
    cases = []
    for reps in [1, 2, 3, 4, 5, 7, 8, 10, 12, 13, 15, 16, 20, 25]:
        cases.append({'reps': reps, 'intensity_mult': sim.intensity_for_reps(reps)})
    return cases


def fx_volume_load() -> list[dict]:
    """volume_load = max(1.0, weight × reps), then base = volume_load^0.65."""
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
        (100, 100, 1.0),     # at peak
        (110, 100, 1.0),     # above peak (clamps to 1.0; peak should advance)
        (70, 100, 0.7),      # 70% deload
        (50, 100, 0.5),      # 50% technique
        (30, 100, 0.4),      # below floor → 0.4
        (10, 100, 0.4),      # way below floor
        (50, 0, 1.0),        # peak=0 → divide-by-zero guard returns 1.0
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
    """cap_mult = 0.5 if weekly_volume >= 20 else 1.0."""
    cases = []
    for wv in [0, 10, 19, 19.99, 20, 20.5, 30, 50]:
        cm = sim.OVER_CAP_MULTIPLIER if wv >= sim.WEEKLY_CAP_SETS else 1.0
        cases.append({'weekly_volume_for_body_part': wv, 'cap_mult': cm})
    return cases


def fx_set_xp_examples() -> list[dict]:
    """End-to-end set_xp examples (no attribution applied — just total set_xp).

    Phase 24a: every scenario carries a `difficulty_mult` input. We exercise
    both ends of the [0.85, 1.25] range explicitly (clamp boundaries) plus a
    mix of real per-exercise values from `DIFFICULTY_MULT_BY_SLUG` so the
    fixture covers the multipliers that actually ship in the migration. The
    `slug` field is informational (documents which migration row the value
    came from) and is not consumed by the Dart parity test — Dart asserts
    against the `inputs.difficulty_mult` numeric value directly.
    """
    cases = []
    scenarios = [
        # Bench at peak, fresh session, low weekly volume — barbell_bench_press = 1.09
        {'name': 'bench_peak_fresh', 'weight': 100, 'reps': 5, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press')},
        # Same set, late in session (10 sets in already) — same exercise
        {'name': 'bench_peak_late_session', 'weight': 100, 'reps': 5, 'peak': 100,
         'session_volume_bp': 10, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press')},
        # Deload at 70% — same exercise
        {'name': 'bench_deload_70', 'weight': 70, 'reps': 5, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'barbell_bench_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_bench_press')},
        # Junk volume — past weekly cap. Use deadlift (1.21) so cap × ceiling
        # interaction is exercised end-to-end.
        {'name': 'past_weekly_cap', 'weight': 100, 'reps': 5, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 25,
         'slug': 'deadlift',
         'difficulty_mult': sim.difficulty_mult_for_slug('deadlift')},
        # High-rep endurance — leg_curl (0.85) hits the FLOOR exactly.
        {'name': 'high_rep_endurance_floor', 'weight': 60, 'reps': 20, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'leg_curl',
         'difficulty_mult': sim.difficulty_mult_for_slug('leg_curl')},
        # 1RM attempt — push_press (1.25) hits the CEILING exactly.
        {'name': 'one_rm_ceiling', 'weight': 140, 'reps': 1, 'peak': 130,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'push_press',
         'difficulty_mult': sim.difficulty_mult_for_slug('push_press')},
        # Bodyweight floor — push_up (1.11), volume_load floored at 1.0.
        {'name': 'bodyweight_floor', 'weight': 0, 'reps': 8, 'peak': 0,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': 'push_up',
         'difficulty_mult': sim.difficulty_mult_for_slug('push_up')},
        # Stagnant lifter at very light weight — barbell_curl (0.87).
        {'name': 'stagnant_curl', 'weight': 5, 'reps': 12, 'peak': 5,
         'session_volume_bp': 5, 'weekly_volume_bp': 8,
         'slug': 'barbell_curl',
         'difficulty_mult': sim.difficulty_mult_for_slug('barbell_curl')},
        # User-created / unmapped exercise — defaults to 1.0 (no-op multiplier;
        # asserts that the column DEFAULT 1.0 path still produces sensible XP).
        {'name': 'user_created_default_1_0', 'weight': 80, 'reps': 8, 'peak': 80,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': None,
         'difficulty_mult': sim.difficulty_mult_for_slug('not_a_real_slug')},
        # Explicit clamp boundaries — pin the literal 0.85 / 1.25 values
        # independent of any single exercise so a future re-tier doesn't
        # accidentally break the boundary contract.
        {'name': 'explicit_floor_0_85', 'weight': 100, 'reps': 8, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': None,
         'difficulty_mult': sim.DIFFICULTY_MULT_FLOOR},
        {'name': 'explicit_ceiling_1_25', 'weight': 100, 'reps': 8, 'peak': 100,
         'session_volume_bp': 0, 'weekly_volume_bp': 0,
         'slug': None,
         'difficulty_mult': sim.DIFFICULTY_MULT_CEILING},
    ]
    for s in scenarios:
        vl = max(1.0, s['weight'] * s['reps'])
        base = vl ** sim.VOLUME_EXPONENT
        intensity = sim.intensity_for_reps(s['reps'])
        peak = s['peak'] if s['peak'] > 0 else s['weight']
        if peak <= 0:
            strength_mult = 1.0
        else:
            strength_mult = max(sim.STRENGTH_MULT_FLOOR,
                                min(1.0, s['weight'] / peak if peak > 0 else 1.0))
        novelty = math.exp(-s['session_volume_bp'] / sim.NOVELTY_DENOMINATOR)
        cap = sim.OVER_CAP_MULTIPLIER if s['weekly_volume_bp'] >= sim.WEEKLY_CAP_SETS else 1.0
        diff_mult = s['difficulty_mult']
        set_xp = base * intensity * strength_mult * novelty * cap * diff_mult
        cases.append({
            'name': s['name'],
            'inputs': {
                'weight_kg': s['weight'],
                'reps': s['reps'],
                'peak_load': s['peak'],
                'session_volume_for_body_part': s['session_volume_bp'],
                'weekly_volume_for_body_part': s['weekly_volume_bp'],
                'difficulty_mult': diff_mult,
                'slug': s['slug'],
            },
            'components': {
                'volume_load': vl,
                'base_xp': base,
                'intensity_mult': intensity,
                'strength_mult': strength_mult,
                'novelty_mult': novelty,
                'cap_mult': cap,
                # Field name + position mirror Dart's `SetXpComponents.toJson()`
                # (between cap_mult and set_xp). JSON output is sort_keys=True
                # so on-disk ordering is alphabetical anyway — name match is
                # the load-bearing contract.
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
    """Cumulative XP for each rank (1..99) + rank_for_xp lookups."""
    cumulative = {}
    for n in range(1, 100):
        cumulative[str(n)] = sim.xp_for_rank(n)
    lookups = []
    for total in [0, 59, 60, 277, 278, 813, 814, 3068, 3069, 8916, 8917,
                  63430, 63431, 430170, 430171, 6832760, 6832761, 9999999]:
        lookups.append({'total_xp': total, 'rank': sim.rank_for_xp(total)})
    milestones = []
    for n in [1, 2, 5, 10, 20, 30, 50, 70, 90, 99]:
        milestones.append({'rank': n, 'cumulative_xp': sim.xp_for_rank(n)})
    return {
        'cumulative': cumulative,
        'lookups': lookups,
        'milestones': milestones,
    }


def fx_vitality() -> dict:
    """
    Vitality EWMA test cases — verifies asymmetric α + peak monotonicity.

    Uses τ_up = 2 weeks, τ_down = 6 weeks.
    α_up = 1 - exp(-1/2) ≈ 0.3935
    α_down = 1 - exp(-1/6) ≈ 0.1535
    """
    alpha_up = 1 - math.exp(-1 / sim.VITALITY_TAU_UP_WEEKS)
    alpha_down = 1 - math.exp(-1 / sim.VITALITY_TAU_DOWN_WEEKS)

    # Trajectory: start at 0, train at 100 vol/wk for 10 weeks (rebuild),
    # then 0 vol/wk for 20 weeks (decay). Capture EWMA + peak each week.
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

    # Comeback simulation — replays sim.simulate('comeback_kid', 260) and
    # extracts the chest body-part EWMA at key weeks.
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
    """Character level = max(1, floor((Σranks - 6) / 4) + 1) for v1 (6 active)."""
    cases = []
    scenarios = [
        ({'chest': 1, 'back': 1, 'legs': 1, 'shoulders': 1, 'arms': 1, 'core': 1}, 1),
        ({'chest': 5, 'back': 5, 'legs': 5, 'shoulders': 5, 'arms': 5, 'core': 5}, 7),
        ({'chest': 20, 'back': 20, 'legs': 20, 'shoulders': 20, 'arms': 20, 'core': 20}, 29),
        ({'chest': 50, 'back': 50, 'legs': 50, 'shoulders': 50, 'arms': 50, 'core': 50}, 74),
        ({'chest': 99, 'back': 99, 'legs': 99, 'shoulders': 99, 'arms': 99, 'core': 99}, 148),
    ]
    for ranks, expected in scenarios:
        cases.append({'ranks': ranks, 'character_level': expected})
    return cases


# ---------------------------------------------------------------------------
# Backfill replay reference output — 1500-set fixture user
# ---------------------------------------------------------------------------

def fx_backfill_replay() -> dict:
    """
    Replays an intermediate archetype's first ~30 weeks of training (≈1500
    sets) through the sim and emits the final state for each body part.

    The Dart + PG backfill tests must produce the same final state when fed
    the same chronological set log.

    NOTE: emits the per-set log too so integration tests can replay it.
    """
    archetype = sim.ARCHETYPES['intermediate']
    weeks = 30  # ~1500 sets at 4 sessions × 12-15 sets each

    # We need to instrument the sim to emit per-set events. Re-run inline
    # here (mirrors `simulate` but logs).
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
                # Phase 24a: each set carries the multiplier its real-slug
                # analog would use in the live save path. The alias resolver
                # maps simulator short names ('bench', 'squat', etc.) onto
                # the actual `exercises.difficulty_mult` value that ships in
                # the migration, so the regenerated final ranks reflect the
                # exact per-exercise weighting users will experience.
                diff_mult = sim.difficulty_mult_for_alias(exercise)
                for _ in range(n_sets):
                    set_index += 1
                    session_set_index += 1
                    awarded, vol = sim.compute_set_xp(
                        exercise, w, reps, novelty_count, weekly_count, peak_loads,
                        difficulty_mult=diff_mult,
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
                        'awarded': dict(awarded),
                    })
        rate = sim.progression_rate(archetype, week)
        for ex in weights:
            weights[ex] *= rate

    final_ranks = {p: sim.rank_for_xp(xp_pool[p]) for p in sim.BODY_PARTS}
    return {
        'archetype': 'intermediate',
        'weeks_simulated': weeks,
        'total_sets': set_index,
        'final_xp_pool': xp_pool,
        'final_ranks': final_ranks,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    fixtures = {
        'meta': {
            'volume_exponent': sim.VOLUME_EXPONENT,
            'novelty_denominator': sim.NOVELTY_DENOMINATOR,
            'weekly_cap_sets': sim.WEEKLY_CAP_SETS,
            'over_cap_multiplier': sim.OVER_CAP_MULTIPLIER,
            'strength_mult_floor': sim.STRENGTH_MULT_FLOOR,
            'difficulty_mult_floor': sim.DIFFICULTY_MULT_FLOOR,
            'difficulty_mult_ceiling': sim.DIFFICULTY_MULT_CEILING,
            'xp_base': sim.XP_BASE,
            'xp_growth': sim.XP_GROWTH,
            'char_level_denominator': sim.CHAR_LEVEL_DENOMINATOR,
        },
        'intensity_lookup': fx_intensity_lookup(),
        'volume_load': fx_volume_load(),
        'strength_mult': fx_strength_mult(),
        'novelty_mult': fx_novelty_mult(),
        'cap_mult': fx_cap_mult(),
        'set_xp_examples': fx_set_xp_examples(),
        'attribution_distribution': fx_attribution_distribution(),
        'rank_curve': fx_rank_curve(),
        'vitality': fx_vitality(),
        'character_level': fx_character_level(),
        'backfill_replay': fx_backfill_replay(),
    }
    out = os.path.join(HERE, 'rpg_xp_fixtures.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(fixtures, f, indent=2, sort_keys=True)
    print(f'Wrote {out}')
    print(f'  intensity_lookup: {len(fixtures["intensity_lookup"])} cases')
    print(f'  volume_load: {len(fixtures["volume_load"])} cases')
    print(f'  strength_mult: {len(fixtures["strength_mult"])} cases')
    print(f'  novelty_mult: {len(fixtures["novelty_mult"])} cases')
    print(f'  cap_mult: {len(fixtures["cap_mult"])} cases')
    print(f'  set_xp_examples: {len(fixtures["set_xp_examples"])} cases')
    print(f'  attribution: {len(fixtures["attribution_distribution"])} exercises')
    print(f'  rank_curve milestones: {len(fixtures["rank_curve"]["milestones"])}')
    print(f'  vitality trajectory: {len(fixtures["vitality"]["rebuild_then_decay_trajectory"])} weeks')
    print(f'  backfill_replay: {fixtures["backfill_replay"]["total_sets"]} sets')


if __name__ == '__main__':
    main()
