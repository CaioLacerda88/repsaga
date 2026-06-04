# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### PR A2 — locale metadata backfill + client hydration

Branch: `feat/auth-locale-metadata-backfill-and-client-hydration`

Closes the two `user_metadata.locale = NULL` populations documented in PR
#300's `docs/auth-email-templates/README.md` → "Known edge cases" and
explicitly deferred:

1. **Legacy users** — anyone who signed up before PR #300 merged. Their
   `auth.users.raw_user_meta_data` has no `locale` key, so password reset,
   magic link, and email change emails fall into the template's
   `{{ else }}` English branch regardless of `profiles.locale`.
2. **Google OAuth signups** — Supabase's OAuth flow cannot set
   `user_metadata` at authorization time, so OAuth users land in the same
   `{{ else }}` English branch even if their `profiles.locale = 'pt'`.

Two-layer fix:

**SQL migration (bounded, one-shot — covers legacy users):**

- [x] `supabase/migrations/00073_backfill_user_metadata_locale.sql` —
      idempotent UPDATE merging `profiles.locale` into
      `auth.users.raw_user_meta_data` for every user whose metadata locale
      is currently NULL and whose `profiles.locale IN ('en','pt')`.
      `COALESCE(raw_user_meta_data, '{}'::jsonb)` defends against legacy
      rows with NULL metadata.

**Dart client hydration (unbounded, ongoing — covers OAuth + any future
gap):**

- [x] `lib/core/constants/supported_locales.dart` — new const
      `kSupportedLocales = ['en','pt']` shared by `MaterialApp.supportedLocales`,
      the SQL backfill allowlist (comment cross-reference), and the
      hydration helper's allowlist guard.
- [x] `lib/app.dart` — `MaterialApp.supportedLocales` consumes
      `kSupportedLocales.map(Locale.new).toList()` instead of the
      gen-l10n-produced `AppLocalizations.supportedLocales`. A unit test
      pins the two stay in sync.
- [x] `lib/features/auth/data/auth_repository.dart` — new
      `updateUserMetadata(Map<String, Object?> data)` wraps
      `_auth.updateUser(UserAttributes(data:))` with `mapException` +
      `_authTimeout`. Keeps Supabase access inside the repository layer.
- [x] `lib/features/profile/providers/profile_providers.dart` —
      `ProfileNotifier.build()` fires `unawaited(_hydrateLocaleMetadataIfMissing(profile))`
      after `getProfile(...)` resolves. The helper short-circuits when
      `user_metadata.locale` is already populated, when `profile.locale`
      is not in `kSupportedLocales`, or on any caught error (Sentry
      breadcrumb only — never an `AsyncError` on the profile). Placement
      rides on the existing `provider-init-timing` cluster fix so the
      check re-runs on every signedIn / tokenRefreshed event.

**Tests:**

- [x] `test/unit/features/profile/providers/profile_notifier_locale_hydration_test.dart` —
      6 hydration cases + 1 contract test:
  - writes locale = 'pt' when metadata locale is null + profile.locale is 'pt'
  - no-op when user_metadata.locale is already populated
  - no-op when getProfile returns null (no profile row yet)
  - no-op when profile.locale not in `kSupportedLocales` (e.g. 'fr')
  - `updateUserMetadata` failure does not promote profile to AsyncError
  - fires for 'en' too (proves it is not pt-specific)
  - `kSupportedLocales` matches `AppLocalizations.supportedLocales`

**Verification:**

- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean (0 issues)
- [x] 3408 unit + widget tests pass, 1 skipped, 0 failures. 25 integration
      tests fail for environment reasons (no live local Supabase) — same
      baseline as `main`, not regressions.
- [x] `make ci` end-to-end green (format + gen + analyze + test + android
      debug build) — opened PR #303
- [x] PR body includes
      `**QA pass pending — final coverage + E2E run after code review.**`

**Post-merge:** apply migration 00073 to hosted Supabase via
`npx supabase db push` so the legacy-user backfill lands in production.
Verify the email-template "Pre-existing user" verification case from
`docs/auth-email-templates/README.md` flips from `{{ else }}` to `pt` for
a sample legacy `profiles.locale = 'pt'` user.
