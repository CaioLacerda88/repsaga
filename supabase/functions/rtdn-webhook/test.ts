// Unit tests for rtdn-webhook Edge Function.
//
// We exercise `handleRtdn()` + `rtdnTypeToStatePatch()` +
// `decodePubSubPayload()` directly. HTTP boundary + Pub/Sub JWT
// verification are covered by a dedicated JWT test against the shared
// helper (`_shared/google_play.test.ts`) — this file focuses on state
// machine + idempotency.
//
// Run with: deno test --allow-net --allow-env supabase/functions/

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  decodePubSubPayload,
  handleRequest,
  handleRtdn,
  rtdnTypeToStatePatch,
} from './index.ts';

const FAKE_TOKEN = 'tok_rtdn_1';
const FAKE_USER_ID = '33333333-3333-3333-3333-333333333333';

// --- In-memory Supabase client stub ---------------------------------------
//
// We implement just enough of the builder API shape that handleRtdn
// exercises: `.from(table).select('...').eq('purchase_token', x).maybeSingle()`,
// `.from(table).insert(row)`, and `.from(table).update(patch).eq(...).eq(...)`.
// All chain methods return `this`; the terminal awaitable returns the
// response shape `{ data, error }` via `.then()`.

interface StubCall {
  table: string;
  op: 'select' | 'insert' | 'update';
  payload?: unknown;
}

function makeClient(opts: {
  lookupUser?: string | null;
  insertError?: { code?: string; message: string };
  updateError?: { code?: string; message: string };
} = {}): { client: unknown; calls: StubCall[] } {
  const calls: StubCall[] = [];
  const client = {
    from(table: string) {
      const ctx = {
        _table: table,
        _op: null as 'select' | 'insert' | 'update' | null,
        _payload: undefined as unknown,
        select(_cols: string) {
          this._op = 'select';
          return this;
        },
        eq(_k: string, _v: unknown) {
          return this;
        },
        insert(row: unknown) {
          this._op = 'insert';
          this._payload = row;
          calls.push({ table: this._table, op: 'insert', payload: row });
          return Promise.resolve(
            opts.insertError ? { data: null, error: opts.insertError } : { data: row, error: null },
          );
        },
        update(patch: unknown) {
          this._op = 'update';
          this._payload = patch;
          calls.push({ table: this._table, op: 'update', payload: patch });
          return {
            eq(_k: string, _v: unknown) {
              return {
                eq(_k2: string, _v2: unknown) {
                  return Promise.resolve(
                    opts.updateError
                      ? { data: null, error: opts.updateError }
                      : { data: patch, error: null },
                  );
                },
              };
            },
          };
        },
        maybeSingle() {
          calls.push({ table: this._table, op: 'select' });
          if (opts.lookupUser === undefined || opts.lookupUser === null) {
            return Promise.resolve({ data: null, error: null });
          }
          return Promise.resolve({ data: { user_id: opts.lookupUser }, error: null });
        },
      };
      return ctx;
    },
  };
  return { client, calls };
}

// --- envelope builder ------------------------------------------------------

function makeEnvelope(rtdnPayload: unknown): { message: { data: string } } {
  const json = JSON.stringify(rtdnPayload);
  // Standard (non-URL-safe) base64 — matches Pub/Sub push.
  const b64 = btoa(json);
  return { message: { data: b64 } };
}

// --- state mapping table ---------------------------------------------------

Deno.test('rtdnTypeToStatePatch covers all 10 documented + restarted + deferred', () => {
  const expectations: Record<number, { state?: string; in_grace_period?: boolean }> = {
    1:  { state: 'active',    in_grace_period: false },   // RECOVERED
    2:  { state: 'active',    in_grace_period: false },   // RENEWED
    3:  { state: 'canceled' },                            // CANCELED
    4:  { state: 'active',    in_grace_period: false },   // PURCHASED
    5:  { state: 'on_hold',   in_grace_period: false },   // ON_HOLD
    6:  { state: 'active',    in_grace_period: true  },   // IN_GRACE_PERIOD
    7:  { state: 'active',    in_grace_period: false },   // RESTARTED
    9:  { state: 'active',    in_grace_period: false },   // DEFERRED
    10: { state: 'paused' },                              // PAUSED
    12: { state: 'revoked' },                             // REVOKED
    13: { state: 'expired' },                             // EXPIRED
  };
  for (const [type, expected] of Object.entries(expectations)) {
    const patch = rtdnTypeToStatePatch(Number(type));
    assert(patch, `no patch for type ${type}`);
    if (expected.state !== undefined) assertEquals(patch.state, expected.state);
    if (expected.in_grace_period !== undefined) {
      assertEquals(patch.in_grace_period, expected.in_grace_period);
    }
  }
});

Deno.test('rtdnTypeToStatePatch returns null for unknown types', () => {
  assertEquals(rtdnTypeToStatePatch(42), null);
  assertEquals(rtdnTypeToStatePatch(0), null);
});

