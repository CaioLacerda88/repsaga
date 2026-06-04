# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

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

