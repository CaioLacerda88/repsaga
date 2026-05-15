# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 24d — Calibration gate

Branch: `feature/phase24d-calibration-gate`
Spec: `docs/PROJECT.md` §3 → Phase 24 → 24d acceptance criteria.

Pure Python sim + docs. No Dart, no SQL, no UI. The 6 existing CONSISTENCY
archetypes stay untouched (they validate detraining concerns and back the
fixture replay). 6 NEW calibration archetypes are added per the spec table:
beginner_24d, intermediate_compound, advanced_powerlifter,
hypertrophy_bodybuilder, bodyweight_only, machine_only.

### Phase A — Sim extension + baseline doc (Task 24d-1)

- [x] Read PROJECT.md §3 → Phase 24d acceptance + framework + 00053 + 00056
- [x] Plan: extend `SIM_ALIAS_TO_DEFAULT_SLUG` with identity entries for new real slugs; extend `ATTRIBUTION` for any new exercises; add `pistol_squat`+`archer_push_up` to `DIFFICULTY_MULT_BY_SLUG` (24b values, gap-fill)
- [x] Add `CALIBRATION_ARCHETYPES` dict with 6 new entries (separate from `ARCHETYPES` to keep blast radius zero on existing fixture replay)
- [x] Add `CALIBRATION_DAY_TEMPLATES` keyed by archetype-specific session names (heterogeneous per archetype unlike the shared `DAY_TEMPLATES`)
- [x] Add `simulate_calibration(archetype, weeks)` mirroring `simulate()` shape but consulting per-archetype day templates + bodyweight_kg from the new archetype
- [x] Add per-week reporter that prints per-archetype 12-week table (week | xp_earned | char_level | per-bp ranks)
- [x] Add `--calibration` CLI flag — default behavior (no flag) unchanged
- [x] Verify default `python tasks/rpg-xp-simulation.py` still produces existing output
- [x] Verify `python tasks/rpg-xp-simulation.py --calibration` runs cleanly + prints all 6 new archetypes
- [x] Spot-check bodyweight_only resolves all curated bodyweight slugs (`uses_bodyweight_load=True` debug)
- [x] Generate `docs/xp-balance-baseline.md` from a `--baseline-doc` (or stdout-redirect) mode containing: constants snapshot, tier table, 199 difficulty_mult slugs sorted, 20 uses_bodyweight_load slugs, 6-archetype week-12 summary, per-archetype week-by-week tables
- [x] `python test/fixtures/generate_rpg_fixtures.py` regenerates fixture byte-identically (proves no formula change)
- [x] `flutter test test/unit/features/rpg/` parity tests still green
- [x] Mark task #26 complete via TaskUpdate

### Phase B — Pass-criteria analysis (Task 24d-2 — DONE iter 3 sign-off)

Iter 3 sign-off accepted (4/6 PASS, 2 borderline in safe direction). Constants:
`VOLUME_EXPONENT 0.65→0.60`, `WEEKLY_CAP_SETS 20→15`, `OVER_CAP_MULTIPLIER 0.5→0.3`,
T4 `-0.05` to 28 curated slugs.

### Phase C — Production propagation of iter-3 calibration (Task 24d-2b)

Per `docs/xp-balance-baseline.md` iter-3 sign-off + `docs/PROJECT.md` §3 Phase 24d.
Atomic Dart + SQL + Python sim + fixture regen + framework doc + tests.

- [x] Dart `xp_calculator.dart` — update 3 constants + class doc Phase 24d note
- [x] NEW migration `00059_phase24d_calibration_propagation.sql` — UPDATE 28 T4 slugs (-0.05) + DO-block sanity assert
- [x] Same migration — `CREATE OR REPLACE FUNCTION` for `rpg_base_xp` helper (volume_exponent 0.65→0.60), `record_set_xp`, `record_session_xp_batch`, `_rpg_backfill_chunk` with new cap constants (15 / 0.3) at the inline formula sites
- [x] Python sim — promote `_CALIBRATION_VOLUME_EXPONENT/WEEKLY_CAP_SETS/OVER_CAP_MULTIPLIER` to canonical, delete override scaffolding, update `DIFFICULTY_MULT_BY_SLUG` for the 23 in-mirror T4 slugs (-0.05 each; 5 Phase-24b T4 slugs not yet mirrored stay absent per existing partial-mirror invariant), update CONFIG header
- [x] Regenerate fixture: `python test/fixtures/generate_rpg_fixtures.py`
- [x] `xp_calculator_test.dart` — fixture-driven; updated 3 explicit constant assertions (0.60 / 15 / 0.3) + cap boundary test (15.0 → 0.3)
- [x] Integration tests — `rpg_backfill_test.dart` + `rpg_backfill_resume_test.dart` `ExerciseDef.difficultyMult` for `lat_pulldown` shifted 0.99→0.94 (T4)
- [x] Framework doc `xp-difficulty-framework.md` — T4 row tier_mult 0.95→0.90 + "Phase 24d calibration update" note + §6 worked-examples table extended + §7 deadlift-vs-leg-press ratio updated
- [x] Update `xp-balance-baseline.md` — appended "Production propagation" section + dropped PROVISIONAL markers + marked OFFICIAL launch baseline
- [x] Verification: `dart format` (522 files clean) + `dart analyze --fatal-infos` (no issues) + `flutter test --exclude-tags integration` (2689 tests passing)
- [x] Verification: `npx supabase db reset` clean through 00059; psql spot-check confirmed `leg_press` = 0.92, `lat_pulldown` = 0.94, `machine_chest_press` = 0.94, `cable_crunch` = 0.90, `cable_pullover` = 0.96, `barbell_squat` = 1.19 (unchanged), `deadlift` = 1.21 (unchanged); `rpg_base_xp(100, 8)` = 55.19 (= 800^0.60)
- [x] Verification: `flutter test --tags integration` — all 39 tests green (15 record_set_xp, 6 backfill, 18 others)
- [x] Verification: `flutter build apk --debug --no-shrink` clean + `flutter build web` clean
