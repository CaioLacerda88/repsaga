# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 32 PR 32g — Workout-flow hotfix wave + critical E2E coverage

Per PROJECT.md §3 Phase 32 → PR 32g + `docs/home-to-workout-flow-audit.md`
findings (§4 Code review + §3.4 critical/high test gaps). Branch:
`fix/phase-32g-workout-flow-hotfix-wave`.

### Bugs (from the 2026-05-27 code review)

- [x] **Bug 1 — Duration off every finish (HIGH).** Surfaced
      `durationSeconds` on `FinishWorkoutResult` (typedef extended in
      `active_workout_notifier.dart` L81-95; populated at L1378 inside
      the guard, returned at L1869 in the record). Coordinator consumes
      `finishResult.durationSeconds / 60` floor instead of recomputing
      against `DateTime.now()` (local). `_computeDurationMinutes` helper
      removed entirely. Unit test extended in
      `finish_workout_coordinator_post_session_navigation_test.dart`:
      pins `captured.single.durationMinutes == 30` when notifier
      returns `durationSeconds: 1800`.
- [x] **Bug 2 — `developer.log` invisible on `adb logcat` (HIGH).**
      All `log(...)` calls replaced with `debugPrint('[Scope] msg')`
      across 4 files (audit listed 3 plus 1 extra discovered during
      sweep: `earned_titles_backfill_provider.dart`). Cluster reference
      inline at every site. The misleading "goes to logcat" comment in
      `celebration_orchestrator.dart:188` deleted. `dart:developer`
      imports removed from all 4 files.
- [x] **Bug 3 — Title equip silent rethrow (MEDIUM).** Wrapped the
      screen-layer `onEquipPressed` closure in `try { await
      repo.equipTitle(slug); ... } catch (_) { if (!mounted) rethrow;
      ScaffoldMessenger.of(context).showSnackBar(...); rethrow; }`. New
      ARB key `postSessionTitleEquipFailed` (en + pt) regen'd via
      `flutter gen-l10n`. Widget test
      `title_equip_failure_snackbar_test.dart` covers en + pt failure
      paths + a success-path negative pin.
- [x] **Likely Bug 2 — Confirm banner not persisted (MEDIUM).**
      Migrated `weeklyPlanNeedsConfirmationProvider` from
      `StateProvider<bool>` to `NotifierProvider<...,bool>` backed by
      Hive `userPrefs` keyed per week monday
      (`weeklyPlanConfirmNeeded:<monday-ISO>`). **Decision: persist to
      Hive (not re-derive).** Audit: the flag's trigger is the
      transient `_rollForwardFromLastWeek` write, with the user
      dismissing on Confirm/Edit — there's no server "confirmed_at"
      field to re-derive from, and adding one would require a
      migration. Hive write is durable across process kills + scoped
      per week (auto-clears on monday rollover when the key for the
      new week is absent). Three existing widget tests updated to use
      `_NeedsConfirmationStub extends WeeklyPlanNeedsConfirmationNotifier`
      pattern instead of the legacy `StateProvider.overrideWith(ref =>
      bool)` shape.

### CI gate against `dart:developer.log` reintroduction

- [x] Added `scripts/check_no_developer_log.sh` mirroring the
      `check_typography_call_sites.sh` shape. 3 gates: forbid
      `dart:developer` import, forbid `developer.log(` qualified call,
      forbid bare `log(` call. Scoped to `lib/features/workouts/` +
      `lib/features/rpg/`. Wired into `.github/workflows/ci.yml`
      analyze job + `Makefile` analyze target. Cluster reference
      `developer-log-invisible-logcat` inline in the failure message.
      Gate verified clean post-fix.

### E2E specs (5 critical from the audit's §3.4 priority list)

- [x] **EmptySessionGuardSheet** in `test/e2e/specs/workouts.spec.ts`:
      `should show EmptySessionGuardSheet when finishing with zero
      completed sets (Phase 30 PR 30a)`. Inherits @smoke from describe.
- [x] **PopScope leave-confirm** in `test/e2e/specs/post_session.spec.ts`:
      `should show leave-confirm dialog when pressing back on
      post-session route (Phase 31)`. Cancel keeps URL; Leave routes to
      /home.
