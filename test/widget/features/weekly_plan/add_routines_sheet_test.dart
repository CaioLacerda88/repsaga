/// Widget tests for AddRoutinesSheet.
///
/// Covers Fix 1B (PR `fix/active-and-plan-ux`):
///   * "Create new routine" action row at the bottom of the list — pops the
///     sheet with a `createNew()` sentinel so the parent can navigate.
///   * Empty state (`availableRoutines.isEmpty`) is a tappable button that
///     emits the same `createNew()` sentinel — replaces the dead text.
///   * Returning user pre-selects the freshly-created routine via the
///     `preSelectedRoutineIds` constructor param. The user must still
///     confirm via the "Add N routines" button — pre-selection does NOT
///     auto-add (locked by UI/UX critic).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/weekly_plan/ui/add_routines_sheet.dart';

import '../../../helpers/test_material_app.dart';

Routine _routine({String id = 'r-001', String name = 'Push Day'}) {
  return Routine(
    id: id,
    name: name,
    isDefault: false,
    exercises: const [],
    createdAt: DateTime(2026),
  );
}

/// Pumps a launcher screen with a button that opens the sheet via
/// `showModalBottomSheet`, returning the sheet's result for assertions.
Future<AddRoutinesSheetResult?> _pumpAndOpenSheet(
  WidgetTester tester, {
  required List<Routine> available,
  required Set<String> inPlanIds,
  Set<String>? preSelectedRoutineIds,
}) async {
  AddRoutinesSheetResult? capturedResult;

  await tester.pumpWidget(
    TestMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                capturedResult =
                    await showModalBottomSheet<AddRoutinesSheetResult>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => AddRoutinesSheet(
                        availableRoutines: available,
                        inPlanIds: inPlanIds,
                        preSelectedRoutineIds:
                            preSelectedRoutineIds ?? const <String>{},
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

  return capturedResult;
}

void main() {
  group('AddRoutinesSheet — Fix 1B (create-new entrypoint)', () {
    testWidgets(
      'shows "Create new routine" action row at the bottom of the list',
      (tester) async {
        await _pumpAndOpenSheet(
          tester,
          available: [_routine()],
          inPlanIds: const {},
        );

        expect(
          find.text('Create new routine'),
          findsOneWidget,
          reason:
              'The sheet must surface a "Create new routine" affordance — '
              'previously there was no way to reach the routine-creation '
              'flow from inside the picker.',
        );
      },
    );

    testWidgets(
      'tapping "Create new routine" pops the sheet with createNew() sentinel '
      'carrying the empty selection set when nothing is checked',
      (tester) async {
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
                              availableRoutines: [_routine()],
                              inPlanIds: const {},
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

        await tester.tap(find.text('Create new routine'));
        await tester.pumpAndSettle();

        expect(
          result,
          isA<AddRoutinesSheetResultCreateNew>(),
          reason:
              'Tapping the create row must pop the sheet with a discrete '
              'createNew sentinel so the parent can navigate to the create '
              'route and then re-open the sheet on return.',
        );
        // No tile was checked before tapping, so the sentinel must carry
        // an empty selection set. The parent's merge then collapses to
        // just the freshly-created routine's id.
        expect(
          (result as AddRoutinesSheetResultCreateNew).previouslySelectedIds,
          isEmpty,
          reason:
              'No tile was checked before tapping create-new — sentinel '
              'must carry an empty set so the merge on return is just the '
              'new routine.',
        );
      },
    );

    testWidgets(
      'tapping "Create new routine" with checked tiles carries those ids '
      'through the sentinel — guards against multi-routine session regression',
      (tester) async {
        // Regression pin (from UI/UX post-build review): user checks A,
        // then taps "Create new routine". On return, the sheet re-opens
        // with ONLY the newly-created routine pre-selected — A is silently
        // dropped. The fix is to carry A's id through the sentinel so the
        // parent can merge {A} ∪ {new} when re-opening.
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
                                _routine(id: 'r-a', name: 'Routine A'),
                                _routine(id: 'r-b', name: 'Routine B'),
                              ],
                              inPlanIds: const {},
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

        // User checks Routine A.
        await tester.tap(find.text('Routine A'));
        await tester.pumpAndSettle();

        // Then taps "Create new routine". The confirm button can occlude
        // the bottom of the list inside the bottom-sheet's small viewport;
        // ensure the row is visible before tapping so the test exercises
        // the real production tap path rather than failing on layout.
        await tester.ensureVisible(find.text('Create new routine'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create new routine'));
        await tester.pumpAndSettle();

        expect(result, isA<AddRoutinesSheetResultCreateNew>());
        expect(
          (result as AddRoutinesSheetResultCreateNew).previouslySelectedIds,
          equals({'r-a'}),
          reason:
              'Sentinel must carry the user\'s prior selection so the parent '
              'can merge it with the freshly-created routine\'s id when '
              're-opening the sheet. Without this, A is silently unchecked '
              'on return — multi-routine add sessions break.',
        );
      },
    );

    testWidgets('empty state is a tappable button that emits createNew()', (
      tester,
    ) async {
      AddRoutinesSheetResult? result;

      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<AddRoutinesSheetResult>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const AddRoutinesSheet(
                        availableRoutines: [],
                        inPlanIds: <String>{},
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

      // Empty state should expose the create-new affordance instead of
      // the dead "Create more routines to add them here." text.
      final createButton = find.text('Create new routine');
      expect(createButton, findsOneWidget);

      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(
        result,
        isA<AddRoutinesSheetResultCreateNew>(),
        reason:
            'Empty-state create-new button must emit the same sentinel as '
            'the bottom-of-list row so the parent has a single navigation '
            'path to handle.',
      );
      // Empty-state path: there are no available routines to check, so
      // `_selected` is necessarily empty. The sentinel must carry an empty
      // set — the parent's merge then collapses to just the freshly-created
      // routine's id, which is the same UX as the pre-fix behaviour.
      expect(
        (result as AddRoutinesSheetResultCreateNew).previouslySelectedIds,
        isEmpty,
        reason:
            'Empty-state path has no possible selection — sentinel carries '
            'an empty set, parent merge collapses to just the new routine.',
      );
    });

    testWidgets(
      'preSelectedRoutineIds pre-checks the matching tile on first build',
      (tester) async {
        // Returning-user flow: parent passes the freshly-created routine's
        // id; the sheet pre-checks it. The user STILL must confirm via the
        // "ADD N ROUTINES" button — pre-selection does NOT auto-add.
        await _pumpAndOpenSheet(
          tester,
          available: [
            _routine(id: 'r-existing', name: 'Push Day'),
            _routine(id: 'r-new', name: 'Brand New Routine'),
          ],
          inPlanIds: const {},
          preSelectedRoutineIds: const {'r-new'},
        );

        // The "ADD 1 ROUTINE" confirm button reflects the pre-selection.
        expect(find.text('ADD 1 ROUTINE'), findsOneWidget);
        // The pre-selected tile shows the filled check-circle (selected
        // state).
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
      },
    );

    testWidgets(
      'pre-selection does NOT auto-pop the sheet — user must confirm',
      (tester) async {
        // Locked by UI/UX: "Returning user pre-selects the new routine but
        // does NOT auto-add." This pin guards against a future shortcut
        // that auto-pops with the pre-selected list.
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
                              availableRoutines: [_routine(id: 'r-new')],
                              inPlanIds: const {},
                              preSelectedRoutineIds: const {'r-new'},
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

        // Sheet should still be visible — no auto-pop.
        expect(find.byType(AddRoutinesSheet), findsOneWidget);
        expect(result, isNull);
      },
    );
  });
}
