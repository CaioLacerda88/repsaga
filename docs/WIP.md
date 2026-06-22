# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 T1.4 — offline-sync integration tier — `feature/hardening-t1.4-offline-integration`

Per `docs/PROJECT.md` §2 → Phase 38.9 T1.4. The 4,347-LOC offline-sync stack
(`lib/core/offline/`) is unit-MOCKED only — no test exercises the real local-store↔Supabase
replay. Add a `test/integration/` test for replay-under-partial-failure.

**Approach:** new `test/integration/offline_sync_replay_test.dart`, tagged `integration` so the
existing `integration-test` CI job (`flutter test --tags integration`) auto-runs it — NO ci.yml
change. Uses the `rpg_integration_setup.dart` harness (local Supabase, per-test isolated user
via Admin API). Real Hive box (temp dir) + real `SyncService` drain against real Supabase.

**No-regression mandate (user-standing):** the test pins CURRENT correct replay behavior. If it
reveals a real sync bug (e.g. a mid-batch terminal failure aborts the batch and loses subsequent
valid items), STOP and report it as a finding → tech-lead fixes; do NOT weaken the assertion to
make it pass. Test-only addition; no production code change unless a real bug is found+fixed.

### Checklist
- [x] Read the sync stack (`sync_service.dart`, `offline_queue_service.dart`, `pending_action.dart`,
  `sync_error_classifier.dart`) + an existing integration test for the harness pattern + how Hive
  is initialized for VM tests (`Hive.init(tempDir)` in setUp, mirroring `sync_service_test.dart`).
- [x] Write `offline_sync_replay_test.dart`: 3 pending actions (valid → structurally-broken →
  valid), drained via the REAL `SyncService` (offline→online transition trigger) against REAL
  Supabase + a REAL Hive box. Asserts: (a) both valid workouts persisted server-side, (b) broken
  action flagged `errorCategory.structural` + retryCount incremented (not dropped), (c) queue
  settles at 1 (valids dequeued, broken retained), (d) the post-failure valid action is NOT lost
  behind the failure. Plus a clean-batch control test (queue fully drains).
- [x] Transient-failure case SKIPPED — see note below (can't be made deterministic vs real Supabase
  without a network-fault proxy; would be flaky). Documented rather than added.
- [x] Run locally vs local Supabase → GREEN (2/2). No production-code bug found; partial-failure
  isolation is correct. One classifier observation surfaced (below) — NOT a data-loss bug.
- [x] format + analyze clean; `@Tags(['integration'])` set so the `integration-test` CI job runs it.

### Classifier fix (bundled into T1.4 per user, 2026-06-22)

#### Consumer inventory (blast radius)

`isTerminal` consumers:
- `sync_service.dart:372` (`_drain` catch) — on terminal, currently ONLY skips the backoff
  delay; does NOT stop future drains. The retryCount ceiling (`>= kMaxSyncRetries`, line 316)
  is the real terminal gate. **This is the second half of the bug:** even a corrected
  `isTerminal` wouldn't stop the 6× retries by itself.
- `active_workout_notifier.dart:1705` (save catch) — terminal → rethrow (surface to UI);
  transient → enqueue offline. After fix, a real RLS/FK/cast save error now correctly
  rethrows instead of being silently queued. Conservative-set guarantees no NEW rethrows
  for codes that could succeed on retry.

`httpCode` consumers:
- `active_workout_notifier.dart:1728` — 5xx → `serverErrorQueued = true` (copy variant only).
  PostgREST 5xx surfaces with a numeric-ish code? No — a true gateway 5xx is an HttpException/
  SocketException, not a PostgrestException. For PostgrestException, code is SQLSTATE → httpCode
  null → 5xx branch never trips for Postgrest. This path is effectively dead for Postgrest too,
  BUT it only selects snackbar copy (no data impact) and the AuthException path (statusCode is a
  real HTTP int) still works. **Left as-is — out of scope, no data correctness impact.**
- `sync_error_classifier.dart` internal (isNetworkClass 5xx check).

`isNetworkClass` consumers:
- `connectivity_recovery_provider.dart:64` (`recordFailure`) — arms recovery window only for
  network-class failures. For `app.AuthException`/`supabase.AuthException` the `code`/`statusCode`
  IS a real HTTP int (ErrorMapper copies `statusCode`), so the 401 path WORKS. The 5xx-Postgrest
  branch is dead (same SQLSTATE reason) but a genuine server-down surfaces as Socket/Timeout which
  ARE caught. **Left untouched — fixing it would newly-arm the recovery window on structural
  Postgrest errors (regression risk on ConnectivityRecoveryNotifier). Out of scope.**

#### Design decision: SQLSTATE allow-set, NOT derive-from-category

`SyncErrorMapper.classifyCategory` tags ALL Postgrest/DatabaseException as `structural` — too
coarse for terminal-ness. A `40001` serialization conflict, `40P01` deadlock, or a 5xx wrapped
as `DatabaseException(code:'500')` is `structural`-CATEGORY but MUST stay TRANSIENT (retry
succeeds). Deriving terminal from `structural` would newly-drop those → regression. So:
- `errorCategory` stays the UI-CTA concern (structural → "Dismiss").
- `isTerminal` gets a conservative SQLSTATE/PGRST allow-set = the single source of terminal-ness.
- They are deliberately separate; documented in both files.

