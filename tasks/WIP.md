# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/auth-timeout — guard auth calls against indefinite hangs

**Branch:** `fix/auth-timeout`
**Source:** Architectural review of login path (this session). Not a PLAN.md step — defensive bug fix on top of the auth pipeline.

**Root cause:** `AuthRepository` calls (`_auth.signInWithPassword`, `signUp`, `resetPassword`, `signInWithOAuth`, `resend`, `refreshSession`, `delete-user` Edge Function invoke) have no client-side timeout. Combined with `AsyncValue.guard`'s by-design hang-blindness, a network black hole (captive portal silently dropping packets, dead Wi-Fi handoff) leaves `authNotifierProvider` in `AsyncLoading()` forever — login button spinner with no error, no recovery, no upper bound.

**Fix scope:** apply `.timeout(Duration(seconds: 30))` to every `AuthRepository` network call. `TimeoutException` propagates through `mapException` → `NetworkException` → `AsyncValue.guard` lands in `AsyncError` → `AuthErrorMessages.fromError` matches `'timeout'` → user sees `authErrorTimeout`. Spinner clears.

**Out of scope:** `BaseRepository.mapException` blanket timeout (would risk regressing legitimately-long-running ops in other repos), splash/Hive bootstrap timeouts (mitigated by PR #147 self-heal), OAuth in-browser progress UI.

### Checklist

- [x] tech-lead: add `.timeout(30s)` to each `AuthRepository` method (signInWithEmail, signUpWithEmail, resetPassword, signInWithGoogle, signOut, resendConfirmationEmail, refreshSession, deleteAccount); map `TimeoutException` -> `NetworkException('Request timeout.')` in `ErrorMapper`; reorder `AuthErrorMessages` so the `'timeout'` substring fires before `'network'` (the runtimeType prefix `NetworkException` would otherwise short-circuit it)
- [x] tech-lead: write unit test — simulate a never-completing Future at the GoTrueClient seam (real `AuthRepository` with `@visibleForTesting authTimeout: Duration(milliseconds: 50)`), assert `AuthNotifier.signInWithEmail` ends in `AsyncError(NetworkException)` with message containing `'timeout'`, and that `AuthErrorMessages.fromError` resolves to `authErrorTimeout`
- [x] tech-lead: run `dart format .` + `dart analyze --fatal-infos` clean (full project analyze: 0 issues; full unit/widget suite: 2387 passed)
- [x] orchestrator: CI green — format clean, `dart analyze --fatal-infos` 0 issues, reward-accent + hardcoded-colors guards clean, 2353 tests passing (integration excluded per Makefile), android-debug APK built in 46s
- [x] qa-engineer: PASS — selectors untouched (every `auth-*` semantic identifier preserved); unit test exercises full chain incl. the load-bearing `AuthErrorMessages` reorder; sole `AuthRepository(...)` callsite at `auth_providers.dart:10` is non-`const`, so dropping `const` from the constructor regresses nothing
- [ ] orchestrator: open PR with root-cause + surgical-fix summary
- [ ] reviewer: pass; address every finding before merge
- [ ] squash merge to main, delete branch, remove this WIP section
