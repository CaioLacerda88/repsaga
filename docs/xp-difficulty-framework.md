# Exercise Difficulty Framework for XP Calibration

Permanent reference for the `exercises.difficulty_mult` system shipped in
Phase 24, extended in Phase 29 v2 + 29.6 with five additional XP-chain
refinements and a piecewise rank curve. When curating multipliers for new
default exercises (or auditing existing ones), use this document — it is
the literature-derived basis for every tier assignment and constant in the
formula. Last reviewed 2026-05-22.

For the phases that built this framework, see `PROJECT.md` §4 → Phase 24
(four sub-phases — difficulty multiplier infrastructure, 50 new defaults,
bodyweight-as-load, calibration sign-off) and Phase 29 (XP formula v2 +
29.6 absolute strength premium + per-lift × per-gender Symmetric Strength
tier tables + piecewise rank curve). For the SQL migrations, see
`*_add_exercise_difficulty_mult.sql` (00053) and
`00065_phase29_xp_formula_v2.sql`. For the Dart calculator, see
`lib/features/rpg/domain/xp_calculator.dart`,
`lib/features/rpg/domain/implied_tier.dart`, and
`lib/features/rpg/domain/rank_curve.dart`. For the Python parity simulator
that drives the 4-site invariant, see `tasks/rpg-xp-simulation.py`. The
balance-baseline snapshot (per-persona week-12 results) lives at
`docs/xp-balance-baseline.md`.

---

## 1. Difficulty axes

The literature converges on a small number of objectively measurable axes
that distinguish a "hard" lift from an "easy" one. Each is independently
defensible.

**Neural / coordination demand.** Movements with high inter-muscular
coordination requirements recruit more motor units and produce larger
acute neuromuscular fatigue per unit of mechanical work. The Olympic
lifts are the canonical example: peak power outputs of 30–50 W/kg, far
higher than slow strength lifts [Garhammer, 1993, *A Review of Power
Output Studies of Olympic and Powerlifting*, JSCR]. NSCA's *Essentials
of Strength Training and Conditioning, 4th ed.* (Haff & Triplett, 2016)
treats coordination complexity as a primary classifier for exercise
selection and progression order.

**Technical skill ceiling.** Some lifts have a long learning curve where
adding weight without proficiency is unsafe or unproductive. Verkhoshansky
& Siff's *Supertraining (6th ed., 2009)* describes the snatch, clean,
jerk, and full squat as "coordinative-strength" exercises whose loading
must trail technical mastery. The bench press, by contrast, has near-zero
skill ceiling above intermediate level.

**Stabilizer recruitment.** Free-weight exercises require the lifter to
control the load in 6 degrees of freedom; machines reduce this to 1–2.
McCaw & Friday (1994, *A Comparison of Muscle Activity Between a Free
Weight and Machine Bench Press*, JSCR) found 50% higher stabilizer EMG
(anterior deltoid, biceps brachii) in the free-weight bench press at
matched intensity. Schwanbeck et al. (2009, JSCR) replicated this for
the squat: free-weight back squat produced 43% greater overall muscle
activation than Smith-machine squat at the same relative load.

**Joint articulation count.** Multi-joint (compound) exercises by
definition involve more musculature and metabolic cost per set than
single-joint movements. ACSM's *Guidelines for Exercise Testing and
Prescription (11th ed., 2021)* and Schoenfeld's *Science and Development
of Muscle Hypertrophy (2nd ed., 2020)* both prescribe compound exercises
as foundational and isolation as supplemental, reflecting the work-per-set
asymmetry.

**Injury risk under load.** Spinal compressive load varies dramatically
by exercise. Stuart McGill (*Low Back Disorders, 3rd ed., 2016*) measured
peak L4-L5 compressive forces above 18,000 N during maximal deadlifts vs.
<3,000 N during machine-supported movements. Higher risk does not increase
XP directly, but it correlates with technical and stabilizer demand, so it
tracks the same direction as the other axes.

**Free weight vs. machine constraint.** A direct corollary of the
stabilizer axis. The same external load on a machine is "easier" because
the machine handles balance, path, and unilateral correction. Schoenfeld
(2016, *Strength and Conditioning Journal*, *Strength Training for
Aesthetics*) explicitly grades machines lower on neuromuscular cost than
their free-weight analogs.

**Bodyweight as part of the load.** When the trainee's mass is part of
the resistance, true load = external + body. A 70 kg lifter doing a
strict pull-up is moving ~70 kg through a long range against gravity;
the lat pulldown stack reads whatever the pin selects. This is not bro
science — it's a measurement artifact of `volume_load = weight × reps`
that the formula must correct for.

## 2. Tier system

Five tiers, multiplier range 0.85–1.25 (within the hard 0.80–1.25 cap).

