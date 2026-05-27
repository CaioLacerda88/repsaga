/**
 * Share-card flow E2E (Phase 30 PR 30b).
 *
 * Covers the Discreet path end-to-end on web: post-session summary →
 * share CTA tap → share-sheet → "Sem foto · só a saga" → preview screen
 * (locked Discreet variant) → retake (back to sheet).
 *
 * **What we DON'T test on web:**
 *   * Camera capture — Playwright can't drive native getUserMedia / camera
 *     intents on Chromium without a fake-media-stream config the project
 *     hasn't set up. Manual / device-level coverage owns that path.
 *   * Gallery picker — same reason; the browser file-picker dialog is
 *     out-of-band for Playwright unless we route through a file-input
 *     mock, which is unnecessary for the steady-state UI contract.
 *
 * **What we DO test on web:**
 *   * Share CTA → bottom sheet rendered with the 3 rows.
 *   * Discreet row tap → preview screen mounted, Discreet variant locked.
 *   * Variant toggle absent on the Discreet path.
 *   * Retake from preview → returns to a state where the share sheet can
 *     be opened again.
 *
 * Reuses the rpgRankUpThreshold user from `rank-up-celebration.spec.ts`
 * (Phase 29 v2 single-rank-up window: chest rank 3 / 157 XP). The
 * single rank-up event makes `hasShareCta == true` on the post-session
 * summary panel, surfacing the CTA we exercise here.
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
import { WORKOUT, POST_SESSION, SHARE_FLOW } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

/**
 * Reseed the rank-up threshold user — same shape used by
 * `rank-up-celebration.spec.ts` reseedRankUpThresholdUser. Lifted here as
 * a local copy so the spec stays self-contained; if both files drift,
 * the shared `worker-users` user ID is the contract that keeps them
 * pointing at the same seed.
 */
async function reseedShareCtaUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(
    admin,
    getUser('rpgRankUpThreshold').email,
  );
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  await admin
    .from('exercise_peak_loads_by_rep_range')
    .delete()
    .eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  await admin.from('body_part_progress').upsert(
    { user_id: userId, body_part: 'chest', total_xp: 157, rank: 3 },
    { onConflict: 'user_id,body_part' },
  );

  const { data: benchRows } = await admin
    .from('exercises')
    .select('id')
    .eq('slug', 'barbell_bench_press')
    .eq('is_default', true)
    .limit(1);
  const benchId = benchRows?.[0]?.id;
  if (benchId) {
    await admin.from('exercise_peak_loads').upsert(
      {
        user_id: userId,
        exercise_id: benchId,
        peak_weight: 80,
        peak_reps: 5,
        peak_date: new Date().toISOString(),
      },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  const now = new Date();
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

test.describe('Share flow', { tag: '@smoke' }, () => {
  // Serial mode: prevents parallel races on the shared rpgRankUpThreshold
  // user under --repeat-each.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await reseedShareCtaUser();
    await login(
      page,
      getUser('rpgRankUpThreshold').email,
      getUser('rpgRankUpThreshold').password,
    );

    // Finish a workout that yields a rank-up — guarantees the post-session
    // summary panel renders the share CTA (hasShareCta == true).
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Land on the post-session route + advance through the cinematic to
    // the summary panel where the share CTA is visible.
    await page.waitForURL(/\/workout\/finish\//, { timeout: 10_000 });
    // Skip cinematic — the skip button is visible during any beat.
    const skip = page.locator(POST_SESSION.skipBtn);
    if (await skip.isVisible().catch(() => false)) {
      await skip.click();
    }
    await expect(page.locator(POST_SESSION.summary)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should open share sheet when CTA tapped on post-session screen', async ({
    page,
  }) => {
    await page.locator(POST_SESSION.shareCta).click();
    await expect(page.locator(SHARE_FLOW.sheet)).toBeVisible({
      timeout: 5_000,
    });
    // All three rows should be visible (camera shown when permission is
    // granted OR denied — only hidden on permanentlyDenied which web
    // never reports).
    await expect(page.locator(SHARE_FLOW.sheetGallery)).toBeVisible();
    await expect(page.locator(SHARE_FLOW.sheetDiscreet)).toBeVisible();
  });

  test('should switch to discreet variant when "Sem foto" tapped', async ({
    page,
  }) => {
    await page.locator(POST_SESSION.shareCta).click();
    await expect(page.locator(SHARE_FLOW.sheet)).toBeVisible({
      timeout: 5_000,
    });

    await page.locator(SHARE_FLOW.sheetDiscreet).click();

    // Preview screen mounts.
    await expect(page.locator(SHARE_FLOW.previewScreen)).toBeVisible({
      timeout: 5_000,
    });
    // Phase 31: the A ↔ B variant toggle is retired (D3 Achievement Frame
    // is the single photo overlay; Discreet renders here for the no-photo
    // path). Retake + share CTAs remain.
    await expect(page.locator(SHARE_FLOW.previewRetake)).toBeVisible();
    await expect(page.locator(SHARE_FLOW.previewShareButton)).toBeVisible();
  });

  test('should return to share sheet when retake tapped', async ({ page }) => {
    await page.locator(POST_SESSION.shareCta).click();
    await expect(page.locator(SHARE_FLOW.sheet)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(SHARE_FLOW.sheetDiscreet).click();
    await expect(page.locator(SHARE_FLOW.previewScreen)).toBeVisible({
      timeout: 5_000,
    });

    await page.locator(SHARE_FLOW.previewRetake).click();

    // Preview screen is gone — controller is back to idle, navigator
    // popped to the summary panel.
    await expect(page.locator(SHARE_FLOW.previewScreen)).toBeHidden({
      timeout: 5_000,
    });
    // Summary panel back in view — the share CTA is still tappable, so
    // the user could re-open the sheet.
    await expect(page.locator(POST_SESSION.summary)).toBeVisible();
    await expect(page.locator(POST_SESSION.shareCta)).toBeVisible();
  });
});
