import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// Bottom navigation label for home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation label for exercises tab
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get navExercises;

  /// Bottom navigation label for routines tab
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get navRoutines;

  /// Bottom navigation label for profile tab
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// Bottom navigation label for the character-sheet (Saga) tab — replaces 'Profile'.
  ///
  /// In en, this message translates to:
  /// **'Saga'**
  String get sagaTabLabel;

  /// Day-1 copy for the class-badge slot on the character sheet, before any class has been derived.
  ///
  /// In en, this message translates to:
  /// **'The iron will name you.'**
  String get classSlotPlaceholder;

  /// Class-badge label for CharacterClass.initiate — newcomer to the path. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Initiate'**
  String get classInitiate;

  /// Class-badge label for CharacterClass.berserker — arms-dominant specialist. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Berserker'**
  String get classBerserker;

  /// Class-badge label for CharacterClass.bulwark — chest-dominant pressing specialist. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Bulwark'**
  String get classBulwark;

  /// Class-badge label for CharacterClass.sentinel — back-dominant pulling specialist. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Sentinel'**
  String get classSentinel;

  /// Class-badge label for CharacterClass.pathfinder — legs-dominant lower-body specialist. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Pathfinder'**
  String get classPathfinder;

  /// Class-badge label for CharacterClass.atlas — shoulders-dominant overhead specialist. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Atlas'**
  String get classAtlas;

  /// Class-badge label for CharacterClass.anchor — core-dominant stability specialist. Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Anchor'**
  String get classAnchor;

  /// Class-badge label for CharacterClass.ascendant — balanced (rare, prestigious). Phase 18e.
  ///
  /// In en, this message translates to:
  /// **'Ascendant'**
  String get classAscendant;

  /// Subtitle on the dormant Cardio row of the character sheet — communicates that cardio is intentionally not yet active.
  ///
  /// In en, this message translates to:
  /// **'Cardio runes awaken in a future chapter.'**
  String get dormantCardioCopy;

  /// Inline banner shown on the character sheet when the user has zero lifetime XP (Phase 18b onboarding gate).
  ///
  /// In en, this message translates to:
  /// **'Your first set awakens this path.'**
  String get firstSetAwakensCopy;

  /// Codex nav row label for the Stats deep-dive sub-screen (Phase 18d).
  ///
  /// In en, this message translates to:
  /// **'Stats deep-dive'**
  String get statsDeepDiveLabel;

  /// Codex nav row label for the Titles sub-screen (Phase 18c).
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get titlesLabel;

  /// Codex nav row label for the workout-history sub-screen.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyLabel;

  /// App bar title for the profile-settings sub-screen reachable via the gear icon on the character sheet.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsLabel;

  /// Empty-state copy for a body part the user has never trained (peak == 0; the ewma/peak ratio is undefined and the percentage renders as an em-dash). Distinct from vitalityCopyDormant which describes formerly-trained body parts whose conditioning has fully decayed (ratio is genuinely 0%).
  ///
  /// In en, this message translates to:
  /// **'Uncharted — log a set to begin.'**
  String get vitalityCopyUntested;

  /// Marginalia copy for a body-part rune in the Dormant state (peak > 0 but EWMA ~ 0 — trained at least once, then fully fallen off the path). Renders as 0–33% on the stats deep-dive screen. Distinct from vitalityCopyUntested which is the never-trained branch.
  ///
  /// In en, this message translates to:
  /// **'Dormant. Train this group to reawaken its path.'**
  String get vitalityCopyDormant;

  /// Short subtitle for an untested row in the vitality table (Phase 26c). Compact stats register — shorter than vitalityCopyUntested which remains the long marginalia copy used elsewhere.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get vitalityRowUntestedSubtitle;

  /// Label for the high band (66–100%) on the vitality HP-drain ramp. Shown inside the vitality explainer bottom sheet (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get vitalityStateBandActive;

  /// Label for the mid band (34–65%) on the vitality HP-drain ramp. Shown inside the vitality explainer bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Waning'**
  String get vitalityStateBandWaning;

  /// Label for the low band (0–33%) on the vitality HP-drain ramp. Shown inside the vitality explainer bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Dormant'**
  String get vitalityStateBandDormant;

  /// Title of the vitality explainer bottom sheet (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Vitality'**
  String get vitalityExplainerTitle;

  /// First-paragraph definition copy in the vitality explainer bottom sheet (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Vitality reflects how recent your training is for each muscle group. It\'s a measure of how active your saga is, not a measure of strength.'**
  String get vitalityExplainerDefinition;

  /// Sub-heading above the three-state band ramp in the vitality explainer (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'How it moves:'**
  String get vitalityExplainerHowItMoves;

  /// High-band copy in the vitality explainer (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'66–100% — recent training, on the path.'**
  String get vitalityExplainerBandActive;

  /// Mid-band copy in the vitality explainer (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'34–65% — slowing down, the path is fading.'**
  String get vitalityExplainerBandWaning;

  /// Low-band copy in the vitality explainer (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'0–33% — the path has gone silent.'**
  String get vitalityExplainerBandDormant;

  /// heroGold-bordered safety guarantee in the vitality explainer (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Vitality does NOT affect your rank or XP — those are permanent. Vitality is purely a consistency signal.'**
  String get vitalityExplainerRankSafety;

  /// Trailing copy on per-stat XP labels across Saga, Stats deep-dive, Home expanded card, Titles próximos rows. Rendered as 'N XP · M {withinRankXpSuffix}' (e.g., '1,420 XP · 580 to next rank').
  ///
  /// In en, this message translates to:
  /// **'to next rank'**
  String get withinRankXpSuffix;

  /// AppBar title for the /saga/stats deep-dive screen (Phase 18d.2). Distinct from `statsDeepDiveLabel` because the codex nav row uses 'Stats deep-dive' but the screen header uses the shorter 'Stats'.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get statsDeepDiveTitle;

  /// Section heading for the 90-day vitality trend chart on the stats deep-dive screen — used when the user has ≥30 days of activity.
  ///
  /// In en, this message translates to:
  /// **'90-Day Vitality Trend'**
  String get vitalityTrendHeading;

  /// Section heading for the vitality trend chart in narrow-window mode — used when the user has <30 days of activity (the chart's X-axis spans first_activity_date → today instead of a rolling 90-day window).
  ///
  /// In en, this message translates to:
  /// **'Vitality Trend'**
  String get vitalityTrendHeadingShort;

  /// Section heading above the live vitality table on the stats deep-dive screen. Anchors the chart→table junction so the table reads as its own section, not as the chart's legend.
  ///
  /// In en, this message translates to:
  /// **'Live Vitality'**
  String get liveVitalitySectionHeading;

  /// Section heading for the per-body-part volume and peak EWMA table on the stats deep-dive screen.
  ///
  /// In en, this message translates to:
  /// **'Volume & Peak'**
  String get volumePeakSectionHeading;

  /// Section heading for the per-exercise peak loads list on the stats deep-dive screen.
  ///
  /// In en, this message translates to:
  /// **'Peak Loads'**
  String get peakLoadsSectionHeading;

  /// Empty-state copy for the peak loads section when the user has no `exercise_peak_loads` rows.
  ///
  /// In en, this message translates to:
  /// **'No peaks recorded yet.'**
  String get peakLoadsEmpty;

  /// Unit label for the weekly volume (set count, last 7 days) column in the per-body-part volume/peak table.
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get weeklyVolumeUnit;

  /// Label for the estimated 1RM value rendered next to a peak load row when the calculator can produce one.
  ///
  /// In en, this message translates to:
  /// **'1RM est.'**
  String get oneRmEstimateLabel;

  /// Right-edge X-axis label on the vitality trend chart — always 'today'.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get chartXLabelToday;

  /// Left-edge X-axis label on the vitality trend chart in 90-day mode (≥30 days of activity).
  ///
  /// In en, this message translates to:
  /// **'90 days ago'**
  String get chartXLabel90DaysAgo;

  /// Left-edge X-axis label on the vitality trend chart in narrow mode (<30 days of activity). The number is the count of days since the user's first activity.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String chartXLabelDaysAgo(int count);

  /// Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// PR-7 — UI-critic deferred from PR-1. Scoped label for the abort button inside `ActiveWorkoutLoadingOverlay`. The generic `cancel` key reads as 'cancel my workout' in the finish/discard phase (the user just confirmed the destructive action; 'Cancel' on the spinner reads as undoing the entire workout). 'Stop' is unambiguous: it stops the in-flight save/discard request and restores the prior state. Scoped to this single call site — every other dialog and Material control still uses `cancel`.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get loadingOverlayStop;

  /// Delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Dismiss button label
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Continue button label (continueLabel avoids Dart keyword)
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// Log out button label
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// Done button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Edit button label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Create button label
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Add button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Skip button label
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Back button label
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Two-tap-to-exit hint shown on Home when the user presses back once. A second back press within 3 seconds exits the app.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get backExitHint;

  /// Close button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Start action label
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// Remove button label
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Discard button label
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// Resume button label
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// Clear button label
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Replace button label
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// Undo action label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// All filter label
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Separator between login methods
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get or;

  /// Generic loading indicator text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get error;

  /// Empty search results message
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// Generic empty state message
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyState;

  /// Search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Email field label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Log in button label
  ///
  /// In en, this message translates to:
  /// **'LOG IN'**
  String get logIn;

  /// Sign up button label
  ///
  /// In en, this message translates to:
  /// **'SIGN UP'**
  String get signUp;

  /// Heading shown above the signup form (replaces the dim subtitle in signup mode)
  ///
  /// In en, this message translates to:
  /// **'CREATE ACCOUNT'**
  String get signupHeading;

  /// Non-blocking password-strength tier word, weakest tier (composed with a tip as '{tier} — {tip}')
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passwordStrengthWeak;

  /// Non-blocking password-strength tier word, middle tier (composed with a tip as '{tier} — {tip}')
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get passwordStrengthMedium;

  /// Non-blocking password-strength label, strongest tier (shown standalone, no tip)
  ///
  /// In en, this message translates to:
  /// **'Strong password!'**
  String get passwordStrengthStrong;

  /// Password strength next-step tip: the password is too short
  ///
  /// In en, this message translates to:
  /// **'use 8+ characters'**
  String get passwordTipLength;

  /// Password strength next-step tip: the password has no digit
  ///
  /// In en, this message translates to:
  /// **'add a number'**
  String get passwordTipNumber;

  /// Password strength next-step tip: the password has no special character
  ///
  /// In en, this message translates to:
  /// **'add a symbol'**
  String get passwordTipSymbol;

  /// Tooltip / accessibility label for the reveal-password eye when the password is hidden
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// Tooltip / accessibility label for the reveal-password eye when the password is shown
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// One-time ghost hint under the signup password strength bar nudging the user to reveal their password
  ///
  /// In en, this message translates to:
  /// **'Tap the eye to check your password'**
  String get passwordRevealHint;

  /// Helper text below the disabled signup CTA explaining the age-gate
  ///
  /// In en, this message translates to:
  /// **'Confirm your age to continue'**
  String get signupAgeRequiredHint;

  /// Forgot password link text
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// Send password reset email button label
  ///
  /// In en, this message translates to:
  /// **'Send Reset Email'**
  String get sendResetEmail;

  /// Offline connectivity banner text
  ///
  /// In en, this message translates to:
  /// **'Offline — changes will sync when you\'re back online'**
  String get offlineBanner;

  /// Singular form: number of offline changes pending sync
  ///
  /// In en, this message translates to:
  /// **'{count} change pending sync'**
  String pendingSyncSingular(int count);

  /// Plural form: number of offline changes pending sync
  ///
  /// In en, this message translates to:
  /// **'{count} changes pending sync'**
  String pendingSyncPlural(int count);

  /// Relative date: today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Relative date: yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Relative date: N days ago
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(int count);

  /// Relative date: N weeks ago
  ///
  /// In en, this message translates to:
  /// **'{count} weeks ago'**
  String weeksAgo(int count);

  /// Relative date: N months ago
  ///
  /// In en, this message translates to:
  /// **'{count} months ago'**
  String monthsAgo(int count);

  /// Muscle group: chest
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get muscleGroupChest;

  /// Muscle group: back
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get muscleGroupBack;

  /// Muscle group: legs
  ///
  /// In en, this message translates to:
  /// **'Legs'**
  String get muscleGroupLegs;

  /// Muscle group: shoulders
  ///
  /// In en, this message translates to:
  /// **'Shoulders'**
  String get muscleGroupShoulders;

  /// Muscle group: arms
  ///
  /// In en, this message translates to:
  /// **'Arms'**
  String get muscleGroupArms;

  /// Muscle group: core
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get muscleGroupCore;

  /// Muscle group: cardio
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get muscleGroupCardio;

  /// Equipment type: barbell
  ///
  /// In en, this message translates to:
  /// **'Barbell'**
  String get equipmentBarbell;

  /// Equipment type: dumbbell
  ///
  /// In en, this message translates to:
  /// **'Dumbbell'**
  String get equipmentDumbbell;

  /// Equipment type: cable
  ///
  /// In en, this message translates to:
  /// **'Cable'**
  String get equipmentCable;

  /// Equipment type: machine
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get equipmentMachine;

  /// Equipment type: bodyweight
  ///
  /// In en, this message translates to:
  /// **'Bodyweight'**
  String get equipmentBodyweight;

  /// Equipment type: bands
  ///
  /// In en, this message translates to:
  /// **'Bands'**
  String get equipmentBands;

  /// Equipment type: kettlebell
  ///
  /// In en, this message translates to:
  /// **'Kettlebell'**
  String get equipmentKettlebell;

  /// Set type: working set
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get setTypeWorking;

  /// Set type: warm-up
  ///
  /// In en, this message translates to:
  /// **'Warm-up'**
  String get setTypeWarmup;

  /// Set type: drop set
  ///
  /// In en, this message translates to:
  /// **'Drop Set'**
  String get setTypeDropset;

  /// Set type: to failure
  ///
  /// In en, this message translates to:
  /// **'To Failure'**
  String get setTypeFailure;

  /// Record type: max weight
  ///
  /// In en, this message translates to:
  /// **'Max Weight'**
  String get recordTypeMaxWeight;

  /// Record type: max reps
  ///
  /// In en, this message translates to:
  /// **'Max Reps'**
  String get recordTypeMaxReps;

  /// Record type: max volume
  ///
  /// In en, this message translates to:
  /// **'Max Volume'**
  String get recordTypeMaxVolume;

  /// Weight unit: kilograms (display)
  ///
  /// In en, this message translates to:
  /// **'KG'**
  String get weightUnitKg;

  /// Weight unit: pounds (display)
  ///
  /// In en, this message translates to:
  /// **'LBS'**
  String get weightUnitLbs;

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'RepSaga'**
  String get appName;

  /// Login screen subtitle for existing users
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// Login screen subtitle for new users
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createYourAccount;

  /// Email validation error: empty
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// Email validation error: invalid format
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get emailInvalid;

  /// Password validation error: empty
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// Password validation error: too short
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

  /// Display-name validation error on the signup form: empty
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get displayNameRequired;

  /// Hint when forgot password tapped without email
  ///
  /// In en, this message translates to:
  /// **'Enter your email above, then tap \"Forgot password?\"'**
  String get forgotPasswordHint;

  /// Reset password dialog title
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// Reset password confirmation message
  ///
  /// In en, this message translates to:
  /// **'Send a password reset email to {email}?'**
  String sendResetEmailTo(String email);

  /// Snackbar after password reset email sent
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent. Check your inbox.'**
  String get resetEmailSent;

  /// Google sign-in button label
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// Toggle to login mode
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get alreadyHaveAccount;

  /// Toggle to signup mode
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get dontHaveAccount;

  /// Legal footer prefix text
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our '**
  String get legalAgreePrefix;

  /// Terms of Service link text
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// Legal footer and separator
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get andSeparator;

  /// Privacy Policy link text
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// Auth error: invalid credentials
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password. Please try again.'**
  String get authErrorInvalidCredentials;

  /// Auth error: email not confirmed
  ///
  /// In en, this message translates to:
  /// **'Please check your inbox and confirm your email first.'**
  String get authErrorEmailNotConfirmed;

  /// Auth error: already registered
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Try logging in instead.'**
  String get authErrorAlreadyRegistered;

  /// Auth error: rate limited
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get authErrorRateLimit;

  /// Auth error: weak password
  ///
  /// In en, this message translates to:
  /// **'Password is too weak. Use at least 6 characters.'**
  String get authErrorWeakPassword;

  /// Auth error: network issue
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check your network and try again.'**
  String get authErrorNetwork;

  /// Auth error: timeout
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please try again.'**
  String get authErrorTimeout;

  /// Auth error: expired token/OTP
  ///
  /// In en, this message translates to:
  /// **'The confirmation link has expired. Please request a new one.'**
  String get authErrorTokenExpired;

  /// Auth error: generic fallback
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get authErrorGeneric;

  /// Email confirmation screen title
  ///
  /// In en, this message translates to:
  /// **'Check your inbox'**
  String get checkYourInbox;

  /// Confirmation email sent to specific address
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation email to'**
  String get confirmationSentTo;

  /// Confirmation email sent (no address)
  ///
  /// In en, this message translates to:
  /// **'We sent you a confirmation email'**
  String get confirmationSent;

  /// Instructions to verify email
  ///
  /// In en, this message translates to:
  /// **'Tap the link in the email to verify your account, then come back and log in.'**
  String get tapLinkToVerify;

  /// Confirmation when email resent
  ///
  /// In en, this message translates to:
  /// **'Email resent! Check your inbox.'**
  String get emailResent;

  /// Back to login button
  ///
  /// In en, this message translates to:
  /// **'BACK TO LOGIN'**
  String get backToLogin;

  /// Resend confirmation email link
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive it? Resend email'**
  String get didntReceiveResend;

  /// Onboarding welcome headline
  ///
  /// In en, this message translates to:
  /// **'Track every rep,\nevery time'**
  String get onboardingHeadline;

  /// Onboarding welcome subtitle
  ///
  /// In en, this message translates to:
  /// **'Log workouts, crush personal records, and build the physique you want.'**
  String get onboardingSubtitle;

  /// Onboarding get started button
  ///
  /// In en, this message translates to:
  /// **'GET STARTED'**
  String get getStarted;

  /// Profile setup page title
  ///
  /// In en, this message translates to:
  /// **'Set up your profile'**
  String get setupProfile;

  /// Profile setup subtitle
  ///
  /// In en, this message translates to:
  /// **'Tell us a bit about yourself'**
  String get tellUsAboutYourself;

  /// Display name field label
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// Fitness level section label
  ///
  /// In en, this message translates to:
  /// **'Fitness level'**
  String get fitnessLevel;

  /// Training frequency question
  ///
  /// In en, this message translates to:
  /// **'How often do you plan to train?'**
  String get howOftenTrain;

  /// Weekly goal hint text
  ///
  /// In en, this message translates to:
  /// **'Your weekly goal — you can change this anytime'**
  String get weeklyGoalHint;

  /// Finish onboarding button
  ///
  /// In en, this message translates to:
  /// **'LET\'S GO'**
  String get letsGo;

  /// Snackbar: profile save failed — safety-net copy for unmapped AppException subtypes on the onboarding save path
  ///
  /// In en, this message translates to:
  /// **'Failed to save profile. Please try again.'**
  String get failedToSaveProfile;

  /// Onboarding save snackbar shown when a NetworkException or TimeoutException reaches the catch block — recovery is retry-after-reconnect
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Check your connection and try again.'**
  String get onboardingErrorOffline;

  /// Onboarding save snackbar shown when an AuthException reaches the catch block after the BaseRepository stale-token refresh-retry already failed
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Sign in again.'**
  String get onboardingErrorSessionExpired;

  /// Action label on the session-expired snackbar — tapping it routes the user back to /login
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get onboardingErrorSessionExpiredCta;

  /// Onboarding save snackbar shown when a ValidationException reaches the catch block with no recognised field token — falls back to a non-leaky hint
  ///
  /// In en, this message translates to:
  /// **'Please check your inputs.'**
  String get onboardingErrorValidationGeneric;

  /// Onboarding save snackbar shown when a ValidationException carries a recognised field token — '<localized field name>: <message>'
  ///
  /// In en, this message translates to:
  /// **'{field}: {message}'**
  String onboardingErrorValidationField(String field, String message);

  /// Fitness level: beginner
  ///
  /// In en, this message translates to:
  /// **'Beginner'**
  String get fitnessLevelBeginner;

  /// Fitness level: intermediate
  ///
  /// In en, this message translates to:
  /// **'Intermediate'**
  String get fitnessLevelIntermediate;

  /// Fitness level: advanced
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get fitnessLevelAdvanced;

  /// ActionHero headline when the user has zero routines — points them at routine creation. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Create first routine'**
  String get homeActionHeroCreateFirstRoutine;

  /// ActionHero headline when the bucket is empty or fully complete — the user can still start an unplanned (spontaneous) workout. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Free workout'**
  String get homeActionHeroFreeWorkout;

  /// ActionHero subline shown beneath the free-workout headline when every planned routine in the week's bucket has been completed. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Week complete'**
  String get homeActionHeroFreeWorkoutSubtitleWeekComplete;

  /// ActionHero headline pointing at the next uncompleted routine in the week's bucket. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Start {routineName}'**
  String homeActionHeroStartRoutine(String routineName);

  /// Uppercase eyebrow label above the ActionHero start-routine headline. Phase 32 PR 32a.
  ///
  /// In en, this message translates to:
  /// **'START'**
  String get homeActionHeroStartEyebrow;

  /// Uppercase eyebrow label above the ActionHero free-workout headline. Phase 32 PR 32a.
  ///
  /// In en, this message translates to:
  /// **'FREE WORKOUT'**
  String get homeActionHeroFreeEyebrow;

  /// Uppercase eyebrow label above the ActionHero create-first-routine headline shown to day-0 users. Phase 32 PR 32a.
  ///
  /// In en, this message translates to:
  /// **'WELCOME'**
  String get homeActionHeroWelcomeEyebrow;

  /// Right-aligned counter on the home bucket section header. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No days trained} =1{1 day trained} other{{count} days trained}}'**
  String homeBucketDaysTrained(int count);

  /// Section title for the home bucket chip row. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get homeBucketSectionTitle;

  /// Star-marked badge text on bucket chips for spontaneous (off-plan) routines logged during the week. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get homeBucketSpontaneousBadge;

  /// Semantics hint on the chevron of the home character card — communicates the tap affordance to assistive tech. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Tap to expand character details'**
  String get homeCharacterCardChevronHint;

  /// Collapsed character-card indicator highlighting the body part closest to its next rank threshold. Diamond glyph (◆) prefix matches the body-part hue at render time. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'◆ {bodyPart} · {xp} XP for rank {rank}'**
  String homeClosestRankUp(String bodyPart, int xp, int rank);

  /// Right-aligned link below the home bucket chip row that opens the weekly plan editor. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Edit plan →'**
  String get homeEditPlanLink;

  /// Fallback copy shown on the collapsed character card when the user has no trained body parts yet (day-0). Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Begin your journey — first set awaits'**
  String get homeFirstStepFallback;

  /// Encouragement nudge variant when a body-part-specific title is within one rank. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'{bodyPart} title within reach: {titleName}'**
  String homeNudgeBodyPartTitleClose(String bodyPart, String titleName);

  /// Encouragement nudge variant when a cross-build (distinction) title is within reach. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'Cross-build title within reach: {titleName}'**
  String homeNudgeCrossBuildClose(String titleName);

  /// Encouragement nudge variant when planned bucket entries remain for the current week. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Need 1 workout to close the week} other{Need {count} workouts to close the week}}'**
  String homeNudgeRemainingWorkouts(int count);

  /// Encouragement nudge variant celebrating a consecutive-day training streak. Phase 26f.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1-day streak} other{{count}-day streak}}'**
  String homeNudgeStreakDays(int count);

  /// Confirmation banner question
  ///
  /// In en, this message translates to:
  /// **'Same plan this week?'**
  String get samePlanThisWeek;

  /// Section header for user's routines on home
  ///
  /// In en, this message translates to:
  /// **'MY ROUTINES'**
  String get myRoutines;

  /// Link to see all routines
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// CTA for first routine creation
  ///
  /// In en, this message translates to:
  /// **'Create Your First Routine'**
  String get createYourFirstRoutine;

  /// Sentence-case muted label above the seeded starter-routines preview on Home (day-0 users). Phase 27 L3.
  ///
  /// In en, this message translates to:
  /// **'Starter Routines'**
  String get homeStarterRoutinesLabel;

  /// Action hero label: up next
  ///
  /// In en, this message translates to:
  /// **'UP NEXT'**
  String get heroUpNext;

  /// Action hero label: first workout
  ///
  /// In en, this message translates to:
  /// **'YOUR FIRST WORKOUT'**
  String get heroYourFirstWorkout;

  /// Action hero label: no plan
  ///
  /// In en, this message translates to:
  /// **'NO PLAN'**
  String get heroNoPlan;

  /// Action hero label: new week
  ///
  /// In en, this message translates to:
  /// **'NEW WEEK'**
  String get heroNewWeek;

  /// Action hero headline: plan your week
  ///
  /// In en, this message translates to:
  /// **'Plan your week'**
  String get planYourWeek;

  /// Action hero subline: pick routines
  ///
  /// In en, this message translates to:
  /// **'Pick routines for the week'**
  String get pickRoutinesForWeek;

  /// Quick workout button
  ///
  /// In en, this message translates to:
  /// **'Quick workout'**
  String get quickWorkout;

  /// Start new week headline
  ///
  /// In en, this message translates to:
  /// **'Start new week'**
  String get startNewWeek;

  /// Completed count subline
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} done'**
  String nOfNDone(int completed, int total);

  /// Exercise count and estimated duration
  ///
  /// In en, this message translates to:
  /// **'{count} exercises · ~{minutes} min'**
  String exerciseCountDuration(int count, int minutes);

  /// Snackbar: offline start workout blocked
  ///
  /// In en, this message translates to:
  /// **'Starting a workout requires an internet connection'**
  String get offlineStartWorkout;

  /// Snackbar: exercise load failure for routine
  ///
  /// In en, this message translates to:
  /// **'Could not load exercises. Please try again.'**
  String get couldNotLoadExercises;

  /// Prefix for last session line on home
  ///
  /// In en, this message translates to:
  /// **'Last: '**
  String get lastSessionPrefix;

  /// Exercises screen title
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get exercises;

  /// Search exercises placeholder
  ///
  /// In en, this message translates to:
  /// **'Search exercises...'**
  String get searchExercises;

  /// Empty state: filters active, no results
  ///
  /// In en, this message translates to:
  /// **'No exercises match your filters'**
  String get noExercisesMatchFilters;

  /// Empty state: no exercises at all
  ///
  /// In en, this message translates to:
  /// **'Your exercises will appear here'**
  String get yourExercisesWillAppear;

  /// Clear filters button
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearFilters;

  /// Exercise detail screen title
  ///
  /// In en, this message translates to:
  /// **'Exercise Details'**
  String get exerciseDetails;

  /// Error loading exercise detail
  ///
  /// In en, this message translates to:
  /// **'Failed to load exercise'**
  String get failedToLoadExercise;

  /// Badge for user-created exercises
  ///
  /// In en, this message translates to:
  /// **'Custom exercise'**
  String get customExercise;

  /// Section header: personal records
  ///
  /// In en, this message translates to:
  /// **'Personal Records'**
  String get personalRecords;

  /// Empty state: no personal records
  ///
  /// In en, this message translates to:
  /// **'No records yet'**
  String get noRecordsYet;

  /// Delete exercise button/dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Exercise'**
  String get deleteExercise;

  /// Delete exercise confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteExerciseConfirm(String name);

  /// Deleting state label
  ///
  /// In en, this message translates to:
  /// **'Deleting...'**
  String get deleting;

  /// Exercise image label: start position
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get imageStart;

  /// Exercise image label: end position
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get imageEnd;

  /// Reps display with count
  ///
  /// In en, this message translates to:
  /// **'{count} reps'**
  String repsUnit(int count);

  /// Exercise name field label
  ///
  /// In en, this message translates to:
  /// **'Exercise Name'**
  String get exerciseName;

  /// Validation: name required
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// Validation: name too short
  ///
  /// In en, this message translates to:
  /// **'Name must be at least 2 characters'**
  String get nameTooShort;

  /// Muscle group section label
  ///
  /// In en, this message translates to:
  /// **'Muscle Group'**
  String get muscleGroup;

  /// Equipment type section label
  ///
  /// In en, this message translates to:
  /// **'Equipment Type'**
  String get equipmentType;

  /// Validation: muscle+equipment required
  ///
  /// In en, this message translates to:
  /// **'Please select a muscle group and equipment type'**
  String get selectMuscleAndEquipment;

  /// Session expired snackbar
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please log in again.'**
  String get sessionExpired;

  /// Description field label
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// Description field hint
  ///
  /// In en, this message translates to:
  /// **'Brief description of the exercise (optional)'**
  String get descriptionHint;

  /// Form tips field label
  ///
  /// In en, this message translates to:
  /// **'Form Tips'**
  String get formTips;

  /// Form tips field hint
  ///
  /// In en, this message translates to:
  /// **'Form cues, one per line (optional)'**
  String get formTipsHint;

  /// Form tips field helper text
  ///
  /// In en, this message translates to:
  /// **'Enter each tip on a new line'**
  String get formTipsHelper;

  /// Exercise detail about section header
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get aboutSection;

  /// Exercise detail form tips section header
  ///
  /// In en, this message translates to:
  /// **'FORM TIPS'**
  String get formTipsSection;

  /// Finish workout button
  ///
  /// In en, this message translates to:
  /// **'Finish Workout'**
  String get finishWorkout;

  /// Hint: need completed set to finish
  ///
  /// In en, this message translates to:
  /// **'Complete at least one set to finish'**
  String get completeOneSet;

  /// Empty workout: add exercise prompt
  ///
  /// In en, this message translates to:
  /// **'Add your first exercise'**
  String get addFirstExercise;

  /// Empty workout: add exercise hint
  ///
  /// In en, this message translates to:
  /// **'Tap the button below to get started'**
  String get tapButtonToStart;

  /// Add exercise button
  ///
  /// In en, this message translates to:
  /// **'Add Exercise'**
  String get addExercise;

  /// Add set button
  ///
  /// In en, this message translates to:
  /// **'Add Set'**
  String get addSet;

  /// Fill remaining sets button with the count of sets that will be filled
  ///
  /// In en, this message translates to:
  /// **'Fill remaining ({count, plural, =1{1 set} other{{count} sets}})'**
  String fillRemainingSetsCount(int count);

  /// Snackbar: filled remaining sets
  ///
  /// In en, this message translates to:
  /// **'Filled remaining sets'**
  String get filledRemainingSets;

  /// Remove exercise dialog title
  ///
  /// In en, this message translates to:
  /// **'Remove Exercise?'**
  String get removeExerciseTitle;

  /// Remove exercise dialog content
  ///
  /// In en, this message translates to:
  /// **'Remove {name} and all its sets?'**
  String removeExerciseContent(String name);

  /// Snackbar: discard workout failed
  ///
  /// In en, this message translates to:
  /// **'Failed to discard workout. Please retry.'**
  String get failedToDiscardWorkout;

  /// Snackbar: save workout failed
  ///
  /// In en, this message translates to:
  /// **'Failed to save workout. Please retry.'**
  String get failedToSaveWorkout;

  /// Snackbar: workout saved offline
  ///
  /// In en, this message translates to:
  /// **'Workout saved. Will sync when back online.'**
  String get workoutSavedOffline;

  /// Snackbar: workout queued offline because the server returned a 5xx error (AW-EX-D-US1-03). Distinguishes from plain connectivity loss.
  ///
  /// In en, this message translates to:
  /// **'Server error — saved locally. Will retry automatically.'**
  String get workoutSavedServerError;

  /// Set column header: set number
  ///
  /// In en, this message translates to:
  /// **'SET'**
  String get setColumnSet;

  /// Set column header: weight
  ///
  /// In en, this message translates to:
  /// **'WEIGHT'**
  String get setColumnWeight;

  /// Set column header: reps
  ///
  /// In en, this message translates to:
  /// **'REPS'**
  String get setColumnReps;

  /// Set column header: type (read-only detail)
  ///
  /// In en, this message translates to:
  /// **'TYPE'**
  String get setColumnType;

  /// Snackbar: set deleted
  ///
  /// In en, this message translates to:
  /// **'Set {number} deleted'**
  String setDeleted(int number);

  /// Discard workout dialog title
  ///
  /// In en, this message translates to:
  /// **'Discard Workout?'**
  String get discardWorkoutTitle;

  /// Discard workout dialog content. PR-7 brand-voice revisit: pre-fix copy was 'You've been working out for {duration}. This cannot be undone.' — descriptively flat for the highest-stakes destructive moment in the active workout. New copy borrows the journey framing already established by `vitalityCopy*` and class-tagline strings ('the path begins', 'return to the path') and replaces 'cannot be undone' with the concrete consequence: the work disappears. Lower abstraction, higher weight, same brand voice as the rest of the app.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been on the path {duration}. Discard now and the work is gone.'**
  String discardWorkoutContent(String duration);

  /// Finish workout dialog title. PR-7 brand-voice revisit: pre-fix 'Finish Workout?' read as a generic Material confirm prompt. 'Seal' echoes the saga / chapter framing the rest of the app uses without going LARP-y; 'session' stays grounded in lifting reality. Pairs with the Save & Finish CTA which now reads as the deliberate close of a chapter rather than a transactional save.
  ///
  /// In en, this message translates to:
  /// **'Seal this session?'**
  String get finishWorkoutTitle;

  /// Warning about incomplete sets
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 incomplete set} other{You have {count} incomplete sets}}'**
  String incompleteSetsWarning(int count);

  /// Q1 notes-edit-after — evocative placeholder hint inside the workout-notes edit field (distinct from the addNote affordance label on the detail screen).
  ///
  /// In en, this message translates to:
  /// **'How was the session? Observations, how you felt, what you\'d adjust…'**
  String get addNotesHint;

  /// Keep going button in finish dialog
  ///
  /// In en, this message translates to:
  /// **'Keep Going'**
  String get keepGoing;

  /// Save and finish button
  ///
  /// In en, this message translates to:
  /// **'Save & Finish'**
  String get saveAndFinish;

  /// Resume workout dialog title
  ///
  /// In en, this message translates to:
  /// **'Resume workout?'**
  String get resumeWorkoutTitle;

  /// Resume stale workout dialog title
  ///
  /// In en, this message translates to:
  /// **'Pick up where you left off?'**
  String get resumeWorkoutStaleTitle;

  /// Resume dialog: workout in progress
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is still in progress.'**
  String workoutInProgress(String name);

  /// Resume dialog: stale workout interrupted info. Rendered on its own visual line after a `\n` separator following the quoted workout name, so the leading word starts a sentence — capital W, not lowercase. PR-7 capitalization fix.
  ///
  /// In en, this message translates to:
  /// **'Was interrupted {age}.'**
  String workoutInterrupted(String age);

  /// Resume anyway button for stale workouts
  ///
  /// In en, this message translates to:
  /// **'Resume anyway'**
  String get resumeAnyway;

  /// Rest timer default exercise name
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get restTimerLabel;

  /// Rest timer semantics label
  ///
  /// In en, this message translates to:
  /// **'Rest timer: {time} remaining'**
  String restTimerRemaining(String time);

  /// Rest timer -30s button semantics
  ///
  /// In en, this message translates to:
  /// **'Subtract 30 seconds'**
  String get subtract30Semantics;

  /// Rest timer +30s button semantics
  ///
  /// In en, this message translates to:
  /// **'Add 30 seconds'**
  String get add30Semantics;

  /// Rest timer skip button semantics
  ///
  /// In en, this message translates to:
  /// **'Skip rest timer'**
  String get skipRestSemantics;

  /// Resume age: less than 1 hour
  ///
  /// In en, this message translates to:
  /// **'less than an hour ago'**
  String get lessThanAnHourAgo;

  /// Resume age: N hours ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String hoursAgo(int count);

  /// Resume age: yesterday at time
  ///
  /// In en, this message translates to:
  /// **'yesterday at {time}'**
  String yesterdayAt(String time);

  /// Resume age: weekday at time
  ///
  /// In en, this message translates to:
  /// **'{weekday} at {time}'**
  String weekdayAt(String weekday, String time);

  /// Workout history screen title
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// Error loading workout history
  ///
  /// In en, this message translates to:
  /// **'Failed to load history'**
  String get failedToLoadHistory;

  /// Empty history: title
  ///
  /// In en, this message translates to:
  /// **'No workouts yet'**
  String get noWorkoutsYet;

  /// Empty history: subtitle
  ///
  /// In en, this message translates to:
  /// **'Your completed workouts will appear here'**
  String get completedWorkoutsAppear;

  /// Empty history: CTA
  ///
  /// In en, this message translates to:
  /// **'Start your first workout'**
  String get startFirstWorkout;

  /// Error loading workout detail
  ///
  /// In en, this message translates to:
  /// **'Failed to load workout'**
  String get failedToLoadWorkout;

  /// Workout generic label
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get workout;

  /// Fallback exercise name when name is null
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get exerciseGeneric;

  /// Notes section label
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// Q1 notes-edit-after — tappable empty-state affordance on the workout-detail notes section, prompting the user to write a note for a past workout.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get addNote;

  /// Q1 notes-edit-after — character counter inside the notes edit field. Only shown near the cap (remaining <= 200).
  ///
  /// In en, this message translates to:
  /// **'{current} / {max}'**
  String notesCharCounter(int current, int max);

  /// PR #285 device-verification (UX-critic Q2) — label half of the 48dp surface2 strip below the exercise list on the workout-detail screen. Mirrors the top XP/PRs strip pattern. Rendered in AppTextStyles.label (Barlow Condensed tracked) at textDim alpha 0.6, paired with workoutDetailTotalVolumeValue (Rajdhani numeric) for the value.
  ///
  /// In en, this message translates to:
  /// **'Total volume'**
  String get workoutDetailTotalVolumeLabel;

  /// PR #285 device-verification (UX-critic Q2) — value half of the 48dp total-volume strip on the workout-detail screen. Passes through a pre-formatted volume string from WorkoutFormatters.formatVolume() which already includes the weight-unit suffix (e.g. '1,740 kg' / '1,740 lbs'). No additional formatting at the localization layer — keeps weight-unit handling centralized in the formatter.
  ///
  /// In en, this message translates to:
  /// **'{volume}'**
  String workoutDetailTotalVolumeValue(String volume);

  /// Routines screen title
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get routines;

  /// Error loading routines
  ///
  /// In en, this message translates to:
  /// **'Failed to load routines'**
  String get failedToLoadRoutines;

  /// Section header: my routines
  ///
  /// In en, this message translates to:
  /// **'MY ROUTINES'**
  String get myRoutinesSection;

  /// Section header: starter routines
  ///
  /// In en, this message translates to:
  /// **'STARTER ROUTINES'**
  String get starterRoutinesSection;

  /// One-time discoverability hint shown above the routine list explaining that long-pressing a routine card opens edit/delete.
  ///
  /// In en, this message translates to:
  /// **'Press and hold to edit'**
  String get hintRoutineLongPress;

  /// Routines empty-state headline, branded illustration. BUG-029.
  ///
  /// In en, this message translates to:
  /// **'No routines yet'**
  String get routinesEmptyTitle;

  /// Routines empty-state body copy, branded illustration. BUG-029.
  ///
  /// In en, this message translates to:
  /// **'Plan a workout sequence once and reuse it every session.'**
  String get routinesEmptyBody;

  /// Routines empty-state inline CTA — navigates to /routines/create. BUG-029.
  ///
  /// In en, this message translates to:
  /// **'Create routine'**
  String get routinesEmptyCta;

  /// Create routine screen title
  ///
  /// In en, this message translates to:
  /// **'Create Routine'**
  String get createRoutine;

  /// Edit routine screen title
  ///
  /// In en, this message translates to:
  /// **'Edit Routine'**
  String get editRoutine;

  /// Routine name field hint
  ///
  /// In en, this message translates to:
  /// **'Routine name'**
  String get routineName;

  /// Routine notes field placeholder; '(optional)' suffix signals the field is not required
  ///
  /// In en, this message translates to:
  /// **'Program intent, form cues, deload schedule… (optional)'**
  String get routineNotesHint;

  /// Eyebrow label for the routine notes header strip and read-only sheet during an active workout
  ///
  /// In en, this message translates to:
  /// **'TRAINING NOTES'**
  String get routineNotesEyebrow;

  /// Snackbar: routine save failed
  ///
  /// In en, this message translates to:
  /// **'Failed to save routine. Please retry.'**
  String get failedToSaveRoutine;

  /// Sets label in routine exercise card
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get setsLabel;

  /// Rest label in routine exercise card
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get restLabel;

  /// Routine action: duplicate and edit
  ///
  /// In en, this message translates to:
  /// **'Duplicate and Edit'**
  String get duplicateAndEdit;

  /// Delete routine dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Routine'**
  String get deleteRoutine;

  /// Delete routine confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteRoutineConfirm(String name);

  /// Number of exercises
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exercise} other{{count} exercises}}'**
  String exercisesCount(int count);

  /// Profile screen title
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Default display name
  ///
  /// In en, this message translates to:
  /// **'Gym User'**
  String get gymUser;

  /// Edit name dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit Display Name'**
  String get editDisplayName;

  /// Edit name field hint
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterYourName;

  /// Workouts stat label
  ///
  /// In en, this message translates to:
  /// **'Workouts'**
  String get workouts;

  /// Member since stat label
  ///
  /// In en, this message translates to:
  /// **'Member since'**
  String get memberSince;

  /// Weight unit section label
  ///
  /// In en, this message translates to:
  /// **'Weight Unit'**
  String get weightUnit;

  /// Weekly goal section label
  ///
  /// In en, this message translates to:
  /// **'Weekly Goal'**
  String get weeklyGoal;

  /// Section header: data management
  ///
  /// In en, this message translates to:
  /// **'DATA MANAGEMENT'**
  String get dataManagement;

  /// Manage data link
  ///
  /// In en, this message translates to:
  /// **'Manage Data'**
  String get manageData;

  /// Section header: legal
  ///
  /// In en, this message translates to:
  /// **'LEGAL'**
  String get legal;

  /// Crash reports toggle title
  ///
  /// In en, this message translates to:
  /// **'Send crash reports'**
  String get sendCrashReports;

  /// Crash reports toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Help improve RepSaga by sending anonymous crash data.'**
  String get crashReportsSubtitle;

  /// Log out confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logOutConfirm;

  /// Manage data screen title
  ///
  /// In en, this message translates to:
  /// **'Manage Data'**
  String get manageDataTitle;

  /// Delete history tile title
  ///
  /// In en, this message translates to:
  /// **'Delete Workout History'**
  String get deleteWorkoutHistory;

  /// Delete history subtitle — count is pre-formatted (may be '...' during loading)
  ///
  /// In en, this message translates to:
  /// **'{count} workouts will be removed'**
  String workoutsWillBeRemoved(String count);

  /// Reset all data tile title
  ///
  /// In en, this message translates to:
  /// **'Reset All Account Data'**
  String get resetAllAccountData;

  /// Reset all data subtitle
  ///
  /// In en, this message translates to:
  /// **'Removes everything. Permanent.'**
  String get resetAllSubtitle;

  /// Delete account tile title/dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// Delete account subtitle
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all data'**
  String get deleteAccountSubtitle;

  /// Delete history dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete all workout history?'**
  String get deleteAllHistoryTitle;

  /// Delete history dialog content
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all {count} workouts and cannot be undone.'**
  String deleteAllHistoryContent(int count);

  /// Delete history confirm button
  ///
  /// In en, this message translates to:
  /// **'Delete History'**
  String get deleteHistoryButton;

  /// Double confirm dialog title
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get areYouSure;

  /// Double confirm delete button
  ///
  /// In en, this message translates to:
  /// **'Yes, Delete'**
  String get yesDelete;

  /// Snackbar: history cleared
  ///
  /// In en, this message translates to:
  /// **'Workout history cleared'**
  String get historyCleared;

  /// Snackbar: clear history failed
  ///
  /// In en, this message translates to:
  /// **'Failed to clear history: {message}'**
  String failedToClearHistory(String message);

  /// Reset account data dialog title
  ///
  /// In en, this message translates to:
  /// **'Reset Account Data'**
  String get resetAccountData;

  /// Reset account warning text
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all workouts and personal records. Your routines and custom exercises will be kept. There is no undo.'**
  String get resetAccountWarning;

  /// Reset confirmation instruction
  ///
  /// In en, this message translates to:
  /// **'Type RESET to confirm'**
  String get typeResetToConfirm;

  /// Reset account confirm button
  ///
  /// In en, this message translates to:
  /// **'Reset Account'**
  String get resetAccountButton;

  /// Snackbar: account data reset
  ///
  /// In en, this message translates to:
  /// **'Account data reset'**
  String get accountDataReset;

  /// Snackbar: reset data failed
  ///
  /// In en, this message translates to:
  /// **'Failed to reset data: {message}'**
  String failedToResetData(String message);

  /// Delete account warning text
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account, all your workouts, personal records, routines, and custom exercises. This cannot be undone.'**
  String get deleteAccountWarning;

  /// Delete account confirmation instruction
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get typeDeleteToConfirm;

  /// Delete account confirm button
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountButton;

  /// Snackbar: delete account failed
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account: {message}'**
  String failedToDeleteAccount(String message);

  /// Delete history: second dialog content
  ///
  /// In en, this message translates to:
  /// **'Your personal records and routines will be kept.'**
  String get prsRoutinesKept;

  /// Section header: workout history
  ///
  /// In en, this message translates to:
  /// **'WORKOUT HISTORY'**
  String get workoutHistorySection;

  /// Legal PR 3 — section header above the Export my data tile on Manage Data. Distinct from the destructive 'DANGER' section below so the LGPD Art. 18 V / GDPR Art. 20 portability affordance reads as a benign read-only operation, not a wipe action.
  ///
  /// In en, this message translates to:
  /// **'YOUR DATA'**
  String get yourDataSection;

  /// Legal PR 3 — Manage Data tile title. Triggers the in-app JSON export the Privacy Policy §6 Portability row promises (Profile → Manage Data → Export my data → native share sheet).
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get exportMyData;

  /// Legal PR 3 — subtitle on the Export my data tile. Sets the expectation: a single JSON file, not a multi-format ZIP, delivered via the OS share sheet.
  ///
  /// In en, this message translates to:
  /// **'Download a JSON file of your account data.'**
  String get exportMyDataSubtitle;

  /// Legal PR 3 — loading-dialog body shown while the export aggregator fetches every user-owned table and serializes the JSON. The aggregation queries hit several tables and can take 2-5 seconds for users with rich history.
  ///
  /// In en, this message translates to:
  /// **'Preparing your data export…'**
  String get dataExportPreparing;

  /// Legal PR 3 — success snackbar shown when the JSON export has been handed to the native share sheet. The share sheet itself surfaces the file picker / target chooser; the snackbar simply confirms the export step completed.
  ///
  /// In en, this message translates to:
  /// **'Data export ready'**
  String get dataExportSuccess;

  /// Legal PR 3 — error snackbar shown when the JSON export pipeline fails (network error, serialization failure, share-plus platform error). The {message} placeholder is ExportException.userMessage — a safe, generic surface that never leaks the underlying Postgres / network detail to the UI (the dev log + Sentry still see the raw cause).
  ///
  /// In en, this message translates to:
  /// **'Failed to export data: {message}'**
  String dataExportFailed(String message);

  /// Section header: danger
  ///
  /// In en, this message translates to:
  /// **'DANGER'**
  String get dangerSection;

  /// Section header: privacy
  ///
  /// In en, this message translates to:
  /// **'PRIVACY'**
  String get privacySection;

  /// PRs stat label
  ///
  /// In en, this message translates to:
  /// **'PRs'**
  String get prsLabel;

  /// Training frequency display
  ///
  /// In en, this message translates to:
  /// **'{count}x per week'**
  String perWeekLabel(int count);

  /// Frequency picker question
  ///
  /// In en, this message translates to:
  /// **'How many times per week do you want to train?'**
  String get frequencyQuestion;

  /// Phase 24c — settings row label for the user's optional body weight (used to compute XP for bodyweight exercises).
  ///
  /// In en, this message translates to:
  /// **'Body weight'**
  String get profileBodyweightLabel;

  /// Phase 24c — settings row subtitle shown when the user has not yet entered a bodyweight.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileBodyweightNotSet;

  /// Phase 24c — bottom-sheet helper text explaining what the bodyweight value is used for.
  ///
  /// In en, this message translates to:
  /// **'Used to compute XP for bodyweight exercises like pull-ups, dips, push-ups.'**
  String get profileBodyweightHelper;

  /// Phase 24c — inline validation error when the entered bodyweight falls outside the allowed range. min/max are pre-formatted integers for the unit; unit is 'kg' or 'lbs'.
  ///
  /// In en, this message translates to:
  /// **'Enter a value between {min} and {max} {unit}'**
  String profileBodyweightInvalidRange(String min, String max, String unit);

  /// Phase 24c-8 — non-blocking SnackBar title shown the first time a user completes a set on a bodyweight exercise (pull-up, dip, push-up, etc.) when their profile has no bodyweight set. The XP for those exercises is computed from `effective_load = bodyweight + entered weight`; without bodyweight, the load undercounts. Voice: declarative, no exclamation, no preachy CTA — matches the rest of the in-workout snackbar copy.
  ///
  /// In en, this message translates to:
  /// **'Set your body weight for accurate XP'**
  String get bodyweightPromptTitle;

  /// Phase 24c-8 — explanatory body copy paired with `bodyweightPromptTitle`. Reserved for extended surfaces (future tooltip / onboarding card / settings hint) where the SnackBar's single-line constraint isn't binding. The active-workout SnackBar renders only the title to keep the bar at one line + two actions; this string is wired so post-launch UX revisions can add an info icon → tooltip without an l10n PR.
  ///
  /// In en, this message translates to:
  /// **'Bodyweight exercises like pull-ups and dips count your weight as part of the load.'**
  String get bodyweightPromptBody;

  /// Phase 24c-8 — primary action on the bodyweight prompt SnackBar. Tapping opens the bodyweight editor bottom sheet (reusing the profile-settings sheet from 24c-7). Short, imperative, parallel structure with `bodyweightPromptSkip`.
  ///
  /// In en, this message translates to:
  /// **'Set now'**
  String get bodyweightPromptSetNow;

  /// Phase 24c-8 — dismissive action on the bodyweight prompt SnackBar. Tapping records a forever-dismissal in Hive (`bodyweight_prompt_dismissed_at`); the prompt never re-appears. Distinct from the existing top-level `skip` key so this surface can be re-copied independently if voice review changes the wording.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get bodyweightPromptSkip;

  /// Generic retry message
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get pleaseTryAgain;

  /// PR list screen title
  ///
  /// In en, this message translates to:
  /// **'Personal Records'**
  String get personalRecordsTitle;

  /// Error loading PR list
  ///
  /// In en, this message translates to:
  /// **'Failed to load records'**
  String get failedToLoadRecords;

  /// Empty PR list: title
  ///
  /// In en, this message translates to:
  /// **'No Records Yet'**
  String get noRecordsYetTitle;

  /// Empty PR list: subtitle
  ///
  /// In en, this message translates to:
  /// **'Complete a workout to start tracking records'**
  String get completeWorkoutToTrack;

  /// Start workout CTA
  ///
  /// In en, this message translates to:
  /// **'Start Workout'**
  String get startWorkout;

  /// PR celebration: new PR heading
  ///
  /// In en, this message translates to:
  /// **'NEW PR'**
  String get newPrHeading;

  /// PR celebration: first workout title
  ///
  /// In en, this message translates to:
  /// **'First Workout Complete!'**
  String get firstWorkoutComplete;

  /// PR celebration: first workout subtitle
  ///
  /// In en, this message translates to:
  /// **'These are your starting benchmarks'**
  String get startingBenchmarks;

  /// Fallback exercise name
  ///
  /// In en, this message translates to:
  /// **'Unknown Exercise'**
  String get unknownExercise;

  /// Plan management screen title
  ///
  /// In en, this message translates to:
  /// **'This Week\'s Plan'**
  String get thisWeeksPlan;

  /// Overflow menu tooltip
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// Auto-fill menu option
  ///
  /// In en, this message translates to:
  /// **'Auto-fill'**
  String get autoFill;

  /// Clear week menu option
  ///
  /// In en, this message translates to:
  /// **'Clear Week'**
  String get clearWeek;

  /// Add routine row label
  ///
  /// In en, this message translates to:
  /// **'Add Routine'**
  String get addRoutine;

  /// Plan progress: at soft cap
  ///
  /// In en, this message translates to:
  /// **'{count}/{total} planned — ready to go'**
  String plannedReadyToGo(int count, int total);

  /// Plan progress: below soft cap
  ///
  /// In en, this message translates to:
  /// **'{count}/{total} planned this week'**
  String plannedThisWeek(int count, int total);

  /// Empty plan state
  ///
  /// In en, this message translates to:
  /// **'No routines planned this week'**
  String get noRoutinesPlanned;

  /// Add routines button
  ///
  /// In en, this message translates to:
  /// **'Add Routines'**
  String get addRoutines;

  /// Auto-fill replace dialog title
  ///
  /// In en, this message translates to:
  /// **'Replace current plan?'**
  String get replacePlanTitle;

  /// Auto-fill replace dialog content
  ///
  /// In en, this message translates to:
  /// **'Auto-fill will replace your current plan with your most-used routines.'**
  String get replacePlanContent;

  /// Clear week dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear Week'**
  String get clearWeekTitle;

  /// Clear week dialog content
  ///
  /// In en, this message translates to:
  /// **'Start fresh this week?'**
  String get clearWeekContent;

  /// Snackbar: routine removed from plan
  ///
  /// In en, this message translates to:
  /// **'Routine removed'**
  String get routineRemoved;

  /// Fallback routine name
  ///
  /// In en, this message translates to:
  /// **'Unknown Routine'**
  String get unknownRoutine;

  /// Add routines sheet title
  ///
  /// In en, this message translates to:
  /// **'Add Routines'**
  String get addRoutinesSheet;

  /// Hint: no more routines to add
  ///
  /// In en, this message translates to:
  /// **'Create more routines to add them here.'**
  String get createMoreRoutines;

  /// Add N routines button label
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{ADD 1 ROUTINE} other{ADD {count} ROUTINES}}'**
  String addCountRoutines(int count);

  /// AddRoutinesSheet inline action that pops the sheet and opens the routine-creation flow. Visually a text-link, not a tile.
  ///
  /// In en, this message translates to:
  /// **'Create new routine'**
  String get createNewRoutine;

  /// 1-second confirmation snackbar shown after the weekly plan autosaves. No spinner, no icon — just visible feedback that the edit landed.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedConfirmation;

  /// Tooltip on the discoverability copy-icon shown on set 2+ when the row's weight differs from the previous set's. Tapping copies the previous set's weight + reps.
  ///
  /// In en, this message translates to:
  /// **'Copy from previous set'**
  String get copyFromPreviousSet;

  /// Week review: complete header
  ///
  /// In en, this message translates to:
  /// **'WEEK COMPLETE'**
  String get weekComplete;

  /// Week review: in-progress header
  ///
  /// In en, this message translates to:
  /// **'THIS WEEK'**
  String get thisWeek;

  /// Week review: new week link
  ///
  /// In en, this message translates to:
  /// **'NEW WEEK'**
  String get newWeekLink;

  /// Week review: session count
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String sessionsCount(int count);

  /// Week review: PR count
  ///
  /// In en, this message translates to:
  /// **'{count} PRs'**
  String prsCount(int count);

  /// Add routine to plan prompt
  ///
  /// In en, this message translates to:
  /// **'{name} isn\'t in your plan yet. Add it?'**
  String addToPlanPrompt(String name);

  /// Sync failure: one workout
  ///
  /// In en, this message translates to:
  /// **'Workout couldn\'t sync'**
  String get syncFailureSingular;

  /// Sync failure: multiple workouts
  ///
  /// In en, this message translates to:
  /// **'{count} workouts couldn\'t sync'**
  String syncFailurePlural(int count);

  /// Sync failure subtitle
  ///
  /// In en, this message translates to:
  /// **'Saved locally. Retry or dismiss.'**
  String get savedLocallyRetry;

  /// Snackbar: retry blocked while offline
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — retry when back online'**
  String get offlineRetryHint;

  /// Pending sync sheet title
  ///
  /// In en, this message translates to:
  /// **'Pending Sync'**
  String get pendingSyncTitle;

  /// Item count in pending sync sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemCount(int count);

  /// Empty pending sync sheet
  ///
  /// In en, this message translates to:
  /// **'All synced!'**
  String get allSynced;

  /// Snackbar: sync success
  ///
  /// In en, this message translates to:
  /// **'Synced successfully.'**
  String get syncedSuccessfully;

  /// Pending action: save workout
  ///
  /// In en, this message translates to:
  /// **'Save workout'**
  String get pendingActionSaveWorkout;

  /// Pending action: update records
  ///
  /// In en, this message translates to:
  /// **'Update records'**
  String get pendingActionUpdateRecords;

  /// Pending action: mark routine complete
  ///
  /// In en, this message translates to:
  /// **'Mark routine complete'**
  String get pendingActionMarkComplete;

  /// Pending action queued time
  ///
  /// In en, this message translates to:
  /// **'Queued at {time}'**
  String queuedAt(String time);

  /// Pending action retry count
  ///
  /// In en, this message translates to:
  /// **'{count} retries'**
  String retryCount(int count);

  /// User-safe sync error for transient/structural failures (Postgrest FK/unique violations, type-cast errors, RLS denials). Raw exception goes to logs, never to UI. BUG-042.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync right now. We\'ll retry shortly.'**
  String get syncErrorRetryGeneric;

  /// User-safe sync error for network/timeout/socket failures. The data is safe in the queue. BUG-042.
  ///
  /// In en, this message translates to:
  /// **'No connection. Your data will sync when you\'re back online.'**
  String get syncErrorOffline;

  /// User-safe sync error for authentication failures (Supabase AuthException). BUG-042.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please log in again.'**
  String get syncErrorSessionExpired;

  /// Generic fallback for unknown sync errors — used by SyncErrorMapper when no other classifier matches. BUG-042.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. We\'ll retry shortly.'**
  String get syncErrorUnknown;

  /// User-safe sync error body for structural failures that retry won't fix (FK violations, type-cast crashes, expired sessions). Shown alongside the Dismiss CTA. BUG-008.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send this — please contact support.'**
  String get syncErrorStructuralBody;

  /// CTA on the pending-sync sheet for structural errors that can't be fixed by retrying. BUG-008.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get syncDismissAction;

  /// Pending sync badge: one workout
  ///
  /// In en, this message translates to:
  /// **'1 workout pending sync'**
  String get pendingSyncBadgeSingular;

  /// Pending sync badge: multiple workouts
  ///
  /// In en, this message translates to:
  /// **'{count} workouts pending sync'**
  String pendingSyncBadgePlural(int count);

  /// Pending sync badge accessibility label, composed from the visible badge text plus the action hint. BUG-021.
  ///
  /// In en, this message translates to:
  /// **'{label}. Tap to manage.'**
  String pendingSyncBadgeSemantics(String label);

  /// Exercise picker: empty result
  ///
  /// In en, this message translates to:
  /// **'No exercises found'**
  String get noExercisesFound;

  /// Exercise picker: load error
  ///
  /// In en, this message translates to:
  /// **'Failed to load exercises'**
  String get failedToLoadExercises;

  /// Duration format: less than 1 minute
  ///
  /// In en, this message translates to:
  /// **'< 1m'**
  String get durationLessThanOneMin;

  /// Weight input dialog title
  ///
  /// In en, this message translates to:
  /// **'Enter weight'**
  String get enterWeight;

  /// OK button label
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Reps input dialog title
  ///
  /// In en, this message translates to:
  /// **'Enter reps'**
  String get enterReps;

  /// Error loading legal document
  ///
  /// In en, this message translates to:
  /// **'Failed to load document'**
  String get failedToLoadDocument;

  /// Discard workout tooltip
  ///
  /// In en, this message translates to:
  /// **'Discard workout'**
  String get discardWorkout;

  /// Move exercise up tooltip
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// Move exercise down tooltip
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// Swap exercise tooltip
  ///
  /// In en, this message translates to:
  /// **'Swap exercise'**
  String get swapExercise;

  /// Remove exercise tooltip
  ///
  /// In en, this message translates to:
  /// **'Remove exercise'**
  String get removeExercise;

  /// PR-3 Q3 — confirm dialog title shown when the user tries to swap an exercise that already has one or more completed sets. Uses the concrete new-exercise name (per UI critic guidance: never 'the new exercise').
  ///
  /// In en, this message translates to:
  /// **'Swap to {newExercise}?'**
  String swapExerciseConfirmTitle(String newExercise);

  /// PR-3 Q3 — confirm dialog body explaining that completed sets re-attribute to the new exercise's PR history. Uses concrete names on both sides + the count of logged sets.
  ///
  /// In en, this message translates to:
  /// **'Swapping from {oldExercise}: your {count} logged {count, plural, one{set} other{sets}} will move to {newExercise}\'s PR history.'**
  String swapExerciseConfirmBody(
    int count,
    String newExercise,
    String oldExercise,
  );

  /// PR-3 Q3 — confirm-side action label on the swap-exercise confirm dialog. Distinct from the generic `swapExercise` (used as tooltip on the icon button) so we can keep the verb tight in dialog chrome.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swapExerciseConfirmAction;

  /// PR-3 H5 — undo snackbar text shown for ~4 seconds after adding an exercise from the picker. Pairs with an `Undo` action that calls `restoreExercise` to revert. Scoped to the ADD path only — swap has its own confirm (Q3).
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String addExerciseUndo(String name);

  /// Chart time window: last 30 days
  ///
  /// In en, this message translates to:
  /// **'30d'**
  String get last30Days;

  /// Chart time window: last 90 days
  ///
  /// In en, this message translates to:
  /// **'90d'**
  String get last90Days;

  /// Chart time window: all time
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// Accessibility label for metric cycle button
  ///
  /// In en, this message translates to:
  /// **'Switch metric to {metric}'**
  String switchMetricTo(String metric);

  /// Chart error: failed to load progress data
  ///
  /// In en, this message translates to:
  /// **'Could not load progress'**
  String get couldNotLoadProgress;

  /// Chart empty state: no data yet
  ///
  /// In en, this message translates to:
  /// **'Log your first set to start tracking'**
  String get logFirstSetToTrack;

  /// Chart metric label: estimated one-rep max
  ///
  /// In en, this message translates to:
  /// **'e1RM'**
  String get chartMetricE1rm;

  /// Chart metric label: raw weight
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get chartMetricWeight;

  /// Chart window label: 30 days
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get chartWindowDays30;

  /// Chart window label: 90 days
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get chartWindowDays90;

  /// Chart window label: all time
  ///
  /// In en, this message translates to:
  /// **'all time'**
  String get chartWindowAllTime;

  /// Chart trend: N workouts logged with no trend direction
  ///
  /// In en, this message translates to:
  /// **'{count} workouts logged — keep going'**
  String workoutsLoggedKeepGoing(int count);

  /// Chart trend: 1 workout logged
  ///
  /// In en, this message translates to:
  /// **'1 workout logged — keep going'**
  String get oneWorkoutLoggedKeepGoing;

  /// Chart trend: no change
  ///
  /// In en, this message translates to:
  /// **'Holding steady at {weight} {unit}'**
  String holdingSteadyAt(String weight, String unit);

  /// Chart trend: positive delta
  ///
  /// In en, this message translates to:
  /// **'Up {weight} {unit} in {window}'**
  String trendUp(String weight, String unit, String window);

  /// Chart trend: negative delta
  ///
  /// In en, this message translates to:
  /// **'Down {weight} {unit} in {window}'**
  String trendDown(String weight, String unit, String window);

  /// Accessibility: PR ring anchor label
  ///
  /// In en, this message translates to:
  /// **'PR marker at {weight} {unit}'**
  String prMarkerAt(String weight, String unit);

  /// Set row accessibility: set number with type info
  ///
  /// In en, this message translates to:
  /// **'Set {number}. Long press to change type: {type}'**
  String setNumberSemantics(int number, String type);

  /// Set row accessibility: set number with copy hint and type info
  ///
  /// In en, this message translates to:
  /// **'Set {number}. Tap to copy previous set. Long press to change type: {type}'**
  String setNumberCopySemantics(int number, String type);

  /// Set row tooltip: tap to copy, hold to change type
  ///
  /// In en, this message translates to:
  /// **'Tap: copy last set\nHold: change type'**
  String get tooltipCopyLastSetAndChangeType;

  /// Set row tooltip: hold to change type
  ///
  /// In en, this message translates to:
  /// **'Hold: change type'**
  String get tooltipChangeType;

  /// Accessibility: set completion checkbox label (completed)
  ///
  /// In en, this message translates to:
  /// **'Set completed'**
  String get setCompleted;

  /// Accessibility: set completion checkbox label (not completed)
  ///
  /// In en, this message translates to:
  /// **'Mark set as done'**
  String get markSetAsDone;

  /// Accessibility: set completion checkbox label when the row is in the predicted-PR state (current weight/reps would beat the standing record). Replaces the plain 'Mark set as done' so screen-reader users hear the achievement preview before tapping. Phase 20 commit 4.
  ///
  /// In en, this message translates to:
  /// **'Mark set as done — predicted record'**
  String get markSetAsDonePredictedPr;

  /// Tooltip: enter reorder mode
  ///
  /// In en, this message translates to:
  /// **'Reorder exercises'**
  String get reorderExercisesTooltip;

  /// Tooltip: exit reorder mode
  ///
  /// In en, this message translates to:
  /// **'Exit reorder mode'**
  String get exitReorderModeTooltip;

  /// Exercise card accessibility label in active workout. PR-3 (H2/Q6) — the long-press-to-swap shortcut was removed; the visible swap_horiz icon button is the sole entry point. The label no longer mentions long-press.
  ///
  /// In en, this message translates to:
  /// **'Exercise: {name}. Tap for details.'**
  String exerciseSemanticsLabel(String name);

  /// Accessibility: fill remaining sets button
  ///
  /// In en, this message translates to:
  /// **'Fill all uncompleted sets with last completed values'**
  String get fillRemainingSetsSemantics;

  /// Accessibility: add exercise FAB
  ///
  /// In en, this message translates to:
  /// **'Add exercise to workout'**
  String get addExerciseToWorkoutSemantics;

  /// Accessibility: exercise picker search
  ///
  /// In en, this message translates to:
  /// **'Search exercises to add'**
  String get searchExercisesToAddSemantics;

  /// Accessibility: add specific exercise from picker
  ///
  /// In en, this message translates to:
  /// **'Add {name}'**
  String addExerciseSemantics(String name);

  /// Set type abbreviation: working
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get setTypeAbbrWorking;

  /// Set type abbreviation: warm-up
  ///
  /// In en, this message translates to:
  /// **'WU'**
  String get setTypeAbbrWarmup;

  /// Set type abbreviation: drop set
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get setTypeAbbrDropset;

  /// Set type abbreviation: to failure
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get setTypeAbbrFailure;

  /// Set type abbreviation: warm-up (detail view)
  ///
  /// In en, this message translates to:
  /// **'Wu'**
  String get setTypeAbbrWarmupShort;

  /// Accessibility: last session line
  ///
  /// In en, this message translates to:
  /// **'Last session: {name}, {date}'**
  String lastSessionSemantics(String name, String date);

  /// Accessibility: exercise list search
  ///
  /// In en, this message translates to:
  /// **'Search exercises'**
  String get searchExercisesSemantics;

  /// Accessibility: exercise list item
  ///
  /// In en, this message translates to:
  /// **'Exercise: {name}'**
  String exerciseItemSemantics(String name);

  /// Accessibility prefix for muscle group picker
  ///
  /// In en, this message translates to:
  /// **'Muscle group'**
  String get muscleGroupSemanticsPrefix;

  /// Accessibility prefix for equipment type picker
  ///
  /// In en, this message translates to:
  /// **'Equipment type'**
  String get equipmentTypeSemanticsPrefix;

  /// Accessibility: delete exercise button
  ///
  /// In en, this message translates to:
  /// **'Delete exercise'**
  String get deleteExerciseSemantics;

  /// Validation: exercise name already exists
  ///
  /// In en, this message translates to:
  /// **'An exercise with this name already exists'**
  String get exerciseNameDuplicate;

  /// Short relative date: N days ago
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgoShort(int count);

  /// Short relative date: N weeks ago
  ///
  /// In en, this message translates to:
  /// **'{count}w ago'**
  String weeksAgoShort(int count);

  /// Short relative date: N months ago
  ///
  /// In en, this message translates to:
  /// **'{count}mo ago'**
  String monthsAgoShort(int count);

  /// Default routine name: Push Day
  ///
  /// In en, this message translates to:
  /// **'Push Day'**
  String get routineNamePushDay;

  /// Default routine name: Pull Day
  ///
  /// In en, this message translates to:
  /// **'Pull Day'**
  String get routineNamePullDay;

  /// Default routine name: Leg Day
  ///
  /// In en, this message translates to:
  /// **'Leg Day'**
  String get routineNameLegDay;

  /// Default routine name: Full Body
  ///
  /// In en, this message translates to:
  /// **'Full Body'**
  String get routineNameFullBody;

  /// Default routine name: Upper/Lower — Upper
  ///
  /// In en, this message translates to:
  /// **'Upper/Lower — Upper'**
  String get routineNameUpperLowerUpper;

  /// Default routine name: Upper/Lower — Lower
  ///
  /// In en, this message translates to:
  /// **'Upper/Lower — Lower'**
  String get routineNameUpperLowerLower;

  /// Default routine name: 5x5 Strength
  ///
  /// In en, this message translates to:
  /// **'5x5 Strength'**
  String get routineNameFiveByFiveStrength;

  /// Default routine name: Full Body Beginner
  ///
  /// In en, this message translates to:
  /// **'Full Body Beginner'**
  String get routineNameFullBodyBeginner;

  /// Default routine name: Arms & Abs
  ///
  /// In en, this message translates to:
  /// **'Arms & Abs'**
  String get routineNameArmsAndAbs;

  /// Section header: preferences
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get preferences;

  /// Language preference row label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Saga intro overlay, step 1 hero headline
  ///
  /// In en, this message translates to:
  /// **'YOUR TRAINING IS YOUR CHARACTER'**
  String get sagaIntroStep1Title;

  /// Saga intro overlay, step 1 body copy
  ///
  /// In en, this message translates to:
  /// **'Every set you complete shapes who you become. Lift, track, level up.'**
  String get sagaIntroStep1Body;

  /// Saga intro overlay, step 2 hero headline
  ///
  /// In en, this message translates to:
  /// **'XP FROM EVERY SET, PR, QUEST'**
  String get sagaIntroStep2Title;

  /// Saga intro overlay, step 2 body copy
  ///
  /// In en, this message translates to:
  /// **'Volume, intensity, personal records and weekly quests all grant XP.'**
  String get sagaIntroStep2Body;

  /// Saga intro overlay, step 3 hero headline with the user's starting level and rank
  ///
  /// In en, this message translates to:
  /// **'LVL {level} — {rank}'**
  String sagaIntroStep3Title(int level, String rank);

  /// Saga intro overlay, step 3 body copy
  ///
  /// In en, this message translates to:
  /// **'Your journey begins here. Keep training to climb ranks.'**
  String get sagaIntroStep3Body;

  /// Saga intro overlay primary button, non-final steps
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get sagaIntroNext;

  /// Saga intro overlay primary button, final step (dismisses)
  ///
  /// In en, this message translates to:
  /// **'BEGIN'**
  String get sagaIntroBegin;

  /// Saga intro overlay skip button label, top-right of the step indicator. Calls onDismiss directly. BUG-025.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get sagaIntroSkip;

  /// Rank name: rookie
  ///
  /// In en, this message translates to:
  /// **'ROOKIE'**
  String get sagaRankRookie;

  /// Rank name: iron
  ///
  /// In en, this message translates to:
  /// **'IRON'**
  String get sagaRankIron;

  /// Rank name: copper
  ///
  /// In en, this message translates to:
  /// **'COPPER'**
  String get sagaRankCopper;

  /// Rank name: silver
  ///
  /// In en, this message translates to:
  /// **'SILVER'**
  String get sagaRankSilver;

  /// Rank name: gold
  ///
  /// In en, this message translates to:
  /// **'GOLD'**
  String get sagaRankGold;

  /// Rank name: platinum
  ///
  /// In en, this message translates to:
  /// **'PLATINUM'**
  String get sagaRankPlatinum;

  /// Rank name: diamond
  ///
  /// In en, this message translates to:
  /// **'DIAMOND'**
  String get sagaRankDiamond;

  /// Phase 18c standalone uppercase noun for the rank-up overlay composition (body-part / RANK / numeral). The rank-up overlay needs to wrap only the numeral in RewardAccent, so the heading is composed from three pieces rather than rendered as one localized string.
  ///
  /// In en, this message translates to:
  /// **'RANK'**
  String get rankWord;

  /// Phase 18c character level-up overlay headline. Numeral 64sp Rajdhani 700 in heroGold.
  ///
  /// In en, this message translates to:
  /// **'LEVEL {level}'**
  String levelUpHeading(int level);

  /// Phase 18c first-awakening overlay copy (zero-history onboarding moment, 800ms).
  ///
  /// In en, this message translates to:
  /// **'{bodyPart} AWAKENS'**
  String firstAwakeningHeading(String bodyPart);

  /// Phase 18c title-unlock half-sheet rank label (small caps tracking line above the title name) for body-part titles.
  ///
  /// In en, this message translates to:
  /// **'{bodyPart} · RANK {rank} TITLE'**
  String titleUnlockRankLabel(String bodyPart, int rank);

  /// Phase 18e title-unlock half-sheet sub-label for character-level titles (Wanderer at lvl 10, Saga-Eternal at lvl 148, ...).
  ///
  /// In en, this message translates to:
  /// **'CHARACTER LEVEL {level}'**
  String titleUnlockCharacterLevelLabel(int level);

  /// Phase 18e title-unlock half-sheet sub-label for cross-build distinction titles (Pillar-Walker, Saga-Forged, ...). The label is fixed (not parameterized) because the trigger predicates aren't user-meaningful at the unlock moment — the flavor copy carries the why.
  ///
  /// In en, this message translates to:
  /// **'DISTINCTION TITLE'**
  String get titleUnlockCrossBuildLabel;

  /// Phase 18c title-unlock half-sheet primary CTA.
  ///
  /// In en, this message translates to:
  /// **'EQUIP TITLE'**
  String get equipTitleButton;

  /// Phase 18c label on the title-unlock half-sheet when the title is already the active one.
  ///
  /// In en, this message translates to:
  /// **'EQUIPPED'**
  String get equippedLabel;

  /// Phase 18c inline mid-set PR chip label (heroGold via RewardAccent). Identical in both locales.
  ///
  /// In en, this message translates to:
  /// **'PR'**
  String get prChipLabel;

  /// Phase 18c active-workout AppBar trailing OutlinedButton label.
  ///
  /// In en, this message translates to:
  /// **'FINISH'**
  String get finishButtonLabel;

  /// PR-5 H6 — helper text shown beneath the disabled FINISH button explaining why it cannot be tapped. Hidden once the button becomes enabled.
  ///
  /// In en, this message translates to:
  /// **'Complete at least one set to finish.'**
  String get finishWorkoutDisabledHint;

  /// Phase 18c active-workout FAB label (replaces the Finish-FAB, freed by moving Finish to the AppBar).
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get addExerciseFabLabel;

  /// Phase 18c condensed overflow card after the cap-at-3 rule trims rank-ups. Tapping opens the Saga screen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 more rank-up — open Saga} other{{count} more rank-ups — open Saga}}'**
  String celebrationOverflowLabel(int count);

  /// Phase 18c muted hint below the overflow card copy that signals the entire card is tappable to dismiss and continue.
  ///
  /// In en, this message translates to:
  /// **'Tap to continue'**
  String get celebrationOverflowTapHint;

  /// Phase 18c titles screen AppBar title.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get titlesScreenTitle;

  /// Phase 18c titles screen empty-state copy when no titles have been unlocked yet.
  ///
  /// In en, this message translates to:
  /// **'Earn your first title by ranking up a body part.'**
  String get titlesEmptyState;

  /// Phase 18c titles screen progress header — earned vs total catalog count.
  ///
  /// In en, this message translates to:
  /// **'{earned} of {total} earned'**
  String titlesProgressLabel(int earned, int total);

  /// Phase 18c titles screen per-row rank threshold breadcrumb (under each title name).
  ///
  /// In en, this message translates to:
  /// **'Rank {rank}'**
  String titlesRowRankThreshold(int rank);

  /// Phase 18e titles screen per-row character-level threshold breadcrumb (under each character-level title name).
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String titlesRowCharacterLevel(int level);

  /// Phase 18e titles screen per-row sub-label for cross-build distinction titles. Fixed (not parameterized) since the trigger predicate isn't user-meaningful at the row level — flavor copy carries the why.
  ///
  /// In en, this message translates to:
  /// **'Distinction'**
  String get titlesRowCrossBuild;

  /// Phase 18e titles screen section header for character-level titles (lvl 10/25/50/75/100/125/148).
  ///
  /// In en, this message translates to:
  /// **'CHARACTER LEVEL'**
  String get titlesSectionCharacterLevel;

  /// Phase 18e titles screen section header for cross-build distinction titles (Pillar-Walker, Saga-Forged, etc.).
  ///
  /// In en, this message translates to:
  /// **'DISTINCTION'**
  String get titlesSectionCrossBuild;

  /// Titles screen region header for the currently-equipped title.
  ///
  /// In en, this message translates to:
  /// **'Equipped'**
  String get titlesRegionEquipped;

  /// Titles screen region header for titles the user has already unlocked but is not currently wearing.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get titlesRegionEarned;

  /// Titles screen region header for upcoming locked titles closest to unlock.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get titlesRegionNext;

  /// Per-row CTA button label that equips an already-earned title as the active one.
  ///
  /// In en, this message translates to:
  /// **'Equip'**
  String get titlesRowEquipCta;

  /// Small inline tag/badge shown on the currently-equipped title row to indicate it is the one in use.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get titlesEquippedTag;

  /// Localized scope label used in place of a body-part name for character-level titles (e.g. on the equipped card, earned-row meta line). Stays consistent with `titlesNextSubCharacter*`.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get titlesCharacterLabel;

  /// Compact counter pill shown at the top of the Titles screen — earned vs total catalog count.
  ///
  /// In en, this message translates to:
  /// **'{earned} / {total} earned'**
  String titlesCounterPill(int earned, int total);

  /// Sub-line under a body-part-driven next title showing how many ranks remain. Plural form (remaining >= 2).
  ///
  /// In en, this message translates to:
  /// **'{bodyPart} · {remaining} ranks to go'**
  String titlesNextSubBodyPart(String bodyPart, int remaining);

  /// Sub-line under a body-part-driven next title when exactly one rank remains. Singular form.
  ///
  /// In en, this message translates to:
  /// **'{bodyPart} · 1 rank to go'**
  String titlesNextSubBodyPartOne(String bodyPart);

  /// Sub-line under a character-level-driven next title showing how many character levels remain. Plural form (remaining >= 2).
  ///
  /// In en, this message translates to:
  /// **'Character · {remaining} levels to go'**
  String titlesNextSubCharacter(int remaining);

  /// Sub-line under a character-level-driven next title when exactly one level remains. Singular form.
  ///
  /// In en, this message translates to:
  /// **'Character · 1 level to go'**
  String get titlesNextSubCharacterOne;

  /// Cross-build distinction card label used to flag these titles as special / rare relative to the per-body-part ladder.
  ///
  /// In en, this message translates to:
  /// **'Special'**
  String get titlesCrossBuildEspecial;

  /// Cross-build distinction card bottleneck line surfacing the single nearest blocking body-part rank.
  ///
  /// In en, this message translates to:
  /// **'◆ 1 rank to go in {bodyPart}'**
  String titlesCrossBuildBottleneck(String bodyPart);

  /// BUG-011 class-change overlay tagline for CharacterClass.initiate. Short declarative phrase, lowercase. Brand voice: masculine-emphatic. Used as `classChangeOverlayHeadline(className, tagline)` formatting.
  ///
  /// In en, this message translates to:
  /// **'the path begins'**
  String get classTaglineInitiate;

  /// BUG-011 class-change overlay tagline for CharacterClass.berserker (arms-dominant).
  ///
  /// In en, this message translates to:
  /// **'the fury answers'**
  String get classTaglineBerserker;

  /// BUG-011 class-change overlay tagline for CharacterClass.bulwark (chest-dominant). PO example.
  ///
  /// In en, this message translates to:
  /// **'the pillar moves'**
  String get classTaglineBulwark;

  /// BUG-011 class-change overlay tagline for CharacterClass.sentinel (back-dominant). PO example.
  ///
  /// In en, this message translates to:
  /// **'the watcher wakes'**
  String get classTaglineSentinel;

  /// BUG-011 class-change overlay tagline for CharacterClass.pathfinder (legs-dominant).
  ///
  /// In en, this message translates to:
  /// **'the ground holds'**
  String get classTaglinePathfinder;

  /// BUG-011 class-change overlay tagline for CharacterClass.atlas (shoulders-dominant). Brand voice update (Cluster-3 review 2026-05-02): 'the sky bends' read as too soft for a shoulder-dominant archetype; 'the shoulder carries' is direct + load-bearing.
  ///
  /// In en, this message translates to:
  /// **'the shoulder carries'**
  String get classTaglineAtlas;

  /// BUG-011 class-change overlay tagline for CharacterClass.anchor (core-dominant).
  ///
  /// In en, this message translates to:
  /// **'the line holds'**
  String get classTaglineAnchor;

  /// BUG-011 class-change overlay tagline for CharacterClass.ascendant (balanced — rare, prestigious). Brand voice update (Cluster-3 review 2026-05-02): 'the balance is rare' was a state, not an action; 'the balance was conquered' is declarative past-tense as completed mastery, matching the action-driven voice of the other taglines.
  ///
  /// In en, this message translates to:
  /// **'the balance was conquered'**
  String get classTaglineAscendant;

  /// BUG-011 class-change overlay subtitle (Inter 14sp textDim) — appears at t=1400-1600ms beneath the class name.
  ///
  /// In en, this message translates to:
  /// **'Your journey has earned a name.'**
  String get classChangeOverlaySubtitle;

  /// BUG-011 class-change overlay previous-class line. Only shown on the Initiate→first transition; later class-changes don't surface fromClass. Lowercase 'before' is intentional — reads as a footnote, not a heading.
  ///
  /// In en, this message translates to:
  /// **'before: {className}'**
  String classChangePreviousLabel(String className);

  /// BUG-011 condensed overflow line when multiple class changes fire in one workout — exceedingly rare (would require multiple class crosses in a single finish). Singular 'class change' is correct since {count} is always 1+ additional after the first overlay fires; English doesn't pluralize 'change' here.
  ///
  /// In en, this message translates to:
  /// **'+{count} more class change'**
  String classChangeOverflowMore(int count);

  /// BUG-014 cross-build progress hint for broad_shouldered. Surfaces only the smallest gap among the three upper guards (chest/back/shoulders). {gap} is the rank delta to the next floor; {muscleName} is the localized body-part name (e.g. 'shoulders').
  ///
  /// In en, this message translates to:
  /// **'Master the upper pillars — chest, back, and shoulders above rank 30, with clear dominance over the lower body. {gap} more rank in {muscleName}.'**
  String crossBuildHintBroadShouldered(int gap, String muscleName);

  /// BUG-014 cross-build progress hint for pillar_walker. Single body-part gap (always legs) — the predicate has a hard floor of 40 on legs.
  ///
  /// In en, this message translates to:
  /// **'Your legs must speak louder than your arms. {gap} more rank in legs.'**
  String crossBuildHintPillarWalker(int gap);

  /// BUG-014 cross-build progress hint for even_handed. Surfaces the single body part furthest from rank 30 (the floor every track must clear).
  ///
  /// In en, this message translates to:
  /// **'Every muscle at the same level — no weak link. {gap} more rank in {muscleName}.'**
  String crossBuildHintEvenHanded(int gap, String muscleName);

  /// BUG-014 cross-build progress hint for iron_bound. Surfaces the smallest gap among the big three (chest/back/legs).
  ///
  /// In en, this message translates to:
  /// **'Chest, back, legs — the three pillars above rank 60. {gap} more rank in {muscleName}.'**
  String crossBuildHintIronBound(int gap, String muscleName);

  /// BUG-014 cross-build progress hint for saga_forged. Surfaces the single body part furthest from rank 60 (the floor every track must clear).
  ///
  /// In en, this message translates to:
  /// **'The end of the journey starts here — every attribute above rank 60. {gap} more rank in {muscleName}.'**
  String crossBuildHintSagaForged(int gap, String muscleName);

  /// BUG-014 fallback for cross-build hints when the predicate evaluates true but the title hasn't been awarded yet (rare race window between award and UI refresh).
  ///
  /// In en, this message translates to:
  /// **'All conditions met — predicate satisfied.'**
  String get crossBuildHintSatisfied;

  /// Phase 18c chest R5 title display name.
  ///
  /// In en, this message translates to:
  /// **'Initiate of the Forge'**
  String get title_chest_r5_initiate_of_the_forge_name;

  /// Phase 18c chest R5 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'First sparks struck against iron.'**
  String get title_chest_r5_initiate_of_the_forge_flavor;

  /// Phase 18c chest R10 title display name.
  ///
  /// In en, this message translates to:
  /// **'Plate-Bearer'**
  String get title_chest_r10_plate_bearer_name;

  /// Phase 18c chest R10 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The bar trusts your collarbone now.'**
  String get title_chest_r10_plate_bearer_flavor;

  /// Phase 18c chest R15 title display name.
  ///
  /// In en, this message translates to:
  /// **'Forge-Marked'**
  String get title_chest_r15_forge_marked_name;

  /// Phase 18c chest R15 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Heat lives where your sternum meets the iron.'**
  String get title_chest_r15_forge_marked_flavor;

  /// Phase 18c chest R20 title display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Chested'**
  String get title_chest_r20_iron_chested_name;

  /// Phase 18c chest R20 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Plate after plate, the rib-cage answers.'**
  String get title_chest_r20_iron_chested_flavor;

  /// Phase 18c chest R25 title display name.
  ///
  /// In en, this message translates to:
  /// **'Anvil-Heart'**
  String get title_chest_r25_anvil_heart_name;

  /// Phase 18c chest R25 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Hammered, never bent.'**
  String get title_chest_r25_anvil_heart_flavor;

  /// Phase 18c chest R30 title display name.
  ///
  /// In en, this message translates to:
  /// **'Forge-Born'**
  String get title_chest_r30_forge_born_name;

  /// Phase 18c chest R30 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Older lifters look for the cracks. There aren\'t any.'**
  String get title_chest_r30_forge_born_flavor;

  /// Phase 18c chest R40 title display name.
  ///
  /// In en, this message translates to:
  /// **'Bulwark-Chested'**
  String get title_chest_r40_bulwark_chested_name;

  /// Phase 18c chest R40 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Walls do not flex. Neither do you.'**
  String get title_chest_r40_bulwark_chested_flavor;

  /// Phase 18c chest R50 title display name.
  ///
  /// In en, this message translates to:
  /// **'Forge-Plated'**
  String get title_chest_r50_forge_plated_name;

  /// Phase 18c chest R50 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Armour the bar wears down to your shape.'**
  String get title_chest_r50_forge_plated_flavor;

  /// Phase 18c chest R60 title display name.
  ///
  /// In en, this message translates to:
  /// **'Anvil-Forged'**
  String get title_chest_r60_anvil_forged_name;

  /// Phase 18c chest R60 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Ten thousand reps, one shape.'**
  String get title_chest_r60_anvil_forged_flavor;

  /// Phase 18c chest R70 title display name.
  ///
  /// In en, this message translates to:
  /// **'Forge-Heart'**
  String get title_chest_r70_forge_heart_name;

  /// Phase 18c chest R70 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The fire kept burning where most went out.'**
  String get title_chest_r70_forge_heart_flavor;

  /// Phase 18c chest R80 title display name.
  ///
  /// In en, this message translates to:
  /// **'Heart of the Forge'**
  String get title_chest_r80_heart_of_forge_name;

  /// Phase 18c chest R80 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Without you, the steel goes cold.'**
  String get title_chest_r80_heart_of_forge_flavor;

  /// Phase 18c chest R90 title display name.
  ///
  /// In en, this message translates to:
  /// **'Forge-Untouched'**
  String get title_chest_r90_forge_untouched_name;

  /// Phase 18c chest R90 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Heat passes through. Nothing marks you.'**
  String get title_chest_r90_forge_untouched_flavor;

  /// Phase 18c chest R99 terminal title display name.
  ///
  /// In en, this message translates to:
  /// **'The Anvil'**
  String get title_chest_r99_the_anvil_name;

  /// Phase 18c chest R99 terminal title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Every plate in this gym took its shape from you.'**
  String get title_chest_r99_the_anvil_flavor;

  /// Phase 18c back R5 title display name.
  ///
  /// In en, this message translates to:
  /// **'Lattice-Touched'**
  String get title_back_r5_lattice_touched_name;

  /// Phase 18c back R5 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Wings begin under the skin first.'**
  String get title_back_r5_lattice_touched_flavor;

  /// Phase 18c back R10 title display name.
  ///
  /// In en, this message translates to:
  /// **'Wing-Marked'**
  String get title_back_r10_wing_marked_name;

  /// Phase 18c back R10 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The shadow on the floor is wider than yesterday.'**
  String get title_back_r10_wing_marked_flavor;

  /// Phase 18c back R15 title display name.
  ///
  /// In en, this message translates to:
  /// **'Rope-Hauler'**
  String get title_back_r15_rope_hauler_name;

  /// Phase 18c back R15 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Whatever\'s hanging, you\'re pulling.'**
  String get title_back_r15_rope_hauler_flavor;

  /// Phase 18c back R20 title display name.
  ///
  /// In en, this message translates to:
  /// **'Lat-Crowned'**
  String get title_back_r20_lat_crowned_name;

  /// Phase 18c back R20 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Two slabs hold up the silhouette.'**
  String get title_back_r20_lat_crowned_flavor;

  /// Phase 18c back R25 title display name.
  ///
  /// In en, this message translates to:
  /// **'Talon-Backed'**
  String get title_back_r25_talon_backed_name;

  /// Phase 18c back R25 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The bar comes down because you said so.'**
  String get title_back_r25_talon_backed_flavor;

  /// Phase 18c back R30 title display name.
  ///
  /// In en, this message translates to:
  /// **'Wing-Spread'**
  String get title_back_r30_wing_spread_name;

  /// Phase 18c back R30 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Doorways notice you now.'**
  String get title_back_r30_wing_spread_flavor;

  /// Phase 18c back R40 title display name.
  ///
  /// In en, this message translates to:
  /// **'Lattice-Hauled'**
  String get title_back_r40_lattice_hauled_name;

  /// Phase 18c back R40 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Iron rises and the lattice answers.'**
  String get title_back_r40_lattice_hauled_flavor;

  /// Phase 18c back R50 title display name.
  ///
  /// In en, this message translates to:
  /// **'Wing-Crowned'**
  String get title_back_r50_wing_crowned_name;

  /// Phase 18c back R50 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The bar bows. The wings rise.'**
  String get title_back_r50_wing_crowned_flavor;

  /// Phase 18c back R60 title display name.
  ///
  /// In en, this message translates to:
  /// **'Lattice-Spread'**
  String get title_back_r60_lattice_spread_name;

  /// Phase 18c back R60 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Cathedral rafters built one rep at a time.'**
  String get title_back_r60_lattice_spread_flavor;

  /// Phase 18c back R70 title display name.
  ///
  /// In en, this message translates to:
  /// **'Wing-Storm'**
  String get title_back_r70_wing_storm_name;

  /// Phase 18c back R70 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Air moves when you do.'**
  String get title_back_r70_wing_storm_flavor;

  /// Phase 18c back R80 title display name.
  ///
  /// In en, this message translates to:
  /// **'Wing of Storms'**
  String get title_back_r80_wing_of_storms_name;

  /// Phase 18c back R80 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The kind of back weather forms around.'**
  String get title_back_r80_wing_of_storms_flavor;

  /// Phase 18c back R90 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Lattice'**
  String get title_back_r90_sky_lattice_name;

  /// Phase 18c back R90 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'What holds up the heavens, on you.'**
  String get title_back_r90_sky_lattice_flavor;

  /// Phase 18c back R99 terminal title display name.
  ///
  /// In en, this message translates to:
  /// **'The Lattice'**
  String get title_back_r99_the_lattice_name;

  /// Phase 18c back R99 terminal title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Every cable in the gym answers to you.'**
  String get title_back_r99_the_lattice_flavor;

  /// Phase 18c legs R5 title display name.
  ///
  /// In en, this message translates to:
  /// **'Ground-Walker'**
  String get title_legs_r5_ground_walker_name;

  /// Phase 18c legs R5 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The earth knows your weight.'**
  String get title_legs_r5_ground_walker_flavor;

  /// Phase 18c legs R10 title display name.
  ///
  /// In en, this message translates to:
  /// **'Stone-Stepper'**
  String get title_legs_r10_stone_stepper_name;

  /// Phase 18c legs R10 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Boulders move when you sit down.'**
  String get title_legs_r10_stone_stepper_flavor;

  /// Phase 18c legs R15 title display name.
  ///
  /// In en, this message translates to:
  /// **'Pillar-Apprentice'**
  String get title_legs_r15_pillar_apprentice_name;

  /// Phase 18c legs R15 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The columns are learning your name.'**
  String get title_legs_r15_pillar_apprentice_flavor;

  /// Phase 18c legs R20 title display name.
  ///
  /// In en, this message translates to:
  /// **'Pillar-Walker'**
  String get title_legs_r20_pillar_walker_name;

  /// Phase 18c legs R20 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Two columns where there used to be limbs.'**
  String get title_legs_r20_pillar_walker_flavor;

  /// Phase 18c legs R25 title display name.
  ///
  /// In en, this message translates to:
  /// **'Quarry-Strider'**
  String get title_legs_r25_quarry_strider_name;

  /// Phase 18c legs R25 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Stone is just where you start.'**
  String get title_legs_r25_quarry_strider_flavor;

  /// Phase 18c legs R30 title display name.
  ///
  /// In en, this message translates to:
  /// **'Mountain-Strider'**
  String get title_legs_r30_mountain_strider_name;

  /// Phase 18c legs R30 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Up is just another set.'**
  String get title_legs_r30_mountain_strider_flavor;

  /// Phase 18c legs R40 title display name.
  ///
  /// In en, this message translates to:
  /// **'Stone-Strider'**
  String get title_legs_r40_stone_strider_name;

  /// Phase 18c legs R40 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The ground splits before it stops you.'**
  String get title_legs_r40_stone_strider_flavor;

  /// Phase 18c legs R50 title display name.
  ///
  /// In en, this message translates to:
  /// **'Mountain-Footed'**
  String get title_legs_r50_mountain_footed_name;

  /// Phase 18c legs R50 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Foundations shift around your stance.'**
  String get title_legs_r50_mountain_footed_flavor;

  /// Phase 18c legs R60 title display name.
  ///
  /// In en, this message translates to:
  /// **'Mountain-Rooted'**
  String get title_legs_r60_mountain_rooted_name;

  /// Phase 18c legs R60 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Storms break before they move you.'**
  String get title_legs_r60_mountain_rooted_flavor;

  /// Phase 18c legs R70 title display name.
  ///
  /// In en, this message translates to:
  /// **'Pillar-Footed'**
  String get title_legs_r70_pillar_footed_name;

  /// Phase 18c legs R70 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Architecture\'s job, on a body.'**
  String get title_legs_r70_pillar_footed_flavor;

  /// Phase 18c legs R80 title display name.
  ///
  /// In en, this message translates to:
  /// **'Pillar of Storms'**
  String get title_legs_r80_pillar_of_storms_name;

  /// Phase 18c legs R80 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Wind shears around. You stay.'**
  String get title_legs_r80_pillar_of_storms_flavor;

  /// Phase 18c legs R90 title display name.
  ///
  /// In en, this message translates to:
  /// **'Mountain-Untouched'**
  String get title_legs_r90_mountain_untouched_name;

  /// Phase 18c legs R90 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Erosion takes a million years. You take one more set.'**
  String get title_legs_r90_mountain_untouched_flavor;

  /// Phase 18c legs R99 terminal title display name.
  ///
  /// In en, this message translates to:
  /// **'The Pillar'**
  String get title_legs_r99_the_pillar_name;

  /// Phase 18c legs R99 terminal title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Take you out and the ceiling falls.'**
  String get title_legs_r99_the_pillar_flavor;

  /// Phase 18c shoulders R5 title display name.
  ///
  /// In en, this message translates to:
  /// **'Burden-Tester'**
  String get title_shoulders_r5_burden_tester_name;

  /// Phase 18c shoulders R5 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'First weight overhead — the sky noticed.'**
  String get title_shoulders_r5_burden_tester_flavor;

  /// Phase 18c shoulders R10 title display name.
  ///
  /// In en, this message translates to:
  /// **'Yoke-Apprentice'**
  String get title_shoulders_r10_yoke_apprentice_name;

  /// Phase 18c shoulders R10 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Iron rests on you and stays put.'**
  String get title_shoulders_r10_yoke_apprentice_flavor;

  /// Phase 18c shoulders R15 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Reach'**
  String get title_shoulders_r15_sky_reach_name;

  /// Phase 18c shoulders R15 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Arms find ceiling without thinking.'**
  String get title_shoulders_r15_sky_reach_flavor;

  /// Phase 18c shoulders R20 title display name.
  ///
  /// In en, this message translates to:
  /// **'Atlas-Touched'**
  String get title_shoulders_r20_atlas_touched_name;

  /// Phase 18c shoulders R20 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Old myths recognise the shape.'**
  String get title_shoulders_r20_atlas_touched_flavor;

  /// Phase 18c shoulders R25 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Vaulter'**
  String get title_shoulders_r25_sky_vaulter_name;

  /// Phase 18c shoulders R25 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Up is where the bar lives.'**
  String get title_shoulders_r25_sky_vaulter_flavor;

  /// Phase 18c shoulders R30 title display name.
  ///
  /// In en, this message translates to:
  /// **'Yoke-Crowned'**
  String get title_shoulders_r30_yoke_crowned_name;

  /// Phase 18c shoulders R30 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'What sits on you stays decoration.'**
  String get title_shoulders_r30_yoke_crowned_flavor;

  /// Phase 18c shoulders R40 title display name.
  ///
  /// In en, this message translates to:
  /// **'Atlas-Carried'**
  String get title_shoulders_r40_atlas_carried_name;

  /// Phase 18c shoulders R40 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The world is not as heavy as it claims.'**
  String get title_shoulders_r40_atlas_carried_flavor;

  /// Phase 18c shoulders R50 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Yoked'**
  String get title_shoulders_r50_sky_yoked_name;

  /// Phase 18c shoulders R50 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The horizon hangs from your traps.'**
  String get title_shoulders_r50_sky_yoked_flavor;

  /// Phase 18c shoulders R60 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Vaulted'**
  String get title_shoulders_r60_sky_vaulted_name;

  /// Phase 18c shoulders R60 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Arms make space where there wasn\'t any.'**
  String get title_shoulders_r60_sky_vaulted_flavor;

  /// Phase 18c shoulders R70 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Held'**
  String get title_shoulders_r70_sky_held_name;

  /// Phase 18c shoulders R70 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Drop you and the clouds fall.'**
  String get title_shoulders_r70_sky_held_flavor;

  /// Phase 18c shoulders R80 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Sundered'**
  String get title_shoulders_r80_sky_sundered_name;

  /// Phase 18c shoulders R80 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'What you press splits the dome.'**
  String get title_shoulders_r80_sky_sundered_flavor;

  /// Phase 18c shoulders R90 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sky-Untouched'**
  String get title_shoulders_r90_sky_untouched_name;

  /// Phase 18c shoulders R90 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Storms pass overhead. You don\'t bow.'**
  String get title_shoulders_r90_sky_untouched_flavor;

  /// Phase 18c shoulders R99 terminal title display name.
  ///
  /// In en, this message translates to:
  /// **'The Atlas'**
  String get title_shoulders_r99_the_atlas_name;

  /// Phase 18c shoulders R99 terminal title flavor line.
  ///
  /// In en, this message translates to:
  /// **'All the weight of the heavens. Light work.'**
  String get title_shoulders_r99_the_atlas_flavor;

  /// Phase 18c arms R5 title display name.
  ///
  /// In en, this message translates to:
  /// **'Vein-Stirrer'**
  String get title_arms_r5_vein_stirrer_name;

  /// Phase 18c arms R5 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The blood remembers the curl.'**
  String get title_arms_r5_vein_stirrer_flavor;

  /// Phase 18c arms R10 title display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Fingered'**
  String get title_arms_r10_iron_fingered_name;

  /// Phase 18c arms R10 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'What you grip, you keep.'**
  String get title_arms_r10_iron_fingered_flavor;

  /// Phase 18c arms R15 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sinew-Drawn'**
  String get title_arms_r15_sinew_drawn_name;

  /// Phase 18c arms R15 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Cables, cords, ropes — they answer.'**
  String get title_arms_r15_sinew_drawn_flavor;

  /// Phase 18c arms R20 title display name.
  ///
  /// In en, this message translates to:
  /// **'Marrow-Cleaver'**
  String get title_arms_r20_marrow_cleaver_name;

  /// Phase 18c arms R20 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Each rep cuts deeper than the last.'**
  String get title_arms_r20_marrow_cleaver_flavor;

  /// Phase 18c arms R25 title display name.
  ///
  /// In en, this message translates to:
  /// **'Steel-Sleeved'**
  String get title_arms_r25_steel_sleeved_name;

  /// Phase 18c arms R25 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Sleeves can\'t keep up. Stop trying.'**
  String get title_arms_r25_steel_sleeved_flavor;

  /// Phase 18c arms R30 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sinew-Sworn'**
  String get title_arms_r30_sinew_sworn_name;

  /// Phase 18c arms R30 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The fibres don\'t quit before you do.'**
  String get title_arms_r30_sinew_sworn_flavor;

  /// Phase 18c arms R40 title display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Knuckled'**
  String get title_arms_r40_iron_knuckled_name;

  /// Phase 18c arms R40 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The handle bends first.'**
  String get title_arms_r40_iron_knuckled_flavor;

  /// Phase 18c arms R50 title display name.
  ///
  /// In en, this message translates to:
  /// **'Steel-Forged'**
  String get title_arms_r50_steel_forged_name;

  /// Phase 18c arms R50 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Hammered into the shape that lifts.'**
  String get title_arms_r50_steel_forged_flavor;

  /// Phase 18c arms R60 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sinew-Bound'**
  String get title_arms_r60_sinew_bound_name;

  /// Phase 18c arms R60 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Cables ran out of slack years ago.'**
  String get title_arms_r60_sinew_bound_flavor;

  /// Phase 18c arms R70 title display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Sleeved'**
  String get title_arms_r70_iron_sleeved_name;

  /// Phase 18c arms R70 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Knuckle to shoulder, all of it carries.'**
  String get title_arms_r70_iron_sleeved_flavor;

  /// Phase 18c arms R80 title display name.
  ///
  /// In en, this message translates to:
  /// **'Sinew of Storms'**
  String get title_arms_r80_sinew_of_storms_name;

  /// Phase 18c arms R80 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Lightning learns its shape from yours.'**
  String get title_arms_r80_sinew_of_storms_flavor;

  /// Phase 18c arms R90 title display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Untouched'**
  String get title_arms_r90_iron_untouched_name;

  /// Phase 18c arms R90 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Plate slides on. Plate slides off. The arm doesn\'t move.'**
  String get title_arms_r90_iron_untouched_flavor;

  /// Phase 18c arms R99 terminal title display name.
  ///
  /// In en, this message translates to:
  /// **'The Sinew'**
  String get title_arms_r99_the_sinew_name;

  /// Phase 18c arms R99 terminal title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Whatever needs lifting in this gym, you lift it.'**
  String get title_arms_r99_the_sinew_flavor;

  /// Phase 18c core R5 title display name.
  ///
  /// In en, this message translates to:
  /// **'Spine-Tested'**
  String get title_core_r5_spine_tested_name;

  /// Phase 18c core R5 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'First brace held — bar stayed level.'**
  String get title_core_r5_spine_tested_flavor;

  /// Phase 18c core R10 title display name.
  ///
  /// In en, this message translates to:
  /// **'Core-Forged'**
  String get title_core_r10_core_forged_name;

  /// Phase 18c core R10 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Mid-line locked, ribs to hips.'**
  String get title_core_r10_core_forged_flavor;

  /// Phase 18c core R15 title display name.
  ///
  /// In en, this message translates to:
  /// **'Pillar-Spined'**
  String get title_core_r15_pillar_spined_name;

  /// Phase 18c core R15 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The bar can lean. You don\'t.'**
  String get title_core_r15_pillar_spined_flavor;

  /// Phase 18c core R20 title display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Belted'**
  String get title_core_r20_iron_belted_name;

  /// Phase 18c core R20 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Belt\'s a formality at this point.'**
  String get title_core_r20_iron_belted_flavor;

  /// Phase 18c core R25 title display name.
  ///
  /// In en, this message translates to:
  /// **'Stonewall'**
  String get title_core_r25_stonewall_name;

  /// Phase 18c core R25 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Air goes in. Force comes out.'**
  String get title_core_r25_stonewall_flavor;

  /// Phase 18c core R30 title display name.
  ///
  /// In en, this message translates to:
  /// **'Diamond-Spine'**
  String get title_core_r30_diamond_spine_name;

  /// Phase 18c core R30 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Compressed enough times, things turn to gem.'**
  String get title_core_r30_diamond_spine_flavor;

  /// Phase 18c core R40 title display name.
  ///
  /// In en, this message translates to:
  /// **'Anchor-Belted'**
  String get title_core_r40_anchor_belted_name;

  /// Phase 18c core R40 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Whatever the load, the trunk holds.'**
  String get title_core_r40_anchor_belted_flavor;

  /// Phase 18c core R50 title display name.
  ///
  /// In en, this message translates to:
  /// **'Stone-Cored'**
  String get title_core_r50_stone_cored_name;

  /// Phase 18c core R50 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Hit the centre. Hit a wall.'**
  String get title_core_r50_stone_cored_flavor;

  /// Phase 18c core R60 title display name.
  ///
  /// In en, this message translates to:
  /// **'Marrow-Carved'**
  String get title_core_r60_marrow_carved_name;

  /// Phase 18c core R60 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Each rep cut a notch into bone.'**
  String get title_core_r60_marrow_carved_flavor;

  /// Phase 18c core R70 title display name.
  ///
  /// In en, this message translates to:
  /// **'Stone-Spined'**
  String get title_core_r70_stone_spined_name;

  /// Phase 18c core R70 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'The vertebrae stack like masonry.'**
  String get title_core_r70_stone_spined_flavor;

  /// Phase 18c core R80 title display name.
  ///
  /// In en, this message translates to:
  /// **'Spine of Storms'**
  String get title_core_r80_spine_of_storms_name;

  /// Phase 18c core R80 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Wind through trees. Trunk doesn\'t move.'**
  String get title_core_r80_spine_of_storms_flavor;

  /// Phase 18c core R90 title display name.
  ///
  /// In en, this message translates to:
  /// **'Marrow-Untouched'**
  String get title_core_r90_marrow_untouched_name;

  /// Phase 18c core R90 title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Whatever cracks the body, it stops at the centre.'**
  String get title_core_r90_marrow_untouched_flavor;

  /// Phase 18c core R99 terminal title display name.
  ///
  /// In en, this message translates to:
  /// **'The Spine'**
  String get title_core_r99_the_spine_name;

  /// Phase 18c core R99 terminal title flavor line.
  ///
  /// In en, this message translates to:
  /// **'Hold the bar like a chapel beam.'**
  String get title_core_r99_the_spine_flavor;

  /// Phase 18e character-level title (lvl 10) display name. The first milestone — you've left the trailhead.
  ///
  /// In en, this message translates to:
  /// **'Wanderer'**
  String get title_wanderer_name;

  /// Phase 18e character-level title (lvl 10) flavor line.
  ///
  /// In en, this message translates to:
  /// **'The first milestone is behind you. The map opens.'**
  String get title_wanderer_flavor;

  /// Phase 18e character-level title (lvl 25) display name. The road has worn into your boots.
  ///
  /// In en, this message translates to:
  /// **'Path-Trodden'**
  String get title_path_trodden_name;

  /// Phase 18e character-level title (lvl 25) flavor line.
  ///
  /// In en, this message translates to:
  /// **'Twenty-five levels in. The road knows your weight.'**
  String get title_path_trodden_flavor;

  /// Phase 18e character-level title (lvl 50) display name. Half the curve done.
  ///
  /// In en, this message translates to:
  /// **'Path-Sworn'**
  String get title_path_sworn_name;

  /// Phase 18e character-level title (lvl 50) flavor line.
  ///
  /// In en, this message translates to:
  /// **'Halfway. You don\'t quit on the path now.'**
  String get title_path_sworn_flavor;

  /// Phase 18e character-level title (lvl 75) display name. Three-quarters of the climb.
  ///
  /// In en, this message translates to:
  /// **'Path-Forged'**
  String get title_path_forged_name;

  /// Phase 18e character-level title (lvl 75) flavor line.
  ///
  /// In en, this message translates to:
  /// **'Three quarters in. The path is forged from you.'**
  String get title_path_forged_flavor;

  /// Phase 18e character-level title (lvl 100) display name. Triple-digits unlocked.
  ///
  /// In en, this message translates to:
  /// **'Saga-Scribed'**
  String get title_saga_scribed_name;

  /// Phase 18e character-level title (lvl 100) flavor line.
  ///
  /// In en, this message translates to:
  /// **'One hundred levels. Your name is in the codex.'**
  String get title_saga_scribed_flavor;

  /// Phase 18e character-level title (lvl 125) display name. Late-game persistence.
  ///
  /// In en, this message translates to:
  /// **'Saga-Bound'**
  String get title_saga_bound_name;

  /// Phase 18e character-level title (lvl 125) flavor line.
  ///
  /// In en, this message translates to:
  /// **'One twenty-five. The saga binds you, and you bind back.'**
  String get title_saga_bound_flavor;

  /// Phase 18e character-level title (lvl 148, terminal) display name. The end of the curve.
  ///
  /// In en, this message translates to:
  /// **'Saga-Eternal'**
  String get title_saga_eternal_name;

  /// Phase 18e character-level title (lvl 148) flavor line.
  ///
  /// In en, this message translates to:
  /// **'One forty-eight. The saga has a name now, and it is yours.'**
  String get title_saga_eternal_flavor;

  /// Phase 18e cross-build title — leg-dominant build (Legs ≥ 40 AND Legs ≥ 2× Arms). Display name.
  ///
  /// In en, this message translates to:
  /// **'Pillar-Walker'**
  String get title_pillar_walker_name;

  /// Phase 18e cross-build title (pillar_walker) flavor line.
  ///
  /// In en, this message translates to:
  /// **'You walk on pillars, not on arms. The ground knows.'**
  String get title_pillar_walker_flavor;

  /// Phase 18e cross-build title — upper-body specialist (Chest+Back+Shoulders ≥ 2×(Legs+Core), every upper ≥ 30). Display name.
  ///
  /// In en, this message translates to:
  /// **'Broad-Shouldered'**
  String get title_broad_shouldered_name;

  /// Phase 18e cross-build title (broad_shouldered) flavor line.
  ///
  /// In en, this message translates to:
  /// **'Yokes for shoulders, gates for a chest. Carry the weight.'**
  String get title_broad_shouldered_flavor;

  /// Phase 18e cross-build title — balanced build (every rank within 30% of max AND min ≥ 30). Display name.
  ///
  /// In en, this message translates to:
  /// **'Even-Handed'**
  String get title_even_handed_name;

  /// Phase 18e cross-build title (even_handed) flavor line.
  ///
  /// In en, this message translates to:
  /// **'No weakness. No favorite lift. The whole forge, even-tempered.'**
  String get title_even_handed_flavor;

  /// Phase 18e cross-build title — strength specialist (Chest+Back+Legs all ≥ 60). Display name.
  ///
  /// In en, this message translates to:
  /// **'Iron-Bound'**
  String get title_iron_bound_name;

  /// Phase 18e cross-build title (iron_bound) flavor line.
  ///
  /// In en, this message translates to:
  /// **'Bench, pull, squat — all bound in iron. The big three answer to you.'**
  String get title_iron_bound_flavor;

  /// Phase 18e cross-build title — every rank ≥ 60 (end-game prestige). Display name.
  ///
  /// In en, this message translates to:
  /// **'Saga-Forged'**
  String get title_saga_forged_name;

  /// Phase 18e cross-build title (saga_forged) flavor line.
  ///
  /// In en, this message translates to:
  /// **'Every track at sixty. The saga is forged, and you forged it.'**
  String get title_saga_forged_flavor;

  /// Accessibility/tooltip: WeightStepper minus button.
  ///
  /// In en, this message translates to:
  /// **'Decrease weight'**
  String get decrementWeight;

  /// Accessibility/tooltip: WeightStepper plus button.
  ///
  /// In en, this message translates to:
  /// **'Increase weight'**
  String get incrementWeight;

  /// Accessibility/tooltip: RepsStepper minus button.
  ///
  /// In en, this message translates to:
  /// **'Decrease reps'**
  String get decrementReps;

  /// Accessibility/tooltip: RepsStepper plus button.
  ///
  /// In en, this message translates to:
  /// **'Increase reps'**
  String get incrementReps;

  /// Accessibility label on the WeightStepper value zone. Reads the formatted weight + unit and hints at tap-to-type.
  ///
  /// In en, this message translates to:
  /// **'Weight value: {formatted} {unit}. Tap to enter weight.'**
  String weightValueSemantics(String formatted, String unit);

  /// Accessibility label on the RepsStepper value zone. Reads the rep count and hints at tap-to-type.
  ///
  /// In en, this message translates to:
  /// **'Reps value: {value}. Tap to enter reps.'**
  String repsValueSemantics(int value);

  /// Accessibility label for the RestTimerOverlay outer dismiss scrim (the GestureDetector that ends the timer when tapped).
  ///
  /// In en, this message translates to:
  /// **'Dismiss rest timer'**
  String get restTimerDismiss;

  /// Accessibility label on the active-workout AppBar title. Announces the workout name and the rename affordance.
  ///
  /// In en, this message translates to:
  /// **'{name}. Tap to rename workout.'**
  String workoutNameTapToRenameSemantics(String name);

  /// Default name auto-generated when a workout is started without a name. Locale-aware: read at workout-start time and persisted.
  ///
  /// In en, this message translates to:
  /// **'Workout — {date}'**
  String workoutDefaultName(String date);

  /// Volume column header in VolumePeakBlock (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volumePeakBlockVolumeLabel;

  /// Carga pico (peak load) column header in VolumePeakBlock (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Peak load'**
  String get volumePeakBlockCargaPicoLabel;

  /// Generic-tip fallback label when the user has no personal history for this body part (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get volumePeakBlockReferenciaLabel;

  /// Plural unit for weekly volume in VolumePeakBlock (matches the existing weeklyVolumeUnit pattern; Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get volumePeakBlockSeries;

  /// Delta-basis copy for the previous-week comparison (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'vs last week'**
  String get volumePeakBlockDeltaVsPrevWeek;

  /// Delta-basis copy for the 4-week-mean comparison (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'vs 4-week avg'**
  String get volumePeakBlockDeltaVsFourWeekMean;

  /// Suppressed-delta copy for users with insufficient history (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'no history'**
  String get volumePeakBlockDeltaNoHistory;

  /// Footer copy under the Referência generic-tip block (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'estimated'**
  String get volumePeakBlockDeltaEstimated;

  /// Over-target delta tail copy ('▲ +N above target') — locked decision rules this as amber, not green (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'above target'**
  String get volumePeakBlockDeltaAboveTarget;

  /// Tiny pill badge next to the monthly peak EWMA delta (Phase 26c).
  ///
  /// In en, this message translates to:
  /// **'30D'**
  String get volumePeakBlockBadge30D;

  /// Title above the 6-bar engagement section in the plan editor (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'Weekly engagement'**
  String get weeklyEngagementHeader;

  /// Title of the bottom sheet that explains the set-counting rule (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'How we count sets'**
  String get engagementExplainerTitle;

  /// Body of the engagement explainer sheet (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'Each set counts toward the body part with the largest share of its XP attribution. If two body parts tie at the largest share, both count. This avoids double-counting unrelated muscles while still crediting compound lifts.'**
  String get engagementExplainerBody;

  /// Legend label for the filled portion of the engagement bar (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get engagementLegendDone;

  /// Legend label for the dimmed portion of the engagement bar (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get engagementLegendPlanned;

  /// Counter pill at the top of the plan editor (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 days trained} =1{1 day trained} other{{count} days trained}}'**
  String daysTrainedCount(int count);

  /// CTA at the bottom of the bucket list (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'+ Add workout'**
  String get addWorkout;

  /// Warning when bucket count exceeds trainingFrequencyPerWeek (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'Exceeds your weekly limit of {count}'**
  String softCapWarning(int count);

  /// Tag on bucket rows for routines that didn't match a planned entry (Phase 26e).
  ///
  /// In en, this message translates to:
  /// **'Spontaneous'**
  String get spontaneousTag;

  /// Phase 30 PR 30a — Beat 1 copy variant: Day-zero (first session ever). Mockup §2 Variant Day-Zero.
  ///
  /// In en, this message translates to:
  /// **'BEGUN.\nTHE WORST IS BEHIND.'**
  String get b1CopyDayZero;

  /// Phase 30 PR 30a — Beat 1 copy variant: baseline A (default). Mockup §2 Variant Baseline.
  ///
  /// In en, this message translates to:
  /// **'DONE.\nSTRONGER.'**
  String get b1CopyBaselineA;

  /// Phase 30 PR 30a — Beat 1 copy variant: baseline B (alternates with A across sessions). Mockup §5 State 2 script.
  ///
  /// In en, this message translates to:
  /// **'CONSISTENCY WINS.'**
  String get b1CopyBaselineB;

  /// Phase 30 PR 30a — Beat 1 copy variant: threshold-anticipatory (PR or rank-up incoming). Mockup §2 Variant Threshold-anticipatory.
  ///
  /// In en, this message translates to:
  /// **'NEW LIMIT.'**
  String get b1CopyPrAnticipatory;

  /// Phase 30 PR 30a — Beat 1 copy variant: title-anticipatory (reuses Threshold-anticipatory parse window with a different copy line). Mockup §2 + §5 State 8.
  ///
  /// In en, this message translates to:
  /// **'ACHIEVEMENT AWAKENED.'**
  String get b1CopyTitleAnticipatory;

  /// Phase 30 PR 30a — Beat 1 copy variant: max-combo / class-change / level-up (folds level into B1 copy). Mockup §2 Variant Max-combo + §5 State 7.
  ///
  /// In en, this message translates to:
  /// **'LEVEL {n}.\nTHE SAGA CONTINUES.'**
  String b1CopyMaxLevelUp(int n);

  /// Beat 1 copy variant: class-change-only state (State 9). Distinct ARB key from the PR-anticipatory variant — same string today, but the semantic distinction lets editorial copy diverge without code churn. Mockup §5 State 9 bottom copy line.
  ///
  /// In en, this message translates to:
  /// **'NEW LIMIT.'**
  String get b1CopyClassChangeOnly;

  /// Phase 30 PR 30a — Beat 3 PR eyebrow for a single-PR session. Mockup §4 PR single.
  ///
  /// In en, this message translates to:
  /// **'!! Record'**
  String get b3PrEyebrowSingle;

  /// Phase 30 PR 30a — Beat 3 PR eyebrow for a multi-PR session. Mockup §4 PR multi.
  ///
  /// In en, this message translates to:
  /// **'!! {n} Records'**
  String b3PrEyebrowMulti(int n);

  /// Phase 30 PR 30a — Beat 3 PR copy line for single-PR. Mockup §4 PR single.
  ///
  /// In en, this message translates to:
  /// **'YOU BROKE THROUGH.'**
  String get b3PrCopySingle;

  /// Phase 30 PR 30a — Beat 3 PR copy line for multi-PR. Mockup §4 PR multi.
  ///
  /// In en, this message translates to:
  /// **'YOU DESTROYED IT.'**
  String get b3PrCopyMulti;

  /// Phase 30 PR 30a — Beat 3 multi-PR pill row template. Mockup §4 PR multi.
  ///
  /// In en, this message translates to:
  /// **'{exercise} · {weight}kg × {reps}'**
  String b3PrPillTemplate(String exercise, String weight, int reps);

  /// Phase 30 PR 30a — Beat 3 title-unlock eyebrow. Mockup §4 Title.
  ///
  /// In en, this message translates to:
  /// **'Title Unlocked'**
  String get b3TitleEyebrow;

  /// Phase 30 PR 30a — Beat 3 class-change eyebrow. Mockup §4 Class change + §5 State 9.
  ///
  /// In en, this message translates to:
  /// **'Class Awakened'**
  String get b3ClassEyebrow;

  /// Phase 30 PR 30a — Beat 3 class-change subline below the class name. Mockup §4 Class change.
  ///
  /// In en, this message translates to:
  /// **'AWAKENED.'**
  String get b3ClassSubline;

  /// Phase 30 PR 30a — Beat 2 elevated rank-up copy template. Mockup §3 Variant D.
  ///
  /// In en, this message translates to:
  /// **'{bodyPart} · RANK {n}'**
  String b2RankCopy(String bodyPart, String n);

  /// Phase 30 PR 30a — Summary panel saga number. Mockup §5 storyboards.
  ///
  /// In en, this message translates to:
  /// **'Saga {n}'**
  String summarySagaNumber(int n);

  /// Phase 30 PR 30a — Summary panel saga label for day-zero finish. Mockup §5 State 1.
  ///
  /// In en, this message translates to:
  /// **'1st saga'**
  String get summaryDayZero;

  /// Phase 30 PR 30a — Summary panel duration + sets line.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min · {sets} sets'**
  String summaryDurationSets(int minutes, int sets);

  /// Phase 30 PR 30a — Summary panel tonnage line (kg already formatted at the call site).
  ///
  /// In en, this message translates to:
  /// **'{kg} ton'**
  String summaryTonnage(String kg);

  /// Phase 30 PR 30a — Summary panel next-step eyebrow. Mockup §5 storyboards.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get summaryNextStepLabel;

  /// Phase 30 PR 30a — Summary panel next-rank hook. Mockup §5 States 1, 2, 5, 8.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP left\nfor {bodyPart} rank {n}.'**
  String summaryNextRank(int xp, String bodyPart, int n);

  /// Phase 30 PR 30a — Summary panel next-level hook. Mockup §5 States 7, 10.
  ///
  /// In en, this message translates to:
  /// **'{ranks} ranks to\nlevel {n}.'**
  String summaryNextLevel(int ranks, int n);

  /// Phase 30 PR 30a — Summary panel new-title eyebrow. Mockup §5 State 8.
  ///
  /// In en, this message translates to:
  /// **'New title'**
  String get summaryNewTitleLabel;

  /// Phase 30 PR 30a — Summary panel title-equip CTA label.
  ///
  /// In en, this message translates to:
  /// **'EQUIP'**
  String get summaryEquipCta;

  /// Phase 30 PR 30a — Summary panel title-equip 'later' label.
  ///
  /// In en, this message translates to:
  /// **'later'**
  String get summaryEquipLater;

  /// Phase 30 PR 30a — Summary panel CONTINUAR button. Mockup §5 storyboards. The trailing arrow is rendered as a Material icon at the call site, never baked into the string (visual gate fix 2026-05-23).
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get summaryContinueCta;

  /// Phase 30 PR 30a — Summary panel share CTA label (placeholder in 30a; wired in 30b). The camera glyph is rendered as a Material icon at the call site, never baked into the string (visual gate fix 2026-05-23).
  ///
  /// In en, this message translates to:
  /// **'Share saga'**
  String get summaryShareCta;

  /// Phase 30 PR 30a — Snackbar shown when the share CTA is tapped in 30a.
  ///
  /// In en, this message translates to:
  /// **'Share — coming soon'**
  String get summaryShareComingSoon;

  /// Phase 30 PR 30b — Bottom-sheet title for the share-card picker.
  ///
  /// In en, this message translates to:
  /// **'Share your saga'**
  String get shareSheetTitle;

  /// Phase 30 PR 30b — Camera option row in the share-card bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get shareSheetTakePhoto;

  /// Phase 30 PR 30b — Gallery option row in the share-card bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Pick from gallery'**
  String get shareSheetFromGallery;

  /// Phase 30 PR 30b — Discreet (no-photo) option row in the share-card bottom sheet. Mockup §7.
  ///
  /// In en, this message translates to:
  /// **'No photo · just the saga'**
  String get shareSheetNoPhoto;

  /// Phase 30 PR 30b — Preview-screen retake button label. Returns to the share-sheet step.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get sharePreviewRetake;

  /// Phase 30 PR 30b — Preview-screen primary CTA. Triggers the render + native share-sheet handoff.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get sharePreviewShare;

  /// Phase 30 PR 30b — Brand wordmark baked into the share card. Same in en + pt; constant kept here for white-label / event-rebrand changes.
  ///
  /// In en, this message translates to:
  /// **'REPSAGA'**
  String get shareWordmark;

  /// Phase 30 PR 30b — Snackbar copy when camera permission is denied on the share flow.
  ///
  /// In en, this message translates to:
  /// **'Camera access denied. Tap again to retry.'**
  String get sharePermissionDenied;

  /// Phase 30 PR 30b — Snackbar copy when camera permission is permanently denied. Screen layer pairs this with an 'Open settings' affordance.
  ///
  /// In en, this message translates to:
  /// **'Camera access blocked in settings.'**
  String get sharePermissionPermanentlyDenied;

  /// Phase 30 PR 30b — Snackbar copy when ShareImageRenderer fails to produce a sharable image.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t render the saga card. Try again.'**
  String get shareRenderError;

  /// Phase 30 PR 30b — Snackbar action label paired with sharePermissionPermanentlyDenied. Taps openAppSettings() so the user can flip the camera-permission toggle.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get shareOpenSettings;

  /// Phase 30 PR 30a — Summary panel rank-up overflow card header. Mockup §5 State 6.
  ///
  /// In en, this message translates to:
  /// **'+1 RANK · OPEN SAGA'**
  String get summaryRankUpOverflowHeader;

  /// Phase 30 PR 30a — Empty-session guard sheet title. Mockup §5 State 11.
  ///
  /// In en, this message translates to:
  /// **'End workout?'**
  String get emptyGuardTitle;

  /// Phase 30 PR 30a — Empty-session guard sheet body. Mockup §5 State 11.
  ///
  /// In en, this message translates to:
  /// **'No exercises logged.'**
  String get emptyGuardBody;

  /// Phase 30 PR 30a — Empty-session guard sheet discard button.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get emptyGuardDiscard;

  /// Phase 30 PR 30a — Empty-session guard sheet continue button.
  ///
  /// In en, this message translates to:
  /// **'Keep training'**
  String get emptyGuardContinue;

  /// Phase 30 PR 30a — Beat 2 body-part eyebrow suffix when a body part first awakens this session. Mockup §5 State 1.
  ///
  /// In en, this message translates to:
  /// **'Awakened'**
  String get postSessionFirstAwakeningSuffix;

  /// Phase 30 PR 30a — Cascade variant truncation pill. Mockup §3 Variant C.
  ///
  /// In en, this message translates to:
  /// **'+{n} more'**
  String postSessionCascadeTruncationPill(String n);

  /// Phase 30 PR 30a — Sub-label below the XP slam numeral in Beat 1 / Beat 2.
  ///
  /// In en, this message translates to:
  /// **'XP'**
  String get postSessionXpLabel;

  /// Phase 30 PR 30a — Summary panel title-equip success state. Mockup §5 State 8 + WIP.md PR 30a Open question #6.
  ///
  /// In en, this message translates to:
  /// **'Equipped ✓'**
  String get postSessionTitleEquipped;

  /// Phase 32 PR 32g (Bug 3) — Snackbar shown on the post-session screen when the title-equip RPC fails. The TitleEquipRow's contract is to reset its loading state and rethrow so the screen surfaces the error.
  ///
  /// In en, this message translates to:
  /// **'Could not equip title. Please try again.'**
  String get postSessionTitleEquipFailed;

  /// Phase 30 PR 30a UX pass 2 (2026-05-23) — Label inside the top-right skip pill that jumps the post-session cinematic to the summary panel. Pre-uppercased to match the letter-spaced eyebrow casing convention (AppTextStyles.label).
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get cinematicSkipLabel;

  /// Phase 31 Pass 3 — Mission Debrief section eyebrow above the lift rows. Pre-title-cased; widget uppercases for the +0.22em tracked label register.
  ///
  /// In en, this message translates to:
  /// **'Session report'**
  String get postSessionDebriefEyebrow;

  /// Phase 31 Pass 3 — Personal record flag rendered next to the weight × reps on a Mission Debrief lift row. heroGold-tinted; canonical reward signal.
  ///
  /// In en, this message translates to:
  /// **'PR'**
  String get postSessionPrFlag;

  /// Phase 31 Pass 3 — '+N more exercises' footer on the Mission Debrief lift table when the session trained more than 4 exercises.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+1 more exercise} other{+{count} more exercises}}'**
  String postSessionMoreLifts(int count);

  /// Phase 31 Pass 3 — Per-BP rank line in the Mission Debrief (no rank-up). Used on every BP that earned XP this session.
  ///
  /// In en, this message translates to:
  /// **'Rank {n}'**
  String postSessionRankLabel(int n);

  /// Phase 31 Pass 3 — Per-BP rank-up grammar in the Mission Debrief (rank-up session). Renders the rank delta arrow.
  ///
  /// In en, this message translates to:
  /// **'Rank {fromRank} → {toRank}'**
  String postSessionRankUpArrow(int fromRank, int toRank);

  /// Phase 31 Pass 3 — Weight unit suffix on Mission Debrief lift rows. v1 ships kg only; the key exists so a future lb locale can override without code touch.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get postSessionWeightUnit;

  /// Phase 31 round-2 Bug E — Confirmation dialog title shown when the user presses the system back button on the post-session screen. The user has just finished a workout; backing out of the cinematic/debrief is permanent (no re-entry path), so the dialog blocks accidental dismissal.
  ///
  /// In en, this message translates to:
  /// **'Leave the post-battle?'**
  String get postSessionLeaveTitle;

  /// Phase 31 round-2 Bug E — Cancel action on the post-session leave-confirmation dialog. Returns the user to the post-session surface.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get postSessionLeaveCancel;

  /// Phase 31 round-2 Bug E — Confirm action on the post-session leave-confirmation dialog. Routes the user through the same `onContinue` path the CONTINUAR button uses (back to /home).
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get postSessionLeaveConfirm;

  /// Phase 31 round-2 Bug F — Mission Debrief XP hero block right-of-numeral label. Renders alongside the '+{totalXp}' numeric ('+340 XP EARNED'). Pre-uppercased — already in the tracked-label register.
  ///
  /// In en, this message translates to:
  /// **'XP EARNED'**
  String get postSessionXpEarnedLabel;

  /// Phase 32 PR 32e — Bottom-sheet title shown when the user taps the IdentityCard avatar to upload a new picture. Sits above the camera / gallery / cancel rows.
  ///
  /// In en, this message translates to:
  /// **'Choose avatar source'**
  String get avatarPickerSheetTitle;

  /// Phase 32 PR 32e — Camera row in the avatar picker bottom sheet. Reuses the share-card camera-row pattern.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get avatarPickerCamera;

  /// Phase 32 PR 32e — Gallery row in the avatar picker bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Pick from gallery'**
  String get avatarPickerGallery;

  /// Phase 32 PR 32e — Cancel row in the avatar picker bottom sheet. Closes the sheet without picking.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get avatarPickerCancel;

  /// Phase 32 PR 32e — Eyebrow title above the circular crop area in the AvatarCropSheet. The user pinches / drags inside the circle to frame their picture.
  ///
  /// In en, this message translates to:
  /// **'Position your avatar'**
  String get avatarCropSheetTitle;

  /// Phase 32 PR 32e — Confirm button on the AvatarCropSheet bottom bar. Rasterizes the visible crop area and uploads to Supabase Storage.
  ///
  /// In en, this message translates to:
  /// **'Use this'**
  String get avatarCropSheetConfirm;

  /// Phase 32 PR 32e — Cancel button on the AvatarCropSheet bottom bar. Dismisses without uploading.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get avatarCropSheetCancel;

  /// Phase 32 PR 32e — Success snackbar shown after a successful avatar upload. The IdentityCard re-renders with the new image at the same time.
  ///
  /// In en, this message translates to:
  /// **'Avatar updated.'**
  String get avatarUploadSuccess;

  /// Phase 32 PR 32e — Error snackbar shown when the avatar upload fails (network / storage error). The user can re-tap the avatar to retry.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your avatar. Please try again.'**
  String get avatarUploadFailed;

  /// Phase 32 PR 32e — Accessibility label for the IdentityCard avatar surface. The {name} placeholder receives the user's display name (or email fallback). Read by screen readers when the user lands on the avatar.
  ///
  /// In en, this message translates to:
  /// **'Profile avatar for {name}'**
  String avatarSemanticsLabel(String name);

  /// Phase 32 PR 32e — Snackbar copy shown when the user denies camera permission during the avatar-upload flow. Distinct from avatarUploadFailed (network/storage error) so the user sees the actual cause. The screen layer pairs this with an Open settings action when the OS reports permanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access denied. Try the gallery, or open settings to grant access.'**
  String get cameraPermissionDeniedForAvatar;

  /// Phase 32 PR 32f — Sticky week-header eyebrow label on the History screen. {date} is the localized Monday-of-week display (e.g. 'May 20').
  ///
  /// In en, this message translates to:
  /// **'Week of {date}'**
  String historyWeekLabel(String date);

  /// Phase 32 PR 32f — Sets portion of the sticky week-header roll-up on the History screen. Rendered alongside the XP total separately so the XP digits can pick up heroGold while the sets portion stays in default text color. TODO(pre-launch): swap to ICU plural ({sets, plural, =1{1 set} other{{sets} sets}}) — accepted as a known gap for PR #285; '1 sets' renders for single-set weeks until then.
  ///
  /// In en, this message translates to:
  /// **'{sets} sets'**
  String historyWeekRollupSets(int sets);

  /// Phase 32 PR 32f — Per-workout XP eyebrow line above the title row on each History card. Rendered in heroGold via AppTextStyles.numericSmall.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP'**
  String historyCardXpEyebrow(int xp);

  /// Phase 32 PR 32f — Per-workout PR diamond row on a History card. Rendered only when prCount > 0 — omitted entirely when zero (UX-critic 'no empty placeholders' rule). The leading diamond glyph is part of the literal, not a separate icon. ICU plural added per PR #285 device-verification finding so '6 PR' becomes '6 PRs'.
  ///
  /// In en, this message translates to:
  /// **'◆ {count, plural, =1{1 PR} other{{count} PRs}}'**
  String historyCardPrCount(int count);

  /// Phase 32 PR 32f — XP portion of the 48dp summary strip on the Workout Detail screen. Rendered in hotViolet (daily-driver register) via Text.rich so the PR portion can pick up heroGold via RewardAccent independently. Replaces the prior single-string historyDetailStrip after PR #285 split the colors per the reward-scarcity rule.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP'**
  String historyDetailStripXpPart(int xp);

  /// Phase 32 PR 32f — PR portion of the 48dp summary strip on the Workout Detail screen. Rendered inside a RewardAccent scope so the digits + label inherit heroGold. Rendered only when prCount > 0; the leading separator dot is supplied by the screen layer. ICU plural added per PR #285 device-verification finding so '1 PR' / '6 PRs' grammar matches.
  ///
  /// In en, this message translates to:
  /// **'{prs, plural, =1{1 PR} other{{prs} PRs}}'**
  String historyDetailStripPrPart(int prs);

  /// Phase 32 PR 32f — Sticky week-header label for the current ISO week (Monday-of-week == Monday of today). Replaces the date-formatted historyWeekLabel for the current week so the heading reads as a relative anchor instead of repeating a date the user already knows.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get historyWeekLabelCurrent;

  /// Legal PR 2 — Analytics opt-out toggle title in Profile → Settings → Privacy. Mirrors `sendCrashReports`.
  ///
  /// In en, this message translates to:
  /// **'Send usage analytics'**
  String get sendUsageAnalytics;

  /// Legal PR 2 — Analytics opt-out toggle subtitle. Calls out the user's right to withdraw at any time (LGPD Art. 9 / GDPR Art. 7(3)).
  ///
  /// In en, this message translates to:
  /// **'Helps RepSaga improve. You can disable any time.'**
  String get usageAnalyticsSubtitle;

  /// Leading clause of the inline age-gate checkbox sentence (Option A). Followed inline by the Terms link, the localized 'and' separator, then the Privacy Policy link — e.g. 'I'm 18+ and agree to the Terms and the Privacy Policy'.
  ///
  /// In en, this message translates to:
  /// **'I\'m 18+ and agree to the'**
  String get signupAgeConfirmationLead;

  /// Legal PR 2 — Title of the consent dialog shown when the user tries to save a body-weight value before opting in. Reuses the LGPD Art. 11 / Privacy Policy §7 language that classifies body weight as health data.
  ///
  /// In en, this message translates to:
  /// **'Body weight is sensitive data.'**
  String get bodyweightConsentTitle;

  /// Legal PR 2 — Body of the consent dialog shown when the user tries to save a body-weight value before opting in. Explains the purpose (XP calc for bodyweight exercises) and the withdrawal path (Privacy section toggle).
  ///
  /// In en, this message translates to:
  /// **'Per the Privacy Policy, body weight is health data and requires your explicit consent. It\'s used solely to improve XP calculation for bodyweight exercises. You can revoke this consent any time in Profile → Settings → Privacy.'**
  String get bodyweightConsentBody;

  /// Legal PR 2 — Affirmative action on the body-weight consent dialog. Tapping flips `bodyweight_consent_enabled` to true AND proceeds with the upsert.
  ///
  /// In en, this message translates to:
  /// **'Save with consent'**
  String get bodyweightConsentAccept;

  /// Legal PR 2 — Title for the withdrawal switch in Profile → Settings → Privacy. Mirrors `sendCrashReports` shape.
  ///
  /// In en, this message translates to:
  /// **'Body weight tracking'**
  String get bodyweightConsentToggleTitle;

  /// Legal PR 2 — Subtitle clarifying that flipping the switch off only blocks future writes, not historical ones (retention is governed by the manage-data screen).
  ///
  /// In en, this message translates to:
  /// **'Required to log body weight. Disabling does not delete past entries.'**
  String get bodyweightConsentToggleSubtitle;

  /// Legal PR 2 — Section header for the gender editor in Profile → Settings.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// Legal PR 2 — One-time disclosure banner shown above the gender selector the FIRST time it's opened. Self-extinguishes once any value is picked. LGPD Art. 11 sensitive-data disclosure (Privacy Policy §7).
  ///
  /// In en, this message translates to:
  /// **'Gender helps RepSaga match XP calculations to gender-aware strength tier tables. This is sensitive data — you can pick \"Other\" or leave it blank to skip.'**
  String get genderConsentBanner;

  /// Legal PR 2 — Gender option label (matches Symmetric Strength male tier tables).
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// Legal PR 2 — Gender option label (matches strengthlevel.com female tier tables).
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// Legal PR 2 — Gender option label. Same backward-compat fallback as NULL (male tier tables) — documented in `lib/features/profile/models/profile.dart`.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genderOther;

  /// Legal PR 2 — Display value shown in the Profile → Settings row when `profile.gender == null`. Tapping opens the editor.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get genderNotSet;

  /// Phase 38b — uppercase tracked eyebrow on the CardioEntryCard, e.g. 'RUNNING · CARDIO'. ARB supplies the casing (label-register convention).
  ///
  /// In en, this message translates to:
  /// **'{activity} · CARDIO'**
  String cardioEyebrow(String activity);

  /// Phase 38b — eyebrow fallback for cardio exercises without a known activity mapping (user-created).
  ///
  /// In en, this message translates to:
  /// **'CARDIO'**
  String get cardioEyebrowGeneric;

  /// Phase 38b — activity label for treadmill (uppercase, eyebrow register).
  ///
  /// In en, this message translates to:
  /// **'RUNNING'**
  String get cardioActivityRunning;

  /// Phase 38b — activity label for rowing_machine.
  ///
  /// In en, this message translates to:
  /// **'ROWING'**
  String get cardioActivityRowing;

  /// Phase 38b — activity label for stationary_bike / assault_bike.
  ///
  /// In en, this message translates to:
  /// **'CYCLING'**
  String get cardioActivityCycling;

  /// Phase 38b — activity label for jump_rope.
  ///
  /// In en, this message translates to:
  /// **'JUMP ROPE'**
  String get cardioActivityJumpRope;

  /// Phase 38b — activity label for elliptical.
  ///
  /// In en, this message translates to:
  /// **'ELLIPTICAL'**
  String get cardioActivityElliptical;

  /// Phase 38b — activity label for sled_push / sled_drag.
  ///
  /// In en, this message translates to:
  /// **'SLED'**
  String get cardioActivitySled;

  /// Phase 38b — tiny uppercase unit label under the mm:ss duration hero.
  ///
  /// In en, this message translates to:
  /// **'MIN'**
  String get cardioDurationMinLabel;

  /// Phase 38b — field label above the optional distance value (uppercase, field-label register).
  ///
  /// In en, this message translates to:
  /// **'DISTANCE'**
  String get cardioDistanceLabel;

  /// Phase 38b — field label above the optional RPE value when empty.
  ///
  /// In en, this message translates to:
  /// **'EFFORT (RPE)'**
  String get cardioEffortLabel;

  /// Phase 38b — shorter field label above the RPE pips once a value is set (mirrors the locked mockup).
  ///
  /// In en, this message translates to:
  /// **'EFFORT'**
  String get cardioEffortShortLabel;

  /// Phase 38b — ghost affordance on an empty optional field (distance / RPE). Invites, never nags — the mockup forbids rendering '0.0 km'.
  ///
  /// In en, this message translates to:
  /// **'+ add'**
  String get cardioAddValue;

  /// Phase 38b — done CTA at the bottom of the CardioEntryCard. Collapses the card to the summary line.
  ///
  /// In en, this message translates to:
  /// **'Complete cardio'**
  String get completeCardio;

  /// Phase 38b — duration segment of the collapsed completed-card summary line, e.g. '28:45 min'.
  ///
  /// In en, this message translates to:
  /// **'{duration} min'**
  String cardioSummaryDuration(String duration);

  /// Phase 38b — RPE segment of the collapsed summary line, e.g. 'effort 7/10'.
  ///
  /// In en, this message translates to:
  /// **'effort {rpe}/10'**
  String cardioSummaryEffort(int rpe);

  /// Phase 38b — accessibility label on the green check in the completed cardio card header (tapping un-completes).
  ///
  /// In en, this message translates to:
  /// **'Cardio logged. Tap to edit again.'**
  String get cardioUncompleteSemantics;

  /// Phase 38b — DurationStepper number-input dialog title. Accepts mm:ss or whole minutes.
  ///
  /// In en, this message translates to:
  /// **'Enter duration'**
  String get enterDuration;

  /// Phase 38b — hint inside the duration dialog text field.
  ///
  /// In en, this message translates to:
  /// **'mm:ss'**
  String get enterDurationHint;

  /// Phase 38b — distance tap-to-type dialog title.
  ///
  /// In en, this message translates to:
  /// **'Enter distance'**
  String get enterDistance;

  /// Phase 38b — accessibility label: DurationStepper minus button (30s step).
  ///
  /// In en, this message translates to:
  /// **'Decrease duration'**
  String get decrementDuration;

  /// Phase 38b — accessibility label: DurationStepper plus button (30s step).
  ///
  /// In en, this message translates to:
  /// **'Increase duration'**
  String get incrementDuration;

  /// Phase 38b — accessibility label on the DurationStepper center value zone.
  ///
  /// In en, this message translates to:
  /// **'Duration: {formatted} minutes. Tap to enter duration.'**
  String durationValueSemantics(String formatted);

  /// Phase 38b — accessibility label on the distance field of the CardioEntryCard.
  ///
  /// In en, this message translates to:
  /// **'Distance. Tap to enter distance.'**
  String get cardioDistanceSemantics;

  /// Phase 38b — accessibility label on the RPE field of the CardioEntryCard.
  ///
  /// In en, this message translates to:
  /// **'Effort (RPE). Tap to choose 1 to 10.'**
  String get cardioEffortSemantics;

  /// Phase 38b — title of the 1–10 RPE picker bottom sheet (48dp-floor targets; the inline pips are display-only).
  ///
  /// In en, this message translates to:
  /// **'Effort (RPE)'**
  String get rpeSheetTitle;

  /// Phase 38b — helper line under the RPE sheet title.
  ///
  /// In en, this message translates to:
  /// **'How hard did it feel, from 1 (easy) to 10 (max effort)?'**
  String get rpeSheetSubtitle;

  /// Phase 38b — accessibility label on each 1–10 option in the RPE sheet.
  ///
  /// In en, this message translates to:
  /// **'Effort {value} of 10'**
  String rpeOptionSemantics(int value);

  /// Phase 38d — Profile → Settings row label + AgeEditorSheet title for the optional birth-year capture.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get ageLabel;

  /// Phase 38d — dimmed value shown in the Age row when `profile.dateOfBirth == null`. Calm invitation, never an error (no warning icon).
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get ageNotSet;

  /// Phase 38d — derived age shown in the Age row + the wheel's live age tag once a birth year is picked, e.g. '39'. Computed as currentYear − birthYear; the raw stored date is never revealed (data minimization).
  ///
  /// In en, this message translates to:
  /// **'{age}'**
  String ageYears(int age);

  /// Phase 38d — one-line point-of-collection disclosure helper under the AgeEditorSheet title. DOB is LGPD Art. 6 consent, so this is a pure disclosure (NOT a sensitive-data consent toggle like gender/bodyweight).
  ///
  /// In en, this message translates to:
  /// **'We use your age to score cardio against the right fitness norms. Optional.'**
  String get ageSheetHelper;

  /// Phase 38d — tiny uppercase tracked caption above the live derived-age number in the birth-year wheel's selection band, e.g. 'age 39'.
  ///
  /// In en, this message translates to:
  /// **'age'**
  String get ageWheelTag;

  /// Phase 38d — ghost affordance in the AgeEditorSheet that clears any stored birth date to NULL (age-35 fallback) and closes the sheet.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get agePreferNotToSay;

  /// Phase 38d — accessibility label on the birth-year wheel.
  ///
  /// In en, this message translates to:
  /// **'Birth year. Swipe to choose. Currently {year}, age {age}.'**
  String ageWheelSemantics(int year, int age);

  /// Phase 38d — accessibility label on the Age settings row; `value` is the derived age string or 'Not set'.
  ///
  /// In en, this message translates to:
  /// **'Age. {value}. Tap to edit.'**
  String ageRowSemantics(String value);

  /// Phase 38d — copy in the one-time post-session nudge shown after a cardio session when DOB is null. Invite, not nag.
  ///
  /// In en, this message translates to:
  /// **'Add your age to score this cardio against the right fitness norms.'**
  String get agePromptMessage;

  /// Phase 38d — CTA in the post-session age nudge; opens the AgeEditorSheet.
  ///
  /// In en, this message translates to:
  /// **'Set age'**
  String get agePromptSetAge;

  /// Phase 38d — accessibility label on the dismiss (✕) affordance of the post-session age nudge; records the never-show-again flag.
  ///
  /// In en, this message translates to:
  /// **'Dismiss age prompt'**
  String get agePromptDismissSemantics;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