| Tier | Name | Mult | Defining characteristics |
|---|---|---|---|
| **T1** | **Olympic / ballistic** | **1.25** | Triple extension, peak power, full-body coordination, highest skill ceiling |
| **T2** | **Foundational compound (free weight, axial load)** | **1.15** | Multi-joint, spine bears load, large stabilizer demand, moderate-to-high skill |
| **T3** | **Standard compound (free weight or supported)** | **1.05** | Multi-joint, lower spinal load OR partial support, moderate stabilizer recruitment |
| **T4** | **Machine compound / cable multi-joint** | **0.90** | Multi-joint but fixed path, low stabilizer demand, low skill ceiling |
| **T5** | **Single-joint isolation** | **0.85** | One articulation, minimal coordination, low skill ceiling |

Spread: 1.25 / 0.85 = 1.47× at equal volume_load before any secondary-muscle
adjustment. Within the "no exercise earns >50% more than another" cap.

> **Phase 24d calibration update (2026-05-15):** T4 was 0.95 in Phase 24a.
> The 6-archetype balance simulation found this too generous — the
> machine_only profile out-earned the intermediate-compound profile at the
> archetype-totals level (criterion C4 inversion in `docs/xp-balance-baseline.md`).
> Dropped to 0.90 (a uniform `-0.05` per-slug propagation applied to the 28
> curated T4 default exercises in migration 00059). The T4 < T3 ordering
> is preserved (T3 1.05 > T4 0.90 by 0.15), and the spread (T1 1.25 / T5
> 0.85 = 1.47×) is unchanged because T1/T5 didn't move.

Bodyweight strength movements (strict pull-up, dip, pistol squat) are
handled separately in §4 — they get assigned to T2 or T3 by character,
then receive a bodyweight-load correction.

## 3. Exercise assignments

**T1 (1.25) — Olympic / ballistic**
Power clean, power snatch, hang clean, clean and jerk, snatch, jerk,
push press, kettlebell snatch, depth jump, broad jump, jump squat,
box jump, medicine ball slam.

**T2 (1.15) — Foundational compound**
Back squat, front squat, conventional deadlift, sumo deadlift, overhead
press, barbell row, pendlay row, zercher squat, trap bar deadlift,
atlas stone, Turkish get-up, strict pull-up*, strict chin-up*, strict
dip*, pistol squat*, archer push-up*.
(*bodyweight — see §4 for load handling)

**T3 (1.05) — Standard compound**
Romanian deadlift, barbell bench press, incline barbell bench, hip
thrust, good morning, dumbbell bench press, incline dumbbell press,
dumbbell row, single-arm dumbbell row, dumbbell shoulder press,
dumbbell lunge, goblet squat, dumbbell Romanian deadlift, hack squat
(loaded, plate-style), kettlebell swing, farmers walk, walking lunge,
push-up*, bodyweight squat*, hanging leg raise*.

**T4 (0.90) — Machine compound / cable multi-joint**
Leg press, Smith-machine squat, chest press machine, seated row, lat
pulldown, assisted pull-up machine, cable row, cable fly (when used
as a multi-joint chest movement), tricep pushdown, face pull, cable
crunch.

**T5 (0.85) — Single-joint isolation**
Barbell curl, dumbbell curl, hammer curl, preacher curl, tricep
extension, skull crusher, lateral raise, cable lateral raise, rear
delt fly, calf raise, leg curl machine, leg extension, plank.

Notes on judgment calls (marked explicitly):
- Trap bar deadlift placed T2 alongside conventional. Camara et al.
  (2016, JSCR) found similar peak force/power; the reduced shear load
  doesn't lower technical demand enough to drop a tier. Judgment call,
  not literature-derived for the exact tier boundary.
- Smith-machine squat at T4: Schwanbeck (2009) puts it firmly below
  free squat. Literature-derived.
- Farmers walk at T3: gait + loaded carry is multi-joint and
  stabilizer-heavy but low skill ceiling. Judgment call.
- Plank at T5: isometric, single "joint pattern" by accounting
  convention. Judgment call.

## 4. The bodyweight question

**Recommendation: Use bodyweight as the load input AND keep the tier
multiplier honest. Both, not either.**

Rationale:

The `volume_load = weight × reps` formula is a mechanical work proxy.
If a 70 kg lifter does a strict pull-up for 8 reps, they have moved
~70 kg × 8 ≈ 560 kg-reps. Pretending the external load is 0 zeroes out
real mechanical work — that's the bug, not a feature. McGuigan
(*Monitoring Training and Performance in Athletes*, 2017) explicitly
recommends including bodyweight in load calculations for calisthenic
work to maintain comparability across modalities.

Letting tier multiplier alone "fix" this is mathematically incoherent:
a heavier lifter doing the same pull-up does more work, and a multiplier
can't see bodyweight. The fix must live in the load input.

