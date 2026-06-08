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
import { flutterFill, waitForAppReady } from '../helpers/app';
import { AUTH, NAV, ONBOARDING, ONBOARDING_FLOW } from '../helpers/selectors';
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
  // Test 6: Session-expired recovery loop — session cleared then re-auth
  //         routes back to /onboarding (not /home), and completing onboarding
  //         after re-auth reaches /home.
  //
  // What this pins:
  //   (a) After the 42501 Sign in CTA fires `context.go('/login')`, the user
  //       lands on the login screen (navigation contract — widget test swallows
  //       the FlutterError, so this E2E is the only test exercising the real
  //       router path).
  //   (b) Re-auth for a user whose `onboarded_at` is still NULL (the profile
  //       row was deleted by `beforeEach`, not yet stamped) routes to
  //       /onboarding — not /home. The router gate checks `onboardedAt != null`
  //       AFTER the profile provider resolves post-login; if the gate regresses
  //       to a stale cached null or always-true, this test fails.
  //   (c) Completing onboarding after the re-auth stamps `onboarded_at` and
  //       routes to /home — the full save path works end-to-end.
  //
  // Regression window: the root cause of the 42501 fix-wave (five PRs over
  // 48 hours, PR #299–#312) was that users hit the 42501 error on fresh
  // signup, had NO recovery affordance, and were stuck. This test closes
  // the final loop: "the Sign in CTA's navigation target (`/login`) is
  // reachable from `/onboarding` mid-session, and re-auth from that state
  // correctly resumes the onboarding flow rather than dropping the user on
  // /home with an incomplete profile."
  //
  // Session simulation: `page.goto('/')` alone does NOT route to the login
  // screen when the user is still authenticated — the Flutter router sees a
  // live session and routes back to /onboarding. Instead we clear
  // localStorage (which holds the Supabase `sb-*-auth-token` key) before
  // navigating, so the Flutter app reinitializes with no stored session and
  // routes to the login screen. This is equivalent to what the 42501 Sign in
  // CTA achieves via `context.go('/login')` combined with Supabase's
  // auth.signOut() call that clears the persisted token.
  // ---------------------------------------------------------------------------
  test('should route back to /onboarding after re-auth when onboarded_at is still null, then reach /home after completing onboarding', async ({
    page,
  }) => {
    // Step 1: Sign in — user lands on /onboarding (fresh-signup state per
    // beforeEach, no profile row → trigger creates one with NULL onboarded_at).
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });

    // Step 2: Simulate the Sign in CTA navigation — clear the Supabase session
    // from localStorage (the `sb-*-auth-token` key) then navigate to '/'.
    // This is what `context.go('/login')` + auth.signOut() achieves in
    // production: the persisted token is gone, so the Flutter app
    // reinitializes as unauthenticated and the router redirects to the login
    // screen. The profile row still has `onboarded_at = NULL` (onboarding was
    // never completed), so after re-auth the router must route back to
    // /onboarding.
    await page.evaluate(() => window.localStorage.clear());
    await page.goto('/');
    await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 10_000 });

    // Step 3: Re-auth. The router checks profileProvider → profile.onboardedAt
    // == null → needsOnboarding = true → routes to /onboarding.
    // Using loginExpectingOnboarding (not login) because the profile row's
    // `onboarded_at` is still NULL — the re-authed user must NOT land on /home.
    await loginExpectingOnboarding(
      page,
      getUser('smokeOnboarding').email,
      getUser('smokeOnboarding').password,
    );
    // Pin (b): re-auth after the CTA redirects back to /onboarding, not /home.
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({
      timeout: 10_000,
    });
    // Belt-and-suspenders: the home tab must NOT be visible yet.
    await expect(page.locator(NAV.homeTab)).not.toBeVisible({ timeout: 2_000 });

    // Step 4: Complete onboarding after re-auth. This is the full recovery
    // loop: the user fills in their profile and taps LET'S GO.
    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(
      page.locator(ONBOARDING_FLOW.profileSetupIndicator),
    ).toBeVisible({ timeout: 10_000 });

    await flutterFill(page, ONBOARDING_FLOW.displayNameInput, 'Recovery User');
    await page.locator(ONBOARDING_FLOW.frequency3x).click();
    await page.locator(ONBOARDING.letsGoButton).click();

    // Pin (c): after completing onboarding post-re-auth, the user reaches
    // /home. The `onboarded_at` stamp written by `saveOnboardingProfile` is
    // the same code path validated in Test 3; this test pins that the code
    // path is still reachable after a mid-session logout/re-auth cycle.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
    expect(page.url()).toContain('/home');
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

