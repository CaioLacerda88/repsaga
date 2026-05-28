# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

## Phase 32 PR 32h — Retire user-created exercises (RPG thesis preservation)

**Branch:** `feature/phase-32h-retire-user-exercises`

**Source spec:** `docs/PROJECT.md` §3 Phase 32 → "PR 32h — Retire
user-created exercises".

**Scope:** Deletion-only PR. Removes the entire user-create-exercise
surface (UI + route + repository method + offline-queue variant + tests
+ l10n keys) because user-created exercises can't carry calibrated
`tier_diff_mult` / `xp_attribution` per the Phase 29 v2 XP formula —
logging them would silently produce zero-XP work, breaking
`project_rpg_thesis`. Pre-launch, no live users → silent retirement.

### Boundary inventory (from Explore audit 2026-05-28)

**`CreateExerciseScreen` references:**
- DEFN — `lib/features/exercises/ui/create_exercise_screen.dart:21-27`
- IMPORT — `lib/core/router/app_router.dart:22`
- IMPORT — `lib/features/workouts/ui/widgets/exercise_picker_sheet.dart:10`
- INSTANTIATION — `app_router.dart:204` (GoRoute builder at `/exercises/create`)
- INSTANTIATION — `exercise_picker_sheet.dart:196` (Navigator.push in empty-state)

**`createExercise` method (`exercise_repository.dart:297-346`) callers:**
- `create_exercise_screen.dart:89-99` (`_submit`)
- `pending_sync_provider.dart:167-176` (offline-queue replay)
- 6 tests in `exercise_repository_test.dart:273-401`

**`PendingCreateExercise` offline-queue variant:**
- DEFN — `pending_action.dart:128-143` (Freezed sealed-union factory)
- WRITER — `create_exercise_screen.dart:108-125` (on `NetworkException`)
- READER — `pending_sync_provider.dart:146-176` (`_executeAction` switch arm)
- READER — `pending_sync_provider.dart:203-207` (`_withRetry` switch arm)
- READER — `sync_service.dart:441` (`_actionType()`)
- READER — `sync_service.dart:464-466` (`_resetRetryCount()`)
- READER — `sync_service.dart:521` (`_extractUserId()`)
- TEST — `offline_queue_service_test.dart:244-269` (round-trip)
- TEST — `sync_service_test.dart:1503-1699` (BUG-003 dep-ordering group, 2 tests + helper)

**Exercise-screen CTAs to remove:**
- `exercise_list_screen.dart` L111-113 (`_CreateExerciseFab`), L589-621 (FAB defn), L90-94 (empty-state TextButton), L520-587 (empty-state body)
- `exercise_picker_sheet.dart` L181-206 (`FilledButton.icon` in empty-state with `_query` pre-fill)

**Route navigations to drop:**
- `exercise_list_screen.dart:93` — `context.go('/exercises/create')` (empty-state)
- `exercise_list_screen.dart:112` — `context.go('/exercises/create')` (FAB onTap)

**l10n keys to delete (EXCLUSIVE — verified by `grep "l10n.<key>"` audit):**
- `createExercise`, `createExerciseButton`, `exerciseCreated`,
  `exerciseCreatedOffline`, `createWithName`, `createNewExerciseSemantics`
- Both `app_en.arb` + `app_pt.arb`, plus generated `app_localizations*.dart`
  (regenerated via `make gen` / `flutter gen-l10n`)

**l10n keys to KEEP (used by retained surfaces):**
- `noExercisesFound` — exercise_picker_sheet empty-state copy stays
- `addExercise` — exercise_picker_sheet title stays
- `addExerciseUndo` / `addExerciseToWorkoutSemantics` /
  `addExerciseSemantics` / `addExerciseFabLabel` — active-workout flow

