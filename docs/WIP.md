# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 24c — Bodyweight Load Semantics

**Branch:** `feature/phase24c-bodyweight-load`
**Source:** `docs/PROJECT.md` §3 → Phase 24 sub-phase 24c row.
**Framework:** `docs/xp-difficulty-framework.md` §4 (the bodyweight question).
**Builds on:** Phase 24a (`difficulty_mult` infrastructure + payload promotion factory) + Phase 24b (200 default exercises).

### Goal

For 17 curated bodyweight exercises (pull-ups, dips, push-ups, pistol squats, etc.), compute `effective_load = profile.bodyweight_kg + sets.weight` instead of bare `sets.weight`. Snapshot the effective load + the bodyweight-used flag into `xp_events.payload` for audit trail. Forward-only — past events stay frozen.

### Boundary inventory

| Surface | Files | Change |
|---|---|---|
| Schema | NEW migration `00056_add_bodyweight_load_semantics.sql` | `profiles.bodyweight_kg numeric(5,2) NULL` + sanity CHECK; `exercises.uses_bodyweight_load BOOLEAN NOT NULL DEFAULT FALSE`; UPDATE 17 curated slugs; DO-block sanity assert |
| SQL RPCs | NEW migration `00057_record_xp_with_bodyweight_load.sql` (CREATE OR REPLACE; does NOT mutate 00040/00050/00052/00054) | Pre-fetch `profiles.bodyweight_kg` once per user; carry `uses_bodyweight_load` in batch CTE; compute `v_effective_weight = CASE ... END` per set; use in volume_load + strength_mult; snapshot to payload |
| Dart Profile model | `lib/features/profile/models/profile.dart` + repository | Add `double? bodyweightKg`; extend `upsertProfile` with optional param |
| Dart Exercise model | `lib/features/exercises/models/exercise.dart` | Add `bool usesBodyweightLoad` (`@Default(false)`); Hive cache schema bump |
| Dart XpEvent model | `lib/features/rpg/models/xp_event.dart` | Extend `fromJson` factory to promote `effective_load` + `bodyweight_used` from payload (Phase 24a precedent) |
| Python sim | `tasks/rpg-xp-simulation.py` + `test/fixtures/generate_rpg_fixtures.py` | `USES_BODYWEIGHT_LOAD_BY_SLUG`; effective_load in `compute_set_xp`; new boundary scenarios in fixture (pure BW / BW+belt / not-BW / null-BW); regenerate `rpg_xp_fixtures.json` |
| Tests | `xp_calculator_test.dart`, `rpg_record_set_xp_test.dart`, `rpg_backfill_test.dart`, `rpg_backfill_resume_test.dart`, NEW `xp_event_test.dart` cases | 6 new XpEvent unit tests + 4 new integration test cases + fixture-driven re-baselining |
| Profile UI | `lib/features/profile/ui/profile_settings_screen.dart` (+ l10n) | New "Body weight" row + edit bottom sheet + validation + widget tests |
| Active workout UI | `lib/features/workouts/ui/...` (+ Hive `user_prefs` + l10n) | One-shot lazy prompt on first qualifying set when bodyweight not set; dismissable forever |

**Boundary breach risks (top 3):**
1. **Dart-vs-SQL drift on effective_weight.** Mitigated by integration parity tests (1e-4 absolute tolerance) covering the 4 boundary scenarios from 24c-5.
2. **Profile bodyweight not set → silent under-counting of XP.** Mitigated by 24c-8 lazy prompt + graceful SQL fallback (`COALESCE(bodyweight_kg, 0)` keeps the math defined).
3. **Hive cache stale Exercise model lacks `usesBodyweightLoad`.** Mitigated by Hive schema version bump in 24c-2 — auto-clears cache on app launch for users on the old version.

### Curation list (17 slugs for `uses_bodyweight_load = TRUE`)

Per framework §4 + 24b additions (per inventory):
- **Pull family:** `pull_up`, `chin_up`, `wide_grip_pull_up`
- **Dip family:** `dips`, `ring_dip`, `muscle_up`
- **Push-up family:** `push_up`, `wide_push_up`, `incline_push_up`, `decline_push_up`, `diamond_push_up`, `close_grip_push_up`, `archer_push_up`
- **Squat family:** `bodyweight_squat`, `pistol_squat`
- **Lunge:** `walking_lunges`
- **Hanging:** `hanging_leg_raise`
- **Olympic gymnastics:** `handstand_push_up`
- **Body pull:** `inverted_row`
- **Eccentric (judgment call):** `nordic_curl` — flag for telemetry post-launch

