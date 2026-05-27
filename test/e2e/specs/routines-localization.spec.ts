/**
 * Routines content localization — E2E scenarios.
 *
 * Phase 15f: exercise names in routine create/edit resolved from exercise_translations.
 * Phase 32 PR 32a: default routine names (Push Day / Pull Day / etc.) resolved
 *   from workout_template_translations; MY ROUTINES section header reads
 *   "MEUS TREINOS" in pt (was "MINHAS TREINOS" before grammar fix).
 *
 * Scenarios:
 *   E1 — pt user creates routine with pt-picker → pt names in routine list
 *   Phase 32 — MY ROUTINES header + default routine names render localized
 */

import { test, expect } from '@playwright/test';
import { flutterFill, navigateToTab, scrollToVisible } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  ROUTINE,
  CREATE_ROUTINE,
  ROUTINE_MANAGEMENT,
  EXERCISE_PICKER,
  EXERCISE_LOC,
} from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { EXERCISE_NAMES } from '../fixtures/test-exercises';

// =============================================================================
// FULL: Routine create with pt exercise picker (E1)
// Uses smokeLocalizationRoutines user (pt locale, lapsed state)
// =============================================================================

test.describe('Routine localization pt locale', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalizationRoutines').email,
      getUser('smokeLocalizationRoutines').password,
    );
    await navigateToTab(page, 'Routines');
  });

  // E1: pt user creates routine with pt-picker → pt names in routine list.
  test('should show pt exercise names in routine exercise picker for pt user (E1)', async ({
    page,
  }) => {
    const routineName = `Treino PT ${Date.now()}`;
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;

    // Open the create routine screen.
    await page.click(ROUTINE_MANAGEMENT.createIconButton);
    await expect(
      page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle),
    ).toBeVisible({ timeout: 10_000 });

    // Enter a routine name.
    const nameInput = page.locator(CREATE_ROUTINE.nameInput);
    await expect(nameInput).toBeVisible({ timeout: 5_000 });
    await nameInput.fill(routineName);

    // Open the exercise picker.
    await page.click(CREATE_ROUTINE.addExerciseButton);
    await expect(page.locator(EXERCISE_PICKER.searchInput)).toBeVisible({
      timeout: 10_000,
    });

    // Search for the pt bench press name. flutterFill is required — Flutter
    // CanvasKit ignores synthetic events from page.fill().
    await flutterFill(
      page,
      EXERCISE_PICKER.searchInput,
      ptBenchName.substring(0, 6),
    );
    await page.waitForTimeout(800);

    // E1 hard assertion: the pt-named picker entry MUST be present. A
    // misconfigured RPC or wrong locale resolution would fail this.
    const ptAddButton = page
      .locator(EXERCISE_LOC.addExerciseButton(ptBenchName, 'pt'))
      .first();
    await expect(ptAddButton).toBeVisible({ timeout: 10_000 });
    await ptAddButton.click();

    // Wait for the picker to close (back to create-routine screen).
    await expect(
      page.locator(ROUTINE_MANAGEMENT.createRoutineScreenTitle),
    ).toBeVisible({ timeout: 10_000 });

    // Save the routine.
    await page.click(CREATE_ROUTINE.saveButton);

    // Should navigate back to the routines list.
    await expect(page.locator(ROUTINE.heading)).toBeVisible({ timeout: 15_000 });

    // The routine must appear in MY ROUTINES section.
    await expect(
      page.locator(ROUTINE.routineName(routineName)),
    ).toBeVisible({ timeout: 10_000 });
  });
});

// =============================================================================
// SMOKE: MY ROUTINES header + default routine names render localized (Phase 32 PR 32a)
//
// Two flows, one per locale:
//   1. en (smokeLocalizationEn) — header reads "MY ROUTINES", default
//      template names render in English ("Push Day", "Full Body", etc.).
//   2. pt (smokeLocalizationRoutines) — header reads "MEUS TREINOS" (post
//      grammar fix from "MINHAS TREINOS"), default template names render
//      in Portuguese ("Dia de Empurrar", "Corpo Inteiro", etc.) — these
//      come from workout_template_translations via the resolver, NOT from
//      the verbatim English literal in workout_templates.name.
//
// Per CLAUDE.md cluster_e2e_global_setup_seed_verify: default templates
// are seeded via supabase/migrations/00014_seed_default_workout_templates.sql
// (global, not per-user) so every authenticated user sees them. The PT
// names come from supabase/migrations/00067_workout_template_translations.sql.
// =============================================================================

test.describe(
  'Routine localization headers + default names',
  { tag: '@smoke' },
  () => {
    test('should show MY ROUTINES header in English for en locale user', async ({
      page,
    }) => {
      await login(
        page,
        getUser('smokeLocalizationEn').email,
        getUser('smokeLocalizationEn').password,
      );
      await navigateToTab(page, 'Routines');

      // Section header reads "MY ROUTINES" in en locale.
      await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
        timeout: 15_000,
      });
      await expect(page.locator('text=MY ROUTINES').first()).toBeVisible({
        timeout: 10_000,
      });
    });

    test('should show MEUS TREINOS header in Portuguese (post grammar fix)', async ({
      page,
    }) => {
      await login(
        page,
        getUser('smokeLocalizationRoutines').email,
        getUser('smokeLocalizationRoutines').password,
      );
      await navigateToTab(page, 'Routines');

      // Phase 32 PR 32a grammar fix: header now reads "MEUS TREINOS"
      // (masculine plural agreeing with "treinos") rather than the legacy
      // "MINHAS TREINOS" (feminine, ungrammatical).
      await expect(page.locator(ROUTINE.myRoutinesSection)).toBeVisible({
        timeout: 15_000,
      });
      await expect(page.locator('text=MEUS TREINOS').first()).toBeVisible({
        timeout: 10_000,
      });
      // Guard: legacy ungrammatical heading must not appear anywhere.
      await expect(page.locator('text=MINHAS TREINOS')).not.toBeVisible({
        timeout: 3_000,
      });
    });

    test('should show pt-translated default routine names for pt locale user', async ({
      page,
    }) => {
      await login(
        page,
        getUser('smokeLocalizationRoutines').email,
        getUser('smokeLocalizationRoutines').password,
      );
      await navigateToTab(page, 'Routines');

      await expect(page.locator(ROUTINE.starterRoutinesSection)).toBeVisible({
        timeout: 15_000,
      });

      // Default routine names must render their pt translations from
      // workout_template_translations. The verbatim English literals
      // (Push Day, Full Body) must NOT appear — that would mean the
      // resolver join silently dropped pt rows.
      const ptDefaults: Array<{ pt: string; en: string }> = [
        { pt: 'Dia de Empurrar', en: 'Push Day' },
        { pt: 'Dia de Puxar', en: 'Pull Day' },
        { pt: 'Dia de Pernas', en: 'Leg Day' },
        { pt: 'Corpo Inteiro', en: 'Full Body' },
      ];

      for (const { pt, en } of ptDefaults) {
        // Scroll the pt-named card into view — SliverList culls off-screen.
        await scrollToVisible(page, ROUTINE.routineName(pt));
        await expect(page.locator(ROUTINE.routineName(pt)).first()).toBeVisible({
          timeout: 10_000,
        });
        // The English literal must not appear as a standalone card
        // text node — if it does, the resolver is not running.
        await expect(
          page.getByText(en, { exact: true }),
        ).not.toBeVisible({ timeout: 2_000 });
      }
    });
  },
);
