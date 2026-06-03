# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### PR 2 — refresh-retry on 42501 — implementation checklist

Branch: `fix/auth-refresh-retry-on-stale-token`
Per the audit in the WIP.md section
"Auth → Onboarding → Home flow — architectural audit & remediation plan"
(authored on main + cross-referenced for this worktree) → PR 2.

- [x] Add `debugSetBreadcrumbFn` test seam to `SentryReport` (mirrors
      `debugSetCaptureFn`).
- [x] Add `refreshAndRetry<T>({required action, required refresh})` helper to
      `BaseRepository`. ONE retry, bounded. On 42501 / 401 catch → `await
      refresh()` → re-invoke action. Second failure rethrows the ORIGINAL
      error (no double-wrap, no swallow).
- [x] Emit `SentryReport.addBreadcrumb(category: 'auth', message:
      'session_refreshed_inline')` on successful retry.
- [x] Wrap `ProfileRepository.{upsertProfile, updateTrainingFrequency,
      updateWeightUnit, updateLocale}` with the new helper via a
      `_withStaleTokenRetry` shim. `getProfile` (read) NOT wrapped.
- [x] Inline cluster reference comment near `refreshAndRetry` →
      `async-caller-broke-snackbar` (close analog).
- [x] Failing-first tests in
      `test/unit/features/profile/data/profile_repository_test.dart`:
  - First upsert throws 42501, second succeeds → returns row,
    refreshSession called once, upsert called twice, breadcrumb fires.
  - 23505 (non-42501) → no retry, no refresh call, throws immediately.
  - 42501 + refreshSession throws → original 42501 surfaces (no
    double-wrap).
  - 401 AuthException → same retry pattern fires.
  - Two-failure 42501 → original error surfaces, exactly one retry.
  - Happy path → no refresh, no retry, no breadcrumb.
  - Same retry contract for `updateTrainingFrequency`, `updateWeightUnit`,
    `updateLocale`.
  - `getProfile` (read) NOT wrapped — 42501 surfaces immediately.
- [ ] `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] `flutter test` green.
- [ ] PR body includes literal
      `**QA pass pending — final coverage + E2E run after code review.**`.
- [ ] Remove this WIP section after merge.

---
