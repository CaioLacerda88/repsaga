# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/workouts-pr-cache-bootstrap — Family 1A from active-workout exploratory pass (BLOCKER)

**Branch:** `fix/workouts-pr-cache-bootstrap`
**Source:** `tasks/active-workout-implementation-plan.md` Family 1 + master findings AW-EX-D-US1-01 (BLOCKER), AW-EX-E-US1-03 (cache-wipe amplifier).

**Root cause:** the PR cache (`HiveService.prCache` box) is **never seeded from the DB at session start**. It only fills lazily on the first `prRepo.getRecordsForExercises()` call inside `finishWorkout()`. So on a fresh session, the in-memory PR-detection comparison runs against an empty cache → first set of any exercise wins → user sees fake "NEW PR" celebrations for weights/reps clearly below their baseline. Charter D reproduced this directly: log Bench Press 50 kg×8, then in a second session log 30 kg×5 → three "NEW PR" badges appear despite all values being lower than the baseline.

Compounded by `sync_service._reconcilePrCache` at `sync_service.dart:451` which calls `clearBox(prCache)` after a successful drain, re-arming the bug for the next offline window (AW-EX-E-US1-03).

**Fix scope (PR1A only):**
1. Add a new `prCacheBootstrapProvider` (FutureProvider or AsyncNotifier) that on first read seeds `HiveService.prCache` from `prRepo.getRecordsForExercises()` against ALL of the user's exercises with PR history. Subsequent reads are a no-op.
2. Wire eager warmup into `_ShellScaffold` (in `lib/core/router/app_router.dart`) next to the existing `ref.listen(rpgProgressProvider, ...)` pattern around L383. The provider runs in the background; the UI doesn't block on it.
3. Replace `sync_service._reconcilePrCache: clearBox(prCache)` (sync_service.dart:451) with `ref.invalidate(prCacheBootstrapProvider)` so the cache RE-SEEDS from DB after drain instead of being wiped to empty.
4. One-shot Hive migration: on first launch after this fix lands, wipe existing `prCache` entries (they were polluted by the bug). Mechanism: a `pr_cache_v2_migrated` flag in `HiveService.userPrefs` — if absent, clear `prCache` then set the flag.
5. Tests: unit tests for the bootstrap provider (seed-on-first-read, no-op on subsequent reads, invalidate triggers re-seed) + migration test (cache cleared exactly once, flag persists).

**Out of scope (deferred to PR1B):** error classification at the `finishWorkout` catch site, save timeout bump from 2s to 10s, loading overlay with cancel button. Those build on top of PR1A's discrimination model.

### Checklist

- [x] tech-lead: read implementation plan Family 1 section + Charter D / Charter E findings to ground the diagnosis
- [x] tech-lead: TDD — write failing unit tests first (bootstrap provider seed/no-op/re-seed behavior, Hive migration contract)
- [x] tech-lead: implement `prCacheBootstrapProvider` at `lib/features/personal_records/providers/pr_cache_bootstrap_provider.dart`; fetches via `prRepo.getRecordsForUser` and writes per-exercise cache entries (`exercises:<id>` shape); subsequent reads no-op via Riverpod future caching
- [x] tech-lead: wire eager warmup in `_ShellScaffold` next to `rpgProgressProvider` listener (`lib/core/router/app_router.dart`)
- [x] tech-lead: replace `clearBox(prCache)` in `sync_service._reconcilePrCache` with `ref.invalidate(prCacheBootstrapProvider)`
- [x] tech-lead: add Hive migration in the bootstrap provider's first-call path keyed on `pr_cache_v2_migrated` flag; one-shot clear of stale entries
- [x] tech-lead: extend `PRRepository.getRecordsForExercises` with per-exercise cache fallback so offline subset reads work after bootstrap (was missing — multi-id key shape would otherwise never hit cache for arbitrary subsets)
- [x] tech-lead: `dart format` + `dart analyze --fatal-infos` clean; full unit/widget suite green (2375 tests)
- [x] orchestrator: CI green — format clean, `dart analyze --fatal-infos` 0 issues, reward-accent + hardcoded-colors guards clean, 2375 tests passing (+5 net new on the bootstrap path), android-debug APK built in 34.8s
- [x] qa-engineer: PASS — selectors untouched (zero E2E impact); 8+3+5 test coverage validated against the new contracts; auth-aware no-op pinned via verifyNever; no regression in existing PR-detection tests; sole `lib/` files touched are the 4 expected
- [x] orchestrator: PR #177 opened — https://github.com/CaioLacerda88/repsaga/pull/177
- [x] reviewer: pass; address every finding before merge
  - Critical 1: removed `_cache.clearBox(HiveService.prCache)` from `PRRepository.upsertRecords` — the post-drain reconcile path's `ref.invalidate(prCacheBootstrapProvider)` is now the single source of truth for cache freshness; per-exercise entries remain serviceable until the rebuild atomically overwrites them, closing the empty-cache window that re-armed AW-EX-E-US1-03.
  - Critical 2: bootstrap is now auth-reactive — derives userId from `authStateProvider` (via `await ref.watch(authStateProvider.future)`) instead of the synchronous, non-reactive `currentUserIdProvider`. Sign-out → sign-in transitions naturally re-run the provider with the new user. New unit test `re-fetches against the new user when authStateProvider emits a different signed-in user` pins the contract.
  - Warning 1: deleted the orphan duplicate test at `sync_service_test.dart:1775-1828` — coverage subsumed by the group test at L1306.
  - Warning 2: removed the duplicate `_seedPerExerciseEntries` helper from `pr_cache_bootstrap_provider.dart`; the bootstrap now calls `repo.seedExerciseCacheEntries(records)` through the repo's public API. The "testability" justification was unnecessary — mocking `seedExerciseCacheEntries` to delegate to a real Hive write produces the same observable contract.
  - Warning 3: migration comment honestly scopes "leftover stale entries" — the seed write only overwrites entries for exercises still in the user's PR list; entries for exercises no longer in the list (soft-deleted, server-rolled-back) remain until naturally evicted.
  - Suggestion 1: addressed by Critical 2's new test.
  - Suggestion 2: addressed inline — the bootstrap body now opens with a `// Note:` block explaining the migration → seed order and the auth source choice.
- [ ] squash merge to main, delete branch, post-merge cleanup PR (mark Family 1A resolved in master findings)
