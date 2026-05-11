/**
 * Centralized selectors for RepSaga Flutter web.
 *
 * Flutter 3.41.6+ uses the Accessibility Object Model (AOM) for accessible
 * names instead of setting `aria-label` as a DOM attribute on flt-semantics
 * elements. This means CSS selectors like `flt-semantics[aria-label="X"]`
 * return 0 matches. Instead, use Playwright role-based selectors like
 * `role=button[name="X"]` which query the browser accessibility tree.
 *
 * Exceptions (still use DOM attributes):
 *   - Native <input> elements retain `aria-label` (e.g., AUTH.emailInput)
 *   - `aria-live` attributes are still set as DOM attributes
 *   - `role` is still set as a DOM attribute on flt-semantics elements
 *
 * Semantics labels found in the source (use role= selectors to match):
 *   - _MuscleGroupButton:  'role=button[name="<name> muscle group filter"]'
 *   - _SearchBar:          'role=textbox[name="Search exercises"]'
 *   - _EquipmentFilter:    'role=checkbox[name="<name>"]'
 *   - _ExerciseCard:       'role=button[name="Exercise: <name>"]'
 *   - _CreateExerciseFab:  'role=button[name="Create new exercise"]'
 *   - _TappableImage:      'role=img[name="<name> start position"]' / "end position"
 *   - Delete button:       'role=button[name="Delete exercise"]'
 */

// ---------------------------------------------------------------------------
// Auth — LoginScreen
// LoginScreen uses AppTextField with label props "Email" and "Password" and
// AppButton with label "LOG IN" / "SIGN UP". No Semantics wrappers added yet,
// so we target visible text / placeholder text.
// ---------------------------------------------------------------------------
export const AUTH = {
  /** AppTextField with label "Email" — Semantics(identifier: 'auth-email-input') */
  emailInput: '[flt-semantics-identifier="auth-email-input"]',
  /** AppTextField with label "Password" — Semantics(identifier: 'auth-password-input') */
  passwordInput: '[flt-semantics-identifier="auth-password-input"]',
  /** GradientButton label "LOG IN" — Semantics(identifier: 'auth-login-btn') */
  loginButton: '[flt-semantics-identifier="auth-login-btn"]',
  /** GradientButton label "SIGN UP" — Semantics(identifier: 'auth-signup-btn') */
  signUpButton: '[flt-semantics-identifier="auth-signup-btn"]',
  /** TextButton "Don't have an account? Sign up" — Semantics(identifier: 'auth-toggle-signup') */
  toggleToSignUp: '[flt-semantics-identifier="auth-toggle-signup"]',
  /** TextButton "Already have an account? Log in" — Semantics(identifier: 'auth-toggle-login') */
  toggleToLogIn: '[flt-semantics-identifier="auth-toggle-login"]',
  /** OutlinedButton.icon "Continue with Google" — Semantics(identifier: 'auth-google-btn') */
  googleButton: '[flt-semantics-identifier="auth-google-btn"]',
  /** TextButton "Forgot password?" — Semantics(identifier: 'auth-forgot-pwd') */
  forgotPasswordButton: '[flt-semantics-identifier="auth-forgot-pwd"]',
  /** "Send Reset Email" button in dialog — Semantics(identifier: 'auth-send-reset') */
  sendResetEmailButton: '[flt-semantics-identifier="auth-send-reset"]',
  /** The "RepSaga" headline present on the login screen */
  appTitle: 'text=RepSaga',
  /** "Welcome back" subtitle (sign-in mode) — Semantics(identifier: 'auth-welcome-back') */
  welcomeBack: '[flt-semantics-identifier="auth-welcome-back"]',
  /** Inline error message — Semantics(liveRegion: true) sets aria-live */
  errorMessage: '[aria-live="polite"]',
} as const;

// ---------------------------------------------------------------------------
// Onboarding — OnboardingScreen (2-page flow after first sign-up, Step 5e)
//
// Step 5e trimmed onboarding from 3 pages to 2:
//   Page 1: Welcome ("Track every rep, every time") → GET STARTED
//   Page 2: Profile setup (display name + fitness level) → LET'S GO
//
// The old NEXT button and workout-choice page (page 3) were removed.
// ---------------------------------------------------------------------------
export const ONBOARDING = {
  /** Page 1 CTA — takes user to profile setup — Semantics(identifier: 'onboarding-get-started') */
  getStartedButton: '[flt-semantics-identifier="onboarding-get-started"]',
  /**
   * NEXT button — was used on page 2 of the old 3-page flow.
   * After Step 5e this button no longer exists. The selector is kept here
   * so tests can assert `not.toBeVisible()` on it.
   */
  nextButton: 'text=NEXT',
  /** Display name input on page 2 — Semantics(identifier: 'onboarding-display-name') */
  displayNameInput: '[flt-semantics-identifier="onboarding-display-name"]',
  /** Page 2 final CTA — Semantics(identifier: 'onboarding-lets-go') */
  letsGoButton: '[flt-semantics-identifier="onboarding-lets-go"]',
} as const;

// ---------------------------------------------------------------------------
// Shell / Bottom Navigation
// NavigationDestination labels are exposed as accessible names via AOM.
// Use role=tab selectors to match them in the accessibility tree.
// Tabs: Home, Exercises, Routines, Profile.
// ---------------------------------------------------------------------------
export const NAV = {
  homeTab: '[flt-semantics-identifier="nav-home"]',
  exercisesTab: '[flt-semantics-identifier="nav-exercises"]',
  routinesTab: '[flt-semantics-identifier="nav-routines"]',
  profileTab: '[flt-semantics-identifier="nav-profile"]',
} as const;

// ---------------------------------------------------------------------------
// Exercise list — ExerciseListScreen
// ---------------------------------------------------------------------------
export const EXERCISE_LIST = {
  /** Page heading "Exercises" — Semantics(identifier: 'exercise-list-heading') */
  heading: '[flt-semantics-identifier="exercise-list-heading"]',
  /** Search field — Semantics(identifier: 'exercise-list-search') */
  searchInput: '[flt-semantics-identifier="exercise-list-search"]',
  /** "All" muscle group filter — Semantics(identifier: 'exercise-filter-all') */
  allMuscleGroupFilter: '[flt-semantics-identifier="exercise-filter-all"]',
  /**
   * Muscle group filter buttons — Semantics(identifier: 'exercise-filter-{name}').
   * The name is the lowercase display name with spaces replaced by hyphens.
   */
  muscleGroupFilter: (name: string) =>
    `[flt-semantics-identifier="exercise-filter-${name.toLowerCase().replace(/ /g, '-')}"]`,
  /**
   * Equipment FilterChip — Semantics(identifier: 'exercise-equip-{enumName}').
   * The name is the enum name (e.g. "barbell", "dumbbell", "cable", "machine", "bodyweight").
   */
  equipmentFilter: (enumName: string) =>
    `[flt-semantics-identifier="exercise-equip-${enumName.toLowerCase()}"]`,
  /** Individual exercise card — role selector for computed accessible name */
  exerciseCard: (name: string) => `role=button[name*="Exercise: ${name}"]`,
  /** FAB — Semantics(identifier: 'exercise-list-create-fab') */
  createFab: '[flt-semantics-identifier="exercise-list-create-fab"]',
  /** Empty state when no filters applied — Semantics(identifier: 'exercise-list-empty-no-filter') */
  emptyStateNoFilter: '[flt-semantics-identifier="exercise-list-empty-no-filter"]',
  /** Empty state when filters yield no results — Semantics(identifier: 'exercise-list-empty-filtered') */
  emptyStateFiltered: '[flt-semantics-identifier="exercise-list-empty-filtered"]',
  /** Clear Filters button — Semantics(identifier: 'exercise-list-clear-filters') */
  clearFiltersButton: '[flt-semantics-identifier="exercise-list-clear-filters"]',
} as const;

