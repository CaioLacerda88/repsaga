/// Widget tests for [CardioEntryCard] + [DurationStepper] (Phase 38b).
///
/// Pins the user-visible contracts of the locked
/// `docs/phase-38-mockups.html` states:
///   1. Empty — 30:00 duration hero, `+ add` ghosts on distance/RPE,
///      "Complete cardio" CTA, activity eyebrow, teal stripe.
///   2. Filled — distance value + unit and RPE pips replace the ghosts.
///   3. Completed — body collapses to the one-line summary + green ✓;
///      stepper and CTA disappear; ✓ tap re-opens for edits.
/// Plus the input flows (stepper ±, duration dialog, distance dialog, RPE
/// sheet) asserted on what the user SEES afterwards — not on call wiring —
/// and the 48dp tap-target floors via `tester.getSize` (feedback:
/// tap-target-measurement).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/cardio_session.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/cardio_entry_card.dart';
import 'package:repsaga/features/workouts/ui/widgets/cardio_field.dart';
import 'package:repsaga/features/workouts/ui/widgets/duration_stepper.dart';

import '../../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _treadmill = Exercise(
  id: 'exercise-treadmill',
  name: 'Treadmill',
  muscleGroup: MuscleGroup.cardio,
  equipmentType: EquipmentType.machine,
  isDefault: true,
  createdAt: DateTime(2026),
  slug: 'treadmill',
);

final _workout = Workout(
  id: 'workout-001',
  userId: 'user-001',
  name: 'Cardio Day',
  startedAt: DateTime.now().toUtc(),
  isActive: true,
  createdAt: DateTime.now().toUtc(),
);

CardioSession _session({
  int durationSeconds = 1800,
  double? distanceM,
  int? rpe,
  bool isCompleted = false,
}) {
  return CardioSession(
    id: 'cardio-001',
    workoutId: 'workout-001',
    exerciseId: 'exercise-treadmill',
    durationSeconds: durationSeconds,
    distanceM: distanceM,
    rpe: rpe,
    isCompleted: isCompleted,
    createdAt: DateTime.now().toUtc(),
  );
}

ActiveWorkoutExercise _entry(CardioSession session) {
  return ActiveWorkoutExercise(
    workoutExercise: WorkoutExercise(
      id: 'we-cardio',
      workoutId: 'workout-001',
      exerciseId: 'exercise-treadmill',
      order: 0,
      exercise: _treadmill,
    ),
    sets: const [],
    cardioSession: session,
  );
}

// ---------------------------------------------------------------------------
// Provider stubs
// ---------------------------------------------------------------------------