// --- decoder ---------------------------------------------------------------

Deno.test('decodePubSubPayload base64-decodes + parses', () => {
  const env = makeEnvelope({
    eventTimeMillis: '1700000000000',
    packageName: 'com.repsaga.app',
    subscriptionNotification: {
      notificationType: 4,
      purchaseToken: FAKE_TOKEN,
      subscriptionId: 'repsaga_premium',
    },
  });
  const payload = decodePubSubPayload(env);
  assertEquals(payload.subscriptionNotification?.notificationType, 4);
  assertEquals(payload.subscriptionNotification?.purchaseToken, FAKE_TOKEN);
});

Deno.test('decodePubSubPayload throws on missing message.data', () => {
  try {
    decodePubSubPayload({ message: {} });
    throw new Error('expected throw');
  } catch (e) {
    assert(String(e).includes('missing message.data'));
  }
});

// --- handleRtdn: happy path for each type ---------------------------------

for (const type of [1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 13]) {
  Deno.test(`handleRtdn type=${type} → UPSERT + state patch + 200`, async () => {
    const { client, calls } = makeClient({ lookupUser: FAKE_USER_ID });
    const payload = {
      eventTimeMillis: '1700000000000',
      packageName: 'com.repsaga.app',
      subscriptionNotification: {
        notificationType: type,
        purchaseToken: FAKE_TOKEN,
        subscriptionId: 'repsaga_premium',
      },
    };
    // deno-lint-ignore no-explicit-any
    const res = await handleRtdn(payload, { client: client as any });
    assertEquals(res.status, 200);
    assertEquals(res.body.success, true);
    assertEquals(res.body.notification_type, type);
    // audit insert + subscriptions update
    const ops = calls.map((c) => `${c.table}.${c.op}`);
    assert(ops.includes('subscription_events.insert'));
    assert(ops.includes('subscriptions.update'));
  });
}

// --- idempotency ----------------------------------------------------------

Deno.test('duplicate RTDN → 23505 short-circuits with 200 and NO state update', async () => {
  const { client, calls } = makeClient({
    lookupUser: FAKE_USER_ID,
    insertError: { code: '23505', message: 'duplicate key' },
  });
  const payload = {
    eventTimeMillis: '1700000000000',
    subscriptionNotification: {
      notificationType: 2,
      purchaseToken: FAKE_TOKEN,
    },
  };
  // deno-lint-ignore no-explicit-any
  const res = await handleRtdn(payload, { client: client as any });
  assertEquals(res.status, 200);
  assertEquals(res.body.duplicate, true);
  // No subscriptions.update because we bailed before applying the patch.
  const updates = calls.filter((c) => c.op === 'update');
  assertEquals(updates.length, 0);
});

Deno.test('RTDN for unknown purchase_token → audit skipped, state skipped, still 200', async () => {
  const { client, calls } = makeClient({ lookupUser: null });
  const payload = {
    eventTimeMillis: '1700000000000',
    subscriptionNotification: {
      notificationType: 4,
      purchaseToken: 'tok_unknown',
    },
  };
  // deno-lint-ignore no-explicit-any
  const res = await handleRtdn(payload, { client: client as any });
  assertEquals(res.status, 200);
  assertEquals(res.body.known_user, false);
  // No inserts / updates because we don't know who this belongs to.
  const writes = calls.filter((c) => c.op !== 'select');
  assertEquals(writes.length, 0);
});

Deno.test('testNotification → 200 without DB touch', async () => {
  const { client, calls } = makeClient();
  // deno-lint-ignore no-explicit-any
  const res = await handleRtdn({ testNotification: { version: '1.0' } }, { client: client as any });
  assertEquals(res.status, 200);
  assertEquals(res.body.test, true);
  assertEquals(calls.length, 0);
});

Deno.test('unknown notificationType → 200 with audit only', async () => {
  const { client, calls } = makeClient({ lookupUser: FAKE_USER_ID });
  const payload = {
    subscriptionNotification: {
      notificationType: 999,
      purchaseToken: FAKE_TOKEN,
    },
  };
  // deno-lint-ignore no-explicit-any
  const res = await handleRtdn(payload, { client: client as any });
  assertEquals(res.status, 200);
  assertEquals(res.body.unknown_type, 999);
  // audit row was inserted but no state patch fired.
  assert(calls.some((c) => c.op === 'insert'));
  assert(!calls.some((c) => c.op === 'update'));
});

Deno.test('missing subscriptionNotification → 200 ignored', async () => {
  const { client, calls } = makeClient({ lookupUser: FAKE_USER_ID });
  // deno-lint-ignore no-explicit-any
  const res = await handleRtdn({}, { client: client as any });
  assertEquals(res.status, 200);
  assertEquals(res.body.ignored, 'no subscriptionNotification');
  assertEquals(calls.length, 0);
});

