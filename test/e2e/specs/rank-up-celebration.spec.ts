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
 *   rpgRankUpThreshold   — chest at rank 4, 270 XP (~8 XP below R5 threshold)
 *   rpgMultiCelebration  — chest at rank 9 (810 XP), 3 others at rank 2 + 2
 *                          others at rank 1 (≥1 XP) — one bench set yields
 *                          [rankUp(chest, 10), levelUp(4), titleUnlock(chest_r10)]
 *                          with NO class change and NO first-awakening (BUG-017)
 *   rpgOverflowQueue     — all 6 body parts at rank 4, 270 XP
 *   rpgFreshUser         — zero workout history (reused from 18a)
 *   smokePR              — prior PR at 100 kg bench press (reused)
 */

import { test, expect } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
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
import { TEST_USERS } from '../fixtures/test-users';
import { SEED_EXERCISES, EXERCISE_NAMES } from '../fixtures/test-exercises';
import {
  getAdminClient,
  getUserIdByEmail,
  resetExerciseHistoryForUser,
  seedPrForUser,
} from '../helpers/test-data-reset';

// ---------------------------------------------------------------------------
// Admin Supabase client — used to reseed RPG state before each test repeat.
// Seeding in beforeEach (rather than relying solely on global-setup) ensures
// the test is repeatable with --repeat-each: each run starts with a clean
// XP slate, preventing novelty-discount drift from prior workout history.
// ---------------------------------------------------------------------------
function makeAdminClient() {
  const url = process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
  const serviceKey = process.env['SUPABASE_SERVICE_ROLE_KEY'] ??
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' +
    '.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0' +
    '.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function getUserId(email: string): Promise<string | null> {
  const admin = makeAdminClient();
  const { data } = await admin.auth.admin.listUsers();
  const user = data?.users?.find((u) => u.email === email);
  return user?.id ?? null;
}

