// Supabase Edge Function: validate-purchase
//
// Called from the Flutter client after a successful
// `in_app_purchase` flow to server-validate the purchase token against
// the Google Play Developer API and grant entitlement only if Play
// confirms it.
//
// Contract (POST JSON):
//   {
//     "product_id":     "repsaga_premium:monthly",
//     "purchase_token": "eyjk...",
//     "user_id":        "<uuid>",       // optional; defaults to JWT sub
//     "source":         "client" | "cron_reconcile"  // optional, audit only
//   }
//
// Behavior:
//   1. Verify the caller's JWT (anon client) or accept service-role JWTs
//      from the internal reconciliation cron.
//   2. Ensure the JWT user_id matches `obfuscatedExternalAccountId` in
//      the Play response — prevents token hijacking across Supabase users.
//   3. UPSERT the `subscriptions` row through the service-role client.
//   4. Write an audit row to `subscription_events` (type = source).
//   5. If the subscription needs acknowledgement, call the Play
//      acknowledge endpoint. On acknowledgement failure we return 500
//      WITHOUT leaving the UPSERT in a "granted" state on a pending
//      subscription — we deliberately keep the row but force
//      `acknowledgement_state='pending'` so a retry is clean. The
//      entitlements view only reports `premium` if state='active' AND
//      expires_at > now(); it does NOT consult acknowledgement_state
//      directly, so this is enforced at the UI layer by a follow-up
//      check (16b will expose `acknowledgement_state` through the client
//      to gate access until ack succeeds). For 16a the contract is:
//      non-2xx ack → function returns 500 and the client is responsible
//      for retrying.
//
//      PARTIAL FAILURE CONTRACT: If the Play :acknowledge call SUCCEEDS
//      but the subsequent `UPDATE subscriptions SET acknowledgement_state
//      = 'acknowledged'` FAILS, the function still returns 200. Play is
//      the source of truth once it has acknowledged — returning 500 would
//      make the client retry and re-ack a token that Play already treats
//      as acknowledged. The DB drift (row says 'pending' even though Play
//      says acknowledged) is corrected by the reconcile cron on its next
//      tick. We log the DB failure via console.error so ops can alert on
//      it.
//
// Env vars (Supabase sets the first three automatically):
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  (service account credentials)
//   GOOGLE_PLAY_PACKAGE_NAME          (e.g. "com.repsaga.app")

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { precheckJwtExp, requireBodySize } from '../_shared/auth.ts';
import {
  acknowledgePlaySubscription,
  baseProductIdFromPlay,
  fetchPlaySubscriptionV2,
  getPlayAccessToken,
  normalizePlaySubscription,
  type ServiceAccountJson,
} from '../_shared/google_play.ts';

// Intentionally no `?? ''` fallback — a missing SUPABASE_URL at module
// load is a deployment misconfiguration and we want it to blow up
// loudly when the isolate first boots rather than silently serving a
// blank Allow-Origin. The runtime env check inside the handler (line
// below) would only fire on the first request, by which point CORS
// preflights to this isolate have already been answered incorrectly.
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

// --- Service-role identity check -----------------------------------------
//
// The reconcile cron (see migration 00026) invokes this function with a
// service-role JWT in the Authorization header so it can set user_id
// explicitly in the body (no user session attached). We detect that by
// decoding the JWT payload and checking `role === 'service_role'`.
//
// The Supabase Edge Function runtime has ALREADY cryptographically verified
// the JWT signature by the time we see it (verify_jwt is on for this
// function), so decoding without verifying again is safe here — we are only
// reading a claim the runtime already authenticated. We deliberately do NOT
// compare the raw service-role key as a bearer token: that conflates a
// secret with an auth token and breaks as soon as Supabase rotates keys or
// issues alternate service-role JWTs.
export function isServiceRoleJwt(jwt: string): boolean {
  const parts = jwt.split('.');
  if (parts.length < 2) return false;
  const payloadB64 = parts[1];
  if (!payloadB64) return false;
  try {
    // JWT uses base64url without padding. atob wants standard base64
    // with correct padding, so translate and re-pad.
    const b64 = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
    const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
    const payload = JSON.parse(atob(b64 + pad)) as { role?: unknown };
    return payload?.role === 'service_role';
  } catch {
    return false;
  }
}

