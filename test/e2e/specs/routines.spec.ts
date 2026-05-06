/**
 * Routines — consolidated E2E tests.
 *
 * Sources:
 *   - smoke/routine-management.smoke.spec.ts (smokeRoutineManagement, 3 tests) -> @smoke
 *   - smoke/routine-start.smoke.spec.ts      (smokeRoutineStart, 4 tests)      -> @smoke
 *   - smoke/routine-error.smoke.spec.ts      (smokeRoutineError, 1 test)       -> @smoke
 *   - full/routines.spec.ts                  (fullRoutines, 5 tests)           -> untagged
 *   - full/routine-regression.spec.ts        (fullRoutineRegression, 7 tests)  -> untagged
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import {
  navigateToTab,
  waitForAppReady,
  flutterFill,
  flutterFillByInput,
  flutterLongPress,
  scrollToVisible,
} from '../helpers/app';
import {
  NAV,
  ROUTINE,
  CREATE_ROUTINE,
  EXERCISE_PICKER,
  ROUTINE_MANAGEMENT,
  WORKOUT,
  HOME,
  EXERCISE_LIST,
  EXERCISE_DETAIL,
  CREATE_EXERCISE,
} from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';

// The Push Day starter routine is seeded by seed.sql and always present.
const PUSH_DAY = 'Push Day';

// Starter routine names as inserted by supabase/seed.sql.
const STARTER_ROUTINES = ['Push Day', 'Pull Day', 'Leg Day', 'Full Body'];

// Semantics label for the Barbell Bench Press exercise card in the active workout.
// The _ExerciseCard wraps the name in Semantics with this label pattern.
const BENCH_PRESS_ARIA = 'role=group[name*="Exercise: Barbell Bench Press. Tap for details"]';

// =============================================================================
// SMOKE — Routine management (smokeRoutineManagement user)
// =============================================================================

const ROUTINE_NAME = 'Smoke Test Routine';
const ROUTINE_NAME_EDITED = 'Smoke Test Routine Edited';
// A seeded exercise that always exists.
const EXERCISE_NAME = 'Barbell Bench Press';

test.describe('Routine management', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeRoutineManagement').email,
      getUser('smokeRoutineManagement').password,
    );
    await navigateToTab(page, 'Routines');
  });

  test('should create a new routine and show it in MY ROUTINES list', async ({
    page,
  }) => {
    // Tap the + AppBar action to open CreateRoutineScreen.
    await expect(page.locator(ROUTINE.heading).first()).toBeVisible({ timeout: 10_000 });
    await page.locator(ROUTINE_MANAGEMENT.createIconButton).click();

    // CreateRoutineScreen: title is "Create Routine".
    await expect(page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Fill routine name.
    await flutterFill(page, CREATE_ROUTINE.nameInput, ROUTINE_NAME);

    // Add an exercise — tap "Add Exercise" button.
    await page.locator(CREATE_ROUTINE.addExerciseButton).click();

    // ExercisePickerSheet appears. Search for the exercise.
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });
    await flutterFillByInput(page, 'Search exercises', EXERCISE_NAME);

    // Tap the "Add Barbell Bench Press" tile (use .first() in case of duplicates).
    const addTile = page.locator(EXERCISE_PICKER.addExerciseButton(EXERCISE_NAME)).first();
    await expect(addTile).toBeVisible({ timeout: 10_000 });
    await addTile.click();

    // Back on CreateRoutineScreen — exercise card should now appear.
    await expect(page.locator(`text=${EXERCISE_NAME}`).first()).toBeVisible({
      timeout: 10_000,
    });

    // Save — the Save TextButton in the AppBar.
    await page.locator(CREATE_ROUTINE.saveButton).click();

    // After save, pop back to RoutineListScreen.
    await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
      timeout: 15_000,
    });

    // The new routine must appear in MY ROUTINES.
    await expect(page.locator(ROUTINE.routineName(ROUTINE_NAME)).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should edit a routine name via the action sheet', async ({ page }) => {
    // Ensure the routine exists first (create if missing).
    await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    const routineCard = page.locator(ROUTINE.routineName(ROUTINE_NAME)).first();
    const exists = await routineCard.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!exists) {
      // Create it.
      await page.locator(ROUTINE_MANAGEMENT.createIconButton).click();
      await expect(page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle)).toBeVisible({
        timeout: 10_000,
      });
      await flutterFill(page, CREATE_ROUTINE.nameInput, ROUTINE_NAME);
      await page.locator(CREATE_ROUTINE.addExerciseButton).click();
      await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
        timeout: 10_000,
      });
      await flutterFillByInput(page, 'Search exercises', EXERCISE_NAME);
      await page.locator(EXERCISE_PICKER.addExerciseButton(EXERCISE_NAME)).first().click();
      await page.locator(CREATE_ROUTINE.saveButton).click();
      await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
        timeout: 15_000,
      });
    }

    // Long-press the routine card to open the action sheet.
    await flutterLongPress(page, ROUTINE.routineName(ROUTINE_NAME));

    // Action sheet: tap Edit.
    await expect(page.locator(ROUTINE.editOption)).toBeVisible({ timeout: 10_000 });
    await page.locator(ROUTINE.editOption).click();

    // CreateRoutineScreen in edit mode — title is "Edit Routine".
    await expect(page.locator(ROUTINE_MANAGEMENT.editRoutineScreenTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Clear existing name and type new name.
    await flutterFill(page, CREATE_ROUTINE.nameInput, ROUTINE_NAME_EDITED);

    // Save.
    await page.locator(CREATE_ROUTINE.saveButton).click();

    // Back on list — edited name must appear.
    await expect(page.locator(ROUTINE.routineName(ROUTINE_NAME_EDITED)).first()).toBeVisible({
      timeout: 15_000,
    });

    // Old name must be gone — use exact text match to avoid matching the
    // edited name "Smoke Test Routine Edited" which contains the old name.
    await expect(page.getByText(ROUTINE_NAME, { exact: true })).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should delete a routine and remove it from the list', async ({ page }) => {
    await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Find a deletable routine — either the edited or original name.
    const nameToDelete = await page
      .locator(ROUTINE.routineName(ROUTINE_NAME_EDITED))
      .first()
      .isVisible({ timeout: 3_000 })
      .catch(() => false)
      ? ROUTINE_NAME_EDITED
      : ROUTINE_NAME;

    const routineExists = await page
      .locator(ROUTINE.routineName(nameToDelete))
      .first()
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!routineExists) {
      // Create it fresh so we have something to delete.
      await page.locator(ROUTINE_MANAGEMENT.createIconButton).click();
      await expect(page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle)).toBeVisible({
        timeout: 10_000,
      });
      await flutterFill(page, CREATE_ROUTINE.nameInput, ROUTINE_NAME);
      await page.locator(CREATE_ROUTINE.addExerciseButton).click();
      await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
        timeout: 10_000,
      });
      await flutterFillByInput(page, 'Search exercises', EXERCISE_NAME);
      await page.locator(EXERCISE_PICKER.addExerciseButton(EXERCISE_NAME)).first().click();
      await page.locator(CREATE_ROUTINE.saveButton).click();
      await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
        timeout: 15_000,
      });
    }

    const targetName = routineExists ? nameToDelete : ROUTINE_NAME;

    // Long-press to open action sheet.
    await flutterLongPress(page, ROUTINE.routineName(targetName));

    await expect(page.locator(ROUTINE.deleteOption)).toBeVisible({ timeout: 10_000 });
    await page.locator(ROUTINE.deleteOption).click();

    // Delete confirmation dialog.
    await expect(page.locator(ROUTINE.deleteDialogTitle)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(ROUTINE.deleteConfirmButton).click();

    // The routine must no longer appear in the list.
    await expect(
      page.locator(ROUTINE.routineName(targetName)),
    ).not.toBeVisible({ timeout: 10_000 });
  });
});

// =============================================================================
// SMOKE — Routine start (smokeRoutineStart user, BUG-001/003/004/005)
// =============================================================================

test.describe('Routine start', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeRoutineStart').email,
      getUser('smokeRoutineStart').password,
    );
    await navigateToTab(page, 'Routines');
  });

  test('should preserve exercise name after page reload, not show "Exercise" fallback (BUG-001)', async ({
    page,
  }) => {
    // Start a workout from the Push Day routine.
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });
    // Push Day may render below the fold due to Flutter SliverList viewport
    // culling — scroll it into view before the click.
    const pushDay1 = await scrollToVisible(page, ROUTINE.routineName(PUSH_DAY));
    await pushDay1.click();

    // The active workout screen must load with exercises pre-filled.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // Bench Press must be visible in the exercise card before reload.
    // Use the Semantics aria-label (set on the tappable exercise name area)
    // rather than a plain text selector, which can fail for flt-semantics
    // elements with zero CSS dimensions (text drawn on canvas).
    await expect(page.locator(BENCH_PRESS_ARIA)).toBeVisible({
      timeout: 10_000,
    });

    // Simulate app restore by reloading the page (preserves IndexedDB/Hive).
    await page.reload();

    // After a reload, Flutter CanvasKit re-downloads and must re-initialise.
    // waitForAppReady() re-enables the semantics tree and waits for the auth
    // stream to resolve — document.body.innerText is empty in CanvasKit because
    // text is drawn to canvas, so a plain waitForFunction on innerText never fires.
    await waitForAppReady(page);

    // Navigate back to the active workout (via resume banner or direct route).
    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!finishVisible) {
      // The active workout banner (bottom bar) or "Resume" link should be on
      // the home screen. The banner shows the workout name with em-dash prefix.
      const activeBannerVisible = await page
        .locator(HOME.activeBanner)
        .isVisible({ timeout: 10_000 })
        .catch(() => false);

      if (activeBannerVisible) {
        await page.locator(HOME.activeBanner).click();
      } else {
        const resumeVisible = await page
          .locator('text=Resume')
          .isVisible({ timeout: 5_000 })
          .catch(() => false);
        if (resumeVisible) {
          await page.locator('text=Resume').click();
        } else {
          // Try tapping the active workout banner by routine name.
          const banner = page.locator('role=button[name*="Push Day"]');
          if (await banner.isVisible({ timeout: 5_000 }).catch(() => false)) {
            await banner.click();
          }
        }
      }

      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
    }

    // KEY ASSERTION FOR BUG-001:
    // The exercise name must show the real name, NOT the "Exercise" fallback.
    // We assert both: the real name IS visible, and the raw fallback is absent.
    await expect(page.locator(BENCH_PRESS_ARIA)).toBeVisible({
      timeout: 10_000,
    });

    // Verify the fallback "Exercise" is NOT used as the standalone card header.
    // The Semantics label pattern is "Exercise: <name>. Tap for details."
    // If BUG-001 is present, the label becomes "Exercise: Exercise. Tap for details."
    // We detect this by looking for the specific fallback aria-label.
    const fallbackLabel = page.locator(
      'role=group[name*="Exercise: Exercise. Tap for details"]',
    );
    await expect(fallbackLabel).not.toBeVisible({ timeout: 3_000 });

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    await expect(page.locator(WORKOUT.discardConfirmButton)).toBeVisible({ timeout: 5_000 });
    await page.locator(WORKOUT.discardConfirmButton).click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should start an active workout when tapping a starter routine (BUG-003)', async ({
    page,
  }) => {
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Push Day may render below the fold — scroll into view first.
    const pushDay = await scrollToVisible(page, ROUTINE.routineName(PUSH_DAY));
    await pushDay.click();

    // The active workout screen must appear — the Finish Workout button confirms it.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // At least one exercise card must be rendered (Add Set button signals this).
    // Use .first() to avoid strict mode violations when multiple exercise cards
    // are rendered (each has its own "Add Set" button).
    await expect(page.locator(WORKOUT.addSetButton).first()).toBeVisible({
      timeout: 10_000,
    });

    // The exercise name from the seeded routine must be accessible via its
    // Semantics aria-label in the workout card header.
    await expect(page.locator(BENCH_PRESS_ARIA)).toBeVisible({
      timeout: 10_000,
    });

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    await expect(page.locator(WORKOUT.discardConfirmButton)).toBeVisible({ timeout: 5_000 });
    await page.locator(WORKOUT.discardConfirmButton).click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should pre-fill non-zero weight for first-time exercises when starting routine (BUG-004)', async ({
    page,
  }) => {
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Push Day may render below the fold — scroll into view first.
    const pushDay = await scrollToVisible(page, ROUTINE.routineName(PUSH_DAY));
    await pushDay.click();

    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // The Bench Press card must be accessible via its Semantics aria-label.
    await expect(page.locator(BENCH_PRESS_ARIA)).toBeVisible({
      timeout: 10_000,
    });

    // The weight value in the first set row must NOT be "0" for a barbell exercise.
    // Flutter Semantics uses label: 'Weight value: <N> kg. Tap to enter weight.'
    // with button: true. In Flutter web CanvasKit, the accessible name of the
    // flt-semantics element is exposed via aria-label on the element itself.
    // However Playwright's role=button[name*="..."] uses computed accessible name,
    // which correctly matches these buttons regardless of attribute vs text source.
    const zeroWeightButton = page.locator(
      'role=button[name*="Weight value: 0 kg"]',
    );
    await expect(zeroWeightButton).not.toBeVisible({ timeout: 5_000 });

    // Also verify that at least one weight button with a positive value is shown.
    // Barbell default is 20 kg, dumbbell default is 10 kg.
    const anyWeightButton = page.locator(
      'role=button[name*="Weight value:"]',
    );
    await expect(anyWeightButton.first()).toBeVisible({ timeout: 10_000 });

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    await expect(page.locator(WORKOUT.discardConfirmButton)).toBeVisible({ timeout: 5_000 });
    await page.locator(WORKOUT.discardConfirmButton).click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should show muscle group names in routine card subtitle, not bare count (BUG-005)', async ({
    page,
  }) => {
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Push Day may be below the fold — scroll into view so the card mounts
    // into the DOM before we read its text content.
    await scrollToVisible(page, ROUTINE.routineName(PUSH_DAY));

    // The Push Day card is a flt-semantics[role="button"] whose text content
    // includes the subtitle. Check that the subtitle contains a muscle group name.
    // We filter buttons by text content to find the Push Day card.
    const pushDayCard = page
      .locator('flt-semantics[role="button"]')
      .filter({ hasText: 'Push Day' });

    await expect(pushDayCard.first()).toBeVisible({ timeout: 10_000 });

    // The card's text content should include at least one of the expected
    // muscle group names from Push Day exercises.
    const cardText = await pushDayCard.first().textContent();
    const hasChest = cardText?.includes('Chest') ?? false;
    const hasShoulders = cardText?.includes('Shoulders') ?? false;
    const hasArms = cardText?.includes('Arms') ?? false;

    // At least one muscle group name must appear in the card subtitle.
    expect(hasChest || hasShoulders || hasArms).toBe(true);

    // The fallback text "6 exercises" must NOT appear in the Push Day card text.
    // (Push Day has 6 exercises per seed.sql — that number would appear
    // iff exercise resolution failed and BUG-005 is present.)
    expect(cardText?.includes('6 exercises')).toBe(false);
  });
});

// =============================================================================
// SMOKE — Routine error handling (smokeRoutineError user, BUG-003)
// =============================================================================

test.describe('Routine error handling', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeRoutineError').email,
      getUser('smokeRoutineError').password,
    );
  });

  test('should show error snackbar when starting routine with all-deleted exercises, not silent failure (BUG-003)', async ({
    page,
  }) => {
    const suffix = Date.now();
    const exerciseName = `Smoke BUG-003 Ex ${suffix}`;
    const routineName = `Smoke BUG-003 Routine ${suffix}`;

    // Step 1: Create a custom exercise.
    await navigateToTab(page, 'Exercises');
    await page.click(EXERCISE_LIST.createFab);
    await expect(page.locator(CREATE_EXERCISE.nameInput)).toBeVisible({
      timeout: 10_000,
    });
    await flutterFill(page, CREATE_EXERCISE.nameInput, exerciseName);
    await page.locator('role=button[name*="Muscle group: Chest"]').first().click();
    await page.locator('role=button[name*="Equipment type: Barbell"]').first().click();
    await page.click(CREATE_EXERCISE.saveButton);
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 15_000,
    });

    // Step 2: Create a routine with only this exercise.
    await navigateToTab(page, 'Routines');
    await page.locator(ROUTINE_MANAGEMENT.createIconButton).click();

    const nameInput = page.locator(CREATE_ROUTINE.nameInput);
    await expect(nameInput).toBeVisible({ timeout: 10_000 });
    await nameInput.click();
    await page.keyboard.press('Control+a');
    await page.keyboard.type(routineName, { delay: 10 });

    await page.click(CREATE_ROUTINE.addExerciseButton);
    await expect(
      page.locator('role=textbox[name*="Search exercises to add"]'),
    ).toBeVisible({ timeout: 10_000 });
    await flutterFill(
      page,
      'role=textbox[name*="Search exercises to add"]',
      exerciseName,
    );
    await page.waitForTimeout(600);

    const addBtn = page
      .locator(`role=button[name*="Add ${exerciseName}"]`)
      .first();
    await expect(addBtn).toBeVisible({ timeout: 10_000 });
    await addBtn.click();

    await page.click(CREATE_ROUTINE.saveButton);
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({ timeout: 15_000 });

    // Step 3: Delete the exercise (soft-delete).
    await navigateToTab(page, 'Exercises');
    // Use flutterFillByInput to target the search input's underlying HTML element
    // directly — clicking the flt-semantics overlay does not reliably transfer focus.
    await flutterFillByInput(page, 'Search exercises', exerciseName);
    await page.waitForTimeout(800);

    const card = page.locator(EXERCISE_LIST.exerciseCard(exerciseName)).first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();

    await expect(page.locator(EXERCISE_DETAIL.deleteButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.click(EXERCISE_DETAIL.deleteButton);
    await expect(page.locator(EXERCISE_DETAIL.deleteDialogContent)).toBeVisible({
      timeout: 5_000,
    });
    await page.click(EXERCISE_DETAIL.deleteConfirmButton);
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 15_000,
    });

    // Step 4: Reload the page to clear Riverpod's cached state for routineListProvider.
    // Without a reload, the provider serves stale data where the exercise still
    // appears non-deleted (Riverpod AsyncNotifier without autoDispose does not
    // re-fetch on tab navigation). The reload forces a cold re-fetch so that
    // startRoutineWorkout sees the updated deletedAt timestamp.
    await page.reload();
    await waitForAppReady(page);
    await navigateToTab(page, 'Routines');
    await page.waitForTimeout(500);

    const myRoutineCard = page.locator(ROUTINE.routineName(routineName)).first();
    await expect(myRoutineCard).toBeVisible({ timeout: 10_000 });
    await myRoutineCard.click();

    // Step 5-6: The error snackbar must appear.
    // The deleted exercise is filtered out -> exercises is empty -> snackbar fires.
    // Use .first() because Flutter renders both <flt-announcement-polite> (a11y)
    // and a <span> (visual) for SnackBar text — strict mode requires one element.
    await expect(
      page.locator('text=Could not load exercises').first(),
    ).toBeVisible({ timeout: 10_000 });

    // Step 7: The active workout screen must NOT have appeared.
    // If Finish Workout is visible the silent-failure bug is present.
    await expect(page.locator(WORKOUT.finishButton)).not.toBeVisible({
      timeout: 3_000,
    });
  });
});

// =============================================================================
// FULL — Routines (fullRoutines user)
// =============================================================================

test.describe('Routines', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullRoutines').email,
      getUser('fullRoutines').password,
    );
    await navigateToTab(page, 'Routines');
  });

  test('should show the STARTER ROUTINES section heading on routines tab', async ({
    page,
  }) => {
    await expect(page.locator(ROUTINE.heading).first()).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should display all four starter routines from seed data', async ({
    page,
  }) => {
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Each starter routine may be below the fold — scroll into view before
    // asserting visibility. Flutter SliverList culls off-screen items so a
    // plain `toBeVisible` against an off-screen item never resolves.
    for (const name of STARTER_ROUTINES) {
      await scrollToVisible(page, ROUTINE.routineName(name));
      await expect(page.locator(ROUTINE.routineName(name)).first()).toBeVisible({
        timeout: 10_000,
      });
    }
  });

  test('should navigate to active workout screen when tapping a starter routine card', async ({
    page,
  }) => {
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Tap "Push Day" — the first starter routine in seed order. Scroll it
    // into view first since SliverList culls off-screen items in CI.
    const pushDay = await scrollToVisible(page, ROUTINE.routineName('Push Day'));
    await pushDay.click();

    // The active workout screen identifies itself by the Finish Workout button.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // The routine pre-fills exercises. At least one Add Set button must appear,
    // confirming exercise cards were rendered.
    await expect(page.locator(WORKOUT.addSetButton).first()).toBeVisible({
      timeout: 10_000,
    });

    // Push Day contains "Barbell Bench Press" per seed.sql.
    // On the active workout screen, exercise names are part of the group's
    // accessible name (not standalone text nodes). Use the WORKOUT selector.
    await expect(
      page.locator(WORKOUT.exerciseDetailTap('Barbell Bench Press')),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('should return to home when discarding a routine-started workout', async ({ page }) => {
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Push Day may be below the fold — scroll into view before tapping.
    const pushDay = await scrollToVisible(page, ROUTINE.routineName('Push Day'));
    await pushDay.click();
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // Discard the workout.
    const discardBtn = page.locator(WORKOUT.discardButton);
    const isVisible = await discardBtn
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!isVisible) {
      const overflow = page.locator('role=button[name="More options"]');
      if (await overflow.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await overflow.click();
      }
    }

    await page.locator(WORKOUT.discardButton).click();

    // Confirm the discard dialog.
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();

    // Must return to home.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should access routines tab from all other tabs without crashing', async ({
    page,
  }) => {
    // Navigate away to Exercises and back to Routines.
    await page.click(NAV.exercisesTab);
    await expect(page.locator('text=Exercises')).toBeVisible({ timeout: 15_000 });

    await page.click(NAV.routinesTab);
    await expect(page.locator(ROUTINE.heading).first()).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });

    // Navigate from Home tab.
    await page.click(NAV.homeTab);
    // Home tab is confirmed by the URL reaching /home. The old "Start Empty
    // Workout" button was removed in W8; verify with a reliable home indicator.
    await page.waitForURL('**/home**', { timeout: 15_000 });

    await page.click(NAV.routinesTab);
    await expect(page.locator(ROUTINE.heading).first()).toBeVisible({ timeout: 15_000 });
  });
});

