# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### PR B — typed error UX on onboarding form

Branch: `fix/auth-onboarding-typed-error-snackbars`

Replace the generic `failedToSaveProfile` snack with one bar per `AppException`
subtype reaching the onboarding catch block so users see "you're offline" vs.
"session expired (sign in)" vs. "validation hint" instead of the same opaque
copy for every failure. Continues the May 2026 auth-remediation audit after
#298 / #299 / #300.

**Discovery (AppException hierarchy):**

- [x] `lib/core/exceptions/app_exception.dart` — `AuthException`, `DatabaseException`, `NetworkException`, `TimeoutException` (`dart:async` collision documented), `ValidationException(message, field)`. No new types introduced.
- [x] `lib/core/exceptions/error_mapper.dart` — confirmed unmapped errors fall through to `NetworkException`; in-flight `AppException` subtypes pass through unchanged.

**l10n (en + pt parity):**

- [x] `lib/l10n/app_en.arb` + `app_pt.arb` — five new keys (`onboardingErrorOffline`, `onboardingErrorSessionExpired`, `onboardingErrorSessionExpiredCta`, `onboardingErrorValidationGeneric`, `onboardingErrorValidationField(field, message)`). `flutter gen-l10n` ran; generated `app_localizations*.dart` regenerated cleanly.

**UI dispatch:**

- [x] `lib/features/auth/ui/onboarding_screen.dart` — `_showSaveErrorSnack(Object error)` switch on AppException subtypes:
  - `NetworkException` / `TimeoutException` → offline copy, no CTA.
  - `AuthException` → session-expired copy + `SnackBarAction` "Sign in" → `context.go('/login')` (FlutterError swallowed for routerless test contexts). `persist: false` set explicitly per `persist-eats-duration` cluster.
  - `ValidationException` → field-prefixed copy when `field == 'displayName'` resolves to the localized label, otherwise generic catch-all (unknown field tokens never leak to UI).
  - Fall-through → existing `failedToSaveProfile` safety-net copy.

**Tests (behavior-not-wiring — assert rendered snack text via `find.text`):**

- [x] `test/widget/features/auth/ui/onboarding_save_error_test.dart` — 6 cases: NetworkException, TimeoutException, AuthException (asserts both copy AND `widgetWithText(SnackBarAction, 'Sign in')`), ValidationException with known field, ValidationException with unknown field, DatabaseException (safety-net pin).

**Verification:**

- [x] `dart format .` clean.
- [x] `dart analyze --fatal-infos` clean. `check_reward_accent`, `check_hardcoded_colors`, `check_typography_call_sites`, `check_no_developer_log` all clean.
- [x] `flutter test --exclude-tags integration --exclude-tags golden test/unit test/widget` — 3403 pass, 1 skipped, 0 failures. Integration tests in `test/integration/` already fail on main for env reasons (no live local Supabase) — not regressions.
- [ ] Open PR with `**QA pass pending — final coverage + E2E run after code review.**`

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
