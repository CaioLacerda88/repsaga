/**
 * Worker-scoped E2E user factory (Phase 21).
 *
 * # Why this exists
 *
 * Pre-Phase-21, every test file shared a single static pool of users defined in
 * `test-users.ts` (e.g., `e2e-smoke-pr@test.local`). With `workers: 2`, two
 * Playwright workers could simultaneously claim tests pointing at the same
 * underlying Supabase user — and one worker's `beforeEach` reset routinely
 * wiped state mid-execution of the other worker's test. CI sometimes won the
 * race, sometimes lost (see `tasks/e2e-pollution-audit.md` for the audit).
 *
 * Phase 20 shipped Tier 1 cleanup (per-test reset for the worst pairs) to
 * unblock CI. Phase 21 is the architectural fix: each worker gets its own
 * private copy of every user role, keyed by `process.env.TEST_PARALLEL_INDEX`.
 *
 * # Worker-index resolution
 *
 * Playwright sets `TEST_PARALLEL_INDEX=0..N-1` per worker process at runtime.
 * Inside the worker process, `getUser('smokePR')` resolves to:
 *
 *     { email: 'smokePR_w0@test.local', password: TEST_USER_PASSWORD }
 *
 * for worker 0, and `_w1`, `_w2`, `_w3` for workers 1-3.
 *
 * Code that runs OUTSIDE a worker process — namely `global-setup.ts` and
 * `global-teardown.ts` — also reads this helper. In those phases
 * `TEST_PARALLEL_INDEX` is undefined, so `getUser()` defaults to `'0'` (a
 * sane fallback for ad-hoc single-worker invocations). Setup iterates all
 * worker indices explicitly via `getEmailPattern()` + a known workers count,
 * not via `getUser()`, so the default never matters in practice.
 *
 * # How it eliminates cross-worker races
 *
 * Two workers can never resolve to the same email. `smokePR_w0` and
 * `smokePR_w1` are distinct Supabase auth rows with distinct user_ids and
 * fully independent body_part_progress / xp_events / workouts trees. A
 * `beforeEach` reset on worker 0's user is invisible to worker 1.
 *
 * Concurrent races on the same user are structurally impossible — not
 * mitigated, not best-effort, but eliminated at the data-shape level.
 *
 * # Lifecycle
 *
 * - `global-setup.ts` enumerates `[0..workers-1] × getAllUserKeys()` and
 *   creates each `{role}_w{index}@test.local` via the Supabase Admin API,
 *   then applies the same per-user seed data per (worker, role) pair.
 * - Each spec file calls `getUser('roleName').email` instead of the legacy
 *   `TEST_USERS.roleName.email`. The lookup is constant-time (string concat).
 * - `global-teardown.ts` deletes every auth user whose email matches
 *   `getEmailPattern()` (`/_w\d+@test\.local$/`).
 */

import { TEST_USERS } from './test-users';

export type TestUserKey = keyof typeof TEST_USERS;

/**
 * Default worker index for invocations outside a Playwright worker process
 * (e.g., manual scripts, single-worker local runs, global-setup before any
 * worker exists). Inside a worker, `process.env.TEST_PARALLEL_INDEX` is
 * always set by Playwright.
 */
const DEFAULT_WORKER_INDEX = '0';

/**
 * The shared password used by every E2E test user. Sourced from
 * `TEST_USER_PASSWORD` in `test/e2e/.env.local` (mirrored to the static
 * fixture object for backwards-compat). All worker-scoped users share the
 * same password — only the email varies.
 */
const TEST_USER_PASSWORD = 'TestPassword123!';

/**
 * Return the worker-scoped credentials for the given role on the current
 * Playwright worker.
 *
 * In a worker process: reads `TEST_PARALLEL_INDEX` and returns
 * `{role}_w{index}@test.local`.
 *
 * Outside a worker (global-setup/teardown, ad-hoc scripts): returns the
 * `_w0` variant. Setup code that needs to enumerate every (worker, role)
 * pair should iterate `[0..workers-1]` explicitly and build emails with
 * `buildEmailForWorker(role, index)` instead of relying on the default.
 */
export function getUser(role: TestUserKey): {
  email: string;
  password: string;
} {
  const index = process.env['TEST_PARALLEL_INDEX'] ?? DEFAULT_WORKER_INDEX;
  return {
    email: buildEmailForWorker(role, Number.parseInt(index, 10)),
    password: TEST_USER_PASSWORD,
  };
}

/**
 * Build the worker-scoped email for an arbitrary worker index. Used by
 * global-setup to create users for workers 0..N-1 from the controller
 * process (where `TEST_PARALLEL_INDEX` is unset).
 *
 * Always returns a fully-lowercase email. Supabase Auth (GoTrue) silently
 * lowercases the email on storage, so any case-sensitive comparison
 * (e.g., `userList.users.find(u => u.email === buildEmailForWorker(...))`)
 * would mismatch when the role key contains uppercase letters
 * (e.g., `rpgFoundationUser`). By lowercasing here, both sides of every
 * comparison use the same canonical form.
 */
export function buildEmailForWorker(
  role: TestUserKey,
  workerIndex: number,
): string {
  return `${role.toLowerCase()}_w${workerIndex}@test.local`;
}

/**
 * All known role keys. Used by global-setup to iterate every role per
 * worker, and by tests as a sanity-check against typos.
 */
export function getAllUserKeys(): TestUserKey[] {
  return Object.keys(TEST_USERS) as TestUserKey[];
}

/**
 * Regex matching every worker-scoped email (across all worker indices and
 * all roles). Used by global-teardown to scan-and-delete in one pass
 * without enumerating the exact role × worker matrix.
 *
 * Matches lowercased forms: `smokepr_w0@test.local`, `rpgfreshuser_w3@test.local`.
 * Does NOT match: legacy static emails like `e2e-smoke-pr@test.local`.
 *
 * Stored emails are always lowercase (Supabase Auth lowercases on insert),
 * so a lowercase regex is sufficient. The `[a-z]` anchor before `_w` keeps
 * us from matching unrelated patterns like `:8080/test.local` if any
 * non-test email contained `_wN@test.local`.
 */
export function getEmailPattern(): RegExp {
  return /[a-z]_w\d+@test\.local$/;
}
