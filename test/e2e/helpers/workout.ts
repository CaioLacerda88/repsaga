/**
 * Workout action helpers for E2E tests.
 *
 * These helpers drive the active-workout screen interactions. Each helper
 * isolates a single UI action so smoke specs remain readable.
 *
 * Assumes the user is already logged in before calling these helpers.
 *
 * CanvasKit renderer notes
 * ------------------------
 * Flutter web (CanvasKit) does not render standard HTML elements for most
 * widgets — it draws to <canvas>. However, text fields are an exception:
 * Flutter injects a hidden <input> overlay into the DOM when a TextField
 * receives focus so that the OS keyboard and clipboard work. Playwright can
 * interact with this overlay using the generic 'input' selector.
 *
 * The weight and reps entry dialogs work as follows:
 *   1. Tap the large value text in the set row (initially "0" for both).
 *      WeightStepper / RepsStepper open an AlertDialog with a TextField.
 *   2. The AlertDialog title ("Enter weight" / "Enter reps") confirms focus.
 *   3. Flutter renders a hidden <input> overlay for the focused TextField.
 *      Using `page.locator('input').last()` targets this overlay.
 *   4. Clear and fill the input, then click "OK" to confirm.
 */

import { Page, expect } from '@playwright/test';
import { flutterFill } from './app';
import { WORKOUT, EXERCISE_PICKER, HOME, FIRST_WORKOUT_CTA } from './selectors';

/**
 * Start an empty workout from the Home screen.
 *
 * W8 Home refresh removed the "Start Empty Workout" FilledButton. The helper
 * now handles two home states:
 *
 *   - Lapsed state (has history, no plan): taps "Quick workout" OutlinedButton.
 *   - Brand-new state (no history, no plan): the hero shows "YOUR FIRST WORKOUT"
 *     which starts the Full Body routine, not an empty workout. In this case we
 *     fall back to tapping the beginner CTA (FIRST_WORKOUT_CTA.card — the button
 *     role selector) and accept that it starts a routine instead of an empty
 *     workout. Tests using freshStateUsers that need truly empty workouts should
 *     ensure lapsed state by completing one workout first.
 *
 * For tests that need a truly empty workout (no exercises pre-filled), use the
 * lapsed state by ensuring the user has at least one completed workout before
 * calling this helper. Users in global-setup freshStateUsers start brand-new
 * but transition to lapsed after the first test in each suite completes a workout.
 */
export async function startEmptyWorkout(page: Page): Promise<void> {
  // W8 Home refresh removed the "Start Empty Workout" FilledButton.
  // The entry points are now state-dependent:
  //   - Lapsed (has history, no plan): "Quick workout" OutlinedButton
  //   - Brand-new (no history, no plan): "YOUR FIRST WORKOUT" hero CTA
  //
  // Wait for the home screen to stabilise (either state is visible), then click
  // the appropriate entry point. We use waitFor({ state: 'visible' }) so the
  // helper actually waits rather than doing an immediate snapshot check.
  //
  // Prefer "Quick workout" (lapsed state). If it never appears within 10 s,
  // fall back to the "YOUR FIRST WORKOUT" beginner CTA (brand-new state).

  const quickWorkoutLoc = page.locator(HOME.quickWorkout).first();
  const beginnerCtaLoc = page.locator(FIRST_WORKOUT_CTA.card).first();

  // Race the two locators: whichever becomes visible first wins.
  const quickWorkoutVisible = await quickWorkoutLoc
    .waitFor({ state: 'visible', timeout: 10_000 })
    .then(() => true)
    .catch(() => false);

  if (quickWorkoutVisible) {
    await quickWorkoutLoc.click();
  } else {
    // Brand-new state: the beginner CTA card is the only entry point.
    // Use .first() to guard against Flutter AOM duplicate nodes.
    await beginnerCtaLoc.waitFor({ state: 'visible', timeout: 10_000 });
    await beginnerCtaLoc.click();
    // Flutter CanvasKit may need a second tap to fire the InkWell after the
    // first click activates the semantics overlay.
    await page.waitForTimeout(800);
    // BUG-020: WORKOUT.finishButton is no longer used as the navigation
    // sentinel here. After BUG-020 the Finish button lives in the bottom bar
    // and is HIDDEN on the empty workout body (no exercises yet). Use the
    // Add Exercise FAB / empty-state CTA instead — it is always visible on
    // the active workout screen regardless of exercise count.
    const navigated = await page
      .locator(WORKOUT.addExerciseFab)
      .isVisible({ timeout: 2_000 })
      .catch(() => false);
    if (!navigated) {
      await beginnerCtaLoc.click().catch(() => {});
      await page.waitForTimeout(800);
    }
  }

  // BUG-020: confirm we reached the active workout screen by waiting for the
  // Add Exercise entry point (visible on both empty-body and FAB states).
  // The Finish button is now hidden on the empty body — do NOT use it here.
  await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible({
    timeout: 20_000,
  });
}

