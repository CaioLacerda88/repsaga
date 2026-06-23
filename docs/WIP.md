# Work In Progress

Active branch work. Removed once merged. Empty when no in-flight work exists —
backlog/parked items live in `docs/PROJECT.md` §2.

---

## Phase Vitality-2 — Per-Body-Part Conditioning Delta (post-session)

**Branch:** `feature/phase-vitality-per-bp-delta`
**Source:** on-device diagnosis 2026-06-23 (see PROJECT.md §2 "Phase Vitality-2").

**Problem (confirmed on hosted device test):** the post-session "Conditioning
charged" beat collapses all trained body parts into one aggregate `+N%`
(`ConditioningCharge` = mean of per-bp `clamp(ewma/peak)` deltas). It's unclear
to the user and structurally fragile:
1. **Aggregate dilution** — parts already at 100% (legs/cardio) contribute `+0`
   and drag the headline down (back +17 / arms +12 / core +24 read as a single "+11%").
2. **Frozen all-time-peak denominator** — `charge = ewma / peak` with `peak` the
   monotonic all-time max; detrained users sit at 2–7% and small steps round to
   0% → beat silently hides (the original "no charge shown" report).
3. **Once-per-day guard** — `last_vitality_date` lets vitality step at most once
   per UTC day; 2nd+ same-day sessions (or after the 3am cron) → delta 0 → no beat.

**Diagnosis evidence:** instrumented `post_session_controller` + controlled
`last_vitality_date` reset proved the client wiring is CORRECT (post-save snapshot
is fresh — no stale-read bug). The no-show is the `shouldRender` gate behaving as
coded on a sub-1% aggregate delta. So this is a design problem, not a defect.

**Directive (user, 2026-06-23):** replace the single aggregate with a
**per-body-part delta** so the user can see what each trained part gained. Resolve
the dilution + frozen-peak + guard wrinkles as part of the redesign.

### Locked decisions (2026-06-23)
- **Scope: FULL FIX** (user choice) — per-bp display + rolling-peak denominator + guard surfacing.
- **Metric (per-bp delta):** gain = `new_ewma − old_ewma`, denominator = **rolling 90-day max
  of that bp's `vitality_ewma`**, computed at debrief time from `xp_events` history. Stored
  `vitality_peak` and the Saga screen are UNTOUCHED (Saga keeps "at career best" semantics).
  Fixes detrained-user invisibility (rolling max decays, so a comeback session reads big).
- **Guard:** keep the once-per-day `last_vitality_date` step (EWMA integrity). Change
  `recompute_vitality_for_user` `void → int` (count of stepped bps) via a forward migration so
  the client distinguishes "stepped now" from "already charged today" → show an explicit
  "already charged today" state instead of hiding the beat.
- **Render gate:** replace `deltaPercentInt > 0` with "any trained bp has charge data" — an
  all-maxed session still renders ("everything stayed charged"), never silently hidden.
- **Visual:** "rune charge strip" — per-part hue glyph + label + state-aware delta. NOT a per-bp
  bar stack (rejected as card-soup in the original round). Maxed parts → full rune + HELD word,
  never `+0`. Delta-ordered, ~4 rows + "+N more recharged".
- **OPEN (mockup decides):** maxed-part treatment (inline HELD rows vs "N at peak" footer);
  whether the eyebrow carries a `N charged` count.

### Design LOCKED (user-approved mockup `docs/phase-vitality2-mockups.html`)
- Summary: per-bp rune strip · inline "MÁX" held rows · bare eyebrow · delta-ordered · 4 rows + "+N more" ·
  all-maxed still renders · "já carregado hoje" guard state.
- Cinematic: charge rune **fused onto the B2 hero beat** (rune end-cap on the rank bar, same hue/beat;
  MÁX = pre-lit/held; cascade = hero row only). Single charge source feeds summary + B2 (no drift).
- Safety: fill-only never drains, past-tense descriptive copy, NO decay countdown (Phase-39/ToS aligned).

### Refined decisions (post-boundary-inventory 2026-06-23)
- **Denominator = additive `vitality_ref_peak` column** (decaying reference peak), NOT debrief-time xp_events
  replay (no historical EWMA exists to read). Maintained in `recompute_vitality_for_user` AND mirrored in
  `supabase/functions/vitality-nightly/index.ts`. `vitality_peak`/Saga UNTOUCHED. charge = `clamp(ewma/ref_peak)`.
  tech-lead designs decay constant + backfill (goal: detrained comeback reads meaningfully; not all pinned 100%).
