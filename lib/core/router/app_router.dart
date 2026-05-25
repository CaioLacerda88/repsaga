import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import '../../features/personal_records/ui/pr_list_screen.dart';
import '../../features/workouts/ui/post_session/post_session_controller.dart';
import '../../features/workouts/ui/active_workout_screen.dart';
import '../../features/workouts/ui/home_screen.dart';
import '../../features/workouts/ui/post_session/post_session_screen.dart';
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
      // Phase 30 PR 30a — full-screen cinematic post-session route.
      // **Push-only** (never deep-linked, never popable to active workout —
      // back goes to home). Receives `PostSessionParams` via `state.extra`.
      //
      // Cluster: `gorouter-context-go-vs-push` — we use `go()` from the
      // coordinator (not `push()`) because the active-workout screen has
      // already unmounted by the time we navigate here; `push()` would
      // leave a dead route entry behind it.
      //
      // PR 30c retired the legacy `/pr-celebration` route — the post-session
      // cinematic is the canonical post-finish destination for online +
      // non-empty sessions; offline / zero-set finishes still land on /home.
      GoRoute(
        path: '/workout/finish/:workoutId',
        name: 'postWorkoutFinish',
        redirect: (context, state) {
          // Soft-fail to /home on a malformed extra envelope; the route is
          // push-only so the only way to land here without a valid extra is
          // a programmer error.
          if (state.extra is! PostSessionParams) return '/home';
          return null;
        },
        builder: (context, state) {
          final params = state.extra! as PostSessionParams;
          return PostSessionScreen(
            params: params,
            // Decoupling Rule 8 — the route container wires GoRouter.
            onContinue: () => context.go('/home'),
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) =>
            SagaIntroGate(child: ShellScaffold(child: child)),
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

/// Notifies GoRouter when auth state changes so it re-evaluates redirects.
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
    _ref.listen(needsOnboardingProvider, (prev, next) => notifyListeners());
  }

  final Ref _ref;
}

/// Height in logical pixels of the OfflineBanner CONTENT (the rendered Row
/// with icon + text), NOT including the status bar inset above it. The
/// banner is wrapped in `SafeArea(top: true)` in `_ShellScaffold.build`
/// so it sits below the system status bar; the body's Padding therefore
/// uses `MediaQuery.viewPadding.top + _kOfflineBannerHeight` to compute
/// total vertical space the banner occupies.
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

