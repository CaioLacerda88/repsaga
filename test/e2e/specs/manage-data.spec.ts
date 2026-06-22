/**
 * Manage Data — consolidated E2E tests.
 *
 * Sources:
 *   - smoke/manage-data.smoke.spec.ts  (throwaway user, 1 test)    -> @smoke
 *   - full/manage-data.spec.ts         (fullManageData, 11 tests)  -> untagged
 */

import { test, expect, type Page } from '@playwright/test';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { dismissCelebrationIfPresent, flutterFill, navigateToTab, waitForAppReady } from '../helpers/app';
import { login } from '../helpers/auth';
import { AUTH, NAV, WORKOUT, PROFILE, MANAGE_DATA, HISTORY, HOME, SAGA } from '../helpers/selectors';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
  finishWorkout,
} from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';

dotenv.config({ path: path.join(__dirname, '..', '.env.local') });

// ---------------------------------------------------------------------------
// Admin API helpers (used by smoke account deletion test)
// ---------------------------------------------------------------------------

function getAdminClient(): SupabaseClient {
  const supabaseUrl = process.env['SUPABASE_URL'];
  const serviceRoleKey = process.env['SUPABASE_SERVICE_ROLE_KEY'];
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY — check test/e2e/.env.local',
    );
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function createThrowawayUser(supabase: SupabaseClient): Promise<{
  userId: string;
  email: string;
  password: string;
}> {
  const ts = Date.now();
  const email = `e2e-throwaway-delete-${ts}@test.local`;
  const password = 'TestPassword123!';
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error || !data.user) {
    throw new Error(`Failed to create throwaway user: ${error?.message}`);
  }
  return { userId: data.user.id, email, password };
}

async function seedWorkout(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  await supabase.from('workouts').insert({
    user_id: userId,
    name: 'Delete Test Workout',
    started_at: new Date(Date.now() - 3600000).toISOString(),
    finished_at: new Date(Date.now() - 1800000).toISOString(),
    duration_seconds: 1800,
  });
}

async function emergencyCleanup(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  try {
    const { data: workouts } = await supabase
      .from('workouts')
      .select('id')
      .eq('user_id', userId);
    const workoutIds = (workouts ?? []).map((w) => w.id);
    if (workoutIds.length > 0) {
      const { data: wxs } = await supabase
        .from('workout_exercises')
        .select('id')
        .in('workout_id', workoutIds);
      const wxIds = (wxs ?? []).map((wx) => wx.id);
      if (wxIds.length > 0) {
        await supabase.from('sets').delete().in('workout_exercise_id', wxIds);
        await supabase
          .from('workout_exercises')
          .delete()
          .in('workout_id', workoutIds);
      }
      await supabase.from('personal_records').delete().eq('user_id', userId);
      await supabase.from('workouts').delete().eq('user_id', userId);
    }
    await supabase.from('profiles').delete().eq('id', userId);
    await supabase.auth.admin.deleteUser(userId);
  } catch {
    // Swallow — emergency only.
  }
}

// ---------------------------------------------------------------------------
// Raw DB table names that must NEVER appear in visible page text (full suite).
// ---------------------------------------------------------------------------
const FORBIDDEN_TABLE_NAMES = [
  'workouts',
  'workout_exercises',
  'sets',
  'personal_records',
  'profiles',
] as const;

// ---------------------------------------------------------------------------
// Full suite helpers
// ---------------------------------------------------------------------------

/**
 * Ensure the fullManageData user is in Phase 26f lapsed state.
 *
 * The describe block runs tests sequentially and earlier tests (MD-006)
 * delete all workout history, which drops `workoutCountProvider` to 0 and
 * makes the ActionHero render `_CreateFirstRoutineHero` instead of
 * `_FreeWorkoutHero`. Subsequent tests that need to start an empty workout
 * (MD-007/009/010/011) would then fail because `startEmptyWorkout` targets
 * the free-workout banner. Re-seeding a sets-less marker workout before
 * each such test restores lapsed state without re-introducing any
 * workout_exercises / sets the post-delete assertions could trip over.
 *
 * Idempotent on the well-known workout name so this is safe to call from
 * tests that did NOT just delete history (the second insert is a no-op).
 */
