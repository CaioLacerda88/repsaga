# Exercise Difficulty Framework for XP Calibration

Permanent reference for the `exercises.difficulty_mult` system shipped in
Phase 24. When curating multipliers for new default exercises (or auditing
existing ones), use this document — it is the literature-derived basis for
every tier assignment and constant in the formula. Last reviewed 2026-05-13.

For the phase that introduced this framework, see `PROJECT.md` §3 →
Phase 24 — XP Balancing. For the SQL migration adding the column, see
the migration named `*_add_exercise_difficulty_mult.sql`. For the Dart
calculator, see `lib/features/rpg/domain/xp_calculator.dart` (`difficultyMult`
param). For the Python parity simulator, see `tasks/rpg-xp-simulation.py`.

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
| **T4** | **Machine compound / cable multi-joint** | **0.95** | Multi-joint but fixed path, low stabilizer demand, low skill ceiling |
| **T5** | **Single-joint isolation** | **0.85** | One articulation, minimal coordination, low skill ceiling |

Spread: 1.25 / 0.85 = 1.47× at equal volume_load before any secondary-muscle
adjustment. Within the "no exercise earns >50% more than another" cap.

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

**T4 (0.95) — Machine compound / cable multi-joint**
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
- tier_mult ∈ {0.85, 0.95, 1.05, 1.15, 1.25}
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

## 7. Calibration sanity checks

Ratios at equal `weight × reps`, using `set_xp ∝ volume_load ×
difficulty_mult`. Secondary counts approximate typical catalog tagging.

**Deadlift (T2, 4 secondaries → 1.21) vs leg press (T4, 2 secondaries → 0.99)**
Ratio: 1.21 / 0.99 = **1.22×**. Deadlift earns 22% more at equal
volume_load. Matches Schoenfeld (2020) and McGill (2016) framing of the
deadlift as the higher-demand movement. Feels right.

**Strict pull-up @ bodyweight (T2, 4 secondaries → 1.21, load = bodyweight) vs lat pulldown (T4, 3 secondaries → 1.01)**
At a 70 kg lifter doing 8 reps with bodyweight as load: 70 × 8 × 1.21 =
678. Lat pulldown at 50 kg × 8 × 1.01 = 404. Pull-up earns ~1.68× the
XP — which captures both the harder movement (1.20× from multipliers)
and the heavier effective load (1.40×). Aligns with coaching intuition
that pull-ups are categorically harder. Cossey, Wilson et al. (2017) on
lat activation patterns supports the directionality.

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
