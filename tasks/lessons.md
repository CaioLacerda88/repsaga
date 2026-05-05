# Lessons Learned

Patterns and mistakes to avoid. Reviewed at session start.

---

## 2026-04-10: Placeholder cleanup needs a whole-repo grep, not per-file surgery

**Mistake:** Round 1 QA flagged one `(placeholder)` instance in `assets/legal/privacy_policy.md` section 1 and the orchestrator briefed tech-lead to fix exactly that one line (plus the `docs/` mirror). Tech-lead did exactly what was asked. Round 2 QA (against live Supabase) then found FIVE more instances the first pass had missed: privacy_policy section 11, terms_of_service sections 11+12, docs/index.md, and both docs/ ToS mirrors — plus a `[JURISDICTION]` template token in the ToS governing-law clause. A cleanup pass that should have been one PR became a two-commit amend cycle.

**Root cause:** Round 1's QA agent cited one `file:line` in its report and the orchestrator trusted the citation to be exhaustive. It wasn't. The agent had grepped one search term in one file, not the whole pattern class across the whole repo.

**Lesson:** Placeholder-cleanup tasks are inherently whole-repo. Before declaring them scoped, always run `Grep(pattern: "placeholder|\[[A-Z_]+\]|TODO|TBD", path: repo)` across `.md` (and any other text-based user-facing asset directory). The orchestrator must do this grep itself when writing the fix brief — do NOT delegate enumeration to a single-file QA citation.

**Rule:** For any "clean up X across legal/docs/copy" task: before dispatching the fix agent, the orchestrator runs a pattern grep across all user-facing asset directories and includes the complete match list in the brief. QA agents cite representative instances, not exhaustive ones — treat their reports as "at least these", not "only these".

---

## 2026-04-09: context.go() vs context.push() on Flutter web with GoRouter

**Mistake:** Changed all `context.go('/workout/active')` to `context.push()` to "ensure back-stack entry" for Android back button. This broke 3 E2E tests that rely on page reload.

**Root cause:** On Flutter web, after `page.reload()`, GoRouter re-initializes. The auth redirect cycle (loading → splash → home) means the user always lands on `/home` after reload, regardless of the original URL. The E2E tests then navigate back to the workout via the `_ActiveWorkoutBanner`. With `push()` from inside a ShellRoute to a top-level route, GoRouter 13.x web behavior is unreliable.

**Lesson:** `PopScope(canPop: false)` is sufficient for Android back button — it intercepts ALL back presses. No back-stack entry is needed when `canPop` is false. Don't change `go()` to `push()` for routes outside a ShellRoute unless you verify E2E reload behavior.

**Rule:** Navigation routing changes (`go`↔`push`, route restructuring) are FLOW changes, not visual-only. Always run E2E suite when routing logic changes.

---

## 2026-04-09: Use systematic debugging for CI/E2E failures

**Mistake:** Investigated E2E failure with ad-hoc grep/read cycles, taking multiple rounds to narrow down. Should have used `superpowers:systematic-debugging` skill from the start.

**Lesson:** When CI fails, immediately: (1) read the actual error output, (2) check what changed vs the last green run, (3) form a single hypothesis, (4) test minimally. Don't scatter-search hoping to stumble on the answer.

---

## 2026-04-09: PostgreSQL ALTER TYPE ADD VALUE must be in its own transaction

**Mistake:** Added `ALTER TYPE muscle_group ADD VALUE 'cardio'` and then INSERT rows referencing `'cardio'` in the same migration file. Supabase wraps each migration in a transaction, so the INSERT failed with `ERROR: unsafe use of new value "cardio" of enum type muscle_group (SQLSTATE 55P04)`.

**Root cause:** PostgreSQL does not allow using a newly added enum value in the same transaction where it was created. The value must be committed first.

**Lesson:** Always put `ALTER TYPE ... ADD VALUE` in its own migration file, separate from any DML that references the new value. This ensures the enum change commits before it's used.

