/// Regression guard for the `SnackBarTapOutDismissScope` bounding-box
/// hit-test contract.
///
/// **The critic-flagged failure mode (the reason this test exists):**
/// users mid-set-log tap a weight stepper / "+ Add set" button on the
/// exercise card that sits *above* the snack. With a naive "tap anywhere
/// outside dismisses" handler, the dismiss fires and the 5 s
/// swipe-delete-set undo window silently cancels. The user finds their
/// set gone scrolling up later.
///
/// The scope's contract: pointer-down events are only treated as
/// "outside the snack" when the pointer position lies outside the
/// content widget's screen RECT — *not* its widget-tree subtree. So a
/// pointer landing on a stepper several rows up does NOT trigger
/// dismiss, even though the stepper is not a descendant of the snack.
///
/// This file holds two paired tests:
///
///   1. NEGATIVE — pointer-down on a stepper above the snack: snack
///      stays visible.
///   2. POSITIVE — pointer-down on an empty region above the snack:
///      snack dismisses.
///
/// We deliberately do NOT pump the full `ActiveWorkoutScreen` here. The
/// scope is feature-agnostic and lives in `lib/shared/widgets/`; pumping
/// a minimal host that reproduces the load-bearing layout (tall body
/// with a tappable widget at the top, snack overlay at the bottom) is
/// the most direct way to assert the contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/shared/widgets/snackbar_tap_out_dismiss_scope.dart';

void main() {
  group('SnackBarTapOutDismissScope — bounding-box hit-test', () {
    testWidgets(
      'should NOT dismiss the snack when the user taps a stepper above '
      'the snack region (regression guard: critic-flagged failure mode)',
      (tester) async {
        int stepperTaps = 0;

        // Layout:
        //   - "Stepper" button pinned to the TOP of the screen.
        //   - "Show snack" button pinned to the CENTER.
        //   - Snack appears at the BOTTOM after tapping show.
        // The stepper is well outside the snack's rendered rect, so a
        // pointer-down on it must NOT dismiss the snack.
        await tester.pumpWidget(
          MaterialApp(
            home: ScaffoldMessenger(
              child: SnackBarTapOutDismissScope(
                child: Scaffold(
                  body: Column(
                    children: [
                      // Stepper at top — a representative "card content"
                      // widget the user might tap mid-set-log.
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevatedButton(
                          key: const ValueKey('stepper'),
                          onPressed: () => stepperTaps++,
                          child: const Text('Stepper'),
                        ),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (innerContext) {
                          return ElevatedButton(
                            onPressed: () {
                              SnackBarTapOutDismissScope.of(
                                innerContext,
                              ).showCountdownSnackBar(
                                context: innerContext,
                                message: 'Set 1 deleted',
                                duration: const Duration(seconds: 10),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () {},
                                ),
                              );
                            },
                            child: const Text('Show snack'),
                          );
                        },
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Trigger the snack and let the entrance animation finish.
        await tester.tap(find.text('Show snack'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Set 1 deleted'),
          findsOneWidget,
          reason: 'Pre-condition: snack visible after entrance animation.',
        );

        // Tap the stepper at the TOP. This is the load-bearing assertion:
        // the snack must REMAIN visible AND the stepper's own onPressed
        // must still fire.
        await tester.tap(find.byKey(const ValueKey('stepper')));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          stepperTaps,
          1,
          reason:
              'The stepper`s own tap handler MUST still fire — the scope`s '
              'Listener uses HitTestBehavior.translucent so child '
              'gestures are unaffected.',
        );
        expect(
          find.text('Set 1 deleted'),
          findsOneWidget,
          reason:
              'CRITIC-FLAGGED CONTRACT: a pointer-down on a widget '
              'OUTSIDE the snack`s rendered rect must NOT dismiss the '
              'snack — otherwise the undo window silently cancels when '
              'the user taps any chrome on the screen.',
        );
      },
    );

    testWidgets(
      'should dismiss the snack when the user taps an empty region above '
      'the snack (positive companion test)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ScaffoldMessenger(
              child: SnackBarTapOutDismissScope(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (innerContext) {
                        return ElevatedButton(
                          onPressed: () {
                            SnackBarTapOutDismissScope.of(
                              innerContext,
                            ).showCountdownSnackBar(
                              context: innerContext,
                              message: 'Set 1 deleted',
                              duration: const Duration(seconds: 10),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () {},
                              ),
                            );
                          },
                          child: const Text('Show snack'),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Show snack'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Set 1 deleted'), findsOneWidget);

        // Tap somewhere clearly above the snack region. The default test
        // viewport is 800 × 600; an empty point at y=100 lands far above
        // the bottom-edge snack.
        await tester.tapAt(const Offset(400, 100));
        await tester.pump();
        // Reverse animation runs ~250 ms.
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Set 1 deleted'),
          findsNothing,
          reason:
              'Tap on an empty region above the snack MUST dismiss the '
              'snack — that is the tap-out contract. If this fails the '
              'scope`s Listener is not firing, or the bounding-box rect '
              'is computed wrong.',
        );
      },
    );

    testWidgets(
      'should NOT dismiss when the pointer-down lands inside the snack '
      'content rect (sanity: tapping the snack itself never dismisses)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ScaffoldMessenger(
              child: SnackBarTapOutDismissScope(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (innerContext) {
                        return ElevatedButton(
                          onPressed: () {
                            SnackBarTapOutDismissScope.of(
                              innerContext,
                            ).showCountdownSnackBar(
                              context: innerContext,
                              message: 'Set 1 deleted',
                              duration: const Duration(seconds: 10),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () {},
                              ),
                            );
                          },
                          child: const Text('Show snack'),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Show snack'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Set 1 deleted'), findsOneWidget);

        // Tap the snack message text directly.
        await tester.tap(find.text('Set 1 deleted'));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('Set 1 deleted'),
          findsOneWidget,
          reason:
              'A tap INSIDE the snack must never dismiss it — the user '
              'expects the snack to remain visible while they read its '
              'content.',
        );
      },
    );
  });
}
