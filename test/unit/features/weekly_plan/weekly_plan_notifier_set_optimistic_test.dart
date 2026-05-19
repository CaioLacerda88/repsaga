/// Pins the synchronous-state-update contract on
/// [WeeklyPlanNotifier.setOptimistic].
///
/// The plan editor calls this immediately on every local edit so dependent
/// providers ([weeklyEngagementProvider], Home bucket chips, etc.) — all of
/// which `ref.watch(weeklyPlanProvider)` — see the new bucket on the next
/// frame, instead of waiting the 300ms debounce + Supabase roundtrip for
/// [WeeklyPlanNotifier.upsertPlan] to publish the persisted plan. Without
/// this, the user adds a routine and the engagement bars don't react for
/// 400-800ms — visible "freeze" the user reported during L13.4 device QA.
///
/// Behavior pinned here:
///   * Calling `setOptimistic(routines)` while a plan is already cached
///     replaces only the `routines` field via `copyWith` — `id`, `userId`,
///     `weekStart` are preserved so the engagement provider's downstream
///     lookups (which key off `routineId`, not `plan.id`) stay stable.
///   * Calling `setOptimistic(routines)` with a null plan (no row exists
///     yet this week) publishes a synthetic plan with a placeholder `id`,
///     so the engagement provider has something to walk. The actual
///     persisted `id` arrives from Supabase on the next `upsertPlan`.
///   * The update happens synchronously — `state.value` reflects the new
///     routines the very next line. No async hop, no scheduler dance.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/data/weekly_plan_repository.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockWeeklyPlanRepository extends Mock implements WeeklyPlanRepository {}

const _fakeUser = User(
  id: 'user-001',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

WeeklyPlan _plan({String id = 'plan-001', List<String> routineIds = const []}) {
  return WeeklyPlan(
    id: id,
    userId: 'user-001',
    weekStart: DateTime(2026, 5, 18),
    routines: routineIds
        .asMap()
        .entries
        .map((e) => BucketRoutine(routineId: e.value, order: e.key + 1))
        .toList(),
    createdAt: DateTime(2026, 5, 18),
    updatedAt: DateTime(2026, 5, 18),
  );
}

ProviderContainer _container({
  required _MockAuthRepository mockAuth,
  required _MockWeeklyPlanRepository mockRepo,
}) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(mockAuth),
      weeklyPlanRepositoryProvider.overrideWithValue(mockRepo),
    ],
  );
}

void main() {
  group('WeeklyPlanNotifier.setOptimistic', () {
    late _MockAuthRepository mockAuth;
    late _MockWeeklyPlanRepository mockRepo;

    setUp(() {
      mockAuth = _MockAuthRepository();
      mockRepo = _MockWeeklyPlanRepository();
      when(() => mockAuth.currentUser).thenReturn(_fakeUser);
    });

    test('preserves id/userId/weekStart and overwrites routines when a '
        'plan already exists', () async {
      // Seed: notifier resolves to a plan with one routine.
      when(
        () => mockRepo.getPlanForWeek(any(), any()),
      ).thenAnswer((_) async => _plan(routineIds: ['r1']));

      final container = _container(mockAuth: mockAuth, mockRepo: mockRepo);
      addTearDown(container.dispose);

      // Force build, await initial fetch.
      await container.read(weeklyPlanProvider.future);
      final before = container.read(weeklyPlanProvider).value!;
      expect(before.id, 'plan-001');
      expect(before.routines.map((r) => r.routineId), ['r1']);

      // Local edit: bucket grows to [r1, r2, r3].
      container.read(weeklyPlanProvider.notifier).setOptimistic([
        const BucketRoutine(routineId: 'r1', order: 1),
        const BucketRoutine(routineId: 'r2', order: 2),
        const BucketRoutine(routineId: 'r3', order: 3),
      ]);

      // State updates SYNCHRONOUSLY — no await between setOptimistic and
      // the assertion. The engagement provider's ref.watch fires on the
      // same microtask, so dependent rebuilds happen this frame, not
      // after the 300ms debounce + network.
      final after = container.read(weeklyPlanProvider).value!;
      expect(after.id, 'plan-001', reason: 'plan id must be preserved');
      expect(after.userId, 'user-001');
      expect(after.weekStart, DateTime(2026, 5, 18));
      expect(after.routines.map((r) => r.routineId), ['r1', 'r2', 'r3']);
    });

    test('publishes a synthetic plan with a placeholder id when no plan '
        'exists yet this week', () async {
      // Seed: getPlanForWeek returns null → notifier sees no plan.
      when(
        () => mockRepo.getPlanForWeek(any(), any()),
      ).thenAnswer((_) async => null);
      // The notifier's build() schedules a microtask-time
      // `_tryAutoPopulate`; stub it to a quiet failure so the test
      // doesn't see surprise state mutations from auto-populate.
      when(
        () => mockRepo.getPreviousWeekPlan(any(), any()),
      ).thenAnswer((_) async => null);

      final container = _container(mockAuth: mockAuth, mockRepo: mockRepo);
      addTearDown(container.dispose);

      await container.read(weeklyPlanProvider.future);
      expect(container.read(weeklyPlanProvider).value, isNull);

      container.read(weeklyPlanProvider.notifier).setOptimistic([
        const BucketRoutine(routineId: 'r1', order: 1),
      ]);

      final after = container.read(weeklyPlanProvider).value;
      expect(after, isNotNull);
      expect(after!.routines.map((r) => r.routineId), ['r1']);
      expect(
        after.id,
        startsWith('optimistic-'),
        reason:
            'A no-plan-yet edit publishes a synthetic plan with a '
            'placeholder id so the engagement provider has something to '
            'walk. The real id arrives from Supabase on the next upsert.',
      );
    });

    test(
      'is a no-op when no user is authenticated and no plan is cached',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);
        when(
          () => mockRepo.getPlanForWeek(any(), any()),
        ).thenAnswer((_) async => null);

        final container = _container(mockAuth: mockAuth, mockRepo: mockRepo);
        addTearDown(container.dispose);

        await container.read(weeklyPlanProvider.future);
        expect(container.read(weeklyPlanProvider).value, isNull);

        container.read(weeklyPlanProvider.notifier).setOptimistic([
          const BucketRoutine(routineId: 'r1', order: 1),
        ]);

        // Signed-out edge case: nothing to write a plan against. Silently
        // ignore rather than synthesize a plan with a fake userId — the
        // editor is unreachable in this state anyway (the route guard
        // sends signed-out users to /login).
        expect(container.read(weeklyPlanProvider).value, isNull);
      },
    );
  });
}
