"""
RepSaga RPG XP simulation harness.

Plays back synthetic 5-year training histories for several user archetypes
(beginner / intermediate / advanced / perpetual-light / detraining cases)
through the candidate XP + Vitality formulas to surface pacing problems
before we lock the math.

Tweak the constants in the CONFIG block below; re-run to see new
trajectories. Output is a milestones table per archetype plus a Vitality
trajectory for detraining scenarios.

Usage:  python tasks/rpg-xp-simulation.py

================================================================================
PARITY WARNING — synchronized formula sites
================================================================================
The XP formula is implemented in FOUR places that MUST stay byte-for-byte
identical. Any change to a constant, multiplier order, or floor/ceiling here
must land in the same PR as the matching change in:

  1. lib/features/rpg/domain/xp_calculator.dart
     (Dart `XpCalculator.computeSetXp` — live save path)
  2. test/fixtures/generate_rpg_fixtures.py
     (regenerate `rpg_xp_fixtures.json` so Dart parity tests stay green)
  3. supabase/migrations/00040_*.sql, 00050_*.sql, 00052_*.sql, and
     00054_record_xp_with_difficulty_mult.sql
     (PL/pgSQL `record_set_xp` / `record_session_xp_batch` /
     `_rpg_backfill_chunk` — live persist path; per-exercise difficulty_mult
     fetched from `exercises.difficulty_mult` and applied at the same
     position in the chain)

Integration parity tests assert all four agree to 1e-4 absolute. If you only
change one site you'll get a build that compiles but produces silently
inconsistent XP between client computation and server persistence.
================================================================================
"""

from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field

# ============================================================================
# CONFIG — tunable XP math constants
# ============================================================================

# Per-rank XP curve: xp_to_next(n) = XP_BASE × XP_GROWTH^(n-1)
XP_BASE = 60
XP_GROWTH = 1.10

# Per-set XP formula
VOLUME_EXPONENT = 0.65         # base = (weight × reps)^this; sub-linear so 10× vol ≠ 10× XP
NOVELTY_DENOMINATOR = 15       # higher = slower diminishing returns within a session
WEEKLY_CAP_SETS = 20           # effective sets per body part before XP halves
OVER_CAP_MULTIPLIER = 0.5

# Strength multiplier: clamp(current_load / peak_load, FLOOR, 1.0).
# Anti-stagnation — a perpetual 5kg curl can't outrank a real lifter.
STRENGTH_MULT_FLOOR = 0.4

# Difficulty multiplier range (Phase 24a). Per-exercise composite carried on
# `exercises.difficulty_mult`. Documented here for parity with the SQL CHECK
# constraint and Dart `XpCalculator.difficultyMultFloor`/`Ceiling`. Values
# OUTSIDE this range reaching `compute_set_xp` are a data-integrity bug —
# the simulator does not silently clip.
DIFFICULTY_MULT_FLOOR = 0.85
DIFFICULTY_MULT_CEILING = 1.25

# Intensity multiplier by rep range (lower reps = heavier load = more XP per rep)
INTENSITY_BY_REPS = [
    (1, 1.30),
    (3, 1.25),
    (5, 1.20),
    (8, 1.00),
    (12, 0.95),
    (15, 0.90),
    (20, 0.80),
]

# Character level: floor((Σ ranks − N) / DENOMINATOR) + 1
CHAR_LEVEL_DENOMINATOR = 4

# Class threshold: ranks within this fraction of max → Ascendant (balanced)
ASCENDANT_BALANCE_THRESHOLD = 0.30
ASCENDANT_MIN_RANK = 5

# Vitality (asymmetric EWMA on weekly volume per body part).
# Time constants in WEEKS — converted from days (14d / 42d) by /7.
VITALITY_TAU_UP_WEEKS = 2.0    # rebuild fast (myonuclei retention)
VITALITY_TAU_DOWN_WEEKS = 6.0  # decay slow (Mujika & Padilla curves)
VITALITY_PEAK_PERMANENT = True # peak never decays — saga is inviolate

