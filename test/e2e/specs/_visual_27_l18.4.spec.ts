/**
 * Phase 27 L18.4 visual verification — typography sweep.
 *
 * Captures screenshots of the 4 changed surfaces for side-by-side comparison
 * with any mockup reference. Not a regression test — it always passes;
 * the artefacts in `docs/27-l18.4-visual/` are the deliverable.
 *
 * Surfaces:
 *   1. Routines list — routine names should render in Rajdhani (titleDisplay).
 *   2. Exercises list — exercise names must STAY in Inter (title, not titleDisplay).
 *   3. Exercise detail — muscle-group chip icon carries body-part hue; chip label
 *      at 12dp Inter 600 with correct letter-spacing.
 *   4. Saga (character sheet) — XP bar labels in Rajdhani tabular; untrained "—"
 *      in Rajdhani matching the trained rank-numeral column.
 *   5. Profile Settings — section-header rhythm (eyebrow labels above section
 *      blocks); specifically the bottom half (Preferences / Data management /
 *      Legal / Privacy) where the 32dp spacers sit.
 *
 * Tagged @visual so the default regression run excludes it.
 * Run on demand:
 *   FLUTTER_APP_URL= npx playwright test specs/_visual_27_l18.4.spec.ts
 *
 * Navigation notes (App Router topology):
 *   - The Saga/Character Sheet tab is `nav-profile` in the bottom nav.
 *   - Profile Settings is reached via the gear icon on the character sheet
 *     (identifier: 'saga-settings-btn').
 *   - Saga sub-routes (/saga/stats etc.) also belong to the Saga tab.
 *
 * Users:
 *   - rpgFoundationUser — 12+ workouts, multiple body parts ranked.
 *     Drives the "trained" Saga surface + Profile Settings.
 *   - rpgFreshUser — profile only, zero workouts. Day-0 Saga surface.
 *   - fullRoutines — has starter + user routines for routines list.
 *   - fullExercises — exercises list with full exercise library.
 *
 * Viewports: 320dp (smallest Android), 360dp (baseline), 412dp (large phone).
 */

import { test } from '@playwright/test';
import { Page } from '@playwright/test';
import path from 'path';
import { mkdirSync } from 'fs';
import { login } from '../helpers/auth';
import { HOME, NAV, SAGA, PROFILE, EXERCISE_LIST, EXERCISE_DETAIL, ROUTINE } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

const VIEWPORTS = [
  { name: '320dp', width: 320, height: 720 },
  { name: '360dp', width: 360, height: 800 },
  { name: '412dp', width: 412, height: 915 },
];

const OUTPUT_DIR = path.resolve(
  __dirname, '..', '..', '..', 'docs', '27-l18.4-visual',
);

// Ensure output dir exists before any test writes screenshots.
mkdirSync(OUTPUT_DIR, { recursive: true });

/** Navigate to the Routines tab and wait for the list to settle. */
async function settleRoutines(page: Page): Promise<void> {
  await page.locator(ROUTINE.heading).waitFor({ state: 'visible', timeout: 15_000 });
  await page.waitForTimeout(600);
}

/** Navigate to the Exercises tab and wait for the list to settle. */
async function settleExercises(page: Page): Promise<void> {
  await page.locator(EXERCISE_LIST.heading).waitFor({ state: 'visible', timeout: 15_000 });
  await page.waitForTimeout(400);
}

/**
 * Navigate to the Saga (character sheet) screen — the "profile" tab in the
 * bottom nav — and wait for the character sheet container to settle.
 */
async function settleSaga(page: Page): Promise<void> {
  await page.locator(SAGA.characterSheet).waitFor({ state: 'visible', timeout: 15_000 });
  await page.waitForTimeout(800);
}

/** Open Profile Settings via the gear icon on the character sheet. */
async function settleProfileSettings(page: Page): Promise<void> {
  await page.locator(SAGA.gearIcon).click();
  // Profile settings screen — wait for the section heading to appear.
  // SAGA.profileSettingsScreen = '[flt-semantics-identifier="profile-heading"]'
  await page.locator(SAGA.profileSettingsScreen).waitFor({
    state: 'visible',
    timeout: 10_000,
  });
  await page.waitForTimeout(400);
}

