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
     (Dart `XpCalculator.computeSetXp` — live save path; the Dart calculator
     is bodyweight-agnostic — production callers pre-convert sets.weight to
     `effective_load` before invoking computeSetXp)
  2. test/fixtures/generate_rpg_fixtures.py
     (regenerate `rpg_xp_fixtures.json` so Dart parity tests stay green)
  3. supabase/migrations/00040_*.sql, 00050_*.sql, 00052_*.sql,
     00054_record_xp_with_difficulty_mult.sql, and
     00057_record_xp_with_bodyweight_load.sql
     (PL/pgSQL `record_set_xp` / `record_session_xp_batch` /
     `_rpg_backfill_chunk` — live persist path; per-exercise difficulty_mult
     fetched from `exercises.difficulty_mult` and applied at the same
     position in the chain; per-exercise `uses_bodyweight_load` from
     `exercises.uses_bodyweight_load` (00056) drives effective_weight =
     COALESCE(weight,0) + COALESCE(bodyweight,0) when TRUE — applied to
     volume_load + strength_mult numerator BEFORE the chain in 00057)

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
#
# CANONICAL constants below are the SHIPPED values — must stay byte-for-byte
# identical to:
#   * `lib/features/rpg/domain/xp_calculator.dart`
#   * `supabase/migrations/00040_*.sql`, `00050_*.sql`, `00052_*.sql`,
#     `00054_*.sql`, `00057_*.sql`, `00059_*.sql` (PL/pgSQL hardcoded values)
#   * `test/fixtures/rpg_xp_fixtures.json` (regenerated via
#     `test/fixtures/generate_rpg_fixtures.py`, which imports THIS module
#     and reads the constants directly)
#
# Changing a CANONICAL value here without the matching cross-system update
# will break the Dart parity tests on the next `make ci`.
#
# Phase 24d (2026-05-15) propagated the iter-3 calibration sign-off into the
# canonical constants — `VOLUME_EXPONENT` 0.65 → 0.60, `WEEKLY_CAP_SETS`
# 20 → 15, `OVER_CAP_MULTIPLIER` 0.5 → 0.3, plus a per-slug `-0.05` delta
# applied to 28 curated T4 slugs in `DIFFICULTY_MULT_BY_SLUG` below (and in
# `supabase/migrations/00059_phase24d_calibration_propagation.sql`).
# `_CALIBRATION_*` override scaffolding is no longer needed at the call
# site — the 6 calibration archetypes now read canonical constants like
# every other code path.

# Per-rank XP curve: xp_to_next(n) = XP_BASE × XP_GROWTH^(n-1)
XP_BASE = 60
XP_GROWTH = 1.10

# Per-set XP formula (CANONICAL — Phase 24d propagation)
VOLUME_EXPONENT = 0.60         # base = (weight × reps)^this; sub-linear so 10× vol ≠ 10× XP
NOVELTY_DENOMINATOR = 15       # higher = slower diminishing returns within a session
WEEKLY_CAP_SETS = 15           # effective sets per body part before over-cap multiplier kicks in
OVER_CAP_MULTIPLIER = 0.3      # multiplier applied beyond weekly cap (Phase 24d: 0.5 → 0.3)

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
    # Phase 24b additions (00055) — pistol_squat and archer_push_up are
    # consumed by the Phase 24d bodyweight_only calibration archetype. The
    # rest of the 49 Phase 24b new defaults aren't exercised by current
    # archetypes (so are not mirrored here yet) — adding them is a no-op for
    # fixture replay but a follow-up sweep can complete the parity later.
    #
    # Phase 24d propagation: 23 of the 28 curated T4 slugs were already in
    # this dict; their values dropped by 0.05 to mirror migration 00059's
    # `UPDATE exercises SET difficulty_mult = round(difficulty_mult - 0.05, 2)`
    # on the 28-slug T4 set. The other 5 (`belt_squat`, `pendulum_squat`,
    # `glute_ham_raise`, `cable_pullover`, `cable_overhead_extension`) are
    # Phase-24b additions still absent from this mirror — they fall through
    # to the 1.0 default for sim purposes; production reads the migrated
    # column value (0.92, 0.92, 0.94, 0.96, 0.92 respectively).
    'archer_push_up': 1.21, 'pistol_squat': 1.17,
    'ab_rollout': 1.09, 'arnold_press': 1.09,
    'back_extension': 0.89, 'band_face_pull': 0.94, 'band_pull_apart': 0.89, 'band_squat': 0.92,
    'barbell_bench_press': 1.09, 'barbell_bent_over_row': 1.19, 'barbell_curl': 0.87,
    'barbell_shrug': 0.89, 'barbell_squat': 1.19, 'bench_dip': 1.09, 'bicycle_crunch': 0.85,
    'bodyweight_squat': 1.07, 'box_jump': 1.25, 'bulgarian_split_squat': 1.07,
    'cable_chest_press': 0.94, 'cable_crossover': 0.94, 'cable_crunch': 0.90, 'cable_curl': 0.87,
    'cable_face_pull': 0.94, 'cable_front_raise': 0.89, 'cable_glute_kickback': 0.92,
    'cable_hammer_curl': 0.87, 'cable_lateral_raise': 0.89, 'cable_pull_through': 0.94,
    'cable_rear_delt_fly': 0.89, 'cable_row': 0.94, 'cable_woodchop': 0.94,
    'calf_raise': 0.85, 'chest_supported_row': 1.07, 'chin_up': 1.19,
    'close_grip_bench_press': 1.09, 'close_grip_lat_pulldown': 0.94, 'close_grip_push_up': 1.11,
    'concentration_curl': 0.87, 'crunches': 0.85,
    'dead_bug': 0.85, 'deadlift': 1.21, 'decline_barbell_bench_press': 1.09,
    'decline_dumbbell_press': 1.09, 'decline_push_up': 1.11, 'diamond_push_up': 1.11,
    'dips': 1.19, 'donkey_kick': 0.87, 'dumbbell_bench_press': 1.09,
    'dumbbell_calf_raise': 0.85, 'dumbbell_curl': 0.87, 'dumbbell_fly': 0.89,
    'dumbbell_lunges': 1.07, 'dumbbell_pullover': 0.91, 'dumbbell_row': 1.09,
    'dumbbell_shoulder_press': 1.09, 'dumbbell_shrug': 0.89, 'dumbbell_tricep_extension': 0.87,
    'elliptical': 0.85, 'ez_bar_curl': 0.87,
    'face_pull': 0.94, 'farmer_s_walk': 1.11, 'flutter_kick': 0.85,
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
    'lat_pulldown': 0.94, 'lateral_raise': 0.89, 'leg_abductor': 0.85, 'leg_adductor': 0.85,
    'leg_curl': 0.85, 'leg_extension': 0.85, 'leg_press': 0.92, 'leg_raise': 0.85,
    'machine_chest_press': 0.94, 'machine_row': 0.94, 'machine_shoulder_press': 0.94,
    'mountain_climber': 1.09,
    'nordic_curl': 0.87,
    'overhead_press': 1.19, 'overhead_tricep_extension': 0.87,
    'pallof_press': 0.92, 'pec_deck': 0.89, 'pendlay_row': 1.19,
    'plank': 0.89, 'plank_up_down': 1.09, 'preacher_curl': 0.87,
    'pull_up': 1.19, 'push_press': 1.25, 'push_up': 1.11,
    'rack_pull': 1.21, 'rear_delt_fly': 0.89, 'reverse_crunch': 0.85, 'reverse_curl': 0.87,
    'reverse_hyperextension': 0.94, 'reverse_lunges': 1.07, 'reverse_pec_deck': 0.89,
    'reverse_wrist_curl': 0.87, 'romanian_deadlift': 1.09, 'rope_pushdown': 0.92,
    'rowing_machine': 0.85, 'russian_twist': 0.85,
    'seal_row': 1.07, 'seated_calf_raise': 0.85, 'side_plank': 0.89,
    'single_leg_glute_bridge': 0.87, 'single_leg_leg_press': 0.92, 'sit_up': 0.85,
    'skull_crusher': 0.87, 'spider_curl': 0.87, 'stationary_bike': 0.85,
    'step_up': 1.07, 'straight_arm_pulldown': 0.89, 'sumo_deadlift': 1.21,
    't_bar_row': 1.19, 'toe_touch': 0.85, 'treadmill': 0.85, 'tricep_pushdown': 0.92,
    'upright_row': 0.94,
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
    'tricep_pushdown': 'tricep_pushdown',             # 0.92
    'row':             'barbell_bent_over_row',       # 1.19
    'pulldown':        'lat_pulldown',                # 0.94
    'pullup':          'pull_up',                     # 1.19
    'curl':            'barbell_curl',                # 0.87
    'squat':           'barbell_squat',               # 1.19
    'deadlift':        'deadlift',                    # 1.21
    'leg_press':       'leg_press',                   # 0.92
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
# Bodyweight-as-load semantics (Phase 24c)
# ============================================================================
#
# Mirrors `exercises.uses_bodyweight_load` populated by
# `supabase/migrations/00056_add_bodyweight_load_semantics.sql`. The 20-element
# list is the canonical curation source — Python sim, SQL RPCs (00057), and
# Dart Exercise model must agree.
#
# For exercises in this set, the live persist path (00057) computes:
#
#   effective_weight = COALESCE(sets.weight, 0) + COALESCE(profiles.bodyweight_kg, 0)
#
# which feeds `volume_load` and `strength_mult`'s numerator. For all other
# exercises, effective_weight degrades to `COALESCE(sets.weight, 0)` —
# pre-Phase-24c semantics. NULL bodyweight degrades gracefully to entered-only.
#
# Note: the Dart `XpCalculator.computeSetXp` is bodyweight-AGNOSTIC. Production
# callers pre-convert and pass `effective_load` as `weight_kg`. The fixture
# generator does the same — it computes `effective_load` here and feeds it
# into `weight_kg` slots so the existing fixture-driven Dart parity tests
# stay green without code change.

