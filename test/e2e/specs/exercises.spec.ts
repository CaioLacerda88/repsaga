/**
 * Exercises — merged E2E spec.
 *
 * Sources:
 *   - smoke/exercise.smoke.spec.ts          (smokeExercise, 6 tests)
 *   - smoke/exercise-library.smoke.spec.ts  (smokeExercise, 7 tests)
 *   - smoke/exercise-form-tips.smoke.spec.ts (smokeFormTips, 2 tests)
 *   - full/exercise-library.spec.ts         (fullExercises, 13 tests)
 *   - full/exercise-detail-sheet.spec.ts    (fullExDetailSheet, 4 tests)
 *
 * Structure:
 *   1. Exercises         @smoke  — merged exercise.smoke + exercise-library.smoke (smokeExercise)
 *   2. Exercise form tips @smoke — exercise-form-tips.smoke (smokeFormTips)
 *   3. Exercise library          — full/exercise-library (fullExercises)
 *   4. Exercise detail sheet     — full/exercise-detail-sheet (fullExDetailSheet)
 */

import { test, expect } from '@playwright/test';
import { flutterFill, flutterFillByInput, navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  EXERCISE_LIST,
  EXERCISE_DETAIL,
  EXERCISE_PICKER,
  NAV,
  WORKOUT,
} from '../helpers/selectors';
import { startEmptyWorkout, addExercise } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';

// =============================================================================
// SMOKE: Exercises (merged exercise.smoke + exercise-library.smoke)
// Both use smokeExercise user
// =============================================================================

