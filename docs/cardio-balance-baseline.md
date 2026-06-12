# Cardio Balance Baseline — v1 DRAFT

> **Status: v1 DRAFT calibration (not yet shipped, not yet 4-site-wired).**
> Companion to `docs/xp-balance-baseline.md` (strength) and the design analysis
> in `docs/cardio-stat-plan.md`. This is the *formula refinement + balance
> simulation* the cardio stat needs before it becomes an implementation phase —
> the cardio analogue of the Phase 29 strength calibration. Source of truth:
> `tasks/cardio-xp-simulation.py`. Reproduce: `python tasks/cardio-xp-simulation.py`.
>
> When cardio moves to an active phase, this baseline gets promoted to a 4-site
> parity invariant (Python sim → fixture oracle → Dart → SQL) exactly like the
> strength chain, and the constants below get locked.

---

## 1. Why a separate model (the science verdict)

Strength scoring is **load** (weight×reps → 1RM tier); cardio is **rate × time**
(energy turnover; VO₂max is a flux, mL O₂·kg⁻¹·**min⁻¹**). They are dimensionally
incompatible — cardio cannot reuse the weight×reps tier tables. So cardio gets
its own metric (**MET-minutes**, ACSM Compendium) and its own capacity tier
(**estimated VO₂max → sex/age percentile**), but **reuses** two things from the
strength system for cross-stat consistency:

1. **The shared piecewise rank curve** (rank 5 ≈ 278 XP, 20 ≈ 3,070, 50 ≈ 14,080)
   — so a cardio rank feels like a strength rank and feeds the character level
   additively (denominator 4, `N_active` 6→7).