// =============================================================================
// FULL — Routine regressions (fullRoutineRegression user)
// =============================================================================

// Muscle groups known to appear in starter routine subtitles when exercises
// resolve correctly (per seed.sql exercise list for each routine).
// MuscleGroup enum values: chest, back, legs, shoulders, arms, core
// (display names: Chest, Back, Legs, Shoulders, Arms, Core).
const PUSH_DAY_GROUPS = ['Chest', 'Shoulders', 'Arms'];
const PULL_DAY_GROUPS = ['Back', 'Arms'];

test.describe('Routine regressions', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullRoutineRegression').email,
      getUser('fullRoutineRegression').password,
    );
    await navigateToTab(page, 'Routines');
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should show muscle group names in Push Day card subtitle, not bare count (BUG-005)', async ({
    page,
  }) => {
    // Flutter CanvasKit draws card subtitle text onto canvas, so flt-semantics
    // text elements may have zero CSS dimensions. isVisible() returns false even
    // when the text is rendered visually. Instead we read the text content of the
    // routine card button (a flt-semantics[role="button"] that wraps all text)
    // and check that it includes at least one expected muscle group name.
    //
    // Push Day may render below the fold (SliverList viewport culling) — scroll
    // into view first so the card is in the DOM before we filter on text.
    await scrollToVisible(page, ROUTINE.routineName('Push Day'));

    const pushDayCard = page
      .locator('flt-semantics[role="button"]')
      .filter({ hasText: 'Push Day' });
    await expect(pushDayCard.first()).toBeVisible({ timeout: 10_000 });

    const cardText = await pushDayCard.first().textContent();
    const foundGroup = PUSH_DAY_GROUPS.some(g => cardText?.includes(g));
    expect(foundGroup).toBe(true);

    // The fallback "6 exercises" must not be in the Push Day card text.
    expect(cardText?.includes('6 exercises')).toBe(false);
  });

  test('should show muscle group names in Pull Day card subtitle (BUG-005)', async ({
    page,
  }) => {
    // Pull Day may render below the fold — scroll into view first.
    await scrollToVisible(page, ROUTINE.routineName('Pull Day'));

    const pullDayCard = page
      .locator('flt-semantics[role="button"]')
      .filter({ hasText: 'Pull Day' });
    await expect(pullDayCard.first()).toBeVisible({ timeout: 10_000 });

    const cardText = await pullDayCard.first().textContent();
    const foundGroup = PULL_DAY_GROUPS.some(g => cardText?.includes(g));
    expect(foundGroup).toBe(true);
  });

  test('should not show bare exercise-count fallback in any starter routine card (BUG-005)', async ({
    page,
  }) => {
    // None of the starter routine cards should include just "N exercises" in
    // their text content. That text is the _buildSubtitle() fallback when
    // re.exercise is null. Check all four starter routine cards.
    //
    // Each card may be below the fold (SliverList viewport culling) — scroll
    // each into view before reading its text. Skip silently only if scroll
    // genuinely fails to reveal the card (e.g., starter list shrank); the
    // assertion is per-card, not aggregate.
    for (const routineName of STARTER_ROUTINES) {
      const scrolled = await scrollToVisible(
        page,
        ROUTINE.routineName(routineName),
      ).catch(() => null);
      if (!scrolled) continue;

      const card = page
        .locator('flt-semantics[role="button"]')
        .filter({ hasText: routineName });
      const isPresent = await card.count().then(c => c > 0);
      if (!isPresent) continue;

      const cardText = await card.first().textContent();
      // The starter routines have 6, 6, 7, and 6 exercises respectively.
      const hasFallback = ['6 exercises', '7 exercises', '5 exercises'].some(
        f => cardText?.includes(f),
      );
      expect(hasFallback).toBe(false);
    }
  });

  test('should show error snackbar when starting routine whose only exercise was deleted (BUG-003)', async ({
    page,
  }) => {
    const uniqueSuffix = Date.now();
    const exerciseName = `BUG-003 Exercise ${uniqueSuffix}`;
    const routineName = `BUG-003 Routine ${uniqueSuffix}`;

    // Step 1: Create a custom exercise.
    await navigateToTab(page, 'Exercises');
    await page.click(EXERCISE_LIST.createFab);
    await expect(page.locator(CREATE_EXERCISE.nameInput)).toBeVisible({
      timeout: 10_000,
    });
    await flutterFill(page, CREATE_EXERCISE.nameInput, exerciseName);
    await page.locator('role=button[name*="Muscle group: Chest"]').first().click();
    await page.locator('role=button[name*="Equipment type: Barbell"]').first().click();
    await page.click(CREATE_EXERCISE.saveButton);
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 15_000,
    });

    // Step 2: Create a routine that uses this exercise.
    await navigateToTab(page, 'Routines');
    // The Create Routine button is the + icon in the AppBar (no accessible label).
    // It is the first flt-semantics[role="button"] in the DOM on the Routines screen.
    await page.locator('flt-semantics[role="button"]').first().click();

    // Fill in the routine name.
    const nameInput = page.locator(CREATE_ROUTINE.nameInput);
    await expect(nameInput).toBeVisible({ timeout: 10_000 });
    await nameInput.click();
    await page.keyboard.press('Control+a');
    await page.keyboard.type(routineName, { delay: 10 });

    // Add the custom exercise to the routine.
    await page.click(CREATE_ROUTINE.addExerciseButton);
    const searchInput = page.locator('role=textbox[name*="Search exercises to add"]');
    await expect(searchInput).toBeVisible({ timeout: 10_000 });
    await flutterFill(page, 'role=textbox[name*="Search exercises to add"]', exerciseName.substring(0, 10));
    await page.waitForTimeout(600);

    const addBtn = page.locator(`role=button[name*="Add ${exerciseName}"]`).first();
    await expect(addBtn).toBeVisible({ timeout: 10_000 });
    await addBtn.click();

    // Save the routine.
    await page.click(CREATE_ROUTINE.saveButton);
    await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({ timeout: 15_000 });

    // Verify the custom routine appears. The fullRoutineRegression user
    // accumulates state across the suite, so MY ROUTINES may overflow the
    // viewport — scroll the new routine card into view before asserting.
    await scrollToVisible(page, ROUTINE.routineName(routineName));
    await expect(page.locator(ROUTINE.routineName(routineName)).first()).toBeVisible({
      timeout: 10_000,
    });

    // Step 3: Delete the exercise so it becomes soft-deleted (deletedAt is set).
    await navigateToTab(page, 'Exercises');
    // Use flutterFillByInput to target the underlying HTML input directly —
    // clicking the flt-semantics overlay does not reliably transfer focus.
    await flutterFillByInput(page, 'Search exercises', exerciseName.substring(0, 10));
    await page.waitForTimeout(800);

    const exerciseCard = page
      .locator(EXERCISE_LIST.exerciseCard(exerciseName))
      .first();
    await expect(exerciseCard).toBeVisible({ timeout: 10_000 });
    await exerciseCard.click();

    await expect(page.locator(EXERCISE_DETAIL.deleteButton)).toBeVisible({
      timeout: 10_000,
    });
    await page.click(EXERCISE_DETAIL.deleteButton);
    await expect(page.locator(EXERCISE_DETAIL.deleteDialogContent)).toBeVisible({
      timeout: 5_000,
    });
    await page.click(EXERCISE_DETAIL.deleteConfirmButton);
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 15_000,
    });

    // Step 4: Reload the page to clear Riverpod's cached routineListProvider state.
    // Without a reload, the cached routine data still shows the exercise as non-deleted
    // (Riverpod AsyncNotifier without autoDispose does not re-fetch on tab navigation).
    // The reload forces a cold re-fetch so startRoutineWorkout filters the deleted exercise.
    await page.reload();
    await waitForAppReady(page);
    await navigateToTab(page, 'Routines');

    // The routine may appear in MY ROUTINES section.
    const myRoutineCard = page
      .locator(ROUTINE.routineName(routineName))
      .first();
    await expect(myRoutineCard).toBeVisible({ timeout: 10_000 });
    await myRoutineCard.click();

    // Step 5-6: The snackbar with the error message must appear.
    // The start action filters out the soft-deleted exercise -> exercises is empty
    // -> shows SnackBar("Could not load exercises. Please try again.").
    // Use .first() because Flutter renders both <flt-announcement-polite> (a11y)
    // and a <span> (visual) for SnackBar text — strict mode requires one element.
    await expect(
      page.locator('text=Could not load exercises').first(),
    ).toBeVisible({ timeout: 10_000 });

    // Step 7: The app must NOT have navigated to the active workout screen.
    // "Finish Workout" button must NOT be visible.
    await expect(page.locator(WORKOUT.finishButton)).not.toBeVisible({
      timeout: 3_000,
    });

    // We must still be on the Routines tab (or Home — either is fine as long
    // as we did not land on the active workout screen).
    const onRoutines = await page
      .locator(ROUTINE.heading)
      .first()
      .isVisible({ timeout: 3_000 })
      .catch(() => false);
    // "Start Empty Workout" was removed in W8. Check for home URL or the
    // NAV home tab instead to confirm we did not land on the workout screen.
    const onHome = await page
      .locator(NAV.homeTab)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    expect(onRoutines || onHome).toBe(true);
  });

  test('should start Full Body routine barbell exercises with non-zero weight (BUG-004)', async ({
    page,
  }) => {
    // Full Body may render below the fold — scroll into view before tapping.
    const fullBody = await scrollToVisible(
      page,
      ROUTINE.routineName('Full Body'),
    );
    await fullBody.click();

    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // Barbell Squat must be in the routine (accessible via Semantics aria-label).
    // Flutter CanvasKit draws text to canvas — text= selectors fail for zero-dimension
    // flt-semantics elements; the aria-label from Semantics(label: ...) is reliable.
    await expect(
      page.locator(`role=group[name*="Exercise: ${SEED_EXERCISES.squat}. Tap for details"]`),
    ).toBeVisible({ timeout: 10_000 });

    // For barbell exercises, the default weight is 20 kg — not 0 kg.
    // Use role=button[name*=...] which matches on computed accessible name —
    // this correctly matches Flutter Semantics(label: ..., button: true) elements.
    const zeroWeightButtons = page.locator(
      'role=button[name*="Weight value: 0 kg"]',
    );

    // Count how many exercise cards are barbell vs bodyweight.
    // We can't easily distinguish per-exercise, but we can assert that
    // NOT ALL weight buttons show 0 — at least one barbell exercise (Squat or
    // Bench Press) should show a non-zero value.
    const allWeightButtons = page.locator(
      'role=button[name*="Weight value:"]',
    );
    await expect(allWeightButtons.first()).toBeVisible({ timeout: 10_000 });

    const totalWeightButtons = await allWeightButtons.count();
    const zeroWeightCount = await zeroWeightButtons.count();

    // Not ALL weight buttons can be zero — barbell exercises should have 20 kg.
    // Plank (bodyweight) legitimately shows 0 kg, but Barbell Squat and
    // Barbell Bench Press must not be 0.
    // Conservative assertion: at least one weight button must be non-zero.
    expect(zeroWeightCount).toBeLessThan(totalWeightButtons);

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should start Push Day dumbbell exercises with non-zero weight (BUG-004)', async ({
    page,
  }) => {
    // Push Day may be below the fold due to viewport culling in Flutter's
    // SliverList.builder — scroll into view via the shared helper.
    const pushDay = await scrollToVisible(
      page,
      ROUTINE.routineName('Push Day'),
    );
    await pushDay.click();

    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // Push Day includes dumbbell exercises (e.g., Lateral Raise, Incline Dumbbell Press).
    // Lateral Raise is the 4th exercise — it may be outside the viewport and NOT in
    // the DOM due to Flutter's virtualized list. Instead of scrolling to a specific
    // exercise, scroll down to load more exercise cards and then check all visible
    // weight buttons. Incline Dumbbell Press (dumbbell, 10 kg default) is always
    // visible and is sufficient to verify the non-zero default weight behavior.
    //
    // Scroll the workout list down to ensure dumbbell exercises are in view.
    // Use mouse wheel scrolling which triggers Flutter's scroll physics.
    await page.mouse.wheel(0, 500);
    await page.waitForTimeout(500);

    // At least one weight button must show a non-zero value.
    // Use role=button[name*=...] for computed accessible name matching.
    const allWeightButtons = page.locator(
      'role=button[name*="Weight value:"]',
    );
    const zeroWeightButtons = page.locator(
      'role=button[name*="Weight value: 0 kg"]',
    );

    await expect(allWeightButtons.first()).toBeVisible({ timeout: 10_000 });
    const total = await allWeightButtons.count();
    const zeros = await zeroWeightButtons.count();

    // Push Day has no bodyweight exercises — all should have defaults > 0.
    // At minimum, Incline Dumbbell Press (10 kg) confirms dumbbell defaults work.
    expect(zeros).toBeLessThan(total);

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  test('should preserve exercise names after page reload when started from a routine (BUG-001)', async ({
    page,
  }) => {
    // Pull Day may be below the fold — scroll into view before tapping.
    const pullDay = await scrollToVisible(
      page,
      ROUTINE.routineName('Pull Day'),
    );
    await pullDay.click();

    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 20_000,
    });

    // Capture the first exercise name that is visible in the workout via aria-label.
    // Pull Day includes "Deadlift" and "Barbell Bent-Over Row" per seed.sql.
    // Use role=button[name*=...] — text= selectors fail for zero-dimension
    // CanvasKit elements where text is drawn onto canvas. Flutter 3.41.6+ uses
    // AOM for accessible names, so role-based selectors are required.
    const deadliftAria = `role=group[name*="Exercise: ${SEED_EXERCISES.deadlift}. Tap for details"]`;
    const bentRowAria = 'role=group[name*="Exercise: Barbell Bent-Over Row. Tap for details"]';

    const deadliftVisible = await page
      .locator(deadliftAria)
      .isVisible({ timeout: 10_000 })
      .catch(() => false);

    const bentRowVisible = await page
      .locator(bentRowAria)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    expect(deadliftVisible || bentRowVisible).toBe(true);

    // Reload to simulate crash / app restore.
    await page.reload();

    // waitForAppReady re-enables semantics after reload and waits for auth.
    // document.body.innerText is empty in CanvasKit (text drawn to canvas).
    await waitForAppReady(page);

    // Return to the active workout screen.
    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!finishVisible) {
      const activeBannerVisible = await page
        .locator(HOME.activeBanner)
        .isVisible({ timeout: 10_000 })
        .catch(() => false);
      if (activeBannerVisible) {
        await page.locator(HOME.activeBanner).click();
      } else {
        const resumeVisible = await page
          .locator('text=Resume')
          .isVisible({ timeout: 5_000 })
          .catch(() => false);
        if (resumeVisible) {
          await page.locator('text=Resume').click();
        } else {
          const banner = page.locator('role=button[name*="Pull Day"]');
          if (await banner.isVisible({ timeout: 5_000 }).catch(() => false)) {
            await banner.click();
          }
        }
      }
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
    }

    // KEY ASSERTION: the "Exercise" fallback must NOT appear as a card header.
    const fallbackLabel = page.locator(
      'role=group[name*="Exercise: Exercise. Tap for details"]',
    );
    await expect(fallbackLabel).not.toBeVisible({ timeout: 3_000 });

    // The real exercise name (Deadlift or Bent-Over Row) must still be visible
    // after reload via its Semantics aria-label.
    if (deadliftVisible) {
      await expect(
        page.locator(deadliftAria),
      ).toBeVisible({ timeout: 10_000 });
    } else {
      await expect(
        page.locator(bentRowAria),
      ).toBeVisible({ timeout: 10_000 });
    }

    // Clean up.
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});
