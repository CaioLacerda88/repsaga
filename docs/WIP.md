# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 Tier 1 (Correctness) — `fix/hardening-tier1-correctness`

Per `docs/PROJECT.md` §2 → Phase 38.9. First PR = the two `jsonb-payload-vs-typed-dart`
cluster correctness fixes (T1.1 + T1.2). T1.3 (RLS gate) + T1.4 (offline integration) are
separate follow-up PRs.

### Boundary inventory (error_mapper change — done 2026-06-21)
- Only direct caller of `ErrorMapper.mapException` = `base_repository.dart:77`; every feature
  reaches it transitively. Catch-all fires only for non-Postgrest/Auth/Timeout/AppException =
  raw `TypeError`/`_TypeError`/`CastError` (+ generic Exception/raw values).
- **Verified root cause of the retry storm:** Riverpod 3.2.1 `defaultRetry`
  (`provider_container.dart:838`) does `if (error is Error) return null` — it declines to retry
  Dart `Error`s. `error_mapper` wrapping a `_TypeError` as `NetworkException` (an `Exception`)
  **defeats that guard** → provider retries 200ms×2ⁿ cap 6.4s (matches cluster note exactly).
  No *custom* Riverpod retry is configured (`main.dart:64` bare `ProviderScope`) — the storm is
  the **default** retry, so reclassifying to another `Exception` subtype alone does NOT stop it.
- Type-branching callers (from inventory): `sync_error_classifier.dart` (isNetworkClass/isTerminal),
  `sync_error_mapper.dart` (TypeError + DatabaseException both → `structural`, so sync UI unchanged),
  `onboarding_screen.dart` save-snack, `auth_error_messages.dart`, `async_value_builder.dart:26`
  (userMessage text changes "check connection" → "something went wrong" — correct),
  `connectivity_recovery_provider.dart:62` (no longer armed by deserialization errors — correct).
- `DatabaseException(message, {required code})`; use a non-numeric code (`'deserialization'`) so
  `isTerminal`/`isNetworkClass`/`httpCode` all treat it as non-terminal, non-network (matches
  `rpc_unexpected_type` precedent at `workout_repository.dart:251`).

### Checklist
- [x] **T1.1** Extract `weekly_engagement_provider.dart:147-174` raw `.from('sets')` query into a
  `WeeklyEngagementRepository` (extends `BaseRepository`, routes through `mapException`); parse the
  JSONB rows via `json_helpers.optionalField` instead of throwing `as Map` casts. Provider becomes
  a thin `ref.read(weeklyEngagementRepositoryProvider).getDoneCounts(...)`. Repo unit-tested
  (5 tests: 3 happy-path + 2 malformed-row → typed DatabaseException). Existing pure-Dart provider
  composition tests untouched + green.
- [x] **T1.2a** `error_mapper.dart`: branch `error is TypeError` (catches `_TypeError`/`CastError`)
  → `DatabaseException(<msg>, code: 'deserialization')` BEFORE the NetworkException fallback. Generic
  Exception/String/int → NetworkException unchanged (3 existing tests green). +2 positive tests
  (_TypeError bad-cast + CastError) → DatabaseException(code:'deserialization').
- [x] **T1.2b** `lib/core/data/app_retry.dart` → `appProviderRetry(int, Object)` retries only
  `error is app.TimeoutException || SyncErrorClassifier.isNetworkClass(error)`, else null; delegates
  backoff to `ProviderContainer.defaultRetry`. Wired via
  `const ProviderScope(retry: appProviderRetry, child: App())` in `main.dart`. +9 unit tests
  (Network/timeout/5xx → retry; deserialization/4xx/Validation/Auth/raw-Error → null; delegate-curve
  parity vs defaultRetry).
- [x] format + analyze clean (`--fatal-infos`); 159 targeted tests green (weekly_plan + core
  exceptions + core data). Full pipeline (reviewer → QA) pending — orchestrator gate.

_No other in-flight work._
