/**
 * Playwright global setup — creates E2E test users via Supabase Admin Auth API.
 *
 * Runs once before all tests. Creates each test user with email_confirm: true
 * so they can log in immediately without email verification.
 *
 * Uses the Service Role key (admin privileges) — never expose this key to the
 * client-side app. It is only used here in the test setup process.
 *
 * If a user already exists (e.g., from a previous interrupted run), the error
 * is swallowed and setup continues so reruns are idempotent.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import {
  buildEmailForWorker,
  getAllUserKeys,
  TestUserKey,
  WORKERS_COUNT,
} from './fixtures/worker-users';

dotenv.config({ path: path.join(__dirname, '.env.local') });

/**
 * Throttle delay between sequential auth.admin.createUser calls. The local
 * Supabase Auth (GoTrue) instance starts to rate-limit after ~10 rapid-fire
 * creates, so we pace at 10/sec. Total cost: ~30 roles × 4 workers × 100ms
 * ≈ 12s for user creation, which is fine for a one-time globalSetup.
 */
const CREATE_USER_THROTTLE_MS = 100;

/**
 * Look up a user ID by email from the Supabase auth admin API.
 * Returns null if not found.
 */
async function getUserId(
  supabase: SupabaseClient,
  email: string,
): Promise<string | null> {
  // perPage: 1000 — Phase 21 creates ~168 users; the GoTrue default 50
  // silently truncates the result set and would miss any user on page 2+.
  // This helper is only used by createUserWithThrottle's idempotent
  // duplicate-lookup path, but correctness still matters when the suite
  // is rerun against an already-populated Supabase.
  const { data: listData } = await supabase.auth.admin.listUsers({
    perPage: 1000,
  });
  const user = listData?.users?.find((u) => u.email === email);
  return user?.id ?? null;
}

/**
 * Seed a single minimal completed workout for a user.
 *
 * P8 introduced a new-user CTA that replaces the "Plan your week" empty state
 * when `workoutCount == 0`. Some weekly-plan tests still assume the empty state
 * shows "Plan your week", so we seed one workout for those users to push
 * `workoutCount` above 0. This preserves the test semantics (weekly plan
 * feature is tested for "already-onboarded" users, not brand-new ones).
 *
 * Idempotent: checks for an existing workout named 'E2E Warmup Workout'.
 */
async function seedMinimalWorkout(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  const { data: existing } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E Warmup Workout')
    .maybeSingle();

  if (existing) return;

  const now = new Date();
  const startedAt = new Date(now.getTime() - 2 * 60 * 60 * 1000);
  const finishedAt = new Date(now.getTime() - 90 * 60 * 1000);

  const { error } = await supabase.from('workouts').insert({
    user_id: userId,
    name: 'E2E Warmup Workout',
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    duration_seconds: 1800,
  });

  if (error) {
    console.log(
      `[global-setup] Warning: could not seed minimal workout for ${userId}: ${error.message}`,
    );
  }
}

/**
 * Seed workout data for the smokePR user so PR display tests find records.
 *
 * Inserts: workout -> workout_exercise -> set -> personal_record
 * Uses "Barbell Bench Press" (seeded by seed.sql).
 *
 * Idempotent: checks if a workout named 'E2E Seed Workout' already exists.
 */
async function seedPRData(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  // Check if seed workout already exists
  const { data: existing } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E Seed Workout')
    .maybeSingle();

  if (existing) {
    console.log('[global-setup] PR seed data already exists, skipping.');
    return;
  }

  // Find "Barbell Bench Press" exercise by slug (slug column is stable; name
  // column was dropped in Phase 15f migration 00034).
  const { data: exercises, error: exError } = await supabase
    .from('exercises')
    .select('id')
    .eq('slug', 'barbell_bench_press')
    .eq('is_default', true)
    .limit(1);
  const exercise = exercises?.[0] ?? null;

  if (exError || !exercise) {
    console.log(
      `[global-setup] Warning: could not find Barbell Bench Press exercise: ${exError?.message}`,
    );
    return;
  }

  const now = new Date();
  const startedAt = new Date(now.getTime() - 60 * 60 * 1000); // 1h ago
  const finishedAt = new Date(now.getTime() - 30 * 60 * 1000); // 30min ago

  // Insert completed workout
  const { data: workout, error: wError } = await supabase
    .from('workouts')
    .insert({
      user_id: userId,
      name: 'E2E Seed Workout',
      started_at: startedAt.toISOString(),
      finished_at: finishedAt.toISOString(),
      duration_seconds: 1800,
    })
    .select('id')
    .single();

  if (wError || !workout) {
    console.log(
      `[global-setup] Warning: could not insert seed workout: ${wError?.message}`,
    );
    return;
  }

  // Insert workout_exercise
  const { data: wx, error: wxError } = await supabase
    .from('workout_exercises')
    .insert({
      workout_id: workout.id,
      exercise_id: exercise.id,
      order: 0,
    })
    .select('id')
    .single();

  if (wxError || !wx) {
    console.log(
      `[global-setup] Warning: could not insert seed workout_exercise: ${wxError?.message}`,
    );
    return;
  }

  // Insert set
  const { data: set, error: setError } = await supabase
    .from('sets')
    .insert({
      workout_exercise_id: wx.id,
      set_number: 1,
      reps: 5,
      weight: 100,
      set_type: 'working',
      is_completed: true,
    })
    .select('id')
    .single();

  if (setError || !set) {
    console.log(
      `[global-setup] Warning: could not insert seed set: ${setError?.message}`,
    );
    return;
  }

  // Insert personal_record
  const { error: prError } = await supabase.from('personal_records').insert({
    user_id: userId,
    exercise_id: exercise.id,
    record_type: 'max_weight',
    value: 100,
    reps: 5,
    achieved_at: finishedAt.toISOString(),
    set_id: set.id,
  });

  if (prError) {
    console.log(
      `[global-setup] Warning: could not insert seed personal_record: ${prError.message}`,
    );
    return;
  }

  console.log(`[global-setup] Seeded PR data for smokePR user (workout: ${workout.id})`);
}

/**
 * Seed a completed prior workout of Barbell Bench Press at 80 kg × 8 for
 * the Phase 23 D6 auto-seed E2E test.
 *
 * The test starts a fresh workout, mid-workout adds Barbell Bench Press,
 * and asserts the new exercise card opens with set 1 pre-filled at
 * exactly 80 kg × 8 from this seeded prior session.
 *
 * Idempotent: bails if `E2E Auto-seed Prior Workout` already exists.
 */
async function seedAutoSeedPriorWorkout(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  const { data: existing } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E Auto-seed Prior Workout')
    .maybeSingle();

  if (existing) return;

  const { data: exercises, error: exError } = await supabase
    .from('exercises')
    .select('id')
    .eq('slug', 'barbell_bench_press')
    .eq('is_default', true)
    .limit(1);
  const exercise = exercises?.[0] ?? null;

  if (exError || !exercise) {
    console.log(
      `[global-setup] Warning: could not find Barbell Bench Press for auto-seed: ${exError?.message}`,
    );
    return;
  }

  const now = new Date();
  const startedAt = new Date(now.getTime() - 60 * 60 * 1000);
  const finishedAt = new Date(now.getTime() - 30 * 60 * 1000);

  const { data: workout, error: wError } = await supabase
    .from('workouts')
    .insert({
      user_id: userId,
      name: 'E2E Auto-seed Prior Workout',
      started_at: startedAt.toISOString(),
      finished_at: finishedAt.toISOString(),
      duration_seconds: 1800,
    })
    .select('id')
    .single();

  if (wError || !workout) {
    console.log(
      `[global-setup] Warning: could not insert auto-seed workout: ${wError?.message}`,
    );
    return;
  }

  const { data: wx, error: wxError } = await supabase
    .from('workout_exercises')
    .insert({
      workout_id: workout.id,
      exercise_id: exercise.id,
      order: 0,
    })
    .select('id')
    .single();

  if (wxError || !wx) {
    console.log(
      `[global-setup] Warning: could not insert auto-seed workout_exercise: ${wxError?.message}`,
    );
    return;
  }

  const { error: setError } = await supabase.from('sets').insert({
    workout_exercise_id: wx.id,
    set_number: 1,
    reps: 8,
    weight: 80,
    set_type: 'working',
    is_completed: true,
  });

  if (setError) {
    console.log(
      `[global-setup] Warning: could not insert auto-seed set: ${setError.message}`,
    );
  } else {
    console.log(
      `[global-setup] Seeded prior workout for smokeAutoSeed user (workout: ${workout.id}, bench 80x8)`,
    );
  }
}

