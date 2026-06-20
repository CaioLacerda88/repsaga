# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Never-done seed = 0kg (kill the nebulous equipment-default weight)

**Branch:** `feature/never-done-seed-zero`
**Source:** User clarified the routine progression model (2026-06-20). TARGETS STAY (the #357
edit-routine feature is correct + keeps top precedence). The ONLY problem was the never-done WEIGHT
fallback seeding a "nebulous" equipment default (barbell 20kg etc.). Desired precedence:
**target → last-lifted → 0kg** (weight). This REPLACES the old "drop targets → last-lifted" queued
phase, which is now cancelled (targets stay; builder untouched; no header cue — user chose "skip it").

**Scope (small — internal seed values only; no boundary crossing, no migration, no UI):**
- [ ] `active_workout_notifier.dart` L458 (`startFromRoutine` seed):
      `weight: re.targetWeight ?? prev?.weight ?? equipDefaults.weight` → `... ?? 0`
      (reps UNCHANGED: `re.targetReps ?? prev?.reps ?? equipDefaults.reps`).
- [ ] `active_workout_notifier.dart` L704 (`_seedFirstSetForAddedExercise`, mid-workout add):
      `seedWeight ??= equipDefaults.weight` → `seedWeight ??= 0` (reps `??= equipDefaults.reps` UNCHANGED).
      User confirmed BOTH sites (start + mid-workout add) seed 0kg for never-done.
- [ ] Add an inline comment at both sites noting the precedence (target → last → 0) + WHY (kill nebulous
      default; user-approved 2026-06-20) so a future agent doesn't "restore" the equip default.

**Decisions locked (user, 2026-06-20):**
- Reps never-done = equipment default (a 0-rep set is a non-set). Only WEIGHT → 0.
- Target still wins; 0kg only when NO target AND NO history.
- No completion guard — a 0kg strength set stays completable like a bodyweight set (user's call).
- Bodyweight/bands already seed 0kg (equipDefaults.weight==0) — no visible change; bodyweight added-weight
  target still applies (target-first).
- `addSet` ("+ add set", L778) already does `defaultWeight ?? 0` — no change.

**Tests (flip the never-done WEIGHT assertions; reps/target/cardio assertions unchanged):**
- [ ] `test/unit/features/workouts/providers/start_from_routine_smart_defaults_test.dart` — BUG-004
      smart-defaults: never-done weight 20kg/10kg/etc → now **0**. (This intentionally reverses BUG-004's
      WEIGHT smart-default; reps defaults stay. Note the reversal in the test + commit.)
- [ ] `test/unit/features/workouts/providers/start_from_routine_test.dart` — any never-done weight
      fallback assertion → 0. Target-precedence + last-lifted tests UNCHANGED.
- [ ] Add/confirm a mid-workout-add never-done test asserts 0kg.
- [ ] `make test` (or affected unit) green; `dart format` + `dart analyze --fatal-infos` clean.

**E2E/visual:** none — no UI change, no selector change, no flow change. (The set row already renders the
seeded value; only the number differs.) Verify no E2E asserts a never-done 20kg seed.
