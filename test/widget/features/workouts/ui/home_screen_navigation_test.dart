/// Navigation tests for HomeScreen.
///
/// Covers the navigation flows that fan out from Home:
/// - LastSessionLine → /home/history via push (history detail entry).
/// - "EDITAR PLANO →" link in BucketChipRow → /plan/week (plan editor).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/character_sheet_provider.dart';
import 'package:repsaga/features/rpg/providers/rank_up_pulse_provider.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/streak_provider.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/core/offline/pending_sync_provider.dart';
import 'package:repsaga/features/workouts/ui/home_screen.dart';
import 'package:repsaga/features/workouts/ui/widgets/last_session_line.dart';

import '../../../../fixtures/test_factories.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _MockPulseStorage extends Mock implements RankUpPulseLocalStorage {}

class _RoutineStub extends AsyncNotifier<List<Routine>>
    implements RoutineListNotifier {
  _RoutineStub(this.routines);
  final List<Routine> routines;

  @override
  Future<List<Routine>> build() async => routines;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryStub extends AsyncNotifier<List<Workout>>
    implements WorkoutHistoryNotifier {
  _HistoryStub(this.workouts);
  final List<Workout> workouts;

  @override
  Future<List<Workout>> build() async => workouts;

  @override
  bool get hasMore => false;

  @override
  bool get isLoadingMore => false;

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

class _NullActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  @override
  Future<ActiveWorkoutState?> build() async => null;

  @override
  Future<void> startWorkout([String? name]) async {}

  @override
  Future<void> discardWorkout() async {}

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
  _ProfileStub(this.profile);
  final Profile? profile;

  @override
  Future<Profile?> build() async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ZeroPendingSyncNotifier extends PendingSyncNotifier {
  @override
  int build() => 0;
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

Workout _workout({required String finishedAt, String name = 'Push Day'}) =>
    Workout.fromJson(
      TestWorkoutFactory.create(name: name, finishedAt: finishedAt),
    );

BodyPartSheetEntry _untrained(BodyPart bp) => BodyPartSheetEntry(
  bodyPart: bp,
  rank: 1,
  vitalityEwma: 0,
  vitalityPeak: 0,
  vitalityState: VitalityState.untested,
  xpInRank: 0,
  xpForNextRank: 100,
  totalXp: 0,
);

CharacterSheetState _dayZeroSheet() => CharacterSheetState(
  characterLevel: 1,
  lifetimeXp: 0,
  xpForNextLevel: 1000,
  bodyPartProgress: [for (final bp in activeBodyParts) _untrained(bp)],
  activeTitle: null,
  characterClass: null,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _buildTestApp({
  required List<Workout> workouts,
  WeeklyPlan? plan,
  List<Routine> routines = const [],
}) {
  final pulseStorage = _MockPulseStorage();
  when(
    () => pulseStorage.isPulsing(any(), now: any(named: 'now')),
  ).thenReturn(false);

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => const Scaffold(body: HomeScreen()),
        routes: [
          GoRoute(
            path: 'history',
            builder: (context, _) =>
                const Scaffold(body: Center(child: Text('History Screen'))),
          ),
        ],
      ),
      GoRoute(
        path: '/plan/week',
        builder: (context, _) =>
            const Scaffold(body: Center(child: Text('Plan Week Screen'))),
      ),
      GoRoute(
        path: '/workout/active',
        builder: (context, _) =>
            const Scaffold(body: Center(child: Text('Active Workout Screen'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      routineListProvider.overrideWith(() => _RoutineStub(routines)),
      workoutHistoryProvider.overrideWith(() => _HistoryStub(workouts)),
      activeWorkoutProvider.overrideWith(() => _NullActiveWorkoutNotifier()),
      weeklyPlanProvider.overrideWith(() => _PlanStub(plan)),
      weeklyPlanNeedsConfirmationProvider.overrideWith((ref) => false),
      workoutCountProvider.overrideWith((ref) => Future.value(workouts.length)),
      profileProvider.overrideWith(
        () => _ProfileStub(
          const Profile(id: 'user-001', displayName: 'Alex', weightUnit: 'kg'),
        ),
      ),
      pendingSyncProvider.overrideWith(() => _ZeroPendingSyncNotifier()),
      characterSheetProvider.overrideWith((_) => AsyncData(_dayZeroSheet())),
      rankUpPulseLocalStorageProvider.overrideWithValue(pulseStorage),
      streakProvider.overrideWith((ref) => 0),
      // HomeGreeting (Phase 27 L2) reads `currentUserEmailProvider` for its
      // displayName-fallback. Seed a stable value so the greeting renders
      // the profile's `displayName` and doesn't crash on a missing auth
      // subgraph. Mirrors the override seeded in `home_screen_test.dart`.
      currentUserEmailProvider.overrideWithValue('test@repsaga.test'),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(BodyPart.chest);
  });

  group('HomeScreen - last session line navigation', () {
    testWidgets('tapping LastSessionLine navigates to /home/history via push', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        _buildTestApp(
          workouts: [_workout(finishedAt: yesterday.toIso8601String())],
        ),
      );
      // CharacterCard's RuneHalo runs infinite animations, so we avoid
      // pumpAndSettle on the source tree; two pumps are enough for the
      // history line to hydrate.
      await tester.pump();
      await tester.pump();

      // Scroll the LastSessionLine into view — the new home composition
      // pushes it below the CharacterCard, which can place it off-screen
      // on the default test viewport.
      await tester.scrollUntilVisible(find.byType(LastSessionLine), 200);
      await tester.tap(find.byType(LastSessionLine));
      await tester.pumpAndSettle();

      expect(find.text('History Screen'), findsOneWidget);

      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      expect(nav.canPop(), isTrue);
    });

    testWidgets('back from History returns to HomeScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        _buildTestApp(
          workouts: [_workout(finishedAt: yesterday.toIso8601String())],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.scrollUntilVisible(find.byType(LastSessionLine), 200);
      await tester.tap(find.byType(LastSessionLine));
      await tester.pumpAndSettle();
      expect(find.text('History Screen'), findsOneWidget);

      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      nav.pop();
      // Cannot pumpAndSettle after pop — CharacterCard's RuneHalo runs
      // infinite-loop AnimationControllers (8s rotation, 3s breathing
      // pulse) on the destination (Home) tree. Stepped pumps drain the
      // pop transition without waiting for animation idle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // History is off the stack — destination text gone.
      expect(find.text('History Screen'), findsNothing);
    });
  });

  group('HomeScreen - bucket chip row navigation', () {
    testWidgets(
      'tapping "Edit plan" link in BucketChipRow navigates to /plan/week',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Empty bucket — the BucketChipRow still surfaces the "Edit plan →"
        // link (DECISION LOCKED 2026-05-18) so this navigation flow works
        // even for "has-routines-but-no-plan" users.
        await tester.pumpWidget(_buildTestApp(workouts: const [], plan: null));
        await tester.pump();
        await tester.pump();

        // English locale (TestMaterialApp default) — the link reads
        // "EDIT PLAN →".
        final link = find.text('EDIT PLAN →');
        await tester.scrollUntilVisible(link, 200);
        await tester.tap(link);
        await tester.pumpAndSettle();

        expect(find.text('Plan Week Screen'), findsOneWidget);
      },
    );
  });
}
