# RepSaga — Master Plan

## Quick Reference

Gym training app for logging workouts, tracking personal records, and managing exercises. Flutter + Supabase + Riverpod. Android-first, iOS deferred. Dark bold theme, gym-floor UX (one-handed, glanceable, sweat-proof).

**Market context:** $12B+ fitness app market, 70% abandoned within 90 days. Core differentiator: RPG gamification tightly coupled to real training data (see Phase 17-18). Brazilian fitness market $1.32B — pt-BR localization in Phase 15. Monetization: trial-to-paywall subscription via Google Play Billing (Phase 16).

### Progress

| Step/Phase | Name | Status | PR(s) |
|------------|------|--------|-------|
| 1 | Project Setup & CI | DONE | #1 |
| 2 | Database Schema & Seed | DONE | #2 |
| 3 | Auth & Onboarding | DONE | #3-#5 |
| 3b | Auth UX Polish | DONE | #6 |
| 4 | Exercise Library + Images | DONE | #7-#10 |
| 5 | Workout Logging (5a-5d) | DONE | #11-#15 |
| 5e | UX Polish Sprint | DONE | #16-#18 |
| 6 | Routines | DONE | #19 |
| 7 | Personal Records | DONE | #20 |
| 8 | Home Polish & PR Integration | DONE | #21 |
| 9 | E2E Testing & CI/CD | DONE | #22-#23 |
| 9d | Final QA Pass | DONE | #24 |
| 10 | UX Improvements & Security | DONE | #25-#26 |
| 11 | Exercise Content, Smart Defaults, Home Simplification | DONE | #27-#30 |
| 12 | Weekly Training Plan (Bucket Model) | DONE | #32 |
| 12.1 | E2E Infrastructure: Parallelism, Teardown, Data Seeding | DONE | #35 |
| 12.2a | Bug Fixes (7 UX bugs) | DONE | #36 |
| 12.2b | Home Screen Redesign | DONE | #37 |
| 12.2c | Plan Management UX Polish | DONE | #38 |
| 12.3a | P0 Bug Fixes (back nav, home flicker) | DONE | #39 |
| 12.3b | Copy Fix + Content Expansion (exercises, routines) | DONE | #40 |
| 12.3c | Standalone Routine → Plan Prompt | DONE | #41 |
| 13a-PR1 | Account Deletion + Volume Unit + OAuth Deep Link | DONE | #42 |
| 13a-PR2 | Release Signing + Branding + Privacy Policy & ToS (icon DEFERRED) | DONE | #43 |
| 13a-PR3 | Sprint A QA follow-ups (legal polish, PWA theme, test coverage, live delete E2E) | DONE | #44 |
| 13a-PR5 | Observability: Sentry crash reporting + first-party analytics_events (B2 + B3) | DONE | #46 |
| 13a-PR6 | Bulk Dependency Upgrade + Toolchain Refresh (Riverpod 3, GoRouter 17, Freezed 3) | DONE | #49 |
| 13a-PR7 | Close local CI Android build gap (`make ci` runs `flutter build apk --debug`) | DONE | #47 |
| 13a-PR8 | E2E overhaul: Flutter 3.41.6 AOM selectors, bug fixes, restructure to feature files | DONE | #50 |
| 13-QA1 | QA Monkey Testing: Exercise Filter Performance (autoDispose, invalidation, rebuild fix) | DONE | #74 |
| 13-QA2 | QA Monkey Testing: Active Workout Stability (crash guards, timer fixes, cancel safety) | DONE | #75 |
| 13-QA3 | QA Monkey Testing: Minor Polish (wall-clock timer, nav guards, list virtualization) | DONE | #76 |
| 13 | Launch — last phase before Play Store (all sprints + QA DONE; verification gates open) | IN PROGRESS | - |
| 14a | Connectivity + Read-Through Cache Foundation | DONE | #78, #79 |
| 14b | Offline Workout Capture + Queue | DONE | #81 |
| 14c | Sync Service + Backoff + Observability | DONE | #83 |
| 14d | Local PR Detection + Reconciliation | DONE | #84 |
| 14e | Polish + Edge Cases | DONE | #85 |
| 14 | Offline Support | DONE | #78-#85 |
| 15a | i18n Infrastructure + E2E Selector Migration | DONE | #86 |
| 15b | Full String Extraction | DONE | #87 |
| 15c | Portuguese Translations + Exercise Content | DONE | #88 |
| 15d | Language Picker UI + Persistence | DONE | #89 |
| 15e | QA + E2E + Overflow Polish | DONE | #91 |
| 15f | Exercise Content Localization (DB-side translations + slug) | DONE | #110 |
| 15 | Portuguese (Brazil) Localization | DONE | #86–#91, #110 |
| 16 | Subscription Monetization (GPB + trial-to-paywall) | PARKED | #93, #99 |
| 16a | Backend: schema + Edge Functions + Play Console draft | DONE | #93 |
| 16b | Client integration + paywall UI + onboarding rewire | DEFERRED | - |
| 16c | Hard gate enforcement + router guard + E2E refactor | DEFERRED | - |
| 16d | Analytics + hardening + launch-readiness checklist | DEFERRED | - |
| 17.0 | Visual Language Foundation (pixel-art — SUPERSEDED by 17.0c) | SUPERSEDED | #101 |
| 17.0c | Arcane Ascent Material Migration (teardown pixel, rebuild Material Design + app icon + 17.0d polish) | DONE | #105, #106, #107 |
| 17.0e | Icon Pack Integration (migrate inline SVGs → v3-silhouette asset pack, CC BY 3.0 attribution) | DONE | #108 |
| 17b | XP & Level System + Retroactive Backfill (placeholder XP math — rebased by Phase 18a) | DONE | #103 |
| 17a | Celebration Overlay + Active Logger Hardening (overlay choreography rebased into 18c) | SUPERSEDED | - |
| 17c | Weekly Streak + Comeback Bonus | SUPERSEDED | - |
| 17d | Character Sheet + Milestone Signal (re-scoped into 18b character sheet + 18d stats deep-dive) | SUPERSEDED | - |
| 17e | Home Recap + First-Week Quest + LVL Line | SUPERSEDED | - |
| 17 | Gamification Foundation (visual + XP infra shipped; remaining sub-phases SUPERSEDED by Phase 18 RPG v1) | PARTIAL | #101, #103, #105, #106, #107, #108 |
| 18a | RPG v1: Schema + XP engine + backfill (foundation) | DONE | #112 |
| 18b | RPG v1: Character sheet + rune sigils UI | DONE | #113 |
| 18c | RPG v1: Mid-workout overlay rewire + title unlocks | DONE | #114 |
| 18d | RPG v1: Stats deep-dive + Vitality nightly job + visual states | DONE | #118, #119 |
| 18e | RPG v1: Class system + cross-build titles + final QA pass | DONE | #120 |
| 18 | RPG System v1 (per `docs/superpowers/specs/2026-04-25-rpg-system-v1-design.md`) | DONE | #112–#120 |
| 18.5 | Multi-Agent Audit Cycle (8 clusters, 41 numbered findings; only deferred: BUG-017) | DONE | #124, #127, #128, #129, #130, #132, #134, #136, #138, #140, #142, #144 |
| 20 | Active Workout Set-Row Redesign (Direction B + standing-PR semantic; closes BUG-018/019/020) | DONE | #152 |
| 21 | E2E per-worker user isolation + parallelism bump (CI ~32min → ~21min, workers 2→4) | DONE | #154, #156, #157 |
| Backlog | Active backlog (Phase 20 polish carry-overs, architectural follow-ups, post-rebrand, Phase 16 parked status) | BACKLOG | see "## Active Backlog" section |
| 19 | Deferred RPG v2 + Nice-to-Have (Quests engine, Stats radar, Synergy, PR mini-events, Cardio track, etc.) | BACKLOG | - |

### Section Index

Read only what you need:

| Section | When to read |
|---------|-------------|
| Tech Stack & Architecture | Building any code |
| Completed Steps (1-11) | Need context on what already exists |
| Step 12: Weekly Training Plan | Implementing Step 12 |
| Step 12.2: Home Redesign + Bug Fixes | Implementing Step 12.2 |
| Step 12.3: UX Polish & Content Expansion | Implementing Step 12.3 |
| Phase 13: Launch | Final work before Play Store submission |
| Phase 14: Offline Support | Implementing offline-first workout capture |
| Phase 15: Localization | Implementing pt-BR support |
| Phase 16: Subscription Monetization | Implementing GPB subscriptions / paywall |
| Phase 17: Gamification Foundation (visual + XP infra; remaining sub-phases superseded) | Context on shipped 17.0c / 17b infrastructure |
| Phase 18: RPG System v1 | Implementing the canonical RPG (rank, vitality, character sheet, classes, titles) — read with `docs/superpowers/specs/2026-04-25-rpg-system-v1-design.md` |
| Phase 19: Deferred RPG v2 + Nice-to-Have | Cardio track, quests engine, synergy multipliers, etc. |
| QA Status | Doing QA or review |
| Verification & Testing | Writing tests |
| UX Design Direction | Building UI |

---

## Tech Stack & Architecture

- **Frontend:** Flutter (Android-first), SDK `^3.11.4`
- **Backend:** Supabase (Postgres, Auth, Storage)
- **Auth:** Supabase Auth — email/password + Google, `AuthFlowType.pkce`
- **State:** Riverpod `^3.3.1` (AsyncNotifier pattern)
- **Local:** Hive (active workout cache, offline queue)
- **Models:** Freezed `^3.0.0` + json_serializable
- **Theme:** Dark & bold, Material 3

### Architecture Decisions

- **Repository pattern**: All Supabase access through repository classes. No `supabase.from()` in providers/UI.
- **Feature isolation**: `lib/features/<feature>/{data,models,providers,ui}/`. No cross-feature imports.
- **Sealed exceptions**: All errors mapped to `AppException` subtypes in repository layer.
- **Offline strategy**: Server is source of truth. Active workouts use Hive with sync-on-save. Last-write-wins.
- **Atomic saves**: `save_workout` Postgres RPC — single transaction, no partial data.
- **Weight units**: Stored in user's chosen unit (kg/lbs). `weight_unit` in profile.
- **Hive boxes**: `active_workout`, `offline_queue`, `user_prefs`. Schema versioned.

### Route Tree (GoRouter)

```
/splash, /login, /onboarding, /email-confirmation  (no shell)
/workout/active                                      (no shell, full-screen)
ShellRoute:
  /home, /home/history, /home/history/:workoutId
  /exercises, /exercises/:id
  /routines, /routines/create, /routines/:id/edit
  /records
  /profile, /profile/manage-data
  /plan/week
```

### Database Schema

**Tables:** `profiles`, `exercises`, `workouts`, `workout_exercises`, `sets`, `personal_records`, `workout_templates`, `weekly_plans`

Key columns and relationships — read migration files in `supabase/migrations/` for full DDL.

- **profiles** — `id (FK auth.users)`, `username`, `display_name`, `avatar_url`, `fitness_level`, `weight_unit` (kg/lbs), `training_frequency_per_week` (2-6)
- **exercises** — `id`, `name`, `muscle_group` (enum), `equipment_type` (enum), `description`, `form_tips`, `image_start_url`, `image_end_url`, `is_default`, `user_id`, `deleted_at` (soft delete)
- **workouts** — `id`, `user_id`, `name`, `started_at`, `finished_at`, `duration_seconds`, `is_active`, `notes`
- **workout_exercises** — `id`, `workout_id`, `exercise_id`, `order`, `rest_seconds`
- **sets** — `id`, `workout_exercise_id`, `set_number`, `reps`, `weight`, `rpe`, `set_type` (working/warmup/dropset/failure), `is_completed`
- **personal_records** — `id`, `user_id`, `exercise_id`, `record_type` (max_weight/max_reps/max_volume), `value`, `reps`, `achieved_at`, `set_id`
- **workout_templates** — `id`, `user_id`, `name`, `is_default`, `exercises` (JSONB)
- **weekly_plans** — `id`, `user_id`, `week_start` (Monday), `routines` (JSONB), `UNIQUE(user_id, week_start)`

**RLS:** All user data scoped by `user_id = auth.uid()`. Default exercises/templates readable by all.

### Project Structure

```
lib/
  main.dart, app.dart
  core/          theme/, router/, data/, constants/, exceptions/, local_storage/, utils/
  features/
    auth/        data/, providers/, ui/
    exercises/   data/, models/, providers/, ui/
    workouts/    data/, models/, providers/, ui/
    personal_records/  data/, models/, domain/, providers/, ui/
    routines/    data/, models/, providers/, ui/
    profile/     data/, models/, providers/, ui/
    weekly_plan/ data/, models/, providers/, ui/
  shared/widgets/

supabase/migrations/  (00001-00011)
test/  unit/, widget/, e2e/, fixtures/
```

---

## Completed Steps (1-11)

> Condensed summaries. Full specs in git history (PR branches).

### Step 1: Project Setup & CI (PR #1)
- Flutter project scaffold, dependencies pinned, Supabase init with PKCE
- Core infrastructure: `BaseRepository`, sealed `AppException`, GoRouter skeleton, Hive service
- Shared widgets: `AsyncValueBuilder`, `ErrorOverlay`, `ThemedButton`, `FormInput`
- Dark bold theme, Makefile targets, strict `analysis_options.yaml`
- CI pipeline: format + analyze + build_runner + test

### Step 2: Database Schema & Seed (PR #2)
- Initial migration: all tables, enums, indexes, RLS policies
- Seed: ~60 default exercises, 4 starter templates (Push/Pull/Legs, Upper/Lower, Full Body)
- RLS integration tests for user isolation

### Step 3: Auth & Onboarding (PRs #3-#5)
- Supabase Auth with Google + email/password, PKCE redirect
- Auth state provider (AsyncNotifier watching `onAuthStateChange`)
- Router redirect: unauthenticated -> login, authenticated -> home
- Screens: Splash, Login/Signup, Onboarding (2 pages: welcome + profile setup)
- Profile created on first login

### Step 3b: Auth UX Polish (PR #6)
- Post-signup email confirmation screen with resend
- User-friendly auth error messages, loading states
- Custom Supabase email templates (RepSaga-branded)

### Step 4: Exercise Library + Images (PRs #7-#10)
- Exercise model (Freezed), repository with CRUD + filters
- Exercise list: muscle group category buttons, search, equipment filter, empty states
- Exercise picker (shared contract for workout flow)
- Custom exercise creation with duplicate name validation, soft delete
- Exercise images: `cached_network_image`, start/end positions, fullscreen overlay
- Images hosted on GitHub (404 issue — see QA-005, deferred to Phase 13)

### Step 5: Workout Logging (PRs #11-#15)
- `ActiveWorkoutNotifier` (AsyncNotifier) as core state machine
- Hive persistence with schema versioning, atomic save via `save_workout` RPC
- Sub-steps: data layer (5a), active workout screen (5b), rest timer + polish (5c), finish flow + history (5d)
- WeightStepper/RepsStepper with tap-to-type, long-press repeat, 48dp targets
- Rest timer: full-screen overlay, countdown, haptic, +/-30s adjustment
- Finish dialog with incomplete sets warning, workout history with pagination
- Active workout banner in bottom nav, elapsed timer
- 328 tests (51 unit, 45 widget)

### Step 5e: UX Polish Sprint (PRs #16-#18)
- Removed start-workout name dialog (auto-naming), trimmed onboarding to 2 pages
- Set row redesign: 28-32sp numbers, tap-to-type, RPE hidden by default
- Wired onboarding data to Supabase, built minimal Profile screen
- Moved Finish button to thumb zone, added previous session hints, create-exercise in picker
- Prominent Add Set button, rest timer adjustment, active workout banner polish

### Step 6: Routines (PR #19)
- Renamed from "Templates" to "Routines" (market vocabulary)
- Bottom nav: Home | Exercises | Routines | Profile (History moved inside Home)
- Routine model (Freezed), repository, list/create screens
- Start-from-routine: 2 taps to first set (tap card -> pre-filled workout)
- Routines don't store weights — sourced from last session via `lastWorkoutSetsProvider`
- Home screen rebuild: routine launchpad + recent workouts + start empty workout
- 72dp routine cards, long-press for edit/delete, starter routines for new users

### Step 7: Personal Records (PR #20)
- PR detection in `finishWorkout()`: max weight, max reps, max volume
- Only working sets, strictly greater than previous, first workout consolidated
- Bodyweight logic: weight=0 tracks max_reps only, added weight tracks all three
- PR celebration: screen flash, spring animation, heavy haptic (no confetti)
- PR list screen with empty state

### Step 8: Home Polish & PR Integration (PR #21)
- Resume unfinished workout banner (most prominent element)
- Recent PRs section on home, "View All" to PR list
- Workout history detail with PR badges on record sets

### Step 9: E2E Testing & CI/CD (PRs #22-#24)
- Playwright infrastructure: config, helpers, fixtures, global setup/teardown
- Smoke tests (every PR): auth, workout, PR detection
- Full suite (merge to main): all features + edge cases + crash recovery
- `e2e.yml` + `release.yml` GitHub Actions workflows
- Final manual QA pass on physical devices

### Step 10: UX Improvements & Security (PRs #25-#26)
- Exercise detail bottom sheet in active workout (DraggableScrollableSheet)
- Stat cards on home (workout count, PR count with subtitles)
- Manage Data screen: delete history (two-step), reset all (type-to-confirm)
- Error message sanitization: `AppException.userMessage`, no raw DB errors in UI
- Migration: `personal_records.set_id` FK changed to `ON DELETE SET NULL`
- 61 new tests

### Step 11: Content, Smart Defaults, Home Simplification (PRs #27-#30)
- Exercise descriptions + form tips (migration, seed, UI in detail screen + bottom sheet)
- Smart set defaults: 4-priority fallback chain (prev session -> last set -> equipment defaults -> 0/0)
- Home simplification: removed Recent/Recent Records sections, enriched stat card subtitles
- 11b: 6 regression bug fixes (Hive serialization, form tips, routine start errors, equipment defaults)
- 11c: CI pipeline split into 3 parallel jobs + caching, 8 new E2E regression specs
- 787 tests total