# Bodyweight progression (proxy for rep increases on bodyweight exercises)
PROGRESSION_RATES = {
    'beginner': 1.025,      # 2.5% per week (newbie gains honeymoon, ~12 weeks)
    'intermediate': 1.005,  # 0.5% per week
    'advanced': 1.001,      # 0.1% per week (creep)
    'stagnant': 1.000,      # zero progression — the "5kg forever" archetype
}

# Newbie-gains decay: progression rate decays toward intermediate after 12 weeks
NEWBIE_DECAY_WEEKS = 12

# ============================================================================
# Exercise → body-part attribution map (literature-grounded draft)
# ============================================================================

ATTRIBUTION = {
    # Push
    'bench':           {'chest': 0.70, 'shoulders': 0.20, 'arms': 0.10},
    'incline_bench':   {'chest': 0.60, 'shoulders': 0.30, 'arms': 0.10},
    'overhead_press':  {'shoulders': 0.60, 'arms': 0.20, 'core': 0.20},
    'lateral_raise':   {'shoulders': 0.85, 'arms': 0.10, 'core': 0.05},
    'tricep_pushdown': {'arms': 0.95, 'shoulders': 0.05},
    # Pull
    'row':             {'back': 0.70, 'arms': 0.20, 'core': 0.10},
    'pulldown':        {'back': 0.75, 'arms': 0.20, 'core': 0.05},
    'pullup':          {'back': 0.65, 'arms': 0.25, 'core': 0.10},
    'curl':            {'arms': 0.90, 'back': 0.10},
    # Legs
    'squat':           {'legs': 0.80, 'core': 0.10, 'back': 0.10},
    'deadlift':        {'back': 0.40, 'legs': 0.40, 'core': 0.10, 'arms': 0.10},
    'leg_press':       {'legs': 0.95, 'core': 0.05},
    'lunge':           {'legs': 0.90, 'core': 0.10},
    # Core
    'plank':           {'core': 0.90, 'shoulders': 0.05, 'arms': 0.05},
    'leg_raise':       {'core': 1.00},
}

# ============================================================================
# Per-exercise difficulty multiplier (Phase 24a)
# ============================================================================
#
# Mirrors `exercises.difficulty_mult` populated by
# `supabase/migrations/00053_add_exercise_difficulty_mult.sql`. Values are the
# pre-clamped composite (tier_mult + secondary bump, framework §6) and live
# in [0.85, 1.25]. The migration is the source of truth — if you change a
# value here without updating the migration (or vice versa), integration
# parity tests break.
#
# Slugs not in this map default to 1.0 (matches the SQL `COALESCE(..., 1.0)`
# and the column DEFAULT 1.0 for user-created exercises).
#
# The simulator's archetype playback uses short aliases for exercise classes
# (`bench`, `squat`, `row`, etc.) that don't appear here — those are
# pre-Phase-24a synthetic identifiers and are looked up via
# `SIM_ALIAS_DIFFICULTY_MULT` below using a plausible default-exercise
# analog. The fixture generator's backfill replay maps each alias to a real
# slug so the regenerated fixture exercises the actual per-slug values that
# ship in the migration.

