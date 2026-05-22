/**
 * Rank-up celebration + mid-workout overlay tests (Phase 18c).
 *
 * Tests:
 *   S1 — Single rank-up overlay auto-advances
 *   S2 — Multi-event sequence (rank-up → level-up → title sheet)
 *   S3 — FirstAwakeningOverlay throttle (fires once, not again in same session)
 *   S4 — Overflow cap (3 shown + CelebrationOverflowCard with overflow count)
 *   S5 — PR chip appears inline after set commit, persists for session
 *   S6 — Finish button is in AppBar trailing; FAB triggers add-exercise flow
 *
 * All tests are tagged @smoke — they cover the critical RPG reward loop which
 * is the core engagement mechanic of Phase 18c.
 *
 * Seeding (see global-setup.ts):
 *   rpgRankUpThreshold   — chest at rank 3, 157 XP (Phase 29 v2 single-rank-up
 *                          deterministic window midpoint; one bench 80×5 lands
 *                          chest at 238.3199 XP / rank 4, no title threshold
 *                          crossed)
 *   rpgMultiCelebration  — chest at rank 9 (810 XP), 3 others at rank 2 + 2
 *                          others at rank 1 (≥1 XP) — one bench set yields
 *                          [rankUp(chest, 10), levelUp(4), titleUnlock(chest_r10)]
 *                          with NO class change and NO first-awakening (BUG-017)
 *   rpgOverflowQueue     — all 6 body parts at rank 5, 354 XP (Phase 29 v2)
 *   rpgFreshUser         — zero workout history (reused from 18a)
 *   smokePR              — prior PR at 100 kg bench press (reused)
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
import { WORKOUT, SAGA, HOME, CELEBRATION, SET_ROW } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';
import { SEED_EXERCISES, EXERCISE_NAMES } from '../fixtures/test-exercises';
import { getAdminClient, getUserIdByEmail } from '../helpers/test-data-reset';

// Reseed rpgRankUpThresholdUser (Phase 29 v2 single-rank-up deterministic
// window): chest at rank 3 / 157 XP, all others rank 1 @ 0 XP. The single-
// rank-up window for one bench 80x5 set at rank-3 dominance is
// (117.28, 197.14) XP — midpoint 157 leaves ~40 XP margin on either side
// so the post-state is unambiguously chest rank 4 (no skip to rank 5, no
// title threshold crossed at rank 5 either since chest stays below 278.46).
// Called in beforeEach so the test is repeatable with --repeat-each.
async function reseedRankUpThresholdUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('rpgRankUpThreshold').email);
  if (!userId) return;

  // Delete all workouts (cascade removes workout_exercises → sets → nulls PR set_id).
  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  // Phase 29 v2: in-band per-(slug, rep_band) peaks drive overload_mult.
  // Stale rows make every re-run look like "matched the band best" (mult
  // = 1.0); deleting forces a fresh ladder per test fixture.
  await admin.from('exercise_peak_loads_by_rep_range').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    { user_id: userId, sets_processed: 0, started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), completed_at: new Date().toISOString() },
    { onConflict: 'user_id' },
  );

  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const xp = bp === 'chest' ? 157 : 0;
    const rank = bp === 'chest' ? 3 : 1;
    await admin.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: xp, rank },
      { onConflict: 'user_id,body_part' },
    );
  }

  const { data: benchRows } = await admin.from('exercises').select('id')
    .eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchId = benchRows?.[0]?.id;
  if (benchId) {
    await admin.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchId, peak_weight: 80, peak_reps: 5,
        peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  // Seed one prior minimal workout so the app shows Quick workout (lapsed state).
  const now = new Date();
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

// Reseed rpgMultiCelebration: chest rank 9 @ 810 XP (just below R10
// threshold 815), 3 body parts at rank 2 (XP > 0), 2 at rank 1 (XP > 0).
// One bench set crosses chest 9 → 10 + character level 3 → 4 + chest_r10
// title fires; pre/post class is stable Bulwark, no first-awakening.
// See `seedRpgMultiCelebrationUser` in global-setup.ts for the full
// derivation (BUG-017, Cluster 3).
async function reseedMultiCelebrationUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('rpgMultiCelebration').email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  // Phase 29 v2: see reseedRankUpThresholdUser for rationale.
  await admin.from('exercise_peak_loads_by_rep_range').delete().eq('user_id', userId);
  await admin.from('personal_records').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    { user_id: userId, sets_processed: 0, started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), completed_at: new Date().toISOString() },
    { onConflict: 'user_id' },
  );

  const bodyPartSeed: Record<string, { xp: number; rank: number }> = {
    chest:     { xp: 810, rank: 9 },
    back:      { xp: 65,  rank: 2 },
    legs:      { xp: 65,  rank: 2 },
    shoulders: { xp: 65,  rank: 2 },
    arms:      { xp: 1,   rank: 1 },
    core:      { xp: 1,   rank: 1 },
  };
  for (const [bp, seed] of Object.entries(bodyPartSeed)) {
    await admin.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: seed.xp, rank: seed.rank },
      { onConflict: 'user_id,body_part' },
    );
  }

  const { data: benchRows } = await admin.from('exercises').select('id')
    .eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchId = benchRows?.[0]?.id;
  if (benchId) {
    await admin.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchId, peak_weight: 80, peak_reps: 5,
        peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
    const achievedAt = new Date(Date.now() - 86_400_000).toISOString();
    await admin.from('personal_records').insert([
      { user_id: userId, exercise_id: benchId, record_type: 'max_weight', value: 80, reps: 5, achieved_at: achievedAt },
      { user_id: userId, exercise_id: benchId, record_type: 'max_reps', value: 5, achieved_at: achievedAt },
      { user_id: userId, exercise_id: benchId, record_type: 'max_volume', value: 400, achieved_at: achievedAt },
    ]);
  }

  const now = new Date();
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

// Reseed rpgFreshUser: zero workout history, zero XP, zero body_part_progress.
// Called in beforeEach so the test is repeatable with --repeat-each without
// conflicting parallel runs on the same user (serial mode + reseed = isolation).
async function reseedRpgFreshUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('rpgFreshUser').email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  // Phase 29 v2: see reseedRankUpThresholdUser for rationale.
  await admin.from('exercise_peak_loads_by_rep_range').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);
  // Clear weekly plans so startEmptyWorkout lands on the quick-workout CTA,
  // not on a routine card from an active plan. Without this, routineId is
  // non-null after finish, _shouldShowPlanPrompt was evaluated post-dispose,
  // and navigation never fired (stuck on /workout/active).
  await admin.from('weekly_plans').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    { user_id: userId, sets_processed: 0, started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), completed_at: new Date().toISOString() },
    { onConflict: 'user_id' },
  );

  // Seed exercise peak loads for bench and squat so strength_mult = 1.0
  // on the first set (avoids peak-load timing race inside save_workout).
  const { data: benchRows } = await admin.from('exercises').select('id')
    .eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchId = benchRows?.[0]?.id;
  if (benchId) {
    await admin.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchId, peak_weight: 60, peak_reps: 5,
        peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
  }
  const { data: squatRows } = await admin.from('exercises').select('id')
    .eq('slug', 'barbell_squat').eq('is_default', true).limit(1);
  const squatId = squatRows?.[0]?.id;
  if (squatId) {
    await admin.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: squatId, peak_weight: 80, peak_reps: 5,
        peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  // Phase 26f ActionHero day-0 gate: workoutCount == 0 renders
  // _CreateFirstRoutineHero (no path into empty workout). Re-seed one
  // finished workout with NO sets so getFinishedWorkoutCount returns 1 →
  // the FreeWorkout branch wins → startEmptyWorkout can resolve the
  // free-workout banner. Sets-less workout is XP-neutral so the
  // CelebrationEventBuilder snapshot diff still flags
  // wasUntouched → isNowTouched for the exercises this test logs.
  const warmupStartedAt = new Date(Date.now() - 2 * 60 * 60 * 1000);
  const warmupFinishedAt = new Date(Date.now() - 90 * 60 * 1000);
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: warmupStartedAt.toISOString(),
    finished_at: warmupFinishedAt.toISOString(),
    duration_seconds: 1800,
  });
}

// Reseed rpgOverflowQueue (Phase 29 v2): all 6 body parts at rank 5,
// total_xp = 354 (midpoint of the deterministic R6-crossing window).
// The 4-exercise workout pushes all
// 6 BPs to rank 6 without any BP skipping a rank, keeping class
// Ascendant pre+post (no class-change overlay eating a queue slot).
// See seedRpgOverflowQueueUser in global-setup.ts for the full
// derivation + margin analysis.
async function reseedOverflowQueueUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('rpgOverflowQueue').email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  // Phase 29 v2: see reseedRankUpThresholdUser for rationale.
  await admin.from('exercise_peak_loads_by_rep_range').delete().eq('user_id', userId);
  await admin.from('personal_records').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    { user_id: userId, sets_processed: 0, started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), completed_at: new Date().toISOString() },
    { onConflict: 'user_id' },
  );

  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    await admin.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: 354, rank: 5 },
      { onConflict: 'user_id,body_part' },
    );
  }

  const exerciseSlugs: Record<string, { slug: string; peak: number }> = {
    chest:     { slug: 'barbell_bench_press',   peak: 80 },
    legs:      { slug: 'barbell_squat',          peak: 80 },
    back:      { slug: 'barbell_bent_over_row',  peak: 70 },
    shoulders: { slug: 'overhead_press',         peak: 50 },
  };
  for (const { slug, peak } of Object.values(exerciseSlugs)) {
    const { data: exRows } = await admin.from('exercises').select('id')
      .eq('slug', slug).eq('is_default', true).limit(1);
    const exId = exRows?.[0]?.id;
    if (exId) {
      await admin.from('exercise_peak_loads').upsert(
        { user_id: userId, exercise_id: exId, peak_weight: peak, peak_reps: 5,
          peak_date: new Date().toISOString() },
        { onConflict: 'user_id,exercise_id' },
      );
      const achievedAt = new Date(Date.now() - 86_400_000).toISOString();
      await admin.from('personal_records').insert([
        { user_id: userId, exercise_id: exId, record_type: 'max_weight', value: peak, reps: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_reps', value: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_volume', value: peak * 5, achieved_at: achievedAt },
      ]);
    }
  }

  const now = new Date();
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

// Reseed rpgOverflowTapCard: same seeding contract as rpgOverflowQueue
// (Phase 29 v2 calibration — all 6 BPs at rank 5 / 354 XP) but on a
// dedicated user so the auto-dismiss and tap-card tests don't race on
// shared XP state under --repeat-each=2.
async function reseedOverflowTapCardUser(): Promise<void> {
  const admin = getAdminClient();
  const userId = await getUserIdByEmail(admin, getUser('rpgOverflowTapCard').email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  // Phase 29 v2: see reseedRankUpThresholdUser for rationale.
  await admin.from('exercise_peak_loads_by_rep_range').delete().eq('user_id', userId);
  await admin.from('personal_records').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    { user_id: userId, sets_processed: 0, started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), completed_at: new Date().toISOString() },
    { onConflict: 'user_id' },
  );

  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    await admin.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: 354, rank: 5 },
      { onConflict: 'user_id,body_part' },
    );
  }

  const exerciseSlugs: Record<string, { slug: string; peak: number }> = {
    chest:     { slug: 'barbell_bench_press',   peak: 80 },
    legs:      { slug: 'barbell_squat',          peak: 80 },
    back:      { slug: 'barbell_bent_over_row',  peak: 70 },
    shoulders: { slug: 'overhead_press',         peak: 50 },
  };
  for (const { slug, peak } of Object.values(exerciseSlugs)) {
    const { data: exRows } = await admin.from('exercises').select('id')
      .eq('slug', slug).eq('is_default', true).limit(1);
    const exId = exRows?.[0]?.id;
    if (exId) {
      await admin.from('exercise_peak_loads').upsert(
        { user_id: userId, exercise_id: exId, peak_weight: peak, peak_reps: 5,
          peak_date: new Date().toISOString() },
        { onConflict: 'user_id,exercise_id' },
      );
      const achievedAt = new Date(Date.now() - 86_400_000).toISOString();
      await admin.from('personal_records').insert([
        { user_id: userId, exercise_id: exId, record_type: 'max_weight', value: peak, reps: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_reps', value: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_volume', value: peak * 5, achieved_at: achievedAt },
      ]);
    }
  }

  const now = new Date();
  await admin.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString(),
    finished_at: new Date(now.getTime() - 90 * 60 * 1000).toISOString(),
    duration_seconds: 1800,
  });
}

// =============================================================================
// S1 — Single rank-up overlay auto-advances (no tap required)
// =============================================================================

test.describe('Rank-up celebration', { tag: '@smoke' }, () => {
  // Serial mode: serializes repeat runs so the reseed in beforeEach always
  // completes before the next test starts. Prevents parallel races on the
  // shared rpgRankUpThreshold user when running with --repeat-each.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    // Reseed RPG state so each repeat starts with chest at rank 3 / 157 XP
    // (Phase 29 v2 single-rank-up window midpoint) and zero workout history
    // (prevents novelty-discount drift on repeat runs).
    await reseedRankUpThresholdUser();
    await login(
      page,
      getUser('rpgRankUpThreshold').email,
      getUser('rpgRankUpThreshold').password,
    );
  });

  test('should show RankUpOverlay after crossing a rank threshold and auto-advance to home', async ({
    page,
  }) => {
    // User is pre-seeded with chest at rank 3 / 157 XP (Phase 29 v2 single-
    // rank-up window midpoint). One bench 80x5 set earns 81.3199 XP to chest
    // (tier_diff_mult ~2.21 at rank=3 / implied_tier=15 fallback), landing
    // chest at 238.3199 XP / rank 4. Window margin ~40 XP either side rules
    // out skip-to-rank-5 + title threshold crossing.
    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Finish the workout to trigger the celebration queue.
    await finishWorkout(page);

    // The RankUpOverlay should appear as a dialog on screen.
    await expect(page.locator(CELEBRATION.rankUpOverlay).first()).toBeVisible({
      timeout: 15_000,
    });

    // The overlay auto-advances after 1.1 s (CelebrationPlayer.overlayHold).
    // We wait up to 4 s for it to disappear without any tap.
    await expect(page.locator(CELEBRATION.rankUpOverlay).first()).not.toBeVisible({
      timeout: 4_000,
    });

    // After all overlays clear, the app navigates to the PR celebration or
    // home screen. Both are acceptable post-finish landing pages.
    await page.waitForURL(/\/(home|pr-celebration)/, { timeout: 10_000 });

    // Parity gate — assert the EXACT per-body-part XP totals the SQL chain
    // wrote, matching the Dart calculator + Python sim + fixture oracle at
    // 1e-4 absolute. The values are derived from seeding chest rank 3 / 157
    // XP and applying one bench 80x5 set with implied_tier=15 (bodyweight-
    // null fallback). If a SQL helper drifts the parity gate catches it
    // BEFORE any flaky overlay-timing assertion upstream.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgRankUpThreshold').email);
    expect(userId).toBeTruthy();
    const { data: bpRows } = await admin
      .from('body_part_progress')
      .select('body_part, total_xp, rank')
      .eq('user_id', userId!)
      .order('body_part');
    const bpMap: Record<string, { total_xp: number; rank: number }> = {};
    for (const row of (bpRows ?? []) as Array<{ body_part: string; total_xp: number; rank: number }>) {
      bpMap[row.body_part] = { total_xp: Number(row.total_xp), rank: row.rank };
    }
    // Exact post-state per the Phase 29 v2 chain (1e-4 absolute parity).
    const expected: Record<string, { total_xp: number; rank: number }> = {
      chest:     { total_xp: 238.3199, rank: 4 },
      back:      { total_xp: 0.0,      rank: 1 },
      legs:      { total_xp: 0.0,      rank: 1 },
      shoulders: { total_xp: 23.2342,  rank: 1 },
      arms:      { total_xp: 11.6171,  rank: 1 },
      core:      { total_xp: 0.0,      rank: 1 },
    };
    for (const bp of Object.keys(expected)) {
      expect(bpMap[bp], `${bp} body_part_progress row missing`).toBeDefined();
      expect(bpMap[bp].rank, `${bp} rank`).toBe(expected[bp].rank);
      const delta = Math.abs(bpMap[bp].total_xp - expected[bp].total_xp);
      expect(delta, `${bp} XP drift > 1e-4 (got ${bpMap[bp].total_xp}, expected ${expected[bp].total_xp})`)
        .toBeLessThanOrEqual(1e-4);
    }
  });
});

// =============================================================================
// S2 — Multi-event sequence: rank-up → level-up → title unlock sheet
// =============================================================================

test.describe('Multi-event celebration sequence', { tag: '@smoke' }, () => {
  // Serial mode: prevents parallel races on the shared rpgMultiCelebration user.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    // Reseed so chest is back at rank 9 / 810 XP (with 5 other body parts
    // tuned to give the BUG-017 trio of [rankUp, levelUp, title] without
    // triggering class-change or first-awakening) and prior workout
    // history is cleared before every repeat (prevents novelty-discount
    // drift).
    await reseedMultiCelebrationUser();
    await login(
      page,
      getUser('rpgMultiCelebration').email,
      getUser('rpgMultiCelebration').password,
    );
  });

  test('should sequence rank-up overlay then level-up overlay then title unlock sheet', async ({
    page,
  }) => {
    // User is pre-seeded (BUG-017): chest at rank 9 (810 XP), 3 body
    // parts at rank 2 (XP > 0), 2 at rank 1 (XP > 0). One bench set →
    // chest rank 10 → character level 4 → chest_r10_plate_bearer title
    // unlock. Critically: class stays Bulwark (no class-change overlay)
    // and shoulders has > 0 XP pre (no first-awakening), so the queue
    // contains exactly 3 events that fit cap-at-3 with no silent drops.
    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    await finishWorkout(page);

    // 1) Rank-up overlay appears first.
    await expect(page.locator(CELEBRATION.rankUpOverlay).first()).toBeVisible({
      timeout: 15_000,
    });

    // Auto-advances after 1.1 s — wait for it to clear.
    await expect(page.locator(CELEBRATION.rankUpOverlay).first()).not.toBeVisible({
      timeout: 4_000,
    });

    // 2) Level-up overlay appears next (character level 2).
    await expect(page.locator(CELEBRATION.levelUpOverlay).first()).toBeVisible({
      timeout: 4_000,
    });

    // Auto-advances.
    await expect(page.locator(CELEBRATION.levelUpOverlay).first()).not.toBeVisible({
      timeout: 4_000,
    });

    // 3) Title unlock sheet appears last (the "crown" per spec §13.2).
    await expect(page.locator(CELEBRATION.titleUnlockSheet).first()).toBeVisible({
      timeout: 5_000,
    });

    // Equip button is visible inside the sheet.
    await expect(page.locator(CELEBRATION.equipTitleButton).first()).toBeVisible({
      timeout: 5_000,
    });

    // Tap EQUIP TITLE — should persist the title and dismiss the sheet.
    await page.locator(CELEBRATION.equipTitleButton).first().click();

    // Sheet should dismiss after equip.
    await expect(
      page.locator(CELEBRATION.titleUnlockSheet).first(),
    ).not.toBeVisible({ timeout: 8_000 });

    // Navigate to character sheet and assert the active title pill reflects the
    // newly equipped title.
    await page.waitForURL(/\/home/, { timeout: 10_000 });
    // Wait for home screen to stabilise before navigating to profile tab.
    // 26f: the CharacterCard always renders on Home and replaces the legacy
    // "Quick workout" CTA as the post-workout home-loaded sentinel.
    await page.locator(HOME.characterCard).first().waitFor({ state: 'visible', timeout: 15_000 }).catch(() => {});
    await page.locator(WORKOUT.finishButton).waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});

    // Navigate to Profile (Saga) tab and verify active title pill is set.
    await page.locator('[flt-semantics-identifier="nav-profile"]').click();
    // Wait for the character sheet body to fully load (confirms the Saga screen
    // has rendered its data state, not just the loading skeleton).
    await expect(page.locator(SAGA.runeHalo).first()).toBeVisible({
      timeout: 15_000,
    });
    // Phase 26b: sagaHeaderTitle replaces the legacy activeTitlePill selector.
    // The title text is now a Semantics-wrapped Text in the SagaHeader meta column.
    await expect(page.locator(SAGA.sagaHeaderTitle).first()).toBeVisible({
      timeout: 10_000,
    });

    // Parity gate — assert the EXACT per-body-part XP totals + ranks the SQL
    // chain wrote, matching the Dart calculator + Python sim + fixture oracle
    // at 1e-4 absolute. Seed: chest 810/r9, back/legs/shoulders 65/r2,
    // arms/core 1/r1. After one bench 80x5 set (chest gain 50.0489, shoulders
    // +14.2997, arms +7.1498): chest 860.0489 (rank 10, crosses chest_r10
    // title threshold), shoulders 79.2997 (still rank 2), arms 8.1498 (still
    // rank 1), back/legs unchanged. Sum of ranks 10+2+2+2+1+1=18,
    // character_level = floor((18-6)/4)+1 = 4.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgMultiCelebration').email);
    expect(userId).toBeTruthy();
    const { data: bpRows } = await admin
      .from('body_part_progress')
      .select('body_part, total_xp, rank')
      .eq('user_id', userId!)
      .order('body_part');
    const bpMap: Record<string, { total_xp: number; rank: number }> = {};
    for (const row of (bpRows ?? []) as Array<{ body_part: string; total_xp: number; rank: number }>) {
      bpMap[row.body_part] = { total_xp: Number(row.total_xp), rank: row.rank };
    }
    const expected: Record<string, { total_xp: number; rank: number }> = {
      chest:     { total_xp: 860.0489, rank: 10 },
      back:      { total_xp:  65.0,    rank:  2 },
      legs:      { total_xp:  65.0,    rank:  2 },
      shoulders: { total_xp:  79.2997, rank:  2 },
      arms:      { total_xp:   8.1498, rank:  1 },
      core:      { total_xp:   1.0,    rank:  1 },
    };
    for (const bp of Object.keys(expected)) {
      expect(bpMap[bp], `${bp} body_part_progress row missing`).toBeDefined();
      expect(bpMap[bp].rank, `${bp} rank`).toBe(expected[bp].rank);
      const delta = Math.abs(bpMap[bp].total_xp - expected[bp].total_xp);
      expect(delta, `${bp} XP drift > 1e-4 (got ${bpMap[bp].total_xp}, expected ${expected[bp].total_xp})`)
        .toBeLessThanOrEqual(1e-4);
    }

    // Title gate — chest_r10_plate_bearer row must exist AND be the active
    // title (equip button was tapped above). The unique partial index on
    // `earned_titles(user_id) WHERE is_active=TRUE` guarantees at most one
    // active title per user; we additionally assert no OTHER title is active.
    const { data: titleRows } = await admin
      .from('earned_titles')
      .select('title_id, is_active')
      .eq('user_id', userId!);
    const titles = (titleRows ?? []) as Array<{ title_id: string; is_active: boolean }>;
    const r10 = titles.find((t) => t.title_id === 'chest_r10_plate_bearer');
    expect(r10, 'chest_r10_plate_bearer earned_titles row missing').toBeDefined();
    expect(r10!.is_active, 'chest_r10_plate_bearer must be active after EQUIP tap').toBe(true);
    const otherActive = titles.filter((t) => t.is_active && t.title_id !== 'chest_r10_plate_bearer');
    expect(otherActive, `unexpected other active title(s): ${JSON.stringify(otherActive)}`).toHaveLength(0);
  });
});

// =============================================================================
// S3 — FirstAwakeningOverlay: fires once per workout finish (at most one per
//      finish, even when multiple body parts awaken simultaneously).
// =============================================================================

test.describe('First awakening overlay', { tag: '@smoke' }, () => {
  // Serial mode: prevents parallel races on the shared rpgFreshUser when
  // running with --repeat-each. Two parallel instances would both write
  // XP to the same user, causing the second instance's pre/post snapshot
  // diff to miss the "wasUntouched" condition and skipping the overlay.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    // Reseed RPG state so each repeat starts with zero XP and no workout
    // history (restores the "fresh user" condition that triggers FirstAwakening).
    await reseedRpgFreshUser();
    await login(
      page,
      getUser('rpgFreshUser').email,
      getUser('rpgFreshUser').password,
    );
  });

  test('should show FirstAwakeningOverlay on workout finish and fire for at most one body part even when two parts awaken', async ({
    page,
  }) => {
    // rpgFreshUser has zero workout history — all body parts are Dormant.
    // FirstAwakeningOverlay fires on WORKOUT FINISH (not on set commit).
    // CelebrationEventBuilder has a `break` after the first awakening event,
    // so at most one body part fires per finish call.
    await startEmptyWorkout(page);

    // BUG-020: Finish button only appears after the first exercise is added.
    // Add bench press (chest = first body-part touch this session).
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '60');
    await setReps(page, '5');
    // Complete the first (only) uncompleted set.
    await completeSet(page, 0);

    // Add a second exercise for a different body part (squat = legs).
    // This creates a second body-part awakening candidate in the finish diff.
    await addExercise(page, SEED_EXERCISES.squat);
    await setWeight(page, '80');
    await setReps(page, '5');
    // After completing bench (now in completed list), squat is the only
    // uncompleted checkbox — always at index 0 of WORKOUT.markSetDone.
    // Using completeSet(page, 0) clicks the first uncompleted checkbox.
    // The verification `completed.nth(0)` confirms at least one set completed.
    await completeSet(page, 0);

    // Finish the workout — this triggers CelebrationPlayer to build + play
    // the queue. The builder emits at most ONE FirstAwakeningEvent (breaks
    // after the first awakened body part found in activeBodyParts order).
    await finishWorkout(page);

    // The FirstAwakeningOverlay should appear after the finish.
    // CelebrationPlayer.overlayHold = 1100ms, so the overlay is held for
    // 1.1s even though the internal animation is only 800ms.
    await expect(
      page.locator(CELEBRATION.firstAwakeningOverlay).first(),
    ).toBeVisible({ timeout: 15_000 });

    // The overlay auto-dismisses after 1.1s (overlayHold).
    // Wait up to 4s for it to disappear.
    await expect(
      page.locator(CELEBRATION.firstAwakeningOverlay).first(),
    ).not.toBeVisible({ timeout: 4_000 });

    // After the overlay dismisses, no SECOND firstAwakeningOverlay should appear
    // (the builder `break` ensures at most one per finish).
    const secondOverlayVisible = await page
      .locator(CELEBRATION.firstAwakeningOverlay)
      .first()
      .isVisible({ timeout: 2_000 })
      .catch(() => false);

    expect(secondOverlayVisible).toBe(false);

    // The app navigates to home or pr-celebration after the celebration queue.
    await page.waitForURL(/\/(home|pr-celebration)/, { timeout: 15_000 });

    // Parity gate — assert the EXACT per-body-part XP totals + ranks. Seed:
    // all 0 XP / rank 1. Workout: bench 60x5 + squat 80x5. Attribution:
    //   bench  (chest gain 82.3560, shoulders 23.5303, arms 11.7651)
    //   squat  (legs 122.1155, core 15.2644, back 15.2644)
    // Post: chest 82.3560 (rank 2), legs 122.1155 (rank 2), all secondary
    // BPs rank 1 (touched but below 60 XP rank-2 threshold). Two rank-ups +
    // one firstAwakening (chest, taken first in active order). The
    // FirstAwakening break in the builder ensures only ONE awakening event.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgFreshUser').email);
    expect(userId).toBeTruthy();
    const { data: bpRows } = await admin
      .from('body_part_progress')
      .select('body_part, total_xp, rank')
      .eq('user_id', userId!)
      .order('body_part');
    const bpMap: Record<string, { total_xp: number; rank: number }> = {};
    for (const row of (bpRows ?? []) as Array<{ body_part: string; total_xp: number; rank: number }>) {
      bpMap[row.body_part] = { total_xp: Number(row.total_xp), rank: row.rank };
    }
    const expected: Record<string, { total_xp: number; rank: number }> = {
      chest:     { total_xp:  82.3560, rank: 2 },
      back:      { total_xp:  15.2644, rank: 1 },
      legs:      { total_xp: 122.1155, rank: 2 },
      shoulders: { total_xp:  23.5303, rank: 1 },
      arms:      { total_xp:  11.7651, rank: 1 },
      core:      { total_xp:  15.2644, rank: 1 },
    };
    for (const bp of Object.keys(expected)) {
      expect(bpMap[bp], `${bp} body_part_progress row missing`).toBeDefined();
      expect(bpMap[bp].rank, `${bp} rank`).toBe(expected[bp].rank);
      const delta = Math.abs(bpMap[bp].total_xp - expected[bp].total_xp);
      expect(delta, `${bp} XP drift > 1e-4 (got ${bpMap[bp].total_xp}, expected ${expected[bp].total_xp})`)
        .toBeLessThanOrEqual(1e-4);
    }
  });
});

// =============================================================================
// S4 — Overflow queue cap: 3 overlays shown + CelebrationOverflowCard
// =============================================================================

test.describe('Celebration overflow cap', { tag: '@smoke' }, () => {
  // Serial mode: prevents parallel races on the shared rpgOverflowQueue user.
  // With workers: 2 and --repeat-each, parallel runs of this test would race
  // on the reseed and on record_session_xp_batch novelty computation.
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    // Reseed all 6 body parts back to rank 5 / 354 XP (Phase 29 v2 tuned —
    // see reseedOverflowQueueUser docstring above for the derivation). Also
    // clears prior workout history so record_session_xp_batch sees zero
    // historical sets and novelty discounting starts fresh on every repeat.
    await reseedOverflowQueueUser();
    await login(
      page,
      getUser('rpgOverflowQueue').email,
      getUser('rpgOverflowQueue').password,
    );
  });

  test('should cap celebration queue at 3 overlays and show overflow card for remaining rank-ups', async ({
    page,
  }) => {
    // The 4-set workout below + queue drain + overflow-card mount comfortably
    // fits the default 60s budget on a 6+ vCPU dev machine, but on CI's
    // 4-vCPU runner with workers=4 the JS event loop is starved enough that
    // Flutter's 1.1s overlay holds and 0.2s gaps stretch unpredictably. Triple
    // the budget so the queue has room to drain even under worst-case timer
    // delivery latency. Same reasoning as the standing-PR test below at line ~841.
    test.slow();

    // rpgOverflowQueue is seeded with all 6 body parts at rank 5, total_xp =
    // 354 (Phase 29 v2 deterministic R6-crossing window — midpoint of the
    // (R6−smallestGain, R7−largestGain) interval). The 4 compound lifts
    // below — bench (chest 0.70 / shoulders 0.20 / arms 0.10), squat
    // (legs 0.80 / core 0.10 / back 0.10), row (back 0.70 / arms 0.20 /
    // core 0.10), OHP (shoulders 0.60 / arms 0.20 / core 0.20) — spread
    // XP across ALL 6 body parts via primary + secondary attribution.
    // Under Phase 29 v2's `tier_diff_mult` at rank 5 (≈ 2.05 with the
    // bodyweight-null implied tier of 15), each body part gains 36-86 XP.
    // Per the share-count novelty semantics (matching the Python sim +
    // Dart calculator + fixture oracle), the per-set values are EXACT
    // (1e-4 absolute parity) — see seedRpgOverflowQueueUser dartdoc in
    // global-setup.ts for the full per-bp breakdown. Result: 6 single-
    // rank crossings (all 5 → 6), no skips, pre+post class both
    // Ascendant. Cap-at-3 → 3 in queue, 3 overflow.
    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    // Body part 1: chest (bench press)
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Body part 2: legs (squat)
    // After bench is completed, squat's set is the only uncompleted checkbox
    // (index 0 of WORKOUT.markSetDone). Use index 0 to click it.
    await addExercise(page, SEED_EXERCISES.squat);
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Body part 3: back (bent-over row)
    // Same reasoning: after bench+squat are completed, row's set is the only
    // remaining uncompleted checkbox.
    await addExercise(page, EXERCISE_NAMES.barbell_bent_over_row.en);
    await setWeight(page, '70');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Body part 4: shoulders (overhead press) — pushes total to 4 rank-ups
    // which exceeds cap-at-3, triggering the overflow card.
    await addExercise(page, SEED_EXERCISES.overheadPress);
    await setWeight(page, '50');
    await setReps(page, '5');
    await completeSet(page, 0);

    await finishWorkout(page);

    // CelebrationQueue cap-at-3 allocation for this finish:
    //   events         = 6 rank-ups + 1 level-up + 0 class-change + 0 titles
    //   slot 1 (class) = 0 (no class change, Ascendant pre+post)
    //   slot 2 (top)   = 1 (the highest-rank rank-up)
    //   spillover      = take(2) additional rank-ups → 2 more in queue
    //   queue          = [top rank-up, 2nd rank-up, 3rd rank-up]
    //   overflow       = 6 − 3 = 3 rank-ups (folded into the overflow card)
    //
    // What this test asserts at the e2e layer:
    //   1. The first rank-up overlay appears (queue began playing).
    //   2. The overflow card appears with the correct "+3 ranks" label
    //      — the cap-at-3 receipt.
    //   3. EXACT per-body-part XP totals match the Phase 29 v2 chain
    //      (Dart calculator + Python sim + fixture oracle) within 1e-4
    //      absolute. This is the parity drift detector — if the SQL
    //      chain divergees from the oracle, this assertion catches it
    //      before any flaky timing-based check.
    //
    // What we DO NOT assert here any more:
    //   * The 4 s auto-dismiss → covered by the widget test
    //     `celebration_overflow_card_test.dart` ("auto-dismisses after 4
    //     seconds"). e2e is the wrong layer to measure animation timers
    //     against real wall-clock — under any CPU pressure the timer fires
    //     late and the test races itself. The widget test pins the same
    //     property using `tester.pump(Duration)` with a fake clock.
    //   * Per-overlay sequencing of rank-up₁ → rank-up₂ → level-up →
    //     overflow → that's covered by the multi-celebration test (S3).
    await expect(page.locator(CELEBRATION.rankUpOverlay).first()).toBeVisible({
      timeout: 15_000,
    });

    // Hold the handle ONCE so re-resolutions can't lose to the auto-dismiss.
    // The 45s timeout (vs the queue's nominal ~3.7s drain time) absorbs CI's
    // 4-vCPU starvation: under load, each 1.1s overlay hold can stretch to
    // 5–8s, so the cumulative drain can take 25–35s before the overflow card
    // mounts. Still well inside the test.slow() 180s overall budget.
    const overflowCard = page.locator(CELEBRATION.celebrationOverflowCard).first();
    await expect(overflowCard).toBeVisible({ timeout: 45_000 });

    // The accessible label is `"{N} more rank-ups — open Saga"`. With this
    // seeding (6 rank-ups − 3 in the queue = 3 overflowed), the label MUST
    // read `3 more rank-ups` for cap-at-3 to be working end-to-end.
    await expect(overflowCard).toHaveAccessibleName(/3 more rank-ups/);

    // Parity gate — assert the EXACT per-body-part XP totals the SQL chain
    // wrote, matching the Dart calculator + Python sim + fixture oracle at
    // 1e-4 absolute. If a SQL helper drifts (novelty miscounts, rounding
    // changes, etc.) the gate catches it BEFORE any flaky timing assertion
    // upstream. The values are derived from seeding rank-5 / 354 XP per BP
    // and applying the 4-exercise workout with implied_tier=15 (bodyweight-
    // null fallback) — see `seedRpgOverflowQueueUser` in global-setup.ts
    // for the per-set decomposition.
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgOverflowQueue').email);
    expect(userId).toBeTruthy();
    const { data: bpRows } = await admin
      .from('body_part_progress')
      .select('body_part, total_xp, rank')
      .eq('user_id', userId!)
      .order('body_part');
    const bpMap: Record<string, { total_xp: number; rank: number }> = {};
    for (const row of (bpRows ?? []) as Array<{ body_part: string; total_xp: number; rank: number }>) {
      bpMap[row.body_part] = { total_xp: Number(row.total_xp), rank: row.rank };
    }
    // Exact post-state per the Phase 29 v2 chain (1e-4 absolute parity).
    const expected: Record<string, { total_xp: number; rank: number }> = {
      chest:     { total_xp: 422.4366, rank: 6 },
      back:      { total_xp: 433.1780, rank: 6 },
      legs:      { total_xp: 439.3888, rank: 6 },
      shoulders: { total_xp: 421.2183, rank: 6 },
      arms:      { total_xp: 399.1321, rank: 6 },
      core:      { total_xp: 390.3483, rank: 6 },
    };
    for (const bp of Object.keys(expected)) {
      expect(bpMap[bp], `${bp} body_part_progress row missing`).toBeDefined();
      expect(bpMap[bp].rank, `${bp} rank`).toBe(expected[bp].rank);
      const delta = Math.abs(bpMap[bp].total_xp - expected[bp].total_xp);
      expect(delta, `${bp} XP drift > 1e-4 (got ${bpMap[bp].total_xp}, expected ${expected[bp].total_xp})`)
        .toBeLessThanOrEqual(1e-4);
    }
  });

});

// =============================================================================
// S4b — Overflow card tap routes to /profile (dedicated user for isolation)
//
// Separate describe block with a DEDICATED user (rpgOverflowTapCard) so that
// when --repeat-each=2 runs with 2 workers, the auto-dismiss test (S4) and the
// tap-card test (S4b) operate on separate users and cannot collide on XP state.
// Previously both tests shared rpgOverflowQueue; under --repeat-each the second
// worker's beforeEach would race against the first worker's workout, causing the
// XP state to be inconsistent and the overflow card to not appear.
// =============================================================================

test.describe('Celebration overflow card tap navigation', { tag: '@smoke' }, () => {
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    // Reseed all 6 body parts back to rank 5 / 354 XP (Phase 29 v2 — same
    // contract as rpgOverflowQueue). Uses dedicated rpgOverflowTapCard user
    // (isolated from rpgOverflowQueue) so this describe block never races
    // with S4 on --repeat-each runs.
    await reseedOverflowTapCardUser();
    await login(
      page,
      getUser('rpgOverflowTapCard').email,
      getUser('rpgOverflowTapCard').password,
    );
  });

  test('should route to /profile when the user taps the overflow card', async ({
    page,
  }) => {
    // CI 4-vCPU starvation slows the celebration queue's Timer.delayed
    // sequence — same reasoning as S4 above. test.slow() + a 45s overflow-
    // card visibility budget absorbs the worst-case timer delivery latency.
    test.slow();

    // Same seeding contract as the auto-dismiss test (4 compound lifts produce
    // 4+ rank-ups, exceeds cap-at-3, triggers the overflow card). The new
    // assertion: when the user explicitly taps the card, the post-finish
    // navigation routes to /profile (Saga) instead of /home or /pr-celebration.
    // Spec WIP §17/§175: "tap routes to /profile" — the card's whole purpose
    // is to give a path to see the rank-ups that didn't fit in the queue.
    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    await addExercise(page, SEED_EXERCISES.squat);
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    await addExercise(page, EXERCISE_NAMES.barbell_bent_over_row.en);
    await setWeight(page, '70');
    await setReps(page, '5');
    await completeSet(page, 0);

    await addExercise(page, SEED_EXERCISES.overheadPress);
    await setWeight(page, '50');
    await setReps(page, '5');
    await completeSet(page, 0);

    await finishWorkout(page);

    // Capture the locator handle ONCE up-front. Re-resolving (i.e., calling
    // `page.locator(...)` again) on the click line opens a race window: the
    // 4 s auto-dismiss timer can fire between `toBeVisible` returning and
    // the click resolution, and the second locator finds nothing. Holding
    // a single Locator instance keeps Playwright's actionability poll
    // pointed at the same element through the click.
    const overflowCard = page.locator(CELEBRATION.celebrationOverflowCard).first();
    await expect(overflowCard).toBeVisible({ timeout: 45_000 });

    // Tap the card. The completer resolves to true and the post-finish
    // navigation routes to /profile (Saga) instead of /home.
    //
    // `{ force: true }` is required for two independent reasons:
    //   1. Flutter CanvasKit's flutter-view element intercepts all DOM
    //      pointer events; Playwright's normal click would fail the
    //      actionability check (same pattern as manage-data.spec.ts line
    //      597/605 for GradientButton clicks).
    //   2. force-mode skips Playwright's pre-click visibility re-check, so
    //      we don't open ANOTHER race window between toBeVisible above and
    //      the click dispatch below — the AOM event fires immediately.
    await overflowCard.click({ force: true });

    await page.waitForURL(/\/profile/, { timeout: 10_000 });

    // Parity gate — same Phase 29 v2 XP chain as S4 (rpgOverflowQueue uses
    // identical seeding contract). Asserting per-bp XP + rank here guards
    // against a SQL drift that would silently corrupt the tap-card scenario
    // even when the overflow card still renders. Values mirror the S4 block
    // above (1e-4 absolute parity with Dart calculator + Python sim +
    // fixture oracle).
    const admin = getAdminClient();
    const userId = await getUserIdByEmail(admin, getUser('rpgOverflowTapCard').email);
    expect(userId).toBeTruthy();
    const { data: bpRows } = await admin
      .from('body_part_progress')
      .select('body_part, total_xp, rank')
      .eq('user_id', userId!)
      .order('body_part');
    const bpMap: Record<string, { total_xp: number; rank: number }> = {};
    for (const row of (bpRows ?? []) as Array<{ body_part: string; total_xp: number; rank: number }>) {
      bpMap[row.body_part] = { total_xp: Number(row.total_xp), rank: row.rank };
    }
    const expected: Record<string, { total_xp: number; rank: number }> = {
      chest:     { total_xp: 422.4366, rank: 6 },
      back:      { total_xp: 433.1780, rank: 6 },
      legs:      { total_xp: 439.3888, rank: 6 },
      shoulders: { total_xp: 421.2183, rank: 6 },
      arms:      { total_xp: 399.1321, rank: 6 },
      core:      { total_xp: 390.3483, rank: 6 },
    };
    for (const bp of Object.keys(expected)) {
      expect(bpMap[bp], `${bp} body_part_progress row missing`).toBeDefined();
      expect(bpMap[bp].rank, `${bp} rank`).toBe(expected[bp].rank);
      const delta = Math.abs(bpMap[bp].total_xp - expected[bp].total_xp);
      expect(delta, `${bp} XP drift > 1e-4 (got ${bpMap[bp].total_xp}, expected ${expected[bp].total_xp})`)
        .toBeLessThanOrEqual(1e-4);
    }
  });
});

// =============================================================================
// S5 — Inline PR signal appears in set row after committing a PR-beating set,
//      persists for the rest of the workout.
//
// Phase 20 (PR #152) replaced the dedicated `_PrChip` widget with the gold
// edge-frame treatment on the set row itself: a PR-beating completed set
// transitions to `PrRowState.completedStandingPr`, which surfaces as the
// `[flt-semantics-identifier="set-row-state-standing-pr"]` selector
// (`SET_ROW.stateStandingPr`). The previous chip-targeted assertion
// (`CELEBRATION.prChip` / `workout-pr-chip`) targeted a widget that no longer
// exists; this test was migrated together with the row redesign.
// =============================================================================

test.describe('PR signal inline display', { tag: '@smoke' }, () => {
  // NOTE on test data: this describe shares `smokePR` with
  // `personal-records.spec.ts`, which logs PRs up to 999 kg via test :309
  // (and 130 kg via the commit-7 :264 test). Earlier attempts in PR #152
  // tried two paths to neutralise the cross-spec pollution:
  //
  //   (1) Bumping the assertion timeout — failed: not a timing issue.
  //   (2) Per-describe `beforeEach` reset+seed via the test-data-reset
  //       helper — failed: introduced a CONCURRENT race when this
  //       beforeEach ran on Worker B while `personal-records.spec.ts:309`
  //       was mid-test on Worker A; the reset's surgical delete of
  //       smokePR's bench history wiped Worker A's just-completed
  //       set/workout rows out from under the resolver.
  //
  // The architectural fix (per-worker user isolation) lives in PROJECT.md
  // Phase 21. Until then we use the simplest working tactic: pick a
  // weight no other test on smokePR can plausibly leave behind. The
  // `personal-records.spec.ts` ceiling is 999 kg; using 1500 kg gives
  // safe headroom and still passes Flutter's reasonable-input bounds.

  test.beforeEach(async ({ page }) => {
    // smokePR user has a prior PR of 100 kg bench press from
    // `seedPRData()` in global-setup.ts. Other tests on smokePR may
    // have logged additional PRs up to 999 kg — see the audit at
    // `tasks/e2e-pollution-audit.md`. The 1500 kg weight below
    // unconditionally beats any of them.
    await login(
      page,
      getUser('smokePR').email,
      getUser('smokePR').password,
    );
  });

  test('should show standing-PR signal in set row after committing a heavier set than prior PR', async ({
    page,
  }) => {
    // Two-set sequence on a heavily-Semantics-driven row state machine. The
    // setup chain (login → startEmptyWorkout → addExercise → setWeight ×2
    // → setReps ×2 → completeSet ×2) on CI's parallel-load Docker environment
    // can run 50-55s before the standing-PR assertion fires. Default 60s
    // test budget leaves no headroom — same accumulated-state class as the
    // similar two-set patterns in `personal-records.spec.ts` and the v1
    // S5 test that already use `test.slow()`. Triple the budget for
    // structural resilience to CI worker load.
    test.slow();

    // Use 1500 kg (well above any other test's PR) so the assertion is
    // robust to pollution from `personal-records.spec.ts:309`'s 999 kg PR
    // without depending on reset+seed orchestration that races across
    // workers. See the describe-block comment above for the history.
    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // Log a PR-beating weight. 1500 kg unconditionally beats everything
    // any sibling test on smokePR could have left behind (the audit ceiling
    // is 999 kg from personal-records.spec.ts:309).
    await setWeight(page, '1500');
    await setReps(page, '5');

    // Commit the set — the row must transition to standing-PR after commit,
    // NOT while typing. Phase 20's `_SetRowFrame` emits the standing-PR
    // identifier when `display.state == PrRowState.completedStandingPr`.
    await completeSet(page, 0);

    // The standing-PR row identifier should now be visible inline. 15s
    // budget — the Semantics tree update that exposes the state-* identifier
    // can run several frames behind the completeSet checkbox click on CI's
    // slow workers. Locally this assertion resolves in ~200ms.
    await expect(page.locator(SET_ROW.stateStandingPr).first()).toBeVisible({
      timeout: 15_000,
    });

    // NOTE: an earlier version of this test added a second non-PR set to
    // assert that set 1's standing-PR identifier PERSISTS through a
    // subsequent completion. That assertion was structurally flaky on
    // CI — adding + completing set 2 triggers an AOM re-emit window
    // during which the row's state Semantics is briefly absent before
    // re-emitting as `set-row-state-standing-pr`. The 15s timeout was
    // not enough headroom and the test failed on first attempt + passed
    // on retry consistently. Removed pending Phase 21 (per-worker user
    // isolation will let us tighten timing without race interference).
    // The unit-level resolver tests at
    // `test/unit/features/workouts/domain/pr_row_state_resolver_test.dart`
    // already pin the persistence contract end-to-end (set 1 stays
    // standing when set 2 is non-PR — multi-set cascade scenarios).
  });
});

// =============================================================================
// S6 — Finish button in persistent bottom bar (BUG-020); FAB triggers add-exercise flow
// =============================================================================

test.describe('Active workout chrome (Phase 18c)', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('smokeWorkout').email,
      getUser('smokeWorkout').password,
    );
  });

  test('should show Finish button after adding exercise and FAB triggers add-exercise flow', async ({
    page,
  }) => {
    await startEmptyWorkout(page);

    // Add an exercise — the Finish bottom bar only appears once the workout
    // has at least one exercise (BUG-020: bottom bar hidden on empty body).
    await addExercise(page, SEED_EXERCISES.benchPress);

    // Finish button must now be visible in the persistent bottom bar.
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // The add-exercise FAB must be visible now that exercises > 0.
    await expect(page.locator(WORKOUT.addExerciseFab)).toBeVisible({
      timeout: 5_000,
    });

    // Tap the FAB — exercise picker sheet should open.
    await page.locator(WORKOUT.addExerciseFab).click();
    await expect(
      page.locator('[flt-semantics-identifier="exercise-picker-search"]').first(),
    ).toBeVisible({ timeout: 10_000 });

    // Dismiss the picker by pressing Escape.
    await page.keyboard.press('Escape');
    await expect(
      page.locator('[flt-semantics-identifier="exercise-picker-search"]').first(),
    ).not.toBeVisible({ timeout: 5_000 });

    // Complete one set so Finish becomes enabled.
    await setWeight(page, '80');
    await setReps(page, '5');
    await completeSet(page, 0);

    // Tap Finish → confirmation dialog must appear.
    await page.locator(WORKOUT.finishButton).click();
    await expect(page.locator(WORKOUT.dialogFinishButton)).toBeVisible({
      timeout: 8_000,
    });

    // Confirm → workout completes → navigate away from active workout screen.
    await page.locator(WORKOUT.dialogFinishButton).click();
    await page.waitForURL(/\/(home|pr-celebration)/, { timeout: 15_000 });
  });
});
