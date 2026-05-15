/// Widget-level coverage for the Phase 24c-8 lazy bodyweight prompt.
///
/// **Scope (per WIP Phase G).** The prompt fires the FIRST time a user
/// completes a set on a `usesBodyweightLoad == true` exercise during a
/// session, when their profile has no `bodyweightKg` AND they haven't
/// permanently dismissed the prompt before. All four gates must hold.
///
/// **Test surface.** We drive [BodyweightPromptCoordinator] directly
/// rather than wiring up the full [ActiveWorkoutScreen] for two reasons:
///   1. The screen mounts a deep widget tree (rest timer, finish bar,
///      celebration plumbing) whose providers each need a fake. The
///      coordinator is the unit-of-behaviour we care about; pumping the
///      whole screen would test every dependency it transitively pulls.
///   2. The trigger contract is "diff previous→next ActiveWorkoutState",
///      which is observable on the coordinator's public API directly.
///      Driving via `maybeShow(previous, next)` exercises the same code
///      path the screen's `ref.listen` uses.
///
/// **Behaviour-not-wiring.** Every assertion checks USER-VISIBLE state:
///   * SnackBar text appearing/absent,
///   * Bottom sheet opening,
///   * The Hive flag being persisted (verified by re-querying the
///     dismissal provider on a fresh container),
///   * No-op behaviour rendering NO snack.
/// We never assert "function was called" or count internal flag writes.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/bodyweight_prompt_dismissal_provider.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/bodyweight_row.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/active_workout_screen.dart';
import 'package:repsaga/features/workouts/ui/coordinators/bodyweight_prompt_coordinator.dart';
import 'package:repsaga/shared/widgets/snackbar_tap_out_dismiss_scope.dart';

import '../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _pullUp = Exercise(
  id: 'ex-pullup',
  name: 'Pull-up',
  muscleGroup: MuscleGroup.back,
  equipmentType: EquipmentType.bodyweight,
  isDefault: true,
  usesBodyweightLoad: true,
  createdAt: DateTime(2026),
);

final _benchPress = Exercise(
  id: 'ex-bench',
  name: 'Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  // usesBodyweightLoad defaults to false — explicit-false here is the
  // negative-case fixture: completing a set on this exercise must NEVER
  // trigger the prompt regardless of profile state.
  createdAt: DateTime(2026),
);

Workout _workout() {
  final now = DateTime.now().toUtc();
  return Workout(
    id: 'workout-001',
    userId: 'user-001',
    name: 'Push Day',
    startedAt: now,
    isActive: true,
    createdAt: now,
  );
}

ActiveWorkoutExercise _exerciseEntry({
  required Exercise exercise,
  required List<({int setNumber, bool completed, double? weight, int reps})>
  sets,
  String? workoutExerciseId,
}) {
  final weId = workoutExerciseId ?? 'we-${exercise.id}';
  return ActiveWorkoutExercise(
    workoutExercise: WorkoutExercise(
      id: weId,
      workoutId: 'workout-001',
      exerciseId: exercise.id,
      order: 0,
      exercise: exercise,
    ),
    sets: [
      for (final s in sets)
        ExerciseSet(
          id: '$weId-set-${s.setNumber}',
          workoutExerciseId: weId,
          setNumber: s.setNumber,
          weight: s.weight,
          reps: s.reps,
          setType: SetType.working,
          isCompleted: s.completed,
          createdAt: DateTime(2026),
        ),
    ],
  );
}

ActiveWorkoutState _state(List<ActiveWorkoutExercise> exercises) {
  return ActiveWorkoutState(workout: _workout(), exercises: exercises);
}

/// Minimal AsyncNotifier stub that returns the given Profile (or null)
/// from `build()`. Reused across tests to vary `bodyweightKg` per case.
class _FakeProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _FakeProfileNotifier(this._value);
  final Profile? _value;

  @override
  Future<Profile?> build() async => _value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mounts a minimal harness around the coordinator so it can show