- [x] **Class-change cinematic** in
      `test/e2e/specs/rank-up-celebration.spec.ts`:
      `should mount b3_class_change_cut and EQUIP row when finish
      flips class (Phase 30)`. **Decision: re-used `rpgClassCrossUser`
      fixture (Phase 18e seed) instead of adding a new
      `rpgClassChangeThreshold` user.** The existing seed already
      encodes chest=270 XP / rank 4 + others=0 XP / rank 1 → one bench
      80×5 set crosses rank 5 → Initiate→Bulwark class flip. A
      duplicate user would mean duplicate seed code for no behavioral
      difference. In-spec `reseedClassCrossUser` mirrors
      `seedRpgClassCrossUser` from global-setup so tests are
      repeatable + survive cross-spec contamination.
- [x] **server-error vs offline-error copy** in
      `test/e2e/specs/offline-sync.spec.ts`:
      `should show server-error snackbar when save_workout RPC returns
      500 (not connection-refused)`. Uses `page.route` 500 fulfill on
      `**/rest/v1/rpc/save_workout*`. Asserts `workoutSavedServerError`
      copy + negative pin on `workoutSavedOffline`.
- [x] **Tap planned bucket chip → routine sheet** in
      `test/e2e/specs/home.spec.ts`:
      `should open RoutineActionSheet when tapping a planned bucket
      chip and start active workout`. Lives inside the existing
      `Home bucket chip row (planned routines)` describe so it
      inherits `ensurePushDayInPlan` from beforeEach.

### Widget tests (3 from §3.4 high prio)

- [x] **Mission Debrief top-N + "+N more"** — coverage already pinned
      in the existing `mission_debrief_section_test.dart` (5+ exercise
      tests at L382 + L433 verify 4 LiftRow + "+1 outro" / "+2 more"
      footer). No duplicate test added.
- [x] **Rest-timer countdown + auto-advance** in
      `test/widget/features/workouts/ui/widgets/rest_timer_overlay_test.dart`:
      new `should NOT keep the overlay visible once the notifier
      reaches remaining=0 + isActive=false (haptic delay then auto-stop)`.
      Cluster `pump-duration-masks-forward` — assertion is on the
      rendered tree (CircularProgressIndicator + Skip both findsNothing
      post-dismiss), not the controller value.
- [x] **Long Mission Debrief 6-BP layout** in the same
      `mission_debrief_section_test.dart`: new `PR 32g — long debrief
      (6 BPs trained) renders a 6-segment XP bar at 320dp without
      RenderFlex overflow`. Pins `XpSegmentedBar.segments.length == 6`
      + `tester.takeException() == null` at 320dp.

### Day-0 ActionHero (medium prio)

- [ ] **Deferred to follow-up PR.** Investigation findings: default
      routines are GLOBAL `routines` table rows (no `user_id`), so a
      beforeEach DELETE against one user would also delete the rows for
      every other test user. Reaching
      `routineListProvider.value.isEmpty` requires either (a) a new
      `is_visible_to` join column + migration, or (b) per-user RLS
      predicate filtering, or (c) bootstrap-time provider override
      bypassing real UI state. (a) and (b) are migrations outside this
      hotfix wave's scope; (c) defeats the E2E contract. Skipped test
      stays in place; expanded comment block + Phase 32 PR 32g
      investigation summary inline at the skip site. Branch IS covered
      by `action_hero_test.dart` unit tests.

### Verification + ship

- [x] Format clean (`dart format --set-exit-if-changed .`)
- [x] Analyze clean (`dart analyze --fatal-infos` — no issues)
- [x] Reward-accent / hardcoded-colors / typography / no-developer-log
      gates all clean
- [x] Unit + widget tests green (3254 passed, 1 pre-existing skip)
- [x] `git grep -nE 'developer\.log\(' lib/features/workouts/
      lib/features/rpg/` returns zero hits
- [x] 5 new E2E specs parse via `npx playwright test --list`
- [ ] PR description includes
      `**QA pass pending — final coverage + E2E run after code review.**`
      + the decision-log summary (Bug 1 surface-durationSeconds rationale,
      Likely Bug 2 Hive choice, D3 fixture re-use, Day-0 deferral)
- [ ] Apply hosted Supabase migrations post-merge (none in this PR —
      no SQL changes)
