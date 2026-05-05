/// Isolated widget contract for [FinishBottomBar].
///
/// The integration-level pins (Scaffold slot, AppBar absence, FAB clearance)
/// live in `test/widget/features/workouts/ui/active_workout_finish_button_test.dart`
/// — those guard the screen wiring. This file pins the bar's *own* behaviour
/// in isolation so the widget can be refactored, reused, or relocated without
/// having to spin up the full ActiveWorkoutScreen + Riverpod overrides.
///
/// Phase 20 commit 5 (BUG-020) acceptance pins:
///   1. Renders a tappable primary CTA when `enabled: true`.
///   2. CTA has the spec-required ≥56dp min height (one-handed thumb target).
///   3. CTA fires `onPressed` when tapped.
///   4. CTA is disabled (does NOT fire `onPressed`) when `enabled: false` —
///      this is how loading / cancel / "no completed sets" states surface.
///   5. The widget exposes the contract identifiers (`finish-bottom-bar`
///      ValueKey + `workout-finish-btn` Semantics identifier) that E2E tests
///      depend on (see `test/e2e/helpers/selectors.ts`).
///   6. SafeArea is wired so the CTA never collides with the system gesture
///      bar at the screen bottom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/finish_bottom_bar.dart';

import '../../../../../helpers/test_material_app.dart';

Widget _host({required bool enabled, required VoidCallback onPressed}) {
  return TestMaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      bottomNavigationBar: FinishBottomBar(
        enabled: enabled,
        onPressed: onPressed,
      ),
      body: const SizedBox.expand(),
    ),
  );
}

void main() {
  group('FinishBottomBar', () {
    testWidgets('renders the FilledButton CTA when enabled', (tester) async {
      await tester.pumpWidget(_host(enabled: true, onPressed: () {}));

      expect(find.byType(FinishBottomBar), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('CTA meets the spec-required ≥56dp min height', (tester) async {
      await tester.pumpWidget(_host(enabled: true, onPressed: () {}));

      final buttonRect = tester.getRect(find.byType(FilledButton));
      expect(
        buttonRect.height >= 56,
        isTrue,
        reason:
            'FilledButton height is ${buttonRect.height}dp — Phase 20 spec '
            'requires ≥56dp for the one-handed thumb target. Bumping below 56dp '
            'regresses BUG-020.',
      );
    });

    testWidgets('fires onPressed when tapped (enabled state)', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(enabled: true, onPressed: () => taps += 1));

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets(
      'does NOT fire onPressed when disabled (loading / no-sets state)',
      (tester) async {
        // The disabled state surfaces three things in the wild:
        //   - workout has zero completed sets (the live gate)
        //   - finish coordinator is mid-save (loading)
        //   - cancellation in flight
        // All three flow through the single `enabled` boolean. This pin guards
        // the contract without needing to mock the coordinator.
        var taps = 0;
        await tester.pumpWidget(
          _host(enabled: false, onPressed: () => taps += 1),
        );

        // Use `tester.tap(..., warnIfMissed: false)` because Material's
        // disabled FilledButton still occupies hit-test space; we just want to
        // prove the callback never fires.
        await tester.tap(find.byType(FilledButton), warnIfMissed: false);
        await tester.pump();

        expect(taps, 0);

        // Cross-check: the FilledButton's onPressed is null when disabled.
        final btn = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(btn.onPressed, isNull);
      },
    );

    testWidgets('exposes the E2E selector contract', (tester) async {
      // Two contracts we explicitly own:
      //   - ValueKey('finish-bottom-bar') on the outer Material — used by the
      //     active_workout_finish_button_test.dart FAB-clearance pin.
      //   - Semantics(identifier: 'workout-finish-btn') wrapping the button —
      //     used by `test/e2e/helpers/selectors.ts` (WORKOUT.finishButton +
      //     ROUTINE.finishButton). Renaming either silently breaks E2E.
      await tester.pumpWidget(_host(enabled: true, onPressed: () {}));

      expect(
        find.byKey(const ValueKey('finish-bottom-bar')),
        findsOneWidget,
        reason:
            'ValueKey("finish-bottom-bar") is the public contract for the FAB-'
            'clearance pin in active_workout_finish_button_test.dart.',
      );

      final finishSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.identifier == 'workout-finish-btn',
      );
      expect(
        finishSemantics,
        findsOneWidget,
        reason:
            'Semantics(identifier: "workout-finish-btn") is the public E2E '
            'contract — selectors.ts depends on it. Do not rename.',
      );
    });

    testWidgets(
      'wraps the button in SafeArea so the CTA clears system insets',
      (tester) async {
        // Phase 20 spec: bottom edge needs SafeArea(bottom: true) so the button
        // doesn't hug Android's gesture bar / iPhone's home indicator.
        await tester.pumpWidget(_host(enabled: true, onPressed: () {}));

        // Find the SafeArea descendant of FinishBottomBar.
        final safeAreaFinder = find.descendant(
          of: find.byType(FinishBottomBar),
          matching: find.byType(SafeArea),
        );
        expect(safeAreaFinder, findsOneWidget);

        final safeArea = tester.widget<SafeArea>(safeAreaFinder);
        expect(
          safeArea.top,
          isFalse,
          reason:
              'SafeArea.top should be false — the bar lives at the bottom of '
              'the screen so only the bottom inset matters; allowing the top '
              'inset would push the bar away from the screen edge on devices '
              'with notches.',
        );
        expect(
          safeArea.bottom,
          isTrue,
          reason:
              'SafeArea.bottom must be true so the FilledButton clears the '
              'gesture bar / home indicator (Phase 20 BUG-020 spec).',
        );
      },
    );
  });
}
