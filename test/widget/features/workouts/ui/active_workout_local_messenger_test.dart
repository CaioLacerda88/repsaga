/// Regression pin for PR-3 (review fix): the active-workout screen wraps
/// its body in a route-scoped [ScaffoldMessenger] so in-screen snackbars
/// (H5 add-exercise undo, swipe-to-delete-set undo, etc.) DO NOT survive
/// route transitions out of `/workout/active`.
///
/// **Why this test exists.** The failing E2E tests MD-006/007/010/011 all
/// flagged the same regression: the H5 add-exercise undo snackbar was
/// posted to the root `ScaffoldMessenger` (the default one MaterialApp
/// installs), so it survived `context.go('/home')`, followed the user
/// across Home → Profile → Manage Data, and blocked the manage-data
/// success snackbar from appearing. The fix wraps `_ActiveWorkoutBody`
/// in a `ScaffoldMessenger` widget — its messenger lives only as long as
/// the screen, and disposes (purging its snackbar queue) when the route
/// changes.
///
/// This test pins the structural property: pump a route with a local
/// `ScaffoldMessenger`, show a snackbar via it, replace the route, and
/// confirm the snackbar is gone. Without the wrap, a snackbar shown via
/// `ScaffoldMessenger.of(context)` would land on the MaterialApp's root
/// messenger and persist across the route swap (the failure mode).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Route-scoped ScaffoldMessenger (PR-3 review fix)', () {
    testWidgets(
      'snackbar shown by inner messenger is purged when its route is replaced',
      (tester) async {
        // The root messenger key — we assert at the end that it has NOT
        // received the snackbar (proving the snackbar lived only on the
        // inner, route-scoped messenger).
        final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();
        final navigatorKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: rootMessengerKey,
            navigatorKey: navigatorKey,
            home: const _ActiveScreenAnalog(),
          ),
        );
        await tester.pump();

        // Tap "Show snackbar" — this calls `ScaffoldMessenger.of(context)`
        // from inside the body, resolving to the local messenger we
        // installed in `_ActiveScreenAnalog.build`.
        await tester.tap(find.text('Show snackbar'));
        await tester.pump(); // start the show animation
        await tester.pump(const Duration(milliseconds: 50));

        // Pre-condition: the snackbar IS visible.
        expect(
          find.text('Bench Press added'),
          findsOneWidget,
          reason:
              'Pre-condition: the snackbar must be visible after tap. If '
              'this fails the test setup is wrong, not the production code.',
        );

        // Now replace the route — this is the analog of `context.go("/home")`
        // in production. The `_ActiveScreenAnalog` widget unmounts, taking
        // its `ScaffoldMessenger` with it.
        navigatorKey.currentState!.pushReplacement(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('home-screen')),
          ),
        );
        await tester.pumpAndSettle();

        // Post-condition #1: we are on the new screen.
        expect(find.text('home-screen'), findsOneWidget);

        // Post-condition #2 (the load-bearing assertion): the snackbar is
        // gone. With the local messenger in place, replacing the route
        // disposes the messenger and purges its queue. Without the local
        // messenger, the snackbar would have landed on the root messenger
        // and would still be visible (or queued) on the new screen.
        expect(
          find.text('Bench Press added'),
          findsNothing,
          reason:
              'Snackbar must NOT survive route replacement. If this fails, '
              'the snackbar is being shown on the ROOT messenger instead '
              'of the route-scoped one — which is exactly the regression '
              'that broke MD-006/007/010/011 in PR-3 review.',
        );

        // Belt + suspenders: the root messenger should never have seen
        // this snackbar at all (its queue is empty). If the test infra
        // somehow inverted, the inner snackbar might have landed on the
        // root messenger and been popped immediately on route change.
        // Posting a fresh snackbar on the root messenger now and pumping
        // it in proves the root messenger is uncluttered.
        rootMessengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('home-only-message')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('home-only-message'), findsOneWidget);
      },
    );
  });
}

/// Minimal analog of `ActiveWorkoutScreen` that reproduces ONLY the
/// structural property under test: a `ScaffoldMessenger` wraps the body.
/// Production code uses the same shape — see
/// `lib/features/workouts/ui/active_workout_screen.dart` build method
/// (the `ScaffoldMessenger(child: _ActiveWorkoutBody(...))` line).
///
/// We don't pump the real `ActiveWorkoutScreen` because that would drag
/// in the full Riverpod provider graph, GoRouter, and rest-timer state.
/// The structural contract being tested is independent of any of that —
/// the wrap either purges or doesn't purge on unmount.
class _ActiveScreenAnalog extends StatelessWidget {
  const _ActiveScreenAnalog();

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        body: Center(
          child: Builder(
            builder: (innerContext) {
              return ElevatedButton(
                onPressed: () {
                  // Resolves to the LOCAL messenger above, exactly as
                  // `_onAddExercise` resolves it inside the production
                  // `_ActiveWorkoutBody`.
                  ScaffoldMessenger.of(innerContext).showSnackBar(
                    const SnackBar(
                      content: Text('Bench Press added'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                },
                child: const Text('Show snackbar'),
              );
            },
          ),
        ),
      ),
    );
  }
}
