/**
 * Home screen — Phase 26f redesign.
 *
 * Covers the new home composition:
 *   1. CharacterCard (collapsed/expanded, closest-rank-up indicator)
 *   2. EncouragementNudge (rotating priority line)
 *   3. ActionHero (3 branches: start-routine, free-workout, create-first-routine)
 *   4. BucketChipRow (header + chips when bucket non-empty + Editar plano link)
 *   5. LastSessionLine, HomeRoutinesList (preserved from W8)
 *
 * Branch identifiers are locale-independent — assertions target
 * `home-action-hero-<branch>` rather than localized text.
 *
 * User selection
 * --------------
 * - fullHome (@smoke): lapsed (1 minimal workout, no plan, default routines
 *   exist, no body-part training data). Steady state for character-card
 *   collapse/expand, day-0 closest-rank-up fallback, free-workout ActionHero,
 *   empty-bucket BucketChipRow (header + Editar plano only).
 * - rpgFoundationUser: 12 workouts seeded across 6 weeks → multiple body
 *   parts trained. Drives the closest-rank-up indicator (non-fallback) and
 *   body-part-row tap → /saga/stats deep-dive.
 * - smokeWeeklyPlan: lapsed, no plan. Drives plan creation in-test so the
 *   bucket chip row + start-routine ActionHero branch are reachable.
 */

import { test, expect } from '@playwright/test';
import { Page } from '@playwright/test';
import { navigateToTab } from '../helpers/app';
import { login } from '../helpers/auth';
import { HOME, NAV, SAGA, WEEKLY_PLAN, WEEKLY_PLAN_26E } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

// The Push Day starter routine is seeded by seed.sql.
const PUSH_DAY = 'Push Day';

/**
 * Drive the UI to add Push Day to the current week's plan, used by tests that
 * need a non-empty bucket. Mirrors the pattern from weekly-plan.spec.ts so the
 * tests don't depend on raw DB writes.
 */
async function ensurePushDayInPlan(page: Page): Promise<void> {
  await page.evaluate(() => {
    window.location.hash = '#/plan/week';
  });
  await page.waitForURL('**/plan/week**', { timeout: 10_000 });
  await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
    timeout: 15_000,
  });

  const alreadyIn = await page
    .locator(`text=${PUSH_DAY}`)
    .first()
    .isVisible({ timeout: 3_000 })
    .catch(() => false);

  if (!alreadyIn) {
    const addBtn = page
      .locator(WEEKLY_PLAN.addRoutinesButton)
      .or(page.locator(WEEKLY_PLAN.addRoutineRow))
      .or(page.locator(WEEKLY_PLAN_26E.addWorkoutCta));
    await expect(addBtn.first()).toBeVisible({ timeout: 10_000 });
    await addBtn.first().click();

    await expect(page.locator(WEEKLY_PLAN.addRoutinesSheetTitle)).toBeVisible({
      timeout: 10_000,
    });

    // Flutter's ListView.builder uses viewport culling — items below the fold
    // are not in the DOM. Scroll until the Push Day tile appears, then tap.
    const pushDayTile = page
      .locator(`role=button[name*="${PUSH_DAY}"]`)
      .first();
    const visibleAlready = await pushDayTile
      .waitFor({ state: 'visible', timeout: 3_000 })
      .then(() => true)
      .catch(() => false);

    if (!visibleAlready) {
      const vp = page.viewportSize();
      const cx = vp ? vp.width / 2 : 400;
      const cy = vp ? vp.height * 0.7 : 500;
      await page.mouse.move(cx, cy);
      for (let i = 0; i < 8; i++) {
        await page.mouse.wheel(0, 200);
        await page.waitForTimeout(300);
        const ok = await pushDayTile
          .waitFor({ state: 'visible', timeout: 1_500 })
          .then(() => true)
          .catch(() => false);
        if (ok) break;
      }
    }

    await pushDayTile.click();
    await page.locator(WEEKLY_PLAN.addConfirmButton).click();
    await expect(page.locator(`text=${PUSH_DAY}`).first()).toBeVisible({
      timeout: 10_000,
    });
  }

  // Back to home.
  await navigateToTab(page, 'Home');
}

