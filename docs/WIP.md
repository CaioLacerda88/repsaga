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
- [ ] Establish baseline: `npx supabase db reset` (≤00078), edge-runtime up
      (`docker start supabase_edge_runtime_repsaga`), run FULL `flutter test --tags
      integration`, capture the exact failing set (the "18"). Separate real code
      failures from edge-runtime infra flakes (vitality 503).
- [ ] Fix [1] record_set_xp parity oracle (root cause; assert exact PG==Dart, no widened tol).
- [ ] Fix [2] peak_load exercises.name seed.
- [ ] Fix [3] backfill suite (diagnose first).
- [ ] Any other failures in the captured set — root-cause each.
- [ ] FULL `flutter test --tags integration` GREEN (infra flakes excepted + documented).
- [ ] `dart format` + `dart analyze --fatal-infos` + `flutter test --exclude-tags "integration || golden"` still green.
- [ ] reviewer → fixes → PR → merge.
- [ ] (Optional follow-up, separate task) devops: a CI integration job against a CI Supabase so this can't rot again — note in PROJECT.md §2 if not done here.

### After merge
Rebase `feature/phase38c-cardio-earning` onto the green main (it touches
`rpg_record_set_xp_test.dart` too → expect a conflict there; resolve keeping BOTH
the oracle fix and 38c's `event_type='set'` cross-credit scoping), then resume the
38c pipeline (reviewer re-engage → QA → PR → ship → push 00079 to hosted).
