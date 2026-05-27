# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 32 PR 32c — Week-plan picker repeat-fix + weekday `.toLocal()` fix

Per PROJECT.md §3 Phase 32 → PR 32c + `docs/home-to-workout-flow-audit.md`
(bucket-chip done-flip E2E + workout-spans-midnight regression fold in
here per the audit's triage map). Branch:
`fix/phase-32c-week-plan-picker-toLocal`.

### Bug 1 — Week-plan picker filters picked routines (blocks repeating across days)

- [x] Investigate `lib/features/weekly_plan/ui/add_routines_sheet.dart` —
      locate the filter. Filter was at the CALLER (`week_plan_screen.dart::
      _showAddSheet` L416-419), not the sheet itself.
- [x] Remove the filter — `_showAddSheet` now passes the full `allRoutines`
      list straight through. Updated `AddRoutinesSheet`'s class doc + the
      `availableRoutines` field doc to reflect the new contract.
- [x] Verify the save path supports repeats — `WeeklyPlanRepository.
      upsertPlan` serializes the entire bucket as a JSONB array (no UNIQUE
      on `routine_id`); `BucketRoutine` keys on `(routineId, order)`;
      `WeeklyPlanNotifier.upsertPlan` (called from `_savePlan`) doesn't
      dedupe. Only `addRoutineToPlan` has a dedupe and it's only used by
      `post_workout_navigator.dart` for the spontaneous-match flow — not
      our path.

### Bug 2 — Weekday label drift between Home + Week Plan screens

- [x] `week_plan_screen.dart` — `_shortDayLabel` retired in favor of a new
      `WeekdayFormatter.shortDayLabel` shared helper (`lib/core/utils/
      weekday_formatter.dart`). The helper calls `.toLocal()` BEFORE
      `DateFormat.E.format()`. Two modes (`uppercase: true|false`) so the
      Week Plan editor's title-case row meta + Home's uppercase chip label
      share the same underlying weekday.
- [x] Audit other call sites — only 2 instances of `DateFormat.E(...).
      format(...)` in `lib/`: `bucket_chip_row.dart:339` (already correct)
      and the now-retired `week_plan_screen.dart:692`. Below 3-instance
      threshold; no cluster ledger entry added (surface for orchestrator
      triage if more drift emerges).
- [x] `bucket_chip_row.dart` left UNTOUCHED per orchestrator instruction
      (regression risk). A snapshot replica of its `_shortDayLabel` logic
      lives in `weekday_consistency_test.dart` and pins that the shared
      formatter produces byte-identical output — future divergence breaks
      the test.

### Tests

- [x] Unit `test/unit/features/weekly_plan/weekday_consistency_test.dart`
      — 4 tests, all green. Pins: (a) `.toLocal()` is applied before
      formatting; (b) uppercase + title-case modes agree on weekday across
      all 7 weekdays + 2 boundary UTC instants in both en + pt locales;
      (c) title-case output is 3-char + first-letter-uppercase; (d) shared
      formatter matches bucket_chip_row's snapshot replica byte-for-byte.
      Initializes intl locale data in `setUpAll` so the pt path doesn't
      fall back to missing-symbol behavior.
- [x] Widget `test/widget/features/weekly_plan/picker_repeat_test.dart`
      — 2 tests, both green. Pins: (a) sheet renders every routine in the
      `availableRoutines` list (no internal filter); (b) tapping the same
      routine returns it via the Selected sentinel — caller is responsible
      for appending a new ordered `BucketRoutine` entry.
- [x] E2E `test/e2e/specs/weekly-plan.spec.ts` — added test "should render
      bucket chip in done state for completed routine (PR 32c)" in the
      `Weekly Plan review` describe block (smokeWeeklyPlanReview user is
      seeded with completed Push Day routines). Asserts the chip's
      accessible name carries an uppercase weekday label (regex covers en
      + pt-BR 3-letter abbrevs) — that label is ONLY emitted in the done
      state. Playwright list confirms it parses (15 tests in file).

### Verification + ship

- [x] `dart format --output=none --set-exit-if-changed lib/ test/` clean
- [x] `dart analyze --fatal-infos` — No issues found
- [x] `check_reward_accent.sh` / `check_hardcoded_colors.sh` /
      `check_typography_call_sites.sh` all clean
- [x] `flutter test test/unit/features/weekly_plan/ test/widget/features/
      weekly_plan/ test/widget/features/workouts/ui/widgets/
      bucket_chip_row_test.dart` — 156/156 pass
- [x] `git grep -nE 'DateFormat\.E\([^)]*\)\.format\([^)]*\)' lib/` — only
      `bucket_chip_row.dart:339` (which uses `local`, already correct)
- [ ] PR description includes
      `**QA pass pending — final coverage + E2E run after code review.**`
      (orchestrator opens the PR)
- [x] No new migration — no Supabase push needed
