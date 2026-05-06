/**
 * Gamification intro spec — Phase 17b.
 *
 * Tests the SagaIntroGate + SagaIntroOverlay first-run flow:
 *   1. Fresh user sees the 3-step SagaIntroOverlay on first home load.
 *   2. After dismissal the overlay does not re-appear on page reload
 *      (Hive `saga_intro_seen` flag persists in IndexedDB).
 *   3. The LVL badge is visible on HomeScreen after the flow completes.
 *
 * User: `sagaIntroUser` — created by global-setup with a profile row (so
 * the router lands on /home, not /onboarding) and zero workout history
 * (retro yields 0 XP → LVL 1 on first launch).
 *
 * Hive is keyed per-user and stored in browser IndexedDB. Within a single
 * Playwright browser context (same `page` object) storage persists across
 * reloads — which is exactly the "same device" scenario. Across separate
 * browser contexts (separate `page` objects) storage is isolated by default
 * because Playwright spawns each test with a fresh browser context.
 * We rely on this isolation so each test starts with a clean Hive state.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { dismissSagaIntroOverlay, waitForAppReady } from '../helpers/app';
import { NAV, GAMIFICATION } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

// ---------------------------------------------------------------------------
// Smoke — gamification intro flow (Phase 17b)
// ---------------------------------------------------------------------------
test.describe('Gamification intro', { tag: '@smoke' }, () => {
  // --------------------------------------------------------------------------
  // Test 1: 3-step overlay appears on first mount and can be dismissed.
  //
  // Flow: login → overlay step 0 visible → NEXT → step 1 → NEXT → step 2
  //       → BEGIN → overlay gone → home nav visible (shell intact).
  //
  // Phase 18b: _LvlBadge removed from HomeScreen. The sagaIntroUser has zero
  // workout history. After dismissal the shell renders without crash.
  // --------------------------------------------------------------------------
  test('should show saga intro overlay on first mount and advance through all 3 steps to dismiss', async ({
    page,
  }) => {
    await login(
      page,
      getUser('sagaIntroUser').email,
      getUser('sagaIntroUser').password,
      { dismissSagaIntro: false },
    );

    // The SagaIntroGate kicks retro_backfill_xp in a post-frame callback and
    // shows the overlay once xpProvider resolves. Give the RPC time to return.
    // Step 0 must appear before we can interact with the overlay.
    await expect(page.locator(GAMIFICATION.step0)).toBeVisible({
      timeout: 20_000,
    });

    // Verify only step 0 is rendered at this point (step 1 and 2 are not yet shown).
    await expect(page.locator(GAMIFICATION.step1)).not.toBeVisible({
      timeout: 3_000,
    });

    // NEXT → step 1.
    await page.locator(GAMIFICATION.nextButton).click();
    await expect(page.locator(GAMIFICATION.step1)).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(GAMIFICATION.step0)).not.toBeVisible({
      timeout: 3_000,
    });

    // NEXT → step 2.
    await page.locator(GAMIFICATION.nextButton).click();
    await expect(page.locator(GAMIFICATION.step2)).toBeVisible({
      timeout: 5_000,
    });

    // BEGIN → overlay dismissed.
    await page.locator(GAMIFICATION.beginButton).click();

    // Overlay is gone; home navigation is accessible.
    await expect(page.locator(GAMIFICATION.step0)).not.toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(GAMIFICATION.step2)).not.toBeVisible({
      timeout: 3_000,
    });
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 5_000 });

    // Phase 18b: _LvlBadge was removed from HomeScreen in favour of the
    // full character sheet on /profile. After the overlay dismisses, the home
    // navigation must be accessible (the shell renders with no badge crash).
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 10_000 });
  });

  // --------------------------------------------------------------------------
  // Test 2: Overlay does NOT re-appear after dismissal on the same device.
  //
  // After dismissing the overlay (test 1's flow) within the same browser
  // context, we reload the page and verify the overlay is absent. Hive
  // stores the `saga_intro_seen` flag in browser IndexedDB, which persists
  // across reloads within the same browser context (same "device" semantics).
  // --------------------------------------------------------------------------
  test('should not re-show overlay after dismissal on page reload', async ({
    page,
  }) => {
    await login(
      page,
      getUser('sagaIntroUser').email,
      getUser('sagaIntroUser').password,
      { dismissSagaIntro: false },
    );

    await dismissSagaIntroOverlay(page);

    // Reload the page — Hive (IndexedDB) persists within the same browser
    // context, so `saga_intro_seen` remains true.
    await page.reload();
    await waitForAppReady(page);

    // The router redirects to /home because the user is still authenticated.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

    // Wait for the home screen to settle (nav tabs are the presence signal now
    // that _LvlBadge was removed in Phase 18b — the character sheet on /profile
    // is the canonical XP surface). Asserting homeTab visible before asserting
    // overlay absent prevents the race where the app is still initializing.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 5_000 });

    // Overlay must NOT re-appear — the Hive flag gate in SagaIntroGate
    // (hasSeenSagaIntroForUser) must suppress it.
    await expect(page.locator(GAMIFICATION.step0)).not.toBeVisible({
      timeout: 3_000,
    });
  });

  // --------------------------------------------------------------------------
  // Test 3: Home navigation renders correctly after saga intro dismissal.
  //
  // Phase 18b removed _LvlBadge from HomeScreen (superseded by the character
  // sheet on /profile). After overlay dismissal the shell must render with the
  // bottom nav visible and no crash. Level is shown on the Saga tab instead.
  // --------------------------------------------------------------------------
  test('should render home navigation correctly after saga intro dismissal', async ({
    page,
  }) => {
    await login(
      page,
      getUser('sagaIntroUser').email,
      getUser('sagaIntroUser').password,
      { dismissSagaIntro: false },
    );

    await dismissSagaIntroOverlay(page);

    // Phase 18b: _LvlBadge was removed from HomeScreen. After overlay dismissal
    // the home navigation must render correctly (no crash, no blank screen).
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 10_000 });
  });
});
