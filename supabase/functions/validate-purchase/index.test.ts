// Unit tests for validate-purchase Edge Function.
//
// These tests exercise the pure `validatePurchase()` core with a mocked
// fetch (Play OAuth + Play API) and a fake SupabaseClient stub. No real
// network, no Play API, no DB.
//
// Run with:  deno test --allow-net --allow-env supabase/functions/
//
// We do NOT test the HTTP boundary here — JWT resolution + body parsing
// live in the `serve()` wrapper and are thin enough that repeated
// coverage adds little value.

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  deriveEntitlement,
  handleRequest,
  isServiceRoleJwt,
  validatePurchase,
} from './index.ts';
import {
  _resetPlayTokenCacheForTests,
  type ServiceAccountJson,
} from '../_shared/google_play.ts';

// --- Fixtures --------------------------------------------------------------

// `signAssertion()` in the shared helper calls `crypto.subtle.importKey`
// with the PEM private_key, so we need a PEM that is actually importable.
// We generate a throwaway RSA-2048 keypair at test-suite start and export
// its PKCS#8 body as PEM. The signature is never verified upstream in
// tests (we mock the OAuth token endpoint to succeed regardless), so the
// key just needs to be valid enough to import + sign.
async function generateFakeServiceAccount(): Promise<ServiceAccountJson> {
  const { privateKey } = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', privateKey));
  let bin = '';
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const b64 = btoa(bin);
  const lines = b64.match(/.{1,64}/g) ?? [b64];
  const pem = `-----BEGIN PRIVATE KEY-----\n${lines.join('\n')}\n-----END PRIVATE KEY-----\n`;
  return {
    client_email: 'test@example.iam.gserviceaccount.com',
    private_key: pem,
    token_uri: 'https://oauth2.googleapis.com/token',
  };
}

// Cache a single generated service account for the whole test run —
// generating 2048-bit RSA keys is slow (~100ms) and we don't need
// per-test isolation of the key material (the OAuth endpoint is mocked).
let _cachedFakeSa: ServiceAccountJson | null = null;
async function getFakeServiceAccount(): Promise<ServiceAccountJson> {
  if (!_cachedFakeSa) _cachedFakeSa = await generateFakeServiceAccount();
  return _cachedFakeSa;
}

const FAKE_USER_ID = '11111111-1111-1111-1111-111111111111';

// --- Fetch mock ------------------------------------------------------------
//
// Drives only the Play HTTP endpoints: oauth2 token exchange, subscriptionsv2
// get, and :acknowledge. Supabase DB calls are served by the client stub
// below, never by fetch.

interface FetchMockEntry {
  url: string | RegExp;
  response: {
    status?: number;
    body: unknown;
    ok?: boolean;
  };
}

function buildFetchMock(entries: FetchMockEntry[]): typeof fetch {
  return (input, _init) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    for (const e of entries) {
      const matches = typeof e.url === 'string' ? url.includes(e.url) : e.url.test(url);
      if (matches) {
        const status = e.response.status ?? 200;
        return Promise.resolve(new Response(JSON.stringify(e.response.body), {
          status,
          headers: { 'Content-Type': 'application/json' },
        }));
      }
    }
    return Promise.reject(new Error(`fetch mock: no match for ${url}`));
  };
}

// --- Supabase client stub --------------------------------------------------
//
// handleRtdn-style: records calls, returns configured errors.
// The Edge Function calls:
//   client.from('subscriptions').upsert(row, { onConflict })
//   client.from('subscription_events').insert(row)
//   client.from('subscriptions').update(patch).eq('user_id', x)

interface DbCall {
  table: string;
  op: 'upsert' | 'insert' | 'update';
  payload?: unknown;
}

