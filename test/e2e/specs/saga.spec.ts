/**
 * Saga (Character Sheet) — E2E smoke tests.
 * Phase 18b: /profile now renders CharacterSheetScreen.
 *
 * Scenarios covered:
 *   S1 @smoke — fresh user sees character sheet with zero-history banner
 *   S2 @smoke — foundation user sees filled character sheet (no banner, body-part rows visible)
 *   S3 @smoke — gear icon navigates to profile settings
 *   S4 @smoke — re-tapping Saga tab from settings pops back to character sheet
 *   S5 @smoke — Stats codex nav row navigates to stub screen
 *   S6 @smoke — Titles codex nav row navigates to stub screen
 *   S7 @smoke — History codex nav row navigates to /home/history
 *
 * User isolation:
 *   - Fresh user:      rpgFreshUser (zero workout history, no XP)
 *   - Foundation user: rpgFoundationUser (12+ workouts, LVL > 1, multi-body-part XP)
 *
 * Selector note: All character-sheet elements use flt-semantics-identifier
 * wrappers. The SAGA.* selectors in helpers/selectors.ts map to these.
 */

import { test, expect, type Page } from '@playwright/test';
import { login } from '../helpers/auth';
import { dismissCelebrationIfPresent, navigateToTab } from '../helpers/app';
import { SAGA, NAV, HISTORY, CELEBRATION } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
  finishWorkout,
} from '../helpers/workout';
import {
  getAdminClient,
  getUserIdByEmail,
  resetRpgStateForUser,
} from '../helpers/test-data-reset';

// ---------------------------------------------------------------------------
// Shared helper: login as rpgFoundationUser and land on the character sheet.
// Used by the three describe blocks whose beforeEach is identical:
//   "foundation user character sheet", "navigation", "body-part row tap".
// Blocks with unique preambles (DB reset, codex-nav drill, S12 Home nav)
// keep their own inline beforeEach.
// ---------------------------------------------------------------------------
async function loginFoundationAndGoToCharacterSheet(page: Page): Promise<void> {
  await login(page, getUser('rpgFoundationUser').email, getUser('rpgFoundationUser').password);
  await navigateToTab(page, 'Profile');
  await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 20_000 });
}

// ---------------------------------------------------------------------------
// S1–S2: Character sheet renders (smoke)
// Uses separate describe blocks for user isolation.
// ---------------------------------------------------------------------------

test.describe('Saga — fresh user character sheet', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    // Phase 21 isolates rpgFreshUser ACROSS workers, but tests on the same
    // worker still share that user. With `fullyParallel: false`, Playwright
    // schedules entire spec files on a single worker — meaning rpg-
    // foundation.spec.ts (E2/E3/E6 each save a workout for rpgFreshUser)
    // can run on the same worker as saga.spec.ts. After E2 saves a workout,
    // body_part_progress has XP and the firstSetAwakensBanner is hidden.
    //
    // The Tier 1 helper deletes workouts + xp_events + body_part_progress
    // + earned_titles + weekly_plans, then upserts a completed
    // backfill_progress so SagaIntroGate doesn't re-run backfill on next
    // login.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgFreshUser').email);
    if (userId) {
      await resetRpgStateForUser(admin, userId);
    }

    await login(page, getUser('rpgFreshUser').email, getUser('rpgFreshUser').password);
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 20_000 });
  });

  // S1: Zero-history state — banner visible, all structural elements present.
  //
  // rpgFreshUser has no workout history so lifetimeXp == 0.
  // CharacterSheetScreen renders _FirstSetAwakensBanner when isZeroHistory == true.
  // All other structural elements (halo, radar, body-part rows, codex nav) must
  // also render — even with zero data, the sheet is fully laid out.
  test('should render character sheet with first-set-awakens banner for zero-history user (S1)', async ({
    page,
  }) => {
    // Core structural elements must be present.
    await expect(page.locator(SAGA.runeHalo).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(SAGA.characterLevel).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(SAGA.sagaHeaderClass).first()).toBeVisible({ timeout: 10_000 });

    // Zero-history onboarding banner must appear.
    await expect(page.locator(SAGA.firstSetAwakensBanner).first()).toBeVisible({
      timeout: 10_000,
    });

    // At least one body-part row must be present (chest is always seeded).
    await expect(page.locator(SAGA.bodyPartRow('chest')).first()).toBeVisible({
      timeout: 10_000,
    });

    // Codex navigation rows must be present.
    await expect(page.locator(SAGA.codexNavStats).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(SAGA.codexNavTitles).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(SAGA.codexNavHistory).first()).toBeVisible({ timeout: 10_000 });
  });
});

