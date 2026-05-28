/// Widget tests for [FinishWorkoutCoordinator]'s empty-session guard
/// (Phase 30 PR 30a — mockup §5 State 11).
///
/// Pinned contracts:
///   1. When [ActiveWorkoutNotifier.totalSetsCount] == 0, tapping Finish
///      shows [EmptySessionGuardSheet] BEFORE the post-session route is pushed.
///   2. Choosing "Continuar treinando" dismisses the sheet and leaves the
///      active-workout screen visible — the post-session route is NEVER pushed.
///   3. Choosing "Descartar" navigates to /home — the post-session route is
///      NEVER pushed.
///
/// These assertions satisfy WIP.md PR 30a acceptance criterion #3:
///   "Empty-session guard (State 11): zero sets → EmptySessionGuardSheet
///    modal shows; Descartar → /home; Continuar treinando → returns to
///    active workout. Post-session route is never pushed for empty sessions."
///
/// The coordinator's post-session push path reads the GoRouter context —
/// we capture the route transitions via a spy GoRouter that records calls
/// to `go()` / `push()` so we can assert NEVER-pushed without running
/// a full integration harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/coordinators/finish_workout_coordinator.dart';
import 'package:repsaga/features/workouts/ui/widgets/empty_session_guard_sheet.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

ActiveWorkoutState _makeZeroSetState() {
  return ActiveWorkoutState(
    workout: Workout(
      id: 'workout-001',
      userId: 'user-001',
      name: 'Push Day',
      startedAt: DateTime.now().toUtc(),
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    ),
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-001',
          workoutId: 'workout-001',
          exerciseId: 'exercise-001',
          order: 0,
          exercise: _testExercise,
        ),
        // Zero sets — the guard condition.
        sets: const [],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

/// Fake notifier that always reports zero sets and a no-op discardWorkout.
///
/// `totalSetsCount == 0` triggers the empty-session guard in
/// [FinishWorkoutCoordinator.finish]. The `discardWorkout` stub completes
/// immediately so the Descartar path resolves synchronously in the test.
class _ZeroSetNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _ZeroSetNotifier(this._state);
  final ActiveWorkoutState _state;

  @override
  Future<ActiveWorkoutState?> build() async => _state;

  @override
  int get totalSetsCount => 0;

  @override
  int get incompleteSetsCount => 0;

  @override
  Future<void> discardWorkout() async {
    // Simulate the notifier transitioning to null (workout deleted).
    state = const AsyncData(null);
  }

  @override
  CelebrationQueueResult? consumeLastCelebration() => null;

  /// Phase 32 PR 32d: the coordinator's finish() path now calls
  /// [ActiveWorkoutNotifier.recordZeroXpSession] BEFORE showing the guard
  /// sheet so the funnel signal lands regardless of which branch the user
  /// picks. Stubbed as a no-op here — the analytics emit contract is
  /// covered separately in
  /// `active_workout_notifier_zero_xp_emit_test.dart`. The guard-sheet
  /// route assertions remain the contract pinned by this file.
  @override
  void recordZeroXpSession() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

/// Builds a minimal GoRouter + ProviderScope scaffold that allows the
/// coordinator's [finish] method to be called from a button tap.
///
/// [navigatedLocations] accumulates every `go()` / `push()` call so we can
/// assert no post-session route was pushed. The coordinator reads the router
/// via `context.go(...)` which GoRouter intercepts in the harness's router.
Widget _buildHarness({
  required _ZeroSetNotifier notifier,
  required List<String> navigatedLocations,
}) {
  // Spy router: records location strings from `go()` calls. The coordinator
  // calls `context.go('/home')` on the Discard path and
  // `rootContext.go('/workout/finish/:id')` on the post-session path.
  // Under the test harness the GoRouter handles `go()` via its own
  // internal navigation; we observe the destination by watching
  // `router.routerDelegate.currentConfiguration` after settling.
  final router = GoRouter(
    initialLocation: '/active',
    routes: [
      GoRoute(
        path: '/active',
        builder: (context, state) => _ActiveWorkoutStub(notifier: notifier),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          navigatedLocations.add('/home');
          return const Scaffold(body: Text('Home'));
        },
      ),
      GoRoute(
        path: '/workout/finish/:workoutId',
        builder: (context, state) {
          // This must NEVER be reached in the empty-session tests.
          navigatedLocations.add('/workout/finish');
          return const Scaffold(body: Text('PostSession'));
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [activeWorkoutProvider.overrideWith(() => notifier)],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Minimal active-workout stub screen. Exposes a "Finish" button whose
/// tap calls [FinishWorkoutCoordinator.finish] via a [ConsumerStatefulWidget].
class _ActiveWorkoutStub extends ConsumerStatefulWidget {
  const _ActiveWorkoutStub({required this.notifier});
  final _ZeroSetNotifier notifier;

  @override
  ConsumerState<_ActiveWorkoutStub> createState() => _ActiveWorkoutStubState();
}

class _ActiveWorkoutStubState extends ConsumerState<_ActiveWorkoutStub> {
  late final FinishWorkoutCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = FinishWorkoutCoordinator();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('finish-btn'),
          onPressed: () => _coordinator.finish(context: context, ref: ref),
          child: const Text('Finish'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FinishWorkoutCoordinator — empty-session guard (State 11)', () {
    testWidgets('shows EmptySessionGuardSheet when total set count is zero', (
      tester,
    ) async {
      final navigated = <String>[];
      final notifier = _ZeroSetNotifier(_makeZeroSetState());

      await tester.pumpWidget(
        _buildHarness(notifier: notifier, navigatedLocations: navigated),
      );
      await tester.pumpAndSettle();

      // Tap the Finish button — triggers coordinator.finish().
      await tester.tap(find.byKey(const ValueKey('finish-btn')));
      await tester.pumpAndSettle();

      // Contract: the empty-session guard sheet must appear.
      expect(
        find.byType(EmptySessionGuardSheet),
        findsOneWidget,
        reason:
            'EmptySessionGuardSheet must show when totalSetsCount == 0. '
            'Without the guard, the coordinator would push the post-session '
            'route for zero work — training users that the RPG layer is fake.',
      );
    });

    testWidgets(
      'post-session route is NEVER pushed when the guard sheet is shown',
      (tester) async {
        final navigated = <String>[];
        final notifier = _ZeroSetNotifier(_makeZeroSetState());

        await tester.pumpWidget(
          _buildHarness(notifier: notifier, navigatedLocations: navigated),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('finish-btn')));
        await tester.pumpAndSettle();

        // The guard sheet is showing; the post-session route must not have
        // been pushed before the user made a choice.
        expect(
          navigated.any((l) => l.startsWith('/workout/finish')),
          isFalse,
          reason:
              'Post-session route must NEVER be pushed while the guard sheet '
              'is showing. If this fails, the empty-session guard was bypassed.',
        );
      },
    );

    testWidgets(
      '"Continuar treinando" dismisses sheet and keeps active-workout screen visible',
      (tester) async {
        final navigated = <String>[];
        final notifier = _ZeroSetNotifier(_makeZeroSetState());

        await tester.pumpWidget(
          _buildHarness(notifier: notifier, navigatedLocations: navigated),
        );
        await tester.pumpAndSettle();

        // Open the guard sheet.
        await tester.tap(find.byKey(const ValueKey('finish-btn')));
        await tester.pumpAndSettle();

        expect(find.byType(EmptySessionGuardSheet), findsOneWidget);

        // Tap the "Continuar treinando" FilledButton.
        // The sheet renders: FilledButton (Continuar) + TextButton (Descartar).
        final continueBtn = find.descendant(
          of: find.byType(EmptySessionGuardSheet),
          matching: find.byType(FilledButton),
        );
        await tester.tap(continueBtn);
        await tester.pumpAndSettle();

        // Sheet dismissed — active workout screen still mounted.
        expect(find.byType(EmptySessionGuardSheet), findsNothing);
        expect(find.byKey(const ValueKey('finish-btn')), findsOneWidget);

        // No post-session route pushed.
        expect(
          navigated.any((l) => l.startsWith('/workout/finish')),
          isFalse,
          reason:
              '"Continuar treinando" must leave the active-workout screen '
              'open and must NOT push the post-session route.',
        );
      },
    );

    testWidgets(
      '"Descartar" navigates to /home and NEVER pushes the post-session route',
      (tester) async {
        final navigated = <String>[];
        final notifier = _ZeroSetNotifier(_makeZeroSetState());

        await tester.pumpWidget(
          _buildHarness(notifier: notifier, navigatedLocations: navigated),
        );
        await tester.pumpAndSettle();

        // Open the guard sheet.
        await tester.tap(find.byKey(const ValueKey('finish-btn')));
        await tester.pumpAndSettle();

        expect(find.byType(EmptySessionGuardSheet), findsOneWidget);

        // Tap the "Descartar" TextButton.
        // The sheet renders: FilledButton (Continuar) + TextButton (Descartar).
        final discardBtn = find.descendant(
          of: find.byType(EmptySessionGuardSheet),
          matching: find.byType(TextButton),
        );
        await tester.tap(discardBtn);
        await tester.pumpAndSettle();

        // Sheet dismissed; navigated to /home.
        expect(find.byType(EmptySessionGuardSheet), findsNothing);
        expect(find.text('Home'), findsOneWidget);

        // Positive assertion: /home was navigated.
        expect(
          navigated.contains('/home'),
          isTrue,
          reason:
              '"Descartar" must navigate to /home so the discarded workout '
              'does not remain in the active-workout screen.',
        );

        // Critical negative assertion: post-session route was never pushed.
        expect(
          navigated.any((l) => l.startsWith('/workout/finish')),
          isFalse,
          reason:
              '"Descartar" from the empty-session guard must NEVER push '
              'the post-session route. Zero work does not earn a ceremony.',
        );
      },
    );
  });
}
