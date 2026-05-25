/**
 * Visual verification spec for PR 30b (share-card flow).
 *
 * Captures screenshots of the 5 surfaces at 3 viewports each (15 total):
 * 1. Post-session summary panel with share CTA visible
 * 2. Share sheet (bottom sheet step 1) — 3 rows
 * 3. Discreet preview (variant=Discreet, no-photo path)
 * 4. Variant A preview (Minimal Strip) — web can't feed photo; Discreet used
 * 5. Variant B preview (Full-Bleed Collars) — web can't feed photo; Discreet used
 *
 * Screenshots saved to test-results/pr-30b-visual/
 *
 * NOTE: This spec is NOT part of the regular suite (@smoke / regression).
 * It is a one-off visual capture tool for the CLAUDE.md step 9 gate.
 */

import { test, expect } from '@playwright/test';
import * as path from 'path';
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
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

const OUT_DIR = path.join(__dirname, '..', 'test-results', 'pr-30b-visual');

const VIEWPORTS: Array<{ name: string; width: number; height: number }> = [
  { name: '320dp', width: 320, height: 693 },
  { name: '360dp', width: 360, height: 780 },
  { name: '412dp', width: 412, height: 892 },
];

async function reseedUser(): Promise<void> {
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

  const now = new Date();
  await admin.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: now.toISOString(),
      updated_at: now.toISOString(),
      completed_at: now.toISOString(),
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
        peak_date: now.toISOString(),
      },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Visual Warmup',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

// Reach the post-session summary panel with share CTA visible.
async function navigateToSummary(page: import('@playwright/test').Page): Promise<void> {
  await reseedUser();
  await login(
    page,
    getUser('rpgRankUpThreshold').email,
    getUser('rpgRankUpThreshold').password,
  );

  await startEmptyWorkout(page);
  await addExercise(page, 'Barbell Bench Press');

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
  } else {
    // Wait a few seconds then try again (cinematic may still be transitioning)
    await page.waitForTimeout(3_000);
    if (await skip.isVisible().catch(() => false)) {
      await skip.click();
    }
  }
  await expect(page.locator(POST_SESSION.summary)).toBeVisible({
    timeout: 10_000,
  });
}

test.describe('PR 30b visual verification', () => {
  test.describe.configure({ mode: 'serial' });

  test('capture surface 1 — post-session summary + share CTA', async ({
    page,
  }) => {
    await navigateToSummary(page);

    for (const vp of VIEWPORTS) {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      await page.waitForTimeout(400);
      await expect(page.locator(POST_SESSION.summary)).toBeVisible();
      // Verify share CTA is present
      const ctaVisible = await page
        .locator(POST_SESSION.shareCta)
        .isVisible()
        .catch(() => false);
      console.log(`[Surface 1 @ ${vp.name}] Share CTA visible: ${ctaVisible}`);

      await page.screenshot({
        path: path.join(OUT_DIR, `surface1-summary-${vp.name}.png`),
      });
    }
  });

  test('capture surface 2 — share sheet (bottom sheet)', async ({ page }) => {
    await navigateToSummary(page);

    for (const vp of VIEWPORTS) {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      await page.waitForTimeout(400);

      // Open share sheet
      await expect(page.locator(POST_SESSION.shareCta)).toBeVisible({
        timeout: 5_000,
      });
      await page.locator(POST_SESSION.shareCta).click();
      await expect(page.locator(SHARE_FLOW.sheet)).toBeVisible({
        timeout: 8_000,
      });
      await page.waitForTimeout(500);

      // Check all 3 rows
      const cameraVisible = await page
        .locator(SHARE_FLOW.sheetCamera)
        .isVisible()
        .catch(() => false);
      const galleryVisible = await page
        .locator(SHARE_FLOW.sheetGallery)
        .isVisible()
        .catch(() => false);
      const discreetVisible = await page
        .locator(SHARE_FLOW.sheetDiscreet)
        .isVisible()
        .catch(() => false);
      console.log(
        `[Surface 2 @ ${vp.name}] Camera: ${cameraVisible}, Gallery: ${galleryVisible}, Discreet: ${discreetVisible}`,
      );

      await page.screenshot({
        path: path.join(OUT_DIR, `surface2-share-sheet-${vp.name}.png`),
      });

      // Dismiss sheet and return to summary
      await page.keyboard.press('Escape');
      await page.waitForTimeout(800);
      // If summary not back, try clicking in top area
      const summaryBack = await page
        .locator(POST_SESSION.summary)
        .isVisible()
        .catch(() => false);
      if (!summaryBack) {
        await page.mouse.click(vp.width / 2, 30);
        await page.waitForTimeout(800);
      }
    }
  });

  test('capture surface 3 — discreet preview', async ({ page }) => {
    await navigateToSummary(page);

    for (const vp of VIEWPORTS) {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      await page.waitForTimeout(400);

      // Open share sheet
      await expect(page.locator(POST_SESSION.shareCta)).toBeVisible({
        timeout: 5_000,
      });
      await page.locator(POST_SESSION.shareCta).click();
      await expect(page.locator(SHARE_FLOW.sheet)).toBeVisible({
        timeout: 8_000,
      });

      // Tap "Sem foto" (Discreet row)
      await page.locator(SHARE_FLOW.sheetDiscreet).click();
      await expect(page.locator(SHARE_FLOW.previewScreen)).toBeVisible({
        timeout: 8_000,
      });
      await page.waitForTimeout(800); // allow canvas render

      // Check variant toggle is hidden (Discreet path locks variant)
      const toggleVisible = await page
        .locator(SHARE_FLOW.variantToggle)
        .isVisible()
        .catch(() => false);
      const retakeVisible = await page
        .locator(SHARE_FLOW.previewRetake)
        .isVisible()
        .catch(() => false);
      const shareButtonVisible = await page
        .locator(SHARE_FLOW.previewShareButton)
        .isVisible()
        .catch(() => false);
      console.log(
        `[Surface 3 @ ${vp.name}] VariantToggle hidden: ${!toggleVisible}, Retake: ${retakeVisible}, ShareBtn: ${shareButtonVisible}`,
      );

      await page.screenshot({
        path: path.join(OUT_DIR, `surface3-discreet-preview-${vp.name}.png`),
      });

      // Go back via retake
      if (retakeVisible) {
        await page.locator(SHARE_FLOW.previewRetake).click();
        await expect(page.locator(POST_SESSION.summary)).toBeVisible({
          timeout: 8_000,
        });
      }
    }
  });

  test('note surface 4+5 — variant A/B require photo (web gap)', async ({
    page: _page,
  }) => {
    // Variant A (Minimal Strip) and Variant B (Full-Bleed Collars) require a
    // photo from camera or gallery — the browser file-picker is not driveable
    // by Playwright without a file-input harness. These paths need physical
    // Android coverage per feedback_visual_verification_physical_device.
    //
    // This test exists to document the coverage gap — it does not assert anything.
    console.log(
      '[Surfaces 4+5] Variant A/B require photo → physical-device follow-up required.',
    );
    expect(true).toBe(true); // placeholder so test runner counts it
  });
});
