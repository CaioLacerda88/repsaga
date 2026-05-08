# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/workouts-finish-error-classification — Family 1B from active-workout exploratory pass

**Branch:** `fix/workouts-finish-error-classification`
**Source:** `tasks/active-workout-implementation-plan.md` Family 1 PR1B + master findings AW-EX-D-US1-03, AW-EX-D-US1-04, AW-EX-E-US1-02. Re-test AW-EX-D-US1-02 (likely dissolved post-1A).

**Root cause:** `active_workout_notifier.finishWorkout()` has a single `catch (e)` block (~L744-831) that uniformly enqueues every save failure as offline. `SyncErrorClassifier.isTerminal()` is consulted in the drain loop but NOT at the point of initial enqueue. So:
- HTTP 500 from `save_workout` is silently queued — user sees "Saved offline" with NO error indication (AW-EX-D-US1-03)
- Save hang (no timeout) falls through to offline queue at ~2s — no loading overlay, contradicting the documented 10s cancel-button contract (AW-EX-D-US1-04)
- Code-confirmed in Charter E (AW-EX-E-US1-02)

**Fix scope (PR1B only):**
1. Hoist `SyncErrorClassifier.isTerminal()` to the catch site in `finishWorkout`. On terminal (4xx, validation), RETHROW so `AsyncValue.guard` lands in `AsyncError` and the UI surfaces the error properly. Only enqueue on transient/offline.
2. Add explicit `.timeout(Duration(seconds: 30))` on `WorkoutRepository.saveWorkout`. Currently uses Supabase HTTP client default — TimeoutException is already classified as transient by `SyncErrorClassifier`, so this composes naturally.
3. Wrap `notifier.finishWorkout()` in a loading overlay (in `finish_workout_coordinator.dart` or wherever the call site lives) that reveals a Cancel button after 10 seconds. Tap Cancel = abort save, workout reverts to active state (NOT discarded — per PLAN.md Phase 14b "local-first, never lose user data").
4. Decision on 5xx: keep as transient (queue) but set a discriminator in the snackbar copy so the user knows it's a server issue vs network issue. May add `SyncErrorCategory.serverError` to the queued action for badge differentiation.
5. Tests:
   - Unit: classification at catch site (mock 4xx → AsyncError, mock socket error → queue, mock 500 → queue with serverError category if added)
   - Unit: explicit timeout on saveWorkout (mock never-resolving Future → TimeoutException after 30s)
   - Widget: loading overlay reveals Cancel at 10s; tap Cancel → notifier returns to active state, workout intact
6. Re-probe AW-EX-D-US1-02 (Saga intro intercepting PR celebration) post-1B — if it dissolved, mark resolved; if not, that's Family 7's domain.

**Out of scope:** anything in Families 2-8 not already shipped. Saga intro race is Family 7 territory; only re-probe it as part of this PR's QA gate.

### Checklist