/// Bottom-nav shell. Public for `@visibleForTesting` access from
/// `test/widget/core/router/shell_back_nav_test.dart` — the back-press
/// contract lives entirely inside `_handleBackButton` and there is no Flutter Web
/// path to drive it via E2E (see `cluster-flutter-web-popscope-unreachable`).
@visibleForTesting
class ShellScaffold extends ConsumerStatefulWidget {
  const ShellScaffold({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<ShellScaffold> {
  /// True after the first back-press on `/home` and until the 3-second
  /// `_exitTimer` resets it. A second press while this is true triggers
  /// `SystemNavigator.pop()`. Local widget state — no Riverpod — because the
  /// concern is purely ephemeral UI bookkeeping that lives and dies with
  /// the shell's mount.
  bool _exitPending = false;
  Timer? _exitTimer;

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

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

  /// Centralized back-press intercept (Pattern A — Material/Android
  /// "always-back-to-home"):
  ///
  ///   1. Sub-route inside a tab (inner navigator can pop) → return `false`
  ///      so GoRouter's `RouterDelegate.popRoute()` runs the normal pop
  ///      (e.g. `/exercises/abc123` → `/exercises`).
  ///   2. Non-home tab root → `context.go('/home')` jumps to Home as the
  ///      default destination.
  ///   3. `/home` → first press shows a localized exit hint snackbar and arms
  ///      a 3-second timer. Second press inside the window calls
  ///      `SystemNavigator.pop()`; otherwise the flag resets.
  ///
  /// Returns `true` when the back was handled (Flutter skips the default
  /// exit-activity behavior); `false` when we want to let the inner navigator
  /// pop normally.
  ///
  /// Pairs with the `NotificationListener<NavigationNotification>` wrap in
  /// [build] — that wrap is what makes this callback reachable on real-device
  /// Android (cluster `nested-nav-back-gate`). See the comment block on the
  /// listener for the platform-gate causal chain.
  Future<bool> _handleBackButton() async {
    // Case 1: sub-route on top of a tab root — let GoRouter pop normally.
    // `context.canPop()` is the right discriminator here because
    // `matchedLocation` from the SHELL'S context only reports the active
    // tab (`/exercises`, never `/exercises/abc123`), making it useless for
    // tab-root vs sub-route classification.
    if (context.canPop()) {
      return false; // not handled — RouterDelegate.popRoute() will pop.
    }

    final location = GoRouterState.of(context).matchedLocation;
    final path = Uri.parse(location).path;

    // Case 3: on Home — two-tap-to-exit.
    if (path == '/home' || path == '/') {
      if (_exitPending) {
        SystemNavigator.pop();
        return true;
      }
      _arm();
      return true;
    }

    // Case 2: on another tab root — go Home (no stack push).
    context.go('/home');
    return true;
  }

  void _arm() {
    setState(() => _exitPending = true);
    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _exitPending = false);
    });

    final messenger = ScaffoldMessenger.of(context);
    // Clear any prior queued snackbar so repeated presses don't stack —
    // see cluster `route-scoped-messenger-queue` for the queue-survival
    // bug class this defends against.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).backExitHint),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
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
    // Status-bar inset for the offline-banner placement below. We capture it
    // once here so the body Padding and the SafeArea wrap on the banner
    // agree on the same value within a single build.
    final viewPaddingTop = MediaQuery.of(context).viewPadding.top;

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
    // Phase 27 L13.4: centralized back-press intercept (Pattern A —
    // "always-back-to-home"). Cluster: `nested-nav-back-gate`.
    // The [BackButtonListener] hooks the
    // [Router]'s [BackButtonDispatcher] before GoRouter's
    // [RouterDelegate.popRoute] runs; the outer
    // [NotificationListener] is what makes that callback reachable on
    // real-device Android.
    //
    // Why the [NotificationListener] is load-bearing: at a tab root the
    // inner `_CustomNavigator` (built by GoRouter inside the ShellRoute)
    // holds a single page and reports
    // `NavigationNotification(canHandlePop: false)` on every history
    // change. That bubbles up to `WidgetsApp._defaultOnNavigationNotification`
    // → `SystemNavigator.setFrameworkHandlesBack(false)` →
    // `FlutterActivity.unregisterOnBackInvokedCallback()` — after which
    // Android handles back natively (`Activity.finish()`) and Flutter
    // never sees the press. We intercept the false notification HERE,
    // before it can leave the shell, and re-dispatch as `true` so the
    // platform keeps routing back-press into Flutter. This is the same
    // shape `NavigatorPopHandler` uses for nested navigators, adapted
    // for the "always intercept at the shell" pattern. Without it,
    // PopScope/BackButtonListener BOTH appear silent on device (the
    // dispatcher chain is never invoked at all). With it, [_handleBackButton]
    // fires as expected on every back press.
    //
    // Sub-routes pop normally via `false`; tab-root presses (other than
    // /home) go to /home; /home arms a 3 s two-tap-to-exit window.
    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        if (notification.canHandlePop) {
          return false;
        }
        // Re-dispatch as canHandlePop:true so `WidgetsApp` doesn't tell the
        // platform to disable framework back-handling. The shell owns the
        // back-press contract; the inner navigator's view of "can I pop?"
        // is irrelevant to the platform gate. `dispatch` walks ANCESTORS of
        // [context] (this widget's BuildContext), so the re-dispatch can't
        // re-enter our own listener (no infinite loop). Fragility worth
        // naming: any future wrap that adds a NotificationListener<Navigation-
        // Notification> ABOVE this shell must propagate canHandlePop:true
        // (return false from its onNotification) or this gate breaks again.
        const NavigationNotification(canHandlePop: true).dispatch(context);
        return true; // stop the original
      },
      child: BackButtonListener(
        onBackButtonPressed: _handleBackButton,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                // Body Padding below explicitly adds the top inset when offline
                // so the banner (which sits in the inset via SafeArea below)
                // doesn't cover tab content. Tab content widgets ALSO wrap
                // themselves in SafeArea — we strip the top padding from
                // MediaQuery here so their SafeArea doesn't double-pad against
                // the status bar that we've already accounted for.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: !isOnline,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: isOnline
                          ? 0
                          : viewPaddingTop + _kOfflineBannerHeight,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
              if (!isOnline)
                Align(
                  alignment: Alignment.topCenter,
                  // Cluster: safearea-system-overlay-overlap — Scaffold defaults
                  // to extending body behind status bar on Android edge-to-edge;
                  // widgets painted at body y=0 (here, the OfflineBanner Align
                  // overlay) sit behind the system status bar without an
                  // explicit SafeArea wrap. Same class as the PostSessionScreen
                  // visual fix in bff76bd.
                  child: SafeArea(
                    top: true,
                    bottom: false,
                    left: false,
                    right: false,
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
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                surfaceTintColor: Colors.transparent,
                selectedIndex: isOnTab ? tabIndex : 0,
                onDestinationSelected: (index) {
                  const routes = [
                    '/home',
                    '/exercises',
                    '/routines',
                    '/profile',
                  ];
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
        ),
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
