/**
 * Crash and session recovery spec — merged from full suite.
 *
 * Tests resilience of the active workout persistence layer (Hive local storage).
 * The app stores the active workout in Hive so it survives navigation away and
 * full page reloads.
 *
 * Tests:
 *  1. Start a workout -> reload the page -> resume banner is visible on home
 *  2. Tap resume banner -> returns to the active workout screen with data intact
 *  3. Start a workout -> navigate away via tabs -> come back -> banner present
 *  4. HOME-004 (P0) — Resume banner disappears after finishing the workout
 *  5. Rapid double-tap on Finish does not create duplicate workouts
 *
 * Simulation notes:
 *  - "Close browser tab" is simulated by calling page.reload() which clears JS
 *    memory but preserves localStorage/IndexedDB (where Hive stores data in web).
 *  - "Navigate away" is simulated by clicking a different tab then returning.
 *  - "Double-tap Finish" is simulated by clicking the confirm button twice in
 *    rapid succession; the app should handle this gracefully (button disabled
 *    or navigation happens before second tap can register).
 *
 * Uses the dedicated `fullCrash` test user.
 * The Flutter web app is served automatically by Playwright's webServer config
 * during local dev. In CI the FLUTTER_APP_URL env var is set by the workflow.
 */

import { test, expect } from '@playwright/test';
import { dismissCelebrationIfPresent, waitForAppReady } from '../helpers/app';
import { login } from '../helpers/auth';
import { NAV, WORKOUT, HOME } from '../helpers/selectors';
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