---

## Step 12: Weekly Training Plan — Bucket Model

> **Status:** IN PROGRESS (PR #32). Migration applied to hosted Supabase. 5 regression bugs fixed. 6 E2E smoke tests added.

> **Feature overview:** Users plan their training week by placing routines into an ordered "bucket" — sequenced but not tied to specific days. The app surfaces "what's next" on the Home screen and tracks weekly completion.

#### 12a: Schema & Backend

**New table: `weekly_plans`** (migration `00011_create_weekly_plans.sql` — applied)

```sql
CREATE TABLE weekly_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,  -- always a Monday
  routines JSONB NOT NULL DEFAULT '[]',
  -- [{routine_id: UUID, order: int, completed_workout_id: UUID|null, completed_at: timestamptz|null}]
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, week_start)
);
```

**Extend `profiles`:** `training_frequency_per_week INTEGER NOT NULL DEFAULT 3 CHECK (BETWEEN 2 AND 6)`

**Auto-populate:** On first app open of the week, copy previous week's routines (reset completion data). Show "Same plan this week?" banner with Edit/Confirm.

#### 12b: Training Frequency in Onboarding & Profile

- Onboarding page 2: 5 chip options (2x-6x/week), default 3x
- Profile: "Weekly goal" tappable row -> bottom sheet with same chips

#### 12c: Home Screen — THIS WEEK Section

Between stat cards and MY ROUTINES. Horizontal scrollable routine chips:
- **Done:** collapsed green chip with checkmark
- **Next:** solid green, taller (52dp), primary CTA, tap starts routine
- **Remaining:** ghosted, 0.55 opacity

Header: `THIS WEEK` + `{n} of {m}` count + suggested-next pill chip. Completion is automatic on workout finish. No day-of-week assignment, no shaming language.

**Empty states:** No routines -> section hidden. Has routines but no bucket -> "Plan your week ->" CTA. Disengaged 2+ weeks -> collapses to single line.

#### 12d: Plan Management Screen (`/plan/week`)

ReorderableListView of routine rows. Add via DraggableScrollableSheet multi-select. Soft cap at `training_frequency_per_week` (greys out, tooltip, still tappable). Auto-fill button, swipe-to-remove with undo, clear week action.

#### 12e: Week Review

When all complete OR new week starts: section transforms to `WEEK COMPLETE` with stats row (`{n} sessions . {kg} . {n} PRs`). `NEW WEEK` action pre-populates from completed week. Incomplete weeks show remaining at 0.3 opacity, no shame text.

**Gamification hooks (Phase 15+):** Consistency stat delta, quest XP — hidden until gamification system is built.

#### 12f: Integration Points

- Starting from bucket uses existing `startRoutineWorkout()` — zero logging changes
- Workout completion matches `routineId` in bucket and marks complete
- Bucket is a planning aid, not a gatekeeper — any workout can start anytime

#### Step 12 — Acceptance Criteria

- [x] `weekly_plans` table with RLS, `profiles.training_frequency_per_week` column
- [x] Training frequency in onboarding (page 2) and Profile
- [x] THIS WEEK section with ordered chips (done/next/remaining states)
- [x] Suggested-next pill chip, auto-completion on workout finish
- [x] Plan management: drag-to-reorder, add/remove, soft cap, auto-fill
- [x] Auto-populate from last week with confirm/edit banner
- [x] Week review: WEEK COMPLETE with stats, NEW WEEK action
- [x] Widget/unit tests (64 new), E2E smoke tests (6 new, 24 test cases)
- [x] 5 regression bugs fixed (auto-populate timing, weight unit, nav highlight, undo race)

#### Step 12 — File Plan

```
lib/features/weekly_plan/
  data/  weekly_plan_repository.dart, models/weekly_plan.dart
  providers/  weekly_plan_provider.dart, suggested_next_provider.dart, week_review_stats_provider.dart
  ui/  widgets/ (week_bucket_section, routine_chip, week_review_section), plan_management_screen, add_routines_sheet

Modified: onboarding_screen, profile_screen, home_screen, app_router, active_workout_notifier
Migration: supabase/migrations/00011_create_weekly_plans.sql
```

---

## Step 12.1: E2E Infrastructure — Parallelism, Teardown, Data Seeding (DONE — PR #35)

- Replaced Python `http.server` with `http-server` npm package (concurrent). `workers: 2` in config + CI.
- Global teardown cascades FK deletes (sets → workout_exercises → workouts → PRs → plans → profiles → auth user). All 24 test users delete cleanly.
- Seeded workout+PR data for `smokePR`, completed weekly plan for `smokeWeeklyPlanReview`, profile for `smokeExercise`.
- Rewrote `exercise-library.smoke.spec.ts` to standard infra (removed hardcoded `test.skip`, uses `smokeExercise` user).
- Added Dart semantics labels (`tooltip: 'Create routine'`, `Semantics(label: 'More options')`) for Playwright selectors.
- **Result:** 58 passed, 2 skipped (expected), 0 failures, 6.1 min runtime. Key files: `global-setup.ts`, `global-teardown.ts`, `playwright.config.ts`, `selectors.ts`, `e2e.yml`.

## 13a-PR8: E2E Overhaul — AOM Selectors, Bug Fixes, Feature-Based Restructure (DONE — PR #50)

- **Flutter 3.41.6 AOM migration:** Replaced all `flt-semantics[aria-label="..."]` CSS selectors with `role=TYPE[name*="..."]` Playwright selectors. Flutter no longer sets `aria-label` as DOM attributes — accessible names are communicated via the browser's Accessibility Object Model.
- **App bug fixes:** Exercise delete navigation (captured GoRouter before async gap, `router.go('/exercises')` instead of `context.pop()`). RLS policy `exercises_select_own_deleted` for soft-delete visibility. Hive saves awaited in `ActiveWorkoutNotifier` (prevent data loss on web reload).
- **Strict mode fixes:** `.first()` / `.last()` on SnackBar text and search input locators where Flutter renders dual DOM elements.
- **Restructure:** Flattened `smoke/` (16 files) + `full/` (11 files) into `specs/` (11 feature-based files). Replaced directory-based organization with Playwright `{ tag: '@smoke' }` on describe blocks. Standardized naming: `test('should ...')`, bug IDs parenthesized.
- **Removed:** 2 tests for unimplemented RECENT RECORDS feature. Unskipped 6 previously-skipped tests (delete nav, EX-003, BUG-003 smoke + full).
- **Result:** 145 passed, 0 failed, 0 skipped. 994 unit/widget tests. Key files: `specs/*.spec.ts`, `helpers/selectors.ts`, `playwright.config.ts`, `exercise_detail_screen.dart`, `active_workout_notifier.dart`, `supabase/migrations/00017_fix_exercise_soft_delete_rls.sql`.

---

## Step 12.2: Home Redesign + Weekly Plan UX + Bug Fixes

> **Status:** TODO. Addresses 7 user-reported issues: 4 bugs, 2 UX gaps, 1 home screen redesign.
> Split into 3 sub-steps for manageable PRs.

### Context & Agent Analysis

**PO verdict:** Home screen should be action-first (weekly plan hero), not dashboard-first (stat cards). Routines list is redundant with weekly plan. Frequency limit should stay soft (goal, not gate) — matches Fitbod/Strong/Hevy. Enforced routine ordering is a retention-killer; bucket model's value is flexibility.

**UI/UX verdict:** Chip system is the strongest design element — keep and strengthen. Remove routines list from home entirely. Replace lifetime stats with contextual stats (last session, week volume). Empty plan state is invisible. "Start Empty Workout" should be FilledButton, not OutlinedButton. Don't add gradients, progress bars, or muscle group tags to chips.

---

### 12.2a: Bug Fixes (6 issues)

**Bug #1: "Fill Remaining" doesn't check off sets**
- **Root cause:** `fillRemainingSets()` in `active_workout_notifier.dart:408-444` copies weight/reps but doesn't set `isCompleted: true`
- **Fix:** Add `isCompleted: true` to the `copyWith` call for filled sets
- **File:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`
- **Test:** Update existing test in `test/unit/features/workouts/providers/active_workout_notifier_test.dart:1096-1234` to expect completion

**Bug #2: Stat card counts not updating after workout**
- **Root cause:** After workout completion (`active_workout_screen.dart:173-175`), only `workoutHistoryProvider` and `prListProvider` are invalidated — `workoutCountProvider`, `prCountProvider`, and `recentPRsProvider` are NOT invalidated
- **Fix:** Add `ref.invalidate(workoutCountProvider)`, `ref.invalidate(prCountProvider)`, `ref.invalidate(recentPRsProvider)` after workout save
- **Files:** `lib/features/workouts/ui/active_workout_screen.dart`

**Bug #3: Profile page stat cards not navigable**
- **Root cause:** `_StatCard` in `profile_screen.dart:341-385` is a plain `Container` with no `onTap`/`GestureDetector`
- **Fix:** Wrap Workouts card → `/home/history`, PRs card → `/records`. Member Since stays informational.
- **File:** `lib/features/profile/ui/profile_screen.dart`

**Bug #4: Weekly plan enforces fixed routine order**
- **Root cause:** `week_bucket_section.dart` sets `onTap: null` for non-"next" chips. Only the `suggestedNextProvider` result is tappable.
- **Fix:** Make ALL uncompleted chips tappable (launch that routine). Keep "suggested next" as a visual recommendation (green highlight) not a gate.
- **File:** `lib/features/weekly_plan/ui/widgets/week_bucket_section.dart`

**Bug #5: No visible way to edit weekly plan mid-week**
- **Root cause:** Edit access is hidden behind long-press gesture on chip row (`GestureDetector(onLongPress: ...)`). Most users will never discover it.
- **Fix:** Add visible "Edit" icon/link in the THIS WEEK section header row. Keep long-press as secondary gesture.
- **File:** `lib/features/weekly_plan/ui/widgets/week_bucket_section.dart`

**Bug #6: "Last:" shows wrong weight after changing weight mid-workout**
- **Root cause:** `lastWorkoutSetsProvider` is a cached FutureProvider. The `lastSet` passed to `SetRow` is not reactive to current-session changes. When user changes weight on a set, "Last:" still shows stale previous-workout data.
- **Investigate further:** "Last:" is *supposed* to show the previous workout's values. Verify whether the bug is: (a) stale cache from a prior session, or (b) user expects "Last:" to reflect current-session sets. If (a), fix cache invalidation. If (b), relabel to "Previous:" and document behavior.
- **Files:** `lib/features/workouts/ui/active_workout_screen.dart:548`, `lib/features/workouts/ui/widgets/set_row.dart:170`

**Bug #7: Weekly frequency setting has no visible effect**
- **Root cause:** `trainingFrequencyPerWeek` is a soft cap only — dims the "Add Routine" button + shows tooltip. But `Tooltip` requires long-press on mobile (invisible to most users).
- **Fix (keep as soft cap per PO recommendation):** Replace invisible `Tooltip` with always-visible inline text "Goal reached — add anyway" in `bodySmall` muted style when `atSoftCap == true`. Do NOT hard-block.
- **File:** `lib/features/weekly_plan/ui/plan_management_screen.dart`

#### 12.2a — Acceptance Criteria

- [ ] Fill Remaining marks sets as completed (checkbox checked)
- [ ] Home stat cards update immediately after workout completion
- [ ] Profile Workouts card → workout history, PRs card → records screen
- [ ] All uncompleted weekly plan chips are tappable (not just "next")
- [ ] Visible "Edit" affordance in THIS WEEK section header
- [ ] "Last:" behavior verified and fixed or clarified
- [ ] Frequency soft-cap shows inline text instead of tooltip
- [ ] Existing tests updated, new unit tests for each fix
- [ ] `make ci` passes

#### 12.2a — File Plan

```
Modified:
  lib/features/workouts/providers/notifiers/active_workout_notifier.dart  — fillRemainingSets adds isCompleted: true
  lib/features/workouts/ui/active_workout_screen.dart                     — invalidate count/PR providers after save
  lib/features/profile/ui/profile_screen.dart                             — add navigation to stat cards
  lib/features/weekly_plan/ui/widgets/week_bucket_section.dart            — all chips tappable + edit icon in header
  lib/features/weekly_plan/ui/plan_management_screen.dart                 — inline soft-cap text
  lib/features/workouts/ui/widgets/set_row.dart                           — verify/fix Last: display

Tests:
  test/unit/features/workouts/providers/active_workout_notifier_test.dart  — update fillRemaining test
  test/widget/ (new)                                                       — stat card navigation, chip tappability
```

---

### 12.2b: Home Screen Redesign

**Goal:** Transform home from a generic dashboard into a gym-floor action screen. One-handed, glanceable, answers "what do I do today?" in 2 seconds.

#### Layout (top to bottom)

1. **Header** — Date ("WED, APR 9") + user display name. Remove large "RepSaga" title (wasted prime real estate — user knows what app they opened).

2. **THIS WEEK section (hero)** — Full visual weight, always above the fold.
   - Section title "THIS WEEK" with progress counter ("2 of 4") as secondary metadata BELOW title (not competing with SuggestedNextPill in same Row).
   - Chip row: increase `next` chip to 60dp (add exercise count as secondary line: "Push Day / 6 exercises"), `remaining` to 48dp, `done` stays 44dp.
   - "Edit" icon visible in section header.
   - Empty state: full-width bordered container at 72dp min-height with centered text + icon. Not a dim line of text.

3. **Contextual stat cells** — 2 horizontal cells replacing current stat cards:
   - **Last session:** "3 days ago — Push Day" (tap → workout history)
   - **This week's volume:** "12,400 kg this week" (tap → history filtered to week)
   - NOT lifetime workout count or PR count (those live on Profile).

4. **Start Empty Workout** — `FilledButton` (not `OutlinedButton`), full-width, always visible without scrolling.

5. **Routines list** — REMOVE entirely when user has an active weekly plan. Keep "Create Your First Routine" CTA only for `userRoutines.isEmpty && defaultRoutines.isEmpty` (onboarding state).

#### What NOT to do
- No gradient overlays on chips/cards
- No progress bars inside stat cards
- No muscle group tags on chips (belongs in routine detail)
- No animated confetti beyond existing WeekReviewSection
- No streak counter until Phase 15 (broken streaks demoralize)

#### 12.2b — Acceptance Criteria

- [ ] Home shows date + name header (no large app title)
- [ ] THIS WEEK is the hero section, above stat cells
- [ ] Progress counter separated from SuggestedNextPill (different rows)
- [ ] Chip sizes: next=60dp, remaining=48dp, done=44dp
- [ ] Next chip shows exercise count as secondary line
- [ ] Empty plan state is a 72dp+ tappable container
- [ ] Contextual stats replace lifetime stats (last session + week volume)
- [ ] Week volume requires new query/RPC (sum of weight*reps this week)
- [ ] Routines list hidden when active plan exists
- [ ] Start Empty Workout is FilledButton, visible without scrolling
- [ ] `make ci` passes, E2E smoke tests updated if selectors changed

#### 12.2b — File Plan

```
Modified:
  lib/features/workouts/ui/home_screen.dart                    — restructure layout, remove routines list, new stat cells
  lib/features/weekly_plan/ui/widgets/week_bucket_section.dart  — header layout, empty state redesign, progress counter placement
  lib/features/weekly_plan/ui/widgets/routine_chip.dart         — chip size increases, exercise count on next chip
  lib/features/workouts/providers/workout_history_providers.dart — new provider: weekVolumeProvider (sum weight*reps this week)

New:
  lib/features/workouts/ui/widgets/contextual_stat_cell.dart    — reusable stat cell widget (last session, week volume)

Tests:
  test/widget/features/workouts/ui/home_screen_test.dart        — verify new layout, conditional routines list
  test/e2e/smoke/ (update selectors if needed)
```

---

### 12.2c: Plan Management UX Polish (DONE — PR #38)

- Auto-fill `OutlinedButton` (`Icons.repeat`) in empty plan state + loading guard
- Inline "X/Y routines planned" / "X/Y goal reached" counter below Add Routine row (alpha 0.55 for WCAG AA)
- `SuggestedNextCard` replaces pill — full-width 56dp card, green left border, play_arrow icon, "Up next" label
- `_ConfirmBanner` color constants unified with sibling classes
- 852 tests (15 new widget tests + 3 edge cases)

---

## Step 12.3: UX Polish & Content Expansion

> Findings from manual exploratory QA on device (2026-04-09). Prioritized by PO, root-caused by QA, design direction from UX.

### 12.3a: P0 Bug Fixes — Back Navigation + Home Screen Flicker (DONE — PR #39)

- **Bug 1 (back nav):** PopScope moved to top-level `ActiveWorkoutScreen.build()`, covers loading + active states. `_showDiscardDialog` extracted to ConsumerWidget level.
- **Bug 2 (home flicker):** `WeekBucketSection` shows stale data during provider reload via `hasValue` guard. `hasActivePlan` uses `planAsync.hasValue` to retain state during loading.
- **6 new widget tests** (858 total). Key files: `active_workout_screen.dart`, `week_bucket_section.dart`, `home_screen.dart`.
- **Lesson:** `context.go()` → `context.push()` breaks Flutter web reload in GoRouter 13.x. `PopScope(canPop: false)` is sufficient for back button. See `tasks/lessons.md`.

---

### 12.3b: Copy Fix + Content Expansion (DONE — PR #40)

- **Copy fix**: "goal reached" → "planned — ready to go" / "planned this week" in `plan_management_screen.dart`
- **31 new exercises** across 7 muscle groups including new `cardio` category (migration 00013 + 00014). Total ~92 exercises.
- **5 new routine templates**: Upper/Lower Upper, Upper/Lower Lower, 5×5 Strength, Full Body Beginner, Arms & Abs
- **Preset action sheet**: Default routines show Start + Duplicate and Edit (no Edit/Delete). `duplicateRoutine()` added to notifier.
- **871 tests** (13 new). Lesson: PG `ALTER TYPE ADD VALUE` must be in a separate transaction from INSERTs using the new value.

---

### 12.3c: Standalone Routine → Plan Prompt (DONE — PR #41)

- **Post-workout prompt**: Bottom sheet "X isn't in your plan yet. Add it?" with Add/Skip. Shown after PR celebration (or directly) when routine not in plan.
- **`addRoutineToPlan`** method on `WeeklyPlanNotifier` with idempotency guard + error handling.
- **PR celebration integration**: Prompt data passed via route extras; shown on Continue tap.
- **885 tests** (13 new). Routine name looked up from provider (immutable) instead of mutable workout name.

---

### Stale Workout Timeout (Deferred to Phase 13)

Not auto-discard. When app opens and `startedAt` is >6 hours ago, show prominent modal: "Your workout from [date] is still open — Resume or Discard?" Already handled partially by `ResumeWorkoutDialog`. Enhancement goes into Phase 13 production readiness.

### Execution Order

| Sub-step | Dependencies | Effort |
|----------|-------------|--------|
| 12.3a (P0 bugs) | None | 0.5 session |
| 12.3b (copy + content) | None (can parallel with 12.3a) | 1 session |
| 12.3c (plan prompt) | 12.3a (needs stable back nav) | 0.5 session |

---

## Phase 13: Launch

> Final phase before Play Store submission. Everything after this (Phase 14 Offline Support, Phase 15-16 Gamification) is post-launch.
> Structure: **Sprint A — Store Blockers** (complete) → **Toolchain Bridge** (complete) → **Sprint B — Retention** (next) → **Sprint C — Resilience** → submit.

### Completed

**Sprint A — Store blockers**
- PR #42: Account deletion, volume unit display, OAuth deep link
- PR #43: Release signing, branding strings, privacy policy + ToS
- PR #44: Sprint A QA follow-ups (legal polish, PWA theme, live delete E2E)
- PR #45: Wakelock during active workout
- PR #46: Observability — Sentry crash reporting (PII-scrubbed) + first-party `analytics_events` table with 8 ratified events

**Toolchain bridge**
- PR #47: `make ci` gained `flutter build apk --debug --no-shrink` to catch native plugin breakage pre-push
- PR #49: Bulk dependency upgrade — Riverpod 3, GoRouter 17, Freezed 3 (34 deps swept, 994/994 tests pass, APK/Web size unchanged)
- PR #50: E2E overhaul — Flutter 3.41.6 AOM selectors, feature-based restructure (11 spec files, 145 tests with @smoke tags), exercise soft-delete RLS fix
- PR #51: Phase 13c removed from plan (Athletic Brutalism redesign conflicted with RPG gamification direction)

**Sprint B — Retention (in progress)**
- PR #53: P4 Exercise images fix — rehosted 59 default exercise images from third-party GitHub to our own `exercise-media` Supabase Storage bucket (migration `00018`). Root cause of prior 404s: migration `00004` seeded fabricated folder paths that never matched the source catalog.
  - New artifacts: `tools/exercise_image_mapping.json` (audit trail with curation notes), `tools/fix_exercise_images.dart` (idempotent uploader kept in-repo for re-runs).
  - E2E regression asserts HTTP 200 on bucket fetches — `CachedNetworkImage` silently falls back to a muscle-group icon, so presence-only `<img>` checks would miss the failure mode.
  - Closes QA-005. Remaining ~32 NULL-URL exercises from migration `00014` are handled by P9 (content + images ship together).
- PR #55: P8 First-run empty-state CTA. Replaces the "Plan your week" dead-end for zero-workout users with a single beginner-routine hero card in the THIS WEEK slot (Full Body default; alphabetical fallback; `SizedBox.shrink` when no defaults). Tap jumps straight into active workout via existing `startRoutineWorkout()`. `_ContextualStatCells` now hide when both values are empty instead of showing "No workouts yet / No volume yet".
  - Gated on `workoutCount == 0` (not a one-shot first-launch flag) so the CTA persists across sessions until the first workout is logged — the critical gotcha for fitness apps where most signups don't lift in session 1.
  - New pure `estimateRoutineDurationMinutes()` util in `lib/features/weekly_plan/utils/` replaces the original hardcoded "~45 min" — now accurate across all seeded routines (Full Body ≈ 55 min).
  - `workoutCountProvider` now `ref.keepAlive()`-guarded to avoid repeated COUNT queries on nav push/pop; `ref.invalidate()` on workout finish still forces refresh.
  - Tests: +6 Flutter (1 widget for loading-state guard, 5 unit for duration estimator), +3 Playwright smoke (`First workout CTA (P8)` describe block in `home.spec.ts`). New `smokeFirstWorkout` e2e user. `usersNeedingSeededWorkoutForP8` array added so existing weekly-plan tests retain their "Plan your week" assertion.
  - Follow-up: EX-003 search-input `flutterFill` flake tracked in #56 (pre-existing, unrelated).
- PR #58: P9 Exercise content standard + library expansion. Backfilled 31 content-less exercises from migration `00014` (migration `00020`) and shipped 58 new default exercises (migration `00019`) to reach **150 default exercises, 100% covered by `description` + `form_tips`** — Phase 13 Exit Criterion #1 now MET on hosted Supabase. Voice matches 00010: imperative second-person, 15-25-word descriptions, 4-bullet form tips; Upright Row carries a shoulder-impingement warning as a special case.
  - **Governance:** New `scripts/check_exercise_content_pairing.sh` is a row-level CI guard — any PR that INSERTs exercises must UPDATE `description` + `form_tips` for *every* inserted name in the same PR, or the build fails (wired ahead of analyze/test/build in `ci.yml`). CLAUDE.md now carries the convention verbatim. Rewritten from an initial set-level check to per-name matching after reviewer pushback — partial compliance silently passing was the real risk.
  - **UI polish (shipped alongside content):** Exercise detail sheet reordered to name → custom label → description → chips → images → FORM TIPS → PRs → delete (the "Created [date]" line was dropped). Form-tip bullets switched from `check_circle_outline` to a 6dp primary-color dot; body prose raised to full `onSurface` opacity. Browse list got a 3dp primary-color left accent on non-default (user-created) exercise cards; `ExerciseImage` now propagates `memCacheHeight`/`memCacheWidth` so height-only callers (detail sheet) stop decoding full-res images.
  - **Absorbs P2** — count-only library expansion was rejected in favor of shipping 150 exercises with complete content rather than 150 with 50+ empty detail sheets.
  - Tests: 1030 Flutter pass, new `test/fixtures/test_finders.dart` helper (`findBulletDots()`) shared across three widget tests. All 6 reviewer findings (2 Important + 4 Nits) fixed in the same cycle per "no deferring" policy.
- PR #60: P1 Per-exercise weight progress chart — `fl_chart` line chart on the exercise detail sheet between PR section and delete. Metric: max completed working-set weight per calendar day (shared `completedWorkingSets` predicate extracted to `lib/features/workouts/utils/set_filters.dart` so chart and PR detection can't drift). 90d-default / All-time toggle held as per-exercise local state. Phase 13 Exit Criterion #4 now MET.
  - **Anti-generic aesthetic:** 3dp green line on `surfaceColor` (no card wrapper), linear curves, no gradient fill, single midpoint hairline grid, inline min/max y-labels flush-right, `lineTouchData` disabled (read-only glance surface), 200dp fixed height. 0-point → copy only ("Log this exercise to see your progress"); 1-point → copy only ("1 session logged") — skips a 200dp mostly-empty canvas.
  - **Side effects:** `SegmentedButtonThemeData` added to `AppTheme.dark` (Material 3 default read ghostly on the dark surface); `exerciseProgressProvider` invalidated in `ActiveWorkoutNotifier.finishWorkout` so chart refreshes post-save despite `keepAlive`; `Semantics(image: true)` required for Flutter AOM to expose the chart as `role=img` (the E2E assertion path — CI-only regression caught on first push).
  - Tests: 1070 Flutter pass (+8 net: 9 set_filters + 17 exercise_progress + 10 widget section + 1 active_workout_notifier invalidation; minus the deduplicated PR-detection private). +1 Playwright `@smoke` (`Exercise progress chart`, new `smokeExerciseProgress` user with two seeded sessions to hit the multi-point branch).
  - All reviewer findings (2 Important + 2 Nits + 1 post-fix Important) closed in-cycle per "no deferring" policy.

**Sprint C — Resilience (complete)**
- PR #61: W6 Direct Supabase access in UI. Literal `.from()` leak scan was already clean — all DB access sits inside `data/` repos. The residual bypass was `Supabase.instance.client.auth.currentUser?.id` read inline from one UI screen (`create_exercise_screen.dart`) and four methods inside `ProfileNotifier`, forcing those files to import `supabase_flutter` for a session lookup. New `currentUserIdProvider` (sync `Provider<String?>`, intentionally non-reactive — router handles auth transitions via `authStateProvider`) in `features/auth/providers/auth_providers.dart`. All 5 call sites now go through `ref.read(currentUserIdProvider)`; unused `supabase_flutter` import dropped from the UI file. Tests: +2 unit pinning signed-in / signed-out branches via `overrideWithValue`; 1072 total. Reviewer approved, 2 nits (comment clarifying non-reactive contract, comment clarifying test intent) closed in-cycle per "no deferring" policy. `sentry_init.dart` and `auth_repository.dart` intentionally untouched (core infra + THE auth layer).
- PR #63: W3b Input length limits (TextField + server CHECK). Defense-in-depth — UI `maxLength` blocks casual over-entry, migration `00021_input_length_limits.sql` adds 9 `CHECK` constraints against API-level abuse (anyone bypassing the client). `AppTextField` gets `maxLength` (pass-through) + `showCounter` (default `true`, off only for the onboarding display-name field where the fixed-height viewport cannot afford the counter line). Six UI sites wired: onboarding/profile display-name (50), create-exercise/routine/workout-rename name (80), finish-workout notes (1000). DB ceilings sized with headroom above observed seed maxes (form_tips seed max 246 → DB 2000). Pre-flight `char_length` scan against hosted Supabase confirmed zero existing rows would violate any constraint. Tests: +2 widget (`AppTextField` clamping + counter), +1 widget (finish-workout notes clamping), +1 widget (create-exercise name clamping — added in reviewer fixup since the WIP spec had promised it); 1076 total. Migration applied to hosted Supabase post-merge; all 9 constraints verified via `pg_constraint`. Reviewer findings (1 Important + 2 Nits) closed in-cycle per "no deferring" policy.
- PR #65: W3 Stale workout timeout UX. `ResumeWorkoutDialog` branches on workout age (`>= 6h`). Fresh branch keeps the existing minimal copy (`Resume workout?` / `"$name" is still in progress.` / buttons `Discard` + `Resume`). Stale branch adds human-readable age context — title `Pick up where you left off?`, body renders `"$workoutName"` in `titleMedium` via `Text.rich` with a muted second line `was interrupted $age.`, primary button relabeled `Resume anyway` (product-owner call: data-preservation stays primary; label friction does the stale-signalling). Age formatter ladder: `<1h` → `"less than an hour ago"`; same-day `≥1h` → `"$N hour(s) ago"` (singular at 1h); previous calendar day → `"yesterday at 3:14 PM"`; `<7d` → `"Monday at 9:30 AM"`; `≥7d` → `"$N days ago"`. Pulled as top-level `formatResumeAge(DateTime, DateTime)` + `isStaleWorkout(Duration)` to unit-test with a fixed clock. Anti-generic rules (ui-ux-critic): no clock/warning icon, no centered body text, no chip, same `AlertDialog` widget type. Trigger and `discardWorkout()` semantics unchanged — visual-only. Tests: +17 unit (formatter branches + boundary + midnight rollover + 12 AM/PM + clock-skew fallback), +9 widget (both branches' title/body/buttons + action results); 1103 total. Reviewer blocker (missing quotes around `$workoutName` in stale span) + important (test didn't assert the quotes) closed in-cycle per "no deferring" policy.
- PR #67: W8 Home information architecture refresh. Original perf premise (long list virtualization) was invalidated — HomeScreen has no long list — so W8 was re-scoped (product-owner + ui-ux-critic) into a four-state IA rewrite: active-plan / brand-new / lapsed / week-complete, each sharing a unified `_HeroBanner` vocabulary (80dp, Material+InkWell surface, 3dp primary-color left accent, label → headline → subline → `FilledButton`). Lapsed state drives toward planning: `Plan your week` primary + `Quick workout` secondary. Home tree recomposed for scoped rebuilds — each block (`HomeStatusLine`, `_ConfirmBanner`, `_WeekReviewCard`, `ActionHero`, `RepaintBoundary(WeekBucketSection)`, `LastSessionLine`, `_HomeRoutinesList`) is its own `ConsumerWidget` and `HomeScreen.build` watches zero providers. Two new derived booleans (`hasActivePlanProvider` from `weeklyPlanProvider`, `hasAnyWorkoutProvider` from keep-alive `workoutCountProvider`) let status-line + routine-list skip rebuilds on paginated history loads. **Deletions:** `contextual_stat_cell.dart` + its test, `weekVolumeProvider` + its test, `_SuggestedNextCard` inside `week_bucket_section.dart`, `THIS WEEK` label/counter, date header. Starter routines moved off home entirely into `/routines`. **Side-fix:** `ResumeWorkoutDialog` now accepts an optional `DateTime? now` injection seam so age-dependent widget tests pin the clock (midnight-crossing flake). Tests: +widget (action hero all 4 states + tap destinations incl. Quick workout → Discard → start new + navigate), +widget (status line all 4 states), +widget (last session line), +widget (home routines), +unit (`lastSessionProvider` replaces `week_volume_provider_test`); total 1087. **E2E:** `startEmptyWorkout` helper is now state-aware (races `HOME.quickWorkout` vs `FIRST_WORKOUT_CTA.card`); `e2e-full-ex-detail-sheet` user added to both `freshStateUsers` and `usersNeedingSeededWorkoutForP8` so the `Exercise detail sheet` describe's `startEmptyWorkout` beforeEach gets deterministic lapsed state; full 148-test E2E suite green on CI. All reviewer findings (3 Blockers / 6 Important / 5 Nits) closed in-cycle per "no deferring" policy — B1 dead-end discard (Quick-workout → Discard now starts a fresh workout + navigates to `/workout/active`) + I1 lapsed hero breaking `_HeroBanner` vocab (rewrapped) being the load-bearing fixes.
- PR #69: B6 ProGuard/R8 release optimization. Enabled `isMinifyEnabled = true` + `isShrinkResources = true` on `release` buildType only (debug untouched); `android/app/proguard-rules.pro` ships **narrow keep rules by design** — no `-keep class ** { *; }` wildcards. Rule blocks: reflection-friendly attributes (`Signature, *Annotation*, EnclosingMethod, InnerClasses, SourceFile, LineNumberTable` + `renamesourcefileattribute`), JNI native-methods + enum `values()`/`valueOf` + Parcelable `CREATOR`, Flutter embedding (`io.flutter.**` — covers `plugin`, `plugins`, `embedding` sub-packages), Play Core deferred-components `-dontwarn` (we don't ship deferred components; suppresses ~1.5MB bloat), Sentry (`io.sentry.**`), OkHttp/OkIO/Conscrypt/BouncyCastle/OpenJSSE TLS `-dontwarn` (OkHttp3 pulled in transitively by `sentry-android` for envelope transport — NOT from `supabase_flutter`, which is pure Dart), Kotlinx coroutines `-dontwarn`. Explicitly **no rules** for Hive (pure Dart, `Box<dynamic>` only), Supabase (pure Dart, no `io.supabase` classpath), Freezed/json_serializable/Riverpod/GoRouter (AOT-compiled into `libapp.so`) — each gap documented inline. New Makefile target `build-android-release-arm64` for local verification. **Measurements:** arm64-v8a split APK **25.83MB → 22.83MB (-11.6%)**, `classes.dex` **-64.7%**. Absolute size floor ~22 MB is native libs (`libflutter.so` + `libapp.so` + `libsentry*.so` ≈ 21.8 MB — untouchable by R8; further reduction requires AAB + per-device ABI/language splits, separate DevOps task). 5-flow on-device smoke on Samsung S25 Ultra (login/OAuth, workout logging + save, analytics event emission, exercise progress chart, force-stop + restart) captured 13,806 logcat lines; zero `FATAL EXCEPTION`, `ClassNotFound`, `NoSuchMethodError`, `MissingPluginException`, `SIGSEGV`, `SIGABRT` scoped to `com.repsaga.repsaga`. E2E not re-run (Playwright targets the web build; zero overlap with Android JVM/R8). Reviewer findings: 2 Important — redundant Flutter sub-package keeps (removed; identical APK size on rebuild proved the redundancy) + OkHttp comment attribution error (split section, re-attributed transitive chain to `sentry-android` 9.16.1) — both closed in-cycle per "no deferring" policy. Phase 13 Exit Criterion #6 MET; closing Sprint C also meets Exit Criterion #5.

**QA Monkey Testing Sweep (complete)**
- Full monkey testing analysis (rapid gestures, background/foreground cycling, concurrent taps, filter stress) found 18 issues: 3 crash vectors, 8 freeze risks, 4 visual glitches, 3 minor. All resolved across 3 PRs.
- PR #74: Exercise filter performance — root cause of user-reported filter freeze: `exerciseListProvider` was `FutureProvider.family` without `autoDispose`, creating permanent cache entries per filter combo. Fix: `autoDispose.family` + correct invalidation target (`exerciseListProvider` not `filteredExerciseListProvider`) + `ConsumerWidget` extraction to eliminate double rebuilds. Systemic `autoDispose` added to `lastWorkoutSetsProvider` and `workoutDetailProvider`. Tests: 1153 total.
- PR #75: Active workout stability — `_isFinishing`/`_isDiscarding` re-entrance guards on async operations, `_isShowingDiscardDialog` to prevent stacked dialogs, `_cancelRequested` token for cancel-safe async (prevents in-flight future from clobbering restored state), `_LoadingOverlay` with 10s cancel escape hatch (hidden during initial load via `hasRestorable`), `onLongPressCancel` on steppers, 300ms `_saveDebounce` on plan management, `confirmDismiss` race guard on set swipe-delete, `mounted` guard on PR celebration `postFrameCallback`. Tests: 1166 total.
- PR #76: Minor polish — wall-clock timer computation in `RestTimerNotifier` (correct after background resume, uses `package:clock` for `fakeAsync` testability), exercise picker sheet pops before pushing create screen, `GoRouter` same-tab navigation guard, `hasMore` check before `loadMore()`, `ListView.builder` replacing `SingleChildScrollView + Column.map()` in routine list. Tests: 1168 total.

### Deferred to v1.1+

- **P5** — 1RM estimation (Epley formula on exercise detail + PR cards)
- **W4** — Push notifications (workout reminders)
- **W5** — Data export (CSV/JSON)
- **W7** — Supabase free-tier monitoring (ongoing ops task, not a ship gate)
- **App icon redesign** — awaits post-launch direction decision

### Out of Scope for Phase 13

- **Gamification (Phase 15-16).** No XP, levels, streaks, quests, or badges land in Phase 13 — the format is still being decided. Code written in this phase must remain scalable to a future gamification layer (clean data/UI separation, no hard-coded assumptions that would block later hooks), but no gamification features ship here.
- **Offline (Phase 14).** The original B7 scope ("offline workout save & retry") is superseded by the broader Phase 14 work.
- **iOS.** Android-first; iOS deferred.

### Exit Criteria — Ready to Submit to Play Store

1. ✅ `SELECT COUNT(*) FROM exercises WHERE is_default = true AND (description IS NULL OR form_tips IS NULL)` returns `0` on hosted Supabase (met by PR #58 — 150/150 covered)
2. Zero image 404s on default exercise tiles (QA walkthrough against production storage)
3. New user sign-up → home shows "Start your first workout" CTA with beginner routine, not a blank list (E2E verified)
4. ✅ Any exercise with ≥2 logged sets shows a weight-over-time chart; zero/single-data-point states handled without crash (met by PR #60 — unit + widget + @smoke E2E cover all three states)
5. ✅ All Sprint C items merged (met by PR #69 — B6 ProGuard/R8 closed the last Sprint C item)
6. ✅ R8 code + resource shrinking enabled on release builds: `classes.dex` reduced ≥50% and total `arm64-v8a` APK deflation 10-15% documented in PR body. (Absolute APK size floor ~22 MB is set by Flutter native libs `libflutter.so` + `libapp.so` + `libsentry*.so` ≈ 21.8 MB, untouchable by R8. Further reduction requires AAB + per-device ABI/language splits — separate DevOps task, out of scope for Phase 13.)
7. Full CI green, 145/145 E2E pass, no critical open bugs in QA Status

---

## Phase 14: Offline Support

> Users are in gyms — basements, metal walls, dead zones. The app must let them finish a workout without a network. Phase 14 makes that a first-class experience without adopting a full offline-first sync engine.

**Scope shift:** Phase 13 B7 ("Offline workout save & retry") is absorbed into this phase. B7 scoped only the sync worker; Phase 14 is broader — read cache, sync service, PR reconciliation, UX indicators — because partial offline is worse than no offline (users don't know what's saved).

### Design Principles

- **Single-user app, no conflict resolution.** Workouts are append-only; profile and routines are last-write-wins with `updated_at`. Don't over-engineer for collaborative edits.
- **The active workout is sacred.** Once started, finishing it offline must succeed. Everything else (browsing, editing) can degrade gracefully.
- **Idempotent writes only.** Every queued mutation must be safe to replay. `save_workout` RPC is naturally replay-safe (delete-and-reinsert of `workout_exercises` + `sets` within a transaction) — verified in 14b preconditions.
- **Server is still the source of truth.** Local caches are read-through; the queue is a buffer, not a store. No merge logic, no vector clocks.
- **Instant UX over strict correctness.** Compute PR celebration locally from `pr_cache` for immediate dopamine; reconcile on sync drain. Rare divergence silently corrected.
- **Fail loud but recoverable.** Terminal failures surface in the sync indicator + Sentry breadcrumb; never silently drop.

### Preconditions (already in place)

- `HiveService` opens `active_workout`, `offline_queue`, `user_prefs` boxes (`lib/core/local_storage/hive_service.dart`). `offline_queue` is scaffolded but unused — Phase 14 wires it.
- `WorkoutLocalStorage` persists active workout state with schema-version guard — crash-safe in-progress workouts already work.
- `save_workout` is a single atomic Postgres RPC (`lib/features/workouts/data/workout_repository.dart`) that takes the whole payload and returns the saved `Workout` — trivially queueable as a single unit.
- **`PRDetectionService` is already a pure-function Dart service** at `lib/features/personal_records/domain/pr_detection_service.dart` — no extraction work needed for 14d.
- `PRRepository.upsertRecords` already uses `onConflict: 'user_id, exercise_id, record_type'` — replay-safe.
- All writes use client-generated UUIDs.
- Phase 13a Sprint A observability (Sentry + analytics) lands before this phase — Phase 14 leans on both for sync telemetry.

### Known constraints (IMPORTANT for scope)

- **`save_workout` RPC requires the `workouts` row to already exist on the server.** It does `UPDATE workouts ... WHERE id = v_workout_id` and raises `P0002` if the row is missing (see `supabase/migrations/00005_save_workout_rpc.sql`). The row is created earlier by `WorkoutRepository.createActiveWorkout()` — a regular insert.
  - **Consequence:** Phase 14 supports "workout started online, finished offline" (the common case). "Workout started fully offline" is **out of scope for v1 of this phase** unless a migration upgrades `save_workout` to upsert the `workouts` row itself. Track separately if needed later.
  - Replay of a `save_workout` call with the same `workout.id` IS safe — the RPC delete-and-reinserts `workout_exercises` and `sets` each call.

### 14a: Connectivity + Read-Through Cache Foundation (DONE — #78, #79)

- **PR #78 (Infrastructure):** `connectivity_plus` dep, `onlineStatusProvider`/`isOnlineProvider` (500ms debounce), `CacheService` (generic Hive JSON read/write/delete/clearBox), 5 new Hive boxes in `HiveService`, `OfflineBanner` widget mounted in shell route. 32 tests.
- **PR #79 (Repo Caching):** Read-through cache on all 4 repos (Exercise, Routine, PR, Workout). Pattern: read cache → try network → success writes cache → failure returns cached or rethrows. Key decisions: workout history only caches on refresh pass (limit >= 50); routine cache uses `{routines, exercises}` envelope for resolved Exercise objects; workout exerciseSummary stored as `_exercise_summary` custom field. `cacheRefreshProvider` fires once on app open. All write methods evict affected cache keys. 55 new cache tests, 1235 total.
- **Serialization gotchas solved:** `RoutineExercise.exercise` (`@JsonKey(includeToJson: false)`) → envelope pattern. `Workout.exerciseSummary` (excluded from both toJson/fromJson) → custom field + `copyWith`.
- **Not in scope:** writes still online-only (14b).

### 14b: Offline Workout Capture + Queue (DONE — #81)

- **`PendingAction` Freezed sealed class** (`lib/core/offline/pending_action.dart`) with 3 variants: `saveWorkout` (full RPC JSON payload), `upsertRecords`, `markRoutineComplete`. Uses `@Freezed(unionKey: 'type')` for discriminated union serialization.
- **`OfflineQueueService`** + **`PendingSyncNotifier`** manage Hive-backed queue with reactive count. Retry executes via repos, validates `planId` for stale plans, dequeues on success.
- **`finishWorkout()` offline path**: catches saveWorkout network failure → enqueues → evicts history caches → increments cached workout count → continues PR detection (from cache) + weekly plan (enqueues on failure). Each downstream call independently degrades.
- **Pending sync badge** below `HomeStatusLine` (tertiary color, `cloud_upload_outlined`, count). Tap opens modal bottom sheet with per-item retry.
- **Offline snackbar**: "Workout saved. Will sync when back online." (`tertiaryContainer` for M3 contrast).
- 40 new tests (1275 total). Key design: repository stays pure (network-only), queueing lives in notifier layer.

### 14c: Sync Service + Backoff + Observability ✅ PR #83

- **SyncService** (`sync_service.dart`) — Riverpod Notifier watches connectivity, drains queue FIFO on offline→online transition. Exponential backoff 1s→30s cap, max 6 retries.
- **SyncErrorClassifier** (`sync_error_classifier.dart`) — terminal (400/403/404/409/422) vs transient (5xx, network, timeout, auth). 401 treated as transient (JWT auto-refresh).
- **Transparent sync UX** (design pivot from original spec): silent background drain, no visible syncing animation. PendingSyncBadge 200ms fade-out. Terminal-only UI via SyncFailureCard (red accent, Retry + Dismiss).
- **In-flight guard** on PendingSyncNotifier prevents manual/auto retry race.
- **Analytics**: 3 Freezed events (workoutSyncQueued/Succeeded/Failed) with action type, retry count, queue duration.
- **Sentry breadcrumbs** on drain attempt and failure (PII-safe).
- 40 new tests (14 classifier + 18 service + 1 notifier + 7 widget), 7 E2E tests. 1315 unit/widget total.

### 14d: Local PR Detection + Reconciliation ✅ PR #84

- **Offline-first PR detection**: `finishWorkout()` reads existing records from `pr_cache` directly (no network), celebrates immediately, always enqueues `upsertRecords` via offline queue.
- **Optimistic cache update** with replace-by-`recordType` semantics prevents stale/duplicate records across consecutive offline finishes.
- **Post-drain reconciliation**: `SyncService` batches unique userIds from drained `upsertRecords` items, refreshes `pr_cache` from server once per user after the loop. Sentry breadcrumb logged.
- **Backward-compatible `userId`** on `PendingAction.upsertRecords` (`@Default('')`) — pre-14d queued items deserialize safely.
- 15 new tests (1330 total). Key review fixes: batched reconciliation, online save count increment, removed broken divergence comparison.

### 14e: Polish + Edge Cases ✅ PR #85

- **Sign-out cache clear**: `AuthNotifier.signOut()` and `deleteAccount()` call `HiveService.clearAll()` (best-effort — swallowed on failure so Hive I/O never blocks sign-out). `hiveServiceProvider` added for DI/mocking.
- **Start-workout offline guard**: `startRoutineWorkout()` and `_startQuickWorkout()` check `isOnlineProvider`, show snackbar "Starting a workout requires an internet connection", return early. `kOfflineStartWorkoutMessage` shared constant.
- **Auth startup already offline-safe**: `authStateProvider` reads from local Supabase session cache (no network call). `cacheRefreshProvider` skips when offline.
- **E2E boundary**: Playwright can't trigger `connectivity_plus` (OS-level); offline guards covered by widget tests instead. 7 existing E2E tests from 14c cover the testable sync paths.
- 9 new tests (1339 total).

### Out of Scope (defer)

- **Fully offline workout start** (requires `save_workout` RPC upgrade to upsert workout row, OR queueing `createActiveWorkout`).
- Offline edits to routines, profile, or weekly plan — single-user, low-value, high-complexity.
- Full offline-first via PowerSync or Brick — oversized for current product stage.
- Cross-device sync conflict resolution — single-device assumed.

### Risks

| Risk | Mitigation |
|------|------------|
| `save_workout` RPC semantics change (loses replay-safety) | Pin with a migration test + `save_workout` unit test that re-calls with the same payload twice. |
| User assumes offline-start works | Clear messaging on `startWorkout` failure + explicit banner copy. |
| Local PR detection drifts from server | Detection is already deterministic; `pr_cache` is refreshed every `app_opened` + on drain. Drift is narrow. |
| Sync storm after long offline | FIFO + backoff naturally throttles. |
| Cache staleness | `app_opened` refresh + pull-to-refresh escape hatch. |
| Users don't trust "pending sync" | Prominent amber badge + count + tap-to-details. Terminal failure = loud banner. |
| Terminal-failed queue items accumulate | `failed_queue` + support CTA + manual clearance via profile. |
| `finishedWorkoutCount` drifts from server | Reconcile on drain via `_repo.getFinishedWorkoutCount(userId)`. |

### Dependencies on Earlier Phases

- **Phase 13a (observability):** Sentry breadcrumbs + analytics pipeline. Phase 14 emits events through the same plumbing.
- **Phase 12.x (weekly plan):** `WeeklyPlanNotifier` state must remain network-cached for offline plan display; `markRoutineComplete` becomes a queueable action.
- **Phase 7 (personal records):** `PRRepository` reads + `PRDetectionService` power local PR detection.
- **Phase 5 (workout logging):** `save_workout` RPC, `ActiveWorkoutNotifier`, `WorkoutLocalStorage` are the core surface.

### Effort Estimate

- 14a: ~3-4 days (connectivity + 5 read caches + banner + count cache)
- 14b: ~2-3 days (queue model + repo refactor + pending-sync UI + PR/plan enqueue rewiring)
- 14c: ~3-4 days (sync service + backoff + UX + analytics)
- 14d: ~1-2 days (smaller than originally scoped — no extraction, just rewiring)
- 14e: ~2-3 days (edge cases + E2E)

**Total: ~2 weeks, shippable as 3-5 PRs.**

---

## Phase 15: Portuguese (Brazil) Localization

Full pt-BR localization with language switcher in profile settings. Official `flutter_localizations` + `gen-l10n` with ARB files. DB stays English — default exercise/routine content translated client-side via ARB keyed by slug. Locale stored in Hive `user_prefs` (instant offline) + Supabase `profiles.locale` (cross-device). E2E selectors migrated from text-based to locale-independent identifiers.

### Architecture Decisions

1. **i18n approach:** `flutter_localizations` + `gen-l10n` with ARB files. Already have `intl: ^0.20.0`. Type-safe, zero new deps.
2. **DB content:** Keep DB in English. Translate default exercises/routines client-side via ARB keyed by slug. User-created content stays in user's language.
3. **Locale storage:** Hive `user_prefs` key `locale` (instant cold-start) + `locale` column in Supabase `profiles` (cross-device sync).
4. **Locale provider:** Riverpod `Notifier<Locale>` watching Hive, drives `MaterialApp.locale`. Immediate switch, no restart.
5. **E2E selectors:** Migrate from text-based (`name*="English text"`) to locale-independent identifiers via `Semantics(identifier: ...)`. Validate mechanism with Flutter AOM in 15a spike.

### 15a: i18n Infrastructure + E2E Selector Migration (DONE — PR #86)

- Wired Flutter i18n pipeline: `flutter_localizations`, `l10n.yaml`, ARB files (50 keys en + pt), `gen-l10n` Makefile target, `LocaleNotifier` Riverpod provider
- Added `locale` field to `Profile` model + `updateLocale()` repository method + migration `00022_add_locale_to_profiles.sql`
- Migrated ~135 E2E selectors from text-based to `Semantics(identifier: ...)` with `[flt-semantics-identifier="xxx"]` DOM attribute; fixed 14 AOM edge cases (click interception, text merge, viewport culling, GestureDetector→InkWell)
- Widget test harness created (`test/helpers/localized_widget.dart`); widget test migration deferred to 15b
- 1357 unit/widget tests, 155 E2E tests pass

### 15b: Full String Extraction (DONE — PR #87)

- Extracted all hardcoded UI strings into ARB files (396 keys in en + pt, up from ~200)
- Refactored enum `displayName` → `localizedName(l10n)` via `enum_l10n.dart` (5 enums, exhaustive switches)
- Localized `WorkoutFormatters` (date strings, NumberFormat with locale, DateFormat with locale)
- Created `TestMaterialApp` harness, updated 52 widget test files
- 15 dead ARB keys removed per review; 1381 tests + 155 E2E pass

### 15c: Portuguese Translations + Exercise Content (DONE — PR #88)

- All 556 ARB keys translated to Brazilian Portuguese with proper diacritics
- `exercise_l10n.dart`: slug-keyed lookup for 150 default exercise names + 9 routine names
- ARB completeness test (key parity + untranslated value detection)
- ~120 diacritic corrections; "PR" and "Drop Set" kept in English per Brazilian gym convention
- 1400 tests pass

### 15d: Language Picker UI + Persistence — DONE (PR #89)

- PREFERENCES section on ProfileScreen with Language row (own-language display names)
- `LanguagePickerSheet` modal wired to `LocaleNotifier.setLocale()` — instant switch, no restart
- Hive-first + Supabase best-effort sync; `reconcileWithRemote(String)` from app bootstrap
- App.build() listens to `authStateProvider` (not profileProvider) for post-login reconcile — prevents caching AsyncData(null) on a non-reactive currentUserId dependency
- Tests: locale_provider unit (incl. reconcile + remote sync paths), language_picker_sheet widget, profile_screen integration

### 15e: QA + E2E + Overflow Polish — DONE (PR #91)

- `lib/core/format`: `AppNumberFormat` + `AppDateFormat` with explicit locale — `80,5 kg` / `18/04/2026` in pt, `80.5 kg` / `04/18/2026` in en
- `WeightStepper` dialog accepts both `,` and `.` decimal separators for pt-BR native keyboards
- Bottom nav + profile label overflow guards validated at 320dp under pt
- E2E: `setLocale()` helper, `smokeLocalization` (server-seeded `locale='pt'`) + `smokeLocalizationEn` users, 9-test `localization.spec.ts` covering boot-in-pt / live switch / reload persistence / nav rendering
- Tests: 1449 unit+widget pass; 164 E2E pass

### Cultural UX Requirements

- **Decimal:** Comma for pt-BR (`80,5 kg`). `NumberFormat` with locale.
- **Dates:** dd/MM/yyyy for pt-BR. All `DateFormat` calls locale-aware.
- **Weight:** kg default, standard in Brazil. No change.
- **"PR":** Keep untranslated — Brazilian gym culture uses it.
- **Exercise names:** Portuguese primary for defaults. User-created untranslated.

### Overflow Risk Map

| Severity | Widget | Fix |
|----------|--------|-----|
| Critical | Bottom nav labels | `maxLines: 1` + `ellipsis`, test at 320dp |
| High | "Weight Unit" label → "Peso" | Shorter copy or `ellipsis` |
| High | `_StatCard` labels | `maxLines: 1` + `ellipsis` |
| Medium | SnackBar / dialog buttons | SnackBars scroll; buttons full-width |
| Low | Rest timer buttons | Numeric, immune |

### Risks

| Risk | Mitigation |
|------|------------|
| Semantics.identifier + AOM mechanism | Validate in 15a spike before full migration |
| Widget test breakage (missing delegates) | Shared helper + pin `locale: Locale('en')` |
| Enum displayName refactor (~42 call sites) | Mechanical grep-replace, CI catches regressions |
| PT-BR overflow | Proactive `maxLines`+`ellipsis` in 15b + regression in 15e |
| ARB key drift en/pt | Completeness unit test in CI |
| Hive/Supabase locale desync | Hive authoritative, Supabase best-effort |

### Effort Estimate

| Sub-phase | Days |
|-----------|------|
| 15a: Infrastructure + selector migration | 3-4 |
| 15b: String extraction | 4-5 |
| 15c: Portuguese translations + content | 3-4 |
| 15d: Language picker UI | 1-2 |
| 15e: QA + E2E + polish | 2-3 |
| **Total** | **~2.5-3 weeks** |

---

## Phase 15f: Exercise Content Localization (DONE — PR #110)

DB-side exercise content i18n. Replaced client-side ARB localization for default exercises with a dedicated `exercise_translations` table keyed by `(exercise_id, locale)` and a fallback cascade `p_locale → 'en' → any`. Schema scales to N locales without rework.

- **Schema:** 5 migrations (00030 slug + derive trigger; 00031 `exercise_translations` table + RLS; 00032 EN backfill from legacy columns; 00033 150 pt-BR seed rows; 00034 column drop + 4 localized RPCs).
- **RPCs:** `fn_exercises_localized`, `fn_search_exercises_localized`, `fn_insert_user_exercise`, `fn_update_user_exercise` — replace all embedded selects in 4 repositories.
- **Cache:** locale-keyed Hive boxes (`exerciseCache`, `routineCache`, `workoutHistoryCache`, `prCache`); `LocaleNotifier.setLocale` clears all four on switch.
- **Tests:** 1786 unit/widget green; 14 new E2E scenarios A1-G2 across 5 new `*-localization.spec.ts` specs (183/183 full suite); 4 forward invariants (orphaned/missing-en/missing-pt/orphaned-translations) all 0/0/0/0 on staging + prod.
- **Rollback:** `scripts/emergency_rollback_15f.sql` — round-trip verified (apply → rollback → 7 pre-15f invariants → re-apply 5 migrations clean → 4 forward invariants 0/0/0/0). Restores legacy composite unique index + 3 length CHECK constraints. EN data fully recoverable.
- **CI guard:** `scripts/check_exercise_translation_coverage.sh` enforces every default-exercise INSERT ships with both en+pt translation rows in the same PR (recognizes both VALUES-JOIN and SELECT-FROM-exercises patterns). Replaces the old client-side pairing check.
- **Tooling:** `scripts/verify_prod_translation_invariants.sh` is a one-shot manual healthcheck for prod (runs the 4 invariant queries via psql).

**Spec:** `docs/superpowers/specs/2026-04-24-exercise-content-localization-design.md`. **pt-BR glossary:** `docs/superpowers/specs/phase15f-pt-glossary.md`.

---

## Phase 16: Subscription Monetization

> Trial-to-paywall model. No free tier — users get full app during 14-day trial, then subscribe to continue. Gamification progress (Phase 17-18) becomes the retention lever via loss aversion: letting the sub lapse freezes accumulated XP, levels, and streaks behind the paywall.

### Business Model (locked)

- **Monthly:** R$19,90 / $3,99 / €3,99 · **Annual:** R$119,90 / $23,99 / €23,99 (~50% discount vs monthly-equivalent)
- **Currency & reach:** Global availability from day one. Explicit prices set for BRL, USD, EUR. PPP-aware auto-conversion enabled in Play Console for all other countries (uses Play's suggested-pricing-per-country tool). Merchant account location (Brazil) determines payout currency (BRL) and tax jurisdiction — NOT buyer eligibility. Users in any Play-supported country can subscribe.
- **Trial:** 14-day free trial via Play intro offer on both base plans. One trial per Google account (Play-enforced, returning lapsed users go straight to "Subscribe").
- **Gating:** Hard paywall — no feature-tier split. Trial OR active sub → full access. No trial + no sub → paywall-only.
- **No lifetime.** **No installment base plan** at launch (can add post-launch as a second Brazilian base plan without schema changes).
- **Offline grace:** 7 days past server `expires_at` before locking features.
- **Launch blocker:** Merchant account in Play Console not yet created (planned: Brazilian, receives BRL payouts from global sales). All code/infra ships and is testable via closed testing + license-tester accounts before merchant is live; production go-live is gated on merchant setup.

### Architecture (locked)

- **Package:** `in_app_purchase ^3.2.x` (official Flutter plugin over Play Billing Library 7+). No RevenueCat — no vendor-in-the-middle, Supabase Edge Functions replace RC's server.
- **Server validation:** Every purchase token validated server-side via `validate-purchase` Edge Function calling Google Play Developer API `purchases.subscriptionsv2.get`. Zero client writes to entitlement state.
- **Acknowledgement:** Edge Function calls `purchases.subscriptions.acknowledge` within 3 days (Google auto-refunds unacknowledged subs). If acknowledgement fails, do NOT grant entitlement.
- **RTDN:** Google Cloud Pub/Sub push → `rtdn-webhook` Edge Function. Handles all 10 notification types (PURCHASED, RENEWED, RECOVERED, CANCELED, EXPIRED, REVOKED, ON_HOLD, IN_GRACE_PERIOD, PAUSED, DEFERRED). Pub/Sub JWT verified on inbound against Google's public keys.
- **Idempotency:** `subscription_events` audit log with `UNIQUE(purchase_token, notification_type, event_time)` — duplicate RTDNs return 200 immediately.
- **Fallback:** pg_cron reconciliation job every 6h polls `purchases.subscriptionsv2.get` for subs with `expires_at > now() - interval '7 days'` in case Pub/Sub misses events.
- **Entitlement read path:** `entitlements` SQL view derives state from `subscriptions` row; client reads the view only.
- **Offline cache:** Hive box `entitlement_cache` with `cached_at` + `offline_expires_at = server_expires_at + 7d`.
- **Security binding:** `obfuscatedAccountId = supabase_user_id` on every `PurchaseParam` — binds purchase token to the Supabase user. Edge Function validates JWT user_id matches `obfuscatedExternalAccountId` in Play API response.
- **RLS:** users SELECT own rows only; no client INSERT/UPDATE/DELETE on subscription tables. All writes go through Edge Functions using service role.

### Schema

**`subscriptions`** (one row per user, upserted on each event)

```
id, user_id UNIQUE REFERENCES auth.users ON DELETE CASCADE,
product_id, purchase_token, linked_purchase_token,
state (active|canceled|expired|on_hold|paused|revoked),
auto_renewing, in_grace_period, acknowledgement_state,
started_at, expires_at, updated_at
```

**`subscription_events`** (immutable audit log)

```
id, user_id, purchase_token, notification_type, event_time, raw_payload,
UNIQUE(purchase_token, notification_type, event_time)
```

**`entitlements` view** (computed)

```sql
CASE
  WHEN state='active' AND expires_at > now() THEN 'premium'
  WHEN in_grace_period AND expires_at > now() - interval '3 days' THEN 'grace_period'
  WHEN state='on_hold' THEN 'on_hold'
  ELSE 'free'
END AS entitlement_state
```

RLS: SELECT `auth.uid() = user_id` on all three. No client writes. Service role for Edge Function writes.

### User Lifecycle Flow

1. **Signup** → onboarding → `/paywall` (NEW: onboarding now precedes paywall, not home)
2. **Start trial** → Play Billing sheet → user selects payment method → trial active → client calls `validate-purchase` → entitlement granted → home
3. **Trial (14d)** → full app, gamification accumulates (this IS the retention asset)
4. **Day 14** → Google Play auto-renewal → RTDN `SUBSCRIPTION_RENEWED` → `expires_at` extended
5. **Cancel during trial** → state=canceled; access continues until `expires_at`, then paywall. No second trial.
6. **Payment fails** → Google enables 7-day grace → our cache grace (7d) stacks on top → banner prompts user to update payment → if never recovered, state transitions to `on_hold` → paywall.
7. **Lapsed user returns** → paywall only (Google blocks second trial) → XP/levels preserved server-side, accessible only after re-subscribing. **This is the retention moat.**

### Paywall UX (per UI brief)

- Full-screen, same dark theme as rest of app (`#0F0F1A` background, no modal-on-blur)
- Hero claim in `displayLarge` w900 (e.g., "TREINAR SEM LIMITES" / "TRAIN WITHOUT LIMITS")
- Two pricing tier cards side-by-side: annual default-selected with amber `#FFD54F` "MELHOR VALOR" / "BEST VALUE" badge; monthly unselected. Full-card tap area.
- Compact 3-row benefit table (not bulleted icons)
- Primary CTA: full-width 56dp `#00E676` button, "Começar Grátis" / "Start Free Trial"
- Restore purchases as secondary text button
- Fine print below fold: trial end date, easy-cancel link
- Gating pattern: teaser-then-`DraggableScrollableSheet` for inline contextual upsells (NOT padlock + hard lock)

### Sub-phases

#### 16a — Backend foundation — DONE (PR #93)

- 4 migrations (`00023` subscriptions + RLS, `00024` events audit log with `UNIQUE(purchase_token, notification_type, event_time)`, `00025` entitlements view with `security_invoker`, `00026` pg_cron ±7d reconciliation via `net.http_post`). Applied to hosted Supabase.
- 2 Edge Functions: `validate-purchase` (decodes JWT `role` claim for service-role detection; `obfuscatedAccountId` binding; ack within 3d; 200-with-log on Play-ack-OK/DB-update-fail partial failure), `rtdn-webhook` (Pub/Sub JWT verify, all 10 RTDN types, idempotent via UNIQUE).
- Shared `_shared/google_play.ts`: OAuth2 with `androidpublisher` scope, module-scope token + JWK caches, state normalizer.
- 57 Deno unit tests passing (Deno 2.7.12); Flutter test suite unchanged at 1449/1449.
- Manual setup documented in `docs/phase-16a-setup.md` — Google Cloud SA, Pub/Sub topic+push sub, Play Console draft product with BRL/USD/EUR + PPP auto-convert, DB settings `app.settings.edge_functions_url` / `app.settings.service_role_key` for the cron. **User handles these external steps before 16b closed testing.**
- No Flutter code, no `pubspec.yaml` changes.

#### 16b — Client integration + paywall UI + onboarding rewire

- `in_app_purchase ^3.2.x` added to `pubspec.yaml`
- `BillingException` subtype added to `AppException` hierarchy (`userCancelled`, `billingUnavailable`, `alreadyOwned`, `networkError`, `billingConfigError`)
- `HiveService.entitlementCache` box key + init/clear integration
- Freezed models: `Subscription`, `SubscriptionEvent`, sealed `EntitlementState` (Free / Premium / GracePeriod / OnHold)
- `SubscriptionRepository extends BaseRepository` — fetch products, `initiatePurchase` (sets `obfuscatedAccountId`), `restorePurchases`, `validateAndGrant`
- `EntitlementNotifier` (AsyncNotifier) — offline-first read, Hive cache, Realtime subscription to `subscriptions` for post-purchase flash
- `PurchaseNotifier` (AsyncNotifier) — manages `PurchaseUpdatedStream` lifecycle at provider level
- `PaywallScreen`, `SubscriptionSettingsCard` (in Profile), `PaywallBottomSheet` widget
- Onboarding flow rewire: `/email-confirmation` → onboarding → `/paywall` → `/home` (was: straight to `/home`)
- l10n keys added to `app_en.arb` + `app_pt.arb` (paywall copy, CTAs, trial/grace messaging)
- Unit tests: entitlement state transitions, offline cache grace logic, 7-day boundary conditions
- Widget tests: paywall renders, tier selection state, restore flow, error states

#### 16c — Hard gate enforcement + E2E refactor

- `EntitlementGate` widget wraps app shell; Premium/GracePeriod → child, else redirect to `/paywall`
- `app_router.dart` redirect guard: authenticated + no entitlement → `/paywall`
- `/paywall` as top-level route (outside ShellRoute, like `/onboarding`)
- `/subscription-manage` deep-links to Play Store subscription management
- **E2E test harness:** override `subscriptionRepositoryProvider` → `FakeSubscriptionRepository` returns active-trial state so existing 145 tests continue passing unchanged
- New E2E spec `specs/subscriptions.spec.ts`: paywall-after-onboarding, no-paywall-when-trial-active, paywall-after-trial-expired, restore-flow
- Acceptance: full suite green; no real purchase required

#### 16d — Analytics, hardening, launch-readiness

- Analytics events added to sealed `AnalyticsEvent`: `paywall_viewed`, `trial_started`, `subscribe_completed`, `subscription_cancelled`, `subscription_restored`, `grace_period_entered`, `subscription_expired`
- Sentry breadcrumbs on every purchase state transition
- Grace-period banner in app shell (red left-border variant, tap → Play Store billing management)
- pg_cron reconciliation monitoring + alerting
- Privacy Policy + ToS updates with subscription-specific clauses
- Play Store listing prep: subscription disclosure text, screenshots
- **Launch-readiness checklist** (gated on external steps):
  - [ ] Brazilian merchant account active in Play Console
  - [ ] Explicit prices set for BRL + USD + EUR; PPP auto-conversion enabled for all other countries via Play's suggested-pricing tool
  - [ ] Spot-check price rendering in top-10 target markets (US, UK, DE, FR, ES, PT, MX, AR, CA, AU) — no weird auto-converted numbers
  - [ ] Production Pub/Sub topic + push subscription → live Edge Function URL
  - [ ] End-to-end validation with license-tester: subscribe → cancel → re-subscribe cycle
  - [ ] Brazilian test account confirms BRL rendering; US test account confirms USD; EU test account confirms EUR
  - [ ] ToS + Privacy Policy live on Play Store listing

### Acceptance Criteria (full phase)

- Every purchase token validated server-side before entitlement grant
- Zero client-side writes to `subscriptions` / `subscription_events` / entitlement fields
- RTDN handled idempotently for all 10 notification types
- 7-day offline grace window enforced: app functional for 7 days past server expiry on loss of connectivity, locks on day 8
- Every paywall state transition fires analytics event
- Trial starts exactly once per Google account (enforced by Google, verified in our flow)
- Paywall renders correctly in `en` and `pt-BR` at 360dp minimum width
- `make ci` green; full E2E suite green (145 existing + ~4-6 new = ~150 tests)
- No UI flash between app launch and paywall/home decision (entitlement check resolves before first non-splash frame)

### External dependencies / open items

- **Brazilian merchant account** — user to set up in Play Console before 16d "go live" checklist completes
- **Google Cloud project** for Pub/Sub — user confirms existing or creates new
- **Legal review** — Privacy Policy + ToS subscription clauses (not blocking code, blocking Play Store submission)
- **Pricing localization** — confirm BRL prices render in all test accounts before launch
- **Analytics dashboards** (follow-up, not 16d-blocking): Supabase SQL views for trial conversion, churn, grace recovery

---

## Phase 17: Gamification Foundation

> RPG progression tightly coupled to real training data — "your strength IS your character." Refined from the Phase 17 v1 spec after PO + UX post-mortem of GymLevels, Arise, and competitor teardown (2026-04-22).

### Retention Dependency (from Phase 16 pricing research) — UPDATED for RPG v1

Our annual price ($23.99 USD) matches Hevy; Hevy offers a permanent freemium tier. A user comparing the two at trial-end will ask "why pay when Hevy is free?" The answer has to be delivered **inside the 14-day trial**: progression must feel real within the first 2–3 sessions. **Under RPG v1** (Phase 18) this becomes: visible body-part Rank progress on the character sheet within the first session, the first rune awakening on first attributed set per body part, and at least one Rank threshold crossed by mid-trial. The Phase 17 LVL curve (`xpForLevel(n) = floor(300 * pow(n, 1.3))`) is **placeholder** — the new pacing is governed by the Rank curve in design spec §6 (`xp_to_next(n) = 60 × 1.10^(n-1)`), validated by 260-week simulation: Rank 1→20 in ~8 weeks of consistent training. A trial user hits multiple body-part Rank-ups inside 14 days.

### Cross-Phase: Paywall Personalization Hook (consumed by Phase 16b) — UPDATED for RPG v1

When Phase 16b unparks and wires `PaywallScreen`, the paywall MUST display the user's actual progression — under RPG v1 that becomes their **Character Level + dominant body-part Rank + active title**, not the legacy `GamificationSummary` shape. Phase 18b exposes `character_sheet_provider` (composes `rpg_progress_provider` + active title + class), which 16b reads. The legacy `xp_provider` from 17b is preserved as a transitional read-through during Phase 18a→b implementation but slated for removal once the character sheet provider is the canonical source. **This callout is load-bearing: do not let 16b drift back to a stock paywall.**

### Design Principles (non-negotiable)

- Every mechanic must be defensible with real training logic. No arbitrary dopamine.
- Gamification lives in the post-workout overlay and profile — never interrupts logging.
- No punishment for rest days, no streak anxiety, no confetti, no particle spam.
- Beginners see only XP bar + LVL for the first 30 days; stats panel is behind a "more" expand.
- Stats normalized to personal best (0–100), not population norms.
- Variable rewards are tied to **real behavior** (PR, milestone, comeback), never pure chance. No loot boxes.
- Milestones are **signals** (geometric marks), not collectible badge walls.

### Build Order (historical — preserved for archeology)

1. **17.0c (DONE)** — Arcane Ascent Material 3 theme + 12-token palette + app icon. Foundation visual surface, retained.
2. **17b (DONE)** — Placeholder XP + Saga Intro Overlay infra. Saga Intro Overlay is **kept** as the rebrand-into-saga ritual; placeholder XP math + the `xpForLevel` curve are slated for replacement by Phase 18a.
3. **17a / 17c / 17d / 17e — SUPERSEDED.** All four sub-phases are absorbed into or dropped by the Phase 18 RPG v1 design (see below). Original specs remain in git history.

Phase 18 (RPG v1) is now the canonical gamification plan. See `docs/superpowers/specs/2026-04-25-rpg-system-v1-design.md` for the full design and §"Phase 18: RPG System v1" below for the implementation decomposition (18a-18e).

---

### 17.0: Visual Language Foundation — SUPERSEDED (PR #101, merged 2026-04-23; torn down in 17.0c 2026-04-23)

Pixel-art visual system shipped in PR #101 (3 days on main). Post-ship evaluation surfaced unsolvable issues with AI-gen pixel asset quality (invader blobs, black scatter, palette drift, fused frames) and the aesthetic itself polarized users who didn't self-identify as retro-game-literate. **Verdict:** full rollback + rebuild on Material Design with the "Arcane Ascent" direction. See §17.0c for the replacement spec.

What was in PR #101 (for git history): 20 palette tokens on `AppColors`, Press-Start-2P font, `PixelImage`/`PixelPanel` widgets, `MuscleGroup`/`EquipmentType` migrated to `String iconPath`, `scripts/check_hardcoded_colors.sh` lint. 1468 tests. All of this is being torn down in 17.0c.

---

### 17.0c: Arcane Ascent Material Migration — DONE (PR #105, merged 2026-04-23)

- **Teardown + rebuild in one PR.** Pixel-art system (PR #101) fully excised — 63 PNGs, `PixelImage`/`PixelPanel`, Press-Start-2P, `palette_tokens_test`, `check_hardcoded_colors` pixel allowlist all deleted. Replaced with Material 3 + Arcane Ascent palette (12 tokens: `abyss / surface / surface2 / primaryViolet / hotViolet / heroGold / textCream / textDim / success / warning / error / hair`) per Direction B of `tasks/mockups/material-saga-comparison-v2.html`.
- **Foundation files:** `lib/core/theme/app_theme.dart` (Arcane palette + `AppTextStyles` via `google_fonts`), `lib/core/theme/app_icons.dart` (20 inline-SVG icons, side-view barbell lift motif, nullable `color:` param falls back to `IconTheme`), `lib/shared/widgets/reward_accent.dart` (sole sanctioned emitter of `heroGold`), `scripts/check_reward_accent.sh` (grep-gate wired into `make analyze`, opt-out via `// ignore: reward_accent — <reason>`). Rajdhani + Inter TTFs bundled under `assets/fonts/` — `allowRuntimeFetching = false` in `test/flutter_test_config.dart` so google_fonts never CDN-fetches in prod or tests.
- **Migration surfaces:** router nav tabs (hotViolet active, textDim idle) + `_ActiveWorkoutBanner`, splash, exercise list empty state, home `_LvlBadge`, saga intro overlay 3-screen reskin (Hive first-open gate from PR #103 untouched — wrapped in `RewardAccent` for step-3), workout detail trophy, progress chart PR ring. `_LvlBadge` XP-gain animation deferred to 17e per original scope.
- **Tests:** 1663 passing (+121 net: `arcane_theme_test`, `app_icons_test` at 24/40/64 dp with IconTheme fallback, `reward_accent_test`, `nav_icon_wiring_test`). `dart analyze --fatal-infos` clean. Both gate scripts clean. E2E full suite green (25m33s — selectors unchanged; visual-only migration held).
- **Stage 6 app icon** shipped in PR #106 (2026-04-24): user picked variant 3 (rune + barbell composite with four-point hero-gold star core). Full plate at `assets/app_icon/arcane_sigil_1024.png` (iOS / Play Store / web) + chroma-keyed transparent foreground at `assets/app_icon/arcane_sigil_foreground.png` for Android adaptive (66% safe zone). `flutter_launcher_icons` regenerated with `adaptive_icon_background: "#0D0319"` + web manifest colors swapped to Arcane (`#0D0319` / `#B36DFF`). Installed to Galaxy S25 Ultra for on-device verification.
- **Impact on later sub-phases:** Pixel asset-consumption schedule in obsolete §17.0 is void. 17a (PR celebration) already has a `TODO(phase17a)` annotation in `pr_celebration_screen.dart` flagging the `RewardAccent` flash migration. 17c/d/e consume `AppIcons` and SVGs at sub-phase start.
- **Stage 7 (17.0d polish)** shipped in PR #107 (2026-04-24): 13 Material icons migrated to monoline SVGs — 7 new `MuscleGroup` glyphs (`app_muscle_icons.dart`), 6 new `EquipmentType` glyphs (`app_equipment_icons.dart`; barbell reuses `AppIcons.lift` intentionally), plus nav + editor chrome (`close`, `edit`, `levelUp` trophy). PR celebration flash switched from violet → hero gold (scarcity rule enforced via `RewardAccent`). `AppIcons.render` now defaults `excludeFromSemantics = (semanticsLabel == null)` to match Material `Icon` — fixed an AppBar `header` regression that broke the `role=heading[name*="Workout —"]` E2E selector on web. 1744 tests passing.

---

### 17b: XP & Level System + Retroactive Backfill — DONE (PR #103, merged 2026-04-23)

- **Data layer shipped:** migrations `00028_user_xp.sql` (tables `user_xp`+`xp_events`, RLS owner-read, `award_xp` RPC `SECURITY DEFINER`) and `00029_retroactive_xp.sql` (`retro_backfill_xp(uuid)` idempotent procedure). Both applied to hosted Supabase post-merge.
- **Domain:** `XpCalculator` implements the base/volume/intensity/PR/quest/comeback formula; `xpForLevel(n) = floor(300 * pow(n, 1.3))` precomputed to `kXpCurve[1..100]`; 7 ranks Rookie→Diamond. `xpProvider` AsyncNotifier emits `GamificationSummary` with optimistic update on `awardForWorkout`. Workout save wires XP award in `active_workout_notifier.finishWorkout()` (post-PR detection, online only — retro is the offline safety net).
- **UI:** pixel-art `SagaIntroOverlay` (3 screens, Begin-to-dismiss, `PixelImage`+`PixelPanel` framed, no Material chrome). `SagaIntroGate` wraps authenticated ShellRoute — runs retro backfill once per user, renders overlay when unseen, persists `saga_intro_seen` via Hive helpers. Minimal `_LvlBadge` placeholder wired on HomeScreen for E2E; full styling lands in 17e.
- **Tests:** 1544/1544 passing. Unit (62 cases: xp_calculator, level_curve, xp_repository, gamification_summary). Widget (saga_intro_overlay 9 cases, saga_intro_gate 5 cases, lvl_badge). E2E `specs/gamification-intro.spec.ts` (@smoke, 3 tests covering first-run overlay, no re-show on reload, LVL badge visible). `login()` helper auto-dismisses overlay for downstream tests via `dismissSagaIntro` option.
- **Key decisions / gotchas:** XP award lives in notifier (not repo) because PR detection already runs there. Hive `saga_intro_seen` is per-user keyed, persists across reloads in same browser context. `testWidgets` + `Hive.box.put` requires `tester.runAsync` wrappers — documented in `feedback_hive_testwidgets.md` memory.

---

### 17a: Celebration Overlay + Active Logger Hardening — SUPERSEDED by Phase 18 RPG v1

The celebration-overlay choreography conceptualized here (sequential XP / PR / LEVEL-UP zone reveals) is rebased into **Phase 18c** as the rank-up + title-unlock overlay sequencer, now fed by real Phase 18 XP math instead of placeholder. Active-logger hardening (mid-session PR chip, XP accumulator whisper, finish-workout button placement) remains directionally correct and is folded into 18c's UI work — see Phase 18c file plan. Full content preserved in git history (this file pre-2026-04-25).

---

### 17c: Weekly Streak + Comeback Bonus — SUPERSEDED by Phase 18 RPG v1

The "saga is permanent, never decays" framing of Phase 18 replaces the weekly-streak loop. Vitality (per §8 of the design spec) is the new conditioning signal — asymmetric rebuild-fast / decay-slow EWMA on real volume. There is no streak counter, no comeback multiplier, no week-strip in the new model. Returning users are visually rewarded by their Vitality runes re-igniting as they retrain, not by an XP multiplier flag. Original spec preserved in git history.

---

### 17d: Character Sheet + Milestone Signal — SUPERSEDED by Phase 18 RPG v1

Replaced by Phase 18b (character sheet) + Phase 18d (stats deep-dive). The new character sheet renders six body-part Ranks (1-99) with rune sigils + a derived Character Level + an active title — not LVL/XP/rank-glyph/highlights/milestones. The milestone-timeline concept is deferred indefinitely (Titles in Phase 18 cover the same identity-marker need without a separate detector + table). Original spec preserved in git history.

---

### 17e: Home Recap + First-Week Quest Stub + LVL Line — SUPERSEDED by Phase 18 RPG v1

Home recap card / best-set chips / volume delta retained directionally but become a Phase 19 nice-to-have. The hardcoded first-week quest is dropped entirely (quests engine moved to deferred Phase 19, see "Deferred RPG v2" backlog). Home subtitle's LVL line will read from Phase 18's derived Character Level once 18b ships — no separate rewire required here. Original spec preserved in git history.

---

## Phase 18: RPG System v1 — the canonical RPG plan

> **Source of truth:** `docs/superpowers/specs/2026-04-25-rpg-system-v1-design.md`. That spec carries the math, schema, attribution map, rank curve, vitality formula, class lookup, and 90-title catalog. This section translates the spec into shippable sub-phases. **All decisions in the design spec supersede any earlier RPG/gamification plan in this file.**

### Mental model (one paragraph)

Two numbers per body part: **Rank** (1-99, monotonic, the lifetime saga) and **Vitality** (0-100%, asymmetric EWMA on real volume — rebuild fast at τ=2wk, decay slow at τ=6wk; peak permanent). Six body parts in v1 (chest/back/legs/shoulders/arms/core). **Character Level** is derived: `floor((Σranks − 6) / 4) + 1`, capped at 148 theoretical max. **Class** is derived from current Rank distribution (Initiate / Berserker / Bulwark / Sentinel / Pathfinder / Atlas / Anchor / Ascendant). **Titles** unlock at Rank thresholds (78 per-body-part + 7 character-level + 5 cross-build = 90). Cardio is a v2 deferral — schema accepts it day one, no UI surface.

### Foundation already shipped (Phase 17)

- **17.0c (PR #105/#106/#107)** — Arcane Ascent Material 3 theme + 12-token palette + app icon. The visual surface RPG paints on.
- **17b (PR #103)** — `xp_events` table, `award_xp` RPC, `retro_backfill_xp` procedure, `XpCalculator` (placeholder formula `xpForLevel(n) = floor(300 * pow(n, 1.3))`), Saga Intro Overlay, `SagaIntroGate` (Hive first-open gate). **Status:** infrastructure stays; XP math is **placeholder** — Phase 18a replaces the formula and rebases existing `xp_events`/`user_xp` rows via the new backfill (see 18a migration plan). The overlay choreography is reusable as-is for rank-up/title-unlock events in 18c.

### Sub-phase decomposition

```
18a  Schema + XP engine + backfill          (PR 1; foundation, no user-facing UI changes)
 │
18b  Character sheet + rune sigils UI       (PR 2; depends on 18a)
 │
18c  Mid-workout overlay rewire + titles    (PR 3; depends on 18a + 18b)
 │
18d  Stats deep-dive + Vitality nightly job (PR 4; depends on 18a)
 │
18e  Class system + cross-build titles + QA (PR 5; depends on 18a-d)
```

18b and 18d can run in parallel after 18a if dispatched to different agents. 18e is the integration + final-QA closer.

---

### 18a: Schema + XP engine + backfill (RPG v1 foundation) — DONE (PR #112)

- Schema landed: `xp_events`, `body_part_progress`, `exercise_peak_loads`, `earned_titles`, `backfill_progress` (RLS owner-only); `xp_attribution` JSONB on `exercises` with IMMUTABLE helper + CHECK; `character_state` view with `WITH (security_invoker = true)` so RLS is honored.
- XP hot path: `record_session_xp_batch(workout_id)` single-pass (float8 inner loop, numeric(14,4) at storage boundary) — p95 = 11ms on 100-set payload via EXPLAIN ANALYZE (38× speedup over the original per-set PL/pgSQL FOR loop). Diagnostic single-set entry `record_set_xp(set_id)` retained for chunked backfill + concurrency tests; doc-commented as one-set-per-call only.
- Backfill `backfill_rpg_v1(user_id)` is a FUNCTION returning `(out_processed, out_total_processed, out_is_complete)` looped from `RpgRepository.runBackfill` (PostgREST tx-wrap + DEFINER COMMIT incompatibility forced FUNCTION-with-driver-loop instead of PROCEDURE-with-internal-COMMITs); cursor uses the same `(started_at, set_id)` total ordering as the chunk fetch.
- 17b `user_xp` / `award_xp` / `retro_backfill_xp` dropped; `XpRepository` shim now reads `character_state.lifetime_xp` so the 17b LVL badge + saga intro overlay keep rendering during the 18a→18b transition. `XpCalculator` placeholder + `xpForLevel` curve flagged for 18e cleanup (still live for `active_workout_notifier`).
- Bug fixes landed in same PR: BUG-RPG-001 (re-save reversal pattern in `save_workout` — sum prior xp_events per body_part, decrement, recompute rank, then cascade-delete), BUG-RPG-002 (cursor ordering parity in chunk loop), BUG-RPG-003 (numeric(14,4) widening for 0.0001 parity), BUG-RPG-004 (batch refactor + monotone-peak `WHERE EXCLUDED.peak_weight > ...` guard so `updated_at` is honest).
- CI infra: `@Tags(['integration'])` + `dart_test.yaml` + `--exclude-tags integration` in `.github/workflows/ci.yml` and `Makefile` so remote CI doesn't try to run integration tests without a live Supabase. New `make test-integration` target for opt-in.
- Tests: 1885 unit/widget passing, 17/17 integration (incl. 100-set perf bench), 6/6 in `test/e2e/specs/rpg-foundation.spec.ts` (E1–E6 of the bulletproof e2e matrix). Migration applied to hosted Supabase post-merge.

**18a-deliverable e2e matrix rows shipped (the rest land in 18b/c as UI lands):** E1 backfill on first login, E2 first-workout XP applied, E3 re-save no double XP (BUG-RPG-001 sentinel), E4 XP accumulates across workouts, E5 saga intro gate regression, E6 compound body-part attribution (squat: legs 0.80 / core 0.10 / back 0.10 ± 5%, 1-set baseline to avoid per-body-part novelty decay drift).

---

### 18b: Character sheet + rune sigils UI — DONE (PR #113)

- **Profile tab → Saga.** `/profile` now resolves to `CharacterSheetScreen`; legacy account/locale/sign-out/manage-data moved to `/profile/settings` reachable via gear icon. Tab label: "Saga" (en + pt-BR). `_LvlBadge` placeholder from 17b deleted.
- **Layout:** rune halo + Lvl 56sp + class badge slot + active title pill → hexagonal Vitality radar (CustomPainter, 6 axes, fill opacity ∝ rank/99) → six asymmetric codex rows (trained expanded, untrained collapsed) → dormant Cardio row → three full-width codex nav rows (Stats / Titles / History). Stats + Titles route to `SagaStubScreen` (filled by 18d/18c); History routes to existing `/history`.
- **Four rune halo glow states** per spec §8.4: Dormant (12% opacity, slow rotate), Fading (cold `primaryViolet` ring, breathing pulse), Active (static `hotViolet`, two-layer shadow), Radiant (`heroGold` via `RewardAccent`, sweep highlight, +10% size, `HapticFeedback.lightImpact()` once on first paint).
- **Class badge ships day-1** with placeholder "The iron will name you." / "O ferro lhe dará um nome." (real class derivation deferred to 18e). First-set-awakens banner renders only when `lifetime_xp == 0`; disappears after first online workout via `ref.invalidate(rpgProgressProvider)` in `ActiveWorkoutNotifier._finishOnline` (review-found Blocker, fixed in `055a4e3`).
- **Tab re-tap fix** (knock-on benefit): `_ShellScaffold.onDestinationSelected` now calls `context.go(target)` unconditionally — previously the `current == target` guard silently dropped re-taps when on a pushed sub-route because `RouteMatchList.uri` ignores `ImperativeRouteMatch` entries. Affects all four branches.
- **Tests shipped:** 1919 unit/widget pass (+17 new RPG tier including 4-test Radiant haptic group + 2 vitality_radar goldens at `test/widget/features/rpg/widgets/goldens/`); new `test/e2e/specs/saga.spec.ts` (S1–S7 `@smoke`, all green); full Playwright suite 196/197 → 197/197 after the router fix unblocked the locale-switch flow.
- **L10n** added 9 new keys (`sagaTabLabel`, `classSlotPlaceholder`, `dormantCardioCopy`, `firstSetAwakensCopy`, `statsDeepDiveLabel`, `titlesLabel`, `historyLabel`, `comingSoonStub`, `settingsLabel`) — full en + pt-BR coverage.

---

### 18c: Mid-workout overlay rewire + title unlocks — DONE (PR #114)

- Shipped `CelebrationPlayer` orchestrator + `CelebrationQueue` sequencing rank-up → level-up → title (1.1s each, 200ms gap), reusing the 17b overlay scaffold but driven by Phase 18 XP deltas.
- 78 per-body-part titles in `assets/rpg/titles_v1.json` (en + pt-BR via `.arb`), unlock detection client-side, `earned_titles` rows persisted via UPSERT through `titles_repository.dart`. Cross-build + character-level titles still queued for 18e.
- Title unlock half-sheet renders post-workout with "Equip" CTA (single active title enforced by `earned_titles_one_active` unique index). Sheet `isDismissible: true` per spec §13.2. Migration `00041_earned_titles_insert_policy.sql` adds the missing `earned_titles_insert_own` RLS policy.
- Overflow card (spec §13.2 "more events than time") holds 4s with localized "Tap to continue" hint; tap routes to `/profile` via new `CelebrationPlayResult { userTappedOverflow }` contract. AOM tap dispatch fixed by promoting outer `Semantics` to `container + button + onTap` (mirrors `GradientButton`).
- Use-after-dispose hardening: `_ActiveWorkoutBodyState` captures `shouldPrompt` and `rootContext` before the finish `await`; post-disposal callbacks (equip-title, plan-prompt) read providers via `ProviderScope.containerOf(rootContext)` instead of the disposed `ref`. `_isFinishHandled` file-level guard prevents postFrameCallback from racing celebration playback.
- Tests: 4 new widget tests in `celebration_player_test.dart` (queue sequencing, overflow auto-dismiss vs tap, sheet dismissal); E2E `specs/rank-up-celebration.spec.ts` with dedicated seeded users for rank-up, title-unlock, and overflow-tap-to-saga paths; full regression run (184/204 first-attempt pass — 8 hard failures + 12 flakies all pre-existing baseline, captured in `test/e2e/FLAKY_TESTS.md`).
- Active-logger chrome polish kept scoped per spec §13.2: mid-session PR chip + finish-button placement only. XP whisper deferred to 18d alongside Vitality visual states.

---

### 18d: Stats deep-dive + Vitality nightly job + visual states

Split into two PRs because the cron should populate real EWMA values before the deep-dive UI ships — opening the screen on day 1 to flat-zero charts would feel broken. **18d.1 (backend + mapper) merged 2026-04-29 as PR #118; 18d.2 (UI) merged 2026-04-29 as PR #119. Phase 18d complete — next step is 18e (class system + cross-build titles).**

#### 18d.1: Vitality nightly job + state mapper foundation — DONE (PR #118)

- **Migration `00042_vitality_cron.sql`** applied to hosted: `vitality_runs (user_id, run_date)` PK idempotency table (RLS owner-SELECT), `pg_cron` schedule `vitality_nightly_03utc` at `0 3 * * *`, partial index `body_part_progress_vitality_ewma_nonzero_idx ON (user_id) WHERE vitality_ewma > 0` keeps the nightly UNION query within spec §12.3 budget at scale.
- **Edge Function `vitality-nightly`** deployed (v1, ACTIVE on hosted): service-role-only auth (anon/anon-key/end-user JWTs all 401 with constant-time JWT compare), asymmetric EWMA per spec §8.1 (`ALPHA_UP_TAU_2W = 1-exp(-7/14) ≈ 0.3935` rebuild, `ALPHA_DOWN_TAU_6W = 1-exp(-7/42) ≈ 0.1535` decay), INSERT-first idempotent dedup. Optional `{ chunk: 0..9 }` body parameter for `user_id % 10` chunking; cron currently submits a single un-chunked invocation (volume nowhere near §12.3 ceiling).
- **Architectural fix mid-flight:** active-users pool now UNIONs `xp_events past 7d` with `body_part_progress.vitality_ewma > 0` so deload weeks still get decay applied (spec §8.2 compliance — without the second branch, a user who deloaded to zero would be invisible to the nightly job and EWMA would freeze).
- **`VitalityStateMapper`** at `lib/features/rpg/domain/vitality_state_mapper.dart` is now the single source of truth for spec §8.4: `fromPercent(pct)` (canonical, 0..1 fraction; `≤0 → dormant`, `(0, 0.30] → fading`, `(0.30, 0.70] → active`, `(0.70, 1.0] → radiant`), `fromVitality({ewma, peak})` (guards `peak ≤ 0 → dormant`, else dispatches). Owns the `bodyPartColor` Map (chart-line / halo / progress-bar palette, locked once — `heroGold` reserved for state=radiant only) plus `borderColorFor / haloColorFor / progressBarColorFor / localizedCopy` lookups. Existing `VitalityStateX.fromVitality(ewma, peak)` extension delegates to mapper (back-compat shim).
- **Latent bug fixed:** the prior `VitalityStateX.fromVitality` compared raw EWMA values (volume-derived, thousands) to literal `30/70`. Masked because `record_set_xp` doesn't update `vitality_ewma` yet — would have manifested as soon as the nightly job populates real values. Mapper now normalizes via `VitalityCalculator.percentage(ewma, peak)` first.
- **L10n** added 4 keys (en + pt) for state copy: `vitalityCopyDormant` ("Awaits your first stride."), `vitalityCopyFading` ("Conditioning lost — return to the path."), `vitalityCopyActive` ("On the path."), `vitalityCopyRadiant` ("Path mastered."). Render only on stats deep-dive screen — character sheet stays number-free + copy-free per spec §8.4 + §13.3.
- **Tests:** 2028/2028 unit+widget, 9/9 integration (4-week steady rebuild within 5% of closed-form per spec §18 acceptance #6, asymmetric α verified, idempotency × 2, end-user JWT 401 reject, UNION-pool decay pin). Mapper boundary tests at exact 0/0+ε/0.30/0.30+ε/0.70/0.70+ε/1.0 + defensive (>1.0, <0).
- **2026-05-04 patch:** added `VitalityState.untested` variant for `peak == 0` body parts. Decouples "never trained" (display: `—`) from "conditioning decayed" (display: `0%`). New l10n key `vitalityCopyUntested`. Per PO + UI/UX consensus — no math/cron change.

#### 18d.2: Stats deep-dive screen at `/saga/stats` — DONE (PR #119)

- **Route + nav** wired: `/saga/stats` reachable from character sheet's Stats codex row; replaces prior `SagaStubScreen` mount. Character sheet stays number-free (sentinel test in `character_sheet_screen_test.dart` blocks `%` regressions).
- **`statsProvider`** at `lib/features/rpg/providers/stats_provider.dart` — single source of truth hydrating `StatsDeepDiveState` (Freezed) from `body_part_progress` + `xp_events` + `exercise_peak_loads`. Cardio peaks now excluded at source (`_muscleGroupToBodyPart(cardio)` returns `null`) so v1 cardio gate doesn't allocate-then-drop; structural fix carries forward to Phase 19.
- **Three spec amendments locked in tests** (PO + UX critic, override original §13.3): (1) no activity gate — empty state via data shape, not a wall; (2) hybrid X-axis — narrow window (first activity → today) for <30 days of history, full 90-day window otherwise; (3) ghost lines `AppColors.textDim` @ 30% opacity 1sp + selected line vivid `bodyPartColor` 2.5sp + terminal dot, plus all rows are raw `Row+Padding+Divider(surface2)` (no `ListTile`).
- **Layout:** AppBar → trend chart (with `liveVitalitySectionHeading` anchoring chart→table junction) → live Vitality table → Volume & Peak → Peak Loads. Four widgets factored: `vitality_table.dart`, `vitality_trend_chart.dart`, `peak_loads_table.dart`, `_VolumePeakTable` (private to screen). New `AppTextStyles.sectionHeader` token replaces inline `fontSize: 12` overrides.
- **Tests:** 2081 unit + widget pass (+53 net: provider 16, screen 8, vitality table 9, trend chart 9, peak loads 8, character sheet sentinel +1, plus cardio v1-gate). E2E `specs/saga.spec.ts` extended with S8–S11 + 6 new `SAGA.*` selectors; full saga spec passes 11/11 standalone, 17/17 combined with rpg-foundation.
- **L10n:** 13 new keys with full en + pt coverage (`statsDeepDiveTitle`, `vitalityTrendHeading`, `vitalityTrendHeadingShort`, `liveVitalitySectionHeading`, `volumePeakSectionHeading`, `peakLoadsSectionHeading`, `peakLoadsEmpty`, `weeklyVolumeUnit`, `oneRmEstimateLabel`, `chartXLabelToday`, `chartXLabel90DaysAgo`, plus the "1RM est." label and weekly-volume unit suffix).

---

### 18e: Class system + cross-build titles + final QA pass — DONE (PR #120)

- **Class system (spec §9):** `class_resolver.dart` (pure `resolveClass(Map<BodyPart,int>)`) with §9.2 resolution order — `max < 5 → Initiate; min ≥ 5 ∧ spread ≤ 30% → Ascendant; else dominant lookup` + alphabetical tie-break. 8 classes (Initiate, Berserker, Bulwark, Sentinel, Pathfinder, Atlas, Anchor, Ascendant). Wired into `classProvider` watching `rpgProgressProvider`; two-tier `ClassBadge` (Initiate quieter, others vivid; asymmetric sigil radius `4/10/10/4`).
- **Title catalog (spec §10):** `Title` refactored to sealed Freezed union (`BodyPartTitle` / `CharacterLevelTitle` / `CrossBuildTitle`) keyed by `kind` discriminator. 7 character-level + 5 cross-build = 90 titles total in v1. Display copy in `.arb` keyed by slug (48 new keys en+pt). `assets/rpg/titles_character_level.json` + `titles_cross_build.json` ship the structural data.
- **Detection + retroactive backfill:** `title_unlock_detector.dart` extended with `detectCharacterLevel` + `detectCrossBuild` (half-open `(old, new]` semantics); `celebration_event_builder.dart` orchestrates all three with cumulative `earnedSoFar` guard. `cross_build_title_evaluator.dart` (5 predicates: pillar_walker, broad_shouldered, even_handed, iron_bound (per-track ≥ 60), saga_forged) mirrored by SQL `evaluate_cross_build_titles_for_user(uuid)` in `supabase/migrations/00043_cross_build_titles_backfill.sql` for retroactive awarding.
- **Tests:** 65 net new (2183 / 2183 passing) — class_resolver (17), cross_build_evaluator (21), class_provider pin (6), detector extension (11→28), builder orchestration (8→12), class_badge styling. E2E: T1/T2/T3 (`title-equip.spec.ts`) + S12 (class label cross in `saga.spec.ts`).
- **Notable Phase 18e fix:** `titles_screen.dart` Semantics wrappers required `container: true` so Flutter web's AOM doesn't elide identifier-only nodes (root cause of CI E2E flake — a real bug masked by local smoke not running the regression suite, surfaced by the new T2/T3 tests).

Completes the **RPG v1 arc** (18a→18e). Cardio is v2 (Phase 19); Wayfarer class deferred with it.

---

### Anti-patterns retained from prior Phase 17/18 (still binding for RPG v1)

The 25-item list below was authored for the superseded 17/18 plan but every item still applies to RPG v1. Re-confirmed against design spec §15 (no premium gating), §13.5 (no leaderboards/social), §13.3 (no population-relative comparisons), §8.4 (no streak flames). Item #11 (no daily streaks) and #12 (no class XP multipliers — class is cosmetic-only) align directly with spec §9 + §13.

---

### Anti-Patterns (Explicitly Banned — 25 items)

1. Confetti or particle spam.
2. Streak flames or emoji (🔥, 💪, 🏆, etc.) — geometric marks only.
3. Badge walls / grid collections — milestones are a vertical timeline, capped at 20.
4. Locked badge states ("earn this!") — nothing ever shows locked progress visuals.
5. Multiple progress bars on home — LVL line only.
6. Level-gated features — every feature is available at LVL 1.
7. Push notification streak anxiety — no nudges "don't lose your streak."
8. XP in persistent header — XP lives on profile and in celebration overlay only.
9. Animated badges / shimmering collectibles.
10. Global leaderboards — no population comparisons in v1.
11. Punitive daily streaks — weeks only, and missing never punishes.
12. Class XP multipliers — no class system in v1 (deferred to Phase 19).
13. Social infrastructure — no friends/feeds in v1.
14. RED color for missed days (week strip neutral grey only).
15. Loot boxes / pure-chance rewards — all rewards tied to real behavior.
16. Time-pressure "daily quest resets in 4h" copy — quests are weekly, expire gracefully.
17. Fake urgency banners ("Only today!") in gamification surfaces.
18. Population-relative stats ("you're stronger than 80% of users") — personal-best only.
19. "Paywall tease" framing of gamification — every XP/LVL/quest works on free trial.
20. Generic Material list views for milestones or quests — must use bespoke typography + chrome.
21. Hardcoded colors outside `AppColors` — lint-enforced in 17.0.
22. Overlays that block logging — celebration fires post-save, mid-session chips are non-modal.
23. Vanilla "Recent workouts" list on home — recap card is bespoke, data-forward.
24. Features behind purely cosmetic "level requirements."
25. Any retention mechanic that lies to the user ("LVL 5 unlocks!" when it doesn't).

---

## Phase 18.5: Multi-Agent Audit Cycle (2026-04-30 → 2026-05-04) — DONE

**Trigger:** two production sync errors surfaced on a Galaxy S25 Ultra:
- `type 'Null' is not a subtype of type 'String' in type cast` (workout save replay)
- `DatabaseException: insert or update on table "personal_records" violates foreign key constraint`

Both showed in the home-screen "Sincronização Pendente" sheet with retry counters incrementing toward terminal failure (data loss).

**Approach:** parallel sweep across four specialized agents — UX/visual, QA stress simulation, DB schema/perf, codebase/test audit. Findings prioritized P0..P3 and clustered for batch fixes. Tracker file `BUGS.md` carried 41 numbered findings + 1 mid-cycle addition (BUG-042).

**Cluster ledger** (all PRs squash-merged to main):

| Cluster | Theme | PRs | Bugs |
|---|---|---|---|
| 1 | Offline sync replay & data-loss | #124, #127 | BUG-001..009, 042 |
| 2 | Repository unsafe-cast audit | #129 | BUG-010 |
| 3 | RPG progression UX | #134 | BUG-011..016 |
| 4 | Tap-target & sweat-proof UX | #132 | BUG-018..020 |
| 5 | Localization & accessibility | #130 | BUG-021..025 |
| 6 | Brand consistency | #130 | BUG-026..029 |
| 7 | DB integrity & performance | #128 | BUG-030..034 |
| 8 PR A | Architecture leaks (Flutter import in domain, etc.) | #136 | BUG-035, 039, 040 |
| 8 PR B | `active_workout_screen.dart` decomposition (1706 → 270 lines) | #138 | BUG-036, 041 |
| 8 PR C | `profile_settings_screen.dart` decomposition (801 → 169 lines) | #140 | BUG-037 |
| 8 PR D | `plan_management_screen.dart` decomposition (752 → 503 lines) | #142 | BUG-038 |
| Bonus | `exerciseProgressProvider` BUG-040 pattern extension | #144 | (BUG-040 follow-up) |

**Notable wins:**
- DRY `ExerciseSet.toRpcJson()` serializer eliminates the offline/online drift that caused BUG-001
- `dependsOn: List<String>` on queued offline actions prevents FK violations on PR upserts whose parent workout hasn't committed yet (BUG-002)
- `SyncErrorMapper` classifies exceptions by class and renders locale-aware user messages — never raw `e.toString()` — at the pending-sync sheet boundary (BUG-042, opened mid-cycle after the user flagged information disclosure on screenshots)
- New `invalidateOnUserIdChange` shared helper at `lib/features/auth/providers/auth_invalidation.dart` for any user-scoped keepAlive provider — wired into `workoutHistoryProvider`, `workoutCountProvider`, `exerciseProgressProvider`
- Class change overlay choreography (1600ms multi-stage, hotViolet only — NO heroGold to differentiate from rank-up; per-character glyph stagger; haptic at t=700ms; BUG-011)
- Cap-at-3 celebration reservation policy: classUp slot 1 → highest rank-up slot 2 → titles → level-up; closer priority `rank-ups → titles → level-up` (BUG-013)
- `_broadShouldered` cross-build title ratio rebalanced from `upper >= 2 * lower` to `upper * 10 >= lower * 16` (1.6× integer arithmetic) — applied as SQL migration `00049` for cron-driven re-evaluation (BUG-015)
- Cluster 8 PR B: pure refactor extracting `DiscardWorkoutCoordinator`, `FinishWorkoutCoordinator`, `CelebrationOrchestrator`, `PostWorkoutNavigator` — file-level mutable globals (`_isShowingDiscardDialog`, `_isFinishHandled`) hoisted to coordinator instance fields; `ActiveWorkoutScreen` promoted to `ConsumerStatefulWidget`

**Test corpus growth:**
- Started: 2274 unit/widget tests
- Ended: **2285 unit/widget tests** (+11)
- Full local E2E regression: **212/212 pass**

**Deferred:** BUG-017 (vitality stale on workout finish) — explicitly deferred by the audit, cron architecture is a deliberate spec choice. Revisit if user complaints materialize via a "last updated" timestamp on the vitality widget or an Edge Function recompute on workout finish.

**File hygiene:** `BUGS.md` deleted post-cycle; resolution narratives + PR refs preserved in this PLAN.md section and in each PR's commit message.

---

## Phase 20: Active Workout Set-Row Redesign (DONE — PR #152)

Direction B (Tactile Data Table) shipped. Active workout screen now uses a 5-state PR row matrix (none / pending-predicted-PR / completed-non-PR / completed-superseded-PR / completed-standing-PR) with heroGold scarcity confined to three places per standing-PR row (4dp left rune-stripe, gold value text, 4dp right bracket on done-col). PR semantic locked as **standing-record-only** with binary cascade (any unbeaten record type keeps a row standing). Closes BUG-018 / BUG-019 / BUG-020.

- **Key files:** `lib/features/workouts/ui/widgets/set_row.dart` (rewrite), `lib/features/workouts/domain/pr_row_state.dart` + `pr_row_state_resolver.dart` (new pure-domain resolver), `lib/features/workouts/providers/workout_providers.dart` (`activeWorkoutRowDisplaysProvider` family), `lib/shared/widgets/{weight,reps}_stepper.dart` (flex-filled tap zones), `lib/features/workouts/ui/widgets/finish_bottom_bar.dart` (BUG-020 tightened to 56dp). Reference design at `docs/design/2026-05-01-active-workout-redesign/` (critique + `direction-b-pr-refined.html` v3).
- **Test count:** 2369 unit/widget/integration, all green. New coverage: 5-state widget matrix, supersession transitions, alignment golden, provider integration, finish-bottom-bar contract pins.
- **Notable architectural decisions:** (a) `RewardAccent` ancestor pattern enforces heroGold scarcity (`scripts/check_reward_accent.sh` gate). (b) `_DoneCell` predicted-PR path uses an asymmetric Semantics: outer `Semantics(button: true, onTap:)` + inner `excludeFromSemantics: true` to bypass a Flutter Web semantics-engine role-swap bug (engine `lib/web_ui/lib/src/engine/semantics/semantics.dart` lines 1763-1771 + 2282-2312). The Checkbox path stays natural — DO NOT "consistency-fix" it. Widget test pins the contract.
- **E2E lessons captured** (see `tasks/lessons.md` + `tasks/e2e-pollution-audit.md`): every `Semantics(identifier:)` for e2e MUST pair with `container: true, explicitChildNodes: true`; deleting a UI widget with e2e selectors requires a cross-spec grep; new e2e PR tests must verify they actually beat global-setup seeds; cross-spec test-data pollution between describe blocks sharing a Supabase user is structural — Tier 1 cleanup helper at `test/e2e/helpers/test-data-reset.ts` lives there for Phase 21 to use.
- **Deferred follow-ups (post-Phase-20 polish train, all DONE except where noted):** Rename pt-BR `Rotinas → Treinos` + `Sessão` (PR #158) · Match indicator "= last set" — Pillar 1 (PR #159) · Set-type long-press discoverability — persistent `WK/WU/DR/FL` micro-label (PR #160) · Validation audit appended to `critique.md` (PR #161). **Still deferred:** post-completion hint persistence (Phase 20 critique Problem 3 — first attempt re-triggered the role-swap bug; needs layout-stable redesign), bodyweight row weight-column noise + pending-FL label color (audit Findings A+B), and a manual on-device walkthrough — all in the **Active Backlog** section below.

---

## Phase 21: E2E Per-Worker User Isolation + Parallelism Bump (DONE — PR #154)

Per-worker user pool (`{role}_w{N}@test.local`) eliminates cross-worker DB races on shared Supabase users; workers bumped 2 → 3 for ~23% CI speedup vs the workers=2 baseline (24.6 min vs ~32 min). Held at workers=3, not 4 — workers=4 saturates the CI runner's 4 vCPU AND exceeds Supabase's `sign_in_sign_ups=30/5min` IP rate limit on the larger spec files. Refactored 2 timing-fragile celebration tests (S4 + S4b) to assert on durable signals instead of Flutter `Timer.delayed` animation windows.

- **Key files:** `test/e2e/fixtures/worker-users.ts` (new — exports `WORKERS_COUNT` as the single source of truth, `getUser('role')` resolver, `buildEmailForWorker`, `getEmailPattern`); `test/e2e/global-setup.ts` (per-worker × per-role user creation with throttle + 429 retry backoff, ~126 users at workers=3 × 42 roles); `test/e2e/global-teardown.ts` (regex-pattern delete + 8-wide batched delete to avoid GoTrue saturation); `test/e2e/specs/*.spec.ts` (160 occurrences across 23 files migrated to `getUser('role')`); `test/e2e/specs/rank-up-celebration.spec.ts` (S4/S4b assertion trim — auto-dismiss + click-after-wait races dropped, durable label assertion added); `test/e2e/playwright.config.ts` (`workers: WORKERS_COUNT`, `retries: 1`, conservative `fullyParallel: false`).
- **Test count:** 214/214 e2e green at workers=3 in 24.6 min (vs ~32 min baseline). 16 consecutive passes of the previously-fragile S4/S4b across stress configs (workers=3 + `--repeat-each=5` = 10/10; workers=4 + `--repeat-each=3` = 6/6). `@flaky` tag removed.
- **Notable architectural decisions:** (a) `WORKERS_COUNT` is a single export consumed by both `playwright.config.ts` and `global-setup.ts` — drift would silently misprovision users with a confusing "user not found" failure. (b) `mode: serial` describe blocks + worker-scoped users + `fullyParallel: false` keep within-file order serial; only across-file parallelism is exploited (intra-file parallelism would need per-test isolation we don't yet have). (c) S4 + S4b refactored to drop e2e wall-clock animation assertions (`Timer.delayed` 1.1 s overlay holds, 4 s overflow auto-dismiss) — those properties live at the widget-test layer (`celebration_overflow_card_test.dart` with `tester.pump(Duration)` against a fake clock), where they're cheap and deterministic. e2e is the wrong layer to measure animation timers. (d) Tier 1 `resetRpgStateForUser` retained in `saga.spec.ts:63` and `:387` — Phase 21 fixes *cross-worker* pollution, not *intra-worker* pollution between sequential spec files within a single worker.
- **Latent infra bugs fixed during implementation:** GoTrue `listUsers()` default `perPage: 50` silently truncating user lookups at 168+ users (fixed: `perPage: 1000`); full-parallel `Promise.allSettled` over 168 deletes saturating GoTrue with ~25% 500s (fixed: 8-wide batched delete); Supabase Auth canonicalizing emails to lowercase causing case-sensitive lookups to mismatch role keys with uppercase letters like `rpgFoundationUser` (fixed: lowercase inside `buildEmailForWorker`); intra-worker pollution between sequential spec files within a single worker (fixed: surgical Tier 1 reset retained in saga.spec.ts).
- **Deferred follow-ups (all DONE post-merge):** Raised local `sign_in_sign_ups` 30 → 1000 + bumped `WORKERS_COUNT` 3 → 4 in PR #156 (~33% CI speedup vs the workers=2 baseline). Reviewer nits cleanup in PR #157 (consolidated duplicate admin-client + getUserId helpers, deleted stale doc references). Phase 20 validation walkthrough discharged in PR #161 (audit appendix in `critique.md`).

---

## Active Backlog

Single source of truth for **deferred work that is not yet a phase but is on the backlog**. Items here are either:
- (a) Real follow-ups identified during a shipped phase that didn't fit the phase's scope
- (b) Architectural cleanups parked when their fix didn't have a clear blast-radius / urgency
- (c) Manual / external-coordination tasks that can't run autonomously
- (d) Post-launch decisions waiting on telemetry

Items in (d) move to a "v2-park" sub-list and don't get worked on without new product input.

> **Phase 20 (set-row redesign) shipped 2026-04-29 in PR #152.** All five
> originally-deferred polish items landed across PRs #158/#159/#160/#161/#163.
> The two items below (20-P-1 and 20-P-4) are NOT incomplete redesign work —
> 20-P-1 is a "would be nice" enhancement blocked on a Flutter Web engine
> bug, 20-P-4 is a manual hardware QA pass. Both are filed under the
> appropriate sections below (architectural / manual) rather than as
> "redesign in progress."

### Architectural follow-ups (parked, no urgency)

- **20-P-1 — post-completion hint persistence** (Phase 20 critique Problem 3).
  Goal: keep the `Previous: Xkg × Y` line visible after the user completes a
  set so they can confirm retrospectively. **Blocked on a layout-stable
  redesign** — the first attempt (PR #159) re-triggered Phase 20's Flutter
  Web semantics-engine role-swap bug (a sibling Text appearing on completion
  drops the row's `flt-semantics-identifier`). Fix needs a fixed-height hint
  slot so adding/removing the visible Text never reflows the parent Column.
  Diagnosis: `set_row.dart` `_shouldShowHint` doc + `set_row_test.dart` revert
  note. Picks up when someone has appetite for the layout-stable redesign or
  the Flutter engine bug is fixed upstream.
- **Cold-launch orphan drain** — `SyncService` doesn't auto-drain
  pre-existing queue items when the app boots already-online. Improvement:
  gate the drain on `onlineStatusProvider`'s first real `AsyncData` emission
  (not the optimistic-default true). Worth fixing when a user reports a
  stuck queue badge after fresh launch.
- **Two unpatched legacy `exercise_peak_loads` writers**
  (`_rpg_backfill_chunk` line ~263, `record_set_xp` line ~1656) still emit
  unguarded INSERTs. Migration `00051_peak_loads_multi_writer_guard.sql`
  BEFORE-INSERT trigger silently absorbs them. Optional cleanup migration
  could add explicit `IF weight > 0` guards at the writer site for
  code-review explicitness. Not a correctness gap — purely a clean-code
  concern.
- **Wire Deno tests into CI** — `supabase/functions/**/*.test.ts` files
  exist (notably `vitality-nightly/auth.test.ts` from PR #151) but no
  workflow runs them. A small CI step would catch Edge Function
  regressions.

### v2-park (post-launch telemetry decisions)

- **"Add set" button visual weight** — `_AddSetButton` border at
  `colorScheme.primary α 0.3` reads as "optional" rather than "expected next
  step." Structurally correct (full-width, 48dp tap floor, isNew lock).
  Revisit when telemetry on `sets per exercise` vs `add-set taps` is
  available post-launch.
- **Long-press discoverability** — the `WK/WU/DR/FL` micro-label improves
  set-type affordance but the long-press cycle itself still requires
  accidental discovery (audit verdict on critique Problem 2: "partial"). If
  post-launch telemetry shows users never cycle set type, consider replacing
  long-press with tap-to-cycle (no modal layer) or a small icon hint
  adjacent to the abbr.

### Manual / external — needs the user (not autonomous)

These items can't be driven by Claude on the codebase — they need human
eyes on a device, manual dashboard configuration, or external
coordination.

- **20-P-4 — Phase 20 on-device walkthrough.** Real Brazilian-mid-market
  360dp hardware sweep: pixel-perfect spacing, haptic timing, celebration
  animation curves, real-thumb misfire under sweat. The autonomous code-state
  half landed in PR #161. The remaining visual half needs human eyes on a
  device — not catchable from code review or Playwright headless.
- **Supabase project display name** — Dashboard → Project Settings →
  General → rename to "RepSaga" (cosmetic; not blocking anything).
- **Auth redirect URLs allowlist** — Dashboard → Authentication → URL
  Configuration → add `io.supabase.repsaga://login-callback/` **when
  Google Sign-In is enabled** (Phase 16b dep, not before).
- **Brand assets** — register `repsaga.com` / `repsaga.app` /
  `repsaga.com.br`; lock `@repsaga` on Instagram, X/Twitter, TikTok.
- **Play Console subscription product `repsaga_premium`** — blocked on
  signed-AAB upload (keystore generation + Internal Testing release). On
  the Phase 16 resume checklist below.

### Known flaky e2e tests

See `test/e2e/FLAKY_TESTS.md` for the live register. Current entries are **methodology carryovers** (Supabase local rate limits + shared-user state under `--repeat-each`) — not bugs in production code or test code. Each one passes reliably in normal CI single-run mode.

- `exercises.spec.ts:372` — "should filter exercises by name via search input" — pre-existing search-debounce flake. Passes on retry; investigation is its own line item.

### Phase 16 (Subscription Monetization) — PARKED status

PR #93 (16a backend) + PR #99 (GCP migration to `repsaga-prod`) shipped. Status today:

- **External infrastructure ready:** SA, Pub/Sub topic/push-sub, Supabase secrets rotated, Edge Functions redeployed. Test notification verified end-to-end (Play → Pub/Sub → `rtdn-webhook` 200).
- **What's blocked:** Phase 16b (paywall UI + onboarding rewire), 16c (hard gate), 16d (analytics + launch gate). 16b is internal code work with no external blockers — **deferred by choice** to ship Phase 17 RPG first as the retention moat.
- **Resume checklist** when Phase 16 unparks:
  - Generate upload keystore: `keytool -genkey -keystore android/keystore/repsaga-release.jks -alias repsaga-release -keyalg RSA -keysize 2048 -validity 10000`
  - Create `android/key.properties` (NOT committed) from `android/key.properties.example`
  - Back up keystore + key.properties (1Password attachment, encrypted secondary)
  - `flutter build appbundle --release`
  - Upload AAB to Play Console → Internal testing draft. Enroll in Play App Signing (Google-managed)
  - Create subscription product `repsaga_premium` (full pricing/trial spec under `## Phase 16 → Business Model` above)
  - Resume Phase 16b dev per CLAUDE.md tech-lead pipeline

---

## Phase 19: Deferred RPG v2 + Nice-to-Have (v2.0+)

### RPG v2 (deferred — held until post-v1 telemetry justifies build)

| Feature | Source | Notes |
|---------|--------|-------|
| Cardio track | RPG spec §16.1 | HR-zone XP weighting + kcal fallback + RPE fallback. Schema accepts cardio events from day one (18a); only the UI surface + cardio-earning paths defer. |
| Power / Endurance sub-tracks | RPG spec §16.2 | Each body-part Rank splits into Power + Endurance sub-ranks. Needs estimated 1RM model first. |
| Synergy multipliers | RPG spec §16.3 | "Upper-Body Mastery" cross-body-part bonuses. D2-style. |
| Rival comparison | RPG spec §16.4 | Friend-only, opt-in, never global. |
| PR mini-events | RPG spec §16.5 | Enhanced overlay + shareable rune card on 1RM PR. |
| Weekly Smart Quests engine | Was 18a in superseded plan | 3-quest-per-week generator + localized pool. Replaced by RPG v1 ranks/titles as the retention spine. Reconsider if v1 telemetry shows quests would add value. |
| Training Stats radar (6-stat) | Was 18b in superseded plan | Replaced by RPG v1's Stats Deep-Dive (18d). Six-axis personal-best radar may return as an alternate visualization. |

### Other nice-to-haves

| Feature | Notes |
|---------|-------|
| Plate calculator | Intermediate lifters think in plates |
| Body weight tracking | Correlate volume with weight changes |
| Dark/Light mode toggle | Some users prefer light in bright gyms |
| WearOS integration | Not critical for launch |
| App review prompt | Ask happy users for store review |
| Seasonal content | Battle passes, dungeon/boss — only if v1.0 research shows demand |

### Monetization

Subscription-based — see Phase 16 for full spec. No feature-tier split: trial OR active subscription = full app access. Cosmetic one-time purchases (avatar items, rank icons, XP bar themes) remain v2.0+ candidates.

---

## QA Status (as of 2026-04-17)

> Full manual QA plan: `tasks/manual-qa-testplan.md` (89 cases, 29 automated).

**All Critical and High bugs resolved** (52+ items across PRs #24-#32, plus PR #50 E2E overhaul, PR #53 exercise image rehost, and PRs #74-#76 monkey testing sweep). See git history for full audit trails.

### Open

No open Critical/High bugs. Monkey testing sweep (18 findings: 3 crash, 8 freeze, 4 visual, 3 minor) fully resolved in PRs #74-#76.

### Feature Gaps (v1.1+)

Edit custom exercises, per-exercise notes in workout, RPE tracking (widget exists, hidden), reorder exercises in routine builder, edit workout post-hoc, PRs in bottom nav. (~~offline caching beyond active workout~~ — covered by Phase 14.)

---

## Verification & Testing

### CI Pipeline (GitHub Actions)

- `ci.yml`: 3 parallel jobs — `analyze` (format + lint + secret scan), `test` (flutter test --coverage), `build` (APK + web). Gate job `ci` depends on all three.
- `e2e.yml`: Flutter web build -> Playwright. Full regression on every PR (~16 min, 145 tests).
- `release.yml`: `v*` tags -> split APKs -> GitHub Release.

### Test Layers

- **Unit** (`flutter_test` + `mocktail`): Models, repositories, business logic, providers. Target 80%+ on business logic. **1168 tests.**
- **Widget** (`flutter_test`): Screen states (loading/data/error/empty), interactions, form validation, conditional UI.
- **E2E** (Playwright on Flutter web): Critical journeys — auth, exercises, workouts, routines, PRs, home, crash recovery, manage data, weekly plan, onboarding, profile. **145 tests (61 @smoke, 84 regression).**

### E2E Structure

```
test/e2e/
  playwright.config.ts, global-setup.ts, global-teardown.ts
  helpers/  auth.ts, app.ts, workout.ts, selectors.ts
  fixtures/ test-users.ts, test-exercises.ts
  specs/    auth, exercises, workouts, routines, home, crash-recovery,
            personal-records, profile, manage-data, weekly-plan, onboarding
```

**Organization:** Feature-based files in `specs/`. Smoke tests tagged with `{ tag: '@smoke' }` on their describe blocks. Run `--grep @smoke` for quick CI gate, no filter for full regression.

**Selectors:** `role=TYPE[name*="..."]` selectors (Playwright accessibility protocol). Flutter 3.41.6 uses AOM — `aria-label` is no longer a DOM attribute on most elements. All selectors centralized in `helpers/selectors.ts`.

**Naming convention:** `test.describe('Feature Name')` + `test('should ...')`. Bug IDs parenthesized at end: `test('should show error snackbar (BUG-003)')`.

**User isolation:** Unique test user per describe block, created in `global-setup.ts` via Supabase Admin API. No shared mutable state between test files. Inline `TEST_USERS.xxx` in `beforeEach` (no `const USER` aliases).

**Adding new E2E tests:** Place in the appropriate feature file in `specs/`. Tag with `{ tag: '@smoke' }` if it should run in the quick CI gate. Add a new test user in `fixtures/test-users.ts` + `global-setup.ts` if the test needs isolated state.

---

## UX Design Direction

- **Typography:** Body at w500. Weight/reps/timer at 28-32sp (hero content). Condensed font for numbers.
- **Colors:** Gradient accents for primary actions (`#00E676` -> `#00BFA5`). Destructive gradient (`#FF5252` -> `#D32F2F`). PR amber `#FFD54F`.
- **Cards:** Subtle 1dp top border with primary green at 15% opacity.
- **Spacing:** Tight within set rows (8dp), generous between exercises (24dp). Not uniform.
- **Icons:** Filled/bold variants (Material Symbols weight 600+).
- **Touch targets:** 48dp+ interactive, 56dp+ for workout logging primary actions. One-handed thumb-reachable.
- **Anti-patterns:** No pastel colors, no thin-line icons, no uniform padding, no generic Material Design.

### Competitive Position

| Feature | Strong | Hevy | RepSaga |
|---------|--------|------|----------|
| Progress charts | Yes | Yes | **No** (Phase 13) |
| 1RM estimation | Yes | Yes | **No** (Phase 13) |
| Exercise library | ~350 | ~650 | **~60** (Phase 13) |
| RPG gamification | No | No | **Planned** (Phase 15-16) |
| Offline support | Yes | Yes | **Planned** (Phase 14) |
| Rest timer | Yes | Yes | Yes |
| Routines | Yes | Yes | Yes |
| PR detection | Yes | Yes | Yes |
| Weekly planning | No | No | Yes (Step 12) |
