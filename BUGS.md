# BUGS — Active Workout Audit Fix Wave (Phase 22)

**Live tracker for the multi-PR fix wave kicked off 2026-05-10.** Deleted post-cycle per the Phase 18.5 hygiene convention; permanent narrative + PR refs preserved in `PLAN.md` Phase 22.

Findings use this cycle's local code prefix (severity-coded for triage):

- `C` = Critical — data loss, unrecoverable state, silent corruption
- `H` = High — broken behavior, dangerous undocumented gestures, accessibility floor
- `M` = Medium — correctness in edge cases, noticeable UX friction
- `S` = Smell — fragility / quality issues that work today
- `Q` = UX decision (research-backed) folded into a PR

This is a **distinct numbering scheme** from BUG-XXX (Phase 18.5) and AW-EX-X-XX (the earlier exploratory pass at `tasks/active-workout-findings.md`). No cross-prefix collisions.

## Status legend

- **RESOLVED** — fix shipped, PR linked
- **OPEN** — assigned to a PR in Phase 22's cluster ledger, not yet shipped
- **PARKED** — deferred out of this cycle to a separate phase or telemetry decision

---

## PR-1 — State-machine integrity ✅ RESOLVED (PR #195, merged as `bb62bff`)

### C1 — Cancel-after-save race could surface duplicate-finish UX
**Status:** RESOLVED — PR #195
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` finishWorkout

User taps Cancel between `_repo.saveWorkout(...)` returning success and `state = result` landing → state restored to active workout, but the workout is server-committed + Hive-cleared. User retries Finish → second save call hits PK collision (defended by RPC) but lands as a confusing error.

**Fix:** introduced `var saveCommitted = false;` inside `AsyncValue.guard`; flipped true immediately after `_repo.saveWorkout(...)` returns; post-guard cancel-check now `if (_cancelRequested && !saveCommitted)`. Cancel only honored pre-commit; post-commit flow continues normally (celebration + nav).

### C2 — Discard cleared Hive before server call
**Status:** RESOLVED — PR #195
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` discardWorkout

Original order: Hive cleared first, server call second. Terminal server error → workout vanishes from Hive permanently.

**Fix:** swap the order — server delete first, Hive cleared only on success. Tested with a Completer-based ordering pin.

### C4 — `cancelLoading` permanently stuck spinner during start phase
**Status:** RESOLVED — PR #195
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` cancelLoading

When `_lastValidState == null` (start phase), `cancelLoading` set the cancel flag but emitted no state. Loading overlay stayed forever.

**Fix:** emit `state = const AsyncData(null)` so the screen's existing post-frame redirect navigates to `/home`. Combined with Q1, removed the entire `hasRestorable` gate.

### H7 — Offline `PendingMarkRoutineComplete` missing `dependsOn: [workout.id]`
**Status:** RESOLVED — PR #195
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` finishWorkout (offline branch)

`SyncService` drains FIFO + `dependsOn` only. Without the dep, `markRoutineComplete` could process before `saveWorkout` commits → references a `workoutId` the server has never seen. Verified hazard via `weekly_plans.routines` JSONB-with-no-FK + RPC silently inserts unknown UUIDs.

**Fix:** carry `dependsOn: [workout.id]` on the offline enqueue, mirroring the existing `PendingUpsertRecords` pattern.

### Q1 — Cancel from t=0 on the loading overlay (UX decision)
**Status:** RESOLVED — PR #195
**File:** `lib/features/workouts/ui/widgets/active_workout_loading_overlay.dart`

Original overlay only showed Cancel after a 10s timer + only when `hasRestorable: true`. Per Material progress-indicator guidance + Strong/Hevy benchmarks, delayed-fade-in cancel teaches distrust.

**Fix:** Cancel button always rendered. Dropped the timer + `hasRestorable` gate (combined with C4, `cancelLoading` always has a meaningful action). Overlay simplified `ConsumerStatefulWidget` → `ConsumerWidget`.