/// Applies cardio mutations to its in-memory state so the card observably
/// re-renders — the tests assert on what the user SEES after an
/// interaction, which requires the state round-trip to actually happen.
class _MutatingActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _MutatingActiveWorkoutNotifier(this._initial);
  final ActiveWorkoutState _initial;

  @override
  Future<ActiveWorkoutState?> build() async => _initial;

  @override
  Future<void> updateCardioSession(
    String workoutExerciseId, {
    int? durationSeconds,
    double? distanceM,
    int? rpe,
  }) async {
    final current = state.value!;
    state = AsyncData(
      current.copyWith(
        exercises: current.exercises.map((e) {
          if (e.workoutExercise.id != workoutExerciseId) return e;
          final s = e.cardioSession!;
          return e.copyWith(
            cardioSession: s.copyWith(
              durationSeconds: durationSeconds ?? s.durationSeconds,
              distanceM: distanceM ?? s.distanceM,
              rpe: rpe ?? s.rpe,
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Future<void> completeCardioEntry(String workoutExerciseId) async {
    final current = state.value!;
    state = AsyncData(
      current.copyWith(
        exercises: current.exercises.map((e) {
          if (e.workoutExercise.id != workoutExerciseId) return e;
          final s = e.cardioSession!;
          return e.copyWith(
            cardioSession: s.copyWith(isCompleted: !s.isCompleted),
          );
        }).toList(),
      ),
    );
  }

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

/// Pumps a [CardioEntryCard] wired to a mutating notifier. The card watches
/// `activeWorkoutProvider` only through its interactions; rendering reads
/// the constructor's [entry], so a `_Rebuilder` consumer re-feeds the
/// latest state into the card on every notifier emission (mirroring what
/// ExerciseList does in production).
Widget _buildCard(
  _MutatingActiveWorkoutNotifier notifier, {
  bool reorderMode = false,
}) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(() => notifier),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(activeWorkoutProvider).value;
            if (state == null) return const SizedBox.shrink();
            return CardioEntryCard(
              activeExercise: state.exercises.single,
              reorderMode: reorderMode,
              isFirst: true,
              isLast: true,
            );
          },
        ),
      ),
    ),
  );
}

Future<_MutatingActiveWorkoutNotifier> _pump(
  WidgetTester tester,
  CardioSession session, {
  bool reorderMode = false,
}) async {
  final notifier = _MutatingActiveWorkoutNotifier(
    ActiveWorkoutState(workout: _workout, exercises: [_entry(session)]),
  );
  await tester.pumpWidget(_buildCard(notifier, reorderMode: reorderMode));
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  group('CardioEntryCard — empty state (mockup 1)', () {
    testWidgets('renders the 30:00 duration hero, MIN label, activity '
        'eyebrow, two + add ghosts and the Complete cardio CTA', (
      tester,
    ) async {
      await _pump(tester, _session());

      expect(find.text('30:00'), findsOneWidget);
      expect(find.text('MIN'), findsOneWidget);
      // en-locale eyebrow for the treadmill slug.
      expect(find.text('RUNNING · CARDIO'), findsOneWidget);
      // Optional fields invite, never nag — one ghost per field, and no
      // zero-value rendering anywhere.
      expect(find.text('+ add'), findsNWidgets(2));
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.text('Complete cardio'), findsOneWidget);
      expect(find.byType(DurationStepper), findsOneWidget);
    });

    testWidgets('renders the teal identity stripe', (tester) async {
      await _pump(tester, _session());

      final stripe = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byType(CardioEntryCard),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(
        stripe.any((w) => w.color == AppColors.bodyPartCardio),
        isTrue,
        reason:
            'The 3dp teal stripe is the at-a-glance cardio marker '
            '(locked mockup .card.cardio::before).',
      );
    });
  });

  group('CardioEntryCard — duration input', () {
    testWidgets('+ steps the hero up by 30 seconds', (tester) async {
      await _pump(tester, _session());

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      expect(find.text('30:30'), findsOneWidget);
      expect(find.text('30:00'), findsNothing);
    });

    testWidgets('- floors at 0:30 — 0:00 is unreachable, CTA stays enabled', (
      tester,
    ) async {
      await _pump(tester, _session(durationSeconds: 30));

      // At the 30s floor the minus is a no-op: tapping leaves the hero at
      // 0:30 and never reaches 0:00 (duration is always > 0 by UI
      // construction; the DB CHECK > 0 is the backstop).
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(find.text('0:30'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);

      final cta = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Complete cardio'),
      );
      expect(
        cta.onPressed,
        isNotNull,
        reason:
            'duration can never be 0, so completing is always available — '
            'there is no dead disabled-CTA state.',
      );
    });

    testWidgets('tapping the value opens the dialog; mm:ss entry updates the '
        'hero', (tester) async {
      await _pump(tester, _session());

      await tester.tap(find.text('30:00'));
      await tester.pumpAndSettle();
      expect(find.text('Enter duration'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '28:45');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('28:45'), findsOneWidget);
      expect(find.text('Enter duration'), findsNothing);
    });

    testWidgets('stepper ± buttons meet the 40×48 tap-target floor', (
      tester,
    ) async {
      await _pump(tester, _session());

      // Rendered size, not declared constraints (feedback:
      // tap-target-measurement — WeightStepper's compact density silently
      // shrank its RENDERED buttons to 40×40 while its declared-constraint
      // test stayed green; DurationStepper drops the density override so
      // the real hit-box honors the floor: 40dp visual width grows to the
      // 48dp Material padded tap target, height renders at 48).
      for (final finder in [
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(IconButton),
        ),
        find.ancestor(
          of: find.byIcon(Icons.add).first,
          matching: find.byType(IconButton),
        ),
      ]) {
        final size = tester.getSize(finder);
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: 'stepper button height must meet the 48dp floor',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(40),
          reason: 'stepper button width must meet the 40dp BUG-019 floor',
        );
      }
    });
  });

  group('CardioEntryCard — distance input', () {
    testWidgets('tap-to-type sets the value; ghost is replaced by value + '
        'unit', (tester) async {
      await _pump(tester, _session());

      await tester.tap(find.text('DISTANCE'));
      await tester.pumpAndSettle();
      expect(find.text('Enter distance'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '5.2');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('5.2'), findsOneWidget);
      expect(find.textContaining(' km'), findsOneWidget);
      // Only the RPE ghost remains.
      expect(find.text('+ add'), findsOneWidget);
    });

    testWidgets('comma decimal parses too (pt-BR numeric keyboard habit)', (
      tester,
    ) async {
      await _pump(tester, _session());

      await tester.tap(find.text('DISTANCE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '5,2');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('5.2'), findsOneWidget);
    });
  });

  group('CardioEntryCard — RPE input', () {
    testWidgets('field opens the 1–10 sheet; picking 7 reflects back as '
        'pips and drops the ghost', (tester) async {
      await _pump(tester, _session());

      await tester.tap(find.text('EFFORT (RPE)'));
      await tester.pumpAndSettle();
      expect(find.text('Effort (RPE)'), findsOneWidget);

      await tester.tap(find.text('7'));
      await tester.pumpAndSettle();

      // Sheet dismissed, value reflected: the empty-state long label swaps
      // to the short one and the distance ghost is the only one left.
      expect(find.text('Effort (RPE)'), findsNothing);
      expect(find.text('EFFORT'), findsOneWidget);
      expect(find.text('EFFORT (RPE)'), findsNothing);
      expect(find.text('+ add'), findsOneWidget);
    });

    testWidgets('every RPE sheet option meets the 48dp tap-target floor', (
      tester,
    ) async {
      await _pump(tester, _session());

      await tester.tap(find.text('EFFORT (RPE)'));
      await tester.pumpAndSettle();

      for (var value = 1; value <= 10; value++) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text('$value'),
            matching: find.byType(InkWell),
          ),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: 'RPE option $value height (tap-target floor)',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(48),
          reason: 'RPE option $value width (tap-target floor)',
        );
      }
    });
  });

  group('CardioEntryCard — completion (mockup 3)', () {
    testWidgets('Complete cardio collapses the body to the summary line + '
        'green ✓; inputs disappear', (tester) async {
      await _pump(
        tester,
        _session(durationSeconds: 1725, distanceM: 5200.0, rpe: 7),
      );

      await tester.tap(find.text('Complete cardio'));
      await tester.pumpAndSettle();

      // Collapsed summary with every logged segment.
      expect(find.text('28:45 min · 5.2 km · effort 7/10'), findsOneWidget);
      // Editing chrome is gone.
      expect(find.byType(DurationStepper), findsNothing);
      expect(find.text('Complete cardio'), findsNothing);
      expect(find.text('+ add'), findsNothing);
      // Green ✓ in the header trailing slot.
      final check = tester.widget<Icon>(find.byIcon(Icons.check));
      expect(check.color, AppColors.success);
      // Teal stripe persists as the cardio identity.
      final stripes = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byType(CardioEntryCard),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(stripes.any((w) => w.color == AppColors.bodyPartCardio), isTrue);
    });

    testWidgets('summary omits optional segments that were never logged', (
      tester,
    ) async {
      await _pump(tester, _session(durationSeconds: 1800, isCompleted: true));

      expect(find.text('30:00 min'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('effort'), findsNothing);
    });

    testWidgets('tapping the green ✓ re-opens the entry for edits', (
      tester,
    ) async {
      await _pump(tester, _session(isCompleted: true));

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.byType(DurationStepper), findsOneWidget);
      expect(find.text('Complete cardio'), findsOneWidget);
      expect(find.text('30:00 min'), findsNothing);
    });

    testWidgets('the Complete cardio CTA meets the 48dp height floor', (
      tester,
    ) async {
      await _pump(tester, _session());

      final size = tester.getSize(
        find.widgetWithText(OutlinedButton, 'Complete cardio'),
      );
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('CardioEntryCard — 320dp overflow guards', () {
    // Pumps the card into a 320dp-wide surface — the smallest Android
    // breakpoint the responsive layout must survive. A RenderFlex overflow
    // throws during paint and `tester.takeException()` surfaces it.
    Future<void> pumpAt320(WidgetTester tester, CardioSession session) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = _MutatingActiveWorkoutNotifier(
        ActiveWorkoutState(workout: _workout, exercises: [_entry(session)]),
      );
      await tester.pumpWidget(_buildCard(notifier));
      await tester.pumpAndSettle();
    }

    testWidgets('filled with a max-10 RPE does not overflow at 320dp', (
      tester,
    ) async {
      await pumpAt320(tester, _session(distanceM: 5200.0, rpe: 10));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the 10-pip RPE row must scale down inside the half-width '
            'field at 320dp instead of overflowing',
      );
    });

    testWidgets('completed summary with all segments does not overflow at '
        '320dp', (tester) async {
      await pumpAt320(
        tester,
        _session(durationSeconds: 1725, distanceM: 5200.0, rpe: 7),
      );
      await tester.tap(find.text('Complete cardio'));
      await tester.pumpAndSettle();

      expect(find.text('28:45 min · 5.2 km · effort 7/10'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the completed one-line summary must scale down at 320dp '
            'instead of overflowing',
      );
    });
  });

  group('CardioEntryCard — reorder mode', () {
    testWidgets('a COMPLETED entry shows the reorder arrows, not the ✓, so it '
        'can be moved', (tester) async {
      await _pump(tester, _session(isCompleted: true), reorderMode: true);

      // In reorder mode the up/down arrows must win over the completed ✓ —
      // otherwise a completed cardio card collapses to the green check and
      // becomes immovable (the ✓ replaces the action cluster in the header).
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(
        find.byIcon(Icons.check),
        findsNothing,
        reason: 'the ✓ must yield to the reorder affordance in reorderMode',
      );
    });

    testWidgets('outside reorder mode a COMPLETED entry still shows the ✓', (
      tester,
    ) async {
      await _pump(tester, _session(isCompleted: true));

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });
  });

  group('CardioEntryCard — shared CardioField density (blast-radius guard)', () {
    testWidgets('the active card keeps the COMPACT CardioField size — the '
        'Phase 38h builder-only large variant must NOT leak in here', (
      tester,
    ) async {
      await _pump(tester, _session());

      final fields = tester.widgetList<CardioField>(find.byType(CardioField));
      expect(fields, isNotEmpty);
      for (final f in fields) {
        expect(
          f.size,
          CardioFieldSize.compact,
          reason:
              'the active CardioEntryCard renders byte-identically to before '
              '38h — the large variant is opt-in for the routine builder only',
        );
        expect(
          f.showEditAffordance,
          isFalse,
          reason: 'the pencil glyph is a routine-builder affordance only',
        );
      }
    });
  });

  group('CardioEntryCard — eyebrow fallback', () {
    testWidgets('unknown slug renders the generic CARDIO eyebrow, never the '
        'raw slug (cluster: slug-rendered-as-display-name)', (tester) async {
      final custom = Exercise(
        id: 'exercise-custom',
        name: 'Stair Climber',
        muscleGroup: MuscleGroup.cardio,
        equipmentType: EquipmentType.machine,
        isDefault: false,
        createdAt: DateTime(2026),
        slug: 'stair_climber',
      );
      final notifier = _MutatingActiveWorkoutNotifier(
        ActiveWorkoutState(
          workout: _workout,
          exercises: [
            ActiveWorkoutExercise(
              workoutExercise: WorkoutExercise(
                id: 'we-cardio',
                workoutId: 'workout-001',
                exerciseId: 'exercise-custom',
                order: 0,
                exercise: custom,
              ),
              sets: const [],
              cardioSession: _session(),
            ),
          ],
        ),
      );
      await tester.pumpWidget(_buildCard(notifier));
      await tester.pumpAndSettle();

      expect(find.text('CARDIO'), findsOneWidget);
      expect(find.textContaining('stair_climber'), findsNothing);
    });
  });
}
