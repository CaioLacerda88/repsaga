# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Fix — onboarding save error + retry path + regression tests

Branch: `fix/onboarding-save-error-databaseexception-42501-and-retry-investigation`

Surfaced FOUR times today across four different fix attempts. User confirmation:
snackbar reads "Couldn't save your profile" on a fresh email+password signup,
deterministic, Wi-Fi connected — rules out network flake and pins it to a
`DatabaseException` (or unmapped exception) reaching the safety-net fallback
in `_showSaveErrorSnack`.

**Systematic debugging summary (PROJECT.md Debugging Protocol — Phase 1-3):**

* Phase 1 (root cause): user-visible symptom is the safety-net snackbar
  ("Couldn't save your profile"). PR #302 typed-dispatch matrix on
  `_showSaveErrorSnack` covers `NetworkException`, `TimeoutException`,
  `AuthException`, `ValidationException` — `DatabaseException` falls through.
  PR #298's `BaseRepository.refreshAndRetry` succeeds at the refresh call but
  the second `upsertProfile` STILL fails with PostgREST `42501`. The repository
  rethrows the ORIGINAL 42501 → wrapped as `DatabaseException(code: '42501')`
  → reaches the catch in `_finishOnboarding` → typed-dispatch has no
  `DatabaseException` branch → falls through to "Couldn't save your profile".
