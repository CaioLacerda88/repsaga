# Cardio Stat — Design Plan & Blast-Radius Analysis

> Status: **ANALYSIS / NOT SCHEDULED.** Decision input for a future phase. Three
> parallel investigations (codebase blast radius · cardio science · RPG-thesis &
> market) fed this doc. Nothing here is built. See "Open decisions" before acting.
>
> **Formula refined + balance-simulated** (the cardio analogue of the Phase 29
> strength calibration): a v1 cardio XP formula now passes a **14-persona** balance
> panel — including the strength→cardio cross-contribution (§2.5). Source of truth
> `tasks/cardio-xp-simulation.py`; calibration writeup + constants + science
> citations in **`docs/cardio-balance-baseline.md`**.

---

## 0. TL;DR

| Question you asked | Answer |
|---|---|
| **Does cardio need separate science research to be accurate?** | **Yes — unavoidably.** Strength scoring is *load* (weight×reps→1RM tiers); cardio is *rate × time* (energy turnover). They are dimensionally incompatible — cardio cannot reuse the strength tier tables. Recommended basis: **MET-minutes** (ACSM Compendium) + a per-user estimated-VO₂max tier multiplier. |
| **How does it impact the RPG formula?** | Cardio **cannot** plug into the existing 11-multiplier strength chain (`record_session_xp_batch`). It needs a **parallel cardio-XP function** with its own inputs and its own calibration baseline (a Phase-29-sized effort). The character-level math was *pre-designed* to append cardio additively (`N_active` 6→7); the class system has a reserved **Wayfarer** slot; `xp_events` already has `cardio_session`/`hr_zone`/`kcal` event types. |
| **Does it fit the thesis ("RPG never decouples from real lifts")?** | **Extends it, conditionally.** The veto killed RPE because RPE is *subjective*. Cardio metrics (pace/distance/duration/HR) are *objective*. The condition: the earning path must be anchored to objective session data — never a "I did 30 min of cardio" free-text. |
| **Does lifting earn cardio XP too?** | **Yes — one-directionally, and it was the missing piece.** Resistance training is a real (smaller, density-dependent) CRF stimulus, so a strength session earns cardio XP through the *same* MET-minutes pipeline. But the credit flows **strength → cardio only, never cardio → strength** — the interference effect is directional (Wilson 2012: endurance impairs strength; strength doesn't impair aerobic gains). Heavy long-rest lifting demonstrates ~walking-level VO₂ → ~0 cardio rank (un-farmable); high-density metcons earn real, sub-runner credit. No new mechanism — the demonstrated-VO₂ gate sorts it for free. See **§2.5**. |
| **Then does running earn a *strength* rank (running→legs)?** | **No — structurally, not as a tuning choice.** Running/cycling *can* build some leg tissue (mostly in the untrained; sprints/hills more than jogging), but specificity caps it at "strong enough to run," never a higher 1RM — and it fades with training (interference). The strength rank credits *demonstrated load* (weight×reps→1RM); a run demonstrates none, so it scores zero **by construction** — the exact mirror of walking earning ~0 cardio rank. The one save-gate fix (§1) seals both directions at once. See **§2.6**. |
| **Recommended shape** | A **separate parallel "Endurance/Cardio" track** (not a 7th strength body-part, not woven into legs). The `docs/rpg-design.md` spec already chose this; the schema already supports it. |
| **When** | **Post-launch** (the spec's "Phase 18b / v2 conditioning track"). Not a launch blocker. Do **not** pre-build before launch. One launch-adjacent decision: keep or hide the existing "Cardio — coming v2" teaser row (it's a promise). |

---

## 1. Current state — how cardio flows *today*

**Verdict: schema-ready but mechanically dormant — and the live save-path will *mis-attribute* a cardio set if one is ever logged with reps.**

Cardio is wired into the *shape* of the system but connected to nothing meaningful:

- `BodyPart.cardio` exists in the Dart enum (`lib/features/rpg/models/body_part.dart:12`), the SQL `muscle_group` enum (`00013`), the `body_part_progress.body_part` CHECK list (`00040:167`), and `xp_events.event_type` accepts `'cardio_session' | 'hr_zone' | 'kcal'` (`00040:117`).
- 8 default cardio exercises exist (Treadmill, Rowing, Bike, Jump Rope, Elliptical in `00014`; assault bike, sled push/drag in `00055`), each carrying `xp_attribution = {"cardio":1.00}`.
- **But** cardio is deliberately excluded from `activeBodyParts` (the 6: chest/back/legs/shoulders/arms/core — `body_part.dart:50`) and from the `character_state` view's `WHERE body_part IN (...)` filter (`00040:321`). So cardio never contributes to Character Level, Class, or Titles. The Saga screen renders the 6 + a hardcoded `DormantCardioRow` ("coming in v2").

### ⚠️ Latent bug (fix regardless of whether the full feature ships)
Both XP RPCs (`record_set_xp`, `record_session_xp_batch` in `00065`) gate sets on `reps IS NOT NULL AND reps >= 1`, then run the **weight×reps** formula over **any** attribution key, *including* `cardio` (`WHEN 'cardio' THEN 7`, `00065:1439`). A treadmill set logged with `weight=0, reps≥1` today would: pass the gate → earn the `volume_load = max(1.0, 0×reps) = 1.0` floor → and **write a real `cardio` row into `body_part_progress`** that is invisible on the Saga screen but silently present in the DB. In normal use cardio earns ~nothing and is invisible, but this is a real correctness gap. **Recommendation: branch the save gate on `muscle_group`/`event_type` so cardio is either cleanly ignored (pre-feature) or routed to the cardio path (post-feature) — never silently fed into the strength formula.**

### No cardio data model
A "set" records only `(weight, reps, rpe, set_type, is_completed, notes)` (`exercise_set.dart:14-37`). A workout records only session-level `duration_seconds, started_at, finished_at` (`workout.dart:14-17`). **There is no per-set/per-entry distance, pace, speed, incline, HR, or duration column anywhere.** To log cardio meaningfully you must add, at minimum, **(distance OR duration) + intensity (pace/HR/RPE)**.

---

## 2. The science — why cardio needs its own model

**Strength and cardio are physiologically and metrically distinct and cannot share a scoring model:**

1. **Load vs. rate.** A 1RM is a near-instantaneous peak force (neuromuscular + structural). VO₂max is a *flux* — mL O₂·kg⁻¹·**min⁻¹** — cardiac output × capillarity × mitochondria. One is load; the other is rate × duration.
2. **Duration is load-bearing for cardio, irrelevant for a 1RM.** A 1RM doesn't care if it took 2 s or 4 s. Cardio stimulus is *intrinsically* intensity × time. The strength formula has no time axis.
3. **No weight to bucket.** Strength tiers scale with absolute load relative to bodyweight (2× BW squat = elite). Cardio "elite" is a VO₂max threshold (~60 mL/kg/min) and pace-at-effort. Plugging weight×reps into cardio is scientifically indefensible.

### Recommended cardio-XP basis: MET-minutes + VO₂max overlay
**MET-minutes** (ACSM 2024 Adult Compendium of Physical Activities) is the only metric that is (a) lab-anchored, (b) cross-modality on one scale, and (c) computable from exactly what a manual logger has.

```
Session stimulus  = MET(activity, pace?) × duration_min      → MET-minutes
Cardio XP         = MET-minutes × intensity/tier multiplier
```

- **Required inputs:** activity type (→ ACSM MET value) + duration (min).
- **Optional sharpeners:** distance/pace (→ replace table-average MET with a pace-derived MET via the ACSM running equation `VO₂ = 0.2·speed + 0.9·speed·grade + 3.5`); RPE (intensity fallback, à la Strava); HR (toward TRIMP-grade internal load — never mandatory).
- **Tier multiplier** = the session's intensity relative to the user's **estimated VO₂max** (a sprint at 90% VO₂max earns more per minute than a stroll at 35%). This is the cardio analogue of the strength tier and prevents the "accumulation, not progression" failure mode.
- **Progression overlay:** maintain a rolling **estimated VO₂max** from best logged efforts (Cooper / 1.5-mi formulas when distance+duration exist; non-exercise/HR-ratio trend otherwise) and surface **pace-at-equal-effort improving over time** as the "you're getting fitter" headline.

**Worked example:** 70 kg user, 30-min run at ~6 mph → ACSM MET ≈ 9.8 → **294 MET-min** (≈343 kcal). With pace logged, the ACSM equation refines it to ~10.2 MET → 306 MET-min (~4% sharper).

**Caveats:** MET tables are population averages (the VO₂max tier multiplier corrects per-user); self-reported activity type is coarse (logging pace collapses the error band); no HR = external/estimated load, not measured physiological response; field VO₂max estimates are *within-protocol trend only*, never an absolute lab number.

### 2.5 Strength → cardio cross-contribution (the directional credit) — **was missing; now specified**

**A strength session is itself a cardiorespiratory stimulus, and the cardio track must credit it — one-directionally.** This was the gap: the original plan modeled the two tracks as fully orthogonal (cardio earned *only* from cardio modalities), which is science-wrong and leaves a genuinely-conditioned metcon athlete invisible on the cardio rail.

**The science says credit it, but asymmetrically:**

1. **Resistance training produces real, intensity/density-dependent CRF gains.** Resistance *circuit*-based training improves VO₂max ~**6.3%** (45-study meta-analysis); traditional resistance training alone adds ~**+1.9 mL·kg⁻¹·min⁻¹** in untrained/older adults and ≈0 in the already-trained. So the contribution is real but smaller than dedicated aerobic work, and it *scales with the session's metabolic density* (short-rest circuits ≫ heavy long-rest singles).
2. **The interference effect is directional** (Wilson et al. 2012 meta-analysis, 21 studies / 422 effect sizes): endurance training measurably *impairs* strength/hypertrophy/power (frequency- and duration-dependent; running worse than cycling), **but "aerobic-capacity gains are not compromised by concurrent strength training."** Lifting helps (a little) cardio; cardio hurts strength. **This is the scientific keystone for the whole cross-stat policy: credit flows strength → cardio, NEVER cardio → strength.** It is *why* running must never feed a legs/strength rank (§3 Option C is not just a grammar choice — it's the physiologically-correct direction), and why crediting lifting toward cardio is not the symmetric mistake.

**The elegant part — no new mechanism.** A resistance session enters the *same* MET-minutes → intensity-gate → demonstrated-VO₂-tier pipeline as any fixed-MET activity (a `kind='abs'` session, like walking). The existing honesty gate then sorts it correctly for free:

| Session | Session-avg MET | Demonstrates | Cardio credit |
|---|---|---|---|
| Heavy powerlifting (long rests pull the mean down) | ~3.5–4 | ~walking-level VO₂ | **~zero** — you can't farm cardio rank by lifting heavy (correct: heavy RT ≈ 0 VO₂max gain) |
| High-density circuit / metcon (short rest) | ~7–8 | moderate VO₂ | **real but sub-runner** (correct: metcons genuinely build CRF) |

Validated in the sim: a **Pure Powerlifter lands cardio rank 8** (band 1–10, VO₂ barely moves); a **CrossFit/Metcon athlete lands rank 18** (band 12–30, VO₂ +5.2% ≈ the literature), below a dedicated runner of equal VO₂. The 12 original personas are unchanged. Panel is now **14/14**.

**Two design decisions this surfaces (both defensible, intended):**
- **One session earns on BOTH tracks** — a metcon banks strength XP (weight×reps) *and* cardio XP (MET-min). This is not double-counting one adaptation; it's crediting two distinct real outcomes of one session (it built some strength *and* some CRF). Intended.
- **Session MET must be estimated, never declared** — to stay un-farmable, the resistance-session MET comes from *work density* (inter-set rest, rep range, set volume vs. session wall-clock — all already logged or derivable), mapped to an ACSM MET band (light/moderate ~3.5, vigorous free-weight ~5.0, circuit-minimal-rest ~8.0). "I did a hard workout" never sets it. This is the same estimate-don't-ask philosophy as the est-VO₂max source (§8).

*(Sources: resistance-circuit-training VO₂max meta-analysis [Ramos-Campo et al., PMC8145598]; RT-for-CRF in older adults [Oxford, Age & Ageing afac143]; concurrent-training directional interference [Wilson et al. 2012, JSCR]; ACSM 2024 Compendium RT MET codes. Full citations in `cardio-balance-baseline.md` §8.)*

### 2.6 Cardio → strength: why the credit does NOT flow back (the running→legs question)

The mirror question: running/cycling load the legs — should a hard run earn a *strength* rank? **No — and it's a structural guarantee, not a tuning choice.** But the honest answer is more nuanced than "running does nothing for your legs," so here's the full reasoning:

**The science (running/cycling *can* build some leg tissue — but not what a strength rank measures):**
1. **Specificity caps it at "strong enough to run," not a higher 1RM.** A sedentary person's legs do get stronger from a running program — *only strong enough to support running*; you would no more expect running to raise a 1RM squat than expect heavy squats to improve swimming (practitioner consensus: Barbell Medicine, Stronger by Science). High-intensity work (sprints, hills, hard cycling intervals) *can* add real quad/hamstring cross-sectional area — one cited protocol found 4×30 s bike sprints ≈ 4×10–12 leg-press for 5-week lower-body strength — but cycling hypertrophy is localized, eccentric-light, and needs enormous volume; a HIIT meta-analysis finds only modest strength/mass effects.
2. **The effect is real mainly in the untrained and vanishes with training.** Concurrent-training meta-analysis by training status (PMC8053170): in *untrained* people endurance does **not** impair 1RM leg gains (ES = 0.03, p = 0.87) and beginners can even gain some strength from endurance; in *trained* people the directional interference effect suppresses strength (Wilson 2012). So any running→legs strength credit would be a transient beginner artifact, not a durable signal.

**Why it must still earn zero strength rank — the same gate that handles walking, mirrored:**
- **The strength rank credits *demonstrated load* (weight×reps → 1RM tier). A run demonstrates no quantifiable external load** — there is no bar, no weight×reps — so by *construction* it earns zero strength XP. This is exactly symmetric to walking earning ~zero cardio rank: each rank credits only what is **demonstrated in its own currency**. A dense lifting circuit *inherently sustains* an elevated VO₂ (so it demonstrates cardio performance → credited on cardio, §2.5); a run *never produces* a maximal external load (so it demonstrates nothing in the strength currency → not credited). Not a double standard — cardiorespiratory flux is a property of *any* sustained session; peak demonstrated load is a property of *only* lifting.
- **The real leg-strength base a beginner builds from sprints only "counts" once they demonstrate it under a bar** — precisely as walking's VO₂ base only counts once demonstrated at intensity. The system's demonstrated-performance gate already encodes this with zero special-casing.
- **Crediting it would be farmable and would corrupt rank meaning** — a marathoner who never squats showing a high "legs rank" reads to every lifter as "heavy squatter." That is the auto-fail dilution the thesis forbids (and the §3 Option C rejection).

**Implementation consequence: nothing to build, and one fix protects both directions.** No strength-formula change, no simulation needed — the protection is *structural* (the weight×reps formula can't score a load-less run). The single save-gate fix already flagged in §1 (branch on `muscle_group`/`event_type` so a cardio entry can't enter the weight×reps path) is what *enforces* it: it simultaneously stops cardio from mis-attributing into strength **and** stops any "run logged with reps" from farming a legs rank. One gate, both cross-directions sealed.

**Consumer grounding:** every high-fidelity model (Garmin Training Load, Whoop Strain, Strava Relative Effort) leans on continuous HR; the only models that degrade gracefully to no-sensor input are MET/active-energy (Apple's rings) and manual RPE (Strava's fallback). A manual logger must therefore be MET-based with optional RPE/pace sharpeners.

*(Sources: ACSM 2024 Compendium; Cooper/1.5-mi/Rockport VO₂max field formulas; Uth–Sørensen HR-ratio; ACSM metabolic equations; Banister TRIMP; TrainingPeaks rTSS; Strava/Garmin/Whoop/Apple scoring docs. Full citations in the research notes appended to the PR.)*

---

## 3. RPG-thesis analysis

**Verdict: EXTENDS the thesis, conditionally.** The thesis veto ("the RPG layer never decouples from real lifts") killed RPE specifically because **RPE is subjective** — unverifiable, inflatable without training harder. Cardio metrics — pace, distance, duration, HR zone — are **objective**: a 5 km at 5:00/km in HR zone 4 either happened or it didn't. The anti-RPE logic does not apply. Critically, `docs/rpg-design.md` **already names a "future Cardio track"** (§2/§3/§16.1), pre-wires the additive character-level path ("when cardio ships, N_active becomes 7", §7), and reserves a **Wayfarer** class for cardio dominance (§9.1). This was designed in, not bolted on.

**The condition:** "extends" holds *only* if the earning input is objective and from a real session. HR-zone-weighted / MET-weighted effort gated on logged runs is thesis-safe. A free-text "did 30 min of cardio" with no verification is **Habitica territory** and would dilute the "cannot be farmed" property that defines the system. **The earning formula must carry the same rigor as the strength chain.**

### Conceptual model — pick **(B) separate parallel track**
| Option | Verdict |
|---|---|
| **(A) 7th body-part stat** | ✗ Breaks the anatomical grammar ("you level up your *body parts*"). Cardio is a systemic capacity, not a body part. Distorts class-resolution math built around 6 strength specialists. |
| **(B) Separate parallel "Endurance/Cardio" track** | ✓ **Recommended.** What the spec already specifies. Lands as a 7th `body_part_progress` row that feeds the character level *additively* (denominator stays 4), enters the class resolver at its own weight (Wayfarer), has its own title ladder + Vitality glow + earning path. A strength-only user sees a dormant "awaits your first stride" rune — invitation, not accusation. |
| **(C) Woven into existing parts (running→legs)** | ✗ **Worst option / auto-fail.** Corrupts the rank's meaning — a runner who never squats would show a "legs rank" a lifter reads as heavy squatting. Directly dilutes rank identity. **And it's the physiologically *wrong direction*:** running builds running-specific fitness, not max 1RM strength (specificity), and can *impair* trained strength (directional interference, Wilson 2012). Running demonstrates no barbell load, so it earns zero strength rank structurally — full reasoning in **§2.6**. The *reverse* credit — strength → cardio — IS science-valid and IS specified (§2.5); these are not symmetric, and the asymmetry is the whole point. |

### Dilution vs. upside
- **Risk (earning path):** if cardio XP flows from duration alone, a 60-min leisurely walk earns like a 60-min tempo run → erodes the "honest, un-farmable" property. Mitigation = intensity (MET/HR-zone) weighting, the cardio analogue of `intensity_mult`.
- **Upside (complete athlete):** a consistent lifter who also runs is *currently invisible* in RepSaga — retention risk in the other direction (Brazil's large recreational-running population — São Paulo Marathon is the largest in LatAm). Recognizing it, in its own track, is the "complete athlete" positioning without diluting strength identity.
- **Competitive gap:** no current app does per-modality parallel-track RPG progression. Strava/Apple/Zwift use a single undifferentiated XP pool (works for social/single-sport, not RPG identity); Garmin keeps cardio (VO₂max) and an emerging strength metric *deliberately separate* — the closest validation of Option B, but as wearable analytics, not RPG. The slot is unoccupied.

---

## 4. Gamification & UI design impact

> Design-level view of how cardio slots into every gamification surface and the
> UI. Code-level file inventory is §5. Backed by a UI/UX-critic design pass + a
> product-owner class/identity pass (this PR).

### 4.1 Earning layer (formula & math)
1. **New parallel earning function** — `record_cardio_session` (SQL) + Dart `CardioXpCalculator`, NOT a branch in the weight×reps chain. A **4-site parity change** (Python → fixture → Dart → SQL, 1e-4) with its own calibration baseline (`cardio-balance-baseline.md`, done — 14/14 panel). Resistance sessions feed this same function as a `kind='abs'` fixed-MET entry (§2.5) — no separate strength→cardio path.
2. **Save gate must branch** — `reps >= 1` (`00065:731,1360`) excludes cardio; route by `muscle_group='cardio'`/`event_type` to the cardio path; close the latent mis-attribution bug (§1).

### 4.2 Ranks & character level
- A **7th rank** on the shared curve (rank 5≈278 XP … 50≈14,080). `character_state` view + `rank_curve.characterLevel` go 6→7 active keys; the design pre-wired `N_active`→7. Re-validate the level formula with 7 terms (cluster `character-level-misuses-rank-fn`).
- **Character-level weight = 1:1** (a cardio rank counts like a strength rank; denominator stays 4). A cardio rank is earned on the same curve by *demonstrated* VO₂, so it represents equivalent real work — down-weighting it would assert "strength > cardio," a thesis violation of its own. Theoretical max level rises 148→172 (7×99); add a level title at 172.

### 4.3 Class system & "combined classes" (the load-bearing identity call)
Today: cosmetic, single-dominant via `argmax` over 6 + `Ascendant` (balanced prestige) + `Initiate`. **Recommended path:**
- **v2 launch → Model B "compound label":** keep the strength class (6-stat argmax) and add a **separate cardio descriptor** — `[StrengthClass] · [CardioDescriptor]`. Descriptor by cardio rank: `0`→none (dormant), `1-9` Stirring, `10-19` Conditioning, `20-39` Tempered, `≥40` Conditioned; **Wayfarer** when cardio rank > *any* single strength rank (cardio-dominant). A pure runner reads "Initiate · Wayfarer" (achievement acknowledged immediately); a lifter-who-runs reads "Pathfinder · Tempered" (identity intact, cardio as bonus track).
- **Ascendant stays 6-strength-only** (explicit). It means "balanced *across the body you built*." Folding cardio into its "within-30%-of-max" test would strip a deliberate lifter of their prestige class for not running — punitive, not descriptive (thesis: the class describes what you *are*, never shames what you aren't).
- **Phased Model C "combined classes" (post-data, NOT at launch):** once real cardio distributions exist, add 2-3 rare named prestige classes that override the compound label — e.g. **Vanguard** (character level ≥75 AND cardio rank ≥40 — the complete athlete), **Iron-Runner** (any strength rank ≥50 AND cardio rank ≥30). Inventing combined-class thresholds before population data would mis-size them.
- *Implementation:* add `Wayfarer` to `character_class.dart` + a `cardioDescriptor` resolver; the `argmax`/Ascendant strength path is **untouched** (no balance regression for lifters).

### 4.4 Titles
- **Own 13-rung cardio ladder** (kinetic/wind register, distinct from forge/iron): First Stride (5) → Pace-Forged (20) → Stride-Lord (50) → Wind-King (60) → **The Stride** (99) — matching the "The [Noun]" max-rank grammar. Lands in the existing `EarnedTitleRow`/`NextTitleRow` UI with the cardio hue.
- **Cross-build (strength × cardio):** complete the stub `iron_bound` (`Chest/Back/Legs ≥60 AND cardio ≤10` — celebratory for the committed lifter who *doesn't* run, not punitive); add **The Forged Wind** (char-level ≥75 AND cardio ≥40, the title-tier complete-athlete) and **Storm-Tempered** (any strength ≥50 AND cardio ≥50). Total titles 90 → **106**.

### 4.5 Celebrations (post-session cinematic)
- `celebration_event_builder` loops `activeBodyParts` → cardio rank-ups / title-unlocks / awakening surface automatically once cardio is "active." The cinematic fires for a **cardio-only session** (a completed workout with a cardio entry) with no change to the finish flow.
- **Cardio gets its own teal hue flood** for B2 cuts (instantly recognizable as a cardio session); **class-change cuts stay `hotViolet`** (a character-wide event, not a body-part one — teal would misread as another rank-up).
- **Net-new:** a `CardioLiftRow` for the summary panel (`30 min · 6.2 km · Zone 3` instead of `75 kg × 5`) — without it the strength `LiftRow` renders "0 kg × 0", the clearest possible bolted-on tell.

### 4.6 Saga character sheet & the cardio rune
- **7-row rail:** the hardcoded "Cardio — dormant" row becomes a real progression row. **Group it apart** from the 6 anatomical rows (a 1dp `surface2` divider + a slightly different row tint) — cardio is a *capacity*, not a body part; styling it identically = the auto-fail "7th body part." At **320 dp** the 7th row pushes the Stats/Titles nav ~one scroll lower — tolerable, not a cliff.
- **Dedicated teal-cyan hue token** (`AppColors.bodyPartCardio`) replacing the `hair` gray placeholder — used *everywhere* cardio renders (rune dot, XP bar, trend line, flood cut, title accent). This single token is what makes cardio read as first-class identity ("teal = my running") rather than bolted-on. Keep the dormant row at the *teal* color low-opacity (not gray) so awakening is an opacity lift, not a jarring hue swap.
- **Two-speed Vitality halo (top UX risk):** cardio's τ_down=3wk decays ~2× faster than strength's 6wk, so a 4-week layoff fades the averaged avatar halo *driven by cardio* even while strength conditioning is fine. Don't change the math — make it **legible**: cardio's own row-dot reads its *own* vitality state, and the stats screen states plainly "cardio conditioning decays faster (3-wk vs 6-wk)." Honesty about the mechanic is the mitigation.

### 4.7 Cardio logging surface (the single highest bolted-on risk)
Strength logging is a weight×reps set-table (`SetRow`/`ExerciseCard`). Cardio's input is structurally different (activity type + duration + optional distance/pace/RPE, no sets). **Do NOT** shoehorn it into `SetRow` with hidden columns (a "set" with no sets = reads as a bug), nor split it into a separate "cardio mode" (two apps in one nav). **Recommended:** a dedicated **`CardioEntryCard`** — same card shell / surface / typography as `ExerciseCard`, but its own grammar: an activity-type chip row + duration stepper + optional distance + an RPE chip row + the same green done-CTA. It lives in the *same* `ExerciseList` (the picker already lists the 8 cardio exercises), so strength and cardio sessions coexist natively. This is real net-new UI (widgets + models + provider wiring), not a skin.

### 4.8 Top design risks + verdict
1. **Logging surface** (high) → `CardioEntryCard`, never a deformed `SetRow`.
2. **Two-speed halo** (medium) → legibility, not math change.
3. **Wayfarer/class miscalibration** (medium) → the descriptor thresholds above; the strength argmax/Ascendant path stays untouched.

**Verdict: cardio can be first-class, not bolted-on** — the architecture was pre-wired for it (schema, `N_active` additive level, Wayfarer slot, `xp_events` polymorphism, title slot). The bet that makes it *native*: one purpose-built teal identity hue carried through every surface, the same RPG *grammar* (permanent rank, conditioning Vitality, titles, class) with a distinct cardio *vocabulary*. The anatomical "level up your body parts" identity is **not fractured** — cardio is visibly a different system that obeys the same saga rules.

---

## 5. Blast radius (layered inventory)

> "Active" gates are the highest-leverage: ~40 call sites loop `activeBodyParts`. The two single hardest points: `lib/features/rpg/models/body_part.dart` (`activeBodyParts`) and `supabase/migrations/00065_…` (formula + `reps>=1` gate + 6-part character-level filter).

**(a) DB schema + migrations** — `muscle_group` enum (`00013`), cardio exercise seeds (`00014`, `00055`), `xp_events.event_type` polymorphism (`00040:117`), `body_part_progress` CHECK (`00040:167`), `character_state` view 6-part filter (`00040:321`), cardio `xp_attribution` seeds (`00040:1920`), cardio `difficulty_mult` placeholder 0.85 (`00053`). **New:** cardio data-model columns/table + a cardio-earning migration.

**(b) SQL formula + parity** — `record_set_xp` / `record_session_xp_batch` (`00065`): the `reps>=1` gate, the `'cardio'→7` index map, the 7-wide weekly-vol arrays, the 6-part character-level recompute. Parity oracle: `tasks/rpg-xp-simulation.py`, `test/fixtures/generate_rpg_fixtures.py`, `rpg_xp_fixtures.json`. **All move together.**

**(c) Dart domain** — `body_part.dart` (`activeBodyParts`), `xp_calculator.dart` (`volumeLoad`), `implied_tier.dart` (no cardio family), `rank_curve.dart` (`characterLevel` + `_activeKeys`), `class_resolver.dart` + `character_class.dart` (no Wayfarer), `xp_distribution.dart` (cardio key "earns nothing"), `celebration_event_builder.dart`, `body_part_hues.dart` (`cardio: hair` gray), `cross_build_title_evaluator.dart` (cardio stub).

**(d) Providers/repos** — `rpg_repository.dart` (`getAllBodyPartProgress`, `getCharacterState`, `getPeakLoadPerBodyPart` cardio skip), `rpg_progress_provider.dart`, `character_sheet_provider.dart`, `class_provider.dart`, `stats_provider.dart`, weekly-plan engagement bars.

**(e) UI** — `dormant_cardio_row.dart` (the "coming v2" row → becomes a real progression row), `character_sheet_screen.dart` (6 rows + dormant), `saga_header.dart`, `vitality_table.dart`, `vitality_trend_chart.dart`, `stats_deep_dive_screen.dart`, `titles_screen.dart`, the post-session cinematic cuts (`b2_cascade_cut`, `b3_title_cut`, choreographer/controller). A new cardio-logging input surface (activity type, duration, distance/pace/HR/RPE) is **net-new UI**.

**(f) Tests** — parity fixtures (regen), integration parity tests, plus new cases for `class_resolver` / `celebration_event_builder` / `rank_curve` / `xp_distribution` under a 7th active stat; no cardio test file exists yet; new cardio-logging E2E flow.

**(g) Docs** — `rpg-design.md` §16.1 (the v2 spec to flesh out), `PROJECT.md` backlog row, **new** `cardio-balance-baseline.md` calibration doc + cluster-ledger awareness.

---

## 6. Data-model gap (must be designed first)

Logging cardio needs net-new storage. Two shapes:
- **(i) Extend `sets`/`workout_exercises`** with nullable cardio columns (`duration_seconds`, `distance_m`, `avg_hr`, `incline_pct`, `rpe`) — cheaper, but pollutes the strength row shape.
- **(ii) A dedicated `cardio_sessions` table** (`workout_id`, `exercise_id`, `duration_s`, `distance_m`, `avg_hr?`, `rpe?`, computed `met`, `met_minutes`) — cleaner separation, matches the parallel-track architecture, and is where the cardio-XP function reads from. **Recommended.**

User-facing minimum: **activity type + duration**. Recommended optional: **distance/pace** (biggest accuracy gain) and **RPE**. Wearable HR is a later integration, never required.

**Strength-session cardio MET (for the §2.5 cross-contribution) needs no new user input** — it's *derived* from data the strength side already captures: session wall-clock (`workouts.duration_seconds`), completed-set count, rep ranges, and inter-set rest (derivable from set timestamps or estimated from set-type). Map work-density → an ACSM RT MET band (≈3.5 light/moderate · ≈5.0 vigorous free-weight · ≈8.0 minimal-rest circuit) → feed the cardio pipeline as a `kind='abs'` session. The one schema touch worth considering: persist a per-session `est_met` (or the rest-density inputs) so the cardio-XP function can read it without re-deriving. **Decision needed:** whether v1 ships the strength→cardio credit (richer, more honest "complete athlete") or defers it to a v2.1 once the pure-cardio track is validated — see §8.

---

## 7. Suggested phasing (post-launch)

0. **Pre-feature hygiene (small, do anytime):** branch the save gate so cardio can't silently mis-attribute (§1 latent bug). Decide the launch teaser: keep the dormant "awaits your first stride" rune (a promise you'll keep) or hide it until ship.
1. **Cardio data model** — `cardio_sessions` table + Dart models + logging UI (type + duration + optional distance/pace/RPE).
2. **MET-minutes earning formula + calibration baseline** — ACSM MET table, pace→MET sharpener, per-user est-VO₂max tier multiplier; new `cardio-balance-baseline.md`; 4-site parity (Python/fixture/Dart/SQL). *This is the Phase-29-sized research+calibration block.* **Includes the strength→cardio cross-credit (§2.5):** route each resistance session into the same function as a work-density-derived `kind='abs'` MET entry; persist a per-session `est_met`. (If deferred per §8 #2, this sub-step slips one release — but the formula is identical, so deferring is purely a scope call, not a model change.)
3. **Wire into progression** — flip cardio "active" (6→7), character-level additive, Wayfarer class, cardio title ladder, Vitality on the cardio track, celebrations.
4. **UI** — promote the dormant row to a real Endurance progression surface; cardio rank-ups in the post-session cinematic.
5. **Parity + QA + visual-verification** per the standard pipeline.

---

## 8. Open decisions

### Resolved by the formula + design/product passes (see §4 / `cardio-balance-baseline.md`)
- **Earning rigor floor** → the demonstrated-VO₂ model already prevents duration-only farming (a walk demonstrates ~15 mL/kg/min for anyone). ✅
- **Class integration / combined classes** → Model B compound label at launch (`[StrengthClass] · [CardioDescriptor]`), phased Model C prestige classes (Vanguard / Iron-Runner) post-data. ✅ (§4.3)
- **Ascendant** → stays 6-strength-only. ✅
- **Character-level weight** → 1:1, denominator 4 unchanged. ✅
- **Wayfarer trigger** → cardio rank > any single strength rank. ✅
- **Cardio title ladder + cross-build titles** → 13-rung ladder + Iron-Bound / Forged-Wind / Storm-Tempered. ✅
- **Logging surface** → dedicated `CardioEntryCard` in the shared exercise list. ✅ (§4.7)
- **Cardio identity hue** → a new teal-cyan `AppColors.bodyPartCardio` token. ✅ (§4.6)

### Still genuinely open (need a product call before an active phase)
1. **Wearable scope:** manual-only v1, or HR/GPS (Apple Health / Google Fit / Garmin) from the start? Manual-only is thesis-sufficient; HR is a sharpener.
2. **Strength→cardio credit — v1 or v2.1?** The mechanism + science are specified and sim-validated (§2.5; 14/14 panel), and it costs no new user input (MET derived from work density). Open call: ship it with the first cardio release (richer "complete athlete" from day one; needs the per-session `est_met` derivation wired) or defer one release until the pure-cardio track is validated on real data (simpler first cut). Recommendation: **ship it** — without it a CrossFit/metcon-heavy user is wrongly invisible on cardio, the exact gap that prompted this section; the demonstrated-VO₂ gate already makes it un-farmable.
3. **Est-VO₂max source** when no distance/HR is logged — non-exercise estimate (age/sex/BMI/activity) vs. a periodic "fitness-test" entry vs. best-effort-derived.
4. **Tier-threshold calibration** — confirm the cardio VO₂max bands by sex/age against the ACSM tables on real data (engineering/calibration, the cardio analogue of the gender tier tables).
5. **`VITALITY_XP_FLOOR`** (0.40 default) and whether the Vitality XP-gate should also apply to **strength** (would need a fresh 13-persona re-tune — see `cardio-balance-baseline.md` §8).
6. **Launch teaser** — keep or hide the dormant "awaits your first stride" cardio row at launch (it's a promise).

---

## 9. Recommendation

**Post-launch, as a properly-scoped phase (the spec's Phase 18b / v2 conditioning track). Do not pre-build before launch.** The architecture is already pre-wired for the parallel-track model — this is *completing a designed slot*, not a new architectural bet — but the **earning formula is a real research + calibration effort** (MET-minutes + VO₂max tiers + 4-site parity), and shipping it under-calibrated would itself be a thesis violation (gameable or invisible). Two things are worth doing *now*, cheaply: **(a)** close the latent cardio mis-attribution bug; **(b)** make a deliberate call on the launch teaser copy. Everything else waits for a dedicated phase with the open decisions above resolved.