Drain-loop second half: on terminal, force `retryCount := kMaxSyncRetries` so the EXISTING
ceiling gate (line 316 skip + `terminalFailureCount`) stops re-drains — no new boolean flag
(honors "structural guarantees over runtime flags"). This is what actually makes "terminal on
first attempt → not retried 6×" true.

#### Codes classified
Terminal (deterministic, identical replay always fails): `22P02` (invalid_text_representation),
`23502/23503/23505/23514` (not_null/FK/unique/check), `42501` (insufficient_privilege/RLS),
`42P01/42703` (undefined_table/column), `deserialization` (ErrorMapper TypeError sentinel — a
malformed payload won't reshape on retry), any `PGRST*` (PostgREST request/schema-cache error).
Transient (keep retrying — UNKNOWN DEFAULTS HERE): `40001` serialization, `40P01` deadlock,
`55P03` lock_not_available, `57014` query_canceled, `53xxx` insufficient_resources, `08xxx`
connection, 5xx, `unknown` sentinel, network/timeout/auth-401, and anything not in the set.

- [x] Root-cause: `SyncErrorClassifier.isTerminal` parsed `error.code` as HTTP int vs
  `{400,403,404,409,422}`, but real `PostgrestException.code` is Postgres SQLSTATE / `PGRST*` →
  never parses → terminal fast-path was DEAD in prod. SECOND defect found: even a corrected
  `isTerminal` wouldn't stop retries — the drain catch only skipped the backoff delay; the
  retry-count ceiling was the only real terminal gate. Decided AGAINST derive-from-category
  (`classifyCategory` tags ALL Postgrest as `structural`, too coarse — would newly-drop 40001/
  40P01/5xx-wrapped). Used a conservative SQLSTATE/PGRST allow-set as the single source of
  terminal-ness; `errorCategory` stays the UI-CTA concern.
- [x] Inventoried `isTerminal` / `httpCode` / `isNetworkClass` consumers (see above). `httpCode`
  5xx-Postgrest branch + `isNetworkClass` 5xx-Postgrest branch left untouched (copy-only / out of
  scope; AuthException 401/HTTP paths still work).
- [x] Fix: SQLSTATE/PGRST allow-set in `isTerminal` (terminal: `22P02`, `23502/23503/23505/23514`,
  `42501`, `42P01/42703`, `deserialization` sentinel, `PGRST*`; everything else incl. `unknown`
  sentinel + `40001/40P01/55P03/57014/53xxx/08xxx`/5xx → transient). Drain catch now pins terminal
  actions to `kMaxSyncRetries` on first failure (reuses the existing ceiling gate — no new flag).
  Corrected the "preserves the HTTP status" doc comment in classifier + the 5xx-copy comment in
  active_workout_notifier.
- [x] Integration test pins CORRECTED behavior: malformed-UUID (22P02) → terminal on first attempt
  → `retryCount == kMaxSyncRetries`, `terminalFailureCount == 1`, retained for Dismiss CTA, valids
  isolated. GREEN vs local Supabase (logs confirm `code=22P02` → DatabaseException → terminal).
- [x] Unit tests rewritten to REAL shapes: classifier suite covers 10 terminal SQLSTATEs/PGRST + 7
  transient SQLSTATEs + sentinels; sync_service terminal test asserts first-attempt ceiling-pin;
  finish-classification + active_workout cancel tests use real SQLSTATEs (22P02/42501/23503).
- [x] No regression: full `flutter test` = 3976 passed / 1 skipped / 0 failed; integration 2/2
  green; `dart format` + `dart analyze --fatal-infos` clean.

### Notes for tech-lead (NOT bugs — observations from building the test)
- **Real structural errors are never `SyncErrorClassifier.isTerminal`.** `isTerminal` does
  `int.tryParse(error.code)` against `{400,403,404,409,422}`, but real PostgREST/Postgres errors
  carry SQLSTATE/PGRST codes in `error.code` (`22P02`, `P0002`, `42501`, `PGRST202`), all of which
  `int.tryParse` → null → classified TRANSIENT. So a permanently-broken queued action is backoff-
  retried up to `kMaxSyncRetries` (6) rather than abandoned on first attempt. It still becomes
  terminal via the retry-count path and `errorCategory.structural` still drives the UI dismiss CTA,
  so there's no data loss — but the `isTerminal` HTTP-code set only matches the MOCK shapes the unit
  tests inject (`PostgrestException(code:'409')`), not production error shapes. Flagging for review;
  the test pins current behavior (structural flag + retained queue), not the mock's terminal path.
- Transient case omitted deliberately: simulating "fails once then succeeds" needs a controllable
  network fault between client and real Supabase; against a healthy local instance every retry would
  succeed identically, giving no signal. The unit suite already covers transient/backoff with mocks.

_T1.1+T1.2 (#367), T1.3 (#369) merged. Tiers 0/2/3 queued in PROJECT.md §2._
