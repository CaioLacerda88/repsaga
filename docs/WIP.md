# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

## Phase 32 PR 32d — Analytics expansion (RPG + share + churn)

**Branch:** `feature/phase-32d-analytics-expansion`

**Source spec:** `docs/PROJECT.md` §3 Phase 32 → "PR 32d — Analytics expansion".

**Scope:** Add 5 typed analytics events to the existing `AnalyticsEvent`
sealed union + `analytics_events` table (free-form `name` + `props jsonb`,
no enum to update — see migration 00015) so the launch-phase funnel
gains RPG / share / churn signal. Paywall events explicitly deferred to
Launch Phase 16b.

Five new events:
1. `first_rank_up` — fires once per (user, body_part) on the user's first
   ever rank-up for that BP. Props: `{body_part, new_rank}`.
2. `post_session_cinematic_shown` — fires when the post-session screen
   mounts and the 3-beat cinematic begins. Props:
   `{total_xp, had_rank_up, had_title_unlock, had_class_change}`.
3. `share_card_exported` — fires on successful native share-sheet
   completion. Props: `{variant, had_custom_photo}`.
4. `title_unlocked` — fires per unlocked title in the post-session pipeline.
   Props: `{title_slug, workout_number}`.
5. `session_zero_xp` — fires when a workout is finished with zero
   completed sets (empty-session guard path). Props:
   `{exercise_count, elapsed_seconds}`.

### Boundary inventory — analytics emit + JSON round-trip

(Per CLAUDE.md "Boundary-trigger ripple check" — this PR adds 5 sealed-union
variants. Each variant adds a case in `.name` + `.props` switches; consumers
that pattern-match on the union must be exhaustive.)

- **AnalyticsEvent sealed union:** `lib/features/analytics/data/models/analytics_event.dart`
  L100–111 (`name` switch) and L115–210 (`props` switch). Both switches use
  `switch (this)` over sealed subclasses — Dart enforces exhaustiveness; new
  factories MUST update both. No other consumer pattern-matches on the union
  shape — `AnalyticsRepository.record(event)` only reads `event.name` +
  `event.props` polymorphically.
- **Repository contract:** `lib/features/analytics/data/analytics_repository.dart`
  → `record(AnalyticsEvent event)` — no signature change; inserts
  `{user_id, name, props, platform, app_version}` into `analytics_events`.
  No new column / no migration needed (props is free-form jsonb).
- **Existing emit sites (for pattern reference):**
  `active_workout_notifier.dart` L327, L447, L1176, L1557, L1814 — uses
  internal `_recordWorkoutEvent({required AnalyticsEvent event})` helper
  at L2001 that reads `analyticsRepositoryProvider` and forwards. New emit
  sites should mirror this read-from-ref pattern.
- **Post-session screen** does NOT currently emit any analytics
  (verified — zero matches for `analyticsRepository` / `AnalyticsEvent` in
  `post_session_screen.dart`). New event `post_session_cinematic_shown`
  needs a fresh `ref.read(analyticsRepositoryProvider).record(...)` call
  inside an `initState`-side-effect (post-frame) or a one-shot guard.