// --- Core handler, extracted so unit tests can drive it without HTTP ------

export interface ValidatePurchaseDeps {
  fetchFn?: typeof fetch;
  now?: () => Date;
}

export interface ValidatePurchaseInput {
  userId: string;
  productId: string;
  purchaseToken: string;
  source: string;
  serviceAccount: ServiceAccountJson;
  packageName: string;
  client: SupabaseClient;
}

export interface ValidatePurchaseResult {
  status: number;
  body: Record<string, unknown>;
}

export async function validatePurchase(
  input: ValidatePurchaseInput,
  deps: ValidatePurchaseDeps = {},
): Promise<ValidatePurchaseResult> {
  const fetchFn = deps.fetchFn ?? fetch;

  // 1. OAuth2 exchange for an androidpublisher access token.
  let accessToken: string;
  try {
    accessToken = await getPlayAccessToken(input.serviceAccount, fetchFn);
  } catch (e) {
    return {
      status: 500,
      body: { error: 'Failed to obtain Play access token', detail: String(e) },
    };
  }

  // 2. purchases.subscriptionsv2.get
  const play = await fetchPlaySubscriptionV2({
    packageName: input.packageName,
    token: input.purchaseToken,
    accessToken,
    fetchFn,
  });

  if (play.status >= 400) {
    // 4xx/5xx from Play — relay status class so client can decide to
    // retry (5xx) vs surface as user error (4xx).
    return {
      status: play.status >= 500 ? 502 : 400,
      body: { error: 'Play API error', status: play.status, detail: play.body },
    };
  }

  const playBody = play.body as Parameters<typeof normalizePlaySubscription>[0]['playResponse'];

  // 3. Enforce obfuscatedAccountId binding — the client is supposed to
  // set this to the Supabase user_id at purchase time. If Play says the
  // token belongs to a different user, refuse the grant.
  const boundUserId =
    playBody.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  if (!boundUserId) {
    return {
      status: 400,
      body: {
        error: 'Purchase token is not bound to a Supabase user '
             + '(obfuscatedAccountId missing)',
      },
    };
  }
  if (boundUserId !== input.userId) {
    return {
      status: 403,
      body: {
        error: 'Purchase token user mismatch',
        expected: input.userId,
        actual: boundUserId,
      },
    };
  }

  // 4. Normalize + UPSERT the subscription row via the service role.
  const adminClient = input.client;

  const normalized = normalizePlaySubscription({
    purchaseToken: input.purchaseToken,
    playResponse: playBody,
  });

  const { error: upsertError } = await adminClient
    .from('subscriptions')
    .upsert(
      {
        user_id: input.userId,
        product_id: normalized.product_id || input.productId,
        purchase_token: normalized.purchase_token,
        linked_purchase_token: normalized.linked_purchase_token,
        state: normalized.state,
        auto_renewing: normalized.auto_renewing,
        in_grace_period: normalized.in_grace_period,
        acknowledgement_state: normalized.acknowledgement_state,
        started_at: normalized.started_at,
        expires_at: normalized.expires_at,
      },
      { onConflict: 'user_id' },
    );
  if (upsertError) {
    return {
      status: 500,
      body: { error: 'Subscriptions UPSERT failed', detail: upsertError.message },
    };
  }

  // 5. Audit row. Duplicate RTDNs are collapsed at the
  // (purchase_token, notification_type, event_time) UNIQUE constraint
  // elsewhere; that dedupe is designed for Play replaying the SAME
  // RTDN. For validate-purchase we WANT each client-initiated call
  // audited as its own row — the client may legitimately call us
  // multiple times (retry after 5xx, polling during payment settle,
  // cron reconcile) and each invocation is a distinct event worth
  // recording. Generating a fresh event_time per call guarantees the
  // UNIQUE constraint won't collapse rows that semantically differ,
  // at the cost of a duplicate on true retry-after-success (rare; the
  // audit table is append-only and cheap).
  const eventTime = (deps.now ? deps.now() : new Date()).toISOString();
  const { error: evErr } = await adminClient
    .from('subscription_events')
    .insert({
      user_id: input.userId,
      purchase_token: input.purchaseToken,
      notification_type: `validate:${input.source}`,
      event_time: eventTime,
      raw_payload: playBody as unknown as Record<string, unknown>,
    });
  if (evErr && !isUniqueViolation(evErr)) {
    // Non-dedupe insert failure is a real error — but do NOT undo the
    // UPSERT: the subscriptions row already reflects Play truth.
    return {
      status: 500,
      body: { error: 'subscription_events insert failed', detail: evErr.message },
    };
  }

  // 6. Acknowledge within 3d. If it fails, we return 500 WITHOUT marking
  // acknowledgement_state='acknowledged'. Entitlement derivation doesn't
  // require acknowledged state at the DB level, but the client contract
  // is: a 200 means "use the app"; 500 means "do not grant yet, retry".
  if (normalized.acknowledgement_state === 'pending') {
    const baseProduct = baseProductIdFromPlay(playBody) ?? '';
    if (!baseProduct) {
      return {
        status: 500,
        body: { error: 'Cannot acknowledge: no product id in Play response' },
      };
    }
    const ack = await acknowledgePlaySubscription({
      packageName: input.packageName,
      subscriptionId: baseProduct,
      token: input.purchaseToken,
      accessToken,
      fetchFn,
    });
    if (!ack.ok) {
      return {
        status: 500,
        body: {
          error: 'Acknowledgement failed; entitlement not granted',
          detail: ack.body,
          status: ack.status,
        },
      };
    }
    // Best-effort: update acknowledgement_state. If this write fails
    // we still return 200 because Play itself has been acknowledged —
    // the reconcile cron will pick up the truth on its next run.
    // See the "PARTIAL FAILURE CONTRACT" note at the top of this file.
    const { error: ackUpdateErr } = await adminClient
      .from('subscriptions')
      .update({ acknowledgement_state: 'acknowledged' })
      .eq('user_id', input.userId);
    if (ackUpdateErr) {
      // Log so ops can see it; do NOT flip the response to 500.
      console.error(
        'validate-purchase: Play ack succeeded but DB ack-state update failed',
        {
          user_id: input.userId,
          purchase_token: input.purchaseToken,
          detail: ackUpdateErr.message,
        },
      );
    }
  }

  return {
    status: 200,
    body: {
      success: true,
      entitlement_state: deriveEntitlement(normalized, deps.now ? deps.now() : new Date()),
      expires_at: normalized.expires_at,
    },
  };
}

