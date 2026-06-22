# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

RepSaga — a gym training app for logging workouts, tracking personal records, and managing exercises.

**On session start:** Read `PROJECT.md` Quick Reference (progress table + current state) and `docs/WIP.md` (in-flight work). Only read full PROJECT.md sections relevant to the current task.

## Commands

```bash
export PATH="/c/flutter/bin:$PATH"

flutter pub get              # install dependencies
make gen                     # code generation (Freezed/json_serializable)
make gen-watch               # code generation in watch mode
make format                  # dart format .
make analyze                 # dart analyze --fatal-infos
make test                    # flutter test
make build-android-debug     # android debug APK (Gradle/Kotlin compile check)
make ci                      # full pipeline: format + gen + analyze + test + android-debug-build (~3-5 min)

flutter run -d android       # run on Android
flutter run -d chrome        # run on Chrome (for Playwright e2e)
```

## Code Style

- `const` constructors wherever possible
- No hardcoded colors or text styles — use `AppTheme` from `core/theme/`
- Extract widgets when build method exceeds ~50 lines
- Import our exceptions with prefix when Supabase types clash: `import '...' as app;`
- When fixing a bug that matches a known cluster (see PROJECT.md §0 Cluster Ledger), reference the cluster name in the inline comment so future agents can grep it. If the fix uncovers a NEW recurring pattern, write a 6-line `cluster_*.md` auto-memory entry + add a row to PROJECT.md Cluster Ledger in the same PR.
- Commit format: `feat|fix|refactor|test|docs|ci|chore(scope): description`
- Scopes: `auth`, `exercises`, `workouts`, `progress`, `profile`, `core`, `theme`, `ci`, `rpg`, `gamification`, `test`

### Exercise content translation coverage rule

Post-Phase-15f, exercise display text (`name`, `description`, `form_tips`) lives in `exercise_translations` keyed by `(exercise_id, locale)` — never on `exercises` itself. Any migration that inserts a default exercise (`is_default = true`) MUST be paired with INSERT INTO `exercise_translations` rows for **both `'en'` and `'pt'`** for every new slug — either in the same migration file or in a sibling migration in the same PR. No default exercise ships without full en+pt coverage.

Default-exercise INSERTs MUST include the `slug` column in their column list with a literal slug value per tuple — slug is the join key for translations and is `NOT NULL` on the table.

CI enforces this via `scripts/check_exercise_translation_coverage.sh` (recognizes both the canonical `(VALUES (slug, ...)) JOIN exercises e ON e.slug = v.slug` pattern and the implicit `SELECT ... FROM exercises e` backfill pattern). Violation fails the pipeline.

## Testing

### Test user-visible behavior, not wiring

Every test must assert a user-perceptible outcome — what the user sees, what dismisses, what stays. "The function was called" is not a behavior; it's a wiring trace. If the only thing that breaks the test is removing the call site, the test isn't pinning the contract.

Examples:
- WRONG: `verify(() => notifier.showSnackBar()).called(1);`
- RIGHT: `expect(find.byType(SnackBarCountdown), findsNothing);` (after the duration elapses)

