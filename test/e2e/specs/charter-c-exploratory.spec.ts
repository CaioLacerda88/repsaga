/**
 * Charter C — "Reorder + add + remove juggling"
 * Device: BR-1 (Samsung Galaxy A14, 360×780, DPR 2.0)
 * Persona: Alex (beginner; rapid, sometimes-undecided actions)
 * Date: 2026-05-07
 *
 * Structured exploratory charter. Guard: EXPL_CHARTER_C=1 so CI never runs this.
 *
 * All probes share a single continuous session (one test block) so that
 * workout state accumulated in earlier probes is available to later ones.
 * Each probe is a named section within the test. The test is intentionally
 * not split into separate `test()` blocks because the probes are inherently
 * sequential and interdependent.
 *
 * Probes (per testplan §6 Charter C):
 *   P1 — Add 5 exercises; verify FAB/finish-bar/reorder-toggle appearances
 *   P2 — Swap exercise 3 via long-press → picker
 *   P3 — Remove exercise 2; renumbering correct?
 *   P4 — Reorder via up/down arrows; order updates immediately?
 *   P5 — Add same exercise twice (duplicate); second block appended?
 *   P6 — Long-press swap mid-rest-timer
 *   P7 — Remove all exercises; empty state reappears
 *   P8 — Add from empty-state CTA; flow returns to normal
 *   P9/P10 — Bodyweight ↔ weighted swap; weight column show/hide
 *   P11 — Finish button disabled/hidden states
 *   P12 — Provider re-key: remove + re-add same exercise; hint present?
 */

import { test, expect, Page, BrowserContext } from '@playwright/test';
import {
  WORKOUT,
  EXERCISE_PICKER,
  HOME,
  NAV,
  SET_ROW,
} from '../helpers/selectors';
import {
  flutterFill,
  flutterLongPress,
} from '../helpers/app';
import { login } from '../helpers/auth';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
} from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

// ---------------------------------------------------------------------------
// Guard: skip unless EXPL_CHARTER_C=1
// ---------------------------------------------------------------------------
const RUN = process.env['EXPL_CHARTER_C'] === '1';

/**
 * Add a BODYWEIGHT exercise to the active workout.
 * Like addExercise() but skips the "Weight value" check since bodyweight
 * exercises have no weight column. Waits for the Add Set button instead.
 */
async function addBodyweightExercise(page: Page, exerciseName: string): Promise<void> {
  await page.click(WORKOUT.addExerciseFab);

  await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({ timeout: 10_000 });
  await flutterFill(page, EXERCISE_PICKER.searchInput, exerciseName);

  const addButton = page.locator(EXERCISE_PICKER.addExerciseButton(exerciseName)).first();
  await expect(addButton).toBeVisible({ timeout: 10_000 });
  await addButton.click();

  await expect(page.locator(EXERCISE_PICKER.searchInput)).not.toBeVisible({ timeout: 10_000 });
  await expect(page.locator(WORKOUT.addSetButton).last()).toBeVisible({ timeout: 10_000 });
  await page.locator(WORKOUT.addSetButton).last().click();

  // For bodyweight: wait for reps value button (no weight button)
  await expect(page.locator('role=button[name*="Reps value"]').first()).toBeVisible({ timeout: 10_000 });
}

const VIEWPORT = { width: 360, height: 780 };
const SS_BASE =
  'C:/Users/caiol/Projects/repsaga/tasks/active-workout-findings/screenshots';

// ---------------------------------------------------------------------------
// Correct exercise names as they appear in the DB (verified from picker UI)
// ---------------------------------------------------------------------------
const EX = {
  pushUp: 'Push-Up',           // Bodyweight, Chest
  benchPress: 'Barbell Bench Press',  // Weighted, Chest
  squat: 'Barbell Squat',      // Weighted, Legs
  pullUp: 'Pull-Up',           // Bodyweight, Back
  overheadPress: 'Overhead Press',    // Weighted, Shoulders
  legPress: 'Leg Press',       // Weighted, Legs
  dumbbellCurl: 'Dumbbell Curl',      // Weighted, Arms
};

// ---------------------------------------------------------------------------
// Charter C — single continuous session test
// ---------------------------------------------------------------------------