DIFFICULTY_MULT_BY_SLUG = {
    'ab_rollout': 1.09, 'arnold_press': 1.09,
    'back_extension': 0.89, 'band_face_pull': 0.99, 'band_pull_apart': 0.89, 'band_squat': 0.97,
    'barbell_bench_press': 1.09, 'barbell_bent_over_row': 1.19, 'barbell_curl': 0.87,
    'barbell_shrug': 0.89, 'barbell_squat': 1.19, 'bench_dip': 1.09, 'bicycle_crunch': 0.85,
    'bodyweight_squat': 1.07, 'box_jump': 1.25, 'bulgarian_split_squat': 1.07,
    'cable_chest_press': 0.99, 'cable_crossover': 0.99, 'cable_crunch': 0.95, 'cable_curl': 0.87,
    'cable_face_pull': 0.99, 'cable_front_raise': 0.89, 'cable_glute_kickback': 0.97,
    'cable_hammer_curl': 0.87, 'cable_lateral_raise': 0.89, 'cable_pull_through': 0.99,
    'cable_rear_delt_fly': 0.89, 'cable_row': 0.99, 'cable_woodchop': 0.99,
    'calf_raise': 0.85, 'chest_supported_row': 1.07, 'chin_up': 1.19,
    'close_grip_bench_press': 1.09, 'close_grip_lat_pulldown': 0.99, 'close_grip_push_up': 1.11,
    'concentration_curl': 0.87, 'crunches': 0.85,
    'dead_bug': 0.85, 'deadlift': 1.21, 'decline_barbell_bench_press': 1.09,
    'decline_dumbbell_press': 1.09, 'decline_push_up': 1.11, 'diamond_push_up': 1.11,
    'dips': 1.19, 'donkey_kick': 0.87, 'dumbbell_bench_press': 1.09,
    'dumbbell_calf_raise': 0.85, 'dumbbell_curl': 0.87, 'dumbbell_fly': 0.89,
    'dumbbell_lunges': 1.07, 'dumbbell_pullover': 0.91, 'dumbbell_row': 1.09,
    'dumbbell_shoulder_press': 1.09, 'dumbbell_shrug': 0.89, 'dumbbell_tricep_extension': 0.87,
    'elliptical': 0.85, 'ez_bar_curl': 0.87,
    'face_pull': 0.99, 'farmer_s_walk': 1.11, 'flutter_kick': 0.85,
    'front_raise': 0.89, 'front_squat': 1.19,
    'glute_bridge': 0.87, 'goblet_squat': 1.09, 'good_morning': 1.09,
    'hack_squat': 1.09, 'hammer_curl': 0.87, 'hanging_leg_raise': 1.09,
    'heel_touch': 0.85, 'hip_thrust': 1.07, 'hollow_body_hold': 0.85, 'hyperextension': 0.89,
    'incline_barbell_bench_press': 1.09, 'incline_dumbbell_curl': 0.87,
    'incline_dumbbell_fly': 0.89, 'incline_dumbbell_press': 1.09, 'incline_push_up': 1.11,
    'inverted_row': 1.09,
    'jm_press': 1.09, 'jump_rope': 0.85,
    'kettlebell_deadlift': 1.21, 'kettlebell_goblet_squat': 1.09, 'kettlebell_press': 1.09,
    'kettlebell_row': 1.09, 'kettlebell_swing': 1.11, 'kettlebell_turkish_get_up': 1.21,
    'kettlebell_windmill': 1.09,
    'landmine_press': 1.11, 'landmine_shoulder_press': 1.11,
    'lat_pulldown': 0.99, 'lateral_raise': 0.89, 'leg_abductor': 0.85, 'leg_adductor': 0.85,
    'leg_curl': 0.85, 'leg_extension': 0.85, 'leg_press': 0.97, 'leg_raise': 0.85,
    'machine_chest_press': 0.99, 'machine_row': 0.99, 'machine_shoulder_press': 0.99,
    'mountain_climber': 1.09,
    'nordic_curl': 0.87,
    'overhead_press': 1.19, 'overhead_tricep_extension': 0.87,
    'pallof_press': 0.97, 'pec_deck': 0.89, 'pendlay_row': 1.19,
    'plank': 0.89, 'plank_up_down': 1.09, 'preacher_curl': 0.87,
    'pull_up': 1.19, 'push_press': 1.25, 'push_up': 1.11,
    'rack_pull': 1.21, 'rear_delt_fly': 0.89, 'reverse_crunch': 0.85, 'reverse_curl': 0.87,
    'reverse_hyperextension': 0.99, 'reverse_lunges': 1.07, 'reverse_pec_deck': 0.89,
    'reverse_wrist_curl': 0.87, 'romanian_deadlift': 1.09, 'rope_pushdown': 0.97,
    'rowing_machine': 0.85, 'russian_twist': 0.85,
    'seal_row': 1.07, 'seated_calf_raise': 0.85, 'side_plank': 0.89,
    'single_leg_glute_bridge': 0.87, 'single_leg_leg_press': 0.97, 'sit_up': 0.85,
    'skull_crusher': 0.87, 'spider_curl': 0.87, 'stationary_bike': 0.85,
    'step_up': 1.07, 'straight_arm_pulldown': 0.89, 'sumo_deadlift': 1.21,
    't_bar_row': 1.19, 'toe_touch': 0.85, 'treadmill': 0.85, 'tricep_pushdown': 0.97,
    'upright_row': 0.99,
    'v_up': 0.85,
    'walking_lunges': 1.07, 'wall_sit': 0.87, 'wide_grip_pull_up': 1.19,
    'wide_push_up': 1.11, 'windshield_wiper': 0.85, 'wrist_curl': 0.87,
    'zottman_curl': 0.87,
}