### Reviewer cycle — Fix A: start-phase race (post-guard cancel check)
**Status:** RESOLVED — PR #195 (reviewer-cycle commit `5a68623`)
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` startWorkout, startFromRoutine

Reviewer flagged: `startWorkout` had no post-guard `_cancelRequested` check. The `cancelLoading` null-branch emit could be silently overwritten by the still-in-flight guard future. Today safe because all call sites await before navigating, but fragile — relies on call-site discipline.

**Fix:** added `if (_cancelRequested) { _cancelRequested = false; state = const AsyncData(null); }` post-guard in both `startWorkout` and `startFromRoutine`. Also unified `cancelLoading` to always set the flag (no more split-by-branch reset) since all four call sites now consume + reset.

### Reviewer cycle — Fix B: discard-race (discardCommitted gate)
**Status:** RESOLVED — PR #195 (reviewer-cycle commit `e849b6a`)
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` discardWorkout

Reviewer surfaced as a "one-question check": same C1 shape on the discard path. Cancel between `_repo.discardWorkout(...)` success and `_localStorage.clearActiveWorkout()` → workout visually restored but server row already deleted.

**Fix:** mirror C1's pattern — `var discardCommitted = false;` inside the guard, flipped true after `_repo.discardWorkout(...)` returns, post-guard cancel check gated by it.

---

## PR-2 — Tap target + undo snackbar reachability — OPEN

### H1 — Done-checkbox tap target only 40dp wide
**Status:** OPEN — assigned to PR-2
**File:** `lib/features/workouts/ui/widgets/set_row.dart` `_DoneCell` lines ~1281-1296

Outer `SizedBox(width: 40, height: 48)` constrains the GestureDetector to 40dp horizontally even though the containing Container is 52dp wide. Combined with `MaterialTapTargetSize.shrinkWrap` + `VisualDensity.compact` on the Checkbox, the most time-critical tap in the app (mark set complete) misses Material's 48dp floor. Same issue for `_PredictedPrUncheckedMark` (32dp visual + 40dp wrapper).

**Fix sketch:** change inner `SizedBox(width: 40, ...)` to `width: 48` or use full `52`. `deferToChild` hit behavior already prevents stealing taps from steppers.

### C3 — Swipe-to-delete undo SnackBar is hidden behind rest timer overlay
**Status:** OPEN — assigned to PR-2
**Files:** `lib/features/workouts/ui/widgets/set_row.dart:264-278`, `lib/features/workouts/ui/widgets/rest_timer_overlay.dart:71-77`, `lib/features/workouts/ui/active_workout_screen.dart` (Stack ordering)

Snackbar duration 4s. Set completion auto-starts rest timer (opaque scrim covering screen, intercepts taps). User accidentally swipe-deletes a set during rest → undo snackbar fires UNDER the overlay → invisible AND unreachable.

**Fix sketch:** re-stack so `ScaffoldMessenger` overlay sits ABOVE `RestTimerOverlay` (dedicated `ScaffoldMessenger` higher in tree, or move rest timer into a non-blocking widget that excludes the snackbar slot). Bump duration 4s → 10s (Material max). Per Q5 decision.

### Discard-race E2E (post-PR-1 gap)
**Status:** OPEN — assigned to PR-2
**File:** `test/e2e/specs/workouts.spec.ts` (new test)

E2E for the reviewer-cycle Fix B (discard cancel-after-commit). Same `page.route()` stall pattern as PR-1's Q1 test but on `DELETE /workouts`. ~20 LOC. PR-2 is the right home since it touches the same overlay/snackbar surface.

### S1 — `DiscardWorkoutCoordinator._isShowingDialog` re-entrance window during post-cancel stall
**Status:** OPEN — file under PR-3 (closest related cluster; scope minimal, non-blocking for PR-2 ship)
**File:** `lib/features/workouts/ui/coordinators/discard_workout_coordinator.dart`

When `cancelLoading` is called mid-discard (the `discardWorkout()` awaitable is still in-flight waiting for the stalled DELETE), the notifier restores state immediately and the workout UI reappears. However, `_isShowingDialog` remains `true` inside the coordinator's `show()` method, which is still suspended at `await ref.read(activeWorkoutProvider.notifier).discardWorkout()`. Any subsequent tap on the AppBar X or system back gesture hits the `if (_isShowingDialog) return;` guard and silently no-ops. The user cannot re-open the discard dialog until the stalled network eventually completes and the `finally` clears the flag — an unbounded wait from the user's perspective (could be 30 seconds if the route handler is configured with a long abort timeout).

