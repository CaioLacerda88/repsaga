/// Locales supported by RepSaga for UI and auth email templates.
///
/// Single source of truth shared across three sites that must stay in
/// sync — adding a new locale touches all three together:
///
/// 1. `MaterialApp.supportedLocales` (`lib/app.dart`) — Flutter's
///    runtime list of locales the UI can render. Built directly from
///    this const.
/// 2. `ProfileNotifier._hydrateLocaleMetadataIfMissing`
///    (`lib/features/profile/providers/profile_providers.dart`) —
///    refuses to write a non-allowlisted locale into
///    `auth.users.raw_user_meta_data`. Protects the email-template
///    `{{ if eq .Data.locale "<X>" }}` branches from ever seeing a
///    locale value they aren't wired to handle.
/// 3. SQL backfill `supabase/migrations/00073_backfill_user_metadata_locale.sql`
///    uses the literal `IN ('en','pt')` allowlist. The migration's
///    header comment cross-references this file; keep both in sync.
///
/// Adding a new locale: see `docs/auth-email-templates/README.md` →
/// "Adding a new locale" for the full checklist (template bodies,
/// subject lines, this const, the migration backfill if any users
/// already have `profiles.locale = '<new>'`).
const kSupportedLocales = <String>['en', 'pt'];
