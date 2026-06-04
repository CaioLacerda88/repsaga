// Unit tests for delete-user Edge Function.
//
// These tests drive the exported `handleRequest()` HTTP boundary with
// injected admin / user clients — covering the Phase 33 PR 33a
// defense-in-depth additions (findings 028 / 030 / 031):
//
//   * 413 on >4KB Content-Length (finding-028 partial)
//   * 401 on expired JWT BEFORE req.json() (finding-030)
//   * platform allow-list — out-of-list values coerce to 'unknown' in
//     the audit row, not 400 (finding-031: best-effort audit)
//   * app_version regex — non-matching values stripped to null in the
//     audit row (finding-031: best-effort audit)
//   * Valid platform + valid version pass through unchanged
//
// Run with: deno test --allow-net --allow-env supabase/functions/delete-user/
//
// Test fixture pattern follows validate-purchase/test.ts (fake clients +
// behavior-not-wiring assertions).

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { handleRequest } from './index.ts';

const FAKE_USER_ID = '44444444-4444-4444-4444-444444444444';

// --- Supabase client stubs ------------------------------------------------

interface DbCall {
  table: string;
  op: 'insert' | 'select' | 'count' | 'delete' | 'storage_remove';
  payload?: unknown;
}

/** Options for the admin-client stub. */
interface AdminClientOpts {
  /** When set, the avatars storage remove call throws this error
   *  (covers the idempotency / transient-failure path: cluster
   *  data-protection-compliance). */
  storageRemoveError?: Error;
}

/** Admin client stub that captures inserts (for audit row assertions) and
 *  succeeds on user delete. The `calls` array preserves chronological
 *  order — tests that verify the storage delete fires BEFORE
 *  auth.admin.deleteUser rely on that ordering. */
function makeAdminClient(opts: AdminClientOpts = {}): { client: unknown; calls: DbCall[] } {
  const calls: DbCall[] = [];
  const client = {
    from(table: string) {
      return {
        // workout count chain: .select(...).eq(...).not(...) → returns { count }
        select(_cols: string, _opts?: unknown) {
          calls.push({ table, op: 'select' });
          return {
            eq(_k: string, _v: unknown) {
              return {
                not(_k2: string, _op: string, _v2: unknown) {
                  return Promise.resolve({ count: 0, data: null, error: null });
                },
              };
            },
          };
        },
        insert(row: unknown) {
          calls.push({ table, op: 'insert', payload: row });
          return Promise.resolve({ data: row, error: null });
        },
      };
    },
    storage: {
      from(bucket: string) {
        return {
          remove(paths: string[]) {
            calls.push({
              table: `storage:${bucket}`,
              op: 'storage_remove',
              payload: paths,
            });
            if (opts.storageRemoveError) {
              return Promise.reject(opts.storageRemoveError);
            }
            return Promise.resolve({ data: [], error: null });
          },
        };
      },
    },
    auth: {
      admin: {
        deleteUser(_uid: string) {
          calls.push({ table: 'auth.users', op: 'delete' });
          return Promise.resolve({ data: null, error: null });
        },
      },
    },
  };
  return { client, calls };
}

/** User client stub that returns a fixed user on getUser. */
function makeUserClient(opts: { user?: { id: string } | null; error?: { message: string } | null } = {}) {
  return {
    auth: {
      getUser(_jwt: string) {
        return Promise.resolve({
          data: { user: opts.user === undefined ? { id: FAKE_USER_ID, created_at: new Date(Date.now() - 30 * 86400_000).toISOString() } : opts.user },
          error: opts.error ?? null,
        });
      },
    },
  };
}

/** A client stub that throws on any DB op — confirms the rejection
 *  short-circuited before reaching the DB. */
