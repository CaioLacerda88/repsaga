# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Cardio + bodyweight in the routine builder (type-aware cards)

**Branch:** `feature/cardio-routine-builder`
**Source:** User bug report — routine create/edit modal shows a "Sets" stepper for cardio
exercises (and no bodyweight distinction). Phase 38 made *active logging* cardio-aware but
never updated the routine builder. User decisions: (1) full fix — cardio captures an optional
duration/distance **target**; (2) include a bodyweight distinction.
**Pipeline:** UI-facing feature → ui-ux-critic design lock (done) → mockup sign-off → tech-lead TDD
→ reviewer → QA (incl. E2E) → visual gate → ship. **No migration needed** (see inventory).

### Boundary inventory (ripple check — filled BEFORE implementation)
Change = add `targetDurationSeconds int?` + `targetDistanceM double?` to `RoutineSetConfig`
(`routine.dart`), threading through the JSONB shape + the start-routine seed path. Cardio entry
= exactly ONE config row carrying the target (no set count), reusing existing `setConfigs` machinery.

**Highest-risk break points (must handle):**
1. `start_routine_action.dart:65-70` — flattens `setConfigs`→first-config scalars; **data-loss** for
   cardio target unless `RoutineStartExercise` (`routine_start_config.dart:8-16`) is extended + threaded.
2. `active_workout_notifier.dart:415-427` + `_seedCardioSession` (625-637) — start-from-routine cardio
   seed hard-codes 30:00; add optional `durationSeconds`/`distanceM` params so it honors the routine target.
3. `create_routine_screen.dart` — `_ExerciseCard` (333-466) has NO type branch; `_save` (79-90) +
   `initState` rehydrate (48-61) assume strength shape.
4. `routine_duration_estimator.dart:35-44` — wrong duration for cardio (uses rest×sets); use target duration.
5. `weekly_engagement_provider.dart:82-99` — counts `setConfigs.length` as muscle credits; cardio = 0/skip.
6. Codegen regen (`routine.g.dart` + `routine.freezed.dart`); `test_factories.dart:157-190` needs a cardio variant.
7. E2E `selectors.ts:646-649` (`create-routine-sets`/`-rest`) encode universal-stepper assumption; need cardio-target selectors + conditional handling in `routines.spec.ts`.

**Shape-agnostic (no change):** `routine_repository.dart` passthrough, `duplicateRoutine`,
the `workout_templates.exercises` JSONB column + its array-only CHECK, all save_workout/cardio RPCs
(never read `set_configs`), crash-recovery/resume (rehydrates from `CardioSession` JSON, not routine entries).
→ **No SQL migration required.**

### Design lock (ui-ux-critic)
- **Cardio card:** 3dp teal stripe (`bodyPartCardio`) + `clipBehavior: Clip.antiAlias`, `_CardioEyebrow`
  verbatim, two optional `_CardioField` target slots (TARGET TIME / TARGET DISTANCE) with `+ add` ghost,
  NO set stepper / NO rest chips. Reuse (don't clone) `_CardioField`/`_GhostValue`/`_CardioEyebrow`/
  `CardioFormat.*` + the duration & distance tap-to-type dialogs → extract to shared helpers.
- **Bodyweight card:** strength layout UNCHANGED (set stepper + rest chips) + a neutral `BODYWEIGHT`
  tag (cream/`surface2`, NO color — brand-vs-identity rule). Honest minimal; don't invent a weight field.
- **New ARB keys (en+pt):** `routineTargetTimeLabel`, `routineTargetDistanceLabel`, `routineBodyweightTag`.
  Reuse `cardioAddValue` for the ghost.

### Checklist
- [x] Mockup section in `docs/phase-38-mockups.html` (3 card variants × empty/filled cardio) → **user sign-off** ✅ approved 2026-06-18 (distance follows profile unit)
- [x] Model: `RoutineSetConfig` + `targetDurationSeconds`/`targetDistanceM` (+ regen); cardio detection via `_RoutineExerciseEntry.isCardio`/`isBodyweight`
- [x] Extract shared cardio helpers → `cardio_field.dart` (`CardioField`/`GhostValue`/`CardioEyebrow`) + `cardio_target_dialogs.dart` (duration/distance dialogs return parsed value); `cardio_entry_card.dart` + `duration_stepper.dart` rewired (no behavior change, existing widget tests green)
- [x] `_ExerciseCard` 3-branch (cardio / bodyweight / strength); `_save` writes ONE cardio config; `initState` reads target off single config
- [x] Thread target: `start_routine_action.dart` → `RoutineStartExercise` → `_seedCardioSession(durationSeconds, distanceM)`
- [x] `routine_duration_estimator` (target duration, 30:00 fallback) + `weekly_engagement_provider` (skip cardio → 0 muscle credits)
- [x] l10n keys en+pt (`routineTargetTimeLabel`/`routineTargetDistanceLabel`/`routineBodyweightTag`); test factories cardio variant
- [x] Tests: model round-trip + back-compat, estimator (target + fallback), start-bridge seed (28:00/5km + default) [unit] + 3 card variants [widget] — full suite 3843 pass / 1 skip / 0 fail
- [ ] E2E: cardio routine flow + selector audit (`create-routine-target-time`/`-distance`) — QA gate
- [ ] Visual gate: 320/360/412dp, all variants, empty+filled; teal stripe clips to corner
- [ ] PROJECT.md: add phase row + condense on merge