// ---------------------------------------------------------------------------
// Onboarding — fresh-signup end-to-end (regression)
//
// Drives the actual app signup form (NOT Admin API pre-provisioning) through
// the full signup → onboarding → /home arc in a SINGLE continuous session.
//
// WHY this block exists and differs from the 'Onboarding' block above:
//   The pre-provisioned `smokeOnboarding` user has its `auth.users` row
//   committed at global-setup time, so its JWT token chain is stable by
//   the time any test runs. The 42501 RLS race that caused the five-PR
//   fix-wave (PR #299–#312) is a fresh-signup race: a newly-created
//   `auth.users` row reaches `saveOnboardingProfile` within the same
//   session that created the row, before certain Postgres triggers / RLS
//   policies see the committed user. No pre-provisioned user can exercise
//   that window — only a user created mid-test via the real app signup form
//   can hit it.
//
// What this pins:
//   (a) The full signup form contract — toggle, fill, age-gate checkbox
//       (PR #309: onPressed:null until ticked), tap Sign Up.
//   (b) Immediate routing to /onboarding for a fresh account (no profile
//       → `handle_new_user` trigger creates row with NULL onboarded_at).
//   (c) `saveOnboardingProfile` completes WITHOUT a 42501 snackbar in the
//       same session that created the auth.users row.
//   (d) Happy-path: /home reached post-save, onboarded_at stamped.
//
// Teardown: ephemeral user deleted via Admin API in afterEach (mirrors
// auth.spec.ts sign-up happy-path pattern). Best-effort — global teardown
// also sweeps orphaned test accounts.
//
// Race-flushing: run with --repeat-each=10 periodically to flush timing-
// dependent failures in the 42501 window.
// ---------------------------------------------------------------------------
test.describe('Onboarding — fresh-signup end-to-end (regression)', { tag: '@smoke' }, () => {
  // Captured mid-test so afterEach can clean up even if later assertions fail.
  let ephemeralUserId: string | null = null;

  test.afterEach(async () => {
    if (ephemeralUserId) {
      const admin = getAdminClient();
      try {
        await admin.auth.admin.deleteUser(ephemeralUserId);
      } catch {
        // Best-effort — global teardown sweeps orphans.
      }
      ephemeralUserId = null;
    }
  });

  test('should complete signup → onboarding → /home in one session without error snackbar', async ({
    page,
  }) => {
    // Unique-per-run email so parallel workers never collide.
    // Cluster: e2e-spec-state-leak-across-tests.
    const ephemeralEmail = `e2e_fresh_signup_${Date.now()}_${Math.random()
      .toString(36)
      .slice(2, 7)}@test.local`;
    const password = 'TestPassword123!';

    await page.goto('/');
    await waitForAppReady(page);

    // Toggle to sign-up mode.
    await expect(page.locator(AUTH.toggleToSignUp)).toBeVisible({ timeout: 10_000 });
    await page.locator(AUTH.toggleToSignUp).click();
    await expect(page.locator(AUTH.signUpButton)).toBeVisible({ timeout: 5_000 });

    // Fill credentials via real keyboard events (cluster: flutter-web-input-synthetic).
    await flutterFill(page, AUTH.emailInput, ephemeralEmail);
    await flutterFill(page, AUTH.passwordInput, password);

    // PR #309 contract: Sign Up CTA has onPressed:null until age checkbox is ticked.
    await expect(page.locator(AUTH.ageConfirmationCheckbox)).toBeVisible({ timeout: 5_000 });
    await page.locator(AUTH.ageConfirmationCheckbox).click();

    // Tap Sign Up.
    await page.locator(AUTH.signUpButton).click();

    // New user → `handle_new_user` trigger creates profile row with
    // `onboarded_at = NULL` → router routes to /onboarding.
    // Local Supabase: `enable_confirmations = false` (supabase/config.toml
    // [auth.email]) → session returned immediately, no email confirm screen.
    // Cluster: flutter-web-url-assertion — assert content, not URL.
    await expect(page.locator(ONBOARDING.getStartedButton)).toBeVisible({ timeout: 20_000 });

    // Capture userId NOW so afterEach cleans up even if later assertions fail.
    // (getUserIdByEmail does a DB lookup — safe to call mid-test.)
    const admin = getAdminClient();
    ephemeralUserId = await getUserIdByEmail(admin, ephemeralEmail);

    // Advance to page 2.
    await page.locator(ONBOARDING.getStartedButton).click();
    await expect(page.locator(ONBOARDING_FLOW.profileSetupIndicator)).toBeVisible({
      timeout: 10_000,
    });

    // Fill profile fields — this is the exact save path that triggered the
    // 42501 race on fresh signups (PR #299 through #312 fix-wave).
    await flutterFill(page, ONBOARDING_FLOW.displayNameInput, 'Fresh Signup User');
    await page.locator(ONBOARDING_FLOW.frequency3x).click();
    await page.locator(ONBOARDING.letsGoButton).click();

    // -----------------------------------------------------------------------
    // Critical regression assertion: no error snackbar must appear.
    //
    // Copies verbatim from lib/l10n/app_en.arb and lib/l10n/app_pt.arb:
    //   failedToSaveProfile        — generic repository / RLS catch-all
    //   onboardingErrorSessionExpired — 42501 / AuthException typed branch
    //   onboardingErrorOffline     — NetworkException / TimeoutException branch
    //
    // Both locales are checked because the user's locale is not seeded for an
    // ephemeral account — it defaults to the device locale, which may be pt on
    // Portuguese-locale CI agents. The 5 s window is tight enough to catch a
    // snackbar that fires immediately post-save, but we check before the /home
    // navigation assertion so a save error surfaces the correct failure category
    // rather than masking behind a nav timeout.
    // -----------------------------------------------------------------------
    for (const errorCopy of [
      // en copies
      'Failed to save profile. Please try again.',
      'Your session expired. Sign in again.',
      "You're offline. Check your connection and try again.",
      // pt copies
      'Falha ao salvar perfil. Tente novamente.',
      'Sua sessão expirou. Faça login novamente.',
      'Você está offline. Verifique sua conexão e tente novamente.',
    ]) {
      await expect(page.locator(`text=${errorCopy}`).first()).not.toBeVisible({
        timeout: 1_000,
      });
    }

    // Happy-path assert. Cluster: flutter-web-url-assertion — content before URL.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
    expect(page.url()).toContain('/home');
  });
});
