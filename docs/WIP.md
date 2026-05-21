# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Pre-compact state snapshot — 2026-05-21

Two phases in flight: Phase 29 (XP formula v2) actively building, Phase 30 (post-session screen) plan locked + awaiting user authorization.

### ✅ Shipped to main (the typography saga is DONE)

| PR | What |
|---|---|
| `#244` | Phase 27 post-26f bug-fix sweep |
| `#245` | Phase 27 L18.4 typography sweep + CI gate |
| `#246` | docs: Phase 27 condense + QA coverage |
| `#247` | docs cleanup: prune stale phase artifacts + Phase 26 mockup HTML |
| `#248` | Phase 28a typography foundation (CI gates × 5, 3 new tokens, property pins, dartdoc prescription) |
| `#249` | Phase 28b Barlow swap + 216-site textTheme migration + narrowed `_textTheme` shim |
| `#250` | sub-bar XP fraction format (`54/107 XP` color-split) |
| `#251` | **Phase 29 PR 1** — Python sim consolidation (Phase 29 v2 baseline locked, 13/13 personas PASS, fixture deliberately NOT regenerated to preserve 4-site parity) |

Branch state: `main` is at PR #251 squash-merge.

### 🟢 In flight — Phase 29 PR 2 (SQL + Dart + fixture regen + parity tests)

**Branch:** `feature/29-pr2-sql-dart-port` off `main`.

**Status:** Code complete. `make ci` green (format + lint scripts + analyze + 3004 unit/widget tests passing + Android debug APK build). Awaiting PR open + review.

**Migration filename:** `supabase/migrations/00065_phase29_xp_formula_v2.sql` (00060 was already taken by `00060_titles_award_at_detection.sql`; the next free slot was 00065).

**Shipped:**
- `test/fixtures/rpg_xp_fixtures.json` regenerated as Phase 29 v2 oracle. 94 set_xp_v2 + 17 implied_tier + 12 abs_strength_premium + 17 tier_diff_mult + 7 overload_mult + 7 frequency_mult + 7 near-failure cases. Legacy 6-multiplier component lists preserved for Dart unit-test parity.
- `lib/features/rpg/domain/implied_tier.dart` — NEW pure module. Per-lift × per-gender Symmetric Strength tables (6 families × 2 genders), Brzycki 1RM, per-exercise variant discount. `LiftGender` enum (separate from `Profile.Gender` to keep rpg/domain feature-pure).
- `lib/features/rpg/domain/xp_calculator.dart` — Phase 29 v2 11-multiplier chain. New constants: `kEBonus`, `kEFloor`, `kECeil`, `kNfIntensityBonus`, `kNfTargetThreshold`, `kFrequencyMultTable`. New helpers: `intensityWithNearFailure`, `nearFailureInferred`, `overloadMult`, `frequencyMult`. `computeSetXp` gains 6 optional params with neutral defaults — keeps existing integration test call sites compiling without churn.
- `lib/features/rpg/domain/rank_curve.dart` — piecewise. `xpGrowthBreakpoint = 20`, `linearXpPerRank = 367.0` (LITERAL, not derived).
- `lib/features/profile/models/profile.dart` — added `Gender? gender` field (`@JsonValue('male'|'female'|'other')`).
- `lib/features/exercises/models/exercise.dart` — added `double bodyweightLoadRatio` (default 1.0).
- `lib/core/local_storage/hive_service.dart` — `currentCacheSchemaVersion: 1 → 2` (forces clients to refetch exercises with the new `bodyweight_load_ratio` column).
- `lib/features/profile/data/profile_repository.dart` — `upsertProfile(... Gender? gender)`.
- `supabase/migrations/00065_phase29_xp_formula_v2.sql` — schema (gender + bodyweight_load_ratio + exercise_peak_loads_by_rep_range table with RLS), 8 helper functions (`rpg_rep_band`, `rpg_cumulative_xp_for_rank` REPLACED piecewise, `rpg_implied_tier_for_exercise`, `rpg_tier_diff_mult`, `rpg_abs_strength_premium`, `rpg_overload_mult`, `rpg_frequency_mult`, `rpg_near_failure_inferred`), all three RPCs (`record_set_xp` / `record_session_xp_batch` / `_rpg_backfill_chunk`) rewritten for the 11-multiplier chain + per-band peak maintenance, end-of-migration `UPDATE body_part_progress SET rank = rpg_rank_for_xp(total_xp)` + DO-block sanity asserts. Applied cleanly to local Supabase; helper smoke-tests match fixture values.
- Tests: `xp_calculator_test.dart` adds Phase 29 v2 constants parity + abs_strength_premium / tier_diff_mult / overload_mult / frequency_mult / near_failure_inferred fixture-driven groups + 94-row set_xp_v2 per-bp parity at 1e-4. `rank_curve_test.dart` rewires for piecewise milestones. New `test/unit/features/rpg/domain/implied_tier_test.dart` (fixture parity + gender NULL fallback + variant discount + persona pins). New `test/unit/features/rpg/domain/phase29_formula_parity_test.dart` (top-level row-count + meta-key invariants — fails fast if a fixture section gets dropped).