function isUniqueViolation(err: { code?: string; message?: string }): boolean {
  return err.code === '23505' || /duplicate key/i.test(err.message ?? '');
}

// Mirror of the entitlements SQL view's CASE (see migration 00025). Kept
// in TS so the HTTP response can echo the derived state without a round
// trip. The branch ordering MATCHES the view exactly:
//   1. active + not-expired  → premium (covers Play's own retry grace)
//   2. in_grace_period + within our 3d soft tail → grace_period
//   3. on_hold               → on_hold
//   4. otherwise             → free
// Keep this in sync with 00025_create_entitlements_view.sql.
//
// Exported so unit tests can exercise the branches directly.
export function deriveEntitlement(
  n: { state: string; in_grace_period: boolean; expires_at: string | null },
  now: Date,
): string {
  if (!n.expires_at) return 'free';
  const exp = new Date(n.expires_at).getTime();
  if (n.state === 'active' && exp > now.getTime()) return 'premium';
  if (n.in_grace_period && exp > now.getTime() - 3 * 24 * 60 * 60 * 1000) {
    return 'grace_period';
  }
  if (n.state === 'on_hold') return 'on_hold';
  return 'free';
}

// --- HTTP boundary --------------------------------------------------------
//
// Phase 33 PR 33a (findings 026 / 027 / 028) hardened the boundary with:
//   * 32KB body-size cap at the top (requireBodySize) — finding 028
//   * JWT exp precheck BEFORE req.json() (precheckJwtExp) — finding 027
//   * Length clamps, source allow-list, UUID regex on user_id — finding 026
//
// `handleRequest()` is exported so unit tests can drive these rejections
// without spinning up the Edge Runtime. The deps object injects the
// Supabase clients + Play fetch so the rejection paths don't construct
// real clients (which would require network / env access).