/// SnackBars and resolve `AppLocalizations`. The harness exposes a
/// captured [BuildContext] via a [GlobalKey] sitting BELOW the
/// SnackBarTapOutDismissScope so each test drives the coordinator's
/// `maybeShow` from the SAME context the production screen would supply
/// (a context underneath the scope so `maybeOf` resolves correctly).
///
/// **Single Scaffold + ScaffoldMessenger:** the production screen wraps
/// its inner Scaffold with a route-scoped `ScaffoldMessenger`. We mirror
/// that here — one ScaffoldMessenger immediately above one Scaffold —
/// so `ScaffoldMessenger.of(context)` resolves to the same instance the
/// snack lands on, otherwise the snack queues against an empty
/// messenger and never paints (the symptom of the 10-minute hang in the
/// initial draft of this harness).
///
/// We pump TWO frames after pumpWidget — the first lets the
/// ProfileProvider's `AsyncNotifier.build` resolve (it returns a
/// `Future<Profile?>`), the second lets the resolved value land in the
/// container so subsequent `ref.read(profileProvider).value` reads it.
Future<({BodyweightPromptCoordinator coord, BuildContext ctx, WidgetRef ref})>
_pumpHarness(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  final coord = BodyweightPromptCoordinator();
  final ctxKey = GlobalKey();
  late WidgetRef capturedRef;

  // Pre-read profileProvider so its AsyncNotifier.build() Future enters
  // the microtask queue BEFORE pumpWidget. The first pump then drains
  // microtasks (resolving the Future → AsyncData) in the same frame as
  // the widget tree mounts, so subsequent `ref.read(profileProvider).value`
  // calls observe the resolved Profile.
  container.read(profileProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestMaterialApp(
        home: ScaffoldMessenger(
          child: Scaffold(
            body: SnackBarTapOutDismissScope(
              child: Consumer(
                builder: (consumerCtx, ref, _) {
                  capturedRef = ref;
                  return SizedBox.expand(key: ctxKey);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Two pumps: first lets pumpWidget settle the widget tree, second
  // drains any AsyncNotifier microtasks scheduled during build.
  await tester.pump();
  await tester.pump();

  return (coord: coord, ctx: ctxKey.currentContext!, ref: capturedRef);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bw_prompt_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('BodyweightPromptCoordinator — gating behaviour', () {
    testWidgets(
      'should show the prompt SnackBar on the FIRST completed set of a '
      'usesBodyweightLoad exercise when bodyweight is null and the prompt '
      'has not been dismissed',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const Profile(id: 'u1', bodyweightKg: null),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final harness = await _pumpHarness(tester, container: container);

        final previous = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: false, weight: 0, reps: 8)],
          ),
        ]);
        final next = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: true, weight: 0, reps: 8)],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: previous,
          next: next,
        );
        // SnackBar entrance animation is ~250 ms; pump generously.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text('Set your body weight for accurate XP'),
          findsOneWidget,
          reason:
              'Phase 24c-8: the EN bodyweightPromptTitle must be on-screen '
              'after a fresh isCompleted: false→true transition on a '
              'uses_bodyweight_load exercise with bodyweightKg=null and '
              'no dismissal flag.',
        );
        expect(find.text('Set now'), findsOneWidget);
        expect(find.text('Skip'), findsOneWidget);
      },
    );

    testWidgets(
      'should NOT show a second prompt during the same session even after '
      'another qualifying set is completed (in-memory one-shot)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const Profile(id: 'u1', bodyweightKg: null),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final harness = await _pumpHarness(tester, container: container);

        final s0 = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [
              (setNumber: 1, completed: false, weight: 0, reps: 8),
              (setNumber: 2, completed: false, weight: 0, reps: 8),
            ],
          ),
        ]);
        final s1 = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [
              (setNumber: 1, completed: true, weight: 0, reps: 8),
              (setNumber: 2, completed: false, weight: 0, reps: 8),
            ],
          ),
        ]);
        final s2 = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [
              (setNumber: 1, completed: true, weight: 0, reps: 8),
              (setNumber: 2, completed: true, weight: 0, reps: 8),
            ],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: s0,
          next: s1,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Set your body weight for accurate XP'),
          findsOneWidget,
        );

        // Dismiss the first snack and pump it out of the messenger so the
        // second show would be observable if the coordinator wasn't
        // session-shot.
        ScaffoldMessenger.of(harness.ctx).hideCurrentSnackBar();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Set your body weight for accurate XP'), findsNothing);

        // Second qualifying transition: set #2 just completed.
        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: s1,
          next: s2,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text('Set your body weight for accurate XP'),
          findsNothing,
          reason:
              'Phase 24c-8: the in-memory session-shot guard must prevent '
              'a second prompt within the same coordinator instance even '
              'after another qualifying completion.',
        );
      },
    );

    testWidgets('should NOT show the prompt when the completed set is on a '
        'non-usesBodyweightLoad exercise (bench press)', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(
              const Profile(id: 'u1', bodyweightKg: null),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final harness = await _pumpHarness(tester, container: container);

      final previous = _state([
        _exerciseEntry(
          exercise: _benchPress,
          sets: [(setNumber: 1, completed: false, weight: 60, reps: 8)],
        ),
      ]);
      final next = _state([
        _exerciseEntry(
          exercise: _benchPress,
          sets: [(setNumber: 1, completed: true, weight: 60, reps: 8)],
        ),
      ]);

      harness.coord.maybeShow(
        context: harness.ctx,
        ref: harness.ref,
        previous: previous,
        next: next,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Set your body weight for accurate XP'),
        findsNothing,
        reason:
            'Phase 24c-8: the prompt only fires for exercises whose '
            'Exercise.usesBodyweightLoad is true. Bench press '
            '(usesBodyweightLoad=false) must never trigger it.',
      );
    });

    testWidgets(
      'should NOT show the prompt when the profile already has bodyweightKg set',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const Profile(id: 'u1', bodyweightKg: 78.0),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final harness = await _pumpHarness(tester, container: container);

        final previous = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: false, weight: 0, reps: 8)],
          ),
        ]);
        final next = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: true, weight: 0, reps: 8)],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: previous,
          next: next,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text('Set your body weight for accurate XP'),
          findsNothing,
          reason:
              'Phase 24c-8: the prompt only fires when bodyweightKg is '
              'null. A user who has already set it (78.0 here) must never '
              'see the prompt.',
        );
      },
    );

    testWidgets(
      'should NOT show the prompt across sessions once the user has tapped '
      'Skip (Hive flag persists)',
      (tester) async {
        // Pre-seed the dismissal flag in the user_prefs box so the
        // coordinator reads "already dismissed" on its first check.
        // This simulates a user who tapped Skip in a previous session.
        //
        // Hive writes inside `testWidgets` MUST go through `tester.runAsync`
        // — direct `await box.put(...)` against fake_async hangs Hive's
        // own internal Lock<T>. See cluster `feedback_hive_testwidgets`
        // in MEMORY.md.
        await tester.runAsync(() async {
          await Hive.box<dynamic>(HiveService.userPrefs).put(
            'bodyweight_prompt_dismissed_at',
            DateTime.now().toUtc().toIso8601String(),
          );
        });

        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const Profile(id: 'u1', bodyweightKg: null),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final harness = await _pumpHarness(tester, container: container);

        // Sanity: the dismissal provider should observe the seeded flag.
        expect(
          container.read(bodyweightPromptDismissalProvider),
          isTrue,
          reason:
              'BodyweightPromptDismissalProvider must read the persisted '
              'dismissal timestamp on build.',
        );

        final previous = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: false, weight: 0, reps: 8)],
          ),
        ]);
        final next = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: true, weight: 0, reps: 8)],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: previous,
          next: next,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text('Set your body weight for accurate XP'),
          findsNothing,
          reason:
              'Phase 24c-8: a user who tapped Skip in any prior session has '
              '`bodyweight_prompt_dismissed_at` persisted in user_prefs. '
              'The prompt must never show again — Hive flag survives the '
              'cache-schema wipe (24c-2 designs userPrefs out of '
              'cacheSchemaBoxes).',
        );
      },
    );
  });

  group('BodyweightPromptCoordinator — actions', () {
    testWidgets(
      'should open the bodyweight editor bottom sheet when the user taps '
      'the Set now action',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const Profile(id: 'u1', bodyweightKg: null),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final harness = await _pumpHarness(tester, container: container);

        final previous = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: false, weight: 0, reps: 8)],
          ),
        ]);
        final next = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: true, weight: 0, reps: 8)],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: previous,
          next: next,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Set now'), findsOneWidget);

        await tester.tap(find.text('Set now'));
        // Modal sheet enter animation.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(BodyweightEditorSheet),
          findsOneWidget,
          reason:
              'Phase 24c-8: tapping `Set now` must deep-link into the same '
              'BodyweightEditorSheet the profile-settings row uses '
              '(reuse contract per 24c-7 + spec).',
        );
      },
    );

    testWidgets(
      'should persist the Hive dismissal flag and never prompt again when '
      'the user taps Skip',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const Profile(id: 'u1', bodyweightKg: null),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Pre-condition: flag is unset.
        expect(
          container.read(bodyweightPromptDismissalProvider),
          isFalse,
          reason: 'Hive flag must be unset at the start of the test.',
        );

        final harness = await _pumpHarness(tester, container: container);

        final previous = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: false, weight: 0, reps: 8)],
          ),
        ]);
        final next = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: true, weight: 0, reps: 8)],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: previous,
          next: next,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Skip'), findsOneWidget);

        // Tap Skip — fires `markDismissed()` (async `Hive.box.put`)
        // which completes on Dart's real event loop, NOT the fake_async
        // the testWidgets zone runs in. The whole tap + pump cycle must
        // therefore run inside `tester.runAsync` so the pending Hive
        // I/O future isn't tracked by the test zone (otherwise the test
        // never reports complete and times out at 10 minutes). See the
        // saga_intro_gate test's `_pumpGate` for the canonical pattern,
        // and the cluster `feedback_hive_testwidgets`.
        await tester.runAsync(() async {
          await tester.tap(find.text('Skip'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });

        // Behaviour assertion: the dismissal flag is now set in Hive.
        // We re-read via a brand-new ProviderContainer to verify the
        // Hive write actually committed to disk (the notifier reads
        // from the box on every fresh `build()`). A NEW container
        // simulates "a future app launch" — same Hive directory, but
        // no in-memory state carries over.
        final freshContainer = ProviderContainer();
        addTearDown(freshContainer.dispose);
        expect(
          freshContainer.read(bodyweightPromptDismissalProvider),
          isTrue,
          reason:
              'Phase 24c-8: tapping Skip must persist the dismissal '
              'timestamp into user_prefs so a future container (= a '
              'future app launch) reads it as dismissed.',
        );

        // Coverage of the "future coordinator instance with dismissed=true
        // does NOT show the prompt" path is already pinned by the
        // dedicated `should NOT show the prompt across sessions...`
        // gating test above (which seeds the Hive flag pre-mount and
        // verifies the prompt never appears). Re-verifying that branch
        // here would require a second harness mount inside the same
        // test — fragile under the SnackBar's 6s TweenAnimationBuilder
        // (it makes pumpAndSettle hang) and offers no marginal coverage.
      },
    );

    testWidgets(
      'should NOT show the prompt on subsequent sets in the same session '
      'after the user saves a bodyweight value via Set now',
      (tester) async {
        // Two phases of profile state: starts null, becomes 70kg after
        // the user saves. We swap the AsyncNotifier mid-test by
        // invalidating the provider. Simpler than threading a mutable
        // state into the fake.
        var current = const Profile(id: 'u1', bodyweightKg: null);

        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(() {
              return _FakeProfileNotifier(current);
            }),
          ],
        );
        addTearDown(container.dispose);

        final harness = await _pumpHarness(tester, container: container);

        // First completion → prompt shows.
        final s0 = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [
              (setNumber: 1, completed: false, weight: 0, reps: 8),
              (setNumber: 2, completed: false, weight: 0, reps: 8),
            ],
          ),
        ]);
        final s1 = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [
              (setNumber: 1, completed: true, weight: 0, reps: 8),
              (setNumber: 2, completed: false, weight: 0, reps: 8),
            ],
          ),
        ]);

        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: s0,
          next: s1,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Set your body weight for accurate XP'),
          findsOneWidget,
        );

        // Simulate the bottom-sheet save: profile flips to 70 kg AND the
        // session-shot already flipped on first show. We update `current`
        // and invalidate the provider so subsequent reads see 70.0.
        current = const Profile(id: 'u1', bodyweightKg: 70.0);
        container.invalidate(profileProvider);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Dismiss the first snack so a second wouldn't be hidden behind
        // the messenger queue.
        ScaffoldMessenger.of(harness.ctx).hideCurrentSnackBar();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Second qualifying completion in the same session.
        final s2 = _state([
          _exerciseEntry(
            exercise: _pullUp,
            sets: [
              (setNumber: 1, completed: true, weight: 0, reps: 8),
              (setNumber: 2, completed: true, weight: 0, reps: 8),
            ],
          ),
        ]);
        harness.coord.maybeShow(
          context: harness.ctx,
          ref: harness.ref,
          previous: s1,
          next: s2,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text('Set your body weight for accurate XP'),
          findsNothing,
          reason:
              'Phase 24c-8: once the profile has bodyweightKg set, the '
              'profile-gate short-circuits the prompt regardless of the '
              'session-shot flag — defence in depth.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Production-wiring regression guard (cluster_inherited_widget_context_above_scope)
  // ---------------------------------------------------------------------------
  //
  // **Why this group exists.** The "gating behaviour" + "actions" groups above
  // drive the coordinator directly via a synthetic in-scope context. They
  // pin the coordinator's CONTRACT (which gates fire, which actions run),
  // but they don't pin the WIRING SHAPE — i.e. they would all pass even if
  // the production screen passed a context ABOVE
  // `SnackBarTapOutDismissScope` to the coordinator's `maybeShow`, in which
  // case `SnackBarTapOutDismissScope.maybeOf(context)` returns null and
  // every prompt fire silently no-ops (the defensive branch at the top of
  // `_showPromptSnackBar` swallows it).
  //
  // The Phase 24c bug fix #2 (2026-05-15) cause was exactly that: the
  // `ref.listen` lived at `_ActiveWorkoutScreenState.build`, which is the
  // ANCESTOR of `SnackBarTapOutDismissScope`. Inherited-widget lookups
  // walk UP only, so the scope was unreachable. Moving the listener into
  // `_ActiveWorkoutBody.build` (a descendant of the scope) restored the
  // contract.
  //
  // This test mounts the FULL `ActiveWorkoutScreen` and asserts that
  // completing a qualifying set surfaces the SnackBar. If a future refactor
  // moves the listener back above the scope, or hoists the scope below the
  // listener, this test fails BEFORE the e2e suite catches it.
  group('BodyweightPromptCoordinator — production wiring (regression guard)', () {
    setUpAll(() {
      registerFallbackValue(_FakeActiveWorkoutState());
    });

    testWidgets('should fire the bodyweight prompt via the production ref.listen '
        'wiring (mounts the full ActiveWorkoutScreen so the listener context '
        'must be a descendant of SnackBarTapOutDismissScope)', (tester) async {
      // Build a state that already contains a Pull-Up exercise with one
      // un-completed set — the test then drives `completeSet` to flip
      // it to completed, which is the production path the coordinator
      // listens for via the diff in `maybeShow`.
      final preCompletionState = ActiveWorkoutState(
        workout: _workout(),
        exercises: [
          _exerciseEntry(
            exercise: _pullUp,
            sets: [(setNumber: 1, completed: false, weight: 0, reps: 8)],
            workoutExerciseId: 'we-pullup-prod',
          ),
        ],
      );

      final mockRepo = _MockWorkoutRepository();
      final mockStorage = _MockWorkoutLocalStorage();

      // The notifier's `build()` calls `_localStorage.loadActiveWorkout()`.
      // Returning the pre-completion state seeds the AsyncData<state>
      // immediately, so the screen mounts with the Pull-Up card visible
      // and we can drive `completeSet` from the test container.
      when(
        () => mockStorage.loadActiveWorkout(),
      ).thenReturn(preCompletionState);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      final container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
          restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
          // Profile must have bodyweightKg=null for the prompt to fire.
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(
              const Profile(id: 'u1', bodyweightKg: null),
            ),
          ),
          exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
          lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
          elapsedTimerProvider.overrideWith(
            (ref, startedAt) => Stream.value(const Duration(minutes: 5)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestMaterialApp(home: ActiveWorkoutScreen()),
        ),
      );
      // Two pumps drain the AsyncNotifier microtasks (build → AsyncData)
      // and let the screen render the Pull-Up card.
      await tester.pump();
      await tester.pump();

      // Sanity: the screen mounted the body (and therefore the
      // SnackBarTapOutDismissScope) — there should be a Scaffold visible.
      expect(find.byType(Scaffold), findsWidgets);

      // Drive a set completion via the notifier — this is the EXACT
      // production path: SetRow → notifier.completeSet → state mutation
      // → ref.listen fires → coordinator.maybeShow → snack visible.
      await container
          .read(activeWorkoutProvider.notifier)
          .completeSet('we-pullup-prod', 'we-pullup-prod-set-1');
      // Pump twice: first lets the notifier emit AsyncData, second lets
      // the snack's enter animation start. Then jump 400ms for the
      // entrance animation to settle without pumpAndSettle (which would
      // hang on the 6-second TweenAnimationBuilder countdown).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Set your body weight for accurate XP'),
        findsOneWidget,
        reason:
            'Phase 24c bug fix #2 (cluster_inherited_widget_context_above_scope): '
            'completing a uses_bodyweight_load set on a profile with '
            'bodyweightKg=null MUST surface the prompt SnackBar through '
            'the production ref.listen wiring. If this fails, the '
            'listener context is no longer a descendant of '
            'SnackBarTapOutDismissScope (or the scope no longer wraps '
            'the body), so `SnackBarTapOutDismissScope.maybeOf(context)` '
            'returns null and the coordinator silently swallows the fire. '
            'See active_workout_screen.dart `_ActiveWorkoutBodyState.build` '
            'for the correct wiring shape.',
      );
      expect(find.text('Set now'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Fakes / mocks for the production-wiring regression guard
// ---------------------------------------------------------------------------

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class _FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

class _NullRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  @override
  RestTimerState? build() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