function clientSpyThatMustNotFire(): unknown {
  return {
    from(_table: string) {
      throw new Error('client.from must NOT have fired during rejection');
    },
    auth: {
      getUser(_jwt: string) {
        throw new Error('auth.getUser must NOT have fired during rejection');
      },
      admin: {
        deleteUser(_uid: string) {
          throw new Error('auth.admin.deleteUser must NOT have fired during rejection');
        },
      },
    },
  };
}

// --- Request helpers -------------------------------------------------------

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
  return new Request('https://example.local/delete-user', {
    method: 'POST',
    headers,
    body: opts.body,
  });
}

function encodeJwtPayload(payload: Record<string, unknown>): string {
  const b64url = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  return `${header}.${body}.sig`;
}

function freshJwt(): string {
  return encodeJwtPayload({
    exp: Math.floor(Date.now() / 1000) + 3600,
    role: 'authenticated',
    sub: FAKE_USER_ID,
  });
}

function expiredJwt(): string {
  return encodeJwtPayload({
    exp: Math.floor(Date.now() / 1000) - 1,
    role: 'authenticated',
    sub: FAKE_USER_ID,
  });
}

// --- Tests -----------------------------------------------------------------

Deno.test('delete-user: 413 on >4KB Content-Length', async () => {
  const res = await handleRequest(
    makeRequest({
      authorization: `Bearer ${freshJwt()}`,
      contentLength: '5000',
      body: JSON.stringify({ platform: 'android' }),
    }),
    {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
    },
  );
  assertEquals(res.status, 413);
  const body = await res.json();
  assertStringIncludes(String(body.error), 'Payload too large');
});

