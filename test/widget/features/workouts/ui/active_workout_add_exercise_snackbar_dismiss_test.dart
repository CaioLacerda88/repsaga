/// Regression pin: the add-exercise undo SnackBar in
/// `_ActiveWorkoutBody._onAddExercise` MUST be constructed via
/// `SnackBarTapOutDismissScope.showCountdownSnackBar` with the agreed
/// 3500 ms duration, the `addExerciseUndo` l10n key, and NO
/// `showCloseIcon` (rejected on-device 2026-05-13 in favour of the
/// countdown-bar + tap-out approach).
///
/// **Background.** Flutter's `SnackBar` constructor defaults `persist` to
/// `true` whenever `action != null` (`snack_bar.dart`,
/// `persist = persist ?? action != null`). With `persist: true` the
/// framework's auto-dismiss `Timer` still fires after `duration`, but
/// returns early without calling `hideCurrentSnackBar` — the SnackBar
/// then sits on-screen indefinitely. User-visible bug 2026-05-13 on
/// Android release. The fix wave moved all three undo snacks
/// (add-exercise, swipe-delete-set, plan routine-removed) to a single
/// `SnackBarTapOutDismissScope` factory that pins `persist: false`, wraps
/// the content in a countdown progress bar, and installs a screen-level
/// pointer listener that dismisses on bounding-box-outside taps.
///
/// **Why source-grep.** The snack is built inside an
/// `await ExercisePickerSheet.show` chain. The picker is a static method
/// wrapping `showModalBottomSheet` — no DI seam at the widget level.
/// Pumping the full flow (FAB → picker → pick → snack) needs ~200 lines
/// of provider/overlay stubs that assert nothing about the contract under
/// test. The source-grep below pins the production wiring directly:
/// factory entrypoint, duration, l10n key, no `showCloseIcon`. Runtime
/// behaviour of the bounding-box hit-test is covered by the dedicated
/// `snackbar_tap_out_dismiss_scope_test.dart` widget tests.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/shared/widgets/snackbar_tap_out_dismiss_scope.dart';

void main() {
  group(
    'Add-exercise undo SnackBar — countdown + tap-out factory contract',
    () {
      test('should be constructed via showCountdownSnackBar with the agreed '
          '3500 ms duration, addExerciseUndo l10n key, and NO showCloseIcon — '
          'pins the production wiring', () {
        final source = File(
          'lib/features/workouts/ui/active_workout_screen.dart',
        ).readAsStringSync();

        // Locate the call to `showCountdownSnackBar` inside
        // `_onAddExercise`. The call site is the public seam: it
        // dictates duration, l10n key, action. The factory wraps the
        // SnackBar internals (persist:false, SnackBarCountdown content)
        // — those are pinned separately by the scope's own tests.
        final factoryIdx = source.indexOf('showCountdownSnackBar(');
        expect(
          factoryIdx,
          isNot(-1),
          reason:
              'Could not find `showCountdownSnackBar(` in '
              'active_workout_screen.dart. The factory entrypoint must '
              'be the only way `_onAddExercise` shows its undo snack — '
              'so the persist:false + countdown contract can never be '
              'bypassed by reverting to a bare `showSnackBar` call.',
        );

        // Capture the call expression: from `showCountdownSnackBar(` to
        // its first `);` close. Args are split across lines so we walk
        // to the first close paren at the call's outer indent.
        final callEnd = source.indexOf(');', factoryIdx);
        expect(callEnd, isNot(-1), reason: 'Factory call has no `);` close.');
        final callExpr = source.substring(factoryIdx, callEnd);

        expect(
          callExpr.contains('addExerciseUndo'),
          isTrue,
          reason:
              'The factory call MUST pass the `addExerciseUndo` l10n key '
              'as the snack message. Captured:\n$callExpr',
        );
        expect(
          callExpr.contains('Duration(milliseconds: 3500)'),
          isTrue,
          reason:
              'The factory call MUST pass a 3500 ms duration (tuned '
              '2026-05-13 down from the original 4 s). If this fails '
              'the duration drifted from the UX spec.\n'
              'Captured:\n$callExpr',
        );

        // X-icon was rejected on-device 2026-05-13 — must NOT appear
        // anywhere near this call.
        expect(
          callExpr.contains('showCloseIcon'),
          isFalse,
          reason:
              'showCloseIcon was rejected by UI/UX on 2026-05-13 in '
              'favour of countdown-bar + tap-out dismiss. '
              'Captured:\n$callExpr',
        );
      });

      testWidgets(
        'should show, animate the countdown bar over the declared 3500 ms, '
        'then auto-dismiss (framework + scope contract smoke)',
        (tester) async {
          // Pump a minimal host that mirrors the production tree shape:
          // PopScope > ScaffoldMessenger > SnackBarTapOutDismissScope >
          // Scaffold. Taps the show-button to drive the factory directly.
          await tester.pumpWidget(
            MaterialApp(
              home: PopScope(
                canPop: false,
                onPopInvokedWithResult: (_, _) {},
                child: ScaffoldMessenger(
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
                                  message: 'Bench Press added',
                                  duration: const Duration(milliseconds: 3500),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () {},
                                  ),
                                );
                              },
                              child: const Text('Show snackbar'),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          await tester.tap(find.text('Show snackbar'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            find.text('Bench Press added'),
            findsOneWidget,
            reason: 'Pre-condition: snackbar visible after entrance animation.',
          );

          // 3500 ms duration + ~250 ms reverse animation. Pump 50 × 100 ms
          // = 5 s so the auto-dismiss Timer fires AND the resulting
          // reverse animation ticks.
          for (int i = 0; i < 50; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          expect(
            find.text('Bench Press added'),
            findsNothing,
            reason:
                'Framework + scope contract: `showCountdownSnackBar` MUST '
                'auto-dismiss at `duration`. If this fails, either the '
                'scope dropped `persist: false` or Flutter changed the '
                'persist semantics.',
          );
        },
      );
    },
  );
}
