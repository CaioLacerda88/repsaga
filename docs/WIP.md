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

**State:** 26a + 26b + 26c + 26d shipped (PRs #232, #234, #236, #238 — see
PROJECT.md §4 for retrospectives). Two sub-phases remain (26e–f). Each gets
its own plan written via `superpowers:writing-plans` just before that
sub-phase starts, so each plan reflects the actual landed state of prior
sub-phases.

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

Re-invoke `superpowers:writing-plans` to draft 26d's plan against the
up-to-date codebase (now that 26c's `VolumePeakBlock` / `VitalityExplainerSheet`
/ HP-drain `VitalityTable` / per-body-part trend ghosts / `VolumeDeltaView` +
`PeakDeltaView` view-state factories / `VolumePeakRow` history fields are
live on `main`).