Equally, the pull-up doesn't become "easy" once bodyweight is counted.
It still has stabilizer, grip, and scapular control demands that lat
pulldown doesn't. So the tier assignment (T2) stays — bodyweight
strength movements behave like foundational compounds with respect to
coordination, even though the resistance is unconventional.

**Implementation:** For pull-ups, chin-ups, dips, push-ups, pistol
squats, bodyweight squats, archer push-ups, walking lunges, hanging
leg raises — set effective load = bodyweight + any added external load
(belt-weight, vest). Then apply the standard tier multiplier. Pure
bodyweight + tier-by-character is the cleanest model.

The "Neither — strength_mult normalizes it" option is rejected: a
peak-load normalizer doesn't help when the rep itself is logged at
weight=0. The set never enters the system at the right magnitude in
the first place.

## 5. Secondary muscle group as proxy

**Recommendation: Yes, use it, but small and capped. +0.02 per
secondary muscle, cap at +0.06, additive to tier_mult.**

The literature on EMG and activation supports the *direction* of this
proxy but not large weights. Gottschall, Mills & Hastings (2013, JSCR,
*Integration Core Exercises Elicit Greater Muscle Activation Than
Isolation Exercises*) showed that compound exercises recruit more total
musculature than isolation, and that activation spread (multiple muscles
meaningfully active) correlates with metabolic cost per rep. Schoenfeld
et al. (2015, *European Journal of Applied Physiology*) found multi-joint
movements produced greater systemic hormonal and neuromuscular response
than single-joint, with response scaling roughly with muscle mass
recruited.

But the proxy is noisy. `secondary_muscle_groups` is curated by a human,
and the line between "secondary" and "stabilizer" and "synergist" is
fuzzy. A back squat might be tagged with 3 secondaries (glutes,
hamstrings, core) or 6 (add adductors, erectors, calves) depending on
the cataloguer. So the per-muscle bump must be small enough that catalog
noise doesn't dominate tier signal.

