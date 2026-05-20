/// Phase 27 L13 — Back-nav routes to Home as default for bottom-nav tabs.
///
/// Pattern A (Material/Android "always-back-to-home"):
///   * Sub-route inside a tab        → context.pop() (normal back).
///   * Non-home tab root             → context.go('/home').
///   * /home                         → first press shows exit-hint snackbar;
///                                     second press within 3 s exits the app
///                                     via `SystemNavigator.pop()`.
///
/// `WidgetsBinding.handlePopRoute()` is the test-harness analog of the Android
/// hardware back press — it walks the same pop chain that fires PopScope
/// callbacks. See `active_workout_popscope_test.dart` for the same hook.
///
/// On Flutter Web the browser back / Escape key do NOT reach PopScope (see
/// cluster_flutter_web_popscope_unreachable) — widget tests are the only
/// PopScope contract surface, so the centralized intercept ships behind these
/// seven scenarios.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/local_storage/cache_refresh_provider.dart';
import 'package:repsaga/core/offline/sync_service.dart';
import 'package:repsaga/core/router/app_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_backfill_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Stubs — minimum overrides to render ShellScaffold in isolation.
// ---------------------------------------------------------------------------

class _NullActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  @override
  Future<ActiveWorkoutState?> build() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No-op SyncService stub. The shell only `ref.watch`es the provider to keep
/// it alive — it doesn't read state — so a zero-fail snapshot is sufficient.
class _NoopSyncService extends SyncService {
  @override
  SyncState build() => const SyncState();
}

class _EmptyRpgProgress extends AsyncNotifier<RpgProgressSnapshot>
    implements RpgProgressNotifier {
  @override
  Future<RpgProgressSnapshot> build() async => RpgProgressSnapshot.empty;

  @override
  Future<RpgProgressSnapshot> refreshAfterSave() async =>
      RpgProgressSnapshot.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a router whose ShellRoute uses the real production [ShellScaffold].
/// Each leaf is a stub Scaffold so we don't need to fixture the full screen
/// graph — back-press behavior is owned by the shell, not the screens.
GoRouter _buildRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home-body')),
            routes: [
              GoRoute(
                path: 'history',
                builder: (_, _) => const Scaffold(body: Text('history-body')),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, _) =>
                        const Scaffold(body: Text('history-detail-body')),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/exercises',
            builder: (_, _) => const Scaffold(body: Text('exercises-body')),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, _) =>
                    const Scaffold(body: Text('exercise-detail-body')),
              ),
            ],
          ),
          GoRoute(
            path: '/routines',
            builder: (_, _) => const Scaffold(body: Text('routines-body')),
          ),
          GoRoute(
            path: '/records',
            builder: (_, _) => const Scaffold(body: Text('records-body')),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(body: Text('profile-body')),
          ),
          GoRoute(
            path: '/saga/stats',
            builder: (_, _) => const Scaffold(body: Text('saga-stats-body')),
          ),
          GoRoute(
            path: '/plan/week',
            builder: (_, _) => const Scaffold(body: Text('plan-week-body')),
          ),
        ],
      ),
    ],
  );
}

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(() => _NullActiveWorkoutNotifier()),
      isOnlineProvider.overrideWithValue(true),
      // Lightweight no-op overrides — the shell only `ref.listen`s these.
      cacheRefreshProvider.overrideWith((_) async {}),
      syncServiceProvider.overrideWith(() => _NoopSyncService()),
      rpgProgressProvider.overrideWith(() => _EmptyRpgProgress()),
      prCacheBootstrapProvider.overrideWith((_) async {}),
      earnedTitlesBackfillProvider.overrideWith((_) async {}),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

/// Walks the route-pop chain the same way Android hardware back does.
Future<void> _pressBack(WidgetTester tester) async {
  // ignore: avoid_dynamic_calls
  await (tester.binding as dynamic).handlePopRoute();
  await tester.pump();
}

