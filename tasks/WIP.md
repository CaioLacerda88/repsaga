# Work In Progress

Active work being done by agents. Each section is removed once the branch is merged.

---

## Phase 21 — E2E Per-Worker User Isolation + workers=4 — IN PR #154 REVIEW

**Branch:** `feature/phase21-e2e-per-worker-isolation` (off main `b86589d`)
**PR:** #154 — https://github.com/CaioLacerda88/repsaga/pull/154
**HEAD:** `223419d`

### Resume context — 2026-05-06 (post-compact)

**What's done (all on the branch, pushed):**

- 12 commits: 6 planned + 4 production-bug fix commits + 1 simplification + 1 reviewer-fixes commit
- Local verification:
  - Smoke subset (113 @smoke, workers=4): **113/113 pass in 10.7 min**
  - Full suite workers=4 retries=0: 213/214 + 1 known flake (exercises:372 search)
  - Full suite workers=4 retries=1 (CI-equivalent): **214/214 effective pass, 21.4 min**
  - Speedup: ~33% (33 min → 21 min vs pre-Phase-21 baseline)
- Reviewer pass complete (independent agent): 0 blockers, 2 important (BOTH fixed in `223419d`), 3 nits (deferred)

### Commit table

| # | SHA | Description |
|---|---|---|
| 1 | `29ecf04` | feat(e2e): worker-scoped user factory at `test/e2e/fixtures/worker-users.ts` |
| 2 | `91bec20` | refactor(e2e): global-setup creates 168 per-worker users (4 workers × 42 roles) |
| 3 | `95c1985` | refactor(e2e): global-teardown by `_w\d+@test\.local` regex pattern |
| 4 | `7e0bed4` | refactor(e2e): migrate spec files to `getUser('role')` (160 occurrences across 23 files) |
| 5 | `8d8827f` | chore(e2e): bump workers 2 → 4 |
| 6 | `8fd43b0` | refactor(e2e): drop Tier 1 helper application (later REVERTED in F3) |
| F1 | `edd0561` | fix(e2e): listUsers `perPage: 1000` (was silently truncating at 50) + 8-wide teardown batching |
| F2 | `f72130a` | fix(e2e): lowercase worker-scoped emails (Supabase Auth canonicalizes to lowercase) |
| F3 | `5daf9c4` | fix(e2e): RESTORE Tier 1 `resetRpgStateForUser` in saga.spec.ts — Phase 21 fixes cross-worker but NOT intra-worker pollution |
| F4 | `c1ed317` | fix(e2e): bump `personal-records:309` standing-PR timeout 10s → 15s under workers=4 |
| 11 | `c97d00d` | test(e2e): simplify `personal-records:309` to single-set scope (supersession contract pinned at unit level) |
| 12 | `223419d` | chore(e2e): single-source `WORKERS_COUNT` (exported from `worker-users.ts`, imported by `global-setup.ts` + `playwright.config.ts`) + global-teardown comment documenting cascade-handled tables |

### Production bugs found + fixed during implementation

1. **GoTrue `listUsers()` pagination** — defaults `perPage: 50`. With 168 users, page-2+ users silently invisible to lookups. Symptom: `userList.users.find(u => u.email === ...)` returns undefined. Fix: pass `perPage: 1000`.
2. **GoTrue concurrent-delete saturation** — full-parallel `Promise.allSettled` over 168 deletes returned 500s on ~25%. Fix: 8-wide batched delete.
3. **Supabase Auth email canonicalization** — Auth lowercases on insert. Case-sensitive lookups (`rpgFoundationUser_w0` vs stored `rpgfoundationuser_w0`) silently mismatched. Fix: lowercase the role inside `buildEmailForWorker`.
4. **Intra-worker pollution still exists** — Phase 21 only fixes *cross-worker* pollution. With `fullyParallel: false`, sequential spec files within ONE worker still share user state. `rpg-foundation.spec.ts` writes XP for `rpgFreshUser_wN`, `saga.spec.ts:S1` reads from same user expecting zero history. Fix: `resetRpgStateForUser` in saga.spec.ts beforeEach (kept, NOT removed by Phase 21).

