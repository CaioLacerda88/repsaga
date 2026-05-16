# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 26 — Pre-launch UI/UX Revamp

**Reference:** `docs/PROJECT.md §3 Phase 26` (authoritative spec) +
`docs/phase-26-mockups.html` (visual companion).

**State:** Spec written. Awaiting user review before handing off to
`writing-plans` for the implementation-plan generation. Six sub-phases
locked; ~17–22 dev days estimated total. Six sub-phase branches will be
opened in dependency order (26a first, since it adds the tokens everything
else consumes).

### 26a — Color system foundation

Branch: `feature/26a-color-system-foundation`

- [ ] Add `AppColors.xpTrack` = `Color(0x1AB36DFF)` to `lib/core/theme/app_theme.dart`
- [ ] Add `AppColors.bodyPartChest` = `Color(0xFFF472B6)` (pink-400) — frees hotViolet from chest identity
- [ ] Add `AppColors.bodyPartBack` = `Color(0xFF38BDF8)` (sky)
- [ ] Add `AppColors.bodyPartCardio` = `Color(0xFFFB923C)` (orange, infrastructure-only)
- [ ] Add `AppColors.vitalityHigh / vitalityMid / vitalityLow` semantic aliases
- [ ] Update `VitalityStateStyles.bodyPartColor[BodyPart.chest]` to read `bodyPartChest`
- [ ] Update `VitalityStateStyles.bodyPartColor[BodyPart.back]` to read `bodyPartBack`
- [ ] Add `VitalityStateStyles.vitalityRampColorFor(double pct)` helper
- [ ] Whitelist heroGold on `EquippedTitleCard` + `CrossBuildCard` in `scripts/check_reward_accent.sh`
- [ ] Fix `vitalityCopyDormant` l10n (en + pt) — currently describes Untested state, repurpose for Dormant
- [ ] Add l10n keys: `vitalityStateBandActive` ("Ativo" / "Active"), `vitalityStateBandEsmorecendo` ("Esmorecendo"), `vitalityStateBandDormente` ("Dormente"), `withinRankXpSuffix` ("para o próximo rank")
- [ ] Drop unused vitality-state row-level marginalia copy keys (caminho esfriando / Path mastered)
- [ ] Unit tests for `vitalityRampColorFor` boundary cases (0.0, 0.33, 0.34, 0.65, 0.66, 1.0, null)
- [ ] Golden tests for the four new tokens on `AppColors.abyss` (contrast assertion)

### 26b — Saga screen revamp

Branch: `feature/26b-saga-option-b-v4`

- [ ] Restructure `lib/features/rpg/ui/character_sheet_screen.dart` to Option B v4 layout
- [ ] Rewrite `lib/features/rpg/ui/widgets/body_part_rank_row.dart` (full-width XP bar + within-rank label)
- [ ] Update `lib/features/rpg/ui/widgets/rune_halo.dart` — drop active-state glow, 36dp sizing for header
- [ ] New: `lib/features/rpg/ui/widgets/rank_up_pulse.dart` (24h dot pulse animation)
- [ ] New: `lib/features/rpg/data/rank_up_pulse_repository.dart` (Hive-backed map<bodyPart, dateUntil>)
- [ ] Stat-row tap → routes to `/saga/stats` with `?body_part=X` query
- [ ] Body-part-row visual states: untrained / trained / just-rank-up'd
- [ ] Header at 320/360/412dp: ellipsis on `b-meta` for long class/title
- [ ] Update `_CharacterSheetSkeleton` shape for the new layout
- [ ] Update `test/e2e/specs/rpg-saga.spec.ts` selectors for new structure
- [ ] Widget tests: header layout (3 breakpoints golden); body-part-row state variants; rank-up pulse 24h expiry; stat-row tap routing

### 26c — Stats deep-dive

Branch: `feature/26c-stats-deep-dive`

