# Work In Progress

Active branch work. Removed once merged. Empty when no in-flight work exists —
backlog/parked items live in `docs/PROJECT.md` §2.

---

## a11y fixes — tap targets + contrast (Phase 38.9 T2.6 follow-ups) — `feature/a11y-contrast-and-tap-targets`

Per `docs/PROJECT.md` §2 → the a11y findings the #400 gate surfaced. Two WCAG-AA gaps on the
highest-traffic surfaces. Careful: contrast is a token change with blast radius + a visual change
(needs the 320/360/412dp screenshot gate); tap-targets must NOT change the row layout/BUG-019 budget.

### Tap targets — REVERTED (accepted BUG-019 dense-row limitation)
- [x] **REVERTED to main.** The visual-verification gate proved the 48dp-WIDE stepper hit-rect is not
  achievable in the active-workout row: at 360dp baseline width the +/- button's expanded 48dp hit-rect
  (242–290) swallows the adjacent value-node center (cx≈244), so tapping the reps number fired
  "Increase reps" instead of opening the reps editor. The per-node widget tests measured each button in
  isolation and missed the neighbor occlusion. A true 48×48 stepper target requires a full row redesign
  (out of scope). Reverted:
  - `weight_stepper.dart` + `reps_stepper.dart` → restored to main's 40×48 IconButton (MergeSemantics
    label fold intact; no OverflowBox).
  - `stepper_hit_target.dart` → deleted (the wrapper that caused the occlusion).
  - `set_row.dart` done-cell → restored to main's form (identifier `Semantics` back on the inner 32dp
    visual, no `ExcludeSemantics` lift), preserving main's Flutter-Web role-swap workaround exactly. The
    52×48 outer GestureDetector hit-box is main's pre-existing PR-2 H1 box — unchanged.
- Tap-targets are now **unchanged from main**. Tracked as a follow-up row-redesign item in PROJECT.md §2.

### Contrast (per ui-ux-critic scoping — tokenization cleanup, NOT a global wash-out)
Most failures are NOT `textDim` (it passes ~6.62) — they're inline `onSurface.withValues(alpha:)` /
dimmed `primary` literals (uncaught by the hardcoded-color gate) + a compounding bug.
- [x] Add `AppColors.textDimAA` — value BUMPED to `0xFFCFC5E3` (rendered oracle under-reported the
  original `0xFFBBAFD4` to 4.38 at 10sp due to small-glyph AA blend; `0xCFC5E3` clears it, pure
  ratio 12.21/11.07/10.09). Text-only; `textDim` kept for decorative non-text. Documented.
- [x] Migrate TEXT tier: `bodySmall.color` + `numericSmall.color` → `textDimAA`. Theme unit tests
  updated (`arcane_theme_test.dart`) + new deterministic AA-ratio pins for textDimAA AND hotViolet.
- [x] Login: wordmark / Forgot-pwd / mode-toggle / Terms+Privacy links → `hotViolet` SOLID;
  OR-divider / legal-muted / welcome-subtitle → `textDimAA` solid. (Login full-screen contrast oracle
  not asserted — it under-reports thin hotViolet glyphs + a degenerate "." node; AA pinned via theme
  ratio tests instead. Documented in the a11y test library-doc.)
- [x] SetRow "kg": `textDimAA` solid AND pulled OUT of the completed-row `Opacity(0.6)` (Opacity now
  wraps only the stepper value `Expanded`; unit is a full-opacity sibling). Both pending+completed
  SetRow contrast guidelines PASS rendered.
- [x] HomeGreeting eyebrow → `textDimAA`. Full HomeGreeting contrast oracle PASSES.
- [x] **Sweep done — REPORTED (NOT migrated; out of T2.6 scope → follow-up sweep phase).** 112
  `onSurface/primary.withValues(alpha:)` hits across 40 files + ~10 explicit `textDim` text overrides.
  Most are decorative (borders/fills/chart gridlines/icon tints @ ≤0.3). Dim TEXT on alpha ≥0.45 lives
  on Profile/Exercises/Workout-history/Onboarding/PR-list etc. — a design-token contrast sweep with
  its own visual gate (cluster `design-token-sweep-on-new-tokens`), not foldable into this phase.

### Verify (careful — rendered oracle + visual gate)
- [x] `dart analyze --fatal-infos` clean; `check_typography_call_sites.sh` + `check_hardcoded_colors.sh`
  green.
- [x] a11y gate (`test/widget/a11y/`): CONTRAST tests asserting (un-skipped) — SetRow contrast
  (pending + completed Opacity-exclusion), HomeGreeting eyebrow, LoginScreen-via-theme-pins all PASS
  RENDERED. TAP-TARGET tests RE-SKIPPED (`skip: true`) with an honest "accepted BUG-019 dense-row limit"
  name for RepsStepper, WeightStepper, SetRow (standard), SetRow predicted-PR — a 48dp width steals the
  neighbor's tap; needs a row redesign (PROJECT.md §2). Labeled-tap-target tests still assert (label
  fold + done-cell identifier are main's form, unaffected). textDimAA bumped to clear the oracle.
- [x] Full `flutter test` green: **4000 passed, 4 skipped, 0 failures** (the 4 skips are the re-skipped
  tap-target tests — RepsStepper, WeightStepper, SetRow standard, SetRow predicted-PR).
- [ ] Visual gate (handed to qa/Playwright after): build web, screenshot Login (login+signup), Home,
  SetRow (pending/done/PR states) at 320/360/412dp — confirm AA improvement renders + the dim aesthetic
  survives (not washed out).

_meta-1.18 quartet investigated → DON'T adopt (blocker intact); lock-truth fix in #403._
