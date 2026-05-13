/**
 * Workouts — consolidated E2E tests.
 *
 * Sources:
 *   - smoke/workout.smoke.spec.ts          (smokeWorkout, 5 tests)       -> @smoke
 *   - smoke/workout-restore.smoke.spec.ts  (smokeWorkoutRestore, 2 tests) -> @smoke
 *   - full/workout-logging.spec.ts         (fullWorkout, 14 tests)       -> untagged
 *   - full/history.spec.ts                 (fullHistory, 1 test)         -> untagged
 */

import { test, expect } from '@playwright/test';
import { dismissCelebrationIfPresent, flutterFill, waitForAppReady } from '../helpers/app';
import { login } from '../helpers/auth';
import { NAV, WORKOUT, HOME, HISTORY, FIRST_WORKOUT_CTA, EXERCISE_PICKER, SET_ROW } from '../helpers/selectors';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
  finishWorkout,
} from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';

// =============================================================================
// SMOKE — Workout core journey (smokeWorkout user)
// =============================================================================

test.describe('Workouts', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkout').email,
      getUser('smokeWorkout').password,
    );
  });

  test('should save workout successfully on completion and show celebration or home (QA-001)', async ({
    page,
  }) => {
    // Start an empty workout.
    await startEmptyWorkout(page);

    // Add Barbell Bench Press (BUG-020: Finish button hidden on empty body).
    await addExercise(page, SEED_EXERCISES.benchPress);

    // After adding, the Finish button becomes visible in the bottom bar.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // Wait for the exercise card with its set row. Use .first() to guard
    // against strict mode violation when the workout starts with pre-filled
    // exercises (brand-new state starts Full Body with multiple exercises).
    await expect(page.locator(WORKOUT.addSetButton).first()).toBeVisible({
      timeout: 10_000,
    });

    // Set weight and reps on the first set.
    await setWeight(page, '60');
    await setReps(page, '8');

    // Mark the set as done.
    await completeSet(page, 0);

    // Finish the workout — this triggers the save_workout RPC.
    await finishWorkout(page);

    // After finishing, either the PR celebration or the home screen must
    // appear. Both indicate a successful save. Neither should be a 404 error.
    // Use URL-based detection to avoid the ScaleTransition visibility race.
    await dismissCelebrationIfPresent(page);

    // We must end up on the Home screen — proves navigation completed.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
  });

  test('should show home screen with a workout entry point after login', async ({
    page,
  }) => {
    // After login the home screen should be visible with the navigation bar
    // and a way to start a workout. W8: the "Start Empty Workout" button was
    // replaced — the home screen shows either:
    //   • "Quick workout" (lapsed state, has history)
    //   • "YOUR FIRST WORKOUT" card (brand-new, no history)
    //
    // Use waitFor() (retrying) rather than isVisible() (one-shot check) so the
    // test properly waits for the ActionHero to render after the provider loads.
    await expect(page.locator(NAV.homeTab)).toBeVisible();
    const hasQuickWorkout = await page
      .locator(HOME.quickWorkout)
      .first()
      .waitFor({ state: 'visible', timeout: 10_000 })
      .then(() => true)
      .catch(() => false);
    // Flutter AOM exposes the hero card as a button — use the card selector
    // (role=button[name*="YOUR FIRST WORKOUT"]) not the plain text selector
    // (text=) which only matches DOM text nodes, not aria-labels.
    const hasBeginnerCta = await page
      .locator(FIRST_WORKOUT_CTA.card)
      .first()
      .waitFor({ state: 'visible', timeout: 5_000 })
      .then(() => true)
      .catch(() => false);
    expect(hasQuickWorkout || hasBeginnerCta).toBe(true);
  });

  test('should complete full workout journey: start, add exercise, set weight/reps, complete set, finish', async ({
    page,
  }) => {
    // 1. Start an empty workout from the home screen.
    await startEmptyWorkout(page);

    // 2. Add Barbell Bench Press from the exercise picker.
    // BUG-020: Finish button is hidden until exercises exist; add first.
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Active workout screen is visible — finish button appears in the bottom
    // bar now that an exercise exists.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });

    // After adding, an exercise card with at least one set row should appear.
    // The add-set button confirms the exercise card is rendered. Use .first()
    // to avoid strict mode violations when multiple exercises are present.
    await expect(page.locator(WORKOUT.addSetButton).first()).toBeVisible({
      timeout: 10_000,
    });

    // 3. The first set row is pre-populated with "0" for weight and reps.
    //    Use the setWeight / setReps helpers which tap the value text,
    //    interact with the AlertDialog, and dismiss it.
    await setWeight(page, '60');
    await setReps(page, '8');

    // 4. Mark the set as done.
    await completeSet(page, 0);

    // 5. Finish the workout.
    await finishWorkout(page);

    // After finishing, the app navigates to the PR celebration screen (first
    // workout) or back to Home. Use URL-based detection to avoid the
    // ScaleTransition visibility race on PR heading identifiers.
    await dismissCelebrationIfPresent(page);

    // We should now be on the Home screen.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should update stat card on home screen after finishing workout', async ({
    page,
  }) => {
    // Complete a minimal workout — the Finish button is disabled until at
    // least one set is marked as done.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '50');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss PR / celebration screen if shown. Uses URL-based detection to
    // avoid the ScaleTransition visibility race.
    await dismissCelebrationIfPresent(page);

    // Back on Home — the contextual stat cells should be visible.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // The home screen was redesigned in Step 12.2b: lifetime stat cards
    // ("Workouts", "Records") were removed in favour of contextual stat cells
    // ("Last session" + "Week's volume"). Assert the new contextual stat cell
    // labels are present — this confirms the home screen rendered after save.
    await expect(page.locator('text=Last session')).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should return to home without saving when discarding a workout', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // Click the Discard button (available in the AppBar or overflow menu).
    const discardButton = page.locator(WORKOUT.discardButton);
    const isDirectlyVisible = await discardButton
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!isDirectlyVisible) {
      // Try the overflow / back action to expose discard.
      const overflowMenu = page.locator('role=button[name="More options"]');
      if (
        await overflowMenu.isVisible({ timeout: 3_000 }).catch(() => false)
      ) {
        await overflowMenu.click();
      }
    }

    await page.locator(WORKOUT.discardButton).click();

    // A confirmation dialog appears — confirm discard.
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();

    // Should navigate back to Home.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

// =============================================================================
// SMOKE — Workout restore (smokeWorkoutRestore user, BUG-001)
// =============================================================================

test.describe('Workout restore', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutRestore').email,
      getUser('smokeWorkoutRestore').password,
    );
  });

  test('should preserve manually-added exercise name after page reload (BUG-001)', async ({
    page,
  }) => {
    // Start a manual (empty) workout and add Barbell Bench Press.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Confirm the exercise card is visible before reload via its accessible name.
    // Flutter CanvasKit draws text to canvas so text= selectors fail for zero-dimension
    // flt-semantics elements. The _ExerciseCard Semantics label (via AOM) is reliable.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });

    // Simulate app restore by reloading (preserves IndexedDB/Hive state).
    await page.reload();

    // After a reload, Flutter must re-initialise its semantics tree.
    // waitForAppReady() enables accessibility and waits for auth to resolve.
    // document.body.innerText is empty in CanvasKit (text drawn to canvas),
    // so a plain waitForFunction on innerText would never fire.
    await waitForAppReady(page);

    // If the active workout screen was not re-entered automatically, navigate
    // back via the active workout banner or resume link.
    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!finishVisible) {
      const activeBannerVisible = await page
        .locator(HOME.activeBanner)
        .isVisible({ timeout: 10_000 })
        .catch(() => false);

      if (activeBannerVisible) {
        await page.locator(HOME.activeBanner).click();
      } else {
        const resumeVisible = await page
          .locator('text=Resume')
          .isVisible({ timeout: 5_000 })
          .catch(() => false);
        if (resumeVisible) {
          await page.locator('text=Resume').click();
        }
      }

      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
    }

    // KEY ASSERTION FOR BUG-001:
    // The fallback name "Exercise: Exercise. Tap for details." must NOT
    // be present. That pattern only appears when exercise was null on restore.
    const fallbackLabel = page.locator(
      'role=group[name*="Exercise: Exercise. Tap for details"]',
    );
    await expect(fallbackLabel).not.toBeVisible({ timeout: 3_000 });

    // The real exercise name must be visible as the card heading via its
    // Semantics accessible name. text= selectors fail for CanvasKit zero-dimension
    // flt-semantics elements — the role=button[name=...] selector is reliable.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });

    // Clean up by discarding.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show correct names for multiple manually-added exercises after reload (BUG-001)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await addExercise(page, SEED_EXERCISES.squat);

    // Both exercise cards must be visible before reload via their Semantics accessible names.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.squat}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });

    // Reload to simulate restore.
    await page.reload();

    // waitForAppReady re-enables semantics after reload and waits for auth.
    await waitForAppReady(page);

    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!finishVisible) {
      const activeBannerVisible = await page
        .locator(HOME.activeBanner)
        .isVisible({ timeout: 10_000 })
        .catch(() => false);

      if (activeBannerVisible) {
        await page.locator(HOME.activeBanner).click();
      } else {
        const resumeVisible = await page
          .locator('text=Resume')
          .isVisible({ timeout: 5_000 })
          .catch(() => false);
        if (resumeVisible) {
          await page.locator('text=Resume').click();
        }
      }

      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
    }

    // Neither card should show the "Exercise" fallback accessible name.
    const fallbackLabel = page.locator(
      'role=group[name*="Exercise: Exercise. Tap for details"]',
    );
    await expect(fallbackLabel).not.toBeVisible({ timeout: 3_000 });

    // Both real names must still be visible via their Semantics accessible names.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.squat}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

// =============================================================================
// FULL — Workout logging (fullWorkout user)
// =============================================================================

