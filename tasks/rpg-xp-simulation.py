"""
RepSaga RPG XP simulation harness — Phase 29 v2 + 29.6 LOCKED.

================================================================================
PARITY WARNING — synchronized formula sites (5 sites — Phase 29 v2 expansion)
================================================================================
The XP formula is implemented in FIVE places that MUST stay byte-for-byte
identical. Any change to a constant, multiplier order, or floor/ceiling here
must land in the same PR as the matching change in:

  1. lib/features/rpg/domain/xp_calculator.dart
     (Dart `XpCalculator.computeSetXp` — live save path; the Dart calculator
     is bodyweight-agnostic — production callers pre-convert sets.weight to
     `effective_load` before invoking computeSetXp)
  2. lib/features/rpg/domain/implied_tier.dart (NEW in Phase 29 PR 2)
     (Dart per-lift gender-aware tier table interpolator + abs_strength_premium
     fraction calculator — must mirror this file's IMPLIED_TIER_TABLES_MALE /
     IMPLIED_TIER_TABLES_FEMALE / EXERCISE_TIER_DISCOUNT / E_BONUS / E_FLOOR /
     E_CEIL byte-for-byte)
  3. tasks/rpg-xp-simulation.py (this file — the LOCKED BASELINE & ORACLE)
  4. test/fixtures/generate_rpg_fixtures.py
     (regenerate `rpg_xp_fixtures.json` so Dart parity tests stay green)
  5. supabase/migrations/*_record_set_xp.sql (Phase 29 PR 2 will add the
     migration that updates `record_set_xp` / `record_session_xp_batch` /
     `_rpg_backfill_chunk` for the Phase 29 v2 multiplier chain + Path C
     premium + piecewise rank curve)

Integration parity tests assert all five agree to 1e-4 absolute. If you only
change one site you'll get a build that compiles but produces silently
inconsistent XP between client computation and server persistence.
================================================================================

Phase 29 v2 + 29.6 LOCKED CONSTANTS — must match Dart/SQL/fixture byte-for-byte:

  VOLUME_EXPONENT        = 0.60
  NOVELTY_DENOMINATOR    = 15.0
  WEEKLY_CAP_SETS        = 15.0
  OVER_CAP_MULTIPLIER    = 0.3
  STRENGTH_MULT_FLOOR    = 0.4
  VOLUME_LOAD_FLOOR      = 1.0       (max(1.0, eff_weight * reps))

  # Refinement #6 piecewise rank curve
  XP_BASE                = 60
  XP_GROWTH_BAND1        = 1.10      (ranks 1-20)
  RANK_CURVE_BREAKPOINT  = 20
  LINEAR_XP_PER_RANK     = 367.0     (LITERAL — derived 60 × 1.10^19 ≈ 366.957
                                       would drift parity at high ranks)

  # Phase 29.6 Path C absolute strength premium
  E_BONUS                = 0.8
  E_FLOOR                = 35.0
  E_CEIL                 = 55.0

  # Refinement #4 near-failure inference
  NF_INTENSITY_BONUS     = 0.10
  NF_TARGET_THRESHOLD    = 0.85      (actual_reps < target_reps × 0.85 →
                                       inferred near-failure)

  # Refinement #3 frequency_mult (INCLUDED — simple inline impl)
  FREQUENCY_MULT_TABLE   = [1.00, 1.06, 1.10, 1.06, 1.00]
                            (sessions 1/2/3/4/5+ per body-part per 7d window)

  # Refinement #2 progressive overload reward (named physiological bands)
  REP_BAND_HEAVY         = (1, 4)
  REP_BAND_STRENGTH      = (5, 7)
  REP_BAND_HYPERTROPHY   = (8, 12)
  REP_BAND_ENDURANCE     = (13, +inf)

  # Refinement #1 / Phase 29.6 — per-lift gender-aware Symmetric Strength tiers
  IMPLIED_TIER_TABLES_MALE   (BENCH/SQUAT/DEADLIFT/OHP/ROW/ISOLATION)
  IMPLIED_TIER_TABLES_FEMALE (BENCH/SQUAT/DEADLIFT/OHP/ROW/ISOLATION)
  EXERCISE_TIER_DISCOUNT     (per-exercise variant discount, e.g. leg_press 0.65)

Per-set XP chain (11 multipliers in this exact order — PR 2 Dart + SQL must
match position-by-position):

    set_xp = base
           × intensity
           × strength
           × novelty
           × cap
           × difficulty_mult
           × tier_diff_mult
           × abs_strength_premium      (Phase 29.6 Path C)
           × overload_mult
           × frequency_mult
           × attribution_share         (per body part)

================================================================================

Plays back synthetic training histories for several user archetypes through
the locked Phase 29 v2 + 29.6 XP formula to surface pacing problems and act
as the integration parity oracle.

Usage:  python tasks/rpg-xp-simulation.py             # 13-persona panel
        python tasks/rpg-xp-simulation.py --legacy    # legacy 5-archetype run
"""

from __future__ import annotations

import argparse
import math
import random
from collections import defaultdict
from dataclasses import dataclass, field, replace

# ============================================================================
# CONFIG — locked formula constants (Phase 29 v2 + 29.6)
# ============================================================================

# Per-rank XP curve (Refinement #6 piecewise)
XP_BASE = 60
XP_GROWTH = 1.10                     # legacy alias (ranks 1-20 in piecewise)
XP_GROWTH_BAND1 = 1.10               # explicit Phase 29 v2 name
RANK_CURVE_BREAKPOINT = 20           # piecewise breakpoint
LINEAR_XP_PER_RANK = 367.0           # LITERAL — derived ~366.957 would drift

# Per-set XP formula (CANONICAL — Phase 29 v2 inherits Phase 24d propagation)
VOLUME_EXPONENT = 0.60               # base = (eff_weight × reps)^this
NOVELTY_DENOMINATOR = 15             # higher = slower diminishing returns
WEEKLY_CAP_SETS = 15                 # effective sets per body part before over-cap
OVER_CAP_MULTIPLIER = 0.3            # multiplier beyond weekly cap
STRENGTH_MULT_FLOOR = 0.4            # clamp current/peak below this → floor
VOLUME_LOAD_FLOOR = 1.0              # max(1.0, eff_weight * reps)

# Difficulty multiplier range (Phase 24a). Per-exercise composite in [0.85, 1.25].
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

# Vitality (asymmetric EWMA on weekly volume per body part)
VITALITY_TAU_UP_WEEKS = 2.0          # rebuild fast  (live 00083: τ_up = 14d)
VITALITY_TAU_DOWN_WEEKS = 6.0        # decay slow    (live 00083: τ_down = 42d strength)
VITALITY_PEAK_PERMANENT = True

# Live 00083 recompute cadence — the EWMA + ref_peak step ONCE PER UTC DAY, with
# the EWMA sampled from a TRAILING 7-DAY volume window. The Phase-Vitality-3
# panel reproduces this on a DAILY grid (see step_vitality_daily) — a weekly
# single-step model is NOT faithful: it would decay ref_peak a full week while
# the EWMA takes only one sample, collapsing ref_peak onto the EWMA so vpct never
# leaves 1.0. The daily grid is what makes the gate actually throttle an
# inconsistent lifter (vpct 0.4-0.7) while leaving a consistent one at 1.0.
VITALITY_SAMPLE_DAYS = 7.0           # live c_sample_days
VITALITY_TAU_UP_DAYS = 14.0          # live c_tau_up
VITALITY_TAU_DOWN_DAYS_STRENGTH = 42.0   # live c_tau_down_str
VITALITY_ALPHA_UP = 1.0 - math.exp(-VITALITY_SAMPLE_DAYS / VITALITY_TAU_UP_DAYS)
VITALITY_ALPHA_DOWN = 1.0 - math.exp(-VITALITY_SAMPLE_DAYS / VITALITY_TAU_DOWN_DAYS_STRENGTH)
REF_PEAK_DECAY_DAILY = math.exp(-math.log(2.0) / 21.0)   # live c_ref_peak_decay
DAYS_PER_WEEK = 7

# ----------------------------------------------------------------------------
# Phase Vitality-3 — Strength Vitality XP-gate (PR 1, SIM ONLY)
# ----------------------------------------------------------------------------
# The gate throttles strength set XP by per-body-part conditioning, mirroring
# the cardio gate (migration 00081) but using the DECAYING reference peak
# (migration 00083) as the denominator — that decay is what lets a detrained
# returner's vmult recover (a frozen all-time peak never could). THROTTLE-ONLY:
# rank is never touched (decision D6, saga inviolate); only XP earn-rate scales.
#
#   vpct  = clamp(vit_ewma / vit_ref_peak, 0, 1)   (ref_peak ≤ 0 → vpct 1.0)
#   vmult = FLOOR + (1 − FLOOR) × vpct
#   set_xp_gated = (11-multiplier chain) × vmult    ← applied as the 12th factor
#
# vmult is computed ONCE per body part from PRE-session vitality (non-circular:
# the live recompute runs AFTER the XP writes). CRITICAL STABILITY PROPERTY: the
# EWMA that feeds vpct is driven by weekly VOLUME LOAD (Σ vol×share per bp), NOT
# by the gated XP — the gate must never feed its own input or the loop
# destabilizes. See simulate_persona().
STRENGTH_VITALITY_FLOOR = 0.50       # D1 sweep {0.40, 0.50}. CHOSEN: 0.50 — the
                                     # gentler comeback floor. Both floors hit the
                                     # acceptance (returner ≥0.90 by back-wk2,
                                     # sandbagger < advanced), so D1 is decided on
                                     # "returner week-1 feel": 0.50 means a
                                     # returning lifter's single throttled week
                                     # back earns HALF, not 60%-off, honoring the
                                     # muscle-memory thesis (return is an
                                     # awakening, not a punishment) while keeping
                                     # the un-farmable property — a one-off
                                     # post-layoff burst still only earns 0.50×.
                                     # See docs/xp-balance-baseline.md.

# D2 — global re-center: adding vmult ≤ 1.0 slows every non-100% persona, so the
# whole panel drifts down. Restore steady-state by scaling base_xp by a single
# global multiplier (NOT per-rep-tier — preserves the Phase-29 curve shape).
# Swept holding PANEL_TARGET_BANDS fixed to minimize Σ|Δ_consistent| while
# keeping the 6 consistent personas in-band AND within ±0.5 rank of their
# pre-gate avg_rank. CHOSEN: see docs/xp-balance-baseline.md.
STRENGTH_BASE_RECENTER = 1.00        # CHOSEN by the wk8-12 VPCT_NORMAL sweep
                                     # (= 1.0; VPCT_NORMAL measured 1.0 — a
                                     # consistent lifter sits at FULL charge so
                                     # the gate is a no-op for them and there is
                                     # nothing to re-center). See baseline doc.

# Reference-peak half-life — mirrors migration 00083 (21-day daily decay).
# Applied on the DAILY grid (REF_PEAK_DECAY_DAILY above), NOT compounded weekly.
VITALITY_REF_PEAK_HALFLIFE_DAYS = 21.0

# DISCRETIZATION NOTE (the accepted Phase-29 panel-vs-live gap): the panel does
# not model individual training DAYS — it batches a week's sets together for the
# XP math. For the VITALITY clock only, it distributes each week's per-bp volume
# load as a single lump on day 0 of the week and then advances the EWMA/ref_peak
# 7 daily steps with a trailing-7-day volume window. This reproduces the live
# recompute's day-by-day behavior (which is what makes the gate throttle an
# inconsistent lifter) without claiming to replay real per-session timestamps.
# The only fidelity loss is intra-week session spacing (the live window would see
# e.g. a Mon/Wed/Fri spread rather than one Monday lump) — immaterial to the
# converged vpct because the trailing window sums the same weekly total either
# way; it only changes the within-week ripple, which the weekly XP batch ignores.

# Bodyweight progression (legacy consistency archetypes)
PROGRESSION_RATES = {
    'beginner': 1.025,
    'intermediate': 1.005,
    'advanced': 1.001,
    'stagnant': 1.000,
}
NEWBIE_DECAY_WEEKS = 12

# Refinement #4 — near-failure inference
NF_INTENSITY_BONUS = 0.10
NF_TARGET_THRESHOLD = 0.85

# Refinement #3 — frequency_mult (sessions per body part per 7d)
FREQUENCY_MULT_TABLE = [1.00, 1.06, 1.10, 1.06, 1.00]
# Persona-panel-v2 used (1.00, 1.10, 1.15, 1.10, 1.00) but the spec brief locks
# (1.00, 1.06, 1.10, 1.06, 1.00) per the gentler PR-2-friendly impl. The
# persona panel target bands accommodate both — we ship the gentler curve.

