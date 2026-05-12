# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Phase 23 — Active Workout: rest-overlay chrome + hint-text removal

**Branch:** `fix/active-workout-rest-and-prefill`
**Trigger:** user on-device feedback (2026-05-12) — two distinct issues observed during a real workout (Upper/Lower — Upper, Supino Reto com Barra).

**Issue 1 — rest overlay z-order + back-button.**
- `+ Adicionar exercício` FAB and `FINALIZAR` bottom button render ABOVE the rest-timer scrim (visible in the user's screenshot). They shouldn't.
- Android back button currently shows the discard dialog instead of dismissing the rest timer.

**Issue 2 — per-row hint texts are inconsistent and not useful.**
- The `Previous: 80kg × 8` and `= last set` hint lines flicker on/off based on suppression rules (no prior data, 0kg, completion, match). User reads this as visual noise.
- Per PO + UI/UX research (2026-05-12): the user's instinct is correct — pre-fill already covers the anchor job, the hint is a shadow duplicate. **Verdict: remove the hints; pre-fill the fields; the yellow PR marker remains the win signal.** Earlier proposal of a per-exercise summary chip was **rejected by user** — keep the surface as bare as possible.

### Source decisions (locked in)

| # | Decision | Source |
|---|---|---|
| D1 | Rest overlay fix: hide FAB + FinishBottomBar conditionally while rest is active (preserves PR #198 body-slot architecture and Q5 snackbar reachability). AppBar X stays. | User-approved 2026-05-12 |
| D2 | Back button: if rest timer is active → dismiss timer via `restTimerProvider.notifier.stop()` and do NOT show discard. | User-approved 2026-05-12 |
| D3 | Back button during loading overlay (rare, finish/discard network in flight): still route to discard coordinator (loading has its own Cancel CTA — back is reasonable escape). | Tech-lead default; user-deferred |
| D4 | Drop all per-row hint texts: `Previous: …`, `= last set`, mobile `!kIsWeb` filler, related Semantics islands. Drop `lastSet` constructor param on `SetRow`. | User-approved 2026-05-12 |
| D5 | No per-exercise summary chip in card header. | User-approved 2026-05-12 (reversed earlier preview) |
| D6 | Auto-seed set 1 on `addExercise` with last-session working-set values (Hevy/Strong-style). Matches user's stated intent: "save the last weights and repeat them." | User-approved 2026-05-12 |

### Test coverage contract

**Every code change below must ship with both:**
1. **Inline documentation** — dartdoc/comment on the changed method/widget explaining the WHY (not WHAT). Reference the source decision (D1–D6) and the PR/incident that motivates it. Multi-paragraph context only where load-bearing (e.g. the PR #198 body-slot trade-off, the AOM role-swap history); one-liners elsewhere per CLAUDE.md "default to no comments."
2. **Test coverage** — a unit/widget test pinning the new behavior AND, where applicable, an E2E test confirming the user-visible contract.

The checklists below pair each implementation item with its required tests + docs. A change without its paired test box ticked is NOT done.

### Fix 1 — Rest overlay chrome cleanup

**F1.1 — Hide FAB + FinishBottomBar while rest is active**
- [ ] **Code** — `lib/features/workouts/ui/active_workout_screen.dart` `_ActiveWorkoutBody.build`: gate `floatingActionButton` and `bottomNavigationBar` on `!widget.showRestTimerOverlay`. AppBar untouched.
- [ ] **Doc** — Replace the existing PR-2 C3 dartdoc block (L109-131) with a brief note: "Rest overlay covers the body slot only by PR #198's C3 design. To complete the 'overlay over everything' contract (Phase 23 D1), FAB + FinishBottomBar are conditionally hidden while `showRestTimerOverlay` is true. AppBar stays — its X is the in-rest discard affordance."
- [ ] **Widget test** — new `test/widget/features/workouts/ui/active_workout_rest_chrome_visibility_test.dart`:
  - `should hide AddExerciseFab when rest timer is active`
  - `should hide FinishBottomBar when rest timer is active`
  - `should restore FAB and Finish after rest timer stops`
  - `should keep AppBar discard X reachable during rest` (re-confirms `active_workout_appbar_discard_during_rest_test.dart` contract is preserved)
- [ ] **E2E test** — new describe block in `test/e2e/specs/workouts.spec.ts` tagged `{ tag: '@smoke' }`: `Rest overlay chrome`:
  - `should hide add-exercise FAB and finish bar while rest timer is visible` — start a workout, complete a set to trigger rest, assert `WORKOUT.addExerciseFab` and `WORKOUT.finishBtn` are `toBeHidden()`, dismiss rest, assert both are `toBeVisible()` again.
  - Add the new test user `smokeRestChrome` to `test/e2e/fixtures/test-users.ts` + `test/e2e/global-setup.ts` per CLAUDE.md E2E conventions (one user per describe block).
  - Update `test/e2e/helpers/selectors.ts` if needed — confirm `WORKOUT.addExerciseFab` and `WORKOUT.finishBtn` selectors exist; add semantic identifiers in the widget if either is missing (`Semantics(identifier:)` with pair-rule per PR #152 lessons).

**F1.2 — Back-press priority chain (rest → dismiss; loading → discard; else → discard)**
- [ ] **Code** — `lib/features/workouts/ui/active_workout_screen.dart` outer `PopScope.onPopInvokedWithResult` (L152-158): replace with the priority chain. `timerState` is already in scope at the parent `build` (L78); use directly.
- [ ] **Doc** — Inline dartdoc on the `onPopInvokedWithResult` callback explaining the three branches and pointing to D2/D3. One paragraph. Include "Phase 23 D2: rest is the dominant on-screen affordance; back-press dismisses rest first. Loading overlay branch (D3) preserves existing discard route — loading has its own Cancel CTA."
- [ ] **Widget test** — extend `test/widget/features/workouts/ui/active_workout_appbar_discard_during_rest_test.dart` (or new sibling `active_workout_back_button_priority_test.dart`):
  - `should stop rest timer on Android back press without showing discard dialog`
  - `should fall through to discard dialog when rest timer is inactive`
  - `should fall through to discard dialog when loading overlay is active even if rest timer is also active`
  - `should stop rest timer exactly once when back press fires during rest` (no double-stop / no spurious state listener re-entrance — covers risk #2 in the register)
- [ ] **E2E test** — extend the new `Rest overlay chrome` describe block in `workouts.spec.ts`:
  - `should dismiss rest timer when Escape (browser back analog) is pressed` — Flutter web maps `Escape` to PopScope; same code path as Android back. Start a workout, trigger rest, `await page.keyboard.press('Escape')`, assert rest scrim is `toBeHidden()` AND discard dialog is `not.toBeVisible()`.
  - `should show discard dialog when Escape is pressed with no rest timer active`
  - Note in test comment: Android-native back press is not Playwright-reachable; widget tests own the deeper PopScope contract.

### Fix 2 — Hint removal + pre-fill on add-exercise

**F2.1 — Strip hint logic from `SetRow`**
- [ ] **Code** — `lib/features/workouts/ui/widgets/set_row.dart`:
  - Remove `_matchedLastSet()`, `_shouldShowHint()` methods.
  - Remove the three-branch hint slot block (L366-424) including the mobile-only `!kIsWeb` filler.
  - Remove the `lastSet` constructor parameter + field. Search the file for every remaining `widget.lastSet` reference and verify all callsites are dead.
  - Remove `package:flutter/foundation.dart` import iff no remaining `kIsWeb` reference (verify via grep before deleting).
  - Verify `previousSet` field (in-session N-1 copy-hint at L65) is UNTOUCHED — it's a separate concept.
- [ ] **Doc** — Replace the L174-237 + L293-365 dartdoc blocks with a single short note: "Hint logic removed 2026-05-12 (Phase 23 D4). Pre-fill carries the anchor; the PR yellow marker carries the win signal. Removing the conditional hint slot eliminates the Flutter Web AOM role-swap mutation vector documented in the PR #159 / #193 incidents — the row Semantics tree shape is now fixed at render time."
- [ ] **Widget test** — `test/widget/features/workouts/ui/widgets/set_row_test.dart`:
  - DELETE `group('ghost text (previous session hint)', …)` (~L335-404)
  - DELETE `group('match indicator (Pillar 1)', …)` (~L406-489)
  - DELETE the "Fix 3 — 0kg suppression" block (~L2182-2320; search `Fix 3 —`)
  - DELETE standing-PR + hint interaction tests (~L2808-2956)
  - Remove `lastSet:` from every remaining `SetRow(...)` construction in the file.
  - Add new test: `should not render any previous-session hint text` — pump a `SetRow` with a workout-exercise that has prior data via the notifier; assert `find.textContaining('Previous:')`, `find.textContaining('= last set')`, `find.textContaining('Anterior:')`, `find.textContaining('última série')` all return `findsNothing`. Cover both EN and PT locales (one test each).
  - Add new test: `row Semantics tree shape is stable across set completion` — pump the row, capture the Semantics tree (via `tester.getSemantics`), tap the done cell, capture again, assert the structural shape matches. Pins the AOM regression-removal directly.
- [ ] **E2E test** — extend the existing `Personal records` describe block in `test/e2e/specs/personal-records.spec.ts` (no new user needed, reuse the existing PR-baseline user):
  - `should not show per-row previous-session hint in active workout (Phase 23)` — start workout, add exercise with prior data, assert the text `/Previous:|Anterior:|= last set|= última série/` is NOT visible anywhere in the exercise card region.
- [ ] **E2E cleanup** — `test/e2e/specs/charter-c-exploratory.spec.ts` L1018-1034 `prevHintBefore` probe — leave the probe (exploratory diagnostics, returns 0 hits now) AND add an inline comment: `// Phase 23: per-row hint removed; probe kept for historical diagnostics, will report 0 hits.`

**F2.2 — Drop `lastSet:` arg at the `SetRow` callsite**
- [ ] **Code** — `lib/features/workouts/ui/widgets/exercise_card.dart`: remove the `lastSet: lastSet,` arg in `_buildSetRows` (~L422) and the `index < lastSets.length ? lastSets[index] : null` lookup feeding it (~L404). Preserve the `lastSets` variable + lookup that drives `_onAddSet` pre-fill — still load-bearing.
- [ ] **Doc** — short inline comment on the kept `lastSets` lookup: "Used only for `_onAddSet` pre-fill defaults (Phase 23 D6). Per-row hint consumption removed."
- [ ] **Widget test** — `test/widget/features/workouts/ui/widgets/exercise_card_test.dart`:
  - Confirm the warmup-filter pre-fill tests (~L451-540) still pass unchanged (they exercise Add Set, not the hint).
  - Add new test: `should not render any per-row hint text` for an exercise with prior data (mirror of F2.1's row-level test but at the card level).

**F2.3 — Auto-seed set 1 on `addExercise`**
- [ ] **Code** — `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` `addExercise`: instead of `sets: const []`, build a single seeded set:
  - Read `lastWorkoutSets[exerciseId]` (existing data plumbing).
  - Filter `setType != SetType.warmup` (Phase 22 Q2 warmup-filter convention).
  - Take the working-set with the lowest set_number (set 1's match); if absent, fall back to the LAST working set's values; if no working sets exist, fall back to the exercise's equipment defaults.
  - Bodyweight exercises: skip the weight value (keep `weight: null` or `weight: 0` per existing schema convention — verify in the model), use the prior reps; if no prior data, use equipment-default reps.
  - The new set must have: fresh client UUID, `set_number: 1`, `is_completed: false`, `set_type: SetType.working`.
  - Verify call-site separation: confirm `addExercise` is NOT reached on routine-start (routine-start uses `startRoutineWorkout` which has its own pre-fill at L340-370). Document the call-site map in a comment.
- [ ] **Doc** — Dartdoc on `addExercise` explaining the auto-seed contract (D6), the fallback chain, and the warmup-filter convention pointer (Phase 22 Q2).
- [ ] **Unit test** — `test/unit/features/workouts/providers/active_workout_notifier_test.dart` (or wherever `addExercise` is exercised today; create the group if absent):
  - `should auto-seed set 1 with prior working-set values when last session has matching exercise data`
  - `should auto-seed set 1 with last working-set values when prior set count < 1 match (fallback to last available)`
  - `should fall back to equipment defaults when no prior data exists for the exercise`
  - `should fall back to equipment defaults when prior session contained ONLY warmup sets (warmup-filter applied)`
  - `should auto-seed reps but not weight for a bodyweight exercise with prior data`
  - `should auto-seed equipment-default reps for a bodyweight exercise with no prior data`
  - `should generate a unique client UUID for the seeded set` (regression guard against any accidental shared-UUID bug)
  - `should set is_completed=false and set_type=working on the seeded set`
- [ ] **Widget test** — `test/widget/features/workouts/ui/active_workout_screen_add_exercise_test.dart` (new or extend existing):
  - `should render exercise card with one pre-filled set immediately after add-exercise` — pump screen, trigger picker → pick exercise with prior data, assert exactly one set row exists with the expected weight/reps values.
- [ ] **E2E test** — extend `test/e2e/specs/workouts.spec.ts` Workout logging describe block (or add a new sibling describe `Add exercise auto-seed`):
  - `should auto-seed set 1 with last session values when adding an exercise mid-workout` — seed user with a prior workout of bench press at 80kg×8 (use existing test fixture helpers), start a fresh quick workout, tap Add Exercise → pick bench press, assert the new exercise card has one set with the weight stepper showing `80` and the reps stepper showing `8`.
  - `should auto-seed equipment defaults when adding an exercise with no prior data` — seed an exercise that the user has never logged, add it mid-workout, assert the set defaults to the equipment-default values (whatever the seed migration sets — verify in `00010_seed_exercises.sql` and similar).
  - New user `smokeAutoSeed` in `test-users.ts` + `global-setup.ts`. Reuse seeded prior-workout helpers from `seededFinishWorkoutUsers` pattern (verify the helper exists, otherwise add it).

**F2.4 — ARB key cleanup**
- [ ] **Code** — `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb`: remove the `previousSet` key + `@previousSet` placeholders block, `matchedLastSet` key + its placeholders, and any `*Semantics` keys exclusively serving these strings (search both ARBs for `previous`, `matched`, `lastSet` to enumerate).
- [ ] **Doc** — No inline doc needed for ARB deletes (the WIP entry + commit message carry the rationale).
- [ ] **Build verification** — Run `make gen` after the ARB edits. The build will fail loudly if any Dart file still references the deleted keys — that's the test. Also run `dart analyze --fatal-infos` to surface dead references.
- [ ] **E2E** — none for this item (ARB deletion is verified by F2.1's "no hint text visible" assertions).

### Cross-cutting

**Verification gate (must run before opening PR)**
- [ ] Full `make ci` green: format + gen + analyze (--fatal-infos) + test + android-debug-build.
- [ ] E2E smoke + the three previously-fragile specs:
  ```bash
  cd test/e2e && FLUTTER_APP_URL= npx playwright test --grep @smoke specs/workouts.spec.ts specs/personal-records.spec.ts specs/rank-up-celebration.spec.ts --reporter=list
  ```
  - The three tests that broke under PR #159/#193 (`personal-records.spec.ts:264`, `:309`, `rank-up-celebration.spec.ts:847`) MUST stay green.
- [ ] Full E2E regression locally: `cd test/e2e && FLUTTER_APP_URL= npx playwright test --reporter=list`. All 234 tests pass (62 `@flaky`-tagged are excluded by default).
- [ ] On-device walkthrough on Samsung S25 Ultra (Android 16):
  - Rest-timer dismiss via tap, via Skip button, AND via Android back button (the OS button itself, not Escape).
  - FAB + Finalize are NOT visible while rest timer is on screen.
  - Add-exercise mid-workout: the new exercise card opens with one set already pre-filled at last session's values.
  - Row layout has no flickering hint slot — verify by completing and un-completing sets.

**Risk register**
1. **AOM role-swap regression** on the three previously-fragile E2E tests. Mitigation: those three tests are explicitly in the smoke gate above. The structural change here (removing the conditional hint slot) makes the row Semantics tree shape STRICTLY simpler than the failed PR #159/#193 attempts; risk surface is lower than those, but the smoke gate is the verifier.
2. **Auto-seed regression in routine-start flow.** `addExercise` is the quick-workout / mid-routine add path; `startRoutineWorkout` has its own pre-fill at notifier L340-370. Tech-lead must verify call-site separation in code AND add a unit test pinning `startRoutineWorkout` is untouched (no double-seed).
3. **Stale `lastWorkoutSets` pre-fill after a fresh save/discard.** Risk: auto-seed could carry forward values from a since-deleted workout if `lastWorkoutSetsProvider` is not invalidated post-finish. Mitigation: confirm invalidation point in `active_workout_notifier.dart::finishWorkout` AND `discardWorkout`; if missing, add it AND a unit test pinning the invalidation.
4. **E2E selector drift.** F1.1's E2E test needs reliable selectors for the FAB and Finish bar. If either lacks a `Semantics(identifier:)` today, add it during this PR (pair-rule per PR #152 lessons) and update `selectors.ts`.

**PR strategy**
- **Single PR.** Both fixes touch the same active-workout surface and share test scaffolding (rest-timer provider override, `pumpUntilDone` helpers). Splitting would force the second PR to rebase on the first's `SetRow.lastSet` removal — pure churn.
- PR title: `fix(workouts): rest-overlay chrome cleanup + drop per-row hint, pre-fill from last session`.
- PR body must reference: PR #198 (Phase 22 PR-2 / Q5 / C3 — body-slot architecture preserved), PR #159 + #193 (the role-swap incidents we are unwinding), this WIP entry, and the new PLAN.md Phase 23 section (added in the same PR).
- PLAN.md: append a new `## Phase 23 — Active Workout: rest-overlay chrome + hint-text removal` section with the condensed post-merge form (3-5 bullets per CLAUDE.md PLAN.md Lifecycle: "After merge → condense the step to 3-5 bullet points"). Add a row to the progress table.

**Out of scope**
- Per-exercise summary chip (UI/UX-critic proposed; user rejected — keep the surface bare).
- Weight unit mid-cycle conversion (separate concern).
- Warmup-as-first-class-data-model refactor (still in Active Backlog from Phase 22).
- Routine-start pre-fill path changes (untouched — `addExercise` only).
