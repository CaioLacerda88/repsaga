/**
 * Auth spec — merged from smoke and full suites.
 *
 * Smoke: critical login/logout journey (smokeAuth user).
 * Full: edge cases beyond the happy-path — wrong password, non-existent email,
 * empty field validation, mode toggle, duplicate signup, and full tab journey
 * (fullAuth user).
 *
 * Uses dedicated test users created in global-setup.ts.
 * The Flutter web app is served automatically by Playwright's webServer config
 * during local dev. In CI the FLUTTER_APP_URL env var is set by the workflow.
 */

import { test, expect } from '@playwright/test';
import { waitForAppReady, flutterFill } from '../helpers/app';
import { login, logout } from '../helpers/auth';
import {
  AUTH,
  EXERCISE_LIST,
  NAV,
  PROFILE,
  PR_DISPLAY,
  ROUTINE,
  SAGA,
} from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

// ---------------------------------------------------------------------------
// Smoke — critical login/logout journey
// ---------------------------------------------------------------------------
test.describe('Auth', { tag: '@smoke' }, () => {
  test('should show login screen on first load', async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);

    // The login screen identifies itself with the "RepSaga" title and
    // "Welcome back" subtitle.
    await expect(page.locator(AUTH.appTitle)).toBeVisible();
    await expect(page.locator(AUTH.welcomeBack)).toBeVisible();

    // Both form fields must be present.
    await expect(page.locator(AUTH.emailInput)).toBeVisible();
    await expect(page.locator(AUTH.passwordInput)).toBeVisible();

    // The primary action button must be present and labelled LOG IN.
    await expect(page.locator(AUTH.loginButton)).toBeVisible();
  });

  test('should land on home screen with bottom nav after valid login', async ({
    page,
  }) => {
    await login(page, getUser('smokeAuth').email, getUser('smokeAuth').password);

    // The shell scaffold renders the bottom NavigationBar on all main routes.
    await expect(page.locator(NAV.homeTab)).toBeVisible();
    await expect(page.locator(NAV.exercisesTab)).toBeVisible();
    await expect(page.locator(NAV.routinesTab)).toBeVisible();
    await expect(page.locator(NAV.profileTab)).toBeVisible();
  });

  test('should show error message on wrong password login', async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);

    await flutterFill(page, AUTH.emailInput, 'test@example.com');
    await flutterFill(page, AUTH.passwordInput, 'definitely-wrong-password');
    await page.click(AUTH.loginButton);

    // The LoginScreen renders an inline error container on auth failure.
    // The exact text comes from AuthErrorMessages.fromError — we just assert
    // that some error text is rendered, not the exact wording.
    await expect(page.locator(AUTH.errorMessage)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should return to login screen after logout', async ({ page }) => {
    await login(page, getUser('smokeAuth').email, getUser('smokeAuth').password);
    await logout(page);

    // After logout the router redirects to /login.
    await expect(page.locator(AUTH.appTitle)).toBeVisible();
    await expect(page.locator(AUTH.loginButton)).toBeVisible();
  });

  test('should show success feedback for forgot password with valid email', async ({
    page,
  }) => {
    await page.goto('/');
    await waitForAppReady(page);

    // Fill in a valid email address.
    await flutterFill(page, AUTH.emailInput, getUser('smokeAuth').email);

    // Click the forgot password button — opens a confirmation dialog.
    await page.click(AUTH.forgotPasswordButton);

    // Confirm the reset in the dialog.
    const sendReset = page.locator(AUTH.sendResetEmailButton);
    await expect(sendReset).toBeVisible({ timeout: 5_000 });
    await sendReset.click();

    // The login screen itself must still be visible after the reset (no unhandled crash).
    await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 10_000 });

    // The aria-live region may show either a success message ("password reset
    // email sent") or a rate-limit error (429). Both are acceptable outcomes.
    // Only fail if the text contains an unexpected error.
    const hasLiveRegion = await page
      .locator(AUTH.errorMessage)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (hasLiveRegion) {
      const liveText = ((await page.locator(AUTH.errorMessage).textContent()) ?? '').toLowerCase().trim();
      if (liveText.length > 0) {
        const isSuccess = liveText.includes('reset') || liveText.includes('sent') || liveText.includes('inbox');
        const isRateLimit = liveText.includes('rate limit');
        // Both success and rate-limit are acceptable. Any other text is unexpected.
        expect(isSuccess || isRateLimit).toBe(true);
      }
    }
  });

  test('should change button label and subtitle when toggling to sign-up mode', async ({
    page,
  }) => {
    await page.goto('/');
    await waitForAppReady(page);

    // Initially in sign-in mode.
    await expect(page.locator(AUTH.loginButton)).toBeVisible();

    // Toggle to sign-up mode.
    await page.click(AUTH.toggleToSignUp);

    // Button should now read SIGN UP and subtitle should read "Create your
    // account" — both are hard-coded strings in LoginScreen._isSignUp branch.
    await expect(page.locator(AUTH.signUpButton)).toBeVisible();
    await expect(page.locator('text=Create your account')).toBeVisible();

    // Toggle back.
    await page.click(AUTH.toggleToLogIn);
    await expect(page.locator(AUTH.loginButton)).toBeVisible();
    await expect(page.locator(AUTH.welcomeBack)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Full — edge cases beyond the happy-path smoke tests
// ---------------------------------------------------------------------------
test.describe('Auth — edge cases', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
  });

  test('should show error message for wrong password', async ({ page }) => {
    await flutterFill(page, AUTH.emailInput, getUser('fullAuth').email);
    await flutterFill(page, AUTH.passwordInput, 'definitely-wrong-password');
    await page.click(AUTH.loginButton);

    // The LoginScreen renders an inline error container on auth failure.
    await expect(page.locator(AUTH.errorMessage)).toBeVisible({
      timeout: 15_000,
    });

    // The error must not navigate away from the login screen.
    await expect(page.locator(AUTH.appTitle)).toBeVisible();
  });

  test('should show error message for non-existent email login', async ({
    page,
  }) => {
    await flutterFill(page, AUTH.emailInput, 'no-such-user-xyz@test.local');
    await flutterFill(page, AUTH.passwordInput, 'AnyPassword123!');
    await page.click(AUTH.loginButton);

    await expect(page.locator(AUTH.errorMessage)).toBeVisible({
      timeout: 15_000,
    });

    // Still on the login screen.
    await expect(page.locator(AUTH.loginButton)).toBeVisible();
  });

  test('should show error when submitting with empty email and password', async ({
    page,
  }) => {
    // Leave both fields blank and submit.
    await page.click(AUTH.loginButton);

    // Either inline validation text or the error alert must appear.
    const hasError =
      (await page
        .locator(AUTH.errorMessage)
        .isVisible({ timeout: 8_000 })
        .catch(() => false)) ||
      (await page
        .locator('text=Email is required')
        .isVisible({ timeout: 2_000 })
        .catch(() => false)) ||
      (await page
        .locator('text=required')
        .isVisible({ timeout: 2_000 })
        .catch(() => false));

    expect(hasError).toBe(true);
    // Must remain on the login screen.
    await expect(page.locator(AUTH.appTitle)).toBeVisible();
  });

  test('should show validation error for malformed email without @ (AUTH-006)', async ({
    page,
  }) => {
    // Enter an email that is clearly malformed — no "@" symbol.
    await flutterFill(page, AUTH.emailInput, 'notanemail');
    await flutterFill(page, AUTH.passwordInput, 'AnyPassword123!');
    await page.click(AUTH.loginButton);

    // LoginScreen._validateEmail returns 'Enter a valid email' for this case.
    // The error surfaces as inline field error text below the email input.
    const hasValidationError =
      (await page
        .locator('text=Enter a valid email')
        .isVisible({ timeout: 8_000 })
        .catch(() => false)) ||
      (await page
        .locator('text=valid email')
        .isVisible({ timeout: 2_000 })
        .catch(() => false)) ||
      (await page
        .locator(AUTH.errorMessage)
        .isVisible({ timeout: 2_000 })
        .catch(() => false));

    expect(hasValidationError).toBe(true);

    // Must remain on the login screen — no navigation on validation error.
    await expect(page.locator(AUTH.appTitle)).toBeVisible();
    await expect(page.locator(AUTH.loginButton)).toBeVisible();
  });

  test('should toggle to sign-up mode and back to login mode', async ({ page }) => {
    // Initially in login mode.
    await expect(page.locator(AUTH.loginButton)).toBeVisible();
    await expect(page.locator(AUTH.welcomeBack)).toBeVisible();

    // Toggle to sign-up mode.
    await page.click(AUTH.toggleToSignUp);

    // Sign-up mode: SIGN UP button visible, "Create your account" subtitle.
    await expect(page.locator(AUTH.signUpButton)).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator('text=Create your account')).toBeVisible();

    // Toggle back to login mode.
    await page.click(AUTH.toggleToLogIn);

    await expect(page.locator(AUTH.loginButton)).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(AUTH.welcomeBack)).toBeVisible();
  });

  test('should show error when signing up with already-registered email', async ({
    page,
  }) => {
    // Switch to sign-up mode.
    await page.click(AUTH.toggleToSignUp);
    await expect(page.locator(AUTH.signUpButton)).toBeVisible({ timeout: 5_000 });

    // Attempt to create an account with an email that already exists.
    await flutterFill(page, AUTH.emailInput, getUser('fullAuth').email);
    await flutterFill(page, AUTH.passwordInput, getUser('fullAuth').password);
    await page.click(AUTH.signUpButton);

    // Supabase returns a "User already registered" error that surfaces as an
    // inline error message in LoginScreen.
    await expect(page.locator(AUTH.errorMessage)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should complete full journey: login, navigate all tabs, logout, back on login', async ({
    page,
  }) => {
    await login(page, getUser('fullAuth').email, getUser('fullAuth').password);

    // All four bottom nav tabs must be visible after login.
    await expect(page.locator(NAV.homeTab)).toBeVisible();
    await expect(page.locator(NAV.exercisesTab)).toBeVisible();
    await expect(page.locator(NAV.routinesTab)).toBeVisible();
    await expect(page.locator(NAV.profileTab)).toBeVisible();

    // Navigate through each tab and verify the heading/content loads.
    await page.click(NAV.exercisesTab);
    await expect(page.locator(EXERCISE_LIST.heading)).toBeVisible({ timeout: 15_000 });

    await page.click(NAV.routinesTab);
    await expect(page.locator(ROUTINE.heading).first()).toBeVisible({ timeout: 15_000 });

    // Phase 18b: /profile shows CharacterSheetScreen; Log Out is on /profile/settings.
    await page.click(NAV.profileTab);
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 15_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

    // finding-059: verify /records is reachable via in-app navigation (Records stat row).
    // The StatsRow exposes a "PRs" stat card as role=button that navigates to /records.
    await expect(page.locator(PROFILE.recordsStatRow).first()).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(PROFILE.recordsStatRow).first().click();
    // Assert the Records screen rendered (PR_DISPLAY.screenTitle is
    // Semantics(identifier: 'pr-display-title')). Content-visibility assertion per
    // cluster `flutter-web-url-assertion` — URL hash routing is unreliable.
    await expect(page.locator(PR_DISPLAY.screenTitle)).toBeVisible({ timeout: 15_000 });

    await page.click(NAV.homeTab);
    // Home screen in W8 no longer has a "Start Empty Workout" button.
    // Verify the home tab is active (URL-based confirmation).
    await page.waitForURL('**/home**', { timeout: 15_000 });

    // Logout returns to the login screen.
    await logout(page);

    await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(AUTH.loginButton)).toBeVisible();

    // Bottom nav must not be visible after logout.
    await expect(page.locator(NAV.homeTab)).not.toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Auth — sign-up happy path (finding-037)
// ---------------------------------------------------------------------------
// Uses a throwaway unique-per-run email to avoid conflicts with seeded users.
// afterEach deletes the created user via the admin API so the Supabase auth
// table doesn't accumulate stale test accounts across runs. Per-test cleanup
// (not afterAll) so adding a second test to this describe block in the
// future cannot silently leak earlier-test accounts via closure-capture.
// ---------------------------------------------------------------------------
test.describe('Auth — sign-up happy path', () => {
  let throwawayEmail: string;

  test.beforeEach(async ({ page }) => {
    throwawayEmail = `signup-${Date.now()}-${Math.floor(Math.random() * 9999)}@test.local`;
    await page.goto('/');
    await waitForAppReady(page);
  });

  test.afterEach(async () => {
    // Clean up the throwaway user immediately after the test that created it.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, throwawayEmail);
    if (userId) {
      await admin.auth.admin.deleteUser(userId);
    }
  });

  test('should create a new account and reach email confirmation screen', async ({
    page,
  }) => {
    // Toggle to sign-up mode.
    await page.click(AUTH.toggleToSignUp);
    await expect(page.locator(AUTH.signUpButton)).toBeVisible({ timeout: 5_000 });

    // Enter credentials for a brand-new email address (unique per run).
    await flutterFill(page, AUTH.emailInput, throwawayEmail);
    await flutterFill(page, AUTH.passwordInput, 'TestPass123!');
    await page.locator(AUTH.signUpButton).click();

    // After a successful sign-up, Supabase requires email confirmation.
    // The app navigates to /email-confirmation and shows the EmailConfirmationScreen.
    // Assert via the "BACK TO LOGIN" GradientButton which is the most stable
    // AOM target on that screen (no flt-semantics-identifier on the heading
    // Text widget — CanvasKit renders it to canvas). Content-visibility assertion
    // per cluster `flutter-web-url-assertion`.
    await expect(
      page.locator(AUTH.emailConfirmationBackToLogin),
    ).toBeVisible({ timeout: 15_000 });
  });
});