test.describe('Charter C — Reorder + add + remove juggling — BR-1', () => {
  test.skip(!RUN, 'Set EXPL_CHARTER_C=1 to run');
  test.use({ viewport: VIEWPORT });

  let page: Page;
  let context: BrowserContext;
  const findings: string[] = [];

  function log(msg: string): void {
    console.log(`[charter-c] ${msg}`);
    findings.push(msg);
  }

  async function ss(label: string): Promise<void> {
    const path = `${SS_BASE}/charter-C-BR-1-${label}.png`;
    await page.screenshot({ path, fullPage: false }).catch((e) =>
      log(`[SS FAIL] ${label}: ${String(e.message)}`),
    );
    log(`[screenshot] charter-C-BR-1-${label}.png`);
  }

  async function aomSnap(prefix: string): Promise<void> {
    const labels: string[] = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('flt-semantics'))
        .map((el: Element) => {
          const label =
            (el as HTMLElement & { ariaLabel?: string }).ariaLabel ??
            el.getAttribute('aria-label') ??
            '';
          const id = el.getAttribute('flt-semantics-identifier') ?? '';
          const text = label || id ? `[${id}]${label.slice(0, 80)}` : '';
          return text;
        })
        .filter(Boolean)
        .slice(0, 50);
    });
    log(`AOM[${prefix}]: ${labels.join(' | ')}`);
  }

  async function countExercises(): Promise<number> {
    return page.locator('role=button[name*="Delete exercise"]').count().catch(() => 0);
  }

  async function exerciseNames(): Promise<string[]> {
    return page.evaluate(() => {
      return Array.from(document.querySelectorAll('flt-semantics'))
        .map((el: Element) => {
          const label =
            (el as HTMLElement & { ariaLabel?: string }).ariaLabel ?? '';
          return label;
        })
        .filter((l) => l.includes('Exercise:') && l.includes('Tap for details'))
        .map((l) => {
          const match = l.match(/Exercise: (.+?)\./);
          return match ? match[1] : '';
        })
        .filter(Boolean);
    });
  }

  // Open the exercise picker to swap an exercise by using the swap button
  // Strategy: try long-press first, then fall back to swap button
  async function openSwapPicker(exerciseName: string): Promise<boolean> {
    const groupSelector = `role=group[name*="Exercise: ${exerciseName}. Tap for details"]`;
    const groupVisible = await page.locator(groupSelector).isVisible({ timeout: 3_000 }).catch(() => false);
    if (!groupVisible) {
      log(`[swap] Exercise "${exerciseName}" group not visible — cannot open swap picker`);
      return false;
    }

    // Try long-press on the group
    await flutterLongPress(page, groupSelector, 900);
    await page.waitForTimeout(1200);

    let pickerOpen = await page.locator(EXERCISE_PICKER.searchInput).isVisible({ timeout: 3_000 }).catch(() => false);
    if (pickerOpen) {
      log(`[swap] Picker opened via long-press on "${exerciseName}"`);
      return true;
    }

    // Long-press may have opened detail sheet — dismiss it
    await page.keyboard.press('Escape');
    await page.waitForTimeout(600);

    // Try the swap icon button (visible in normal mode)
    const swapBtn = page.locator('role=button[name*="Swap exercise"]').first();
    const hasSwap = await swapBtn.isVisible({ timeout: 2_000 }).catch(() => false);
    if (hasSwap) {
      await swapBtn.click();
      await page.waitForTimeout(800);
      pickerOpen = await page.locator(EXERCISE_PICKER.searchInput).isVisible({ timeout: 3_000 }).catch(() => false);
      if (pickerOpen) {
        log(`[swap] Picker opened via swap button for "${exerciseName}"`);
        return true;
      }
    }

    log(`[swap] Could not open swap picker for "${exerciseName}" — neither long-press nor button worked`);
    return false;
  }

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({
      viewport: VIEWPORT,
      deviceScaleFactor: 2.0,
      baseURL: 'http://127.0.0.1:4200',
    });
    page = await context.newPage();

    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        log(`[CONSOLE ERROR] ${msg.text()}`);
      }
    });
    page.on('pageerror', (err) => {
      log(`[PAGE ERROR] ${String(err)}`);
    });
    page.on('response', (response) => {
      if (response.status() >= 400 && response.status() < 600) {
        log(`[HTTP ${response.status()}] ${response.url()}`);
      }
    });

    const user = getUser('fullWorkout');
    await login(page, user.email, user.password);
    log(`[setup] Logged in as ${user.email}`);
  });

  test.afterAll(async () => {
    console.log('\n=== CHARTER C FINDINGS ===');
    findings.forEach((f) => console.log(f));
    await context.close();
  });

  // =========================================================================
  // MAIN CHARTER SESSION — all probes in sequence
  // =========================================================================

  test('Charter C — all probes sequential', async () => {

    // -----------------------------------------------------------------------
    // P1: Add 5 exercises; verify FAB/finish-bar/reorder-toggle appearances
    // -----------------------------------------------------------------------
    log('=== P1: Add 5 exercises ===');

    await startEmptyWorkout(page);
    log('[P1] Active workout started');
    await ss('P1-empty-workout');

    // Verify initial empty state
    const fabEmpty = await page.locator(WORKOUT.addExerciseFab).isVisible({ timeout: 3_000 });
    log(`[P1] FAB visible on empty workout: ${fabEmpty} (expected: true)`);

    const finishEmpty = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[P1] Finish bar visible on empty workout: ${finishEmpty} (expected: false)`);
    if (finishEmpty) {
      log('[FINDING:P1-01] PROD-BUG CANDIDATE: Finish bar visible on empty workout — expected hidden per §5.5 matrix');
    }

    const reorderEmpty = await page.locator('[flt-semantics-identifier="workout-reorder-toggle"]').isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[P1] Reorder toggle visible on empty workout: ${reorderEmpty} (expected: false)`);
    if (reorderEmpty) {
      log('[FINDING:P1-02] PROD-BUG CANDIDATE: Reorder toggle shown with 0 exercises — §5.5 says hidden when <2');
    }

    // Add exercise 1: Push-Up (bodyweight) — use BW helper (no weight column)
    await addBodyweightExercise(page, EX.pushUp);
    log('[P1] Added exercise 1: Push-Up (bodyweight)');
    await ss('P1-after-ex1');

    const reorderAfter1 = await page.locator('[flt-semantics-identifier="workout-reorder-toggle"]').isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[P1] Reorder toggle after 1 exercise: ${reorderAfter1} (expected: false — needs ≥2)`);
    if (reorderAfter1) {
      log('[FINDING:P1-03] PROD-BUG: Reorder toggle appeared with only 1 exercise — §5.5 requires ≥2');
    }

    // Add exercise 2: Barbell Bench Press (weighted)
    await addExercise(page, EX.benchPress);
    log('[P1] Added exercise 2: Barbell Bench Press (weighted)');
    await ss('P1-after-ex2');

    const reorderAfter2 = await page.locator('[flt-semantics-identifier="workout-reorder-toggle"]').isVisible({ timeout: 3_000 }).catch(() => false);
    log(`[P1] Reorder toggle after 2 exercises: ${reorderAfter2} (expected: true — ≥2 exercises)`);
    if (!reorderAfter2) {
      log('[FINDING:P1-04] PROD-BUG: Reorder toggle NOT appearing after 2nd exercise — or AOM identifier wrong');
      // Check AOM for any reorder-related elements
      await aomSnap('P1-no-reorder-toggle');
    }

    // Add exercise 3: Barbell Squat (weighted) — log 2 sets for swap probe
    await addExercise(page, EX.squat);
    log('[P1] Added exercise 3: Barbell Squat');

    // Log 2 sets on exercise 3 (Barbell Squat)
    // The 3 exercises each have 1 uncompleted set: ex1[0], ex2[0], ex3[0].
    // completeSet(page, N) clicks the Nth uncompleted set AND verifies the Nth completed marker.
    // Complete all 3 sets in order so the index alignment is correct.
    await page.waitForTimeout(400);

    // Set weight/reps for the last (ex3) set before completing anything
    await setWeight(page, '60');
    await setReps(page, '8');

    // Complete set on exercise 3 directly by clicking its done-mark button
    // (all 3 sets are uncompleted, ex3 is nth(2) in the done-mark list)
    // Use a direct click on ex3's done-mark, then verify via setCompleted count
    const doneMarks = page.locator(WORKOUT.markSetDone);
    const doneCount = await doneMarks.count().catch(() => 0);
    log(`[P1] Done-mark buttons before completing ex3 set: ${doneCount}`);

    // Click ex3's done mark (index 2 in the list)
    if (doneCount >= 3) {
      await doneMarks.nth(2).click();
      await page.waitForTimeout(600);
      // Dismiss rest timer if it appeared
      const rt = page.locator('role=progressbar[name*="Rest timer"]');
      const rtVisible = await rt.isVisible({ timeout: 2_000 }).catch(() => false);
      if (rtVisible) {
        const skipBtn = page.locator('role=button[name*="Skip"]').first();
        const hasSkip = await skipBtn.isVisible({ timeout: 1_000 }).catch(() => false);
        if (hasSkip) { await skipBtn.click(); }
        else { await page.mouse.click(180, 390); }
        await rt.waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});
      }
      log('[P1] Completed 1 set on exercise 3');
    }

    // Add second set on ex3
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(600);
    await setWeight(page, '65');
    await setReps(page, '6');

    // Complete 2nd set on ex3 — now index is higher since we completed 1 already
    const doneMarks2 = page.locator(WORKOUT.markSetDone);
    const doneCount2 = await doneMarks2.count().catch(() => 0);
    log(`[P1] Done-mark buttons after 1st completion + new set: ${doneCount2}`);
    if (doneCount2 >= 1) {
      await doneMarks2.last().click();
      await page.waitForTimeout(600);
      const rt2 = page.locator('role=progressbar[name*="Rest timer"]');
      const rtVisible2 = await rt2.isVisible({ timeout: 2_000 }).catch(() => false);
      if (rtVisible2) {
        const skipBtn2 = page.locator('role=button[name*="Skip"]').first();
        const hasSkip2 = await skipBtn2.isVisible({ timeout: 1_000 }).catch(() => false);
        if (hasSkip2) { await skipBtn2.click(); }
        else { await page.mouse.click(180, 390); }
        await rt2.waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});
      }
      log('[P1] Completed 2nd set on exercise 3');
    }

    await page.waitForTimeout(500);
    log('[P1] Logged 2 completed sets on exercise 3 (Barbell Squat)');
    await ss('P1-ex3-sets-logged');

    // Add exercise 4: Pull-Up (bodyweight) — use BW helper (no weight column)
    await addBodyweightExercise(page, EX.pullUp);
    log('[P1] Added exercise 4: Pull-Up (bodyweight)');

    // Add exercise 5: Overhead Press (weighted)
    await addExercise(page, EX.overheadPress);
    log('[P1] Added exercise 5: Overhead Press (weighted)');
    await ss('P1-5exercises');

    const exerciseCountP1 = await countExercises();
    log(`[P1] Exercise count after adding 5: ${exerciseCountP1} (expected: 5)`);
    if (exerciseCountP1 !== 5) {
      log(`[FINDING:P1-05] ANOMALY: Expected 5 exercises, got ${exerciseCountP1}`);
    }

    const finishAfter5 = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 3_000 }).catch(() => false);
    log(`[P1] Finish bar visible after 5 exercises with completed sets: ${finishAfter5} (expected: true)`);
    if (!finishAfter5) {
      log('[FINDING:P1-06] PROD-BUG: Finish bar NOT visible after adding 5 exercises with ≥1 completed set');
    }

    await aomSnap('P1-5ex-complete');
    log('[P1] DONE');

    // -----------------------------------------------------------------------
    // P2: Swap exercise 3 (Barbell Squat → Leg Press)
    // -----------------------------------------------------------------------
    log('=== P2: Swap exercise 3 ===');

    const setCountBeforeSwap = await page.locator(WORKOUT.markSetDone).count().catch(() => 0);
    const completedBeforeSwap = await page.locator(WORKOUT.setCompleted).count().catch(() => 0);
    log(`[P2] Sets before swap: incomplete=${setCountBeforeSwap}, completed=${completedBeforeSwap}`);

    await ss('P2-before-swap');

    const swapPickerOpened = await openSwapPicker(EX.squat);
    log(`[P2] Swap picker opened for Barbell Squat: ${swapPickerOpened}`);

    if (swapPickerOpened) {
      await ss('P2-picker-open');
      await flutterFill(page, EXERCISE_PICKER.searchInput, EX.legPress);
      await page.waitForTimeout(1500);

      const legPressBtn = page.locator(EXERCISE_PICKER.addExerciseButton(EX.legPress)).first();
      const hasLegPress = await legPressBtn.isVisible({ timeout: 5_000 }).catch(() => false);
      log(`[P2] Leg Press in picker: ${hasLegPress}`);

      if (hasLegPress) {
        await legPressBtn.click();
        await page.waitForTimeout(1500);
        await ss('P2-after-swap');

        // Verify swap results
        const legPressVisible = await page.locator('role=group[name*="Exercise: Leg Press. Tap for details"]').isVisible({ timeout: 3_000 }).catch(() => false);
        const squatGone = !(await page.locator('role=group[name*="Exercise: Barbell Squat. Tap for details"]').isVisible({ timeout: 2_000 }).catch(() => false));
        log(`[P2] Leg Press visible after swap: ${legPressVisible}`);
        log(`[P2] Barbell Squat gone after swap: ${squatGone}`);

        if (!squatGone) {
          log('[FINDING:P2-01] PROD-BUG: Original exercise still visible after swap');
        }

        const completedAfterSwap = await page.locator(WORKOUT.setCompleted).count().catch(() => 0);
        log(`[P2] Completed sets after swap: ${completedAfterSwap} (before: ${completedBeforeSwap})`);
        if (completedAfterSwap < completedBeforeSwap) {
          log('[FINDING:P2-02] PROD-BUG: Completed sets LOST after swap — sets not retained');
        } else {
          log('[P2] PASS: Sets retained after swap (completed count preserved)');
        }

        // Check PR state on swapped exercise
        const pendingPrAfterSwap = await page.locator(SET_ROW.statePendingPr).count().catch(() => 0);
        log(`[P2] Pending PR rows after swap: ${pendingPrAfterSwap} (Leg Press is new exercise, expected >0 if user has no prior Leg Press history)`);
      } else {
        log('[P2] Leg Press not found in picker — exercise name mismatch or search failed');
      }
    } else {
      log('[FINDING:P2-03] PROD-BUG CANDIDATE: Neither long-press nor swap button opened picker for Barbell Squat');
    }
    log('[P2] DONE');

    // -----------------------------------------------------------------------
    // P3: Remove exercise 2 (Barbell Bench Press)
    // -----------------------------------------------------------------------
    log('=== P3: Remove exercise 2 ===');

    const exerciseCountBeforeRemove = await countExercises();
    const namesBeforeRemove = await exerciseNames();
    log(`[P3] Exercises before remove: ${exerciseCountBeforeRemove} — ${namesBeforeRemove.join(', ')}`);

    await ss('P3-before-remove');

    const allDeleteBtns = page.locator('role=button[name*="Delete exercise"]');
    const deleteBtnCount = await allDeleteBtns.count().catch(() => 0);
    log(`[P3] Delete buttons visible: ${deleteBtnCount}`);

    if (deleteBtnCount >= 2) {
      // Click 2nd delete button (exercise 2)
      await allDeleteBtns.nth(1).click();
      await page.waitForTimeout(800);

      // Confirm dialog
      // Look for confirmation buttons with common patterns
      const confirmPatterns = ['Remove', 'Delete', 'Confirm', 'Yes'];
      let confirmed = false;
      for (const pattern of confirmPatterns) {
        const btn = page.locator(`role=button[name*="${pattern}"]`).first();
        const btnVisible = await btn.isVisible({ timeout: 2_000 }).catch(() => false);
        if (btnVisible) {
          // Make sure it's not the original Delete exercise button
          const btnText = await btn.textContent().catch(() => '');
          if (!btnText?.includes('exercise') && !btnText?.includes('Exercise')) {
            await btn.click();
            confirmed = true;
            log(`[P3] Confirmed deletion via "${pattern}" button`);
            break;
          }
        }
      }

      if (!confirmed) {
        // Take a screenshot to see what dialog appeared
        await ss('P3-confirm-dialog');
        await aomSnap('P3-confirm-dialog');
        log('[FINDING:P3-01] TEST-INFRA: Could not find confirmation button — see AOM snapshot');
      }

      await page.waitForTimeout(1000);
      await ss('P3-after-remove');

      const exerciseCountAfterRemove = await countExercises();
      const namesAfterRemove = await exerciseNames();
      log(`[P3] Exercises after remove: ${exerciseCountAfterRemove} (expected: ${exerciseCountBeforeRemove - 1}) — ${namesAfterRemove.join(', ')}`);

      if (exerciseCountAfterRemove !== exerciseCountBeforeRemove - 1) {
        log(`[FINDING:P3-02] ANOMALY: Exercise count after remove wrong: ${exerciseCountAfterRemove} vs expected ${exerciseCountBeforeRemove - 1}`);
      }

      const benchPressGone = !(await page.locator('role=group[name*="Exercise: Barbell Bench Press. Tap for details"]').isVisible({ timeout: 2_000 }).catch(() => false));
      log(`[P3] Barbell Bench Press removed: ${benchPressGone}`);
      if (!benchPressGone) {
        log('[FINDING:P3-03] PROD-BUG: Exercise still visible after delete + confirm');
      }

      // Verify completed sets still intact on remaining exercises
      const completedAfterRemove = await page.locator(WORKOUT.setCompleted).count().catch(() => 0);
      log(`[P3] Completed sets after removing ex2: ${completedAfterRemove}`);
    } else {
      log(`[P3] SKIP: Not enough exercises (${deleteBtnCount} delete buttons found)`);
    }
    log('[P3] DONE');

    // -----------------------------------------------------------------------
    // P4: Reorder mode — up/down arrows
    // -----------------------------------------------------------------------
    log('=== P4: Reorder mode ===');

    // Find reorder toggle — try multiple selector strategies
    const reorderSelectors = [
      '[flt-semantics-identifier="workout-reorder-toggle"]',
      'role=button[name*="Reorder exercises"]',
      'role=button[name*="reorder"]',
    ];

    let reorderEntered = false;
    for (const sel of reorderSelectors) {
      const toggle = page.locator(sel).first();
      const visible = await toggle.isVisible({ timeout: 2_000 }).catch(() => false);
      if (visible) {
        await toggle.click();
        reorderEntered = true;
        log(`[P4] Entered reorder mode via: ${sel}`);
        break;
      }
    }

    if (!reorderEntered) {
      log('[FINDING:P4-01] PROD-BUG CANDIDATE: Reorder toggle not found in AOM after >2 exercises');
      await aomSnap('P4-no-reorder-toggle');
    }

    await page.waitForTimeout(800);
    await ss('P4-reorder-mode');
    await aomSnap('P4-reorder-mode');

    const namesBeforeReorder = await exerciseNames();
    log(`[P4] Exercise order before reorder: ${namesBeforeReorder.join(', ')}`);

    // Look for up/down buttons
    const upBtnSelectors = [
      'role=button[name*="Move up"]',
      '[flt-semantics-identifier="workout-reorder-up"]',
    ];
    const downBtnSelectors = [
      'role=button[name*="Move down"]',
      '[flt-semantics-identifier="workout-reorder-down"]',
    ];

    let upBtns = page.locator(upBtnSelectors[0]);
    let downBtns = page.locator(downBtnSelectors[0]);
    let upCount = await upBtns.count().catch(() => 0);
    let downCount = await downBtns.count().catch(() => 0);

    if (upCount === 0) {
      upBtns = page.locator(upBtnSelectors[1]);
      downBtns = page.locator(downBtnSelectors[1]);
      upCount = await upBtns.count().catch(() => 0);
      downCount = await downBtns.count().catch(() => 0);
    }

    log(`[P4] Up buttons: ${upCount}, Down buttons: ${downCount}`);

    if (upCount === 0 && downCount === 0) {
      log('[FINDING:P4-02] PROD-BUG CANDIDATE: No reorder up/down buttons found in AOM — either reorder mode not entered, or buttons not exposed to AOM');
    } else {
      // Move first exercise down
      const firstDown = downBtns.first();
      const firstDownVisible = await firstDown.isVisible({ timeout: 2_000 }).catch(() => false);
      if (firstDownVisible) {
        await firstDown.click();
        await page.waitForTimeout(500);
        log('[P4] Tapped first exercise "Move down"');
        await ss('P4-after-first-move-down');
      }

      // Move last exercise up
      const lastUp = upBtns.last();
      const lastUpVisible = await lastUp.isVisible({ timeout: 2_000 }).catch(() => false);
      if (lastUpVisible) {
        await lastUp.click();
        await page.waitForTimeout(500);
        log('[P4] Tapped last exercise "Move up"');
      }

      const namesAfterReorder = await exerciseNames();
      log(`[P4] Exercise order after reorder: ${namesAfterReorder.join(', ')}`);
      const orderChanged = JSON.stringify(namesBeforeReorder) !== JSON.stringify(namesAfterReorder);
      log(`[P4] Order changed: ${orderChanged}`);
      if (!orderChanged) {
        log('[FINDING:P4-03] PROD-BUG: Order did not change despite tapping reorder arrows');
      }
    }

    // Exit reorder mode
    const exitSelectors = [
      '[flt-semantics-identifier="workout-reorder-toggle"]',
      'role=button[name*="Done reordering"]',
      'role=button[name*="Done"]',
    ];
    for (const sel of exitSelectors) {
      const btn = page.locator(sel).first();
      const visible = await btn.isVisible({ timeout: 1_500 }).catch(() => false);
      if (visible) {
        await btn.click();
        log('[P4] Exited reorder mode');
        break;
      }
    }
    await page.waitForTimeout(500);
    await ss('P4-after-exit-reorder');

    // Verify delete buttons reappear
    const deleteAfterExit = await page.locator('role=button[name*="Delete exercise"]').count().catch(() => 0);
    log(`[P4] Delete buttons after exiting reorder: ${deleteAfterExit}`);
    if (deleteAfterExit === 0) {
      log('[FINDING:P4-04] PROD-BUG: Delete buttons did not reappear after exiting reorder mode');
    }
    log('[P4] DONE');

    // -----------------------------------------------------------------------
    // P5: Add same exercise twice
    // -----------------------------------------------------------------------
    log('=== P5: Add same exercise twice ===');

    const exerciseCountP5Before = await countExercises();
    const pushUpGroupsBefore = (await exerciseNames()).filter(n => n === EX.pushUp || n === EX.pullUp).length;
    log(`[P5] Exercises before: ${exerciseCountP5Before}, Push-Up count: ${pushUpGroupsBefore}`);

    await addBodyweightExercise(page, EX.pushUp);
    await page.waitForTimeout(500);
    log(`[P5] Added ${EX.pushUp} again`);
    await ss('P5-after-duplicate');

    const exerciseCountP5After = await countExercises();
    log(`[P5] Exercises after: ${exerciseCountP5After} (expected: ${exerciseCountP5Before + 1})`);

    if (exerciseCountP5After === exerciseCountP5Before + 1) {
      log('[P5] PASS: Second Push-Up block appended (expected behavior)');
    } else if (exerciseCountP5After === exerciseCountP5Before) {
      log('[FINDING:P5-01] PROD-BUG: Duplicate exercise NOT appended — may be silently deduplicated');
    }

    const pushUpGroupsAfter = (await exerciseNames()).filter(n => n === EX.pushUp || n === EX.pullUp).length;
    log(`[P5] Push-Up groups in AOM after: ${pushUpGroupsAfter}`);
    await aomSnap('P5-duplicate');
    log('[P5] DONE');

    // -----------------------------------------------------------------------
    // P6: Long-press swap mid-rest-timer
    // -----------------------------------------------------------------------
    log('=== P6: Long-press swap mid-rest-timer ===');

    // Complete a set on the first exercise to trigger rest timer
    const incompleteSet = page.locator(WORKOUT.markSetDone).first();
    const hasIncomplete = await incompleteSet.isVisible({ timeout: 3_000 }).catch(() => false);
    if (!hasIncomplete) {
      await page.locator(WORKOUT.addSetButton).first().click();
      await page.waitForTimeout(700);
    }

    // Click the done mark WITHOUT using the completeSet helper (which auto-dismisses timer)
    await page.locator(WORKOUT.markSetDone).first().click();
    await page.waitForTimeout(400);

    const restTimerVisible = await page.locator('role=progressbar[name*="Rest timer"]').isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[P6] Rest timer visible after completing set: ${restTimerVisible}`);

    if (restTimerVisible) {
      await ss('P6-rest-timer-active');

      // While rest timer is active, attempt long-press on a different exercise
      // Find any exercise group that is NOT the first (since first triggered timer)
      const exerciseGroupsNow = await exerciseNames();
      log(`[P6] Exercises visible during rest timer: ${exerciseGroupsNow.join(', ')}`);

      const targetExercise = exerciseGroupsNow.length > 1 ? exerciseGroupsNow[1] : null;
      if (targetExercise) {
        log(`[P6] Attempting long-press on "${targetExercise}" while rest timer active...`);
        const targetSel = `role=group[name*="Exercise: ${targetExercise}. Tap for details"]`;
        await flutterLongPress(page, targetSel, 900);
        await page.waitForTimeout(1200);

        const timerAfter = await page.locator('role=progressbar[name*="Rest timer"]').isVisible({ timeout: 2_000 }).catch(() => false);
        const pickerAfter = await page.locator(EXERCISE_PICKER.searchInput).isVisible({ timeout: 2_000 }).catch(() => false);
        log(`[P6] Rest timer still visible: ${timerAfter}`);
        log(`[P6] Picker opened: ${pickerAfter}`);

        await ss('P6-after-longpress-through-timer');

        if (pickerAfter && timerAfter) {
          log('[FINDING:P6-01] PROD-BUG: Picker opened THROUGH rest timer scrim — both simultaneously active. Confirms AW-EX-A-BR1-04 / AW-EX-B-US1-01 pattern also affects long-press. Rest timer scrim does not block long-press pointer events.');
        } else if (pickerAfter && !timerAfter) {
          log('[P6] NOTE: Timer dismissed then picker opened — reasonable but tap-through still occurred');
        } else if (!pickerAfter && !timerAfter) {
          log('[P6] Timer dismissed by long-press start; picker did not open (pointer absorbed by overlay)');
        } else {
          log('[P6] Timer still active, picker did not open (scrim correctly blocked)');
        }

        // Cleanup
        if (pickerAfter) {
          await page.keyboard.press('Escape');
          await page.waitForTimeout(500);
        }
      } else {
        log('[P6] SKIP: Only 1 exercise — cannot test cross-exercise long-press during timer');
      }

      // Dismiss rest timer
      const timerStill = await page.locator('role=progressbar[name*="Rest timer"]').isVisible({ timeout: 1_000 }).catch(() => false);
      if (timerStill) {
        const skipBtn = page.locator('role=button[name*="Skip"]').first();
        const hasSkip = await skipBtn.isVisible({ timeout: 1_000 }).catch(() => false);
        if (hasSkip) {
          await skipBtn.click();
        } else {
          const vp = page.viewportSize() ?? { width: 360, height: 780 };
          await page.mouse.click(vp.width / 2, vp.height / 2);
        }
        await page.waitForTimeout(500);
      }
    } else {
      log('[P6] Rest timer did not appear — skipping mid-timer probe');
    }
    log('[P6] DONE');

    // -----------------------------------------------------------------------
    // P7: Remove all exercises — empty state reappears
    // -----------------------------------------------------------------------
    log('=== P7: Remove all exercises ===');
    await ss('P7-before-remove-all');

    let removeIter = 0;
    while (removeIter < 15) {
      const firstDelete = page.locator('role=button[name*="Delete exercise"]').first();
      const hasDelete = await firstDelete.isVisible({ timeout: 2_000 }).catch(() => false);
      if (!hasDelete) break;

      await firstDelete.click();
      await page.waitForTimeout(600);

      // Try all common confirmation patterns
      const confirmPatterns = ['Remove', 'Delete', 'Confirm', 'Yes'];
      let confirmed = false;
      for (const pattern of confirmPatterns) {
        const btn = page.locator(`role=button[name*="${pattern}"]`).first();
        const visible = await btn.isVisible({ timeout: 1_500 }).catch(() => false);
        if (visible) {
          await btn.click();
          confirmed = true;
          break;
        }
      }
      if (!confirmed) {
        // Snapshot to see what appeared
        log(`[P7] No confirm dialog on iteration ${removeIter + 1} — may be direct delete or unknown dialog`);
        await aomSnap(`P7-iter${removeIter + 1}`);
        break;
      }

      await page.waitForTimeout(800);
      removeIter++;
      log(`[P7] Removed exercise ${removeIter}`);
    }

    await ss('P7-after-remove-all');

    const finishHiddenP7 = !(await page.locator(WORKOUT.finishButton).isVisible({ timeout: 2_000 }).catch(() => false));
    const fabP7 = await page.locator(WORKOUT.addExerciseFab).isVisible({ timeout: 3_000 }).catch(() => false);
    log(`[P7] Finish button hidden after all removed: ${finishHiddenP7} (expected: true)`);
    log(`[P7] FAB/CTA visible after all removed: ${fabP7} (expected: true)`);
    if (!finishHiddenP7) {
      log('[FINDING:P7-01] PROD-BUG: Finish button visible after removing all exercises');
    }
    if (!fabP7) {
      log('[FINDING:P7-02] PROD-BUG: FAB/CTA not visible after removing all exercises — empty-state not shown');
    }
    await aomSnap('P7-empty');
    log('[P7] DONE');

    // -----------------------------------------------------------------------
    // P8: Add from empty-state CTA
    // -----------------------------------------------------------------------
    log('=== P8: Add from empty-state CTA ===');

    const ctaVisible = await page.locator(WORKOUT.addExerciseFab).isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[P8] Empty-state CTA visible: ${ctaVisible}`);

    if (ctaVisible) {
      await page.locator(WORKOUT.addExerciseFab).first().click();
      await page.waitForTimeout(1000);

      const pickerOpen = await page.locator(EXERCISE_PICKER.searchInput).isVisible({ timeout: 5_000 }).catch(() => false);
      log(`[P8] Picker opened from empty CTA: ${pickerOpen}`);

      if (pickerOpen) {
        await flutterFill(page, EXERCISE_PICKER.searchInput, EX.dumbbellCurl);
        await page.waitForTimeout(1500);
        const curlBtn = page.locator(EXERCISE_PICKER.addExerciseButton(EX.dumbbellCurl)).first();
        const hasCurl = await curlBtn.isVisible({ timeout: 5_000 }).catch(() => false);
        if (hasCurl) {
          await curlBtn.click();
          await page.waitForTimeout(1000);
          log('[P8] Added Dumbbell Curl from empty-state CTA');
          await ss('P8-after-add-from-cta');

          const exerciseCountP8 = await countExercises();
          log(`[P8] Exercise count after add from CTA: ${exerciseCountP8} (expected: 1)`);
          const addSetVisible = await page.locator(WORKOUT.addSetButton).isVisible({ timeout: 3_000 }).catch(() => false);
          log(`[P8] Add Set button visible: ${addSetVisible}`);
          if (exerciseCountP8 !== 1) {
            log('[FINDING:P8-01] ANOMALY: Expected 1 exercise after add-from-CTA');
          }
        } else {
          log('[P8] Dumbbell Curl not found in picker');
          await page.keyboard.press('Escape');
        }
      } else {
        log('[FINDING:P8-02] PROD-BUG: Picker did not open from empty-state CTA');
      }
    } else {
      log('[FINDING:P8-03] PROD-BUG: Empty-state CTA not visible after removing all exercises');
    }
    log('[P8] DONE');

    // -----------------------------------------------------------------------
    // P9/P10: Bodyweight ↔ weighted swap; weight column show/hide
    // -----------------------------------------------------------------------
    log('=== P9/P10: Bodyweight ↔ weighted swap ===');

    // Start fresh for clean observation
    // Discard current workout and start new
    const discardBtn = page.locator(WORKOUT.discardButton);
    const hasDiscard = await discardBtn.isVisible({ timeout: 2_000 }).catch(() => false);
    if (hasDiscard) {
      await discardBtn.click();
      await page.waitForTimeout(500);
      const confirmDiscard = page.locator(WORKOUT.discardConfirmButton);
      const hasConfirmDiscard = await confirmDiscard.isVisible({ timeout: 3_000 }).catch(() => false);
      if (hasConfirmDiscard) {
        await confirmDiscard.click();
        await page.waitForURL(/\/home/, { timeout: 10_000 });
        log('[P9] Discarded workout for clean P9/P10 state');
      }
    }

    await startEmptyWorkout(page);

    // Add Push-Up (bodyweight) — use BW helper (no weight column)
    await addBodyweightExercise(page, EX.pushUp);
    log('[P9] Added Push-Up (bodyweight)');
    await ss('P9-bodyweight-only');

    // Check weight buttons for bodyweight-only exercise
    const weightCountBW = await page.locator('role=button[name*="Weight value"]').count().catch(() => 0);
    log(`[P9] Weight buttons for bodyweight exercise: ${weightCountBW} (expected: 0 — no weight column for BW)`);
    if (weightCountBW > 0) {
      log('[FINDING:P9-01] PROD-BUG CANDIDATE: Weight column visible for bodyweight exercise — should be hidden per §5.5');
    }

    // Check reps buttons (should be present)
    const repsCountBW = await page.locator('role=button[name*="Reps value"]').count().catch(() => 0);
    log(`[P9] Reps buttons for bodyweight exercise: ${repsCountBW} (expected: ≥1)`);

    // P9: Swap bodyweight → weighted; weight column should APPEAR
    const swapToWeightedOpened = await openSwapPicker(EX.pushUp);
    log(`[P9] Swap picker opened for Push-Up: ${swapToWeightedOpened}`);

    if (swapToWeightedOpened) {
      await flutterFill(page, EXERCISE_PICKER.searchInput, EX.benchPress);
      await page.waitForTimeout(1500);
      const benchBtn = page.locator(EXERCISE_PICKER.addExerciseButton(EX.benchPress)).first();
      const hasBench = await benchBtn.isVisible({ timeout: 5_000 }).catch(() => false);
      if (hasBench) {
        await benchBtn.click();
        await page.waitForTimeout(1000);
        log('[P9] Swapped Push-Up → Barbell Bench Press');
        await ss('P9-after-swap-to-weighted');

        const weightCountWeighted = await page.locator('role=button[name*="Weight value"]').count().catch(() => 0);
        log(`[P9] Weight buttons after swap to weighted: ${weightCountWeighted} (before: ${weightCountBW})`);
        if (weightCountBW === 0 && weightCountWeighted === 0) {
          log('[FINDING:P9-02] PROD-BUG: Weight column did NOT reappear after swapping bodyweight → weighted');
        } else if (weightCountWeighted > weightCountBW) {
          log('[P9] PASS: Weight column appeared after swap to weighted');
        }

        // P10: Swap weighted → bodyweight; weight column should HIDE
        log('=== P10: Weighted → bodyweight ===');
        const weightCountP10Before = await page.locator('role=button[name*="Weight value"]').count().catch(() => 0);
        log(`[P10] Weight buttons before swap to bodyweight: ${weightCountP10Before}`);

        const swapToBodyweightOpened = await openSwapPicker(EX.benchPress);
        log(`[P10] Swap picker opened for Bench Press: ${swapToBodyweightOpened}`);

        if (swapToBodyweightOpened) {
          await flutterFill(page, EXERCISE_PICKER.searchInput, EX.pullUp);
          await page.waitForTimeout(1500);
          const pullUpBtn = page.locator(EXERCISE_PICKER.addExerciseButton(EX.pullUp)).first();
          const hasPullUp = await pullUpBtn.isVisible({ timeout: 5_000 }).catch(() => false);
          if (hasPullUp) {
            await pullUpBtn.click();
            await page.waitForTimeout(1000);
            log('[P10] Swapped Bench Press → Pull-Up');
            await ss('P10-after-swap-to-bodyweight');

            const weightCountP10After = await page.locator('role=button[name*="Weight value"]').count().catch(() => 0);
            log(`[P10] Weight buttons after swap to bodyweight: ${weightCountP10After} (before: ${weightCountP10Before})`);
            if (weightCountP10After >= weightCountP10Before && weightCountP10Before > 0) {
              log('[FINDING:P10-01] PROD-BUG: Weight column did NOT hide after swapping weighted → bodyweight. Rows still show weight buttons for removed-weight exercise type.');
            } else if (weightCountP10After < weightCountP10Before) {
              log('[P10] PASS: Weight column hid after swap to bodyweight');
            } else {
              log('[P10] INCONCLUSIVE: No weight buttons present before swap to bodyweight — may already be hidden');
            }
          }
        }
      }
    } else {
      log('[P9] SKIP: Could not open swap picker for Push-Up');
    }
    log('[P9/P10] DONE');

    // -----------------------------------------------------------------------
    // P11: Finish button states
    // -----------------------------------------------------------------------
    log('=== P11: Finish button states ===');

    // Discard and start fresh empty workout
    const discardP11 = page.locator(WORKOUT.discardButton);
    const hasDiscardP11 = await discardP11.isVisible({ timeout: 2_000 }).catch(() => false);
    if (hasDiscardP11) {
      await discardP11.click();
      await page.waitForTimeout(500);
      const confirmP11 = page.locator(WORKOUT.discardConfirmButton);
      const hasConfirmP11 = await confirmP11.isVisible({ timeout: 3_000 }).catch(() => false);
      if (hasConfirmP11) {
        await confirmP11.click();
        await page.waitForURL(/\/home/, { timeout: 10_000 });
      }
    }

    await startEmptyWorkout(page);
    log('[P11] Started fresh empty workout');

    const finishP11Empty = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[P11] Finish hidden on empty workout: ${!finishP11Empty} (expected: true/hidden)`);
    if (finishP11Empty) {
      log('[FINDING:P11-01] PROD-BUG: Finish button visible on empty workout');
    }
    await ss('P11-empty-finish-state');

    await addExercise(page, EX.benchPress);
    const finishP11NoSets = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 3_000 }).catch(() => false);
    log(`[P11] Finish visible after exercise added (no completed sets): ${finishP11NoSets}`);

    if (finishP11NoSets) {
      // Measure the opacity/disabled state
      const isDisabled = await page.evaluate(() => {
        const allNodes = document.querySelectorAll('flt-semantics');
        for (const el of allNodes) {
          const id = el.getAttribute('flt-semantics-identifier') ?? '';
          if (id === 'workout-finish-btn') {
            return el.getAttribute('aria-disabled') === 'true';
          }
        }
        return null;
      });
      log(`[P11] Finish button aria-disabled when no sets completed: ${isDisabled} (expected: true)`);
      if (isDisabled === false) {
        log('[FINDING:P11-02] PROD-BUG: Finish button NOT disabled when no sets completed — should be 30% alpha per §5.5 matrix');
      }
    }

    await ss('P11-finish-no-completed-sets');

    await setWeight(page, '80');
    await setReps(page, '8');
    await completeSet(page, 0);
    await page.waitForTimeout(500);
    log('[P11] Completed 1 set');
    await ss('P11-finish-after-1-set');

    const finishEnabledAfterSet = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 3_000 }).catch(() => false);
    log(`[P11] Finish visible after 1 completed set: ${finishEnabledAfterSet}`);

    if (finishEnabledAfterSet) {
      const isDisabledAfter = await page.evaluate(() => {
        const allNodes = document.querySelectorAll('flt-semantics');
        for (const el of allNodes) {
          const id = el.getAttribute('flt-semantics-identifier') ?? '';
          if (id === 'workout-finish-btn') {
            return el.getAttribute('aria-disabled') === 'true';
          }
        }
        return null;
      });
      log(`[P11] Finish button aria-disabled after 1 completed set: ${isDisabledAfter} (expected: false/null)`);
      if (isDisabledAfter === true) {
        log('[FINDING:P11-03] PROD-BUG: Finish button still aria-disabled after completing 1 set');
      } else {
        log('[P11] PASS: Finish button enabled after completing 1 set');
      }
    }
    log('[P11] DONE');

    // -----------------------------------------------------------------------
    // P12: Provider re-key: remove + re-add same exercise; previous-set hint
    // -----------------------------------------------------------------------
    log('=== P12: Provider re-key probe ===');

    // Current state: workout with Bench Press, 1 completed set
    // Check for "Previous: X kg × Y" hint on set rows
    // Phase 23: per-row hint removed; probe kept for historical diagnostics, will report 0 hits.
    const prevHintBefore = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('flt-semantics'))
        .map((el: Element) => {
          const label =
            (el as HTMLElement & { ariaLabel?: string }).ariaLabel ?? '';
          return label;
        })
        .filter(l =>
          l.toLowerCase().includes('previous') ||
          l.toLowerCase().includes('last time') ||
          l.includes('kg ×') ||
          l.includes('kg x') ||
          l.includes('= last')
        );
    });
    log(`[P12] Previous-set hints before removal: ${prevHintBefore.length} — ${prevHintBefore.slice(0, 3).join(' | ')}`);

    // Remove Barbell Bench Press
    const deleteP12 = page.locator('role=button[name*="Delete exercise"]').first();
    const hasDeleteP12 = await deleteP12.isVisible({ timeout: 2_000 }).catch(() => false);

    if (hasDeleteP12) {
      await deleteP12.click();
      await page.waitForTimeout(600);

      const confirmPatterns = ['Remove', 'Delete', 'Confirm'];
      for (const pattern of confirmPatterns) {
        const btn = page.locator(`role=button[name*="${pattern}"]`).first();
        const visible = await btn.isVisible({ timeout: 1_500 }).catch(() => false);
        if (visible) {
          await btn.click();
          break;
        }
      }
      await page.waitForTimeout(800);
      log('[P12] Removed Barbell Bench Press');

      // Re-add same exercise
      await addExercise(page, EX.benchPress);
      await page.waitForTimeout(500);
      log('[P12] Re-added Barbell Bench Press');
      await ss('P12-after-readd');

      // Check for previous-set hints
      const prevHintAfter = await page.evaluate(() => {
        return Array.from(document.querySelectorAll('flt-semantics'))
          .map((el: Element) => {
            const label =
              (el as HTMLElement & { ariaLabel?: string }).ariaLabel ?? '';
            return label;
          })
          .filter(l =>
            l.toLowerCase().includes('previous') ||
            l.toLowerCase().includes('last time') ||
            l.includes('kg ×') ||
            l.includes('kg x') ||
            l.includes('= last')
          );
      });
      log(`[P12] Previous-set hints after re-add: ${prevHintAfter.length} — ${prevHintAfter.slice(0, 3).join(' | ')}`);

      if (prevHintBefore.length > 0 && prevHintAfter.length === 0) {
        log('[FINDING:P12-01] PROD-BUG CANDIDATE: Previous-set hints lost after exercise remove + re-add — provider may not re-key correctly');
      } else if (prevHintAfter.length > 0) {
        log('[P12] PASS: Previous-set hints present after re-add (provider re-keyed correctly)');
      } else {
        log('[P12] NOTE: No previous-set hints in either state — fresh workout user, no prior history');
      }
    } else {
      log('[P12] SKIP: No delete button found');
    }
    log('[P12] DONE');

    log('=== ALL PROBES COMPLETE ===');
  });
});
