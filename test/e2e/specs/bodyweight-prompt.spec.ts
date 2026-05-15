/**
 * Bodyweight prompt — Phase 24c-8 E2E.
 *
 * Pins the lazy-prompt round-trip end to end:
 *   1. User starts a workout with a `uses_bodyweight_load = TRUE` exercise
 *      (Pull-Up).
 *   2. Completing the first set surfaces the bodyweight prompt SnackBar.
 *   3. Tapping "Set now" opens the BodyweightEditorSheet (the same sheet
 *      reachable from profile-settings, deep-linked here per 24c-7).
 *   4. Saving 70 closes the sheet and persists `profiles.bodyweight_kg = 70`.
 *   5. Finishing the workout records an `xp_event` whose `payload.effective_load`
 *      reflects the new bodyweight (the SQL math in 00057_record_xp_with_bodyweight_load
 *      reads the freshly-saved profile).
 *
 * **Why @smoke:** XP integrity for bodyweight exercises depends on this
 * surface — without the prompt, users on bodyweight-heavy routines silently
 * undercount XP indefinitely. The smoke gate must catch a regression in
 * either the prompt visibility OR the post-save SQL pickup.
 */
import { test, expect } from '@playwright/test';
import { dismissCelebrationIfPresent } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  startEmptyWorkout,
  addExercise,
  setReps,
  completeSet,
  finishWorkout,
} from '../helpers/workout';
import { NAV } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

test.describe('Bodyweight prompt', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeBodyweightPrompt').email,
      getUser('smokeBodyweightPrompt').password,
    );
  });

  test(
    'should prompt for body weight on first uses_bodyweight_load set, save it, '
    + 'and feed the new value into the next xp_event payload',
    async ({ page }) => {
      // Pre-condition: the seeded user has profile.bodyweight_kg = NULL
      // (per global-setup `smokeBodyweightPrompt` runner). We assert this
      // BEFORE the UI flow so a regression in the seeder fails loudly here
      // rather than masquerading as a UI bug downstream.
      const admin = getAdminClient();
      const userId = await getUserIdByEmail(
        admin,
        getUser('smokeBodyweightPrompt').email,
      );
      expect(userId, 'smokeBodyweightPrompt user must exist after global-setup').not.toBeNull();
      const userRow = await admin
        .from('profiles')
        .select('bodyweight_kg')
        .eq('id', userId!)
        .single();
      expect(userRow.data?.bodyweight_kg).toBeNull();

      // 1. Start a workout from the home CTA.
      await startEmptyWorkout(page);

      // 2. Add Pull-Up — `uses_bodyweight_load = TRUE` per
      //    00056_add_bodyweight_load_semantics.sql. This is the load-bearing
      //    selection: any non-bodyweight exercise (bench press etc.) would
      //    bypass the prompt entirely.
      await addExercise(page, SEED_EXERCISES.pullUp);

      // 3. Complete the first set. Pull-Up's seeded weight is 0 (bodyweight
      //    move with no added load); only set reps then mark done.
      await setReps(page, '8');
      await completeSet(page, 0);

      // 4. Assert the prompt SnackBar appears. The EN copy is
      //    "Set your body weight for accurate XP" — `bodyweightPromptTitle`
      //    in app_en.arb.
      //
      //    Flutter CanvasKit draws the SnackBar text to canvas (no DOM text
      //    node) and the AOM exposes it as a `role=group` whose accessible
      //    name contains the text. `.first()` is required because Flutter
      //    emits two AOM boundaries per SnackBar (per the CLAUDE.md E2E
      //    Conventions note + the swipe-to-delete + add-exercise undo
      //    selector patterns in helpers/selectors.ts).
      const promptText = page.locator(
        'role=group[name=/Set your body weight for accurate XP/]',
      ).first();
      await expect(promptText).toBeVisible({ timeout: 10_000 });

      // 5. Tap "Set now" — opens BodyweightEditorSheet.
      //    `role=button[name="Set now"]` — Flutter renders the SnackBar
      //    action as a TextButton whose accessible name is the label.
      await page.locator('role=button[name="Set now"]').first().click();

      // 6. The Save button is the AOM signal that the BodyweightEditorSheet
      //    is open. Flutter 3.41.6 uses AOM for accessibility (not DOM
      //    `flt-semantics-*` attributes — per CLAUDE.md E2E Conventions).
      //    `role=button[name="Save"]` matches the sheet's primary action.
      const saveButton = page
        .locator('role=button[name="Save"]')
        .first();
      await expect(saveButton).toBeVisible({ timeout: 10_000 });

      // 7. Type 70 in the sheet input. Use Playwright's keyboard.type
      //    against the focused <input> — Flutter routes real key events
      //    through CanvasKit's hidden proxy. The TextField is autofocus,
      //    so we click `input` (the hidden CanvasKit proxy) to guarantee
      //    focus then type via the keyboard.
      const input = page.locator('input').last();
      await input.click({ timeout: 5_000 });
      await page.keyboard.press('Control+a');
      await page.keyboard.press('Delete');
      await page.keyboard.type('70', { delay: 10 });

      // 8. Tap Save — the sheet pops with the saved kg, profileProvider
      //    invalidates, and the prompt's session-shot flag short-circuits
      //    any future qualifying-set checks.
      await saveButton.click();
      await expect(saveButton).not.toBeVisible({ timeout: 10_000 });

      // 9. Finish the workout. This commits the pull-up set + xp_event
      //    via record_xp_with_bodyweight_load (00057). The xp_event payload
      //    must carry effective_load = 70 because the user's bodyweight is
      //    now 70 kg AND the exercise is uses_bodyweight_load.
      await finishWorkout(page);
      await dismissCelebrationIfPresent(page);
      await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 20_000 });

      // 10. Verify via REST: profile.bodyweight_kg is persisted.
      const after = await admin
        .from('profiles')
        .select('bodyweight_kg')
        .eq('id', userId!)
        .single();
      expect(after.data?.bodyweight_kg).toBeCloseTo(70, 1);

      // 11. Verify the latest pull-up xp_event payload reflects the
      //     bodyweight contribution. We pick the most recent xp_event for
      //     this user and assert payload.effective_load = 70 (entered
      //     weight 0 + bodyweight 70) AND payload.bodyweight_used = true.
      //
      //     Phase 24c-3 + 24c-4 pin the payload shape. If this fails the
      //     server-side wiring isn't picking up the freshly-saved profile
      //     row — almost always a caching bug in record_xp_with_bodyweight_load
      //     OR a regression in 00057 reading bodyweight_kg from the wrong
      //     source.
      const xpEvents = await admin
        .from('xp_events')
        .select('id, payload, created_at')
        .eq('user_id', userId!)
        .order('created_at', { ascending: false })
        .limit(5);
      expect(xpEvents.error).toBeNull();
      expect(xpEvents.data?.length).toBeGreaterThan(0);

      // The most recent event should be the pull-up set we just completed.
      // Find the first event whose payload.bodyweight_used === true (this
      // filters out any incidental events from other code paths).
      const bodyweightEvent = xpEvents.data?.find(
        (e: { payload: Record<string, unknown> }) =>
          e.payload?.['bodyweight_used'] === true,
      );
      expect(
        bodyweightEvent,
        'Expected at least one xp_event with payload.bodyweight_used=true '
          + 'after finishing a pull-up workout post-save. Got: '
          + JSON.stringify(xpEvents.data),
      ).toBeDefined();
      expect(
        (bodyweightEvent!.payload as Record<string, number>)['effective_load'],
      ).toBeCloseTo(70, 1);
    },
  );
});