test.describe('Workout logging', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullWorkout').email,
      getUser('fullWorkout').password,
    );
  });

  test('should show Add Exercise button on empty workout and Finish button after adding exercise', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // BUG-020: Finish button is hidden on the empty workout body — the bottom
    // bar (_FinishBottomBar) only renders when exercises.isNotEmpty. The empty
    // body owns its own CTA (Add Exercise) as the sole action.
    await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible();
    await expect(page.locator(WORKOUT.finishButton)).not.toBeVisible();

    // Add an exercise — now the bottom bar should appear.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });

    // Clean up by discarding.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show both exercise cards when adding multiple exercises', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // Add Barbell Bench Press.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.addSetButton).first()).toBeVisible({
      timeout: 10_000,
    });

    // Add Barbell Squat.
    await addExercise(page, SEED_EXERCISES.squat);

    // Both exercise names must appear as card headings.
    // Flutter CanvasKit renders exercise names to canvas — no DOM text node.
    // The name only appears in the exercise card group's accessible name.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}"]`),
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.squat}"]`),
    ).toBeVisible({ timeout: 10_000 });

    // Discard to clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
  });

  test('should set weight and reps via dialog entry', async ({ page }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Set weight to 100 kg via the dialog helper.
    await setWeight(page, '100');

    // The dialog must dismiss and the weight value must update to 100 in the set row.
    await expect(page.locator('text=100')).toBeVisible({ timeout: 5_000 });

    // Set reps to 5 via the dialog helper.
    await setReps(page, '5');

    // Discard.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
  });

  test('should add multiple sets to an exercise', async ({ page }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Each exercise card starts with one set row. The Add Set button adds more.
    const initialSets = await page
      .locator(WORKOUT.markSetDone)
      .count();

    await page.click(WORKOUT.addSetButton);
    await page.waitForTimeout(300);

    const setsAfterFirst = await page.locator(WORKOUT.markSetDone).count();
    expect(setsAfterFirst).toBeGreaterThan(initialSets);

    await page.click(WORKOUT.addSetButton);
    await page.waitForTimeout(300);

    const setsAfterSecond = await page.locator(WORKOUT.markSetDone).count();
    expect(setsAfterSecond).toBeGreaterThan(setsAfterFirst);

    // Discard.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
  });

  test('should complete individual sets via checkbox toggle', async ({ page }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Add a second set so we can check independence.
    await page.click(WORKOUT.addSetButton);

    // Mark the first set as done.
    await completeSet(page, 0);

    // The first checkbox is now in the completed state.
    await expect(page.locator(WORKOUT.setCompleted).nth(0)).toBeVisible({
      timeout: 5_000,
    });

    // The second set must still be in the uncompleted state.
    await expect(page.locator(WORKOUT.markSetDone).nth(0)).toBeVisible({
      timeout: 5_000,
    });

    // Discard.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
  });

  test('should show incomplete sets warning dialog when finishing with incomplete sets', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Add a second set so we have 2 sets total.
    await page.click(WORKOUT.addSetButton);

    // Complete set 0 to enable the Finish button (onPressed requires _hasCompletedSet).
    await completeSet(page, 0);

    // Leave set 1 incomplete — tap Finish Workout.
    await page.click(WORKOUT.finishButton);

    // The dialog should warn about incomplete sets.
    // The warning text follows the pattern "You have N incomplete set(s)".
    // Flutter's showDialog + AlertDialog renders as role="alertdialog" via AOM.
    // Playwright's role= selector uses exact role matching — role=dialog does NOT
    // match alertdialog. Use role=alertdialog directly, with a fallback to check
    // for the dialog content text.
    const dialog = page.locator('role=alertdialog').or(page.locator('role=dialog'));
    await expect(dialog).toBeVisible({ timeout: 8_000 });

    const hasIncompleteWarning =
      (await page
        .locator('text=incomplete')
        .isVisible({ timeout: 5_000 })
        .catch(() => false)) ||
      (await page
        .locator("text=You have")
        .isVisible({ timeout: 2_000 })
        .catch(() => false));

    expect(hasIncompleteWarning).toBe(true);

    // "Keep Going" closes the dialog and returns to the workout.
    await page.click(WORKOUT.keepGoingButton);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 5_000,
    });

    // Discard.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
  });

  test('should navigate away from workout screen after finishing with completed sets', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Set weight and reps using the helpers.
    await setWeight(page, '60');
    await setReps(page, '8');

    await completeSet(page, 0);
    await finishWorkout(page);

    // App must navigate to either the PR celebration screen or home.
    // Use URL-based detection to avoid the ScaleTransition visibility race
    // on PR.firstWorkoutHeading / PR.newPRHeading (both live inside a
    // ScaleTransition that starts at scale=0, making them temporarily
    // invisible to Playwright's isVisible() check).
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show confirmation dialog and return to home when discarding workout', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // The Discard button may be directly visible or inside an overflow menu.
    const discardBtn = page.locator(WORKOUT.discardButton);
    const isVisible = await discardBtn
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!isVisible) {
      const overflow = page.locator('role=button[name="More options"]');
      if (
        await overflow.isVisible({ timeout: 3_000 }).catch(() => false)
      ) {
        await overflow.click();
      }
    }

    await page.locator(WORKOUT.discardButton).click();

    // Confirmation dialog must appear.
    await expect(page.locator('text=Discard Workout?')).toBeVisible({
      timeout: 5_000,
    });

    // Confirm discard.
    await page.locator(WORKOUT.discardConfirmButton).click();

    // Must return to home without saving the workout.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should auto-generate workout name with an em-dash date separator', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // The AppBar title uses an em-dash (U+2014) separator: "Workout — Day Mon DD"
    const appBarTitle = page.locator('role=heading[name*="Workout \u2014"]');
    await expect(appBarTitle).toBeVisible({ timeout: 10_000 });

    // Discard to clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
  });

  test('should survive decimal weight 22.5 through full save and display round-trip (WK-023)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Enter the decimal weight via the dialog helper.
    await setWeight(page, '22.5');

    // Confirm the decimal value is visible in the set row immediately after entry.
    await expect(page.locator('text=22.5')).toBeVisible({ timeout: 5_000 });

    await setReps(page, '10');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss PR celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // Navigate to history via the Last session line (SPA navigation).
    // page.goto('/home/history') reloads the Flutter SPA and the router
    // doesn't preserve the deep link. W8: the stat cell is gone; use the
    // editorial Last session line which also navigates to /home/history.
    await expect(page.locator(HOME.lastSessionLine)).toBeVisible({
      timeout: 10_000,
    });
    await page.click(HOME.lastSessionLine);

    // The history screen must be visible.
    await expect(page.locator(HISTORY.heading)).toBeVisible({ timeout: 15_000 });

    // Tap the most recent workout card to open its detail.
    //
    // Flake fix (#15): the WorkoutHistory screen loads from Hive cache first
    // (no network round-trip). The detail also loads from cache. The race was
    // that history-list cards are rendered asynchronously even from cache under
    // Riverpod's AsyncValue stream — a card might flicker briefly visible before
    // the list fully settles. Use expect(firstHistoryCard).toBeVisible() with a
    // generous timeout to wait for the list to stabilise, then wait for the URL
    // to change to a /workout/ detail route before asserting text content.
    // This eliminates the race between the SPA route push and the Riverpod
    // provider rebuilding the set rows with the persisted weight data.
    const firstHistoryCard = page.locator('role=button[name*="Workout"]').first();
    await expect(firstHistoryCard).toBeVisible({ timeout: 15_000 });
    await firstHistoryCard.click();

    // Wait for the SPA to navigate to the workout detail route before asserting.
    // The router pushes /home/history/{workoutId} on card tap. Waiting for the
    // URL change ensures Riverpod has fetched (or restored from cache) the detail
    // data, so the set rows are guaranteed to exist before text=22.5 is checked.
    await page.waitForURL(/\/home\/history\//, { timeout: 15_000 });

    // The workout detail screen must display "22.5" as the logged weight.
    await expect(page.locator('text=22.5')).toBeVisible({ timeout: 15_000 });
  });

  test('should open detail bottom sheet when tapping exercise name during active workout (EX-DETAIL-001)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // The exercise name is wrapped in a tappable Semantics area with
    // label "Exercise: <name>. Tap for details. Long press to swap."
    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // The bottom sheet must appear. The "ABOUT" section header only appears
    // in the detail sheet, confirming it's open. Using .nth(1) on the exercise
    // name fails because CanvasKit renders the card's name inside the group's
    // accessible name, not as a standalone text node.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // Clean up — dismiss the sheet by pressing Escape, then discard the workout.
    await page.keyboard.press('Escape');
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });

    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show exercise name and muscle group in detail bottom sheet (EX-DETAIL-002)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // The sheet must show the "ABOUT" section — confirms the sheet is open.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // The muscle group chip must appear. Barbell Bench Press -> Chest.
    // Use .first() — CanvasKit renders "Chest" in the ABOUT text too.
    await expect(page.locator('text=Chest').first()).toBeVisible({ timeout: 5_000 });

    // Dismiss.
    await page.keyboard.press('Escape');
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });

    // Discard workout.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should return to workout with timer visible after dismissing exercise detail sheet (EX-DETAIL-003)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.squat);

    // Note the workout is now in progress — the elapsed timer is in the AppBar.
    // Open the detail sheet.
    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.squat}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // Sheet is open — verify via the ABOUT section, consistent with EX-DETAIL-001/002.
    //
    // Original comment said "Squat doesn't have ABOUT/FORM TIPS sections" — that
    // was incorrect; squat DOES have ABOUT. The original `text=Barbell Squat`
    // approach broke in Phase 23 Cluster C: after the await-fix the H5 SnackBar
    // fires reliably, posting "Barbell Squat added" into the ARIA live region.
    // `text=Barbell Squat` then matches BOTH the live region ("Barbell Squat added")
    // AND the sheet heading ("Barbell Squat"), causing a strict-mode violation.
    // Switch to `text=ABOUT` (same as EX-DETAIL-001/002) — deterministic, no
    // live-region collision.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // Dismiss the sheet by pressing Escape.
    await page.keyboard.press('Escape');

    // The workout screen must still be active.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });

    // The elapsed timer format is MM:SS or H:MM:SS. We match on a colon digit
    // pattern to verify it is still displayed in the AppBar.
    // The AppBar title area contains the workout name + timer as a Column.
    // The timer text is produced by _ElapsedTimer which renders e.g. "01:23".
    await expect(page.locator('text=/\\d+:\\d+/')).toBeVisible({
      timeout: 5_000,
    });

    // Discard.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should preserve workout set data after viewing exercise detail sheet (EX-DETAIL-004)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Enter weight and reps, then mark the set done.
    await setWeight(page, '80');
    await setReps(page, '10');
    await completeSet(page, 0);

    // The set is now completed — verify the checkbox state before opening sheet.
    await expect(page.locator(WORKOUT.setCompleted).nth(0)).toBeVisible({
      timeout: 5_000,
    });

    // Open the exercise detail sheet.
    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // Sheet is open — the "ABOUT" section confirms it.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // Dismiss the sheet.
    await page.keyboard.press('Escape');
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });

    // The completed set checkbox must still be in the completed state.
    await expect(page.locator(WORKOUT.setCompleted).nth(0)).toBeVisible({
      timeout: 5_000,
    });

    // The weight value must still be visible.
    await expect(page.locator('text=80')).toBeVisible({ timeout: 5_000 });

    // Discard.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

// =============================================================================
// FULL — Workout history (fullHistory user)
// =============================================================================