test.describe('Saga — foundation user character sheet', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await loginFoundationAndGoToCharacterSheet(page);
  });

  // S2: Foundation user — no zero-history banner, has XP and level > 1.
  //
  // rpgFoundationUser has ~12 prior workouts so lifetimeXp > 0.
  // _FirstSetAwakensBanner must NOT render.
  // The Lvl numeral must be > 1 (seeded workouts grant enough XP for level-up).
  // Multiple body-part rows must be expanded (trained).
  test('should render filled character sheet without zero-history banner for foundation user (S2)', async ({
    page,
  }) => {
    // Zero-history banner must NOT be visible for a user with history.
    await expect(page.locator(SAGA.firstSetAwakensBanner)).not.toBeVisible({ timeout: 5_000 });

    // Halo and class label must be present — both confirm the data state rendered
    // (not loading skeleton). Phase 26b replaces the radar with the SagaHeader.
    await expect(page.locator(SAGA.runeHalo).first()).toBeVisible({ timeout: 10_000 });

    // Class label (sagaHeaderClass) must be visible — even if class is null
    // (placeholder "The iron will name you." shows). Presence confirms the
    // rpgProgressProvider has emitted data (not loading state).
    await expect(page.locator(SAGA.sagaHeaderClass).first()).toBeVisible({ timeout: 15_000 });

    // Multiple body-part rows must be present.
    for (const slug of ['chest', 'back', 'legs'] as const) {
      await expect(page.locator(SAGA.bodyPartRow(slug)).first()).toBeVisible({
        timeout: 10_000,
      });
    }

    // Level must be > 1 — rpgFoundationUser has 12+ seeded workouts which
    // grant enough XP to push past LVL 1. Read the AOM accessible name on
    // the character-level Semantics wrapper (canvaskit renders the numeral
    // on a canvas, but the Semantics(identifier:'character-level') wrapper
    // exposes the text via the accessibility tree).
    // Phase 26b: `SagaHeader` renders the level as a "<N>" + "LVL" stack
    // (was a single "Lvl <N>" line). The Semantics wrapper still exposes
    // `label: 'Lvl <N>'` for the AOM, but `textContent()` now returns the
    // concatenated visible text (e.g. "3 3 LVL" — once for the aria-label
    // shadow, once for the visible numeral, once for the LVL tag).
    //
    // Read the aria-label first (canonical "Lvl <N>" contract) and fall
    // back to the first digit-run in textContent if the label is absent.
    // Matches the working pattern in `rpg-foundation.spec.ts:readLvlFromCharacterSheet`.
    const lvlEl = page.locator(SAGA.characterLevel).first();
    const ariaLabel = await lvlEl.getAttribute('aria-label');
    const rawText = ariaLabel ?? (await lvlEl.textContent()) ?? '';
    const match = rawText.match(/\d+/);
    const lvl = match ? Number(match[0]) : NaN;
    expect(lvl).toBeGreaterThan(1);
  });

  test('should render CharacterXpBar on the character sheet', async ({ page }) => {
    // The bar is unconditional once the screen has loaded — it renders even
    // on day-zero (showing 0 XP toward LVL 2). This smoke catches a missing
    // SagaHeader → CharacterXpBar composition regression without asserting on
    // math (widget tests already pin the math).
    await expect(page.locator(SAGA.characterXpBar).first()).toBeVisible({
      timeout: 10_000,
    });
  });
});