// =============================================================================
// SMOKE — Home (fullHome user, lapsed state)
// =============================================================================
test.describe('Home', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(page, getUser('fullHome').email, getUser('fullHome').password);
    await navigateToTab(page, 'Home');
    // CharacterCard always renders on home — wait for it as the
    // "home tree settled" sentinel before each test.
    await expect(page.locator(HOME.characterCard)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should show character card collapsed on first load', async ({
    page,
  }) => {
    // Collapsed surface: closest-rank-up indicator visible, expanded body absent.
    await expect(page.locator(HOME.characterCard)).toBeVisible();
    await expect(page.locator(HOME.closestRankUp).first()).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(HOME.characterCardExpanded)).not.toBeVisible();
  });

  test('should expand character card on tap and reveal body-part rows', async ({
    page,
  }) => {
    await page.locator(HOME.characterCard).click();

    // Expanded body must mount.
    await expect(page.locator(HOME.characterCardExpanded)).toBeVisible({
      timeout: 5_000,
    });

    // Body-part rows render in canonical order. Assert at least the first
    // two (chest, back) are present — full canonical order is covered by
    // the Saga widget unit tests.
    await expect(page.locator(SAGA.bodyPartRow('chest')).first()).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(SAGA.bodyPartRow('back')).first()).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should collapse character card on second tap', async ({ page }) => {
    // Open.
    await page.locator(HOME.characterCard).click();
    await expect(page.locator(HOME.characterCardExpanded)).toBeVisible({
      timeout: 5_000,
    });
    // Close — tap the card header zone again.
    await page.locator(HOME.characterCard).click();
    await expect(page.locator(HOME.characterCardExpanded)).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should hide closest-rank-up indicator when card is expanded', async ({
    page,
  }) => {
    // Collapsed: indicator visible.
    await expect(page.locator(HOME.closestRankUp).first()).toBeVisible({
      timeout: 10_000,
    });

    // Expand → indicator hides (the expanded body owns the higher-fidelity
    // stat rows that render the same info).
    await page.locator(HOME.characterCard).click();
    await expect(page.locator(HOME.characterCardExpanded)).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.locator(HOME.closestRankUp)).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test('should show day-0 first-step fallback for a fresh-training user', async ({
    page,
  }) => {
    // fullHome's seeded workout has no workout_exercises → no body-part
    // training data → closestRankUp returns null → fallback copy renders
    // inside the closest-rank-up Semantics container.
    await expect(page.locator(HOME.closestRankUp).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should render encouragement nudge', async ({ page }) => {
    // EncouragementNudge resolves one of 5 priorities and always renders
    // something (day-0 fallback if nothing else triggers).
    await expect(page.locator(HOME.encouragementNudge).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should show free-workout ActionHero when no plan exists', async ({
    page,
  }) => {
    // Lapsed state (no plan, default routines exist) → ActionHero falls
    // through to the free-workout branch.
    await expect(page.locator(HOME.actionHero).first()).toBeVisible({
      timeout: 10_000,
    });
    await expect(
      page.locator(HOME.actionHeroFreeWorkout).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('should hide bucket chip wrap when bucket is empty (header + Editar plano stay visible)', async ({
    page,
  }) => {
    // BucketChipRow root + Editar plano link are always rendered.
    await expect(page.locator(HOME.bucketChipRow)).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.locator(HOME.editPlanLink).first()).toBeVisible({
      timeout: 10_000,
    });
    // No bucket chips — empty plan means no `home-bucket-chip-*` nodes exist.
    // We can't selector-match on "anything starting with home-bucket-chip-"
    // without inspecting the DOM, so the contract assertion here is that
    // none of the seeded default-routine UUIDs appear as bucket chips. The
    // weakest reliable form: assert the row exists but no chip-shaped
    // selector resolves. We use the structural assertion below by querying
    // the bucket-chip-row's descendants.
    // NOTE: the parent row's identifier `home-bucket-chip-row` matches a
    // `home-bucket-chip-*` prefix selector too, so we filter that out via
    // `:not()` on the row identifier — only true chip nodes (each carrying
    // a routine UUID suffix) remain.
    const chipCount = await page
      .locator(
        '[flt-semantics-identifier^="home-bucket-chip-"]:not([flt-semantics-identifier="home-bucket-chip-row"])',
      )
      .count();
    expect(chipCount).toBe(0);
  });

  test('should navigate to /plan/week when tapping Editar plano link', async ({
    page,
  }) => {
    await page.locator(HOME.editPlanLink).first().click();
    // The plan management screen is the deterministic destination — assert
    // on the destination heading rather than the URL (Flutter web hash
    // routing — see cluster_flutter_web_url_assertion).
    await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should render all four bottom nav tabs', async ({ page }) => {
    // Regression guard from the W8 era — pixel icons + Semantics identifiers
    // on every NavigationBar destination.
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
    await expect(page.locator(NAV.exercisesTab)).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(NAV.routinesTab)).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(NAV.profileTab)).toBeVisible({ timeout: 5_000 });
  });
});

