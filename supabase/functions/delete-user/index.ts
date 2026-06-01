// Supabase Edge Function: delete-user
//
// Permanently deletes the calling user's auth record. All user-owned rows in
// public tables cascade via FK (ON DELETE CASCADE), so this single call
// removes the account and every piece of data tied to it.
//
// Before the delete runs, the function writes a row to
// `account_deletion_events` — an anonymous audit stream used for churn
// metrics. The row has no user_id (intentional: GDPR-clean) and carries
// only aggregate props: workout_count and days_since_signup. This happens
// inside the function because a client-side insert would be wiped by the
// CASCADE a few milliseconds later.
//
// The function is invoked from the Flutter app via
// `supabase.functions.invoke('delete-user')`. Supabase-js automatically
// attaches the caller's JWT as `Authorization: Bearer <jwt>` — we verify that
// token with a user-scoped client, then switch to a service-role client to
// perform the admin delete (auth.admin.deleteUser requires elevated perms).
//
// Optional POST body: `{ "platform": "android", "app_version": "1.2.3" }`
// Both fields are stored in the deletion event after normalization:
//   * platform — must be one of {'android','ios','web'}; out-of-list
//     values coerce to 'unknown' (best-effort audit; spec rejects 400
//     because the audit row is non-critical). Finding-031.
//   * app_version — must match `^\d+\.\d+\.\d+(\+\d+)?$`; non-matching
//     values are stripped to null. Finding-031.
// The function tolerates an empty body.
//
// Phase 33 PR 33a defense-in-depth (findings 028 / 030 / 031):
//   * 4KB Content-Length cap via requireBodySize (finding-028)
//   * JWT exp precheck BEFORE req.json() via precheckJwtExp (finding-030)
//   * platform allow-list + app_version regex (finding-031)
//
// Required environment variables (set automatically by Supabase for every
// Edge Function):
//   - SUPABASE_URL
//   - SUPABASE_ANON_KEY
//   - SUPABASE_SERVICE_ROLE_KEY

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { precheckJwtExp, requireBodySize } from '../_shared/auth.ts';

// CORS: restrict to the Supabase project URL only. The Flutter app invokes
// this function via `supabase.functions.invoke` (SDK call, no browser CORS),
// so we do NOT need a wildcard. Pinning to SUPABASE_URL keeps the function
// invokable from the local Supabase Studio / dashboard while blocking
// arbitrary cross-origin callers.
const allowedOrigin = Deno.env.get('SUPABASE_URL') ?? '';
const corsHeaders = {
  'Access-Control-Allow-Origin': allowedOrigin,
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  Vary: 'Origin',
};

// Maximum byte length for the optional client-supplied metadata fields
// (platform, app_version). Anything longer is clamped — prevents a bad
// client from stuffing PII-bearing strings into audit rows. This clamp
// is the LEGACY first line of defense; the platform allow-list and
// app_version regex below (finding-031) replace it for valid-content
// validation but the byte cap stays as a coarse safety net.
const MAX_METADATA_LEN = 64;

// 4KB request-body cap (finding-028). The actual delete-user payload is
// two short strings (≤ 200 bytes total in production), so 4KB is two
// orders of magnitude of headroom.
const MAX_BODY_BYTES = 4 * 1024;

/** Allowed `platform` values for the audit row. Anything else coerces to
 * 'unknown' (best-effort audit per finding-031 — the row is non-critical
 * so we don't reject the whole delete on a bad metadata field). */
const PLATFORM_ALLOW_LIST = ['android', 'ios', 'web'] as const;

/** Semver regex: `MAJOR.MINOR.PATCH` optionally followed by `+BUILD` (an
 * integer build number, matching the Flutter convention in `pubspec.yaml`
 * — `version: 1.2.3+45`). Non-matching values are stripped to null in
 * the audit row (finding-031). */
const APP_VERSION_RE = /^\d+\.\d+\.\d+(\+\d+)?$/;

function clampMeta(value: string): string {
  return value.length > MAX_METADATA_LEN
    ? value.slice(0, MAX_METADATA_LEN)
    : value;
}

/** Normalize the caller-supplied platform string per finding-031.
 *  Returns 'unknown' for any value not in the allow-list. */
function normalizePlatform(raw: string): string {
  const clamped = clampMeta(raw);
  return (PLATFORM_ALLOW_LIST as readonly string[]).includes(clamped)
    ? clamped
    : 'unknown';
}

/** Normalize the caller-supplied app_version string per finding-031.
 *  Returns null for any non-matching value. */
