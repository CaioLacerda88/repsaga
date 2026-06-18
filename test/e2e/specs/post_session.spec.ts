/**
 * Post-session summary E2E (Phase 31 Pass 3).
 *
 * Asserts the S2 Mission Debrief section renders on the post-session
 * summary panel after the cinematic resolves. Behavior, not wiring:
 *   - the debrief section is visible
 *   - at least one lift row renders inside it
 *   - the segmented XP bar is visible (one or more BP segments)
 *   - the per-BP rank delta row for the trained body part is visible
 *
 * Reuses the rpgRankUpThreshold user (same as share_flow.spec.ts).
 * Lands on the summary panel via the skip button + skips the cinematic.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import {
  startEmptyWorkout,
  addExercise,
  setWeight,
  setReps,
  completeSet,
  finishWorkout,
} from '../helpers/workout';
import { WORKOUT, POST_SESSION, NAV } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES } from '../fixtures/test-exercises';
import {
  getAdminClient,
  getUserIdByEmail,
  seedPrForUser,
} from '../helpers/test-data-reset';

async function reseedDebriefUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(
    admin,
    getUser('rpgRankUpThreshold').email,
  );
  if (!userId) return;

  // Full RPG-state wipe + restore to the chest-rank-3 / 157-XP threshold
  // window. Mirrors `reseedRankUpThresholdUser` in
  // `rank-up-celebration.spec.ts` — the post_session describe runs ≥4
  // tests serially through the same user, and a workouts-only reseed left
  // body_part_progress / peak_loads / earned_titles mutated across tests
  // (test N's finished workout pushed chest past the rank-up threshold,
  // breaking test N+1's cinematic state). The serial-mode flake on
  // `:100` in PR 33c CI was the visible symptom; expanding the reseed
  // matches the proven isolation contract used by rank-up-celebration.
  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  await admin
    .from('exercise_peak_loads_by_rep_range')
    .delete()
    .eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  // Suppress the SagaIntroGate retro backfill — without this row, the
  // first post-login navigation triggers a backfill spinner that races
  // with the workout flow's first frame and amplifies cinematic timing
  // noise.
  await admin.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  // Phase 29 v2 deterministic single-rank-up window: chest at rank 3 /
  // 157 XP, all other body parts at rank 1 / 0 XP. The single-rank-up
  // window for one bench 80x5 set at rank-3 dominance is
  // (117.28, 197.14) XP — midpoint 157 leaves ~40 XP margin on either
  // side so the post-state is unambiguously chest rank 4 (no skip to
  // rank 5).
  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const xp = bp === 'chest' ? 157 : 0;
    const rank = bp === 'chest' ? 3 : 1;
    await admin.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: xp, rank },
      { onConflict: 'user_id,body_part' },
    );
  }

  // Peak load for bench (matches the rank-up describe's seed): keeps the
  // post-session overload_mult stable across test iterations.
  const { data: benchRows } = await admin
    .from('exercises')
    .select('id')
    .eq('slug', 'barbell_bench_press')
    .eq('is_default', true)
    .limit(1);
  const benchId = benchRows?.[0]?.id;
  if (benchId) {
    await admin.from('exercise_peak_loads').upsert(
      {
        user_id: userId,
        exercise_id: benchId,
        peak_weight: 80,
        peak_reps: 5,
        peak_date: new Date().toISOString(),
      },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  // Re-seed a minimal past workout so workoutCount > 0 after the delete.
  // Without this the ActionHero lands on _CreateFirstRoutineHero (0-workout
  // state) and startEmptyWorkout can't find home-action-hero-free-workout.
  // The warmup workout is intentionally finished 90 min ago and not part
  // of a weekly plan, so ActionHero resolves to _FreeWorkoutHero (no
  // suggested next — the rpgRankUpThreshold user has no user-built
  // routines).
  const now = new Date();
  const startedAt = new Date(now.getTime() - 2 * 60 * 60 * 1000);
  const finishedAt = new Date(now.getTime() - 90 * 60 * 1000);
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Debrief Warmup',
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    duration_seconds: 1800,
  });
}

test.describe('Post-session summary', { tag: '@smoke' }, () => {
  // Serial mode: prevents parallel races on the shared rpgRankUpThreshold
  // user.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await reseedDebriefUser();
    await login(
      page,
      getUser('rpgRankUpThreshold').email,
      getUser('rpgRankUpThreshold').password,
    );

    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    await page.waitForURL(/\/workout\/finish\//, { timeout: 10_000 });
    const skip = page.locator(POST_SESSION.skipBtn);
    if (await skip.isVisible().catch(() => false)) {
      await skip.click();
    }
    await expect(page.locator(POST_SESSION.summary)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('should render the Mission Debrief section after the cinematic ends', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
  });

  test('should render at least one lift row inside the debrief section', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(POST_SESSION.missionDebriefLiftRow).first(),
    ).toBeVisible();
  });

  test('should render at least one per-BP rank delta row in the debrief section', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(POST_SESSION.missionDebriefBpRow).first(),
    ).toBeVisible();
  });

  test('should render the segmented XP bar inside the debrief section', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.missionDebriefSection)).toBeVisible({
      timeout: 5_000,
    });
    await expect(
      page.locator(POST_SESSION.missionDebriefXpBar),
    ).toBeVisible();
  });

  // finding-041: CONTINUAR CTA navigates back to the home shell.
  test('should navigate to home screen when CONTINUAR is tapped on the summary panel', async ({
    page,
  }) => {
    await expect(page.locator(POST_SESSION.continueCta)).toBeVisible({
      timeout: 10_000,
    });
    await page.locator(POST_SESSION.continueCta).click();
    // Content-visibility assertion (not URL assertion) per cluster
    // `flutter-web-url-assertion`. The home bottom-nav tab is locale-
    // independent (flt-semantics-identifier, not aria-label text).
    await expect(page.locator(NAV.homeTab)).toBeVisible({ timeout: 15_000 });
  });

  // PR 32g leave-confirm E2E removed — cluster
  // `flutter-web-popscope-unreachable`. GoRouter's
  // `MultiEntriesBrowserHistory` consumes `popstate` BEFORE the
  // route's PopScope handler runs on Flutter web, so
  // `page.goBack()` cannot trigger the leave-confirm dialog. The
  // contract is exercised on Android (where the OS back button
  // routes through PopScope normally) and pinned by widget tests
  // at `test/widget/features/workouts/ui/post_session/`. Audit
  // entry in `docs/home-to-workout-flow-audit.md` §3.4 is closed
  // by the widget-test coverage; this stays an Android-only
  // contract on the E2E side.
});

// =============================================================================
// finding-042 — B3 PR cut renders when the finished workout contains a new PR.
//
// The post-session cinematic has three beats. Beat 3 (B3) is gated on whether
// the workout produced at least one personal record. This describe pins the
// B3 PR cut (`POST_SESSION.b3Pr`) for a PR-only workout (no rank-up event
// in the same session so the B3 PR surface is the sole Beat 3 variant).
//
// User: `smokePR` — seeded with a bench press PR at 100 kg. Logging 1500 kg
// unconditionally beats any prior PR regardless of cross-spec pollution from
// other smokePR tests (ceiling is 999 kg in `personal-records.spec.ts`).
//
// Strategy: do NOT skip the cinematic. Wait for B3 to appear directly.
// Beat 2 is the body-part tally cut (POST_SESSION.b2Tally); Beat 3 follows
// it automatically after the choreographer advances. The test uses a
// sufficiently long timeout (45 s) to cover the full cinematic playthrough.
// =============================================================================

// Reseed the smokePR user back to the canonical baseline (matches
// `reseedSmokePrUser` in personal-records.spec.ts):
//   - cleanFreshStateUser equivalent: workouts + RPG state cleared
//   - bench press 100 kg x 5 max_weight PR re-seeded via seedPrForUser
//
// Why this is required: on `--repeat-each > 1` the first run logs bench 1500 kg
// which writes `exercise_peak_loads.peak_weight = 1500` for this user. The
// second run logs the same 1500 kg → no new peak → no PR event → B3 PR cut
// never fires → 45s timeout. Wiping workouts is insufficient because
// `exercise_peak_loads`, `personal_records`, and the RPG XP chain
// (`xp_events`, `body_part_progress`, etc.) all survive workout deletion and
// gate PR detection in `record_session_xp_batch`. Mirrors the cascade-aware
// wipe used by the personal-records spec.
async function reseedSmokePrUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('smokePR').email);
  if (!userId) return;

  // PRs first — `personal_records.set_id` is ON DELETE SET NULL, so rows
  // survive workout deletion and would shadow the baseline if not cleared.
  await admin.from('personal_records').delete().eq('user_id', userId);
  // Workouts cascade-delete workout_exercises + sets (FK ON DELETE CASCADE in
  // migration 00001), so no need to wipe them individually.
  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('weekly_plans').delete().eq('user_id', userId);

  // RPG state — must be wiped or accumulated XP/peak loads break PR detection
  // on the next run.
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('user_xp').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  await admin
    .from('exercise_peak_loads_by_rep_range')
    .delete()
    .eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  // Mark backfill_progress completed so SagaIntroGate.runRetroBackfill is a
  // no-op on next login (matches personal-records reseed pattern).
  const nowIso = new Date().toISOString();
  await admin.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: nowIso,
      updated_at: nowIso,
      completed_at: nowIso,
    },
    { onConflict: 'user_id' },
  );

  // Re-seed the canonical bench press 100 kg x 5 PR (matches global-setup's
  // seedPRData). The 1500 kg set in the test below unconditionally beats this.
  await seedPrForUser(admin, userId, 'barbell_bench_press', 100, 5);
}

test.describe('Post-session B3 PR cut', { tag: '@smoke' }, () => {
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async () => {
    await reseedSmokePrUser();
  });

  test('should render the B3 PR cut when the finished workout contains a new personal record', async ({
    page,
  }) => {
    // smokePR has a bench PR at 100 kg. 1500 kg unconditionally beats it.
    await login(
      page,
      getUser('smokePR').email,
      getUser('smokePR').password,
    );

    await startEmptyWorkout(page);
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '1500');
    await setReps(page, '5');
    await completeSet(page, 0);
    await finishWorkout(page);

    await page.waitForURL(/\/workout\/finish\//, { timeout: 10_000 });

    // The cinematic plays B1 → B2 → B3. B3 PR cut is the assertion target.
    // Allow up to 45 s for the full choreography to reach Beat 3.
    // Behavior contract: the user sees the PR cut (not just "some post-session
    // element") — this distinguishes a PR-producing workout from a rank-up-only
    // workout where B3 would show the class-change or title cut instead.
    await expect(page.locator(POST_SESSION.b3Pr)).toBeVisible({
      timeout: 45_000,
    });
  });
});