## 2026-05-04: CHECK violations need a writer audit, not a single-site patch

**Mistake:** Migration 00050 patched ONE of three functions writing to `exercise_peak_loads` (the one in the immediate stack trace — `record_session_xp_batch`). Shipped, deployed to hosted, immediately re-hit `code=23514` on the user's phone because `_rpg_backfill_chunk` (called from `RpgRepository.runBackfill()` on app launch) ALSO writes peak_loads with no `weight > 0` guard. A second migration (00051) was needed to install a BEFORE-INSERT trigger on the table.

**Root cause:** Reviewer + tech-lead + orchestrator all focused on the function in the failure's stack trace and missed that the SAME constraint had three writers. The architectural smell ("guard duplicated at every writer") was visible in the code but not flagged because the audit scope was set by the failing function, not by the violated constraint.

**Lesson:** When patching a CHECK constraint failure, the workflow is:

1. Identify the failing constraint name from the error.
2. Run `npx supabase db dump --linked --schema public > /tmp/hosted.sql` and grep `INSERT INTO <table>|UPDATE <table>` to find every function writing to the constrained table.
3. For each writer, classify the (constraint, writer) pair as confirmed-bug / latent-bug / safe.
4. Patch every confirmed-bug pair in the same migration.
5. **If 3+ writers exist for one constraint, install a BEFORE-INSERT trigger backstop** so a future fourth writer cannot reintroduce the bug. Trigger overhead is negligible for low-frequency tables; the architectural guarantee is worth it.
6. Cross-reference Dart RPC callers + grants to `authenticated` role for diagnostic functions that could be hit externally even if not on the production hot path.

The trap is "the failure must be in the function the trace points at." Stack traces show the firing site, not the design flaw — and a constraint with 3+ writers is the design flaw, not any individual writer.

---

## 2026-05-04: Adding `Semantics(identifier: ...)` for e2e requires `container: true` + `explicitChildNodes: true`

**Mistake:** PR #152 commit 7 added `Semantics(identifier: 'set-row-state-...')` around the `_SetRowFrame` to expose row state to Playwright. CI passed all unit/widget/build/analyze gates locally and on first push. On the second CI push the e2e job blew up with 13 failures — all variants of "click landed on the wrong widget." The page snapshot showed every interactive element inside an exercise card had collapsed into ONE giant `flt-tappable role="group"` — the header InkWell, the icon buttons, the column headers, and every set row's stepper buttons + checkboxes — all with one merged `aria-label` listing every text label in the card. Tapping the header opened the "Enter weight" dialog instead of the detail sheet.

**Root cause:** A bare `Semantics(identifier: ...)` in Flutter does NOT create a new semantic boundary — it merges its info into whatever ancestor Semantics it finds. Without `container: true`, the new node has no boundary; without `explicitChildNodes: true`, descendant Semantics nodes also fold into the merged group. The result is all descendants AND siblings of the wrapper become one tappable region in the AOM, intercepting clicks on every nested interactive widget.

**Why CI on the FIRST push didn't catch it:** Bisecting CI runs revealed the merge was already happening in commit 7 (211e34d). The first push had a flake-prone test failure that masked this — the e2e job timed out on a different test before reaching most of the affected ones. Push #2 (after the reviewer-fix commit `995a3a6` shipped) gave the e2e suite a clean run that exposed all 13 failures at once.

