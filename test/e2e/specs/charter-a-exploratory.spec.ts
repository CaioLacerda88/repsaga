/**
 * Charter A — Exploratory test: Brutal set-row workout
 * Device: BR-1 (Samsung Galaxy A14, 360×780, DPR 2.0)
 * Persona: Sam (data-nerd)
 * Date: 2026-05-07
 *
 * Structured exploratory charter. Guard: EXPL_CHARTER_A=1 so CI never runs this.
 * Each probe logs detailed output for writing up the findings file.
 * Dependencies: uses existing test helpers (login, startEmptyWorkout, addExercise).
 */

import { test, expect, Page, BrowserContext } from '@playwright/test';
import { AUTH, WORKOUT, EXERCISE_PICKER, HOME, NAV, SET_ROW, GAMIFICATION } from '../helpers/selectors';
import { waitForAppReady, dismissSagaIntroOverlay, flutterFill } from '../helpers/app';
import { login } from '../helpers/auth';
import { startEmptyWorkout, addExercise, setWeight, setReps, completeSet } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

// Skip entire file unless EXPL_CHARTER_A=1
const RUN = process.env.EXPL_CHARTER_A === '1';

const VIEWPORT = { width: 360, height: 780 };

// ============================================================
// Charter A — BR-1 probes
// ============================================================

