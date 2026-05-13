/// Regression pin: the routine-removed undo SnackBar in
/// `plan_management_screen.dart` MUST carry `persist: false`.
///
/// Same bug class as the active-workout undo SnackBars — see
/// `test/widget/features/workouts/ui/active_workout_add_exercise_snackbar_dismiss_test.dart`
/// for the full root-cause narrative.
///
/// Subtlety specific to this surface: the screen wires a
/// `controller.closed.whenComplete` listener to clear
/// `_undoSnackbarActive`. That listener fires for ANY close reason
/// (timeout, hide, dismiss, swipe, action). With persist defaulting to
/// `true`, `SnackBarClosedReason.timeout` is unreachable — the flag would
/// only clear on manual dismiss or action tap. `persist: false` restores
/// the timeout path, which the Saved-snackbar suppression logic depends
/// on.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plan-management routine-removed undo — persist:false contract', () {
    test('should declare `persist: false` in the SnackBar literal that '
        "displays `routineRemoved` — pins the production wiring", () {
      final source = File(
        'lib/features/weekly_plan/ui/plan_management_screen.dart',
      ).readAsStringSync();

      final idx = source.indexOf('routineRemoved');
      expect(
        idx,
        isNot(-1),
        reason:
            'The SnackBar literal that uses `routineRemoved` could not '
            'be found in plan_management_screen.dart. The contract test '
            'is wrong, or the undo flow was moved without updating this '
            'pin.',
      );

      final snackBarStart = source.lastIndexOf('SnackBar(', idx);
      expect(
        snackBarStart,
        isNot(-1),
        reason: 'Expected SnackBar(...) literal before routineRemoved.',
      );

      // Walk forward to the `_savePlan` call inside the undo callback,
      // then to the line that closes the SnackBar arg list.
      final savePlanIdx = source.indexOf('_savePlan(', idx);
      expect(
        savePlanIdx,
        isNot(-1),
        reason: 'Expected _savePlan inside undo onPressed.',
      );
      final snackBarLiteralEnd = source.indexOf('\n        ),', savePlanIdx);
      expect(
        snackBarLiteralEnd,
        isNot(-1),
        reason:
            'Could not locate end of SnackBar literal in '
            'plan_management_screen.dart. The file shape changed.',
      );

      final snackBarLiteral = source.substring(
        snackBarStart,
        snackBarLiteralEnd,
      );

      expect(
        snackBarLiteral.contains('persist: false'),
        isTrue,
        reason:
            "The routine-removed undo SnackBar MUST include "
            "`persist: false`. Without it, Flutter defaults `persist` to "
            "true (because an `action:` is present); the snackbar never "
            "auto-dismisses AND the `_undoSnackbarActive` suppression "
            "flag stays stuck at true (its `closed` listener never fires "
            "for the timeout path), permanently blocking the Saved-"
            "snackbar suppression contract.\n\n"
            'SnackBar literal captured:\n$snackBarLiteral',
      );

      // UI/UX 2026-05-13 follow-up — Material's X icon is the canonical
      // explicit-dismiss affordance when the SnackBar's `action:` performs
      // work other than dismiss (UNDO restores the just-removed routine).
      expect(
        snackBarLiteral.contains('showCloseIcon: true'),
        isTrue,
        reason:
            "The routine-removed undo SnackBar MUST include "
            "`showCloseIcon: true` so the user has an explicit dismiss "
            "affordance distinct from the UNDO action.\n\n"
            'SnackBar literal captured:\n$snackBarLiteral',
      );
    });

    testWidgets(
      'should disappear after the declared 5 s duration when constructed '
      'with `persist: false` + Undo action (framework contract smoke)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (innerContext) {
                    return ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(innerContext).showSnackBar(
                          SnackBar(
                            content: const Text('Routine removed'),
                            duration: const Duration(seconds: 5),
                            persist: false,
                            action: SnackBarAction(
                              label: 'UNDO',
                              onPressed: () {},
                            ),
                          ),
                        );
                      },
                      child: const Text('Remove routine'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Remove routine'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Routine removed'),
          findsOneWidget,
          reason: 'Pre-condition: snackbar visible after entrance animation.',
        );

        for (int i = 0; i < 70; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          find.text('Routine removed'),
          findsNothing,
          reason:
              'Framework contract: a SnackBar with `persist: false` + an '
              'action MUST auto-dismiss at `duration`.',
        );
      },
    );
  });
}