// ---------------------------------------------------------------------------
// Exercise detail — ExerciseDetailScreen
// ---------------------------------------------------------------------------
export const EXERCISE_DETAIL = {
  /** AppBar title "Exercise Details" — Semantics(identifier: 'exercise-detail-title') */
  appBarTitle: '[flt-semantics-identifier="exercise-detail-title"]',
  /** "Custom exercise" badge — Semantics(identifier: 'exercise-detail-custom-badge') */
  customBadge: '[flt-semantics-identifier="exercise-detail-custom-badge"]',
  /** Delete button — Semantics(identifier: 'exercise-detail-delete-btn') */
  deleteButton: '[flt-semantics-identifier="exercise-detail-delete-btn"]',
  /** Confirmation dialog content — Semantics(identifier: 'exercise-detail-delete-dialog') */
  deleteDialogContent: '[flt-semantics-identifier="exercise-detail-delete-dialog"]',
  /** Confirm delete action in dialog — Semantics(identifier: 'exercise-detail-delete-confirm') */
  deleteConfirmButton: '[flt-semantics-identifier="exercise-detail-delete-confirm"]',
  /** Cancel delete action in dialog — Semantics(identifier: 'exercise-detail-delete-cancel') */
  deleteCancelButton: '[flt-semantics-identifier="exercise-detail-delete-cancel"]',
  /** Coming-soon placeholder text */
  prPlaceholder: 'text=Personal records & workout history coming soon',
  /**
   * Start-position image for a named exercise in _ExerciseImageRow.
   * _TappableImage wraps the image in Semantics(label: '${name} start position', image: true).
   * Flutter 3.41.6+ exposes this as role=img with the computed accessible name.
   */
  startImage: (name: string) => `role=img[name*="${name} start position"]`,
  /**
   * End-position image for a named exercise in _ExerciseImageRow.
   * _TappableImage wraps the image in Semantics(label: '${name} end position', image: true).
   */
  endImage: (name: string) => `role=img[name*="${name} end position"]`,
  /**
   * "FORM TIPS" section heading on the exercise detail screen (en locale).
   * The ExerciseFormTipsSection widget renders the formTipsSection l10n string
   * as plain Text. This selector is safe to use after EXERCISE_DETAIL.appBarTitle
   * and EXERCISE_DETAIL.customBadge are confirmed visible (detail screen rendered).
   * For pt locale use EXERCISE_LOC.formTipsSectionText('pt') ('DICAS DE FORMA').
   */
  formTipsSection: 'text=FORM TIPS',
  /**
   * BL-3: "Progress (kg)" section heading was removed. The unit now lives on
   * the Y-axis; the trend summary line is the first text row.
   *
   * Note: BL-3 removed the `Semantics(image: true)` wrapper from the LineChart
   * canvas. The old `role=img[name*="Progress chart"]` selector no longer matches.
   *
   * The `progressChartCard` and `progressChartEmptyContainer` selectors were
   * removed during BL-3 review: they used `[data-flutter-semantics-key="..."]`
   * which Flutter does not emit on the DOM (Key doesn't surface in the AX tree
   * that way). No spec exercised them, so removing is safe. Re-add via a
   * proper `Semantics(identifier: ...)` wrapper if an E2E needs to target the
   * card or empty container in the future.
   */
  /**
   * The 30d window segment button — always visible when ProgressChartSection
   * has data. Text label: "30d".
   */
  progressChart30dButton: 'text=30d',
  /**
   * New empty-state copy (BL-3 acceptance #12).
   * Rendered when workoutCount == 0 and no points exist.
   */
  progressChartEmptyCopy: '[flt-semantics-identifier="exercise-detail-chart-empty"]',
} as const;

// ---------------------------------------------------------------------------
// Create exercise — CreateExerciseScreen
// AppTextField label is "Exercise Name", button label is "CREATE EXERCISE"
// ---------------------------------------------------------------------------
export const CREATE_EXERCISE = {
  /** Name text field — Semantics(identifier: 'create-exercise-name') */
  nameInput: '[flt-semantics-identifier="create-exercise-name"]',
  /** CREATE EXERCISE button — Semantics(identifier: 'create-exercise-save') */
  saveButton: '[flt-semantics-identifier="create-exercise-save"]',
} as const;

