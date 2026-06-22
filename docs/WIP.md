# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 T1.3 — RLS isolation test gate — `feature/hardening-t1.3-rls-gate`

Per `docs/PROJECT.md` §2 → Phase 38.9 T1.3. Prerequisite for Phase 40 (first cross-user RLS).
**Approach:** pgTAP via `supabase test db` against the LOCAL Supabase the pipeline already boots
(NOT the commented-out hosted-secrets stub at `ci.yml:445`). Self-contained, no secrets.

**No-regression guardrails (user-mandated):**
- Tests MUST pass against CURRENT RLS — that's the proof current isolation is sound. A RED test
  = a real existing RLS hole → STOP, surface to user, do NOT silently alter production policies.
- This PR adds ONLY: `supabase/tests/*.sql` (pgTAP) + a new `rls-tests` CI job. No production
  RLS policy edits, no migration changes, no app-code changes. Zero boundary surface.
- New CI job must not break the existing pipeline — verify the `ci` aggregator wiring + that the
  Supabase boot pattern matches the proven `integration-test` job.

### Checklist
- [x] Inventory every RLS-protected table + its policies (read `supabase/migrations/`).
- [x] Write `supabase/tests/rls_isolation_test.sql` (pgTAP): for each user-data table, prove
  (a) a user CAN access their own rows, (b) a user CANNOT SELECT/INSERT/UPDATE/DELETE another
  user's rows. Simulate users via `set local role authenticated` + `request.jwt.claims`.
  → 58 assertions across profiles, exercises (custom), workouts, workout_exercises, sets,
  personal_records, weekly_plans, workout_templates (routines), cardio_sessions, xp_events,
  body_part_progress, exercise_peak_loads, exercise_peak_loads_by_rep_range, earned_titles,
  backfill_progress, vitality_runs, subscriptions, subscription_events,
  + storage.objects avatars own-prefix.
- [x] Run `supabase start` + `supabase test db` LOCALLY → ALL GREEN. `Result: PASS` / Tests=58,
  0 not-ok, no plan mismatch. **Current RLS isolation is sound — zero holes found.**
- [x] Add a dedicated `rls-tests` CI job (setup-cli@latest → start → wait-ready → `supabase test
  db`; no Flutter) + added to the `ci` aggregator `needs` + result check + echo. Stale commented
  hosted-secrets stub removed.
- [x] Verify: YAML valid, ci.needs includes rls-tests, no production migration / app-code / RLS
  policy edits (only `supabase/tests/` + `ci.yml`). Reviewer reads, QA skipped (CI/tooling).

#### Review findings applied (PR #369 CHANGES REQUESTED)
- [x] [Blocker] Added owner-scoped SELECT isolation (positive + negative) for `vitality_runs`,
  `subscriptions`, `subscription_events` (SELECT-only authenticated surface; writes via
  service-role Edge Functions). Seeded one row per user per table matching real NOT NULL columns.
- [x] [Important] `backfill_progress` — added the positive+negative SELECT pair that the header
  claimed but the body never asserted.
- [x] [Nit] After the workouts blocked-UPDATE assertion, added a superuser read proving B's row
  value is intact ('B Workout', not 'HACKED') — makes "row truly untouched" explicit.
- [x] [No action] CI image-pull retry left consistent with integration-test/e2e jobs (no wrapper).

_Phase 38.9 T1.1+T1.2 merged via #367; T1.4 + Tiers 0/2/3 still queued in PROJECT.md §2._
