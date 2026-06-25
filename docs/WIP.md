# Work In Progress

Active branch work. Removed once merged. Empty when no in-flight work exists —
backlog/parked items live in `docs/PROJECT.md` §2.

---

## ACTIVE — on-device bug investigation (2026-06-25) — ROOT CAUSES CONFIRMED

On-device test of `main` (Vitality-2 + Vitality-3 live). User reported two bugs. Test
account `user_id = e75428f6-311f-4748-ae4c-70920eb19082`. Both root-caused with live
hosted data. Bug 2 = clean code fix (queued). Bug 1 = architectural, needs a decision.

### >>> DECISION (2026-06-25): Bug 1 fix = day-base re-step (Option A, user-locked). Bug 2 fix DONE (uncommitted, tech-lead). <<<

### Phase Vitality-4 — save-time immediacy via day-base re-step (implements Bug 1 fix)

**Mechanism.** Add per-bp start-of-day base columns; change `recompute_vitality_for_user` so a part
already stepped today RE-STEPS from its stored day-base (with the now-complete 7d window) instead of
being SKIPPED. α applied once/day from the right base → no double-count, immediacy restored, sim
parity preserved. Cron stays at 03:00 (timing now irrelevant — the save always re-steps from the
base the cron snapshotted).

**Boundary inventory (from Explore):**
- EDIT site (only cadence/base-selection change): `recompute_vitality_for_user` — latest def is
  `00083_vitality_ref_peak.sql:115-226` (guard filter at `:177` + conflict guard `:224`; `targets`
  CTE `:168-178` is where skip→re-step). Callers unchanged: `save_workout` (00082:419-421),
  `vitality-nightly/index.ts:282-285`.
- NEW columns on `body_part_progress`: `vitality_ewma_day_base`, `vitality_peak_day_base`,
  `vitality_ref_peak_day_base` (numeric(14,4), nullable). Added in next migration (00085).
- Dart model: `body_part_progress.dart` `fromJson` ignores unknown keys → NO model/codegen change
  (day-base is server-internal). `rpg_repository` uses bare `.select()` → columns flow harmlessly.
- LIKELY UNCHANGED (pure step, NO formula edit): Python sim `rpg-xp-simulation.py:1169-1203`
  (already daily-from-prior-base — parity confirmed), `vitality_calculator.dart:79-91`,
  edge `stepEwma` index.ts:206-219, `rpg_strength_vitality_mult` 00084:41-55, fixture oracle +
  rpg_xp_fixtures.json.
- MUST-FLIP (contract framing; numbers may survive since re-step-from-same-base w/ same window is
  idempotent): integration `rpg_vitality_nightly_test.dart:690-696` (first-writer-wins) + `:547-553`
  (no double-step); pgTAP `vitality_ref_peak_test.sql:179-195` block (c). Re-frame "guard no-op" →
  "re-step from day base."
- NEW regression test (the actual bug): cron steps part at 03:00, THEN a save the same day with the
  session's volume in the window → the part's ewma MUST step UP (before≠after). This is the case the
  current code can't produce.
- Downstream beneficiary: `conditioning_charge.dart` `alreadyChargedToday` (`:95-98`) now rarely
  fires for post-cron saves → per-bp gains render. No code change, but verify the beat shows gains.

**Implementation checklist:**
- [x] New migration 00085: ADD 3 day-base columns (nullable) + CREATE OR REPLACE
      `recompute_vitality_for_user` with re-step-from-base logic. Applied locally; SQL parses + runs.
- [x] Update pgTAP `vitality_ref_peak_test.sql` block (c) framing + ADD block (e) re-step-up test.
      plan(10)→plan(13). All 13 ok locally.
- [x] Update integration `rpg_vitality_nightly_test.dart` (idempotency + first-writer tests) framing
      + ADD the cron-then-save-steps-up regression test. 15/15 green locally (edge runtime live).
- [x] Confirmed NO Python sim / fixture / Dart calculator / edge stepEwma formula change — the step
      math is byte-identical; only the BASE the step reads changed. Parity preserved.
- [x] Verified Dart model ignores the new columns (no `disallowUnrecognizedKeys`; no codegen needed).
      `dart analyze --fatal-infos` clean.

