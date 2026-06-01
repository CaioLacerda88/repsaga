// Supabase Edge Function: rtdn-webhook
//
// Receives Real-Time Developer Notifications (RTDNs) from Google Play
// via Cloud Pub/Sub push delivery. Pub/Sub wraps each RTDN in a push
// envelope and signs the HTTP request with a Google-issued OIDC JWT —
// we verify that JWT, unwrap the envelope, decode the base64 data, and
// translate Play's notification_type into a row UPSERT on
// `subscriptions` plus an audit insert on `subscription_events`.
//
// Public endpoint. There is no end-user JWT on this path — the auth
// mechanism is the Pub/Sub service-account JWT in the `Authorization`
// header.
//
// Handled subscriptionNotification.notificationType values:
//   1  SUBSCRIPTION_RECOVERED      → active,  in_grace=false
//   2  SUBSCRIPTION_RENEWED        → active,  in_grace=false
//   3  SUBSCRIPTION_CANCELED       → canceled (access until expires_at)
//   4  SUBSCRIPTION_PURCHASED      → active
//   5  SUBSCRIPTION_ON_HOLD        → on_hold
//   6  SUBSCRIPTION_IN_GRACE_PERIOD→ active,  in_grace=true
//   7  SUBSCRIPTION_RESTARTED      → active (re-subscribed after cancel)
//   9  SUBSCRIPTION_DEFERRED       → active (billing deferred)
//  10  SUBSCRIPTION_PAUSED         → paused
//  12  SUBSCRIPTION_REVOKED        → revoked
//  13  SUBSCRIPTION_EXPIRED        → expired
//
// Idempotency: we insert into `subscription_events` first. A duplicate
// notification collapses at the unique constraint
// (purchase_token, notification_type, event_time) and we return 200
// without touching the subscriptions row — Pub/Sub's retry loop then
// stops redelivering.
//
// Env vars:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   RTDN_PUBSUB_AUDIENCE       — the `aud` claim configured on the Pub/Sub
//                                push subscription (typically the
//                                Edge Function URL).

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireBodySize } from '../_shared/auth.ts';
import { verifyPubSubJwt } from '../_shared/google_play.ts';

// Phase 33 PR 33a defense-in-depth (findings 028 / 033):
//   * 16KB request-body cap at the HTTP boundary (requireBodySize)
//   * 16KB decoded base64 payload cap inside decodePubSubPayload
// Real Pub/Sub envelopes are ≤ ~8KB; anything above 16KB is a malicious
// payload bomb. Both caps short-circuit BEFORE expensive work (JWT
// verify / JSON.parse) so the attacker can't induce CPU burn.
const MAX_BODY_BYTES = 16 * 1024;
const MAX_DECODED_PAYLOAD_BYTES = 16 * 1024;

// Pub/Sub push is server-to-server; no browser CORS needed for the real
// production traffic. We still answer OPTIONS for the Supabase dashboard
// (which issues a preflight when invoking the function from the browser).
// Pinning Allow-Origin to SUPABASE_URL matches the pattern used by
// validate-purchase and avoids a wildcard origin on a public endpoint.
//
// Same "fail loudly at module scope if SUPABASE_URL is missing" rule as
// validate-purchase — a deployment without SUPABASE_URL is broken and
// we prefer a boot error to a silent blank Allow-Origin.
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

// --- RTDN type mapping ----------------------------------------------------

export interface SubscriptionStatePatch {
  state?: 'active' | 'canceled' | 'expired' | 'on_hold' | 'paused' | 'revoked';
  in_grace_period?: boolean;
  auto_renewing?: boolean;
}

