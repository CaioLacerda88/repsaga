# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

---

## Plan: investigate exercises.spec.ts:372 flake + cold-launch orphan drain

**Branch:** `fix/exercises-debounce-flake-investigation`

User direction: "Do items 1 and 2. Be precise about them, check if we're not
breaking anything around it. And for item 2, check if the flakiness doesn't
hint at a hidden bug or something."

### Order of execution

1. **Item 2 first** (debounce flake investigation). The flakiness could
   reveal a real production race that informs Item 1's approach. Apply
   `superpowers:systematic-debugging` — root cause before fix.
2. **Item 1 second** (cold-launch orphan drain). Once item 2 is settled,
   read the current `SyncService` startup logic, understand what's actually
   broken, propose the surgical fix, verify no regression.

Each item ships as its own PR for independent review/revert.

### Item 2 — `exercises.spec.ts:372` debounce flake

**Symptom (from FLAKY_TESTS.md and recent CI runs):** the test "should
filter exercises by name via search input" intermittently fails on the
first attempt and passes on retry. Currently classified as "search debounce
flake."

**Investigation steps:**

- [ ] Read the test code at `test/e2e/specs/exercises.spec.ts:372`
- [ ] Read the search-input widget + the debounce implementation in
  `lib/features/exercises/`
- [ ] Find the most recent failure artifact (page snapshot, error context)
  to see exactly where the test was when it timed out
- [ ] Look for: race conditions between debounce timer + provider rebuild
  + Playwright polling cadence; any timing assumption in the test that
  could break under CI CPU pressure; any production debounce bug that
  manifests as a brief "wrong list shown" window
- [ ] Categorise the root cause: pure test infra (fix in test only) vs
  real production race (fix in production code)
- [ ] If production: build minimal repro, fix at source, add unit/widget
  test, verify e2e is green
- [ ] If pure test: tighten the wait condition or replace polling with a
  durable signal

### Item 1 — cold-launch orphan drain

**Symptom:** `SyncService` doesn't auto-drain pre-existing queue items
when the app boots already-online. The optimistic-default `true` of
`onlineStatusProvider` causes the drain to skip on cold launch when
queue items exist from a previous offline session.

**Investigation steps:**

- [ ] Read `SyncService` startup logic + `onlineStatusProvider`
- [ ] Confirm the bug: trace cold-launch flow through the relevant
  `AsyncValue` lifecycle
- [ ] Map the surgical fix: gate the drain on the first real
  `AsyncData` emission (not the optimistic default)
- [ ] Verify the fix doesn't break: (a) the existing online→offline
  transition path, (b) the offline-on-launch path (where drain
  should NOT fire), (c) any test that asserts the current behavior
- [ ] Add a unit/integration test reproducing the cold-launch case
- [ ] Reviewer pass before push
