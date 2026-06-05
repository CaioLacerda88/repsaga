# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Legal PR 3 — Portability JSON export

Branch: `feat/legal-pr3-portability-json-export`

Closes the hedge declared in PR 1 (#305) Privacy Policy §6 Portability row.
LGPD Art. 18 V / GDPR Art. 20 portability mechanism delivered in-app via
Profile → Manage Data → **Export my data**. Generates a JSON file of every
user-owned table the user has rows in and hands it to the native share sheet
via `share_plus` (same integration shape as Phase 30b post-session share
card).

**Cluster references:** `data-protection-compliance` (this PR IS the
portability mechanism the policy promises); `persist-eats-duration` on the
success/error snackbar; `permission-handler-web-silent-failure` does NOT
apply directly (share_plus on web uses `navigator.share`/download fallback,
no permission_handler dependency).

**Out of scope:** subscription / payment data (Launch Phase paywall ships
those tables — no rows for any user yet), `account_deletion_events`
(anonymized aggregate, not tied to user_id), auth.users password hash + JWT
(secrets, never exported — only id+email exposed at top of JSON).

**JSON shape (top-level keys):**
- `exportedAt`, `schemaVersion: 1`, `user{id,email}`, `profile`
- `workouts[]` — denormalized: each workout embeds its `workoutExercises[]`
  which embeds its `sets[]`
- `personalRecords[]`, `weeklyPlans[]`, `xpEvents[]`,
  `bodyPartProgress[]`, `exercisePeakLoads[]`,
  `exercisePeakLoadsByRepRange[]`, `earnedTitles[]`,
  `backfillProgress[]` (0-or-1 row), `vitalityRuns[]`, `analyticsEvents[]`
- `exercises[]` — only slugs referenced by the user's data
  (`{slug, userCreated}`), NOT the full default library

**Implementation checklist:**

- [x] `lib/core/exceptions/app_exception.dart` — add `ExportException`
      subtype (sealed AppException). Holds the original cause + stage label
      so the snackbar can show a stable user-safe message while the dev
      log keeps the underlying error.
- [x] `lib/features/profile/data/data_export_service.dart` — new
      `DataExportService` with `Future<String> buildJsonExport(String
      userId)`. Constructor takes `SupabaseClient` + `Clock` seam (for
      `exportedAt` determinism). Queries each user-owned table directly,
      assembles a `Map<String, dynamic>`, returns
      `JsonEncoder.withIndent('  ').convert(map)`. Per-stage try/catch
      wraps each table fetch and rethrows as `ExportException(stage:
      'workouts', cause: ...)` so partial failures surface where they
      happened.
- [x] `lib/features/profile/providers/data_export_providers.dart` — new
      `dataExportServiceProvider` (plain `Provider<DataExportService>`)
      + `exportJobProvider`
      (`NotifierProvider<ExportJobController, AsyncValue<ExportResult>>`).
      `ExportResult` carries the generated `XFile` path + bytes so the
      caller can hand it to `Share.shareXFiles`. The controller manages
      idle → loading → data/error transitions.
- [x] `lib/features/profile/ui/manage_data_screen.dart` — new "YOUR DATA"
      section above "WORKOUT HISTORY"; "Export my data" tile +
      `_showExportSheet` method that runs the export through the provider
      and dispatches to share_plus. Loading dialog mirrors the
      delete-account pattern (PopScope + CircularProgressIndicator). Error
      snackbar uses `ExportException.userMessage`; success snackbar uses
      a new `dataExportSuccess` ARB key. `persist: false` on the snackbar
      builder where applicable.
- [x] `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb` — new keys:
      `yourDataSection`, `exportMyData`, `exportMyDataSubtitle`,
      `dataExportSuccess`, `dataExportFailed{message}`,
      `dataExportPreparing`. en+pt parity.
- [x] `assets/legal/privacy_policy.md` + `docs/privacy_policy.md` —
      update §6 Portability row only: replace the email-15-business-days
      hedge with the in-app path. Access row stays email-based (intentional
      asymmetry — Access = human-readable summary; Portability = machine-
      readable export).
- [x] `test/unit/features/profile/data/data_export_service_test.dart` —
      mocktail-driven `SupabaseClient` builder mock. Cases:
      - empty user → valid skeleton with `schemaVersion: 1`, empty arrays
        for every collection, `user.id` populated
      - rich user → populated collections; `exercises[]` contains ONLY
        slugs that appear in the user's workouts (not full default library)
      - network error mid-export → propagates as `ExportException` with
        `stage` field populated
      - exported JSON is valid (`jsonDecode` round-trip succeeds)
      - pretty-printed (contains 2-space indentation)
- [x] `test/widget/features/profile/ui/manage_data_screen_test.dart` —
      extend existing harness with `MockDataExportService`. Cases:
      - "Your data" section + "Export my data" tile rendered
      - tap → loading spinner shown → share sink invoked with XFile whose
        filename matches `repsaga_export_YYYY-MM-DD.json`
      - on success: success snackbar rendered
      - on `ExportException`: error snackbar with safe user message
        (no raw exception body)
- [x] Run `make gen` (l10n regen — app_localizations_en.dart / _pt.dart
      regenerate from the ARB additions).

**Verification:**

- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean — 0 issues
- [x] New unit tests green (7/7 in
      `test/unit/features/profile/data/data_export_service_test.dart`)
- [x] New widget tests green (5 new export tests in the existing
      `manage_data_screen_test.dart` group; full file: 29/29)
- [x] Full `flutter test` baseline: 3465 passed, 1 skipped, 25 failed
      — identical to the PR #307 baseline (the 25 failures are all in
      `test/integration/*` requiring a live local Supabase). Not
      regressions.
