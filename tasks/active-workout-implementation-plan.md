# Active Workout — Implementation Impact Analysis

**Input:** [`active-workout-findings.md`](active-workout-findings.md) — 8 root-cause families with proposed PR clusters.
**Goal:** Map every proposed change to specific files/lines, identify regression risk, and produce a defensible implementation order.
**Method:** Code reading against the four source touchpoints per family (notifier, sync service, repository, UI widget). Cross-checked against existing test coverage in `test/unit/`, `test/widget/`, and `test/e2e/specs/`.

---

## Family 1 — Save-error classification + PR cache integrity (BLOCKER)

Maps bugs: AW-EX-D-US1-01, AW-EX-D-US1-02, AW-EX-D-US1-03, AW-EX-D-US1-04, AW-EX-E-US1-02, AW-EX-E-US1-03.

### 1. Files to modify

**Save-error classification at enqueue time:**
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:744-831` — single `catch (e)` block that uniformly enqueues. Inject a `SyncErrorClassifier.isTerminal(e)` check at L750 BEFORE setting `savedOffline = true`. On terminal, rethrow so `AsyncValue.guard` (the outer wrapper at the calling site) lands in `AsyncError`.
- `lib/core/offline/sync_error_classifier.dart:11-27` — extend the classifier to recognize `5xx` codes as transient-but-surfaceable (currently ALL 5xx return `false` → silent queue). Decision needed: do we keep 5xx as transient (queue) but emit a "Server error, retrying in background" snackbar? Or surface 5xx as user-facing error?

**PR cache seeding (the BLOCKER root):**
- `lib/features/personal_records/data/pr_repository.dart:38-88` — `getRecordsForExercises()` already has read-through caching, but it's only called in two narrow paths: from inside `finishWorkout()` as a cache-miss fallback (`active_workout_notifier.dart:892-895`) and from `pr_detection_service` consumers. There is NO seed-on-session-start call site. Need a new `getAllRecordsForUser()` style call OR reuse `getRecordsForUser(userId, locale)` (already exists at L101-136) which writes the user-keyed cache entry — but the active workout reads `'exercises:<sortedIds>'`-keyed entries, NOT user-keyed.
- New code path required: a session-bootstrap provider that fetches all PRs once on auth + writes them into the exercise-keyed cache shape. Can live in `lib/features/personal_records/providers/pr_cache_bootstrap_provider.dart` (new file).

**Integration site for the bootstrap:**
- `lib/core/router/app_router.dart:383` — `ref.listen(rpgProgressProvider, (_, _) {})` — same pattern. Add `ref.listen(prCacheBootstrapProvider, (_, _) {})` here so the bootstrap fires once per shell mount per authenticated user. Or wire it into `SagaIntroGate` since that's already auth-scoped.

**Drain reconciliation correctness:**
- `lib/core/offline/sync_service.dart:444-462` (`_reconcilePrCache`) — replaces `clearBox()` with surgical reseed. After upsertRecords drain succeeds, fetch fresh records and write them into the exercise-keyed cache shape. Or invalidate AND immediately reseed via the bootstrap provider.

**Loading overlay + cancel for slow saves:**
- `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart` (path inferred — see directory listing) — wrap the `notifier.finishWorkout()` await in a `showDialog` loading overlay with a 10s reveal of a Cancel button. Time-out the network call separately (currently the timeout is whatever the supabase HTTP client defaults to, plus the `connectivity_plus` 500ms debounce).
- `lib/features/workouts/data/workout_repository.dart:saveWorkout` (location not pinned, called via the notifier) — set an explicit timeout of ~10s on the underlying `mapException(...)` block.

**Hardening fallback (AW-EX-E-US1-04):**
- `active_workout_notifier.dart:960-996` — the fallback `dependsOn: const <String>[]` enqueue path. Current code has detailed comments explaining when this is safe (parent already committed). To harden: add a runtime assertion / Sentry breadcrumb if `savedOffline == true` is ever observed at this branch (defense-in-depth against future state-bleed bugs).

### 2. Existing test coverage

**Tests that protect this surface:**
- `test/unit/features/workouts/providers/active_workout_notifier_test.dart:1150-1199` — "offline path: saveWorkout fails → enqueues PendingSaveWorkout, savedOffline flag is true, state is AsyncData(null)". This test will FAIL after Family 1 if a 4xx classifier check is added — the test stubs `Exception('Network error')` which doesn't have a code, so it would still be classified transient. SAFE. But any test that throws a `PostgrestException` with code 400/422 would now need to assert `AsyncError`, not enqueue.
- `test/unit/core/offline/sync_error_classifier_test.dart` — current contract pinned. Adding any 5xx surfacing semantics requires updating these tests.
- `test/unit/core/offline/sync_service_test.dart` — drain loop, classifier-at-drain-time. The `_reconcilePrCache` change replaces `clearBox` with reseed — any test asserting "box is cleared after upsertRecords drain" must be updated to "box contains fresh fetched records after drain".
- `test/unit/features/personal_records/domain/pr_detection_service_test.dart` — pure detection logic, no cache side-effects. SAFE.
- `test/unit/features/personal_records/data/pr_repository_cache_test.dart` — read-through caching contract. New bootstrap path likely adds test cases here without breaking existing ones.

**E2E tests on this surface:**
- `test/e2e/specs/personal-records.spec.ts` — celebrates first PR, asserts navigation to `/pr-celebration`.
- `test/e2e/specs/workouts.spec.ts` — finish workout → home navigation.
- `test/e2e/specs/offline-sync.spec.ts:26-29` — explicitly documents that fetch-restore won't drain on web; pins the Family 5 architectural boundary, NOT a Family 1 dependency.
- `test/e2e/specs/charter-d-exploratory.spec.ts:208` (B1 branch) — the new pinning test for "below-baseline workout → /home, not /pr-celebration". This is the regression gate for AW-EX-D-US1-01.

### 3. Hidden dependencies / blast radius

- **Hive `prCache` data migration:** existing users boot with stale exercise-keyed entries from the false-PR sessions. After Family 1 lands, those entries point to incorrect baselines. **Options:** (a) wipe `prCache` once on first launch post-fix via a versioned migration flag in `userPrefs` (`'pr_cache_migration_v2'` style), or (b) trust the bootstrap to overwrite per-key on first read. Option (a) is safer — option (b) leaves stale entries for exercises the user doesn't touch in the first session.
- **`SagaIntroGate` lifecycle coupling:** if the bootstrap is wired into the gate's `_maybeKickRetro` style postFrameCallback, it inherits the same "active-workout screen renders OUTSIDE the shell" caveat documented in `celebration_orchestrator.dart:71-74`. A user who signs up and immediately starts a workout never traverses the shell — the bootstrap must fire from a path that's reachable in that flow too. **Recommendation:** wire it into `app_router.dart:383` (the shell scaffold) AND additionally call it eagerly from the auth-state-change side-effect (so the "fresh-user direct-to-workout" flow is also covered).
- **`PRRepository.upsertRecords` calls `_cache.clearBox` (L313):** every successful upsert wipes the entire prCache. After Family 1, the bootstrap must re-run after every `upsertRecords` to repopulate. Or `upsertRecords` should perform surgical cache patching instead of clearBox.
- **`getRecordsForExercises` falls back to `{}` on network failure** (`pr_repository.dart:84-87` — note the `if (cached != null) return cached; rethrow;`). After bootstrap, the cache is hot, so the fallback path is dead unless cache is wiped mid-session. Still — the rethrow propagates to `active_workout_notifier:894`, which is inside a `try/catch` that swallows. Acceptable.
- **Loading overlay + cancel button:** if cancel is wired, it must NOT delete the workout from local Hive — the user may want to retry. Local-first contract: hitting cancel reverts to the workout screen with state intact.
- **Public API surface:** `WorkoutRepository.saveWorkout` is called only from `active_workout_notifier`. The classifier consumer site is also the only call site. Low blast radius.

### 4. Implementation strategy

**Split into two PRs.** They share files but have orthogonal risk profiles:

**PR 1A — PR cache bootstrap + Hive migration (the BLOCKER fix):**
1. Add `prCacheBootstrapProvider` (Riverpod `AsyncNotifier`) that reads all PRs for the current user via a new `PRRepository.getAllRecordsForCacheBootstrap()` — fetches per user, writes per-exercise-id cache keys matching the active-workout consumer pattern.
2. Bump the prCache schema version: write a `'pr_cache_schema_v2'` flag into `userPrefs` on first bootstrap; on app start, if flag absent and prCache non-empty, wipe prCache once. (One-time migration; idempotent.)
3. Wire `ref.listen(prCacheBootstrapProvider, (_, _) {})` into `app_router.dart:383` next to the rpgProgressProvider listen.
4. Replace `_reconcilePrCache`'s `clearBox` with `ref.invalidate(prCacheBootstrapProvider)` so successful drain triggers a fresh bootstrap. (The provider's autoDispose contract handles the invalidation pattern naturally.)
5. Update `pr_repository_cache_test.dart` and `sync_service_test.dart` to assert reseed-not-clear.
6. New widget test: `tasks/active-workout-implementation-plan.md` reproducer — start app with prior PR data, log a below-baseline workout → no PR detected.

**PR 1B — Save-error classification + loading overlay (the MAJOR fixes):**
1. Hoist `SyncErrorClassifier.isTerminal()` call to `active_workout_notifier:750`. On terminal, rethrow before enqueueing.
2. Decide on 5xx behavior: probably keep enqueueing (transient) but set a flag in the returned `FinishWorkoutResult` so the UI snackbar reads "saved offline due to server error" vs plain "saved offline".
3. Wrap `notifier.finishWorkout()` in a loading overlay that reveals a Cancel button at 10s.
4. Add explicit `.timeout(Duration(seconds: 30))` on `WorkoutRepository.saveWorkout` so a hung connection eventually times out as a `TimeoutException` (which `SyncErrorClassifier` already classifies as transient).
5. New unit tests for the classification at the catch site.

**Sequencing:** PR 1A first. PR 1B depends on PR 1A's bootstrap being live for the regression test to be meaningful.

**Backward compatibility:** A user mid-workout who updates the app: `ActiveWorkoutLocalStorage` carries the in-progress state in Hive `activeWorkout` box, untouched by these changes. They resume cleanly. The migration flag wipes prCache once on next cold start — they'll miss accurate PR detection until the bootstrap completes (~one network roundtrip). Acceptable.

### 5. Regression risk

**Score: 4/5.**

- The cache bootstrap touches every authenticated entry into the shell. A bug here (e.g. infinite-loop ref.listen, race against the `_coldLaunchDrain` in `SyncService`) could brick the shell mount.
- The classifier hoist changes the public contract of `finishWorkout` from "always returns success or AsyncData(null)" to "may return AsyncError on terminal save errors". UI consumers (the coordinator) must handle this — failure to update the coordinator means the user sees no feedback (current bug) or sees a generic error (worse). The `FinishWorkoutResult` shape returned from the notifier may need to add a `terminal: bool` discriminator.
- The Hive migration is one-shot but write-heavy on first launch for users with many PRs — could add 100-500ms to startup. Acceptable but observable.

**Mitigations:**
- Feature-flag the classifier hoist behind `kDebugMode` initially, ship to internal users via `EnableExperiments`, then GA.
- Bootstrap provider must be `autoDispose` — keepAlive only while shell is mounted.
- Migration flag write should `.flush()` so a crash mid-migration doesn't loop forever.

### 6. Test additions required

- **Unit:** `test/unit/features/workouts/providers/active_workout_notifier_finish_classification_test.dart` — mock `mockRepo.saveWorkout` to throw `PostgrestException(code: '400', ...)` → assert `AsyncError`, NOT enqueued; mock `Exception('Socket')` → assert enqueued.
- **Unit:** `test/unit/features/personal_records/providers/pr_cache_bootstrap_test.dart` — provider seeds the cache from repo; idempotent; doesn't refetch on second invocation when keepAlive is held.
- **Unit:** update `test/unit/core/offline/sync_service_test.dart` — `_reconcilePrCache` reseeds rather than clears.
- **Widget:** loading overlay reveals Cancel at 10s; tap Cancel → notifier returns to active state, workout intact.
- **E2E:** `test/e2e/specs/personal-records.spec.ts` — new test "below-baseline workout produces no PR celebration after first PR is established". Scenario: user has 50kg×8 baseline → log 30kg×5 → assert URL is `/home`.
- **E2E:** existing `charter-d-exploratory.spec.ts:208` (B1) becomes the regression gate.

### 7. Open questions for triage

- **Q1.1 (architectural):** Bootstrap on shell mount, or eagerly on auth state change? Shell mount misses the "fresh signup → start workout immediately" flow (per `celebration_orchestrator.dart:71-74`). Recommend: BOTH — shell `ref.listen` keeps it warm during normal navigation, plus an auth-listener side-effect for the direct-to-workout flow.
- **Q1.2 (UX):** Loading overlay copy and cancel semantics. Does Cancel discard the workout, or just abort the save (workout reverts to active)? PLAN.md Phase 14b convention is "local-first, never lose user data" → recommend abort-not-discard.
- **Q1.3 (5xx UX):** "Saved offline due to server error" vs treating 5xx the same as offline. Consider: is the badge "Pending sync (1)" misleading when the cause is server-side, not client connectivity? Possibly add a distinct `errorCategory: SyncErrorCategory.serverError` on the queued action so the badge can show a different icon.

---

## Family 2 — Rest timer scrim modality (MAJOR, single-line fix)

Maps bugs: AW-EX-A-BR1-04, AW-EX-B-US1-01, AW-EX-F-BR1-05.

### 1. Files to modify

- `lib/features/workouts/ui/widgets/rest_timer_overlay.dart:49` — outer `GestureDetector(onTap: stop)` needs `behavior: HitTestBehavior.opaque`. The `Material` child at L52 with a fully-alpha'd color paints across the whole screen but does not block hit-testing because Flutter's hit-test propagates through the GestureDetector.
- Optionally add `Semantics(label: l10n.restTimerDismiss)` to the same GestureDetector for AOM coverage (overlap with Family 3).

### 2. Existing test coverage

- `test/widget/features/workouts/ui/widgets/rest_timer_overlay_test.dart` — current tests cover rendering, button taps, completion haptic. **No test currently asserts tap-through behavior**, so the fix doesn't break anything. New test required.

### 3. Hidden dependencies / blast radius

- The inner control row at `rest_timer_overlay.dart:108-109` already uses `GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque)` to prevent button taps from reaching the outer dismiss handler. Setting `HitTestBehavior.opaque` on the outer GestureDetector preserves this — the inner detector is hit first by virtue of widget tree depth, claims the gesture, and the outer's onTap doesn't fire. **Verified pattern.**
- Long-press dismissibility (Charter C concern): `HitTestBehavior.opaque` does NOT change tap-vs-long-press behavior. Long-press requires the gesture detector to receive a sustained pointer-down — the outer detector's `onTap` fires on pointer-up after a short hold. If anything, `HitTestBehavior.opaque` makes the long-press path MORE reliable because the underlying widgets don't compete in the gesture arena.
- `AbsorbPointer` is overkill — it would also block the inner button row. The fix is `HitTestBehavior.opaque` on the outer detector ONLY.

### 4. Implementation strategy

Single PR, single line change plus a widget test:

```dart
return GestureDetector(
  behavior: HitTestBehavior.opaque,  // ADD
  onTap: () => ref.read(restTimerProvider.notifier).stop(),
  child: Material(...),
);
```

### 5. Regression risk

**Score: 1/5.**

`HitTestBehavior.opaque` on a full-screen GestureDetector is the canonical Flutter pattern for "modal scrim". The risk is essentially zero unless we discover a hidden code path that DEPENDS on tap-through working (e.g., a Sentry test that simulated dismissal via tap-through to verify haptic count).

### 6. Test additions required

- **Widget:** `test/widget/features/workouts/ui/widgets/rest_timer_overlay_test.dart` — pump overlay AND a `GestureDetector` underneath that asserts its onTap was NOT called when the scrim is tapped. Verifies the opaque hit-test contract.
- **E2E:** Existing rest timer tests (`workouts.spec.ts`) likely have a "tap to dismiss" assertion already. Verify they still pass — if any test depended on tap-through opening another sheet, it must be updated.

### 7. Open questions for triage

- None. This is a safe, surgical fix. UX critic should be invited to optionally extend the fix with an explicit "Tap to dismiss" hint at the bottom (the AW-UX-A-BR1-05 finding mentions the instruction may be below the fold on 780px-tall viewports).

---

## Family 3 — A11y semantic wrappers (MAJOR)

Maps bugs: AW-EX-A-BR1-03, AW-EX-A-BR1-05, AW-EX-B-US1-02, AW-EX-C-BR1-01, AW-EX-C-BR1-02, AW-EX-F-BR1-01, AW-EX-F-BR1-06.

### 1. Files to modify

**Stepper buttons (the +/− IconButtons):**
- `lib/shared/widgets/weight_stepper.dart:168-183` (`-` button) and `:228-243` (`+` button) — the simplest fix is to add `tooltip: l10n.decrementWeight` / `tooltip: l10n.incrementWeight` to the `IconButton`. Flutter auto-promotes the tooltip text into the AOM as the button's accessible name. NEW ARB keys required.
- `lib/shared/widgets/reps_stepper.dart:135-147` (`-`) and `:176-192` (`+`) — same pattern with `decrementReps` / `incrementReps`.

**Set-type micro-label inside the set number cell:**
- `lib/features/workouts/ui/widgets/set_row.dart:666-674` — the `Text(set.setType.tinyAbbr, ...)` inside the `_SetNumberCell` Column. The existing parent `Semantics` at L613-622 covers the cell with `setNumberCopySemantics`/`setNumberSemantics` labels. Either: (a) inject the set type into the parent label, or (b) wrap the inner Text in its own `Semantics(label: l10n.setTypeAbbrFor(set.setType.localizedName(l10n)))`. (a) is simpler — extend the existing ARB strings with a "%type" interpolation.

**Rest timer overlay:**
- `lib/features/workouts/ui/widgets/rest_timer_overlay.dart:61-95` — wrap the existing countdown `Semantics` with `liveRegion: true` so the screen reader announces every tick. Add a separate `Semantics(button: true, label: l10n.restTimerDismiss)` on the outer `GestureDetector` (L49) — overlaps with Family 2.
- Also wrap the exercise-name Text at L97-104 with `Semantics(label: timerState.exerciseName)`.

**Reorder toggle / exit-reorder buttons:**
- `lib/features/workouts/ui/active_workout_screen.dart:229-240` (`_buildAppBarActions`) — wrap the `IconButton` in `Semantics(container: true, explicitChildNodes: true, identifier: 'workout-reorder-toggle')`. Pair-rule per `lessons.md` (`PR #152`).