- [ ] Update `lib/features/rpg/ui/stats_deep_dive_screen.dart`: 3-section layout (Peak Loads dropped)
- [ ] `_SectionHeader` gets 12dp bottom padding (fixes trend overlap)
- [ ] Update `lib/features/rpg/ui/widgets/vitality_trend_chart.dart`: selected line 2.5dp/100%, others 1dp/35%, 180ms tap tween
- [ ] Update `lib/features/rpg/ui/widgets/vitality_table.dart`: HP-ramp coloring; drop fading/radiant marginalia
- [ ] New: `lib/features/rpg/ui/widgets/volume_peak_block.dart` per-body-part two-column block
- [ ] New: `lib/features/rpg/ui/widgets/vitality_explainer_sheet.dart` (ⓘ tooltip)
- [ ] DELETE: `lib/features/rpg/ui/widgets/peak_loads_table.dart`
- [ ] Extend `lib/features/rpg/providers/stats_provider.dart` with weekly volume/delta + 30D EWMA delta math
- [ ] Volume delta adapts to history: weeks 0–1 → none; 2–4 → vs semana passada; 5+ → vs média (4 sem)
- [ ] Over-target uses `warning` amber (not green) — locked decision
- [ ] Generic-tip fallback: REFERÊNCIA label + ⓘ estimado badge (10 sets/wk Schoenfeld floor)
- [ ] Widget tests: vitality table boundary %s; trend chart line emphasis; volume/peak block edge cases; ⓘ sheet opens

### 26d — Titles screen + awarding pipeline bug fix

Branch: `feature/26d-titles-bug-fix`

- [ ] `supabase/migrations/00060_titles_award_at_detection.sql` — extend `record_set_xp` + `record_session_xp_batch` RPCs with `INSERT INTO earned_titles ... ON CONFLICT DO NOTHING` at rank-threshold crossings
- [ ] `supabase/migrations/00061_backfill_earned_titles.sql` — one-shot `backfill_earned_titles(user_id uuid)` RPC walking xp_events
- [ ] Bootstrap hook: call backfill on first app open post-deploy per user (feature-flag-gated)
- [ ] `lib/features/rpg/data/titles_repository.dart`: `equipTitle` simplifies to is_active toggle only
- [ ] `lib/features/rpg/ui/titles_screen.dart` rewrite for three-region layout (Equipado / Conquistados / Próximos)
- [ ] New: `lib/features/rpg/ui/widgets/equipped_title_card.dart` (heroGold gradient)
- [ ] New: `lib/features/rpg/ui/widgets/earned_title_row.dart`
- [ ] New: `lib/features/rpg/ui/widgets/next_title_row.dart` (rank progress bar)
- [ ] New: `lib/features/rpg/ui/widgets/cross_build_card.dart` (heroGold treatment, ESPECIAL badge)
- [ ] Locked titles hidden entirely (no "Ver todos" link)
- [ ] Regression test (e2e): workout → dismiss celebration overlay → re-open Titles → earned row visible
- [ ] Integration test: backfill RPC idempotency
- [ ] Update `test/e2e/specs/titles.spec.ts` for new layout
- [ ] Title names in `assets/rpg/titles_v1.json` UNCHANGED for this phase

### 26e — Plan editor + bucket model evolution

Branch: `feature/26e-bucket-spontaneous`

- [ ] Add `isSpontaneous: bool` (default false) to `BucketRoutine` in `lib/features/weekly_plan/data/models/weekly_plan.dart`
- [ ] Freezed regen, generated files updated
- [ ] `supabase/migrations/00062_weekly_plan_is_spontaneous_backfill.sql` — backfill existing JSONB entries
- [ ] `supabase/migrations/00063_save_workout_bucket_update.sql` — extend save_workout RPC: find-or-create bucket entry for the completed workout
- [ ] First-completion-wins logic: if matching uncompleted entry exists, fill it; otherwise create spontaneous
- [ ] Update `lib/features/weekly_plan/data/weekly_plan_repository.dart` for the new logic + week rollover (copy isSpontaneous=false entries, clear completion)
- [ ] Rewrite `lib/features/weekly_plan/ui/week_plan_screen.dart` as compact ordered list (drop day rows)
- [ ] New: `lib/features/weekly_plan/ui/widgets/bucket_routine_row.dart`
- [ ] New: `lib/features/weekly_plan/ui/widgets/engajamento_section.dart` (6 body-part bars, cardio hidden)
- [ ] New: `lib/features/weekly_plan/providers/weekly_engagement_provider.dart` with `{ includePlanned: bool }` parameter
- [ ] Set-counting rule per locked decision: primary by max XP share, ties counted, strict equality
- [ ] ⓘ on Engajamento header → set-counting explainer bottom sheet
- [ ] Update `test/e2e/specs/weekly-plan.spec.ts` for new layout + spontaneous flow
- [ ] Unit tests: save_workout find-or-create (planned hit / no match / duplicate / multi-workout-same-day)
- [ ] Integration test: save_workout → bucket update
- [ ] Engajamento math tests: compound tie counting, abandoned body part

