# Home → Workout Completion — Flow Audit

> Consolidates a 2026-05-27 three-agent investigation: code map +
> E2E coverage matrix + test plan (flow-mapper agent) and a deep
> code review for bugs / convention violations (feature-dev:code-reviewer
> agent). Findings are triaged across Phase 32 sub-PRs (32a–32g).
>
> Scope: a user opens the app on Home and progresses through finishing
> a workout. End-to-end: Home → routine/free-workout start → active
> workout (set logging + rest + finish coordination) → post-session
> cinematic + Mission Debrief → return to Home. Out of scope: Saga,
> Stats, Titles, Profile, Routine creator, Plan editor (those have
> their own Phase 32 PRs).

## 1. Code map

### UI screens

| File | Role |
|---|---|
| `lib/features/workouts/ui/home_screen.dart` | Home shell + `homeReadyProvider` 4-provider gate + skeleton |
| `lib/features/workouts/ui/active_workout_screen.dart` | Full-screen logging surface; PopScope/back priority; route-scoped messenger |
| `lib/features/workouts/ui/post_session/post_session_screen.dart` | 3-beat cinematic + summary panel host |
| `lib/features/workouts/ui/post_session/share/share_preview_screen.dart` | Discreet/D3 share preview + retake + export |
| `lib/features/routines/ui/routine_list_screen.dart` | Routine list (Home falls through via `_HomeRoutinesList`) |

### UI widgets — Home

`character_card.dart` (expanding card + closest-rank-up) · `bucket_chip_row.dart` (chip wrap + Editar plano link) · `action_hero.dart` (3-branch CTA) · `home_greeting.dart` (Phase 27 L2 eyebrow+name) · `encouragement_nudge.dart` (5-priority rotating line) · `last_session_line.dart` · `resume_workout_banner.dart` · `pr_chip.dart`.

### UI widgets — Active Workout

`exercise_card.dart` · `exercise_list.dart` (reorderable) · `set_row.dart` (weight/reps stepper, long-press cycle, swipe-to-delete) · `exercise_picker_sheet.dart` · `add_exercise_fab.dart` · `finish_bottom_bar.dart` · `rest_timer_overlay.dart` · `elapsed_timer.dart` · `active_workout_app_bar_title.dart` · `active_workout_loading_overlay.dart` · `empty_workout_body.dart` · `discard_workout_dialog.dart` · `finish_workout_dialog.dart` · `empty_session_guard_sheet.dart` · `resume_workout_dialog.dart` · `swap_exercise_confirm_dialog.dart` · `add_to_plan_prompt.dart`.

### UI widgets — Post-session

`cuts/b1_xp_cut.dart` · `cuts/b2_bp_tally_cut.dart` · `cuts/b2_cascade_cut.dart` · `cuts/b2_elevated_cut.dart` · `cuts/b3_pr_cut.dart` · `cuts/b3_title_cut.dart` · `cuts/b3_class_change_cut.dart` · `cuts/cinematic_skip_button.dart` · `cuts/cinematic_tap_hint.dart` · `cuts/cut_slash.dart` · `summary/post_session_summary_panel.dart` · `summary/mission_debrief_section.dart` · `summary/widgets/lift_row.dart` · `summary/widgets/xp_segmented_bar.dart` · `summary/title_equip_row.dart` · `summary/next_step_hook.dart` · `summary/share_cta_button.dart` · `share/share_sheet.dart` · `share/share_card_renderer.dart` · `share/share_card_typography.dart` · `share/variants/share_card_achievement_frame.dart` · `share/variants/share_card_discreet.dart`.

### Coordinators

`coordinators/finish_workout_coordinator.dart` (re-entrance + pre-await captures + dialog + cinematic push) · `coordinators/discard_workout_coordinator.dart` · `coordinators/bodyweight_prompt_coordinator.dart` (Phase 24c-8) · `coordinators/celebration_orchestrator.dart` (offline-skipped, queue consume) · `coordinators/post_workout_navigator.dart` (slimmed 3-branch fallback).

### Providers / notifiers

Workouts: `providers/notifiers/active_workout_notifier.dart` (state machine, Hive autosave, celebration queue build, `FinishWorkoutResult` record) · `providers/notifiers/rest_timer_notifier.dart` · `providers/workout_providers.dart` · `providers/workout_history_providers.dart` · `providers/streak_provider.dart` · `providers/share_controller.dart` (6-state share machine).