- [ ] PR body includes
      `**QA pass pending — final coverage + E2E run after code review.**`

---

### Fix — manage-data compliance: avatar storage leak + exercises FK + reset-all active workouts

Branch: `fix/manage-data-avatar-storage-leak-and-cascade`

Read-only compliance audit on the delete-account / reset-all flow surfaced 2
Blockers + 2 Important findings. All four land in this PR per
`feedback_no_deferring_review_findings`.

**Findings (audit excerpt):**

1. **Blocker — `exercises.user_id` FK lacks `ON DELETE CASCADE`**
   (`supabase/migrations/00001_initial_schema.sql:63`). Legacy user-created
   rows from before the Phase 32h retirement (PR #281) still depend on this
   FK; account-delete would orphan or block them.
2. **Blocker — avatar binary leaks on account delete**
   (`supabase/functions/delete-user/index.ts`). FK cascade covers
   `public.*`; Supabase Storage objects do NOT cascade off
   `auth.users` deletion. `avatars/{user_id}/avatar.jpg` survives — LGPD/GDPR
   miss.
3. **Important — idempotency guard on storage removal.** The storage delete
   must tolerate "object not found" (re-runs, users who never uploaded an
   avatar) without aborting the account delete.
4. **Important — "Reset all" leaves active workouts behind**
   (`lib/features/profile/providers/manage_data_providers.dart:30`).
   `workoutRepo.clearHistory(userId)` filters `is_active = false AND
   finished_at IS NOT NULL`, so an in-progress / draft workout survives the
   reset. The label says "ALL account data" — implementation must match.

**Cluster references:** `data-protection-compliance` (named in MEMORY
index `feedback_data_protection_compliance.md`; this PR also lands the row
in PROJECT.md §0 Cluster Ledger — the audit lockdown migration #69 cited
it but never indexed the handle).

**Implementation checklist:**

- [x] `supabase/migrations/00074_exercises_user_id_cascade.sql` — drop the
      existing auto-named FK on `exercises.user_id`, re-add as
      `exercises_user_id_fkey` with `ON DELETE CASCADE`. Pattern mirrors
      `00047_personal_records_exercise_id_on_delete.sql` (information_schema
      lookup + canonical-name existence guard for idempotency).
- [x] `supabase/functions/delete-user/index.ts` — add storage removal block
      BEFORE `auth.admin.deleteUser` fires. Idempotent try/catch swallows
      "not found" + transient storage failures so the account delete is
      never blocked.
- [x] `lib/features/workouts/data/workout_repository.dart` —
      `clearHistory(userId, {bool includeActive = false})`. Default keeps
      the existing finished-only behavior; `true` drops the `is_active` +
      `finished_at` filters so the wipe is total.
- [x] `lib/features/profile/providers/manage_data_providers.dart` —
      `resetAllAccountData` passes `includeActive: true` to capture
      draft/in-progress workouts.
- [x] `supabase/functions/delete-user/index.test.ts` — add storage removal
      coverage: (a) happy path calls `storage.from('avatars').remove([uid+'/avatar.jpg'])`
      BEFORE `auth.admin.deleteUser`, (b) storage error doesn't block the
      delete.
- [x] `test/unit/features/workouts/data/workout_clear_history_test.dart` —
      extend with `includeActive: true` case asserting the `is_active` +
      `finished_at` filters are NOT applied + regression guard pinning
      the default still preserves the finished-only contract.
- [x] `test/widget/features/profile/ui/manage_data_screen_test.dart` —
      pin `resetAllAccountData` forwards `includeActive: true` to the
      repo via a literal-true `verify` matcher (catches accidental flips
      to `false` or the named arg being dropped).
- [x] PROJECT.md §0 Cluster Ledger — new row
      `data-protection-compliance` indexed.

**Verification:**

- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean (0 issues — `.env` warning is a
      pre-existing local-env artifact; CI runs against a real `.env`)
- [x] Affected unit/widget tests green: 29/29 in
      `workout_clear_history_test.dart` + `manage_data_screen_test.dart`
- [x] Full suite: 3447 tests, 1 skipped, 25 failures — all 25 in
      `test/integration/*` requiring a live local Supabase. **Identical
      baseline to `main` HEAD c9b95ebf** (mirrors PR A2's documented
      baseline). Not regressions.
- [x] Android debug APK built clean via
      `flutter build apk --debug --no-shrink`
- [x] PR body includes
      `**QA pass pending — final coverage + E2E run after code review.**`

**Post-merge:**

- Apply migration 00074 to hosted Supabase via `npx supabase db push`. The
  Postgres CLI runs each migration in its own transaction by default;
  cluster `postgres-alter-type-transaction` does NOT apply (this is FK
  constraint mutation, not enum mutation).
- Deploy Edge Function delta via `supabase functions deploy delete-user`.

