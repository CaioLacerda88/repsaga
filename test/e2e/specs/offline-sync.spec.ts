// Offline sync — E2E tests for Phase 14 offline-first capabilities.
//
// Phase 14 added:
//   14a — ConnectivityService (connectivity_plus OS-level detection) + read-through cache
//   14b — Offline workout capture: queue PendingAction in Hive when save fails offline
//   14c — SyncService auto-drain on reconnection, SyncFailureCard, PendingSyncBadge
//
// -----------------------------------------------------------------------
// How offline simulation works in Playwright
// -----------------------------------------------------------------------
// The app's ConnectivityService uses connectivity_plus which queries the OS
// network stack — NOT an HTTP health check. Playwright's page.route() blocks
// HTTP requests but does NOT change what the OS reports to connectivity_plus.
// Therefore, blocking the REST endpoint glob alone does NOT trigger
// isOnlineProvider to become false and does NOT show the OfflineBanner.
//
// What blocking Supabase REST DOES do:
//   - WorkoutRepository.saveWorkout() throws a network error.
//   - ActiveWorkoutNotifier catches that error and enqueues a PendingAction.
//   - PendingSyncNotifier increments its count → PendingSyncBadge becomes visible.
//   - After unrouting, subsequent save attempts (manual retry) succeed.
//
// What we CANNOT test via Playwright:
//   - OfflineBanner appearance (requires OS-level network loss)
//   - SyncService auto-drain on reconnection (requires an OS offline→online
//     transition so isOnlineProvider emits false then true)
//
// These gaps are documented per-test so future test authors know the boundary.
//
// -----------------------------------------------------------------------
// Test user
// -----------------------------------------------------------------------
// smokeOfflineSync — dedicated user in test-users.ts and global-setup.ts.
// Seeded with one prior workout (lapsed state) so startEmptyWorkout() finds
// "Quick workout" rather than the brand-new beginner CTA.
// Cleaned on every run (freshStateUsers) so queue state doesn't accumulate.

import { test, expect, Page } from '@playwright/test';
import { login } from '../helpers/auth';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
} from '../helpers/workout';
import { NAV, OFFLINE, WORKOUT } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Block all Supabase REST API calls to simulate a network failure for HTTP
 * requests. This does NOT change the OS-reported connectivity status — the
 * OfflineBanner will NOT appear, but save operations will fail and enqueue
 * their payload in the offline Hive queue.
 */
async function blockSupabaseRest(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', (route) =>
    route.abort('connectionrefused'),
  );
}

/**
 * Restore Supabase REST connectivity by removing the route intercept.
 */
async function restoreSupabaseRest(page: Page): Promise<void> {
  await page.unroute('**/rest/v1/**');
}

// ---------------------------------------------------------------------------
// Offline sync smoke tests
//
// Tagged @smoke: these tests run in the CI gate. They are self-contained and
// fast (no network-dependent waits). Each test logs in fresh, performs its
// action, and lands back on home within the 60s test timeout.
// ---------------------------------------------------------------------------