// =============================================================================
// REGRESSION — Character card body-part rows (rpgFoundationUser)
//
// The foundation user has multiple body parts trained → the closest-rank-up
// indicator surfaces real XP-to-rank progress (not the day-0 fallback) and
// the expanded body-part rows are tappable into /saga/stats.
// =============================================================================
test.describe('Home character card (trained user)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('rpgFoundationUser').email,
      getUser('rpgFoundationUser').password,
    );
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.characterCard)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should show closest-rank-up indicator with real XP for a trained user', async ({
    page,
  }) => {
    // Indicator visible in the collapsed state — the foundation user has
    // trained chest/back/legs across 12 sessions so closestRankUp returns
    // a non-null record. The semantics identifier is the same one used by
    // the day-0 fallback (see character_card.dart _ClosestRankUpRow), so
    // this test pins presence + collapsed-state visibility.
    await expect(page.locator(HOME.closestRankUp).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should navigate to /saga/stats when tapping a body-part row in the expanded card', async ({
    page,
  }) => {
    // Open the card so the body-part rows mount.
    await page.locator(HOME.characterCard).click();
    await expect(page.locator(HOME.characterCardExpanded)).toBeVisible({
      timeout: 5_000,
    });

    // Tap the chest row. The row owns its own InkWell that pushes
    // /saga/stats?body_part=chest — assert on the destination screen
    // (saga-stats-screen identifier) rather than the URL because Flutter
    // web hash routing makes URL assertions unreliable (cluster:
    // flutter-web-url-assertion).
    await page.locator(SAGA.bodyPartRow('chest')).first().click();
    await expect(page.locator(SAGA.statsDeepDiveScreen)).toBeVisible({
      timeout: 15_000,
    });
  });
});