// ---------------------------------------------------------------------------
// Active workout — ActiveWorkoutScreen
// ---------------------------------------------------------------------------
export const WORKOUT = {
  /** "Start Empty Workout" button on the Home screen launchpad — deprecated, use HOME.quickWorkout */
  startEmpty: 'text=Start Empty Workout',
  /** "Finish Workout" button — Semantics(identifier: 'workout-finish-btn') */
  finishButton: '[flt-semantics-identifier="workout-finish-btn"]',
  /** "Save & Finish" button in dialog — Semantics(identifier: 'workout-dialog-finish') */
  dialogFinishButton: '[flt-semantics-identifier="workout-dialog-finish"]',
  // Identifier appears on both the empty-state FilledButton and the FAB
  // (shown when exercises exist). The two widgets are mutually exclusive.
  addExerciseFab: '[flt-semantics-identifier="workout-add-exercise"]',
  /** "Add Set" button — Semantics(identifier: 'workout-add-set') */
  addSetButton: '[flt-semantics-identifier="workout-add-set"]',
  /** Checkbox to mark set as done — Semantics(identifier: 'workout-set-done') */
  markSetDone: '[flt-semantics-identifier="workout-set-done"]',
  /** Checkbox set completed — Semantics(identifier: 'workout-set-completed') */
  setCompleted: '[flt-semantics-identifier="workout-set-completed"]',
  /** Discard workout icon button — Semantics(identifier: 'workout-discard-btn') */
  discardButton: '[flt-semantics-identifier="workout-discard-btn"]',
  /** "Discard" confirm in dialog — Semantics(identifier: 'workout-discard-confirm') */
  discardConfirmButton: '[flt-semantics-identifier="workout-discard-confirm"]',
  /** "Keep Going" button — Semantics(identifier: 'workout-keep-going') */
  keepGoingButton: '[flt-semantics-identifier="workout-keep-going"]',
  /** Tappable weight value that opens the weight entry dialog */
  enterWeightDialog: 'text=Enter weight',
  /** Tappable reps value that opens the reps entry dialog */
  enterRepsDialog: 'text=Enter reps',
  /** Workout notes input — Semantics(identifier: 'workout-notes') */
  notesInput: '[flt-semantics-identifier="workout-notes"]',
  /**
   * Cancel button inside ActiveWorkoutLoadingOverlay (PR1 — Q1).
   * The button is a TextButton with the l10n "Cancel" label, visible at t=0
   * in every phase (start/finish/discard). No flt-semantics-identifier is
   * added — match by accessible role+name instead, which is locale-sensitive.
   * The label is "Cancel" in en and "Cancelar" in pt-BR; use the English
   * variant for all E2E tests running in the default en locale.
   */
  loadingOverlayCancelButton: 'role=button[name="Cancel"]',
  /**
   * Exercise name tappable area inside an exercise card during an active workout.
   *
   * _ExerciseCard wraps the exercise name in a Semantics with the label:
   *   "Exercise: <name>. Tap for details. Long press to swap."
   * Flutter 3.41.6+ renders this as role=group (not role=button) because the
   * parent Semantics node merges children into a group container.
   * We match on the "Tap for details" substring to target the tappable region
   * regardless of exercise name.
   */
  exerciseDetailTap: (name: string) =>
    `role=group[name*="Exercise: ${name}. Tap for details"]`,
  /**
   * Reorder-mode toggle in the active-workout AppBar. Visible only when the
   * workout has 2+ exercises. Tapping toggles between Icons.swap_vert (idle)
   * and Icons.done (in-mode) — the identifier itself is stable across both
   * states so a single selector covers enter and exit. Family 3 fix
   * (AW-EX-C-BR1-01) — wrapped in
   * `Semantics(container: true, explicitChildNodes: true,
   * identifier: 'workout-reorder-toggle')`.
   */
  reorderToggle: '[flt-semantics-identifier="workout-reorder-toggle"]',
  /**
   * Swap-exercise IconButton inside `_ExerciseCard` (visible when the card
   * is NOT in reorder mode). Family 3 fix (AW-EX-C-BR1-02) — wrapped in
   * `Semantics(container: true, explicitChildNodes: true,
   * identifier: 'workout-swap-exercise')`.
   */
  swapExercise: '[flt-semantics-identifier="workout-swap-exercise"]',
  /**
   * Remove-exercise IconButton inside `_ExerciseCard` (visible when the
   * card is NOT in reorder mode). Family 3 fix (AW-EX-C-BR1-02) — wrapped
   * in `Semantics(container: true, explicitChildNodes: true,
   * identifier: 'workout-remove-exercise')`.
   */
  removeExercise: '[flt-semantics-identifier="workout-remove-exercise"]',
  /**
   * PR-2 C3/Q5 — swipe-to-delete undo SnackBar.
   *
   * Swipe-deleting a set fires a 10s SnackBar with content "Set N deleted"
   * and a SnackBarAction labelled "Undo" (en) / "Desfazer" (pt). The
   * structural change in PR-2 (overlays moved INTO the Scaffold body slot)
   * makes this SnackBar visible AND tap-reachable when the rest-timer
   * overlay is up — pre-fix, the rest-timer scrim hid the SnackBar both
   * visually and from hit-testing.
   *
   * Use the regex below (`/Set \d+ deleted/`) so the selector matches any
   * set-number. Flutter CanvasKit draws the SnackBar's Text widget to
   * canvas, so a `text=` selector misses (no DOM text node). The
   * SnackBar's content surfaces in the AOM as a `role=group` whose
   * accessible name is the localized text — matching by role+name is the
   * stable selector. Use `.first()` because Flutter renders two AOM
   * boundaries per SnackBar (per the CLAUDE.md E2E Conventions note).
   */
  swipeToDeleteSnackBar: 'role=group[name=/Set \\d+ deleted/]',
  /**
   * PR-2 C3/Q5 — Undo action button inside the swipe-to-delete SnackBar.
   * `SnackBarAction` renders as a TextButton inside the SnackBar — Flutter
   * exposes it as role=button via the AOM. Locale-sensitive: the label is
   * "Undo" in en (default for E2E) and "Desfazer" in pt.
   *
   * Pinning the button as the reachability target proves the rest-timer
   * overlay's full-screen GestureDetector no longer eats taps in the
   * SnackBar region — pre-PR-2 the tap landed on the scrim and dismissed
   * the timer instead of triggering the undo action.
   */
  swipeToDeleteUndoButton: 'role=button[name="Undo"]',
  /**
   * Fix 2 — "Copy from previous set" tooltip on the set-number cell of set 2+.
   * The copy icon (Icons.content_copy at 12dp, α=0.4) is visible ONLY when the
   * current set's weight differs from the previous in-session set. The tap
   * target is the parent InkWell (_SetNumberCell), not the icon itself —
   * tap the set-number cell to trigger the copy.
   *
   * No flt-semantics-identifier is emitted for the icon itself (it's render-only);
   * use role=button selectors on the set-number cell or query by tooltip text.
   * This entry documents the feature for future selector additions if needed.
   */
  copyFromPreviousSetIcon: 'role=img[name="content_copy"]',
  /**
   * PR-3 Q3 — confirm dialog shown when the user attempts to swap an
   * exercise that already has one or more completed sets. The dialog's
   * title is wrapped in `Semantics(container: true, explicitChildNodes:
   * true, identifier: 'workout-swap-confirm-dialog')` so we can target it
   * deterministically across locales.
   */
  swapExerciseConfirmDialog:
    '[flt-semantics-identifier="workout-swap-confirm-dialog"]',
  /**
   * PR-3 Q3 — Cancel action inside the swap-confirm dialog. Wrapped in
   * `Semantics(identifier: 'workout-swap-confirm-cancel')`.
   */
  swapExerciseConfirmCancelButton:
    '[flt-semantics-identifier="workout-swap-confirm-cancel"]',
  /**
   * PR-3 Q3 — Swap (confirm) action inside the swap-confirm dialog.
   * Wrapped in `Semantics(identifier: 'workout-swap-confirm-swap')`.
   */
  swapExerciseConfirmSwapButton:
    '[flt-semantics-identifier="workout-swap-confirm-swap"]',
  /**
   * PR-3 H5 — undo SnackBar fired after adding an exercise from the
   * picker. The content text reads `"<Exercise> added"` (en) or
   * `"<Exercise> adicionado"` (pt). Match by accessible name as a regex
   * because Flutter CanvasKit draws the SnackBar text to canvas (no DOM
   * text node) and the AOM exposes it as a `role=group`. Use `.first()`
   * — Flutter renders two AOM boundaries per SnackBar.
   *
   * EN-ONLY ASSUMPTION (PR3 review W2): the `<name> added$` regex matches
   * only the EN structural copy. The PT translation is structurally
   * different — `Exercício adicionado: <name>` (prefix-then-name) vs EN's
   * suffix-then-verb — and would NOT match this selector. The full
   * E2E suite runs under the en locale by default (see global-setup), so
   * this is a deliberate scoping. If/when the suite gains a pt-locale
   * variant, add a sibling `addExerciseUndoSnackBarPt` matching
   * `/^Exercício adicionado:.+/` and gate the assertion on the active
   * locale.
   */
  addExerciseUndoSnackBar: 'role=group[name=/.+ added$/]',
  /**
   * PR-3 H5 — Undo action button inside the add-exercise SnackBar.
   * Locale-sensitive: "Undo" in en (default for E2E) — same key as
   * `swipeToDeleteUndoButton` (`undo` ARB) so the selector matches both
   * use cases. When two snackbars are stacked, prefer the role-name
   * selector + .first() to grab the most-recent.
   */
  addExerciseUndoButton: 'role=button[name="Undo"]',
} as const;

// ---------------------------------------------------------------------------
// Exercise picker — bottom sheet shown when adding exercises to a workout
// ---------------------------------------------------------------------------
export const EXERCISE_PICKER = {
  /** Search field — Semantics(identifier: 'exercise-picker-search') */
  searchInput: '[flt-semantics-identifier="exercise-picker-search"]',
  /** "Add <name>" tile — role selector for computed accessible name */
  addExerciseButton: (name: string) =>
    `role=button[name*="Add ${name}"]`,
} as const;

// ---------------------------------------------------------------------------
// Home screen — W8 IA refresh
//
// The stat-cell grid (_ContextualStatCells) was deleted in W8. All selectors
// for `HOME_STATS.lastSessionCell` and `HOME_STATS.weekVolumeCell` are
// removed here; any test that previously relied on those cells must use the
// new `HOME.lastSessionLine` selector instead.
// ---------------------------------------------------------------------------
export const HOME = {
  /**
   * Active workout banner in the shell bottom bar — shown when an active
   * workout is in progress on any tab. _ActiveWorkoutBanner (app_router.dart)
   * wraps the banner in Semantics(button: true, label: 'Active workout: <name>').
   * The prefix "Active workout:" is stable regardless of whether the workout
   * was started from a routine (name = routine name) or manually (name =
   * "Workout \u2014 <date>").
   */
  activeBanner: '[flt-semantics-identifier="home-active-banner"]',
  /**
   * HomeStatusLine — the single-line state-aware status at the top of Home.
   * Semantics(identifier: 'home-status-line') wraps every return branch.
   */
  statusLine: '[flt-semantics-identifier="home-status-line"]',
  /**
   * Brand-new state: HomeStatusLine shows the user's display name only.
   * Used to confirm the brand-new home state without relying on workout data.
   * Check for 'Gym User' which is the display_name seeded for most E2E users.
   */
  statusDisplayName: (name: string) => `text=${name}`,
  /**
   * ActionHero label — the small uppercase label inside the hero banner.
   * One of: "UP NEXT", "YOUR FIRST WORKOUT", "NEW WEEK".
   * labelSmall with letterSpacing and FontWeight.w700.
   */
  actionHeroLabel: (label: string) => `text=${label}`,
  /**
   * ActionHero headline — the routine name (active / beginner) or
   * "Start new week" (week-complete). titleLarge bold.
   */
  actionHeroHeadline: (headline: string) => `text=${headline}`,
  /**
   * LastSessionLine — editorial "Last: {routineName}, {relativeDate}" tap
   * target navigating to /home/history.
   * Flutter's Semantics widget sets label="Last session: {name}, {date}" on the
   * InkWell. The AOM exposes this as a button with accessible name starting with
   * "Last session:". Use the role+name selector for reliable matching.
   */
  lastSessionLine: '[flt-semantics-identifier="home-last-session"]',
  /**
   * "See all" TextButton in _HomeRoutinesList — routes to /routines.
   * Only visible when the user has more than 3 user routines and no active plan.
   */
  myRoutinesSeeAll: '[flt-semantics-identifier="home-see-all-routines"]',
  /**
   * "Plan your week" _HeroBanner in the lapsed-state ActionHero.
   * Semantics(identifier: 'home-plan-your-week') wraps the banner.
   * Navigates to /plan/week.
   */
  planYourWeek: '[flt-semantics-identifier="home-plan-your-week"]',
  /**
   * "Quick workout" OutlinedButton in the lapsed-state ActionHero secondary CTA.
   * Navigates to /workout/active (starts an empty workout).
   */
  quickWorkout: '[flt-semantics-identifier="home-quick-workout"]',
  /**
   * "Start new week" _HeroBanner inside the week-complete ActionHero.
   * Semantics(identifier: 'home-start-new-week') wraps the banner.
   * Tapping navigates to /plan/week.
   */
  startNewWeek: '[flt-semantics-identifier="home-start-new-week"]',
} as const;

