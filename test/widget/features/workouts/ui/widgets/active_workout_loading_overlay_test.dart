// Loading overlay Cancel-from-t=0 contract (PR1 — Q1).
//
// Pre-PR1 the overlay hid the Cancel button behind a 10s timer AND a
// `hasRestorable` boolean gate. The user had no escape during the start
// phase (because there was no restorable state to revert to) and had to
// wait 10s before the button appeared during finish/discard. After PR1's
// C4 fix to cancelLoading, both gates become obsolete:
//
//   - cancelLoading() now ALWAYS does something useful: restore the prior
//     state if there is one, otherwise emit AsyncData(null) so the screen
//     navigates to /home. There is no scenario where the button is a no-op.
//   - The 10s timer pushed users into resigning fast saves on slow
//     networks (premature reveal) AND trapped them on the spinner during
//     the first 10s of a stuck network (delayed reveal). Both directions
//     are user-hostile; rendering the affordance immediately matches the
//     simpler, predictable mental model.
//
// New contract:
//   - At t=0 the overlay shows BOTH a CircularProgressIndicator AND a
//     Cancel button.
//   - Tapping Cancel calls `notifier.cancelLoading()`.
//   - No `hasRestorable` parameter exists — the overlay is a
//     ConsumerWidget with no internal state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/active_workout_loading_overlay.dart';

import '../../../../../helpers/test_material_app.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class _FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

Widget _buildOverlayHarness() {
  final mockRepo = _MockWorkoutRepository();
  final mockStorage = _MockWorkoutLocalStorage();
  when(() => mockStorage.loadActiveWorkout()).thenReturn(null);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

  return ProviderScope(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: ActiveWorkoutLoadingOverlay()),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeActiveWorkoutState());
  });

  group(
    'ActiveWorkoutLoadingOverlay — Cancel-from-t=0 contract (PR1 — Q1)',
    () {
      testWidgets('at t=0 shows BOTH the spinner AND the cancel button', (
        tester,
      ) async {
        await tester.pumpWidget(_buildOverlayHarness());

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.byType(TextButton),
          findsOneWidget,
          reason:
              'Cancel must be visible immediately on mount — no 10s timer, no '
              'hasRestorable gate. cancelLoading() always does something '
              'useful, so the button always has a meaningful action to take.',
        );
      });

      testWidgets(
        'tapping cancel calls notifier.cancelLoading() and the notifier '
        'settles into AsyncData (not AsyncLoading)',
        (tester) async {
          final mockRepo = _MockWorkoutRepository();
          final mockStorage = _MockWorkoutLocalStorage();
          when(() => mockStorage.loadActiveWorkout()).thenReturn(null);
          when(
            () => mockStorage.saveActiveWorkout(any()),
          ).thenAnswer((_) async {});

          final container = ProviderContainer(
            overrides: [
              workoutRepositoryProvider.overrideWithValue(mockRepo),
              workoutLocalStorageProvider.overrideWithValue(mockStorage),
            ],
          );
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: TestMaterialApp(
                theme: AppTheme.dark,
                home: const Scaffold(body: ActiveWorkoutLoadingOverlay()),
              ),
            ),
          );

          final cancelFinder = find.byType(TextButton);
          expect(cancelFinder, findsOneWidget);

          await tester.tap(cancelFinder);
          await tester.pump();

          // Pin: state is settled AsyncData (not AsyncLoading, not AsyncError)
          // after the tap. With `_lastValidState == null`, cancelLoading()
          // emits AsyncData(null) — the C4 fix that makes this widget's
          // simplification safe.
          final state = container.read(activeWorkoutProvider);
          expect(
            state,
            isA<AsyncData<ActiveWorkoutState?>>(),
            reason:
                'cancelLoading() must leave the notifier in AsyncData so the '
                'screen redirect fires — leaving AsyncLoading would trap the '
                'user on the spinner.',
          );
          expect(state.value, isNull);
        },
      );

      testWidgets('overlay is a ConsumerWidget with no internal timer state', (
        tester,
      ) async {
        // Sanity check: the overlay should be stateless (ConsumerWidget),
        // not ConsumerStatefulWidget. A future refactor that re-introduces
        // a timer would be a step backward — pin the simpler shape.
        await tester.pumpWidget(_buildOverlayHarness());
        final widget = tester.widget<ActiveWorkoutLoadingOverlay>(
          find.byType(ActiveWorkoutLoadingOverlay),
        );
        expect(widget, isA<ConsumerWidget>());
      });
    },
  );
}
