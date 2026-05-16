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

**State:** 26a shipped (PR #232 — see PROJECT.md §4 for retrospective). Five
sub-phases remain (26b–f). Each gets its own plan written via
`superpowers:writing-plans` just before that sub-phase starts, so each plan
reflects the actual landed state of prior sub-phases.

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

### Next step

Re-invoke `superpowers:writing-plans` to draft 26b's plan against the up-to-date codebase (now that 26a's tokens + helper + map rebind are live on `main`).