// ---------------------------------------------------------------------------
// Set-row state — Phase 20 5-state gold-edge-frame matrix
//
// Each set row in the active workout screen wraps its _SetRowFrame in a
// Semantics(identifier: ...) node that reflects the current PrRowState.
// These selectors let E2E tests discriminate among the five row states
// without relying on color (invisible to the AOM) or locale-dependent labels.
//
// Identifiers are emitted by _SetRowFrame.build in set_row.dart.
// One identifier per row — states are mutually exclusive.
// ---------------------------------------------------------------------------
export const SET_ROW = {
  /** Pending set with no projected PR — 3dp violet stripe, ○ violet done-mark */
  stateNone: '[flt-semantics-identifier="set-row-state-none"]',
  /** Pending set whose current values WOULD produce a PR if completed now — 4dp gold stripe, ◆ gold done-mark */
  statePendingPr: '[flt-semantics-identifier="set-row-state-pending-pr"]',
  /** Completed set that did not produce any new PR — 3dp green stripe */
  stateCompleted: '[flt-semantics-identifier="set-row-state-completed"]',
  /** Completed PR superseded by a later set in the same workout — 3dp green stripe + 2% gold tint, no right bracket */
  stateSupersededPr: '[flt-semantics-identifier="set-row-state-superseded-pr"]',
  /** Completed PR currently the best across all history — 4dp gold stripe + 4% tint + 4dp gold right bracket */
  stateStandingPr: '[flt-semantics-identifier="set-row-state-standing-pr"]',
} as const;

// ---------------------------------------------------------------------------
// Personal Records — celebration screen and records list
// ---------------------------------------------------------------------------
export const PR = {
  /** Heading shown when a new personal record is set — Semantics(identifier: 'pr-new-heading') */
  newPRHeading: '[flt-semantics-identifier="pr-new-heading"]',
  /** Heading shown when the user completes their first workout — Semantics(identifier: 'pr-first-workout') */
  firstWorkoutHeading: '[flt-semantics-identifier="pr-first-workout"]',
  /** "Continue" button on the PR celebration screen — Semantics(identifier: 'pr-continue-btn') */
  continueButton: '[flt-semantics-identifier="pr-continue-btn"]',
  /** "RECENT RECORDS" section on the progress tab — not yet implemented in the UI */
  recentRecordsSection: 'text=RECENT RECORDS',
} as const;

// ---------------------------------------------------------------------------
// Routines list — RoutinesScreen
// ---------------------------------------------------------------------------
export const ROUTINE = {
  /** Page heading — Semantics(identifier: 'routine-heading') on AppBar title */
  heading: '[flt-semantics-identifier="routine-heading"]',
  /** "MY ROUTINES" section header — SectionHeader(semanticsIdentifier: 'routine-my-section') */
  myRoutinesSection: '[flt-semantics-identifier="routine-my-section"]',
  /** "STARTER ROUTINES" section header — SectionHeader(semanticsIdentifier: 'routine-starter-section') */
  starterRoutinesSection: '[flt-semantics-identifier="routine-starter-section"]',
  /** AppBar + IconButton to create a routine — same as ROUTINE_MANAGEMENT.createIconButton */
  createButton: '[flt-semantics-identifier="routine-mgmt-create-btn"]',
  /** Routine card identified by name */
  routineName: (name: string) => `text=${name}`,
  /** Context menu "Edit" option — Semantics(identifier: 'routine-edit-option') */
  editOption: '[flt-semantics-identifier="routine-edit-option"]',
  /** Context menu "Delete" option — Semantics(identifier: 'routine-delete-option') */
  deleteOption: '[flt-semantics-identifier="routine-delete-option"]',
  /** Delete confirmation dialog title — Semantics(identifier: 'routine-delete-dialog-title') */
  deleteDialogTitle: '[flt-semantics-identifier="routine-delete-dialog-title"]',
  /** "Cancel" button in delete dialog — Semantics(identifier: 'routine-cancel-btn') */
  cancelButton: '[flt-semantics-identifier="routine-cancel-btn"]',
  /** "Delete" confirm button in delete dialog — Semantics(identifier: 'routine-delete-confirm') */
  deleteConfirmButton: '[flt-semantics-identifier="routine-delete-confirm"]',
} as const;

// ---------------------------------------------------------------------------
// Create/Edit routine — CreateRoutineScreen
// ---------------------------------------------------------------------------
export const CREATE_ROUTINE = {
  /** Name text field — hintText "Routine name". Target the flt-semantics
   *  text-field element directly via its data attribute to avoid the raw
   *  HTML input proxy that gets intercepted by the semantics overlay. */
  nameInput: 'input[data-semantics-role="text-field"]',
  /** "Add Exercise" button — Semantics(identifier: 'create-routine-add-exercise') */
  addExerciseButton: '[flt-semantics-identifier="create-routine-add-exercise"]',
  /** "Save" button — Semantics(identifier: 'create-routine-save') */
  saveButton: '[flt-semantics-identifier="create-routine-save"]',
  /** Sets label in set configuration row — Semantics(identifier: 'create-routine-sets') */
  setsLabel: '[flt-semantics-identifier="create-routine-sets"]',
  /** Rest label in set configuration row — Semantics(identifier: 'create-routine-rest') */
  restLabel: '[flt-semantics-identifier="create-routine-rest"]',
} as const;

// ---------------------------------------------------------------------------
// Workout history — HistoryScreen
// ---------------------------------------------------------------------------
export const HISTORY = {
  /** Page heading — Semantics(identifier: 'history-heading') on AppBar title */
  heading: '[flt-semantics-identifier="history-heading"]',
  /** Empty state message — Semantics(identifier: 'history-empty') */
  emptyState: '[flt-semantics-identifier="history-empty"]',
  /** CTA in empty state — Semantics(identifier: 'history-empty-cta') */
  emptyStateCta: '[flt-semantics-identifier="history-empty-cta"]',
  /** Retry button shown on error state — Semantics(identifier: 'history-retry') */
  retryButton: '[flt-semantics-identifier="history-retry"]',
} as const;

// ---------------------------------------------------------------------------
// Profile screen — ProfileScreen
// ---------------------------------------------------------------------------
export const PROFILE = {
  /** Page heading — Semantics(identifier: 'profile-heading') */
  heading: '[flt-semantics-identifier="profile-heading"]',
  /** Primary "Log Out" button — Semantics(identifier: 'profile-logout-btn') */
  logOutButton: '[flt-semantics-identifier="profile-logout-btn"]',
  /** Confirmation dialog body text — Semantics(identifier: 'profile-logout-dialog') */
  logOutConfirmDialog: '[flt-semantics-identifier="profile-logout-dialog"]',
  /** Cancel button in the confirmation dialog — Semantics(identifier: 'profile-cancel-btn') */
  cancelButton: '[flt-semantics-identifier="profile-cancel-btn"]',
  /** Weight unit "kg" option — Semantics(identifier: 'profile-kg') */
  kgOption: '[flt-semantics-identifier="profile-kg"]',
  /** Weight unit "lbs" option — Semantics(identifier: 'profile-lbs') */
  lbsOption: '[flt-semantics-identifier="profile-lbs"]',
  /**
   * "Manage Data" row — Semantics(identifier: 'profile-manage-data')
   */
  manageData: '[flt-semantics-identifier="profile-manage-data"]',
  /**
   * "Language" row — Semantics(identifier: 'profile-language-row').
   * Tapping opens the LanguagePickerSheet.
   */
  languageRow: '[flt-semantics-identifier="profile-language-row"]',
  /**
   * Root of the language picker bottom sheet — Semantics(identifier: 'profile-language-picker').
   * Useful to assert the sheet opened or closed.
   */
  languagePickerSheet: '[flt-semantics-identifier="profile-language-picker"]',
  /**
   * Language option tile inside the LanguagePickerSheet.
   * Identifier pattern: 'language-option-{locale}' where locale is 'en' or 'pt'.
   */
  languageOption: (locale: 'en' | 'pt') =>
    `[flt-semantics-identifier="language-option-${locale}"]`,
} as const;