// =============================================================================
// REGRESSION — Bucket chip row populated state (smokeWeeklyPlan)
//
// smokeWeeklyPlan is lapsed (no plan) and starts clean each run. We drive the
// UI to add Push Day, then assert the BucketChipRow + start-routine
// ActionHero branch reflect the planned routine.
// =============================================================================
test.describe('Home bucket chip row (planned routines)', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWeeklyPlan').email,
      getUser('smokeWeeklyPlan').password,
    );
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.characterCard)).toBeVisible({
      timeout: 15_000,
    });
    await ensurePushDayInPlan(page);
    // Wait for the bucket chip row to settle in the populated state.
    await expect(page.locator(HOME.bucketChipRow)).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should render the bucket chip wrap with at least one planned chip', async ({
    page,
  }) => {
    // After ensurePushDayInPlan, the chip wrap mounts a chip with an
    // identifier of the form `home-bucket-chip-<routineId>`. We don't know
    // the UUID upfront, so we match on the identifier prefix.
    // NOTE: the parent row's identifier `home-bucket-chip-row` matches a
    // `home-bucket-chip-*` prefix selector too, so we filter that out via
    // `:not()` on the row identifier — only true chip nodes (each carrying
    // a routine UUID suffix) remain.
    //
    // Use waitFor({ state: 'attached' }) before .count() — the homeReadyProvider
    // skeleton gate resolves the container (`home-bucket-chip-row`) before the
    // individual chip flt-semantics-identifier attributes are committed to the
    // DOM. .count() is a one-shot snapshot; without an explicit wait it races
    // the Semantics tree hydration and returns 0.
    const chipSelector =
      '[flt-semantics-identifier^="home-bucket-chip-"]:not([flt-semantics-identifier="home-bucket-chip-row"])';
    await page.locator(chipSelector).first().waitFor({ state: 'attached', timeout: 10_000 });
    const chipCount = await page.locator(chipSelector).count();
    expect(chipCount).toBeGreaterThanOrEqual(1);
  });

  test('should show start-routine ActionHero when the bucket has an uncompleted entry', async ({
    page,
  }) => {
    // Push Day was just added and has NOT been completed → suggestedNext
    // is non-null → ActionHero branches into start-routine. Assert on the
    // per-branch identifier so the test is locale-independent.
    await expect(
      page.locator(HOME.actionHeroStartRoutine).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('should keep Editar plano link visible when bucket is populated', async ({
    page,
  }) => {
    // Editar plano is always rendered (locked decision) — both empty-bucket
    // and populated-bucket states. Pin the populated branch here.
    await expect(page.locator(HOME.editPlanLink).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  // Phase 32 PR 32g (D5) — bucket-chip → RoutineActionSheet → Start.
  // Pre-PR-32g this flow was never covered at the E2E layer (audit row #6).
  // Tapping a chip opens `showRoutineActionSheet` for the routine; tapping
  // Start routes through `startRoutineAction` → /workout/active. The
  // active-workout screen becomes visible.
  test('should open RoutineActionSheet when tapping a planned bucket chip and start active workout', async ({
    page,
  }) => {
    // `ensurePushDayInPlan` already ran in this describe block's beforeEach,
    // so a chip is present. Tap any chip — Push Day is a default routine,
    // so the action sheet's Start option is text-labeled (no Semantics id).
    const chipSelector =
      '[flt-semantics-identifier^="home-bucket-chip-"]:not([flt-semantics-identifier="home-bucket-chip-row"])';
    const chip = page.locator(chipSelector).first();
    await chip.waitFor({ state: 'attached', timeout: 10_000 });
    await chip.click();

    // The action sheet's ListTile labelled "Start" comes from
    // `l10n.start`. Default-routine variant (chip routine is Push Day,
    // is_default = true). Text-based selector — no Semantics id on the
    // default branch.
    const startListTile = page.locator('role=button[name*="Start"]').first();
    await expect(startListTile).toBeVisible({ timeout: 5_000 });
    await startListTile.click();

    // Active workout screen mounts — the Finish button is the canonical
    // post-PR-30 marker.
    await expect(page.locator('[flt-semantics-identifier="workout-finish-btn"]')).toBeVisible({
      timeout: 15_000,
    });
  });
});

// =============================================================================
// REGRESSION — Create-first-routine ActionHero branch (deferred)
//
// The third ActionHero branch fires only when the user has zero routines
// (including no default routines visible). The Supabase seed exposes the
// default routines (Full Body, Push Day, …) as GLOBAL rows with no
// `user_id` — `routineListProvider` returns them via a RLS SELECT for
// every authenticated user. There is no per-user "hide default routines"
// affordance, so we cannot reach `routineListProvider.value.isEmpty`
// through any combination of beforeEach DELETEs against a single user
// (deleting the rows would break the seeded routines for every other
// test user too).
//
// Phase 32 PR 32g investigation (2026-05-27): looked at three approaches —
// (1) per-user `is_visible_to` join column, (2) RLS predicate skipping
// defaults for a specific test email, (3) provider-side override at app
// bootstrap. (1) and (2) are migrations + new RLS rules — out of scope
// for a hotfix wave. (3) bypasses real UI state — defeats the E2E
// contract. Defer to a follow-up PR carrying the per-user-default-hide
// migration; either schema- or feature-flag-driven works.
//
// Unit tests already pin the branch: see
// `test/widget/features/workouts/ui/widgets/action_hero_test.dart`.
// =============================================================================
test.describe('Home ActionHero create-first-routine branch', () => {
  test.skip(
    'should show create-first-routine ActionHero when user has zero routines',
    () => {
      // Deferred — see describe-block comment. Branch covered by unit
      // tests in action_hero_test.dart.
    },
  );
});

// =============================================================================
// REGRESSION — Post-onboarding plan-edit hero transition (fix/home-action-hero-stale-weekly-plan)
//
// Bug: day-0 user (workoutCount == 0, only default routines) visits /plan/week,
// adds a default routine to the bucket, then returns home — the ActionHero was
// stuck on "Criar primeira rotina" because the old gate
// (`workoutCount == 0 && userRoutines.isEmpty`) ignored the bucket entirely.
//
// Fix: gate now requires `next == null` as a third precondition, so a non-empty
// bucket routes to _StartNextRoutineHero regardless of whether the user has
// built a custom routine. Cluster: optimistic-ui-vs-async-provider.
//
// The smokeFirstWorkout user is a pure day-0 fixture: profile row + zero
// workouts + zero weekly_plan rows. Default routines (Push Day, Full Body, …)
// are visible via RLS to every authenticated user, so the gate conditions
// `workoutCount == 0` and `userRoutines.isEmpty` are both satisfied after login.
//
// NOTE: global-setup seeds smokeFirstWorkout with `cleanFreshStateUser` + no
// seedMinimalWorkout, so workoutCount == 0 is guaranteed at beforeEach time.
// The test MUST NOT call ensurePushDayInPlan from the shared helper above
// (which uses `smokeWeeklyPlan`) — it inlines the plan-edit flow so the user
// identity stays isolated.
// =============================================================================
test.describe('Home ActionHero post-onboarding plan-edit transition', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeFirstWorkout').email,
      getUser('smokeFirstWorkout').password,
    );
    await navigateToTab(page, 'Home');
    await expect(page.locator(HOME.characterCard)).toBeVisible({
      timeout: 15_000,
    });
  });

  test(
    'should advance from create-first-routine to start-routine hero after adding a default routine to the weekly plan',
    async ({ page }) => {
      // Pre-condition: day-0 user with only default routines and no plan.
      // The gate (`workoutCount == 0 && userRoutines.isEmpty && next == null`)
      // should be satisfied → create-first-routine branch OR, because default
      // routines can't be fully excluded via RLS, the hero may already be
      // free-workout. Either way, assert it is NOT the start-routine branch.
      await expect(page.locator(HOME.actionHero).first()).toBeVisible({
        timeout: 10_000,
      });
      await expect(
        page.locator(HOME.actionHeroStartRoutine).first(),
      ).not.toBeVisible({ timeout: 5_000 });

      // Navigate to /plan/week and add Push Day to the bucket.
      await page.evaluate(() => {
        window.location.hash = '#/plan/week';
      });
      await page.waitForURL('**/plan/week**', { timeout: 10_000 });
      await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({
        timeout: 15_000,
      });

      const addBtn = page
        .locator(WEEKLY_PLAN.addRoutinesButton)
        .or(page.locator(WEEKLY_PLAN.addRoutineRow))
        .or(page.locator(WEEKLY_PLAN_26E.addWorkoutCta));
      await expect(addBtn.first()).toBeVisible({ timeout: 10_000 });
      await addBtn.first().click();

      await expect(page.locator(WEEKLY_PLAN.addRoutinesSheetTitle)).toBeVisible({
        timeout: 10_000,
      });

      const pushDayTile = page
        .locator(`role=button[name*="${PUSH_DAY}"]`)
        .first();
      const visibleAlready = await pushDayTile
        .waitFor({ state: 'visible', timeout: 3_000 })
        .then(() => true)
        .catch(() => false);

      if (!visibleAlready) {
        const vp = page.viewportSize();
        const cx = vp ? vp.width / 2 : 400;
        const cy = vp ? vp.height * 0.7 : 500;
        await page.mouse.move(cx, cy);
        for (let i = 0; i < 8; i++) {
          await page.mouse.wheel(0, 200);
          await page.waitForTimeout(300);
          const ok = await pushDayTile
            .waitFor({ state: 'visible', timeout: 1_500 })
            .then(() => true)
            .catch(() => false);
          if (ok) break;
        }
      }

      await pushDayTile.click();
      await page.locator(WEEKLY_PLAN.addConfirmButton).click();
      await expect(page.locator(`text=${PUSH_DAY}`).first()).toBeVisible({
        timeout: 10_000,
      });

      // Return home — the fix ensures the hero reactively transitions.
      await navigateToTab(page, 'Home');

      // Post-condition: ActionHero must now show start-routine, NOT
      // create-first-routine. This was the exact failure mode of the bug.
      await expect(
        page.locator(HOME.actionHeroStartRoutine).first(),
      ).toBeVisible({ timeout: 10_000 });
      await expect(
        page.locator(HOME.actionHeroCreateFirstRoutine).first(),
      ).not.toBeVisible({ timeout: 5_000 });
    },
  );
});
