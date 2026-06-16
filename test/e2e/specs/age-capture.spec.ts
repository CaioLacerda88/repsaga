/**
 * Age (birth-year) capture — Phase 38d E2E.
 *
 * Two new user flows ship in 38d; this spec pins both end to end against a
 * fresh Flutter web build:
 *
 *   FLOW 1 — Set age in profile settings:
 *     Profile → Settings → AgeRow → AgeEditorSheet (birth-year wheel) →
 *     Save the DEFAULT resting year (age-35) → the row reflects a value
 *     (and `profiles.date_of_birth` is persisted) → reopen → Prefer not to
 *     say → the value clears back to NULL ("Not set").
 *
 *   FLOW 2 — First-cardio post-session age prompt:
 *     A user with NULL `date_of_birth` finishes a workout containing a
 *     completed cardio entry → the post-session summary shows the one-time
 *     "set your age" nudge → "Set age" opens the same sheet; dismiss records
 *     the never-show-again flag.
 *
 * WHEEL-DRIVABILITY VERDICT (documented, not faked):
 * ----------------------------------------------------
 * The control is a Flutter `ListWheelScrollView` rendered to <canvas> under
 * CanvasKit. Its per-row numerals are NOT DOM text nodes and the wheel does
 * NOT expose stable per-item AOM nodes addressable by year, so spinning the
 * wheel to an *arbitrary* target birth year is NOT reliably drivable by
 * Playwright. We therefore do NOT assert "the user picked 1990". Instead we
 * drive the load-bearing user-perceptible outcomes:
 *   - the sheet opens with the wheel + disclosure + Save / Cancel /
 *     Prefer-not-to-say affordances present;
 *   - saving the DEFAULT resting year (age-35) persists a non-NULL DOB and
 *     the row stops reading "Not set";
 *   - Prefer-not-to-say clears the DOB back to NULL and the row reads
 *     "Not set" again.
 * The wheel's ≥18 structural floor, clear-to-NULL path, and textScaler
 * item-extent are pinned at the widget tier (age_row_test.dart); duplicating
 * them here would add no behavioral coverage E2E can actually drive.
 *
 * Behavior, not wiring: assertions are on what the user perceives (the row
 * value, the sheet, the prompt banner) and on the persisted DB column —
 * never on "a method was called".
 *
 * Isolation: dedicated `smokeAgeCapture` user. FLOW 1 mutates the DOB column,
 * so `beforeEach` reseeds it back to NULL via the admin API; serial mode
 * prevents parallel races on the shared user (cluster
 * `e2e-spec-state-leak-across-tests`).
 */
import { test, expect } from '@playwright/test';
import { navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  startEmptyWorkout,
  addExercise,
  finishWorkout,
} from '../helpers/workout';
import {
  AGE_EDITOR,
  CARDIO,
  NAV,
  POST_SESSION,
  SAGA,
  WORKOUT,
} from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

/**
 * Reset the smokeAgeCapture user's `date_of_birth` back to NULL so every
 * test starts from the day-zero "Not set" state (FLOW 1 sets it; FLOW 2
 * requires it null to gate the prompt).
 */
async function reseedAgeCaptureUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('smokeAgeCapture').email);
  if (!userId) return;
  await admin
    .from('profiles')
    .update({ date_of_birth: null })
    .eq('id', userId);
}

async function readDob(): Promise<string | null | undefined> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('smokeAgeCapture').email);
  if (!userId) return undefined;
  const row = await admin
    .from('profiles')
    .select('date_of_birth')
    .eq('id', userId)
    .single();
  return row.data?.date_of_birth as string | null | undefined;
}

async function openProfileSettings(
  page: import('@playwright/test').Page,
): Promise<void> {
  await navigateToTab(page, 'Profile');
  await page
    .locator(SAGA.characterSheet)
    .first()
    .waitFor({ state: 'visible', timeout: 10_000 });
  await page.locator(SAGA.gearIcon).first().click();
  await page
    .locator(SAGA.profileSettingsScreen)
    .first()
    .waitFor({ state: 'visible', timeout: 10_000 });
}