/**
 * Seed a completed weekly plan for the smokeWeeklyPlanReview user.
 *
 * Inserts: profile (frequency 1), workout, weekly_plan with completed routine.
 * Uses the "Push Day" starter template (seeded by seed.sql).
 *
 * Idempotent: checks if a weekly_plan for this week already exists.
 */
async function seedWeeklyPlanReviewData(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  // Calculate this Monday (ISO week start)
  const now = new Date();
  const dayOfWeek = now.getUTCDay(); // 0=Sun, 1=Mon, ..., 6=Sat
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
  const thisMonday = new Date(now);
  thisMonday.setUTCDate(now.getUTCDate() + mondayOffset);
  thisMonday.setUTCHours(0, 0, 0, 0);
  const weekStart = thisMonday.toISOString().split('T')[0]; // YYYY-MM-DD

  // Check if weekly plan already exists for this week
  const { data: existingPlan } = await supabase
    .from('weekly_plans')
    .select('id')
    .eq('user_id', userId)
    .eq('week_start', weekStart)
    .maybeSingle();

  if (existingPlan) {
    console.log('[global-setup] Weekly plan review seed data already exists, skipping.');
    return;
  }

  // Upsert profile with training_frequency_per_week: 2 (minimum valid value, low enough that 1 routine = done)
  // Note: the CHECK constraint is BETWEEN 2 AND 6, so minimum is 2.
  // However, for "WEEK COMPLETE" we need completed_count >= frequency.
  // We'll set frequency to 2 and insert 2 completed workouts to satisfy it.
  const { error: profileError } = await supabase
    .from('profiles')
    .upsert(
      {
        id: userId,
        display_name: 'Weekly Plan Reviewer',
        fitness_level: 'intermediate',
        training_frequency_per_week: 2,
      },
      { onConflict: 'id' },
    );

  if (profileError) {
    console.log(
      `[global-setup] Warning: could not upsert profile for weekly plan review: ${profileError.message}`,
    );
    return;
  }

  // Find "Push Day" workout template (limit 1 in case seed.sql ran multiple times)
  const { data: templates, error: templateError } = await supabase
    .from('workout_templates')
    .select('id')
    .eq('name', 'Push Day')
    .eq('is_default', true)
    .limit(1);
  const pushDay = templates?.[0] ?? null;

  if (templateError || !pushDay) {
    console.log(
      `[global-setup] Warning: could not find Push Day template: ${templateError?.message}`,
    );
    return;
  }

  // Insert 2 completed workouts (to match frequency of 2)
  const startedAt1 = new Date(now.getTime() - 2 * 60 * 60 * 1000);
  const finishedAt1 = new Date(now.getTime() - 90 * 60 * 1000);
  const startedAt2 = new Date(now.getTime() - 60 * 60 * 1000);
  const finishedAt2 = new Date(now.getTime() - 30 * 60 * 1000);

  const { data: workout1, error: w1Error } = await supabase
    .from('workouts')
    .insert({
      user_id: userId,
      name: 'Push Day',
      started_at: startedAt1.toISOString(),
      finished_at: finishedAt1.toISOString(),
      duration_seconds: 1800,
    })
    .select('id')
    .single();

  if (w1Error || !workout1) {
    console.log(
      `[global-setup] Warning: could not insert seed workout 1: ${w1Error?.message}`,
    );
    return;
  }

  const { data: workout2, error: w2Error } = await supabase
    .from('workouts')
    .insert({
      user_id: userId,
      name: 'Push Day',
      started_at: startedAt2.toISOString(),
      finished_at: finishedAt2.toISOString(),
      duration_seconds: 1800,
    })
    .select('id')
    .single();

  if (w2Error || !workout2) {
    console.log(
      `[global-setup] Warning: could not insert seed workout 2: ${w2Error?.message}`,
    );
    return;
  }

  // Insert weekly_plan with 2 completed routines
  const routines = [
    {
      routine_id: pushDay.id,
      order: 0,
      completed_workout_id: workout1.id,
      completed_at: finishedAt1.toISOString(),
    },
    {
      routine_id: pushDay.id,
      order: 1,
      completed_workout_id: workout2.id,
      completed_at: finishedAt2.toISOString(),
    },
  ];

  const { error: planError } = await supabase.from('weekly_plans').insert({
    user_id: userId,
    week_start: weekStart,
    routines: routines,
  });

  if (planError) {
    console.log(
      `[global-setup] Warning: could not insert seed weekly_plan: ${planError.message}`,
    );
    return;
  }

  console.log(
    `[global-setup] Seeded completed weekly plan for smokeWeeklyPlanReview (week: ${weekStart})`,
  );
}

/**
 * Seed two completed working sets on two different calendar dates for the
 * smokeExerciseProgress user so ProgressChartSection renders its multi-point
 * LineChart branch (which emits the `image: true` Semantics node the smoke
 * test selector matches).
 *
 * A single-point series is intentionally rendered as copy-only ("1 session
 * logged") with NO `image: true` semantics — see
 * `lib/features/exercises/ui/widgets/progress_chart_section.dart`. Seeding a
 * second session on a distinct calendar day bumps us onto the chart branch.
 *
 * Inserts: profile → 2 × (workout → workout_exercise → set). The two workouts
 * are >1 day apart (8 days and today) to avoid device-local timezone edge
 * cases around day-bucketing in `buildProgressPoints`.
 *
 * Uses "Barbell Bench Press" (seeded by seed.sql). Both sets are
 * `set_type = 'working'` and `is_completed = true` — the predicate in
 * `lib/features/workouts/utils/set_filters.dart` filters on exactly that.
 *
 * Idempotent: checks if a workout named 'E2E Progress Chart Workout 1' already
 * exists for this user.
 */
async function seedExerciseProgressData(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  const { data: existing } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E Progress Chart Workout 1')
    .maybeSingle();

  if (existing) {
    console.log('[global-setup] Exercise progress seed data already exists, skipping.');
    return;
  }

  // Find "Barbell Bench Press" exercise by slug (slug column is stable; name
  // column was dropped in Phase 15f migration 00034).
  const { data: exercises, error: exError } = await supabase
    .from('exercises')
    .select('id')
    .eq('slug', 'barbell_bench_press')
    .eq('is_default', true)
    .limit(1);
  const exercise = exercises?.[0] ?? null;

  if (exError || !exercise) {
    console.log(
      `[global-setup] Warning: could not find Barbell Bench Press for progress seed: ${exError?.message}`,
    );
    return;
  }

  const now = new Date();
  // Session 1: ~8 days ago (>1-day gap keeps us clear of timezone edge cases).
  const startedAt1 = new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000);
  const finishedAt1 = new Date(
    now.getTime() - 8 * 24 * 60 * 60 * 1000 + 30 * 60 * 1000,
  );
  // Session 2: today (~90 minutes ago, matches the pattern of other seed helpers).
  const startedAt2 = new Date(now.getTime() - 2 * 60 * 60 * 1000);
  const finishedAt2 = new Date(now.getTime() - 90 * 60 * 1000);

  const sessions: Array<{
    name: string;
    startedAt: Date;
    finishedAt: Date;
    weight: number;
  }> = [
    {
      name: 'E2E Progress Chart Workout 1',
      startedAt: startedAt1,
      finishedAt: finishedAt1,
      weight: 80,
    },
    {
      name: 'E2E Progress Chart Workout 2',
      startedAt: startedAt2,
      finishedAt: finishedAt2,
      weight: 82.5,
    },
  ];

  const insertedWorkoutIds: string[] = [];
  for (const session of sessions) {
    const { data: workout, error: wError } = await supabase
      .from('workouts')
      .insert({
        user_id: userId,
        name: session.name,
        started_at: session.startedAt.toISOString(),
        finished_at: session.finishedAt.toISOString(),
        duration_seconds: 1800,
      })
      .select('id')
      .single();

    if (wError || !workout) {
      console.log(
        `[global-setup] Warning: could not insert progress chart workout (${session.name}): ${wError?.message}`,
      );
      return;
    }

    const { data: wx, error: wxError } = await supabase
      .from('workout_exercises')
      .insert({
        workout_id: workout.id,
        exercise_id: exercise.id,
        order: 0,
      })
      .select('id')
      .single();

    if (wxError || !wx) {
      console.log(
        `[global-setup] Warning: could not insert progress chart workout_exercise (${session.name}): ${wxError?.message}`,
      );
      return;
    }

    const { error: setError } = await supabase.from('sets').insert({
      workout_exercise_id: wx.id,
      set_number: 1,
      reps: 5,
      weight: session.weight,
      set_type: 'working',
      is_completed: true,
    });

    if (setError) {
      console.log(
        `[global-setup] Warning: could not insert progress chart set (${session.name}): ${setError.message}`,
      );
      return;
    }

    insertedWorkoutIds.push(workout.id);
  }

  console.log(
    `[global-setup] Seeded exercise progress data for smokeExerciseProgress (workouts: ${insertedWorkoutIds.join(', ')})`,
  );
}

