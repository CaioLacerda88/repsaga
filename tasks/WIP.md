# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/workouts-tap-targets-48dp — Family 4 from active-workout exploratory pass

**Branch:** `fix/workouts-tap-targets-48dp`
**Source:** `tasks/active-workout-implementation-plan.md` Family 4 + master findings AW-EX-A-BR1-01 (M), AW-EX-A-BR1-02 (m), AW-EX-F-BR1-09 (m).

**Root cause:** several interactive widgets in the active-workout flow render below Material's 48dp minimum on the smallest priority viewport (360×780):
- **Done-mark** (`set_row.dart:990` per impact analysis) — 32×32 px, 33% below the 48dp minimum height (AW-EX-A-BR1-01)
- **Add Set button** — Charter A measured 40-tall on BR-1; impact analysis flagged this as POSSIBLY stale (`_AddSetButton` at `exercise_card.dart:540` already declares `minimumSize: Size(double.infinity, 48)`). Investigate first to confirm the discrepancy. (AW-EX-A-BR1-02)
- **Dialog `TextButton` actions** (Finish / Discard / Weight / Reps / Remove dialogs + SnackBar Undo) — render at Flutter's default 36dp. Systemic across the active-workout flow. (AW-EX-F-BR1-09)

**Fix scope (Family 4):**
1. **Investigate AW-EX-A-BR1-02 first.** Measure the `_AddSetButton` rendered size on a 360-wide test viewport. If it's already ≥48dp, the Charter A finding was a measurement error — mark resolved without code change. If real, fix.
2. **Done-mark cell widening** in `set_row.dart` — increase the wrapper around the done-mark / predicted-PR-mark to ≥48×48dp on smallest viewport. The visual ◆/✓ stays small; only the tap-target box grows.
3. **Project-wide `dialogTextButtonStyle`** — introduce a shared style with `minimumSize: Size(64, 48)` and apply across all `AlertDialog` actions in the active-workout flow (Finish, Discard, Weight stepper input, Reps stepper input, Remove exercise) AND the SnackBar undo action. Place the style in `lib/core/theme/` next to the existing button styling.
4. Tests: widget tests measuring `boundingBox` of each interactive on a 360-wide test viewport. Assert ≥40 wide AND ≥48 tall.

### Checklist