// ---------------------------------------------------------------------------
// Manage Data screen — ManageDataScreen
// ---------------------------------------------------------------------------
export const MANAGE_DATA = {
  /** AppBar title — Semantics(identifier: 'manage-data-heading') */
  heading: '[flt-semantics-identifier="manage-data-heading"]',
  /** "Delete Workout History" list tile — Semantics(identifier: 'manage-data-delete-history') */
  deleteHistory: '[flt-semantics-identifier="manage-data-delete-history"]',
  /** "Reset All Account Data" list tile — Semantics(identifier: 'manage-data-reset-all') */
  resetAll: '[flt-semantics-identifier="manage-data-reset-all"]',
  /** "Delete History" button in first confirmation dialog — Semantics(identifier: 'manage-data-delete-confirm') */
  deleteHistoryConfirmButton: '[flt-semantics-identifier="manage-data-delete-confirm"]',
  /** "Yes, Delete" button in second confirmation dialog — Semantics(identifier: 'manage-data-yes-delete') */
  yesDeleteButton: '[flt-semantics-identifier="manage-data-yes-delete"]',
  /**
   * TextField inside the Reset Account full-screen dialog.
   * Flutter renders a hidden <input> when the TextField is focused; we use the
   * hint text to identify it via role selector.
   */
  resetInput: 'role=textbox[name*="RESET"]',
  /** "Reset Account" GradientButton — Semantics(identifier: 'manage-data-reset-btn') via semanticsIdentifier */
  resetButton: '[flt-semantics-identifier="manage-data-reset-btn"]',
  /** Close / cancel icon button in Reset Account dialog — Semantics(identifier: 'manage-data-reset-cancel') */
  resetCancelButton: '[flt-semantics-identifier="manage-data-reset-cancel"]',
  /** SnackBar after successful history deletion — Semantics(identifier: 'manage-data-history-cleared') */
  historyCleared: '[flt-semantics-identifier="manage-data-history-cleared"]',
  /** SnackBar after successful reset — Semantics(identifier: 'manage-data-account-reset') */
  accountReset: '[flt-semantics-identifier="manage-data-account-reset"]',
} as const;

// ---------------------------------------------------------------------------
// Weekly plan — WeekBucketSection (Home screen) and PlanManagementScreen
// ---------------------------------------------------------------------------
export const WEEKLY_PLAN = {
  /** "THIS WEEK" header in WeekReviewSection — Semantics(identifier: 'weekly-plan-this-week') */
  thisWeekHeader: '[flt-semantics-identifier="weekly-plan-this-week"]',
  /** "WEEK COMPLETE" header in WeekReviewSection — Semantics(identifier: 'weekly-plan-complete') */
  weekCompleteHeader: '[flt-semantics-identifier="weekly-plan-complete"]',
  /**
   * "Plan your week" CTA — same as HOME.planYourWeek.
   * _EmptyBucketState was removed; lapsed hero banner uses Semantics(identifier: 'home-plan-your-week').
   */
  planYourWeekCta: '[flt-semantics-identifier="home-plan-your-week"]',
  /** AppBar title of PlanManagementScreen — Semantics(identifier: 'weekly-plan-title') */
  planManagementTitle: '[flt-semantics-identifier="weekly-plan-title"]',
  /** "Add Routines" FilledButton in empty state — Semantics(identifier: 'weekly-plan-add-routines') */
  addRoutinesButton: '[flt-semantics-identifier="weekly-plan-add-routines"]',
  /** "Add Routine" row in ReorderableListView — Semantics(identifier: 'weekly-plan-add-routine-row') */
  addRoutineRow: '[flt-semantics-identifier="weekly-plan-add-routine-row"]',
  /** "Add Routines" sheet title — Semantics(identifier: 'weekly-plan-add-sheet-title') */
  addRoutinesSheetTitle: '[flt-semantics-identifier="weekly-plan-add-sheet-title"]',
  /** "ADD N ROUTINE(S)" confirm button in sheet — Semantics(identifier: 'weekly-plan-add-confirm') */
  addConfirmButton: '[flt-semantics-identifier="weekly-plan-add-confirm"]',
  /** PopupMenuButton overflow icon — Semantics(identifier: 'weekly-plan-overflow') */
  overflowMenuButton: '[flt-semantics-identifier="weekly-plan-overflow"]',
  /** "Clear Week" PopupMenuItem — Semantics(identifier: 'weekly-plan-clear-week') */
  clearWeekOption: '[flt-semantics-identifier="weekly-plan-clear-week"]',
  /** "Clear" confirm button in dialog — Semantics(identifier: 'weekly-plan-clear-confirm') */
  clearConfirmButton: '[flt-semantics-identifier="weekly-plan-clear-confirm"]',
  /** "Start new week" banner in ActionHero — Semantics(identifier: 'home-start-new-week') */
  newWeekButton: '[flt-semantics-identifier="home-start-new-week"]',
  /**
   * Stats text in WeekReviewSection — contains "sessions" substring.
   * _buildStatsText always starts with "{n} sessions". Dynamic content — keep text= selector.
   */
  sessionsStatsText: 'text=/sessions/',
  /**
   * Fix 1A — "Saved" confirmation SnackBar shown after a successful upsertPlan.
   * The snackbar content is the l10n key `savedConfirmation` ("Saved" / "Salvo").
   * Appears for 1s; use waitForSelector with a short timeout.
   */
  savedSnackbar: 'text=Saved',
  /**
   * Fix 1B — "Create new routine" action row at the bottom of AddRoutinesSheet.
   * Semantics(identifier: 'weekly-plan-create-new-routine') wraps the InkWell.
   * Only visible when the sheet is open and availableRoutines.isNotEmpty.
   * On empty state, the sheet shows the _EmptyStateCreateNew button instead
   * (which shares the same AOM accessible name "Create new routine").
   */
  createNewRoutineRow: '[flt-semantics-identifier="weekly-plan-create-new-routine"]',
} as const;

// ---------------------------------------------------------------------------
// Onboarding — extended selectors for the 2-page flow
// ---------------------------------------------------------------------------
// Note: ONBOARDING already exists above. These are supplemental selectors for
// the onboarding smoke test that target specific page content.
// The base ONBOARDING object is already exported; we extend via ONBOARDING_FLOW.
export const ONBOARDING_FLOW = {
  /**
   * Page 1 welcome headline: "Track every rep,\nevery time".
   * Semantics(identifier: 'onboarding-welcome') wraps the Text.
   */
  welcomeHeadline: '[flt-semantics-identifier="onboarding-welcome"]',
  /**
   * Page 2 indicator: the "Beginner" pill (formerly ChoiceChip, now
   * _BrandedPillChoice). Semantics(identifier: 'onboarding-beginner') wraps
   * the pill — identifier is stable across the widget swap.
   */
  profileSetupHeadline: '[flt-semantics-identifier="onboarding-beginner"]',
  /**
   * Display name AppTextField on page 2.
   * Semantics(identifier: 'onboarding-display-name') wraps the AppTextField.
   */
  displayNameInput: '[flt-semantics-identifier="onboarding-display-name"]',
  /**
   * "3x" frequency pill — the default selection.
   *
   * Why role=button[name="3x"] instead of [flt-semantics-identifier=...]:
   * Flutter 3.41.6's semantics tree compactor non-deterministically strips
   * outer `Semantics(container: true, identifier: ...)` wrappers when their
   * sole child is a tap-target node (InkWell). Live DOM probes against
   * build/web confirm: the fitness-level Wrap (3 pills) keeps the wrapper
   * nodes — so `flt-semantics-identifier="onboarding-beginner"` etc. are
   * emitted — but the structurally-identical frequency Wrap (5 pills) gets
   * its wrappers compacted away, leaving only the inner InkWell node.
   * Per CLAUDE.md "use Playwright `role=TYPE[name*=...]` selectors
   * (accessibility protocol), NOT CSS `flt-semantics[...]`": the role-based
   * selector targets the AOM directly and is unaffected by which
   * intermediate `flt-semantics` nodes the compactor preserves.
   *
   * Why `role=button` and not `role=checkbox`: the AOM dump from the CI
   * failure (run 25242304322) shows the frequency pills emit `role=button`,
   * not `role=checkbox`:
   *   `- button "2x" - button "3x" - button "4x" - button "5x" - button "6x"`
   * `_BrandedPillChoice` is `Material > InkWell > AnimatedContainer > Text`
   * with no `Semantics(checked: ...)` wrapper. Flutter auto-emits `button`
   * semantics for `InkWell` tap-targets — there is no `aria-checked`
   * attribute. An earlier change (d2ab8c0) assumed the pill emitted a
   * `checkbox` role; that assumption was wrong and caused the selector to
   * never resolve in CI. The pill is semantically a single-select choice
   * (tapping one deselects siblings) — `button` is the correct role
   * emission for this pattern.
   */
  frequency3x: 'role=button[name="3x"]',
  /**
   * Back TextButton.icon on page 2.
   * TextButton label: Text('Back').
   */
  backButton: '[flt-semantics-identifier="onboarding-back"]',
} as const;

