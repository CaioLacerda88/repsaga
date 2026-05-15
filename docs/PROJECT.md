# RepSaga — PROJECT.md

> Single source of truth for project structure, phase history, conventions,
> backlog, and parked work. Agents: read §0 always; load deeper sections
> only when the task needs them.

---

## §0 Read-on-arrival

**Mission.** Gym tracking app with RPG elements — log workouts, track
personal records, manage exercises and routines, earn XP, ranks, classes,
and titles tied to real lifts. Flutter + Supabase + Riverpod. Android-first,
iOS deferred. Dark bold theme, gym-floor UX (one-handed, glanceable,
sweat-proof). Brazilian fitness market focus (pt-BR shipped). Monetization:
trial-to-paywall subscription via Google Play Billing.

**Current state (2026-05-15).** **Phase 24 COMPLETE.** All four
sub-phases shipped: 24a (PR #222) wired `exercises.difficulty_mult`
(0.85–1.25); 24b (PR #224) expanded library 150 → 200; 24c (PR #227)
added bodyweight-as-load semantics; 24d (PR #229) ran the six-archetype
× 12-week calibration sim, identified the launch baseline, and
propagated the tuned constants (`VOLUME_EXPONENT 0.65→0.60`,
`WEEKLY_CAP_SETS 20→15`, `OVER_CAP_MULTIPLIER 0.5→0.3`, T4 multipliers
−0.05 across 28 slugs) to all 4 production sites. All applied to hosted
Supabase. Calibration baseline locked in `docs/xp-balance-baseline.md`;
future tuning is a new phase. Next: **Phase 25 — RPE** (research-first),
then the **Launch Phase** (un-numbered; subscription + Play Store + any
pre-launch scope expansion, formerly Phase 16). XP difficulty framework
permanent reference: `docs/xp-difficulty-framework.md`.

### Progress snapshot — latest 7 phases (full history in §4)

| Phase | Description | Status | PR(s) |
|---|---|---|---|
| 18 | RPG System v1 (rank, vitality, classes, titles) | DONE | #112–#120 |
| 18.5 | Multi-agent audit cycle (8 clusters, 41 findings) | DONE | #124–#144 |
| 20 | Active Workout Set-Row Redesign | DONE | #152 |
| 21 | E2E per-worker isolation + parallelism bump | DONE | #154, #156, #157 |
| 22 | Active Workout Audit Fix Wave (7 PRs) | DONE | #195–#208 |
| 23 | Active Workout: rest-overlay + hint removal + auto-seed + SnackBar fix-wave | DONE | #212, #214 |
| 24a | XP Balancing — difficulty multiplier infrastructure | DONE | #222 |
| 24b | New default exercises (50 additions; 150 → 200) | DONE | #224 |
| 24c | Bodyweight-as-load semantics (20 curated slugs) | DONE | #227 |
| 24d | Calibration sign-off + production propagation | DONE | #229 |

### Cluster Ledger — named bug patterns

Reference the cluster name in inline comments when fixing a matching bug
(CLAUDE.md → Code Style A3). Full pattern + fix template lives in the
auto-memory entry of the same slug.

| Cluster | Surface | One-liner |
|---|---|---|
| `flutter-web-aom-role-swap` | Web | Sibling Text drops parent's `flt-semantics-identifier`; use `ValueKey(id)` |
| `flutter-web-identifier-transition-stale` | Web | Identifier-only mutations skip setAttribute; force fresh node mount |
| `flutter-web-popscope-unreachable` | Web | GoRouter consumes popstate; PopScope contracts owned by widget tests |
| `gorouter-context-go-vs-push` | Routing | `go` replaces stack, `push` adds; choose by back-button intent |
| `persist-eats-duration` | SnackBar | `persist = action != null` silently; pass `persist: false` |
| `action-not-snackbaraction` | SnackBar | Plain TextButton loses auto-dismiss; call `hideCurrentSnackBar` manually |
| `route-scoped-messenger-queue` | SnackBar | Snacks survive `context.go`; route-scope the messenger |
| `align-widthfactor-zerofill` | Layout | `Align(widthFactor:, childless ColoredBox)` = 0×0; use `FractionallySizedBox` |
| `pump-duration-masks-forward` | Test | Synthetic clock hides missing `forward()`; test rendered output |
| `semantics-identifier-pair-rule` | Semantics | `container:true + explicitChildNodes:true` on tap target itself |
| `e2e-selector-full-audit` | E2E | Grep ALL spec files before deleting a widget; charters touch broad surface |
| `e2e-global-setup-seed-verify` | E2E | New tests read `global-setup.ts` for seeded values, not convention |
| `hive-testwidgets` | Test | `Hive.put` hangs under `testWidgets`; wrap in `tester.runAsync` |
| `async-caller-broke-snackbar` | State | Async notifier method needs caller-side `await`; CLAUDE.md A1 catches it |
| `postgres-alter-type-transaction` | DB | `ALTER TYPE ADD VALUE` can't run in transaction; own migration |
| `check-violation-writer-audit` | DB | Audit every writer, not just the surfacer |

### Section index

| Section | Read when |
|---|---|
| §1 Architecture & Conventions | Building code; touching a new layer |
| §2 Active Backlog | Picking up work; deciding what's next |
| §3 In-flight | Working on a live phase |
| §4 Completed Phases | Need historical context |
| §5 Parked / Archived | Considering reviving a parked phase |

---

## §1 Architecture & Conventions

### Tech Stack

- **Frontend:** Flutter (Android-first), SDK `^3.11.4`
- **Backend:** Supabase (Postgres, Auth, Storage, Edge Functions, pg_cron)
- **Auth:** Supabase Auth — email/password + Google, `AuthFlowType.pkce`
- **State:** Riverpod `^3.3.1` (AsyncNotifier pattern)
- **Local:** Hive (active workout cache, offline queue, locale, entitlements)
- **Models:** Freezed `^3.0.0` + json_serializable
- **Theme:** Dark & bold, Material 3 (Arcane Ascent palette — 12 tokens on `AppColors`)

### Architecture Decisions

- **Repository pattern**: All Supabase access through repository classes. No `supabase.from()` in providers/UI.
- **Feature isolation**: `lib/features/<feature>/{data,models,providers,ui}/`. No cross-feature imports.
- **Sealed exceptions**: All errors mapped to `AppException` subtypes in repository layer.
- **Offline strategy**: Server is source of truth. Active workouts use Hive with sync-on-save. Last-write-wins. See Phase 14 for full sync architecture.
- **Atomic saves**: `save_workout` Postgres RPC — single transaction, no partial data.
- **Weight units**: Stored in user's chosen unit (kg/lbs). `weight_unit` in profile.
- **Hive boxes**: `active_workout`, `offline_queue`, `user_prefs`, `exerciseCache`, `routineCache`, `workoutHistoryCache`, `prCache`, `entitlement_cache`. Schema versioned.
- **RPG attribution**: `exercises.xp_attribution` JSONB with IMMUTABLE helper + CHECK. XP hot path via `record_session_xp_batch(workout_id)` single-pass.

### Route Tree (GoRouter)

```
/splash, /login, /onboarding, /email-confirmation     (no shell)
/workout/active                                        (no shell, full-screen)
/paywall                                               (no shell — Phase 16b dep)
ShellRoute:
  /home, /home/history, /home/history/:workoutId
  /exercises, /exercises/:id
  /routines, /routines/create, /routines/:id/edit
  /records
  /profile (Saga character sheet), /profile/settings, /profile/manage-data
  /saga/stats
  /plan/week
```

### Database Schema (overview)

**Tables:** `profiles`, `exercises`, `exercise_translations`, `workouts`, `workout_exercises`, `sets`, `personal_records`, `workout_templates`, `weekly_plans`, `xp_events`, `body_part_progress`, `exercise_peak_loads`, `earned_titles`, `backfill_progress`, `vitality_runs`, `subscriptions`, `subscription_events`, `analytics_events`.

Key relationships — read migration files in `supabase/migrations/` for full DDL.

- **Localized exercise content:** `exercises` carries `slug` + structural fields; display strings live in `exercise_translations(exercise_id, locale)`. Fallback cascade `p_locale → 'en' → any`. See Phase 15f for the contract and CLAUDE.md → Exercise content translation coverage rule for the CI gate.
- **RPG:** `body_part_progress` is current state per (user, body_part); `xp_events` is the immutable per-set ledger; `character_state` view derives Character Level + dominant rank + class.
- **Subscriptions:** `entitlements` view derives state from `subscriptions` row; client reads view only, all writes go through Edge Functions using service role. See the Launch Phase entry in §5 (formerly Phase 16) for the full lifecycle.
- **RLS:** All user data scoped by `user_id = auth.uid()`. Default exercises/templates readable by all. Subscription tables SELECT-only for clients.

### Project Structure

```
lib/
  main.dart, app.dart
  core/          theme/, router/, data/, constants/, exceptions/, local_storage/, utils/, offline/, format/
  features/
    auth/        data/, providers/, ui/
    exercises/   data/, models/, providers/, ui/
    workouts/    data/, models/, providers/, ui/, ui/coordinators/
    personal_records/  data/, models/, domain/, providers/, ui/
    routines/    data/, models/, providers/, ui/
    profile/     data/, models/, providers/, ui/
    weekly_plan/ data/, models/, providers/, ui/
    rpg/         data/, domain/, providers/, ui/, ui/overlays/, ui/widgets/
  shared/widgets/
  l10n/          app_en.arb, app_pt.arb (~560 keys)

supabase/migrations/  (00001–00050+)
supabase/functions/   validate-purchase, rtdn-webhook, vitality-nightly
test/  unit/, widget/, e2e/, fixtures/, integration/
```

### Testing strategy

- **Unit + widget** (`flutter_test` + `mocktail`): 2622 tests as of 2026-05-13. Behavior-first — test the user-visible outcome, not the wiring (see CLAUDE.md A2). Mock Supabase via mocktail; never hit a real backend.
- **Integration** (`flutter_test` with live Supabase): tagged `integration` and excluded from default CI. Run via `make test-integration` against a local stack.
- **E2E** (Playwright on Flutter Web): 237 tests across 23+ spec files. Per-worker user pool (`{role}_w{N}@test.local`) with `WORKERS_COUNT` as the single source of truth in `test/e2e/fixtures/worker-users.ts`. Smoke tests carry `{ tag: '@smoke' }`; run via `--grep @smoke` for the quick gate. Selectors live in `helpers/selectors.ts`; use Playwright `role=TYPE[name*="..."]` (accessibility protocol) — Flutter 3.41.6 uses AOM, not DOM `aria-label`.

Full operational details (commands, conventions, when to add new tests) live in `CLAUDE.md` → Testing + E2E Conventions sections.

---

## §2 Active Backlog

Single source of truth for **deferred work that is not yet a phase but is on the backlog**. Items here are either:
- (a) Real follow-ups identified during a shipped phase that didn't fit the phase's scope
- (b) Architectural cleanups parked when their fix didn't have a clear blast-radius / urgency
- (c) Manual / external-coordination tasks that can't run autonomously
- (d) Post-launch decisions waiting on telemetry

Items in (d) move to the "v2-park" sub-list and don't get worked on without new product input.

### Architectural follow-ups (parked, no urgency)

_None outstanding._ Recently closed:

- **20-P-1** — post-completion hint persistence — dropped 2026-05-13. The
  entire per-row hint mechanic was removed in Phase 23 D4 (`set_row.dart:223`);
  this follow-up was a v1 patch against a deleted feature.
- **23-P-1** — seeded-set provenance cue — dropped 2026-05-13. Polish only;
  no user signal that the silent auto-seed reads as confusing.
- **23-P-2** — H5 add-exercise undo widget test — dropped 2026-05-13.
  Architecturally blocked on `ExercisePickerSheet.show` being static, and
  PR #217 strengthened the E2E coverage of the same flow — the case for
  ever fixing this collapsed.
- **23-P-4** — E2E dismissal-time assertions for the three undo SnackBars —
  DONE in PR #217 (2026-05-13). Added two-endpoint duration regression pins
  for the add-exercise undo (3.5 s, `workouts.spec.ts:1873`) and the routine-
  removed undo (3 s, `weekly-plan.spec.ts:464`); set-delete already pinned
  at `workouts.spec.ts:1153` from PR #214. Reviewer-cycle surfaced a
  preexisting flake (the "Saved" confirmation snack's ~1.4 s lifetime
  reflows the routine row mid-frame, breaking `boundingBox` /
  `scrollIntoViewIfNeeded`) — fixed with a 2.5 s settle wait + 5× retry on
  measurement. Closes the regression gap that let the `persist-eats-duration`
  cluster bug hide for weeks behind passing source-grep widget tests.

### v2-park (post-launch telemetry decisions)

- **"Add set" button visual weight** — `_AddSetButton` border at
  `colorScheme.primary α 0.3` reads as "optional" rather than "expected next
  step." Structurally correct (full-width, 48 dp tap floor, isNew lock).
  Revisit when telemetry on `sets per exercise` vs `add-set taps` is
  available post-launch.
- **Long-press discoverability** — the `WK/WU/DR/FL` micro-label improves
  set-type affordance but the long-press cycle itself still requires
  accidental discovery (audit verdict on critique Problem 2: "partial"). If
  post-launch telemetry shows users never cycle set type, consider replacing
  long-press with tap-to-cycle (no modal layer) or a small icon hint
  adjacent to the abbr.

### v1.1 feature gaps

_Most v1.1 items dropped 2026-05-13_ after a current-state audit
against the codebase. The roadmap reorganized around Phase 24 (XP
balancing) → Phase 25 (RPE) → Launch Phase. Surviving / promoted items:

- **RPE tracking** — promoted to **Phase 25** (research-first; the
  PROJECT.md claim that "widget exists, hidden by default" was wrong —
  only the model field exists, no widget. Full spec lives in §3
  In-flight when Phase 25 opens).

Dropped (with rationale):

- ~~Edit custom exercises~~ — superseded by Phase 24b default-library
  expansion. The workaround (delete + recreate) is acceptable for the
  rare case, and editing `muscle_group` on an exercise with prior XP
  events creates a confusing snapshot/forward asymmetry that's worse
  than recreate.
- ~~Per-exercise notes inside a workout~~ — workout-level notes already
  ship (finish dialog `_notesController`). Per-exercise demand
  unproven; no signal user wants it.
- ~~Reorder exercises in routine builder~~ — speculative polish. No user
  signal. Mid-workout reorder already shipped.
- ~~Edit workout post-hoc~~ — history-mutation surface adds significant
  data-integrity complexity (XP replay, PR re-detection) without proven
  demand. Defer to post-launch when telemetry shows whether users want it.
- ~~PRs in bottom nav~~ — IA change without user signal. PRs are
  reachable via Profile in two taps; that's adequate for v1.
- ~~1RM estimation~~ — **already shipped**. Epley formula lives in
  `lib/features/exercises/utils/e1rm.dart`, used by progress chart +
  RPG peak-loads + stats provider. The PROJECT.md "Phase 13 deferred"
  note was outdated.
- ~~Push notifications~~ — no signal it's needed for launch. Could be
  revived in the Launch Phase if scope expands.
- ~~Data export~~ — no demand signal. Could be revived in the Launch
  Phase if scope expands.
- ~~App icon redesign~~ — moved into the Launch Phase scope (final
  brand sweep is a launch-gate decision, not v1.1 polish).

### Known flaky e2e tests

See `test/e2e/FLAKY_TESTS.md` for the live register. Current entries are
**methodology carryovers** (Supabase local rate limits + shared-user state
under `--repeat-each`) — not bugs in production code or test code. Each
one passes reliably in normal CI single-run mode.

- `routines.spec.ts` rename + delete — RESOLVED 2026-05-11. Root cause was
  `flutterLongPress` helper occasionally firing `onTap` instead of
  `onLongPress` (Chromium pointer-event jitter). Fix landed in
  `helpers/app.ts`: re-anchor cursor with `mouse.move` between `down` and
  `up`, default hold raised 800 → 1000 ms. 40/40 consecutive passes.
- `saga.spec.ts:437` S12 class-badge cross — RESOLVED 2026-05-11. Root cause
  was 60 s test timeout too tight for the longest single-user flow. Fix:
  `test.setTimeout(120_000)`, `@flaky` removed. 20/20 consecutive passes.

---

## §3 In-flight

> No phase has started implementation as of 2026-05-13. The three phases
> below are the locked roadmap to public release. When a sub-phase opens,
> its full implementation spec gets written here (acceptance criteria,
> file plan, schema if relevant, UX details) and `docs/WIP.md` tracks the
> running checklist. Post-merge, the spec collapses into §4 Completed
> Phases.

### Phase 24 — XP Balancing

Refines the XP-per-set formula so total set XP reflects real-world
exercise difficulty within a defensible 0.85–1.25 cap. Expands the
default exercise library to fill identified gaps. Validates the
recalibration against simulated user profiles before declaring done.

Permanent reference for the curation framework + tier assignments +
formula constants: `docs/xp-difficulty-framework.md`. Citations to
NSCA, ACSM, Schoenfeld, McGill, Verkhoshansky & Siff, Garhammer,
Schwanbeck — see that file. Future tuning of tier multipliers,
secondary-muscle bumps, or floor/ceiling constants requires a new
phase; Phase 24d is the final calibration sign-off.

| Sub-phase | Status | Scope |
|---|---|---|
| 24a — Difficulty multiplier infrastructure | DONE (PR #222) | See §4 condensed entry. |
| 24b — New default exercises | DONE (PR #224) | See §4 condensed entry. |
| 24c — Bodyweight load semantics | DONE (PR #227) | See §4 condensed entry. |
| 24d — Balance simulation gate | DONE (PR #229) | See §4 condensed entry. Constants snapshot locked in `docs/xp-balance-baseline.md`. |

#### 24d acceptance criteria (the calibration gate)

Six user profiles each simulated for 12 weeks of training. Each profile
captures a realistic training pattern from the user spectrum:

| Profile | Training pattern | What it stress-tests |
|---|---|---|
| Beginner | 3×/wk, light weights, all working sets, progressive overload | Steady rank-up, no early ceiling |
| Intermediate compound-focused | 4×/wk, 5×5 style, mostly T2/T3 exercises | Baseline expected progression curve |
| Advanced powerlifter | 3×/wk, low reps (1-5), heavy T2 lifts near 90% 1RM | `strength_mult` floor keeps user productive near ceiling |
| Hypertrophy bodybuilder | 5-6×/wk, high volume, T3 + T5 mix, isolation-heavy | `cap_mult` bites; `novelty_mult` diminishes; still feels rewarding |
| Bodyweight-only | 4×/wk, T2/T3 bodyweight only | Bodyweight load + tier_mult keeps them competitive with weighted lifters |
| Machine-only | 4×/wk, T4/T5 machine work only | Ranks slower than free-weight lifters but not punitively |

Pass criteria (all must hold):

- Every profile reaches a reasonable character level by week 12; no
  profile is impossible to rank up.
- Spread between fastest and slowest profile ≤ ~25% in total XP earned.
- Bodyweight-only profile is competitive (within ~20%) with the
  intermediate-compound profile.
- Machine-only profile ranks meaningfully slower than the free-weight
  profile but earns enough to feel progress (no "machines are useless").
- Powerlifter doesn't grossly underperform the bodybuilder despite
  lower volume — `strength_mult` should compensate.
- No exercise produces an XP "lottery ticket" — outliers in `set_xp`
  must be explained.

Deliverables:

- Python simulator extension at `tasks/rpg-xp-simulation.py` with the
  six profile scenarios.
- Results table at `docs/xp-balance-baseline.md` showing per-profile
  week-12 XP totals, rank, body-part progression.
- If any criterion fails, retune constants and rerun. The PR for 24d
  is the calibration sign-off.
- Snapshot of `difficulty_mult` values + tier table + secondary-muscle
  bump + all formula constants as the **launch baseline**. Future
  tuning is a new phase.

### Phase 25 — RPE

Research-first. Decisions land before implementation.

**Research questions:**
- How is RPE used in real strength training? (RIR scale, Borg scale,
  autoregulation principles, RPE-based load prescription)
- How do competitor apps (Hevy, Strong, Boostcamp) surface RPE? Always
  visible / opt-in / setting-gated?
- Does RPE feed XP? Options to evaluate:
  - Token bonus per RPE-tagged set (encourage tracking)
  - Multiplier shape (additive to formula, vs replace `strength_mult`,
    vs separate effort signal)
  - Tracking-only (no XP impact, opt-in field)
- Localization: RPE / RIR vocabulary in pt-BR. Brazilian gym culture
  uses RPE less than US gyms — does the field need explanation copy?

**Implementation scope (depends on research outcome):**
- Widget: stepper or chip selector inside the set row.
- Storage: `ExerciseSet.rpe` already exists on the model and notifier
  accepts the field — only the UI is missing.
- L10n strings.
- Tests: unit, widget, E2E selector(s).
- If RPE feeds XP: calculator + RPC + Python sim + fixtures parity
  (same pattern as Phase 24a).

Full implementation spec lands here when research closes.

### Launch Phase

**No phase number** — final phase before public release. Scope is
deliberately open so we can fold in any last-minute work without
renumbering.

**Core scope (locked):**
- Subscription / paywall — was Phase 16. Full spec lives in §5 Parked /
  Archived. Pulls in:
  - 16b paywall UI + onboarding rewire
  - 16c hard gate
  - 16d analytics + launch gate
- Play Console product `repsaga_premium` setup.
- Signed-AAB upload + Play App Signing enrollment + Internal Testing.
- Manual / external prerequisites (run before / during this phase):
  - Supabase project display name → "RepSaga"
  - Auth redirect URLs allowlist (`io.supabase.repsaga://login-callback/`)
    when Google Sign-In is enabled.
  - Brand assets — register `repsaga.com` / `.app` / `.com.br`; lock
    `@repsaga` on Instagram, X/Twitter, TikTok.

**Scope expansion candidates** (decide closer to launch):
- App icon redesign — direction decision was deferred from v1.1.
- Push notifications — if telemetry / product direction calls for it.
- Data export (CSV / JSON) — if competitive / regulatory pressure
  appears.
- Security review pass — penetration / RLS audit before public release.
- Store assets — screenshots, feature graphic, listing copy in pt-BR
  + en.

---

## §4 Completed Phases

> Condensed summaries. Full specs live in PR descriptions, commit messages,
> and git history.

### Phase 1: Project Setup & CI (PR #1)

- Flutter project scaffold, dependencies pinned, Supabase init with PKCE
- Core infrastructure: `BaseRepository`, sealed `AppException`, GoRouter skeleton, Hive service
- Shared widgets: `AsyncValueBuilder`, `ErrorOverlay`, `ThemedButton`, `FormInput`
- Dark bold theme, Makefile targets, strict `analysis_options.yaml`
- CI pipeline: format + analyze + build_runner + test

### Phase 2: Database Schema & Seed (PR #2)

- Initial migration: all tables, enums, indexes, RLS policies
- Seed: ~60 default exercises, 4 starter templates (Push/Pull/Legs, Upper/Lower, Full Body)
- RLS integration tests for user isolation

### Phase 3: Auth & Onboarding (PRs #3–#5)

- Supabase Auth with Google + email/password, PKCE redirect
- Auth state provider (AsyncNotifier watching `onAuthStateChange`)
- Router redirect: unauthenticated → login, authenticated → home
- Screens: Splash, Login/Signup, Onboarding (2 pages: welcome + profile setup)
- Profile created on first login

### Phase 3b: Auth UX Polish (PR #6)

- Post-signup email confirmation screen with resend
- User-friendly auth error messages, loading states
- Custom Supabase email templates (RepSaga-branded)

### Phase 4: Exercise Library + Images (PRs #7–#10)

- Exercise model (Freezed), repository with CRUD + filters
- Exercise list: muscle group category buttons, search, equipment filter, empty states
- Exercise picker (shared contract for workout flow)
- Custom exercise creation with duplicate name validation, soft delete
- Exercise images: `cached_network_image`, start/end positions, fullscreen overlay
- Images hosted on GitHub (404 issue surfaced as QA-005, resolved in Phase 13 PR #53)

### Phase 5: Workout Logging (PRs #11–#15)

- `ActiveWorkoutNotifier` (AsyncNotifier) as core state machine
- Hive persistence with schema versioning, atomic save via `save_workout` RPC
- Sub-steps: data layer (5a), active workout screen (5b), rest timer + polish (5c), finish flow + history (5d)
- WeightStepper/RepsStepper with tap-to-type, long-press repeat, 48 dp targets
- Rest timer: full-screen overlay, countdown, haptic, +/-30 s adjustment
- Finish dialog with incomplete-sets warning, workout history with pagination
- Active workout banner in bottom nav, elapsed timer
- 328 tests (51 unit, 45 widget)

### Phase 5e: UX Polish Sprint (PRs #16–#18)

- Removed start-workout name dialog (auto-naming), trimmed onboarding to 2 pages
- Set row redesign: 28-32 sp numbers, tap-to-type, RPE hidden by default
- Wired onboarding data to Supabase, built minimal Profile screen
- Moved Finish button to thumb zone, added previous-session hints, create-exercise in picker
- Prominent Add Set button, rest timer adjustment, active workout banner polish

### Phase 6: Routines (PR #19)

- Renamed from "Templates" to "Routines" (market vocabulary)
- Bottom nav: Home | Exercises | Routines | Profile (History moved inside Home)
- Routine model (Freezed), repository, list/create screens
- Start-from-routine: 2 taps to first set (tap card → pre-filled workout)
- Routines don't store weights — sourced from last session via `lastWorkoutSetsProvider`
- Home screen rebuild: routine launchpad + recent workouts + start empty workout
- 72 dp routine cards, long-press for edit/delete, starter routines for new users

### Phase 7: Personal Records (PR #20)

- PR detection in `finishWorkout()`: max weight, max reps, max volume
- Only working sets, strictly greater than previous, first workout consolidated
- Bodyweight logic: weight=0 tracks max_reps only, added weight tracks all three
- PR celebration: screen flash, spring animation, heavy haptic (no confetti)
- PR list screen with empty state

### Phase 8: Home Polish & PR Integration (PR #21)

- Resume unfinished workout banner (most prominent element)
- Recent PRs section on home, "View All" to PR list
- Workout history detail with PR badges on record sets

### Phase 9: E2E Testing & CI/CD (PRs #22–#24)

- Playwright infrastructure: config, helpers, fixtures, global setup/teardown
- Smoke tests (every PR): auth, workout, PR detection
- Full suite (merge to main): all features + edge cases + crash recovery
- `e2e.yml` + `release.yml` GitHub Actions workflows
- Final manual QA pass on physical devices

### Phase 10: UX Improvements & Security (PRs #25–#26)

- Exercise detail bottom sheet in active workout (DraggableScrollableSheet)
- Stat cards on home (workout count, PR count with subtitles)
- Manage Data screen: delete history (two-step), reset all (type-to-confirm)
- Error message sanitization: `AppException.userMessage`, no raw DB errors in UI
- Migration: `personal_records.set_id` FK changed to `ON DELETE SET NULL`
- 61 new tests

### Phase 11: Content, Smart Defaults, Home Simplification (PRs #27–#30)

- Exercise descriptions + form tips (migration, seed, UI in detail screen + bottom sheet)
- Smart set defaults: 4-priority fallback chain (prev session → last set → equipment defaults → 0/0)
- Home simplification: removed Recent/Recent Records sections, enriched stat card subtitles
- 11b: 6 regression bug fixes (Hive serialization, form tips, routine start errors, equipment defaults)
- 11c: CI pipeline split into 3 parallel jobs + caching, 8 new E2E regression specs
- 787 tests total

### Phase 12: Weekly Training Plan — Bucket Model (PR #32)

- New table `weekly_plans` (migration `00011`) with Monday-aligned `week_start`, JSONB `routines` array, `UNIQUE(user_id, week_start)`
- `training_frequency_per_week` (2-6, default 3) added to `profiles`
- Auto-populate on first app open of the week (copies prior week's routines, resets completion)
- Onboarding page 2: 5 chip options (2x-6x/week); Profile: "Weekly goal" row
- Home `THIS WEEK` section between stat cards and routines — chip row with done/next/remaining states, `Edit` affordance
- `/plan/week` management screen with `ReorderableListView`, add via `DraggableScrollableSheet`, soft cap at `training_frequency_per_week`, swipe-to-remove with undo
- Week review: `WEEK COMPLETE` state with stats row, `NEW WEEK` action pre-populates from completed week
- Bucket is a planning aid, not a gatekeeper — any workout can start anytime

### Phase 12.1: E2E Infrastructure — Parallelism, Teardown, Data Seeding (PR #35)

- Replaced Python `http.server` with `http-server` npm package (concurrent); `workers: 2` in config + CI
- Global teardown cascades FK deletes (sets → workout_exercises → workouts → PRs → plans → profiles → auth user); 24 test users delete cleanly
- Seeded workout+PR data for `smokePR`, completed weekly plan for `smokeWeeklyPlanReview`, profile for `smokeExercise`
- Rewrote `exercise-library.smoke.spec.ts` to standard infra
- Added Dart semantics labels (`tooltip: 'Create routine'`, `Semantics(label: 'More options')`) for Playwright selectors
- 58 passed, 2 skipped (expected), 0 failures, 6.1 min runtime

### Phase 12.2: Home Redesign + Weekly Plan UX + Bug Fixes (PRs #36–#38)

- **12.2a (PR #36):** 7 bug fixes — Fill Remaining now checks off sets, stat cards invalidate post-workout, Profile cards navigable, all uncompleted chips tappable (not just "next"), visible Edit in THIS WEEK header, "Last:" stale-data fix, frequency soft-cap inline text replaces invisible tooltip
- **12.2b (PR #37):** Home screen redesign — Date + name header (no app title), THIS WEEK as hero, chip sizes 60/48/44 dp, contextual stats (Last session, Week volume) replace lifetime counts, Start Empty Workout as `FilledButton`, routines list hidden when plan exists
- **12.2c (PR #38):** Auto-fill `OutlinedButton` in empty plan state; inline "X/Y routines planned" counter; `SuggestedNextCard` replaces pill (full-width 56 dp, green left border); 852 tests

### Phase 12.3: UX Polish & Content Expansion (PRs #39–#41)

- **12.3a (PR #39):** P0 bugs — back nav (`PopScope(canPop: false)` at top-level), home flicker (hasValue guard during reload). Lesson: `context.go()` → `context.push()` breaks Flutter Web reload in GoRouter 13.x (see cluster `gorouter-context-go-vs-push`).
- **12.3b (PR #40):** Copy fix ("planned this week" replaces "goal reached"); 31 new exercises in 7 muscle groups including new `cardio` enum (migration 00013/00014, ~92 total); 5 new routine templates; preset action sheet (Start + Duplicate, no Edit/Delete on defaults). Lesson: `ALTER TYPE ADD VALUE` must run in its own transaction (see cluster `postgres-alter-type-transaction`).
- **12.3c (PR #41):** Post-workout prompt "X isn't in your plan yet. Add it?" with idempotency guard + error handling; PR celebration integration via route extras

### Phase 13a-PR8: E2E Overhaul — AOM Selectors, Bug Fixes, Feature-Based Restructure (PR #50)

- **Flutter 3.41.6 AOM migration:** All `flt-semantics[aria-label="..."]` CSS selectors replaced with `role=TYPE[name*="..."]` Playwright selectors. Flutter no longer sets `aria-label` as DOM attributes — accessible names go via the browser's AOM.
- **App bug fixes:** Exercise delete navigation (captured GoRouter before async gap, `router.go('/exercises')` instead of `context.pop()`); RLS policy `exercises_select_own_deleted` for soft-delete visibility; Hive saves awaited in `ActiveWorkoutNotifier`.
- **Strict-mode fixes:** `.first()` / `.last()` on SnackBar text + search input locators where Flutter renders dual DOM elements.
- **Restructure:** Flattened `smoke/` (16 files) + `full/` (11 files) into `specs/` (11 feature-based files). `{ tag: '@smoke' }` on describe blocks replaces directory split. Naming: `test('should ...')`, bug IDs parenthesized.
- 145 passed / 0 failed / 0 skipped; 994 unit/widget tests.

### Phase 13: Launch (Sprints A/B/C — PRs #42–#76)

Last phase before Play Store submission. Structured as Sprint A — Store Blockers → Toolchain Bridge → Sprint B — Retention → Sprint C — Resilience.

- **Sprint A — store blockers:** account deletion (#42), volume unit display + OAuth deep link (#42), release signing + branding + Privacy Policy/ToS (#43), QA follow-ups (#44), wakelock during active workout (#45), Sentry crash reporting (PII-scrubbed) + first-party `analytics_events` table with 8 ratified events (#46).
- **Toolchain bridge:** `make ci` gained `flutter build apk --debug --no-shrink` (#47); bulk dep upgrade Riverpod 3 / GoRouter 17 / Freezed 3 (#49); E2E AOM overhaul (#50).
- **Sprint B — retention:** rehosted 59 default exercise images to Supabase Storage `exercise-media` (#53, closes QA-005); first-run empty-state CTA replacing "Plan your week" dead-end (#55); exercise content standard + 58 new defaults reaching **150 exercises 100% covered by description + form_tips** with `scripts/check_exercise_content_pairing.sh` CI gate (#58, Exit Criterion #1); per-exercise weight progress chart via `fl_chart` with anti-generic aesthetic (#60, Exit Criterion #4).
- **Sprint C — resilience:** UI auth seam via `currentUserIdProvider` (#61); input length limits with TextField `maxLength` + 9 server-side `CHECK` constraints in migration `00021` (#63); stale workout timeout UX (#65); home information architecture refresh — four-state IA (active-plan / brand-new / lapsed / week-complete) sharing unified `_HeroBanner` (#67); ProGuard/R8 release optimization — APK 25.83 MB → 22.83 MB, classes.dex -64.7% (#69, Exit Criteria #5/#6).
- **QA monkey testing sweep:** 18 issues found (3 crash, 8 freeze, 4 visual, 3 minor) all resolved in #74 (exercise filter performance — `autoDispose.family`), #75 (active workout stability — `_isFinishing`/`_isDiscarding` guards, cancel-safe async), #76 (wall-clock timer, navigation guards, list virtualization). 1168 tests.

### Phase 14: Offline Support (PRs #78–#85)

> The active workout is sacred. Once started, finishing it offline must succeed. Server is still source of truth. Idempotent writes only. No conflict resolution (single-user app).

- **14a (#78/#79):** `connectivity_plus`, `onlineStatusProvider` with 500 ms debounce, `CacheService` for generic Hive JSON, 5 new Hive boxes, `OfflineBanner` in shell route, read-through cache on all 4 repos with eviction on writes. 32 + 55 tests (1235 total).
- **14b (#81):** `PendingAction` Freezed sealed union (`saveWorkout` / `upsertRecords` / `markRoutineComplete`); `OfflineQueueService` + `PendingSyncNotifier` (Hive-backed queue, reactive count); `finishWorkout` offline path with downstream graceful degradation; pending sync badge with per-item retry sheet. 40 new tests.
- **14c (#83):** `SyncService` watches connectivity, drains FIFO on offline→online, exponential backoff 1s→30s cap, max 6 retries; `SyncErrorClassifier` (terminal vs transient); transparent sync UX (silent background drain, no syncing animation); terminal-only `SyncFailureCard` with Retry + Dismiss; in-flight guard prevents manual/auto retry race; 3 analytics events + Sentry breadcrumbs. 40 new tests + 7 E2E.
- **14d (#84):** Offline-first PR detection reads `pr_cache` directly; optimistic cache update with replace-by-recordType; post-drain reconciliation batches userIds, refreshes once per user; backward-compatible `userId` field on `upsertRecords`. 15 new tests.
- **14e (#85):** Sign-out cache clear (`HiveService.clearAll()` swallowed on failure); start-workout offline guard ("Starting a workout requires an internet connection"); auth startup offline-safe (Supabase session cache, no network); E2E boundary documented (Playwright can't trigger `connectivity_plus`). 9 new tests, 1339 total.

### Phase 15: Portuguese (Brazil) Localization (PRs #86–#91)

Full pt-BR with language switcher; `flutter_localizations` + `gen-l10n` ARB pipeline. DB stays English — default exercise/routine content translated client-side via slug-keyed ARB. Locale stored in Hive `user_prefs` (instant offline) + Supabase `profiles.locale` (cross-device).

- **15a (#86):** i18n pipeline wired, ~135 E2E selectors migrated from text-based to `Semantics(identifier: ...)` with `flt-semantics-identifier` DOM attribute; 14 AOM edge cases fixed; `LocaleNotifier`; migration `00022_add_locale_to_profiles.sql`. 1357 unit+widget, 155 E2E.
- **15b (#87):** All hardcoded UI strings extracted into ARB (396 keys en+pt); enum `displayName` → `localizedName(l10n)`; `WorkoutFormatters` localized; `TestMaterialApp` harness, 52 widget tests updated. 15 dead ARB keys removed per review; 1381 tests.
- **15c (#88):** 556 ARB keys translated to Brazilian Portuguese; slug-keyed `exercise_l10n` for 150 default exercises + 9 routines; ARB completeness test; "PR" and "Drop Set" kept in English per Brazilian gym convention. 1400 tests.
- **15d (#89):** `LanguagePickerSheet` modal wired to `LocaleNotifier.setLocale`; Hive-first + Supabase best-effort sync; `App.build()` listens to `authStateProvider` (not profile — prevents caching `AsyncData(null)`; see cluster `provider_init_timing`).
- **15e (#91):** `AppNumberFormat` + `AppDateFormat` with explicit locale (`80,5 kg` / `18/04/2026` in pt); `WeightStepper` dialog accepts `,` and `.`; bottom nav + Profile overflow guards at 320 dp under pt; E2E `localization.spec.ts` (9 tests covering boot / live switch / reload persistence). 1449 unit+widget, 164 E2E.

### Phase 15f: Exercise Content Localization (PR #110)

DB-side exercise content i18n. Replaced client-side ARB localization for default exercises with a dedicated `exercise_translations` table keyed by `(exercise_id, locale)` and a fallback cascade `p_locale → 'en' → any`. Schema scales to N locales without rework.

- **Schema:** 5 migrations (00030 slug + derive trigger; 00031 `exercise_translations` table + RLS; 00032 EN backfill from legacy columns; 00033 150 pt-BR seed rows; 00034 column drop + 4 localized RPCs).
- **RPCs:** `fn_exercises_localized`, `fn_search_exercises_localized`, `fn_insert_user_exercise`, `fn_update_user_exercise` replace all embedded selects in 4 repositories.
- **Cache:** locale-keyed Hive boxes (`exerciseCache`, `routineCache`, `workoutHistoryCache`, `prCache`); `LocaleNotifier.setLocale` clears all four on switch.
- **CI guard:** `scripts/check_exercise_translation_coverage.sh` enforces every default-exercise INSERT ships with both en+pt translation rows in the same PR. See CLAUDE.md → Exercise content translation coverage rule.
- 1786 unit/widget, 183/183 full E2E suite, 4 forward invariants (orphaned/missing-en/missing-pt/orphaned-translations) all 0/0/0/0 on staging + prod.
- pt-BR translation glossary preserved at `docs/pt-glossary.md`.

### Phase 17: Gamification Foundation (PRs #101, #103, #105–#108)

> Refined from the original Phase 17 spec after PO + UX post-mortem of GymLevels, Arise, and competitor teardown. **17.0c, 17.0e, 17b shipped. 17a / 17c / 17d / 17e SUPERSEDED by Phase 18 RPG v1.**

- **17.0 (PR #101 — superseded by 17.0c):** Pixel-art visual system shipped in PR #101; rolled back after post-ship evaluation surfaced unsolvable AI-gen pixel asset quality issues + aesthetic polarization.
- **17.0c (PRs #105, #106, #107):** Arcane Ascent Material 3 theme + 12-token palette + app icon. 63 PNGs / `PixelImage` / Press-Start-2P / pixel-allowlist deleted. New `AppColors` (abyss / surface / surface2 / primaryViolet / hotViolet / heroGold / textCream / textDim / success / warning / error / hair), `AppTextStyles` via google_fonts (Rajdhani + Inter TTF-bundled, `allowRuntimeFetching = false`), `AppIcons` (20 inline-SVG icons, side-view barbell motif), `RewardAccent` as sole sanctioned heroGold emitter + `scripts/check_reward_accent.sh` lint gate. Migrated nav tabs, splash, exercise list, home `_LvlBadge`, saga intro overlay, workout detail trophy. App icon variant 3 (rune + barbell composite with hero-gold star core) shipped + adaptive icon foreground.
- **17.0e (PR #108):** Inline SVG → v3-silhouette asset pack migration with CC BY 3.0 attribution.
- **17b (PR #103, foundation retained):** Migrations `00028_user_xp` (`user_xp` + `xp_events` + `award_xp` RPC SECURITY DEFINER) and `00029_retroactive_xp` (`retro_backfill_xp` idempotent). `XpCalculator` placeholder + 7 ranks Rookie→Diamond; `xpProvider` AsyncNotifier with optimistic update; XP awarded post-PR detection in `finishWorkout`. `SagaIntroOverlay` (3 screens, Begin-to-dismiss); `SagaIntroGate` runs retro backfill once per user, renders overlay when unseen, persists `saga_intro_seen` via Hive. **Status:** infrastructure stays; XP math is placeholder — Phase 18a replaces the formula. Overlay choreography reused as-is for rank-up/title-unlock in 18c.
- **17a / 17c / 17d / 17e SUPERSEDED by Phase 18 RPG v1.** Celebration choreography → 18c. Weekly streak loop replaced by Vitality (§8). Character sheet → 18b + 18d. Home recap → Phase 19. Original specs preserved in git history.

### Phase 18: RPG System v1 (PRs #112–#120)

> **Source of truth:** `docs/rpg-design.md` carries the math, schema, attribution map, rank curve, vitality formula, class lookup, and 90-title catalog.

**Mental model:** Two numbers per body part — **Rank** (1-99, monotonic, lifetime saga) and **Vitality** (0-100%, asymmetric EWMA on real volume — rebuild fast τ=2 wk, decay slow τ=6 wk, peak permanent). Six body parts in v1 (chest/back/legs/shoulders/arms/core). **Character Level** is derived: `floor((Σranks − 6) / 4) + 1`, capped at 148 theoretical max. **Class** is derived from current Rank distribution. **Titles** unlock at Rank thresholds (78 per-body-part + 7 character-level + 5 cross-build = 90). Cardio is a v2 deferral — schema accepts day one, no UI surface.

- **18a (PR #112) — Schema + XP engine + backfill:** `xp_events`, `body_part_progress`, `exercise_peak_loads`, `earned_titles`, `backfill_progress` (RLS owner-only); `xp_attribution` JSONB on `exercises` with IMMUTABLE helper + CHECK; `character_state` view (`security_invoker = true`). XP hot path `record_session_xp_batch(workout_id)` single-pass — p95 = 11 ms on 100-set payload (38× speedup vs per-set PL/pgSQL FOR loop). `backfill_rpg_v1(user_id)` FUNCTION with driver loop. Bug fixes BUG-RPG-001..004 landed in same PR. CI: `@Tags(['integration'])` + `--exclude-tags integration` for remote runs.
- **18b (PR #113) — Character sheet + rune sigils UI:** `/profile` resolves to `CharacterSheetScreen` (legacy account/locale/sign-out moved to `/profile/settings`). Tab label "Saga". Layout: rune halo + Lvl 56sp + class badge slot + active title pill → hexagonal Vitality radar (CustomPainter, 6 axes) → six asymmetric codex rows (trained expanded, untrained collapsed) → dormant Cardio row → Stats/Titles/History nav. Four rune halo glow states (Dormant/Fading/Active/Radiant) per §8.4. Class badge ships day-1 with placeholder. First-set-awakens banner gated on `lifetime_xp == 0`. **Knock-on fix:** tab re-tap restored when on a pushed sub-route. 1919 tests, new `saga.spec.ts` (S1–S7 @smoke).
- **18c (PR #114) — Mid-workout overlay rewire + title unlocks:** `CelebrationPlayer` + `CelebrationQueue` sequencing rank-up → level-up → title (1.1 s each, 200 ms gap), reuses 17b overlay scaffold driven by Phase 18 XP. 78 per-body-part titles in `assets/rpg/titles_v1.json` (en + pt-BR), unlock detection client-side, `earned_titles` persisted via UPSERT. Half-sheet renders post-workout with "Equip" CTA (single active title enforced by unique index). Overflow card holds 4 s with localized "Tap to continue" routing to `/profile`. Use-after-dispose hardening via `_ActiveWorkoutBodyState` capturing `rootContext` before finish `await`.
- **18d.1 (PR #118) — Vitality nightly job:** Migration `00042_vitality_cron.sql` (`vitality_runs` idempotency, `pg_cron` at 03:00 UTC, partial index). Edge Function `vitality-nightly` service-role-only, asymmetric EWMA (`α_up = 0.3935` rebuild, `α_down = 0.1535` decay per §8.1), INSERT-first dedup, optional chunked invocation. Active-users pool UNIONs `xp_events past 7d` with `body_part_progress.vitality_ewma > 0` so deload weeks still get decay applied. `VitalityStateMapper` is single source of truth for §8.4 (Dormant/Fading/Active/Radiant). Latent bug fixed: prior `fromVitality` compared raw EWMA to 30/70 literals — now normalizes via `VitalityCalculator.percentage`. 2028 tests + 9 integration.
- **18d.2 (PR #119) — Stats deep-dive screen at `/saga/stats`:** Trend chart + live Vitality table + Volume & Peak + Peak Loads. `statsProvider` hydrates `StatsDeepDiveState` from `body_part_progress` + `xp_events` + `exercise_peak_loads`. Cardio peaks excluded at source. Three spec amendments locked in tests (no activity gate, hybrid X-axis, ghost lines + selected line styling). New `vitality_table.dart`, `vitality_trend_chart.dart`, `peak_loads_table.dart` widgets. 2081 tests.
- **18e (PR #120) — Class system + cross-build titles + final QA:** `class_resolver.dart` pure function with §9.2 resolution order — `max<5 → Initiate; min≥5 ∧ spread≤30% → Ascendant; else dominant`. 8 classes. Two-tier `ClassBadge` (Initiate quieter). `Title` refactored to sealed Freezed union (BodyPartTitle / CharacterLevelTitle / CrossBuildTitle); 7 + 5 = 90 titles total. Detection + retroactive backfill (5 cross-build predicates mirrored in SQL via `evaluate_cross_build_titles_for_user`). E2E T1/T2/T3 + S12. 2183 tests.

Completes the **RPG v1 arc** (18a→18e). Cardio + Wayfarer class deferred to Phase 19.

### Anti-Patterns (Explicitly Banned — 25 items)

Carried forward through Phase 18 RPG v1. Bound to all gamification work.

1. Confetti or particle spam. 2. Streak flames or emoji — geometric marks only. 3. Badge walls / grid collections — milestones are a vertical timeline. 4. Locked badge states. 5. Multiple progress bars on home — LVL line only. 6. Level-gated features. 7. Push notification streak anxiety. 8. XP in persistent header — profile + celebration overlay only. 9. Animated badges. 10. Global leaderboards. 11. Punitive daily streaks. 12. Class XP multipliers. 13. Social infrastructure in v1. 14. RED for missed days (week strip neutral grey). 15. Loot boxes / pure-chance rewards. 16. Time-pressure "daily quest resets" copy. 17. Fake urgency banners. 18. Population-relative stats. 19. "Paywall tease" framing of gamification. 20. Generic Material list views for milestones/quests. 21. Hardcoded colors outside `AppColors` (lint-enforced). 22. Overlays that block logging. 23. Vanilla "Recent workouts" list on home. 24. Features behind cosmetic level requirements. 25. Any retention mechanic that lies to the user.

### Phase 18.5: Multi-Agent Audit Cycle (PRs #124–#144)

**Trigger:** two production sync errors on a Galaxy S25 Ultra surfaced under the "Sincronização Pendente" sheet with retry counters incrementing toward terminal failure.

**Approach:** parallel sweep across four specialized agents — UX/visual, QA stress simulation, DB schema/perf, codebase/test audit. 41 numbered findings + 1 mid-cycle addition (BUG-042). All clustered for batch fixes:

| Cluster | Theme | PRs | Bugs |
|---|---|---|---|
| 1 | Offline sync replay & data-loss | #124, #127 | BUG-001..009, 042 |
| 2 | Repository unsafe-cast audit | #129 | BUG-010 |
| 3 | RPG progression UX | #134 | BUG-011..016 |
| 4 | Tap-target & sweat-proof UX | #132 | BUG-018..020 |
| 5 | Localization & accessibility | #130 | BUG-021..025 |
| 6 | Brand consistency | #130 | BUG-026..029 |
| 7 | DB integrity & performance | #128 | BUG-030..034 |
| 8 PR A | Architecture leaks | #136 | BUG-035, 039, 040 |
| 8 PR B | `active_workout_screen.dart` decomposition (1706 → 270 lines) | #138 | BUG-036, 041 |
| 8 PR C | `profile_settings_screen.dart` decomposition (801 → 169 lines) | #140 | BUG-037 |
| 8 PR D | `plan_management_screen.dart` decomposition (752 → 503 lines) | #142 | BUG-038 |
| Bonus | `exerciseProgressProvider` BUG-040 pattern extension | #144 | (BUG-040 follow-up) |

**Notable wins:** DRY `ExerciseSet.toRpcJson()` eliminating offline/online drift; `dependsOn: List<String>` on queued offline actions preventing FK violations; `SyncErrorMapper` rendering locale-aware user messages at the pending-sync sheet boundary; new `invalidateOnUserIdChange` shared helper; class change overlay choreography (1600 ms multi-stage, hotViolet-only); cap-at-3 celebration reservation policy; `_broadShouldered` cross-build ratio rebalanced via SQL migration `00049` for cron-driven re-evaluation; Cluster 8 PR B coordinator extraction (`DiscardWorkoutCoordinator`, `FinishWorkoutCoordinator`, `CelebrationOrchestrator`, `PostWorkoutNavigator`).

2274 → 2285 unit/widget tests (+11), 212/212 E2E. **Deferred:** BUG-017 vitality stale on workout finish — cron architecture is a deliberate spec choice.

### Phase 20: Active Workout Set-Row Redesign (PR #152)

Direction B (Tactile Data Table) shipped. Active workout screen now uses a 5-state PR row matrix (none / pending-predicted-PR / completed-non-PR / completed-superseded-PR / completed-standing-PR) with heroGold scarcity confined to three places per standing-PR row (4 dp left rune-stripe, gold value text, 4 dp right bracket on done-col). PR semantic locked as **standing-record-only** with binary cascade (any unbeaten record type keeps a row standing). Closes BUG-018 / BUG-019 / BUG-020.

- **Key files:** `lib/features/workouts/ui/widgets/set_row.dart` (rewrite), `lib/features/workouts/domain/pr_row_state.dart` + `pr_row_state_resolver.dart`, `lib/features/workouts/providers/workout_providers.dart` (`activeWorkoutRowDisplaysProvider`), `lib/shared/widgets/{weight,reps}_stepper.dart` (flex-filled tap zones), `lib/features/workouts/ui/widgets/finish_bottom_bar.dart`.
- **Notable architectural decisions:** `RewardAccent` ancestor pattern enforces heroGold scarcity. `_DoneCell` predicted-PR path uses asymmetric Semantics (outer `Semantics(button: true, onTap:)` + inner `excludeFromSemantics: true`) to bypass the Flutter Web engine role-swap bug — see cluster `flutter-web-aom-role-swap`. The Checkbox path stays natural; DO NOT consistency-fix it.
- 2369 unit/widget/integration tests. Deferred follow-ups landed across PRs #158–#163.

### Phase 21: E2E Per-Worker User Isolation + Parallelism Bump (PRs #154, #156, #157)

Per-worker user pool (`{role}_w{N}@test.local`) eliminates cross-worker DB races on shared Supabase users; workers bumped 2 → 4 (PR #156, ~33% CI speedup vs the workers=2 baseline; ~24 min vs ~32 min). Held at 4 — saturates the runner's 4 vCPU AND approaches Supabase's `sign_in_sign_ups=1000/5min` IP rate limit. Refactored 2 timing-fragile celebration tests (S4 + S4b) to assert on durable signals instead of `Timer.delayed` animation windows.

- **Key files:** `test/e2e/fixtures/worker-users.ts` (new — `WORKERS_COUNT` single source of truth, `getUser('role')` resolver); `test/e2e/global-setup.ts` (per-worker × per-role with throttle + 429 retry backoff); `test/e2e/global-teardown.ts` (regex-pattern delete + 8-wide batched delete to avoid GoTrue saturation); 160 occurrences across 23 spec files migrated to `getUser('role')`.
- **Latent infra bugs fixed:** GoTrue `listUsers()` default `perPage: 50` silently truncating user lookups (fixed: `perPage: 1000`); full-parallel `Promise.allSettled` over 168 deletes saturating GoTrue with ~25% 500s (fixed: 8-wide batched delete); Supabase Auth canonicalizing emails to lowercase causing case-sensitive role-key mismatches (fixed inside `buildEmailForWorker`); intra-worker pollution between sequential spec files (fixed: surgical Tier 1 reset retained in `saga.spec.ts`).

### Phase 22: Active Workout Audit Fix Wave (PRs #195–#208)

**Trigger:** user request for a "thorough review of active workout logic" after the on-device usability pass (PR #193). Orchestrator-driven audit then plan, not a freeform sweep. Two parallel audit agents (logic + UX), product-owner web research (Strong/Hevy/Boostcamp/FitNotes/JEFIT) for 6 open UX questions, RPC idempotency + weekly-plan FK verification, then RPG-impact pass.

**6 UX decisions** (high-confidence, evidence-backed):

| # | Decision | Source |
|---|---|---|
| Q1 | Show Cancel from t=0 on the loading overlay (no fade-in delay) | Material progress-indicator guidance + Strong/Hevy benchmarks |
| Q2 | Filter previous-session warmup sets when computing pre-fill defaults | FitNotes/Hevy treat warmup as separate type |
| Q3 | Conditional confirm on swap-with-completed-sets; silent swap if zero completed | Hevy/Strong never silently re-attribute PR history |
| Q4 | "Fill Remaining" does NOT trigger rest timer | Fill-Remaining is "log what already happened" |
| Q5 | Undo snackbar 4 s → 10 s + lift z-order above rest-timer overlay (note: 10 s later dropped to 5 s in PR #214) | Material max + overlay-eats-snackbar was a layering bug |
| Q6 | Remove long-press swap on exercise name entirely | Industry converged away from gesture shortcuts in gym apps |

**Cluster ledger** (all PRs squash-merged):

| Cluster | Theme | PR |
|---|---|---|
| PR-1 | State-machine integrity + Q1 overlay UX | #195 |
| PR-2 | Done-checkbox tap target + Q5 undo-snackbar reachability above rest-timer | #198 |
| PR-3 | Hidden destructive gestures + Q3 swap-confirm + H5 add-exercise undo + S1 discard re-entrance | #200 |
| PR-4 | Set defaults: warmup filter (Q2) + propagateWeight + cascading-undo order | #202 |
| PR-5 | Hint slot stability + visual contrast + disabled-Finish helper + device feedback | #204 |
| PR-6 | PR-row state during PR-data loading + analytics source DRY | #206 |
| PR-7 | Brand voice copy + generic-icon swaps (anti-AI aesthetic) | #208 |

**Wave outcome:** 18+ findings shipped (4 Critical, 8 High, 11 Medium + Smells + 7 reviewer-cycle catches). 2274 → 2595 unit/widget tests, 234 E2E passing. Two user-on-device feedback items folded mid-wave. Reviewer-cycle pattern caught H5 snackbar route-leak, M3 cascading-undo `_originalSetIndices` map leak across keepAlive notifier sessions, `_isShowingDialog` race in DiscardWorkoutCoordinator, Q3 PT 'jornada' vs established 'caminho' metaphor.

**Deferred backlog (per-phase):** offline celebration replay; M9/M10 discoverability coach marks; first-class warmup type as data model (PR-4's M1 fix patches the symptom — the real fix is to model warmups as their own class).

### Phase 23: Active Workout — rest-overlay chrome + hint removal + auto-seed + SnackBar fix-wave (PRs #212, #214)

**Trigger:** user on-device feedback during a real workout (Upper/Lower — Supino Reto com Barra). Two distinct issues that escaped Phase 22's re-audit. Plus a follow-on SnackBar bug-wave surfaced on the same on-device verification cycle.

- **Rest overlay chrome (D1–D3):** FAB + FinishBottomBar conditionally hidden while rest is active so the scrim truly covers everything except the AppBar X (the in-rest discard affordance). AppBar `backgroundColor` flips to `AppColors.abyss` during rest so it visually merges into the scrim. Android back-press priority chain: rest active → dismiss rest; loading overlay → discard coordinator (loading has its own Cancel CTA); else → discard dialog.
- **Per-row hint removal (D4–D5):** all `Previous: …` / `= last set` / mobile-only filler hint logic deleted from `SetRow` and `ExerciseCard`; `lastSet` constructor param dropped; ARB keys `previousSet` / `matchedLastSet` / `tapToDismiss` removed. Pre-fill carries the anchor; the yellow PR marker carries the win signal. Per-exercise summary chip explicitly rejected by user — keep the surface bare.
- **Auto-seed set 1 on `addExercise` (D6):** Hevy/Strong-style — when the user adds an exercise mid-workout, set 1 is pre-filled from the prior session's first working set (warmup-filtered per Phase 22 Q2), falling back to last working set, then equipment defaults. Bodyweight exercises seed reps but not weight. Routine-start path untouched — it has its own pre-fill at `startRoutineWorkout` and unit test REV-5 pins `getLastWorkoutSets` is called exactly once for routines.
- **Phase 23 root-caused incidents:** Cluster A (`flutter-web-popscope-unreachable`), Cluster B (`flutter-web-identifier-transition-stale`), Cluster C (`async-caller-broke-snackbar`). All landed in PR #212.
- **PR #214 SnackBar fix-wave:** Three undo SnackBars persisted indefinitely on Android — Flutter `persist = persist ?? action != null` footgun (cluster `persist-eats-duration`). Fixed `persist: false` + custom `SnackBarCountdown` widget with `TweenAnimationBuilder` drain bar (3 dp, `Curves.linear`) + bounding-box hit-test tap-out dismiss + factory-shape entry via `SnackBarTapOutDismissScope.showCountdownSnackBar`. New `lib/shared/widgets/snackbar_tap_out_dismiss_scope.dart`. Durations dropped: add-exercise 4 s → 3.5 s, routine-remove 5 s → 3 s, set-delete 10 s → 5 s — countdown bar makes definite intent legible. Four named clusters captured: `persist-eats-duration`, `action-not-snackbaraction`, `align-widthfactor-zerofill`, `pump-duration-masks-forward`.
- **Test corpus growth:** 2595 → 2622 unit/widget tests. Phase 23 review cycle: 5 in-cycle revisions (REV-1..REV-5). PR #214 review: 2 reviewer-cycle FIXes + 5 follow-on bug-cycle fixes (layout, animation drain, action-dismiss, stale E2E duration).

### Phase 24a: XP Balancing — Difficulty Multiplier Infrastructure (PR #222)

> Permanent framework reference: `docs/xp-difficulty-framework.md`. Tier table, composite formula, and source citations live there; future tuning is a new phase.

Wires `exercises.difficulty_mult` (numeric 0.85–1.25) through every XP write site so total set XP reflects real-world exercise difficulty within a defensible cap. Ships the schema column with curated values for all 150 default exercises, the SQL RPC chain extension (`base × intensity × strength × novelty × cap × difficulty_mult × attribution_share`), Dart formula extension, Python parity sim recreation, and a CI gate. Forward-only — `xp_events.payload` snapshots `difficulty_mult` at write time; past events are not replayed.

- **Schema (00053):** `ALTER TABLE exercises ADD COLUMN difficulty_mult numeric(4,2) NOT NULL DEFAULT 1.0` + per-slug UPDATE for 150 defaults with inline `-- T<N> + <sec> sec → <value>` audit comments + `CHECK BETWEEN 0.85 AND 1.25` + DO-block sanity assert (any `is_default=true` row at literal 1.0 trips it; the proof that 1.0 is unreachable from `tier_mult ∈ {0.85,0.95,1.05,1.15,1.25} + bump ∈ {0,0.02,0.04,0.06}` lives in the migration comment). Phase B used `jsonb_object_keys(xp_attribution) - 1` as the secondary-count source because `secondary_muscle_groups` is `[]` on every default — the more honest signal.
- **RPCs (00054, CREATE OR REPLACE — does not mutate 00040/00050/00052):** `record_set_xp` / `record_session_xp_batch` / `_rpg_backfill_chunk` fetch `COALESCE(exercises.difficulty_mult, 1.0)` (defensive even though the column is `NOT NULL`), apply in chain, snapshot to `payload` JSONB. Hot path discipline preserved — `record_session_xp_batch` carries the multiplier in the batch CTE, not per-row sub-select. All prior fixes (`AND s.weight > 0` from 00050; `IF v_weight > 0` writer-site guards from 00051/00052) preserved verbatim.
- **Dart:** `XpCalculator.computeSetXp` adds required `difficultyMult` named param applied as final multiplier; `SetXpComponents` gains field + `'difficulty_mult'` JSON key. `XpEvent.fromJson` is a custom factory that promotes `payload.difficulty_mult` to top-level (the model field is nullable for legacy events; without the promotion, the field would always deserialize as null because Freezed reads the row's top-level key but the value is nested in payload — caught by reviewer in cycle 1).
- **CI gates:** new `scripts/check_exercise_difficulty_mult_coverage.sh` analogous to translation coverage — fails if any future migration adds `is_default=true` exercises without paired `difficulty_mult` assignment in the same PR. Self-tested via `--self-test` mode + 3 fixture files. Wired into `analyze`'s `needs` symmetric with translation gate.
- **Parity:** `tasks/rpg-xp-simulation.py` recreated (was deleted in PR #215) with `DIFFICULTY_MULT_BY_SLUG` dict mirroring 00053. Fixture regenerated with 11 set_xp scenarios incl. 0.85 and 1.25 boundary cases. 4 new XpEvent unit tests pin promotion / legacy null / idempotency / empty-payload semantics.
- **Verification:** 2622 → 2630 unit/widget tests (+8: 4 XpEvent + 4 difficulty_mult parameter semantics), 35/35 integration, Android debug APK clean, E2E smoke 119/119 (13.2 min — zero selector/text drift, as expected for backend phase), `npx supabase db reset` clean through 00054. Reviewer cycle: 1 Blocker (always-null XpEvent.difficultyMult) + 2 Warnings + 2 Nits — all fixed in same cycle, no deferrals. Hosted Supabase migrated cleanly via `npx supabase db push` post-merge.
- **Out of scope (24b/c/d):** ~30–50 new default exercises (24b), bodyweight `effective_load = bodyweight + added` (24c), six-profile × 12-week calibration sign-off (24d).

### Phase 24b: New Default Exercises — 50 additions, 150 → 200 (PR #224)

> Built on Phase 24a's `difficulty_mult` infrastructure. Each new exercise ships with the full content surface a default needs: slug + en/pt translations (name + description + form_tips) + muscle_group + equipment_type + xp_attribution (sums to 1.0) + curated difficulty_mult.

- **Coverage by tier:** T1 Olympic platform (14: power_clean, snatch, hang_clean, hang_snatch, clean_and_jerk, push_jerk, split_jerk, kettlebell_snatch, dumbbell_snatch, medicine_ball_slam, broad_jump, depth_jump, lateral_box_jump, single_leg_box_jump). T2 bodyweight (8: pistol_squat, archer_push_up, ring_dip, handstand_push_up, l_sit, muscle_up, hanging_windshield_wiper, single_leg_glute_bridge_eccentric) + specialty barbell (7: atlas_stone, zercher_squat, safety_bar_squat, snatch_grip_deadlift, deficit_deadlift, paused_squat, paused_bench_press). T3 variants (7: larsen_press, neutral_grip_pull_up, mixed_grip_deadlift, single_arm_landmine_press/row, kettlebell_clean, kettlebell_high_pull, dumbbell_clean). T4 cable/machine (5: belt_squat, pendulum_squat, glute_ham_raise, cable_pullover, cable_overhead_extension). T5 accessory (7: copenhagen_plank, suitcase_carry, fat_grip_curl, single_leg_calf_raise, seated_dumbbell_calf_raise, etc.). Cardio (3: assault_bike, sled_push, sled_drag — T5 placeholder per Phase 24a precedent; cardio = Phase 19 v2 deferral).
- **Migration (00055, ~1003 lines):** single transaction with PART A (50 exercise INSERTs idempotent via `WHERE NOT EXISTS slug`) + PART B/C (50 en + 50 pt translations joined by slug; eponyms preserved English in pt per `docs/pt-glossary.md` §2) + PART D (3 sanity DO-blocks: row count = 50, paired translations = 100, no slug at literal 1.0). All 50 difficulty_mult values curated per Phase 24a framework `clamp(tier_mult + min(secondary_count, 3) × 0.02, 0.85, 1.25)` with inline `-- T<N> + <sec> sec → <value>` audit comments.
- **Images: 28/50 sourced** from yuhonas/free-exercise-db (CC0) and uploaded to hosted Supabase Storage `exercise-media/<slug>_{start,end}.jpg` via service-role REST API. The other 22 ship with `image_start_url = NULL` — matches existing `cable_chest_press` / `pec_deck` precedent in the original 150 defaults; UI tolerates absence. Follow-up image-sourcing task can backfill those 22 from alt providers.
- **Reviewer cycle (commit 6d02701):** 3 Blockers (muscle_group fields didn't match dominant `xp_attribution` body part — atlas_stone chest→back, larsen_press shoulders→chest, medicine_ball_slam chest→core; pure discoverability inversions) + 2 Warnings (atlas_stone audit comment showed wrong terminal value; 5× pt-tips `e explode em` → `e exploda em` imperative) + 1 Suggestion (paused_squat / paused_bench_press audit comments now name non-paused T3 counterpart). All fixed in same cycle.
- **CI fix-cycle (commit f5207d3):** Local @smoke (119 tests) passed but CI's full regression (302 tests) caught `exercises-localization.spec.ts` "should show en exercise names…" — alphabetical list pushed `Barbell Bench Press` below the fold once Ab Rollout / Archer Push-Up / Arnold Press / Assault Bike / Atlas Stone / Back Extension / Band Face Pull landed alphabetically prior. Flutter virtualizes the list — off-screen items aren't in the DOM. Fixed by adding `flutterFillByInput('Search exercises', 'Barbell Bench')` before the visibility assertion (same pattern every other test in the file uses). Verification gap surfaced: orchestrator should run the full regression locally (or trust CI) for data-shape changes that affect exercise enumeration order — relying solely on @smoke missed this.
- **Verification:** unit/widget 2630/2630, integration 35/35, Android debug APK clean, db reset clean through 00055 (3 sentinels did not trip), E2E full regression green on CI after the fix. Hosted spot-check confirms 200 defaults + reviewer fixes applied (atlas_stone=back, larsen_press=chest).
- **Out of scope (24c/d):** bodyweight `effective_load = bodyweight + added` semantics (24c); six-profile × 12-week calibration sign-off (24d). Image backfill for the 22 NULL slugs is a separate follow-up task (alt providers like exrx, musclewiki, custom stock).

### Phase 24c: Bodyweight-as-Load Semantics (PR #227)

> Builds on Phase 24a (`difficulty_mult` infrastructure + payload promotion) and 24b (200 defaults). Per `docs/xp-difficulty-framework.md` §4 (the bodyweight question).

For 20 curated bodyweight exercises (pull-ups, dips, push-ups, pistol squats, walking lunges, hanging leg raises, plus 24b additions: muscle_up, ring_dip, handstand_push_up, archer/wide/incline/decline/diamond/close-grip push-up variants, inverted_row, nordic_curl), the XP formula now uses `effective_load = profile.bodyweight_kg + sets.weight` instead of bare entered weight. Forward-only — past `xp_events` stay frozen.

- **Schema (00056):** `profiles.bodyweight_kg numeric(5,2) NULL` with 25–250 kg sanity CHECK; `exercises.uses_bodyweight_load BOOLEAN NOT NULL DEFAULT FALSE`; UPDATE 20 curated slugs; DO-block sanity assert (`v_expected = 20`).
- **RPCs (00057, CREATE OR REPLACE × 3 — does not mutate 00040/50/52/54):** `record_set_xp` / `record_session_xp_batch` / `_rpg_backfill_chunk` pre-fetch `profiles.bodyweight_kg` once per user, carry `uses_bodyweight_load` in the batch CTE (no per-row sub-select), compute `v_effective_weight = CASE WHEN uses_bodyweight_load THEN COALESCE(weight,0)+COALESCE(bw,0) ELSE COALESCE(weight,0) END` per set, snapshot `effective_load` and `bodyweight_used` to `payload`. Hot-path discipline preserved. Graceful NULL-bodyweight fallback (degrades to entered-weight-only). All prior fixes (00050 weight>0; 00051/52 writer-site guards) preserved.
- **Bug-cycle fix (00058, DROP+CREATE × 4):** the 4 exercise RPCs from 00034 (`fn_exercises_localized`, `fn_search_exercises_localized`, `fn_insert_user_exercise`, `fn_update_user_exercise`) had RETURNS TABLE shapes that stripped `uses_bodyweight_load`, defeating the prompt coordinator (Dart received `usesBodyweightLoad: false` from the picker). Caught by the full E2E regression. DROP+CREATE required because RETURNS TABLE shape changes disallow `CREATE OR REPLACE`.
- **Dart:** `Profile.bodyweightKg` + `Exercise.usesBodyweightLoad` Freezed fields; `ProfileRepository.upsertProfile(bodyweightKg:)` extension; `XpEvent.fromJson` factory promotes 2 new payload keys (Phase 24a precedent); Hive cache schema bump v1 (clears stale Exercise cache lacking the new field; preserves `userPrefs` + `offlineQueue`); new `BodyweightPromptCoordinator` (one-shot session prompt, dismissable forever via Hive flag); reusable `showBodyweightEditorSheet` from `lib/features/profile/ui/widgets/bodyweight_row.dart` (deep-linked from active workout prompt).
- **UI:** Profile settings gains a "Body weight" row + edit bottom sheet (en+pt l10n; lbs unit conversion; 25–250 kg validation); active workout shows a lazy SnackBar prompt on first qualifying set when bodyweight not set ("Set now" / "Skip" actions). Reviewer cycle added the `container: true + explicitChildNodes: true` pair-rule properties to 3 `Semantics(identifier:)` nodes per `cluster_semantics_identifier_pair_rule`.
- **Bug-cycle fix #2 (`active_workout_screen.dart`):** the `ref.listen` for the prompt was at screen-state level (above `SnackBarTapOutDismissScope`), so `scope.maybeOf(context)` always returned null and the coordinator's defensive branch silently swallowed every fire. Moved listener into `_ActiveWorkoutBody` (descendant of scope). Added regression-guard widget test that mounts the full `ActiveWorkoutScreen` and verifies the SnackBar surfaces through the production wiring path. New cluster: `cluster_inherited_widget_context_above_scope` (worth adding to MEMORY.md ledger).
- **Verification:** unit/widget 2689/2689 (was 2622 pre-24c; +67 new across xp_event factory promotion, profile model, exercise model, hive service, bodyweight_row, prompt coordinator); integration 39/39 (was 35; +4 bodyweight payload cases — pure BW, BW+belt, flag-off, NULL-BW graceful fallback); Android debug APK clean; `npx supabase db reset` clean through 00058 (DO-blocks did not trip); E2E full regression 241/241 passed (29.3 min), 62 skipped, 0 failures, 0 flaky after both bug-cycle fixes. Hosted spot-check confirms 20 bodyweight slugs + `fn_exercises_localized` surfaces `uses_bodyweight_load: true` for `pull_up`.
- **Python parity:** `USES_BODYWEIGHT_LOAD_BY_SLUG` (20 slugs) + `effective_weight` helper in `tasks/rpg-xp-simulation.py`; 4 new fixture boundary scenarios in `set_xp_examples`; `backfill_replay` legs rank 38→39, +5.8% legs XP from `walking_lunges` bodyweight load.
- **Out of scope (24d):** Six-profile × 12-week calibration sign-off (24d). Onboarding bodyweight prompt deferred to Launch Phase. Backfill of historical xp_events explicitly forward-only.

### Phase 24d: Calibration Sign-off + Production Propagation (PR #229)

> Closes Phase 24. Six-archetype × 12-week balance simulation against the 6 acceptance criteria; iter-3 sign-off propagated to all 4 production sites in lockstep. **Constants snapshot is the launch baseline** — future tuning is a new phase. Permanent reference: `docs/xp-balance-baseline.md`.

- **Sim methodology:** 6 archetypes per spec (Beginner, Intermediate compound, Advanced powerlifter, Hypertrophy bodybuilder, Bodyweight only, Machine only) × 12 weeks each. Existing 6 CONSISTENCY archetypes (beginner/intermediate/advanced/stagnant/comeback/vacationer) preserved alongside for future calibration phases. Sim-only iter 1 surfaced 1 hard fail (machine_only outranking intermediate, 1.088×) + 3 borderlines. Iter 2 (V=0.60, cap=15) narrowed everything; iter 3 (added over_cap=0.3 + T4 −0.05 across 28 slugs) cleared the hard fail and the powerlifter ratio. Final verdict: 4/6 PASS, 0 hard fail, 2 borderlines (C2 spread 31% / target 25%; C3 BW overshoot 23.4% / target 20%) explicitly accepted as documented deviations — both move in safe directions and both are structural (closing C2 needs a Phase 25+ intensity bonus the framework doesn't have; closing C3 partially undoes 24c's competitive-bodyweight intent).
- **Mid-phase instrumentation bug caught:** sim's `_CALIBRATION_ATTRIBUTION` had 6 silently-empty entries + 15 drifted from migration 00053 — surfaced by criterion 6 outlier scan before any tuning landed. Fixed all 21; iter-1 numbers re-baselined +18% to +131% per archetype before iter-2 tuning began. Without this catch, every "FAIL" verdict would have been a measurement artifact and tuning would have chased phantoms.
- **Constants tuned (forward-only — past xp_events stay frozen):** `VOLUME_EXPONENT 0.65→0.60` (more sub-linear), `WEEKLY_CAP_SETS 20→15` (tighter ceiling), `OVER_CAP_MULTIPLIER 0.5→0.3` (stronger penalty past cap), 28 T4 slugs `difficulty_mult −0.05` each (resolves machine-vs-free-weight inversion; preserves T4 < T3 ordering — framework §2 updated to T4=0.90 baseline).
- **Sites updated atomically (4 production sites in lockstep):** Dart `XpCalculator` constants; SQL migration 00059 with `rpg_base_xp` helper update so all 3 RPCs centralize via one place; Python sim canonical (`_CALIBRATION_*` override scaffolding deleted); fixture regenerated. The 28-slug T4 list lives in both the migration UPDATE block and the sim's `DIFFICULTY_MULT_BY_SLUG` (sim mirror is partial — 23 of 28 in mirror; the 5 Phase-24b T4 additions stay absent from the partial mirror per the dict's documented invariant; production reads from the column).
- **Reviewer cycle:** 0 Blockers, 2 Warnings (stale T4 inline comments in sim; framework §3 T4 header still showing 0.95) + 2 Nits (stale 0.65 in test labels; baseline doc tier-table snapshot still 0.95) — all pure doc/comment integrity, no production logic touched. All fixed in cycle + 2 same-cluster preventive fixes (tier-table emitter; tier_mult set definition).
- **Verification:** unit/widget 2689/2689; integration 39/39; Android debug APK clean; `npx supabase db reset` clean through 00059 (DO-block: 28 T4 slugs at <=0.96 difficulty_mult); psql spot-checks pre + post hosted (leg_press 0.92 was 0.97; lat_pulldown 0.94 was 0.99; rpg_base_xp(100,8) = 55.19 was 79.43); E2E full regression 241/241 passed (30.2 min), 62 skipped, 0 failures, 0 flaky.
- **Phase 24 closed.** Library at 200 defaults; XP economy calibrated; baseline locked. Next: Phase 25 (RPE, research-first), then the Launch Phase.

---

## §5 Parked / Archived

### Phase 16: Subscription Monetization — RENAMED to "Launch Phase" backbone

> Reframed 2026-05-13 (PR #220-era roadmap restructure). Phase 16's
> locked business model, architecture, and resume checklist below are
> now the backbone of the un-numbered **Launch Phase** (see §3
> In-flight). The Launch Phase deliberately has no number so we can
> fold in additional pre-launch scope (app icon redesign, push
> notifications, data export, security review, store assets, etc.)
> without renumbering. The Phase 16 spec itself is unchanged — the
> rename is positioning only.
>
> Implementation deps from 16a (server-side validation, RTDN webhook,
> entitlements view, GCP `repsaga-prod` migration) are already shipped
> in PR #93 + PR #99. What's still to do: 16b/c/d (paywall UI, hard
> gate, analytics + launch gate) + the manual / external items listed
> in §3 → Launch Phase.


> Trial-to-paywall model. No free tier — users get full app during 14-day trial, then subscribe to continue. Gamification progress (Phase 17-18) becomes the retention lever via loss aversion: letting the sub lapse freezes accumulated XP, levels, and streaks behind the paywall.

**Status:** PR #93 (16a backend) + PR #99 (GCP migration to `repsaga-prod`) shipped. External infrastructure ready: SA, Pub/Sub topic/push-sub, Supabase secrets rotated, Edge Functions redeployed. Test notification verified end-to-end (Play → Pub/Sub → `rtdn-webhook` 200). **What's blocked:** 16b (paywall UI + onboarding rewire), 16c (hard gate), 16d (analytics + launch gate). 16b is internal code work with no external blockers — **deferred by choice** to ship Phase 17 RPG first as the retention moat.

#### Business Model (locked)

- **Monthly:** R$19,90 / $3,99 / €3,99 · **Annual:** R$119,90 / $23,99 / €23,99 (~50% discount vs monthly-equivalent)
- **Currency & reach:** Global from day one. Explicit prices for BRL, USD, EUR. PPP-aware auto-conversion enabled in Play Console for all other countries. Merchant account location (Brazil) determines payout currency (BRL) and tax jurisdiction — NOT buyer eligibility.
- **Trial:** 14-day free trial via Play intro offer on both base plans. One trial per Google account (Play-enforced).
- **Gating:** Hard paywall — no feature-tier split. Trial OR active sub → full access. No trial + no sub → paywall-only.
- **No lifetime.** **No installment base plan** at launch (can add post-launch as a second Brazilian base plan).
- **Offline grace:** 7 days past server `expires_at` before locking features.

#### Architecture (locked)

- **Package:** `in_app_purchase ^3.2.x` over Play Billing Library 7+. No RevenueCat — Supabase Edge Functions replace RC's server.
- **Server validation:** Every purchase token validated server-side via `validate-purchase` Edge Function calling Google Play Developer API `purchases.subscriptionsv2.get`. Zero client writes to entitlement state.
- **Acknowledgement:** Edge Function calls `purchases.subscriptions.acknowledge` within 3 days (Google auto-refunds unacknowledged subs).
- **RTDN:** Google Cloud Pub/Sub push → `rtdn-webhook` Edge Function. Handles all 10 notification types. Pub/Sub JWT verified on inbound against Google's public keys.
- **Idempotency:** `subscription_events` audit log with `UNIQUE(purchase_token, notification_type, event_time)` — duplicate RTDNs return 200 immediately.
- **Fallback:** pg_cron reconciliation job every 6 h polls `purchases.subscriptionsv2.get` for subs with `expires_at > now() - interval '7 days'` in case Pub/Sub misses events.
- **Entitlement read path:** `entitlements` SQL view derives state from `subscriptions` row; client reads view only.
- **Offline cache:** Hive box `entitlement_cache` with `cached_at` + `offline_expires_at = server_expires_at + 7d`.
- **Security binding:** `obfuscatedAccountId = supabase_user_id` on every `PurchaseParam`. Edge Function validates JWT user_id matches `obfuscatedExternalAccountId` in Play API response.

#### Resume checklist (when Phase 16 unparks)

1. Generate upload keystore: `keytool -genkey -keystore android/keystore/repsaga-release.jks -alias repsaga-release -keyalg RSA -keysize 2048 -validity 10000`
2. Create `android/key.properties` (NOT committed) from `android/key.properties.example`
3. Back up keystore + key.properties (1Password attachment, encrypted secondary)
4. `flutter build appbundle --release`
5. Upload AAB to Play Console → Internal testing draft. Enroll in Play App Signing (Google-managed).
6. Create subscription product `repsaga_premium` per the business model above.
7. Resume Phase 16b dev per CLAUDE.md tech-lead pipeline.

#### 16a deliverables (shipped — PR #93)

- 4 migrations (`00023` subscriptions + RLS, `00024` events audit log, `00025` entitlements view with `security_invoker`, `00026` pg_cron ±7 d reconciliation via `net.http_post`). Applied to hosted Supabase.
- 2 Edge Functions: `validate-purchase` (JWT role-claim decode, `obfuscatedAccountId` binding, ack within 3 d), `rtdn-webhook` (Pub/Sub JWT verify, all 10 RTDN types, idempotent via UNIQUE).
- Shared `_shared/google_play.ts`: OAuth2 with `androidpublisher` scope, module-scope token + JWK caches, state normalizer.
- 57 Deno unit tests passing.

#### 16b/16c/16d sub-phase plans (deferred — preserved for the resume)

- **16b** — `in_app_purchase ^3.2.x` dep; `BillingException` subtype; `HiveService.entitlementCache`; Freezed `Subscription` / `SubscriptionEvent` / sealed `EntitlementState`; `SubscriptionRepository`; `EntitlementNotifier` (offline-first read, Hive cache, Realtime subscription); `PurchaseNotifier`; `PaywallScreen`, `SubscriptionSettingsCard`, `PaywallBottomSheet`. Onboarding flow rewire `/email-confirmation → onboarding → /paywall → /home`. l10n keys added.
- **16c** — `EntitlementGate` wraps app shell; router redirect guard; `/paywall` as top-level route (outside ShellRoute); `/subscription-manage` Play Store deep-link; E2E harness overrides `subscriptionRepositoryProvider` → fake active-trial so existing tests pass.
- **16d** — Analytics events (`paywall_viewed`, `trial_started`, `subscribe_completed`, etc.); Sentry breadcrumbs on every purchase state transition; grace-period banner; pg_cron reconciliation monitoring; Privacy Policy + ToS updates; launch-readiness checklist gated on Brazilian merchant account.

### Phase 19: Deferred RPG v2 + Nice-to-Have (v2.0+)

#### RPG v2 (deferred — held until post-v1 telemetry justifies build)

| Feature | Source | Notes |
|---|---|---|
| Cardio track | RPG spec §16.1 | HR-zone XP weighting + kcal fallback + RPE fallback. Schema accepts cardio events from day one (18a); only the UI surface + cardio-earning paths defer. |
| Power / Endurance sub-tracks | RPG spec §16.2 | Each body-part Rank splits into Power + Endurance sub-ranks. Needs estimated 1RM model first. |
| Synergy multipliers | RPG spec §16.3 | "Upper-Body Mastery" cross-body-part bonuses. D2-style. |
| Rival comparison | RPG spec §16.4 | Friend-only, opt-in, never global. |
| PR mini-events | RPG spec §16.5 | Enhanced overlay + shareable rune card on 1RM PR. |
| Weekly Smart Quests engine | Was 18a in superseded plan | 3-quest-per-week generator + localized pool. Replaced by RPG v1 ranks/titles as the retention spine. Reconsider if v1 telemetry shows quests would add value. |
| Training Stats radar (6-stat) | Was 18b in superseded plan | Replaced by RPG v1's Stats Deep-Dive (18d). Six-axis personal-best radar may return as an alternate visualization. |

#### Other nice-to-haves

| Feature | Notes |
|---|---|
| Plate calculator | Intermediate lifters think in plates |
| Body weight tracking | Correlate volume with weight changes |
| Dark/Light mode toggle | Some users prefer light in bright gyms |
| WearOS integration | Not critical for launch |
| App review prompt | Ask happy users for store review |
| Seasonal content | Battle passes, dungeon/boss — only if v1.0 research shows demand |

#### Phase 22/23 deferred backlog (separate phases later)

- **Offline celebration replay** — when a workout is finished offline and crosses an RPG threshold, the celebration moment is permanently lost. Queue drain awards XP correctly but `_buildAndStashCelebration` doesn't re-fire. Two design options (full pre-snapshot persist vs. notify-only on drain).
- **M9, M10 — discoverability coach marks** for set-type long-press cycle and tap-to-copy on set number. Needs onboarding design + Hive-persisted "seen" flags.
- **First-class warmup type as data model** — FitNotes/Hevy promoted warmup sets to a typed entity with their own pre-fill rules, PR exclusion, and calculator. RepSaga today treats warmup as a tag. PR-4's M1 patches the symptom; the real fix is to model warmups as their own class.