- [x] tech-lead: read implementation plan §Family 1 PR1B + Charter D / E findings; read `sync_error_classifier.dart` to confirm 4xx vs transient discrimination
- [x] tech-lead: TDD — failing unit tests first (catch-site classification: 4xx → AsyncError, socket → queue; explicit timeout: never-resolving Future → TimeoutException)
- [x] tech-lead: hoist `SyncErrorClassifier.isTerminal()` to `active_workout_notifier.finishWorkout()` catch site; rethrow on terminal so `AsyncValue.guard` surfaces error
- [x] tech-lead: add `.timeout(Duration(seconds: 30))` to `WorkoutRepository.saveWorkout` (or wherever the network call composes)
- [x] tech-lead: loading overlay with 10s-deferred Cancel button already exists at `active_workout_loading_overlay.dart`; verified contract still holds
- [x] tech-lead: 5xx UX decision — extend `FinishWorkoutResult` typedef with a `serverErrorQueued` bool; coordinator picks distinguishable snackbar copy. Queued `PendingAction` keeps `errorCategory: SyncErrorCategory.none` because drain-time classification is the canonical source for that field
- [x] tech-lead: `dart format` + `dart analyze --fatal-infos` clean; full unit/widget suite green (2389 tests pass; +9 unit + +5 widget added vs baseline 2375)
- [x] orchestrator: CI green — format clean, `dart analyze --fatal-infos` 0 issues, reward-accent + hardcoded-colors guards clean, 2389 tests passing (+14 from PR1B), android-debug APK built in 36.2s
- [x] qa-engineer: PASS — selector impact zero (loading overlay was already in the widget tree, no new selector references needed); coverage validated across 9 catch-site + 5 widget overlay + FakeAsync timeout tests; D-02 verdict: medium-high confidence dissolved post-1A (primary cause D-01 false-cache is gone; secondary Saga intro race not fully ruled out without Playwright re-probe — route to Family 7 with that note)
  - [x] tech-lead: in-cycle hardening — added 5 direct classifier-level tests for wrapped `app.*` types (DatabaseException 400/500, NetworkException, TimeoutException, AuthException) to localize failure if the `app.*` branch in `SyncErrorClassifier` regresses (was previously only covered indirectly via `active_workout_notifier_finish_classification_test.dart`). Total: 14 → 19 in `sync_error_classifier_test.dart`; full unit/widget suite 2389 → 2394, all green.
- [x] orchestrator: PR #179 opened — https://github.com/CaioLacerda88/repsaga/pull/179
- [x] reviewer: pass; address every finding before merge
  - [x] tech-lead: Warning 1 (cancel-tap test assertion is type-only) — strengthened the post-tap assertion in `active_workout_loading_overlay_test.dart` from `expect(notifier, isNotNull)` to `expect(state, isA<AsyncData<ActiveWorkoutState?>>())` with a reason string explaining the failure mode (overlay would remain visible if cancelLoading left the notifier in AsyncLoading/AsyncError). Test name unchanged: `tapping cancel after 10s invokes notifier.cancelLoading() — workout state intact, no save discarded`.
  - [x] tech-lead: Warning 2 (no integration test for `dart:async TimeoutException → enqueue` chain) — added `transient raw dart:async TimeoutException → enqueued, savedOffline=true, serverErrorQueued=false (mapException wrap chain pin)` to `active_workout_notifier_finish_classification_test.dart`. Stubs `saveWorkout` to throw the raw `dart:async` type (bypassing `mapException`), confirms classifier still treats it as transient and enqueues — pins the dual recognition in `SyncErrorClassifier` (raw `TimeoutException` L42 + `app.TimeoutException` L46) so a future refactor that leaks the raw type past the repo wrap doesn't silently swap "Saved offline" for an unhandled `AsyncError`.
  - [x] tech-lead: Suggestion (extract `SyncErrorClassifier.httpCode()` helper) — addressed in same-cycle revision per CLAUDE.md "no deferring review findings". Added `SyncErrorClassifier.httpCode(Object error) -> int?` recognising `supabase.PostgrestException` + `app.DatabaseException` + `app.AuthException` (superset of the inline switch — same set `isTerminal` discriminates as code-bearing). Notifier catch site now calls the helper instead of the inline switch; removed the stale `package:supabase_flutter` import that became unused once the pattern-match was deleted. Kept `isTerminal` body untouched (it still does its own pattern-match — wider refactor risks regressing the 19 existing `isTerminal` tests for zero correctness gain). Added 4 dedicated `httpCode` unit tests (Postgrest/numeric, wrapped DatabaseException, NetworkException → null, unknown → null) — `sync_error_classifier_test.dart` 19 → 23.
  - [x] tech-lead: `dart format` clean, `dart analyze --fatal-infos` clean (full repo), full unit/widget suite green: 2395 → 2399 (+4 new `httpCode` tests; existing notifier classification tests pass through the helper unchanged).
- [ ] squash merge to main, delete branch, post-merge cleanup PR (mark Family 1B resolved)
