// Shared Edge Function defense-in-depth helpers.
//
// Two pure helpers used at the top of every stateful Edge Function handler:
//
//   requireBodySize(req, maxBytes, corsHeaders)
//     Body-size cap (Phase 33 PR 33a, finding-028). Returns a 413 Response
//     when the request's Content-Length exceeds `maxBytes`; returns null
//     when the header is missing OR ≤ max. Missing header is treated as
//     "OK to proceed" — the Supabase Edge Runtime still enforces a
//     platform-level body ceiling upstream (~10MB), and chunked-transfer
//     requests legitimately omit Content-Length. This helper is the
//     APPLICATION-LEVEL cap on top of that platform ceiling, sized per
//     endpoint to the realistic payload (e.g. 4KB for delete-user,
//     32KB for validate-purchase).
//
//   precheckJwtExp(jwt)
//     Cheap local exp-claim check (Phase 33 PR 33a, findings 027 / 030).
//     Decodes the JWT payload and confirms `exp` is a future
//     NumericDate. Does NOT verify the signature — the Supabase gateway
//     already verified it before our handler runs (verify_jwt = on for
//     these functions). The point of this precheck is to short-circuit
//     malformed / expired tokens BEFORE paying the body-parse cost
//     (`req.json()`); callers MUST still do `auth.getUser(jwt)` afterward
//     for the full validity check (revocation, user-still-exists).
//
// Both helpers are framework-agnostic: they take a `Request` and return a
// `Response`-or-null / a discriminated result. They don't import the
// Edge Function `serve` runtime, the Supabase client, or any handler
// state — they're safe to import from any function or test.

export type CorsHeaders = Record<string, string>;

/**
 * Returns a 413 Response when `Content-Length` exceeds `maxBytes`.
 * Returns null when the header is missing, non-numeric, or ≤ maxBytes —
 * the caller should proceed with `req.json()` / `req.text()`.
 *
 * Body of the 413: `{ error: 'Payload too large', maxBytes }` as JSON.
 * The caller's CORS headers are merged into the response so the browser
 * (or Supabase dashboard) doesn't reject the 413 itself on a CORS check.
 */
export function requireBodySize(
  req: Request,
  maxBytes: number,
  corsHeaders: CorsHeaders,
): Response | null {
  const raw = req.headers.get('Content-Length');
  if (raw === null) return null;
  // parseInt with a non-numeric string returns NaN; `NaN > maxBytes` is
  // false, so we fall through to null. This intentionally treats a
  // malformed Content-Length the same as a missing one — the upstream
  // platform cap still applies. Pinned by an explicit test in auth.test.ts.
  const length = parseInt(raw, 10);
  if (!Number.isFinite(length) || length <= maxBytes) return null;
  return new Response(
    JSON.stringify({ error: 'Payload too large', maxBytes }),
    {
      status: 413,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

export interface JwtPrecheckResult {
  valid: boolean;
  reason?: 'malformed' | 'expired';
}

/**
 * Cheap local check that the JWT's `exp` claim is a future NumericDate.
 *
 * Does NOT verify the signature. The Supabase Edge Function gateway has
 * already cryptographically verified the JWT signature by the time our
 * handler runs (verify_jwt = on); this helper exists purely to short-
 * circuit malformed / expired tokens BEFORE the handler pays the body
 * parse cost. Callers must still run `auth.getUser(jwt)` (or the
 * equivalent service-role role-claim check) to enforce
 * revocation + user-still-exists.
 *
 * Returns:
 *   { valid: true }                          — exp is in the future
 *   { valid: false, reason: 'expired' }      — exp is a number ≤ now
 *   { valid: false, reason: 'malformed' }    — any other failure
 *                                              (no exp, non-number exp,
 *                                               unparseable payload,
 *                                               not a 3-segment JWT)
 */
export function precheckJwtExp(jwt: string): JwtPrecheckResult {
  if (typeof jwt !== 'string' || jwt.length === 0) {
    return { valid: false, reason: 'malformed' };
  }
  const parts = jwt.split('.');
  // RFC 7519 JWS Compact Serialization: header.payload.signature. We
  // require all three segments — a 2-segment string is not a JWT.
  if (parts.length !== 3) return { valid: false, reason: 'malformed' };
  const payloadB64 = parts[1];
  if (!payloadB64) return { valid: false, reason: 'malformed' };

  let payload: { exp?: unknown };
  try {
    // JWT uses base64url without padding. atob expects standard base64
    // with correct padding — translate `-/_` back and re-pad. Mirrors
    // the decoder in `isServiceRoleJwt` (validate-purchase, vitality-nightly)
    // so behavior is consistent across all Edge Function JWT touchpoints.
    const b64 = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
    const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
    payload = JSON.parse(atob(b64 + pad));
  } catch {
    return { valid: false, reason: 'malformed' };
  }

  // RFC 7519 §4.1.4 defines `exp` as a NumericDate. A string-typed exp
  // is non-compliant — reject as malformed (NOT expired) so the caller's
  // log surface distinguishes "we have an exp but it's stale" from "this
  // isn't a real JWT".
  if (typeof payload.exp !== 'number') {
    return { valid: false, reason: 'malformed' };
  }
  // NumericDate is seconds since epoch — multiply by 1000 to compare
  // against Date.now() (millis since epoch).
  if (payload.exp * 1000 <= Date.now()) {
    return { valid: false, reason: 'expired' };
  }
  return { valid: true };
}
