/**
 * Charter A — Refined pass for probes that need a second look.
 * Specifically: weight dialog, tap targets, PR state semantics,
 * and set-type label visibility.
 * Guard: EXPL_CHARTER_A_REFINED=1
 */

import { test, expect, Page, BrowserContext } from '@playwright/test';
import { WORKOUT, HOME, NAV, SET_ROW, GAMIFICATION } from '../helpers/selectors';
import { waitForAppReady, flutterFill } from '../helpers/app';
import { login } from '../helpers/auth';
import { startEmptyWorkout, addExercise, setWeight, setReps, completeSet } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

const RUN = process.env.EXPL_CHARTER_A_REFINED === '1';
const VIEWPORT = { width: 360, height: 780 };

test.describe('Charter A — Refined pass (weight dialog + tap targets + PR states)', () => {
  test.skip(!RUN, 'Set EXPL_CHARTER_A_REFINED=1 to run');
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
    page.on('console', (msg) => {
      if (msg.type() === 'error') findings.push(`[CONSOLE ERROR] ${msg.text()}`);
    });
    page.on('response', (r) => {
      if (r.status() >= 400) findings.push(`[HTTP ${r.status()}] ${r.url()}`);
    });

    // Use fullWorkout user - already has prior workouts (lapsed state)
    const user = getUser('fullWorkout');
    await login(page, user.email, user.password);
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    console.log('[setup] Ready on /workout/active with Barbell Bench Press');
  });

  test.afterAll(async () => {
    console.log('\n=== REFINED FINDINGS ===');
    findings.forEach(f => console.log(f));
    await context.close();
  });

  // -------------------------------------------------------
  // Refined Probe 1: Complete accessibility tree dump
  // -------------------------------------------------------
  test('refined-01: full accessibility tree dump of active workout', async () => {
    console.log('\n[REFINED-01] Full AOM dump');

    // Use Playwright's accessibility tree (not flt-semantics DOM)
    const snapshot = await page.accessibility.snapshot();
    console.log('  AOM snapshot:\n' + JSON.stringify(snapshot, null, 2).slice(0, 5000));
    findings.push(`[REFINED-01] AOM: ${JSON.stringify(snapshot, null, 2).slice(0, 2000)}`);

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-initial.png',
    });
  });

  // -------------------------------------------------------
  // Refined Probe 2: Tap-target sizes on actual set row
  // -------------------------------------------------------
  test('refined-02: tap-target sizes — measure all interactive elements', async () => {
    console.log('\n[REFINED-02] Tap-target measurement');

    const MIN_W = 40; // Material minimum in dp/CSS px
    const MIN_H = 48;

    // All interactive elements via their AOM roles
    const controls = [
      { label: 'weight-minus', loc: page.locator('role=button[name="-"]').first() },
      { label: 'weight-plus', loc: page.locator('role=button[name="+"]').first() },
      { label: 'reps-minus', loc: page.locator('role=button[name="-"]').last() },
      { label: 'reps-plus', loc: page.locator('role=button[name="+"]').last() },
      { label: 'done-mark', loc: page.locator(WORKOUT.markSetDone).first() },
      { label: 'add-set', loc: page.locator(WORKOUT.addSetButton) },
      { label: 'finish', loc: page.locator(WORKOUT.finishButton) },
      { label: 'add-exercise-fab', loc: page.locator(WORKOUT.addExerciseFab) },
    ];

    const report: string[] = [];
    for (const c of controls) {
      const box = await c.loc.boundingBox({ timeout: 5000 }).catch(() => null);
      if (box) {
        const tooSmall = box.width < MIN_W || box.height < MIN_H;
        const line = `${c.label}: ${box.width.toFixed(1)}w × ${box.height.toFixed(1)}h at (${box.x.toFixed(0)},${box.y.toFixed(0)}) ${tooSmall ? '<< BELOW MINIMUM' : 'OK'}`;
        report.push(line);
        console.log(`  ${line}`);
      } else {
        const line = `${c.label}: NOT FOUND`;
        report.push(line);
        console.log(`  ${line}`);
      }
    }

    findings.push(`[REFINED-02] Tap targets:\n  ${report.join('\n  ')}`);

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-tap-targets.png',
    });
  });

  // -------------------------------------------------------
  // Refined Probe 3: Weight dialog — full input testing
  // -------------------------------------------------------
  test('refined-03: weight dialog — tap value, test all edge case inputs', async () => {
    console.log('\n[REFINED-03] Weight dialog inputs');

    // The weight value is a GestureDetector that opens a dialog.
    // In existing tests, setWeight helper uses 'role=button[name*="Weight value"]'.first()
    const weightValueBtn = page.locator('role=button[name*="Weight value"]').first();
    const altWeightBtn = page.locator('[flt-semantics-identifier*="weight"]').first();

    // Try the weight value button first
    let opened = false;
    const wBox = await weightValueBtn.boundingBox({ timeout: 5000 }).catch(() => null);
    console.log(`  Weight value button box: ${JSON.stringify(wBox)}`);

    if (wBox) {
      await weightValueBtn.click();
      await page.waitForTimeout(500);
      const dialogVisible = await page.locator('text=Enter weight').isVisible({ timeout: 2000 }).catch(() => false);
      console.log(`  Dialog visible after click: ${dialogVisible}`);
      opened = dialogVisible;
      findings.push(`[REFINED-03] Weight dialog opened: ${dialogVisible}`);
    }

    if (opened) {
      // The hidden input proxy
      const input = page.locator('input').last();

      // Test 1: valid decimal 102.5
      await input.fill('');
      await page.keyboard.press('Control+a');
      await page.keyboard.type('102.5', { delay: 30 });
      let val = await input.inputValue();
      console.log(`  After '102.5': "${val}"`);
      findings.push(`[REFINED-03] '102.5' → input shows: "${val}"`);

      // Confirm
      const okBtn = page.locator('role=button[name="OK"]');
      if (await okBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await okBtn.click();
      }
      await page.waitForTimeout(500);

      // Verify stepper displays 102.5
      const aomAfter = await page.accessibility.snapshot();
      const weightNode = JSON.stringify(aomAfter).includes('102.5');
      console.log(`  AOM shows 102.5 after submit: ${weightNode}`);
      findings.push(`[REFINED-03] After submit 102.5, AOM has 102.5: ${weightNode}`);

      // Decrement and check step behavior
      const minusBtn = page.locator('role=button[name="-"]').first();
      await minusBtn.click();
      await page.waitForTimeout(300);
      const aomAfterDec = await page.accessibility.snapshot();
      const aomStr = JSON.stringify(aomAfterDec);
      // Look for weight values near 100
      const match = aomStr.match(/"name":"(\d+(?:\.\d+)?) kg"/g);
      console.log(`  After decrement from 102.5: ${JSON.stringify(match)}`);
      findings.push(`[REFINED-03] After -1 from 102.5: ${JSON.stringify(match)}`);

      // Re-open for comma test
      const weightBtn2 = page.locator('role=button[name*="Weight value"]').first();
      if (await weightBtn2.isVisible({ timeout: 3000 }).catch(() => false)) {
        await weightBtn2.click();
        await page.waitForTimeout(500);

        if (await page.locator('text=Enter weight').isVisible({ timeout: 2000 }).catch(() => false)) {
          const input2 = page.locator('input').last();

          // Test comma decimal (BR locale)
          await input2.fill('');
          await page.keyboard.press('Control+a');
          await page.keyboard.type('102,5', { delay: 30 });
          val = await input2.inputValue();
          console.log(`  After '102,5': "${val}"`);
          findings.push(`[REFINED-03] '102,5' (comma decimal) → input shows: "${val}"`);

          // Test empty submit
          await input2.fill('');
          val = await input2.inputValue();
          console.log(`  After clear: "${val}"`);
          findings.push(`[REFINED-03] After clear → input shows: "${val}"`);

          // Test negative
          await page.keyboard.type('-5', { delay: 30 });
          val = await input2.inputValue();
          console.log(`  After '-5': "${val}"`);
          findings.push(`[REFINED-03] '-5' → input shows: "${val}"`);

          // Test very large
          await input2.fill('');
          await page.keyboard.type('9999', { delay: 30 });
          val = await input2.inputValue();
          console.log(`  After '9999': "${val}"`);
          findings.push(`[REFINED-03] '9999' → input shows: "${val}"`);

          // Test alpha-mixed
          await input2.fill('');
          await page.keyboard.type('abc123def', { delay: 30 });
          val = await input2.inputValue();
          console.log(`  After 'abc123def': "${val}"`);
          findings.push(`[REFINED-03] 'abc123def' → input shows: "${val}"`);

          // Escape to close
          await page.keyboard.press('Escape');
          await page.waitForTimeout(300);
        }
      }
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-weight-dialog.png',
    });
  });

  // -------------------------------------------------------
  // Refined Probe 4: Set-type long-press — observe AOM changes
  // -------------------------------------------------------
  test('refined-04: set-type long-press — AOM-based observation', async () => {
    console.log('\n[REFINED-04] Set-type AOM observation');

    // Get AOM before any long-press
    const aomBefore = JSON.stringify(await page.accessibility.snapshot());
    console.log(`  AOM before: ${aomBefore.slice(0, 500)}`);
    findings.push(`[REFINED-04] AOM before: ${aomBefore.slice(0, 500)}`);

    // Find the set row and the set-number area
    const setRowNone = page.locator(SET_ROW.stateNone).first();
    const setRowPending = page.locator(SET_ROW.statePendingPr).first();

    let targetRow = null;
    let targetBox = null;

    const noneBox = await setRowNone.boundingBox({ timeout: 3000 }).catch(() => null);
    const pendingBox = await setRowPending.boundingBox({ timeout: 3000 }).catch(() => null);

    if (noneBox) { targetBox = noneBox; console.log('  Using none row'); }
    else if (pendingBox) { targetBox = pendingBox; console.log('  Using pending row'); }

    if (targetBox) {
      console.log(`  Row box: x=${targetBox.x.toFixed(0)} y=${targetBox.y.toFixed(0)} w=${targetBox.width.toFixed(0)} h=${targetBox.height.toFixed(0)}`);

      // Set-number cell: leftmost ~55px of the row
      const setNumX = targetBox.x + 27; // center of the ~55px set-num column
      const setNumY = targetBox.y + targetBox.height / 2;
      console.log(`  Long-pressing at (${setNumX.toFixed(0)}, ${setNumY.toFixed(0)})`);

      // Long-press 1
      await page.mouse.move(setNumX, setNumY);
      await page.mouse.down();
      await page.waitForTimeout(1000); // 1s hold
      await page.mouse.up();
      await page.waitForTimeout(800);

      const aomAfter1 = JSON.stringify(await page.accessibility.snapshot());
      console.log(`  AOM after long-press 1: ${aomAfter1.slice(0, 500)}`);
      findings.push(`[REFINED-04] AOM after LP1: ${aomAfter1.slice(0, 500)}`);

      await page.screenshot({
        path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-set-type-1.png',
      });

      // Long-press 2
      await page.mouse.move(setNumX, setNumY);
      await page.mouse.down();
      await page.waitForTimeout(1000);
      await page.mouse.up();
      await page.waitForTimeout(800);

      const aomAfter2 = JSON.stringify(await page.accessibility.snapshot());
      console.log(`  AOM after long-press 2: ${aomAfter2.slice(0, 500)}`);
      findings.push(`[REFINED-04] AOM after LP2: ${aomAfter2.slice(0, 500)}`);

      // Long-press 3
      await page.mouse.move(setNumX, setNumY);
      await page.mouse.down();
      await page.waitForTimeout(1000);
      await page.mouse.up();
      await page.waitForTimeout(800);

      const aomAfter3 = JSON.stringify(await page.accessibility.snapshot());
      findings.push(`[REFINED-04] AOM after LP3: ${aomAfter3.slice(0, 500)}`);

      // Long-press 4 (back to WK)
      await page.mouse.move(setNumX, setNumY);
      await page.mouse.down();
      await page.waitForTimeout(1000);
      await page.mouse.up();
      await page.waitForTimeout(800);

      const aomAfter4 = JSON.stringify(await page.accessibility.snapshot());
      findings.push(`[REFINED-04] AOM after LP4: ${aomAfter4.slice(0, 500)}`);

      await page.screenshot({
        path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-set-type-4.png',
      });
    } else {
      findings.push('[REFINED-04] SKIPPED: no set row found');
    }
  });

  // -------------------------------------------------------
  // Refined Probe 5: PR state — complete set as fresh user PR
  // -------------------------------------------------------
  test('refined-05: PR state — complete set and observe row state', async () => {
    console.log('\n[REFINED-05] PR state after completion');

    // The fullWorkout user has PRs. We need to beat them.
    // Use setWeight to enter a very high weight to guarantee PR
    await setWeight(page, '500'); // Unrealistically high — should always be a PR
    await setReps(page, '1');
    await page.waitForTimeout(500);

    // Check AOM before complete
    const aomBefore = JSON.stringify(await page.accessibility.snapshot());
    const pendingBefore = await page.locator(SET_ROW.statePendingPr).count();
    const noneBefore = await page.locator(SET_ROW.stateNone).count();
    console.log(`  Before complete: pending_pr=${pendingBefore}, none=${noneBefore}`);
    findings.push(`[REFINED-05] Before complete: pending_pr=${pendingBefore}, none=${noneBefore}`);

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-pre-complete.png',
    });

    // Complete the set
    const doneMark = page.locator(WORKOUT.markSetDone).first();
    if (await doneMark.isVisible({ timeout: 3000 }).catch(() => false)) {
      await doneMark.click();
      await page.waitForTimeout(2000); // wait for state update

      // Check rest timer
      const aomAfterComplete = await page.accessibility.snapshot();
      const aomStr = JSON.stringify(aomAfterComplete);
      console.log(`  AOM after complete (first 800): ${aomStr.slice(0, 800)}`);
      findings.push(`[REFINED-05] AOM after complete: ${aomStr.slice(0, 800)}`);

      // Check PR states
      const standingPr = await page.locator(SET_ROW.stateStandingPr).count();
      const completedNonPr = await page.locator(SET_ROW.stateCompleted).count();
      const superseded = await page.locator(SET_ROW.stateSupersededPr).count();
      console.log(`  PR states: standing=${standingPr}, non_pr=${completedNonPr}, superseded=${superseded}`);
      findings.push(`[REFINED-05] After complete (500kg, 1 rep): standing=${standingPr}, non_pr=${completedNonPr}`);

      await page.screenshot({
        path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-post-complete.png',
      });

      // Dismiss rest timer if present
      const restTimerVisible = aomStr.includes('Rest') || aomStr.includes('1:3') || aomStr.includes('Skip');
      console.log(`  Rest timer in AOM: ${restTimerVisible}`);
      if (restTimerVisible) {
        // Click Skip button
        const skipBtn = page.locator('role=button[name="Skip"]').first();
        if (await skipBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
          await skipBtn.click();
          findings.push('[REFINED-05] Dismissed rest timer via Skip button');
        } else {
          // Tap outside
          await page.mouse.click(180, 100);
          findings.push('[REFINED-05] Dismissed rest timer via scrim tap');
        }
        await page.waitForTimeout(500);
      }
    }
  });

  // -------------------------------------------------------
  // Refined Probe 6: Swipe-to-delete on small viewport
  // -------------------------------------------------------
  test('refined-06: swipe-to-delete + undo on BR-1', async () => {
    console.log('\n[REFINED-06] Swipe-to-delete');

    // Add a new set to have something to delete
    const addSetBtn = page.locator(WORKOUT.addSetButton);
    if (!(await addSetBtn.isVisible({ timeout: 3000 }).catch(() => false))) {
      findings.push('[REFINED-06] SKIPPED: Add Set not visible');
      return;
    }
    await addSetBtn.click();
    await page.waitForTimeout(500);

    // Count rows
    const countBefore = await page.locator(SET_ROW.stateNone).count() +
                        await page.locator(SET_ROW.statePendingPr).count() +
                        await page.locator(SET_ROW.stateCompleted).count() +
                        await page.locator(SET_ROW.stateStandingPr).count() +
                        await page.locator(SET_ROW.stateSupersededPr).count();
    console.log(`  Rows before: ${countBefore}`);

    // Find the newest row
    const allNoneRows = await page.locator(SET_ROW.stateNone).all();
    const allPendingRows = await page.locator(SET_ROW.statePendingPr).all();
    const targetRows = [...allNoneRows, ...allPendingRows];

    if (targetRows.length === 0) {
      findings.push('[REFINED-06] SKIPPED: no swipeable rows');
      return;
    }

    const targetRow = targetRows[targetRows.length - 1];
    const box = await targetRow.boundingBox();

    if (!box) {
      findings.push('[REFINED-06] SKIPPED: no bounding box');
      return;
    }

    console.log(`  Row to swipe: y=${box.y.toFixed(0)}, height=${box.height.toFixed(0)}`);

    // Perform fast swipe (left)
    const startX = box.x + box.width * 0.75;
    const endX = box.x + 2;
    const midY = box.y + box.height / 2;

    await page.mouse.move(startX, midY);
    await page.mouse.down();
    for (let i = 1; i <= 15; i++) {
      await page.mouse.move(startX + (endX - startX) * (i / 15), midY);
      await page.waitForTimeout(15);
    }
    await page.mouse.up();
    await page.waitForTimeout(1000);

    const countAfter = await page.locator(SET_ROW.stateNone).count() +
                       await page.locator(SET_ROW.statePendingPr).count() +
                       await page.locator(SET_ROW.stateCompleted).count() +
                       await page.locator(SET_ROW.stateStandingPr).count() +
                       await page.locator(SET_ROW.stateSupersededPr).count();

    console.log(`  Rows after swipe: ${countAfter} (was ${countBefore})`);
    findings.push(`[REFINED-06] After swipe: rows=${countAfter} (before=${countBefore}). ${countAfter < countBefore ? 'ROW DELETED' : 'swipe did not delete'}`);

    // Undo snackbar
    const undoVisible = await page.locator('text=Undo').first().isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`  Undo snackbar: ${undoVisible}`);
    findings.push(`[REFINED-06] Undo snackbar: ${undoVisible}`);

    if (undoVisible) {
      await page.locator('text=Undo').first().click();
      await page.waitForTimeout(500);
      const countAfterUndo = await page.locator(SET_ROW.stateNone).count() +
                              await page.locator(SET_ROW.statePendingPr).count() +
                              await page.locator(SET_ROW.stateCompleted).count() +
                              await page.locator(SET_ROW.stateStandingPr).count() +
                              await page.locator(SET_ROW.stateSupersededPr).count();
      console.log(`  Rows after undo: ${countAfterUndo} (expected ${countBefore})`);
      findings.push(`[REFINED-06] After undo: rows=${countAfterUndo} (expected ${countBefore}). ${countAfterUndo === countBefore ? 'UNDO WORKED' : 'UNDO FAILED'}`);
    }

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-swipe.png',
    });
  });

  // -------------------------------------------------------
  // Refined Probe 7: Rest timer visibility + dismissal
  // -------------------------------------------------------
  test('refined-07: rest timer visibility and dismissal methods', async () => {
    console.log('\n[REFINED-07] Rest timer');

    // Complete a set to trigger rest timer
    const doneMark = page.locator(WORKOUT.markSetDone).first();
    if (!(await doneMark.isVisible({ timeout: 3000 }).catch(() => false))) {
      findings.push('[REFINED-07] SKIPPED: no done-mark visible');
      return;
    }

    await doneMark.click();
    await page.waitForTimeout(1000);

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-rest-timer.png',
    });

    // Check what's visible
    const aomSnapshot = JSON.stringify(await page.accessibility.snapshot());
    const hasSkip = aomSnapshot.includes('Skip');
    const hasMinus30 = aomSnapshot.includes('-30s') || aomSnapshot.includes('-30');
    const hasPlus30 = aomSnapshot.includes('+30s') || aomSnapshot.includes('+30');
    const hasTimer = /\d:\d\d/.test(aomSnapshot);

    console.log(`  Rest timer: skip=${hasSkip}, -30=${hasMinus30}, +30=${hasPlus30}, countdown=${hasTimer}`);
    findings.push(`[REFINED-07] Rest timer elements: skip=${hasSkip}, -30=${hasMinus30}, +30=${hasPlus30}, countdown=${hasTimer}`);

    // Try to click Skip
    const skipBtn = page.locator('role=button[name="Skip"]').first();
    const skipVisible = await skipBtn.isVisible({ timeout: 2000 }).catch(() => false);
    console.log(`  Skip button visible: ${skipVisible}`);
    findings.push(`[REFINED-07] Skip button visible in DOM: ${skipVisible}`);

    if (skipVisible) {
      await skipBtn.click();
      await page.waitForTimeout(500);
      const aomAfterSkip = JSON.stringify(await page.accessibility.snapshot());
      const timerGone = !(/\d:\d\d/.test(aomAfterSkip)) && !aomAfterSkip.includes('Skip');
      console.log(`  Timer dismissed after Skip: ${timerGone}`);
      findings.push(`[REFINED-07] Timer dismissed via Skip: ${timerGone}`);
    } else {
      // Try scrim tap
      await page.mouse.click(180, 100);
      await page.waitForTimeout(500);
      findings.push('[REFINED-07] Attempted scrim dismiss (Skip not available)');
    }
  });

  // -------------------------------------------------------
  // Refined Probe 8: Final session screenshot
  // -------------------------------------------------------
  test('refined-08: final state screenshot + AOM', async () => {
    console.log('\n[REFINED-08] Final state');

    const finalAom = await page.accessibility.snapshot();
    console.log(`  Final AOM: ${JSON.stringify(finalAom, null, 2).slice(0, 3000)}`);
    findings.push(`[REFINED-08] Final AOM: ${JSON.stringify(finalAom, null, 2).slice(0, 1000)}`);

    await page.screenshot({
      path: 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots/charter-A-BR-1-refined-final.png',
    });

    // Summary of all errors
    const errors = findings.filter(f => f.startsWith('[CONSOLE') || f.startsWith('[HTTP') || f.startsWith('[PAGE'));
    console.log(`  Total errors: ${errors.length}`);
    errors.forEach(e => console.log(`    ${e}`));
    findings.push(`[REFINED-08] Summary: ${errors.length} errors, ${findings.length} findings`);
  });
});
