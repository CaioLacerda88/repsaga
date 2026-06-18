# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## CI integration-test job + e2e shard rebalance

**Branch:** `ci/integration-test-job`
**Source:** `docs/PROJECT.md` §2 → "CI integration-test job (follow-up from #339)"
**Pipeline:** Tooling/CI change → devops implements → reviewer reads → ship (QA skipped, no user surface).

The integration-tagged suite (`flutter test --tags integration`) is NOT run in CI
because it needs a live Supabase — so it rotted to 18 failures undetected until the
38c review (#339 repaired it). Stand up a CI job so it can't silently rot again, and
rebalance the e2e shard split (shard 2 brushes the 30-min ceiling).

### Checklist
- [x] New `integration-test` job in `.github/workflows/ci.yml`:
  - [x] Boot a live local Supabase (mirror the `e2e.yml` pattern: `supabase/setup-cli@v1`
        + `supabase start` + write `.env` from `supabase status -o env` + wait-for-ready probe)
  - [x] `flutter pub get` + `build_runner` + `flutter test --tags integration`
  - [x] Add the job to the `ci` aggregator `needs:` + the all-jobs-passed gate (keep symmetry)
- [x] Rebalance e2e shards in `.github/workflows/e2e.yml` (shard 2 → 30-min ceiling):
      bump 3→4 shards (`matrix.shard: [1,2,3,4]` + `--shard=N/4`) so per-shard wall-clock drops
- [x] Verify YAML is well-formed; confirm the integration suite is green on this branch's HEAD
      vs main (gate = "no NEW failures vs main") — 72/72 passed
- [ ] PROJECT.md §2: condense the follow-up once the job is live (after PR merges)

**Phase 38 (Cardio / Conditioning Track) ✅ COMPLETE** — 38a–38g + 38e-bis shipped;
migrations 00077–00081 + the `vitality-nightly` edge fn on hosted; balance locked v1-final.
Remaining §2 follow-up after this: post-launch cardio tier-band recalibration (telemetry-gated).