**E2E specs to delete (`test/e2e/specs/exercises.spec.ts`):**
- 5 smoke + 4 full = 9 tests at lines 53–68, 70–92, 94–118, 230–285,
  533–584, 840–877, 879–930, 960–1018, 1069–1133. Each is exclusively
  create-exercise (form validation, full create flow, create+delete,
  duplicate-name, form-tips post-create). Surviving exercises spec
  covers seeded browsing/filter/search + detail screen.

### Decisions locked

- **Sealed-union variant treatment:** DELETE `PendingCreateExercise` from
  `pending_action.dart`. Pair with a one-shot startup purge that drops
  any legacy queue entries (string-matched on the JSON `kind` field BEFORE
  deserialization, to avoid the sealed-union exhaustiveness crash). The
  purge is a 10-line defensive guard — adds cheap insurance against
  local-dev Hive boxes that may have queued entries from before this PR.
  No live users to worry about, but the cost is trivial.
- **Repository method:** DELETE `createExercise` from
  `exercise_repository.dart`. No other consumers — all readers
  (`getExercises`, `searchExercises`, `getExercisesByIds`,
  `recentExercises`) stay untouched.
- **`exercise_picker_sheet` empty-state replacement:** drop the
  `FilledButton.icon` (the "create one" CTA). The empty-state body now
  shows just `l10n.noExercisesFound` text — the user clears the search
  filter to recover. No replacement CTA.
- **`exercise_list_screen` empty-state:** drop both the FAB and the
  empty-state "Create" TextButton. The empty-state shows just the
  list icon + heading copy. Since default exercises are seeded, the
  empty-state should only ever appear when a filter excludes
  everything — in which case the "Clear Filters" button (already
  there at L90-94 `if (hasFilters)` branch) handles recovery.
- **Schema:** no migration. `exercises.user_id` + `exercises.is_default`
  columns + RLS policies stay untouched (write paths just become
  unreachable from the UI). Keeps the schema flexible if we ever
  re-introduce user-created exercises post-launch.
- **No suggest-CTA, no banner, no migration** (locked by user — no
  live users to communicate with).
- **iOS:** out (Android-first launch).
- **Per `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`:**
  all reviewer findings fix in cycle.

### Files to delete

- [x] `lib/features/exercises/ui/create_exercise_screen.dart`
- [x] `test/widget/features/exercises/ui/create_exercise_screen_test.dart`

### Files to modify

- [x] `lib/core/router/app_router.dart` — import + `/exercises/create` route dropped
- [x] `lib/features/workouts/ui/widgets/exercise_picker_sheet.dart` — `FilledButton.icon` CTA + import dropped; empty state collapses to icon + `noExercisesFound` text
- [x] `lib/features/exercises/ui/exercise_list_screen.dart` — FAB widget, empty-state Create TextButton, and `onCreateExercise` callback removed; `_EmptyState` collapses to icon + heading when no filters apply
- [x] `lib/features/exercises/data/exercise_repository.dart` — `createExercise` method dropped
- [x] `lib/core/offline/pending_action.dart` — `PendingCreateExercise` factory dropped + `make gen` re-ran
- [x] `lib/core/offline/pending_sync_provider.dart` — `_executeAction` + `_withRetry` arms dropped + unused `Exercise`/`exercise_providers` imports
- [x] `lib/core/offline/sync_service.dart` — `_actionType`, `_resetRetryCount`, `_userId` arms dropped + `purgeRetiredKinds` invocation added to `build()`
- [x] `lib/core/offline/offline_queue_service.dart` — `purgeRetiredKinds()` method added (string-match raw JSON before deserialize, idempotent, defensively wrapped in try/catch)
- [x] `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` — BUG-003 dependsOn-scan block dropped from `_enqueueOfflineWorkout`
- [x] `lib/shared/widgets/pending_sync_sheet.dart` — `_icon` / `_label` arms dropped
- [x] `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb` — 7 keys dropped (`createExercise`, `createExerciseButton`, `exerciseCreated`, `exerciseCreatedOffline`, `createWithName`, `createNewExerciseSemantics`, `pendingActionCreateExercise`). `noExercisesFound`, `addExercise`, and the active-workout `addExercise*` family preserved.