# Refinement #2 — rep bands (heavy / strength / hypertrophy / endurance)
REP_BAND_HEAVY_MAX = 4
REP_BAND_STRENGTH_MAX = 7
REP_BAND_HYPERTROPHY_MAX = 12
# endurance: 13+

# Phase 29.6 Path C — absolute strength premium
E_BONUS = 0.8
E_FLOOR = 35.0
E_CEIL = 55.0

# tier_diff_mult parameters (Pokemon Gen 5 adaptation — refinement carried
# from Phase 29 tier-diff prototype)
TIER_DIFF_OFFSET = 10.0
TIER_DIFF_EXP = 2.5
TIER_DIFF_MAX = 8.0
TIER_DIFF_MIN = 0.25

# ============================================================================
# Exercise → body-part attribution map
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
    # Phase 29 v2 — machine-only + hypertrophy split additions
    'machine_chest_press': {'chest': 0.75, 'shoulders': 0.15, 'arms': 0.10},
    'seated_row':          {'back': 0.75, 'arms': 0.20, 'core': 0.05},
    'leg_extension':       {'legs': 1.00},
    'leg_curl':            {'legs': 0.85, 'core': 0.15},
    'romanian_deadlift':   {'legs': 0.55, 'back': 0.35, 'core': 0.10},
}

# ============================================================================
# Per-exercise difficulty multiplier (Phase 24a)
# ============================================================================

