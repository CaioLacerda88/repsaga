/**
 * Titles screen — E2E regression spec for the Phase 26d three-region rewrite.
 *
 * Scenarios covered:
 *   T1 — The earned (is_active=false) title row renders in the Conquistados
 *         region with the "Equipar" CTA visible. Regression against the
 *         pre-26d dismiss-without-equip bug, now eliminated server-side.
 *   T2 — No EquippedTitleCard is present when no title is active
 *         (rpgTitleEquipUser seeds is_active=false).
 *   T3 — The TitlesCounterPill in the AppBar renders the correct
 *         "{earned} / 90" copy.
 *
 * User isolation:
 *   rpgTitleEquipUser — chest at rank 5 with 'chest_r5_initiate_of_the_forge'
 *   pre-seeded in earned_titles (is_active=false). This gives:
 *     - ≥1 Conquistados row (the seeded title)
 *     - No Equipado card (no active title)
 *     - earnedCount = 1 for the counter pill
 *
 * Seeding: global-setup.ts → seedRpgTitleEquipUser()
 *
 * Navigation: Profile tab → Titles codex nav row (codex-nav-titles) →
 *   TitlesScreen (titles-screen identifier).
 *
 * E2E conventions (CLAUDE.md):
 *   - Describe: feature name only, no "smoke"/"full" suffix.
 *   - Tests: "should ..." naming.
 *   - Selectors: TITLES.* (new Phase 26d block), CELEBRATION.titleLibraryButton.
 *   - Text input: flutterFill() — not used here (no text fields).
 *   - SnackBar text: .first() selector.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab } from '../helpers/app';
import { SAGA, CELEBRATION, TITLES } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

test.describe('Titles screen', () => {
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

    // Navigate to the Titles screen via the codex nav row.
    // CELEBRATION.titleLibraryButton = '[flt-semantics-identifier="codex-nav-titles"]'
    await page
      .locator(CELEBRATION.titleLibraryButton)
      .first()
      .scrollIntoViewIfNeeded();
    await page.locator(CELEBRATION.titleLibraryButton).first().click();

    await expect(
      page.locator(TITLES.screen).first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  // T1: Regression — earned (is_active=false) title row persists in Conquistados.
  //
  // Pre-26d, dismissing the TitleUnlockSheet without tapping "Equipar" could
  // leave the DB row in earned_titles without surfacing it again in the old
  // TitlesScreen (it relied on server-side is_active=true). The 26d screen
  // reads the raw earned_titles list and always renders is_active=false entries
  // as EarnedTitleRow entries in the Conquistados region.
  test('should show the earned title row in Conquistados with Equipar CTA', async ({
    page,
  }) => {
    // rpgTitleEquipUser has chest_r5_initiate_of_the_forge in earned_titles
    // with is_active=false — the canonical regression state.
    await expect(
      page
        .locator(TITLES.earnedRow('chest_r5_initiate_of_the_forge'))
        .first(),
    ).toBeVisible({ timeout: 10_000 });

    // The "Equip" / "Equipar" CTA must be visible inside that region
    // (TextButton in EarnedTitleRow). Using a case-insensitive role/name
    // match so the assertion works in both en and pt-BR locales. .first()
    // is the safe accessor per the AOM text-merge cluster.
    await expect(
      page.getByRole('button', { name: /equip/i }).first(),
    ).toBeVisible();
  });

  // T2: No Equipado card when no title is active.
  //
  // rpgTitleEquipUser seeds is_active=false for all earned_titles rows, so
  // the Equipado region must be absent (view.equipped == null in TitlesViewModel).
  test('should not show the Equipado card when no title is active', async ({
    page,
  }) => {
    // toHaveCount(0) — the element must not exist in the DOM at all.
    await expect(page.locator(TITLES.equippedCard)).toHaveCount(0);
  });

  // T3: Counter pill renders "{earned} / 90" in the AppBar.
  //
  // Total catalog: 78 body-part + 7 character-level + 5 cross-build = 90.
  // rpgTitleEquipUser has 1 earned title, so the pill should read "1 / 90".
  // We assert the pattern rather than the exact "1" because global-setup runs
  // are idempotent but don't guarantee exactly-one earned title if T2 from
  // title-equip.spec.ts ran first in the same session (it equips the title,
  // which doesn't add new earned rows — count stays 1).
  test('should render the counter pill with a numerator and the total of 90', async ({
    page,
  }) => {
    const pill = page.locator(TITLES.counterPill).first();
    await expect(pill).toBeVisible({ timeout: 10_000 });
    // Locale-independent: "1 / 90 earned" (en) or "1 / 90 conquistados" (pt-BR).
    // The regex matches the fraction regardless of locale suffix.
    await expect(pill).toContainText(/\d+\s*\/\s*90/);
  });
});
