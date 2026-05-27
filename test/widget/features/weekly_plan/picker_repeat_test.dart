/// Widget tests for the picker-repeat fix (PR 32c).
///
/// Before PR 32c, `WeekPlanScreen._showAddSheet` filtered out routines
/// already in this week's bucket before passing them to
/// `AddRoutinesSheet`. Users with classic splits (Push Day Mon/Wed/Fri)
/// reported the routine "disappearing" from the picker after adding it
/// once — they couldn't re-add it on a second day.
///
/// `BucketRoutine` is keyed on `(routineId, order)` not `routineId`
/// alone, so the data model already supports the same routine on
/// multiple days. The filter was a UX gate, not a data-model
/// constraint. PR 32c removed it.
///
/// This test pins the contract: pumping the sheet with a non-empty
/// list of routines surfaces ALL of them, regardless of any caller-
/// side bucket state. The test does NOT pump WeekPlanScreen — that
/// surface is covered by its own widget tests + the E2E spec; here we
/// pin the sheet's own contract that it renders every routine handed
/// in (no internal filter).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/weekly_plan/ui/add_routines_sheet.dart';

import '../../../helpers/test_material_app.dart';

Routine _routine({required String id, required String name}) => Routine(
  id: id,
  name: name,
  isDefault: false,
  exercises: const <RoutineExercise>[],
  createdAt: DateTime(2026),
);

/// Pumps a launcher screen that opens the [AddRoutinesSheet] via
/// `showModalBottomSheet`. Mirrors the production navigation pattern
/// in `WeekPlanScreen._showAddSheet`.
Future<AddRoutinesSheetResult?> _openSheet(
  WidgetTester tester, {
  required List<Routine> available,
}) async {
  AddRoutinesSheetResult? captured;
  await tester.pumpWidget(
    TestMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showModalBottomSheet<AddRoutinesSheetResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      AddRoutinesSheet(availableRoutines: available),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('AddRoutinesSheet — picker repeat (PR 32c)', () {
    testWidgets(
      'renders every routine handed in — no internal "already in bucket" filter',
      (tester) async {
        // The caller (WeekPlanScreen) hands the full routine list to the
        // sheet. Pre-32c the caller filtered out any routine already in
        // the bucket BEFORE passing in — the sheet itself never knew
        // about the bucket. Post-32c the caller stops filtering. This
        // test pins that the sheet renders whatever it's handed,
        // without re-introducing a filter at the sheet layer.
        await _openSheet(
          tester,
          available: [
            _routine(id: 'r-push', name: 'Push Day'),
            _routine(id: 'r-pull', name: 'Pull Day'),
            _routine(id: 'r-legs', name: 'Leg Day'),
          ],
        );

        expect(
          find.text('Push Day'),
          findsOneWidget,
          reason: 'Push Day must be in the picker list.',
        );
        expect(
          find.text('Pull Day'),
          findsOneWidget,
          reason: 'Pull Day must be in the picker list.',
        );
        expect(
          find.text('Leg Day'),
          findsOneWidget,
          reason: 'Leg Day must be in the picker list.',
        );
      },
    );

    testWidgets(
      'tapping the same routine returns it via the Selected sentinel — '
      'caller is responsible for appending a new BucketRoutine entry',
      (tester) async {
        // The user's scenario: "Push Day" is already in the bucket on
        // Monday. The user re-opens the picker on Wednesday, finds
        // "Push Day" still listed (pre-32c it would have been hidden),
        // taps it, and confirms with the ADD button. The sheet pops
        // with a Selected sentinel carrying the routine — the caller
        // then appends a NEW `BucketRoutine(routineId: 'r-push',
        // order: nextOrder)` to the bucket, distinct from the existing
        // entry on Monday because the order differs.
        //
        // This test pins the sheet's half of the contract: the sheet
        // returns the routine, full stop. The caller's behavior
        // (appending a new bucket entry without de-duping) is covered
        // by `week_plan_screen_test.dart` and the E2E.
        AddRoutinesSheetResult? result;
        await tester.pumpWidget(
          TestMaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result =
                          await showModalBottomSheet<AddRoutinesSheetResult>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => AddRoutinesSheet(
                              availableRoutines: [
                                _routine(id: 'r-push', name: 'Push Day'),
                                _routine(id: 'r-pull', name: 'Pull Day'),
                              ],
                            ),
                          );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Tap "Push Day" — simulates the user choosing it for a second day.
        await tester.tap(find.text('Push Day'));
        await tester.pumpAndSettle();

        // Tap the "ADD 1 ROUTINE" confirm button.
        await tester.tap(find.text('ADD 1 ROUTINE'));
        await tester.pumpAndSettle();

        expect(result, isA<AddRoutinesSheetResultSelected>());
        final selected = result! as AddRoutinesSheetResultSelected;
        expect(
          selected.routines.map((r) => r.id),
          equals(['r-push']),
          reason:
              'Sheet must return the routine the user picked, even if it '
              'is also (per the caller\'s knowledge) already in the bucket. '
              'The caller is responsible for appending a new ordered '
              'entry — the sheet stays single-responsibility.',
        );
      },
    );
  });
}