// ---------------------------------------------------------------------------
// Routine management — additional selectors for create/edit/delete flow
// ---------------------------------------------------------------------------
export const ROUTINE_MANAGEMENT = {
  /** + IconButton in RoutineListScreen AppBar — Semantics(identifier: 'routine-mgmt-create-btn') */
  createIconButton: '[flt-semantics-identifier="routine-mgmt-create-btn"]',
  /** AppBar title when creating — Semantics(identifier: 'routine-mgmt-create-title') */
  createRoutineScreenTitle: '[flt-semantics-identifier="routine-mgmt-create-title"]',
  /** AppBar title when editing — Semantics(identifier: 'routine-mgmt-edit-title') */
  editRoutineScreenTitle: '[flt-semantics-identifier="routine-mgmt-edit-title"]',
} as const;

// ---------------------------------------------------------------------------
// PR display — Personal Records screen selectors
// ---------------------------------------------------------------------------
export const PR_DISPLAY = {
  /** AppBar title — Semantics(identifier: 'pr-display-title') */
  screenTitle: '[flt-semantics-identifier="pr-display-title"]',
  /** Empty state title — Semantics(identifier: 'pr-display-empty-title') */
  emptyStateTitle: '[flt-semantics-identifier="pr-display-empty-title"]',
  /** Empty state body text — Semantics(identifier: 'pr-display-empty') */
  emptyState: '[flt-semantics-identifier="pr-display-empty"]',
  /** "Max Weight" label in _RecordTile — Semantics(identifier: 'pr-display-max-weight') */
  maxWeightLabel: '[flt-semantics-identifier="pr-display-max-weight"]',
  exerciseRecordCard: '[flt-semantics-identifier="pr-exercise-card"]',
  /**
   * Locate a specific PR card by exercise name. The card wraps its content
   * in Semantics(container: true), which merges all child Text widgets into
   * the parent group's accessibility label — so individual `text=...` nodes
   * do NOT exist for the exercise name. Use role=group[name*=...] to match
   * against the merged AOM label, e.g. "Supino Reto com Barra 100 kg × 5".
   */
  exerciseRecordCardByName: (name: string) =>
    `role=group[name*="${name}"]`,
} as const;

// ---------------------------------------------------------------------------
// Profile Weekly Goal — selectors for _WeeklyGoalRow and frequency sheet
// ---------------------------------------------------------------------------
export const PROFILE_WEEKLY_GOAL = {
  /** "Weekly Goal" section label — Semantics(identifier: 'profile-goal-label') */
  sectionLabel: '[flt-semantics-identifier="profile-goal-label"]',
  /**
   * The _WeeklyGoalRow InkWell — matches on the "{n}x per week" text pattern.
   * Dynamic content — keep role= selector.
   */
  frequencyRow: 'role=button[name=/per week/]',
  /**
   * Frequency row with a specific value, e.g. "3x per week".
   * Dynamic content — keep role= selector.
   */
  frequencyRowWithValue: (freq: number) => `role=button[name="${freq}x per week"]`,
  /** Description text in frequency sheet — Semantics(identifier: 'profile-goal-sheet-title') */
  sheetTitle: '[flt-semantics-identifier="profile-goal-sheet-title"]',
  /** Same as sheetTitle — Semantics(identifier: 'profile-goal-sheet-title') */
  sheetDescription: '[flt-semantics-identifier="profile-goal-sheet-title"]',
} as const;

// ---------------------------------------------------------------------------
// Home stat cards — DELETED in W8 Home refresh
//
// _ContextualStatCells and its two stat cells ("Last session", "Week's
// volume") were removed in W8. The `HOME_STATS` export is intentionally
// absent so compile errors surface any test that still references it.
// Tests that previously used HOME_STATS.lastSessionCell should now use
// HOME.lastSessionLine.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Offline sync — OfflineBanner, PendingSyncBadge, SyncFailureCard (Phase 14)
// ---------------------------------------------------------------------------
export const OFFLINE = {
  /** OfflineBanner — Semantics(identifier: 'offline-banner') */
  banner: '[flt-semantics-identifier="offline-banner"]',
  /** PendingSyncBadge — Semantics(identifier: 'offline-pending-badge') */
  pendingSyncBadge: '[flt-semantics-identifier="offline-pending-badge"]',
  /** PendingSyncBadge singular — same identifier, use with singular assertion */
  pendingSyncBadgeSingular: '[flt-semantics-identifier="offline-pending-badge"]',
  /** SyncFailureCard — Semantics(identifier: 'offline-failure-card') */
  failureCardSingular: '[flt-semantics-identifier="offline-failure-card"]',
  /** SyncFailureCard plural — same identifier, card renders both singular/plural */
  failureCardPlural: (_n: number) => '[flt-semantics-identifier="offline-failure-card"]',
  /** Subtitle inside SyncFailureCard — Semantics(identifier: 'offline-failure-subtitle') */
  failureCardSubtitle: '[flt-semantics-identifier="offline-failure-subtitle"]',
  /** Retry TextButton inside SyncFailureCard — Semantics(identifier: 'offline-retry') */
  retryButton: '[flt-semantics-identifier="offline-retry"]',
  /** Dismiss TextButton inside SyncFailureCard — Semantics(identifier: 'offline-dismiss') */
  dismissButton: '[flt-semantics-identifier="offline-dismiss"]',
} as const;

// ---------------------------------------------------------------------------
// First-run beginner routine CTA — _BeginnerRoutineCta in WeekBucketSection (P8).
//
// Rendered when plan is null or empty AND workoutCount == 0 AND a default
// routine exists. Shows "YOUR FIRST WORKOUT" label, routine name headline,
// and a stats line ("N exercises · ~45 min"). Tapping the card starts an
// active workout for the recommended routine.
//
// Flutter merges the Column into a single tappable InkWell, so the card's
// accessible name concatenates child text. Matching on the "YOUR FIRST
// WORKOUT" substring is the most stable selector.
// ---------------------------------------------------------------------------
export const FIRST_WORKOUT_CTA = {
  /** The "YOUR FIRST WORKOUT" label text — Semantics(identifier: 'first-workout-label') */
  label: '[flt-semantics-identifier="first-workout-label"]',
  /** The whole card tap target — Semantics(identifier: 'first-workout-card') */
  card: '[flt-semantics-identifier="first-workout-card"]',
  /** Routine name displayed as the headline — parameterized for flexibility */
  routineName: (name: string) => `text=${name}`,
} as const;

