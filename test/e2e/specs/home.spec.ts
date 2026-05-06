/**
 * Home screen and navigation spec — W8 IA refresh.
 *
 * Tests:
 *  1. All 4 bottom nav tabs are visible and tappable
 *  2. Switching tabs updates the visible screen content
 *  3. Brand-new user sees "YOUR FIRST WORKOUT" CTA (smokeFirstWorkout user)
 *  4. Brand-new user tapping CTA navigates to /workout/active
 *  5. After completing a workout, the Last session line is visible
 *  6. Tapping Last session line navigates to the history screen
 *  7. Lapsed state (has history, no plan) shows Plan your week + Quick workout
 *  8. "Plan your week" button navigates to /plan/week
 *  9. "Quick workout" button starts an active workout (/workout/active)
 * 10. See all routes to /routines when user has >3 routines (no plan state)
 * 11. Profile tab shows the user's email and Log Out button
 * 12. Profile weight unit toggle shows kg and lbs options
 *
 * Stat cell tests (HOME-STAT-001 through HOME-STAT-004) are removed — the
 * _ContextualStatCells widget was deleted in W8. The editorial Last session
 * line (HOME.lastSessionLine) replaces the stat-cell tap-to-history flow.
 */

import { test, expect } from '@playwright/test';
import { dismissCelebrationIfPresent, navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  NAV,
  HOME,
  WORKOUT,
  HISTORY,
  PROFILE,
  WEEKLY_PLAN,
  FIRST_WORKOUT_CTA,
  SAGA,
} from '../helpers/selectors';
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

// ---------------------------------------------------------------------------
// Full — home screen and navigation (fullHome user)
//
// fullHome is cleaned to zero workouts + no plan each run (global-setup
// freshStateUsers). It starts each run in the brand-new state and transitions
// to lapsed after completing a workout.
// ---------------------------------------------------------------------------
test.describe('Home screen and navigation', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, getUser('fullHome').email, getUser('fullHome').password);
  });

  test('should show all four bottom nav tabs after login', async ({ page }) => {
    await expect(page.locator(NAV.homeTab)).toBeVisible();
    await expect(page.locator(NAV.exercisesTab)).toBeVisible();
    await expect(page.locator(NAV.routinesTab)).toBeVisible();
    await expect(page.locator(NAV.profileTab)).toBeVisible();
  });

  test('should update visible content heading when switching tabs', async ({
    page,
  }) => {
    // Exercises tab.
    await page.click(NAV.exercisesTab);
    await page.waitForURL('**/exercises**', { timeout: 15_000 });

    // Routines tab.
    await page.click(NAV.routinesTab);
    await page.waitForURL('**/routines**', { timeout: 15_000 });

    // Profile tab (Phase 18b: shows CharacterSheetScreen).
    await page.click(NAV.profileTab);
    await page.waitForURL('**/profile**', { timeout: 15_000 });
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 15_000 });

    // Home tab — verify the ActionHero or status line renders.
    await page.click(NAV.homeTab);
    await page.waitForURL('**/home**', { timeout: 15_000 });
    // Home always renders either the action hero or the status line.
    const hasHero = await page
      .locator(FIRST_WORKOUT_CTA.label)
      .isVisible({ timeout: 10_000 })
      .catch(() => false);
    const hasPlanBtn = await page
      .locator(HOME.planYourWeek)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);
    const hasStatusLine = await page
      .locator(HOME.statusLine)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);
    expect(hasHero || hasPlanBtn || hasStatusLine).toBe(true);
  });

  test('should show Last session line after completing a workout', async ({
    page,
  }) => {
    // Start and finish a minimal workout with one completed set.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // After completing a workout the Last session editorial line must be visible.
    await expect(page.locator(HOME.lastSessionLine)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should navigate to history screen when tapping Last session line', async ({
    page,
  }) => {
    // Complete a workout first so the Last session line is present.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // Wait for the Last session line then tap it.
    await expect(page.locator(HOME.lastSessionLine)).toBeVisible({
      timeout: 10_000,
    });
    await page.click(HOME.lastSessionLine);

    // History screen heading must appear.
    await expect(page.locator(HISTORY.heading)).toBeVisible({ timeout: 15_000 });
  });

  test('should show lapsed state (Plan your week + Quick workout) after completing a workout', async ({
    page,
  }) => {
    // Complete a workout to push workoutCount above 0 — now lapsed state.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });

    // Lapsed state: no plan this week, has history.
    await expect(page.locator(HOME.planYourWeek)).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(HOME.quickWorkout)).toBeVisible({ timeout: 5_000 });
    // Status line shows "No plan this week".
    await expect(page.locator('text=No plan this week')).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should navigate to /plan/week when tapping Plan your week', async ({
    page,
  }) => {
    // Complete a workout to enter lapsed state.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(HOME.planYourWeek)).toBeVisible({ timeout: 15_000 });
    await page.click(HOME.planYourWeek);

    // Weekly plan management screen must appear.
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should navigate to /workout/active when tapping Quick workout', async ({
    page,
  }) => {
    // Complete a workout to enter lapsed state.
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await setWeight(page, '60');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // Dismiss celebration if shown. Uses URL-based detection to avoid the
    // ScaleTransition visibility race on PR.firstWorkoutHeading / PR.newPRHeading.
    await dismissCelebrationIfPresent(page);

    await expect(page.locator(HOME.quickWorkout)).toBeVisible({ timeout: 15_000 });
    await page.click(HOME.quickWorkout);

    // BUG-020: Finish button only appears after the first exercise is added.
    // Use addExerciseFab as the screen-ready sentinel for an empty workout.
    await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible({
      timeout: 15_000,
    });

    // Clean up — discard the started workout.
    await page.locator(WORKOUT.discardButton).click();
    await expect(page.locator(WORKOUT.discardConfirmButton)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(WORKOUT.discardConfirmButton).click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show user email and Log Out button on profile settings', async ({
    page,
  }) => {
    // Phase 18b: /profile shows CharacterSheet; email + Log Out are on /profile/settings.
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

    // The user's email is shown in the identity card.
    await expect(page.locator(`text=${getUser('fullHome').email}`)).toBeVisible({
      timeout: 10_000,
    });

    // Log Out button must be visible.
    await expect(page.locator(PROFILE.logOutButton)).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should show kg and lbs options in profile weight unit toggle', async ({
    page,
  }) => {
    // Phase 18b: weight unit toggle is on /profile/settings.
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

    await expect(page.locator(PROFILE.kgOption)).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(PROFILE.lbsOption)).toBeVisible({ timeout: 5_000 });

    // Tapping lbs must not crash the app.
    await page.click(PROFILE.lbsOption);
    await expect(page.locator(PROFILE.lbsOption)).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(PROFILE.kgOption)).toBeVisible();
  });
});