/**
 * Seed the rpgFoundationUser with ~12 prior workouts across 6 weeks and
 * multiple body parts, so the backfill produces lifetime_xp > 0 and LVL > 1.
 *
 * Workout plan (12 sessions over 6 weeks, 2 per week):
 *   Sessions 1-4:  barbell_bench_press (chest dominant)
 *   Sessions 5-8:  barbell_squat (legs dominant)
 *   Sessions 9-12: barbell_bent_over_row (back dominant)
 *
 * Each session: 3 working sets × the exercise. This ensures multiple body-part
 * progress rows are created by backfill. Seeding inserts the raw workout/set
 * rows directly (bypass save_workout RPC) so backfill processes them on first
 * login.
 *
 * Idempotent: checks for 'E2E RPG Foundation Workout 1' before seeding.
 */
async function seedRpgFoundationUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Ensure profile row exists so the router lands on /home.
  await supabase.from('profiles').upsert(
    {
      id: userId,
      display_name: 'RPG Foundation User',
      fitness_level: 'intermediate',
    },
    { onConflict: 'id' },
  );

  // Check idempotency.
  const { data: existing } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E RPG Foundation Workout 1')
    .maybeSingle();
  if (existing) {
    console.log('[global-setup] RPG foundation seed data already exists, skipping.');
    return;
  }

  // Find exercises by slug.
  const slugs = ['barbell_bench_press', 'barbell_squat', 'barbell_bent_over_row'];
  const exerciseMap: Record<string, string> = {};
  for (const slug of slugs) {
    const { data: exRows } = await supabase
      .from('exercises')
      .select('id')
      .eq('slug', slug)
      .eq('is_default', true)
      .limit(1);
    const ex = exRows?.[0];
    if (!ex) {
      console.log(`[global-setup] Warning: could not find exercise ${slug} for RPG foundation seed.`);
      return;
    }
    exerciseMap[slug] = ex.id;
  }

  // 12 workout sessions: 2 per week for 6 weeks ago → now.
  // Weeks 6-5-4-3-2-1 ago (oldest first so backfill cursor traverses in order).
  const sessions: Array<{ name: string; slug: string; weightKg: number; reps: number; weeksAgo: number; dayOffset: number }> = [
    // Week 6 ago
    { name: 'E2E RPG Foundation Workout 1', slug: 'barbell_bench_press', weightKg: 70, reps: 8, weeksAgo: 6, dayOffset: 1 },
    { name: 'E2E RPG Foundation Workout 2', slug: 'barbell_squat', weightKg: 90, reps: 5, weeksAgo: 6, dayOffset: 4 },
    // Week 5 ago
    { name: 'E2E RPG Foundation Workout 3', slug: 'barbell_bench_press', weightKg: 72.5, reps: 8, weeksAgo: 5, dayOffset: 1 },
    { name: 'E2E RPG Foundation Workout 4', slug: 'barbell_squat', weightKg: 92.5, reps: 5, weeksAgo: 5, dayOffset: 4 },
    // Week 4 ago
    { name: 'E2E RPG Foundation Workout 5', slug: 'barbell_bent_over_row', weightKg: 60, reps: 10, weeksAgo: 4, dayOffset: 1 },
    { name: 'E2E RPG Foundation Workout 6', slug: 'barbell_bench_press', weightKg: 75, reps: 8, weeksAgo: 4, dayOffset: 4 },
    // Week 3 ago
    { name: 'E2E RPG Foundation Workout 7', slug: 'barbell_squat', weightKg: 95, reps: 5, weeksAgo: 3, dayOffset: 1 },
    { name: 'E2E RPG Foundation Workout 8', slug: 'barbell_bent_over_row', weightKg: 62.5, reps: 10, weeksAgo: 3, dayOffset: 4 },
    // Week 2 ago
    { name: 'E2E RPG Foundation Workout 9', slug: 'barbell_bench_press', weightKg: 77.5, reps: 8, weeksAgo: 2, dayOffset: 1 },
    { name: 'E2E RPG Foundation Workout 10', slug: 'barbell_squat', weightKg: 97.5, reps: 5, weeksAgo: 2, dayOffset: 4 },
    // Week 1 ago
    { name: 'E2E RPG Foundation Workout 11', slug: 'barbell_bent_over_row', weightKg: 65, reps: 10, weeksAgo: 1, dayOffset: 1 },
    { name: 'E2E RPG Foundation Workout 12', slug: 'barbell_bench_press', weightKg: 80, reps: 8, weeksAgo: 1, dayOffset: 4 },
  ];

  const now = new Date();
  let seededCount = 0;
  for (const session of sessions) {
    const startedAt = new Date(now);
    startedAt.setDate(now.getDate() - session.weeksAgo * 7 - session.dayOffset);
    startedAt.setHours(10, 0, 0, 0);
    const finishedAt = new Date(startedAt.getTime() + 60 * 60 * 1000);

    const { data: workout, error: wErr } = await supabase
      .from('workouts')
      .insert({
        user_id: userId,
        name: session.name,
        started_at: startedAt.toISOString(),
        finished_at: finishedAt.toISOString(),
        duration_seconds: 3600,
      })
      .select('id')
      .single();

    if (wErr || !workout) {
      console.log(`[global-setup] Warning: could not insert RPG foundation workout (${session.name}): ${wErr?.message}`);
      continue;
    }

    const { data: wx, error: wxErr } = await supabase
      .from('workout_exercises')
      .insert({
        workout_id: workout.id,
        exercise_id: exerciseMap[session.slug],
        order: 1,
      })
      .select('id')
      .single();

    if (wxErr || !wx) {
      console.log(`[global-setup] Warning: could not insert workout_exercise for ${session.name}: ${wxErr?.message}`);
      continue;
    }

    // 3 working sets per session.
    for (let s = 1; s <= 3; s++) {
      const { error: setErr } = await supabase.from('sets').insert({
        workout_exercise_id: wx.id,
        set_number: s,
        reps: session.reps,
        weight: session.weightKg,
        set_type: 'working',
        is_completed: true,
      });
      if (setErr) {
        console.log(`[global-setup] Warning: could not insert set ${s} for ${session.name}: ${setErr.message}`);
      }
    }

    seededCount++;
  }

  console.log(`[global-setup] Seeded ${seededCount} RPG foundation workouts for rpgFoundationUser`);
}

/**
 * Seed the rpgFreshUser with just a profile row (zero workout history).
 * The backfill produces 0 XP → LVL 1. Used by E2-E3-E6 tests.
 *
 * Clean on every run: deletes all workouts + XP data so state is deterministic.
 */