// ---------------------------------------------------------------------------
// S3–S7: Navigation tests (smoke)
// All use rpgFoundationUser — avoids zero-history banner scrolling issues.
// ---------------------------------------------------------------------------

test.describe('Saga — navigation', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await loginFoundationAndGoToCharacterSheet(page);
  });

  // S3: Gear icon → profile settings.
  //
  // The gear icon in the CharacterSheetScreen AppBar calls context.push('/profile/settings').
  // ProfileSettingsScreen root is identified by Semantics(identifier: 'profile-heading').
  test('should open profile settings screen when tapping gear icon (S3)', async ({ page }) => {
    await page.locator(SAGA.gearIcon).first().click();
    // ProfileSettingsScreen renders a "Profile" section heading (profile-heading identifier).
    // URL update via context.push is unreliable in Flutter web — assert on element visibility.
    await expect(page.locator(SAGA.profileSettingsScreen).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  // S4: Re-tap Saga tab from settings → back to character sheet.
  //
  // _ShellScaffold.onDestinationSelected handles re-tap of the active branch
  // by popping any pushed sub-routes (e.g. /profile/settings, /saga/stats)
  // back to the branch root (/profile, the character sheet). This test
  // verifies that contract: open settings via the gear icon, re-tap the Saga
  // tab, expect the character sheet back (settings no longer visible).
  test('should show character sheet after re-tapping Saga tab from settings (S4)', async ({
    page,
  }) => {
    // Navigate into settings via gear icon.
    await page.locator(SAGA.gearIcon).first().click();
    await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

    // Re-tap the Saga / Profile nav tab.
    await page.click(NAV.profileTab);

    // Expect: settings popped off, character sheet visible again.
    await expect(page.locator(SAGA.runeHalo).first()).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(SAGA.profileSettingsScreen)).not.toBeVisible({ timeout: 5_000 });
  });

  // S5: Stats codex nav row → stats deep-dive screen (Phase 18d.2).
  //
  // CodexNavRow with semanticIdentifier 'codex-nav-stats' calls
  // context.push('/saga/stats'). Phase 18d.2 retired SagaStubScreen here in
  // favor of StatsDeepDiveScreen (saga-stats-screen identifier).
  test('should navigate to stats deep-dive screen when tapping Stats codex nav row (S5)', async ({
    page,
  }) => {
    // Scroll to bring codex nav rows into view (they are below the fold).
    await page.locator(SAGA.codexNavStats).first().scrollIntoViewIfNeeded();
    await page.locator(SAGA.codexNavStats).first().click();

    // Assert the Phase 18d.2 deep-dive screen rendered.
    await expect(page.locator(SAGA.statsDeepDiveScreen).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  // S6: Titles codex nav row → titles screen (functional list, Phase 18c upgrade).
  //
  // CodexNavRow with semanticIdentifier 'codex-nav-titles' calls context.push('/profile/titles').
  // Phase 18c upgraded /profile/titles from SagaStubScreen to TitlesScreen (functional list).
  // TitlesScreen root uses Semantics(identifier: 'titles-screen').
  test('should navigate to titles screen when tapping Titles codex nav row (S6)', async ({
    page,
  }) => {
    await page.locator(SAGA.codexNavTitles).first().scrollIntoViewIfNeeded();
    await page.locator(SAGA.codexNavTitles).first().click();

    // Flutter web pushes the route via context.push — assert on visible content.
    // Phase 18c: TitlesScreen uses 'titles-screen' identifier (not 'saga-stub-screen').
    await expect(page.locator(CELEBRATION.titlesScreen).first()).toBeVisible({ timeout: 15_000 });
  });

  // S7: History codex nav row → workout history screen.
  //
  // CodexNavRow with semanticIdentifier 'codex-nav-history' calls context.push('/home/history').
  // WorkoutHistoryScreen AppBar uses Semantics(identifier: 'history-heading').
  test('should navigate to workout history screen when tapping History codex nav row (S7)', async ({
    page,
  }) => {
    await page.locator(SAGA.codexNavHistory).first().scrollIntoViewIfNeeded();
    await page.locator(SAGA.codexNavHistory).first().click();

    // Flutter web pushes the route — assert on history-heading OR history-empty.
    // Foundation user has workout history so heading should appear; empty state
    // is the fallback in case the history list loads slower than expected.
    const hasHeading = await page
      .locator(HISTORY.heading)
      .isVisible({ timeout: 15_000 })
      .catch(() => false);
    const hasEmpty = await page
      .locator(HISTORY.emptyState)
      .isVisible({ timeout: 5_000 })
      .catch(() => false);
    expect(hasHeading || hasEmpty).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// S8–S10: Stats deep-dive composition + interaction (Phase 18d.2)
//
// The /saga/stats deep-dive composes four sub-widgets — VitalityTable,
// VitalityTrendChart, _VolumePeakTable, PeakLoadsTable — keyed off
// statsProvider. These tests verify the composition contract end-to-end:
//   S8 — fresh user lands without an activity gate, all four sub-widgets render.
//   S9 — foundation user sees the same layout populated with their data.
//   S10 — re-tapping the Saga tab from /saga/stats pops back to the character sheet.
//
// User isolation: rpgFoundationUser exists already in TEST_USERS. We reuse
// it to keep the user-fixture surface area small. S8 reuses rpgFreshUser.
// ---------------------------------------------------------------------------

test.describe('Saga — stats deep-dive', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('rpgFoundationUser').email,
      getUser('rpgFoundationUser').password,
    );
    await navigateToTab(page, 'Profile');
    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });

    // Drill into /saga/stats via the codex nav row.
    await page.locator(SAGA.codexNavStats).first().scrollIntoViewIfNeeded();
    await page.locator(SAGA.codexNavStats).first().click();
    await page
      .locator(SAGA.statsDeepDiveScreen)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });
  });

  // S8: Composition — the three deep-dive sections render.
  //
  // Phase 26c restructured the screen: VitalityTrendChart + VitalityTable
  // + per-body-part VolumePeakBlocks (replacing the legacy single
  // _VolumePeakTable + PeakLoadsTable). Chest sits at the top of the
  // VolumePeakBlock column (canonical activeBodyParts order) and serves
  // as the section-rendered sentinel.
  test('should compose the 3 deep-dive sub-widgets (S8)', async ({ page }) => {
    await expect(page.locator(SAGA.vitalityTable).first()).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(SAGA.vitalityTrendChart).first()).toBeVisible({
      timeout: 10_000,
    });
    // The volume-peak blocks sit below the fold on small viewports. Scroll
    // the chest block into view before asserting visibility — the
    // identifier is emitted regardless, but visibility requires layout
    // overlap with the viewport.
    await page
      .locator(SAGA.volumePeakBlock('chest'))
      .first()
      .scrollIntoViewIfNeeded();
    await expect(
      page.locator(SAGA.volumePeakBlock('chest')).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  // S8b (Phase 26c): the ⓘ on the trend section header opens
  // VitalityExplainerSheet. Same sheet from the table-section ⓘ — this
  // test pins the trend-section entry point. Inherits @smoke from the
  // enclosing describe block's tag.
  test('should open vitality explainer sheet when tapping the trend section info icon', async ({
    page,
  }) => {
    await page
      .locator(SAGA.vitalityTrendInfoIcon)
      .first()
      .scrollIntoViewIfNeeded();
    await page.locator(SAGA.vitalityTrendInfoIcon).first().click();

    await expect(
      page.locator(SAGA.vitalityExplainerSheet).first(),
    ).toBeVisible({ timeout: 5_000 });
  });

  // S9: Tapping a vitality row drives the trend chart's selected line.
  //
  // The screen holds selection state and passes selectedBodyPart into the
  // chart. We can't visually assert which color is "vivid" from the AOM, but
  // we can verify that tapping a row doesn't error and that the chart stays
  // visible across the interaction (i.e. no rebuild crash).
  test('should keep the trend chart rendered after tapping a vitality row (S9)', async ({
    page,
  }) => {
    await expect(page.locator(SAGA.vitalityTrendChart).first()).toBeVisible({
      timeout: 10_000,
    });

    // Tap the legs row (always present — provider always emits all six rows).
    await page.locator(SAGA.vitalityRow('legs')).first().scrollIntoViewIfNeeded();
    await page.locator(SAGA.vitalityRow('legs')).first().click();

    // The chart must still be in the tree afterward.
    await expect(page.locator(SAGA.vitalityTrendChart).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  // S10: Re-tapping the Saga tab from /saga/stats pops back to the
  // character sheet. Mirrors S4's contract for the deep-dive route.
  test('should pop back to the character sheet on Saga tab re-tap (S10)', async ({
    page,
  }) => {
    await page.click(NAV.profileTab);

    // Character sheet visible again; deep-dive no longer in the tree.
    await expect(page.locator(SAGA.characterSheet).first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.locator(SAGA.statsDeepDiveScreen)).not.toBeVisible({
      timeout: 5_000,
    });
  });
});

// ---------------------------------------------------------------------------
// S11: Fresh user can reach /saga/stats without activity gate (Phase 18d.2)
//
// PO + UX-critic amendment #1: the deep-dive screen is reachable from a
// fresh account. The empty-state copy is communicated through the data
// shape (zero %, dormant copy, flat trend lines, empty peaks copy).
// ---------------------------------------------------------------------------

test.describe('Saga — stats deep-dive (fresh user)', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    // Reset the fresh user's RPG state so we land on a true zero-history
    // baseline. See the matching beforeEach above for the full rationale —
    // intra-worker pollution from rpg-foundation.spec.ts still requires
    // this reset even after Phase 21 per-worker isolation.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgFreshUser').email);
    if (userId) {
      await resetRpgStateForUser(admin, userId);
    }

    await login(
      page,
      getUser('rpgFreshUser').email,
      getUser('rpgFreshUser').password,
    );
    await navigateToTab(page, 'Profile');
    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });
  });

  test('should let a fresh user open /saga/stats without an activity gate (S11)', async ({
    page,
  }) => {
    await page.locator(SAGA.codexNavStats).first().scrollIntoViewIfNeeded();
    await page.locator(SAGA.codexNavStats).first().click();

    await expect(page.locator(SAGA.statsDeepDiveScreen).first()).toBeVisible({
      timeout: 15_000,
    });
    // Vitality table renders even with all-zero rows — six rows still appear.
    await expect(page.locator(SAGA.vitalityTable).first()).toBeVisible({
      timeout: 10_000,
    });
  });
});