export function rtdnTypeToStatePatch(
  notificationType: number,
): SubscriptionStatePatch | null {
  switch (notificationType) {
    case 1:  // RECOVERED
      return { state: 'active', in_grace_period: false };
    case 2:  // RENEWED
      return { state: 'active', in_grace_period: false, auto_renewing: true };
    case 3:  // CANCELED (access continues until expires_at)
      return { state: 'canceled', auto_renewing: false };
    case 4:  // PURCHASED
      return { state: 'active', in_grace_period: false };
    case 5:  // ON_HOLD
      return { state: 'on_hold', in_grace_period: false };
    case 6:  // IN_GRACE_PERIOD
      return { state: 'active', in_grace_period: true };
    case 7:  // RESTARTED (user re-subscribed after cancel)
      return { state: 'active', in_grace_period: false, auto_renewing: true };
    case 9:  // DEFERRED (billing postponed)
      return { state: 'active', in_grace_period: false };
    case 10: // PAUSED
      return { state: 'paused' };
    case 12: // REVOKED (refunded, lose access immediately)
      return { state: 'revoked', auto_renewing: false };
    case 13: // EXPIRED (fully lapsed)
      return { state: 'expired', auto_renewing: false };
    default:
      return null;
  }
}

// --- Inbound envelope shape (Pub/Sub push) --------------------------------

interface PubSubEnvelope {
  message?: {
    data?: string; // base64-encoded JSON payload from Google Play
    messageId?: string;
    publishTime?: string;
    attributes?: Record<string, string>;
  };
  subscription?: string;
}

// Play's actual RTDN JSON body shape (subset we care about).
interface RtdnPayload {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: {
    version?: string;
    notificationType?: number;
    purchaseToken?: string;
    subscriptionId?: string;
  };
  testNotification?: {
    version?: string;
  };
  oneTimeProductNotification?: unknown;
}

export function decodePubSubPayload(envelope: PubSubEnvelope): RtdnPayload {
  const b64 = envelope.message?.data;
  if (!b64) throw new Error('Pub/Sub envelope missing message.data');
  // atob is available in Deno; base64 may contain `+` `/` so no URL-safe
  // transform is needed here (Pub/Sub uses standard base64, not URL-safe).
  const json = atob(b64);
  // Defense-in-depth (finding-033): cap the DECODED payload before
  // JSON.parse runs. A 10MB envelope decodes to ~7MB JSON; JSON.parse
  // on 7MB of attacker-controlled string is cheap CPU but still avoidable.
  // Real RTDNs are ≤ ~2KB, so 16KB is two orders of magnitude headroom.
  if (json.length > MAX_DECODED_PAYLOAD_BYTES) {
    throw new Error(
      `payload too large: ${json.length} bytes > ${MAX_DECODED_PAYLOAD_BYTES}`,
    );
  }
  return JSON.parse(json) as RtdnPayload;
}

// --- Core handler, extracted for unit testability --------------------------

export interface HandleRtdnDeps {
  client: SupabaseClient;
  now?: () => Date;
}

export interface HandleRtdnResult {
  status: number;
  body: Record<string, unknown>;
}

export async function handleRtdn(
  payload: RtdnPayload,
  deps: HandleRtdnDeps,
): Promise<HandleRtdnResult> {
  // Test notifications carry no subscription context — always 200.
  if (payload.testNotification) {
    return { status: 200, body: { success: true, test: true } };
  }
  const sn = payload.subscriptionNotification;
  if (!sn || !sn.purchaseToken || typeof sn.notificationType !== 'number') {
    return { status: 200, body: { success: true, ignored: 'no subscriptionNotification' } };
  }

  const eventTime = payload.eventTimeMillis
    ? new Date(Number(payload.eventTimeMillis))
    : (deps.now ? deps.now() : new Date());

  // Look up the user_id bound to this token. Any `subscriptions` row
  // inserted by validate-purchase carries it; if we've never seen the
  // token (RTDN arrives before the client's validate-purchase), we
  // still record the event and return 200 — when validate-purchase
  // eventually runs it will UPSERT and the reconcile cron will
  // re-synchronise state.
  const { data: existing } = await deps.client
    .from('subscriptions')
    .select('user_id')
    .eq('purchase_token', sn.purchaseToken)
    .maybeSingle();

  const userId = existing?.user_id ?? null;

  // 1. Idempotent audit insert. We do this BEFORE the state patch so a
  // duplicate RTDN short-circuits without touching subscriptions.
  if (userId) {
    const { error: insErr } = await deps.client
      .from('subscription_events')
      .insert({
        user_id: userId,
        purchase_token: sn.purchaseToken,
        notification_type: `rtdn:${sn.notificationType}`,
        event_time: eventTime.toISOString(),
        raw_payload: payload as unknown as Record<string, unknown>,
      });
    if (insErr) {
      if (isUniqueViolation(insErr)) {
        return { status: 200, body: { success: true, duplicate: true } };
      }
      return { status: 500, body: { error: 'audit insert failed', detail: insErr.message } };
    }
  }

  // 2. State patch.
  const patch = rtdnTypeToStatePatch(sn.notificationType);
  if (!patch) {
    // Unknown notification type: return 200 so Pub/Sub stops retrying
    // (we've already written the audit row for forensics).
    return { status: 200, body: { success: true, unknown_type: sn.notificationType } };
  }
  if (userId) {
    const { error: updErr } = await deps.client
      .from('subscriptions')
      .update(patch)
      .eq('user_id', userId)
      .eq('purchase_token', sn.purchaseToken);
    if (updErr) {
      return { status: 500, body: { error: 'state update failed', detail: updErr.message } };
    }
  }

  return {
    status: 200,
    body: {
      success: true,
      notification_type: sn.notificationType,
      applied: patch,
      known_user: userId !== null,
    },
  };
}