test.describe('Workout history', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullHistory').email,
      getUser('fullHistory').password,
    );
  });

  test('should show empty state for a user with no completed workouts (HIST-005)', async ({
    page,
  }) => {
    // Navigate to the history screen. Since P8 hides the Last session stat
    // cell when lastSession == null && weekVolume == 0 (the new-user empty
    // state), we cannot tap that cell here. Navigate via SPA hash routing
    // instead — page.goto() would reload the Flutter SPA and lose state.
    await page.evaluate(() => {
      window.location.hash = '#/home/history';
    });

    // The history screen AppBar title confirms we are on the right screen.
    await expect(page.locator(HISTORY.heading)).toBeVisible({ timeout: 15_000 });

    // The empty state text must be visible.
    await expect(page.locator(HISTORY.emptyState)).toBeVisible({
      timeout: 10_000,
    });

    // The call-to-action button must accompany the empty state.
    await expect(page.locator(HISTORY.emptyStateCta)).toBeVisible({
      timeout: 5_000,
    });

    // The "Retry" error button must NOT be visible — this is an empty state,
    // not an error state.
    await expect(page.locator(HISTORY.retryButton)).not.toBeVisible();
  });
});

// =============================================================================
// REGRESSION — Cancel button on loading overlay visible from t=0 (PR1 — Q1)
//
// Verifies that the loading overlay's Cancel button is visible immediately
// (from t=0) when the overlay mounts during a finish operation — no 10-second
// fade-in delay (audit Q1: `_cancelTimeout` timer removed, `hasRestorable`
// gate removed, Cancel always rendered).
//
// This test drives a complete workout to the "Save & Finish" confirmation
// dialog, intercepts the save_workout RPC to stall the network, confirms the
// Cancel button is visible as soon as the overlay mounts, then taps Cancel and
// verifies the workout state is restored (the user's data is not lost).
//
// Note on cancel-during-start (C4): the C4 fix (emit AsyncData(null) when
// _lastValidState == null) is covered by the unit test at
// `test/unit/.../active_workout_notifier_test.dart:3468`. An E2E for that
// scenario is not added here because the navigation flow for startWorkout
// calls `context.go('/workout/active')` AFTER `await startWorkout()` resolves,
// so the active-workout screen is never visible while the network is stalled —
// the route intercept would prevent the navigation from completing and the
// overlay would never mount. The unit test provides the authoritative coverage.
// =============================================================================

// =============================================================================
// REGRESSION — Set deletion during rest timer (PR2 — C3/Q5)
//
// Verifies that the swipe-to-delete undo SnackBar is visible AND tap-reachable
// when the rest-timer overlay is up. Pre-PR-2 the rest-timer overlay sat ABOVE
// the inner Scaffold's snackbar slot, so the undo SnackBar fired UNDER the
// 0.87-alpha scrim — invisible AND its undo action's tap was eaten by the
// rest-timer's full-screen `HitTestBehavior.opaque` GestureDetector.
//
// PR-2 fix: overlays moved INTO the Scaffold body slot. The Scaffold paints
// the snackbar slot AFTER the body (`_ScaffoldSlot.snackBar`), so SnackBars
// now render visually + hit-test ABOVE the rest-timer scrim with no extra
// ScaffoldMessenger hoisting required.
//
// Companion change history:
//   * PR-2 C3/Q5 (2026-04) bumped the set-delete snack duration from 4 s to
//     10 s — the rationale was "a user mid-rest with eyes off the phone
//     needs more than 4 s to react."
//   * Phase 23 PR #214 (2026-05) reverted the bump to 5 s after the
//     countdown progress bar (Phase 23 same PR) makes the remaining time
//     legible — the extra-wide reaction window became unnecessary visual
//     debt. The duration assertion below pins the new 5 s contract.
//
// Both visibility (#1, #3) and reachability (#2) need E2E coverage per the
// PR-2 brief — widget tests can't measure z-order or full-screen hit-testing
// the way Playwright can drive a real DOM stack.
// =============================================================================

