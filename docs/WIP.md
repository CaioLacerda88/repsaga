# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

# Phase 33 — Pre-Launch Quality Sweep — Stage 1: Discovery

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dispatch 5 read-only specialist audit agents in parallel; assemble their returned findings into `docs/pre-launch-audit.md`; commit and open the 33-discovery PR. Output: one canonical findings doc that the Phase 33 triage gate consumes.

**Architecture:** Each audit agent receives a self-contained prompt with the finding-block format contract. Agents return their section content as their final message (no file writes). Orchestrator concatenates all 5 returns into `docs/pre-launch-audit.md`, renumbers findings globally (`finding-001`, `finding-002`, …) for cross-referencing during triage, and commits via a docs-only PR.

**Tech Stack:** Agent tool (subagent dispatch with `run_in_background: true`), git/gh CLI, plain markdown. No source-code changes during this stage.

**Spec reference:** `docs/PROJECT.md` §3 → Phase 33 — Pre-Launch Quality Sweep → Stage 1.

**Branch:** `feature/phase-33-discovery`

---

## Files

- **Create:** `docs/pre-launch-audit.md` — assembled findings doc; lives on `main` for the duration of Phase 33; deleted in the final Phase 33 cleanup PR.
- **Modify:** `docs/WIP.md` (this file) — check items off as work lands; section removed when the 33-discovery PR merges.

No `lib/` / `test/` / `supabase/` writes in this stage.

---

## Checklist

- [x] Task 1 — Branch + scaffold audit doc
- [x] Task 2 — Dispatch 5 audit agents in parallel (background)
- [x] Task 3 — Receive returns + validate finding-block format
- [x] Task 4 — Assemble `docs/pre-launch-audit.md` (concat + global renumber + severity-summary table)
- [x] Task 5 — Commit + push + open PR
- [x] Task 6 — Post severity-counts summary to user (handoff to Stage 2 triage)

