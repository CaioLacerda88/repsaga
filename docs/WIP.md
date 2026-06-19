# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Vitality immediacy — save-time recompute + "Conditioning charged" debrief

**Source:** user-approved phase (memory `project_queued_post_drag_phases.md`). Today vitality
updates ONLY overnight (`vitality-nightly` edge fn); the save path never touches it, so the runes
lag a day behind XP/rank. Make vitality recompute AT SAVE TIME for touched body parts, guarded so
the nightly job can't double-count, + a post-session debrief beat. Thesis-safe (same real lift,
surfaced now). **Decomposed into 2 sequential PRs** (backend then UI; sequential, NOT stacked —
avoids the stacked-PR child-autoclose cluster).

### Boundary inventory (blast radius — from Explore sweep, do NOT start code above this)
**3 vitality COMPUTE sites (collapse 3→2):**
1. `supabase/functions/vitality-nightly/index.ts` `processUser` (L206-300) — the WRITER (the only thing that
   writes `body_part_progress.vitality_ewma/peak`). EWMA `stepEwma` L165-177; consts L104-118
   (τ_up=14, τ_down strength=42 / cardio=21, sample=7d).
2. `lib/features/rpg/domain/vitality_calculator.dart` `step()` — Dart parity helper, READ-ONLY (no writes). **Survives as producer #2.**
3. `lib/features/rpg/providers/stats_provider.dart` `_reconstructTrends` (L290-370) — chart display projection (re-steps week-by-week, rescales terminal to persisted ewma). **Display only — stays.**
   (`00081` XP-gate READS cardio vitality for `vmult` — a reader, not a producer.)

**Guard / persistence:** `vitality_runs` PK `(user_id,run_date)` (00042 L49-54) = per-user/day, NOT per-bp.
`body_part_progress.vitality_ewma/peak` (00040 L178-179). No `last_vitality_date` / `vitality_pct` column yet.

**Save path:** `save_workout` (00079 L629-824) → atomic txn → `record_session_xp_batch` (L751) →
`record_cardio_session` (L756). Returns ONLY `to_jsonb(workouts row)` (no XP/vitality). Dart caller
`workout_repository.saveWorkout()` (L67-139).

**Provider chokepoint:** `rpgProgressProvider` (`rpg_progress_provider.dart` L106-156) — always re-SELECTs
`body_part_progress`; `refreshAfterSave()` (L140-145). All vitality emitters read through it →
re-emit fresh automatically. NOT app/keepAlive scoped. ONE stale risk: trend chart terminal anchor
(stats_provider L357-368) — verify no same-day double-count visually.

**Debrief UI:** `mission_debrief_section.dart` (pure StatelessWidget on `PostSessionState`); state built in
`post_session_controller.dart` `_buildInitial` (L133-299). Hue bar to reuse: `XpSegmentedBar` + `BodyPartHues.hueFor`.
Cuts are a FIXED list under `cuts/` — beat is a static summary widget, add NOTHING to `cuts`.
Before-vitality capture point: `finish_workout_coordinator.dart` pre-await snapshot (L243-254).

**Fresh-today pulse (reuse):** `rank_up_pulse_local_storage.dart` (Hive box `rank_up_pulse`, key=bodyPart.dbValue,
24h) + `body_part_rank_row.dart` L51-55 consumer.

**Tests/parity:** `test/integration/rpg_vitality_nightly_test.dart` (inlined α consts L60-70; idempotency asserts
ONE `vitality_runs` row/day L534-564 — WILL change). `test/fixtures/rpg_xp_fixtures.json` `vitality` block +
`generate_rpg_fixtures.py` (constants UNCHANGED — formula relocates, not re-tuned). E2E: `selectors.ts`
L1613-1653 + `saga.spec.ts` / `cardio.spec.ts` (selectors unchanged unless DOM shifts).

### PR 1 — backend: save-time recompute (migration + RPC, NO UI) — CODE COMPLETE, PR pending
- [x] New migration `00082`: add `body_part_progress.last_vitality_date date` (per-bp first-writer-wins guard).
- [x] New `recompute_vitality_for_user(p_user uuid, p_body_parts text[] DEFAULT NULL)` SQL RPC — ports `processUser`
      EWMA verbatim (same consts), window-based + idempotent: steps each target bp ONLY if
      `last_vitality_date IS DISTINCT FROM (now() utc)::date`, then UPSERTs ewma/peak/updated_at + last_vitality_date.
      NOTE: RPC UPSERTs (insert-on-missing over the active universe), NOT update-only — faithful port of the old
      edge-fn `upsert()` (an UPDATE-only port silently froze a day-0 user whose first volume had no prior row).
- [x] `save_workout` (superseded in 00082, not edited in 00079): `PERFORM recompute_vitality_for_user(v_user_id,
      <session-attributed bps>)` AFTER `record_cardio_session` (in-txn, after the cardio XP-gate so the gate keeps
      prior-day vitality). Touched bps = `array_agg(DISTINCT attribution key)` over this session's xp_events.
      RETURN shape unchanged (`to_jsonb(workouts row)`).
- [x] `vitality-nightly` edge fn: `processUser` collapses to one `recompute_vitality_for_user(user, null)` call
      (3→2 producers). `vitality_runs` insert kept as advisory audit log (upsert/ignoreDuplicates); per-bp guard
      is the dedup authority.
- [x] Dart↔SQL parity: SQL RPC EWMA == `VitalityCalculator`/fixtures (verified 1e-4 in psql + integration).
      Updated `rpg_vitality_nightly_test.dart`: idempotency = "second same-day call does NOT double-step ewma";
      added `_clearVitalityGuard` for the multi-day trajectory loops; added save-time-recompute + first-writer-wins
      coverage. Fixture constants unchanged.
- [x] Verify: migration applied LOCAL; FULL integration suite GREEN (15 files, 0 failures — incl. cardio XP-gate
      parity); `dart format` + `dart analyze --fatal-infos` clean. Hosted push deferred to post-merge (pipeline step 12).

### PR 2 — UI: debrief beat + fresh-today pulse (after PR 1 merges)
- [ ] ui-ux-critic defines the "Conditioning charged +N%" beat (count-up on body-part-hue bar, per trained bp).
- [ ] Extend `PostSessionState` with before/after vitality_pct per trained bp (from coordinator snapshot vs
      post-refresh) — NO change to `save_workout` return / `PostSessionParams` contract.
- [ ] Render beat in `MissionDebriefSection` (static; no new cinematic cut). Honest server number.
- [ ] Saga rows "fresh today" pulse: sibling Hive box on the rank-up-pulse pattern, set for trained bps,
      consumed in `body_part_rank_row.dart`.
- [ ] Visual gate (mockup vs 320/360/412) + verify trend chart no same-day double-count.