/**
 * Add an exercise to the active workout via the exercise picker bottom sheet.
 *
 * Clicks the "Add Exercise" FAB, types the exercise name into the search field,
 * then taps the matching "Add <name>" tile to add it.
 */
export async function addExercise(
  page: Page,
  exerciseName: string,
): Promise<void> {
  await page.click(WORKOUT.addExerciseFab);

  // The picker opens as a bottom sheet with a search field.
  await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
    timeout: 10_000,
  });

  await flutterFill(page, EXERCISE_PICKER.searchInput, exerciseName);

  // Wait for the debounce / filter to apply, then select the exercise.
  // Flutter CanvasKit renders duplicate semantics nodes for each exercise card,
  // so we use .first() to avoid strict-mode violations.
  const addButton = page.locator(EXERCISE_PICKER.addExerciseButton(exerciseName)).first();
  await expect(addButton).toBeVisible({ timeout: 10_000 });
  await addButton.click();

  // Wait for the picker to dismiss and the exercise to appear in the workout.
  await expect(page.locator(EXERCISE_PICKER.searchInput)).not.toBeVisible({
    timeout: 10_000,
  });

  // Phase 23 D6: `ActiveWorkoutNotifier.addExercise` now auto-seeds set 1
  // with prior-session working values (or equipment defaults when there's
  // no prior data). The exercise card renders with one set immediately —
  // no `Add Set` click required. The weight button is the user-visible
  // sentinel for "set 1 is rendered."
  await expect(
    page.locator('role=button[name*="Weight value"]').first(),
  ).toBeVisible({ timeout: 10_000 });
}

/**
 * Set the weight for the next uncompleted set by tapping its value.
 *
 * Taps the first visible weight value text to open the "Enter weight" dialog,
 * clears the existing value, types the new value, and confirms with "OK".
 *
 * Implementation note: WeightStepper shows the current value as large text
 * (e.g. "0") inside a GestureDetector. Tapping it opens an AlertDialog.
 * Flutter renders a hidden <input> overlay for the focused TextField inside
 * the dialog, which Playwright can target with `page.locator('input').last()`.
 */
export async function setWeight(page: Page, value: string): Promise<void> {
  // The weight value has a Semantics label like "Weight value: 0 kg. Tap to enter weight."
  // Click the LAST matching weight button to open the "Enter weight" dialog.
  //
  // Why .last(): WeightStepper is rendered for ALL sets regardless of completion
  // state. After completing sets from earlier exercises, their weight buttons
  // remain in DOM. The most recently added (uncompleted) set is always last in
  // DOM order. Using .first() incorrectly targets a completed set's button.
  await page.locator('role=button[name*="Weight value"]').last().click();

  // Wait for the OK button to confirm the dialog is open. We avoid using
  // `text=Enter weight` because the weight button's own semantics label
  // ("...Tap to enter weight.") also matches that selector.
  const okButton = page.locator('text="OK"');
  await expect(okButton).toBeVisible({ timeout: 5_000 });

  // The dialog TextField focuses automatically. Select all existing content
  // and type the new value using real keyboard events.
  await page.waitForTimeout(300);
  await page.keyboard.press('Control+a');
  await page.keyboard.type(value, { delay: 10 });

  await okButton.click();

  // Wait for the OK button to disappear — confirms the dialog dismissed.
  await expect(okButton).not.toBeVisible({ timeout: 5_000 });
}

