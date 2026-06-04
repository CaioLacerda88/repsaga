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
- [x] Open PR with `**QA pass pending — final coverage + E2E run after code review.**` — PR #302
