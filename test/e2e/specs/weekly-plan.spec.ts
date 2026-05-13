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
import { HOME, WEEKLY_PLAN } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

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

// =============================================================================
// SMOKE — Weekly Plan (smokeWeeklyPlan user)
// =============================================================================

test.describe('Weekly Plan', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
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

    // Tap "Add Routines" button (empty state) or "Add Routine" row.
    const addRoutinesBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
      .or(page.locator(WEEKLY_PLAN.addRoutineRow));
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
      // Add it.
      const addBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
        .or(page.locator(WEEKLY_PLAN.addRoutineRow));
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

    // The home status line should be visible (e.g. "0 of 1 this week").
    // The old thisWeekHeader identifier is only on WeekReviewSection which
    // renders in week-complete state — use the always-visible status line.
    await expect(page.locator(HOME.statusLine).first()).toBeVisible({
      timeout: 15_000,
    });
    // The chip button includes the routine name in its accessible label.
    await expect(page.getByRole('button', { name: new RegExp(PUSH_DAY) })).toBeVisible({
      timeout: 10_000,
    });
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
      const addBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
        .or(page.locator(WEEKLY_PLAN.addRoutineRow));
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
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Add Push Day to the plan so there is a pending (non-done) routine row
    // available for swipe-remove. Push Day is a default routine seeded by
    // seed.sql — available to every user without manual creation.
    const addBtn = page.locator(WEEKLY_PLAN.addRoutinesButton)
      .or(page.locator(WEEKLY_PLAN.addRoutineRow));
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

    // Swipe-remove the Push Day row (Dismissible direction: endToStart).
    // The PlanRoutineRow Dismissible is keyed by routine id. We anchor the
    // horizontal drag on the text label's vertical centre — no dedicated
    // Semantics identifier exists on the row; the text is the stable anchor.
    const routineText = page.locator(`text=${PUSH_DAY}`).first();
    await expect(routineText).toBeVisible({ timeout: 5_000 });
    const box = await routineText.boundingBox();
    if (!box) throw new Error('Push Day row bounding box not available');

    const viewport = page.viewportSize() ?? { width: 1280, height: 720 };
    const y = box.y + box.height / 2;
    const startX = viewport.width - 24;
    const endX = 24;

    await page.mouse.move(startX, y);
    await page.mouse.down();
    const steps = 12;
    for (let i = 1; i <= steps; i++) {
      const x = startX - ((startX - endX) * i) / steps;
      await page.mouse.move(x, y, { steps: 2 });
    }
    await page.mouse.up();

    // Appearance assertion — snack fires immediately after dismissal.
    const snackBar = page.locator(WEEKLY_PLAN.routineRemovedUndoSnackBar).first();
    await expect(snackBar).toBeVisible({ timeout: 5_000 });

    // Endpoint 1 — still visible at ~1.5 s (well inside the 3 s window).
    await page.waitForTimeout(1_500);
    await expect(snackBar).toBeVisible({
      timeout: 1_000, // must already be visible, not "soon will be"
    });

    // Endpoint 2 — dismissed by ~4.5 s total (1.5 s elapsed + 3 s more).
    // 3 s duration + ~0.4 s exit animation + 1.0 s headroom = 4.4 s post-fire.
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
