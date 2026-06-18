/**
 * Cardio — consolidated end-to-end journey (Phase 38g).
 *
 * Cardio shipped across Phases 38a–38f in pieces (XP gating, CardioEntryCard,
 * post-session age prompt, Saga 7th-track row, debrief row, titles catalog).
 * This feature spec walks the WHOLE cardio arc a real user lives, in one place,
 * asserting user-perceptible outcomes (not wiring):
 *
 *   Journey A — log a cardio session in a live workout (smokeAgeCapture user):
 *     add a cardio exercise → CardioEntryCard → complete the entry → finish →
 *     the post-session debrief shows the cardio entry row. This proves the
 *     full earn path end-to-end through the real UI.
 *
 *   Journey B — cardio is a first-class progression track (rpgCardioActiveUser,
 *     pre-seeded cardio rank 5 / 168 XP):
 *     the Saga rail shows the teal cardio progression row with a real rank, and
 *     tapping it routes to the cardio stats deep-dive
 *     (/saga/stats?body_part=cardio). And the character level REFLECTS cardio:
 *     it is the value the 7-part level math yields (Lvl 3), strictly above the
 *     strength-only baseline (Lvl 2) — i.e. cardio counts toward level.
 *
 * Deliberately NOT duplicated here (cross-referenced instead):
 *   - The cardio-XP-gating unit/widget contract (cardio earns no strength XP)
 *     is pinned by Dart tests, not E2E.
 *   - The Saga 7th-track render + route is also pinned granularly in
 *     `saga.spec.ts` → "Saga — cardio is a visible 7th track" (S14). This spec
 *     re-walks it as part of the consolidated journey so the full arc lives in
 *     one feature file; the saga.spec.ts block is the focused regression guard.
 *   - The debrief CardioEntryRow journey previously lived as its own block in
 *     `post_session.spec.ts` → "Post-session cardio debrief row". That block is
 *     removed in this phase: Journey A here is the exact same flow (Treadmill →
 *     complete → finish → debrief row) on the same user, so keeping both would
 *     run the slow log-and-finish path twice. cardio.spec.ts now owns it.
 *   - The cardio title's presence in the catalog is pinned by the "/ 106"
 *     counter assertion in `titles.spec.ts` (T3). An earned-cardio-title flow
 *     needs a dedicated earned-title user and is heavier than this journey
 *     warrants, so it is cross-referenced, not re-pinned here.
 *
 * Users (both already exist — no new fixture/global-setup user needed):
 *   - smokeAgeCapture: lapsed user wired for the cardio-only
 *     Treadmill flow (Treadmill seeds a default 30:00 CardioSession on add → the
 *     "Complete cardio" CTA is enabled immediately). Reused for Journey A.
 *   - rpgCardioActiveUser: cardio TRAINED (rank 5 / 168 XP) + two strength
 *     tracks (chest 3, legs 3) seeded directly into body_part_progress. Used
 *     for Journey B (Saga row + routing + level math).
 */

import { test, expect, type Page } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab } from '../helpers/app';
import {
  startEmptyWorkout,
  addExercise,
  finishWorkout,
} from '../helpers/workout';
import { WORKOUT, POST_SESSION, SAGA, CARDIO } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';
import {
  getAdminClient,
  getUserIdByEmail,
} from '../helpers/test-data-reset';

// ===========================================================================
// Journey A — log a cardio session end-to-end → see it in the debrief.
//
// User: smokeAgeCapture. Per-test reseed + serial mode keep
// the workout/cardio chain deterministic (cluster
// e2e-spec-state-leak-across-tests): cardio_sessions cascade-delete with their
// parent workout, so wiping workouts clears any prior in-flight cardio entry.
// A finished warmup workout is re-seeded so startEmptyWorkout resolves the
// "Free workout" ActionHero rather than the day-0 create-first-routine CTA.
// ===========================================================================

async function reseedCardioJourneyUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('smokeAgeCapture').email);
  if (!userId) return;
  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  const now = new Date();
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Cardio Journey Warmup',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

test.describe('Cardio', { tag: '@smoke' }, () => {
  // Serial + per-test reseed: the describe shares one user and Journey A
  // mutates workout state, so reseed-before-each keeps each run deterministic
  // under --workers>1 / --repeat-each (cluster e2e-spec-state-leak-across-tests).
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await reseedCardioJourneyUser();
    await login(
      page,
      getUser('smokeAgeCapture').email,
      getUser('smokeAgeCapture').password,
    );
  });

  test('should log a cardio session and surface it in the post-session debrief', async ({
    page,
  }) => {
    // --- Log the cardio session through the real UI ---
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.treadmill);

    // Adding Treadmill seeds a default 30:00 CardioSession, so "Complete cardio"
    // is enabled with no further input. The identifier wraps the OutlinedButton
    // with explicitChildNodes:true → force-click dispatches the tap onto it
    // (cluster aom-explicit-children-block-name-merge).
    await page.locator(CARDIO.complete).first().scrollIntoViewIfNeeded();
    await page.locator(CARDIO.complete).first().click({ force: true });

    // Behavior: the entry flips to the completed state (green ✓ uncomplete
    // affordance appears) — the user SEES the cardio entry register as done.
    await expect(page.locator(CARDIO.uncomplete).first()).toBeVisible({
      timeout: 10_000,
    });

    // A completed cardio entry is sufficient to enable FINISH (the gate accepts
    // "one completed set OR cardio entry"). Finish the session.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });
    await finishWorkout(page);

    // --- Land on the post-session summary, past the cinematic ---
    await page.waitForURL(/\/workout\/finish\//, { timeout: 15_000 });
    const skip = page.locator(POST_SESSION.skipBtn);
    if (await skip.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await skip.click();
    }
    await expect(page.locator(POST_SESSION.summary)).toBeVisible({
      timeout: 15_000,
    });

    // Behavior: the debrief ledger renders AND it contains the cardio entry
    // the user just logged (sourced from state.cardioEntries, the teal duration
    // hero — not a strength lift row).
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    const cardioRow = page
      .locator(POST_SESSION.missionDebriefCardioRow)
      .first();
    await cardioRow.scrollIntoViewIfNeeded();
    await expect(cardioRow).toBeVisible({ timeout: 10_000 });
  });
});

