# Active Workout — Exploratory Test Plan

**App:** RepSaga (web build, driven by Playwright locally — manual / codegen mode)
**Date:** 2026-05-07
**Sibling doc:** [`manual-qa-testplan.md`](manual-qa-testplan.md) — broad app-journey plan; this one is a single-screen deep dive.
**Why this exists:** Active Workout is the most-touched and most-stateful screen in the app. The historical bug list (BUG-001 through BUG-042 — 20+ entries since Phase 18, mostly clustered around set-row chrome, sync-after-finish, and Web semantics) suggests recurring fragility that automated tests have not been catching at the seams. We need a structured exploratory pass to surface what deterministic tests can't.

---

## 1. Approach

- **Driver:** Playwright in **headed mode**, run locally. Use codegen for selector capture as we discover new affordances; do NOT promote anything to a deterministic E2E spec inside this round (that's a follow-up). The goal here is exploration, not regression hardening.
- **Personas** (reusing the sibling doc): Alex (Beginner), Jordan (Consistent Lifter), Sam (Data Nerd). Each charter is scoped to one persona's mindset.
- **Charters** (§6) are timeboxed (~30–45 min each) with a goal + a list of things to probe. Within a charter, follow your nose — exploratory testing is heuristic-driven, not script-driven.
- **What to capture:** bugs AND UX-improvement notes. The latter are weighted equal in this round — the brief was "super buggy" but UX issues are often the disguise. Use the templates in §8.
- **Triage discipline:** log first, fix in a separate round. Do NOT pause exploration to chase a fix mid-charter — the context-switch destroys the exploratory momentum.

---

## 2. Coverage gap analysis

What automated tests already pin (so we don't waste exploratory time on them):

| Surface | Coverage | Where |
|---|---|---|
| 5 PR-state row renders | widget | `set_row_test.dart` |
| Dismissible swipe-to-delete | widget | `set_row_test.dart` |
| Done-mark toggle + rest timer trigger | widget | `set_row_test.dart`, `rest_timer_overlay_test.dart` |
| Back button → discard dialog | widget | `active_workout_popscope_test.dart` |
| Wakelock enable/disable on mount/unmount | widget | `active_workout_wakelock_test.dart` |
| Finish button enabled iff ≥1 completed set | widget | `active_workout_finish_button_test.dart` |
| Finish + Discard dialog content | widget | `finish_workout_dialog_test.dart`, `discard` widget tests |
| Set-row alignment on 360dp | widget | `set_row_alignment_test.dart` |
| Bodyweight column-layout | widget | `exercise_card_test.dart` |
| Hive crash recovery / resume banner | E2E | `crash-recovery.spec.ts` |
| Offline-queue badge after offline finish | E2E | `offline-sync.spec.ts` |
| Core happy path (start → set → finish) | E2E | `workouts.spec.ts` |
| PR celebration on heaviest-weight beat | E2E | `personal-records.spec.ts` |
| Start-from-routine pre-fill | unit + E2E | `start_from_routine_test.dart`, `routines.spec.ts` |
| pr_row_state pure resolver | unit | `pr_row_state_resolver_test.dart` |

**What is thinly tested or untested — these are where exploration should focus:**

1. **Multi-touch / gesture conflicts.** Two fingers on a stepper. Swipe-to-delete while another row's stepper is held. Long-press during a Dismissible drag. Set-type long-press while rest timer animates.
2. **Reorder mode interactions.** No widget test exercises the up/down arrows or the toggle. Edge cases: reorder while modal open, reorder during rest timer, reorder of bodyweight + weighted mixed.
3. **Set-type long-press cycle.** working → warmup → dropset → failure. No test pins the cycle order or the visual micro-label updates.
4. **Fill-remaining edge cases.** Empty list, bodyweight, mixed completed/incomplete, single-set exercise.
5. **Exercise picker race conditions.** Filter chip + search input + tile tap in rapid succession; pop sheet mid-debounce.
6. **Rest timer edge cases.** Adjust ±30 at exactly 0 seconds remaining; skip mid-tick; background app while running; auto-dismiss while user is mid-tap on -30.
7. **Concurrent action across exercises.** Tap done on exercise A's set while exercise B's stepper is being held.
8. **Decimal-weight locale handling.** BR locale uses comma `,`; US uses dot `.`. The `WeightStepper`'s tap-to-type dialog: does it accept both? Mixed input?
9. **Notes field edges.** Emojis, RTL characters, exactly 1000 chars (limit), 1001 chars, leading/trailing whitespace.
10. **Rename workout edges.** 80-char limit boundary, leading/trailing spaces, only-whitespace, paste long string from clipboard.
11. **Routine with deleted/swapped exercises.** Orphaned `WorkoutExercise.exercise == null` (BUG-001 territory). Hive-restored workout where a referenced exercise was deleted server-side.
12. **600ms newly-added-set done-mark lock.** Does it actually fire on slow CPUs? On the 360x780 budget profile?
13. **Predicted PR transition.** `pendingPredictedPr` → `completedStandingPr` → if a later set beats it → `completedSupersededPr`. Visual fluidity, no flicker.
14. **Network drop mid-action.** Drop offline mid-stepper change, mid-finish-dialog, mid-add-exercise. Verify Hive autosave catches everything.
15. **Loading overlay 10-second cancel button.** Does the cancel actually restore state? (`cancelLoading()` was added per BUG-039.)
16. **Two simultaneous tabs (Web only).** Active workout on tab A, start a new workout on tab B — what happens to Hive? to the resume banner?
17. **Finish-flow router branches.** 7+ post-finish paths (online+PR, online+plan-prompt, online+celebration-overflow→/profile, offline-queued, server error, etc.). The sibling doc covers this at journey level; here we want to pin every branch.
18. **Add-to-plan prompt edge cases.** Routine workout already in plan → no prompt; routine workout NOT in plan → prompt; ad-hoc workout → never prompt.
19. **Snackbar layering.** "Set deleted — undo" + offline-banner + active-workout banner + finish-loading scrim — do they stack/replace correctly?
20. **Wakelock under inactivity.** Does the screen actually stay on through a 10-min real workout? Does it release on every exit path (discard, finish, network error, kill app, navigate away)?
21. **Disabled vs hidden state correctness.** Every control with a conditional state needs probing for stale/wrong condition. See §5.5 disabled-state matrix.
22. **Slow network, not binary offline.** Set save / finish save under 3G/2G simulation — does the just-shipped 30s auth timeout pattern apply to workout save? What does the user see during the wait?
23. **Captive portal scenarios.** DNS resolves, HTTPS to Supabase fails silently. App should treat as offline, not hang.
24. **Long-duration workout (>1 hour).** Timer rollover MM:SS → H:MM:SS at 60:00. Wakelock stays on. No memory leak from rest-timer stream subscriptions.
25. **DST transition mid-workout.** Start at 1:55 AM, the clock rolls back at 2:00 AM to 1:00 AM — what does the elapsed timer show? `startedAt` should be immutable wall-clock.
26. **System clock change mid-workout.** User manually changes phone clock. Elapsed should not drift; finish-time on saved workout should be sane.
27. **i18n overflow in pt-BR.** Brazilian Portuguese strings are typically ~20% longer than English. Finish button, dialog titles, empty-state copy, snackbar text.
28. **Decimal locale handling.** BR uses `,` as decimal separator; US uses `.`. The weight-stepper tap-to-type dialog must accept whichever the locale prescribes (or both gracefully).
29. **Keyboard-only navigation (web).** Tab order, focus traps in modals, return-focus on close, Escape to dismiss, Enter to confirm.
30. **Screen reader semantics.** PR state changes announced? Set row label reads in a sensible order ("Set 3, working, 100kg, 8 reps, completed, standing PR")?
31. **Reduced motion.** `prefers-reduced-motion: reduce` should shorten or skip celebration animations and the rest-timer ring sweep.
32. **Visual at scale.** Browser zoom 200%, system font size XL — does the set row break, wrap, or stay legible?
33. **Real multi-touch (Android-only).** Two-finger simultaneous tap, pinch, multi-finger swipe. Playwright web cannot synthesize these reliably — defer to a dedicated Android pass.

---

## 3. Device + viewport matrix

From market research (StatCounter 2025–26 + IDC):

### Brazil (Android ~85%, iOS ~15%)

| ID | Device | Viewport (CSS px) | DPR | Why include |
|---|---|---|---|---|
| **BR-1** | Samsung Galaxy A14 | **360 × 780** | 2.0 | Stress: smallest viewport in matrix. Highest-volume budget Android in BR. |
| BR-2 | Motorola Moto G54 | 393 × 851 | 2.5 | Mainstream BR mid-range 1080p. |
| BR-3 | Samsung Galaxy A55 | 412 × 915 | 2.625 | Mid-high Android band shared with Pixel 8. |
| BR-4 | iPhone 13 | 390 × 844 | 3.0 | iPhone 12/13/14 logical family in BR. |

### United States (iOS ~60%, Android ~40%)

| ID | Device | Viewport (CSS px) | DPR | Why include |
|---|---|---|---|---|
| US-1 | iPhone 15 / 14 | 393 × 852 | 3.0 | Mainstream US iPhone. |
| **US-2** | iPhone 16 Pro Max | **440 × 956** | 3.0 | Stress: largest viewport. Layout overflow + stretched-tap-target risk. |
| US-3 | Samsung Galaxy S25 | 360 × 780 | 3.0 | Same CSS as BR-1, different DPR — render-quality divergence. |
| US-4 | Samsung Galaxy S24 Ultra | 384 × 824 | 3.75 | Highest DPR — hi-DPI icon/chart rendering. |
| US-5 | Google Pixel 8 | 412 × 915 | 2.625 | 412 Android breakpoint; different DPR from Samsung at same width. |

### Priority

- **Always run on:** BR-1 (smallest stress) + US-2 (largest stress) + US-1 (US mainstream) + BR-2 (BR mainstream) — these 4 cover ~70% of both markets and the layout extremes.
- **Add if time:** US-4 (DPR stress) + BR-4 (iOS in BR — different from US iPhone usage patterns).
- **Skip unless investigating a specific issue:** BR-3, US-3, US-5 (overlap with priority profiles' layout buckets).

---

## 4. Environment setup

### Prerequisites (run before each session)

```bash
export PATH="/c/flutter/bin:$PATH"

# 1. Local Supabase running and healthy
docker ps --format '{{.Names}} {{.Status}}' | grep supa
# If down: npx supabase start

# 2. Fresh web build from current main
git checkout main && git pull --ff-only
flutter build web

# 3. Test users provisioned (creates them via Admin API if missing)
cd test/e2e && npm install && cd ../..
```

### Launching Playwright in headed exploratory mode

The driver is `test/e2e/specs/exploratory.spec.ts` — guarded by `EXPL_DRIVER=1` so it's CI-safe (regression runs skip it). Each priority device viewport is a separate test, tagged so you can `--grep` to it. The test auto-logs-in, navigates to a chosen landing screen, then calls `page.pause()` — handing the browser to you via the Playwright Inspector.

```bash
cd test/e2e

# BR-1 (smallest stress, 360×780). Default user: fullPR (Sam — PR baselines).
EXPL_DRIVER=1 FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@BR-1" --headed

# US-2 (largest stress, 440×956)
EXPL_DRIVER=1 FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@US-2" --headed

# US-1 (US mainstream, 393×852)
EXPL_DRIVER=1 FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@US-1" --headed

# BR-2 (BR mainstream, 393×851)
EXPL_DRIVER=1 FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@BR-2" --headed

# Land directly on the active-workout screen (skip the home tap):
EXPL_DRIVER=1 EXPL_LANDING=workout FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@BR-1" --headed

# Switch to a different test user (e.g. for Charter B / interruption testing):
EXPL_DRIVER=1 EXPL_USER=fullCrash FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@BR-1" --headed

# Switch to pt-BR (Charter F / i18n) — uses a Brazilian Portuguese seed user:
EXPL_DRIVER=1 EXPL_USER=smokeLocalizationWorkout FLUTTER_APP_URL= npx playwright test specs/exploratory.spec.ts --grep "@BR-2" --headed
```

**Inside the inspector:**
- Drive the browser freely
- Use **Pick locator** to grab `[flt-semantics-identifier="..."]` selectors for findings
- Right-click in the browser to open DevTools (Network / Console / Application / Performance)
- Hit **Resume** or close the inspector to end the session

### Test users to use

From `test/e2e/fixtures/test-users.ts` — pick one per charter so we don't poison shared state:
- Charter A → existing exploratory user (create one if needed)
- Charter B → fresh user (interruption testing benefits from clean Hive)
- Charter C → user with multiple routines pre-seeded
- Charter D → user with at least one prior workout (PR baselines exist)

### Backend visibility while testing

Open in separate terminal so we can spot 400/500 errors and Sentry-worthy events:

```bash
docker logs -f supabase_kong_repsaga 2>&1 | grep -E "HTTP/[0-9.]+ [45][0-9]{2}"
```

---

## 5. Interaction matrix (what to probe per element)

Compressed from the code-explorer's full surface map. For exhaustive widget-by-widget detail with file:line refs, see [the explorer report attached to this commit's PR description].

| Surface | Affordance | Probe |
|---|---|---|
| **Active workout banner** (on home tabs) | tap | Goes to `/workout/active`. Confirm hidden after finish/discard. |
| **AppBar workout-name row** | tap | Enters edit mode (`TextField`). |
| **AppBar workout-name `TextField`** | type, submit, tap-outside | Persists to Hive immediately. 80-char limit. Empty → reverts. |
| **AppBar elapsed timer** | none | Ticks every second, MM:SS or H:MM:SS. Wall-clock based — survives bg. |
| **AppBar reorder toggle** | tap | Only when ≥2 exercises. Icon flips swap_vert ↔ done. |
| **AppBar discard / X button** | tap | Opens `DiscardWorkoutDialog`. |
| **Exercise card name row** | tap | Opens `_ExerciseDetailSheet` (DraggableScrollableSheet 0.85). |
| **Exercise card name row** | long-press | Opens `ExercisePickerSheet` to **swap** exercise; sets retained. |
| **Exercise card swap btn** | tap (normal mode) | Same as long-press above. |
| **Exercise card delete btn** | tap (normal mode) | Confirm dialog → `removeExercise()`. |
| **Exercise card up/down arrows** | tap (reorder mode) | `reorderExercise(±1)`. Disabled at edges. |
| **Set-number cell** | tap (set ≥ 2) | `copyLastSet()`. Underline decoration shows tap affordance. |
| **Set-number cell** | long-press | Cycle setType: working → warmup → dropset → failure. |
| **Set-type micro-label** (WK/WU/DR/FL) | none | Updates immediately on long-press cycle. |
| **Weight stepper ± buttons** | tap, long-press repeat | `updateSet(weight: ±step)`. Step varies by magnitude. |
| **Weight stepper value** | tap | Opens `AlertDialog` for keyboard input (decimal). |
| **Reps stepper ± buttons** | tap, long-press repeat | `updateSet(reps: ±1)`. |
| **Reps stepper value** | tap | Opens dialog for keyboard input (integer). |
| **Done-mark / ◆** | tap | `completeSet()`. Haptic. Triggers rest timer. 600ms lock on new sets. |
| **Set row** | swipe left | `Dismissible` → `deleteSet()` + undo snackbar. |
| **Add Set button** | tap | `addSet()` with smart defaults. |
| **Add Set button** | long-press | `fillRemainingSets()` — copies last completed values. |
| **Fill Remaining button** | tap | Same as long-press above (alternate affordance). |
| **Add Exercise FAB** | tap | Opens `ExercisePickerSheet`. |
| **Empty state CTA** | tap | Same as FAB. |
| **Picker search field** | type | 300ms debounce. |
| **Picker muscle chips** | tap | Mutually exclusive selection. |
| **Picker exercise tile** | tap | Pops sheet, returns selection → `addExercise()` or `swapExercise()`. |
| **Picker "Create exercise"** | tap | Pops sheet, navigates to `CreateExerciseScreen`. |
| **Finish button** | tap | Opens `FinishWorkoutDialog`. Disabled until ≥1 completed set. |
| **Finish dialog notes field** | type | Captured in result; max 1000 chars. |
| **Finish dialog "Save & Finish"** | tap | Triggers loading overlay → save → router branch. |
| **Finish dialog "Keep Going"** | tap | Closes dialog, stays on workout. |
| **Discard dialog "Discard"** | tap | `discardWorkout()` → `/home`. |
| **Discard dialog "Cancel"** | tap | Closes dialog, stays on workout. |
| **Rest timer ring + countdown** | none | Wall-clock, survives bg. Auto-dismiss 600ms after 0. |
| **Rest timer −30 button** | tap | `adjustTime(-30)`, clamps min 30s. |
| **Rest timer +30 button** | tap | `adjustTime(+30)`, clamps max 600s. |
| **Rest timer skip button** | tap | `skip()` → null state. |
| **Rest timer scrim** | tap (outside controls) | `stop()`. |
| **Loading overlay cancel** | tap (after 10s) | `cancelLoading()`. Only shown when `hasRestorable == true`. |
| **Add-to-plan sheet "Add"** | tap | Adds routine to weekly plan, → `/home`. |
| **Add-to-plan sheet "Skip"** | tap | → `/home`. |

---

## 5.5 Disabled-state matrix

Every control where state is conditional. For each row, probe: (a) the disabled visual cue is clear, (b) the enabled-after-condition transition is immediate (no stale), (c) tapping a disabled/hidden control produces no haptic / state change / a11y noise.

| Surface | Conditional state | Trigger | Visual cue when off |
|---|---|---|---|
| Finish workout button | enabled iff ≥1 completed set | `_hasCompletedSet == false` | 30% alpha violet bg + textDim label |
| FinishBottomBar | hidden | `exercises.isEmpty` | Not rendered |
| Add Exercise FAB | hidden | `exercises.isEmpty` (CTA in empty state instead) | Not rendered |
| Reorder toggle (AppBar) | hidden | `exercises.length < 2` | Not rendered |
| Reorder up arrow (per card) | disabled | `isFirst == true` | Greyed icon, no haptic on tap |
| Reorder down arrow (per card) | disabled | `isLast == true` | Greyed icon, no haptic on tap |
| Set-number cell tap (copy-last) | no-op | first set (set number 1) | No underline decoration on digit |
| Done-mark on newly-added set | locked | within 600ms of `addSet()` | No visual cue — silent ignore |
| Loading overlay cancel button | hidden | `<10s elapsed` OR `!hasRestorable` | Not rendered |
| Modal scrim during finish/discard | non-dismissible | `asyncState.isLoading == true` | Cannot tap-outside to dismiss |
| Picker "Create exercise" button | hidden | search input is empty | Not rendered |
| Fill Remaining button | hidden | no incomplete sets after last completed set | Not rendered |
| Steppers (weight/reps) on completed set | dimmed but tappable | `isCompleted && !isAccented` | 60% alpha |
| Steppers on accented set (predicted PR) | gold-tinted | `isAccented == true` | Gold accent, full alpha |
| Predicted PR ◆ unchecked-mark | replaces checkbox | row state == `pendingPredictedPr` | Gold ◆ instead of ☐ |
| Workout name `TextField` | only in edit mode | tap on static name | Static text shown otherwise |
| Picker exercise tile (already in workout) | (verify: is it disabled or shown but no-op?) | Charter C probe — current behavior unclear | TBD |
| `_ActiveWorkoutBanner` on home tabs | hidden | `activeWorkoutProvider.value == null` | Not rendered |

**Probe also:**
- A control that flips enabled in response to a state change (e.g., complete a set → finish button enables) must update on the same frame, no stale grey.
- Tapping a disabled control should produce zero haptic feedback (Android), zero ripple (Material), zero a11y announcement.
- A hidden control should NOT be in the keyboard tab order or in the screen-reader tree.

---

## 6. Charters

### Charter A — "Brutal set-row workout" (45 min) — Persona: Sam

**Goal:** Stress every interaction on the set row to find input-handling, gesture-conflict, and state-transition bugs.
**Heuristic:** SFDIPOT (Structure / Function / Data / Interfaces / Platform / Operations / Time).

**Setup:** Existing user with at least one prior workout for "Bench Press" (PR baseline exists for predicted-PR transitions).

**Probe:**
- Steppers: tap, long-press repeat, tap-to-type. Inputs: valid/invalid, decimals (`.` and `,`), negative, zero, leading zeros, very large (9999), very small (0.5), empty submit, only-whitespace, paste from clipboard.
- Set-type cycle: long-press 1 / 2 / 3 / 4 / 5+ times. Verify cycle order WK → WU → DR → FL → WK and color/abbreviation updates instantly.
- Done-mark: tap immediately after add (within 600ms), double-tap, tap during rest-timer countdown for an earlier set, tap on completed set (uncomplete → does PR state revert?), tap then immediately swipe to delete.
- Dismissible: swipe + tap undo within snackbar window (5s?), swipe + ignore (no undo, set permanently gone), swipe slow vs fast, swipe on completed vs incomplete vs predicted-PR row.
- Set-number tap (copy-last): set 1 (no-op), set 2 / 5 / 10+, after long-press cycle changed setType (does copy preserve setType?).
- All 5 PR row states reachable in one workout? Try to drive `pendingPredictedPr` → `completedStandingPr` → `completedSupersededPr` by adding more sets.
- Predicted PR ◆ unchecked-mark: tap to complete — does the gold-bordered ◆ smoothly become a checked ✓?
- Rapid-fire stepper: 10 increments in 2 seconds — does state stay coherent? does the screen jank?

**On smallest viewport (BR-1, 360×780) specifically:** are stepper tap targets ≥40×48dp per BUG-019?

**Multi-touch — Playwright caveat:** Playwright Web cannot reliably synthesize true multi-touch (two simultaneous fingers on different elements). For probes that genuinely need it, mark "real-device only" and defer to the Android device pass.
- ✅ Testable in Playwright web: rapid sequential taps (single finger, very fast), touch + keyboard combo, touch + scroll combo, long-press hold + touchend on same element.
- ❌ Real-device only: two-finger simultaneous tap on different rows, pinch on stepper, multi-finger swipe across set rows, 3-finger Samsung accessibility shortcut interrupting workout.

---

### Charter B — "Workout interruption survival" (45 min) — Persona: Jordan

**Goal:** Ensure no data loss across realistic interruptions.

**Setup:** Fresh user. Start a workout, log a few sets. Then force interruptions.

**Probe:**
- Background app at every state: mid-stepper-tap, mid-finish-dialog, mid-rest-timer, mid-loading-overlay, mid-picker-sheet, during set-type long-press hold.
- Force-quit (close browser tab) then reopen → resume banner shows? state intact?
- Rotate portrait ↔ landscape: layout breaks? state preserved? rest timer pauses or continues?
- Network drop offline mid-set update → online → finish → does Hive autosave + sync drain?
- Network drop mid-finish (after dialog confirm) → does it queue and snackbar correctly?
- Receive a notification (via test-utility), tap it — return to workout intact?
- Lock screen, unlock 10 minutes later → wakelock kept screen on? timer accurate?
- Open same user in second browser tab → start a new workout → what happens to tab A's active workout? to Hive?

**On smallest viewport:** does the offline banner + active-workout chrome + bottom nav still leave room for the set rows?

---

### Charter C — "Reorder + add + remove juggling" (30 min) — Persona: Alex

**Goal:** Find inconsistent state from rapid mutations to the exercise list.

**Setup:** Empty workout.

**Probe:**
- Add 5 exercises (mix bodyweight + weighted). Verify FAB and finish-bar reappear after first add. Verify reorder toggle appears at 2+.
- Swap exercise 3 (long-press → picker → select different) — sets retained? PR target updates to new exercise?
- Remove exercise 2 — set numbering on others stays correct? PR cache for removed exercise cleaned?
- Reorder via up/down — sequence updates immediately?
- Add same exercise twice (current behavior: appends second block) — verify expected.
- Long-press swap mid-rest-timer — does rest timer pause / dismiss / persist?
- Toggle reorder mode while a sub-modal is open (e.g., set-type long-press dialog if one exists, or detail sheet) — what wins?
- Bodyweight exercise → verify weight column hidden in headers + rows + steppers. Then swap to weighted exercise — does weight column re-appear in rows?
- After every removal, confirm `lastWorkoutSetsProvider` re-keys correctly (the family key includes exercise IDs).

---

### Charter D — "Finish-flow happy + sad paths" (45 min) — Persona: Sam

**Goal:** Validate every branch of the post-finish router.

**Branches to hit:**
1. Online + 0 PRs + ad-hoc workout → `/home` (no celebration, no prompt).
2. Online + ≥1 PR + ad-hoc → `/pr-celebration`.
3. Online + multiple PRs (different exercises, different types: heaviest-weight + most-reps) → all listed on celebration.
4. Online + 0 PRs + routine workout NOT in plan → add-to-plan sheet → `/home`.
5. Online + 0 PRs + routine workout already in plan → `/home` (no prompt).
6. Online + ≥1 PR + routine NOT in plan → celebration → plan prompt?
7. Online + tap overflow card on celebration → `/profile` (Saga sheet).
8. Offline + queued save → "Saved offline" snackbar (tertiaryContainer color), → `/home`. No celebration even if PRs would be detected.
9. Online + server 500 on save → "Failed to save workout" snackbar, stays on screen, retry possible?
10. Online → background mid-save (after dialog confirm) → return — celebration plays?
11. Tap finish twice rapidly within 300ms — only one save fires? (BUG: existing tests pin this for the dialog level, not the in-dialog Save button.)
12. Cancel from loading overlay (10s+ wait) — state restored? can we finish again?

**Notes-field probes (within #1):**
- Empty notes — saved as null?
- 1000 chars exactly — accepted?
- 1001 chars — truncated or rejected?
- Emojis — render in workout-detail screen later?
- Leading/trailing whitespace — trimmed?

---

### Charter E — "Offline / sync drain stress" (45 min) — Persona: Jordan

**Goal:** Find data-loss, duplication, dependency-chain, or stale-state bugs in the offline → online → drain pipeline. This is the highest-fragility area per the historical bug list (BUG-002, BUG-003, BUG-005, BUG-006, BUG-008, BUG-042 are all sync-related).

**Setup:** User with at least one prior workout (PR baselines exist). Browser DevTools Network tab open. A second terminal tailing Supabase API logs:

```bash
docker logs -f supabase_kong_repsaga 2>&1 | grep -E "HTTP/[0-9.]+ [45][0-9]{2}"
```

**Probe:**

#### Cold launch
- Cold launch online with pre-existing queue (PR #171 territory). Pre-seed 3 queued `PendingSaveWorkout` into Hive (via DevTools Application tab on `flutter.web.workout.queue`), reload. Drain starts automatically? Pending badge decrements smoothly? No double-drain on subsequent connectivity flap?

#### Steady-state offline
- Offline → start workout → log 3 sets → finish offline. Verify "Saved offline" snackbar in `tertiaryContainer` color, redirect to `/home`, pending badge increments by 1 (or 2 if PRs detected → separate `PendingUpsertRecords`).
- Reconnect online (toggle DevTools "Offline" off). Drain triggers automatically (NOT just on next manual flap)? Workout appears in history after drain completes?

#### Dependency chains
- Offline → create custom exercise via picker → use it in workout → finish offline → reconnect → drain. Custom exercise must persist BEFORE the workout that references it (BUG-002/003). Watch supabase logs for any FK violation (HTTP 409/400 on `personal_records_set_id_fkey` or `workout_exercises_exercise_id_fkey`).
- Offline → finish workout with new PRs → online → drain. Verify `PendingSaveWorkout` runs before `PendingUpsertRecords` (the PR action's `dependsOn` should hold it).

#### Concurrent state
- Offline → start workout → set → flip ONLINE mid-set → set again → finish online. Hive autosave + the optimistic state in `activeWorkoutProvider` — any double-save? Set count correct in workout-detail later?
- Offline + multiple workouts queued (back-to-back, unlikely but possible). Online. Drain order = FIFO?

#### Failure modes
- Offline → finish → online. Inject a server 4xx by manually editing the queued `PendingAction`'s payload to a known-invalid shape via DevTools Application tab (or take a known-bad seeded routine). Drain. Does it retry up to `kMaxSyncRetries` (6)? Does the failure card surface in the pending-sync sheet? Does "Dismiss" remove it from queue?
- Captive portal simulation: in DevTools Network, set throttle to "Offline" but for some requests use the "blocked" condition. Or simpler: kill the local Supabase container mid-drain (`docker stop supabase_kong_repsaga`). Does the drain bound the wait (the 30s timeout we shipped) or hang?

#### PR cache reconciliation (BUG-005/006)
- Detect a PR offline (heaviest weight on Bench Press). DON'T finish yet. Switch to a second tab as same user, finish a different workout that ALSO sets a higher PR on the same exercise (this is a stretch — may need to seed via direct DB write). Original tab finishes, drains. Whose PR wins? Cache stays consistent?

#### Visual / timing
- Offline banner: toggle wifi 5x in 5s. Banner debounces (no flicker)? Or does it strobe?
- "Saved offline" snackbar color: matches `tertiaryContainer` on each priority device? (BR-1 + US-2 minimum.)
- Pending sync badge: increments on enqueue immediately, decrements on dequeue immediately, NOT on next manual refresh.

#### Observability
- Browser DevTools Network → filter `sentry`. Do sync breadcrumbs (`category: 'sync'`, messages `Draining action`, `Holding action`, `Drain failed`) actually fire? If not, it's a Sentry-blind area.

---

### Charter F — "Accessibility, visual scale, and i18n" (45 min) — Personas: all

**Goal:** Catch a11y regressions, visual breakage at scale, and pt-BR overflow. Captures screenshot baselines for future visual-regression automation.

**Setup:** Browser at the priority viewport. DevTools Rendering panel open. A complete workout-in-progress with one PR-pending set (so all visual states are exercisable).

**Probe:**

#### Accessibility (web — VoiceOver on macOS / NVDA on Windows / Chromevox)
- **Tab-only navigation:** complete a workout using ONLY Tab + Enter + Space + Esc. Is the Tab order logical (top-down, left-right)? Can you reach every control? Can you Esc out of the picker / detail sheet / dialogs?
- **Focus management on modals:**
  - Open finish dialog — focus moves to first focusable (notes field or first button)?
  - Close — focus returns to the Finish button?
  - Same for picker (focus on search input?), detail sheet, discard dialog.
- **Focus traps:** while a modal is open, can Tab escape the modal? It shouldn't.
- **Screen-reader announcements:** turn on VoiceOver/NVDA, navigate set rows. Are PR states announced ("standing personal record", "predicted PR")? Set row read in sensible order?
- **Live regions:** when a set transitions PR state (e.g., another set supersedes it), is there an `aria-live` announcement?
- **Tap-target sizing:** every interactive element ≥40×48dp on smallest viewport (BR-1). Use Chrome DevTools "Inspect tap targets" overlay if available, otherwise eyeball.
- **`prefers-reduced-motion: reduce`** (DevTools → Rendering → Emulate CSS media feature): celebration animations, rest-timer ring sweep — should be shortened or skipped, not played at full duration.
- **Forced colors mode** (Windows high contrast, simulated via DevTools): does the app fall back gracefully? Any hardcoded color that should adapt?

#### Visual scale
- **Browser zoom 200%** — does any row break? Set row stays one-line? Steppers still tappable? Bottom nav still visible?
- **System font size XL** (use Chrome `--force-device-scale-factor`, or Android emulator with system font scale 130%): set row text wraps gracefully? Exercise name truncates with ellipsis or overflows?
- **Compounded:** smallest viewport (BR-1, 360×780) + browser zoom 150% = ~240px effective. Does the screen degrade gracefully or shatter?

#### Localization (en + pt-BR)
- Switch browser language to pt-BR (Chrome Settings → Languages, or `--lang=pt-BR` flag). Reload.
  - Confirm every label translates. Look for any string that stays in English (= missing l10n key — file an AW-EX bug).
  - Confirm pt-BR text doesn't overflow: Finish button label, Discard dialog title, "Save & Finish" button, "Keep Going" button, empty-state body, snackbar text. The Pixel 8 / S25 mainstream viewport (393–412 wide) is the realistic check; the 360-wide Galaxy A14 is the stress.
- **Decimal separator:** in pt-BR, the weight-stepper tap-to-type dialog should accept `102,5` as `102.5`. Does it also accept `102.5`? What if the user types `102,5.2` (mixed)? `WeightStepper` uses `AppNumberFormat.weight` — verify it round-trips correctly.
- **Number formatting in display:** `1.000,50` (pt-BR) vs `1,000.50` (en). Where is workout volume / weight totals shown?
- **Date in workout name fallback:** `"Workout — Wed Apr 2"` — localized to `"Treino — Qua 2 Abr"` in pt-BR?

#### Visual regression (screenshot capture)
For every charter end-state on every priority device, capture a screenshot to `tasks/active-workout-findings/screenshots/<charter-id>-<device-id>-<state>.png`. Suggested states per charter:
- Charter A: empty workout, mid-workout with mixed PR states, all sets complete
- Charter B: resume banner, offline banner active, loading overlay shown
- Charter C: reorder mode active, picker sheet open, swap dialog
- Charter D: finish dialog with notes filled, celebration screen, post-finish home
- Charter E: offline banner + active workout, pending-sync sheet, terminal-failure card
- Charter F: pt-BR rendering, 200% zoom, reduced-motion variant

These form the visual baseline. They are NOT compared automatically in this round — that's a future visual-regression suite.

---

## 7. UX-improvement notes — what to capture even when nothing is "broken"

Not every bug shows as a crash. Use this list to trigger a UX note:

- **Tap target sizes** on smallest viewport (BR-1) — anything <40dp×48dp is a flag.
- **Touch responsiveness** — any visible delay between tap and visual feedback.
- **Animation jank** — frame drops during state transitions (use Chrome DevTools Performance tab if needed).
- **Color contrast** — PR row chrome (gold/green) against background; "= last time" muted text legibility.
- **Information density** — does the set row feel cramped on 360×780?
- **Hidden affordances** — set-number tap-to-copy, long-press to cycle setType, long-press add-set to fill-remaining. Discoverability score (1-5) per affordance.
- **Hint text legibility** — "= last time" in muted text, "Previous: Nkg × R" hint, set-type micro-label.
- **Snackbar visibility** — does the undo snackbar appear behind active-workout chrome on small screens?
- **Rest timer ring readability** — countdown contrast, ring visibility at low remaining time, button reachability with thumb.
- **Error message clarity** — every snackbar/dialog error: is it actionable for a non-technical user?
- **Empty state copy quality** — first-time user sees the empty workout body — does it teach what to do next?
- **Navigation predictability** — after finish, does the user understand why they landed where they did? (PR celebration is celebratory — does it feel earned, or surprising?)

---

## 8. Capture templates

### Bug template

Save findings to `tasks/active-workout-findings.md` (create on first hit).

```markdown
### AW-EX-NN — <one-line summary>

- **Persona:** Alex / Jordan / Sam
- **Charter:** A / B / C / D
- **Device:** BR-1 / US-1 / etc.
- **Severity:** blocker (data loss, crash) / major (broken core flow) / minor (cosmetic) / nit
- **Repro steps:**
  1. ...
  2. ...
  3. ...
- **Expected:** ...
- **Actual:** ...
- **Backend / console errors:** any 4xx/5xx in supabase logs, any browser console errors, Sentry breadcrumb if visible
- **Notes:** workarounds, frequency (always / intermittent), related BUG-XXX if known
```

### UX-improvement template

```markdown
### AW-UX-NN — <one-line summary>

- **Surface:** which widget/screen
- **Device:** which viewport revealed it
- **Issue:** what feels off
- **Proposed direction:** rough idea, NOT a final solution (we triage later)
- **Severity:** annoyance / friction / silent-failure
```

---

## 9. Timeboxing

Choose based on available time. Charters now total six (A–F); plan sessions accordingly.

| Time | Coverage |
|---|---|
| **1h smoke** | Charter A only, on BR-1 (smallest stress) |
| **2h focused** | Charters A + E (set-row + offline) on US-1 |
| **4h standard** | Charters A, B, D, E on US-1 |
| **6h thorough** | All 6 charters (A–F) on US-1 |
| **10h full** | All 6 charters on BR-1 + US-1 + US-2 (smallest + mainstream + largest) |
| **16h+ comprehensive** | All 6 charters × 4 priority devices (BR-1, BR-2, US-1, US-2) |

Triage runs alongside but separately: don't pause a charter to fix bugs — log first, fix in a later round.

After exploration, the deliverable is `tasks/active-workout-findings.md`. The triage round (separate session) decides which findings become bug fixes, which become UX-improvement PRs, which are deferred to a future phase, and which are accepted as-is.

---

## 10. Out of scope for this round

- Writing new automated E2E tests for findings — that's the triage / fix round
- Performance profiling beyond targeted DevTools probes — Lighthouse / frame-rate analysis is a separate exercise
- **Real multi-touch beyond what Playwright web supports** — true 2-finger / pinch / multi-finger swipe needs a dedicated Android-on-device pass with `flutter run` or a real Playwright-Android setup
- **Native iOS Safari / real Android Chrome WebView** — the web build via Playwright is the agreed surface. Native release APK testing is its own pass (we have the APK already installed on a Galaxy S25 Ultra from the earlier session — use it for an Android-supplemental pass if findings warrant)
- System-level a11y (Android Switch Control, iOS Voice Control) — out of scope unless a feature is built specifically for it
- Foldable / split-screen / multi-window layouts — separate concern
- Automated visual regression (screenshot diffing) — we capture baselines this round but don't diff them yet