2. **The `tier_diff_mult` "capacity-chases-rank" mechanic** (Pokémon Gen 5
   adaptation). For strength, the per-set tier comes from the **load lifted in
   that set** (an impressive lift, not the lifter's standing capacity). The
   cardio analogue: the per-session tier comes from **what the session
   demonstrates**.

### The honesty guarantee — rank credits *demonstrated performance*
Cardio rank credits **what you demonstrate**, not estimated capacity — exactly as
strength credits the lift, not the lifter. The model derives **two separate
signals from physiology**, so the science is the sole judge:

- **Intensity is *relative* to current fitness** (`rel = MET×3.5 / standing
  VO₂max`) — drives the reward weighting + the adaptation stimulus. The *same*
  walk is a real stimulus for a deconditioned person (~55% of their low VO₂max)
  and worthless for a runner (~25% of their high VO₂max).
- **Tier is what the session *demonstrated*** (`demonstrated_vo2 = MET×3.5 /
  sustainable_fraction(duration)` → percentile → tier) — drives the
  `tier_diff_mult` burst.

This resolves the cardio thesis the way the physiology demands:

- **A walk demonstrates ~walking-level fitness for ANYONE → low tier → low rank
  credit.** Walking is "worth little" *for the stat* — for the deconditioned and
  the fit alike (a fit ex-runner who now only walks earns ~nothing).
- **But walking still raises a deconditioned person's underlying VO₂max**
  (real physiology) — the base that lets them later jog and *then* demonstrate
  (and rank) more. You must add intensity to keep ranking — the real training
  principle, enforced by the model.
- **A genuinely fit runner demonstrates it with hard efforts → high tier → ranks
  up fast** (the cardio "Diego" — capacity honored *once shown*).
- **Huge easy volume converges to ~the demonstrated tier, never past it.**

> **The walking question, answered by science (not product taste):** walking is
> worth what it *demonstrates* — which is low — so it gives very little rank
> progression for everyone. It is *not worthless physiologically* for a beginner
> (it builds the aerobic base), but that improvement shows up as a higher
> *underlying* VO₂max that the rank only credits once the user demonstrates it at
> higher intensity. "If walking is worthless, make it worthless" — the model does
> exactly this, and lets the physiology decide when it isn't.

---

## 2. The cardio formula (v1 DRAFT)

A logged session = `(activity, duration, intensity)`. `intensity` is the chosen
relative effort for self-paced work (run/bike/swim — abs MET scales with fitness)
OR a fixed absolute MET for fixed-pace work (walking, a machine setting).

```
abs_MET        = (rel_effort × VO₂max) / 3.5   (self-paced)   -- a fitter athlete
               = fixed activity MET            (walking etc.)    runs faster at "easy"
rel_intensity  = abs_MET × 3.5 / standing_VO₂max              -- RELATIVE to current fitness
met_minutes    = abs_MET × duration_min                       -- ACSM absolute energy
eff_met_min    = met_minutes × intensity_mult(rel_intensity)  -- sub-50% ≈ ~0 (Wenger & Bell)
capped         = weekly diminishing-returns on eff_met_min beyond WEEKLY_CARDIO_CAP
base_xp        = capped ^ VOLUME_EXPONENT (0.60)              -- mirrors strength volume_load^0.60
demonstrated   = abs_MET × 3.5 / sustainable_fraction(duration)  -- what THIS session showed
implied_tier   = vo2_to_percentile(demonstrated, age, sex) → tier[0,70]  -- ACSM/Cooper norms
cardio_xp      = base_xp
               × tier_diff_mult(cardio_rank, implied_tier)    -- DEMONSTRATED tier chases rank
               × modality_mult(activity)                      -- run 1.00 reference
               × vitality_xp_mult(vitality_pct)               -- VITALITY GATE (never touches rank)
               × CARDIO_XP_SCALE (3.5)                         -- currency → shared rank curve
cardio_rank    = rank_for_xp(Σ cardio_xp)                      -- SHARED piecewise curve
```

**Two derived signals, deliberately separate:** `rel_intensity` (relative to your
*current* fitness) governs the reward weighting and the adaptation stimulus;
`demonstrated` (what the session *showed*, via the velocity-duration curve)
governs the tier burst. A walk demonstrates ~15 mL/kg/min for anyone → low tier →
low rank, while a hard 30-min tempo demonstrates ~your true VO₂max → high tier.

**VO₂max progression (the "getting fitter" axis):** each week, VO₂max rises by a
**saturating approach to a personal ceiling**, scaled by the week's
intensity-weighted stimulus — novices gain fast, the near-ceiling barely move:
```
ΔVO₂ = VO2_GAIN_K × (weekly_eff_met_min / VO2_STIMULUS_NORM)
                  × (ceiling − VO₂) / ceiling          -- headroom shrinks near ceiling
```
Rising VO₂ raises `implied_tier`, which keeps `tier_diff_mult` > 1 until rank
catches capacity — producing the same fast-gains-then-plateau shape the
physiology shows (Bacon 2013; HERITAGE).

### Vitality — gates XP earned, never the rank

Vitality is an asymmetric-EWMA conditioning signal (permanent peak). The
**mechanic** is shared with strength, but the **kinetics are different physiology
and intentionally NOT unified**:

- **Strength Vitality = muscle memory** (myonuclear/epigenetic retention;
  Bruusgaard 2010, Seaborne 2018) → strength "remembers," decays **slow**
  (`τ_down ≈ 6 wk`).
- **Cardio Vitality = cardiorespiratory detraining** (Coyle: VO₂max −7% in ~12
  days) → decays **~2× faster** (`τ_down ≈ 3 wk`). Rebuild `τ_up ≈ 2 wk` (no
  strong cardio analogue to strength's myonuclear rebuild advantage).

**Never copy these constants between stats — they encode different biology.** The
design spec currently uses Vitality only for the rune *glow*; this baseline wires
it into the earning chain per the intended mechanic:

```
vitality_pct   = clamp(vitality_ewma / vitality_peak, 0, 1)   -- rebuilds fast, decays slow
vitality_xp_mult = VITALITY_XP_FLOOR + (1 − VITALITY_XP_FLOOR) × vitality_pct
```

- **Rank is NEVER lowered** — the saga is inviolate (permanent peak).
- **Vitality < 100% *decreases the XP a session earns*** until the user rebuilds
  conditioning to 100%, at which point full XP resumes. With `VITALITY_XP_FLOOR =
  0.40`, a fully-lapsed returner earns 40% and ramps to 100% as they recondition
  (`FLOOR = 0` would be strictly linear / harshest — a product tunable).
- **Why:** anchors rank progress to *sustained* conditioning, so a one-off burst
  after a long layoff can't bank full rank — the same un-farmable property as the
  demonstrated-tier and intensity gates. (Consistent trainers sit at 100% Vitality
  → `mult = 1.00` → the 12-persona panel is unaffected.)

`python tasks/cardio-xp-simulation.py --vitality` — comeback demo (4-wk build →
6-wk layoff → return):

| wk | phase | rank | vit% | xpMult |
|---|---|---|---|---|
| 4 | build | 21 | 100% | 1.00 |
| 5–10 | **LAYOFF** | **21 (frozen)** | 100→**14%** | — |
| 11 | return | 22 | 14% | **0.48** |
| 12 | return | 24 | 54% | 0.73 |
| 13 | return | 25 | 79% | 0.88 |

Rank holds flat through the layoff; on return, XP is throttled (0.48×) and ramps
back to full as Vitality rebuilds. Note the steeper drop than strength would show
(τ_down=3 wk vs 6 wk) — **cardio detrains faster, by design.** Whether the strength
stat should *also* gate XP is a separate UX decision (§8) — and if so it runs on
*its own* slow-decay kinetics, never these.

---

## 3. Constants snapshot (v1 DRAFT — tuned on the panel)

| Constant | Value | Notes |
|---|---|---|
| `VOLUME_EXPONENT` | `0.60` | `base_xp = capped_met_min^this` (shared with strength) |
| `CARDIO_XP_SCALE` | `3.5` | calibrates MET-min currency onto the shared rank curve |
| `INTENSITY_ANCHORS` | `(0.35,0.05) (0.50,0.35) (0.70,0.75) (0.85,1.05) (0.95,1.35) (1.05,1.45)` | %VO₂max → multiplier; sub-50% ≈ maintenance (Wenger & Bell) |
| `WEEKLY_CARDIO_CAP_METMIN` | `2500` | intensity-weighted MET-min before over-cap discount |
| `OVER_CAP_MULT` | `0.30` | applied to weekly volume beyond the cap |
| `MODALITY_MULT` | run/row/swim/treadmill `1.00`, hiit `1.05`, elliptical `0.97`, bike/walk `0.95` | "difficulty" analog; MET already captures most modality difference |
| `VO2_CEILING_CAP` | `90` | practical human VO₂max max (Svendsen 97.5 / Dæhlie 96 records) |
| `VO2_GAIN_K` | `0.040` | progression rate (novice +~15%/12wk, trained ≤5%; saturating toward genetic ceiling) |
| `VO2_STIMULUS_NORM` | `1200` | weekly eff-MET-min counting as 1 stimulus unit |
| `sustainable_fraction` | `(6,1.00) (15,0.93) (30,0.88) (45,0.84) (60,0.80) (90,0.76) (120,0.74) (180,0.70)` | velocity-duration curve → `demonstrated_vo2` (the cardio analogue of estimating 1RM from a set) |
| `VITALITY_TAU_UP_WEEKS` / `_DOWN_` | `2.0` / `3.0` | conditioning EWMA. τ_down=**3** (NOT strength's 6) — cardio detrains ~2× faster (Coyle). Separate physiology; never share with strength |
| `VITALITY_XP_FLOOR` | `0.40` | XP-mult floor when fully lapsed (`mult = FLOOR + (1−FLOOR)×vitality_pct`); 0 = strictly linear |
| `TIER_DIFF_*` | `OFFSET 10 · EXP 2.5 · MAX 8.0 · MIN 0.25` | **verbatim** from strength |
| rank curve | `XP_BASE 60 · GROWTH 1.10 · BREAKPOINT 20 · LINEAR 367` | **verbatim** from strength |

### Cardio tier table — VO₂max → percentile → tier `[0,70]`
ACSM / Cooper Institute normative VO₂max (mL·kg⁻¹·min⁻¹) by **sex × age decade**
(percentiles 5/25/50/75/90/95), interpolated to a percentile, then mapped to the
`[0,70]` tier scale (anchors: pct 5→tier 5, 50→25, 75→37, 90→50, 95→60, 99→68).
The ~15–20% male/female gap and the ~8–10%/decade age decline are **baked into
separate tables** (not a single multiplier), so an older or female user is scored
against their own demographic — a 55-yo at the 75th percentile ranks the same
tier as a 25-yo at the 75th. Full table in `tasks/cardio-xp-simulation.py`
`_VO2_NORMS`.

### Intensity ladder (why a stroll scores ~nothing)
| %VO₂max | `intensity_mult` | Zone |
|---|---|---|
| 40% | 0.15 | stroll — near-maintenance |
| 50% | 0.35 | moderate floor |
| 62% | 0.59 | easy |
| 70% | 0.75 | tempo |
| 80% | 0.95 | sub-threshold |
| 88% | 1.14 | threshold |
| 95% | 1.35 | VO₂max intervals |

---

## 4. Science anchors (citations)

| Parameter | Grounded in |
|---|---|
| Tier bands (VO₂max norms) | **Cooper Institute / ACSM Guidelines 11th ed.** percentile tables (>80k treadmill tests) |
| Saturating progression curve | **Bacon et al. 2013** (PLoS ONE, +0.51 L·min⁻¹, ~+13–15%); **HERITAGE / Bouchard 1999** (genetic ceiling, ±1.0 L·min⁻¹ spread); **Montero & Lundby 2017** (dose eliminates non-responders) |
| Intensity dominance + ~50% floor | **Wenger & Bell 1986** (Sports Med 3:346 — 90–100% VO₂max = max-gain band) |
| MET-minutes currency + weekly anchors | **ACSM 2024 Adult Compendium**; **WHO 2020** (500–1000 MET-min/wk; elite ~10×) |
| Detraining (Vitality decay) | **Coyle et al.** (−7%/12 days, asymptotic) |
| Modality normalization | CPET comparison studies (treadmill ~7–12% > cycle) |
| 1 MET = 3.5 mL O₂·kg⁻¹·min⁻¹ | ACSM definition |

Full source list + per-number confidence notes are in the research brief
appended to the PR that introduces this file. Two values are flagged as
*engineering choices to tune, not physiological constants*: the exact
intensity-multiplier ladder and the ~50% VO₂max threshold (defensible from
Wenger & Bell's qualitative findings, not a single published cutoff).

---

## 5. 12-persona balance panel — v1 DRAFT (12/12 PASS)

`python tasks/cardio-xp-simulation.py --persona-panel`. Bands are an independent
product/design call on "what rank this profile *should* be," derived from the
persona's VO₂max percentile (capacity), not fit to the model output.

| Persona | Sex/Age | VO₂ start→wk12 | capacity tier | wk12 rank | Target band | Verdict |
|---|---|---|---|---|---|---|
| Couch-to-5K Beginner (walk+jog) | M/30 | 30.0→31.7 | 11.7 | 11 | 10–22 | PASS |
| Recreational Jogger | M/35 | 42.0→44.7 | 29.0 | 20 | 15–30 | PASS |
| Committed Runner | M/32 | 52.0→59.3 | 58.5 | 44 | 38–52 | PASS |
| HIIT Enthusiast | F/28 | 38.0→43.7 | 35.2 | 33 | 24–38 | PASS |
| Committed Cyclist | M/40 | 46.0→53.1 | 52.8 | 42 | 30–46 | PASS |
| Female Recreational Runner | F/30 | 36.0→38.2 | 42.1 | 22 | 15–32 | PASS |
| Older Runner | M/55 | 38.0→39.6 | 36.8 | 23 | 22–40 | PASS |
| **Daily Walker** (un-farmable gate) | F/45 | 26.0→28.8 | 29.3 | 14 | 8–22 | PASS |
| **Reformed Runner Now Only Walks** (worthless-when-fit gate) | M/40 | 54.0→54.1 | 55.6 | 7 | 1–10 | PASS |
| **Fit Newcomer** (capacity-honored gate) | M/27 | 64.0→66.4 | 60.1 | 45 | 40–60 | PASS |
| Elite Endurance | M/26 | 72.0→79.2 | 65.5 | 60 | 56–72 | PASS |
| **Easy-Miles Marathoner** (intensity gate) | M/38 | 50.0→56.3 | 49.6 | 39 | 34–50 | PASS |

> "capacity tier" = the percentile tier of the user's *standing* VO₂max (their
> actual fitness). The **rank** comes from *demonstrated* performance, so rank ≤
> capacity until the user demonstrates that capacity at intensity.

### Why the four bold personas are load-bearing
- **Daily Walker** — 6×/wk, 45–60 min, brisk walk (~3.8 MET ≈ 51% VO₂max at
  start). Underlying VO₂ improves modestly (26→28.8, real physiology) but the
  walk *demonstrates* only ~15 mL/kg/min → rank lands at **14** and can never
  reach elite. All that volume is capped by what walking demonstrates.
- **Reformed Runner Now Only Walks** — VO₂ 54 (genuinely fit) but now ONLY walks.
  The walk is ~25% of *his* VO₂max → below threshold → ~zero stimulus, and it
  demonstrates ~walking fitness → tier ~5 → no burst → rank **7**. **The same
  activity is judged by physiology, not its label** — walking is worthless for
  the stat even for the fit. (His Vitality would also decay — Coyle.)
- **Fit Newcomer** — VO₂ 64, just started logging, and *demonstrates* it with
  intervals + threshold runs → high demonstrated tier → `tier_diff_mult` bursts →
  rank **45** fast. Real fitness recognized once *shown* — the cardio "Diego."
- **Easy-Miles Marathoner** — 5×/wk, mostly easy, ~420 min/wk. Easy runs
  under-demonstrate, so rank converges to **39** (his hard tempo sets the tier),
  *not* to his elite volume. Intensity-honest: you rank for what you demonstrate.

---

## 6. Open design decisions (resolve before this becomes a phase)

1. **Walking generosity — RESOLVED by the demonstrated-performance model** (kept
   here as the rationale of record). Walking now ranks low for everyone (walker
   14, fit-ex-runner-who-walks 7) because the rank credits *demonstrated* VO₂,
   and a walk demonstrates ~15 mL/kg/min. The remaining tunables are the
   `sustainable_fraction` curve and the sub-50% `intensity_mult` floor — both
   physiology-anchored (velocity-duration curve; Wenger & Bell threshold) but
   open to product tightening if walking should score even nearer zero.
2. **Estimated-VO₂max source in the real app.** The sim assumes a known VO₂max;
   the app must *estimate* it from logged data: best efforts (Cooper / 1.5-mi
   when distance+duration exist), pace-at-effort, HR-ratio (if HR), or a
   non-exercise estimate (age/sex/BMI/activity). Decide the estimation chain +
   its required logging fields (activity type + duration mandatory; distance/pace
   strongly recommended; HR optional).
3. **`CARDIO_XP_SCALE` & convergence speed.** 3.5 makes established athletes reach
   ~their tier in ~12 wk. Tune for the desired progression pace (faster = more
   immediately rewarding; slower = longer journey).
4. **Character-level weight of a cardio rank.** Does one cardio rank count exactly
   like one strength rank in the level sum (`N_active` 6→7, denominator 4), or at
   a tuned weight so a pure runner can't out-level a pure lifter (or vice-versa)?
5. **Wayfarer class dominance threshold** (the reserved cardio-dominant class).
6. **Weekly cap & modality mults** — `WEEKLY_CARDIO_CAP_METMIN` and the
   modality table are first-pass; revisit with telemetry.
7. **Detraining cadence** — confirm the Vitality `TAU_DOWN` for cardio matches
   Coyle's faster early decay (cardio detrains faster than strength).
8. **Vitality XP-gate — a design mechanic, separate from the (already-decided)
   kinetics.** Two distinct things: *(i)* the decay/rebuild **kinetics** are
   physiology and are **NOT shared** — cardio's `τ_down=3 wk` (Coyle) vs strength's
   `6 wk` (muscle memory); each stat keeps its own. *(ii)* the **XP-gate mechanic**
   (Vitality < 100% reduces XP earned) is a UX choice this baseline adds for cardio
   but which `rpg-design.md` §8 currently specs as glow-only (and strength doesn't
   apply). Decide: (a) the `VITALITY_XP_FLOOR` value (0.40 vs stricter); (b)
   whether the *mechanic* should also apply to strength for player consistency —
   if yes, it runs on strength's **own** slow-decay kinetics and **requires a fresh
   13-persona re-tune** (strength was balanced without it; do NOT retrofit blindly).

---

## 7. How to reproduce / next steps

```bash
python tasks/cardio-xp-simulation.py                 # curves + 11-persona panel
python tasks/cardio-xp-simulation.py --persona-panel # panel only
python tasks/cardio-xp-simulation.py --curves        # rank curve, tier map, ladders
python tasks/cardio-xp-simulation.py --traj walker   # week-by-week trajectory
```

**When cardio becomes an active phase** (post-launch, per `cardio-stat-plan.md`):
lock these constants, port the formula to a `record_cardio_session` SQL function
+ a Dart `CardioXpCalculator`, regenerate the fixture oracle with cardio rows,
and gate CI on 4-site parity at 1e-4 — exactly as the strength chain does. Add
the cardio data model (`cardio_sessions` table), flip cardio "active" (6→7),
wire Wayfarer + a cardio title ladder, and promote the dormant Saga row to a
real Endurance progression surface.