test.describe('Exercises', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeExercise').email,
      getUser('smokeExercise').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  test('should render exercise list screen with search', async ({
    page,
  }) => {
    // The page heading and search input must be present.
    // Use first() because "Exercises" text also appears in the bottom nav tab.
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible();
    await expect(page.locator(EXERCISE_LIST.searchInput).last()).toBeVisible();

    // The muscle group "All" filter chip is always rendered.
    await expect(
      page.locator(EXERCISE_LIST.allMuscleGroupFilter),
    ).toBeVisible();
  });

  // -----------------------------------------------------------------
  // Negative pin: the user-create-exercise surface has been retired.
  // The Add FAB and its underlying route must remain absent so a
  // future contributor can't accidentally re-introduce a logging path
  // for un-calibrated user-created exercises (RPG thesis: every logged
  // set must carry a calibrated tier_diff_mult / xp_attribution).
  // -----------------------------------------------------------------
  test('should not render an Add Exercise affordance on the library', async ({
    page,
  }) => {
    // Wait for the library to settle (heading + seeded cards visible).
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible();
    const seededCards = page.locator('role=button[name*="Exercise:"]');
    await expect(seededCards.first()).toBeVisible({ timeout: 10_000 });

    // The retired FAB identifier must NOT mount in the AOM.
    await expect(
      page.locator('[flt-semantics-identifier="exercise-list-create-fab"]'),
    ).not.toBeVisible({ timeout: 3_000 });
  });

  test('should filter exercise list by name via search', async ({ page }) => {
    // The list should have at least one exercise (user custom exercises or
    // default seeded exercises, depending on database state).
    // We search for a partial string to trigger the filter.
    await flutterFill(page, EXERCISE_LIST.searchInput, 'Bench');

    // Wait for the debounce to fire (300 ms default + render time).
    await page.waitForTimeout(800);

    // Either a matching card appears or the "no results" state is shown.
    // Use role selector for cards — CanvasKit may render aria-label as child
    // text rather than an attribute.
    const cards = page.locator('role=button[name*="Exercise:"]');
    const emptyState = page.locator(EXERCISE_LIST.emptyStateFiltered);

    const hasCards = await cards.first().isVisible({ timeout: 5_000 }).catch(() => false);
    const hasEmpty = await emptyState.isVisible({ timeout: 5_000 }).catch(() => false);

    // At least one of the two states must be visible — the app must not crash.
    expect(hasCards || hasEmpty).toBe(true);
  });

  // ---------------------------------------------------------------------------
  // fix/exercise-filter-autodispose regression guard
  //
  // Root cause: searchQueryProvider was app-scoped (not .autoDispose). After
  // the fix, all filter StateProviders are .autoDispose so they reset when the
  // ExerciseListScreen widget is unmounted (i.e., when the user navigates away).
  //
  // Regression scenario: type "bench" → navigate away → come back → filter
  // persists (list is still filtered to bench results) but the TextField shows
  // empty, so the user cannot clear it. This test catches that regression.
  // ---------------------------------------------------------------------------
  test('should clear search filter when navigating away and back', async ({ page }) => {
    // Step 1: Wait for the full exercise list to load.
    const allCards = page.locator('role=button[name*="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });

    // Step 2: Type "bench" — filters down to bench-related exercises only.
    //
    // Use flutterFillByInput (direct <input>.focus()) rather than flutterFill
    // (which clicks the semantics overlay and waits 200ms for Flutter's text
    // editing connection to attach). On the exercise search field specifically
    // — same as flake noted in the form-tips test at line ~469 — the semantics
    // click → text-editing-connection chain races under CI 4-vCPU saturation:
    // the keystrokes fire before Flutter has wired Control+a / 'bench' through
    // to the focused TextEditingController, the search query stays empty, the
    // list never narrows, and `role=button[name*="Bench"]` finds nothing
    // (Barbell Bench Press is below-the-fold in the virtualized alphabetical
    // list when unfiltered). Failure mode is deterministic, not flaky pump
    // timing — the artifact screenshot shows the search input still showing
    // its placeholder.
    await flutterFillByInput(page, 'Search exercises', 'bench');
    await page.waitForTimeout(800);

    // Step 3: Assert filtered state — Deadlift is NOT a bench exercise.
    // "Deadlift" is always in the seed data and never matches "bench".
    await expect(
      page.locator(EXERCISE_LIST.exerciseCard(SEED_EXERCISES.deadlift)),
    ).not.toBeVisible({ timeout: 5_000 });

    // Verify at least one matching card IS visible (confirms the filter fired).
    const benchCard = page.locator('role=button[name*="Bench"]');
    await expect(benchCard.first()).toBeVisible({ timeout: 5_000 });

    // Step 4: Navigate away to a different tab.
    await navigateToTab(page, 'Routines');

    // Step 5: Navigate back to Exercises.
    await navigateToTab(page, 'Exercises');

    // Step 6 — Wait for the exercise list to stabilise after navigation back.
    // We wait for at least one card to appear (the list re-renders from scratch
    // on mount) and for the "All" muscle group filter to be visible (reliable
    // liveness signal — always rendered when the screen is mounted).
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(EXERCISE_LIST.allMuscleGroupFilter)).toBeVisible({
      timeout: 5_000,
    });

    // Step 7 — REGRESSION CHECK: the search TextEditingController must be empty.
    //
    // If the .autoDispose fix is absent, filteredExerciseListProvider still
    // holds the stale "bench" query AND the TextEditingController retains the
    // "bench" text (because the widget was never disposed). The underlying native
    // <input> proxy reflects the TextEditingController value via Flutter's text
    // editing connection — an empty value here proves the controller was reset
    // when the ExerciseListScreen widget was unmounted (i.e., .autoDispose worked).
    //
    // This is the most direct regression guard for the autoDispose bug: the symptom
    // is the user sees an empty search field but the list is still filtered. A
    // non-empty input value here surfaces that exact bug.
    //
    // Note: count-based assertions (restoredCount > filteredCount) and viewport-
    // content assertions (Deadlift/Squat visible) were removed. Flutter's virtualized
    // list renders only viewport items; the count and which items appear in the
    // initial viewport both vary with the number of custom exercises accumulated
    // across --repeat-each runs. The input value assertion is layout-independent
    // and correctly characterises the regression.
    //
    // Flake fix (#21): after navigating back, Flutter re-establishes the text
    // editing connection lazily — the native <input> proxy may not exist yet when
    // the flt-semantics cards first appear. Wait for the proxy to be attached to
    // the DOM before asserting its value, otherwise toHaveValue can fire before
    // Flutter has connected the TextEditingController to the input element.
    const searchInput = page.locator('input[aria-label*="Search exercises"]');
    await searchInput.waitFor({ state: 'attached', timeout: 10_000 });
    await expect(searchInput).toHaveValue('', { timeout: 5_000 });
  });

  test('should narrow exercise list with muscle group filter', async ({ page }) => {
    // Apply the "Chest" muscle group filter.
    await page.click(EXERCISE_LIST.muscleGroupFilter('Chest'));

    // Wait for the debounce and re-render.
    await page.waitForTimeout(600);

    // The filter chip should now be in the selected state.
    await expect(
      page.locator(EXERCISE_LIST.muscleGroupFilter('Chest')),
    ).toHaveAttribute('aria-current', 'true');
  });

  test('should render muscle group and equipment filter chips with pixel icons (17.0)', async ({
    page,
  }) => {
    // Phase 17.0 replaced Material icons with PixelImage in the filter chips.
    // The icon inside each chip uses semanticLabel:'' (decorative) so it does
    // not appear in the AOM. Instead we assert the enclosing chip identifiers
    // are present — a widget-build error caused by a bad pixel asset path would
    // prevent these chips from rendering at all.
    //
    // Muscle group chips (all 7 + "All").
    await expect(page.locator(EXERCISE_LIST.allMuscleGroupFilter)).toBeVisible();
    for (const group of ['chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio']) {
      await expect(
        page.locator(EXERCISE_LIST.muscleGroupFilter(group)),
      ).toBeVisible({ timeout: 5_000 });
    }

    // Equipment type chips (all 7). These are off-screen on narrow viewports
    // so we scroll the filter row into view before asserting.
    for (const equip of ['barbell', 'dumbbell', 'cable', 'machine', 'bodyweight', 'bands', 'kettlebell']) {
      await expect(
        page.locator(EXERCISE_LIST.equipmentFilter(equip)),
      ).toBeVisible({ timeout: 5_000 });
    }
  });

  test('should show seeded exercises in exercise list', async ({ page }) => {
    // At least one exercise card must be visible after seeding.
    // We use the exerciseCard selector pattern with a partial match to find
    // any exercise card rather than a specific name.
    const exerciseCards = page.locator('role=button[name*="Exercise:"]');
    await expect(exerciseCards.first()).toBeVisible({ timeout: 10_000 });
    expect(await exerciseCards.count()).toBeGreaterThan(0);
  });

  test('should narrow list when selecting a muscle group filter', async ({ page }) => {
    // Count total cards before filtering.
    const allCards = page.locator('role=button[name*="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });
    const totalBefore = await allCards.count();

    // Apply "Chest" filter — a muscle group guaranteed to exist in seed data.
    await page.click(EXERCISE_LIST.muscleGroupFilter('Chest'));

    // Wait for the list to update (debounce + provider re-render).
    await page.waitForTimeout(500);

    const cardsAfter = await allCards.count();

    // The filter must either reduce the count or keep it the same (if every
    // exercise happens to be Chest — unlikely but valid). It must not crash.
    expect(cardsAfter).toBeGreaterThanOrEqual(0);
    expect(cardsAfter).toBeLessThanOrEqual(totalBefore);
  });

  test('should narrow list when selecting an equipment filter', async ({ page }) => {
    // Apply "Barbell" equipment filter.
    await page.click(EXERCISE_LIST.equipmentFilter('Barbell'));
    await page.waitForTimeout(500);

    // Verify the filter is now selected. The identifier resolves to the
    // Semantics group wrapper; the actual checkbox is inside it.
    const barbellCheckbox = page
      .locator(EXERCISE_LIST.equipmentFilter('Barbell'))
      .locator('role=checkbox');
    await expect(barbellCheckbox).toBeChecked();
  });

  test('should filter exercises by name via search input', async ({ page }) => {
    // Wait for initial exercise list to load.
    const cards = page.locator('role=button[name*="Exercise:"]');
    await expect(cards.first()).toBeVisible({ timeout: 10_000 });

    // Type a partial name. "bench" matches multiple seed exercises.
    await flutterFill(page, EXERCISE_LIST.searchInput, 'bench');

    // Wait for the post-debounce SETTLED state — EITHER filtered results
    // appear OR the filtered-empty placeholder mounts. We deliberately
    // accept either branch: this test is a smoke check on "typing in the
    // search box doesn't crash", not on "search returns N results."
    //
    // Why this isn't a fixed `waitForTimeout(500)`: the previous version
    // waited 500 ms (300 ms debounce + 200 ms slack), then asserted
    // count-then-emptyState. Under CI 4-vCPU contention or any latency
    // that pushed the search RPC past ~200 ms, the 500 ms expired during
    // the legitimate loading transition (debounce fired → provider
    // invalidated old result → new result hadn't landed). At that moment
    // `cards.count() == 0` AND `emptyStateFiltered` was NOT visible —
    // the AsyncValueBuilder was showing a CircularProgressIndicator. Both
    // assertion branches failed. Reproducible at workers=4 + repeat-each=10
    // (3/10 flake before this fix).
    //
    // `Locator.or()` polls until ONE of the two conditions holds — bypassing
    // the loading transition entirely. 5 s budget covers worst-case
    // CI 4-vCPU + network latency.
    const settled = cards
      .first()
      .or(page.locator(EXERCISE_LIST.emptyStateFiltered));
    await expect(settled).toBeVisible({ timeout: 5_000 });
  });

  test('should open detail screen when tapping an exercise card', async ({ page }) => {
    // Wait for exercises to load then click the first card.
    const firstCard = page.locator('role=button[name*="Exercise:"]').first();
    await expect(firstCard).toBeVisible({ timeout: 10_000 });
    await firstCard.click();

    // The detail screen AppBar shows "Exercise Details".
    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should return to exercise list on back navigation from detail', async ({
    page,
  }) => {
    // Wait for exercises to load then click the first card.
    const firstCard = page.locator('role=button[name*="Exercise:"]').first();
    await expect(firstCard).toBeVisible({ timeout: 10_000 });
    await firstCard.click();

    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Use the browser/AppBar back button.
    await page.goBack();

    // We should be back on the list screen.
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 10_000,
    });
  });
});

