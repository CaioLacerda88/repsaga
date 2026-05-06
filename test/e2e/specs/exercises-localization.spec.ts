/**
 * Exercise content localization — E2E scenarios A1-A5, B1-B2, G1-G2.
 * Phase 15f: exercise name/description/form_tips served from
 * exercise_translations table via fn_exercises_localized RPC.
 *
 * Scenarios:
 *   A1 @smoke — pt user sees list alphabetized in pt; spot-check 3 names
 *   A2 @smoke — pt user opens detail → pt name/description/form_tips
 *   A3         — en user sees list in en
 *   A4 @smoke  — en user sees en detail
 *   A5         — pt user filters chest → pt chest exercises only
 *   B1         — pt user searches "supino" → finds pt-named bench press
 *   B2         — pt user searches "bench" → finds via en-name fallback
 *   G1         — pt user creates custom exercise → visible with pt name; en user doesn't see it
 *   G2         — Accented chars round-trip correctly (name + description)
 */

import { test, expect } from '@playwright/test';
import { flutterFill, flutterFillByInput, navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import {
  EXERCISE_LIST,
  EXERCISE_DETAIL,
  EXERCISE_LOC,
  CREATE_EXERCISE,
} from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { EXERCISE_NAMES } from '../fixtures/test-exercises';

// =============================================================================
// SMOKE: Exercise list and detail — pt locale (A1, A2)
// Uses smokeLocalization user (existing pt user from Phase 15e)
// =============================================================================

test.describe('Exercise list localization', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalization').email,
      getUser('smokeLocalization').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  // A1: pt user sees list alphabetized in pt; spot-check a pt-unique name.
  test('should show pt-BR exercise names in the exercise list for pt user (A1)', async ({
    page,
  }) => {
    // Wait for the exercise list to load.
    // pt locale: AOM label prefix is "Exercício:" (app_pt.arb exerciseItemSemantics).
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;

    // Broad load-gate: at least one pt-localized exercise card must render.
    // Specific card assertion comes after the search below — splitting these
    // avoids a tautological `.or()` where the broad fallback always satisfies
    // the gate before the specific card has had a chance to load.
    await expect(
      page.locator('role=button[name*="Exercício:"]').first(),
    ).toBeVisible({ timeout: 15_000 });

    // Search for the pt name of Barbell Bench Press ("Supino" — starts with S,
    // off-screen in the initial A-sorted viewport).
    //
    // Flake fix (CI run 25242304322 — A1/A2/B1/B2): switch from
    // `flutterFill(page, EXERCISE_LIST.searchInput, ...)` to
    // `flutterFillByInput(page, 'Buscar exercícios', ...)`. The flt-semantics-
    // identifier overlay click in `flutterFill` is unreliable for the
    // Semantics-wrapped TextField in exercise_list_screen.dart — AOM dump
    // showed the input was rendered but no query landed, so the debounced
    // state change never fired and the RPC was never called (15s timeout).
    // `flutterFillByInput` does direct `inputEl.focus()` + keyboard, mirroring
    // the proven-stable A4 pattern.
    //
    // Flake fix (#20/A1): register the waitForResponse promise BEFORE the fill
    // so we never miss the RPC response that fires as soon as the debounce
    // expires (~300ms). The old waitForTimeout(800) raced CI latency —
    // replacing with a deterministic waitForResponse on
    // fn_search_exercises_localized eliminates the race regardless of network
    // / worker load. Timeout of 15s accommodates cold Supabase containers in
    // local and CI environments. Don't filter on status — a 4xx surfaces as
    // a meaningful test failure instead of a 15s timeout, revealing auth/RLS
    // issues in CI early.
    const searchResponsePromise = page.waitForResponse(
      (resp) => resp.url().includes('fn_search_exercises_localized'),
      { timeout: 15_000 },
    );
    await flutterFillByInput(page, 'Buscar exercícios', ptBenchName.substring(0, 6));
    await searchResponsePromise;
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(ptBenchName, 'pt')).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Verify the en name does NOT appear for this pt user.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(enBenchName, 'pt')),
    ).not.toBeVisible({ timeout: 3_000 });
  });

  // A2: pt user opens exercise detail → sees pt name, description, form_tips.
  test('should show pt description and form_tips on exercise detail for pt user (A2)', async ({
    page,
  }) => {
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;

    // Search for the pt name of Barbell Bench Press.
    //
    // Flake fix (CI run 25242304322 — A1/A2/B1/B2): use flutterFillByInput
    // (direct inputEl.focus() + keyboard) instead of flutterFill (flt-semantics
    // overlay click) — see A1 docblock above for the AOM-dump evidence.
    //
    // Flake fix (#20/A2): same deterministic waitForResponse pattern as A1.
    // Register before the fill so we don't miss the Supabase RPC response.
    // Don't filter on status — 4xx is a fast, clear failure vs a 15s timeout.
    const searchResponsePromise = page.waitForResponse(
      (resp) => resp.url().includes('fn_search_exercises_localized'),
      { timeout: 15_000 },
    );
    await flutterFillByInput(page, 'Buscar exercícios', ptBenchName.substring(0, 8));
    await searchResponsePromise;

    const card = page
      .locator(EXERCISE_LOC.exerciseCard(ptBenchName, 'pt'))
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();

    // Detail screen must be visible.
    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // The exercise name rendered in the detail body must be the pt name.
    await expect(
      page.locator(`text=${ptBenchName}`).first(),
    ).toBeVisible({ timeout: 5_000 });

    // ABOUT section must be present (pt: "SOBRE" — app_pt.arb aboutSection).
    await expect(
      page.locator(EXERCISE_LOC.aboutSectionText('pt')).first(),
    ).toBeVisible({ timeout: 5_000 });

    // FORM TIPS section must be present (pt: "DICAS DE FORMA" — app_pt.arb formTipsSection).
    await expect(
      page.locator(EXERCISE_LOC.formTipsSectionText('pt')).first(),
    ).toBeVisible({ timeout: 5_000 });

    // No literal backslash-n (regression guard from BUG-002).
    const literalBackslashN = page.locator('text=/\\\\n/');
    await expect(literalBackslashN).not.toBeVisible({ timeout: 3_000 });
  });
});