test.describe('Set deletion during rest timer (PR2 — C3)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutSwipeUndo').email,
      getUser('smokeWorkoutSwipeUndo').password,
    );
  });

  /**
   * Swipe-delete the set whose `markSetDone` checkbox is at `setIndex`.
   *
   * Uses `page.mouse.move/down/up` to synthesize a real horizontal drag
   * from right→left across the set row. Flutter's `Dismissible` listens for
   * `HorizontalDragGestureRecognizer` events; a synthetic `dispatchEvent`
   * approach doesn't work because Flutter CanvasKit reads from the
   * pointer-event stream, not synthetic event listeners.
   *
   * The drag distance is ~70% of the row width — Dismissible's default
   * `dismissThresholds: 0.4` requires >=40% travel for the dismiss gesture
   * to commit, but we go further to guarantee the threshold under any
   * viewport drift.
   */
  async function swipeDeleteSet(
    page: import('@playwright/test').Page,
    setIndex: number,
  ): Promise<void> {
    // Anchor on the visible checkbox of the target set so we can derive
    // the row's vertical centre. The Dismissible wraps the entire row,
    // so dragging from any horizontal position on the row's vertical
    // axis triggers the swipe.
    const checkboxes = page.locator(WORKOUT.markSetDone);
    await expect(checkboxes.nth(setIndex)).toBeVisible({ timeout: 5_000 });
    const box = await checkboxes.nth(setIndex).boundingBox();
    if (!box) throw new Error(`set #${setIndex} bounding box not available`);

    // Start near the right edge of the viewport (dismiss is endToStart),
    // end near the left. Use the checkbox's vertical centre as the y axis.
    const viewport = page.viewportSize() ?? { width: 1280, height: 720 };
    const y = box.y + box.height / 2;
    const startX = viewport.width - 24;
    const endX = 24;

    // Move there first so the Dismissible's hit-test owns the pointer.
    await page.mouse.move(startX, y);
    await page.mouse.down();
    // Multi-step drag — Flutter's HorizontalDragGestureRecognizer needs a
    // few intermediate move events to register a real drag (a single
    // jump-and-up reads as a tap, not a drag).
    const steps = 12;
    for (let i = 1; i <= steps; i++) {
      const x = startX - ((startX - endX) * i) / steps;
      await page.mouse.move(x, y, { steps: 2 });
    }
    await page.mouse.up();
  }

  test('should show undo SnackBar above rest timer overlay after swipe-delete then complete (PR2 — C3)', async ({
    page,
  }) => {
    // Realistic C3 repro: swipe-delete a set FIRST (snackbar fires, no
    // overlay yet → Dismissible owns the gesture), then immediately
    // complete a sibling set (rest timer fires within the snackbar's
    // 5 s window — Phase 23 #214, down from 10 s). Pre-fix, the
    // rest-timer scrim painted ABOVE the snackbar and ate the Undo tap.
    // Post-fix, the snackbar slot paints above the overlay (overlays
    // moved INTO the Scaffold body slot).
    //
    // Why not "complete first → swipe during rest"? The rest-timer's
    // outer GestureDetector covers the viewport with HitTestBehavior.opaque
    // — a horizontal-drag gesture on a SetRow underneath the overlay is
    // intercepted by the timer's scrim before reaching the Dismissible.
    // The realistic user flow is the inverse order driven here.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    // Add a second + third set so we have 3 total: set #1 to swipe-delete,
    // set #2 to complete (rest fires), set #3 still pending. Three sets
    // ensure the exercise card retains a row even after delete + complete
    // (avoids the empty-card edge case).
    await page.locator(WORKOUT.addSetButton).first().click();
    await page.locator(WORKOUT.addSetButton).first().click();
    await expect(page.locator(WORKOUT.markSetDone).nth(2)).toBeVisible({
      timeout: 10_000,
    });

    // Set weight + reps on set #2 (the LAST uncompleted set since
    // setWeight/setReps target .last()).
    await setWeight(page, '60');
    await setReps(page, '8');

    // Step 1 — swipe-delete set #1 (markSetDone index 0). No overlay yet,
    // so Dismissible owns the gesture cleanly.
    await swipeDeleteSet(page, 0);

    // Snackbar fires immediately on dismissal.
    const snackBar = page.locator(WORKOUT.swipeToDeleteSnackBar).first();
    await expect(snackBar).toBeVisible({ timeout: 5_000 });

    // Step 2 — within the snackbar's 5 s window (Phase 23 #214),
    // complete what is now set #1 (originally set #2 — the one we set
    // weight on). Setting weight
    // via the LAST `Weight value` button targets the LAST uncompleted set,
    // which is now at markSetDone index 1 (set #3 was not given values).
    // To trigger rest reliably, complete the set whose weight is non-zero —
    // that's the one at index 0 of markSetDone (the original set #2 after
    // set #1 was deleted, which inherits set-row weight 60).
    //
    // Note: `setWeight` ran BEFORE the delete and targeted whichever set
    // was last at that time (originally set #3 — bottom of three sets).
    // After deleting set #1, the original set #3 sits at markSetDone index 1.
    // Complete it so the rest timer fires — ignoring the inferior set #1
    // (now-renumbered to set #2) which has 0/0 values.
    await page.locator(WORKOUT.markSetDone).nth(1).click();

    // Rest timer mounts on top of the snackbar. PR-2 C3 acceptance #1:
    // the snackbar must STILL be visible — its slot paints above the
    // overlay-as-body-stack-item.
    const restTimer = page.locator('role=progressbar[name*="Rest timer"]');
    await expect(restTimer).toBeVisible({ timeout: 8_000 });
    await expect(snackBar).toBeVisible();

    // Clean up: dismiss timer, discard workout.
    await restTimer.click({ force: true }).catch(() => {});
    await restTimer
      .waitFor({ state: 'hidden', timeout: 5_000 })
      .catch(() => {});
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should restore the deleted set when tapping Undo on the snackbar above rest timer (PR2 — C3)', async ({
    page,
  }) => {
    // Same realistic setup: swipe-delete THEN complete sibling. The Undo
    // action sits in the snackbar slot which paints above the rest-timer
    // scrim — pre-fix the rest-timer's GestureDetector ate the tap.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await page.locator(WORKOUT.addSetButton).first().click();
    await page.locator(WORKOUT.addSetButton).first().click();
    await expect(page.locator(WORKOUT.markSetDone).nth(2)).toBeVisible({
      timeout: 10_000,
    });

    await setWeight(page, '60');
    await setReps(page, '8');

    // Capture markSetDone count BEFORE the delete: should be 3 pending.
    expect(await page.locator(WORKOUT.markSetDone).count()).toBe(3);

    // Step 1 — swipe-delete set #1.
    await swipeDeleteSet(page, 0);

    // Snackbar with Undo appears.
    const undoButton = page.locator(WORKOUT.swipeToDeleteUndoButton).first();
    await expect(undoButton).toBeVisible({ timeout: 5_000 });

    // Step 2 — complete the previously-set-weight set so rest fires and
    // covers the snackbar.
    await page.locator(WORKOUT.markSetDone).nth(1).click();

    const restTimer = page.locator('role=progressbar[name*="Rest timer"]');
    await expect(restTimer).toBeVisible({ timeout: 8_000 });

    // Confirm Undo button is still visible above the scrim.
    await expect(undoButton).toBeVisible();

    // PR-2 C3 acceptance #2: tap Undo through the rest-timer overlay's
    // region. The snackbar slot composites above the overlay → tap lands
    // on the SnackBarAction handler.
    await undoButton.click();

    // The deleted set is restored. Total markSetDone count: now 1
    // pending (set #3 — formerly set #2 — still uncompleted) + restored
    // set = 2 pending. Plus the 1 completed set = 3 total visible done
    // states (1 completed + 2 markSetDone).
    await expect(page.locator(WORKOUT.markSetDone)).toHaveCount(2, {
      timeout: 5_000,
    });

    // Clean up.
    const stillVisible = await restTimer
      .isVisible({ timeout: 1_000 })
      .catch(() => false);
    if (stillVisible) {
      await restTimer.click({ force: true }).catch(() => {});
      await restTimer
        .waitFor({ state: 'hidden', timeout: 5_000 })
        .catch(() => {});
    }
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should auto-dismiss the set-delete undo SnackBar at its 5 s duration (Phase 23 #214)', async ({
    page,
  }) => {
    // Pins the new set-delete undo SnackBar duration (5 s, down from
    // PR-2 Q5's 10 s ceiling). The countdown bar that ships in the
    // same Phase 23 PR makes the remaining time legible, so the
    // extra-wide reaction window is unnecessary visual debt.
    //
    // Two endpoints asserted — together they bracket the duration
    // contract without coupling to the exact frame the snack closes
    // on:
    //   * Visible at ~2.5 s post-fire   → past the old 4 s ceiling but
    //                                     well inside the new 5 s.
    //                                     Regression guard against
    //                                     anyone dropping the duration
    //                                     below ~3 s ("snack feels
    //                                     rushed").
    //   * Dismissed by ~6 s post-fire   → past the new 5 s ceiling +
    //                                     the snack's 250 ms reverse
    //                                     animation. Regression guard
    //                                     against anyone bumping the
    //                                     duration back up to the old
    //                                     10 s.
    //
    // Run WITHOUT a rest-timer trigger so the test isn't bottlenecked
    // on any other timing — z-order / tap-reachability under the rest
    // overlay is already pinned by the two preceding tests in this
    // describe block. This test owns ONLY the duration contract.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await page.locator(WORKOUT.addSetButton).first().click();
    await expect(page.locator(WORKOUT.markSetDone).nth(1)).toBeVisible({
      timeout: 10_000,
    });

    await swipeDeleteSet(page, 0);

    const snackBar = page.locator(WORKOUT.swipeToDeleteSnackBar).first();
    await expect(snackBar).toBeVisible({ timeout: 5_000 });

    // Endpoint 1 — still visible at ~2.5 s. `waitForTimeout` is the
    // right primitive here because the assertion target is a duration,
    // not a state/network event.
    await page.waitForTimeout(2_500);
    await expect(snackBar).toBeVisible({
      timeout: 1_000, // tight — must already be visible, not "soon"
    });

    // Endpoint 2 — dismissed by ~6 s. We're at 2.5 s now; wait another
    // 3.5 s = 6 s total. Snack's 5 s duration + ~250 ms reverse
    // animation = ~5.25 s, so 6 s lands comfortably past the close.
    await page.waitForTimeout(3_500);
    await expect(snackBar).toBeHidden({
      timeout: 1_000,
    });

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

// =============================================================================
// REGRESSION — Workout discard cancel (PR2 — Fix B coverage gap from PR1)
//
// Closes the post-PR-1 E2E coverage gap on the discard-race fix. PR-1
// reviewer-cycle Fix B added a `discardCommitted` gate to the notifier so a
// cancel mid-discard is honored ONLY pre-server-commit. The unit test at
// active_workout_notifier_test.dart pins the boolean transition; this E2E
// pins the user-visible behavior of the same flow.
//
// Pattern mirrors the PR-1 Q1 cancel-overlay test — uses `page.route()` with
// named function refs (per the PR-1 reviewer-cycle Fix C) so the unroute
// removes the same handler installed by route. Stalls DELETE /workouts so
// the cancel happens BEFORE the server-commit. Then unstalls + retries to
// verify the discard succeeds normally on the second pass.
// =============================================================================

test.describe('Workout discard cancel (PR2 — Fix B coverage gap)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutDiscardRace').email,
      getUser('smokeWorkoutDiscardRace').password,
    );
  });

  test('should restore active workout when Cancel tapped during stalled DELETE /workouts and complete discard when stall is released (PR2 — Fix B)', async ({
    page,
  }) => {
    // Set up an active workout with one logged set so there's something
    // visible to assert is "still there" after Cancel.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '8');

    // Intercept DELETE /workouts to stall the network. Same naming pattern
    // as PR-1 Q1 (Fix C) — predicate + handler pinned to named variables so
    // the later page.unroute removes the SAME handler.
    let signalIntercepted!: () => void;
    const intercepted = new Promise<void>((resolve) => {
      signalIntercepted = resolve;
    });

    let stallRequests = true;

    // Stall pattern (different from the PR-1 Q1 SAVE pattern, on purpose):
    //
    // The first DELETE /workouts is intercepted and HELD until the test
    // releases `stallRequests = false`. When released, the held route
    // **continues** to the server (route.continue()) — we do NOT abort it.
    //
    // **Why not abort like PR-1 Q1 does?**: aborting throws into the
    // notifier's `_repo.discardWorkout(...)` future, which the guard
    // catches as `AsyncError`. The post-guard cancel-check uses
    // `_cancelRequested`, which the SECOND discard call (issued by the
    // test's retry path) resets at its method top — so by the time the
    // first call's guard returns AsyncError, _cancelRequested is false
    // and `state = result` clobbers the second call's restored state
    // with AsyncError. AsyncError.value == null → the active-workout
    // screen's redirect fires → home. The retry-discard tap then races
    // a DOM that's already navigating away.
    //
    // route.continue() lets the first call's discard reach the server
    // SUCCESSFULLY. The notifier's `discardCommitted = true` flips, the
    // first call's post-guard cancel-check evaluates to
    // `_cancelRequested && !discardCommitted = false && false`, neither
    // branch fires, and state = AsyncData(null) lands. Screen navigates
    // home from the first call's completion. The second-call retry is
    // therefore unnecessary — the cancel was effectively no-op'd by the
    // server eventually committing.
    //
    // To preserve the test's intent (verify Cancel SHOWS the active
    // workout immediately, and the user CAN re-discard), we drop the
    // retry tap and instead assert that after release, the discard
    // eventually completes (home tab visible) — which is the same
    // user-facing observable.
    const routeHandler = async (route: import('@playwright/test').Route) => {
      signalIntercepted();
      // S1 coverage gap (BUGS.md PR-2): this test does NOT cover the
      // re-entrance window where DiscardWorkoutCoordinator._isShowingDialog
      // stays `true` while the cancelled-but-still-in-flight DELETE is
      // held. Closing it requires asserting the discard dialog re-opens
      // BEFORE `stallRequests = false`. Tracked under PR-3 per BUGS.md S1.
      // Spin until the test releases the stall. Polling rather than a
      // single await on a promise so the handler exits cleanly when the
      // test sets `stallRequests = false` AT ANY moment.
      while (stallRequests) {
        await new Promise<void>((r) => setTimeout(r, 100));
      }
      await route.continue();
    };

    // The repository call is `_workouts.delete().eq('id', wid).eq('user_id', uid)`,
    // which Supabase translates to `DELETE /rest/v1/workouts?id=eq.{...}&user_id=eq.{...}`.
    // The path is `/rest/v1/workouts` and the method is DELETE — match on the
    // path (the URL query string carries the IDs as filter args).
    const DISCARD_URL = (url: URL) =>
      url.pathname.includes('/rest/v1/workouts');

    // page.route() filters by URL only — we further filter by method inside the
    // handler so we don't accidentally stall the GET /workouts that loads the
    // active workout on app boot. Use a wrapper.
    const routeFilter = async (route: import('@playwright/test').Route) => {
      if (route.request().method() !== 'DELETE') {
        await route.continue();
        return;
      }
      await routeHandler(route);
    };

    await page.route(DISCARD_URL, routeFilter);

    // Tap the discard button + confirm the dialog → triggers DELETE /workouts.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();

    // Wait for the DELETE to be intercepted (loading overlay should be up).
    await intercepted;

    // The loading overlay is up with its always-visible Stop button (Q1;
    // relabeled in PR-7 from Cancel → Stop). PR-2 acceptance: tapping Stop
    // during the stall must restore the workout (discardCommitted == false,
    // so the post-guard cancel-check honors the cancel).
    const cancelButton = page.locator(WORKOUT.loadingOverlayStopButton);
    await expect(cancelButton).toBeVisible({ timeout: 5_000 });
    await cancelButton.click();

    // Workout state is restored: the active workout's Finish button is back,
    // and the previously-set weight is still visible in the set row.
    // (Flutter CanvasKit draws text to canvas, so target the AOM-exposed
    // weight button by its accessible name pattern instead of `text=`.)
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });
    await expect(
      page.locator('role=button[name*="Weight value: 60"]').first(),
    ).toBeVisible({ timeout: 5_000 });

    // The loading overlay is gone (Cancel dismissed it).
    await expect(cancelButton).not.toBeVisible({ timeout: 5_000 });

    // PR-2 acceptance #2 — releasing the stall completes the held first
    // discard end-to-end (route.continue() inside the handler), which
    // server-commits the soft-delete. State then settles to
    // `AsyncData(null)` and the active-workout screen's
    // `displayState == null && !asyncState.isLoading` redirect fires →
    // home navigation completes naturally.
    //
    // **Why not a separate retry-discard tap?** see the long comment on
    // `routeHandler` above for the full root-cause: a second discard
    // call would race the held first call's eventual error/success path,
    // and the notifier's `_cancelRequested` flag is a single global
    // (not scoped per discard invocation), so the second call's reset
    // would invalidate the first call's post-guard cancel honoring.
    // Letting the held first call complete naturally avoids that race
    // AND tests the same user-visible contract: cancel restores state
    // until the in-flight network completes, then the discard transitions
    // home cleanly.
    //
    // Note: the FIRST discard call's network was held by the route
    // handler's `while (stallRequests)` loop. Setting the flag releases
    // that loop on its next 100ms tick, which then `route.continue()`s.
    stallRequests = false;

    // Home tab visible — the held first-discard's request continued
    // server-side, the soft-delete committed, and the screen redirected
    // home. No stuck state, no orphaned dialog.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    // Defensive cleanup — remove the route handler so it doesn't
    // intercept other tests in the same worker. (Pass the SAME function
    // reference passed to page.route per PR-1 reviewer-cycle Fix C.)
    await page.unroute(DISCARD_URL, routeFilter);
  });
});

