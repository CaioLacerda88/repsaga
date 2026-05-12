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
- [x] **Code** — `lib/features/workouts/ui/active_workout_screen.dart` `_ActiveWorkoutBody.build`: gate `floatingActionButton` and `bottomNavigationBar` on `!widget.showRestTimerOverlay`. AppBar untouched.
- [x] **Doc** — Replace the existing PR-2 C3 dartdoc block (L109-131) with a brief note: "Rest overlay covers the body slot only by PR #198's C3 design. To complete the 'overlay over everything' contract (Phase 23 D1), FAB + FinishBottomBar are conditionally hidden while `showRestTimerOverlay` is true. AppBar stays — its X is the in-rest discard affordance."
- [x] **Widget test** — new `test/widget/features/workouts/ui/active_workout_rest_chrome_visibility_test.dart`:
  - `should hide AddExerciseFab when rest timer is active`
  - `should hide FinishBottomBar when rest timer is active`
  - `should restore FAB and Finish after rest timer stops`
  - `should keep AppBar discard X reachable during rest` (re-confirms `active_workout_appbar_discard_during_rest_test.dart` contract is preserved)
- [x] **E2E test** — new describe block in `test/e2e/specs/workouts.spec.ts` tagged `{ tag: '@smoke' }`: `Rest overlay chrome`:
  - `should hide add-exercise FAB and finish bar while rest timer is visible` — start a workout, complete a set to trigger rest, assert `WORKOUT.addExerciseFab` and `WORKOUT.finishBtn` are `toBeHidden()`, dismiss rest, assert both are `toBeVisible()` again.
  - Add the new test user `smokeRestChrome` to `test/e2e/fixtures/test-users.ts` + `test/e2e/global-setup.ts` per CLAUDE.md E2E conventions (one user per describe block).
  - Update `test/e2e/helpers/selectors.ts` if needed — confirm `WORKOUT.addExerciseFab` and `WORKOUT.finishBtn` selectors exist; add semantic identifiers in the widget if either is missing (`Semantics(identifier:)` with pair-rule per PR #152 lessons). (Both selectors already exist — see `WORKOUT.addExerciseFab` + `WORKOUT.finishButton`.)

**F1.2 — Back-press priority chain (rest → dismiss; loading → discard; else → discard)**
- [x] **Code** — `lib/features/workouts/ui/active_workout_screen.dart` outer `PopScope.onPopInvokedWithResult` (L152-158): replace with the priority chain. `timerState` is already in scope at the parent `build` (L78); use directly.
- [x] **Doc** — Inline dartdoc on the `onPopInvokedWithResult` callback explaining the three branches and pointing to D2/D3. One paragraph. Include "Phase 23 D2: rest is the dominant on-screen affordance; back-press dismisses rest first. Loading overlay branch (D3) preserves existing discard route — loading has its own Cancel CTA."
- [x] **Widget test** — extend `test/widget/features/workouts/ui/active_workout_appbar_discard_during_rest_test.dart` (or new sibling `active_workout_back_button_priority_test.dart`):
  - `should stop rest timer on Android back press without showing discard dialog`
  - `should fall through to discard dialog when rest timer is inactive`
  - `should fall through to discard dialog when loading overlay is active even if rest timer is also active`
  - `should stop rest timer exactly once when back press fires during rest` (no double-stop / no spurious state listener re-entrance — covers risk #2 in the register)
- [x] **E2E test** — extend the new `Rest overlay chrome` describe block in `workouts.spec.ts`:
  - `should dismiss rest timer when Escape (browser back analog) is pressed` — Flutter web maps `Escape` to PopScope; same code path as Android back. Start a workout, trigger rest, `await page.keyboard.press('Escape')`, assert rest scrim is `toBeHidden()` AND discard dialog is `not.toBeVisible()`.
  - `should show discard dialog when Escape is pressed with no rest timer active`
  - Note in test comment: Android-native back press is not Playwright-reachable; widget tests own the deeper PopScope contract.

### Fix 2 — Hint removal + pre-fill on add-exercise

**F2.1 — Strip hint logic from `SetRow`**
- [x] **Code** — `lib/features/workouts/ui/widgets/set_row.dart`:
  - Remove `_matchedLastSet()`, `_shouldShowHint()` methods.
  - Remove the three-branch hint slot block (L366-424) including the mobile-only `!kIsWeb` filler.
  - Remove the `lastSet` constructor parameter + field. Search the file for every remaining `widget.lastSet` reference and verify all callsites are dead.
  - Remove `package:flutter/foundation.dart` import iff no remaining `kIsWeb` reference (verify via grep before deleting).
  - Verify `previousSet` field (in-session N-1 copy-hint at L65) is UNTOUCHED — it's a separate concept.
- [x] **Doc** — Replace the L174-237 + L293-365 dartdoc blocks with a single short note: "Hint logic removed 2026-05-12 (Phase 23 D4). Pre-fill carries the anchor; the PR yellow marker carries the win signal. Removing the conditional hint slot eliminates the Flutter Web AOM role-swap mutation vector documented in the PR #159 / #193 incidents — the row Semantics tree shape is now fixed at render time."
- [x] **Widget test** — `test/widget/features/workouts/ui/widgets/set_row_test.dart`:
  - DELETE `group('ghost text (previous session hint)', …)` (~L335-404)
  - DELETE `group('match indicator (Pillar 1)', …)` (~L406-489)
  - DELETE the "Fix 3 — 0kg suppression" block (~L2182-2320; search `Fix 3 —`)
  - DELETE standing-PR + hint interaction tests (~L2808-2956)
  - Remove `lastSet:` from every remaining `SetRow(...)` construction in the file.
  - Add new test: `should not render any previous-session hint text` — pump a `SetRow` with a workout-exercise that has prior data via the notifier; assert `find.textContaining('Previous:')`, `find.textContaining('= last set')`, `find.textContaining('Anterior:')`, `find.textContaining('última série')` all return `findsNothing`. Cover both EN and PT locales (one test each).
  - Add new test: `row Semantics tree shape is stable across set completion` — pump the row, capture the Semantics tree (via `tester.getSemantics`), tap the done cell, capture again, assert the structural shape matches. Pins the AOM regression-removal directly.
- [x] **E2E test** — extend the existing `Personal records` describe block in `test/e2e/specs/personal-records.spec.ts` (no new user needed, reuse the existing PR-baseline user):
  - `should not show per-row previous-session hint in active workout (Phase 23)` — start workout, add exercise with prior data, assert the text `/Previous:|Anterior:|= last set|= última série/` is NOT visible anywhere in the exercise card region.
- [x] **E2E cleanup** — `test/e2e/specs/charter-c-exploratory.spec.ts` L1018-1034 `prevHintBefore` probe — leave the probe (exploratory diagnostics, returns 0 hits now) AND add an inline comment: `// Phase 23: per-row hint removed; probe kept for historical diagnostics, will report 0 hits.`

**F2.2 — Drop `lastSet:` arg at the `SetRow` callsite**
- [x] **Code** — `lib/features/workouts/ui/widgets/exercise_card.dart`: remove the `lastSet: lastSet,` arg in `_buildSetRows` (~L422) and the `index < lastSets.length ? lastSets[index] : null` lookup feeding it (~L404). Preserve the `lastSets` variable + lookup that drives `_onAddSet` pre-fill — still load-bearing.
- [x] **Doc** — short inline comment on the kept `lastSets` lookup: "Used only for `_onAddSet` pre-fill defaults (Phase 23 D6). Per-row hint consumption removed."
- [x] **Widget test** — `test/widget/features/workouts/ui/widgets/exercise_card_test.dart`:
  - Confirm the warmup-filter pre-fill tests (~L451-540) still pass unchanged (they exercise Add Set, not the hint).
  - Add new test: `should not render any per-row hint text` for an exercise with prior data (mirror of F2.1's row-level test but at the card level).

**F2.3 — Auto-seed set 1 on `addExercise`**
- [x] **Code** — `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` `addExercise`: instead of `sets: const []`, build a single seeded set:
  - Read `lastWorkoutSets[exerciseId]` (existing data plumbing).
  - Filter `setType != SetType.warmup` (Phase 22 Q2 warmup-filter convention).
  - Take the working-set with the lowest set_number (set 1's match); if absent, fall back to the LAST working set's values; if no working sets exist, fall back to the exercise's equipment defaults.
  - Bodyweight exercises: skip the weight value (keep `weight: null` or `weight: 0` per existing schema convention — verify in the model), use the prior reps; if no prior data, use equipment-default reps.
  - The new set must have: fresh client UUID, `set_number: 1`, `is_completed: false`, `set_type: SetType.working`.
  - Verify call-site separation: confirm `addExercise` is NOT reached on routine-start (routine-start uses `startRoutineWorkout` which has its own pre-fill at L340-370). Document the call-site map in a comment.
- [x] **Doc** — Dartdoc on `addExercise` explaining the auto-seed contract (D6), the fallback chain, and the warmup-filter convention pointer (Phase 22 Q2).
- [x] **Unit test** — `test/unit/features/workouts/providers/active_workout_notifier_test.dart` (or wherever `addExercise` is exercised today; create the group if absent):
  - `should auto-seed set 1 with prior working-set values when last session has matching exercise data`
  - `should auto-seed set 1 with last working-set values when prior set count < 1 match (fallback to last available)`
  - `should fall back to equipment defaults when no prior data exists for the exercise`
  - `should fall back to equipment defaults when prior session contained ONLY warmup sets (warmup-filter applied)`
  - `should auto-seed reps but not weight for a bodyweight exercise with prior data`
  - `should auto-seed equipment-default reps for a bodyweight exercise with no prior data`
  - `should generate a unique client UUID for the seeded set` (regression guard against any accidental shared-UUID bug)
  - `should set is_completed=false and set_type=working on the seeded set`
- [x] **Widget test** — `test/widget/features/workouts/ui/active_workout_screen_add_exercise_test.dart` (new or extend existing):
  - `should render exercise card with one pre-filled set immediately after add-exercise` — pump screen, trigger picker → pick exercise with prior data, assert exactly one set row exists with the expected weight/reps values.
- [x] **E2E test** — extend `test/e2e/specs/workouts.spec.ts` Workout logging describe block (or add a new sibling describe `Add exercise auto-seed`):
  - `should auto-seed set 1 with last session values when adding an exercise mid-workout` — seed user with a prior workout of bench press at 80kg×8 (use existing test fixture helpers), start a fresh quick workout, tap Add Exercise → pick bench press, assert the new exercise card has one set with the weight stepper showing `80` and the reps stepper showing `8`.
  - ~~`should auto-seed equipment defaults when adding an exercise with no prior data`~~ — covered at the widget level by `active_workout_screen_add_exercise_test.dart` (second test, '...equipment-default-filled set when no prior data exists'). Reproducing the same contract through the full E2E web pipeline would require seeding two prior workouts on the same user just to assert a deterministic equipment-default — the widget test already pins it cheaply.
  - New user `smokeAutoSeed` in `test-users.ts` + `global-setup.ts`. Reuse seeded prior-workout helpers from `seededFinishWorkoutUsers` pattern (verify the helper exists, otherwise add it). (Added `seedAutoSeedPriorWorkout` in `global-setup.ts`.)

**F2.4 — ARB key cleanup**
- [x] **Code** — `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb`: remove the `previousSet` key + `@previousSet` placeholders block, `matchedLastSet` key + its placeholders, and any `*Semantics` keys exclusively serving these strings (search both ARBs for `previous`, `matched`, `lastSet` to enumerate).
- [x] **Doc** — No inline doc needed for ARB deletes (the WIP entry + commit message carry the rationale).
- [x] **Build verification** — Run `make gen` after the ARB edits. The build will fail loudly if any Dart file still references the deleted keys — that's the test. Also run `dart analyze --fatal-infos` to surface dead references.
- [x] **E2E** — none for this item (ARB deletion is verified by F2.1's "no hint text visible" assertions).

### Cross-cutting

**Verification gate (must run before opening PR)**
- [x] Full `make ci` green: format + gen + analyze (--fatal-infos) + test + android-debug-build. 2601 unit/widget tests pass (+1 new identifier-transition test); android debug APK build succeeds.
- [x] E2E smoke gate on the three target spec files green: 26 passed (2026-05-12 post-fix run). All three previously-fragile PR tests + both new Phase 23 smoke describes pass.
- [x] **Cluster A — Escape vs PopScope on Flutter Web (root-caused 2026-05-12):** `PopScope.onPopInvokedWithResult` fires on `popRoute` system-channel events. On Flutter Web with GoRouter, browser `popstate` is routed via `MultiEntriesBrowserHistory.onPopState` into a `pushRouteInformation` message that the Router consumes by changing the route — the OUTGOING screen's PopScope callback is NEVER fired. Keyboard Escape is unwired entirely. Net: there is NO Flutter-Web-reachable path that fires the active-workout PopScope. **Fix:** keep the FAB+Finish-hide-during-rest contract (D1, observable via Skip button) at E2E; delete the two PopScope-priority-chain E2E tests (D2/D3) — those contracts are fully owned by the existing widget tests in `active_workout_back_button_priority_test.dart` via `tester.binding.handlePopRoute()`. File-header comment in `workouts.spec.ts` documents the convention so future test authors don't repeat the assumption.
- [x] **Cluster B — Flutter Web identifier-transition propagation hole (root-caused 2026-05-12):** The row's chrome rebuilt correctly post-completion (gold stripe + values + green checkbox + gold bracket all visible in the failure screenshot — proving the resolver returned `completedStandingPr` and the widget tree was correct), but the row's DOM element retained `flt-semantics-identifier="set-row-state-pending-pr"` from BEFORE completion. AOM-identifier-only mutations on a Semantics node whose role and structure stay identical do not always reach `setAttribute('flt-semantics-identifier', ...)` in the Flutter Web engine — the SemanticsNode is reused with the stale identifier string. **Fix:** wrap the row's identifier-bearing `Semantics(identifier:)` in a `ValueKey(rowStateId)` so the framework mounts a fresh SemanticsNode whenever the identifier value changes; the engine then emits the new attribute on a newly-created DOM element. The widget test `row Semantics emits the correct identifier across state transitions` (set_row_test.dart, F2.1 sibling) pins this contract at unit speed so a future refactor dropping the key surfaces immediately.
- [x] **Cluster C — H5 add-exercise undo SnackBar regression (root-caused 2026-05-12 during full E2E regression after cluster A/B fixes):** Phase 23 D6 made `ActiveWorkoutNotifier.addExercise` async (it now awaits `_seedFirstSetForAddedExercise` → `WorkoutRepository.getLastWorkoutSets`). The caller `_ActiveWorkoutBody._onAddExercise` was fire-and-forget — it called `notifier.addExercise(exercise)` without `await`, then immediately diffed the exercise list to find the new id, then showed the undo SnackBar. Pre-Phase-23 this worked because addExercise mutated state synchronously. Post-Phase-23 the diff reads state BEFORE the async seed-fetch resolves, finds no new id, and the SnackBar is never shown — silently breaking `workouts.spec.ts:1764 / :1786`. **Fix:** `await notifier.addExercise(exercise)` so the diff runs against post-mutation state. PR-3 review W1 explicitly warned about this exact failure mode ("the moment addExercise becomes async — and the snackbar's Undo would then silently delete an exercise the user never added"); Phase 23 broke the caller-side contract without updating the caller.
- [x] Full E2E regression locally — **237 passed, 62 @flaky skipped, 1 flaky** (workouts.spec.ts:762 EX-DETAIL-003 passed on retry, pre-existing intermittent flake unrelated to Phase 23). Run: `cd test/e2e && FLUTTER_APP_URL= npx playwright test --reporter=list`.
- [ ] On-device walkthrough on Samsung S25 Ultra (Android 16) — pending user verification on real device.

### Review-cycle revisions (2026-05-12)

Design review + QA gate returned five revisions. All landed in the same cycle
per CLAUDE.md "no deferring review findings" (Blockers / Importants / Nits all
fixed now; only the two genuinely architectural items deferred — both
documented in `PLAN.md` → Active Backlog → Architectural follow-ups, entries
`23-P-1` and `23-P-2`).

- [x] **REV-1 [UI/UX IMPORTANT #1]** — PT-BR `addExerciseUndo` copy aligned
  with EN structure. `lib/l10n/app_pt.arb` flipped from
  `"Exercício adicionado: {name}"` to `"{name} adicionado"`. `make gen`
  regenerated `app_localizations_pt.dart`. No test references the old
  prefix-then-name string (grep clean across `test/`). E2E selectors comment
  in `test/e2e/helpers/selectors.ts` updated — PT and EN now share the
  suffix-verb structure, so the `EN-ONLY ASSUMPTION` caveat in the
  `addExerciseUndoSnackBar` doc is gone.
- [x] **REV-2 [UI/UX IMPORTANT #3]** — AppBar merges into the abyss scrim
  during rest. `lib/features/workouts/ui/active_workout_screen.dart`
  AppBar `backgroundColor` becomes `AppColors.abyss` when
  `widget.showRestTimerOverlay` is true, else `null` (theme default —
  transparent). Inline comment cites D1 visual-merge rationale +
  REV-2 date. Widget test
  `test/widget/features/workouts/ui/active_workout_rest_chrome_visibility_test.dart`
  extended with the new
  `should set AppBar backgroundColor to abyss when rest timer is active`
  test (both directions pinned — active = `AppColors.abyss`,
  stopped = `null`).
- [x] **REV-3 [UI/UX NIT #6]** — `tapToDismiss` hint copy fully removed.
  `lib/features/workouts/ui/widgets/rest_timer_overlay.dart` drops the
  `SizedBox(height: 24)` + `ExcludeSemantics(Text(l10n.tapToDismiss, ...))`
  block, replaced with a one-liner explaining the removal. ARB keys
  deleted from `lib/l10n/app_en.arb` and `lib/l10n/app_pt.arb`; `make gen`
  regenerated the localization classes — `dart analyze --fatal-infos`
  confirms zero remaining consumers. Widget test
  `tapToDismiss visual hint is excluded from the AOM` rewritten as
  `tap-to-dismiss hint copy is removed (Phase 23 UI/UX REV-3)`,
  pinning both the absent Text AND the absent AOM label. The PR-5
  contrast pin (`PR-5 — tapToDismiss hint renders with alpha >= 0.55`)
  deleted — moot once the Text is gone; the new test's reason comment
  notes the PR-5 + PR #187 pins re-engage automatically if the Text is
  ever re-added. REV-3 supersedes the original NIT #4 (PT verb
  consistency) — removing the copy removes the verb-mismatch concern.
- [x] **REV-4 [QA risk #1]** — multi-row Semantics sibling stability.
  `test/widget/features/workouts/ui/widgets/set_row_test.dart` adds
  `sibling rows keep their identifier when one row transitions state
  (Phase 23 QA REV-4)` — pumps three sibling rows (pending-no-pr,
  pending-predicted-pr, completed-no-pr), records every
  `set-row-state-*` identifier in document order, transitions the
  middle row to `completedStandingPr`, asserts siblings 0 and 2 keep
  their pre-transition identifier (belt-and-suspenders on the per-row
  `ValueKey(rowStateId)` Cluster B fix). New helper
  `_collectRowStateIdentifiers(tester)` walks the SemanticsOwner to
  collect them in visit order; matches the helper style of the existing
  `_findRowStateIdentifier` single-row variant.
- [x] **REV-5 [QA risk #2]** — routine-start direct non-call assertion.
  `test/unit/features/workouts/providers/start_from_routine_test.dart`
  adds `routine-start path does NOT invoke addExercise auto-seed`. The
  test pumps a three-exercise routine and verifies
  `mockRepo.getLastWorkoutSets` is called EXACTLY ONCE (routine-start's
  own pre-fill) — never the 1 + 3 fan-out a hidden addExercise per-
  exercise call would produce. A defensive cross-pin asserts the state
  contains exactly the three routine exercises in order, catching any
  duplicate from a stray addExercise pass.

**Verification re-run after review-cycle revisions**

- [x] `dart format .` — 508 files, 0 changed.
- [x] `dart analyze --fatal-infos` — No issues found.
- [x] `flutter test` — 2639 unit/widget tests pass. (Second pass after a
  transient Hive-timing flake on first run; second run was deterministic
  green, exit 0.)
- [x] Targeted re-run on the four files touched by REV-2 / REV-3 / REV-4 /
  REV-5 — all 103 selected tests pass including
  `should set AppBar backgroundColor to abyss when rest timer is active`,
  `tap-to-dismiss hint copy is removed`,
  `sibling rows keep their identifier when one row transitions state`,
  and `routine-start path does NOT invoke addExercise auto-seed`.
- [x] `flutter build apk --debug --no-shrink` — `Built build\app\outputs\flutter-apk\app-debug.apk`.
- [x] PLAN.md Active Backlog updated with `23-P-1` (seeded-set provenance
  cue) and `23-P-2` (H5 add-exercise undo SnackBar widget coverage) —
  the two architectural follow-ups deferred to v1.1 per the spec.

**Post-mortem (handoff continuity, 2026-05-12)**

The original tech-lead session that implemented REV-1..REV-5 died
silently after staging all 13 file edits and the WIP.md updates but
before committing or pushing. A follow-up orchestrator dispatch found
the branch at `8770f05` with the working tree fully populated and the
WIP.md verification gate already marked green. The handover tech-lead
verified the working tree against the REV-1..REV-5 spec line-by-line
(every revision present and correct in source + tests + docs), re-ran
`dart format` (clean), `dart analyze --fatal-infos` (clean), and
`flutter test` (success=true, exit 0 on second pass — the same
transient Hive-timing flake the original session reported reproduces
here, second run deterministic green). The five commits were then
created in the logical chunks the original spec called for. No code
changes were needed during the handover — purely a continuity action
to land the work the previous session had completed but not committed.

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
