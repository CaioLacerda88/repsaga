# Work In Progress

Active work being done by agents. Each section is removed once the branch is merged.

---

## Phase 20 polish follow-ups — IN PROGRESS

Five deferred follow-ups from PR #152 (Phase 20 — Active Workout Set-Row Redesign). Per Phase 20 PLAN.md "Deferred follow-ups" line, plus the on-disk audit confirming three of the originally-listed items already shipped:

| Code-state audit (already on `main`, despite the stale deferred-list) |
|---|
| ✅ Pillar 1 pre-fill from last session — `active_workout_notifier.dart:319` `addSet(defaultWeight, defaultReps)` |
| ✅ Tap-to-numpad input — `weight_stepper.dart:109` / `reps_stepper.dart:87` `_showNumberInput` |
| ✅ Set-type long-press cycle (function) — `set_row.dart:237` `onLongPress: _cycleSetType` |

### Genuinely pending (this WIP)

| # | Item | Scope | Files |
|---|---|---|---|
| 1 | **Match-indicator state** when current weight×reps match the last session | small | `lib/features/workouts/domain/pr_row_state.dart` (extend enum or add an `isMatchingLast` flag), `set_row.dart` (subtle non-gold visual), widget tests |
| 2 | **Hint persistence** after completion (`_shouldShowHint` returns true even when `isCompleted`) | small | `set_row.dart:149-163`, widget tests |
| 3 | **Set-type long-press discoverability** redesign (icon hint OR replace long-press with tap-to-cycle) | medium | Needs ui-ux-critic input on the affordance pattern BEFORE code |
| 4 | **`Rotinas` → `Treinos` pt-BR rename** + `Sessão` for logged sessions | small | `lib/l10n/app_pt.arb`, e2e selector audit (any `name*="Rotinas"` etc.), Portuguese-localization e2e specs |
| 5 | **Phase 20 validation walkthrough** — stock weighted + bodyweight workouts on the redesigned active workout screen → screenshots → ui-ux-critic with `[ship-now]` / `[redesign-input]` / `[v2-park]` tagging | medium | Running app + ui-ux-critic agent; `[redesign-input]` findings append to `docs/design/2026-05-01-active-workout-redesign/critique.md` |

### Order of execution

User direction is "go ahead with #4, then proceed through 1–5." Order:

1. **#4 (rename)** — cleanest stand-alone change, well-researched (`docs/design/.../naming-treinos-vs-rotinas.md`).
2. **#1 + #2** — bundle, tiny `set_row.dart` changes; same widget test file.
3. **#3 (long-press redesign)** — dispatch ui-ux-critic FIRST for the affordance pattern, then code.
4. **#5 (walkthrough)** — needs running app + screenshots → ui-ux-critic critique pass.

Each item ships as its own PR for independent review/revert. PLAN.md Phase 20 "Deferred follow-ups" line gets trimmed as items land.

### Currently active

- [x] Plan written to WIP
- [x] **#4 — `Rotinas` → `Treinos` rename** (PR #158, merged `27dbdd5`)
- [x] **#1 — match indicator** (PR #159, merged `346660e`)
- [ ] **#2 — hint persistence after completion** — DEFERRED. First attempt re-triggered Phase 20's role-swap bug on standing-PR rows (sibling Text appearing on completion drops the row's `flt-semantics-identifier`). Needs a layout-stable redesign: fixed-height hint slot so adding/removing the Text doesn't reflow the parent Column. See `_shouldShowHint`'s doc + test note in `set_row.dart` / `set_row_test.dart`.
- [ ] **#3 — set-type long-press discoverability redesign** (in progress — ui-ux-critic dispatch next)
- [ ] #5 (queued — manual walkthrough)

---

## Phase 16 — Subscription Monetization — PARKED (2026-04-22)

**Why parked:** Phase 16 keeps hitting external blockers (Brazilian merchant account, Play Console → upload signed AAB required before subscription product can be created, license-tester account setup). Phase 17 gamification is fully internal code work with no external gates and produces the retention moat that makes Phase 16's paywall pitch compelling. Decision: ship Phase 17 (Gamification) before resuming 16b/c/d.

### What's complete in Phase 16

- **16a** (backend): migrations + Edge Functions shipped in PR #93. Vault secrets set. Confirmed working end-to-end after GCP migration (PR #99): Play test notification → Pub/Sub → `rtdn-webhook` returns 200 with new `repsaga-prod` credentials.
- External infrastructure fully rebuilt in `repsaga-prod`: SA, Pub/Sub topic/push-sub, Supabase secrets rotated, Edge Functions redeployed. Old `gymbuddy-app-proj` shut down.

### What's blocked (resume on Phase 17 complete)

- **16b** (client + paywall UI + onboarding rewire): needs `in_app_purchase` package added, models, repo, notifier, `PaywallScreen`, l10n. No external dep; could technically ship without real purchases. **Deferred by choice, not blocker.**
- **Play Console subscription product `repsaga_premium`**: blocked on uploading a signed AAB to Internal Testing. Blocked on generating the upload keystore (`android/keystore/repsaga-release.jks` + `android/key.properties`). Keystore generation is a 10-min chore; the app bundle upload + Play App Signing enrollment is another ~15 min. **Not doing now — pivot to Phase 17.**
- **16c** (hard gate + E2E): depends on 16b.
- **16d** (analytics + merchant-account launch gate): depends on Brazilian merchant account, blocked on 16b/c.

