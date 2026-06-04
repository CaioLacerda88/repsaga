/**
 * Auth helpers: login and logout flows.
 *
 * Test users are created by global-setup.ts using the Supabase Admin Auth API
 * and credentials in test/e2e/.env.local. No manual setup is required.
 *
 * Import specific user credentials via getUser('roleName') from
 * fixtures/worker-users.ts (Phase 21+) rather than using
 * getTestCredentials() for new tests.
 */

import { Page, expect } from '@playwright/test';
import { AUTH, GAMIFICATION, NAV, ONBOARDING, SAGA } from './selectors';
import { dismissSagaIntroOverlay, waitForAppReady, flutterFill } from './app';
import { getUser } from '../fixtures/worker-users';

/**
 * Log in with email and password.
 *
 * Navigates to the base URL, waits for the login screen, fills credentials,
 * submits, then waits until the home shell (bottom nav) is visible.
 *
 * Every fresh browser context lands on the SagaIntroGate, which paints a
 * 3-step intro overlay on top of the shell the first time any user signs
 * in on that device. Unless a test is specifically exercising that flow
 * (see gamification-intro.spec.ts), the helper dismisses the overlay so
 * downstream clicks aren't swallowed by the Stack overlay.
 *
 * Pass `{ dismissSagaIntro: false }` to keep the overlay mounted.
 */
export async function login(
  page: Page,
  email: string,
  password: string,
  options: { dismissSagaIntro?: boolean } = {},
): Promise<void> {
  const { dismissSagaIntro = true } = options;

  await page.goto('/');
  await waitForAppReady(page);

  // Confirm we are on the login screen.
  await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 10_000 });

  await flutterFill(page, AUTH.emailInput, email);
  await flutterFill(page, AUTH.passwordInput, password);
  await page.click(AUTH.loginButton);

  // After successful login, the router redirects to /home and the shell nav
  // becomes visible. We wait for any bottom nav tab as confirmation.
  await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

  if (dismissSagaIntro) {
    // SagaIntroGate only paints the overlay once xpProvider resolves and the
    // retro-backfill Hive flag is set. On a cold login that can take a few
    // seconds; on a warm session it never appears. Probe for step 0 with a
    // bounded wait and skip silently if the overlay isn't part of the flow.
    try {
      await page
        .locator(GAMIFICATION.step0)
        .waitFor({ state: 'visible', timeout: 15_000 });
    } catch {
      return;
    }
    await dismissSagaIntroOverlay(page);
  }
}

/**
 * Log in as a user that has no completed profile (smokeOnboarding etc.) and
 * expects to land on `/onboarding` instead of `/home`. Mirrors [login] but
 * asserts the onboarding welcome page's GET STARTED button is visible rather
 * than the home tab. PR 1 (PR #299) moved the half-onboarded gate from an
 * in-memory `needsOnboardingProvider` to a derived check on
 * `profile.onboardedAt == null` — users without a profile row are now routed
 * to `/onboarding` post-login, so any test that signs them in needs this
 * variant of the helper to avoid timing out on `NAV.homeTab`.
 *
 * No `dismissSagaIntro` parameter — the SagaIntroGate only paints AFTER the
 * user reaches `/home`, so it's not relevant on the onboarding path.
 */
export async function loginExpectingOnboarding(
  page: Page,
  email: string,
  password: string,
): Promise<void> {
  await page.goto('/');
  await waitForAppReady(page);

  // Confirm we are on the login screen.
  await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 10_000 });

  await flutterFill(page, AUTH.emailInput, email);
  await flutterFill(page, AUTH.passwordInput, password);
  await page.click(AUTH.loginButton);

  // After login the router redirects to /onboarding (no profile row =>
  // needsOnboarding=true). Wait for page 1's GET STARTED button as the
  // confirmation that the welcome screen rendered.
  await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
    timeout: 20_000,
  });
}

/**
 * Log out by navigating to the Profile tab, opening settings, then confirming.
 *
 * Phase 18b: /profile now shows CharacterSheetScreen. The "Log Out" button
 * moved to /profile/settings (ProfileSettingsScreen), reached via the gear icon
 * in the character sheet's AppBar.
 *
 * Flow: Saga tab → gear icon → Settings → "Log Out" → confirmation dialog → "Log Out".
 * After logout the router redirects to /login.
 */
export async function logout(page: Page): Promise<void> {
  await page.click(NAV.profileTab);

  // Wait for CharacterSheetScreen to load, then navigate to settings.
  await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
  await page.locator(SAGA.gearIcon).first().click();
  await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

  // Click the "Log Out" button on the profile settings screen.
  await page.click('text=Log Out');

  // A confirmation dialog appears. Click the "Log Out" button inside the dialog
  // (the last occurrence — the first is the button that opened the dialog).
  const logOutButtons = page.locator('text=Log Out');
  await expect(logOutButtons.last()).toBeVisible({ timeout: 5_000 });
  await logOutButtons.last().click();

  // After logout, the router redirects to /login.
  await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 15_000 });
}

/**
 * Read test credentials from environment variables.
 *
 * Prefers TEST_USER_EMAIL / TEST_USER_PASSWORD environment variables for
 * backward compatibility. Falls back to the smokeAuth user from fixtures if
 * the env vars are not set.
 *
 * For new tests, call getUser('roleName') from fixtures/worker-users.ts
 * (Phase 21+) instead of calling this function. getUser returns a
 * worker-scoped email so concurrent Playwright workers never collide.
 */
export function getTestCredentials(): { email: string; password: string } {
  const email = process.env['TEST_USER_EMAIL'];
  const password =
    process.env['TEST_USER_PASSWORD'] ?? 'TestPassword123!';

  if (email) {
    return { email, password };
  }

  // Fall back to the smokeAuth role (worker-scoped under Phase 21).
  return {
    email: getUser('smokeAuth').email,
    password,
  };
}