**Evidence:** `DiscardWorkoutCoordinator.show` at lines 38–67. The flag is set at line 39 and only cleared in `finally` at line 66. `cancelLoading` operates on the notifier's state, not on the coordinator's flag — they are decoupled. The PR-2 E2E test (`Fix B`) uses `route.continue()` which lets the DELETE complete naturally, so the coordinator exits on its own. A test that asserts the discard dialog re-opens AFTER Cancel but BEFORE the stall resolves would fail.

**Fix sketch:** in `DiscardWorkoutCoordinator.show`, listen for state restoration after `discardWorkout()` returns (e.g., check `ref.read(activeWorkoutProvider).valueOrNull != null` post-await) and if state was restored by a cancel, clear `_isShowingDialog` early so the user can retry. Alternatively, convert `_isShowingDialog` to a `ValueNotifier<bool>` and set it false as part of `cancelLoading`'s state emission path. Tech-lead should evaluate which coupling is cleaner.

---

## PR-3 — Hidden destructive gestures cleanup — OPEN

### H2 / Q6 — Long-press on exercise name = silent destructive swap
**Status:** OPEN — assigned to PR-3
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart:424-427`

Tap on header = open detail sheet. Long-press = open exercise picker → tapping a different exercise IMMEDIATELY swaps. Visible swap-icon button does the same thing. Hidden long-press is undiscoverable AND destructive (loses user's mental model). Per Q6 decision: industry has converged AWAY from gesture shortcuts in gym apps.

**Fix sketch:** remove `onLongPress` from header InkWell entirely.

### H3 — Long-press on "Add Set" silently runs Fill Remaining
**Status:** OPEN — assigned to PR-3
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart:313-315`

`_AddSetButton.onLongPress` calls `_fillRemaining`. The dedicated `_FillRemainingButton` is rendered separately right below it. Two affordances for the same action; one invisible.

**Fix sketch:** drop the `onLongPress`. Keep the dedicated button.

### Q3 — Confirm dialog when swap-exercise has logged sets
**Status:** OPEN — assigned to PR-3
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart` `_swapExercise`

Today: silent swap regardless of state. Logged sets re-attribute to new exercise's PR history.

**Fix sketch:** zero completed sets → silent swap (no friction). One or more completed sets → confirm sheet ("Swap to **Incline Bench**? Your 3 logged sets will count toward Incline Bench PRs (not Bench Press).") with explicit Cancel. Per Q3 decision; copy uses concrete exercise names per UI critic guidance.

### H5 — Adding wrong exercise has no undo
**Status:** OPEN — assigned to PR-3
**Files:** `lib/features/workouts/ui/widgets/exercise_picker_sheet.dart:215`, `active_workout_notifier.dart` (new `restoreExercise` mirror of `removeExercise`)

Tap = immediate add. Remove requires icon → confirm dialog → confirm. 1 tap to mistake, 3-4 taps to fix.

**Fix sketch:** show 4-second undo snackbar after add ("Bench Press added — Undo") that calls a new `notifier.restoreExercise(...)`.

---

## PR-4 — Set defaults + edge cases — OPEN

### M1 / Q2 — Warmup sets from previous session leak as defaults for working sets
**Status:** OPEN — assigned to PR-4
**Files:** `lib/features/workouts/ui/widgets/exercise_card.dart` `_computeNewSetDefaults`, `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` `startFromRoutine`

`_computeNewSetDefaults` Priority 2 explicitly skips warmup-from-current-session. Priority 1 (previous session at matching index) does NOT skip warmups. Same in `startFromRoutine` — `previousSets[setIndex]` includes warmups. User who logged `[warmup@40, warmup@60, working@100]` last session gets pre-filled `[40, 60, 100]` — has to manually bump sets 1-2.

**Fix sketch:** filter `lastSets` (and `previousSets` in routine path) by `setType != warmup` BEFORE index-matching.

### M2 — `propagateWeight` treats follower `weight: null` as same as `0`
**Status:** OPEN — assigned to PR-4
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:494`

`(s.weight ?? 0) != oldWeight` — when `oldWeight==0` and follower has `weight: null`, walk continues past it and overwrites. Edge case (follower added from routine with no weight history). Could produce false-PR if propagated value beats history.

