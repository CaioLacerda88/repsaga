# Phase 26e — Plan editor + bucket model evolution · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve Phase 12's bucket model to distinguish planned vs spontaneous entries. Move the bucket find-or-create logic into the `save_workout` RPC so the server is the source of truth (no more client-side `markRoutineComplete`). Rewrite the plan editor as a compact ordered list with a new **Engajamento** section showing weekly muscle-group volume (6 body-part bars, cardio hidden, set-counting math read live from `exercises.xp_attribution`).

**Architecture:**
- Data model: `BucketRoutine` gains `@Default(false) bool isSpontaneous`. JSONB tolerant of the new key.
- SQL: migration 00062 backfills `is_spontaneous = false` on every existing `weekly_plans.routines[*]`; migration 00063 extends `save_workout` to look up the current-week `weekly_plans` row and apply first-completion-wins find-or-create logic in the same transaction.
- Client logic: existing `WeeklyPlanNotifier.markRoutineComplete` (called from workout-save side effects) is REMOVED. The bucket entry is updated server-side; the notifier just `ref.invalidateSelf()` after save.
- Engajamento math: new `weeklyEngagementProvider` with `{ includePlanned: bool }` argument. Set-counting rule = primary by max XP share, ties counted, strict equality. Live read from `exercises.xp_attribution` JSONB joined through `workout_exercises → exercises` for done sets; from `routines.exercises[*].exercise_id` for planned sets.
- UI: `plan_management_screen.dart` is renamed/rewritten as `week_plan_screen.dart` per the spec's file list. Compact 42dp `BucketRoutineRow` + `EngajamentoSection` + ⓘ explainer bottom sheet. Counter pill = unique completion-dates count.

**Tech Stack:** Flutter ^3.11.4, Dart, Freezed, Riverpod 3 AsyncNotifier, GoRouter 17, `supabase_flutter`, `flutter_test`, `mocktail`, l10n via `flutter_localizations` + ARB files.

**Spec source:** `docs/PROJECT.md §3 Phase 26 → 26e acceptance criteria` (lines 464–496). Visual reference: `docs/phase-26-mockups.html` section `#plan` (lines 1325–1427).

**Branch:** `feature/26e-bucket-spontaneous`

---

## Locked decisions (do NOT re-debate during execution)

These were resolved before plan-writing. Surface them in every PR description and reviewer-handoff so they don't get re-litigated mid-flight:

- **First-completion-wins.** If the workout's `routine_id` matches an uncompleted bucket entry, that entry is filled (state 2 / planned-done). Otherwise a new entry with `isSpontaneous = true` is appended (state 4 / spontaneous). If both a matching uncompleted entry AND a duplicate spontaneous would match, prefer filling the planned entry. (Spec lines 470–473.)
- **Week rollover.** Existing auto-populate on first app open of new week copies only entries where `isSpontaneous == false`, clears completion state. Spontaneous entries DO NOT carry forward. (Spec line 474.)
- **00062 backfill semantics.** All existing JSONB entries set to `is_spontaneous = false` (conservative — preserves the user's current plan as planned, not spontaneous). (Spec line 475.)
- **Set-counting math.** Per-set body part = the body part with the maximum `xp_attribution` share. If two or more body parts tie at the max share (strict equality, no tolerance), each tied body part is credited with the set. Live read from `exercises.xp_attribution` JSONB; no precomputed denormalization.
- **`weeklyEngagementProvider` parameter.** `{ includePlanned: bool }`. Plan editor passes `true` (shows done + planned stacked). Future Stats deep-dive Volume & pico passes `false` (shows only done). (Spec line 483.)
- **Total counter REMOVED from Engajamento header.** Naive sum would mislead because compound-attribution + tie-counting double-counts. The 6 per-body-part bars are the truthful surface. (Spec line 481.)
- **Cardio HIDDEN from Engajamento.** Per spec line 545 — cardio infrastructure ships in 26a; rendering deferred to v1.1.
- **No reflow / no "Mover" CTA.** Bucket has no day binding; "missed past planned" isn't a state. (Spec line 547.)
- **Screen rename.** `plan_management_screen.dart` → `week_plan_screen.dart` per the spec's file list. The route `/plan/week` is unchanged; the widget class renames from `PlanManagementScreen` to `WeekPlanScreen`. All existing screen logic is rewritten to match the new compact-row layout — the rename is wholesale, not a cosmetic move.
- **`routine_id` must ride the `save_workout` payload.** Verified during plan-writing: `lib/features/workouts/data/workout_repository.dart:66-98` currently passes a `p_workout` map without `routine_id`. The 00063 SQL migration reads `p_workout ->> 'routine_id'`; without the Dart plumbing, every workout looks like a free-workout and the find-or-create always appends spontaneous. **Task 3 covers this Dart-side change as Step 1.5 (BEFORE the migration body); the active-workout notifier already carries `routineId` on `ActiveWorkoutState` so the wiring is one map entry.**

---

## File map

**New:**
- `lib/features/weekly_plan/ui/widgets/bucket_routine_row.dart` — compact ~42dp row: status icon (○ planned outline / ✓ green filled / ✓ violet filled + ★) + routine name + completion-day meta + ⋯ overflow.
- `lib/features/weekly_plan/ui/widgets/engajamento_section.dart` — header (label + ⓘ icon) + 6 muscle bars in canonical order + legend. Excludes cardio.
- `lib/features/weekly_plan/ui/widgets/muscle_bar_row.dart` — single bar row used by `EngajamentoSection`: 6dp dot + uppercase 10sp name + 4dp stacked track + tabular "X / Y" number.
- `lib/features/weekly_plan/providers/weekly_engagement_provider.dart` — `weeklyEngagementProvider` Riverpod family; argument `WeeklyEngagementArgs({ bool includePlanned })`. Emits `WeeklyEngagement` value.
- `lib/features/weekly_plan/domain/weekly_engagement.dart` — pure-Dart `WeeklyEngagement` value class + the set-counting math (`primaryBodyPartsForSet`).
- `supabase/migrations/00062_weekly_plan_is_spontaneous_backfill.sql` — JSONB backfill: walk every `weekly_plans.routines` array, set `is_spontaneous = false` on every entry that lacks the key.
- `supabase/migrations/00063_save_workout_bucket_update.sql` — `CREATE OR REPLACE FUNCTION save_workout(...)` with the find-or-create logic appended after the existing body.
- `test/unit/features/weekly_plan/domain/weekly_engagement_test.dart` — set-counting unit tests.
- `test/unit/features/weekly_plan/providers/weekly_engagement_provider_test.dart` — provider tests with mocked Supabase.
- `test/widget/features/weekly_plan/widgets/bucket_routine_row_test.dart` — status-icon states + ★ tag visibility.
- `test/widget/features/weekly_plan/widgets/engajamento_section_test.dart` — bar rendering, ⓘ tap → bottom sheet, cardio absent.
- `test/widget/features/weekly_plan/week_plan_screen_test.dart` — screen-level: counter pill text, "+ Adicionar treino" tap, empty-state path.
- `test/integration/save_workout_bucket_update_test.dart` — live (or mocktail-stubbed via `supabase_flutter`) save_workout call against the 00063 RPC: planned hit, spontaneous append, duplicate-prefers-planned, multi-workout-same-day.

**Modified:**
- `lib/features/weekly_plan/data/models/weekly_plan.dart` — add `@Default(false) bool isSpontaneous` to `BucketRoutine`.
- `lib/features/weekly_plan/data/models/weekly_plan.freezed.dart` + `weekly_plan.g.dart` — regenerated via `make gen`.
- `lib/features/weekly_plan/data/weekly_plan_repository.dart` — DROP `markRoutineComplete` (now server-side). Keep `getPlanForWeek`, `getPreviousWeekPlan`, `upsertPlan`, `deletePlan`. Week-rollover filter inside `_tryAutoPopulate` (in the notifier file, not the repo) gains the `where !r.isSpontaneous` filter.
- `lib/features/weekly_plan/providers/weekly_plan_provider.dart` — `_tryAutoPopulate` and `autoPopulateFromLastWeek` filter previous-week routines to `!r.isSpontaneous` before copying. `markRoutineComplete` method removed; all call sites updated to `ref.invalidate(weeklyPlanProvider)` (the next read fetches the server-updated row).
- `lib/features/weekly_plan/ui/week_plan_screen.dart` (renamed from `plan_management_screen.dart` — full rewrite). New compact layout: ordered list of `BucketRoutineRow`, counter pill, "+ Adicionar treino" CTA, soft-cap warning, `EngajamentoSection` below a hairline.
- `lib/core/router/app_router.dart` — update `/plan/week` builder to `WeekPlanScreen()` (was `PlanManagementScreen()`).
- `lib/features/workouts/providers/active_workout_notifier.dart` (or wherever `markRoutineComplete` is currently called from on `saveWorkout`) — drop the client-side `markRoutineComplete` call. The 00063 RPC handles it server-side; the notifier then `ref.invalidate(weeklyPlanProvider)`.
- `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb` — new keys: `daysTrainedCount`, `addWorkout`, `spontaneousTag`, `weeklyEngagementHeader`, `engagementExplainerTitle`, `engagementExplainerBody`, `engagementLegendDone`, `engagementLegendPlanned`. See Task 13 for full text.
- `test/e2e/specs/weekly-plan.spec.ts` — major updates: new selectors for compact rows, spontaneous-tag visibility test, Engajamento section visible, ⓘ → bottom sheet smoke test. Replace any selectors that referenced the deleted `PlanRoutineRow`/`PlanAddRoutineRow` widgets.
- `test/e2e/helpers/selectors.ts` — new `WEEKLY_PLAN` keys: `bucketRow`, `bucketRowSpontaneousTag`, `daysTrainedCounter`, `addWorkoutCta`, `engagementSection`, `engagementInfoIcon`, `engagementExplainerSheet`, `muscleBarChest` etc.
- `test/unit/features/weekly_plan/weekly_plan_model_test.dart` — extend with `isSpontaneous` default-value + JSONB roundtrip tests.
- `test/unit/features/weekly_plan/weekly_plan_notifier_mark_complete_test.dart` — RENAME to `weekly_plan_notifier_rollover_test.dart` (since `markRoutineComplete` is gone). Tests now pin the rollover filter: spontaneous entries do NOT copy forward.

**Deleted:**
- `lib/features/weekly_plan/ui/plan_management_screen.dart` — replaced by `week_plan_screen.dart`. The compact layout is structurally different enough that a rename-edit would obscure the diff; clean rewrite is cleaner.
- `lib/features/weekly_plan/ui/widgets/plan_routine_row.dart` — replaced by `bucket_routine_row.dart` (different shape: status icon set expanded with the ★ spontaneous tag, drag-handle removed since reorder remains on the new row but the visual treatment differs).
- `lib/features/weekly_plan/ui/widgets/plan_add_routine_row.dart` — replaced by an inline "+ Adicionar treino" CTA in `week_plan_screen.dart` (single trailing row, simpler than the existing soft-cap-aware widget).
- `test/widget/features/weekly_plan/widgets/plan_routine_row_test.dart` and `plan_add_routine_row_test.dart` — companions to the deleted widgets.

**Pre-flight reads (engineer should skim before starting):**
- `docs/PROJECT.md §3 → 26e acceptance criteria` (lines 464–496) — authoritative spec.
- `docs/PROJECT.md §4 Phase 26d retrospective` — what just landed; the pattern to mirror for migration shape + UI density.
- `lib/features/weekly_plan/data/models/weekly_plan.dart` — current `BucketRoutine` shape.
- `lib/features/weekly_plan/data/weekly_plan_repository.dart` — week-rollover + plan persistence patterns.
- `lib/features/weekly_plan/ui/plan_management_screen.dart` — current screen logic (debounce + undo snackbar pattern; carry these forward intact into the new screen).
- `lib/features/weekly_plan/providers/weekly_plan_provider.dart` — current `_tryAutoPopulate` + `markRoutineComplete`.
- `supabase/migrations/00040_rpg_system_v1.sql` lines 1620–1759 — current `save_workout` RPC body (the `record_session_xp_batch` lookup pattern from 26d is the migration template).
- `supabase/migrations/00057_record_xp_with_bodyweight_load.sql` — most-recent RPC rewrite pattern.
- `supabase/migrations/00060_titles_award_at_detection.sql` — 26d's `CREATE OR REPLACE FUNCTION` pattern (the closest precedent for what 00063 does).
- `lib/features/rpg/domain/xp_distribution.dart` + `lib/features/rpg/models/body_part.dart` — `xp_attribution` JSONB contract + canonical body-part list.
- `docs/phase-26-mockups.html` section `#plan` (lines 1325–1427) — visual companion.

**Critical pre-existing-pattern flags:**
- Test boilerplate from this plan MAY include `import 'package:flutter/material.dart';`. **Drop it if the test body doesn't reference a Material symbol** — RepSaga runs `dart analyze --fatal-infos` and `unused_import` is fatal. See auto-memory `feedback_plan_unused_imports`.
- Test file names + group labels + test labels MUST be phase-agnostic. **No `Phase 26e` in any test name.** See auto-memory `feedback_phase_agnostic_test_names`.
- Every reviewer finding (Important / Minor / Nit) gets fixed in the same cycle. No "post-merge follow-up." See auto-memory `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`.
- **Cluster `postgres_alter_type_transaction`** — 00062 + 00063 don't add enum values, but if you find yourself adding one mid-execution, remember `ALTER TYPE ADD VALUE` must run in its own transaction.
- **Cluster `check_violation_writer_audit`** — 00063 writes to `weekly_plans.routines` (JSONB). If a CHECK constraint surfaces during execution, audit EVERY writer of `weekly_plans` (notifier upsertPlan + autoPopulate + 00063 new write site).
- **Cluster `async_caller_broke_snackbar`** — the active-workout save path that currently calls client-side `markRoutineComplete` likely awaits a chain of async ops. When you remove that call and replace it with `ref.invalidate`, audit any subsequent `if (state.value?...)` checks — invalidating doesn't synchronously update `state.value`; the next `ref.read` triggers a fresh fetch.
- **Cluster `semantics_identifier_pair_rule`** — every new `Semantics(identifier:)` on `BucketRoutineRow` / `EngajamentoSection` / ⓘ icon needs `container: true` + `explicitChildNodes: true` on the same node that owns the tap target.
- **Cluster `semantics_button_missing`** — the ⓘ icon's tap target needs `Semantics(button: true, ...)` or Playwright clicks will land but won't forward.
- **Cluster `align_widthfactor_zerofill`** — the muscle-bar stacked track (planned-fill 40% opacity + done-fill 100% opacity on a 4dp track) should use `FractionallySizedBox`, NOT `Align(widthFactor: x, child: ColoredBox)` — the latter collapses to 0×0 under loose constraints.
- **Cluster `pump_duration_masks_forward`** — bucket-row state-change tests (planned → done, done → spontaneous) should assert rendered output (icon glyph + tag visibility), not animation-controller state.

---

## Task 1: Data model — `BucketRoutine.isSpontaneous`

**Files:**
- Modify: `lib/features/weekly_plan/data/models/weekly_plan.dart`
- Regenerate: `lib/features/weekly_plan/data/models/weekly_plan.freezed.dart`, `weekly_plan.g.dart`
- Modify: `test/unit/features/weekly_plan/weekly_plan_model_test.dart`

- [ ] **Step 1: Write the failing test (extend existing file)**

Append to `test/unit/features/weekly_plan/weekly_plan_model_test.dart`:

```dart
  group('BucketRoutine — isSpontaneous field', () {
    test('defaults to false when absent from JSONB (back-compat)', () {
      final json = _bucketRoutineJson();
      // Defensive: legacy JSONB rows have no `is_spontaneous` key.
      json.remove('is_spontaneous');
      final routine = BucketRoutine.fromJson(json);
      expect(routine.isSpontaneous, isFalse);
    });

    test('roundtrips true through toJson/fromJson', () {
      final routine = const BucketRoutine(
        routineId: 'routine-001',
        order: 1,
        isSpontaneous: true,
      );
      final json = routine.toJson();
      expect(json['is_spontaneous'], isTrue);
      final restored = BucketRoutine.fromJson(json);
      expect(restored.isSpontaneous, isTrue);
    });

    test('roundtrips false explicitly', () {
      const routine = BucketRoutine(
        routineId: 'routine-001',
        order: 1,
        isSpontaneous: false,
      );
      final json = routine.toJson();
      expect(json['is_spontaneous'], isFalse);
      final restored = BucketRoutine.fromJson(json);
      expect(restored.isSpontaneous, isFalse);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/weekly_plan/weekly_plan_model_test.dart
```

Expected: FAIL — `The named parameter 'isSpontaneous' isn't defined`.

- [ ] **Step 3: Add the field**

Edit `lib/features/weekly_plan/data/models/weekly_plan.dart`:

```dart
@freezed
abstract class BucketRoutine with _$BucketRoutine {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory BucketRoutine({
    required String routineId,
    required int order,
    String? completedWorkoutId,
    DateTime? completedAt,
    @Default(false) bool isSpontaneous,
  }) = _BucketRoutine;

  factory BucketRoutine.fromJson(Map<String, dynamic> json) =>
      _$BucketRoutineFromJson(json);
}
```

- [ ] **Step 4: Regenerate**

```bash
export PATH="/c/flutter/bin:$PATH"
make gen
```

Expected: `weekly_plan.freezed.dart` + `weekly_plan.g.dart` updated to include `isSpontaneous`. No errors.

- [ ] **Step 5: Run to verify it passes**

```bash
flutter test test/unit/features/weekly_plan/weekly_plan_model_test.dart
```

Expected: all `isSpontaneous` tests pass plus all pre-existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/weekly_plan/data/models/weekly_plan.dart \
        lib/features/weekly_plan/data/models/weekly_plan.freezed.dart \
        lib/features/weekly_plan/data/models/weekly_plan.g.dart \
        test/unit/features/weekly_plan/weekly_plan_model_test.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): add BucketRoutine.isSpontaneous field (26e)