### Bug 1 — chest "CONDICIONAMENTO MANTIDO" — ROOT CAUSE: nightly cron pre-empts save-time recompute
- **Confirmed architectural root cause.** The `vitality-nightly` cron is scheduled at **03:00 UTC
  daily** (migration 00042 `vitality_nightly_03utc`) and processes ~every active user, calling
  `recompute_vitality_for_user(user, NULL)` → steps + stamps `last_vitality_date = today` for ALL
  body parts. When the user trains later that day, `save_workout`'s in-txn
  `recompute_vitality_for_user(user, touched_bps)` is **fully guard-blocked** by the per-bp
  `WHERE last_vitality_date IS DISTINCT FROM v_today` filter → the EWMA does NOT step → the
  just-finished session contributes nothing to the conditioning charge → chest reads "mantido".
- **Vitality-2 save-time immediacy is dead-on-arrival** for anyone training after 03:00 UTC — i.e.
  nearly everyone, and ALWAYS for Brazil (UTC−3, cron fires at 00:00 local before the day's training).
- Live proof: this user's `body_part_progress` shows back/legs `updated_at=03:00:03` (cron-only) and
  chest/shoulders/arms/core/cardio `updated_at=12:32:56` (the push session — but that updated_at is
  the XP reversal/re-earn, NOT a vitality step); ALL parts `last_vitality_date=2026-06-25`. chest
  `ewma=73.18` was computed by the 03:00 cron; the 12:32 push stepped zero vitality.
- Secondary (minor) display aspect: when a session MIXES guard-blocked parts with genuinely-stepped
  parts, the blocked parts render "MANTIDO" (held) rather than the honest "já carregado hoje".
  Becomes moot for trained parts once the cron stops pre-empting.
- **Fix needs a decision (see below).** Options: (C) reschedule cron to end-of-UTC-day so saves win
  the day (cheap, fixes the reported case, improves sim parity — guard is already first-writer-wins);
  (A) day-base re-step: store start-of-day ewma/ref_peak, let the save recompute today's tick from
  that base with the now-complete 7d window (fully correct + timezone-independent + handles
  twice-a-day, but new column + RPC rework + Python-sim parity + fixtures + integration tests).

### Bug 2 — routine seeds 0kg instead of last-lifted — ROOT CAUSE: PostgREST parent-row ordering
- **Confirmed code bug** (not the routine target — the "Push Day" / "Dia de Empurrar" default
  template id `945880a1` has ALL `target_weight = null`, so the seed `re.targetWeight ?? prev?.weight
  ?? 0` correctly falls through to last-lifted).
- `getLastWorkoutSets` (`workout_repository.dart:497`) uses
  `.order('finished_at', referencedTable:'workouts', ascending:false)` to order the TOP-LEVEL
  `workout_exercises` rows, then dedups "first per exercise" via a `seen` set. **But PostgREST orders
  the EMBEDDED (to-one) `workouts` resource, NOT the parent rows** → parent rows come back in
  PK/insertion order → the dedup picks an ARBITRARY old session.
- Live proof: replaying the query for bench `8b0f72d3` returns row[0] = **2026-04-06 @ 0kg**; the real
  most-recent is row[33] = **06-24 @ 60kg**. Seed served 0kg (user then re-typed → persisted 10kg).
- **Fix (minimal, correct):** sort the returned rows by `workouts.finished_at` DESC client-side BEFORE
  the `seen` dedup — `finished_at` is already fetched per row (`row['workouts']['finished_at']`). No
  query restructuring. Add a unit/widget test pinning "most-recent session wins" with rows returned
  in non-sorted order (the regression the current code can't catch). TDD via tech-lead.

---

## DONE this arc (for context)
- **Phase Vitality-2** (#406) — per-bp conditioning rune strip + B2 cinematic charge fuse + decaying
  `vitality_ref_peak`; live on hosted.
- **Phase Vitality-3** (#408) — strength XP vitality gate (`vmult=0.50+0.50·clamp(ewma/ref_peak)`,
  throttle-only) + sim recalibration + anti-cheese invariant fix; migration 00084 live + smoke-verified.
- **Phase 39 (Feel-Good/Retention)** (#410) — SPEC'D (design locked): photo-hero share reframe (dual
  Bestiary + Stats modes), Charge Ring / comeback / Rest Validation surfaces. Roadmap renumbered
  (Quest→40, Social→41). Docs: `bestiary-spec.md`, `bestiary-catalog.md`, `phase-39*-mockups.html`.
  Not built — Build Slice 1 (Bestiary resolver + share toggle, server-free) is the queued next build.
