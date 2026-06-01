// Unit tests for `_shared/auth.ts` — body-size cap + JWT exp precheck.
//
// Run with: deno test --allow-net --allow-env supabase/functions/_shared/auth.test.ts
//
// These helpers underpin Edge Function defense-in-depth (Phase 33 PR 33a,
// audit findings 027, 028, 030, 033). Each helper is pure / I/O-free:
//
//   requireBodySize(req, max, corsHeaders) — returns a 413 Response when
//     Content-Length exceeds `max`; returns null when the header is missing
//     OR ≤ max. Missing header is treated as OK to proceed (the Edge Runtime
//     still applies its platform-level ceiling upstream — see
//     pre-launch-audit.md finding-028).
//
//   precheckJwtExp(jwt) — cheap local decode + `exp` claim check. Does NOT
//     verify the signature (the Supabase gateway already did before our
//     handler runs). Use BEFORE `req.json()` to short-circuit malformed /
//     expired JWTs without paying the body-parse cost. Caller must still
//     perform the full validity check via `auth.getUser(jwt)` for
//     non-repudiation.

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { precheckJwtExp, requireBodySize } from './auth.ts';

// --- Test helpers ----------------------------------------------------------

const CORS = {
  'Access-Control-Allow-Origin': 'http://localhost:54321',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  Vary: 'Origin',
};

function reqWithContentLength(value: string | null): Request {
  const headers = new Headers();
  if (value !== null) headers.set('Content-Length', value);
  return new Request('https://example.local/', {
    method: 'POST',
    headers,
  });
}

/** Build a JWT-shaped string with the given payload claims. Signature is a
 * fixed dummy — production callers reach us only after the gateway has
 * already verified the signature, so the precheck never re-verifies. */
function makeJwt(payload: Record<string, unknown>): string {
  const header = { alg: 'HS256', typ: 'JWT' };
  const b64url = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}.sig`;
}

// --- requireBodySize -------------------------------------------------------

Deno.test('requireBodySize: missing Content-Length → null (proceed)', () => {
  const result = requireBodySize(reqWithContentLength(null), 1024, CORS);
  assertEquals(result, null);
});

Deno.test('requireBodySize: Content-Length below max → null (proceed)', () => {
  const result = requireBodySize(reqWithContentLength('500'), 1024, CORS);
  assertEquals(result, null);
});

Deno.test('requireBodySize: Content-Length equal to max → null (proceed)', () => {
  const result = requireBodySize(reqWithContentLength('1024'), 1024, CORS);
  assertEquals(result, null);
});

Deno.test('requireBodySize: Content-Length above max → 413 Response', async () => {
  const result = requireBodySize(reqWithContentLength('2048'), 1024, CORS);
  assert(result instanceof Response, 'expected Response when over max');
  assertEquals(result.status, 413);
  const body = await result.json();
  assertEquals(body.error, 'Payload too large');
  assertEquals(body.maxBytes, 1024);
});

Deno.test(
  'requireBodySize: 413 Response carries CORS headers from caller',
  () => {
    const result = requireBodySize(reqWithContentLength('9999'), 1024, CORS);
    assert(result instanceof Response);
    assertEquals(
      result.headers.get('Access-Control-Allow-Origin'),
      'http://localhost:54321',
    );
    assertEquals(result.headers.get('Vary'), 'Origin');
    assertEquals(result.headers.get('Content-Type'), 'application/json');
  },
);

Deno.test('requireBodySize: non-numeric Content-Length → null (treat as missing)', () => {
  // A non-numeric Content-Length isn't a valid HTTP header value — Deno's
  // platform-level body cap will still catch the actual body size. We
  // intentionally don't 413 on parse failure: parseInt('abc',10) → NaN,
  // and `NaN > maxBytes` is false, so we fall through to null. Pinning this
  // behavior so a later refactor doesn't accidentally start rejecting
  // ambiguous headers.
  const result = requireBodySize(reqWithContentLength('abc'), 1024, CORS);
  assertEquals(result, null);
});

// --- precheckJwtExp --------------------------------------------------------

Deno.test('precheckJwtExp: future exp → { valid: true }', () => {
  // 1 hour from now (seconds since epoch).
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const result = precheckJwtExp(makeJwt({ exp, role: 'authenticated' }));
  assertEquals(result.valid, true);
  assertEquals(result.reason, undefined);
});

Deno.test('precheckJwtExp: service-role JWT with future exp → { valid: true }', () => {
  // Supabase issues service-role JWTs WITH an `exp` claim (typically 10y
  // in the future). The precheck must accept them — no special-casing of
  // role=service_role. See PR 33a plan note line 1242.
  const exp = Math.floor(Date.now() / 1000) + 10 * 365 * 24 * 3600;
  const result = precheckJwtExp(makeJwt({ role: 'service_role', exp }));
  assertEquals(result.valid, true);
});

Deno.test('precheckJwtExp: past exp → { valid: false, reason: "expired" }', () => {
  const exp = Math.floor(Date.now() / 1000) - 1; // 1s ago
  const result = precheckJwtExp(makeJwt({ exp, role: 'authenticated' }));
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'expired');
});

Deno.test('precheckJwtExp: missing exp claim → { valid: false, reason: "malformed" }', () => {
  // A JWT without `exp` cannot be precheck-validated. Treat as malformed
  // rather than expired — distinguishes "actively rejected" from
  // "rolled-its-own-format".
  const result = precheckJwtExp(makeJwt({ role: 'authenticated', sub: 'u1' }));
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: exp is string (not number) → { valid: false, reason: "malformed" }', () => {
  // RFC 7519 says `exp` is a NumericDate (number). Stringly-typed claims
  // are non-compliant — reject as malformed.
  const result = precheckJwtExp(
    makeJwt({ exp: '9999999999', role: 'authenticated' }),
  );
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: not a JWT (no dots) → { valid: false, reason: "malformed" }', () => {
  const result = precheckJwtExp('not-a-jwt');
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: only two segments → { valid: false, reason: "malformed" }', () => {
  const result = precheckJwtExp('header.payload');
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: payload not valid base64 → { valid: false, reason: "malformed" }', () => {
  const result = precheckJwtExp('header.!!!not-base64!!!.sig');
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: payload decodes to non-JSON → { valid: false, reason: "malformed" }', () => {
  // base64url("not json") -> 'bm90IGpzb24'
  const result = precheckJwtExp('header.bm90IGpzb24.sig');
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: empty string → { valid: false, reason: "malformed" }', () => {
  const result = precheckJwtExp('');
  assertEquals(result.valid, false);
  assertEquals(result.reason, 'malformed');
});

Deno.test('precheckJwtExp: handles base64url chars (- and _) in payload', () => {
  // Pick a payload that, when base64-encoded, contains `-` or `_`.
  // Build a long-ish payload to force URL-safe replacements.
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const jwt = makeJwt({ exp, role: 'service_role', n: '??>>??>>' });
  const result = precheckJwtExp(jwt);
  assertEquals(result.valid, true);
});
