/**
 * Charter B — "Workout interruption survival"
 * Device: US-1 (iPhone 15, 393×852, DPR 3.0)
 * Persona: Jordan (consistent lifter)
 * Date: 2026-05-07
 *
 * Structured exploratory charter. Guard: EXPL_CHARTER_B=1 so CI never runs this.
 *
 * Probes:
 *   P1 — Backgrounding (visibilitychange) in various workout states
 *   P2 — Navigate-away ("tab close") + resume banner
 *   P3 — Rotate portrait ↔ landscape
 *   P4 — Network drop offline → online (fetch override)
 *   P5 — Two-tab same user
 *   P6 — Offline banner layout (US-1 viewport)
 */

import { test, expect, Page, BrowserContext, Browser } from '@playwright/test';
import { WORKOUT, HOME, OFFLINE, GAMIFICATION } from '../helpers/selectors';
import { waitForAppReady } from '../helpers/app';
import { login } from '../helpers/auth';
import { startEmptyWorkout, addExercise, completeSet } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

// Skip entire file unless EXPL_CHARTER_B=1
const RUN = process.env['EXPL_CHARTER_B'] === '1';

const VIEWPORT_PORTRAIT = { width: 393, height: 852 };
const VIEWPORT_LANDSCAPE = { width: 852, height: 393 };
const SS_BASE = 'C:/Users/caiol/Projects/repsaga/tasks/active-workout-findings/screenshots';

// ============================================================
// Charter B — US-1 probes
// ============================================================

