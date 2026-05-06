/**
 * Workout content localization — E2E scenarios C1, C2.
 * Phase 15f: exercise names in active workout resolved from exercise_translations.
 *
 * Scenarios:
 *   C1 @smoke — pt user starts workout from pt-picker → pt names in workout screen
 *   C2         — locale switch during workout → fetched exercises reflect new locale on refresh
 */

import { test, expect } from '@playwright/test';
import { flutterFill, navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  WORKOUT,
  EXERCISE_PICKER,
  EXERCISE_LOC,
  PROFILE,
  SAGA,
} from '../helpers/selectors';
import { startEmptyWorkout } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';
import { EXERCISE_NAMES } from '../fixtures/test-exercises';

// =============================================================================
// SMOKE: Active workout pt names (C1)
// Uses smokeLocalizationWorkout user (pt locale, lapsed state)
// =============================================================================

test.describe('Active workout pt locale', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalizationWorkout').email,
      getUser('smokeLocalizationWorkout').password,
    );
  });

  test.afterEach(async ({ page }) => {
    // Clean up any in-progress workout to avoid state leakage.
    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (finishVisible) {
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
    }
  });

  // C1: pt user starts workout from pt-picker → pt names in workout screen.
  test('should show pt exercise names in active workout after adding exercise from pt picker (C1)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // BUG-020: Finish button only appears after first exercise is added.
    // Open the exercise picker immediately.
    await page.click(WORKOUT.addExerciseFab);
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });

    // Search for the pt bench press name using flutterFill (Flutter CanvasKit
    // requires real keyboard events; page.fill() uses synthetic events Flutter
    // ignores). Substring keeps the search permissive.
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;
    await flutterFill(page, EXERCISE_PICKER.searchInput, ptBenchName.substring(0, 6));
    await page.waitForTimeout(800);

    // Hard assertion: the pt-named picker entry must be present, not a fallback
    // generic "Adicionar " match. A misconfigured RPC would fail this.
    const ptAddButton = page
      .locator(EXERCISE_LOC.addExerciseButton(ptBenchName, 'pt'))
      .first();
    await expect(ptAddButton).toBeVisible({ timeout: 10_000 });
    await ptAddButton.click();

    // Workout screen shows the active session.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });

    // Hard assertion: the active-workout exercise card MUST show the pt name.
    await expect(
      page.locator(EXERCISE_LOC.exerciseDetailTap(ptBenchName, 'pt')).first(),
    ).toBeVisible({ timeout: 10_000 });

    // The en name must NOT leak into the active workout.
    await expect(
      page.locator(
        EXERCISE_LOC.exerciseDetailTap(EXERCISE_NAMES.barbell_bench_press.en, 'en'),
      ),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});

// =============================================================================
// FULL: Locale switch during workout (C2)
// Uses smokeLocalizationEn user (en locale, can switch to pt)
// =============================================================================

test.describe('Locale switch during workout', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalizationEn').email,
      getUser('smokeLocalizationEn').password,
    );
  });

  test.afterEach(async ({ page }) => {
    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (finishVisible) {
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
    }
  });

  // C2: locale switch → exercise picker shows new locale names.
  // Design note: the workout screen blocks the bottom nav bar while a workout
  // is active. So we: (1) switch locale via Profile, (2) start a new workout
  // and verify the exercise picker shows pt names.
  test('should reflect new locale for exercise names after switching locale mid-workout (C2)', async ({
    page,
  }) => {
    // Step 1: Switch locale to pt via Profile Settings → Language.
    // Phase 18b: /profile shows CharacterSheet; language row is on /profile/settings.
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await expect(page.locator(PROFILE.languageRow)).toBeVisible({ timeout: 10_000 });
    await page.click(PROFILE.languageRow);
    await expect(page.locator(PROFILE.languagePickerSheet)).toBeVisible({ timeout: 5_000 });
    await page.click(PROFILE.languageOption('pt'));
    await page.waitForTimeout(800);

    // Step 2: Navigate to Home, then start a new workout.
    await navigateToTab(page, 'Home');

    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    // Step 3: Open the exercise picker — it must show pt exercise names.
    await page.click(WORKOUT.addExerciseFab);
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });

    // Search for bench press using the pt name. flutterFill is required —
    // Flutter ignores synthetic events from page.fill().
    await flutterFill(
      page,
      EXERCISE_PICKER.searchInput,
      EXERCISE_NAMES.barbell_bench_press.pt.substring(0, 6),
    );
    await page.waitForTimeout(800);

    // Hard assertion: the picker MUST show the pt-named bench press after the
    // locale switch. This is C2's primary contract — locale switch invalidates
    // the locale-affected cache and the next picker fetch returns pt names.
    await expect(
      page
        .locator(
          EXERCISE_LOC.addExerciseButton(EXERCISE_NAMES.barbell_bench_press.pt, 'pt'),
        )
        .first(),
    ).toBeVisible({ timeout: 10_000 });
  });
});