**Carry-forward to PR 3 (docs):**
- `target_reps` column does not yet exist on `sets`. SQL RPCs default `v_target_reps := NULL` → near_failure always inferred FALSE on the server. Helper is wired; the active-workout UI signal is a follow-up. Documented in the migration header + record_set_xp inline comment.
- Documentation updates (xp-difficulty-framework, xp-balance-baseline, rpg-design §6) deferred to PR 3 per the brief.

### ⏳ Queued — Phase 29 PR 3 (docs + auto-memory)

Dispatches when PR 2 merges. Updates: `docs/xp-difficulty-framework.md` Phase 29 sections (§7-§13), `docs/xp-balance-baseline.md` regenerate with 13-persona v2 baseline, `docs/rpg-design.md` §6 piecewise curve update, NEW auto-memory `project_xp_formula_v2.md`, PROJECT.md §3 entry → §4 condensation.

### ⏸️ Held — Phase 30 (post-session "after-battle" screen)

**Status:** Concept B locked + all 11 design questions resolved + 3-PR decomposition chosen. **User reviewing implementation plan before tech-lead dispatch.**

**Mockup:** `docs/post-session-screen-mockup.html` (in main since PR #251 swept it in incidentally).

**3-PR decomposition** (when user authorizes):
- PR 30a: post-session screen + state machine + 7 cut widgets (XpCut/BodyPartCut/PRCut/RankUpCut/LevelUpCut/ClassChangeCut/TitleCut/SummaryPanel) + router + finish_workout_coordinator wiring + tests
- PR 30b: share card (offscreen 1080×1920 RepaintBoundary + share_plus 9:16 + golden test)
- PR 30c: deprecate `pr_celebration_screen.dart` + migrate E2E selectors/widget tests

**Resume condition:** User comes back with "dispatch PR 30a" / "adjust X" / "park entirely".

---

## Compact-restore checklist

When restoring after `/compact`:

1. Re-read this WIP.md FIRST
2. Check Phase 29 PR 2 status: `gh pr list --search "Phase 29"` or look for new PR opened by agent `a2baf22c9bc3f0f1d`
3. Check task list — Phase 29 task #24 is `in_progress`; Phase 30 task #26 is `pending` awaiting user authorization
4. Read auto-memory `project_phase_29_v2_formula.md` for the locked formula spec
5. Read auto-memory `feedback_pr_decomposition_parity_invariant.md` for the PR-1-failure lesson
6. If user is ready to resume Phase 30: read `docs/post-session-screen-mockup.html` + the Phase 30 task description
7. If Phase 29 PR 2 already landed and merged: dispatch Phase 29 PR 3 (docs)

## Active background processes

None at compact time — the PR 251 merge watcher (`bu6lt2mpg`) already fired and completed. The Phase 29 PR 2 agent (`a2baf22c9bc3f0f1d`) is harness-tracked (you'll be notified when it completes).
