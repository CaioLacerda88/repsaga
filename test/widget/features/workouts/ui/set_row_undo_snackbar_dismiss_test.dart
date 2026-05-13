/// Regression pin: the swipe-to-delete-set undo SnackBar in
/// `_SetRowState.build` (the Dismissible `onDismissed` callback) MUST be
/// constructed via `SnackBarTapOutDismissScope.showCountdownSnackBar`
/// with the agreed 5 s duration, the `setDeleted` l10n key, and NO
/// `showCloseIcon`.
///
/// Companion to `active_workout_add_exercise_snackbar_dismiss_test.dart`.
/// See that file's header for the root-cause narrative (Flutter's
/// `persist = persist ?? action != null` default) and the fix-wave
/// architecture (countdown bar + tap-out dismiss via
/// `SnackBarTapOutDismissScope`). Same bug class, different surface:
/// `_SetRowState` constructs an undo snack with a destructive UNDO action
/// (`restoreSet`), so the same persist-by-default trap and the same
/// tap-out-dismiss requirement apply. Duration tuned 2026-05-13 from the
/// PR-2 C3/Q5 10 s ceiling to 5 s — the countdown bar makes the
/// remaining time legible, so the extra-wide reaction window is
/// unnecessary visual debt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Swipe-to-delete-set undo SnackBar — factory contract', () {
    test('should be constructed via showCountdownSnackBar with a 5 s duration, '
        'the setDeleted l10n key, and NO showCloseIcon — pins the production '
        'wiring', () {
      final source = File(
        'lib/features/workouts/ui/widgets/set_row.dart',
      ).readAsStringSync();

      final factoryIdx = source.indexOf('showCountdownSnackBar(');
      expect(
        factoryIdx,
        isNot(-1),
        reason:
            'Could not find `showCountdownSnackBar(` in set_row.dart. The '
            'factory entrypoint must be the only way `onDismissed` shows '
            'its undo snack — so the persist:false + countdown + tap-out '
            'contract can never be bypassed by reverting to a bare '
            '`showSnackBar` call.',
      );

      final callEnd = source.indexOf(');', factoryIdx);
      expect(callEnd, isNot(-1), reason: 'Factory call has no `);` close.');
      final callExpr = source.substring(factoryIdx, callEnd);

      expect(
        callExpr.contains('setDeleted'),
        isTrue,
        reason:
            'The factory call MUST pass the `setDeleted` l10n key as the '
            'snack message. Captured:\n$callExpr',
      );
      expect(
        callExpr.contains('Duration(seconds: 5)'),
        isTrue,
        reason:
            'The factory call MUST pass a 5 s duration (tuned 2026-05-13 '
            'down from the original PR-2 C3/Q5 10 s ceiling). If this '
            'fails the duration drifted from the UX spec.\n'
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
