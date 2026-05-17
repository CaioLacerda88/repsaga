/**
 * Title equip — E2E tests for the title library equip flow (Phase 18e).
 *
 * Scenarios covered:
 *   T1 — Titles codex nav row opens the title library screen.
 *   T2 — An earned unequipped title row is tappable; tapping it equips the
 *         title (EQUIPPED badge appears, active-title-pill on character sheet
 *         updates on next visit).
 *
 * User isolation:
 *   rpgTitleEquipUser — chest at rank 5; 'chest_r5_initiate_of_the_forge'
 *   pre-seeded in earned_titles (is_active = false). The title is NOT yet
 *   equipped so the test can drive the equip interaction from a clean state.
 *
 * Seeding: global-setup.ts → seedRpgTitleEquipUser()
 *
 * E2E conventions (CLAUDE.md):
 *   - Describe: feature name only ("Title equip"), no "smoke"/"full" suffix.
 *   - Tests: "should ..." naming.
 *   - Selectors: CELEBRATION.titleLibraryButton, CELEBRATION.titleLibrarySheet,
 *     TITLES.earnedRow(slug) (replaces pre-26d CELEBRATION.titleRow — identifier
 *     changed from 'title-row-{slug}' to 'titles-earned-row-{slug}' in Phase 26d),
 *     TITLES.equippedCard (replaces CELEBRATION.equippedTitleLabel — identifier
 *     changed from 'equipped-title-label' to 'titles-equipped-card' in Phase 26d),
 *     SAGA.sagaHeaderTitle.
 *   - Text input: flutterFill() — not used here (no text fields).
 *   - SnackBar text: .first() selector.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab } from '../helpers/app';
import { SAGA, CELEBRATION, TITLES } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

test.describe('Title equip', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('rpgTitleEquipUser').email,
      getUser('rpgTitleEquipUser').password,
    );
    await navigateToTab(page, 'Profile');
    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });
  });

  // T1: Titles codex nav row opens the title library screen.
  //
  // SAGA.codexNavTitles (= CELEBRATION.titleLibraryButton) calls
  // context.push('/profile/titles') → TitlesScreen (CELEBRATION.titleLibrarySheet).
  // Phase 18e extended TitlesScreen with CHARACTER LEVEL and DISTINCTION sections;
  // the 'titles-screen' Semantics identifier is unchanged.
  test('should open title library screen when tapping Titles codex nav row (T1)', async ({
    page,
  }) => {
    await page
      .locator(CELEBRATION.titleLibraryButton)
      .first()
      .scrollIntoViewIfNeeded();
    await page.locator(CELEBRATION.titleLibraryButton).first().click();

    await expect(
      page.locator(CELEBRATION.titleLibrarySheet).first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  // T2: Tapping an earned unequipped title row equips the title.
  //
  // rpgTitleEquipUser has 'chest_r5_initiate_of_the_forge' in earned_titles
  // with is_active = false. The 26d TitlesScreen renders this in the
  // Conquistados region as an EarnedTitleRow with an "Equipar" CTA.
  // After the equip round-trip completes, the EquippedTitleCard
  // (titles-equipped-card identifier) appears in the Equipado region.
  //
  // The active-title-pill on the character sheet is checked on a second
  // navigation so the earnedTitlesProvider + equippedTitleSlugProvider
  // invalidation has time to propagate before we assert.
  test('should equip an earned title and show EquippedTitleCard in Equipado region (T2)', async ({
    page,
  }) => {
    // Open the title library.
    await page
      .locator(CELEBRATION.titleLibraryButton)
      .first()
      .scrollIntoViewIfNeeded();
    await page.locator(CELEBRATION.titleLibraryButton).first().click();

    await page
      .locator(CELEBRATION.titleLibrarySheet)
      .first()
      .waitFor({ state: 'visible', timeout: 15_000 });

    // The earned title row must be visible in the Conquistados region.
    // Phase 26d: identifier changed from 'title-row-{slug}' to
    // 'titles-earned-row-{slug}' in EarnedTitleRow.
    const titleRow = page
      .locator(TITLES.earnedRow('chest_r5_initiate_of_the_forge'))
      .first();
    await titleRow.scrollIntoViewIfNeeded();
    await expect(titleRow).toBeVisible({ timeout: 10_000 });

    // Tap the Equip / Equipar CTA to equip. Role-match is locale-independent.
    // The EarnedTitleRow.onEquip callback fires _equip → equipTitle RPC
    // → earnedTitlesProvider + equippedTitleSlugProvider invalidation.
    await page.getByRole('button', { name: /equip/i }).first().click();

    // The EquippedTitleCard must appear in the Equipado region after the
    // round-trip completes. Phase 26d: identifier changed from
    // 'equipped-title-label' to 'titles-equipped-card' in EquippedTitleCard.
    // equip_title is a Postgres UPSERT (fast path) — the round-trip typically
    // completes in < 2 s on the local Supabase instance.
    await expect(
      page.locator(TITLES.equippedCard).first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  // T3: After equipping a title, the character sheet shows the active-title-pill.
  //
  // This test runs after T2 in the same describe block and relies on the
  // rpgTitleEquipUser's equip state persisting across the navigation. Because
  // each test has its own beforeEach (login + navigate to Profile), we equip
  // the title again in T3 to avoid cross-test state coupling.
  test('should show active-title-pill on character sheet after equipping a title (T3)', async ({
    page,
  }) => {
    // Open the title library and equip the title.
    await page
      .locator(CELEBRATION.titleLibraryButton)
      .first()
      .scrollIntoViewIfNeeded();
    await page.locator(CELEBRATION.titleLibraryButton).first().click();

    await page
      .locator(CELEBRATION.titleLibrarySheet)
      .first()
      .waitFor({ state: 'visible', timeout: 15_000 });

    // Phase 26d: identifier changed from 'title-row-{slug}' to
    // 'titles-earned-row-{slug}' in EarnedTitleRow.
    const titleRow = page
      .locator(TITLES.earnedRow('chest_r5_initiate_of_the_forge'))
      .first();

    // Equip the title (idempotently across runs). T3's prerequisite is
    // "a title is equipped" — either we equip it now, or it's already equipped
    // from T2's run in the same Playwright invocation (Postgres earned_titles
    // state persists between tests in the same describe block; global-setup
    // only re-seeds at invocation start, not between tests).
    //
    // Phase 26d: The EquippedTitleCard (identifier 'titles-equipped-card')
    // replaces the old EQUIPPED badge (identifier 'equipped-title-label').
    //
    // Wait for the data region to be ready before probing: either the
    // EarnedTitleRow (unequipped state) OR the EquippedTitleCard (already
    // equipped from T2 running first in the same worker session) must appear.
    // We wait for either signal with a generous timeout so the AOM has time
    // to settle after data fetch.
    const equippedCard = page.locator(TITLES.equippedCard).first();
    const earnedRowLocator = titleRow;

    // Poll until one of the two expected elements is visible.
    await page.waitForSelector(
      `${TITLES.equippedCard}, ${TITLES.earnedRow('chest_r5_initiate_of_the_forge')}`,
      { timeout: 15_000 },
    );

    const alreadyEquipped = await equippedCard.isVisible().catch(() => false);
    if (!alreadyEquipped) {
      await earnedRowLocator.scrollIntoViewIfNeeded();
      await expect(earnedRowLocator).toBeVisible({ timeout: 5_000 });
      // Role-match is locale-independent (en: "Equip", pt-BR: "Equipar").
      await page.getByRole('button', { name: /equip/i }).first().click();
    }
    await expect(equippedCard).toBeVisible({ timeout: 15_000 });

    // Navigate back to the character sheet. The active-title-pill should render
    // because equippedTitleSlugProvider was invalidated after the equip RPC.
    // go_router.pop() or re-tapping the Profile tab returns to /profile.
    await page.goBack();

    await page
      .locator(SAGA.characterSheet)
      .first()
      .waitFor({ state: 'visible', timeout: 20_000 });

    // The saga-header-title renders when activeTitle != null && isNotEmpty.
    // equippedTitleSlugProvider watch fires on the character sheet rebuild.
    // Phase 26b: sagaHeaderTitle replaces the legacy activeTitlePill selector.
    await expect(page.locator(SAGA.sagaHeaderTitle).first()).toBeVisible({
      timeout: 15_000,
    });
  });
});