test.describe('Charter B — Workout interruption survival — US-1', () => {
  test.skip(!RUN, 'Set EXPL_CHARTER_B=1 to run');
  test.use({ viewport: VIEWPORT_PORTRAIT });

  let page: Page;
  let context: BrowserContext;
  const findings: string[] = [];

  // Helper: capture a screenshot
  async function ss(name: string): Promise<void> {
    const path = `${SS_BASE}/charter-B-US-1-${name}.png`;
    await page.screenshot({ path, fullPage: false }).catch(e =>
      findings.push(`[SS FAIL] ${name}: ${e.message}`)
    );
    console.log(`[screenshot] ${path}`);
  }

  // Helper: read all semantics AOM texts
  async function semanticsTexts(): Promise<string[]> {
    return page.evaluate(() => {
      return Array.from(document.querySelectorAll('flt-semantics'))
        .map((el: Element) => {
          const label = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
          const id = el.getAttribute('flt-semantics-identifier') ?? '';
          return label || id ? `[${id}]${label.slice(0, 80)}` : '';
        })
        .filter(Boolean);
    });
  }

  // Helper: find rest timer countdown value in AOM
  async function readRestTimer(): Promise<string | null> {
    return page.evaluate(() => {
      for (const el of Array.from(document.querySelectorAll('flt-semantics'))) {
        const label = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        if (/^\d+:\d{2}$/.test(label.trim())) return label.trim();
      }
      return null;
    });
  }

  // Helper: dispatch visibilitychange to hidden
  async function goBackground(): Promise<void> {
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'hidden', writable: true, configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
  }

  // Helper: dispatch visibilitychange to visible
  async function returnForeground(): Promise<void> {
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: true, configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
  }

  // Helper: override fetch (simulate offline)
  async function goOffline(): Promise<void> {
    await page.evaluate(() => {
      (window as any).__origFetch = window.fetch;
      window.fetch = () => Promise.reject(new TypeError('Failed to fetch'));
    });
  }

  // Helper: restore fetch
  async function goOnline(): Promise<void> {
    await page.evaluate(() => {
      if ((window as any).__origFetch) window.fetch = (window as any).__origFetch;
    });
  }

  // Helper: ensure we're on the active workout screen
  async function ensureOnWorkout(): Promise<void> {
    if (page.url().includes('/workout/active')) return;
    const banner = page.locator(HOME.activeBanner);
    const hasBanner = await banner.isVisible({ timeout: 5000 }).catch(() => false);
    if (hasBanner) {
      await banner.click();
      await page.waitForURL(/\/workout\/active/, { timeout: 10000 });
      return;
    }
    await page.goto('/');
    await waitForAppReady(page);
    await page.waitForURL(/\/(home|workout)/, { timeout: 15000 });
    if (page.url().includes('/home')) {
      const banner2 = page.locator(HOME.activeBanner);
      const hasBanner2 = await banner2.isVisible({ timeout: 5000 }).catch(() => false);
      if (hasBanner2) {
        await banner2.click();
        await page.waitForURL(/\/workout\/active/, { timeout: 10000 });
      }
    }
  }

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({
      viewport: VIEWPORT_PORTRAIT,
      deviceScaleFactor: 3.0,
      userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    });
    page = await context.newPage();

    page.on('console', (msg) => {
      if (msg.type() === 'error') findings.push(`[console.error] ${msg.text()}`);
    });
    page.on('pageerror', (err) => findings.push(`[page.error] ${String(err)}`));
    page.on('response', (r) => {
      if (r.status() >= 400) findings.push(`[HTTP ${r.status()}] ${r.url()}`);
    });

    // Use fullCrash user — already has prior workout history (lapsed state),
    // isolated per worker via Phase 21 worker-scoped users.
    const user = getUser('fullCrash');
    await login(page, user.email, user.password);
    console.log(`[setup] Logged in as ${user.email}`);

    // Start empty workout and add Bench Press, log 2 sets.
    // addExercise clicks "Add Set" once and creates set 0 — complete it.
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    await completeSet(page, 0);
    // Add a second set: after completing set 0, markSetDone only shows 0 remaining
    // pending sets, so the new set becomes nth(0) of markSetDone.
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(700); // past 600ms lock
    await completeSet(page, 0); // index 0 of remaining pending sets
    console.log('[setup] 2 sets logged on Bench Press');
    await ss('setup-complete');
  });

  test.afterAll(async () => {
    console.log('\n=== CHARTER B FINDINGS ===');
    findings.forEach((f) => console.log(f));
    await context.close();
  });

  // ===========================================================
  // P1 — Backgrounding (visibilitychange)
  // ===========================================================

  test('P1-B1: background mid-stepper — state survives', async () => {
    await ensureOnWorkout();
    const urlBefore = page.url();
    console.log(`[P1-B1] URL before BG: ${urlBefore}`);

    await goBackground();
    await page.waitForTimeout(3000);
    await returnForeground();
    await page.waitForTimeout(1000);

    const urlAfter = page.url();
    console.log(`[P1-B1] URL after BG: ${urlAfter}`);
    await ss('P1-B1-after-bg');

    if (!urlAfter.includes('/workout/active')) {
      findings.push(`[BUG] P1-B1: URL changed after background. Before=${urlBefore} After=${urlAfter}`);
    }
    expect(urlAfter).toContain('/workout/active');
  });

  test('P1-B2: background mid-finish-dialog — dialog survives', async () => {
    await ensureOnWorkout();

    const finishBtn = page.locator(WORKOUT.finishButton);
    await expect(finishBtn).toBeVisible({ timeout: 8000 });
    await finishBtn.click();
    await page.waitForTimeout(1000);

    const dialogBefore = await page.locator(WORKOUT.dialogFinishButton).isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[P1-B2] Dialog open before BG: ${dialogBefore}`);

    await goBackground();
    await page.waitForTimeout(3000);
    await returnForeground();
    await page.waitForTimeout(1000);

    const dialogAfter = await page.locator(WORKOUT.dialogFinishButton).isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[P1-B2] Dialog open after BG: ${dialogAfter}`);
    await ss('P1-B2-after-bg-dialog');

    if (dialogBefore && !dialogAfter) {
      findings.push('[BUG] P1-B2: Finish dialog was DISMISSED by backgrounding — potential data loss if dialog was required to save notes');
    } else if (!dialogBefore) {
      findings.push('[OBS] P1-B2: finish button not enabled (no completed sets before dialog tap, or B2 ran out of order)');
    } else {
      findings.push('[OK] P1-B2: finish dialog survived backgrounding');
    }

    // Dismiss dialog to clean up
    const keepGoing = page.locator(WORKOUT.keepGoingButton);
    const hasKG = await keepGoing.isVisible({ timeout: 3000 }).catch(() => false);
    if (hasKG) await keepGoing.click();
    else await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
  });

  test('P1-B3: background mid-rest-timer — timer continues during background', async () => {
    await ensureOnWorkout();

    // Add a set and complete it to trigger rest timer
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(700); // 600ms lock
    const doneMark = page.locator(WORKOUT.markSetDone).first();
    await expect(doneMark).toBeVisible({ timeout: 5000 });
    await doneMark.click();
    await page.waitForTimeout(600);

    // Read timer before background
    const timerBefore = await readRestTimer();
    console.log(`[P1-B3] Rest timer before BG: ${timerBefore}`);

    const t0 = Date.now();
    await goBackground();
    await page.waitForTimeout(5000);
    const bgMs = Date.now() - t0;
    await returnForeground();
    await page.waitForTimeout(800);

    const timerAfter = await readRestTimer();
    console.log(`[P1-B3] Rest timer after ${Math.round(bgMs / 1000)}s BG: ${timerAfter}`);
    await ss('P1-B3-rest-timer-after-bg');

    if (timerBefore && timerAfter) {
      const parse = (t: string) => { const [m, s] = t.split(':').map(Number); return m * 60 + s; };
      const secsBefore = parse(timerBefore);
      const secsAfter = parse(timerAfter);
      const delta = secsBefore - secsAfter;
      const expectedDelta = Math.round(bgMs / 1000);
      console.log(`[P1-B3] Timer delta: ${delta}s (expected ~${expectedDelta}s)`);
      if (Math.abs(delta - expectedDelta) > 3) {
        findings.push(`[BUG] P1-B3: Rest timer delta=${delta}s but BG was ${expectedDelta}s — timer may have FROZEN during background`);
      } else {
        findings.push(`[OK] P1-B3: Rest timer continued during background (delta=${delta}s, bg=${expectedDelta}s)`);
      }
    } else if (!timerBefore) {
      findings.push('[OBS] P1-B3: Rest timer did not appear after completing set');
    } else if (!timerAfter) {
      findings.push('[OBS] P1-B3: Rest timer GONE after background (auto-dismissed or frozen-then-completed)');
    }

    // Dismiss rest timer
    await page.mouse.click(196, 80);
    await page.waitForTimeout(500);
  });

  test('P1-B4: background during 600ms done-mark lock — lock state respected after return', async () => {
    await ensureOnWorkout();

    // Add set, background within 300ms (within lock window)
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(200); // within 600ms lock
    await goBackground();
    await page.waitForTimeout(2000);
    await returnForeground();
    await page.waitForTimeout(800);

    // App should still be on workout
    const onWorkout = page.url().includes('/workout/active');
    console.log(`[P1-B4] Still on workout after lock+BG: ${onWorkout}`);
    if (!onWorkout) {
      findings.push(`[BUG] P1-B4: Navigated away from workout during lock+BG. URL: ${page.url()}`);
    } else {
      findings.push('[OK] P1-B4: Workout screen survived lock+BG cycle');
    }
    await ss('P1-B4-lock-bg');
    expect(onWorkout).toBe(true);
  });

  // ===========================================================
  // P2 — Navigate-away ("force-quit") + resume banner
  // ===========================================================

  test('P2-A: navigate away and back — active workout banner appears on /home', async () => {
    await ensureOnWorkout();
    const urlBefore = page.url();
    console.log(`[P2-A] URL before nav-away: ${urlBefore}`);
    await ss('P2-before-nav-away');

    // Navigate to /home (simulates returning from kill/tab-close)
    await page.goto('/');
    await waitForAppReady(page);
    await page.waitForTimeout(1500);
    console.log(`[P2-A] URL after nav to /: ${page.url()}`);

    const banner = page.locator(HOME.activeBanner);
    const bannerVisible = await banner.isVisible({ timeout: 6000 }).catch(() => false);
    console.log(`[P2-A] Active workout banner: ${bannerVisible}`);
    await ss('P2-home-after-nav');

    if (!bannerVisible) {
      findings.push('[BUG] P2-A: Active workout banner NOT visible after navigating away — Hive-backed workout state may have been lost');
    } else {
      findings.push('[OK] P2-A: Active workout banner visible after navigate-away');
    }
    expect(bannerVisible).toBe(true);
  });

  test('P2-B: tap resume banner — returns to workout with sets intact', async () => {
    // Ensure we're on /home with banner
    if (!page.url().includes('/home')) {
      await page.goto('/');
      await waitForAppReady(page);
      await page.waitForTimeout(1500);
    }

    const banner = page.locator(HOME.activeBanner);
    const bannerVisible = await banner.isVisible({ timeout: 6000 }).catch(() => false);
    if (!bannerVisible) {
      findings.push('[SKIP] P2-B: No banner to tap (P2-A already captured this bug)');
      test.skip();
      return;
    }

    await banner.click();
    await page.waitForURL(/\/workout\/active/, { timeout: 10000 });
    console.log(`[P2-B] URL after banner tap: ${page.url()}`);

    // Count completed sets (should be 2+)
    const completedSets = await page.locator(WORKOUT.setCompleted).count();
    const pendingSets = await page.locator(WORKOUT.markSetDone).count();
    console.log(`[P2-B] Completed sets: ${completedSets}, pending sets: ${pendingSets}`);
    await ss('P2-workout-after-resume');

    if (completedSets === 0) {
      findings.push('[BUG] P2-B: No completed sets after resume — set data may have been lost in Hive state restoration');
    } else {
      findings.push(`[OK] P2-B: Resume preserved ${completedSets} completed sets`);
    }
    expect(completedSets).toBeGreaterThan(0);
  });

  // ===========================================================
  // P3 — Rotate / resize
  // ===========================================================

  test('P3-A: rotate to landscape — state preserved, chrome reachable', async () => {
    await ensureOnWorkout();
    await ss('P3-portrait-before');

    // Measure portrait positions
    const finishPortrait = await page.locator(WORKOUT.finishButton).boundingBox().catch(() => null);
    const addSetPortrait = await page.locator(WORKOUT.addSetButton).last().boundingBox().catch(() => null);
    console.log(`[P3-A] Portrait finish-btn: ${JSON.stringify(finishPortrait)}`);
    console.log(`[P3-A] Portrait add-set: ${JSON.stringify(addSetPortrait)}`);

    // Rotate to landscape
    await page.setViewportSize(VIEWPORT_LANDSCAPE);
    await page.waitForTimeout(2000);

    const urlLandscape = page.url();
    const onWorkout = urlLandscape.includes('/workout/active');
    console.log(`[P3-A] Landscape URL: ${urlLandscape}`);

    const finishLandscape = await page.locator(WORKOUT.finishButton).boundingBox().catch(() => null);
    const addSetLandscape = await page.locator(WORKOUT.addSetButton).last().boundingBox().catch(() => null);
    const setRowLandscape = await page
      .locator(`${WORKOUT.setCompleted}, ${WORKOUT.markSetDone}`)
      .first()
      .boundingBox()
      .catch(() => null);
    console.log(`[P3-A] Landscape finish-btn: ${JSON.stringify(finishLandscape)}`);
    console.log(`[P3-A] Landscape add-set: ${JSON.stringify(addSetLandscape)}`);
    console.log(`[P3-A] Landscape set-row: ${JSON.stringify(setRowLandscape)}`);
    await ss('P3-landscape');

    if (!onWorkout) {
      findings.push(`[BUG] P3-A: Navigated away from workout on rotate. URL: ${urlLandscape}`);
    }
    if (!finishLandscape) {
      findings.push('[BUG] P3-A: Finish button NOT visible in landscape');
    }
    if (!addSetLandscape) {
      findings.push('[BUG] P3-A: Add Set button NOT visible in landscape');
    }
    if (!setRowLandscape) {
      findings.push('[OBS] P3-A: No set rows visible in landscape (may have scrolled off)');
    }
    if (onWorkout && finishLandscape && addSetLandscape) {
      findings.push('[OK] P3-A: Landscape layout preserved workout state with key chrome visible');
    }
    expect(onWorkout).toBe(true);
  });

  test('P3-B: rest timer in landscape — overlay renders correctly', async () => {
    // We're in landscape from P3-A
    if (!page.url().includes('/workout/active')) {
      await ensureOnWorkout();
    }

    // Complete a set to trigger rest timer
    await page.locator(WORKOUT.addSetButton).last().click();
    await page.waitForTimeout(700);
    const doneMark = page.locator(WORKOUT.markSetDone).first();
    const hasDone = await doneMark.isVisible({ timeout: 3000 }).catch(() => false);
    if (!hasDone) {
      findings.push('[SKIP] P3-B: No done-mark visible in landscape — skipping rest timer overlay test');
      return;
    }
    await doneMark.click();
    await page.waitForTimeout(800);

    const timerLandscape = await readRestTimer();
    const timerVisible = timerLandscape !== null;
    console.log(`[P3-B] Rest timer in landscape: ${timerLandscape}`);
    await ss('P3-landscape-rest-timer');

    if (!timerVisible) {
      findings.push('[BUG] P3-B: Rest timer did not appear in landscape after completing set');
    } else {
      findings.push(`[OK] P3-B: Rest timer appeared in landscape: ${timerLandscape}`);
    }

    // Dismiss
    await page.mouse.click(852 / 2, 80);
    await page.waitForTimeout(500);
  });

  test('P3-C: finish dialog in landscape — readable', async () => {
    if (!page.url().includes('/workout/active')) {
      await ensureOnWorkout();
    }

    const finishBtn = page.locator(WORKOUT.finishButton);
    const hasFinish = await finishBtn.isVisible({ timeout: 3000 }).catch(() => false);
    if (!hasFinish) {
      findings.push('[SKIP] P3-C: finish button not visible in landscape');
      return;
    }
    await finishBtn.click();
    await page.waitForTimeout(1000);
    const dialogVisible = await page.locator(WORKOUT.dialogFinishButton).isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[P3-C] Finish dialog in landscape: ${dialogVisible}`);
    if (dialogVisible) await ss('P3-landscape-finish-dialog');

    if (!dialogVisible) {
      findings.push('[BUG] P3-C: Finish dialog did not open in landscape');
    } else {
      findings.push('[OK] P3-C: Finish dialog opened in landscape');
    }

    const keepGoing = page.locator(WORKOUT.keepGoingButton);
    const hasKG = await keepGoing.isVisible({ timeout: 2000 }).catch(() => false);
    if (hasKG) await keepGoing.click();
    else await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
  });

  test('P3-D: rotate back to portrait — state and layout fully restored', async () => {
    await page.setViewportSize(VIEWPORT_PORTRAIT);
    await page.waitForTimeout(2000);

    const urlPortrait = page.url();
    const onWorkout = urlPortrait.includes('/workout/active');
    console.log(`[P3-D] Portrait after rotate back: ${urlPortrait}`);

    const finishPortraitAfter = await page.locator(WORKOUT.finishButton).boundingBox().catch(() => null);
    const addSetPortraitAfter = await page.locator(WORKOUT.addSetButton).last().boundingBox().catch(() => null);
    console.log(`[P3-D] Portrait finish-btn after rotate: ${JSON.stringify(finishPortraitAfter)}`);
    console.log(`[P3-D] Portrait add-set after rotate: ${JSON.stringify(addSetPortraitAfter)}`);
    await ss('P3-portrait-after-rotate');

    if (!onWorkout) {
      findings.push(`[BUG] P3-D: Navigated away on rotate-back. URL: ${urlPortrait}`);
    }
    if (!finishPortraitAfter) {
      findings.push('[BUG] P3-D: Finish button missing after portrait restore');
    }
    if (onWorkout && finishPortraitAfter) {
      findings.push('[OK] P3-D: Portrait restored after landscape → portrait rotation');
    }
    expect(onWorkout).toBe(true);
  });

  // ===========================================================
  // P4 — Network drop offline → online
  // ===========================================================

  test('P4-A: offline banner appears when fetch is blocked', async () => {
    await ensureOnWorkout();

    const bannerBefore = await page.locator(OFFLINE.banner).isVisible({ timeout: 2000 }).catch(() => false);
    console.log(`[P4-A] Banner before offline: ${bannerBefore}`);

    await goOffline();
    await page.waitForTimeout(4000);

    const bannerAfter = await page.locator(OFFLINE.banner).isVisible({ timeout: 8000 }).catch(() => false);
    console.log(`[P4-A] Banner after going offline: ${bannerAfter}`);
    await ss('P4-offline-banner');

    if (!bannerAfter) {
      findings.push('[OBS] P4-A: Offline banner did NOT appear with fetch override — ConnectivityService may not observe fetch failures; may require real OS network change');
    } else {
      findings.push('[OK] P4-A: Offline banner appeared after fetch override');
    }
    // Don't hard-fail: fetch override may not trigger the ConnectivityService
    // (it may use a different mechanism). Log as observation.

    await goOnline();
    await page.waitForTimeout(2000);
  });

  test('P4-B: set operations succeed while offline (Hive autosave)', async () => {
    await ensureOnWorkout();
    await goOffline();
    await page.waitForTimeout(2000);

    // Add and complete a set
    const addSetBtn = page.locator(WORKOUT.addSetButton).last();
    const hasAdd = await addSetBtn.isVisible({ timeout: 3000 }).catch(() => false);
    if (hasAdd) {
      await addSetBtn.click();
      await page.waitForTimeout(700);
    }
    const doneMark = page.locator(WORKOUT.markSetDone).first();
    const hasDone = await doneMark.isVisible({ timeout: 3000 }).catch(() => false);
    if (hasDone) {
      await doneMark.click();
      await page.waitForTimeout(500);
      await page.mouse.click(196, 80);
      await page.waitForTimeout(400);
    }

    // Count completed sets — Hive should have autosaved
    const completedSets = await page.locator(WORKOUT.setCompleted).count();
    console.log(`[P4-B] Completed sets while offline: ${completedSets}`);
    await ss('P4-set-offline');

    if (completedSets === 0) {
      findings.push('[BUG] P4-B: No completed sets while offline — set completion may require network');
    } else {
      findings.push(`[OK] P4-B: Set completion works offline (${completedSets} completed)`);
    }

    await goOnline();
    await page.waitForTimeout(1000);
  });

  test('P4-C: finish workout offline — saved-offline snackbar + pending badge', async () => {
    await ensureOnWorkout();
    await goOffline();
    await page.waitForTimeout(2000);

    const finishBtn = page.locator(WORKOUT.finishButton);
    const hasFinish = await finishBtn.isVisible({ timeout: 5000 }).catch(() => false);
    if (!hasFinish) {
      findings.push('[SKIP] P4-C: finish button not visible');
      await goOnline();
      return;
    }
    await finishBtn.click();
    await page.waitForTimeout(1000);
    const dialogVisible = await page.locator(WORKOUT.dialogFinishButton).isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[P4-C] Finish dialog opens while offline: ${dialogVisible}`);

    if (dialogVisible) {
      await page.locator(WORKOUT.dialogFinishButton).click();
      await page.waitForTimeout(4000);
      const urlAfter = page.url();
      console.log(`[P4-C] URL after offline finish: ${urlAfter}`);

      // Check snackbar / offline-related AOM text
      const allTexts = await semanticsTexts();
      const offlineTexts = allTexts.filter(t =>
        t.toLowerCase().includes('offline') ||
        t.toLowerCase().includes('saved') ||
        t.toLowerCase().includes('sync') ||
        t.toLowerCase().includes('queue')
      );
      console.log(`[P4-C] Offline-related AOM: ${JSON.stringify(offlineTexts)}`);
      await ss('P4-offline-finish-result');

      const wentHome = urlAfter.includes('/home');
      const badge = await page.locator(OFFLINE.pendingSyncBadge).isVisible({ timeout: 3000 }).catch(() => false);
      console.log(`[P4-C] Went home: ${wentHome}, pending badge: ${badge}`);

      if (!wentHome) {
        findings.push(`[BUG] P4-C: Offline finish did not navigate to /home. URL: ${urlAfter}`);
      } else {
        findings.push('[OK] P4-C: Offline finish navigated to /home');
      }
      if (offlineTexts.length === 0) {
        findings.push('[BUG] P4-C: No "saved offline" or sync feedback visible after offline finish');
      } else {
        findings.push(`[OK] P4-C: Offline finish showed feedback: ${offlineTexts.join(', ')}`);
      }
      if (!badge) {
        findings.push('[OBS] P4-C: Pending sync badge not visible after offline finish (may not be on home, or badge missing)');
      } else {
        findings.push('[OK] P4-C: Pending sync badge visible after offline finish');
      }
    } else {
      findings.push('[OBS] P4-C: Finish dialog not visible offline — finish button may be disabled or dialog failed to open');
      const keepGoing = page.locator(WORKOUT.keepGoingButton);
      const hasKG = await keepGoing.isVisible({ timeout: 2000 }).catch(() => false);
      if (hasKG) await keepGoing.click();
    }

    await goOnline();
    await page.waitForTimeout(2000);
  });

  test('P4-D: reconnect online — sync drain triggers, banner disappears', async () => {
    // At this point P4-C may have finished the workout. Check current state.
    const currentUrl = page.url();
    console.log(`[P4-D] Current URL: ${currentUrl}`);

    await goOffline();
    await page.waitForTimeout(1000);
    const bannerOffline = await page.locator(OFFLINE.banner).isVisible({ timeout: 5000 }).catch(() => false);
    await goOnline();
    await page.waitForTimeout(4000);
    const bannerOnline = await page.locator(OFFLINE.banner).isVisible({ timeout: 3000 }).catch(() => false);
    console.log(`[P4-D] Banner offline: ${bannerOffline}, after online: ${bannerOnline}`);

    if (bannerOffline && bannerOnline) {
      findings.push('[OBS] P4-D: Offline banner still showing after restoring online — may need more time or real network event');
    } else if (bannerOffline && !bannerOnline) {
      findings.push('[OK] P4-D: Offline banner dismissed after restoring online');
    } else {
      findings.push('[OBS] P4-D: Offline banner did not appear with fetch override (consistent with P4-A observation)');
    }
    await ss('P4-after-online-restore');
  });

  // ===========================================================
  // P5 — Two-tab same user
  // ===========================================================

  test('P5-A: second tab shows active workout banner (if active workout exists)', async () => {
    // Navigate to home
    if (!page.url().includes('/home')) {
      await page.goto('/');
      await waitForAppReady(page);
      await page.waitForTimeout(1500);
    }

    const tab1Banner = await page.locator(HOME.activeBanner).isVisible({ timeout: 5000 }).catch(() => false);
    console.log(`[P5-A] Tab 1 banner: ${tab1Banner}`);

    // Open second page in same context (= same session, same Hive Isar instance)
    const tabB = await context.newPage();
    await tabB.setViewportSize(VIEWPORT_PORTRAIT);
    await tabB.goto('/');
    await waitForAppReady(tabB);
    await tabB.waitForTimeout(2000);

    const tabBUrl = tabB.url();
    const tabBBanner = await tabB.locator(HOME.activeBanner).isVisible({ timeout: 5000 }).catch(() => false);
    const tabBOnWorkout = tabBUrl.includes('/workout/active');
    console.log(`[P5-A] Tab B URL: ${tabBUrl}`);
    console.log(`[P5-A] Tab B banner: ${tabBBanner}, on workout: ${tabBOnWorkout}`);
    await tabB.screenshot({ path: `${SS_BASE}/charter-B-US-1-P5-tab-b.png` });

    // If tab 1 has a banner, tab B should too (same Hive)
    if (tab1Banner && !tabBBanner && !tabBOnWorkout) {
      findings.push('[BUG] P5-A: Tab 1 has active banner but Tab B does NOT — Hive state not shared across tabs (each tab has isolated IndexedDB)');
    } else if (tab1Banner && (tabBBanner || tabBOnWorkout)) {
      findings.push('[OK] P5-A: Tab B shows active workout state (banner or direct workout route)');
    } else if (!tab1Banner) {
      findings.push('[OBS] P5-A: Tab 1 has no active banner (workout may have been finished in P4-C) — Tab B test not meaningful');
    }

    if (tabBBanner) {
      await tabB.locator(HOME.activeBanner).click();
      await tabB.waitForTimeout(2000);
      const tabBAfterTap = tabB.url();
      console.log(`[P5-A] Tab B after banner tap: ${tabBAfterTap}`);
      const completedTabB = await tabB.locator(WORKOUT.setCompleted).count();
      console.log(`[P5-A] Tab B completed sets after resume: ${completedTabB}`);
      if (completedTabB === 0) {
        findings.push('[BUG] P5-A: Tab B resumed workout shows 0 completed sets (same isolation issue or state corruption)');
      }
      await tabB.screenshot({ path: `${SS_BASE}/charter-B-US-1-P5-tab-b-after-banner.png` });
    }

    await tabB.close();
  });

  // ===========================================================
  // P6 — Offline banner layout (393×852)
  // ===========================================================

  test('P6: offline banner + chrome layout on US-1 — no overlap', async () => {
    // Need to be on workout screen
    await ensureOnWorkout();

    await goOffline();
    await page.waitForTimeout(5000);

    const banner = page.locator(OFFLINE.banner);
    const bannerVis = await banner.isVisible({ timeout: 8000 }).catch(() => false);
    console.log(`[P6] Offline banner visible: ${bannerVis}`);

    if (bannerVis) {
      const bannerBox = await banner.boundingBox().catch(() => null);
      const finishBox = await page.locator(WORKOUT.finishButton).boundingBox().catch(() => null);
      const addSetBox = await page.locator(WORKOUT.addSetButton).last().boundingBox().catch(() => null);
      const setRowBox = await page
        .locator(`${WORKOUT.setCompleted}, ${WORKOUT.markSetDone}`)
        .first()
        .boundingBox()
        .catch(() => null);

      console.log(`[P6] Banner: ${JSON.stringify(bannerBox)}`);
      console.log(`[P6] Finish: ${JSON.stringify(finishBox)}`);
      console.log(`[P6] AddSet: ${JSON.stringify(addSetBox)}`);
      console.log(`[P6] SetRow: ${JSON.stringify(setRowBox)}`);
      await ss('P6-offline-banner-layout');

      if (bannerBox && finishBox) {
        const bannerBottom = bannerBox.y + bannerBox.height;
        const finishTop = finishBox.y;
        if (bannerBottom > finishTop) {
          findings.push(`[BUG] P6: Offline banner overlaps Finish button! banner_bottom=${bannerBottom} > finish_top=${finishTop}`);
        } else {
          findings.push(`[OK] P6: Banner does not overlap finish button (banner_bottom=${bannerBottom}, finish_top=${finishTop})`);
        }
      }
      if (bannerBox && setRowBox) {
        const bannerBottom = bannerBox.y + bannerBox.height;
        const rowTop = setRowBox.y;
        if (bannerBottom > rowTop) {
          findings.push(`[BUG] P6: Offline banner overlaps set rows! banner_bottom=${bannerBottom} > row_top=${rowTop}`);
        } else {
          findings.push(`[OK] P6: Banner does not overlap set rows (banner_bottom=${bannerBottom}, row_top=${rowTop})`);
        }
      }
    } else {
      findings.push('[OBS] P6: Offline banner not triggered by fetch override — cannot measure layout overlap. Banner layout test requires real OS network offline simulation or Chrome DevTools CDP offline emulation.');
      await ss('P6-no-banner');
    }

    await goOnline();
    await page.waitForTimeout(1000);
  });
});