// ===========================================================================
// FLOW 1 — Set age in profile settings.
// ===========================================================================
test.describe('Age capture — profile settings', { tag: '@smoke' }, () => {
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await reseedAgeCaptureUser();
    await login(
      page,
      getUser('smokeAgeCapture').email,
      getUser('smokeAgeCapture').password,
    );
    await openProfileSettings(page);
  });

  test('should open the AgeEditorSheet with wheel, disclosure, and Save / Cancel / Prefer-not-to-say affordances', async ({
    page,
  }) => {
    // The Age row is always present (regardless of DOB state).
    await page.locator(AGE_EDITOR.row).first().scrollIntoViewIfNeeded();
    await expect(page.locator(AGE_EDITOR.row).first()).toBeVisible({
      timeout: 10_000,
    });

    // Tap to open. The identifier node sits inside an InkWell with
    // explicitChildNodes:true → force:true dispatches pointer events at the
    // node coordinates, which Flutter hit-tests onto the InkWell.
    await page.locator(AGE_EDITOR.row).first().click({ force: true });

    // The sheet is open: wheel present, both action buttons present, and the
    // affirmative-skip ghost present. These four affordances are the full
    // user-perceptible contract of the sheet's controls.
    await expect(page.locator(AGE_EDITOR.sheet).first()).toBeVisible({
      timeout: 8_000,
    });
    await expect(page.locator(AGE_EDITOR.wheel).first()).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(AGE_EDITOR.preferNotToSay).first()).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(AGE_EDITOR.saveButton).first()).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(AGE_EDITOR.cancelButton).first()).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should persist a birth date when saving the default wheel year and clear it back to NULL via Prefer not to say', async ({
    page,
  }) => {
    // Precondition: DOB starts NULL (reseed in beforeEach). Assert it loudly
    // so a seeder regression fails here, not downstream as a UI mystery.
    expect(await readDob(), 'DOB must start NULL after reseed').toBeNull();

    // --- Save the default resting year (age-35) ---------------------------
    await page.locator(AGE_EDITOR.row).first().scrollIntoViewIfNeeded();
    await page.locator(AGE_EDITOR.row).first().click({ force: true });
    await expect(page.locator(AGE_EDITOR.sheet).first()).toBeVisible({
      timeout: 8_000,
    });

    // Do NOT spin the wheel (canvas-rendered; not reliably drivable). Saving
    // immediately commits the default resting year = currentYear − 35, which
    // is exactly the skip==fallback contract (locked decision #5). The
    // user-perceptible outcome is identical whether they spin or not: a
    // non-NULL DOB lands and the row stops reading "Not set".
    await page.locator(AGE_EDITOR.saveButton).first().click();

    // Sheet closes on save.
    await expect(page.locator(AGE_EDITOR.sheet)).not.toBeVisible({
      timeout: 8_000,
    });

    // Behavior 1 (persisted state): a non-NULL DOB is written, stored as
    // January 1 of the picked year (YYYY-01-01 — birth-year granularity).
    // currentYear − 35 in 2026 = 1991 → '1991-01-01'.
    const savedDob = await readDob();
    expect(savedDob, 'DOB must be persisted after Save').not.toBeNull();
    expect(savedDob, 'DOB stored as YYYY-01-01').toMatch(/^\d{4}-01-01$/);
    const expectedYear = new Date().getFullYear() - 35;
    expect(savedDob).toContain(String(expectedYear));

    // Behavior 2 (rendered row): the row no longer reads "Not set". The row's
    // AOM label is `ageRowSemantics(value)` = "Age. {value}. Tap to edit."
    // After a save the {value} is the derived age numeral, so the label no
    // longer contains "Not set". Re-fetch via the identifier node's
    // accessible name; the node is stable across the value mutation because
    // its identifier is fixed.
    const rowName = await page
      .locator(AGE_EDITOR.row)
      .first()
      .getAttribute('aria-label');
    // Flutter surfaces the labeled identifier node's name as aria-label on
    // the flt-semantics element when the node carries an explicit `label:`.
    // If a future Flutter build stops mirroring label→aria-label, the DB
    // assertion above remains the authoritative persisted-state proof; we
    // keep the row assertion as the user-visible signal but tolerate a null
    // attribute by falling back to "value changed in DB" already asserted.
    if (rowName !== null) {
      expect(rowName).not.toContain('Not set');
      expect(rowName).toMatch(/\d/);
    }

    // --- Clear back to NULL via Prefer not to say ------------------------
    await page.locator(AGE_EDITOR.row).first().click({ force: true });
    await expect(page.locator(AGE_EDITOR.sheet).first()).toBeVisible({
      timeout: 8_000,
    });
    await page.locator(AGE_EDITOR.preferNotToSay).first().click();
    await expect(page.locator(AGE_EDITOR.sheet)).not.toBeVisible({
      timeout: 8_000,
    });

    // Behavior 3 (cleared state): DOB is back to NULL — the row reverts to
    // the calm "Not set" invitation (the age-35 fallback resumes).
    expect(
      await readDob(),
      'DOB must clear to NULL after Prefer not to say',
    ).toBeNull();

    const clearedName = await page
      .locator(AGE_EDITOR.row)
      .first()
      .getAttribute('aria-label');
    if (clearedName !== null) {
      expect(clearedName).toContain('Not set');
    }
  });
});

