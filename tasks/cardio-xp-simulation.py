#!/usr/bin/env python3
"""Cardio XP / progression simulation — calibration source of truth (v1 DRAFT).

Mirror of `tasks/rpg-xp-simulation.py` (the strength formula) for the proposed
CARDIO stat. Cardio is dimensionally distinct from strength (rate × time, not
load), so it cannot reuse the weight×reps chain — but it REUSES two things for
consistency with the strength system:

  1. The SHARED piecewise rank curve (rank 5 ≈ 278 XP, 20 ≈ 3,440, 50 ≈ 14,448)
     so a cardio rank feels like a strength rank and feeds character level
     additively (denominator 4, N_active 6→7).
  2. The `tier_diff_mult` "capacity chases rank" mechanic (Pokemon Gen 5
     adaptation). For strength, the per-set tier comes from the LOAD LIFTED in
     that set (an impressive lift, not the lifter's standing capacity). The
     cardio analogue: the per-session tier comes from what the session
     DEMONSTRATES — `demonstrated_vo2 = MET×3.5 / sustainable_fraction(duration)`
     → sex/age percentile → tier [0,70] (ACSM/Cooper tables).

KEY DESIGN PROPERTY (the thesis honesty guarantee):
  Cardio rank credits DEMONSTRATED PERFORMANCE, not estimated capacity — exactly
  as strength credits the lift, not the lifter. Two derived signals, kept
  separate, make the physiology the sole judge:
    * intensity (for reward weighting + adaptation) is RELATIVE to current
      fitness: rel = MET×3.5 / standing_VO2max. The SAME walk is a stimulus for
      a deconditioned person (~55% of their low VO2max) and worthless for a
      runner (~25% of their high VO2max).
    * tier (for the tier_diff_mult burst) is what the session DEMONSTRATED.
  Consequences (validated on the panel):
    - A walk demonstrates ~walking-level fitness for ANYONE → low tier → low
      rank credit. Walking is "worth little" for the stat — for the deconditioned
      AND the fit (the reformed-runner-who-only-walks earns ~nothing).
    - BUT walking still raises a deconditioned person's underlying VO2max
      (physiology) — the base that lets them later jog and THEN demonstrate (and
      rank) more. You must increase intensity to keep ranking — the real
      training principle, enforced by the model.
    - A genuinely fit runner DEMONSTRATES it with hard efforts → high tier →
      ranks up fast (the cardio "Diego" — capacity honored once shown).
    - Huge easy volume converges to ~the demonstrated tier, never past it.
  This is the direct cardio analogue of the strength thesis veto: you can't fake
  cardio rank any more than you can fake a 1RM.

Science anchors (citations in docs/cardio-balance-baseline.md):
  - ACSM/Cooper Institute VO2max percentile norms (sex × age decade).
  - Bacon 2013 / HERITAGE / Montero-Lundby: novice +13-20% in 8-12 wk, trained
    ≤5%, saturating approach to a genetic ceiling (~90 mL/kg/min practical max).
  - Wenger & Bell 1986: intensity is the dominant lever; ~50% VO2max floor below
    which adaptation is minimal; 90-100% VO2max is the max-gain band.
  - WHO 2020: 500-1000 MET-min/week recommended; elite ~10× that.
  - Coyle detraining: ~-7% / 12 days, asymptotic (Vitality decay — modeled in
    the app's Vitality layer, not scored here).
  - STRENGTH→CARDIO cross-credit (one-directional): resistance training is a real
    but smaller, density-dependent CRF stimulus (circuit RT +6.3% VO2max,
    PMC8145598; RT-alone +1.9 mL/kg/min, Oxford afac143), and the interference
    effect is directional (Wilson 2012 JSCR: endurance impairs strength, strength
    does NOT impair aerobic gains). So a lifting session feeds THIS pipeline as a
    kind='abs' fixed-MET entry (`_lift`/`_metcon`), credited strength→cardio only,
    never the reverse. The demonstrated-VO2 gate keeps heavy lifting ~0 and
    metcons modest. See MODALITY_MULT comment + the powerlifter/crossfitter
    personas.

Run:  python tasks/cardio-xp-simulation.py --persona-panel
      python tasks/cardio-xp-simulation.py --curves
"""

import math
import sys
from dataclasses import dataclass, field

# ============================================================================
# SHARED constants (verbatim from the strength baseline — keep in lockstep)
# ============================================================================
XP_BASE = 60
XP_GROWTH_BAND1 = 1.10
RANK_CURVE_BREAKPOINT = 20
LINEAR_XP_PER_RANK = 367.0

TIER_DIFF_OFFSET = 10.0
TIER_DIFF_EXP = 2.5
TIER_DIFF_MAX = 8.0
TIER_DIFF_MIN = 0.25

VOLUME_EXPONENT = 0.60  # base_xp = met_minutes ^ this (mirrors volume_load^0.60)
# Calibrates the cardio "currency" (MET-min) onto the SHARED rank curve so a
# consistently-training athlete's rank converges to their VO2max-percentile tier
# in ~8-12 wk (the cardio analogue of strength's Diego reaching his tier). Tuned
# on the persona panel.
CARDIO_XP_SCALE = 3.5

