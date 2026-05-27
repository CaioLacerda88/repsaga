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
import { WORKOUT, POST_SESSION, NAV } from '../helpers/selectors';
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

  // Re-seed a minimal past workout so workoutCount > 0 after the delete.
  // Without this the ActionHero lands on _CreateFirstRoutineHero (0-workout
  // state) and startEmptyWorkout can't find home-action-hero-free-workout.
  // The warmup workout is intentionally finished 90 min ago and not part of
  // a weekly plan, so ActionHero resolves to _FreeWorkoutHero (no suggested
  // next — the rpgRankUpThreshold user has no user-built routines).
  const now = new Date();
  const startedAt = new Date(now.getTime() - 2 * 60 * 60 * 1000);
  const finishedAt = new Date(now.getTime() - 90 * 60 * 1000);
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Debrief Warmup',
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    duration_seconds: 1800,
  });
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

  test('should render the segmented XP bar inside the debrief section', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(POST_SESSION.missionDebriefXpBar),
    ).toBeVisible();
  });

  test('should show leave-confirm dialog when pressing back on post-session route (Phase 31)', async ({
    page,
  }) => {
    // Phase 32 PR 32g — pins the Phase 31 round-2 Bug E invariant: the
    // post-session route must intercept the system back button with a
    // confirmation dialog. "Cancel" keeps the user on /workout/finish/...
    // and "Leave" navigates to /home, persisting the workout.
    //
    // The dialog title text comes from `postSessionLeaveTitle`. The
    // dialog itself has no Semantics identifier today — text selector is
    // the load-bearing match. en default; if the test user's locale ever
    // flips to pt, swap the assertion to 'Sair da pós-batalha?'.
    const leaveTitle = page.locator(
      'text=Leave the post-battle?',
    );

    // Browser back triggers the route's PopScope handler.
    await page.goBack();

    // Dialog must be visible.
    await expect(leaveTitle).toBeVisible({ timeout: 5_000 });

    // Cancel keeps the user on the post-session summary panel. Assert on
    // content visibility (the summary stays mounted) instead of `toHaveURL`
    // — Flutter web hash routing makes URL assertions after `context.push`
    // unreliable (cluster `flutter-web-url-assertion`).
    await page.locator('role=button[name="CANCEL"]').click();
    await expect(leaveTitle).toBeHidden({ timeout: 2_000 });
    await expect(page.locator(POST_SESSION.summary)).toBeVisible({
      timeout: 2_000,
    });

    // Press back again, then Leave — destination is /home. Assert on the
    // home tab visibility instead of `toHaveURL` (same cluster).
    await page.goBack();
    await expect(leaveTitle).toBeVisible({ timeout: 5_000 });
    await page.locator('role=button[name="LEAVE"]').click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 5_000 });
  });
});