- [x] tech-lead: read implementation plan §Family 4 + Charter A / F findings; specifically confirm the AW-EX-A-BR1-02 stale-vs-real status before touching the Add Set button
- [x] tech-lead: TDD — failing widget tests first (boundingBox of done-mark + dialog actions on 360-wide viewport)
- [x] tech-lead: widen done-mark cell wrapper to ≥48×48dp without changing the visual size of the icon — done via outer `SizedBox(40, 48)` + `GestureDetector` wrapping the existing 32×32 visual; inner Semantics still owns AOM identifier + tap action
- [x] tech-lead: introduce `dialogTextButtonStyle` in `lib/core/theme/` with `minimumSize: Size(64, 48)`; apply across the 5 active-workout dialogs (SnackBar Undo deferred — see verdict below)
- [x] tech-lead: AW-EX-A-BR1-02 — **confirmed STALE.** Pre-fix measurement on 360-wide test viewport: Add Set OutlinedButton renders at **300.0w × 48.0h dp** — already meets Material 2.5.5. The Charter A "40 px tall" reading was a Playwright `boundingBox()` measurement error (probably reported visual content height instead of full button hit-area). Test kept as a regression guard.
- [x] tech-lead: AW-EX-F-BR1-09 — **also confirmed largely STALE at the rendered level.** Pre-fix dialog action measurements on a 360-wide test viewport all reported 48.0h (Material 3's `MaterialTapTargetSize.padded` default already inflates the hit-test region to ≥48dp even when `minimumSize` is the legacy `(64, 36)`). The `dialogTextButtonStyle` was still applied as defense-in-depth: makes the 48dp floor STRUCTURAL at the call site so a future contributor flipping `materialTapTargetSize: shrinkWrap` won't silently regress. SnackBarAction (the Undo) is also already ≥48dp via the same Material default — and `SnackBarAction` does not expose a `style` parameter, so applying the shared style there would require wrapping in a custom widget; deferred (kept the print verdict in the test for the audit record).
- [x] tech-lead: `dart format` + `dart analyze --fatal-infos` clean; full unit/widget suite green (2440/2440)
- [x] orchestrator: CI green — format clean, `dart analyze --fatal-infos` 0 issues, reward-accent + hardcoded-colors guards clean, 2406 tests passing (+7 from Family 4), android-debug APK built in 34.6s
- [x] qa-engineer: PASS across all 7 acceptance criteria — selector impact zero (outer GestureDetector excluded from semantics; AOM identifier hierarchy unchanged); 7 measurement tests use `tester.getSize` on a 360-wide viewport with proper teardown; defense-in-depth correctly applied across 5 dialog surfaces; SnackBarAction deferral structurally correct (no `style` param; Material default already 48dp); 138 existing workout widget tests pass cleanly; no `lib/` regression
- [x] orchestrator: PR #181 opened — https://github.com/CaioLacerda88/repsaga/pull/181
- [x] reviewer round 1: PR #181 — Critical (gesture-arena double-fire) + 3 Warnings + 2 Suggestions
- [x] reviewer round 2 — all 6 findings addressed in a single follow-up commit:
  - [x] **Critical (gesture-arena single-fire):** flipped `_DoneCell` outer GestureDetector to `HitTestBehavior.deferToChild`. Investigation finding (Phase 1 systematic debugging): the reviewer's specific premise — that `translucent` causes BOTH detectors to fire, producing toggle-on→toggle-off — does NOT actually reproduce today. Flutter's `GestureArena.sweep` resolves two competing `onTap`-only recognizers by accepting the FIRST member (innermost child) and rejecting all others (`arena.dart` line 170-178). So `completeSet` fired exactly once both pre- and post-fix in the harness. The `deferToChild` change is still architecturally correct — STRUCTURAL defense rather than relying on first-member-wins arena semantics. Robust to future refactors that introduce competing non-tap recognizers (long-press / pan-cancel) which CAN produce double-accept resolution. Pinned by 2 new `gesture-arena single-fire pin` tests counting `completeSet` invocations on a no-mutation fake notifier.
  - [x] **Warning 1 (fragile `.first` SizedBox):** anchored both done-cell hit-area finders on a precise `SizedBox && w.width == 40 && w.height == 48` predicate so a future SizedBox insertion can't silently measure the wrong widget.
  - [x] **Warning 2 (defense-in-depth dialog test):** added a test that wraps a TextButton under a Theme with `MaterialTapTargetSize.shrinkWrap`, asserts a bare TextButton renders <48dp (sanity anchor), then asserts a TextButton with `dialogTextButtonStyle` STILL renders ≥48dp. Pins the structural defense-in-depth contract — the style isn't theatrical.
  - [x] **Warning 3 (docblock too long):** trimmed `dialog_button_style.dart` from 38 to 11 lines. Kept: scope sentence + composition example. Dropped: Material 2.5.5 AAA citations + Family 4 references (covered by PR description and git log).
  - [x] **Suggestion 1 (destructive button duplication):** `discard_workout_dialog.dart` and `exercise_card.dart` now use `dialogTextButtonStyle.copyWith(foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error))` — single source of truth for the 48dp floor.
  - [x] **Suggestion 2 (inline FilledButton.styleFrom):** added `dialogFilledButtonStyle` to `dialog_button_style.dart`; `finish_workout_dialog.dart` "Save & Finish" now uses it.
- [x] tech-lead round 2: `dart format` clean, `dart analyze --fatal-infos` 0 issues, full unit/widget suite green (2409/2409, +3 from round 1).
- [ ] squash merge to main, delete branch, post-merge cleanup PR (mark Family 4 resolved)