# ============================================================================
# CARDIO-specific constants (v1 DRAFT — these are what the panel calibrates)
# ============================================================================
MET_REST = 3.5  # 1 MET = 3.5 mL O2 / kg / min (ACSM)

# Intensity multiplier vs fraction of VO2max (Wenger & Bell: <~50% ≈ maintenance,
# 90-100% = max-gain band). Piecewise-linear anchors (pct_vo2max → mult).
INTENSITY_ANCHORS = [
    (0.35, 0.05),  # very light — near-zero progression credit
    (0.50, 0.35),  # moderate floor
    (0.70, 0.75),  # tempo
    (0.85, 1.05),  # threshold
    (0.95, 1.35),  # VO2max intervals
    (1.05, 1.45),  # supramaximal
]

# Weekly intensity-weighted MET-min beyond which extra volume is heavily
# discounted (anti-grind; the cap is secondary — tier_diff_mult is the primary
# honesty gate). Anchored well above the WHO 500-1000 band so a committed
# trainer isn't capped, but a 20-session/wk grind doesn't stack linearly.
WEEKLY_CARDIO_CAP_METMIN = 2500.0
OVER_CAP_MULT = 0.30

# Modality normalization (whole-body / weight-bearing elicit higher VO2 at a
# given %effort; the MET model already captures most of it — this is a small
# "difficulty" analog). Reference = running 1.00.
#
# STRENGTH → CARDIO cross-contribution (resistance work earns cardio credit too):
#   Resistance training produces a REAL but smaller, intensity/density-dependent
#   cardiorespiratory adaptation (circuit/metabolic RT ~+6.3% VO2max, 45-study
#   meta-analysis PMC8145598; traditional RT alone ~+1.9 mL/kg/min in untrained,
#   ~0 in trained — Oxford afac143). The interference is DIRECTIONAL (Wilson 2012
#   JSCR, 21 studies/422 ES): endurance training impairs strength, but "aerobic
#   capacity gains are NOT compromised by concurrent strength training." So the
#   cross-credit flows ONE WAY — strength → cardio, never cardio → strength
#   (which is why running must never feed a strength/legs rank: §3 Option C).
#   A resistance session enters this SAME pipeline as a kind='abs' fixed-MET
#   session; the demonstrated-VO2 gate then does the honest sorting for free:
#     * traditional heavy/long-rest lifting averages ~3.5-4 MET (rests pull the
#       session mean down) → demonstrates ~walking-level VO2 → ~0 cardio rank.
#       You CANNOT farm cardio rank by lifting heavy. (Correct: heavy RT barely
#       moves VO2max.)
#     * high-density circuit/metcon averages ~7-8 MET, short rest → demonstrates
#       moderate VO2 → real but sub-runner cardio credit. (Correct: metcons do
#       build CRF.)
#   "strength"/"circuit" get a modality penalty vs running because RT is less
#   central-cardiovascular-specific at a matched %VO2max (aerobic training still
#   beats RT for VO2max at equal effort — the meta-analyses above).
# MET bands: ACSM 2024 Compendium — light/moderate weight training ~3.5 (02050),
# vigorous free-weight/multi ~5.0 (02054), powerlifting/bodybuilding vigorous
# ~6.0, circuit w/ minimal rest + some aerobic, vigorous ~8.0 (02040).
MODALITY_MULT = {
    "run": 1.00, "treadmill": 1.00, "row": 1.00, "swim": 1.00,
    "elliptical": 0.97, "bike": 0.95, "walk": 0.95, "hiit": 1.05,
    "strength": 0.80, "circuit": 0.90,
}

# Genetic ceiling for VO2max progression (practical human max ~90).
VO2_CEILING_CAP = 90.0
# Per-week VO2max gain coefficient (tuned so novice +~15% in 12 wk, trained ≤5%,
# saturating toward personal ceiling). dVO2 = K × stimulus_norm × headroom_frac.
VO2_GAIN_K = 0.040
# Normalizer: weekly intensity-weighted MET-min that counts as "1 unit" of
# stimulus for the progression curve (~a committed week).
VO2_STIMULUS_NORM = 1200.0

# Vitality — asymmetric EWMA on weekly volume. The *mechanic* (rank never drops;
# Vitality < 100% DECREASES XP GAINED until reconditioned to 100%) is shared with
# strength, but the *kinetics are DIFFERENT PHYSIOLOGY and intentionally not
# unified with strength's*:
#   - Strength Vitality = MUSCLE MEMORY (myonuclear/epigenetic retention; Bruusgaard
#     2010, Seaborne 2018) → slow decay (strength "remembers"): τ_down ≈ 6 wk.
#   - Cardio Vitality = CARDIORESPIRATORY DETRAINING (Coyle et al.: VO2max −7% in
#     ~12 days, ~−16% by 8 wk) → decays ~2× faster: τ_down ≈ 3 wk.
# Rebuild is moderately fast for both (no strong cardio analogue to the strength
# myonuclear-memory rebuild advantage), so τ_up ≈ 2 wk. NEVER copy these constants
# between stats — they encode different biology.
VITALITY_TAU_UP_WEEKS = 2.0
VITALITY_TAU_DOWN_WEEKS = 3.0   # cardio detrains ~2× faster than strength (Coyle)
# XP multiplier floor when fully lapsed. mult = FLOOR + (1-FLOOR)×vitality_pct, so
# a returning user always earns at least FLOOR× and ramps to full as they rebuild
# (avoids "earn ~0 for weeks" while still gating one-off post-layoff bursts —
# the un-farmable property). Tunable; FLOOR=0 = strictly linear (harshest).
VITALITY_XP_FLOOR = 0.40


