// Supabase Edge Function: vitality-nightly
//
// Phase 18d Stage 1 — nightly Vitality EWMA recompute.
//
// Triggered once per UTC day at 03:00 by `cron.schedule('vitality_nightly_03utc', ...)`
// (see migration 00042). Service-role-only — anonymous and end-user JWTs are
// rejected at the Authorization gate. The cron job sets the Authorization
// header to `Bearer <service_role_key>` sourced from Vault. The role check
// decodes the JWT payload claim (see `isServiceRoleJwt`); it does NOT
// string-compare against `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`, which
// is unreliable under Supabase's new API key system (see comment block on
// `isServiceRoleJwt` below for the rationale).
//
// Behavior per user (spec §8.1, §12.2):
//   1. INSERT INTO vitality_runs (user_id, run_date) FIRST.
//      A duplicate (PRIMARY KEY conflict) means we already ran this user
//      for the current UTC day — short-circuit, no further work.
//   2. For each of the six v1 strength body parts compute
//        weekly_volume[bp] = SUM((attribution ->> bp)::numeric)
//                            FROM xp_events
//                            WHERE user_id = ? AND occurred_at > now() - 7d
//      The `attribution` jsonb already stores the post-multiplier per-bp
//      XP contribution — that IS the volume measure the EWMA tracks
//      (spec §8.1: "weekly_volume[bp] = SUM(attribution[bp] × volume_load)";
//      our `attribution[bp]` field is the per-bp set_xp share which is
//      proportional to volume_load × proportion, so it's the same signal).
//   3. Apply asymmetric EWMA:
//        α_up   = 1 - exp(-7/14) ≈ 0.3935  when weekly_volume >= prior_ewma
//        α_down = 1 - exp(-7/42) ≈ 0.1535  otherwise
//        new_ewma = α × weekly_volume + (1-α) × prior_ewma
//        new_peak = max(prior_peak, new_ewma)
//   4. UPSERT body_part_progress {vitality_ewma, vitality_peak, updated_at}.
//
// Idempotency:
//   * vitality_runs PRIMARY KEY (user_id, run_date) is the dedup gate.
//   * The per-user transaction is small enough to retry as a unit; if it
//     fails halfway, the next nightly run finds no vitality_runs row and
//     re-attempts.
//
// Performance (spec §12.3 budget: <10min for 100k users):
//   * Optional `{ chunk: number (0-9) }` body param shards by `user_id % 10`.
//     Cron submits a single un-chunked invocation today; chunking is wired
//     for future operator-driven scale-out.
//   * Per-user work is one SELECT (xp_events aggregation), one INSERT
//     (vitality_runs), and 1-6 UPSERTs (body_part_progress). All
//     index-backed.
//
// Env vars (Supabase sets the first two automatically):
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Fail-loud on missing env at module load — a deployment without
// SUPABASE_URL is broken and we want a boot error, not a silent
// blank Allow-Origin (matches the rtdn-webhook / validate-purchase pattern).
const allowedOrigin = (() => {
  const u = Deno.env.get('SUPABASE_URL');
  if (!u) throw new Error('SUPABASE_URL is not set');
  return u;
})();
const corsHeaders = {
  'Access-Control-Allow-Origin': allowedOrigin,
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  Vary: 'Origin',
};

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// --- EWMA constants -------------------------------------------------------
//
// Spec §8.1: τ_up = 2 weeks (14 days), τ_down = 6 weeks (42 days). The
// sample period is one week (the rolling weekly-volume window length).
//
//   α_up   = 1 - exp(-Δt / τ_up)   where Δt=7d, τ_up=14d  → ≈ 0.39346934
//   α_down = 1 - exp(-Δt / τ_down) where Δt=7d, τ_down=42d → ≈ 0.15351830
//
// Asymmetry rationale (spec §8.2): myonuclear retention literature
// (Bruusgaard 2010, Seaborne 2018, Psilander 2019) — retraining is
// empirically 2-3× faster than initial acquisition. τ_up < τ_down encodes
// this directly.
//
// Constants are inlined rather than imported from
// `lib/features/rpg/domain/vitality_calculator.dart` because that's Dart
// and the Edge Function is Deno; we re-derive them here from the same
// τ values to keep the formula explicit and auditable. The PG/Dart parity
// integration test (`test/integration/rpg_vitality_nightly_test.dart`)
// pins both producers to the same trajectory.
export const TAU_UP_DAYS = 14.0;
export const TAU_DOWN_DAYS = 42.0;
export const SAMPLE_PERIOD_DAYS = 7.0;
export const ALPHA_UP = 1 - Math.exp(-SAMPLE_PERIOD_DAYS / TAU_UP_DAYS);
export const ALPHA_DOWN = 1 - Math.exp(-SAMPLE_PERIOD_DAYS / TAU_DOWN_DAYS);

