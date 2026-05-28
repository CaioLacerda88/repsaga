# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

## Phase 32 PR 32b — Auth correctness + Credential Manager + security audit

**Branch:** `feature/phase-32b-auth-correctness`

**Source spec:** `docs/PROJECT.md` §3 Phase 32 → "PR 32b — Auth correctness +
Credential Manager + targeted security audit".

**Scope:** Three workstreams in one PR — Credential Manager autofill
integration on `LoginScreen`, missing test coverage for duplicate-email +
Google Sign-In, and a targeted security audit whose report ships in the
PR description. Per spec: "no code unless findings warrant a follow-up" —
audit is investigation-only by default.

### Boundary inventory — auth surface (from Explore audit 2026-05-28)

(Per CLAUDE.md "Boundary-trigger ripple check" — this PR touches the
login screen + adds a Credential Manager dep that fires native API calls.
Both are boundary surfaces.)

**Reactive state shape (no signature changes planned, but consumers must
not regress):**
- `authStateProvider` (`lib/features/auth/providers/auth_providers.dart`
  L50–97) — `StreamProvider<AuthState>` with fallback timer + initial-event
  fast path. Consumed by `app_router.dart:68` for redirect logic and
  `login_screen.dart:158,162` for error display.
- `authNotifierProvider` — `AsyncNotifier<Session?>`. 7 public methods
  (`signUpWithEmail`, `signInWithEmail`, `signInWithGoogle`, `signOut`,
  `resetPassword`, `resendConfirmationEmail`, `deleteAccount`).
- `_RouterRefreshListenable` (`app_router.dart`) — re-evaluates redirect
  on `authStateProvider` or `needsOnboardingProvider` change. **Race risk:**
  any new auth event emitted by Credential Manager could re-trigger the
  redirect chain — CM save must NOT emit AuthChangeEvents. Track via
  cluster `async-caller-broke-snackbar` family (state-machine integrity).

**OAuth deep-link contract (untouched, but documented for the audit):**
- `auth_repository.dart:90–97` — `signInWithGoogle` calls
  `_auth.signInWithOAuth(OAuthProvider.google, redirectTo:
  'io.supabase.repsaga://login-callback/')`. Returns immediately after
  browser launch; session arrives async via `onAuthStateChange` listener
  on the next deep-link callback.
- Android intent filter at `android/app/src/main/AndroidManifest.xml:73–78`
  (scheme `io.supabase.repsaga`). iOS scheme NOT verified in audit —
  out of scope for this PR (Android-first launch).

**E2E selector inventory (11 current `auth-*` identifiers — verified in
`test/e2e/helpers/selectors.ts:31–56`):**
- `auth-email-input`, `auth-password-input`, `auth-login-btn`,
  `auth-signup-btn`, `auth-toggle-signup`, `auth-toggle-login`,
  `auth-google-btn`, `auth-forgot-pwd`, `auth-send-reset`,
  `auth-welcome-back`, plus AUTH.errorMessage (`[aria-live="polite"]`).
- Specs that assert: `test/e2e/specs/auth.spec.ts` (smoke + full),
  `test/e2e/helpers/auth.ts` (login + logout helpers used across many
  specs). **Anything that renames or removes these identifiers cascades
  into ~all E2E specs via the shared `login()` helper.**

**Audit pre-scan results (passes — no criticals expected in final report):**
- RLS policies: every user-data table (`profiles`, `routines`, `workouts`,
  `workout_exercises`, `sets`, `personal_records`, `workout_templates`,
  `weekly_plans`, `analytics_events`, `subscriptions`, `subscription_events`,
  `user_xp`, `xp_events`, `body_part_progress`, `exercise_peak_loads`,
  `earned_titles`, `backfill_progress`, `vitality_runs`) has policies
  scoped to `auth.uid()` ownership; service-role-only tables
  (`analytics_events`-INSERT-only, `xp_events`-no-INSERT,
  `subscriptions`-no-write) follow the intentional asymmetry pattern.
- Edge Functions (`delete-user`, `validate-purchase`, `rtdn-webhook`,
  `vitality-nightly`): all verify JWT via Authorization header parse;
  CORS restricted to `SUPABASE_URL`; idempotency guards on the writers
  via PK constraints or UPSERT.
- Client bundle scan: `git grep` for `service_role` / `sk_live` / `sk_test`
  / `eyJ` in `lib/` — all zero. `.env` has `SUPABASE_URL` +
  `SUPABASE_ANON_KEY` + `SENTRY_DSN` only (anon key is public by
  Supabase design).

### Decisions locked (this WIP)

- **Credential Manager package:** start with `supabase_flutter ^2.5.0`'s
  built-in OAuth flow + the `google_sign_in` package (likely already
  transitively present). Tech-lead to verify via Context7 lookup —
  package + version pinning per `feedback_context7_when_to_use.md`.
  Avoid `credential_manager` (community pkg) unless `google_sign_in`
  cannot satisfy the autofill UX.
- **iOS scope:** out (Android-first launch). Note in PR description.
- **autofill UX:** add `AutofillHints.email` + `AutofillHints.password`
  / `AutofillHints.newPassword` to `AppTextField` via a new
  `autofillHints` constructor param. Wrap the login form in
  `AutofillGroup` so OS surfaces the save prompt on submit.
- **CM save trigger:** after successful `signInWithEmail` /
  `signUpWithEmail` ONLY. OAuth flows save credentials through the
  browser's native password manager — we don't add a duplicate save
  prompt for those. Save call must be synchronous-safe and must NOT
  emit `AuthChangeEvent`s (validate by reading
  `_RouterRefreshListenable` assumptions — see boundary inventory).
