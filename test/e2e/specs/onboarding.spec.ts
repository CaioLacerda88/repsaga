/**
 * Onboarding spec — merged from smoke suite.
 *
 * Tests the 2-page onboarding flow that appears for new users after sign-up:
 *   Page 1: Welcome ("Track every rep, every time") -> GET STARTED
 *   Page 2: Profile setup (display name + fitness level + frequency) -> LET'S GO
 *
 * NOTE: This test requires a fresh account that has never completed onboarding.
 * The `smokeOnboarding` user is provisioned by global-setup with no profile row,
 * which causes the router to redirect to /onboarding after login.
 *
 * TODO (infrastructure): The global-setup creates auth users but does NOT
 * automatically delete the user's profile row between runs. If the smokeOnboarding
 * user has already completed onboarding (profile row exists), the router will
 * redirect to /home instead of /onboarding, and these tests will fail.
 *
 * To make these tests repeatable:
 *   Option A: Delete the profile row for smokeOnboarding in global-setup via
 *             the Supabase Admin API (DELETE from profiles WHERE id = <user_id>).
 *   Option B: Use a freshly created user per test run (unique email per run).
 *   Option C: Add a Supabase edge function or SQL to reset onboarding state.
 *
 * Until infrastructure supports this, the test navigates directly to /onboarding
 * to verify the UI renders, acknowledging this bypasses the auth redirect guard.
 */

import { test, expect } from '@playwright/test';
import { login, loginExpectingOnboarding, logout } from '../helpers/auth';
import { waitForAppReady, flutterFill } from '../helpers/app';
import { NAV, ONBOARDING, ONBOARDING_FLOW } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