test.describe('Charter A — Brutal set-row workout — BR-1', () => {
  test.skip(!RUN, 'Set EXPL_CHARTER_A=1 to run');

  test.use({ viewport: VIEWPORT });

  let page: Page;
  let context: BrowserContext;
  const findings: string[] = [];

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({
      viewport: VIEWPORT,
      deviceScaleFactor: 2.0,
      baseURL: 'http://127.0.0.1:4200',
    });
    page = await context.newPage();

    // Capture console errors throughout the session
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        findings.push(`[CONSOLE ERROR] ${msg.text()}`);
      }
    });
    page.on('pageerror', (err) => {
      findings.push(`[PAGE ERROR] ${String(err)}`);
    });
    page.on('response', (response) => {
      if (response.status() >= 400) {
        findings.push(`[HTTP ${response.status()}] ${response.url()}`);
      }
    });

    // Use the fullWorkout user (has prior workout history → lapsed state → quick-workout CTA)
    const user = getUser('fullWorkout');
    await login(page, user.email, user.password);
    console.log(`[setup] Logged in as ${user.email}`);

    // Start empty workout and add Barbell Bench Press
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    console.log('[setup] Barbell Bench Press added to workout');

    // Take baseline screenshot
    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-baseline.png',
    });
    console.log('[setup] Setup complete');
  });

  test.afterAll(async () => {
    console.log('\n=== FINDINGS CAPTURED DURING SESSION ===');
    findings.forEach(f => console.log(f));
    await context.close();
  });

  // -------------------------------------------------------
  // Helper: read all semantics labels from the page
  // -------------------------------------------------------
  async function allSemantics(): Promise<string[]> {
    return page.evaluate(() => {
      const els = document.querySelectorAll('flt-semantics');
      const labels: string[] = [];
      els.forEach((el: Element) => {
        const label = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        const id = el.getAttribute('flt-semantics-identifier') ?? '';
        const role = el.getAttribute('role') ?? '';
        if (label || id) {
          labels.push(`[${role}/${id}] ${label.slice(0, 60)}`);
        }
      });
      return labels;
    });
  }

  // -------------------------------------------------------
  // Probe 1: Stepper basic tap behavior
  // -------------------------------------------------------
  test('probe-01: stepper basic tap — weight + and minus update immediately', async () => {
    console.log('\n[PROBE 01] Stepper basic tap');

    // Capture initial semantics to understand the structure
    const initialSemantics = await allSemantics();
    console.log(`  Initial screen semantics (${initialSemantics.length} nodes):`);
    initialSemantics.slice(0, 30).forEach(s => console.log(`    ${s}`));
    findings.push(`[PROBE 01] Initial semantics: ${JSON.stringify(initialSemantics.slice(0, 20))}`);

    // Find + and - buttons
    const plusButtons = page.locator('role=button[name="+"]');
    const minusButtons = page.locator('role=button[name="-"]');
    const plusCount = await plusButtons.count();
    const minusCount = await minusButtons.count();
    console.log(`  + buttons: ${plusCount}, - buttons: ${minusCount}`);
    findings.push(`[PROBE 01] Stepper buttons found: plus=${plusCount}, minus=${minusCount}`);

    // Capture button bounding boxes for size assessment
    for (let i = 0; i < Math.min(plusCount, 6); i++) {
      const box = await plusButtons.nth(i).boundingBox();
      if (box) {
        console.log(`  plus[${i}] at (${box.x.toFixed(0)},${box.y.toFixed(0)}) size ${box.width.toFixed(1)}×${box.height.toFixed(1)}`);
      }
    }

    // Tap + 3 times
    if (plusCount > 0) {
      const firstPlus = plusButtons.first();
      for (let i = 0; i < 3; i++) {
        await firstPlus.click();
        await page.waitForTimeout(300);
      }
      console.log('  Tapped + 3 times');

      // Read semantic labels to detect any weight-related values
      const afterPlus = await allSemantics();
      const weightNodes = afterPlus.filter(s => s.includes('kg') || /\d+\.\d/.test(s));
      console.log(`  Weight-related nodes after +3: ${JSON.stringify(weightNodes)}`);
      findings.push(`[PROBE 01] After +3 taps: ${JSON.stringify(weightNodes)}`);

      // Tap - 2 times
      const firstMinus = minusButtons.first();
      for (let i = 0; i < 2; i++) {
        await firstMinus.click();
        await page.waitForTimeout(300);
      }
      console.log('  Tapped - 2 times');

      const afterMinus = await allSemantics();
      const weightNodes2 = afterMinus.filter(s => s.includes('kg') || /\d+\.\d/.test(s));
      console.log(`  Weight-related nodes after -2: ${JSON.stringify(weightNodes2)}`);
      findings.push(`[PROBE 01] After -2 taps: ${JSON.stringify(weightNodes2)}`);
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-stepper-taps.png',
    });
  });

  // -------------------------------------------------------
  // Probe 2: Weight stepper tap-to-type dialog
  // -------------------------------------------------------
  test('probe-02: weight stepper tap-to-type dialog — various inputs', async () => {
    console.log('\n[PROBE 02] Weight tap-to-type dialog');

    // The weight stepper shows a number (e.g., "20.0") — clicking it opens a dialog.
    // Look for the clickable weight value text. It may be identified by its context.
    // Try clicking on the weight value in the set row.

    // The WorkoutHelpers setWeight function does: locator(WORKOUT.enterWeightDialog).click()
    // which matches 'text=Enter weight' — but that's the dialog title, not the trigger.
    // The actual trigger is the tappable weight value which shows kg value.

    // Let's look for the weight stepper value via accessible name or nearby position
    const semantics = await allSemantics();
    console.log(`  Current screen nodes: ${JSON.stringify(semantics.slice(0, 40))}`);

    // Try the approach from workout helper: click weight value, dialog appears
    // The weight value in the stepper appears as text like "20.0" near the + and - buttons
    // In the AOM it may appear as a button or generic element

    // Strategy: find elements near the + button
    const plusBtn = page.locator('role=button[name="+"]').first();
    const plusBox = await plusBtn.boundingBox();
    console.log(`  Plus button position: ${JSON.stringify(plusBox)}`);

    if (plusBox) {
      // The weight value should be between the - and + buttons
      // Click slightly to the left of the + button (where the value is)
      const valueX = plusBox.x - 50; // roughly where the weight value text is
      const valueY = plusBox.y + plusBox.height / 2;
      console.log(`  Trying to click weight value at (${valueX.toFixed(0)}, ${valueY.toFixed(0)})`);
      await page.mouse.click(valueX, valueY);
      await page.waitForTimeout(1000);

      // Check if dialog appeared
      const dialogVisible = await page.locator('role=dialog').first().isVisible({ timeout: 2000 }).catch(() => false);
      const hasDialogTitle = await page.locator('text=Enter weight').isVisible({ timeout: 1000 }).catch(() => false);
      console.log(`  Dialog appeared: ${dialogVisible}, has title: ${hasDialogTitle}`);
      findings.push(`[PROBE 02] Dialog appeared after weight value click: ${dialogVisible || hasDialogTitle}`);

      if (dialogVisible || hasDialogTitle) {
        // Find the input inside the dialog
        const textInput = page.locator('input').last();
        const inputVisible = await textInput.isVisible({ timeout: 2000 }).catch(() => false);
        console.log(`  Text input in dialog visible: ${inputVisible}`);

        if (inputVisible) {
          // Test 1: valid decimal with dot
          await textInput.fill('');
          await page.keyboard.type('102.5', { delay: 50 });
          await page.waitForTimeout(300);
          let val = await textInput.inputValue().catch(() => 'n/a');
          console.log(`  After typing '102.5': input value = "${val}"`);
          findings.push(`[PROBE 02] Input after '102.5': "${val}"`);

          // Submit with OK
          const okBtn = page.locator('role=button[name="OK"]');
          if (await okBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
            await okBtn.click();
          } else {
            await page.keyboard.press('Enter');
          }
          await page.waitForTimeout(500);

          // Verify the stepper shows 102.5
          const afterSubmit = await allSemantics();
          const afterVals = afterSubmit.filter(s => s.includes('102') || s.includes('kg'));
          console.log(`  After submitting 102.5: ${JSON.stringify(afterVals)}`);
          findings.push(`[PROBE 02] After submit 102.5: ${JSON.stringify(afterVals)}`);

          // Decrement once and observe where it lands
          const firstMinus = page.locator('role=button[name="-"]').first();
          await firstMinus.click();
          await page.waitForTimeout(300);
          const afterDec = await allSemantics();
          const afterDecVals = afterDec.filter(s => s.includes('kg') || /\d{2}/.test(s));
          console.log(`  After decrement from 102.5: ${JSON.stringify(afterDecVals.slice(0, 5))}`);
          findings.push(`[PROBE 02] After decrement from 102.5: ${JSON.stringify(afterDecVals.slice(0, 5))}`);

          // Re-open dialog for comma test
          await page.mouse.click(valueX, valueY);
          await page.waitForTimeout(800);
          const dialogAgain = await page.locator('text=Enter weight').isVisible({ timeout: 2000 }).catch(() => false);

          if (dialogAgain) {
            const textInput2 = page.locator('input').last();
            await textInput2.fill('');
            await page.keyboard.type('102,5', { delay: 50 }); // comma decimal (BR locale)
            await page.waitForTimeout(300);
            val = await textInput2.inputValue().catch(() => 'n/a');
            console.log(`  After typing '102,5' (comma): input value = "${val}"`);
            findings.push(`[PROBE 02] Input after comma decimal '102,5': "${val}"`);

            // Test zero
            await textInput2.fill('');
            await page.keyboard.type('0', { delay: 50 });
            val = await textInput2.inputValue().catch(() => 'n/a');
            console.log(`  After typing '0': "${val}"`);
            findings.push(`[PROBE 02] Input after '0': "${val}"`);

            // Test very large
            await textInput2.fill('');
            await page.keyboard.type('9999', { delay: 50 });
            val = await textInput2.inputValue().catch(() => 'n/a');
            console.log(`  After typing '9999': "${val}"`);
            findings.push(`[PROBE 02] Input after '9999': "${val}"`);

            // Test negative
            await textInput2.fill('');
            await page.keyboard.type('-5', { delay: 50 });
            val = await textInput2.inputValue().catch(() => 'n/a');
            console.log(`  After typing '-5': "${val}"`);
            findings.push(`[PROBE 02] Input after '-5': "${val}"`);

            // Test alpha
            await textInput2.fill('');
            await page.keyboard.type('abc123def', { delay: 50 });
            val = await textInput2.inputValue().catch(() => 'n/a');
            console.log(`  After typing 'abc123def': "${val}"`);
            findings.push(`[PROBE 02] Input after 'abc123def': "${val}"`);

            // Cancel
            await page.keyboard.press('Escape');
            await page.waitForTimeout(300);
          }
        }
      } else {
        console.log('  WARNING: Weight dialog did not open via position click');
        findings.push('[PROBE 02] Weight dialog did NOT open via position click — selector needed');
      }
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-weight-dialog.png',
    });
  });

  // -------------------------------------------------------
  // Probe 3: Set-type long-press cycle
  // -------------------------------------------------------
  test('probe-03: set-type long-press cycle — WK → WU → DR → FL → WK', async () => {
    console.log('\n[PROBE 03] Set-type long-press cycle');

    // Find set rows
    const stateNone = page.locator(SET_ROW.stateNone);
    const statePending = page.locator(SET_ROW.statePendingPr);
    const noneCount = await stateNone.count();
    const pendingCount = await statePending.count();
    console.log(`  Set rows: none=${noneCount}, pending=${pendingCount}`);

    // Target the first available set row
    const targetRow = noneCount > 0 ? stateNone.first() : statePending.first();
    const box = await targetRow.boundingBox().catch(() => null);

    if (!box) {
      console.log('  WARNING: No set row found');
      findings.push('[PROBE 03] SKIPPED: no set rows found');
      return;
    }

    console.log(`  Row at (${box.x.toFixed(0)},${box.y.toFixed(0)}) ${box.width.toFixed(0)}×${box.height.toFixed(0)}`);

    // The set-number cell is the leftmost column in the row
    // Estimated position: first ~40px of the row, vertically centered
    const setNumX = box.x + 20;
    const setNumY = box.y + box.height / 2;

    // Cycle through 5 long-presses to cycle WK → WU → DR → FL → WK
    const setTypesBefore: string[] = [];
    const setTypesAfter: string[][] = [];

    // Capture initial type
    const initialSemantics = await allSemantics();
    const initialSetType = initialSemantics.filter(s =>
      s.toLowerCase().includes('wk') || s.toLowerCase().includes('wu') ||
      s.toLowerCase().includes('dr') || s.toLowerCase().includes('fl') ||
      s.toLowerCase().includes('working') || s.toLowerCase().includes('warmup'));
    console.log(`  Initial set type nodes: ${JSON.stringify(initialSetType)}`);
    findings.push(`[PROBE 03] Initial set type: ${JSON.stringify(initialSetType)}`);

    for (let i = 0; i < 5; i++) {
      // Long-press: hold for 800ms
      await page.mouse.move(setNumX, setNumY);
      await page.mouse.down();
      await page.waitForTimeout(800);
      await page.mouse.up();
      await page.waitForTimeout(600); // wait for animation

      const postSemantics = await allSemantics();
      const typeNodes = postSemantics.filter(s =>
        s.toLowerCase().includes('wk') || s.toLowerCase().includes('wu') ||
        s.toLowerCase().includes('dr') || s.toLowerCase().includes('fl') ||
        s.toLowerCase().includes('working') || s.toLowerCase().includes('warmup') ||
        s.toLowerCase().includes('dropset') || s.toLowerCase().includes('failure'));
      console.log(`  After long-press ${i + 1}: ${JSON.stringify(typeNodes)}`);
      findings.push(`[PROBE 03] After long-press ${i + 1}: ${JSON.stringify(typeNodes)}`);
      setTypesAfter.push(typeNodes);
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-set-type-cycle.png',
    });
  });

  // -------------------------------------------------------
  // Probe 4: Done-mark toggle
  // -------------------------------------------------------
  test('probe-04: done-mark toggle — complete and uncomplete', async () => {
    console.log('\n[PROBE 04] Done-mark toggle');

    const doneMark = page.locator(WORKOUT.markSetDone).first();
    const doneMarkVisible = await doneMark.isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`  Done-mark (uncompleted) visible: ${doneMarkVisible}`);
    findings.push(`[PROBE 04] Done-mark visible: ${doneMarkVisible}`);

    if (doneMarkVisible) {
      // Complete the set
      await doneMark.click();
      await page.waitForTimeout(1000);

      // Check state after completion
      const standingPr = await page.locator(SET_ROW.stateStandingPr).count();
      const completed = await page.locator(SET_ROW.stateCompleted).count();
      const completedMark = await page.locator(WORKOUT.setCompleted).count();

      console.log(`  After completion: standing_pr=${standingPr}, completed_non_pr=${completed}, setCompleted_marks=${completedMark}`);
      findings.push(`[PROBE 04] After completion: standing_pr=${standingPr}, completed_non_pr=${completed}`);

      // Check if rest timer appeared (should fire after completing a set)
      const restTimerVisible = await page.locator('text=Rest Timer').first().isVisible({ timeout: 1000 }).catch(() => false);
      const countdownVisible = await page.locator('[flt-semantics-identifier*="rest"]').first().isVisible({ timeout: 1000 }).catch(() => false);
      console.log(`  Rest timer text visible: ${restTimerVisible}, countdown visible: ${countdownVisible}`);
      findings.push(`[PROBE 04] Rest timer appeared: ${restTimerVisible || countdownVisible}`);

      // Dismiss rest timer if present
      if (restTimerVisible || countdownVisible) {
        // Tap outside the rest timer controls to dismiss (scrim tap)
        await page.mouse.click(180, 100);
        await page.waitForTimeout(500);
      }

      // Tap again to uncomplete
      const completedMarkEl = page.locator(WORKOUT.setCompleted).first();
      if (await completedMarkEl.isVisible({ timeout: 2000 }).catch(() => false)) {
        await completedMarkEl.click();
        await page.waitForTimeout(500);

        const revertedNone = await page.locator(SET_ROW.stateNone).count();
        const revertedPending = await page.locator(SET_ROW.statePendingPr).count();
        console.log(`  After uncomplete: none=${revertedNone}, pending=${revertedPending}`);
        findings.push(`[PROBE 04] After uncomplete: none=${revertedNone}, pending=${revertedPending}`);
      } else {
        console.log('  Could not find completed mark to re-tap');
        findings.push('[PROBE 04] Could not uncomplete: completed mark not found for re-tap');
      }
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-done-mark.png',
    });
  });

  // -------------------------------------------------------
  // Probe 5: 600ms done-mark lock on newly-added set
  // -------------------------------------------------------
  test('probe-05: 600ms done-mark lock on newly-added set', async () => {
    console.log('\n[PROBE 05] 600ms lock on newly-added set');

    // Count completed sets before adding
    const completedBefore = await page.locator(WORKOUT.setCompleted).count() +
                            await page.locator(SET_ROW.stateStandingPr).count() +
                            await page.locator(SET_ROW.stateCompleted).count();
    console.log(`  Completed sets before: ${completedBefore}`);

    // Add a new set
    const addSetBtn = page.locator(WORKOUT.addSetButton);
    if (!(await addSetBtn.isVisible({ timeout: 5000 }).catch(() => false))) {
      findings.push('[PROBE 05] SKIPPED: Add Set button not visible');
      return;
    }

    await addSetBtn.click();
    // IMMEDIATELY try to tap done-mark within 200ms (well within the 600ms lock)
    const t0 = Date.now();

    const allDoneMarks = page.locator(WORKOUT.markSetDone);
    const newDoneMark = allDoneMarks.last();

    // Tap as fast as possible
    if (await newDoneMark.isVisible({ timeout: 400 }).catch(() => false)) {
      const elapsed = Date.now() - t0;
      console.log(`  Tapping done-mark ${elapsed}ms after addSet`);
      await newDoneMark.click();
      await page.waitForTimeout(500);

      const completedAfter = await page.locator(WORKOUT.setCompleted).count() +
                              await page.locator(SET_ROW.stateStandingPr).count() +
                              await page.locator(SET_ROW.stateCompleted).count();

      const lockFired = completedAfter <= completedBefore;
      console.log(`  Completed after lock test: ${completedAfter} (was ${completedBefore}). Lock fired: ${lockFired}`);
      findings.push(`[PROBE 05] Tap at ${elapsed}ms: completed=${completedAfter} (before=${completedBefore}). Lock ${lockFired ? 'FIRED correctly' : 'DID NOT FIRE — bug?'}`);
    } else {
      findings.push('[PROBE 05] Done-mark not visible within 400ms of add — could not test lock');
    }
  });

  // -------------------------------------------------------
  // Probe 6: PR state transitions — drive all 5 states
  // -------------------------------------------------------
  test('probe-06: PR row state transitions — drive all 5 states', async () => {
    console.log('\n[PROBE 06] PR state transitions');

    // Complete first uncompleted set → should be standingPr on a fresh user
    const doneMarks = page.locator(WORKOUT.markSetDone);
    const doneCount = await doneMarks.count();
    console.log(`  Uncompleted sets: ${doneCount}`);

    if (doneCount > 0) {
      await doneMarks.first().click();
      await page.waitForTimeout(1500); // wait for state update + rest timer

      // Dismiss rest timer if present
      await page.mouse.click(180, 100);
      await page.waitForTimeout(500);

      const standing1 = await page.locator(SET_ROW.stateStandingPr).count();
      const nonPr1 = await page.locator(SET_ROW.stateCompleted).count();
      console.log(`  After first complete: standing_pr=${standing1}, non_pr=${nonPr1}`);
      findings.push(`[PROBE 06] State 1 (first set complete): standing_pr=${standing1}, non_pr=${nonPr1}`);

      await page.screenshot({
        path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-standing-pr.png',
      });

      // Add second set with HIGHER weight → first becomes superseded
      const addSetBtn = page.locator(WORKOUT.addSetButton);
      if (await addSetBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await addSetBtn.click();
        await page.waitForTimeout(500);

        // Increment weight on the new set by clicking + several times
        const plusButtons = page.locator('role=button[name="+"]');
        const plusCount = await plusButtons.count();
        const lastPlus = plusButtons.last();
        for (let i = 0; i < 5; i++) {
          await lastPlus.click();
          await page.waitForTimeout(100);
        }

        // Check pending PR state on new set
        const pendingPr = await page.locator(SET_ROW.statePendingPr).count();
        console.log(`  Second set (higher weight) pending PR: ${pendingPr}`);
        findings.push(`[PROBE 06] Second set pendingPR: ${pendingPr}`);

        // Complete second set
        const updatedDoneMarks = page.locator(WORKOUT.markSetDone);
        if (await updatedDoneMarks.last().isVisible({ timeout: 2000 }).catch(() => false)) {
          await updatedDoneMarks.last().click();
          await page.waitForTimeout(1500);
          await page.mouse.click(180, 100); // dismiss rest timer
          await page.waitForTimeout(500);

          const superseded = await page.locator(SET_ROW.stateSupersededPr).count();
          const standing2 = await page.locator(SET_ROW.stateStandingPr).count();
          console.log(`  After second complete: superseded=${superseded}, standing=${standing2}`);
          findings.push(`[PROBE 06] State 2 (second set complete, higher): superseded=${superseded}, standing=${standing2}`);

          await page.screenshot({
            path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-superseded-pr.png',
          });

          // Add third set with LOWER weight → should be completedNonPr
          if (await addSetBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
            await addSetBtn.click();
            await page.waitForTimeout(500);

            // Decrement weight substantially on new set
            const minusButtons = page.locator('role=button[name="-"]');
            const lastMinus = minusButtons.last();
            for (let i = 0; i < 12; i++) {
              await lastMinus.click();
              await page.waitForTimeout(80);
            }

            // Check pending PR state (should be none since weight is lower)
            const pendingPr3 = await page.locator(SET_ROW.statePendingPr).count();
            const none3 = await page.locator(SET_ROW.stateNone).count();
            console.log(`  Third set (lower weight) state: pending_pr=${pendingPr3}, none=${none3}`);
            findings.push(`[PROBE 06] Third set state (lower weight): pending_pr=${pendingPr3}, none=${none3}`);

            // Complete third set
            const finalDoneMarks = page.locator(WORKOUT.markSetDone);
            if (await finalDoneMarks.last().isVisible({ timeout: 2000 }).catch(() => false)) {
              await finalDoneMarks.last().click();
              await page.waitForTimeout(1500);
              await page.mouse.click(180, 100); // dismiss rest timer
              await page.waitForTimeout(500);

              const superseded3 = await page.locator(SET_ROW.stateSupersededPr).count();
              const standing3 = await page.locator(SET_ROW.stateStandingPr).count();
              const completedNonPr = await page.locator(SET_ROW.stateCompleted).count();
              console.log(`  After third (lower) complete: superseded=${superseded3}, standing=${standing3}, non_pr=${completedNonPr}`);
              findings.push(`[PROBE 06] State 3 (third lower set): superseded=${superseded3}, standing=${standing3}, non_pr=${completedNonPr}`);

              await page.screenshot({
                path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-all-pr-states.png',
              });
            }
          }
        }
      }
    }

    // Log full semantics at end of PR probe
    const finalSemantics = await allSemantics();
    console.log(`  Final screen (${finalSemantics.length} nodes):`);
    finalSemantics.slice(0, 20).forEach(s => console.log(`    ${s}`));
  });

  // -------------------------------------------------------
  // Probe 7: Swipe-to-delete + undo
  // -------------------------------------------------------
  test('probe-07: dismissible swipe-to-delete and undo', async () => {
    console.log('\n[PROBE 07] Swipe-to-delete');

    // Add a fresh set so we have something to delete
    const addSetBtn = page.locator(WORKOUT.addSetButton);
    if (await addSetBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await addSetBtn.click();
      await page.waitForTimeout(500);
    }

    const countBefore = await page.locator(SET_ROW.stateNone).count() +
                        await page.locator(SET_ROW.statePendingPr).count() +
                        await page.locator(SET_ROW.stateCompleted).count() +
                        await page.locator(SET_ROW.stateStandingPr).count() +
                        await page.locator(SET_ROW.stateSupersededPr).count();
    console.log(`  Set rows before swipe: ${countBefore}`);

    // Find a row to swipe — target the newest (pending/none) row
    const targetRows = [
      ...await page.locator(SET_ROW.stateNone).all(),
      ...await page.locator(SET_ROW.statePendingPr).all(),
    ];

    if (targetRows.length === 0) {
      findings.push('[PROBE 07] SKIPPED: no un-completed set rows to swipe');
      return;
    }

    const targetRow = targetRows[targetRows.length - 1];
    const box = await targetRow.boundingBox();
    if (!box) {
      findings.push('[PROBE 07] SKIPPED: could not get bounding box');
      return;
    }

    console.log(`  Swiping row at y=${box.y.toFixed(0)}, height=${box.height.toFixed(0)}`);

    // Full left swipe
    const startX = box.x + box.width * 0.8;
    const endX = box.x + 5;
    const midY = box.y + box.height / 2;

    await page.mouse.move(startX, midY);
    await page.mouse.down();
    // Slow drag to simulate realistic swipe
    const steps = 10;
    for (let i = 1; i <= steps; i++) {
      await page.mouse.move(startX + (endX - startX) * (i / steps), midY);
      await page.waitForTimeout(20);
    }
    await page.mouse.up();
    await page.waitForTimeout(800);

    const countAfterSwipe = await page.locator(SET_ROW.stateNone).count() +
                             await page.locator(SET_ROW.statePendingPr).count() +
                             await page.locator(SET_ROW.stateCompleted).count() +
                             await page.locator(SET_ROW.stateStandingPr).count() +
                             await page.locator(SET_ROW.stateSupersededPr).count();
    console.log(`  Rows after swipe: ${countAfterSwipe} (was ${countBefore})`);
    findings.push(`[PROBE 07] Rows after swipe: ${countAfterSwipe} (before=${countBefore})`);

    // Check for undo snackbar
    const undoBtn = page.locator('text=Undo').first();
    const undoVisible = await undoBtn.isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`  Undo snackbar visible: ${undoVisible}`);
    findings.push(`[PROBE 07] Undo snackbar visible: ${undoVisible}`);

    if (undoVisible) {
      // Tap undo
      await undoBtn.click();
      await page.waitForTimeout(500);
      const countAfterUndo = await page.locator(SET_ROW.stateNone).count() +
                              await page.locator(SET_ROW.statePendingPr).count() +
                              await page.locator(SET_ROW.stateCompleted).count() +
                              await page.locator(SET_ROW.stateStandingPr).count() +
                              await page.locator(SET_ROW.stateSupersededPr).count();
      console.log(`  Rows after undo: ${countAfterUndo} (expected ${countBefore})`);
      findings.push(`[PROBE 07] Rows after undo: ${countAfterUndo} (expected ${countBefore}). Undo ${countAfterUndo === countBefore ? 'WORKED' : 'FAILED'}`);
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-swipe-delete.png',
    });
  });

  // -------------------------------------------------------
  // Probe 8: Tap-target sizing on 360×780
  // -------------------------------------------------------
  test('probe-08: tap-target size — stepper buttons >= 40x48dp on 360x780', async () => {
    console.log('\n[PROBE 08] Tap-target size assessment');

    // Minimum per Material spec: 40dp wide × 48dp tall
    const MIN_W = 40; // px (at DPR 2.0, these are CSS px)
    const MIN_H = 48;

    const findings_08: string[] = [];

    // Check + buttons
    const plusButtons = page.locator('role=button[name="+"]');
    const plusCount = await plusButtons.count();
    for (let i = 0; i < Math.min(plusCount, 6); i++) {
      const box = await plusButtons.nth(i).boundingBox();
      if (box) {
        const tooSmall = box.width < MIN_W || box.height < MIN_H;
        const msg = `plus[${i}]: ${box.width.toFixed(1)}×${box.height.toFixed(1)} px @ (${box.x.toFixed(0)},${box.y.toFixed(0)}) ${tooSmall ? '<<< TOO SMALL' : 'OK'}`;
        console.log(`  ${msg}`);
        findings_08.push(msg);
      }
    }

    // Check - buttons
    const minusButtons = page.locator('role=button[name="-"]');
    const minusCount = await minusButtons.count();
    for (let i = 0; i < Math.min(minusCount, 6); i++) {
      const box = await minusButtons.nth(i).boundingBox();
      if (box) {
        const tooSmall = box.width < MIN_W || box.height < MIN_H;
        const msg = `minus[${i}]: ${box.width.toFixed(1)}×${box.height.toFixed(1)} px @ (${box.x.toFixed(0)},${box.y.toFixed(0)}) ${tooSmall ? '<<< TOO SMALL' : 'OK'}`;
        console.log(`  ${msg}`);
        findings_08.push(msg);
      }
    }

    // Check done-mark buttons
    const doneMarks = page.locator(WORKOUT.markSetDone);
    const doneCount = await doneMarks.count();
    for (let i = 0; i < Math.min(doneCount, 4); i++) {
      const box = await doneMarks.nth(i).boundingBox();
      if (box) {
        const tooSmall = box.width < MIN_W || box.height < MIN_H;
        const msg = `done-mark[${i}]: ${box.width.toFixed(1)}×${box.height.toFixed(1)} px ${tooSmall ? '<<< TOO SMALL' : 'OK'}`;
        console.log(`  ${msg}`);
        findings_08.push(msg);
      }
    }

    // Check completed marks
    const completedMarks = page.locator(WORKOUT.setCompleted);
    const compCount = await completedMarks.count();
    for (let i = 0; i < Math.min(compCount, 4); i++) {
      const box = await completedMarks.nth(i).boundingBox();
      if (box) {
        const tooSmall = box.width < MIN_W || box.height < MIN_H;
        const msg = `completed-mark[${i}]: ${box.width.toFixed(1)}×${box.height.toFixed(1)} px ${tooSmall ? '<<< TOO SMALL' : 'OK'}`;
        console.log(`  ${msg}`);
        findings_08.push(msg);
      }
    }

    // Check add-set button
    const addSetBtn = page.locator(WORKOUT.addSetButton);
    if (await addSetBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      const box = await addSetBtn.boundingBox();
      if (box) {
        const msg = `add-set: ${box.width.toFixed(1)}×${box.height.toFixed(1)} px`;
        console.log(`  ${msg}`);
        findings_08.push(msg);
      }
    }

    findings.push(`[PROBE 08] Tap targets:\n  ${findings_08.join('\n  ')}`);

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-tap-targets.png',
    });
  });

  // -------------------------------------------------------
  // Probe 9: Rapid-fire stepper (10 taps in 2 seconds)
  // -------------------------------------------------------
  test('probe-09: rapid-fire stepper — 10 taps in 2 seconds stays coherent', async () => {
    console.log('\n[PROBE 09] Rapid-fire stepper');

    const plusBtn = page.locator('role=button[name="+"]').first();
    if (!(await plusBtn.isVisible({ timeout: 3000 }).catch(() => false))) {
      findings.push('[PROBE 09] SKIPPED: + button not visible');
      return;
    }

    const t0 = Date.now();
    let errors = 0;

    // 10 rapid taps
    for (let i = 0; i < 10; i++) {
      try {
        await plusBtn.click({ timeout: 500 });
      } catch (e) {
        errors++;
      }
      await page.waitForTimeout(150); // ~150ms between taps = ~1.5s total
    }

    const elapsed = Date.now() - t0;
    console.log(`  10 taps in ${elapsed}ms (${errors} errors)`);

    // Check for console errors from rapid tapping
    const consoleErrors = findings.filter(f => f.startsWith('[CONSOLE ERROR]'));
    console.log(`  Console errors so far: ${consoleErrors.length}`);
    findings.push(`[PROBE 09] Rapid-fire: ${10 - errors}/10 taps succeeded in ${elapsed}ms. Console errors so far: ${consoleErrors.length}`);

    // Check final state is coherent
    const finalSemantics = await allSemantics();
    const weightVals = finalSemantics.filter(s => s.includes('kg') || /\[\w+\/\].*\d+/.test(s));
    console.log(`  Final weight semantics: ${JSON.stringify(weightVals.slice(0, 5))}`);
    findings.push(`[PROBE 09] After rapid-fire: ${JSON.stringify(weightVals.slice(0, 5))}`);
  });

  // -------------------------------------------------------
  // Probe 10: Final screenshot + console error summary
  // -------------------------------------------------------
  test('probe-10: session summary — console errors + final state', async () => {
    console.log('\n[PROBE 10] Session summary');

    const allErrors = findings.filter(f =>
      f.startsWith('[CONSOLE ERROR]') || f.startsWith('[PAGE ERROR]') || f.startsWith('[HTTP '));
    console.log(`  Total runtime errors: ${allErrors.length}`);
    allErrors.forEach(e => console.log(`    ${e}`));

    const allFindings = findings.filter(f => !f.startsWith('['));
    console.log(`  Total finding entries: ${findings.length}`);

    // Final complete screenshot
    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-final.png',
    });

    // Dump complete screen semantics for offline analysis
    const finalSemantics = await allSemantics();
    console.log(`\n  FINAL SCREEN SEMANTICS (${finalSemantics.length} nodes):`);
    finalSemantics.forEach(s => console.log(`    ${s}`));

    findings.push(`[PROBE 10] Final: ${allErrors.length} errors, ${findings.length} findings logged`);
  });
});
