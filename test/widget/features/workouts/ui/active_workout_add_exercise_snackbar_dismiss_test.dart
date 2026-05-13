/// Regression pin: the add-exercise undo SnackBar in
/// `_ActiveWorkoutBody._onAddExercise` MUST carry `persist: false`.
///
/// **Why this test exists.** Flutter's `SnackBar` constructor defaults the
/// `persist` field to `true` whenever `action != null`
/// (`packages/flutter/lib/src/material/snack_bar.dart`,
/// `persist = persist ?? action != null`). With `persist: true` the
/// framework's auto-dismiss `Timer` still fires after `duration`, but its
/// callback returns early without calling `hideCurrentSnackBar`
/// (`scaffold.dart`, inside the `_snackBarTimer` callback). The SnackBar
/// then sits on-screen indefinitely until the user taps Undo, swipes it
/// away, or another SnackBar replaces it.
///
/// User-visible symptom (bug report 2026-05-13, Samsung S25 Ultra, Android
/// release APK): after `+ Add exercise` → pick exercise → "{exercise} added"
/// SnackBar appeared but never auto-dismissed. The bug is platform-agnostic;
/// it reproduces on every platform because the `persist == true` default
/// eats the timeout regardless of vsync, ADB, or MediaQuery
/// accessibleNavigation state.
///
/// **Why a source-grep test (not a behavioural pump):** the SnackBar in
/// `_onAddExercise` is constructed inside an `await ExercisePickerSheet.show`
/// chain. `ExercisePickerSheet.show` is a static method wrapping
/// `showModalBottomSheet`, with no DI seam at the widget level. Pumping
/// the full flow (FAB → picker → pick → SnackBar) would require ~200 lines
/// of provider/overlay stubs that all assert nothing about the persist
/// contract — only the picker plumbing. A source-grep that asserts
/// "`persist: false` appears in the SnackBar literal near `addExerciseUndo`"
/// is the most direct way to pin the contract without that overhead.
///
/// The companion behavioural assertion lives further down in this file:
/// it pumps a hand-rolled SnackBar that mirrors the production literal
/// bit-for-bit (4 s duration + Undo action + `persist: false`) and proves
/// the auto-dismiss timer actually does what we want when the opt-out is
/// in place. That second test is a smoke check on the framework contract;
/// the source-grep is the production-wiring guarantee.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Add-exercise undo SnackBar — Phase-23 W1 persist:false contract', () {
    test('should declare `persist: false` in the SnackBar literal that '
        "displays `addExerciseUndo` — pins the production wiring", () {
      final source = File(
        'lib/features/workouts/ui/active_workout_screen.dart',
      ).readAsStringSync();

      // Locate the SnackBar literal that uses `addExerciseUndo`. Match
      // from the `addExerciseUndo` token forward to the closing `)` of
      // the SnackBar constructor (the next `action: SnackBarAction` block
      // closes inside that range, so we anchor on `onPressed: () {` which
      // is the SnackBarAction's callback opener — that gives us a window
      // covering the whole SnackBar(...) arg list above it).
      final idx = source.indexOf('addExerciseUndo');
      expect(
        idx,
        isNot(-1),
        reason:
            'The SnackBar literal that uses `addExerciseUndo` could not '
            'be found in active_workout_screen.dart. The contract test '
            'is wrong, or _onAddExercise was renamed/moved without '
            'updating this pin.',
      );

      // Walk backward from `addExerciseUndo` to find the enclosing
      // SnackBar constructor opening.
      final snackBarStart = source.lastIndexOf('SnackBar(', idx);
      expect(
        snackBarStart,
        isNot(-1),
        reason: 'Expected SnackBar(...) literal before addExerciseUndo.',
      );

      // Walk forward from `addExerciseUndo` to find the matching closing
      // `)` of the SnackBar constructor. The SnackBar literal contains
      // one nested SnackBarAction(...) constructor — we search for the
      // first `,\n      ),` after addExerciseUndo's SnackBarAction
      // closes, but a simpler bound is to capture everything up to the
      // `messenger.showSnackBar(` closing — the SnackBar is the only arg
      // so the close lands at the trailing `);` of the call site.
      final showSnackBarEnd = source.indexOf('\n    );', idx);
      expect(
        showSnackBarEnd,
        isNot(-1),
        reason:
            'Could not find end of messenger.showSnackBar(...) call after '
            'addExerciseUndo. The file shape changed.',
      );

      final snackBarLiteral = source.substring(snackBarStart, showSnackBarEnd);

      expect(
        snackBarLiteral.contains('persist: false'),
        isTrue,
        reason:
            "The SnackBar literal in `_onAddExercise` MUST include "
            "`persist: false`. Without it, Flutter defaults `persist` to "
            "true (because an `action:` is present), and the SnackBar "
            "never auto-dismisses regardless of `duration:`. This is the "
            'bug reported on Android release builds on 2026-05-13.\n\n'
            'SnackBar literal captured:\n$snackBarLiteral',
      );

      // UI/UX 2026-05-13 follow-up — Material's X icon is the canonical
      // explicit-dismiss affordance when the SnackBar's `action:` performs
      // work other than dismiss (UNDO restores the just-added exercise).
      // Without `showCloseIcon: true` the user can only "exit" the
      // snackbar by triggering UNDO (destructive vs intent) or waiting
      // passively for the 4 s auto-dismiss.
      expect(
        snackBarLiteral.contains('showCloseIcon: true'),
        isTrue,
        reason:
            "The SnackBar literal in `_onAddExercise` MUST include "
            "`showCloseIcon: true` so the user has an explicit dismiss "
            "affordance distinct from the UNDO action. If this fails the "
            "close-icon affordance was dropped from the production "
            "wiring.\n\nSnackBar literal captured:\n$snackBarLiteral",
      );
    });

    testWidgets(
      'should disappear after the declared 4 s duration when constructed '
      'with `persist: false` + Undo action (framework contract smoke)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            // PopScope + nested ScaffoldMessenger mirrors the production
            // tree shape so the messenger's context chain matches the
            // route-scoped arrangement.
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
                            // Mirrors `_ActiveWorkoutBody._onAddExercise`
                            // bit-for-bit: hideCurrent + show with a 4 s
                            // duration, persist:false opt-out, and an
                            // Undo action.
                            ScaffoldMessenger.of(innerContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: const Text('Bench Press added'),
                                  duration: const Duration(seconds: 4),
                                  persist: false,
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () {},
                                  ),
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

        // Pump in 100 ms increments past the 4 s duration + reverse
        // animation. A single `pump(Duration(seconds: 6))` would collapse
        // the entire fakeAsync window into one frame, firing the timer
        // but not ticking the reverse animation the timer triggers.
        for (int i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          find.text('Bench Press added'),
          findsNothing,
          reason:
              'Framework contract: a SnackBar with `persist: false` + an '
              'action MUST auto-dismiss at `duration`. If this fails the '
              'Flutter version in use changed the persist semantics or '
              'the test infra is broken.',
        );
      },
    );
  });
}
