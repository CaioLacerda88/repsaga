/**
 * E2E test-data reset/seed helpers.
 *
 * Why this file exists
 * --------------------
 * Multiple describe blocks across different spec files share the SAME
 * Supabase test user (e.g. `smokePR`, `rpgFreshUser`). Tests run in
 * alphabetical spec-file order, so a mutation made by `personal-records.spec.ts`
 * leaks into `rank-up-celebration.spec.ts`'s baseline; a mutation made by
 * `rpg-foundation.spec.ts` leaks into `saga.spec.ts`'s baseline; etc.
 *
 * PR #152's e2e debug cycle CONFIRMED two such pollution paths and the audit
 * at `tasks/e2e-pollution-audit.md` documented five more HIGH-risk pairs.
 * The architectural fix (per-worker user isolation) is parked as PROJECT.md
 * Phase 21 — until then, these helpers let individual describe blocks
 * restore canonical state in their `beforeEach` and stay green regardless
 * of prior-spec mutations.
 *
 * FK note
 * -------
 * `personal_records.set_id` is `ON DELETE SET NULL` (migration
 * `00008_fix_personal_records_set_id_fk.sql:43-45`), NOT cascade. Deleting
 * sets does NOT remove their PR rows — it nulls the link. If your reset
 * needs to remove PR rows too, delete `personal_records` explicitly BEFORE
 * deleting sets / workout_exercises / workouts.
 *
 * `workouts → workout_exercises → sets` ARE all `ON DELETE CASCADE`
 * (`00001_initial_schema.sql:84,94`), so deleting a `workouts` row removes
 * its descendants automatically.
 *
 * Scope (this file)
 * -----------------
 * - getAdminClient / getUserIdByEmail — primitives the spec files use to
 *   reach Supabase as the service role. Single source of truth; spec files
 *   import these instead of re-defining their own.
 * - resetExerciseHistoryForUser — surgical reset of one (user, exercise)
 *   pair (PRs + peak_loads + sets + workout_exercises + workouts that ONLY
 *   contained that exercise). Retained for potential reuse; no longer
 *   called from `rank-up-celebration.spec.ts` post-Phase-21 (the unbeatable-
 *   weight tactic in that spec replaced the surgical reset, and Phase 21's
 *   per-worker user isolation removes the cross-spec pollution this helper
 *   was designed to neutralise).
 * - seedPrForUser — re-establishes a canonical PR after a reset. Sibling to
 *   `seedPRData` in `global-setup.ts` but parameterised + uses a different
 *   sentinel name ('E2E Reset Seed') for idempotency. Retained for reuse.
 * - resetRpgStateForUser — clears workouts + xp + body_part_progress +
 *   backfill_progress + exercise_peak_loads + personal_records for a user.
 *   Still in active use by `saga.spec.ts` to fix INTRA-worker
 *   rpg-foundation→saga pollution (Phase 21 fixes cross-worker, not
 *   intra-worker pollution between sequential spec files on one worker).
 *
 * Tier 2 (locale bleed, offline-sync) was DEFERRED and then subsumed by
 * Phase 21's per-worker isolation. Do NOT add Tier 2 helpers here.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';

/**
 * Construct an admin Supabase client using the service-role key.
 *
 * Reads `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` from the environment
 * (set by `dotenv` in `global-setup.ts` against `test/e2e/.env.local`).
 * Falls back to the local-supabase defaults so spec files can import this
 * factory without re-doing the env wiring.
 */