async function seedRpgFreshUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Clean all workout data + RPG XP state every run (fresh user must start clean).
  const { data: existingWorkouts } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId);
  if (existingWorkouts && existingWorkouts.length > 0) {
    const workoutIds = existingWorkouts.map((w: { id: string }) => w.id);
    const { data: wxs } = await supabase
      .from('workout_exercises')
      .select('id')
      .in('workout_id', workoutIds);
    if (wxs && wxs.length > 0) {
      await supabase.from('sets').delete().in('workout_exercise_id', wxs.map((wx: { id: string }) => wx.id));
    }
    await supabase.from('workout_exercises').delete().in('workout_id', workoutIds);
    await supabase.from('workouts').delete().in('id', workoutIds);
  }

  // Clean RPG tables.
  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);

  // Pre-seed backfill_progress as completed (sets_processed=0, completed_at=NOW).
  // This prevents the Flutter app's SagaIntroGate from triggering
  // backfill_rpg_v1 on login (the server-side completed_at guard short-circuits
  // it). Without this, the RPC might create tiny floating-point XP artifacts
  // in the full E2E suite, causing isZeroHistory to return false and hiding
  // the first-set-awakens banner.
  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  // Upsert profile so the router lands on /home (not /onboarding).
  await supabase.from('profiles').upsert(
    {
      id: userId,
      display_name: 'RPG Fresh User',
      fitness_level: 'beginner',
    },
    { onConflict: 'id' },
  );

  // Seed peak loads for the two exercises used in S3 so strength_mult = 1.0
  // on the first workout attempt. Without peak loads, the RPC uses peak=0
  // and advances peak to the current weight before computing strength_mult —
  // that works correctly (strength_mult = 1.0 per the RPC comment) but the
  // timing of the peak-load upsert inside save_workout can occasionally cause
  // the second save in the same test run to fail XP attribution, making S3
  // flaky on first run. Seeding peaks up-front makes the run deterministic.
  const { data: benchRows } = await supabase
    .from('exercises').select('id').eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchIdFresh = benchRows?.[0]?.id;
  if (benchIdFresh) {
    await supabase.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchIdFresh, peak_weight: 60, peak_reps: 5, peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
  }
  const { data: squatRows } = await supabase
    .from('exercises').select('id').eq('slug', 'barbell_squat').eq('is_default', true).limit(1);
  const squatIdFresh = squatRows?.[0]?.id;
  if (squatIdFresh) {
    await supabase.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: squatIdFresh, peak_weight: 80, peak_reps: 5, peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  // Phase 26f ActionHero day-0 gate (workoutCount == 0) renders
  // _CreateFirstRoutineHero, which has no path into an empty workout. The
  // RPG E2E tests (18a-E2 first-workout XP, S3 FirstAwakeningOverlay) need
  // to drive `startEmptyWorkout` so the user must be in lapsed state from
  // the ActionHero's perspective. seedMinimalWorkout inserts ONE finished
  // workout with NO workout_exercises / NO sets — `getFinishedWorkoutCount`
  // returns 1 (free-workout branch wins) but record_session_xp_batch sees
  // zero historical sets, so:
  //   * 18a-E2's `body_part_progress` rows still come exclusively from the
  //     test's own bench-press workout (assertion target preserved).
  //   * S3's CelebrationEventBuilder snapshot diff still detects
  //     `wasUntouched → isNowTouched` for every body part the test exercises
  //     (FirstAwakeningOverlay still fires).
  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Cleaned and seeded profile for rpgFreshUser');
}

/**
 * Seed rpgRankUpThreshold user:
 * chest body_part_progress at ~270 XP (Rank 5 threshold ≈ 278.46 XP).
 * One working bench-press set earns ~10-15 XP and crosses the boundary.
 *
 * Also seeds a prior minimal workout so the app lands in lapsed state
 * (Quick workout entry point visible).
 *
 * Idempotent: skips if body_part_progress row for chest already exists.
 */
async function seedRpgRankUpThresholdUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Delete workouts first so record_session_xp_batch sees zero historical sets
  // on every run. The cascade chain (workouts → workout_exercises → sets) removes
  // all child rows automatically. Without this, the XP novelty discount grows on
  // each subsequent run and may prevent the rank-threshold from being crossed.
  await supabase.from('workouts').delete().eq('user_id', userId);

  // Clean RPG tables every run so XP state is deterministic.
  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);
  await supabase.from('earned_titles').delete().eq('user_id', userId);

  // Mark backfill as completed so SagaIntroGate doesn't re-run it.
  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  // Upsert profile so router lands on /home.
  await supabase.from('profiles').upsert(
    { id: userId, display_name: 'Rank Up Threshold User', fitness_level: 'intermediate' },
    { onConflict: 'id' },
  );

  // Seed chest body_part_progress at rank 2 with 120 XP.
  // Rank 3 cumulative threshold = 126 XP (60 × (1.10² − 1) / 0.10).
  // One bench press set earns ~8–12 XP for chest → crosses rank 3.
  // No title is awarded at rank 3 (first title at rank 5), so the
  // celebration queue contains only a FirstAwakeningOverlay (shoulders
  // awakens from bench secondary XP) + a RankUpOverlay — no title sheet
  // that would block navigation and fail S1.
  // Character level with chest=2, others=1: floor((2+5-6)/4)+1 = 1.
  // After chest→3: floor((3+5-6)/4)+1 = 1. No level-up. Clean queue.
  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const xp = bp === 'chest' ? 120 : 0;
    const rank = bp === 'chest' ? 2 : 1;
    const { error } = await supabase.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: xp, rank },
      { onConflict: 'user_id,body_part' },
    );
    if (error) {
      console.log(`[global-setup] Warning: could not seed body_part_progress (${bp}) for rpgRankUpThreshold: ${error.message}`);
    }
  }

  // Seed peak load for bench press so strength_mult = 1.0 (weight = peak).
  const { data: benchExercises } = await supabase
    .from('exercises').select('id').eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchId = benchExercises?.[0]?.id;
  if (benchId) {
    await supabase.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchId, peak_weight: 80, peak_reps: 5, peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
  }

  // Seed one prior minimal workout so the app shows Quick workout (lapsed state).
  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Seeded rpgRankUpThresholdUser (chest at 120 XP, rank 2 → crosses rank 3 on bench set)');
}

/**
 * Seed rpgMultiCelebration user (BUG-017, Cluster 3):
 * Pre-state designed so a single bench set produces EXACTLY 3 celebration
 * events — rank-up + level-up + title — with NO class-change and NO
 * first-awakening overlay sneaking in. The pre-fix seed (chest R4→R5)
 * triggered both a class-change (Initiate→Bulwark) and a shoulders
 * first-awakening alongside the intended trio, and the cap-at-3 queue
 * silently dropped the title.
 *
 * Pre-state:
 *   * chest:                rank 9 (810 XP — just below rank-10 cumulative 815)
 *   * back, legs, shoulders: rank 2 (65 XP each — past rank-2 cumulative 60)
 *   * arms, core:           rank 1 (1 XP each — > 0 prevents first-awakening
 *                                    if attribution touches them)
 *
 * Workout: one bench set @ 80 kg × 5 reps (≈ 30 XP to chest).
 *
 * Post-state derivation:
 *   * chest: 810 + ~30 = ~840 XP, rank 10 → RankUpEvent(chest, 10)
 *   * sum_pre = 9 + 2 + 2 + 2 + 1 + 1 = 17, level = floor(11/4) + 1 = 3
 *   * sum_post = 10 + 2 + 2 + 2 + 1 + 1 = 18, level = floor(12/4) + 1 = 4
 *     → LevelUpEvent(4)
 *   * pre-class: max=9 (chest), min=1, ratio>30%, dominant=chest = Bulwark
 *     post-class: max=10 (chest), min=1, ratio>30%, dominant=chest = Bulwark
 *     → NO class change
 *   * shoulders/arms/core all have pre-XP > 0 → NO first-awakening
 *   * chest_r10_plate_bearer title fires (threshold 10, in (9, 10])
 *
 * Final queue: [rankUp(chest, 10), levelUp(4), titleUnlock(chest_r10)]
 * Exactly fits cap-at-3 — no overflow, no silent drops.
 */
async function seedRpgMultiCelebrationUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Delete workouts first so record_session_xp_batch sees zero historical sets
  // on every run. The cascade (workouts → workout_exercises → sets) removes all
  // child rows automatically. personal_records.set_id is set to NULL by the FK
  // ON DELETE SET NULL rule — the explicit personal_records delete below then
  // removes the now-nulled records before re-seeding fresh ones.
  await supabase.from('workouts').delete().eq('user_id', userId);

  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('personal_records').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);
  await supabase.from('earned_titles').delete().eq('user_id', userId);

  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  await supabase.from('profiles').upsert(
    { id: userId, display_name: 'Multi Celebration User', fitness_level: 'intermediate' },
    { onConflict: 'id' },
  );

  // BUG-017 seed shape — see doc comment above for the full derivation.
  // Three rank-2 body parts + two rank-1 with > 0 XP avoid the first-
  // awakening overlay; chest at rank 9 with chest already dominant
  // avoids the Initiate→Bulwark class change.
  const bodyPartSeed: Record<string, { xp: number; rank: number }> = {
    chest:     { xp: 810, rank: 9 },
    back:      { xp: 65,  rank: 2 },
    legs:      { xp: 65,  rank: 2 },
    shoulders: { xp: 65,  rank: 2 },
    arms:      { xp: 1,   rank: 1 },
    core:      { xp: 1,   rank: 1 },
  };
  for (const [bp, seed] of Object.entries(bodyPartSeed)) {
    const { error } = await supabase.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: seed.xp, rank: seed.rank },
      { onConflict: 'user_id,body_part' },
    );
    if (error) {
      console.log(`[global-setup] Warning: body_part_progress seed error (${bp}) for rpgMultiCelebration: ${error.message}`);
    }
  }

  const { data: benchExercises } = await supabase
    .from('exercises').select('id').eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchId = benchExercises?.[0]?.id;
  if (benchId) {
    await supabase.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchId, peak_weight: 80, peak_reps: 5, peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
    // Seed prior personal records for all three record types so the workout
    // finish does NOT trigger pr-celebration navigation (bench at 80kg/5
    // produces max_weight=80, max_reps=5, max_volume=400 — all already known).
    const benchAchievedAt = new Date(Date.now() - 86_400_000).toISOString();
    await supabase.from('personal_records').insert([
      { user_id: userId, exercise_id: benchId, record_type: 'max_weight', value: 80, reps: 5, achieved_at: benchAchievedAt },
      { user_id: userId, exercise_id: benchId, record_type: 'max_reps', value: 5, achieved_at: benchAchievedAt },
      { user_id: userId, exercise_id: benchId, record_type: 'max_volume', value: 400, achieved_at: benchAchievedAt },
    ]);
  }

  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Seeded rpgMultiCelebrationUser (chest 810 XP / rank 9 → R10 + level 4 + chest_r10 title; class stable, no first-awakening)');
}