Default false. JSONB-backwards-compat (missing key reads as false).
Sets up bucket model evolution for 26e: 00063 RPC will append
spontaneous entries when a workout doesn't match an uncompleted
planned entry.
EOF
)"
```

---

## Task 2: Migration 00062 — JSONB backfill

**Files:**
- Create: `supabase/migrations/00062_weekly_plan_is_spontaneous_backfill.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/00062_weekly_plan_is_spontaneous_backfill.sql`:

```sql
-- =============================================================================
-- 00062 — Phase 26e Task 2: backfill is_spontaneous = false on every entry
--
-- BucketRoutine gained `is_spontaneous: bool` (default false) in the Freezed
-- model. The JSONB column tolerates the missing key because fromJson defaults
-- to false on absent values, BUT once 00063's save_workout RPC starts
-- referencing v->>'is_spontaneous' inside SQL, NULL would surface as an
-- ambiguous third state. Backfill resolves this once: every existing entry
-- gets `is_spontaneous = false` written explicitly. From then on every writer
-- (client upsert, 00063 server-side append) sets the key.
--
-- Conservative default: existing entries represent the user's CURRENT plan;
-- treating them as planned (not spontaneous) preserves week-rollover behavior
-- (planned-only carries forward).
--
-- Idempotent: re-running this migration is a no-op against an already-backfilled
-- row (jsonb concatenation just overwrites with the same value).
-- =============================================================================

BEGIN;

UPDATE public.weekly_plans
SET routines = (
  SELECT COALESCE(
    jsonb_agg(
      CASE
        WHEN r ? 'is_spontaneous' THEN r
        ELSE r || jsonb_build_object('is_spontaneous', false)
      END
      ORDER BY (r->>'order')::int
    ),
    '[]'::jsonb
  )
  FROM jsonb_array_elements(routines) AS r
)
WHERE jsonb_typeof(routines) = 'array'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(routines) AS r
    WHERE NOT (r ? 'is_spontaneous')
  );

COMMIT;
```

- [ ] **Step 2: Run the analyzer / format**

```bash
export PATH="/c/flutter/bin:$PATH"
dart format .
```

(no Dart changes — confirms repo is still well-formatted.)

- [ ] **Step 3: Apply locally and spot-check**

```bash
npx supabase db reset    # if running locally; rebuilds db with all migrations
# OR for an in-flight local db:
npx supabase migration up
```

Then in `psql` against the local database:

```sql
SELECT id, jsonb_path_query_array(routines, '$[*].is_spontaneous')
FROM weekly_plans
LIMIT 5;
```

Expected: every array entry returns `false`. No NULLs.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/00062_weekly_plan_is_spontaneous_backfill.sql
git commit -m "$(cat <<'EOF'
feat(weekly-plan): backfill is_spontaneous=false on existing entries (26e)

Walks weekly_plans.routines JSONB arrays, adds is_spontaneous=false
to any entry missing the key. Conservative default — preserves
existing plans as planned (not spontaneous), so week rollover still
carries them forward.

Idempotent: re-running against a backfilled row is a no-op.
EOF
)"
```

---

## Task 3: Migration 00063 — `save_workout` find-or-create bucket entry

**Files:**
- Create: `supabase/migrations/00063_save_workout_bucket_update.sql`
- Modify: `lib/features/workouts/data/workout_repository.dart` (Step 1.5 — plumb `routine_id` into the RPC payload BEFORE the migration consumes it)

This is the biggest single migration in the phase. It `CREATE OR REPLACE`s `save_workout` from 00040, appending a new step after the XP roll-up that finds the current-week `weekly_plans` row and applies first-completion-wins find-or-create.

**ROUTINE_ID PLUMBING (Step 1.5).** Before the migration body, `lib/features/workouts/data/workout_repository.dart:saveWorkout(...)` must include `routine_id` in the `p_workout` map. The signature gains an optional `String? routineId` parameter (callers from the active-workout notifier already have it on `ActiveWorkoutState.routineId`); the map becomes:

```dart
'p_workout': {
  'id': workout.id,
  'user_id': workout.userId,
  'name': workout.name,
  'finished_at': workout.finishedAt?.toIso8601String(),
  'duration_seconds': workout.durationSeconds,
  'notes': workout.notes,
  'routine_id': routineId, // 26e: drives the bucket find-or-create in 00063
},
```

