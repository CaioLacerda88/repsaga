import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../connectivity/connectivity_provider.dart';
import '../theme/app_icons.dart';
import '../local_storage/cache_refresh_provider.dart';
import '../offline/sync_service.dart';
import '../observability/sentry_init.dart' show sanitizeRouteName;
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/providers/onboarding_provider.dart';
import '../../features/auth/providers/signup_state_provider.dart';
import '../../features/auth/ui/email_confirmation_screen.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/auth/ui/onboarding_screen.dart';
import '../../features/auth/ui/splash_screen.dart';
import '../../features/exercises/ui/create_exercise_screen.dart';
import '../../features/exercises/ui/exercise_detail_screen.dart';
import '../../features/exercises/ui/exercise_list_screen.dart';
import '../../features/rpg/ui/saga_intro_gate.dart';
import '../../features/workouts/models/active_workout_state.dart';
import '../../features/workouts/providers/workout_providers.dart';
import '../../features/profile/ui/manage_data_screen.dart';
import '../../features/profile/ui/profile_settings_screen.dart';
import '../../features/rpg/models/body_part.dart';
import '../../features/rpg/ui/character_sheet_screen.dart';
import '../../features/rpg/ui/stats_deep_dive_screen.dart';
import '../../features/rpg/ui/titles_screen.dart';
import '../../features/routines/ui/create_routine_screen.dart';
import '../../features/routines/ui/routine_list_screen.dart';
import '../../features/personal_records/domain/pr_detection_service.dart';
import '../../features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import '../../features/personal_records/ui/pr_celebration_screen.dart';
import '../../features/personal_records/ui/pr_list_screen.dart';
import '../../features/workouts/ui/active_workout_screen.dart';
import '../../features/workouts/ui/home_screen.dart';
import '../../features/weekly_plan/ui/week_plan_screen.dart';
import '../../features/rpg/providers/earned_titles_backfill_provider.dart';
import '../../features/rpg/providers/rpg_progress_provider.dart';
import '../../features/workouts/ui/workout_detail_screen.dart';
import '../../features/routines/models/routine.dart';
import '../../features/workouts/ui/workout_history_screen.dart';
import '../../shared/widgets/legal_doc_screen.dart';
import '../../shared/widgets/offline_banner.dart';
import '../theme/app_theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _RouterRefreshListenable(ref),
    observers: [
      SentryNavigatorObserver(
        enableAutoTransactions: false,
        setRouteNameAsTransaction: false,
        routeNameExtractor: sanitizeRouteName,
      ),
    ],
    redirect: (context, state) {
      // Read authState inside the redirect callback (not at routerProvider
      // construction time) so GoRouter is never recreated on auth events.
      // _RouterRefreshListenable already watches authStateProvider and calls
      // notifyListeners() to trigger redirect re-evaluation when auth changes.
      final authState = ref.read(authStateProvider);
      final isLoading = authState.isLoading;
      final isLoggedIn = authState.value?.session != null;
      final needsOnboarding = ref.read(needsOnboardingProvider);
      final location = state.matchedLocation;

      // While auth is resolving, stay on splash.
      if (isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      // Not logged in → go to login (unless already there, on email
      // confirmation, or viewing a public legal page).
      if (!isLoggedIn) {
        final hasSignupPending = ref.read(signupPendingEmailProvider) != null;
        if (location == '/email-confirmation' && hasSignupPending) return null;
        if (location == '/privacy-policy' || location == '/terms-of-service') {
          return null;
        }
        return location == '/login' ? null : '/login';
      }

      // Logged in → clear any pending signup state.
      ref.read(signupPendingEmailProvider.notifier).state = null;

      // Logged in but needs onboarding → go to onboarding.
      if (needsOnboarding && location != '/onboarding') {
        return '/onboarding';
      }

      // Logged in, on login or splash → go home.
      if (location == '/login' || location == '/splash') {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/email-confirmation',
        builder: (context, state) => const EmailConfirmationScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (context, state) => const LegalDocScreen(
          title: 'Privacy Policy',
          assetPath: 'assets/legal/privacy_policy.md',
        ),
      ),
      GoRoute(
        path: '/terms-of-service',
        builder: (context, state) => const LegalDocScreen(
          title: 'Terms of Service',
          assetPath: 'assets/legal/terms_of_service.md',
        ),
      ),
      GoRoute(
        path: '/workout/active',
        redirect: (context, state) {
          // Check in-memory state first (set immediately by startWorkout),
          // then fall back to Hive (persisted across restarts).
          final inMemory = ref.read(activeWorkoutProvider).value;
          final inHive = ref.read(hasActiveWorkoutProvider);
          if (inMemory == null && !inHive) return '/home';
          return null;
        },
        builder: (context, state) => const ActiveWorkoutScreen(),
      ),
      GoRoute(
        path: '/pr-celebration',
        redirect: (context, state) {
          // Validate the entire envelope here so the builder never has to
          // assert types on `state.extra`. A redirect is the right place for
          // this — the alternative (throwing inside the builder) would crash
          // the navigator with a typed `StateError` instead of a graceful
          // redirect to /home, which is what we want for a programmer error
          // that slipped past compile time.
          return validatePrCelebrationExtra(state.extra) ? null : '/home';
        },
        builder: (context, state) {
          // The redirect above guarantees the shape; build a typed
          // [PrCelebrationArgs] so a future refactor that breaks the contract
          // surfaces as a typed `StateError` (programmer error) rather than a
          // cryptic Dart cast crash. Keep these checks in addition to the
          // redirect — the builder may be re-invoked on rebuild even after
          // the redirect approved the entry. Defense in depth (BUG-010).
          final args = PrCelebrationArgs.fromExtra(state.extra);
          return PRCelebrationScreen(
            result: args.result,
            exerciseNames: args.exerciseNames,
            planPromptRoutineId: args.planPromptRoutineId,
            planPromptRoutineName: args.planPromptRoutineName,
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) =>
            SagaIntroGate(child: _ShellScaffold(child: child)),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
            routes: [
              GoRoute(
                path: 'history',
                builder: (context, state) => const WorkoutHistoryScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => WorkoutDetailScreen(
                      workoutId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/exercises',
            builder: (context, state) => const ExerciseListScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) => const CreateExerciseScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => ExerciseDetailScreen(
                  exerciseId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/routines',
            builder: (context, state) => const RoutineListScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) =>
                    CreateRoutineScreen(routine: state.extra as Routine?),
              ),
            ],
          ),
          GoRoute(
            path: '/records',
            builder: (context, state) => const PRListScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const CharacterSheetScreen(),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (context, state) => const ProfileSettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'manage-data',
                    builder: (context, state) => const ManageDataScreen(),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/saga/stats',
            builder: (context, state) {
              // Deep-link: ?body_part=<slug> pre-selects the trend chart.
              final bodyPartToken = state.uri.queryParameters['body_part'];
              final initialBodyPart = bodyPartToken == null
                  ? null
                  : BodyPart.tryFromDbValue(bodyPartToken);
              return StatsDeepDiveScreen(initialBodyPart: initialBodyPart);
            },
          ),
          GoRoute(
            path: '/saga/titles',
            builder: (context, state) => const TitlesScreen(),
          ),
          GoRoute(
            path: '/plan/week',
            builder: (context, state) => const WeekPlanScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Typed envelope for the `/pr-celebration` route's `state.extra`.
///
/// **Why a class instead of inline casts:** the route receives a freeform
/// `Map<String, dynamic>` because GoRouter's `extra` is `Object?`. Pulling the
/// validation into a single named factory means there is exactly ONE place to
/// keep the schema in sync with the navigator pushes — and a unit test can
/// pin the contract without standing up a full router.
///
/// All factories throw [StateError] (programmer error) on shape mismatch
/// rather than a cryptic Dart cast — the redirect on the route catches the
/// `false` return of [validatePrCelebrationExtra] before the builder runs, so
/// the StateError only fires if the redirect was bypassed (e.g. a builder
/// rebuild without re-running the redirect). It IS a programmer error in
/// that case, and a typed StateError makes the bug visible.
@immutable
class PrCelebrationArgs {
  const PrCelebrationArgs({
    required this.result,
    required this.exerciseNames,
    this.planPromptRoutineId,
    this.planPromptRoutineName,
  });

  /// Validates and unpacks the freeform `state.extra` shape pushed by the
  /// finish-workout flow. Throws [StateError] with a field-naming message on
  /// any drift; callers that prefer a soft fallback (the redirect) should
  /// gate on [validatePrCelebrationExtra] first.
  factory PrCelebrationArgs.fromExtra(Object? extra) {
    if (extra is! Map<String, dynamic>) {
      throw StateError('PR celebration extra is not a Map<String, dynamic>');
    }
    final result = extra['result'];
    if (result is! PRDetectionResult) {
      throw StateError(
        'PR celebration extra.result is not a PRDetectionResult',
      );
    }
    final exerciseNames = extra['exerciseNames'];
    if (exerciseNames is! Map<String, String>) {
      throw StateError(
        'PR celebration extra.exerciseNames is not a Map<String, String>',
      );
    }
    final routineId = extra['planPromptRoutineId'];
    if (routineId != null && routineId is! String) {
      throw StateError(
        'PR celebration extra.planPromptRoutineId is not a String',
      );
    }
    final routineName = extra['planPromptRoutineName'];
    if (routineName != null && routineName is! String) {
      throw StateError(
        'PR celebration extra.planPromptRoutineName is not a String',
      );
    }
    return PrCelebrationArgs(
      result: result,
      exerciseNames: exerciseNames,
      planPromptRoutineId: routineId as String?,
      planPromptRoutineName: routineName as String?,
    );
  }

  final PRDetectionResult result;
  final Map<String, String> exerciseNames;
  final String? planPromptRoutineId;
  final String? planPromptRoutineName;
}

/// Returns true when [extra] satisfies the [PrCelebrationArgs] contract.
/// Used by the route's `redirect` to soft-fail to /home on a malformed push
/// rather than throwing inside the navigator.
@visibleForTesting
bool validatePrCelebrationExtra(Object? extra) {
  if (extra is! Map<String, dynamic>) return false;
  if (extra['result'] is! PRDetectionResult) return false;
  if (extra['exerciseNames'] is! Map<String, String>) return false;
  final routineId = extra['planPromptRoutineId'];
  if (routineId != null && routineId is! String) return false;
  final routineName = extra['planPromptRoutineName'];
  if (routineName != null && routineName is! String) return false;
  return true;
}

/// Notifies GoRouter when auth state changes so it re-evaluates redirects.
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
    _ref.listen(needsOnboardingProvider, (prev, next) => notifyListeners());
  }

  final Ref _ref;
}

/// Height in logical pixels of the OfflineBanner overlay. Used to pad the
/// active tab's content so it isn't covered by the banner.
///
/// Geometry: vertical padding 12 + 12 = 24dp, plus the rendered line height
/// of `AppTextStyles.bodySmall` (`fontSize: 12 * height: 1.5` = 18dp) which
/// dominates the inner Row over the 16dp `cloud_off` icon. Total: 42dp.
///
/// The constant is only valid as long as the banner is rendered with
/// `TextScaler.noScaling` — see `_ShellScaffold.build` where the
/// `OfflineBanner` is wrapped in a `MediaQuery.copyWith(textScaler:)` to
/// pin the height. If a future change removes that pin, system text
/// scaling can grow this height (or wrap the row), and the constant must
/// either become responsive or move back to a measure-and-cache pattern.
const double _kOfflineBannerHeight = 42;

class _ShellScaffold extends ConsumerWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  /// Returns the selected tab index, or -1 for non-tab routes (e.g. /records,
  /// /plan/week) so the bottom nav does not falsely highlight a tab.
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/exercises')) return 1;
    if (location.startsWith('/routines')) return 2;
    // /profile is the Saga character sheet; /saga/* sub-routes (stats/titles)
    // are stubs that also belong to the Saga tab visually.
    if (location.startsWith('/profile') || location.startsWith('/saga')) {
      return 3;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeState = ref.watch(activeWorkoutProvider).value;
    final isOnline = ref.watch(isOnlineProvider);
    ref.watch(cacheRefreshProvider);
    ref.watch(syncServiceProvider);
    // Eagerly warm up RPG progress so it is ready when finishWorkout runs the
    // pre/post snapshot diff. Without this, the provider is lazy and only
    // initialised when the Saga screen is opened — causing the pre-snapshot
    // to be empty for users who finish a workout without visiting Saga first.
    //
    // We use `ref.listen` (no-op handler) instead of `ref.watch` so a change
    // in `rpgProgressProvider` does not rebuild the shell scaffold. The
    // shell renders no RPG state directly; rebuilding it on every XP delta
    // would invalidate the bottom-nav state for zero visual benefit. The
    // listen subscription is enough to keep the provider alive.
    ref.listen(rpgProgressProvider, (_, _) {});
    // Eagerly warm up the PR cache so per-exercise lookups (in-session
    // PR display via `exercisePRsProvider`, finish-workout detection via
    // the per-exercise fallback in `getRecordsForExercises`) have a
    // correct historical baseline from the moment the shell mounts.
    // Without this, the cache is empty on a fresh session and the first
    // working set of any exercise is falsely projected as a "new PR"
    // (AW-EX-D-US1-01 BLOCKER). Same `ref.listen` no-op pattern as
    // rpgProgressProvider — keeps the provider alive across the shell's
    // lifetime without rebuilding the scaffold on emissions.
    ref.listen(prCacheBootstrapProvider, (_, _) {});
    // One-shot backfill of `earned_titles` rows for users who pre-date the
    // detection-time INSERT migration (00061). The provider is gated by a
    // per-(user, device) Hive flag — first signed-in build calls the
    // `backfill_earned_titles(uuid)` RPC; subsequent launches no-op. RPC
    // failures are swallowed so a transient network blip never blocks the
    // shell; the flag stays unset on failure so the next session retries.
    // Same `ref.listen` no-op pattern as `prCacheBootstrapProvider` and
    // `rpgProgressProvider` — keeps the provider alive across the shell's
    // lifetime without rebuilding the scaffold on emissions.
    ref.listen(earnedTitlesBackfillProvider, (_, _) {});
    final tabIndex = _currentIndex(context);
    // When on a non-tab route (e.g. /records, /plan/week), pass index 0 to
    // satisfy NavigationBar's range requirement but hide the indicator so no
    // tab appears active.
    final isOnTab = tabIndex >= 0;

    // Family 5A / AW-EX-B-US1-03: the OfflineBanner is rendered as a
    // top-of-body overlay (Stack, painted AFTER child), not as a Column
    // sibling above the body. Putting it inside
    // `Column([OfflineBanner, Expanded(child)])` causes the banner's
    // `Semantics(identifier: 'offline-banner')` to be silently dropped from
    // the Flutter Web accessibility tree: some descendant of `child` (the
    // home/exercises/etc. tab content) registers
    // `isBlockingSemanticsOfPreviouslyPaintedNodes` (typical sources are
    // `BlockSemantics`, `ModalBarrier`, or `Drawer`-style scrims), and that
    // bit propagates up to `Expanded` and culls every sibling semantics
    // node painted before it. The banner widget then renders visually on
    // canvas but its `flt-semantics-identifier="offline-banner"` DOM node
    // never appears — breaking the E2E selector and any AT user.
    //
    // The Stack approach paints `child` first, then the banner on top, so
    // the banner is NOT a previous-sibling of the blocking node and its
    // semantics survive. The child receives `Padding` while offline so the
    // top of the active tab is not covered. Verified end-to-end with
    // Playwright `page.context().setOffline(true)` driving OFFLINE-008/009.
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: isOnline ? 0 : _kOfflineBannerHeight,
              ),
              child: child,
            ),
          ),
          if (!isOnline)
            Align(
              alignment: Alignment.topCenter,
              // Pin the banner to `TextScaler.noScaling` so its rendered
              // height stays equal to `_kOfflineBannerHeight` (42dp)
              // regardless of system font scaling. The banner is a short,
              // high-contrast visual marker — letting it scale would either
              // wrap the row (worse a11y) or push it past the padded body
              // and overlap content. Other text in the app respects the
              // user's text-scale preference; this banner is the one
              // exception, by design. See `_kOfflineBannerHeight` for the
              // height contract this pin protects.
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.noScaling),
                child: const OfflineBanner(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activeState != null) _ActiveWorkoutBanner(state: activeState),
          NavigationBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            indicatorColor: isOnTab
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            surfaceTintColor: Colors.transparent,
            selectedIndex: isOnTab ? tabIndex : 0,
            onDestinationSelected: (index) {
              const routes = ['/home', '/exercises', '/routines', '/profile'];
              final target = routes[index];

              // Always go(target). This replaces the entire match list with
              // the target branch root, discarding any sub-routes previously
              // pushed via context.push (e.g. /profile/settings, /saga/stats,
              // /home/history). The result is consistent "tap tab to return
              // to branch root" semantics across all tabs.
              //
              // We deliberately do NOT add a `current == target` no-op guard.
              // Inside a ShellRoute, RouteMatchList.uri ignores
              // ImperativeRouteMatch entries (see go_router match.dart:547),
              // so a user sitting on /profile/settings reports "currently
              // /profile" — and a guarded tap would be silently dropped.
              // Re-going to the same location with no pushed routes is a
              // cheap no-op for GoRouter (identical match list → no rebuild),
              // so removing the guard is safe.
              context.go(target);
            },
            destinations: [
              Semantics(
                container: true,
                identifier: 'nav-home',
                child: NavigationDestination(
                  icon: const _NavIcon(svg: AppIcons.home),
                  selectedIcon: const _NavIcon(
                    svg: AppIcons.home,
                    color: AppColors.hotViolet,
                  ),
                  label: AppLocalizations.of(context).navHome,
                  tooltip: '',
                ),
              ),
              Semantics(
                container: true,
                identifier: 'nav-exercises',
                child: NavigationDestination(
                  icon: const _NavIcon(svg: AppIcons.lift),
                  selectedIcon: const _NavIcon(
                    svg: AppIcons.lift,
                    color: AppColors.hotViolet,
                  ),
                  label: AppLocalizations.of(context).navExercises,
                  tooltip: '',
                ),
              ),
              Semantics(
                container: true,
                identifier: 'nav-routines',
                child: NavigationDestination(
                  icon: const _NavIcon(svg: AppIcons.plan),
                  selectedIcon: const _NavIcon(
                    svg: AppIcons.plan,
                    color: AppColors.hotViolet,
                  ),
                  label: AppLocalizations.of(context).navRoutines,
                  tooltip: '',
                ),
              ),
              Semantics(
                container: true,
                identifier: 'nav-profile',
                child: NavigationDestination(
                  icon: const _NavIcon(svg: AppIcons.hero),
                  selectedIcon: const _NavIcon(
                    svg: AppIcons.hero,
                    color: AppColors.hotViolet,
                  ),
                  label: AppLocalizations.of(context).sagaTabLabel,
                  tooltip: '',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveWorkoutBanner extends ConsumerWidget {
  const _ActiveWorkoutBanner({required this.state});

  final ActiveWorkoutState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final elapsed = ref.watch(elapsedTimerProvider(state.workout.startedAt));

    return Semantics(
      container: true,
      identifier: 'home-active-banner',
      button: true,
      label: 'Active workout: ${state.workout.name}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => context.go('/workout/active'),
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcons.render(
                AppIcons.lift,
                color: theme.colorScheme.onPrimary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.workout.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                elapsed.when(
                  data: _formatElapsed,
                  loading: () => '...',
                  error: (_, _) => '',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: theme.colorScheme.onPrimary),
            ],
          ),
        ),
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }
}

/// Fixed-size SVG nav icon (24dp) for the bottom NavigationBar.
///
/// The icon is decorative at this layer; the enclosing `NavigationDestination`
/// already exposes its own label to the accessibility tree.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.svg, this.color = AppColors.textDim});

  final String svg;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppIcons.render(svg, color: color, size: 24);
  }
}