// =============================================================================
// SMOKE — Brand-new user CTA (P8 / W8) — smokeFirstWorkout user
//
// A brand-new account with zero workouts and no active weekly plan sees the
// "YOUR FIRST WORKOUT" hero banner recommending the Full Body default routine.
// Tapping the banner must start an active workout at /workout/active.
// =============================================================================
test.describe('First workout CTA (P8)', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeFirstWorkout').email,
      getUser('smokeFirstWorkout').password,
    );
    await navigateToTab(page, 'Home');
  });

  test('should show YOUR FIRST WORKOUT card for a brand-new user', async ({
    page,
  }) => {
    await expect(page.locator(FIRST_WORKOUT_CTA.label)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should recommend the Full Body default routine', async ({ page }) => {
    await expect(page.locator(FIRST_WORKOUT_CTA.label)).toBeVisible({
      timeout: 15_000,
    });
    await expect(
      page.locator(FIRST_WORKOUT_CTA.routineName('Full Body')).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('should navigate to /workout/active when tapping the card', async ({
    page,
  }) => {
    // The CTA renders as a merged-semantics button. Use the card selector
    // (role=button[name*="YOUR FIRST WORKOUT"]) which is reliable with Flutter AOM.
    await expect(page.locator(FIRST_WORKOUT_CTA.card)).toBeVisible({
      timeout: 15_000,
    });

    // Flutter CanvasKit AOM: clicking the flt-semantics button node fires a
    // semantics action (SemanticsAction.tap) which should trigger InkWell.onTap.
    // Use the card locator for the click — it's the merged-semantics node that
    // Flutter's AOM exposes as role=button.
    await page.locator(FIRST_WORKOUT_CTA.card).click();
    await page.waitForTimeout(800);

    // Check if we navigated. If not, try again — Flutter CanvasKit may require
    // two interactions (first activates semantics, second fires the tap).
    const navigated = await page.locator(WORKOUT.finishButton)
      .isVisible({ timeout: 2_000 })
      .catch(() => false);
    if (!navigated) {
      await page.locator(FIRST_WORKOUT_CTA.card).click().catch((e) => {
        console.warn('retry click failed:', e);
      });
      await page.waitForTimeout(800);
    }

    // Active workout screen identifies itself by the Finish Workout button.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });
  });

  test('should NOT render old stat-grid cells (HOME_STATS deleted in W8)', async ({
    page,
  }) => {
    // The _ContextualStatCells widget was deleted. Neither "Last session" nor
    // "Week's volume" should appear on home for any user.
    await expect(page.locator('text=Last session')).not.toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator("text=Week's volume")).not.toBeVisible({
      timeout: 3_000,
    });
  });

  test('should NOT render Start Empty Workout button (removed in W8)', async ({
    page,
  }) => {
    // The old "Start Empty Workout" FilledButton was replaced by the lapsed-state
    // "Quick workout" OutlinedButton and the brand-new hero CTA. Neither the old
    // label should appear.
    await expect(page.locator('text=Start Empty Workout')).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should render all four bottom nav tabs with pixel icons (17.0)', async ({
    page,
  }) => {
    // Phase 17.0 replaced Material IconData with PixelImage in the bottom
    // NavigationBar. Each tab is wrapped in Semantics(identifier: 'nav-<name>')
    // and the icon uses semanticLabel:'' (decorative). Assert every tab is
    // reachable via its identifier — this catches a regression where a pixel
    // asset path is wrong and the widget throws, collapsing the tab.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(NAV.exercisesTab)).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(NAV.routinesTab)).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(NAV.profileTab)).toBeVisible({ timeout: 5_000 });
  });
});