function makeClient(opts: {
  upsertError?: { code?: string; message: string };
  insertError?: { code?: string; message: string };
  updateError?: { code?: string; message: string };
} = {}): { client: unknown; calls: DbCall[] } {
  const calls: DbCall[] = [];
  const client = {
    from(table: string) {
      return {
        upsert(row: unknown, _opts?: unknown) {
          calls.push({ table, op: 'upsert', payload: row });
          return Promise.resolve(
            opts.upsertError
              ? { data: null, error: opts.upsertError }
              : { data: row, error: null },
          );
        },
        insert(row: unknown) {
          calls.push({ table, op: 'insert', payload: row });
          return Promise.resolve(
            opts.insertError
              ? { data: null, error: opts.insertError }
              : { data: row, error: null },
          );
        },
        update(patch: unknown) {
          calls.push({ table, op: 'update', payload: patch });
          // Mirror the shape used by `rtdn-webhook/test.ts` —
          // `.update(...).eq(...).eq(...)` — even though the
          // production code for validate-purchase currently only
          // chains ONE .eq(). A future refactor that adds a second
          // filter (e.g. to guard against stale user_id matches)
          // would otherwise hit a TypeError at `undefined.eq is not a
          // function` and hide the real bug. Keep stubs symmetric
          // across functions.
          const result = () =>
            Promise.resolve(
              opts.updateError
                ? { data: null, error: opts.updateError }
                : { data: patch, error: null },
            );
          const chain = {
            eq(_k: string, _v: unknown) {
              return {
                eq(_k2: string, _v2: unknown) {
                  return result();
                },
                then(
                  onFulfilled?: (v: unknown) => unknown,
                  onRejected?: (e: unknown) => unknown,
                ) {
                  return result().then(onFulfilled, onRejected);
                },
              };
            },
          };
          return chain;
        },
      };
    },
  };
  return { client, calls };
}

// --- Play response fixtures ------------------------------------------------

function playOk(opts: {
  ackState?: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' | 'ACKNOWLEDGEMENT_STATE_PENDING';
  subState?: string;
  boundUserId?: string;
  expiresInMs?: number;
} = {}): Record<string, unknown> {
  return {
    kind: 'androidpublisher#subscriptionPurchaseV2',
    subscriptionState: opts.subState ?? 'SUBSCRIPTION_STATE_ACTIVE',
    startTime: new Date(Date.now() - 60_000).toISOString(),
    latestOrderId: 'GPA.1234-5678-9012-34567',
    lineItems: [{
      productId: 'repsaga_premium',
      expiryTime: new Date(Date.now() + (opts.expiresInMs ?? 30 * 24 * 60 * 60 * 1000)).toISOString(),
      autoRenewingPlan: { autoRenewEnabled: true },
      offerDetails: { basePlanId: 'monthly' },
    }],
    acknowledgementState: opts.ackState ?? 'ACKNOWLEDGEMENT_STATE_PENDING',
    externalAccountIdentifiers: {
      obfuscatedExternalAccountId: opts.boundUserId ?? FAKE_USER_ID,
    },
  };
}

const OAUTH_TOKEN_OK: FetchMockEntry = {
  url: 'oauth2.googleapis.com/token',
  response: { body: { access_token: 'ya29.test', expires_in: 3600 } },
};

// --- Tests -----------------------------------------------------------------

async function baseInput(
  client: unknown,
  overrides: Partial<Parameters<typeof validatePurchase>[0]> = {},
): Promise<Parameters<typeof validatePurchase>[0]> {
  return {
    userId: FAKE_USER_ID,
    productId: 'repsaga_premium:monthly',
    purchaseToken: 'tok_1',
    source: 'client',
    serviceAccount: await getFakeServiceAccount(),
    packageName: 'com.repsaga.app',
    // deno-lint-ignore no-explicit-any
    client: client as any,
    ...overrides,
  };
}

Deno.test('happy path: active sub + pending ack → acknowledges + 200', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient();
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2/tokens/tok_1', response: { body: playOk() } },
    { url: ':acknowledge', response: { body: {} } },
  ]);

  const result = await validatePurchase(await baseInput(client), { fetchFn });

  assertEquals(result.status, 200);
  assertEquals(result.body.success, true);
  assertEquals(result.body.entitlement_state, 'premium');

  // Order matters: UPSERT → event → (Play ack) → mark-acknowledged.
  // We must NOT mark acknowledged before Play confirms.
  const ops = calls.map((c) => `${c.table}.${c.op}`);
  assertEquals(ops[0], 'subscriptions.upsert');
  assertEquals(ops[1], 'subscription_events.insert');
  assertEquals(ops[2], 'subscriptions.update');
});

