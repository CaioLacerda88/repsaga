/**
 * Routines content localization — E2E scenario E1.
 * Phase 15f: exercise names in routine create/edit resolved from exercise_translations.
 *
 * Scenarios:
 *   E1 — pt user creates routine with pt-picker → pt names in routine list
 */

import { test, expect } from '@playwright/test';
import { flutterFill, navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  ROUTINE,
  CREATE_ROUTINE,
  ROUTINE_MANAGEMENT,
  EXERCISE_PICKER,
  EXERCISE_LOC,
} from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { EXERCISE_NAMES } from '../fixtures/test-exercises';

// =============================================================================
// FULL: Routine create with pt exercise picker (E1)
// Uses smokeLocalizationRoutines user (pt locale, lapsed state)
// =============================================================================

test.describe('Routine localization pt locale', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalizationRoutines').email,
      getUser('smokeLocalizationRoutines').password,
    );
    await navigateToTab(page, 'Routines');
  });

  // E1: pt user creates routine with pt-picker → pt names in routine list.
  test('should show pt exercise names in routine exercise picker for pt user (E1)', async ({
    page,
  }) => {
    const routineName = `Rotina PT ${Date.now()}`;
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;

    // Open the create routine screen.
    await page.click(ROUTINE_MANAGEMENT.createIconButton);
    await expect(
      page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle),
    ).toBeVisible({ timeout: 10_000 });

    // Enter a routine name.
    const nameInput = page.locator(CREATE_ROUTINE.nameInput);
    await expect(nameInput).toBeVisible({ timeout: 5_000 });
    await nameInput.fill(routineName);

    // Open the exercise picker.
    await page.click(CREATE_ROUTINE.addExerciseButton);
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });

    // Search for the pt bench press name. flutterFill is required — Flutter
    // CanvasKit ignores synthetic events from page.fill().
    await flutterFill(
      page,
      EXERCISE_PICKER.searchInput,
      ptBenchName.substring(0, 6),
    );
    await page.waitForTimeout(800);

    // E1 hard assertion: the pt-named picker entry MUST be present. A
    // misconfigured RPC or wrong locale resolution would fail this.
    const ptAddButton = page
      .locator(EXERCISE_LOC.addExerciseButton(ptBenchName, 'pt'))
      .first();
    await expect(ptAddButton).toBeVisible({ timeout: 10_000 });
    await ptAddButton.click();

    // Wait for the picker to close (back to create-routine screen).
    await expect(
      page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle),
    ).toBeVisible({ timeout: 10_000 });

    // Save the routine.
    await page.click(CREATE_ROUTINE.saveButton);

    // Should navigate back to the routines list.
    await expect(page.locator(ROUTINE.heading)).toBeVisible({ timeout: 15_000 });

    // The routine must appear in MY ROUTINES section.
    await expect(
      page.locator(ROUTINE.routineName(routineName)),
    ).toBeVisible({ timeout: 10_000 });
  });
});