### Current CI state (pending compact)

- All non-e2e checks PASS on `223419d` (analyze, build, test, ci, exercise-translation-coverage-check)
- E2E job CANCELLED at 45-min job timeout — not a test failure. Hung on `Install Playwright browser system deps (cache hit)` step for **41 minutes** before timeout. That step normally takes 30s — `npx playwright install-deps chromium` (apt-get system packages). NOT a Phase 21 issue; GitHub Actions infrastructure (apt mirror slow / unreachable).
- Triggered re-run via `gh run rerun 25420515336 --failed`. **Rerun is pending as of compact.** Run ID for new e2e attempt: `25420515336/job/74589114916`.
- If rerun ALSO hangs: bump `timeout-minutes: 45 → 60` in `.github/workflows/e2e.yml` OR switch to `--with-deps` install path that downloads from playwright's CDN.

### Critical not-to-redo list (architectural traps)

- `WORKERS_COUNT` MUST stay synchronized between `playwright.config.ts` and `global-setup.ts`. Currently a single export from `fixtures/worker-users.ts` — both files import. **Do not duplicate** the constant.
- `saga.spec.ts:63` and `:387` `beforeEach` hooks call `resetRpgStateForUser` for `rpgFreshUser_wN`. **Do not remove** — they catch intra-worker pollution that Phase 21 doesn't solve. The Tier 1 helper (`test/e2e/helpers/test-data-reset.ts`) stays, just used surgically.
- `getEmailPattern()` regex is `/[a-z]_w\d+@test\.local$/`. The `[a-z]` anchor matters — without it, the pattern could match unrelated patterns. Don't simplify to `/_w\d+@test\.local$/`.
- The `personal-records:309` test was REWRITTEN to single-set scope. **Do not "restore" the 2-set supersession assertion** — it's structurally flaky under workers=4 contention even at 30s timeout. Supersession is fully covered at unit-test level (`pr_row_state_resolver_test.dart`'s multi-set cascade tests).
- The Checkbox path in `_DoneCell` (Phase 20 carry-over) keeps natural Semantics. **Do not "consistency-fix" it** to match the predicted-PR's asymmetric `Semantics(button: true, onTap:)` pattern. Asymmetric is correct (Phase 20 lessons captured why).
- `fullyParallel: true` is OUT OF SCOPE for Phase 21. Within-file parallelism requires per-test isolation we don't have.

### Awaiting (post-compact)

