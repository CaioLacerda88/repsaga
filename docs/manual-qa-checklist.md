# Manual Exploratory QA Test Plan

**App:** RepSaga
**Date:** 2026-04-09
**Scope:** All shipped features -- Auth, Exercise Library, Workout Logging, Routines, Personal Records, Weekly Plan, Home Screen, Profile
**Tester mindset:** Gym-goer between sets. Sweaty hands. In a hurry. Will tap wrong things.

> **Active Workout deep dive:** for a single-screen exploratory pass on the active workout surface (charters, device matrix, capture templates), see [`active-workout-exploratory-testplan.md`](active-workout-exploratory-testplan.md). The plan in this file covers the broader 12-journey app survey.

---

## Personas

- **Alex (Beginner)** -- First week using the app. No history. Exploring everything.
- **Jordan (Consistent Lifter)** -- Logs 4x/week. Has 20+ past workouts, existing routines, a weekly plan.
- **Sam (Data Nerd)** -- Tracks PRs obsessively. Compares week-over-week volume. Notices wrong numbers immediately.

---

## Journey 1 -- First-Time User Onboarding to First Workout

**Persona:** Alex (Beginner)
**Goal:** Sign up and complete a real workout within the first session.

### Steps

1. Open the app cold (no existing account).
2. Tap "Create account". Enter a valid email and password (min length). Submit.
3. Complete the onboarding flow -- set a display name, choose a training frequency.
4. Land on the Home screen. Observe the THIS WEEK section and the "Create Your First Routine" CTA.
5. Tap "Start Empty Workout" instead.
6. On the active workout screen -- tap "Add Exercise".
7. Search for "Bench Press". Select it.
8. Enter weight and reps for Set 1. Tap the checkmark to complete the set.
9. Add a second set using "+ Add Set".
10. Complete the second set.
11. Tap "Finish Workout".
12. Observe the finish dialog -- dismiss any incomplete sets warning.
13. If a PR was achieved: go through the PR celebration screen.
14. Confirm you land on Home.

### What to Verify

- Account creation succeeds; no error on valid input.
- Onboarding screen appears exactly once on first login.
- Home shows "Create Your First Routine" CTA when no routines exist.
- Active workout timer starts immediately and ticks every second.
- Set row accepts weight and reps; tapping checkmark marks the set complete (visual change).
- "Finish Workout" button is disabled until at least one set is completed.
- After finish, "Last session" stat card on Home updates to today.
- Workout count on Profile increments by 1.

### Edge Cases to Probe

- Submit signup with a password that is too short -- error message must be clear.
- Submit signup with an already-registered email -- error must not say "unexpected error".
- Tap "Finish Workout" immediately after starting with no exercises -- button must be disabled.
- Start a workout, add one exercise, complete zero sets -- Finish button stays disabled.
- Kill and relaunch the app mid-workout -- confirm the active workout is still in progress on relaunch.

---

## Journey 2 -- Resume Interrupted Workout

**Persona:** Jordan (Consistent Lifter)
**Goal:** Return to a workout after the phone screen turned off or the app was backgrounded.

### Steps

1. Start an empty workout from Home.
2. Add one exercise and complete one set.
3. Background the app for 30 seconds. Return to it.
4. Verify the workout is still active and the timer has continued.
5. Go to Home (tap the X / back icon), choose "Resume" on the dialog.
6. Confirm you are back on the active workout screen.
7. Now tap X again, choose "Discard". Confirm the dialog warns about the elapsed time and sets logged.
8. Confirm you land on Home and the workout is gone.

### What to Verify

- The ResumeWorkoutDialog appears when tapping "Start Empty Workout" while one is already in progress.
- "Resume" navigates back to the active workout at the exact same state.
- "Discard" clears the workout; Home no longer shows a resume prompt.
- "Cancel" (dismiss dialog) leaves the workout intact.
- After discard, "Last session" stat does NOT update (discarded workouts must not be saved).

### Edge Cases to Probe

- Background for 10+ minutes. Return. Timer should reflect real elapsed time, not frozen.
- Discard, then immediately tap "Start Empty Workout" -- must start fresh with no ghost state.
- Tap the Android physical back button on the active workout screen -- must trigger the discard dialog, not navigate away silently.

---

## Journey 3 -- Log a Full Routine Workout (Core Daily Loop)

**Persona:** Jordan (Consistent Lifter)
**Goal:** Start from a saved routine, log all sets, and finish in under 3 minutes of tapping.