test.describe.configure({ mode: 'serial' });

test.describe('L18.4 typography sweep — visual verification', { tag: '@visual' }, () => {

  // ─── Surface 1: Routines list ────────────────────────────────────────────
  for (const vp of VIEWPORTS) {
    test(`routines list @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('fullRoutines');
      await login(page, user.email, user.password);
      await page.locator(NAV.routinesTab).click();
      await settleRoutines(page);
      await page.screenshot({
        path: `${OUTPUT_DIR}/routines_${vp.name}.png`,
        fullPage: true,
      });
    });
  }

  // ─── Surface 2: Exercises list ───────────────────────────────────────────
  for (const vp of VIEWPORTS) {
    test(`exercises list @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('fullExercises');
      await login(page, user.email, user.password);
      await page.locator(NAV.exercisesTab).click();
      await settleExercises(page);
      await page.screenshot({
        path: `${OUTPUT_DIR}/exercises_list_${vp.name}.png`,
        fullPage: true,
      });
    });
  }

  // ─── Surface 3: Exercise detail — muscle-group chip with hue icon ────────
  for (const vp of VIEWPORTS) {
    test(`exercise detail (chest / barbell) @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('fullExercises');
      await login(page, user.email, user.password);
      await page.locator(NAV.exercisesTab).click();
      await settleExercises(page);
      // Apply the "Chest" muscle-group filter so only chest exercises are
      // visible — the alphabetically-first chest exercise becomes the top
      // card, avoiding the "off-screen item unreachable by AOM click" issue
      // on short viewports. Archer Push-Up (Chest/Bodyweight) is typically
      // the first result.
      await page.locator(EXERCISE_LIST.muscleGroupFilter('chest')).click();
      await page.waitForTimeout(400);
      // Click the first chest exercise in the filtered list.
      await page.locator(EXERCISE_LIST.exerciseCard('')).first().click();
      await page.locator(EXERCISE_DETAIL.appBarTitle).waitFor({
        state: 'visible',
        timeout: 10_000,
      });
      await page.waitForTimeout(400);
      await page.screenshot({
        path: `${OUTPUT_DIR}/exercise_detail_chest_${vp.name}.png`,
        fullPage: true,
      });
    });
  }

  // ─── Surface 4: Saga — foundation user (trained rows + XP bar) ───────────
  for (const vp of VIEWPORTS) {
    test(`saga — foundation user (trained rows) @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('rpgFoundationUser');
      await login(page, user.email, user.password, { dismissSagaIntro: true });
      await page.locator(NAV.profileTab).click();
      await settleSaga(page);
      await page.screenshot({
        path: `${OUTPUT_DIR}/saga_foundation_${vp.name}.png`,
        fullPage: true,
      });
    });

    test(`saga — fresh user (untrained rows + day-0 XP bar) @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('rpgFreshUser');
      await login(page, user.email, user.password, { dismissSagaIntro: true });
      await page.locator(NAV.profileTab).click();
      await settleSaga(page);
      await page.screenshot({
        path: `${OUTPUT_DIR}/saga_fresh_${vp.name}.png`,
        fullPage: true,
      });
    });
  }

  // ─── Surface 5: Profile Settings — section-header rhythm ─────────────────
  // Specific reviewer concern (Suggestion #4): the bottom-half of the screen
  // (Preferences / Data management / Legal / Privacy) uses 32dp spacers above
  // 12dp eyebrow labels. Screenshots will show whether the rhythm reads as
  // intended separators or overly-spaced captions.
  for (const vp of VIEWPORTS) {
    test(`profile settings @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('rpgFoundationUser');
      await login(page, user.email, user.password, { dismissSagaIntro: true });
      await page.locator(NAV.profileTab).click();
      await settleSaga(page);
      await settleProfileSettings(page);
      // Capture full-page so the bottom sections (Preferences / Data / Legal /
      // Privacy) are included regardless of viewport height.
      await page.screenshot({
        path: `${OUTPUT_DIR}/profile_settings_${vp.name}.png`,
        fullPage: true,
      });
    });
  }
});
