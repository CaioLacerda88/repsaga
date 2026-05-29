/// Tests for the routines surface on HomeScreen.
///
/// Two day-0 surfaces live below `ActionHero` in the `_HomeRoutinesList`:
///   * **MY ROUTINES** — populated when the user has created custom routines
///     (truncated to 3 + "See all" pill), shown only when there's no active
///     weekly plan.
///   * **Starter Routines** (Phase 27 L3) — when the user has zero custom
///     routines, the seeded default routines render as a tappable preview so
///     day-0 users can start lifting without filling out the
///     routine-builder. Tapping a card starts a workout for that default
///     (mirrors the populated-list card behavior — no auto-create-routine).
///
/// Starter routines moved to /routines in W8 (see
/// `routine_list_screen_test.dart`). What's on HOME is the lightweight
/// preview added in 27 L3 — same `RoutineCard` style as the populated case,
/// no divider, no chevron, no header icon.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/routines/ui/widgets/routine_card.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/core/offline/pending_sync_provider.dart';
import 'package:repsaga/features/workouts/ui/home_screen.dart';
import 'package:repsaga/l10n/app_localizations.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _RoutineStub extends AsyncNotifier<List<Routine>>
    implements RoutineListNotifier {
  _RoutineStub(this.routines);
  final List<Routine> routines;

  @override
  Future<List<Routine>> build() async => routines;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryStub extends AsyncNotifier<WorkoutHistoryState>
    implements WorkoutHistoryNotifier {
  _HistoryStub(this.workouts);
  final List<Workout> workouts;

  @override
  Future<WorkoutHistoryState> build() async =>
      (workouts: workouts, isLoadingMore: false, hasMore: false);

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

class _NullActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  @override
  Future<ActiveWorkoutState?> build() async => null;

  /// No-op so `startRoutineWorkout`'s `await ...startFromRoutine(...)` does
  /// not explode on NoSuchMethodError when a `_DefaultRoutinesPreview` card
  /// tap test wants to assert post-start navigation. Mirrors the pattern in
  /// `home_screen_action_hero_test.dart`.
  @override
  Future<void> startFromRoutine(RoutineStartConfig config) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanStub extends AsyncNotifier<WeeklyPlan?>
    implements WeeklyPlanNotifier {
  _PlanStub(this.plan);
  final WeeklyPlan? plan;

  @override
  Future<WeeklyPlan?> build() async => plan;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileStub extends AsyncNotifier<Profile?> implements ProfileNotifier {
  @override
  Future<Profile?> build() async =>
      const Profile(id: 'user-001', displayName: 'Alex', weightUnit: 'kg');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ZeroPendingSyncNotifier extends PendingSyncNotifier {
  @override
  int build() => 0;
}

/// PR 32g — `weeklyPlanNeedsConfirmationProvider` migrated from
/// `StateProvider<bool>` to a Hive-backed `NotifierProvider<...,bool>`.
class _NeedsConfirmationStub extends WeeklyPlanNeedsConfirmationNotifier {
  _NeedsConfirmationStub(this._value);
  final bool _value;

  @override
  bool build() => _value;

  @override
  Future<void> set(bool value) async {
    state = value;
  }
}

// ---------------------------------------------------------------------------
// Factories
// ---------------------------------------------------------------------------

Routine _routine({
  required String id,
  required String name,
  bool isDefault = false,
  String? userId,
}) => Routine(
  id: id,
  name: name,
  userId: userId,
  isDefault: isDefault,
  exercises: const [],
  createdAt: DateTime(2026),
);

/// A routine whose single exercise has a resolved (non-null, non-deleted)
/// [Exercise] so `startRoutineWorkout` proceeds through to
/// `context.go('/workout/active')` rather than tripping the
/// empty-exercises snackbar guard. Used by the starter-card tap-nav test.
Routine _defaultRoutineWithExercise({
  required String id,
  required String name,
}) {
  final exerciseJson = TestExerciseFactory.create(
    id: 'ex-$id',
    name: 'Bench Press',
    equipmentType: 'barbell',
  );
  final routineJson = TestRoutineFactory.create(
    id: id,
    name: name,
    userId: null,
    isDefault: true,
    exercises: [
      TestRoutineExerciseFactory.create(
        exerciseId: 'ex-$id',
        exercise: exerciseJson,
      ),
    ],
  );
  return Routine.fromJson(routineJson);
}

BucketRoutine _bucket({required String routineId, required int order}) =>
    BucketRoutine(routineId: routineId, order: order);

WeeklyPlan _plan({required List<BucketRoutine> routines}) => WeeklyPlan(
  id: 'plan-001',
  userId: 'user-001',
  weekStart: DateTime(2026, 4, 13),
  routines: routines,
  createdAt: DateTime(2026, 4, 13),
  updatedAt: DateTime(2026, 4, 13),
);

Workout _workout() => Workout.fromJson(
  TestWorkoutFactory.create(finishedAt: '2026-04-10T10:00:00Z'),
);

Widget _build({
  required List<Routine> routines,
  WeeklyPlan? plan,
  List<Workout> workouts = const [],
  int workoutCount = 0,
}) {
  return ProviderScope(
    overrides: [
      routineListProvider.overrideWith(() => _RoutineStub(routines)),
      workoutHistoryProvider.overrideWith(() => _HistoryStub(workouts)),
      activeWorkoutProvider.overrideWith(() => _NullActiveWorkoutNotifier()),
      weeklyPlanProvider.overrideWith(() => _PlanStub(plan)),
      weeklyPlanNeedsConfirmationProvider.overrideWith(
        () => _NeedsConfirmationStub(false),
      ),
      workoutCountProvider.overrideWith((ref) => Future.value(workoutCount)),
      profileProvider.overrideWith(() => _ProfileStub()),
      pendingSyncProvider.overrideWith(() => _ZeroPendingSyncNotifier()),
      // HomeGreeting (Phase 27 L2) reads `currentUserEmailProvider` for its
      // displayName-fallback. Seed a stable value so the greeting always
      // renders the profile's `displayName` and doesn't crash on a missing
      // auth subgraph.
      currentUserEmailProvider.overrideWithValue('test@repsaga.test'),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: HomeScreen()),
    ),
  );
}

/// Router-based harness for tests that need to assert post-tap navigation
/// (e.g. starter-card tap → `/workout/active`). Uses `MaterialApp.router`
/// because the populated-list / starter-card tap path calls
/// `startRoutineWorkout`, which finishes with `context.go('/workout/active')`.
///
/// `Consumer` around `HomeScreen` silently watches `activeWorkoutProvider`
/// so the seeded AsyncNotifier actually builds + commits its initial state
/// before the tap — otherwise `ref.read(activeWorkoutProvider).value` reads
/// a null `AsyncLoading` and the resume dialog never appears (mirrors the
/// existing `home_screen_action_hero_test.dart` harness pattern).
Widget _buildWithRouter({
  required List<Routine> routines,
  WeeklyPlan? plan,
  List<Workout> workouts = const [],
  int workoutCount = 0,
  ValueChanged<String>? onRoute,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(activeWorkoutProvider);
              return const HomeScreen();
            },
          ),
        ),
      ),
      GoRoute(
        path: '/workout/active',
        pageBuilder: (ctx, state) {
          onRoute?.call('/workout/active');
          return const NoTransitionPage(
            child: Scaffold(body: Text('Active Workout Screen')),
          );
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      routineListProvider.overrideWith(() => _RoutineStub(routines)),
      workoutHistoryProvider.overrideWith(() => _HistoryStub(workouts)),
      activeWorkoutProvider.overrideWith(() => _NullActiveWorkoutNotifier()),
      weeklyPlanProvider.overrideWith(() => _PlanStub(plan)),
      weeklyPlanNeedsConfirmationProvider.overrideWith(
        () => _NeedsConfirmationStub(false),
      ),
      workoutCountProvider.overrideWith((ref) => Future.value(workoutCount)),
      profileProvider.overrideWith(() => _ProfileStub()),
      pendingSyncProvider.overrideWith(() => _ZeroPendingSyncNotifier()),
      isOnlineProvider.overrideWith((ref) => true),
      currentUserEmailProvider.overrideWithValue('test@repsaga.test'),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HomeScreen - starter routines section header is sentence-case', () {
    testWidgets('never renders the uppercase STARTER ROUTINES header on home', (
      tester,
    ) async {
      // The uppercase `starterRoutinesSection` ARB key is the routine-list
      // screen's header. Home uses the sentence-case
      // `homeStarterRoutinesLabel` (Phase 27 L3) when the day-0 preview is
      // shown, and nothing when the user has custom routines.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          routines: [
            _routine(id: 'u-1', name: 'My Push', userId: 'user-001'),
            _routine(id: 'd-1', name: 'Full Body', isDefault: true),
          ],
          workouts: [_workout()],
          workoutCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('STARTER ROUTINES'), findsNothing);
      // User has a custom routine → preview is hidden, so the seeded
      // "Full Body" card must not appear on home.
      expect(find.text('Full Body'), findsNothing);
    });
  });

  group('HomeScreen - _DefaultRoutinesPreview (Phase 27 L3)', () {
    testWidgets(
      'renders up to 3 default routines as preview when user has no custom routines',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _build(
            routines: [
              _routine(id: 'd-1', name: 'Full Body', isDefault: true),
              _routine(id: 'd-2', name: 'Push Pull', isDefault: true),
              _routine(id: 'd-3', name: 'PPL', isDefault: true),
              _routine(id: 'd-4', name: 'Bro Split', isDefault: true),
            ],
            workoutCount: 0,
          ),
        );
        await tester.pump();
        await tester.pump();

        // Sentence-case label flush left, lowercase second word.
        expect(find.text('Starter Routines'), findsOneWidget);
        // First 3 defaults render as RoutineCards. 4th is dropped.
        expect(find.text('Full Body'), findsOneWidget);
        expect(find.text('Push Pull'), findsOneWidget);
        expect(find.text('PPL'), findsOneWidget);
        expect(find.text('Bro Split'), findsNothing);
        // Reuses the same RoutineCard widget as the populated MY ROUTINES
        // list — no new variant per UX-critic locked spec.
        expect(find.byType(RoutineCard), findsNWidgets(3));
        // Explicit anti-patterns from the locked spec.
        expect(find.text('See all'), findsNothing);
      },
    );

    testWidgets(
      'renders nothing when user has no custom routines AND no defaults exist',
      (tester) async {
        // Edge case: seed RPC has not run yet. _DefaultRoutinesPreview falls
        // back to SizedBox.shrink() so ActionHero owns the day-0 message
        // alone — no duplicate / broken layout.
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_build(routines: const [], workoutCount: 0));
        await tester.pump();
        await tester.pump();

        expect(find.text('Starter Routines'), findsNothing);
        expect(find.byType(RoutineCard), findsNothing);
      },
    );

    testWidgets(
      'hidden once the user has at least one custom routine (MY ROUTINES wins)',
      (tester) async {
        // The day-0 preview disappears as soon as the user creates their
        // first custom routine — there's no "Starter Routines + MY ROUTINES"
        // double-section. Per UX-critic Option B+.
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _build(
            routines: [
              _routine(id: 'u-1', name: 'My Push', userId: 'user-001'),
              _routine(id: 'd-1', name: 'Full Body', isDefault: true),
              _routine(id: 'd-2', name: 'Push Pull', isDefault: true),
            ],
            workoutCount: 0,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Starter Routines'), findsNothing);
        expect(find.text('MY ROUTINES'), findsOneWidget);
        expect(find.text('My Push'), findsOneWidget);
        expect(find.text('Full Body'), findsNothing);
        expect(find.text('Push Pull'), findsNothing);
      },
    );

    testWidgets('hidden when an active weekly plan exists', (tester) async {
      // _HomeRoutinesList short-circuits on `hasActivePlanProvider` BEFORE
      // it even reads the routine list — so neither MY ROUTINES nor the new
      // preview render once a plan exists. This must remain true after L3.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          routines: [_routine(id: 'd-1', name: 'Full Body', isDefault: true)],
          plan: _plan(routines: [_bucket(routineId: 'd-1', order: 1)]),
          workoutCount: 0,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Starter Routines'), findsNothing);
      expect(find.byType(RoutineCard), findsNothing);
    });

    testWidgets(
      'tapping a default card starts that routine and navigates to /workout/active',
      (tester) async {
        // Pins the contract: the starter cards are NOT a shortcut to
        // `/routines/create`. They start an actual workout for the tapped
        // default routine — same path as the populated MY ROUTINES card.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        String? routed;
        await tester.pumpWidget(
          _buildWithRouter(
            routines: [
              _defaultRoutineWithExercise(id: 'd-1', name: 'Full Body'),
            ],
            workoutCount: 0,
            onRoute: (location) => routed = location,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Full Body'), findsOneWidget);
        await tester.tap(find.text('Full Body'));
        await tester.pumpAndSettle();

        expect(routed, '/workout/active');
        expect(find.text('Active Workout Screen'), findsOneWidget);
      },
    );
  });

  group('HomeScreen - MY ROUTINES (truncated top 3)', () {
    testWidgets('shows MY ROUTINES when user has routines and no active plan', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          routines: [_routine(id: 'u-1', name: 'My Push', userId: 'user-001')],
          workouts: [_workout()],
          workoutCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('MY ROUTINES'), findsOneWidget);
      expect(find.text('My Push'), findsOneWidget);
    });

    testWidgets('truncates user routines to the top 3', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          routines: [
            _routine(id: 'u-1', name: 'My Push', userId: 'user-001'),
            _routine(id: 'u-2', name: 'My Pull', userId: 'user-001'),
            _routine(id: 'u-3', name: 'My Legs', userId: 'user-001'),
            _routine(id: 'u-4', name: 'My Arms', userId: 'user-001'),
            _routine(id: 'u-5', name: 'My Shoulders', userId: 'user-001'),
          ],
          workouts: [_workout()],
          workoutCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('My Push'), findsOneWidget);
      expect(find.text('My Pull'), findsOneWidget);
      expect(find.text('My Legs'), findsOneWidget);
      expect(find.text('My Arms'), findsNothing);
      expect(find.text('My Shoulders'), findsNothing);
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('no See all pill when 3 or fewer user routines', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          routines: [
            _routine(id: 'u-1', name: 'My Push', userId: 'user-001'),
            _routine(id: 'u-2', name: 'My Pull', userId: 'user-001'),
          ],
          workouts: [_workout()],
          workoutCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('See all'), findsNothing);
    });

    testWidgets('MY ROUTINES hidden when active plan exists', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          routines: [_routine(id: 'r-1', name: 'Push', userId: 'user-001')],
          plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
          workoutCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('MY ROUTINES'), findsNothing);
      expect(find.text('STARTER ROUTINES'), findsNothing);
    });
  });
}