### 26f — Home redesign

Branch: `feature/26f-home-character-card`

- [ ] Rewrite `lib/features/workouts/ui/home_screen.dart` for new structure
- [ ] New: `lib/features/workouts/ui/widgets/character_card.dart` (collapsed + expanded states, animated)
- [ ] Expanded state hides the closest-rank-up indicator (locked decision)
- [ ] State NOT persisted across launches (always opens collapsed)
- [ ] Stat rows in expanded state tappable → `/saga/stats?body_part=X`
- [ ] New: `lib/features/workouts/ui/widgets/bucket_chip_row.dart`
- [ ] New: `lib/features/workouts/ui/widgets/encouragement_nudge.dart` (rotating-priority logic)
- [ ] DELETE: `lib/features/workouts/ui/widgets/week_bucket_section.dart` (7-day timeline)
- [ ] DELETE: `lib/features/workouts/ui/widgets/home_status_line.dart`
- [ ] ActionHero adapts to bucket state (next-uncompleted / livre / criar-rotina)
- [ ] "Editar plano →" always visible (even empty bucket)
- [ ] Closest-rank-up logic: smallest absolute "XP to next rank" gap
- [ ] Update `test/e2e/specs/home.spec.ts` selectors throughout
- [ ] Widget tests: char-card expand/collapse; closest-rank-up boundary cases; bucket chip state variants; rotating-nudge priority

### Cross-cutting (any sub-phase)

- [ ] Verification: full `make ci` green before opening each sub-phase PR
- [ ] E2E selectors: update `test/e2e/helpers/selectors.ts` as widgets gain new semantic identifiers
- [ ] L10n: every new string lands in both `app_en.arb` and `app_pt.arb`
- [ ] Reviewer + QA per CLAUDE.md pipeline; no deferrals (`feedback_no_deferring_review_findings`)

### Out of scope (deferred to v1.1)

- Cardio visibility on rank surfaces (Saga, Stats, Home rank rail, Engajamento) — token ships in 26a, rendering deferred
- ⓘ parity tooltips on Volume & pico header + Saga character XP bar
- Auto-reflow algorithm for missed planned routines (rejected — bucket has no day binding)

### Resume context (post-compact) — 2026-05-15

**Where we are:**
- Phase 26 brainstorming complete. Spec in `docs/PROJECT.md §3 Phase 26`. Visual reference in `docs/phase-26-mockups.html`. Scratch dir `.superpowers/brainstorm/` emptied.
- **Phase 26a plan written** to `docs/phase-26a-plan.md` (9 tasks, TDD bite-size). User said "be very cautious" — plan reflects that.
- **26b–26f plans NOT YET WRITTEN** — by design, one plan per sub-phase, written before each sub-phase starts (so plans reflect actual landed state of prior sub-phases).
- Memory updated with 4 new entries: `project_rpg_thesis`, `project_phase_progression`, `project_design_language_brand_vs_identity`, `user_visual_iteration_style`. MEMORY.md gained Project + User sections.

**Open question to ask user after resume:**
Which execution mode for 26a?
1. **Subagent-Driven** (recommended for "be very cautious" — fresh subagent per task, review between tasks)
2. **Inline Execution** (executing-plans skill, batched checkpoints)

**Next steps when resumed:**
1. Ask user execution mode → 1 or 2.
2. Branch: `feature/26a-color-system-foundation` (per the 26a plan header).
3. Execute Task 1 → Task 9 per `docs/phase-26a-plan.md`.
4. PR → reviewer → QA → merge per CLAUDE.md pipeline.
5. After merge: condense 26a in PROJECT.md §4, remove from WIP, re-invoke `superpowers:writing-plans` for 26b plan.

**Critical real bug discovered during brainstorming** (now in 26d scope, not 26a): `earned_titles` is INSERTed only at equip-time, so dismissing the celebration overlay permanently loses the title. Fix is server-side INSERT at detection-time + one-shot backfill RPC. Don't lose track of this.