/** Max payload sizes — finding 026. */
const MAX_PRODUCT_ID_LEN = 128;
const MAX_PURCHASE_TOKEN_LEN = 4096;
const MAX_SOURCE_LEN = 32;
const MAX_BODY_BYTES = 32 * 1024;

/** Source allow-list — finding 026. `client` = end-user-driven call from
 * Flutter; `cron_reconcile` = nightly reconciliation cron. Any other
 * value is an audit-row-pollution attempt or a stale caller. */
const SOURCE_ALLOW_LIST = ['client', 'cron_reconcile'] as const;

/** RFC 4122 UUID v1-v5 pattern — used to validate body.user_id on
 * service-role calls. The Postgres `uuid` column would also reject
 * malformed strings, but a clean 400 here saves a round-trip and
 * produces a clearer error than a Postgres cast 500. */
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface HandleRequestDeps {
  /** Supabase admin client (service-role). Tests inject a stub. */
  adminClient: SupabaseClient;
  /** Supabase user-scoped client (anon key + JWT header). Tests inject a stub. */
  userClient: SupabaseClient;
  /** Play API fetch — mocked in tests. */
  fetchFn?: typeof fetch;
  /** Service account JSON. Pulled from env in serve(); injected in tests. */
  serviceAccount?: ServiceAccountJson;
  /** Play package name. Pulled from env in serve(); injected in tests. */
  packageName?: string;
  /** Clock — for `now`-dependent paths in validatePurchase. */
  now?: () => Date;
}