**Specifics:**
- +0.02 per `secondary_muscle_groups` entry
- Hard cap at +0.06 (i.e., the first 3 entries count; further entries don't)
- Additive to tier_mult, not multiplicative — keeps the math interpretable
- Does NOT replace tier_mult — the tier captures skill, stabilizer,
  neural demand; secondaries capture muscle-mass-recruited specifically

This keeps the total multiplier inside the 0.80–1.25 cap: T5 with 0
secondaries = 0.85 (floor respected); T1 with cap = 1.25 + 0.06 = 1.31,
clamped to 1.25 at the ceiling.

## 6. Final composite formula

```
difficulty_mult = clamp(
    tier_mult + min(secondary_muscle_count, 3) × 0.02,
    0.85,
    1.25
)
```

Constants:
- tier_mult ∈ {0.85, 0.90, 1.05, 1.15, 1.25}
- bump_per_muscle = 0.02
- max_bumped_muscles = 3 (effective cap of +0.06)
- floor = 0.85, ceiling = 1.25

**Worked examples:**

| Exercise | Tier | tier_mult | sec_count | bump | raw | clamped |
|---|---|---|---|---|---|---|
| Barbell back squat | T2 | 1.15 | 3 | +0.06 | 1.21 | **1.21** |
| Bicep curl | T5 | 0.85 | 0 | 0 | 0.85 | **0.85** |
| Strict pull-up | T2 | 1.15 | 4 | +0.06 (capped) | 1.21 | **1.21** |
| Power clean | T1 | 1.25 | 5 | +0.06 (capped) | 1.31 | **1.25** |
| Lat pulldown (post-24d) | T4 | 0.90 | 3 | +0.06 (capped) | 0.96 | **0.94** (rounded down by the migration `-0.05` propagation; see §2 Phase 24d note) |
| Leg press (post-24d) | T4 | 0.90 | 2 | +0.04 | 0.94 | **0.92** (post-24d delta) |

## 7. Calibration sanity checks

Ratios at equal `weight × reps`, using `set_xp ∝ volume_load ×
difficulty_mult`. Secondary counts approximate typical catalog tagging.

**Deadlift (T2, 4 secondaries → 1.21) vs leg press (T4, 2 secondaries → 0.92 post-24d)**
Ratio: 1.21 / 0.92 = **1.32×**. Deadlift earns 32% more at equal
volume_load (a wider gap than the pre-Phase-24d 1.22×, reflecting the
calibration sign-off that machines should rank meaningfully slower than
free weights). Matches Schoenfeld (2020) and McGill (2016) framing of the
deadlift as the higher-demand movement. Feels right.

**Strict pull-up @ bodyweight (T2, 4 secondaries → 1.21, load = bodyweight) vs lat pulldown (T4, 3 secondaries → 0.94 post-24d)**
At a 70 kg lifter doing 8 reps with bodyweight as load: 70 × 8 × 1.21 =
678. Lat pulldown at 50 kg × 8 × 0.94 = 376. Pull-up earns ~1.80× the
XP — which captures both the harder movement (~1.29× from multipliers,
post-24d) and the heavier effective load (1.40×). Aligns with coaching
intuition that pull-ups are categorically harder. Cossey, Wilson et al.
(2017) on lat activation patterns supports the directionality.

**Power clean (T1, 5+ secondaries → 1.25 clamped) vs barbell bench press (T3, 2 secondaries → 1.09)**
Ratio: 1.25 / 1.09 = **1.15×**. Clean earns 15% more at equal volume_load.
Garhammer's power data would justify a larger gap, but the 1.25 cap
keeps the system from becoming a lottery. Conservative-but-defensible.

**Barbell row (T2, 3 secondaries → 1.21) vs dumbbell row (T3, 3 secondaries → 1.11)**
Ratio: 1.21 / 1.11 = **1.09×**. Modest 9% edge for the bilateral
free-weight version. Fleck & Kraemer (*Designing Resistance Training
Programs, 4th ed., 2014*) treat these as close cousins; the small gap
matches.

**Back squat (T2, 3 secondaries → 1.21) vs leg extension (T5, 0 secondaries → 0.85)**
Ratio: 1.21 / 0.85 = **1.42×**. Maximum allowed differentiation.
Schoenfeld (2020) and ACSM (2021) both treat this gap as foundational
to program design — compound vs. isolation is the largest categorical
jump in resistance training, and the framework reflects that without
exceeding the 1.50× hard cap.

All five ratios fall in defensible territory. No pair exceeds 1.50× at
equal volume_load. The framework is ready for migration.

---

## 8. Phase 29 v2 + 29.6 — The 11-multiplier chain

Phase 24 shipped a six-multiplier chain (base × intensity × strength ×
novelty × cap × difficulty). Phase 29 v2 extends it with five refinements
(per-lift × per-gender implied tier + named-band overload + rolling
frequency + near-failure inference + per-exercise bodyweight load
fraction) plus the Phase 29.6 Path C **absolute strength premium**. The
shipped chain order, in execution sequence (matches
`lib/features/rpg/domain/xp_calculator.dart` and
`supabase/migrations/00065_phase29_xp_formula_v2.sql` byte-for-byte):

```
set_xp = volume_load^0.60                                              -- base
       × intensity_mult(reps) + (0.10 if near_failure_inferred)        -- #4
       × strength_mult(weight, peak_load)                              -- floor 0.40
       × novelty_mult(session_share_count)                             -- exp(-share/15)
       × cap_mult(weekly_share_count)                                  -- 0.30 if >= 15
       × difficulty_mult(exercise)                                     -- [0.85, 1.25]
       × tier_diff_mult(implied_tier, current_rank)                    -- #1 — Pokemon Gen 5 adapted
       × overload_mult(weight, reps, prior_best_in_band)               -- #2 — named rep bands
       × frequency_mult(sessions_for_bp_in_7d)                         -- #3 — rolling weekly count
       × abs_strength_premium(implied_tier)                            -- 29.6 Path C
```

Then distributed across body parts via `xp_attribution`:
`xp_awarded[bp] = set_xp × attribution[exercise][bp]`.

### 8.1 Why this shape

Phase 24d's six-multiplier baseline matched 6 calibration archetypes at
the totals level, but the **13-persona panel** for Phase 29 surfaced a
thesis violation: a 4-yr returning intermediate (Diego, 80 kg, real
lifts) landed at character level 1 by week 12. The RPG layer was
decoupling from real lifts — failing the load-bearing principle
(`memory/project_rpg_thesis.md`). Phase 29 v2 introduces the Pokemon
Gen 5 scaled-XP mechanic adapted to gym mechanics: a low-rank user
logging a heavy compound lift gets a measurable burst of XP
(mathematically derived from rank-vs-implied-tier gap), naturally
producing the fast-burst-then-plateau curve that matches both RPG
balance feel AND gym physiology (newbie gains → plateau).

Phase 29.6 then closes the "elite competitor at low rank" gap: when a
new user shows up with a 180 kg × 3 bench, the formula recognizes the
absolute load magnitude (not just the gap-to-rank) and grants a
persistent premium tied to actual lift strength.

### 8.2 Locked constants — Phase 29 v2

The 4-site parity invariant (Python sim, fixture JSON, Dart, SQL) holds
at 1e-4 absolute. Every constant below is mirrored at all four sites.

| Constant | Value | Notes |
|---|---|---|
| `VOLUME_EXPONENT` | `0.60` | unchanged from Phase 24d |
| `NOVELTY_DENOMINATOR` | `15.0` | unchanged |
| `WEEKLY_CAP_SETS` | `15.0` | unchanged |
| `OVER_CAP_MULTIPLIER` | `0.30` | unchanged |
| `STRENGTH_MULT_FLOOR` | `0.40` | unchanged |
| `DIFFICULTY_MULT_FLOOR` | `0.85` | per-exercise floor |
| `DIFFICULTY_MULT_CEILING` | `1.25` | per-exercise ceiling |
| `E_BONUS` | `0.8` | absolute-strength premium max boost |
| `E_FLOOR` | `35.0` | implied_tier below this → no premium |
| `E_CEIL` | `55.0` | implied_tier above this → max premium |
| `NF_INTENSITY_BONUS` | `0.10` | near-failure adds +0.10 to intensity |
| `NF_TARGET_THRESHOLD` | `0.85` | actual < target × 0.85 → near_failure |
| `FREQUENCY_MULT_TABLE` | `[1.00, 1.06, 1.10, 1.06, 1.00]` | sessions 1/2/3/4/5+ |
| `XP_BASE` | `60` | rank curve geometric base (ranks 1-20) |
| `XP_GROWTH_BAND1` | `1.10` | geometric growth in ranks 1-20 |
| `RANK_CURVE_BREAKPOINT` | `20` | piecewise pivot |
| `LINEAR_XP_PER_RANK` | `367.0` | **LITERAL** — not derived from `60 × 1.10^19 ≈ 366.957` (the derived float would compound rounding at high ranks across the 4 parity sites) |

## 9. Refinement #1 — `tier_diff_mult` (Pokemon Gen 5 adapted)

The XP-scaling formula used in Pokemon's Gen 5 trainer-battle reward
mechanic, adapted for rank-vs-tier instead of level-vs-opponent-level.

```
T = implied_tier(exercise, weight, reps, bodyweight, gender)   ∈ [0, 70]
R = current_rank for the exercise's primary body part          ∈ [1, 99]

tier_diff_mult = clamp(((2T + 10) / (T + R + 10))^2.5, 0.25, 8.0)
```

**Behavior:**

- At parity (T = R): mult = 1.0 exactly.
- T >> R (underleveled lifter, heavy lift): mult climbs toward 8.0 cap.
- T << R (overleveled, light technique work): mult floors at 0.25.
- Smooth across the boundary — no step discontinuity.

The 8.0/0.25 clamps are aggressive but necessary to keep the formula
from degenerating at extreme R-T gaps (an elite at rank 5 hitting a 2.5×BW
bench shouldn't earn 30× — 8× is the locked ceiling that still feels
proportional).

### 9.1 `implied_tier` derivation

Three steps: estimate 1RM via Brzycki, normalize to bodyweight + apply
per-exercise isolation discount, interpolate into the per-lift × per-gender
Symmetric Strength table.

```
1RM_est        = weight × 36 / (37 - reps)                    -- Brzycki
ratio          = 1RM_est / bodyweight ÷ isolation_discount
tier           = linear_interpolate(tier_table[family][gender], ratio)
                 ∈ [0, 70]
```

**Lift families** (6): bench, squat, deadlift, ohp, row, curl. Each
exercise maps to a family in `lib/features/rpg/domain/implied_tier.dart`.

**Gender tables** (2 per family — male / female): sourced from Symmetric
Strength + strengthlevel.com standards (2026-05-20 snapshot). Each table
has 8 (ratio, tier) anchor pairs spanning Untrained → Legendary.
`gender = NULL` or `'other'` falls back to the male table (matches the
Python sim's `female=False` default and preserves backward-compat for
existing users who signed up before the `profiles.gender` column existed).

**Isolation discount** (per-exercise; default 1.0):

| Exercise family | Discount |
|---|---|
| Compound (bench, squat, deadlift, ohp, row) | 1.00 |
| Curl (bicep, hammer) | 0.55 |
| Tricep pushdown | 0.55 |
| Lateral raise | 0.25 |

**Legendary extension** (rank 65-70):

- Bench: 2.5× BW
- Squat: 3.0× BW
- Deadlift: 3.5× BW
- OHP: 1.4× BW

NULL bodyweight (user hasn't entered it via Phase 24c's prompt yet) falls
back to a sentinel implied_tier of **15.0** (the `kBodyweightZeroFallback`
constant) — gentle middle of the table; no XP cliff for users who haven't
filled in their weight.

## 10. Phase 29.6 Path C — `abs_strength_premium`

A persistent multiplier tied to ABSOLUTE strength (implied_tier), not to
rank or to the rank-vs-tier gap. Closes the "elite at low rank" gap that
`tier_diff_mult` alone can't address (`tier_diff_mult` decays as R climbs
toward T, but an experienced lifter's PR magnitude should keep paying out
as long as the lifter keeps repping it).