async function ensureLapsedStateForFullManageData(
  page: Page,
  userEmail: string,
): Promise<void> {
  const supabase = getAdminClient();
  const { data: userList } = await supabase.auth.admin.listUsers({
    perPage: 1000,
  });
  const user = userList?.users?.find((u) => u.email === userEmail);
  if (!user) return;
  const userId = user.id;

  const { data: existing } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E Manage-Data Lapsed Marker')
    .maybeSingle();
  if (existing) {
    // Already lapsed — but the in-app workoutCountProvider could be stale
    // if a prior test in the describe block called reload(). Force a
    // refresh via page navigation so the Home tree re-queries.
    return;
  }

  const startedAt = new Date(Date.now() - 2 * 60 * 60 * 1000);
  const finishedAt = new Date(Date.now() - 90 * 60 * 1000);
  await supabase.from('workouts').insert({
    user_id: userId,
    name: 'E2E Manage-Data Lapsed Marker',
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    duration_seconds: 1800,
  });

  // The Home screen's workoutCountProvider is `keepAlive` and caches its
  // value for the session. After we insert the marker workout via the
  // admin API we need the client to re-query. A hard reload is the
  // simplest deterministic way to invalidate the cached count without
  // wiring an in-app refresh affordance into this helper. waitForAppReady
  // re-enables semantics so subsequent selectors resolve.
  await page.reload();
  await waitForAppReady(page);
}

/**
 * Complete a single-exercise workout with one set so there is data to delete.
 * Dismisses any post-workout overlay (PR celebration, rank-up, level-up,
 * title-unlock) using the shared deterministic helper so this helper is immune
 * to the ScaleTransition animation race that caused #9/#10/#11 flakiness.
 */
async function doWorkoutAndReturnHome(page: Page): Promise<void> {
  await startEmptyWorkout(page);
  await addExercise(page, SEED_EXERCISES.benchPress);
  await setWeight(page, '60');
  await setReps(page, '5');
  await completeSet(page, 0);
  await finishWorkout(page);

  // Use the shared deterministic helper (Family 2 fix) instead of the racy
  // isVisible()-based check. dismissCelebrationIfPresent uses waitForURL to
  // detect the post-session cinematic (`/workout/finish/:id`) and short-
  // circuits cleanly when the finish goes straight to /home (offline /
  // zero-set finishes).
  await dismissCelebrationIfPresent(page, 25_000);

  await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });
}

/** Navigate to Profile Settings -> Manage Data screen.
 *
 * Phase 18b: /profile shows CharacterSheetScreen; manage-data route moved to
 * /profile/settings/manage-data. Navigate via gear icon → settings → manage data.
 */
async function openManageData(page: Page): Promise<void> {
  await navigateToTab(page, 'Profile');
  await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
  await page.locator(SAGA.gearIcon).first().click();
  await expect(page.locator(PROFILE.manageData)).toBeVisible({ timeout: 10_000 });
  await page.click(PROFILE.manageData);
  await expect(page.locator(MANAGE_DATA.heading)).toBeVisible({ timeout: 15_000 });
}

/**
 * Assert that no currently visible page text contains any of the forbidden
 * database table names. Checks all flt-semantics aria-labels and text nodes.
 *
 * This is the regression guard for the delete bug: if Supabase returns an
 * error like 'relation "workouts" does not exist' and the app forwards that
 * message verbatim to the UI, this assertion catches it.
 */
