# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Onboarding profile RLS — root-cause analysis

Bug: brand-new user (`gihfigueiredo_@hotmail.com`, uid
`9038f670-d8c8-4af4-a815-d6f7ee4ed945`) hits PostgREST `42501` when tapping
"Let's Go" on `/onboarding`. Captured live via adb logcat against hosted
Supabase on a Samsung S938B release build of `main @ b3eab15f`.

User-reported clue: the email confirmation link "showed an error" but they
still logged in afterward.

#### 1. Evidence (verified)

- Hosted RLS policies on `public.profiles` are correct. Direct SQL impersonation
  with `SET LOCAL request.jwt.claims = '{"sub":"<uid>","role":"authenticated"}'`
  + the same upsert payload succeeds. The policy lets the row through when a
  real JWT with `sub=<uid>` arrives.
- The user's `auth.users` row is healthy: `email_confirmed_at=13:27:48 UTC`,
  `last_sign_in_at=13:28:15 UTC`, `role='authenticated'`, `aud='authenticated'`.
- The `profiles` row exists (default values from the `handle_new_user`
  trigger).
- The error fires at 13:33 UTC — ~5 minutes after sign-in. Default Supabase
  access token TTL is 1 hour, so the token issued at sign-in is NOT expired
  by clock-time.
- Because the request was rejected at the RLS layer (42501, not 401), the
  request DID carry an `Authorization: Bearer <something>` header — but with
  a JWT whose `role` resolves to `anon` at PostgREST (or with NO bearer at
  all → anon by default). Either way, the upsert hits `anon` policies, which
  do not exist for `profiles`.

Therefore the question is: **why does the Dart client send a request without
the authenticated user's JWT, even though `auth.currentUser?.id` returns a
non-null id?**

#### 2. Hypothesis

**ONE theory.** The user's first sign-in came via `signInWithPassword` AFTER
a broken email-confirmation deep-link attempt. The broken deep-link is the
critical clue — here's the causal chain:

1. User signs up. `auth_notifier.signUpWithEmail` → gotrue PKCE flow
   (`AuthFlowType.pkce`, `main.dart:61`). A PKCE code verifier is written to
   `_asyncStorage` under key `<defaultStorageKey>-code-verifier`
   (`gotrue_client.dart:216`). No session yet — confirmation pending.
2. User opens the confirmation email. The link points at Supabase's hosted
   `/auth/v1/verify` endpoint. Supabase's hosted Site URL / redirect-URL
   allowlist does NOT include `io.supabase.repsaga://login-callback/` for
   the email flow (the Android manifest only registers
   `<data android:scheme="io.supabase.repsaga"/>` for OAuth —
   `android/app/src/main/AndroidManifest.xml:77`). The hosted verify endpoint
   redirects to its fallback (the project's Site URL, typically `localhost:3000`
   or the deprecated `auth/v1/verify` HTML page) — user sees the "error" they
   reported. **At this point the PKCE code verifier in mobile local storage
   is still pending.** The hosted verify step nonetheless marks
   `email_confirmed_at` on the server (matching the captured 13:27:48 UTC).
3. User goes back to the app and signs in with email+password via
   `signInWithPassword`. This call uses the `password` grant (NOT the
   PKCE `auth_code` exchange) — see `gotrue_client.dart:285`. A session
   is returned, `_saveSession` runs (line 311), `AuthChangeEvent.signedIn`
   fires (line 312). `currentSession` and `currentUser` are now populated.
4. Router redirects to `/onboarding` (login screen sets
   `needsOnboardingProvider=true` only on the SIGNUP path,
   `login_screen.dart:67` — but the user is logged in nonetheless and
   `needsOnboardingProvider` would have been set during step 1's signup
   attempt because `needsOnboardingProvider` is a plain `StateProvider`,
   not cleared on app restart, AND the user might be on a brand-new install
   where it defaulted to `false` — in that case the only way they reached
   `/onboarding` is the post-signup gate from step 1, meaning the state
   provider IS true).

**The disconnect.** Given `currentSession != null` and `currentUser?.id`
returning the correct uid, the most plausible JWT-missing failure mode that
matches the observed `42501` (auth header IS sent, but with `anon` claims)
is one of:

- **A.** The session loaded synchronously at step 1's app start
  (`SupabaseAuth.initialize` → `setInitialSession`, supabase_flutter
  `supabase_auth.dart:63`) is a STALE session from a previous tenant /
  install / test-run on the device. `setInitialSession` does NOT check
  `session.isExpired` (`gotrue_client.dart:1007-1017`) — it blindly assigns
  `_currentSession = session` and emits `AuthChangeEvent.initialSession`.
  When the user later signs in, the synchronous `signInWithPassword`
  response DOES populate the session correctly. But `_getAccessToken`
  in `supabase-2.10.4/lib/src/supabase_client.dart:242-271` returns
  `currentSession?.accessToken` — and if the stale session was somehow
  not overwritten (e.g. because of an aborted refresh path), the access
  token attached to the upsert is the prior tenant's expired JWT, which
  Supabase Auth → PostgREST resolves to `role=anon`.
- **B.** (More likely.) The user opened the email link on a different
  device / web. Their mobile app NEVER processed the PKCE deep-link, so
  the code verifier from step 1's signup sits in local storage. When they
  return and sign in via password, the password grant succeeds, but the
  PKCE verifier is still there. **In supabase_flutter 2.12.2's deep-link
  observer (`supabase_auth.dart:139-145`), ANY incoming URI with a `code`
  query parameter triggers `getSessionFromUrl` while
  `_authFlowType == AuthFlowType.pkce` is true.** Some launcher / OEM
  intent (e.g. Samsung's Smart Switch app-handoff, or a stale OEM
  intent re-delivery on app foreground) can re-deliver an old intent
  containing a `code=` parameter — and `_isAuthCallbackDeeplink` would
  match it. `getSessionFromUrl` then calls `exchangeCodeForSession`
  (`gotrue_client.dart:334-377`), which: (a) consumes the stored PKCE
  verifier, (b) hits gotrue `/token?grant_type=pkce`, (c) on success
  REPLACES `_currentSession` with the exchanged session. If gotrue
  rejects the code (already-used / expired) but with a 2xx response that
  AuthSessionUrlResponse mis-parses — `Session.fromJson` returns null on
  missing `access_token` and the `!` would throw — and the catch on
  `supabase_auth.dart:222-227` would only log it. Net effect: a window
  where `currentSession` is mutated mid-request, or where the access token
  attached to a queued upsert is stale.

**However**, both A and B require races / external intents I cannot prove
without device-side logs. The **simplest hypothesis that fits all observed
facts** is theory **C**, which I now lift above A/B:

- **C (primary hypothesis).** Hosted Supabase's `Site URL` is misconfigured
  for this project. The email confirmation link points at a redirect target
  the user's mobile browser can't open into the app (no Android App Link
  + `assetlinks.json`, no `intent://` filter for an `https` host —
  the manifest only registers `io.supabase.repsaga` scheme for OAuth).
  Supabase's `/auth/v1/verify?token=...&type=signup&redirect_to=...` hits
  its fallback rendering — the "error" the user saw. Crucially, when the
  user later signs in via password, gotrue's `/token?grant_type=password`
  IS rejected with `email_not_confirmed` UNLESS the verify endpoint already
  marked the email confirmed server-side. The captured DB row shows
  `email_confirmed_at=13:27:48 UTC`, meaning the verify endpoint DID confirm
  the email — but the response sent back to the browser was the error HTML
  page (because the redirect target was invalid). The password sign-in then
  succeeds at 13:28:15 UTC. **At this point the session IS valid.**

  The actual failure at 13:33 (5 minutes later) then traces to: at app
  cold-start `App.build()` constructs the GoRouter (with its embedded
  `_RouterRefreshListenable`), which `ref.listen`s `authStateProvider`.
  `authStateProvider` synchronously emits `initialSession` from
  `repo.currentSession` (`auth_providers.dart:58-62`). At cold-start
  immediately after `Supabase.initialize()`, **`supabase_flutter`'s
  `SupabaseAuth.initialize` runs `await _localStorage.initialize()` then
  `await ... setInitialSession(persistedSession)` (`supabase_auth.dart:54-69`)
  AS A FUTURE that `Supabase.initialize()` does NOT await fully** — the
  Future returned by `Supabase.initialize` resolves before the Flutter-only
  `SupabaseAuth.initialize`'s deep-link observer completes. Combined with
  the deep-link observer auto-firing on initial URI (when the user
  re-opened the app via the email link's failure page, the URI carrying
  `?code=<broken-or-already-used>` was queued), the flow is:

  1. `main()` → `await Supabase.initialize(...)` returns.
  2. `runApp` mounts. `App.build` constructs router. `currentUserIdProvider`
     synchronously returns the password-sign-in user.
  3. In parallel, `_handleInitialUri` (`supabase_auth.dart:190-210`) on
     the FIRST app open after the email-link tap consumes the queued
     `code=...` URI and calls `exchangeCodeForSession`.
  4. `exchangeCodeForSession` either succeeds (replacing the session, no
     harm) OR — if the code is invalid / already used — **throws inside
     the catch, but BEFORE throwing it consumes the verifier and may have
     partially mutated `_currentSession` via `_saveSession(session)` if
     `Session.fromJson` returned a session with null `access_token` but
     non-null user via a sloppy deserialization path on a 200-but-error
     gotrue response.**

  But again, even C requires deep-link logs to confirm.

**Refined primary hypothesis (the simplest one consistent with ALL facts):**

> The Authorization bearer attached to the PostgREST upsert is `null` (so the
> `AuthHttpClient` falls back to the supabase ANON key, `auth_http_client.dart:13-15`)
> because `_getAccessToken` (`supabase_client.dart:242-271`) entered its
> `currentSession?.isExpired` branch, called `refreshSession()`, the refresh
> FAILED (the broken deep-link state left the refresh token invalidated
> server-side — confirm-and-relogin can rotate refresh tokens), the catch on
> line 252-268 swallowed the error because `expiresAt` was within Supabase's
> 10-second `expiryMargin` rather than already past, and `_getAccessToken`
> fell through to return `currentSession?.accessToken` — but `_currentSession`
> was already nulled by a concurrent `signedOut` notification from the failed
> refresh, leaving `accessToken` null. AuthHttpClient then attaches the anon
> key → PostgREST resolves to `role=anon` → no `anon` insert policy on
> `profiles` → 42501.

The user-reported deep-link error is the proximate cause because Supabase
server-side rotates / invalidates refresh tokens when the verify endpoint
runs after the email has already been confirmed elsewhere (or when a
password sign-in races a hosted `verify` redirect).

#### 3. Minimum verification step

A single targeted `debugPrint` in `ProfileNotifier.saveOnboardingProfile`
captures every variable needed to discriminate A / B / C above. We dump the
auth state IMMEDIATELY before the upsert call:

```diff
--- a/lib/features/profile/providers/profile_providers.dart
+++ b/lib/features/profile/providers/profile_providers.dart
@@ -62,17 +62,32 @@ class ProfileNotifier extends AsyncNotifier<Profile?> {
   Future<void> saveOnboardingProfile({
     required String displayName,
     required String fitnessLevel,
     int trainingFrequencyPerWeek = 3,
   }) async {
     final userId = ref.read(currentUserIdProvider);
     if (userId == null) return;
+    // TEMP DIAGNOSTIC — onboarding RLS 42501 root-cause probe. Remove once
+    // the hypothesis is confirmed/refuted (do NOT ship).
+    final client = Supabase.instance.client;
+    final session = client.auth.currentSession;
+    final accessToken = session?.accessToken;
+    final tokenLen = accessToken?.length ?? 0;
+    final tokenPrefix = accessToken == null
+        ? 'null'
+        : accessToken.substring(0, accessToken.length.clamp(0, 16));
+    debugPrint(
+      '[onboarding-rls-probe] userId=$userId '
+      'sessionPresent=${session != null} '
+      'sessionUserId=${session?.user.id} '
+      'isExpired=${session?.isExpired} '
+      'expiresAt=${session?.expiresAt} '
+      'tokenLen=$tokenLen '
+      'tokenPrefix=$tokenPrefix',
+    );
     final repo = ref.read(profileRepositoryProvider);
     state = AsyncData(
       await repo.upsertProfile(
         userId: userId,
         displayName: displayName,
         fitnessLevel: fitnessLevel,
         trainingFrequencyPerWeek: trainingFrequencyPerWeek,
       ),
     );
   }
```

Plus the required new imports:

```diff
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:flutter_riverpod/legacy.dart' show StateProvider;
+import 'package:flutter/foundation.dart' show debugPrint;
 import 'package:hive_flutter/hive_flutter.dart';
 import 'package:supabase_flutter/supabase_flutter.dart';
```

(`Supabase` is already imported on line 4.)

**Why this works:** the line MUST emit via `debugPrint` (not `developer.log`)
so it surfaces in adb logcat per cluster `developer-log-invisible-logcat`.
The variables discriminate between hypotheses:

- If `sessionPresent=false` → router gate is broken; we shouldn't have been
  on `/onboarding` (refutes C, points at A or B).
- If `sessionPresent=true` && `tokenLen=0` → `accessToken` is the empty
  string, which is the gotrue-2.19.0 deserialization-edge bug shape.
- If `sessionPresent=true` && `tokenLen>0` && `isExpired=true` → the
  `_getAccessToken` refresh path silently failed; confirms C primary
  hypothesis.
- If `sessionPresent=true` && `tokenLen>0` && `isExpired=false` &&
  `sessionUserId == userId` → the JWT is being sent but PostgREST is
  resolving its `role` claim incorrectly (would point at hosted JWT-secret
  rotation or a malformed JWT payload — refutes A/B/C and opens new branch).

**Deploy:** apply the diff, `flutter build apk --release`, install on the
S938B (`adb install -r build/app/outputs/flutter-apk/app-release.apk`), have
the user reproduce. `adb logcat -s flutter` captures the line.

#### 4. If hypothesis confirmed (sessionPresent=true && isExpired=true)

Fix sketch (do NOT implement yet):

- The right fix is to make `saveOnboardingProfile` (and every other
  authenticated repository call) survive a stale/expired token by
  explicitly calling `await Supabase.instance.client.auth.refreshSession()`
  via the repository's existing `refreshSession()` method when an upsert
  fails with `42501`. The retry must be bounded (one shot) and only on
  RLS errors (not on every error class). Pattern lives at the BaseRepository
  / ErrorMapper boundary so all repositories inherit it.
- Secondary fix: in `_RouterRefreshListenable`, also re-evaluate
  `authState.value?.session?.isExpired` so a stale session in the cache
  does not pass the `isLoggedIn` gate and let the user reach `/onboarding`
  with a token that will fail.
- The deep-link "error" is a hosted-Supabase config issue (Site URL +
  Additional Redirect URLs allowlist must include an Android intent-fileable
  destination). Out of scope for this Dart fix but should be documented in
  PROJECT.md as a release blocker.

#### 5. If hypothesis refuted

Next branches:

- If `sessionPresent=false` on `/onboarding`: investigate router gate
  (`app_router.dart:67-95`) — the `isLoggedIn = authState.value?.session
  != null` check must be racing the persisted-session load. Add a second
  `debugPrint` in the redirect callback dumping `authState.value?.session`
  and `currentUser?.id`. Pattern: cluster
  `provider-init-timing` (App.build subscribing to async state at mount
  caches stale).
- If `sessionUserId != userId`: a stale session from a previous device
  user / test run; need to audit `SupabaseAuth.initialize` →
  `setInitialSession` for the tenant-isolation gap (gotrue 2.19.0 does NOT
  validate the session JWT's `sub` against any stored uid before
  assigning it; that's a known sharp edge with multi-tenant Hive boxes
  surviving uninstalls — but `allowBackup=false` on the manifest should
  prevent this).