```
abs_strength_premium = 1 + E_BONUS × clamp((T - E_FLOOR) / (E_CEIL - E_FLOOR), 0, 1)
                     = 1 + 0.8 × clamp((T - 35) / 20, 0, 1)
```

**Behavior:**

- T < 35: premium = 1.0 (no boost; novice / intermediate territory).
- T = 45 (mid-band, ~Advanced lifter): premium = 1.4×.
- T = 55: premium = 1.8× (max).
- T > 55: clamped at 1.8× (no runaway scaling for legendary outliers).

This is the **Path C** resolution from the Phase 29.6 design call: the
team evaluated several premium shapes (persistent vs decaying, linear vs
sigmoid) and locked Path C (persistent, linear, clamped). Persistent
matters because the premium is supposed to reward strength capacity itself
— if it decayed with rank, it would re-collapse into a `tier_diff_mult`
variant.

## 11. Refinement #2 — `overload_mult` (named rep bands)

Rewards in-band PR effort. Tracks the user's best (weight, reps) per
(user, exercise, rep_band) in the `exercise_peak_loads_by_rep_range`
table (introduced in migration 00065; owner-read RLS, SECURITY DEFINER
writes from the XP RPCs).

**Rep bands** (physiological, not mathematical):

| Reps | Band |
|---|---|
| 1-4 | `heavy` |
| 5-7 | `strength` |
| 8-12 | `hypertrophy` |
| 13+ | `endurance` |