**Fix sketch:** distinguish `null` from `0` — treat null as customized → stop walk.

### M3 — Cascading undo of deleted sets restores in wrong order
**Status:** OPEN — assigned to PR-4
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` `restoreSet`

Delete set #2, delete set #3 (now renumbered to #2), undo each → original set #4 ends up at position 2 instead of 3 because `setNumber` was renumbered between deletes. Data preserved, order broken.

**Fix sketch:** `restoreSet` should insert based on captured ORIGINAL position with a stable sort over current sets, not a re-renumbered position.

---

## PR-5 — Hint slot stability + visual contrast + disabled-Finish helper — OPEN

### H8 — Hint slot reflow shifts adjacent rows under the thumb
**Status:** OPEN — assigned to PR-5
**File:** `lib/features/workouts/ui/widgets/set_row.dart:283-361`

Set transitions pending → completed → previous-session hint disappears, row collapses by ~18dp, adjacent rows shift up. User tapping done on set 3 then quickly moving to set 4 may miss because set 4's checkbox shifted. Comment acknowledges "row reflow is acceptable" — that decision was made because `Visibility(maintainSize: true)` triggered a Flutter Web semantics bug. On mobile that bug doesn't apply.

**Fix sketch:** fixed-height filler `SizedBox(height: 18)` when hint is hidden, gated behind `kIsWeb` check if the AOM bug still bites.

### M7 — Elapsed timer color fails WCAG AA contrast
**Status:** OPEN — assigned to PR-5
**File:** `lib/features/workouts/ui/widgets/elapsed_timer.dart:38`

Uses `theme.colorScheme.primary` (`primaryViolet #6A2FA8`) on `abyss #0D0319` background. ~2.6:1 contrast (AA needs 4.5:1).

**Fix sketch:** swap to `hotViolet #B36DFF` (~5.9:1, passes AA).

### M8 — Edit-name pencil + exercise info icons functionally invisible
**Status:** OPEN — assigned to PR-5
**Files:** `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart:92-97` (pencil 14dp α=0.4), `lib/features/workouts/ui/widgets/exercise_card.dart:455-460` (info 14dp α=0.35)

Functional affordances rendered at the visibility threshold.

**Fix sketch:** pencil → 16dp α=0.6; info → 16dp α=0.5.

### H6 — Disabled "FINISH" button has no explanation
**Status:** OPEN — assigned to PR-5
**File:** `lib/features/workouts/ui/widgets/finish_bottom_bar.dart:74-100`

Renders dim violet, no helper text, no tooltip. New user with all sets entered but none ticked sees a grey button and no signal to tap the checkboxes.

**Fix sketch:** when `enabled == false`, show short helper text "Complete at least one set to finish."

### Rest-timer dismiss hint near-invisible
**Status:** OPEN — assigned to PR-5
**File:** `lib/features/workouts/ui/widgets/rest_timer_overlay.dart:269-276`

"Tap anywhere to dismiss" at α=0.3 on near-black scrim.

**Fix sketch:** raise to α=0.55-0.65.

---

## PR-6 — PR-row loading flicker + analytics DRY — OPEN

### M6 — `activeWorkoutRowDisplaysProvider` returns empty PR list during loading → false predicted-PR signals
**Status:** OPEN — assigned to PR-6
**File:** `lib/features/workouts/providers/workout_providers.dart:109-110`

`exercisePRsProvider(...).value ?? const []` — while loading, every completed working set looks like a "standing PR" (gold stripe + bracket). Once data lands, rows reclassify. Visual flicker. Documented as "first-ever workout" behavior but also fires for returning users with slow PR data.