- **Guard surfaced client-side** via `before.ewma == after.ewma` (exact) → "já carregado hoje". NO RPC
  `void→int` change (avoids DROP/recreate + the pgTAP gap). Keeps `recompute_vitality_for_user` signature stable.
- **Render gate** = "any trained bp has charge data" (replaces `deltaPercentInt > 0`).

### Boundary inventory (Explore, 2026-06-23) — implementation must touch
- **B1 RPC:** `recompute_vitality_for_user` (00082:96) gains ref_peak maintenance (CREATE OR REPLACE ok — no
  signature change). Mirror in `vitality-nightly/index.ts:239`. save_workout PERFORM unaffected. Add a pgTAP
  test (currently ZERO coverage). Integration `rpg_vitality_nightly_test.dart` asserts rows — extend for ref_peak.
- **B2 model:** `ConditioningCharge` (conditioning_charge.dart) → per-bp shape. Readers: controller :179, state
  :155 (freezed), mission_debrief_section :296, conditioning_charge_bar.dart. Tests: conditioning_charge_test
  (full), mission_debrief_section_test :961, conditioning_charge_bar_test. l10n keys (en+pt) + arb_completeness :116.
- **B3 cut classes:** `B2SingleBpCut`/`B2SequentialDominant`/`Secondary`/`B2CascadeCut`+`CascadeRow`/
  `B2ElevatedRankUpCut` (choreographer 40-129) gain `chargeFractionBefore/After`; built in `_appendBeat2` :314 /
  `_buildCascadeCut` :427 / controller :190,:312. Renderers: b2_bp_tally_cut, b2_cascade_cut, b2_elevated_cut,
  post_session_screen :502-565. Tests: choreographer_test (cut-type pins — fixtures break on required fields →
  default the new fields), b2_cascade_cut_test, **regen `post_session_summary_panel_golden_test`**.
- **B4 plumbing:** per-bp charge derivable in controller :164-183 (has before+after ewma/peak/ref_peak). Model
  `body_part_progress.dart` gains `vitalityRefPeak` (parsed from `select()`); schema 00040:178.

### Build stages (one feature branch, staged commits → one PR)
- [x] **S1 — backend:** migration `00083_vitality_ref_peak.sql` (add `vitality_ref_peak numeric(14,4)` +
      ref_peak maintenance in `recompute_vitality_for_user` via `GREATEST(new_ewma, prior_ref_peak * decay)`,
      decay = `exp(-ln2/21)` ≈ 0.9675/day = 21-day half-life; backfill `ref_peak = vitality_peak`
      zero-discontinuity) + mirror `REF_PEAK_DECAY` + `stepEwma` refPeak in `vitality-nightly/index.ts` +
      `BodyPartProgress.vitalityRefPeak` (model + default factory + 8 test helpers) + NEW pgTAP
      `vitality_ref_peak_test.sql` (10 assertions, was zero coverage) + extended integration test (decay +
      nightly/save parity) + model fromJson unit test. analyze clean; unit 512 pass; pgTAP 10/10; integration
      14/14; backfill 196/196 verified on LOCAL. NOT pushed to hosted (post-merge step).
- [ ] **S2 — domain:** rewrite `ConditioningCharge` → per-bp (charge from ref_peak, MÁX detection, guard
      flag, "has charge data" gate). Rewrite `conditioning_charge_test`. Unit-tested.
- [ ] **S3 — summary UI:** rune-strip widget (replaces `conditioning_charge_bar`) — per-bp rows, inline MÁX,
      bare eyebrow, +N more, all-maxed, guard state. l10n en+pt. Widget tests. Wire `mission_debrief_section`.
- [ ] **S4 — cinematic:** B2 cut classes gain `chargeFraction*` (defaulted) + rune end-cap render on
      b2_bp_tally/elevated (hero only on cascade) + controller sources from snapshot. Choreographer/cut tests +
      golden regen.
- [ ] Reviewer → QA → visual verification (320/360/412dp, summary + B2 cut) → merge → `db push` migration.

_Building — S1 next._
