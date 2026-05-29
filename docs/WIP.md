# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

## Phase 32 PR 32f — History screen redesign

**Branch:** `feature/phase-32f-history-redesign`

**Source spec:** `docs/PROJECT.md` §3 Phase 32 → "PR 32f — History screen redesign".

**Scope:** Redesign History list — sticky week headers (Monday-start, pt-BR locale-aware) with per-week roll-up (sets + `hotViolet` XP total); per-card XP eyebrow (`+N XP` in `hotViolet` `numericSmall`) + optional PR diamond (`◆ N PR` wrapped in `RewardAccent` for `heroGold` via the sanctioned scarcity scope, omitted when zero); workout detail screen gets a 52dp `surface2` header strip with `+N XP` (hotViolet) and `M PRs` (RewardAccent → heroGold) above the existing set-by-set log, hidden entirely when both aggregates are zero.

**Color-register split (locked post-PR-#285 review):** XP is the daily-driver progress metric — every workout produces XP, so it maps to `hotViolet` (structural-accent register). PR diamonds and the strip's PR span go through `RewardAccent`, the single sanctioned `heroGold` emitter. This preserves the reward-scarcity contract that `scripts/check_reward_accent.sh` enforces. Painting the per-card XP eyebrow gold would have made the entire feed read as "reward", eroding the dopamine payoff the palette is engineered to deliver.

### Boundary inventory (from Explore audit 2026-05-29)

**Target swap surfaces:**
- `lib/features/workouts/ui/workout_history_screen.dart` — currently `ListView.builder` (L93-110) wrapped in `RefreshIndicator`; scroll-listener triggers `loadMore()` at -200px (L37-46). Switch to `CustomScrollView` + `SliverList` + `SliverPersistentHeader` for sticky week headers.
- `_WorkoutHistoryCard` inline widget at L175-261 — renders title / exercise summary / duration / date / chevron. Add the XP eyebrow + PR diamond above the existing rows.
- `lib/features/workouts/ui/workout_detail_screen.dart` — already a `CustomScrollView` with `SliverAppBar(pinned: true)` + `SliverList` + `SliverToBoxAdapter` (L82-170). Add the 48dp `surface2` header strip via a new `SliverToBoxAdapter` between SliverAppBar and the exercise list.

**Sliver precedent in codebase:**
- `workout_detail_screen.dart` already uses slivers (precedent for the screen pattern)
- `routine_list_screen.dart` uses `CustomScrollView` + `SliverPadding` + `SliverToBoxAdapter` + `SliverList.builder`
- **NO `SliverPersistentHeader` / `SliverPersistentHeaderDelegate` precedent** — week header needs a fresh delegate class

**Workout model — MISSING aggregates (HIGH severity):**
- `lib/features/workouts/models/workout.dart` — has `id, userId, name, startedAt, finishedAt, durationSeconds, isActive, notes, exerciseSummary` (computed client-side), `createdAt`. **No `totalXp`, no `prCount`.**
- XP source: `xp_events.total_xp WHERE session_id = workouts.id` (SUM aggregation)
- PR source: `personal_records` joined to `sets → workout_exercises → workouts.id` (COUNT). Existing `workoutPRSetIdsProvider(workoutId)` provider already exists for the detail screen (`workout_detail_screen.dart:191`) — REUSE for the detail strip.

**Locale + week-start logic:**
- `lib/core/utils/weekday_formatter.dart` (Phase 32c) — `shortDayLabel(date, locale, {uppercase})` already exists with explicit `.toLocal()` per the weekday-utc-vs-local cluster. REUSE.
- **No existing "Monday of this week" function** — new pure utility needed.
- pt-BR uses Monday as ISO week start by default in `intl`. No override needed.

**E2E specs touching history:**
- DIRECT: `test/e2e/specs/history-localization.spec.ts` (1 spec, D1 scenario — asserts pt-localized exercise name renders in exerciseSummary). SAFE — only adds XP eyebrow above the existing row.
- REFERENCES: charter-a/b/c-exploratory, gamification-intro, manage-data, personal-records, rank-up-celebration, rpg-foundation, saga, workouts. None of these scroll the history list extensively.
- Existing `HISTORY` selectors in `helpers/selectors.ts:591-600`: `heading`, `emptyState`, `emptyStateCta`, `retryButton`. All SAFE.
- **NEW selectors needed:** `history-week-header`, `history-card-xp-eyebrow`, `history-card-pr-diamond`, `history-detail-strip`.

**Hidden coupling — verified safe:**
- Home `BucketChipRow` — week chips, not workout cards; no per-workout XP read needed. Untouched.
- Share card pipeline — XP comes from `PostSessionState.totalXpEarned` at finish time, not from history queries. Untouched.
- Offline sync — `evictHistoryCaches()` invalidates after offline save; the new aggregate path will pick up fresh data on the next load. No special handling.

### Decisions locked

- **Data dependency strategy: SQL aggregation via new RPC.** Single round-trip per page beats client-side N+1 lookups. New SQL function `get_workout_history_with_aggregates(p_user_id, p_limit, p_offset)` returns the existing history columns PLUS:
  - `total_xp INT` — `COALESCE(SUM(xp_events.total_xp), 0)` per workout
  - `pr_count INT` — `COUNT(*)` of `personal_records` joined via `sets → workout_exercises → workouts`
  - Migration `00070_get_workout_history_with_aggregates.sql` (next number after 00069)
  - `SECURITY INVOKER` + RLS-scoped JOIN (caller passes `auth.uid()` indirectly via `workouts.user_id` filter)
  - Test: query the function with a seeded fixture, assert aggregates match expected XP / PR counts
- **Workout model gains `totalXp` + `prCount` as required fields** with `@JsonKey(name: 'total_xp')` + `@JsonKey(name: 'pr_count')`. Both backed by the new RPC; default 0 if upstream legacy paths still hit the old `select`.
- **`getWorkoutHistory()` rewires to call the new RPC.** Existing per-workout name resolution stays (exercises name map still resolved client-side via the existing 2-query merge — the new RPC returns workouts + their workout_exercises ID list, then the locale name resolution runs after).
- **Detail screen XP source:** the existing `workoutPRSetIdsProvider` returns PR set IDs (used for the gold ring on individual set rows). For the new 48dp strip's total counts, reuse it (the count is `.length`); XP comes from the same RPC call enriched in the detail fetch OR a separate `get_workout_xp(workout_id)` mini-RPC. Cleaner: bundle XP into the detail fetch too via `get_workout_detail_with_xp` RPC or augment the existing detail-fetch return.
- **`workout_history_grouping.dart` — pure function.** Takes `List<Workout>` + locale string, returns `List<({DateTime weekStart, List<Workout> workouts, int totalSets, int totalXp})>`. ISO week start = Monday at 00:00 local. Deterministic order (most recent week first).
- **`history_week_header.dart` — new widget.** Receives `weekLabel` string + roll-up tuple. Renders 48dp pinned header: week label (`AppTextStyles.eyebrow`) + roll-up `"N sets · M XP"` (XP in `heroGold` `numericSmall`). Uses `SliverPersistentHeader(pinned: true, delegate: _WeekHeaderDelegate)`.
- **`_WeekHeaderDelegate` — `SliverPersistentHeaderDelegate` subclass.** `minExtent == maxExtent == 48`. `shouldRebuild` compares week start + roll-up totals.
- **PR diamond — omit when zero.** Per UX-critic "no empty placeholders" — the row collapses entirely (no "0 PRs" rendered).
- **Per `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`:** all reviewer findings fix in cycle.

### Files to create

- [ ] `supabase/migrations/00070_get_workout_history_with_aggregates.sql` — new SQL function returning history rows + `total_xp` + `pr_count` aggregates. Apply post-merge per CLAUDE.md step 12.
- [ ] `lib/features/workouts/domain/workout_history_grouping.dart` — pure function `groupByIsoWeek(List<Workout>, String locale) → List<WeekGroup>` with deterministic week ordering. Co-located `WeekGroup` typedef with `weekStart`, `workouts`, `totalSets`, `totalXp`.
- [ ] `lib/features/workouts/ui/widgets/history_week_header.dart` — `HistoryWeekHeader` widget + `_WeekHeaderDelegate` (`SliverPersistentHeaderDelegate`). 48dp pinned. Semantics identifier `history-week-header`. Localized strings as constructor params (per `feedback_widget_l10n_parameterization`).
- [ ] **Tests** — see "Tests to add" below

### Files to modify

- [ ] `lib/features/workouts/models/workout.dart`
  - Add `@JsonKey(name: 'total_xp', defaultValue: 0) required int totalXp` field
  - Add `@JsonKey(name: 'pr_count', defaultValue: 0) required int prCount` field
  - Regen freezed via `make gen`
- [ ] `lib/features/workouts/data/workout_repository.dart`
  - `getWorkoutHistory()` (L188-276): rewire from `workouts.select(...)` to the new RPC. Keep the 2-query merge for name resolution (RPC returns workouts + workout_exercises ID list; name resolution runs after).
  - `getWorkoutDetail()` (L345-368): augment to include the totalXp aggregate. Either call the new RPC for detail OR a separate `get_workout_xp(workout_id)` mini-RPC — tech-lead picks cleaner.
  - `_workoutFromHistoryRow()` (L251 area): parse the new `total_xp` + `pr_count` fields into the Workout model.
  - Cache key unchanged (`'<userId>:<locale>'`).
- [ ] `lib/features/workouts/ui/workout_history_screen.dart`
  - Replace `ListView.builder` (L93-110) with `CustomScrollView` + `SliverList` + interspersed `SliverPersistentHeader` per week group
  - Drive grouping via `workout_history_grouping.dart`
  - Preserve scroll-listener for `loadMore()` (slivers respect ScrollController same as ListView)
  - Preserve `RefreshIndicator` wrapping (still works around `CustomScrollView`)
  - Preserve empty-state branch (unchanged — no week headers when zero workouts)
- [ ] `lib/features/workouts/ui/workout_history_screen.dart` `_WorkoutHistoryCard` (L175-261)
  - Add XP eyebrow row ABOVE the title — `Text(l10n.historyCardXpEyebrow(workout.totalXp))` painted with `AppTextStyles.numericSmall.copyWith(color: AppColors.hotViolet.withValues(alpha: 0.85))` (NOT heroGold — reward-scarcity rule, see PR #285 Blocker 4)
  - Add PR diamond row (rendered only when `workout.prCount > 0`) wrapped in `RewardAccent` so the heroGold color flows through the sanctioned scope rather than a raw token reference (PR #285 Blocker 5)
  - Add Semantics identifiers `history-card-xp-eyebrow` + `history-card-pr-diamond`
- [ ] `lib/features/workouts/ui/workout_detail_screen.dart`
  - Insert a new `SliverToBoxAdapter` BETWEEN the existing `SliverAppBar(pinned: true)` and the first content sliver
  - 48dp height, `surface2` background
  - `Text.rich` with two spans: XP in `hotViolet` (daily-driver), PR span rendered only when `prCount > 0` and wrapped in `RewardAccent` for heroGold via the scarcity scope
  - PR count reads from `workout.prCount` (RPC source of truth) — NOT from `workoutPRSetIdsProvider.length`. The PR provider is still used for the gold-ring on individual set rows (different purpose). Single source of truth per PR #285 Important 8.
  - Hidden entirely when `totalXp == 0 && prCount == 0` (PR #285 Important 7 — no negative-confirmation `+0 XP · 0 PRs` strip)
  - Semantics identifier `history-detail-strip`
- [ ] `lib/l10n/app_en.arb` + `app_pt.arb`
  - `historyWeekLabel(date)` — e.g. EN: `"Week of {date}"`, pt-BR: `"Semana de {date}"`
  - `historyWeekRollup(sets, xp)` — e.g. EN: `"{sets} sets · {xp} XP"`, pt-BR: `"{sets} séries · {xp} XP"`
  - `historyCardXpEyebrow(xp)` — e.g. EN: `"+{xp} XP"`, pt-BR: `"+{xp} XP"`
  - `historyCardPrCount(count)` — e.g. EN: `"◆ {count} PR"`, pt-BR: `"◆ {count} PR"`
  - `historyDetailStrip(xp, prs)` — e.g. EN: `"+{xp} XP · {prs} PRs"`, pt-BR: `"+{xp} XP · {prs} PRs"`
- [ ] `test/e2e/helpers/selectors.ts` (L591-600)
  - Add `HISTORY.weekHeader`, `HISTORY.cardXpEyebrow`, `HISTORY.cardPrDiamond`, `HISTORY.detailStrip` selectors using the new identifiers

### Tests to add

- [ ] **Unit (`test/unit/features/workouts/domain/workout_history_grouping_test.dart`):**
  - Grouping function with workouts spanning 2 weeks → 2 groups, most-recent-first ordering
  - Empty input → empty list
  - All workouts in same week → 1 group with correct roll-up totals
  - Workout at week boundary (Sunday 23:59 local) → grouped with the week it falls in (Sunday IS week-end per Monday-start ISO)
  - Locale + DateTime UTC vs local: feed a UTC DateTime that crosses a day boundary in pt-BR → assert the workout is grouped per the BRT local week, not UTC
- [ ] **Widget (`test/widget/features/workouts/ui/workout_history_screen_test.dart`):**
  - Pump 7 workouts across 2 weeks → assert 2 sticky `history-week-header` widgets render
  - Card eyebrow renders `+N XP` in heroGold for each workout
  - PR diamond renders only when `prCount > 0` (negative pin: no widget when prCount == 0)
  - Empty state still works (no week headers)
- [ ] **Widget (`test/widget/features/workouts/ui/widgets/history_week_header_test.dart`):**
  - Header renders week label + roll-up
  - Delegate `shouldRebuild` returns true on totals change, false on identity
- [ ] **Widget (`test/widget/features/workouts/ui/workout_detail_screen_test.dart`):**
  - 48dp `history-detail-strip` renders above first exercise card
  - Strip shows `+N XP · M PRs` with correct values
  - Strip absent (or `+0 XP · 0 PRs`) when both aggregates are zero — tech-lead picks; UX-critic likely "render with zeros so the strip's vertical rhythm doesn't jump"
- [ ] **E2E (`test/e2e/specs/history-localization.spec.ts` extension):**
  - One smoke test: assert `HISTORY.weekHeader` is visible after the list loads
  - One smoke test: assert at least one `HISTORY.cardXpEyebrow` is visible
  - Don't pin specific XP values (they're seed-dependent and flake-prone)

### Verification

- `make ci` green
- E2E smoke green
- **Visual verification on physical Android REQUIRED** (CLAUDE.md step 9):
  - Sticky week headers stay pinned during scroll
  - XP eyebrow + PR diamond render correctly at 320dp / 360dp / 412dp
  - PR diamond omitted when zero; week header still readable
  - Detail screen 48dp strip aligns with the AppBar's bottom edge
  - Screenshot each surface at all 3 viewports; attach to PR thread

### Out of scope

- Drag-to-sort, manual workout reordering — not asked for
- Detail screen redesign beyond the 48dp strip — keep the existing set-by-set log intact
- Cross-week trend chart (vitality / strength) — handled by Stats deep-dive
- iOS scope (Android-first launch)
- Backfill of `total_xp` / `pr_count` to legacy `xp_events` data — the aggregation runs on-demand in the RPC, no migration of historical rows
