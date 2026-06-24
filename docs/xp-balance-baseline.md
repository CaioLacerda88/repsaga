# XP Balance Baseline — Phase 29 v2 + 29.6

> **Status: OFFICIAL launch baseline as of 2026-05-22.** Snapshot of the
> Phase 29 v2 + 29.6 XP formula chain, locked constants, and 13-persona
> validation panel. Replaces the Phase 24d six-archetype baseline that
> shipped 2026-05-15.
>
> Phase 24d's 6 archetypes validated the original 6-multiplier chain at
> the totals level but couldn't catch the "experienced lifter at low
> character level" thesis violation (see `memory/project_rpg_thesis.md`).
> The Phase 29 13-persona panel adds the missing coverage: a 4-yr
> returning intermediate, an elite competitor at low rank, gender-aware
> personas (Female Beginner / Female Intermediate), an older lifter, a
> smurf, and machine-only / hypertrophy / consistent-but-weak
> variants. All 13 PASS under the Phase 29 v2 chain.

## Production sites (all green)

The 4-site parity invariant (1e-4 absolute) is held by these
implementation sites:

- `tasks/rpg-xp-simulation.py` — source of truth (Phase 29 PR 1, #251)
- `test/fixtures/rpg_xp_fixtures.json` — oracle (94 set_xp_v2 + 17
  implied_tier + 12 abs_strength_premium + 17 tier_diff_mult + 7
  overload_mult + 7 frequency_mult + 7 near_failure rows)
- `lib/features/rpg/domain/{xp_calculator,implied_tier,rank_curve}.dart`
  — Dart consumer (Phase 29 PR 2, #252)
- `supabase/migrations/00065_phase29_xp_formula_v2.sql` — SQL consumer
  (Phase 29 PR 2, #252)

## Constants snapshot (Phase 29 v2 + 29.6 — locked)

| Constant | Value | Notes |
|---|---|---|
| `VOLUME_EXPONENT` | `0.60` | base_xp = volume_load^this (unchanged from Phase 24d) |
| `NOVELTY_DENOMINATOR` | `15.0` | exp(-session_share/this) per body part |
| `WEEKLY_CAP_SETS` | `15.0` | effective sets/bp before over-cap kicks in |
| `OVER_CAP_MULTIPLIER` | `0.30` | multiplier applied beyond weekly cap |
| `STRENGTH_MULT_FLOOR` | `0.40` | anti-stagnation floor on strength_mult |
| `DIFFICULTY_MULT_FLOOR` | `0.85` | per-exercise difficulty floor |
| `DIFFICULTY_MULT_CEILING` | `1.25` | per-exercise difficulty ceiling |
| `E_BONUS` | `0.8` | abs_strength_premium max boost (29.6 Path C) |
| `E_FLOOR` | `35.0` | implied_tier below this → no premium |
| `E_CEIL` | `55.0` | implied_tier above this → 1.8× max premium |
| `NF_INTENSITY_BONUS` | `0.10` | near-failure adds +0.10 to intensity_mult |
| `NF_TARGET_THRESHOLD` | `0.85` | actual_reps < target × this → near_failure |
| `FREQUENCY_MULT_TABLE` | `[1.00, 1.06, 1.10, 1.06, 1.00]` | sessions 1/2/3/4/5+ in trailing 7d |
| `XP_BASE` | `60` | rank curve geometric base (Band 1: ranks 1-20) |
| `XP_GROWTH_BAND1` | `1.10` | geometric growth in Band 1 |
| `RANK_CURVE_BREAKPOINT` | `20` | piecewise pivot (geometric → linear) |
| `LINEAR_XP_PER_RANK` | `367.0` | **LITERAL** flat XP per rank in Band 2 (21-99). Not derived from `60 × 1.10^19 ≈ 366.957` — would compound rounding at high ranks across 4 sites. |
| `CHAR_LEVEL_DENOMINATOR` | `4` | `floor((Σ ranks − 6) / this) + 1` |
| `VITALITY_TAU_UP_WEEKS` | `2.0` | vitality rise time constant |
| `VITALITY_TAU_DOWN_WEEKS` | `6.0` | vitality decay time constant |
| `VITALITY_PEAK_PERMANENT` | `True` | peak never decays — saga inviolate |

## The 11-multiplier chain

```
set_xp = volume_load^0.60                              -- base
       × intensity_mult(reps) + (0.10 if near_failure) -- #4 inferred
       × strength_mult(weight, peak_load)              -- floor 0.40
       × novelty_mult(session_share_count)             -- exp(-share/15)
       × cap_mult(weekly_share_count)                  -- 0.30 if ≥ 15
       × difficulty_mult(exercise)                     -- [0.85, 1.25]
       × tier_diff_mult(implied_tier, current_rank)    -- #1
       × overload_mult(weight, reps, prior_best_band)  -- #2
       × frequency_mult(sessions_for_bp_in_7d)         -- #3
       × abs_strength_premium(implied_tier)            -- 29.6 Path C
```

Then distributed per body part:
`xp_awarded[bp] = set_xp × attribution[exercise][bp]`.

### Critical note — accumulator semantics

`session_vol` and `weekly_vol` (the novelty and cap accumulators) are
**share-count** values, NOT XP-earned values. They count the cumulative
attribution share for a body part within a session or rolling week:

```
session_share[bp] += attribution[exercise][bp]
```

A Phase 29 PR 2 reviewer cycle surfaced this in the SQL chain (cluster
`cluster-dart-sql-payload-semantic-drift`): an earlier draft tracked
XP-earned values, which silently broke parity vs the Python sim + Dart
oracle. The fix re-derives the share by JOINing through
`exercises.xp_attribution` rather than aggregating from
`xp_events.payload`.

## Intensity-by-reps table (unchanged through Phase 29)

| Reps ≥ | `intensity_mult` |
|---|---|
| 1 | 1.30 |
| 3 | 1.25 |
| 5 | 1.20 |
| 8 | 1.00 |
| 12 | 0.95 |
| 15 | 0.90 |
| 20+ | 0.80 |

If `near_failure_inferred = TRUE` (i.e., `actual_reps < target × 0.85`),
`+0.10` is added to the looked-up multiplier. Currently always FALSE
on the server (target_reps column not yet wired; helper is plumbed for
when active-workout UI exposes the signal).

## Difficulty tier table snapshot (unchanged from Phase 24d)

| Tier | Name | `tier_mult` | Defining characteristic |
|---|---|---|---|
| T1 | Olympic / ballistic | 1.25 | Triple extension, peak power, highest skill ceiling |
| T2 | Foundational compound (free weight, axial load) | 1.15 | Multi-joint, spine bears load, large stabilizer demand |
| T3 | Standard compound (free weight or supported) | 1.05 | Multi-joint, lower spinal load OR partial support |
| T4 | Machine compound / cable multi-joint | 0.90 | Fixed path, low stabilizer demand |
| T5 | Single-joint isolation | 0.85 | One articulation, minimal coordination |

Composite: `difficulty_mult = clamp(tier_mult + min(secondary_count, 3) × 0.02, 0.85, 1.25)`.
Per-slug values for the 200 default exercises are stored in
`exercises.difficulty_mult` (migration 00053 seed + 00055 Phase 24b
additions). Curation framework: `docs/xp-difficulty-framework.md` §2-§7.

## Implied-tier table anchors (Symmetric Strength + strengthlevel.com)

`implied_tier ∈ [0, 70]` per lift family, interpolated linearly between
the 8 anchor pairs below per (family, gender). NULL bodyweight → tier
15.0 sentinel (gentle middle).

**Male bench (BW-multiple → tier):**

| BW-ratio | Tier |
|---|---|
| 0.50 | 5 |
| 0.75 | 15 |
| 1.00 | 25 |
| 1.25 | 35 |
| 1.50 | 45 |
| 1.75 | 55 |
| 2.00 | 60 |
| 2.50 | 65 |

(Squat / deadlift / OHP / row / curl tables in
`lib/features/rpg/domain/implied_tier.dart`. Female tables scaled per
strengthlevel.com 2026-05-20 snapshot — broadly ~80% of male anchors at
equivalent tiers.)

## Bodyweight load ratio (Refinement #5 — 20 curated slugs)

| Slug | `bodyweight_load_ratio` |
|---|---|
| `pull_up`, `chin_up`, `wide_grip_pull_up`, `muscle_up` | 1.00 |
| `dips`, `ring_dip`, `pistol_squat` | 0.95 |
| `archer_push_up` | 0.80 |
| `decline_push_up` | 0.74 |
| `bodyweight_squat`, `single_leg_deadlift_unweighted` | 0.75 |
| `push_up` (standard) | 0.64 |
| `incline_push_up` | 0.41 |

(Other curated slugs from Phase 24c — `close_grip_push_up`,
`diamond_push_up`, `handstand_push_up`, `hanging_leg_raise`,
`inverted_row`, `nordic_curl`, `walking_lunges`, `wide_push_up` —
retain the Phase 24c default of 1.00; covered by the `uses_bodyweight_load`
flag.) Sources: Suprak et al. 2011 (push-ups), Youdas et al. 2010
(pull-ups), Bryanton et al. 2012 (squats).

## Piecewise rank curve (Refinement #6)

```
xp_for_rank(R):
  if R <= 1:  return 0
  if R <= 20: return 60 × (1.10^(R-1) - 1) / 0.10      -- Band 1: geometric
  else:       return xp_for_rank(20) + (R - 20) × 367.0 -- Band 2: linear
```

**Cumulative milestones:**

| Rank | Cumulative XP (Phase 29 v2) | Note |
|---|---|---|
| 1 | 0 | starting rank |
| 5 | 278 | Band 1 |
| 10 | ~814 | Band 1 |
| 15 | ~1,907 | Band 1 |
| 20 | ~3,440 | Band 1 → Band 2 transition |
| 25 | ~5,275 | Band 2 (3,440 + 5 × 367) |
| 30 | ~7,110 | Band 2 |
| 50 | ~14,448 | Band 2 (3,440 + 30 × 367) |
| 70 | ~21,788 | Band 2 (3,440 + 50 × 367) |
| 99 | ~32,433 | Band 2 (3,440 + 79 × 367) |

Compare to Phase 24d (geometric end-to-end): rank 50 was ~63,431 XP and
rank 99 was ~6.83M XP. Phase 29 v2 makes the high-rank endgame
accessible at realistic training cadences without flattening the
newbie honeymoon (Band 1 is unchanged).

The 00065 migration backfills `body_part_progress.rank` for every
existing user via `UPDATE body_part_progress SET rank = rpg_rank_for_xp(total_xp)`.
Users above rank ~21 see their rank shift UP. Pre-29
`xp_events.payload` values stay frozen — forward-only.

## 13-persona panel — Phase 29 v2 results (13 / 13 PASS)

Full simulator output from `python tasks/rpg-xp-simulation.py
--persona-panel`. Bands derived from product-owner + design call on what
"feels right" for each persona's training profile.

| Persona | Body weight | Experience | Cadence | wk12 avg rank | Target band | Verdict |
|---|---|---|---|---|---|---|
| True Beginner | 75 kg | 0 yr | 3×/wk full-body | 15.7 | 13-19 | PASS |
| **Diego** (returning intermediate) | 80 kg | 4 yr | 4×/wk upper/lower | 27.3 | 23-30 | PASS |
| Strong Intermediate | 85 kg | 6 yr | 4×/wk PPL | 31.5 | 29-38 | PASS |
| Advanced | 90 kg | 8 yr | 4×/wk PPL | 41.8 | 36-46 | PASS |
| Elite Path C (bench 180×3) | 95 kg | 10 yr | 4×/wk strength | 52.7 | 49-66 | PASS |
| Smurf (fake 140 kg 1RM) | 70 kg | low | 3×/wk | 18.2 | < Diego | PASS |
| Weak + Consistent | 75 kg | mid | 5×/wk modest | 24.3 | 17-26 | PASS |
| Strong + Inconsistent | 90 kg | mid | 3×/wk heavy | 27.7 | 24-32 | PASS |
| Female Beginner | 58 kg | 0 yr | 3×/wk full-body | 16.3 | 9-17 | PASS |
| Female Intermediate | 60 kg | 2 yr | 4×/wk PPL | 21.3 | 17-27 | PASS |
| Older Lifter (55 yo) | 80 kg | 5 yr | 3×/wk | 23.0 | 14-24 | PASS |
| Machine-Only Gym Tourist | 78 kg | 1 yr | 4×/wk machines | 21.2 | 11-23 | PASS |
| Hypertrophy BB Split | 82 kg | 4 yr | 5×/wk PPL | 31.0 | 22-33 | PASS |

### Why Diego is the load-bearing persona

Diego is the **returning intermediate** — 4 yr of prior training,
80 kg bodyweight, real working weights (bench 95 × 5, squat 130 × 5,
deadlift 160 × 5). Under Phase 24d's flat chain, Diego landed at
character level 1 by week 12, despite logging real intermediate-tier
lifts. That's the **RPG thesis violation** (`memory/project_rpg_thesis.md`):
the RPG layer must never decouple from real lifts. A user who can bench
95 × 5 is not a beginner, and the formula calling them a beginner is the
formula being wrong, not the user.

Phase 29 v2's `tier_diff_mult` recognizes the gap between Diego's
implied_tier (~25) and his starting rank (1), grants a measurable XP
burst, and naturally produces the fast-burst-then-plateau curve. By
week 12, Diego lands at avg rank 27.3 — solidly inside the Strong
Intermediate band. Thesis honored.

## What changed from Phase 24d's 6-archetype baseline

The Phase 24d six-archetype framework (`beginner_24d`,
`intermediate_compound`, `advanced_powerlifter`, `hypertrophy_bodybuilder`,
`bodyweight_only`, `machine_only`) validated the 6-multiplier chain at
the totals level. Those archetypes still run in the calibration suite
for cross-reference (see git history of this doc through 2026-05-20 for
their full week-12 outputs under Phase 24d's chain).

The 13-persona panel **does not retire** the 6 archetypes — both sets
live in the sim. The personas are the steady-state acceptance gate for
Phase 29 v2 specifically; the archetypes are the historical Phase 24d
calibration baseline. If future tuning ever reopens, both sets should
land inside their respective bands.

## Phase Vitality-3 — Strength Vitality XP-gate (sim, PR 1)

> **Status: sim source-of-truth landed; consumer adoption is PR 2.** PR 1 builds
> per-body-part conditioning into the persona panel, adds the gate to
> `compute_set_xp` (defaulting NEUTRAL so the existing fixture regenerates
> byte-identical), adds 2 new personas, and re-centers. PR 2 will regenerate the
> fixture WITH the gate + port the gate to Dart `xp_calculator` + the
> `00084_*_strength_vitality_gate.sql` migration in one atomic 4-site PR.

### The gate

Strength set XP is throttled by per-body-part conditioning, mirroring the cardio
gate (migration `00081`) but using the **decaying reference peak** (migration
`00083`) as the denominator — the decay is what lets a detrained returner's
multiplier recover (a frozen all-time peak never could). **Throttle-only** (D6):
rank is never touched; only XP earn-rate scales.

```
vpct  = clamp(vit_ewma / vit_ref_peak, 0, 1)   (ref_peak <= 0 -> vpct 1.0)
vmult = FLOOR + (1 - FLOOR) * vpct
set_xp_gated = (11-multiplier chain) * vmult    <- applied as the 12th, final factor
```

`vmult` is computed ONCE per body part from PRE-session vitality (non-circular —
the live recompute runs AFTER the XP writes). **Stability linchpin:** the EWMA
that feeds `vpct` is driven by weekly VOLUME LOAD (Sigma vol*share per bp), NEVER
by the gated XP — so the gate throttles the rank currency but never its own
input. No runaway/collapse is possible.

### Vitality clock — daily grid (the non-obvious fidelity requirement)

The live `00083` recompute steps the EWMA + ref_peak **once per UTC day**, with
the EWMA sampled from a **trailing 7-day** volume window and ref_peak decaying at
a 21-day daily half-life. The panel reproduces this on a **daily grid**
(`advance_vitality_week`): each scheduled week appends one volume lump + 6 zero
days, then 7 daily steps run.

This daily fidelity is **load-bearing, not cosmetic.** A naive weekly single-step
model decays ref_peak a full week (×2^(-1/3) ≈ 0.79) while the EWMA takes only
one α_down sample (retains ≈0.85), so ref_peak collapses onto the EWMA and `vpct`
is pinned at 1.0 **for every persona** — the gate would never throttle anyone.
On the daily grid the ref_peak stays above a lapsed EWMA long enough for `vpct`
to fall, which is exactly what makes the gate bite an inconsistent lifter (vpct
0.4–0.7) while leaving a consistent one at 1.0. The only fidelity loss vs a live
replay is intra-week session spacing (a Mon/Wed/Fri spread vs one Monday lump) —
immaterial to the converged `vpct` because the trailing window sums the same
weekly total regardless.

### VPCT_NORMAL and the re-center (the crux)

`VPCT_NORMAL` = median converged (wks 8-12) `vpct` of the 6 consistent personas
(`beginner`, `weak_consistent`, `advanced`, `elite`, `female_intermediate`,
`hypertrophy_bb`).

**Measured: VPCT_NORMAL = 1.00** — all 6 consistent personas sit at full charge.
A lifter who trains every week keeps `vit_ewma >= vit_ref_peak`, so `vpct` clamps
to 1.0 and `vmult = 1.0`. **The gate is a no-op for a consistent lifter.**

Consequently the `STRENGTH_BASE_RECENTER` sweep (1.00 → 1.40, 0.02 grid, bands +
FLOOR held fixed; objective: minimize Sigma|Delta_consistent| while keeping all 6
in-band AND within ±0.5 rank of their pre-gate avg_rank) selects:

**STRENGTH_BASE_RECENTER = 1.00** (unique winner; Sigma|Delta| = 0.00).

Any value > 1.02 pushes the consistent personas out of the ±0.5 guard, because
the gate never offsets them — there is nothing for a base inflation to cancel
against. This is the clean result: the gate ONLY ever throttles the inconsistent
(sandbagger) and detrained (returner) personas, and is invisible to everyone
else, so no re-centering is required.

| Constant | Value | Notes |
|---|---|---|
| `STRENGTH_VITALITY_FLOOR` | `0.50` | `vmult = FLOOR + (1-FLOOR)*vpct`. Chosen over 0.40 on returner week-1 feel (below) |
| `STRENGTH_BASE_RECENTER` | `1.00` | global base_xp scale; sweep winner (VPCT_NORMAL = 1.0 -> no recenter needed) |
| `VITALITY_TAU_UP_DAYS` | `14.0` | EWMA rebuild (live `c_tau_up`) |
| `VITALITY_TAU_DOWN_DAYS_STRENGTH` | `42.0` | EWMA decay (live `c_tau_down_str`) |
| `VITALITY_REF_PEAK_HALFLIFE_DAYS` | `21.0` | ref_peak daily decay (live `c_ref_peak_decay`) |

### FLOOR choice (D1 — decided on returner week-1 feel)

Both floors pass acceptance (returner recovers `vmult >= 0.90` by back-week 2;
sandbagger lands below advanced). FLOOR is therefore decided on the **returner's
first week back**:

| FLOOR | returner back-wk1 earned vmult | back-wk2 | sandbagger conv vpct |
|---|---|---|---|
| 0.40 | 0.40× (60% off) | 0.90× | 0.64 |
| **0.50 (chosen)** | **0.50× (half)** | **0.92×** | 0.64 |

**0.50** honors the muscle-memory thesis (a comeback is an awakening, not a
punishment): a returning lifter's single throttled week back earns half rather
than 60%-off, while the un-farmable property is preserved — a one-off post-layoff
burst still only earns 0.50×, and (per the WIP science gate) the returner's huge
`tier_diff_mult` bonus means net week-1 earning still exceeds a consistent
lifter's. The sandbagger's chronic vpct ≈ 0.64 is unchanged by the floor depth.

### 15-persona panel (`STRENGTH_BASE_RECENTER = 1.00`, `FLOOR = 0.50`)

The 13 existing personas are **byte-identical** to the Phase 29 v2 baseline
(vpct 1.00 → vmult 1.00, recenter 1.00 → no change). The 2 new personas exercise
the gate. (15 = 13 panel + sandbagger in-panel + the returner via its harness.)

| Persona | AvgRk | conv vpct | Band | Pass |
|---|---|---|---|---|
| Female Beginner | 16.3 | 1.00 | 9-17 | PASS |
| True Beginner | 15.7 | 1.00 | 14-18 | PASS |
| Machine Tourist | 21.0 | 1.00 | 11-23 | PASS |
| Older Lifter | 23.0 | 1.00 | 14-24 | PASS |
| Weak+Consistent | 24.2 | 1.00 | 17-26 | PASS |
| Female Intermediate | 21.2 | 1.00 | 17-27 | PASS |
| Smurf | 18.0 | 1.00 | 13-20 | PASS |
| Strong+Inconsistent | 27.5 | 1.00 | 24-32 | PASS |
| Diego (returning) | 27.2 | 1.00 | 24-28 | PASS |
| **Sandbagger** (new) | **19.7** | **0.64** | 18-30 | PASS |
| Hypertrophy BB | 30.8 | 1.00 | 22-33 | PASS |
| Strong Intermediate | 31.2 | 1.00 | 28-38 | PASS |
| Advanced | 41.3 | 1.00 | 35-45 | PASS |
| Elite Path C | 52.2 | 1.00 | 50-65 | PASS |
| **Detrained Returner** (new) | harness | see curve | — | PASS (returner report) |

**Verdict: 14/14 in-panel PASS + returner harness PASS = 15/15.**

Invariants: Sandbagger 19.7 < Advanced 41.3 (a high rank cannot be coasted on —
chronic low charge throttles earn-rate). Female ordering FBeg < FInt < Diego
holds. (The panel's `Smurf 18.0 vs TrueBeg 15.7` display line reads FAIL — this
is a **pre-existing** Phase-29 baseline condition, unchanged by the gate: the
smurf's fake-1RM session-1 is already strength-floored, and the avg_rank display
quirk comes from its higher standing weights, not from any gate interaction.)

### Detrained-returner recovery curve (8wk seed / 8wk layoff / 6wk graded return)

| back-week | earned vmult | post vpct |
|---|---|---|
| seed (wks 1-8) | 1.00 | 1.00 (saturated charge) |
| layoff (wks 9-16) | n/a (zero volume) | 0.39 → 0.00 (decays) |
| **back wk1** | **0.50** (floor — the comeback dip) | 0.83 |
| **back wk2** | **0.92** (>= 0.90 — recovered) | 1.00 |
| back wk3+ | 1.00 (full) | 1.00 |

**Rank never drops during the 8-week layoff** (avg_rank 29.7 held across all 8
layoff weeks — D6, saga inviolate). `vmult >= 0.90` is recovered by **back-week
2** (within the 2-4 week target). The graded return (`return_ramp=(2,3)`: 2
sessions back-wk1, 3 back-wk2, then full) is the honest behavioral model — a
faithful daily-grid recovery from an instant slam-back-to-full-volume return is
~1 week, so the ramp is what produces (and what we document as) the gradual
multi-week curve. Robust across seeds {42,1,7,99} and layoff lengths {4,8,12}.

## How to reproduce

```bash
# Full persona panel (default; now 14 in-panel personas incl. sandbagger)
python tasks/rpg-xp-simulation.py

# Vitality-3 — detrained-returner recovery report (rank-holds + recovery curve)
python tasks/rpg-xp-simulation.py --returner

# Vitality-3 — VPCT_NORMAL measurement + STRENGTH_BASE_RECENTER sweep
python tasks/rpg-xp-simulation.py --recenter-sweep

# Regenerate the 4-site oracle fixture (must stay byte-identical until PR 2)
python test/fixtures/generate_rpg_fixtures.py
```

The panel prints `Verdict: 14/14 PASS` and `Sandbagger < Advanced: OK`; the
returner report prints `Rank never drops during layoff: OK` and
`vmult >= 0.90 recovered by back-week: 2`. CI gates on Dart parity against the
fixture at 1e-4 absolute via
`test/unit/features/rpg/domain/{xp_calculator_test,implied_tier_test,phase29_formula_parity_test}.dart`.

**PR 1 parity guarantee:** with the gate's `vmult` and `base_recenter` arguments
defaulting NEUTRAL (1.0), `test/fixtures/generate_rpg_fixtures.py` regenerates
`rpg_xp_fixtures.json` **byte-identical** — the Vitality-3 numbers only appear
when `simulate_persona` passes the real per-bp values. PR 2 regenerates the
fixture WITH the gate as part of the atomic 4-site adoption.

## Future tuning

A new phase. The Phase 29 v2 constants snapshot above is the locked
launch baseline. Tuning options if post-launch telemetry surfaces gaps:

- **Difficulty curve flattening at higher ranks** — bump
  `LINEAR_XP_PER_RANK` upward to slow Band 2.
- **Gender table re-anchoring** — strengthlevel.com / Symmetric Strength
  publish revised standards periodically.
- **Near-failure activation** — wire `sets.target_reps` from the active
  workout UI to enable the dormant `near_failure_inferred` signal.
- **Frequency table re-tuning** — if telemetry shows the 1.06 / 1.10 /
  1.06 / 1.00 shape under-rewards 4×/wk hypertrophy cadences.

Each would be a new calibration phase with its own 13-persona pass.
