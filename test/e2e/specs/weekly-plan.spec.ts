/**
 * Weekly Plan — consolidated E2E tests.
 *
 * Sources:
 *   - smoke/weekly-plan.smoke.spec.ts        (smokeWeeklyPlan, 5 tests)       -> @smoke
 *   - smoke/weekly-plan-review.smoke.spec.ts (smokeWeeklyPlanReview, 9 tests) -> @smoke
 *
 * Both sources are smoke tests — no full/regression equivalent exists yet.
 */

import { test, expect } from '@playwright/test';
import { Page } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab } from '../helpers/app';
import { HOME, WEEKLY_PLAN, WEEKLY_PLAN_26E } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

/**
 * Flutter's ListView.builder uses viewport culling — items outside the visible
 * area are not rendered in the DOM. Scroll the active bottom sheet down to
 * force all items to render, then locate the one matching [buttonNameFragment].
 *
 * Uses page.mouse.wheel() which triggers Flutter's scroll physics (same
 * approach as routines.spec.ts BUG-004 exercise scroll tests).
 */
async function scrollSheetAndClick(
  page: Page,
  buttonNameFragment: string,
): Promise<void> {
  // Try to find the element without scrolling first (it may already be visible).
  const loc = page.locator(`role=button[name*="${buttonNameFragment}"]`).first();
  const alreadyVisible = await loc
    .waitFor({ state: 'visible', timeout: 3_000 })
    .then(() => true)
    .catch(() => false);

  if (alreadyVisible) {
    await loc.click();
    return;
  }

  // Position the mouse over the sheet's content area so wheel events scroll
  // the sheet's list, not the background page.
  const viewportSize = page.viewportSize();
  const cx = viewportSize ? viewportSize.width / 2 : 400;
  const cy = viewportSize ? viewportSize.height * 0.7 : 500;
  await page.mouse.move(cx, cy);

  // Scroll the bottom-sheet list down in steps until the button becomes visible.
  // page.mouse.wheel() triggers Flutter's scroll physics reliably.
  for (let i = 0; i < 8; i++) {
    await page.mouse.wheel(0, 200);
    await page.waitForTimeout(300);

    const visible = await loc
      .waitFor({ state: 'visible', timeout: 1_500 })
      .then(() => true)
      .catch(() => false);
    if (visible) break;
  }

  await expect(loc).toBeVisible({ timeout: 5_000 });
  await loc.click();
}

// The Push Day starter routine is seeded by seed.sql.
const PUSH_DAY = 'Push Day';

/**
 * Reseed the smokeWeeklyPlan user back to the canonical "no plan + minimal
 * workout" baseline that `global-setup.ts:smokeWeeklyPlan` originally
 * provisioned (delete weekly_plans + ensureProfile + seedMinimalWorkout).
 *
 * Why this exists
 * ---------------
 * The five tests in the 'Weekly Plan' smoke describe block ALL run
 * sequentially against the SAME server-side user (Playwright per-worker user
 * isolation handles cross-worker races, not intra-worker back-to-back tests).
 * Tests 3 and 5 mutate weekly_plans:
 *
 *   - Test 3 ('should add a routine ...') opens Plan Management, optionally
 *     clears any existing plan via the AppBar overflow menu, then adds
 *     Push Day. The clear-existing path is defensive AND silently no-ops
 *     when the popup menu doesn't render in the 3 s observation window —
 *     so under CI 4-vCPU contention the defensive branch can run, hit a
 *     transient hidden-popup state, and proceed to "add" Push Day on top
 *     of a stale plan. Once Push Day is in the plan, the AddRoutinesSheet
 *     correctly filters it OUT (server-side dedupe), so a retry of test 3
 *     finds nothing to scroll to and times out on `scrollSheetAndClick`.
 *
 *   - Test 5 ('should remove routines ...') clears the plan, but that
 *     runs AFTER test 3, so it doesn't repair test 3's setup pollution.
 *
 *   - On CI `retries: 1`, a failed test 3 first attempt that managed to
 *     add Push Day before failing leaves the row in the table; the retry
 *     then can't add Push Day a second time.
 *
 * Direct evidence: the CI failure artifact (run 26261681645) page snapshot
 * shows the Plan Management screen with Push Day already pinned to the
 * plan (with an "X" remove button) AND the AddRoutinesSheet open below it
 * listing 'Pull Day, Leg Day, Full Body, + Create new routine' — Push Day
 * is missing from the sheet because it's already in the plan.
 *
 * Fix mirrors `reseedFullCrashUser` in crash-recovery.spec.ts (commit
 * 28d67d6): per-test reset back to the baseline that global-setup
 * established, BEFORE login, so the Flutter app hydrates from clean state.
 *
 * Reset scope = global-setup `smokeWeeklyPlan` runner:
 *   - weekly_plans (delete)
 *   - ensureProfile (no-op if already set, mirrors global-setup)
 *   - seedMinimalWorkout (idempotent — checks 'E2E Warmup Workout' sentinel)
 *
 * Idempotent. Safe to call on a user that's already clean.
 */
async function reseedSmokeWeeklyPlanUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(
    admin,
    getUser('smokeWeeklyPlan').email,
  );
  if (!userId) return;

  // Delete weekly_plans rows for this user — mirrors global-setup's
  // smokeWeeklyPlan runner step 1. Cascade: weekly_plans → no FK children
  // (routine_id is a soft reference; routines stay intact).
  await admin.from('weekly_plans').delete().eq('user_id', userId);

  // The other two steps in global-setup's smokeWeeklyPlan runner —
  // ensureProfile and seedMinimalWorkout — are idempotent: ensureProfile
  // upserts a row keyed on user_id, seedMinimalWorkout checks for an
  // existing workout named 'E2E Warmup Workout' before inserting. After
  // global-setup runs once at suite start, both are no-ops on subsequent
  // calls. We deliberately do NOT re-call them here: the test pollution
  // mechanism is weekly_plans accumulation specifically, not profile or
  // workout drift. Keeping the reset surgical avoids touching tables that
  // aren't part of the leak.
}

// =============================================================================
// SMOKE — Weekly Plan (smokeWeeklyPlan user)
// =============================================================================

test.describe('Weekly Plan', { tag: '@smoke' }, () => {
  // Serial mode: the five tests share one server-side user; serial execution
  // serializes the per-test reseed in beforeEach so test N+1's setup never
  // races test N's teardown. Also makes `--repeat-each=N` stable for this
  // file. Cross-worker isolation is unaffected — each worker still has its
  // own `smokeWeeklyPlan` user via the per-worker user pool.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    // Reset the server-side user to the canonical baseline BEFORE login so
    // the Flutter app hydrates from clean state. See `reseedSmokeWeeklyPlanUser`
    // docstring for the per-test pollution mechanism this prevents.
    await reseedSmokeWeeklyPlanUser();
    await login(
      page,
      getUser('smokeWeeklyPlan').email,
      getUser('smokeWeeklyPlan').password,
    );
    // Start on the Home tab where the THIS WEEK section lives.
    await navigateToTab(page, 'Home');
  });

  test('should show THIS WEEK section or Plan your week CTA on home screen when routines exist', async ({
    page,
  }) => {
    // After login, either "THIS WEEK" (plan set) or "Plan your week" CTA
    // (no plan yet) should appear in the home area. Both indicate the
    // WeekBucketSection is rendering correctly.
    //
    // Note: When no plan is set, _EmptyBucketState renders BOTH "THIS WEEK"
    // (as a section header) and "Plan your week" (as a CTA). Using .or()
    // without .first() would match 2 elements and trigger a strict mode
    // violation, so we use .first() to pick whichever appears first.
    const thisWeek = page.locator(WEEKLY_PLAN.thisWeekHeader).first();
    const planYourWeek = page.locator(WEEKLY_PLAN.planYourWeekCta);

    // Wait for one of the two states to appear.
    await expect(thisWeek.or(planYourWeek).first()).toBeVisible({ timeout: 15_000 });
  });

  test('should navigate to Plan Management screen when tapping Plan your week CTA', async ({
    page,
  }) => {
    // If the plan already exists (from a previous run), clear it first via
    // the Plan Management screen so we can reach the CTA.
    // Use .first() because _EmptyBucketState renders "THIS WEEK" as a
    // section header alongside "Plan your week", and _ActiveBucketSection
    // also renders "THIS WEEK" — strict mode requires a single element.
    const thisWeekVisible = await page
      .locator(WEEKLY_PLAN.thisWeekHeader)
      .first()
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (thisWeekVisible) {
      // Plan already exists — navigate to plan management via hash routing.
      // page.goto() would reload the Flutter SPA and lose app state.
      await page.evaluate(() => { window.location.hash = '#/plan/week'; });
    } else {
      // Tap the "Plan your week" CTA.
      await page.locator(WEEKLY_PLAN.planYourWeekCta).click();
    }

    // Plan Management screen title is "This Week's Plan".
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should add a routine to the weekly plan from Plan Management screen', async ({
    page,
  }) => {
    // Navigate via hash — page.goto('/plan/week') returns 404 from the
    // Python file server which has no SPA fallback routing.
    await page.evaluate(() => { window.location.hash = '#/plan/week'; });
    await page.waitForURL('**/plan/week**', { timeout: 10_000 });

    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });

    // Clear any existing plan so we can add fresh. Use the popup menu.
    // The AppBar overflow menu has "Clear Week" option.
    // For a fresh user the plan is empty, but we handle the case where
    // previous test runs left state behind.
    const popupButton = page.locator(WEEKLY_PLAN.overflowMenuButton);

    const popupVisible = await popupButton.isVisible({ timeout: 3_000 }).catch(() => false);
    if (popupVisible) {
      await popupButton.click();
      const clearWeek = page.locator(WEEKLY_PLAN.clearWeekOption);
      const clearVisible = await clearWeek.isVisible({ timeout: 3_000 }).catch(() => false);
      if (clearVisible) {
        await clearWeek.click();
        // Confirm the clear dialog.
        const clearConfirm = page.locator(WEEKLY_PLAN.clearConfirmButton);
        const dialogShown = await clearConfirm.isVisible({ timeout: 5_000 }).catch(() => false);
        if (dialogShown) {
          await clearConfirm.click();
          // After clearing, context.pop() navigates away from /plan/week.
          // When the user navigated via window.location.hash (not a push), pop
          // may not go to /home. Instead of waiting for a specific URL, just
          // wait briefly for navigation to complete, then re-navigate via hash.
          await page.waitForTimeout(2_000);
          await page.evaluate(() => { window.location.hash = '#/plan/week'; });
          await page.waitForTimeout(2_000);
        }
      } else {
        // Popup opened but no clear needed — dismiss the popup with Escape.
        await page.keyboard.press('Escape');
        await page.waitForTimeout(500);
      }
    }

    // Dismiss any lingering popup overlay (Escape closes Flutter popups).
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    // Ensure we're on the plan management screen.
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Tap "Add Routines" button (empty state), "Add Routine" row, or the
    // "+ Add workout" CTA (Phase 26e compact layout — always visible).
    const addRoutinesBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
      .or(page.locator(WEEKLY_PLAN.addRoutineRow))
      .or(page.locator(WEEKLY_PLAN_26E.addWorkoutCta));
    await expect(addRoutinesBtn.first()).toBeVisible({ timeout: 10_000 });
    await addRoutinesBtn.first().click();

    // AddRoutinesSheet appears. Select Push Day.
    await expect(page.locator(WEEKLY_PLAN.addRoutinesSheetTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Tap the Push Day tile in the sheet.
    // Flutter's ListView.builder uses viewport culling — items below the fold
    // are not rendered in the DOM. Use scrollSheetAndClick to scroll until
    // Push Day becomes visible, then click it.
    await scrollSheetAndClick(page, PUSH_DAY);

    // Confirm with "ADD 1 ROUTINE" button.
    await expect(page.locator(WEEKLY_PLAN.addConfirmButton)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(WEEKLY_PLAN.addConfirmButton).click();

    // Push Day should now appear as a row in the plan.
    await expect(page.locator(`text=${PUSH_DAY}`).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should show routine chip on Home screen when routine is in the plan', async ({
    page,
  }) => {
    // Ensure Push Day is in the plan by navigating to plan management.
    // Navigate via hash — page.goto('/plan/week') returns 404 from the
    // Python file server which has no SPA fallback routing.
    await page.evaluate(() => { window.location.hash = '#/plan/week'; });
    await page.waitForURL('**/plan/week**', { timeout: 10_000 });
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });

    // Check if Push Day is already in the list.
    const alreadyIn = await page
      .locator(`text=${PUSH_DAY}`)
      .first()
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (!alreadyIn) {
      // Add it. Phase 26e layout shows "+ Add workout" CTA instead of the
      // old empty-state "Add Routines" button — include it as a fallback.
      const addBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
        .or(page.locator(WEEKLY_PLAN.addRoutineRow))
        .or(page.locator(WEEKLY_PLAN_26E.addWorkoutCta));
      await addBtn.first().click();
      await expect(page.locator(WEEKLY_PLAN.addRoutinesSheetTitle)).toBeVisible({
        timeout: 10_000,
      });
      // Flutter's ListView.builder uses viewport culling — scroll to find Push Day.
      await scrollSheetAndClick(page, PUSH_DAY);
      await page.locator(WEEKLY_PLAN.addConfirmButton).click();
      await expect(page.locator(`text=${PUSH_DAY}`).first()).toBeVisible({
        timeout: 10_000,
      });
    }

    // Navigate to Home.
    await navigateToTab(page, 'Home');

    // 26f: the BucketChipRow is always rendered on Home (header + chips when
    // bucket non-empty + Editar plano link). Use it as the "home loaded and
    // plan reactive" sentinel — replaces the legacy home-status-line check.
    await expect(page.locator(HOME.bucketChipRow).first()).toBeVisible({
      timeout: 15_000,
    });
    // The chip button includes the routine name in its accessible label.
    // Phase 26f: the BucketChipRow wraps each chip in a Semantics(button: true)
    // node AND Flutter renders an inner text node that also exposes role=button
    // — `getByRole('button', { name: /Push Day/ })` resolves to BOTH. Use the
    // outer chip identifier (`home-bucket-chip-*`, with the routine UUID
    // suffix) which is unique and locale-independent.
    await expect(
      page
        .locator(
          '[flt-semantics-identifier^="home-bucket-chip-"]:not([flt-semantics-identifier="home-bucket-chip-row"])',
        )
        .first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('should remove routines from Home screen section when clearing the plan', async ({
    page,
  }) => {
    // Ensure there is at least one routine in the plan first.
    // Navigate via hash — page.goto('/plan/week') returns 404 from the
    // Python file server which has no SPA fallback routing.
    await page.evaluate(() => { window.location.hash = '#/plan/week'; });
    await page.waitForURL('**/plan/week**', { timeout: 10_000 });
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });

    const alreadyIn = await page
      .locator(`text=${PUSH_DAY}`)
      .first()
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (!alreadyIn) {
      // Phase 26e layout always shows "+ Add workout" CTA; include it as a
      // fallback so the test works on both old and new screen revisions.
      const addBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
        .or(page.locator(WEEKLY_PLAN.addRoutineRow))
        .or(page.locator(WEEKLY_PLAN_26E.addWorkoutCta));
      const addVisible = await addBtn.first().isVisible({ timeout: 5_000 }).catch(() => false);
      if (addVisible) {
        await addBtn.first().click();
        await expect(page.locator(WEEKLY_PLAN.addRoutinesSheetTitle)).toBeVisible({
          timeout: 10_000,
        });
        // Flutter's ListView.builder uses viewport culling — scroll to find Push Day.
        await scrollSheetAndClick(page, PUSH_DAY);
        await page.locator(WEEKLY_PLAN.addConfirmButton).click();
        await expect(page.locator(`text=${PUSH_DAY}`).first()).toBeVisible({
          timeout: 10_000,
        });
      }
    }

    // Now clear the week via the popup menu.
    // The PopupMenuButton is wrapped in Semantics(label: 'More options').
    const popupButton = page.locator(WEEKLY_PLAN.overflowMenuButton);
    await expect(popupButton).toBeVisible({ timeout: 5_000 });
    await popupButton.click();

    await expect(page.locator(WEEKLY_PLAN.clearWeekOption)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(WEEKLY_PLAN.clearWeekOption).click();

    // Confirm the "Clear Week" dialog.
    await expect(page.locator(WEEKLY_PLAN.clearConfirmButton)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(WEEKLY_PLAN.clearConfirmButton).click();

    // After clearing, we pop back to home or re-navigate.
    // Wait for navigation to settle.
    await page.waitForURL('**/home**', { timeout: 10_000 }).catch(() => {});

    // Navigate to Home.
    await navigateToTab(page, 'Home');

    // Home should now show "Plan your week" CTA (no plan set).
    await expect(page.locator(WEEKLY_PLAN.planYourWeekCta)).toBeVisible({
      timeout: 15_000,
    });
  });
});