/** v1 strength body-parts. Cardio (v2) is intentionally excluded — same
 * `activeBodyParts` set as Dart `lib/features/rpg/models/body_part.dart`. */
export const V1_BODY_PARTS = [
  'chest',
  'back',
  'legs',
  'shoulders',
  'arms',
  'core',
] as const;
export type BodyPart = (typeof V1_BODY_PARTS)[number];

// --- Pure math (testable in isolation) ------------------------------------

export interface EwmaInput {
  priorEwma: number;
  priorPeak: number;
  weeklyVolume: number;
}

export interface EwmaOutput {
  ewma: number;
  peak: number;
}

/**
 * Single-step asymmetric EWMA update. Pure function — no side-effects, no
 * I/O. `priorPeak` is monotone non-decreasing per spec §8.3 (peak is
 * permanent and never decays).
 */
export function stepEwma(input: EwmaInput): EwmaOutput {
  const { priorEwma, priorPeak, weeklyVolume } = input;
  const alpha = weeklyVolume >= priorEwma ? ALPHA_UP : ALPHA_DOWN;
  const newEwma = alpha * weeklyVolume + (1 - alpha) * priorEwma;
  const newPeak = newEwma > priorPeak ? newEwma : priorPeak;
  return { ewma: newEwma, peak: newPeak };
}

// --- Per-user worker (extracted for unit testability) ---------------------

export interface ProcessUserDeps {
  client: SupabaseClient;
  /** Override "today" for tests (UTC date). Production passes nothing. */
  now?: () => Date;
}

export interface ProcessUserResult {
  /** True if the user was processed (vitality_runs row newly inserted). */
  processed: boolean;
  /** True if we found a pre-existing vitality_runs row → no-op. */
  skipped: boolean;
  /** Per-body-part EWMA update results, only populated when processed. */
  updates: Record<BodyPart, EwmaOutput> | null;
}

/**
 * Process one user: claim the (user_id, run_date) idempotency row, compute
 * weekly volume per body part, and UPSERT body_part_progress. Returns the
 * computed updates so the integration test can assert against them
 * directly.
 *
 * Layering: this function ONLY does data access via the supplied
 * `client` — no orchestration, no fan-out. The HTTP boundary in `serve()`
 * is responsible for paginating users and calling this once per user.
 */
export async function processUser(
  userId: string,
  deps: ProcessUserDeps,
): Promise<ProcessUserResult> {
  const now = deps.now ? deps.now() : new Date();
  const runDate = utcDateString(now);

  // 1. Claim the idempotency row. PRIMARY KEY conflict ⇒ already ran today.
  const { error: insErr } = await deps.client
    .from('vitality_runs')
    .insert({ user_id: userId, run_date: runDate });
  if (insErr) {
    if (isUniqueViolation(insErr)) {
      return { processed: false, skipped: true, updates: null };
    }
    throw new Error(`vitality_runs insert failed: ${insErr.message}`);
  }

  // 2. Compute weekly_volume[bp] from xp_events past 7d. Single round-trip:
  //    pull all xp_events.attribution rows for the window and aggregate
  //    in TS. At 50 events/user this is cheaper than 6 server-side SQL
  //    aggregations (one per body part).
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 3600 * 1000);
  const { data: events, error: evErr } = await deps.client
    .from('xp_events')
    .select('attribution')
    .eq('user_id', userId)
    .gte('occurred_at', sevenDaysAgo.toISOString());
  if (evErr) {
    throw new Error(`xp_events fetch failed: ${evErr.message}`);
  }

  const weeklyVolume = aggregateAttribution(events ?? []);

  // 3. Read prior (ewma, peak) for each v1 body part.
  const { data: priorRows, error: prErr } = await deps.client
    .from('body_part_progress')
    .select('body_part, vitality_ewma, vitality_peak')
    .eq('user_id', userId)
    .in('body_part', V1_BODY_PARTS as unknown as string[]);
  if (prErr) {
    throw new Error(`body_part_progress fetch failed: ${prErr.message}`);
  }

  const prior = new Map<string, { ewma: number; peak: number }>();
  for (const row of priorRows ?? []) {
    prior.set(row.body_part as string, {
      ewma: Number(row.vitality_ewma ?? 0),
      peak: Number(row.vitality_peak ?? 0),
    });
  }

  // 4. Apply EWMA per body part and UPSERT.
  const updates: Record<BodyPart, EwmaOutput> = {} as Record<
    BodyPart,
    EwmaOutput
  >;
  for (const bp of V1_BODY_PARTS) {
    const p = prior.get(bp) ?? { ewma: 0, peak: 0 };
    const out = stepEwma({
      priorEwma: p.ewma,
      priorPeak: p.peak,
      weeklyVolume: weeklyVolume[bp] ?? 0,
    });
    updates[bp] = out;

    // UPSERT — leave total_xp/rank untouched. The DO UPDATE only writes
    // vitality_* columns. We use upsert() with onConflict='user_id,body_part'
    // and ignoreDuplicates=false so the row is updated when it exists.
    const { error: upErr } = await deps.client.from('body_part_progress').upsert(
      {
        user_id: userId,
        body_part: bp,
        // numeric(14,4) precision — see 00040 column comment.
        vitality_ewma: out.ewma,
        vitality_peak: out.peak,
        // total_xp and rank are unchanged for an UPSERT against an
        // existing row — supabase-js merges only the supplied keys when
        // ON CONFLICT matches. For a brand-new row (no prior progress)
        // total_xp defaults to 0 and rank to 1 from the schema.
        updated_at: now.toISOString(),
      },
      { onConflict: 'user_id,body_part' },
    );
    if (upErr) {
      throw new Error(
        `body_part_progress upsert failed for ${bp}: ${upErr.message}`,
      );
    }
  }

  return { processed: true, skipped: false, updates };
}