Deno.test('already-acknowledged sub does NOT call :acknowledge', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient();
  let ackCalled = false;
  const base = buildFetchMock([
    OAUTH_TOKEN_OK,
    {
      url: 'subscriptionsv2/tokens/tok_ack',
      response: { body: playOk({ ackState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' }) },
    },
  ]);
  const fetchFn: typeof fetch = (input, init) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    if (url.includes(':acknowledge')) ackCalled = true;
    return base(input, init);
  };

  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_ack' }),
    { fetchFn },
  );

  assertEquals(result.status, 200);
  assertEquals(ackCalled, false);
  // No post-ack update — the row was already acknowledged.
  assertEquals(calls.filter((c) => c.op === 'update').length, 0);
});

Deno.test('user_id mismatch → 403, no DB writes', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient();
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    {
      url: 'subscriptionsv2/tokens/tok_mismatch',
      response: { body: playOk({ boundUserId: '22222222-2222-2222-2222-222222222222' }) },
    },
  ]);

  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_mismatch' }),
    { fetchFn },
  );

  assertEquals(result.status, 403);
  assertStringIncludes(result.body.error as string, 'user mismatch');
  assertEquals(calls.length, 0);
});

Deno.test('missing obfuscatedAccountId → 400', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient();
  const playBody = playOk();
  delete (playBody as Record<string, unknown>).externalAccountIdentifiers;
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2', response: { body: playBody } },
  ]);
  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_noacct' }),
    { fetchFn },
  );
  assertEquals(result.status, 400);
  assertStringIncludes(result.body.error as string, 'obfuscatedAccountId');
  assertEquals(calls.length, 0);
});

Deno.test('Play API 410 (expired/invalid token) → 400 relay', async () => {
  _resetPlayTokenCacheForTests();
  const { client } = makeClient();
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    {
      url: 'subscriptionsv2/tokens/tok_expired',
      response: { status: 410, body: { error: { code: 410, message: 'token expired' } } },
    },
  ]);
  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_expired' }),
    { fetchFn },
  );
  assertEquals(result.status, 400);
  assertEquals(result.body.error, 'Play API error');
});

Deno.test('Play API 500 → 502 relay', async () => {
  _resetPlayTokenCacheForTests();
  const { client } = makeClient();
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2', response: { status: 500, body: { error: 'boom' } } },
  ]);
  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_500' }),
    { fetchFn },
  );
  assertEquals(result.status, 502);
});

Deno.test('pending ack + no product id in Play response → 500, no :acknowledge call', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient();

  // Play returns a PENDING ack with zero lineItems — the function cannot
  // build the `:acknowledge` URL without a base product id, so it must
  // bail with 500 BEFORE marking the row acknowledged.
  const playBody: Record<string, unknown> = {
    kind: 'androidpublisher#subscriptionPurchaseV2',
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    startTime: new Date(Date.now() - 60_000).toISOString(),
    latestOrderId: 'GPA.no-line-items',
    lineItems: [],
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
    externalAccountIdentifiers: { obfuscatedExternalAccountId: FAKE_USER_ID },
  };

  let ackCalled = false;
  const base = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2/tokens/tok_nolineitem', response: { body: playBody } },
  ]);
  const fetchFn: typeof fetch = (input, init) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    if (url.includes(':acknowledge')) ackCalled = true;
    return base(input, init);
  };

  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_nolineitem' }),
    { fetchFn },
  );

  assertEquals(result.status, 500);
  assertEquals(
    result.body.error,
    'Cannot acknowledge: no product id in Play response',
  );
  // Critical: we must NOT have issued a Play :acknowledge call, and we
  // must NOT have PATCHed the row to acknowledged.
  assertEquals(ackCalled, false, ':acknowledge must not be called');
  assertEquals(
    calls.filter((c) => c.op === 'update').length,
    0,
    'no UPDATE should run when we cannot acknowledge',
  );
  // UPSERT + audit insert still ran (state is known, audit is best-effort).
  assert(calls.some((c) => c.table === 'subscriptions' && c.op === 'upsert'));
});

Deno.test('acknowledgement failure → 500, subscriptions row NOT marked acknowledged', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient();
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2/tokens/tok_ackfail', response: { body: playOk() } },
    { url: ':acknowledge', response: { status: 500, body: { error: 'ack service down' } } },
  ]);

  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_ackfail' }),
    { fetchFn },
  );

  assertEquals(result.status, 500);
  assertStringIncludes(result.body.error as string, 'Acknowledgement failed');

  // Critical: UPSERT must have fired (state is now known), but we must
  // NOT have subsequently PATCHed to mark acknowledgement_state =
  // 'acknowledged'. Only UPSERT + audit insert, no UPDATE.
  const updateCalls = calls.filter((c) => c.op === 'update');
  assertEquals(updateCalls.length, 0, 'no UPDATE should run on ack failure');
  assert(calls.some((c) => c.op === 'upsert'));
});