/**
 * Set the reps for the next uncompleted set by tapping its value.
 *
 * Taps the first visible reps value text to open the "Enter reps" dialog,
 * clears the existing value, types the new value, and confirms with "OK".
 *
 * Implementation note: After setting weight, the weight cell shows the new
 * value (no longer "0"), so the first "0" text visible is now the reps value.
 */
export async function setReps(page: Page, value: string): Promise<void> {
  // The reps value has a Semantics label like "Reps value: 0. Tap to enter reps."
  // Click the LAST matching reps button to open the "Enter reps" dialog.
  //
  // Why .last(): RepsStepper is rendered for ALL sets regardless of completion
  // state. After completing sets from earlier exercises, their reps buttons
  // remain in DOM. The most recently added (uncompleted) set is always last in
  // DOM order. Using .first() incorrectly targets a completed set's button.
  await page.locator('role=button[name*="Reps value"]').last().click();

  // Wait for the OK button to confirm the dialog is open. We avoid using
  // `text=Enter reps` because the reps button's own semantics label
  // ("...Tap to enter reps.") also matches that selector.
  const okButton = page.locator('text="OK"');
  await expect(okButton).toBeVisible({ timeout: 5_000 });

  // The dialog TextField focuses automatically. Select all existing content
  // and type the new value using real keyboard events.
  await page.waitForTimeout(300);
  await page.keyboard.press('Control+a');
  await page.keyboard.type(value, { delay: 10 });

  await okButton.click();

  // Wait for the OK button to disappear — confirms the dialog dismissed.
  await expect(okButton).not.toBeVisible({ timeout: 5_000 });
}

/**
 * Mark a set as completed by clicking its checkbox.
 *
 * Flutter CanvasKit may consume the first click to activate the semantics
 * overlay without forwarding the tap to the Checkbox widget. If the checkbox
 * doesn't toggle after 2 seconds, we retry.
 *
 * @param page - Playwright page.
 * @param setIndex - Zero-based index of the set row (defaults to 0, the first set).
 */