- **Duplicate-email widget test:** mock Supabase signup with the
  literal `'user already registered'` error string. Assert the
  `authErrorAlreadyRegistered` snackbar renders + dismisses on
  duration. Use behavior-not-wiring per `feedback_test_user_visible_behavior`.
- **Google Sign-In E2E spec:** new `test/e2e/specs/auth-google.spec.ts`.
  Tag `@smoke`. Use existing test-user infrastructure; mock the OAuth
  redirect via Playwright's `page.route()` to return a deterministic
  callback URL (Supabase's hosted callback isn't exercisable from
  Playwright without an actual Google account).
- **Audit report scope:** ship the pre-scan results from this WIP as
  the PR-description audit report. No new code from audit unless
  reviewer raises a Blocker on a finding.

### Files to create / modify

**Implementation (must change):**
- [x] **Decision pivot:** no new dependency needed. `AutofillHints`,
  `AutofillGroup`, and `TextInput.finishAutofillContext` are first-party
  Flutter APIs (since 1.20). Android Credential Manager (API 34+) and
  iOS Passwords (12+) pick them up natively when wired through the
  shared autofill scope. `google_sign_in` was deferred — it would have
  required native Android module configuration (SHA-1, OAuth client ID)
  outside this PR's scope, and OAuth save flows are already handled by
  the in-app browser's password manager (per WIP "decisions locked").
  `pubspec.yaml` was NOT modified.
- [x] **Modified** `lib/shared/widgets/app_text_field.dart` — added
  optional `autofillHints` parameter, forwarded to `TextFormField`.
  Backwards-compatible (default `null`).
- [x] **Modified** `lib/features/auth/ui/login_screen.dart`:
  - Form body wrapped in `AutofillGroup`
  - Email field: `autofillHints: const [AutofillHints.email]`
  - Password field: switches between `AutofillHints.password` (login)
    and `AutofillHints.newPassword` (signup) based on `_isSignUp`
  - `_submit` calls `_finishAutofillIfSucceeded` after successful auth,
    which gates on `authNotifierProvider.hasError` then invokes
    `TextInput.finishAutofillContext()` — surfaces the OS save prompt
    only on success.

**Tests (must add):**
- [x] **Created** `test/widget/features/auth/ui/duplicate_email_snackbar_test.dart`
  (2 tests). Pumps `LoginScreen` with `authRepositoryProvider` + 
  `hiveServiceProvider` overridden to mocks that throw 
  `Exception('User already registered')` on `signUpWithEmail`. Pins:
  - banner renders the exact en `authErrorAlreadyRegistered` string
  - banner persists past `Duration(seconds: 10)` simulated pump (no
    auto-dismiss — the inline-banner contract differs from the WIP's
    "snackbar dismisses on duration" spec; the negative pin guards
    `cluster_persist_eats_duration` if the surface is ever migrated to
    a timed SnackBar)
- [x] **Created** `test/widget/features/auth/ui/autofill_hints_test.dart`
  (4 tests). Walks the Semantics tree to the underlying `EditableText`
  for each field; asserts `autofillHints` equality. Includes a
  `findsOneWidget` check for `AutofillGroup` (without it the per-field
  hints are no-ops on submit).
- [x] **Created** `test/e2e/specs/auth-google.spec.ts` (`@smoke`).
  Test 1: button selector pin (visibility). Test 2: tap → assert
  either (a) an outbound request hits `/auth/v1/authorize?provider=google`
  OR (b) the login screen disappears (navigation away). Real Google
  OAuth completion is not testable from Playwright.

**Selectors (must update if any new identifier shipped):**
- [x] No new identifier required. `AUTH.googleButton` already exists in
  `test/e2e/helpers/selectors.ts` (line 45).

**Audit report (PR description only — no files in repo):**
- [ ] Compose a markdown audit report from the WIP boundary inventory:
  RLS policy summary by table, Edge Function JWT-verify status, bundle
  secret scan results, dependency leak check. Format as a collapsed
  `<details>` block in the PR body so it doesn't dominate the diff
  conversation.

### Verification

- `make ci` green (format + analyze + test + android-debug-build)
- E2E `--grep @smoke` green locally (full suite optional — pulled
  by remote CI)
- **Visual verification on physical Android** (CLAUDE.md step 9):
  1. Build APK + install on physical Android (API 34+ required for
     Credential Manager)
  2. Sign up with a fresh email — assert OS save-credentials prompt
     surfaces post-submit
  3. Sign out, return to login — assert OS autofill chip surfaces
     above the keyboard for the email field
  4. Tap autofill chip — assert email + password populate from
     Credential Manager
  5. Screenshot each step; attach to PR thread

### Decisions captured

- **Credential Manager dep TBD via Context7** — tech-lead picks between
  `supabase_flutter` minor upgrade vs adding `google_sign_in` based on
  what each version supports natively
- **iOS not in scope** — Android-first launch; iOS Credential Manager
  flows ship with whichever phase adds iOS deployment
- **OAuth save flow is browser-handled** — we do not add a custom save
  prompt for the Google flow; Chrome's password manager handles it
- **Audit findings ship in PR description** — no separate audit doc;
  goes into git history via the PR body
- **Per `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`:**
  all reviewer findings (Blocker / Important / Nit) fix in cycle. No
  follow-ups for "minor security tweaks" — if reviewer raises one, it
  fixes here.