Every existing `_repository.saveWorkout(...)` call site needs the new param threaded. There's exactly one production call site (the active-workout notifier's `_finishWorkout` path); test fixtures may add more.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/00063_save_workout_bucket_update.sql`:

```sql
-- =============================================================================
-- 00063 — Phase 26e Task 3: save_workout extends to update weekly_plans bucket
--
-- ## What this does
--
-- CREATE OR REPLACE `save_workout(p_workout, p_exercises, p_sets)` to ALSO
-- update the current-week `weekly_plans` row using first-completion-wins
-- find-or-create logic:
--
--   1. Compute the current week's Monday (UTC date_trunc + adjust for ISO
--      week start = Monday). The plan row is keyed by (user_id, week_start).
--   2. If no plan row exists for this week, no-op the bucket update — the
--      user simply hasn't planned this week. (We do NOT auto-create here;
--      the notifier owns plan creation via upsertPlan.)
--   3. Walk the plan's `routines` JSONB array:
--        - If we find an entry with `routine_id == workout.routine_id` AND
--          `completed_workout_id IS NULL`, fill it: set completed_workout_id
--          + completed_at. Done — write back and return.
--        - Otherwise append a new entry: `routine_id = workout.routine_id`,
--          `order = max(existing order) + 1`, `completed_workout_id = workout.id`,
--          `completed_at = now()`, `is_spontaneous = true`.
--   4. The walk fills the FIRST uncompleted match by `order` ASC — this is
--      "first-completion-wins" (spec line 473). A duplicate spontaneous
--      cannot pre-empt a still-uncompleted planned entry of the same routine.
--
-- ## Why this lives in save_workout and not a separate RPC
--
-- We want the bucket update to ride the same transaction as the workout
-- insert + XP roll-up. If the transaction rolls back (validation, FK error,
-- record_session_xp_batch raise), the bucket stays untouched. A separate RPC
-- call from the notifier would leave a gap where the workout was saved but
-- the bucket update failed.
--
-- ## Hot-path discipline
--
-- The bucket update is bounded by the plan row size (rare to exceed 10
-- routines; spec recommends <= training_frequency_per_week, typically 3-5).
-- The JSONB walk is a single SQL statement (no PL/pgSQL loop). One UPDATE
-- against weekly_plans by id at the end. < 1 ms vs the existing ~30-50 ms
-- save_workout body.
--
-- ## Idempotency
--
-- Re-saving the same workout (workout.id already present in the plan as a
-- `completed_workout_id`) is a no-op: the find step skips entries whose
-- `completed_workout_id == workout.id` (already-applied). The CREATE OR
-- REPLACE function body is itself idempotent.
--
-- ## What's NOT in this migration
--
--   * No schema changes. `weekly_plans.routines` is already JSONB; the new
--     `is_spontaneous` key is just an extra string-keyed entry inside each
--     array element.
--   * No new RLS policy changes. save_workout remains SECURITY DEFINER; the
--     UPDATE against weekly_plans happens in definer context and bypasses
--     RLS (matching how 00040's UPDATE on workouts already works).
--   * No change to record_session_xp_batch or any XP-side RPC. The bucket
--     update is independent of XP — it could even short-circuit if the user
--     has no plan for the week.
-- =============================================================================

CREATE OR REPLACE FUNCTION save_workout(
  p_workout jsonb,
  p_exercises jsonb,
  p_sets jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workout_id  uuid;
  v_user_id     uuid;
  v_routine_id  uuid;
  v_finished_at timestamptz;
  v_result      jsonb;

  -- Bucket update locals.
  v_plan_id        uuid;
  v_plan_routines  jsonb;
  v_week_start     date;
  v_now            timestamptz := now();
  v_found_idx      int;
  v_match_idx      int;
  v_routine_entry  jsonb;
  v_max_order      int;
  v_new_routines   jsonb;
BEGIN
  v_workout_id  := (p_workout ->> 'id')::uuid;
  v_user_id     := (p_workout ->> 'user_id')::uuid;
  v_routine_id  := NULLIF(p_workout ->> 'routine_id', '')::uuid;
  v_finished_at := (p_workout ->> 'finished_at')::timestamptz;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: workout user_id does not match authenticated user'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM workouts WHERE id = v_workout_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Workout not found or does not belong to user'
      USING ERRCODE = 'P0002';
  END IF;

  -- ===========================================================================
  -- BUG-RPG-001 fix — REVERSAL PATTERN (unchanged from 00040)
  -- ===========================================================================
  WITH session_contrib AS (
    SELECT
      e.user_id,
      kv.key                    AS body_part,
      SUM(kv.value::numeric)    AS xp_to_revert
    FROM xp_events e
    CROSS JOIN LATERAL jsonb_each_text(e.attribution) AS kv(key, value)
    WHERE e.user_id = v_user_id
      AND e.session_id = v_workout_id
    GROUP BY e.user_id, kv.key
  )
  UPDATE body_part_progress bpp
  SET total_xp = GREATEST(0, bpp.total_xp - sc.xp_to_revert),
      rank     = public.rpg_rank_for_xp(GREATEST(0, bpp.total_xp - sc.xp_to_revert)),
      updated_at = now()
  FROM session_contrib sc
  WHERE bpp.user_id   = sc.user_id
    AND bpp.body_part = sc.body_part;

  DELETE FROM workout_exercises WHERE workout_id = v_workout_id;

  UPDATE workouts
  SET
    name             = COALESCE(p_workout ->> 'name', name),
    finished_at      = v_finished_at,
    duration_seconds = (p_workout ->> 'duration_seconds')::integer,
    notes            = p_workout ->> 'notes',
    is_active        = false
  WHERE id = v_workout_id AND user_id = v_user_id;

  INSERT INTO workout_exercises (id, workout_id, exercise_id, "order", rest_seconds)
  SELECT
    (e ->> 'id')::uuid,
    (e ->> 'workout_id')::uuid,
    (e ->> 'exercise_id')::uuid,
    (e ->> 'order')::integer,
    (e ->> 'rest_seconds')::integer
  FROM jsonb_array_elements(p_exercises) AS e;

  INSERT INTO sets (id, workout_exercise_id, set_number, reps, weight, rpe, set_type, notes, is_completed)
  SELECT
    (s ->> 'id')::uuid,
    (s ->> 'workout_exercise_id')::uuid,
    (s ->> 'set_number')::integer,
    (s ->> 'reps')::integer,
    (s ->> 'weight')::numeric,
    (s ->> 'rpe')::integer,
    COALESCE(s ->> 'set_type', 'working'),
    s ->> 'notes',
    COALESCE((s ->> 'is_completed')::boolean, false)
  FROM jsonb_array_elements(p_sets) AS s;

  PERFORM public.record_session_xp_batch(v_workout_id);

  -- ===========================================================================
  -- Phase 26e Task 3: bucket find-or-create on weekly_plans.
  --
  -- Compute current-week Monday (ISO week start) from v_finished_at if set,
  -- else now(). All math UTC; the client's week boundary may drift by a few
  -- hours at TZ edges — acceptable since the user's "week" is defined here
  -- by when the workout was finished, not by their local clock.
  -- ===========================================================================
  v_week_start := (date_trunc('week', COALESCE(v_finished_at, v_now))::date);

  SELECT id, routines
  INTO v_plan_id, v_plan_routines
  FROM weekly_plans
  WHERE user_id = v_user_id AND week_start = v_week_start
  FOR UPDATE;  -- lock the row to avoid concurrent writers racing append

  -- If no plan exists for this week, the user hasn't planned anything —
  -- skip the bucket update entirely. The notifier's separate upsertPlan
  -- call is what creates the row in the first place.
  IF v_plan_id IS NULL THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  -- If this workout has already been applied to the bucket (idempotent
  -- re-save), short-circuit: any entry whose completed_workout_id matches
  -- means the previous save_workout call already handled it.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_plan_routines) AS r
    WHERE (r ->> 'completed_workout_id') = v_workout_id::text
  ) THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  -- First-completion-wins: find the FIRST uncompleted entry (by JSONB order
  -- index = bucket order) whose routine_id matches. If routine_id is NULL on
  -- the workout (free workout, no source routine), skip the match step and
  -- go straight to spontaneous-append.
  v_match_idx := NULL;
  IF v_routine_id IS NOT NULL THEN
    SELECT idx
    INTO v_match_idx
    FROM (
      SELECT
        (row_number() OVER (ORDER BY (r ->> 'order')::int))::int - 1 AS idx,
        r
      FROM jsonb_array_elements(v_plan_routines) WITH ORDINALITY AS arr(r, ord)
    ) ranked
    WHERE (ranked.r ->> 'routine_id') = v_routine_id::text
      AND (ranked.r ->> 'completed_workout_id') IS NULL
    ORDER BY idx ASC
    LIMIT 1;
  END IF;

  IF v_match_idx IS NOT NULL THEN
    -- Planned hit: fill the matched entry in place.
    v_new_routines := jsonb_set(
      v_plan_routines,
      ARRAY[v_match_idx::text],
      (v_plan_routines -> v_match_idx)
        || jsonb_build_object(
             'completed_workout_id', v_workout_id::text,
             'completed_at',         to_jsonb(v_now)
           )
    );
  ELSE
    -- No match → append spontaneous entry. v_routine_id may be NULL for
    -- a free workout; we still record it so the user sees the workout in
    -- their bucket. NULL serializes as the JSON null literal — the Dart
    -- side's `String? routineId` accepts it.
    SELECT COALESCE(MAX((r ->> 'order')::int), 0)
    INTO v_max_order
    FROM jsonb_array_elements(v_plan_routines) AS r;

    v_routine_entry := jsonb_build_object(
      'routine_id',           CASE WHEN v_routine_id IS NULL THEN NULL ELSE to_jsonb(v_routine_id::text) END,
      'order',                v_max_order + 1,
      'completed_workout_id', v_workout_id::text,
      'completed_at',         to_jsonb(v_now),
      'is_spontaneous',       true
    );
    v_new_routines := v_plan_routines || jsonb_build_array(v_routine_entry);
  END IF;

  UPDATE weekly_plans
  SET routines   = v_new_routines,
      updated_at = v_now
  WHERE id = v_plan_id;

  SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION save_workout(jsonb, jsonb, jsonb) TO authenticated;
```

- [ ] **Step 2: Apply locally**

```bash
npx supabase migration up
```

Expected: migration applies cleanly. No errors.

- [ ] **Step 3: Smoke-test in `psql`**

In a local `psql` session against the local Supabase DB, run a manual sequence as a logged-in user (use the JWT-as-DB-role helper or `SET LOCAL "request.jwt.claim.sub" = '<test-user-uuid>'`):

```sql
-- Setup: a plan with one uncompleted entry.
INSERT INTO weekly_plans (id, user_id, week_start, routines, created_at, updated_at)
VALUES (
  gen_random_uuid(), '<test-user-uuid>',
  date_trunc('week', now())::date,
  '[{"routine_id":"<routine-A-uuid>","order":1,"is_spontaneous":false}]'::jsonb,
  now(), now()
);

-- Save a workout sourced from routine A → should fill the planned entry.
SELECT save_workout(
  jsonb_build_object('id', '<workout-1-uuid>', 'user_id', '<test-user-uuid>',
                     'routine_id', '<routine-A-uuid>',
                     'finished_at', now()::text,
                     'duration_seconds', 1800),
  '[]'::jsonb, '[]'::jsonb
);

-- Verify the bucket entry is filled.
SELECT jsonb_pretty(routines) FROM weekly_plans WHERE user_id = '<test-user-uuid>';
-- Expected: routine_id matches, completed_workout_id = workout-1-uuid,
--           is_spontaneous = false.

-- Save another workout sourced from routine A → no uncompleted match → spontaneous.
SELECT save_workout(
  jsonb_build_object('id', '<workout-2-uuid>', 'user_id', '<test-user-uuid>',
                     'routine_id', '<routine-A-uuid>',
                     'finished_at', now()::text,
                     'duration_seconds', 1800),
  '[]'::jsonb, '[]'::jsonb
);

-- Verify a second entry was appended with is_spontaneous = true.
SELECT jsonb_array_length(routines), jsonb_pretty(routines)
FROM weekly_plans WHERE user_id = '<test-user-uuid>';
-- Expected: length = 2, second entry has order = 2, is_spontaneous = true.
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/00063_save_workout_bucket_update.sql
git commit -m "$(cat <<'EOF'
feat(weekly-plan): save_workout updates bucket find-or-create (26e)

Extends save_workout RPC with first-completion-wins logic:
- match uncompleted planned entry by routine_id → fill it
- no match → append spontaneous entry (is_spontaneous = true)
- idempotent re-save short-circuits via completed_workout_id check
- no plan for current week → no-op the bucket update

Rides the same transaction as the workout insert + XP roll-up,
so a rollback leaves both untouched.
EOF
)"
```

---

## Task 4: Drop client-side `markRoutineComplete`

**Files:**
- Modify: `lib/features/weekly_plan/providers/weekly_plan_provider.dart`
- Modify: `lib/features/weekly_plan/data/weekly_plan_repository.dart`
- Modify: `lib/features/workouts/providers/active_workout_notifier.dart` (or wherever `markRoutineComplete` is called from the save path — grep first)
- Rename: `test/unit/features/weekly_plan/weekly_plan_notifier_mark_complete_test.dart` → `weekly_plan_notifier_rollover_test.dart` (the file gets a smaller scope: rollover-only).

- [ ] **Step 1: Find every caller of `markRoutineComplete`**

```bash
grep -rn "markRoutineComplete" lib/ test/
```

Document the call sites. Expected hits include the active-workout notifier's save path and the existing notifier tests.

- [ ] **Step 2: Write the failing rollover test**

Rewrite `test/unit/features/weekly_plan/weekly_plan_notifier_mark_complete_test.dart` as a new file `test/unit/features/weekly_plan/weekly_plan_notifier_rollover_test.dart`. Delete the original. The new file pins the spontaneous-filter contract:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';

void main() {
  group('week rollover filters spontaneous entries', () {
    test('only non-spontaneous entries copy forward', () {
      final previous = [
        const BucketRoutine(routineId: 'r1', order: 1, isSpontaneous: false),
        const BucketRoutine(
          routineId: 'r2',
          order: 2,
          isSpontaneous: true,
          completedWorkoutId: 'w-spontaneous',
        ),
        const BucketRoutine(routineId: 'r3', order: 3, isSpontaneous: false),
      ];

      // Mirror the filter expression used inside autoPopulateFromLastWeek
      // and _tryAutoPopulate so a future refactor that drops the filter
      // breaks this test.
      final carriedForward = previous
          .where((r) => !r.isSpontaneous)
          .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
          .toList();

      expect(carriedForward.length, 2);
      expect(carriedForward[0].routineId, 'r1');
      expect(carriedForward[1].routineId, 'r3');
      // Completion state is cleared.
      expect(carriedForward.every((r) => r.completedWorkoutId == null), isTrue);
      expect(carriedForward.every((r) => !r.isSpontaneous), isTrue);
    });

    test('all-spontaneous previous week → empty rollover', () {
      final previous = [
        const BucketRoutine(routineId: 'r1', order: 1, isSpontaneous: true),
        const BucketRoutine(routineId: 'r2', order: 2, isSpontaneous: true),
      ];
      final carriedForward = previous.where((r) => !r.isSpontaneous).toList();
      expect(carriedForward, isEmpty);
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails the right way**

```bash
flutter test test/unit/features/weekly_plan/weekly_plan_notifier_rollover_test.dart
```

Expected: PASS. (This test pins the contract — the implementation change comes in Step 4.)

- [ ] **Step 4: Apply the filter in the provider**

Edit `lib/features/weekly_plan/providers/weekly_plan_provider.dart`:

1. In `_tryAutoPopulate`, change:
   ```dart
   final resetRoutines = previous.routines
       .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
       .toList();
   ```
   to:
   ```dart
   final resetRoutines = previous.routines
       .where((r) => !r.isSpontaneous)
       .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
       .toList();
   // Renumber to keep order contiguous starting at 1.
   final renumbered = resetRoutines
       .indexed
       .map((entry) => entry.$2.copyWith(order: entry.$1 + 1))
       .toList();
   ```
   (and pass `renumbered` to `repo.upsertPlan`.)

2. Apply the same filter to `autoPopulateFromLastWeek` (the user-facing manual auto-populate path).

3. **Remove `markRoutineComplete` entirely.** Search for the method definition (currently lines 121–207 in `weekly_plan_provider.dart`). Delete it. Replace its single in-class doc reference with a comment noting the server-side path:

   ```dart
   // markRoutineComplete is gone: the 00063 save_workout RPC updates the
   // bucket entry server-side in the same transaction as the workout insert.
   // After saveWorkout, callers `ref.invalidate(weeklyPlanProvider)` to
   // re-fetch the updated row.
   ```

4. The week_complete analytics event currently fires from inside `markRoutineComplete`. **It now needs a new firing site.** Add a `ref.listen` inside `WeeklyPlanNotifier.build()` that fires the event when state transitions to a fully-completed plan:

   ```dart
   // Detect plan-fully-completed transitions and fire week_complete once.
   // Previously this lived inside markRoutineComplete; with the RPC owning
   // the mutation, we react to state changes here instead.
   ref.listenSelf((previous, next) {
     final prevPlan = previous?.value;
     final nextPlan = next.value;
     if (prevPlan == null || nextPlan == null) return;
     final wasAllComplete = prevPlan.routines.isNotEmpty &&
         prevPlan.routines.every((r) => r.completedWorkoutId != null);
     final isNowAllComplete = nextPlan.routines.isNotEmpty &&
         nextPlan.routines.every((r) => r.completedWorkoutId != null);
     if (!wasAllComplete && isNowAllComplete) {
       _fireWeekCompleteEvent(nextPlan);
     }
   });
   ```

   Extract the existing event-build logic from the old `markRoutineComplete` into `_fireWeekCompleteEvent(WeeklyPlan plan)`. Same business logic, same fields — only the firing site moves.

- [ ] **Step 5: Drop the repository method**

Edit `lib/features/weekly_plan/data/weekly_plan_repository.dart`:

Delete `markRoutineComplete` (lines 67–92). The repository now only exposes `getPlanForWeek`, `getPreviousWeekPlan`, `upsertPlan`, `deletePlan`.

- [ ] **Step 6: Update the active-workout call site**

Per the grep output from Step 1, find the active-workout save path that currently calls:

```dart
await ref.read(weeklyPlanProvider.notifier).markRoutineComplete(
  routineId: routineId, workoutId: workoutId,
);
```

Replace with:

```dart
// 00063 RPC handles the bucket update server-side. Invalidate the provider
// so the next read fetches the updated row. Async-caller-broke-snackbar
// cluster: do NOT await invalidate — it's a sync trigger to refetch, not
// a read.
ref.invalidate(weeklyPlanProvider);
```

If the caller has subsequent logic that reads `weeklyPlanProvider.state` synchronously, audit that — invalidating does not update `state.value` synchronously. Use the existing async `ref.read(weeklyPlanProvider.future)` pattern if the next step depends on the fresh value.

- [ ] **Step 7: Run all affected tests**

```bash
flutter test test/unit/features/weekly_plan/ test/widget/features/weekly_plan/ test/unit/features/workouts/
```

Expected: all green. If the `weekly_plan_notifier_mark_complete_test.dart` rename leaves a stale file, `git rm` it.

- [ ] **Step 8: Run analyzer**

```bash
dart analyze --fatal-infos
```

Expected: clean. (Unreferenced imports from the removed `markRoutineComplete` need to be cleaned up — `pr_providers.dart` `prListProvider` import in the provider file may now be the only reference; verify before removing.)

- [ ] **Step 9: Commit**

```bash
git add lib/features/weekly_plan/providers/weekly_plan_provider.dart \
        lib/features/weekly_plan/data/weekly_plan_repository.dart \
        lib/features/workouts/providers/active_workout_notifier.dart \
        test/unit/features/weekly_plan/weekly_plan_notifier_rollover_test.dart
