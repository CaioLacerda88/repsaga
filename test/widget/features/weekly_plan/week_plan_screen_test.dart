/// Widget tests for [WeekPlanScreen] (Phase 26e rewrite).
///
/// Covers the four contract pins from `docs/phase-26e-plan.md` Task 10:
///   1. Counter pill shows "N dias treinados" — same-day completions
///      collapse to one day.
///   2. Counter pill counts two different completion days as 2.
///   3. "+ Adicionar treino" CTA opens the AddRoutinesSheet.
///   4. Soft-cap warning text appears only when bucket strictly exceeds
///      `trainingFrequencyPerWeek`.
///   5. The ⓘ icon on EngajamentoSection opens the explainer sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/domain/weekly_engagement.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_engagement_provider.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/weekly_plan/ui/add_routines_sheet.dart';
import 'package:repsaga/features/weekly_plan/ui/week_plan_screen.dart';
import 'package:repsaga/features/weekly_plan/ui/widgets/engagement_explainer_sheet.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';

import '../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _WeeklyPlanStub extends AsyncNotifier<WeeklyPlan?>
    implements WeeklyPlanNotifier {
  _WeeklyPlanStub(this.plan);
  final WeeklyPlan? plan;

  @override
  Future<WeeklyPlan?> build() async => plan;

  @override
  Future<void> upsertPlan(List<BucketRoutine> routines) async {}

  @override
  Future<void> clearPlan() async {}

  @override
  // ignore: must_call_super
  dynamic noSuchMethod(Invocation invocation) {}
}

class _RoutineListStub extends AsyncNotifier<List<Routine>>
    implements RoutineListNotifier {
  _RoutineListStub(this.routines);
  final List<Routine> routines;

  @override
  Future<List<Routine>> build() async => routines;

  @override
  // ignore: must_call_super
  dynamic noSuchMethod(Invocation invocation) {}
}

class _ProfileStub extends AsyncNotifier<Profile?> implements ProfileNotifier {
  _ProfileStub(this.frequency);
  final int frequency;

  @override
  Future<Profile?> build() async => Profile(
    id: 'user-001',
    displayName: 'Test',
    weightUnit: 'kg',
    trainingFrequencyPerWeek: frequency,
  );

  @override
  // ignore: must_call_super
  dynamic noSuchMethod(Invocation invocation) {}
}

class _EmptyHistoryNotifier extends AsyncNotifier<List<Workout>>
    implements WorkoutHistoryNotifier {
  @override
  Future<List<Workout>> build() async => [];

  @override
  bool get hasMore => false;

  @override
  bool get isLoadingMore => false;

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  const _FakeAnalyticsRepository();

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {}
}

// ---------------------------------------------------------------------------
// Factories
// ---------------------------------------------------------------------------

Routine _routine({String id = 'r-001', String name = 'Push Day'}) {
  return Routine(
    id: id,
    name: name,
    isDefault: false,
    exercises: const [],
    createdAt: DateTime(2026),
  );
}

BucketRoutine _bucket({
  required String routineId,
  required int order,
  String? completedWorkoutId,
  DateTime? completedAt,
  bool isSpontaneous = false,
}) {
  return BucketRoutine(
    routineId: routineId,
    order: order,
    completedWorkoutId: completedWorkoutId,
    completedAt: completedAt,
    isSpontaneous: isSpontaneous,
  );
}