// ---------------------------------------------------------------------------
// Saga — CharacterSheetScreen + sub-screens (Phase 18b)
//
// The Saga (formerly Profile) tab now lands on CharacterSheetScreen at /profile.
// All character-sheet elements use Semantics(identifier: ...) wrappers so
// Playwright can target them via flt-semantics-identifier selectors.
// ---------------------------------------------------------------------------
export const SAGA = {
  /** CharacterSheetScreen body container — Semantics(identifier: 'character-sheet') */
  characterSheet: '[flt-semantics-identifier="character-sheet"]',
  /** RuneHalo widget in header — Semantics(identifier: 'rune-halo') */
  runeHalo: '[flt-semantics-identifier="rune-halo"]',
  /**
   * Character level numeral "Lvl N" — Semantics(identifier: 'character-level').
   * Text is rendered via GoogleFonts on a canvas in canvaskit mode, so
   * `text=` selectors won't match. Use this identifier + textContent() to
   * read the numeric level from the AOM label.
   */
  characterLevel: '[flt-semantics-identifier="character-level"]',
  /** VitalityRadar canvas — Semantics(identifier: 'vitality-radar') */
  vitalityRadar: '[flt-semantics-identifier="vitality-radar"]',
  /** Per-body-part rank row — Semantics(identifier: 'body-part-row-{slug}') */
  bodyPartRow: (slug: 'chest' | 'back' | 'legs' | 'shoulders' | 'arms' | 'core') =>
    `[flt-semantics-identifier="body-part-row-${slug}"]`,
  /** ClassBadge slot — Semantics(identifier: 'class-badge') */
  classBadge: '[flt-semantics-identifier="class-badge"]',
  /** ActiveTitlePill — Semantics(identifier: 'active-title-pill') */
  activeTitlePill: '[flt-semantics-identifier="active-title-pill"]',
  /** DormantCardioRow — Semantics(identifier: 'dormant-cardio-row') */
  dormantCardioRow: '[flt-semantics-identifier="dormant-cardio-row"]',
  /** First-set-awakens onboarding banner — Semantics(identifier: 'first-set-awakens-banner') */
  firstSetAwakensBanner: '[flt-semantics-identifier="first-set-awakens-banner"]',
  /** Codex nav rows — Semantics(identifier: 'codex-nav-{section}') */
  codexNavStats: '[flt-semantics-identifier="codex-nav-stats"]',
  codexNavTitles: '[flt-semantics-identifier="codex-nav-titles"]',
  codexNavHistory: '[flt-semantics-identifier="codex-nav-history"]',
  /**
   * RankStamp circle badge inside a BodyPartRankRow (expanded rows only).
   * Semantics is inherited from the parent body-part-row container. There is no
   * per-stamp identifier. Use `SAGA.bodyPartRow(slug)` to scope assertion to a
   * specific body part, then look for a descendant with rank text if needed.
   * This entry documents the current implementation — direct targeting is not
   * supported until a per-stamp identifier is added.
   *
   * Note: the WIP contract listed `rankStamp` as a selector to add; this is the
   * accurate representation of what the DOM exposes today.
   */
  // rankStamp: not selectable by identifier in this release (no per-stamp Semantics)
  /** Gear-icon settings button in CharacterSheetScreen AppBar — Semantics(identifier: 'saga-settings-btn') */
  gearIcon: '[flt-semantics-identifier="saga-settings-btn"]',
  /** ProfileSettingsScreen root — identified by PROFILE.heading ('profile-heading') */
  profileSettingsScreen: '[flt-semantics-identifier="profile-heading"]',
  /** SagaStubScreen body — Semantics(identifier: 'saga-stub-screen').
   *  Locale-independent (was previously `text=Coming soon.`, which broke
   *  pt-BR because the localized copy is "Em breve.").
   *
   *  Phase 18d.2 retired this for /saga/stats — use `statsDeepDiveScreen`
   *  instead. The selector is kept here for any future stub-screen route
   *  (e.g. /saga/skills if added later).
   */
  sagaStubScreen: '[flt-semantics-identifier="saga-stub-screen"]',
  // -----------------------------------------------------------------------
  // Phase 18d.2 — /saga/stats deep-dive screen
  //
  // The deep-dive replaces SagaStubScreen at /saga/stats. It composes four
  // sub-widgets, each wrapped in its own Semantics(identifier: ...) so E2E
  // can target them independently.
  // -----------------------------------------------------------------------
  /** StatsDeepDiveScreen root — Semantics(identifier: 'saga-stats-screen') */
  statsDeepDiveScreen: '[flt-semantics-identifier="saga-stats-screen"]',
  /** VitalityTable container — Semantics(identifier: 'vitality-table') */
  vitalityTable: '[flt-semantics-identifier="vitality-table"]',
  /**
   * Per-row tap target inside VitalityTable.
   * Each row is wrapped in Semantics(identifier: 'vitality-row-{slug}'),
   * where slug is the BodyPart.dbValue ('chest', 'back', 'legs', etc.).
   */
  vitalityRow: (slug: 'chest' | 'back' | 'legs' | 'shoulders' | 'arms' | 'core') =>
    `[flt-semantics-identifier="vitality-row-${slug}"]`,
  /** VitalityTrendChart container — Semantics(identifier: 'vitality-trend-chart') */
  vitalityTrendChart: '[flt-semantics-identifier="vitality-trend-chart"]',
  /** _VolumePeakTable container — Semantics(identifier: 'volume-peak-table') */
  volumePeakTable: '[flt-semantics-identifier="volume-peak-table"]',
  /** PeakLoadsTable container — Semantics(identifier: 'peak-loads-table') */
  peakLoadsTable: '[flt-semantics-identifier="peak-loads-table"]',
} as const;

// ---------------------------------------------------------------------------
// Phase 18c — Mid-workout overlays + title unlocks
//
// All overlay widgets and the TitlesScreen have Semantics(identifier: ...)
// wrappers added in the QA gate for Phase 18c.
// ---------------------------------------------------------------------------
export const CELEBRATION = {
  /** RankUpOverlay card — Semantics(identifier: 'rank-up-overlay') */
  rankUpOverlay: '[flt-semantics-identifier="rank-up-overlay"]',
  /** LevelUpOverlay root — Semantics(identifier: 'level-up-overlay') */
  levelUpOverlay: '[flt-semantics-identifier="level-up-overlay"]',
  /** TitleUnlockSheet root — Semantics(identifier: 'title-unlock-sheet') */
  titleUnlockSheet: '[flt-semantics-identifier="title-unlock-sheet"]',
  /** FirstAwakeningOverlay root — Semantics(identifier: 'first-awakening-overlay') */
  firstAwakeningOverlay: '[flt-semantics-identifier="first-awakening-overlay"]',
  /** CelebrationOverflowCard root — Semantics(identifier: 'celebration-overflow-card') */
  celebrationOverflowCard: '[flt-semantics-identifier="celebration-overflow-card"]',
  /**
   * BUG-013 (Cluster 3) — RankUpOverflowFlipbook inside the overflow card.
   * Replaces the prior text-only "{N} more rank-ups" line with three cycling
   * muscle sigils + "+{N} ranks" headline. Semantics(identifier:
   * 'rank-up-overflow-flipbook').
   */
  rankUpOverflowFlipbook: '[flt-semantics-identifier="rank-up-overflow-flipbook"]',
  /**
   * BUG-011 (Cluster 3) — ClassChangeOverlay root —
   * Semantics(identifier: 'class-change-overlay'). Fires when a workout
   * finish crosses a class boundary (Initiate→first earned class, or any
   * subsequent class flip). 1600ms choreography; auto-dismissed by the
   * celebration player.
   */
  classChangeOverlay: '[flt-semantics-identifier="class-change-overlay"]',
  /**
   * BUG-011 — subtitle line inside the class-change overlay
   * ("Sua jornada ganhou um nome." / "Your journey has earned a name.").
   */
  classChangeSubtitle: '[flt-semantics-identifier="class-change-subtitle"]',
  /**
   * BUG-011 — class name label inside the class-change overlay
   * (Rajdhani 700 36sp uppercase). Used for content verification.
   */
  classChangeNameLabel: '[flt-semantics-identifier="class-change-name-label"]',
  /**
   * BUG-011 — "antes: {className}" subtitle. Only visible on the
   * Initiate→first transition; suppressed on later class flips.
   */
  classChangePreviousLabel: '[flt-semantics-identifier="class-change-previous-label"]',
  /**
   * BUG-014 (Cluster 3) — structured stat chip on locked cross-build
   * title rows. Identifier pattern: 'cross-build-stat-chip-{slug}' where
   * slug is the CrossBuildTriggerId dbValue (iron_bound, broad_shouldered,
   * even_handed, pillar_walker, saga_forged).
   */
  crossBuildStatChip: (slug: string) =>
    `[flt-semantics-identifier="cross-build-stat-chip-${slug}"]`,
  /**
   * EQUIP TITLE ElevatedButton — targeted by accessible role+name.
   * Using role=button rather than flt-semantics-identifier because the
   * button is a child node inside a Semantics container; the identifier
   * lands on the container (group role) while the actual tap-action is on
   * the ElevatedButton's merged semantics node (button role).
   */
  equipTitleButton: 'role=button[name="EQUIP TITLE"]',
  /** "EQUIPPED" badge inside a TitleRow — Semantics(identifier: 'equipped-title-label') */
  equippedTitleLabel: '[flt-semantics-identifier="equipped-title-label"]',
  /** PR chip inline in set row — Semantics(identifier: 'workout-pr-chip') */
  prChip: '[flt-semantics-identifier="workout-pr-chip"]',
  /**
   * Finish button — now in the persistent bottom bar (_FinishBottomBar).
   * BUG-020 reversed Phase 18c §13: moved back from AppBar trailing to
   * Scaffold.bottomNavigationBar for one-handed reach + discoverability.
   * Semantics(identifier: 'workout-finish-btn') unchanged — selector works
   * without modification. Alias for WORKOUT.finishButton.
   */
  finishButton: '[flt-semantics-identifier="workout-finish-btn"]',
  /**
   * "Add exercise" FAB — Semantics(identifier: 'workout-add-exercise').
   * Alias for WORKOUT.addExerciseFab. Selector unchanged.
   */
  addExerciseFab: '[flt-semantics-identifier="workout-add-exercise"]',
  /** TitlesScreen root — Semantics(identifier: 'titles-screen') */
  titlesScreen: '[flt-semantics-identifier="titles-screen"]',
  /**
   * Individual title row by slug — Semantics(identifier: 'title-row-{slug}').
   * Example: CELEBRATION.titleRow('ground_walker')
   */
  titleRow: (slug: string) => `[flt-semantics-identifier="title-row-${slug}"]`,
  /**
   * Title library entry point on the character sheet — the "Titles" codex nav row.
   * Alias for SAGA.codexNavTitles. Used in title-equip.spec.ts for readability.
   * Semantics(identifier: 'codex-nav-titles').
   */
  titleLibraryButton: '[flt-semantics-identifier="codex-nav-titles"]',
  /**
   * Title library screen root — alias for titlesScreen.
   * Used in title-equip.spec.ts for readability.
   * Semantics(identifier: 'titles-screen').
   */
  titleLibrarySheet: '[flt-semantics-identifier="titles-screen"]',
} as const;

