/**
 * Profile weekly goal spec — merged from smoke suite.
 *
 * Tests changing the training frequency (weekly goal) from the Profile screen:
 *   - Login -> navigate to Profile tab.
 *   - Find the "Weekly Goal" row showing "{n}x per week".
 *   - Tap it to open the frequency bottom sheet.
 *   - Select a different frequency chip.
 *   - Verify the row now shows the new frequency.
 *   - Restore the original frequency so the test is idempotent.
 *
 * Uses the dedicated `smokeProfileWeeklyGoal` user for state isolation.
 *
 * Label source: ProfileScreen._WeeklyGoalRow renders the row text as
 * "${frequency}x per week" and the bottom sheet title as "Weekly Goal".
 * The ChoiceChips in the sheet are labeled "${freq}x" (e.g. "3x", "4x").
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab } from '../helpers/app';
import { PROFILE, PROFILE_WEEKLY_GOAL, SAGA } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

// ---------------------------------------------------------------------------
// Smoke — profile weekly goal
// ---------------------------------------------------------------------------
test.describe('Profile — weekly goal', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(page, getUser('smokeProfileWeeklyGoal').email, getUser('smokeProfileWeeklyGoal').password);
    // Phase 18b: /profile now shows CharacterSheetScreen. The weekly goal row is
    // on /profile/settings (ProfileSettingsScreen). Navigate via the gear icon.
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });
  });

  // ---------------------------------------------------------------------------
  // Test 1: Profile screen shows the Weekly Goal section.
  //
  // ProfileScreen renders a "Weekly Goal" titleMedium Text above the
  // _WeeklyGoalRow widget. The row shows "${frequency}x per week".
  // ---------------------------------------------------------------------------
  test('should show Weekly Goal section with frequency text on Profile screen', async ({
    page,
  }) => {
    await expect(page.locator(PROFILE.heading).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sectionLabel)).toBeVisible({
      timeout: 10_000,
    });
    // The row text matches "${n}x per week" where n is 2-6.
    await expect(page.locator(PROFILE_WEEKLY_GOAL.frequencyRow)).toBeVisible({
      timeout: 10_000,
    });
  });

  // ---------------------------------------------------------------------------
  // Test 2: Tapping the Weekly Goal row opens the frequency bottom sheet.
  //
  // _WeeklyGoalRow is an InkWell that calls _showFrequencySheet on tap.
  // The sheet has title "Weekly Goal" and ChoiceChips: 2x, 3x, 4x, 5x, 6x.
  // ---------------------------------------------------------------------------
  test('should open frequency selection sheet when tapping Weekly Goal row', async ({
    page,
  }) => {
    await expect(page.locator(PROFILE_WEEKLY_GOAL.frequencyRow)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(PROFILE_WEEKLY_GOAL.frequencyRow).click();

    // Bottom sheet title.
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).toBeVisible({
      timeout: 10_000,
    });

    // All frequency options must be present (rendered as ChoiceChips).
    for (const chip of ['2x', '3x', '4x', '5x', '6x']) {
      await expect(page.locator(`role=checkbox[name="${chip}"]`)).toBeVisible({
        timeout: 5_000,
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Test 3: Selecting a different frequency updates the displayed value.
  //
  // If the current frequency is 3x, we change it to 4x and verify the row
  // text updates to "4x per week". Then we restore it to 3x.
  // ---------------------------------------------------------------------------
  test('should update weekly goal row text when selecting a frequency chip', async ({
    page,
  }) => {
    await expect(page.locator(PROFILE_WEEKLY_GOAL.frequencyRow)).toBeVisible({
      timeout: 10_000,
    });

    // Read the current frequency from the row text.
    const rowText = await page
      .locator(PROFILE_WEEKLY_GOAL.frequencyRow)
      .textContent({ timeout: 5_000 });
    const currentFreq = rowText?.match(/(\d+)x per week/)?.[1] ?? '3';
    const currentFreqNum = parseInt(currentFreq, 10);

    // Pick a different frequency to switch to.
    // Cycle: if current is 3, use 4; if current is 6, use 5; otherwise +1.
    const newFreqNum = currentFreqNum < 6 ? currentFreqNum + 1 : currentFreqNum - 1;
    const newFreqChip = `${newFreqNum}x`;
    const originalFreqChip = `${currentFreqNum}x`;

    // Open the sheet.
    await page.locator(PROFILE_WEEKLY_GOAL.frequencyRow).click();
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Select the new frequency chip (rendered as ChoiceChip -> checkbox role).
    // Use CSS selector to target the flt-semantics element directly, ensuring
    // Playwright sends a pointer click (not a checkbox toggle action).
    await page.locator(`role=checkbox[name="${newFreqChip}"]`).click();

    // The sheet should close automatically after selection (Navigator.of(ctx).pop()).
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).not.toBeVisible({
      timeout: 10_000,
    });

    // Wait for the async profile update to propagate to the UI.
    await page.waitForTimeout(500);

    // The row should now show the new frequency.
    await expect(
      page.locator(PROFILE_WEEKLY_GOAL.frequencyRowWithValue(newFreqNum)),
    ).toBeVisible({ timeout: 10_000 });

    // Restore to original frequency (cleanup for test isolation).
    await page.locator(PROFILE_WEEKLY_GOAL.frequencyRow).click();
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(`role=checkbox[name="${originalFreqChip}"]`).click();
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).not.toBeVisible({
      timeout: 10_000,
    });

    // Verify the original value is restored.
    await expect(
      page.locator(PROFILE_WEEKLY_GOAL.frequencyRowWithValue(currentFreqNum)),
    ).toBeVisible({ timeout: 10_000 });
  });

  // ---------------------------------------------------------------------------
  // Test 4: Selecting the already-active frequency still closes the sheet.
  //
  // Tapping the currently selected chip also calls onSelected, which calls
  // updateTrainingFrequency and pops the sheet. The displayed value should not
  // change but the sheet must close.
  // ---------------------------------------------------------------------------
  test('should close sheet without error when selecting the current frequency', async ({
    page,
  }) => {
    await expect(page.locator(PROFILE_WEEKLY_GOAL.frequencyRow)).toBeVisible({
      timeout: 10_000,
    });

    // Read current frequency.
    const rowText = await page
      .locator(PROFILE_WEEKLY_GOAL.frequencyRow)
      .textContent({ timeout: 5_000 });
    const currentFreq = rowText?.match(/(\d+)x per week/)?.[1] ?? '3';
    const currentFreqNum = parseInt(currentFreq, 10);
    const currentChipText = `${currentFreqNum}x`;

    // Open sheet.
    await page.locator(PROFILE_WEEKLY_GOAL.frequencyRow).click();
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Tap the currently selected chip (rendered as ChoiceChip -> checkbox role).
    // Use CSS selector for consistent pointer click behavior.
    await page.locator(`role=checkbox[name="${currentChipText}"]`).click();

    // Sheet must close.
    await expect(page.locator(PROFILE_WEEKLY_GOAL.sheetTitle)).not.toBeVisible({
      timeout: 5_000,
    });

    // Value is unchanged.
    await expect(
      page.locator(PROFILE_WEEKLY_GOAL.frequencyRowWithValue(currentFreqNum)),
    ).toBeVisible({ timeout: 5_000 });
  });
});
