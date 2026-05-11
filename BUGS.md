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

## PR-2 — Tap target + undo snackbar reachability ✅ RESOLVED (PR #198, merged as `a7fa13a`)

### H1 — Done-checkbox tap target only 40dp wide
**Status:** RESOLVED — PR #198
**Fix:** widened inner `GestureDetector` to full 52dp Container width and swapped `HitTestBehavior.deferToChild` → `translucent` so the slack ring is hittable. Pinned by `tester.getSize()` widget tests + a slack-zone single-fire test.

### C3 / Q5 — Swipe-to-delete undo SnackBar hidden behind rest timer overlay
**Status:** RESOLVED — PR #198
**Fix:** structural re-layering — moved `RestTimerOverlay` + `ActiveWorkoutLoadingOverlay` INTO `_ActiveWorkoutBody`'s Scaffold body slot via new `showLoadingOverlay` / `showRestTimerOverlay` flags. Flutter's `_ScaffoldSlot` paints the snackbar slot AFTER the body slot, so SnackBars now naturally composite above the overlays. Plus duration bumped 4s → 10s (Material max). Side effect (validated by UI critic): rest-timer scrim now covers body area only, not AppBar / FinishBottomBar — every reachable AppBar action is gated by a confirm dialog or non-destructive.

### Discard-race E2E (post-PR-1 gap)
**Status:** RESOLVED — PR #198
**Fix:** added `should restore active workout when Cancel tapped during stalled DELETE /workouts` E2E. Uses `route.continue()` instead of `route.abort()` to avoid an unrelated cross-invocation `_cancelRequested` race (separately tracked as S1).

### S1 — `DiscardWorkoutCoordinator._isShowingDialog` re-entrance window during post-cancel stall
**Status:** RESOLVED — PR #200 (closest related cluster; scope minimal, non-blocking for PR-2 ship)
**File:** `lib/features/workouts/ui/coordinators/discard_workout_coordinator.dart`

When `cancelLoading` is called mid-discard (the `discardWorkout()` awaitable is still in-flight waiting for the stalled DELETE), the notifier restores state immediately and the workout UI reappears. However, `_isShowingDialog` remains `true` inside the coordinator's `show()` method, which is still suspended at `await ref.read(activeWorkoutProvider.notifier).discardWorkout()`. Any subsequent tap on the AppBar X or system back gesture hits the `if (_isShowingDialog) return;` guard and silently no-ops. The user cannot re-open the discard dialog until the stalled network eventually completes and the `finally` clears the flag — an unbounded wait from the user's perspective.

**Evidence:** `DiscardWorkoutCoordinator.show` at lines 38–67. The flag is set at line 39 and only cleared in `finally` at line 66. `cancelLoading` operates on the notifier's state, not on the coordinator's flag — they are decoupled. The PR-2 E2E test (`Fix B`) uses `route.continue()` which lets the DELETE complete naturally, so the coordinator exits on its own. A test that asserts the discard dialog re-opens AFTER Cancel but BEFORE the stall resolves would fail.

**Fix sketch:** in `DiscardWorkoutCoordinator.show`, listen for state restoration after `discardWorkout()` returns (check `ref.read(activeWorkoutProvider).valueOrNull != null` post-await) and if state was restored by a cancel, clear `_isShowingDialog` early so the user can retry. Alternatively, convert `_isShowingDialog` to a `ValueNotifier<bool>` and set it false as part of `cancelLoading`'s state emission path.

---

## PR-3 — Hidden destructive gestures cleanup ✅ RESOLVED (PR #200, merged as `4e39ff4`)

### H2 / Q6 — Long-press on exercise name = silent destructive swap
**Status:** RESOLVED — PR #200
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart:424-427`

Tap on header = open detail sheet. Long-press = open exercise picker → tapping a different exercise IMMEDIATELY swaps. Visible swap-icon button does the same thing. Hidden long-press is undiscoverable AND destructive (loses user's mental model). Per Q6 decision: industry has converged AWAY from gesture shortcuts in gym apps.

**Fix sketch:** remove `onLongPress` from header InkWell entirely.

### H3 — Long-press on "Add Set" silently runs Fill Remaining
**Status:** RESOLVED — PR #200
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart:313-315`

`_AddSetButton.onLongPress` calls `_fillRemaining`. The dedicated `_FillRemainingButton` is rendered separately right below it. Two affordances for the same action; one invisible.

**Fix sketch:** drop the `onLongPress`. Keep the dedicated button.

### Q3 — Confirm dialog when swap-exercise has logged sets
**Status:** RESOLVED — PR #200
**File:** `lib/features/workouts/ui/widgets/exercise_card.dart` `_swapExercise`

Today: silent swap regardless of state. Logged sets re-attribute to new exercise's PR history.

**Fix sketch:** zero completed sets → silent swap (no friction). One or more completed sets → confirm sheet ("Swap to **Incline Bench**? Your 3 logged sets will count toward Incline Bench PRs (not Bench Press).") with explicit Cancel. Per Q3 decision; copy uses concrete exercise names per UI critic guidance.

### H5 — Adding wrong exercise has no undo
**Status:** RESOLVED — PR #200
**Files:** `lib/features/workouts/ui/widgets/exercise_picker_sheet.dart:215`, `active_workout_notifier.dart` (new `restoreExercise` mirror of `removeExercise`)

Tap = immediate add. Remove requires icon → confirm dialog → confirm. 1 tap to mistake, 3-4 taps to fix.

