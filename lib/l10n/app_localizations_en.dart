// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navExercises => 'Exercises';

  @override
  String get navRoutines => 'Routines';

  @override
  String get navProfile => 'Profile';

  @override
  String get sagaTabLabel => 'Saga';

  @override
  String get classSlotPlaceholder => 'The iron will name you.';

  @override
  String get classInitiate => 'Initiate';

  @override
  String get classBerserker => 'Berserker';

  @override
  String get classBulwark => 'Bulwark';

  @override
  String get classSentinel => 'Sentinel';

  @override
  String get classPathfinder => 'Pathfinder';

  @override
  String get classAtlas => 'Atlas';

  @override
  String get classAnchor => 'Anchor';

  @override
  String get classAscendant => 'Ascendant';

  @override
  String get dormantCardioCopy => 'Cardio runes awaken in a future chapter.';

  @override
  String get firstSetAwakensCopy => 'Your first set awakens this path.';

  @override
  String get statsDeepDiveLabel => 'Stats deep-dive';

  @override
  String get titlesLabel => 'Titles';

  @override
  String get historyLabel => 'History';

  @override
  String get settingsLabel => 'Settings';

  @override
  String get vitalityCopyUntested => 'Uncharted — log a set to begin.';

  @override
  String get vitalityCopyDormant =>
      'Dormant. Train this group to reawaken its path.';

  @override
  String get vitalityRowUntestedSubtitle => 'No data';

  @override
  String get vitalityStateBandActive => 'Active';

  @override
  String get vitalityStateBandWaning => 'Waning';

  @override
  String get vitalityStateBandDormant => 'Dormant';

  @override
  String get vitalityExplainerTitle => 'Vitality';

  @override
  String get vitalityExplainerDefinition =>
      'Vitality reflects how recent your training is for each muscle group. It\'s a measure of how active your saga is, not a measure of strength.';

  @override
  String get vitalityExplainerHowItMoves => 'How it moves:';

  @override
  String get vitalityExplainerBandActive =>
      '66–100% — recent training, on the path.';

  @override
  String get vitalityExplainerBandWaning =>
      '34–65% — slowing down, the path is fading.';

  @override
  String get vitalityExplainerBandDormant =>
      '0–33% — the path has gone silent.';

  @override
  String get vitalityExplainerRankSafety =>
      'Vitality does NOT affect your rank or XP — those are permanent. Vitality is purely a consistency signal.';

  @override
  String get withinRankXpSuffix => 'to next rank';

  @override
  String get statsDeepDiveTitle => 'Stats';

  @override
  String get vitalityTrendHeading => '90-Day Vitality Trend';

  @override
  String get vitalityTrendHeadingShort => 'Vitality Trend';

  @override
  String get liveVitalitySectionHeading => 'Live Vitality';

  @override
  String get volumePeakSectionHeading => 'Volume & Peak';

  @override
  String get peakLoadsSectionHeading => 'Peak Loads';

  @override
  String get peakLoadsEmpty => 'No peaks recorded yet.';

  @override
  String get weeklyVolumeUnit => 'sets';

  @override
  String get oneRmEstimateLabel => '1RM est.';

  @override
  String get chartXLabelToday => 'Today';

  @override
  String get chartXLabel90DaysAgo => '90 days ago';

  @override
  String chartXLabelDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get loadingOverlayStop => 'Stop';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get continueLabel => 'Continue';

  @override
  String get logOut => 'Log Out';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get create => 'Create';

  @override
  String get add => 'Add';

  @override
  String get skip => 'Skip';

  @override
  String get back => 'Back';

  @override
  String get backExitHint => 'Press back again to exit';

  @override
  String get close => 'Close';

  @override
  String get start => 'Start';

  @override
  String get remove => 'Remove';

  @override
  String get discard => 'Discard';

  @override
  String get resume => 'Resume';

  @override
  String get clear => 'Clear';

  @override
  String get replace => 'Replace';

  @override
  String get undo => 'Undo';

  @override
  String get all => 'All';

  @override
  String get or => 'OR';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Something went wrong';

  @override
  String get noResults => 'No results found';

  @override
  String get emptyState => 'Nothing here yet';

  @override
  String get search => 'Search';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get logIn => 'LOG IN';

  @override
  String get signUp => 'SIGN UP';

  @override
  String get signupHeading => 'CREATE ACCOUNT';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthMedium => 'Medium';

  @override
  String get passwordStrengthStrong => 'Strong password!';

  @override
  String get passwordTipLength => 'use 8+ characters';

  @override
  String get passwordTipNumber => 'add a number';

  @override
  String get passwordTipSymbol => 'add a symbol';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get passwordRevealHint => 'Tap the eye to check your password';

  @override
  String get signupAgeRequiredHint => 'Confirm your age to continue';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get sendResetEmail => 'Send Reset Email';

  @override
  String get offlineBanner =>
      'Offline — changes will sync when you\'re back online';

  @override
  String pendingSyncSingular(int count) {
    return '$count change pending sync';
  }

  @override
  String pendingSyncPlural(int count) {
    return '$count changes pending sync';
  }

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String weeksAgo(int count) {
    return '$count weeks ago';
  }

  @override
  String monthsAgo(int count) {
    return '$count months ago';
  }

  @override
  String get muscleGroupChest => 'Chest';

  @override
  String get muscleGroupBack => 'Back';

  @override
  String get muscleGroupLegs => 'Legs';

  @override
  String get muscleGroupShoulders => 'Shoulders';

  @override
  String get muscleGroupArms => 'Arms';

  @override
  String get muscleGroupCore => 'Core';

  @override
  String get muscleGroupCardio => 'Cardio';

  @override
  String get equipmentBarbell => 'Barbell';

  @override
  String get equipmentDumbbell => 'Dumbbell';

  @override
  String get equipmentCable => 'Cable';

  @override
  String get equipmentMachine => 'Machine';

  @override
  String get equipmentBodyweight => 'Bodyweight';

  @override
  String get equipmentBands => 'Bands';

  @override
  String get equipmentKettlebell => 'Kettlebell';

  @override
  String get setTypeWorking => 'Working';

  @override
  String get setTypeWarmup => 'Warm-up';

  @override
  String get setTypeDropset => 'Drop Set';

  @override
  String get setTypeFailure => 'To Failure';

  @override
  String get recordTypeMaxWeight => 'Max Weight';

  @override
  String get recordTypeMaxReps => 'Max Reps';

  @override
  String get recordTypeMaxVolume => 'Max Volume';

  @override
  String get weightUnitKg => 'KG';

  @override
  String get weightUnitLbs => 'LBS';

  @override
  String get appName => 'RepSaga';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Enter a valid email';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get displayNameRequired => 'Enter a name';

  @override
  String get forgotPasswordHint =>
      'Enter your email above, then tap \"Forgot password?\"';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String sendResetEmailTo(String email) {
    return 'Send a password reset email to $email?';
  }

  @override
  String get resetEmailSent => 'Password reset email sent. Check your inbox.';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get alreadyHaveAccount => 'Already have an account? Log in';

  @override
  String get dontHaveAccount => 'Don\'t have an account? Sign up';

  @override
  String get legalAgreePrefix => 'By continuing, you agree to our ';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get andSeparator => ' and ';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get authErrorInvalidCredentials =>
      'Wrong email or password. Please try again.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Please check your inbox and confirm your email first.';

  @override
  String get authErrorAlreadyRegistered =>
      'An account with this email already exists. Try logging in instead.';

  @override
  String get authErrorRateLimit =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get authErrorWeakPassword =>
      'Password is too weak. Use at least 6 characters.';

  @override
  String get authErrorNetwork =>
      'No internet connection. Check your network and try again.';

  @override
  String get authErrorTimeout => 'Request timed out. Please try again.';

  @override
  String get authErrorTokenExpired =>
      'The confirmation link has expired. Please request a new one.';

  @override
  String get authErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get checkYourInbox => 'Check your inbox';

  @override
  String get confirmationSentTo => 'We sent a confirmation email to';

  @override
  String get confirmationSent => 'We sent you a confirmation email';

  @override
  String get tapLinkToVerify =>
      'Tap the link in the email to verify your account, then come back and log in.';

  @override
  String get emailResent => 'Email resent! Check your inbox.';

  @override
  String get backToLogin => 'BACK TO LOGIN';

  @override
  String get didntReceiveResend => 'Didn\'t receive it? Resend email';

  @override
  String get onboardingHeadline => 'Track every rep,\nevery time';

  @override
  String get onboardingSubtitle =>
      'Log workouts, crush personal records, and build the physique you want.';

  @override
  String get getStarted => 'GET STARTED';

  @override
  String get setupProfile => 'Set up your profile';

  @override
  String get tellUsAboutYourself => 'Tell us a bit about yourself';

  @override
  String get displayName => 'Display name';

  @override
  String get fitnessLevel => 'Fitness level';

  @override
  String get howOftenTrain => 'How often do you plan to train?';

  @override
  String get weeklyGoalHint => 'Your weekly goal — you can change this anytime';

  @override
  String get letsGo => 'LET\'S GO';

  @override
  String get failedToSaveProfile => 'Failed to save profile. Please try again.';

  @override
  String get onboardingErrorOffline =>
      'You\'re offline. Check your connection and try again.';

  @override
  String get onboardingErrorSessionExpired =>
      'Your session expired. Sign in again.';

  @override
  String get onboardingErrorSessionExpiredCta => 'Sign in';

  @override
  String get onboardingErrorValidationGeneric => 'Please check your inputs.';

  @override
  String onboardingErrorValidationField(String field, String message) {
    return '$field: $message';
  }

  @override
  String get fitnessLevelBeginner => 'Beginner';

  @override
  String get fitnessLevelIntermediate => 'Intermediate';

  @override
  String get fitnessLevelAdvanced => 'Advanced';

  @override
  String get homeActionHeroCreateFirstRoutine => 'Create first routine';

  @override
  String get homeActionHeroFreeWorkout => 'Free workout';

  @override
  String get homeActionHeroFreeWorkoutSubtitleWeekComplete => 'Week complete';

  @override
  String homeActionHeroStartRoutine(String routineName) {
    return 'Start $routineName';
  }

  @override
  String get homeActionHeroStartEyebrow => 'START';

  @override
  String get homeActionHeroFreeEyebrow => 'FREE WORKOUT';

  @override
  String get homeActionHeroWelcomeEyebrow => 'WELCOME';

  @override
  String homeBucketDaysTrained(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString days trained',
      one: '1 day trained',
      zero: 'No days trained',
    );
    return '$_temp0';
  }

  @override
  String get homeBucketSectionTitle => 'This week';

  @override
  String get homeBucketSpontaneousBadge => 'Free';

  @override
  String get homeCharacterCardChevronHint => 'Tap to expand character details';

  @override
  String homeClosestRankUp(String bodyPart, int xp, int rank) {
    return '◆ $bodyPart · $xp XP for rank $rank';
  }

  @override
  String get homeEditPlanLink => 'Edit plan →';

  @override
  String get homeFirstStepFallback => 'Begin your journey — first set awaits';

  @override
  String homeNudgeBodyPartTitleClose(String bodyPart, String titleName) {
    return '$bodyPart title within reach: $titleName';
  }

  @override
  String homeNudgeCrossBuildClose(String titleName) {
    return 'Cross-build title within reach: $titleName';
  }

  @override
  String homeNudgeRemainingWorkouts(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Need $countString workouts to close the week',
      one: 'Need 1 workout to close the week',
    );
    return '$_temp0';
  }

  @override
  String homeNudgeStreakDays(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString-day streak',
      one: '1-day streak',
    );
    return '$_temp0';
  }

  @override
  String get samePlanThisWeek => 'Same plan this week?';

  @override
  String get myRoutines => 'MY ROUTINES';

  @override
  String get seeAll => 'See all';

  @override
  String get createYourFirstRoutine => 'Create Your First Routine';

  @override
  String get homeStarterRoutinesLabel => 'Starter Routines';

  @override
  String get heroUpNext => 'UP NEXT';

  @override
  String get heroYourFirstWorkout => 'YOUR FIRST WORKOUT';

  @override
  String get heroNoPlan => 'NO PLAN';

  @override
  String get heroNewWeek => 'NEW WEEK';

  @override
  String get planYourWeek => 'Plan your week';

  @override
  String get pickRoutinesForWeek => 'Pick routines for the week';

  @override
  String get quickWorkout => 'Quick workout';

  @override
  String get startNewWeek => 'Start new week';

  @override
  String nOfNDone(int completed, int total) {
    return '$completed of $total done';
  }

  @override
  String exerciseCountDuration(int count, int minutes) {
    return '$count exercises · ~$minutes min';
  }

  @override
  String get offlineStartWorkout =>
      'Starting a workout requires an internet connection';

  @override
  String get couldNotLoadExercises =>
      'Could not load exercises. Please try again.';

  @override
  String get lastSessionPrefix => 'Last: ';

  @override
  String get exercises => 'Exercises';

  @override
  String get searchExercises => 'Search exercises...';

  @override
  String get noExercisesMatchFilters => 'No exercises match your filters';

  @override
  String get yourExercisesWillAppear => 'Your exercises will appear here';

  @override
  String get clearFilters => 'Clear Filters';

  @override
  String get exerciseDetails => 'Exercise Details';

  @override
  String get failedToLoadExercise => 'Failed to load exercise';

  @override
  String get customExercise => 'Custom exercise';

  @override
  String get personalRecords => 'Personal Records';

  @override
  String get noRecordsYet => 'No records yet';

  @override
  String get deleteExercise => 'Delete Exercise';

  @override
  String deleteExerciseConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get deleting => 'Deleting...';

  @override
  String get imageStart => 'Start';

  @override
  String get imageEnd => 'End';

  @override
  String repsUnit(int count) {
    return '$count reps';
  }

  @override
  String get exerciseName => 'Exercise Name';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get nameTooShort => 'Name must be at least 2 characters';

  @override
  String get muscleGroup => 'Muscle Group';

  @override
  String get equipmentType => 'Equipment Type';

  @override
  String get selectMuscleAndEquipment =>
      'Please select a muscle group and equipment type';

  @override
  String get sessionExpired => 'Session expired. Please log in again.';

  @override
  String get description => 'Description';

  @override
  String get descriptionHint => 'Brief description of the exercise (optional)';

  @override
  String get formTips => 'Form Tips';

  @override
  String get formTipsHint => 'Form cues, one per line (optional)';

  @override
  String get formTipsHelper => 'Enter each tip on a new line';

  @override
  String get aboutSection => 'ABOUT';

  @override
  String get formTipsSection => 'FORM TIPS';

  @override
  String get finishWorkout => 'Finish Workout';

  @override
  String get completeOneSet => 'Complete at least one set to finish';

  @override
  String get addFirstExercise => 'Add your first exercise';

  @override
  String get tapButtonToStart => 'Tap the button below to get started';

  @override
  String get addExercise => 'Add Exercise';

  @override
  String get addSet => 'Add Set';

  @override
  String fillRemainingSetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
    );
    return 'Fill remaining ($_temp0)';
  }

  @override
  String get filledRemainingSets => 'Filled remaining sets';

  @override
  String get removeExerciseTitle => 'Remove Exercise?';

  @override
  String removeExerciseContent(String name) {
    return 'Remove $name and all its sets?';
  }

  @override
  String get failedToDiscardWorkout =>
      'Failed to discard workout. Please retry.';

  @override
  String get failedToSaveWorkout => 'Failed to save workout. Please retry.';

  @override
  String get workoutSavedOffline =>
      'Workout saved. Will sync when back online.';

  @override
  String get workoutSavedServerError =>
      'Server error — saved locally. Will retry automatically.';

  @override
  String get setColumnSet => 'SET';

  @override
  String get setColumnWeight => 'WEIGHT';

  @override
  String get setColumnReps => 'REPS';

  @override
  String get setColumnType => 'TYPE';

  @override
  String setDeleted(int number) {
    return 'Set $number deleted';
  }

  @override
  String get discardWorkoutTitle => 'Discard Workout?';

  @override
  String discardWorkoutContent(String duration) {
    return 'You\'ve been on the path $duration. Discard now and the work is gone.';
  }

  @override
  String get finishWorkoutTitle => 'Seal this session?';

  @override
  String incompleteSetsWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count incomplete sets',
      one: 'You have 1 incomplete set',
    );
    return '$_temp0';
  }

  @override
  String get addNotesHint => 'Add notes (optional)';

  @override
  String get keepGoing => 'Keep Going';

  @override
  String get saveAndFinish => 'Save & Finish';

  @override
  String get resumeWorkoutTitle => 'Resume workout?';

  @override
  String get resumeWorkoutStaleTitle => 'Pick up where you left off?';

  @override
  String workoutInProgress(String name) {
    return '\"$name\" is still in progress.';
  }

  @override
  String workoutInterrupted(String age) {
    return 'Was interrupted $age.';
  }

  @override
  String get resumeAnyway => 'Resume anyway';

  @override
  String get restTimerLabel => 'Rest';

  @override
  String restTimerRemaining(String time) {
    return 'Rest timer: $time remaining';
  }

  @override
  String get subtract30Semantics => 'Subtract 30 seconds';

  @override
  String get add30Semantics => 'Add 30 seconds';

  @override
  String get skipRestSemantics => 'Skip rest timer';

  @override
  String get lessThanAnHourAgo => 'less than an hour ago';

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String yesterdayAt(String time) {
    return 'yesterday at $time';
  }

  @override
  String weekdayAt(String weekday, String time) {
    return '$weekday at $time';
  }

  @override
  String get history => 'History';

  @override
  String get failedToLoadHistory => 'Failed to load history';

  @override
  String get noWorkoutsYet => 'No workouts yet';

  @override
  String get completedWorkoutsAppear =>
      'Your completed workouts will appear here';

  @override
  String get startFirstWorkout => 'Start your first workout';

  @override
  String get failedToLoadWorkout => 'Failed to load workout';

  @override
  String get workout => 'Workout';

  @override
  String get exerciseGeneric => 'Exercise';

  @override
  String get notes => 'Notes';

  @override
  String get addNote => 'Add a note';

  @override
  String get workoutDetailTotalVolumeLabel => 'Total volume';

  @override
  String workoutDetailTotalVolumeValue(String volume) {
    return '$volume';
  }

  @override
  String get routines => 'Routines';

  @override
  String get failedToLoadRoutines => 'Failed to load routines';

  @override
  String get myRoutinesSection => 'MY ROUTINES';

  @override
  String get starterRoutinesSection => 'STARTER ROUTINES';

  @override
  String get hintRoutineLongPress => 'Press and hold to edit';

  @override
  String get routinesEmptyTitle => 'No routines yet';

  @override
  String get routinesEmptyBody =>
      'Plan a workout sequence once and reuse it every session.';

  @override
  String get routinesEmptyCta => 'Create routine';

  @override
  String get createRoutine => 'Create Routine';

  @override
  String get editRoutine => 'Edit Routine';

  @override
  String get routineName => 'Routine name';

  @override
  String get failedToSaveRoutine => 'Failed to save routine. Please retry.';

  @override
  String get setsLabel => 'Sets';

  @override
  String get restLabel => 'Rest';

  @override
  String get duplicateAndEdit => 'Duplicate and Edit';

  @override
  String get deleteRoutine => 'Delete Routine';

  @override
  String deleteRoutineConfirm(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String exercisesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
    );
    return '$_temp0';
  }

  @override
  String get profile => 'Profile';

  @override
  String get gymUser => 'Gym User';

  @override
  String get editDisplayName => 'Edit Display Name';

  @override
  String get enterYourName => 'Enter your name';

  @override
  String get workouts => 'Workouts';

  @override
  String get memberSince => 'Member since';

  @override
  String get weightUnit => 'Weight Unit';

  @override
  String get weeklyGoal => 'Weekly Goal';

  @override
  String get dataManagement => 'DATA MANAGEMENT';

  @override
  String get manageData => 'Manage Data';

  @override
  String get legal => 'LEGAL';

  @override
  String get sendCrashReports => 'Send crash reports';

  @override
  String get crashReportsSubtitle =>
      'Help improve RepSaga by sending anonymous crash data.';

  @override
  String get logOutConfirm => 'Are you sure you want to log out?';

  @override
  String get manageDataTitle => 'Manage Data';

  @override
  String get deleteWorkoutHistory => 'Delete Workout History';

  @override
  String workoutsWillBeRemoved(String count) {
    return '$count workouts will be removed';
  }

  @override
  String get resetAllAccountData => 'Reset All Account Data';

  @override
  String get resetAllSubtitle => 'Removes everything. Permanent.';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountSubtitle =>
      'Permanently delete your account and all data';

  @override
  String get deleteAllHistoryTitle => 'Delete all workout history?';

  @override
  String deleteAllHistoryContent(int count) {
    return 'This will permanently delete all $count workouts and cannot be undone.';
  }

  @override
  String get deleteHistoryButton => 'Delete History';

  @override
  String get areYouSure => 'Are you sure?';

  @override
  String get yesDelete => 'Yes, Delete';

  @override
  String get historyCleared => 'Workout history cleared';

  @override
  String failedToClearHistory(String message) {
    return 'Failed to clear history: $message';
  }

  @override
  String get resetAccountData => 'Reset Account Data';

  @override
  String get resetAccountWarning =>
      'This will permanently delete all workouts and personal records. Your routines and custom exercises will be kept. There is no undo.';

  @override
  String get typeResetToConfirm => 'Type RESET to confirm';

  @override
  String get resetAccountButton => 'Reset Account';

  @override
  String get accountDataReset => 'Account data reset';

  @override
  String failedToResetData(String message) {
    return 'Failed to reset data: $message';
  }

  @override
  String get deleteAccountWarning =>
      'This will permanently delete your account, all your workouts, personal records, routines, and custom exercises. This cannot be undone.';

  @override
  String get typeDeleteToConfirm => 'Type DELETE to confirm';

  @override
  String get deleteAccountButton => 'Delete Account';

  @override
  String failedToDeleteAccount(String message) {
    return 'Failed to delete account: $message';
  }

  @override
  String get prsRoutinesKept =>
      'Your personal records and routines will be kept.';

  @override
  String get workoutHistorySection => 'WORKOUT HISTORY';

  @override
  String get yourDataSection => 'YOUR DATA';

  @override
  String get exportMyData => 'Export my data';

  @override
  String get exportMyDataSubtitle =>
      'Download a JSON file of your account data.';

  @override
  String get dataExportPreparing => 'Preparing your data export…';

  @override
  String get dataExportSuccess => 'Data export ready';

  @override
  String dataExportFailed(String message) {
    return 'Failed to export data: $message';
  }

  @override
  String get dangerSection => 'DANGER';

  @override
  String get privacySection => 'PRIVACY';

  @override
  String get prsLabel => 'PRs';

  @override
  String perWeekLabel(int count) {
    return '${count}x per week';
  }

  @override
  String get frequencyQuestion =>
      'How many times per week do you want to train?';

  @override
  String get profileBodyweightLabel => 'Body weight';

  @override
  String get profileBodyweightNotSet => 'Not set';

  @override
  String get profileBodyweightHelper =>
      'Used to compute XP for bodyweight exercises like pull-ups, dips, push-ups.';

  @override
  String profileBodyweightInvalidRange(String min, String max, String unit) {
    return 'Enter a value between $min and $max $unit';
  }

  @override
  String get bodyweightPromptTitle => 'Set your body weight for accurate XP';

  @override
  String get bodyweightPromptBody =>
      'Bodyweight exercises like pull-ups and dips count your weight as part of the load.';

  @override
  String get bodyweightPromptSetNow => 'Set now';

  @override
  String get bodyweightPromptSkip => 'Skip';

  @override
  String get pleaseTryAgain => 'Please try again.';

  @override
  String get personalRecordsTitle => 'Personal Records';

  @override
  String get failedToLoadRecords => 'Failed to load records';

  @override
  String get noRecordsYetTitle => 'No Records Yet';

  @override
  String get completeWorkoutToTrack =>
      'Complete a workout to start tracking records';

  @override
  String get startWorkout => 'Start Workout';

  @override
  String get newPrHeading => 'NEW PR';

  @override
  String get firstWorkoutComplete => 'First Workout Complete!';

  @override
  String get startingBenchmarks => 'These are your starting benchmarks';

  @override
  String get unknownExercise => 'Unknown Exercise';

  @override
  String get thisWeeksPlan => 'This Week\'s Plan';

  @override
  String get moreOptions => 'More options';

  @override
  String get autoFill => 'Auto-fill';

  @override
  String get clearWeek => 'Clear Week';

  @override
  String get addRoutine => 'Add Routine';

  @override
  String plannedReadyToGo(int count, int total) {
    return '$count/$total planned — ready to go';
  }

  @override
  String plannedThisWeek(int count, int total) {
    return '$count/$total planned this week';
  }

  @override
  String get noRoutinesPlanned => 'No routines planned this week';

  @override
  String get addRoutines => 'Add Routines';

  @override
  String get replacePlanTitle => 'Replace current plan?';

  @override
  String get replacePlanContent =>
      'Auto-fill will replace your current plan with your most-used routines.';

  @override
  String get clearWeekTitle => 'Clear Week';

  @override
  String get clearWeekContent => 'Start fresh this week?';

  @override
  String get routineRemoved => 'Routine removed';

  @override
  String get unknownRoutine => 'Unknown Routine';

  @override
  String get addRoutinesSheet => 'Add Routines';

  @override
  String get createMoreRoutines => 'Create more routines to add them here.';

  @override
  String addCountRoutines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ADD $count ROUTINES',
      one: 'ADD 1 ROUTINE',
    );
    return '$_temp0';
  }

  @override
  String get createNewRoutine => 'Create new routine';

  @override
  String get savedConfirmation => 'Saved';

  @override
  String get copyFromPreviousSet => 'Copy from previous set';

  @override
  String get weekComplete => 'WEEK COMPLETE';

  @override
  String get thisWeek => 'THIS WEEK';

  @override
  String get newWeekLink => 'NEW WEEK';

  @override
  String sessionsCount(int count) {
    return '$count sessions';
  }

  @override
  String prsCount(int count) {
    return '$count PRs';
  }

  @override
  String addToPlanPrompt(String name) {
    return '$name isn\'t in your plan yet. Add it?';
  }

  @override
  String get syncFailureSingular => 'Workout couldn\'t sync';

  @override
  String syncFailurePlural(int count) {
    return '$count workouts couldn\'t sync';
  }

  @override
  String get savedLocallyRetry => 'Saved locally. Retry or dismiss.';

  @override
  String get offlineRetryHint => 'You\'re offline — retry when back online';

  @override
  String get pendingSyncTitle => 'Pending Sync';

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get allSynced => 'All synced!';

  @override
  String get syncedSuccessfully => 'Synced successfully.';

  @override
  String get pendingActionSaveWorkout => 'Save workout';

  @override
  String get pendingActionUpdateRecords => 'Update records';

  @override
  String get pendingActionMarkComplete => 'Mark routine complete';

  @override
  String queuedAt(String time) {
    return 'Queued at $time';
  }

  @override
  String retryCount(int count) {
    return '$count retries';
  }

  @override
  String get syncErrorRetryGeneric =>
      'Couldn\'t sync right now. We\'ll retry shortly.';

  @override
  String get syncErrorOffline =>
      'No connection. Your data will sync when you\'re back online.';

  @override
  String get syncErrorSessionExpired => 'Session expired. Please log in again.';

  @override
  String get syncErrorUnknown => 'Something went wrong. We\'ll retry shortly.';

  @override
  String get syncErrorStructuralBody =>
      'We couldn\'t send this — please contact support.';

  @override
  String get syncDismissAction => 'Dismiss';

  @override
  String get pendingSyncBadgeSingular => '1 workout pending sync';

  @override
  String pendingSyncBadgePlural(int count) {
    return '$count workouts pending sync';
  }

  @override
  String pendingSyncBadgeSemantics(String label) {
    return '$label. Tap to manage.';
  }

  @override
  String get noExercisesFound => 'No exercises found';

  @override
  String get failedToLoadExercises => 'Failed to load exercises';

  @override
  String get durationLessThanOneMin => '< 1m';

  @override
  String get enterWeight => 'Enter weight';

  @override
  String get ok => 'OK';

  @override
  String get enterReps => 'Enter reps';

  @override
  String get failedToLoadDocument => 'Failed to load document';

  @override
  String get discardWorkout => 'Discard workout';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get swapExercise => 'Swap exercise';

  @override
  String get removeExercise => 'Remove exercise';

  @override
  String swapExerciseConfirmTitle(String newExercise) {
    return 'Swap to $newExercise?';
  }

  @override
  String swapExerciseConfirmBody(
    int count,
    String newExercise,
    String oldExercise,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sets',
      one: 'set',
    );
    return 'Swapping from $oldExercise: your $count logged $_temp0 will move to $newExercise\'s PR history.';
  }

  @override
  String get swapExerciseConfirmAction => 'Swap';

  @override
  String addExerciseUndo(String name) {
    return '$name added';
  }

  @override
  String get last30Days => '30d';

  @override
  String get last90Days => '90d';

  @override
  String get allTime => 'All time';

  @override
  String switchMetricTo(String metric) {
    return 'Switch metric to $metric';
  }

  @override
  String get couldNotLoadProgress => 'Could not load progress';

  @override
  String get logFirstSetToTrack => 'Log your first set to start tracking';

  @override
  String get chartMetricE1rm => 'e1RM';

  @override
  String get chartMetricWeight => 'Weight';

  @override
  String get chartWindowDays30 => '30 days';

  @override
  String get chartWindowDays90 => '90 days';

  @override
  String get chartWindowAllTime => 'all time';

  @override
  String workoutsLoggedKeepGoing(int count) {
    return '$count workouts logged — keep going';
  }

  @override
  String get oneWorkoutLoggedKeepGoing => '1 workout logged — keep going';

  @override
  String holdingSteadyAt(String weight, String unit) {
    return 'Holding steady at $weight $unit';
  }

  @override
  String trendUp(String weight, String unit, String window) {
    return 'Up $weight $unit in $window';
  }

  @override
  String trendDown(String weight, String unit, String window) {
    return 'Down $weight $unit in $window';
  }

  @override
  String prMarkerAt(String weight, String unit) {
    return 'PR marker at $weight $unit';
  }

  @override
  String setNumberSemantics(int number, String type) {
    return 'Set $number. Long press to change type: $type';
  }

  @override
  String setNumberCopySemantics(int number, String type) {
    return 'Set $number. Tap to copy previous set. Long press to change type: $type';
  }

  @override
  String get tooltipCopyLastSetAndChangeType =>
      'Tap: copy last set\nHold: change type';

  @override
  String get tooltipChangeType => 'Hold: change type';

  @override
  String get setCompleted => 'Set completed';

  @override
  String get markSetAsDone => 'Mark set as done';

  @override
  String get markSetAsDonePredictedPr => 'Mark set as done — predicted record';

  @override
  String get reorderExercisesTooltip => 'Reorder exercises';

  @override
  String get exitReorderModeTooltip => 'Exit reorder mode';

  @override
  String exerciseSemanticsLabel(String name) {
    return 'Exercise: $name. Tap for details.';
  }

  @override
  String get fillRemainingSetsSemantics =>
      'Fill all uncompleted sets with last completed values';

  @override
  String get addExerciseToWorkoutSemantics => 'Add exercise to workout';

  @override
  String get searchExercisesToAddSemantics => 'Search exercises to add';

  @override
  String addExerciseSemantics(String name) {
    return 'Add $name';
  }

  @override
  String get setTypeAbbrWorking => 'W';

  @override
  String get setTypeAbbrWarmup => 'WU';

  @override
  String get setTypeAbbrDropset => 'D';

  @override
  String get setTypeAbbrFailure => 'F';

  @override
  String get setTypeAbbrWarmupShort => 'Wu';

  @override
  String lastSessionSemantics(String name, String date) {
    return 'Last session: $name, $date';
  }

  @override
  String get searchExercisesSemantics => 'Search exercises';

  @override
  String exerciseItemSemantics(String name) {
    return 'Exercise: $name';
  }

  @override
  String get muscleGroupSemanticsPrefix => 'Muscle group';

  @override
  String get equipmentTypeSemanticsPrefix => 'Equipment type';

  @override
  String get deleteExerciseSemantics => 'Delete exercise';

  @override
  String get exerciseNameDuplicate =>
      'An exercise with this name already exists';

  @override
  String daysAgoShort(int count) {
    return '${count}d ago';
  }

  @override
  String weeksAgoShort(int count) {
    return '${count}w ago';
  }

  @override
  String monthsAgoShort(int count) {
    return '${count}mo ago';
  }

  @override
  String get routineNamePushDay => 'Push Day';

  @override
  String get routineNamePullDay => 'Pull Day';

  @override
  String get routineNameLegDay => 'Leg Day';

  @override
  String get routineNameFullBody => 'Full Body';

  @override
  String get routineNameUpperLowerUpper => 'Upper/Lower — Upper';

  @override
  String get routineNameUpperLowerLower => 'Upper/Lower — Lower';

  @override
  String get routineNameFiveByFiveStrength => '5x5 Strength';

  @override
  String get routineNameFullBodyBeginner => 'Full Body Beginner';

  @override
  String get routineNameArmsAndAbs => 'Arms & Abs';

  @override
  String get preferences => 'PREFERENCES';

  @override
  String get language => 'Language';

  @override
  String get sagaIntroStep1Title => 'YOUR TRAINING IS YOUR CHARACTER';

  @override
  String get sagaIntroStep1Body =>
      'Every set you complete shapes who you become. Lift, track, level up.';

  @override
  String get sagaIntroStep2Title => 'XP FROM EVERY SET, PR, QUEST';

  @override
  String get sagaIntroStep2Body =>
      'Volume, intensity, personal records and weekly quests all grant XP.';

  @override
  String sagaIntroStep3Title(int level, String rank) {
    return 'LVL $level — $rank';
  }

  @override
  String get sagaIntroStep3Body =>
      'Your journey begins here. Keep training to climb ranks.';

  @override
  String get sagaIntroNext => 'NEXT';

  @override
  String get sagaIntroBegin => 'BEGIN';

  @override
  String get sagaIntroSkip => 'Skip';

  @override
  String get sagaRankRookie => 'ROOKIE';

  @override
  String get sagaRankIron => 'IRON';

  @override
  String get sagaRankCopper => 'COPPER';

  @override
  String get sagaRankSilver => 'SILVER';

  @override
  String get sagaRankGold => 'GOLD';

  @override
  String get sagaRankPlatinum => 'PLATINUM';

  @override
  String get sagaRankDiamond => 'DIAMOND';

  @override
  String get rankWord => 'RANK';

  @override
  String levelUpHeading(int level) {
    return 'LEVEL $level';
  }

  @override
  String firstAwakeningHeading(String bodyPart) {
    return '$bodyPart AWAKENS';
  }

  @override
  String titleUnlockRankLabel(String bodyPart, int rank) {
    return '$bodyPart · RANK $rank TITLE';
  }

  @override
  String titleUnlockCharacterLevelLabel(int level) {
    return 'CHARACTER LEVEL $level';
  }

  @override
  String get titleUnlockCrossBuildLabel => 'DISTINCTION TITLE';

  @override
  String get equipTitleButton => 'EQUIP TITLE';

  @override
  String get equippedLabel => 'EQUIPPED';

  @override
  String get prChipLabel => 'PR';

  @override
  String get finishButtonLabel => 'FINISH';

  @override
  String get finishWorkoutDisabledHint =>
      'Complete at least one set to finish.';

  @override
  String get addExerciseFabLabel => 'Add exercise';

  @override
  String celebrationOverflowLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more rank-ups — open Saga',
      one: '1 more rank-up — open Saga',
    );
    return '$_temp0';
  }

  @override
  String get celebrationOverflowTapHint => 'Tap to continue';

  @override
  String get titlesScreenTitle => 'Titles';

  @override
  String get titlesEmptyState =>
      'Earn your first title by ranking up a body part.';

  @override
  String titlesProgressLabel(int earned, int total) {
    return '$earned of $total earned';
  }

  @override
  String titlesRowRankThreshold(int rank) {
    return 'Rank $rank';
  }

  @override
  String titlesRowCharacterLevel(int level) {
    return 'Level $level';
  }

  @override
  String get titlesRowCrossBuild => 'Distinction';

  @override
  String get titlesSectionCharacterLevel => 'CHARACTER LEVEL';

  @override
  String get titlesSectionCrossBuild => 'DISTINCTION';

  @override
  String get titlesRegionEquipped => 'Equipped';

  @override
  String get titlesRegionEarned => 'Earned';

  @override
  String get titlesRegionNext => 'Next';

  @override
  String get titlesRowEquipCta => 'Equip';

  @override
  String get titlesEquippedTag => 'Active';

  @override
  String get titlesCharacterLabel => 'Character';

  @override
  String titlesCounterPill(int earned, int total) {
    return '$earned / $total earned';
  }

  @override
  String titlesNextSubBodyPart(String bodyPart, int remaining) {
    return '$bodyPart · $remaining ranks to go';
  }

  @override
  String titlesNextSubBodyPartOne(String bodyPart) {
    return '$bodyPart · 1 rank to go';
  }

  @override
  String titlesNextSubCharacter(int remaining) {
    return 'Character · $remaining levels to go';
  }

  @override
  String get titlesNextSubCharacterOne => 'Character · 1 level to go';

  @override
  String get titlesCrossBuildEspecial => 'Special';

  @override
  String titlesCrossBuildBottleneck(String bodyPart) {
    return '◆ 1 rank to go in $bodyPart';
  }

  @override
  String get classTaglineInitiate => 'the path begins';

  @override
  String get classTaglineBerserker => 'the fury answers';

  @override
  String get classTaglineBulwark => 'the pillar moves';

  @override
  String get classTaglineSentinel => 'the watcher wakes';

  @override
  String get classTaglinePathfinder => 'the ground holds';

  @override
  String get classTaglineAtlas => 'the shoulder carries';

  @override
  String get classTaglineAnchor => 'the line holds';

  @override
  String get classTaglineAscendant => 'the balance was conquered';

  @override
  String get classChangeOverlaySubtitle => 'Your journey has earned a name.';

  @override
  String classChangePreviousLabel(String className) {
    return 'before: $className';
  }

  @override
  String classChangeOverflowMore(int count) {
    return '+$count more class change';
  }

  @override
  String crossBuildHintBroadShouldered(int gap, String muscleName) {
    return 'Master the upper pillars — chest, back, and shoulders above rank 30, with clear dominance over the lower body. $gap more rank in $muscleName.';
  }

  @override
  String crossBuildHintPillarWalker(int gap) {
    return 'Your legs must speak louder than your arms. $gap more rank in legs.';
  }

  @override
  String crossBuildHintEvenHanded(int gap, String muscleName) {
    return 'Every muscle at the same level — no weak link. $gap more rank in $muscleName.';
  }

  @override
  String crossBuildHintIronBound(int gap, String muscleName) {
    return 'Chest, back, legs — the three pillars above rank 60. $gap more rank in $muscleName.';
  }

  @override
  String crossBuildHintSagaForged(int gap, String muscleName) {
    return 'The end of the journey starts here — every attribute above rank 60. $gap more rank in $muscleName.';
  }

  @override
  String get crossBuildHintSatisfied =>
      'All conditions met — predicate satisfied.';

  @override
  String get title_chest_r5_initiate_of_the_forge_name =>
      'Initiate of the Forge';

  @override
  String get title_chest_r5_initiate_of_the_forge_flavor =>
      'First sparks struck against iron.';

  @override
  String get title_chest_r10_plate_bearer_name => 'Plate-Bearer';

  @override
  String get title_chest_r10_plate_bearer_flavor =>
      'The bar trusts your collarbone now.';

  @override
  String get title_chest_r15_forge_marked_name => 'Forge-Marked';

  @override
  String get title_chest_r15_forge_marked_flavor =>
      'Heat lives where your sternum meets the iron.';

  @override
  String get title_chest_r20_iron_chested_name => 'Iron-Chested';

  @override
  String get title_chest_r20_iron_chested_flavor =>
      'Plate after plate, the rib-cage answers.';

  @override
  String get title_chest_r25_anvil_heart_name => 'Anvil-Heart';

  @override
  String get title_chest_r25_anvil_heart_flavor => 'Hammered, never bent.';

  @override
  String get title_chest_r30_forge_born_name => 'Forge-Born';

  @override
  String get title_chest_r30_forge_born_flavor =>
      'Older lifters look for the cracks. There aren\'t any.';

  @override
  String get title_chest_r40_bulwark_chested_name => 'Bulwark-Chested';

  @override
  String get title_chest_r40_bulwark_chested_flavor =>
      'Walls do not flex. Neither do you.';

  @override
  String get title_chest_r50_forge_plated_name => 'Forge-Plated';

  @override
  String get title_chest_r50_forge_plated_flavor =>
      'Armour the bar wears down to your shape.';

  @override
  String get title_chest_r60_anvil_forged_name => 'Anvil-Forged';

  @override
  String get title_chest_r60_anvil_forged_flavor =>
      'Ten thousand reps, one shape.';

  @override
  String get title_chest_r70_forge_heart_name => 'Forge-Heart';

  @override
  String get title_chest_r70_forge_heart_flavor =>
      'The fire kept burning where most went out.';

  @override
  String get title_chest_r80_heart_of_forge_name => 'Heart of the Forge';

  @override
  String get title_chest_r80_heart_of_forge_flavor =>
      'Without you, the steel goes cold.';

  @override
  String get title_chest_r90_forge_untouched_name => 'Forge-Untouched';

  @override
  String get title_chest_r90_forge_untouched_flavor =>
      'Heat passes through. Nothing marks you.';

  @override
  String get title_chest_r99_the_anvil_name => 'The Anvil';

  @override
  String get title_chest_r99_the_anvil_flavor =>
      'Every plate in this gym took its shape from you.';

  @override
  String get title_back_r5_lattice_touched_name => 'Lattice-Touched';

  @override
  String get title_back_r5_lattice_touched_flavor =>
      'Wings begin under the skin first.';

  @override
  String get title_back_r10_wing_marked_name => 'Wing-Marked';

  @override
  String get title_back_r10_wing_marked_flavor =>
      'The shadow on the floor is wider than yesterday.';

  @override
  String get title_back_r15_rope_hauler_name => 'Rope-Hauler';

  @override
  String get title_back_r15_rope_hauler_flavor =>
      'Whatever\'s hanging, you\'re pulling.';

  @override
  String get title_back_r20_lat_crowned_name => 'Lat-Crowned';

  @override
  String get title_back_r20_lat_crowned_flavor =>
      'Two slabs hold up the silhouette.';

  @override
  String get title_back_r25_talon_backed_name => 'Talon-Backed';

  @override
  String get title_back_r25_talon_backed_flavor =>
      'The bar comes down because you said so.';

  @override
  String get title_back_r30_wing_spread_name => 'Wing-Spread';

  @override
  String get title_back_r30_wing_spread_flavor => 'Doorways notice you now.';

  @override
  String get title_back_r40_lattice_hauled_name => 'Lattice-Hauled';

  @override
  String get title_back_r40_lattice_hauled_flavor =>
      'Iron rises and the lattice answers.';

  @override
  String get title_back_r50_wing_crowned_name => 'Wing-Crowned';

  @override
  String get title_back_r50_wing_crowned_flavor =>
      'The bar bows. The wings rise.';

  @override
  String get title_back_r60_lattice_spread_name => 'Lattice-Spread';

  @override
  String get title_back_r60_lattice_spread_flavor =>
      'Cathedral rafters built one rep at a time.';

  @override
  String get title_back_r70_wing_storm_name => 'Wing-Storm';

  @override
  String get title_back_r70_wing_storm_flavor => 'Air moves when you do.';

  @override
  String get title_back_r80_wing_of_storms_name => 'Wing of Storms';

  @override
  String get title_back_r80_wing_of_storms_flavor =>
      'The kind of back weather forms around.';

  @override
  String get title_back_r90_sky_lattice_name => 'Sky-Lattice';

  @override
  String get title_back_r90_sky_lattice_flavor =>
      'What holds up the heavens, on you.';

  @override
  String get title_back_r99_the_lattice_name => 'The Lattice';

  @override
  String get title_back_r99_the_lattice_flavor =>
      'Every cable in the gym answers to you.';

  @override
  String get title_legs_r5_ground_walker_name => 'Ground-Walker';

  @override
  String get title_legs_r5_ground_walker_flavor =>
      'The earth knows your weight.';

  @override
  String get title_legs_r10_stone_stepper_name => 'Stone-Stepper';

  @override
  String get title_legs_r10_stone_stepper_flavor =>
      'Boulders move when you sit down.';

  @override
  String get title_legs_r15_pillar_apprentice_name => 'Pillar-Apprentice';

  @override
  String get title_legs_r15_pillar_apprentice_flavor =>
      'The columns are learning your name.';

  @override
  String get title_legs_r20_pillar_walker_name => 'Pillar-Walker';

  @override
  String get title_legs_r20_pillar_walker_flavor =>
      'Two columns where there used to be limbs.';

  @override
  String get title_legs_r25_quarry_strider_name => 'Quarry-Strider';

  @override
  String get title_legs_r25_quarry_strider_flavor =>
      'Stone is just where you start.';

  @override
  String get title_legs_r30_mountain_strider_name => 'Mountain-Strider';

  @override
  String get title_legs_r30_mountain_strider_flavor =>
      'Up is just another set.';

  @override
  String get title_legs_r40_stone_strider_name => 'Stone-Strider';

  @override
  String get title_legs_r40_stone_strider_flavor =>
      'The ground splits before it stops you.';

  @override
  String get title_legs_r50_mountain_footed_name => 'Mountain-Footed';

  @override
  String get title_legs_r50_mountain_footed_flavor =>
      'Foundations shift around your stance.';

  @override
  String get title_legs_r60_mountain_rooted_name => 'Mountain-Rooted';

  @override
  String get title_legs_r60_mountain_rooted_flavor =>
      'Storms break before they move you.';

  @override
  String get title_legs_r70_pillar_footed_name => 'Pillar-Footed';

  @override
  String get title_legs_r70_pillar_footed_flavor =>
      'Architecture\'s job, on a body.';

  @override
  String get title_legs_r80_pillar_of_storms_name => 'Pillar of Storms';

  @override
  String get title_legs_r80_pillar_of_storms_flavor =>
      'Wind shears around. You stay.';

  @override
  String get title_legs_r90_mountain_untouched_name => 'Mountain-Untouched';

  @override
  String get title_legs_r90_mountain_untouched_flavor =>
      'Erosion takes a million years. You take one more set.';

  @override
  String get title_legs_r99_the_pillar_name => 'The Pillar';

  @override
  String get title_legs_r99_the_pillar_flavor =>
      'Take you out and the ceiling falls.';

  @override
  String get title_shoulders_r5_burden_tester_name => 'Burden-Tester';

  @override
  String get title_shoulders_r5_burden_tester_flavor =>
      'First weight overhead — the sky noticed.';

  @override
  String get title_shoulders_r10_yoke_apprentice_name => 'Yoke-Apprentice';

  @override
  String get title_shoulders_r10_yoke_apprentice_flavor =>
      'Iron rests on you and stays put.';

  @override
  String get title_shoulders_r15_sky_reach_name => 'Sky-Reach';

  @override
  String get title_shoulders_r15_sky_reach_flavor =>
      'Arms find ceiling without thinking.';

  @override
  String get title_shoulders_r20_atlas_touched_name => 'Atlas-Touched';

  @override
  String get title_shoulders_r20_atlas_touched_flavor =>
      'Old myths recognise the shape.';

  @override
  String get title_shoulders_r25_sky_vaulter_name => 'Sky-Vaulter';

  @override
  String get title_shoulders_r25_sky_vaulter_flavor =>
      'Up is where the bar lives.';

  @override
  String get title_shoulders_r30_yoke_crowned_name => 'Yoke-Crowned';

  @override
  String get title_shoulders_r30_yoke_crowned_flavor =>
      'What sits on you stays decoration.';

  @override
  String get title_shoulders_r40_atlas_carried_name => 'Atlas-Carried';

  @override
  String get title_shoulders_r40_atlas_carried_flavor =>
      'The world is not as heavy as it claims.';

  @override
  String get title_shoulders_r50_sky_yoked_name => 'Sky-Yoked';

  @override
  String get title_shoulders_r50_sky_yoked_flavor =>
      'The horizon hangs from your traps.';

  @override
  String get title_shoulders_r60_sky_vaulted_name => 'Sky-Vaulted';

  @override
  String get title_shoulders_r60_sky_vaulted_flavor =>
      'Arms make space where there wasn\'t any.';

  @override
  String get title_shoulders_r70_sky_held_name => 'Sky-Held';

  @override
  String get title_shoulders_r70_sky_held_flavor =>
      'Drop you and the clouds fall.';

  @override
  String get title_shoulders_r80_sky_sundered_name => 'Sky-Sundered';

  @override
  String get title_shoulders_r80_sky_sundered_flavor =>
      'What you press splits the dome.';

  @override
  String get title_shoulders_r90_sky_untouched_name => 'Sky-Untouched';

  @override
  String get title_shoulders_r90_sky_untouched_flavor =>
      'Storms pass overhead. You don\'t bow.';

  @override
  String get title_shoulders_r99_the_atlas_name => 'The Atlas';

  @override
  String get title_shoulders_r99_the_atlas_flavor =>
      'All the weight of the heavens. Light work.';

  @override
  String get title_arms_r5_vein_stirrer_name => 'Vein-Stirrer';

  @override
  String get title_arms_r5_vein_stirrer_flavor =>
      'The blood remembers the curl.';

  @override
  String get title_arms_r10_iron_fingered_name => 'Iron-Fingered';

  @override
  String get title_arms_r10_iron_fingered_flavor => 'What you grip, you keep.';

  @override
  String get title_arms_r15_sinew_drawn_name => 'Sinew-Drawn';

  @override
  String get title_arms_r15_sinew_drawn_flavor =>
      'Cables, cords, ropes — they answer.';

  @override
  String get title_arms_r20_marrow_cleaver_name => 'Marrow-Cleaver';

  @override
  String get title_arms_r20_marrow_cleaver_flavor =>
      'Each rep cuts deeper than the last.';

  @override
  String get title_arms_r25_steel_sleeved_name => 'Steel-Sleeved';

  @override
  String get title_arms_r25_steel_sleeved_flavor =>
      'Sleeves can\'t keep up. Stop trying.';

  @override
  String get title_arms_r30_sinew_sworn_name => 'Sinew-Sworn';

  @override
  String get title_arms_r30_sinew_sworn_flavor =>
      'The fibres don\'t quit before you do.';

  @override
  String get title_arms_r40_iron_knuckled_name => 'Iron-Knuckled';

  @override
  String get title_arms_r40_iron_knuckled_flavor => 'The handle bends first.';

  @override
  String get title_arms_r50_steel_forged_name => 'Steel-Forged';

  @override
  String get title_arms_r50_steel_forged_flavor =>
      'Hammered into the shape that lifts.';

  @override
  String get title_arms_r60_sinew_bound_name => 'Sinew-Bound';

  @override
  String get title_arms_r60_sinew_bound_flavor =>
      'Cables ran out of slack years ago.';

  @override
  String get title_arms_r70_iron_sleeved_name => 'Iron-Sleeved';

  @override
  String get title_arms_r70_iron_sleeved_flavor =>
      'Knuckle to shoulder, all of it carries.';

  @override
  String get title_arms_r80_sinew_of_storms_name => 'Sinew of Storms';

  @override
  String get title_arms_r80_sinew_of_storms_flavor =>
      'Lightning learns its shape from yours.';

  @override
  String get title_arms_r90_iron_untouched_name => 'Iron-Untouched';

  @override
  String get title_arms_r90_iron_untouched_flavor =>
      'Plate slides on. Plate slides off. The arm doesn\'t move.';

  @override
  String get title_arms_r99_the_sinew_name => 'The Sinew';

  @override
  String get title_arms_r99_the_sinew_flavor =>
      'Whatever needs lifting in this gym, you lift it.';

  @override
  String get title_core_r5_spine_tested_name => 'Spine-Tested';

  @override
  String get title_core_r5_spine_tested_flavor =>
      'First brace held — bar stayed level.';

  @override
  String get title_core_r10_core_forged_name => 'Core-Forged';

  @override
  String get title_core_r10_core_forged_flavor =>
      'Mid-line locked, ribs to hips.';

  @override
  String get title_core_r15_pillar_spined_name => 'Pillar-Spined';

  @override
  String get title_core_r15_pillar_spined_flavor =>
      'The bar can lean. You don\'t.';

  @override
  String get title_core_r20_iron_belted_name => 'Iron-Belted';

  @override
  String get title_core_r20_iron_belted_flavor =>
      'Belt\'s a formality at this point.';

  @override
  String get title_core_r25_stonewall_name => 'Stonewall';

  @override
  String get title_core_r25_stonewall_flavor => 'Air goes in. Force comes out.';

  @override
  String get title_core_r30_diamond_spine_name => 'Diamond-Spine';

  @override
  String get title_core_r30_diamond_spine_flavor =>
      'Compressed enough times, things turn to gem.';

  @override
  String get title_core_r40_anchor_belted_name => 'Anchor-Belted';

  @override
  String get title_core_r40_anchor_belted_flavor =>
      'Whatever the load, the trunk holds.';

  @override
  String get title_core_r50_stone_cored_name => 'Stone-Cored';

  @override
  String get title_core_r50_stone_cored_flavor => 'Hit the centre. Hit a wall.';

  @override
  String get title_core_r60_marrow_carved_name => 'Marrow-Carved';

  @override
  String get title_core_r60_marrow_carved_flavor =>
      'Each rep cut a notch into bone.';

  @override
  String get title_core_r70_stone_spined_name => 'Stone-Spined';

  @override
  String get title_core_r70_stone_spined_flavor =>
      'The vertebrae stack like masonry.';

  @override
  String get title_core_r80_spine_of_storms_name => 'Spine of Storms';

  @override
  String get title_core_r80_spine_of_storms_flavor =>
      'Wind through trees. Trunk doesn\'t move.';

  @override
  String get title_core_r90_marrow_untouched_name => 'Marrow-Untouched';

  @override
  String get title_core_r90_marrow_untouched_flavor =>
      'Whatever cracks the body, it stops at the centre.';

  @override
  String get title_core_r99_the_spine_name => 'The Spine';

  @override
  String get title_core_r99_the_spine_flavor =>
      'Hold the bar like a chapel beam.';

  @override
  String get title_wanderer_name => 'Wanderer';

  @override
  String get title_wanderer_flavor =>
      'The first milestone is behind you. The map opens.';

  @override
  String get title_path_trodden_name => 'Path-Trodden';

  @override
  String get title_path_trodden_flavor =>
      'Twenty-five levels in. The road knows your weight.';

  @override
  String get title_path_sworn_name => 'Path-Sworn';

  @override
  String get title_path_sworn_flavor =>
      'Halfway. You don\'t quit on the path now.';

  @override
  String get title_path_forged_name => 'Path-Forged';

  @override
  String get title_path_forged_flavor =>
      'Three quarters in. The path is forged from you.';

  @override
  String get title_saga_scribed_name => 'Saga-Scribed';

  @override
  String get title_saga_scribed_flavor =>
      'One hundred levels. Your name is in the codex.';

  @override
  String get title_saga_bound_name => 'Saga-Bound';

  @override
  String get title_saga_bound_flavor =>
      'One twenty-five. The saga binds you, and you bind back.';

  @override
  String get title_saga_eternal_name => 'Saga-Eternal';

  @override
  String get title_saga_eternal_flavor =>
      'One forty-eight. The saga has a name now, and it is yours.';

  @override
  String get title_pillar_walker_name => 'Pillar-Walker';

  @override
  String get title_pillar_walker_flavor =>
      'You walk on pillars, not on arms. The ground knows.';

  @override
  String get title_broad_shouldered_name => 'Broad-Shouldered';

  @override
  String get title_broad_shouldered_flavor =>
      'Yokes for shoulders, gates for a chest. Carry the weight.';

  @override
  String get title_even_handed_name => 'Even-Handed';

  @override
  String get title_even_handed_flavor =>
      'No weakness. No favorite lift. The whole forge, even-tempered.';

  @override
  String get title_iron_bound_name => 'Iron-Bound';

  @override
  String get title_iron_bound_flavor =>
      'Bench, pull, squat — all bound in iron. The big three answer to you.';

  @override
  String get title_saga_forged_name => 'Saga-Forged';

  @override
  String get title_saga_forged_flavor =>
      'Every track at sixty. The saga is forged, and you forged it.';

  @override
  String get decrementWeight => 'Decrease weight';

  @override
  String get incrementWeight => 'Increase weight';

  @override
  String get decrementReps => 'Decrease reps';

  @override
  String get incrementReps => 'Increase reps';

  @override
  String weightValueSemantics(String formatted, String unit) {
    return 'Weight value: $formatted $unit. Tap to enter weight.';
  }

  @override
  String repsValueSemantics(int value) {
    return 'Reps value: $value. Tap to enter reps.';
  }

  @override
  String get restTimerDismiss => 'Dismiss rest timer';

  @override
  String workoutNameTapToRenameSemantics(String name) {
    return '$name. Tap to rename workout.';
  }

  @override
  String workoutDefaultName(String date) {
    return 'Workout — $date';
  }

  @override
  String get volumePeakBlockVolumeLabel => 'Volume';

  @override
  String get volumePeakBlockCargaPicoLabel => 'Peak load';

  @override
  String get volumePeakBlockReferenciaLabel => 'Reference';

  @override
  String get volumePeakBlockSeries => 'sets';

  @override
  String get volumePeakBlockDeltaVsPrevWeek => 'vs last week';

  @override
  String get volumePeakBlockDeltaVsFourWeekMean => 'vs 4-week avg';

  @override
  String get volumePeakBlockDeltaNoHistory => 'no history';

  @override
  String get volumePeakBlockDeltaEstimated => 'estimated';

  @override
  String get volumePeakBlockDeltaAboveTarget => 'above target';

  @override
  String get volumePeakBlockBadge30D => '30D';

  @override
  String get weeklyEngagementHeader => 'Weekly engagement';

  @override
  String get engagementExplainerTitle => 'How we count sets';

  @override
  String get engagementExplainerBody =>
      'Each set counts toward the body part with the largest share of its XP attribution. If two body parts tie at the largest share, both count. This avoids double-counting unrelated muscles while still crediting compound lifts.';

  @override
  String get engagementLegendDone => 'Done';

  @override
  String get engagementLegendPlanned => 'Planned';

  @override
  String daysTrainedCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString days trained',
      one: '1 day trained',
      zero: '0 days trained',
    );
    return '$_temp0';
  }

  @override
  String get addWorkout => '+ Add workout';

  @override
  String softCapWarning(int count) {
    return 'Exceeds your weekly limit of $count';
  }

  @override
  String get spontaneousTag => 'Spontaneous';

  @override
  String get b1CopyDayZero => 'BEGUN.\nTHE WORST IS BEHIND.';

  @override
  String get b1CopyBaselineA => 'DONE.\nSTRONGER.';

  @override
  String get b1CopyBaselineB => 'CONSISTENCY WINS.';

  @override
  String get b1CopyPrAnticipatory => 'NEW LIMIT.';

  @override
  String get b1CopyTitleAnticipatory => 'ACHIEVEMENT AWAKENED.';

  @override
  String b1CopyMaxLevelUp(int n) {
    return 'LEVEL $n.\nTHE SAGA CONTINUES.';
  }

  @override
  String get b1CopyClassChangeOnly => 'NEW LIMIT.';

  @override
  String get b3PrEyebrowSingle => '!! Record';

  @override
  String b3PrEyebrowMulti(int n) {
    return '!! $n Records';
  }

  @override
  String get b3PrCopySingle => 'YOU BROKE THROUGH.';

  @override
  String get b3PrCopyMulti => 'YOU DESTROYED IT.';

  @override
  String b3PrPillTemplate(String exercise, String weight, int reps) {
    return '$exercise · ${weight}kg × $reps';
  }

  @override
  String get b3TitleEyebrow => 'Title Unlocked';

  @override
  String get b3ClassEyebrow => 'Class Awakened';

  @override
  String get b3ClassSubline => 'AWAKENED.';

  @override
  String b2RankCopy(String bodyPart, String n) {
    return '$bodyPart · RANK $n';
  }

  @override
  String summarySagaNumber(int n) {
    return 'Saga $n';
  }

  @override
  String get summaryDayZero => '1st saga';

  @override
  String summaryDurationSets(int minutes, int sets) {
    return '$minutes min · $sets sets';
  }

  @override
  String summaryTonnage(String kg) {
    return '$kg ton';
  }

  @override
  String get summaryNextStepLabel => 'Next';

  @override
  String summaryNextRank(int xp, String bodyPart, int n) {
    return '$xp XP left\nfor $bodyPart rank $n.';
  }

  @override
  String summaryNextLevel(int ranks, int n) {
    return '$ranks ranks to\nlevel $n.';
  }

  @override
  String get summaryNewTitleLabel => 'New title';

  @override
  String get summaryEquipCta => 'EQUIP';

  @override
  String get summaryEquipLater => 'later';

  @override
  String get summaryContinueCta => 'CONTINUE';

  @override
  String get summaryShareCta => 'Share saga';

  @override
  String get summaryShareComingSoon => 'Share — coming soon';

  @override
  String get shareSheetTitle => 'Share your saga';

  @override
  String get shareSheetTakePhoto => 'Take a photo';

  @override
  String get shareSheetFromGallery => 'Pick from gallery';

  @override
  String get shareSheetNoPhoto => 'No photo · just the saga';

  @override
  String get sharePreviewRetake => 'Retake';

  @override
  String get sharePreviewShare => 'Share';

  @override
  String get shareWordmark => 'REPSAGA';

  @override
  String get sharePermissionDenied =>
      'Camera access denied. Tap again to retry.';

  @override
  String get sharePermissionPermanentlyDenied =>
      'Camera access blocked in settings.';

  @override
  String get shareRenderError => 'Couldn\'t render the saga card. Try again.';

  @override
  String get shareOpenSettings => 'Open settings';

  @override
  String get summaryRankUpOverflowHeader => '+1 RANK · OPEN SAGA';

  @override
  String get emptyGuardTitle => 'End workout?';

  @override
  String get emptyGuardBody => 'No exercises logged.';

  @override
  String get emptyGuardDiscard => 'Discard';

  @override
  String get emptyGuardContinue => 'Keep training';

  @override
  String get postSessionFirstAwakeningSuffix => 'Awakened';

  @override
  String postSessionCascadeTruncationPill(String n) {
    return '+$n more';
  }

  @override
  String get postSessionXpLabel => 'XP';

  @override
  String get postSessionTitleEquipped => 'Equipped ✓';

  @override
  String get postSessionTitleEquipFailed =>
      'Could not equip title. Please try again.';

  @override
  String get cinematicSkipLabel => 'SKIP';

  @override
  String get postSessionDebriefEyebrow => 'Session report';

  @override
  String get postSessionPrFlag => 'PR';

  @override
  String postSessionMoreLifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count more exercises',
      one: '+1 more exercise',
    );
    return '$_temp0';
  }

  @override
  String postSessionRankLabel(int n) {
    return 'Rank $n';
  }

  @override
  String postSessionRankUpArrow(int fromRank, int toRank) {
    return 'Rank $fromRank → $toRank';
  }

  @override
  String get postSessionWeightUnit => 'kg';

  @override
  String get postSessionLeaveTitle => 'Leave the post-battle?';

  @override
  String get postSessionLeaveCancel => 'Cancel';

  @override
  String get postSessionLeaveConfirm => 'Leave';

  @override
  String get postSessionXpEarnedLabel => 'XP EARNED';

  @override
  String get avatarPickerSheetTitle => 'Choose avatar source';

  @override
  String get avatarPickerCamera => 'Take a photo';

  @override
  String get avatarPickerGallery => 'Pick from gallery';

  @override
  String get avatarPickerCancel => 'Cancel';

  @override
  String get avatarCropSheetTitle => 'Position your avatar';

  @override
  String get avatarCropSheetConfirm => 'Use this';

  @override
  String get avatarCropSheetCancel => 'Cancel';

  @override
  String get avatarUploadSuccess => 'Avatar updated.';

  @override
  String get avatarUploadFailed =>
      'Couldn\'t update your avatar. Please try again.';

  @override
  String avatarSemanticsLabel(String name) {
    return 'Profile avatar for $name';
  }

  @override
  String get cameraPermissionDeniedForAvatar =>
      'Camera access denied. Try the gallery, or open settings to grant access.';

  @override
  String historyWeekLabel(String date) {
    return 'Week of $date';
  }

  @override
  String historyWeekRollupSets(int sets) {
    return '$sets sets';
  }

  @override
  String historyCardXpEyebrow(int xp) {
    return '+$xp XP';
  }

  @override
  String historyCardPrCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PRs',
      one: '1 PR',
    );
    return '◆ $_temp0';
  }

  @override
  String historyDetailStripXpPart(int xp) {
    return '+$xp XP';
  }

  @override
  String historyDetailStripPrPart(int prs) {
    String _temp0 = intl.Intl.pluralLogic(
      prs,
      locale: localeName,
      other: '$prs PRs',
      one: '1 PR',
    );
    return '$_temp0';
  }

  @override
  String get historyWeekLabelCurrent => 'This Week';

  @override
  String get sendUsageAnalytics => 'Send usage analytics';

  @override
  String get usageAnalyticsSubtitle =>
      'Helps RepSaga improve. You can disable any time.';

  @override
  String get signupAgeConfirmationLead => 'I\'m 18+ and agree to the';

  @override
  String get bodyweightConsentTitle => 'Body weight is sensitive data.';

  @override
  String get bodyweightConsentBody =>
      'Per the Privacy Policy, body weight is health data and requires your explicit consent. It\'s used solely to improve XP calculation for bodyweight exercises. You can revoke this consent any time in Profile → Settings → Privacy.';

  @override
  String get bodyweightConsentAccept => 'Save with consent';

  @override
  String get bodyweightConsentToggleTitle => 'Body weight tracking';

  @override
  String get bodyweightConsentToggleSubtitle =>
      'Required to log body weight. Disabling does not delete past entries.';

  @override
  String get genderLabel => 'Gender';

  @override
  String get genderConsentBanner =>
      'Gender helps RepSaga match XP calculations to gender-aware strength tier tables. This is sensitive data — you can pick \"Other\" or leave it blank to skip.';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderOther => 'Other';

  @override
  String get genderNotSet => 'Not set';
}