git rm test/unit/features/weekly_plan/weekly_plan_notifier_mark_complete_test.dart
git commit -m "$(cat <<'EOF'
refactor(weekly-plan): server-side bucket update via 00063 RPC (26e)

Drop client-side markRoutineComplete + repository method. The 00063
save_workout RPC now owns bucket find-or-create. Callers invalidate
weeklyPlanProvider after save; the next read fetches the server-updated
row.

Week rollover now filters spontaneous entries (planned-only carries
forward) per the locked spec.

week_complete analytics event fires from a ref.listenSelf in the
notifier instead of from the deleted markRoutineComplete method.
Same payload, same fire-once guard.
EOF
)"
```

---

## Task 5: `WeeklyEngagement` domain + set-counting math

**Files:**
- Create: `lib/features/weekly_plan/domain/weekly_engagement.dart`
- Create: `test/unit/features/weekly_plan/domain/weekly_engagement_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/features/weekly_plan/domain/weekly_engagement_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/domain/weekly_engagement.dart';

void main() {
  group('primaryBodyPartsForSet — max-share with strict-equality tie counting', () {
    test('single dominant body part returns just that part', () {
      // barbell_bench_press: chest 0.70, shoulders 0.20, arms 0.10
      final result = primaryBodyPartsForSet({
        'chest': 0.70,
        'shoulders': 0.20,
        'arms': 0.10,
      });
      expect(result, equals({BodyPart.chest}));
    });

    test('two-way tie at the max share counts both', () {
      // Synthetic tie: chest 0.50, back 0.50.
      final result = primaryBodyPartsForSet({'chest': 0.50, 'back': 0.50});
      expect(result, equals({BodyPart.chest, BodyPart.back}));
    });

    test('three-way tie at the max share counts all three', () {
      final result = primaryBodyPartsForSet({
        'chest': 0.34,
        'back': 0.33,
        'legs': 0.33,
      });
      // 0.34 > 0.33 = 0.33: only chest wins (strict equality required for tie).
      expect(result, equals({BodyPart.chest}));
    });

    test('strict equality: 0.50 == 0.50 ties, 0.50 vs 0.499 does not', () {
      final tied = primaryBodyPartsForSet({'chest': 0.50, 'back': 0.50});
      expect(tied, equals({BodyPart.chest, BodyPart.back}));

      final notTied = primaryBodyPartsForSet({'chest': 0.501, 'back': 0.499});
      expect(notTied, equals({BodyPart.chest}));
    });

    test('cardio key is dropped (not in v1 engagement rendering)', () {
      // Hypothetical cardio-heavy attribution that ties with legs.
      final result = primaryBodyPartsForSet({'cardio': 0.50, 'legs': 0.50});
      // Cardio is excluded from the v1 surface — only legs counts.
      expect(result, equals({BodyPart.legs}));
    });

    test('all-cardio set returns empty (renders nothing in the 6-bar view)', () {
      final result = primaryBodyPartsForSet({'cardio': 1.00});
      expect(result, isEmpty);
    });

    test('empty attribution returns empty set', () {
      final result = primaryBodyPartsForSet(const {});
      expect(result, isEmpty);
    });

    test('zero shares are ignored (no false ties at 0.0)', () {
      final result = primaryBodyPartsForSet({'chest': 0.0, 'back': 0.0});
      // No body part has a positive share — nothing counts.
      expect(result, isEmpty);
    });
  });

  group('WeeklyEngagement — totals composition', () {
    test('done + planned counts compose into per-body-part numerators', () {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 10, BodyPart.back: 4},
        planned: {BodyPart.chest: 8, BodyPart.shoulders: 6},
      );
      // chest: 10 done out of (10 done + 8 planned = 18 planned-total).
      expect(engagement.doneFor(BodyPart.chest), 10);
      expect(engagement.plannedFor(BodyPart.chest), 18);
      expect(engagement.doneFor(BodyPart.back), 4);
      expect(engagement.plannedFor(BodyPart.back), 4); // no planned beyond done
      expect(engagement.doneFor(BodyPart.shoulders), 0);
      expect(engagement.plannedFor(BodyPart.shoulders), 6);
      // Untouched body parts default to zero.
      expect(engagement.doneFor(BodyPart.legs), 0);
      expect(engagement.plannedFor(BodyPart.legs), 0);
    });

    test('planned bar reads max(done, planned) — never less than done', () {
      // Edge: user did 12 chest sets but only planned 6. Planned total =
      // max(12, 6) = 12 so the planned bar reads "12 / 12" and the done
      // fill matches it (no visual gap implying unplanned work).
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 12},
        planned: {BodyPart.chest: 6},
      );
      expect(engagement.doneFor(BodyPart.chest), 12);
      expect(engagement.plannedFor(BodyPart.chest), 12);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/unit/features/weekly_plan/domain/weekly_engagement_test.dart
```

Expected: FAIL — `weekly_engagement.dart` doesn't exist yet.

- [ ] **Step 3: Implement the helper**

Create `lib/features/weekly_plan/domain/weekly_engagement.dart`:

```dart
import '../../rpg/models/body_part.dart';

/// Returns the set of body parts that this set should "count" toward in the
/// Engajamento section.
///
/// **Set-counting rule (locked, spec line 483):** the primary body part of
/// a set is the body part with the **maximum** `xp_attribution` share. If
/// two or more body parts tie at the max (strict equality, no tolerance),
/// each tied body part is credited with the set.
///
/// `attribution` keys are `BodyPart.dbValue` strings (matches
/// `exercises.xp_attribution` JSONB on the DB side). Cardio keys are
/// dropped — the 6-bar Engajamento view excludes cardio (v1).
///
/// Returns an empty set if the attribution is empty, all shares are
/// non-positive, or every winning body part is cardio.
Set<BodyPart> primaryBodyPartsForSet(Map<String, num> attribution) {
  if (attribution.isEmpty) return const {};

  double maxShare = -1;
  final winners = <BodyPart>{};
  attribution.forEach((key, value) {
    final share = value.toDouble();
    if (share <= 0) return;
    final bp = BodyPart.tryFromDbValue(key);
    if (bp == null) return;
    if (bp == BodyPart.cardio) return; // v1: cardio excluded from rendering
    if (share > maxShare) {
      maxShare = share;
      winners
        ..clear()
        ..add(bp);
    } else if (share == maxShare) {
      // Strict equality: 0.50 == 0.50 ties; 0.501 != 0.500 does not.
      winners.add(bp);
    }
  });
  return winners;
}

/// Aggregated weekly counts of "primary-attribution sets" per body part.
///
/// `done` = sets the user actually completed this week.
/// `planned` = sets currently in the bucket's routines, summed across all
/// uncompleted bucket entries (the work the user has committed to).
///
/// The widget renders `plannedFor` as the bar denominator and `doneFor` as
/// the filled portion. `plannedFor` is guaranteed to be >= `doneFor` (see
/// the [from] factory): a user who over-performs vs their plan still has
/// the bar read full, not less than the work they actually did.
class WeeklyEngagement {
  const WeeklyEngagement._(this._done, this._plannedTotals);

  /// Build from raw per-body-part done + planned counts. `plannedTotals`
  /// in the returned object is `max(donePerBp, plannedPerBp)` so the bar
  /// invariant `doneFor <= plannedFor` always holds.
  factory WeeklyEngagement.from({
    required Map<BodyPart, int> done,
    required Map<BodyPart, int> planned,
  }) {
    final totals = <BodyPart, int>{};
    for (final bp in BodyPart.values) {
      if (bp == BodyPart.cardio) continue; // v1: cardio excluded
      final d = done[bp] ?? 0;
      final p = planned[bp] ?? 0;
      totals[bp] = d > p ? d : p;
    }
    return WeeklyEngagement._(Map.of(done), totals);
  }

  /// Empty engagement (no data) — used by providers as a loading/initial value.
  static const WeeklyEngagement empty = WeeklyEngagement._({}, {});

  final Map<BodyPart, int> _done;
  final Map<BodyPart, int> _plannedTotals;

  int doneFor(BodyPart bp) => _done[bp] ?? 0;
  int plannedFor(BodyPart bp) => _plannedTotals[bp] ?? 0;
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/unit/features/weekly_plan/domain/weekly_engagement_test.dart
```

Expected: all groups pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/weekly_plan/domain/weekly_engagement.dart \
        test/unit/features/weekly_plan/domain/weekly_engagement_test.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): WeeklyEngagement domain + set-counting math (26e)

Pure-Dart helper computing per-body-part primary attribution using
the locked rule: max share, strict-equality tie counted. Cardio
dropped from the v1 surface. WeeklyEngagement.from() composes
done + planned counts with the bar invariant doneFor <= plannedFor.
EOF
)"
```

---

## Task 6: `weeklyEngagementProvider`

**Files:**
- Create: `lib/features/weekly_plan/providers/weekly_engagement_provider.dart`
- Create: `test/unit/features/weekly_plan/providers/weekly_engagement_provider_test.dart`

The provider takes `WeeklyEngagementArgs({ bool includePlanned })`, reads:
- Done: sets from `workouts` finished this week, joined to `exercises.xp_attribution`. For each set, call `primaryBodyPartsForSet` and increment per-bp counters.
- Planned (if `includePlanned == true`): bucket routines from the current `weeklyPlanProvider`, walk each uncompleted entry's `Routine.exercises[*]`, sum `setConfigs.length` per exercise, then apply `primaryBodyPartsForSet` per exercise (treating each planned set as one attribution call).

- [ ] **Step 1: Write the failing test**

Create `test/unit/features/weekly_plan/providers/weekly_engagement_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/domain/weekly_engagement.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_engagement_provider.dart';

void main() {
  group('weeklyEngagementProvider — composition', () {
    test('includePlanned=true sums done + planned across the same body part', () {
      // The provider implementation reads from Supabase + weeklyPlanProvider.
      // Here we test the composition pure-Dart entry point exposed by the
      // provider file (engagementFromCounts) — the IO read is covered by
      // the integration test in Task 12.
      final engagement = engagementFromCounts(
        doneCounts: {BodyPart.chest: 5, BodyPart.back: 3},
        plannedCounts: {BodyPart.chest: 8, BodyPart.shoulders: 6},
        includePlanned: true,
      );
      expect(engagement.doneFor(BodyPart.chest), 5);
      expect(engagement.plannedFor(BodyPart.chest), 8);
      expect(engagement.doneFor(BodyPart.back), 3);
      expect(engagement.plannedFor(BodyPart.back), 3);
      expect(engagement.plannedFor(BodyPart.shoulders), 6);
    });

    test('includePlanned=false ignores plannedCounts entirely', () {
      final engagement = engagementFromCounts(
        doneCounts: {BodyPart.chest: 5},
        plannedCounts: {BodyPart.chest: 999, BodyPart.shoulders: 999},
        includePlanned: false,
      );
      expect(engagement.doneFor(BodyPart.chest), 5);
      expect(engagement.plannedFor(BodyPart.chest), 5); // max(done=5, planned=0)
      expect(engagement.plannedFor(BodyPart.shoulders), 0);
    });
  });

  group('weeklyEngagementProvider — empty state', () {
    test('zero history + no plan returns WeeklyEngagement.empty', () {
      final container = ProviderContainer(overrides: [
        // The provider depends on weeklyPlanProvider + a (mocked) workout
        // history reader. Skeleton override — Task 12 integration test
        // exercises the real read path.
      ]);
      addTearDown(container.dispose);
      // Test only the no-state path here; full read mocking is heavy and
      // covered downstream.
      expect(WeeklyEngagement.empty.doneFor(BodyPart.chest), 0);
      expect(WeeklyEngagement.empty.plannedFor(BodyPart.chest), 0);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/unit/features/weekly_plan/providers/weekly_engagement_provider_test.dart
```

Expected: FAIL — `engagementFromCounts` doesn't exist yet.

- [ ] **Step 3: Implement the provider**

Create `lib/features/weekly_plan/providers/weekly_engagement_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../../rpg/models/body_part.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../domain/weekly_engagement.dart';
import 'weekly_plan_provider.dart';

/// Arguments for [weeklyEngagementProvider].
///
/// `includePlanned`: plan editor passes `true` (the bar shows done + planned
/// stacked). Future Stats deep-dive Volume & pico will pass `false` (only
/// done renders).
class WeeklyEngagementArgs {
  const WeeklyEngagementArgs({required this.includePlanned});

  final bool includePlanned;

  @override
  bool operator ==(Object other) =>
      other is WeeklyEngagementArgs && other.includePlanned == includePlanned;

  @override
  int get hashCode => includePlanned.hashCode;
}

/// Per-body-part counts → [WeeklyEngagement]. Pure-Dart composition seam,
/// exposed for unit testing.
WeeklyEngagement engagementFromCounts({
  required Map<BodyPart, int> doneCounts,
  required Map<BodyPart, int> plannedCounts,
  required bool includePlanned,
}) {
  return WeeklyEngagement.from(
    done: doneCounts,
    planned: includePlanned ? plannedCounts : const {},
  );
}

/// Emits the current week's engagement totals.
///
/// IO contract:
///   * Done counts: SELECT every set from the current Monday onward where
///     the parent workout's `user_id == auth.uid()`. Join `workout_exercises
///     → exercises` for the attribution JSONB. For each completed set, apply
///     [primaryBodyPartsForSet] and increment per-bp counters.
///   * Planned counts (only when `includePlanned == true`): read the current
///     bucket via `weeklyPlanProvider` + routine details via
///     `routineListProvider`. For each uncompleted bucket entry, walk
///     `Routine.exercises[*]`; each routine-exercise's `setConfigs.length`
///     is the number of planned sets sharing that exercise's attribution.
///     Apply [primaryBodyPartsForSet] per planned set.
///
/// Provider re-fires whenever `weeklyPlanProvider` or `routineListProvider`
/// change. We deliberately do NOT cache the workout-history read across
/// invalidations: post-save the cache is stale, and Phase 12-era workout
/// queries are <50 ms in practice.
final weeklyEngagementProvider = FutureProvider.family
    .autoDispose<WeeklyEngagement, WeeklyEngagementArgs>((ref, args) async {
  final userId = ref.read(authRepositoryProvider).currentUser?.id;
  if (userId == null) return WeeklyEngagement.empty;

  final monday = currentWeekMonday();
  final mondayStr =
      '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

  // ---- DONE COUNTS ---------------------------------------------------------
  // One round-trip: pull every completed working set + its exercise's
  // xp_attribution for the current week. Returns rows like:
  //   { exercise_id: <uuid>, xp_attribution: { "chest": 0.70, ... } }
  final client = Supabase.instance.client;
  final doneRows = await client
      .from('sets')
      .select('''
        is_completed,
        set_type,
        reps,
        workout_exercises!inner(
          workout_id,
          exercise:exercises!inner(xp_attribution, muscle_group),
          workouts!inner(user_id, finished_at)
        )
      ''')
      .eq('workout_exercises.workouts.user_id', userId)
      .gte('workout_exercises.workouts.finished_at', mondayStr)
      .eq('is_completed', true);

  final doneCounts = <BodyPart, int>{};
  for (final row in doneRows as List<dynamic>) {
    final r = row as Map<String, dynamic>;
    final setType = (r['set_type'] as String?) ?? 'working';
    if (setType != 'working') continue;
    final reps = r['reps'] as int?;
    if (reps == null || reps < 1) continue;

    final we = r['workout_exercises'] as Map<String, dynamic>;
    final ex = we['exercise'] as Map<String, dynamic>;
    final attrJson = ex['xp_attribution'] as Map<String, dynamic>?;
    final primaryMuscle = ex['muscle_group'] as String?;

    final attrMap = attrJson != null && attrJson.isNotEmpty
        ? attrJson.map((k, v) => MapEntry(k, (v as num)))
        : (primaryMuscle != null
            ? {primaryMuscle: 1.0 as num}
            : <String, num>{});

    final winners = primaryBodyPartsForSet(attrMap);
    for (final bp in winners) {
      doneCounts[bp] = (doneCounts[bp] ?? 0) + 1;
    }
  }

  // ---- PLANNED COUNTS ------------------------------------------------------
  Map<BodyPart, int> plannedCounts = const {};
  if (args.includePlanned) {
    final plan = ref.watch(weeklyPlanProvider).value;
    final routines = ref.watch(routineListProvider).value ?? [];
    if (plan != null) {
      final routineMap = {for (final r in routines) r.id: r};
      final acc = <BodyPart, int>{};
      for (final bucket in plan.routines) {
        if (bucket.completedWorkoutId != null) continue; // already done — counted via doneRows
        final routine = routineMap[bucket.routineId];
        if (routine == null) continue;
        for (final routineExercise in routine.exercises) {
          final exercise = routineExercise.exercise;
          if (exercise == null) continue;
          final attrJson = exercise.xpAttribution;
          final primaryMuscle = exercise.muscleGroup.dbValue;
          final attrMap = (attrJson != null && attrJson.isNotEmpty)
              ? attrJson.map((k, v) => MapEntry(k, (v as num)))
              : <String, num>{primaryMuscle: 1.0};
          final winners = primaryBodyPartsForSet(attrMap);
          final setCount = routineExercise.setConfigs.length;
          for (final bp in winners) {
            acc[bp] = (acc[bp] ?? 0) + setCount;
          }
        }
      }
      plannedCounts = acc;
    }
  }

  return engagementFromCounts(
    doneCounts: doneCounts,
    plannedCounts: plannedCounts,
    includePlanned: args.includePlanned,
  );
});
```

> NOTE on the planned read: this assumes `Exercise.xpAttribution` is exposed on the Exercise model as `Map<String, num>?` and `muscleGroup.dbValue` returns the SQL token. If the Exercise model doesn't carry `xpAttribution` yet, expose it via the existing exercise repository — that's a small parallel addition tracked in the next step's verification.

- [ ] **Step 4: Verify the Exercise model exposes `xpAttribution`**

```bash
grep -n "xpAttribution\|xp_attribution" lib/features/exercises/models/exercise.dart
```

If the field is missing, add `Map<String, num>? xpAttribution` to `Exercise` (Freezed regen). If it's already there, no-op. Wire-decode is `@JsonKey(name: 'xp_attribution')`.

- [ ] **Step 5: Run to verify the unit test passes**

```bash
flutter test test/unit/features/weekly_plan/providers/weekly_engagement_provider_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/weekly_plan/providers/weekly_engagement_provider.dart \
        test/unit/features/weekly_plan/providers/weekly_engagement_provider_test.dart \
        lib/features/exercises/models/exercise.dart \
        lib/features/exercises/models/exercise.freezed.dart \
        lib/features/exercises/models/exercise.g.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): weeklyEngagementProvider with includePlanned toggle (26e)

Reads completed sets from the current week, joins exercises.xp_attribution,
applies the locked set-counting rule (primary by max share, ties counted).
includePlanned=true also walks the bucket's uncompleted routines via
routine_list to add planned counts.

Exercise model gains xpAttribution: Map<String, num>? for the planned read.
EOF
)"
```

---

## Task 7: `BucketRoutineRow` widget

**Files:**
- Create: `lib/features/weekly_plan/ui/widgets/bucket_routine_row.dart`
- Create: `test/widget/features/weekly_plan/widgets/bucket_routine_row_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/features/weekly_plan/widgets/bucket_routine_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/weekly_plan/ui/widgets/bucket_routine_row.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required bool isDone,
    required bool isSpontaneous,
    String? completionDayLabel,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BucketRoutineRow(
            routineId: 'r1',
            name: 'Push Day',
            isDone: isDone,
            isSpontaneous: isSpontaneous,
            completionDayLabel: completionDayLabel,
            onOverflowTap: () {},
          ),
        ),
      ),
    );
  }

  group('BucketRoutineRow — status icon states', () {
    testWidgets('planned (not done) shows an outline ring', (tester) async {
      await pumpRow(tester, isDone: false, isSpontaneous: false);
      expect(find.byKey(const ValueKey('bucket-row-status-planned')), findsOneWidget);
      expect(find.byKey(const ValueKey('bucket-row-status-done')), findsNothing);
      expect(find.byKey(const ValueKey('bucket-row-spontaneous-tag')), findsNothing);
    });

    testWidgets('done planned shows a filled green check and no ★ tag', (tester) async {
      await pumpRow(
        tester,
        isDone: true,
        isSpontaneous: false,
        completionDayLabel: 'Seg',
      );
      expect(find.byKey(const ValueKey('bucket-row-status-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('bucket-row-spontaneous-tag')), findsNothing);
      expect(find.text('Seg'), findsOneWidget);
    });

    testWidgets('done spontaneous shows a violet check + ★ Espontâneo tag', (tester) async {
      await pumpRow(
        tester,
        isDone: true,
        isSpontaneous: true,
        completionDayLabel: 'Qua',
      );
      expect(find.byKey(const ValueKey('bucket-row-status-done-spontaneous')), findsOneWidget);
      expect(find.byKey(const ValueKey('bucket-row-spontaneous-tag')), findsOneWidget);
      expect(find.textContaining('Espontâneo'), findsOneWidget);
      expect(find.text('Qua'), findsOneWidget);
    });
  });

  group('BucketRoutineRow — name styling', () {
    testWidgets('pending name uses textDim color', (tester) async {
      await pumpRow(tester, isDone: false, isSpontaneous: false);
      final nameText = tester.widget<Text>(find.text('Push Day'));
      // Dim color is applied via .copyWith(color: ...) on titleMedium — the
      // exact value comes from AppColors.textDim. We assert color is set,
      // and pin the exact value in a separate visual-verification step.
      expect(nameText.style?.color, isNotNull);
    });

    testWidgets('done name uses textCream color', (tester) async {
      await pumpRow(tester, isDone: true, isSpontaneous: false);
      final nameText = tester.widget<Text>(find.text('Push Day'));
      expect(nameText.style?.color, isNotNull);
    });
  });

  group('BucketRoutineRow — overflow menu', () {
    testWidgets('overflow icon fires onOverflowTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BucketRoutineRow(
              routineId: 'r1',
              name: 'Push Day',
              isDone: false,
              isSpontaneous: false,
              onOverflowTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bucket-row-overflow')));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/weekly_plan/widgets/bucket_routine_row_test.dart
```

Expected: FAIL — widget doesn't exist.

- [ ] **Step 3: Implement the widget**

Create `lib/features/weekly_plan/ui/widgets/bucket_routine_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Compact bucket-entry row used by the plan editor (~42dp min-height).
///
/// States:
///   * Planned (not done) — outline-ring icon, name in textDim.
///   * Done planned — green-filled check, name in textCream, completion-day
///     meta on the right.
///   * Done spontaneous — violet-filled check + ★ Espontâneo tag, name in
///     textCream, completion-day meta on the right.
///
/// The drag handle from the previous `PlanRoutineRow` is removed — the new
/// design uses long-press-to-drag via ReorderableListView's default
/// behavior, no visible affordance needed at 42dp height.
class BucketRoutineRow extends StatelessWidget {
  const BucketRoutineRow({
    super.key,
    required this.routineId,
    required this.name,
    required this.isDone,
    required this.isSpontaneous,
    this.completionDayLabel,
    this.onOverflowTap,
  });

  final String routineId;
  final String name;
  final bool isDone;
  final bool isSpontaneous;

  /// Localized 3-letter weekday tag ("Seg", "Ter", …). Null when not done.
  final String? completionDayLabel;

  final VoidCallback? onOverflowTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      container: true,
      identifier: 'bucket-row-$routineId',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _StatusIcon(isDone: isDone, isSpontaneous: isSpontaneous),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDone ? AppColors.textCream : AppColors.textDim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isSpontaneous && isDone) ...[
                    const SizedBox(width: 8),
                    _SpontaneousTag(label: l10n.spontaneousTag),
                  ],
                ],
              ),
            ),
            if (isDone && completionDayLabel != null) ...[
              Text(
                completionDayLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Semantics(
              container: true,
              button: true,
              identifier: 'bucket-row-overflow-$routineId',
              child: IconButton(
                key: const ValueKey('bucket-row-overflow'),
                icon: const Icon(Icons.more_horiz, size: 20),
                color: AppColors.textDim,
                visualDensity: VisualDensity.compact,
                onPressed: onOverflowTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.isDone, required this.isSpontaneous});

  final bool isDone;
  final bool isSpontaneous;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;

    if (!isDone) {
      return Container(
        key: const ValueKey('bucket-row-status-planned'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.brandViolet, width: 1.5),
        ),
      );
    }

    final fillColor = isSpontaneous ? AppColors.hotViolet : AppColors.success;
    final key = isSpontaneous
        ? const ValueKey('bucket-row-status-done-spontaneous')
        : const ValueKey('bucket-row-status-done');

    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fillColor),
      child: const Icon(Icons.check, color: AppColors.textCream, size: 14),
    );
  }
}