**AND/OR ladder** (matched against the prior best in the same band):

| Condition | `overload_mult` |
|---|---|
| `weight > prior_best.weight` | **1.15** |
| `reps > prior_best.reps AND weight >= prior_best.weight` | **1.10** |
| Any improvement (either weight or reps up) | **1.05** |
| No improvement | **1.00** |

Strict-improvement semantics: ties don't qualify. The ladder is
short-circuit `IF`-chain — the first matching branch wins.

The `exercise_peak_loads_by_rep_range` table coexists with the legacy
`exercise_peak_loads` (exercise-wide PR tracker from Phase 18a). The
first is purely for `overload_mult` lookups; the second remains the
canonical PR detector consumed by the Personal Records feature.

## 12. Refinement #3 — `frequency_mult` (rolling 7d session count)

Rewards smart weekly cadence — productive volume is distributed across
several sessions, not crammed into one. Counts distinct workout sessions
in the trailing 7d window that touched the same body part.

```
n = COUNT(DISTINCT workout_id) FROM xp_events
    WHERE body_part = bp
      AND occurred_at > NOW() - INTERVAL '7 days'
      AND workout_id != current_workout_id          -- exclude in-flight session
```

Lookup table (sessions 1 / 2 / 3 / 4 / 5+):

| Sessions in 7d | `frequency_mult` |
|---|---|
| 1 (first session of the week) | 1.00 |
| 2 | 1.06 |
| 3 (peak — typical hypertrophy cadence) | 1.10 |
| 4 | 1.06 |
| 5+ (over-training territory) | 1.00 |

The `workout_id != current` exclusion prevents the in-flight session
from double-counting itself. Implemented inline in the RPC via a simple
`COUNT(...) FILTER` clause; if hot-path queries become slow at scale a
materialized counter is queued for Phase 29.5.

The table is intentionally gentler than the original prototype (which
peaked at 1.15) per the Phase 29 PR 1 ambiguity-resolution call — the
13/13 persona PASS was validated against `[1.00, 1.06, 1.10, 1.06, 1.00]`.

## 13. Refinement #4 — `near_failure_inferred` (no UI toggle)

The XP formula rewards effort intensity through `intensity_mult(reps)`
already, but Phase 29 v2 adds a **derived** near-failure signal — no
per-set checkbox in the UI. The intent is to capture the "I left maybe
one rep in the tank" effort without adding a self-report toggle that
would bloat the set row and bias to optimism.

```
near_failure_inferred = (actual_reps < target_reps × 0.85)
                      ? intensity_mult += NF_INTENSITY_BONUS    -- +0.10
                      : intensity_mult unchanged
```

**Current state:** the helper is plumbed end-to-end in Dart + SQL +
fixture parity, but `sets.target_reps` is not yet a column. The SQL RPCs
hard-NULL `v_target_reps`, so `rpg_near_failure_inferred` always returns
FALSE on the server. Helper is ready for when the active-workout UI
exposes a target-reps signal (planned follow-up). The fixture already
contains 7 near-failure parity cases to pin the Dart side.

## 14. Refinement #5 — `bodyweight_load_ratio` (per-exercise)

Phase 24c shipped a binary `uses_bodyweight_load BOOLEAN` flag with a
flat all-1.0 simple-addition semantic for 20 curated slugs. Phase 29 v2
replaces that flat-1.0 with **per-exercise biomechanical fractions**
sourced from the kinesiology literature:

