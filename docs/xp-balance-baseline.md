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

## How to reproduce

```bash
# Full 13-persona panel
python tasks/rpg-xp-simulation.py --persona-panel

# Regenerate the 4-site oracle fixture
python test/fixtures/generate_rpg_fixtures.py
```

The fixture regen prints `persona_panel PASS: 13/13` on a clean run. CI
gates on Dart parity against the fixture at 1e-4 absolute via
`test/unit/features/rpg/domain/{xp_calculator_test,implied_tier_test,phase29_formula_parity_test}.dart`.

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
