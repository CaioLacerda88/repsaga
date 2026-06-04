# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Legal PR 1 — Privacy Policy + ToS copy updates (LGPD + GDPR + medical)

Branch: `docs/legal-pr1-policy-tos-copy-lgpd-gdpr-medical`

First of three PRs closing the read-only legal audit. PR 1 is **copy-only**
to `assets/legal/privacy_policy.md` + `assets/legal/terms_of_service.md` and
their byte-identical `docs/` mirrors (Jekyll front-matter aside). No UI
surfaces, no Dart code, no schema. The `LegalDocScreen` rendering pipeline
(`flutter_markdown_plus`) handles the longer document unchanged.

PR 2 (UI consent flows: age-gate signup checkbox, sensitive-data opt-in
toggle for bodyweight + gender, withdrawal toggle parity, consent-state
Hive box) and PR 3 (in-app workout-history export → JSON over signed URL)
ship the runtime surfaces this PR only declares.

**Blockers addressed (Privacy Policy):**

- [x] L1 — lawful basis enumerated per data category (LGPD Art. 6,
      GDPR Art. 6 §1(b/f), Art. 9 §2(a))
- [x] L2 — body weight + gender classified as sensitive personal data
      (LGPD Art. 11 / GDPR Art. 9), opt-in declared, fallback to
      reduced bodyweight-XP accuracy stated
- [x] L3 — gender disclosed in §2 with purpose (XP-calc accuracy via
      gender-aware tier tables) + `'other'`/NULL → male table fallback
- [x] L4 — Art. 18 / Art. 15-21 rights with declared in-app surfaces
      and email-fallback SLA (15 business days)
- [x] L5 — DPO / Encarregado named: Caio Lacerda, `dpo@repsaga.app`
      (LGPD Art. 41 reference)
- [x] L6 — minimum age raised to 18 (16 in EEA per GDPR Art. 8 §1
      conservative floor); parental-consent infra absent
- [x] G3 — consent withdrawal as easy as giving it (Art. 7 §3)
- [x] G4 — granular erasure: body weight + avatar deletable
      individually without account closure (Art. 17)
- [x] G6 — retention period stated: active account + 30 days purge,
      hedged by Supabase backup window
- [x] G7 — cross-border transfers covered by Supabase DPA + SCCs
      (`https://supabase.com/dpa`, GDPR Art. 46)
- [x] G8 — right to lodge complaint with national DPA stated
- [x] L7 — subscription/purchase data shape pre-declared (Launch Phase
      paywall): `product_id`, `purchase_token`, state, billing window;
      Google Play handles payment, RepSaga sees no card data
- [x] L8 — analytics enumeration expanded with actual event taxonomy
      from `lib/features/analytics/data/models/analytics_event.dart`
      and identifier purge on account delete
- [x] L9 — avatar storage explicitly named: private bucket + signed
      URLs (1-year TTL)
- [x] L10 — §9 reworded from "by using you consent" to Supabase DPA +
      SCCs (LGPD Art. 33 / GDPR Chapter V mechanism)
- [x] L11 — derived RPG data (XP totals, body-part progress, class,
      earned titles) disclosed as processed data and included in
      deletion scope
- [x] L13 — breach notification commitment (ANPD-required timeframe)
- [x] L12 (nit) — 30-day deletion hedged with Supabase backup schedule
- [x] last-updated date bumped to 2026-06-04

**Blockers addressed (Terms of Service):**

- [x] M1 — RPG-specific overtraining disclaimer (title/rank never a
      reason to train injured or skip recovery)
- [x] M2 — RED-S / disordered-eating language; bodyweight optionality
      reaffirmed
- [x] M3 — youth lifter growth-plate disclaimer (belt-and-braces even
      with 18+ floor)
- [x] M4 — cardiovascular condition explicit callout
- [x] M5 — pregnant / postpartum explicit callout
- [x] M6 — share-card camera/photo disclosure: local processing only,
      never uploaded
- [x] M7 — "stop if you feel pain" copy moved to top of §1, bolded
      as a dedicated warning paragraph
- [x] §3 minimum age aligned with Privacy Policy §8 (18+ globally,
      16+ EEA)
- [x] last-updated date bumped to 2026-06-04

**Mirroring:**

- [x] `docs/privacy_policy.md` body byte-identical to
      `assets/legal/privacy_policy.md` (Jekyll front-matter preserved)
- [x] `docs/terms_of_service.md` body byte-identical to
      `assets/legal/terms_of_service.md`

