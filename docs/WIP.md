# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 Tier 2 — pipeline gates — `feature/hardening-t2-pipeline-gates`

Per `docs/PROJECT.md` §2 → Phase 38.9 Tier 2. CI/tooling + docs bundle (reviewer reads,
QA skipped). **No-regression rule: a new gate must NOT red-fail main on existing code —
verify zero current violations (or allow-list with justification) BEFORE wiring each gate.**

### Checklist
- [x] **T2.3 layering gate** — `scripts/check_no_supabase_outside_data.sh` created. Pattern
  `\.(from|rpc)\('` (string-literal only; comment lines filtered; collection `.from(var)` excluded).
  `health_check_provider.dart` allow-listed (infra probe, not feature data access; full justification
  in script ALLOW_LIST comment). Script exits 0 on current code. Wired as `layering-check` CI job
  (bash-only, parallel with analyze/test/build) + added to `ci` aggregator needs/result-check/echo.
- [x] **T2.1 coverage floor** — `scripts/check_coverage_floor.sh` created. Measured: 78.4%
  (16555/21104 lines) after Phase 38b. Floor set to 77 (rounds down, ~1.4% headroom). Added as
  "Check coverage floor" step in `test` job immediately after `flutter test --coverage`. Script
  exits 0 locally. Documents how to raise the floor.
- [x] **T2.2 dependency-vuln scan** — `osv-scanner` CI job added (google/osv-scanner-action@v2,
  parallel, bash-only). `.osv-scanner.toml` created with ignore-list infrastructure (no ignores
  needed yet — first real run in CI will audit). `.github/dependabot.yml` added for `pub` +
  `github-actions` ecosystems (weekly, Mon 09:00 BRT, limit 5 PRs each). osv-scanner not locally
  available — CI first run is the real audit. Job wired into `ci` aggregator.
- [x] **T2.4 migration-rollback doc** — CLAUDE.md step 12 extended with: (a) forward-fix convention
  (never down-migrations, always a new corrective migration), (b) pre-push checklist for
  launch-critical migrations (PITR backup confirmation, pg_dump snapshot, local-first test,
  corrective migration pre-prepared).
- [x] Verify: T2.3 + T2.1 scripts pass locally (output pasted in task summary); `ci` aggregator
  updated consistently for `layering-check` + `osv-scanner`; YAML structurally valid (12 jobs
  with runs-on, all indentation checked).

_Tier 1 complete (#367/#369/#372). Tiers 0 + 3 still queued in PROJECT.md §2._
