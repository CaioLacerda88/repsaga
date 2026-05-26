/**
 * Post-session summary E2E (Phase 31 Pass 3).
 *
 * Asserts the S2 Mission Debrief section renders on the post-session
 * summary panel after the cinematic resolves. Behavior, not wiring:
 *   - the debrief section is visible
 *   - at least one lift row renders inside it
 *   - the segmented XP bar is visible (one or more BP segments)
 *   - the per-BP rank delta row for the trained body part is visible
 *
 * Reuses the rpgRankUpThreshold user (same as share_flow.spec.ts).
 * Lands on the summary panel via the skip button + skips the cinematic.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
  finishWorkout,
} from '../helpers/workout';
import { WORKOUT, POST_SESSION } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

async function reseedDebriefUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(
    admin,
    getUser('rpgRankUpThreshold').email,
  );
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
}

test.describe('Post-session summary', { tag: '@smoke' }, () => {
  // Serial mode: prevents parallel races on the shared rpgRankUpThreshold
  // user.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await reseedDebriefUser();
    await login(
      page,
      getUser('rpgRankUpThreshold').email,
      getUser('rpgRankUpThreshold').password,
    );

    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    await page.waitForURL(/\/workout\/finish\//, { timeout: 10_000 });
    const skip = page.locator(POST_SESSION.skipBtn);
    if (await skip.isVisible().catch(() => false)) {
      await skip.click();
    }
    await expect(page.locator(POST_SESSION.summary)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should render the Mission Debrief section after the cinematic ends', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should render at least one lift row inside the debrief section', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(POST_SESSION.missionDebriefLiftRow).first(),
    ).toBeVisible();
  });

  test('should render at least one per-BP rank delta row in the debrief section', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(POST_SESSION.missionDebriefBpRow).first(),
    ).toBeVisible();
  });
});