/**
 * Seed rpgOverflowQueue user (Phase 29 v2):
 *
 * Pre-state: all 6 body parts at rank 5, total_xp = 354. The seed value
 * is the MIDPOINT of the deterministic window for "all 6 BPs single-rank
 * up to 6, none skip to 7":
 *   * core (smallest gainer, 36.35 XP) needs seed > R6 − 36.35 = 329.96
 *   * legs (largest gainer, 85.39 XP) needs seed < R7 − 85.39 = 377.55
 *   * midpoint = 354 leaves ~24 XP margin on both ends.
 *
 * The post-state XP per body part is EXACT (1e-4 absolute parity with
 * the Dart `XpCalculator` + Python sim + fixture oracle):
 *   * chest:     354.0 + 68.4366 → 422.4366 (rank 6)
 *   * back:      354.0 + 79.1780 → 433.1780 (rank 6)
 *   * legs:      354.0 + 85.3888 → 439.3888 (rank 6)
 *   * shoulders: 354.0 + 67.2183 → 421.2183 (rank 6)
 *   * arms:      354.0 + 45.1321 → 399.1321 (rank 6)
 *   * core:      354.0 + 36.3483 → 390.3483 (rank 6)
 *
 * Class is Ascendant (minRank ≥ 5, spread = 0%) both pre and post →
 * NO ClassChangeEvent. Character level 7 → 8 → exactly 1 LevelUpEvent.
 * No body-part / character-level title thresholds cross in the (5, 6]
 * rank window → no TitleUnlockEvent.
 *
 * Celebration queue cap-at-3 allocation:
 *   * slot 1 (class change): empty
 *   * slot 2 (top rank-up):  legs (newRank=6)
 *   * spillover (2 more):    back, chest (newRank=6, alphabetical)
 *   * overflow rank-ups:     6 − 3 = 3 → card asserts "3 more rank-ups"
 *
 * Per-set XP totals (asserted in the E2E test for parity drift detection):
 *   * Set 1 — bench 80×5:  97.7666 XP  (chest 68.4366, shoulders 19.5533, arms 9.7767)
 *   * Set 2 — squat 80×5: 106.7360 XP  (legs 85.3888, back 10.6736, core 10.6736)
 *   * Set 3 — row  70×5:   97.8635 XP  (back 68.5044, arms 19.5727, core 9.7863)
 *   * Set 4 — OHP  50×5:   79.3361 XP  (shoulders 47.6650, arms 15.7828, core 15.8883)
 *
 * If a SQL helper changes and the per-set XP diverges from the values
 * above by more than 1e-4, the E2E parity assertion will flag it BEFORE
 * the celebration-queue logic ever runs.
 */
async function seedRpgOverflowQueueUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Delete workouts first so record_session_xp_batch sees zero historical sets
  // on every run (fixes seed-depletion bug: novelty discount from prior-run sets
  // reduced XP below the rank-4 threshold on the 2nd+ run, preventing overflow).
  // The cascade chain (workouts → workout_exercises → sets) removes children
  // automatically. personal_records.set_id is nulled by ON DELETE SET NULL.
  await supabase.from('workouts').delete().eq('user_id', userId);

  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('personal_records').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);
  await supabase.from('earned_titles').delete().eq('user_id', userId);

  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  await supabase.from('profiles').upsert(
    { id: userId, display_name: 'Overflow Queue User', fitness_level: 'intermediate' },
    { onConflict: 'id' },
  );

  // All 6 body parts seeded at rank 5, total_xp = 354. See the function
  // dartdoc above for the deterministic window + exact post-state values.
  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const { error } = await supabase.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: 354, rank: 5 },
      { onConflict: 'user_id,body_part' },
    );
    if (error) {
      console.log(`[global-setup] Warning: body_part_progress seed error (${bp}) for rpgOverflowQueue: ${error.message}`);
    }
  }

  // Seed peak loads and prior personal records for the 4 exercises used in S4.
  // Peak loads keep strength_mult = 1.0; personal records prevent pr-celebration
  // navigation after workout finish (the app only navigates to /pr-celebration
  // when prResult.hasNewRecords is true — no record exists means any set is a PR).
  const exerciseSlugs: Record<string, { slug: string; peak: number }> = {
    chest:     { slug: 'barbell_bench_press',   peak: 80 },
    legs:      { slug: 'barbell_squat',          peak: 80 },
    back:      { slug: 'barbell_bent_over_row',  peak: 70 },
    shoulders: { slug: 'overhead_press',         peak: 50 },
  };
  for (const { slug, peak } of Object.values(exerciseSlugs)) {
    const { data: exRows } = await supabase
      .from('exercises').select('id').eq('slug', slug).eq('is_default', true).limit(1);
    const exId = exRows?.[0]?.id;
    if (exId) {
      await supabase.from('exercise_peak_loads').upsert(
        { user_id: userId, exercise_id: exId, peak_weight: peak, peak_reps: 5, peak_date: new Date().toISOString() },
        { onConflict: 'user_id,exercise_id' },
      );
      // Seed prior personal records for all three record types so workout
      // finish does not trigger pr-celebration navigation (any set at the
      // seeded weight/reps would otherwise register as a new max_reps or
      // max_volume record even when max_weight is already known).
      const achievedAt = new Date(Date.now() - 86_400_000).toISOString();
      await supabase.from('personal_records').insert([
        { user_id: userId, exercise_id: exId, record_type: 'max_weight', value: peak, reps: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_reps', value: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_volume', value: peak * 5, achieved_at: achievedAt },
      ]);
    }
  }

  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Seeded rpgOverflowQueueUser (all 6 body parts at rank 5, 354 XP — Phase 29 v2 R6 deterministic window, Ascendant class)');
}

/**
 * Seed rpgOverflowTapCard user — identical seeding contract to rpgOverflowQueue
 * but on a dedicated user. This prevents cross-worker XP state races when
 * --repeat-each=2 runs the auto-dismiss test (S4) and the tap-card test (S4b)
 * on parallel workers: each test now operates on its own user.
 */
async function seedRpgOverflowTapCardUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  await supabase.from('workouts').delete().eq('user_id', userId);
  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('personal_records').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);
  await supabase.from('earned_titles').delete().eq('user_id', userId);

  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  await supabase.from('profiles').upsert(
    { id: userId, display_name: 'Overflow Tap User', fitness_level: 'intermediate' },
    { onConflict: 'id' },
  );

  // All 6 body parts at rank 5, total_xp = 354 (mirror
  // seedRpgOverflowQueueUser; see that function's dartdoc for the
  // deterministic-window derivation + exact post-state XP values).
  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const { error } = await supabase.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: 354, rank: 5 },
      { onConflict: 'user_id,body_part' },
    );
    if (error) {
      console.log(`[global-setup] Warning: body_part_progress seed error (${bp}) for rpgOverflowTapCard: ${error.message}`);
    }
  }

  const exerciseSlugs: Record<string, { slug: string; peak: number }> = {
    chest:     { slug: 'barbell_bench_press',   peak: 80 },
    legs:      { slug: 'barbell_squat',          peak: 80 },
    back:      { slug: 'barbell_bent_over_row',  peak: 70 },
    shoulders: { slug: 'overhead_press',         peak: 50 },
  };
  for (const { slug, peak } of Object.values(exerciseSlugs)) {
    const { data: exRows } = await supabase
      .from('exercises').select('id').eq('slug', slug).eq('is_default', true).limit(1);
    const exId = exRows?.[0]?.id;
    if (exId) {
      await supabase.from('exercise_peak_loads').upsert(
        { user_id: userId, exercise_id: exId, peak_weight: peak, peak_reps: 5, peak_date: new Date().toISOString() },
        { onConflict: 'user_id,exercise_id' },
      );
      const achievedAt = new Date(Date.now() - 86_400_000).toISOString();
      await supabase.from('personal_records').insert([
        { user_id: userId, exercise_id: exId, record_type: 'max_weight', value: peak, reps: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_reps', value: 5, achieved_at: achievedAt },
        { user_id: userId, exercise_id: exId, record_type: 'max_volume', value: peak * 5, achieved_at: achievedAt },
      ]);
    }
  }

  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Seeded rpgOverflowTapCardUser (all 6 body parts at rank 5, 354 XP — Phase 29 v2 R6 deterministic window, Ascendant class)');
}