// ---------------------------------------------------------------------------
// Full — crash and session recovery (no smoke equivalent)
// ---------------------------------------------------------------------------
test.describe('Crash and session recovery', () => {

  test.beforeEach(async ({ page }) => {
    await login(page, getUser('fullCrash').email, getUser('fullCrash').password);
  });

  test('should persist active workout across a full page reload and show resume banner', async ({
    page,
  }) => {
    // Start a workout and add an exercise so there is meaningful state to persist.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Verify the workout screen is active.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible();

    // Simulate a browser crash / tab close by reloading the page.
    await page.reload();

    // After reload the app re-initialises. waitForAppReady() re-enables the
    // semantics tree and waits for auth to resolve. document.body.innerText
    // is empty in CanvasKit (text drawn to canvas), so waitForFunction on
    // innerText would never fire.
    await waitForAppReady(page);

    // The active workout banner appears at the bottom of the home screen when
    // an active workout exists. It shows the workout name and elapsed time.
    // We look for:
    //   1. The active workout banner (role=button with "Workout —" prefix), OR
    //   2. A "Resume" text link, OR
    //   3. The app redirected directly to the active workout screen.
    const activeBannerVisible = await page
      .locator(HOME.activeBanner)
      .isVisible({ timeout: 10_000 })
      .catch(() => false);

    const resumeBannerVisible = !activeBannerVisible && await page
      .locator('text=Resume')
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    // Alternative: the app may redirect directly to the active workout screen.
    const workoutScreenVisible = !activeBannerVisible && !resumeBannerVisible && await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    expect(activeBannerVisible || resumeBannerVisible || workoutScreenVisible).toBe(true);

    // Clean up by discarding the workout.
    if (workoutScreenVisible) {
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
    } else {
      // Tap the active workout banner (or Resume link) to navigate to the workout.
      if (activeBannerVisible) {
        await page.locator(HOME.activeBanner).click();
      } else {
        await page.locator('text=Resume').click();
      }
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
    }

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should return to active workout with exercise data intact after tapping resume banner', async ({
    page,
  }) => {
    // Start a workout and add an exercise.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.squat);
    // Flutter CanvasKit renders exercise names to canvas — no DOM text node.
    // The name only appears in the exercise card group's accessible name.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.squat}"]`),
    ).toBeVisible({ timeout: 10_000 });

    // Reload to simulate crash.
    await page.reload();

    // waitForAppReady re-enables semantics after reload and waits for auth.
    await waitForAppReady(page);

    // If the active workout banner or resume link is visible, tap it.
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

    // After tapping (or direct redirect) the workout screen must be visible.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // The exercise that was added before the reload must still be there.
    // Flutter CanvasKit renders exercise names to canvas — no DOM text node.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.squat}"]`),
    ).toBeVisible({ timeout: 10_000 });

    // BUG-001 guard: the "Exercise" fallback must NOT appear as the card header.
    // If WorkoutExercise.exercise was excluded from toJson (the bug), then after
    // restore exercise is null and the UI falls back to 'Exercise' as the name.
    // The Semantics label becomes "Exercise: Exercise. Tap for details." — we
    // assert that pattern is absent to explicitly guard against BUG-001.
    const fallbackLabel = page.locator(
      'role=group[name*="Exercise: Exercise. Tap for details"]',
    );
    await expect(fallbackLabel).not.toBeVisible({ timeout: 3_000 });

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should still show resume banner after navigating to another tab and back', async ({
    page,
  }) => {
    // Start a workout.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.deadlift);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible();

    // Navigate away by going back to home first (the active workout screen is
    // full-screen without bottom navigation), then switching to the Exercises tab.
    await page.goBack();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
    await page.click(NAV.exercisesTab);
    await expect(page.locator('text=Exercises')).toBeVisible({
      timeout: 15_000,
    });

    // Return to Home.
    await page.click(NAV.homeTab);
    // W8: "Start Empty Workout" was removed. Confirm home tab is active via URL.
    await page.waitForURL('**/home**', { timeout: 15_000 });

    // The active workout banner or a resume link must still be present on the
    // home screen because the workout was not discarded.
    const activeBannerVisible = await page
      .locator(HOME.activeBanner)
      .isVisible({ timeout: 10_000 })
      .catch(() => false);

    const resumeVisible = !activeBannerVisible && await page
      .locator('text=Resume')
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    const workoutActiveVisible = !activeBannerVisible && !resumeVisible && await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    expect(activeBannerVisible || resumeVisible || workoutActiveVisible).toBe(true);

    // Clean up — navigate to workout screen then discard.
    if (workoutActiveVisible) {
      await page.locator(WORKOUT.discardButton).click();
    } else {
      if (activeBannerVisible) {
        await page.locator(HOME.activeBanner).click();
      } else {
        await page.locator('text=Resume').click();
      }
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
      await page.locator(WORKOUT.discardButton).click();
    }

    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should hide resume banner from home after finishing the workout (HOME-004)', async ({
    page,
  }) => {
    // Start a workout with one completed set so Finish succeeds cleanly.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Navigate to Home — the active workout banner must appear on the home screen.
    // The workout screen is full-screen without bottom nav, so go back first.
    await page.goBack();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
    // W8: "Start Empty Workout" removed. Home confirmed by NAV tab visibility above.

    // The _ActiveWorkoutBanner renders the workout name which starts with
    // "Workout \u2014". Verify it is present before finishing.
    const bannerBeforeFinish = page.locator(HOME.activeBanner);
    await expect(bannerBeforeFinish).toBeVisible({ timeout: 10_000 });

    // Tap the banner to return to the active workout screen.
    await bannerBeforeFinish.click();
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // Finish the workout.
    await finishWorkout(page);

    // Dismiss the PR celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    // Return to home if not already there.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
    await page.click(NAV.homeTab);
    // W8: "Start Empty Workout" removed. Home confirmed by NAV tab + URL.
    await page.waitForURL('**/home**', { timeout: 15_000 });

    // The banner must no longer be visible — the workout is finished.
    await expect(page.locator(HOME.activeBanner)).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should not create duplicate workouts on rapid double-tap of Finish', async ({
    page,
  }) => {
    // This test combines the celebration playback path (1.6 s ClassChangeOverlay
    // + 1.1 s rank-up + 1.1 s level-up + 1.1 s title) with the post-finish
    // navigation chain. Under CI 4-vCPU saturation the celebration sequence
    // alone can consume 6–8 s before `dismissCelebrationIfPresent` returns,
    // and the subsequent NAV-tab visibility check needs additional slack.
    // 60 s is the wrong budget for this scenario — the established pattern
    // (FLAKY_TESTS.md S12 carryover, `saga.spec.ts:437` class-badge test) is
    // to extend the budget to 120 s for "celebration chain + nav verification"
    // tests rather than weaken what they exist to validate.
    test.setTimeout(120_000);

    // Count save_workout RPC requests to verify the production re-entrance
    // guard (`FinishWorkoutCoordinator._isFinishing`) actually deduplicates.
    // Pattern lifted from `charter-d-exploratory.spec.ts:B11` — counting the
    // network requests is the real behavior contract (one save fires, not
    // two), independent of how cleanly the UI navigates.
    const saveRequests: string[] = [];
    page.on('request', (req) => {
      const url = req.url();
      if (url.includes('save_workout')) {
        saveRequests.push(url);
      }
    });

    // Complete a proper workout so we can verify only one is saved.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Open the finish confirmation dialog.
    await page.click(WORKOUT.finishButton);

    // The dialog has "Save & Finish" as the confirm button.
    const confirmFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(confirmFinish).toBeVisible({ timeout: 5_000 });

    // Resolve the button centre BEFORE clicking — once the first click fires,
    // the dialog dismisses and the locator is detached. We need stable
    // coordinates for the second click.
    const btnBox = await confirmFinish.boundingBox();
    if (!btnBox) {
      throw new Error('Save & Finish button has no bounding box');
    }
    const cx = btnBox.x + btnBox.width / 2;
    const cy = btnBox.y + btnBox.height / 2;

    // Fire two rapid mouse clicks at the same coordinates with an 80 ms gap.
    // Raw `page.mouse.click(x, y)` dispatches mousedown/mouseup to the browser
    // viewport directly — no DOM element resolution, no auto-waiting, no
    // detached-element retry. This is the only way to actually fire BOTH
    // clicks while the dialog is still on-screen, which is required to
    // exercise the production `_isFinishing` re-entrance guard in
    // `FinishWorkoutCoordinator`.
    //
    // Why NOT `locator.click()` twice: Playwright's locator click auto-waits
    // for the target element, and the project's default `actionTimeout` is
    // 15 s. After the first click dismisses the dialog the locator is detached,
    // so the second `await locator.click()` polls for 15 s before erroring —
    // burning the entire test budget on an internal Playwright retry that has
    // nothing to do with what we're testing.
    await page.mouse.click(cx, cy);
    await page.waitForTimeout(80);
    await page.mouse.click(cx, cy);

    // The app must navigate away cleanly — to celebration or home.
    // Use URL-based detection to avoid the ScaleTransition visibility race.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // Production contract: the `_isFinishing` re-entrance guard must collapse
    // both clicks into a single save_workout RPC call. If two RPCs fire,
    // either the guard is broken or the test isn't actually firing both
    // clicks while the dialog is still on-screen. Either way it's a real
    // regression. Note: web RPCs can also surface as POST to the Supabase
    // REST endpoint, which the URL-substring match above catches.
    expect(
      saveRequests.length,
      `Expected at most one save_workout RPC; got ${saveRequests.length}: ` +
        JSON.stringify(saveRequests),
    ).toBeLessThanOrEqual(1);

    // The app should be in a clean state — no crash, no duplicate dialogs.
    const hasErrorState = await page
      .locator('text=Error')
      .isVisible({ timeout: 3_000 })
      .catch(() => false);
    expect(hasErrorState).toBe(false);
  });
});