| Slug | `bodyweight_load_ratio` | Source |
|---|---|---|
| `pull_up`, `chin_up`, `wide_grip_pull_up`, `muscle_up` | 1.00 | Youdas et al. 2010 (full BW lift through long ROM) |
| `dips`, `ring_dip`, `pistol_squat` | 0.95 | Free-hanging or unilateral squat near-full BW |
| `archer_push_up` | 0.80 | Suprak et al. 2011 (asymmetric load on one arm) |
| `decline_push_up` | 0.74 | Suprak (head-down inversion increases the percent of BW supported by the arms) |
| `bodyweight_squat`, `single_leg_deadlift_unweighted` | 0.75 | Bryanton et al. 2012 (effective system mass minus support leg) |
| `push_up` (standard) | 0.64 | Suprak (~64% of BW supported on the hands in plank-position push-up) |
| `incline_push_up` | 0.41 | Suprak (head-up inversion reduces the load) |
| Everything else | 1.00 (default) | Conservative — no biomech literature → no discount |

Effective weight (used by `volume_load`, `strength_mult`, and
`implied_tier`):

```
effective_weight = sets.weight + bodyweight_kg × exercises.bodyweight_load_ratio
                   (only for slugs where uses_bodyweight_load = TRUE)
```

The column is `numeric(3,2) NOT NULL DEFAULT 1.0` with
`CHECK BETWEEN 0.20 AND 1.00` (gym-realistic range).

## 15. Refinement #6 — Piecewise rank curve

The Phase 24d rank curve was geometric end-to-end: `xp_to_next(n) = 60 × 1.10^(n-1)`.
That works for ranks 1-20 (the newbie honeymoon) but generates absurd
totals at the top end: rank 50 ≈ 63,431 XP, rank 99 ≈ 6.83M XP. Two
problems:

1. At launch, no real user will see a high rank without years of
   training, but the Phase 29 v2 persona simulation showed mature
   personas plateauing in the 25-35 range — meaning rank 50+ matters for
   the post-launch endgame. 63k XP per rank past rank 50 makes that
   endgame inaccessible at any realistic training cadence.
2. The geometric curve is exponential — at rank 99 each rank costs 6.83M
   XP, which is a lottery-ticket gap from rank 98 (no felt progress
   between consecutive ranks unless you specialize hard).

Phase 29 v2 replaces the curve with a **piecewise** structure:

```
xp_for_rank(R):
  if R <= 1:  return 0
  if R <= 20: return 60 × (1.10^(R-1) - 1) / 0.10      -- geometric Band 1
  else:       return xp_for_rank(20) + (R - 20) × 367.0 -- linear Band 2
```

**Cumulative milestones (Phase 29 v2):**

| Rank | Cumulative XP |
|---|---|
| 1 | 0 |
| 10 | ~814 |
| 20 (Band 1 → Band 2 breakpoint) | ~3,440 |
| 30 | ~7,110 |
| 50 | ~14,448 (3,440 + 30 × 367) |
| 70 | ~21,788 (3,440 + 50 × 367) |
| 99 | ~32,433 (3,440 + 79 × 367) |

Why piecewise:

- **Band 1 (geometric, 60 × 1.10^(n-1)):** preserves the Phase 24d
  newbie honeymoon — rank 1→20 in ~8 weeks of consistent training, the
  rank curve that the 6-archetype Phase 24d calibration was tuned
  against.
- **Band 2 (linear, 367.0 XP/rank LITERAL):** flat per-rank cost in the
  long tail. Predictable. Each rank past 20 costs exactly the same as
  the previous one — the lifer's flex is "I've grinded N more linear
  ranks past 20," not "I bought a lottery ticket at rank 60."

**Critical:** `367.0` is a LITERAL constant in every Phase 29 v2
implementation site (Python sim / fixture / Dart / SQL). The derived
value `60 × 1.10^19 ≈ 366.957` would compound float rounding at high
ranks across the 4 parity sites and silently break the 1e-4 invariant.
This is pinned by a dedicated test: `cumulativeXpForRank(21) - cumulativeXpForRank(20) == 367.0`
exactly.

**Backfill semantics:** the 00065 migration ran
`UPDATE body_part_progress SET rank = rpg_rank_for_xp(total_xp)` for all
users. Existing users above rank ~21 see their rank shift UP because
the piecewise curve makes high ranks dramatically cheaper. Pre-29
`xp_events.payload` values stay frozen (forward-only semantics — a
historical event still records the XP it earned under the prior chain);
only the derived `body_part_progress.rank` column changes.

## 16. Character level (unchanged through Phase 29)

```
character_level = max(1, floor((Σ active_ranks - N_active) / 4) + 1)
N_active = 6 (chest, back, legs, shoulders, arms, core)
```