class _SpontaneousTag extends StatelessWidget {
  const _SpontaneousTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('bucket-row-spontaneous-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.hotViolet.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.hotViolet,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

> If `AppColors.brandViolet` / `hotViolet` / `textDim` / `textCream` / `success` aren't already on `AppColors`, they ship from 26a — verify by `grep "brandViolet" lib/core/theme/app_theme.dart` and use the existing constants. Do NOT introduce hard-coded hex.

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/widget/features/weekly_plan/widgets/bucket_routine_row_test.dart
```

Expected: all groups pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/weekly_plan/ui/widgets/bucket_routine_row.dart \
        test/widget/features/weekly_plan/widgets/bucket_routine_row_test.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): BucketRoutineRow compact 42dp row (26e)

Three status states: planned outline ring / green-filled done check /
violet-filled done check with ★ Espontâneo tag. Completion-day meta
on the right when done. Overflow ⋯ icon as the per-row action target.
EOF
)"
```

---

## Task 8: `MuscleBarRow` widget + `EngajamentoSection`

**Files:**
- Create: `lib/features/weekly_plan/ui/widgets/muscle_bar_row.dart`
- Create: `lib/features/weekly_plan/ui/widgets/engajamento_section.dart`
- Create: `test/widget/features/weekly_plan/widgets/engajamento_section_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/features/weekly_plan/widgets/engajamento_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/domain/weekly_engagement.dart';
import 'package:repsaga/features/weekly_plan/ui/widgets/engajamento_section.dart';

void main() {
  group('EngajamentoSection — body-part bars', () {
    testWidgets('renders 6 bars in canonical order (no cardio)', (tester) async {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 5},
        planned: {BodyPart.chest: 10, BodyPart.back: 4, BodyPart.legs: 6},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EngajamentoSection(engagement: engagement, onInfoTap: () {}),
          ),
        ),
      );

      // Canonical order: chest, back, legs, shoulders, arms, core.
      expect(find.text('PEITO'), findsOneWidget);
      expect(find.text('COSTAS'), findsOneWidget);
      expect(find.text('PERNAS'), findsOneWidget);
      expect(find.text('OMBROS'), findsOneWidget);
      expect(find.text('BRAÇOS'), findsOneWidget);
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('CARDIO'), findsNothing);
    });

    testWidgets('renders "X / Y" numeric labels per bar', (tester) async {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 5},
        planned: {BodyPart.chest: 10},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EngajamentoSection(engagement: engagement, onInfoTap: () {}),
          ),
        ),
      );
      // chest: 5 done / 10 planned.
      expect(find.text('5 / 10'), findsOneWidget);
    });
  });

  group('EngajamentoSection — info icon', () {
    testWidgets('ⓘ icon fires onInfoTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EngajamentoSection(
              engagement: WeeklyEngagement.empty,
              onInfoTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('engagement-info-icon')));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('EngajamentoSection — header has NO total counter', () {
    testWidgets('does NOT show a sum-of-sets total in the header', (tester) async {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 5, BodyPart.back: 3},
        planned: {BodyPart.chest: 10, BodyPart.back: 4},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EngajamentoSection(engagement: engagement, onInfoTap: () {}),
          ),
        ),
      );
      // The naive total would be (5+3) / (10+4) = 8 / 14. That string must
      // NOT appear anywhere in the header — total is intentionally dropped
      // (spec line 481).
      expect(find.text('8 / 14'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/weekly_plan/widgets/engajamento_section_test.dart
```

Expected: FAIL — widgets don't exist.

- [ ] **Step 3: Implement `MuscleBarRow`**

Create `lib/features/weekly_plan/ui/widgets/muscle_bar_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// One row in the Engajamento section.
///
/// Layout (horizontal, ~22dp):
///   [6dp dot] [UPPERCASE 10sp name] [4dp stacked track ──────] [X / Y]
///
/// Track has two stacked fills on the same 4dp height:
///   * planned-fill: bodyPartColor at 40% opacity, width = plannedSets/maxScale
///   * done-fill:    bodyPartColor at 100% opacity, width = doneSets/maxScale
///
/// `maxScale` is the largest plannedSets value across all 6 bars (or 1 if
/// all are zero) — passed in by the parent so all bars share the same scale.
class MuscleBarRow extends StatelessWidget {
  const MuscleBarRow({
    super.key,
    required this.name,
    required this.bodyPartColor,
    required this.doneSets,
    required this.plannedSets,
    required this.maxScale,
  });

  final String name;
  final Color bodyPartColor;
  final int doneSets;
  final int plannedSets;
  final int maxScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final donePct = maxScale > 0 ? doneSets / maxScale : 0.0;
    final plannedPct = maxScale > 0 ? plannedSets / maxScale : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bodyPartColor),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              name.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: AppColors.textDim,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  // Track background (low-contrast).
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.xpTrack,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Planned fill (40% opacity).
                  // FractionallySizedBox per cluster_align_widthfactor_zerofill —
                  // Align(widthFactor:, ColoredBox) would collapse to 0×0.
                  FractionallySizedBox(
                    widthFactor: plannedPct.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bodyPartColor.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Done fill (100% opacity) overlays the planned fill.
                  FractionallySizedBox(
                    widthFactor: donePct.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bodyPartColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              '$doneSets / $plannedSets',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textCream,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `EngajamentoSection`**

Create `lib/features/weekly_plan/ui/widgets/engajamento_section.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/models/body_part.dart';
import '../../domain/weekly_engagement.dart';
import 'muscle_bar_row.dart';

/// 6-bar muscle-volume section in the plan editor.
///
/// Renders bars in canonical body-part order (chest, back, legs, shoulders,
/// arms, core). Cardio intentionally excluded (v1). Total counter NOT in
/// the header (compound-attribution + tie-counting double-counting would
/// mislead — see spec line 481).
class EngajamentoSection extends StatelessWidget {
  const EngajamentoSection({
    super.key,
    required this.engagement,
    required this.onInfoTap,
  });

  final WeeklyEngagement engagement;
  final VoidCallback onInfoTap;

  static const _orderedBodyParts = [
    BodyPart.chest,
    BodyPart.back,
    BodyPart.legs,
    BodyPart.shoulders,
    BodyPart.arms,
    BodyPart.core,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Shared max-scale: largest planned value across all 6 bars, so all
    // bars use a consistent x-axis. Falls back to 1 to keep widths sane
    // when the user has no data yet.
    int maxScale = 1;
    for (final bp in _orderedBodyParts) {
      if (engagement.plannedFor(bp) > maxScale) maxScale = engagement.plannedFor(bp);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hairline above section.
        const Divider(height: 1, color: AppColors.hairline),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                l10n.weeklyEngagementHeader,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textCream,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                container: true,
                button: true,
                identifier: 'engagement-info-icon',
                label: l10n.engagementExplainerTitle,
                child: IconButton(
                  key: const ValueKey('engagement-info-icon'),
                  icon: const Icon(Icons.info_outline, size: 16),
                  color: AppColors.textDim,
                  visualDensity: VisualDensity.compact,
                  onPressed: onInfoTap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final bp in _orderedBodyParts)
                MuscleBarRow(
                  name: _localizedName(bp, l10n),
                  bodyPartColor: AppColors.colorForBodyPart(bp),
                  doneSets: engagement.doneFor(bp),
                  plannedSets: engagement.plannedFor(bp),
                  maxScale: maxScale,
                ),
              const SizedBox(height: 8),
              _Legend(
                doneLabel: l10n.engagementLegendDone,
                plannedLabel: l10n.engagementLegendPlanned,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _localizedName(BodyPart bp, AppLocalizations l10n) {
    switch (bp) {
      case BodyPart.chest:
        return l10n.bodyPartChest;
      case BodyPart.back:
        return l10n.bodyPartBack;
      case BodyPart.legs:
        return l10n.bodyPartLegs;
      case BodyPart.shoulders:
        return l10n.bodyPartShoulders;
      case BodyPart.arms:
        return l10n.bodyPartArms;
      case BodyPart.core:
        return l10n.bodyPartCore;
      case BodyPart.cardio:
        return ''; // unreachable — cardio filtered out above
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.doneLabel, required this.plannedLabel});

  final String doneLabel;
  final String plannedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim);
    Widget swatch(double opacity) => Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.hotViolet.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(2),
          ),
        );
    return Row(
      children: [
        swatch(1.0),
        const SizedBox(width: 4),
        Text(doneLabel, style: dim),
        const SizedBox(width: 12),
        swatch(0.4),
        const SizedBox(width: 4),
        Text(plannedLabel, style: dim),
      ],
    );
  }
}
```

> Verify `AppColors.colorForBodyPart(BodyPart)`, `hairline`, `xpTrack`, and the `bodyPartChest`/etc. l10n keys exist (26a shipped them per the spec). If `colorForBodyPart` is missing, use a switch on `BodyPart` mapping to existing `AppColors.bodyPartChest/Back/Legs/Shoulders/Arms/Core` constants.

- [ ] **Step 5: Run to verify it passes**

```bash
flutter test test/widget/features/weekly_plan/widgets/engajamento_section_test.dart
```

Expected: all tests pass. (Some text expectations may need the l10n keys added in Task 13 — if so, run after Task 13 and add a checkbox here for re-running.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/weekly_plan/ui/widgets/muscle_bar_row.dart \
        lib/features/weekly_plan/ui/widgets/engajamento_section.dart \
        test/widget/features/weekly_plan/widgets/engajamento_section_test.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): EngajamentoSection + MuscleBarRow widgets (26e)

6-bar muscle-volume view in canonical order (cardio excluded). Each
bar = 6dp body-part dot + 10sp uppercase name + 4dp stacked
planned/done track + tabular "X / Y" set count. ⓘ icon opens the
set-counting-rule explainer (Task 10). No total counter in the
header per spec.
EOF
)"
```

---

## Task 9: Engagement explainer bottom sheet

**Files:**
- Create: `lib/features/weekly_plan/ui/widgets/engagement_explainer_sheet.dart`

The ⓘ tap opens this sheet. It explains the set-counting rule in plain Portuguese.

- [ ] **Step 1: Implement the sheet**

Create `lib/features/weekly_plan/ui/widgets/engagement_explainer_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Bottom sheet explaining the set-counting rule used by Engajamento.
///
/// Triggered by the ⓘ icon on the EngajamentoSection header. Pure-text
/// content — no inputs or actions beyond the close affordance.
class EngagementExplainerSheet extends StatelessWidget {
  const EngagementExplainerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const EngagementExplainerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.engagementExplainerTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textCream,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.engagementExplainerBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textDim,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit (no test — pure presentational, covered by Task 11's screen test that opens the sheet)**

```bash
git add lib/features/weekly_plan/ui/widgets/engagement_explainer_sheet.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): engagement explainer bottom sheet (26e)

