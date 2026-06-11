# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## E2E suite sharding (fix CI timeout) — branch `fix/e2e-shard-timeout`

**Problem.** The `E2E Tests` workflow (`e2e.yml`) is a single job, `timeout-minutes: 45`.
Test execution alone is ~33–40 min (343 tests / 4 workers / `retries:1`); fixed
setup ~5.5 min (web build is cached & off the critical path). Since 06-11 ~13:35
*every* run on every branch + main is cancelled at the 45-min cap (runner-speed
variance + retries tipping an at-the-edge suite over the ceiling). Not new tests,
not the build — the test execution outgrew the budget.

**Root-cause evidence.** Last green E2E 06-10 21:32 = 38m32s total (≈6-min headroom).
Timed-out runs: tests started 5.5 min in, ran 40 min, still unfinished at cancel.
`ci` aggregator does NOT depend on `e2e` → e2e is advisory, not a required check
(only `ci` is required by branch protection). Fixing it is about signal + runner
cost, not unblocking a hard gate.

**Decision: shard the test run across 3 isolated-backend jobs (durable fix).**
- Rejected: raise timeout (kicks the can); split build to own job (build isn't
  the bottleneck — proven); smoke-on-PR/full-nightly (weakens the gate philosophy).

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
- [x] Local validation (`playwright --list`): CI collection = 286 tests / 30 files (61 charter tests dropped); local = 347 / 39 (unchanged). Shard split 110/83/93 (1.33× spread, under the 1.4× rebalance threshold).
- [ ] Reviewer reads (CI change → reviewer reads, QA skipped per CLAUDE.md pipeline exceptions).
- [ ] Verify on CI: push branch, confirm 3 shards each finish < 30 min and the suite is green. Capture per-shard durations; if a shard's wall-clock is hot (>~1.4× the fastest), rebalance (bump N to 4 / split workouts.spec.ts).
- [ ] After merge: condense to a one-line note; clear this WIP section.