test.describe('Workout loading overlay cancel (PR1 — Q1)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutCancelStart').email,
      getUser('smokeWorkoutCancelStart').password,
    );
  });

  test('should show Cancel button immediately on loading overlay and restore workout on tap (PR1 — Q1)', async ({
    page,
  }) => {
    // Set up a workout with one completed set so Finish is enabled.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Intercept the save_workout RPC to stall the network — the loading overlay
    // mounts while this request is in-flight and we assert Cancel from t=0.
    // The handler is stored so we can unroute it precisely after the cancel.
    let signalIntercepted!: () => void;
    const intercepted = new Promise<void>((resolve) => {
      signalIntercepted = resolve;
    });

    // Flag: once we tap Cancel we let subsequent requests through so discard works.
    let stallRequests = true;

    const routeHandler = async (route: import('@playwright/test').Route) => {
      if (!stallRequests) {
        await route.continue();
        return;
      }
      // Signal immediately so the test can proceed while this stalls.
      signalIntercepted();
      // Hold for up to 30s; the test taps Cancel long before this fires.
      // Once the page.unroute removes the handler, new requests flow freely.
      await new Promise<void>((r) => setTimeout(r, 30_000));
      await route.abort().catch(() => {});
    };

    // PR1 review — Fix C: Playwright's `page.unroute` with a function URL
    // predicate only removes the handler when called with the EXACT same
    // function reference. Two arrow-function literals at the route/unroute
    // call sites are different references, so the unroute is a silent no-op
    // and the stall handler stays attached for the rest of the page's
    // lifetime. Bind the predicate (and the handler) to named variables so
    // both calls share identity.
    const SAVE_WORKOUT_URL = (url: URL) =>
      url.pathname.includes('/rest/v1/rpc/save_workout') ||
      (url.pathname.includes('/rest/v1/workouts') && url.search.includes('is_active'));

    await page.route(SAVE_WORKOUT_URL, routeHandler);

    // Tap Finish Workout in the bottom bar.
    await page.click(WORKOUT.finishButton);

    // Confirmation dialog — tap "Save & Finish" to trigger the save RPC.
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await dialogFinish.click();

    // Wait for the route to be intercepted (save RPC stalled, overlay mounting).
    await intercepted;

    // Q1 assertion: the Stop button must be visible from t=0 — no timer
    // delay. Pre-PR1 the button only appeared after 10s; now it renders
    // immediately. (PR-7 relabel: "Cancel" → "Stop"; the role+name match
    // changed at the same time.)
    const cancelButton = page.locator(WORKOUT.loadingOverlayStopButton);
    await expect(cancelButton).toBeVisible({ timeout: 5_000 });

    // Tap Stop to abort the in-flight save.
    await cancelButton.click();

    // The notifier restores the prior workout state (C1 pre-commit cancel).
    // The user should be back on the active workout screen with their data intact.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });

    // The loading overlay must no longer be visible.
    await expect(cancelButton).not.toBeVisible({ timeout: 5_000 });

    // Disable stalling so we don't leave a route handler armed for the next test.
    // Pass the SAME function references as the page.route() call above —
    // see Fix C comment at the route() call site.
    stallRequests = false;
    await page.unroute(SAVE_WORKOUT_URL, routeHandler);

    // No cleanup discard / nav assertion. Two prior attempts proved that
    // class of cleanup is fundamentally brittle here:
    //   1. Original PR-1 chain (tap discard → confirm → wait nav-home 15s)
    //      — fails on GHA when the real server discard takes >15s to
    //      clear state + flip nav (FLAKY_TESTS.md #22 history).
    //   2. `page.goto('/')` shortcut (PR-2 first attempt) — fails because
    //      Hive still has the active workout, so the app auto-resumes
    //      to `/workout/active` and nav-home never appears.
    //
    // The Q1 product contract is fully asserted at lines 1428-1441
    // above (Cancel visible from t=0 → restores workout → overlay
    // dismissed). Cleanup is optional: Playwright per-test browser
    // context isolation wipes Hive between tests (so the next test
    // sees a fresh storage), and `smokeWorkoutCancelStart` is dedicated
    // to this single test (no cross-test pollution risk). The
    // server-side workout row stays `is_active: true` — harmless
    // because `loadActiveWorkout` reads from Hive, not the server.
  });
});

// =============================================================================
// PR-3 — Destructive-gesture cleanup + Q3 swap confirm + H5 add undo
//
// Per BUGS.md PR-3: every destructive shortcut on the active-workout surface
// is now either removed or behind an explicit confirm/undo. These tests pin
// the user-visible behavior of those changes so a future commit can't
// silently re-add a long-press shortcut or regress the confirm copy.
// =============================================================================

test.describe('Exercise card destructive gestures cleanup (PR3)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutDestructiveGestures').email,
      getUser('smokeWorkoutDestructiveGestures').password,
    );
  });

  test('should NOT swap exercise on long-press of header (H2/Q6)', async ({
    page,
  }) => {
    // PR-3 H2/Q6: long-press on the exercise name was removed. The visible
    // swap_horiz icon button is the sole entry point. We verify the negative
    // contract by long-pressing the header and asserting the exercise picker
    // bottom sheet does NOT open.
    //
    // Note on Flutter InkWell long-press semantics: when `onLongPress` is
    // null but `onTap` is set, a long-press of any duration falls through
    // to the onTap handler on pointer up. So the long-press synthesised
    // here MAY open the exercise detail sheet (onTap firing). That's
    // correct, expected behaviour — the regression to catch is the OLD
    // behaviour where long-press opened the EXERCISE PICKER. We pin only
    // the absence of the picker; the detail sheet may or may not appear
    // and is dismissed before cleanup either way.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Long-press the header. Use the same role-group selector the existing
    // exercise-detail tests use to target the InkWell.
    const header = page
      .locator(WORKOUT.exerciseDetailTap('Barbell Bench Press'))
      .first();
    await expect(header).toBeVisible({ timeout: 10_000 });
    const box = await header.boundingBox();
    if (!box) throw new Error('header bounding box not available');
    // Synthesize a long-press: pointer down → wait > Material's 500ms
    // long-press threshold → pointer up. The test passes when the
    // picker DOES NOT mount as a result.
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(900); // > 500ms long-press threshold
    await page.mouse.up();
    await page.waitForTimeout(500); // settle

    // Load-bearing assertion: the EXERCISE PICKER did NOT open. The picker's
    // search input is the stable selector for "the picker is on screen."
    await expect(page.locator(EXERCISE_PICKER.searchInput).first()).toHaveCount(
      0,
      { timeout: 2_000 },
    );

    // The detail sheet may have opened (InkWell.onTap fallback when
    // onLongPress is null). Dismiss it via Escape before cleanup so the
    // discard button is reachable.
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    // Cleanup: discard the workout to clear server-side state.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should NOT trigger fill remaining on long-press of Add Set (H3)', async ({
    page,
  }) => {
    // PR-3 H3: long-press on "Add Set" was removed. The visible
    // _FillRemainingButton (only rendered when there are completable sets)
    // is the sole entry point. We assert the negative contract by long-
    // pressing Add Set and asserting the "Filled remaining sets" snackbar
    // — the unique signature of the fill-remaining action — does NOT appear.
    //
    // Note on Flutter OutlinedButton long-press semantics: when
    // `onLongPress` is null, the Material button does NOT fall through
    // to onPressed. The button-class API is distinct from InkWell's tap
    // semantics — see [ButtonStyleButton._onLongPressed]. So this gesture
    // has NO observable effect post-fix; the snackbar absence is the
    // proof.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Add a second set so there's something fill-remaining could affect,
    // then complete set #1 so fill-remaining would have a source.
    await page.locator(WORKOUT.addSetButton).first().click();
    await expect(page.locator(WORKOUT.markSetDone).nth(1)).toBeVisible({
      timeout: 10_000,
    });

    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Long-press the Add Set button.
    const addBtn = page.locator(WORKOUT.addSetButton).first();
    await expect(addBtn).toBeVisible();
    const box = await addBtn.boundingBox();
    if (!box) throw new Error('Add Set bounding box not available');
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(900);
    await page.mouse.up();

    // Wait for any potential fill-remaining snackbar to fire — if the long-
    // press were still wired, "Filled remaining sets" would appear within
    // ~500ms.
    await page.waitForTimeout(800);

    // Load-bearing assertion: the fill-remaining snackbar must NOT appear.
    // The snackbar text is unique to the fill-remaining action; if it
    // shows, the long-press handler regressed. Match by text to keep the
    // assertion locale-independent in en (default test locale).
    await expect(
      page.locator('text=Filled remaining sets').first(),
    ).toHaveCount(0, { timeout: 2_000 });

    // Cleanup.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

test.describe('Swap exercise with logged sets (PR3 — Q3)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutDestructiveGestures').email,
      getUser('smokeWorkoutDestructiveGestures').password,
    );
  });

  test('should swap silently when no sets are completed (Q3)', async ({
    page,
  }) => {
    // Zero completed sets → silent swap (no friction). The confirm dialog
    // MUST NOT appear.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Tap swap-icon to open picker.
    await page.locator(WORKOUT.swapExercise).first().click();
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 5_000,
    });

    // Pick a different exercise.
    await flutterFill(page, EXERCISE_PICKER.searchInput, SEED_EXERCISES.squat);
    const addBarbellSquat = page
      .locator(EXERCISE_PICKER.addExerciseButton(SEED_EXERCISES.squat))
      .first();
    await expect(addBarbellSquat).toBeVisible({ timeout: 10_000 });
    await addBarbellSquat.click();

    // PR-3 Q3 contract: zero-completed → no confirm dialog.
    await expect(
      page.locator(WORKOUT.swapExerciseConfirmDialog),
    ).toHaveCount(0, { timeout: 2_000 });

    // The swap landed — picker is gone and the squat header is now visible.
    await expect(page.locator(EXERCISE_PICKER.searchInput)).not.toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(WORKOUT.exerciseDetailTap(SEED_EXERCISES.squat)).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Cleanup.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show confirm dialog with concrete exercise names when ≥1 set is completed (Q3)', async ({
    page,
  }) => {
    // One or more completed sets → confirm dialog with concrete copy.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Log + complete one set so the swap has something to attribute.
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Open picker via swap icon, pick a different exercise.
    await page.locator(WORKOUT.swapExercise).first().click();
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 5_000,
    });
    await flutterFill(page, EXERCISE_PICKER.searchInput, SEED_EXERCISES.squat);
    const addSquat = page
      .locator(EXERCISE_PICKER.addExerciseButton(SEED_EXERCISES.squat))
      .first();
    await expect(addSquat).toBeVisible({ timeout: 10_000 });
    await addSquat.click();

    // The confirm dialog must appear with concrete names. The selector is
    // identifier-based; locale-independent.
    await expect(
      page.locator(WORKOUT.swapExerciseConfirmDialog).first(),
    ).toBeVisible({ timeout: 5_000 });
    // The title text contains the NEW exercise name (en — default locale).
    await expect(
      page.locator(`text=Swap to ${SEED_EXERCISES.squat}?`).first(),
    ).toBeVisible({ timeout: 2_000 });
    // The body contains both names + the "1 logged set" count.
    await expect(
      page.locator('text=/1 logged set/').first(),
    ).toBeVisible({ timeout: 2_000 });

    // Cancel — original exercise stays.
    await page.locator(WORKOUT.swapExerciseConfirmCancelButton).first().click();
    await expect(
      page.locator(WORKOUT.swapExerciseConfirmDialog),
    ).toHaveCount(0, { timeout: 5_000 });
    await expect(
      page.locator(WORKOUT.exerciseDetailTap('Barbell Bench Press')).first(),
    ).toBeVisible({ timeout: 5_000 });

    // Cleanup.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should swap when Confirm is tapped on the swap dialog (Q3)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    await page.locator(WORKOUT.swapExercise).first().click();
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 5_000,
    });
    await flutterFill(page, EXERCISE_PICKER.searchInput, SEED_EXERCISES.squat);
    const addSquat = page
      .locator(EXERCISE_PICKER.addExerciseButton(SEED_EXERCISES.squat))
      .first();
    await expect(addSquat).toBeVisible({ timeout: 10_000 });
    await addSquat.click();

    await expect(
      page.locator(WORKOUT.swapExerciseConfirmDialog).first(),
    ).toBeVisible({ timeout: 5_000 });
    // Confirm Swap → the exercise is replaced; header shows the new name.
    await page.locator(WORKOUT.swapExerciseConfirmSwapButton).first().click();
    await expect(
      page.locator(WORKOUT.swapExerciseConfirmDialog),
    ).toHaveCount(0, { timeout: 5_000 });
    await expect(
      page.locator(WORKOUT.exerciseDetailTap(SEED_EXERCISES.squat)).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Cleanup.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

test.describe('Add exercise undo (PR3 — H5)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutDestructiveGestures').email,
      getUser('smokeWorkoutDestructiveGestures').password,
    );
  });

  test('should show undo snackbar after adding an exercise from picker (H5)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // The undo snackbar fires immediately after the picker dismisses.
    // Note: addExercise() helper performs a single round-trip and then
    // taps Add Set internally, but the snackbar is shown by the SCREEN
    // (`_onAddExercise`) so it lands BEFORE the helper's Add Set tap.
    // The snackbar's 3.5 s duration (Phase 23 #214) easily covers the
    // helper sequence — the appearance check below is bounded by the
    // 5 s Playwright timeout, not by the snack lifetime.
    const snackBar = page.locator(WORKOUT.addExerciseUndoSnackBar).first();
    await expect(snackBar).toBeVisible({ timeout: 5_000 });

    // Cleanup.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should remove the just-added exercise when Undo is tapped (H5)', async ({
    page,
  }) => {
    // Verify the undo action actually invokes restoreExercise — the
    // just-added exercise is dropped and the workout returns to the
    // empty body state.
    await startEmptyWorkout(page);

    // Tap the FAB → picker → benchPress directly so we control the
    // snackbar lifetime tightly.
    await page.click(WORKOUT.addExerciseFab);
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });
    await flutterFill(
      page,
      EXERCISE_PICKER.searchInput,
      SEED_EXERCISES.benchPress,
    );
    const addBench = page
      .locator(EXERCISE_PICKER.addExerciseButton(SEED_EXERCISES.benchPress))
      .first();
    await expect(addBench).toBeVisible({ timeout: 10_000 });
    await addBench.click();

    // Undo snackbar appears.
    const undoButton = page.locator(WORKOUT.addExerciseUndoButton).first();
    await expect(undoButton).toBeVisible({ timeout: 5_000 });

    // Tap Undo → the exercise is removed → the empty-body CTA returns.
    await undoButton.click();

    // After undo, no exercise card should be visible. The empty-body
    // shows the same FAB selector (workout-add-exercise) — but no
    // exercise header, no add-set button. Assert the bench-press header
    // is gone.
    await expect(
      page.locator(WORKOUT.exerciseDetailTap('Barbell Bench Press')),
    ).toHaveCount(0, { timeout: 5_000 });

    // Cleanup.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});