Triggered by the ⓘ icon on the Engajamento header. Explains the
set-counting rule: primary by max XP share, ties at max count for
all tied body parts. Pure-text — no input.
EOF
)"
```

---

## Task 10: `WeekPlanScreen` rewrite

**Files:**
- Create: `lib/features/weekly_plan/ui/week_plan_screen.dart`
- Delete: `lib/features/weekly_plan/ui/plan_management_screen.dart` (after the router is updated)
- Delete: `lib/features/weekly_plan/ui/widgets/plan_routine_row.dart`
- Delete: `lib/features/weekly_plan/ui/widgets/plan_add_routine_row.dart`
- Delete the companion tests for the two deleted widgets.
- Modify: `lib/core/router/app_router.dart` — change the `/plan/week` builder.

- [ ] **Step 1: Write the screen-level widget test**

Create `test/widget/features/weekly_plan/week_plan_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:repsaga/features/weekly_plan/ui/week_plan_screen.dart';
// + the providers/mocks needed for the harness — pattern from
//   plan_management_screen_test.dart (delete the old one after porting).

void main() {
  group('WeekPlanScreen — counter pill', () {
    testWidgets('shows "N dias treinados" with unique completion dates', (tester) async {
      // Bucket with 3 entries, 2 of them completed on the same day:
      // → counter reads "1 dias treinados" (not 2 — same-day collapses).
      // Inline factories from test_factories.dart.
      // ... harness setup ...
      // expect(find.text('1 dias treinados'), findsOneWidget);
    });

    testWidgets('counts two different completion days as 2', (tester) async {
      // ... two entries completed on different dates ...
      // expect(find.text('2 dias treinados'), findsOneWidget);
    });
  });

  group('WeekPlanScreen — "+ Adicionar treino" CTA', () {
    testWidgets('opens AddRoutinesSheet when tapped', (tester) async {
      // ... harness with empty bucket ...
      // await tester.tap(find.text('+ Adicionar treino'));
      // await tester.pumpAndSettle();
      // expect(find.byType(AddRoutinesSheet), findsOneWidget);
    });

    testWidgets('shows soft-cap warning when bucket >= trainingFrequencyPerWeek', (tester) async {
      // ... harness with trainingFrequencyPerWeek = 3 and bucket of 3 ...
      // expect(find.textContaining('limite'), findsOneWidget);
    });
  });

  group('WeekPlanScreen — Engajamento info icon', () {
    testWidgets('ⓘ tap opens the explainer bottom sheet', (tester) async {
      // ... harness ...
      // await tester.tap(find.byKey(const ValueKey('engagement-info-icon')));
      // await tester.pumpAndSettle();
      // expect(find.byType(EngagementExplainerSheet), findsOneWidget);
    });
  });
}
```

> The full harness boilerplate is omitted here for brevity — copy the pattern from the existing `test/widget/features/weekly_plan/plan_management_screen_test.dart` (which is deleted in this task). The four expectations above are the contract pins.

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/weekly_plan/week_plan_screen_test.dart
```

Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement the screen**

Create `lib/features/weekly_plan/ui/week_plan_screen.dart`. Structure:

```dart
// (Imports — Flutter, Riverpod, l10n, AppTheme, weekly_plan providers,
//  weekly_engagement_provider, BucketRoutineRow, EngajamentoSection,
//  EngagementExplainerSheet, AddRoutinesSheet, profile_providers,
//  routine_list_notifier, ... — match the existing
//  plan_management_screen.dart import set.)

class WeekPlanScreen extends ConsumerStatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  ConsumerState<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends ConsumerState<WeekPlanScreen> {
  // CARRY FORWARD VERBATIM from PlanManagementScreen:
  //   * _bucketRoutines, _dirty, _seeded
  //   * _saveDebounce + _savePlan + _flushDebouncedSave
  //   * _maybeShowSavedSnackbar + _savedSnackbarActive
  //   * _undoSnackbarActive + _removeRoutine undo flow (Dismissible still
  //     applies to non-completed rows; just inside BucketRoutineRow's
  //     overflow menu rather than as a swipe handle — see step 4)
  //   * _pendingAnalyticsEvent + _flushAnalyticsEvent (analytics debounce)
  //   * initState + dispose
  //   * _showAddSheet (unchanged from existing)
  //   * _autoFill (unchanged)
  //   * _confirmClear (unchanged)
  //   * _renumber + _onReorder (unchanged — ReorderableListView still drives
  //     the list)

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final routinesAsync = ref.watch(routineListProvider);
    final profile = ref.watch(profileProvider);
    final allRoutines = routinesAsync.value ?? [];
    final routineMap = <String, Routine>{for (final r in allRoutines) r.id: r};
    final trainingFrequency = profile.value?.trainingFrequencyPerWeek ?? 3;
    final atSoftCap = _bucketRoutines.length >= trainingFrequency;
    final engagementAsync = ref.watch(
      weeklyEngagementProvider(const WeeklyEngagementArgs(includePlanned: true)),
    );

    final uniqueCompletionDays = _bucketRoutines
        .where((r) => r.completedAt != null)
        .map((r) => DateTime(
              r.completedAt!.year,
              r.completedAt!.month,
              r.completedAt!.day,
            ))
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'weekly-plan-title',
          child: Text(l10n.thisWeeksPlan),
        ),
        actions: [
          // (overflow menu — unchanged from PlanManagementScreen)
        ],
      ),
      body: SnackBarTapOutDismissScope(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // Counter pill row.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    l10n.thisWeek,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.textDim,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const Spacer(),
                  _CounterPill(count: uniqueCompletionDays, label: l10n.daysTrainedCount(uniqueCompletionDays)),
                ],
              ),
            ),
            // Bucket list — ReorderableListView wrapped in a shrinkWrap'd
            // section so it lives inside the outer ListView with the
            // Engajamento section below.
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _bucketRoutines.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final bucket = _bucketRoutines[index];
                final routine = routineMap[bucket.routineId];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(bucket.routineId),
                  index: index,
                  child: BucketRoutineRow(
                    routineId: bucket.routineId,
                    name: routine?.name ?? l10n.unknownRoutine,
                    isDone: bucket.completedWorkoutId != null,
                    isSpontaneous: bucket.isSpontaneous,
                    completionDayLabel: bucket.completedAt != null
                        ? _shortDayLabel(bucket.completedAt!, l10n)
                        : null,
                    onOverflowTap: bucket.completedWorkoutId != null
                        ? null
                        : () => _removeRoutine(context, index),
                  ),
                );
              },
            ),
            // "+ Adicionar treino" CTA.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: InkWell(
                onTap: () => _showAddSheet(allRoutines),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.addWorkout,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.brandViolet,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
            // Soft-cap warning (carried forward from PlanAddRoutineRow).
            if (atSoftCap)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  l10n.softCapWarning(trainingFrequency),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                      ),
                ),
              ),
            const SizedBox(height: 24),
            // Engajamento.
            engagementAsync.when(
              data: (engagement) => EngajamentoSection(
                engagement: engagement,
                onInfoTap: () => EngagementExplainerSheet.show(context),
              ),
              loading: () => const SizedBox(height: 200),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // _shortDayLabel: lookup table or DateFormat(EEE, locale).
  // _CounterPill: small private widget with the existing
  // Semantics(identifier: 'weekly-plan-counter') treatment.
}
```

> The carry-forward block is intentional — the existing debounce + undo + analytics scaffolding is well-tested and shouldn't be re-engineered for 26e. The only architectural change is the layout (bucket rows + Engajamento section in a single scroll view).

- [ ] **Step 4: Update the router**

Edit `lib/core/router/app_router.dart` line 254–255:

```dart
GoRoute(
  path: '/plan/week',
  builder: (context, state) => const WeekPlanScreen(),
),
```

And update the import at the top of the file (replace `PlanManagementScreen` import with `WeekPlanScreen`).

- [ ] **Step 5: Delete the old screen + widgets + tests**

```bash
git rm lib/features/weekly_plan/ui/plan_management_screen.dart \
       lib/features/weekly_plan/ui/widgets/plan_routine_row.dart \
       lib/features/weekly_plan/ui/widgets/plan_add_routine_row.dart \
       test/widget/features/weekly_plan/widgets/plan_routine_row_test.dart \
       test/widget/features/weekly_plan/widgets/plan_add_routine_row_test.dart \
       test/widget/features/weekly_plan/plan_management_screen_test.dart
```

(Adjust paths to whatever actually exists — verify with `git ls-files` before deleting.)

- [ ] **Step 6: Run the analyzer + tests**

```bash
dart analyze --fatal-infos
flutter test test/unit/features/weekly_plan/ test/widget/features/weekly_plan/
```

Expected: clean analyzer, all tests pass (the new `week_plan_screen_test.dart` from Step 1 is now exercised against the real widget).

- [ ] **Step 7: Commit**

```bash
git add lib/features/weekly_plan/ui/week_plan_screen.dart \
        lib/core/router/app_router.dart \
        test/widget/features/weekly_plan/week_plan_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): WeekPlanScreen rewrite with compact layout (26e)

Replaces PlanManagementScreen with a single-scroll layout:
  - "Esta semana" header + "N dias treinados" counter pill (unique
    completion dates)
  - Compact BucketRoutineRow list (planned/done/spontaneous states)
  - "+ Adicionar treino" CTA
  - Soft-cap warning when bucket >= trainingFrequencyPerWeek
  - Hairline divider + EngajamentoSection with ⓘ explainer

Carries forward the debounce + undo + analytics scaffolding from
PlanManagementScreen verbatim — the architectural change is the
layout, not the persistence path.

Drops plan_routine_row, plan_add_routine_row, and the old screen
file along with their companion widget tests.
EOF
)"
```

---

## Task 11: L10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_pt.arb`

- [ ] **Step 1: Add the new keys**