export function getAdminClient(): SupabaseClient {
  const url = process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
  const serviceKey =
    process.env['SUPABASE_SERVICE_ROLE_KEY'] ??
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' +
      '.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0' +
      '.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/**
 * Look up a user ID by email via the auth admin API.
 * Returns null if the user does not exist (helpers no-op in that case
 * so a missing test user can't crash a beforeEach).
 */
export async function getUserIdByEmail(
  admin: SupabaseClient,
  email: string,
): Promise<string | null> {
  // perPage: 1000 — Phase 21 creates ~168 users (workers × roles), and the
  // GoTrue default of 50 silently truncates the result set. Without
  // explicit perPage, .find() misses any user on page 2+.
  const { data } = await admin.auth.admin.listUsers({ perPage: 1000 });
  const user = data?.users?.find((u) => u.email === email);
  return user?.id ?? null;
}

/**
 * Resolve an exercise's UUID from its slug. Slug is the stable join key
 * (the `name` column was dropped in Phase 15f migration 00034).
 */
async function getExerciseIdBySlug(
  admin: SupabaseClient,
  slug: string,
): Promise<string | null> {
  const { data } = await admin
    .from('exercises')
    .select('id')
    .eq('slug', slug)
    .eq('is_default', true)
    .limit(1);
  return data?.[0]?.id ?? null;
}

/**
 * Surgical reset for one (user, exercise) pair.
 *
 * Removes PR rows + peak loads + every set/workout-exercise targeting
 * that exercise. Workouts are removed only if they end up containing
 * NO other exercises after the workout-exercise deletion — multi-exercise
 * workouts that happen to touch this exercise are preserved (their other
 * `workout_exercises` rows stay intact, and the workout row stays).
 *
 * Idempotent: safe to call when no rows exist for the (user, exercise)
 * pair. Logs a single summary line at the end so a failing test can
 * identify which seed state it actually started from.
 *
 * Deletion order (FK-safe):
 *   1. personal_records  — removed explicitly because set_id is
 *      ON DELETE SET NULL, not cascade.
 *   2. exercise_peak_loads — independent table, no FK to sets.
 *   3. sets — selected via the `workout_exercises` join (subquery);
 *      cascades nothing else.
 *   4. workout_exercises — removes the exercise→workout link rows.
 *      Each row's deletion does NOT cascade to its parent workout.
 *   5. workouts — only those owned by `userId` that no longer have any
 *      remaining `workout_exercises` rows after step 4. ANY orphan
 *      workout owned by this user is removed (not just ones tied to
 *      `exerciseSlug`); leftover empty workouts from earlier surgical
 *      resets would only confuse downstream assertions.
 */
export async function resetExerciseHistoryForUser(
  admin: SupabaseClient,
  userId: string,
  exerciseSlug: string,
): Promise<void> {
  const exerciseId = await getExerciseIdBySlug(admin, exerciseSlug);
  if (!exerciseId) {
    console.log(
      `[test-reset] Warning: exercise slug '${exerciseSlug}' not found; skipping reset for ${userId}`,
    );
    return;
  }

  // 1. Delete PR rows for (user, exercise). These reference sets via
  //    set_id ON DELETE SET NULL — if we deleted sets first, the PR
  //    rows would survive with null set_id and still drive the PR
  //    resolver (the resolver reads value/record_type/exercise_id; it
  //    does not need set_id). Delete PRs explicitly.
  const { count: prCount } = await admin
    .from('personal_records')
    .delete({ count: 'exact' })
    .eq('user_id', userId)
    .eq('exercise_id', exerciseId);

  // 2. Delete peak loads for (user, exercise). Independent — no FK to sets.
  await admin
    .from('exercise_peak_loads')
    .delete()
    .eq('user_id', userId)
    .eq('exercise_id', exerciseId);

  // 3. Find all workout_exercise IDs for this user × exercise so we
  //    can scope the sets DELETE through them. Doing this in two
  //    queries (lookup → delete) is more portable than relying on
  //    PostgREST's nested-DELETE semantics.
  const { data: wxRows } = await admin
    .from('workout_exercises')
    .select('id, workout_id, workouts!inner(user_id)')
    .eq('exercise_id', exerciseId)
    .eq('workouts.user_id', userId);

  const wxIds = (wxRows ?? []).map((r: { id: string }) => r.id);
  const workoutIds = Array.from(
    new Set(
      (wxRows ?? []).map((r: { workout_id: string }) => r.workout_id),
    ),
  );

  let setCount = 0;
  if (wxIds.length > 0) {
    const { count } = await admin
      .from('sets')
      .delete({ count: 'exact' })
      .in('workout_exercise_id', wxIds);
    setCount = count ?? 0;

    // 4. Delete the workout_exercises rows themselves.
    await admin.from('workout_exercises').delete().in('id', wxIds);
  }

  // 5. Delete workouts owned by this user that have no remaining
  //    workout_exercises rows. We constrain to the workout IDs we just
  //    touched so we don't accidentally drop a wholly unrelated empty
  //    workout the user happened to have on file.
  let workoutCount = 0;
  if (workoutIds.length > 0) {
    const { data: stillReferenced } = await admin
      .from('workout_exercises')
      .select('workout_id')
      .in('workout_id', workoutIds);
    const referenced = new Set(
      (stillReferenced ?? []).map(
        (r: { workout_id: string }) => r.workout_id,
      ),
    );
    const orphans = workoutIds.filter((id) => !referenced.has(id));
    if (orphans.length > 0) {
      const { count } = await admin
        .from('workouts')
        .delete({ count: 'exact' })
        .eq('user_id', userId)
        .in('id', orphans);
      workoutCount = count ?? 0;
    }
  }

  console.log(
    `[test-reset] cleared ${prCount ?? 0} PRs, ${setCount} sets, ${workoutCount} workouts for ${userId} ${exerciseSlug}`,
  );
}

/**
 * Insert a single max_weight PR row plus the supporting workout/set
 * chain so the PR resolver has a concrete set to attribute the record
 * to. Mirrors `seedPRData` in `global-setup.ts` but parameterised.
 *
 * Idempotent: a workout named 'E2E Reset Seed' for this user is treated
 * as the sentinel; if one already exists the seed is skipped (matches
 * `seedPRData`'s behaviour with 'E2E Seed Workout').
 *
 * Inserts a max_weight personal record at (weight, reps). Use this AFTER
 * `resetExerciseHistoryForUser` to re-establish a known baseline that
 * the test's PR-breaker set then beats.
 */
export async function seedPrForUser(
  admin: SupabaseClient,
  userId: string,
  exerciseSlug: string,
  weight: number,
  reps: number,
): Promise<void> {
  const exerciseId = await getExerciseIdBySlug(admin, exerciseSlug);
  if (!exerciseId) {
    console.log(
      `[test-reset] Warning: exercise slug '${exerciseSlug}' not found; skipping PR seed for ${userId}`,
    );
    return;
  }

  // Idempotency check — a prior reset+seed cycle on the same describe
  // block should be a no-op.
  const { data: existing } = await admin
    .from('workouts')
    .select('id')
    .eq('user_id', userId)
    .eq('name', 'E2E Reset Seed')
    .maybeSingle();
  if (existing) {
    return;
  }

  const now = new Date();
  const startedAt = new Date(now.getTime() - 60 * 60 * 1000);
  const finishedAt = new Date(now.getTime() - 30 * 60 * 1000);

  const { data: workout, error: wErr } = await admin
    .from('workouts')
    .insert({
      user_id: userId,
      name: 'E2E Reset Seed',
      started_at: startedAt.toISOString(),
      finished_at: finishedAt.toISOString(),
      duration_seconds: 1800,
    })
    .select('id')
    .single();
  if (wErr || !workout) {
    console.log(
      `[test-reset] Warning: failed to insert seed workout for ${userId}: ${wErr?.message}`,
    );
    return;
  }

  const { data: wx, error: wxErr } = await admin
    .from('workout_exercises')
    .insert({
      workout_id: workout.id,
      exercise_id: exerciseId,
      order: 0,
    })
    .select('id')
    .single();
  if (wxErr || !wx) {
    console.log(
      `[test-reset] Warning: failed to insert seed workout_exercise for ${userId}: ${wxErr?.message}`,
    );
    return;
  }

  const { data: set, error: setErr } = await admin
    .from('sets')
    .insert({
      workout_exercise_id: wx.id,
      set_number: 1,
      reps,
      weight,
      set_type: 'working',
      is_completed: true,
    })
    .select('id')
    .single();
  if (setErr || !set) {
    console.log(
      `[test-reset] Warning: failed to insert seed set for ${userId}: ${setErr?.message}`,
    );
    return;
  }

  const { error: prErr } = await admin.from('personal_records').insert({
    user_id: userId,
    exercise_id: exerciseId,
    record_type: 'max_weight',
    value: weight,
    reps,
    achieved_at: finishedAt.toISOString(),
    set_id: set.id,
  });
  if (prErr) {
    console.log(
      `[test-reset] Warning: failed to insert seed personal_record for ${userId}: ${prErr.message}`,
    );
    return;
  }

  console.log(
    `[test-reset] seeded ${weight}kg×${reps} ${exerciseSlug} PR for ${userId}`,
  );
}

/**
 * Reset full RPG state for a user back to the "fresh user" baseline.
 *
 * Used by `saga.spec.ts:63` ("Saga — fresh user character sheet") and
 * `saga.spec.ts:387` ("Saga — stats deep-dive (fresh user)") to cancel
 * out workouts written by `rpg-foundation.spec.ts` (E2/E3/E6) into the
 * shared `rpgFreshUser`. The original inline cleanups in those describe
 * blocks deleted xp_events / body_part_progress / exercise_peak_loads /
 * backfill_progress but NOT `workouts` — meaning the surviving workout
 * rows re-triggered `backfill_rpg_v1` on the next login (because
 * backfill_progress was cleared) and re-wrote XP into body_part_progress
 * before the saga screen rendered. Result: zero-history banner missing,
 * S1 fails.
 *
 * This helper deletes:
 *   - workouts (cascades to workout_exercises → sets via FK)
 *   - personal_records (set_id is ON DELETE SET NULL, not cascade —
 *     must be deleted explicitly to keep the user pristine)
 *   - exercise_peak_loads
 *   - xp_events
 *   - body_part_progress
 *   - backfill_progress
 *   - earned_titles
 *   - weekly_plans (mirrors `reseedRpgFreshUser` in rank-up-celebration:
 *     prevents lingering plan rows from interfering with quick-workout
 *     CTA flow assertions)
 *
 * Then upserts a backfill_progress row marked as completed so the
 * SagaIntroGate's `runRetroBackfill` is a no-op on next login (no
 * surviving workout to backfill from).
 *
 * Idempotent.
 */
export async function resetRpgStateForUser(
  admin: SupabaseClient,
  userId: string,
): Promise<void> {
  // Order: PRs first (set_id is SET NULL, not cascade), then workouts
  // (which cascades to workout_exercises → sets), then everything else.
  await admin.from('personal_records').delete().eq('user_id', userId);
  await admin.from('workouts').delete().eq('user_id', userId);
  await admin.from('xp_events').delete().eq('user_id', userId);
  await admin.from('body_part_progress').delete().eq('user_id', userId);
  await admin.from('exercise_peak_loads').delete().eq('user_id', userId);
  await admin.from('earned_titles').delete().eq('user_id', userId);
  await admin.from('backfill_progress').delete().eq('user_id', userId);
  await admin.from('weekly_plans').delete().eq('user_id', userId);

  // Re-seed backfill_progress as completed so the next login does NOT
  // trigger a retro backfill (the user has no workouts, so backfill
  // would be a no-op anyway, but suppressing it removes one source of
  // racing writes during the saga screen's first paint).
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

  console.log(`[test-reset] reset RPG state for ${userId}`);
}
