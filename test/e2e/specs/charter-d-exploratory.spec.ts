/**
 * Charter D — "Finish-flow happy + sad paths"
 * Device: US-1 (iPhone 15, 393×852, DPR 3.0)
 * Persona: Sam (data-nerd; verifies every post-finish branch)
 * Date: 2026-05-07
 *
 * **SUPERSEDED ARTIFACT — PR 30a / PR 30c post-session migration (2026-05-22)**
 *
 * This charter's URL-route assumptions predate the PR 30a / PR 30c
 * post-session migration. Branches B1, B2, B3, B4, B5, B10, B11 probe
 * whether the legacy `/pr-celebration` route fires (or doesn't). That route
 * was retired in PR 30c — every online non-empty finish now routes through
 * `/workout/finish/:workoutId` (the post-session cinematic). Updating each
 * URL guard to `/workout/finish/` would fundamentally change the questions
 * these branches were asking: B1 was investigating "does /pr-celebration
 * fire incorrectly for 0 PRs?", not "does /workout/finish/ fire?".
 *
 * The charter's investigative narrative is preserved for continuity. The
 * entire test.describe block is skipped (test.describe.skip) so the tests
 * compile but never run. Do not remove — the findings log at FINAL provides
 * a paper trail for the AW-EX-D-US1-* bugs discovered on 2026-05-07.
 *
 * Superseded by: workouts.spec.ts (online finish → /workout/finish/),
 * offline-sync.spec.ts (offline finish → /home), personal-records.spec.ts
 * (PR detection post-cinematic).
 *
 * Guard: EXPL_CHARTER_D=1 so CI never ran this even before skipping.
 *
 * Branches:
 *   SETUP  — sign up fresh user, complete onboarding, establish Bench Press baseline
 *   B1     — Online + 0 PRs + ad-hoc → expected /home (no celebration)
 *   B2     — Online + ≥1 PR + ad-hoc → expected /pr-celebration [ROUTE RETIRED]
 *   B3     — Multiple PRs in one workout → celebration lists both [ROUTE RETIRED]
 *   B4     — Routine workout, NOT in plan → add-to-plan prompt
 *   B5     — Routine workout, IN plan → /home (no prompt)
 *   B8     — Offline + queued save → "Saved offline" snackbar
 *   B9     — Server 500 → error snackbar, stays on screen
 *   B10    — Background mid-save → celebration plays on return [ROUTE RETIRED]
 *   B11    — Tap Save & Finish twice rapidly → only one save [ROUTE RETIRED]
 *   B12    — Cancel from loading overlay (10s wait)
 *   NOTES  — notes field edge cases
 *
 * All branches use soft assertions so failures don't cascade.
 */

import { test, expect, Page } from '@playwright/test';
import { WORKOUT, HOME, NAV, PR, AUTH } from '../helpers/selectors';
import { waitForAppReady, flutterFill, scrollToVisible } from '../helpers/app';
import { startEmptyWorkout, addExercise, setWeight, setReps, completeSet } from '../helpers/workout';

// Skip entire file unless EXPL_CHARTER_D=1
const RUN = process.env['EXPL_CHARTER_D'] === '1';

const VIEWPORT = { width: 393, height: 852 };
const SS_BASE = 'C:/Users/caiol/Projects/repsaga/test/e2e/test-results/charter-screenshots';

// Fresh user created once; email includes timestamp so reruns don't collide.
const CHARTER_TS = process.env['EXPL_CHARTER_D_TS'] ?? Date.now().toString();
const USER_EMAIL = `expl-d-us1-${CHARTER_TS}@test.local`;
const USER_PASS = 'Test1234!';

// Shared findings array (accumulated across all tests via console log + exported)
const FINDINGS: string[] = [];

// ============================================================
// Utility helpers
// ============================================================

async function ss(page: Page, name: string): Promise<void> {
  const path = `${SS_BASE}/charter-D-US-1-${name}.png`;
  await page.screenshot({ path, fullPage: false }).catch(e =>
    FINDINGS.push(`[SS FAIL] ${name}: ${e.message}`)
  );
  console.log(`[screenshot] ${path}`);
}

async function aomDump(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    return Array.from(document.querySelectorAll('flt-semantics'))
      .map((el: Element) => {
        const label = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        const id = el.getAttribute('flt-semantics-identifier') ?? '';
        const role = el.getAttribute('role') ?? '';
        return (label || id) ? `[${role}][${id}] ${label.slice(0, 100)}` : '';
      })
      .filter(Boolean);
  });
}

async function signupFreshUser(page: Page, email: string, pass: string): Promise<void> {
  await page.goto('/');
  await waitForAppReady(page);
  const toggleSignUp = page.locator('[flt-semantics-identifier="auth-toggle-signup"]');
  await expect(toggleSignUp).toBeVisible({ timeout: 15_000 });
  await toggleSignUp.click();
  // Option A — the full signup form requires display name + password (the
  // confirm field was dropped; the reveal toggle is the typo-safety net).
  await flutterFill(page, '[flt-semantics-identifier="auth-display-name-input"]', 'Sam DataNerd');
  await flutterFill(page, '[flt-semantics-identifier="auth-email-input"]', email);
  await flutterFill(page, '[flt-semantics-identifier="auth-password-input"]', pass);
  // Legal PR 2 — age gate: Sign Up CTA disabled until checkbox ticked.
  await expect(
    page.locator(AUTH.ageConfirmationCheckbox),
  ).toBeVisible({ timeout: 5_000 });
  await page.locator(AUTH.ageConfirmationCheckbox).click();
  await page.click('[flt-semantics-identifier="auth-signup-btn"]');
  await page.waitForURL(/onboarding/, { timeout: 30_000 });
}