# ============================================================================
# Shared rank curve (verbatim)
# ============================================================================
def _xp_geometric(n):
    if n <= 1:
        return 0.0
    return XP_BASE * (XP_GROWTH_BAND1 ** (n - 1) - 1) / (XP_GROWTH_BAND1 - 1)


_XP_AT_BREAKPOINT = _xp_geometric(RANK_CURVE_BREAKPOINT)


def xp_for_rank(n):
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


def update_vitality(week_volume, ewma, peak):
    """Asymmetric EWMA (rebuild fast, decay slow). Returns (new_ewma, new_peak).
    Peak is PERMANENT → rank never drops."""
    a_up = 1.0 - math.exp(-1.0 / VITALITY_TAU_UP_WEEKS)
    a_dn = 1.0 - math.exp(-1.0 / VITALITY_TAU_DOWN_WEEKS)
    alpha = a_up if week_volume >= ewma else a_dn
    new = alpha * week_volume + (1.0 - alpha) * ewma
    return new, max(peak, new)


def vitality_pct(ewma, peak):
    return 1.0 if peak <= 0 else max(0.0, min(1.0, ewma / peak))


def vitality_xp_mult(vpct):
    """Vitality < 100% scales DOWN the XP a session earns (never the rank). At
    100% conditioning → full XP; lapsed → reduced, ramping back as you rebuild."""
    return VITALITY_XP_FLOOR + (1.0 - VITALITY_XP_FLOOR) * vpct


def tier_diff_mult(current_rank, implied_tier):
    """Capacity-chases-rank burst — VERBATIM from the strength sim."""
    if implied_tier <= 0:
        return 1.0
    rank = max(1.0, current_rank)
    a = 2.0 * implied_tier + TIER_DIFF_OFFSET
    c = implied_tier + rank + TIER_DIFF_OFFSET
    if c <= 0:
        return TIER_DIFF_MAX
    raw = (a / c) ** TIER_DIFF_EXP
    return max(TIER_DIFF_MIN, min(TIER_DIFF_MAX, raw))


# ============================================================================
# VO2max → percentile → cardio tier  (ACSM / Cooper Institute normative tables)
# ============================================================================
# VO2max (mL/kg/min) at percentiles [5, 25, 50, 75, 90, 95] by sex × age decade.
_PCTS = [5, 25, 50, 75, 90, 95]
_VO2_NORMS = {
    ("M", 20): [29.0, 40.1, 48.0, 55.2, 61.8, 66.3],
    ("M", 30): [27.2, 35.9, 42.4, 49.2, 56.5, 59.8],
    ("M", 40): [24.2, 31.9, 37.8, 45.0, 52.1, 55.6],
    ("M", 50): [20.9, 27.1, 32.6, 39.7, 45.6, 50.7],
    ("M", 60): [17.4, 23.7, 28.2, 34.5, 40.3, 43.0],
    ("M", 70): [16.3, 20.4, 24.4, 30.4, 36.6, 39.7],
    ("F", 20): [21.7, 30.5, 37.6, 44.7, 51.3, 56.0],
    ("F", 30): [19.0, 25.3, 30.2, 36.1, 41.4, 45.8],
    ("F", 40): [17.0, 22.1, 26.7, 32.4, 38.4, 41.7],
    ("F", 50): [16.0, 19.9, 23.4, 27.6, 32.0, 35.9],
    ("F", 60): [13.4, 17.2, 20.0, 23.8, 27.0, 29.4],
    ("F", 70): [13.1, 15.6, 18.3, 20.8, 23.1, 24.1],
}
# percentile → cardio tier [0,70] (mirrors strength implied_tier scale).
_TIER_ANCHORS = [(0, 0), (5, 5), (25, 18), (50, 25), (75, 37), (90, 50),
                 (95, 60), (99, 68), (100, 70)]


def _interp(anchors, x):
    """Piecewise-linear interpolation over (x, y) anchors, clamped at the ends."""
    if x <= anchors[0][0]:
        return anchors[0][1]
    if x >= anchors[-1][0]:
        return anchors[-1][1]
    for (x0, y0), (x1, y1) in zip(anchors, anchors[1:]):
        if x0 <= x <= x1:
            t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return anchors[-1][1]