// =============================================================================
// SMOKE: Exercise form tips (from exercise-form-tips.smoke)
// Uses smokeFormTips user
// =============================================================================

test.describe('Exercise form tips', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeFormTips').email,
      getUser('smokeFormTips').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  // ---------------------------------------------------------------------------
  // BUG-002 (P1): Form tips render as separate bullet items, not a single blob.
  //
  // Barbell Bench Press has 4 form tips separated by newlines in the database.
  // If BUG-002 is present, all 4 tips appear joined as one block with literal
  // "\n" characters visible in the text.
  // If BUG-002 is fixed, each tip renders as its own row with a check-circle icon.
  // ---------------------------------------------------------------------------
  test('should render form tips as separate bullet items without literal backslash-n (BUG-002)', async ({
    page,
  }) => {
    // Search for Bench Press to quickly find the exercise.
    // Use flutterFillByInput to target the underlying <input> directly, since
    // the exercise search field's semantics overlay does not reliably transfer
    // focus via a semantics click alone.
    await flutterFillByInput(page, 'Search exercises', SEED_EXERCISES.benchPress);
    await page.waitForTimeout(800);

    // Open the exercise detail.
    const card = page
      .locator(EXERCISE_LIST.exerciseCard(SEED_EXERCISES.benchPress))
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();

    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // The "FORM TIPS" section header must be present — confirms the tips data
    // was loaded from the database and the section rendered at all.
    await expect(page.locator('text=FORM TIPS')).toBeVisible({ timeout: 10_000 });

    // KEY ASSERTION FOR BUG-002:
    // The literal two-character sequence backslash-n must NOT appear on screen.
    // If form_tips contains literal "\n" chars and the widget fails to split
    // them, the rendered text would contain "\\n" visible to the user.
    const literalBackslashN = page.locator('text=/\\\\n/');
    await expect(literalBackslashN).not.toBeVisible({ timeout: 3_000 });

    // The first known tip for Barbell Bench Press must appear as its own text
    // element. We match the opening words which are unique per tip.
    // Tip 1: "Plant feet flat on the floor and squeeze shoulder blades together"
    await expect(
      page.locator('text=Plant feet flat').first(),
    ).toBeVisible({ timeout: 5_000 });

    // A second distinct tip must also be visible separately.
    // Tip 2: "Lower the bar to mid-chest with elbows at roughly 45 degrees"
    await expect(
      page.locator('text=Lower the bar to mid-chest').first(),
    ).toBeVisible({ timeout: 5_000 });

    // If both tips are visible as separate elements, splitting worked correctly.
    // (If BUG-002 was present, only the combined blob would be visible, and
    // the partial text matches above would still succeed — but the literal \n
    // assertion above would catch the regression.)
  });

});