Deno.test('duplicate audit insert (unique violation) is tolerated', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient({
    insertError: { code: '23505', message: 'duplicate key value' },
  });
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2/tokens/tok_dup', response: { body: playOk() } },
    { url: ':acknowledge', response: { body: {} } },
  ]);

  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_dup' }),
    { fetchFn },
  );

  assertEquals(result.status, 200);
  assert(result.body.success);
  // Despite the duplicate event, we still UPSERTed and still acknowledged.
  assert(calls.some((c) => c.table === 'subscriptions' && c.op === 'upsert'));
  assert(calls.some((c) => c.table === 'subscriptions' && c.op === 'update'));
});

Deno.test('non-dedupe audit insert failure → 500', async () => {
  _resetPlayTokenCacheForTests();
  const { client } = makeClient({
    insertError: { message: 'connection refused' },
  });
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2/tokens/tok_evterr', response: { body: playOk() } },
  ]);
  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_evterr' }),
    { fetchFn },
  );
  assertEquals(result.status, 500);
  assertStringIncludes(result.body.error as string, 'subscription_events');
});

Deno.test('UPSERT failure → 500, no audit insert', async () => {
  _resetPlayTokenCacheForTests();
  const { client, calls } = makeClient({
    upsertError: { message: 'constraint violation' },
  });
  const fetchFn = buildFetchMock([
    OAUTH_TOKEN_OK,
    { url: 'subscriptionsv2/tokens/tok_upfail', response: { body: playOk() } },
  ]);
  const result = await validatePurchase(
    await baseInput(client, { purchaseToken: 'tok_upfail' }),
    { fetchFn },
  );
  assertEquals(result.status, 500);
  assertStringIncludes(result.body.error as string, 'UPSERT failed');
  assertEquals(calls.filter((c) => c.op === 'insert').length, 0);
});

// --- Partial-failure contract (Play ack succeeds, DB ack-state write fails) -
//
// When Play has acknowledged the token but the follow-up UPDATE to mark
// `acknowledgement_state='acknowledged'` in our table errors out, we must:
//   (a) still return 200 — Play is the source of truth, the reconcile cron
//       will fix the DB on its next tick, and re-returning 500 would make
//       the client re-ack a token that Play already acknowledged.
//   (b) log the DB failure via console.error so ops can alert on it.

Deno.test(
  'Play ack OK + DB ack-state update FAILS → 200 AND console.error logged',
  async () => {
    _resetPlayTokenCacheForTests();
    const { client } = makeClient({
      updateError: { message: 'db temporarily unavailable' },
    });
    const fetchFn = buildFetchMock([
      OAUTH_TOKEN_OK,
      { url: 'subscriptionsv2/tokens/tok_partial', response: { body: playOk() } },
      { url: ':acknowledge', response: { body: {} } },
    ]);

    // Spy on console.error. Capture calls + args so we can assert the
    // specific log fires on this path.
    const originalError = console.error;
    const errorCalls: unknown[][] = [];
    console.error = (...args: unknown[]) => {
      errorCalls.push(args);
    };

    try {
      const result = await validatePurchase(
        await baseInput(client, { purchaseToken: 'tok_partial' }),
        { fetchFn },
      );

      assertEquals(
        result.status,
        200,
        'DB ack-state failure must NOT downgrade to 500 — Play is acked',
      );
      assertEquals(result.body.success, true);

      // Exactly one error log from this code path, with the expected prefix.
      assertEquals(
        errorCalls.length,
        1,
        'expected one console.error for ack-state update failure',
      );
      const [msg, ctx] = errorCalls[0] as [string, Record<string, unknown>];
      assertStringIncludes(msg, 'Play ack succeeded but DB ack-state update failed');
      assertEquals(ctx.user_id, FAKE_USER_ID);
      assertEquals(ctx.purchase_token, 'tok_partial');
      assertEquals(ctx.detail, 'db temporarily unavailable');
    } finally {
      console.error = originalError;
    }
  },
);