USES_BODYWEIGHT_LOAD_BY_SLUG = frozenset({
    # Pull family (T2)
    "pull_up", "chin_up", "wide_grip_pull_up",
    # Dip family (T2)
    "dips", "ring_dip", "muscle_up",
    # Push-up family (T3 + archer T2)
    "push_up", "wide_push_up", "incline_push_up", "decline_push_up",
    "diamond_push_up", "close_grip_push_up", "archer_push_up",
    # Squat family
    "bodyweight_squat", "pistol_squat",
    # Lunge
    "walking_lunges",
    # Hanging
    "hanging_leg_raise",
    # Olympic gymnastics
    "handstand_push_up",
    # Body pull
    "inverted_row",
    # Eccentric (judgment call — telemetry-flagged post-launch)
    "nordic_curl",
})


def uses_bodyweight_load(slug: str) -> bool:
    """Mirrors `exercises.uses_bodyweight_load` from migration 00056. The
    20-element list is the canonical source; Python sim, SQL RPCs (00057),
    and Dart helpers must agree.

    Slugs not in the curated set return False (matches the column DEFAULT
    FALSE for user-created and non-curated exercises)."""
    return slug in USES_BODYWEIGHT_LOAD_BY_SLUG


def effective_weight(
    slug: str,
    entered_weight: float,
    bodyweight_kg: float | None,
) -> float:
    """Compute effective load for the volume + strength formula.

    Mirrors `00057_record_xp_with_bodyweight_load.sql`'s `v_effective_weight`
    CASE expression byte-for-byte:

        effective_weight = CASE WHEN uses_bodyweight_load
                                THEN COALESCE(weight, 0) + COALESCE(bw, 0)
                                ELSE COALESCE(weight, 0)
                           END

    NULL bodyweight degrades to entered-weight-only (graceful fallback) — a
    user who hasn't set their bodyweight yet still earns XP, just slightly
    under-counted until they enter their mass.
    """
    if uses_bodyweight_load(slug):
        return (entered_weight or 0.0) + (bodyweight_kg or 0.0)
    return entered_weight or 0.0


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

    # Phase 24c: user bodyweight in kg. Default 70 kg (framework example).
    # Bodyweight is held constant across the simulation — gym training
    # does not meaningfully shift bodyweight on a 5-year horizon for the
    # archetypes we model (advanced lifters fluctuate ±2-3 kg around a
    # set point). If we add cut/bulk archetypes later, this becomes a
    # callable. NULL semantics live in the fixture generator, not here.
    bodyweight_kg: float = 70.0


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
    bodyweight_kg: float | None = None,
    slug: str | None = None,
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

    Phase 24c bodyweight-as-load: if `slug` is curated in
    `USES_BODYWEIGHT_LOAD_BY_SLUG`, `effective_weight = entered_weight +
    (bodyweight_kg or 0)` is used for both `volume_load` and the
    `strength_mult` numerator (mirrors 00057). Peak_loads still tracks
    ENTERED weight only — see migration 00057 header for the rationale.
    Default args (`bodyweight_kg=None, slug=None`) keep backward compat
    for callers that don't yet thread bodyweight; in that case effective
    weight degrades to entered weight (pre-24c semantics).

    Phase 24d propagation: the formerly-provisional overrides
    (`_CALIBRATION_VOLUME_EXPONENT/WEEKLY_CAP_SETS/OVER_CAP_MULTIPLIER`)
    are now the canonical module constants. Every code path — calibration
    archetypes, consistency archetypes, fixture-gen, Dart parity — reads
    `VOLUME_EXPONENT`, `WEEKLY_CAP_SETS`, `OVER_CAP_MULTIPLIER` directly.
    """
    # Phase 24c: resolve slug. If not provided, fall back to `exercise` (the
    # simulator's short alias). uses_bodyweight_load() returns False for the
    # short aliases (they're not in the 20-slug curation set), which matches
    # the desired backward-compat behavior — the simulator's archetype
    # playback uses 'pullup' (alias) NOT 'pull_up' (real slug), so passing
    # `slug=SIM_ALIAS_TO_DEFAULT_SLUG[exercise]` is the responsibility of
    # the simulator caller (see `simulate()`).
    resolved_slug = slug if slug is not None else exercise
    eff_weight = effective_weight(resolved_slug, weight, bodyweight_kg)

    # Phase 24c: volume_load + base_xp consume effective_weight.
    volume_load = max(1.0, eff_weight * reps)
    base_xp = volume_load ** VOLUME_EXPONENT
    intensity = intensity_for_reps(reps)

    # Phase 24c: peak_loads tracks ENTERED weight (not effective) — matches
    # the 00057 writer-site guard. The strength_mult numerator is still
    # effective_weight (favorable for weighted bodyweight, neutral for pure
    # bodyweight since peak stays 0 → short-circuit returns 1.0).
    peak_load = peak_loads.get(exercise, weight)
    if weight > peak_load:
        peak_loads[exercise] = weight
        peak_load = weight
    if peak_load > 0:
        strength_mult = max(STRENGTH_MULT_FLOOR, min(1.0, eff_weight / peak_load))
    else:
        strength_mult = 1.0

    # Phase 24d overlay: calibration archetypes use real default slugs
    # (e.g. `barbell_bench_press`) that aren't in the alias-based
    # `ATTRIBUTION` map. The overlay dict (populated below the function
    # by the calibration block) is consulted FIRST so calibration runs
    # see real-slug splits without mutating `ATTRIBUTION` itself —
    # `test/fixtures/generate_rpg_fixtures.py` iterates `ATTRIBUTION`
    # to build its parity cases, so adding entries there would break
    # the byte-identical fixture regen check.
    distribution = (
        _CALIBRATION_ATTRIBUTION.get(exercise)
        if exercise in _CALIBRATION_ATTRIBUTION
        else ATTRIBUTION.get(exercise, {})
    )

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
                    # Phase 24c: resolve simulator alias → real slug so
                    # uses_bodyweight_load() consults the same 20-slug
                    # curation set as the SQL RPCs (00057). For aliases
                    # not in SIM_ALIAS_TO_DEFAULT_SLUG (synthetic, no
                    # real-world analog) the resolved slug is the alias
                    # itself — uses_bodyweight_load() returns False, so
                    # behavior matches pre-24c.
                    real_slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                    for _ in range(n_sets):
                        awarded, vol = compute_set_xp(
                            exercise, w, reps, novelty_count, weekly_count, peak_loads,
                            difficulty_mult=diff_mult,
                            bodyweight_kg=archetype.bodyweight_kg,
                            slug=real_slug,
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
# Phase 24d — Calibration archetypes (6 profiles × 12 weeks)
# ============================================================================
#
# CONSISTENCY archetypes above (beginner / intermediate / advanced /
# stagnant_lifter / comeback_kid / vacationer) validate detraining + the
# strength_mult anti-stagnation invariant over a 5-year horizon. They also
# back the fixture replay in `test/fixtures/generate_rpg_fixtures.py` — so
# their shape MUST NOT CHANGE.
#
# CALIBRATION archetypes here validate Phase 24's pass criteria
# (docs/PROJECT.md §3 → Phase 24d) — does the formula produce sensible
# 12-week progression curves across the realistic user spectrum?
#
# Six archetypes per the spec table:
#   beginner_24d              — light starting weights, progressive overload
#   intermediate_compound     — 5×5 T2/T3 mix
#   advanced_powerlifter      — heavy low-rep T2 near 90% 1RM
#   hypertrophy_bodybuilder   — 5-6×/wk high-volume T3+T5 isolation-heavy
#   bodyweight_only           — T2/T3 bodyweight curated set (uses 00056 load)
#   machine_only              — T4/T5 machine-only
#
# Design choices:
#   * Each calibration archetype carries its own per-day template list
#     (`day_templates: dict[str, list[tuple[str, int, int]]]`). The classic
#     `DAY_TEMPLATES` / `WEEK_SCHEDULES` pair is fine for the homogeneous
#     consistency archetypes but the calibration set is intentionally
#     heterogeneous (a powerlifter does NOT do the bodybuilder's day) so
#     each archetype self-describes.
#   * Exercise IDs in calibration day templates are REAL DEFAULT SLUGS
#     (`barbell_bench_press`, `pull_up`, etc.) — not short aliases. This
#     keeps the data closer to production semantics + lets
#     `uses_bodyweight_load` resolve against the canonical 20-slug curation
#     set without an alias hop. The simulator's existing alias lookup is
#     extended below (`SIM_ALIAS_TO_DEFAULT_SLUG`) with identity entries so
#     real slugs flow through the same `difficulty_mult_for_alias()` path.
#   * Per-archetype progression rate per the spec: ~2.5 kg/wk compound,
#     ~1 kg/wk isolation for the beginner; ~1 kg/wk compound for
#     intermediate; ~0.5 kg/wk for advanced powerlifter; modest progression
#     for hypertrophy bodybuilder; bodyweight progression via added reps
#     (modeled here as bodyweight_kg fixed + entered_weight increment to
#     proxy weighted-vest progression, since the simulator's weekly cap is
#     per-set not per-rep). Machine-only progression is on entered weight.
#   * The existing `simulate()` function uses a SHARED `DAY_TEMPLATES` +
#     `WEEK_SCHEDULES` lookup. Calibration uses a parallel function
#     `simulate_calibration()` that consumes the archetype's own templates
#     + schedule. Two functions, one shared per-set / per-week / vitality
#     core — keeps the calibration path additive (zero blast radius on
#     fixture replay).

# Identity entries so real default slugs flow through `difficulty_mult_for_alias()`
# (which looks up via SIM_ALIAS_TO_DEFAULT_SLUG). Without these, real slugs
# would fall through to the 1.0 default. Listed alphabetically by source
# archetype usage; comment lists the difficulty_mult value resolved via
# DIFFICULTY_MULT_BY_SLUG to make the table easy to audit at a glance.
_CALIBRATION_REAL_SLUG_IDENTITY = {
    # Already in SIM_ALIAS_TO_DEFAULT_SLUG via alias (skip): barbell_bench_press,
    # incline_barbell_bench_press, overhead_press, lateral_raise, tricep_pushdown,
    # barbell_bent_over_row, lat_pulldown, pull_up, barbell_curl, barbell_squat,
    # deadlift, leg_press, walking_lunges, plank, leg_raise.
    'archer_push_up':           'archer_push_up',           # 1.21 (T2 bodyweight)
    'cable_crossover':          'cable_crossover',          # 0.94 (T4)
    'cable_curl':               'cable_curl',               # 0.87 (T5)
    'cable_lateral_raise':      'cable_lateral_raise',      # 0.89 (T5)
    'calf_raise':               'calf_raise',               # 0.85 (T5)
    'chin_up':                  'chin_up',                  # 1.19 (T2 bodyweight)
    'close_grip_push_up':       'close_grip_push_up',       # 1.11 (T3 bodyweight)
    'decline_push_up':          'decline_push_up',          # 1.11 (T3 bodyweight)
    'diamond_push_up':          'diamond_push_up',          # 1.11 (T3 bodyweight)
    'dips':                     'dips',                     # 1.19 (T2 bodyweight)
    'dumbbell_curl':            'dumbbell_curl',            # 0.87 (T5)
    'dumbbell_fly':             'dumbbell_fly',             # 0.89 (T5)
    'hammer_curl':              'hammer_curl',              # 0.87 (T5)
    'hanging_leg_raise':        'hanging_leg_raise',        # 1.09 (T3 bodyweight)
    'hip_thrust':               'hip_thrust',               # 1.07 (T3)
    'leg_abductor':             'leg_abductor',             # 0.85 (T5)
    'leg_adductor':             'leg_adductor',             # 0.85 (T5)
    'leg_curl':                 'leg_curl',                 # 0.85 (T5)
    'leg_extension':            'leg_extension',            # 0.85 (T5)
    'machine_chest_press':      'machine_chest_press',      # 0.94 (T4)
    'machine_row':              'machine_row',              # 0.94 (T4)
    'machine_shoulder_press':   'machine_shoulder_press',   # 0.94 (T4)
    'pendlay_row':              'pendlay_row',              # 1.19 (T2)
    'pistol_squat':             'pistol_squat',             # 1.17 (T2 bodyweight)
    'push_up':                  'push_up',                  # 1.11 (T3 bodyweight)
    'romanian_deadlift':        'romanian_deadlift',        # 1.09 (T3)
    'wide_push_up':             'wide_push_up',             # 1.11 (T3 bodyweight)
}
SIM_ALIAS_TO_DEFAULT_SLUG.update(_CALIBRATION_REAL_SLUG_IDENTITY)


# Body-part attribution for the real default slugs used by calibration
# archetypes. Authoritative source for every split is the production
# migration's `xp_attribution` jsonb column:
#
#   * `supabase/migrations/00040_rpg_system_v1.sql` (lines 1762-1925) for
#     the original 150 default exercises.
#   * `supabase/migrations/00055_phase24b_new_default_exercises.sql` for the
#     50 Phase-24b additions (`pistol_squat`, `archer_push_up`, etc.).
#
# This dict MUST stay byte-equivalent to the migration's jsonb payloads for
# the slugs it lists — calibration is meant to reflect production XP
# attribution, not a synthetic proxy. The Phase 24d-2 audit (May 2026) caught
# 21 slugs where the calibration map either was missing entirely (silent
# zero-XP bug — six slugs) or had drifted from the migration (15 slugs).
# All 21 corrected below.
#
# Lookup order: `_calibration_attribution()` consults this map FIRST so
# real-slug splits never fall through to the alias-based `ATTRIBUTION` dict
# (which is keyed by Python-sim aliases like `pullup`, `squat`, `row` and
# does not resolve real slugs like `pull_up`, `barbell_squat`,
# `barbell_bent_over_row`). Mutating `ATTRIBUTION` itself would change the
# fixture-replay surface — calibration adds the fix here so blast radius is
# zero for `test/fixtures/generate_rpg_fixtures.py`.
_CALIBRATION_ATTRIBUTION = {
    # Push (free weight) — 00040 lines 1772-1790
    'barbell_bench_press':         {'chest': 0.70, 'shoulders': 0.20, 'arms': 0.10},
    'incline_barbell_bench_press': {'chest': 0.60, 'shoulders': 0.30, 'arms': 0.10},
    'overhead_press':              {'shoulders': 0.60, 'arms': 0.20, 'core': 0.20},
    # Push (machine / cable) — 00040 lines 1780-1798
    'machine_chest_press':         {'chest': 0.75, 'shoulders': 0.15, 'arms': 0.10},
    'machine_shoulder_press':      {'shoulders': 0.70, 'arms': 0.20, 'core': 0.10},
    'cable_crossover':             {'chest': 0.85, 'shoulders': 0.10, 'arms': 0.05},
    # Push (bodyweight push-up family) — 00040 lines 1784-1816
    'push_up':                     {'chest': 0.65, 'shoulders': 0.20, 'arms': 0.10, 'core': 0.05},
    'wide_push_up':                {'chest': 0.75, 'shoulders': 0.15, 'arms': 0.05, 'core': 0.05},
    'close_grip_push_up':          {'arms': 0.50, 'chest': 0.40, 'shoulders': 0.05, 'core': 0.05},
    'decline_push_up':             {'chest': 0.70, 'shoulders': 0.20, 'arms': 0.05, 'core': 0.05},
    'diamond_push_up':             {'chest': 0.50, 'arms': 0.40, 'shoulders': 0.05, 'core': 0.05},
    # Push (Phase 24b) — 00055 line 213
    'archer_push_up':              {'chest': 0.55, 'arms': 0.25, 'shoulders': 0.15, 'core': 0.05},
    # Push (dip — T2 bodyweight) — 00040 line 1818
    'dips':                        {'chest': 0.45, 'arms': 0.40, 'shoulders': 0.15},
    # Pull (free weight) — 00040 lines 1821-1822, 1844
    'barbell_bent_over_row':       {'back': 0.70, 'arms': 0.20, 'core': 0.10},
    'pendlay_row':                 {'back': 0.70, 'arms': 0.20, 'core': 0.10},
    'barbell_curl':                {'arms': 0.90, 'back': 0.10},
    # Pull (machine / cable) — 00040 lines 1828, 1831, 1850
    'machine_row':                 {'back': 0.75, 'arms': 0.20, 'core': 0.05},
    'lat_pulldown':                {'back': 0.75, 'arms': 0.20, 'core': 0.05},
    'cable_curl':                  {'arms': 0.90, 'back': 0.10},
    # Pull (bodyweight) — 00040 lines 1834-1835
    'pull_up':                     {'back': 0.65, 'arms': 0.25, 'core': 0.10},
    'chin_up':                     {'back': 0.55, 'arms': 0.35, 'core': 0.10},
    # Legs (free weight / hip hinge) — 00040 lines 1860, 1869, 1871
    'barbell_squat':               {'legs': 0.80, 'core': 0.10, 'back': 0.10},
    'romanian_deadlift':           {'legs': 0.55, 'back': 0.35, 'core': 0.10},
    'hip_thrust':                  {'legs': 0.85, 'core': 0.15},
    # Legs (bodyweight) — 00040 line 1878 + 00055 line 201
    'walking_lunges':              {'legs': 0.90, 'core': 0.10},
    'pistol_squat':                {'legs': 0.80, 'core': 0.20},
    # Legs (machine isolation) — 00040 lines 1885-1891
    'leg_extension':               {'legs': 1.00},
    'leg_curl':                    {'legs': 1.00},
    'leg_abductor':                {'legs': 1.00},
    'leg_adductor':                {'legs': 1.00},
    'calf_raise':                  {'legs': 1.00},
    # Arms (cable / isolation) — 00040 lines 1846-1850
    'dumbbell_curl':               {'arms': 0.90, 'back': 0.10},
    'hammer_curl':                 {'arms': 0.90, 'back': 0.10},
    # Shoulders (cable / isolation) — 00040 line 1798
    'cable_lateral_raise':         {'shoulders': 0.85, 'arms': 0.10, 'core': 0.05},
    # Chest (isolation) — 00040 line 1778
    'dumbbell_fly':                {'chest': 0.85, 'shoulders': 0.10, 'arms': 0.05},
    # Core (bodyweight) — 00040 line 1901
    'hanging_leg_raise':           {'core': 0.85, 'arms': 0.10, 'back': 0.05},
}


def _calibration_attribution(exercise: str) -> dict[str, float]:
    """Resolves attribution for a calibration archetype's exercise.

    Lookup order: `_CALIBRATION_ATTRIBUTION` (real-slug authoritative) →
    `ATTRIBUTION` (alias-based, pre-Phase-24a synthetic). Fixture-replay
    parity REQUIRES that we never mutate the global `ATTRIBUTION` dict —
    `test/fixtures/generate_rpg_fixtures.py` iterates it to produce the
    `attribution` test cases, so adding entries would change the fixture
    surface and fail the byte-identical regen check.
    """
    if exercise in _CALIBRATION_ATTRIBUTION:
        return _CALIBRATION_ATTRIBUTION[exercise]
    return ATTRIBUTION.get(exercise, {})


@dataclass
class CalibrationArchetype:
    """A calibration archetype self-describes its sessions per week, day
    templates (per session label), schedule (ordered list of session labels),
    starting weights, progression strategy, and bodyweight.

    Distinct from `Archetype` so the existing fixture replay's archetype
    consumers don't accidentally pick these up. The two structures share
    the simulate-set internals (`compute_set_xp`) — calibration just brings
    its own scheduling shape.
    """
    name: str
    description: str
    sessions_per_week: int
    day_templates: dict[str, list[tuple[str, int, int]]]
    schedule: list[str]
    starting_weights: dict[str, float]
    weekly_increment: dict[str, float]  # absolute kg/wk per exercise (clean per-spec rates)
    bodyweight_kg: float = 75.0


# Per-spec weekly increments:
#   * beginner_24d:           +2.5 kg/wk compounds, +1.0 kg/wk isolation
#   * intermediate_compound:  +1.0 kg/wk compounds, +0.5 kg/wk accessory
#   * advanced_powerlifter:   +0.5 kg/wk T2, +0.25 kg/wk accessory
#   * hypertrophy_bodybuilder: +0.5 kg/wk compounds, +0.25 kg/wk isolation
#   * bodyweight_only:        added load via weighted-vest proxy (+0.5 kg/wk)
#   * machine_only:           +1.0 kg/wk on machines

CALIBRATION_ARCHETYPES: dict[str, CalibrationArchetype] = {
    'beginner_24d': CalibrationArchetype(
        name='beginner_24d',
        description='3×/wk, light starting weights, full-body progressive overload (~2.5 kg/wk compound, ~1 kg/wk isolation).',
        sessions_per_week=3,
        day_templates={
            'full_body_a': [
                ('barbell_squat', 3, 5),
                ('barbell_bench_press', 3, 5),
                ('barbell_bent_over_row', 3, 5),
                ('barbell_curl', 2, 10),
            ],
            'full_body_b': [
                ('deadlift', 1, 5),
                ('overhead_press', 3, 5),
                ('lat_pulldown', 3, 8),
                ('tricep_pushdown', 2, 10),
            ],
            'full_body_c': [
                ('barbell_squat', 3, 5),
                ('barbell_bench_press', 3, 5),
                ('barbell_bent_over_row', 3, 5),
                ('lateral_raise', 2, 12),
            ],
        },
        schedule=['full_body_a', 'full_body_b', 'full_body_c'],
        starting_weights={
            'barbell_squat': 40.0,
            'barbell_bench_press': 30.0,
            'barbell_bent_over_row': 30.0,
            'deadlift': 50.0,
            'overhead_press': 20.0,
            'lat_pulldown': 30.0,
            'barbell_curl': 10.0,
            'tricep_pushdown': 15.0,
            'lateral_raise': 5.0,
        },
        weekly_increment={
            'barbell_squat': 2.5,
            'barbell_bench_press': 2.5,
            'barbell_bent_over_row': 2.5,
            'deadlift': 2.5,
            'overhead_press': 2.5,
            'lat_pulldown': 2.5,
            'barbell_curl': 1.0,
            'tricep_pushdown': 1.0,
            'lateral_raise': 1.0,
        },
    ),

    'intermediate_compound': CalibrationArchetype(
        name='intermediate_compound',
        description='4×/wk, 5×5 mostly T2/T3 compounds. 5 sets × 5 reps at ~75% 1RM. Slow progression (~1 kg/wk).',
        sessions_per_week=4,
        day_templates={
            'upper_a': [
                ('barbell_bench_press', 5, 5),
                ('pendlay_row', 5, 5),
                ('overhead_press', 3, 5),
            ],
            'lower_a': [
                ('barbell_squat', 5, 5),
                ('romanian_deadlift', 3, 5),
                ('hip_thrust', 3, 8),
            ],
            'upper_b': [
                ('incline_barbell_bench_press', 5, 5),
                ('barbell_bent_over_row', 5, 5),
                ('overhead_press', 3, 5),
            ],
            'lower_b': [
                ('deadlift', 3, 5),
                ('barbell_squat', 3, 5),
                ('romanian_deadlift', 3, 8),
            ],
        },
        schedule=['upper_a', 'lower_a', 'upper_b', 'lower_b'],
        starting_weights={
            'barbell_bench_press': 80.0,
            'incline_barbell_bench_press': 70.0,
            'pendlay_row': 70.0,
            'barbell_bent_over_row': 80.0,
            'overhead_press': 45.0,
            'barbell_squat': 110.0,
            'deadlift': 140.0,
            'romanian_deadlift': 100.0,
            'hip_thrust': 100.0,
        },
        weekly_increment={
            'barbell_bench_press': 1.0,
            'incline_barbell_bench_press': 1.0,
            'pendlay_row': 1.0,
            'barbell_bent_over_row': 1.0,
            'overhead_press': 0.5,
            'barbell_squat': 1.0,
            'deadlift': 1.0,
            'romanian_deadlift': 1.0,
            'hip_thrust': 1.0,
        },
    ),

    'advanced_powerlifter': CalibrationArchetype(
        name='advanced_powerlifter',
        description='3×/wk, low reps (1-5) heavy T2 lifts at 85-92% 1RM. Tests strength_mult floor near peak.',
        sessions_per_week=3,
        day_templates={
            'squat_day': [
                ('barbell_squat', 5, 3),
                ('barbell_squat', 1, 1),     # top single
                ('romanian_deadlift', 3, 5),
                ('hanging_leg_raise', 3, 8),
            ],
            'bench_day': [
                ('barbell_bench_press', 5, 3),
                ('barbell_bench_press', 1, 1),  # top single
                ('overhead_press', 3, 3),
                ('barbell_bent_over_row', 3, 5),
            ],
            'deadlift_day': [
                ('deadlift', 5, 2),
                ('deadlift', 1, 1),          # top single
                ('barbell_squat', 3, 3),     # backoff
                ('pendlay_row', 3, 5),
            ],
        },
        schedule=['squat_day', 'bench_day', 'deadlift_day'],
        starting_weights={
            'barbell_squat': 200.0,
            'barbell_bench_press': 140.0,
            'deadlift': 240.0,
            'overhead_press': 80.0,
            'romanian_deadlift': 180.0,
            'barbell_bent_over_row': 120.0,
            'pendlay_row': 110.0,
            'hanging_leg_raise': 0.0,
        },
        weekly_increment={
            'barbell_squat': 0.5,
            'barbell_bench_press': 0.5,
            'deadlift': 0.5,
            'overhead_press': 0.25,
            'romanian_deadlift': 0.5,
            'barbell_bent_over_row': 0.25,
            'pendlay_row': 0.25,
            'hanging_leg_raise': 0.0,
        },
    ),

    'hypertrophy_bodybuilder': CalibrationArchetype(
        name='hypertrophy_bodybuilder',
        description='5×/wk high-volume T3+T5 mix, isolation-heavy. Tests cap_mult bites + novelty diminishes.',
        sessions_per_week=5,
        day_templates={
            'chest_tris': [
                ('barbell_bench_press', 4, 10),
                ('incline_barbell_bench_press', 4, 10),
                ('cable_crossover', 4, 12),
                ('dumbbell_fly', 3, 12),
                ('tricep_pushdown', 4, 12),
            ],
            'back_bis': [
                ('lat_pulldown', 4, 10),
                ('barbell_bent_over_row', 4, 10),
                ('cable_curl', 4, 12),
                ('dumbbell_curl', 3, 12),
                ('hammer_curl', 3, 12),
            ],
            'legs': [
                ('barbell_squat', 4, 10),
                ('romanian_deadlift', 4, 10),
                ('hip_thrust', 4, 12),
                ('leg_extension', 4, 12),
                ('leg_curl', 4, 12),
                ('calf_raise', 4, 15),
            ],
            'shoulders': [
                ('overhead_press', 4, 8),
                ('lateral_raise', 4, 12),
                ('cable_lateral_raise', 4, 15),
                ('hanging_leg_raise', 3, 12),
            ],
            'arms': [
                ('cable_curl', 4, 12),
                ('hammer_curl', 4, 12),
                ('tricep_pushdown', 4, 12),
                ('dumbbell_curl', 3, 15),
            ],
        },
        schedule=['chest_tris', 'back_bis', 'legs', 'shoulders', 'arms'],
        starting_weights={
            'barbell_bench_press': 90.0,
            'incline_barbell_bench_press': 70.0,
            'cable_crossover': 25.0,
            'dumbbell_fly': 14.0,
            'tricep_pushdown': 35.0,
            'lat_pulldown': 70.0,
            'barbell_bent_over_row': 80.0,
            'cable_curl': 25.0,
            'dumbbell_curl': 14.0,
            'hammer_curl': 14.0,
            'barbell_squat': 120.0,
            'romanian_deadlift': 100.0,
            'hip_thrust': 120.0,
            'leg_extension': 60.0,
            'leg_curl': 50.0,
            'calf_raise': 60.0,
            'overhead_press': 50.0,
            'lateral_raise': 10.0,
            'cable_lateral_raise': 10.0,
            'hanging_leg_raise': 0.0,
        },
        weekly_increment={
            'barbell_bench_press': 0.5,
            'incline_barbell_bench_press': 0.5,
            'cable_crossover': 0.25,
            'dumbbell_fly': 0.25,
            'tricep_pushdown': 0.25,
            'lat_pulldown': 0.5,
            'barbell_bent_over_row': 0.5,
            'cable_curl': 0.25,
            'dumbbell_curl': 0.25,
            'hammer_curl': 0.25,
            'barbell_squat': 0.5,
            'romanian_deadlift': 0.5,
            'hip_thrust': 0.5,
            'leg_extension': 0.25,
            'leg_curl': 0.25,
            'calf_raise': 0.25,
            'overhead_press': 0.25,
            'lateral_raise': 0.25,
            'cable_lateral_raise': 0.25,
            'hanging_leg_raise': 0.0,
        },
    ),

    'bodyweight_only': CalibrationArchetype(
        name='bodyweight_only',
        description='4×/wk T2/T3 bodyweight only. Tests bodyweight load (00056) + tier_mult.',
        sessions_per_week=4,
        day_templates={
            'pull_day': [
                ('pull_up', 4, 8),
                ('chin_up', 3, 8),
                ('archer_push_up', 3, 6),
                ('hanging_leg_raise', 3, 10),
            ],
            'push_day': [
                ('push_up', 4, 12),
                ('decline_push_up', 3, 10),
                ('diamond_push_up', 3, 10),
                ('dips', 3, 8),
            ],
            'legs_day': [
                ('pistol_squat', 4, 6),
                ('walking_lunges', 3, 10),
                ('hanging_leg_raise', 3, 10),
            ],
            'mixed_day': [
                ('pull_up', 3, 8),
                ('close_grip_push_up', 3, 12),
                ('wide_push_up', 3, 12),
                ('dips', 3, 8),
                ('pistol_squat', 3, 6),
            ],
        },
        schedule=['pull_day', 'push_day', 'legs_day', 'mixed_day'],
        # Added load (weighted vest / belt) — many bodyweight athletes
        # progress by adding mass. Starts at 0 across the board so the
        # uses_bodyweight_load path is the dominant XP driver; weekly
        # increment models adding load over time (proxy for adding reps
        # since the simulator's reps are fixed per template).
        starting_weights={
            'pull_up': 0.0, 'chin_up': 0.0, 'archer_push_up': 0.0,
            'hanging_leg_raise': 0.0, 'push_up': 0.0, 'decline_push_up': 0.0,
            'diamond_push_up': 0.0, 'dips': 0.0, 'pistol_squat': 0.0,
            'walking_lunges': 0.0, 'close_grip_push_up': 0.0, 'wide_push_up': 0.0,
        },
        weekly_increment={
            'pull_up': 0.5, 'chin_up': 0.5, 'archer_push_up': 0.0,
            'hanging_leg_raise': 0.0, 'push_up': 0.5, 'decline_push_up': 0.5,
            'diamond_push_up': 0.5, 'dips': 0.5, 'pistol_squat': 0.0,
            'walking_lunges': 0.0, 'close_grip_push_up': 0.5, 'wide_push_up': 0.5,
        },
        bodyweight_kg=75.0,
    ),

    'machine_only': CalibrationArchetype(
        name='machine_only',
        description='4×/wk T4/T5 machine work only. Tests T4/T5 multipliers — slower but feels productive.',
        sessions_per_week=4,
        day_templates={
            'push_day': [
                ('machine_chest_press', 4, 10),
                ('machine_shoulder_press', 3, 10),
                ('cable_lateral_raise', 4, 12),
                ('tricep_pushdown', 4, 12),
            ],
            'pull_day': [
                ('lat_pulldown', 4, 10),
                ('machine_row', 4, 10),
                ('cable_curl', 4, 12),
            ],
            'legs_day': [
                ('leg_press', 4, 10),
                ('leg_extension', 4, 12),
                ('leg_curl', 4, 12),
                ('leg_abductor', 3, 15),
                ('leg_adductor', 3, 15),
                ('calf_raise', 4, 15),
            ],
            'mixed_day': [
                ('machine_chest_press', 3, 12),
                ('machine_row', 3, 12),
                ('lat_pulldown', 3, 10),
                ('tricep_pushdown', 3, 12),
                ('cable_curl', 3, 12),
            ],
        },
        schedule=['push_day', 'pull_day', 'legs_day', 'mixed_day'],
        starting_weights={
            'machine_chest_press': 70.0,
            'machine_shoulder_press': 50.0,
            'cable_lateral_raise': 12.0,
            'tricep_pushdown': 40.0,
            'lat_pulldown': 70.0,
            'machine_row': 70.0,
            'cable_curl': 25.0,
            'leg_press': 150.0,
            'leg_extension': 60.0,
            'leg_curl': 50.0,
            'leg_abductor': 50.0,
            'leg_adductor': 50.0,
            'calf_raise': 80.0,
        },
        weekly_increment={
            'machine_chest_press': 1.0,
            'machine_shoulder_press': 0.5,
            'cable_lateral_raise': 0.5,
            'tricep_pushdown': 0.5,
            'lat_pulldown': 1.0,
            'machine_row': 1.0,
            'cable_curl': 0.5,
            'leg_press': 2.0,
            'leg_extension': 0.5,
            'leg_curl': 0.5,
            'leg_abductor': 0.5,
            'leg_adductor': 0.5,
            'calf_raise': 0.5,
        },
    ),
}


def simulate_calibration(archetype: CalibrationArchetype, weeks: int = 12) -> list[dict]:
    """Calibration-specific simulation loop.

    Mirrors `simulate()` byte-for-byte at the per-set / vitality / rank
    layer (it calls the same `compute_set_xp` + `update_vitality` helpers)
    but consumes per-archetype day templates + schedule + absolute weekly
    increments (not the % progression rates used by the consistency
    archetypes). The split is intentional: changing the progression
    semantics here cannot accidentally drift the fixture replay.

    Returns one snapshot per week, same shape as `simulate()` plus an
    `xp_earned_this_week` field (total XP awarded in just this week — the
    consistency reporter derives this manually but the calibration
    week-by-week report needs it per-row).

    Phase 24d propagation: the iter-3 calibration sign-off has been baked
    into the canonical module constants (`VOLUME_EXPONENT`,
    `WEEKLY_CAP_SETS`, `OVER_CAP_MULTIPLIER`) and into per-slug
    `DIFFICULTY_MULT_BY_SLUG` values (28 T4 slugs dropped by 0.05). The
    calibration archetypes now consume the same canonical math as
    production — no overrides, no per-slug deltas, no scaffolding — and
    are kept around so future calibration phases can rerun them against
    fresh tuning hypotheses without rebuilding the archetype set.
    """
    xp_pool = {p: 0.0 for p in BODY_PARTS}
    weights = dict(archetype.starting_weights)
    peak_loads: dict[str, float] = dict(archetype.starting_weights)
    vit_ewma: dict[str, float] = {}
    vit_peak: dict[str, float] = {}
    snapshots: list[dict] = []
    prev_total_xp = 0.0

    for week in range(1, weeks + 1):
        weekly_count: dict[str, float] = defaultdict(float)
        weekly_volume_per_part: dict[str, float] = defaultdict(float)

        for day in archetype.schedule:
            novelty_count: dict[str, float] = defaultdict(float)
            for exercise, n_sets, reps in archetype.day_templates[day]:
                w = weights.get(exercise, 0.0)
                distribution = _calibration_attribution(exercise)
                diff_mult = difficulty_mult_for_alias(exercise)
                # Calibration archetypes use REAL slugs (extended via
                # identity entries in `_CALIBRATION_REAL_SLUG_IDENTITY`),
                # so the resolved slug is the exercise itself for
                # uses_bodyweight_load() lookup. Phase 24d propagation: the
                # T4 -0.05 delta is now baked into DIFFICULTY_MULT_BY_SLUG
                # itself, so `difficulty_mult_for_alias` returns the
                # already-adjusted value — no per-call-site delta logic.
                real_slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                for _ in range(n_sets):
                    awarded, vol = compute_set_xp(
                        exercise, w, reps, novelty_count, weekly_count, peak_loads,
                        difficulty_mult=diff_mult,
                        bodyweight_kg=archetype.bodyweight_kg,
                        slug=real_slug,
                    )
                    for bp, xp in awarded.items():
                        xp_pool[bp] += xp
                    for bp, share in distribution.items():
                        weekly_volume_per_part[bp] += vol * share

        # Absolute weekly increments (not the % rate used by simulate()).
        for ex, inc in archetype.weekly_increment.items():
            if inc > 0:
                weights[ex] = weights.get(ex, 0.0) + inc

        for bp in ACTIVE_RANKS:
            update_vitality(bp, weekly_volume_per_part.get(bp, 0.0), vit_ewma, vit_peak)

        total_xp_now = sum(xp_pool.values())
        ranks = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
        snapshots.append({
            'week': week,
            'ranks': ranks,
            'character_level': character_level(ranks),
            'total_xp': {p: int(v) for p, v in xp_pool.items()},
            'xp_earned_this_week': int(total_xp_now - prev_total_xp),
            'cumulative_total_xp': int(total_xp_now),
            'class': dominant_class(ranks),
            'vitality': {p: vitality_pct(p, vit_ewma, vit_peak) for p in ACTIVE_RANKS},
        })
        prev_total_xp = total_xp_now

    return snapshots


def print_calibration_report(name: str, snapshots: list[dict]) -> None:
    archetype = CALIBRATION_ARCHETYPES[name]
    print(f"\n=== {name.upper()} ===")
    print(archetype.description)
    print(f"Sessions/week: {archetype.sessions_per_week}  |  Bodyweight: {archetype.bodyweight_kg} kg")
    header = (
        f"{'Wk':>3} {'Lvl':>3}  {'Chst':>4} {'Back':>4} {'Legs':>4} {'Shld':>4} {'Arms':>4} {'Core':>4}    "
        f"{'XP/wk':>8}  {'TotalXP':>10}"
    )
    print(header)
    print('-' * len(header))
    for snap in snapshots:
        r = snap['ranks']
        print(
            f"{snap['week']:>3} {snap['character_level']:>3}  "
            f"{r['chest']:>4} {r['back']:>4} {r['legs']:>4} {r['shoulders']:>4} {r['arms']:>4} {r['core']:>4}    "
            f"{snap['xp_earned_this_week']:>8,}  {snap['cumulative_total_xp']:>10,}"
        )


def calibration_assert_bodyweight_resolution() -> None:
    """Sanity check: every exercise in the bodyweight_only archetype that
    should consume bodyweight load actually does. Prints a one-line OK or
    raises if curation is missing. Runs under `--calibration`."""
    archetype = CALIBRATION_ARCHETYPES['bodyweight_only']
    used_slugs: set[str] = set()
    for day in archetype.day_templates.values():
        for exercise, _, _ in day:
            used_slugs.add(exercise)
    expected_bw = {
        'pull_up', 'chin_up', 'archer_push_up', 'hanging_leg_raise',
        'push_up', 'decline_push_up', 'diamond_push_up', 'dips',
        'pistol_squat', 'walking_lunges', 'close_grip_push_up',
        'wide_push_up',
    }
    missing = [s for s in expected_bw if s in used_slugs and not uses_bodyweight_load(s)]
    if missing:
        raise AssertionError(
            f"bodyweight_only archetype uses slugs that are NOT in "
            f"USES_BODYWEIGHT_LOAD_BY_SLUG: {missing}. Either the slug is "
            f"miscurated or the archetype's exercise list is wrong."
        )
    print(
        f"[OK] bodyweight_only resolution: {len(used_slugs)} slugs, "
        f"{sum(1 for s in used_slugs if uses_bodyweight_load(s))} consume bodyweight "
        f"({archetype.bodyweight_kg} kg)."
    )


def write_baseline_doc(path: str) -> None:
    """Generates `docs/xp-balance-baseline.md` — the launch baseline snapshot.

    Pure side-effect; consumed by Phase 24d-2 (pass-criteria analysis).
    """
    # Run all 6 calibration archetypes for 12 weeks.
    all_snaps: dict[str, list[dict]] = {
        name: simulate_calibration(arch, weeks=12)
        for name, arch in CALIBRATION_ARCHETYPES.items()
    }

    lines: list[str] = []
    lines.append('# XP Balance Baseline — Phase 24d')
    lines.append('')
    lines.append(
        '> Snapshot of the XP formula constants + per-slug `difficulty_mult` '
        '+ `uses_bodyweight_load` curation as the **launch baseline**. '
        'Generated by Phase 24d (`python tasks/rpg-xp-simulation.py --baseline-doc`). '
        'Future tuning is a NEW PHASE.'
    )
    lines.append('>')
    lines.append(
        '> Six-archetype × 12-week simulation per `docs/PROJECT.md` §3 → '
        'Phase 24d acceptance criteria. Pass-criteria analysis lives in '
        'Task 24d-2; this file is the raw output the analysis reads.'
    )
    lines.append('')

    # --- Constants snapshot ---
    lines.append('## Constants snapshot')
    lines.append('')
    lines.append(
        '> **Phase 24d propagation complete.** The iter-3 calibration sign-off '
        'values are now canonical — `VOLUME_EXPONENT = 0.60`, '
        '`WEEKLY_CAP_SETS = 15`, `OVER_CAP_MULTIPLIER = 0.3` — and a per-slug '
        '`-0.05` delta has been baked into the 28 curated T4 slugs in '
        '`exercises.difficulty_mult` (migration 00059). Dart + SQL + Python '
        'sim + fixture all agree on the launch baseline; the 6 calibration '
        'archetypes here exercise the same canonical math as production, no '
        'overrides.'
    )
    lines.append('')
    lines.append('| Constant | Value | Notes |')
    lines.append('|---|---|---|')
    rows = [
        ('XP_BASE', XP_BASE, 'XP curve base'),
        ('XP_GROWTH', XP_GROWTH, 'Per-rank multiplier'),
        ('VOLUME_EXPONENT', VOLUME_EXPONENT,
         'base_xp = volume_load^this (Phase 24d: 0.65 → 0.60)'),
        ('NOVELTY_DENOMINATOR', NOVELTY_DENOMINATOR,
         'novelty = exp(-cumulative/this) per session'),
        ('WEEKLY_CAP_SETS', WEEKLY_CAP_SETS,
         'Effective sets per body part before over-cap multiplier kicks in (Phase 24d: 20 → 15)'),
        ('OVER_CAP_MULTIPLIER', OVER_CAP_MULTIPLIER,
         'Multiplier applied beyond weekly cap (Phase 24d: 0.5 → 0.3)'),
        ('STRENGTH_MULT_FLOOR', STRENGTH_MULT_FLOOR,
         'Anti-stagnation floor for strength_mult'),
        ('DIFFICULTY_MULT_FLOOR', DIFFICULTY_MULT_FLOOR,
         'Per-exercise difficulty hard floor'),
        ('DIFFICULTY_MULT_CEILING', DIFFICULTY_MULT_CEILING,
         'Per-exercise difficulty hard ceiling'),
        ('CHAR_LEVEL_DENOMINATOR', CHAR_LEVEL_DENOMINATOR,
         'floor((Σ ranks − N) / this) + 1'),
        ('ASCENDANT_BALANCE_THRESHOLD', ASCENDANT_BALANCE_THRESHOLD,
         'Class threshold (balanced)'),
        ('ASCENDANT_MIN_RANK', ASCENDANT_MIN_RANK,
         'Min rank for Ascendant class'),
        ('VITALITY_TAU_UP_WEEKS', VITALITY_TAU_UP_WEEKS,
         'Vitality rise time constant'),
        ('VITALITY_TAU_DOWN_WEEKS', VITALITY_TAU_DOWN_WEEKS,
         'Vitality decay time constant'),
        ('VITALITY_PEAK_PERMANENT', VITALITY_PEAK_PERMANENT,
         'Peak never decays — saga inviolate'),
    ]
    for label, value, note in rows:
        lines.append(f'| `{label}` | `{value}` | {note} |')
    lines.append('')
    lines.append('Intensity-by-reps table (lower reps = heavier load):')
    lines.append('')
    lines.append('| Reps ≥ | Intensity mult |')
    lines.append('|---|---|')
    for r, m in INTENSITY_BY_REPS:
        lines.append(f'| {r} | {m} |')
    lines.append('')

    # --- Tier table ---
    lines.append('## Tier table snapshot (framework §3)')
    lines.append('')
    lines.append('| Tier | Name | tier_mult | Defining characteristic |')
    lines.append('|---|---|---|---|')
    lines.append('| T1 | Olympic / ballistic | 1.25 | Triple extension, peak power, highest skill ceiling |')
    lines.append('| T2 | Foundational compound (free weight, axial load) | 1.15 | Multi-joint, spine bears load, large stabilizer demand |')
    lines.append('| T3 | Standard compound (free weight or supported) | 1.05 | Multi-joint, lower spinal load OR partial support |')
    lines.append('| T4 | Machine compound / cable multi-joint | 0.90 | Fixed path, low stabilizer demand |')
    lines.append('| T5 | Single-joint isolation | 0.85 | One articulation, minimal coordination |')
    lines.append('')
    lines.append(
        'Composite: `difficulty_mult = clamp(tier_mult + min(secondary_count, 3) × 0.02, 0.85, 1.25)`. '
        'Secondary bump = +0.02 per secondary, capped at +0.06 (i.e. first 3 secondaries count).'
    )
    lines.append('')

    # --- difficulty_mult per slug (sourced from this file's DIFFICULTY_MULT_BY_SLUG) ---
    lines.append('## difficulty_mult per slug')
    lines.append('')
    lines.append(
        f'`{len(DIFFICULTY_MULT_BY_SLUG)}` curated slugs in the simulator\'s '
        '`DIFFICULTY_MULT_BY_SLUG` mirror — sourced from '
        '`supabase/migrations/00053_add_exercise_difficulty_mult.sql` (150 entries) '
        'plus two Phase-24b additions (`archer_push_up`, `pistol_squat`) consumed '
        'by the calibration `bodyweight_only` archetype. The remaining 47 Phase-24b '
        'slugs in `00055_phase24b_new_default_exercises.sql` are not exercised by '
        'the current archetype set; back-filling them is a follow-up sweep with '
        'zero blast radius on fixture replay. User-created exercises and unmapped '
        'slugs fall back to `1.0` (neutral) — matches SQL `COALESCE(..., 1.0)` and '
        'the column DEFAULT.'
    )
    lines.append('')
    lines.append('| Slug | difficulty_mult |')
    lines.append('|---|---|')
    for slug in sorted(DIFFICULTY_MULT_BY_SLUG.keys()):
        lines.append(f'| `{slug}` | {DIFFICULTY_MULT_BY_SLUG[slug]} |')
    lines.append('')

    # --- uses_bodyweight_load per slug ---
    lines.append('## uses_bodyweight_load per slug')
    lines.append('')
    lines.append(
        f'`{len(USES_BODYWEIGHT_LOAD_BY_SLUG)}` curated slugs (sourced from '
        '`supabase/migrations/00056_add_bodyweight_load_semantics.sql`). For these '
        'slugs, `effective_load = entered_weight + bodyweight_kg`. All others use '
        '`effective_load = entered_weight`.'
    )
    lines.append('')
    lines.append('| Slug |')
    lines.append('|---|')
    for slug in sorted(USES_BODYWEIGHT_LOAD_BY_SLUG):
        lines.append(f'| `{slug}` |')
    lines.append('')

    # --- Six-archetype summary table ---
    lines.append('## Six-archetype results — week 12')
    lines.append('')
    lines.append(
        '| Archetype | Sessions/wk | Bodyweight | Total XP | Char level | Max rank (body part) | Min rank (body part) |'
    )
    lines.append('|---|---|---|---|---|---|---|')
    for name in CALIBRATION_ARCHETYPES.keys():
        arch = CALIBRATION_ARCHETYPES[name]
        wk12 = all_snaps[name][-1]
        # Only consider ACTIVE_RANKS for max/min — cardio is structurally 1 in v1.
        active = {bp: wk12['ranks'][bp] for bp in ACTIVE_RANKS}
        max_bp = max(active, key=active.get)
        min_bp = min(active, key=active.get)
        total = wk12['cumulative_total_xp']
        lines.append(
            f'| `{name}` | {arch.sessions_per_week} | {arch.bodyweight_kg} kg | '
            f'{total:,} | {wk12["character_level"]} | '
            f'{active[max_bp]} ({max_bp}) | {active[min_bp]} ({min_bp}) |'
        )
    lines.append('')

    # --- Per-archetype detail ---
    lines.append('## Per-archetype detail')
    lines.append('')
    for name, arch in CALIBRATION_ARCHETYPES.items():
        snaps = all_snaps[name]
        lines.append(f'### {name}')
        lines.append('')
        lines.append(arch.description)
        lines.append('')
        lines.append(f'- Sessions/week: `{arch.sessions_per_week}`')
        lines.append(f'- Schedule: `{arch.schedule}`')
        lines.append(f'- Bodyweight: `{arch.bodyweight_kg}` kg')
        lines.append('')
        # Day-template summary.
        lines.append('Day templates:')
        lines.append('')
        for day_name, template in arch.day_templates.items():
            entries = ', '.join(f'{ex}×{n}×{r}' for ex, n, r in template)
            lines.append(f'- `{day_name}` — {entries}')
        lines.append('')
        # Week-by-week.
        lines.append('#### Week-by-week')
        lines.append('')
        lines.append('| Week | Char lvl | Chest | Back | Legs | Shld | Arms | Core | XP earned | Cumulative XP |')
        lines.append('|---|---|---|---|---|---|---|---|---|---|')
        for snap in snaps:
            r = snap['ranks']
            lines.append(
                f'| {snap["week"]} | {snap["character_level"]} | '
                f'{r["chest"]} | {r["back"]} | {r["legs"]} | {r["shoulders"]} | '
                f'{r["arms"]} | {r["core"]} | {snap["xp_earned_this_week"]:,} | '
                f'{snap["cumulative_total_xp"]:,} |'
            )
        lines.append('')
        # Final state.
        lines.append('#### Final state at week 12')
        lines.append('')
        wk12 = snaps[-1]
        lines.append('| Body part | Total XP earned | Rank | Vitality % |')
        lines.append('|---|---|---|---|')
        for bp in BODY_PARTS:
            xp = wk12['total_xp'][bp]
            rank = wk12['ranks'][bp]
            if bp in ACTIVE_RANKS:
                vit = f'{int(wk12["vitality"][bp] * 100)}%'
            else:
                vit = 'n/a (cardio v2 deferred)'
            lines.append(f'| {bp} | {xp:,} | {rank} | {vit} |')
        lines.append('')
        lines.append(f'- Class at week 12: `{wk12["class"]}`')
        lines.append(f'- Total XP across all body parts: `{wk12["cumulative_total_xp"]:,}`')
        lines.append('')

    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def run_calibration() -> None:
    """Runs the 6 calibration archetypes × 12 weeks and prints reports.
    Default behavior of the script (no `--calibration` flag) is unchanged.
    """
    print('RepSaga RPG XP Calibration Run — Phase 24d')
    print('=' * 70)
    print('Six archetypes × 12 weeks. See docs/xp-balance-baseline.md for the')
    print('full baseline snapshot (constants + per-slug mults + raw weekly data).')
    print()
    calibration_assert_bodyweight_resolution()
    for name, arch in CALIBRATION_ARCHETYPES.items():
        snaps = simulate_calibration(arch, weeks=12)
        print_calibration_report(name, snaps)
    print('\n')
    print('Done. Pass-criteria analysis is Task 24d-2 — this run produces')
    print('the data; the next task reads and judges it.')


# ============================================================================
# Main
# ============================================================================

if __name__ == '__main__':
    import sys

    # Phase 24d: `--calibration` runs ONLY the 6 new calibration archetypes;
    # `--baseline-doc [path]` (re)generates docs/xp-balance-baseline.md from
    # the same 6-archetype 12-week run. Default behavior (no flag) is the
    # original CONSISTENCY archetypes + detraining scenarios — unchanged.
    if '--baseline-doc' in sys.argv:
        # Optional path arg: --baseline-doc /custom/path.md
        idx = sys.argv.index('--baseline-doc')
        if idx + 1 < len(sys.argv) and not sys.argv[idx + 1].startswith('--'):
            out_path = sys.argv[idx + 1]
        else:
            out_path = 'docs/xp-balance-baseline.md'
        write_baseline_doc(out_path)
        print(f"Baseline doc written to {out_path}")
        sys.exit(0)

    if '--calibration' in sys.argv:
        run_calibration()
        sys.exit(0)

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