Adjacent feature providers: `routines/providers/notifiers/routine_list_notifier.dart` · `routines/providers/routine_providers.dart` · `weekly_plan/providers/weekly_plan_provider.dart` · `weekly_plan/providers/suggested_next_provider.dart` · `weekly_plan/providers/weekly_engagement_provider.dart` · `profile/providers/profile_providers.dart` · `rpg/providers/rpg_progress_provider.dart` (pre-finish `bpRankBefore`) · `rpg/providers/earned_titles_provider.dart` · `rpg/providers/class_provider.dart` · `rpg/providers/active_title_provider.dart` · `personal_records/providers/pr_providers.dart` · `analytics/providers/analytics_providers.dart` · `core/offline/pending_sync_provider.dart`.

### Repositories + storage

`features/workouts/data/workout_repository.dart` (calls `save_workout` RPC) · `features/workouts/data/workout_local_storage.dart` (Hive `active_workout` box) · `features/workouts/data/share_service.dart` (image_picker + share_plus + permission_handler with `kIsWeb` short-circuit per cluster) · `features/workouts/data/share_image_renderer.dart` (1080×1920 RepaintBoundary→PNG) · `features/routines/data/routine_repository.dart` · `features/weekly_plan/data/weekly_plan_repository.dart` · `features/profile/data/profile_repository.dart` · `features/personal_records/data/pr_repository.dart` · `core/offline/offline_queue_service.dart` · `core/offline/sync_service.dart`. **Edge Functions touched by this flow: none** — `save_workout` is a Postgres RPC.

### Domain helpers

`workouts/domain/post_session_choreographer.dart` (cinematic cut list builder) · `workouts/domain/post_session_timing.dart` · `workouts/domain/reward_tier.dart` (S2/S3/S4 tier derivation) · `workouts/domain/session_lift_summary.dart` (Mission Debrief top-N) · `workouts/domain/pr_row_state.dart` + `pr_row_state_resolver.dart` · `workouts/domain/pr_score.dart` · `workouts/domain/share_payload.dart` · `workouts/domain/closest_rank_up.dart` · `workouts/domain/encouragement_nudge_priority.dart` · `workouts/utils/set_defaults.dart` · `workouts/utils/set_filters.dart` · `rpg/domain/celebration_event_builder.dart` · `rpg/domain/celebration_queue.dart` (with `SlotPolicy`) · `rpg/domain/title_unlock_detector.dart` · `rpg/domain/class_resolver.dart` · `rpg/domain/character_xp_calculator.dart` · `rpg/domain/rank_curve.dart` · `weekly_plan/domain/weekly_engagement.dart` · `weekly_plan/utils/routine_duration_estimator.dart` · `personal_records/domain/pr_detection_service.dart`.

### Models (Freezed)

`workouts/models/active_workout_state.dart` · `workouts/models/exercise_set.dart` · `workouts/models/set_type.dart` · `workouts/models/weight_unit.dart` · `workouts/models/workout.dart` · `workouts/models/workout_exercise.dart` · `workouts/models/routine_start_config.dart` · `workouts/ui/post_session/post_session_state.dart` · `workouts/domain/session_lift_summary.dart` · `workouts/domain/share_payload.dart` · `core/offline/pending_action.dart` · `routines/models/routine.dart` · `rpg/models/celebration_event.dart` (sealed) · `rpg/models/body_part_progress.dart` · `rpg/models/character_sheet_state.dart` · `weekly_plan/data/models/weekly_plan.dart`.

### SQL migrations touching the flow

`00050_save_workout_skip_zero_weight_peak.sql` · `00051_peak_loads_multi_writer_guard.sql` · `00052_peak_loads_writer_site_guards.sql` · `00057_record_xp_with_bodyweight_load.sql` · `00059_phase24d_calibration_propagation.sql` · `00060_titles_award_at_detection.sql` · `00061_backfill_earned_titles.sql` · `00062_weekly_plan_is_spontaneous_backfill.sql` · `00063_save_workout_bucket_update.sql` · `00064_peak_load_per_body_part.sql` · `00065_phase29_xp_formula_v2.sql`.

## 2. E2E coverage matrix

Spec key: `WK`=workouts · `RT`=routines · `HM`=home · `CR`=crash-recovery · `OFF`=offline-sync · `RU`=rank-up-celebration · `PS`=post_session · `SH`=share_flow · `BW`=bodyweight-prompt · `WP`=weekly-plan · `CHB`=charter-b-exploratory.

