/**
 * Onboarding resume spec — PR 1 D1 regression guard.
 *
 * The `onboardingResume` user is provisioned by global-setup with a profile
 * row whose `display_name` is set but `onboarded_at` is NULL — the "half-
 * onboarded" shape that the OLD `StateProvider<bool>` would misroute to
 * /home on process restart. With the column-anchored derivation introduced
 * by PR 1, the router MUST send this user back to /onboarding after sign-in.
 *
 * If this test ever regresses we have either:
 *   - reverted the column-anchored derivation (defects D1/D2/D11 are back),
 *   - or accidentally backfilled `onboarded_at` somewhere it shouldn't be.
 */

import { test, expect } from '@playwright/test';
import { waitForAppReady, flutterFill } from '../helpers/app';
import { AUTH, ONBOARDING } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

test.describe('Onboarding resume', { tag: '@smoke' }, () => {
  test('should route a half-onboarded user back to /onboarding after sign-in (PR 1 / D1)', async ({
    page,
  }) => {
    await page.goto('/');
    await waitForAppReady(page);

    await flutterFill(
      page,
      AUTH.emailInput,
      getUser('onboardingResume').email,
    );
    await flutterFill(
      page,
      AUTH.passwordInput,
      getUser('onboardingResume').password,
    );
    await page.click(AUTH.loginButton);

    // The router's PR 1 derivation reads `profile.onboardedAt` to decide
    // /onboarding vs /home. With `onboarded_at = NULL`, the user lands on
    // /onboarding — the GET STARTED CTA on the welcome page is the surface
    // signal. Content-visibility assertion per
    // `cluster_flutter_web_url_assertion`.
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 15_000,
    });
  });
});
