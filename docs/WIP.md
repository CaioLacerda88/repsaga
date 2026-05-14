# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 24a — Difficulty Multiplier Infrastructure

**Branch:** `feature/phase24a-difficulty-mult`
**Source:** `docs/PROJECT.md` §3 → Phase 24 — XP Balancing (24a row).
**Framework:** `docs/xp-difficulty-framework.md` (tier table + formula).

### Goal

Wire `exercises.difficulty_mult` (numeric 0.85–1.25) into the XP formula
across the three canonical sites (Dart `XpCalculator`, SQL `record_set_xp` /
`record_session_xp_batch`, Python parity sim). Curate every existing
`is_default = true` exercise against the §3 tier table. Forward-only:
`xp_events.payload` snapshots `difficulty_mult` at write time; past events
are NOT replayed.

### Boundary inventory

Cross-cuts three formula implementations + payload schema + 150 default
exercises + parity-fixture pipeline. Single PR — parity tests enforce
all-three-or-nothing; splitting would leave broken intermediate states.

| Surface | Files | Change |
|---|---|---|
| Dart formula | `lib/features/rpg/domain/xp_calculator.dart` | Add `difficultyMult` param to `computeSetXp`; apply as final multiplier; add field + JSON key to `SetXpComponents` |
| Dart payload model | `lib/features/rpg/models/xp_event.dart` | Add `difficultyMult` field (Freezed regen) |
| SQL RPC (per-set + batch + backfill) | NEW migration with `CREATE OR REPLACE FUNCTION record_set_xp` + `record_session_xp_batch` + `backfill_rpg_v1` | Fetch `exercises.difficulty_mult` per set, apply in body-part loop, snapshot to `payload` JSONB. **Do NOT edit 00040/00050/00052 in place** — append-only convention. |
| Schema migration | NEW migration `0005X_add_exercise_difficulty_mult.sql` | `ALTER TABLE exercises ADD COLUMN difficulty_mult numeric(4,2) NOT NULL DEFAULT 1.0` + per-slug `UPDATE` for ~150 defaults + `CHECK (difficulty_mult BETWEEN 0.85 AND 1.25)` + DO-block sanity assert (every `is_default = true` mapped) |
| Python sim | RECREATE `tasks/rpg-xp-simulation.py` (deleted in PR #215) | Rebuild from current Dart formula + add per-exercise `DIFFICULTY_MULT` map keyed by slug |
| Fixture generator | `test/fixtures/generate_rpg_fixtures.py` | Add difficulty_mult to set-xp examples + backfill replay; regenerate `rpg_xp_fixtures.json` |
| Dart parity tests | `test/unit/features/rpg/xp_calculator_test.dart` | Auto-updates from regenerated fixture (fixture-driven) |
| SQL parity tests | `test/integration/rpg_record_set_xp_test.dart`, `rpg_backfill_test.dart`, `rpg_backfill_resume_test.dart` | Update hardcoded ranks/totals from new sim output; assert `difficulty_mult` in payload |
| CI gate | `scripts/check_exercise_translation_coverage.sh` (sibling pattern) | Add `scripts/check_exercise_difficulty_mult_coverage.sh` — every `is_default = true` insert paired with a difficulty_mult assignment in the same PR (analogous to translation coverage) |
| Providers (no code change, verify only) | `rpgProgressProvider`, `statsProvider`, `characterSheetProvider`, `classProvider` via `sync_service.dart` | Invalidation cascade already wired; no code change but verify after migration apply |

**Boundary breach risks (top 3):**
1. **Out-of-sync formula** — Dart, SQL, Python diverge. Mitigated by integration parity tests (1e-4 absolute tolerance).
2. **Payload schema mismatch** — SQL writes `difficulty_mult`, Dart `XpEvent` model can't deserialize. Mitigated by Freezed regen + `rpg_record_set_xp_test.dart`.
3. **Unmapped default exercises** — DEFAULT 1.0 silently swallows misses. Mitigated by DO-block sanity assert at the end of the migration that fails loudly if any `is_default = true` row still has the literal default.

### Tier curation source

`docs/xp-difficulty-framework.md` §3 lists 80+ named exercises across tiers.
Our existing 150-default library overlaps but doesn't match 1:1 — every
default exercise must be assigned a tier explicitly. Where a default
doesn't appear in §3, choose the closest §3 analog and document the
judgment call in the migration as an inline SQL comment.

Composite formula (§6):
```
difficulty_mult = clamp(
    tier_mult + min(secondary_muscle_count, 3) × 0.02,
    0.85,
    1.25
)
```

For 24a we ship `difficulty_mult` as the final composite (tier_mult +
secondary bump pre-baked). The schema does not store tier separately;
the migration includes the tier assignment in inline SQL comments
(`-- T2 + 3 sec → 1.21`) so future audits can reverse-engineer.

### Implementation checklist

#### Phase A — Foundation (no behavior change)

- [ ] Verify framework doc is current (already reviewed 2026-05-13; no edits expected)
- [x] Recreate `tasks/rpg-xp-simulation.py` with current formula (from `xp_calculator.dart`) — no difficulty_mult yet (recovered from `10b1c4e^`, audited byte-for-byte against current Dart, no drift)
- [x] Confirm `python test/fixtures/generate_rpg_fixtures.py` regenerates an identical `rpg_xp_fixtures.json` (parity baseline) — byte-identical
- [x] Run `make test` — confirm green before any formula change (`flutter test test/unit/features/rpg/` → 307/307 passed)

#### Phase B — Schema + curation

- [x] New migration `00053_add_exercise_difficulty_mult.sql`:
  - [x] `ALTER TABLE exercises ADD COLUMN difficulty_mult numeric(4,2) NOT NULL DEFAULT 1.0`
  - [x] Per-slug UPDATE block for every `is_default = true` exercise (150 rows). Match by `slug` (added in 00030). Inline comment per row with `-- T<N> + <sec> sec → <value>`. Secondary count proxy: `jsonb_object_keys(xp_attribution) − 1` (since `secondary_muscle_groups` was added empty in 00040 and never populated for defaults).
  - [x] `ALTER TABLE exercises ADD CONSTRAINT chk_difficulty_mult_range CHECK (difficulty_mult BETWEEN 0.85 AND 1.25)`
  - [x] DO-block sanity assert: zero defaults at the literal 1.0 (verified via `npx supabase db reset` end-to-end; 150/150 curated, range [0.85, 1.25], 13 distinct values).
- [x] `scripts/check_exercise_difficulty_mult_coverage.sh` — CI gate parses INSERT/UPDATE shapes; self-test (3 fixtures: complete / missing / inline) passes.
- [x] Wire into `.github/workflows/ci.yml` next to `exercise-translation-coverage-check`; added to `ci` aggregator's `needs` list.

#### Phase C — Dart formula

- [x] `lib/features/rpg/domain/xp_calculator.dart`:
  - [x] Add `difficultyMult` required param to `computeSetXp`
  - [x] Apply as final multiplier in the chain: `setXp = base × intensity × strength × novelty × cap × difficultyMult`
  - [x] Add `difficultyMult` field to `SetXpComponents`
  - [x] Add `difficulty_mult` key to `SetXpComponents.toJson()` (placed in chain order between `cap_mult` and `set_xp`)
  - [x] Add `difficultyMultFloor = 0.85` / `difficultyMultCeiling = 1.25` constants (documented; not enforced in `computeSetXp` — SQL CHECK is source of truth)
- [x] `lib/features/rpg/models/xp_event.dart`:
  - [x] Add nullable `difficultyMult` field for legacy-payload deserialization
  - [x] Regenerate Freezed (`xp_event.freezed.dart` + `xp_event.g.dart` updated; `difficulty_mult` snake-case JSON key wired)
- [x] All call sites of `computeSetXp` updated to pass `difficultyMult: 1.0` explicitly (preserves current XP values until Phase E regenerates fixture):
  - [x] `test/unit/features/rpg/xp_calculator_test.dart` (5 sites in fixture/edge tests)
  - [x] `test/integration/rpg_record_set_xp_test.dart` (4 sites)
  - [x] `test/integration/rpg_backfill_test.dart` (1 site in `computeDartReference`)
- [x] Update doc comment in `xp_calculator.dart` to reflect new formula chain (preserved the "change all three sites in one PR" warning)
- [x] 3 new hand-computed unit tests added (ceiling 1.25, floor 0.85, default 1.0 byte-parity with pre-24a chain) + 1 constants test
- [x] `dart format` clean, `dart analyze --fatal-infos` clean, `flutter test test/unit/features/rpg/` 311/311 green

#### Phase D — SQL RPC

- [x] New migration `00054_record_xp_with_difficulty_mult.sql` — `CREATE OR REPLACE FUNCTION` for:
  - [x] `record_set_xp(p_set_id uuid)` — fetches `exercises.difficulty_mult` via `COALESCE(..., 1.0)` in the existing attribution SELECT; applies as final multiplier in per-bp chain; payload includes `difficulty_mult` key in chain order
  - [x] `record_session_xp_batch(p_workout_id uuid)` — multiplier carried on `v_set_record` from the driving SELECT (single new column on existing `JOIN exercises ex` — no per-row re-query); cast to float8 once alongside base/intensity/strength; payload rounds to numeric(14,4) at storage boundary
  - [x] `_rpg_backfill_chunk(p_user_id, p_chunk_size)` — same pattern; the wrapper `backfill_rpg_v1` itself wasn't replaced (cursor/checkpoint only — no XP math)
- [x] SQL formula chain matches Dart byte-for-byte (intensity table verified unchanged in 00040 helpers; multiplier order: `base × intensity × strength × novelty × cap × difficulty × attr_share`; strength clamp behavior unchanged)
- [x] Inline comment block added at the top of each RPC referencing `xp_calculator.dart::computeSetXp` and the all-three-sites-in-one-PR rule
- [x] `npx supabase db reset` clean end-to-end (migrations 00001 → 00054 apply without error)
- [x] Spot-checked payload shape via DO-block on a T1 (1.25) and T5 (0.85) default exercise: `record_set_xp` and `record_session_xp_batch` both write `difficulty_mult` key with correct value; per-set XP parity verified to 1e-9 absolute (bench: PG=96.3648 vs hand-computed 96.3648 with diff=1.25; isolation: PG=48.2780 vs 48.27805 rounded with diff=0.85)
- [x] Integration tests fail ONLY on the expected Dart-vs-SQL value mismatch — Phase F handoff. All deltas observed are exact difficulty_mult ratios (1.090 / 1.190 / 1.210). **Zero** schema errors, JSON shape mismatches, missing-key errors, or deserialization failures. Confirmed across `rpg_record_set_xp_test.dart` (3 parity tests fail, 4 idempotency/concurrent/peak-load tests pass) and `rpg_backfill_test.dart` / `rpg_backfill_resume_test.dart` (parity tests fail with same exact ratio).

#### Phase E — Python sim parity

- [x] Update `tasks/rpg-xp-simulation.py`:
  - [x] Add `DIFFICULTY_MULT_BY_SLUG` dict mirroring the migration's tier assignments (150 entries, byte-identical to `00053_add_exercise_difficulty_mult.sql` — verified via diff against extracted `(slug, mult)` pairs from the migration; zero drift)
  - [x] Add module-level `DIFFICULTY_MULT_FLOOR = 0.85` / `DIFFICULTY_MULT_CEILING = 1.25` constants (mirror `XpCalculator.difficultyMultFloor` / `Ceiling`); add `difficulty_mult_for_slug(slug)` returning 1.0 default for user-created/unknown
  - [x] Add `SIM_ALIAS_TO_DEFAULT_SLUG` map + `difficulty_mult_for_alias(alias)` so the simulator's short class aliases (`bench`, `squat`, `row`, etc.) resolve to real per-slug multipliers; preserves the existing `simulate()` shape while exercising the migration's actual values
  - [x] Update `compute_set_xp` to require `difficulty_mult` named param (no default — same convention as Dart) and apply as final multiplier in chain BEFORE the per-bp attribution split: `base × intensity × strength × novelty × cap × difficulty_mult × share`
  - [x] Update `simulate()` driver to look up the per-set mult via `difficulty_mult_for_alias(exercise)` once per exercise definition (cheap; aliases don't change within a session)
  - [x] Update file-level docstring to mention `00054_record_xp_with_difficulty_mult.sql` as a fourth synchronized site
- [x] Update `test/fixtures/generate_rpg_fixtures.py`:
  - [x] `fx_set_xp_examples()` rewritten — 11 scenarios now (was 8): 8 use real per-exercise mults (bench/deadlift/leg_curl/push_press/push_up/barbell_curl), plus 3 new explicit-clamp scenarios (`user_created_default_1_0` at 1.0, `explicit_floor_0_85` at 0.85, `explicit_ceiling_1_25` at 1.25). Both clamp ends exercised with literal values independent of any single exercise mapping. `inputs.difficulty_mult` + `components.difficulty_mult` keys carry the value (alphabetical JSON key order via `sort_keys=True`; field-name match is the load-bearing contract)
  - [x] `fx_backfill_replay()` updated — per-set log entries now include `difficulty_mult` and the 1500-set archetype playback applies the per-alias mult per set. Final ranks shifted as expected: chest 30→31, back 36→37, legs 37→38, shoulders 30→31, core 26→28, arms unchanged at 37 (~+5-10% XP per part — matches the average mult >1.0 the intermediate split exercises)
  - [x] `fx_attribution_distribution()` left unchanged — only multiplies a fixed `set_xp_input = 100.0` by attribution shares; does not consume `compute_set_xp` so no shift expected
  - [x] Added `difficulty_mult_floor: 0.85` / `difficulty_mult_ceiling: 1.25` to `meta` block
- [x] Regenerated `test/fixtures/rpg_xp_fixtures.json` (+113 −21 lines, exactly 3 hunks: `meta`, `set_xp_examples`, `backfill_replay`). Verified via section-by-section equality check vs `HEAD`: `intensity_lookup`, `volume_load`, `strength_mult`, `novelty_mult`, `cap_mult`, `character_level`, `rank_curve`, `vitality`, `attribution_distribution` are byte-identical (those don't go through difficulty_mult — vitality is volume-based not XP-based, so correctly unchanged)
- [x] `flutter test test/unit/features/rpg/` — 309/310 pass; 1 expected failure in `xp_calculator_test.dart` "every set_xp fixture case matches" because the test still hardcodes `difficultyMult: 1.0` (Phase C placeholder) instead of reading `inputs.difficulty_mult` from the regenerated fixture. The failure ratio is exactly 74.29/68.16 = 1.090 = bench mult — proves the formula chain is wired correctly. **Phase F handoff:** rewire the test to consume `inputs['difficulty_mult']` from the fixture; out of scope for Phase E per the prompt's "DO NOT touch xp_calculator_test.dart source code" boundary
- [x] `dart analyze --fatal-infos` clean (Python-only changes; no Dart drift)

#### Phase F — Test updates

- [x] `test/unit/features/rpg/xp_calculator_test.dart`: rewired the fixture-driven `computeSetXp — end-to-end parity` assertion to read `inputs['difficulty_mult']` per scenario (one-line change). All 311 RPG unit tests pass off the regenerated fixture; the 4 Phase-C semantic tests stay untouched.
- [x] `test/integration/rpg_record_set_xp_test.dart`: every `computeSetXp` call site now reads the curated multiplier via `difficultyMultForSlug(adminClient, slug)` (mirrors what the SQL RPC reads from `exercises.difficulty_mult`); added a `payload['difficulty_mult']` shape + value assertion to the bench parity test (Phase D `xp_events.payload` contract); added one new test "user-created exercise reads difficulty_mult column default 1.0 (COALESCE path)" using the production `fn_insert_user_exercise` RPC. 11/11 tests pass.
- [x] `test/integration/rpg_backfill_test.dart`: extended `ExerciseDef` with `difficultyMult` field (default 1.0 for non-breaking constructor); fixture's 3 entries now carry their curated values (bench 1.09, lat_pulldown 0.99, squat 1.19); `computeDartReference` reads `ex.difficultyMult` per set so the Dart sequential simulation matches `_rpg_backfill_chunk` (the test computes its own reference per-run, so no hardcoded final ranks/totals to update). 3/3 tests pass.
- [x] `test/integration/rpg_backfill_resume_test.dart`: inspected — the file has NO hardcoded XP totals or rank values. All assertions are either checkpoint behavior (e.g., `last_set_id` non-null after partial chunk), no-double-counting invariants (final ≥ intermediate), or comparison-against-reference-user / `computeDartReference` (which now mirrors per-slug multipliers via the fixture change). The only update needed was extending `kSmallFixture`'s `ExerciseDef` entries with the same per-slug `difficultyMult` values used by `kBackfillFixture`. 3/3 tests pass.
- [x] Floor/ceiling unit tests already exist in the Phase C semantic group (4 tests at `xp_calculator_test.dart` lines 398-517 — ceiling 1.25, floor 0.85, default 1.0 byte-parity, constants match). No new ones added; the brief asked to leave the Phase-C tests intact.
- [x] User-created (non-default) exercise unit/integration coverage: added the integration test described above. The unit-level coverage of "default 1.0 byte-parity with pre-24a chain" already lives in the Phase-C semantic group.

**Phase F verification (2026-05-14):**
- `dart format .` — 515 files, 0 changed (clean baseline)
- `dart analyze --fatal-infos` — `No issues found!`
- `flutter test --exclude-tags integration` — 2626/2626 pass
- `flutter test --tags integration test/integration/` — 35/35 pass (covers RPG record_set_xp, RPG backfill, RPG backfill resume, RPG vitality nightly + others)
- All 16 remaining `difficultyMult: 1.0` literals are intentional: (a) the 4 Phase-C semantic-pin tests; (b) Boundary + edge cases group's pure-formula tests at `xp_calculator_test.dart` 280-389 that hand-compute expected values with multiplier neutralized; (c) the one new integration test for the column-default 1.0 path.

#### Phase G — Verification gate (per CLAUDE.md → verification-before-completion)

- [ ] `make ci` clean (format + gen + analyze + test + android-debug-build)
- [ ] Integration tests pass against local Supabase: `make test-integration`
- [ ] E2E smoke run: `cd test/e2e && FLUTTER_APP_URL= npx playwright test --grep @smoke --reporter=list` — confirm no selector/text drift (24a is backend; expectation is zero E2E breakage)
- [ ] Migration applies cleanly to a fresh local Supabase: `npx supabase db reset` end-to-end

#### Phase H — Ship

- [ ] PR body includes `**QA pass pending — final coverage + E2E run after code review.**`
- [ ] After merge: apply migrations to hosted Supabase via `npx supabase db push`
- [ ] Verify `body_part_progress.total_xp` magnitude shift on a test user before declaring 24a done
- [ ] Condense Phase 24a section in PROJECT.md §4 (3-5 bullets); remove this WIP section

### Out of scope for 24a (defer to 24b/c/d)

- 30–50 new default exercises (Olympic variants, bodyweight progressions, machine gaps) — **24b**
- Bodyweight-as-load semantics (`effective_load = bodyweight + added`) — **24c**
- Six-profile × 12-week simulation gate + calibration sign-off — **24d**
- Retroactive replay of historical `xp_events` with new multipliers — **explicitly forward-only, never**
- UX surface for users to set difficulty on custom exercises — defer; default 1.0 is acceptable

### Notes on judgment calls (will be revisited)

- The framework doc names some exercises (e.g., farmers walk, plank) as
  explicit "judgment calls, not literature-derived for the exact tier
  boundary." The migration adopts the framework as-is for 24a; if 24d
  simulation surfaces a problematic outlier, the constant changes in 24d
  before launch.
- `xp_attribution_sum` helper at SQL is the model for adding constraint
  helpers, but difficulty_mult is a simple range so a plain CHECK is
  enough — no IMMUTABLE function needed.