| # | Functional path | Spec(s) | Smoke? | Status |
|---|---|---|---|---|
| 1 | Cold-start home — fresh day-0 | HM:404 (skipped) | n/a | **NOT COVERED** — no zero-routine seeded user |
| 2 | Cold-start home — foundation user | HM:274–318 | regression | COVERED |
| 3 | Cold-start home — lapsed (1 workout) | HM:109–264 | smoke | COVERED |
| 4 | ActionHero "Start" → workout start | HM:369–378 | smoke | COVERED (presence only) |
| 5 | ActionHero "Free Workout" → workout start | HM:203–214, WK, RU | smoke | COVERED |
| 6 | Tap planned bucket chip → routine sheet → start | none | n/a | **NOT COVERED** |
| 7 | Routine list → start | RT:340–374, RT:616, RT:1041 | smoke | COVERED |
| 8 | 3 exercises × 3 sets happy path | WK:182–224 (1×1 only) | smoke | **PARTIAL** |
| 9 | Set type toggle (warmup / drop / failure) | CharterA:306 | exploratory | **PARTIAL** — no behavior assertion |
| 10 | Rest timer countdown + auto-advance | CHB:234–308, CharterA:395 | exploratory | **PARTIAL** — countdown progression not pinned |
| 11 | Exercise navigation forward + back | none (scroll-based) | n/a | NOT COVERED |
| 12 | Mid-workout discard with data → confirm | WK:254–284, WK:667–699, RT:334–337 | smoke | COVERED |
| 13 | Mid-workout discard no data → no confirm | none | n/a | **NOT COVERED** |
| 14 | Finish all sets → post-session cinematic plays | WK:646, RU:419, PS | smoke | COVERED |
| 15 | Finish with incomplete sets → confirm + skip | WK:597–644 | regression | COVERED (Keep Going only; skip branch not pinned) |
| 16 | Finish offline → queue → online → sync | OFF:212–252, CHB:576–658 | smoke | COVERED |
| 17 | B1 XP cut → B2 cascade → B3 PR sequence | none | n/a | **NOT COVERED** — beat progression not asserted |
| 18 | Post-session with rank-up event | RU:419–504, PS | smoke | COVERED at server-state level |
| 19 | Post-session with title-unlock event | RU:506–634 | smoke | COVERED (queue sequencing — summary slot not asserted) |
| 20 | Post-session with class-change event | none | n/a | **NOT COVERED** — no fixture user |
| 21 | Mission Debrief: lifts + XP bar + rank deltas | PS:92–131 | smoke | COVERED (presence only — not top-4 ordering, not "+N more", not "next-target") |
| 22 | Share CTA → sheet → variant → export | SH:154–210 | smoke | COVERED for sheet+Discreet+retake; PNG write not asserted |
| 23 | Return Home → bucket chip "done" | WK:226–252 (presence) | smoke | **PARTIAL** — done-state Semantics flag not asserted |
| 24 | Return Home → week-plan completion banner | WP, HM `_ConfirmBanner` | smoke | **PARTIAL** — completion banner not pinned |
| 25 | Resume banner after navigation/reload | CR:170–304 | regression | COVERED |
| 26 | Resume banner gone after finish | CR:365–409 | regression | COVERED |
| 27 | Rapid double-tap Finish — no duplicate workout | CR:411–449 | regression | COVERED |
| 28 | Decimal weight 22.5 round-trip | WK:717–774 | regression | COVERED |
| 29 | Bodyweight prompt on `uses_bodyweight_load` | BW:44 | smoke | COVERED |
| 30 | PopScope leave-confirm on `/workout/finish/:id` | none | n/a | **NOT COVERED** — Phase 31 invariant |
| 31 | EmptySessionGuardSheet (0 sets + finish) | none | n/a | **NOT COVERED** — Phase 30 PR 30a invariant |
| 32 | Set undo SnackBar above rest scrim | WK:1090–1232 | regression | COVERED |
| 33 | Add-exercise undo SnackBar | WK:1894–2055 | regression | COVERED |
| 34 | Background mid-workout (state preservation) | CHB:178–308 | exploratory | COVERED via charters (not formal regression) |
| 35 | Landscape rotation mid-workout | CHB:373–512 | exploratory | COVERED via charters |
| 36 | Set-row swipe-delete + cascade restore | WK:1090, WK:2202 | regression | COVERED |
| 37 | Exercise swap (long-press header) | WK:1613–1893 | regression | COVERED |
| 38 | `workoutSavedServerError` vs `workoutSavedOffline` copy | none | n/a | **NOT COVERED** — only navigation pinned, not copy switch |

