# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active branch: `fix/active-and-plan-ux` — usability pass from on-device feedback

User installed RepSaga on their Galaxy S25 Ultra (release APK, debug-keystore-signed) and surfaced 4 concrete usability issues. UI/UX critic reviewed the proposed fixes; direction is locked.

### Fix 1A — Weekly plan: visible save feedback

**File:** `lib/features/weekly_plan/ui/plan_management_screen.dart`

The screen autosaves on every reorder/add/remove/undo/auto-fill via `_savePlan()` (300ms debounce → `_flushDebouncedSave` → `upsertPlan`). Persistence is correct; user has no feedback that it happened. Show a 1-second `SnackBar` saying "Saved" / "Salvo" after each save.

Constraints:
- **Suppress when an undo snackbar is already showing** — `_removeRoutine` shows an undo snack for 5s. If we hide the current snackbar to show "Saved", we destroy the undo affordance. Either skip the "Saved" snack on the remove path entirely (the undo snack is itself evidence the edit registered), or check `ScaffoldMessenger`'s state before showing.
- No spinner, no icon, no offline variant. The offline banner already handles offline state.
- Fire from `_flushDebouncedSave` after `upsertPlan` returns successfully (not optimistically — if the upsert fails we don't lie).

### Fix 1B — Weekly plan: "Create new routine" entry point in AddRoutinesSheet

**Files:** `lib/features/weekly_plan/ui/add_routines_sheet.dart`, `lib/features/weekly_plan/ui/plan_management_screen.dart`

Bottom-sheet picker for routines currently has no way to create a new routine. Add an action row at the **bottom** of the list (above the `Add X routines` confirm button) that:
- Visually a text-link, NOT a selectable tile (`Icon(Icons.add)` + primary-colored "Create new routine" / "Criar nova rotina")
- On tap: pop the sheet, then push the existing routine creation route from the parent
- On return: re-open the sheet with the freshly-created routine **pre-selected** (checkbox checked) — user must still confirm via the `Add X routines` button. Do NOT auto-add.

Also: the empty state (`Center(child: Text(l10n.createMoreRoutines))`) is currently dead text. Convert to a `TextButton` invoking the same create-new flow.

The sheet is launched from `_showAddSheet` in `plan_management_screen.dart` via `showModalBottomSheet`. The modal context is destroyed when popped, so passing a callback or returning a sentinel value (e.g. `_AddRoutinesSheetResult.createNew()`) lets the parent navigate after pop. Either approach works; pick whichever is cleanest.

### Fix 2 — Active workout: weight propagation across sets

**Files:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`, `lib/features/workouts/ui/widgets/set_row.dart`, `lib/features/workouts/ui/widgets/exercise_card.dart`

Common case: user taps `+` repeatedly on set 1 to dial in their working weight (e.g., 0 → 20kg). Sets 2 and 3 stay at 0kg, requiring the same tedious tapping. Implement "follow the leader while still in formation":

When set N's weight changes:
- Walk forward through subsequent sets in the same exercise
- For each: if `!set.isCompleted && set.weight == oldWeight`, update its weight to the new value
- Single atomic state emission for all mutations (NOT 3 sequential rebuilds)

Constraints:
- **Weight only.** Reps come from the routine prescription; do not propagate.
- Completed sets are immutable — never retroactively rewrite a logged set.
- Customized sets (those whose weight differs from the leader's old value) drop out of formation.

New notifier method: `propagateWeight(workoutExerciseId, fromSetId, oldWeight, newWeight)`. Call site is the WeightStepper's onChanged in `set_row.dart` (or wherever the +/- update lands).

Animation: when a set's weight updates via propagation, animate the value change with a slot-machine slide-up via `AnimatedSwitcher` (150ms easeOut, `Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero)`). User-initiated taps change the value directly without the slide; only propagated changes animate. This visually distinguishes "I changed this" from "the app inferred this for me".

`_copyLastSet` affordance at `set_row.dart:319` (existing tap-on-set-number for sets > 1) — keep, but make discoverable: small `Icons.content_copy` at 12dp, alpha 0.4, displayed on set 2+ ONLY when `set.weight != previousSet.weight`. Now functions as a power-user "re-sync" escape hatch.

### Fix 3 — Active workout: suppress "Anterior: 0kg × X" hint

**File:** `lib/features/workouts/ui/widgets/set_row.dart`, method `_shouldShowHint()` (line ~201)

Add `if ((lastSet.weight ?? 0) == 0) return false;` after the existing `lastSet == null` guard. The hint exists to anchor the user to last session's working weight; a 0kg "anchor" is noise. No replacement label — empty space is the correct UX.

If hiding the hint causes column reflow (the existing comment at `:185-197` notes this concern about a sibling Text affecting the row's `flt-semantics-identifier`), wrap the hint slot in `Visibility(maintainSize: true, maintainAnimation: true, maintainState: true, ...)`. Verify with widget test.

### New ARB keys (en + pt parity required)

| Key | en | pt |
|---|---|---|
| `savedConfirmation` | "Saved" | "Salvo" |
| `createNewRoutine` | "Create new routine" | "Criar nova rotina" |
| `copyFromPreviousSet` (tooltip) | "Copy from previous set" | "Copiar da série anterior" |

### Tests required (TDD)

- **Fix 1A:** widget test — pump plan management screen, simulate edit (e.g. add routine), advance debounce timer, expect SnackBar with "Saved" text. Negative pin: when an undo snackbar is showing (after `_removeRoutine`), the Saved snack does NOT replace it.
- **Fix 1B:** widget test — pump AddRoutinesSheet, find "Create new routine" tile by Semantics identifier, tap → expect sheet pops with a sentinel result. Empty-state test: when `availableRoutines.isEmpty && inPlanIds.isEmpty`, expect a tappable button. Pre-select on return: integration-style widget test that opens the sheet, simulates a return-from-creation (could be a parameterized fixture), verifies the new routine is pre-selected.
- **Fix 2:** unit tests on `propagateWeight` — happy path (3 sets all at 0kg, set 1 → 20kg → all 3 become 20kg), customized-set-stops-propagation (set 2 at 22.5kg stays), completed-set-stops-propagation, weight-only (reps unchanged). Also a test that the emission is atomic: spy on state changes during a propagation and assert exactly 1 emission.
- **Fix 3:** widget test — pump set_row with `lastSet.weight == 0`, expect hint NOT visible. Pump with `lastSet.weight == 20.0`, expect hint visible. If `Visibility(maintainSize:)` is added, pin row height equality across the two cases.

### Acceptance criteria

- `make ci` clean (format + gen + analyze + test + android-debug-build).
- All existing E2E tests still pass (especially `weekly-plan.spec.ts` if it exists, and `active-workout.spec.ts`).
- ARB en + pt parity per CLAUDE.md exercise content rule (the same parity discipline applies to all UI strings).
- `_copyLastSet` icon doesn't break tap-target sizing — verify with `tester.getSize` if needed (per memory feedback `feedback_tap_target_measurement.md`).

### Pipeline tracking

- [x] Branch + WIP entry (Task #53)
- [x] Tech-lead implements all 4 fixes with TDD (Task #54)
- [x] UI/UX implementation review (Task #55)
- [x] QA gate (Task #56)
- [ ] Verify + PR + reviewer cycle (Task #57)
- [ ] Post-merge cleanup (Task #58)

---

## Resume context (post-compact pickup)

**Active-workout exploratory pass: 28 / 31 bugs shipped across 10 PR pairs.
Pass effectively complete.**

| Family | PRs | Status |
|---|---|---|
| 2 — Rest scrim modality | #175, #176 | ✅ |
| 1A — PR cache bootstrap (BLOCKER) | #177, #178 | ✅ |
| 1B — Save-error classification | #179, #180 | ✅ |
| 4 — Tap targets 48dp | #181, #182 | ✅ |
| 8 — Finish-button disabled wiring (STALE) | #183, #184 | ✅ |
| 7 — postFrame race + offline contract | #185, #186 | ✅ (3-round arc) |
| 3 + 6 — A11y semantics + i18n leaks | #187, #188 | ✅ (11 bugs in one cycle) |
| 5A — Web `OfflineBanner` Semantics (root cause: shell layout) | #189, #190 | ✅ |
| 5B — Drain reliability (recovery hook + 60s health check) | #191, _cleanup_ | ✅ |

The remaining 3 bugs in `tasks/active-workout-findings.md` are stale
measurement findings already reclassified during prior families (Family 4
tap-target measurements; cluster-F edge cases) — not regressions to chase.

**Process patterns that worked through the entire pass:**
- TDD discipline (failing-test-first) caught stale measurement findings in
  Families 4 and 8, surfaced architecture-level bugs in Families 1A and 7,
  and exposed the actual layout-bug root cause in Family 5A (initial
  hypothesis blamed `package:web`; tech-lead's systematic-debugging found
  a Flutter Web semantics-tree compaction issue in `_ShellScaffold`).
- Reviewer agent caught real bugs in every cycle. Family 5B caught: missing
  T+5min boundary test, doc/code mismatch on `mapException`, dead-wired
  recovery recorder in `AnalyticsRepository`, over-broad `catch (_)` in
  `_hasTransientItems`, over-broad `AuthException` classification.
- Post-merge cleanup PRs admin-merge after fast checks (memory feedback —
  saves ~20 min per cycle vs waiting on e2e).
- All findings (Critical / Warning / Nit / Suggestion) addressed in same
  cycle per memory feedback — zero post-merge follow-ups.
- `superpowers:systematic-debugging` Phase 1 prevented multiple ad-hoc
  patches that would have shipped the wrong fix.

**Next dispatch when resuming:**
- Active-workout pass is closed. PLAN.md is the canonical source for new
  initiatives (`## Active Backlog` section).

---

_No work in flight._