// --- deriveEntitlement branch coverage -------------------------------------
//
// Mirrors the SQL CASE in 00025_create_entitlements_view.sql. The TS and
// SQL derivations MUST agree; these tests pin the ordering:
//   * active + not expired  → premium  (covers Play's own retry grace)
//   * in_grace_period + expires_at within our 3d soft tail → grace_period
//   * on_hold                → on_hold
//   * otherwise              → free

Deno.test('deriveEntitlement: state=active + future expires_at → premium', () => {
  const now = new Date('2025-06-01T00:00:00Z');
  const result = deriveEntitlement(
    {
      state: 'active',
      in_grace_period: false,
      expires_at: '2025-07-01T00:00:00Z',
    },
    now,
  );
  assertEquals(result, 'premium');
});

Deno.test(
  'deriveEntitlement: in_grace_period=true + state=active + future expires_at → premium'
    + ' (Play retry window, not our soft tail)',
  () => {
    const now = new Date('2025-06-01T00:00:00Z');
    // Play is actively retrying billing — state stays active and
    // expires_at is still in the future. Per the view ordering, this
    // must resolve to `premium`, NOT `grace_period`.
    const result = deriveEntitlement(
      {
        state: 'active',
        in_grace_period: true,
        expires_at: '2025-06-05T00:00:00Z',
      },
      now,
    );
    assertEquals(result, 'premium');
  },
);

Deno.test(
  'deriveEntitlement: in_grace_period=true + expires_at just past + state!=active → grace_period',
  () => {
    const now = new Date('2025-06-01T00:00:00Z');
    // expires_at slipped 1 day into the past; our 3d soft tail still
    // applies. State is not active because Play may have transitioned
    // it (e.g. expired) by the time the client polls, but the grace
    // flag was captured from the prior RTDN.
    const result = deriveEntitlement(
      {
        state: 'expired',
        in_grace_period: true,
        expires_at: '2025-05-31T00:00:00Z',
      },
      now,
    );
    assertEquals(result, 'grace_period');
  },
);

Deno.test(
  'deriveEntitlement: in_grace_period=true + expires_at >3d past → free',
  () => {
    const now = new Date('2025-06-10T00:00:00Z');
    const result = deriveEntitlement(
      {
        state: 'expired',
        in_grace_period: true,
        expires_at: '2025-06-01T00:00:00Z', // 9 days past, outside the 3d tail
      },
      now,
    );
    assertEquals(result, 'free');
  },
);

Deno.test('deriveEntitlement: state=on_hold → on_hold', () => {
  const now = new Date('2025-06-10T00:00:00Z');
  const result = deriveEntitlement(
    {
      state: 'on_hold',
      in_grace_period: false,
      expires_at: '2025-06-01T00:00:00Z',
    },
    now,
  );
  assertEquals(result, 'on_hold');
});

Deno.test('deriveEntitlement: no expires_at → free', () => {
  const result = deriveEntitlement(
    { state: 'active', in_grace_period: false, expires_at: null },
    new Date('2025-06-10T00:00:00Z'),
  );
  assertEquals(result, 'free');
});

// --- isServiceRoleJwt decoder ----------------------------------------------
//
// The HTTP wrapper uses this to detect the reconcile cron's caller.
// We decode the middle segment and check payload.role without verifying
// the signature (the Edge Function runtime verified it). These tests lock
// that contract and ensure garbage input returns false rather than
// throwing.

function encodeJwtPayload(payload: unknown): string {
  const header = { alg: 'HS256', typ: 'JWT' };
  const b64url = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  const h = b64url(JSON.stringify(header));
  const p = b64url(JSON.stringify(payload));
  // Signature segment is irrelevant for decoding; use a fixed placeholder.
  return `${h}.${p}.sig`;
}

Deno.test('isServiceRoleJwt: role=service_role → true', () => {
  const jwt = encodeJwtPayload({ role: 'service_role', iss: 'supabase' });
  assertEquals(isServiceRoleJwt(jwt), true);
});

Deno.test('isServiceRoleJwt: role=authenticated → false', () => {
  const jwt = encodeJwtPayload({ role: 'authenticated', sub: 'some-user-id' });
  assertEquals(isServiceRoleJwt(jwt), false);
});