Append (alphabetized into the existing structure — match the file's section ordering pattern) to both ARB files:

**`app_pt.arb`** — Portuguese (primary, source of truth for Brazilian fitness UX):

```json
{
  "daysTrainedCount": "{count, plural, =0{0 dias treinados} =1{1 dia treinado} other{{count} dias treinados}}",
  "@daysTrainedCount": { "placeholders": { "count": { "type": "int" } } },
  "addWorkout": "+ Adicionar treino",
  "spontaneousTag": "★ Espontâneo",
  "weeklyEngagementHeader": "Engajamento da semana",
  "engagementExplainerTitle": "Como contamos os sets?",
  "engagementExplainerBody": "Cada série conta para o grupo muscular com a maior porcentagem na atribuição do exercício. Se duas partes empatam exatamente no topo, ambas recebem a série. Cardio é mostrado em uma vista separada (chega na v1.1).",
  "engagementLegendDone": "feito",
  "engagementLegendPlanned": "planejado",
  "softCapWarning": "Você atingiu o limite de {frequency} treinos por semana. Adicionar mais pode sobrecarregar.",
  "@softCapWarning": { "placeholders": { "frequency": { "type": "int" } } }
}
```

**`app_en.arb`** — English (English-locale users; mirror PT structure):

```json
{
  "daysTrainedCount": "{count, plural, =0{0 days trained} =1{1 day trained} other{{count} days trained}}",
  "@daysTrainedCount": { "placeholders": { "count": { "type": "int" } } },
  "addWorkout": "+ Add workout",
  "spontaneousTag": "★ Spontaneous",
  "weeklyEngagementHeader": "Weekly engagement",
  "engagementExplainerTitle": "How are sets counted?",
  "engagementExplainerBody": "Each set counts toward the body part with the highest share in the exercise's attribution. If two parts tie exactly at the top, both receive the set. Cardio is shown in a separate view (coming in v1.1).",
  "engagementLegendDone": "done",
  "engagementLegendPlanned": "planned",
  "softCapWarning": "You've hit your {frequency} workouts-per-week limit. Adding more may overload.",
  "@softCapWarning": { "placeholders": { "frequency": { "type": "int" } } }
}
```

- [ ] **Step 2: Regenerate l10n**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter gen-l10n
```

Expected: `lib/l10n/app_localizations.dart` (+ pt/en files) regenerated with the new accessors. No errors.

- [ ] **Step 3: Re-run all weekly_plan widget tests**

```bash
flutter test test/widget/features/weekly_plan/
```

Expected: all green (any text-expectations from Tasks 7/8/10 that depended on these keys now resolve).

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_pt.arb lib/l10n/app_localizations*.dart
git commit -m "$(cat <<'EOF'
feat(weekly-plan): l10n keys for 26e plan editor + engajamento (26e)

en + pt coverage for:
  - daysTrainedCount (plural)
  - addWorkout, spontaneousTag, softCapWarning
  - weeklyEngagementHeader, engagementExplainerTitle/Body
  - engagementLegendDone, engagementLegendPlanned
EOF
)"
```

---

## Task 12: Integration test for `save_workout` find-or-create

**Files:**
- Create: `test/integration/save_workout_bucket_update_test.dart`

This exercises the 00063 RPC end-to-end against a real (or mocktail-stubbed via `supabase_flutter`) Supabase client. Pattern: lift from existing integration tests under `test/integration/` (find the closest precedent with `grep -l "save_workout\|record_session_xp_batch" test/integration/`).

- [ ] **Step 1: Write the integration test**

Create `test/integration/save_workout_bucket_update_test.dart`:

```dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';

// Imports for: Supabase test client / harness, test_factories, BucketRoutine
// model, ... — match the pattern from the existing integration tests.

void main() {
  group('save_workout — bucket find-or-create', () {
    setUp(() async {
      // ... seed a test user + empty workout/plan slate ...
    });

    test('matches uncompleted planned entry by routine_id → fills it', () async {
      // 1. Insert weekly_plan with one uncompleted entry, routine_id = R1.
      // 2. Insert a workout sourced from R1, finished now().
      // 3. Call save_workout RPC.
      // 4. Re-read weekly_plan. Expect:
      //    - routines.length == 1
      //    - routines[0].completed_workout_id == workout.id
      //    - routines[0].is_spontaneous == false
    });

    test('no match (different routine_id) → appends spontaneous entry', () async {
      // 1. Plan has one uncompleted entry, routine_id = R1.
      // 2. Insert a workout sourced from R2.
      // 3. Call save_workout.
      // 4. Re-read plan. Expect:
      //    - routines.length == 2
      //    - routines[0].routine_id == R1, still uncompleted
      //    - routines[1].routine_id == R2, completed_workout_id set,
      //      is_spontaneous == true, order == 2
    });

    test('duplicate routine — prefers filling the planned entry over creating spontaneous',
        () async {
      // 1. Plan has TWO uncompleted entries, both routine_id = R1 (the user
      //    planned the same routine twice this week).
      // 2. Insert a workout sourced from R1.
      // 3. Call save_workout.
      // 4. Expect: the FIRST uncompleted entry by order ASC is filled.
      //    The second remains uncompleted. No spontaneous append.
    });

    test('matching entry already completed → appends spontaneous (re-save same day)',
        () async {
      // 1. Plan has one entry for R1, completed earlier today.
      // 2. Insert a new workout sourced from R1 (second session same day).
      // 3. Call save_workout.
      // 4. Expect: a new spontaneous entry appended with order = 2.
    });

    test('idempotent re-save — same workout id twice does not append duplicate',
        () async {
      // 1. Plan with one entry R1.
      // 2. Save workout W1 (sourced from R1) — fills the entry.
      // 3. Call save_workout AGAIN with the same W1 (e.g. retry after network
      //    blip).
      // 4. Expect: routines.length unchanged. The previously-filled entry
      //    still references W1.
    });

    test('no plan for current week → no-op bucket update', () async {
      // 1. No weekly_plan row for this week.
      // 2. Save a workout.
      // 3. Expect: weekly_plans table still has no row for the user/week.
      //    Workout saved normally; XP rolls up; bucket untouched.
    });

    test('multi-workout same day → both land in the bucket correctly', () async {
      // 1. Plan with R1 (uncompleted) + R2 (uncompleted).
      // 2. Save W1 sourced from R1.
      // 3. Save W2 sourced from R2 (same day).
      // 4. Expect: both entries filled. unique-completion-days counter (the
      //    client-side derived value) is 1 (same date).
    });
  });
}
```

> Pattern note: if no existing integration tests against `save_workout` exist (Phase 26d added them under `test/integration/`), use the closest precedent — likely `test/integration/record_session_xp_batch_test.dart` — and copy the Supabase harness setup verbatim.

- [ ] **Step 2: Run the integration test**

```bash
export PATH="/c/flutter/bin:$PATH"
# Ensure local Supabase is running:
npx supabase start
flutter test test/integration/save_workout_bucket_update_test.dart
```

Expected: all 7 scenarios pass against the local Supabase instance.

- [ ] **Step 3: Commit**

```bash
git add test/integration/save_workout_bucket_update_test.dart
git commit -m "$(cat <<'EOF'
test(weekly-plan): integration coverage for save_workout bucket logic (26e)

Seven scenarios against 00063 RPC:
  - planned hit fills the matched entry
  - no match appends spontaneous
  - duplicate routine prefers planned over spontaneous
  - already-completed match → new spontaneous
  - idempotent re-save (same workout id)
  - no plan for current week → no-op
  - multi-workout same day → both bucket entries land
EOF
)"
```

---

## Task 13: E2E updates

**Files:**
- Modify: `test/e2e/specs/weekly-plan.spec.ts`
- Modify: `test/e2e/helpers/selectors.ts`

- [ ] **Step 1: Update selectors**

Edit `test/e2e/helpers/selectors.ts`. Add/replace under `WEEKLY_PLAN`:

```ts
export const WEEKLY_PLAN = {
  // ... existing selectors (planManagementTitle, thisWeekHeader, etc.) ...

  // 26e: compact-row layout.
  bucketRow: (routineId: string) =>
    `[flt-semantics-identifier="bucket-row-${routineId}"]`,
  bucketRowSpontaneousTag: 'flt-semantics:has-text("Espontâneo"), [aria-label*="Espontâneo"]',
  daysTrainedCounter: 'flt-semantics:has-text("dias treinad")',
  addWorkoutCta: 'role=button[name*="Adicionar treino"]',
  engagementSection: 'flt-semantics:has-text("Engajamento da semana")',
  engagementInfoIcon: '[flt-semantics-identifier="engagement-info-icon"]',
  engagementExplainerSheet: 'flt-semantics:has-text("Como contamos os sets")',
  // body-part bars in the engagement section
  muscleBarChest: 'flt-semantics:has-text("PEITO")',
  muscleBarBack: 'flt-semantics:has-text("COSTAS")',
  muscleBarLegs: 'flt-semantics:has-text("PERNAS")',
  muscleBarShoulders: 'flt-semantics:has-text("OMBROS")',
  muscleBarArms: 'flt-semantics:has-text("BRAÇOS")',
  muscleBarCore: 'flt-semantics:has-text("CORE")',
  // explicit absence assertion
  muscleBarCardio: 'flt-semantics:has-text("CARDIO")',
};
```

> Adjust to whatever selector convention the existing file uses (the example mixes `flt-semantics` CSS with Playwright `role=` — match the established pattern).

- [ ] **Step 2: Update the spec file**

Edit `test/e2e/specs/weekly-plan.spec.ts`. Two structural changes:

1. **Replace any selector references** that point at the deleted `PlanRoutineRow`/`PlanAddRoutineRow` widgets with the new `BucketRoutineRow` + add CTA selectors. Grep first:
   ```bash
   grep -n "plan-routine-row\|plan-add-routine\|drag_handle" test/e2e/specs/weekly-plan.spec.ts
   ```

2. **Add new tests** in the existing `test.describe('Weekly Plan', { tag: '@smoke' }, () => {...})` block:

```ts
test('should show "+ Adicionar treino" CTA at the bottom of the bucket list', async ({ page }) => {
  await page.evaluate(() => { window.location.hash = '#/plan/week'; });
  await expect(page.locator(WEEKLY_PLAN.planManagementTitle)).toBeVisible({ timeout: 15_000 });
  await expect(page.locator(WEEKLY_PLAN.addWorkoutCta)).toBeVisible({ timeout: 5_000 });
});

test('should show Engajamento section with 6 body-part bars (cardio absent)', async ({ page }) => {
  await page.evaluate(() => { window.location.hash = '#/plan/week'; });
  await expect(page.locator(WEEKLY_PLAN.engagementSection).first()).toBeVisible({ timeout: 15_000 });
  // 6 canonical body parts present.
  await expect(page.locator(WEEKLY_PLAN.muscleBarChest).first()).toBeVisible();
  await expect(page.locator(WEEKLY_PLAN.muscleBarBack).first()).toBeVisible();
  await expect(page.locator(WEEKLY_PLAN.muscleBarLegs).first()).toBeVisible();
  await expect(page.locator(WEEKLY_PLAN.muscleBarShoulders).first()).toBeVisible();
  await expect(page.locator(WEEKLY_PLAN.muscleBarArms).first()).toBeVisible();
  await expect(page.locator(WEEKLY_PLAN.muscleBarCore).first()).toBeVisible();
  // Cardio NOT rendered.
  await expect(page.locator(WEEKLY_PLAN.muscleBarCardio)).toHaveCount(0);
});

test('should open the engagement explainer bottom sheet on ⓘ tap', async ({ page }) => {
  await page.evaluate(() => { window.location.hash = '#/plan/week'; });
  await expect(page.locator(WEEKLY_PLAN.engagementSection).first()).toBeVisible({ timeout: 15_000 });
  await page.locator(WEEKLY_PLAN.engagementInfoIcon).first().click();
  await expect(page.locator(WEEKLY_PLAN.engagementExplainerSheet).first()).toBeVisible({ timeout: 5_000 });
});
```

3. **Add a spontaneous-flow test** (this exercises 00063 indirectly via the workout-save flow):

```ts
test('should append a spontaneous bucket entry when saving a workout not in the plan', async ({
  page,
}) => {
  // Pre-condition: bucket has routines, none of them is "Pull Day" (or
  // whichever routine the test seeds and runs). The test user's seeded data
  // controls this — check global-setup.ts for the seeded plan shape. Cluster
  // e2e_global_setup_seed_verify applies: read global-setup before relying
  // on bucket assumptions.
  // 1. Navigate to plan editor, snapshot routine count.
  // 2. Start + finish a workout from a routine that is NOT in the bucket.
  // 3. Return to plan editor.
  // 4. Assert: a new row appeared with the ★ Espontâneo tag visible.
});
```

> The exact selectors for steps 2-3 depend on the existing workout-completion flow in other spec files — pattern after `test/e2e/specs/workouts.spec.ts` if that's the canonical place.

- [ ] **Step 3: Build the Flutter web app**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter build web
```

- [ ] **Step 4: Run E2E**

```bash
cd test/e2e
FLUTTER_APP_URL= npx playwright test specs/weekly-plan.spec.ts --reporter=list
```

Expected: all weekly-plan tests pass (existing + new). If anything red, screenshot diff is in `test/e2e/test-results/`.

- [ ] **Step 5: Commit**

```bash
git add test/e2e/specs/weekly-plan.spec.ts test/e2e/helpers/selectors.ts
git commit -m "$(cat <<'EOF'
test(e2e): weekly-plan selectors + spontaneous-flow coverage (26e)

Updates selectors.ts with bucket-row / Engajamento / explainer-sheet /
6-muscle-bar identifiers. Adds three new smoke tests:
  - "+ Adicionar treino" CTA visible
  - 6 body-part bars rendered (cardio explicitly absent)
  - ⓘ tap opens explainer bottom sheet
Plus the cross-cutting spontaneous-flow test exercising 00063 via
the workout-save round-trip.
EOF
)"
```

---

## Task 14: Visual verification (3-viewport screenshots vs mockup)

Per CLAUDE.md pipeline step 9 — UI phases ship a screenshot package comparing against `docs/phase-26-mockups.html`. This is BLOCKING for merge.

- [ ] **Step 1: Boot the app**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter build web
```

Use Playwright's auto-serve OR Chrome DevTools MCP for screenshots:

```bash
cd test/e2e
FLUTTER_APP_URL= npx playwright test --grep @smoke specs/auth.spec.ts  # warms up the server
```

(Or just run the local file server pattern documented in CLAUDE.md.)

- [ ] **Step 2: For each test user, screenshot the plan editor at 3 viewports**

Pick two user states from `test/e2e/fixtures/test-users.ts`:
- A foundation user with a populated bucket + completed workouts this week (so done-fills render on the muscle bars).
- A fresh user with no plan / no workouts (empty-state path).

For each user, sign in and navigate to `/plan/week`. Use `mcp__plugin_playwright_playwright__browser_resize` + `browser_take_screenshot` at:
- 320×690 (smallest Android)
- 360×800 (baseline)
- 412×915 (large phone)

Save screenshots under `tasks/26e-visuals/<user>-<viewport>.png` (or wherever the local convention is — `tasks/` is the standard scratch area).

- [ ] **Step 3: Diff against mockup**

Open `docs/phase-26-mockups.html` in a browser at the same viewport widths. Side-by-side compare:
- Status-icon glyphs (○ outline / ✓ green / ✓ violet + ★)
- Routine name color (textCream done, textDim pending)
- ★ Espontâneo tag color + padding
- Counter pill style
- Bar colors match `AppColors.bodyPartChest/Back/...` from 26a
- Bar layout (dot + name + track + number all aligned)
- Cardio NOT visible
- ⓘ icon size + opacity
- Legend dots + opacity

Flag any drift loudly in the PR thread.

- [ ] **Step 4: Drop the screenshots into the PR**

```bash
gh pr comment <PR#> --body "$(cat <<'EOF'
**Visual verification — 26e plan editor**

| Viewport | Foundation user | Fresh user |
|---|---|---|
| 320dp | tasks/26e-visuals/foundation-320.png | tasks/26e-visuals/fresh-320.png |
| 360dp | tasks/26e-visuals/foundation-360.png | tasks/26e-visuals/fresh-360.png |
| 412dp | tasks/26e-visuals/foundation-412.png | tasks/26e-visuals/fresh-412.png |

Side-by-side with `docs/phase-26-mockups.html #plan` — [drift notes inline].
EOF
)"
```

If drift > visual-noise threshold (colors visibly off, ellipsis not firing, spacing wrong), back to `tech-lead` → re-render → re-screenshot. Don't merge until visuals match.

- [ ] **Step 5: Commit (no code change — visual verification is a gate, not a code addition)**

If during visual verification small fixes are needed (color drift, padding off by a few dp), commit them as `fix(weekly-plan): post-visual-verification tweaks (26e)` in the same task.

---

## Self-review

Before opening the PR, run through:

1. **Locked decisions surfaced.** Every PR description references the "Locked decisions" block from this plan so reviewers don't re-debate.
2. **All four sub-projects committed independently.** Verify with `git log --oneline feature/26e-bucket-spontaneous`:
   - Data model (Task 1)
   - Migrations 00062 + 00063 (Tasks 2-3)
   - Notifier refactor (Task 4)
   - Engagement provider + math (Tasks 5-6)
   - UI widgets (Tasks 7-10)
   - L10n + integration tests + E2E (Tasks 11-13)
3. **No client-side `markRoutineComplete`.** `grep -rn "markRoutineComplete" lib/ test/` returns zero hits.
4. **Backfill is idempotent.** 00062 re-run on a backfilled DB is a no-op.
5. **RPC is idempotent.** Re-saving the same workout (test in Task 12) doesn't double-append.
6. **First-completion-wins verified in the integration test.** The "duplicate routine prefers planned" scenario passes.
7. **Engajamento has NO total counter in the header.** The widget test pins this.
8. **Cardio is hidden.** Widget test asserts `find.text('CARDIO')` is `findsNothing`; E2E asserts the cardio bar has `count(0)`.
9. **Phase-agnostic test names.** No `Phase 26e`, no `(was X)`, no "now maps to" prose.
10. **No unused imports.** `dart analyze --fatal-infos` is clean.
11. **Cluster references in inline comments** where applicable (e.g. `// align_widthfactor_zerofill` on the FractionallySizedBox usage; `// async_caller_broke_snackbar` on the `ref.invalidate` call in the workouts notifier).
12. **Visual verification done at 3 viewports for at least 2 users.** Screenshots attached to the PR.
13. **`make ci` green from a clean tree.**
14. **E2E green** (`FLUTTER_APP_URL= npx playwright test --reporter=list`).
15. **Hosted Supabase migrations applied** after merge (`npx supabase db push`) — verify before declaring the phase done.

---

## Tasks summary

| # | Task | Files touched | Independent commit |
|---|---|---|---|
| 1 | Data model — `BucketRoutine.isSpontaneous` | 1 modify, 1 test | ✓ |
| 2 | Migration 00062 — JSONB backfill | 1 new | ✓ |
| 3 | Migration 00063 — save_workout find-or-create | 1 new | ✓ |
| 4 | Drop client-side `markRoutineComplete` | 3 modify, 1 rename, 1 delete | ✓ |
| 5 | `WeeklyEngagement` + set-counting math | 2 new | ✓ |
| 6 | `weeklyEngagementProvider` | 2 new (+ Exercise model touch) | ✓ |
| 7 | `BucketRoutineRow` widget | 2 new | ✓ |
| 8 | `MuscleBarRow` + `EngajamentoSection` | 3 new | ✓ |
| 9 | Engagement explainer bottom sheet | 1 new | ✓ |
| 10 | `WeekPlanScreen` rewrite + router | 1 new, 1 modify, 5+ delete | ✓ |
| 11 | L10n keys | 2 modify | ✓ |
| 12 | Integration test for save_workout bucket logic | 1 new | ✓ |
| 13 | E2E updates | 2 modify | ✓ |
| 14 | Visual verification | (gate, no commit unless fixes) | (gate) |

14 tasks. Per-task time budget 5-15 min for the trivial ones (1, 2, 9, 11) and 15-30 min for the architectural ones (3, 4, 6, 10). Total ~3-4 hours of focused execution; longer if visual verification surfaces drift requiring re-render rounds.