### Tests to update

- [x] DELETE `test/widget/features/exercises/ui/create_exercise_screen_test.dart`
- [x] DELETE `createExercise` group from `test/unit/features/exercises/data/exercise_repository_test.dart`
- [x] EDIT `test/unit/core/offline/offline_queue_service_test.dart` — drop the `PendingAction.createExercise(...)` round-trip and rename the surviving test to "deserializes every supported action type". Added a new `purgeRetiredKinds` group with 4 tests (drop legacy rows, idempotency, healthy queue no-op, unparseable row tolerance).
- [x] DELETE `test/unit/core/offline/sync_service_test.dart` BUG-003 group (2 tests + helper) plus `_MockExerciseRepository`, `ExerciseRepository` import, `Exercise` import, `exercise_providers` import, and `MuscleGroup`/`EquipmentType` registerFallbackValue calls.
- [x] DELETE 9 create-flow E2E tests from `test/e2e/specs/exercises.spec.ts` (smoke create FAB / form-validation / create / delete / no-form-tips / full create / full delete / EX-003 soft-deleted search / EX-007 duplicate name). Also dropped the smoke `should render heading and filter controls` duplicate and the full `should load exercise list with seeded exercises` createFab assertion.
- [x] DELETE G1 / G2 user-created tests from `test/e2e/specs/exercises-localization.spec.ts`; updated header comment + dropped `CREATE_EXERCISE` import.
- [x] ADD `purgeRetiredKinds` unit tests (4) primed with raw legacy JSON blobs.
- [x] ADD E2E negative pin `should not render an Add Exercise affordance on the library` in `exercises.spec.ts`.
- [x] EDIT `test/widget/features/exercises/ui/exercise_list_screen_test.dart` — renamed the FAB + empty-state tests to pin the post-retirement steady state (no FAB; empty state collapses to icon + heading).
- [x] EDIT `test/unit/features/workouts/providers/active_workout_notifier_test.dart` — dropped the BUG-003 positive pin (createExercise-dependent offline save); rewrote the negative pin as a steady-state "offline saveWorkout has empty dependsOn" test since user-created exercises were the only parent class.
- [x] EDIT `test/unit/core/offline/sync_service_health_check_test.dart` — `_ThrowingQueueService` stub gets a `purgeRetiredKinds()` override returning 0 (matches real impl's swallow-on-failure contract).
- [x] AUDIT `test/e2e/helpers/selectors.ts` — dropped `EXERCISE_LIST.createFab` and the entire `CREATE_EXERCISE` block. `test/fixtures/test_factories.dart` audit: no `createExerciseRequest` / `userCreatedExercise` factories existed; no edits needed.

### Verification

- `make ci` green
- Smoke E2E `--grep @smoke` green locally + remote
- Manual sanity: `grep -r "CreateExerciseScreen\|createExercise\|PendingCreateExercise\|/exercises/create" lib/ test/`
  returns 0 hits (production code is clean)
- Physical-Android verification: SKIPPED per spec (deletion-only, no new
  UX surface — E2E negative-pin is the load-bearing gate)
- One quick manual check on physical Android post-merge: open the
  Exercise library tab, confirm no FAB; open the workout exercise
  picker, search for a non-existent name, confirm no "create one" CTA.
  Visual screenshot in PR body.

### Decisions captured

- **No migration; no replacement UX.** Library + picker both lose the
  create affordance entirely.
- **Sealed-union purge over no-op stub.** Cleaner — the union becomes
  3 variants (`saveWorkout`, `updateExercise`, `deleteExercise`), and
  any code path that asserts exhaustiveness gets simpler.
- **Repository method drops, not stubs.** No `@Deprecated` annotation
  needed — the method has no external consumers post-deletion.
- **Skip iOS work** — Android-first launch.
- **Skip suggest-CTA** — pre-launch, no users to redirect.