**Fix sketch:** when `exercisePRsProvider.isLoading`, return `PrRowState.none` for completed sets (don't classify until data lands).

### Source-string DRY (smell)
**Status:** OPEN — assigned to PR-6
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` lines 259, 732, 1258

`current.routineId != null ? 'routine_card' : 'empty'` duplicated in three call sites. Bug-prone — one missed update produces inconsistent analytics.

**Fix sketch:** extract `_workoutSource()` helper.

---

## PR-7 — Brand voice + generic-icon swaps — OPEN

### Generic-AI-aesthetic items (Audit Section 5)
**Status:** OPEN — assigned to PR-7
**Files:** various

- `lib/features/workouts/ui/widgets/resume_workout_banner.dart:47` — `Icons.fitness_center` → `AppIcons.lift` (brand glyph exists)
- `lib/features/workouts/ui/widgets/exercise_card.dart:944` — PR empty state `Icons.emoji_events_rounded` → custom glyph or text-only
- `lib/features/workouts/ui/active_workout_screen.dart:251` — reorder toggle `Icons.swap_vert` → `Icons.reorder` (3-line drag handle convention)
- `lib/l10n/app_en.arb` + `app_pt.arb` — revisit `finishWorkoutTitle`, `discardWorkoutContent`, `workoutInterrupted` (lowercase after newline), the cancel-during-loading copy, the ambiguous "D" PT set-type abbreviation

### UI-critic deferred copy: "Cancel" → "Stop" / "Parar" on loading overlay
**Status:** OPEN — assigned to PR-7
**File:** `lib/features/workouts/ui/widgets/active_workout_loading_overlay.dart` + new ARB key

UI critic flagged on PR-1 review: "Cancel" might read as destructive ("cancel my workout") in finish/discard phase. Recommended new scoped ARB key (preserve generic `cancel` for reuse). Deferred from PR-1 as ARB scope expansion; explicit home is here in the brand voice PR.

### `_AddSetButton` near-invisible OutlinedButton
**Status:** OPEN — assigned to PR-7
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart` `_AddSetButton`

Outline at `primary.withValues(alpha: 0.3)` — high-frequency action deserves more visual punch. Today reads quieter than the "Fill remaining" TextButton beside it.

**Fix sketch:** filled accent — 12% hotViolet fill + brighter border. (Already filed as `v2-park` in Active Backlog — this PR is the right home if appetite exists; otherwise leave parked.)

---

## PARKED — deferred to separate phases or telemetry decisions

### PR-RPG: Offline celebration replay
**Status:** PARKED — needs its own design phase
**File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` `_buildAndStashCelebration`

Offline finishes that cross an RPG threshold (rank-up / first-awakening / title-unlock) silently lose the celebration moment. Queue drain awards XP correctly via the server-side reversal pattern, but `_buildAndStashCelebration` doesn't re-fire — it only runs in the foreground notifier path. Two design options: (a) full pre-snapshot persist + drain-time replay, (b) notify-only on drain (banner on next foreground open). Belongs in a separate phase, not this fix wave.

### M9 — Long-press set-type discoverability
**Status:** PARKED — needs onboarding design pass
**File:** `lib/features/workouts/ui/widgets/set_row.dart:698-790`

The 9dp `W/Wu/D/F` micro-label is the only signal. Self-teaching by long-press is documented as the design intent but discoverability is near-zero. Needs a one-time coach mark + Hive-persisted "seen" flag — that's a small feature with onboarding ramifications, not a one-line patch.

### M10 — Tap-to-copy invisibility
**Status:** PARKED — same onboarding scope as M9
**File:** `lib/features/workouts/ui/widgets/set_row.dart:736-759`

Dotted underline + 12dp icon at α=0.4 are invisible at arm's length. Users will trigger the copy by accident while reaching for the checkbox.

### First-class warmup type (cross-cutting)
**Status:** PARKED — architecturally larger than this fix wave
**Files:** `lib/features/workouts/models/exercise_set.dart`, every consumer of `setType`

Product-owner research surfaced: FitNotes / Hevy promoted warmup sets to a typed entity with their own pre-fill rules, PR exclusion, and calculator. RepSaga today treats warmup as a tag on the same set record. PR-4's M1 fix patches the symptom (filter warmups in defaults) — the real fix is to model warmups as their own class. Not in scope here; reconsider before more analytics features ship.

### Sub-200ms loading-overlay flash
**Status:** PARKED — pre-existing, surfaced by UI critic on PR-1 review
**File:** `lib/features/workouts/ui/widgets/active_workout_loading_overlay.dart` call site

Operations completing faster than ~200ms render the overlay (with Cancel) for one or two frames then immediately disappear. UI critic flagged as not a regression but a mild jarring effect. Mitigation: 150ms debounce on overlay mount, or `FadeTransition` wrap. Out of scope for current PR wave.