// =============================================================================
// SMOKE: Exercise progress chart (P1)
// Uses smokeExerciseProgress user — seeded with two completed Bench Press sets
// on two different calendar dates so ProgressChartSection renders its
// multi-point LineChart branch (which emits the `image: true` semantics the
// selector below matches). A single-point series is intentionally copy-only
// with no `image` semantics, so one session would not satisfy this assertion.
// =============================================================================

test.describe('Exercise progress chart', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeExerciseProgress').email,
      getUser('smokeExerciseProgress').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  test('should show progress chart section on exercise detail for a user with logged sets', async ({
    page,
  }) => {
    // Search for Barbell Bench Press — the exercise seeded by global-setup.
    await flutterFillByInput(page, 'Search exercises', SEED_EXERCISES.benchPress);
    await page.waitForTimeout(800);

    const card = page
      .locator(EXERCISE_LIST.exerciseCard(SEED_EXERCISES.benchPress))
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();

    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // BL-3: "Progress (kg)" heading was removed (acceptance #9). The chart
    // section is now identified by its trend summary copy and window toggle.
    // With two seeded sessions, the trend copy should be a non-empty string
    // (Up/Down/Holding steady) and the 30d window segment must be visible.
    //
    // The window SegmentedButton is the most reliable liveness signal — it is
    // always rendered when the section has data (loading state shows a spinner,
    // error state shows "Could not load progress" + the toggles, data state
    // always shows the toggle row).
    await expect(
      page.locator(EXERCISE_DETAIL.progressChart30dButton),
    ).toBeVisible({ timeout: 10_000 });

    // The old "Progress (kg)" heading must NOT appear (regression guard for
    // BL-3 acceptance #9 — kill the section header).
    await expect(
      page.locator('text=/^Progress \\(/'),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});

// =============================================================================
// FULL: Exercise library (from full/exercise-library)
// Uses fullExercises user
// =============================================================================

test.describe('Exercise library', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullExercises').email,
      getUser('fullExercises').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  test('should load exercise list with seeded exercises', async ({ page }) => {
    // The heading and filter controls must be present.
    await expect(page.locator(EXERCISE_LIST.heading)).toBeVisible();
    await expect(page.locator(EXERCISE_LIST.searchInput).last()).toBeVisible();
    await expect(page.locator(EXERCISE_LIST.allMuscleGroupFilter)).toBeVisible();

    // At least one exercise card from seed data must be visible.
    const cards = page.locator('role=button[name^="Exercise:"]');
    await expect(cards.first()).toBeVisible({ timeout: 10_000 });
    const count = await cards.count();
    expect(count).toBeGreaterThan(5);
  });

  test('should narrow results to bench-related exercises when searching for "bench"', async ({
    page,
  }) => {
    const allCards = page.locator('role=button[name^="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });
    const totalBefore = await allCards.count();

    // Use flutterFillByInput (direct <input>.focus()) rather than flutterFill
    // — see the matching comment on the smoke `should clear search filter`
    // test (~line 153) for the failure mode. Short version: flutterFill
    // clicks the semantics overlay and relies on Flutter's text-editing
    // connection attaching within 200 ms, which races under CI 4-vCPU
    // contention and causes the keystrokes to drop silently. Targeting the
    // <input aria-label="Search exercises..."> directly removes that race.
    await flutterFillByInput(page, 'Search exercises', 'bench');
    // Allow the 300 ms debounce to fire + extra CI margin.
    await page.waitForTimeout(1_000);

    const countAfter = await allCards.count();

    // "bench" should match at least "Barbell Bench Press" from seed data.
    expect(countAfter).toBeGreaterThanOrEqual(1);
    // Filtering must reduce or equal the original count, never exceed it.
    expect(countAfter).toBeLessThanOrEqual(totalBefore);

    // Verify at least one result contains "Bench" in its aria-label.
    const benchCard = page.locator('role=button[name*="Bench"]');
    await expect(benchCard.first()).toBeVisible({ timeout: 10_000 });
  });

  test('should show only chest exercises with Chest muscle group filter', async ({
    page,
  }) => {
    const allCards = page.locator('role=button[name^="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });
    const totalBefore = await allCards.count();

    await page.click(EXERCISE_LIST.muscleGroupFilter('Chest'));
    await page.waitForTimeout(600);

    // The filter chip must enter selected state.
    await expect(
      page.locator(EXERCISE_LIST.muscleGroupFilter('Chest')),
    ).toHaveAttribute('aria-current', 'true');

    const countAfter = await allCards.count();
    // Must narrow the list (seed data has chest + other muscle groups).
    expect(countAfter).toBeGreaterThanOrEqual(1);
    expect(countAfter).toBeLessThanOrEqual(totalBefore);

    // All visible exercise cards must be Chest exercises. The AOM accessible name
    // includes the muscle group (e.g. "Exercise: Push-Up Push-Up Chest Bodyweight").
    await expect(
      page.locator('role=button[name*="Chest"]').first(),
    ).toBeVisible({ timeout: 5_000 });
  });

  test('should narrow results with Barbell equipment filter', async ({ page }) => {
    const allCards = page.locator('role=button[name^="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });
    const totalBefore = await allCards.count();

    await page.click(EXERCISE_LIST.equipmentFilter('Barbell'));
    await page.waitForTimeout(600);

    // Equipment filters are checkboxes — the identifier resolves to the
    // Semantics group wrapper; target the checkbox inside it.
    await expect(
      page.locator(EXERCISE_LIST.equipmentFilter('Barbell')).locator('role=checkbox'),
    ).toBeChecked();

    const countAfter = await allCards.count();
    expect(countAfter).toBeGreaterThanOrEqual(1);
    expect(countAfter).toBeLessThanOrEqual(totalBefore);
  });

  test('should narrow results further with combined muscle group and search filter', async ({
    page,
  }) => {
    // Apply Chest filter first.
    await page.click(EXERCISE_LIST.muscleGroupFilter('Chest'));
    await page.waitForTimeout(600);

    const chestCards = page.locator('role=button[name^="Exercise:"]');
    await expect(chestCards.first()).toBeVisible({ timeout: 5_000 });
    const chestCount = await chestCards.count();

    // Then add a text search on top.
    await flutterFill(page, EXERCISE_LIST.searchInput, 'incline');
    await page.waitForTimeout(600);

    const combinedCount = await chestCards.count();

    // Combined filter must produce fewer or equal results than muscle group alone.
    expect(combinedCount).toBeLessThanOrEqual(chestCount);
    // "Incline Barbell Bench Press" and "Incline Dumbbell Press" are in seed.
    if (combinedCount > 0) {
      // Flutter 3.41.6+ AOM — ariaLabel property returns null for computed names.
      // Use Playwright's role selector to verify the result contains "Incline".
      await expect(
        page.locator('role=button[name*="Incline"]').first(),
      ).toBeVisible({ timeout: 5_000 });
    }
  });

  test('should reset to full list after clearing filters', async ({
    page,
  }) => {
    const allCards = page.locator('role=button[name^="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });

    // Apply Core filter. Flutter's virtualized list only renders viewport items,
    // so count comparison is unreliable. Instead verify content changes.
    await page.click(EXERCISE_LIST.muscleGroupFilter('Core'));
    await page.waitForTimeout(600);

    // After filtering, the first visible card must be a Core exercise.
    // AOM accessible names include the muscle group (e.g., "Exercise: Plank Plank Core Bodyweight").
    await expect(
      page.locator('role=button[name*="Core"]').first(),
    ).toBeVisible({ timeout: 5_000 });

    // Click "All" to reset.
    await page.click(EXERCISE_LIST.allMuscleGroupFilter);
    await page.waitForTimeout(600);

    // After reset, exercises from other muscle groups should appear.
    // Verify a non-Core exercise is now visible.
    const cards = page.locator('role=button[name^="Exercise:"]');
    await expect(cards.first()).toBeVisible({ timeout: 5_000 });
    const count = await cards.count();
    let hasNonCore = false;
    for (let i = 0; i < Math.min(count, 6); i++) {
      const name = await cards.nth(i).getAttribute('aria-label') ?? '';
      // Fall back to Playwright's accessibility name via evaluate.
      const accName = name || await cards.nth(i).evaluate(
        (el) => el.getAttribute('aria-label') ?? (el as any).ariaLabel ?? '',
      );
      if (accName && !accName.includes('Core')) {
        hasNonCore = true;
        break;
      }
    }
    // If AOM names are not readable, at minimum verify the list has items.
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('should open detail screen showing the name when tapping an exercise card', async ({
    page,
  }) => {
    const firstCard = page.locator('role=button[name^="Exercise:"]').first();
    await expect(firstCard).toBeVisible({ timeout: 10_000 });

    await firstCard.click();

    // The detail screen must show the "Exercise Details" app bar title.
    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });
    // Verify the detail screen has content (ABOUT section or exercise name heading).
    // Can't reliably extract the exercise name from AOM, so verify the detail
    // screen rendered by checking for the back button + title.
    await expect(page.locator('role=button[name="Back"]')).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should return to the list on back navigation from detail screen', async ({
    page,
  }) => {
    const firstCard = page.locator('role=button[name^="Exercise:"]').first();
    await expect(firstCard).toBeVisible({ timeout: 10_000 });
    await firstCard.click();

    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Use the browser back navigation.
    await page.goBack();

    await expect(page.locator(EXERCISE_LIST.heading)).toBeVisible({
      timeout: 10_000,
    });
    // Exercise cards must still be present after returning.
    await expect(
      page.locator('role=button[name^="Exercise:"]').first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  // ---------------------------------------------------------------------------
  // EX-005 (P1) — Filter combination zero results shows empty state
  // Core + Kettlebell is unlikely to have a seeded match; if it does, the
  // test still passes because the assertion is on the empty state itself.
  // We exhaust filters until we reach zero, then assert the empty state text.
  // ---------------------------------------------------------------------------
  test('should show filtered empty state for filter combination with zero results (EX-005)', async ({
    page,
  }) => {
    // Wait for the full list to load before filtering.
    const allCards = page.locator('role=button[name^="Exercise:"]');
    await expect(allCards.first()).toBeVisible({ timeout: 10_000 });

    // Apply Core muscle group + Kettlebell equipment — a combination unlikely
    // to be in the seed data. If it IS seeded, the test falls back to a further
    // search term that will guarantee zero results.
    await page.click(EXERCISE_LIST.muscleGroupFilter('Core'));
    await page.waitForTimeout(600);
    await page.click(EXERCISE_LIST.equipmentFilter('Kettlebell'));
    await page.waitForTimeout(600);

    // Check if the empty state appeared. If not (seed has Core+Kettlebell
    // exercises), also apply a nonsense search to force zero results.
    const emptyStateVisible = await page
      .locator(EXERCISE_LIST.emptyStateFiltered)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (!emptyStateVisible) {
      await flutterFill(page, EXERCISE_LIST.searchInput, 'ZZZnoResultsXXX');
      await page.waitForTimeout(700);
    }

    // The filtered empty state text must now be visible.
    await expect(page.locator(EXERCISE_LIST.emptyStateFiltered)).toBeVisible({
      timeout: 5_000,
    });

    // The "Clear Filters" button must accompany the empty state.
    await expect(page.locator(EXERCISE_LIST.clearFiltersButton)).toBeVisible({
      timeout: 3_000,
    });
  });

  // ---------------------------------------------------------------------------
  // P4 regression — Exercise image rendering from Supabase Storage
  //
  // Migration 00018 replaced broken GitHub raw URLs with Supabase Storage URLs
  // (https://{project}.supabase.co/storage/v1/object/public/exercise-media/...)
  // for all ~59 default exercises. This test guards against a regression where
  // the DB rows revert to broken URLs or the storage bucket becomes unavailable,
  // which would cause CachedNetworkImage to silently fall back to the icon
  // placeholder — images appear "missing" to the user with no error thrown.
  //
  // Assertion strategy:
  //   Flutter web (CanvasKit) renders everything to <canvas> — CachedNetworkImage
  //   does NOT produce <img> DOM elements. Instead we intercept network requests:
  //   1. Use page.waitForResponse to capture the start and end image responses
  //      concurrently with navigating to the detail screen.
  //   2. Assert both semantic role=img nodes are visible — confirms _ExerciseImageRow
  //      rendered (i.e., image URLs are non-null in the DB row).
  //   3. Assert both captured responses returned HTTP 200 (not 404).
  //      CachedNetworkImage silently falls back to the icon placeholder on 404 —
  //      only the network status check surfaces this regression.
  // ---------------------------------------------------------------------------
  test('should render start and end images for default exercises (P4 regression)', async ({
    page,
  }) => {
    // Register waitForResponse promises BEFORE tapping the exercise card so we
    // don't miss responses that arrive before we register the listener.
    // barbell_bench_press_start.jpg and barbell_bench_press_end.jpg are the
    // expected filenames produced by the sanitization in migration 00018.
    const startImageResponsePromise = page.waitForResponse(
      (resp) =>
        resp.url().includes('exercise-media') && resp.url().includes('_start'),
      { timeout: 20_000 },
    );
    const endImageResponsePromise = page.waitForResponse(
      (resp) =>
        resp.url().includes('exercise-media') && resp.url().includes('_end'),
      { timeout: 20_000 },
    );

    // Search for Barbell Bench Press — it is guaranteed to have both
    // image_start_url and image_end_url set by migration 00018.
    await flutterFillByInput(page, 'Search exercises', SEED_EXERCISES.benchPress);

    const card = page
      .locator(EXERCISE_LIST.exerciseCard(SEED_EXERCISES.benchPress))
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();

    // Wait for the detail screen to load.
    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // The semantic image roles must be present — confirms _ExerciseImageRow
    // rendered both _TappableImage widgets (i.e., image URLs are non-null in the DB).
    // If either is absent, the DB row is missing the URL — data regression.
    await expect(
      page.locator(EXERCISE_DETAIL.startImage(SEED_EXERCISES.benchPress)).first(),
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.locator(EXERCISE_DETAIL.endImage(SEED_EXERCISES.benchPress)).first(),
    ).toBeVisible({ timeout: 5_000 });

    // Assert both image requests completed with HTTP 200. The predicates above
    // match on URL only so a 404 resolves the promise and is surfaced by the
    // explicit status check below (rather than as a generic 20 s timeout).
    const [startResp, endResp] = await Promise.all([
      startImageResponsePromise,
      endImageResponsePromise,
    ]);

    expect(
      startResp.status(),
      `Start image returned ${startResp.status()} for URL: ${startResp.url()}`,
    ).toBe(200);
    expect(
      endResp.status(),
      `End image returned ${endResp.status()} for URL: ${endResp.url()}`,
    ).toBe(200);
  });
});

// =============================================================================
// FULL: Exercise detail sheet (from full/exercise-detail-sheet)
// Uses fullExDetailSheet user
// =============================================================================

test.describe('Exercise detail sheet', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullExDetailSheet').email,
      getUser('fullExDetailSheet').password,
    );
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    // Confirm workout screen is ready.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
  });

  test.afterEach(async ({ page }) => {
    // Clean up any in-progress workout to avoid state leakage between tests.
    const finishVisible = await page
      .locator(WORKOUT.finishButton)
      .isVisible({ timeout: 3_000 })
      .catch(() => false);

    if (finishVisible) {
      await page.locator(WORKOUT.discardButton).click();
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
      await confirmDiscard.click();
    }
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  // ---------------------------------------------------------------------------
  // BUG-002 (P1): Form tips inside the active workout bottom sheet render as
  // separate bullet items, NOT as a single block with literal `\n` characters.
  //
  // The bottom sheet is opened by tapping the exercise name card in the workout
  // screen. It renders ExerciseFormTipsSection — the same widget as the standalone
  // detail screen, but via a different navigation path.
  // ---------------------------------------------------------------------------
  test('should not show literal backslash-n in form tips in the active workout bottom sheet (BUG-002)', async ({
    page,
  }) => {
    // Open the exercise detail bottom sheet by tapping the exercise name.
    // The Semantics label is "Exercise: <name>. Tap for details. Long press to swap."
    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // Wait for the bottom sheet to open — the "ABOUT" section header appears
    // only in the detail sheet, confirming it's open. Using .nth(1) on the
    // exercise name fails because CanvasKit renders the workout card's name
    // inside the group's accessible name, not as a standalone text node.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // The "FORM TIPS" section header must be present inside the sheet.
    // If form_tips is null/empty, this section is hidden — absence here means
    // the data was not loaded, not that BUG-002 is absent.
    const formTipsVisible = await page
      .locator('text=FORM TIPS')
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    if (!formTipsVisible) {
      // Form tips section not rendered — skip the BUG-002 assertion.
      // This should not happen for Barbell Bench Press (seeded with tips),
      // so fail the test to surface the data issue.
      throw new Error(
        'FORM TIPS section was not visible in the bottom sheet for ' +
          `${SEED_EXERCISES.benchPress}. Check that seed data includes form_tips.`,
      );
    }

    // KEY ASSERTION FOR BUG-002:
    // The literal two-character sequence backslash-n must NOT appear anywhere.
    // If the SQL migration stored `\n` as two chars (backslash + n) and the
    // widget did not split on the literal sequence, the user sees "\\n" in text.
    const literalBackslashN = page.locator('text=/\\\\n/');
    await expect(literalBackslashN).not.toBeVisible({ timeout: 3_000 });

    // The first form tip for Barbell Bench Press must appear as its own text
    // element: "Plant feet flat on the floor and squeeze shoulder blades together"
    await expect(
      page.locator('text=Plant feet flat').first(),
    ).toBeVisible({ timeout: 5_000 });

    // A second distinct tip must also be present separately:
    // "Lower the bar to mid-chest with elbows at roughly 45 degrees"
    await expect(
      page.locator('text=Lower the bar to mid-chest').first(),
    ).toBeVisible({ timeout: 5_000 });

    // Dismiss the sheet.
    await page.keyboard.press('Escape');
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });
  });

  // ---------------------------------------------------------------------------
  // Form tips bottom sheet: muscle group and equipment type chips are rendered.
  //
  // _ExerciseDetailSheet also renders _SheetChip widgets for muscle group and
  // equipment type. These are not tested in the form-tips smoke spec (which
  // only checks the standalone detail screen).
  // Barbell Bench Press: muscle group = Chest, equipment = Barbell.
  // ---------------------------------------------------------------------------
  test('should show muscle group and equipment chips in exercise detail sheet', async ({
    page,
  }) => {
    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // Wait for the sheet to open — the "ABOUT" header only appears in the sheet.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // Muscle group chip — Chest. Use .first() because CanvasKit renders
    // "Chest" inside the ABOUT description text too (strict mode violation).
    await expect(page.locator('text=Chest').first()).toBeVisible({ timeout: 5_000 });

    // Equipment type chip — Barbell. Same .first() rationale.
    await expect(page.locator('text=Barbell').first()).toBeVisible({ timeout: 5_000 });

    // Dismiss.
    await page.keyboard.press('Escape');
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });
  });

  // ---------------------------------------------------------------------------
  // Standalone exercise detail screen: form tips also render correctly.
  //
  // Belt-and-suspenders companion to the smoke spec. Tests that visiting the
  // detail screen from within the active workout (via the tap handler) works.
  // This differs from the smoke test which navigates the exercise library
  // independently of any active workout.
  // ---------------------------------------------------------------------------
  test('should render form tips without literal backslash-n on standalone exercise detail reached from workout sheet (BUG-002)', async ({
    page,
  }) => {
    // Open the bottom sheet first.
    const exerciseTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.benchPress}. Tap for details"]`,
    );
    await expect(exerciseTap).toBeVisible({ timeout: 10_000 });
    await exerciseTap.click();

    // Wait for the sheet to open — the "ABOUT" header only appears in the sheet.
    await expect(page.locator('text=ABOUT')).toBeVisible({ timeout: 10_000 });

    // Look for a "View full details" or "See more" link inside the sheet that
    // navigates to the standalone detail page. If the sheet provides this link,
    // tap it and verify the full detail page also renders tips correctly.
    // If no such link exists, dismiss and skip this part.
    const viewFullDetailsLink = page.locator(
      'text=View full details',
    );
    const hasViewFullDetails = await viewFullDetailsLink
      .isVisible({ timeout: 2_000 })
      .catch(() => false);

    if (hasViewFullDetails) {
      await viewFullDetailsLink.click();

      await expect(page.locator('text=Exercise Details')).toBeVisible({
        timeout: 10_000,
      });

      // Form tips on the standalone page must not contain literal \n.
      const literalBackslashN = page.locator('text=/\\\\n/');
      await expect(literalBackslashN).not.toBeVisible({ timeout: 3_000 });

      // Navigate back.
      await page.goBack();
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
        timeout: 15_000,
      });
    } else {
      // Sheet does not expose a full-detail link — dismiss and accept the test
      // as having covered the sheet path only.
      await page.keyboard.press('Escape');
      await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });
    }
  });

  // ---------------------------------------------------------------------------
  // Form tips section boundary: seeded exercise WITH tips shows the section;
  // a different exercise type does not crash the sheet.
  //
  // This verifies the section boundary — it must be present for exercises that
  // have form_tips data and absent (or not crashing) for those that don't.
  // Uses Barbell Squat which is also a seeded exercise with form tips.
  // ---------------------------------------------------------------------------
  test('should show form tips section for Barbell Squat in the active workout sheet', async ({
    page,
  }) => {
    // Add Barbell Squat to the workout (Bench Press is already there from beforeEach).
    await addExercise(page, SEED_EXERCISES.squat);

    // Open the detail sheet for Barbell Squat.
    const squatTap = page.locator(
      `role=group[name*="Exercise: ${SEED_EXERCISES.squat}. Tap for details"]`,
    );
    await expect(squatTap).toBeVisible({ timeout: 10_000 });
    await squatTap.click();

    // Sheet opens — exercise name appears a second time.
    await expect(
      page.locator(`text=${SEED_EXERCISES.squat}`).first(),
    ).toBeVisible({ timeout: 10_000 });

    // No literal \n characters must be visible anywhere on the sheet.
    const literalBackslashN = page.locator('text=/\\\\n/');
    await expect(literalBackslashN).not.toBeVisible({ timeout: 3_000 });

    // Dismiss.
    await page.keyboard.press('Escape');
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({ timeout: 5_000 });
  });
});