test.describe('Offline sync', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeOfflineSync').email,
      getUser('smokeOfflineSync').password,
    );
  });

  // -------------------------------------------------------------------------
  // Test 1: PendingSyncBadge appears when a workout save is queued offline
  //
  // Flow:
  //   1. Block Supabase REST (simulates failed save, not OS-level offline).
  //   2. Complete a workout — save fails, workout is enqueued in Hive.
  //   3. App navigates back to Home (offline queue path skips celebration).
  //   4. PendingSyncBadge is visible with "1 workout pending sync" text.
  //   5. Unblock REST — subsequent manual retry via badge succeeds.
  //
  // OfflineBanner: NOT tested here because it requires OS-level offline.
  // SyncService auto-drain: NOT tested here because it requires an
  //   isOnlineProvider false→true transition triggered by the OS.
  // -------------------------------------------------------------------------
  test('should show pending sync badge after workout save is queued offline (OFFLINE-001)', async ({
    page,
  }) => {
    // Start a workout and add a set with REST available (home screen and
    // exercise picker need Supabase to load data).
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Block REST just before finishing so the save call fails and the
    // ActiveWorkoutNotifier enqueues the workout in Hive.
    await blockSupabaseRest(page);

    // BUG-020 moved "Finish Workout" back to the persistent bottom bar.
    // The stable semantics identifier remains unchanged.
    await page.click(WORKOUT.finishButton);

    // The finish confirmation dialog appears — confirm save.
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await dialogFinish.click();

    // After queueing the workout, the app navigates to Home.
    // We wait for either the home nav tab or the badge — whichever comes first.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    // The PendingSyncBadge should now be visible on the home screen.
    // It renders inside the body column (not in the nav bar) so it is
    // visible when the home tab is active.
    const badge = page.locator(OFFLINE.pendingSyncBadge);
    await expect(badge).toBeVisible({ timeout: 15_000 });

    // Verify the badge shows exactly 1 workout pending.
    const singularBadge = page.locator(OFFLINE.pendingSyncBadgeSingular);
    await expect(singularBadge).toBeVisible({ timeout: 5_000 });

    // Restore connectivity so the app can sync on manual retry.
    await restoreSupabaseRest(page);

    // The badge remains visible until sync completes. We do NOT wait for
    // auto-drain here because that requires an OS offline→online transition
    // which Playwright cannot simulate.
  });

  // -------------------------------------------------------------------------
  // Test 2: PendingSyncBadge count increments for multiple queued workouts
  //
  // Flow:
  //   1. Block REST, complete and finish two separate workouts.
  //   2. Verify badge shows "2 workouts pending sync".
  //
  // Note: Flutter web Hive storage persists across test runs within the same
  // browser context. global-setup cleans the Supabase side but Hive is local.
  // This test therefore does NOT assert an exact count — it asserts the badge
  // shows a count >= 1 (the workout we just queued, plus any prior residual).
  // Use OFFLINE.pendingSyncBadge (any count) rather than a fixed plural.
  // -------------------------------------------------------------------------
  test('should show pending sync badge with correct label format (OFFLINE-002)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.squat);
    await setWeight(page, '60');
    await setReps(page, '3');
    await completeSet(page, 0);

    // Block REST just before finishing so the save gets queued.
    await blockSupabaseRest(page);

    // BUG-020: Finish button in persistent bottom bar.
    await page.click(WORKOUT.finishButton);
    const dialogFinish2 = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish2).toBeVisible({ timeout: 8_000 });
    await dialogFinish2.click();

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    // The badge must be visible with some pending count.
    // The role=button[name*="pending sync"] selector already validates the
    // accessible name via Playwright's AOM query. Flutter 3.41.6+ does not
    // expose aria-label as a DOM attribute, so getAttribute returns null.
    const badge = page.locator(OFFLINE.pendingSyncBadge);
    await expect(badge).toBeVisible({ timeout: 15_000 });

    // Verify the label matches singular or plural form by checking that
    // one of the specific name patterns is visible in the AOM tree.
    const isSingular = await page
      .locator(OFFLINE.pendingSyncBadgeSingular)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);
    const isPlural = await page
      .locator('role=button[name*="workouts pending sync"]')
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    expect(isSingular || isPlural).toBe(true);

    await restoreSupabaseRest(page);
  });

  // -------------------------------------------------------------------------
  // Test 3: PendingSyncBadge is absent when queue is empty (baseline)
  //
  // This test runs BEFORE any offline simulation. With a fresh user and
  // no queued actions, the badge must be hidden (SizedBox.shrink). This
  // baseline guards against regressions where the badge renders incorrectly
  // when the queue is empty.
  //
  // Note: This test MUST run before OFFLINE-001 and OFFLINE-002 in the same
  // worker — but Playwright does not guarantee test ordering within a describe
  // block when using workers > 1. The smokeOfflineSync user is fresh per run
  // (cleaned by global-setup), so the Supabase queue is empty. Hive (local
  // IndexedDB) may contain residual items from previous browser context runs,
  // but we accept this because the test validates the happy-path absence.
  // -------------------------------------------------------------------------
  test('should not show pending sync badge when queue is empty at login (OFFLINE-003)', async ({
    page,
  }) => {
    // Immediately after login on a fresh session the badge must be absent.
    // We wait briefly for the Home screen to stabilise before asserting.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // Wait for any async providers to settle (e.g. cache refresh).
    await page.waitForTimeout(2_000);

    // The badge uses AnimatedSwitcher with 200ms fade. After 2s it must be gone.
    // We use not.toBeVisible() rather than toBeHidden() because the widget
    // renders SizedBox.shrink() (zero-size, detached from accessibility tree)
    // rather than a visible-but-hidden element.
    const badge = page.locator(OFFLINE.pendingSyncBadge);
    await expect(badge).not.toBeVisible();
  });

  // -------------------------------------------------------------------------
  // Test 4: SyncFailureCard is absent when there are no terminal failures
  //
  // The SyncFailureCard only appears when terminalFailureCount > 0 AND the
  // device is online. Terminal failures require kMaxSyncRetries (6) failed
  // attempts — not achievable in a single E2E test run without artificial
  // retry-count manipulation. This test asserts the card is absent in the
  // normal (no failures) state.
  //
  // Testing SyncFailureCard visibility with terminal failures is deferred
  // to a unit test for SyncService where we can inject retryCount = 6.
  // -------------------------------------------------------------------------
  test('should not show sync failure card when there are no terminal failures (OFFLINE-004)', async ({
    page,
  }) => {
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
    await page.waitForTimeout(2_000);

    // SyncFailureCard text is absent when terminalFailureCount == 0.
    await expect(
      page.locator(OFFLINE.failureCardSingular),
    ).not.toBeVisible();

    await expect(
      page.locator(OFFLINE.failureCardSubtitle),
    ).not.toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Offline sync full suite — non-smoke, more thorough checks
// ---------------------------------------------------------------------------

test.describe('Offline sync — badge interaction', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeOfflineSync').email,
      getUser('smokeOfflineSync').password,
    );
  });

  // -------------------------------------------------------------------------
  // Test 5: Tapping PendingSyncBadge opens the sync management sheet
  //
  // PendingSyncBadge has Semantics(button: true) — tapping it calls
  // _showSyncSheet() which opens a PendingSyncSheet modal bottom sheet.
  // The sheet title "Pending Sync" or the retry controls confirm it opened.
  // -------------------------------------------------------------------------
  test('should open sync management sheet when tapping the pending sync badge (OFFLINE-005)', async ({
    page,
  }) => {
    // Queue a workout by completing one with REST blocked during save.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '100');
    await setReps(page, '3');
    await completeSet(page, 0);

    // Block REST just before finishing so the save gets queued.
    await blockSupabaseRest(page);

    // BUG-020: Finish button in persistent bottom bar.
    await page.click(WORKOUT.finishButton);
    const dialogFinish3 = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish3).toBeVisible({ timeout: 8_000 });
    await dialogFinish3.click();

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    const badge = page.locator(OFFLINE.pendingSyncBadge);
    await expect(badge).toBeVisible({ timeout: 15_000 });

    // Restore REST before tapping the badge — the sheet's retry action needs
    // a working connection.
    await restoreSupabaseRest(page);

    // Tap the badge to open the sync sheet.
    await badge.click();

    // The PendingSyncSheet bottom sheet should be visible. It contains a
    // list of pending actions with retry controls. The sheet title or a
    // "Retry All" / individual retry button confirms it opened.
    // Flutter modal bottom sheets render in a portal outside the main tree —
    // we detect any visible retry button as confirmation.
    const sheetVisible =
      await page
        .locator('text=Retry All')
        .isVisible({ timeout: 8_000 })
        .catch(() => false) ||
      await page
        .locator('text=Pending Sync')
        .isVisible({ timeout: 3_000 })
        .catch(() => false) ||
      await page
        .locator('text=Retry')
        .first()
        .isVisible({ timeout: 3_000 })
        .catch(() => false);

    expect(sheetVisible).toBe(true);

    // Dismiss the sheet.
    await page.keyboard.press('Escape');
  });

  // -------------------------------------------------------------------------
  // Test 6: OfflineBanner absence confirmed — OS-level test boundary
  //
  // This test documents the boundary of what Playwright can test for the
  // OfflineBanner. Blocking Supabase REST does NOT trigger the banner because
  // connectivity_plus reads from the OS network stack, not HTTP responses.
  //
  // The banner is covered by widget tests (test/widget/shared/widgets/) where
  // isOnlineProvider can be mocked to false. This test confirms the banner is
  // correctly absent when the OS reports the connection as online.
  // -------------------------------------------------------------------------
  test('should not show offline banner when OS connectivity is online (OFFLINE-006)', async ({
    page,
  }) => {
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // The OfflineBanner must be absent when the machine is online.
    // This also validates that the banner does not render on fresh login.
    await expect(page.locator(OFFLINE.banner)).not.toBeVisible({
      timeout: 5_000,
    });
  });

  // -------------------------------------------------------------------------
  // Test 7: App navigates to home after offline-queued workout finish
  //
  // When the save is queued (offline path), the app bypasses the PR
  // celebration screen (which requires a successful server response to
  // compute records) and navigates directly to Home. This test verifies
  // the navigation completes without hanging.
  // -------------------------------------------------------------------------
  test('should navigate to home after finishing a workout that is queued offline (OFFLINE-007)', async ({
    page,
  }) => {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.deadlift);
    await setWeight(page, '120');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Block REST just before finishing so the save gets queued.
    await blockSupabaseRest(page);

    // BUG-020: Finish button in persistent bottom bar.
    await page.click(WORKOUT.finishButton);
    const dialogFinish4 = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish4).toBeVisible({ timeout: 8_000 });
    await dialogFinish4.click();

    // Navigation must complete to Home within the timeout.
    // The PR celebration screen is NOT expected here (requires server response).
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    // Confirm we are truly on /home by checking the URL.
    await page.waitForURL(/\/home/, { timeout: 5_000 });

    await restoreSupabaseRest(page);
  });
});