Explicitly EXCLUDED: isometrics (plank, side_plank, hollow_body_hold, l_sit, dead_bug, wall_sit, copenhagen_plank), short-range crunches (crunches, sit_up, reverse_crunch, bicycle_crunch, etc.), cardio (treadmill, stationary_bike, elliptical, rowing_machine, assault_bike, jump_rope), single-joint isolation (glute_bridge family).

### Implementation checklist

#### Phase A — Schema + curation (24c-1)

- [x] `00056_add_bodyweight_load_semantics.sql`: ALTER TABLE profiles + ALTER TABLE exercises + 20 UPDATE rows (curation list expanded from WIP "17" miscount; verified all 20 slugs exist in 200-row default library) + DO-block sanity assert (`v_expected := 20`)
- [x] Verify `npx supabase db reset` clean — all 56 migrations apply, DO-block does not trip, 20 marked TRUE / 180 marked FALSE / 200 total

#### Phase B — Dart models (24c-2 + 24c-3)

- [x] Profile model + repo extension (24c-2 task #17 — added `bodyweightKg` field with `bodyweight_kg` JSON key, extended `upsertProfile(bodyweightKg:)` with omit-on-null semantics, 9 new model tests + 2 new repo tests)
- [x] Exercise model extension + Hive schema bump (24c-2 task #17 — added `usesBodyweightLoad` field with `@Default(false)`, introduced `HiveService.currentCacheSchemaVersion=1` + `migrateCacheSchema()` running after `init()` opens boxes, wipes `cacheSchemaBoxes` (excludes `userPrefs`/`offlineQueue`), 9 new exercise model tests + 6 new HiveService migration tests)
- [x] XpEvent payload promotion factory + 6 unit tests (24c-3 task #18 — added `effectiveLoad: double?` + `bodyweightUsed: bool?` Freezed fields with payload-snapshot doc comments, extended `fromJson` factory to promote `payload.effective_load` and `payload.bodyweight_used` independently of the existing `difficulty_mult` promotion (top-level wins per key, missing keys default to null), 6 new unit tests covering each promotion path + idempotency + legacy null semantics + Phase-24a regression — total 10 tests in `xp_event_test.dart`, full suite 2663/2663 green)

#### Phase C — SQL RPCs (24c-4)

- [x] `00057_record_xp_with_bodyweight_load.sql` (CREATE OR REPLACE × 3 — `record_set_xp`, `record_session_xp_batch`, `_rpg_backfill_chunk`). Pre-fetches `profiles.bodyweight_kg` once per RPC call; carries `COALESCE(ex.uses_bodyweight_load, FALSE)` on the driving SELECT (no per-iteration sub-select); computes `v_effective_weight = CASE uses_bodyweight_load THEN COALESCE(weight,0)+COALESCE(bw,0) ELSE COALESCE(weight,0) END`; feeds it to `rpg_base_xp` + `rpg_strength_mult`; snapshots `effective_load` (rounded to 4 decimals) + `bodyweight_used` between difficulty_mult and set_xp in `xp_events.payload`. `volume_load` snapshot also re-derived from `v_effective_weight` so payload reflects the bodyweight-aware base. Peak_loads writer-site guard preserved verbatim — peaks track ENTERED weight only. NOT NULL DEFAULT FALSE column COALESCE-defended for the same reason as 24a's difficulty_mult. `npx supabase db reset` clean through 00057.
- [x] Spot-check via psql DO blocks (3 per-set + 1 batch + 1 backfill = 5 scenarios, all PASS):
      A. bench (uses_bodyweight_load=FALSE), BW=70, entered=80 → effective=80, bodyweight_used=false, volume_load=640
      B. pull_up (uses_bodyweight_load=TRUE), BW=70, entered=0 → effective=70, bodyweight_used=true, volume_load=560 (=70×8)
      C. pull_up (TRUE), BW=NULL, entered=20 → effective=20 (graceful COALESCE fallback), bodyweight_used=true (flag still on)
      Batch: pull_up (BW=75, entered=0) + bench (BW=75, entered=100) in one session → 75 / 100 effective, flag-correct
      Backfill: weighted pull_up (BW=65, entered=5) → effective=70 (=65+5), volume_load=560

#### Phase D — Python sim parity + fixture regen (24c-5)

- [x] `tasks/rpg-xp-simulation.py` updated — added `USES_BODYWEIGHT_LOAD_BY_SLUG` (20-slug frozenset matching 00056), `uses_bodyweight_load(slug)` + `effective_weight(slug, entered, bw)` helpers (mirrors 00057 CASE byte-for-byte with COALESCE-on-NULL semantics), extended `compute_set_xp` with `bodyweight_kg` + `slug` kwargs (default None for backward compat) feeding effective weight into both volume_load + strength_mult numerator (peak still tracks ENTERED weight per 00057 writer-site guard), Archetype dataclass gained `bodyweight_kg: float = 70.0`, `simulate()` resolves alias→real slug + threads bodyweight to compute_set_xp. Updated docstring to list 00057 as the 4th synchronized formula site.
- [x] `generate_rpg_fixtures.py` updated — 4 new boundary scenarios appended to `fx_set_xp_examples` (pure bodyweight: pull_up 70kg/0added; weighted: ring_dip 70kg+20belt; not-bw: barbell_bench_press with bw ignored; null-bw: pull_up with NULL bw graceful fallback). Each scenario carries `bodyweight_kg` + `uses_bodyweight_load` + `entered_weight_kg` + `effective_load` informational keys; `weight_kg` is set to the already-converted effective_load so the existing fixture-driven Dart parity test consumes a bodyweight-aware value (Dart calculator stays bodyweight-agnostic). `fx_backfill_replay` threads `bodyweight_kg=75.0` + alias-resolved real slug per set, emits new per-set audit fields (`slug`, `uses_bodyweight_load`, `effective_load`) + `bodyweight_kg` at the top level. `meta` block gains `bodyweight_load_slugs` (sorted 20-slug list).
- [x] `rpg_xp_fixtures.json` regenerated — 15 set_xp_examples (was 11), `meta.bodyweight_load_slugs` present, `backfill_replay.bodyweight_kg=75.0`. Final ranks shifted only on legs (38→39) — expected, walking_lunges is the only intermediate-archetype exercise in the curated set; non-leg ranks byte-identical. Unchanged sections verified: intensity_lookup, volume_load, strength_mult, novelty_mult, cap_mult, character_level, rank_curve, vitality, attribution_distribution. Spot-check: pure_bw (70kg×8, diff=1.21) → vl=560, base≈61.14, set_xp=73.98 (matches direct math within 1e-9). All 321 RPG unit tests green against new fixture (Dart calculator never sees bodyweight — production callers pre-convert).

#### Phase E — Test re-baseline (24c-6)

- [x] Unit fixture-driven tests pass auto (2663/2663 unit tests green; xp_event_test.dart 10/10 covering Phase 24c-3 factory promotion)
- [x] 4 new integration cases (pure BW / BW+belt / not-BW / null-BW) — added `Phase 24c — bodyweight load semantics` group in `test/integration/rpg_record_set_xp_test.dart` covering pull-up/pure-BW (effective=70, vol=560), pull-up/belt-weighted (effective=90, vol=720), bench-press/flag-off (effective=80 ignoring BW=70), pull-up/null-BW (effective=20, flag stays true). Each test asserts payload.effective_load + payload.bodyweight_used + payload.volume_load match SQL semantics AND that XpEvent.fromJson promotes both new keys end-to-end (live integration parity for the 24c-3 factory). Added `bodyweightLoadForSlug(adminClient, slug)` helper to `rpg_integration_setup.dart` (companion to `difficultyMultForSlug`) for curation drift sanity checks. All 15 record_set_xp integration tests green (was 11).
- [x] Backfill replay hardcoded values updated — INVESTIGATION RESULT: no updates required. `kBackfillFixture` (in `rpg_backfill_test.dart`) uses `barbell_bench_press`, `lat_pulldown`, `barbell_squat` — none of these are in the curated 20-slug list, so `uses_bodyweight_load=FALSE` and `effective_weight = entered_weight` (CASE ELSE branch). SQL output is byte-identical to pre-24c for this fixture. `computeDartReference()` and `ExerciseDef` are unchanged. Both `rpg_backfill_test.dart` (3/3) and `rpg_backfill_resume_test.dart` (3/3) pass green without modification. The legs rank shift 38→39 and totals delta in `rpg_xp_fixtures.json` (which DOES include walking_lunges in its intermediate archetype) is unrelated to the integration tests — that fixture drives Python sim parity in unit tests, which auto-consume the regenerated values.

#### Phase F — Profile UI (24c-7)

- [x] New "Body weight" row + edit bottom sheet + l10n keys (en+pt) + widget tests (24c-7 task #22 — added `core/format/weight_unit.dart` (kg<->lbs conversions + 25–250 kg range constants mirroring the SQL CHECK), 4 new l10n keys (`profileBodyweightLabel` / `profileBodyweightNotSet` / `profileBodyweightHelper` / `profileBodyweightInvalidRange` with min/max/unit ICU placeholders so the same string serves both kg and lbs ranges), `BodyweightRow` + `BodyweightEditorSheet` in `lib/features/profile/ui/widgets/bodyweight_row.dart` (row mirrors `ProfileLanguageRow` shape: label + value + chevron, opens modal sheet on tap; sheet pre-fills converted to user's weight_unit, validates against canonical kg bounds, converts back to kg before `repository.upsertProfile(bodyweightKg:)`, then `ref.invalidate(profileProvider)` and pops with the saved kg as result for active-workout 24c-8 reuse), wired into `ProfileSettingsScreen` between Weight Unit and Weekly Goal sections, 17 new widget tests covering: not-set subtitle, en/pt locale formatting, integer-no-trailing-decimal, lbs conversion display, sheet open, kg/lbs prefill, kg/lbs save with conversion, pt comma input, below-25/above-250/empty validation, lbs-range helper text (25kg→55lbs / 250kg→551lbs), cancel-no-upsert, type-clears-error. Updated existing chevron-count assertion in `profile_screen_test.dart` from 5→6. Full suite 2680/2680 green (was 2663). Format + analyze clean.)

#### Phase G — Active workout lazy prompt (24c-8)

- [x] One-shot prompt on first qualifying set when bodyweight=null + dismissable + Hive flag + l10n + widget tests + 1 E2E (24c-8 task #23 — added `BodyweightPromptDismissalNotifier` (sync `Notifier<bool>` backed by `user_prefs` Hive box at key `bodyweight_prompt_dismissed_at`, mirrors `crashReportsEnabledProvider` pattern; survives 24c-2 cache wipe because `userPrefs` is excluded from `cacheSchemaBoxes`); added `BodyweightPromptCoordinator` owned by `_ActiveWorkoutScreenState` (mirrors discard/finish coordinator pattern, separates orchestration from `ActiveWorkoutNotifier.completeSet` so the data method stays side-effect-free); coordinator's `maybeShow(previous, next)` is called from the existing `ref.listen<AsyncValue<ActiveWorkoutState?>>` and diffs per-set-id (not per-count) to detect a fresh `isCompleted: false→true` transition on a `usesBodyweightLoad=true` exercise; gates: usesBodyweightLoad → profile.bodyweightKg=null → !dismissed → !shownThisSession; in-memory session-shot resets implicitly with screen state lifecycle; reuses `SnackBarTapOutDismissScope.showCountdownSnackBar` (extended with new optional `secondaryAction:` arg + `_SecondaryActionButton` widget for the dismissive Skip slot — additive, single-action callers unchanged); 6s duration; "Set now" deep-links into `showBodyweightEditorSheet` from 24c-7 (no UI duplication); "Skip" calls `markDismissed()`; auto-dismiss = "ask again next workout"; added 4 l10n keys (`bodyweightPromptTitle`/`bodyweightPromptSetNow`/`bodyweightPromptSkip` + `bodyweightPromptBody` reserved for future expansion) in en+pt; 8 new widget tests in `test/widget/features/workouts/active_workout_bodyweight_prompt_test.dart` covering all 5 gates + Set-now sheet open + Skip flag persistence + post-save no-reprompt; 1 new E2E in `test/e2e/specs/bodyweight-prompt.spec.ts` (tagged `@smoke`) verifying the full round-trip — prompt appears → Set now opens sheet → save 70 → finish workout → REST verifies `profile.bodyweight_kg=70` AND `xp_events.payload.effective_load=70` + `bodyweight_used=true`; new `smokeBodyweightPrompt` test user + global-setup runner forcing `bodyweight_kg=NULL`; full unit/widget suite 2688/2688 green (was 2680, +8 new); format + analyze clean.)

#### Phase H — Verification (24c-9)

- [ ] make-ci equivalent + integration + db reset + full E2E regression (NOT just smoke — Phase 24b lesson)

#### Phase I — Ship (24c-10)

- [ ] PR + reviewer + QA + ASK USER → merge + hosted apply + docs-condense PR

### Out of scope for 24c (defer to 24d / Launch)

- Six-profile × 12-week simulation calibration (Phase 24d)
- Onboarding bodyweight prompt (defer to Launch / Phase 25 — current lazy prompt covers MVP)
- Bodyweight unit conversion (lbs ↔ kg) — Phase C uses existing `weight_unit` semantics; explicit conversion tests in 24c-7
- Backfilling historical xp_events with new effective_load — explicitly forward-only per spec