- If everything looks healthy: capture the literal request via
  `adb logcat | grep -i postgrest` or install Charles Proxy on a wifi
  bridge and read the actual `Authorization` header that the device sends.
  The 42501 with a valid-looking JWT pointing at the right uid would
  mean PostgREST is rejecting the JWT for a reason other than auth
  (e.g. hosted JWT secret rotated and the cached session was signed with
  the old secret — would need to compare the JWT's `iat` against the
  Supabase project's JWT-secret-rotation timestamp).

---

### PR 2 — refresh-retry on 42501 — implementation checklist

Branch: `fix/auth-refresh-retry-on-stale-token`
Per WIP.md → "Auth → Onboarding → Home flow — architectural audit & remediation plan" → PR 2.

- [ ] Add `debugSetBreadcrumbFn` test seam to `SentryReport` (mirrors `debugSetCaptureFn`).
- [ ] Add `_refreshAndRetry<T>({required action, required refresh})` to `BaseRepository`. ONE retry, bounded. On 42501 / 401 catch → `await refresh()` → re-invoke action. Second failure rethrows the ORIGINAL error.
- [ ] Emit `SentryReport.addBreadcrumb(category: 'auth', message: 'session_refreshed_inline')` on successful retry.
- [ ] Wrap `ProfileRepository.{upsertProfile, updateTrainingFrequency, updateWeightUnit, updateLocale}` with the new helper. `getProfile` (read) NOT wrapped.
- [ ] Inline cluster reference comment near `_refreshAndRetry` → `async-caller-broke-snackbar` (close analog).
- [ ] Failing-first tests in `test/unit/features/profile/data/profile_repository_test.dart`:
  - First upsert throws 42501, second succeeds → returns row, refreshSession called once, upsert called twice, breadcrumb fires.
  - 23505 (non-42501) → no retry, no refresh call, throws immediately.
  - 42501 + refreshSession throws → original 42501 surfaces (no double-wrap).
  - 401 AuthException → same retry pattern.
  - Successful first call → no refresh, no retry.
- [ ] `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] `make ci` green.
- [ ] PR body includes literal `**QA pass pending — final coverage + E2E run after code review.**`.
- [ ] Remove this WIP section after merge.

---

### Auth → Onboarding → Home flow — architectural audit & remediation plan

Author: tech-lead (read-only architectural pass — no code lands until the
orchestrator picks PRs to dispatch).
Scope: the entire path from `signUpWithEmail` / `signInWithEmail` /
`signInWithGoogle` through `email_confirmation_screen` → `onboarding_screen`
→ `home_screen`, plus the `IdentityCard` rename path and every recovery
affordance on the way.

#### 1. State machine — current

Intended (what `app_router.dart` redirect block implies):

  - `splash` while `authStateProvider.isLoading == true`.
  - `login` when no session AND no `signupPendingEmailProvider`.
  - `email-confirmation` when no session AND `signupPendingEmailProvider !=
    null`.
  - `onboarding` when `session != null` AND
    `needsOnboardingProvider == true`.
  - `home` when `session != null` AND `needsOnboardingProvider == false`.

Concrete defect / drift surfaces:

  - **D1. Onboarding flag has no DB anchor.** `needsOnboardingProvider`
    (`lib/features/auth/providers/onboarding_provider.dart:5`) is a plain
    `StateProvider<bool>` defaulting to `false`. Only set to `true` on the
    signup path (`login_screen.dart:67`). Process restart → flag resets →
    half-onboarded users with `profiles.display_name = null` land on
    `/home` (matches today's repro of `gihfigueiredo_@hotmail.com`).
  - **D2. The flag is a runtime cache of a derivable fact.** The truth
    lives in `profiles` (specifically `display_name`); the boolean is a
    coincidental shadow. Violates "structural guarantees over runtime
    flags" — a single missed `setState(true)` or process restart drifts
    the state machine.
  - **D3. Splash terminal state.** `isLoading` is `AsyncValue.isLoading` of
    `authStateProvider` — the stream synchronously emits an `initialSession`
    event (`auth_providers.dart:58-62`) so `isLoading` flips to `false`
    immediately. We never park on `/splash` for an actual loading window;
    the splash route is effectively unreachable after `main()` returns.
    Not a bug, but it means the splash is dead code unless we add a
    "session refresh on resume" pre-router step.
  - **D4. Stale session never proactively refreshed.** No call site invokes
    `AuthRepository.refreshSession()`. `_getAccessToken` inside
    `SupabaseClient` does so lazily and best-effort — if refresh fails
    (refresh token rotated by the broken deep-link path, network blip), the
    next mutation hits PostgREST with anon and surfaces as `42501`. The
    router gate doesn't check `session.isExpired` — `isLoggedIn =
    authState.value?.session != null` admits expired sessions.
  - **D5. `_finishOnboarding` swallows AppException categorically.** Single
    catch → generic `failedToSaveProfile` snackbar (`onboarding_screen.dart
    :100-107`). No retry, no re-auth affordance, no breadcrumb, no
    analytics. RLS-rejected writes look identical to airplane-mode writes
    look identical to "Supabase returned 500".
  - **D6. `IdentityCard` rename is silent on failure.** `identity_card.dart
    :234-237` calls `upsertProfile` then `ref.invalidate(profileProvider)`.
    Nothing in the try/catch chain — if the same anon-JWT path fires here,
    the dialog closes, the name does NOT change, the user has no signal.
  - **D7. Auth notifier doesn't surface success-vs-error to callers
    structurally.** `login_screen._submit` reads `ref.read(authNotifier
    Provider).hasError` after `await` to decide whether to set the
    onboarding flag + navigate. That's three repeated `ref.read` calls
    racing on a single mutation — works today because `AsyncValue.guard`
    completes synchronously after the awaited Future, but it's a smell:
    a future caller awaiting concurrently could land between two reads
    and flip the value. A `Result<T, AppException>` return type would make
    success branching explicit.
  - **D8. Email confirmation deep-link unhandled on Android.** Manifest
    intent-filter only registers `io.supabase.repsaga://` scheme (line 77)
    for the OAuth callback. The hosted Supabase verify endpoint redirects
    to whatever Site URL is configured — not deep-linked into the app —
    so the user sees the hosted error / fallback HTML. The server still
    sets `email_confirmed_at` (verified in the live row), but the PKCE
    code verifier in mobile local storage is left dangling. Subsequent
    password sign-in works but the residual PKCE state is one of the
    suspects in the 42501 chain.
  - **D9. No breadcrumb on profile-write failures.** `BaseRepository.map
    Exception` captures unexpected raw errors via
    `SentryReport.captureException` (line 74) but `AppException` rethrows
    skip the breadcrumb path (line 67) — fine for tracker hygiene, but
    means the 42501 case (mapped → `DatabaseException`) has NO Sentry
    trail at all because no upstream breadcrumb fires either.
  - **D10. `_handleInitialUri` deep-link delivery not observed.** We don't
    log when supabase_flutter's deep-link observer fires `getSessionFrom
    Url` after a cold start. If an OEM redelivers a stale `?code=` intent
    the resulting session mutation is invisible. The prior analysis lists
    this as the secondary suspect; we have no observability surface for
    confirming/refuting.
  - **D11. `signupPendingEmailProvider` is also a runtime-only flag.**
    Cleared on logged-in branch of redirect (`app_router.dart:90`). If
    the user kills the app between signup and confirmation, they lose
    the "we sent confirmation to <email>" affordance — they'll land on
    `/login` with no breadcrumb that they have a pending confirmation.
    Same class as D1.

#### 2. State machine — proposed

Replace the boolean cache with a derivation:

  ```
  needsOnboarding := session != null
                     AND (profile == null
                          OR (profile.displayName ?? '').trim().isEmpty)
  ```

`displayName` is the only field truly user-supplied during onboarding —
`fitnessLevel` and `trainingFrequencyPerWeek` have server-side defaults
(`'beginner'` / `3`) that the `handle_new_user` trigger does NOT set
(`00001_initial_schema.sql:46-53` only inserts `id` + `created_at`;
defaults are column-level), so the row exists with `display_name = null`,
`fitness_level = 'beginner'` (column default), `training_frequency_per_week
 = 3` (column default — set in a later migration).

Why not add a `profiles.onboarded_at timestamptz` column:

  - Pros: explicit, future-proof if onboarding gains additional gated
    fields.
  - Cons: needs a hosted migration + a backfill UPDATE for existing
    users (set to `now()` where `display_name IS NOT NULL` else `null`);
    one more column to keep in sync; doesn't actually buy us anything
    `display_name IS NULL` doesn't already give us.

Recommendation: derive from `display_name` for v1 (PR 1 below). If
onboarding gains a second required field (e.g. forced gender pick to
make Phase 29 tier tables deterministic), promote to `onboarded_at` in
a follow-up.

Proposed state machine (router redirect):

  ```
  if authState.isLoading                          -> /splash
  if session == null
       AND signupPendingEmail != null             -> /email-confirmation
       AND location is /privacy|/terms            -> stay
       else                                       -> /login
  if session != null AND session.isExpired
       AND refreshSession() fails                 -> /login (force re-auth)
  if session != null AND profile.isLoading        -> /splash (NEW —
                                                    block until we know
                                                    if onboarding is
                                                    needed)
  if session != null AND profile is error         -> /onboarding-error
                                                    (NEW — see PR 3
                                                    below) OR retry
  if session != null AND profile.displayName
       is null/empty AND location != /onboarding  -> /onboarding
  if session != null AND onboarded
       AND location in {/login, /splash}          -> /home
  ```

Crucial: the router must `ref.watch(profileProvider)` (it currently does
not). Adding the watch makes the redirect callback re-run on profile
arrival; the `_RouterRefreshListenable` already has the pattern for
adding listeners — extend it to also listen to `profileProvider`.

Trade-off (open question §5 Q2): adding `profileProvider` to the redirect
means a first-time-render race — the redirect fires when profile is
still `AsyncLoading`. We can either (a) block on `/splash` until profile
resolves (proposed above — clean state machine, one extra splash beat on
cold start ~150-300ms) OR (b) optimistically route to `/home` and
redirect to `/onboarding` if the profile arrives with a null display
name (one frame of `/home` flash but no splash extension). I prefer (a)
for state-machine cleanliness; the user blast radius is one extra splash
beat for one-time onboarding users.

#### 3. Error handling matrix

Columns: entry point | error category | current UX | proposed UX |
recovery affordance | telemetry.

| Entry | Category | Current | Proposed | Recovery | Telemetry |
|---|---|---|---|---|---|
| `signUpWithEmail` | `AuthException` (already_registered, weak_password) | Inline error via `AuthErrorMessages.fromError` | Same (works) | Switch to Log In + prefill email | breadcrumb `auth.sign_up_email_failed` with `code` only |
| `signUpWithEmail` | `NetworkException` | Inline `authErrorNetwork` | Same (works) | Retry button on inline error card | breadcrumb `auth.sign_up_email_network` |
| `signUpWithEmail` | `TimeoutException` | Inline `authErrorTimeout` | Same (works) | Retry | breadcrumb |
| `signUpWithEmail` | `DatabaseException` (handle_new_user trigger fails) | Generic snackbar | Inline error: "We couldn't set up your account. Try again or contact support." + Sentry capture | Retry once; second failure → support copy with email link | Sentry capture (this is a server-side bug, not a user error) |
| `signInWithEmail` | `AuthException` (invalid_credentials, email_not_confirmed) | Inline error via mapper | Same (works) — email_not_confirmed already routes to `authErrorEmailNotConfirmed` | If email_not_confirmed: button "Resend confirmation" that flips to `/email-confirmation` | breadcrumb `auth.sign_in_email_failed` with `code` only |
| `signInWithEmail` | `NetworkException` / `TimeoutException` | Inline error | Same | Retry | breadcrumb |
| `signInWithGoogle` | `AuthException` | Snackbar via mapper | Inline error card | Retry | breadcrumb `auth.sign_in_google_failed` |
| `signInWithGoogle` | `NetworkException` | Same | Same | Retry | breadcrumb |
| `signInWithGoogle` | OAuth redirect timeout (user dropped from browser without completing) | No surface — provider stays loading until next emission | Add 60s soft timeout that returns user to login with copy "Sign-in didn't complete" | Retry button | breadcrumb |
| `_finishOnboarding` | `AuthException` (token expired / invalid) | Generic snackbar | Specific copy: "Your session expired. Sign in again." + force `signOut()` + redirect to `/login` | Forced re-auth | Sentry capture (this should not happen if PR 2 lands) |
| `_finishOnboarding` | `DatabaseException` code=`42501` | Generic snackbar | Specific copy: "Couldn't save your profile. Tap to retry." + one auto-retry after `refreshSession()` | Manual retry, then force re-auth on second failure | Sentry capture WITH category breadcrumb `profile.onboarding_rls_42501` + analytics `onboarding_failed` |
| `_finishOnboarding` | `DatabaseException` other codes | Generic snackbar | Same generic snackbar (the catchall) + Sentry capture | Manual retry | Sentry capture |
| `_finishOnboarding` | `NetworkException` / `TimeoutException` | Generic snackbar | Specific copy: "You're offline. Your profile will save once you reconnect." (we could even queue to offline_queue, but profile upsert is outside the existing queue scope — see open question Q4) OR copy "Couldn't reach the server. Tap to retry." | Manual retry; offline_queue if we extend it | breadcrumb |
| `_finishOnboarding` | empty name | Snackbar "please enter name" | Same (works) but render as inline field error rather than snackbar | inline | none |
| `IdentityCard.updateDisplayName` | any AppException | **SILENT — no try/catch** (dialog closes, name unchanged) | Snackbar with mapped message + the same retry/re-auth ladder as `_finishOnboarding` | Manual retry from settings | Sentry capture |
| `IdentityCard.updateDisplayName` | optimistic-UI gap | After upsert returns, we `ref.invalidate(profileProvider)` — refetch races local form state; for ~300ms the new name might not show | Use AsyncNotifier `state = AsyncData(updatedProfile)` directly inside a `ProfileNotifier.updateDisplayName(...)` method (mirroring `updateTrainingFrequency`) so the new name renders instantly | n/a | n/a |

Gaps that the matrix surfaces:

  - **G1. No `ProfileNotifier.updateDisplayName` method exists** —
    `IdentityCard` bypasses the notifier and writes directly via the
    repository. That's a layering violation (UI calling repository
    directly, skipping the notifier's state-update contract). The
    pattern should match `updateTrainingFrequency` /
    `toggleWeightUnit`.
  - **G2. `_finishOnboarding` does not differentiate by AppException
    subtype.** All errors look the same. The recovery affordance differs
    fundamentally between `DatabaseException` (retry) and
    `AuthException` (force re-auth).
  - **G3. No "force-re-auth-with-toast" helper.** When we detect a stale
    session anywhere, the right move is `signOut()` + redirect to login
    with a toast like "Your session expired. Sign in to continue.". This
    helper doesn't exist; each call site would have to roll it.
  - **G4. No Sentry breadcrumb on profile-write success/failure.** Only
    `auth.sign_*` breadcrumbs exist; profile writes are invisible. When
    a 42501 fires we have zero context.
  - **G5. `onboardingFailed` analytics event missing** — we only emit
    `onboardingCompleted` on the success branch.

#### 4. Remediation plan — decomposed into reviewable PRs

Order: PR 1 unblocks the user-visible drift; PR 2 fixes the proximate
42501 cause; PR 3 hardens the error surface; PR 4 closes the deep-link
loop; PR 5 retrofits observability. Each PR is independently mergeable
to hosted prod.

##### PR 1 — `fix(auth): derive onboarding state from profile row`

Scope:
  - Delete `lib/features/auth/providers/onboarding_provider.dart` and
    every reference.
  - Replace with a new derived provider, e.g.
    `needsOnboardingProvider = Provider<bool>((ref) {
      final session = ref.watch(authStateProvider).value?.session;
      if (session == null) return false;
      final profile = ref.watch(profileProvider).value;
      // If the profile hasn't loaded yet, return false (router stays on
      // splash anyway because we extend the loading gate — see below).
      // After load, true iff displayName is null/empty/whitespace.
      if (profile == null) return true;  // row missing entirely
      final dn = profile.displayName?.trim() ?? '';
      return dn.isEmpty;
    });`
  - Extend `_RouterRefreshListenable` to also listen to
    `profileProvider`.
  - Extend the router redirect's `isLoading` gate to ALSO park on
    `/splash` when `session != null && profileProvider.isLoading`.
  - Strip the `ref.read(needsOnboardingProvider.notifier).state = true`
    from `login_screen.dart:67` and `... = false` from
    `onboarding_screen.dart:79` — both become unnecessary because the
    provider is derived.

Acceptance criteria:
  - User who half-onboards, kills the app, reopens → lands on
    `/onboarding` (not `/home`).
  - User with `display_name = "Caio"` who reopens → lands on `/home` (no
    onboarding flash).
  - Fresh signup that succeeds → land on `/onboarding` then `/home`
    after submit (current happy path unchanged).
  - No `setState(true)` / `setState(false)` calls anywhere in the
    onboarding flow.

Tests required (pin exact deterministic outcomes per
`feedback_engineering_quality_bar`):
  - Unit: `needsOnboardingProvider` returns `true` for a profile with
    `displayName: null`, `true` for `''`, `true` for `' '` (whitespace-
    only), `false` for `'Caio'`, `false` when session is null.
  - Widget: with a `ProviderScope` overriding `authStateProvider` →
    valid session AND `profileProvider` → `AsyncData(Profile(display
    Name: null))`, pump `MaterialApp.router(routerConfig: router)`,
    assert the rendered screen is `OnboardingScreen` (not
    `HomeScreen`).
  - Widget: same setup but `Profile(displayName: 'Caio')` → renders
    `HomeScreen`.
  - Widget: process-restart simulation — pump with `authStateProvider`
    overridden to a valid session, then dispose + repump with a NEW
    container (simulating fresh Riverpod scope) and assert routing is
    identical to first pump (no flag-survival bug).

Migration / data-shape impact:
  - None. Pure client-side refactor. `profiles.display_name` is already
    nullable.

##### PR 2 — `fix(auth): refresh session before authenticated mutations on stale token`

Scope:
  - Add a private helper `BaseRepository._refreshAndRetry<T>(Future<T>
    Function() action)` that wraps a `mapException`-wrapped action and,
    on a `DatabaseException` with `code == '42501'` (or
    `AuthException` with `code == '401'`), calls
    `Supabase.instance.client.auth.refreshSession()` and retries
    exactly once. Second failure → rethrow original.
  - Apply it to: `ProfileRepository.upsertProfile`,
    `ProfileRepository.updateTrainingFrequency`,
    `ProfileRepository.updateWeightUnit`,
    `ProfileRepository.updateLocale`. (Other repositories: separate
    PR — keep this one scoped to the surface where the user has
    reproduced the bug.)
  - Bound: exactly one retry. After the retry, the original error
    propagates with the original stack — no swallowing.
  - Add a breadcrumb `auth.session_refreshed_inline` when the retry
    succeeds (so the Sentry trail tells us "this user dodged a 42501").

Acceptance criteria:
  - On a synthetic stale-token scenario (mock `_auth.currentSession`
    returns a session with `isExpired = true`, mock `refreshSession()`
    succeeds and produces a fresh token, mock the second upsert
    returns the row), `upsertProfile` returns the row without
    surfacing the 42501.
  - On `refreshSession()` failure → original 42501 surfaces with the
    original message (no double-wrap).

Tests required:
  - Unit: `ProfileRepository.upsertProfile` against a `mocktail`
    `SupabaseClient` where the first call throws
    `PostgrestException(code: '42501')` and the second call returns the
    row. Assert: returns row, calls `refreshSession()` exactly once,
    calls upsert exactly twice.
  - Unit: same but second call ALSO throws 42501 → assert: throws
    `DatabaseException(code: '42501')`, calls `refreshSession()`
    exactly once (no infinite retry).
  - Unit: first call throws `PostgrestException(code: '23505')`
    (unique-constraint violation, NOT 42501) → assert: no retry,
    throws immediately.

Migration / data-shape impact:
  - None.

##### PR 3 — `feat(onboarding): typed error handling with retry + re-auth affordance`

Scope:
  - Add a `ProfileNotifier.updateDisplayName(newName)` method that
    mirrors `updateTrainingFrequency` (sets state to `AsyncLoading`,
    awaits upsert, sets state to `AsyncData` of fresh profile, or
    `AsyncError`).
  - Refactor `_finishOnboarding` to:
    1. Set local UI state to "saving".
    2. `await ref.read(profileProvider.notifier).saveOnboardingProfile
       (...)`.
    3. Switch on the resulting `AsyncValue`:
       - `AsyncData` → fire `onboardingCompleted` analytics +
         `context.go('/home')`.
       - `AsyncError(AuthException)` → show "Your session expired" +
         force `signOut` + redirect to `/login`.
       - `AsyncError(NetworkException | TimeoutException)` → show
         "Tap to retry" inline error with a retry button.
       - `AsyncError(DatabaseException)` → show generic copy with a
         retry button + capture to Sentry + fire `onboardingFailed`
         analytics with the AppException category.
  - Refactor `_editName` in `IdentityCard` to call the new
    `ProfileNotifier.updateDisplayName` and surface the same error
    ladder.
  - Add ARB keys: `onboardingErrorSessionExpired`,
    `onboardingErrorNetwork`, `onboardingErrorGeneric`,
    `onboardingRetry` in `app_en.arb` + `app_pt.arb`.
  - Add `AnalyticsEvent.onboardingFailed(errorCategory: String)`.
  - Add a `ForceReauthHelper` in `lib/features/auth/utils/` that
    encapsulates `signOut + go('/login') + toast` so future call sites
    don't have to roll it (closes gap G3).

Acceptance criteria:
  - With `saveOnboardingProfile` mocked to throw `AuthException` →
    user sees "Your session expired" toast, lands on `/login`, signup
    state cleared.
  - With it mocked to throw `NetworkException` → user sees inline
    error WITH retry button, retry calls `saveOnboardingProfile`
    again. No navigation.
  - With it mocked to throw `DatabaseException(code: '42501')` after
    PR 2 lands → upsert auto-retries internally with refreshed token,
    succeeds. (Test covers the integration path.)
  - With it mocked to throw `DatabaseException(code: 'other')` →
    inline error with retry, Sentry capture fires, `onboardingFailed`
    analytics fires with `error_category: 'database'`.
  - With it succeeding → `onboardingCompleted` fires + go('/home').

Tests required:
  - Widget tests covering each branch above. Assertions on the
    rendered text, navigation calls (via a Mock `GoRouter` or
    `pumpAndSettle` + `find.byType(LoginScreen)` after dispatching the
    error), analytics calls (mock `analyticsRepositoryProvider`),
    and Sentry capture (use `SentryReport.debugSetCaptureFn` to
    spy).
  - Same matrix for `IdentityCard._editName`.

Migration / data-shape impact:
  - ARB key additions (en + pt). Analytics event addition (the
    `analytics_events` table accepts free-form JSON `payload`, so no
    SQL migration needed — `AnalyticsEvent.onboardingFailed` just
    serializes the new shape).

##### PR 4 — `chore(deep-links): document Android app-link setup for email confirmation`

Scope (NO IMPLEMENTATION — this is a documentation + checklist PR):
  - Add a section to `docs/PROJECT.md` (Active Backlog or a new
    `docs/auth_deep_links.md` flat doc) listing the steps needed:
    1. Configure hosted Supabase Site URL to an HTTPS URL we own (e.g.
       `https://repsaga.app/auth/v1/verify`).
    2. Add `<intent-filter>` for `https://repsaga.app` scheme with
       `android:autoVerify="true"` to the manifest.
    3. Publish `.well-known/assetlinks.json` on the HTTPS host.
    4. Update Supabase "Additional Redirect URLs" allowlist to include
       both the HTTPS host and the `io.supabase.repsaga://` scheme.
    5. iOS: add `applinks:repsaga.app` to `Runner.entitlements` and a
       corresponding `apple-app-site-association` file.
  - This PR does NOT touch code; it's a runbook + checklist so the
    user can act in the Supabase dashboard + Play / App Store consoles.
  - Mark D8 + D10 as known issues with workaround in the meantime: the
    user can still email-confirm via the browser fallback; PR 2
    handles the resulting refresh-token gap.

Acceptance criteria:
  - `docs/auth_deep_links.md` exists with the runbook.
  - PROJECT.md §2 Active Backlog has a "Email confirmation deep-link
    on Android" entry referencing the runbook.

Tests required:
  - n/a — docs only.

##### PR 5 — `chore(observability): breadcrumb + analytics on profile-write paths`

Scope:
  - Add breadcrumbs at the entry of every authenticated profile-write
    method in `ProfileRepository` (category `profile`, message
    `upsert_attempt` / `update_freq_attempt` / etc.) including
    structured `data: {'user_id_present': bool, 'session_expired':
    bool}` (NO email, NO display name — per the PII policy at
    `sentry_report.dart:77-91`).
  - On a write failure that's already an `AppException`, log a
    breadcrumb `profile.write_failed` with `error_category` and `code`
    fields (these are bounded enum-like values, PII-safe).
  - Add an `onboardingFailed` analytics event call inside the PR 3
    refactor (already listed there); this PR's role is the
    breadcrumb plumbing.

Acceptance criteria:
  - Any 42501 (or any other 4xx/5xx from a profile write) shows up in
    Sentry's breadcrumb trail with `category: 'profile'`.
  - PR 2's `auth.session_refreshed_inline` breadcrumb is observable
    in the same trail.

Tests required:
  - Unit: assertions via `SentryReport.debugSetCaptureFn` that the
    breadcrumb fires on the failure path. (We don't currently
    intercept `addBreadcrumb` for tests — may need a small testing
    surface added to `SentryReport`.)

Migration / data-shape impact:
  - None.

#### 5. Open questions

  - **Q1. Derive vs. add `profiles.onboarded_at`?** Recommendation:
    derive from `display_name` for v1. Defer the column until
    onboarding gains a second required field. (Architectural choice;
    affects PR 1 scope.)
  - **Q2. Splash-vs-flash on profile-loading.** When session arrives
    but profile is still `AsyncLoading`, do we (a) park on `/splash`
    for the ~150-300ms while we resolve, or (b) optimistically render
    `/home` and re-redirect to `/onboarding` on profile arrival?
    Recommendation: (a) — cleaner state machine, single extra splash
    beat that only fires once per cold start.
  - **Q3. PR 2 scope — just `ProfileRepository` or all
    authenticated repositories?** Recommendation: just
    `ProfileRepository` in PR 2; a follow-up sweep PR can apply the
    retry to `WorkoutsRepository`, `RoutinesRepository`, etc. once
    we've validated the pattern lives well in the base.
  - **Q4. Offline-queue the onboarding upsert?** The offline_queue
    today handles workout/PR writes. Adding profile upserts is
    feasible but expands the queue's scope. Recommendation: NO for
    now — onboarding is a one-shot flow with a clear UX expectation
    of "tap, see saved"; queueing it would mean rendering an
    optimistic name + needing rollback on a sync conflict. Out of
    scope for this remediation; if the user-reported case is a
    network blip, the retry button covers it.
  - **Q5. Should `signupPendingEmailProvider` also persist to Hive?**
    Same drift class as D1 (D11) — process restart loses the
    pending-confirmation breadcrumb. Recommendation: small PR after
    PR 1 lands, persist to `userPrefs` Hive box keyed by `signup_
    pending_email`. Out of scope for the 5-PR plan above unless
    orchestrator says go.
  - **Q6. Should the diagnostic `debugPrint` probe in
    `ProfileNotifier.saveOnboardingProfile` (lines 70-86) be removed
    in PR 1 or kept until PR 2 lands?** Recommendation: keep through
    PR 2's merge — the probe is the source of truth for the
    "did PR 2 actually fix it" gate. Remove in PR 5 alongside the
    new breadcrumb plumbing.

#### 6. What this does NOT address

The following are infrastructure / external-system changes that need
the USER to act outside the codebase. They are listed so they're not
forgotten, but no PR in this plan attempts them:

  - **Hosted Supabase Site URL configuration.** The "Site URL" and
    "Additional Redirect URLs" in the hosted dashboard (Authentication
    → URL Configuration) need to be set to an HTTPS URL the email
    template can redirect to, and that HTTPS URL needs to either
    (a) be a web page that re-deep-links into the app, or (b) be
    an Android App Link the device opens directly. PR 4 documents
    the runbook but the user must execute the dashboard change.
  - **Android App Link `assetlinks.json`.** Needs to be published on
    the HTTPS host (e.g.
    `https://repsaga.app/.well-known/assetlinks.json`) with the
    Play-signed SHA-256 of the release certificate. Requires Play
    Console access for the signing-cert fingerprint.
  - **iOS Universal Link `apple-app-site-association`.** Same shape
    on the iOS side once we ship there.
  - **Email template content audit.** The hosted Supabase
    confirmation email template uses
    `{{ .ConfirmationURL }}` — confirming what URL that resolves to
    today (and whether it includes the right `redirect_to=` param
    that points back at our app's intent-filter) requires dashboard
    access.
  - **Production JWT secret rotation policy.** If the hosted JWT
    secret is rotated, sessions signed with the old secret become
    unverifiable — surfacing as a `42501`-look-alike. Not in scope
    for the Dart side; should be documented in PROJECT.md as a
    release-blocker check.

---

### Boundary inventory — PR 1 onboarded_at

Compiled by the Explore agent. Scope: every consumer of
`needsOnboardingProvider`, every constructor / field-access of `Profile`,
every router-redirect timing assertion, every test fixture seeding profile
rows. PR 1 implementation MUST cross-check this list before considering
the change "complete."

#### A. `needsOnboardingProvider` consumers (4 sites)

Provider definition: `lib/features/auth/providers/onboarding_provider.dart:5`
— `StateProvider<bool>` defaulting to `false`.

Write sites (BREAKAGE — both become compile errors after PR 1):
- `lib/features/auth/ui/login_screen.dart:67` — sets `true` on signup success
- `lib/features/auth/ui/onboarding_screen.dart:79` — sets `false` on completion

Read sites (compile-safe after refactor — derived provider keeps `ref.read`/`ref.watch`):
- `lib/core/router/app_router.dart:70` — used in redirect gate
- `lib/core/router/app_router.dart:269` — `_RouterRefreshListenable` listens for re-evaluation

#### B. `Profile` class consumers (47 import sites)

Model definition: `lib/features/profile/models/profile.dart` — `@freezed`
class. Current fields: `id`, `displayName`, `fitnessLevel`, `weightUnit`,
`trainingFrequencyPerWeek`, `locale`, `createdAt`, `bodyweightKg`,
`gender`, `avatarUrl`.

Tier 1 — factory/constructor surfaces that need the new `onboardedAt`:
- `lib/features/profile/models/profile.dart` — add `DateTime? onboardedAt`
  to the @freezed factory.
- `test/fixtures/test_factories.dart:73` — `TestProfileFactory.create()`
  needs an `onboardedAt: String?` param.

Tier 2 — field-access call sites (low risk, scan-only):
- `lib/features/profile/providers/profile_providers.dart`,
  `lib/features/profile/ui/profile_settings_screen.dart`,
  `lib/features/profile/ui/widgets/identity_card.dart`,
  `lib/features/profile/ui/widgets/bodyweight_row.dart` — all destructure
  existing fields; none touch onboarding-state logic.

Tier 3 — Hive cache:
- `lib/core/local_storage/hive_service.dart:67` — `currentCacheSchemaVersion`
  is currently `3`. **BUMP TO `4`** because Profile shape changed. Per
  cluster `jsonb-payload-vs-typed-dart` (nullable on SQL side → nullable
  on Dart side).

Tier 4 — `.copyWith(...)` callers (low risk, but reviewable):
- `lib/features/profile/providers/profile_providers.dart:106,119` — Freezed
  copyWith preserves unspecified fields, so `onboardedAt` survives the
  copy. No code change needed.

#### C. Router redirect timing impact (E2E)

The new "park on `/splash` while `session != null && profileProvider.isLoading`"
gate adds ~150-300ms on cold start. Tests that assert immediate post-login
landing routes need timeout-margin verification:

- `test/e2e/specs/auth.spec.ts:51` — `should land on home screen…` asserts
  `NAV.homeTab` visible. **REVIEW** the timeout margin.
- `test/e2e/specs/onboarding.spec.ts:152-154` — 20s margin already; safe.
- Other specs using `page.goto('/')` post-auth: scan for hard-coded
  synchronous assertions vs `toBeVisible`/`waitForURL` with timeout.
- Widget tests pumping `GoRouter` and asserting `matchedLocation`: scan
  `test/widget/core/router/` (if it exists) for the new
  `profileProvider.isLoading` gate.

#### D. `ProfileNotifier.saveOnboardingProfile` callers

Single caller: `lib/features/auth/ui/onboarding_screen.dart:72-78`
(`_finishOnboarding`). No caller-site changes. The notifier internally
gains `onboardedAt: DateTime.now()` in its upsert payload at
`lib/features/profile/providers/profile_providers.dart:88-94`.

#### E. `ProfileRepository.upsertProfile` signature

Current sig at `lib/features/profile/data/profile_repository.dart:23-33`.
Add nullable param: `DateTime? onboardedAt`. Forward into the upsert map
under key `'onboarded_at'` only if non-null (per omit-on-null discipline
established by Phase 24c `bodyweightKg`, Phase 29 `gender`, Phase 32e
`avatarUrl`). Grep confirms ONE current call site (the notifier).

#### F. Migration ordering

Existing migrations touching `profiles`:
1. `00001_initial_schema.sql` — CREATE TABLE + initial RLS + trigger
2. `00021_input_length_limits.sql` — adds CHECK length constraints
3. `00022_add_locale_to_profiles.sql` — adds `locale` column
4. `00056_add_bodyweight_load_semantics.sql` — adds `bodyweight_kg`
5. `00065_phase29_xp_formula_v2.sql` — adds `gender`

Current highest migration on disk is `00069_avatars_bucket_private_lockdown.sql`
— so new migration is **`00070_add_onboarded_at_to_profiles.sql`**.

Schema:
```sql
ALTER TABLE profiles
  ADD COLUMN onboarded_at timestamptz;

-- Backfill historical: users with a display_name already finished onboarding.
-- Set to created_at as a historical proxy (closest signal we have).
UPDATE profiles
  SET onboarded_at = created_at
  WHERE display_name IS NOT NULL;
```

No CHECK needed. No trigger update. RLS unchanged (existing
`profiles_update_own` policy covers the new column).

#### G. Backfill verification (live DB inspection)

PR 1 agent must run a SELECT before generating the migration to confirm
the live distribution:
```sql
SELECT
  COUNT(*) FILTER (WHERE display_name IS NOT NULL) AS will_backfill,
  COUNT(*) FILTER (WHERE display_name IS NULL)     AS stays_null,
  COUNT(*)                                          AS total
FROM profiles;
```

For our case at hand (`gihfigueiredo_@hotmail.com`) — `display_name IS NULL`,
so they stay `onboarded_at = NULL` post-backfill → next launch routes them
to `/onboarding` (desired behavior).

#### H. Test fixtures (Dart)

`test/fixtures/test_factories.dart:73` — `TestProfileFactory.create()`
gains `String? onboardedAt` with sensible default.

Scan `test/widget/**/*_test.dart` for any test constructing `Profile(...)`
directly (NOT via the factory) — Freezed enforces named args, so they'll
break at the constructor signature. Most likely under
`lib/features/profile/` or `lib/features/auth/` test trees.

#### I. E2E global-setup seeding

`test/e2e/global-setup.ts` `ensureProfile()` (around line 1261) seeds
test users with `display_name` etc. After PR 1, this helper should ALSO
seed `onboarded_at` (otherwise every test user starts as half-onboarded
and lands on `/onboarding`, breaking every spec that assumes the user is
on `/home`). Add `onboarded_at: new Date().toISOString()` to the default
payload, and let callers override if a test specifically needs the
half-onboarded state.

NEW E2E test surface to add: `onboarding-resume.spec.ts` — a test that
deliberately leaves `onboarded_at = NULL` and asserts the user lands on
`/onboarding` after sign-in. Closes the regression-guard gap on D1.

#### J. Cluster references for inline comments

- `provider-init-timing` — when router gains the `profileProvider` listen
- `jsonb-payload-vs-typed-dart` — when adding the nullable `DateTime?` field
- (No existing cluster for "router-splash-park-on-derived-loading"; defer
  the cluster write until we see it twice.)

#### Implementation checklist seed

- [ ] Live SELECT pre-migration to confirm row distribution
- [ ] Append `supabase/migrations/00070_add_onboarded_at_to_profiles.sql`
- [ ] Dart Profile model: add `DateTime? onboardedAt`. Run `make gen`
- [ ] Hive: bump `currentCacheSchemaVersion` 3 → 4 + version-log comment
- [ ] `needsOnboardingProvider`: replace `StateProvider<bool>` with derived
  `Provider<bool>` reading `profileProvider` + `authStateProvider`
- [ ] `app_router.dart`: extend `_RouterRefreshListenable` to listen to
  `profileProvider`. Add `profile.isLoading` to the splash-park gate
- [ ] Strip `needsOnboardingProvider.notifier.state = X` writes from
  `login_screen.dart:67` and `onboarding_screen.dart:79`
- [ ] `ProfileRepository.upsertProfile`: add `DateTime? onboardedAt` param,
  forward as `'onboarded_at'` key when non-null
- [ ] `ProfileNotifier.saveOnboardingProfile`: pass
  `onboardedAt: DateTime.now()` to repo call
- [ ] `TestProfileFactory.create()`: add `String? onboardedAt` with default
- [ ] `test/e2e/global-setup.ts` `ensureProfile`: default
  `onboarded_at: new Date().toISOString()`
- [ ] Unit tests for `needsOnboardingProvider`: null displayName, empty,
  whitespace, "Caio", session=null — exact deterministic outcomes
- [ ] Widget tests for the router gate: pump with mocked session +
  profile combos, assert exact destination route
- [ ] E2E: scan `auth.spec.ts:51` for the splash-margin issue. Add
  `onboarding-resume.spec.ts` for D1 regression
- [ ] `make ci` clean before PR open

---

### PR 1 — onboarded_at refactor — implementation checklist

Branch: `fix/auth-derive-onboarding-from-profile`
Per WIP.md → "Auth → Onboarding → Home flow — architectural audit & remediation plan" → PR 1 + "Boundary inventory — PR 1 onboarded_at".

User-locked design choices: Q1 = add `profiles.onboarded_at` column (NOT
derive-from-`display_name`). Q2 = park on /splash until profile resolves.
**Critical pivot:** the audit's PR 1 spec originally proposed deriving from
`display_name` (see Q1). The user picked the column-anchor path instead;
this checklist follows the column-anchor path.

**Live row distribution (queried 2026-06-03 hosted):**
- `will_backfill = 2` (display_name IS NOT NULL → onboarded_at = created_at)
- `stays_null = 4` (display_name IS NULL → onboarded_at stays NULL → router sends them through /onboarding on next launch)
- `total = 6`

Quote inline in `00072_add_onboarded_at_to_profiles.sql` so the impact at
ship time is readable in `supabase/migrations`.

**Migration number reconciled:** boundary inventory says `00070`. Highest
on disk is `00071_peak_load_primary_only.sql`. New migration is
`00072_add_onboarded_at_to_profiles.sql`.

**PR 2 status:** PR 2 (refresh-retry on 42501) appears to have ALREADY
merged into `main` — `BaseRepository.refreshAndRetry` exists, all four
mutation methods would need wrapping in PR 2's worktree. The two PRs
compose: PR 1 ADDS a parameter to `upsertProfile`; PR 2 WRAPS the call
body. Either order rebases cleanly.

**Test fixture note:** `test/unit/features/profile/data/profile_repository_test.dart`
already includes PR 2's refresh-and-retry test group. PR 1 just adds the
new `onboardedAt`-related upsert payload tests inside the existing
`upsertProfile` group.

#### Checklist

- [ ] Pre-implementation: live SELECT against hosted Supabase (DONE — 2/4/6)
- [ ] `supabase/migrations/00072_add_onboarded_at_to_profiles.sql` with row-count comment
- [ ] `lib/features/profile/models/profile.dart`: add `DateTime? onboardedAt` (cluster `jsonb-payload-vs-typed-dart`)
- [ ] `make gen` for Freezed
- [ ] `lib/core/local_storage/hive_service.dart`: bump `currentCacheSchemaVersion` 3 → 4 + version-log entry
- [ ] Rewrite `lib/features/auth/providers/onboarding_provider.dart`: `StateProvider<bool>` → derived `Provider<bool>` reading `profileProvider` + `authStateProvider` (cluster `provider-init-timing`)
- [ ] `lib/core/router/app_router.dart`: extend `_RouterRefreshListenable` to listen to `profileProvider`; extend `isLoading` gate to ALSO park on `/splash` when `session != null && profileProvider.isLoading` (cluster `provider-init-timing`)
- [ ] Strip `ref.read(needsOnboardingProvider.notifier).state = true` from `lib/features/auth/ui/login_screen.dart:67`
- [ ] Strip `ref.read(needsOnboardingProvider.notifier).state = false` from `lib/features/auth/ui/onboarding_screen.dart:79`
- [ ] `lib/features/profile/data/profile_repository.dart`: add `DateTime? onboardedAt` to `upsertProfile`; forward as `'onboarded_at': onboardedAt.toIso8601String()` only when non-null (omit-on-null discipline)
- [ ] `lib/features/profile/providers/profile_providers.dart`: pass `onboardedAt: DateTime.now()` in `saveOnboardingProfile`'s upsert call (KEEP the `[onboarding-rls-probe]` debugPrint — per user, removed in PR 5)
- [ ] `test/fixtures/test_factories.dart`: `TestProfileFactory.create()` gains `String? onboardedAt` with default `'2026-01-01T00:00:00Z'` (non-null because tests almost always want a fully-onboarded user)
- [ ] Unit test: `needsOnboardingProvider` returns expected values for null/empty session, profile.onboardedAt null, profile.onboardedAt non-null, profile null
- [ ] Unit test: `ProfileRepository.upsertProfile` includes `'onboarded_at'` only when non-null (mirrors `bodyweightKg` / `gender` / `avatarUrl` omit-on-null tests)
- [ ] Widget test: pump `MaterialApp.router(routerConfig: router)` with overrides, assert destination is `OnboardingScreen` for `onboardedAt: null`, `HomeScreen` for non-null, `SplashScreen` while profile loads
- [ ] Widget test: process-restart simulation (dispose + repump with new ProviderContainer, identical routing)
- [ ] `test/e2e/global-setup.ts`: `ensureProfile()` gains `onboarded_at: new Date().toISOString()` default; `smokeOnboarding` user still gets `deleteProfile` (lands on /onboarding)
- [ ] `test/e2e/specs/onboarding-resume.spec.ts`: new spec for D1 regression — user with `onboarded_at = NULL` signs in, lands on /onboarding (NOT /home)
- [ ] `dart format .`
- [ ] `dart analyze --fatal-infos` clean
- [ ] `make ci` clean before PR open
- [ ] PR body includes literal `**QA pass pending — final coverage + E2E run after code review.**`
- [ ] Remove this WIP section after merge

---

### PR 1 — onboarded_at refactor — implementation checklist

Branch: `fix/auth-derive-onboarding-from-profile`

User-locked design choices: Q1 = add `profiles.onboarded_at` column. Q2 =
park on `/splash` until profile resolves.

**Live row distribution (queried 2026-06-03 hosted):** 2 will_backfill / 4
stays_null / 6 total — quoted in the migration's leading comment.

**Migration number reconciled:** boundary inventory said `00070`; highest on
disk is now `00071_peak_load_primary_only.sql` → shipped as
`00072_add_onboarded_at_to_profiles.sql`.

**Inline computation in redirect (deviation from spec):** the audit's PR 1
plan reads `needsOnboardingProvider` inside the redirect. In practice
Riverpod 3's `ref.read` on a `Provider<bool>` can return a stale cached value
when the redirect is fired synchronously from
`_RouterRefreshListenable.notifyListeners()` — the dependent providers have
delivered their new values but the derived Provider's recompute is queued
until the next watcher read. The redirect callback is a one-shot `ref.read`,
so the cached false survives across the auth-+-profile transition window.
Inlining the `profileValue == null || profileValue.onboardedAt == null` check
in the redirect callback is the structural fix — the derived
`needsOnboardingProvider` is kept for downstream consumers but the route
gate computes from the profile shape directly to avoid the timing window.

#### Checklist

- [x] Pre-implementation: live SELECT against hosted Supabase (2/4/6)
- [x] `supabase/migrations/00072_add_onboarded_at_to_profiles.sql` with row-count comment
- [x] `lib/features/profile/models/profile.dart`: add `DateTime? onboardedAt`
- [x] `make gen` for Freezed
- [x] `lib/core/local_storage/hive_service.dart`: bump version 3 → 4 + version-log entry
- [x] Rewrite `lib/features/auth/providers/onboarding_provider.dart`: `StateProvider<bool>` → derived `Provider<bool>`
- [x] `lib/core/router/app_router.dart`: `_RouterRefreshListenable` listens to `profileProvider`; redirect parks on /splash when `profile.isLoading`; needsOnboarding computed inline (see deviation note above)
- [x] Strip `needsOnboardingProvider.notifier.state = true` from `login_screen.dart`
- [x] Strip `needsOnboardingProvider.notifier.state = false` from `onboarding_screen.dart`
- [x] `lib/features/profile/data/profile_repository.dart`: `DateTime? onboardedAt` param, forward as `'onboarded_at'` only when non-null
- [x] `lib/features/profile/providers/profile_providers.dart`: pass `onboardedAt: DateTime.now()` in `saveOnboardingProfile`'s upsert
- [x] `test/fixtures/test_factories.dart`: `TestProfileFactory.create()` gains `String? onboardedAt` (default `'2026-01-01T00:00:00Z'`)
- [x] Unit test: `needsOnboardingProvider` (6 cases — null session, loading, profile-null, onboardedAt-null, onboardedAt-non-null, process-restart)
- [x] Unit test: `ProfileRepository.upsertProfile` — `'onboarded_at'` included when non-null, omitted when null
- [x] Widget test: pump `MaterialApp.router(routerConfig: router)` with overrides, assert destination is /onboarding / /home / /splash for the three core cases
- [x] `test/e2e/global-setup.ts`: `ensureProfile()` defaults `onboarded_at: now()`; all direct profile-upserts (7 sites) carry the same default
- [x] `test/e2e/fixtures/test-users.ts`: new `onboardingResume` user
- [x] `test/e2e/specs/onboarding-resume.spec.ts`: deliberate-NULL test asserts /onboarding landing
- [x] `dart format .`
- [x] `dart analyze --fatal-infos` clean
- [x] `flutter test` — affected areas all green (190 tests, including new 6+4+3)
- [ ] Open PR with `**QA pass pending — final coverage + E2E run after code review.**`
- [ ] Remove this WIP section after merge