Deno.test('isServiceRoleJwt: role missing → false', () => {
  const jwt = encodeJwtPayload({ sub: 'anon' });
  assertEquals(isServiceRoleJwt(jwt), false);
});

Deno.test('isServiceRoleJwt: malformed input → false (no throw)', () => {
  assertEquals(isServiceRoleJwt(''), false);
  assertEquals(isServiceRoleJwt('not.a.jwt'), false);
  assertEquals(isServiceRoleJwt('onlyonepart'), false);
  assertEquals(isServiceRoleJwt('a..c'), false);
});

// --- Phase 33 PR 33a: handleRequest defense-in-depth ----------------------
//
// These tests drive the HTTP boundary directly via the exported
// `handleRequest()` so we can assert on the body-size cap, JWT exp
// precheck, and input-validation rejections WITHOUT spinning up the
// Edge Runtime. The pure validatePurchase() core remains the focus of
// the tests above — these only cover the defensive layer in front of
// it (findings 026 / 027 / 028).
//
// For each rejection path we also assert no Supabase / Play work was
// triggered — that's the "behavior, not wiring" contract: a rejection
// MUST short-circuit before the expensive code runs.

function makeRequest(opts: {
  authorization?: string | null;
  contentLength?: string | null;
  body?: string;
}): Request {
  const headers = new Headers();
  if (opts.authorization !== null && opts.authorization !== undefined) {
    headers.set('Authorization', opts.authorization);
  }
  if (opts.contentLength !== null && opts.contentLength !== undefined) {
    headers.set('Content-Length', opts.contentLength);
  }
  if (opts.body !== undefined) {
    headers.set('content-type', 'application/json');
  }
  return new Request('https://example.local/validate-purchase', {
    method: 'POST',
    headers,
    body: opts.body,
  });
}

/** Future-dated JWT exp (1h from now). */
function freshJwt(extraPayload: Record<string, unknown> = {}): string {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  return encodeJwtPayload({ exp, role: 'authenticated', ...extraPayload });
}

/** Expired JWT exp (1s ago). */
function expiredJwt(): string {
  const exp = Math.floor(Date.now() / 1000) - 1;
  return encodeJwtPayload({ exp, role: 'authenticated', sub: 'u1' });
}

/** A fetch spy that throws if invoked. Used to assert the rejection
 *  path didn't reach Play API. */
function fetchSpyThatMustNotFire(): typeof fetch {
  return (input) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    throw new Error(`fetch must NOT have fired during rejection: ${url}`);
  };
}

/** A SupabaseClient stub that throws on any DB op — confirms the
 *  rejection short-circuited before reaching the DB. */
function clientSpyThatMustNotFire(): unknown {
  return {
    from(_table: string) {
      throw new Error('client.from must NOT have fired during rejection');
    },
    auth: {
      getUser(_jwt: string) {
        throw new Error('auth.getUser must NOT have fired during rejection');
      },
    },
  };
}

Deno.test('validate-purchase: 413 on >32KB Content-Length, no body parse', async () => {
  const res = await handleRequest(
    makeRequest({
      authorization: `Bearer ${freshJwt()}`,
      contentLength: '40000',
      body: JSON.stringify({ product_id: 'x', purchase_token: 'y' }),
    }),
    {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
      fetchFn: fetchSpyThatMustNotFire(),
    },
  );
  assertEquals(res.status, 413);
  const body = await res.json();
  assertStringIncludes(String(body.error), 'Payload too large');
});

Deno.test(
  'validate-purchase: 401 on expired JWT BEFORE body parse',
  async () => {
    // Spy on the body: if the handler ever calls .json() / .text() on the
    // request, this token would have to be read. We assert the body was
    // NEVER consumed by checking req.bodyUsed after the call.
    const req = makeRequest({
      authorization: `Bearer ${expiredJwt()}`,
      body: JSON.stringify({ product_id: 'x', purchase_token: 'y' }),
    });

    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
      fetchFn: fetchSpyThatMustNotFire(),
    });
    assertEquals(res.status, 401);
    assertEquals(
      req.bodyUsed,
      false,
      'request body must NOT be consumed on expired-JWT short-circuit',
    );
  },
);