### Steps

1. From Home, observe the "MY ROUTINES" section (or a routine chip in THIS WEEK).
2. Tap a routine card (e.g., "Push Day").
3. Active workout screen loads with exercises pre-populated from the routine.
4. For the first exercise, log 3 sets of weight + reps. Complete each.
5. For the second exercise, enter weight only for Set 1. Tap "Fill Remaining" to copy weight to all other sets.
6. Complete all sets in exercise 2.
7. Add a new exercise mid-workout using the FAB.
8. Complete at least one set for the new exercise.
9. Tap "Finish Workout". Add an optional note in the dialog. Confirm.
10. Observe: PR celebration screen (if a record was broken) or Home.

### What to Verify

- Pre-populated exercises match the routine's exercise list and order.
- "Fill Remaining" copies the same weight/reps to all incomplete sets in that exercise.
- FAB for adding exercise is visible when exercises exist.
- Notes entered in the finish dialog are saved (verify via workout history).
- After finish: Home "Last session" reflects the routine name and today's date.
- After finish: "Week's volume" on Home increases by the workout's total volume.

### Edge Cases to Probe

- Routine has 8+ exercises -- scroll down to verify all are present and the FAB/Finish button are not obscured.
- Attempt to add the same exercise twice in one workout -- confirm it appends a second block (not silently ignored).
- Enter 0 for weight -- does the set accept it? (bodyweight exercises).
- Enter a decimal weight (e.g., 102.5 kg) -- verify it persists exactly without rounding.

---

## Journey 4 -- Personal Record Detection and Cross-Feature Update

**Persona:** Sam (Data Nerd)
**Goal:** Confirm that a PR is correctly detected and reflected everywhere after a workout.

### Steps

1. Check the Records screen before the workout. Note the current heaviest weight PR for one specific exercise (e.g., Bench Press).
2. Start an empty workout. Add that same exercise.
3. Log a weight 5 kg heavier than the known PR. Complete the set.
4. Finish the workout.
5. If PR celebration shows: verify the correct exercise name and new record value are displayed.
6. Navigate to the Records screen.
7. Confirm the new PR is listed with correct weight, date, and "heaviest weight" badge.
8. Navigate to Profile. Confirm the PR count incremented.

### What to Verify

- PR celebration screen appears automatically when a new record is set.
- The celebration screen names the correct exercise and shows the correct value.
- Records screen shows the updated value immediately (no stale cache).
- Profile PR count reflects the new total.
- A workout with NO new PR goes directly to Home -- no false celebration screen.

### Edge Cases to Probe

- Log the exact same weight as an existing PR -- should NOT trigger a new PR (it must be strictly heavier/more).
- Break two PRs in one workout (e.g., heaviest weight AND most reps on different exercises) -- both should appear.
- Break a PR, go to Home, then navigate to Records -- data must still be correct (not just an in-memory artifact).
- First ever set for an exercise -- must be recorded as a PR (there is no prior bar to clear).

---

## Journey 5 -- Weekly Plan Setup and Completion Tracking

**Persona:** Jordan (Consistent Lifter)
**Goal:** Plan a full week, complete workouts, and see the week close out.

### Steps

1. From Home, tap the "Plan your week" empty state (or the edit icon on THIS WEEK).
2. On Plan Management screen: tap "Add Routines". Select 3 routines (e.g., Push, Pull, Legs).
3. Tap back. Observe the THIS WEEK section shows 3 chips with "0 of 3" progress.
4. Tap the first routine chip ("Up next" card). Complete a full workout from it.
5. After finishing: return to Home. Verify the chip for that routine shows a checkmark and progress reads "1 of 3".
6. Repeat for a second routine.
7. Go to Plan Management. Reorder routines by dragging. Verify sequence numbers update on Home.
8. Complete the third routine.
9. Verify the THIS WEEK section transforms to "WEEK COMPLETE" with a weekly review.
10. Tap "New Week" (or equivalent CTA). Confirm the plan resets.

### What to Verify

- Completing a workout marks the correct chip as done (matched by routine ID, not name).
- Progress counter increments correctly after each workout.
- Reordering in Plan Management immediately reflects on Home chips.
- WEEK COMPLETE state shows correct total volume and PR count for the week.
- "New Week" resets all completion states but retains the plan structure.

### Edge Cases to Probe