# Mapping from the simulator's short class aliases (used by DAY_TEMPLATES /
# WEEK_SCHEDULES) onto a representative real default-exercise slug. This
# lets the multi-week archetype playback exercise the actual per-exercise
# multipliers that ship in the migration without rewriting the synthetic
# day templates.
SIM_ALIAS_TO_DEFAULT_SLUG = {
    'bench':           'barbell_bench_press',         # 1.09
    'incline_bench':   'incline_barbell_bench_press', # 1.09
    'overhead_press':  'overhead_press',              # 1.19
    'lateral_raise':   'lateral_raise',               # 0.89
    'tricep_pushdown': 'tricep_pushdown',             # 0.97
    'row':             'barbell_bent_over_row',       # 1.19
    'pulldown':        'lat_pulldown',                # 0.99
    'pullup':          'pull_up',                     # 1.19
    'curl':            'barbell_curl',                # 0.87
    'squat':           'barbell_squat',               # 1.19
    'deadlift':        'deadlift',                    # 1.21
    'leg_press':       'leg_press',                   # 0.97
    'lunge':           'walking_lunges',              # 1.07
    'plank':           'plank',                       # 0.89
    'leg_raise':       'leg_raise',                   # 0.85
}


def difficulty_mult_for_slug(slug: str) -> float:
    """Per-exercise difficulty multiplier; defaults to 1.0 for user-created /
    unmapped slugs (matches SQL `COALESCE(exercises.difficulty_mult, 1.0)`
    and Dart `XpCalculator.computeSetXp` which receives whatever the column
    default produced).
    """
    return DIFFICULTY_MULT_BY_SLUG.get(slug, 1.0)


def difficulty_mult_for_alias(alias: str) -> float:
    """Resolves a simulator short alias (e.g. 'bench') to a real slug
    multiplier via `SIM_ALIAS_TO_DEFAULT_SLUG`. Falls back to 1.0 for
    unmapped aliases (synthetic exercises with no real-world analog)."""
    slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(alias)
    if slug is None:
        return 1.0
    return difficulty_mult_for_slug(slug)


# ============================================================================
# Day templates — weekly split layouts
# ============================================================================

DAY_TEMPLATES = {
    'push':  [('bench', 4, 8), ('overhead_press', 3, 8), ('lateral_raise', 3, 12), ('tricep_pushdown', 3, 12)],
    'pull':  [('row', 4, 8), ('pulldown', 3, 10), ('curl', 3, 12), ('plank', 2, 30)],
    'legs':  [('squat', 4, 6), ('deadlift', 3, 5), ('leg_press', 3, 10), ('lunge', 3, 10)],
    'upper': [('bench', 3, 8), ('row', 3, 8), ('overhead_press', 3, 8), ('curl', 3, 10), ('tricep_pushdown', 3, 10)],
}

WEEK_SCHEDULES = {
    3: ['push', 'pull', 'legs'],
    4: ['push', 'pull', 'legs', 'upper'],
    5: ['push', 'pull', 'legs', 'upper', 'legs'],
}

# ============================================================================
# User archetypes
# ============================================================================

@dataclass
class Archetype:
    name: str
    sessions_per_week: int
    starting_weights: dict[str, float]
    progression: str  # key into PROGRESSION_RATES

    # Optional layoff schedule: list of (start_week, end_week) inclusive
    # ranges where the user does NO training. Used for detraining scenarios.
    layoffs: list[tuple[int, int]] = field(default_factory=list)