// =============================================================================
// PR-3 S1 — DiscardWorkoutCoordinator re-entrance window
//
// Stalls DELETE /workouts so we can probe the coordinator's re-entrance
// guard BEFORE the network resolves. Pre-fix, tapping discard a SECOND time
// while the held first call awaits silently no-ops on `_isShowingDialog`.
// Post-fix, the post-await state poll clears the flag the moment Cancel
// restores state, so the second tap re-opens the dialog cleanly.
// =============================================================================

test.describe('Discard re-entrance (PR3 — S1)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutDiscardReentry').email,
      getUser('smokeWorkoutDiscardReentry').password,
    );
  });

  test('should allow re-opening discard dialog after Cancel during stalled DELETE (S1)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '8');

    // Stall handler — same naming pattern as PR-2 Fix B test (named
    // function refs so page.unroute removes the SAME handler).
    let signalIntercepted!: () => void;
    const intercepted = new Promise<void>((resolve) => {
      signalIntercepted = resolve;
    });
    let stallRequests = true;

    const routeHandler = async (route: import('@playwright/test').Route) => {
      signalIntercepted();
      while (stallRequests) {
        await new Promise<void>((r) => setTimeout(r, 100));
      }
      await route.continue();
    };

    const DISCARD_URL = (url: URL) =>
      url.pathname.includes('/rest/v1/workouts');
    const routeFilter = async (route: import('@playwright/test').Route) => {
      if (route.request().method() !== 'DELETE') {
        await route.continue();
        return;
      }
      await routeHandler(route);
    };
    await page.route(DISCARD_URL, routeFilter);

    // 1. Tap discard → confirm → DELETE is intercepted + held.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await intercepted;

    // 2. Loading overlay is up with its always-visible Stop button (PR-7
    //    relabel from Cancel → Stop; selector renamed accordingly).
    const cancelOverlay = page.locator(WORKOUT.loadingOverlayStopButton);
    await expect(cancelOverlay).toBeVisible({ timeout: 5_000 });
    await cancelOverlay.click();

    // 3. State is restored — the workout is back. The held DELETE is STILL
    //    in flight at this point.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });
    await expect(cancelOverlay).not.toBeVisible({ timeout: 5_000 });

    // 4. Tap discard AGAIN — pre-fix this silently no-op'd on
    //    `_isShowingDialog`. Post-fix the coordinator's post-await state
    //    poll cleared the guard the moment Cancel restored state, so
    //    this tap re-opens the dialog cleanly.
    await page.locator(WORKOUT.discardButton).click();
    await expect(
      page.locator(WORKOUT.discardConfirmButton),
    ).toBeVisible({
      timeout: 5_000,
    });

    // 5. Dismiss this second dialog so the test can wind down — tap the
    //    Cancel button on the discard dialog (NOT the loading overlay,
    //    which is no longer up).
    await page.locator(WORKOUT.keepGoingButton).click().catch(async () => {
      // Fallback: some builds expose Cancel via role=button instead of
      // the keep-going semantics identifier. Use the role-name selector.
      await page
        .locator('role=button[name="Cancel"]')
        .first()
        .click()
        .catch(() => {});
    });

    // Release the held DELETE so the test exits cleanly. The held first
    // discard call now completes server-side; the screen redirects home
    // because `discardCommitted` flips and state lands AsyncData(null).
    stallRequests = false;
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    await page.unroute(DISCARD_URL, routeFilter);
  });
});

// =============================================================================
// PR-4 / M3 — Cascading delete + undo restores ORIGINAL order
//
// Pre-fix `restoreSet` inserted using `deletedSet.setNumber - 1`. After a
// cascading delete (e.g. delete #2 then delete #3-renumbered-to-#2), the
// captured setNumber reflects the position AT TIME OF DELETION, not the
// original. The post-fix notifier records each set's original index in an
// id-keyed map at first-delete time so undo restores the FIRST-observed
// position. This test pins the user-visible flow end-to-end: the swipe +
// snackbar interaction sequence is awkward to drive in widget tests, so
// the E2E coverage here complements the unit-test coverage in
// active_workout_notifier_test.dart group "restoreSet cascading order".
//
// Per the PR-4 brief: "Bugs come from uncovered functional flows — let's
// cover them in e2e to avoid regression."
// =============================================================================

