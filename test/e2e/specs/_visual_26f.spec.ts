/**
 * Phase 26f visual verification (mockup parity).
 *
 * Captures screenshots of the redesigned Home surface for side-by-side
 * comparison with `docs/phase-26-mockups.html`. Not a regression test — it
 * always passes; the artefacts in `docs/26f-visual/` are the deliverable.
 *
 * Leading underscore in the filename pushes it to the bottom of spec
 * ordering so it doesn't run unless explicitly targeted.
 *
 * Users:
 *   - rpgFoundationUser — 12 workouts across 6 weeks. Drives the "trained"
 *     character card (lvl > 1, class assigned, multiple body parts ranked,
 *     non-fallback closest-rank-up).
 *   - rpgFreshUser — profile only, zero workouts. Day-0 collapsed state with
 *     first-step fallback.
 *
 * Viewports: 320 (smallest Android), 360 (baseline), 412 (large phone).
 */

import { test } from '@playwright/test';
import { Page } from '@playwright/test';
import { login } from '../helpers/auth';
import { HOME } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

const VIEWPORTS = [
  { name: '320dp', width: 320, height: 720 },
  { name: '360dp', width: 360, height: 800 },
  { name: '412dp', width: 412, height: 915 },
];

const OUTPUT_DIR = 'C:/Users/caiol/Projects/repsaga/docs/26f-visual';

async function settleHome(page: Page): Promise<void> {
  // Wait for the redesigned character card to be mounted.
  await page.locator(HOME.characterCard).waitFor({ state: 'visible', timeout: 20_000 });
  // Brief idle so Riverpod hydration + initial paint settle.
  await page.waitForTimeout(800);
}

test.describe.configure({ mode: 'serial' });

// Tagged @visual so default regression runs (and @smoke) exclude this spec;
// re-run on demand with `npx playwright test --grep @visual`.
test.describe('Phase 26f visual verification', { tag: '@visual' }, () => {
  for (const vp of VIEWPORTS) {
    test(`rpg foundation user — collapsed @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('rpgFoundationUser');
      await login(page, user.email, user.password, { dismissSagaIntro: true });
      await settleHome(page);
      await page.screenshot({
        path: `${OUTPUT_DIR}/foundation_collapsed_${vp.name}.png`,
        fullPage: true,
      });
    });

    test(`rpg foundation user — expanded @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('rpgFoundationUser');
      await login(page, user.email, user.password, { dismissSagaIntro: true });
      await settleHome(page);
      await page.locator(HOME.characterCard).first().click();
      // Easing curve completes in ~250ms; pad for nested AnimatedSize.
      await page.waitForTimeout(800);
      await page.screenshot({
        path: `${OUTPUT_DIR}/foundation_expanded_${vp.name}.png`,
        fullPage: true,
      });
    });

    test(`rpg fresh user — day-0 collapsed @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const user = getUser('rpgFreshUser');
      await login(page, user.email, user.password, { dismissSagaIntro: true });
      await settleHome(page);
      await page.screenshot({
        path: `${OUTPUT_DIR}/fresh_collapsed_${vp.name}.png`,
        fullPage: true,
      });
    });
  }
});
