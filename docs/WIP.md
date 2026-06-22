# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 T2.5 + T2.6 (easy wins) — `feature/hardening-t2.5-t2.6-gates`

Per `docs/PROJECT.md` §2 → Phase 38.9 T2.5/T2.6 (refined specs). Build the two deterministic,
low-flake slices; leave the harder pieces (EXPLAIN plan-gate, automated visual regression)
documented-deferred. CI/tooling + tests → reviewer reads.

### T2.5 — perf gate: index-coverage (deterministic, not wall-clock)
- [x] pgTAP test `supabase/tests/hot_path_index_coverage_test.sql` (auto-runs via the existing
  bare `supabase test db` / `rls-tests` CI harness — no --file filter, no new CI job).
  10 `has_index` assertions on the hot-path indexes, each documenting which hot query relies on it:
  `xp_events` ×4 (user_set_unique idempotency, user_cardio_session_unique, user_occurred window,
  session partial), `body_part_progress` PK (user_id, body_part), `sets` FK (workout_exercise_id),
  `exercise_peak_loads` PK + `_by_rep_range` PK, `cardio_sessions` (workout_id + exercise_id).
  All 10 verified present on current schema. `supabase test db` → Files=2, Tests=68, Result: PASS.

### T2.6 Track A — a11y guideline gate (deterministic widget tests)
- [x] Added `test/widget/a11y/a11y_guidelines_test.dart` — pumps key surfaces and runs the three
  built-in matchers (textContrast / androidTapTarget / labeledTapTarget). Surfaces: GradientButton,
  RepsStepper, WeightStepper, SetRow (standard + predicted-PR), ClassBadge, LoginScreen, HomeGreeting.
  `flutter test` → 3994 tests, 0 failures (was ~3979; +15 a11y assertions). `dart analyze --fatal-infos`
  clean. Gate GREEN on current code.
  - **Fixed in-widget:** the +/- stepper buttons emitted an unlabeled inner IconButton tap node
    (outer `Semantics(label:)` was on a separate node) → wrapped each in `MergeSemantics`
    (`reps_stepper.dart` + `weight_stepper.dart`, cluster_semantics_identifier_pair_rule). Now
    `labeledTapTargetGuideline` passes for both steppers + SetRow. All existing stepper/SetRow tests
    still pass (no gesture-path regression).
  - **Reported-for-production (deferred, skipped with `// TODO(a11y):`):** (1) stepper/SetRow tap
    targets are 40×48 / 32×32 by deliberate BUG-019 row-budget — raising to 48×48 is a row-layout
    change; (2) low-contrast dim text — SetRow "kg" (1.13), HomeGreeting date eyebrow (2.78), several
    LoginScreen secondary labels (1.21–2.95). These are AppColors.textDim token choices → design pass.

### Deferred (documented in §2, NOT built here)
- T2.5 EXPLAIN/auto_explain plan-gate (per-row-subquery/N+1 detection) — plpgsql hides inner plans.
- T2.6 automated visual regression — widget goldens can't catch CanvasKit paint bugs; make the
  manual Playwright visual gate non-skippable instead (a separate process change).

_Phase 38.9 Tiers 0-3 done. This closes the buildable part of T2.5/T2.6._