function isUniqueViolation(err: { code?: string; message?: string }): boolean {
  return err.code === '23505' || /duplicate key/i.test(err.message ?? '');
}

// --- HTTP boundary --------------------------------------------------------
//
// `handleRequest()` is exported so unit tests can drive the body-size cap +
// decoded-payload cap without standing up the Edge Runtime or a real
// Pub/Sub JWT. The deps object injects the Supabase client + JWT verifier
// + audience so the rejection paths don't require a real OIDC roundtrip.

export interface HandleRequestDeps {
  client: SupabaseClient;
  /** JWT verifier — production uses verifyPubSubJwt; tests inject a stub.
   * Return value is discarded by handleRequest (we only care whether it
   * throws); typed as `unknown` so production's `PubSubClaims` return
   * and test stubs returning `void` both satisfy the contract. */
  verifyJwt: (args: { token: string; expectedAudience: string }) => Promise<unknown>;
  expectedAudience: string;
  now?: () => Date;
}

export async function handleRequest(
  req: Request,
  deps: HandleRequestDeps,
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 1. App-level body-size cap (finding-028). Reject 16KB+ envelopes
  //    BEFORE JWT verify — JWT verify is a JWKs fetch + RSA verify, so
  //    short-circuiting on body size first saves the expensive crypto.
  const tooBig = requireBodySize(req, MAX_BODY_BYTES, corsHeaders);
  if (tooBig) return tooBig;

  try {
    // 2. Verify Pub/Sub JWT.
    const authHeader = req.headers.get('Authorization') ?? '';
    const jwt = authHeader.replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ error: 'Missing Pub/Sub JWT' }, 401);
    try {
      await deps.verifyJwt({ token: jwt, expectedAudience: deps.expectedAudience });
    } catch (e) {
      return json({ error: 'Invalid Pub/Sub JWT', detail: String(e) }, 401);
    }

    // 3. Parse envelope.
    let envelope: PubSubEnvelope;
    try {
      envelope = await req.json();
    } catch (_) {
      return json({ error: 'Invalid JSON body' }, 400);
    }
    let payload: RtdnPayload;
    try {
      // decodePubSubPayload enforces the inner 16KB decoded-base64 cap
      // (finding-033). A payload-too-large throw bubbles up here and we
      // surface it as 400 — same status code as a malformed envelope.
      payload = decodePubSubPayload(envelope);
    } catch (e) {
      return json({ error: 'Malformed Pub/Sub payload', detail: String(e) }, 400);
    }

    // 4. Delegate to the pure handler.
    const result = await handleRtdn(payload, { client: deps.client, now: deps.now });
    return json(result.body, result.status);
  } catch (e) {
    return json(
      { error: e instanceof Error ? e.message : 'Unknown error' },
      500,
    );
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const audience = Deno.env.get('RTDN_PUBSUB_AUDIENCE');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!audience || !supabaseUrl || !serviceRoleKey) {
    return json({ error: 'Server misconfigured' }, 500);
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return handleRequest(req, {
    client,
    verifyJwt: verifyPubSubJwt,
    expectedAudience: audience,
  });
});