- **Share controller** L195–207 — `sharePreview` returns to `idle` on
  success and `unavailable`/throw → `error`. The `share_card_exported`
  event should fire ONLY on the success branch (result.status ==
  ShareResultStatus.success — not `dismissed` which still returns idle).
  `variant` derives from `ShareStatePreview.photo` (null = discreet,
  non-null = A or B — exact A vs B distinction lives in the preview
  screen's controller state, may need a small plumbing addition).
- **Title-unlock emit site:** `title_unlock_detector.dart` returns
  `List<Title>` to `CelebrationEventBuilder` (line 146 invocation pattern).
  Builder hands those to the post-session cinematic. Emit point = where the
  builder yields a `TitleUnlockEvent` to the queue (one event per title) —
  see `lib/features/rpg/domain/celebration_event_builder.dart`.
- **first_rank_up idempotency:** PROJECT.md §3 spec says "emitting the
  event a second time for the same (user_id, body_part) is a no-op". Three
  candidate impls — pick before coding:
  - **(A) Hive cache** `firstRankUpEmittedBPs:<user_id>` Set<String>.
    Pros: O(1) check, no DB round-trip. Cons: new device install loses
    state → may re-emit (acceptable for informational events).
  - **(B) Server query** `SELECT 1 FROM analytics_events WHERE
    user_id=$1 AND name='first_rank_up' AND props->>'body_part'=$2`.
    Pros: source-of-truth correct. Cons: extra read on every finish that
    detected a rank-up.
  - **(C) Hybrid** — Hive check first, fall back to server query on
    cache miss (writes to both on first emit).
  - **Decision (tech-lead):** start with (A) Hive-only. Rationale:
    informational event, occasional double-fire on new device is
    acceptable, avoids per-finish DB read. Document the trade-off in
    the emit-site comment so future agents understand why we're not
    server-querying.

### Files to create / modify

- [ ] **Modify** `lib/features/analytics/data/models/analytics_event.dart`
  - Add 5 `const factory` constructors with prop types matching the spec
  - Extend `.name` switch with 5 new cases (snake_case)
  - Extend `.props` switch with 5 new cases (snake_case prop keys)
- [ ] **Modify** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`
  - Emit `session_zero_xp` from the empty-session guard branch in the
    finish flow (the one that bails before `save_workout` runs). Reuse
    `_recordWorkoutEvent` helper. Compute `elapsed_seconds` from the
    same captured `_workoutStartedAt` already in scope.
- [ ] **Modify** `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart`
  - Emit `first_rank_up` per body-part rank delta (oldRank == 0 && newRank
    >= 1) on Hive-cache miss. Read body-part deltas from the
    `FinishWorkoutResult` (already plumbed for the cinematic).
  - Hive-cache key: `firstRankUpEmittedBPs:<user_id>` Set<String> of
    body-part slugs that fired.
- [ ] **Modify** `lib/features/workouts/ui/post_session/post_session_screen.dart`
  - Emit `post_session_cinematic_shown` once on mount (post-first-frame
    guard). Props derived from the in-scope `CelebrationQueue` snapshot:
    `had_rank_up = queue.events.any(_RankUpEvent)`,
    `had_title_unlock = queue.events.any(_TitleUnlockEvent)`,
    `had_class_change = queue.events.any(_ClassChangeEvent)`,
    `total_xp = result.totalXp`.
  - Use a `bool _analyticsFired = false` guard — Riverpod rebuilds must
    not double-fire.
- [ ] **Modify** `lib/features/workouts/providers/share_controller.dart`
  - In `sharePreview` success branch (`result.status ==
    ShareResultStatus.success` — NOT `dismissed`), emit
    `share_card_exported` with
    `{variant: <discreet|withPhoto>, had_custom_photo: photo != null}`.
  - `variant` from the captured `ShareStatePreview.photo` null-check at
    method entry. (A vs B distinction is screen-layer concern — if
    plumbing is light, pass via method param; if not, just emit
    `discreet` vs `with_photo` for v1 and refine later.)
  - Read `ref.read(analyticsRepositoryProvider)` — controller is already
    a Riverpod `Notifier` so `ref` is in scope.
- [ ] **Modify** `lib/features/rpg/domain/celebration_event_builder.dart`
  - For each `TitleUnlockEvent` queued, emit `title_unlocked` with
    `{title_slug, workout_number}`. `workout_number` plumbed from the
    finish result. `title_slug` from `Title.slug`.
  - Alternative emit site: the post-session screen iterates the queue
    and could emit there. Decide based on which has cleaner access to
    `workoutNumber` — the builder currently runs server-side-derived
    data, the screen has the full result. Likely screen-layer.
- [ ] **Create** N/A (no new files — all surgical edits to existing files
  + extending the existing test file)
- [ ] **No migration** (analytics_events table uses free-form `name` text +
  jsonb props — no enum to alter, see migration 00015 L7–15). Update PR
  description to flag the spec's mention of `0006Y_analytics_event_kinds_phase32.sql`
  as stale — no enum exists in the schema.

### Tests (extend `test/unit/features/analytics/data/models/analytics_event_test.dart`)

- [ ] `.name` group: 5 new cases asserting the snake_case event names
- [ ] `.props` group: 5 new cases asserting prop keys are snake_case + values
  match the constructor args
- [ ] Hive-cache idempotency unit test for `first_rank_up`:
  - Fake Hive box; first emit writes the BP slug + returns true (fired)
  - Second emit with same `(user_id, body_part)` short-circuits (no
    duplicate record call)
  - Different BP slug fires independently
- [ ] Coordinator emit test (`test/unit/features/workouts/.../finish_workout_coordinator_*_test.dart`):
  - Verify `session_zero_xp` emits when finish runs with zero completed sets
  - Verify `first_rank_up` emits only on Hive-cache miss
- [ ] Share controller emit test:
  - Verify `share_card_exported` emits on `ShareResultStatus.success`
  - Verify NO emit on `ShareResultStatus.dismissed` or exception path
  - Verify `had_custom_photo` reflects the preview photo state

### Verification

- `make ci` green
- E2E selector impact assessment only — no UI surface changes (analytics
  emissions are invisible to E2E). Skip new E2E specs per CLAUDE.md
  "visual-only / no flow change" rule.
- No visual verification (no UI surface added).

### Decisions captured

- **No migration** — `analytics_events.name` is free-form `text`. The
  PROJECT.md PR 32d spec listed `0006Y_analytics_event_kinds_phase32.sql`
  but the schema (00015) doesn't have an enum to alter. Strike that
  line item from the spec post-merge.
- **first_rank_up storage:** Hive cache (Option A above). Tradeoff
  comment in code at emit site.
- **share_card_exported variant granularity:** v1 emits `discreet` vs
  `with_photo` only. A-vs-B variant added in Launch Phase if signal
  proves load-bearing.
- **Paywall events:** explicitly deferred — `paywall_shown`,
  `paywall_converted`, `trial_started` ship with Launch Phase 16b
  (the sub-phase that adds the paywall screen itself).