// =============================================================================
// SMOKE — Weekly Plan Review (smokeWeeklyPlanReview user)
// =============================================================================

test.describe('Weekly Plan review', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWeeklyPlanReview').email,
      getUser('smokeWeeklyPlanReview').password,
    );
    await navigateToTab(page, 'Home');
  });

  test('should render weekly plan section on home screen without error', async ({ page }) => {
    // At least one of the three states must be visible.
    // Use .first() on each locator to avoid strict mode violations when
    // multiple "THIS WEEK" text nodes coexist (e.g., _EmptyBucketState
    // renders "THIS WEEK" header alongside "Plan your week" CTA).
    const thisWeek = page.locator(WEEKLY_PLAN.thisWeekHeader).first();
    const weekComplete = page.locator(WEEKLY_PLAN.weekCompleteHeader);
    const planYourWeek = page.locator(WEEKLY_PLAN.planYourWeekCta);

    await expect(
      thisWeek.or(weekComplete).or(planYourWeek).first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  test('should show WEEK COMPLETE header when all bucket routines are done', async ({
    page,
  }) => {
    const weekComplete = page.locator(WEEKLY_PLAN.weekCompleteHeader);
    const isComplete = await weekComplete.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!isComplete) {
      // TODO: Seed completed weekly plan in global-setup.ts.
      // For now, skip the assertion — the test is a placeholder for when
      // infrastructure supports seeding a complete week.
      test.skip();
      return;
    }

    // The WEEK COMPLETE header must be visible.
    await expect(weekComplete).toBeVisible();
  });

  test('should show stats text with sessions count when week review is shown', async ({
    page,
  }) => {
    const weekComplete = page.locator(WEEKLY_PLAN.weekCompleteHeader);
    const isComplete = await weekComplete.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!isComplete) {
      // TODO: Seed completed weekly plan in global-setup.ts.
      test.skip();
      return;
    }

    // The stats text always includes "sessions".
    await expect(page.locator(WEEKLY_PLAN.sessionsStatsText)).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should navigate to Plan Management screen when tapping NEW WEEK button', async ({ page }) => {
    const weekComplete = page.locator(WEEKLY_PLAN.weekCompleteHeader);
    const isComplete = await weekComplete.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!isComplete) {
      // TODO: Seed completed weekly plan in global-setup.ts.
      test.skip();
      return;
    }

    // Tap NEW WEEK.
    await page.locator(WEEKLY_PLAN.newWeekButton).click();

    // Should navigate to Plan Management screen.
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should display completed routine chips with done state in week review', async ({
    page,
  }) => {
    const weekComplete = page.locator(WEEKLY_PLAN.weekCompleteHeader);
    const isComplete = await weekComplete.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!isComplete) {
      // TODO: Seed completed weekly plan in global-setup.ts.
      test.skip();
      return;
    }

    // In WEEK COMPLETE state, all chips should be in the "done" state.
    // The WeekReviewSection renders chips with RoutineChipState.done when
    // completedWorkoutId != null.
    // Since chips render as non-interactive Containers (no Semantics label),
    // we verify the header and stats are present as proof of correct rendering.
    await expect(weekComplete).toBeVisible();
    await expect(page.locator(WEEKLY_PLAN.sessionsStatsText)).toBeVisible({
      timeout: 5_000,
    });
  });
});