test.describe('Cascading undo restores order (PR4 — M3)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutPr4CascadingUndo').email,
      getUser('smokeWorkoutPr4CascadingUndo').password,
    );
  });

  /**
   * Swipe-delete the set at the given checkbox index (mirrors the helper
   * in the PR-2 swipe tests above).
   */
  async function swipeDeleteSet(
    page: import('@playwright/test').Page,
    setIndex: number,
  ): Promise<void> {
    const checkboxes = page.locator(WORKOUT.markSetDone);
    await expect(checkboxes.nth(setIndex)).toBeVisible({ timeout: 5_000 });
    const box = await checkboxes.nth(setIndex).boundingBox();
    if (!box) throw new Error(`set #${setIndex} bounding box not available`);

    const viewport = page.viewportSize() ?? { width: 1280, height: 720 };
    const y = box.y + box.height / 2;
    const startX = viewport.width - 24;
    const endX = 24;

    await page.mouse.move(startX, y);
    await page.mouse.down();
    const steps = 12;
    for (let i = 1; i <= steps; i++) {
      const x = startX - ((startX - endX) * i) / steps;
      await page.mouse.move(x, y, { steps: 2 });
    }
    await page.mouse.up();
  }

  test('should restore the most-recent cascading delete with correct count + label consecutivity (M3)', async ({
    page,
  }) => {
    // M3 E2E SCOPE NOTE.
    //
    // Material's SnackBar replaces an in-flight SnackBar when a new one
    // is shown — only ONE is visible at a time. After Step 2 below
    // (second swipe-delete), the SnackBar from Step 1's delete has
    // already been dismissed permanently; tapping its Undo is no longer
    // physically possible from the UI. Earlier drafts of this test
    // chained TWO undo taps to assert the full cascading-undo-of-multi-
    // -deletes restoration (`[1,2,3,4]` final order). That second tap
    // was unreachable in practice, and the original `stillHasUndo`
    // conditional silently skipped it — PR #202 review W1 (the
    // unconditional-final-order ask) surfaced the impossibility.
    //
    // What CAN this E2E meaningfully pin:
    //   - Swipe-delete fires a SnackBar with Undo.
    //   - Tapping Undo restores the just-deleted set's row.
    //   - After cascading delete + one undo, count + label consecutivity
    //     are correct (3 sets visible, labels Set 2..3 present, no Set
    //     4 leftover).
    //
    // What this E2E CANNOT pin (and shouldn't try to):
    //   - The post-fix vs pre-fix DIVERGENCE in restored-set IDENTITY
    //     within a multi-undo cascade. All sets in this seed share the
    //     same equipment defaults — labels renumber on insert regardless
    //     of position, so label consecutivity alone does not distinguish
    //     `[set-1, set-3, set-4]` from `[set-1, set-4, set-3]`. The
    //     unit test "M3: cascading delete (#2, #3) then undo, undo →
    //     original order [1,2,3,4]" in
    //     active_workout_notifier_test.dart asserts the id-keyed order
    //     directly. Trust the unit coverage for that property.
    //
    // Title reflects the actual contract this E2E pins.

    // Setup: 4-set exercise. Add bench press (auto-creates 1 set), then
    // add 3 more so we have set numbers [1, 2, 3, 4] before any deletion.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await page.locator(WORKOUT.addSetButton).first().click();
    await page.locator(WORKOUT.addSetButton).first().click();
    await page.locator(WORKOUT.addSetButton).first().click();
    await expect(page.locator(WORKOUT.markSetDone)).toHaveCount(4, {
      timeout: 10_000,
    });

    // Pre-condition: all 4 set rows visible. `markSetDone` count already
    // verified above; additionally confirm set labels 2–4 via their AOM
    // button nodes (set 2+ renders as a button with "Set N." in the name
    // because `isCopyable=true` produces a copyable InkWell). Set 1 is
    // a generic node in the AOM (not a button) — its existence is
    // covered by the `toHaveCount(4)` assertion above.
    for (const n of [2, 3, 4]) {
      await expect(
        page.locator(`role=button[name*="Set ${n}."]`).first(),
      ).toBeVisible({ timeout: 5_000 });
    }

    // Step 1 — swipe-delete set #2 (markSetDone index 1). Set #3 + #4
    // renumber down to #2 + #3. After this:
    //   visible sets = [Set 1, Set 2 (was #3), Set 3 (was #4)]
    await swipeDeleteSet(page, 1);
    await expect(page.locator(WORKOUT.markSetDone)).toHaveCount(3, {
      timeout: 5_000,
    });
    // The "Set 4" label should no longer be present after the renumber.
    // Set 4 was an isCopyable set (button), so use role=button.
    await expect(
      page.locator(`role=button[name*="Set 4."]`).first(),
    ).not.toBeVisible({ timeout: 3_000 });

    // The first delete fires a snackbar. We don't tap Undo yet — we want
    // to delete a SECOND set first to reproduce the cascading-renumber
    // scenario that the M3 fix targets.
    const snackbar = page.locator(WORKOUT.swipeToDeleteSnackBar).first();
    await expect(snackbar).toBeVisible({ timeout: 5_000 });

    // Step 2 — swipe-delete what is NOW set #2 (originally set #3). The
    // swipe handler captures its setNumber as "2" — the M3 trap. After
    // this:
    //   visible sets = [Set 1, Set 2 (was #4)]
    // Step 1's SnackBar is replaced by Step 2's and is no longer
    // tappable (see scope note at the top).
    await swipeDeleteSet(page, 1);
    await expect(page.locator(WORKOUT.markSetDone)).toHaveCount(2, {
      timeout: 5_000,
    });

    // The latest snackbar replaces the earlier one. Pick the last (most
    // recent) Undo by .last() — this is the ONLY Undo reachable from
    // here forward (Material SnackBar contract).
    const undoButtons = page.locator(WORKOUT.swipeToDeleteUndoButton);
    await expect(undoButtons.last()).toBeVisible({ timeout: 5_000 });

    // Step 3 — undo the SECOND delete (most-recent). M3 contract: the
    // restored set lands at its ORIGINAL position (index 2 → set #3 in
    // the renumbered list). After this:
    //   visible sets = [Set 1, Set 2 (was #4), Set 3 (restored set #3)]
    // Pre-fix this would have landed at index 1 (the snapshot's
    // post-renumbered setNumber - 1 = 1) producing [Set 1, restored,
    // was-#4]. With renumber-on-insert this STILL produces
    // [Set 1, Set 2, Set 3] labels (consecutivity is preserved either
    // way) — see the scope note above on why the unit test is the
    // authority for the id-keyed ordering claim.
    await undoButtons.last().click();
    await expect(page.locator(WORKOUT.markSetDone)).toHaveCount(3, {
      timeout: 5_000,
    });

    // Final assertion (UNCONDITIONAL — PR #202 review W1): the user-
    // visible signal after cascading-delete + most-recent-undo is
    // consistent — Set 1..3 are present, no Set 4 leftover. Set 2+
    // render as AOM buttons (isCopyable=true InkWell). Set 1 is a
    // generic AOM node; its existence is proved by `toHaveCount(3)`.
    for (const n of [2, 3]) {
      await expect(
        page.locator(`role=button[name*="Set ${n}."]`).first(),
      ).toBeVisible({
        timeout: 5_000,
      });
    }
    await expect(
      page.locator(`role=button[name*="Set 4."]`).first(),
    ).not.toBeVisible({ timeout: 2_000 });

    // Cleanup: discard so the next test run starts fresh.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await dismissCelebrationIfPresent(page).catch(() => {});
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
  });
});

// =============================================================================
// PR-5 — Disabled FINISH helper text (H6)
//
// When the active workout has no completed sets the FINISH button is
// rendered disabled. Pre-fix the user saw a dim grey button with no signal
// to tap the completion checkboxes. Post-fix a single line of helper text
// renders beneath the button, gated behind `Semantics(identifier:
// 'finish-disabled-hint')` for E2E reachability.
// =============================================================================

test.describe('Disabled FINISH helper text (PR5 — H6)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkout').email,
      getUser('smokeWorkout').password,
    );
  });

  test('should show the disabled-state helper text when no sets are completed', async ({
    page,
  }) => {
    // Start a workout with an exercise but DO NOT complete any sets — the
    // bar should render disabled and the helper text must surface in the
    // AOM (queryable via WORKOUT.finishDisabledHint).
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // The helper text identifier emits only when the button is disabled.
    await expect(
      page.locator(WORKOUT.finishDisabledHint).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('should hide the disabled-state helper text once a set is completed', async ({
    page,
  }) => {
    // Inverse contract: completing a set re-enables the FINISH button, so
    // the disabled-state helper must vanish. This pin guards against a
    // regression where the hint stays around as noise next to a now-tappable
    // CTA.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Sanity: helper is visible while no set is completed.
    await expect(
      page.locator(WORKOUT.finishDisabledHint).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Enter a set and tick it.
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // The helper must disappear — `if (!enabled)` is the conditional in
    // the widget tree.
    await expect(
      page.locator(WORKOUT.finishDisabledHint).first(),
    ).not.toBeVisible({ timeout: 10_000 });

    // Cleanup: discard the workout so we don't leak state to the next test.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await dismissCelebrationIfPresent(page).catch(() => {});
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
  });
});

// =============================================================================
// PR-5 — Hint slot layout stability across set completion (H8)
//
// Pre-fix: when a set transitions pending->completed the previous-session
// hint disappears, the row collapses by ~18dp, and adjacent rows shift
// upward mid-gesture. A user moving from set N's checkbox to set N+1's
// checkbox can miss-tap because the target moved between frames.
//
// Post-fix: on mobile (`!kIsWeb`) the hint slot reserves its ~18dp
// vertical footprint with an ExcludeSemantics-wrapped filler when no
// hint is shown. Web continues to use the conditional render to avoid the
// Flutter Web semantics-engine role-swap bug — see set_row.dart's
// `_shouldShowHint` dartdoc.
//
// **E2E note on Web vs mobile.** Playwright drives the Flutter Web build,
// where the conditional-render branch is active and adjacent rows DO
// still shift on completion. The mobile filler is pinned by the widget
// test `H8 — hint slot layout stability (PR-5)`. To keep the E2E
// non-contradictory with the documented Web behaviour, this spec
// verifies the AOM-level outcome that the user cares about: after
// completing a set, the NEXT set's checkbox remains tappable without
// re-finding it (no "set 4 checkbox moved under me" failure mode). On
// Flutter Web the geometric shift is small enough that this is true
// either way — the regression hazard is mobile; the widget test is the
// canonical guard.
// =============================================================================

test.describe('Layout stability on set completion (PR5 — H8)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkout').email,
      getUser('smokeWorkout').password,
    );
  });

  test('should keep adjacent set rows tappable after a set is completed and its hint slot collapses', async ({
    page,
  }) => {
    // Start a fresh workout with a single exercise + add a second set so
    // we have two rows. Complete set 1; without breaking out of the test
    // flow we then drive a tap on set 2's checkbox. Pre-fix on mobile
    // the row would reflow ~18dp and the next checkbox would have moved.
    // Post-fix the next checkbox stays where we expect.
    //
    // This is the functional cover for H8 — proves the next-checkbox is
    // still reachable after a completion event. The widget test pins the
    // exact geometry contract; this spec proves the user-visible outcome
    // (no broken tap chain) in the live app.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Fill set 1 and complete it.
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Add a second set so we have an adjacent row. Tap the Add Set button
    // — by then set 1 is checked and the hint slot above set 2 may or may
    // not be visible depending on prev-session data (smokeWorkout user
    // has none on a fresh exercise, so the hint slot is empty by default).
    const addSet = page.locator(WORKOUT.addSetButton).first();
    await expect(addSet).toBeVisible({ timeout: 10_000 });
    await addSet.click();

    // Set 2 was just added — there's a 600ms isNew lock on its checkbox
    // (BUG-018 / fat-thumb defense). Wait it out before tapping.
    await page.waitForTimeout(700);

    // Fill values for set 2 (any value — we just need a sane state) then
    // tap its done checkbox. The contract under test: this tap lands on
    // the set-2 checkbox without us having to re-find it.
    //
    // setIndex=0: after completing set 1, only set 2's checkbox remains in
    // the `workout-set-done` locator pool. `completeSet` indexes into the
    // currently-uncompleted checkboxes, not into global row positions.
    await setReps(page, '5');
    await completeSet(page, 0);

    // Cleanup: discard so the next run starts fresh.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await dismissCelebrationIfPresent(page).catch(() => {});
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
  });
});

