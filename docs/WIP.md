# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Round 4.5 — locale-routed email templates

Branch: `feat/auth-locale-routed-email-templates`

Replace the bilingual single-template approach with locale-routed Go-template
conditionals so Brazilian users see only Portuguese, English users see only
English. Closes the locale-routing question flagged in Round 4 README.

**Dart wiring (signup → user_metadata.locale):**

- [x] `lib/features/auth/data/auth_repository.dart` — add optional `String? locale` to `signUpWithEmail`; forward as `data: {'locale': locale}` only when non-null. Keep `.timeout(_authTimeout)`.
- [x] `lib/features/auth/providers/notifiers/auth_notifier.dart` — read `ref.read(localeProvider).languageCode`, forward to repo. Inline comment explains WHY + flags Google OAuth edge case.

**Email templates (HTML + plain-text, four flows):**

- [x] `docs/auth-email-templates/confirm-signup.html` + `.txt`
- [x] `docs/auth-email-templates/reset-password.html` + `.txt`
- [x] `docs/auth-email-templates/magic-link.html` + `.txt`
- [x] `docs/auth-email-templates/change-email.html` + `.txt`

Each renders ONE language via `{{ if eq .Data.locale "pt" }} … {{ else }} … {{ end }}`.
No hairline divider, no `ENGLISH` / `PORTUGUÊS` eyebrow labels.

**README:**

- [x] `docs/auth-email-templates/README.md` — conditional subject lines table, updated verification checklist (en default + pt + explicit en), new "Known edge case" section for Google OAuth missing `user_metadata.locale`. Drop bilingual rationale.

**Tests (TDD — failing first, then production):**

- [x] `test/unit/features/auth/data/auth_repository_test.dart` — three cases pinning `data: {'locale': 'pt'}` / `'en'` / omitted-data when no locale param.
- [x] `test/unit/features/auth/providers/notifiers/auth_notifier_test.dart` — `localeProvider` override → repo invoked with `locale: 'pt'` exactly.
- [x] `test/widget/features/auth/ui/duplicate_email_snackbar_test.dart` — added `locale:` matcher + `localeProvider` Hive-free stub so existing widget test continues to pass after the signature change.

**Verification:**

- [x] `dart format .` clean, `dart analyze --fatal-infos` clean, 3370 unit + widget tests pass (1 skipped, 0 failures). Integration tests in `test/integration/` were already failing on `main` for environment reasons (no live local Supabase) — not regressions.
- [ ] Open PR with `**QA pass pending — final coverage + E2E run after code review.**`
