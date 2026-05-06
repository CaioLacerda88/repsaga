/**
 * Localization E2E spec — Phase 15e.
 *
 * Validates that pt-BR localisation works end-to-end: server-seeded locale
 * boots the app in Portuguese, the language picker switches locales live,
 * pt-BR strings are rendered on the main screens, and the bottom navigation
 * does not clip any tab label at narrow viewport widths.
 *
 * Test users:
 *   - smokeLocalization  — profile.locale = 'pt' seeded in global-setup.
 *                          Boots the app in Portuguese without any picker
 *                          interaction, validating the 15d reconcileWithRemote
 *                          path. Also has one seeded workout (lapsed state).
 *   - smokeLocalizationEn — profile.locale not set (defaults to English).
 *                          Used for the en→pt live-switch test.
 *
 * Locale assertion strategy:
 *   Flutter NavigationBar tab labels are rendered as Text() children inside
 *   NavigationDestination widgets. Playwright's `text=` selector matches these
 *   as text nodes, BUT the locale reconciliation in ProfileNotifier.build() is
 *   async (reads from Hive then confirms with Supabase). The nav rebuilds only
 *   AFTER reconciliation completes, which adds a brief delay relative to login.
 *
 *   To avoid race conditions we use a two-pronged approach:
 *   1. For the primary locale assertion we navigate to a content screen
 *      (Profile or Exercises) and check the screen heading. These headings
 *      render as regular Text() widgets and correctly reflect the locale.
 *      By the time navigateToTab completes the locale reconciliation has had
 *      time to complete (the tab navigation itself takes ~1-2 s).
 *   2. For the nav label overflow check (test 8) we assert all four nav
 *      identifiers are present — the identifiers are locale-independent and
 *      prove the tabs are accessible in the AOM regardless of label text.
 *
 * Weight decimal formatting (80,5 kg in pt-BR) is intentionally NOT covered
 * here. No fractional weight is visible in the seeded state for the
 * smokeLocalization user (the seeded workout contains no set data). See the
 * note at the bottom of this file.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab, setLocale, waitForAppReady } from '../helpers/app';
import { NAV, PROFILE, EXERCISE_LIST, LOCALIZATION, SAGA } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

// ---------------------------------------------------------------------------
// Describe block 1: smokeLocalization user — boots in pt-BR via server seed
// ---------------------------------------------------------------------------
test.describe('Localization — pt-BR server-seeded boot', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalization').email,
      getUser('smokeLocalization').password,
    );
  });

  // -------------------------------------------------------------------------
  // Test 1: App boots in pt-BR after server-seeded locale (reconcileWithRemote).
  //
  // global-setup upserts profiles.locale = 'pt' for smokeLocalization. On
  // login ProfileNotifier.build() reads the remote locale via
  // reconcileWithRemote() and calls LocaleNotifier.setLocale(). This is
  // deferred via Future.microtask so the first frame renders with the Hive-
  // cached locale (or device default) and then rebuilds.
  //
  // We navigate to the Exercises screen (whose heading is "Exercícios" in
  // pt-BR) to verify the locale has been applied. We also check the Profile
  // heading "Perfil" to cover a second screen.
  //
  // Note: checking the bottom nav label text (text=Início) is done in a
  // separate test after navigateToTab gives reconciliation time to complete.
  // -------------------------------------------------------------------------
  test('should boot app in pt-BR after server-seeded locale', async ({ page }) => {
    // Navigate to Exercises — the heading must be the pt-BR translation.
    await navigateToTab(page, 'Exercises');
    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Exercícios').first()).toBeVisible({ timeout: 10_000 });

    // Navigate to the Saga tab (formerly Profile) then open Settings via gear icon.
    // Phase 18b: /profile now shows CharacterSheetScreen; legacy profile content
    // (heading "Perfil", language row, etc.) moved to /profile/settings.
    await navigateToTab(page, 'Profile');
    await expect(page.locator(SAGA.characterSheet).first()).toBeVisible({ timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await expect(page.locator(PROFILE.heading).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Perfil').first()).toBeVisible({ timeout: 10_000 });
  });

  // -------------------------------------------------------------------------
  // Test 2: Bottom nav tab labels render in Portuguese on the Home screen.
  //
  // After reconcileWithRemote applies the pt-BR locale the NavigationBar
  // widget rebuilds and the tab labels switch from English to Portuguese.
  // We navigate away and back to Home so the reconciliation has had time to
  // complete before we check the nav labels.
  //
  // Flutter exposes NavigationDestination items in the AOM as role=tab with
  // the label text as their accessible name. We use role=tab[name=...] selectors
  // (not text= selectors) to match the tab's accessible name.
  // -------------------------------------------------------------------------
  test('should show pt-BR nav labels after locale reconciliation', async ({ page }) => {
    // Navigate away (forces reconciliation to run while navigating).
    // Phase 18b: Saga tab shows CharacterSheet — navigate there to trigger
    // reconciliation, then navigate to Home to check nav label translations.
    await navigateToTab(page, 'Profile');
    await expect(page.locator(SAGA.characterSheet).first()).toBeVisible({ timeout: 10_000 });

    // Navigate back to Home.
    await navigateToTab(page, 'Home');

    // The nav labels must now be in Portuguese.
    // NavigationBar destinations are exposed as role=tab with the label as
    // their accessible name. Use LOCALIZATION selectors (role=tab[name=...]).
    await expect(page.locator(LOCALIZATION.ptNavHome).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(LOCALIZATION.ptNavExercises).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(LOCALIZATION.ptNavRoutines).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(LOCALIZATION.ptNavProfile).first()).toBeVisible({ timeout: 10_000 });
  });

  // -------------------------------------------------------------------------
  // Test 3: Profile screen renders key labels in Portuguese.
  //
  // ProfileScreen renders several l10n strings directly as Text widgets:
  //   - l10n.profile          → "Perfil"   (heading)
  //   - l10n.weightUnit       → "Unidade de Peso"
  //   - l10n.language         → "Idioma"
  // We assert three of these to cover the heading, a section label, and a
  // row label without being exhaustive.
  // -------------------------------------------------------------------------
  test('should render profile settings screen labels in Portuguese', async ({ page }) => {
    // Phase 18b: /profile shows CharacterSheetScreen; settings are at /profile/settings.
    // Open settings via gear icon to reach the screen that contains "Perfil" heading,
    // "Unidade de Peso" weight-unit label, and "Idioma" language row.
    await navigateToTab(page, 'Profile');
    await expect(page.locator(SAGA.characterSheet).first()).toBeVisible({ timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();

    await expect(page.locator(PROFILE.heading).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Perfil').first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Unidade de Peso').first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Idioma').first()).toBeVisible({ timeout: 10_000 });
  });

  // -------------------------------------------------------------------------
  // Test 4: Exercises screen heading renders in Portuguese.
  //
  // ExerciseListScreen renders l10n.exercises → "Exercícios" as the page
  // heading. We assert the heading text to confirm the exercises screen is
  // localised.
  // -------------------------------------------------------------------------
  test('should render exercises screen heading in Portuguese', async ({ page }) => {
    await navigateToTab(page, 'Exercises');

    await expect(page.locator(EXERCISE_LIST.heading).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Exercícios').first()).toBeVisible({ timeout: 10_000 });
  });

  // -------------------------------------------------------------------------
  // Test 5: "Member since" date renders in pt-BR abbreviated month format.
  //
  // _StatsRow on ProfileScreen calls AppDateFormat.monthYear(createdAt, locale: 'pt')
  // which uses DateFormat.yMMM('pt') → "abr. de 2026" (abbreviated month +
  // "de" connector + year). We assert that the rendered text contains "de "
  // (the connector unique to pt-BR abbreviated month-year) rather than an
  // English month abbreviation like "Apr".
  // -------------------------------------------------------------------------
  test('should render member-since date in pt-BR abbreviated month format', async ({
    page,
  }) => {
    // Phase 18b: "Membro desde" stat card is on ProfileSettingsScreen (/profile/settings).
    await navigateToTab(page, 'Profile');
    await expect(page.locator(SAGA.characterSheet).first()).toBeVisible({ timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();

    // "Membro desde" is the pt-BR label for the stat card.
    await expect(page.locator('text=Membro desde').first()).toBeVisible({ timeout: 10_000 });

    // Verify pt-BR date pattern: look for the "de " connector used in
    // DateFormat.yMMM('pt') output (e.g. "abr. de 2026").
    const pageText = await page.evaluate(() => document.body.innerText);
    expect(pageText).toMatch(/\bde \d{4}\b/);

    // Assert no English month abbreviations appear anywhere on screen.
    const englishMonthPattern = /\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/;
    expect(pageText).not.toMatch(englishMonthPattern);
  });

  // -------------------------------------------------------------------------
  // Test 6: pt→en language picker switch — starts in pt-BR, picks English.
  //
  // Uses the setLocale() helper which navigates to Profile → taps the
  // Language row → taps the 'en' option → waits for the sheet to dismiss.
  // After switching, the exercises screen heading must render English.
  // -------------------------------------------------------------------------
  test('should switch from pt-BR to English and render English screen headings', async ({
    page,
  }) => {
    // Confirm we start in pt-BR by checking the character sheet (Saga tab).
    await navigateToTab(page, 'Profile');
    await expect(page.locator(SAGA.characterSheet).first()).toBeVisible({ timeout: 10_000 });

    // Switch to English via the language picker (navigates to /profile/settings internally).
    await setLocale(page, 'en');

    // Navigate to Exercises — heading must now be English.
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercises').first()).toBeVisible({ timeout: 10_000 });

    // Restore to pt-BR so the user state is clean for subsequent runs.
    await setLocale(page, 'pt');
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercícios').first()).toBeVisible({ timeout: 10_000 });
  });
});

// ---------------------------------------------------------------------------
// Describe block 2: smokeLocalizationEn user — en default, tests en→pt switch
// ---------------------------------------------------------------------------
test.describe('Localization — en-default language picker switch', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalizationEn').email,
      getUser('smokeLocalizationEn').password,
    );
  });

  // -------------------------------------------------------------------------
  // Test 7: en→pt live switch updates screen headings without page reload.
  //
  // User starts with English locale (no locale seeded in profiles). Opens
  // the language picker, selects pt-BR. The MaterialApp.locale rebuilds and
  // screen headings must immediately switch to Portuguese.
  // -------------------------------------------------------------------------
  test('should switch from English to pt-BR and update screen headings live', async ({
    page,
  }) => {
    // Confirm we start in English — exercises heading should be "Exercises".
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercises').first()).toBeVisible({ timeout: 15_000 });

    // Switch to pt-BR via the language picker.
    await setLocale(page, 'pt');

    // Navigate back to Exercises — heading must be "Exercícios" in pt-BR.
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercícios').first()).toBeVisible({ timeout: 10_000 });

    // Also verify the ProfileSettingsScreen is Portuguese (navigate via gear icon).
    // Phase 18b: /profile shows CharacterSheet; settings at /profile/settings.
    await navigateToTab(page, 'Profile');
    await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 10_000 });
    await page.locator(SAGA.gearIcon).first().click();
    await expect(page.locator('text=Perfil').first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('text=Unidade de Peso').first()).toBeVisible({ timeout: 10_000 });

    // Restore to English (idempotent for future runs).
    await setLocale(page, 'en');
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercises').first()).toBeVisible({ timeout: 10_000 });
  });

  // -------------------------------------------------------------------------
  // Test 8: pt-BR locale persists across a page reload (Hive + Supabase round-trip).
  //
  // After switching to pt-BR, reload the page. The app must rehydrate the
  // locale from Hive (fast path) or Supabase (slow path) and continue
  // rendering Portuguese labels.
  // -------------------------------------------------------------------------
  test('should persist pt-BR locale across page reload', async ({ page }) => {
    // Switch to pt-BR.
    await setLocale(page, 'pt');

    // Verify pt-BR is active before reload.
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercícios').first()).toBeVisible({ timeout: 10_000 });

    // Reload the page — clears in-memory Riverpod state, forces rehydration.
    // waitForAppReady re-enables the Flutter semantics layer (destroyed on
    // reload) and waits for the router to navigate away from the splash.
    await page.reload();
    await waitForAppReady(page);

    // Re-login if the reload landed on /login (session may not persist across
    // a hard reload depending on Supabase session storage configuration).
    const currentUrl = page.url();
    if (currentUrl.includes('/login')) {
      await login(
        page,
        getUser('smokeLocalizationEn').email,
        getUser('smokeLocalizationEn').password,
      );
    }

    // Navigate to Exercises — the heading must be Portuguese after rehydration.
    // Locale reconciliation reads from Hive first (fast path: locale='pt' was
    // written by the previous setLocale call), so this should be immediate.
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercícios').first()).toBeVisible({ timeout: 20_000 });

    // Restore to English.
    await setLocale(page, 'en');
    await navigateToTab(page, 'Exercises');
    await expect(page.locator('text=Exercises').first()).toBeVisible({ timeout: 10_000 });
  });
});

// ---------------------------------------------------------------------------
// Describe block 3: Bottom nav overflow check — smokeLocalization user
// ---------------------------------------------------------------------------
test.describe('Localization — bottom nav no overflow at narrow viewport', { tag: '@smoke' }, () => {
  test.use({ viewport: { width: 375, height: 667 } });

  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeLocalization').email,
      getUser('smokeLocalization').password,
    );
  });

  // -------------------------------------------------------------------------
  // Test 9: All four nav tabs are present in the AOM at a 375px mobile viewport.
  //
  // RenderFlex overflow in the NavigationBar at narrow widths would cause one
  // or more tabs to be clipped and disappear from the accessibility tree.
  // We assert all four identifier-based selectors are visible to catch that.
  //
  // 375px is a common small-phone width (iPhone SE / Android compact). The
  // Portuguese labels are longer than English ("Exercícios" vs "Exercises",
  // "Rotinas" vs "Routines") so this specifically catches overflow regressions
  // introduced by longer translations.
  //
  // Identifier-based selectors are used (not text= selectors) because:
  //   a) They are locale-independent — the test is about overflow, not locale.
  //   b) They match the AOM node presence directly, which is what matters for
  //      keyboard / screen-reader navigation (the overflow spec requirement).
  // -------------------------------------------------------------------------
  test('should show all four nav tabs in AOM at 375px viewport width', async ({
    page,
  }) => {
    // All four tabs must be present in the accessibility tree.
    await expect(page.locator(NAV.homeTab).first()).toBeVisible({ timeout: 20_000 });
    await expect(page.locator(NAV.exercisesTab).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(NAV.routinesTab).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(NAV.profileTab).first()).toBeVisible({ timeout: 10_000 });
  });
});

// ---------------------------------------------------------------------------
// NOTE: Weight decimal formatting (80,5 kg in pt-BR) is NOT covered here.
//
// The smokeLocalization user has one seeded workout ("E2E Warmup Workout")
// with no set data, so no weight value is rendered anywhere in the app for
// this user. Seeding a workout-with-sets solely for a formatting assertion
// adds fragility without proportional confidence (the formatting is exercised
// by the AppNumberFormat widget tests in test/unit/).
//
// If a future seeded user gains fractional-weight set data, assert that the
// History or PR screen renders "80,5 kg" (comma) rather than "80.5 kg" (dot).
// ---------------------------------------------------------------------------
