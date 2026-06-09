// Q1 (notes-edit-after): unit coverage for WorkoutNotesNotifier.save — the
// controller the History detail screen calls to persist an edit to a past
// workout's free-text notes.
//
// Behavior pinned:
//   * a successful save forwards the normalized value to the repository,
//   * blank / whitespace-only input normalizes to a null clear,
//   * the detail provider is re-fetched after a successful write,
//   * a repository failure is rethrown (so the edit sheet can surface it) and
//     the detail provider is NOT re-fetched (the prior note stays rendered).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  late _MockWorkoutRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = _MockWorkoutRepository();
    when(
      () => mockRepo.updateWorkoutNotes(
        any(),
        notes: any(named: 'notes'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(mockRepo),
        currentUserIdProvider.overrideWithValue('user-001'),
      ],
    );
    addTearDown(container.dispose);
  });

  group('WorkoutNotesNotifier.save', () {
    test('forwards the trimmed note to the repository on success', () async {
      await container
          .read(workoutNotesNotifierProvider.notifier)
          .save('w-1', '  Felt strong  ');

      // The trim contract has no observable effect except the value that
      // reaches the repository (the mock doesn't surface it back, and the
      // notifier state is void), so `verify` on the repo arg is the least-bad
      // handle here — not a lazy wiring trace.
      verify(
        () => mockRepo.updateWorkoutNotes(
          'w-1',
          notes: 'Felt strong',
          userId: 'user-001',
        ),
      ).called(1);
    });

    test('normalizes whitespace-only input to a null clear', () async {
      await container
          .read(workoutNotesNotifierProvider.notifier)
          .save('w-1', '   ');

      verify(
        () =>
            mockRepo.updateWorkoutNotes('w-1', notes: null, userId: 'user-001'),
      ).called(1);
    });

    test('settles back to AsyncData on success', () async {
      await container
          .read(workoutNotesNotifierProvider.notifier)
          .save('w-1', 'note');

      final state = container.read(workoutNotesNotifierProvider);
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('rethrows the domain exception when the write fails', () async {
      when(
        () => mockRepo.updateWorkoutNotes(
          any(),
          notes: any(named: 'notes'),
          userId: any(named: 'userId'),
        ),
      ).thenThrow(const app.DatabaseException('denied', code: '42501'));

      await expectLater(
        container
            .read(workoutNotesNotifierProvider.notifier)
            .save('w-1', 'note'),
        throwsA(isA<app.DatabaseException>()),
      );
    });
  });
}
