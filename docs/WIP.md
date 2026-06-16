# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Integration suite cleanup — get `flutter test --tags integration` green on main

Branch `fix/integration-suite-green` (off main `35a4b2b4`). Discovered during
Phase 38c review: the integration-tagged suite has **~18 pre-existing failures on
main**, invisible because CI runs `--exclude-tags integration` (see
[[project_integration_suite_red_on_main]]). Phase 38c is **paused on its branch**
(`feature/phase38c-cardio-earning` @ `0891d60f`, clean, zero NEW failures) until
this lands; 38c rebases onto the green baseline after.

**Goal:** integration suite green on main (excluding genuine infra flakes), so the
integration gate becomes "all green" again instead of "no new failures vs main."
Fix root causes (stale test oracles / removed-column seeds), NOT the production
formula (Phase-29-v2 unit fixture parity is green — production is correct).

### Known root causes (from the 38c fix-agent diagnosis — re-verify on main)
1. **`rpg_record_set_xp_test.dart` strength PG/Dart parity** — the Dart oracle calls
   `XpCalculator.computeSetXp(...)` WITHOUT `impliedTier`/overload/frequency inputs,
   so it computes `tier_diff_mult=1.0`/`abs_strength_premium=1.0` while the SQL batch
   applies the full Phase-29-v2 chain → ~2.94× under-computation (e.g. shoulders
   PG=91.59 vs Dart=31.20). FIX: feed the oracle the same implied-tier/overload/
   frequency inputs the SQL uses, so PG==Dart. The production formula is correct
   (unit fixtures green) — this is test-oracle staleness since Phase 29 v2.
2. **`peak_load_per_body_part_test.dart`** — seeds the `exercises.name` column removed
   in Phase 15f (content moved to `exercise_translations`). FIX: seed via slug +
   translations like current post-15f tests; drop the `name` insert.
3. **Backfill integration suite** — red; diagnose root cause (likely similar schema/
   oracle drift) and fix.

### Checklist (TDD / systematic-debugging — root cause, not symptom)
- [x] Establish baseline: `npx supabase db reset` (≤00078), edge-runtime up,
      ran FULL `flutter test --tags integration` → baseline `+48 -18`. The 18
      failures were 4 clusters (NO edge-runtime/vitality 503 flakes this run):
      6× `peak_load_per_body_part` (removed `exercises.name` seed), 6×
      `rpg_record_set_xp` (stale Phase-29-v2 oracle), 2×+2× `rpg_backfill` /
      `rpg_backfill_resume` (shared stale `computeDartReference`), 2×
      `rpg_backfill_zero_weight` (admin-client GRANT).
- [x] Fix [1] record_set_xp parity oracle — thread the SQL-derived
      `impliedTier` (NULL-bw fallback = 15.0 via `impliedTier(bodyweightKg:0)`)
      + `currentRank` (fresh user = 1) into all 6 `computeSetXp` call sites.
      Reworked the BUG-RPG-001 "different weights" oracle to seed the residual
      band-peak ladder (overload_mult=1.15) → asserts EXACT PG==Dart at `_kTol`.
- [x] Fix [2] peak_load `exercises.name` seed — drop `name`, supply explicit
      unique `slug` (post-15f join key; trigger RAISEs without it). No
      translation rows needed (RPC reads only `xp_attribution`; rows are
      `is_default=false`).
- [x] Fix [3] backfill suite — rewrote `computeDartReference` to mirror the
      full Phase-29-v2 `_rpg_backfill_chunk` chain (share-count session/weekly
      accumulators, implied_tier 15.0, evolving current_rank via RankCurve,
      overload + frequency mults). Fixed `rpg_backfill_zero_weight` to call
      `backfill_rpg_v1` as the authenticated user (production path; the RPC is
      GRANTed to `authenticated` only, not `service_role`).
- [x] FULL `flutter test --tags integration` GREEN → `+66 -0` (EXIT 0).
- [x] `dart format .` (0 changed) + `dart analyze --fatal-infos` (0 issues) +
      `flutter test --exclude-tags "integration || golden"` (`+3613 ~1`) green.
- [ ] reviewer → fixes → PR → merge.
- [ ] (Optional follow-up, separate task) devops: a CI integration job against a CI Supabase so this can't rot again — note in PROJECT.md §2 if not done here.

### After merge
Rebase `feature/phase38c-cardio-earning` onto the green main (it touches
`rpg_record_set_xp_test.dart` too → expect a conflict there; resolve keeping BOTH
the oracle fix and 38c's `event_type='set'` cross-credit scoping), then resume the
38c pipeline (reviewer re-engage → QA → PR → ship → push 00079 to hosted).
