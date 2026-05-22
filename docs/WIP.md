# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.


---

## Phase 30 · Implementation Plan

> Canonical spec: `docs/post-session-screen-mockup-v2.html` (Round 2, all 11 states + thin-flash mid-workout overlays + photo-overlay share card + 6 implementation gaps). Mockup is locked; do not deviate without surfacing via the "Open questions" subsection.
>
> Decomposed into **4 PRs**: 29.5 (mid-workout overlay redesign — MUST land first), 30a (post-session screen + state machine + summary panel + finish-coordinator wiring), 30b (share card pipeline), 30c (cleanup + deprecate `pr_celebration_screen.dart` + E2E migration + docs + **test-hygiene audit** absorbing the 3 remaining audit candidates).
>
> Status (2026-05-22): **Phase 29 fully shipped** (PR #251 sim consolidation, PR #252 SQL + Dart port + parity fixes, PR #253 docs refresh — all merged; migration `00065_phase29_xp_formula_v2.sql` applied to hosted Supabase). **Ready to dispatch PR 29.5 to tech-lead.**

### PR 29.5 — Path A pivot: retire mid-workout flash layer entirely

> **Path A pivot (2026-05-22).** The original PR 29.5 plan below specced a `thin_flash_overlay.dart` to replace the 5 legacy mid-workout overlays with a Concept-B-conformant hue-flash. On-device verification (Galaxy S25 Ultra, PR 29.5 review pass 3) surfaced that the flashes fire ~200ms before the Phase 30 post-session cinematic ceremony mounts — same moment, same attentional context. The mockup §4½ "dual-loop" thesis only holds with TRUE per-set firing; the architecture only supports session-finish emission. Without per-set firing the flash layer is redundant pre-roll for the cinematic that fires 4 seconds later.
>
> **Decision:** kill the flash layer entirely. The post-session screen (PR 30a, Beats 1–5) carries the full celebration for ALL events. PR 29.5 retires the 5 legacy widgets + scaffolds `CelebrationEvent.personalRecord` + `SlotPolicy` enum that PR 30a will consume. The plan below is preserved as the historical record of what was shipped before the pivot.
>
> See `docs/post-session-screen-mockup-v2.html` §4½ (Path A pivot section) for the full rationale.

**Branch:** `feature/29.5-thin-flash-overlay` off `main` (PRs #252 + #253 already merged; no rebase needed).

**Boundary inventory** (per CLAUDE.md boundary-trigger ripple check; locked before implementation)

This PR crosses four boundaries. Each is exhaustively enumerated below so reviewers can audit the blast radius without re-running the grep.

1. **`CelebrationEvent` sealed union shape** (`lib/features/rpg/models/celebration_event.dart`)
   - Adding `CelebrationEvent.personalRecord({String exerciseId, String exerciseName, num weight, int reps, num? priorBest})` variant. **Deviation from WIP `exerciseSlug` field name**: the `Exercise` model carries `id` (UUID), not `slug`. Using `exerciseId` keeps the carrier honest about what it transports; later post-session navigation maps id → screen the same way an exercise slug would. Flag in hand-off.
   - All existing variants unchanged.
   - Freezed exhaustive switches will fail compilation in every consumer until `personalRecord` is handled. Consumers identified:
     - `lib/features/rpg/domain/celebration_queue.dart` — switch in `build()` bucketing loop
     - `lib/features/rpg/ui/celebration_player.dart` — switch in `_playOverlay` builder + barrier color
     - `lib/features/rpg/ui/overlays/thin_flash_overlay.dart` (NEW) — switch in render
     - any existing tests that build `CelebrationEvent` instances by variant: none directly switch over the union in test code.

2. **`celebration_queue.dart` enqueue contract**
   - Adding `enum SlotPolicy { drop, coalesce, serialize }` + pure function `SlotPolicy slotPolicyFor(CelebrationEvent event)`.
   - Per-variant assignments:
     - `FirstAwakeningEvent` → `serialize` (bypasses cap entirely, head of queue)
     - `ClassChangeEvent` → `serialize` (slot 1 reservation)
     - `RankUpEvent` → `serialize` (top rank-up reserved; spillover too)
     - `PersonalRecordEvent` → `serialize` (per WIP §4½: PR is a mid-workout flash; queue policy mirrors title's "crown" treatment so a PR landing during an active queue is sequenced, not dropped)
     - `TitleUnlockEvent` → `serialize` (third closer slot)
     - `LevelUpEvent` → `drop` (silently absorbed if cap-at-3 fills; re-derivable on saga screen — matches existing behavior locked by BUG-017 tests)
   - The enum names what the queue *already does today*; PR 29.5 just makes the policy first-class + adds the PR variant. No queue ordering changes for existing variants — existing BUG-013/BUG-017 tests must continue to pass unchanged.
   - **No runtime "new event mid-playback" mechanism** is built — the current architecture builds the queue once at finish time. The enum documents the per-event invariant the queue enforces and is unit-test-pinned.

3. **Five overlay widget files retired** (1656 LOC total — WIP's 1163 LOC count excluded rank_up_overlay)
   - `lib/features/rpg/ui/overlays/class_change_overlay.dart` (637 LOC)
   - `lib/features/rpg/ui/overlays/level_up_overlay.dart` (138 LOC)
   - `lib/features/rpg/ui/overlays/first_awakening_overlay.dart` (182 LOC)
   - `lib/features/rpg/ui/overlays/title_unlock_sheet.dart` (208 LOC)
   - `lib/features/rpg/ui/overlays/rank_up_overlay.dart` (491 LOC) — keep `RankUpOverflowFlipbook` (different widget, used by `celebration_overflow_card.dart`); move it to its own file or to celebration_overflow_card.dart
   - Call-sites of the deleted widgets (from `Grep ClassChangeOverlay|LevelUpOverlay|FirstAwakeningOverlay|TitleUnlockSheet|RankUpOverlay`):
     - `lib/features/rpg/ui/celebration_player.dart` — `_playOverlay` switch arms + `_classChangeHold` constant + barrier-color switch (rewrite to dispatch to ThinFlashOverlay uniformly)
     - Widget test files (DELETE):
       - `test/widget/features/rpg/overlays/class_change_overlay_test.dart`
       - `test/widget/features/rpg/overlays/level_up_overlay_test.dart`
       - `test/widget/features/rpg/overlays/first_awakening_overlay_test.dart`
       - `test/widget/features/rpg/overlays/title_unlock_sheet_test.dart`
       - `test/widget/features/rpg/overlays/title_unlock_sheet_golden_test.dart`
       - `test/widget/features/rpg/overlays/rank_up_overlay_test.dart`
       - `test/widget/features/rpg/overlays/rank_up_overlay_golden_test.dart`
     - Widget test file (UPDATE — references old widgets in imports/finders):
       - `test/widget/features/rpg/celebration_player_test.dart` — swap `RankUpOverlay`/`LevelUpOverlay`/`TitleUnlockSheet` finders to `ThinFlashOverlay`; sequence timings change from 1100ms→400ms holds
   - `RankUpOverflowFlipbook` extracted from `rank_up_overlay.dart` into a new module so the overflow card keeps working. Sole consumer: `celebration_overflow_card.dart`.

4. **E2E selectors + helpers**
   - `test/e2e/helpers/selectors.ts` — `CELEBRATION.rankUpOverlay`, `.levelUpOverlay`, `.titleUnlockSheet`, `.firstAwakeningOverlay`, `.classChangeOverlay`, `.classChangeSubtitle`, `.classChangeNameLabel`, `.classChangePreviousLabel` collapse onto thin-flash variant identifiers. Old constants kept as deprecated aliases for one PR cycle (delete in 30c).
   - `test/e2e/helpers/app.ts:384` — `CELEBRATION.titleUnlockSheet` reference; helper now interacts with the title flash (no sheet, no EQUIP CTA).
   - `test/e2e/specs/rank-up-celebration.spec.ts` — multiple references to `CELEBRATION.rankUpOverlay`, `.levelUpOverlay`, `.firstAwakeningOverlay`, `.titleUnlockSheet`. **Resolution policy (per WIP §4½ retire-with-aliases plan):** keep the deprecated aliases pointing at the new identifiers so existing specs continue to pass; tighten in 30c.
   - `test/e2e/specs/saga.spec.ts:536` — `CELEBRATION.classChangeOverlay` reference. Same alias resolution.
   - `test/e2e/specs/titles.spec.ts` — `CELEBRATION.equipTitleButton` reference inside a mid-workout context. The mid-workout EQUIP affordance is GONE; this spec must be updated to expect no equip-button mid-workout (the EQUIP affordance migrates to post-session in PR 30a). Per WIP, the EQUIP-from-titles-screen flow is unaffected.
   - `test/e2e/FLAKY_TESTS.md` — references RankUpOverlay/LevelUpOverlay; documentation update only (no behavior change).
   - `test/e2e/global-setup.ts` — references in setup/teardown contexts; no behavioral impact, comments only.

5. **EQUIP affordance audit (per dispatcher prompt §4)**
   - Mid-workout EQUIP CTA lived ONLY in `TitleUnlockSheet`. Grep for `equipTitleButton`/`equip-title-button`/`equipTitle` across `lib/`:
     - `lib/features/rpg/ui/overlays/title_unlock_sheet.dart` (deleted)
     - `lib/features/profile/ui/titles_screen.dart` (independent EQUIP flow — kept; not mid-workout)
   - No other screen depends on the mid-workout EQUIP affordance. The post-session summary panel will re-introduce EQUIP in PR 30a per WIP spec.

6. **`personalRecord` emission site (NOT wired in PR 29.5)**
   - Per dispatcher prompt: "PR 29.5 wires the variant + thin-flash rendering; PR 30a/30b will wire the emission site." `CelebrationEventBuilder.build` and `ActiveWorkoutNotifier._buildAndStashCelebration` are UNCHANGED in this PR. The new variant + queue policy + thin-flash renderer ship together; emission is unblocked for 30a/30b without further refactor. WIP §4 (which described emission wiring in 29.5) is overridden by the dispatcher prompt — flagged in hand-off.

**Path A scope summary (what shipped)**

- Retire all 5 legacy mid-workout overlays: `class_change_overlay.dart`, `level_up_overlay.dart`, `first_awakening_overlay.dart`, `title_unlock_sheet.dart`, `rank_up_overlay.dart`. The 4 widget-test files for them are deleted; `celebration_player_test.dart` is updated to assert no overlays mount mid-workout (the player becomes a pass-through; the post-session screen in PR 30a carries the full celebration).
- Convert `celebration_player.dart` into a no-op pass-through that preserves its public `play()` signature so `CelebrationOrchestrator` keeps compiling without a call-site rewrite. `onEquipTitle` + `hasPriorEarnedTitles` parameters are marked `@Deprecated` and become dead arguments for one PR cycle (removed in PR 30c).
- Scaffold the `CelebrationEvent.personalRecord` variant on the sealed union with `exerciseId` (not `exerciseSlug` — `Exercise` carries `id`, not slug) + `exerciseName` + `weight` + `reps` + optional `priorBest`. **Emission is NOT wired in this PR** — PR 30a / 30b will plug it in from `peak_loads_repository.dart` deltas. Freezed exhaustive switches now require every consumer to handle the variant.
- Promote `SlotPolicy` to a first-class top-level enum (`drop` / `coalesce` / `serialize`) + pure `slotPolicyFor(CelebrationEvent)` switch. The enum names what `CelebrationQueue` already does today; per-variant assignment is unit-test-pinned so a future variant must make an explicit policy choice.
- Strip the mid-workout EQUIP affordance entirely. The `onEquipTitle` closure in `CelebrationOrchestrator` is now a no-op stub; the real EQUIP affordance migrates to the post-session summary panel in PR 30a.

**What is intentionally NOT in this PR**

- No `thin_flash_overlay.dart` widget. The 1200ms hue-flash variant was specced for Path B but killed during on-device verification (Galaxy S25 Ultra) when it became clear the flash fires ~200ms before the Phase 30 cinematic — same attentional context, redundant pre-roll. The architecture only supports finish-time emission, not true per-set firing, so the dual-loop framing collapses.
- No new ARB keys. The 8 `flash*` keys specced in the abortive Path B (FirstAwakeningHero, RankUpEyebrow, etc.) are not added. Post-session screen ARB keys ship with PR 30a.
- No `scripts/check_thin_flash_no_glow.sh` CI gate. The widget it would protect doesn't exist.
- No golden tests for the retired overlays. Goldens go where pixels matter — the post-session cinematic in PR 30a.
- No `personalRecord` emission site, no `celebration_event_builder.dart` changes, no `peak_loads_repository.dart` wiring. The variant is scaffold-only.

**Acceptance criteria (shipped)**

1. The 5 overlay files are deleted from `lib/features/rpg/ui/overlays/` and their unit/widget/golden tests are removed.
2. `CelebrationEvent` sealed union compiles + Freezed regenerates; the `personalRecord` variant is exhaustively switched in every consumer (`celebration_queue.dart`, `celebration_player.dart` pass-through, `slotPolicyFor`).
3. `slotPolicyFor` returns the documented policy for all 6 variants (first-awakening / class-change / rank-up / title-unlock / personal-record / level-up). Unit-test-pinned.
4. `celebration_player.dart` `play()` returns a result with `userTappedOverflow: false` for every input without mounting any overlay. Verified by widget test.
5. `CelebrationOrchestrator.onEquipTitle` closure is a no-op (gutted in review pass 2 per reviewer Important 1).
6. `make ci` green: format, analyze --fatal-infos, all unit/widget tests, Android debug build.
7. No E2E regression: existing rank-up-celebration spec now asserts URL navigation + server-side XP parity instead of overlay visibility.

**Test coverage (shipped)**

| File | Type | What it pins |
|---|---|---|
| `test/unit/features/rpg/domain/celebration_slot_policy_test.dart` | unit | One group per variant: `slotPolicyFor` returns the documented policy for first-awakening / class-change / rank-up / title-unlock / personal-record / level-up. |
| `test/unit/features/rpg/models/celebration_event_personal_record_test.dart` | unit | Freezed equality, copyWith, exhaustive switch pin for the new variant. |
| `test/widget/features/rpg/celebration_player_test.dart` (updated) | widget | Pass-through behavior: no overlay mounts, `play()` returns `userTappedOverflow: false`. |
| `test/e2e/specs/rank-up-celebration.spec.ts` (updated) | E2E | URL-navigation + server-side XP parity assertion replaces the overlay-visibility check (renamed in review pass 2). |

**Migration / data shape changes**

- `CelebrationEvent.personalRecord` variant added. Freezed regenerates `celebration_event.freezed.dart` — `make gen` after editing.
- No SQL migration, no Hive schema bump.
- Selector aliases in `test/e2e/helpers/selectors.ts` map the deleted overlay identifiers onto a stub that always returns "not found" — kept for one PR cycle (deleted in 30c) so any cross-spec straggler reference compiles but fails loudly.

**Risks + mitigations**

| Risk | Mitigation |
|---|---|
| Empty rank-up/title/class-change finish on hosted Supabase before PR 30a ships → user gets no visual feedback for a rank-up | Mid-workout silence is the intended state for PR 29.5; the post-session screen in PR 30a carries the celebration. Window between 29.5 merge + 30a merge is the regression window — coordinate merge order with user. |
| Future agent re-adds an overlay file under `lib/features/rpg/ui/overlays/` not realizing the layer is retired | The `celebration_player.dart` dartdoc header (lines 19-50) explains why it's a pass-through; the orchestrator's `onEquipTitle` no-op comment points at PR 30a. Both surface the intent at the call site. |
| Deprecated `hasPriorEarnedTitles` + `onEquipTitle` parameters live in tree until PR 30c | Acceptable — both annotated `@Deprecated` with explicit removal target. `analyzer` flags any new caller. |

---

### PR 30a — Post-session screen + state machine + summary panel

**Branch:** `feature/30a-post-session-screen` off `main` (after PR 29.5 merges).

**Scope summary**

- Build the full-screen post-session route `/workout/finish/:workoutId` (named `postWorkoutFinish`). Pushed by `finish_workout_coordinator.dart` after persistence; replaces the current direct `/home` (or `/pr-celebration`) routing for online finishes with non-zero work.
- Implement the **3-beat cinematic state machine** with single `AnimationController` orchestration: B1 (XP cut, 4 tier variants) → B2 (BP tally — single / sequential ≤2 / cascade ≥3 / elevated rank-up fusion) → B3 (max 2 reward cuts: PR/multi-PR/title/class-change) → summary panel.
- Implement the **summary panel** (every state's last frame in mockup §5): saga number + duration + sets + tonnage + per-state next-step hook + share CTA (when PR/rank-up/class-change fired) + title EQUIP row (when title unlocked) + CONTINUAR button.
- Implement the **`rewardTier` derivation** (input: `CelebrationQueueResult`, output: `RewardTier` enum + Beat 1 copy key + skip flags) — pure function in `domain/`, no Riverpod, fully testable.
- Wire `finish_workout_coordinator.dart`: empty-session guard (State 11) BEFORE the route push, drain `celebration_player` queue (mid-workout flashes finish first), then push the post-session route. Offline finishes still route to `/home` directly — post-session screen is online-only per the Phase 18c spec the coordinator inherits.
- Add the **title EQUIP row** to the summary panel (mockup §8 gap 4). Tap → call existing `equip_title` RPC via the existing notifier; "depois" → dismiss. EQUIP affordance is a single full-width primaryViolet button.
- Implement the **skip-to-skip-all gestures** (mockup §8 gap 6): single tap during a cut → advance to next; long-press 500ms → fast-forward to summary panel. CONTINUAR only appears during summary.
- Wire **share-CTA placeholder** that opens a "coming soon" snackbar (real implementation lands in PR 30b). This lets the summary panel ship with the correct layout + the real CTA upgrades transparently when 30b merges.

**Files created** (all absolute paths)

Screen + state:

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\post_session_screen.dart` — top-level full-screen route. Owns the orchestrating `AnimationController` + state machine. Drives the cut sequence via `AnimatedSwitcher`.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\post_session_state.dart` — Freezed model representing the screen's runtime state: `RewardTier`, ordered `List<PostSessionCut>`, current cut index, summary payload. Driven by `PostSessionController` (a Riverpod `AsyncNotifier` keyed on workoutId).
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\providers\post_session_controller.dart` — `AsyncNotifier` resolving the post-session payload: workout snapshot + `CelebrationQueueResult` + PR detection results + the derived `RewardTier`.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\domain\reward_tier.dart` — enum `{ dayZero, baseline, prAnticipatory, classChangeAnticipatory }` + pure `RewardTier.derive(CelebrationQueueResult)` static. Each variant maps to a Beat 1 copy key + a hold duration constant.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\domain\post_session_choreographer.dart` — pure builder: given `(rewardTier, queueResult, prResult, bpTotals)`, returns the ordered `List<PostSessionCut>` to render. **No Riverpod, no IO.** Drives the State 1-10 storyboard logic from mockup §5.

Cut widgets:

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b1_xp_cut.dart` — B1 widget. Takes `RewardTier` + xp + level. Renders 4 copy variants.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b2_bp_tally_cut.dart` — B2 single-BP and sequential mode. Renders eyebrow + xp + bar fill.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b2_cascade_cut.dart` — B2 cascade variant (3+ BPs). Hero BP + cascade rows + truncation pill.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b2_elevated_cut.dart` — B2 elevated (rank-up fusion). Bar fills past + rank slam.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b3_pr_cut.dart` — B3 PR (single + multi roll-up). White flash + gold flood + pill strip.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b3_title_cut.dart` — B3 title (hue-typed flood: BP / cross-build / character-level).
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\cuts\b3_class_change_cut.dart` — B3 class change (hotViolet flood + BULWARK slam + flavor line).

Summary panel:

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\summary\post_session_summary_panel.dart` — full summary card. Composes saga header + duration/sets/tonnage + next-step hook (per state) + reward roll-up rows (rank-up overflow card, title EQUIP row, PR detail link) + share CTA + CONTINUAR button.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\summary\title_equip_row.dart` — single-purpose widget. Renders "Novo título · {name} · [EQUIPAR] [depois]". Tap EQUIPAR → invokes injected callback (wired to `equip_title` RPC).
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\summary\next_step_hook.dart` — derives the per-state forward-hook line ("Falta 240 XP para Peito rank 2.") from the post-finish snapshot. Logic is pure and tested independently.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\summary\share_cta_button.dart` — placeholder in 30a (shows snackbar "Em breve"). Replaced by real implementation in 30b.

Guard:

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\widgets\empty_session_guard_sheet.dart` — modal sheet for State 11. "Nenhum exercício registrado." + Descartar / Continuar treinando.

**Files modified**

- `C:\Users\caiol\Projects\repsaga\lib\core\router\app_router.dart` — add `postWorkoutFinish` route `/workout/finish/:workoutId` outside the shell (full-screen). Document: route is push-only (never deep-linked, never popable to active workout — back goes to home).
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\coordinators\finish_workout_coordinator.dart` — (a) add empty-session guard BEFORE the celebration drain — if `notifier.totalSetsCount == 0`, show `EmptySessionGuardSheet`, branch on result; (b) replace the `navigateAfterFinish` `/pr-celebration` branch with `/workout/finish/:workoutId` for online finishes with non-zero work; offline branch unchanged.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\coordinators\post_workout_navigator.dart` — strip the `/pr-celebration` branch (deprecated; deletion happens in 30c). Add a `prResult != null || hasRewardEvent` predicate that routes online finishes to the post-session route; offline still goes to `/home`.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\providers\active_workout_notifier.dart` — `finishWorkout` returns the `WorkoutFinishResult` with the celebration queue + PR result; the controller picks it up via `consumeLastCelebration()` (existing API).
- `C:\Users\caiol\Projects\repsaga\lib\l10n\app_en.arb` + `app_pt.arb` — add ~24 new keys (see l10n surface below).
- `C:\Users\caiol\Projects\repsaga\test\e2e\helpers\selectors.ts` — add post-session screen selectors.
- `C:\Users\caiol\Projects\repsaga\test\e2e\fixtures\test-users.ts` + `global-setup.ts` — add a `postSessionDayZero` user seeded with zero workouts (for State 1 testing) if no existing fresh-user fixture suffices.

**Files deleted** — none in 30a (`pr_celebration_screen.dart` deletion is held until 30c so the route can be migrated cleanly).

**Dependencies**

- **PR 29.5 must merge before this PR**. The post-session B1 copy ("NÍVEL 23. A SAGA CONTINUA.") only makes sense if the level-up flash mid-workout is the new thin variant; the old `LevelUpOverlay` 200ms slide-in card contradicts the "confirms what already happened" framing.
- Phase 29 PR 2 (#252) merge order is independent — Phase 30a code only depends on the celebration event surface, which is owned by PR 29.5. But if Phase 29 PR 2 has not merged, the XP numbers shown in Beat 1 will use the v1 formula until PR 2 lands. Coordinate with user on which order they want public.
- No new pubspec deps in 30a (share CTA is a placeholder snackbar; real implementation in 30b).

**Acceptance criteria**

1. `RewardTier.derive` is a pure function; given the 4 canonical fixture inputs (dayZero / baseline / prAnticipatory / classChangeAnticipatory) returns the expected enum. Hold duration mapping locked: dayZero=1300ms, baseline=1200ms, prAnticipatory=1200ms, classChangeAnticipatory=1500ms (with 120ms pre-roll).
2. `PostSessionChoreographer.build` produces the correct cut count for every State 1-10 fixture in `test/fixtures/post_session_states.json`. State counts: S1=2 cuts, S2=2, S3=3, S4=3, S5=3, S6=3, S7=2, S8=3, S9=2 (B2 skipped), S10=4. Total cuts + summary panel.
3. Empty-session guard (State 11): zero sets → `EmptySessionGuardSheet` modal shows; Descartar → `/home`; Continuar treinando → returns to active workout. Post-session route is **never pushed** for empty sessions. Verified by widget test on `finish_workout_coordinator.dart` + an E2E test that completes a workout with zero sets.
4. B1 hold duration is 1200ms ± 50ms for baseline tier verified by `pumpAndSettle` timing test (`tester.binding.clock` introspection). dayZero=1300, classChange=1500.
5. Cascade variant truncates at 4 rows + "+N mais" pill when ≥6 BPs trained (mockup §3 Variant C).
6. B3 PR cut shows white-flash (33ms) → gold flood → hero PR line; multi-PR adds N pills (max 3 + "+N mais"). Single white-flash per session enforced by the choreographer (not per cut).
7. Class-change cut skips Beat 2 entirely (State 9). Choreographer test pin.
8. Title EQUIP row → tap "EQUIPAR" → existing `equip_title` RPC fires → success snackbar → row updates to "Equipado ✓" via provider invalidation. Tap "depois" → row collapses with no RPC call.
9. Skip gestures: tap = advance one cut; long-press 500ms = jump to summary. Both verified by `WidgetTester.longPress` and `WidgetTester.tap` driving an animated cut sequence.
10. `make ci` green. New e2e specs pass against `build/web/`.

**Test coverage plan**

| File | Type | What it pins |
|---|---|---|
| `test/unit/features/workouts/domain/reward_tier_test.dart` | unit | 4 derive cases + hold durations + Beat 1 copy keys per tier. |
| `test/unit/features/workouts/domain/post_session_choreographer_test.dart` | unit | One group per state S1-S10; assert cut count + cut types + dominant BP selection (mockup §3 dominant rule: highest XP → highest rank tiebreak → alphabetical). |
| `test/unit/features/workouts/ui/post_session/cuts/b1_xp_cut_test.dart` | widget | Renders 4 variants; hero number visible; copy matches ARB key per tier. |
| `test/unit/features/workouts/ui/post_session/cuts/b2_bp_tally_cut_test.dart` | widget | Single + sequential modes; eyebrow color = BP hue; bar fill percentage matches input. |
| `test/unit/features/workouts/ui/post_session/cuts/b2_cascade_cut_test.dart` | widget | 3, 4, 5, 6 BP inputs; truncation pill at 6+. |
| `test/unit/features/workouts/ui/post_session/cuts/b2_elevated_cut_test.dart` | widget | Bar fills past 100%, rank number slams in, 1.1s hold. |
| `test/unit/features/workouts/ui/post_session/cuts/b3_pr_cut_test.dart` | widget | Single PR layout + multi PR roll-up (3 + "+N mais"). |
| `test/unit/features/workouts/ui/post_session/cuts/b3_title_cut_test.dart` | widget | 3 hue variants (BP / cross-build / character-level). No white flash present. |
| `test/unit/features/workouts/ui/post_session/cuts/b3_class_change_cut_test.dart` | widget | Class name + DESPERTOU subline + italic flavor line. 1.5s hold. |
| `test/unit/features/workouts/ui/post_session/summary/post_session_summary_panel_test.dart` | widget | Renders saga header + stats + next-step hook + share CTA placeholder + CONTINUAR. State-dependent rows (title EQUIP, rank-up overflow, PR detail link) appear conditionally. |
| `test/unit/features/workouts/ui/post_session/summary/title_equip_row_test.dart` | widget | EQUIPAR tap → callback invoked once; "depois" tap → row collapses. |
| `test/unit/features/workouts/ui/post_session/summary/next_step_hook_test.dart` | unit | Pure per-state derivation: rank-XP-remaining, ranks-to-next-level, BP-rank-to-title threshold. |
| `test/unit/features/workouts/ui/widgets/empty_session_guard_sheet_test.dart` | widget | Descartar → result.discarded; Continuar treinando → result.continueTraining. |
| `test/widget/features/workouts/ui/coordinators/finish_workout_coordinator_empty_guard_test.dart` | widget | Zero-set finish → sheet shown + post-session route NEVER pushed (verified via mock router). |
| `test/widget/features/workouts/ui/post_session/post_session_screen_test.dart` | widget | Full screen integration: 3-event queue plays end-to-end; skip-tap advances; long-press jumps to summary. |
| `test/widget/features/workouts/ui/post_session/post_session_skip_gestures_test.dart` | widget | Tap during cut → next cut; long-press 500ms → summary; CONTINUAR only present in summary. |
| `test/widget/features/workouts/ui/post_session/post_session_screen_golden_test.dart` | golden | One golden per state (S1-S10) at 360dp, summary panel frame. 10 goldens total; mockup §5 reference comparison in PR review. |
| `test/e2e/specs/post_session.spec.ts` | E2E (new file) | Tagged `@smoke`. Scenarios: baseline finish (state 2) → 3 cuts + summary; empty session → guard sheet; finish with PR → gold-flood cut visible. |

**l10n surface** — ~24 new keys (pt-BR + en):

| Key | pt-BR | en |
|---|---|---|
| `b1CopyDayZero` | "COMEÇO.\nO PIOR JÁ PASSOU." | "BEGUN.\nTHE WORST IS BEHIND." |
| `b1CopyBaselineA` | "ENCERRADO.\nMAIS FORTE." | "DONE.\nSTRONGER." |
| `b1CopyBaselineB` | "CONSISTÊNCIA VENCE." | "CONSISTENCY WINS." |
| `b1CopyPrAnticipatory` | "NOVO LIMITE." | "NEW LIMIT." |
| `b1CopyTitleAnticipatory` | "CONQUISTA DESPERTADA." | "ACHIEVEMENT AWAKENED." |
| `b1CopyMaxLevelUp` | "NÍVEL {n}.\nA SAGA CONTINUA." | "LEVEL {n}.\nTHE SAGA CONTINUES." |
| `b3PrEyebrowSingle` | "!! Recorde" | "!! Record" |
| `b3PrEyebrowMulti` | "!! {n} Recordes" | "!! {n} Records" |
| `b3PrCopySingle` | "VOCÊ QUEBROU TUDO." | "YOU BROKE THROUGH." |
| `b3PrCopyMulti` | "VOCÊ DESTRUIU TUDO." | "YOU DESTROYED IT." |
| `b3TitleEyebrow` | "Título Desbloqueado" | "Title Unlocked" |
| `b3ClassEyebrow` | "Classe Desperta" | "Class Awakened" |
| `b3ClassSubline` | "DESPERTOU." | "AWAKENED." |
| `b2RankCopy` | "{bodyPart} · RANK {n}" | "{bodyPart} · RANK {n}" |
| `summarySagaNumber` | "Saga {n}" | "Saga {n}" |
| `summaryDayZero` | "1ª saga" | "1st saga" |
| `summaryDurationSets` | "{minutes} min · {sets} séries" | "{minutes} min · {sets} sets" |
| `summaryTonnage` | "{kg} ton" | "{kg} ton" |
| `summaryNextStepLabel` | "Próximo passo" | "Next" |
| `summaryNextRank` | "Faltam {xp} XP\npara {bodyPart} rank {n}." | "{xp} XP left\nfor {bodyPart} rank {n}." |
| `summaryNextLevel` | "Faltam {ranks} ranks\npara nível {n}." | "{ranks} ranks to\nlevel {n}." |
| `summaryNewTitleLabel` | "Novo título" | "New title" |
| `summaryEquipCta` | "EQUIPAR" | "EQUIP" |
| `summaryEquipLater` | "depois" | "later" |
| `summaryContinueCta` | "CONTINUAR ▶" | "CONTINUE ▶" |
| `summaryShareCta` | "📷 Compartilhar saga" | "📷 Share saga" |
| `summaryShareComingSoon` | "Compartilhar — em breve" | "Share — coming soon" |
| `emptyGuardTitle` | "Encerrar treino?" | "End workout?" |
| `emptyGuardBody` | "Nenhum exercício registrado." | "No exercises logged." |
| `emptyGuardDiscard` | "Descartar" | "Discard" |
| `emptyGuardContinue` | "Continuar treinando" | "Keep training" |

**Migration / data shape changes**

- New Freezed model `PostSessionState` (private to feature, no SQL/Hive impact).
- New route in `app_router.dart`; no schema migration.
- `WorkoutFinishResult.prResult` field already exists; no model change.

**Risks + mitigations**

| Risk | Mitigation |
|---|---|
| Single `AnimationController` blocks for ~12s on max-combo; user can't background safely | `WidgetsBinding.lifecycleState != AppLifecycleState.resumed` → pause + restore on resume. Controller is screen-scoped, disposed in `dispose()`. |
| Beat 3 PR cut's white flash → gold flood read as "glow" by `check_thin_flash_no_glow.sh` | The script targets `thin_flash_overlay.dart` only; post-session cuts use their own widget files. The "white flash" is a 33ms stacked `ColoredBox(Colors.white)` — not a `BoxShadow`. Explicitly documented in `b3_pr_cut.dart` header. |
| Title EQUIP RPC failure mid-flow leaves the user confused | Standard repository error handling: show SnackBar with l10n error, leave row clickable for retry. The post-session route doesn't depend on equip success. |
| Long-press 500ms collides with rest-overlay long-press in active workout | Active workout is fully unmounted by the time the post-session route mounts. No overlap possible. |
| `RewardTier.derive` introduces a copy-key mismatch and the wrong line shows | ARB keys are flat constants; derive returns the enum; the widget reads `tier.copyKey` (extension on enum). Unit-tested as a single mapping table. |
| Cascade truncation at 4 rows hides a body part the user trained | Truncation pill always shows "+N mais" with the count; tap opens the summary panel where all BPs appear in the detailed breakdown. Verified by widget test. |

---

### PR 30b — Share card pipeline

**Branch:** `feature/30b-share-card` off `main` (after 30a merges).

**Scope summary**

- Add three new pubspec dependencies: `image_picker` (camera + gallery), `share_plus` (native share sheet + camera roll save), `permission_handler` (graceful camera permission denial). All Context7-verified for current Flutter SDK 3.11.4.
- Implement the 4-screen capture/preview/export flow (mockup §7): bottom sheet → camera/gallery → preview → native share sheet.
- Implement **Variant A (Minimal Strip)** + **Variant B (Full Bleed corner collars)** + **Discreet mode** share-card renderers (mockup §6) using `RepaintBoundary` + `RenderRepaintBoundary.toImage(pixelRatio: 3.0)` at 1080×1920 9:16, JPEG quality 88.
- Wire the **summary panel share CTA** (placeholder added in 30a) to open the bottom sheet.
- Toggle controls on preview screen: tap-to-hide XP / tap-to-hide PR / drag-to-reframe / Variant A↔B toggle / retake.
- Permission deny path: graceful — "Tirar foto" disappears from bottom sheet if camera permission denied, no re-prompt.

**Files created**

- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\share_card_renderer.dart` — pure widget that composes (photo | discreet-flood) + overlay (Variant A | Variant B). Used both as the visible preview AND as the offscreen `RepaintBoundary` for export.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\variants\share_card_variant_a.dart` — bottom strip layout. Hue accent + XP + (optional) PR line + bar + REPSAGA wordmark.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\variants\share_card_variant_b.dart` — top + bottom collar layout with `clip-path: polygon` equivalent (Flutter `CustomClipper<Path>`). Class + PR + lift detail + XP.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\variants\share_card_discreet.dart` — no-photo cinematic still. Hue flood + slash + d-hero numeric + REPSAGA.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\share_sheet.dart` — modal bottom sheet (step 1): TIRAR FOTO + ESCOLHER DA GALERIA + Sem foto.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\share\share_preview_screen.dart` — full-screen preview (step 3): photo zone + overlay + variant toggle + retake + share button. Drag-to-reframe gesture + tap-to-hide affordances.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\domain\share_payload.dart` — pure model. Composes from `(WorkoutSummary, CelebrationQueueResult)`: dominant BP, XP, PR (if any), class, body-part rank progress. Drives the variant renderers.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\data\share_image_renderer.dart` — service. `Future<XFile> render({required GlobalKey repaintKey, double pixelRatio = 3.0, int jpegQuality = 88})`. Wraps `RenderRepaintBoundary.toImage` + JPEG encode + `path_provider` temp file. Returns the temp file path.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\data\share_service.dart` — repository layer. Wraps `share_plus.Share.shareXFiles` + `image_picker.ImagePicker.pickImage`. Single source of truth for sharing IO.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\providers\share_controller.dart` — `AsyncNotifier` orchestrating: pick photo → render → share. Handles permission denial path.

**Files modified**

- `C:\Users\caiol\Projects\repsaga\pubspec.yaml` — add `image_picker` (pin version per Context7), `share_plus` (pin), `permission_handler` (pin). Specific versions deferred to tech-lead at PR open — must use Context7 `query-docs` per CLAUDE.md.
- `C:\Users\caiol\Projects\repsaga\android\app\src\main\AndroidManifest.xml` — add `<uses-permission android:name="android.permission.CAMERA"/>` + `<queries><intent>` block for `image_picker` per its README.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\post_session\summary\share_cta_button.dart` — replace the 30a placeholder snackbar with `shareSheet.open(context, payload: …)`.
- `C:\Users\caiol\Projects\repsaga\lib\l10n\app_en.arb` + `app_pt.arb` — add ~8 new keys (share flow labels).
- `C:\Users\caiol\Projects\repsaga\test\e2e\helpers\selectors.ts` — add share-flow selectors. **E2E NOTE:** image_picker/share_plus on Flutter web fall back to browser native APIs which Playwright cannot fully drive — share-flow E2E coverage stays widget-level. Web build keeps the share CTA but the picker shows a browser file-input.
- `C:\Users\caiol\Projects\repsaga\test\e2e\fixtures\` — add a `fixtures/share-card-photo.jpg` sample photo for preview testing where applicable.

**Files deleted** — none.

**Dependencies**

- Merges after 30a. The summary panel `share_cta_button.dart` exists as a placeholder in 30a; 30b wires it up. If 30a is delayed, 30b can be split: variant renderers (no IO) ship independently as widget tests; permission + picker + share wiring lands when 30a's CTA is available.
- New pubspec deps. **Tech-lead MUST run Context7 `query-docs` on `image_picker`, `share_plus`, `permission_handler` before pinning versions** — see CLAUDE.md "Library API lookups". The versions are deferred to PR-open time, not specified in this plan, because Flutter SDK 3.11.4 minor version compatibility matters.

**Acceptance criteria**

1. `flutter build apk --debug` succeeds with the 3 new pubspec deps and the Android manifest permissions.
2. Bottom sheet → tap "TIRAR FOTO" → `image_picker.pickImage(source: ImageSource.camera)` invoked; mocked in tests.
3. Bottom sheet → tap "ESCOLHER DA GALERIA" → `image_picker.pickImage(source: ImageSource.gallery)` invoked.
4. Bottom sheet → tap "Sem foto · só a saga" → directly proceeds to preview with discreet variant.
5. Preview screen: tap A/B toggle → variant switches (verified by widget hierarchy diff).
6. Preview screen: tap "↻ refazer" → returns to bottom sheet.
7. Preview screen: tap share → `share_image_renderer.render` produces a 1080×1920 JPEG ≤ 1.2MB; `share_plus.shareXFiles` invoked with the file.
8. Permission denied path: `permission_handler.Permission.camera.request()` returns `denied` → bottom sheet renders WITHOUT the "TIRAR FOTO" option; "ESCOLHER DA GALERIA" + "Sem foto" remain.
9. Render-to-image golden test: at 1080×1920 with a fixed mock photo + fixed `SharePayload`, the rendered bytes match a stored golden fixture (Variant A baseline, Variant B PR, Discreet class-change — 3 goldens).
10. `make ci` green including Android debug build.

**Test coverage plan**

| File | Type | What it pins |
|---|---|---|
| `test/unit/features/workouts/domain/share_payload_test.dart` | unit | Compose from `WorkoutSummary + queueResult`: dominant BP selection, PR carry, class carry. 8 cases mirroring mockup §5 states. |
| `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_a_test.dart` | widget | Hue accent matches dominant BP; PR line conditional; XP renders. |
| `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_b_test.dart` | widget | Top + bottom collar layout; clip-path renders (verified by RenderObject `Clip.antiAlias`). |
| `test/unit/features/workouts/ui/post_session/share/variants/share_card_discreet_test.dart` | widget | Discreet flood + slash + d-hero + d-wordmark. Hue swap on class-change. |
| `test/unit/features/workouts/ui/post_session/share/share_card_renderer_golden_test.dart` | golden | 3 goldens (A baseline, B PR, Discreet class-change) at 1080×1920. |
| `test/unit/features/workouts/ui/post_session/share/share_sheet_test.dart` | widget | Permission denied → camera option removed; "Sem foto" present in all states. |
| `test/unit/features/workouts/ui/post_session/share/share_preview_screen_test.dart` | widget | A↔B toggle; retake; tap-to-hide XP; tap-to-hide PR; drag-to-reframe (verified by gesture detector callback). |
| `test/unit/features/workouts/data/share_image_renderer_test.dart` | unit | Mocked `RepaintBoundary.toImage`; assert JPEG bytes < 1.2MB at quality 88; assert temp file cleanup. |
| `test/unit/features/workouts/data/share_service_test.dart` | unit | Mocktail-backed; verify `share_plus.shareXFiles` called with correct args; permission denial returns Result.denied. |
| `test/widget/features/workouts/providers/share_controller_test.dart` | widget | End-to-end: tap CTA → sheet opens → mock picker returns file → preview shows → tap share → service called. |
| `test/e2e/specs/share_flow.spec.ts` | E2E (new) | Tagged `@smoke`. Smoke only — Playwright drives bottom-sheet open + variant toggle + "Sem foto" → preview. Camera/gallery picker assertions skipped on web (browser native UI). |

**l10n surface** — ~10 new keys:

| Key | pt-BR | en |
|---|---|---|
| `shareSheetTitle` | "Compartilhar saga" | "Share saga" |
| `shareTakePhoto` | "📷 TIRAR FOTO" | "📷 TAKE PHOTO" |
| `shareFromGallery` | "🖼 ESCOLHER DA GALERIA" | "🖼 FROM GALLERY" |
| `shareNoPhoto` | "Sem foto · só a saga" | "No photo · saga only" |
| `sharePreviewRetake` | "↻ refazer" | "↻ retake" |
| `sharePreviewMinimal` | "Mínimo" | "Minimal" |
| `sharePreviewBold` | "Destaque" | "Bold" |
| `shareCardWordmark` | "REPSAGA" | "REPSAGA" |
| `sharePermissionDenied` | "Permissão da câmera negada." | "Camera permission denied." |
| `shareRenderError` | "Não foi possível gerar a imagem." | "Could not generate the image." |

**Migration / data shape changes**

- New pubspec deps; bump locks via `flutter pub get`.
- Android manifest gains `CAMERA` permission + `image_picker` intent query block (no autoGoogle deps changes).
- No SQL, no Hive.

**Risks + mitigations**

| Risk | Mitigation |
|---|---|
| `image_picker` API shape changed between training-data version and pinned version | Context7 `query-docs` first; pin to current stable. Read the changelog for breaking changes since SDK 3.11.4 launched. |
| `RepaintBoundary.toImage` returns black on Flutter web | Document web limitation; share-flow gated to native platforms on web (CTA hidden). Verify in widget test on web build. |
| 1080×1920 render at pixelRatio 3.0 exceeds 1.2MB budget | Pixel ratio falls back to 2.0 if encoded size > 1.2MB; documented in `share_image_renderer.dart`. |
| Permission re-prompt on every share open feels intrusive | `permission_handler` is invoked **only on TIRAR FOTO tap**, not on bottom sheet open. Permission state cached per session. |
| Saving to camera roll fails silently on Android Q+ scoped storage | `share_plus.shareXFiles` uses `Intent.ACTION_SEND` which doesn't require WRITE_EXTERNAL_STORAGE on Q+; verified by integration test. |
| Drag-to-reframe gesture conflicts with native scroll on preview | Preview screen is full-screen; no scroll parent. `GestureDetector` is the only consumer. |

---

### PR 30c — Cleanup + deprecate PR celebration screen + final E2E migration + docs

**Branch:** `feature/30c-post-session-cleanup` off `main` (after 30b merges).

**Scope summary**

- Delete `pr_celebration_screen.dart` (476 LOC) and its route `/pr-celebration`. The post-session screen subsumes it — PR confirmation lives in B3 PR cut + summary panel detail row.
- Remove the deprecated overlay selector aliases from `test/e2e/helpers/selectors.ts` that PR 29.5 kept around for one cycle.
- Final E2E pass: grep every `specs/*.spec.ts` for stale references to `pr-celebration`, `rank-up-overlay`, `level-up-overlay`, `first-awakening-overlay`, `title-unlock-sheet`, `class-change-overlay`. Replace remaining hits or delete the assertions.
- Condense Phase 30 in `docs/PROJECT.md` §4: 4-5 bullets per PR. Move full spec from this WIP.md section to git history. Mark `mockup-v2.html` as canonical reference (keep in `docs/`).
- Add auto-memory entry `project_phase_30_post_session.md` capturing: thin-flash + cinematic 3-beat structure, slot-policy, RewardTier derivation, share-card pipeline, EQUIP migration.
- Add cluster ledger row in PROJECT.md §0 if any new pattern emerged during 30a/30b that's worth grep-tagging future bugs.
- Remove `docs/WIP.md` Phase 30 section entirely (this section).
- **Test-hygiene audit** (absorbed from #252's discovery — user directive 2026-05-21). Apply the per-test reseed pattern from `28d67d6` (crash-recovery) + `e2e089e` (weekly-plan) to the 3 remaining audit candidates flagged during #252:

  | Spec | Logins / Reseeds | Risk under Phase 30 SQL chain |
  |---|---|---|
  | `test/e2e/specs/workouts.spec.ts` | 17 / 0 | Highest — deepest workout state, most tests |
  | `test/e2e/specs/personal-records.spec.ts` | 2 / 0 | PR tracking depends on prior peak state |
  | `test/e2e/specs/offline-sync.spec.ts` | 3 / 0 | Hive box state leaks across tests |

  Per spec: add a per-spec `reseed<UserName>User()` helper that cleans (workouts cascade + xp_events + body_part_progress + exercise_peak_loads + exercise_peak_loads_by_rep_range + personal_records + earned_titles + backfill_progress), call it in `beforeEach` before login, add `test.describe.configure({ mode: 'serial' })` for intra-worker safety under `--repeat-each`. Acceptance: each spec runs green at `--workers=4 --repeat-each=3`.

  Estimated added scope: ~400-600 LOC (~120 LOC per spec × 3 + shared helper extraction).

**Files created**

- `C:\Users\caiol\.claude\projects\C--Users-caiol-Projects-repsaga\memory\project_phase_30_post_session.md` — auto-memory entry indexed in MEMORY.md.

**Files modified**

- `C:\Users\caiol\Projects\repsaga\docs\PROJECT.md` — §4 Completed Phases gets a "Phase 30 — Post-session cinematic" entry with 4 sub-bullets (PR 29.5 / 30a / 30b / 30c). Progress snapshot table gets 4 new rows. Cluster Ledger adds rows if applicable.
- `C:\Users\caiol\Projects\repsaga\docs\WIP.md` — remove the entire Phase 30 implementation plan section (kept until 30c merges).
- `C:\Users\caiol\Projects\repsaga\lib\core\router\app_router.dart` — remove the `/pr-celebration` route.
- `C:\Users\caiol\Projects\repsaga\lib\features\workouts\ui\coordinators\post_workout_navigator.dart` — strip the deprecated PR-celebration branch entirely; `prResult` is consumed by the post-session screen, not the navigator.
- `C:\Users\caiol\Projects\repsaga\test\e2e\helpers\selectors.ts` — delete the deprecated alias section added in PR 29.5.
- `C:\Users\caiol\Projects\repsaga\test\e2e\specs\workouts.spec.ts` (+ any other spec referencing `pr-celebration`) — replace assertions with post-session route assertions.
- `C:\Users\caiol\.claude\projects\C--Users-caiol-Projects-repsaga\memory\MEMORY.md` — add the new project entry to the index.

**Files deleted**

- `C:\Users\caiol\Projects\repsaga\lib\features\personal_records\ui\pr_celebration_screen.dart` (476 LOC)
- All `pr_celebration_screen_test.dart` + `pr_celebration_screen_golden_test.dart` files.

**Dependencies**

- Merges after 30b. Cannot strip `pr_celebration_screen.dart` while the route is still wired.
- Final phase — closes Phase 30.

**Acceptance criteria**

1. `flutter analyze --fatal-infos` green after deletions; no dangling imports.
2. `grep -rn "pr-celebration" lib/ test/` returns zero hits.
3. `grep -rn "rank-up-overlay\|level-up-overlay\|first-awakening-overlay\|title-unlock-sheet\|class-change-overlay" test/` returns zero hits.
4. PROJECT.md §4 has the Phase 30 condensed entry (4 bullets).
5. WIP.md Phase 30 section deleted.
6. Auto-memory `project_phase_30_post_session.md` written + indexed.
7. `make ci` green. Full E2E run green.

**Test coverage plan** — no new tests. Verify existing post-session + share-flow E2E specs still pass after the PR-celebration route is gone.

**l10n surface** — none.

**Migration / data shape changes** — none.

**Risks + mitigations**

| Risk | Mitigation |
|---|---|
| Dropping `/pr-celebration` route breaks a deep link a user has bookmarked | The route was internal-only, never deep-linked. Hash-route URLs on web aren't share-stable. No risk. |
| Memory entry overlaps existing entries | Cross-reference + dedupe at index time. Run `grep` in MEMORY.md for prior post-session entries. |
| Lingering text search in non-spec files (e.g. comments) | Acceptable — comments referencing deleted widgets surface as drift but don't block. Reviewer may request scrubbing in same PR. |

---

### Critical path / dependency graph

```
PR 29.5  ─────────────────────────►  thin_flash_overlay + CelebrationEvent.personalRecord variant + queue slot policy
                                                                     │
                                                                     ▼
PR 30a   ─────────────────────────►  post-session screen + state machine + summary panel + finish-coord wiring + EQUIP migration
                                                                     │
                                                                     ▼
PR 30b   ─────────────────────────►  share card pipeline (depends on 30a's CTA placeholder)
                                                                     │
                                                                     ▼
PR 30c   ─────────────────────────►  cleanup: deprecate pr_celebration_screen + final E2E migration + docs

Phase 29 PR 2 (#252) and PR 3 ship on a parallel track — no file overlap with Phase 30.
```

**Total estimated PR LOC** (excluding tests + l10n):
- PR 29.5: −1163 (deletions) + ~250 (new thin_flash + personalRecord variant + builder wiring) ≈ **net −910 LOC**
- PR 30a: ~2400 LOC across screen, state machine, 7 cut widgets, summary panel, choreographer, coordinator wiring
- PR 30b: ~1500 LOC across share pipeline + variant renderers + permission handling
- PR 30c: −476 (pr_celebration_screen) + ~100 (docs + auto-memory) ≈ **net −376 LOC**

Phase 30 cumulative net: ~+2600 LOC, but with **1639 LOC deleted** — net feature surface is ≈+4239 LOC of additions offset by retiring 1639 LOC of legacy.

### CI considerations

| Gate | Status | Where |
|---|---|---|
| `scripts/check_thin_flash_no_glow.sh` | NEW · PR 29.5 | Greps `lib/features/rpg/ui/overlays/thin_flash_overlay.dart` for forbidden tokens (BoxShadow, BorderRadius, blur(, ScaleTransition, SlideTransition, FadeTransition). Wired into `make ci` |
| `scripts/check_typography_call_sites.sh` | EXISTING · enforced | Continues to enforce — new post-session widgets must use AppTextStyles. Reviewer flags any raw `TextStyle(fontFamily:)` in new files |
| `scripts/check_exercise_translation_coverage.sh` | EXISTING · unaffected | No new default exercises shipped in Phase 30 |
| `dart analyze --fatal-infos` | EXISTING · enforced | New widget files must pass; unused_import will catch leftover imports from deleted overlays |
| Golden test reference goldens | NEW · 30a + 30b | 10 post-session state goldens (30a) + 3 share-card goldens (30b). Stored in `test/unit/.../goldens/` per Flutter convention. Re-baseline only on intentional design changes; reviewer must approve baseline updates |
| E2E smoke gate | EXISTING · enforced | New specs (`celebration_flashes.spec.ts` in 29.5, `post_session.spec.ts` in 30a, `share_flow.spec.ts` in 30b) all tagged `@smoke` |
| Android debug APK build | EXISTING · enforced | Critical for PR 30b due to manifest + Kotlin compile of new deps |

### E2E selector migration table

| PR | Old identifier | New identifier | Notes |
|---|---|---|---|
| 29.5 | `[flt-semantics-identifier="rank-up-overlay"]` | `[flt-semantics-identifier="thin-flash-rank-up"]` | Variant attribute on the new widget |
| 29.5 | `[flt-semantics-identifier="level-up-overlay"]` | `[flt-semantics-identifier="thin-flash-level-up"]` | |
| 29.5 | `[flt-semantics-identifier="first-awakening-overlay"]` | `[flt-semantics-identifier="thin-flash-first-awakening"]` | |
| 29.5 | `[flt-semantics-identifier="title-unlock-sheet"]` | `[flt-semantics-identifier="thin-flash-title"]` | EQUIP affordance moves to post-session summary in 30a |
| 29.5 | `[flt-semantics-identifier="class-change-overlay"]` | `[flt-semantics-identifier="thin-flash-class-change"]` | All sub-elements (subtitle, name-label, previous-label) DELETED — flash has no sub-labels |
| 29.5 | (no current identifier) | `[flt-semantics-identifier="thin-flash-pr"]` | NEW mid-workout PR flash variant |
| 30a | `[flt-semantics-identifier="pr-celebration-screen"]` | `[flt-semantics-identifier="post-session-screen"]` | Route + screen renamed; alias kept until 30c |
| 30a | (none) | `[flt-semantics-identifier="post-session-b1-xp"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-b2-tally"]` | New (`variant=single|sequential|cascade|elevated`) |
| 30a | (none) | `[flt-semantics-identifier="post-session-b3-pr"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-b3-title"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-b3-class-change"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-summary"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-continue-cta"]` | New |
| 30a | (none) | `[flt-semantics-identifier="post-session-title-equip-row"]` | New (replaces `title-unlock-sheet-equip-button`) |
| 30a | (none) | `[flt-semantics-identifier="empty-session-guard-sheet"]` | New |
| 30b | (none) | `[flt-semantics-identifier="share-sheet"]` | New |
| 30b | (none) | `[flt-semantics-identifier="share-preview-screen"]` | New |
| 30b | (none) | `[flt-semantics-identifier="share-variant-toggle"]` | New (Minimal ↔ Destaque) |
| 30c | All deprecated aliases | DELETED | Final scrub |

### Open questions for user — **RESOLVED 2026-05-21**

All 9 questions answered by user; **all plan defaults accepted**. Locked decisions:

1. **rank_up_overlay.dart RETIRED** along with the other 4 widgets (5 retired total, all flow through `thin_flash_overlay.dart`).
2. **PR detection fires DURING FINISH-DRAIN only**, not per-set real-time. Same path as rank-up.
3. **PR 29.5 dispatches AFTER #252 merges** (Phase 29 PR 2). Serial timeline.
4. Baseline B1 copy alternates via **session-number % 2** between "ENCERRADO. MAIS FORTE." and "CONSISTÊNCIA VENCE."
5. Share CTA visible when queue contains **any of PR / rank-up / title / class-change**.
6. Title EQUIP success → **"Equipado ✓" inline, no auto-advance**.
7. **Post-session screen is ephemeral**, fires once per finish, never replayable from history.
8. **Long-press skip disabled on the summary panel** (avoids ambiguity with EQUIP row tap).
9. **Web platform: Android-first**. Share preview renders; export uses `navigator.share()` if available else download link. Documented as known limitation.

Historical question text preserved below for traceability.

---

1. **PR 29.5 retains `rank_up_overlay.dart`?** The mockup §4½ lists rank-up as a NEW mid-workout flash variant ("Replaces · (no current overlay — added)") — meaning the existing 491-LOC `rank_up_overlay.dart` is the POST-finish overlay used by `celebration_player`, not a mid-workout one. The plan currently retires it along with the other 4 because `thin_flash_overlay.dart` is the single dispatch target for `celebration_player` post-redesign. Is that the intent? Or should rank-up keep its rich 1100ms post-finish ceremony while only being added as a mid-workout flash variant? **Plan default:** retire `rank_up_overlay.dart` along with the others; post-finish celebrations all play as 400ms flashes (consistent with the mockup's "mid-workout = brief environmental notification" framing). Confirm or override.

2. **PR ordering vs Phase 29 PR 2 (#252) and PR 3.** Both are in flight on parallel tracks. The plan assumes Phase 29 PRs are merged or independent. Confirm: dispatch PR 29.5 immediately after Phase 29 PR 2 merges (current sequence), or before? Phase 30 only depends on the celebration event surface, not the XP formula. **Plan default:** wait for #252 to merge, then dispatch 29.5 off main.

3. **B1 baseline copy alternation.** Mockup §5 State 2 script says "ENCERRADO. MAIS FORTE." alternates with "CONSISTÊNCIA VENCE." session-over-session, "alternation seeded from session number; deterministic." The plan has both as separate ARB keys; the alternation logic lives in `RewardTier.derive` (returns one of two for baseline tier based on `workoutSessionNumber % 2`). Confirm that's the right hook — or should the alternation be more complex (e.g. weighted, time-of-day, mood-based)? **Plan default:** session-number-modulo-2 alternation, no more complexity.

4. **PR detection source-of-truth for the mid-workout flash.** PRs are detected per-workout in `peak_loads_repository.dart` at finish time. Should the mid-workout PR flash (mockup §4½ variant — new!) fire AT THE MOMENT the set is logged (requires real-time peak comparison on every set save) or DURING the celebration drain at finish? **Plan default:** during the finish drain only — same path as rank-up. Real-time per-set PR detection is a follow-up if telemetry shows users miss the mid-workout PR moment. Confirm or escalate.

5. **Share CTA visibility rule.** Mockup §5 shows the share CTA on State 3 (PR), 4 (multi-PR), 5 (rank-up), 6 (multi rank-up), 8 (title), 9 (class change), 10 (max combo). NOT on State 1 (day-zero), 2 (baseline), or 7 (level-up). The plan implements this as "show share CTA when `queueResult` contains ANY of: PR, rank-up, title, class-change." Confirm.

6. **Title EQUIP success behavior.** When the user taps EQUIPAR in the summary panel and the RPC succeeds, the plan updates the row to "Equipado ✓" inline and the user can still tap CONTINUAR to leave. No auto-advance. Confirm — or should equipping auto-advance to home?

7. **Backfill: should the post-session screen replay for the in-flight workout if the user backs out and re-enters via history?** The plan locks: post-session is ephemeral, fires once per finish, never replayable from history. History details remain on the workout-detail screen. Confirm.

8. **Skip-to-skip gesture range.** Long-press 500ms anywhere → jump to summary. Does that include the summary panel itself (no-op) and the title EQUIP row (would be ambiguous)? **Plan default:** long-press disabled once the summary panel is visible; the title row has its own tap target inside that surface. Confirm.

9. **Web platform parity.** PR 30b's share flow degrades gracefully on Flutter web (browser file-input vs native picker; no camera roll save). Is web parity a blocker for launch, or is it acceptable as a known limitation that surfaces a "Use the mobile app for the full share experience" hint? **Plan default:** Android-first; web shows the share preview but the export goes through `navigator.share()` if available, else a download link. Documented as known limitation.

---

## Compact-restore checklist

When restoring after `/compact`:

1. Re-read this WIP.md FIRST — Phase 30 plan is the canonical section.
2. Phase 29 is FULLY SHIPPED (PRs #251, #252, #253 all merged; migration `00065` on hosted Supabase). No Phase 29 state to track.
3. Read `docs/post-session-screen-mockup-v2.html` if any Phase 30 work resumes (locked spec).
4. If user authorizes PR 29.5 dispatch → tech-lead reads `lib/features/rpg/ui/overlays/*.dart` (5 retired files) + `celebration_event.dart` + `celebration_event_builder.dart` + `celebration_queue.dart` + `celebration_player.dart` before writing the new `thin_flash_overlay.dart`
5. Auto-memory entries referenced by the plan: `project_phase_29_v2_formula.md`, `feedback_pr_decomposition_parity_invariant.md`, `feedback_engineering_quality_bar.md`, `feedback_design_token_sweep_on_new_tokens.md`, `feedback_widget_l10n_parameterization.md`

## Active background processes

None. Phase 29 fully merged; ready for next dispatch (PR 29.5 thin-flash overlay redesign).