def _age_band(age):
    return max(20, min(70, (age // 10) * 10))


def vo2_to_percentile(vo2, age, female):
    sex = "F" if female else "M"
    norms = _VO2_NORMS[(sex, _age_band(age))]
    anchors = list(zip(norms, _PCTS))            # (vo2, pct) ascending in vo2
    anchors = [(0.0, 0.0)] + anchors + [(VO2_CEILING_CAP, 100.0)]
    return _interp(anchors, vo2)


def implied_cardio_tier(vo2, age, female):
    """Estimated VO2max → sex/age percentile → cardio tier [0,70]."""
    pct = vo2_to_percentile(vo2, age, female)
    return _interp(_TIER_ANCHORS, pct)


def intensity_mult(pct_vo2max):
    return _interp(INTENSITY_ANCHORS, pct_vo2max)


# Sustainable fraction of VO2max by effort DURATION (velocity-duration / critical-
# power curve): you can hold ~100% VO2max for ~6 min, ~80% for ~60 min, etc. Used
# to turn a session's sustained MET into a DEMONSTRATED VO2max — the cardio
# analogue of estimating 1RM from a set's weight×reps.
_SUSTAIN_ANCHORS = [(6, 1.00), (15, 0.93), (30, 0.88), (45, 0.84),
                    (60, 0.80), (90, 0.76), (120, 0.74), (180, 0.70)]


def sustainable_fraction(duration_min):
    return _interp(_SUSTAIN_ANCHORS, duration_min)


def demonstrated_vo2(abs_met, duration_min):
    """What VO2max this session *demonstrates*: the sustained VO2 (MET×3.5),
    back-projected to a max via the duration the user held it. A hard 30-min
    tempo reveals ~your true VO2max; a walk reveals ~15 — for ANYONE. This is
    what the rank credits (like strength credits the lift, not the lifter)."""
    return min(VO2_CEILING_CAP, (abs_met * MET_REST) / sustainable_fraction(duration_min))


# ============================================================================
# Phase 38c NET-NEW pure functions (app-derivation oracle — do NOT change
# compute_session_xp or the 14-persona panel). These pin Dart/SQL parity for
# the est-VO2max chain + cross-credit derivation + session resolution.
# See docs/WIP.md "Phase 38c DESIGN PROPOSAL" §A/§B + sub-decision D6.
# ============================================================================

# Cross-credit (strength -> cardio) work-density constants. These ONLY feed the
# MET-band derivation; they never touch strength XP and never touch the 14
# personas (which pass a literal MET via _lift/_metcon).
SET_WORK_SECONDS = 30      # a ~8-12 rep working set under tension
REST_DEFAULT = 90          # default inter-set rest when we.rest_seconds is NULL

# est-VO2max chain constants.
AGE_FALLBACK = 35          # median adult; used when profiles.date_of_birth is NULL
VO2_ROLLING_WINDOW_DAYS = 42   # best-of trailing window (6 wk ~= 2 x tau_down)

# Modalities for which logged distance is physiologically interpretable as
# pace -> VO2 via the ACSM *running* equation (A1 best-effort). Bike/row/swim
# need separate equations -> duration-only for estimation in v1.
DISTANCE_MODALITIES = {"run", "treadmill"}

# Per-modality ACSM table-average MET for a logged cardio session WITHOUT a
# pace-derived MET (duration-only, or a non-distance modality). The honest
# "activity type -> ACSM MET value" basis (cardio-stat-plan §2.5). Never
# user-declared; RPE is NOT used for MET. Moderate-effort table averages.
CARDIO_DEFAULT_MET = {
    "run": 9.8, "treadmill": 9.8, "bike": 7.0, "row": 8.5,
    "swim": 8.0, "elliptical": 7.0, "walk": 3.8, "hiit": 11.0,
}

# cardio exercise slug -> sim modality. The 5 default cardio slugs (00014):
# treadmill / rowing_machine / stationary_bike / jump_rope / elliptical.
CARDIO_SLUG_TO_MODALITY = {
    "treadmill": "treadmill",
    "rowing_machine": "row",
    "stationary_bike": "bike",
    "jump_rope": "hiit",
    "elliptical": "elliptical",
}


def best_effort_vo2_from_pace(distance_m, duration_s, modality):
    """A1 best-effort est-VO2max from a logged run/treadmill session.

    velocity -> ACSM horizontal-running VO2 (grade=0) -> back-project via the
    sim's sustainable_fraction. Returns None for non-distance modalities or
    missing inputs (the standing estimate is left unchanged that session).

    This is EXACTLY demonstrated_vo2(acsm_vo2/MET_REST, dur) — one code path,
    reused — but with abs_met derived from MEASURED pace, not an estimate.
    """
    if modality not in DISTANCE_MODALITIES:
        return None
    if distance_m is None or duration_s is None or distance_m <= 0 or duration_s <= 0:
        return None
    duration_min = duration_s / 60.0
    v_m_per_min = distance_m / duration_min
    acsm_vo2 = 0.2 * v_m_per_min + MET_REST              # ACSM running eq, grade=0
    return min(VO2_CEILING_CAP, acsm_vo2 / sustainable_fraction(duration_min))


def nonexercise_seed_vo2(age, female):
    """A3 cold-start seed: the p25 ("below-median untrained") anchor of the
    user's (sex, age_band) VO2 norm. Conservative prior — first real efforts
    can only raise it. age None -> AGE_FALLBACK; female None handled by caller
    (norms table keyed on sex)."""
    a = AGE_FALLBACK if age is None else age
    sex = "F" if female else "M"
    return _VO2_NORMS[(sex, _age_band(a))][1]            # index 1 == p25 anchor


def session_met_from_cardio_log(modality, distance_m, duration_s):
    """D6 session resolution: a logged cardio session -> absolute MET.

    run/treadmill WITH distance -> pace-derived MET (acsm_vo2 / MET_REST).
    otherwise -> per-modality ACSM table-average MET (CARDIO_DEFAULT_MET).
    Always kind='abs' for a logged session. Never user-declared."""
    if (modality in DISTANCE_MODALITIES
            and distance_m is not None and distance_m > 0
            and duration_s is not None and duration_s > 0):
        v_m_per_min = distance_m / (duration_s / 60.0)
        acsm_vo2 = 0.2 * v_m_per_min + MET_REST
        return acsm_vo2 / MET_REST
    return CARDIO_DEFAULT_MET.get(modality, MET_REST)


def est_met_from_density(completed_sets, session_seconds, avg_rest):
    """§B cross-credit: strength work-density -> ACSM RT MET band.

    Returns one of {3.5, 5.0, 6.0, 8.0}, evaluated top-down (first match
    wins), using the CORRECTED §B decision function (the 8.0 band gates on
    rest+cadence, NOT density, so a wall-clock-bound metcon isn't under-shot).
    All thresholds are on estimated/planned signals — never user-declared.

      sets_per_min = completed_sets / (session_seconds / 60)
    """
    if completed_sets <= 0 or session_seconds <= 0:
        return 3.5
    sets_per_min = completed_sets / (session_seconds / 60.0)
    if avg_rest <= 35 and sets_per_min >= 0.50:
        return 8.0      # dense circuit / metcon (ACSM 02040)
    if avg_rest <= 75 and sets_per_min >= 0.40:
        return 6.0      # vigorous PL/BB (~02054 high)
    if avg_rest <= 120:
        return 5.0      # vigorous free-weight (02054)
    return 3.5          # light/moderate, long rest (02050)


# ============================================================================
# Per-session cardio XP
# ============================================================================
def session_met_and_intensity(vo2max, kind, value):
    """Resolve a logged session to (absolute_MET, relative_intensity).

    The PHYSIOLOGY: adaptation tracks intensity RELATIVE to current capacity,
    `rel = absolute_MET × 3.5 / VO2max`. Two activity regimes:

      kind='abs' (walking, fixed machine settings): absolute MET is ~FIXED
        regardless of the user's fitness. rel = MET×3.5/VO2max FALLS as the user
        gets fitter → the same walk self-limits (worthless once fit). This is
        why walking builds a beginner but does nothing for a runner.

      kind='rel' (self-paced run/bike/swim at a chosen effort): the user picks
        the relative effort ('easy/tempo/hard'); a FITTER athlete simply runs
        FASTER, so absolute MET = effort × VO2max / 3.5 scales up with fitness
        while the relative (adaptation) signal stays constant.
    """
    if kind == "abs":
        abs_met = value
        rel = min(1.20, (abs_met * MET_REST) / vo2max)       # VO2_session/VO2max
    else:  # 'rel'
        rel = value
        abs_met = (rel * vo2max) / MET_REST
    return abs_met, rel


def compute_session_xp(vo2max, age, female, modality, duration_min,
                       kind, value, current_rank, week_cap_state):
    """Returns (xp, met_minutes, rel_intensity). Mutates week_cap_state['used'].

    Intensity is DERIVED from physiology (rel = MET×3.5/VO2max), so the science
    judges every session — a stroll scores ~0 for the fit, a brisk walk scores
    modestly for the deconditioned, and walking self-tapers as fitness rises.
    """
    abs_met, rel = session_met_and_intensity(vo2max, kind, value)
    met_min = abs_met * duration_min
    imult = intensity_mult(rel)
    eff_met_min = met_min * imult                     # intensity-weighted volume

    # Weekly diminishing returns (split the portion over the cap at OVER_CAP).
    used = week_cap_state["used"]
    remaining = max(0.0, WEEKLY_CARDIO_CAP_METMIN - used)
    under = min(eff_met_min, remaining)
    over = eff_met_min - under
    capped_met_min = under + over * OVER_CAP_MULT
    week_cap_state["used"] = used + eff_met_min

    base_xp = capped_met_min ** VOLUME_EXPONENT
    # Tier = what THIS session demonstrated (pace × duration), not standing
    # capacity. A walk demonstrates ~low VO2 for anyone → low tier → no burst.
    dvo2 = demonstrated_vo2(abs_met, duration_min)
    tier = implied_cardio_tier(dvo2, age, female)
    tdm = tier_diff_mult(current_rank, tier)
    mod = MODALITY_MULT.get(modality, 1.00)
    xp = base_xp * tdm * mod * CARDIO_XP_SCALE
    return xp, met_min, rel


# ============================================================================
# Persona model + 12-week simulation
# ============================================================================
@dataclass
class CardioPersona:
    name: str
    female: bool
    age: int
    bodyweight_kg: float
    vo2_start: float                 # baseline estimated VO2max
    vo2_ceiling: float               # personal genetic ceiling
    # weekly schedule: list of (modality, duration_min, kind, value)
    sessions: list = field(default_factory=list)
    target_band: tuple = (0, 99)     # acceptance band for wk12 rank
    layoff_weeks: tuple = ()         # weeks with NO training (vitality decays)


def simulate_cardio(persona: CardioPersona, weeks=12):
    total_xp = 0.0
    vo2 = persona.vo2_start
    vit_ewma = 0.0
    vit_peak = 0.0
    history = []
    for wk in range(1, weeks + 1):
        week_cap = {"used": 0.0}
        week_xp = 0.0
        week_eff_metmin = 0.0
        rank = rank_for_xp(total_xp)
        # Vitality gate (computed from conditioning at the START of the week): a
        # lapsed user earns reduced XP until they rebuild to 100%. Rank is NEVER
        # touched — only the XP a new session earns.
        vpct_start = vitality_pct(vit_ewma, vit_peak)
        vmult = vitality_xp_mult(vpct_start)
        sessions = [] if wk in persona.layoff_weeks else persona.sessions
        for (modality, dur, kind, value) in sessions:
            xp, met_min, rel = compute_session_xp(
                vo2, persona.age, persona.female, modality, dur, kind, value,
                rank, week_cap)
            xp *= vmult                                   # ← Vitality scales XP, not rank
            week_xp += xp
            week_eff_metmin += met_min * intensity_mult(rel)
            rank = rank_for_xp(total_xp + week_xp)         # rank ticks up as XP accrues
        total_xp += week_xp
        # VO2max progression: saturating approach to the genetic ceiling, driven
        # by the week's INTENSITY-WEIGHTED stimulus. Sub-threshold work (a stroll,
        # or any fixed-MET activity once the user outgrows it) contributes ~0 — so
        # low-intensity training SELF-PLATEAUS far below the genetic ceiling.
        stim = week_eff_metmin / VO2_STIMULUS_NORM
        vo2 = min(persona.vo2_ceiling,
                  vo2 + VO2_GAIN_K * stim * (persona.vo2_ceiling - vo2))
        # Update Vitality from this week's training volume (intensity-weighted
        # MET-min). Peak is permanent.
        vit_ewma, vit_peak = update_vitality(week_eff_metmin, vit_ewma, vit_peak)
        history.append((wk, round(vo2, 1),
                        round(implied_cardio_tier(vo2, persona.age, persona.female), 1),
                        rank_for_xp(total_xp), round(total_xp, 0),
                        round(vpct_start, 2), round(vmult, 2)))
    return history


# ============================================================================
# Persona panel (cardio calibration ground truth — v1 DRAFT bands)
# ============================================================================
# Self-paced endurance: a chosen RELATIVE effort (abs MET scales with fitness —
# a fitter athlete runs faster at the same "easy").
def _easy(mod, dur):      return (mod, dur, "rel", 0.62)
def _tempo(mod, dur):     return (mod, dur, "rel", 0.80)
def _thr(mod, dur):       return (mod, dur, "rel", 0.88)
def _intervals(mod, dur): return (mod, dur, "rel", 0.95)
# Fixed-MET activities: absolute intensity is ~constant regardless of fitness, so
# RELATIVE intensity (and thus reward) falls as the user gets fitter.
def _walk(dur):   return ("walk", dur, "abs", 3.8)   # brisk walk ≈ 3.8 MET
def _stroll(dur): return ("walk", dur, "abs", 3.0)   # leisurely walk ≈ 3.0 MET
# Resistance sessions feed the SAME cardio pipeline as a fixed-MET activity. The
# MET is the SESSION AVERAGE (rests included), which is what the app estimates
# from work density (rest length / rep range / set volume), never user-declared.
def _lift(dur, met=3.8):   return ("strength", dur, "abs", met)   # traditional, long rest
def _metcon(dur, met=8.0): return ("circuit", dur, "abs", met)    # high-density circuit

PERSONAS = {
    # Sedentary → couch-to-5k. Starts with WALK+JOG; the jogs (above threshold)
    # drive progression while the early walks contribute modestly. Shows the
    # real training principle: you must add intensity to keep adapting.
    "couch_to_5k": CardioPersona(
        name="Couch-to-5K Beginner (M, 30, 85kg)", female=False, age=30,
        bodyweight_kg=85, vo2_start=30.0, vo2_ceiling=50.0,
        sessions=[_walk(30), _easy("run", 22), _tempo("run", 18)],
        target_band=(10, 22)),
    "rec_jogger": CardioPersona(
        name="Recreational Jogger (M, 35, 78kg)", female=False, age=35,
        bodyweight_kg=78, vo2_start=42.0, vo2_ceiling=54.0,
        sessions=[_easy("run", 35), _tempo("run", 30), _easy("run", 40)],
        target_band=(15, 30)),
    "committed_runner": CardioPersona(
        name="Committed Runner (M, 32, 72kg)", female=False, age=32,
        bodyweight_kg=72, vo2_start=52.0, vo2_ceiling=64.0,
        sessions=[_easy("run", 45), _intervals("run", 35), _easy("run", 50),
                  _thr("run", 40), _easy("run", 60)],
        target_band=(38, 52)),
    "hiit": CardioPersona(
        name="HIIT Enthusiast (F, 28, 62kg)", female=True, age=28,
        bodyweight_kg=62, vo2_start=38.0, vo2_ceiling=52.0,
        sessions=[_intervals("hiit", 22), _intervals("hiit", 25),
                  _tempo("bike", 30), _intervals("hiit", 20)],
        target_band=(24, 38)),
    "cyclist": CardioPersona(
        name="Committed Cyclist (M, 40, 80kg)", female=False, age=40,
        bodyweight_kg=80, vo2_start=46.0, vo2_ceiling=58.0,
        sessions=[_easy("bike", 60), _thr("bike", 45), _easy("bike", 90),
                  _intervals("bike", 40)],
        target_band=(30, 46)),
    "female_rec": CardioPersona(
        name="Female Recreational Runner (F, 30, 60kg)", female=True, age=30,
        bodyweight_kg=60, vo2_start=36.0, vo2_ceiling=48.0,
        sessions=[_easy("run", 35), _tempo("run", 28), _easy("run", 35)],
        target_band=(15, 32)),
    "older_runner": CardioPersona(
        name="Older Runner (M, 55, 82kg)", female=False, age=55,
        bodyweight_kg=82, vo2_start=38.0, vo2_ceiling=46.0,
        sessions=[_easy("run", 35), _tempo("run", 30), _easy("run", 40)],
        target_band=(22, 40)),
    # THESIS GATE — un-farmable. 6x/wk brisk WALKS (fixed ~3.8 MET) but NORMAL
    # genetic ceiling (46). The walk is ~51% VO2max at start (modest stimulus →
    # small early gain) and self-tapers below threshold as VO2 creeps up → it
    # PLATEAUS LOW from physiology, not an artificial cap. All that volume can
    # never reach elite.
    "walker": CardioPersona(
        name="Daily Walker (F, 45, 75kg)", female=True, age=45,
        bodyweight_kg=75, vo2_start=26.0, vo2_ceiling=46.0,
        sessions=[_walk(45), _walk(45), _walk(60), _walk(45), _walk(60), _walk(45)],
        target_band=(8, 22)),
    # THESIS GATE — worthless once fit. A VO2 54 ex-runner who now ONLY walks:
    # the walk is ~25% VO2max → below threshold → ~zero XP and zero VO2 gain.
    # Demonstrates that the SAME activity is judged by physiology, not its label.
    "reformed_walker": CardioPersona(
        name="Reformed Runner Now Only Walks (M, 40, 75kg, VO2 54)",
        female=False, age=40, bodyweight_kg=75, vo2_start=54.0, vo2_ceiling=58.0,
        sessions=[_walk(45), _walk(60), _walk(45), _walk(50)],
        target_band=(1, 10)),
    # THESIS GATE — capacity honored (cardio "Diego"). VO2 64, just logging.
    "fit_newcomer": CardioPersona(
        name="Fit Newcomer (M, 27, 70kg, VO2 64)", female=False, age=27,
        bodyweight_kg=70, vo2_start=64.0, vo2_ceiling=68.0,
        sessions=[_easy("run", 45), _intervals("run", 35), _thr("run", 40),
                  _easy("run", 55)],
        target_band=(40, 60)),
    "elite": CardioPersona(
        name="Elite Endurance (M, 26, 65kg, VO2 72)", female=False, age=26,
        bodyweight_kg=65, vo2_start=72.0, vo2_ceiling=80.0,
        sessions=[_easy("run", 70), _intervals("run", 45), _easy("run", 90),
                  _thr("run", 50), _easy("run", 75), _intervals("run", 40)],
        target_band=(56, 72)),
    # Intensity-honest: huge EASY volume converges to ~the VO2 tier, not past it.
    "easy_marathoner": CardioPersona(
        name="Easy-Miles Marathoner (M, 38, 70kg)", female=False, age=38,
        bodyweight_kg=70, vo2_start=50.0, vo2_ceiling=60.0,
        sessions=[_easy("run", 60), _easy("run", 75), _easy("run", 90),
                  _tempo("run", 40), _easy("run", 120)],
        target_band=(34, 50)),
    # STRENGTH→CARDIO GATE — un-farmable from lifting. Pure powerlifter, 4x/wk
    # heavy long-rest sessions (~3.8 MET session avg, 60 min). Genuinely strong,
    # mediocre CRF. The session demonstrates ~walking-level VO2 → tier ~3 → ~zero
    # cardio rank, AND barely raises VO2max (heavy RT ≈ 0 aerobic adaptation —
    # Oxford afac143). Validates: you CANNOT lift your way to a cardio rank.
    "powerlifter": CardioPersona(
        name="Pure Powerlifter (M, 35, 100kg, heavy/long-rest)", female=False,
        age=35, bodyweight_kg=100, vo2_start=36.0, vo2_ceiling=42.0,
        sessions=[_lift(60), _lift(65), _lift(60), _lift(70)],
        target_band=(1, 10)),
    # STRENGTH→CARDIO GATE — metcon earns REAL but sub-runner cardio credit. 5x/wk
    # high-density circuits (~8 MET, 25-30 min, short rest). The session
    # demonstrates moderate VO2 → modest tier, and the metcons genuinely build CRF
    # (circuit RT ~+6.3% VO2max — PMC8145598). Lands mid-pack: above the
    # powerlifter (real conditioning), below a dedicated runner of equal VO2
    # (RT is less central-cardio-specific). Validates the complete-athlete credit.
    "crossfitter": CardioPersona(
        name="CrossFit / Metcon Athlete (M, 29, 82kg)", female=False, age=29,
        bodyweight_kg=82, vo2_start=44.0, vo2_ceiling=54.0,
        sessions=[_metcon(28), _metcon(25), _metcon(30), _metcon(25),
                  _metcon(28)],
        target_band=(12, 30)),
}


def print_persona_panel(weeks=12):
    print(f"\n=== CARDIO persona panel ({weeks} wk) — v1 DRAFT ===\n")
    header = f"{'Persona':<42} {'wk12 VO2':>8} {'tier':>5} {'rank':>5} {'band':>9} {'verdict':>8}"
    print(header)
    print("-" * len(header))
    npass = 0
    for key, p in PERSONAS.items():
        hist = simulate_cardio(p, weeks)
        wk12 = hist[-1]
        _, vo2, tier, rank, xp, vit, vmult = wk12
        lo, hi = p.target_band
        ok = lo <= rank <= hi
        npass += ok
        print(f"{p.name:<42} {vo2:>8.1f} {tier:>5.1f} {rank:>5} "
              f"{f'{lo}-{hi}':>9} {'PASS' if ok else 'FAIL':>8}")
    print("-" * len(header))
    print(f"\npersona_panel: {npass}/{len(PERSONAS)} PASS\n")
    return npass == len(PERSONAS)


def print_curves():
    print("\n=== shared rank curve (cumulative XP) ===")
    for r in (1, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70):
        print(f"  rank {r:>3}: {xp_for_rank(r):>10.0f} XP")
    print("\n=== VO2max → cardio tier (M, age 30) ===")
    for v in (28, 34, 40, 46, 52, 58, 64, 70):
        print(f"  VO2 {v}: pct {vo2_to_percentile(v,30,False):>5.1f} "
              f"→ tier {implied_cardio_tier(v,30,False):>5.1f}")
    print("\n=== intensity_mult vs %VO2max ===")
    for p in (0.40, 0.50, 0.62, 0.70, 0.80, 0.88, 0.95):
        print(f"  {int(p*100):>3}% → ×{intensity_mult(p):.2f}")
    print("\n=== tier_diff_mult(rank, tier=40) sample ===")
    for r in (1, 10, 20, 30, 40, 50):
        print(f"  rank {r:>3} vs tier 40 → ×{tier_diff_mult(r,40):.2f}")


def print_trajectory(key, weeks=12):
    p = PERSONAS[key]
    print(f"\n=== trajectory: {p.name} ===")
    print(f"{'wk':>3} {'VO2':>6} {'tier':>5} {'rank':>5} {'cumXP':>8} {'vit%':>6} {'xpMult':>7}")
    for (wk, vo2, tier, rank, xp, vit, vm) in simulate_cardio(p, weeks):
        print(f"{wk:>3} {vo2:>6.1f} {tier:>5.1f} {rank:>5} {xp:>8.0f} "
              f"{int(vit*100):>5}% {vm:>7.2f}")


# Comeback scenario (standalone — NOT in the strict steady-state panel) to
# exercise the Vitality XP-gate: builds for 4 wk, 6-wk full layoff, then returns.
_COMEBACK = CardioPersona(
    name="Comeback Runner (M, 33, 74kg) — 6-wk layoff then return",
    female=False, age=33, bodyweight_kg=74, vo2_start=50.0, vo2_ceiling=58.0,
    sessions=[_easy("run", 45), _tempo("run", 35), _intervals("run", 30),
              _easy("run", 50)],
    layoff_weeks=(5, 6, 7, 8, 9, 10))


def print_vitality_demo(weeks=18):
    print("\n=== Vitality XP-gate demo (rank NEVER drops; XP scales with conditioning) ===")
    print(f"{'wk':>3} {'phase':<10} {'rank':>5} {'vit%':>6} {'xpMult':>7} {'cumXP':>8}")
    for (wk, vo2, tier, rank, xp, vit, vm) in simulate_cardio(_COMEBACK, weeks):
        phase = "LAYOFF" if wk in _COMEBACK.layoff_weeks else (
            "build" if wk <= 4 else "return")
        print(f"{wk:>3} {phase:<10} {rank:>5} {int(vit*100):>5}% {vm:>7.2f} {xp:>8.0f}")
    print("  ↑ rank holds through the layoff (saga inviolate); on return, xpMult")
    print("    starts low (lapsed conditioning) and ramps back to 1.00 as Vitality")
    print("    rebuilds — so a one-off post-layoff burst can't bank full rank.")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    args = sys.argv[1:]
    if "--curves" in args:
        print_curves()
    elif "--vitality" in args:
        print_vitality_demo()
    elif "--traj" in args:
        i = args.index("--traj")
        print_trajectory(args[i + 1])
    else:
        print_curves()
        print_persona_panel()
        print_vitality_demo()


if __name__ == "__main__":
    main()
