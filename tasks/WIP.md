# Work In Progress

Active work being done by agents. Each section is removed once the branch is merged.

---

## Phase 20 — Active Workout Set-Row Redesign — STARTING

**Branch:** `feature/phase20-active-workout-redesign` (off main at `dc1886c`)
**Status:** Spec locked + PLAN.md entry drafted. Awaiting orchestrator sign-off before commit 1.

**Per PLAN.md Phase 20:** Direction B (Tactile Data Table) chosen, with the gold-edge-frame PR treatment + standing/superseded/predicted PR semantic locked. Source brief in `docs/design/2026-05-01-active-workout-redesign/`. Reference mockup: `direction-b-pr-refined.html` (v3 post-critique). Closes BUG-018 / BUG-019 / BUG-020.

### Commit plan (split for reviewability, single PR)

- [ ] **Commit 1:** `refactor(stepper): full-column tap zones, drop 32dp min-width (BUG-019)` — `lib/shared/widgets/weight_stepper.dart` only. Stepper geometry change in isolation.
- [ ] **Commit 2:** `refactor(workouts): set-row layout + tap-target sizing (BUG-018)` — `set_row.dart` rewritten to Direction B layout (left rune-stripe, full-column stepper zones, ≥48dp set-num cell, 56dp uniform row height). No PR styling yet.
- [ ] **Commit 3:** `feat(rpg): pr detection — standing vs superseded resolver` — pure-domain extension to `pr_detection_service.dart` (or new resolver class). Fully unit-tested before UI consumes it.
- [ ] **Commit 4:** `feat(workouts): set-row PR treatment — gold edge frame + supersession state` — wire resolver into `set_row.dart`, render the 5-state matrix per the locked spec.
- [ ] **Commit 5:** `feat(workouts): finish button bottom anchor for one-handed reach (BUG-020)` — `active_workout_screen.dart`. Hevy-style sticky bottom bar.
- [ ] **Commit 6:** `test(workouts): widget + unit coverage for 5-state row matrix + supersession transitions` — golden tests for row alignment, widget tests per state, unit tests for the resolver.
- [ ] **Commit 7:** `test(e2e): selectors + smoke cases for gold edge frame` — `selectors.ts` + `personal-records.spec.ts` additions.

### Files to touch (per file plan in PLAN.md Phase 20)

- `lib/features/workouts/ui/widgets/set_row.dart` (rewrite)
- `lib/shared/widgets/weight_stepper.dart` (geometry refactor)
- `lib/features/workouts/ui/active_workout_screen.dart` (finish button anchor)
- `lib/features/personal_records/domain/pr_detection_service.dart` (standing/superseded resolver)
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` (wire resolver)
- `lib/l10n/app_en.arb` + `app_pt.arb` (a11y labels for new states)
- `test/widget/features/workouts/widgets/set_row_test.dart` (5-state matrix)
- `test/unit/features/personal_records/domain/pr_detection_service_test.dart` (resolver)
- `test/e2e/specs/personal-records.spec.ts` + `test/e2e/helpers/selectors.ts`
- (possibly new) `lib/features/workouts/domain/pr_row_state.dart` enum/sealed class

### Post-merge

- [ ] Validation walkthrough on the redesigned screen — stock weighted + bodyweight workouts, screenshots, ui-ux-critic review with `[ship-now]` / `[redesign-input]` / `[v2-park]` tagging. Append `[redesign-input]` findings to `docs/design/2026-05-01-active-workout-redesign/critique.md` for follow-up phases.
- [ ] Condense Phase 20 entry in PLAN.md per lifecycle rule (3-5 bullet summary, full spec moves to git history).

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