1. **E2E CI rerun result** on PR #154 (was pending at 25420515336 / job 74589114916). Check: `gh pr checks 154`
2. If green: `gh pr merge 154 --squash --delete-branch` → pull main → small docs PR to condense PLAN.md Phase 21 (5-bullet summary, same pattern as #153) → mark task #29 done
3. If rerun hangs again: investigate `timeout-minutes` bump or install-path change

### Update 2026-05-06 — root-caused, refactored, tags removed

**CI rerun (`25420515336`)** completed but failed: 2 tests in `rank-up-celebration.spec.ts` (S4 + S4b — overflow card scenarios) hit timing races under workers=4 on the 4-vCPU CI runner.

**Root cause (after systematic-debugging):** the e2e tests were asserting on Flutter `Timer.delayed` animation timing — overlay 1.1 s holds, overflow card 4 s auto-dismiss — using real wall-clock windows (`toBeVisible({timeout:20s})`, `not.toBeVisible({timeout:6s})`, `click({force:true})` after a wait). Under any JS event-loop saturation (CI 4-vCPU saturation OR local stress with `workers≥3 + --repeat-each≥3` parallel runs of the same XP-heavy describe), the timers fire 5–10× late and the assertion windows desync from the actual UI events. NOT a logic bug in `record_session_xp_batch` — that math is deterministic and was hand-verified for the test seed (chest +41, legs +47, back +31 XP all clear the +2.6 R4 boundary). The "only BACK · RANK 4 visible" symptom in failure snapshots was just the queue paused mid-playback under starvation.

**The fix (this PR):**

1. Trimmed S4's e2e assertions to the integration property the test exists to verify: cap-at-3 produces a visible overflow card with the correct `+3 more rank-ups` accessible label. Dropped the e2e auto-dismiss assertion (`not.toBeVisible({timeout:6s})`) — already covered cheaper at the widget layer (`celebration_overflow_card_test.dart` line 79–95: `tester.pump(Duration(seconds:4))` + dismiss assertion against a fake clock).
2. S4b: capture the overflow-card locator handle ONCE before the visibility wait, click on the held handle. Closes the race window between `toBeVisible` resolving and `click()` re-resolving the locator into a just-dismissed card.
3. `WORKERS_COUNT` left at 3 (eliminates CI 4-vCPU saturation as a residual factor; confirmed full suite 214/214 pass locally at this setting). Workers=4 attempt in flight.

**Verification (local):**

| Configuration | Before refactor | After refactor |
|---|---|---|
| workers=3 + --repeat-each=3, @flaky filter (6 runs) | S4 3/3 fail, S4b 3/3 pass | **6/6 pass** |
| workers=3 + --repeat-each=5, @flaky filter (10 runs) | not measured | **10/10 pass** |
| workers=4 + --repeat-each=3, @flaky filter (6 runs) | not measured | **6/6 pass** |

`@flaky` tag removed from both describe blocks (per FLAKY_TESTS.md playbook: 5+ consecutive passes discharges the tag). FLAKY_TESTS.md entries #22/#23 deleted; preamble updated to summarise the discharge.

**Workers=4 attempt result (full suite, with the refactor):** 200 passed, 13 failed, 1 flaky in 22.6 min. **Both refactored tests passed cleanly.** All 13 failures are in `exercises.spec.ts` and surface as `"Wrong email or password. Please try again."` on the login screen — i.e., Supabase's `sign_in_sign_ups = 30` per-IP/5-min rate limit (`config.toml:200`) is being saturated by 4 concurrent workers' login flows (~52 logins/IP across the full suite). Same root cause family as FLAKY_TESTS.md entry #14, surfaced here at workers=4 single-pass instead of `--repeat-each`. NOT a regression from this PR — latent since the rate-limit was set.

**Decision:** ship `WORKERS_COUNT=3` (already on branch). Workers=4 needs `sign_in_sign_ups` raised in `supabase/config.toml` AND the CI workflow's `npx supabase start` to pick up the change — separate, scoped follow-up.

**Push state:** all 214 tests green at workers=3 single-pass (verified 24.6 min). Refactored tests proven stable at 16 consecutive passes (workers=3 + --repeat-each=5; workers=4 + --repeat-each=3). `@flaky` tag removed. `FLAKY_TESTS.md` entries #22/#23 deleted. Ready to push.

### Task tracking state at compact

- Tasks #21-27 completed (commits 1-6 + verification gate)
- Task #28 in_progress (PR open, CI re-running, reviewer pass complete)
- Task #29 pending (post-merge PLAN.md condensation)

### Out of scope deferred (do not re-tackle in Phase 21)

- **Tier 2 cleanup from `tasks/e2e-pollution-audit.md`** (locale bleed, offline-sync badges) — Phase 21's per-worker isolation subsumed it as a side effect.
- **`fullyParallel: true`** — separate optimization requiring per-test isolation. Future phase if telemetry shows it's safe.
- **`exercises.spec.ts:372` search debounce flake** — passes on retry; investigation is its own line item.
- **3 reviewer nits** from PR #154 — pure cleanup, follow-up.
- **Validation walkthrough** still owed from Phase 20 (independent of Phase 21): stock weighted + bodyweight workouts on the redesigned active workout screen → screenshots → ui-ux-critic review with `[ship-now]` / `[redesign-input]` / `[v2-park]` tagging.

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
