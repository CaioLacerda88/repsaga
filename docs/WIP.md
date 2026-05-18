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

**Plan:** `docs/phase-26e-plan.md` (14 tasks, subagent-driven execution).

**Locked architectural decisions:**
- First-completion-wins: matching uncompleted entry → fill; otherwise append spontaneous (state 4).
- Week rollover: copy `isSpontaneous == false` entries only; spontaneous do NOT carry forward.
- Backfill (00062): all existing JSONB entries set to `is_spontaneous = false` (conservative).
- Set-counting math: per-set body part = max `xp_attribution` share; tied body parts each credited; strict equality.
- `weeklyEngagementProvider` parameter `{ includePlanned: bool }`.
- Engajamento section: 6 bars in canonical order, cardio HIDDEN, total counter REMOVED from header.
- `routine_id` MUST ride the `save_workout` payload (verified `workout_repository.dart:76-83` currently omits it; Task 3 plumbs it).
- Screen `plan_management_screen.dart` → `week_plan_screen.dart` (wholesale rename + rewrite); class `PlanManagementScreen` → `WeekPlanScreen`.

- [x] Task 1: Data model — `BucketRoutine.isSpontaneous`
- [x] Task 2: Migration 00062 — JSONB backfill
- [x] Task 3: Migration 00063 — `save_workout` find-or-create (+ Dart-side `routine_id` plumbing in `workout_repository.dart`)
- [x] Task 4: Drop client-side `markRoutineComplete`
- [x] Task 5: `WeeklyEngagement` domain + set-counting math
- [x] Task 6: `weeklyEngagementProvider`
- [x] Task 7: `BucketRoutineRow` widget
- [x] Task 8: `MuscleBarRow` widget + `EngajamentoSection`
- [x] Task 9: Engagement explainer bottom sheet
- [x] Task 10: `WeekPlanScreen` rewrite (+ 8 new l10n keys folded in)
- [x] Task 11: L10n keys — collapsed to gen-l10n verification (keys shipped in Task 10)
- [x] Task 12: Integration test for `save_workout` find-or-create
- [x] Task 13: E2E updates
- [x] Task 14: Visual verification (3-viewport screenshots vs mockup)

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