async function completeOnboarding(page: Page): Promise<void> {
  const getStarted = page.locator('[flt-semantics-identifier="onboarding-get-started"]');
  await expect(getStarted).toBeVisible({ timeout: 15_000 });
  await getStarted.click();

  // Option A — onboarding no longer collects the display name (it's on the
  // signup form). Wait for the page-2 indicator, then submit fitness signals.
  const profileSetup = page.locator('[flt-semantics-identifier="onboarding-beginner"]');
  await expect(profileSetup).toBeVisible({ timeout: 10_000 });

  const letsGo = page.locator('[flt-semantics-identifier="onboarding-lets-go"]');
  await expect(letsGo).toBeVisible({ timeout: 10_000 });
  await letsGo.click();
  await page.waitForURL(/home/, { timeout: 20_000 });
}

async function maybeDismissSagaIntro(page: Page): Promise<void> {
  const step0 = page.locator('[flt-semantics-identifier="saga-intro-step-0"]');
  const visible = await step0.isVisible({ timeout: 8_000 }).catch(() => false);
  if (!visible) return;

  const next = page.locator('[flt-semantics-identifier="saga-intro-next"]');
  await next.click();
  await page.waitForTimeout(500);
  await next.click();
  await page.waitForTimeout(500);
  const begin = page.locator('[flt-semantics-identifier="saga-intro-begin"]');
  await begin.click();
  await step0.waitFor({ state: 'detached', timeout: 8_000 }).catch(() => {});
}

async function loginUser(page: Page): Promise<void> {
  await page.goto('/');
  await waitForAppReady(page);
  await flutterFill(page, '[flt-semantics-identifier="auth-email-input"]', USER_EMAIL);
  await flutterFill(page, '[flt-semantics-identifier="auth-password-input"]', USER_PASS);
  await page.click('[flt-semantics-identifier="auth-login-btn"]');
  await page.locator('[flt-semantics-identifier="nav-home"]').waitFor({ state: 'visible', timeout: 20_000 });
  await maybeDismissSagaIntro(page);
}

async function dismissPrCelebrationIfPresent(page: Page): Promise<boolean> {
  const onCelebration = page.url().includes('pr-celebration');
  if (!onCelebration) return false;
  const continueBtn = page.locator('[flt-semantics-identifier="pr-continue-btn"]');
  if (await continueBtn.isVisible({ timeout: 8_000 }).catch(() => false)) {
    await continueBtn.click();
    await page.waitForURL(/home/, { timeout: 15_000 });
  }
  return true;
}

function log(msg: string): void {
  FINDINGS.push(msg);
  console.log(msg);
}

// ============================================================
// Tests (serial mode)
// ============================================================

