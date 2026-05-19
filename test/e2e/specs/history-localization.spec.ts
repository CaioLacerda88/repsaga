/**
 * Workout history content localization — E2E scenario D1.
 * Phase 15f: exercise names in workout history resolved from exercise_translations.
 *
 * Scenarios:
 *   D1 — pt user sees workout summary in pt (exerciseSummary line shows pt name)
 */

import { test, expect } from '@playwright/test';
import { navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import { HISTORY, HOME } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { EXERCISE_NAMES } from '../fixtures/test-exercises';

// =============================================================================
// FULL: Workout history pt locale (D1)
// Uses fullHistoryPt user (pt locale, 5 seeded workouts; the most recent has
// a barbell_bench_press workout_exercise so its exerciseSummary renders the
// pt-localized name "Supino Reto com Barra").
// =============================================================================

test.describe('Workout history pt locale', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullHistoryPt').email,
      getUser('fullHistoryPt').password,
    );
  });

  // D1: pt user sees the pt-localized exercise name in the most recent
  // workout's summary line on the history screen.
  test('should show pt-localized exercise name in workout summary on history screen for pt user (D1)', async ({
    page,
  }) => {
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;

    // Navigate to Home and wait for it to render. 26f: the CharacterCard
    // is always-present on home and is the steady-state "home loaded"
    // sentinel — replaces the legacy home-status-line check.
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.characterCard)).toBeVisible({
      timeout: 15_000,
    });

    // Click the last-session line to enter history. The seed guarantees a
    // last session exists for this user (most recent workout has an exercise),
    // so we hard-fail if the line is missing — this is the only in-app entry
    // point to the history screen.
    await expect(page.locator(HOME.lastSessionLine)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(HOME.lastSessionLine).click();

    // The history screen heading must be visible (route /home/history).
    await expect(page.locator(HISTORY.heading)).toBeVisible({
      timeout: 10_000,
    });

    // Hard assertion (D1's primary contract): the most recent workout's
    // exerciseSummary line must render the pt-localized exercise name.
    // The summary is the bodySmall Text below the workout title.
    await expect(
      page.locator(`text=${ptBenchName}`).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Hard assertion: the en name must NOT leak into the pt user's history.
    await expect(
      page.locator(`text=${enBenchName}`),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});