WeeklyPlan _plan({List<BucketRoutine> routines = const []}) {
  return WeeklyPlan(
    id: 'plan-001',
    userId: 'user-001',
    weekStart: DateTime(2026, 4, 6),
    routines: routines,
    createdAt: DateTime(2026, 4, 6),
    updatedAt: DateTime(2026, 4, 6),
  );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _build({
  required WeeklyPlan? plan,
  required List<Routine> routines,
  int trainingFrequency = 3,
}) {
  final mockAuth = _MockAuthRepository();
  when(() => mockAuth.currentUser).thenReturn(null);

  return ProviderScope(
    overrides: [
      weeklyPlanProvider.overrideWith(() => _WeeklyPlanStub(plan)),
      routineListProvider.overrideWith(() => _RoutineListStub(routines)),
      profileProvider.overrideWith(() => _ProfileStub(trainingFrequency)),
      workoutHistoryProvider.overrideWith(() => _EmptyHistoryNotifier()),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
      // weeklyEngagementProvider hits Supabase — override to a deterministic
      // empty engagement so the screen renders the section without network.
      weeklyEngagementProvider(
        const WeeklyEngagementArgs(includePlanned: true),
      ).overrideWith((_) async => WeeklyEngagement.empty),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Consumer(
        builder: (context, ref, _) {
          ref.watch(workoutHistoryProvider);
          return const WeekPlanScreen();
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WeekPlanScreen counter pill', () {
    testWidgets(
      'should show N days trained counter for unique completion dates',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Three bucket entries, two completed on 2026-04-08 (same day),
        // one not completed → counter should read "1 day trained".
        final completion = DateTime(2026, 4, 8, 18, 30);
        final routines = [
          _routine(id: 'r-001', name: 'Push Day'),
          _routine(id: 'r-002', name: 'Pull Day'),
          _routine(id: 'r-003', name: 'Leg Day'),
        ];
        final plan = _plan(
          routines: [
            _bucket(
              routineId: 'r-001',
              order: 1,
              completedWorkoutId: 'w-1',
              completedAt: completion,
            ),
            _bucket(
              routineId: 'r-002',
              order: 2,
              completedWorkoutId: 'w-2',
              completedAt: completion.add(const Duration(hours: 2)),
            ),
            _bucket(routineId: 'r-003', order: 3),
          ],
        );

        await tester.pumpWidget(
          _build(plan: plan, routines: routines, trainingFrequency: 3),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('1 day trained'),
          findsOneWidget,
          reason:
              'Two completions on the same calendar day must collapse into 1.',
        );
      },
    );

    testWidgets('should count two different completion days as 2', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final routines = [
        _routine(id: 'r-001', name: 'Push Day'),
        _routine(id: 'r-002', name: 'Pull Day'),
      ];
      final plan = _plan(
        routines: [
          _bucket(
            routineId: 'r-001',
            order: 1,
            completedWorkoutId: 'w-1',
            completedAt: DateTime(2026, 4, 7, 10),
          ),
          _bucket(
            routineId: 'r-002',
            order: 2,
            completedWorkoutId: 'w-2',
            completedAt: DateTime(2026, 4, 9, 18),
          ),
        ],
      );

      await tester.pumpWidget(
        _build(plan: plan, routines: routines, trainingFrequency: 3),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2 days trained'),
        findsOneWidget,
        reason: 'Two distinct calendar days must count as 2.',
      );
    });
  });

  group('WeekPlanScreen "+ Add workout" CTA', () {
    testWidgets('should open AddRoutinesSheet when "+ Add workout" is tapped', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final routines = [_routine(id: 'r-001', name: 'Push Day')];
      final plan = _plan();

      await tester.pumpWidget(
        _build(plan: plan, routines: routines, trainingFrequency: 3),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ Add workout'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AddRoutinesSheet),
        findsOneWidget,
        reason: '"+ Add workout" tap must open the AddRoutinesSheet.',
      );
    });

    testWidgets('should show soft-cap warning when bucket count exceeds '
        'trainingFrequencyPerWeek', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Training frequency = 2, bucket has 3 routines → over cap.
      final routines = [
        _routine(id: 'r-001', name: 'Push Day'),
        _routine(id: 'r-002', name: 'Pull Day'),
        _routine(id: 'r-003', name: 'Leg Day'),
      ];
      final plan = _plan(
        routines: [
          _bucket(routineId: 'r-001', order: 1),
          _bucket(routineId: 'r-002', order: 2),
          _bucket(routineId: 'r-003', order: 3),
        ],
      );

      await tester.pumpWidget(
        _build(plan: plan, routines: routines, trainingFrequency: 2),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('weekly limit of 2'),
        findsOneWidget,
        reason:
            'Soft-cap warning must surface the user\'s configured weekly '
            'limit when the bucket overshoots it.',
      );
    });

    testWidgets('should NOT show soft-cap warning at exact cap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // bucket size == trainingFrequency → at cap, NOT over → no warning.
      final routines = [
        _routine(id: 'r-001', name: 'Push Day'),
        _routine(id: 'r-002', name: 'Pull Day'),
      ];
      final plan = _plan(
        routines: [
          _bucket(routineId: 'r-001', order: 1),
          _bucket(routineId: 'r-002', order: 2),
        ],
      );

      await tester.pumpWidget(
        _build(plan: plan, routines: routines, trainingFrequency: 2),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('weekly limit'),
        findsNothing,
        reason:
            'At-cap is the normal steady state — only OVER-cap shows the '
            'soft-cap warning.',
      );
    });
  });

  group('WeekPlanScreen Engajamento info icon', () {
    testWidgets(
      'should open the engagement explainer sheet when the info icon is '
      'tapped',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final routines = [_routine(id: 'r-001', name: 'Push Day')];
        final plan = _plan();

        await tester.pumpWidget(
          _build(plan: plan, routines: routines, trainingFrequency: 3),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('engagement-info-icon')));
        await tester.pumpAndSettle();

        expect(
          find.byType(EngagementExplainerSheet),
          findsOneWidget,
          reason:
              'Tapping the ⓘ icon on EngajamentoSection must open the '
              'engagement-explainer bottom sheet.',
        );
        // Title pin — copy comes from the en ARB.
        expect(find.text('How we count sets'), findsOneWidget);
      },
    );
  });
}
