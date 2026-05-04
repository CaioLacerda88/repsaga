# Work In Progress

Active work being done by agents. Each section is removed once the branch is merged.

---

## fix/save-workout-zero-weight-and-orphan-children — IN PROGRESS

**Branch:** `fix/save-workout-zero-weight-and-orphan-children` off main at `2ecc735`

**Source:** Production crash report on Galaxy S25 Ultra. Two queued workouts ("Full Body Beginner" and "5x5 Strength") fail `save_workout` with `exercise_peak_loads_peak_weight_check`, then dependent `PendingUpsertRecords` actions fail with `personal_records_set_id_fkey`.

### Bug A — SQL — `record_session_xp_batch` zero-weight peak

- [x] Read `00040_rpg_system_v1.sql` `record_session_xp_batch` body end-to-end
- [x] Create `supabase/migrations/00050_save_workout_skip_zero_weight_peak.sql` with `CREATE OR REPLACE FUNCTION` — full body, only the `per_set` CTE filter changes (`AND s.weight > 0`)
- [x] Verify the rest of the function body is byte-for-byte identical to the original

### Bug B — Dart — orphan-children gating

- [x] Modify `lib/core/offline/sync_service.dart` `_drain` `liveIds`: include ALL queued action IDs (drop `if (a.retryCount < kMaxSyncRetries)` filter)
- [x] Add inline comment with bug-fix rationale
- [x] Verify `liveIds.remove(action.id)` on success still works (only fires on actual dequeue; terminal parents are skipped before reaching that line)

### Tests

- [x] New `test/integration/save_workout_zero_weight_test.dart`:
  - bodyweight-only workout (Plank ×3, weight=0) → save_workout success, no `exercise_peak_loads` row, 3 `xp_events` rows present with positive `total_xp`, `body_part_progress` advances
  - mixed weighted + bodyweight (Squat 100×5 + Plank ×60) → Squat exercise has peak row at 100kg, Plank does not, both contribute one xp_events row
- [x] Add unit tests in `test/unit/core/offline/sync_service_test.dart`:
  - terminal parent + child `dependsOn=[parent.id]` → child NOT attempted, retryCount unchanged, `lastError` stays null
  - terminal parent dismissed → next drain → child runs and dequeues
- [x] `dart format` + `dart analyze --fatal-infos` clean (0 issues)
- [x] `flutter test` full suite passes (2293 tests, was 2288)
- [x] `npx supabase db reset` applied 00050; integration test 2/2 pass against fresh local DB
- [ ] E2E: full run in progress (212 tests; non-overlapping with the changes — sync gating + SQL function only)

### Bug C — Vitality "untested" display state (peak == 0)

- [x] Add `VitalityState.untested` as new first variant in `lib/features/rpg/models/vitality_state.dart` (compiler-enforced exhaustiveness across consumers)
- [x] `VitalityStateMapper.fromVitality` guard: `peak <= 0 → untested` (preserve `fromPercent` four-state contract — ratio is already in hand on that path)
- [x] `VitalityStateStyles.borderColorFor` / `localizedCopy` switch: `untested → AppColors.textDim` (reuses dormant dim/grey token; heroGold stays radiant-only)
- [x] `vitality_table.dart` ternary: `state == untested ? '—' : '${(pct*100).round()}%'`
- [x] `rune_halo.dart` `_syncControllerToState` + `_buildForState`: untested shares `_DormantHalo` (rune-silent, slow rotation, 12% opacity)
- [x] `character_sheet_state.dart` `haloState` getter: day-0 (no peak observed on any body part) collapses to `untested`
- [x] `stats_deep_dive_state.empty()` factory: six untested rows for the loading-fallback fixture
- [x] L10n: `vitalityCopyUntested` added to en + pt ARBs; gen-l10n regenerated
- [x] PLAN.md §18d.1: appended 2026-05-04 patch line documenting the variant addition
- [x] Tests: 9 new untested-coverage cases across mapper / shim / styles / table / radar / halo / providers; existing 0%-related tests preserved as regression pins
- [x] `dart format` + `dart analyze --fatal-infos` clean (0 issues)
- [x] `flutter test` full suite passes (2297 tests; +4 vs A+B baseline of 2293)

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