// ---------------------------------------------------------------------------
// Smoke — onboarding flow
// ---------------------------------------------------------------------------
test.describe('Onboarding', { tag: '@smoke' }, () => {
  // Cluster: e2e-spec-state-leak-across-tests. Test 3 below COMPLETES
  // onboarding (writes onboarded_at via the production save path), leaving
  // the worker's smokeOnboarding profile in a fully-onboarded state. Without
  // this reseed, Test 4 (and any future test sharing this user) finds the
  // user routes to /home, so `loginExpectingOnboarding` times out on the
  // GET STARTED locator. Deleting the row restores the fresh-signup state
  // (no profile, the trigger will create one on next login with NULL
  // onboarded_at => router goes /onboarding).
  test.beforeEach(async () => {
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(
      admin,
      getUser('smokeOnboarding').email,
    );
    if (userId) {
      await admin.from('profiles').delete().eq('id', userId);
    }
  });

  // ---------------------------------------------------------------------------
  // Test 1: Onboarding Page 1 renders correctly.
  //
  // Navigate directly to /onboarding and verify the welcome page content.
  // This confirms the widget tree is correct even if the auth redirect guard
  // would normally skip onboarding for an already-onboarded user.
  // ---------------------------------------------------------------------------
  test('should show welcome content and GET STARTED button on page 1', async ({
    page,
  }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );

    // Navigate directly to onboarding. The guard may redirect authenticated
    // users with a profile to /home, in which case this test asserts the
    // onboarding route is reachable (useful for visual regression).
    // Navigate via hash to avoid a full CanvasKit reload.
    await page.evaluate(() => { window.location.hash = '#/onboarding'; });
    await page.waitForURL(/\/(onboarding|home)/, { timeout: 10_000 });

    // Either we land on onboarding or are redirected to home.
    const isOnOnboarding = page.url().includes('/onboarding');

    if (!isOnOnboarding) {
      // TODO: Delete profile row in global-setup to allow testing fresh flow.
      // For now we skip the onboarding-specific assertions.
      test.skip();
      return;
    }

    // Page 1: Welcome content.
    await expect(page.locator(ONBOARDING_FLOW.welcomeHeadline)).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });

    // The old "NEXT" button from the 3-page flow must NOT be present.
    await expect(page.locator(ONBOARDING.nextButton)).not.toBeVisible({
      timeout: 3_000,
    });
  });

  // ---------------------------------------------------------------------------
  // Test 2: Tapping GET STARTED advances to page 2.
  //
  // TODO: Requires a fresh user (no profile row). See infrastructure note above.
  // ---------------------------------------------------------------------------
  test('should advance to profile setup page after tapping GET STARTED', async ({ page }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );
    // Navigate via hash to avoid a full CanvasKit reload.
    await page.evaluate(() => { window.location.hash = '#/onboarding'; });
    await page.waitForURL(/\/(onboarding|home)/, { timeout: 10_000 });

    const isOnOnboarding = page.url().includes('/onboarding');
    if (!isOnOnboarding) {
      // TODO: Reset profile row in global-setup.
      test.skip();
      return;
    }

    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(ONBOARDING.getStartedButton).click();

    // Page 2: Profile setup.
    await expect(page.locator(ONBOARDING_FLOW.profileSetupHeadline)).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(ONBOARDING_FLOW.displayNameInput)).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(ONBOARDING.letsGoButton)).toBeVisible({
      timeout: 5_000,
    });
  });

  // ---------------------------------------------------------------------------
  // Test 3: Complete onboarding — fill name, select frequency, tap LET'S GO.
  //
  // TODO: Requires a fresh user (no profile row). See infrastructure note above.
  // Full flow: Page 1 -> GET STARTED -> fill name -> choose frequency -> LET'S GO
  // -> assert redirect to /home.
  // ---------------------------------------------------------------------------
  test('should redirect to /home after completing onboarding with name and frequency', async ({
    page,
  }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );
    // Navigate via hash to avoid a full CanvasKit reload.
    await page.evaluate(() => { window.location.hash = '#/onboarding'; });
    await page.waitForURL(/\/(onboarding|home)/, { timeout: 10_000 });

    const isOnOnboarding = page.url().includes('/onboarding');
    if (!isOnOnboarding) {
      // TODO: Reset profile row in global-setup.
      test.skip();
      return;
    }

    // Page 1 -> Page 2. Mirror the wait-then-click discipline of test 109
    // (line 126) — under CanvasKit + GitHub Actions resource contention,
    // the button can be visually painted before its AOM hit-target is
    // wired, so a bare `.click()` lands on a not-yet-clickable node and
    // the next `expect(profileSetupHeadline).toBeVisible` fails because
    // the navigation never fired. The Manage Data export test (MD-013)
    // exposed the same Flutter-web-timing class on this CI run.
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(
      page.locator(ONBOARDING_FLOW.profileSetupHeadline),
    ).toBeVisible({
      timeout: 10_000,
    });

    // Fill display name.
    await flutterFill(page, ONBOARDING_FLOW.displayNameInput, 'Smoke Tester');

    // Select 3x training frequency (already the default, but tap it explicitly).
    await page.locator(ONBOARDING_FLOW.frequency3x).click();

    // Submit.
    await page.locator(ONBOARDING.letsGoButton).click();

    // No error snackbar appears in the success path. Pins the regression
    // window for the PR-302 / PR-310 / PR (this PR) fix-wave: if the
    // `DatabaseException(42501)` or `failedToSaveProfile` snack ever
    // surfaces here, the typed-dispatch branch in
    // `_showSaveErrorSnack` has regressed (or the underlying
    // server-side 42501 condition is back). Test fails BEFORE the
    // home-nav timeout would, surfacing the right failure category.
    //
    // Bounded 2 s window matches Material's default SnackBar duration
    // (4 s) minus the post-save->navigation lag — any error snack would
    // be visible inside this window. Both en and pt copy strings are
    // checked because the user-facing locale is profile-driven and the
    // smokeOnboarding user's locale is not seeded explicitly.
    await expect(
      page
        .locator('text=Failed to save profile')
        .or(page.locator('text=Não foi possível salvar')),
    ).not.toBeVisible({ timeout: 2_000 });

    // Should navigate to /home. Cluster:
    // flutter-web-url-assertion — assert on destination-content
    // visibility (NAV.homeTab) before the URL string assertion, since
    // Flutter web hash routing can lag the AOM mount.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
    expect(page.url()).toContain('/home');
  });

  // ---------------------------------------------------------------------------
  // Test 5: After completing onboarding, the user must land on /home
  //         (NOT /onboarding) on the NEXT sign-in. Pins the
  //         `profile.onboarded_at` persistence contract end-to-end —
  //         today no other test asserts that a SECOND sign-in routes the
  //         already-onboarded user past the onboarding gate.
  //
  //         Regression window: PR 1 (PR #299) moved the half-onboarded
  //         decision from an in-memory `StateProvider<bool>` to a
  //         derived check on `profile.onboarded_at == null`. The save
  //         path (`ProfileRepository.upsertProfile`) stamps that column
  //         from `saveOnboardingProfile`. If either the stamp or the
  //         router gate regresses, this test fails the next time it
  //         runs — making the bug visible BEFORE production users hit
  //         the "onboarded twice" loop.
  // ---------------------------------------------------------------------------
  test('should reach /home on second sign-in after completing onboarding', async ({
    page,
  }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );

    // Drive the onboarding flow to completion — same shape as Test 3.
    await page.evaluate(() => { window.location.hash = '#/onboarding'; });
    await page.waitForURL(/\/(onboarding|home)/, { timeout: 10_000 });

    const isOnOnboarding = page.url().includes('/onboarding');
    if (!isOnOnboarding) {
      test.skip();
      return;
    }

    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(
      page.locator(ONBOARDING_FLOW.profileSetupHeadline),
    ).toBeVisible({ timeout: 10_000 });

    await flutterFill(page, ONBOARDING_FLOW.displayNameInput, 'Returning User');
    await page.locator(ONBOARDING_FLOW.frequency3x).click();
    await page.locator(ONBOARDING.letsGoButton).click();

    // First sign-in: landed on /home post-onboarding.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
    expect(page.url()).toContain('/home');

    // Now log out and back in. The contract: the user must land on /home
    // DIRECTLY, NOT be routed back to /onboarding. The `onboarded_at`
    // column survives the SQL round-trip and `ProfileNotifier.build()`
    // re-emits the same profile post-login, so the router gate's
    // `profile.onboardedAt != null` check passes.
    await logout(page);
    await login(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );

    // The login helper already waits for `NAV.homeTab` to be visible, so
    // reaching this line proves the second sign-in did NOT bounce back
    // to /onboarding. Pin the URL too for explicitness — if the router
    // gate regresses and routes to /onboarding, both assertions fail
    // with a clear category.
    expect(page.url()).toContain('/home');
    await expect(page.locator(ONBOARDING.getStartedButton)).not.toBeVisible({
      timeout: 2_000,
    });
  });

  // ---------------------------------------------------------------------------
  // Test 4: Back button on page 2 returns to page 1.
  //
  // TODO: Requires a fresh user (no profile row). See infrastructure note above.
  // ---------------------------------------------------------------------------
  test('should return to welcome page when tapping Back on profile setup page', async ({
    page,
  }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );
    // Navigate via hash to avoid a full CanvasKit reload.
    await page.evaluate(() => { window.location.hash = '#/onboarding'; });
    await page.waitForURL(/\/(onboarding|home)/, { timeout: 10_000 });

    const isOnOnboarding = page.url().includes('/onboarding');
    if (!isOnOnboarding) {
      test.skip();
      return;
    }

    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(page.locator(ONBOARDING_FLOW.profileSetupHeadline)).toBeVisible({
      timeout: 10_000,
    });

    // Tap Back.
    await page.locator(ONBOARDING_FLOW.backButton).click();

    // Should be back on page 1.
    await expect(page.locator(ONBOARDING_FLOW.welcomeHeadline)).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 5_000,
    });
  });
});