// Reseed rpgRankUpThreshold: chest rank 2 @ 120 XP, all others rank 1 @ 0 XP.
// Called in beforeEach so the test is repeatable with --repeat-each.
async function reseedRankUpThresholdUser(): Promise<void> {
  const admin = makeAdminClient();
  const userId = await getUserId(TEST_USERS.rpgRankUpThreshold.email);
  if (!userId) return;

  // Delete all workouts (cascade removes workout_exercises → sets → nulls PR set_id).
  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);

  await admin.from('backfill_progress').upsert(
    { user_id: userId, sets_processed: 0, started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), completed_at: new Date().toISOString() },
    { onConflict: 'user_id' },
  );

  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const xp = bp === 'chest' ? 120 : 0;
    const rank = bp === 'chest' ? 2 : 1;
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
  const admin = makeAdminClient();
  const userId = await getUserId(TEST_USERS.rpgMultiCelebration.email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
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
  const admin = makeAdminClient();
  const userId = await getUserId(TEST_USERS.rpgFreshUser.email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
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
}

// Reseed rpgOverflowQueue: all 6 body parts rank 3 @ 196 XP.
// Seeding at 196 XP (2.6 XP below rank-4 threshold of ~198.6) instead of
// 190 XP ensures a single working set reliably crosses the boundary even
// after novelty discounting. The previous 190 XP seed (8.6 XP gap) was
// occasionally insufficient when XP attribution changed slightly between runs.
async function reseedOverflowQueueUser(): Promise<void> {
  const admin = makeAdminClient();
  const userId = await getUserId(TEST_USERS.rpgOverflowQueue.email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
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
      { user_id: userId, body_part: bp, total_xp: 196, rank: 3 },
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

// Reseed rpgOverflowTapCard: same seeding contract as rpgOverflowQueue but
// on a SEPARATE user. This prevents cross-worker state collisions when
// --repeat-each=2 runs the overflow auto-dismiss test and the overflow tap-card
// test on parallel workers — both workers shared rpgOverflowQueue previously,
// causing XP state races that prevented the overflow card from appearing.
async function reseedOverflowTapCardUser(): Promise<void> {
  const admin = makeAdminClient();
  const userId = await getUserId(TEST_USERS.rpgOverflowTapCard.email);
  if (!userId) return;

  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
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
      { user_id: userId, body_part: bp, total_xp: 196, rank: 3 },
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
    // Reseed RPG state so each repeat starts with chest at rank 2 / 120 XP
    // and zero workout history (prevents novelty-discount drift on repeat runs).
    await reseedRankUpThresholdUser();
    await login(
      page,
      TEST_USERS.rpgRankUpThreshold.email,
      TEST_USERS.rpgRankUpThreshold.password,
    );
  });

  test('should show RankUpOverlay after crossing a rank threshold and auto-advance to home', async ({
    page,
  }) => {
    // User is pre-seeded with chest at rank 4, 270 XP (8 XP below R5).
    // One working bench press set earns ~10-15 XP and crosses the boundary.
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
      TEST_USERS.rpgMultiCelebration.email,
      TEST_USERS.rpgMultiCelebration.password,
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
    await page.locator(HOME.quickWorkout).first().waitFor({ state: 'visible', timeout: 15_000 }).catch(() => {});
    await page.locator(WORKOUT.finishButton).waitFor({ state: 'hidden', timeout: 5_000 }).catch(() => {});

    // Navigate to Profile (Saga) tab and verify active title pill is set.
    await page.locator('[flt-semantics-identifier="nav-profile"]').click();
    // Wait for the character sheet body to fully load (confirms the Saga screen
    // has rendered its data state, not just the loading skeleton).
    await expect(page.locator(SAGA.runeHalo).first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.locator(SAGA.activeTitlePill).first()).toBeVisible({
      timeout: 10_000,
    });
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
      TEST_USERS.rpgFreshUser.email,
      TEST_USERS.rpgFreshUser.password,
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
    // Reseed all 6 body parts back to rank 3 / 196 XP and clear prior workout
    // history so record_session_xp_batch sees zero historical sets on every
    // repeat. 196 XP (2.6 XP below R4 threshold) ensures a single set reliably
    // crosses the boundary after novelty discounting.
    await reseedOverflowQueueUser();
    await login(
      page,
      TEST_USERS.rpgOverflowQueue.email,
      TEST_USERS.rpgOverflowQueue.password,
    );
  });

  test('should cap celebration queue at 3 overlays and show overflow card for remaining rank-ups', async ({
    page,
  }) => {
    // rpgOverflowQueue is seeded with all 6 body parts at rank 3 (196 XP each,
    // 2.6 XP below the rank-4 threshold of ~198.6 XP). We log 4 compound lifts
    // (bench, squat, row, OHP) which spread XP across all body parts via primary
    // + secondary attribution. Even after novelty discounting, a single working
    // set reliably pushes 5+ body parts over the rank-4 threshold, producing
    // 5 rank-ups + 1 level-up which exceeds cap-at-3 and triggers the overflow
    // card.
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

    // CelebrationQueue capacity for this finish:
    //   closersCount   = 1 (level-up, no titles at rank 4)
    //   rankUpCapacity = cap(3) − 1 = 2
    //   queue          = [rank-up₁, rank-up₂, level-up]
    //   overflow       = 3 (the remaining rank-ups not in the queue)
    //
    // The overlays are short-lived (1.1s hold + 0.2s inter-event gap) and
    // share selectors (both rank-ups use the same flt-semantics-identifier),
    // so per-overlay toBeVisible/not.toBeVisible assertions race against
    // Playwright's polling cadence. To stay robust we anchor on the two
    // *stable* signals that prove cap-at-3 worked end-to-end:
    //   1. The first rank-up overlay appears (queue began playing).
    //   2. The overflow card appears once the queue drains (proves the
    //      remaining rank-ups beyond the cap were folded into overflow).
    // The intervening rank-up→level-up transition is exhaustively covered
    // by the multi-celebration test (S3) above.
    await expect(page.locator(CELEBRATION.rankUpOverlay).first()).toBeVisible({
      timeout: 15_000,
    });

    // The 3-slot queue plays for ~3.5 s (3 × 1.1 s hold + 2 × 0.2 s gap)
    // before the overflow card appears. Allow 20 s of slack: on repeat-each
    // runs the first rank-up overlay may only become visible near the 15 s
    // limit, so the overflow card window starts late. The card itself has a
    // 4 s auto-dismiss, so 20 s from the rank-up assert covers the worst case.
    await expect(
      page.locator(CELEBRATION.celebrationOverflowCard).first(),
    ).toBeVisible({ timeout: 20_000 });

    // The overflow card auto-dismisses within 4 s of appearing.
    await expect(
      page.locator(CELEBRATION.celebrationOverflowCard).first(),
    ).not.toBeVisible({ timeout: 6_000 });
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
    // Reseed all 6 body parts back to rank 3 / 196 XP and clear prior workout
    // history. Uses dedicated rpgOverflowTapCard user (isolated from rpgOverflowQueue)
    // so this describe block never races with S4 on --repeat-each runs.
    await reseedOverflowTapCardUser();
    await login(
      page,
      TEST_USERS.rpgOverflowTapCard.email,
      TEST_USERS.rpgOverflowTapCard.password,
    );
  });

  test('should route to /profile when the user taps the overflow card', async ({
    page,
  }) => {
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

    // Wait for the overflow card to mount.
    await expect(
      page.locator(CELEBRATION.celebrationOverflowCard).first(),
    ).toBeVisible({ timeout: 20_000 });

    // Tap the card. The completer resolves to true and the post-finish
    // navigation routes to /profile (Saga) instead of /home.
    // { force: true } is required: Flutter CanvasKit's flutter-view element
    // intercepts all DOM pointer events and Playwright's normal click would
    // fail the "element is interactable" check. Force bypasses that check
    // and dispatches the event directly to the flt-semantics node via AOM,
    // which Flutter CanvasKit picks up correctly. The same pattern is used in
    // manage-data.spec.ts for GradientButton clicks (see line 597/605).
    await page.locator(CELEBRATION.celebrationOverflowCard).first().click({
      force: true,
    });

    await page.waitForURL(/\/profile/, { timeout: 10_000 });
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
  // Cache the admin client + smokePR user ID once per describe block so the
  // per-test beforeEach pays only the reset/seed cost, not another auth admin
  // round-trip. See `tasks/e2e-pollution-audit.md` Section 3 for the
  // CONFIRMED pollution path closed here:
  // `personal-records.spec.ts:309` writes a 999 kg max_weight PR for
  // `smokePR`/`barbell_bench_press`; alphabetical spec ordering then runs
  // `rank-up-celebration.spec.ts:825` against the same user, which expects
  // 105 kg × 5 to be a NEW standing PR. Without this reset, the resolver
  // sees 999 kg as the running best and the row resolves as completedNonPr.
  let cachedSmokePrUserId: string | null = null;

  test.beforeAll(async () => {
    const admin = getAdminClient();
    cachedSmokePrUserId = await getUserIdByEmail(
      admin,
      TEST_USERS.smokePR.email,
    );
  });

  test.beforeEach(async ({ page }) => {
    if (cachedSmokePrUserId) {
      const admin = getAdminClient();
      // Surgical: only barbell_bench_press history. Other smokePR exercises
      // (none today, but defensive) are left intact. Removes accumulated
      // PRs/peak_loads/sets/workout_exercises and any orphan workout that
      // only contained bench press — including global-setup's
      // 'E2E Seed Workout' chain and any prior 'E2E Reset Seed' chain.
      await resetExerciseHistoryForUser(
        admin,
        cachedSmokePrUserId,
        'barbell_bench_press',
      );
      // Re-seed the canonical 100 kg × 5 baseline that the smokePR user
      // contract assumes (matches `seedPRData` in global-setup.ts so any
      // sibling describe block also using smokePR sees the expected PR).
      // The test then beats it with 105 kg × 5.
      await seedPrForUser(
        admin,
        cachedSmokePrUserId,
        'barbell_bench_press',
        100,
        5,
      );
    }

    // smokePR user has a prior PR of 100 kg bench press (re-seeded above
    // for resilience against cross-spec pollution).
    await login(
      page,
      TEST_USERS.smokePR.email,
      TEST_USERS.smokePR.password,
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

    // smokePR user has a prior bench press PR of 100 kg × 5 reps.
    // Log 105 kg × 5 to beat it.
    await startEmptyWorkout(page);
    // BUG-020: Finish button only appears after first exercise is added.
    await addExercise(page, SEED_EXERCISES.benchPress);
    await expect(page.locator(WORKOUT.finishButton)).toBeVisible({
      timeout: 15_000,
    });

    // Log a PR-beating weight (105 kg > prior 100 kg).
    await setWeight(page, '105');
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

    // Add a second set without a PR — set 1's standing-PR signal must PERSIST.
    // The new set 2 (80 kg < 100 kg seed) is non-PR, so it will not get the
    // standing-PR identifier; only set 1's identifier should remain reachable.
    await page.locator(WORKOUT.addSetButton).last().click();
    await setWeight(page, '80');
    await setReps(page, '5');
    // After set 0 is completed, set 1 (the newly added set) is the only
    // uncompleted checkbox — always at index 0 of WORKOUT.markSetDone.
    await completeSet(page, 0);

    // First set's standing-PR signal must still be visible (the resolver is
    // stateless: set 1's 105×5 still beats every other completed working set
    // including the freshly-completed 80×5, so it stays standing).
    await expect(page.locator(SET_ROW.stateStandingPr).first()).toBeVisible({
      timeout: 10_000,
    });
  });
});

// =============================================================================
// S6 — Finish button in persistent bottom bar (BUG-020); FAB triggers add-exercise flow
// =============================================================================

test.describe('Active workout chrome (Phase 18c)', { tag: '@smoke' }, () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      TEST_USERS.smokeWorkout.email,
      TEST_USERS.smokeWorkout.password,
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