ARCHETYPES = {
    'beginner': Archetype(
        name='beginner',
        sessions_per_week=3,
        progression='beginner',
        starting_weights={
            'bench': 40, 'incline_bench': 30, 'overhead_press': 25, 'row': 35, 'pulldown': 35,
            'pullup': 0, 'squat': 50, 'deadlift': 60, 'leg_press': 60, 'lunge': 20,
            'curl': 12, 'tricep_pushdown': 20, 'lateral_raise': 6, 'plank': 1, 'leg_raise': 1,
        },
    ),
    'intermediate': Archetype(
        name='intermediate',
        sessions_per_week=4,
        progression='intermediate',
        starting_weights={
            'bench': 80, 'incline_bench': 65, 'overhead_press': 50, 'row': 70, 'pulldown': 70,
            'pullup': 10, 'squat': 100, 'deadlift': 120, 'leg_press': 140, 'lunge': 40,
            'curl': 18, 'tricep_pushdown': 35, 'lateral_raise': 10, 'plank': 1, 'leg_raise': 1,
        },
    ),
    'advanced': Archetype(
        name='advanced',
        sessions_per_week=5,
        progression='advanced',
        starting_weights={
            'bench': 120, 'incline_bench': 95, 'overhead_press': 80, 'row': 100, 'pulldown': 100,
            'pullup': 25, 'squat': 160, 'deadlift': 200, 'leg_press': 220, 'lunge': 60,
            'curl': 25, 'tricep_pushdown': 50, 'lateral_raise': 14, 'plank': 1, 'leg_raise': 1,
        },
    ),
    # The stagnation test — proves strength_mult prevents grinding past your peers
    # on chronically light loads. Same volume as beginner but no progression.
    'stagnant_lifter': Archetype(
        name='stagnant_lifter',
        sessions_per_week=3,
        progression='stagnant',
        starting_weights={
            'bench': 20, 'incline_bench': 15, 'overhead_press': 15, 'row': 20, 'pulldown': 20,
            'pullup': 0, 'squat': 25, 'deadlift': 30, 'leg_press': 40, 'lunge': 10,
            'curl': 5, 'tricep_pushdown': 8, 'lateral_raise': 3, 'plank': 1, 'leg_raise': 1,
        },
    ),
    # Detraining test: trains intermediate for 1yr, takes 6mo off, resumes
    'comeback_kid': Archetype(
        name='comeback_kid',
        sessions_per_week=4,
        progression='intermediate',
        starting_weights={
            'bench': 80, 'incline_bench': 65, 'overhead_press': 50, 'row': 70, 'pulldown': 70,
            'pullup': 10, 'squat': 100, 'deadlift': 120, 'leg_press': 140, 'lunge': 40,
            'curl': 18, 'tricep_pushdown': 35, 'lateral_raise': 10, 'plank': 1, 'leg_raise': 1,
        },
        layoffs=[(53, 78)],  # 6mo break after first year
    ),
    # Vacation pattern: 2 weeks off every 6 months (life happens)
    'vacationer': Archetype(
        name='vacationer',
        sessions_per_week=4,
        progression='intermediate',
        starting_weights={
            'bench': 80, 'incline_bench': 65, 'overhead_press': 50, 'row': 70, 'pulldown': 70,
            'pullup': 10, 'squat': 100, 'deadlift': 120, 'leg_press': 140, 'lunge': 40,
            'curl': 18, 'tricep_pushdown': 35, 'lateral_raise': 10, 'plank': 1, 'leg_raise': 1,
        },
        layoffs=[(27, 28), (53, 54), (79, 80), (105, 106), (131, 132), (157, 158),
                 (183, 184), (209, 210), (235, 236)],
    ),
}

BODY_PARTS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio']
ACTIVE_RANKS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core']  # v1: cardio earns nothing yet

CLASS_BY_DOMINANT = {
    'arms': 'Berserker', 'chest': 'Bulwark', 'back': 'Sentinel',
    'legs': 'Pathfinder', 'shoulders': 'Atlas', 'core': 'Anchor',
    'cardio': 'Wayfarer',
}

# ============================================================================
# Math helpers
# ============================================================================

def xp_for_rank(n: int) -> float:
    """Cumulative XP to reach rank n (rank 1 = 0 XP)."""
    if n <= 1:
        return 0
    return XP_BASE * (XP_GROWTH ** (n - 1) - 1) / (XP_GROWTH - 1)


def rank_for_xp(total_xp: float) -> int:
    n = 1
    while n < 99 and xp_for_rank(n + 1) <= total_xp:
        n += 1
    return n