// ---------------------------------------------------------------------------
// Per-role seed helpers extracted for the per-worker orchestration loop.
// Each helper takes a `supabase` admin client + a `userId` and applies the
// fixture data that role's tests require. They never look up users by email
// because the same role lives at multiple worker-scoped emails.
// ---------------------------------------------------------------------------

/**
 * Generic clean-then-seed for the freshState role family. Removes prior
 * workouts/sets/PRs/weekly_plans/XP rows so each E2E run starts deterministic.
 */
async function cleanFreshStateUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  const { data: workouts } = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId);

  if (workouts && workouts.length > 0) {
    const workoutIds = workouts.map((w: { id: string }) => w.id);

    const { data: wxs } = await supabase
      .from('workout_exercises')
      .select('id')
      .in('workout_id', workoutIds);

    if (wxs && wxs.length > 0) {
      const wxIds = wxs.map((wx: { id: string }) => wx.id);
      await supabase.from('sets').delete().in('workout_exercise_id', wxIds);
    }

    await supabase
      .from('workout_exercises')
      .delete()
      .in('workout_id', workoutIds);
    await supabase.from('workouts').delete().in('id', workoutIds);
  }

  await supabase.from('personal_records').delete().eq('user_id', userId);
  await supabase.from('weekly_plans').delete().eq('user_id', userId);
  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('user_xp').delete().eq('user_id', userId);
}

/** Upsert a profile row with arbitrary defaults. */
async function ensureProfile(
  supabase: SupabaseClient,
  userId: string,
  fields: {
    display_name?: string;
    fitness_level?: string;
    locale?: string;
    training_frequency_per_week?: number;
  } = {},
): Promise<void> {
  const payload: Record<string, unknown> = {
    id: userId,
    display_name: fields.display_name ?? 'Gym User',
    fitness_level: fields.fitness_level ?? 'intermediate',
  };
  if (fields.locale !== undefined) payload['locale'] = fields.locale;
  if (fields.training_frequency_per_week !== undefined) {
    payload['training_frequency_per_week'] = fields.training_frequency_per_week;
  }
  const { error } = await supabase
    .from('profiles')
    .upsert(payload, { onConflict: 'id' });
  if (error) {
    console.log(
      `[global-setup] Warning: could not upsert profile for ${userId}: ${error.message}`,
    );
  }
}

/** Delete the profile row (used by onboarding-fresh users). */
async function deleteProfile(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  await supabase.from('profiles').delete().eq('id', userId);
}

/**
 * Seed 5 workouts for the fullHistoryPt role. The most recent workout has
 * a barbell_bench_press exercise + completed set so the history screen
 * renders the pt-localized name on the workout card.
 */
async function seedFullHistoryPtData(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  // Idempotent guard: only seed if the well-known workout name doesn't yet exist.
  const existing = await supabase
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E PT History Workout 1')
    .maybeSingle();
  if (existing.data) return;

  const { data: ptBenchExercises } = await supabase
    .from('exercises')
    .select('id')
    .eq('slug', 'barbell_bench_press')
    .eq('is_default', true)
    .limit(1);
  const ptBenchExercise = ptBenchExercises?.[0] ?? null;

  const now = new Date();
  for (let i = 0; i < 5; i++) {
    const startedAt = new Date(now.getTime() - (i + 1) * 24 * 60 * 60 * 1000);
    const finishedAt = new Date(startedAt.getTime() + 60 * 60 * 1000);
    const { data: workout, error: wError } = await supabase
      .from('workouts')
      .insert({
        user_id: userId,
        name: `E2E PT History Workout ${i + 1}`,
        started_at: startedAt.toISOString(),
        finished_at: finishedAt.toISOString(),
        duration_seconds: 3600,
      })
      .select('id')
      .single();

    if (i === 0 && workout && !wError && ptBenchExercise) {
      const { data: wx } = await supabase
        .from('workout_exercises')
        .insert({
          workout_id: workout.id,
          exercise_id: ptBenchExercise.id,
          order: 0,
        })
        .select('id')
        .single();

      if (wx) {
        await supabase.from('sets').insert({
          workout_exercise_id: wx.id,
          set_number: 1,
          reps: 5,
          weight: 80,
          set_type: 'working',
          is_completed: true,
        });
      }
    }
  }
}

/**
 * Per-role seed orchestration. Maps a TestUserKey to a function that
 * applies the role's fixture data given a freshly-created auth user.
 *
 * Roles not in this map get a no-op — the auth user exists but no
 * additional rows are seeded (correct for tests that drive their own
 * profile creation, e.g., onboarding flows).
 *
 * The order of operations within each runner mirrors the legacy
 * globalSetup() flow exactly so semantics are preserved.
 */
function buildRoleSeedRunners(): Record<
  string,
  (supabase: SupabaseClient, userId: string) => Promise<void>