// ===========================================================================
// Journey B — cardio is a first-class progression track: Saga row + routing
// + character level reflects cardio.
//
// User: rpgCardioActiveUser — cardio seeded TRAINED (rank 5 / 168 XP) plus two
// strength tracks (chest 3, legs 3). Read-only navigation; per-test reseed of
// the cardio progress row keeps the alive variant deterministic regardless of
// any prior-run mutation (cluster e2e-spec-state-leak-across-tests).
//
// Character-level math (7-part: chest, back, legs, shoulders, arms, core,
// cardio; absent keys skipped):
//   WITH cardio    → ranks present = cardio 5, chest 3, legs 3
//                    → floor((5+3+3 − 3) / 4) + 1 = floor(8/4) + 1 = 3
//   strength-only  → ranks present = chest 3, legs 3
//                    → floor((3+3 − 2) / 4) + 1 = floor(4/4) + 1 = 2
// So Lvl 3 is the exact value the 7-part math yields, and it is strictly above
// the Lvl-2 strength-only baseline → cardio's rank-5 contribution COUNTS toward
// the character level (the never-regress thesis, observed at the user surface).
// ===========================================================================

const CARDIO_ACTIVE_LEVEL = 3; // 7-part math over cardio 5 / chest 3 / legs 3
const STRENGTH_ONLY_BASELINE_LEVEL = 2; // same ranks, cardio excluded

async function readCharacterLevel(page: Page): Promise<number> {
  const lvlEl = page.locator(SAGA.characterLevel).first();
  await lvlEl.waitFor({ state: 'visible', timeout: 15_000 });
  const label =
    (await lvlEl.getAttribute('aria-label')) ??
    (await lvlEl.textContent({ timeout: 3_000 })) ??
    '';
  const match = label.match(/Lvl (\d+)/);
  if (match) return parseInt(match[1], 10);
  throw new Error(
    `Could not read Lvl from character sheet; character-level label was: "${label}"`,
  );
}

test.describe('Cardio progression track', () => {
  // Serial + per-test cardio-row reseed: deterministic alive cardio row.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(
      admin,
      getUser('rpgCardioActiveUser').email,
    );
    if (userId) {
      // Re-apply the trained-cardio row so it is alive regardless of any
      // prior-run mutation. vitality values keep it out of the untrained branch.
      await admin.from('body_part_progress').upsert(
        {
          user_id: userId,
          body_part: 'cardio',
          total_xp: 168,
          rank: 5,
          vitality_ewma: 0.58,
          vitality_peak: 0.92,
        },
        { onConflict: 'user_id,body_part' },
      );
    }

    await login(
      page,
      getUser('rpgCardioActiveUser').email,
      getUser('rpgCardioActiveUser').password,
    );
    await navigateToTab(page, 'Profile');
    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });
  });

  test('should show the teal cardio row on the Saga rail and route to its stats deep-dive', async ({
    page,
  }) => {
    // The cardio row sits below the six strength rows (after the surface2
    // divider) so it can be below the fold — scroll it in.
    const cardioRow = page.locator(SAGA.cardioProgressRow).first();
    await cardioRow.scrollIntoViewIfNeeded();
    await expect(cardioRow).toBeVisible({ timeout: 10_000 });

    // Tapping the cardio row routes to the cardio stats deep-dive. Assert on
    // destination content, NOT the URL (cluster flutter-web-url-assertion).
    await cardioRow.click();
    await expect(page.locator(SAGA.statsDeepDiveScreen).first()).toBeVisible({
      timeout: 10_000,
    });

    // Pre-selection proof the body_part=cardio query param reached the screen:
    // the cardio vitality row is marked selected. Flutter web emits
    // aria-current (NOT aria-selected) for Semantics(selected:) on a
    // button-role node (cluster flutter-web-aom-selectable-attribute).
    await expect(
      page.locator(SAGA.vitalityRow('cardio')).first(),
    ).toHaveAttribute('aria-current', 'true', { timeout: 10_000 });
  });

  test('should reflect cardio in the character level (above the strength-only baseline)', async ({
    page,
  }) => {
    // The character sheet is already visible from beforeEach. Read the level
    // numeral from the AOM (canvaskit renders the text to canvas).
    const level = await readCharacterLevel(page);

    // Exact value the 7-part level math yields for cardio 5 / chest 3 / legs 3.
    expect(level).toBe(CARDIO_ACTIVE_LEVEL);
    // And — the load-bearing behavior — it is strictly above the level the
    // SAME strength ranks alone would produce. Cardio counts toward the level.
    expect(level).toBeGreaterThan(STRENGTH_ONLY_BASELINE_LEVEL);
  });
});
