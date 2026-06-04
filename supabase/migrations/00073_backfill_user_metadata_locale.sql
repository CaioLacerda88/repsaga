-- PR A2 — fix(auth): backfill user_metadata.locale for legacy users.
--
-- Context. PR #300 wired the Flutter app to forward
-- `localeProvider.languageCode` into `user_metadata.locale` at signup
-- so the locale-routed email templates (PR #299/#301) can branch on
-- `{{ if eq .Data.locale "pt" }}`. Two populations were explicitly
-- documented as "Known edge cases" in
-- `docs/auth-email-templates/README.md` and deferred:
--
--   1. Legacy users — anyone who signed up before PR #300 merged has
--      no `raw_user_meta_data.locale` on their `auth.users` row.
--   2. Google OAuth users — Supabase's OAuth flow cannot set
--      `user_metadata` at signup time (covered by the Dart-side client
--      hydration in `ProfileNotifier`, not this migration).
--
-- This migration closes population #1 by copying `profiles.locale` →
-- `auth.users.raw_user_meta_data.locale` for every user whose
-- `profiles.locale` is in the supported allowlist and whose
-- `raw_user_meta_data->>'locale'` is currently NULL.
--
-- Idempotent. The `IS NULL` guard makes re-running this migration a
-- no-op for anyone whose metadata has already been written (either by
-- a prior run, by post-PR-300 signup, or by the client-side hydration
-- helper). Safe to re-apply if the migration is ever re-run against an
-- environment that's already been backfilled.
--
-- Allowlist. The hardcoded `IN ('en','pt')` list MUST stay in sync with
-- `lib/core/constants/supported_locales.dart` → `kSupportedLocales` and
-- with `MaterialApp.supportedLocales` (driven by the same const). When
-- v1.1 adds a new locale, all three sites get updated together — see
-- `docs/auth-email-templates/README.md` → "Adding a new locale".
-- Unsupported locale values on `profiles.locale` (corrupted seed data,
-- unsupported region tag) are intentionally skipped here so we never
-- pollute `auth.users.raw_user_meta_data` with values the email
-- templates would still route to the `{{ else }}` English branch
-- anyway.
--
-- No CHECK constraint, no trigger, no RLS change. The UPDATE runs as
-- the migration's superuser role (postgres) so RLS does not apply, and
-- the existing `auth.users` schema is unchanged. The single UPDATE is
-- safe inside the default migration transaction — the CLAUDE.md
-- `cluster_postgres_alter_type_transaction` rule applies only to
-- `ALTER TYPE ... ADD VALUE`, which this migration does not perform.
--
-- COALESCE on the source side. A handful of legacy auth.users rows have
-- `raw_user_meta_data = NULL` (no metadata key at all, not even an
-- empty object). Without the COALESCE the `|| jsonb_build_object(...)`
-- short-circuits to NULL and the whole row's metadata gets clobbered.
-- COALESCE pins us to `'{}'::jsonb` as the safe identity element.

UPDATE auth.users u
SET raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb)
                       || jsonb_build_object('locale', p.locale)
FROM public.profiles p
WHERE u.id = p.id
  AND (u.raw_user_meta_data->>'locale') IS NULL
  AND p.locale IN ('en', 'pt');
