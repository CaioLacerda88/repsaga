import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/routines/ui/create_routine_screen.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/ui/widgets/cardio_field.dart';
import 'package:repsaga/shared/widgets/weight_stepper.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

/// Profile stub so the screen's `ref.watch(profileProvider)` (for the cardio
/// distance unit) resolves without Supabase. kg → km distance unit.
class _StubProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  @override
  Future<Profile?> build() async =>
      const Profile(id: 'user-001', weightUnit: 'kg');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Capturing stub for the routine list notifier — records the [exercises] list
/// passed to `updateRoutine` (the edit-mode Save path) so a test can assert the
/// drag-reordered order is what actually persists, not just the on-screen order.
class _CapturingRoutineListNotifier extends AsyncNotifier<List<Routine>>
    implements RoutineListNotifier {
  List<RoutineExercise>? capturedExercises;

  @override
  Future<List<Routine>> build() async => [];

  @override
  Future<void> updateRoutine({
    required String id,
    required String name,
    required List<RoutineExercise> exercises,
    String? notes,
  }) async {
    capturedExercises = exercises;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Exercise _makeExercise({
  String id = 'exercise-001',
  String name = 'Bench Press',
  String muscleGroup = 'chest',
  String equipmentType = 'barbell',
  String slug = 'bench_press',
}) {
  return Exercise.fromJson(
    TestExerciseFactory.create(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      equipmentType: equipmentType,
      slug: slug,
    ),
  );
}

Exercise _makeCardio({
  String id = 'exercise-treadmill',
  String name = 'Treadmill',
}) => _makeExercise(
  id: id,
  name: name,
  muscleGroup: 'cardio',
  equipmentType: 'machine',
  slug: 'treadmill',
);

Exercise _makeBodyweight({
  String id = 'exercise-pullup',
  String name = 'Pull-up',
}) => _makeExercise(
  id: id,
  name: name,
  muscleGroup: 'back',
  equipmentType: 'bodyweight',
  slug: 'pull_up',
);

Widget _buildScreen({Routine? routine}) {
  return ProviderScope(
    overrides: [profileProvider.overrideWith(() => _StubProfileNotifier())],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: CreateRoutineScreen(routine: routine),
    ),
  );
}

/// A single-exercise editing routine — the on-screen card reflects the
/// exercise's type (cardio / bodyweight / strength).
Routine _routineWith(Exercise exercise, {List<RoutineSetConfig>? setConfigs}) {
  return Routine(
    id: 'routine-001',
    name: 'My Routine',
    isDefault: false,
    exercises: [
      RoutineExercise(
        exerciseId: exercise.id,
        setConfigs: setConfigs ?? const [RoutineSetConfig(restSeconds: 90)],
        exercise: exercise,
      ),
    ],
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}

void main() {
  group('CreateRoutineScreen', () {
    // The bottom-anchored FilledButton is the SOLE Save affordance (the
    // redundant AppBar Save was dropped in the usability pass). These pin its
    // enabled/disabled gating.
    Finder bottomSaveButton() => find.byType(FilledButton);

    testWidgets('Save CTA disabled when name is empty and no exercises', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(bottomSaveButton());
      expect(button.onPressed, isNull);
    });

    testWidgets('Save CTA still disabled when name entered but no exercises', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Enter a name (first TextField — the notes field is second)
      await tester.enterText(find.byType(TextField).first, 'My Routine');
      await tester.pump();

      final button = tester.widget<FilledButton>(bottomSaveButton());
      expect(button.onPressed, isNull);
    });

    testWidgets('shows Add Exercise button', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Add Exercise'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows Create Routine title for new routine', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Create Routine'), findsOneWidget);
    });

    testWidgets('shows Edit Routine title when editing existing routine', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      expect(find.text('Edit Routine'), findsOneWidget);
    });

    testWidgets('pre-fills name and exercises when editing', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Name should be pre-filled (first TextField — notes field is second)
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, 'Push Day');

      // Exercise name should appear
      expect(find.text('Bench Press'), findsOneWidget);
    });

    testWidgets('set count stepper shows correct value for editing routine', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Set count should be 4 (number of setConfigs)
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Sets'), findsOneWidget);
    });

    testWidgets('set count stepper increments on + tap', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Initially 3 sets (the Sets-row value); the Reps row defaults to 8.
      final setsRow = find.ancestor(
        of: find.text('Sets'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: setsRow.first, matching: find.text('3')),
        findsOneWidget,
      );

      // Tap the + inside the Sets row (scoped — the Reps row has its own +).
      final setsAdd = find.descendant(
        of: setsRow.first,
        matching: find.widgetWithIcon(IconButton, Icons.add),
      );
      await tester.tap(setsAdd);
      await tester.pump();

      expect(
        find.descendant(of: setsRow.first, matching: find.text('4')),
        findsOneWidget,
      );
    });

    testWidgets('set count stepper decrements on - tap', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      final setsRow = find.ancestor(
        of: find.text('Sets'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: setsRow.first, matching: find.text('3')),
        findsOneWidget,
      );

      // Tap the - inside the Sets row (scoped — Reps + WeightStepper also use
      // Icons.remove).
      final setsRemove = find.descendant(
        of: setsRow.first,
        matching: find.widgetWithIcon(IconButton, Icons.remove),
      );
      await tester.tap(setsRemove);
      await tester.pump();

      expect(
        find.descendant(of: setsRow.first, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('rest time chips are visible with default 1m 30s selected', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Rest time chips: 30s, 1m, 1m 30s, 2m, 3m, 4m
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('1m'), findsOneWidget);
      expect(find.text('1m 30s'), findsOneWidget);
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('3m'), findsOneWidget);
      expect(find.text('4m'), findsOneWidget);
    });

    testWidgets('tapping a rest chip changes selection', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // The TARGET block makes the card taller, so the 2m chip can sit below
      // the fold — scroll it into view before tapping.
      await tester.ensureVisible(find.text('2m'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2m'));
      await tester.pump();

      // The 2m chip should now be selected (ChoiceChip)
      final chip2m = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('2m'), matching: find.byType(ChoiceChip)),
      );
      expect(chip2m.selected, isTrue);
    });

    testWidgets('shows the notes field on the create screen', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Placeholder with the load-bearing "(optional)" suffix.
      expect(
        find.text('Program intent, form cues, deload schedule… (optional)'),
        findsOneWidget,
      );
      // Two TextFields: name + notes.
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('pre-fills notes when editing a routine that has notes', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        notes: 'Brace before every rep.',
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      expect(find.text('Brace before every rep.'), findsOneWidget);
    });

    testWidgets(
      'notes are optional — Save stays enabled with name + exercise and '
      'empty notes',
      (tester) async {
        final routine = Routine(
          id: 'routine-001',
          name: 'Push Day',
          isDefault: false,
          exercises: [
            RoutineExercise(
              exerciseId: 'ex-1',
              setConfigs: [const RoutineSetConfig(restSeconds: 90)],
              exercise: _makeExercise(),
            ),
          ],
          createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        );

        await tester.pumpWidget(_buildScreen(routine: routine));
        await tester.pumpAndSettle();

        // Notes left blank — the bottom Save CTA must still be enabled.
        final button = tester.widget<FilledButton>(bottomSaveButton());
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('notes counter is hidden at low length', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Short note');
      await tester.pump();

      // No "/ 600" counter while well below the 500-char threshold.
      expect(find.textContaining('/ 600'), findsNothing);
    });

    testWidgets('notes counter appears near the cap', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // 520 chars — past the 500-char threshold, under the 600 cap.
      await tester.enterText(find.byType(TextField).last, 'x' * 520);
      await tester.pump();

      expect(find.text('520 / 600'), findsOneWidget);
    });

    testWidgets('remove button removes exercise card', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
          RoutineExercise(
            exerciseId: 'ex-2',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(
              id: 'exercise-002',
              name: 'OHP',
              muscleGroup: 'shoulders',
            ),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // OHP is the SECOND tall card — built in the cacheExtent region but
      // scrolled below the 600dp test viewport, so it's offstage. The generous
      // cacheExtent keeps it in the tree (the E2E/a11y reach guarantee), so we
      // locate it with skipOffstage:false. The default-finder failure here was
      // the offstage-not-removed distinction, not a regression.
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('OHP', skipOffstage: false), findsOneWidget);

      // Tap the first close button to remove Bench Press (card 0 is onstage).
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('Bench Press'), findsNothing);
      // OHP is now the sole card → onstage.
      expect(find.text('OHP'), findsOneWidget);
    });

    group('type-aware exercise cards', () {
      testWidgets(
        'a cardio exercise shows the target slots and NO set stepper / rest '
        'chips',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeCardio(),
                setConfigs: const [RoutineSetConfig()],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The two cardio target slots are present (their field labels).
          expect(find.text('Target time'), findsOneWidget);
          expect(find.text('Target distance'), findsOneWidget);
          // Both empty → the invite-not-nag ghost on each slot.
          expect(find.text('+ add'), findsNWidgets(2));

          // The strength affordances must NOT render for cardio.
          expect(
            find.text('Sets'),
            findsNothing,
            reason: 'cardio has no set count',
          );
          expect(
            find.text('Rest'),
            findsNothing,
            reason: 'cardio has no inter-set rest',
          );
          // A rest chip label that the strength card would render.
          expect(find.text('1m 30s'), findsNothing);
        },
      );

      testWidgets(
        'editing a cardio routine with a populated target rehydrates the '
        'formatted values and hides the + add ghost on filled slots',
        (tester) async {
          // initState rehydration path: a SAVED cardio routine whose single
          // config carries a 28:00 / 5 km target must render those values, not
          // the empty "+ add" invite. Pins the editing-a-saved-cardio-routine
          // contract — the empty-target case above doesn't exercise rehydrate.
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeCardio(),
                setConfigs: const [
                  RoutineSetConfig(
                    targetDurationSeconds: 1680, // 28:00
                    targetDistanceM: 5000, // 5 km (kg profile → km)
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Both target slots still exist (their field labels).
          expect(find.text('Target time'), findsOneWidget);
          expect(find.text('Target distance'), findsOneWidget);

          // The persisted values render in place of the ghost.
          expect(find.text('28:00'), findsOneWidget);
          // Distance renders as a Text.rich whose plain text is "5 km"
          // (kg → km; 5000m → 5.0 km, integer-formatted to "5" + " km").
          expect(find.text('5 km'), findsOneWidget);

          // No "+ add" ghost on EITHER slot — both are filled.
          expect(
            find.text('+ add'),
            findsNothing,
            reason: 'both target slots carry a value, so no invite ghost shows',
          );

          // Still cardio: no strength affordances leaked in.
          expect(find.text('Sets'), findsNothing);
          expect(find.text('Rest'), findsNothing);
        },
      );

      testWidgets(
        'a bodyweight exercise shows BOTH the BODYWEIGHT tag AND its muscle '
        'pill, reps as the hero, and weight behind the + Add weight reveal',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeBodyweight(), // muscleGroup: back
                setConfigs: const [
                  RoutineSetConfig(restSeconds: 90),
                  RoutineSetConfig(restSeconds: 90),
                  RoutineSetConfig(restSeconds: 90),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // TWO pills: neutral BODYWEIGHT tag AND the muscle identity pill —
          // a pull-up is still a Back exercise (info preserved, no glyph).
          expect(find.text('BODYWEIGHT'), findsOneWidget);
          expect(find.text('BACK'), findsOneWidget);

          // Reps is the hero target; the Weight stepper is hidden behind the
          // "+ Add weight" reveal until the user opts in (lean by default).
          expect(find.text('Reps'), findsOneWidget);
          expect(find.text('+ Add weight'), findsOneWidget);
          expect(
            find.text('Added weight'),
            findsNothing,
            reason: 'the added-weight stepper is hidden until + Add weight tap',
          );

          // The strength layout is otherwise UNCHANGED for bodyweight.
          expect(find.text('Sets'), findsOneWidget);
          expect(find.text('Rest'), findsOneWidget);
          expect(find.text('1m 30s'), findsOneWidget); // 90s chip selected

          // No cardio target slots.
          expect(find.text('Target time'), findsNothing);
          expect(find.text('Target distance'), findsNothing);
        },
      );

      testWidgets(
        'a strength exercise shows the muscle chip + Weight/Reps TARGET block '
        '+ set stepper + rest chips (no BODYWEIGHT tag, no cardio slots)',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeExercise(name: 'Bench Press', muscleGroup: 'chest'),
                setConfigs: const [
                  RoutineSetConfig(restSeconds: 90),
                  RoutineSetConfig(restSeconds: 90),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Bench Press'), findsOneWidget);
          // Unified pill grammar (Phase 38h 2b): the muscle group is uppercased
          // via AppTextStyles.label, matching the cardio/bodyweight pills.
          expect(find.text('CHEST'), findsOneWidget); // muscle-group pill
          // TARGET block — Weight + Reps shown inline for a strength exercise.
          expect(find.text('Weight'), findsOneWidget);
          expect(find.text('Reps'), findsOneWidget);
          expect(find.text('Sets'), findsOneWidget);
          expect(find.text('Rest'), findsOneWidget);

          expect(find.text('BODYWEIGHT'), findsNothing);
          // Bodyweight-only "+ Add weight" reveal is absent on strength.
          expect(find.text('+ Add weight'), findsNothing);
          // Cardio-only target slots are absent on strength.
          expect(find.text('Target time'), findsNothing);
          expect(find.text('Target distance'), findsNothing);
        },
      );
    });

    // Keyboard behavior contract. Tapping the name / notes field must OVERLAY
    // the keyboard over the form — the screen behind stays untouched — instead
    // of resizing the body and reflowing the list (which shoved the exercises
    // under a rising empty band, AND left the cards unpainted because the
    // scroll view mis-repaints on resize). `resizeToAvoidBottomInset: false` is
    // the single fix: no resize → no reflow → no mis-repaint. The on-device
    // rendering itself was verified manually because a widget test cannot raise
    // a real soft keyboard (see feedback_visual_verification_physical_device).
    //
    // The body is a single CustomScrollView (the ONE scroll authority) hosting a
    // SliverReorderableList for the cards. That structure lets the reorder
    // sliver's auto-scroll resolve to the page itself (drag-to-edge scrolls), and
    // a generous cacheExtent keeps every card built eagerly so all cards are in
    // the widget tree / AOM for E2E + screen readers even when scrolled off. A
    // lazy ListView with the default cacheExtent dropped off-viewport cards from
    // the DOM and broke the routine-create E2E.
    group('keyboard overlays the form (does not reflow)', () {
      Routine routineWithExercises() => Routine(
        id: 'routine-kbd',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(name: 'Bench Press'),
          ),
          RoutineExercise(
            exerciseId: 'ex-2',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(
              id: 'exercise-002',
              name: 'OHP',
              muscleGroup: 'shoulders',
            ),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      testWidgets('Scaffold does not resize for the keyboard', (tester) async {
        await tester.pumpWidget(_buildScreen(routine: routineWithExercises()));
        await tester.pumpAndSettle();

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.resizeToAvoidBottomInset,
          isFalse,
          reason:
              'the keyboard must overlay the form (screen behind untouched), '
              'not push the body up and reflow the exercise list',
        );
      });

      testWidgets('form body is the single CustomScrollView scroll authority', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen(routine: routineWithExercises()));
        await tester.pumpAndSettle();

        // The body is the SINGLE scroll authority — a CustomScrollView. This is
        // what lets the SliverReorderableList's drag auto-scroll resolve to the
        // page itself (Scrollable.of(context) finds THIS scroll view), so
        // dragging a card to the viewport edge scrolls the page. The old nested
        // ReorderableListView(NeverScrollableScrollPhysics) broke that.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.body, isA<CustomScrollView>());

        // Both seeded exercise cards are in the TREE, not just the on-screen
        // one — the generous cacheExtent keeps every card built/in the AOM even
        // when the second tall card is scrolled into the cache region (offstage
        // in the 600dp test viewport, but present for E2E + screen readers).
        // skipOffstage:false pins exactly that reach guarantee.
        expect(find.text('Bench Press'), findsOneWidget);
        expect(find.text('OHP', skipOffstage: false), findsOneWidget);
      });

      testWidgets('a generous cacheExtent keeps off-viewport cards in the tree', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen(routine: routineWithExercises()));
        await tester.pumpAndSettle();

        // Pin the cacheExtent that preserves eager-render reach (cluster:
        // listview-lazy-build-breaks-e2e). A SliverReorderableList is lazy by
        // default; the generous cacheExtent keeps realistic routines (≤~12 tall
        // cards) fully built so every card stays reachable for E2E + a11y.
        final scrollView = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        expect(scrollView.cacheExtent, greaterThanOrEqualTo(3000));
      });
    });

    group('Phase 38h — unified identity pills (2b)', () {
      Color pillLabelColor(WidgetTester tester, String text) {
        final widget = tester.widget<Text>(find.text(text));
        return widget.style!.color!;
      }

      testWidgets('strength pill renders the muscle group in its BodyPartHues '
          'identity color (chest → pink)', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            routine: _routineWith(
              _makeExercise(name: 'Bench Press', muscleGroup: 'chest'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('CHEST'), findsOneWidget);
        expect(
          pillLabelColor(tester, 'CHEST'),
          BodyPartHues.hueFor(BodyPart.chest),
          reason: 'strength pill label uses the muscle identity hue',
        );
      });

      testWidgets('bodyweight pill is NEUTRAL (textDim label, no identity '
          'color — brand-vs-identity rule)', (tester) async {
        await tester.pumpWidget(
          _buildScreen(routine: _routineWith(_makeBodyweight())),
        );
        await tester.pumpAndSettle();

        expect(find.text('BODYWEIGHT'), findsOneWidget);
        expect(pillLabelColor(tester, 'BODYWEIGHT'), AppColors.textDim);
      });

      testWidgets('cardio pill renders the resolved activity label (Running · '
          'Cardio), never a raw slug', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            routine: _routineWith(
              _makeCardio(),
              setConfigs: const [RoutineSetConfig()],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // treadmill → "RUNNING · CARDIO" (en eyebrow), teal-dim label.
        expect(find.text('RUNNING · CARDIO'), findsOneWidget);
        expect(find.textContaining('treadmill'), findsNothing);
        expect(
          pillLabelColor(tester, 'RUNNING · CARDIO'),
          AppColors.bodyPartCardio.withValues(alpha: 0.72),
        );
      });
    });

    group('Phase 38h — builder cardio slot density (2a)', () {
      testWidgets('the builder opts into the LARGE CardioField + shows the '
          'edit glyph on a FILLED slot', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            routine: _routineWith(
              _makeCardio(),
              setConfigs: const [
                RoutineSetConfig(targetDurationSeconds: 1680), // 28:00 filled
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final fields = tester.widgetList<CardioField>(find.byType(CardioField));
        expect(fields, hasLength(2));
        for (final f in fields) {
          expect(
            f.size,
            CardioFieldSize.large,
            reason: 'the routine builder uses the taller hero slot',
          );
        }
        // The filled duration slot carries the pencil; the empty distance
        // slot keeps the ghost (no pencil).
        expect(find.byIcon(Icons.edit), findsOneWidget);
        expect(find.text('+ add'), findsOneWidget);
      });
    });

    // Zero target = no target. A `0:00` time / `0` distance entered in the
    // builder's target dialog must clear the slot to null (the `+ add` ghost),
    // NOT persist a literal 0. The shared `CardioFormat` parsers still return 0
    // (that layer is correct for the active logging card) — the builder folds
    // the zero into null at the `onTap` boundary. Persistence is asserted via
    // the rehydrate path: a slot cleared to null shows the ghost, so a saved
    // null reopens as the ghost (matching the empty-target case exactly).
    group('zero cardio target is treated as no target (null)', () {
      Future<void> enterDurationDialog(WidgetTester tester, String text) async {
        // The filled duration slot is tappable (edit affordance). Tap it to
        // open the duration dialog, type, confirm.
        await tester.tap(find.text('28:00'));
        await tester.pumpAndSettle();
        expect(find.text('Enter duration'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, text);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      testWidgets(
        'entering 0:00 on a filled time slot reverts it to the + add ghost',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeCardio(),
                setConfigs: const [
                  RoutineSetConfig(targetDurationSeconds: 1680), // 28:00
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Precondition: the value is filled, no ghost on the time slot.
          expect(find.text('28:00'), findsOneWidget);

          await enterDurationDialog(tester, '0:00');

          // The slot reverts to the invite ghost — zero is NOT stored as 0:00.
          expect(find.text('28:00'), findsNothing);
          // Both slots now empty (time cleared, distance never set) → two ghosts.
          expect(find.text('+ add'), findsNWidgets(2));
          // The edit pencil only shows on a FILLED slot; with both empty there
          // is none — confirms the cleared slot is genuinely treated as empty.
          expect(find.byIcon(Icons.edit), findsNothing);
        },
      );

      testWidgets(
        'entering bare 0 on a filled time slot also reverts to the ghost',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeCardio(),
                setConfigs: const [
                  RoutineSetConfig(targetDurationSeconds: 1680),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          await enterDurationDialog(tester, '0');

          expect(find.text('28:00'), findsNothing);
          expect(find.text('+ add'), findsNWidgets(2));
        },
      );

      testWidgets(
        'a real non-zero value (28:45) still persists — zero-guard does not '
        'eat valid targets',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeCardio(),
                setConfigs: const [
                  RoutineSetConfig(targetDurationSeconds: 1680),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          await enterDurationDialog(tester, '28:45');

          // 28:45 is a real target → it renders, no ghost on the time slot.
          expect(find.text('28:45'), findsOneWidget);
          expect(find.text('28:00'), findsNothing);
          // Only the distance slot (never set) shows the ghost.
          expect(find.text('+ add'), findsOneWidget);
          // The filled time slot keeps its edit pencil.
          expect(find.byIcon(Icons.edit), findsOneWidget);
        },
      );

      testWidgets(
        'entering 0 on a filled distance slot reverts it to the + add ghost',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeCardio(),
                setConfigs: const [
                  RoutineSetConfig(targetDistanceM: 5000), // 5 km
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Precondition: 5 km filled.
          expect(find.text('5 km'), findsOneWidget);

          // Open the distance dialog by tapping the filled distance value.
          await tester.tap(find.text('5 km'));
          await tester.pumpAndSettle();
          expect(find.text('Enter distance'), findsOneWidget);
          await tester.enterText(find.byType(TextField).last, '0');
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();

          // Cleared to the ghost — zero distance is no target, not 0 m.
          expect(find.text('5 km'), findsNothing);
          expect(find.text('+ add'), findsNWidgets(2));
          expect(find.byIcon(Icons.edit), findsNothing);
        },
      );
    });

    group('Phase 38h — section eyebrows + name counter (2c)', () {
      testWidgets(
        'ROUTINE and NOTES section eyebrows render above the fields',
        (tester) async {
          await tester.pumpWidget(_buildScreen());
          await tester.pumpAndSettle();

          expect(find.text('ROUTINE'), findsOneWidget);
          expect(find.text('NOTES'), findsOneWidget);
        },
      );

      testWidgets('name counter is hidden at low length', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Push Day');
        await tester.pump();
        expect(find.textContaining('/ 80'), findsNothing);
      });

      testWidgets('name counter appears near the 80-char cap', (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'x' * 75);
        await tester.pump();
        expect(find.text('75 / 80'), findsOneWidget);
      });
    });

    group('Phase 38h — empty state (3d)', () {
      testWidgets('shows the RPG-voiced beat when there are no exercises', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        expect(
          find.text('No exercises yet — add your first to forge this routine.'),
          findsOneWidget,
        );
      });

      testWidgets('the empty beat disappears once an exercise exists', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildScreen(routine: _routineWith(_makeExercise())),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('No exercises yet — add your first to forge this routine.'),
          findsNothing,
        );
      });
    });

    group('Phase 38h — bottom Save CTA (2e)', () {
      testWidgets('the bottom Save CTA is present and disabled when invalid', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        expect(find.text('Save routine'), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save routine'),
        );
        expect(
          button.onPressed,
          isNull,
          reason: 'empty name + no exercises → disabled, mirroring AppBar Save',
        );
      });

      testWidgets('the bottom Save CTA enables with a name + an exercise', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildScreen(routine: _routineWith(_makeExercise())),
        );
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save routine'),
        );
        expect(button.onPressed, isNotNull);
      });
    });

    group('Phase 38h — remove × hit-box (3c)', () {
      testWidgets('the remove × rendered hit-box is at least 48×48', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildScreen(routine: _routineWith(_makeExercise())),
        );
        await tester.pumpAndSettle();

        final size = tester.getSize(
          find.ancestor(
            of: find.byIcon(Icons.close),
            matching: find.byType(IconButton),
          ),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      });
    });

    group('per-exercise target weight + reps', () {
      testWidgets(
        'rehydrates the saved Weight + Reps target onto the steppers',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeExercise(name: 'Bench Press', muscleGroup: 'chest'),
                setConfigs: const [
                  RoutineSetConfig(
                    restSeconds: 90,
                    targetReps: 5,
                    targetWeight: 60,
                  ),
                  RoutineSetConfig(
                    restSeconds: 90,
                    targetReps: 5,
                    targetWeight: 60,
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Reps stepper shows the rehydrated 5 (NOT the fresh-add default 8).
          final repsRow = find.ancestor(
            of: find.text('Reps'),
            matching: find.byType(Row),
          );
          expect(
            find.descendant(of: repsRow.first, matching: find.text('5')),
            findsOneWidget,
          );

          // The WeightStepper shows the rehydrated 60.
          final weightStepper = tester.widget<WeightStepper>(
            find.byType(WeightStepper),
          );
          expect(weightStepper.value, 60);
        },
      );

      testWidgets('tapping the Reps + updates the stepper value', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildScreen(
            routine: _routineWith(
              _makeExercise(),
              setConfigs: const [
                RoutineSetConfig(restSeconds: 90, targetReps: 8),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final repsRow = find.ancestor(
          of: find.text('Reps'),
          matching: find.byType(Row),
        );
        final repsAdd = find.descendant(
          of: repsRow.first,
          matching: find.widgetWithIcon(IconButton, Icons.add),
        );
        await tester.tap(repsAdd);
        await tester.pump();

        expect(
          find.descendant(of: repsRow.first, matching: find.text('9')),
          findsOneWidget,
        );
      });

      testWidgets(
        'bodyweight: the + Add weight reveal expands the Added weight stepper',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: _routineWith(_makeBodyweight())),
          );
          await tester.pumpAndSettle();

          // Hidden by default.
          expect(find.text('Added weight'), findsNothing);
          expect(find.byType(WeightStepper), findsNothing);

          await tester.tap(find.text('+ Add weight'));
          await tester.pumpAndSettle();

          // Revealed: the Added weight label + the stepper appear, CTA gone.
          expect(find.text('Added weight'), findsOneWidget);
          expect(find.byType(WeightStepper), findsOneWidget);
          expect(find.text('+ Add weight'), findsNothing);
        },
      );

      testWidgets(
        'bodyweight: an existing added-weight target auto-reveals the stepper',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeBodyweight(),
                setConfigs: const [
                  RoutineSetConfig(restSeconds: 90, targetWeight: 20),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // No reveal CTA — the stepper is shown directly with the value.
          expect(find.text('+ Add weight'), findsNothing);
          expect(find.text('Added weight'), findsOneWidget);
          final stepper = tester.widget<WeightStepper>(
            find.byType(WeightStepper),
          );
          expect(stepper.value, 20);
        },
      );
    });

    group('reorder mode (collapse + drag)', () {
      Routine threeExerciseRoutine() => Routine(
        id: 'routine-reorder',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-a',
            setConfigs: const [RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(id: 'ex-a', name: 'Alpha'),
          ),
          RoutineExercise(
            exerciseId: 'ex-b',
            setConfigs: const [RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(id: 'ex-b', name: 'Bravo'),
          ),
          RoutineExercise(
            exerciseId: 'ex-c',
            setConfigs: const [RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(id: 'ex-c', name: 'Charlie'),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      Future<void> enterReorderMode(WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.reorder));
        await tester.pumpAndSettle();
      }

      testWidgets('the AppBar reorder toggle is PRESENT with >1 exercise', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen(routine: threeExerciseRoutine()));
        await tester.pumpAndSettle();

        // The hamburger (Icons.reorder) enters reorder mode; Icons.done exits.
        // At rest (normal view) only the enter glyph shows.
        expect(find.byIcon(Icons.reorder), findsOneWidget);
        expect(find.byIcon(Icons.done), findsNothing);
      });

      testWidgets(
        'the AppBar reorder toggle is ABSENT with a single exercise',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: _routineWith(_makeExercise())),
          );
          await tester.pumpAndSettle();

          // Nothing to reorder with one card → the toggle is gated off.
          expect(find.byIcon(Icons.reorder), findsNothing);
          // The remove × is still present, even at one exercise.
          expect(find.byIcon(Icons.close), findsOneWidget);
        },
      );

      testWidgets(
        'the cards live in a SliverReorderableList inside the CustomScrollView',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: threeExerciseRoutine()),
          );
          await tester.pumpAndSettle();

          // Pins the scroll-authority structure: the cards are a sliver inside
          // the page's single CustomScrollView (NOT a nested
          // ReorderableListView with NeverScrollableScrollPhysics). This is the
          // structure that lets drag auto-scroll resolve to the page. A widget
          // test can't assert auto-scroll itself (needs a real viewport drag),
          // so we pin the structure that makes it work.
          expect(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(SliverReorderableList),
            ),
            findsOneWidget,
          );
          // The old nested high-level list must be gone.
          expect(find.byType(ReorderableListView), findsNothing);
        },
      );

      testWidgets(
        'normal mode: cards are FULL (Sets/Rest visible) and NOT draggable',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: threeExerciseRoutine()),
          );
          await tester.pumpAndSettle();

          // Full body renders for every card (Sets/Rest never collapsed in
          // normal view). Cards 2 + 3 sit in the cacheExtent region (offstage
          // in the 600dp viewport) but are fully built — skipOffstage:false
          // counts all 3.
          expect(find.text('Sets', skipOffstage: false), findsNWidgets(3));
          expect(find.text('Rest', skipOffstage: false), findsNWidgets(3));

          // No drag affordance and no per-card drag listener in normal mode.
          expect(
            find.byIcon(Icons.drag_handle, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.byType(ReorderableDragStartListener, skipOffstage: false),
            findsNothing,
          );
        },
      );

      testWidgets(
        'entering reorder mode COLLAPSES the cards: Sets/Rest hidden, title + '
        'pill remain; done restores them',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: threeExerciseRoutine()),
          );
          await tester.pumpAndSettle();

          // Precondition — full cards.
          expect(find.text('Sets', skipOffstage: false), findsNWidgets(3));

          await enterReorderMode(tester);

          // Collapsed: the Sets stepper + Rest chips + remove × are gone.
          expect(find.text('Sets', skipOffstage: false), findsNothing);
          expect(find.text('Rest', skipOffstage: false), findsNothing);
          expect(find.byIcon(Icons.close, skipOffstage: false), findsNothing);

          // Only the header survives — title + identity pill per card.
          expect(find.text('Alpha', skipOffstage: false), findsOneWidget);
          expect(find.text('CHEST', skipOffstage: false), findsNWidgets(3));

          // A drag affordance glyph per collapsed card, and the whole card is
          // wrapped in a drag listener.
          expect(
            find.byIcon(Icons.drag_handle, skipOffstage: false),
            findsNWidgets(3),
          );
          expect(
            find.byType(ReorderableDragStartListener, skipOffstage: false),
            findsNWidgets(3),
          );

          // The toggle now offers EXIT (Icons.done).
          expect(find.byIcon(Icons.done), findsOneWidget);
          expect(find.byIcon(Icons.reorder), findsNothing);

          // Exiting restores the full cards.
          await tester.tap(find.byIcon(Icons.done));
          await tester.pumpAndSettle();

          expect(find.text('Sets', skipOffstage: false), findsNWidgets(3));
          expect(find.text('Rest', skipOffstage: false), findsNWidgets(3));
          expect(
            find.byIcon(Icons.drag_handle, skipOffstage: false),
            findsNothing,
          );
        },
      );

      testWidgets(
        'the collapsed drag affordance carries the Drag to reorder semantics '
        'label',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: threeExerciseRoutine()),
          );
          await tester.pumpAndSettle();

          await enterReorderMode(tester);

          // skipOffstage:false — cards 2 + 3 are built in the cacheExtent
          // region (offstage in the 600dp viewport) but their semantics nodes
          // are present, which is exactly the screen-reader reach guarantee.
          expect(
            find.bySemanticsLabel('Drag to reorder', skipOffstage: false),
            findsNWidgets(3),
            reason: 'each collapsed card carries the drag-reorder label',
          );
        },
      );

      testWidgets(
        'reordering via onReorder moves an exercise and persists the new order',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(routine: threeExerciseRoutine()),
          );
          await tester.pumpAndSettle();

          await enterReorderMode(tester);

          // Initial top-to-bottom order: Alpha, Bravo, Charlie. The lower cards
          // are built in the cacheExtent region but offstage in the 600dp test
          // viewport — skipOffstage:false still resolves their layout geometry
          // (offstage cache children ARE laid out, just not painted), so the
          // top-to-bottom order assertions hold.
          double y(String name) =>
              tester.getTopLeft(find.text(name, skipOffstage: false)).dy;
          expect(y('Alpha') < y('Bravo'), isTrue);
          expect(y('Bravo') < y('Charlie'), isTrue);

          // Drive the SliverReorderableList's onReorder directly: move index 0
          // (Alpha) to the end. The reorder list passes a newIndex that is one
          // PAST the target when moving down, so 3 == "after Charlie".
          final reorderable = tester.widget<SliverReorderableList>(
            find.byType(SliverReorderableList),
          );
          reorderable.onReorder(0, 3);
          await tester.pumpAndSettle();

          // New order: Bravo, Charlie, Alpha — Alpha is now last.
          expect(y('Bravo') < y('Charlie'), isTrue);
          expect(y('Charlie') < y('Alpha'), isTrue);
        },
      );

      testWidgets('the drag-reordered order is what persists through Save', (
        tester,
      ) async {
        final notifier = _CapturingRoutineListNotifier();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileProvider.overrideWith(() => _StubProfileNotifier()),
              routineListProvider.overrideWith(() => notifier),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: CreateRoutineScreen(routine: threeExerciseRoutine()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.reorder));
        await tester.pumpAndSettle();

        // Move index 0 (Alpha) past the end → order becomes B, C, A.
        tester
            .widget<SliverReorderableList>(find.byType(SliverReorderableList))
            .onReorder(0, 3);
        await tester.pumpAndSettle();

        // Tap the bottom Save CTA (edit mode → updateRoutine).
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // The persisted exercise order reflects the drag, NOT the original.
        expect(
          notifier.capturedExercises?.map((e) => e.exerciseId).toList(),
          ['ex-b', 'ex-c', 'ex-a'],
          reason: 'reorder must persist to updateRoutine in the new order',
        );
      });
    });

    group('undo on remove', () {
      Routine twoExerciseRoutine() => Routine(
        id: 'routine-undo',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: const [RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(id: 'ex-1', name: 'Bench Press'),
          ),
          RoutineExercise(
            exerciseId: 'ex-2',
            setConfigs: const [RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(id: 'ex-2', name: 'OHP'),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      testWidgets(
        'removing shows a "removed" SnackBar; Undo restores the exercise '
        'at its original index',
        (tester) async {
          await tester.pumpWidget(_buildScreen(routine: twoExerciseRoutine()));
          await tester.pumpAndSettle();

          // Remove the FIRST card (Bench Press).
          await tester.tap(find.byIcon(Icons.close).first);
          await tester.pump(); // process the removal setState
          await tester.pump(
            const Duration(milliseconds: 300),
          ); // snack slide-in

          expect(find.text('Bench Press'), findsNothing);
          expect(find.text('Bench Press removed'), findsOneWidget);
          expect(find.text('Undo'), findsOneWidget);

          // Tap Undo — Bench Press returns ABOVE OHP (original index 0).
          await tester.tap(find.text('Undo'));
          await tester.pump(); // process the restore setState

          expect(find.text('Bench Press'), findsOneWidget);
          final benchY = tester.getTopLeft(find.text('Bench Press')).dy;
          // After undo OHP is card 1 again — built but offstage below the 600dp
          // viewport. getTopLeft still resolves its layout geometry, so the
          // original-index ordering assertion holds.
          final ohpY = tester
              .getTopLeft(find.text('OHP', skipOffstage: false))
              .dy;
          expect(
            benchY < ohpY,
            isTrue,
            reason: 'undo reinserts Bench Press at its original index (0)',
          );
        },
      );
    });

    group('per-card state isolation (missing-key-state-reuse)', () {
      testWidgets(
        'removing a card does NOT leak its + Add weight reveal onto the '
        'card that takes its position',
        (tester) async {
          // Two bodyweight entries: a weighted pull-up (added-weight target →
          // the stepper auto-reveals) ABOVE a plain dip (no added weight →
          // collapsed). Without a stable key + didUpdateWidget, removing index
          // 0 reuses the State by position and bleeds the revealed flag onto
          // the dip (cluster: missing-key-state-reuse).
          final routine = Routine(
            id: 'routine-bw-leak',
            name: 'Calisthenics',
            isDefault: false,
            exercises: [
              RoutineExercise(
                exerciseId: 'ex-pullup',
                setConfigs: const [
                  RoutineSetConfig(
                    targetReps: 8,
                    targetWeight: 20,
                    restSeconds: 90,
                  ),
                ],
                exercise: _makeBodyweight(
                  id: 'ex-pullup',
                  name: 'Weighted Pull-up',
                ),
              ),
              RoutineExercise(
                exerciseId: 'ex-dip',
                setConfigs: const [
                  RoutineSetConfig(targetReps: 8, restSeconds: 90),
                ],
                exercise: _makeBodyweight(id: 'ex-dip', name: 'Dip'),
              ),
            ],
            createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
          );

          await tester.pumpWidget(_buildScreen(routine: routine));
          await tester.pumpAndSettle();

          // Precondition: the pull-up (card 0, onstage) auto-reveals its
          // Added-weight stepper; the dip (card 1, built but offstage below the
          // 600dp viewport) shows the collapsed "+ Add weight" CTA —
          // skipOffstage:false resolves it.
          expect(find.text('Added weight'), findsOneWidget);
          expect(
            find.text('+ Add weight', skipOffstage: false),
            findsOneWidget,
          );

          // Remove the pull-up (first card).
          await tester.tap(find.byIcon(Icons.close).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Only the dip remains. It must keep its OWN collapsed state — the
          // pull-up's revealed Added-weight stepper must NOT bleed through.
          expect(find.text('Weighted Pull-up'), findsNothing);
          expect(find.text('Dip'), findsOneWidget);
          expect(
            find.text('+ Add weight'),
            findsOneWidget,
            reason: 'the dip has no added weight — its reveal stays collapsed',
          );
          expect(
            find.text('Added weight'),
            findsNothing,
            reason: "the removed card's reveal flag must not leak onto the dip",
          );
        },
      );
    });
  });
}
