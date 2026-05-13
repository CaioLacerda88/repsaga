/// Regression pin: the routine-removed undo SnackBar in
/// `plan_management_screen.dart` MUST be constructed via
/// `SnackBarTapOutDismissScope.showCountdownSnackBar` with the agreed
/// 3 s duration, the `routineRemoved` l10n key, and NO `showCloseIcon`.
///
/// See
/// `test/widget/features/workouts/ui/active_workout_add_exercise_snackbar_dismiss_test.dart`
/// for the root-cause narrative and the architecture of the fix wave.
/// Plan-management-specific subtlety: the screen wires a
/// `controller.closed.whenComplete` listener to clear
/// `_undoSnackbarActive`. That listener fires for ANY close reason
/// (timeout, tap-out, action, user dismiss). The scope's factory pins
/// `persist: false` so the timeout path is reachable; otherwise the
/// flag would stay stuck at true and permanently block the Saved-
/// snackbar suppression contract.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plan-management routine-removed undo — factory contract', () {
    test('should be constructed via showCountdownSnackBar with a 3 s duration, '
        'the routineRemoved l10n key, and NO showCloseIcon — pins the '
        'production wiring', () {
      final source = File(
        'lib/features/weekly_plan/ui/plan_management_screen.dart',
      ).readAsStringSync();

      final factoryIdx = source.indexOf('showCountdownSnackBar(');
      expect(
        factoryIdx,
        isNot(-1),
        reason:
            'Could not find `showCountdownSnackBar(` in '
            'plan_management_screen.dart. The factory entrypoint must be '
            'the only way `_removeRoutine` shows its undo snack — so the '
            'persist:false + countdown + tap-out contract can never be '
            'bypassed by reverting to a bare `showSnackBar` call.',
      );

      final callEnd = source.indexOf(');', factoryIdx);
      expect(callEnd, isNot(-1), reason: 'Factory call has no `);` close.');
      final callExpr = source.substring(factoryIdx, callEnd);

      expect(
        callExpr.contains('routineRemoved'),
        isTrue,
        reason:
            'The factory call MUST pass the `routineRemoved` l10n key as '
            'the snack message. Captured:\n$callExpr',
      );
      expect(
        callExpr.contains('Duration(seconds: 3)'),
        isTrue,
        reason:
            'The factory call MUST pass a 3 s duration (tuned 2026-05-13 '
            'down from the original 5 s — pairing with the countdown bar '
            'makes the remaining time legible). If this fails the '
            'duration drifted from the UX spec.\n'
            'Captured:\n$callExpr',
      );
      expect(
        callExpr.contains('showCloseIcon'),
        isFalse,
        reason:
            'showCloseIcon was rejected by UI/UX on 2026-05-13 in favour '
            'of countdown-bar + tap-out dismiss. Captured:\n$callExpr',
      );
    });
  });
}
