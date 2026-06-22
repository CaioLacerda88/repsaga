# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 T3.3 + T3.4 — RPC doc + test hygiene — `feature/hardening-t3.3-t3.4-cleanup`

Per `docs/PROJECT.md` §2 → Phase 38.9 T3.3 / T3.4. Non-production cleanup (docs + tests);
reviewer reads, no separate QA gate (this IS the test-quality work).

### T3.4 — test hygiene (qa-engineer)
- [x] Rewrite `test/unit/.../celebration_orchestrator_test.dart` — the only pure
  wiring-not-behavior file — to assert via `RankUpPulseLocalStorage` READS (does the recorded
  pulse surface to the consumer), not mock-interaction `verify(...).called`. Kept the
  failure-isolation test (now asserts the surviving write is readable via `isPulsing`). Uses a
  real Hive temp-box (`Hive.init` + `hive-testwidgets` pattern).
- [x] Audit the 6 animation `pump(Duration)` tests — verdict: ALL 6 already assert RENDERED
  output (finders, painted alpha, render-box sizes, Semantics props, widget props, `findsNothing`
  after duration). None assert `controller.value`/progress. No fixes needed; none churned.
- [x] Dead skips + serial mode: **(reviewer fix)** the skipped `ActionHero._startQuickWorkout`
  offline-guard group was NOT dead — the quick-workout feature is live (`action_hero.dart:185`,
  wired to `_FreeWorkoutHero` card tap, offline guard intact at 186-195); only the trigger widget
  changed in 26f (OutlinedButton → card tap), which is why the old text-based test couldn't pass.
  **Re-pointed** (not deleted): `start_workout_offline_guard_test.dart` now has a
  `Free-workout hero — offline guard` group that renders the real `ActionHero` on its free-workout
  branch and asserts BEHAVIOR — offline tap → `offlineStartWorkout` snackbar + `startWorkout` never
  invoked + no nav to `/workout/active`; online tap → workout started + nav fires + no snackbar.
  Deleted the superseded `charter-d-exploratory.spec.ts` (whole file was the one `describe.skip`
  block; also removed its `testIgnore` entry in `playwright.config.ts`) — B8/B9/B11 contracts
  confirmed live-covered elsewhere (below). Added `mode: 'serial'` to the `manage-data`
  "Manage Data" block. `flutter test` 3980 green; `dart analyze --fatal-infos` clean.
  - charter-d B8/B9/B11 coverage check: B8 (offline finish) — `offline-sync.spec.ts` OFFLINE-005/007/008
    (queue → pending-sync badge → home nav) + snackbar copy unit-pinned in
    `active_workout_notifier_finish_classification_test.dart`. B9 (server-500 save) —
    `offline-sync.spec.ts:673` pins `workoutSavedServerError` copy + negative-pin on offline copy.
    B11 (double-tap dedupe) — `crash-recovery.spec.ts:411` (rapid double-tap → clean state) +
    unit `active_workout_notifier_test.dart:3785` "second concurrent finishWorkout returns null". All
    three covered; no backlog item needed.

### T3.3 — canonical-RPC reference doc (tech-lead)
- [x] `docs/canonical-rpc-definitions.md` — for `save_workout` + `record_session_xp_batch` (each
  redefined verbatim across ~6 migrations), document the CURRENT canonical behavior: signature,
  what it does step-by-step, the migrations that touched it (chronological), and the invariants —
  so a future XP/vitality change doesn't need to diff 6 migrations. Referenced from PROJECT.md §1
  Database Schema. Current defs: save_workout → 00082:272-492, record_session_xp_batch → 00081:677-1216.

- [x] Verify: `flutter test` green; `dart analyze` clean (no Dart touched — docs only); doc accurate
  vs the latest migration definitions (cited migration:line ranges).

_Tier 1 + Tier 2 (T2.1–4) + T3.1 + T3.2 + dep batch merged. T2.5/T2.6 + Tier 0 remain._