def character_level(ranks: dict[str, int]) -> int:
    """v1: cardio excluded from character level (deferred to v2). When cardio
    ships, swap ACTIVE_RANKS to include it — denominator stays 4."""
    active = {k: v for k, v in ranks.items() if k in ACTIVE_RANKS}
    total = sum(active.values())
    return max(1, (total - len(active)) // CHAR_LEVEL_DENOMINATOR + 1)


def intensity_for_reps(reps: int) -> float:
    matched = 1.0
    for r, mult in INTENSITY_BY_REPS:
        if reps >= r:
            matched = mult
        else:
            break
    return matched


def dominant_class(ranks: dict[str, int]) -> str:
    strength = {k: v for k, v in ranks.items() if k != 'cardio'}
    vals = list(strength.values())
    if max(vals) > 0 and (max(vals) - min(vals)) / max(vals) <= ASCENDANT_BALANCE_THRESHOLD and min(vals) >= ASCENDANT_MIN_RANK:
        return 'Ascendant'
    dom = max(strength, key=strength.get)
    return CLASS_BY_DOMINANT.get(dom, 'Initiate')


# ============================================================================
# Per-set XP — strength_mult + Phase 24a difficulty_mult
# ============================================================================

def compute_set_xp(
    exercise: str,
    weight: float,
    reps: int,
    novelty_count: dict[str, float],
    weekly_count: dict[str, float],
    peak_loads: dict[str, float],
    difficulty_mult: float,
) -> tuple[dict[str, float], float]:
    """Returns (xp_per_body_part, total_volume_load_for_vitality).

    `difficulty_mult` is required (no default) — same convention as Dart's
    `XpCalculator.computeSetXp`. Caller resolves the value via
    `difficulty_mult_for_slug(slug)` (real slug) or
    `difficulty_mult_for_alias(alias)` (simulator short alias). Applied as
    the final multiplier in the chain BEFORE the per-body-part attribution
    split — mirrors `XpCalculator` byte-for-byte:

        set_xp = base × intensity × strength × novelty × cap × difficulty_mult
        per_bp_xp = set_xp × attribution[bp]
    """
    volume_load = max(1.0, weight * reps)
    base_xp = volume_load ** VOLUME_EXPONENT
    intensity = intensity_for_reps(reps)

    peak_load = peak_loads.get(exercise, weight)
    if weight > peak_load:
        peak_loads[exercise] = weight
        peak_load = weight
    strength_mult = max(STRENGTH_MULT_FLOOR, min(1.0, weight / peak_load if peak_load > 0 else 1.0))

    distribution = ATTRIBUTION.get(exercise, {})

    awarded: dict[str, float] = {}
    for body_part, share in distribution.items():
        novelty = math.exp(-novelty_count[body_part] / NOVELTY_DENOMINATOR)
        cap_mult = OVER_CAP_MULTIPLIER if weekly_count[body_part] >= WEEKLY_CAP_SETS else 1.0
        xp = base_xp * intensity * strength_mult * novelty * cap_mult * difficulty_mult * share
        awarded[body_part] = xp

    for body_part, share in distribution.items():
        novelty_count[body_part] += share
        weekly_count[body_part] += share

    return awarded, volume_load


# ============================================================================
# Vitality — asymmetric EWMA per body part
# ============================================================================

def update_vitality(
    body_part: str,
    weekly_volume: float,
    ewma: dict[str, float],
    peak: dict[str, float],
) -> None:
    """Update body-part EWMA with asymmetric time constants. Peak is permanent
    (never decays). Vitality % is derived as ewma / peak when consumers ask."""
    prior = ewma.get(body_part, 0.0)
    if weekly_volume >= prior:
        alpha = 1.0 - math.exp(-1.0 / VITALITY_TAU_UP_WEEKS)
    else:
        alpha = 1.0 - math.exp(-1.0 / VITALITY_TAU_DOWN_WEEKS)
    new_ewma = alpha * weekly_volume + (1 - alpha) * prior
    ewma[body_part] = new_ewma
    if new_ewma > peak.get(body_part, 0.0):
        peak[body_part] = new_ewma


def vitality_pct(body_part: str, ewma: dict[str, float], peak: dict[str, float]) -> float:
    p = peak.get(body_part, 0.0)
    if p <= 0:
        return 0.0
    return min(1.0, ewma.get(body_part, 0.0) / p)


# ============================================================================
# Simulation
# ============================================================================

def progression_rate(archetype: Archetype, week: int) -> float:
    base = PROGRESSION_RATES[archetype.progression]
    if archetype.progression != 'beginner':
        return base
    if week <= NEWBIE_DECAY_WEEKS:
        return base
    decay = (week - NEWBIE_DECAY_WEEKS) / 26.0
    intermediate_rate = PROGRESSION_RATES['intermediate']
    return max(intermediate_rate, base - (base - intermediate_rate) * min(1.0, decay))


def is_layoff_week(archetype: Archetype, week: int) -> bool:
    return any(start <= week <= end for start, end in archetype.layoffs)


def simulate(archetype: Archetype, weeks: int) -> list[dict]:
    xp_pool = {p: 0.0 for p in BODY_PARTS}
    weights = dict(archetype.starting_weights)
    peak_loads: dict[str, float] = dict(archetype.starting_weights)
    schedule = WEEK_SCHEDULES[archetype.sessions_per_week]
    vit_ewma: dict[str, float] = {}
    vit_peak: dict[str, float] = {}
    snapshots = []

    for week in range(1, weeks + 1):
        weekly_count: dict[str, float] = defaultdict(float)
        weekly_volume_per_part: dict[str, float] = defaultdict(float)
        layoff = is_layoff_week(archetype, week)

        if not layoff:
            for day in schedule:
                novelty_count: dict[str, float] = defaultdict(float)
                for exercise, n_sets, reps in DAY_TEMPLATES[day]:
                    w = weights.get(exercise, 1)
                    distribution = ATTRIBUTION.get(exercise, {})
                    diff_mult = difficulty_mult_for_alias(exercise)
                    for _ in range(n_sets):
                        awarded, vol = compute_set_xp(
                            exercise, w, reps, novelty_count, weekly_count, peak_loads,
                            difficulty_mult=diff_mult,
                        )
                        for bp, xp in awarded.items():
                            xp_pool[bp] += xp
                        for bp, share in distribution.items():
                            weekly_volume_per_part[bp] += vol * share

            rate = progression_rate(archetype, week)
            for ex in weights:
                weights[ex] *= rate

        for bp in ACTIVE_RANKS:
            update_vitality(bp, weekly_volume_per_part.get(bp, 0.0), vit_ewma, vit_peak)

        ranks = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
        snapshots.append({
            'week': week,
            'ranks': ranks,
            'character_level': character_level(ranks),
            'total_xp': {p: int(v) for p, v in xp_pool.items()},
            'class': dominant_class(ranks),
            'vitality': {p: vitality_pct(p, vit_ewma, vit_peak) for p in ACTIVE_RANKS},
            'is_layoff': layoff,
        })

    return snapshots


# ============================================================================
# Reporting
# ============================================================================

def print_archetype(name: str, snapshots: list[dict], milestones: list[int]) -> None:
    print(f"\n=== {name.upper()} ===")
    archetype = ARCHETYPES[name]
    layoff_note = f"  |  Layoffs: {archetype.layoffs}" if archetype.layoffs else ""
    print(f"Schedule: {archetype.sessions_per_week} sessions/week  |  "
          f"Progression: {PROGRESSION_RATES[archetype.progression]}× per week{layoff_note}")
    header = f"{'Wk':>4} {'Lvl':>4}  {'Chst':>4} {'Back':>4} {'Legs':>4} {'Shld':>4} {'Arms':>4} {'Core':>4}    {'Class':<11}  {'Total XP':>10}"
    print(header)
    print('-' * len(header))
    for snap in snapshots:
        if snap['week'] not in milestones:
            continue
        r = snap['ranks']
        total_xp = sum(snap['total_xp'].values())
        marker = '*' if snap['is_layoff'] else ' '
        print(f"{snap['week']:>3}{marker} {snap['character_level']:>4}  "
              f"{r['chest']:>4} {r['back']:>4} {r['legs']:>4} {r['shoulders']:>4} {r['arms']:>4} {r['core']:>4}    "
              f"{snap['class']:<11}  {total_xp:>10,}")


def print_vitality_trajectory(name: str, snapshots: list[dict], parts: list[str]) -> None:
    print(f"\n--- VITALITY TRAJECTORY ({name}) ---")
    header = f"{'Wk':>4} " + ' '.join(f"{bp[:4]:>6}" for bp in parts) + "   note"
    print(header)
    print('-' * len(header))
    sample_weeks = list(range(1, len(snapshots) + 1, max(1, len(snapshots) // 30)))
    if snapshots:
        sample_weeks.append(len(snapshots))
    for w in sorted(set(sample_weeks)):
        snap = snapshots[w - 1]
        vits = ' '.join(f"{int(snap['vitality'][bp] * 100):>5}%" for bp in parts)
        marker = ' (layoff)' if snap['is_layoff'] else ''
        print(f"{w:>4} {vits}{marker}")


def print_xp_curve_summary() -> None:
    print("\n=== RANK XP CURVE (cumulative XP needed to reach rank N) ===")
    samples = [2, 5, 10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 99]
    print(f"{'Rank':>5}  {'XP cum':>14}  {'XP delta':>14}")
    prev = 0
    for n in samples:
        cur = int(xp_for_rank(n))
        print(f"{n:>5}  {cur:>14,}  {cur - prev:>14,}")
        prev = cur


# ============================================================================
# Main
# ============================================================================

if __name__ == '__main__':
    print("RepSaga RPG XP Simulation (with strength_mult + asymmetric Vitality)")
    print("=" * 70)
    print(f"XP curve: {XP_BASE} × {XP_GROWTH}^(n-1)")
    print(f"Volume exp: {VOLUME_EXPONENT}  |  Novelty denom: {NOVELTY_DENOMINATOR}  |  Weekly cap: {WEEKLY_CAP_SETS} sets")
    print(f"Strength_mult floor: {STRENGTH_MULT_FLOOR}")
    print(f"Vitality tau_up: {VITALITY_TAU_UP_WEEKS}wk  |  tau_down: {VITALITY_TAU_DOWN_WEEKS}wk  |  peak permanent: {VITALITY_PEAK_PERMANENT}")
    print(f"Char level denom: {CHAR_LEVEL_DENOMINATOR}")

    print_xp_curve_summary()

    milestones = [1, 2, 4, 8, 12, 26, 52, 104, 156, 208, 260]

    print("\n\n" + "=" * 70)
    print("BASELINE ARCHETYPES (no detraining)")
    print("=" * 70)
    for archetype_name in ['beginner', 'intermediate', 'advanced', 'stagnant_lifter']:
        snapshots = simulate(ARCHETYPES[archetype_name], weeks=260)
        print_archetype(archetype_name, snapshots, milestones)
        last = snapshots[-1]
        max_rank = max(last['ranks'].values())
        avg_vit = sum(last['vitality'].values()) / len(last['vitality'])
        print(f"\nFINAL: Lvl {last['character_level']}  |  max rank {max_rank}  |  "
              f"class {last['class']}  |  avg Vitality {avg_vit*100:.0f}%  |  "
              f"total XP {sum(last['total_xp'].values()):,}")

    print("\n\n" + "=" * 70)
    print("DETRAINING SCENARIOS")
    print("=" * 70)

    print("\n=== COMEBACK KID (1yr train -> 6mo off -> resume) ===")
    snaps = simulate(ARCHETYPES['comeback_kid'], weeks=260)
    detail_milestones = [4, 13, 26, 39, 52, 60, 65, 70, 78, 80, 85, 92, 104, 130, 156, 208, 260]
    print_archetype('comeback_kid', snaps, detail_milestones)
    print_vitality_trajectory('comeback_kid', snaps, ['chest', 'legs', 'arms'])

    print("\n=== VACATIONER (2wk break every 6mo) ===")
    snaps = simulate(ARCHETYPES['vacationer'], weeks=260)
    print_archetype('vacationer', snaps, milestones)
    print_vitality_trajectory('vacationer', snaps, ['chest', 'legs', 'arms'])