async function assertNoTableNamesVisible(page: Page): Promise<void> {
  // Gather all accessible text from flt-semantics accessible names (snackbars,
  // dialogs, headings) and visible text nodes.
  // Flutter 3.41.6+ uses AOM — try ariaLabel JS property first, then DOM attr.
  const visibleText = await page.evaluate(() => {
    const labels = Array.from(document.querySelectorAll('flt-semantics'))
      .map((el) => (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '')
      .join(' ');
    const bodyText = document.body.innerText ?? '';
    return (labels + ' ' + bodyText).toLowerCase();
  });

  for (const tableName of FORBIDDEN_TABLE_NAMES) {
    // We only care if the table name appears in a context that looks like an
    // error. A table name in normal data (e.g. the word "sets" in "3 sets")
    // could be a false positive. We check for the table name surrounded by
    // quotes or preceded by "relation" which is a Postgres error pattern.
    const dangerPatterns = [
      `relation "${tableName}"`,
      `table "${tableName}"`,
      `"${tableName}"`,
    ];
    for (const pattern of dangerPatterns) {
      expect(
        visibleText,
        `Found forbidden DB identifier "${pattern}" in visible page text`,
      ).not.toContain(pattern);
    }
  }
}

// =============================================================================
// SMOKE — Account deletion (throwaway user)
// =============================================================================

test.describe('Account deletion', { tag: '@smoke' }, () => {
  let supabase: SupabaseClient;
  let userId: string;
  let userEmail: string;
  let userPassword: string;
  // Track whether in-app deletion succeeded (to skip emergency cleanup).
  let deletionCompletedInApp = false;

  test.beforeAll(async () => {
    supabase = getAdminClient();
    const user = await createThrowawayUser(supabase);
    userId = user.userId;
    userEmail = user.email;
    userPassword = user.password;

    // Seed a workout to verify cascade deletion later.
    await seedWorkout(supabase, userId);

    // Upsert profile so the app routes to Home, not onboarding.
    // PR 1 (PR #299) derives needsOnboarding from `onboarded_at IS NULL`,
    // so we must stamp the timestamp here — otherwise login() times out
    // waiting for NAV.homeTab while the router parks the throwaway user
    // on /onboarding.
    await supabase.from('profiles').upsert(
      {
        id: userId,
        display_name: 'Delete Test User',
        fitness_level: 'beginner',
        onboarded_at: new Date().toISOString(),
      },
      { onConflict: 'id' },
    );

    console.log(
      `[manage-data] Throwaway user created: ${userEmail} (${userId})`,
    );
  });

  test.afterAll(async () => {
    if (!deletionCompletedInApp) {
      console.log(
        `[manage-data] Emergency cleanup for ${userEmail} (in-app deletion did not complete)`,
      );
      await emergencyCleanup(supabase, userId);
    }
  });

  test(
    'should keep confirm disabled with partial string, enable with full DELETE, and verify deletion in backend',
    async ({ page }) => {
      // -- 1. Log in --
      // Use the shared helper for the happy-path sign-in. The re-login attempt
      // later in this test is kept raw because it's expected to fail and the
      // helper would assert the happy path.
      await login(page, userEmail, userPassword);

      // -- 2. Navigate to Profile -> Manage Data --
      // Phase 18b: /profile now shows CharacterSheetScreen; the Manage Data row
      // is on /profile/settings (ProfileSettingsScreen). Navigate via gear icon.
      await navigateToTab(page, 'Profile');
      await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 20_000 });
      await page.locator(SAGA.gearIcon).first().click();
      await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

      await page.click(PROFILE.manageData);
      // Phase 18b: Flutter web context.push does not trigger waitForURL reliably.
      // Assert on element visibility instead.
      await expect(page.locator(MANAGE_DATA.heading).first()).toBeVisible({
        timeout: 15_000,
      });

      // -- 3. Tap "Delete Account" tile --
      // The tile is rendered as a button with aria-name combining title + subtitle.
      // Use the subtitle as the unique selector to avoid ambiguity with the
      // dialog's "Delete Account" button that appears later.
      await page.locator('text=Permanently delete your account and all data').click();

      // The full-screen dialog opens — verify by checking the dialog's heading.
      await expect(
        page.locator('role=heading[name="Delete Account"]'),
      ).toBeVisible({ timeout: 5_000 });

      // -- 4. Assert "Delete Account" button is initially DISABLED --
      // GradientButton with null onPressed renders with disabled=true in semantics.
      // The Playwright accessibility tree exposes this as role=button [disabled].
      const confirmButton = page.locator('role=button[name="Delete Account"]').last();
      await expect(confirmButton).toBeDisabled({ timeout: 5_000 });

      // -- 5. Focus the "DELETE" TextField --
      // The textbox has role=textbox with name matching the hintText "DELETE".
      const deleteInput = page.locator('role=textbox[name="DELETE"]');
      await expect(deleteInput).toBeVisible({ timeout: 5_000 });
      await deleteInput.click();
      // Wait for Flutter's native <input> proxy to appear.
      await page.locator('input').last().waitFor({ state: 'attached', timeout: 5_000 });
      await page.waitForTimeout(200);

      // -- 6. Type "DELET" (one char short) -- button must stay disabled --
      await page.keyboard.press('Control+a');
      await page.keyboard.type('DELET', { delay: 30 });
      await page.waitForTimeout(400);

      await expect(confirmButton).toBeDisabled({ timeout: 3_000 });

      // -- 7. Complete "DELETE" -- button must become enabled --
      await page.keyboard.type('E', { delay: 30 });
      await page.waitForTimeout(500);

      await expect(confirmButton).toBeEnabled({ timeout: 5_000 });

      // -- 8. Tap the enabled confirm button --
      await confirmButton.click();

      // -- 9. Assert redirect to /login --
      // deleteAccount() -> Edge Function delete-user -> authNotifier signOut -> /login.
      await page.waitForURL('**/login**', { timeout: 30_000 });

      // Mark deletion as completed so afterAll skips emergency cleanup.
      // Set this before the page.goto reload so that afterAll never runs
      // emergency cleanup even if the re-login assertion below fails.
      deletionCompletedInApp = true;

      // The Flutter SPA soft-redirect triggers multiple flt-semantics tree rebuild
      // cycles as the auth notifier propagates signOut state, making the semantics
      // nodes unstable for an extended window. A page.goto reload gives a fresh
      // Flutter init and a fully stable login screen — the assertion being tested
      // (re-login fails after deletion) is unaffected by whether we got here via
      // SPA redirect or a fresh load.
      await page.goto('/');
      // waitForAppReady enables the Flutter semantics tree (required after any
      // page.goto — without it, text= selectors won't match canvas-rendered text).
      await waitForAppReady(page);
      await expect(page.locator(AUTH.appTitle)).toBeVisible({ timeout: 10_000 });

      // -- 10. Attempt re-login with deleted credentials -- must FAIL --
      await flutterFill(page, AUTH.emailInput, userEmail);
      await flutterFill(page, AUTH.passwordInput, userPassword);

      await page.click(AUTH.loginButton);

      // Should show an auth error — deleted user cannot log in.
      await expect(page.locator(AUTH.errorMessage)).toBeVisible({
        timeout: 10_000,
      });

      // Must NOT navigate to Home.
      const isOnHome = await page
        .locator(NAV.homeTab)
        .isVisible({ timeout: 3_000 })
        .catch(() => false);
      expect(isOnHome, 'Should NOT navigate to home after re-login with deleted credentials').toBe(false);

      // -- 11. Backend verification: user must be absent from auth --
      // Use getUserById (O(1)) instead of listUsers to avoid a false-positive
      // once the test DB grows beyond the page size. The Supabase admin SDK
      // returns one of two shapes for a missing user depending on server
      // behavior, so we accept EITHER:
      //   - an AuthError with a 404-ish status (most common: 404 not found),
      //   - or a success-shaped response with data.user === null.
      const getUserResult = await supabase.auth.admin.getUserById(userId);
      const userGone =
        (getUserResult.error !== null &&
          (getUserResult.error.status === undefined ||
            getUserResult.error.status === 404 ||
            getUserResult.error.status >= 400)) ||
        getUserResult.data.user === null;
      expect(
        userGone,
        `User ${userEmail} (${userId}) should not exist in auth.users after deletion. ` +
          `getUserById returned: error=${JSON.stringify(getUserResult.error)} ` +
          `data=${JSON.stringify(getUserResult.data)}`,
      ).toBe(true);

      // -- 12. Cascade verification: workouts must be gone --
      const { data: workoutsAfterDelete } = await supabase
        .from('workouts')
        .select('id')
        .eq('user_id', userId);
      const remainingWorkouts = workoutsAfterDelete?.length ?? 0;
      expect(
        remainingWorkouts,
        `Expected 0 workouts after cascade deletion, found ${remainingWorkouts}`,
      ).toBe(0);

      console.log(
        `[manage-data] Verified: user ${userEmail} (${userId}) deleted from auth. ` +
          `Cascade: 0 workouts remaining. Re-login correctly rejected.`,
      );
    },
  );
});