Smoke coverage: ~30 / 38 paths. Eight bold gaps require new tests.

## 3. Test plan

### 3.1 Critical paths (smoke gate)

1. **Day-0 first-workout.** Fresh user with zero workouts sees `home-action-hero-create-first-routine`, taps Free Workout, logs one set, finishes; lands on post-session with a single-set B1 XP cut visible, then summary; back on Home the Last Session line shows count=1.
2. **Routine → workout → cinematic happy path.** Lapsed user taps planned bucket chip → routine action sheet → Start → active workout opens with routine exercises pre-filled (non-zero weight for barbell, BUG-004) → completes all sets → finishes → cinematic plays B1 → S2 → Mission Debrief mounts.
3. **Mid-workout discard with set data.** Free workout, log one set, tap X → discard dialog visible with "Discard?" copy → confirm → Home visible.
4. **Finish offline → queue → drain online.** Log set, block REST, finish; land Home with `PendingSyncBadge` "1 workout pending sync"; restore REST; tap retry; badge hidden. Pins offline queue path + cinematic bypass + `workoutSavedOffline` snackbar copy.
5. **Crash recovery.** Start workout, reload page; resume banner appears on Home; tap returns to workout with set data intact.
6. **Empty-session guard.** Add exercise, tap Finish with 0 completed sets → `EmptySessionGuardSheet` appears (NOT cinematic). Pins Phase 30 PR 30a invariant.
7. **Post-session leave-confirm.** On `/workout/finish/:id`, browser/hardware back triggers Phase 31 leave-confirm; "Stay" keeps screen, "Leave" navigates to Home and persists workout.

### 3.2 Edge cases by surface

**Home.** Empty bucket (chip-row hidden, Editar plano shown) · full-bucket (7 chips at max density) · all-done week · single-BP-trained user (closest-rank-up resolves to that BP, not fallback) · never-ranked user → day-0 fallback (HM:184 covers) · rank-up mid-session → indicator updates same session (stale-cache risk, not covered) · profile photo not loaded (PR 32e scope, defer) · network slow → `homeReadyProvider` holds skeleton (skeleton render not asserted).

