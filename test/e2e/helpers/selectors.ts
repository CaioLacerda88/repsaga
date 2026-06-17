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
  /**
   * Option A — "CREATE ACCOUNT" heading shown ONLY in signup mode
   * (replaces the dim subtitle). Semantics(identifier: 'auth-signup-heading').
   */
  signupHeading: '[flt-semantics-identifier="auth-signup-heading"]',
  /**
   * Option A — display-name AppTextField (signup mode only), above email.
   * Semantics(identifier: 'auth-display-name-input').
   */
  displayNameInput: '[flt-semantics-identifier="auth-display-name-input"]',
  /**
   * Option A — non-blocking 3-segment password-strength bar (signup mode
   * only). Semantics(identifier: 'auth-password-strength').
   */
  passwordStrengthBar: '[flt-semantics-identifier="auth-password-strength"]',
  /** Inline error message — Semantics(liveRegion: true) sets aria-live */
  errorMessage: '[aria-live="polite"]',
  /**
   * Legal PR 2 — Age-confirmation checkbox.
   * Semantics(identifier: 'auth-age-confirmation') wraps the CheckboxListTile.
   * Only rendered in sign-up mode; hidden in login mode.
   * Must be ticked before AUTH.signUpButton becomes tappable (onPressed != null).
   */
  ageConfirmationCheckbox: '[flt-semantics-identifier="auth-age-confirmation"]',
  /**
   * Legal PR 2 — Privacy Policy link in the age-gate disclosure row.
   * Semantics(identifier: 'auth-age-link-privacy').
   */
  ageLinkPrivacy: '[flt-semantics-identifier="auth-age-link-privacy"]',
  /**
   * Legal PR 2 — Terms of Service link in the age-gate disclosure row.
   * Semantics(identifier: 'auth-age-link-terms').
   */
  ageLinkTerms: '[flt-semantics-identifier="auth-age-link-terms"]',
  /**
   * EmailConfirmationScreen "BACK TO LOGIN" GradientButton — the most stable
   * AOM anchor on the email-confirmation route. The button's `label` is the
   * `backToLogin` l10n key ("BACK TO LOGIN" en / "VOLTAR PARA LOGIN" pt);
   * the E2E suite runs in en. No `flt-semantics-identifier` exists on the
   * EmailConfirmationScreen heading (CanvasKit renders it to canvas), so the
   * role+name selector on the CTA is the test anchor used to assert the
   * post-signup navigation landed on the right route (per cluster
   * `flutter-web-url-assertion` — content-visibility, not toHaveURL).
   */
  emailConfirmationBackToLogin: 'role=button[name="BACK TO LOGIN"]',
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
// Active workout — ActiveWorkoutScreen
// ---------------------------------------------------------------------------
export const WORKOUT = {
  /** "Start Empty Workout" button on the Home screen launchpad — removed in W8 and again in 26f. Kept only so any historical reference still resolves (text= match against a string the app no longer renders). New tests should use HOME.actionHeroFreeWorkout. */
  startEmpty: 'text=Start Empty Workout',
  /** "Finish Workout" button — Semantics(identifier: 'workout-finish-btn') */
  finishButton: '[flt-semantics-identifier="workout-finish-btn"]',
  /**
   * PR-5 H6 — helper text shown beneath the disabled FINISH button.
   *
   * `Semantics(identifier: 'finish-disabled-hint')` wraps a localized line
   * ("Complete at least one set or cardio entry to finish." in en /
   * "Complete pelo menos uma série ou registro de cardio para finalizar."
   * in pt — Phase 38b generalized the copy so it reads correctly for a
   * cardio-only session). Rendered ONLY when the bar is
   * `enabled: false` (no completed sets/cardio / in-flight save /
   * cancellation).
   * Disappears when the button becomes tappable.
   *
   * E2E uses this to assert the disabled-state UX: the user sees a
   * concrete unblock action rather than a silent grey button.
   */
  finishDisabledHint: '[flt-semantics-identifier="finish-disabled-hint"]',
  /** "Save & Finish" button in dialog — Semantics(identifier: 'workout-dialog-finish') */
  dialogFinishButton: '[flt-semantics-identifier="workout-dialog-finish"]',
  // Identifier appears on both the empty-state FilledButton and the FAB
  // (shown when exercises exist). The two widgets are mutually exclusive.
  addExerciseFab: '[flt-semantics-identifier="workout-add-exercise"]',
  /** "Add Set" button — Semantics(identifier: 'workout-add-set') */
  addSetButton: '[flt-semantics-identifier="workout-add-set"]',
  /**
   * "Fill remaining (N sets)" TextButton — Semantics(identifier:
   * 'workout-fill-remaining'). Rendered below the Add Set button ONLY when
   * at least one set is completed AND at least one is still incomplete
   * (Option C — First-Complete Trigger). The label carries the incomplete
   * count, e.g. "Fill remaining (2 sets)" (en). The identifier sits on the
   * Semantics node that wraps the TextButton tap target directly, so a tap
   * routes to the fill-remaining handler.
   */
  fillRemainingButton: '[flt-semantics-identifier="workout-fill-remaining"]',
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
  /**
   * Q1 (notes-edit-after): notes moved off the finish gate onto the History
   * detail screen. These handles address the new editable section + sheet.
   */
  /** Notes section on the workout-detail screen (tap to edit). */
  notesSection: '[flt-semantics-identifier="workout-detail-notes"]',
  /** Multiline notes editor bottom sheet. */
  notesEditSheet: '[flt-semantics-identifier="workout-notes-edit-sheet"]',
  /** Save button inside the notes editor sheet. */
  notesSaveButton: '[flt-semantics-identifier="workout-notes-save"]',
  /** Cancel button inside the notes editor sheet. */
  notesCancelButton: '[flt-semantics-identifier="workout-notes-cancel"]',
  /**
   * Stop button inside ActiveWorkoutLoadingOverlay (PR1 — Q1; relabeled in
   * PR-7 from "Cancel" to "Stop" — UI-critic deferred copy fix).
   *
   * The button is a TextButton with the l10n "Stop" label, visible at t=0
   * in every phase (start/finish/discard). No flt-semantics-identifier is
   * added — match by accessible role+name instead, which is locale-sensitive.
   * The label is "Stop" in en and "Parar" in pt-BR; use the English variant
   * for all E2E tests running in the default en locale.
   *
   * **Why renamed?** Pre-PR-7 the overlay used the generic `cancel` ARB key
   * ("Cancel"). UI critic flagged that "Cancel" during a finish/discard
   * spinner reads as "cancel my workout" — the exact destructive intent
   * the user is trying to AVOID. "Stop" is unambiguous: it stops the
   * in-flight save/discard request and restores prior state.
   */
  loadingOverlayStopButton: 'role=button[name="Stop"]',
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
   * `"<Exercise> adicionado"` (pt) — both share the suffix-verb
   * structure after the Phase 23 UI/UX REV-1 alignment (2026-05-12).
   * Match by accessible name as a regex because Flutter CanvasKit
   * draws the SnackBar text to canvas (no DOM text node) and the AOM
   * exposes it as a `role=group`. Use `.first()` — Flutter renders
   * two AOM boundaries per SnackBar. The selector remains EN-scoped
   * for now (full suite runs under en); a sibling pt selector can be
   * added when a pt-locale run is introduced.
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

  // ---------------------------------------------------------------------------
  // Phase 26f — Home redesign (CharacterCard, BucketChipRow, ActionHero, ...)
  //
  // The W8 status-line + 7-day-bucket layout was replaced by a single-card
  // character surface + chip row. The old text-based ActionHero selectors
  // (label, headline) were replaced by per-branch Semantics identifiers so
  // tests don't depend on localized copy.
  //
  // Dropped (no longer in DOM): statusLine, statusDisplayName, planYourWeek,
  // quickWorkout, startNewWeek, actionHeroLabel, actionHeroHeadline.
  // ---------------------------------------------------------------------------

  /**
   * CharacterCard root — the top tile on Home. Tap toggles expand. The
   * collapsed surface includes the closest-rank-up indicator; the expanded
   * surface mounts XP bar + 6 body-part rows in canonical order.
   * Semantics(container: true, explicitChildNodes: true,
   *   identifier: 'home-character-card').
   */
  characterCard: '[flt-semantics-identifier="home-character-card"]',
  /**
   * Inner expanded body of the CharacterCard — present in DOM only when the
   * card is expanded. Use as a sentinel for "is the card open?" assertions.
   */
  characterCardExpanded:
    '[flt-semantics-identifier="home-character-card-expanded"]',
  /**
   * Closest-rank-up indicator row inside the CharacterCard. Visible only in
   * the COLLAPSED state — the expanded state hides it because the stat rows
   * surface the same info in higher fidelity (locked decision, see
   * `character_card.dart` _CardBody).
   *
   * Day-0 / no-trained-bodypart users see the same identifier wrapping the
   * `homeFirstStepFallback` copy.
   */
  closestRankUp: '[flt-semantics-identifier="home-closest-rank-up"]',
  /**
   * Encouragement nudge — single line above ActionHero. Rotating-priority
   * resolver (cross-build title close / body-part title close / remaining
   * bucket workouts / streak / day-0 first-step fallback). Semantics
   * identifier is stable across all 5 nudge variants.
   */
  encouragementNudge: '[flt-semantics-identifier="home-encouragement-nudge"]',
  /**
   * BucketChipRow root — header + chip wrap (when bucket non-empty) + edit
   * plan link. Always rendered; the chip wrap collapses when the bucket is
   * empty but the header + Editar plano link stay visible (locked decision).
   */
  bucketChipRow: '[flt-semantics-identifier="home-bucket-chip-row"]',
  /**
   * Individual bucket chip — one per planned + spontaneous bucket entry.
   * Identifier carries the routine UUID (not name) so selectors are stable
   * across locale changes and routine renames. Tap opens the routine action
   * sheet.
   */
  bucketChip: (routineId: string) =>
    `[flt-semantics-identifier="home-bucket-chip-${routineId}"]`,
  /**
   * "Editar plano →" link below the bucket chip wrap. Always visible (even
   * when the bucket is empty) — surfaces the plan editor for routines-but-
   * no-plan users. Pushes /plan/week.
   */
  editPlanLink: '[flt-semantics-identifier="home-edit-plan-link"]',
  /**
   * ActionHero outer wrapper — stable across all three branches. Charter
   * specs that just assert "hero exists" can target this; per-branch specs
   * should use one of the variant identifiers below.
   */
  actionHero: '[flt-semantics-identifier="home-action-hero"]',
  /**
   * ActionHero "Start <routineName>" branch — bucket has an uncompleted
   * entry (suggestedNextProvider != null). Tap delegates to
   * startRoutineWorkout(routine).
   */
  actionHeroStartRoutine:
    '[flt-semantics-identifier="home-action-hero-start-routine"]',
  /**
   * ActionHero "Free workout" branch — bucket complete OR no plan exists.
   * Tap starts an empty workout via _startQuickWorkout (with the existing
   * resume-vs-start dialog guard).
   */
  actionHeroFreeWorkout:
    '[flt-semantics-identifier="home-action-hero-free-workout"]',
  /**
   * ActionHero "Create first routine" branch — user has zero routines. Tap
   * pushes /routines/create. Replaces the legacy beginner CTA preselect-
   * default-routine flow.
   */
  actionHeroCreateFirstRoutine:
    '[flt-semantics-identifier="home-action-hero-create-first-routine"]',
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
// Personal Records — records list surface only.
//
// The PR celebration screen + `/pr-celebration` route were retired in PR 30c.
// PR confirmation now lives in the post-session cinematic's B3 PR cut + the
// summary panel detail row — selectors live under `POST_SESSION.*`.
// ---------------------------------------------------------------------------
export const PR = {
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
  /**
   * Sticky week header (52dp surface2 row, shadow on overlapsContent).
   * Renders one per ISO week group at the top of each section. Pinned
   * during scroll. Current ISO week shows "This Week" / "Esta semana"
   * instead of the date format.
   * Semantics(identifier: 'history-week-header')
   */
  weekHeader: '[flt-semantics-identifier="history-week-header"]',
  /**
   * Per-card "+N XP" eyebrow in hotViolet (daily-driver progress register)
   * above the title row. Always present (renders even at 0 XP). One per
   * workout card.
   * Semantics(identifier: 'history-card-xp-eyebrow')
   */
  cardXpEyebrow: '[flt-semantics-identifier="history-card-xp-eyebrow"]',
  /**
   * Per-card "◆ N PR" diamond row in heroGold via RewardAccent (sanctioned
   * scarcity scope). Rendered only when the workout's prCount > 0 —
   * omitted entirely on zero (per the "no empty placeholders" rule).
   * Use `.count() === 0` to assert absence; use `.first()` when at least
   * one is expected.
   * Semantics(identifier: 'history-card-pr-diamond')
   */
  cardPrDiamond: '[flt-semantics-identifier="history-card-pr-diamond"]',
  /**
   * 48dp surface2 summary strip on the Workout Detail screen. Sits
   * between the SliverAppBar and the first exercise card. Renders
   * "+N XP" in hotViolet with optional " · M PRs" span in heroGold
   * (via RewardAccent) when prCount > 0. Hidden entirely when both
   * totalXp and prCount are zero (no negative-confirmation strip on
   * incomplete sessions).
   * Semantics(identifier: 'history-detail-strip')
   */
  detailStrip: '[flt-semantics-identifier="history-detail-strip"]',
  /**
   * Tappable workout card on the History list. The card body is a Material
   * InkWell whose Semantics container merges the per-card text into the
   * accessible name; the workout title prefix "Workout" (en) is stable
   * regardless of routine name or date (routine-driven workouts read
   * "<Routine name> — <date>" while ad-hoc sessions read "Workout — <date>").
   * Match prefix "Workout" via role+name to anchor on the legacy/ad-hoc card
   * shape; tests that need a specific card should index via `.first()` or
   * filter by routine name. Tap pushes /home/history/{workoutId}.
   *
   * No `flt-semantics-identifier` is emitted on the card — the SliverList
   * builds plain `_WorkoutHistoryCard` widgets. Use this selector to find
   * the tappable region; assert content via the detail-screen selectors
   * after the navigation lands.
   */
  workoutCardButton: 'role=button[name*="Workout"]',
} as const;

// ---------------------------------------------------------------------------
// WORKOUT_DETAIL — read-only workout detail screen (/home/history/{workoutId}).
//
// `_ReadOnlyExerciseCard` (workout_detail_screen.dart:265) is a plain Material
// `Card` whose heading is `Text(exercise.exercise?.name)` with NO outer
// `Semantics(label: ...)` wrapper — so `role=group[name*="Exercise: "]` does
// NOT match here (unlike the EXERCISE_LIST / active-workout cards which use
// the `exerciseItemSemantics` l10n key for their AOM label). Two stable
// selectors below:
//   - `totalVolumeStrip` — locale-independent identifier on the 48dp strip
//     below all exercise cards; reliable "screen is alive" sentinel.
//   - `detailExerciseCardByName(name)` — text= match on the rendered display
//     name (caller passes the localized name).
// ---------------------------------------------------------------------------
export const WORKOUT_DETAIL = {
  /**
   * 48dp surface2 total-volume strip rendered BELOW the exercise cards on the
   * workout detail screen (`_WorkoutDetailBody`, ~line 224 of
   * `workout_detail_screen.dart`). Semantics(identifier:
   * 'workout-detail-total-volume-strip').
   *
   * Locale-independent. Use as the proof that "the detail screen mounted and
   * rendered its body" rather than the per-card name text (which is locale +
   * seed-data dependent).
   */
  totalVolumeStrip:
    '[flt-semantics-identifier="workout-detail-total-volume-strip"]',
  /**
   * Per-exercise card on the detail screen — targets the rendered exercise
   * NAME text. Pass the localized display name. For pt locale
   * `barbell_bench_press` renders as "Supino Reto com Barra"; for en it's
   * "Barbell Bench Press". See `seedFullHistoryPtData` in `global-setup.ts`
   * + `00033_seed_exercise_translations_pt.sql` for the pt mapping.
   *
   * Note: Flutter CanvasKit draws Text widgets to canvas — a `text=` selector
   * may not match if the name is rendered into the canvas without DOM text.
   * For the workout-detail screen specifically, the `Text(exercise.name)`
   * widget sits inside a Material `Card` which Flutter surfaces with a
   * matching AOM text node, so `text=` resolves in practice. If a future
   * regression breaks this, add a `Semantics(identifier:
   * 'workout-detail-exercise-card')` wrapper on `_ReadOnlyExerciseCard` and
   * switch this selector to identifier-based.
   */
  detailExerciseCardByName: (name: string) => `text=${name}`,
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
  /**
   * Phase 32 PR 32e — IdentityCard avatar (ProfileAvatar widget).
   * Semantics(identifier: 'identity-card-avatar'). Tappable when the user
   * is signed in — opens the picker → crop → upload flow. The E2E spec
   * only asserts visibility + tappability; the camera/gallery picker is
   * OS-level and untestable by Playwright.
   */
  identityCardAvatar: '[flt-semantics-identifier="identity-card-avatar"]',
  /**
   * Phase 32 PR 32e — Avatar picker bottom sheet root.
   * Semantics(identifier: 'avatar-picker-sheet'). Opens after tapping the
   * identityCardAvatar selector.
   */
  avatarPickerSheet: '[flt-semantics-identifier="avatar-picker-sheet"]',
  /**
   * PRs stat card in the StatsRow on ProfileSettingsScreen.
   * _StatCard wraps the content in Material > InkWell with no Semantics
   * identifier. Flutter AOM exposes the InkWell as role=button whose
   * accessible name concatenates the child Text nodes (value + label).
   * The label text is l10n key `prsLabel` = "PRs" in both en and pt-BR.
   * Use role=button[name*="PRs"] to match regardless of count value.
   * Tapping navigates to /records.
   */
  recordsStatRow: 'role=button[name*="PRs"]',
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
  /**
   * "Export my data" list tile — Semantics(identifier: 'manage-data-export').
   * Legal PR 3 — LGPD Art. 18 V / GDPR Art. 20 portability tile in the
   * YOUR DATA section above the destructive sections.
   */
  exportTile: '[flt-semantics-identifier="manage-data-export"]',
  /**
   * SnackBar after successful JSON export hand-off to share sheet —
   * Semantics(identifier: 'manage-data-export-success').
   * Use .first() — Flutter renders two AOM boundaries per SnackBar.
   */
  exportSuccess: '[flt-semantics-identifier="manage-data-export-success"]',
  /**
   * SnackBar when JSON export fails —
   * Semantics(identifier: 'manage-data-export-failed').
   * Use .first() — Flutter renders two AOM boundaries per SnackBar.
   */
  exportFailed: '[flt-semantics-identifier="manage-data-export-failed"]',
} as const;

// ---------------------------------------------------------------------------
// Legal PR 2 — Body-weight consent dialog selectors
//
// The consent dialog is a barrierDismissible:false AlertDialog surfaced by
// BodyweightEditorSheet._showConsentDialog() when bodyweightConsentProvider
// is false (the default). The dialog title / body / actions have no
// Semantics identifiers — use role=button selectors on the actions.
//
// "Save with consent" → FilledButton (role=button, name matches l10n key
//   `bodyweightConsentAccept` = "Save with consent" in en).
// "Cancel"            → TextButton (role=button, name "Cancel").
// ---------------------------------------------------------------------------
export const BODYWEIGHT_CONSENT = {
  /**
   * BodyweightRow tappable row on ProfileSettingsScreen.
   *
   * The Semantics(identifier: 'profile-bodyweight-row', container: true,
   * explicitChildNodes: true) node sits INSIDE the InkWell as a content
   * wrapper. `explicitChildNodes: true` blocks child-text merging, so the
   * InkWell's computed AOM accessible name is EMPTY — `role=button[name*=...]`
   * selectors match zero elements (cluster: semantics-identifier-pair-rule).
   *
   * Strategy: use the identifier CSS selector for scrollIntoViewIfNeeded and
   * visibility assertions (the node IS in the DOM at valid coordinates), then
   * call `.click({ force: true })` to bypass actionability checks and dispatch
   * pointer events at the node's coordinates — Flutter's hit-testing routes
   * those coordinates to the enclosing InkWell's onTap handler.
   */
  row: '[flt-semantics-identifier="profile-bodyweight-row"]',
  /**
   * "Save with consent" FilledButton in the body-weight consent dialog.
   * Tapping this flips bodyweightConsentProvider to true and proceeds with
   * the upsert. Use .first() if multiple button nodes exist (CanvasKit can
   * emit two AOM nodes per button in some frame states).
   */
  saveWithConsentButton: 'role=button[name="Save with consent"]',
  /**
   * "Cancel" TextButton in the body-weight consent dialog.
   * Tapping dismisses the dialog without saving or flipping the provider.
   * barrierDismissible:false — the dialog cannot be closed by tapping the scrim.
   */
  cancelButton: 'role=button[name="Cancel"]',
} as const;

// ---------------------------------------------------------------------------
// Legal PR 2 — Profile settings Privacy section (new toggles in PR #309)
//
// ProfileSettingsScreen PRIVACY section now contains three toggles in order:
//   1. CrashReportsToggle  (pre-existing)
//   2. AnalyticsToggle     (new — Legal PR 2)
//   3. BodyweightConsentToggle (new — Legal PR 2)
//
// Neither AnalyticsToggle nor BodyweightConsentToggle has a Semantics
// identifier wrapper. Target via SwitchListTile title text (role=switch).
// Flutter web exposes SwitchListTile as role=switch in the AOM.
// ---------------------------------------------------------------------------
export const PRIVACY_TOGGLES = {
  /**
   * Analytics opt-out toggle. SwitchListTile title: `sendUsageAnalytics`
   * = "Send usage analytics" (en). AOM role=switch with computed name
   * derived from the title text.
   */
  analyticsToggle: 'role=switch[name*="Send usage analytics"]',
  /**
   * Body-weight consent toggle (withdrawal mechanism). SwitchListTile
   * title: `bodyweightConsentToggleTitle` = "Body weight tracking" (en).
   */
  bodyweightConsentToggle: 'role=switch[name*="Body weight tracking"]',
  /**
   * Crash-reports toggle (pre-existing). SwitchListTile title:
   * `sendCrashReports` = "Send crash reports" (en).
   */
  crashReportsToggle: 'role=switch[name*="Send crash reports"]',
} as const;

// ---------------------------------------------------------------------------
// Legal PR 2 — Gender editor sheet selectors
//
// GenderEditorSheet surfaces a one-time disclosure banner the first time it's
// opened when gender == null AND genderConsentProvider == false.
// ---------------------------------------------------------------------------
export const GENDER_EDITOR = {
  /**
   * GenderEditorSheet root — Semantics(identifier: 'profile-gender-sheet').
   */
  sheet: '[flt-semantics-identifier="profile-gender-sheet"]',
  /**
   * GenderRow tappable row on ProfileSettingsScreen.
   *
   * The Semantics(identifier: 'profile-gender-row', container: true,
   * explicitChildNodes: true) node sits INSIDE the InkWell as a content
   * wrapper. `explicitChildNodes: true` blocks child-text merging, so the
   * InkWell's computed AOM accessible name is EMPTY — `role=button[name*=...]`
   * selectors match zero elements (cluster: semantics-identifier-pair-rule).
   *
   * Strategy: use the identifier CSS selector for scrollIntoViewIfNeeded and
   * visibility assertions (the node IS in the DOM at valid coordinates), then
   * call `.click({ force: true })` to bypass actionability checks and dispatch
   * pointer events at the node's coordinates — Flutter's hit-testing routes
   * those coordinates to the enclosing InkWell's onTap handler.
   */
  row: '[flt-semantics-identifier="profile-gender-row"]',
  /**
   * One-time consent banner inside the sheet.
   * Semantics(identifier: 'profile-gender-consent-banner').
   * Only rendered when genderConsentProvider == false AND gender == null.
   */
  consentBanner: '[flt-semantics-identifier="profile-gender-consent-banner"]',
  /** "Male" option tile — Semantics(identifier: 'profile-gender-male', button: true) */
  maleTile: '[flt-semantics-identifier="profile-gender-male"]',
  /** "Female" option tile — Semantics(identifier: 'profile-gender-female', button: true) */
  femaleTile: '[flt-semantics-identifier="profile-gender-female"]',
  /** "Other" option tile — Semantics(identifier: 'profile-gender-other', button: true) */
  otherTile: '[flt-semantics-identifier="profile-gender-other"]',
  /** "Not set" option tile — Semantics(identifier: 'profile-gender-not-set', button: true) */
  notSetTile: '[flt-semantics-identifier="profile-gender-not-set"]',
} as const;

// ---------------------------------------------------------------------------
// Phase 38d — Age (birth-year) capture.
//
// Two surfaces share the SAME editor sheet (AgeEditorSheet, opened via
// showAgeEditorSheet):
//   1. Profile → Settings AgeRow (`profile-age-row`).
//   2. Post-session "Set age" nudge (`post-session-age-prompt-cta`).
//
// The sheet's control is a real Flutter `ListWheelScrollView` (birth-year
// wheel) under CanvasKit. WHEEL-DRIVABILITY NOTE: a ListWheelScrollView's
// per-row numerals are drawn to the <canvas> (no DOM text nodes) and the
// wheel does NOT surface stable per-item AOM nodes Playwright can address by
// year. Precise wheel-spin to an arbitrary target year is therefore NOT
// reliably drivable in E2E (the rendered selection is in the canvas, not the
// DOM). Wheel arithmetic — the ≥18 structural floor, clear-to-NULL, and the
// textScaler item-extent — is pinned at the widget tier (age_row_test.dart).
// E2E covers the load-bearing user-perceptible outcomes instead: the sheet
// opens, the disclosure + Save / Cancel / Prefer-not-to-say affordances are
// present, saving the DEFAULT resting year (age-35) persists + the row
// reflects a numeric age, and Prefer-not-to-say reverts the row to "Not set".
//
// The row/sheet identifier nodes sit inside an InkWell with
// explicitChildNodes:true (same `semantics-identifier-pair-rule` barrier as
// GENDER_EDITOR / BODYWEIGHT_CONSENT) → the InkWell's computed AOM name is
// empty, so `role=button[name*=...]` matches 0 elements. Use the identifier
// CSS selector for visibility/scroll + `.click({ force: true })` to dispatch
// pointer events at the node coordinates; Flutter hit-testing routes them to
// the enclosing InkWell.
// ---------------------------------------------------------------------------
export const AGE_EDITOR = {
  /**
   * AgeRow tappable row on ProfileSettingsScreen — Semantics(identifier:
   * 'profile-age-row', container: true, explicitChildNodes: true). Tapping
   * opens AgeEditorSheet. The row's accessible label is `ageRowSemantics`
   * ("Age, {value}"), where value is the derived age ("39") or "Not set".
   */
  row: '[flt-semantics-identifier="profile-age-row"]',
  /**
   * AgeEditorSheet root — Semantics(identifier: 'profile-age-sheet').
   * Visibility = the sheet is open.
   */
  sheet: '[flt-semantics-identifier="profile-age-sheet"]',
  /**
   * The branded birth-year ListWheelScrollView — Semantics(identifier:
   * 'profile-age-wheel'). Present iff the sheet is open. NOT spin-drivable
   * to a target year (see header note); use for presence assertions only.
   */
  wheel: '[flt-semantics-identifier="profile-age-wheel"]',
  /**
   * "Prefer not to say" ghost — Semantics(identifier:
   * 'profile-age-prefer-not-to-say', button: true). Clears any stored DOB to
   * NULL and pops the sheet. `button:true` is set on the wrapper so a normal
   * click forwards (no force needed), but force is harmless if used.
   */
  preferNotToSay: '[flt-semantics-identifier="profile-age-prefer-not-to-say"]',
  /**
   * Save FilledButton inside the sheet. No identifier — match by accessible
   * role+name. Label is the `save` l10n key ("Save" en). Persists
   * `date_of_birth = DateTime(selectedYear, 1, 1)` for the wheel's resting
   * year (default = currentYear − 35) and pops.
   */
  saveButton: 'role=button[name="Save"]',
  /**
   * Cancel TextButton inside the sheet. No identifier — match by role+name.
   * Label is the `cancel` l10n key ("Cancel" en). Pops without writing.
   */
  cancelButton: 'role=button[name="Cancel"]',
} as const;

// ---------------------------------------------------------------------------
// Phase 38b — Cardio entry card (CardioEntryCard) on the active-workout
// screen. A cardio exercise (e.g. Treadmill, a default since 00014) seeds a
// default CardioSession (30:00, no distance/RPE) when added — so the
// "Complete cardio" CTA is enabled immediately with no further input.
// Completing a cardio entry is the load-bearing precondition for the
// Phase 38d post-session age prompt (`PostSessionState.hadCardio`).
// ---------------------------------------------------------------------------
export const CARDIO = {
  /**
   * "Complete cardio" OutlinedButton — Semantics(identifier:
   * 'cardio-complete', container: true, explicitChildNodes: true). Enabled
   * once durationSeconds > 0 (the seeded default is 30:00). The identifier
   * wraps the button; explicitChildNodes blocks name-merge so use the
   * identifier CSS selector + `.click({ force: true })`.
   */
  complete: '[flt-semantics-identifier="cardio-complete"]',
  /**
   * Green ✓ in the completed-cardio header that re-opens the entry for edits
   * — Semantics(identifier: 'cardio-uncomplete'). Present only after
   * completion; a useful sentinel that the entry is in the completed state.
   */
  uncomplete: '[flt-semantics-identifier="cardio-uncomplete"]',
} as const;

// ---------------------------------------------------------------------------
// Weekly plan — WeekBucketSection (Home screen) and PlanManagementScreen
// ---------------------------------------------------------------------------
export const WEEKLY_PLAN = {
  /**
   * "THIS WEEK" header semantics identifier — surfaced by the active weekly
   * plan section on Home. Phase 26f replaced the legacy WeekReviewSection
   * with the bucket chip row (HOME.bucketChipRow); this identifier is still
   * emitted by the active-plan path and is used by the surviving "render
   * weekly plan section on home screen without error" smoke test as one of
   * the three states the home screen may show.
   */
  thisWeekHeader: '[flt-semantics-identifier="weekly-plan-this-week"]',
  /**
   * "Plan your week" affordance on the home tab.
   * Phase 26f: the legacy `home-plan-your-week` banner was deleted. The
   * closest 26f equivalent is the "Editar plano →" link on the bucket chip
   * row — always visible (even on empty bucket) and pushes /plan/week.
   * Pinned here so legacy WEEKLY_PLAN.planYourWeekCta callers keep resolving
   * after the home redesign.
   */
  planYourWeekCta: '[flt-semantics-identifier="home-edit-plan-link"]',
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
  /**
   * 23-P-4 — routine-removed undo SnackBar on PlanManagementScreen.
   *
   * Swipe-removing a pending routine fires a 3 s CountdownSnackBar
   * (`_removeRoutine`, Phase 23 #214) whose message is the l10n key
   * `routineRemoved` = "Routine removed" (en). Flutter CanvasKit draws
   * SnackBar text to canvas, so a `text=` selector never resolves; the
   * AOM exposes the SnackBar content as a `role=group` whose accessible
   * name is the localized message. Use `.first()` — Flutter renders two
   * AOM boundaries per SnackBar (per CLAUDE.md E2E Conventions note on
   * SnackBar text). Locale: en only (full E2E suite runs in English).
   */
  routineRemovedUndoSnackBar: 'role=group[name=/Routine removed/i]',
} as const;

// ---------------------------------------------------------------------------
// Weekly plan — Phase 26e compact-row layout (WeekPlanScreen)
// ---------------------------------------------------------------------------
//
// Identifier-based selectors are locale-independent; text-based selectors use
// EN copy because Playwright runs without a locale config → app defaults to EN.
//
// Muscle bar labels: MuscleBarRow renders `name.toUpperCase()` so the AOM
// text is "CHEST", "BACK", etc. — not the title-case ARB values.
//
// Cardio is intentionally excluded from the 6-bar section (v1 rendering rule).
export const WEEKLY_PLAN_26E = {
  /**
   * "+ Add workout" InkWell at the bottom of the bucket list.
   *
   * AOM structure (Flutter Web):
   *   flt-semantics[role="button"][flt-semantics-identifier="weekly-plan-add-workout"]
   *     └─ flt-semantics[role="button"][flt-tappable][tabindex="0"] "+ Add workout"
   *
   * The outer wrapper node carries the identifier but is NOT flt-tappable.
   * Clicking via `[flt-semantics-identifier=...]` hits the wrapper and does
   * not forward to Flutter's gesture system. Use `role=button[name*="Add workout"]`
   * to target the inner flt-tappable directly (per CLAUDE.md AOM selector rule).
   *
   * Locale note: "+ Add workout" is the EN value of l10n key `addWorkout`.
   * Text-based — if the key changes, update this selector.
   */
  addWorkoutCta: 'role=button[name*="Add workout"]',
  /**
   * ⓘ icon button next to the "Weekly engagement" header.
   * Semantics(button: true, identifier: 'engagement-info-icon').
   */
  engagementInfoIcon: '[flt-semantics-identifier="engagement-info-icon"]',
  /**
   * "Weekly engagement" section — the EngajamentoSection Column is a single
   * AOM group node whose aria-label concatenates all child Text widgets:
   *   "Weekly engagement\nCHEST\n0 / 0\nBACK\n0 / 0\n…\nDone\nPlanned"
   * Flutter AOM puts the label in aria-label, NOT in DOM text content, so
   * `:has-text()` pseudo-class doesn't work — use `role=group[name*=...]`.
   * Use .first() because multiple group nodes may exist in the tree.
   */
  engagementSection: 'role=group[name*="Weekly engagement"]',
  /**
   * Engagement explainer bottom sheet — Flutter Web AOM exposes the modal
   * bottom sheet scrim/container as a node with `aria-label="Dialog"` and no
   * role attribute. The sheet's Text content ("How we count sets", body) is
   * rendered via CanvasKit and does NOT appear as AOM text or aria-label.
   * After `showModalBottomSheet` resolves, the count of `[aria-label="Dialog"]`
   * goes from 0 to 1. Use `.first()` — count should be exactly 1 for this sheet.
   *
   * AOM observation: flt-semantic-node-95 role="" label="Dialog" (no child nodes
   * labeled with sheet content — canvas rendering, not DOM text).
   */
  engagementExplainerSheet: '[aria-label="Dialog"]',
  /**
   * Muscle-group bars — all 6 bars are merged into the EngajamentoSection's
   * single AOM group node (no per-bar Semantics identifiers). The group's
   * aria-label contains each bar's uppercase name. Asserting `name*="CHEST"`
   * on the group confirms the section rendered the bar.
   *
   * MuscleBarRow renders `name.toUpperCase()` → "CHEST", "BACK", etc.
   * All muscle selectors point to the same AOM group; use .first().
   */
  muscleBarChest: 'role=group[name*="CHEST"]',
  muscleBarBack: 'role=group[name*="BACK"]',
  muscleBarLegs: 'role=group[name*="LEGS"]',
  muscleBarShoulders: 'role=group[name*="SHOULDERS"]',
  muscleBarArms: 'role=group[name*="ARMS"]',
  muscleBarCore: 'role=group[name*="CORE"]',
  /**
   * CARDIO is intentionally absent from the v1 6-bar layout.
   * The engagement group's aria-label must NOT contain "CARDIO".
   * Use `page.locator(muscleBarCardio).filter({hasNot:...})` pattern OR
   * simply assert the engagement group's label does not match "CARDIO".
   * Kept as a selector for completeness; test checks count() == 0 indirectly
   * by asserting the section group name does not include "CARDIO".
   */
  muscleBarCardio: 'role=group[name*="CARDIO"]',
  /**
   * Bucket routine row — keyed by routineId.
   * Semantics(identifier: 'bucket-row-{routineId}').
   */
  bucketRow: (routineId: string) =>
    `[flt-semantics-identifier="bucket-row-${routineId}"]`,
  /**
   * Overflow menu on a bucket routine row — keyed by routineId.
   * Semantics(identifier: 'bucket-row-overflow-{routineId}').
   */
  bucketRowOverflow: (routineId: string) =>
    `[flt-semantics-identifier="bucket-row-overflow-${routineId}"]`,
  /**
   * Spontaneous tag chip on a done-spontaneous bucket row.
   * l10n key: spontaneousTag = "Spontaneous" (en).
   *
   * The "Spontaneous" tag text is merged into the bucket-row group's
   * aria-label (no dedicated Semantics identifier on _SpontaneousTag).
   * Use `role=group[name*="Spontaneous"]` to find the row group.
   *
   * Note: The spontaneous E2E flow test (test 2.3) was deferred to v1.1;
   * the widget tests (Task 7) pin this behavior at the unit level.
   */
  bucketRowSpontaneousTag: 'role=group[name*="Spontaneous"]',
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
   *
   * Named `profileSetupIndicator` because page 2 has no actual headline
   * semantics — the Beginner pill is the first stable identifier the
   * spec can wait on as proof that page 2 mounted. The earlier name
   * `profileSetupHeadline` actively misled future maintainers since
   * "Setup profile" / "Tell us about yourself" Text widgets do NOT
   * carry semantics identifiers.
   */
  profileSetupIndicator: '[flt-semantics-identifier="onboarding-beginner"]',
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
  /** Per-body-part rank row — Semantics(identifier: 'body-part-row-{slug}') */
  bodyPartRow: (slug: 'chest' | 'back' | 'legs' | 'shoulders' | 'arms' | 'core') =>
    `[flt-semantics-identifier="body-part-row-${slug}"]`,
  /** CardioProgressRow — Semantics(identifier: 'body-part-row-cardio') */
  cardioProgressRow: '[flt-semantics-identifier="body-part-row-cardio"]',
  /**
   * Phase 26b SagaHeader class-label Text — Semantics(identifier: 'saga-header-class').
   * Replaces the legacy ClassBadge selector ('class-badge'). The class label
   * is now a Text child of the SagaHeader meta column rather than a standalone
   * ClassBadge widget.
   */
  sagaHeaderClass: '[flt-semantics-identifier="saga-header-class"]',
  /**
   * Phase 26b SagaHeader active-title Text — Semantics(identifier: 'saga-header-title').
   * Replaces the legacy ActiveTitlePill selector. Only rendered when an active
   * title is equipped (activeTitle != null && isNotEmpty).
   */
  sagaHeaderTitle: '[flt-semantics-identifier="saga-header-title"]',
  /**
   * Phase 26b CharacterXpBar widget — Semantics(identifier: 'character-xp-bar').
   * The XP progress bar shown beneath the SagaHeader on the character sheet.
   */
  characterXpBar: '[flt-semantics-identifier="character-xp-bar"]',
  /** First-set-awakens onboarding banner — Semantics(identifier: 'first-set-awakens-banner') */
  firstSetAwakensBanner: '[flt-semantics-identifier="first-set-awakens-banner"]',
  /** Codex nav rows — Semantics(identifier: 'codex-nav-{section}') */
  codexNavStats: '[flt-semantics-identifier="codex-nav-stats"]',
  codexNavTitles: '[flt-semantics-identifier="codex-nav-titles"]',
  codexNavHistory: '[flt-semantics-identifier="codex-nav-history"]',
  /** Gear-icon settings button in CharacterSheetScreen AppBar — Semantics(identifier: 'saga-settings-btn') */
  gearIcon: '[flt-semantics-identifier="saga-settings-btn"]',
  /** ProfileSettingsScreen root — identified by PROFILE.heading ('profile-heading') */
  profileSettingsScreen: '[flt-semantics-identifier="profile-heading"]',
  // -----------------------------------------------------------------------
  // Phase 18d.2 + 26c — /saga/stats deep-dive screen
  //
  // The deep-dive replaces SagaStubScreen at /saga/stats. Phase 26c
  // restructured the screen into three sections: VitalityTrendChart,
  // VitalityTable, and a column of per-body-part VolumePeakBlocks
  // (replacing the legacy _VolumePeakTable + PeakLoadsTable).
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
  vitalityRow: (
    slug:
      | 'chest'
      | 'back'
      | 'legs'
      | 'shoulders'
      | 'arms'
      | 'core'
      // Phase 38e — cardio is now a 7th active track; the stats provider
      // iterates activeBodyParts so the VitalityTable emits a cardio row.
      | 'cardio',
  ) => `[flt-semantics-identifier="vitality-row-${slug}"]`,
  /** VitalityTrendChart container — Semantics(identifier: 'vitality-trend-chart') */
  vitalityTrendChart: '[flt-semantics-identifier="vitality-trend-chart"]',
  /**
   * Phase 26c — VitalityExplainerSheet (bottom sheet content opened by
   * the ⓘ icon on either vitality section header).
   */
  vitalityExplainerSheet:
    '[flt-semantics-identifier="vitality-explainer-sheet"]',
  /**
   * Phase 26c — ⓘ icon on the vitality trend section header. Tapping it
   * opens VitalityExplainerSheet. The Semantics wrapper is added at the
   * widget level (lib/features/rpg/ui/stats_deep_dive_screen.dart
   * → _InfoIconButton).
   */
  vitalityTrendInfoIcon:
    '[flt-semantics-identifier="vitality-trend-info-icon"]',
  /**
   * Phase 26c — ⓘ icon on the live-vitality table section header.
   * Opens the same VitalityExplainerSheet.
   */
  vitalityTableInfoIcon:
    '[flt-semantics-identifier="vitality-table-info-icon"]',
  /**
   * Phase 26c — Per-body-part VolumePeakBlock. Slug = BodyPart.dbValue.
   * Replaces the legacy `volumePeakTable` + `peakLoadsTable` selectors
   * (both widgets were deleted in 26c).
   */
  volumePeakBlock: (
    slug: 'chest' | 'back' | 'legs' | 'shoulders' | 'arms' | 'core',
  ) => `[flt-semantics-identifier="volume-peak-block-${slug}"]`,
} as const;

// ---------------------------------------------------------------------------
// Mid-workout overlays + title unlocks
//
// **Path A pivot (PR 29.5, 2026-05-22):** the mid-workout celebration
// flash layer was retired entirely. The post-session screen (PR 30a)
// carries the full celebration ceremony for ALL events. There is no
// mid-workout overlay widget to select against — the five legacy
// overlays and the thin-flash replacement that briefly replaced them
// are all gone. The overflow card surface also migrates to the
// post-session screen and no longer mounts mid-workout.
//
// What remains under CELEBRATION: the TitlesScreen (codex) selectors
// that are unrelated to mid-workout playback, and the FAB / Finish
// button aliases used by workout specs.
// ---------------------------------------------------------------------------
export const CELEBRATION = {
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
// TITLES — Phase 26d revamp (Equipado / Conquistados / Próximos regions).
// Counter pill in the AppBar actions slot. Identifier wrappers per the
// `cluster_semantics_identifier_pair_rule` cluster.
// ---------------------------------------------------------------------------
export const TITLES = {
  /** TitlesScreen root — Semantics(identifier: 'titles-screen'). */
  screen: '[flt-semantics-identifier="titles-screen"]',
  /** Equipado heroGold card (only present when an earned title is active). */
  equippedCard: '[flt-semantics-identifier="titles-equipped-card"]',
  /** Earned-but-not-equipped row by slug. */
  earnedRow: (slug: string) =>
    `[flt-semantics-identifier="titles-earned-row-${slug}"]`,
  /** Next-milestone row by slug (body-part or character-level). */
  nextRow: (slug: string) =>
    `[flt-semantics-identifier="titles-next-row-${slug}"]`,
  /** Cross-build "Especial" card by slug (only when within 1 rank). */
  crossBuildCard: (slug: string) =>
    `[flt-semantics-identifier="titles-cross-build-card-${slug}"]`,
  /** Counter pill in the AppBar actions slot. */
  counterPill: '[flt-semantics-identifier="titles-counter-pill"]',
  /** Region header wrappers. */
  regionEquipped: '[flt-semantics-identifier="titles-region-equipped"]',
  regionEarned: '[flt-semantics-identifier="titles-region-earned"]',
  regionNext: '[flt-semantics-identifier="titles-region-next"]',
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

// ---------------------------------------------------------------------------
// POST_SESSION — Post-session cinematic screen (PR 30a).
//
// The screen lives at `/workout/finish/:workoutId` and is pushed by
// `finish_workout_coordinator.dart` after a non-empty online finish.
// Offline finishes + empty-session finishes still route to /home.
// Post-PR-30c, this is the canonical post-finish destination — the legacy
// `/pr-celebration` route + screen were retired; PR confirmation now
// lives in the B3 PR cut + summary panel detail row below.
//
// All selectors use `flt-semantics-identifier` (Flutter AOM, not CSS class).
// ---------------------------------------------------------------------------
export const POST_SESSION = {
  /** Full-screen post-session route root — Semantics(identifier: 'post-session-screen'). */
  screen: '[flt-semantics-identifier="post-session-screen"]',

  /**
   * Beat 1 XP cut — full-screen XP reveal.
   * Semantics(identifier: 'post-session-b1-xp').
   */
  b1Xp: '[flt-semantics-identifier="post-session-b1-xp"]',

  /**
   * Beat 2 body-part tally cut — all B2 variants (single, cascade, elevated rank-up)
   * share this identifier. Semantics(identifier: 'post-session-b2-tally').
   */
  b2Tally: '[flt-semantics-identifier="post-session-b2-tally"]',

  /**
   * Beat 3 Personal Record cut.
   * Semantics(identifier: 'post-session-b3-pr').
   */
  b3Pr: '[flt-semantics-identifier="post-session-b3-pr"]',

  /**
   * Beat 3 Title Unlock cut.
   * Semantics(identifier: 'post-session-b3-title').
   */
  b3Title: '[flt-semantics-identifier="post-session-b3-title"]',

  /**
   * Beat 3 Class Change cut.
   * Semantics(identifier: 'post-session-b3-class-change').
   */
  b3ClassChange: '[flt-semantics-identifier="post-session-b3-class-change"]',

  /**
   * Summary panel — the final post-cinematic panel with saga label, stats,
   * next-step hook, and CONTINUAR CTA.
   * Semantics(identifier: 'post-session-summary').
   */
  summary: '[flt-semantics-identifier="post-session-summary"]',

  /**
   * CONTINUAR / Continue button on the summary panel.
   * Semantics(identifier: 'post-session-continue-cta').
   */
  continueCta: '[flt-semantics-identifier="post-session-continue-cta"]',

  /**
   * Title EQUIP row inside the summary panel (State 8 / State 10).
   * Replaces the retired `title-unlock-sheet-equip-button` selector from
   * the mid-workout overlay era (PR 29.5).
   * Semantics(identifier: 'post-session-title-equip-row').
   */
  titleEquipRow: '[flt-semantics-identifier="post-session-title-equip-row"]',

  /**
   * Skip-cinematic button (top-right corner of every cinematic cut, NOT on
   * the summary panel). Routes to controller.skipToSummary() — same path
   * the long-press gesture takes. Added in PR 30a UX pass (2026-05-23) as
   * a discoverable affordance for the previously-undiscoverable long-press.
   * Semantics(identifier: 'post-session-skip-btn').
   */
  skipBtn: '[flt-semantics-identifier="post-session-skip-btn"]',

  /**
   * Empty-session guard sheet (State 11) — shown when the user taps Finish
   * with zero logged sets, BEFORE the post-session route is pushed.
   * Semantics(identifier: 'empty-session-guard-sheet').
   */
  emptySessionGuardSheet: '[flt-semantics-identifier="empty-session-guard-sheet"]',

  /**
   * Share CTA on the summary panel (Phase 30 PR 30a label; PR 30b wiring).
   * Tapping opens the share-card bottom sheet.
   * Semantics(identifier: 'post-session-share-cta').
   */
  shareCta: '[flt-semantics-identifier="post-session-share-cta"]',

  /**
   * S2 Mission Debrief section root (Phase 31 Pass 3). Fills the post-
   * cinematic real estate above the share/continue CTAs with the lift
   * table, segmented XP bar, per-BP rank deltas, and next-target callout.
   * Semantics(identifier: 'mission-debrief-section').
   */
  missionDebriefSection: '[flt-semantics-identifier="mission-debrief-section"]',

  /**
   * Per-row lift selector pattern (Phase 31 Pass 3). Index is 0-based;
   * top-4 lifts by XP contribution descending. Use as
   * `${POST_SESSION.missionDebriefLiftRow}-0` for the hero row.
   * Semantics(identifier: 'mission-debrief-lift-row-{i}').
   */
  missionDebriefLiftRow: '[flt-semantics-identifier^="mission-debrief-lift-row-"]',

  /**
   * Per-BP rank delta row selector pattern (Phase 31 Pass 3). Slug is the
   * BodyPart.dbValue (chest/back/legs/...). Use as
   * `[flt-semantics-identifier="mission-debrief-bp-row-chest"]`.
   */
  missionDebriefBpRow: '[flt-semantics-identifier^="mission-debrief-bp-row-"]',

  /**
   * Segmented XP-by-BP bar inside the Mission Debrief (Phase 31). Pins
   * the bar's visibility through the AOM tree without grepping hue colors
   * out of the segment widgets.
   * Semantics(identifier: 'mission-debrief-xp-bar').
   */
  missionDebriefXpBar: '[flt-semantics-identifier="mission-debrief-xp-bar"]',

  /**
   * Phase 38e — per-row cardio entry selector pattern in the Mission Debrief
   * ledger. Index is 0-based; cardio rows render AFTER the strength lift rows
   * so a mixed session reads as one coherent ledger. Sourced from
   * `state.cardioEntries` (completed cardio entries), NOT from `topLifts`.
   * The CardioEntryRow shows the duration as the right-aligned teal hero.
   * Semantics(identifier: 'mission-debrief-cardio-row-{i}', container: true,
   * explicitChildNodes: true) — explicitChildNodes blocks name-merge, so match
   * on the identifier selector (cluster: aom-explicit-children-block-name-merge).
   * Use as `${POST_SESSION.missionDebriefCardioRow}-0` for the first cardio row.
   */
  missionDebriefCardioRow:
    '[flt-semantics-identifier^="mission-debrief-cardio-row-"]',

  /**
   * Phase 38d — one-time post-session "set your age" nudge banner
   * (AgePromptBanner). Rendered on the summary panel ONLY when all gates
   * hold: the session had a completed cardio entry (hadCardio), the cached
   * profile's `date_of_birth` is NULL, and the never-show-again Hive flag is
   * unset. Semantics(identifier: 'post-session-age-prompt').
   */
  agePrompt: '[flt-semantics-identifier="post-session-age-prompt"]',
  /**
   * "SET AGE" CTA inside the age-prompt banner — Semantics(identifier:
   * 'post-session-age-prompt-cta', button: true). Opens the shared
   * AgeEditorSheet (AGE_EDITOR.sheet).
   */
  agePromptCta: '[flt-semantics-identifier="post-session-age-prompt-cta"]',
  /**
   * Dismiss ✕ inside the age-prompt banner — Semantics(identifier:
   * 'post-session-age-prompt-dismiss', button: true). Records the
   * never-show-again Hive flag + removes the banner for the session.
   */
  agePromptDismiss:
    '[flt-semantics-identifier="post-session-age-prompt-dismiss"]',
} as const;

// ---------------------------------------------------------------------------
// SHARE_FLOW — Share-card pipeline (PR 30b).
//
// Bottom sheet (camera / gallery / discreet), preview screen (A↔B toggle,
// retake + share CTAs). Camera + gallery row taps are SKIPPED on web E2E —
// browsers route those to the platform picker which Playwright can't drive.
// The Discreet path (no-photo) is the testable end-to-end shape on web.
// ---------------------------------------------------------------------------
export const SHARE_FLOW = {
  /** Bottom-sheet container — Semantics(identifier: 'share-sheet'). */
  sheet: '[flt-semantics-identifier="share-sheet"]',
  /** Camera row inside the sheet — hidden when permission is permanentlyDenied. */
  sheetCamera: '[flt-semantics-identifier="share-sheet-camera"]',
  /** Gallery row inside the sheet. */
  sheetGallery: '[flt-semantics-identifier="share-sheet-gallery"]',
  /** Discreet row inside the sheet — locks the preview to the Discreet variant. */
  sheetDiscreet: '[flt-semantics-identifier="share-sheet-discreet"]',

  /** Preview screen root — Semantics(identifier: 'share-preview-screen'). */
  previewScreen: '[flt-semantics-identifier="share-preview-screen"]',
  /** Primary share CTA on the preview screen. */
  previewShareButton: '[flt-semantics-identifier="share-preview-share-button"]',
  /** Retake button — resets the controller + pops back to the share sheet. */
  previewRetake: '[flt-semantics-identifier="share-preview-retake"]',
} as const;
