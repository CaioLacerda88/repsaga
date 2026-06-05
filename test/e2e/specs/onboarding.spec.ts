/**
 * Onboarding spec — smoke suite for the post-signup onboarding flow.
 *
 * Tests the 2-page onboarding flow that appears for new users after sign-up:
 *   Page 1: Welcome ("Track every rep, every time") -> GET STARTED
 *   Page 2: Profile setup (display name + fitness level + frequency) -> LET'S GO
 *
 * **State contract.** The describe-level `beforeEach` below resets the
 * `smokeOnboarding` user to fresh-signup state (no profile row → trigger
 * recreates one with NULL onboarded_at → router routes to /onboarding)
 * before every test. The reset is the seed contract — individual tests
 * MUST NOT defensively guard for "what if we landed on /home"; that
 * branch is impossible under this beforeEach, and the dead conditional
 * was actively misleading (a future test author would see it and assume
 * the seed contract is fragile).
 */

import { test, expect } from '@playwright/test';
import { login, loginExpectingOnboarding, logout } from '../helpers/auth';
import { flutterFill } from '../helpers/app';
import { NAV, ONBOARDING, ONBOARDING_FLOW } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

// ---------------------------------------------------------------------------
// Smoke — onboarding flow
// ---------------------------------------------------------------------------
test.describe('Onboarding', { tag: '@smoke' }, () => {
  // Cluster: e2e-spec-state-leak-across-tests. Test 3 / Test 5 below
  // COMPLETE onboarding (writes onboarded_at via the production save
  // path), leaving the worker's smokeOnboarding profile in a
  // fully-onboarded state. Without this reseed, Test 4 (and any future
  // test sharing this user) finds the user routes to /home, so
  // `loginExpectingOnboarding` times out on the GET STARTED locator.
  // Deleting the row restores the fresh-signup state (no profile, the
  // trigger will create one on next login with NULL onboarded_at =>
  // router goes /onboarding).
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
  // The describe-level beforeEach guarantees fresh-signup state, so
  // login routes to /onboarding deterministically — no branch on
  // page.url() needed.
  // ---------------------------------------------------------------------------
  test('should show welcome content and GET STARTED button on page 1', async ({
    page,
  }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );

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
  // ---------------------------------------------------------------------------
  test('should advance to profile setup page after tapping GET STARTED', async ({ page }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );

    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(ONBOARDING.getStartedButton).click();

    // Page 2: Profile setup. profileSetupIndicator targets the
    // "Beginner" pill — the first stable identifier on page 2.
    await expect(page.locator(ONBOARDING_FLOW.profileSetupIndicator)).toBeVisible({
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

    // Page 1 -> Page 2. Mirror the wait-then-click discipline of test 2
    // — under CanvasKit + GitHub Actions resource contention, the
    // button can be visually painted before its AOM hit-target is
    // wired, so a bare `.click()` lands on a not-yet-clickable node and
    // the next `expect(profileSetupIndicator).toBeVisible` fails because
    // the navigation never fired. The Manage Data export test (MD-013)
    // exposed the same Flutter-web-timing class on this CI run.
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(
      page.locator(ONBOARDING_FLOW.profileSetupIndicator),
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
    // window for the PR-302 / PR-310 / PR-312 fix-wave: if the
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
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(
      page.locator(ONBOARDING_FLOW.profileSetupIndicator),
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
  // ---------------------------------------------------------------------------
  test('should return to welcome page when tapping Back on profile setup page', async ({
    page,
  }) => {
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );

    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(page.locator(ONBOARDING_FLOW.profileSetupIndicator)).toBeVisible({
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
