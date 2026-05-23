/// Widget tests pinning the user-visible contract on [CinematicTapHint]:
///
///   1. The chevron renders (visible affordance).
///   2. The pulse animation drives a non-static Opacity over time (test the
///      RENDERED output, not the controller — cluster
///      `pump-duration-masks-forward`).
///   3. The widget ignores pointer events so the host screen's outer
///      `GestureDetector` still receives taps — IGNORING is the contract,
///      eating the tap would break the discoverability gesture.
///
/// **Composition-vs-isolation note.** Visibility predicates (`!_userHasTapped`,
/// `cutIndex == 0`, `elapsed < 2000ms`) are owned by [PostSessionScreen],
/// NOT this widget — see the dartdoc on [CinematicTapHint]. The host-screen
/// composition is pinned in `post_session_screen_routing_test.dart`. This
/// file pins the leaf-widget contract only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/cinematic_tap_hint.dart';

void main() {
  group('CinematicTapHint', () {
    testWidgets('renders a chevron-right icon (the affordance)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [CinematicTapHint()])),
        ),
      );

      // Pump once to drive the initial frame past initState; the widget's
      // own pulse controller is running.
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets(
      'pulse alpha varies between half-pulse frames (rendered Opacity '
      'changes — not just "controller called forward")',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Stack(children: [CinematicTapHint()])),
          ),
        );

        // Sample the Opacity widget's value at two distinct points of the
        // 1200ms pulse cycle. The cycle begins at 0.45 alpha and crests at
        // 0.85, so sampling at +150ms and +600ms must produce different
        // opacity values. If the pulse controller were broken (no .repeat
        // call, missed dispose, wrong tween), both samples would match
        // — the test catches that without inspecting the controller.
        await tester.pump(const Duration(milliseconds: 150));
        final opacityAt150ms = tester
            .widget<Opacity>(find.byType(Opacity))
            .opacity;

        await tester.pump(const Duration(milliseconds: 600));
        final opacityAt750ms = tester
            .widget<Opacity>(find.byType(Opacity))
            .opacity;

        expect(
          opacityAt150ms,
          isNot(equals(opacityAt750ms)),
          reason: 'Pulse must drive a changing Opacity over time',
        );
      },
    );

    testWidgets(
      'does not eat pointer events — host gesture detector still receives '
      'taps through the affordance',
      (tester) async {
        // Host a CinematicTapHint stacked OVER a GestureDetector. If the
        // hint eats the tap, the host counter stays at 0; if it lets the
        // tap pass through (Concept B grammar — pure affordance), the
        // host counter increments. Pin the user-visible contract — what
        // happens to the tap — not the widget-tree structure (which
        // Material's icon-rendering chain decorates with framework-owned
        // IgnorePointer nodes that we don't control).
        var hostTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => hostTaps++,
                child: const Stack(
                  fit: StackFit.expand,
                  children: [CinematicTapHint()],
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap exactly at the chevron's centre — the most adversarial
        // location (if the hint eats taps anywhere, it eats them here).
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump();

        expect(
          hostTaps,
          1,
          reason:
              'CinematicTapHint must NOT eat pointer events — the host '
              "screen's outer GestureDetector handles the tap.",
        );
      },
    );
  });
}