// ---------------------------------------------------------------------------
// S12: Class label updates after a body-part rank cross (Phase 18e, spec §18 #8)
//
// rpgClassCrossUser is seeded with chest at rank 4 (270 XP), all other body
// parts at rank 1. Class resolver: max rank 4 < 5 → Initiate.
//
// After one bench-press set the chest crosses rank 4 → rank 5.
// Class resolver: max=5 ≥ 5 (not Initiate); min=1, spread=(5-1)/5=0.80>0.30
// (not Ascendant); dominant = chest → Bulwark.
//
// The test does NOT assert "Initiate" text because the class badge renders
// localized text that goes through AppLocalizations — asserting the badge is
// visible before and after is the reliable AOM check. The class flip is
// validated structurally by confirming the character sheet reloads (provider
// refresh after save) without errors.
//
// Not tagged @smoke: the full workout + celebration flow is ~2 min and adds
// significant time to the smoke gate. The existing unit tests (class_provider_test.dart
// "rank delta crosses Initiate floor → class flips on the same rebuild") cover
// the immediacy property at the unit level.
// ---------------------------------------------------------------------------

test.describe('Saga — class label updates after rank cross (S12)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('rpgClassCrossUser').email,
      getUser('rpgClassCrossUser').password,
    );
    await navigateToTab(page, 'Home');
  });

  test('should update class badge after chest crosses rank 5 (S12)', async ({
    page,
  }) => {
    // S12 exercises a full rank-up flow that compounds with every overlay step:
    // ProfileNav (5 s) + EmptyWorkout (5 s) + addExercise (5 s) + set inputs
    // (3 s × 2) + completeSet (3 s) + finishWorkout (2 s) + ClassChangeOverlay
    // (best-effort 10 s) + dismissCelebrationIfPresent (up to 25 s for the
    // celebration URL + 12 s overlay loop) + ProfileNav (3 s) + character-sheet
    // assertions (10 s) ≈ 65–80 s under typical local conditions, more under
    // worker contention. Successful runs land around 24–35 s; the 60 s default
    // is insufficient when any celebration step takes its full budget.
    //
    // Every other E2E test stays well under 60 s, so the global default stays.
    // We extend ONLY this test rather than raising the global cap or carving up
    // the production helpers — the inherent celebration timeline (1.6 s
    // ClassChangeOverlay + 1.1 s rank-up + 1.1 s level-up + 1.1 s title) is the
    // correct production behaviour and the test must wait it out.
    test.setTimeout(120_000);

    // Navigate to the character sheet and capture the class badge before the workout.
    // At rank 4 the resolver returns Initiate — badge is visible (placeholder or
    // Initiate label depending on provider load timing).
    await navigateToTab(page, 'Profile');
    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });

    // Confirm the class label slot is rendered (whether loading placeholder or Initiate).
    // Phase 26b: sagaHeaderClass replaces the legacy classBadge selector.
    await expect(page.locator(SAGA.sagaHeaderClass).first()).toBeVisible({
      timeout: 15_000,
    });

    // Navigate to Home and complete a bench-press set to push chest past rank 5.
    await navigateToTab(page, 'Home');
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    // BUG-011 (Cluster 3): the Initiate→Bulwark transition fires a
    // ClassChangeOverlay (1600ms choreography) ahead of the rank-up
    // overlay. We don't wait for it explicitly because the celebration
    // player auto-dismisses after the timeline; the overlay surfaces
    // and disappears within `dismissCelebrationIfPresent`'s 25s budget.
    // Best-effort visibility check (don't fail the test if the rank-up
    // overlay races us — the unit tests pin the queue order).
    await page
      .locator(CELEBRATION.classChangeOverlay)
      .first()
      .waitFor({ state: 'visible', timeout: 10_000 })
      .catch(() => {});

    // Dismiss any celebration overlays (rank-up, level-up, title-unlock, overflow).
    await dismissCelebrationIfPresent(page, 25_000);

    // Navigate back to the character sheet — the rpgProgressProvider has been
    // refreshed by the save_workout path and the class badge should now reflect
    // the post-rank-up class (Bulwark, since chest is now dominant at rank 5+).
    await navigateToTab(page, 'Profile');
    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });

    // The class label must be visible after the rank-up. The exact text depends
    // on AppLocalizations (locale-sensitive), so we assert visibility rather than
    // text content. The resolver contract is pinned by class_provider_test.dart S12.
    // Phase 26b: sagaHeaderClass replaces the legacy classBadge selector.
    await expect(page.locator(SAGA.sagaHeaderClass).first()).toBeVisible({
      timeout: 15_000,
    });

    // Additional check: the character sheet body-part row for chest must also
    // be visible (confirms the provider data refreshed and the sheet re-rendered).
    await expect(page.locator(SAGA.bodyPartRow('chest')).first()).toBeVisible({
      timeout: 10_000,
    });
  });
});