**Lesson:** Whenever you add a `Semantics(identifier: ...)` to a widget for e2e selector exposure (the project's `flt-semantics-identifier=` selector pattern), ALWAYS pair it with `container: true, explicitChildNodes: true`. Both flags are load-bearing. The first creates the semantic boundary so the identifier can be addressed in isolation; the second prevents descendant Semantics from being silently absorbed.

**Rule:** For any new `Semantics(identifier: ...)` in `lib/`:
```dart
return Semantics(
  identifier: 'my-test-id',
  container: true,           // REQUIRED — creates a hard boundary
  explicitChildNodes: true,  // REQUIRED — keeps descendant Semantics distinct
  child: ...,
);
```

Existing widgets that wrap interactive descendants and DO NOT need to be addressable in isolation should also consider these flags if e2e tests start interacting with their descendants. A widget test that asserts `find.bySemantics(...)` will not catch this — only an e2e click flow against the rendered DOM tree will.

---

## 2026-05-04: When deleting a UI widget that has e2e selectors, audit ALL spec files for the selector — not just the file you "expect" to be affected

**Mistake:** PR #152 commit 2 deleted `_PrChip` (the inline PR badge inside the reps cell) when rewriting `set_row.dart`. I correctly removed `pr_chip.dart`'s widget reference and updated `set_row_test.dart`. I did NOT grep for `CELEBRATION.prChip` (the e2e selector) across ALL `.spec.ts` files. Result: `rank-up-celebration.spec.ts:816` was still asserting that selector. The e2e suite caught it, but only because someone (commit 7's qa-engineer) added another e2e change that triggered a fresh full e2e run. If we had skipped commit 7's e2e additions, the stale assertion would have shipped to main and broken the next person's PR.

**Lesson:** When deleting OR renaming a UI widget that exposes a Semantics identifier to e2e:
1. Grep ALL of `test/e2e/specs/**/*.ts` for the selector name (the `XXX.yyyChip` style key from `selectors.ts`) BEFORE deleting.
2. Grep the selector's underlying string (`flt-semantics-identifier="..."` value) too — defensive, in case any test inlines it.
3. Update or remove every test that depended on the selector. If the widget is replaced (not just deleted), retarget the assertion to the new selector — don't just delete the test (the assertion may still cover meaningful behavior).
4. Remove the dead key from `helpers/selectors.ts`.

A `git grep` on the selector name takes 5 seconds. Skipping it costs an entire CI cycle.

---

## 2026-05-04: New e2e tests must verify their PR seed assumptions against `global-setup.ts`

**Mistake:** PR #152 commit 7 added a new e2e test at `personal-records.spec.ts:264` (`should show standing-PR row identifier after completing a PR-breaking set`) using a smokePR user with a 40 kg baseline + 80 kg PR-breaker workout pattern. CI failed because the smokePR user's `global-setup.ts` seeds a 100 kg × 5 max-weight PR. 80 kg never beat the seed, so the row resolved as `completedNonPr` (no gold chrome) and the new `set-row-state-standing-pr` selector was never emitted.

**Lesson:** Whenever a new e2e test asserts on PR-related behavior using an existing test user, FIRST read `test/e2e/global-setup.ts` and find the user's `seedPRData()` (or equivalent seed) call. Pick weights/reps that genuinely BEAT the seed, not just beat each other. If the seed values are inconvenient for the test scenario, either:
- Use a different user that has no seed (e.g., `e2e-rpg-fresh`), OR
- Add a new dedicated test user in `fixtures/test-users.ts` + `global-setup.ts` with the seed YOU want.

Don't assume an "untouched" baseline. Every smokePR/smoke-* user has at least some seed data per the project's parallel-test isolation rule.


---

## 2026-05-04: Semantics(container/explicitChildNodes) is needed at EVERY tap-merging boundary, not just one place

**Mistake:** PR #152 fix attempt #2 (commit `cd8c079`) added `container: true, explicitChildNodes: true` to `_SetRowFrame`'s identifier Semantics after CI surfaced 13 e2e failures. CI passed widget/unit/format/analyze locally; pushed. Run #3 still showed 12 e2e failures — same family of "click intercepted by merged tappable group" but now manifesting in DIFFERENT widgets: the exercise card header InkWell merged with the column-header Text widgets (SET/WEIGHT/REPS), AND the predicted-PR `_PredictedPrUncheckedMark`'s `GestureDetector` emitted its own `role=button` inside the `_DoneCell`'s `workout-set-done` identifier scope. Two more semantic-merge boundaries needed the same treatment that the row frame got.

**Root cause:** The fix-#2 mental model was "the row identifier needs the boundary." The deeper truth: EVERY interactive widget that emits a `Semantics(identifier:)` for e2e — and EVERY widget whose descendants include a tap-handling gesture — is a potential merge boundary. A single fix at the row-frame level handles the row-vs-row merge, but does nothing for header-vs-column-header merging or for inner-gesture-vs-outer-identifier merging. Each is a distinct boundary needing its own pair of flags.

**Lesson:** When you find a Semantics-merge bug, do not stop at "the immediate site." Audit:

1. EVERY `Semantics(identifier: ...)` in the PR's diff. Each MUST have BOTH `container: true` AND `explicitChildNodes: true`. The pair is non-negotiable for e2e-addressable identifiers.
2. EVERY widget with a `Semantics(label: ...)` whose descendants include `InkWell.onTap`, `GestureDetector.onTap`, `Checkbox`, or any other implicitly-tappable widget. The label-bearing node either needs the same pair of flags OR the inner gesture needs `excludeFromSemantics: true` (or `excludeSemantics: true` on a wrapping `Semantics`).
3. EVERY `Text` widget whose VISUAL purpose is decorative table-header / grid-label and that has no role in the accessibility narrative. Wrap in `ExcludeSemantics` to prevent it from being absorbed into ancestor tappable groups via Flutter's implicit upward semantic merging.

**Rule:** When a `Semantics(identifier:)` test passes locally but fails in e2e click flows, the merging is happening at a boundary you did not patch. Search the SAME PR diff for OTHER candidate boundaries — header InkWells, column-header rows, decorative Text — and apply the same boundary discipline before pushing again.

---

## 2026-05-04: Identifiers must live on the actual tap target, not its container

**Mistake:** PR #152 wrapped `_DoneCell` in `Semantics(container: true, identifier: 'workout-set-done', label: ...)`. For the `Checkbox` case this worked — Flutter's Checkbox merges its tap action into the parent identifier node correctly. But the predicted-PR variant uses a custom `GestureDetector(onTap: ..., child: Container(...))` for the gold ◆ glyph. Without `excludeFromSemantics: true` on the gesture, Flutter exposed it as a separate `role=button flt-tappable` semantic node SITTING ON TOP of the parent identifier's bounding box, intercepting Playwright's clicks targeted at `[flt-semantics-identifier="workout-set-done"]`.

**Lesson:** A `Semantics(identifier:)` is queryable by Playwright but is NOT automatically a tap target — it is a labeled wrapper. The ACTUAL tap target is whatever descendant has the gesture handler. If that descendant emits its own AOM button node, Playwright clicks resolve to the parent identifier's bounding box and then hit the descendant button instead — which intercepts because it has its own `flt-tappable` listener. The identifier scope is broken.

**Rule:** When you wrap a custom interactive widget in `Semantics(identifier:)` for e2e:

- If the inner widget has its own gesture (GestureDetector, InkWell with onTap, Checkbox, etc.), set `excludeFromSemantics: true` on the gesture so it does NOT emit a competing button node. Hit-testing keeps working — `excludeFromSemantics` only affects the AOM, not pointer-event routing.
- The parent `Semantics(identifier:, label:, container: true, explicitChildNodes: true)` becomes the SOLE addressable AOM node and Playwright clicks land in its bounding box without interception.
- Add a widget test that walks the semantics tree and asserts NO competing `SemanticsAction.tap`-bearing descendant node carries the same accessibility label as the identifier scope. This catches the regression before CI burns an e2e cycle.

**Rule:** Identifier ⊃ tap target, not the other way around. The identifier is the addressable handle; the tap target is the structural element underneath. They must coincide spatially (same bounding box), and there must be NO separate AOM node mediating between them.