// =============================================================================
// PR-6 / M6 — `activeWorkoutRowDisplaysProvider` loading-state contract
// =============================================================================
//
// Pre-fix `exercisePRsProvider(...).value ?? const []` flattened "loading"
// and "no PRs" into the same empty-baseline branch. While `personal_records`
// was in flight every completed working set was projected as a standing PR
// (gold stripe + bracket / `set-row-state-standing-pr` identifier), then the
// rows reclassified once data landed. Visual flicker, false predicted-PR cue.
//
// The fix gates on `AsyncValue.value`: while it is null (first emission in
// flight, or error with no prior data), every row resolves to
// `PrRowState.none` — identifier `set-row-state-none`. Once the future
// settles to `AsyncData(...)` the resolver runs normally and rows re-emit
// with their real classification (here, since the test user has no PR
// records yet, the first completed working set should become standing PR).
//
// The unit suite owns the contract precisely (loading / error / transition).
// This E2E pins the user-visible behavior end-to-end via the AOM identifier
// node emitted by `_SetRowFrame` in `set_row.dart`.
test.describe('PR-row state during loading (PR6 — M6)', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkoutPr6RowFlicker').email,
      getUser('smokeWorkoutPr6RowFlicker').password,
    );
  });

  test('should NOT classify completed sets as standing-PR while exercisePRsProvider is loading; should reclassify once data lands', async ({
    page,
  }) => {
    // ---- Phase 1: wait for home so prCacheBootstrap has time to flush -----
    //
    // `prCacheBootstrapProvider` fires `getRecordsForUser` (a `user_id=eq.X`
    // GET to /rest/v1/personal_records) shortly after login. We wait for the
    // home tab to be visible so the bootstrap GET has a fair chance to
    // complete before our route handler is installed. The route filter
    // below ALSO defensively passes through `user_id=eq.` GETs in case the
    // bootstrap is still in flight when the route is installed — only
    // `exercise_id=in.` GETs (the row provider's `exercisePRsProvider`
    // dependency) get held.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    // ---- Phase 2: install the per-exercise stall BEFORE addExercise ------
    //
    // `addExercise()` auto-creates the first set (clicks "Add Set" at the
    // end of its body), which mounts `activeWorkoutRowDisplaysProvider`
    // and fires `exercisePRsProvider(benchId).future`. The route MUST be
    // in place before that — otherwise the GET resolves before we can
    // observe the loading window.
    let signalIntercepted!: () => void;
    const intercepted = new Promise<void>((resolve) => {
      signalIntercepted = resolve;
    });

    let stallRequests = true;

    // Match GETs to /rest/v1/personal_records WHOSE QUERY contains
    // `exercise_id=in.` — the per-exercise filter shape Supabase emits for
    // `_records.select().inFilter('exercise_id', [...])`. The bootstrap
    // query (`?user_id=eq.X&order=achieved_at.desc.nullslast`) does NOT
    // match this filter and continues uninterrupted, even if it happens to
    // race the route install. URL-only matching on the path then a
    // method-and-query gate inside the handler keeps non-target traffic
    // (POST /upsert, GET ?user_id=eq for the prListProvider / bootstrap)
    // flowing.
    const PR_URL = (url: URL) => url.pathname.endsWith('/rest/v1/personal_records');

    const routeFilter = async (route: import('@playwright/test').Route) => {
      const req = route.request();
      const url = req.url();
      const isExerciseFilter = url.includes('exercise_id=in.');
      if (req.method() !== 'GET' || !isExerciseFilter) {
        await route.continue();
        return;
      }
      // Per-exercise PR fetch — the row provider's dependency. Hold here
      // until the test releases the stall, then continue normally so the
      // app receives a real (empty) records list and the provider settles
      // into AsyncData(const <PersonalRecord>[]).
      signalIntercepted();
      while (stallRequests) {
        await new Promise<void>((r) => setTimeout(r, 100));
      }
      await route.continue();
    };

    await page.route(PR_URL, routeFilter);

    // ---- Phase 3: drive the active workout into the loading window -------
    //
    // startEmptyWorkout → addExercise. The latter auto-creates set #1,
    // which mounts the row provider and fires the per-exercise GET that
    // our handler now stalls.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Wait until our handler captured the per-exercise GET. Proves the
    // stall is live before any value mutation could trigger a PR
    // projection.
    await intercepted;

    // Set positive weight + reps. The default 0/0 set wouldn't project
    // as a predicted PR even with the empty-baseline bug (the resolver
    // short-circuits on `weight <= 0` / `reps <= 0`), so we MUST seed
    // values that WOULD project as a PR to make the loading-window
    // assertion load-bearing. setWeight / setReps drive purely the UI
    // (TextField dialogs) and don't depend on the held PR fetch.
    await setWeight(page, '80');
    await setReps(page, '5');

    // ---- Phase 4: assert the row is NOT classified as a (predicted) PR --
    //
    // While `prsAsync.value` is null (the GET is held), the row provider
    // returns `PrRowDisplay.plain(PrRowState.none)` for every set, which
    // `_SetRowFrame` maps to identifier `set-row-state-none`. Pre-fix the
    // empty-baseline projection produced `set-row-state-pending-pr` (gold
    // ◆) for set #1's 80×5 because the resolver saw an empty `runningBest`
    // map and treated every positive (weight, reps) as breaking it. This
    // assertion is the load-bearing M6 pin: NO PR-classified row
    // identifier may appear while the baseline is unknown.
    //
    // We assert on the un-completed (pending) set because completing it
    // requires the rest-timer dismiss path, which adds incidental
    // complexity. The same loading-window guard governs both pending and
    // completed rows — pre-fix `pendingPredictedPr` and `completedStandingPr`
    // both leaked through the empty-baseline branch.
    await expect(page.locator(SET_ROW.stateNone).first()).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(SET_ROW.statePendingPr)).toHaveCount(0, {
      timeout: 1_000,
    });
    await expect(page.locator(SET_ROW.stateStandingPr)).toHaveCount(0, {
      timeout: 1_000,
    });

    // ---- Phase 5: release the stall + assert reclassification -------------
    //
    // After releasing, the per-exercise GET resolves with `[]` (fresh user
    // has no records). The resolver then runs against the empty baseline
    // and projects the pending working set (80×5) as a predicted PR —
    // identifier flips to `set-row-state-pending-pr`. This pins the
    // loading→loaded transition: the row reclassifies once data lands,
    // proving the loading-state guard is the only thing that was hiding
    // the (correct, post-load) classification.
    stallRequests = false;
    await expect(page.locator(SET_ROW.statePendingPr).first()).toBeVisible({
      timeout: 10_000,
    });

    // Defensive cleanup — remove the route handler (same pattern as PR-1
    // Q1 / PR-2 Fix B): pass the SAME function reference passed to
    // page.route to remove the SAME handler.
    await page.unroute(PR_URL, routeFilter);

    // Discard so the next test invocation starts from a clean lapsed state.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await dismissCelebrationIfPresent(page).catch(() => {});
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
  });
});

// =============================================================================
// Phase 23 D1 — rest-overlay chrome visibility (smokeRestChrome user)
//
// **Flutter Web back-button convention** (rediscovered 2026-05-12 during
// Phase 23 root-cause triage):
//
// Flutter's `PopScope.onPopInvokedWithResult` fires for `popRoute`
// system-channel events. On Flutter Web, browser back / `window.history.back()`
// does NOT produce a `popRoute` message — `MultiEntriesBrowserHistory.onPopState`
// (which GoRouter relies on) routes browser `popstate` to a `pushRouteInformation`
// message that the `Router` consumes by changing the route. The PopScope callback
// of the OUTGOING screen is never invoked. Keyboard `Escape` is unwired entirely.
//
// Net effect for E2E: there is NO Flutter-Web-reachable path that fires the
// active-workout PopScope's `onPopInvokedWithResult`. That callback is
// Android-hardware-back-only. The deeper PopScope branch chain (D2/D3) is
// fully owned by `active_workout_back_button_priority_test.dart` via
// `tester.binding.handlePopRoute()`. The E2E layer here ONLY pins the
// user-observable chrome contract: that the FAB + Finish bar hide while
// the rest overlay is visible (D1). Rest dismissal happens via the Skip
// button on the rest overlay — the user-visible discoverable surface that
// works on both web and Android.
// =============================================================================
test.describe('Rest overlay chrome', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeRestChrome').email,
      getUser('smokeRestChrome').password,
    );
  });

  test(
    'should hide add-exercise FAB and finish bar while rest timer is visible',
    async ({ page }) => {
      // Drive the workout into the rest-active state, then assert the
      // FAB + Finish bar are absent. After dismissing the rest timer
      // via its own Skip button, both surfaces must reappear — pins both
      // the hide AND the restore halves of the D1 contract.
      await startEmptyWorkout(page);
      await addExercise(page, SEED_EXERCISES.benchPress);
      // Phase 23 D6: addExercise auto-seeds set 1. Set a non-zero weight
      // so the row is meaningful; complete it to fire the rest timer.
      await setWeight(page, '60');
      await setReps(page, '8');

      // Pre-condition: chrome is visible while rest is OFF.
      await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible({
        timeout: 5_000,
      });
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 5_000,
      });

      // Trigger rest by completing set 1. The rest-timer progressbar is
      // the user-visible sentinel for "rest is active."
      await page.locator(WORKOUT.markSetDone).first().click();
      const restTimer = page.locator('role=progressbar[name*="Rest timer"]');
      await expect(restTimer).toBeVisible({ timeout: 8_000 });

      // Phase 23 D1 contract: both surfaces must be hidden during rest.
      await expect(page.locator(WORKOUT.addExerciseFab)).toBeHidden({
        timeout: 3_000,
      });
      await expect(page.locator(WORKOUT.finishButton)).toBeHidden({
        timeout: 3_000,
      });

      // Dismiss the rest timer via its own Skip button — the only
      // Flutter-Web-reachable dismissal path. Note: browser back /
      // keyboard Escape do NOT fire PopScope on Flutter Web — see file
      // header. Skip is the user-visible affordance that works on both
      // platforms.
      const skip = page.locator('role=button[name*="Skip"]').first();
      await skip.click();
      await expect(restTimer).toBeHidden({ timeout: 5_000 });

      // After dismiss: chrome must reappear immediately. Drives the
      // "restore" branch of the D1 contract — proves the gate is
      // reactive, not a one-shot hide.
      await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible({
        timeout: 5_000,
      });
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 5_000,
      });

      // Clean up so the next test invocation starts from a clean state.
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
      await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
    },
  );

  // Phase 23 D2/D3 PopScope priority chain (rest-dismiss vs discard)
  // is intentionally NOT covered at the E2E level — Flutter Web has no
  // way to fire `PopScope.onPopInvokedWithResult` (see file header). The
  // contract is fully pinned at the widget layer:
  //   * `active_workout_back_button_priority_test.dart` — all 4 priority
  //     cases (rest-only, no-rest, rest-and-loading, idempotent stop).
  //   * `active_workout_appbar_discard_during_rest_test.dart` — the
  //     in-rest AppBar discard affordance.
});

// =============================================================================
// Phase 23 D6 — addExercise auto-seeds set 1 (smokeAutoSeed user)
// =============================================================================
test.describe('Add exercise auto-seed', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeAutoSeed').email,
      getUser('smokeAutoSeed').password,
    );
  });

  test(
    'should auto-seed set 1 with last session values when adding an exercise mid-workout',
    async ({ page }) => {
      // Phase 23 D6: smokeAutoSeed has a prior completed workout with
      // Barbell Bench Press @ 80 kg × 8 (seeded in global-setup). Adding
      // bench press to a fresh workout must produce one set carrying
      // those exact values.
      await startEmptyWorkout(page);
      await addExercise(page, SEED_EXERCISES.benchPress);

      // The weight + reps stepper values must reflect the seeded prior
      // session. We probe the user-visible Semantics labels — the
      // stepper renders "Weight value: 80 kg" / "Reps value: 8" — to
      // avoid coupling to internal Text widget structure.
      await expect(
        page.locator('role=button[name*="Weight value: 80"]').first(),
      ).toBeVisible({ timeout: 10_000 });
      await expect(
        page.locator('role=button[name*="Reps value: 8"]').first(),
      ).toBeVisible({ timeout: 5_000 });

      // Clean up.
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
      await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
    },
  );
});
