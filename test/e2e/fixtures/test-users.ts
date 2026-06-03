/**
 * Test user fixtures for E2E tests.
 *
 * Each spec file uses its own dedicated user to avoid shared mutable state
 * between test files. Users are created in global-setup.ts and deleted in
 * global-teardown.ts using the Supabase Admin Auth API.
 *
 * Smoke users: isolated users for the smoke spec suite.
 * Full users: isolated users for the full spec suite (one per spec file).
 */

export const TEST_USERS = {
  // -------------------------------------------------------------------------
  // Smoke users (existing)
  // -------------------------------------------------------------------------
  smokeAuth: {
    email: 'e2e-smoke-auth@test.local',
    password: 'TestPassword123!',
  },
  smokeWorkout: {
    email: 'e2e-smoke-workout@test.local',
    password: 'TestPassword123!',
  },
  smokePR: {
    email: 'e2e-smoke-pr@test.local',
    password: 'TestPassword123!',
  },
  smokeExercise: {
    email: 'e2e-smoke-exercise@test.local',
    password: 'TestPassword123!',
  },
  // Regression smoke users — added to cover BUG-001 through BUG-005.
  smokeRoutineStart: {
    email: 'e2e-smoke-routine-start@test.local',
    password: 'TestPassword123!',
  },
  smokeFormTips: {
    email: 'e2e-smoke-form-tips@test.local',
    password: 'TestPassword123!',
  },
  // BUG-001 manual workout restore path (separate from routine-start path).
  smokeWorkoutRestore: {
    email: 'e2e-smoke-workout-restore@test.local',
    password: 'TestPassword123!',
  },
  // BUG-003 negative path smoke (error snackbar when all exercises deleted).
  smokeRoutineError: {
    email: 'e2e-smoke-routine-error@test.local',
    password: 'TestPassword123!',
  },
  // Weekly plan smoke — isolated user for weekly-plan.smoke.spec.ts
  smokeWeeklyPlan: {
    email: 'e2e-smoke-weekly-plan@test.local',
    password: 'TestPassword123!',
  },
  // Onboarding smoke — fresh user (no profile row) for onboarding.smoke.spec.ts
  smokeOnboarding: {
    email: 'e2e-smoke-onboarding@test.local',
    password: 'TestPassword123!',
  },
  // PR 1 — half-onboarded user (profile row exists with display_name set but
  // `onboarded_at = NULL`). Pins the D1 regression: a user who started but
  // didn't finish onboarding must land on /onboarding after sign-in, not on
  // /home (the OLD `StateProvider<bool>` would default to false and misroute).
  onboardingResume: {
    email: 'e2e-onboarding-resume@test.local',
    password: 'TestPassword123!',
  },
  // Routine management smoke — CRUD for routine-management.smoke.spec.ts
  smokeRoutineManagement: {
    email: 'e2e-smoke-routine-mgmt@test.local',
    password: 'TestPassword123!',
  },
  // Weekly plan review smoke — week complete state for weekly-plan-review.smoke.spec.ts
  smokeWeeklyPlanReview: {
    email: 'e2e-smoke-weekly-plan-review@test.local',
    password: 'TestPassword123!',
  },
  // Profile weekly goal smoke — frequency change for profile-weekly-goal.smoke.spec.ts
  smokeProfileWeeklyGoal: {
    email: 'e2e-smoke-profile-goal@test.local',
    password: 'TestPassword123!',
  },
  // First-workout beginner CTA (P8) — fresh user with zero workouts, verifies
  // the new-user empty-state card is visible and tap navigates to /workout/active.
  smokeFirstWorkout: {
    email: 'e2e-smoke-first-workout@test.local',
    password: 'TestPassword123!',
  },
  // Exercise progress chart (P1) — user with two seeded completed working sets
  // on different calendar dates so ProgressChartSection renders the multi-point
  // LineChart branch (single-point renders copy-only with no `image` semantics).
  smokeExerciseProgress: {
    email: 'e2e-smoke-exercise-progress@test.local',
    password: 'TestPassword123!',
  },
  // Offline sync (Phase 14) — dedicated user for offline-sync.spec.ts.
  // Needs a profile row + one prior workout (lapsed state) so startEmptyWorkout
  // finds "Quick workout" rather than the brand-new beginner CTA.
  smokeOfflineSync: {
    email: 'e2e-smoke-offline-sync@test.local',
    password: 'TestPassword123!',
  },
  // Localization smoke (Phase 15e) — dedicated user for localization.spec.ts.
  // Profile row is seeded with locale: 'pt' so the app boots in Portuguese
  // without requiring the test to open the language picker first. Also has
  // one seeded workout so the app lands in lapsed state (not brand-new CTA).
  smokeLocalization: {
    email: 'e2e-smoke-localization@test.local',
    password: 'TestPassword123!',
  },
  // Localization en-default (Phase 15e) — English locale user for testing
  // the en→pt live-switch path and persistence across page reload.
  // No locale seeded in profiles (defaults to English). Has one seeded
  // workout so the app lands in lapsed state (not brand-new CTA).
  smokeLocalizationEn: {
    email: 'e2e-smoke-localization-en@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Full suite users (one per spec file)
  // -------------------------------------------------------------------------
  fullAuth: {
    email: 'e2e-full-auth@test.local',
    password: 'TestPassword123!',
  },
  fullExercises: {
    email: 'e2e-full-exercises@test.local',
    password: 'TestPassword123!',
  },
  fullWorkout: {
    email: 'e2e-full-workout@test.local',
    password: 'TestPassword123!',
  },
  fullRoutines: {
    email: 'e2e-full-routines@test.local',
    password: 'TestPassword123!',
  },
  fullPR: {
    email: 'e2e-full-pr@test.local',
    password: 'TestPassword123!',
  },
  fullHome: {
    email: 'e2e-full-home@test.local',
    password: 'TestPassword123!',
  },
  fullCrash: {
    email: 'e2e-full-crash@test.local',
    password: 'TestPassword123!',
  },
  fullHistory: {
    email: 'e2e-full-history@test.local',
    password: 'TestPassword123!',
  },
  fullManageData: {
    email: 'e2e-full-manage-data@test.local',
    password: 'TestPassword123!',
  },
  // Regression full suite user — added to cover BUG-003/BUG-004/BUG-005.
  fullRoutineRegression: {
    email: 'e2e-full-routine-regression@test.local',
    password: 'TestPassword123!',
  },
  // Exercise detail bottom sheet full spec (BUG-002 in-workout path).
  fullExDetailSheet: {
    email: 'e2e-full-ex-detail-sheet@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 17b — Gamification intro (smoke)
  // -------------------------------------------------------------------------
  // sagaIntroUser: fresh user, no workout history, saga intro never dismissed.
  // Profile row is seeded (display name set) so the router lands on /home, not
  // /onboarding, where SagaIntroGate wraps the shell and shows the overlay.
  sagaIntroUser: {
    email: 'e2e-saga-intro@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 15f — Exercise content localization (pt-BR)
  // -------------------------------------------------------------------------
  // smokeLocalizationWorkout: pt-BR locale user for active-workout smoke tests.
  // Profile seeded with locale:'pt', one prior workout so app lands in lapsed
  // state (not brand-new CTA). Matches smokeLocalization setup pattern.
  smokeLocalizationWorkout: {
    email: 'e2e-smoke-loc-workout@test.local',
    password: 'TestPassword123!',
  },
  // fullHistoryPt: pt-BR locale user for workout history regression.
  // Profile seeded with locale:'pt', 5+ prior workouts so history renders
  // multiple entries.
  fullHistoryPt: {
    email: 'e2e-full-history-pt@test.local',
    password: 'TestPassword123!',
  },
  // smokeLocalizationRoutines: pt-BR locale user for routine create/edit with
  // pt exercise picker smoke. Profile seeded with locale:'pt', one prior
  // workout for lapsed state.
  smokeLocalizationRoutines: {
    email: 'e2e-smoke-loc-routines@test.local',
    password: 'TestPassword123!',
  },
  // fullPRPt: pt-BR locale user for PR list + detail regression.
  // Profile seeded with locale:'pt', prior PRs seeded via seedPRData.
  fullPRPt: {
    email: 'e2e-full-pr-pt@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 18a — RPG Foundation e2e (specs/rpg-foundation.spec.ts)
  // -------------------------------------------------------------------------
  // rpgFoundationUser: ~12 prior workouts spanning 6 weeks across multiple
  // body parts. After backfill, character_state.lifetime_xp > 0 and LVL > 1.
  // Used by 18a-E1 (backfill on first login) and 18a-E4 (XP accumulation).
  rpgFoundationUser: {
    email: 'e2e-rpg-foundation@test.local',
    password: 'TestPassword123!',
  },
  // rpgFreshUser: profile seeded, zero workout history.
  // Used by 18a-E2 (first-workout XP), 18a-E3 (re-save no double XP),
  // and 18a-E6 (compound body-part attribution).
  rpgFreshUser: {
    email: 'e2e-rpg-fresh@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 18c — Rank-up celebration / overlay tests
  // -------------------------------------------------------------------------

  // rpgRankUpThreshold: chest body_part_progress pre-seeded to the Phase 29 v2
  // single-rank-up deterministic window midpoint (chest rank 3 / 157 XP, all
  // others rank 1 / 0 XP). One bench 80x5 set lands chest at 238.3199 XP / rank
  // 4 with ~40 XP margin on either window edge — guarantees one rank-up event,
  // no skip to rank 5, no chest_r5 title threshold crossed. See seed function
  // in global-setup.ts for the full derivation.
  rpgRankUpThreshold: {
    email: 'e2e-rpg-rank-up-threshold@test.local',
    password: 'TestPassword123!',
  },

  // rpgMultiCelebration: pre-seeded such that a single workout finish triggers
  // a chest rank-up + character level-up + title unlock simultaneously.
  // Seeding: chest at rank 4 threshold (≈ 187 XP) so +1 working set of bench
  // press yields rank 5. At rank 5 a title unlocks for chest. Character level
  // = floor((chest_rank_sum - N_active) / 4) + 1; with chest at 5 and
  // all others at 1, level = floor((5+1+1+1+1+1 - 6) / 4) + 1 = floor(5/4) + 1 = 2.
  // We pre-seed arms, back, legs, shoulders, core at rank 1 (0 XP each) and
  // chest at rank 4 boundary (≈ 187 XP). One chest set → chest rank 5 →
  // title unlock + level 2 → full multi-event queue.
  rpgMultiCelebration: {
    email: 'e2e-rpg-multi-celebration@test.local',
    password: 'TestPassword123!',
  },

  // rpgOverflowQueue: all 6 body parts pre-seeded at rank 5 / 354 XP — the
  // midpoint of the deterministic R6-crossing window. One 4-exercise workout
  // (bench / squat / row / OHP) spreads XP across all 6 body parts via
  // primary + secondary attribution, producing exactly 6 single-rank-up
  // crossings (no skips, no class change). The fixture pins the EXACT
  // post-state per-body-part XP totals (1e-4 absolute) that the SQL chain
  // (`record_session_xp_batch`) writes — Dart calculator + Python sim +
  // fixture oracle parity gate. Used by rank-up-celebration.spec.ts S4.
  rpgOverflowQueue: {
    email: 'e2e-rpg-overflow-queue@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // PR-1 audit fixes — cancel-during-start (C4/Q1) regression
  // -------------------------------------------------------------------------
  // smokeWorkoutCancelStart: lapsed user (has one prior workout, profile seeded).
  // Used to test the cancel-during-start → /home flow (audit C4 + Q1).
  // The user is in lapsed state so "Quick workout" appears and we can start
  // via the normal entry point, then intercept the network call.
  smokeWorkoutCancelStart: {
    email: 'e2e-smoke-workout-cancel-start@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 18e — Class system + title-equip E2E
  // -------------------------------------------------------------------------

  // rpgClassCrossUser: chest pre-seeded at rank 4 (270 XP), all others rank 1.
  // After one bench-press set, chest crosses to rank 5 → class flips from
  // Initiate to Bulwark (chest-dominant, max=5 ≥ 5, spread 0.80 > 0.30).
  // Isolated from rpgMultiCelebration so the class-cross test doesn't interfere
  // with the multi-celebration celebration-queue test.
  rpgClassCrossUser: {
    email: 'e2e-rpg-class-cross@test.local',
    password: 'TestPassword123!',
  },

  // rpgTitleEquipUser: chest pre-seeded at rank 5+ so at least one body-part
  // title ("Plate-Bearer" at R5) has been awarded. The user also has a completed
  // backfill so the title appears in earned_titles and the Titles screen shows it
  // as equippable. Used by title-equip.spec.ts to test tap-to-equip flow.
  rpgTitleEquipUser: {
    email: 'e2e-rpg-title-equip@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // PR-2 audit fixes — undo-snackbar reachability + discard-race
  // -------------------------------------------------------------------------
  // smokeWorkoutSwipeUndo: lapsed user (one prior workout, profile seeded) for
  // the "swipe-delete during rest timer → undo SnackBar visible AND reachable
  // above rest-timer overlay" tests (PR-2 C3/Q5). Isolated from
  // smokeWorkoutCancelStart so the swipe/snackbar test never collides with
  // the loading-overlay-cancel test under workers > 1.
  smokeWorkoutSwipeUndo: {
    email: 'e2e-smoke-workout-swipe-undo@test.local',
    password: 'TestPassword123!',
  },
  // smokeWorkoutDiscardRace: lapsed user for the discard-cancel race E2E
  // (PR-1 reviewer-cycle Fix B — post-PR-1 coverage gap closed in PR-2).
  // Mirrors the smokeWorkoutCancelStart pattern but on the discard path.
  // Isolated so a stall on DELETE /workouts can't bleed into the
  // save-workout-stall test running concurrently on another worker.
  smokeWorkoutDiscardRace: {
    email: 'e2e-smoke-workout-discard-race@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // PR-3 audit fixes — destructive-gesture cleanup + Q3 confirm + H5 undo + S1
  // -------------------------------------------------------------------------
  // smokeWorkoutDestructiveGestures: lapsed user for the long-press cleanup,
  // Q3 swap confirm, and H5 add-exercise undo flows. Isolated so the H5 add-
  // then-undo test can't race the Q3 swap-with-completed-sets test under
  // workers > 1 (both rely on the picker bottom-sheet sequence).
  smokeWorkoutDestructiveGestures: {
    email: 'e2e-smoke-workout-destructive-gestures@test.local',
    password: 'TestPassword123!',
  },
  // smokeWorkoutDiscardReentry: dedicated user for the S1 re-entrance test
  // — stalls DELETE /workouts mid-discard via page.route() so the re-entrance
  // window can be probed BEFORE the network resolves. Isolated from
  // smokeWorkoutDiscardRace because both tests stall the same endpoint and
  // a shared user would race on workout state when running on different
  // workers.
  smokeWorkoutDiscardReentry: {
    email: 'e2e-smoke-workout-discard-reentry@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // PR-4 audit fixes — set defaults + cascading undo
  // -------------------------------------------------------------------------
  // smokeWorkoutPr4CascadingUndo: dedicated user for the cascading-undo
  // restore-order E2E (M3). Drives swipe-delete x2 + undo x2 sequence that
  // depends on the snackbar timing window. Lapsed state so startEmptyWorkout
  // finds "Quick workout" CTA. Isolated from other workout-swipe users so
  // the M3 test can't race the PR-2 swipe/undo tests under workers > 1
  // (both use the same swipe + snackbar machinery).
  smokeWorkoutPr4CascadingUndo: {
    email: 'e2e-smoke-workout-pr4-cascading-undo@test.local',
    password: 'TestPassword123!',
  },

  // ---------------------------------------------------------------------------
  // smokeWorkoutPr6RowFlicker: dedicated user for the PR-6 / M6 E2E that pins
  // the `activeWorkoutRowDisplaysProvider` loading-state contract. The test
  // stalls GETs to `/rest/v1/personal_records` whose query string carries
  // `exercise_id=in.` (i.e., per-exercise queries fired from the row provider
  // — the bootstrap query targets `?user_id=eq.` and is left to flow). Fresh
  // state is required so the post-stall reclassification is unambiguous (no
  // historical PR records → first completed working set becomes
  // `set-row-state-standing-pr` once data lands). Isolated from the
  // PR-1/PR-2/PR-3 stall-route users so two route handlers can never collide
  // on the same backing user under workers > 1.
  // ---------------------------------------------------------------------------
  smokeWorkoutPr6RowFlicker: {
    email: 'e2e-smoke-workout-pr6-row-flicker@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 23 — rest-overlay chrome + addExercise auto-seed
  // -------------------------------------------------------------------------
  // smokeRestChrome: lapsed user for the Phase 23 D1 chrome-visibility test.
  // The test starts a workout, completes a set to trigger the rest timer,
  // then asserts the FAB + finish bar are hidden and the rest scrim covers
  // the body. Isolated from smokeWorkoutSwipeUndo so rest-overlay tests
  // can run in parallel without colliding on the rest-timer state.
  smokeRestChrome: {
    email: 'e2e-smoke-rest-chrome@test.local',
    password: 'TestPassword123!',
  },
  // smokeAutoSeed: lapsed user with one prior workout containing bench press
  // logged at a known weight. The Phase 23 D6 test starts a fresh workout,
  // mid-workout adds bench press, and asserts the new exercise card opens
  // with one set pre-filled at the prior weight/reps. Isolated user keeps
  // the seed data deterministic across worker counts.
  smokeAutoSeed: {
    email: 'e2e-smoke-auto-seed@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 24c-8 — bodyweight prompt E2E (specs/bodyweight-prompt.spec.ts)
  // -------------------------------------------------------------------------
  // smokeBodyweightPrompt: lapsed user (one prior workout for "Quick workout"
  // CTA) with profile.bodyweight_kg = NULL and NO pre-existing dismissal flag.
  // The test starts a workout, adds Pull-Up (uses_bodyweight_load=TRUE),
  // completes the first set, asserts the prompt SnackBar appears, taps Set
  // now, enters 70 in the bottom sheet, saves, and finally asserts via REST
  // that profile.bodyweight_kg = 70 AND that subsequent xp_events for
  // bodyweight exercises carry effective_load = 70.
  //
  // Isolated from every other smokeWorkout user so the bodyweight column
  // stays NULL across runs (other tests don't touch it but isolation is
  // cheap and defensive).
  smokeBodyweightPrompt: {
    email: 'e2e-smoke-bodyweight-prompt@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // 23-P-4 — E2E dismissal-time assertions for the routine-removed undo snack
  // -------------------------------------------------------------------------
  // smokeWeeklyPlanRoutineRemoveUndo: dedicated user for the routine-removed
  // undo SnackBar auto-dismiss test (23-P-4). Isolated from smokeWeeklyPlan so
  // the dismissal-time test (which adds then swipe-removes a routine and waits
  // for the snack to time out) can't race the smokeWeeklyPlan tests that also
  // manipulate the weekly plan under workers > 1.
  smokeWeeklyPlanRoutineRemoveUndo: {
    email: 'e2e-smoke-weekly-plan-remove-undo@test.local',
    password: 'TestPassword123!',
  },

  // -------------------------------------------------------------------------
  // Phase 33 PR 33d — finding-043 exercise retirement E2E coverage
  // -------------------------------------------------------------------------
  // smokeExerciseRetirement: dedicated user for the "delete user-created
  // exercise → hidden from workout picker" test. Seeded with one user-created
  // exercise (is_default = false) in global-setup. The test soft-deletes the
  // exercise via the detail screen and asserts it no longer appears in the
  // exercise picker during an active workout.
  //
  // Isolated from smokeExercise so the delete does not affect the library
  // smoke tests which assert on the full default exercise list.
  smokeExerciseRetirement: {
    email: 'e2e-smoke-exercise-retirement@test.local',
    password: 'TestPassword123!',
  },
} as const;
