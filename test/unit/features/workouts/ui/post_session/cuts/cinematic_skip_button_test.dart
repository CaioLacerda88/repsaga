/// Widget tests pinning the user-visible contract on [CinematicSkipButton]:
///
///   1. Tap fires the injected callback exactly once.
///   2. The semantics identifier `post-session-skip-btn` is present so the
///      E2E selector in `test/e2e/helpers/selectors.ts` keeps targeting it.
///   3. The button declares `button: true` so AOM elements forward taps
///      (cluster: semantics-button-missing).
///   4. The provided label string is actually rendered (UX pass 2,
///      2026-05-23 — the label is the load-bearing visibility hook).
///   5. The rendered tap target is at least 40dp tall + 40dp wide (per
///      memory feedback_tap_target_measurement — Material's
///      MaterialTapTargetSize.padded doesn't apply to raw GestureDetectors,
///      so the widget must size up explicitly).
///
/// All behaviors are asserted against the rendered widget tree (what the
/// user sees / what the AOM exposes), not via mock-call counting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/cinematic_skip_button.dart';

void main() {
  group('CinematicSkipButton', () {
    testWidgets('tap fires the onSkip callback exactly once', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                CinematicSkipButton(label: 'SKIP', onSkip: () => tapCount++),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CinematicSkipButton));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets(
      'carries the post-session-skip-btn semantics identifier so the E2E '
      'selector resolves it',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [CinematicSkipButton(label: 'SKIP', onSkip: () {})],
              ),
            ),
          ),
        );

        final node = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'post-session-skip-btn',
        );
        expect(node, findsOneWidget);
      },
    );

    testWidgets('declares button: true so AOM elements forward taps (cluster: '
        'semantics-button-missing)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [CinematicSkipButton(label: 'SKIP', onSkip: () {})],
            ),
          ),
        ),
      );

      final node = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.identifier == 'post-session-skip-btn' &&
            w.properties.button == true,
      );
      expect(
        node,
        findsOneWidget,
        reason: 'Skip button must declare button:true for AOM tap forwarding',
      );
    });

    testWidgets('renders the provided label string so users can see the '
        'affordance (UX pass 2)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [CinematicSkipButton(label: 'PULAR', onSkip: () {})],
            ),
          ),
        ),
      );

      expect(
        find.text('PULAR'),
        findsOneWidget,
        reason:
            'Label string must render so users actually notice the skip '
            'pill (root cause of pass 1 invisibility)',
      );
    });

    testWidgets('rendered tap target is at least 40dp tall + wide (memory: '
        'feedback_tap_target_measurement)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [CinematicSkipButton(label: 'SKIP', onSkip: () {})],
            ),
          ),
        ),
      );

      // Measure the rendered tap surface — Decorated pill + Row content.
      // Use the GestureDetector descendant; the outer Positioned/SafeArea
      // don't contribute to the tap surface size.
      final tapSize = tester.getSize(find.byType(GestureDetector));
      expect(
        tapSize.height,
        greaterThanOrEqualTo(40.0),
        reason: 'Tap target must be >= 40dp tall (Material minimum)',
      );
      expect(
        tapSize.width,
        greaterThanOrEqualTo(40.0),
        reason: 'Tap target must be >= 40dp wide (Material minimum)',
      );
    });
  });
}