- Add the same routine twice to the plan -- the sheet should exclude already-added routines.
- Complete a workout from a routine that is NOT in this week's plan -- the chip counters must not change.
- Swipe-to-dismiss a completed routine in Plan Management -- the dismiss gesture should be disabled for done items.
- Delete a routine from the Routines tab that is currently in the weekly plan -- verify the plan screen handles the missing routine gracefully (no crash, shows "Unknown Routine" or similar).

---

## Journey 6 -- Weekly Plan Auto-Fill and Confirmation Banner

**Persona:** Jordan (Consistent Lifter)
**Goal:** Use auto-fill to populate next week's plan from workout history.

### Steps

1. Ensure at least 5 past workouts exist across different routines (Jordan's account should have this).
2. Navigate to Plan Management. If a plan exists, note the current routines.
3. Tap the overflow menu (three dots). Tap "Auto-fill".
4. If a plan already exists: confirm the replacement dialog appears. Confirm replacement.
5. Verify that the auto-filled plan contains the most-frequently-used routines, up to the training frequency count.
6. Return to Home.
7. Observe whether the "Same plan this week?" confirmation banner appears (expected if this is a repeat week).
8. Tap "Confirm" on the banner. Verify it disappears.
9. Repeat auto-fill on an account with NO workout history. Verify it falls back gracefully (alphabetical, no crash).

### What to Verify

- Auto-fill picks routines by frequency, not alphabetically.
- Number of auto-filled routines matches the training frequency setting in Profile.
- Confirmation banner only appears for auto-populated weeks (not manually created plans).
- Tapping "Edit" on the confirmation banner navigates to Plan Management.
- Tapping "Confirm" dismisses the banner permanently for the current week.

### Edge Cases to Probe

- Auto-fill when only 1 routine exists and training frequency is 4 -- must fill 1 slot, not crash trying to fill 4.
- Auto-fill on a new account with zero history -- should not hang or show a loading spinner indefinitely.
- Change training frequency in Profile from 3x to 5x, then auto-fill -- plan should populate up to 5 slots.

---

## Journey 7 -- Exercise Library Search and Filter

**Persona:** Alex (Beginner)
**Goal:** Find an unfamiliar exercise, view its details, and add it to a workout.

### Steps

1. Navigate to the Exercises tab.
2. Observe the full unfiltered list. Verify muscle group images render.
3. Tap a muscle group chip (e.g., "Chest"). List filters in real time.
4. Type "fly" in the search bar. Verify results update after a brief debounce (300ms).
5. Select an equipment type filter (e.g., "Dumbbell"). Verify combined filtering works.
6. Tap an exercise. Verify the detail screen shows name, muscle group, and equipment.
7. Navigate back. Clear all filters using the clear action.
8. Search for a string with no results (e.g., "zzzzz"). Verify the empty state appears with a "clear filters" option.
9. Start a workout. Open the exercise picker sheet. Repeat search -- confirm the same filtering works inside the picker.

### What to Verify

- Muscle group filter is mutually exclusive (selecting a new one deselects the previous).
- Search debounce fires after ~300ms, not on every keystroke.
- Empty state clearly distinguishes "no results for filters" from "no exercises at all".
- Clearing all filters restores the full list.
- Exercise picker inside active workout uses the same search/filter experience.

### Edge Cases to Probe

- Search with leading/trailing whitespace -- should trim and not return zero results when results exist.
- Switch between muscle group chips rapidly -- no race condition producing wrong list.
- Very long exercise name -- verify it truncates properly in the list tile, not overflow.
- Navigate away from Exercises tab mid-search, return -- verify search state (either resets cleanly or persists predictably).

---

## Journey 8 -- Profile Settings Persist Across Sessions

**Persona:** Sam (Data Nerd)
**Goal:** Verify that weight unit and training frequency changes survive logout/login.

### Steps

1. Navigate to Profile.
2. Change weight unit from "kg" to "lbs".
3. Change training frequency from 3x to 5x per week.
4. Edit the display name to a new value.
5. Return to Home. Verify volume stat card now shows "lbs".
6. Log out (tap "Log Out", confirm).
7. Log back in with the same credentials.
8. Navigate to Profile. Verify: display name is correct, weight unit is "lbs", frequency is "5x".
9. Navigate to Home. Confirm volume is still shown in "lbs".
10. Go to Plan Management. Verify the training frequency cap is now 5 (counter shows x/5).

### What to Verify

- All three profile fields persist to the backend and survive a full logout/login cycle.
- Home screen "Week's volume" respects the selected weight unit immediately after change.
- Plan Management soft cap reflects the updated training frequency immediately.
- Display name shown in Home header updates without requiring a restart.

### Edge Cases to Probe

- Set display name to an empty string via the edit dialog -- save button or submission should be blocked.
- Rapidly toggle kg/lbs back and forth -- no stale state where the UI shows one but the backend stores another.
- Change frequency from 5x to 2x when 4 routines are already in the plan -- plan screen should show "goal reached" at 2/5 but not strip existing routines automatically.

---

## Journey 9 -- Workout History and Stats Consistency

**Persona:** Sam (Data Nerd)
**Goal:** Confirm that completed workouts appear in history and all derived stats are consistent.

### Steps

1. On Home, note the current "Last session" value and "Week's volume" value.
2. Complete a new workout with 3 exercises, logging a total of ~5000 kg volume.
3. Return to Home. Verify "Last session" shows today's date and the workout name. Verify "Week's volume" has increased.
4. Tap the "Last session" stat card -- verify it navigates to workout history.
5. In history, find the just-completed workout. Verify exercise count and name are correct.
6. Go to Profile. Verify workout count has incremented.
7. Repeat: complete a second workout the same day. Verify "Week's volume" is cumulative (both workouts summed).

### What to Verify

- "Last session" always shows the most recent workout, not the second most recent.
- Week volume correctly sums ALL workouts for the current calendar week.
- History list is sorted newest-first.
- Profile workout count matches the number of items in history.

### Edge Cases to Probe

- Complete a workout at exactly 23:59. Confirm it belongs to the correct day in history.
- If the app's week resets on Monday: complete a workout Sunday, check stats Monday -- prior week's workout must not pollute the new week's volume.
- Delete account data (Manage Data screen) -- all stats must reset to zero, no orphaned numbers.

---

## Journey 10 -- Routine Creation, Edit, and Reorder

**Persona:** Jordan (Consistent Lifter)
**Goal:** Build a new routine from scratch, modify it, and use it in a workout.

### Steps

1. Navigate to Routines tab (or use the "Create Your First Routine" CTA on Home).
2. Create a new routine named "Upper Body A". Add 4 exercises via the exercise picker.
3. Save the routine. Verify it appears under "MY ROUTINES" on Home (if no weekly plan is active).
4. Long-press the routine card. Verify the action sheet appears with Edit, Delete options.
5. Tap "Edit". Reorder exercises 1 and 3. Remove exercise 2. Add a new exercise.
6. Save. Start a workout from this routine. Verify the exercise order matches the edited state.
7. Long-press again. Tap "Delete". Confirm deletion dialog. Verify the routine is removed from Home and Routines tab.

### What to Verify

- Newly created routine appears immediately without requiring a restart or manual refresh.
- Edit changes (reorder, add, remove) persist and are reflected in the next workout.
- Routine card on Home shows the correct exercise count after editing.
- Deletion is confirmed before executing (no accidental one-tap delete).
- After deletion, if the routine was in the weekly plan, Plan Management handles it gracefully.

### Edge Cases to Probe

- Create a routine with a name that is 100+ characters -- verify it truncates in the card without overflow.
- Attempt to save a routine with zero exercises -- check if this is blocked or allowed (and what the downstream effect is if allowed).
- Edit a routine that is currently the "Up next" suggestion on Home -- suggestion card must not crash.

---

## Journey 11 -- Back Navigation and Data Persistence Under Interruption

**Persona:** Alex (Beginner) -- prone to accidental back taps.
**Goal:** Ensure the app does not lose data on typical accidental navigation patterns.

### Steps

1. Start a workout. Add 2 exercises, complete 4 sets total.
2. Tap the Android physical back button. Verify the Discard dialog appears (NOT a silent back navigation).
3. Cancel the dialog. Verify you're back on the active workout with all sets intact.
4. Navigate to Exercises tab (if bottom nav is accessible during a workout -- confirm it is NOT, or that it shows a reminder).
5. On Profile, begin editing the display name in the dialog. Tap outside the dialog (tap backdrop). Verify the dialog closes without saving the partial input.
6. On Plan Management, add 2 routines. Do NOT tap save (if save is explicit) -- tap back. Verify whether changes were auto-saved (bucket model saves immediately) or discarded.
7. Force-quit the app mid-workout. Relaunch. Verify the active workout resumes from its last synced state.

### What to Verify

- Active workout screen blocks accidental back navigation with a confirmation dialog.
- Plan Management saves immediately on each change (no explicit save button -- changes are live).
- Display name dialog: tapping cancel or backdrop dismisses without saving.
- App relaunch restores active workout state (Supabase-backed persistence).

### Edge Cases to Probe

- Go back from Plan Management immediately after auto-fill -- confirm the auto-filled plan was saved before leaving.
- Dismiss the "Discard workout" dialog by tapping outside it -- workout must remain active.
- Edit workout name in the active workout screen, then background the app. Relaunch. Verify the custom name persisted.

---

## Journey 12 -- New User with Starter Routines (Onboarding to First Plan)

**Persona:** Alex (Beginner)
**Goal:** Verify the full new-user funnel: starter routines visible, plan created, first workout logged.

### Steps

1. Log in as a fresh account with no custom routines.
2. Observe Home: "Create Your First Routine" CTA should be absent IF starter (default) routines are available; instead "STARTER ROUTINES" section should be visible.
3. Tap the "Plan your week" empty state.
4. On Plan Management: tap "Add Routines". Verify starter routines (Push Day, Pull Day, Leg Day) are available to add.
5. Add Push Day and Pull Day. Tap back.
6. Verify THIS WEEK shows 2 chips and "0 of 2" progress.
7. Tap the "Up next" card (Push Day). Complete the workout.
8. Verify: Push Day chip is checked, progress shows "1 of 2", SuggestedNextCard now shows "Pull Day".
9. Tap the SuggestedNextCard. Verify it launches Pull Day workout directly.

### What to Verify

- Starter routines appear on Home under "STARTER ROUTINES" for brand new accounts.
- Starter routines are available in the Add Routines sheet for the weekly plan.
- "Create Your First Routine" CTA is shown ONLY when there are zero routines (including no starter routines). It must NOT appear alongside starter routines.
- After completing a plan routine, the suggested next workout updates to the next incomplete bucket item.
- Tapping the SuggestedNextCard starts a workout from that routine directly.

### Edge Cases to Probe

- Both starter routines done; no more remaining -- SuggestedNextCard should disappear, not show a null/crashed card.
- User has no starter routines but creates a custom routine -- "Create Your First Routine" CTA must not show (it should only appear when the routine list is completely empty).
- Starter routine tapped from Home when a weekly plan IS active -- plan chips should work, Home routines section hidden; starter routine cards should not conflict.

---

## Cross-Cutting Checks (Run on Every Journey)

These are not separate journeys but must be verified incidentally during every session:

| Check | What to look for |
|---|---|
| Loading states | Spinners never freeze permanently; skeleton/loading UI shows while data loads |
| Error states | Network-style errors show a message, not a blank screen or crash |
| Empty states | Every list with no data has an explicit empty state (no blank white space) |
| Scroll position | Long lists scroll smoothly; no jump or reset on returning to a screen |
| Weight unit consistency | All weight values across Home, Active Workout, History, PRs, and Profile use the selected unit |
| Elapsed timer | Timer on active workout screen never goes backwards or freezes |
| Snackbar undo | "Routine removed" undo snackbar works within its 5-second window; tapping after it expires does nothing |
| Orientation | App usable in portrait; landscape should not break layouts (stretch test, not a requirement) |
| Rapid tapping | Tap "Finish Workout" twice rapidly -- only one save request fires |

---

## Priority Order for a 2-Hour QA Session

If time is limited, run journeys in this order:

1. Journey 3 -- Core daily loop (highest frequency action)
2. Journey 4 -- PR detection (highest emotional stakes; bugs here cause trust loss)
3. Journey 5 -- Weekly plan completion tracking (cross-feature; most state interactions)
4. Journey 2 -- Resume interrupted workout (common real-world scenario)
5. Journey 1 -- New user onboarding (acquisition funnel)
6. Journey 11 -- Back navigation (silent data loss is a top churn driver)
7. Remaining journeys as time permits

---

## Implementation Notes

- **Finish Workout gated on `_hasCompletedSet`** -- button is disabled until at least one set is completed. Test explicitly in Journey 1.
- **Discard dialog shows elapsed time** -- live calculation from `startedAt`. Verify accuracy in Journey 2.
- **Plan Management auto-saves** -- `_savePlan()` called after every mutation with no debounce. No explicit save button.
- **Starter routines visibility** -- `hasActivePlan` hides the routines section entirely on Home. "Create Your First Routine" CTA only appears with zero routines AND no active plan.