**Exercise card swap/remove buttons:**
- `lib/features/workouts/ui/widgets/exercise_card.dart` — search for the swap and remove `IconButton` widgets and add identifiers `'workout-swap-exercise'` / `'workout-remove-exercise'`. Both must follow the container+explicitChildNodes pair-rule.

**AppBar title rename Semantics label (overlap with Family 6):**
- `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart:78` — replace bare English `'$name. Tap to rename workout.'` with `l10n.workoutNameTapToRenameSemantics(name)`.

**Stepper Semantics labels (overlap with Family 6):**
- `weight_stepper.dart:187` — `'Weight value: $formatted ${widget.unit}. Tap to enter weight.'` → `l10n.weightValueSemantics(formatted, unit)`.
- `reps_stepper.dart:151` — `'Reps value: ${widget.value}. Tap to enter reps.'` → `l10n.repsValueSemantics(widget.value)`.

### 2. Existing test coverage

- `test/widget/features/workouts/ui/widgets/set_row_test.dart` — has a "predicted-PR semantics contract" group that pins identifier+button+tap atomicity (per the comment block in `set_row.dart:920-944`). Will not be invalidated by adding set-type to the cell label, BUT must be re-run to confirm.
- `test/widget/features/workouts/ui/widgets/exercise_card_test.dart` — current selector contracts likely assert `workout-add-set` only. Adding swap/remove identifiers extends, doesn't break.
- `test/widget/features/workouts/ui/widgets/finish_bottom_bar_test.dart` — pins `workout-finish-btn`; unaffected.
- `test/widget/features/workouts/ui/widgets/rest_timer_overlay_test.dart` — current tests don't assert liveRegion. Adding it is purely additive.
- `test/e2e/helpers/selectors.ts` — `WORKOUT.reorderToggle` and `WORKOUT.removeExercise` and `WORKOUT.swapExercise` selectors don't yet exist (per Charter C). Adding them is selector additive — no existing E2E test breaks; some flaky-via-coords selectors become reliable.

