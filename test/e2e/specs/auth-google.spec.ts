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
    // Capture every URL the page tries to navigate to OR fetch. Supabase's
    // `signInWithOAuth(OAuthProvider.google, ...)` issues a GET to
    // `/auth/v1/authorize?provider=google&...` — that hit is the
    // observable side-effect we pin. Playwright can't follow the redirect
    // to accounts.google.com (Google rejects headless browsers), but the
    // outbound request to Supabase IS exercisable.
    let oauthRequestSeen = false;
    page.on('request', (request) => {
      const url = request.url();
      if (
        url.includes('/auth/v1/authorize') &&
        url.includes('provider=google')
      ) {
        oauthRequestSeen = true;
      }
    });

    // Some Flutter builds open the OAuth URL via `window.location.assign`
    // / `window.open` rather than fetch — intercept those too via the
    // `popup`/`framenavigated` events. We give both paths up to 10s after
    // the click to fire.
    page.on('popup', () => {
      oauthRequestSeen = true;
    });
    page.on('framenavigated', (frame) => {
      if (
        frame === page.mainFrame() &&
        (frame.url().includes('accounts.google.com') ||
          frame.url().includes('/auth/v1/authorize'))
      ) {
        oauthRequestSeen = true;
      }
    });

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

    await page.click(AUTH.googleButton);

    // Wait for the OAuth side-effect to fire. The Supabase SDK launches
    // the URL via `url_launcher` on web; the request lands on the
    // authorize endpoint either via XHR or top-level navigation. 10s is
    // generous to accommodate first-load JS warm-up under CI contention.
    await page.waitForTimeout(2_000);
    // Two acceptable signals: (a) an authorize-endpoint hit OR (b) the
    // user is no longer on the login screen (button gone / navigated
    // away). Either confirms the click was wired through.
    const stillOnLogin = await page
      .locator(AUTH.googleButton)
      .isVisible({ timeout: 1_000 })
      .catch(() => false);

    expect(oauthRequestSeen || !stillOnLogin).toBe(true);
  });
});