Deno.test(
  'delete-user: 401 on expired JWT BEFORE body parse',
  async () => {
    const req = makeRequest({
      authorization: `Bearer ${expiredJwt()}`,
      body: JSON.stringify({ platform: 'android', app_version: '1.0.0' }),
    });
    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
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
  'delete-user: 401 on malformed JWT (no exp claim) BEFORE body parse',
  async () => {
    // Symmetric with the expired-JWT test — pins precheckJwtExp at the
    // HTTP boundary. If a future refactor drops the precheck call from
    // handleRequest, this test catches it. auth.test.ts covers the
    // helper in isolation; this test covers the wiring.
    const noExpJwt = encodeJwtPayload({ role: 'authenticated', sub: 'u1' });
    const req = makeRequest({
      authorization: `Bearer ${noExpJwt}`,
      body: JSON.stringify({ platform: 'android', app_version: '1.0.0' }),
    });
    const res = await handleRequest(req, {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
    });
    assertEquals(res.status, 401);
    assertEquals(
      req.bodyUsed,
      false,
      'request body must NOT be consumed on malformed-JWT short-circuit',
    );
  },
);

Deno.test('delete-user: missing Authorization → 401', async () => {
  const res = await handleRequest(
    makeRequest({ authorization: null }),
    {
      // deno-lint-ignore no-explicit-any
      adminClient: clientSpyThatMustNotFire() as any,
      // deno-lint-ignore no-explicit-any
      userClient: clientSpyThatMustNotFire() as any,
    },
  );
  assertEquals(res.status, 401);
});

Deno.test(
  'delete-user: platform not in allow-list coerces to "unknown" in audit row',
  async () => {
    const { client: adminClient, calls } = makeAdminClient();
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({
          platform: 'symbian',
          app_version: '1.2.3',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );
    assertEquals(res.status, 200);
    const auditInsert = calls.find(
      (c) => c.table === 'account_deletion_events' && c.op === 'insert',
    );
    assert(auditInsert, 'audit row must be inserted');
    const payload = auditInsert!.payload as { platform: unknown; app_version: unknown };
    assertEquals(payload.platform, 'unknown');
    // Valid version still passes through.
    assertEquals(payload.app_version, '1.2.3');
  },
);

Deno.test(
  'delete-user: app_version not matching regex stripped to null',
  async () => {
    const { client: adminClient, calls } = makeAdminClient();
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({
          platform: 'android',
          app_version: 'not-a-semver',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );
    assertEquals(res.status, 200);
    const auditInsert = calls.find(
      (c) => c.table === 'account_deletion_events' && c.op === 'insert',
    );
    assert(auditInsert, 'audit row must be inserted');
    const payload = auditInsert!.payload as { platform: unknown; app_version: unknown };
    assertEquals(payload.platform, 'android');
    assertEquals(payload.app_version, null);
  },
);

Deno.test(
  'delete-user: valid platform/version pass through unchanged',
  async () => {
    const { client: adminClient, calls } = makeAdminClient();
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({
          platform: 'ios',
          app_version: '2.0.0+42',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );
    assertEquals(res.status, 200);
    const auditInsert = calls.find(
      (c) => c.table === 'account_deletion_events' && c.op === 'insert',
    );
    assert(auditInsert);
    const payload = auditInsert!.payload as { platform: unknown; app_version: unknown };
    assertEquals(payload.platform, 'ios');
    assertEquals(payload.app_version, '2.0.0+42');
  },
);

Deno.test(
  'delete-user: all three valid platforms pass through (android/ios/web)',
  async () => {
    for (const plat of ['android', 'ios', 'web'] as const) {
      const { client: adminClient, calls } = makeAdminClient();
      const userClient = makeUserClient();
      const res = await handleRequest(
        makeRequest({
          authorization: `Bearer ${freshJwt()}`,
          body: JSON.stringify({ platform: plat, app_version: '1.0.0' }),
        }),
        {
          // deno-lint-ignore no-explicit-any
          adminClient: adminClient as any,
          // deno-lint-ignore no-explicit-any
          userClient: userClient as any,
        },
      );
      assertEquals(res.status, 200, `platform ${plat} should pass through`);
      const auditInsert = calls.find(
        (c) => c.table === 'account_deletion_events' && c.op === 'insert',
      );
      assert(auditInsert, `audit row for platform ${plat}`);
      const payload = auditInsert!.payload as { platform: unknown };
      assertEquals(payload.platform, plat);
    }
  },
);

Deno.test(
  'delete-user: full round-trip — audit row written AND auth.admin.deleteUser called',
  async () => {
    // Sanity check that the `handleRequest` extraction preserves the
    // production path end-to-end: a valid JWT + valid body must reach
    // BOTH the audit insert AND the user-delete call. Catches regressions
    // where a future refactor silently drops one of the two side effects.
    const { client: adminClient, calls } = makeAdminClient();
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({
          platform: 'android',
          app_version: '1.4.2',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );
    assertEquals(res.status, 200);

    const auditInsert = calls.find(
      (c) => c.table === 'account_deletion_events' && c.op === 'insert',
    );
    assert(auditInsert, 'audit row must be inserted');

    const userDelete = calls.find(
      (c) => c.table === 'auth.users' && c.op === 'delete',
    );
    assert(userDelete, 'auth.admin.deleteUser must be called on happy path');
  },
);

Deno.test(
  'delete-user: omitted platform/app_version stay null (best-effort optional)',
  async () => {
    const { client: adminClient, calls } = makeAdminClient();
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({}),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );
    assertEquals(res.status, 200);
    const auditInsert = calls.find(
      (c) => c.table === 'account_deletion_events' && c.op === 'insert',
    );
    assert(auditInsert);
    const payload = auditInsert!.payload as { platform: unknown; app_version: unknown };
    assertEquals(payload.platform, null);
    assertEquals(payload.app_version, null);
  },
);

// =============================================================================
// Avatar storage removal (cluster: data-protection-compliance)
//
// Supabase Storage objects do NOT cascade on `auth.users` delete — the FK
// cascade chain covers `public.*` only. The avatar binary at
// `avatars/{user_id}/avatar.jpg` (migration 00068 layout) must be
// explicitly removed BEFORE the auth delete so the path's `{user_id}`
// segment still maps to a live identifier.
//
// These tests pin two contracts:
//   1. The storage remove fires on the avatars bucket with the canonical
//      `{user_id}/avatar.jpg` path AND BEFORE auth.admin.deleteUser
//      (ordering matters: after the user is gone, the path is anchored
//      to a tombstoned identifier).
//   2. A storage failure (transient network, "object not found" on a
//      user who never uploaded) does NOT block the account delete —
//      idempotency guard per Important 1.
// =============================================================================

Deno.test(
  'delete-user: removes avatar storage object on canonical path before auth delete',
  async () => {
    const { client: adminClient, calls } = makeAdminClient();
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({
          platform: 'android',
          app_version: '1.0.0',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );
    assertEquals(res.status, 200);

    // (1) Storage remove fires on the avatars bucket with the canonical
    //     `{user_id}/avatar.jpg` path. The path layout is locked by the
    //     RLS policy on migration 00068 — diverging would silently fail
    //     the RLS check in production while the test stub stays green,
    //     so the literal path comparison is the contract.
    const storageRemove = calls.find(
      (c) => c.table === 'storage:avatars' && c.op === 'storage_remove',
    );
    assert(storageRemove, 'avatar storage remove must fire');
    const paths = storageRemove!.payload as string[];
    assertEquals(paths, [`${FAKE_USER_ID}/avatar.jpg`]);

    // (2) Ordering: storage remove must precede auth.admin.deleteUser
    //     in the calls log. Pinning the ordering protects against future
    //     refactors that move the storage block below the auth delete —
    //     once the user is deleted, the path's user_id segment maps to
    //     a tombstoned identifier and the object would orphan.
    const storageIdx = calls.findIndex(
      (c) => c.table === 'storage:avatars' && c.op === 'storage_remove',
    );
    const deleteIdx = calls.findIndex(
      (c) => c.table === 'auth.users' && c.op === 'delete',
    );
    assert(storageIdx >= 0, 'storage remove must appear in calls log');
    assert(deleteIdx >= 0, 'auth.users delete must appear in calls log');
    assert(
      storageIdx < deleteIdx,
      `storage remove (idx ${storageIdx}) must precede auth.users delete (idx ${deleteIdx})`,
    );
  },
);

Deno.test(
  'delete-user: storage removal failure does not block account delete (idempotency)',
  async () => {
    // The avatar might never have been uploaded (user never set one) — in
    // that case `storage.remove` either returns success-with-empty-data
    // (handled by the happy path) OR a transient storage error. Either
    // way, the account delete MUST proceed: the user's explicit erasure
    // request is non-negotiable, and a storage glitch must never gate it.
    const { client: adminClient, calls } = makeAdminClient({
      storageRemoveError: new Error('storage backend transient failure'),
    });
    const userClient = makeUserClient();
    const res = await handleRequest(
      makeRequest({
        authorization: `Bearer ${freshJwt()}`,
        body: JSON.stringify({
          platform: 'android',
          app_version: '1.0.0',
        }),
      }),
      {
        // deno-lint-ignore no-explicit-any
        adminClient: adminClient as any,
        // deno-lint-ignore no-explicit-any
        userClient: userClient as any,
      },
    );

    // Despite the storage failure, the response is 200 and the auth
    // delete fired. This is the contract: an avatar leak is recoverable
    // (sweep orphans later); a refused erasure is not.
    assertEquals(res.status, 200);
    const userDelete = calls.find(
      (c) => c.table === 'auth.users' && c.op === 'delete',
    );
    assert(
      userDelete,
      'auth.admin.deleteUser must fire even when storage remove throws',
    );

    // And the audit row still gets written (best-effort audit, like the
    // existing failure-tolerant paths).
    const auditInsert = calls.find(
      (c) => c.table === 'account_deletion_events' && c.op === 'insert',
    );
    assert(
      auditInsert,
      'audit row must still be written when storage remove throws',
    );
  },
);