// --- Helpers --------------------------------------------------------------

/**
 * Sum the per-body-part attribution numerators across a batch of xp_events
 * rows. The attribution jsonb is `{chest: 35.0, shoulders: 10.0, ...}` per
 * the 18a record_set_xp contract — values may be missing for body parts
 * that weren't attributed for a given event.
 */
export function aggregateAttribution(
  events: { attribution: Record<string, unknown> | null }[],
): Record<BodyPart, number> {
  const out: Record<BodyPart, number> = {
    chest: 0, back: 0, legs: 0, shoulders: 0, arms: 0, core: 0,
  };
  for (const ev of events) {
    const attr = ev.attribution ?? {};
    for (const bp of V1_BODY_PARTS) {
      const v = (attr as Record<string, unknown>)[bp];
      if (typeof v === 'number') {
        out[bp] += v;
      } else if (typeof v === 'string') {
        // jsonb numerics arrive as `string` from numeric columns through
        // PostgREST when precision exceeds JS safe-int territory; coerce.
        const n = Number(v);
        if (Number.isFinite(n)) out[bp] += n;
      }
    }
  }
  return out;
}

/** "YYYY-MM-DD" in UTC. Matches the `date` column type on `vitality_runs`. */
export function utcDateString(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isUniqueViolation(err: { code?: string; message?: string }): boolean {
  return err.code === '23505' || /duplicate key/i.test(err.message ?? '');
}

// --- Service-role auth gate -----------------------------------------------

/**
 * Returns true if the JWT payload's `role` claim is `service_role`.
 *
 * The Supabase Edge Function runtime has ALREADY cryptographically verified
 * the JWT signature by the time we see it (verify_jwt is on for this
 * function — there is no `[functions.vitality-nightly] verify_jwt = false`
 * in `supabase/config.toml`), so decoding without re-verifying is safe
 * here: we are only reading a claim the runtime already authenticated.
 *
 * We deliberately do NOT compare the raw token against
 * `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` as a bearer secret. That
 * pattern conflates a project secret with an auth token and silently
 * breaks under Supabase's new API key system: `SUPABASE_SERVICE_ROLE_KEY`
 * is now a platform-managed compatibility shim whose runtime value can
 * differ from the legacy JWT a caller (cron, operator) presents in the
 * Authorization header — even when both are valid service-role
 * credentials. String equality 401s in that drift; role-claim decoding
 * accepts every JWT the gateway already accepted.
 *
 * Mirrors the `isServiceRoleJwt` pattern in `validate-purchase/index.ts`
 * (see the comment block there for the original explanation). Keep the
 * two implementations in sync — they are intentionally identical and
 * could be hoisted to `_shared/` if a third caller appears.
 */
export function isServiceRoleJwt(jwt: string): boolean {
  const parts = jwt.split('.');
  if (parts.length < 2) return false;
  const payloadB64 = parts[1];
  if (!payloadB64) return false;
  try {
    // JWT uses base64url without padding. atob wants standard base64
    // with correct padding, so translate `-/_` and re-pad.
    const b64 = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
    const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
    const payload = JSON.parse(atob(b64 + pad)) as { role?: unknown };
    return payload?.role === 'service_role';
  } catch {
    return false;
  }
}

/**
 * Authorization gate. The cron job and operator-driven curl both supply a
 * service-role JWT in `Authorization: Bearer <jwt>`. The gateway verified
 * the signature; we just need to confirm the role claim.
 */
export function authorizeServiceRole(req: Request): boolean {
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return false;
  return isServiceRoleJwt(token);
}

// --- HTTP boundary --------------------------------------------------------

interface InvokeBody {
  /** Optional shard 0..9 — process only users where `user_id % 10 == chunk`. */
  chunk?: number;
  /** Audit-only label echoed by cron ("cron_nightly") or operators ("manual"). */
  source?: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  // 1. Service-role auth. Refuse anonymous or end-user JWTs outright.
  if (!authorizeServiceRole(req)) {
    return json({ error: 'Unauthorized' }, 401);
  }

  // 2. Optional body for chunking + audit.
  let body: InvokeBody = {};
  if (req.headers.get('Content-Length') !== '0') {
    try {
      const txt = await req.text();
      if (txt.length > 0) {
        body = JSON.parse(txt) as InvokeBody;
      }
    } catch (_) {
      return json({ error: 'Invalid JSON body' }, 400);
    }
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: 'Server misconfigured' }, 500);
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 3. Find candidate users for tonight's recompute. Two pools UNIONed:
  //
  //    a. Users with xp_events in the past 7 days — they have NEW volume
  //       to fold into their EWMA (rebuild path).
  //    b. Users with a non-zero body_part_progress.vitality_ewma — they
  //       have PRIOR conditioning that decays per α_down even on a deload
  //       week with zero events (spec §8.2 asymmetric decay). Excluding
  //       them would freeze the rune at its last-active state forever.
  //
  //    Both queries are O(touched users) rather than O(all users), which
  //    keeps the §12.3 budget intact (the EWMA-only pool is bounded by
  //    "users who have ever trained at least one set" — the same lifetime
  //    cohort that owns body_part_progress rows).
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 3600 * 1000);
  const { data: activeRows, error: activeErr } = await client
    .from('xp_events')
    .select('user_id')
    .gte('occurred_at', sevenDaysAgo.toISOString());
  if (activeErr) {
    return json({ error: 'active users query failed', detail: activeErr.message }, 500);
  }
  const { data: decayRows, error: decayErr } = await client
    .from('body_part_progress')
    .select('user_id')
    .gt('vitality_ewma', 0);
  if (decayErr) {
    return json({ error: 'decay candidates query failed', detail: decayErr.message }, 500);
  }
  const userIdSet = new Set<string>();
  for (const r of activeRows ?? []) {
    if (r.user_id) userIdSet.add(r.user_id as string);
  }
  for (const r of decayRows ?? []) {
    if (r.user_id) userIdSet.add(r.user_id as string);
  }
  let userIds = Array.from(userIdSet);

  // 4. Optional chunk filter — distribute users by lexicographic
  //    user_id hash mod 10. Stable per-user assignment so chunked runs
  //    don't double-process anyone.
  if (typeof body.chunk === 'number') {
    const c = body.chunk | 0;
    if (c < 0 || c > 9) {
      return json({ error: 'chunk must be 0..9' }, 400);
    }
    userIds = userIds.filter((uid) => simpleMod10(uid) === c);
  }

  // 5. Process each user. Errors on individual users do not abort the run —
  //    the next user is independent and a transient failure for one user
  //    must not block the rest. We do return a non-2xx if EVERY user
  //    failed (suggests a global misconfiguration, not transient noise).
  let processed = 0;
  let skipped = 0;
  const errors: { user_id: string; detail: string }[] = [];
  for (const uid of userIds) {
    try {
      const r = await processUser(uid, { client });
      if (r.processed) processed++;
      else if (r.skipped) skipped++;
    } catch (e) {
      errors.push({
        user_id: uid,
        detail: e instanceof Error ? e.message : String(e),
      });
    }
  }

  if (errors.length > 0 && processed === 0 && skipped === 0) {
    return json({ ok: false, errors }, 500);
  }

  return json(
    {
      ok: true,
      processed,
      skipped,
      errored: errors.length,
      chunk: body.chunk ?? null,
      source: body.source ?? null,
    },
    200,
  );
});

/**
 * Cheap deterministic mod-10 for a UUID string. Sums character codes —
 * good enough for ~uniform distribution across UUIDs without pulling in a
 * crypto hash. Stable across runs (same UUID → same chunk).
 */
export function simpleMod10(uuid: string): number {
  let sum = 0;
  for (let i = 0; i < uuid.length; i++) {
    sum = (sum + uuid.charCodeAt(i)) % 1000;
  }
  return sum % 10;
}