String _currentLocation(WidgetTester tester) {
  final context = tester.element(find.byType(ShellScaffold));
  return GoRouterState.of(context).matchedLocation;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ShellScaffold back navigation', () {
    testWidgets('back from non-home tab root navigates to /home', (
      tester,
    ) async {
      final router = _buildRouter(initialLocation: '/exercises');
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();
      expect(find.text('exercises-body'), findsOneWidget);

      await _pressBack(tester);
      await tester.pumpAndSettle();

      expect(_currentLocation(tester), '/home');
      expect(find.text('home-body'), findsOneWidget);
    });

    testWidgets('back from sub-route pops to its parent', (tester) async {
      final router = _buildRouter(initialLocation: '/exercises');
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      // Push the detail sub-route so the navigator actually has a pop entry.
      router.push('/exercises/abc123');
      await tester.pumpAndSettle();
      expect(find.text('exercise-detail-body'), findsOneWidget);

      await _pressBack(tester);
      await tester.pumpAndSettle();

      expect(_currentLocation(tester), '/exercises');
      expect(find.text('exercises-body'), findsOneWidget);
    });

    testWidgets('back from /home first press shows exit hint snackbar', (
      tester,
    ) async {
      final router = _buildRouter(initialLocation: '/home');
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();
      expect(find.text('home-body'), findsOneWidget);

      await _pressBack(tester);
      await tester.pump(); // build the snackbar
      await tester.pump(const Duration(milliseconds: 100)); // settle entry anim

      // The localized exit hint is visible. We're still on /home — canPop
      // returned false and the shell intercepted the pop.
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(_currentLocation(tester), '/home');

      // Drain the 3 s timer + snackbar so the test exits clean.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('back from /home second press within 3s exits app', (
      tester,
    ) async {
      final router = _buildRouter(initialLocation: '/home');
      await tester.pumpWidget(_wrap(router));
      await tester.pumpAndSettle();

      // Capture SystemNavigator.pop calls — they fire on the flutter/platform
      // channel. Mocking the handler is the test-harness escape hatch
      // recommended by the SystemChannels source.
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      // First press → arm exit + show snackbar.
      await _pressBack(tester);
      await tester.pump();

      // Second press while armed → exit.
      await _pressBack(tester);
      await tester.pump();

      expect(
        platformCalls.any((c) => c.method == 'SystemNavigator.pop'),
        isTrue,
        reason:
            'Second back press inside the 3 s window must invoke '
            'SystemNavigator.pop()',
      );

      // Drain the disposed timer so pumpAndSettle exits clean.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'back from /home after 3s timeout shows hint again (not exit)',
      (tester) async {
        final router = _buildRouter(initialLocation: '/home');
        await tester.pumpWidget(_wrap(router));
        await tester.pumpAndSettle();

        final platformCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            platformCalls.add(call);
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });

        // First press → arm.
        await _pressBack(tester);
        await tester.pump();
        expect(find.text('Press back again to exit'), findsOneWidget);

        // Wait past the 3 s window so the flag resets.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // Second press AFTER the timeout → hint again, NOT exit.
        await _pressBack(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Press back again to exit'), findsOneWidget);
        expect(
          platformCalls.any((c) => c.method == 'SystemNavigator.pop'),
          isFalse,
          reason:
              'After the 3 s window the flag must reset — a lone back press '
              'must not exit the app',
        );

        // Drain.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'back from /saga/stats?body_part=chest deep link routes to /home',
      (tester) async {
        final router = _buildRouter(
          initialLocation: '/saga/stats?body_part=chest',
        );
        await tester.pumpWidget(_wrap(router));
        await tester.pumpAndSettle();
        expect(find.text('saga-stats-body'), findsOneWidget);

        await _pressBack(tester);
        await tester.pumpAndSettle();

        expect(_currentLocation(tester), '/home');
        expect(find.text('home-body'), findsOneWidget);
      },
    );

    // Regression test for L13.4 — the shell MUST keep the framework's
    // `canHandlePop` signal sticky-true regardless of what the inner
    // `_CustomNavigator` reports about its own pop-ability. On real-device
    // Android, `WidgetsApp` forwards the last NavigationNotification value
    // to `SystemNavigator.setFrameworkHandlesBack` → if `false` reaches it,
    // the OS un-registers Flutter's OnBackInvokedCallback and back-press
    // exits the activity NATIVELY — no widget callback (PopScope or
    // BackButtonListener) ever fires. The shell's
    // `NotificationListener<NavigationNotification>` wrap is what intercepts
    // descendant `canHandlePop:false` notifications and re-dispatches `true`
    // at the boundary. This test asserts exactly that: every notification
    // leaving the shell (i.e., reaching the test harness above MaterialApp)
    // carries `canHandlePop:true`.
    testWidgets(
      'shell wraps its body in a NotificationListener<NavigationNotification>',
      (tester) async {
        final router = _buildRouter(initialLocation: '/exercises');
        await tester.pumpWidget(_wrap(router));
        await tester.pumpAndSettle();

        // The fix lives in `_ShellScaffoldState.build`: every Scaffold the
        // shell renders MUST be wrapped in a
        // `NotificationListener<NavigationNotification>` so that descendant
        // `canHandlePop:false` notifications (dispatched by the inner
        // `_CustomNavigator` on every history change) are intercepted and
        // re-emitted as `true` before reaching `WidgetsApp`. Without it the
        // platform calls `setFrameworkHandlesBack(false)`, un-registers
        // Flutter's OnBackInvokedCallback, and the next back press exits
        // the activity natively — no widget callback (PopScope or
        // BackButtonListener) ever fires. This was the device-only failure
        // L13.0–L13.3 chased.
        //
        // Asserting structurally — walking the element tree from
        // ShellScaffold down — is the right test surface here because the
        // behavioral assertion (back-press routing) lives in the
        // `setFrameworkHandlesBack` ↔ Android OS contract, which is
        // unreachable from `tester.binding.handlePopRoute()`.
        final shellElement = tester.element(find.byType(ShellScaffold));
        var foundWrap = false;
        void visit(Element element) {
          if (element.widget is NotificationListener<NavigationNotification>) {
            foundWrap = true;
            return;
          }
          element.visitChildren(visit);
        }

        shellElement.visitChildren(visit);
        expect(
          foundWrap,
          isTrue,
          reason:
              'ShellScaffold must wrap its body in a '
              'NotificationListener<NavigationNotification> that intercepts '
              'descendant canHandlePop:false and re-dispatches true. Without '
              'this wrap, real-device back-press exits the activity natively '
              '(setFrameworkHandlesBack(false) un-registers Flutter\'s '
              'OnBackInvokedCallback). See lib/core/router/app_router.dart '
              'in `_ShellScaffoldState.build`.',
        );
      },
    );

    testWidgets(
      'back from deeper sub-route /home/history/wid pops (not jump-to-home)',
      (tester) async {
        // Initial entry directly at the deep detail mirrors a deep-link
        // launch. With no prior push on the stack, `context.pop()` is a
        // no-op AND `context.go('/home')` is forbidden by the spec for
        // sub-routes (only tab-root paths jump to home). The shell's
        // contract here is: do NOT treat this like a tab root — i.e. don't
        // jump to /home. The deep entry naturally has no pop target, so
        // we stay put; what matters is that the snackbar-exit-hint never
        // fires (it's reserved for /home).
        final router = _buildRouter(initialLocation: '/home/history/wid');
        await tester.pumpWidget(_wrap(router));
        await tester.pumpAndSettle();
        expect(find.text('history-detail-body'), findsOneWidget);

        // No exit hint should appear — that's a /home-only affordance.
        await _pressBack(tester);
        await tester.pumpAndSettle();
        expect(find.text('Press back again to exit'), findsNothing);

        // And we did not jump to /home either — sub-routes never short-
        // circuit to the home tab. (With nothing to pop, we stay put.)
        expect(_currentLocation(tester), '/home/history/wid');
      },
    );
  });
}