Deno.test('state update error → 500', async () => {
  const { client } = makeClient({
    lookupUser: FAKE_USER_ID,
    updateError: { message: 'connection refused' },
  });
  // deno-lint-ignore no-explicit-any
  const res = await handleRtdn(
    {
      subscriptionNotification: {
        notificationType: 4,
        purchaseToken: FAKE_TOKEN,
      },
    },
    { client: client as any },
  );
  assertEquals(res.status, 500);
});

// --- Phase 33 PR 33a: body + base64 size caps (findings 028 / 033) -------
//
// rtdn-webhook receives Pub/Sub push envelopes carrying base64-encoded
// RTDN payloads. Two layers of defense:
//   * 16KB request-body cap (finding-028) at the HTTP boundary
//   * 16KB base64-decoded payload cap (finding-033) inside
//     decodePubSubPayload
// Real Pub/Sub envelopes are ≤ ~8KB; anything > 16KB is malicious.

function makeRtdnRequest(opts: {
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
  return new Request('https://example.local/rtdn-webhook', {
    method: 'POST',
    headers,
    body: opts.body,
  });
}

function clientSpyThatMustNotFire(): unknown {
  return {
    from(_table: string) {
      throw new Error('client.from must NOT have fired during rejection');
    },
  };
}

Deno.test(
  'rtdn-webhook: 413 on >16KB Content-Length, no JWT verify, no body parse',
  async () => {
    const req = makeRtdnRequest({
      authorization: 'Bearer anything',
      contentLength: '20000',
      body: '{}',
    });
    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      client: clientSpyThatMustNotFire() as any,
      verifyJwt: () => {
        throw new Error('verifyJwt must NOT have fired on body-too-big');
      },
      expectedAudience: 'aud',
    });
    assertEquals(res.status, 413);
    assertEquals(
      req.bodyUsed,
      false,
      'request body must NOT be consumed on 413 short-circuit',
    );
  },
);

Deno.test(
  'rtdn-webhook: 400 on >16KB decoded base64 payload',
  async () => {
    // Build a JSON payload > 16KB. Padded with junk attributes the
    // production code doesn't read — the size check fires on
    // decoded-length BEFORE JSON.parse so the shape is irrelevant.
    const filler = 'x'.repeat(20000);
    const oversizedJson = JSON.stringify({
      version: '1.0',
      packageName: 'com.repsaga.app',
      junk: filler,
    });
    // The base64-encoded envelope itself is ~27KB but we don't tag
    // Content-Length on the envelope (handleRequest's body cap is
    // independent of the inner-payload cap). The inner cap is what
    // we're exercising here. The envelope JSON wraps the base64.
    const envelope = {
      message: { data: btoa(oversizedJson) },
    };
    const req = makeRtdnRequest({
      authorization: 'Bearer fake',
      body: JSON.stringify(envelope),
      // Set Content-Length below the 16KB outer cap so we exercise the
      // INNER (decoded base64) cap, not the outer body cap.
      contentLength: '15000',
    });
    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      client: clientSpyThatMustNotFire() as any,
      // Stub the JWT verify — we already covered that path elsewhere.
      verifyJwt: () => Promise.resolve(),
      expectedAudience: 'aud',
    });
    assertEquals(res.status, 400);
    const body = await res.json();
    assertStringIncludes(String(body.error), 'Malformed Pub/Sub payload');
    assertStringIncludes(String(body.detail), 'payload too large');
  },
);

Deno.test(
  'decodePubSubPayload: throws on >16KB decoded base64',
  () => {
    // Direct unit test on decodePubSubPayload — the size guard lives
    // there (not in handleRequest) so this is the canonical pin.
    const oversizedJson = JSON.stringify({
      version: '1.0',
      junk: 'y'.repeat(20000),
    });
    const env = { message: { data: btoa(oversizedJson) } };
    let threw: Error | null = null;
    try {
      decodePubSubPayload(env);
    } catch (e) {
      threw = e as Error;
    }
    assert(threw !== null, 'expected throw on oversized payload');
    assertStringIncludes(String(threw!.message), 'payload too large');
  },
);

Deno.test(
  'decodePubSubPayload: ≤16KB decoded payload decodes normally',
  () => {
    // Sanity guard — the size cap must NOT reject realistically-sized
    // RTDN payloads. Real Pub/Sub messages are ≤ ~2KB. Build a 1KB
    // payload and confirm round-trip.
    const payload = {
      version: '1.0',
      packageName: 'com.repsaga.app',
      subscriptionNotification: {
        notificationType: 4,
        purchaseToken: FAKE_TOKEN,
        subscriptionId: 'repsaga_premium',
      },
      padding: 'z'.repeat(800),
    };
    const env = { message: { data: btoa(JSON.stringify(payload)) } };
    const decoded = decodePubSubPayload(env);
    assertEquals(decoded.subscriptionNotification?.notificationType, 4);
  },
);