* Phase 2 (pattern): existing `AuthException` branch (PR #302) is the working
  template — "Your session expired. Sign in again." + Sign in CTA → /login.
  Re-login mints a fresh JWT and the user can complete onboarding on the
  second attempt. Same recovery affordance applies to the second-attempt
  `42501` (the bearer's claims didn't resolve to the right PostgREST role).
* Phase 3 (hypothesis): targeted source-dive on `gotrue-2.19.0` + `supabase-2.10.4`
  pins that the SDK plumbing IS correct — `AuthHttpClient.send()` calls
  `await _getAccessToken()` every request (`auth_http_client.dart:12`), and
  `_callRefreshToken` writes `_saveSession(session)` BEFORE returning
  (`gotrue_client.dart:1294-1295`). So `auth.currentSession.accessToken` IS the
  new bearer when the second `upsert` fires. Root cause of the server-side
  `42501` (auth.uid() = NULL despite a fresh successful refresh) remains
  opaque without instrumented logs — likely a server-side claim-resolution
  edge case on the fresh-signup path (refresh token rotated server-side,
  email-confirm deep-link chain broken, or JWT-secret rotation lag — see
  cluster `stale-token-silent-anon-fallback` candidate flag in
  `base_repository.dart:96`). **Layer 1+2 make the flow user-recoverable
  regardless of the underlying server-side cause.**

**Layer breakdown (5):**

* **Layer 1 — defensive UX (typed `DatabaseException(42501)` branch).**
  Add a branch BEFORE the safety-net fallback in `_showSaveErrorSnack` that
  matches `DatabaseException` with code `'42501'`, surfaces
  `onboardingErrorSessionExpired` + `onboardingErrorSessionExpiredCta` CTA
  (same recovery as the `AuthException` branch — re-login mints a fresh JWT).
  Other `DatabaseException` codes (e.g. `23xxx` CHECK violations) continue
  to fall through to the safety net.
  - Cluster: `stale-token-silent-anon-fallback` (candidate, see Layer 3).
  - Cluster: `persist-eats-duration` — explicit `persist: false` for symmetry
    with the `AuthException` branch (CTA-bearing SnackBar default is `true`).
  - Cluster: `action-not-snackbaraction` — use `SnackBarAction` not bare
    `TextButton` so Material auto-hides on press.

* **Layer 2 — provider footgun (`currentUserIdProvider` stale-cache).**
  `currentUserIdProvider` is documented "not reactive" but it's a `Provider<String?>`
  — Riverpod caches the result on first read until invalidated. If the first
  read happens before Supabase restores its session, the cached value is null
  forever in that container, and `saveOnboardingProfile` silently no-ops.
  Replace `ref.read(currentUserIdProvider)` with
  `ref.read(authStateProvider).value?.session?.user.id` in
  `saveOnboardingProfile`, `updateTrainingFrequency`, and `toggleWeightUnit`
  — aligning with the `build()` reactive pattern documented at
  `profile_providers.dart:60` (cluster: `provider-init-timing`).

* **Layer 3 — retry path investigation (deferred).**
  Source-read on `gotrue-2.19.0` + `supabase-2.10.4` (15 min budget) confirms
  the SDK does NOT cache stale bearers: `AuthHttpClient` fetches the current
  session's access token per-request. The second 42501 therefore reflects a
  server-side condition (auth.uid() = NULL) that the client cannot diagnose
  alone. Documented inline in `base_repository.dart:96` (cluster candidate
  `stale-token-silent-anon-fallback`). Layer 1+2 already make the flow
  user-recoverable — flagging Layer 3 as **follow-up — needs instrumented
  server logs from a reproducer** in the PR body.

* **Layer 4 — tests (no regressions).**
  - Unit: `profile_repository_test.dart` — add a "retry-exhausted" case
    (first `upsert` 42501, refresh OK, second `upsert` 42501 → throws
    `DatabaseException(code: '42501')` with the ORIGINAL message). Pins the
    contract that the retry-path tests already cover for refresh-failure but
    not for second-attempt-failure (the actual production symptom).
  - Widget: `onboarding_save_error_test.dart` — replace the existing
    "DatabaseException 500" safety-net case with two cases: (a)
    `DatabaseException(code: '42501')` → session-expired copy + Sign in CTA,
    (b) `DatabaseException(code: '23514')` → safety-net copy still fires.
  - Widget: NEW `profile_notifier_save_test.dart` — pins that
    `saveOnboardingProfile` reads userId from `authStateProvider` (the live
    session), not from a stale `currentUserIdProvider` cache. Two cases:
    (a) `authStateProvider` has no session → silent no-op (no upsert call,
    no exception), (b) `authStateProvider` has a session → upsert called
    with the session user's id.
  - E2E: `onboarding.spec.ts` — strengthen Test 3 to assert no error snackbar
    appears in the success path; add NEW Test 5 that completes onboarding,
    logs out, logs back in, and asserts the user lands on `/home` directly
    (pins the `onboarded_at` persistence contract end-to-end).

* **Layer 5 — WIP.md + PR body (this section + the PR description).**

**Implementation checklist:**

- [x] Phase 1-3 systematic-debugging — source-dive on `gotrue-2.19.0` +
      `supabase-2.10.4` confirmed SDK plumbing is correct; root cause is
      server-side and deferred.
- [x] Layer 1 — `_showSaveErrorSnack` `DatabaseException(42501)` branch
      (extracted `_showSessionExpiredSnack` helper shared with the
      `AuthException` branch since the recovery affordance is identical)
- [x] Layer 2 — `saveOnboardingProfile` + `updateTrainingFrequency` +
      `toggleWeightUnit` switch from `currentUserIdProvider` to
      `authStateProvider`-derived userId via new `_currentSessionUserId()`
      helper
- [x] Layer 3 — inline comment in `base_repository.dart` documenting the
      source-dive conclusion (deferred — follow-up needs server logs)
- [x] Layer 4 unit — retry-exhausted case in `profile_repository_test.dart`
      (case already exists at L676-717 from PR #298; flagged in WIP as
      pinning the contract — no new test needed)
- [x] Layer 4 widget — DatabaseException(42501)/23514/500 cases in
      `onboarding_save_error_test.dart` (3 cases replacing the prior
      single safety-net case)
- [x] Layer 4 widget — `profile_notifier_save_test.dart` (NEW file) pins
      the live authState userId contract on `saveOnboardingProfile`,
      `updateTrainingFrequency`, and `toggleWeightUnit` — 5 tests
- [x] Layer 4 E2E — strengthen Test 3, add Test 5 (logout→login→/home)
- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` — 0 new infos/warnings/errors on
      touched files (pre-existing project-wide infos unchanged)
- [x] `flutter test test/unit/features/profile/ test/widget/features/auth/`
      — 177/177 green
- [x] `flutter test` end-to-end: 3491 passed + 1 skipped; 25 pre-existing
      integration failures (PGRST204 "Could not find the 'name' column of
      'exercises'" — require local Supabase) unchanged from main HEAD —
      identical to the Legal PR 2 baseline note above. Zero regressions
      from the typed-dispatch / authState-derivation changes.
- [ ] PR body includes `**QA pass pending — final coverage + E2E run after code review.**`
- [ ] PR body calls out Layer 3 deferral with reason

### Legal PR 2 — UI consent flows

Branch: `feat/legal-pr2-consent-ui-age-gate-toggles`

Follow-up to Legal PR 1 (#305) — that PR shipped Policy + ToS copy hedged as
"delivered by a forthcoming app update". This PR ships the 4 UI surfaces that
make those hedges true. Cluster reference: `data-protection-compliance`
(PROJECT.md §0 Cluster Ledger; named in PR #307).

**Surfaces (4):**

1. **Age confirmation at signup** — `lib/features/auth/ui/login_screen.dart`.
   New `CheckboxListTile` shown only in signup mode below the password field
   ("I confirm I am 18 years of age or older."). Sign-up CTA disabled until
   checked. State is local to the screen (transient per signup attempt). Inline
   ToS / Privacy Policy links route via `context.push`. ARB keys:
   `signupAgeConfirmation`, `signupAgeConfirmationLink`.
2. **Bodyweight sensitive-data opt-in** — new
   `lib/features/profile/providers/bodyweight_consent_provider.dart` mirroring
   `crash_reports_enabled_provider.dart` (Hive key `bodyweight_consent_enabled`,
   default **false** — explicit opt-in for sensitive health data per LGPD Art.
   11). UI changes:
   - `bodyweight_row.dart` — `BodyweightEditorSheet._onSave` shows a consent
     dialog when consent is false, defers save until "Save with consent" is
     tapped. Dialog title + body + 2 actions, no SnackBar (the dialog itself
     is the surface).
   - New `bodyweight_consent_toggle.dart` widget mounted in Profile Settings
     → Privacy section. Withdrawal mechanism.
3. **Gender opt-in disclosure** — new gender editor in `profile_settings_screen.dart`
   (currently there's no gender UI — Phase 29 v2 wired the column but the
   editor was deferred). Includes a one-time disclosure banner gated by
   `gender_consent_enabled` Hive key. Banner hidden once any value has been
   picked. New provider `gender_consent_provider.dart`.
4. **Analytics opt-out toggle** — exact-mirror of `CrashReportsToggle`:
   - `lib/features/analytics/data/analytics_repository.dart` — static `_enabled`
     flag + `setEnabled(bool)`; `insertEvent` short-circuits when disabled.
   - `lib/features/profile/providers/analytics_enabled_provider.dart` — Hive
     key `analytics_enabled`, default **true** (legitimate-interest opt-out).
   - `lib/features/profile/ui/widgets/analytics_toggle.dart` — `SwitchListTile`.
   - Mount in `profile_settings_screen.dart` PRIVACY section immediately below
     `CrashReportsToggle`.

**Implementation checklist:**

- [x] Surface 4 — Analytics opt-out (smallest, exact CrashReports mirror)
- [x] Surface 1 — Age confirmation checkbox at signup
- [x] Surface 2 — Bodyweight consent provider + dialog + withdrawal toggle
- [x] Surface 3 — Gender editor + opt-in banner + consent provider
- [x] ARB additions in BOTH `app_en.arb` + `app_pt.arb`
- [x] `flutter gen-l10n` regen
- [x] Unit tests for each new provider (12/12 green)
- [x] Widget tests for each new surface (38/38 green; behavior-not-wiring per CLAUDE.md A2)
- [x] `dart format .` + `dart analyze --fatal-infos` clean
- [x] `flutter test` — 3491 passed; 25 baseline integration failures unchanged from main HEAD (require local Supabase)
- [ ] Branch + commit + push + open PR

**Verification:**

- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean
- [x] Affected unit/widget tests green
- [x] Existing tests with new dependencies updated (login duplicate-email tests
      now tick age checkbox; profile_screen_test counts adjusted for new rows)
- [ ] PR body includes `**QA pass pending — final coverage + E2E run after code review.**`