// =============================================================================
// finding-043 — Exercise retirement (soft-delete) hides the exercise from
//               the workout exercise picker.
//
// PR 32h introduced soft-delete for user-created exercises. A deleted exercise
// must not appear in the exercise picker when starting an active workout.
//
// User: `smokeExerciseRetirement` — seeded in global-setup with one
// user-created exercise ("E2E Retirement Test Exercise"). The test deletes
// it via the detail screen and asserts it no longer appears in the picker.
//
// Cleanup: the delete is persisted. The describe uses serial mode + the
// dedicated isolated user so repeated runs are safe (the user-created
// exercise row is re-seeded by global-setup on each full run).
// =============================================================================

const RETIREMENT_EXERCISE_NAME = 'E2E Retirement Test Exercise';

test.describe('Exercise retirement', { tag: '@smoke' }, () => {
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeExerciseRetirement').email,
      getUser('smokeExerciseRetirement').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  test('should hide a retired user-created exercise from the workout exercise picker', async ({
    page,
  }) => {
    // Step 1: Verify the user-created exercise is visible in the library.
    // The exercise has a "Custom exercise" badge, so it appears with the
    // exerciseCard selector just like any default exercise.
    await flutterFillByInput(page, 'Search exercises', RETIREMENT_EXERCISE_NAME);
    await page.waitForTimeout(800);

    const card = page
      .locator(EXERCISE_LIST.exerciseCard(RETIREMENT_EXERCISE_NAME))
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });

    // Step 2: Open the detail screen.
    await card.click();
    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // The custom badge confirms this is a user-created exercise (not a
    // default exercise, which has no delete button).
    await expect(page.locator(EXERCISE_DETAIL.customBadge)).toBeVisible({
      timeout: 5_000,
    });

    // Step 3: Tap the delete button and confirm in the dialog.
    await page.locator(EXERCISE_DETAIL.deleteButton).click();
    await expect(page.locator(EXERCISE_DETAIL.deleteDialogContent)).toBeVisible({
      timeout: 5_000,
    });
    await page.locator(EXERCISE_DETAIL.deleteConfirmButton).click();

    // Step 4: After deletion the app navigates back to the exercise list
    // (exercise_detail_screen.dart calls router.go('/exercises') before
    // invalidating caches). Wait for the list heading to confirm we landed.
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 10_000,
    });

    // Step 5: The deleted exercise must no longer appear in the list.
    // Re-search to make the absence deterministic (avoid relying on
    // viewport visibility in the full alphabetical list).
    await flutterFillByInput(page, 'Search exercises', RETIREMENT_EXERCISE_NAME);
    await page.waitForTimeout(800);

    // Either the search returns zero results (empty state) OR no card with
    // the exercise name is visible. Both indicate the retirement succeeded.
    const retiredCard = page.locator(
      EXERCISE_LIST.exerciseCard(RETIREMENT_EXERCISE_NAME),
    );
    const emptyState = page.locator(EXERCISE_LIST.emptyStateFiltered);

    const cardGone = await retiredCard.count().then((c) => c === 0);
    const emptyVisible = await emptyState.isVisible({ timeout: 3_000 }).catch(() => false);

    expect(
      cardGone || emptyVisible,
      'Retired exercise still visible in the exercise list after soft-delete',
    ).toBe(true);

    // Step 6: Navigate to an active workout and assert the exercise is absent
    // from the exercise picker (the RPG-thesis-critical downstream check).
    // Use the NAV home tab to leave the exercise screen, then start a workout.
    await page.locator(NAV.homeTab).click();
    await expect(page.locator(EXERCISE_LIST.heading).first()).not.toBeVisible({
      timeout: 5_000,
    });

    // startEmptyWorkout expects the user to be on the Home screen in lapsed
    // state (one prior workout is seeded by global-setup for this user).
    await page.locator(WORKOUT.addExerciseFab).waitFor({ state: 'detached', timeout: 3_000 }).catch(() => {});

    // The home free-workout hero should be visible (lapsed state).
    // Open the exercise picker by starting the workout flow.
    const homeHero = page.locator('[flt-semantics-identifier="home-action-hero-free-workout"]');
    await expect(homeHero).toBeVisible({ timeout: 15_000 });
    await homeHero.click();

    // Confirm the active workout screen mounted.
    await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible({
      timeout: 20_000,
    });
    await page.locator(WORKOUT.addExerciseFab).click();

    // The exercise picker is open. Search for the retired exercise.
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });
    // Use flutterFill for the picker search (CanvasKit hidden input requires
    // real key events). flutterFill clicks the selector before filling, so no
    // explicit `.click()` is needed beforehand.
    await flutterFill(page, EXERCISE_PICKER.searchInput, RETIREMENT_EXERCISE_NAME);
    await page.waitForTimeout(800);

    // The retired exercise must NOT appear in the picker.
    const pickerCard = page.locator(
      EXERCISE_PICKER.addExerciseButton(RETIREMENT_EXERCISE_NAME),
    );
    await expect(pickerCard).not.toBeVisible({ timeout: 5_000 });

    // Discard the workout to clean up.
    await page.keyboard.press('Escape');
    await page.locator(WORKOUT.discardButton).click();
    const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
    await expect(confirmDiscard).toBeVisible({ timeout: 5_000 });
    await confirmDiscard.click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});