**Fix sketch:** show 4-second undo snackbar after add ("Bench Press added — Undo") that calls a new `notifier.restoreExercise(...)`.

---

## PR-4 — Set defaults + edge cases ✅ RESOLVED (PR #202, merged as `a6642be`)

### M1 / Q2 — Warmup pre-fill filter
**Status:** RESOLVED — PR #202
**Fix:** filter `lastSets` (and `previousSets` in `startFromRoutine`) by `setType != warmup` BEFORE index-matching. Empty-after-filter falls through cleanly to next priority. Pinned by 2 unit tests + 1 widget test using `_CapturingActiveWorkoutNotifier`.

### M2 — `propagateWeight` null vs 0 distinction
**Status:** RESOLVED — PR #202
**Fix:** explicit nullable check — null follower stops the walk (treated as uninitialized / end of formation). Regression-guard test pins that explicit `weight: 0` still propagates when `oldWeight == 0`.

### M3 — Cascading undo restores in original order
**Status:** RESOLVED — PR #202
**Fix:** notifier-owned `Map<String, int> _originalSetIndices` keyed by stable set UUID. `deleteSet` records the original index BEFORE renumbering (using `putIfAbsent`). `restoreSet` reads + drops by id after Hive persist succeeds (per reviewer suggestion). Map cleared on every workout lifecycle transition (startWorkout / startFromRoutine / finishWorkout / discardWorkout) — reviewer's one-question check caught a real unbounded-growth memory smell.

---

## PR-5 — Hint slot stability + visual contrast + disabled-Finish helper ✅ RESOLVED (PR #204, merged as `7f53998`)

### H8 — Hint slot stability across set completion
**Status:** RESOLVED — PR #204
**Fix:** `!kIsWeb` gate. Web keeps the byte-identical pre-fix conditional render (provably safe — avoids the Flutter Web semantics-engine role-swap bug that bit PR #193). Mobile gets an `ExcludeSemantics + Padding + Text(' ')` filler matching hint baseline exactly. Pinned by widget test + the `pendingPredictedPr → completedStandingPr` AOM regression pin.

### M7 — Elapsed timer WCAG AA contrast
**Status:** RESOLVED — PR #204
**Fix:** swap `theme.colorScheme.primary` → `AppColors.hotViolet` (#B36DFF; ~5.9:1 on abyss, passes AA).

### M8 — Edit-name pencil + exercise info icons visibility
**Status:** RESOLVED — PR #204
**Fix:** pencil 14dp α=0.4 → 16dp α=0.6 (`active_workout_app_bar_title.dart`); info_outline 14dp α=0.35 → 16dp α=0.5 (`exercise_card.dart`). Pinned by widget tests reading `SvgPicture.colorFilter`.

### H6 — Disabled FINISH button has no explanation
**Status:** RESOLVED — PR #204
**Fix:** new conditional helper text below button when `enabled == false`: "Complete at least one set to finish." New `finishWorkoutDisabledHint` ARB key (EN + PT). Pinned by 3 widget tests (shown / hidden / Semantics id).

### Rest-timer dismiss hint contrast
**Status:** RESOLVED — PR #204
**Fix:** alpha 0.3 → 0.6.

### Rest-timer +30s wraps on Samsung S25 Ultra (device feedback)
**Status:** RESOLVED — PR #204 (folded in mid-PR per user device feedback)
**File:** `lib/features/workouts/ui/widgets/rest_timer_overlay.dart`

Pre-fix: each control button wrapped in `SizedBox(width: 64, height: 56)`. On Samsung S25 Ultra (and likely other Android OEM font rendering) `+30s` wrapped to two lines because TextButton's default 16dp horizontal padding ate ~32dp of the 64dp box, and `+30s` at `titleMedium @ w700` (the `+` glyph is wider than `-`) didn't fit in the remaining ~32dp. Playwright at 360dp Chromium did NOT catch it.

**Fix:** dropped the SizedBox wrappers entirely. TextButton sizes to content + own padding; `minimumSize: Size(48, 48)` enforces WCAG tap-target floor (Skip gets `Size(120, 48)` to remain dominant CTA). Buttons end up slightly asymmetric in width but never wrap, scale with font accessibility settings, and meet the 48dp floor on every screen size. Pinned by widget test asserting `height < 72dp` (single-line) AND `width/height >= 48dp` (tap-target).

---

## PR-6 — PR-row loading flicker + analytics DRY ✅ RESOLVED (PR #206, merged as `005f580`)

### M6 — No false predicted-PR while pr_cache is loading
**Status:** RESOLVED — PR #206
**Fix:** `activeWorkoutRowDisplaysProvider` now gates on `AsyncValue.value == null` (vs the old `?? const []` flatten). Returns `PrRowState.none` for ALL row positions (pending + completed) during loading and AsyncError-with-no-prior-data; preserves stale `AsyncData` during refresh overlays. PR celebration at finish uses `pr_cache` (not the row provider) so finish-time correctness is unaffected. Pinned by 3 unit tests (loading/error/transition) + 1 E2E test using `page.route()` to stall the per-exercise PR query.

### Source-string DRY (smell)
**Status:** RESOLVED — PR #206
**Fix:** extracted `_workoutSource(String? routineId)` helper; routed all 4 analytics emit sites (start / startFromRoutine / finish / discard) through it. Was 2 ternaries + 2 hardcoded literals.

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