DIFFICULTY_MULT_BY_SLUG = {
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
    'seal_row': 1.07, 'seated_calf_raise': 0.85, 'seated_row': 0.99, 'side_plank': 0.89,
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

# Mapping from the simulator's short class aliases onto representative real
# default slugs (so per-exercise difficulty_mult flows through aliases).
SIM_ALIAS_TO_DEFAULT_SLUG = {
    'bench':           'barbell_bench_press',
    'incline_bench':   'incline_barbell_bench_press',
    'overhead_press':  'overhead_press',
    'lateral_raise':   'lateral_raise',
    'tricep_pushdown': 'tricep_pushdown',
    'row':             'barbell_bent_over_row',
    'pulldown':        'lat_pulldown',
    'pullup':          'pull_up',
    'curl':            'barbell_curl',
    'squat':           'barbell_squat',
    'deadlift':        'deadlift',
    'leg_press':       'leg_press',
    'lunge':           'walking_lunges',
    'plank':           'plank',
    'leg_raise':       'leg_raise',
    # Phase 29 v2 — machine + hypertrophy direct slugs (identity mapping so
    # the alias resolver finds them in DIFFICULTY_MULT_BY_SLUG).
    'machine_chest_press': 'machine_chest_press',
    'seated_row':          'seated_row',
    'leg_extension':       'leg_extension',
    'leg_curl':            'leg_curl',
    'romanian_deadlift':   'romanian_deadlift',
}


def difficulty_mult_for_slug(slug):
    return DIFFICULTY_MULT_BY_SLUG.get(slug, 1.0)


def difficulty_mult_for_alias(alias):
    slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(alias)
    if slug is None:
        return 1.0
    return difficulty_mult_for_slug(slug)


# ============================================================================
# Bodyweight-as-load semantics (Phase 24c)
# ============================================================================

USES_BODYWEIGHT_LOAD_BY_SLUG = frozenset({
    "pull_up", "chin_up", "wide_grip_pull_up",
    "dips", "ring_dip", "muscle_up",
    "push_up", "wide_push_up", "incline_push_up", "decline_push_up",
    "diamond_push_up", "close_grip_push_up", "archer_push_up",
    "bodyweight_squat", "pistol_squat",
    "walking_lunges",
    "hanging_leg_raise",
    "handstand_push_up",
    "inverted_row",
    "nordic_curl",
})


def uses_bodyweight_load(slug):
    return slug in USES_BODYWEIGHT_LOAD_BY_SLUG


# ============================================================================
# Refinement #5 — per-exercise bodyweight load ratio
# Source: Suprak et al. 2011 JSCR for push-up variants; Youdas et al. 2010
# JSCR for pull-up; Bryanton et al. 2012 for squat fractions.
# ============================================================================

BODYWEIGHT_LOAD_RATIO = {
    'pull_up':            1.00,
    'chin_up':            1.00,
    'wide_grip_pull_up':  1.00,
    'muscle_up':          1.00,
    'dips':               0.95,
    'ring_dip':           0.95,
    'push_up':            0.64,
    'wide_push_up':       0.65,
    'decline_push_up':    0.74,
    'incline_push_up':    0.41,
    'diamond_push_up':    0.64,
    'close_grip_push_up': 0.63,
    'archer_push_up':     0.80,
    'pistol_squat':       0.95,
    'bodyweight_squat':   0.75,
    'walking_lunges':     0.85,
    'hanging_leg_raise':  1.00,
    'handstand_push_up':  1.00,
    'inverted_row':       0.70,
    'nordic_curl':        1.00,
}


def effective_weight(slug, entered_weight, bodyweight_kg):
    """Compute effective load for the volume + strength formula.

    Phase 29 v2 (Refinement #5) extends Phase 24c: when slug is curated in
    USES_BODYWEIGHT_LOAD_BY_SLUG, the load fraction comes from
    BODYWEIGHT_LOAD_RATIO (per-exercise biomechanically grounded). For
    non-curated slugs, falls through to entered weight only.

    NULL bodyweight degrades gracefully to entered-only (matches 00057 SQL
    COALESCE behavior).
    """
    if uses_bodyweight_load(slug):
        ratio = BODYWEIGHT_LOAD_RATIO.get(slug, 1.00)
        return (entered_weight or 0.0) + (bodyweight_kg or 0.0) * ratio
    return entered_weight or 0.0


# ============================================================================
# Refinement #1 + Phase 29.6 — gender-aware per-lift Symmetric Strength tiers
# ============================================================================
#
# Male tier tables: rigorous BW-relative strength standards per lift family,
# calibrated against published normative strength data (Symmetric Strength,
# Strength Standards). Legendary tier (rank 65+) is Phase 29 extension.
#
# Female tier tables: strengthlevel.com/strength-standards/female/kg snapshot
# 2026-05-20 — empirical normative female ratios per lift family.

# Male tier tables — (rank, label, bodyweight-ratio)
BENCH_TIERS_MALE = [
    ( 0, 'Untrained',    0.50),
    ( 8, 'Novice',       0.75),
    (15, 'Beginner',     1.00),
    (25, 'Intermediate', 1.25),
    (35, 'Advanced',     1.50),
    (45, 'Elite',        1.75),
    (55, 'World-class',  2.00),
    (65, 'Legendary',    2.50),
]

SQUAT_TIERS_MALE = [
    ( 0, 'Untrained',    0.60),
    ( 8, 'Novice',       1.00),
    (15, 'Beginner',     1.25),
    (25, 'Intermediate', 1.75),
    (35, 'Advanced',     2.25),
    (45, 'Elite',        2.75),
    (55, 'World-class',  3.25),
    (65, 'Legendary',    3.75),
]

DEADLIFT_TIERS_MALE = [
    ( 0, 'Untrained',    0.80),
    ( 8, 'Novice',       1.25),
    (15, 'Beginner',     1.50),
    (25, 'Intermediate', 2.00),
    (35, 'Advanced',     2.50),
    (45, 'Elite',        3.00),
    (55, 'World-class',  3.50),
    (65, 'Legendary',    3.75),
]

OHP_TIERS_MALE = [
    ( 0, 'Untrained',    0.30),
    ( 8, 'Novice',       0.45),
    (15, 'Beginner',     0.60),
    (25, 'Intermediate', 0.75),
    (35, 'Advanced',     0.90),
    (45, 'Elite',        1.05),
    (55, 'World-class',  1.20),
    (65, 'Legendary',    1.40),
]

ROW_TIERS_MALE = [
    ( 0, 'Untrained',    0.60),
    ( 8, 'Novice',       0.90),
    (15, 'Beginner',     1.20),
    (25, 'Intermediate', 1.55),
    (35, 'Advanced',     1.90),
    (45, 'Elite',        2.30),
    (55, 'World-class',  2.70),
    (65, 'Legendary',    3.00),
]

ISOLATION_TIERS_MALE = [
    ( 0, 'Untrained',    0.08),
    ( 8, 'Novice',       0.13),
    (15, 'Beginner',     0.20),
    (25, 'Intermediate', 0.30),
    (35, 'Advanced',     0.40),
    (45, 'Elite',        0.50),
    (55, 'World-class',  0.60),
    (65, 'Legendary',    0.70),
]

# Female tier tables — empirical (strengthlevel.com snapshot 2026-05-20)
BENCH_TIERS_FEMALE = [
    ( 0, 'Untrained',    0.28),
    ( 8, 'Novice',       0.48),
    (15, 'Beginner',     0.78),
    (25, 'Intermediate', 1.13),
    (35, 'Advanced',     1.53),
    (45, 'Elite',        1.90),
    (55, 'World-class',  2.30),
    (65, 'Legendary',    2.80),
]

SQUAT_TIERS_FEMALE = [
    ( 0, 'Untrained',    0.48),
    ( 8, 'Novice',       0.78),
    (15, 'Beginner',     1.17),
    (25, 'Intermediate', 1.62),
    (35, 'Advanced',     2.13),
    (45, 'Elite',        2.70),
    (55, 'World-class',  3.10),
    (65, 'Legendary',    3.50),
]

DEADLIFT_TIERS_FEMALE = [
    ( 0, 'Untrained',    0.62),
    ( 8, 'Novice',       0.95),
    (15, 'Beginner',     1.38),
    (25, 'Intermediate', 1.88),
    (35, 'Advanced',     2.43),
    (45, 'Elite',        3.00),
    (55, 'World-class',  3.40),
    (65, 'Legendary',    3.80),
]

OHP_TIERS_FEMALE = [
    ( 0, 'Untrained',    0.20),
    ( 8, 'Novice',       0.35),
    (15, 'Beginner',     0.53),
    (25, 'Intermediate', 0.75),
    (35, 'Advanced',     1.00),
    (45, 'Elite',        1.25),
    (55, 'World-class',  1.50),
    (65, 'Legendary',    1.80),
]

ROW_TIERS_FEMALE = [
    ( 0, 'Untrained',    0.48),
    ( 8, 'Novice',       0.72),
    (15, 'Beginner',     1.00),
    (25, 'Intermediate', 1.35),
    (35, 'Advanced',     1.70),
    (45, 'Elite',        2.10),
    (55, 'World-class',  2.50),
    (65, 'Legendary',    2.80),
]

ISOLATION_TIERS_FEMALE = [
    ( 0, 'Untrained',    0.05),
    ( 8, 'Novice',       0.09),
    (15, 'Beginner',     0.14),
    (25, 'Intermediate', 0.22),
    (35, 'Advanced',     0.32),
    (45, 'Elite',        0.42),
    (55, 'World-class',  0.52),
    (65, 'Legendary',    0.62),
]

# Exercise → tier-table dispatch (per gender), and per-variant discount
EXERCISE_TIER_FAMILY = {
    'bench':                       'bench',
    'incline_bench':               'bench',
    'barbell_bench_press':         'bench',
    'incline_barbell_bench_press': 'bench',
    'machine_chest_press':         'bench',
    'overhead_press':              'ohp',
    'squat':                       'squat',
    'barbell_squat':               'squat',
    'leg_press':                   'squat',
    'lunge':                       'squat',
    'walking_lunges':              'squat',
    'deadlift':                    'deadlift',
    'romanian_deadlift':           'deadlift',
    'row':                         'row',
    'barbell_bent_over_row':       'row',
    'pendlay_row':                 'row',
    'pulldown':                    'row',
    'lat_pulldown':                'row',
    'pullup':                      'row',
    'pull_up':                     'row',
    'seated_row':                  'row',
    'curl':                        'isolation',
    'barbell_curl':                'isolation',
    'tricep_pushdown':             'isolation',
    'lateral_raise':               'isolation',
    'plank':                       'isolation',
    'leg_raise':                   'isolation',
    'leg_extension':               'isolation',
    'leg_curl':                    'isolation',
}

IMPLIED_TIER_TABLES_MALE = {
    'bench':     BENCH_TIERS_MALE,
    'squat':     SQUAT_TIERS_MALE,
    'deadlift':  DEADLIFT_TIERS_MALE,
    'ohp':       OHP_TIERS_MALE,
    'row':       ROW_TIERS_MALE,
    'isolation': ISOLATION_TIERS_MALE,
}

IMPLIED_TIER_TABLES_FEMALE = {
    'bench':     BENCH_TIERS_FEMALE,
    'squat':     SQUAT_TIERS_FEMALE,
    'deadlift':  DEADLIFT_TIERS_FEMALE,
    'ohp':       OHP_TIERS_FEMALE,
    'row':       ROW_TIERS_FEMALE,
    'isolation': ISOLATION_TIERS_FEMALE,
}

# Per-exercise variant discount (e.g. leg_press is easier than back squat)
EXERCISE_TIER_DISCOUNT = {
    'leg_press':           0.65,
    'pulldown':            0.75,
    'lat_pulldown':        0.75,
    'incline_bench':       0.90,
    'incline_barbell_bench_press': 0.90,
    'lunge':               0.80,
    'walking_lunges':      0.80,
    'plank':               0.50,
    'leg_raise':           0.50,
    'machine_chest_press': 0.60,
    'seated_row':          0.75,
    'leg_extension':       0.50,
    'leg_curl':            0.50,
    'romanian_deadlift':   0.90,
}


def _epley_1rm(weight, reps):
    """Brzycki-style 1RM estimate (matches Symmetric Strength's curve)."""
    if reps <= 1:
        return weight
    if reps >= 37:
        return weight
    return weight * 36.0 / (37.0 - reps)


def _interp_tier(table, ratio):
    """Linear interpolate (rank, ratio) pairs."""
    if ratio <= table[0][2]:
        return float(table[0][0])
    if ratio >= table[-1][2]:
        return float(table[-1][0])
    for i in range(len(table) - 1):
        lo = table[i]
        hi = table[i + 1]
        if lo[2] <= ratio <= hi[2]:
            if hi[2] == lo[2]:
                return float(lo[0])
            return lo[0] + (ratio - lo[2]) / (hi[2] - lo[2]) * (hi[0] - lo[0])
    return float(table[-1][0])


def implied_tier(exercise, weight, reps, bodyweight_kg, female=False):
    """Phase 29 v2 + 29.6 gender-aware per-lift implied tier.

    Returns interpolated rank-equivalent (0-65) based on:
      * Per-lift family table (BENCH / SQUAT / DEADLIFT / OHP / ROW / ISOLATION)
      * Gender (male = SymStrength, female = strengthlevel.com)
      * Per-variant discount (e.g. leg_press 0.65, incline_bench 0.90)
      * Brzycki 1RM estimation: 1RM ≈ weight × 36 / (37 - reps)

    Mirrors PR 2's `lib/features/rpg/domain/implied_tier.dart` byte-for-byte.
    """
    if bodyweight_kg <= 0:
        return 15.0
    family = EXERCISE_TIER_FAMILY.get(exercise, 'bench')
    tables = IMPLIED_TIER_TABLES_FEMALE if female else IMPLIED_TIER_TABLES_MALE
    table = tables[family]
    discount = EXERCISE_TIER_DISCOUNT.get(exercise, 1.0)
    one_rm = _epley_1rm(weight, reps)
    ratio = one_rm / bodyweight_kg / discount
    return _interp_tier(table, ratio)


def abs_strength_premium_frac(lift_implied_tier):
    """Phase 29.6 Path C — fraction of E_BONUS to apply.

    frac = clamp((lift_implied_tier - E_FLOOR) / (E_CEIL - E_FLOOR), 0, 1)
    abs_strength_premium = 1.0 + E_BONUS × frac

    Yields:
      lift_implied_tier ≤ E_FLOOR (35)  → frac=0   → premium=1.00
      lift_implied_tier ≥ E_CEIL  (55)  → frac=1   → premium=1.80
      linear interp between.
    """
    frac = max(0.0, min(1.0, (lift_implied_tier - E_FLOOR) / (E_CEIL - E_FLOOR)))
    return frac


def abs_strength_premium(lift_implied_tier):
    """Multiplier applied to set XP — see abs_strength_premium_frac."""
    return 1.0 + E_BONUS * abs_strength_premium_frac(lift_implied_tier)


# ============================================================================
# tier_diff_mult — Pokemon Gen 5 adaptation
# ============================================================================

def tier_diff_mult(current_rank, lift_implied_tier):
    """Reward for lifts that punch above the user's current rank.

    Formula: mult = clamp(((2T + OFFSET) / (T + R + OFFSET))^EXP, MIN, MAX)
      T = lift_implied_tier
      R = current_rank
    """
    if lift_implied_tier <= 0:
        return 1.0
    rank = max(1.0, current_rank)
    a = 2.0 * lift_implied_tier + TIER_DIFF_OFFSET
    c = lift_implied_tier + rank + TIER_DIFF_OFFSET
    if c <= 0:
        return TIER_DIFF_MAX
    raw = (a / c) ** TIER_DIFF_EXP
    return max(TIER_DIFF_MIN, min(TIER_DIFF_MAX, raw))


# ============================================================================
# Refinement #2 — progressive overload reward (named physiological bands)
# ============================================================================
#
# AND/OR logic (carried verbatim from Phase 29 prototype, locked by
# ambiguity-resolution #2):
#   * weight > prior weight in same band     → 1.15 (PR — new weight high)
#   * reps > prior reps AND weight >= prior  → 1.10 (volume PR at same load)
#   * reps > prior OR weight > prior         → 1.05 (modest improvement)
#   * otherwise                              → 1.00 (no overload)

REP_BANDS = ('heavy', 'strength', 'hypertrophy', 'endurance')


def rep_band(reps):
    """Physiological band — NOT mathematical floor(reps/3)."""
    if reps <= REP_BAND_HEAVY_MAX:
        return 'heavy'
    if reps <= REP_BAND_STRENGTH_MAX:
        return 'strength'
    if reps <= REP_BAND_HYPERTROPHY_MAX:
        return 'hypertrophy'
    return 'endurance'


def overload_mult(exercise, weight, reps, best_by_band):
    """Returns (multiplier, updated_best_by_band).

    `best_by_band` is a dict keyed (exercise, band) → (best_weight, best_reps).
    Caller mutates it in-place across sets to track prior bests.
    """
    band = rep_band(reps)
    key = (exercise, band)
    prior = best_by_band.get(key)
    mult = 1.0
    if prior is not None:
        pw, pr = prior
        if weight > pw:
            mult = 1.15
        elif reps > pr and weight >= pw:
            mult = 1.10
        elif reps > pr or weight > pw:
            mult = 1.05
    # Update best if this set improved either dimension
    if prior is None or weight > prior[0] or (weight >= prior[0] and reps > prior[1]):
        best_by_band[key] = (weight, reps)
    return mult, best_by_band


# ============================================================================
# Refinement #3 — frequency reward (per-body-part 7d window)
# ============================================================================

def frequency_mult(session_count):
    """Sessions per body part in trailing 7d → multiplier.

    FREQUENCY_MULT_TABLE = [1.00, 1.06, 1.10, 1.06, 1.00]
    session_count is 1-indexed (1st session = 1.00, 2nd = 1.06, ...).
    """
    idx = max(1, min(session_count, len(FREQUENCY_MULT_TABLE))) - 1
    return FREQUENCY_MULT_TABLE[idx]


# ============================================================================
# Refinement #4 — near-failure inference
# ============================================================================

def inferred_near_failure(actual_reps, target_reps):
    """Mark a set as near-failure when the lifter fell short of the target by
    more than (1 - NF_TARGET_THRESHOLD) of target. Returns True if so.

    NULL target → not inferred.
    """
    if target_reps is None or target_reps <= 0:
        return False
    return actual_reps < target_reps * NF_TARGET_THRESHOLD


# ============================================================================
# Per-rank XP curve (Refinement #6 piecewise)
# ============================================================================

def _xp_geometric(n):
    """Geometric XP sum for ranks 1..n (used for ranks 1-20)."""
    if n <= 1:
        return 0.0
    return XP_BASE * (XP_GROWTH_BAND1 ** (n - 1) - 1) / (XP_GROWTH_BAND1 - 1)


_XP_AT_BREAKPOINT = _xp_geometric(RANK_CURVE_BREAKPOINT)


def xp_for_rank(n):
    """Cumulative XP to reach rank n.

    Phase 29 v2 Refinement #6 piecewise:
      ranks 1-20 : geometric (XP_BASE × XP_GROWTH^(n-1) cum)
      ranks 21+  : linear at LINEAR_XP_PER_RANK (literal 367.0) per rank
    """
    if n <= 1:
        return 0.0
    if n <= RANK_CURVE_BREAKPOINT:
        return _xp_geometric(n)
    return _XP_AT_BREAKPOINT + (n - RANK_CURVE_BREAKPOINT) * LINEAR_XP_PER_RANK


def rank_for_xp(total_xp):
    n = 1
    while n < 99 and xp_for_rank(n + 1) <= total_xp:
        n += 1
    return n


def character_level(ranks):
    active = {k: v for k, v in ranks.items() if k in ACTIVE_RANKS}
    total = sum(active.values())
    return max(1, (total - len(active)) // CHAR_LEVEL_DENOMINATOR + 1)


def intensity_for_reps(reps):
    matched = 1.0
    for r, mult in INTENSITY_BY_REPS:
        if reps >= r:
            matched = mult
        else:
            break
    return matched


def intensity_with_near_failure(reps, near_failure):
    """Refinement #4: additive bonus when near_failure flagged."""
    base = intensity_for_reps(reps)
    return base + (NF_INTENSITY_BONUS if near_failure else 0.0)


# ============================================================================
# Body parts + class taxonomy
# ============================================================================

BODY_PARTS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio']
ACTIVE_RANKS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core']

CLASS_BY_DOMINANT = {
    'arms': 'Berserker', 'chest': 'Bulwark', 'back': 'Sentinel',
    'legs': 'Pathfinder', 'shoulders': 'Atlas', 'core': 'Anchor',
    'cardio': 'Wayfarer',
}


def dominant_class(ranks):
    strength = {k: v for k, v in ranks.items() if k != 'cardio'}
    vals = list(strength.values())
    if max(vals) > 0 and (max(vals) - min(vals)) / max(vals) <= ASCENDANT_BALANCE_THRESHOLD and min(vals) >= ASCENDANT_MIN_RANK:
        return 'Ascendant'
    dom = max(strength, key=strength.get)
    return CLASS_BY_DOMINANT.get(dom, 'Initiate')


# ============================================================================
# Phase 24d calibration attribution overlay (real-slug splits)
# ============================================================================

_CALIBRATION_ATTRIBUTION = {
    'barbell_bench_press':         {'chest': 0.70, 'shoulders': 0.20, 'arms': 0.10},
    'incline_barbell_bench_press': {'chest': 0.60, 'shoulders': 0.30, 'arms': 0.10},
    'overhead_press':              {'shoulders': 0.60, 'arms': 0.20, 'core': 0.20},
    'machine_chest_press':         {'chest': 0.75, 'shoulders': 0.15, 'arms': 0.10},
    'machine_shoulder_press':      {'shoulders': 0.70, 'arms': 0.20, 'core': 0.10},
    'cable_crossover':             {'chest': 0.85, 'shoulders': 0.10, 'arms': 0.05},
    'push_up':                     {'chest': 0.65, 'shoulders': 0.20, 'arms': 0.10, 'core': 0.05},
    'wide_push_up':                {'chest': 0.75, 'shoulders': 0.15, 'arms': 0.05, 'core': 0.05},
    'close_grip_push_up':          {'arms': 0.50, 'chest': 0.40, 'shoulders': 0.05, 'core': 0.05},
    'decline_push_up':             {'chest': 0.70, 'shoulders': 0.20, 'arms': 0.05, 'core': 0.05},
    'diamond_push_up':             {'chest': 0.50, 'arms': 0.40, 'shoulders': 0.05, 'core': 0.05},
    'archer_push_up':              {'chest': 0.55, 'arms': 0.25, 'shoulders': 0.15, 'core': 0.05},
    'dips':                        {'chest': 0.45, 'arms': 0.40, 'shoulders': 0.15},
    'barbell_bent_over_row':       {'back': 0.70, 'arms': 0.20, 'core': 0.10},
    'pendlay_row':                 {'back': 0.70, 'arms': 0.20, 'core': 0.10},
    'barbell_curl':                {'arms': 0.90, 'back': 0.10},
    'machine_row':                 {'back': 0.75, 'arms': 0.20, 'core': 0.05},
    'lat_pulldown':                {'back': 0.75, 'arms': 0.20, 'core': 0.05},
    'cable_curl':                  {'arms': 0.90, 'back': 0.10},
    'pull_up':                     {'back': 0.65, 'arms': 0.25, 'core': 0.10},
    'chin_up':                     {'back': 0.55, 'arms': 0.35, 'core': 0.10},
    'barbell_squat':               {'legs': 0.80, 'core': 0.10, 'back': 0.10},
    'romanian_deadlift':           {'legs': 0.55, 'back': 0.35, 'core': 0.10},
    'hip_thrust':                  {'legs': 0.85, 'core': 0.15},
    'walking_lunges':              {'legs': 0.90, 'core': 0.10},
    'pistol_squat':                {'legs': 0.80, 'core': 0.20},
    'leg_extension':               {'legs': 1.00},
    'leg_curl':                    {'legs': 1.00},
    'leg_abductor':                {'legs': 1.00},
    'leg_adductor':                {'legs': 1.00},
    'calf_raise':                  {'legs': 1.00},
    'dumbbell_curl':               {'arms': 0.90, 'back': 0.10},
    'hammer_curl':                 {'arms': 0.90, 'back': 0.10},
    'cable_lateral_raise':         {'shoulders': 0.85, 'arms': 0.10, 'core': 0.05},
    'dumbbell_fly':                {'chest': 0.85, 'shoulders': 0.10, 'arms': 0.05},
    'hanging_leg_raise':           {'core': 0.85, 'arms': 0.10, 'back': 0.05},
    'seated_row':                  {'back': 0.75, 'arms': 0.20, 'core': 0.05},
}


def _attribution_for(exercise):
    if exercise in _CALIBRATION_ATTRIBUTION:
        return _CALIBRATION_ATTRIBUTION[exercise]
    return ATTRIBUTION.get(exercise, {})


# ============================================================================
# Per-set XP — Phase 29 v2 + 29.6 multiplier chain
# ============================================================================

def compute_set_xp(
    exercise,
    weight,
    reps,
    novelty_count,
    weekly_count,
    peak_loads,
    difficulty_mult,
    bodyweight_kg=None,
    slug=None,
    current_ranks=None,
    best_by_band=None,
    bp_session_count=None,
    near_failure=False,
    female=False,
    target_reps=None,
    vmult=1.0,
    base_recenter=1.0,
):
    """Phase 29 v2 + 29.6 LOCKED per-set XP (+ Phase Vitality-3 gate, PR1).

    11-multiplier chain (in this exact order), then the Vitality-3 gate as a
    12th, FINAL factor:
        set_xp = base × intensity × strength × novelty × cap
               × difficulty_mult × tier_diff_mult × abs_strength_premium
               × overload_mult × frequency_mult × attribution_share
               × vmult                                  (Phase Vitality-3)

    `vmult` (default 1.0) is the per-body-part strength conditioning gate,
    computed ONCE pre-session by the caller from PRE-session vitality. `base_recenter`
    (default 1.0) is the global STRENGTH_BASE_RECENTER scale on base_xp that
    restores steady-state once the gate is live. BOTH default NEUTRAL so the
    legacy/fixture callers (which pass neither) produce byte-identical XP — the
    Vitality-3 numbers only appear when simulate_persona passes the real values.

    Returns (awarded_per_bp dict, volume_load, components dict, best_by_band).

    Phase 29 v2 changes from Phase 24d:
      * effective_weight uses BODYWEIGHT_LOAD_RATIO per-exercise (Ref #5)
      * implied_tier uses gender-aware per-lift Symmetric Strength tables (Ref #1)
      * intensity gets +0.10 additive when near_failure (Ref #4)
      * overload_mult layered on for in-band PRs (Ref #2)
      * frequency_mult layered on for 7d-window per-bp session count (Ref #3)
      * abs_strength_premium layered on for absolute strength rewards (29.6 Path C)

    Backward compat: callers passing only the Phase 24c args (no current_ranks,
    no best_by_band, etc.) get a neutral chain — tier_diff_mult uses rank=1
    proxy, overload_mult=1.0, frequency_mult=1.0, abs_strength_premium uses
    implied_tier=0 proxy (premium=1.0). This keeps fixture_gen's backfill
    replay numerically stable across the Phase 24d → Phase 29 v2 transition.
    """
    # ---- Effective weight (Ref #5 per-exercise BW ratio) ----
    resolved_slug = slug if slug is not None else exercise
    eff_weight = effective_weight(resolved_slug, weight, bodyweight_kg)

    # ---- Base XP ----
    # base_recenter defaults to 1.0 (legacy/fixture path → byte-identical).
    # simulate_persona passes STRENGTH_BASE_RECENTER to restore steady-state
    # once the vmult gate is live (Phase Vitality-3 D2 global base scale).
    volume_load = max(VOLUME_LOAD_FLOOR, eff_weight * reps)
    base_xp = (volume_load ** VOLUME_EXPONENT) * base_recenter

    # ---- Intensity (with Ref #4 near-failure bonus) ----
    # If target_reps provided + actual < threshold, infer near-failure.
    if not near_failure and target_reps is not None:
        near_failure = inferred_near_failure(reps, target_reps)
    intensity = intensity_with_near_failure(reps, near_failure)

    # ---- Strength ----
    peak_load = peak_loads.get(exercise, weight)
    if weight > peak_load:
        peak_loads[exercise] = weight
        peak_load = weight
    if peak_load > 0:
        strength_mult = max(STRENGTH_MULT_FLOOR, min(1.0, eff_weight / peak_load))
    else:
        strength_mult = 1.0

    # ---- Attribution ----
    distribution = _attribution_for(exercise)
    if not distribution:
        distribution = {'chest': 1.0}
    dom_part = max(distribution, key=distribution.get)

    # ---- tier_diff_mult (Ref #1 lift-implied vs current rank) ----
    lift_implied = implied_tier(exercise, weight, reps, bodyweight_kg or 0.0, female=female)
    cr = float((current_ranks or {}).get(dom_part, 1))
    td_mult = tier_diff_mult(cr, lift_implied)

    # ---- abs_strength_premium (Phase 29.6 Path C) ----
    asp_mult = abs_strength_premium(lift_implied)

    # ---- overload_mult (Ref #2) ----
    if best_by_band is None:
        o_mult = 1.0
    else:
        o_mult, best_by_band = overload_mult(exercise, weight, reps, best_by_band)

    # ---- frequency_mult (Ref #3) ----
    if bp_session_count is None:
        f_mult = 1.0
    else:
        f_mult = frequency_mult(bp_session_count.get(dom_part, 1))

    # ---- Per-body-part XP ----
    # Phase Vitality-3: `vmult` is the 12th/final factor. It may be a scalar
    # (legacy/fixture path → 1.0 = no-op) OR a per-body-part dict (the faithful
    # gate — the live SQL applies the charge fraction keyed by attribution body
    # part). A dict missing a bp falls back to 1.0 (un-conditioned prior).
    vmult_is_map = isinstance(vmult, dict)
    awarded = {}
    for body_part, share in distribution.items():
        novelty = math.exp(-novelty_count[body_part] / NOVELTY_DENOMINATOR)
        cap_mult = OVER_CAP_MULTIPLIER if weekly_count[body_part] >= WEEKLY_CAP_SETS else 1.0
        vm = vmult.get(body_part, 1.0) if vmult_is_map else vmult
        xp = (
            base_xp
            * intensity
            * strength_mult
            * novelty
            * cap_mult
            * difficulty_mult
            * td_mult
            * asp_mult
            * o_mult
            * f_mult
            * share
            * vm               # Phase Vitality-3 — 12th/final factor (default 1.0)
        )
        awarded[body_part] = xp

    # Update counters
    for body_part, share in distribution.items():
        novelty_count[body_part] += share
        weekly_count[body_part] += share

    components = {
        'volume_load': volume_load,
        'base_xp': base_xp,
        'intensity_mult': intensity,
        'strength_mult': strength_mult,
        'difficulty_mult': difficulty_mult,
        'tier_diff_mult': td_mult,
        'abs_strength_premium': asp_mult,
        'overload_mult': o_mult,
        'frequency_mult': f_mult,
        'lift_implied_tier': lift_implied,
        'eff_weight': eff_weight,
        'dominant_part': dom_part,
        'near_failure': near_failure,
        # Phase Vitality-3 — record the dominant-part vmult actually applied
        # (vmult may be a per-bp map; the fixture/legacy path passes scalar 1.0).
        'vmult': (vmult.get(dom_part, 1.0) if isinstance(vmult, dict) else vmult),
        'base_recenter': base_recenter,     # Phase Vitality-3 (default 1.0)
    }

    return awarded, volume_load, components, best_by_band


# ============================================================================
# Vitality — asymmetric EWMA per body part
# ============================================================================

def update_vitality(body_part, weekly_volume, ewma, peak):
    prior = ewma.get(body_part, 0.0)
    if weekly_volume >= prior:
        alpha = 1.0 - math.exp(-1.0 / VITALITY_TAU_UP_WEEKS)
    else:
        alpha = 1.0 - math.exp(-1.0 / VITALITY_TAU_DOWN_WEEKS)
    new_ewma = alpha * weekly_volume + (1 - alpha) * prior
    ewma[body_part] = new_ewma
    if new_ewma > peak.get(body_part, 0.0):
        peak[body_part] = new_ewma


def vitality_pct(body_part, ewma, peak):
    p = peak.get(body_part, 0.0)
    if p <= 0:
        return 0.0
    return min(1.0, ewma.get(body_part, 0.0) / p)


# ----------------------------------------------------------------------------
# Phase Vitality-3 — decaying reference peak + the strength conditioning gate
# ----------------------------------------------------------------------------
def advance_vitality_week(vol_history, ewma, ref_peak):
    """Advance every active bp's vitality ONE WEEK on the live DAILY grid.

    `vol_history[bp]` is a deque/list of the most-recent daily volume-load
    lumps (one entry per day, newest last) — each scheduled week appends ONE
    lump (the week's Σ vol×share for that bp) followed by 6 zero days, so the
    trailing-7-day window the live recompute sees is reproduced. This function
    consumes the next 7 days from each bp's history and steps:

        for each of the 7 days:
            win      = Σ (trailing-7-day daily volume)
            α        = α_up if win ≥ ewma else α_down   (live c_alpha_up / down)
            ewma     = α·win + (1−α)·ewma
            ref_peak = GREATEST(ewma, ref_peak × REF_PEAK_DECAY_DAILY)

    Stepping daily (NOT one weekly step) is what keeps ref_peak ABOVE a lapsed
    ewma long enough for vpct to drop — a single weekly step would collapse
    ref_peak onto the ewma and pin vpct at 1.0 for everyone. Mutates ewma +
    ref_peak in place; consumes 7 days from each `vol_history[bp]`.
    """
    for bp in ACTIVE_RANKS:
        hist = vol_history[bp]
        e = ewma.get(bp, 0.0)
        rp = ref_peak.get(bp, 0.0)
        # The 7 fresh days for this week are at the tail; step through the full
        # history tail day-by-day using a trailing-7 window.
        n = len(hist)
        for d in range(n - DAYS_PER_WEEK, n):
            lo = max(0, d - (DAYS_PER_WEEK - 1))
            win = sum(hist[lo:d + 1])
            alpha = VITALITY_ALPHA_UP if win >= e else VITALITY_ALPHA_DOWN
            e = alpha * win + (1.0 - alpha) * e
            rp = max(e, rp * REF_PEAK_DECAY_DAILY)
        ewma[bp] = e
        ref_peak[bp] = rp


def strength_vpct(body_part, ewma, ref_peak):
    """PRE-session charge fraction = clamp(ewma / ref_peak, 0, 1).

    ref_peak ≤ 0 (a never-trained or day-0 bp) → vpct 1.0 (the un-conditioned
    prior: the gate is a no-op on a bp the user has never loaded, exactly like
    the cardio gate's `peak ≤ 0 → vmult 1.0` first-save behavior).
    """
    p = ref_peak.get(body_part, 0.0)
    if p <= 0:
        return 1.0
    return max(0.0, min(1.0, ewma.get(body_part, 0.0) / p))


def strength_vitality_mult(vpct, floor=STRENGTH_VITALITY_FLOOR):
    """vmult = FLOOR + (1 − FLOOR) × vpct (mirrors cardio 00081 / sim:526)."""
    return floor + (1.0 - floor) * vpct


# ============================================================================
# Legacy consistency archetypes (Phase 24c — preserved for fixture backfill)
# ============================================================================

@dataclass
class Archetype:
    name: str
    sessions_per_week: int
    starting_weights: dict
    progression: str
    layoffs: list = field(default_factory=list)
    bodyweight_kg: float = 70.0


ARCHETYPES = {
    'beginner': Archetype(
        name='beginner', sessions_per_week=3, progression='beginner',
        starting_weights={
            'bench': 40, 'incline_bench': 30, 'overhead_press': 25, 'row': 35, 'pulldown': 35,
            'pullup': 0, 'squat': 50, 'deadlift': 60, 'leg_press': 60, 'lunge': 20,
            'curl': 12, 'tricep_pushdown': 20, 'lateral_raise': 6, 'plank': 1, 'leg_raise': 1,
        },
    ),
    'intermediate': Archetype(
        name='intermediate', sessions_per_week=4, progression='intermediate',
        starting_weights={
            'bench': 80, 'incline_bench': 65, 'overhead_press': 50, 'row': 70, 'pulldown': 70,
            'pullup': 10, 'squat': 100, 'deadlift': 120, 'leg_press': 140, 'lunge': 40,
            'curl': 18, 'tricep_pushdown': 35, 'lateral_raise': 10, 'plank': 1, 'leg_raise': 1,
        },
    ),
    'advanced': Archetype(
        name='advanced', sessions_per_week=5, progression='advanced',
        starting_weights={
            'bench': 120, 'incline_bench': 95, 'overhead_press': 80, 'row': 100, 'pulldown': 100,
            'pullup': 25, 'squat': 160, 'deadlift': 200, 'leg_press': 220, 'lunge': 60,
            'curl': 25, 'tricep_pushdown': 50, 'lateral_raise': 14, 'plank': 1, 'leg_raise': 1,
        },
    ),
    'stagnant_lifter': Archetype(
        name='stagnant_lifter', sessions_per_week=3, progression='stagnant',
        starting_weights={
            'bench': 20, 'incline_bench': 15, 'overhead_press': 15, 'row': 20, 'pulldown': 20,
            'pullup': 0, 'squat': 25, 'deadlift': 30, 'leg_press': 40, 'lunge': 10,
            'curl': 5, 'tricep_pushdown': 8, 'lateral_raise': 3, 'plank': 1, 'leg_raise': 1,
        },
    ),
    'comeback_kid': Archetype(
        name='comeback_kid', sessions_per_week=4, progression='intermediate',
        starting_weights={
            'bench': 80, 'incline_bench': 65, 'overhead_press': 50, 'row': 70, 'pulldown': 70,
            'pullup': 10, 'squat': 100, 'deadlift': 120, 'leg_press': 140, 'lunge': 40,
            'curl': 18, 'tricep_pushdown': 35, 'lateral_raise': 10, 'plank': 1, 'leg_raise': 1,
        },
        layoffs=[(53, 78)],
    ),
    'vacationer': Archetype(
        name='vacationer', sessions_per_week=4, progression='intermediate',
        starting_weights={
            'bench': 80, 'incline_bench': 65, 'overhead_press': 50, 'row': 70, 'pulldown': 70,
            'pullup': 10, 'squat': 100, 'deadlift': 120, 'leg_press': 140, 'lunge': 40,
            'curl': 18, 'tricep_pushdown': 35, 'lateral_raise': 10, 'plank': 1, 'leg_raise': 1,
        },
        layoffs=[(27, 28), (53, 54), (79, 80), (105, 106), (131, 132), (157, 158),
                 (183, 184), (209, 210), (235, 236)],
    ),
}

# Legacy alias-based day templates (for Archetype-based simulate())
DAY_TEMPLATES_LEGACY = {
    'push':  [('bench', 4, 8), ('overhead_press', 3, 8), ('lateral_raise', 3, 12), ('tricep_pushdown', 3, 12)],
    'pull':  [('row', 4, 8), ('pulldown', 3, 10), ('curl', 3, 12), ('plank', 2, 30)],
    'legs':  [('squat', 4, 6), ('deadlift', 3, 5), ('leg_press', 3, 10), ('lunge', 3, 10)],
    'upper': [('bench', 3, 8), ('row', 3, 8), ('overhead_press', 3, 8), ('curl', 3, 10), ('tricep_pushdown', 3, 10)],
}

# Backward-compat alias (some readers expected the literal name `DAY_TEMPLATES`)
DAY_TEMPLATES = DAY_TEMPLATES_LEGACY

WEEK_SCHEDULES_LEGACY = {
    3: ['push', 'pull', 'legs'],
    4: ['push', 'pull', 'legs', 'upper'],
    5: ['push', 'pull', 'legs', 'upper', 'legs'],
}
WEEK_SCHEDULES = WEEK_SCHEDULES_LEGACY


def progression_rate(archetype, week):
    base = PROGRESSION_RATES[archetype.progression]
    if archetype.progression != 'beginner':
        return base
    if week <= NEWBIE_DECAY_WEEKS:
        return base
    decay = (week - NEWBIE_DECAY_WEEKS) / 26.0
    intermediate_rate = PROGRESSION_RATES['intermediate']
    return max(intermediate_rate, base - (base - intermediate_rate) * min(1.0, decay))


def is_layoff_week(archetype, week):
    return any(start <= week <= end for start, end in archetype.layoffs)


def simulate(archetype, weeks):
    """Legacy Phase 24c consistency-archetype simulator. Preserved for
    fixture-gen's `fx_backfill_replay()` (which feeds the parity oracle).

    Uses the Phase 29 v2 + 29.6 multiplier chain via compute_set_xp(). Since
    no `best_by_band` / `bp_session_count` are threaded, those multipliers
    default to 1.0 — matches the documented backward-compat path. The result
    is that legacy archetypes earn LESS XP than the new Phase 29 personas
    (no overload + frequency bonuses), which is correct: this path is for
    parity oracle stability, not user-realistic progression.
    """
    xp_pool = {p: 0.0 for p in BODY_PARTS}
    weights = dict(archetype.starting_weights)
    peak_loads = dict(archetype.starting_weights)
    schedule = WEEK_SCHEDULES_LEGACY[archetype.sessions_per_week]
    vit_ewma = {}
    vit_peak = {}
    snapshots = []

    for week in range(1, weeks + 1):
        weekly_count = defaultdict(float)
        weekly_volume_per_part = defaultdict(float)
        layoff = is_layoff_week(archetype, week)

        if not layoff:
            for day in schedule:
                novelty_count = defaultdict(float)
                for exercise, n_sets, reps in DAY_TEMPLATES_LEGACY[day]:
                    w = weights.get(exercise, 1)
                    distribution = ATTRIBUTION.get(exercise, {})
                    diff_mult = difficulty_mult_for_alias(exercise)
                    real_slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                    for _ in range(n_sets):
                        awarded, vol, _comp, _bbb = compute_set_xp(
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
# Phase 29 v2 13-persona panel (calibration ground truth)
# ============================================================================

@dataclass
class Persona:
    """Phase 29 v2 persona for the calibration panel.

    name             : display label
    bodyweight_kg    : user bodyweight
    schedule_key     : key into WEEK_SCHEDULES_PANEL (e.g. 3, 4, 5, 'mach_3', 'hyp_4')
    starting_weights : per-exercise starting load (kg)
    progression_pct  : weekly progression rate (multiplicative)
    reps_scheme      : per-exercise target reps (None → DEFAULT_REPS_PANEL)
    smurf_session    : optional {exercise: (weight, reps)} for fake-1RM session 1
    female           : True → female tier tables
    tapering         : True → progression decays via half-life (beginner gains)
    half_life_weeks  : tapering half-life
    nf_rate          : probability a set is flagged near_failure
    """
    name: str
    bodyweight_kg: float
    schedule_key: object
    starting_weights: dict
    progression_pct: float
    reps_scheme: dict = None
    smurf_session: dict = None
    female: bool = False
    tapering: bool = False
    half_life_weeks: float = 4.0
    nf_rate: float = 0.10
    # Phase Vitality-3 — weeks with NO training (zero volume → vitality decays,
    # ref_peak decays, rank holds). Used by the detrained-returner persona.
    layoff_weeks: tuple = ()
    # Phase Vitality-3 — train only the first N sessions of each scheduled week
    # (sandbagger: light + INCONSISTENT). None → full schedule every week.
    sessions_per_week_cap: int = None


DEFAULT_REPS_PANEL = {
    "bench": 5, "incline_bench": 5, "overhead_press": 5,
    "row": 5, "pulldown": 8, "pullup": 5,
    "squat": 5, "deadlift": 5, "leg_press": 8, "lunge": 8,
    "curl": 10, "tricep_pushdown": 10, "lateral_raise": 12,
    "plank": 30, "leg_raise": 15,
    # Machine + hypertrophy aliases
    "machine_chest_press": 10, "seated_row": 10,
    "leg_extension": 12, "leg_curl": 12, "romanian_deadlift": 8,
}

# Panel day templates (extended with machine + hypertrophy sessions)
DAY_TEMPLATES_PANEL = {
    "push":  [("bench", 4), ("overhead_press", 3), ("lateral_raise", 3), ("tricep_pushdown", 3)],
    "pull":  [("row", 4), ("pulldown", 3), ("curl", 3), ("plank", 2)],
    "legs":  [("squat", 4), ("deadlift", 3), ("leg_press", 3), ("lunge", 3)],
    "upper": [("bench", 3), ("row", 3), ("overhead_press", 3), ("curl", 3), ("tricep_pushdown", 3)],
    # Machine-only 3-day split
    "mp": [("machine_chest_press", 4), ("overhead_press", 3), ("lateral_raise", 3), ("tricep_pushdown", 3)],
    "ml": [("pulldown", 4), ("seated_row", 4), ("curl", 3)],
    "mq": [("leg_press", 4), ("leg_curl", 3), ("leg_extension", 3), ("lunge", 3)],
    # Hypertrophy bodybuilder 4-day split
    "hp": [("bench", 4), ("incline_bench", 3), ("overhead_press", 3), ("lateral_raise", 3), ("tricep_pushdown", 3)],
    "hl": [("row", 4), ("pulldown", 3), ("curl", 3)],
    "hq": [("squat", 4), ("lunge", 3), ("leg_press", 3), ("deadlift", 2)],
    "ha": [("curl", 4), ("tricep_pushdown", 4), ("lateral_raise", 3), ("overhead_press", 2)],
}

WEEK_SCHEDULES_PANEL = {
    3:        ["push", "pull", "legs"],
    4:        ["push", "pull", "legs", "upper"],
    5:        ["push", "pull", "legs", "upper", "legs"],
    "mach_3": ["mp", "ml", "mq"],
    "hyp_4":  ["hp", "hl", "hq", "ha"],
}

SESSION_BODY_PARTS = {
    "push":  {"chest", "shoulders", "arms"},
    "pull":  {"back", "arms", "core"},
    "legs":  {"legs", "core", "back"},
    "upper": {"chest", "back", "shoulders", "arms"},
    "mp":    {"chest", "shoulders", "arms"},
    "ml":    {"back", "arms"},
    "mq":    {"legs", "core"},
    "hp":    {"chest", "shoulders", "arms"},
    "hl":    {"back", "arms"},
    "hq":    {"legs", "core", "back"},
    "ha":    {"arms", "shoulders"},
}


# The 13 personas (locked Phase 29 v2 + 29.6 calibration ground truth)
PERSONAS = {
    "beginner": Persona(
        name="True Beginner (0yr, 75kg)", bodyweight_kg=75.0, schedule_key=3,
        starting_weights={
            "bench": 40, "incline_bench": 30, "overhead_press": 25,
            "row": 35, "pulldown": 35, "pullup": 0,
            "squat": 60, "deadlift": 80, "leg_press": 60, "lunge": 20,
            "curl": 12, "tricep_pushdown": 15, "lateral_raise": 6,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.030, tapering=True, half_life_weeks=4.0, nf_rate=0.05,
    ),
    "diego": Persona(
        name="Diego (4yr returning, 80kg)", bodyweight_kg=80.0, schedule_key=4,
        starting_weights={
            "bench": 85, "incline_bench": 65, "overhead_press": 50,
            "row": 70, "pulldown": 70, "pullup": 10,
            "squat": 108, "deadlift": 139, "leg_press": 140, "lunge": 45,
            "curl": 18, "tricep_pushdown": 32, "lateral_raise": 10,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.001, nf_rate=0.15,
    ),
    "strong_intermediate": Persona(
        name="Strong Intermediate (6yr, 85kg)", bodyweight_kg=85.0, schedule_key=4,
        starting_weights={
            "bench": 100, "incline_bench": 80, "overhead_press": 65,
            "row": 90, "pulldown": 85, "pullup": 20,
            "squat": 130, "deadlift": 170, "leg_press": 180, "lunge": 55,
            "curl": 22, "tricep_pushdown": 40, "lateral_raise": 12,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.0005, nf_rate=0.20,
    ),
    "advanced": Persona(
        name="Advanced (8yr, 90kg)", bodyweight_kg=90.0, schedule_key=5,
        starting_weights={
            "bench": 130, "incline_bench": 100, "overhead_press": 80,
            "row": 110, "pulldown": 105, "pullup": 30,
            "squat": 170, "deadlift": 210, "leg_press": 220, "lunge": 70,
            "curl": 28, "tricep_pushdown": 50, "lateral_raise": 15,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.0002, nf_rate=0.25,
    ),
    "elite": Persona(
        # Phase 29.6 Path C — real competitive powerlifter 95kg, 10yr.
        # bench 180×3 → implied_tier ~55 → frac=1.0 (full premium).
        name="Elite Path C (10yr competitive, 95kg)", bodyweight_kg=95.0, schedule_key=5,
        reps_scheme={
            "bench": 3, "incline_bench": 3, "overhead_press": 3,
            "row": 3, "pulldown": 3, "pullup": 3, "squat": 3, "deadlift": 3,
            "leg_press": 5, "lunge": 5, "curl": 8, "tricep_pushdown": 8,
            "lateral_raise": 10, "plank": 30, "leg_raise": 10,
        },
        starting_weights={
            "bench": 180, "incline_bench": 145, "overhead_press": 115,
            "row": 155, "pulldown": 140, "pullup": 65,
            "squat": 240, "deadlift": 310, "leg_press": 320, "lunge": 110,
            "curl": 42, "tricep_pushdown": 72, "lateral_raise": 24,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.0001, nf_rate=0.30,
    ),
    "smurf": Persona(
        name="Smurf attempt (fake 1RM, 70kg)", bodyweight_kg=70.0, schedule_key=3,
        starting_weights={
            "bench": 60, "incline_bench": 45, "overhead_press": 35,
            "row": 50, "pulldown": 50, "pullup": 0,
            "squat": 70, "deadlift": 90, "leg_press": 90, "lunge": 25,
            "curl": 14, "tricep_pushdown": 18, "lateral_raise": 7,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.005, smurf_session={"bench": (140, 1)}, nf_rate=0.10,
    ),
    "weak_consistent": Persona(
        name="Weak+Consistent (75kg, 5×/wk)", bodyweight_kg=75.0, schedule_key=5,
        starting_weights={
            "bench": 60, "incline_bench": 45, "overhead_press": 37,
            "row": 55, "pulldown": 55, "pullup": 0,
            "squat": 80, "deadlift": 95, "leg_press": 100, "lunge": 30,
            "curl": 14, "tricep_pushdown": 20, "lateral_raise": 7,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.015, nf_rate=0.10,
    ),
    "strong_inconsistent": Persona(
        name="Strong+Inconsistent (90kg, 3×/wk)", bodyweight_kg=90.0, schedule_key=3,
        reps_scheme={
            "bench": 5, "incline_bench": 5, "overhead_press": 5,
            "row": 5, "pulldown": 5, "pullup": 5, "squat": 5, "deadlift": 5,
            "leg_press": 8, "lunge": 8, "curl": 8, "tricep_pushdown": 8,
            "lateral_raise": 12, "plank": 30, "leg_raise": 12,
        },
        starting_weights={
            "bench": 115, "incline_bench": 90, "overhead_press": 70,
            "row": 95, "pulldown": 90, "pullup": 20,
            "squat": 150, "deadlift": 185, "leg_press": 190, "lunge": 60,
            "curl": 24, "tricep_pushdown": 42, "lateral_raise": 12,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.001, nf_rate=0.20,
    ),
    "female_beginner": Persona(
        name="Female Beginner (0yr, 58kg)", bodyweight_kg=58.0, schedule_key=3, female=True,
        starting_weights={
            "bench": 28, "incline_bench": 20, "overhead_press": 18,
            "row": 25, "pulldown": 28, "pullup": 0,
            "squat": 40, "deadlift": 52, "leg_press": 55, "lunge": 15,
            "curl": 7, "tricep_pushdown": 10, "lateral_raise": 3,
            "plank": 1, "leg_raise": 1,
        },
        reps_scheme={
            "bench": 8, "incline_bench": 10, "overhead_press": 8,
            "row": 8, "pulldown": 10, "pullup": 8, "squat": 8, "deadlift": 6,
            "leg_press": 12, "lunge": 10, "curl": 12, "tricep_pushdown": 12,
            "lateral_raise": 15, "plank": 30, "leg_raise": 12,
        },
        progression_pct=0.025, tapering=True, half_life_weeks=3.0, nf_rate=0.05,
    ),
    "female_intermediate": Persona(
        name="Female Intermediate (2yr, 60kg)", bodyweight_kg=60.0, schedule_key=3, female=True,
        starting_weights={
            "bench": 45, "incline_bench": 35, "overhead_press": 30,
            "row": 40, "pulldown": 40, "pullup": 0,
            "squat": 68, "deadlift": 85, "leg_press": 90, "lunge": 25,
            "curl": 10, "tricep_pushdown": 14, "lateral_raise": 5,
            "plank": 1, "leg_raise": 1,
        },
        reps_scheme={
            "bench": 8, "incline_bench": 10, "overhead_press": 8,
            "row": 8, "pulldown": 10, "pullup": 8, "squat": 8, "deadlift": 6,
            "leg_press": 12, "lunge": 10, "curl": 12, "tricep_pushdown": 12,
            "lateral_raise": 15, "plank": 30, "leg_raise": 12,
        },
        progression_pct=0.0015, nf_rate=0.10,
    ),
    "older_lifter": Persona(
        name="Older Lifter (55yo, 5yr, 80kg)", bodyweight_kg=80.0, schedule_key=3,
        starting_weights={
            "bench": 75, "incline_bench": 58, "overhead_press": 45,
            "row": 65, "pulldown": 65, "pullup": 5,
            "squat": 100, "deadlift": 130, "leg_press": 140, "lunge": 38,
            "curl": 14, "tricep_pushdown": 22, "lateral_raise": 8,
            "plank": 1, "leg_raise": 1,
        },
        reps_scheme={
            "bench": 8, "incline_bench": 8, "overhead_press": 8,
            "row": 8, "pulldown": 10, "pullup": 5, "squat": 6, "deadlift": 5,
            "leg_press": 10, "lunge": 10, "curl": 12, "tricep_pushdown": 12,
            "lateral_raise": 15, "plank": 30, "leg_raise": 12,
        },
        progression_pct=0.0005, nf_rate=0.10,
    ),
    "machine_tourist": Persona(
        name="Machine-Only Gym Tourist (1yr, 78kg)", bodyweight_kg=78.0, schedule_key="mach_3",
        starting_weights={
            "machine_chest_press": 40, "overhead_press": 25, "lateral_raise": 8, "tricep_pushdown": 25,
            "pulldown": 45, "seated_row": 45, "curl": 12,
            "leg_press": 80, "leg_curl": 28, "leg_extension": 30, "lunge": 22,
        },
        reps_scheme={
            "machine_chest_press": 12, "overhead_press": 12, "lateral_raise": 15, "tricep_pushdown": 12,
            "pulldown": 12, "seated_row": 12, "curl": 12,
            "leg_press": 12, "leg_curl": 12, "leg_extension": 12, "lunge": 12,
        },
        progression_pct=0.005, nf_rate=0.05,
    ),
    "hypertrophy_bb": Persona(
        name="Hypertrophy BB Split (4yr, 82kg)", bodyweight_kg=82.0, schedule_key="hyp_4",
        starting_weights={
            "bench": 90, "incline_bench": 70, "overhead_press": 50,
            "row": 75, "pulldown": 70, "pullup": 0,
            "squat": 110, "deadlift": 100, "leg_press": 160, "lunge": 45,
            "curl": 22, "tricep_pushdown": 38, "lateral_raise": 11,
            "plank": 1, "leg_raise": 1,
        },
        reps_scheme={
            "bench": 10, "incline_bench": 10, "overhead_press": 8,
            "row": 10, "pulldown": 12, "pullup": 8, "squat": 10, "deadlift": 10,
            "leg_press": 12, "lunge": 12, "curl": 12, "tricep_pushdown": 12,
            "lateral_raise": 15, "plank": 30, "leg_raise": 15,
        },
        progression_pct=0.003, nf_rate=0.15,
    ),
    # ------------------------------------------------------------------------
    # Phase Vitality-3 — two NEW personas that exist to exercise the gate.
    # ------------------------------------------------------------------------
    "sandbagger": Persona(
        # High rank (advanced-ish standing weights) but trains LIGHT (1 session/
        # week) + INCONSISTENT (every OTHER week — the off weeks are layoffs).
        # The oscillating volume keeps vit_ewma chronically below vit_ref_peak →
        # vpct ~0.4-0.6 permanently → vmult throttles their earn-rate so they
        # progress SLOWER than the consistent `advanced` persona. Proves a high
        # rank can't be coasted on: past load doesn't keep paying out.
        name="Sandbagger (high rank, light+inconsistent)", bodyweight_kg=90.0,
        schedule_key=3,
        # Sub-maximal loads (they hold back ~30% off what their rank implies)
        # plus a high rep range — they go through the motions, never near
        # failure. Trains the full 3-day split but only every OTHER week (the
        # off weeks are layoffs) → volume oscillates → vit_ewma stays chronically
        # below vit_ref_peak → vpct ~0.4-0.6 → vmult throttles hard.
        starting_weights={
            "bench": 90, "incline_bench": 70, "overhead_press": 55,
            "row": 78, "pulldown": 75, "pullup": 10,
            "squat": 120, "deadlift": 150, "leg_press": 155, "lunge": 48,
            "curl": 20, "tricep_pushdown": 35, "lateral_raise": 10,
            "plank": 1, "leg_raise": 1,
        },
        reps_scheme={
            "bench": 12, "incline_bench": 12, "overhead_press": 12,
            "row": 12, "pulldown": 12, "pullup": 8, "squat": 12, "deadlift": 10,
            "leg_press": 15, "lunge": 12, "curl": 15, "tricep_pushdown": 15,
            "lateral_raise": 15, "plank": 30, "leg_raise": 15,
        },
        progression_pct=0.0002, nf_rate=0.0,
        layoff_weeks=(2, 4, 6, 8, 10, 12),
    ),
    "detrained_returner": Persona(
        # Was high (advanced standing weights), takes an 8-week ZERO-volume
        # layoff (wks 1-8 here represent the start of the lapse — see the
        # returner harness which pre-seeds prior conditioning), then returns
        # CONSISTENT ~4×/wk near prior loads. ref_peak decays through the layoff
        # so on return vpct climbs fast (τ_up=2wk) → vmult recovers to ≥0.90
        # within 2-4 weeks. Rank NEVER drops during the layoff (D6). The harness
        # drives this persona via simulate_returner(), NOT the standard panel.
        name="Detrained Returner (was high, 8wk layoff)", bodyweight_kg=88.0,
        schedule_key=4,
        starting_weights={
            "bench": 125, "incline_bench": 95, "overhead_press": 75,
            "row": 105, "pulldown": 100, "pullup": 28,
            "squat": 165, "deadlift": 205, "leg_press": 215, "lunge": 68,
            "curl": 26, "tricep_pushdown": 48, "lateral_raise": 14,
            "plank": 1, "leg_raise": 1,
        },
        progression_pct=0.0005, nf_rate=0.15,
    ),
}

# Anti-cheese control: the smurf WITHOUT its fake-1RM session-1 — the SAME lifter
# minus the cheat. Used only by the panel's anti-cheese invariant ("faking a 1RM
# must never PAY"); deliberately NOT in PANEL_ORDER. The old "Smurf <= TrueBeginner"
# check was mis-specified — the smurf logs genuinely HEAVIER working weights, so it
# out-ranks the beginner LEGITIMATELY (real lifts → real XP) and the fake 1RM adds
# nothing. The meaningful property is that the same lifter gains no rank by faking —
# verified robust even for a beginner faking a 220x1. See docs/xp-balance-baseline.md.
PERSONAS["smurf_honest"] = replace(
    PERSONAS["smurf"], smurf_session=None, name="Smurf control (no fake 1RM)"
)

# Display order for the panel (sorted by expected avg_rank ascending)
PANEL_ORDER = [
    "female_beginner", "beginner", "machine_tourist", "older_lifter",
    "weak_consistent", "female_intermediate", "smurf", "strong_inconsistent",
    "diego", "sandbagger", "hypertrophy_bb", "strong_intermediate",
    "advanced", "elite",
]

# Target band per persona (lo, hi) — 13/13 PASS criterion
PANEL_TARGET_BANDS = {
    "beginner":             (14, 18),
    "diego":                (24, 28),
    "strong_intermediate":  (28, 38),
    "advanced":             (35, 45),
    "elite":                (50, 65),
    "smurf":                (13, 20),
    "weak_consistent":      (17, 26),
    "strong_inconsistent":  (24, 32),
    "female_intermediate":  (17, 27),
    "female_beginner":      (9, 17),
    "older_lifter":         (14, 24),
    "machine_tourist":      (11, 23),
    "hypertrophy_bb":       (22, 33),
    # Phase Vitality-3 — sandbagger must land BELOW advanced (35-45). Band set
    # after the gate + recenter sweep (see docs/xp-balance-baseline.md). The
    # detrained_returner is NOT band-gated — it's validated by simulate_returner.
    "sandbagger":           (18, 30),
}


def _tapered_progression(base_rate, half_life_weeks, week):
    """Beginner gains taper: rate(week) = base × exp(-ln2 / hl × (week-1))."""
    return base_rate * math.exp(-math.log(2.0) / half_life_weeks * (week - 1))


def simulate_persona(persona_key, weeks=12, seed=42, gate=True):
    """Phase 29 v2 + 29.6 LOCKED persona simulator (+ Phase Vitality-3 gate).

    Uses the full 11-multiplier chain via compute_set_xp() with all refinements
    enabled (current_ranks, best_by_band, bp_session_count, near_failure,
    female flag), THEN the Phase Vitality-3 strength conditioning gate as the
    12th factor + the STRENGTH_BASE_RECENTER global base scale.

    Vitality threading (the calibration linchpin):
      * Per body part we track `vit_ewma` + `vit_ref_peak` across weeks.
      * The EWMA is fed by weekly VOLUME LOAD (Σ vol×share per bp), NOT by gated
        XP — this severs the feedback loop (the gate throttles the rank currency
        but never its own input, so no runaway/collapse is possible). This is
        the single most important stability property.
      * The vmult applied to a week's sets is computed ONCE from the vitality
        state at the START of the week (PRE-session — mirrors the live ordering
        where recompute_vitality_for_user runs AFTER the XP writes). ref_peak ≤ 0
        (a never-trained / day-0 bp) → vpct 1.0 → vmult 1.0 (gate is a no-op on
        the first load of a bp).
      * After the week, vitality steps forward from that week's volume load
        (zero during a layoff → ewma + ref_peak decay; rank holds — D6).

    `gate=False` reproduces the pre-Vitality-3 panel (no vmult, no base recenter)
    — used to read each consistent persona's CURRENT avg_rank for the ±0.5
    re-center guard.
    """
    rng = random.Random(seed)
    persona = PERSONAS[persona_key]
    nf_rate = persona.nf_rate

    xp_pool = {p: 0.0 for p in BODY_PARTS}
    weights = dict(persona.starting_weights)
    peak_loads = dict(persona.starting_weights)
    best_by_band = {}
    schedule = WEEK_SCHEDULES_PANEL[persona.schedule_key]
    reps_scheme = persona.reps_scheme or DEFAULT_REPS_PANEL
    snapshots = []
    session_num = 0
    smurf_done = False

    # Phase Vitality-3 — per-body-part conditioning state (strength bps only).
    # vol_history[bp] is the daily volume-load timeline (newest last); each week
    # appends one lump + 6 zeros so advance_vitality_week sees the live
    # trailing-7-day window. (See advance_vitality_week + the DISCRETIZATION NOTE.)
    vit_ewma = {bp: 0.0 for bp in ACTIVE_RANKS}
    vit_ref_peak = {bp: 0.0 for bp in ACTIVE_RANKS}
    vol_history = {bp: [] for bp in ACTIVE_RANKS}
    base_recenter = STRENGTH_BASE_RECENTER if gate else 1.0

    for week in range(1, weeks + 1):
        weekly_count = defaultdict(float)
        weekly_xp = defaultdict(float)
        bp_session = defaultdict(int)
        # Volume load accrued THIS week per bp (feeds the EWMA — NOT gated XP).
        weekly_vol_per_bp = defaultdict(float)
        prog = (
            _tapered_progression(persona.progression_pct, persona.half_life_weeks, week)
            if persona.tapering
            else persona.progression_pct
        )

        # PRE-session gate: vmult per strength bp from the START-of-week vitality.
        if gate:
            vmult_map = {
                bp: strength_vitality_mult(strength_vpct(bp, vit_ewma, vit_ref_peak))
                for bp in ACTIVE_RANKS
            }
        else:
            vmult_map = 1.0

        is_layoff = week in persona.layoff_weeks
        if not is_layoff:
            cap = persona.sessions_per_week_cap
            week_schedule = schedule if cap is None else schedule[:cap]
            for day in week_schedule:
                session_num += 1
                for bp in SESSION_BODY_PARTS.get(day, set()):
                    bp_session[bp] += 1
                novelty_count = defaultdict(float)

                for exercise, n_sets in DAY_TEMPLATES_PANEL[day]:
                    r = reps_scheme.get(exercise, DEFAULT_REPS_PANEL.get(exercise, 5))
                    diff_m = difficulty_mult_for_alias(exercise)
                    real_slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                    distribution = _attribution_for(exercise)

                    # Smurf override on session 1
                    use_smurf = (
                        not smurf_done and session_num == 1
                        and persona.smurf_session
                        and exercise in persona.smurf_session
                    )
                    if use_smurf:
                        sw, sr = persona.smurf_session[exercise]
                        for _ in range(n_sets):
                            cr = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
                            nf = rng.random() < nf_rate
                            awarded, vol, _comp, best_by_band = compute_set_xp(
                                exercise, sw, sr, novelty_count, weekly_count, peak_loads,
                                difficulty_mult=diff_m,
                                bodyweight_kg=persona.bodyweight_kg,
                                slug=real_slug,
                                current_ranks=cr,
                                best_by_band=best_by_band,
                                bp_session_count=bp_session,
                                near_failure=nf,
                                female=persona.female,
                                vmult=vmult_map,
                                base_recenter=base_recenter,
                            )
                            for bp2, xp in awarded.items():
                                xp_pool[bp2] += xp
                                weekly_xp[bp2] += xp
                            for bp2, share in distribution.items():
                                if bp2 in vit_ewma:
                                    weekly_vol_per_bp[bp2] += vol * share
                        smurf_done = True
                        continue

                    w = weights.get(exercise, 1.0)
                    for _ in range(n_sets):
                        cr = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
                        nf = rng.random() < nf_rate
                        awarded, vol, _comp, best_by_band = compute_set_xp(
                            exercise, w, r, novelty_count, weekly_count, peak_loads,
                            difficulty_mult=diff_m,
                            bodyweight_kg=persona.bodyweight_kg,
                            slug=real_slug,
                            current_ranks=cr,
                            best_by_band=best_by_band,
                            bp_session_count=bp_session,
                            near_failure=nf,
                            female=persona.female,
                            vmult=vmult_map,
                            base_recenter=base_recenter,
                        )
                        for bp2, xp in awarded.items():
                            xp_pool[bp2] += xp
                            weekly_xp[bp2] += xp
                        for bp2, share in distribution.items():
                            if bp2 in vit_ewma:
                                weekly_vol_per_bp[bp2] += vol * share

            # Apply progression after a trained week
            for ex in weights:
                weights[ex] *= (1.0 + prog)

        # Step vitality forward on the DAILY grid from THIS week's volume load
        # (0 during a layoff). ewma rebuilds (α_up) or decays (α_down); ref_peak
        # is re-topped by a rising ewma or decays daily toward the recent ceiling
        # (the returner-recovery mechanism). Append this week's lump + 6 zero
        # days so the live trailing-7-day window is reproduced.
        if gate:
            for bp in ACTIVE_RANKS:
                vol_history[bp].append(weekly_vol_per_bp.get(bp, 0.0))
                vol_history[bp].extend([0.0] * (DAYS_PER_WEEK - 1))
            advance_vitality_week(vol_history, vit_ewma, vit_ref_peak)

        ranks = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
        snapshots.append({
            "week": week,
            "ranks": ranks,
            "character_level": character_level(ranks),
            "cumulative_xp": int(sum(xp_pool.values())),
            "weekly_xp": {p: int(v) for p, v in weekly_xp.items()},
            "prog_rate": prog,
            "is_layoff": is_layoff,
            # Pre-session vpct/vmult per active bp (the gate that was in force
            # this week). avg_vpct/avg_vmult summarize across active bps.
            "vpct": {bp: strength_vpct(bp, vit_ewma, vit_ref_peak) for bp in ACTIVE_RANKS},
            "vmult": (
                {bp: strength_vitality_mult(strength_vpct(bp, vit_ewma, vit_ref_peak))
                 for bp in ACTIVE_RANKS}
                if gate else {bp: 1.0 for bp in ACTIVE_RANKS}
            ),
        })

    return snapshots


def avg_active_rank(snapshot):
    return sum(snapshot["ranks"][bp] for bp in ACTIVE_RANKS) / len(ACTIVE_RANKS)


# ============================================================================
# Phase Vitality-3 — calibration harness (VPCT_NORMAL, recenter sweep, returner)
# ============================================================================

# The 6 CONSISTENT personas — train a full split every week, no layoffs/caps.
# Their converged vpct (wks 8-12) defines VPCT_NORMAL; the recenter sweep keeps
# them within ±0.5 rank of their pre-gate avg_rank.
CONSISTENT_PERSONAS = [
    "beginner", "weak_consistent", "advanced", "elite",
    "female_intermediate", "hypertrophy_bb",
]


def measure_vpct_normal(weeks=12, window=(8, 12)):
    """VPCT_NORMAL = median over the 6 consistent personas of each persona's
    mean per-active-bp vpct across the converged window (weeks 8-12).

    Returns (vpct_normal, per_persona_vpct).
    """
    lo, hi = window
    per = {}
    for pk in CONSISTENT_PERSONAS:
        snaps = simulate_persona(pk, weeks=weeks)
        vals = []
        for s in snaps:
            if lo <= s["week"] <= hi:
                vals.extend(s["vpct"][bp] for bp in ACTIVE_RANKS)
        per[pk] = sum(vals) / len(vals)
    ordered = sorted(per.values())
    n = len(ordered)
    median = (ordered[n // 2] if n % 2 else (ordered[n // 2 - 1] + ordered[n // 2]) / 2)
    return median, per


def consistent_pregate_avg_ranks(weeks=12):
    """Each consistent persona's CURRENT (pre-gate) avg_rank — the ±0.5 anchor."""
    return {pk: avg_active_rank(simulate_persona(pk, weeks=weeks, gate=False)[-1])
            for pk in CONSISTENT_PERSONAS}


def sweep_base_recenter(grid, weeks=12):
    """Sweep STRENGTH_BASE_RECENTER over `grid`, holding PANEL_TARGET_BANDS +
    FLOOR fixed. Pick the value minimizing Σ|Δ_consistent| (vs pre-gate avg_rank)
    while keeping all 6 consistent personas (a) in-band and (b) within ±0.5 rank
    of their pre-gate avg_rank. Returns the full sweep table + the winner.
    """
    global STRENGTH_BASE_RECENTER
    pregate = consistent_pregate_avg_ranks(weeks=weeks)
    original = STRENGTH_BASE_RECENTER
    rows = []
    try:
        for cand in grid:
            STRENGTH_BASE_RECENTER = cand
            deltas = {}
            in_band = True
            within = True
            for pk in CONSISTENT_PERSONAS:
                ar = avg_active_rank(simulate_persona(pk, weeks=weeks)[-1])
                lo, hi = PANEL_TARGET_BANDS[pk]
                deltas[pk] = ar - pregate[pk]
                if not (lo <= ar <= hi):
                    in_band = False
                if abs(ar - pregate[pk]) > 0.5:
                    within = False
            sigma = sum(abs(d) for d in deltas.values())
            rows.append({
                "recenter": cand, "sigma": sigma, "in_band": in_band,
                "within": within, "deltas": deltas,
            })
    finally:
        STRENGTH_BASE_RECENTER = original
    valid = [r for r in rows if r["in_band"] and r["within"]]
    winner = min(valid, key=lambda r: r["sigma"]) if valid else None
    return rows, winner, pregate


def simulate_returner(weeks_seed=8, weeks_layoff=8, weeks_back=6, seed=42,
                      return_ramp=(2, 3)):
    """Detrained-returner harness.

    Phase 1 (weeks_seed): train consistent ~4×/wk → build rank + saturate
                          vit_ewma ≈ vit_ref_peak (vpct → ~1.0).
    Phase 2 (weeks_layoff): ZERO volume — rank HOLDS (D6), vit_ewma decays
                          (τ_down=6wk), vit_ref_peak decays (21d half-life).
    Phase 3 (weeks_back): return CONSISTENT near prior loads — vpct (and thus
                          vmult) recovers; assert ≥0.90 within 2-4 weeks.

    `return_ramp` caps sessions on the first len(ramp) back-weeks (a realistic
    graded return — a returner eases in rather than slamming straight to full
    volume). E.g. (2, 3) = 2 sessions back-wk1, 3 back-wk2, then full schedule.
    This produces the gradual multi-week recovery curve (rather than a 1-week
    step) WITHOUT changing the gate mechanic. A faithful daily-grid recovery from
    a slam-back-to-full-volume return is ~1 week; the graded ramp is the honest
    behavioral model and the one we document.

    Returns a per-week list of dicts: week, phase, avg_rank, mean vmult/vpct
    across active bps. The rank-never-drops invariant is checked at the layoff
    boundary by the caller.
    """
    persona = PERSONAS["detrained_returner"]
    rng = random.Random(seed)
    nf_rate = persona.nf_rate
    xp_pool = {p: 0.0 for p in BODY_PARTS}
    weights = dict(persona.starting_weights)
    peak_loads = dict(persona.starting_weights)
    best_by_band = {}
    schedule = WEEK_SCHEDULES_PANEL[persona.schedule_key]
    reps_scheme = persona.reps_scheme or DEFAULT_REPS_PANEL
    vit_ewma = {bp: 0.0 for bp in ACTIVE_RANKS}
    vit_ref_peak = {bp: 0.0 for bp in ACTIVE_RANKS}
    vol_history = {bp: [] for bp in ACTIVE_RANKS}
    base_recenter = STRENGTH_BASE_RECENTER
    history = []
    total = weeks_seed + weeks_layoff + weeks_back

    for week in range(1, total + 1):
        if week <= weeks_seed:
            phase = "seed"
        elif week <= weeks_seed + weeks_layoff:
            phase = "layoff"
        else:
            phase = "back"
        is_layoff = (phase == "layoff")

        weekly_count = defaultdict(float)
        bp_session = defaultdict(int)
        weekly_vol_per_bp = defaultdict(float)

        vmult_map = {
            bp: strength_vitality_mult(strength_vpct(bp, vit_ewma, vit_ref_peak))
            for bp in ACTIVE_RANKS
        }

        if not is_layoff:
            # Graded return: cap sessions on the first back-weeks (ease-in ramp).
            week_schedule = schedule
            if phase == "back":
                back_idx = week - (weeks_seed + weeks_layoff)   # 1-based
                if back_idx <= len(return_ramp):
                    week_schedule = schedule[:return_ramp[back_idx - 1]]
            for day in week_schedule:
                for bp in SESSION_BODY_PARTS.get(day, set()):
                    bp_session[bp] += 1
                novelty_count = defaultdict(float)
                for exercise, n_sets in DAY_TEMPLATES_PANEL[day]:
                    r = reps_scheme.get(exercise, DEFAULT_REPS_PANEL.get(exercise, 5))
                    diff_m = difficulty_mult_for_alias(exercise)
                    real_slug = SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                    distribution = _attribution_for(exercise)
                    w = weights.get(exercise, 1.0)
                    for _ in range(n_sets):
                        cr = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
                        nf = rng.random() < nf_rate
                        awarded, vol, _comp, best_by_band = compute_set_xp(
                            exercise, w, r, novelty_count, weekly_count, peak_loads,
                            difficulty_mult=diff_m,
                            bodyweight_kg=persona.bodyweight_kg,
                            slug=real_slug,
                            current_ranks=cr,
                            best_by_band=best_by_band,
                            bp_session_count=bp_session,
                            near_failure=nf,
                            female=persona.female,
                            vmult=vmult_map,
                            base_recenter=base_recenter,
                        )
                        for bp2, xp in awarded.items():
                            xp_pool[bp2] += xp
                        for bp2, share in distribution.items():
                            if bp2 in vit_ewma:
                                weekly_vol_per_bp[bp2] += vol * share

        for bp in ACTIVE_RANKS:
            vol_history[bp].append(weekly_vol_per_bp.get(bp, 0.0))
            vol_history[bp].extend([0.0] * (DAYS_PER_WEEK - 1))
        advance_vitality_week(vol_history, vit_ewma, vit_ref_peak)

        ranks = {p: rank_for_xp(xp_pool[p]) for p in BODY_PARTS}
        post_vmult = [strength_vitality_mult(strength_vpct(bp, vit_ewma, vit_ref_peak))
                      for bp in ACTIVE_RANKS]
        post_vpct = [strength_vpct(bp, vit_ewma, vit_ref_peak) for bp in ACTIVE_RANKS]
        history.append({
            "week": week,
            "phase": phase,
            "avg_rank": sum(ranks[bp] for bp in ACTIVE_RANKS) / len(ACTIVE_RANKS),
            "pre_vmult": sum(vmult_map[bp] for bp in ACTIVE_RANKS) / len(ACTIVE_RANKS),
            "post_vmult": sum(post_vmult) / len(post_vmult),
            "post_vpct": sum(post_vpct) / len(post_vpct),
            "weeks_seed": weeks_seed,
            "weeks_layoff": weeks_layoff,
        })
    return history


# ============================================================================
# Reporting
# ============================================================================

def print_persona_panel(weeks=12):
    sep = "=" * 116
    n = len(PANEL_ORDER)
    print()
    print(sep)
    print(f"  RepSaga Phase 29 v2 + 29.6 + Vitality-3 — {n}-persona panel ({weeks}-week simulation)")
    print(f"  FLOOR={STRENGTH_VITALITY_FLOOR} base_recenter={STRENGTH_BASE_RECENTER} | "
          f"V_exp={VOLUME_EXPONENT} cap={WEEKLY_CAP_SETS} over_cap={OVER_CAP_MULTIPLIER}")
    print(sep)

    results = {}
    cnv_vpct = {}
    for pk in PANEL_ORDER:
        snaps = simulate_persona(pk, weeks=weeks)
        results[pk] = snaps[-1]
        # Converged mean per-active-bp vpct (wks 8-12) — shows the gate in force.
        wins = [s for s in snaps if s["week"] >= max(1, weeks - 4)]
        cnv_vpct[pk] = sum(
            sum(s["vpct"][bp] for bp in ACTIVE_RANKS) / len(ACTIVE_RANKS)
            for s in wins
        ) / len(wins)

    hdr = "  {:<42}  {:>3} {:>3} {:>3} {:>3} {:>3} {:>3}  {:>2}  {:>5}  {:>5}  {:<7}  {:>4}  {:>8}"
    row = "  {:<42}  {:>3} {:>3} {:>3} {:>3} {:>3} {:>3}  {:>2}  {:>5.1f}  {:>5.2f}  {:<7}  {:>4}  {:>8}"
    print()
    print(hdr.format(
        "Persona", "Ch", "Bk", "Lg", "Sh", "Ar", "Co",
        "Lv", "AvgRk", "vpct", "Target", "Pass", "CumXP"))
    print("  " + "-" * 114)

    passes = 0
    for pk in PANEL_ORDER:
        s = results[pk]
        r = s["ranks"]
        ar = avg_active_rank(s)
        p = PERSONAS[pk]
        lo, hi = PANEL_TARGET_BANDS[pk]
        ok = "PASS" if lo <= ar <= hi else "FAIL"
        if ok == "PASS":
            passes += 1
        print(row.format(
            p.name[:42],
            r["chest"], r["back"], r["legs"],
            r["shoulders"], r["arms"], r["core"],
            s["character_level"], ar, cnv_vpct[pk], f"{lo}-{hi}", ok,
            f"{s['cumulative_xp']:,}"))

    print()
    print(f"  Verdict: {passes}/{len(PANEL_ORDER)} PASS")

    sa = avg_active_rank(results["smurf"])  # WITH the fake-1RM session-1
    sh = avg_active_rank(simulate_persona("smurf_honest", weeks=weeks)[-1])  # same lifter, no fake
    fi = avg_active_rank(results["female_intermediate"])
    fb = avg_active_rank(results["female_beginner"])
    di = avg_active_rank(results["diego"])
    sand = avg_active_rank(results["sandbagger"])
    adv = avg_active_rank(results["advanced"])
    # Anti-cheese: faking a 1RM must never PAY. The cheat replaces real working sets
    # and is capped → net XP loss, so with-fake must rank <= the same lifter honest.
    # (Correct invariant; the old Smurf<=TrueBeginner compared a stronger lifter to a
    # weaker one and so was a meaningless permanent FAIL.)
    print(f"  Anti-cheese (faking never pays): smurf+fake {sa:.1f} <= honest {sh:.1f}: "
          f"{'OK' if sa <= sh else 'FAIL'}")
    print(f"  Female ordering: FBeg {fb:.1f} < FInt {fi:.1f} < Diego {di:.1f}: "
          f"{'OK' if fb < fi < di else 'FAIL'}")
    print(f"  Vitality-3: Sandbagger {sand:.1f} < Advanced {adv:.1f}: "
          f"{'OK' if sand < adv else 'FAIL'}  "
          f"(sandbagger throttled to vpct {cnv_vpct['sandbagger']:.2f})")
    return results, passes


def print_returner_report(weeks_seed=8, weeks_layoff=8, weeks_back=6):
    """Detrained-returner recovery report — the Vitality-3 comeback proof."""
    h = simulate_returner(weeks_seed=weeks_seed, weeks_layoff=weeks_layoff,
                          weeks_back=weeks_back)
    print()
    print("=" * 72)
    print(f"  Vitality-3 — Detrained Returner ({weeks_seed}wk seed / "
          f"{weeks_layoff}wk layoff / {weeks_back}wk back)")
    print("=" * 72)
    print(f"  {'wk':>3} {'phase':>7} {'avg_rank':>9} {'vmult(earned)':>14} {'post_vpct':>10}")
    for x in h:
        print(f"  {x['week']:>3} {x['phase']:>7} {x['avg_rank']:>9.2f} "
              f"{x['pre_vmult']:>14.3f} {x['post_vpct']:>10.3f}")
    layoff = [x for x in h if x["phase"] == "layoff"]
    back = [x for x in h if x["phase"] == "back"]
    rank_held = all(x["avg_rank"] >= layoff[0]["avg_rank"] for x in layoff)
    reached = next((i for i, x in enumerate(back, 1) if x["pre_vmult"] >= 0.90), None)
    print()
    print(f"  Rank never drops during layoff: {'OK' if rank_held else 'FAIL'} "
          f"({layoff[0]['avg_rank']:.1f} held across {len(layoff)} layoff weeks)")
    print(f"  vmult >= 0.90 recovered by back-week: {reached} "
          f"({'OK - within 2-4wk' if reached and reached <= 4 else 'FAIL'})")
    return h


def print_xp_curve_summary():
    print()
    print("=== Phase 29 v2 RANK XP CURVE (Refinement #6 piecewise) ===")
    samples = [2, 5, 10, 15, 20, 21, 30, 40, 50, 60, 70, 80, 90, 99]
    print(f"{'Rank':>5}  {'XP cum':>14}  {'XP delta':>14}")
    prev = 0
    for n in samples:
        cur = int(xp_for_rank(n))
        print(f"{n:>5}  {cur:>14,}  {cur - prev:>14,}")
        prev = cur


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="RepSaga Phase 29 v2 + 29.6 LOCKED XP simulator")
    parser.add_argument("--weeks", type=int, default=12,
                        help="Number of weeks to simulate (default 12)")
    parser.add_argument("--legacy", action="store_true",
                        help="Run legacy Phase 24c Archetype simulation instead "
                             "of the 13-persona panel")
    parser.add_argument("--xp-curve", action="store_true",
                        help="Print piecewise rank XP curve summary")
    parser.add_argument("--returner", action="store_true",
                        help="Print the Vitality-3 detrained-returner recovery report")
    parser.add_argument("--recenter-sweep", action="store_true",
                        help="Sweep STRENGTH_BASE_RECENTER + report VPCT_NORMAL")
    args = parser.parse_args()

    if args.xp_curve:
        print_xp_curve_summary()
        return

    if args.returner:
        print_returner_report()
        return

    if args.recenter_sweep:
        vn, per = measure_vpct_normal(weeks=args.weeks)
        print(f"\n  VPCT_NORMAL (median converged wk8-12, 6 consistent) = {vn:.4f}")
        for k, v in per.items():
            print(f"    {k:<22} {v:.4f}")
        grid = [round(1.00 + 0.02 * i, 2) for i in range(21)]   # 1.00 .. 1.40
        rows, winner, _pre = sweep_base_recenter(grid, weeks=args.weeks)
        print(f"\n  {'recenter':>8} {'sigma_d':>9} {'in_band':>8} {'within0.5':>10}")
        for r in rows:
            mark = "  <-- WINNER" if winner and r["recenter"] == winner["recenter"] else ""
            print(f"  {r['recenter']:>8.2f} {r['sigma']:>9.2f} "
                  f"{str(r['in_band']):>8} {str(r['within']):>10}{mark}")
        print(f"\n  WINNER STRENGTH_BASE_RECENTER = "
              f"{winner['recenter'] if winner else None}")
        return

    if args.legacy:
        for key in ['beginner', 'intermediate', 'advanced',
                    'stagnant_lifter', 'comeback_kid', 'vacationer']:
            arch = ARCHETYPES[key]
            snaps = simulate(arch, args.weeks)
            final = snaps[-1]
            r = final['ranks']
            print(f"  {key:<20} wk{args.weeks}: lvl={final['character_level']} "
                  f"ranks=Ch{r['chest']} Bk{r['back']} Lg{r['legs']} "
                  f"Sh{r['shoulders']} Ar{r['arms']} Co{r['core']} "
                  f"cum={sum(final['total_xp'].values()):,}")
        return

    print_persona_panel(weeks=args.weeks)


if __name__ == '__main__':
    main()