### 3. Hidden dependencies / blast radius

- The pair-rule (`container: true` + `explicitChildNodes: true`) is enforced by code review and the lessons.md entry, NOT by static analysis. Future contributors will violate it. **Consider adding a custom lint or a widget test helper** that asserts every `Semantics(identifier:)` in a curated allowlist follows the pair-rule.
- Adding `tooltip:` to the stepper IconButtons surfaces a Material tooltip on long-press — the long-press is currently used for the rapid-increment-repeat behavior at `weight_stepper.dart:170-172`. **Risk: the `Tooltip` widget may compete in the gesture arena with the existing `GestureDetector(onLongPressStart: ...)` wrapper.** Verify in widget test that long-press still triggers `_startRepeating`. If the tooltip captures the gesture, switch to explicit `Semantics(button: true, label: ...)` wrapping instead.
- Adding `liveRegion: true` to the rest timer countdown causes the screen reader to announce every second. May be too chatty — investigate whether `liveRegion` should fire only on minute changes (`announce: '1 minute remaining'`) or on every tick.

### 4. Implementation strategy

Single PR, but stage the changes by widget for review readability:

1. **Steppers** (smallest diff). Add tooltips. Localize the existing English Semantics labels in the same commit (Family 6 overlap).
2. **Set-type label.** Extend `setNumberSemantics` to include the type abbreviation.
3. **Rest timer.** Add liveRegion + dismiss-scrim Semantics + exercise-name Semantics. Coordinate with Family 2 (the scrim's `behavior: HitTestBehavior.opaque` change).
4. **Reorder + swap + remove.** Add identifiers; update `selectors.ts` in the same PR.
5. **AppBar title rename.** Localize the Semantics label.

**ARB keys** required (both en and pt — coordinate with l10n contributor):
- `decrementWeight`, `incrementWeight`, `decrementReps`, `incrementReps`
- `weightValueSemantics`, `repsValueSemantics` (with placeholder for value+unit)
- `restTimerDismiss`
- `workoutNameTapToRenameSemantics` (with `$name` placeholder)
- Optionally extend `setNumberSemantics` to include type or add a separate `setTypeAbbrSemantics`.

### 5. Regression risk

**Score: 2/5.**

The pair-rule violation is the main concern (silent merge of identifier nodes — the PR #152 regression). All new identifiers must be tested with at least one widget test that asserts the identifier is reachable via `find.bySemanticsLabel`/`find.bySemanticsIdentifier`. The Tooltip-vs-LongPress contention is the secondary concern.

### 6. Test additions required

- **Widget:** `test/widget/shared/widgets/weight_stepper_semantics_test.dart` — assert role=button on +/−, assert long-press still triggers repeat.
- **Widget:** `test/widget/features/workouts/ui/widgets/set_row_set_type_semantics_test.dart` — set type changes propagate to the cell label.
- **Widget:** `test/widget/features/workouts/ui/widgets/rest_timer_overlay_test.dart` — extend with liveRegion contract.
- **E2E:** add explicit `WORKOUT.reorderToggle`, `WORKOUT.swapExercise`, `WORKOUT.removeExercise` selector entries; re-run all e2e to confirm no regression.

### 7. Open questions for triage

- **Q3.1 (UX):** liveRegion on the rest timer countdown — every second, every minute, or on completion only? Recommend: only on completion + every 30s of remaining time (configurable per locale via SemanticsAnnouncer).
- **Q3.2 (l10n):** ARB keys for `decrementWeight` etc. — does the team have a translator on call, or do we ship en-only initially with a pt fallback?

---

## Family 4 — Tap targets 48dp (MAJOR-MINOR)

Maps bugs: AW-EX-A-BR1-01, AW-EX-A-BR1-02, AW-EX-F-BR1-09.

### 1. Files to modify

**Done-mark cell:**
- `lib/features/workouts/ui/widgets/set_row.dart:990` — `SizedBox(width: 32, height: 32, child: tapTarget)` — pinned 32×32 inside a 52-wide Container. Increase to `SizedBox(width: 48, height: 48, child: tapTarget)` AND increase the cell `width: 52` (L983) to at least `width: 56` so the 48-wide tap target fits with padding. Verify the column shrinks the row layout acceptably on 360dp.

**Add Set button:**
- `lib/features/workouts/ui/widgets/exercise_card.dart:540` — `minimumSize: const Size(double.infinity, 48)`. **Already 48dp.** Charter A reported 40dp; either the bug was reported BEFORE PR #160 fix landed, OR the fix was rolled back, OR the measurement was off. **Investigate before changing.** Run a fresh viewport test.

**Dialog action buttons (systemic):**
- `lib/features/workouts/ui/widgets/finish_workout_dialog.dart:96-115` (Keep Going + Save & Finish), `lib/shared/widgets/weight_stepper.dart:133-148` (Cancel + OK), `lib/shared/widgets/reps_stepper.dart` (equivalent), `lib/features/workouts/ui/widgets/exercise_card.dart` (remove dialog) — all use stock `TextButton` / `FilledButton` without minimum sizes. 36dp default for TextButton, 40dp for FilledButton.
- Best-practice fix: introduce a global theme-level override in `lib/core/theme/app_theme.dart` — `TextButtonTheme(style: TextButton.styleFrom(minimumSize: const Size(64, 48)))`. **One change covers every dialog in the app.**

### 2. Existing test coverage

- `test/widget/shared/widgets/weight_stepper_test.dart` (likely path) — existing widget tests on stepper layout. The 40×48 IconButton constraints are already pinned; the dialog button sizes likely have no explicit assertion.
- `test/widget/features/workouts/ui/widgets/finish_workout_dialog_test.dart` — pumps the dialog. Adding minimum size to dialog buttons via theme means pumped widgets must include the AppTheme for the assertion to be meaningful.
- `test/e2e/specs/workouts.spec.ts` — uses dialog buttons. No size assertions. Safe.

### 3. Hidden dependencies / blast radius

- **Theme change has app-wide reach:** every dialog action across the app gets the new minimum. Verify this doesn't create awkward layouts in narrow dialogs (`AlertDialog` on a 200-wide test viewport, e.g.). Search for dialogs that explicitly override the theme.
- **`set_row.dart:983` width change** ripples into the row's overall Row layout. The set-row is a fixed 4-column data table; widening the done-mark column shrinks the weight/reps stepper columns by 4dp. Run the existing `set_row_alignment_test.dart` to confirm the layout still snaps cleanly.
- **Hidden coupling: the `_SetNumberCell` (set_row.dart:638)** also uses `BoxConstraints(minWidth: 48, minHeight: 48)`. The set number column and done-mark column are both 48dp targets — symmetrical and correct after the fix.

### 4. Implementation strategy

Single PR, ordered by risk:

1. **Theme override first** — add `TextButtonTheme` and `FilledButtonTheme` overrides to `AppTheme` with `minimumSize: Size(64, 48)`. Run all widget tests; resolve any layout overflow. This is the systemic fix for AW-EX-F-BR1-09.
2. **Done-mark cell** — bump from 32×32 to 48×48 inside the 52→56 Container.
3. **Add Set button** — RE-VERIFY the current 40dp claim. If still 40dp, the `OutlinedButton.styleFrom(minimumSize: Size(double.infinity, 48))` at L540 is being overridden by something — investigate.

### 5. Regression risk

**Score: 3/5.**

Theme-level changes are app-wide. Risks:
- Dialog actions on narrow screens may overflow (the OverflowBar already handles wrap-to-vertical, but adding 12dp height across two stacked buttons is +24dp total — could push notes field above keyboard).
- Existing widget golden tests may fail because button heights change.

Mitigations:
- Run `make ci` after each step.
- pt-BR finish dialog overflow is already noted in AW-UX-F-BR1-02 — this PR may make it slightly worse. Acceptable tradeoff for accessibility.

### 6. Test additions required

- **Widget:** `test/widget/core/theme/dialog_button_theme_test.dart` — pump an `AlertDialog` with two `TextButton` actions; assert `tester.getSize(find.byType(TextButton).first).height >= 48`.
- **Widget:** `test/widget/features/workouts/ui/widgets/set_row_done_mark_test.dart` — assert tap target ≥ 48×48 on a 360dp viewport.

### 7. Open questions for triage

- **Q4.1 (investigation):** Is the AW-EX-A-BR1-02 Add Set 40dp bug actually still present? The code at exercise_card.dart:540 reads `Size(double.infinity, 48)`. Run a fresh measurement before changing.
- **Q4.2 (UX):** dialog button minimum 48dp height — does this break the Material 3 visual rhythm? UX-critic should review the resulting dialog after the change.

---

## Family 5 — Connectivity / sync drain on Web (MAJOR, architectural)

Maps bugs: AW-EX-B-US1-03, AW-EX-E-US1-01, AW-EX-E-US1-04, AW-EX-E-US1-05.

### 1. Files to modify

**Browser-event source for online status:**
- `lib/core/connectivity/connectivity_provider.dart:11-48` — currently relies solely on `connectivity_plus`'s `onConnectivityChanged`. On Flutter Web, this stream only fires on OS-level adapter events. The web build also needs to subscribe to the browser's `online`/`offline` window events.
- New helper: `lib/core/connectivity/connectivity_provider_web.dart` (or use a `kIsWeb` branch) — listens to `web.window.onOnline` / `web.window.onOffline` via the `web` package (current canonical) or `dart:html` (deprecated but still works).
- Best-practice: use `package:web` (the canonical replacement for `dart:html` post-Flutter 3.13) — `web.window.addEventListener('online', ...)`. Add a `web` package dependency or use the built-in `dart:js_interop`.

**Drain trigger augmentation:**
- `lib/core/offline/sync_service.dart:59-65` (the listener) — supplement with: when ANY successful network call fires from anywhere in the app after a recent failure, treat that as a "we are connected" signal and trigger drain. This is a heuristic / belt-and-braces approach. Implementation: add a `connectivityRecoveryProvider` Notifier that any repository can call when it observes a successful response after a recent failure.
- Periodic health check: every 60s when there are queued items, ping the Supabase health endpoint. This is the third signal.

**Connectivity recovery hook for repositories:**
- New: `lib/core/data/base_repository.dart` (already exists per imports) — extend `mapException` to record success in a `connectivityRecoveryNotifier`. On success after a recent recorded failure, fire the drain signal.

### 2. Existing test coverage

- `test/unit/core/offline/sync_service_test.dart` — drain on connectivity transition. Pinned. Still works after the augmentation.
- `test/e2e/specs/offline-sync.spec.ts:26-29` — explicitly documents the limitation. Once Family 5 lands, this comment block can be removed AND new tests added that simulate browser online/offline events via `page.context().setOffline(true)`.
- No existing tests for `package:web` event subscriptions.

### 3. Hidden dependencies / blast radius

- **`package:web` is web-only.** Native builds (Android/iOS) cannot import it. The `kIsWeb` conditional branch must be careful — tree-shaking should remove the web-specific code from native builds, but conditional imports may be required (`import 'connectivity_provider_native.dart' if (dart.library.html) 'connectivity_provider_web.dart' as platform_impl;`).
- **The 500ms debounce at L34** is fine for OS-level events (where adapter flapping is real). For browser online/offline events, debounce may be too aggressive — Chrome fires the event ~immediately on real disconnection. Consider separate debounce values per source.
- **Heuristic drain trigger** ("successful response → drain queue") risks runaway drain attempts under degraded network. Add a 5-second cooldown between drain triggers from the recovery hook.
- **Periodic health check** — when does it stop firing? Only when queue is empty. Risk: a permanently-broken-server (terminal items at retryCount=6) would hammer the health endpoint forever. Solution: stop polling if the queue is entirely terminal items (no transient items remain).
- **`onlineStatusProvider`'s optimistic default of `true`** at L54 — interacts with `_coldLaunchDrain` per the comment block at `sync_service.dart:36-46`. Ensure browser-event subscriptions don't break this protocol.

### 4. Implementation strategy

Two-PR split given the architectural surface:

**PR 5A — Web-specific connectivity:**
1. Add conditional import for `package:web` event subscription.
2. Merge the browser stream with the connectivity_plus stream so `onlineStatusProvider` emits on either source.
3. Update `OfflineBanner` to render correctly on web (the existing `!isOnline` check at `app_router.dart:393` works once the provider fires correctly).
4. New web-specific widget test: simulate browser offline → assert banner appears.

**PR 5B — Drain reliability fallbacks:**
1. Add `connectivityRecoveryProvider` heuristic.
2. Add periodic health check (60s while queue non-empty).
3. Add 5s drain cooldown.
4. Tests: integration tests around the new signals.

**Sequencing:** Can ship independently — PR 5B's value compounds with PR 5A but they're orthogonal.

### 5. Regression risk

**Score: 4/5.**

- Conditional imports across native/web is brittle; broken builds are common when the `dart.library.html` discriminator is wrong (modern: `dart.library.js_interop`).
- Heuristic drain trigger creates a feedback loop risk if the recovery signal fires from a request that itself failed (retry storm).
- Periodic health check adds background network traffic — small but non-zero battery impact on idle devices.

Mitigations:
- Use established platform-channel patterns from the `connectivity_plus` source itself — there's prior art.
- Rate-limit drain triggers from the recovery hook.
- Health check uses a tiny (`HEAD`) request and exits early if the queue is all terminal.

### 6. Test additions required

- **Unit/Integration:** `test/unit/core/connectivity/connectivity_provider_web_test.dart` — mock browser events, assert `isOnlineProvider` updates.
- **Unit:** `test/unit/core/offline/sync_service_recovery_test.dart` — recovery hook fires drain, but cooldown prevents storm.
- **E2E:** `test/e2e/specs/offline-sync.spec.ts` — replace the "documented limitation" tests with real online/offline simulation via Playwright `context.setOffline()`.

### 7. Open questions for triage

- **Q5.1 (architectural):** browser online/offline events alone, or layered with periodic health check? Browser events are unreliable on Chrome (don't fire on captive portal recovery, don't fire on same-SSID reconnect). Periodic health check is the only signal that handles those cases. Recommend BOTH.
- **Q5.2 (cadence):** Health check every 60s while queued items remain — too chatty? PLAN.md offline-first ethos suggests prioritize-correctness-over-battery, but we should pick a number with intent. 60s seems right; revisit if Sentry shows excessive traffic.

---

## Family 6 — i18n leaks (MAJOR-MINOR)

Maps bugs: AW-EX-F-BR1-02, AW-EX-F-BR1-03, AW-EX-F-BR1-04, AW-EX-F-BR1-10.

### 1. Files to modify

**Default workout name (the high-visibility one):**
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:263-267` — `_generateWorkoutName()`. Currently:
  ```dart
  String _generateWorkoutName() {
    final now = DateTime.now();
    final formatted = DateFormat('EEE MMM d').format(now);
    return 'Workout — $formatted';
  }
  ```
  Fix: read `localeProvider` (located at `lib/core/l10n/locale_provider.dart:98`), pass to `DateFormat('EEE MMM d', locale.languageCode).format(now)`, and replace the `'Workout — '` prefix with an ARB key. The notifier has `ref` access — `ref.read(localeProvider).languageCode`.
- **Concern:** the inline comment at L259-262 says "Locale is intentionally not threaded here because this runs in a provider (no BuildContext). The name is stored data, not a display-only string, so it must remain stable regardless of the user's locale setting at read time." This is a deliberate prior decision. **Triage question 6.1.** The current behavior generates the name once at workout start; if the user later switches locale, the name doesn't change. This is desired (workout history shouldn't shape-shift). The fix should still use the current locale at GENERATION TIME — that's what was intended.

**Stepper Semantics labels (overlap with Family 3):**
- `lib/shared/widgets/weight_stepper.dart:187` — `'Weight value: $formatted ${widget.unit}. Tap to enter weight.'` → `l10n.weightValueSemantics(formatted, unit)`.
- `lib/shared/widgets/reps_stepper.dart:151` — same pattern.

**AppBar rename Semantics (overlap with Family 3):**
- `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart:78` — `'$name. Tap to rename workout.'` → `l10n.workoutNameTapToRenameSemantics(name)`.

**Set-type abbreviation convention (the design split):**
- `lib/features/workouts/models/set_type.dart:14-32` — the inline rationale block explicitly defends "universal gym shorthand" as a deliberate design choice. The CONFLICT is that `app_pt.arb` already defines localized `setTypeAbbrWorking: 'N'`, etc., AND `workout_detail_screen.dart:285-288` uses the localized version.
- **Two paths:**
  - Path A: Active workout adopts localized abbreviations. Replace `set.setType.tinyAbbr` at `set_row.dart:667` with a localized lookup. **Reverses prior product decision.**
  - Path B: Workout detail adopts `tinyAbbr`. Remove the `setTypeAbbr*` ARB keys; update workout_detail_screen.dart to use `tinyAbbr`. **Locks in the prior decision.**

### 2. Existing test coverage

- `test/unit/features/workouts/providers/active_workout_notifier_test.dart` — does not pin the workout name format. Safe.
- `test/widget/shared/widgets/weight_stepper_test.dart` (likely path) — current tests don't assert Semantics label content. Adding localized labels does not break them.
- `test/widget/features/workouts/ui/widgets/set_row_test.dart` — pins `set.setType.tinyAbbr` rendering. Path A REQUIRES updating these tests.

### 3. Hidden dependencies / blast radius

- **Workout name is stored data.** Once generated, it persists in the workout row. A user starting a workout in pt-BR that the system saves as "Treino — Qua 7 mai" will see that string forever. If the system was wrong before (English on pt-BR), historical workouts STAY in English. **Migration question:** do we backfill historical workout names? Almost certainly NOT — this is rendering data, the user can rename. But document the policy.
- **`SetType.tinyAbbr`** is referenced from `set_row.dart:667` and possibly elsewhere — `Grep` confirms only set_row.dart (per the Charter F dump). Path B is a clean removal.
- **`setTypeAbbr*` ARB keys** are referenced from `workout_detail_screen.dart:285-288`. Path B requires removing those usages.

### 4. Implementation strategy

Single PR (medium effort):

1. **Workout name fix (highest visibility).** Read `localeProvider` in the notifier, pass `languageCode` to `DateFormat`, replace the prefix with `l10n.workoutDefaultName(formatted)` ARB key. Add ARB keys (`workoutDefaultName: 'Workout — {date}'` / `'Treino — {date}'`).
2. **Stepper + AppBar Semantics labels.** Add ARB keys, route through `AppLocalizations`. Coordinate with Family 3 — same files, complementary changes.
3. **Set-type convention decision.** Triage Q6.2 — pick Path A or B. Implement.

### 5. Regression risk

**Score: 2/5.**

The workout name change affects only newly-started workouts; prior data is untouched. The stepper/AppBar Semantics fix is purely additive on display. Set-type Path A vs Path B is architecturally clean either way; risk is product alignment, not code regression.

### 6. Test additions required

- **Unit:** `test/unit/features/workouts/providers/active_workout_notifier_workout_name_test.dart` — pump under en locale and pt locale, assert `'Workout — Wed May 7'` vs `'Treino — Qua 7 mai'`.
- **Widget:** stepper Semantics localized content.
- **Golden (optional):** workout history list under pt-BR locale shows localized workout names.

### 7. Open questions for triage

- **Q6.1 (architectural):** The inline comment at `active_workout_notifier.dart:259-262` defends not threading locale. Reading the comment: "name is stored data, not a display-only string." This is consistent with my recommendation — generate using user's locale at generation time, then it's stored. The original concern was about read-time locale; that's not an issue. Confirm with product.
- **Q6.2 (UX/product):** Set-type abbreviation convention. Path A: localize everywhere (consistency with the rest of the i18n surface). Path B: universal gym shorthand everywhere (preserves the inline rationale's "teaching" goal). The CURRENT split is the worst of both worlds. Need a product call.
- **Q6.3 (data):** Backfill historical workout names that were generated in the wrong locale? Recommend NO — it's user-renameable data.

---

## Family 7 — Saga intro vs PR celebration race (MAJOR)

Maps bugs: AW-EX-D-US1-02.

### 1. Files to modify

**Re-evaluate after Family 1.** The Charter D analysis suggests this bug may dissolve once the false-PR pollution from AW-EX-D-US1-01 is fixed. AW-EX-D-US1-02 fires for a 60kg×8 PR after a polluted 30kg×5 baseline; if 30kg×5 was never recorded as a PR (Family 1 fix), the 60kg×8 path runs cleanly.

**If still present after Family 1:**
- `lib/features/workouts/ui/coordinators/celebration_orchestrator.dart:51-100` — already calls `SagaIntroSequencer.waitForIntroDismissed(userId).timeout(5s)` per the inline comments. Verify the sequencer fires correctly when the sequence is "first-ever workout, first-ever PR detected" — does the gate complete the sequencer when the user hasn't yet seen the intro?
- `lib/features/rpg/ui/saga_intro_gate.dart:120-170` — the `_dismiss` method (L194-203) calls `markIntroDismissedForSequencer`. The `build` at L141-143 also calls it on initial mount when the intro is already-seen OR was-dismissed-this-session. Verify the case "first run, intro shown over home, user finishes a workout from home → overlay" — the gate's State persists (it wraps the shell), so the sequencer's completer for this user is in flight. Celebration awaits, intro dismisses → `_dismiss` calls `markIntroDismissedForSequencer` → completer resolves → celebration plays.
- **Suspected actual bug:** the post-finish navigation (`post_workout_navigator.dart:104-128`) fires `rootContext.go('/pr-celebration')` BEFORE `SagaIntroSequencer.waitForIntroDismissed()` resolves, so the navigation completes (URL changes to `/pr-celebration`) but the page renders... wait, the celebration is the rootContext.go target. Then `CelebrationPlayer.play` awaits the sequencer. So we're at `/pr-celebration` while the sequencer holds. Actually re-reading: `celebration_orchestrator.dart:96-100` shows the await happens in `play()` which is called BEFORE `navigateAfterFinish`. So the await happens, then navigation. Hmm — this may already be wired correctly.
- **The actual issue:** Charter D observed `/home` as the URL, NOT `/pr-celebration`. That means `prResult.hasNewRecords` returned false, which would be Family 1 (PR detection saw the polluted cache and did NOT fire as a new PR). **Strong evidence Family 7 dissolves after Family 1.**

### 2. Existing test coverage

- `test/widget/features/rpg/ui/saga_intro_gate_test.dart` — pins gate behavior.
- `test/widget/features/rpg/ui/saga_intro_overlay_test.dart` — overlay interactions.
- `test/e2e/specs/saga.spec.ts` — saga flow.
- `test/e2e/specs/personal-records.spec.ts` — PR celebration.
- No existing test pins the SAGA-then-PR ordering on first workout. Family 7 fix (if needed) requires a new test.

### 3. Hidden dependencies / blast radius

- **The sequencer is a global singleton keyed by userId** (`saga_intro_gate.dart:52`). Test isolation requires `SagaIntroSequencer.resetForTesting()` between tests. Existing tests likely already do this.
- **The 5s timeout** at `celebration_orchestrator.dart:96-100` is documented as a defensive fallback for the "fresh user signs in, immediately starts a workout" path where `SagaIntroGate` never mounts (active workout screen is OUTSIDE the shell). If Family 7 is real, the fix may need to scope-narrow or scope-widen this timeout.

### 4. Implementation strategy

**Phase 1: Re-test after Family 1 ships.** Reproduce Charter D B2 in the order: (a) sign up, (b) log workout 1 (50×8), (c) log workout 2 (30×5 — should produce no PR, was producing false PRs pre-Family-1), (d) log workout 3 (60×8 — real PR). Observe whether `/pr-celebration` appears.

**Phase 2 (if still broken):** investigate whether `SagaIntroGate` is mounted when the active workout screen is rendered. If not, the sequencer never resolves and the 5s timeout fallback fires — which means celebrations DO play (just after 5s delay). Charter D observed `/home`, which means `prResult.hasNewRecords` was false. This points back to Family 1.

**Phase 3 (if Family 1 is wrong about the cause):** the fix is in `post_workout_navigator.dart:108-117` — when there's both a `prResult.hasNewRecords` AND the saga intro is presenting, navigate to `/pr-celebration` first, then let the celebration screen's "Continue" button trigger the saga intro on the next route. Or extend `CelebrationOrchestrator.play` to await the sequencer EVEN when `prResult.hasNewRecords == false` (so post-celebration navigation always coordinates with the intro).

### 5. Regression risk

**Score: 2/5** (likely no work; if work needed, low risk because the orchestrator is well-isolated).

### 6. Test additions required

- **E2E:** add a regression test post-Family-1: "first-ever workout produces a PR celebration even when saga intro would also fire on the same session". Sequence: fresh user → log Workout 1 (any weight × any reps) → assert `/pr-celebration` URL. (Workout 1 is always a PR for new users, by virtue of the empty cache making everything a baseline-PR — Family 1 fix changes this, so the test scenario must seed prior data via the test API.)

### 7. Open questions for triage

- **Q7.1:** Re-evaluation gate. Decision: ship Family 1 first; reproduce; confirm or refute Family 7. Do not start Family 7 work until Family 1 is in production.

---

## Family 8 — Disabled-state Finish button (NEEDS-INVESTIGATION)

Maps bugs: AW-EX-C-BR1-03.

### 1. Files to modify

**Investigation, not yet implementation.** The code at `finish_bottom_bar.dart:74` correctly uses `onPressed: enabled ? onPressed : null`, which Flutter's FilledButton honors as `aria-disabled` in the AOM. The `enabled` parameter is `_hasCompletedSet` from `active_workout_screen.dart:271`, which evaluates `widget.state.exercises.any((e) => e.sets.any((s) => s.isCompleted))` (L182-183).

**Hypothesis 1:** Charter C's auto-add-set helper inadvertently completes a set as part of "add exercise" setup. Trace `addExercise` in `active_workout_notifier.dart` — does it create a default `ExerciseSet` with `isCompleted: false`? Audit `lib/features/workouts/utils/set_defaults_test.dart` for the actual default.

**Hypothesis 2:** The Flutter Web Playwright test environment doesn't render `aria-disabled` correctly even when Flutter sets it. Charter C observed the AOM lacked `aria-disabled`, but Flutter Web's AOM mapping is inconsistent — `aria-disabled="false"` may be omitted (only "true" is set explicitly).

**Hypothesis 3:** The 30% alpha visual cue + a stale `enabled` state is the bug. If `_hasCompletedSet` rebuilds late (after a state transition that's still in flight), the visual could lag. But `widget.state` is a fresh prop on each rebuild.

### 2. Existing test coverage

- `test/widget/features/workouts/ui/active_workout_finish_button_test.dart` — pins the disabled state. **Read this test** before investigating.
- `test/widget/features/workouts/ui/widgets/finish_bottom_bar_test.dart` — pins the FilledButton's onPressed null state.

### 3. Hidden dependencies / blast radius

- The `_hasCompletedSet` is recomputed on every build. Any state change that adds/removes a completed set rebuilds the bar. No stale-state risk.
- The `addExercise` in the picker may default a single set to incomplete (this is the documented behavior — picker auto-adds one set so the user has somewhere to enter weight, but isCompleted stays false).

### 4. Implementation strategy

**Step 1: investigation.** Reproduce Charter C P11 locally (with a real browser, not via fetch override). Inspect:
- Does `_hasCompletedSet` return true at any point before user taps Done?
- Does the FilledButton's `aria-disabled` actually appear in the AOM after recent Flutter Web upgrades?

**Step 2 (if real bug):** Audit the picker's auto-add behavior; if a set is being auto-completed, fix the default in `set_defaults.dart`. Or guard the FinishBottomBar with an additional state check.

**Step 3 (if QA misinterpretation):** Document in BUGS.md as a closed false-positive. No code change.

### 5. Regression risk

**Score: 2/5** (small change if real; zero change if false positive).

### 6. Test additions required

- **Widget:** add a test that mounts ActiveWorkoutScreen with one exercise + one auto-added incomplete set; assert `FinishBottomBar.enabled == false`.

### 7. Open questions for triage

- **Q8.1:** Reproduce on real Chrome before committing to a fix. The Playwright observation may be a Flutter Web AOM quirk rather than a real bug.

---

## Cross-cutting decisions

### Combine vs split

| PR cluster | Recommendation |
|---|---|
| Family 1 (BLOCKER) | **SPLIT into 1A (PR cache bootstrap + migration) and 1B (classification + loading overlay).** 1A is the BLOCKER fix; 1B is the MAJOR error-handling fix. Different risk profiles, different test surfaces. |
| Family 2 (rest scrim) | Standalone PR. 30-minute fix. |
| Family 3 + Family 6 (a11y + i18n) | **COMBINE.** They touch the same widgets (steppers, AppBar title, rest timer, set-row). Coordinating ARB key additions in one PR is easier than chaining two. |
| Family 4 (tap targets) | Standalone PR. App-wide theme change has its own review surface. |
| Family 5 (connectivity web) | **SPLIT into 5A (web events) and 5B (recovery hook + health check).** Different platforms, different dependency profiles. |
| Family 7 (saga race) | **DEFER until Family 1 ships.** Strong evidence it dissolves with Family 1's PR cache fix. |
| Family 8 (finish disabled) | **INVESTIGATE first.** May not need a PR at all. |

### Re-evaluation gates

- **Family 7 → after Family 1B merges.** Reproduce Charter D B2 in the new order. If `/pr-celebration` appears, Family 7 is closed.
- **Family 8 → before any PR.** Reproduce on real Chrome. If `aria-disabled` is correctly absent only when the button is enabled, this is a QA misinterpretation.
- **Family 5B → after Family 5A merges.** Web event source is the higher-confidence fix; the recovery heuristic adds value but should be measured against Sentry data on real-world drain failures post-5A.

### Effort vs master findings comparison

| Family | Master estimate | Refined estimate | Confidence in fix |
|---|---|---|---|
| 1A (PR cache + migration) | (subset of 6h) | **5-7h** — bootstrap provider, cache reseed, Hive migration, tests | **High** — root cause clear, fix path documented |
| 1B (classification + overlay) | (subset of 6h) | **3-4h** — classifier hoist, loading overlay, timeout config, tests | **High** — narrow surface, well-pinned by classifier tests |
| 2 (rest scrim) | 30min | **30min-1h** + widget test | **High** — single line, canonical Flutter pattern |
| 3 + 6 combined (a11y + i18n) | 4h + 3h = 7h | **5-7h combined** — single-pass through shared widgets | **High** for code; **Medium** for ARB key approval cycle |
| 4 (tap targets) | 2h | **2-3h** — theme change widens to all dialogs | **Medium** — theme regression risk |
| 5A (web connectivity) | (subset of 8h) | **4-6h** — `package:web` events, conditional imports, tests | **Medium** — first-time Web platform code in this app |
| 5B (recovery hook) | (subset of 8h) | **3-5h** — hook, health check, cooldown, tests | **Low** — heuristic fallback behavior is hard to test exhaustively |
| 7 (saga race) | 3h, may dissolve | **0-3h** — likely 0 after Family 1 | **Medium** — depends on Family 1 result |
| 8 (finish disabled) | 1-2h investigation | **30min investigation + 0-1h fix** | **Low** until investigation completes |

**Net total:** **22-32h** of tech-lead time (vs master findings' 25-28h estimate). Mostly aligned; the cache bootstrap migration and the web connectivity work each add ~1-2h beyond initial estimate.

### Recommended PR ordering (refined)

1. **PR 1 — Family 2 (rest scrim).** 30-min quick win. Single line. Validates the implementation pipeline before the bigger work.
2. **PR 2 — Family 1A (PR cache + bootstrap + migration).** BLOCKER. Highest priority.
3. **PR 3 — Family 1B (save-error classification + loading overlay).** Depends on 1A being live for regression test integrity.
4. **PR 4 — Family 8 investigation outcome.** Either close as false-positive or ship a small fix.
5. **PR 5 — Family 7 re-test.** Confirm it dissolves with 1A; if not, ship a small fix.
6. **PR 6 — Family 4 (tap targets, theme).** Material-compliance pass. Standalone.
7. **PR 7 — Family 3+6 combined (a11y + i18n).** Single sweep through shared widgets with new ARB keys.
8. **PR 8 — Family 5A (web connectivity).** Architectural; lowest urgency but highest confidence in long-term value.
9. **PR 9 — Family 5B (recovery hook + health check).** Layered on 5A.

This ordering front-loads BLOCKER + quick-wins, defers the architectural work, and uses Family 1's resolution to reduce or eliminate Family 7's scope.

---

## Citations summary

All file:line references in this document are absolute paths. Reviewers can navigate directly. Key infrastructure files referenced:

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\providers\notifiers\active_workout_notifier.dart` (the BLOCKER source)
- `C:\Users\caiol\Projects\repsaga\lib\core\offline\sync_service.dart`
- `C:\Users\caiol\Projects\repsaga\lib\core\offline\sync_error_classifier.dart`
- `C:\Users\caiol\Projects\repsaga\lib\core\connectivity\connectivity_provider.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\personal_records\data\pr_repository.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\widgets\rest_timer_overlay.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\widgets\set_row.dart`
- `C:\Users\caiol\Projects\repsaga\lib\shared\widgets\weight_stepper.dart`
- `C:\Users\caiol\Projects\repsaga\lib\shared\widgets\reps_stepper.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\widgets\finish_bottom_bar.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\active_workout_screen.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\coordinators\celebration_orchestrator.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\coordinators\post_workout_navigator.dart`
- `C:\Users\caiol\Projects\repsaga\lib\features\rpg\ui\saga_intro_gate.dart`
- `C:\Users\caiol\Projects\repsaga\lib\core\router\app_router.dart`

_Generated 2026-05-07. Time-boxed analysis at ~55 minutes._
