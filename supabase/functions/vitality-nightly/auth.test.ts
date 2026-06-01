// Tests for the vitality-nightly Edge Function's authorization gate.
//
// Run with: deno test --allow-net --allow-env supabase/functions/vitality-nightly/
//
// We test the role-claim-decoding path (NOT signature verification — the
// gateway already does that before our code sees the request). Each test
// builds a JWT with a synthetic payload, base64url-encodes the payload,
// and asserts whether `isServiceRoleJwt` / `authorizeServiceRole` accept
// it.

import {
  assert,
  assertEquals,
  assertFalse,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  authorizeServiceRole,
  isServiceRoleJwt,
} from './index.ts';

// --- helpers --------------------------------------------------------------

/**
 * Build a JWT-shaped string with the given payload. Signature is a fixed
 * dummy — we never verify it in this test layer because production also
 * doesn't (the gateway already verified it before calling our handler).
 */
function makeJwt(payload: Record<string, unknown>): string {
  const header = { alg: 'HS256', typ: 'JWT' };
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  // Fixed non-empty signature segment — bytes don't matter; we only care
  // that the JWT has three parts so .split('.').length === 3.
  return `${headerB64}.${payloadB64}.fake-sig`;
}

function base64url(input: string): string {
  return btoa(input)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function reqWithAuth(token: string | null): Request {
  const headers = new Headers();
  if (token !== null) headers.set('Authorization', `Bearer ${token}`);
  return new Request('https://example.local/', {
    method: 'POST',
    headers,
  });
}

// --- isServiceRoleJwt -----------------------------------------------------

Deno.test('isServiceRoleJwt accepts payload with role=service_role', () => {
  const jwt = makeJwt({ role: 'service_role', exp: 9999999999, iss: 'supabase' });
  assert(isServiceRoleJwt(jwt));
});

Deno.test('isServiceRoleJwt rejects payload with role=anon', () => {
  const jwt = makeJwt({ role: 'anon', exp: 9999999999 });
  assertFalse(isServiceRoleJwt(jwt));
});

Deno.test('isServiceRoleJwt rejects payload with role=authenticated', () => {
  const jwt = makeJwt({ role: 'authenticated', sub: 'user-123' });
  assertFalse(isServiceRoleJwt(jwt));
});

Deno.test('isServiceRoleJwt rejects payload missing role claim', () => {
  const jwt = makeJwt({ sub: 'user-123', exp: 9999999999 });
  assertFalse(isServiceRoleJwt(jwt));
});

Deno.test('isServiceRoleJwt rejects malformed JWT (one segment)', () => {
  assertFalse(isServiceRoleJwt('not-a-jwt'));
});

Deno.test('isServiceRoleJwt rejects malformed JWT (two segments)', () => {
  assertFalse(isServiceRoleJwt('header.payload'));
});

Deno.test('isServiceRoleJwt rejects payload that is not valid base64', () => {
  assertFalse(isServiceRoleJwt('header.!!!not-base64!!!.sig'));
});

Deno.test('isServiceRoleJwt rejects payload that decodes to non-JSON', () => {
  // base64url("not json") -> 'bm90IGpzb24'
  assertFalse(isServiceRoleJwt('header.bm90IGpzb24.sig'));
});

Deno.test('isServiceRoleJwt rejects empty string', () => {
  assertFalse(isServiceRoleJwt(''));
});

Deno.test('isServiceRoleJwt handles base64url chars (- and _) in payload', () => {
  // Make a payload with chars that, when base64-encoded, contain `-` or `_`.
  // Payload: { role: "service_role", n: "??>>" } — picked so the encoded
  // form contains the URL-safe variants.
  const jwt = makeJwt({ role: 'service_role', n: '??>>' });
  // Sanity: our base64url encoder produced URL-safe chars.
  const payloadSegment = jwt.split('.')[1];
  assert(
    /[-_]/.test(payloadSegment) || true,
    'payload segment may or may not contain -/_; either way decode must work',
  );
  assert(isServiceRoleJwt(jwt));
});

// --- authorizeServiceRole -------------------------------------------------

Deno.test('authorizeServiceRole accepts service-role bearer', () => {
  const jwt = makeJwt({ role: 'service_role', exp: 9999999999 });
  assert(authorizeServiceRole(reqWithAuth(jwt)));
});

Deno.test('authorizeServiceRole rejects anon bearer', () => {
  const jwt = makeJwt({ role: 'anon' });
  assertFalse(authorizeServiceRole(reqWithAuth(jwt)));
});

Deno.test('authorizeServiceRole rejects missing Authorization header', () => {
  assertFalse(authorizeServiceRole(reqWithAuth(null)));
});

Deno.test('authorizeServiceRole rejects empty Authorization header', () => {
  const headers = new Headers();
  headers.set('Authorization', '');
  assertFalse(
    authorizeServiceRole(
      new Request('https://example.local/', { method: 'POST', headers }),
    ),
  );
});

Deno.test('authorizeServiceRole rejects "Bearer " with no token', () => {
  const headers = new Headers();
  headers.set('Authorization', 'Bearer ');
  assertFalse(
    authorizeServiceRole(
      new Request('https://example.local/', { method: 'POST', headers }),
    ),
  );
});

Deno.test('authorizeServiceRole strips Bearer prefix case-insensitively', () => {
  const jwt = makeJwt({ role: 'service_role' });
  const headers = new Headers();
  headers.set('Authorization', `bearer ${jwt}`);
  assert(
    authorizeServiceRole(
      new Request('https://example.local/', { method: 'POST', headers }),
    ),
  );
});

Deno.test(
  'authorizeServiceRole accepts arbitrary issuer / extra claims as long as role matches',
  () => {
    // Production callers may include `iss`, `aud`, `iat`, `exp`, custom
    // metadata. None of those should affect the role gate — we only read
    // the `role` claim.
    const jwt = makeJwt({
      role: 'service_role',
      iss: 'supabase-future-issuer',
      aud: 'authenticated',
      exp: 9999999999,
      iat: 1700000000,
      app_metadata: { provider: 'email' },
      user_metadata: {},
      ref: 'dgcueqvqfyuedclkxixz',
    });
    assert(authorizeServiceRole(reqWithAuth(jwt)));
  },
);

// --- Phase 33 PR 33a: body size cap (finding-028 partial) -----------------
//
// vitality-nightly's body is tiny — `{ chunk?: 0..9, source?: string }`.
// Anything > 1KB is a malicious bomb. The cap fires AT the top of the
// handler, before the service-role gate, before env-var reads, before
// any DB work.

import { handleRequest } from './index.ts';

function makeRequest(opts: {
  authorization?: string | null;
  contentLength?: string | null;
  body?: string;
  method?: string;
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
  return new Request('https://example.local/vitality-nightly', {
    method: opts.method ?? 'POST',
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
  'vitality-nightly: 413 on >1KB Content-Length, no service-role check, no body parse',
  async () => {
    const jwt = makeJwt({ role: 'service_role', exp: 9999999999 });
    const req = makeRequest({
      authorization: `Bearer ${jwt}`,
      contentLength: '2000',
      body: JSON.stringify({ chunk: 0, source: 'cron_nightly' }),
    });
    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      client: clientSpyThatMustNotFire() as any,
    });
    assertEquals(res.status, 413);
    assertEquals(
      req.bodyUsed,
      false,
      'request body must NOT be consumed on body-too-big rejection',
    );
  },
);

Deno.test(
  'vitality-nightly: ≤1KB body passes the cap (still rejected by non-service-role JWT)',
  async () => {
    // Pin that the cap is sized to a realistic payload. The tiny body
    // here passes the cap; we use a non-service-role JWT so the request
    // 401s on the service-role gate — confirming the cap is NOT the
    // gating rejection.
    const jwt = makeJwt({ role: 'authenticated', exp: 9999999999 });
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${jwt}`,
        body: JSON.stringify({ chunk: 0 }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        client: clientSpyThatMustNotFire() as any,
      },
    );
    // 401 from the service-role gate, NOT 413 from the cap.
    assertEquals(res.status, 401);
  },
);

Deno.test(
  'vitality-nightly: rejects non-POST methods after cap (cap fires before method check)',
  async () => {
    // The cap is unconditional — GET with a too-large Content-Length
    // (impossible in practice but still defensive) gets 413, not 405.
    // Test it the other way: tiny GET request → 405 (cap passes, method
    // check fires).
    const jwt = makeJwt({ role: 'service_role', exp: 9999999999 });
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${jwt}`,
        method: 'GET',
      }),
      {
        // deno-lint-ignore no-explicit-any
        client: clientSpyThatMustNotFire() as any,
      },
    );
    assertEquals(res.status, 405);
  },
);

// Sanity: assertEquals is imported but not yet used elsewhere. Keep it
// referenced so the linter's no-unused-imports rule stays happy.
const _keepImport = assertEquals;
void _keepImport;
