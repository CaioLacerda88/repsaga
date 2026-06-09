# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Q2: Routine-level training notes — `feat/routine-notes`

Per PROJECT.md §2 Active Backlog (Q2). Editable when creating/editing a routine,
read-only while training. Char cap 600 (read mid-set; brevity enforced).

### Boundary inventory (filled BEFORE implementation — CLAUDE.md gate)

This change crosses: the `Routine` model + a migration + active-workout state.

**`Routine` model (`lib/features/routines/models/routine.dart`)** — Freezed,
`@JsonSerializable(fieldRename: snake)`. Add `String? notes` (optional → existing
construction sites compile unchanged). `Routine.fromJson` / `toJson` regenerate.

**`Routine(` construction / read sites** (grep, grouped):
- `routine_repository.dart` — `Routine.fromJson(data)` on every read AND after
  insert/update `.select().single()`. Cache read/write also round-trip via
  `toJson`/`fromJson`. Notes flows through automatically once the column exists
  and the write payload includes it.
- `routine_list_notifier.dart` — `createRoutine`/`updateRoutine` forward
  `name`+`exercises` to the repo. **Must add `notes` param to both.**
- `create_routine_screen.dart` — builds `RoutineExercise(...)`, calls
  notifier create/update. **Must add the notes field + pass its value.**
- `weekly_plan/*`, `routine_action_sheet.dart`, `start_routine_action.dart`,
  `action_hero.dart`, `week_plan_screen.dart` — READ `routine.name`/`.id`/
  `.exercises` only; none construct a `Routine` with positional required args,
  so the new optional field is transparent. `start_routine_action.dart` is the
  one that must additionally read `routine.notes` to thread it forward.
- l10n `Routine`-name keys are unrelated (default-routine display names).

**Routine CREATE/UPDATE path** — `RoutineRepository.createRoutine` /
`updateRoutine` write via **plain PostgREST** `_templates.insert({...})` /
`.update({...})` directly to `workout_templates`. **No RPC, no column
whitelist.** RLS policies (`workout_templates_insert_own`/`update_own`) gate by
`user_id`/`is_default` only — they do NOT restrict columns. So persisting
`notes` = add `'notes': notes` to the insert/update map. No RPC to bump.

**`workout_templates` schema** (`00001_initial_schema.sql:119`): `id, user_id,
name, is_default, exercises jsonb, created_at`. No `notes` column → migration
adds it. `00021` already added `valid_workout_templates_name_length`; follow its
`ALTER TABLE ... ADD CONSTRAINT valid_<table>_<col>_length` pattern (separate
non-idempotent statement).

**`config.routineId` → `ActiveWorkoutState` flow** (active-workout read path):
- `start_routine_action.dart` builds `RoutineStartConfig(routineName, exercises,
  routineId)` from a `Routine`.
- `active_workout_notifier.startFromRoutine(config)` creates the workout and
  builds `ActiveWorkoutState(workout, exercises, routineId: config.routineId)`.
- `ActiveWorkoutState` is Freezed + JSON-serialized → **persisted to Hive** for
  crash recovery (`workout_local_storage.dart`).
- `startWorkout()` (ad-hoc) builds state with NO routineId/notes.

**DECIDED wiring (lower-risk):** carry `routineNotes` on `RoutineStartConfig`
AND `ActiveWorkoutState` (not a provider read on the screen). Rationale: (1) the
notes survive crash-recovery rehydration via the existing Hive JSON round-trip,
matching `routineId`; (2) no new provider dependency / network read on the
active-workout screen; (3) ad-hoc `startWorkout()` leaves `routineNotes` null →
state IDENTICAL to today. The header strip renders iff `state.routineNotes` is
non-empty.

**Active-workout exercise list** — `active_workout_screen.dart` renders
`ExerciseList(exercises, reorderMode)` when `exercises.isNotEmpty`, else
`EmptyWorkoutBody`. `ExerciseList` is a `ListView.builder`. The 32dp notes
header strip becomes **index 0** of that list (present only when notes
non-empty), so it scrolls with content and adds zero chrome when absent.

**Counter pattern** — the spec's "workout-notes sheet counter" (textDim →
warning → error) does not yet exist as a live-counter widget in the repo
(`finish_workout_dialog.dart` uses a plain `maxLength`). I'll implement the
custom `buildCounter` inline per spec, using `AppColors.textDim/.warning/.error`.

**l10n** — `routineName`, `addNotesHint`, `editRoutine`, `createRoutine` exist.
`notesCharCounter` does NOT exist yet (PR #323 / Q1 in flight will add it with
format `"{current} / {max}"`). **Dedupe decision:** use the IDENTICAL key name
`notesCharCounter` + value `"{current} / {max}"` so the eventual merge is a
trivial dedupe (per the spec's first option).

### Checklist

- [x] Migration `00075_workout_template_notes.sql`: ADD COLUMN notes + separate
      ADD CONSTRAINT valid_workout_templates_notes_length (<= 600)
- [x] `Routine` model gains `String? notes` + `make gen`
- [x] `RoutineRepository.createRoutine`/`updateRoutine` take + persist `notes`
- [x] `RoutineListNotifier.createRoutine`/`updateRoutine` thread `notes`
      (+ `duplicateRoutine` carries `source.notes`)
- [x] `create_routine_screen.dart` notes field (multiline, optional, counter)
- [x] `RoutineStartConfig` + `ActiveWorkoutState` gain `routineNotes` + gen
- [x] `start_routine_action.dart` threads `routine.notes` into config
- [x] `active_workout_notifier.startFromRoutine` carries notes into state
- [x] `ExerciseList` index-0 header strip (present iff notes non-empty)
- [x] Read-only bottom sheet (`active-workout-routine-notes` semantics)
- [x] l10n: `routineNotesHint`, `routineNotesEyebrow`, `notesCharCounter` + gen
      (dedupe: IDENTICAL `notesCharCounter` key + `"{current} / {max}"` value
      to match PR #323 Q1 — eventual merge is a trivial dedupe)
- [x] Tests: model (2) / repo (4) / editor (5) / active-workout widget (4)
- [x] Verify: gen ✓, format ✓, analyze(0) ✓, test (86 touched) ✓, guards
      (colors+typography) ✓, visual screenshots 360dp ✓ (editor / strip / open
      sheet / no-notes-identical — runtime strip count=0 on ad-hoc confirms
      zero-chrome contract). Migration applied to LOCAL supabase for verify;
      hosted `db push` is a post-merge step.
