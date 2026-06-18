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
 *         "{earned} / 106" copy.
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
import {
  getAdminClient,
  getUserIdByEmail,
} from '../helpers/test-data-reset';

test.describe('Titles screen', () => {
  test.beforeEach(async ({ page }) => {
    // Cross-spec pollution defense: `title-equip.spec.ts` T2 EQUIPS the
    // seeded chest_r5 title (UPDATE earned_titles SET is_active=true). When
    // that spec runs before us in the same worker, the row drifts out of
    // the Conquistados region into Equipado, breaking our regression test.
    // Reset is_active=false for every row owned by this user before each
    // test so we always start from the canonical pre-equip state.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(
      admin,
      getUser('rpgTitleEquipUser').email,
    );
    if (userId) {
      await admin
        .from('earned_titles')
        .update({ is_active: false })
        .eq('user_id', userId)
        .eq('is_active', true);
    }

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

  // T3: Counter pill renders "{earned} / 106" in the AppBar.
  //
  // Total catalog (Phase 38f): 91 body-part (incl. the cardio track) +
  // 8 character-level (incl. saga_unending@172) + 7 cross-build (incl. the
  // cardio triangle) = 106. rpgTitleEquipUser has 1 earned title (seeded by
  // global-setup), so the pill reads "1 / 106". We assert the regex rather
  // than the exact "1" numerator so the test stays locale-independent and
  // tolerates any future seeding tweak that adds rows for this user.
  test('should render the counter pill with a numerator and the total of 106', async ({
    page,
  }) => {
    const pill = page.locator(TITLES.counterPill).first();
    await expect(pill).toBeVisible({ timeout: 10_000 });
    // Locale-independent: "1 / 106 earned" (en) or "1 / 106 conquistados"
    // (pt-BR). The regex matches the fraction regardless of locale suffix.
    await expect(pill).toContainText(/\d+\s*\/\s*106/);
  });
});