// eslint-disable-next-line playwright/no-skipped-test
test.describe.skip('Charter D — Finish-flow happy + sad paths — US-1 [SUPERSEDED: /pr-celebration retired in PR 30c]', () => {
  // This entire describe block is skipped. See file-level comment for rationale.
  // The EXPL_CHARTER_D guard below is kept for documentary purposes only.
  test.skip(!RUN, 'Set EXPL_CHARTER_D=1 to run');
  test.use({ viewport: VIEWPORT });
  test.describe.configure({ mode: 'serial' });

  // ---------------------------------------------------------
  // SETUP: Create fresh user + establish Bench Press baseline
  // ---------------------------------------------------------
  test('SETUP — sign up + onboarding + Workout 1 (Bench Press 50kg×8 → establishes baseline)', async ({ page }) => {
    log('=== SETUP START ===');
    log(`[SETUP] user: ${USER_EMAIL}`);

    await signupFreshUser(page, USER_EMAIL, USER_PASS);
    log('[SETUP] signed up');
    await completeOnboarding(page);
    log('[SETUP] onboarding complete, on /home');
    await maybeDismissSagaIntro(page);

    // Workout 1: Bench Press 50kg×8 — establishes a PR baseline
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    await setWeight(page, '50');
    await setReps(page, '8');
    await completeSet(page, 0);

    await ss(page, 'SETUP-W1-before-finish');

    // Q1 (notes-edit-after): the finish dialog no longer carries a notes
    // field — notes are written later on the History detail screen. The
    // finish gate is now a plain confirm. (The NOTES edge-case test below
    // was retired with the field.)
    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });

    await dialogFinish.click();

    await page.waitForURL(/\/(pr-celebration|home|workout\/finish\/)/, { timeout: 20_000 });
    const urlW1 = page.url();
    log(`[SETUP-W1] URL after Workout 1 finish: ${urlW1}`);

    if (urlW1.includes('pr-celebration')) {
      log('[SETUP-W1] PR celebration appeared — expected for first workout. Dismissing.');
      await ss(page, 'SETUP-W1-pr-celebration');
      await dismissPrCelebrationIfPresent(page);
    } else {
      log('[SETUP-W1] No PR celebration — went directly to /home');
    }

    log(`[SETUP] Baseline established: Bench Press 50kg×8. Now on ${page.url()}`);
    expect(page.url()).toContain('home');
  });

  // ---------------------------------------------------------
  // B1: 0 PRs → should go to /home (no celebration)
  // ---------------------------------------------------------
  test('B1 — 0 PRs (30kg×5, below baseline 50kg×8) → expected /home, no celebration', async ({ page }) => {
    await loginUser(page);
    log('[B1] Workout 2: Bench Press 30kg×5 (below baseline 50kg×8 → 0 new PRs)');

    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    await setWeight(page, '30');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Check set-row state — should NOT show pending-PR (30kg < 50kg baseline)
    const pendingPrRow = await page.locator('[flt-semantics-identifier="set-row-state-pending-pr"]').isVisible({ timeout: 2_000 }).catch(() => false);
    const standingPrRow = await page.locator('[flt-semantics-identifier="set-row-state-standing-pr"]').isVisible({ timeout: 2_000 }).catch(() => false);
    const completedRow = await page.locator('[flt-semantics-identifier="set-row-state-completed"]').isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[B1] Set row state — pending-pr: ${pendingPrRow}, standing-pr: ${standingPrRow}, completed: ${completedRow}`);

    if (pendingPrRow || standingPrRow) {
      log('[B1] FINDING: Set row shows PR state for a below-baseline weight (30kg vs 50kg baseline) — may indicate PR detection issue');
    }

    await ss(page, 'B1-W2-before-finish');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await ss(page, 'B1-W2-finish-dialog');
    await dialogFinish.click();

    await page.waitForURL(/\/(pr-celebration|home|workout\/finish\/)/, { timeout: 25_000 });
    const urlB1 = page.url();
    log(`[B1] URL after 0-PR finish: ${urlB1}`);

    if (urlB1.includes('pr-celebration')) {
      log('[B1] BUG CONFIRMED: Redirected to /pr-celebration despite 0 new PRs (30kg×5 < baseline 50kg×8)');
      log('[B1] Cross-ref: AW-EX-D-US1-01 — PR celebration fires incorrectly when 0 new PRs expected');
      await ss(page, 'B1-unexpected-pr-celebration');

      // Dismiss so B2 can proceed
      await dismissPrCelebrationIfPresent(page);
    } else {
      log('[B1] PASS: Redirected to /home with no celebration (correct behavior for 0 PRs)');
    }

    await ss(page, 'B1-after-finish');
    log('[B1] DONE');
  });

  // ---------------------------------------------------------
  // B2: ≥1 PR → /pr-celebration
  // ---------------------------------------------------------
  test('B2 — ≥1 PR (60kg×8, beats baseline 50kg×8) → expected /pr-celebration', async ({ page }) => {
    await loginUser(page);
    log('[B2] Workout 3: Bench Press 60kg×8 (beats baseline 50kg×8 → new PR)');

    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    await setWeight(page, '60');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Check set-row state — should show standing-PR (60kg > 50kg baseline)
    const standingPrRow = await page.locator('[flt-semantics-identifier="set-row-state-standing-pr"]').isVisible({ timeout: 2_000 }).catch(() => false);
    const pendingPrRow = await page.locator('[flt-semantics-identifier="set-row-state-pending-pr"]').isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[B2] Set row state — standing-pr: ${standingPrRow}, pending-pr: ${pendingPrRow}`);

    if (!standingPrRow && !pendingPrRow) {
      log('[B2] FINDING: Set row does NOT show PR state for a weight above baseline — may indicate PR detection issue');
    }

    await ss(page, 'B2-W3-before-finish');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await dialogFinish.click();

    await page.waitForURL(/\/(pr-celebration|home|workout\/finish\/)/, { timeout: 25_000 });
    const urlB2 = page.url();
    log(`[B2] URL after PR finish: ${urlB2}`);

    if (urlB2.includes('pr-celebration')) {
      log('[B2] PASS: Redirected to /pr-celebration');
      await ss(page, 'B2-pr-celebration');

      // Check celebration content
      const prNewHeading = page.locator('[flt-semantics-identifier="pr-new-heading"]');
      const headingVisible = await prNewHeading.isVisible({ timeout: 8_000 }).catch(() => false);
      log(`[B2] PR new heading visible: ${headingVisible}`);

      const aom = await aomDump(page);
      log(`[B2] Celebration screen AOM (${aom.length} nodes):`);
      aom.slice(0, 30).forEach(l => log(`  ${l}`));

      // Check "Continue" button
      const continueBtn = page.locator('[flt-semantics-identifier="pr-continue-btn"]');
      const continueBtnVisible = await continueBtn.isVisible({ timeout: 8_000 }).catch(() => false);
      log(`[B2] Continue button visible: ${continueBtnVisible}`);

      if (continueBtnVisible) {
        await continueBtn.click();
        await page.waitForURL(/home/, { timeout: 15_000 });
        log(`[B2] After Continue → ${page.url()}`);
      }
    } else {
      log('[B2] BUG: Expected /pr-celebration but got /home');
      await ss(page, 'B2-unexpected-home');
    }

    log('[B2] DONE');
  });

  // ---------------------------------------------------------
  // B3: Multiple PRs in one workout
  // ---------------------------------------------------------
  test('B3 — Multiple PRs in one workout → celebration should list all', async ({ page }) => {
    await loginUser(page);
    log('[B3] Workout 4: Bench Press 65kg×8 (beats 60kg) + Barbell Squat 100kg×10 (fresh exercise)');

    await startEmptyWorkout(page);

    // Exercise 1: Bench Press 65kg (beats 60kg from W3)
    await addExercise(page, 'Barbell Bench Press');
    await setWeight(page, '65');
    await setReps(page, '8');
    await completeSet(page, 0);

    // Exercise 2: Squat (fresh exercise = automatic PR)
    await addExercise(page, 'Barbell Squat');
    await setWeight(page, '100');
    await setReps(page, '10');
    await completeSet(page, 0);

    await ss(page, 'B3-before-finish');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await dialogFinish.click();

    await page.waitForURL(/\/(pr-celebration|home|workout\/finish\/)/, { timeout: 25_000 });
    const urlB3 = page.url();
    log(`[B3] URL after multi-PR finish: ${urlB3}`);

    if (urlB3.includes('pr-celebration')) {
      await ss(page, 'B3-pr-celebration');

      const aom = await aomDump(page);
      log(`[B3] Celebration AOM (${aom.length} nodes):`);
      aom.slice(0, 50).forEach(l => log(`  ${l}`));

      const benchPressInAom = aom.some(l => l.toLowerCase().includes('bench') || l.toLowerCase().includes('press'));
      const squatInAom = aom.some(l => l.toLowerCase().includes('squat'));
      log(`[B3] Bench Press in celebration AOM: ${benchPressInAom}`);
      log(`[B3] Squat in celebration AOM: ${squatInAom}`);

      if (!squatInAom || !benchPressInAom) {
        log('[B3] FINDING: Not all PRs listed on celebration screen — missing exercise(s) in AOM');
      } else {
        log('[B3] PASS: Both exercises visible in celebration AOM');
      }

      const continueBtn = page.locator('[flt-semantics-identifier="pr-continue-btn"]');
      if (await continueBtn.isVisible({ timeout: 8_000 }).catch(() => false)) {
        await continueBtn.click();
        await page.waitForURL(/home/, { timeout: 15_000 });
      }
    } else {
      log('[B3] NOTE: No PR celebration — went to /home');
    }

    log('[B3] DONE');
  });

  // ---------------------------------------------------------
  // B4: Routine workout, NOT in plan → add-to-plan prompt
  // ---------------------------------------------------------
  test('B4 — Routine workout, NOT in plan → add-to-plan prompt expected', async ({ page }) => {
    await loginUser(page);
    log('[B4] Creating routine "Charter D Test Routine", NOT adding to plan');

    // Go to Routines tab
    await page.click(NAV.routinesTab);
    await page.waitForURL(/routines/, { timeout: 10_000 });
    await page.waitForTimeout(1_000);
    await ss(page, 'B4-routines-tab');

    // Create a new routine
    const createBtn = page.locator('[flt-semantics-identifier="routine-mgmt-create-btn"]');
    const createBtnVisible = await createBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[B4] Create routine button visible: ${createBtnVisible}`);

    if (!createBtnVisible) {
      log('[B4] SKIP: Cannot find create routine button');
      return;
    }

    await createBtn.click();
    await page.waitForTimeout(2_000);
    await ss(page, 'B4-create-routine-screen');

    // Fill routine name
    const routineNameInput = page.locator('input[data-semantics-role="text-field"]');
    const nameVisible = await routineNameInput.isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[B4] Routine name input visible: ${nameVisible}`);

    if (nameVisible) {
      await routineNameInput.focus();
      await page.keyboard.press('Control+a');
      await page.keyboard.type('Charter D Test Routine', { delay: 10 });
    } else {
      log('[B4] SKIP: Routine name input not found');
      return;
    }

    // Add exercise to routine
    const addExBtn = page.locator('[flt-semantics-identifier="create-routine-add-exercise"]');
    if (await addExBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await addExBtn.click();
      const pickerSearch = page.locator('[flt-semantics-identifier="exercise-picker-search"]');
      await expect(pickerSearch).toBeVisible({ timeout: 10_000 });
      await flutterFill(page, '[flt-semantics-identifier="exercise-picker-search"]', 'Push-Up');
      const addPushUp = page.locator('role=button[name*="Add Push-Up"]').first();
      if (await addPushUp.isVisible({ timeout: 8_000 }).catch(() => false)) {
        await addPushUp.click();
        await page.waitForTimeout(1_000);
      }
    }

    // Save routine
    const saveBtn = page.locator('[flt-semantics-identifier="create-routine-save"]');
    if (await saveBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await saveBtn.click();
      await page.waitForTimeout(2_000);
    }

    await ss(page, 'B4-after-save-routine');
    log('[B4] Routine saved (NOT added to plan)');

    // Navigate to routines list and start from the routine
    await page.click(NAV.routinesTab);
    await page.waitForURL(/routines/, { timeout: 10_000 });
    await page.waitForTimeout(1_500);

    // Use scrollToVisible to find the routine card (may be below the fold)
    const routineCard = await scrollToVisible(page, 'text=Charter D Test Routine', 15).catch(() => null);
    if (!routineCard) {
      log('[B4] SKIP: Routine card not found after scrolling');
      return;
    }
    log('[B4] Routine card found (scrolled if needed)');

    await routineCard.click();
    await page.waitForTimeout(2_000);
    await ss(page, 'B4-routine-detail');

    // Look for start button on routine detail
    const aomDetail = await aomDump(page);
    log('[B4] Routine detail AOM:');
    aomDetail.slice(0, 20).forEach(l => log(`  ${l}`));

    const startRoutineBtn = page.locator('role=button[name*="Start"]').first();
    const startVisible = await startRoutineBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[B4] Start workout button visible: ${startVisible}`);

    if (!startVisible) {
      log('[B4] SKIP: No start button found on routine detail');
      return;
    }

    await startRoutineBtn.click();
    await page.waitForURL(/workout/, { timeout: 15_000 });
    await page.waitForTimeout(1_500);
    await ss(page, 'B4-routine-workout-active');
    log('[B4] Started routine workout');

    // Complete at least one set
    const addSet = page.locator('[flt-semantics-identifier="workout-add-set"]').last();
    if (await addSet.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await addSet.click();
      await page.waitForTimeout(600);
    }
    await completeSet(page, 0);

    await ss(page, 'B4-before-finish');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await dialogFinish.click();

    // After finish, check for add-to-plan prompt before navigating
    await page.waitForTimeout(3_000);
    await ss(page, 'B4-after-finish-immediate');

    const aomAfterFinish = await aomDump(page);
    log('[B4] AOM immediately after finish:');
    aomAfterFinish.slice(0, 35).forEach(l => log(`  ${l}`));

    const addToPlanDetected = aomAfterFinish.some(l =>
      l.toLowerCase().includes('add to plan') ||
      l.toLowerCase().includes('add') && l.toLowerCase().includes('plan') ||
      l.toLowerCase().includes('skip') ||
      l.toLowerCase().includes('add routine')
    );
    log(`[B4] Add-to-plan prompt detected in AOM: ${addToPlanDetected}`);

    // Check URL
    const urlB4 = page.url();
    log(`[B4] URL after finish: ${urlB4}`);

    if (!addToPlanDetected) {
      log('[B4] FINDING: Add-to-plan prompt NOT detected after routine workout (routine not in plan)');
    } else {
      log('[B4] PASS: Add-to-plan prompt appeared');
      // Try to tap "Skip" to dismiss
      const skipBtn = page.locator('role=button[name*="Skip"]').first();
      if (await skipBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await skipBtn.click();
        await page.waitForURL(/home/, { timeout: 10_000 });
        log(`[B4] Tapped Skip → ${page.url()}`);
      }
    }

    // Handle PR celebration if it appeared
    if (urlB4.includes('pr-celebration') || page.url().includes('pr-celebration')) {
      await dismissPrCelebrationIfPresent(page);
    }

    await ss(page, 'B4-final');
    log('[B4] DONE');
  });

  // ---------------------------------------------------------
  // B5: Routine workout, IN plan → /home (no prompt)
  // ---------------------------------------------------------
  test('B5 — Routine workout, IN plan → /home (no add-to-plan prompt)', async ({ page }) => {
    await loginUser(page);
    log('[B5] Adding Charter D Test Routine to weekly plan, then starting workout from it');

    // Navigate to home and look for plan your week
    await page.click(NAV.homeTab);
    await page.waitForURL(/home/, { timeout: 10_000 });
    await page.waitForTimeout(1_000);
    await ss(page, 'B5-home');

    // Phase 26f: the legacy `home-plan-your-week` banner was removed. The
    // BucketChipRow now exposes an always-visible "Editar plano" link with
    // identifier `home-edit-plan-link` that pushes /plan/week — same
    // navigation contract, always reachable from home.
    const planYourWeek = page.locator('[flt-semantics-identifier="home-edit-plan-link"]').first();
    const planWeekVisible = await planYourWeek.isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[B5] "Editar plano" link visible: ${planWeekVisible}`);

    if (planWeekVisible) {
      await planYourWeek.click();
      // Plan management screen may render within the /home hash route (Flutter pushes a route internally)
      // Don't wait for URL change — wait for the plan screen content to appear
      await page.waitForTimeout(2_000);
      log(`[B5] URL after tapping Plan your week: ${page.url()}`);
    } else {
      log('[B5] NOTE: Plan your week CTA not visible — routine may already be in plan from B4');
      // Try to navigate to routines and start directly
    }

    await page.waitForTimeout(1_500);
    await ss(page, 'B5-plan-screen');

    const aomPlan = await aomDump(page);
    log('[B5] Plan screen AOM:');
    aomPlan.slice(0, 25).forEach(l => log(`  ${l}`));

    const addRoutinesBtn = page.locator('[flt-semantics-identifier="weekly-plan-add-routines"]').first();
    const addRoutineRow = page.locator('[flt-semantics-identifier="weekly-plan-add-routine-row"]').first();

    const addRoutinesBtnVisible = await addRoutinesBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    const addRoutineRowVisible = await addRoutineRow.isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[B5] Add Routines button: ${addRoutinesBtnVisible}, Add Routine row: ${addRoutineRowVisible}`);

    if (addRoutinesBtnVisible) {
      await addRoutinesBtn.click();
    } else if (addRoutineRowVisible) {
      await addRoutineRow.click();
    } else {
      log('[B5] NOTE: Cannot add routine to plan — buttons not visible. May already be in plan from B4 skip');
      // Proceed anyway — check if routine is already in plan
    }

    if (addRoutinesBtnVisible || addRoutineRowVisible) {
      await page.waitForTimeout(2_000);
      await ss(page, 'B5-add-routines-sheet');

      const routineInSheet = page.locator('text=Charter D Test Routine').first();
      if (await routineInSheet.isVisible({ timeout: 8_000 }).catch(() => false)) {
        await routineInSheet.click();
        await page.waitForTimeout(500);
      } else {
        log('[B5] NOTE: Routine not in add-sheet (may already be in plan or selector issue)');
      }

      const addConfirm = page.locator('[flt-semantics-identifier="weekly-plan-add-confirm"]');
      if (await addConfirm.isVisible({ timeout: 5_000 }).catch(() => false)) {
        await addConfirm.click();
        await page.waitForTimeout(2_000);
        log('[B5] Routine added to plan');
      }
    }

    await ss(page, 'B5-after-add-to-plan');

    // Start routine workout
    await page.click(NAV.routinesTab);
    await page.waitForURL(/routines/, { timeout: 10_000 });
    await page.waitForTimeout(1_000);

    const routineCard = await scrollToVisible(page, 'text=Charter D Test Routine', 15).catch(() => null);
    if (!routineCard) {
      log('[B5] SKIP: Routine card not found after scrolling');
      return;
    }

    await routineCard.click();
    await page.waitForTimeout(2_000);

    const startBtn = page.locator('role=button[name*="Start"]').first();
    if (!await startBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      log('[B5] SKIP: Start workout button not found');
      return;
    }

    await startBtn.click();
    await page.waitForURL(/workout/, { timeout: 15_000 });
    await page.waitForTimeout(1_500);

    // Complete a set
    const addSet = page.locator('[flt-semantics-identifier="workout-add-set"]').last();
    if (await addSet.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await addSet.click();
      await page.waitForTimeout(600);
    }
    await completeSet(page, 0);

    await ss(page, 'B5-before-finish');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await dialogFinish.click();

    await page.waitForTimeout(4_000);
    await ss(page, 'B5-after-finish');

    const aomB5 = await aomDump(page);
    log('[B5] AOM after finish:');
    aomB5.slice(0, 30).forEach(l => log(`  ${l}`));

    const addToPlanDetected = aomB5.some(l =>
      l.toLowerCase().includes('add to plan') ||
      l.toLowerCase().includes('skip') && l.toLowerCase().includes('plan')
    );
    log(`[B5] Add-to-plan prompt detected: ${addToPlanDetected}`);

    const urlB5 = page.url();
    log(`[B5] URL after finish: ${urlB5}`);

    if (addToPlanDetected) {
      log('[B5] BUG: Add-to-plan prompt appeared even though routine was in plan');
    } else {
      log('[B5] PASS: No add-to-plan prompt (routine is already in plan — correct)');
    }

    // Handle PR/celebration if appeared
    if (urlB5.includes('pr-celebration') || page.url().includes('pr-celebration')) {
      await dismissPrCelebrationIfPresent(page);
    }

    log('[B5] DONE');
  });

  // ---------------------------------------------------------
  // B8: Offline + queued save
  // ---------------------------------------------------------
  test('B8 — Offline finish → "Saved offline" snackbar + pending badge', async ({ page }) => {
    await loginUser(page);
    log('[B8] Offline + queued save test');

    await startEmptyWorkout(page);
    await addExercise(page, 'Dumbbell Curl');
    await setWeight(page, '10');
    await setReps(page, '12');
    await completeSet(page, 0);

    const pendingBadge = page.locator('[flt-semantics-identifier="offline-pending-badge"]');
    const pendingBefore = await pendingBadge.isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[B8] Pending sync badge BEFORE offline finish: ${pendingBefore}`);

    // Override fetch to simulate offline
    await page.evaluate(() => {
      (window as any).__originalFetch = window.fetch;
      window.fetch = () => Promise.reject(new TypeError('Failed to fetch'));
    });
    log('[B8] Fetch overridden (simulating offline)');

    await page.waitForTimeout(3_000);
    const offlineBanner = page.locator('[flt-semantics-identifier="offline-banner"]');
    const bannerVisible = await offlineBanner.isVisible({ timeout: 3_000 }).catch(() => false);
    log(`[B8] Offline banner visible: ${bannerVisible}`);
    if (!bannerVisible) {
      log('[B8] NOTE: Consistent with AW-EX-B-US1-03 — offline banner does not fire via fetch override on Flutter Web');
    }

    await ss(page, 'B8-before-finish-offline');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await ss(page, 'B8-finish-dialog-offline');
    await dialogFinish.click();

    // Give time for offline handling
    await page.waitForTimeout(5_000);
    await ss(page, 'B8-after-finish-offline');

    const urlB8 = page.url();
    log(`[B8] URL after offline finish: ${urlB8}`);

    const aomB8 = await aomDump(page);
    log('[B8] AOM after offline finish:');
    aomB8.slice(0, 35).forEach(l => log(`  ${l}`));

    const savedOfflineInAom = aomB8.some(l => l.toLowerCase().includes('saved offline'));
    const queuedInAom = aomB8.some(l => l.toLowerCase().includes('queued') || l.toLowerCase().includes('pending'));
    const pendingAfter = await pendingBadge.isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[B8] "Saved offline" in AOM: ${savedOfflineInAom}`);
    log(`[B8] Queued/pending in AOM: ${queuedInAom}`);
    log(`[B8] Pending badge visible after offline finish: ${pendingAfter}`);
    log(`[B8] On /home: ${urlB8.includes('home')}`);

    if (!savedOfflineInAom && !pendingAfter) {
      log('[B8] FINDING: No "Saved offline" snackbar AND no pending badge after offline finish — offline handling may be silent on Flutter Web');
    } else if (savedOfflineInAom) {
      log('[B8] PASS: "Saved offline" snackbar detected in AOM');
    }

    // Restore fetch
    await page.evaluate(() => {
      if ((window as any).__originalFetch) {
        window.fetch = (window as any).__originalFetch;
      }
    });
    log('[B8] Fetch restored (back online)');

    await page.waitForTimeout(5_000);
    await ss(page, 'B8-after-restore-online');

    const pendingAfterRestore = await pendingBadge.isVisible({ timeout: 2_000 }).catch(() => false);
    log(`[B8] Pending badge after restore: ${pendingAfterRestore}`);
    if (pendingAfter && !pendingAfterRestore) {
      log('[B8] PASS: Sync drain triggered — pending badge cleared after reconnect');
    }

    log('[B8] DONE');
  });

  // ---------------------------------------------------------
  // B9: Server 500 on save
  // ---------------------------------------------------------
  test('B9 — Server 500 on save → error feedback + stays on workout screen', async ({ page }) => {
    await loginUser(page);
    log('[B9] Server 500 on save test');

    await startEmptyWorkout(page);
    await addExercise(page, 'Dumbbell Curl');
    await setWeight(page, '20');
    await setReps(page, '10');
    await completeSet(page, 0);

    // Inject 500 for save endpoint
    await page.evaluate(() => {
      (window as any).__originalFetch = window.fetch;
      window.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
        const url = typeof input === 'string' ? input : (input as Request).url;
        if (url.includes('/rpc/save_workout') || url.includes('save_workout')) {
          return Promise.resolve(new Response(JSON.stringify({ message: 'simulated server error' }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
          }));
        }
        return (window as any).__originalFetch(input, init);
      };
    });
    log('[B9] Fetch override: save_workout returns 500');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await ss(page, 'B9-finish-dialog');
    await dialogFinish.click();

    // Wait for error handling
    await page.waitForTimeout(8_000);
    await ss(page, 'B9-after-500');

    const urlB9 = page.url();
    log(`[B9] URL after 500 error: ${urlB9}`);

    const aomB9 = await aomDump(page);
    log('[B9] AOM after 500 error:');
    aomB9.slice(0, 35).forEach(l => log(`  ${l}`));

    const onWorkout = urlB9.includes('workout');
    const onHome = urlB9.includes('home') && !urlB9.includes('workout');
    log(`[B9] Still on workout screen: ${onWorkout}`);
    log(`[B9] Redirected to home: ${onHome}`);

    const errorInAom = aomB9.some(l =>
      l.toLowerCase().includes('error') ||
      l.toLowerCase().includes('fail') ||
      l.toLowerCase().includes('unable') ||
      l.toLowerCase().includes('could not')
    );
    log(`[B9] Error message in AOM: ${errorInAom}`);

    if (onHome && !errorInAom) {
      log('[B9] FINDING: App silently redirected to /home after 500 error — no error feedback to user');
    } else if (onHome && errorInAom) {
      log('[B9] MIXED: App went to /home but shows error — unusual routing');
    } else if (onWorkout && errorInAom) {
      log('[B9] PASS: App stayed on workout screen with error message visible');
    } else if (onWorkout && !errorInAom) {
      log('[B9] FINDING: App stayed on workout screen but no error message visible in AOM');
    }

    // Check if retry is possible
    if (onWorkout) {
      const finishBtnVisible = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 3_000 }).catch(() => false);
      log(`[B9] Finish button still accessible (can retry): ${finishBtnVisible}`);
    }

    // Restore fetch
    await page.evaluate(() => {
      if ((window as any).__originalFetch) {
        window.fetch = (window as any).__originalFetch;
      }
    });

    // Discard to clean state if still on workout
    if (onWorkout) {
      const discardBtn = page.locator('[flt-semantics-identifier="workout-discard-btn"]');
      if (await discardBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await discardBtn.click();
        const confirmDiscard = page.locator('[flt-semantics-identifier="workout-discard-confirm"]');
        if (await confirmDiscard.isVisible({ timeout: 5_000 }).catch(() => false)) {
          await confirmDiscard.click();
          await page.waitForURL(/home/, { timeout: 10_000 });
        }
      }
    }

    log('[B9] DONE');
  });

  // ---------------------------------------------------------
  // B10: Background mid-save → celebration plays on return
  // ---------------------------------------------------------
  test('B10 — Background mid-save → celebration plays on return', async ({ page }) => {
    await loginUser(page);
    log('[B10] Background mid-save test');

    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    // Use a new PR weight (higher than the 65kg from B3)
    await setWeight(page, '80');
    await setReps(page, '8');
    await completeSet(page, 0);

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });

    // Inject a slow fetch for save endpoint
    await page.evaluate(() => {
      (window as any).__originalFetch = window.fetch;
      window.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
        const url = typeof input === 'string' ? input : (input as Request).url;
        if (url.includes('save_workout')) {
          return new Promise(resolve => {
            setTimeout(() => {
              resolve((window as any).__originalFetch(input, init));
            }, 2_500);
          });
        }
        return (window as any).__originalFetch(input, init);
      };
    });

    // Tap Save & Finish
    await dialogFinish.click();
    log('[B10] Save & Finish tapped — save is delayed 2.5s');

    // Immediately go to background
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'hidden', writable: true, configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    log('[B10] App backgrounded while save in progress');

    await page.waitForTimeout(4_000); // Wait for save to complete

    // Return to foreground
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: true, configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    log('[B10] Returned to foreground');

    await page.waitForTimeout(3_000);
    await ss(page, 'B10-after-foreground');

    const urlB10 = page.url();
    log(`[B10] URL after return to foreground: ${urlB10}`);

    const onCelebration = urlB10.includes('pr-celebration');
    const onHome = urlB10.includes('home');
    const onWorkout = urlB10.includes('workout');
    log(`[B10] On /pr-celebration: ${onCelebration}, /home: ${onHome}, /workout: ${onWorkout}`);

    if (onCelebration) {
      log('[B10] PASS: PR celebration appeared after background mid-save');
      await dismissPrCelebrationIfPresent(page);
    } else if (onHome) {
      log('[B10] NOTE: Went directly to /home — PR celebration may have been skipped during background save');
    } else if (onWorkout) {
      log('[B10] FINDING: Still on workout screen after background+save — navigation may have stalled');
    }

    // Restore fetch
    await page.evaluate(() => {
      if ((window as any).__originalFetch) {
        window.fetch = (window as any).__originalFetch;
      }
    });

    log('[B10] DONE');
  });

  // ---------------------------------------------------------
  // B11: Double-tap Save & Finish
  // ---------------------------------------------------------
  test('B11 — Tap Save & Finish twice rapidly → only one save should fire', async ({ page }) => {
    await loginUser(page);
    log('[B11] Double-tap Save & Finish test');

    await startEmptyWorkout(page);
    await addExercise(page, 'Dumbbell Curl');
    await setWeight(page, '15');
    await setReps(page, '10');
    await completeSet(page, 0);

    // Count save_workout requests
    const saveRequests: string[] = [];
    page.on('request', req => {
      if (req.url().includes('save_workout')) {
        saveRequests.push(req.url());
        log(`[B11] save_workout request intercepted: ${req.url().slice(0, 80)}`);
      }
    });

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await ss(page, 'B11-dialog-open');

    // Get the bounding box of the Save & Finish button
    const btnBox = await dialogFinish.boundingBox();
    log(`[B11] Save & Finish button bounding box: ${JSON.stringify(btnBox)}`);

    if (btnBox) {
      const cx = btnBox.x + btnBox.width / 2;
      const cy = btnBox.y + btnBox.height / 2;

      // Click twice rapidly via mouse events (300ms apart)
      await page.mouse.click(cx, cy);
      await page.waitForTimeout(80); // 80ms gap — within 300ms threshold
      await page.mouse.click(cx, cy);
      log('[B11] Dispatched two rapid mouse clicks (80ms apart)');
    } else {
      // Fallback: use Playwright click twice
      await dialogFinish.click();
      await page.waitForTimeout(80);
      await dialogFinish.click().catch(() => {});
      log('[B11] Fallback: two Playwright clicks (80ms apart)');
    }

    await page.waitForTimeout(8_000);
    await page.waitForURL(/\/(home|pr-celebration|workout)/, { timeout: 20_000 }).catch(() => {}); // workout already covers workout/finish/
    await ss(page, 'B11-after-double-tap');

    log(`[B11] Total save_workout requests intercepted: ${saveRequests.length}`);
    const urlB11 = page.url();
    log(`[B11] URL after double-tap: ${urlB11}`);

    if (saveRequests.length === 0) {
      log('[B11] NOTE: No save_workout requests intercepted — Supabase calls may use a different URL pattern');
    } else if (saveRequests.length === 1) {
      log('[B11] PASS: Only one save_workout request (double-tap correctly handled)');
    } else {
      log(`[B11] BUG: ${saveRequests.length} save_workout requests fired from double-tap`);
    }

    // Dismiss celebration if appeared
    if (urlB11.includes('pr-celebration')) {
      await dismissPrCelebrationIfPresent(page);
    } else if (urlB11.includes('workout')) {
      // Still on workout — discard to clean state
      const discardBtn = page.locator('[flt-semantics-identifier="workout-discard-btn"]');
      if (await discardBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await discardBtn.click();
        const confirmDiscard = page.locator('[flt-semantics-identifier="workout-discard-confirm"]');
        if (await confirmDiscard.isVisible({ timeout: 5_000 }).catch(() => false)) {
          await confirmDiscard.click();
        }
      }
    }

    log('[B11] DONE');
  });

  // ---------------------------------------------------------
  // B12: Cancel from loading overlay (10s wait)
  // ---------------------------------------------------------
  test('B12 — Cancel from loading overlay after 10s', async ({ page }) => {
    await loginUser(page);
    log('[B12] Loading overlay cancel button test');

    await startEmptyWorkout(page);
    await addExercise(page, 'Dumbbell Curl');
    await setWeight(page, '15');
    await setReps(page, '12');
    await completeSet(page, 0);

    // Inject a never-resolving fetch for save endpoint
    await page.evaluate(() => {
      (window as any).__originalFetch = window.fetch;
      window.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
        const url = typeof input === 'string' ? input : (input as Request).url;
        if (url.includes('save_workout') || url.includes('/rpc/')) {
          log('[B12-JS] Intercepting save request — returning never-resolving promise');
          return new Promise(() => {}); // Never resolves
        }
        return (window as any).__originalFetch(input, init);
      };
    });
    log('[B12] Fetch override: save_workout never resolves');

    await page.click(WORKOUT.finishButton);
    const dialogFinish = page.locator(WORKOUT.dialogFinishButton);
    await expect(dialogFinish).toBeVisible({ timeout: 8_000 });
    await ss(page, 'B12-finish-dialog');
    await dialogFinish.click();
    log('[B12] Tapped Save & Finish — loading overlay should start');

    // Screenshot at 2s (loading state)
    await page.waitForTimeout(2_000);
    await ss(page, 'B12-loading-2s');

    const aomAt2s = await aomDump(page);
    log('[B12] AOM at 2s:');
    aomAt2s.slice(0, 20).forEach(l => log(`  ${l}`));

    // Wait for 11s total (cancel button appears after 10s)
    await page.waitForTimeout(9_000);
    await ss(page, 'B12-loading-11s');

    log('[B12] Checking for cancel button after ~11s...');
    const aomAt11s = await aomDump(page);
    log('[B12] AOM at 11s:');
    aomAt11s.slice(0, 30).forEach(l => log(`  ${l}`));

    // Look for cancel button
    const cancelButton = page.locator('role=button[name*="Cancel"]').first();
    const cancelVisible = await cancelButton.isVisible({ timeout: 5_000 }).catch(() => false);
    log(`[B12] Cancel button visible after 11s: ${cancelVisible}`);

    if (!cancelVisible) {
      // Check all buttons in AOM
      const allButtons = aomAt11s.filter(l => l.includes('[button]'));
      log(`[B12] All buttons in AOM at 11s: ${allButtons.join(', ')}`);
      log('[B12] FINDING: No cancel button appeared after 11s loading — loading overlay cancel button may be missing or not accessible');
    } else {
      const urlBeforeCancel = page.url();
      log(`[B12] URL before cancel: ${urlBeforeCancel}`);

      await cancelButton.click();
      await page.waitForTimeout(2_000);
      await ss(page, 'B12-after-cancel');

      const urlAfterCancel = page.url();
      log(`[B12] URL after cancel: ${urlAfterCancel}`);

      const onWorkout = urlAfterCancel.includes('workout');
      log(`[B12] Back on workout screen after cancel: ${onWorkout}`);

      if (onWorkout) {
        log('[B12] PASS: Stayed on workout screen — state restored, can retry');
        const finishBtnVisible = await page.locator(WORKOUT.finishButton).isVisible({ timeout: 3_000 }).catch(() => false);
        log(`[B12] Finish button accessible (retry possible): ${finishBtnVisible}`);
      } else {
        log(`[B12] FINDING: After cancel, went to ${urlAfterCancel} instead of workout screen`);
      }
    }

    // Restore fetch
    await page.evaluate(() => {
      if ((window as any).__originalFetch) {
        window.fetch = (window as any).__originalFetch;
      }
    });

    log('[B12] DONE');
  });

  // ---------------------------------------------------------
  // FINAL: Print all findings summary
  // ---------------------------------------------------------
  test('FINAL — print all charter D findings', async () => {
    console.log('\n\n========== CHARTER D FINDINGS ==========');
    FINDINGS.forEach(f => console.log(f));
    console.log(`\nTotal findings: ${FINDINGS.length}`);
    console.log('========================================\n');
    expect(FINDINGS.length).toBeGreaterThan(0);
  });
});
