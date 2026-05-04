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