> {
  return {
    // ── Smoke users that need a profile but no other seed ────────────────
    smokeExercise: async (supabase, userId) => {
      await ensureProfile(supabase, userId);
    },
    smokeProfileWeeklyGoal: async (supabase, userId) => {
      await ensureProfile(supabase, userId);
    },

    // ── Onboarding (fresh state, no profile) ─────────────────────────────
    smokeOnboarding: async (supabase, userId) => {
      await deleteProfile(supabase, userId);
    },

    // ── PR seed user (smoke) ─────────────────────────────────────────────
    smokePR: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, { display_name: 'PR Test User' });
      await seedPRData(supabase, userId);
    },

    // ── First-workout beginner CTA — zero workouts + profile ─────────────
    smokeFirstWorkout: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId);
    },

    // BUG-001 workout-restore tests need lapsed state so startEmptyWorkout
    // resolves the Phase 26f free-workout banner. The tests only assert that
    // a manually-added exercise name survives a page reload — they don't
    // care about day-0 vs lapsed beyond the entry point being reachable.
    smokeWorkoutRestore: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Workout Restore User',
      });
      await seedMinimalWorkout(supabase, userId);
    },

    // ── Saga intro (fresh + profile, no workouts) ────────────────────────
    sagaIntroUser: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId);
    },

    // ── Lapsed-state freshState users — clean then seed minimal workout ──
    smokeWorkout: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    smokeOfflineSync: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    smokeWorkoutCancelStart: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // PR-2 — swipe-delete undo SnackBar reachability tests need the lapsed
    // state (one prior workout) so `startEmptyWorkout` finds the
    // "Quick workout" CTA rather than the brand-new beginner card.
    smokeWorkoutSwipeUndo: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // PR-2 — discard-race cancel E2E (closes post-PR-1 coverage gap).
    // Same lapsed-state seed as the loading-overlay-cancel test.
    smokeWorkoutDiscardRace: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // PR-3 — destructive-gesture cleanup, Q3 swap confirm, H5 add-undo.
    // Lapsed state so `startEmptyWorkout` finds the "Quick workout" CTA.
    smokeWorkoutDestructiveGestures: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // PR-3 S1 — DiscardWorkoutCoordinator re-entrance test. Stalls
    // DELETE /workouts via page.route(). Isolated from smokeWorkoutDiscardRace
    // so two stall handlers can't race the same backing user across workers.
    smokeWorkoutDiscardReentry: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // PR-4 M3 — cascading delete + undo restores original order. Lapsed
    // state so startEmptyWorkout finds "Quick workout" CTA. The test
    // adds 4 sets, swipe-deletes #2 then #3, undoes both, and asserts
    // the rendered set numbers match the original [1,2,3,4] sequence.
    smokeWorkoutPr4CascadingUndo: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // PR-6 M6 — PR-row loading-state contract. Stalls per-exercise GETs to
    // `/rest/v1/personal_records?exercise_id=in.` while the user adds and
    // completes a first set, then asserts the row is NOT classified as
    // `set-row-state-standing-pr` until the stall releases. Fresh state →
    // no historical records → unambiguous post-load reclassification.
    smokeWorkoutPr6RowFlicker: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // Phase 23 D1 — rest-overlay chrome visibility. Lapsed state (one
    // prior workout) so startEmptyWorkout finds "Quick workout". No
    // exercise seeds needed; the test adds bench press fresh.
    smokeRestChrome: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    // Phase 23 D6 — addExercise auto-seed. Seeds a completed prior
    // workout of Barbell Bench Press at 80 kg × 8 so the test can
    // assert the new exercise card opens with one set pre-filled at
    // exactly those values when bench press is added mid-workout.
    smokeAutoSeed: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Gym User',
      });
      await seedAutoSeedPriorWorkout(supabase, userId);
    },
    fullWorkout: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    fullHome: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    fullManageData: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    fullPR: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    fullCrash: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    fullExDetailSheet: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },

    // ── Weekly plan smoke (clean weekly_plans + minimal workout) ─────────
    smokeWeeklyPlan: async (supabase, userId) => {
      await supabase.from('weekly_plans').delete().eq('user_id', userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },

    // ── 23-P-4: routine-removed undo SnackBar dismissal-time test ────────
    // Clean plan state each run so the test starts with an empty plan,
    // adds a routine inside the test, swipe-removes it, then asserts the
    // snack auto-dismisses. Isolated from smokeWeeklyPlan so the 3 s wait
    // in this test can't race the smokeWeeklyPlan plan-manipulation tests.
    smokeWeeklyPlanRoutineRemoveUndo: async (supabase, userId) => {
      await supabase.from('weekly_plans').delete().eq('user_id', userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Weekly Plan Tester',
      });
      await seedMinimalWorkout(supabase, userId);
    },

    // ── Weekly plan review (completed weekly plan) ──────────────────────
    smokeWeeklyPlanReview: async (supabase, userId) => {
      await seedWeeklyPlanReviewData(supabase, userId);
    },

    // ── Phase 24c-8: bodyweight prompt E2E ───────────────────────────────
    // Lapsed user (one prior workout for "Quick workout" CTA) with
    // profile.bodyweight_kg explicitly set to NULL. The test will:
    //   1. Start a workout via the home CTA
    //   2. Add Pull-Up (uses_bodyweight_load = TRUE)
    //   3. Complete the first set
    //   4. Assert the bodyweight prompt SnackBar appears
    //   5. Tap "Set now" → enter 70 kg in the bottom sheet → save
    //   6. Finish the workout
    //   7. Verify via REST that profile.bodyweight_kg = 70 AND that the
    //      pull-up xp_event payload carries effective_load = 70 (proving
    //      the prompt + save round-trip actually fed the SQL math).
    //
    // We force `bodyweight_kg = NULL` here even though new profiles
    // default to NULL — defence in depth against a future ensureProfile
    // change that pre-fills it.
    smokeBodyweightPrompt: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Bodyweight Prompt User',
      });
      // Force NULL bodyweight even if upsertProfile defaults change.
      const { error: bwError } = await supabase
        .from('profiles')
        .update({ bodyweight_kg: null })
        .eq('id', userId);
      if (bwError) {
        console.log(
          `[global-setup] Warning: could not reset bodyweight_kg for ${userId}: ${bwError.message}`,
        );
      }
      await seedMinimalWorkout(supabase, userId);
    },

    // ── Exercise progress chart (P1) ─────────────────────────────────────
    smokeExerciseProgress: async (supabase, userId) => {
      await ensureProfile(supabase, userId, {
        display_name: 'Progress Chart User',
      });
      await seedExerciseProgressData(supabase, userId);
    },

    // ── Localization (pt) ────────────────────────────────────────────────
    smokeLocalization: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Localization User',
        locale: 'pt',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    smokeLocalizationEn: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'Localization En User',
        locale: 'en',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    smokeLocalizationWorkout: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'PT Workout User',
        locale: 'pt',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    smokeLocalizationRoutines: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'PT Routines User',
        locale: 'pt',
      });
      await seedMinimalWorkout(supabase, userId);
    },
    fullHistoryPt: async (supabase, userId) => {
      await ensureProfile(supabase, userId, {
        display_name: 'PT History User',
        locale: 'pt',
      });
      await seedFullHistoryPtData(supabase, userId);
    },
    fullPRPt: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await ensureProfile(supabase, userId, {
        display_name: 'PT PR User',
        locale: 'pt',
      });
      await seedPRData(supabase, userId);
    },

    // ── Phase 18a RPG ────────────────────────────────────────────────────
    // rpgFoundationUser is NOT pre-cleaned: seedRpgFoundationUser is
    // idempotent on its own marker workout name, and the legacy code path
    // never included it in the freshStateUsers cleanup loop either. Wiping
    // the foundation seed every run would break tests that rely on
    // 12-workout XP backfill.
    rpgFoundationUser: async (supabase, userId) => {
      await seedRpgFoundationUser(supabase, userId);
    },
    // rpgFreshUser is also not pre-cleaned at this layer — seedRpgFreshUser
    // does its own deterministic clean (mirrors legacy behavior).
    rpgFreshUser: async (supabase, userId) => {
      await seedRpgFreshUser(supabase, userId);
    },

    // ── Phase 18c celebration overlays ───────────────────────────────────
    rpgRankUpThreshold: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await seedRpgRankUpThresholdUser(supabase, userId);
    },
    rpgMultiCelebration: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await seedRpgMultiCelebrationUser(supabase, userId);
    },
    rpgOverflowQueue: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await seedRpgOverflowQueueUser(supabase, userId);
    },
    rpgOverflowTapCard: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await seedRpgOverflowTapCardUser(supabase, userId);
    },

    // ── Phase 18e class-cross + title-equip ──────────────────────────────
    rpgClassCrossUser: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await seedRpgClassCrossUser(supabase, userId);
    },
    rpgTitleEquipUser: async (supabase, userId) => {
      await cleanFreshStateUser(supabase, userId);
      await seedRpgTitleEquipUser(supabase, userId);
    },
  };
}

/**
 * Throttled auth.admin.createUser with exponential-backoff retry on rate-limit
 * (429-class) errors. Returns the userId on success, or `null` if the user
 * already exists (idempotent — duplicates are not an error).
 */
async function createUserWithThrottle(
  supabase: SupabaseClient,
  email: string,
  password: string,
): Promise<string | null> {
  const maxAttempts = 4;
  let attempt = 0;
  let backoffMs = 500;
  while (attempt < maxAttempts) {
    const { data, error } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (!error) return data.user?.id ?? null;

    const msg = error.message.toLowerCase();
    // Idempotent: user already exists. Look up the existing id so seed
    // helpers can still run against it.
    if (
      msg.includes('already') ||
      msg.includes('registered') ||
      msg.includes('exists')
    ) {
      const existingId = await getUserId(supabase, email);
      return existingId;
    }
    // Rate-limit / transient — retry with backoff.
    if (msg.includes('rate') || msg.includes('429') || msg.includes('limit')) {
      attempt++;
      console.log(
        `[global-setup] Rate-limited creating ${email}, retrying in ${backoffMs}ms (attempt ${attempt}/${maxAttempts})`,
      );
      await new Promise((r) => setTimeout(r, backoffMs));
      backoffMs *= 2;
      continue;
    }
    // Any other error — fail.
    throw new Error(
      `[global-setup] Failed to create user ${email}: ${error.message}`,
    );
  }
  throw new Error(
    `[global-setup] Exhausted retries creating user ${email} (rate-limited)`,
  );
}