// =============================================================================
// SMOKE: Exercise detail — en locale (A4)
// Uses smokeLocalizationEn user (existing en user from Phase 15e)
// =============================================================================

test.describe('Exercise detail en locale', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalizationEn').email,
      getUser('smokeLocalizationEn').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  // A4: en user sees en detail.
  test('should show en description and form_tips on exercise detail for en user (A4)', async ({
    page,
  }) => {
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;

    await flutterFillByInput(page, 'Search exercises', 'Barbell Bench');
    await page.waitForTimeout(800);

    const card = page
      .locator(EXERCISE_LOC.exerciseCard(enBenchName, 'en'))
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();

    await expect(page.locator(EXERCISE_DETAIL.appBarTitle)).toBeVisible({
      timeout: 10_000,
    });

    // The en name must be visible in the detail body.
    await expect(
      page.locator(`text=${enBenchName}`).first(),
    ).toBeVisible({ timeout: 5_000 });

    // ABOUT section with en description.
    await expect(
      page.locator(EXERCISE_LOC.aboutSectionText('en')).first(),
    ).toBeVisible({ timeout: 5_000 });

    // FORM TIPS with en form tips.
    await expect(
      page.locator(EXERCISE_LOC.formTipsSectionText('en')).first(),
    ).toBeVisible({ timeout: 5_000 });

    // The pt name must NOT appear anywhere on screen.
    await expect(
      page.locator(`text=${ptBenchName}`),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});

// =============================================================================
// FULL: Exercise list en (A3), filters (A5), search (B1, B2), custom (G1, G2)
// =============================================================================

test.describe('Exercise list en locale', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('fullExercises').email,
      getUser('fullExercises').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  // A3: en user sees list in en.
  test('should show en exercise names for en user in exercise list (A3)', async ({
    page,
  }) => {
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;

    const cards = page.locator('role=button[name*="Exercise:"]');
    await expect(cards.first()).toBeVisible({ timeout: 15_000 });

    // The en name must appear in the list.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(enBenchName, 'en')).first(),
    ).toBeVisible({ timeout: 10_000 });

    // The pt name must NOT appear.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(ptBenchName, 'en')),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});

test.describe('Exercise list pt locale filters and search', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalization').email,
      getUser('smokeLocalization').password,
    );
    await navigateToTab(page, 'Exercises');
  });

  // A5: pt user filters chest → pt chest exercises only.
  test('should show only pt-named chest exercises when applying chest filter for pt user (A5)', async ({
    page,
  }) => {
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;

    // pt locale: AOM prefix is "Exercício:" (app_pt.arb exerciseItemSemantics).
    const cards = page.locator('role=button[name*="Exercício:"]');
    await expect(cards.first()).toBeVisible({ timeout: 15_000 });

    // Apply Chest filter.
    // pt locale: the button identifier uses the pt display label → 'Peito'.
    // (identifier = `exercise-filter-${label.toLowerCase()}` per exercise_list_screen.dart:196)
    await page.click(EXERCISE_LIST.muscleGroupFilter('Peito'));
    await page.waitForTimeout(600);

    // The filter chip must be selected.
    await expect(
      page.locator(EXERCISE_LIST.muscleGroupFilter('Peito')),
    ).toHaveAttribute('aria-current', 'true');

    // Search for the pt bench press to bring it into view.
    // "Supino Reto com Barra" starts with S — may be off-screen.
    // Use identifier-based searchInput (locale-independent).
    await flutterFill(page, EXERCISE_LIST.searchInput, ptBenchName.substring(0, 6));
    await page.waitForTimeout(600);

    // The pt bench press (a chest exercise) must appear in pt locale.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(ptBenchName, 'pt')).first(),
    ).toBeVisible({ timeout: 10_000 });

    // The en bench press AOM label must NOT appear (pt user sees pt names).
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(enBenchName, 'pt')),
    ).not.toBeVisible({ timeout: 3_000 });
  });

  // B1: pt user searches "supino" → finds pt-named bench press.
  test('should find pt-named bench press when searching "supino" as pt user (B1)', async ({
    page,
  }) => {
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;

    // Flake fix (CI run 25242304322 — A1/A2/B1/B2): use flutterFillByInput
    // (direct inputEl.focus() + keyboard) instead of flutterFill (flt-semantics
    // overlay click) — see A1 docblock for the AOM-dump evidence.
    //
    // Flake fix (#20/B1): same deterministic waitForResponse pattern as A1/A2.
    // Don't filter on status — 4xx is a fast, clear failure vs a 15s timeout.
    const searchResponsePromise = page.waitForResponse(
      (resp) => resp.url().includes('fn_search_exercises_localized'),
      { timeout: 15_000 },
    );
    await flutterFillByInput(page, 'Buscar exercícios', 'supino');
    await searchResponsePromise;

    // At least one result must appear containing the pt bench press name.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(ptBenchName, 'pt')).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  // B2: pt user searches "bench" → finds via en-name cross-locale fallback.
  // The RPC's trigram index covers BOTH locales, so an en-language query from
  // a pt user must still match. The display name returned MUST be pt (the RPC
  // resolves display via the locale fallback cascade, not the matched locale).
  test('should find pt-named bench press when searching "bench" as pt user via cross-locale fallback (B2)', async ({
    page,
  }) => {
    const ptBenchName = EXERCISE_NAMES.barbell_bench_press.pt;
    const enBenchName = EXERCISE_NAMES.barbell_bench_press.en;

    // Flake fix (CI run 25242304322 — A1/A2/B1/B2): use flutterFillByInput
    // (direct inputEl.focus() + keyboard) instead of flutterFill (flt-semantics
    // overlay click) — see A1 docblock for the AOM-dump evidence.
    //
    // Flake fix (#20/B2): same deterministic waitForResponse pattern as A1/B1.
    // Register the promise BEFORE the fill so the RPC response is never missed.
    // Don't filter on status — 4xx is a fast, clear failure vs a 15s timeout.
    const searchResponsePromise = page.waitForResponse(
      (resp) => resp.url().includes('fn_search_exercises_localized'),
      { timeout: 15_000 },
    );
    await flutterFillByInput(page, 'Buscar exercícios', 'bench');
    await searchResponsePromise;

    // Hard assertion: the pt-named bench press card MUST appear. This is B2's
    // primary contract — cross-locale search by en query returns a result for
    // a pt user, with the result rendered in pt.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(ptBenchName, 'pt')).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Hard assertion: the en name must NOT leak into the pt user's list. The
    // RPC's display resolution must override the language used to match.
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(enBenchName, 'pt')),
    ).not.toBeVisible({ timeout: 3_000 });
  });
});

