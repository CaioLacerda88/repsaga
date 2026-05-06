/**
 * Personal Records content localization — E2E scenario F1.
 * Phase 15f: exercise names in PR list resolved from exercise_translations.
 *
 * Scenarios:
 *   F1 — pt user sees PR list with pt exercise names
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { PR_DISPLAY } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { EXERCISE_NAMES } from '../fixtures/test-exercises';

// =============================================================================
// FULL: PR list pt locale (F1)
// Uses fullPRPt user (pt locale, PR data seeded via seedPRData for
// barbell_bench_press — guarantees at least one PR card renders).
// =============================================================================

test.describe('Personal records pt locale', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullPRPt').email,
      getUser('fullPRPt').password,
    );
  });

  // F1: pt user sees PR list with pt exercise names.
  test('should show pt exercise name in PR list for pt user (F1)', async ({
    page,
  }) => {
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;

    // Navigate to /records via SPA hash navigation. Direct page.goto returns
    // 404 from the static file server — the established pattern (see
    // personal-records.spec.ts) is to drive go_router via window.location.hash.
    await page.evaluate(() => {
      window.location.hash = '#/records';
    });
    await page.waitForURL('**/records**', { timeout: 10_000 });

    // The PR screen header must be visible.
    await expect(page.locator(PR_DISPLAY.screenTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Hard fail if the seed didn't materialize: PR screen MUST show the
    // bench press card. fullPRPt is seeded with one PR for barbell_bench_press
    // by seedPRData — empty state here is a regression.
    await expect(
      page.locator(PR_DISPLAY.exerciseRecordCard).first(),
    ).toBeVisible({ timeout: 10_000 });

    // F1 primary contract: the seeded barbell_bench_press PR must render the
    // pt-localized exercise name. _ExerciseRecordCard wraps its content in
    // Semantics(container: true), which merges child Text widgets into the
    // parent group's accessibility label — so we match the merged AOM label
    // (e.g. "Supino Reto com Barra 100 kg × 5") via role=group[name*=...],
    // not via `text=...` (which would find no node).
    await expect(
      page.locator(PR_DISPLAY.exerciseRecordCardByName(ptBenchName)).first(),
    ).toBeVisible({ timeout: 5_000 });

    // F1 second contract: the en name must NOT appear anywhere on the PR
    // screen for this pt user. This guards against locale leakage from the
    // two-query merge (PRs + names) — names must be resolved in the pt
    // locale, not fallback to en when both exist. Same role= matching as
    // above so the negative is a real check (not a tautology against text=
    // selectors that match nothing in the merged-Semantics tree).
    await expect(
      page.locator(PR_DISPLAY.exerciseRecordCardByName(enBenchName)),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});
