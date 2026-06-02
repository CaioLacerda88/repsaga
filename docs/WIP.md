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

# Phase 33 — PR 33b (Dead-code + developer.log batch) Implementation Plan

**Goal:** Land 4 IMPORTANT + 3 folded NICE-TO-HAVE cleanup fixes per the Phase 33 audit. Dart-only — zero changes in `supabase/functions/`, `lib/features/{workouts,rpg}/` (already PR 32g'd for developer.log), or e2e specs.

**Architecture:** Mechanical migration of `developer.log()` / bare `log()` → `debugPrint('[Scope] msg')` across 5 `lib/core/` + `lib/features/personal_records/` files, drop their `dart:developer` imports, delete the orphan `SagaStubScreen` widget, delete 6 RPE l10n keys (Phase 25 dropped) + the `comingSoonStub` key from both ARBs, regenerate localizations, and widen the `check_no_developer_log.sh` CI gate from workouts+rpg scope to all of `lib/`.

**Tech Stack:** Dart (Flutter), Freezed/json_serializable codegen (l10n), bash (CI gate script).

**Spec reference:** `docs/pre-launch-audit.md` lines 123–298 (finding-001, 003, 004, 010 + folded 012, 014, 021).

**Branch:** `feature/phase-33b-cleanup`

---

## Files

### Migrate (5 files, ~12 call sites)
- **Modify:** `lib/core/local_storage/cache_service.dart` — finding-001 (4 sites: 21, 33, 48, 57) + finding-014 (drop `dart:developer` import)
- **Modify:** `lib/core/offline/pending_sync_provider.dart` — finding-001 + finding-021 (2 sites: 71, 137) + drop import
- **Modify:** `lib/core/l10n/locale_provider.dart` — finding-001 + finding-010 (2 sites: 82, 89; also wrap `.catchError` in async try/catch) + drop import
- **Modify:** `lib/core/local_storage/hive_service.dart` — finding-001 (3 sites: 184, 212, 226) + drop import
- **Modify:** `lib/features/personal_records/providers/pr_cache_bootstrap_provider.dart` — finding-001 (3 sites: 118, 141, 155) + drop import

### Delete (2 files + 7 ARB keys)
- **Delete:** `lib/features/rpg/ui/saga_stub_screen.dart` (finding-004) — orphan widget, never imported
- **Modify:** `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb` — delete 6 RPE keys (`rpeTooltip`, `rpeValue`, `rpeLabel`, `rpeMenuItem`, `setRpe`, plus the `@rpeTooltip` etc. metadata) + `comingSoonStub` (and its metadata key)

### Regenerate
- **Modify (codegen):** `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_en.dart`, `lib/l10n/app_localizations_pt.dart` — auto-regen via `flutter gen-l10n` after ARB deletions

### CI gate widening
- **Modify:** `scripts/check_no_developer_log.sh` — widen `SCOPE` from `(lib/features/workouts lib/features/rpg)` to `(lib)` and update preamble.

### Closeout (in the same first commit)
- **Modify:** `docs/WIP.md` — strip PR 33a section, append this PR 33b plan
- **Modify:** `docs/PROJECT.md` §3 sub-PR table — flip 33a PENDING → DONE (#292)

---

## Checklist

- [ ] Task 1 — PR 33a closeout + PR 33b plan commit
- [ ] Task 2 — Verify `dart:developer` usage count baseline + check tests
- [ ] Task 3 — Migrate `cache_service.dart` (finding-001 partial + finding-014)
- [ ] Task 4 — Migrate `pending_sync_provider.dart` (finding-001 + finding-021)
- [ ] Task 5 — Migrate `locale_provider.dart` (finding-001 + finding-010 async try/catch)
- [ ] Task 6 — Migrate `hive_service.dart` (finding-001 partial)
- [ ] Task 7 — Migrate `pr_cache_bootstrap_provider.dart` (finding-001 partial)
- [ ] Task 8 — Delete `saga_stub_screen.dart` (finding-004)
- [ ] Task 9 — Delete 6 RPE keys + `comingSoonStub` from both ARBs (finding-003 + finding-012)
- [ ] Task 10 — `flutter gen-l10n` to regenerate l10n
- [ ] Task 11 — Widen `check_no_developer_log.sh` scope to `lib/`
- [ ] Task 12 — Verify (format + gen + analyze + test) + commit + PR + reviewer + QA + admin-merge

---

## Task 1 — PR 33a closeout + PR 33b plan commit

Done as the first commit on `feature/phase-33b-cleanup`. Includes:
1. Strip PR 33a section from `docs/WIP.md`
2. Append this plan to `docs/WIP.md`
3. Flip 33a row in `docs/PROJECT.md` §3 sub-PR table: PENDING → DONE (#292)

Commit message: `docs(phase-33b): close out PR 33a + plan for PR 33b cleanup batch`

---

## Task 2 — Baseline check

- [ ] **Step 1: Confirm scope of `dart:developer` usage in `lib/`**

Run a Grep for `import 'dart:developer'` under `lib/`. Expected: 5 imports matching the 5 files in this PR. If more, investigate before proceeding.

- [ ] **Step 2: Confirm no test imports `dart:developer`**

Grep `test/` for same pattern. Expected: empty.

---

## Task 3 — Migrate `cache_service.dart`

**Files:**
- Modify: `lib/core/local_storage/cache_service.dart`

- [ ] **Step 1: Read the file end-to-end** — locate the 4 `log(` call sites at lines 21, 33, 48, 57. Each is inside an error handler.

- [ ] **Step 2: Replace pattern** — for each `log(...)`:
  - Import `package:flutter/foundation.dart` (for `debugPrint`) if not already imported
  - Replace `log('msg', name: 'foo', error: e, stackTrace: st)` with `debugPrint('[CacheService] msg: $e\n$st')`
  - Tag prefix: `[CacheService]`

- [ ] **Step 3: Remove `import 'dart:developer';`** (finding-014)

- [ ] **Step 4: Run analyzer + existing tests for the file**

---

## Task 4 — Migrate `pending_sync_provider.dart`

**Files:**
- Modify: `lib/core/offline/pending_sync_provider.dart`

- [ ] **Step 1: Read the file**, locate sites at lines 71 and 137 (finding-021 is the line 137 legacy drain log).

- [ ] **Step 2: Replace pattern** — tag prefix `[PendingSyncNotifier]`. Site at 137 specifically per finding-021: `debugPrint('[PendingSyncNotifier] 26e: <message>')`.

- [ ] **Step 3: Remove `import 'dart:developer';`**

- [ ] **Step 4: Analyzer + tests**

---

## Task 5 — Migrate `locale_provider.dart` (with async try/catch for finding-010)

**Files:**
- Modify: `lib/core/l10n/locale_provider.dart`

- [ ] **Step 1: Read the file** — locate `_syncToRemote` and the two `developer.log` sites at lines 82, 89.

- [ ] **Step 2: Replace `developer.log` calls** with `debugPrint('[LocaleNotifier] Failed to sync locale: $e')`.

- [ ] **Step 3: Refactor `.catchError` → async try/catch per finding-010**

If the current shape is `repo.updateLocale(...).catchError((e) { developer.log(...); });`, restructure to:

```dart
unawaited(() async {
  try {
    await repo.updateLocale(...);
  } catch (e) {
    debugPrint('[LocaleNotifier] Failed to sync locale: $e');
  }
}());
```

Add `import 'dart:async';` if `unawaited` is not yet in scope.

- [ ] **Step 4: Remove `import 'dart:developer';`**

- [ ] **Step 5: Analyzer + tests**

---

## Task 6 — Migrate `hive_service.dart`

**Files:**
- Modify: `lib/core/local_storage/hive_service.dart`

- [ ] **Step 1: Read the file**, locate sites at lines 184, 212, 226 (Hive box recovery / bootstrap).

- [ ] **Step 2: Replace pattern** — tag prefix `[HiveService]`

- [ ] **Step 3: Remove `import 'dart:developer';`**

- [ ] **Step 4: Analyzer + tests**

---

## Task 7 — Migrate `pr_cache_bootstrap_provider.dart`

**Files:**
- Modify: `lib/features/personal_records/providers/pr_cache_bootstrap_provider.dart`

- [ ] **Step 1: Read the file**, locate sites at lines 118, 141, 155 (PR-cache migration).

- [ ] **Step 2: Replace pattern** — tag prefix `[PrCacheBootstrap]`

- [ ] **Step 3: Remove `import 'dart:developer';`**

- [ ] **Step 4: Analyzer + tests**

---

## Task 8 — Delete `saga_stub_screen.dart` (finding-004)

**Files:**
- Delete: `lib/features/rpg/ui/saga_stub_screen.dart`

- [ ] **Step 1: Confirm no imports anywhere in `lib/` or `test/`** via grep on `saga_stub_screen` + `SagaStubScreen`. Expected: zero matches.

- [ ] **Step 2: Delete via `git rm lib/features/rpg/ui/saga_stub_screen.dart`**

- [ ] **Step 3: Re-grep to confirm clean.**

---

## Task 9 — Delete RPE + comingSoonStub ARB keys (finding-003 + finding-012)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_pt.arb`

- [ ] **Step 1: Confirm zero usage of the 6 RPE l10n getters anywhere in `lib/` + `test/`** via grep on `l10n.rpeTooltip`, `l10n.rpeValue`, `l10n.rpeLabel`, `l10n.rpeMenuItem`, `l10n.setRpe`, `l10n.comingSoonStub`.

- [ ] **Step 2: Delete keys + their `@key` metadata from both ARB files**

Keys to delete (in both `app_en.arb` and `app_pt.arb`):
- `rpeTooltip` + `@rpeTooltip`
- `rpeValue` + `@rpeValue`
- `rpeMenuItem` + `@rpeMenuItem`
- `rpeLabel` + `@rpeLabel`
- `setRpe` + `@setRpe`
- `comingSoonStub` + `@comingSoonStub`

- [ ] **Step 3: Verify ARB JSON is still valid**

Use a JSON parser (python -m json.tool or jq) to confirm both files parse.

---

## Task 10 — `flutter gen-l10n` to regenerate l10n

- [ ] **Step 1: Run `flutter gen-l10n`** (the standalone Make target; skip the full `make gen` since no Freezed/json_serializable source files changed).

- [ ] **Step 2: Verify regenerated files are clean** — grep generated files for the 7 removed key names. Expected: zero matches.

- [ ] **Step 3: Run analyzer on `lib/l10n/`** — 0 issues.

---

## Task 11 — Widen `check_no_developer_log.sh` scope

**Files:**
- Modify: `scripts/check_no_developer_log.sh`

- [ ] **Step 1: Change `SCOPE` array** from `(lib/features/workouts lib/features/rpg)` to `(lib)`.

- [ ] **Step 2: Update the preamble** to reflect the new contract — replace the workouts/rpg scope description with "Scope: all of `lib/`. After PR 33b, the entire app uses `debugPrint('[Scope] msg')` instead of `dart:developer.log`."

- [ ] **Step 3: Run the script locally** — expected: `check_no_developer_log: clean ...`

If any violation surfaces, that's a missed migration — fix it before proceeding.

---

## Task 12 — Verify + commit + PR + review cycle

- [ ] **Step 1: Run full pipeline locally** — format + gen-l10n + all analyze scripts + flutter test (excluding integration + golden).

- [ ] **Step 2: Stage + commit**

Suggested commit decomposition:
- `refactor(core): developer.log → debugPrint in 5 files (findings 001/010/014/021)`
- `chore(rpg): delete orphan SagaStubScreen widget (finding-004)`
- `chore(l10n): delete dropped RPE keys + comingSoonStub (findings 003/012)`
- `ci(analyze): widen check_no_developer_log scope to entire lib/`

- [ ] **Step 3: Dispatch reviewer agent**

- [ ] **Step 4: Dispatch qa-engineer agent**

- [ ] **Step 5: Push + open PR** with title `refactor(cleanup): Phase 33 PR 33b — developer.log sweep + dead-code removal`

- [ ] **Step 6: Wait for CI green** — specifically watch the `analyze` job for the widened gate.

- [ ] **Step 7: Admin-merge** with `--squash --admin --delete-branch`.

- [ ] **Step 8: Update PROJECT.md §3 sub-PR table** — flip 33b PENDING → DONE in next fix-PR (PR 33c's first commit).

---

## PR 33b Notes

- **Test files not migrated:** the audit's finding-001 scope is `lib/`. Test files that legitimately import `dart:developer` are out of scope. Task 2 confirms none exist today.
- **Symmetry with PR 32g:** PR 32g migrated `active_workout_notifier.dart`. PR 33b is the rest-of-codebase finisher. After PR 33b merges, the codebase has zero `dart:developer` imports in `lib/`.
- **`flutter/foundation.dart` vs `flutter/material.dart`:** prefer `package:flutter/foundation.dart` for non-UI files (notifiers, services, providers). For UI files already importing material, `debugPrint` comes along for free.
- **No e2e impact:** the only user-visible text change is removing `comingSoonStub` (already unreachable post-Phase-26c/d). RPE keys never rendered. SagaStubScreen never routed to. Zero risk to selectors.
- **CI gate widening is the keystone:** without Task 11, a future PR could reintroduce `developer.log` in `lib/core/` and CI wouldn't catch it. The gate is the contract.