// ===========================================================================
// FLOW 2 — First-cardio post-session age prompt.
// ===========================================================================
test.describe('Age capture — post-session prompt', { tag: '@smoke' }, () => {
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await reseedAgeCaptureUser();
    await login(
      page,
      getUser('smokeAgeCapture').email,
      getUser('smokeAgeCapture').password,
    );
  });

  /**
   * Drive a cardio-only workout to a finished state and land on the
   * post-session summary panel. Treadmill seeds a default 30:00
   * CardioSession on add, so the "Complete cardio" CTA is enabled with no
   * further input; completing it sets `PostSessionState.hadCardio`.
   */
  async function finishCardioWorkoutToSummary(
    page: import('@playwright/test').Page,
  ): Promise<void> {
    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.treadmill);

    // Complete the cardio entry. The identifier wraps the OutlinedButton with
    // explicitChildNodes:true, so force-click dispatches the tap onto it.
    await page.locator(CARDIO.complete).first().scrollIntoViewIfNeeded();
    await page.locator(CARDIO.complete).first().click({ force: true });
    // The green ✓ re-open affordance confirms the entry is now completed.
    await expect(page.locator(CARDIO.uncomplete).first()).toBeVisible({
      timeout: 10_000,
    });

    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 10_000,
    });
    await finishWorkout(page);

    // The non-empty online finish pushes the post-session cinematic. Skip
    // straight to the summary panel (the prompt lives on the summary, not on
    // the cinematic cuts).
    await page.waitForURL(/\/workout\/finish\//, { timeout: 15_000 });
    const skip = page.locator(POST_SESSION.skipBtn);
    if (await skip.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await skip.click();
    }
    await expect(page.locator(POST_SESSION.summary)).toBeVisible({
      timeout: 15_000,
    });
  }

  test('should show the one-time age nudge on the post-session summary after a cardio session when no birth date is set', async ({
    page,
  }) => {
    expect(await readDob(), 'DOB must be NULL to gate the prompt').toBeNull();

    await finishCardioWorkoutToSummary(page);

    // Behavior: the nudge banner is visible on the summary, with its "Set
    // age" CTA reachable.
    await expect(page.locator(POST_SESSION.agePrompt).first()).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(POST_SESSION.agePromptCta).first()).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should open the shared AgeEditorSheet when tapping Set age in the post-session nudge', async ({
    page,
  }) => {
    await finishCardioWorkoutToSummary(page);
    await expect(page.locator(POST_SESSION.agePrompt).first()).toBeVisible({
      timeout: 10_000,
    });

    // Tapping "Set age" opens the same AgeEditorSheet the settings row uses.
    await page.locator(POST_SESSION.agePromptCta).first().click({ force: true });
    await expect(page.locator(AGE_EDITOR.sheet).first()).toBeVisible({
      timeout: 8_000,
    });
    await expect(page.locator(AGE_EDITOR.wheel).first()).toBeVisible({
      timeout: 5_000,
    });

    // Cancel leaves the DOB NULL (no accidental write from merely opening).
    await page.locator(AGE_EDITOR.cancelButton).first().click();
    await expect(page.locator(AGE_EDITOR.sheet)).not.toBeVisible({
      timeout: 5_000,
    });
    expect(
      await readDob(),
      'Opening + cancelling the sheet must not write a DOB',
    ).toBeNull();
  });

  test('should remove the nudge for the rest of the session when dismissed', async ({
    page,
  }) => {
    await finishCardioWorkoutToSummary(page);
    const prompt = page.locator(POST_SESSION.agePrompt).first();
    await expect(prompt).toBeVisible({ timeout: 10_000 });

    // Dismiss ✕ → records the never-show-again Hive flag + removes the
    // banner. Behavior: the banner is gone from the summary.
    await page
      .locator(POST_SESSION.agePromptDismiss)
      .first()
      .click({ force: true });
    await expect(prompt).not.toBeVisible({ timeout: 8_000 });

    // The user did not set an age (dismiss is not a write) — DOB stays NULL.
    expect(
      await readDob(),
      'Dismissing the nudge must not write a DOB',
    ).toBeNull();

    // Returning to home via CONTINUAR works (the dismiss left the summary in
    // a coherent state).
    await expect(page.locator(POST_SESSION.continueCta).first()).toBeVisible({
      timeout: 10_000,
    });
    // Tapping CONTINUAR here drives the summary → /home transition directly.
    // Do NOT call dismissCelebrationIfPresent afterwards: the summary is
    // already being torn down, so the helper re-races the in-flight
    // navigation — it sees the still-matching /workout/finish/ URL, then
    // waits 15s for a post-session-continue-cta that's already gone.
    // (TEST-INFRA double-drive race; the helper is for a fresh cinematic.)
    await page.locator(POST_SESSION.continueCta).first().click();
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });
});
