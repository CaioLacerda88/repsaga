# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Fix E2E: grant regression + sharding — branch `fix/e2e-shard-timeout`

**THE REAL ROOT CAUSE (the "timeout" was a symptom).** Since ~06-11 *every* E2E
run (single-job AND sharded, on every branch + main) was cancelled at the cap.
Sharding surfaced the truth: the app boots, authenticates, then its first query
`GET /rest/v1/profiles?id=eq.<uid>` returns **403 / `42501 permission denied for
table profiles`**. The splash waits on that profile load to route → app hangs on
the REPSAGA splash → `nav-home` never renders → EVERY test fails → failures ×
`retries:1` × 15–20s timeouts blow past the 45-min cap → cancellation, which
masked the real cause as a "timeout". (Proof it predates sharding: the PR #329
single-job run had 540 identical `nav-home` failure lines.)

**Why the 403.** `supabase/setup-cli@v1` floats on `version: latest`; a CLI/image
released ~06-11 stopped applying the implicit default
`GRANT ... ON public tables TO authenticated`. RepSaga's migrations never granted
table privileges explicitly (only a single view grant in 00025) — they relied on
that implicit default. The 06-10 green run and production both still have it.

**Decision.** Fix the root cause (make grants explicit) + keep the sharding (it
made the suite *reportable* and ~halves wall-clock once green). `ci` does NOT
depend on `e2e` (only `ci` is a required check), so e2e was advisory throughout.

**Security audit (DONE, all tables).** 24 user-data tables, all RLS-enabled
(0 disabled), all owner-scoped (`auth.uid()`); both views `security_invoker=true`;
avatars bucket private. No critical holes. One low-sev gap (I-1): `record_set_xp`
/ `record_session_xp_batch` are SECURITY DEFINER + granted to `authenticated` but
don't assert caller ownership — client never calls them directly (zero `.rpc()`
sites), production path is `save_workout` (DEFINER, guarded) → fixed by REVOKE.

### Migration `00076_grant_authenticated_table_privileges.sql`
- Explicit, per-table, least-privilege grants to `authenticated` only (no `anon`;
  service-only tables `account_deletion_events`/`migration_checkpoints` ungranted).
  Additive → no-op on prod (already has the implicit defaults), safe to `db push`.
- REVOKE EXECUTE on the two unguarded XP DEFINER funcs from `authenticated` (I-1).
- Embedded ROLLBACK block = the backout plan (ship the inverse as a new migration).

**Shard-safety audit (DONE — read-only, all 39 specs).** Every CI-running spec is
either fully `mode:'serial'` (bucket 1) or per-test-independent with `beforeEach`
re-login/reseed (bucket 2). The only order-dependent files (5 charter exploratory
specs using `beforeAll` + shared mutable `page`) are env-gated OFF in CI — they
never produce runnable tests, so `--shard` can never split them. **Verdict: the
suite is safe for naive `--shard=k/n`.** (Latent caveat: if anyone ever runs the
charters in CI with their env flag, wrap them in `serial` first.)

**The one invariant (non-negotiable).** Each shard MUST run its own `supabase start`
+ its own full `global-setup` against its own isolated backend. NEVER share a
Supabase across shard jobs — that is the only thing that would reintroduce the
historical seeding / shared-login races (the per-role × per-worker isolation in
`worker-users.ts` stays unchanged; sharding composes on top of it).

### Checklist

- [x] `.github/workflows/e2e.yml`: convert the single `e2e` job → `strategy.matrix.shard: [1,2,3]`, `fail-fast: false`, `timeout-minutes: 30`. Each matrix job keeps ALL existing setup steps (own `supabase start`, env write, wait-for-supabase, pub get, build_runner, cached web build, serve, npm ci, playwright install).
- [x] Test step: `npx playwright test --shard=${{ matrix.shard }}/3 --reporter=line`.
- [x] Failure artifact: `name: playwright-report-${{ matrix.shard }}` (keep `if: failure()`).
- [x] Exclude the env-gated exploratory charter specs from CI collection (Playwright `testIgnore` under `process.env.CI`) so skipped tests don't imbalance the 3-way split. Verified all 9 files: charter-a-exploratory (EXPL_CHARTER_A), charter-a-refined (EXPL_CHARTER_A_REFINED), charter-a-verify-weight (VERIFY_WEIGHT), charter-a-weight-test (EXPL_WEIGHT_DIALOG), charter-b-exploratory (EXPL_CHARTER_B), charter-b-followup (EXPL_CHARTER_B_FU), charter-c-exploratory (EXPL_CHARTER_C), charter-d-exploratory (EXPL_CHARTER_D), exploratory.spec.ts (EXPL_DRIVER). None of these env vars are set in e2e.yml.
- [x] Optional: `e2e-summary` job `needs: [e2e]`, `if: always()`, fails unless `needs.e2e.result == 'success'` — gives one clean status line (e2e is not a required check, so this is cosmetic).
- [x] `WORKERS_COUNT` stays 4 (per shard). `playwright.config.ts` reporter/workers unchanged.
- [x] Local validation (`playwright --list`): CI collection = 286 tests / 30 files; shard split 110/83/93.
- [x] Reviewer (sharding): 1 Important fixed (hard-fail Supabase wait loops); 1 Blocker rejected (concurrency+matrix is canonical).
- [x] Security audit (all tables) + grants migration 00076 (service_role + authenticated) + I-1 revoke.
- [x] **CI GREEN** (run 27381520684): all 3 shards pass — 283 passed, 0 seeding errors, 2 flaky-but-passed. Wall-clock 15 / 16 / 21.5 min (was: timing out at 45). Shard 3 (RPG/saga/animation-heavy serial specs) is the long pole at 21.5 min — under cap with margin; rebalance is a future nice-to-have, not needed.
- [ ] Final reviewer pass on migration 00076 for production-safety (ships via `db push`).
- [ ] Merge PR #330.
- [ ] After merge: `supabase db push` migration 00076 to hosted Supabase (verified additive/no-op). Then condense to a one-line note + clear this WIP section. Write `cluster_*` memory (version:latest tool drift dropped implicit grants → mass E2E failure masked as timeout).