### Resume checklist (when we come back to Phase 16)

- [ ] Generate upload keystore: `keytool -genkey -keystore android/keystore/repsaga-release.jks -alias repsaga-release -keyalg RSA -keysize 2048 -validity 10000`
- [ ] Create `android/key.properties` (not committed) from `android/key.properties.example`
- [ ] Back up keystore + key.properties (1Password attachment, encrypted secondary)
- [ ] `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`
- [ ] Upload AAB to Play Console → RepSaga → Testing → Internal testing → Create release (save as draft, no rollout needed). Enroll in Play App Signing (Google-managed).
- [ ] Create subscription product `repsaga_premium` with 2 base plans (monthly + annual), trial-14d offer, BRL/USD/EUR prices + PPP auto-convert (full spec in PLAN.md Phase 16 → Business Model)
- [ ] Proceed with Phase 16b dev (tech-lead pipeline per CLAUDE.md)

---

## post-rebrand: external service rename cascade (tracking only)

**Why:** PR #98 merged the GymBuddy → RepSaga code rename. Codebase is 100% clean
(zero `gymbuddy`/`GymBuddy` refs post-merge). This section tracks external
services and manual actions that still need renaming outside the repo. Not a
branch — purely a coordination checklist.

### GitHub

- [x] **Rename repo** `gymbuddy-app` → `repsaga` (done; local `origin` updated; old URL auto-redirects)
- [x] **Rename local folder** — Claude Code session now runs in `C:\Users\caiol\Projects\repsaga` (folder + memory dir already migrated)

### Google Cloud Platform

- [x] **Fresh GCP project** `repsaga-prod` created; old `gymbuddy-app-proj` shut down (2026-04-22, see `docs/gcp-project-recreation.md`)
- [x] **Pub/Sub topic** `repsaga-rtdn` created in `repsaga-prod`; Play granted publisher; Play Console RTDN pointed at `projects/repsaga-prod/topics/repsaga-rtdn`
- [x] **Pub/Sub push subscription** `repsaga-rtdn-push` → `rtdn-webhook` Edge Function (OIDC-authed, test notification returns 200)

### Supabase

- [ ] **Project display name** — Dashboard → Project Settings → General → rename to "RepSaga"
- [ ] **Auth redirect URLs allowlist** — Dashboard → Authentication → URL Configuration → add `io.supabase.repsaga://login-callback/` **when Google Sign-In is enabled** (Phase 16b+). Not blocking today since only email/password auth is wired.
- [x] **Edge Function secrets** — `GOOGLE_PLAY_PACKAGE_NAME=com.repsaga.app`, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (new `repsaga-prod` SA), `RTDN_PUBSUB_AUDIENCE` all set; Edge Functions redeployed (2026-04-22)

### Google Play Console (blocked → now unblocked)

- [x] **Create app** with package `com.repsaga.app` — unblocks Phase 16a Stages 1.3, 3.4, 4, 5.3
- [ ] **Create subscription product** `repsaga_premium` (code + test fixtures already expect this ID)
- [x] **Link service account** — `repsaga-play-api@repsaga-prod.iam.gserviceaccount.com` invited via Users and permissions (new flow; old API-access page deprecated by Google ~2024)
- [x] **Point Play at Pub/Sub topic** — `projects/repsaga-prod/topics/repsaga-rtdn`; test notification verified end-to-end (Play → Pub/Sub → `rtdn-webhook` 200)

### Brand assets

- [ ] **Domains** — register `repsaga.com`, `repsaga.app`, `repsaga.com.br`
- [ ] **Social handles** — lock `@repsaga` on Instagram, X/Twitter, TikTok

### Local development environment

- [x] **IntelliJ/Android Studio** — stale `.iml` files + `.idea/modules.xml` deleted; IDE will regenerate with `repsaga` names on next open
- [x] **Claude Code memory dir** — migrated to `C--Users-caiol-Projects-repsaga\memory\`; MEMORY.md index loads correctly this session

### Not renameable (stuck forever — fine)

- Supabase project ref `dgcueqvqfyuedclkxixz` — internal ID, appears in `.env` as part of the Supabase URL
- Android keystore signing certificate (cryptographic; key alias is internal-only)
- Git commit history (correct historical record)

### Acceptance

All checklist items above completed. Phase 16a external setup can proceed with `com.repsaga.app` everywhere.

### Architectural follow-ups (parked, not blocking Phase 20)

- **Cold-launch orphan drain** — `SyncService` doesn't auto-drain pre-existing queue items when the app boots already-online. Improvement: gate the drain on `onlineStatusProvider`'s first real `AsyncData` emission (not the optimistic-default true). Worth fixing when a user reports a stuck queue badge after fresh launch.
- **Two unpatched legacy `exercise_peak_loads` writers** (`_rpg_backfill_chunk` line 263, `record_set_xp` line 1656) still emit unguarded INSERTs. Migration 00051's BEFORE-INSERT trigger silently absorbs them. Optional cleanup migration could add explicit `IF weight > 0` guards at the writer site for code-review explicitness.
- **Wire Deno tests into CI** — `supabase/functions/**/*.test.ts` files exist (notably `vitality-nightly/auth.test.ts` from PR #151) but no workflow runs them. A small CI step would catch Edge Function regressions.
