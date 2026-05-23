/// Widget tests pinning the user-visible contract on [CinematicSkipButton]:
///
///   1. Tap fires the injected callback exactly once.
///   2. The semantics identifier `post-session-skip-btn` is present so the
///      E2E selector in `test/e2e/helpers/selectors.ts` keeps targeting it.
///
/// Both behaviors are asserted against the rendered widget tree (what the
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
              children: [CinematicSkipButton(onSkip: () => tapCount++)],
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
              body: Stack(children: [CinematicSkipButton(onSkip: () {})]),
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
            body: Stack(children: [CinematicSkipButton(onSkip: () {})]),
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
  });
}
