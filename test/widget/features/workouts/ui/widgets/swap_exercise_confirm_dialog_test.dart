/// Widget tests for [SwapExerciseConfirmDialog] (PR-3 / Q3).
///
/// Pins the load-bearing UX-critic-approved copy contracts:
///   * Title names the NEW exercise concretely ("Swap to Incline Bench?").
///   * Body names BOTH sides + the exact count of logged sets.
///   * Cancel returns false; Swap returns true.
///
/// The dialog itself has no state — it is a pure projection of its inputs.
/// These tests pin the projection so a future ARB rewrite or placeholder
/// reorder doesn't silently regress to the generic "the new exercise" copy
/// the UI critic explicitly rejected on the PR-1 review.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/swap_exercise_confirm_dialog.dart';

import '../../../../../helpers/test_material_app.dart';

/// Pumps a host widget with a button that opens the dialog. The host
/// stores the picker's `Future<bool?>` so the test can await its
/// resolution after tapping a dialog action. Returns the host state so
/// tests can read `state.lastResult`.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.oldName,
    required this.newName,
    required this.count,
  });

  final String oldName;
  final String newName;
  final int count;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Future<bool?>? lastResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            setState(() {
              lastResult = SwapExerciseConfirmDialog.show(
                context,
                oldExerciseName: widget.oldName,
                newExerciseName: widget.newName,
                completedSetCount: widget.count,
              );
            });
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<_HostState> _openDialog(
  WidgetTester tester, {
  required String oldName,
  required String newName,
  required int count,
}) async {
  final hostKey = GlobalKey<_HostState>();
  await tester.pumpWidget(
    TestMaterialApp(
      theme: AppTheme.dark,
      home: _Host(
        key: hostKey,
        oldName: oldName,
        newName: newName,
        count: count,
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return hostKey.currentState!;
}

void main() {
  group('SwapExerciseConfirmDialog', () {
    testWidgets(
      'title names the new exercise concretely (Q3 — UI critic guidance)',
      (tester) async {
        await _openDialog(
          tester,
          oldName: 'Bench Press',
          newName: 'Incline Bench',
          count: 3,
        );

        // The title must contain the NEW exercise name, never a generic
        // placeholder. UI critic specifically rejected "Swap to the new
        // exercise?" on PR-1 review.
        expect(find.text('Swap to Incline Bench?'), findsOneWidget);

        // Defensive: the dialog must NOT contain the antipattern strings.
        // If the ARB regresses to "the new exercise" / "this exercise",
        // this test catches it.
        expect(find.textContaining('the new exercise'), findsNothing);
        expect(find.textContaining('this exercise'), findsNothing);
      },
    );

    testWidgets(
      'body names BOTH sides plus the count and uses plural correctly (Q3)',
      (tester) async {
        await _openDialog(
          tester,
          oldName: 'Bench Press',
          newName: 'Incline Bench',
          count: 3,
        );

        // The body lives in a Text widget; isolate it by searching for the
        // count substring (intl's pluralLogic substitutes # → 3).
        final bodyText = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .firstWhere(
              (s) => s.contains('logged set'),
              orElse: () => '<no body text found>',
            );
        expect(bodyText, contains('3 logged sets'));
        // Both names + the PR-attribution language must be in the body.
        expect(bodyText, contains('Incline Bench'));
        expect(bodyText, contains('Bench Press'));
        // PR-3 (review reframe) — copy now uses "PR history" (front-loaded
        // risk: "Swapping from X: ... will move to Y's PR history") instead
        // of the former trailing "(not X)" parenthetical. The substring
        // "PR" still pins the load-bearing concept.
        expect(bodyText, contains('PR history'));
      },
    );

    testWidgets('body uses singular form when count is 1 (Q3 plural-rule)', (
      tester,
    ) async {
      await _openDialog(
        tester,
        oldName: 'Bench Press',
        newName: 'Squat',
        count: 1,
      );

      // ICU plural { one{# logged set} other{# logged sets} } — at count=1
      // must render "1 logged set" (singular) not "1 logged sets" (plural).
      // Walk all Text widgets and find the one with the body content; we
      // assert the singular form appears inside it but the plural-only
      // suffix "logged sets" does not.
      final bodyText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere(
            (s) => s.contains('logged set'),
            orElse: () => '<no body text found>',
          );
      expect(
        bodyText,
        contains('1 logged set'),
        reason:
            'Singular branch must render "1 logged set" at count=1. Got: '
            '"$bodyText".',
      );
      // Make sure the plural-only string isn't there. Match ".logged sets."
      // (with the trailing space/newline) so the substring check doesn't
      // false-positive on "1 logged set will...".
      expect(
        bodyText.contains('logged sets'),
        isFalse,
        reason:
            'Plural form leaked into the singular branch. Got: "$bodyText".',
      );
    });

    testWidgets('Cancel button dismisses with false (Q3)', (tester) async {
      final host = await _openDialog(
        tester,
        oldName: 'Bench Press',
        newName: 'Incline Bench',
        count: 3,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await host.lastResult, isFalse);
    });

    testWidgets('Swap button dismisses with true (Q3)', (tester) async {
      final host = await _openDialog(
        tester,
        oldName: 'Bench Press',
        newName: 'Incline Bench',
        count: 3,
      );

      // The action label is "Swap" (en) — distinct from the icon-button
      // tooltip "Swap exercise" which is `swapExercise` ARB key.
      await tester.tap(find.text('Swap'));
      await tester.pumpAndSettle();

      expect(await host.lastResult, isTrue);
    });
  });
}
