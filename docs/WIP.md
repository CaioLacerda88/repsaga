# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Q1: Move workout notes out of the finish gate into History detail

Branch: `feat/notes-edit-after`
Source: product-owner + ui-ux-critic recommendation (finish gate is the RPG
celebration beat; reflective notes add friction + recency bias). Strong/Hevy
keep notes on the log surface, not the finish modal.

### Decisions
- `finishWorkout({String? notes})` param KEPT (offline-queue/save-RPC compat);
  the finish-dialog path now passes `null`. `FinishWorkoutResult` (dialog class)
  loses its `notes` field.
- Notes editing scoped ONLINE-ONLY: `updateWorkoutNotes` is a direct Supabase
  `update`, not routed through the offline queue. Editing a past workout is a
  rare, deliberate, online action (unlike finishing, which must survive a dead
  connection). Documented here per the brief's "your call" clause.

### Checklist
- [x] Remove notes TextField from `finish_workout_dialog.dart`; collapse to
      warning + Confirm/Cancel. `FinishWorkoutResult` kept as a marker record
      (no `notes` field).
- [x] Coordinator passes `notes: null` to `finishWorkout`.
- [x] `WorkoutRepository.updateWorkoutNotes(workoutId, notes, userId)` +
      `BaseRepository.mapException`, RLS-scoped (`.eq('user_id', …)`).
- [x] `WorkoutNotesNotifier` (plain `AsyncNotifier<void>`; `save(workoutId,
      notes)` — NOT a family, see Riverpod note) + invalidate
      `workoutDetailProvider(workoutId)` on success.
- [x] Detail screen: flat eyebrow (`l10n.notes`) + body; empty → tappable
      `Icons.edit_note` + `l10n.addNote`; present → tappable text. Edit sheet
      `NotesEditSheet` (multiline, maxLength 2000, Save/Cancel). Card dropped.
- [x] l10n: add `addNote` (en/pt); reuse `notes`, `save`, `cancel`.
- [x] Tests: dialog (no notes field, still gates), detail widget (empty→sheet→
      saved→reopen→cancel), repo unit (success/clear/error-mapping), notifier
      unit (trim/clear/settle/rethrow).
- [x] E2E: stripped dead finish-dialog notes probe + retired the `NOTES`
      edge-case test in `charter-d-exploratory.spec.ts`; repointed selectors
      to `notesSection`/`notesEditSheet`/`notesSaveButton`/`notesCancelButton`.
- [x] Verify: gen-l10n, format, analyze --fatal-infos 0, touched tests green,
      guards clean. Web screenshot @360dp below.

### Riverpod 3 note
Initial draft used `FamilyAsyncNotifier<void, String>` + `build(String)` +
`arg` — that's the Riverpod 2 API and does NOT exist in riverpod 3.2.1.
Rewrote as a plain `AsyncNotifier<void>` with `save(workoutId, notes)`.

### Orphaned l10n key
`addNotesHint` ("Add notes (optional)") was the finish-dialog placeholder;
now unused. Left in the ARB (key pruning is out of scope).