This is the canonical formula encoded in the `character_state` view from
migration 00040 §9. Note (`memory/cluster-character-level-misuses-rank-fn`):
the function `rpg_rank_for_xp` is the PER-body-part XP→rank curve, not a
character-level reduction. Applied to a SUM across body parts it returns
silently-incorrect values — a r3-across-6 user (real character level 3)
would be reported as level 6. Title-detection blocks in
`record_session_xp_batch` + `record_set_xp` must use the canonical
`character_state`-shaped reduction, not `rpg_rank_for_xp(SUM(total_xp))`.

## 17. 13-persona panel — Phase 29 v2 validation (13 / 13 PASS)

Every persona's week-12 average rank lands inside its target band. Full
per-persona simulation output in `docs/xp-balance-baseline.md`.

| Persona | Body weight | Experience | wk12 avg rank | Target band | Verdict |
|---|---|---|---|---|---|
| True Beginner | 75 kg | 0 yr | 15.7 | 13-19 | PASS |
| Diego (returning intermediate) | 80 kg | 4 yr | 27.3 | 23-30 | PASS |
| Strong Intermediate | 85 kg | 6 yr | 31.5 | 29-38 | PASS |
| Advanced | 90 kg | 8 yr | 41.8 | 36-46 | PASS |
| Elite Path C (competitive, bench 180×3) | 95 kg | 10 yr | 52.7 | 49-66 | PASS |
| Smurf (fake 140 kg 1RM @ 70 kg) | 70 kg | low | 18.2 | < Diego | PASS |
| Weak + Consistent (5×/wk modest lifts) | 75 kg | mid | 24.3 | 17-26 | PASS |
| Strong + Inconsistent (3×/wk strong lifts) | 90 kg | mid | 27.7 | 24-32 | PASS |
| Female Beginner | 58 kg | 0 yr | 16.3 | 9-17 | PASS |
| Female Intermediate | 60 kg | 2 yr | 21.3 | 17-27 | PASS |
| Older Lifter | 80 kg (55 yo) | 5 yr | 23.0 | 14-24 | PASS |
| Machine-Only Gym Tourist | 78 kg | 1 yr | 21.2 | 11-23 | PASS |
| Hypertrophy BB Split | 82 kg | 4 yr | 31.0 | 22-33 | PASS |

The thesis-violating persona from Phase 24d (Diego — 4-yr returning
intermediate landing at character level 1) now lands at avg rank 27.3
under Phase 29 v2 — solidly inside the Strong Intermediate band, the
RPG layer is back in lockstep with real lifts.

---

## Sources

- ACSM. *Guidelines for Exercise Testing and Prescription, 11th ed.*, 2021.
- Camara, K.D. et al. "An Examination of Muscle Activation and Power
  Characteristics While Performing the Deadlift Exercise With Straight
  and Hexagonal Barbells." *Journal of Strength and Conditioning Research*,
  2016.
- Cossey, A., Wilson, B. et al. EMG activation patterns of latissimus
  dorsi across pulling movements, 2017.
- Fleck, S.J. & Kraemer, W.J. *Designing Resistance Training Programs,
  4th ed.* Human Kinetics, 2014.
- Garhammer, J. "A Review of Power Output Studies of Olympic and
  Powerlifting." *Journal of Strength and Conditioning Research*, 1993.
- Gottschall, J.S., Mills, J., Hastings, B. "Integration Core Exercises
  Elicit Greater Muscle Activation Than Isolation Exercises." *Journal
  of Strength and Conditioning Research*, 2013.
- Haff, G.G. & Triplett, N.T. (eds.). *Essentials of Strength Training
  and Conditioning, 4th ed.*, NSCA / Human Kinetics, 2016.
- McCaw, S.T. & Friday, J.J. "A Comparison of Muscle Activity Between
  a Free Weight and Machine Bench Press." *Journal of Strength and
  Conditioning Research*, 1994.
- McGill, S. *Low Back Disorders: Evidence-Based Prevention and
  Rehabilitation, 3rd ed.* Human Kinetics, 2016.
- McGuigan, M. *Monitoring Training and Performance in Athletes.* Human
  Kinetics, 2017.
- Schoenfeld, B.J. "Strength Training for Aesthetics." *Strength and
  Conditioning Journal*, 2016.
- Schoenfeld, B.J. *Science and Development of Muscle Hypertrophy, 2nd ed.*
  Human Kinetics, 2020.
- Schoenfeld, B.J. et al. "Differential Effects of Heavy Versus Moderate
  Loads on Measures of Strength and Hypertrophy in Resistance-Trained
  Men." *European Journal of Applied Physiology*, 2015.
- Schwanbeck, S., Chilibeck, P.D., Binsted, G. "A Comparison of Free
  Weight Squat to Smith Machine Squat Using Electromyography." *Journal
  of Strength and Conditioning Research*, 2009.
- Verkhoshansky, Y. & Siff, M. *Supertraining, 6th ed.* Verkhoshansky SSTM,
  2009.