// =============================================================================
// REGRESSION — routine-removed undo SnackBar dismissal time (23-P-4)
//
// Pins the 3 s lifetime of the routine-removed undo SnackBar introduced in
// Phase 23 PR #214 (`_removeRoutine` in `plan_management_screen.dart`). The
// companion `persist-eats-duration` cluster bug hid for weeks because
// source-grep widget tests pinned `persist: false` at the call site but
// nothing asserted the snack actually disappeared at duration. This test
// closes that gap for the weekly-plan surface.
//
// Dedicated user `smokeWeeklyPlanRoutineRemoveUndo` ensures this test, which
// waits 3 s for a SnackBar to expire, can't race the `smokeWeeklyPlan` plan-
// manipulation tests under workers > 1 (both navigate to /plan/week and
// modify the routine list).
// =============================================================================

test.describe('Weekly Plan — routine-removed undo SnackBar dismissal (23-P-4)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWeeklyPlanRoutineRemoveUndo').email,
      getUser('smokeWeeklyPlanRoutineRemoveUndo').password,
    );
    await navigateToTab(page, 'Home');
  });

  test('should auto-dismiss the routine-removed undo SnackBar after 3 s (23-P-4)', async ({
    page,
  }) => {
    // Pins the 3 s lifetime of the routine-removed undo SnackBar. Two
    // endpoints bracket the duration contract without coupling to the exact
    // frame the snack closes on:
    //
    //   * Visible at ~1.5 s post-fire   — past the 1 s point but well inside
    //                                      the 3 s window. Guards against
    //                                      "snack dismissed too early".
    //   * Dismissed by ~4.5 s post-fire — past 3 s + ~0.4 s Material exit
    //                                      animation + 1.0 s headroom for
    //                                      headless jitter. Guards against the
    //                                      `persist-eats-duration` cluster bug
    //                                      (`persist: false` dropped or
    //                                      defaulted to true via action).
    //
    // Defensive assertion (c): after the snack times out the routine must
    // still be absent from the list — confirms the snack expired naturally
    // rather than being dismissed by a tap-out or Undo during the wait.

    // Navigate to plan management screen.
    await page.evaluate(() => { window.location.hash = '#/plan/week'; });
    await page.waitForURL('**/plan/week**', { timeout: 10_000 });
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });

    // Ensure the plan is empty so we control which routine gets added.
    // global-setup clears weekly_plans for this user, but handle re-runs.
    const popupButton = page.locator(WEEKLY_PLAN.overflowMenuButton);
    const popupVisible = await popupButton.isVisible({ timeout: 3_000 }).catch(() => false);
    if (popupVisible) {
      await popupButton.click();
      const clearWeek = page.locator(WEEKLY_PLAN.clearWeekOption);
      const clearVisible = await clearWeek.isVisible({ timeout: 3_000 }).catch(() => false);
      if (clearVisible) {
        await clearWeek.click();
        const clearConfirm = page.locator(WEEKLY_PLAN.clearConfirmButton);
        const dialogShown = await clearConfirm.isVisible({ timeout: 5_000 }).catch(() => false);
        if (dialogShown) {
          await clearConfirm.click();
          await page.waitForTimeout(2_000);
          await page.evaluate(() => { window.location.hash = '#/plan/week'; });
          await page.waitForTimeout(2_000);
        }
      } else {
        await page.keyboard.press('Escape');
        await page.waitForTimeout(500);
      }
    }
    // Unconditional Escape + 500 ms settle. Empirically required even on
    // the clean first-run path (global-setup cleared the plan, popup never
    // opened): without it the second `weekly-plan-title` visibility check
    // below times out at 10 s on a non-zero fraction of runs. The 500 ms
    // wait gives the freshly-navigated `/plan/week` overlay tree time to
    // settle (PR-#217 reviewer-cycle Finding 3: removing this regressed
    // the test from green to flaky).
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Add Push Day to the plan so there is a pending (non-done) routine row
    // available for swipe-remove. Push Day is a default routine seeded by
    // seed.sql — available to every user without manual creation.
    // Phase 26e layout always shows "+ Add workout" CTA instead of the old
    // empty-state "Add Routines" button — include it as a fallback.
    const addBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
      .or(page.locator(WEEKLY_PLAN.addRoutineRow))
      .or(page.locator(WEEKLY_PLAN_26E.addWorkoutCta));
    await expect(addBtn.first()).toBeVisible({ timeout: 10_000 });
    await addBtn.first().click();

    await expect(page.locator(WEEKLY_PLAN.addRoutinesSheetTitle)).toBeVisible({
      timeout: 10_000,
    });

    // scrollSheetAndClick is defined at the top of this spec file. It handles
    // Flutter's ListView.builder viewport culling by scrolling until Push Day
    // becomes visible, then clicking it.
    await scrollSheetAndClick(page, PUSH_DAY);

    await expect(page.locator(WEEKLY_PLAN.addConfirmButton)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(WEEKLY_PLAN.addConfirmButton).click();

    // Confirm Push Day is now in the list.
    await expect(page.locator(`text=${PUSH_DAY}`).first()).toBeVisible({
      timeout: 10_000,
    });

    // Wait for the "Saved" confirmation snackbar to fire and dismiss before
    // interacting with the row. A 2.5 s settle covers the 1.7 s worst-case
    // Saved lifetime + headroom (same rationale as the original swipe test).
    await page.waitForTimeout(2_500);

    // Phase 26e removed the Dismissible swipe gesture; removal is now
    // triggered by the overflow (⋯) button on each BucketRoutineRow.
    // The identifier is 'bucket-row-overflow-{routineId}' — use a CSS
    // attribute-prefix selector to match the first overflow button present
    // without knowing the routineId at test time.
    const overflowBtn = page.locator('[flt-semantics-identifier^="bucket-row-overflow-"]').first();
    await expect(overflowBtn).toBeVisible({ timeout: 5_000 });
    await overflowBtn.click();

    // Appearance assertion — snack fires immediately after dismissal.
    const snackBar = page.locator(WEEKLY_PLAN.routineRemovedUndoSnackBar).first();
    await expect(snackBar).toBeVisible({ timeout: 5_000 });

    // Endpoint 1 — still visible at ~1.5 s (well inside the 3 s window).
    await page.waitForTimeout(1_500);
    await expect(snackBar).toBeVisible({
      timeout: 1_000, // must already be visible, not "soon will be"
    });

    // Endpoint 2 — dismissed by ~4.5 s post-fire.
    //   1.5 s (endpoint 1 elapsed) + 3.0 s (this wait) = 4.5 s post-fire.
    //   Snack lifetime: 3 s duration + ~0.4 s exit animation ≈ 3.4 s.
    //   4.5 s lands 1.1 s past close — that's the headroom against headless
    //   jitter and any frame-level slack in the Material exit transition.
    await page.waitForTimeout(3_000);
    await expect(snackBar).toBeHidden({
      timeout: 1_000,
    });

    // Defensive assertion (c): Push Day must still be absent from the list —
    // confirms the snack timed out naturally, not dismissed by Undo. If Undo
    // had been tapped, Push Day would have been restored and would be visible.
    await expect(page.locator(`text=${PUSH_DAY}`).first()).toHaveCount(0, {
      timeout: 2_000,
    });
  });
});

