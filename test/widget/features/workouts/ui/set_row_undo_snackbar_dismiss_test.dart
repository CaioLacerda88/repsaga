/// Regression pin: the swipe-to-delete-set undo SnackBar in
/// `_SetRowState.build` (the Dismissible `onDismissed` callback) MUST
/// carry `persist: false`.
///
/// Companion to `active_workout_add_exercise_snackbar_dismiss_test.dart`.
/// See that file's header for the full root-cause narrative (Flutter's
/// `persist = persist ?? action != null` default in `snack_bar.dart`).
/// Same bug class, different surface: the swipe-to-delete-set
/// SnackBar carries a 10 s duration + Undo action, so the same
/// persist-by-default trap applies. PR-2 C3/Q5 extended the swipe-undo
/// window to Material's 10 s ceiling so a user mid-rest (eyes off the
/// phone) still has time to react — that extended window is meaningless
/// if the SnackBar never dismisses at all.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Swipe-to-delete-set undo SnackBar — persist:false contract', () {
    test('should declare `persist: false` in the SnackBar literal that '
        "displays `setDeleted` — pins the production wiring", () {
      final source = File(
        'lib/features/workouts/ui/widgets/set_row.dart',
      ).readAsStringSync();

      final idx = source.indexOf('setDeleted(');
      expect(
        idx,
        isNot(-1),
        reason:
            'The SnackBar literal that uses `setDeleted` could not be '
            'found in set_row.dart. The contract test is wrong, or '
            'onDismissed was renamed/moved without updating this pin.',
      );

      final snackBarStart = source.lastIndexOf('SnackBar(', idx);
      expect(
        snackBarStart,
        isNot(-1),
        reason: 'Expected SnackBar(...) literal before setDeleted.',
      );

      // showSnackBar(...) in set_row closes with `,\n            ),` —
      // the cascade-chained call's end is a `;` at the outer column 11.
      // Use the `restoreSet` line within the action's onPressed as a
      // pivot and walk forward to the SnackBar literal close.
      final restoreIdx = source.indexOf('restoreSet(', idx);
      expect(
        restoreIdx,
        isNot(-1),
        reason: 'Expected restoreSet inside undo onPressed.',
      );
      final snackBarLiteralEnd = source.indexOf('\n            ),', restoreIdx);
      expect(
        snackBarLiteralEnd,
        isNot(-1),
        reason:
            'Could not locate end of SnackBar literal in set_row.dart. '
            'The file shape changed.',
      );

      final snackBarLiteral = source.substring(
        snackBarStart,
        snackBarLiteralEnd,
      );

      expect(
        snackBarLiteral.contains('persist: false'),
        isTrue,
        reason:
            "The SnackBar literal in set_row's `onDismissed` MUST "
            "include `persist: false`. Without it, Flutter defaults "
            "`persist` to true (because an `action:` is present), and "
            "the 10 s swipe-undo window is meaningless because the "
            "SnackBar never auto-dismisses.\n\n"
            'SnackBar literal captured:\n$snackBarLiteral',
      );

      // UI/UX 2026-05-13 follow-up — Material's X icon is the canonical
      // explicit-dismiss affordance when the SnackBar's `action:` performs
      // work other than dismiss (UNDO restores the just-swiped set). The
      // swipe gesture is a precision interaction for sweaty thumbs on a
      // 16-32 dp slice of the bottom edge; a 48 dp X tap-target is
      // strictly better on gym-floor UX.
      expect(
        snackBarLiteral.contains('showCloseIcon: true'),
        isTrue,
        reason:
            "The SnackBar literal in set_row's `onDismissed` MUST include "
            "`showCloseIcon: true` so the user has an explicit dismiss "
            "affordance distinct from the UNDO action.\n\n"
            'SnackBar literal captured:\n$snackBarLiteral',
      );
    });

    testWidgets(
      'should disappear after the declared 10 s duration when constructed '
      'with `persist: false` + Undo action (framework contract smoke)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PopScope(
              canPop: false,
              onPopInvokedWithResult: (_, _) {},
              child: ScaffoldMessenger(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (innerContext) {
                        return ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(innerContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: const Text('Set 1 deleted'),
                                  duration: const Duration(seconds: 10),
                                  persist: false,
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () {},
                                  ),
                                ),
                              );
                          },
                          child: const Text('Delete set'),
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

        await tester.tap(find.text('Delete set'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Set 1 deleted'),
          findsOneWidget,
          reason: 'Pre-condition: snackbar visible after entrance animation.',
        );

        // Pump past the 10 s window in 100 ms steps so the reverse
        // animation actually ticks. 120 × 100 ms = 12 s.
        for (int i = 0; i < 120; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          find.text('Set 1 deleted'),
          findsNothing,
          reason:
              'Framework contract: a SnackBar with `persist: false` + an '
              'action MUST auto-dismiss at `duration`.',
        );
      },
    );
  });
}
