/**
 * Charter B — Follow-up probes
 *
 * 1. Confirm rest timer AOM label format (to fix readRestTimer helper)
 * 2. Confirm: can weight entry dialog open while rest timer is active?
 * 3. Confirm P1-B3: rest timer continues during background (with corrected AOM read)
 * 4. Confirm offline + ConnectivityService (real network CDP offline)
 *
 * Guard: EXPL_CHARTER_B_FU=1
 */

import { test, expect, Page, BrowserContext } from '@playwright/test';
import { WORKOUT, HOME, OFFLINE } from '../helpers/selectors';
import { waitForAppReady } from '../helpers/app';
import { login } from '../helpers/auth';
import { startEmptyWorkout, addExercise, completeSet } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

const RUN = process.env['EXPL_CHARTER_B_FU'] === '1';
const VIEWPORT_PORTRAIT = { width: 393, height: 852 };
const SS_BASE = 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots';

test.describe('Charter B — Follow-up probes', () => {
  test.skip(!RUN, 'Set EXPL_CHARTER_B_FU=1 to run');
  test.use({ viewport: VIEWPORT_PORTRAIT });

  let page: Page;
  let context: BrowserContext;
  const findings: string[] = [];

  async function ss(name: string): Promise<void> {
    const path = `${SS_BASE}/charter-B-US-1-FU-${name}.png`;
    await page.screenshot({ path }).catch(() => {});
    console.log(`[screenshot] ${path}`);
  }

  // Dump all AOM labels to understand rest-timer semantics structure
  async function dumpAOM(): Promise<string[]> {
    return page.evaluate(() => {
      return Array.from(document.querySelectorAll('flt-semantics'))
        .map((el: Element) => {
          const label = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
          const id = el.getAttribute('flt-semantics-identifier') ?? '';
          const role = el.getAttribute('role') ?? '';
          return (label || id) ? `${role}/${id}: ${label.slice(0, 100)}` : '';
        })
        .filter(Boolean);
    });
  }

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({
      viewport: VIEWPORT_PORTRAIT,
      deviceScaleFactor: 3.0,
    });
    page = await context.newPage();
    page.on('console', (m) => { if (m.type() === 'error') findings.push(`[err] ${m.text()}`); });

    const user = getUser('fullCrash');
    await login(page, user.email, user.password);
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    console.log('[setup] ready');
  });

  test.afterAll(async () => {
    console.log('\n=== FU FINDINGS ===');
    findings.forEach(f => console.log(f));
    await context.close();
  });

  test('FU-1: dump AOM when rest timer is active', async () => {
    // Complete a set to trigger rest timer
    await completeSet(page, 0);
    await page.waitForTimeout(500);

    // DON'T dismiss — capture AOM immediately
    const aom = await dumpAOM();
    console.log('[FU-1] AOM with rest timer active:');
    aom.forEach(l => console.log('  ' + l));
    await ss('FU1-rest-timer-aom');

    // Look for rest timer related entries
    const timerEntries = aom.filter(l =>
      l.toLowerCase().includes('rest') ||
      l.toLowerCase().includes('timer') ||
      l.toLowerCase().includes('progressbar') ||
      /\d+:\d{2}/.test(l)
    );
    console.log('[FU-1] Timer-related AOM entries:', JSON.stringify(timerEntries));
    findings.push(`[FU-1] Rest timer AOM entries: ${JSON.stringify(timerEntries)}`);

    // Dismiss rest timer for next tests
    await page.mouse.click(196, 80);
    await page.waitForTimeout(500);
  });

  test('FU-2: weight dialog tap while rest timer is visible — layering bug?', async () => {
    // Add a set and complete to trigger rest timer
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(700);
    await completeSet(page, 0);
    await page.waitForTimeout(400);

    // Verify rest timer is showing
    const restTimerVisible = await page.locator('role=progressbar[name*="Rest timer"]').isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[FU-2] Rest timer visible: ${restTimerVisible}`);

    if (!restTimerVisible) {
      findings.push('[FU-2] SKIP: rest timer not visible');
      return;
    }

    // Attempt to tap the weight stepper value (behind the rest timer overlay)
    // This should NOT be possible if the overlay correctly absorbs pointer events
    const weightBtn = page.locator('role=button[name*="Weight value"]').last();
    const weightBtnBox = await weightBtn.boundingBox().catch(() => null);
    console.log(`[FU-2] Weight button box: ${JSON.stringify(weightBtnBox)}`);

    if (weightBtnBox) {
      // Try tapping weight button while rest timer is active
      await page.mouse.click(weightBtnBox.x + weightBtnBox.width / 2, weightBtnBox.y + weightBtnBox.height / 2);
      await page.waitForTimeout(500);

      const enterWeightVisible = await page.locator('text="Enter weight"').isVisible({ timeout: 2000 }).catch(() => false);
      console.log(`[FU-2] "Enter weight" dialog appeared while rest timer was active: ${enterWeightVisible}`);
      await ss('FU2-weight-dialog-during-rest-timer');

      if (enterWeightVisible) {
        findings.push('[BUG] FU-2: Weight entry dialog CAN be opened while rest timer overlay is active — rest timer scrim does NOT block pointer events to underlying widgets. Both overlays visible simultaneously.');
        // Dismiss weight dialog
        const cancel = page.locator('text="Cancel"');
        const hasCancel = await cancel.isVisible({ timeout: 2000 }).catch(() => false);
        if (hasCancel) await cancel.click();
        else await page.keyboard.press('Escape');
        await page.waitForTimeout(300);
      } else {
        findings.push('[OK] FU-2: Rest timer overlay correctly blocks tap-through to weight entry dialog');
      }
    }

    // Dismiss rest timer
    await page.mouse.click(196, 80);
    await page.waitForTimeout(500);
  });

  test('FU-3: rest timer continues ticking during background (corrected AOM read)', async () => {
    // Add and complete a set to trigger rest timer
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(700);
    await completeSet(page, 0);
    await page.waitForTimeout(600);

    // Read rest timer via role=progressbar (correct selector)
    const restTimerBefore = await page.locator('role=progressbar[name*="Rest timer"]').isVisible({ timeout: 3000 }).catch(() => false);
    // Read the timer value via AOM dump
    const aomBefore = await dumpAOM();
    const timerLineBefore = aomBefore.find(l => /\d+:\d{2}/.test(l));
    console.log(`[FU-3] Rest timer visible: ${restTimerBefore}`);
    console.log(`[FU-3] Timer line before BG: ${timerLineBefore}`);

    if (!restTimerBefore) {
      findings.push('[FU-3] SKIP: rest timer not visible');
      return;
    }

    // Background 5 seconds
    const t0 = Date.now();
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'hidden', writable: true, configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await page.waitForTimeout(5000);
    const bgMs = Date.now() - t0;
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: true, configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await page.waitForTimeout(800);

    const aomAfter = await dumpAOM();
    const timerLineAfter = aomAfter.find(l => /\d+:\d{2}/.test(l));
    console.log(`[FU-3] Timer line after ${Math.round(bgMs / 1000)}s BG: ${timerLineAfter}`);
    await ss('FU3-rest-timer-bg');

    // Parse timer values
    const parseTimerFromLine = (line?: string): number | null => {
      if (!line) return null;
      const match = line.match(/(\d+):(\d{2})/);
      if (!match) return null;
      return parseInt(match[1]) * 60 + parseInt(match[2]);
    };
    const secsBefore = parseTimerFromLine(timerLineBefore);
    const secsAfter = parseTimerFromLine(timerLineAfter);
    const bgSecs = Math.round(bgMs / 1000);
    console.log(`[FU-3] secsBefore=${secsBefore} secsAfter=${secsAfter} bgSecs=${bgSecs}`);

    if (secsBefore !== null && secsAfter !== null) {
      const delta = secsBefore - secsAfter;
      const accurate = Math.abs(delta - bgSecs) <= 3;
      console.log(`[FU-3] Timer delta=${delta}s (expected ~${bgSecs}s) accurate=${accurate}`);
      if (accurate) {
        findings.push(`[OK] FU-3: Rest timer continued during background — delta=${delta}s, bg=${bgSecs}s`);
      } else if (delta < bgSecs - 3) {
        findings.push(`[BUG] FU-3: Rest timer FROZE during background — delta=${delta}s but bg=${bgSecs}s`);
      } else {
        findings.push(`[OBS] FU-3: Timer delta=${delta}s vs bg=${bgSecs}s — within tolerance`);
      }
    } else {
      findings.push(`[OBS] FU-3: Could not parse timer. before=${timerLineBefore} after=${timerLineAfter}`);
    }

    // Dismiss rest timer
    await page.mouse.click(196, 80);
    await page.waitForTimeout(500);
  });

  test('FU-4: offline via CDP context.setOffline — does banner appear?', async () => {
    // Use Playwright CDP to set real network offline
    const cdpSession = await page.context().newCDPSession(page);
    await cdpSession.send('Network.enable');
    await cdpSession.send('Network.emulateNetworkConditions', {
      offline: true,
      downloadThroughput: -1,
      uploadThroughput: -1,
      latency: 0,
    });
    console.log('[FU-4] CDP network offline enabled');
    await page.waitForTimeout(4000);

    const bannerVisible = await page.locator(OFFLINE.banner).isVisible({ timeout: 8000 }).catch(() => false);
    console.log(`[FU-4] Offline banner with CDP offline: ${bannerVisible}`);
    await ss('FU4-cdp-offline-banner');

    if (!bannerVisible) {
      findings.push('[OBS] FU-4: Offline banner NOT triggered even by CDP network offline — ConnectivityService may use a different mechanism than HTTP connectivity (e.g., WebSocket ping, or network_info_plus package using browser navigator.onLine)');
      // Check navigator.onLine
      const navigatorOnline = await page.evaluate(() => navigator.onLine);
      console.log(`[FU-4] navigator.onLine during CDP offline: ${navigatorOnline}`);
      findings.push(`[FU-4] navigator.onLine during CDP offline: ${navigatorOnline}`);
    } else {
      findings.push('[OK] FU-4: Offline banner appeared with CDP network offline');
    }

    // Restore online
    await cdpSession.send('Network.emulateNetworkConditions', {
      offline: false,
      downloadThroughput: -1,
      uploadThroughput: -1,
      latency: 0,
    });
    await page.waitForTimeout(2000);
    const bannerAfter = await page.locator(OFFLINE.banner).isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[FU-4] Banner after CDP restore online: ${bannerAfter}`);

    await cdpSession.detach();
  });
});