async function globalSetup(): Promise<void> {
  const supabaseUrl = process.env['SUPABASE_URL'];
  const supabaseAnonKey = process.env['SUPABASE_ANON_KEY'];
  const serviceRoleKey = process.env['SUPABASE_SERVICE_ROLE_KEY'];
  const password = process.env['TEST_USER_PASSWORD'];

  // ── Inject local Supabase credentials into the Flutter web build ──────
  // flutter_dotenv loads build/web/assets/.env at runtime. The production
  // build bundles the hosted Supabase URL, but E2E tests run against the
  // local Supabase instance. We overwrite the .env in the build directory
  // so the app connects to the same Supabase the tests use.
  if (supabaseUrl && supabaseAnonKey) {
    const envContent = `SUPABASE_URL=${supabaseUrl}\nSUPABASE_ANON_KEY=${supabaseAnonKey}\n`;
    const buildWebDir = path.join(__dirname, '..', '..', 'build', 'web');
    const envPaths = [
      path.join(buildWebDir, 'assets', '.env'),
      path.join(buildWebDir, '.env'),
    ];
    for (const envPath of envPaths) {
      if (fs.existsSync(path.dirname(envPath))) {
        fs.writeFileSync(envPath, envContent);
        console.log(`[global-setup] Injected local .env into ${envPath}`);
      }
    }
  }

  if (!supabaseUrl || !serviceRoleKey || !password) {
    throw new Error(
      'Missing required environment variables: SUPABASE_URL, ' +
        'SUPABASE_SERVICE_ROLE_KEY, TEST_USER_PASSWORD. ' +
        'Ensure test/e2e/.env.local is present.',
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── Phase 21: per-worker user pool ────────────────────────────────────
  // Create N workers × M roles unique auth users, then run each role's
  // seed runner per (worker, role) pair. Concurrent workers can never
  // collide on a Supabase auth row because emails are worker-scoped.
  const roleKeys = getAllUserKeys();
  const totalUsers = WORKERS_COUNT * roleKeys.length;
  console.log(
    `[global-setup] Creating ${WORKERS_COUNT} workers × ${roleKeys.length} roles = ${totalUsers} users (throttled 10/sec)...`,
  );

  const seedRunners = buildRoleSeedRunners();

  let createdCount = 0;
  // Per-worker user-id map indexed by role for the subsequent seed phase.
  const userIdsByWorker: Array<Partial<Record<TestUserKey, string>>> = [];
  for (let w = 0; w < WORKERS_COUNT; w++) {
    userIdsByWorker.push({});
  }

  for (let workerIndex = 0; workerIndex < WORKERS_COUNT; workerIndex++) {
    for (const role of roleKeys) {
      const email = buildEmailForWorker(role, workerIndex);
      const userId = await createUserWithThrottle(supabase, email, password);
      if (userId) {
        userIdsByWorker[workerIndex]![role] = userId;
      }

      createdCount++;
      if (createdCount % 20 === 0 || createdCount === totalUsers) {
        console.log(
          `[global-setup]   …created ${createdCount}/${totalUsers} users`,
        );
      }

      // Throttle between every create call to avoid GoTrue rate limits.
      await new Promise((r) => setTimeout(r, CREATE_USER_THROTTLE_MS));
    }
  }

  // ── Per-worker seed phase ─────────────────────────────────────────────
  // Roles without a runner are no-ops (auth user only — sufficient for tests
  // that drive their own profile creation, e.g., onboarding / auth tests).
  console.log(`[global-setup] Applying per-role seed data across ${WORKERS_COUNT} workers...`);
  for (let workerIndex = 0; workerIndex < WORKERS_COUNT; workerIndex++) {
    const userIds = userIdsByWorker[workerIndex]!;
    for (const role of roleKeys) {
      const userId = userIds[role];
      if (!userId) continue;
      const runner = seedRunners[role];
      if (!runner) continue;
      await runner(supabase, userId);
    }
    console.log(`[global-setup]   …seeded worker ${workerIndex}`);
  }

  console.log('[global-setup] Done.');
}

/**
 * Seed rpgClassCrossUser: chest at rank 4 (270 XP), all others at rank 1.
 *
 * Seeding mirrors rpgMultiCelebration but on a dedicated user so the
 * class-cross test can run independently without interfering with the
 * multi-celebration XP state. After one bench-press set chest crosses
 * rank 4 → rank 5: class resolver fires dominant chest → Bulwark.
 *
 * The class badge before the workout reads "Initiate" (max rank 4 < 5).
 * After the workout finish + provider refresh it reads "Bulwark".
 */
async function seedRpgClassCrossUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Full clean on every run so XP state is deterministic.
  await supabase.from('workouts').delete().eq('user_id', userId);
  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('personal_records').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);
  await supabase.from('earned_titles').delete().eq('user_id', userId);

  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  await supabase.from('profiles').upsert(
    { id: userId, display_name: 'Class Cross User', fitness_level: 'intermediate' },
    { onConflict: 'id' },
  );

  // Chest at 270 XP / rank 4 (Rank 5 threshold ≈ 278.46 XP).
  // One bench-press set at 80 kg × 5 reps earns ~8–15 chest XP → crosses rank 5.
  // All other body parts at rank 1 / 0 XP (resolver default).
  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const xp = bp === 'chest' ? 270 : 0;
    const rank = bp === 'chest' ? 4 : 1;
    await supabase.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: xp, rank },
      { onConflict: 'user_id,body_part' },
    );
  }

  // Seed bench-press peak load = 80 kg so strength_mult = 1.0 on the test set.
  const { data: benchExercises } = await supabase
    .from('exercises').select('id').eq('slug', 'barbell_bench_press').eq('is_default', true).limit(1);
  const benchId = benchExercises?.[0]?.id;
  if (benchId) {
    await supabase.from('exercise_peak_loads').upsert(
      { user_id: userId, exercise_id: benchId, peak_weight: 80, peak_reps: 5, peak_date: new Date().toISOString() },
      { onConflict: 'user_id,exercise_id' },
    );
    // Pre-seed personal records so workout finish doesn't navigate to /pr-celebration.
    const achievedAt = new Date(Date.now() - 86_400_000).toISOString();
    await supabase.from('personal_records').insert([
      { user_id: userId, exercise_id: benchId, record_type: 'max_weight', value: 80, reps: 5, achieved_at: achievedAt },
      { user_id: userId, exercise_id: benchId, record_type: 'max_reps', value: 5, achieved_at: achievedAt },
      { user_id: userId, exercise_id: benchId, record_type: 'max_volume', value: 400, achieved_at: achievedAt },
    ]);
  }

  // One prior minimal workout so the app shows Quick workout (lapsed state).
  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Seeded rpgClassCrossUser (chest 270 XP / rank 4 → crosses rank 5 on bench set)');
}

/**
 * Seed rpgTitleEquipUser: chest at rank 5 (290 XP) with the R5 chest title
 * already earned in earned_titles. The user also has a prior minimal workout
 * so the app lands in lapsed state (Quick workout entry point visible).
 *
 * The first per-body-part title ("Plate-Bearer" at rank 5) is pre-seeded in
 * earned_titles directly (bypassing save_workout) so it appears in the Titles
 * screen without requiring a real workout to cross the threshold.
 *
 * Idempotent: skips if body_part_progress row for chest already exists.
 */
async function seedRpgTitleEquipUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {

  // Full clean on every run.
  await supabase.from('workouts').delete().eq('user_id', userId);
  await supabase.from('xp_events').delete().eq('user_id', userId);
  await supabase.from('body_part_progress').delete().eq('user_id', userId);
  await supabase.from('exercise_peak_loads').delete().eq('user_id', userId);
  await supabase.from('personal_records').delete().eq('user_id', userId);
  await supabase.from('backfill_progress').delete().eq('user_id', userId);
  await supabase.from('earned_titles').delete().eq('user_id', userId);

  await supabase.from('backfill_progress').upsert(
    {
      user_id: userId,
      sets_processed: 0,
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  await supabase.from('profiles').upsert(
    { id: userId, display_name: 'Title Equip User', fitness_level: 'intermediate' },
    { onConflict: 'id' },
  );

  // Chest at rank 5 (290 XP — above the 278.46 XP threshold).
  const bodyParts = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  for (const bp of bodyParts) {
    const xp = bp === 'chest' ? 290 : 0;
    const rank = bp === 'chest' ? 5 : 1;
    await supabase.from('body_part_progress').upsert(
      { user_id: userId, body_part: bp, total_xp: xp, rank },
      { onConflict: 'user_id,body_part' },
    );
  }

  // Seed the chest R5 title directly in earned_titles.
  // Slug: 'chest_r5_initiate_of_the_forge' (rank 5 chest title per titles_v1.json).
  // is_active = false so the test can equip it and verify the badge updates.
  const earnedAt = new Date(Date.now() - 3_600_000).toISOString();
  const { error: titleError } = await supabase.from('earned_titles').insert({
    user_id: userId,
    title_id: 'chest_r5_initiate_of_the_forge',
    earned_at: earnedAt,
    is_active: false,
  });
  if (titleError) {
    console.log(`[global-setup] Warning: could not seed earned_title for rpgTitleEquipUser: ${titleError.message}`);
  }

  await seedMinimalWorkout(supabase, userId);

  console.log('[global-setup] Seeded rpgTitleEquipUser (chest rank 5, plate_bearer earned but not equipped)');
}

export default globalSetup;
