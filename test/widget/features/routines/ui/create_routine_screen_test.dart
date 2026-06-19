import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/ui/create_routine_screen.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/ui/widgets/cardio_field.dart';

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
    testWidgets('Save button disabled when name is empty and no exercises', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Find the Save TextButton
      final saveButton = find.widgetWithText(TextButton, 'Save');
      expect(saveButton, findsOneWidget);

      // It should be disabled (onPressed is null)
      final button = tester.widget<TextButton>(saveButton);
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'Save button still disabled when name entered but no exercises',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        // Enter a name (first TextField — the notes field is second)
        await tester.enterText(find.byType(TextField).first, 'My Routine');
        await tester.pump();

        final saveButton = find.widgetWithText(TextButton, 'Save');
        final button = tester.widget<TextButton>(saveButton);
        expect(button.onPressed, isNull);
      },
    );

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

      // Initially 3 sets
      expect(find.text('3'), findsOneWidget);

      // Find the IconButton with Icons.add (stepper +), not the OutlinedButton
      final stepperAdd = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      );
      await tester.tap(stepperAdd.first);
      await tester.pump();

      expect(find.text('4'), findsOneWidget);
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

      // Initially 3 sets
      expect(find.text('3'), findsOneWidget);

      // Tap the - button
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
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

      // Tap 2m chip
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

        // Notes left blank — Save must still be enabled.
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Save'),
        );
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

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('OHP'), findsOneWidget);

      // Tap the first close button to remove Bench Press
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('Bench Press'), findsNothing);
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
        'a bodyweight exercise shows the BODYWEIGHT tag and KEEPS the set '
        'stepper + rest chips',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              routine: _routineWith(
                _makeBodyweight(),
                setConfigs: const [
                  RoutineSetConfig(restSeconds: 90),
                  RoutineSetConfig(restSeconds: 90),
                  RoutineSetConfig(restSeconds: 90),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Neutral BODYWEIGHT tag (uppercased) instead of a muscle chip.
          expect(find.text('BODYWEIGHT'), findsOneWidget);

          // The strength layout is UNCHANGED for bodyweight.
          expect(find.text('Sets'), findsOneWidget);
          expect(find.text('3'), findsOneWidget); // set count
          expect(find.text('Rest'), findsOneWidget);
          expect(find.text('1m 30s'), findsOneWidget); // 90s chip selected

          // No cardio target slots.
          expect(find.text('Target time'), findsNothing);
          expect(find.text('Target distance'), findsNothing);
        },
      );

      testWidgets(
        'a strength exercise is unchanged (muscle chip + set stepper + rest '
        'chips, no BODYWEIGHT tag, no target slots)',
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
          expect(find.text('Sets'), findsOneWidget);
          expect(find.text('Rest'), findsOneWidget);

          expect(find.text('BODYWEIGHT'), findsNothing);
          expect(find.text('Target time'), findsNothing);
          expect(find.text('Target distance'), findsNothing);
        },
      );
    });

    // Keyboard behavior contract. Tapping the name / notes field must OVERLAY
    // the keyboard over the form — the screen behind stays untouched — instead
    // of resizing the body and reflowing the list (which shoved the exercises
    // under a rising empty band, AND left the cards unpainted because the
    // SingleChildScrollView mis-repaints on resize). `resizeToAvoidBottomInset:
    // false` is the single fix: no resize → no reflow → no mis-repaint. The
    // on-device rendering itself was verified manually because a widget test
    // cannot raise a real soft keyboard (see
    // feedback_visual_verification_physical_device).
    //
    // The body stays a SingleChildScrollView (NOT a ListView) on purpose: it
    // builds every exercise card eagerly, so all cards are in the widget tree /
    // AOM for E2E + screen readers even when scrolled off. A lazy ListView
    // dropped off-viewport cards from the DOM and broke the routine-create E2E.
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

      testWidgets('form body eagerly builds all exercise cards (no lazy viewport)', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen(routine: routineWithExercises()));
        await tester.pumpAndSettle();

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.body,
          isA<SingleChildScrollView>(),
          reason:
              'the body must build every exercise card eagerly so all cards are '
              'in the tree/AOM for E2E + screen readers even when scrolled off; '
              'a lazy ListView dropped off-viewport cards and broke E2E',
        );
        // Both seeded exercise cards are in the tree, not just the on-screen one.
        expect(find.text('Bench Press'), findsOneWidget);
        expect(find.text('OHP'), findsOneWidget);
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
  });
}
