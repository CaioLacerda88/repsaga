/// PR-7 widget contracts for [ExerciseCard]: filled-accent treatment on the
/// `_AddSetButton` and the text-only PR-empty-state row.
///
/// This file intentionally pins the *visual* contracts only — the Semantics
/// identifiers, action wiring, and tap-target floors are covered by
/// `exercise_card_action_identifiers_test.dart`,
/// `exercise_card_test.dart`, and the active-workout tap-target tests. PR-7
/// is the brand-voice + accent-treatment pass; this file's job is to make
/// sure a future formatter / theme refactor can't silently revert the
/// hotViolet fill or re-introduce the generic Material trophy emoji.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/exercise_card.dart';

import '../../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Fixtures (kept local so a refactor of the sibling test files doesn't
// silently change what this file measures).
// ---------------------------------------------------------------------------

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Barbell Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

final _testWorkout = Workout(
  id: 'workout-001',
  userId: 'user-001',
  name: 'Push Day',
  startedAt: DateTime.now().toUtc(),
  isActive: true,
  createdAt: DateTime.now().toUtc(),
);

ExerciseSet _makeSet({required int setNumber, bool isCompleted = false}) =>
    ExerciseSet(
      id: 'set-$setNumber',
      workoutExerciseId: 'we-001',
      setNumber: setNumber,
      reps: 10,
      weight: 60.0,
      isCompleted: isCompleted,
      setType: SetType.working,
      createdAt: DateTime.now().toUtc(),
    );

ActiveWorkoutExercise _makeActiveExercise({int setCount = 2}) =>
    ActiveWorkoutExercise(
      workoutExercise: WorkoutExercise(
        id: 'we-001',
        workoutId: 'workout-001',
        exerciseId: 'exercise-001',
        order: 1,
        exercise: _testExercise,
      ),
      sets: List.generate(setCount, (i) => _makeSet(setNumber: i + 1)),
    );

ActiveWorkoutState _makeState(ActiveWorkoutExercise activeExercise) =>
    ActiveWorkoutState(workout: _testWorkout, exercises: [activeExercise]);