export async function handleRequest(
  req: Request,
  deps: HandleRequestDeps,
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 1. App-level body-size cap (finding 028). Short-circuit BEFORE any
  //    other work — even before reading env vars — so a malicious 9MB
  //    payload never enters our handler logic.
  const tooBig = requireBodySize(req, MAX_BODY_BYTES, corsHeaders);
  if (tooBig) return tooBig;

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);
    const jwt = authHeader.replace('Bearer ', '');

    // 2. JWT exp precheck (finding 027). Reject expired/malformed JWTs
    //    BEFORE paying the req.json() body-parse cost. Service-role JWTs
    //    DO have an exp claim (Supabase issues them with one), so this
    //    check is uniform — no special-casing.
    const precheck = precheckJwtExp(jwt);
    if (!precheck.valid) {
      return json({ error: 'Invalid or expired token', reason: precheck.reason }, 401);
    }

    // 3. Body parse (now that JWT is at least exp-valid).
    let body: {
      product_id?: unknown;
      purchase_token?: unknown;
      user_id?: unknown;
      source?: unknown;
    } = {};
    try {
      body = await req.json();
    } catch (_) {
      return json({ error: 'Invalid JSON body' }, 400);
    }

    // 4. Input validation (finding 026). Clamp lengths, allow-list source,
    //    UUID-regex user_id. Each rejection cites the offending field by
    //    name so a misbehaving client / cron can fix its payload.
    if (typeof body.product_id !== 'string' || body.product_id.length === 0) {
      return json({ error: 'product_id required' }, 400);
    }
    if (body.product_id.length > MAX_PRODUCT_ID_LEN) {
      return json(
        { error: `product_id exceeds ${MAX_PRODUCT_ID_LEN} chars` },
        400,
      );
    }
    if (
      typeof body.purchase_token !== 'string'
      || body.purchase_token.length === 0
    ) {
      return json({ error: 'purchase_token required' }, 400);
    }
    if (body.purchase_token.length > MAX_PURCHASE_TOKEN_LEN) {
      return json(
        { error: `purchase_token exceeds ${MAX_PURCHASE_TOKEN_LEN} chars` },
        400,
      );
    }
    // Source defaults to 'client' when omitted (legacy contract); only
    // explicitly-passed non-string / oversized / off-list values reject.
    let source: string;
    if (body.source === undefined || body.source === null) {
      source = 'client';
    } else if (typeof body.source !== 'string') {
      return json({ error: 'source must be a string' }, 400);
    } else if (body.source.length > MAX_SOURCE_LEN) {
      return json({ error: `source exceeds ${MAX_SOURCE_LEN} chars` }, 400);
    } else if (
      !(SOURCE_ALLOW_LIST as readonly string[]).includes(body.source)
    ) {
      return json(
        {
          error: `source must be one of: ${SOURCE_ALLOW_LIST.join(', ')}`,
        },
        400,
      );
    } else {
      source = body.source;
    }
    // user_id is optional in the body — service-role callers MUST supply
    // it, authenticated callers MAY. When present it must be a real UUID.
    if (
      body.user_id !== undefined
      && body.user_id !== null
      && (typeof body.user_id !== 'string' || !UUID_RE.test(body.user_id))
    ) {
      return json({ error: 'user_id must be a UUID' }, 400);
    }

    const productId = body.product_id;
    const purchaseToken = body.purchase_token;

    // 5. Resolve caller user_id. Service-role callers (cron) supply it
    // explicitly in the body. Authenticated users are identified from
    // their JWT and MUST match any user_id they pass (prevents a
    // user acting on another user's purchase via a forged body).
    //
    // Service-role detection decodes the JWT role claim rather than
    // string-comparing the raw service-role key — see isServiceRoleJwt
    // above for why.
    let userId: string;
    if (isServiceRoleJwt(jwt)) {
      if (typeof body.user_id !== 'string' || !body.user_id) {
        return json({ error: 'user_id required for service-role calls' }, 400);
      }
      userId = body.user_id;
    } else {
      const { data: { user }, error: uerr } = await deps.userClient.auth.getUser(jwt);
      if (uerr || !user) return json({ error: 'Invalid or expired token' }, 401);
      if (
        typeof body.user_id === 'string'
        && body.user_id
        && body.user_id !== user.id
      ) {
        return json({ error: 'user_id does not match JWT' }, 403);
      }
      userId = user.id;
    }

    if (!deps.serviceAccount || !deps.packageName) {
      return json({ error: 'Server misconfigured' }, 500);
    }

    const result = await validatePurchase(
      {
        userId,
        productId,
        purchaseToken,
        source,
        serviceAccount: deps.serviceAccount,
        packageName: deps.packageName,
        client: deps.adminClient,
      },
      { fetchFn: deps.fetchFn, now: deps.now },
    );
    return json(result.body, result.status);
  } catch (e) {
    return json(
      { error: e instanceof Error ? e.message : 'Unknown error' },
      500,
    );
  }
}

serve(async (req) => {
  // OPTIONS preflight is handled inside handleRequest, but answering it
  // here too keeps the response identical even if the inner handler
  // throws at construction time (e.g. env-var read failure).
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const saJson = Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON');
  const packageName = Deno.env.get('GOOGLE_PLAY_PACKAGE_NAME');
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !saJson || !packageName) {
    return json({ error: 'Server misconfigured' }, 500);
  }

  let serviceAccount: ServiceAccountJson;
  try {
    serviceAccount = JSON.parse(saJson);
  } catch (_) {
    return json({ error: 'Invalid GOOGLE_PLAY_SERVICE_ACCOUNT_JSON' }, 500);
  }

  // Build the per-request user client (needs the caller's JWT in its
  // Authorization header for auth.getUser). The Authorization header
  // is forwarded by Supabase to the Edge Function before this code runs.
  const authHeader = req.headers.get('Authorization') ?? '';
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return handleRequest(req, {
    adminClient,
    userClient,
    serviceAccount,
    packageName,
  });
});
