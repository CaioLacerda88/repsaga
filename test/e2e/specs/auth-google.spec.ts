/**
 * Google Sign-In smoke — Phase 32 PR 32b.
 *
 * The OAuth handshake itself cannot be exercised from Playwright (Google
 * actively blocks programmatic sign-in). What we CAN pin:
 *   1. The button selector contract — `auth-google-btn` must exist + be
 *      visible whenever the login screen renders. A regression in
 *      `selectors.ts` or the LoginScreen Semantics tree breaks the whole
 *      `login()` helper used across ~all auth-gated specs.
 *   2. The click triggers an OAuth flow — by intercepting outbound
 *      requests we assert SOMETHING hits an auth endpoint. We don't try
 *      to complete the handshake; we only verify the click was wired.
 */

import { test, expect } from '@playwright/test';
import { waitForAppReady } from '../helpers/app';
import { AUTH } from '../helpers/selectors';

test.describe('Google Sign-In', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
  });

  test('should render the Google Sign-In button on the login screen', async ({
    page,
  }) => {
    // Pure selector pin — when `selectors.ts` or the LoginScreen Semantics
    // tree drifts, this fails loud BEFORE the shared `login()` helper does.
    await expect(page.locator(AUTH.googleButton)).toBeVisible();
  });

  test('should trigger an OAuth flow when the Google button is tapped', async ({
    page,
  }) => {
    // We pin two observable signals from a successful Google button wire-up:
    //   (a) the Supabase SDK fires a GET to
    //       `/auth/v1/authorize?provider=google&...` — observable via
    //       `page.waitForRequest()`. This is the deterministic happy path.
    //   (b) the page navigates away from the login screen — observable via
    //       the Google button disappearing. This is the fallback for
    //       Flutter builds that issue the OAuth URL via
    //       `window.location.assign` rather than fetch.
    //
    // `page.waitForRequest` is event-driven (no racy sleep) and short-
    // circuits the moment the authorize request fires.

    // Block real navigation to accounts.google.com so the test stays on
    // the login page if the redirect chain reaches Google. We're only
    // pinning that SOMETHING tried to go.
    await page.route('**/accounts.google.com/**', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'text/html',
        body: '<html><body>intercepted</body></html>',
      }),
    );

    // Start waiting BEFORE clicking — `waitForRequest` must be primed so
    // it catches the request fired by the click handler.
    const oauthRequestPromise = page
      .waitForRequest(
        req =>
          req.url().includes('/auth/v1/authorize') &&
          req.url().includes('provider=google'),
        { timeout: 10_000 },
      )
      .catch(() => null);

    await page.click(AUTH.googleButton);

    const oauthRequest = await oauthRequestPromise;
    const oauthRequestSeen = oauthRequest !== null;

    // Fallback: the user is no longer on the login screen (button gone /
    // navigated away). Either signal confirms the click was wired through.
    const stillOnLogin = await page
      .locator(AUTH.googleButton)
      .isVisible({ timeout: 1_000 })
      .catch(() => false);

    expect(oauthRequestSeen || !stillOnLogin).toBe(true);
  });
});
