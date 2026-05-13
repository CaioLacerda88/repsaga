/**
 * Exploratory driver — manual Playwright session for the active workout charters.
 *
 * NOT a regression test. Each `test()` block opens a browser at a priority
 * device viewport, auto-logs-in as a chosen user, navigates to the surface
 * being explored, and then calls `page.pause()` — handing control to the
 * tester via the Playwright Inspector.
 *
 * **Activation:** EXPL_DRIVER=1 must be set or the spec self-skips (CI safety).
 *
 * **Run a single device:**
 *   EXPL_DRIVER=1 FLUTTER_APP_URL= npx playwright test exploratory.spec.ts --grep "@BR-1" --headed
 *   EXPL_DRIVER=1 FLUTTER_APP_URL= npx playwright test exploratory.spec.ts --grep "@US-2" --headed
 *
 * **Override the test user (default: fullPR — Sam persona, has PR baselines):**
 *   EXPL_DRIVER=1 EXPL_USER=fullCrash FLUTTER_APP_URL= npx playwright test exploratory.spec.ts --grep "@BR-1" --headed
 *
 * **Override the starting screen (default: home):**
 *   EXPL_DRIVER=1 EXPL_LANDING=workout EXPL_USER=fullPR FLUTTER_APP_URL= npx playwright test exploratory.spec.ts --grep "@BR-1" --headed
 *
 * Available starting screens via EXPL_LANDING:
 *   home, workout (start a fresh empty workout), routines, exercises, records, profile
 *
 * Plan: PROJECT.md §4 Phase 22 (Active Workout Audit Fix Wave)
 * Findings: PROJECT.md §4 Phase 22 (cluster ledger)
 */

import { test } from '@playwright/test';
import { TEST_USERS } from '../fixtures/test-users';
import { getUser } from '../fixtures/worker-users';
import { login } from '../helpers/auth';

// CI guard: this spec calls `page.pause()` and would block forever in
// automated runs. It only activates when EXPL_DRIVER=1 is set explicitly.
// CI never sets that, so regression suites skip these tests entirely.
test.skip(
  process.env['EXPL_DRIVER'] !== '1',
  'Exploratory driver — set EXPL_DRIVER=1 to enable manual session',
);

// Phase 21+ uses a per-worker user pool. `getUser(role)` returns
// `<role>_w<workerIdx>@test.local` for whichever worker is running this test.
// The exploratory spec runs single-worker, so worker index is always 0.
const userKey = (process.env['EXPL_USER'] ?? 'fullPR') as keyof typeof TEST_USERS;
const user = getUser(userKey);

const landing = process.env['EXPL_LANDING'] ?? 'home';

const devices = [
  { id: 'BR-1', name: 'Galaxy A14 (BR budget)', width: 360, height: 780 },
  { id: 'BR-2', name: 'Moto G54 (BR mainstream)', width: 393, height: 851 },
  { id: 'US-1', name: 'iPhone 15 (US mainstream)', width: 393, height: 852 },
  { id: 'US-2', name: 'iPhone 16 Pro Max (US largest)', width: 440, height: 956 },
];

for (const d of devices) {
  test.describe(`Exploratory — ${d.id} ${d.name}`, { tag: `@${d.id}` }, () => {
    test.use({ viewport: { width: d.width, height: d.height } });

    test(`should hand off to manual driver for ${d.id} (${d.width}x${d.height})`, async ({ page }) => {
      // Disable Playwright's per-test timeout — exploratory sessions are open-ended.
      test.setTimeout(0);

      console.log(`\n[exploratory] Device: ${d.id} ${d.name} (${d.width}x${d.height})`);
      console.log(`[exploratory] User: ${userKey} (${user.email})`);
      console.log(`[exploratory] Landing: ${landing}`);

      // Auto-login. SagaIntroGate is dismissed so it doesn't sit over the shell.
      await login(page, user.email, user.password);

      // Navigate to the requested landing screen.
      switch (landing) {
        case 'workout':
          // Tap the home start-empty-workout / quick-workout CTA. The exact
          // selector depends on user state (brand-new vs lapsed vs active).
          // For Sam (fullPR) the lapsed-state "Quick workout" card is visible.
          await page.locator('[flt-semantics-identifier="home-start-empty-btn"]').click().catch(async () => {
            await page.locator('text=/quick workout/i').first().click();
          });
          await page.waitForURL('**/workout/active**', { timeout: 10_000 });
          break;
        case 'routines':
          await page.locator('[flt-semantics-identifier="nav-routines"]').click();
          break;
        case 'exercises':
          await page.locator('[flt-semantics-identifier="nav-exercises"]').click();
          break;
        case 'profile':
          await page.locator('[flt-semantics-identifier="nav-profile"]').click();
          break;
        case 'records':
          await page.goto('/records');
          break;
        case 'home':
        default:
          // Already there post-login.
          break;
      }

      console.log(`[exploratory] Ready — handing off to inspector. Resume the test (or close the inspector) to end the session.`);

      // Hand off to manual exploration. The Playwright Inspector is open; you can:
      //   - drive the browser freely
      //   - use the inspector's "Pick locator" to grab selectors for findings
      //   - watch network / console in DevTools (right-click in the browser)
      //   - resize the window if you want to test a different viewport mid-session
      // Hit "Resume" or close the inspector to end the session and let the test exit.
      await page.pause();
    });
  });
}