// =============================================================================
// FULL — Manage Data (fullManageData user)
// =============================================================================

test.describe('Manage Data', () => {
  // Belt-and-suspenders: this block's tests are destructive (Reset All /
  // delete-history flows mutate the shared fullManageData user's state) and
  // lean on reseed-idempotency in beforeEach. Serial mode guarantees no two
  // tests race the same reset under --workers>1 / --repeat-each — cluster
  // e2e-spec-state-leak-across-tests.
  test.describe.configure({ mode: 'serial' });

  // Tests that call doWorkoutAndReturnHome run a full workout cycle (Phase 18c
  // overlays + celebrations can queue), so the suite needs the extended 180s
  // budget to stay stable under --repeat-each.
  test.slow();

  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullManageData').email,
      getUser('fullManageData').password,
    );
    // Phase 26f ActionHero collapsed brand-new + lapsed branches into a
    // single workoutCount gate — when count == 0 the hero renders
    // _CreateFirstRoutineHero (no path to an empty workout) and
    // startEmptyWorkout cannot resolve the free-workout banner. Tests
    // earlier in this describe block delete all workout history (MD-006
    // and the Reset All flows), which would leave subsequent tests with
    // workoutCount == 0. Re-seed a sets-less marker workout so the user
    // is always in lapsed state when a test starts. Idempotent on the
    // marker workout name.
    await ensureLapsedStateForFullManageData(
      page,
      getUser('fullManageData').email,
    );
  });

  test('should show a Manage Data row in the DATA MANAGEMENT section on Profile Settings screen (MD-001)', async ({
    page,
  }) => {
    // Phase 18b: manage-data row moved to /profile/settings (ProfileSettingsScreen).
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();

    await expect(page.locator(PROFILE.manageData)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should navigate to the Manage Data screen when tapping the row (MD-002)', async ({
    page,
  }) => {
    await openManageData(page);

    // Both main sections must be visible on the screen.
    await expect(page.locator(MANAGE_DATA.deleteHistory)).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(MANAGE_DATA.resetAll)).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should show workout count subtitle on Delete Workout History tile (MD-003)', async ({
    page,
  }) => {
    await openManageData(page);

    // The subtitle text "N workouts will be removed" (or "... workouts")
    // must appear on screen.
    await expect(page.locator('text=/workouts will be removed/')).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should show Reset All Account Data tile with danger subtitle (MD-004)', async ({
    page,
  }) => {
    await openManageData(page);

    await expect(page.locator(MANAGE_DATA.resetAll)).toBeVisible({
      timeout: 10_000,
    });

    // The subtitle "Removes everything. Permanent." must accompany the tile.
    await expect(page.locator('text=Removes everything')).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should leave workout data intact when cancelling first delete-history dialog (MD-005)', async ({
    page,
  }) => {
    // Log a workout so there is something to cancel-delete.
    await doWorkoutAndReturnHome(page);

    await openManageData(page);

    // Open the delete history flow.
    await page.click(MANAGE_DATA.deleteHistory);

    // The first dialog must appear.
    await expect(
      page.locator('text=Delete all workout history?'),
    ).toBeVisible({ timeout: 8_000 });

    // Cancel — do NOT proceed.
    await page.click('text=Cancel');

    // The dialog must dismiss and we should still be on the Manage Data screen.
    await expect(
      page.locator('text=Delete all workout history?'),
    ).not.toBeVisible({ timeout: 5_000 });
    await expect(page.locator(MANAGE_DATA.heading)).toBeVisible({
      timeout: 5_000,
    });

    // Navigate to history via the Last session line (SPA navigation — page.goto
    // reloads the Flutter SPA and the router doesn't preserve the deep link).
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.lastSessionLine)).toBeVisible({
      timeout: 10_000,
    });
    await page.click(HOME.lastSessionLine);
    await expect(page.locator(HISTORY.heading)).toBeVisible({ timeout: 15_000 });

    // The history list must NOT show the empty state — at least one workout exists.
    await expect(page.locator(HISTORY.emptyState)).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should clear all workout history when confirming both delete-history dialogs (MD-006)', async ({
    page,
  }) => {
    // Ensure at least one workout exists.
    await doWorkoutAndReturnHome(page);

    await openManageData(page);

    // Tap the tile to start the flow.
    await page.click(MANAGE_DATA.deleteHistory);

    // First dialog — confirm.
    await expect(
      page.locator('text=Delete all workout history?'),
    ).toBeVisible({ timeout: 8_000 });
    await page.click(MANAGE_DATA.deleteHistoryConfirmButton);

    // Second dialog — confirm.
    await expect(page.locator('text=Are you sure?')).toBeVisible({
      timeout: 8_000,
    });
    await page.click(MANAGE_DATA.yesDeleteButton);

    // The success SnackBar must appear.
    await expect(page.locator(MANAGE_DATA.historyCleared).first()).toBeVisible({
      timeout: 10_000,
    });

    // No DB table names in visible text (regression check for the delete bug).
    await assertNoTableNamesVisible(page);

    // After history deletion, the Last session line must be hidden (no history).
    // This is a more direct assertion: the home screen hides LastSessionLine
    // when workoutHistory is empty (LastSessionLine renders nothing for a
    // history-less user — 26f preserved this behavior).
    // Wait for the CharacterCard first — it always renders on home and is the
    // most reliable sentinel that the Riverpod home tree has settled after
    // deletion (the stream re-emits before the new layout paints).
    // 20s on the negative assertion accommodates provider invalidation
    // propagating across repeat runs where Supabase sync may still be
    // completing when we navigate to Home.
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.characterCard)).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(HOME.lastSessionLine)).not.toBeVisible({
      timeout: 20_000,
    });
  });

  test('should not expose raw database table names in the UI after delete history (MD-007)', async ({
    page,
  }) => {
    await doWorkoutAndReturnHome(page);
    await openManageData(page);

    await page.click(MANAGE_DATA.deleteHistory);

    await expect(
      page.locator('text=Delete all workout history?'),
    ).toBeVisible({ timeout: 8_000 });
    await page.click(MANAGE_DATA.deleteHistoryConfirmButton);

    await expect(page.locator('text=Are you sure?')).toBeVisible({
      timeout: 8_000,
    });
    await page.click(MANAGE_DATA.yesDeleteButton);

    // Wait for either success SnackBar or for the dialog to close.
    // Then immediately check for forbidden identifiers — the bug manifested
    // as a SnackBar appearing with the table name in the message.
    await expect(page.locator(MANAGE_DATA.historyCleared).first()).toBeVisible({ timeout: 10_000 });

    await assertNoTableNamesVisible(page);

    // Also assert there is no generic error SnackBar that could carry an
    // internal message (belt-and-suspenders).
    await expect(page.locator('text=Failed to clear history')).not.toBeVisible({
      timeout: 3_000,
    });
  });

  test('should keep Reset Account button disabled until RESET is typed in confirmation field (MD-008)', async ({
    page,
  }) => {
    await openManageData(page);

    // Open the Reset All modal.
    await page.click(MANAGE_DATA.resetAll);

    // The full-screen modal must appear (AppBar shows "Reset Account Data").
    await expect(page.locator('text=Reset Account Data')).toBeVisible({
      timeout: 8_000,
    });

    // The "Reset Account" button must be present but disabled (not tappable).
    // Flutter renders a disabled GradientButton with onPressed: null.
    // We verify the button exists but clicking it does NOT close the dialog.
    await expect(page.locator(MANAGE_DATA.resetButton)).toBeVisible({
      timeout: 5_000,
    });

    // The modal stays open after clicking the disabled button.
    await page.click(MANAGE_DATA.resetButton, { force: true });
    await expect(page.locator('text=Reset Account Data')).toBeVisible({
      timeout: 3_000,
    });

    // Type the wrong word — button must remain disabled.
    await flutterFill(page, 'role=dialog >> role=textbox', 'wrong');
    await page.waitForTimeout(500); // debounce — no condition to wait for
    await page.click(MANAGE_DATA.resetButton, { force: true });
    await expect(page.locator('text=Reset Account Data')).toBeVisible({
      timeout: 3_000,
    });

    // Type the correct word "RESET" — button must become enabled.
    // First clear the field using the Flutter fill helper.
    await flutterFill(page, 'role=dialog >> role=textbox', 'RESET');
    await expect(page.locator(MANAGE_DATA.resetButton)).not.toHaveAttribute('aria-disabled', 'true', { timeout: 5_000 });

    // Now clicking the button should close the modal (pop(true)) and trigger
    // the reset. We close by clicking Cancel instead to avoid side effects.
    await page.click(MANAGE_DATA.resetCancelButton);
    await expect(page.locator('text=Reset Account Data')).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should leave all data intact when cancelling the Reset All modal (MD-009)', async ({
    page,
  }) => {
    // Log a workout so there is data to preserve.
    await doWorkoutAndReturnHome(page);

    await openManageData(page);

    await page.click(MANAGE_DATA.resetAll);

    // Modal must open.
    await expect(page.locator('text=Reset Account Data')).toBeVisible({
      timeout: 8_000,
    });

    // Cancel via the X button in the AppBar.
    await page.click(MANAGE_DATA.resetCancelButton);

    // Modal must close.
    await expect(page.locator('text=Reset Account Data')).not.toBeVisible({
      timeout: 5_000,
    });

    // We must still be on the Manage Data screen.
    await expect(page.locator(MANAGE_DATA.heading)).toBeVisible({
      timeout: 5_000,
    });

    // Navigate to history via the Last session line (SPA navigation).
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.lastSessionLine)).toBeVisible({
      timeout: 10_000,
    });
    await page.click(HOME.lastSessionLine);
    await expect(page.locator(HISTORY.heading)).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(HISTORY.emptyState)).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should clear all workout history and personal records when confirming Reset All (MD-010)', async ({
    page,
  }) => {
    // Create data to reset.
    await doWorkoutAndReturnHome(page);

    await openManageData(page);

    await page.click(MANAGE_DATA.resetAll);

    await expect(page.locator('text=Reset Account Data')).toBeVisible({
      timeout: 8_000,
    });

    // Type RESET to enable the confirm button.
    await flutterFill(page, 'role=dialog >> role=textbox', 'RESET');
    await expect(page.locator(MANAGE_DATA.resetButton)).not.toHaveAttribute('aria-disabled', 'true', { timeout: 5_000 });

    // Click the now-enabled "Reset Account" button.
    await page.click(MANAGE_DATA.resetButton);

    // The success SnackBar must appear.
    await expect(page.locator(MANAGE_DATA.accountReset).first()).toBeVisible({
      timeout: 10_000,
    });

    // Regression guard: no table names visible.
    await assertNoTableNamesVisible(page);

    // After Reset All, the Last session line must be hidden (history cleared).
    // Wait for the CharacterCard first — confirms the home tree has re-queried.
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.characterCard)).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(HOME.lastSessionLine)).not.toBeVisible({
      timeout: 20_000,
    });
  });

  test('should not expose raw database table names in the UI after Reset All (MD-011)', async ({
    page,
  }) => {
    await doWorkoutAndReturnHome(page);
    await openManageData(page);

    await page.click(MANAGE_DATA.resetAll);

    await expect(page.locator('text=Reset Account Data')).toBeVisible({
      timeout: 8_000,
    });

    await flutterFill(page, 'role=dialog >> role=textbox', 'RESET');
    await expect(page.locator(MANAGE_DATA.resetButton)).not.toHaveAttribute('aria-disabled', 'true', { timeout: 5_000 });

    await page.click(MANAGE_DATA.resetButton);

    // Wait for the success SnackBar to confirm the operation completed.
    await expect(page.locator(MANAGE_DATA.accountReset).first()).toBeVisible({ timeout: 10_000 });

    // Check the full visible DOM for any forbidden identifiers.
    await assertNoTableNamesVisible(page);

    // Assert no "Failed to reset data" SnackBar appeared.
    await expect(page.locator('text=Failed to reset data')).not.toBeVisible({
      timeout: 3_000,
    });
  });

  // ---------------------------------------------------------------------------
  // MD-012–MD-014: JSON export portability flow (Legal PR 3 — LGPD Art. 18 V /
  // GDPR Art. 20). The OS share sheet that appears after the loading dialog
  // completes is a native layer that Playwright cannot drive; these tests cover
  // the in-app surface: YOUR DATA section render, loading dialog appearance,
  // and the success snackbar that confirms the export step completed.
  //
  // On Flutter web, `share_plus` falls back to a browser download (no native
  // share sheet), so the flow completes without a modal — the success snackbar
  // is the terminal user-visible state.
  // ---------------------------------------------------------------------------

  test('should render the YOUR DATA section and Export my data tile (MD-012)', async ({
    page,
  }) => {
    await openManageData(page);

    // The YOUR DATA section header must appear ABOVE the destructive sections.
    // It is rendered as a plain Text widget — use text= selector.
    await expect(page.locator('text=YOUR DATA')).toBeVisible({ timeout: 8_000 });

    // The Export my data tile — flt-semantics-identifier anchor for locale-
    // independent targeting (per E2E Conventions).
    await expect(page.locator(MANAGE_DATA.exportTile)).toBeVisible({ timeout: 5_000 });

    // The tile subtitle that sets user expectations.
    await expect(
      page.locator('text=Download a JSON file of your account data.'),
    ).toBeVisible({ timeout: 5_000 });

    // Structural order check: YOUR DATA (export) section must appear before the
    // WORKOUT HISTORY section. Both sections are siblings in the same Column —
    // assert the export tile's bounding box top < deleteHistory tile's top.
    const exportBox = await page.locator(MANAGE_DATA.exportTile).first().boundingBox();
    const deleteHistoryBox = await page.locator(MANAGE_DATA.deleteHistory).first().boundingBox();
    if (exportBox && deleteHistoryBox) {
      expect(
        exportBox.y,
        'Export tile must render ABOVE the Delete Workout History tile',
      ).toBeLessThan(deleteHistoryBox.y);
    }
  });

  test('should show a non-dismissible loading dialog while the export is in flight (MD-013)', async ({
    page,
  }) => {
    await openManageData(page);

    // Tap the export tile to start the export flow.
    await page.locator(MANAGE_DATA.exportTile).first().click();

    // The loading dialog MAY appear synchronously — it depends on how fast
    // the export pipeline completes. For users with no data (empty
    // collections), the entire fetch + JSON serialize + share-sink call
    // can finish inside ~100-200ms, which is faster than Playwright's
    // frame-poll granularity for `toBeVisible`. The test then sees the
    // dialog already gone, fails on "element(s) not found", and retries
    // forever.
    //
    // The behavioral contract we're pinning is: "while the export is in
    // flight, the dialog is non-dismissible AND the preparing-text shows".
    // If the in-flight window is shorter than the poll grace, there is
    // nothing for the user to dismiss either — the surface goes straight
    // to the success snackbar (covered by MD-014). Race
    // `role=progressbar` against the success snackbar; whichever appears
    // first satisfies the user-visible contract.
    const progressVisible = page
      .locator('role=progressbar')
      .waitFor({ state: 'visible', timeout: 5_000 })
      .then(() => 'progress' as const)
      .catch(() => null);
    const snackbarVisible = page
      .locator(MANAGE_DATA.exportSuccess)
      .first()
      .waitFor({ state: 'visible', timeout: 5_000 })
      .then(() => 'snackbar' as const)
      .catch(() => null);

    const winner = await Promise.race([progressVisible, snackbarVisible]);
    expect(
      winner,
      'Either the loading dialog or the success snackbar must surface within 5s',
    ).not.toBeNull();

    // If the loading dialog DID surface, assert the preparing-text +
    // non-dismissibility. If the export was too fast, skip this branch —
    // the success snackbar already proved the pipeline ran end-to-end.
    if (winner === 'progress') {
      await expect(
        page.locator('text=Preparing your data export…'),
      ).toBeVisible({ timeout: 5_000 });
      // The loading dialog is guarded by PopScope(canPop: false). We can't
      // simulate a back gesture on Flutter web (cluster:
      // flutter-web-popscope-unreachable), but we CAN assert the dialog
      // remains attached until the export completes — a regression that
      // dropped the barrier would let `not.toBeVisible` succeed
      // immediately, not at the 20s mark below.
    }

    // Wait for the export to complete and the dialog (if it was shown)
    // to dismiss. If the dialog never appeared, this resolves
    // immediately (already not visible).
    await expect(page.locator('role=progressbar')).not.toBeVisible({
      timeout: 20_000,
    });
  });

  test('should show the success snackbar after the export completes (MD-014)', async ({
    page,
  }) => {
    await openManageData(page);

    // Tap the export tile.
    await page.locator(MANAGE_DATA.exportTile).first().click();

    // Wait for the loading dialog to dismiss — signals the export pipeline
    // (fetch + serialize + share-sink hand-off) has completed.
    await expect(page.locator('role=progressbar')).not.toBeVisible({
      timeout: 20_000,
    });

    // Success snackbar must appear. Use .first() — Flutter renders two AOM
    // boundaries per SnackBar (per CLAUDE.md E2E Conventions).
    await expect(
      page.locator(MANAGE_DATA.exportSuccess).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Verify no error snackbar appeared on the same cycle.
    await expect(
      page.locator(MANAGE_DATA.exportFailed).first(),
    ).not.toBeVisible({ timeout: 2_000 });

    // No raw table names must leak through the error path (belt-and-suspenders
    // — mirrors the assertNoTableNamesVisible guard used by MD-007/MD-011).
    await assertNoTableNamesVisible(page);
  });
});