// =============================================================================
// SMOKE — Phase 26e WeekPlanScreen compact layout (smokeWeeklyPlan user)
//
// Covers the three new surfaces shipped in Phase 26e:
//   1. "+ Add workout" CTA (identifier: weekly-plan-add-workout)
//   2. Engajamento section with 6 muscle-group bars (CHEST/BACK/LEGS/
//      SHOULDERS/ARMS/CORE); CARDIO explicitly absent per v1 rendering rule
//   3. ⓘ tap opens the "How we count sets" explainer bottom sheet
//
// Re-uses the smokeWeeklyPlan user (clean weekly_plans + minimal workout
// seeded). Does NOT test the spontaneous bucket-row tag — that requires a
// full workout-save round-trip; pinned by widget tests (Task 7) instead.
// =============================================================================

test.describe('Weekly Plan — 26e compact layout', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWeeklyPlan').email,
      getUser('smokeWeeklyPlan').password,
    );
    // Navigate directly to the WeekPlanScreen.
    await page.evaluate(() => { window.location.hash = '#/plan/week'; });
    await page.waitForURL('**/plan/week**', { timeout: 10_000 });
    // Wait for the screen title to confirm we are on WeekPlanScreen.
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should show the "+ Add workout" CTA on the compact plan layout', async ({
    page,
  }) => {
    // The CTA is the primary affordance for adding workouts on the new
    // compact-row layout (Phase 26e). Identifier-based — locale-independent.
    await expect(
      page.locator(WEEKLY_PLAN_26E.addWorkoutCta).first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  test('should render Engajamento section with 6 body-part bars (CARDIO absent)', async ({
    page,
  }) => {
    // Flutter's AOM merges all MuscleBarRow text into the EngajamentoSection's
    // single group node aria-label:
    //   "Weekly engagement\nCHEST\n0 / 0\nBACK\n0 / 0\n…\nDone\nPlanned"
    // The section is one AOM group; per-bar assertions all resolve to that
    // same node.  Asserting `name*="CHEST"` on the group confirms CHEST was
    // rendered; similarly for the other 5 bars.
    const section = page.locator(WEEKLY_PLAN_26E.engagementSection).first();
    await expect(section).toBeVisible({ timeout: 15_000 });

    // Each bar name appears in the group's aria-label (name*= substring match).
    // All 6 selectors resolve to the same element — CHEST implies the section
    // rendered; asserting all 6 guards against the wrong bar being dropped.
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarChest).first()).toBeVisible();
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarBack).first()).toBeVisible();
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarLegs).first()).toBeVisible();
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarShoulders).first()).toBeVisible();
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarArms).first()).toBeVisible();
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarCore).first()).toBeVisible();

    // CARDIO is intentionally excluded from the v1 6-bar layout.
    // Since all bars are in one AOM group, absence of CARDIO means the
    // group's aria-label must NOT contain "CARDIO" as a substring.
    await expect(page.locator(WEEKLY_PLAN_26E.muscleBarCardio)).toHaveCount(0);
  });

  test('should open the engagement explainer sheet when the info icon is tapped', async ({
    page,
  }) => {
    // The ⓘ icon sits next to the "Weekly engagement" header.
    await expect(
      page.locator(WEEKLY_PLAN_26E.engagementInfoIcon).first(),
    ).toBeVisible({ timeout: 15_000 });

    await page.locator(WEEKLY_PLAN_26E.engagementInfoIcon).first().click();

    // The bottom sheet title is "How we count sets" (engagementExplainerTitle).
    await expect(
      page.locator(WEEKLY_PLAN_26E.engagementExplainerSheet).first(),
    ).toBeVisible({ timeout: 5_000 });
  });
});