// =============================================================================
// FULL: User-created exercise pt (G1, G2)
// G1 uses TWO browser contexts to actually verify cross-user RLS:
//   - context A: pt creator (smokeLocalization) creates the exercise
//   - context B: en user (fullExercises) logs in fresh and confirms it does
//     not appear in their list. Without two contexts the RLS contract is
//     untested — a single context would just be a logout-cancel.
// =============================================================================

test.describe('User-created exercise pt locale', () => {
  // G1: pt user creates "Meu Exercício" → visible with pt name on creator's list;
  //     en user (fullExercises) does NOT see it (RLS on user_id).
  test('should show custom pt-named exercise for creator but not for en user (G1)', async ({
    browser,
  }) => {
    const ptExerciseName = `Meu Exercício ${Date.now()}`;

    // ─ Context A: pt creator creates the exercise ───────────────────────
    const creatorContext = await browser.newContext();
    const creatorPage = await creatorContext.newPage();
    try {
      await login(
        creatorPage,
        getUser('smokeLocalization').email,
        getUser('smokeLocalization').password,
      );
      await navigateToTab(creatorPage, 'Exercises');

      await creatorPage.click(EXERCISE_LIST.createFab);
      await expect(creatorPage.locator(CREATE_EXERCISE.nameInput)).toBeVisible({
        timeout: 10_000,
      });
      await flutterFill(creatorPage, CREATE_EXERCISE.nameInput, ptExerciseName);
      // pt locale: "Grupo muscular: Peito" / "Tipo de equipamento: Barra".
      await creatorPage
        .locator('role=button[name*="Grupo muscular: Peito"]')
        .first()
        .click();
      await creatorPage
        .locator('role=button[name*="Tipo de equipamento: Barra"]')
        .first()
        .click();
      await creatorPage.click(CREATE_EXERCISE.saveButton);

      // Must navigate back to the list.
      await expect(
        creatorPage.locator(EXERCISE_LIST.heading).first(),
      ).toBeVisible({ timeout: 15_000 });

      // Search for the exercise — creator MUST see it with pt prefix.
      await flutterFill(
        creatorPage,
        EXERCISE_LIST.searchInput,
        ptExerciseName.substring(0, 10),
      );
      await creatorPage.waitForTimeout(800);
      const creatorCard = creatorPage
        .locator(EXERCISE_LOC.exerciseCard(ptExerciseName, 'pt'))
        .first();
      await expect(creatorCard).toBeVisible({ timeout: 10_000 });

      // Owner must see the custom badge on detail (RLS allows owner to read
      // their own custom exercise).
      await creatorCard.click();
      await expect(
        creatorPage.locator(EXERCISE_DETAIL.customBadge),
      ).toBeVisible({ timeout: 5_000 });
    } finally {
      // Keep creatorContext open until after we verify with en user, then close.
    }

    // ─ Context B: en user logs in fresh and MUST NOT see the pt exercise ──
    const enContext = await browser.newContext();
    const enPage = await enContext.newPage();
    try {
      await login(
        enPage,
        getUser('fullExercises').email,
        getUser('fullExercises').password,
      );
      await navigateToTab(enPage, 'Exercises');

      // Wait for the en list to render.
      await expect(
        enPage.locator('role=button[name*="Exercise:"]').first(),
      ).toBeVisible({ timeout: 15_000 });

      // Search for the pt exercise name. RLS must hide it from this user.
      await flutterFill(
        enPage,
        EXERCISE_LIST.searchInput,
        ptExerciseName.substring(0, 10),
      );
      await enPage.waitForTimeout(800);

      // Hard RLS contract: the pt user's custom exercise MUST NOT appear in
      // the en user's list under EITHER locale prefix.
      await expect(
        enPage.locator(EXERCISE_LOC.exerciseCard(ptExerciseName, 'en')),
      ).not.toBeVisible({ timeout: 5_000 });
      await expect(
        enPage.locator(EXERCISE_LOC.exerciseCard(ptExerciseName, 'pt')),
      ).not.toBeVisible({ timeout: 3_000 });
    } finally {
      await enContext.close();
      await creatorContext.close();
    }
  });

  // G2: Accented chars round-trip correctly (name + description).
  test('should round-trip accented characters in exercise name and description (G2)', async ({
    page,
  }) => {
    const accentedName = `Levantamento Específico ${Date.now()}`;

    await login(
      page,
      getUser('smokeLocalization').email,
      getUser('smokeLocalization').password,
    );
    await navigateToTab(page, 'Exercises');

    // Create the exercise with accented name.
    await page.click(EXERCISE_LIST.createFab);
    await expect(page.locator(CREATE_EXERCISE.nameInput)).toBeVisible({
      timeout: 10_000,
    });
    await flutterFill(page, CREATE_EXERCISE.nameInput, accentedName);
    // pt locale: "Grupo muscular: Costas" / "Tipo de equipamento: Halter".
    await page.locator('role=button[name*="Grupo muscular: Costas"]').first().click();
    await page.locator('role=button[name*="Tipo de equipamento: Halter"]').first().click();
    await page.click(CREATE_EXERCISE.saveButton);

    // Navigate back to list.
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({
      timeout: 15_000,
    });

    // Search for the accented name.
    await flutterFill(
      page,
      EXERCISE_LIST.searchInput,
      accentedName.substring(0, 12),
    );
    await page.waitForTimeout(800);

    // The accented name must appear exactly as entered (no mangling of
    // ã, é, ü, ô, ç, or em-dash).
    // pt locale: AOM prefix is "Exercício:".
    await expect(
      page.locator(EXERCISE_LOC.exerciseCard(accentedName, 'pt')),
    ).toBeVisible({ timeout: 10_000 });
  });
});
