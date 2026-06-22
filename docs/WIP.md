# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 T3.2 — decompose 3 monolithic build()s — `feature/hardening-t3.2-build-decompose`

Per `docs/PROJECT.md` §2 → Phase 38.9 T3.2. (Also marks T3.1 ✅ #384 done in §2.)
Three screens have a single `build()` far exceeding the 50-line rule and that upcoming
phases will edit:
- `lib/features/auth/ui/login_screen.dart` — build ~472 lines (worst build:method ratio)
- `lib/features/routines/ui/create_routine_screen.dart` — build ~316 lines
- `lib/features/weekly_plan/ui/week_plan_screen.dart` — build ~220 lines

**No-regression mandate (pure behavior-preserving widget extraction):**
- Extract cohesive subtrees into `const` (where possible) private widgets — rendered output
  IDENTICAL. No layout/style/behavior change, no token changes, no logic moves.
- Existing widget tests are the regression net (`login_screen_test.dart`,
  `create_routine_screen_test.dart`; week_plan has thinner coverage — be extra careful there,
  lean on `flutter analyze` + the snackbar test + manual structure-equivalence).
- If a widget test breaks, the extraction changed rendering → fix the extraction, not the test.

### Checklist
- [x] `login_screen` build → extracted `_BrandHeader` / `_ErrorBanner` / `_ForgotPasswordLink` /
  `_OrDivider` / `_GoogleButton` / `_ModeToggleButton` const sub-widgets. `ref.listen`/error-state
  wiring left exactly in place. Build 432→277 lines (email/password fields + age-gate row + CTA stay
  inline — their closures read/mutate `_isSignUp`/`_ageConfirmed`/`_passwordStrength` via setState,
  out of scope per the wiring rule).
- [x] `create_routine_screen` build → extracted `_ReorderToggle` (header action) / `_RoutineHeaderForm`
  (name+notes fields + eyebrow/counter helpers moved in) / `_EmptyExercisesBeat` / `_AddExerciseButton`.
  Build 298→200 lines (exercise-list slivers stay inline — coupled to `_buildExerciseCard`/`_onReorder`/
  reorder-mode state).
- [x] `week_plan_screen` build → extracted `_OverflowMenu` / `_WeekHeaderRow` / `_AddWorkoutCta` /
  `_SoftCapWarning`. Build 219→140 lines (bucket ReorderableListView + engagement `.when` stay inline —
  coupled to `_removeRoutine`/`_renumber` + per-row keying).
- [x] Each extracted widget takes explicit params (no hidden state); `const` ctors where possible.
- [x] `dart format` + `dart analyze --fatal-infos` clean; FULL `flutter test` green, same pass
  count (3978 +1 skipped, baseline-identical); widget tests for all three screens pass unchanged (130).

_Tier 1 + Tier 2 (T2.1–T2.4) + T3.1 merged. T2.5/T2.6 + Tier 0 + T3.3/T3.4 queued._