**Stage 1 outcome (2026-06-01):** 66 numbered entries across 5 sections (65 severity-counted + 1 verification-only). Severity totals: 0 CRITICAL / 25 IMPORTANT / 33 NICE-TO-HAVE / 7 PARK. `docs/pre-launch-audit.md` assembled and committed via 33-discovery PR (#290).

**Stage 2 outcome (2026-06-01):** Triage gate walked 25 IMPORTANT in 3 chunks (PR 33a/33b group → PR 33c → PR 33d/33e/33f group) + batch-reviewed 33 NICE-TO-HAVE. Dispositions:

- **21 IMPORTANT → fix wave** across PR 33a (4) / 33b (4, incl. finding-010 moved from 33e) / 33c (9) / 33d (3) / 33e (1).
- **4 IMPORTANT downgraded → PARKED** (finding-006 / 007 / 008 build-method refactors per non-goals rule; finding-040 empty-session guard E2E per 32g platform-untestable note).
- **11 NICE-TO-HAVE folded** into adjacent fix PRs at near-zero marginal cost (3 → 33a, 3 → 33b, 3 → 33c, 1 → 33d, 1 → 33e).
- **22 NICE-TO-HAVE → PARKED** to PROJECT.md §2 → Phase 33 audit deferrals with concrete revisit-conditions.
- **PR 33f CLOSED** post-triage (both flagged findings parked).

Audit doc stamped with triage dispositions table; park rationale + revisit-conditions written to PROJECT.md §2 → Phase 33 audit deferrals. 33-triage PR lands these artifacts; Stage 3 (Fix wave) starts after merge — first PR is **33a (Security)** per the locked order.

---

## Task 1 — Branch + scaffold audit doc

**Files:** Create `docs/pre-launch-audit.md` (skeleton).

- [ ] **Step 1: Create branch from latest main**

```bash
git checkout main
git pull --ff-only
git checkout -b feature/phase-33-discovery
```

Expected: `Switched to a new branch 'feature/phase-33-discovery'`.

- [ ] **Step 2: Scaffold the audit doc**

Use the Write tool to create `docs/pre-launch-audit.md` with this content:

````markdown
# Pre-Launch Audit (Phase 33)

> Findings assembled from 5 parallel read-only specialist agents.
> Each finding has a stable `finding-NNN` identifier across all sections.
> Triage gate (Stage 2) stamps each `→ PR 33x` or `→ PARKED`.
> This doc is deleted in the final Phase 33 cleanup PR.

**Status:** Stage 1 (Discovery) — pre-triage.

## Severity summary

| Section | CRITICAL | IMPORTANT | NICE-TO-HAVE | PARK | Total |
|---|---|---|---|---|---|
| §A — Code review | _pending_ | _pending_ | _pending_ | _pending_ | _pending_ |
| §B — Security | _pending_ | _pending_ | _pending_ | _pending_ | _pending_ |
| §C — Wiring-trace test candidates | _pending_ | _pending_ | _pending_ | _pending_ | _pending_ |
| §D — E2E gap matrix | _pending_ | _pending_ | _pending_ | _pending_ | _pending_ |
| §E — Deletion candidates | _pending_ | _pending_ | _pending_ | _pending_ | _pending_ |
| **TOTAL** | _pending_ | _pending_ | _pending_ | _pending_ | _pending_ |

## Finding-block reference

Each finding follows this format:

```
### finding-NNN — <one-liner>
- File: `path/to/file.dart:LINE` (or "(N files)" for batch findings)
- Current: <observed behavior>
- Recommended: <change>
- Severity: CRITICAL | IMPORTANT | NICE-TO-HAVE | PARK
- Suggested home: PR 33x | PARK | adjacent
- Cluster ref (optional): <cluster-name>
```

## §A — Code review

_Pending agent A1 return._

## §B — Security

_Pending agent A2 return._

## §C — Wiring-trace test candidates

_Pending agent A3 return._

## §D — E2E gap matrix

_Pending agent A4 return._

## §E — Deletion candidates

_Pending agent A5 return._
````

- [ ] **Step 3: Verify scaffold is on disk**

```bash
ls -l docs/pre-launch-audit.md
git status --short
```

Expected: `docs/pre-launch-audit.md` exists as untracked + `docs/WIP.md` shows as modified.

---

## Task 2 — Dispatch 5 audit agents in parallel (background)

**Files:** None modified — agents return content as messages.

Dispatch all 5 agents in **one message** with 5 parallel `Agent` tool calls, each with `run_in_background: true`. The Agent tool's parallel dispatch is the spec-mandated execution model. Returns arrive via notification as each agent completes.

The 5 prompts below are reproduced verbatim. **Do not edit them mid-dispatch** — if a prompt has a defect, kill all running agents (TaskStop), fix the prompt, re-dispatch the full batch.

- [ ] **Step 1: Dispatch A1 — Code-audit (`reviewer` agent)**

Prompt:

```
You are conducting a Phase 33 pre-launch audit for RepSaga (Flutter +
Supabase gym tracker with RPG progression). Your scope: ALL of `lib/`
across features/auth, features/exercises, features/workouts,
features/personal_records, features/routines, features/profile,
features/weekly_plan, features/rpg, plus core/ and shared/widgets/.

READ-ONLY investigation. Do NOT modify any source files. Do NOT write
files at all. Return your full §A section as your final message — the
orchestrator will assemble the audit doc.

Context to read first (in order):
- `docs/PROJECT.md` §0 (header + Cluster Ledger) — current state + named
  bug patterns to flag-match against
- `docs/PROJECT.md` §3 Phase 33 — depth target + severity criteria
- `CLAUDE.md` — code style, testing rules ("Test user-visible behavior,
  not wiring"), project conventions; the memory rules referenced inline
  in CLAUDE.md (feedback_* and cluster_*) are the rule set to flag-match
  against

Then sweep `lib/` for:

1. **Logic gaps** — branches that can't be reached, sealed-union arms
   without coverage, providers that don't invalidate downstream state,
   async methods whose callers don't await (cluster
   `async-caller-broke-snackbar`), missing PopScope on routes that need
   it
2. **Dead code** — orphan files (no imports), unused exports, commented-
   out blocks, dead branches in switch/if chains
3. **Files too large** — anything > 600 lines where responsibilities
   split obvious; flag with concrete refactor suggestion
4. **Anti-patterns** — `supabase.from()` direct calls in providers/UI
   (must be repository-layer), `setState()` in a widget that re-watches
   a provider, missing `const` on stateless widgets, hardcoded colors or
   text styles instead of `AppTheme`, raw `TextStyle(fontFamily:
   'Rajdhani')` instead of `AppTextStyles.*` (cluster
   `check_typography_call_sites`)
5. **Cluster matches** — search §0 Cluster Ledger entries; flag any
   match (e.g. `Semantics(identifier:)` without
   `container:true + explicitChildNodes:true`, `Align(widthFactor:)`
   with childless ColoredBox, async notifier method without caller-side
   await, JSONB field declared non-nullable in Dart while nullable in
   SQL)

Severity criteria:
- CRITICAL — broken golden flow, data corruption risk, RPG thesis
  violation (e.g. a logging path that produces zero XP silently),
  security-adjacent in lib/ (write the security finding here too, A2
  will independently cover the broader sweep)
- IMPORTANT — logic gap, anti-pattern that risks data loss or wrong
  state, cluster match
- NICE-TO-HAVE — file-too-large smell on stable code, refactor
  opportunity, deprecated import in non-fatal context
- PARK — opinion-shaped style preference, v1.1 territory

Output format — return one block per finding, locally numbered A-01,
A-02, …:

### finding-A-NN — <one-liner ≤ 70 chars>
- File: `path/to/file.dart:LINE` (or `(N files)` for batch findings —
  list paths in Current line)
- Current: <observed behavior + why it's a problem>
- Recommended: <specific change>
- Severity: CRITICAL | IMPORTANT | NICE-TO-HAVE | PARK
- Suggested home: PR 33b (deletes) | PR 33c (workout-flow) |
  PR 33d (RPG/share) | PR 33e (auth/profile) | PR 33f (residual) |
  PARK | adjacent
- Cluster ref (if applicable): <cluster-slug from §0 Ledger>

Return the assembled `## §A — Code review` heading + a one-paragraph
preamble stating "Surveyed N files; M findings; severity breakdown:
X CRITICAL / Y IMPORTANT / Z NICE-TO-HAVE / W PARK" + all finding
blocks in order CRITICAL → IMPORTANT → NICE-TO-HAVE → PARK.

If a severity bucket is empty, write "_No findings in this bucket._"
under the appropriate sub-heading. Completeness > brevity — flag
ambiguous items as NICE-TO-HAVE rather than skipping.
```

Dispatch parameters: `subagent_type: "reviewer"`, `run_in_background: true`, `description: "Phase 33 audit §A — Code review"`.

- [ ] **Step 2: Dispatch A2 — Security (`general-purpose` + /security-review)**

Prompt:

```
You are conducting the Phase 33 pre-launch security audit for RepSaga
(Flutter + Supabase). Your scope WIDENS PR 32b's targeted audit which
shipped 0 criticals across 21 RLS-scoped user-data tables + 4 Edge
Functions. This phase looks for everything 32b didn't cover.

READ-ONLY investigation. Do NOT modify any files. Return your full §B
section content as your final message.

Context to read first:
- `docs/PROJECT.md` §0 + Cluster Ledger
- `docs/PROJECT.md` §3 Phase 33 — severity criteria
- The PR 32b summary in PROJECT.md §4 to know what was already audited

You may invoke the `/security-review` skill if available — but DO NOT
let it gate your investigation. The skill is a complement, not a
replacement.

Scope checklist (cover every bullet; explicitly say "no finding" if a
bullet returns clean):

1. **Edge Function input validation** — for each function under
   `supabase/functions/` (`validate-purchase`, `rtdn-webhook`,
   `vitality-nightly`, etc.): check that every untrusted input (JWT
   claims, request body, query params, Pub/Sub message payload) is
   validated, typed, and bounded. Look for unbounded `JSON.parse`,
   missing length caps, missing format checks (UUID, email), trust
   of user-supplied identifiers without re-deriving from JWT.
2. **Signed-URL TTL audit** — `lib/features/profile/data/avatar_repository.dart`
   (and any other signed-URL issuer) — verify TTL is appropriate (avatar
   ships with 1yr; flag anything > 1yr on user-content; flag anything
   < 24h on rarely-refreshed paths if user-experience suffers).
3. **Deeplink hijack vectors** — `lib/main.dart` + `lib/app.dart` +
   GoRouter config — verify the OAuth callback scheme
   `io.supabase.repsaga://login-callback/` and any custom scheme aren't
   accepting arbitrary external state. Check `AndroidManifest.xml` for
   exported activities + intent filters.
4. **Dependency CVE scan** — run `flutter pub outdated --no-dev-dependencies`
   and `cd test/e2e && npm audit --omit=dev` (you cannot run shell
   commands — instead, read `pubspec.lock` and `test/e2e/package-lock.json`
   and cross-reference major versions against known-bad patterns or
   abandoned packages). Flag dependencies pinned to a major version
   behind current that have known CVEs.
5. **Bundle secrets re-sweep** — grep `lib/` for: anything matching
   `sk_live_`, `sk_test_`, `eyJ` (JWT prefix), `xoxb-` (Slack), bearer
   tokens, hardcoded service-role keys, GCP service account JSON,
   ANYTHING that looks like a credential in source. PR 32b confirmed
   `lib/` clean — re-verify on the current HEAD.
6. **New-table RLS sweep** — for each migration ADDED since PR 32b
   (00067 `workout_template_translations`, 00068 + 00069 avatar +
   private bucket, 00070 `get_workout_history_with_aggregates`, 00071
   `peak_load_per_body_part`): verify RLS policies exist, are
   user-scoped where appropriate, and that SECURITY DEFINER functions
   (if any) re-check `auth.uid()` before returning data.
7. **JWT verification on Edge Functions** — each function should verify
   the inbound JWT (or Pub/Sub JWT for `rtdn-webhook`) before doing
   anything stateful. Flag any path that processes user input before
   verifying.
8. **CORS configuration** — Edge Function CORS should be locked to the
   project's Supabase URL, not `*`.
9. **LGPD/GDPR posture** — any user-uploaded personal content (avatars,
   photos, IDs) must live behind signed URLs over PRIVATE buckets
   (per `feedback_data_protection_compliance`). Verify the avatar
   bucket flip from public→private (PR 32e / migration 00069) didn't
   leave stale objects accessible.
10. **Auth + session** — `lib/features/auth/` — verify PKCE flow is
    correct, refresh-token rotation works, no places where session
    state is persisted in plaintext outside Supabase's own secure
    storage.

Severity:
- CRITICAL — exploitable: SQL injection, missing RLS on a writable
  table, unverified JWT path on a stateful endpoint, plaintext
  credential in lib/, public bucket holding user-uploaded private
  content
- IMPORTANT — defense-in-depth gap, weak input validation that
  doesn't directly exploit but should be tightened, deps with known
  CVEs we can bump
- NICE-TO-HAVE — TLS/CORS lint, deps near end-of-life, log-message
  hygiene (PII potentially leaked to telemetry)
- PARK — theoretical, no clear attacker model in v1

Output format identical to §A but blocks numbered B-01, B-02, …
Heading: `## §B — Security`. Include one-paragraph preamble with
counts. Bucket findings CRITICAL → IMPORTANT → NICE-TO-HAVE → PARK.

If a checklist bullet returns clean, include a brief "Checklist
result" sub-section at the top of §B (above the finding blocks)
saying so per bullet — that way the triage gate knows you actually
verified, not skipped.
```

Dispatch parameters: `subagent_type: "general-purpose"`, `run_in_background: true`, `description: "Phase 33 audit §B — Security"`.

- [ ] **Step 3: Dispatch A3 — Wiring-trace test grep (`Explore` agent)**

Prompt:

```
You are running a mechanical wiring-trace-pattern grep across the
RepSaga test suite for Phase 33 pre-launch audit. Goal: surface tests
that assert call-site wiring instead of user-visible behavior — the
violation pattern CLAUDE.md's "Test user-visible behavior, not wiring"
rule and the cluster `pump-duration-masks-forward` were both written
to prevent.

READ-ONLY. Return §C content as your final message.

Context: read `CLAUDE.md` → Testing section. The May 2026 SnackBar
fix-wave (PR #214) is the cautionary tale — source-grep + widget tests
passed but no test asserted the SnackBar actually disappeared, so the
bug hid until on-device QA. CLAUDE.md A2 + cluster
`persist-eats-duration` / `pump-duration-masks-forward` are the rule
embodiment.

Mechanical patterns to grep across `test/unit/` + `test/widget/`:

Pattern 1: `verify(...).called(N)` — pure wiring trace. The test
asserts a mock was called but never asserts the user-visible
consequence. Use Grep tool with pattern `verify\(.*\)\.called` and
search the test file for any `expect(find` in the same test() block.
If none → candidate.

Pattern 2: `when(...).thenAnswer(...)` chains with no downstream
`expect(find...)` in the test body. The test stubs a return value but
never verifies the rendered output.

Pattern 3: tests that pass with zero `expect(find...)` or
`expect(find.byType(...)` assertions — they're either (a) pure unit
tests on functions (legitimate), (b) wiring-trace tests in disguise
(violation). Distinguish by checking if the test name matches a widget
behavior (e.g. "shows snackbar when X" = should have find.text).

Pattern 4: `tester.pump(Duration(...))` immediately preceded by
controller.forward() expectation but no rendered-output expectation —
the cluster `pump-duration-masks-forward`. Look for `pump(Duration` not
followed by `expect(find` within 5 lines.

For each candidate, output:

### finding-C-NN — <test name + violation type>
- File: `test/path/to/file.dart:LINE`
- Test name: `<the test('...', () => …)` label>`
- Pattern: 1 | 2 | 3 | 4
- Current snippet (≤ 10 lines): `<test body excerpt showing the
  violation>`
- Recommended: <specific rewrite — what `expect(find...)` should be
  added; if no behavior to assert exists, recommend deletion>
- Severity:
    - IMPORTANT if the test is on a high-traffic surface (workout flow,
      RPG XP path, share pipeline, finish coordinator, sync queue,
      profile avatar, weekly plan)
    - NICE-TO-HAVE if it's on a leaf surface or pure utility
- Suggested home: PR 33c | PR 33d | PR 33e | PR 33f | PARK

Important: many wiring-trace patterns are legitimate when the
behavior IS the side effect (e.g. a fire-and-forget analytics emission
test must `verify(.called)` because there's no UI consequence). For
those, EXCLUDE from your output — only flag tests where a real
behavior exists but isn't asserted.

Survey scope target: cover all files matching `test/unit/**/*.dart` +
`test/widget/**/*.dart`. State up-front the total file count surveyed
and the candidate count.

Output: `## §C — Wiring-trace test candidates` + preamble (counts) +
finding blocks in order. Use ONLY IMPORTANT and NICE-TO-HAVE
severities (Pattern 4 + Pattern 3 violations on critical surfaces are
IMPORTANT; everything else is NICE-TO-HAVE). No CRITICAL/PARK for §C.

Cap output: 80 finding blocks. If you find more, sort by surface-risk
and trim — note "+N additional candidates (lower-risk surfaces)
omitted, available on request".
```

Dispatch parameters: `subagent_type: "Explore"`, `run_in_background: true`, `description: "Phase 33 audit §C — Wiring-trace grep"`. Note: `Explore` agents specify search breadth — use `"very thorough"` in the prompt's metadata.

- [ ] **Step 4: Dispatch A4 — E2E coverage matrix (`qa-engineer` agent)**

Prompt:

```
You are building the Phase 33 pre-launch E2E coverage matrix for
RepSaga. Goal: identify gaps where a primary user flow or critical
error path has NO E2E spec covering it (golden-path E2E gaps are
launch-blocker IMPORTANT).

READ-ONLY. Return §D content as your final message.

Context to read first:
- `docs/PROJECT.md` §1 → Route Tree (GoRouter)
- `docs/PROJECT.md` §1 → Testing strategy section
- `CLAUDE.md` → E2E Conventions
- `test/e2e/specs/` — list every spec file + read each describe block
  header
- `test/e2e/helpers/selectors.ts` — known surface coverage
- `test/e2e/fixtures/test-users.ts` + `worker-users.ts` + `global-setup.ts`
  — known seeded states

Method:

Step 1. Build a list of every user-reachable screen from the route tree
+ the screens reachable through navigation actions (modals, sheets,
overlays). Source: GoRouter config in `lib/core/router/`. Include every
ShellRoute child + every full-screen route + every `showModalBottomSheet`
target + every `Navigator.push` destination.

Step 2. For each screen, enumerate primary actions (the user-intended
operations on that screen) AND error paths (network failure,
validation failure, empty state).

Step 3. For each (screen × action) and (screen × error-path) cell,
search `test/e2e/specs/` for a test that exercises it. Cross-reference
selectors in `helpers/selectors.ts` and `helpers/app.ts`.

Step 4. Cell-level status:
- COVERED — an existing test asserts the action/error path's
  user-visible outcome
- PARTIAL — a test reaches the screen but doesn't assert the
  action/error
- MISSING — no test reaches this surface

Step 5. Output a coverage matrix table FIRST, then finding blocks for
every MISSING or PARTIAL cell on a golden path.

Coverage matrix format:

| Screen | Action | Status | Existing test | Notes |
|---|---|---|---|---|
| /home | Tap routine card → /workout/active | COVERED | `workouts.spec.ts:42` | — |
| /home | Tap bucket chip → routine sheet | MISSING | — | Newly added in PR 32f |
| ... | ... | ... | ... | ... |

Finding-block severity:
- IMPORTANT — golden-path action/screen with MISSING coverage on a
  surface that ships in v1 (workout logging, finish flow, post-session
  cinematic, share, history, weekly plan, login, signup, paywall-
  adjacent)
- NICE-TO-HAVE — PARTIAL coverage on a golden path, OR MISSING coverage
  on an edge case (offline, slow network, expired session)
- PARK — MISSING coverage on a surface that ships post-v1 (paywall full
  flow, deeplinks, push notifications)

Each finding block:

### finding-D-NN — <surface + missing-action one-liner>
- Screen: `/route/path` (`lib/features/.../screen.dart`)
- Action / error path: <what's missing>
- Status: MISSING | PARTIAL
- Suggested test landing: `test/e2e/specs/<existing-file>.spec.ts`
  (add new test) or `test/e2e/specs/<new-file>.spec.ts` (new file
  needed)
- Suggested test name (per E2E Conventions): `should ...`
- Suggested user fixture: existing-from-`worker-users.ts` | new
  isolated user
- Severity: IMPORTANT | NICE-TO-HAVE | PARK
- Suggested home: PR 33c | PR 33d | PR 33e | PR 33f | PARK

Cap: 50 IMPORTANT + NICE-TO-HAVE findings (skip PARK individually —
just count them in the preamble). The matrix table itself is uncapped.

Output: `## §D — E2E gap matrix` + preamble (count of screens, actions
covered/missing, total finding blocks) + matrix table + finding blocks
in order.

Special instruction: if you find a flow where the existing E2E test
exists but is `test.skip(...)` with a TODO marker (e.g. the
26-tap-routing-e2e from PROJECT.md §2), surface it as a NICE-TO-HAVE
finding noting the existing skip — orchestrator may decide to unskip
or formally PARK during triage.
```

Dispatch parameters: `subagent_type: "qa-engineer"`, `run_in_background: true`, `description: "Phase 33 audit §D — E2E coverage"`.

- [ ] **Step 5: Dispatch A5 — Dead-code purge (`Explore` agent)**

Prompt:

```
You are running the Phase 33 pre-launch dead-code purge audit for
RepSaga. Goal: identify code, tests, l10n keys, and selectors left
behind from retired features that should now be deleted.

READ-ONLY. Return §E content as your final message.

Known retired features to specifically check for residue from (read
the §4 Completed Phases entries for context):

1. **PR 32h (#281)** — user-created exercise retirement.
   - Search `lib/` for: `CreateExerciseScreen`, `/exercises/create`
     route, `createExercise` repository method, `PendingCreateExercise`
     sealed-union variant, "create-exercise" / "create_exercise"
     identifiers
   - Search `lib/l10n/app_*.arb` for keys like `exerciseCreate*` that
     no longer have a render site
   - Search `test/e2e/helpers/selectors.ts` for any `EXERCISE_LIST.createFab`
     or `CREATE_EXERCISE.*` block still present
   - Search `test/e2e/specs/**` for `create-exercise.spec.ts` or
     similar
2. **Phase 30c (#265)** — `pr_celebration_screen.dart` retirement.
   - Search `lib/` for: `PrCelebrationScreen`, `pr_celebration_screen`,
     `/celebrate/...` routes, any imports of the deleted file
   - Search tests for: `pr_celebration_screen_test.dart` orphan, any
     `find.byType(PrCelebrationScreen)` references
3. **Phase 29.5 (#255)** — 5 retired mid-workout overlay widgets.
   - Search for retired overlay names (read the Phase 29.5 §4 entry
     for the specific 5 widget names) + their test files + ARB keys
4. **Phase 25 RPE drop (2026-05-15)** — RPE references that lingered.
   - Search `lib/features/workouts/` for `rpe` field references that
     no longer have a UI surface (the `ExerciseSet.rpe` model field is
     intentionally kept per the §2 v1.1-park note, but unused widget
     code referencing it should go)
   - Search `test/` for RPE-specific tests that no longer have a
     production code path

General sweeps:

5. **Unused l10n keys** — for each key in `lib/l10n/app_en.arb`, search
   `lib/` for the corresponding `AppLocalizations.of(context).<key>` or
   `l10n.<key>` reference. Flag keys with zero references. Also flag
   keys where the EN value is a placeholder ("TODO", "X") indicating
   incomplete localization.

6. **Orphan files** — files in `lib/` that no other file imports. Use a
   reverse-import scan. Common offenders: `_unused.dart` suffixed
   files, old generated `*.g.dart` siblings of since-renamed `*.dart`
   originals.

7. **Dead arms in sealed unions** — search for `sealed class` or
   `freezed` unions across `lib/`; for each, find the exhaustive
   switch sites; flag any union variant that's never instantiated
   (constructor never called) anywhere in `lib/` or `test/`.

8. **Orphan tests** — test files that test a class/widget no longer in
   `lib/` (the import either fails OR points to a deleted symbol). Run
   a name-only correspondence check.

9. **Stale CI scripts** — `scripts/check_*.sh` gates whose underlying
   pattern is no longer present in the code they police (i.e., the
   gate has nothing to check). Verify each `scripts/check_*.sh` is
   currently used by `.github/workflows/ci.yml` AND the violation
   pattern still exists in code.

For each finding:

### finding-E-NN — <one-liner>
- File(s): `path/to/file.dart` (or list multiple paths)
- Reason it's dead: <which retired feature / why no consumer exists>
- Recommended action: DELETE | DELETE + replace with `// removed:
  <reason>` comment (NEVER — per CLAUDE.md "Avoid backwards-compatibility
  hacks like adding // removed comments"; if you suggest a placeholder,
  the orchestrator will flag your finding)
- Severity:
    - IMPORTANT if the dead code references a deleted symbol AND will
      confuse future agents (e.g. orphan test importing a missing
      class)
    - NICE-TO-HAVE if it's an unused l10n key or orphan-but-harmless
      file
    - PARK if it's a `// TODO(post-launch)` marker that's intentional
- Suggested home: PR 33b (mechanical delete batch) | PR 33c/d/e
  if the delete pairs with a code-review fix on the same surface

Special instruction: GROUP related findings. If 9 ARB keys in app_en.arb
relate to the retired create-exercise flow, ONE finding-E-NN entry that
lists all 9 keys (with their line numbers) is more useful than 9
separate findings. Same for sibling orphan files (e.g.
`pr_celebration_screen.dart` + its `_test.dart` + its golden directory).

Output: `## §E — Deletion candidates` + preamble (count + total LOC
deletable) + finding blocks grouped by retired-feature source first,
then general sweeps. Severity ordering within each group.
```

Dispatch parameters: `subagent_type: "Explore"`, `run_in_background: true`, `description: "Phase 33 audit §E — Dead code"`.

- [ ] **Step 6: Confirm all 5 background tasks running**

After dispatching all 5 in a single message with 5 `Agent` tool calls, use `TaskList` to verify 5 tasks are queued/in-progress. Note the task IDs for reference.

Expected: 5 tasks visible in the list, status `in_progress` or `pending`.

**Do NOT poll for completion.** The Agent tool's `run_in_background` returns notifications when each task finishes. Continue to Task 3 only when all 5 have notified completion.

---

## Task 3 — Receive returns + validate finding-block format

**Files:** None modified — validation only.

- [ ] **Step 1: Wait for all 5 completion notifications**

When each agent completes, the harness emits a notification. Do not poll.

- [ ] **Step 2: For each agent return, validate format**

For each of A1–A5, check the returned content against the contract:

- Top-level heading is `## §X — <Section name>` matching the assigned section
- Preamble paragraph contains counts (CRITICAL / IMPORTANT / NICE-TO-HAVE / PARK)
- Every finding block has the 6 mandatory fields: File, Current, Recommended, Severity, Suggested home, (Cluster ref optional)
- Finding IDs are numbered locally (`finding-A-NN`, `finding-B-NN`, etc.)
- No agent wrote to a file directly (verify via `git status` — only `docs/WIP.md` + `docs/pre-launch-audit.md` should appear modified)

Use `TaskOutput` on each completed task ID to retrieve the return.

- [ ] **Step 3: If any agent's return is malformed, re-dispatch that agent only**

A "malformed" return = missing top-level heading, missing severity counts, finding blocks without all 6 required fields, OR the agent wrote to a file (contract violation).

If a re-dispatch is needed, use the same prompt verbatim plus this prefix:

```
Your previous response did not match the required format. Specifically:
<list specific defects>

Re-do the audit with the format strictly enforced. Same scope as before.
```

Re-dispatch as foreground this time (`run_in_background: false`) so you can see the structured response live.

---

## Task 4 — Assemble `docs/pre-launch-audit.md`

**Files:** Modify `docs/pre-launch-audit.md` — replace scaffold sections with assembled content + populate severity-summary table.

- [ ] **Step 1: Collect all 5 returns**

Have all 5 agent returns in scratch memory (their TaskOutput strings).

- [ ] **Step 2: Globally renumber findings**

Each agent locally numbered findings as `finding-A-01`, `finding-A-02`, ..., `finding-B-01`, etc. Globally renumber to a single sequence: `finding-001`, `finding-002`, ..., preserving section ordering (all A findings first by local order, then all B, then C, D, E).

Keep the section-letter prefix as a sub-tag: `finding-001 (A)` so triage and fix PRs can grep by section if needed.

Suggested renaming script (pseudocode):

```
counter = 1
for section in [A, B, C, D, E]:
    for finding in section.findings:
        old_id = finding.id  # e.g. "finding-A-03"
        new_id = f"finding-{counter:03d} ({section.letter})"
        # replace old_id → new_id in the section text
        counter += 1
```

You can do this inline in the Write tool call — no separate script needed. Just track the counter mentally as you concatenate.

- [ ] **Step 3: Compute severity-summary table**

Count findings per severity per section from the agent preambles + spot-verification of finding blocks. Fill the `_pending_` cells in the table at the top of `docs/pre-launch-audit.md`.

- [ ] **Step 4: Write assembled audit doc**

Use the Write tool to overwrite `docs/pre-launch-audit.md`. The new content is the scaffold's header + a populated severity-summary table + the five agent returns concatenated in order, with one `---` horizontal-rule separator between sections.

Template (replace every `<…>` placeholder with the real value at write time):

```
# Pre-Launch Audit (Phase 33)

> Findings assembled from 5 parallel read-only specialist agents.
> Each finding has a stable `finding-NNN (X)` identifier across sections.
> Triage gate (Stage 2) stamps each `→ PR 33x` or `→ PARKED`.
> This doc is deleted in the final Phase 33 cleanup PR.

**Status:** Stage 1 (Discovery) — pre-triage. Generated <today's date in YYYY-MM-DD>.

## Severity summary

| Section | CRITICAL | IMPORTANT | NICE-TO-HAVE | PARK | Total |
|---|---|---|---|---|---|
| §A — Code review | <count> | <count> | <count> | <count> | <total> |
| §B — Security | <count> | <count> | <count> | <count> | <total> |
| §C — Wiring-trace test candidates | 0 | <count> | <count> | 0 | <total> |
| §D — E2E gap matrix | 0 | <count> | <count> | <count> | <total> |
| §E — Deletion candidates | 0 | <count> | <count> | <count> | <total> |
| **TOTAL** | <sum> | <sum> | <sum> | <sum> | <grand-total> |

## Finding-block reference

<copy the Finding-block reference subsection from the scaffold>

---

<A1's full §A return — the entire content the A1 agent returned, with
its locally-numbered finding-A-NN identifiers replaced by globally-
numbered finding-NNN (A) per Step 2's renumber>

---

<A2's full §B return — globally renumbered to finding-NNN (B)>

---

<A3's full §C return — globally renumbered to finding-NNN (C)>

---

<A4's full §D return — globally renumbered to finding-NNN (D)>

---

<A5's full §E return — globally renumbered to finding-NNN (E)>
```

**Substitution rules:**
- `<count>` cells: integer from severity counts in each agent's preamble
- `<total>` per row: sum of that row's 4 severity cells
- `<sum>` in TOTAL row: column sum across all 5 sections
- `<grand-total>`: sum of all 4 severity columns in the TOTAL row
- Each `<X agent's full return ...>` block: the *entire* string the agent returned (heading + preamble + every finding block), with section-letter prefixes rewritten per Step 2

No `[bracketed-template-instructions]` should remain in the written file. If you can't grep `\[A[1-5]'s full` and get zero hits, the substitution wasn't complete.

- [ ] **Step 5: Sanity check — grep for malformed IDs**

```bash
grep -E "^### finding-[A-E]-[0-9]+" docs/pre-launch-audit.md
```

Expected: zero hits (all should be renumbered globally to `finding-NNN (X)`).

```bash
grep -cE "^### finding-[0-9]{3}" docs/pre-launch-audit.md
```

Expected: count matches the grand-total from the severity summary.

---

## Task 5 — Commit + push + open PR

**Files:** Stage `docs/pre-launch-audit.md` + `docs/WIP.md`.

- [ ] **Step 1: Stage + commit**

```bash
git status --short
```

Expected: only `docs/pre-launch-audit.md` (new file) + `docs/WIP.md` (modified) appear.

```bash
git add docs/pre-launch-audit.md docs/WIP.md
git commit -m "$(cat <<'EOF'
docs(phase-33): Stage 1 discovery — assembled audit findings

5 read-only specialist agents (code-audit, security, wiring-trace grep,
E2E coverage matrix, dead-code) ran in parallel and returned section
content; orchestrator assembled docs/pre-launch-audit.md with globally
renumbered finding-NNN (X) identifiers + severity-summary table.

Findings to be stamped → PR 33x | → PARKED by Phase 33 triage gate
(Stage 2). Doc deleted in final Phase 33 cleanup PR.

Per PROJECT.md §3 Phase 33 → Stage 1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds. If a pre-commit hook fails, investigate root cause + create a NEW commit (per CLAUDE.md commit safety protocol — never amend).

- [ ] **Step 2: Push branch + open PR**

```bash
git push -u origin feature/phase-33-discovery
```

```bash
gh pr create --title "docs(phase-33): Stage 1 discovery — pre-launch audit findings" --body "$(cat <<'EOF'
## Summary

- Phase 33 Stage 1 (Discovery) — assembled audit findings from 5 parallel read-only specialist agents
- New canonical doc: `docs/pre-launch-audit.md` (deleted in final Phase 33 cleanup PR)
- Findings stamped by Phase 33 triage gate (Stage 2) before any fix PR opens
- Zero source-code changes — docs-only

## Severity summary

[paste the severity-summary table from docs/pre-launch-audit.md]

## Spec reference

- `docs/PROJECT.md` §3 → Phase 33 — Pre-Launch Quality Sweep → Stage 1
- Decomposition rationale + non-goals: same section

## Next

Per PROJECT.md §3 Phase 33: Stage 2 — Triage gate (user-facing per-finding sign-off pass) → Stage 3 — Fix wave (33a → 33b → 33c → 33d → 33e → 33f → optional 33g/h).

## Test plan

- [x] Docs-only PR; no code changed
- [x] `grep -cE "^### finding-[0-9]{3}" docs/pre-launch-audit.md` returns the grand-total count
- [x] `git status --short` showed only `docs/pre-launch-audit.md` + `docs/WIP.md` pre-commit

Per `feedback_docs_only_pr_merge`: admin-merge eligible once fast checks pass — do not wait for E2E.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL returned. Note the PR number for the next step.

- [ ] **Step 3: Wait for fast checks; admin-merge once green**

Per `feedback_docs_only_pr_merge`, this is admin-merge eligible. Wait for format/analyze/test checks (skip E2E gate). Use `gh pr checks <PR#>` to monitor.

```bash
gh pr checks <PR#>
```

When fast checks pass:

```bash
gh pr merge <PR#> --squash --admin --delete-branch
```

---

## Task 6 — Post severity-counts summary + handoff to triage

**Files:** None.

- [ ] **Step 1: Post the severity-summary table back to the user**

After merge, surface the severity counts to the user with a one-paragraph framing:

> Phase 33 Stage 1 (Discovery) complete. `docs/pre-launch-audit.md` on main with N total findings. Severity breakdown: <table>. Stage 2 (Triage) next — I'll walk you through CRITICAL + IMPORTANT findings in chunks of 8–12, then batch-review NICE-TO-HAVE with default PARK + your spot-checks.

- [ ] **Step 2: Check off the entire Phase 33 Stage 1 section in this file**

Once the 33-discovery PR merges:

- Mark every `- [ ]` in this Phase 33 Stage 1 section as `- [x]`
- **Do not remove the section yet** — Phase 33 spans multiple PRs; remove only after the final cleanup PR per the lifecycle rule
- Update PROJECT.md §3 Phase 33 sub-PR table: `33-discovery` row status `PENDING` → `DONE` with the PR number

- [ ] **Step 3: Hand off to Stage 2 (Triage)**

Stage 2 is user-facing, doesn't need its own implementation plan. Orchestrator opens the triage gate by reading the assembled audit doc and walking through findings with the user per PROJECT.md §3 Phase 33 → Stage 2 protocol.

---

## Notes

- **Foreground vs background:** background dispatch is correct here because agents are read-only AND take 10–30 min each. The `feedback_agent_foreground.md` rule is specifically for code-writing agents where step-by-step diff visibility matters.
- **Parallel agent dispatch is safe here** because all 5 agents are read-only — no `git checkout`, no file writes. The cluster `parallel-agents-shared-working-tree-thrash` doesn't apply.
- **Re-dispatch policy:** if an agent returns malformed content, ONLY re-dispatch that agent — don't re-run the whole batch. The other 4 returns are still valid.
- **Token budget:** A1's `lib/` scan is the heaviest. If it returns a partial result citing context limits, accept partial coverage as long as severity counts are honest about it. The triage gate can choose to re-dispatch with narrower scope if needed.

---

# Phase 33 — PR 33a (Security) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Land 4 IMPORTANT + 3 folded NICE-TO-HAVE Edge Function defense-in-depth fixes per the Phase 33 audit. Pure backend hardening — zero changes in `lib/` or Dart `test/` (only `test/e2e/package-lock.json` for the ws CVE fix).

**Architecture:** Extract a shared `_shared/auth.ts` helper that handles JWT exp precheck + body-size cap. Call the helper at every stateful Edge Function entry (validate-purchase, delete-user, rtdn-webhook, vitality-nightly). Add per-function input validation (length clamps, regex, allow-lists). Bump the transitive `ws` dep in test/e2e via `npm audit fix`.

**Tech Stack:** Deno + std/http (Edge Functions), TypeScript, `@supabase/supabase-js@2`, npm (test/e2e deps).

**Spec reference:** `docs/pre-launch-audit.md` Triage stamps section, findings 026, 027, 028, 029, 030, 031, 033. Each finding's "Current" + "Recommended" lines are the source-of-truth for fix specifics.

**Branch:** `feature/phase-33a-security`

---

## Files

- **Create:** `supabase/functions/_shared/auth.ts` — `precheckJwtExp(jwt)` + `requireBodySize(req, max)` helpers
- **Create:** `supabase/functions/_shared/auth.test.ts` — Deno tests for the helper
- **Create:** `supabase/functions/delete-user/test.ts` — currently has NO test file (gap)
- **Modify:** `supabase/functions/validate-purchase/index.ts` (findings 026 / 027 / 028)
- **Modify:** `supabase/functions/validate-purchase/test.ts` — add input-validation tests
- **Modify:** `supabase/functions/delete-user/index.ts` (findings 028 / 030 / 031)
- **Modify:** `supabase/functions/rtdn-webhook/index.ts` (findings 028 / 033)
- **Modify:** `supabase/functions/rtdn-webhook/test.ts` — add size-cap + base64-cap tests
- **Modify:** `supabase/functions/vitality-nightly/index.ts` (finding 028)
- **Modify:** `supabase/functions/vitality-nightly/auth.test.ts` — extend or add new test file
- **Modify:** `test/e2e/package-lock.json` (finding 029 via `npm audit fix`)
- **Modify:** `docs/WIP.md` (this plan — checkmarks during implementation)

---

## Checklist

- [ ] Task 1 — `_shared/auth.ts` helper + Deno tests
- [ ] Task 2 — `validate-purchase` fixes (findings 026 / 027 / 028 partial)
- [ ] Task 3 — `delete-user` fixes (findings 028 partial / 030 / 031) + new test file
- [ ] Task 4 — `rtdn-webhook` fixes (findings 028 partial / 033)
- [ ] Task 5 — `vitality-nightly` size cap (finding 028 partial)
- [ ] Task 6 — `ws` CVE fix in test/e2e (finding 029)
- [ ] Task 7 — Verification (deno test + reviewer + qa-engineer) + commit + PR + admin-merge

---

## Task 1 — `_shared/auth.ts` helper + Deno tests

**Files:**
- Create: `supabase/functions/_shared/auth.ts`
- Create: `supabase/functions/_shared/auth.test.ts`

- [ ] **Step 1: Write failing tests in `_shared/auth.test.ts`** covering:
  - `requireBodySize`: returns null when Content-Length missing OR ≤ max; returns 413 Response when > max; correct status + JSON body
  - `precheckJwtExp`: returns `{ valid: false, reason: 'malformed' }` for non-JWT; `{ valid: false, reason: 'expired' }` for exp < now; `{ valid: true }` for exp > now; `{ valid: false, reason: 'malformed' }` for missing exp claim
  - Use the existing test pattern from `validate-purchase/test.ts` (std/assert + crypto.subtle.generateKey for JWT fixtures)

- [ ] **Step 2: Run tests — verify they fail (file doesn't exist yet)**

```bash
deno test --allow-net --allow-env supabase/functions/_shared/auth.test.ts
```

Expected: module-not-found error.

- [ ] **Step 3: Implement `_shared/auth.ts`** with this interface:

```typescript
// Body-size guard. Returns 413 Response if Content-Length > maxBytes;
// returns null if OK to proceed (no Content-Length is treated as OK —
// platform-level body ceiling still applies upstream).
export function requireBodySize(req: Request, maxBytes: number): Response | null;

// Cheap local JWT exp precheck. Does NOT verify signature (gateway already
// did) — just decodes payload and checks `exp` is in the future. Use
// before req.json() to short-circuit expired/malformed JWTs without
// paying the body-parse cost. Caller still needs to do full validity
// check via auth.getUser(jwt) for non-repudiation.
export function precheckJwtExp(jwt: string): { valid: boolean; reason?: 'malformed' | 'expired' };
```

`requireBodySize` returns the 413 with `{ error: 'Payload too large', maxBytes }`. Use CORS headers from the calling Edge Function (pass as a param or import shared).

`precheckJwtExp` splits on `.`, base64-url-decodes the payload, parses JSON, checks `typeof exp === 'number' && exp * 1000 > Date.now()`.

- [ ] **Step 4: Run tests — verify they pass**

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/auth.ts supabase/functions/_shared/auth.test.ts
git commit -m "feat(edge): shared auth helper — body-size cap + JWT exp precheck"
```

---

## Task 2 — `validate-purchase` fixes (findings 026 / 027 / 028 partial)

**Files:**
- Modify: `supabase/functions/validate-purchase/index.ts` (the `serve()` handler around line 384)
- Modify: `supabase/functions/validate-purchase/test.ts`

Audit-doc findings:
- **026** clamp `product_id` ≤ 128, `purchase_token` ≤ 4096, `source` ≤ 32 (+ allow-list `{'client','cron_reconcile'}`), UUID regex on `user_id`
- **027** move `getUser(jwt)` (or `precheckJwtExp` from Task 1) ahead of `req.json()`
- **028** call `requireBodySize(req, 32 * 1024)` at top of handler

- [ ] **Step 1: Write failing tests** in `validate-purchase/test.ts`:
  - `Deno.test('validate-purchase: 413 on >32KB body')` — synthesize a request with Content-Length: 40000, assert response.status === 413
  - `Deno.test('validate-purchase: 401 on expired JWT (no body parse)')` — JWT with exp in the past, assert 401 and that `req.json()` is NOT called (use a spy that throws if invoked)
  - `Deno.test('validate-purchase: 400 on product_id > 128 chars')` — assert 400 + error message references "product_id"
  - `Deno.test('validate-purchase: 400 on malformed user_id (non-UUID)')` — assert 400 + error references "user_id"
  - `Deno.test('validate-purchase: 400 on source not in allow-list')` — pass `source: 'attacker'`, assert 400

- [ ] **Step 2: Run tests — verify failures**

```bash
deno test --allow-net --allow-env supabase/functions/validate-purchase/test.ts
```

Expected: 5 new tests fail with "validation not implemented".

- [ ] **Step 3: Implement** at the top of the `serve()` handler:
  1. Call `requireBodySize(req, 32 * 1024)`; return its Response if non-null
  2. After Authorization-header check, call `precheckJwtExp(jwt)`; return 401 if invalid
  3. After `req.json()`, validate each field:
     - `if (typeof body.product_id !== 'string' || body.product_id.length > 128) return 400`
     - `if (typeof body.purchase_token !== 'string' || body.purchase_token.length > 4096) return 400`
     - `if (typeof body.source !== 'string' || body.source.length > 32 || !['client','cron_reconcile'].includes(body.source)) return 400`
     - `if (body.user_id !== undefined && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.user_id)) return 400`

- [ ] **Step 4: Run tests — verify pass**

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/validate-purchase/
git commit -m "feat(edge): validate-purchase input validation + JWT precheck + body cap (findings 026/027/028)"
```

---

## Task 3 — `delete-user` fixes (findings 028 partial / 030 / 031) + new test file

**Files:**
- Create: `supabase/functions/delete-user/test.ts` — no test file exists yet
- Modify: `supabase/functions/delete-user/index.ts`

Audit-doc findings:
- **028** size cap (4KB — body is tiny: 2 short strings)
- **030** move `getUser`/`precheckJwtExp` ahead of `req.json()`
- **031** validate `platform` against allow-list `{'android','ios','web'}` (coerce to `'unknown'` on mismatch); validate `app_version` regex `/^\d+\.\d+\.\d+(\+\d+)?$/` (silently strip on mismatch)

- [ ] **Step 1: Write failing tests** in new file `supabase/functions/delete-user/test.ts`:
  - `Deno.test('delete-user: 413 on >4KB body')`
  - `Deno.test('delete-user: 401 on expired JWT before body parse')` — spy on `req.json()` to confirm it's not called
  - `Deno.test('delete-user: platform not in allow-list coerces to "unknown" in audit row')`
  - `Deno.test('delete-user: app_version not matching regex stripped to null')`
  - `Deno.test('delete-user: valid platform/version pass through unchanged')`

Follow the test fixture pattern from `validate-purchase/test.ts` (fake service account, mocked Supabase admin client).

- [ ] **Step 2: Run tests — verify failures**

- [ ] **Step 3: Implement** in `delete-user/index.ts`:
  1. Call `requireBodySize(req, 4 * 1024)` at top of handler
  2. After auth-header check, call `precheckJwtExp(jwt)`
  3. Add `PLATFORM_ALLOW_LIST = ['android', 'ios', 'web']`; coerce out-of-list to `'unknown'`
  4. Add `APP_VERSION_RE = /^\d+\.\d+\.\d+(\+\d+)?$/`; null out non-matching values

- [ ] **Step 4: Run tests — verify pass**

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/delete-user/
git commit -m "feat(edge): delete-user JWT precheck + body cap + platform/version allow-lists (findings 028/030/031)"
```

---

## Task 4 — `rtdn-webhook` fixes (findings 028 partial / 033)

**Files:**
- Modify: `supabase/functions/rtdn-webhook/index.ts`
- Modify: `supabase/functions/rtdn-webhook/test.ts`

Audit-doc findings:
- **028** body size cap (16KB — Pub/Sub envelopes ≤ ~8KB realistic)
- **033** after `atob(envelope.message.data)`, check decoded `json.length > 16384` → throw `Error('payload too large')` → 400 response

- [ ] **Step 1: Write failing tests** in `rtdn-webhook/test.ts`:
  - `Deno.test('rtdn-webhook: 413 on >16KB request body')`
  - `Deno.test('rtdn-webhook: 400 on >16KB decoded base64 payload')` — base64-encode a 20KB JSON blob, send under a small envelope, assert 400

- [ ] **Step 2: Run tests — verify failures**

- [ ] **Step 3: Implement**:
  1. `requireBodySize(req, 16 * 1024)` at top of handler
  2. In `decodePubSubPayload`: after `atob(...)`, if decoded JSON length > 16384, throw `Error('payload too large')`; surface as 400 response (note: the function already 200s on testNotification and unknown types — keep that behavior; only the payload-too-large case 400s)

- [ ] **Step 4: Run tests — verify pass**

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/rtdn-webhook/
git commit -m "feat(edge): rtdn-webhook body + base64 payload caps (findings 028/033)"
```

---

## Task 5 — `vitality-nightly` size cap (finding 028 partial)

**Files:**
- Modify: `supabase/functions/vitality-nightly/index.ts`
- Modify or create: `supabase/functions/vitality-nightly/auth.test.ts` (existing) — extend with size-cap test

- [ ] **Step 1: Write failing test** — body > 1KB returns 413 (body is tiny: `{chunk: 0-9, source: string}`)

- [ ] **Step 2: Run — verify failure**

- [ ] **Step 3: Implement** — `requireBodySize(req, 1024)` at top of handler

- [ ] **Step 4: Run — verify pass**

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/vitality-nightly/
git commit -m "feat(edge): vitality-nightly body size cap (finding 028)"
```

---

## Task 6 — `ws` CVE fix in test/e2e (finding 029)

**Files:**
- Modify: `test/e2e/package-lock.json` (via npm)

- [ ] **Step 1: Run `npm audit` to confirm pre-fix state**

```bash
cd test/e2e && npm audit --omit=dev 2>&1 | grep -E "ws|GHSA-58qx"
```

Expected: at least one row mentioning `ws` 8.0.0–8.20.0 + `GHSA-58qx-3vcg-4xpx`.

- [ ] **Step 2: Run `npm audit fix`**

```bash
cd test/e2e && npm audit fix
```

Expected: `ws` lifts to ≥ 8.20.1 transitively. `package-lock.json` updated.

- [ ] **Step 3: Re-run `npm audit` to verify the CVE is cleared**

Expected: no `GHSA-58qx-3vcg-4xpx` row. Other CVEs (if any) noted for future PARK.

- [ ] **Step 4: Run a Playwright smoke locally to verify no regression**

```bash
cd test/e2e && FLUTTER_APP_URL= npx playwright test --grep @smoke --reporter=list
```

Expected: smoke suite green (or the same flake set as before — no new failures introduced by the ws bump). If new failures appear, investigate per CLAUDE.md systematic-debugging protocol before proceeding.

- [ ] **Step 5: Commit**

```bash
git add test/e2e/package-lock.json
git commit -m "chore(deps): bump transitive ws to clear GHSA-58qx-3vcg-4xpx (finding 029)"
```

---

## Task 7 — Verification + commit + PR + admin-merge

- [ ] **Step 1: Run full deno test suite**

```bash
deno test --allow-net --allow-env supabase/functions/
```

Expected: all tests pass — `_shared/`, `validate-purchase`, `delete-user`, `rtdn-webhook`, `vitality-nightly`.

- [ ] **Step 2: Run `make ci` (Flutter side)**

```bash
make ci
```

Expected: green. Should be a no-op for Dart since no `lib/` changes — analyzer + tests + build still need to run to confirm no incidental breakage.

- [ ] **Step 3: Dispatch reviewer agent** for diff review against the audit doc findings

Use foreground dispatch. The reviewer checks: (a) each finding's `Recommended:` line is implemented, (b) cluster-ref comments added where applicable (`developer-log-invisible-logcat` not applicable here; this PR establishes a new pattern — consider adding to PROJECT.md §0 Cluster Ledger as a candidate if any reviewer finding repeats), (c) edge cases on Content-Length headers (chunked encoding, missing header), (d) JWT precheck doesn't change semantics for service-role JWTs.

Loop: reviewer flags → tech-lead fixes → re-review → sign-off.

- [ ] **Step 4: Dispatch qa-engineer agent**

QA verifies: Deno test coverage is complete (negative cases for each new validation path), no missed wiring-trace patterns (per finding-014 (A) folded in 33b not here, but verify these tests assert behavior not just `verify(.called)`).

- [ ] **Step 5: Check off all WIP tasks 1–7**

- [ ] **Step 6: Commit any remaining changes** (WIP checkmarks; review-cycle fixes)

- [ ] **Step 7: Push branch**

```bash
git push -u origin feature/phase-33a-security
```

- [ ] **Step 8: Open PR**

Title: `feat(security): Phase 33 PR 33a — Edge Function defense-in-depth`

Body includes: summary, findings table (021 IMPORTANT + 3 folded), files changed list, test plan, link to audit doc Triage stamps section.

- [ ] **Step 9: Wait for CI green**

Fast checks (analyze + deno-tests + coverage-checks) + e2e. E2E should still pass (no Flutter app changes). If e2e fails, root-cause via systematic-debugging — likely the `ws` bump triggered something.

- [ ] **Step 10: Admin-merge**

```bash
gh pr merge <PR#> --squash --admin --delete-branch
```

Note: this PR is NOT docs-only (touches Edge Functions). The admin-merge is justified by green CI, not the `feedback_docs_only_pr_merge` exception. Wait for E2E to pass before merging.

- [ ] **Step 11: Update PROJECT.md §3 sub-PR table** — flip 33a PENDING → DONE (#PR-number). This update lands in the next fix-PR's commit (not its own micro-PR).

---

## PR 33a Notes

- **Token budget:** the tech-lead agent should keep the helper interface stable across tasks 2–5 (each function calls the same `requireBodySize` + `precheckJwtExp`). If the interface evolves mid-implementation, update Task 1 first then propagate.
- **Service-role JWT semantics:** `validate-purchase` accepts both user JWTs (via `getUser`) and service-role JWTs (via `isServiceRoleJwt` local decode). The `precheckJwtExp` runs BEFORE the service-role branch check — service-role JWTs DO have an `exp` claim (Supabase issues them with one), so they'll still pass the precheck. Don't special-case.
- **Cluster ledger candidate:** the "edge function input-validation pattern" (clamp + allow-list + body-size cap + JWT precheck) could become a cluster entry if this pattern recurs. Defer the ledger write to the actual cluster recurrence — single pattern occurrence doesn't warrant the entry yet.
- **No new migrations:** all fixes are application-layer. Existing RLS + SECURITY INVOKER guarantees are unchanged.
