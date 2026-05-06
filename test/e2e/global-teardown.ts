/**
 * Playwright global teardown — deletes E2E test users via Supabase Admin Auth API.
 *
 * Runs once after all tests complete. Phase 21: identifies test users by
 * the worker-scoped email pattern '{role}_w{N}@test.local' (regex from
 * fixtures/worker-users.ts) and deletes them in parallel.
 *
 * Before deleting each user from auth, all user-owned data is deleted from
 * dependent tables in the correct FK order to avoid constraint violations.
 *
 * Errors during individual user deletion are logged but do not fail teardown
 * so that all users are attempted even if one fails.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { getEmailPattern } from './fixtures/worker-users';

dotenv.config({ path: path.join(__dirname, '.env.local') });

/**
 * Delete all user-owned data from dependent tables before deleting the auth user.
 *
 * The deletion order respects FK constraints:
 *   1. sets (via workout_exercises -> workouts)
 *   2. workout_exercises (via workouts)
 *   3. personal_records
 *   4. workouts
 *   5. weekly_plans
 *   6. workout_templates (user-created only)
 *   7. exercises (user-created only, is_default = false)
 *   8. profiles
 *
 * Uses the service-role key which bypasses RLS.
 */
async function deleteUserData(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  try {
    // 1. Get user's workout IDs
    const { data: workouts } = await supabase
      .from('workouts')
      .select('id')
      .eq('user_id', userId);
    const workoutIds = workouts?.map((w) => w.id) ?? [];

    if (workoutIds.length > 0) {
      // 2. Get workout_exercise IDs for this user's workouts
      const { data: wxs } = await supabase
        .from('workout_exercises')
        .select('id')
        .in('workout_id', workoutIds);
      const wxIds = wxs?.map((wx) => wx.id) ?? [];

      // 3. Delete sets belonging to those workout_exercises
      if (wxIds.length > 0) {
        await supabase.from('sets').delete().in('workout_exercise_id', wxIds);
      }

      // 4. Delete workout_exercises
      await supabase
        .from('workout_exercises')
        .delete()
        .in('workout_id', workoutIds);
    }

    // 5. Delete personal_records
    await supabase.from('personal_records').delete().eq('user_id', userId);

    // 6. Delete workouts
    await supabase.from('workouts').delete().eq('user_id', userId);

    // 7. Delete weekly_plans
    await supabase.from('weekly_plans').delete().eq('user_id', userId);

    // 8. Delete workout_templates (user-created only)
    await supabase.from('workout_templates').delete().eq('user_id', userId);

    // 9. Delete user-created exercises (is_default = false)
    await supabase
      .from('exercises')
      .delete()
      .eq('user_id', userId)
      .eq('is_default', false);

    // 10. Delete XP ledger (Phase 17b)
    await supabase.from('xp_events').delete().eq('user_id', userId);
    await supabase.from('user_xp').delete().eq('user_id', userId);

    // 11. Delete profile
    await supabase.from('profiles').delete().eq('id', userId);
  } catch (err) {
    console.error(
      `[global-teardown] Error deleting data for user ${userId}: ${err}`,
    );
  }
}

async function globalTeardown(): Promise<void> {
  const supabaseUrl = process.env['SUPABASE_URL'];
  const serviceRoleKey = process.env['SUPABASE_SERVICE_ROLE_KEY'];

  if (!supabaseUrl || !serviceRoleKey) {
    console.warn(
      '[global-teardown] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY — ' +
        'skipping test user cleanup.',
    );
    return;
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const pattern = getEmailPattern();
  console.log(
    `[global-teardown] Listing users matching ${pattern} ...`,
  );

  // List all users — local Supabase typically has few users so one page is enough.
  const { data: listData, error: listError } =
    await supabase.auth.admin.listUsers({ perPage: 1000 });

  if (listError) {
    console.error(
      `[global-teardown] Failed to list users: ${listError.message}`,
    );
    return;
  }

  const testUsers = listData.users.filter(
    (u) => typeof u.email === 'string' && pattern.test(u.email),
  );

  if (testUsers.length === 0) {
    console.log(
      '[global-teardown] No worker-scoped E2E test users found — nothing to clean up.',
    );
    return;
  }

  console.log(
    `[global-teardown] Deleting ${testUsers.length} worker-scoped user(s) in parallel...`,
  );

  // Per-user deletion: clean owned rows first (FK-ordered), then auth user.
  // Errors are caught per-user so one failure doesn't block the rest.
  const results = await Promise.allSettled(
    testUsers.map(async (user) => {
      await deleteUserData(supabase, user.id);
      const { error } = await supabase.auth.admin.deleteUser(user.id);
      if (error) {
        throw new Error(
          `Failed to delete ${user.email} (${user.id}): ${error.message}`,
        );
      }
      return user.email ?? user.id;
    }),
  );

  const successes = results.filter((r) => r.status === 'fulfilled').length;
  const failures = results.filter((r) => r.status === 'rejected');
  for (const failure of failures) {
    console.error(`[global-teardown] ${(failure as PromiseRejectedResult).reason}`);
  }

  console.log(
    `[global-teardown] Deleted ${successes}/${testUsers.length} users matching ${pattern}` +
      (failures.length > 0 ? ` (${failures.length} failed)` : ''),
  );
}

export default globalTeardown;