function normalizeAppVersion(raw: string): string | null {
  const clamped = clampMeta(raw);
  return APP_VERSION_RE.test(clamped) ? clamped : null;
}

// --- HTTP boundary (extracted for unit testability) -----------------------

export interface HandleRequestDeps {
  adminClient: SupabaseClient;
  userClient: SupabaseClient;
}

export async function handleRequest(
  req: Request,
  deps: HandleRequestDeps,
): Promise<Response> {
  // Preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 1. App-level body-size cap (finding-028). Reject 4KB+ payloads before
  //    any other work — even before reading env vars.
  const tooBig = requireBodySize(req, MAX_BODY_BYTES, corsHeaders);
  if (tooBig) return tooBig;

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: 'Missing Authorization header' }, 401);
    }
    const jwt = authHeader.replace('Bearer ', '');

    // 2. JWT exp precheck (finding-030). Reject expired/malformed JWTs
    //    BEFORE paying the req.json() body-parse cost.
    const precheck = precheckJwtExp(jwt);
    if (!precheck.valid) {
      return json({ error: 'Invalid or expired token', reason: precheck.reason }, 401);
    }

    // 3. Parse optional POST body for platform / app_version. A missing or
    //    malformed body is tolerated — we just write NULLs for those columns.
    //    Both fields are NORMALIZED through the allow-list / regex per
    //    finding-031 (best-effort audit hygiene).
    let platform: string | null = null;
    let appVersion: string | null = null;
    try {
      if (req.headers.get('content-type')?.includes('application/json')) {
        const body = await req.json();
        if (typeof body?.platform === 'string') {
          platform = normalizePlatform(body.platform);
        }
        if (typeof body?.app_version === 'string') {
          appVersion = normalizeAppVersion(body.app_version);
        }
      }
    } catch (_) {
      // Ignore parse errors — body is optional.
    }

    // Verify the caller's JWT by reading their user record.
    const {
      data: { user },
      error: getUserError,
    } = await deps.userClient.auth.getUser(jwt);
    if (getUserError || !user) {
      return json({ error: 'Invalid or expired token' }, 401);
    }

    // --- 1. Record the deletion event BEFORE deleting the user ---
    //
    // Best-effort: if anything fails here we still proceed with the delete.
    // The audit row is valuable but not worth blocking the user's explicit
    // erasure request. The count query and the audit insert live in
    // SEPARATE try blocks so a transient failure of the count query cannot
    // swallow the audit row — we fall back to `null` for workout_count and
    // still write the event.

    // 1a. Finished workout count for this user (nullable fallback).
    let workoutCount: number | null = null;
    try {
      const { count } = await deps.adminClient
        .from('workouts')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', user.id)
        .not('finished_at', 'is', null);
      workoutCount = count ?? 0;
    } catch (_) {
      // Transient count failure — leave as null so the audit row still ships.
    }

    // 1b. Days since signup, floored. Pure computation, no I/O, no try needed.
    const createdAtIso = user.created_at;
    let daysSinceSignup = 0;
    if (createdAtIso) {
      const createdAt = new Date(createdAtIso);
      if (!Number.isNaN(createdAt.getTime())) {
        daysSinceSignup = Math.floor(
          (Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24),
        );
      }
    }

    // 1c. Insert the audit row. Separate try so 1a failing cannot skip this.
    try {
      await deps.adminClient.from('account_deletion_events').insert({
        props: {
          workout_count: workoutCount,
          days_since_signup: daysSinceSignup,
        },
        platform,
        app_version: appVersion,
      });
    } catch (_) {
      // Swallow and continue to the delete. Audit failure must never block
      // the user's explicit erasure request.
    }

    // --- 2. Delete the user ---
    //
    // All user data in public.* tables cascades via FK constraints.
    const { error: deleteError } = await deps.adminClient.auth.admin.deleteUser(
      user.id,
    );
    if (deleteError) {
      return json({ error: deleteError.message }, 500);
    }

    return json({ success: true }, 200);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'Unknown error' }, 500);
  }
}

serve(async (req) => {
  // OPTIONS preflight handled inside handleRequest too — answer here as
  // a belt-and-suspenders so a misconfigured env still gives a clean
  // CORS preflight response.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: 'Server misconfigured' }, 500);
  }

  // Build the per-request user client (Authorization header forwarded by
  // Supabase before our code runs).
  const authHeader = req.headers.get('Authorization') ?? '';
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return handleRequest(req, { adminClient, userClient });
});

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