**Verification:**

- [x] `dart format .` clean (no Dart changes; format leg passes)
- [x] `dart analyze --fatal-infos` clean (0 issues — markdown-only)
- [x] `flutter test` — `LegalDocScreen` rendering tests pass against
      the expanded markdown (test bundle is synthetic, decoupled
      from policy text)
- [x] `make ci` end-to-end green

**Out of scope (PR 2 / PR 3):**

- Age-confirmation checkbox at signup → PR 2
- Sensitive-data opt-in surface for bodyweight + gender → PR 2
- Consent withdrawal toggle parity → PR 2
- In-app JSON export of workout history → PR 3
- Separate `dpo@repsaga.app` alias provisioning → Caio (outside repo)

**Round 2 — reviewer findings (4 Blockers + 5 Important + 4 Nits, all
same-cycle per `feedback_no_deferring_review_findings`):**

- [x] B1 — overpromise on UI surfaces hedged at 3 sites: §2a sensitive-
      data toggles (opt-in + withdrawal both routed through `dpo@`
      until the in-app toggles ship), §6 withdrawal-of-consent row,
      ToS §3 age-confirmation checkbox
- [x] B2 — malformed `Art. 11 §I(a)` LGPD citation fixed at 2
      occurrences in §4a (body weight + gender rows) → `Art. 11, I`
- [x] B3 — §6 granular-erasure internal contradiction resolved: row
      now matches the export-row hedging pattern (forthcoming UI;
      `dpo@` + 15 business days in the meantime)
- [x] B4 — Sentry toggle verified live in `lib/`: `CrashReportsToggle`
      mounted at `profile_settings_screen.dart:197`, backed by
      `crashReportsEnabledProvider` (Hive `user_prefs` +
      `SentryReport.setEnabled`). §5 path tightened to
      `Profile → Settings → Privacy → Send crash reports` with an
      explicit "wired to live SDK" note; present-tense retained
- [x] I1 — §8 EEA age floor simplified to a single global 18+
      threshold that exceeds the GDPR Art. 8 §1 floor of 16; ToS §3
      mirrored
- [x] I2 — §6 Access vs Portability rows split: Access (Art. 18 II /
      GDPR Art. 15) → human-readable email summary; Portability
      (Art. 18 V / GDPR Art. 20) → forthcoming in-app machine-readable
      JSON. Cross-references inline so future portability launch
      doesn't muddle Access
- [x] I3 — kept the "balancing test documented and available on
      request" phrase in §4a (good practice). **TODO for Caio,
      outside this PR:** write a short one-page internal LGPD-Art. 7
      IX legitimate-interest balancing memo (purposes vs. data-subject
      rights, mitigations applied: no advertising, no third-party
      enrichment, no PII in event payloads, deletion cascade on
      account close) before any LGPD/ANPD inquiry lands. Stash under
      `docs/` (or wherever Caio prefers internal compliance docs)
- [x] I4 — §4 cross-border vagueness fixed with explicit "see §9"
      cross-reference naming LGPD Art. 33 + GDPR Chapter V safeguards
- [x] I5 — ToS §9 liability cap reworded from "greater of US $0 or…"
      to "greater of (a) the amount you paid in the 12 months
      preceding the claim, or (b) R$0 if you are a free-tier user,
      except where prohibited by mandatory consumer-protection law
      including the CDC" — switches to BRL and softens framing
- [x] N1 — avatar TTL infra-specifics removed: "short-lived signed
      URLs that expire and are automatically regenerated"
- [x] N2 — withdrawal "takes effect immediately" → "takes effect
      promptly (CDN-cached signed URLs may have brief propagation
      delay)"
- [x] N3 / N4 — every `PR 2` / `PR 3` / `legal compliance series`
      reference replaced with "a forthcoming app update" across both
      `assets/legal/` files and both `docs/` mirrors. Grep verified
      zero remaining occurrences in user-facing markdown

**Round 2 verification:**

- [x] `dart format .` clean (markdown-only diff)
- [x] `dart analyze --fatal-infos` clean (only pre-existing `.env`
      asset warning, identical to main)
- [x] `flutter test test/widget/shared/widgets/legal_doc_screen_test.dart`
      — 4/4 pass against the round-2 markdown
- [x] `make ci` end-to-end green; android debug build exit 0
- [x] `diff <(tail -n +6 docs/...md) assets/legal/...md` — body
      byte-parity preserved for both files

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