class _FixedActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _FixedActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  @override
  RestTimerState? build() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KgProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'u1', weightUnit: 'kg');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildExerciseCard(ActiveWorkoutExercise activeExercise) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(_makeState(activeExercise)),
      ),
      restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
      exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: ExerciseCard(
            activeExercise: activeExercise,
            reorderMode: false,
            isFirst: true,
            isLast: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ExerciseCard PR-7 brand-voice + accent contracts', () {
    // -----------------------------------------------------------------------
    // _AddSetButton filled accent (PR-7).
    //
    // Pre-fix the button was an OutlinedButton whose only chrome was a
    // `primary @ alpha 0.3` border that read fainter than the Fill Remaining
    // TextButton rendered immediately below. Add Set is the highest-frequency
    // action in the active workout — it deserves to read as a positive
    // primary action, not a quiet secondary one.
    //
    // The fix: 12% hotViolet fill + 60% hotViolet border + full-strength
    // hotViolet foreground, while preserving the 48dp tap-target floor + the
    // `workout-add-set` Semantics identifier the E2E suite depends on.
    // -----------------------------------------------------------------------
    testWidgets(
      'Add Set button has a non-transparent hotViolet-tinted fill (filled accent treatment)',
      (tester) async {
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        // The Semantics identifier is the contract surface — find the
        // OutlinedButton mounted under it (one Add Set button per card).
        final addSetFinder = find.descendant(
          of: find.bySemanticsIdentifier('workout-add-set'),
          matching: find.byType(OutlinedButton),
        );
        expect(addSetFinder, findsOneWidget);

        final OutlinedButton button = tester.widget<OutlinedButton>(
          addSetFinder,
        );
        final ButtonStyle? style = button.style;
        expect(
          style,
          isNotNull,
          reason: 'OutlinedButton must declare a ButtonStyle (filled accent).',
        );

        final Color? fill = style!.backgroundColor?.resolve(<WidgetState>{});
        expect(
          fill,
          isNotNull,
          reason:
              'Add Set button MUST resolve a non-null background color in '
              'the default state. Pre-PR-7 the OutlinedButton had no '
              'backgroundColor at all (transparent) — the affordance read '
              'as a quiet secondary outline.',
        );
        expect(
          fill!.a,
          greaterThan(0),
          reason:
              'Background color must be non-transparent — a 12%-alpha '
              'hotViolet tint is the PR-7 contract.',
        );
        // Channel-level pin: the resolved color is hotViolet, not the
        // generic theme primary. If a future refactor swaps to primary the
        // visual tone shifts (deeper blue-violet) and this fails — that is
        // a deliberate design choice and changing it requires re-reviewing
        // the Add Set affordance weight.
        expect(
          fill.r,
          AppColors.hotViolet.r,
          reason:
              'Fill must be hotViolet-derived (red channel match). PR-7 uses '
              'AppColors.hotViolet @ 12% alpha specifically; primaryViolet '
              'reads too dark on the abyss surface.',
        );
        expect(fill.g, AppColors.hotViolet.g);
        expect(fill.b, AppColors.hotViolet.b);
      },
    );

    testWidgets(
      'Add Set button preserves the 48dp tap-target floor after the accent swap',
      (tester) async {
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        // tester.getSize is the only reliable measure here — Material's
        // `MaterialTapTargetSize.padded` default adds slack outside the
        // declared `minimumSize`. See lessons.md "Tap-target sizes via
        // tester.getSize".
        final Size size = tester.getSize(
          find.descendant(
            of: find.bySemanticsIdentifier('workout-add-set'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason:
              'WCAG AA tap-target floor — the accent swap must not drop the '
              '48dp height contract.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // PR-empty-state row (PR-7).
    //
    // Pre-fix the empty row rendered `Icons.emoji_events_rounded` (Material
    // trophy emoji) at 20dp + the "No records yet" text. The trophy reads as
    // a generic congratulations sticker — wrong tone for an empty-state row
    // that should feel like a quiet absence, not a participation award. The
    // v3-silhouette pack has no trophy glyph so we drop the icon entirely
    // and lean on muted italic text. This also keeps the heroGold reward
    // accent semantic exclusive to the `RewardAccent` PR celebration moment
    // per the heroGold scarcity rule.
    // -----------------------------------------------------------------------
    testWidgets(
      'PR empty-state row renders text-only — no Material trophy icon',
      (tester) async {
        // The empty-state row is reached via the bottom-sheet detail screen.
        // Tap the exercise header's "Tap for details" affordance to open the
        // sheet, then assert.
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        // Open the detail sheet by tapping the exercise header.
        await tester.tap(
          find.bySemanticsLabel(RegExp(r'^Exercise: Barbell Bench Press\.')),
        );
        await tester.pumpAndSettle();

        // Landmark guard (reviewer PR #208 follow-up): assert the bottom
        // sheet actually opened before checking its contents. Without this,
        // a future change to the Semantics label format above would leave
        // `tester.tap` finding nothing, `pumpAndSettle` returning
        // immediately, and the empty-row assertions passing trivially —
        // a vacuous test. Pin a landmark widget unique to the sheet.
        expect(
          find.byType(DraggableScrollableSheet),
          findsOneWidget,
          reason:
              'detail bottom sheet did not open — the header tap missed. '
              'Check the Semantics label regex above against the current '
              'shape in `_ExerciseCardHeader`.',
        );

        // The PR section's empty-row renders "No records yet" — pin its
        // presence and pin the absence of the generic trophy emoji icon.
        expect(find.text('No records yet'), findsOneWidget);
        expect(
          find.byIcon(Icons.emoji_events_rounded),
          findsNothing,
          reason:
              'PR-7: the Material trophy emoji read as generic AI-app '
              'chrome on an empty state. The v3-silhouette pack has no '
              'trophy glyph; the empty row is text-only with a muted '
              'italic treatment.',
        );
      },
    );
  });
}