**ActiveWorkout.** 0 sets + Finish (Critical #6) · 100+ sets (perf, unit only) · exercise rest=0 / rest=999s · weight=0 (covered partially by BW spec) · weight=MAX_INT (bar overflow) · weight beyond visual-scale ceiling · 1RM single rep / 100-rep set · decimal weight 22.5 (WK:717 covers) · tap-to-copy from previous set (`lastWorkoutSetsProvider` consumer; not E2E) · long-press cycle on set type (CharterA only) · very long exercise notes · rapid 10-set entry (CharterA exploratory) · backgrounding mid-set (CHB) · lock screen mid-rest (CHB).

**PostSession.** Single-set / very low XP · 5+ BP trained → long Mission Debrief with "+N more" footer · max-combo cinematic (PR + rank-up + level-up + class-change + title) · share-card under low memory (device-only) · share-card with no photo → Discreet variant (SH:168 covers) · wide aspect-ratio photo + drag-to-reframe · "Next target" callout on rank-r9 (next is title threshold).

**Return-to-home.** Rank changed mid-flight (`bpRankBefore` capture is canonical fix per `cluster_async_caller_broke_snackbar`) · class changed → character-card shows new class · workout spans midnight (`bucket_chip_row` vs `week_plan_screen` `.toLocal()` parity — Phase 32c open bug).

### 3.3 Chaos / failure modes

**Network.** Offline at workout start → Home from Hive cache, `homeReadyProvider` stall · offline at finish (OFF:212 covers) · offline during rest timer (CHB) · flaky 200–1000 ms latency variance · Supabase 503 mid-save → `serverErrorQueued` + `workoutSavedServerError` copy (**not E2E asserted**) · 401 / JWT expiry mid-save (terminal rethrow) · Edge Function timeout (n/a — flow doesn't call Edge Functions during completion).

**DB.** RLS rejection (defense-in-depth) · CHECK constraint (negative reps from a debug path; `record_session_xp_batch` guards but not asserted; `cluster_check_violation_writer_audit`) · UNIQUE conflict on optimistic insert · JSONB null in payload (`cluster_jsonb_payload_vs_typed_dart` — spontaneous workout `routineId == null` regressed in PR 30a Bug F, no E2E coverage).

**Race conditions.** Rapid double-tap Start (Finish covered, Start not) · rapid finish-then-cancel (`_isFinishing` guard exists, not E2E) · two devices same account same workout · sync queue at 50+ pending · set-save fires while another set is optimistically saving (`cluster_optimistic_ui_vs_async_provider`).

**Time.** Device clock skew (server `now()` is authoritative; client `DateTime.now()` for `startedAt`) · timezone change mid-workout (Phase 32c known bug) · workout spans midnight (Phase 32c known bug).

**Hardware.** 320 dp viewport (`visual_30b.spec.ts` captures manually) · 480 dp+ tablet · textScaler 1.5× · Samsung One UI gesture pill (`cluster_safearea_system_overlay_overlap`) · battery saver / low battery · RAM pressure OOM kill (Hive recovery contract).

**Permissions.** image_picker denied (Android 13+ Photos) · camera denied · storage denied — `share_service.dart` graceful fallback exists, no E2E.

### 3.4 Test gaps — implementation priorities

| Prio | Gap | Layer | One-line description | Routes to |
|---|---|---|---|---|
| Critical | EmptySessionGuardSheet (Phase 30 invariant) | E2E (`workouts.spec.ts`) | 0 completed sets + Finish → assert sheet visible, NOT `/workout/finish` URL | 32g |
| Critical | PopScope leave-confirm (Phase 31) | E2E (`post_session.spec.ts`) | Press back on `/workout/finish/:id` → leave-confirm dialog; "Stay" keeps URL, "Leave" goes /home | 32g |
| Critical | Class-change cinematic + EQUIP row | E2E (new fixture `rpgClassChangeThreshold`) | Seed BP progress so finish flips class → assert `b3_class_change_cut` + EQUIP detail row | 32g |
| Critical | `workoutSavedServerError` vs `workoutSavedOffline` copy | E2E (`offline-sync.spec.ts`) | Block REST with 500 (not connectionrefused) → assert server-error variant of snackbar | 32g |
| High | 3-exercise × 3-set happy path | E2E (extend `workouts.spec.ts`) | Bench/squat/deadlift × 3 sets → finish → Mission Debrief top-4 includes all three | 32g |
| High | Mid-workout discard no-data → no confirm | E2E (`workouts.spec.ts`) | Empty workout, no sets, tap X → no dialog, on Home immediately | 32g |
| High | Bucket chip "done" flip on return | E2E (`weekly-plan.spec.ts`) | Plan Push Day, complete, return Home → chip carries done-state Semantics flag | 32c (pairs with picker fix) |
| High | Tap planned bucket chip → routine sheet → Start | E2E (`home.spec.ts`) | After `ensurePushDayInPlan`, tap chip → assert `RoutineActionSheet`, Start → active workout | 32g |
| High | Mission Debrief top-N + "+N more" footer | Widget (`mission_debrief_section_test.dart`) | 6 lifts → exactly 4 rows + footer text `+2 mais` | 32g |
| High | Decimal weight + bodyweight load → XP integration | Integration (live Supabase) | Pull-up + 0.5 kg × 5 → admin query `xp_events.payload.effective_load == bw + 0.5` | 32g |
| High | Rest-timer countdown + auto-advance | Widget (`rest_timer_overlay_test.dart`) | 30 s timer → `tester.pump(31s)` → overlay gone + active row visible (cluster `pump-duration-masks-forward`) | 32g |
| Medium | Rapid double-tap Start (not Finish) | E2E | Tap Free Workout twice in 100 ms → exactly one server-side workout row | defer to v1.1 |
| Medium | Cross-device same account | Integration | Two clients finish same workoutId concurrently → server keeps one row | defer to v1.1 |
| Medium | Workout spans midnight (BRT) | Widget + E2E | Mock `DateTime.now()` rollover → both surfaces agree | **PR 32c regression guard** |
| Medium | Day-0 ActionHero create-first-routine | E2E (new `noDefaultRoutines` fixture) | Filter seed routines → assert `home-action-hero-create-first-routine` visible (HM:404 skipped today) | 32g |
| Medium | Long Mission Debrief (6+ BPs) layout | Widget | All 6 BPs trained → `xp_segmented_bar` 6 segments, no overflow at 320 dp | 32g |
| Medium | textScaler 1.5× on Home + ActiveWorkout | Widget | `MediaQuery(textScaler: 1.5)` → no RenderFlex overflow | defer to v1.1 |
| Medium | Share preview drag-to-reframe | Widget | Pump `SharePreviewScreen`, drag offset → `cardWidthDp/cardHeightDp` reflects | defer to v1.1 |
| Low | RLS rejection defense | Integration | Forge payload for `user_id != auth.uid()` → RPC rejects | defer to v1.1 |
| Low | 100-rep peak-load bucketing | Integration | 100×100 reps → correct rep_band row | defer to v1.1 |
| Low | Wide-aspect photo in share preview | Manual / device | Camera/Playwright limitation | already deferred (PR 30c) |
| Low | Battery saver + lock screen mid-rest | Manual / device | Wakelock disable under battery saver | defer to v1.1 |

## 4. Code review findings

### 4.1 Confident bugs

**Bug 1 — Workout duration wrong every finish. _High._**

- **File:** `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart:550`
- **Scenario:** `_computeDurationMinutes(currentState)` reads `currentState.workout.finishedAt`. `currentState` is the snapshot captured BEFORE `await notifier.finishWorkout()`, so `finishedAt` is always `null` at that point. The fallback `?? DateTime.now()` (local) is the **only branch ever taken**, and it disagrees with the notifier's `DateTime.now().toUtc()` (which gets persisted) by the device UTC offset. Off by 3 h on BRT every finish.
- **Root cause:** Reading state mutated by the awaited call — same lifecycle anti-pattern as `cluster_async_caller_broke_snackbar`.
- **Fix:** Capture `DateTime.now().toUtc()` into a pre-await variable (the comment block at L195 already documents this pattern for `priorWorkoutCount`, `preFinishSetsCount`, etc.) and use that as `end`. OR expose `durationSeconds` from `FinishWorkoutResult` directly — the notifier already computes it at L1379.
- **Cluster:** `async-caller-broke-snackbar` (extended).
- **Routes to:** PR 32g.

**Bug 2 — `developer.log` invisible on `adb logcat` in critical save path. _High._**

- **Files:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:1` (import) + ~7 call sites (L1441, L1448, L1688, L1711, L1747, L1955, L1972) · `lib/features/workouts/data/workout_local_storage.dart:2` · `lib/features/workouts/ui/coordinators/celebration_orchestrator.dart:103, :188` (L188 carries a comment claiming `developer.log` goes to logcat — factually wrong).
- **Scenario:** `dart:developer.log()` writes to the Dart VM developer stream (DevTools / `flutter run`) only. NOT to `adb logcat`. On a physical Android device in the gym, a user reporting "save failed" / "celebration didn't fire" / "PR not detected" cannot be triaged.
- **Root cause:** Cluster `developer-log-invisible-logcat`.
- **Fix:** Replace all `log(...)` calls in these files with `debugPrint('[ActiveWorkoutNotifier] ...')` etc. Delete the misleading comment in `celebration_orchestrator.dart:188`.
- **Routes to:** PR 32g.

**Bug 3 — Title equip RPC errors silently rethrown. _Medium._**

- **Files:** `lib/features/workouts/ui/post_session/post_session_screen.dart:557–562` · `lib/features/workouts/ui/post_session/summary/title_equip_row.dart:74–79`.
- **Scenario:** `_TitleEquipRowState._handleEquip` resets loading state then rethrows. The screen's `onEquipPressed` async closure has no try/catch — exception becomes an unhandled `Future` rejection. User sees the button reset but no error feedback, despite the row's documented contract: "The screen layer surfaces error snackbars."
- **Root cause:** Missing error handler at the screen-layer / widget-contract boundary.
- **Fix:** Wrap the closure body in try/catch; show a localized snackbar via `ScaffoldMessenger.of(context)`.
- **Routes to:** PR 32g.

### 4.2 Likely bugs

**Likely Bug 1 — `celebration_orchestrator.dart:188` `developer.log` for rank-up pulse failures. _Medium._** Same cluster as Bug 2. Folded into PR 32g.

**Likely Bug 2 — `weeklyPlanNeedsConfirmationProvider` not persisted. _Medium._**

- **Files:** `lib/features/workouts/ui/home_screen.dart:361–369` · `lib/features/weekly_plan/providers/weekly_plan_provider.dart:365`.
- **Scenario:** `StateProvider<bool>((ref) => false)` is in-memory only. Hot-reload / app restart / process kill resets the pending-confirmation flag to `false` before the user acts. Likely visible to any user who opens the app fresh each week.
- **Fix:** Either persist to Hive OR rederive from server state at provider build.
- **Routes to:** PR 32g.

### 4.3 Suggestions

- **Suggestion 1:** Coordinate clock source between coordinator + notifier. Surface `durationSeconds` from `FinishWorkoutResult` and remove the parallel computation in the coordinator. → PR 32g (folded with Bug 1 fix).
- **Suggestion 2:** Verify `homeReadyProvider` invalidation chain on return-to-home. Low risk. → audit during PR 32g.

### 4.4 Convention violations

| File:line | Violation | Cluster |
|---|---|---|
| `active_workout_notifier.dart:1` + all `log()` sites | `dart:developer.log` for on-device diagnostics | `developer-log-invisible-logcat` |
| `celebration_orchestrator.dart:188` | `developer.log` + misleading "goes to logcat" comment | `developer-log-invisible-logcat` |
| `workout_local_storage.dart:2` | `dart:developer` import for diagnostics | `developer-log-invisible-logcat` |
| `finish_workout_coordinator.dart:241` | `context.mounted` checked after await but `ref.read` used immediately before the check (L246, L279–290). Pattern diverges from the pre-await capture block 5 lines earlier | `async-caller-broke-snackbar` |
| `post_session_screen.dart:557` | Title equip callback swallows errors (see Bug 3) | CLAUDE.md "No Laziness — find root causes" |

## 5. Triage map

| Finding | Severity | Lands in |
|---|---|---|
| Bug 1 — duration off every finish | High | PR 32g |
| Bug 2 — developer.log sweep (3 files) | High | PR 32g |
| Bug 3 — title equip silent rethrow | Medium | PR 32g |
| Likely Bug 1 — orchestrator developer.log | Medium | PR 32g (same sweep) |
| Likely Bug 2 — confirm-banner not persisted | Medium | PR 32g |
| Convention violations (5) | Mixed | PR 32g |
| EmptySessionGuard E2E | Critical | PR 32g |
| Post-session leave-confirm E2E | Critical | PR 32g |
| Class-change cinematic E2E + fixture | Critical | PR 32g |
| Server-error vs offline-error copy E2E | Critical | PR 32g |
| 3-exercise × 3-set happy path E2E | High | PR 32g |
| Discard no-data branch E2E | High | PR 32g |
| Bucket-chip done-flip E2E | High | PR 32c (pairs with picker fix) |
| Tap-chip → routine sheet E2E | High | PR 32g |
| Mission Debrief top-N widget test | High | PR 32g |
| Decimal + bodyweight XP integration | High | PR 32g |
| Rest-timer countdown widget test | High | PR 32g |
| Workout-spans-midnight regression | Medium | **PR 32c regression guard** |
| Day-0 ActionHero E2E (`noDefaultRoutines` fixture) | Medium | PR 32g |
| Long Mission Debrief layout | Medium | PR 32g |
| All other Medium/Low gaps | Medium/Low | defer to v1.1 |

Add **CI grep gate** to `scripts/` preventing future `dart:developer.log` reintroduction in `lib/features/workouts/` + `lib/features/rpg/` (lints only those layers; rest of repo unaffected). Wire into `ci.yml` as a new step.

## 6. Next steps

1. PR 32a is open (#270) — reviewer in flight; QA + admin-merge after.
2. PR 32c (next in revised order: 32a → 32c → 32g → 32d → 32b → 32e → 32f). Picker fix + weekday `.toLocal()` + the bucket-chip done-flip + midnight-parity regressions land together.
3. PR 32g picks up all the bug fixes + 9 of the gap-closing E2E/widget tests + the developer.log CI gate.
4. Class-change fixture work in 32g requires seeding `body_part_progress` so a Finish event flips the class — coordinate with the test-users infrastructure in `test/e2e/global-setup.ts` and `fixtures/test-users.ts`.