Deno.test(
  'validate-purchase: 401 on malformed JWT (no exp claim) BEFORE body parse',
  async () => {
    // Pins the precheck at the HTTP boundary, not just the helper.
    // If `precheckJwtExp` were ever skipped in `handleRequest`, the
    // auth.test.ts unit tests would still pass — only this HTTP-boundary
    // test catches that regression.
    const noExpJwt = encodeJwtPayload({ role: 'authenticated', sub: 'u1' });
    const req = makeRequest({
      authorization: `Bearer ${noExpJwt}`,
      body: JSON.stringify({ product_id: 'x', purchase_token: 'y' }),
    });

    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
      fetchFn: fetchSpyThatMustNotFire(),
    });
    assertEquals(res.status, 401);
    assertEquals(
      req.bodyUsed,
      false,
      'request body must NOT be consumed on malformed-JWT short-circuit',
    );
  },
);

Deno.test('validate-purchase: 400 on product_id > 128 chars', async () => {
  const longId = 'a'.repeat(129);
  const res = await handleRequest(
    makeRequest({
      authorization: `Bearer ${freshJwt({ role: 'service_role' })}`,
      body: JSON.stringify({
        product_id: longId,
        purchase_token: 'tok',
        source: 'cron_reconcile',
        user_id: FAKE_USER_ID,
      }),
    }),
    {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
      fetchFn: fetchSpyThatMustNotFire(),
    },
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertStringIncludes(String(body.error), 'product_id');
});

Deno.test('validate-purchase: 400 on purchase_token > 4096 chars', async () => {
  const longToken = 'b'.repeat(4097);
  const res = await handleRequest(
    makeRequest({
      authorization: `Bearer ${freshJwt({ role: 'service_role' })}`,
      body: JSON.stringify({
        product_id: 'p',
        purchase_token: longToken,
        source: 'cron_reconcile',
        user_id: FAKE_USER_ID,
      }),
    }),
    {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
      fetchFn: fetchSpyThatMustNotFire(),
    },
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertStringIncludes(String(body.error), 'purchase_token');
});

Deno.test('validate-purchase: 400 on source not in allow-list', async () => {
  const res = await handleRequest(
    makeRequest({
      authorization: `Bearer ${freshJwt({ role: 'service_role' })}`,
      body: JSON.stringify({
        product_id: 'p',
        purchase_token: 'tok',
        source: 'attacker',
        user_id: FAKE_USER_ID,
      }),
    }),
    {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
      fetchFn: fetchSpyThatMustNotFire(),
    },
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertStringIncludes(String(body.error), 'source');
});

Deno.test(
  'validate-purchase: 400 on malformed user_id (non-UUID)',
  async () => {
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt({ role: 'service_role' })}`,
        body: JSON.stringify({
          product_id: 'p',
          purchase_token: 'tok',
          source: 'cron_reconcile',
          user_id: 'not-a-uuid',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: clientSpyThatMustNotFire() as any,
        // deno-lint-ignore no-explicit-any
        userClient: clientSpyThatMustNotFire() as any,
        fetchFn: fetchSpyThatMustNotFire(),
      },
    );
    assertEquals(res.status, 400);
    const body = await res.json();
    assertStringIncludes(String(body.error), 'user_id');
  },
);

Deno.test(
  'validate-purchase: source defaults to "client" when omitted (valid path passes validation gate)',
  async () => {
    // Source is optional — when omitted the handler must NOT reject for
    // "source not in allow-list". This pins that the default ('client')
    // is allow-listed; it's a regression guard against accidentally
    // tightening the allow-list to require an explicit value.
    _resetPlayTokenCacheForTests();
    const { client: adminClient } = makeClient();
    const fetchFn = buildFetchMock([
      OAUTH_TOKEN_OK,
      { url: 'subscriptionsv2/tokens/tok_default_source', response: { body: playOk() } },
      { url: ':acknowledge', response: { body: {} } },
    ]);
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt({ role: 'service_role' })}`,
        body: JSON.stringify({
          product_id: 'p',
          purchase_token: 'tok_default_source',
          // source intentionally omitted
          user_id: FAKE_USER_ID,
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: clientSpyThatMustNotFire() as any,
        fetchFn,
        serviceAccount: await getFakeServiceAccount(),
        packageName: 'com.repsaga.app',
      },
    );
    // 200 — the validation gate passed through to the real flow.
    assertEquals(res.status, 200);
  },
);
