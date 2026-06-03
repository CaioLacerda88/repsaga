# Auth email templates — locale-routed (Round 4.5)

Source of truth for the four auth flow emails (signup confirmation, password
reset, magic link, email change). Each template renders ONE language —
Portuguese (pt-BR) when `user_metadata.locale == "pt"`, English otherwise.

The Dart side writes `user_metadata.locale` during password signup by
forwarding the app locale through `AuthRepository.signUpWithEmail(locale:)` —
see `lib/features/auth/providers/notifiers/auth_notifier.dart`.

## Files

| Flow                  | HTML                        | Plain text                |
| --------------------- | --------------------------- | ------------------------- |
| Sign-up confirmation  | `confirm-signup.html`       | `confirm-signup.txt`      |
| Password reset        | `reset-password.html`       | `reset-password.txt`      |
| Magic link            | `magic-link.html`           | `magic-link.txt`          |
| Email change          | `change-email.html`         | `change-email.txt`        |

## Subject lines (Supabase Dashboard)

Subject lines are configured separately in **Supabase Dashboard → Authentication
→ Email templates → Subject heading**. Paste these conditional strings exactly
— Supabase evaluates Go-template syntax in subject lines the same way it does
in bodies:

| Template         | Subject heading                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------- |
| `confirm-signup` | `{{ if eq .Data.locale "pt" }}Confirme sua conta no RepSaga{{ else }}Confirm your RepSaga account{{ end }}` |
| `reset-password` | `{{ if eq .Data.locale "pt" }}Redefina sua senha no RepSaga{{ else }}Reset your RepSaga password{{ end }}` |
| `magic-link`     | `{{ if eq .Data.locale "pt" }}Seu link de acesso ao RepSaga{{ else }}Your RepSaga sign-in link{{ end }}` |
| `change-email`   | `{{ if eq .Data.locale "pt" }}Confirme seu novo e-mail{{ else }}Confirm your new email address{{ end }}` |

## How the locale routing works

Every template body wraps its content in:

```go
{{ if eq .Data.locale "pt" }}
  <!-- Portuguese body -->
{{ else }}
  <!-- English body — also serves as the default for any locale != "pt"
       and for emails where .Data.locale is missing entirely. -->
{{ end }}
```

`.Data` is the user's `user_metadata` map. When Supabase processes a template,
it interpolates the metadata it has on the user record. Two important
consequences:

1. **English is the default branch.** Any locale value other than `"pt"` —
   including `"en"`, `"es"`, `null`, or a missing key — falls into the `else`
   branch. This is deliberate: English is the safest fallback for an
   unrecognized or absent locale.
2. **Only one language renders.** Each delivered email contains a single
   localized body. No "ENGLISH / PORTUGUÊS" eyebrow labels, no hairline
   divider, no bilingual stack — those artifacts from Rounds 1-4 are gone.

## Verification checklist

When updating Supabase templates from this repo, verify all three branches
land correctly before signing off the rollout:

- [ ] **Default branch (no `.Data.locale`).** Trigger a flow against a user
      with no `user_metadata.locale` set (e.g. a freshly created user via the
      Supabase Admin API without `user_metadata`, or a Google OAuth user —
      see "Known edge case" below). Confirm the **English** body and subject
      render. The `else` branch is the safety net for unknown locales.
- [ ] **Portuguese branch (`pt`).** Trigger a flow with
      `signUp(..., data: {'locale': 'pt'})` and confirm the **Portuguese**
      body and subject render. From the RepSaga app, this happens
      automatically whenever the user has the app in Portuguese at signup
      time.
- [ ] **Explicit English (`en`).** Trigger a flow with
      `signUp(..., data: {'locale': 'en'})` and confirm the **English** body
      and subject render. This proves the `else` branch covers both the
      explicit-en case and the no-metadata case identically.

For a quick local check that doesn't require deploying to the hosted
Supabase project, run the relevant Dart unit test:

```bash
flutter test test/unit/features/auth/data/auth_repository_test.dart \
             test/unit/features/auth/providers/auth_notifier_test.dart
```

The unit tests pin that `signUpWithEmail` writes the expected
`user_metadata.locale` value (or omits it entirely when no locale is
passed) — so a green test run guarantees the Dart side will hand the
correct payload to Supabase. The template-side rendering still needs an
end-to-end send check the first time you push template changes.

## Known edge case

**Google OAuth signups have no `user_metadata.locale`.** Supabase's OAuth
provider flow does not let the client write arbitrary `user_metadata` at
authorization time — the metadata Google returns (name, picture, email_verified)
is merged in, but `locale` from the RepSaga app is not. Consequently, the
first auth email a Google-OAuth user might receive (e.g. magic link, password
reset after they add a password) will fall into the `{{ else }}` branch and
render in English, even if their `profiles.locale` row in the database is
`pt`.

This is acceptable for v1 because:

- OAuth users typically have a session immediately after sign-in (no
  confirmation email needed).
- The fallback language is English, which is the universally safe default for
  any auth flow.

If we want Portuguese auth emails for OAuth users, the fix is a post-signup
Edge Function that copies `profiles.locale` → `auth.users.user_metadata.locale`
once the profile row is created (or updated). This is flagged as a **Launch
Phase scope-expansion candidate**. Do not build it in this PR.

## Updating templates in Supabase

The hosted Supabase project consumes these templates via Dashboard, not via
migration. After editing a file here:

1. Open Supabase Dashboard → Authentication → Email templates.
2. For each updated flow, paste the new subject heading (from the table
   above) and the new body (full file contents).
3. Run the three verification cases above on a staging or scratch user.
4. Squash-merge the PR once template behavior is confirmed in the Dashboard.