The May 2026 SnackBar fix-wave (PR #214) is the cautionary tale: source-grep + widget tests pinned that `persist: false` was set in the call site, but no test ever asserted the SnackBar actually disappeared at duration, nor that the inner drain rectangle ever had non-zero width. The bug hid until on-device verification. See PROJECT.md §0 Cluster Ledger → `persist-eats-duration` / `pump-duration-masks-forward`.

### Conventions

- Structure: `test/unit/`, `test/widget/`, `test/e2e/`, `test/fixtures/`
- Mock Supabase with `mocktail` — never hit real backend in unit tests
- Test factories in `test/fixtures/test_factories.dart`
- `testWidgets` for widget tests, `test` for unit tests

### E2E Tests (Playwright) — Local Execution

**Prerequisites check (run all before writing tests):**
```bash
export PATH="/c/flutter/bin:$PATH"

# 1. Supabase containers must be running (auth, db, rest, storage)
docker ps --format '{{.Names}} {{.Status}}' | grep supa | grep -v healthy && echo "WARNING: unhealthy containers"

# 2. If containers are down:
npx supabase start

# 3. Flutter web build must be fresh (from your current branch!)
git branch --show-current          # verify you're on the right branch
flutter build web                  # rebuilds build/web/ from current code

# 4. E2E deps installed
cd test/e2e && npm install && cd ../..
```

**Running tests:**
```bash
cd test/e2e

# Run full regression suite (all 145 tests)
FLUTTER_APP_URL= npx playwright test --reporter=list

# Quick smoke check only (~68 tests tagged @smoke)
FLUTTER_APP_URL= npx playwright test --grep @smoke --reporter=list

# Run a single feature file:
FLUTTER_APP_URL= npx playwright test specs/auth.spec.ts

# Run a specific test by line number:
FLUTTER_APP_URL= npx playwright test "specs/auth.spec.ts:16"
```

**Key details:**
- `FLUTTER_APP_URL=` (empty) overrides `.env.local` → Playwright auto-serves `build/web/` via custom Node.js static server on port 4200
- **Env auto-swap**: Global setup injects local Supabase credentials into `build/web/assets/.env` so the Flutter app connects to the same Supabase instance the tests use. No manual `.env` swap needed.
- Global setup creates test users via Supabase Admin API → requires local Supabase running
- Global teardown deletes test users → idempotent, safe to rerun
- Screenshots on failure: `test/e2e/test-results/`
- Config: `test/e2e/playwright.config.ts`
- **CI vs local**: The root `.env` has hosted Supabase (production). `test/e2e/.env.local` has local Supabase. Global setup handles the swap automatically.

### E2E Conventions (must follow for all new/modified tests)

**File structure:** Feature-based files in `test/e2e/specs/`. One file per feature area (auth, exercises, workouts, routines, etc.). Never create `smoke/` or `full/` directories — use tags instead.

**Tagging:** Smoke tests (quick CI gate) use `test.describe('Name', { tag: '@smoke' }, () => { ... })`. Regression-only tests have no tag. Run smoke: `--grep @smoke`. Run all: no filter.

**Naming:**
- Describe blocks: feature name (`'Exercises'`, `'Workout logging'`). No "smoke"/"full" suffix.
- Tests: always start with `should`. Bug IDs parenthesized at end: `test('should show error snackbar (BUG-003)')`.

**User isolation:** Each describe block has a dedicated test user. Inline `TEST_USERS.xxx` directly in `beforeEach` — no `const USER` aliases (prevents collisions in merged files). New features needing isolated state require a new user in `fixtures/test-users.ts` + `global-setup.ts`.

**Selectors:** All in `helpers/selectors.ts`. Use Playwright `role=TYPE[name*="..."]` selectors (accessibility protocol), NOT CSS `flt-semantics[aria-label="..."]` (Flutter 3.41.6 uses AOM, not DOM attributes). For SnackBar text, always use `.first()` (Flutter renders two DOM elements per SnackBar). For search inputs, use `.last()` on `toBeVisible` assertions (Flutter renders two `<input>` elements).

**Text input:** Use `flutterFill()` from `helpers/app.ts`, NOT `page.fill()`. Flutter CanvasKit's hidden `<input>` proxy requires real keyboard events. `page.fill()` uses synthetic events that Flutter ignores.

**Adding a new test:**
1. Place in the appropriate `specs/<feature>.spec.ts` file
2. Add `{ tag: '@smoke' }` on the describe block if it's a CI gate test
3. Use an existing test user if the describe block already has one, or create a new user+describe block
4. Follow naming: `test('should ...')`
5. Add selectors to `helpers/selectors.ts` — never inline magic strings
6. Run locally: `FLUTTER_APP_URL= npx playwright test specs/<feature>.spec.ts`

## Development Team (Agent Workflow)

**All implementation is done by specialized agents, not the main conversation.** The main conversation coordinates and delegates.

### Team

| Agent           | Role                                                         | Writes Code | Model  |
| --------------- | ------------------------------------------------------------ | ----------- | ------ |
| `tech-lead`     | Architecture, implementation, bug fixes, migrations          | Yes         | Opus   |
| `qa-engineer`   | Test strategy, unit/widget/e2e tests, Playwright             | Yes         | Opus   |
| `devops`        | CI/CD pipelines, GitHub Actions, releases                    | Yes         | Sonnet |
| `reviewer`      | Code review, quality checks                                  | Read-only   | Opus   |
| `product-owner` | Market research, competitor analysis, feature priorities     | Read-only   | Sonnet |
| `ui-ux-critic`  | Design critique, anti-generic-AI aesthetics                  | Read-only   | Opus   |

> **Model note:** `tech-lead` ran on Fable until 2026-06; Fable access is paused
> (see anthropic.com/news/fable-mythos-access), so it now runs on Opus. Do not
> re-introduce a `model: fable` override — resuming a Fable-pinned agent fails at
> spawn. The agent frontmatter (`.claude/agents/tech-lead.md`) is already set to Opus.

### How it works

**The main conversation orchestrates agents directly.** It dispatches specialists, runs CI, and manages PRs. No intermediate orchestrator layer.

### Development Flow

Each PROJECT.md step follows this pipeline. **No step is skippable.**

1. **Plan** — Read PROJECT.md §0 + the relevant phase section (or §2 Active Backlog if picking up follow-up work). Dispatch `product-owner` + `ui-ux-critic` (if user-facing).
   - **Boundary-trigger ripple check.** When the change crosses one of: public method signature (sync→async, params, return type) · provider's emitted state shape · RPC, migration, or repository contract · symbol rename/removal · route/guard restructure — dispatch `Explore` BEFORE any code with this template:
     > *Find every caller / reader / test / l10n key / E2E selector touching `<symbol>` across `lib/`, `supabase/`, `test/`. Group by feature. Flag any provider that re-emits state derived from this, any caller that assumes synchronous behavior, and any E2E test whose selector depends on the symbol.*
     Output the inventory in `docs/WIP.md` as a "Boundary inventory" section ABOVE the implementation checklist. Implementation can't start until that section is filled. The async-caller-broke-snackbar cluster (PROJECT.md §0) is the canonical motivation.
   - Small fixes that don't cross those boundaries skip this step.
2. **WIP** — Write checklist in `docs/WIP.md` before any code.
3. **Implement (TDD)** — `tech-lead` writes code WITH unit/widget tests. Test-first when possible. Behavior-not-wiring (see Testing section). Run `dart format .` + `dart analyze` after each change.
4. **Design review** (if UI) — `ui-ux-critic` reviews. Generic → revise.
5. **Verify before PR** — Orchestrator runs `superpowers:verification-before-completion` skill: fresh `make ci` (or format + analyze + test), reads full output, confirms 0 failures. No "should pass" — evidence only. Re-read PROJECT.md acceptance criteria against the diff.
6. **Open PR** — only after verification gate passes. PR body **must** include `**QA pass pending — final coverage + E2E run after code review.**` so reviewer knows not to wait on QA before commenting.
7. **Code review** — `reviewer` flags issues. Scope: code structure, correctness, anti-patterns, missing edge cases. Reviewer also flags test-coverage holes BUT doesn't dictate the test design — that's QA's call in step 8. `tech-lead` fixes → reviewer re-engages → loop until reviewer signs off.
8. **QA gate (final)** — `qa-engineer` reviews the post-review article:
   - Writes the tests for any coverage holes the reviewer flagged (against the post-review code, so no churn).
   - **E2E (always):** Verify no selectors/text strings broke; update `helpers/selectors.ts` if needed. New tests go in existing `specs/<feature>.spec.ts` files — follow E2E Conventions below.
   - **E2E (new/changed user flows):** Write/update E2E tests in the appropriate `specs/` file, run full E2E suite locally. **Navigation changes (go↔push, route restructuring) count as flow changes** even if no UI text changed.
   - **E2E (visual-only / no flow change):** Selector impact assessment only.
   - Removes or updates stale E2E tests affected by the change.
   - Bugs found → back to `tech-lead` → reviewer re-engages briefly → QA re-runs from top.
9. **Visual verification (if UI)** — Required whenever a phase ships a new or rewritten user-facing surface. SKIPPED for backend-only / token-only / pure-bugfix phases.
   - Build the Flutter web app from the post-QA HEAD (`flutter build web`).
   - Boot the app (Playwright auto-serves `build/web/` on port 4200 when `FLUTTER_APP_URL=` is empty, OR use Chrome DevTools MCP if interactive inspection is needed).
   - Sign in as each relevant test user from `test/e2e/fixtures/test-users.ts`. For a phase that changes the Saga screen, that's at minimum: a foundation user (steady-state data) AND a fresh user (day-zero). Other screens pick the analogous data states.
   - For each user, screenshot the affected surface at three viewports: **320dp, 360dp, 412dp** (covering smallest Android, baseline, and large-phone breakpoints). Use `mcp__plugin_playwright_playwright__browser_resize` + `browser_take_screenshot`.
   - Compare the screenshots side-by-side with the `docs/phase-<N>-mockups.html` mockup for that surface. The mockup is the locked design target — flag any drift loudly (color values off, spacing wrong, ellipsis not firing, etc.).
   - Surface the comparison in the PR thread (drag-and-drop the screenshots, OR `gh pr comment` with paths) so the merger can eyeball them. Don't bury this in a transcript.
   - Bugs found → back to `tech-lead` → re-render → re-screenshot. Don't merge until the visuals match the mockup.
10. **Verify after QA + visuals** — `make ci` + E2E green + visuals match. Final check before merge.
11. **Ship** — QA OK + CI green + visuals match → squash merge.
12. **Apply migrations** — After merge, check if the phase added/modified SQL migrations (`supabase/migrations/`). If so, apply them to the hosted Supabase instance with `npx supabase db push` (or link + push). Verify the schema matches what the code expects before moving on. During QA/testing, always confirm that any new migrations have been applied to the environment under test.
13. **Close WIP** — Remove WIP section, condense phase in PROJECT.md §4 (see lifecycle below).

### Pipeline exceptions

- **Docs-only PRs:** no reviewer, no QA. Admin-merge once fast checks pass (existing `docs_only_pr_merge` memory rule).
- **Tooling / CI / `.claude/` hooks changes:** reviewer reads, QA skipped (no user-visible surface).
- **Hotfixes for live incidents:** reviewer + QA collapse into one expedited pass, neither skipped.

### Document discipline (no stray files)

Transient agent output (plans, working specs, design notes from superpowers like `writing-plans` or `brainstorming`) → `docs/WIP.md`. Removed when the branch merges.

Shipped + architectural content → `docs/PROJECT.md` (active phase full-spec in §3, post-merge collapsed into §4 Completed Phases — 3-5 bullets).

Long-lived external references that don't fit a phase narrative (legal pages, design subsystems, glossaries, recovery runbooks) → `docs/` flat — no nested `phase/` / `date/` / `superpowers/` folders.

Cross-session lessons and bug clusters → auto-memory `cluster_*.md` entries indexed in MEMORY.md. The in-project grep handle goes into PROJECT.md §0 Cluster Ledger.

Do NOT create long-form spec files under `docs/superpowers/`, `tasks/`, or any other nested folder. The May 2026 cleanup removed multiple stray spec files that should have lived as WIP-then-PROJECT.md condensations.

### Library API lookups (Context7)

`tech-lead` has Context7 MCP tools (`mcp__plugin_context7_context7__resolve-library-id` + `query-docs`) for looking up versioned, official docs of third-party packages. Use it deliberately:

**Use Context7 first when:**
- Writing code that touches a third-party package's API surface (Riverpod 3, Freezed 3, GoRouter 17, `supabase_flutter`, Hive, `in_app_purchase`, `connectivity_plus`, `fl_chart`, `mocktail`, etc.).
- Migrating to a new major version of a pinned dep (the package's CHANGELOG + Context7 docs together are the canonical source).
- Adopting a brand-new package — `resolve-library-id` first, then `query-docs` against the version we're considering.

**Read source directly (skip Context7) when:**
- Debugging Flutter SDK / Dart SDK internals (engine behavior, `RenderObject` constraints, `SemanticsNode` plumbing, animation pipeline). The framework source under `/c/flutter/packages/flutter/lib/...` is the ground truth — Context7 docs cover the public API, not engine internals.
- Looking at our own RepSaga code — `Grep` and `Read` are faster than any external lookup.
- Postgres / SQL — official PG docs are still better than Context7's coverage of niche extensions.

**Fallback chain when Context7 has thin coverage:**
1. Context7 `query-docs` (versioned, official, fast)
2. Official package README on pub.dev (still authoritative)
3. Targeted web search (last resort — easy to land on outdated blog content)

The May 2026 SnackBar fix-wave was correctly source-read territory (Flutter framework internals). But Phase 14 offline (`connectivity_plus`, `hive`), Phase 16 paywall (`in_app_purchase`), and any future Riverpod 3 patterns are Context7 territory. See auto-memory `feedback_context7_when_to_use.md`.

### Debugging Protocol

When ANY non-obvious failure occurs during the pipeline (CI red, E2E failure, unexpected behavior, review-found bugs):

1. **IMMEDIATELY deploy `tech-lead` with `superpowers:systematic-debugging`** — no ad-hoc guessing, no trial-and-error. Non-obvious bugs waste massive time when investigated without systematic analysis.
2. **Phase 1 (Root Cause):** Read the actual error output. Reproduce. Check what changed. Trace data flow backward from the symptom. **Dispatch the tech-lead agent to investigate architecture-level root causes** — don't just grep and patch.
3. **Phase 2 (Pattern):** Find working examples in the codebase. Compare broken vs working. **If the suspected fault is in third-party package usage** (not framework / engine internals), check Context7 docs for the pinned version BEFORE reading our own codebase — stale training-data assumptions are the slowest path to a wrong hypothesis.
4. **Phase 3 (Hypothesis):** Form ONE specific theory ("X causes Y because Z"). Test minimally — one variable at a time.
5. **Phase 4 (Fix):** Fix root cause, not symptom. Verify with tests.
6. **If 3+ fix attempts fail:** Stop. Question the architecture. Discuss with user before continuing.

**This applies to the orchestrator, not just agents.** When investigating CI failures, E2E regressions, or review feedback — follow the phases, don't ad-hoc grep around hoping to stumble on the answer. The instinct to "just try something" wastes context window and time. Invest in understanding first.

### PROJECT.md Lifecycle

PROJECT.md is the single source of truth for all project specs. It's structured for **token-efficient reading** — agents read the Quick Reference first, then only their relevant section.

**During development** (step is active):
- The step has a **full detailed spec** in PROJECT.md: acceptance criteria, file plans, schema, UX details
- Agents read the Quick Reference + their active step section — never the entire file
- WIP.md tracks real-time progress during implementation

**After merge** (step is done):
- **Condense** the step to 3-5 bullet points: what was built, key files, test count, notable decisions
- Move the full spec to git history — it's in the PR/commit, not needed for future agents
- Update the progress table status to DONE with PR number(s)
- Remove the WIP.md section for that step

This prevents PROJECT.md from growing unbounded. Completed steps are summaries; only active/future steps have full specs.

### WIP Tracking (`docs/WIP.md`)

**Every agent that changes code MUST follow this protocol:**

1. **Before writing code:** Read the relevant PROJECT.md step section, then write a checklist in `docs/WIP.md` with:
   - Task name and branch name
   - Reference to the source definition (e.g., "Per PROJECT.md Step 12", "Per PROJECT.md Phase 13")
   - Checkable items for each change to make
   - Files to modify/create
2. **During implementation:** Check off items as they're completed (`- [x]`)
3. **After merge:** Remove the completed section from `docs/WIP.md` and condense the PROJECT.md step

This keeps the coordinator (main conversation) informed of progress and ensures agents don't drift from specs. If `docs/WIP.md` doesn't exist, create it.

### Handoff Protocol

**When delegating to an agent:**
- Provide the PROJECT.md step number and specific sub-tasks
- List files the agent must read before starting
- State what to build, which existing patterns to follow
- Include `export PATH="/c/flutter/bin:$PATH"` for Flutter/Dart commands
- Include the progress reporting instruction (see below)
- **Run code-writing agents in FOREGROUND** so the user sees progress in real-time. Background mode hides the agent's progress lines — only use it for read-only research agents where step-by-step visibility is not needed.

**Agent progress reporting (include in every agent prompt):**
```
PROGRESS REPORTING: Before each major step, output a brief status line so the
orchestrator can track progress. Format: "## [Step N/Total] Description"
Example: "## [1/4] Reading test files..." → "## [2/4] Fixing selectors.ts..."
Output these as plain text between tool calls. Keep them to one line.
```

**When an agent completes work:**
- Agent summarizes: files created/modified, decisions made, known issues
- Coordinator runs `make ci` to verify before handing to next agent
- Next agent in pipeline reads the changed files before starting their work

**When reviewing a PR (reviewer / qa-engineer):**
- Read all changed files, not just the diff summary
- Check against PROJECT.md requirements for that step
- Verify tests cover the acceptance criteria
- Flag real issues only — skip style nitpicks (that's what `make format` and `make analyze` are for)

### Context Hygiene

The main conversation must stay under 60% context usage. When approaching 60%:

1. **Update `docs/WIP.md`** with current state: what's done, what's in progress, what's next, any decisions or blockers
2. **Compact** — use `/compact` to free context
3. After compacting, re-read `docs/WIP.md` to restore working state

This prevents context rot — losing track of in-flight work after auto-compaction. Agents should also keep context lean: delegate research to sub-agents, avoid reading entire large files when a section suffices.

### Agent Permissions

- Code-writing agents need Bash for `flutter pub get`, `dart format`, `dart analyze`, `flutter test`
- Read-only agents (reviewer, ui-ux-critic, product-owner) never get Write/Edit tools
- QA engineer needs Playwright MCP tools for e2e tests

## Git Flow

- `main` is protected — everything through PRs
- Branches: `feature/step<N>-description` or `fix/description`
- Squash merge to main, delete branch after
- Releases: semver `v0.1.0`, `v0.2.0`, etc.
- No direct commits to main, no force pushes, no skipping CI