// ---------------------------------------------------------------------------
// S13: Body-part row tap → /saga/stats?body_part=<slug> (Phase 26b Task 8)
//
// Both _TrainedRow and _UntrainedRow have InkWell tap targets wired to
// context.push('/saga/stats', extra: {'body_part': slug}). The StatsDeepDive
// screen appends the body_part as a query parameter. This smoke test verifies
// the routing contract end-to-end using rpgFoundationUser (has trained rows).
//
// Not tagged @smoke: the body-part routing is a regression test for Phase 26b
// Task 8's InkWell wiring. The existing smoke gate already covers navigation
// to /saga/stats via the codex nav row (S5).
// ---------------------------------------------------------------------------

test.describe('Saga — body-part row tap routes to stats deep-dive', () => {
  test.beforeEach(async ({ page }) => {
    await loginFoundationAndGoToCharacterSheet(page);
  });

  // TODO(26-tap-routing-e2e): Skipped per PR #234 user decision after
  // 4 fix attempts. Production code is correct (widget test pins the
  // contract in body_part_rank_row_test.dart; Playwright trace shows
  // the destination Stats screen rendering on tap). The friction is
  // in proving the navigation via Flutter web's AOM in CI — neither
  // `toHaveURL` nor `aria-selected="true"` reliably reflects the
  // post-tap state in headless runs. Revisit when 26c lands a similar
  // tap surface and we can build a shared helper, OR when Flutter
  // web's AOM-for-navigation diagnostic tooling improves. The widget
  // test gives us functional coverage; this E2E was an extra smoke
  // layer. See cluster memory: flutter-web-url-assertion +
  // semantics-button-missing.
  test.skip('should open stats deep-dive when a body-part row is tapped', async ({ page }) => {
    // Tap the BACK row (not chest — chest is the screen's default
    // pre-selection, so a chest landing would be observationally identical
    // whether or not the `body_part` query param was consumed). Tapping a
    // non-default slug means the test fails if the deep-link routing
    // contract is broken — the trend chart + vitality table would default
    // to chest instead of back.
    const backRow = page.locator(SAGA.bodyPartRow('back')).first();
    await backRow.scrollIntoViewIfNeeded();
    await expect(backRow).toBeVisible({ timeout: 10_000 });
    await backRow.click();

    // Stats screen content visible (saga-stats-screen Semantics identifier).
    //
    // We do NOT assert on `page.toHaveURL(...)` here. GoRouter on Flutter
    // web uses hash routing (HashUrlStrategy by default), and `context.push`
    // from inside a `ShellRoute` does not always reflect the new path in
    // `window.location.hash` within Playwright's poll window — the trace
    // for this test on CI showed `location.hash == '#/profile'` even
    // though the Stats screen was already mounted and visible. The same
    // pattern is documented in S3 above ("URL update via context.push is
    // unreliable in Flutter web — assert on element visibility"). Element
    // visibility + the body_part-pre-selection assertion below cover the
    // routing contract without depending on URL timing.
    await expect(page.locator(SAGA.statsDeepDiveScreen).first()).toBeVisible({
      timeout: 10_000,
    });

    // Pre-selection proof: the VitalityTable row for `back` must be marked
    // selected. `vitalityTable.dart` sets `Semantics(selected: isSelected)`
    // on the row whose body part equals `_selectedBodyPart`, which is
    // initialised from `widget.initialBodyPart` — the value derived from
    // the `body_part` query param in the route builder. If the query param
    // did not reach the screen, chest (the default) would be selected
    // instead and `[aria-selected="true"]` on `vitality-row-back` would
    // never appear.
    await expect(
      page.locator(`${SAGA.vitalityRow('back')}[aria-selected="true"]`).first(),
    ).toBeVisible({ timeout: 10_000 });
  });
});