// ---------------------------------------------------------------------------
// Gamification intro — SagaIntroOverlay + LVL badge (Phase 17b)
//
// SagaIntroOverlay wraps each step in Semantics(identifier: 'saga-intro-step-{n}')
// and the buttons in Semantics(identifier: 'saga-intro-next' / 'saga-intro-begin').
// The LVL badge in HomeScreen uses Semantics(identifier: 'lvl-badge').
// ---------------------------------------------------------------------------
export const GAMIFICATION = {
  /** Step 0 content — Semantics(identifier: 'saga-intro-step-0') */
  step0: '[flt-semantics-identifier="saga-intro-step-0"]',
  /** Step 1 content — Semantics(identifier: 'saga-intro-step-1') */
  step1: '[flt-semantics-identifier="saga-intro-step-1"]',
  /** Step 2 content — Semantics(identifier: 'saga-intro-step-2') */
  step2: '[flt-semantics-identifier="saga-intro-step-2"]',
  /** "NEXT" button on steps 0 and 1 — Semantics(identifier: 'saga-intro-next') */
  nextButton: '[flt-semantics-identifier="saga-intro-next"]',
  /** "BEGIN" button on step 2 — Semantics(identifier: 'saga-intro-begin') */
  beginButton: '[flt-semantics-identifier="saga-intro-begin"]',
  /** LVL badge on HomeScreen — Semantics(identifier: 'lvl-badge') */
  lvlBadge: '[flt-semantics-identifier="lvl-badge"]',
} as const;

// ---------------------------------------------------------------------------
// Localization — pt-BR nav tab accessible names (Phase 15e)
//
// Flutter exposes NavigationDestination items as role=tab in the AOM.
// The accessible name of each tab IS the label text (set by the l10n string).
// These selectors are used in localization.spec.ts to verify that locale
// reconciliation has applied pt-BR labels to the bottom navigation.
//
// Contrast with NAV.* which use flt-semantics-identifier (locale-independent)
// for navigation actions. These LOCALIZATION selectors are assertion-only and
// should only be used in locale-specific tests.
// ---------------------------------------------------------------------------
export const LOCALIZATION = {
  /** pt-BR nav tab — "Início" (Home) */
  ptNavHome: 'role=tab[name="Início"]',
  /** pt-BR nav tab — "Exercícios" (Exercises) */
  ptNavExercises: 'role=tab[name="Exercícios"]',
  /** pt-BR nav tab — "Treinos" (Routines) */
  ptNavRoutines: 'role=tab[name="Treinos"]',
  /** pt-BR nav tab — "Saga" (same word in both en and pt-BR; Phase 18b renamed Profile → Saga) */
  ptNavProfile: 'role=tab[name="Saga"]',
} as const;

// ---------------------------------------------------------------------------
// Exercise localization — locale-keyed exercise card selectors (Phase 15f)
//
// Exercise names now come from the exercise_translations table via
// fn_exercises_localized RPC. Use EXERCISE_NAMES from test-exercises.ts to
// build locale-aware selectors.
//
// For locale-sensitive assertions, prefer:
//   EXERCISE_LIST.exerciseCard(EXERCISE_NAMES.barbell_bench_press[locale])
//
// The selectors below are convenience wrappers for the most common exercises
// used in E2E localization tests.
// ---------------------------------------------------------------------------
export const EXERCISE_LOC = {
  /**
   * Exercise card selector for a localized exercise name.
   * Pass the translated name string (resolved from EXERCISE_NAMES) and the
   * locale ('en' | 'pt'). The AOM label prefix is locale-sensitive:
   *   en → "Exercise: {name}"  (app_en.arb exerciseItemSemantics)
   *   pt → "Exercício: {name}" (app_pt.arb exerciseItemSemantics)
   */
  exerciseCard: (translatedName: string, locale: 'en' | 'pt' = 'en') => {
    const prefix = locale === 'pt' ? 'Exercício' : 'Exercise';
    return `role=button[name*="${prefix}: ${translatedName}"]`;
  },
  /**
   * Exercise picker "Add <translatedName>" / "Adicionar <translatedName>" button.
   * Used in workout + routine exercise-picker flows.
   *   en → "Add {name}"        (app_en.arb addExerciseSemantics)
   *   pt → "Adicionar {name}"  (app_pt.arb addExerciseSemantics)
   */
  addExerciseButton: (translatedName: string, locale: 'en' | 'pt' = 'en') => {
    const verb = locale === 'pt' ? 'Adicionar' : 'Add';
    return `role=button[name*="${verb} ${translatedName}"]`;
  },
  /**
   * Active workout exercise group — matches the tap-for-details AOM label.
   * The prefix follows the same locale rule as exerciseCard.
   */
  exerciseDetailTap: (translatedName: string, locale: 'en' | 'pt' = 'en') => {
    const prefix = locale === 'pt' ? 'Exercício' : 'Exercise';
    return `role=group[name*="${prefix}: ${translatedName}"]`;
  },
  /**
   * Exercise detail "ABOUT" / "SOBRE" section header text.
   * Source: app_en.arb aboutSection ("ABOUT"), app_pt.arb aboutSection ("SOBRE").
   */
  aboutSectionText: (locale: 'en' | 'pt' = 'en') =>
    `text=${locale === 'pt' ? 'SOBRE' : 'ABOUT'}`,
  /**
   * Exercise detail "FORM TIPS" / "DICAS DE FORMA" section header text.
   * Source: app_en.arb formTipsSection, app_pt.arb formTipsSection.
   */
  formTipsSectionText: (locale: 'en' | 'pt' = 'en') =>
    `text=${locale === 'pt' ? 'DICAS DE FORMA' : 'FORM TIPS'}`,
} as const;