export async function completeSet(
  page: Page,
  setIndex: number = 0,
): Promise<void> {
  const checkboxes = page.locator(WORKOUT.markSetDone);
  const completed = page.locator(WORKOUT.setCompleted);
  const restTimer = page.locator('role=progressbar[name*="Rest timer"]');

  await expect(checkboxes.nth(setIndex)).toBeVisible({ timeout: 5_000 });

  // Helper: dismiss the rest timer overlay if visible. The overlay covers the
  // entire screen and intercepts all clicks, so we must dismiss it before any
  // subsequent interaction.
  //
  // Flutter CanvasKit renders the rest timer as a GestureDetector with "tap
  // anywhere to dismiss". Playwright's locator.click() may not reliably trigger
  // Flutter's gesture detector on the overlay. Use page.mouse.click() on the
  // viewport center for a raw pointer event that Flutter processes as a tap.
  async function dismissRestTimer(): Promise<void> {
    const visible = await restTimer.isVisible({ timeout: 3_000 }).catch(() => false);
    if (!visible) return;

    // Strategy 1: Click "Skip" button if visible — most reliable dismissal.
    // Use .first() to avoid strict-mode failures (nested flt-semantics may
    // duplicate the button in the accessibility tree).
    const skipButton = page.locator('role=button[name*="Skip"]').first();
    const hasSkip = await skipButton.isVisible({ timeout: 1_000 }).catch(() => false);
    if (hasSkip) {
      await skipButton.click();
      await restTimer.waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});
    }

    // Strategy 2: If Skip didn't work, tap the center of the viewport.
    // Flutter's GestureDetector wrapping the rest timer overlay responds to
    // taps anywhere on screen. A raw mouse click bypasses Playwright's element
    // targeting and sends the event directly to the browser.
    const stillVisible = await restTimer.isVisible({ timeout: 500 }).catch(() => false);
    if (stillVisible) {
      const viewport = page.viewportSize() ?? { width: 1280, height: 720 };
      await page.mouse.click(viewport.width / 2, viewport.height / 2);
      await restTimer.waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});
    }

    // Strategy 3: Last resort — press Escape key.
    const finalCheck = await restTimer.isVisible({ timeout: 500 }).catch(() => false);
    if (finalCheck) {
      await page.keyboard.press('Escape');
      await restTimer.waitFor({ state: 'hidden', timeout: 3_000 }).catch(() => {});
    }
  }

  // Helper: check if the set already transitioned to the completed state.
  // Uses .or() to check both the nth "Set completed" checkbox AND a single
  // "Set completed" (when there's only one completed set on screen, nth(0)).
  async function isSetCompleted(): Promise<boolean> {
    return completed.nth(setIndex)
      .isVisible({ timeout: 2_000 })
      .catch(() => false);
  }

  // Attempt 1: Click the checkbox. The rest timer may appear after the click.
  await checkboxes.nth(setIndex).click();

  // Wait a moment for the rest timer to potentially appear, then dismiss it.
  // The rest timer animation starts ~200ms after the checkbox click.
  await page.waitForTimeout(500);
  await dismissRestTimer();

  // Check if the set is now completed.
  let didToggle = await isSetCompleted();

  // Attempt 2: Flutter CanvasKit may consume the first click to activate the
  // semantics overlay without forwarding the tap. Wait briefly for the overlay
  // to settle, then retry with a proper click sequence.
  if (!didToggle) {
    // Always dismiss the rest timer first — it may have appeared since last check.
    await dismissRestTimer();

    const stillUnchecked = await checkboxes.nth(setIndex)
      .isVisible({ timeout: 1_000 })
      .catch(() => false);
    if (stillUnchecked) {
      // Small delay to let the semantics overlay fully activate after the first click.
      await page.waitForTimeout(500);
      await checkboxes.nth(setIndex).click({ timeout: 5_000 }).catch(() => {});
      await page.waitForTimeout(500);
      await dismissRestTimer();
      didToggle = await isSetCompleted();
    } else {
      // Checkbox is gone (toggled) but "Set completed" wasn't visible — maybe
      // the rest timer overlay was covering it. Dismiss again and re-check.
      await dismissRestTimer();
      didToggle = await isSetCompleted();
    }
  }

  // Attempt 3: Use page.mouse for a raw pointer event that bypasses Playwright's
  // element targeting. This is more reliable for Flutter CanvasKit's semantics overlay.
  if (!didToggle) {
    await dismissRestTimer();
    const stillUnchecked = await checkboxes.nth(setIndex)
      .isVisible({ timeout: 1_000 })
      .catch(() => false);
    if (stillUnchecked) {
      const box = await checkboxes.nth(setIndex).boundingBox();
      if (box) {
        await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
        await page.waitForTimeout(500);
        await dismissRestTimer();
      }
    } else {
      // Checkbox toggled but completion state wasn't detected — rest timer
      // might still be obscuring the view.
      await dismissRestTimer();
    }
  }

  await expect(completed.nth(setIndex)).toBeVisible({ timeout: 10_000 });
}

/**
 * Finish the active workout.
 *
 * Clicks "Finish Workout" in the bottom bar, then clicks the "Finish Workout"
 * button inside the confirmation dialog. After this the app navigates away
 * from the active workout screen (to the PR celebration or Home).
 */
export async function finishWorkout(page: Page): Promise<void> {
  // Dismiss any lingering rest timer overlay that could intercept the click.
  const restTimer = page.locator('role=progressbar[name*="Rest timer"]');
  const hasRestTimer = await restTimer
    .isVisible({ timeout: 1_000 })
    .catch(() => false);
  if (hasRestTimer) {
    await restTimer.click({ force: true });
    await restTimer.waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});
  }

  await page.click(WORKOUT.finishButton);

  // Confirmation dialog appears — click the "Save & Finish" action button.
  const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
  await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
  await dialogFinish.click();
}
