/// Widget tests for the Phase 26f Action Hero (3-branch contract).
///
/// Branches (decision locked 2026-05-18, docs/WIP.md → T10):
///   1. Routines empty → `_CreateFirstRoutineHero` (identifier:
///      `home-action-hero-create-first-routine`). Headline "Criar primeira
///      rotina"; tap → push `/routines/create`.
///   2. `suggestedNextProvider` returns a `BucketRoutine` → `_StartNextRoutineHero`
///      (identifier: `home-action-hero-start-routine`). Eyebrow "INICIAR",
///      headline `Iniciar {routineName}`, subline = exercise count + duration.
///      Tap → start the routine (mirrors the active-plan branch).
///   3. Else → `_FreeWorkoutHero` (identifier: `home-action-hero-free-workout`).
///      Eyebrow "TREINO LIVRE", headline "Treino livre". Subline =
///      "Semana completa" when `isWeekCompleteProvider` is true, otherwise
///      absent. Tap → quick workout flow (mirrors the legacy `_startQuickWorkout`
///      helper, including the resume-vs-start dialog).
///
/// Each branch sets a per-branch `flt-semantics-identifier` AND lives under the
/// stable outer wrapper `home-action-hero` so charter specs that target the
/// outer hero keep working.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/action_hero.dart';
import 'package:repsaga/l10n/app_localizations.dart';

import '../../../../fixtures/test_factories.dart';

// ---------------------------------------------------------------------------
// Stubs — extend the real notifiers so AsyncNotifierProvider.overrideWith
// can receive a typed factory. Following the bucket_chip_row_test pattern
// from T9.
// ---------------------------------------------------------------------------

class _PlanStub extends WeeklyPlanNotifier {
  _PlanStub(this._plan);
  final WeeklyPlan? _plan;

  @override
  Future<WeeklyPlan?> build() async => _plan;
}

class _RoutineListStub extends RoutineListNotifier {
  _RoutineListStub(this._routines);
  final List<Routine> _routines;

  @override
  Future<List<Routine>> build() async => _routines;
}

class _NullActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  @override
  Future<ActiveWorkoutState?> build() async => null;

  /// No-op so `startRoutineWorkout`'s `await ...startFromRoutine(...)` does
  /// not explode on NoSuchMethodError when a test wants to assert
  /// post-start navigation (no auth wired up in widget tests).
  @override
  Future<void> startFromRoutine(RoutineStartConfig config) async {}

  /// Same idea for the free-workout branch: `_startQuickWorkout` calls
  /// `startWorkout()` when no existing workout is present.
  @override
  Future<void> startWorkout([String? name]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tracks `discardWorkout` + `startWorkout` calls so the resume-vs-start
/// regression test can assert "Quick workout → Discard → fresh workout
/// started" (carried forward from the legacy 4-branch test). The seed
/// represents the stale active workout the user is about to discard; after
/// discard the state becomes null; after startWorkout it becomes
/// [_startedState] (distinct workout id so tests can tell them apart).
class _SeededActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _SeededActiveWorkoutNotifier(this._seed);

  final ActiveWorkoutState _seed;

  int discardCount = 0;
  int startCount = 0;

  static final ActiveWorkoutState _startedState = ActiveWorkoutState(
    workout: Workout(
      id: 'fresh-workout',
      userId: 'user-001',
      name: 'Fresh Workout',
      startedAt: DateTime.utc(2026, 4, 16, 12),
      isActive: true,
      createdAt: DateTime.utc(2026, 4, 16, 12),
    ),
    exercises: const [],
  );

  @override
  Future<ActiveWorkoutState?> build() async => _seed;

  @override
  Future<void> discardWorkout() async {
    discardCount++;
    state = const AsyncData(null);
  }

  @override
  Future<void> startWorkout([String? name]) async {
    startCount++;
    state = AsyncData(_startedState);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

Routine _routine({
  required String id,
  required String name,
  bool isDefault = false,
  String? userId = 'user-001',
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
/// `context.go('/workout/active')` rather than showing the empty-exercises
/// snackbar. Used by the tap-navigation tests.
Routine _routineWithResolvedExercise({
  required String id,
  required String name,
  String? userId = 'user-001',
}) {
  final exerciseJson = TestExerciseFactory.create(
    id: 'ex-$id',
    name: 'Bench Press',
    equipmentType: 'barbell',
  );
  final routineJson = TestRoutineFactory.create(
    id: id,
    name: name,
    userId: userId,
    exercises: [
      TestRoutineExerciseFactory.create(
        exerciseId: 'ex-$id',
        exercise: exerciseJson,
      ),
    ],
  );
  return Routine.fromJson(routineJson);
}

BucketRoutine _bucket({
  required String routineId,
  required int order,
  String? completedWorkoutId,
}) => BucketRoutine(
  routineId: routineId,
  order: order,
  completedWorkoutId: completedWorkoutId,
);

WeeklyPlan _plan({required List<BucketRoutine> routines}) => WeeklyPlan(
  id: 'plan-001',
  userId: 'user-001',
  weekStart: DateTime(2026, 4, 13),
  routines: routines,
  createdAt: DateTime(2026, 4, 13),
  updatedAt: DateTime(2026, 4, 13),
);

/// Seeded active-workout state used by the discard-then-start regression test.
///
/// `startedAt` is "now minus 10 minutes" so the [ResumeWorkoutDialog] picks
/// the non-stale copy ("Resume workout?") — keeps the locator stable
/// regardless of when the suite runs.
ActiveWorkoutState _seedActiveWorkout() {
  final startedAt = DateTime.now().toUtc().subtract(
    const Duration(minutes: 10),
  );
  return ActiveWorkoutState(
    workout: Workout(
      id: 'existing-workout',
      userId: 'user-001',
      name: 'Existing Workout',
      startedAt: startedAt,
      isActive: true,
      createdAt: startedAt,
    ),
    exercises: const [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-existing',
          workoutId: 'existing-workout',
          exerciseId: 'ex-001',
          order: 0,
        ),
        sets: [],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _buildWithRouter({
  WeeklyPlan? plan,
  List<Routine> routines = const [],
  // Default to 1 (returning user) so the day-0 branch isn't triggered for
  // tests that just exercise bucket / free-workout state. Tests targeting
  // `_CreateFirstRoutineHero` pass `workoutCount: 0` explicitly.
  int workoutCount = 1,
  ActiveWorkoutNotifier Function()? activeWorkoutNotifier,
  ValueChanged<String>? onRoute,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        // Wraps ActionHero in a Consumer that silently watches
        // activeWorkoutProvider so the seeded AsyncNotifier actually builds
        // and commits its initial state — otherwise the provider stays
        // uninitialized and `_startQuickWorkout`'s `ref.read(...).value`
        // reads a null AsyncLoading on first tap.
        builder: (ctx, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(activeWorkoutProvider);
              return const ActionHero();
            },
          ),
        ),
      ),
      GoRoute(
        path: '/routines/create',
        pageBuilder: (ctx, state) {
          onRoute?.call('/routines/create');
          return const NoTransitionPage(
            child: Scaffold(body: Text('Create Routine Screen')),
          );
        },
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
      weeklyPlanProvider.overrideWith(() => _PlanStub(plan)),
      routineListProvider.overrideWith(() => _RoutineListStub(routines)),
      // Day-0 gate. `overrideWithValue` seeds the FutureProvider with an
      // already-resolved AsyncData, so the first build sees the value
      // synchronously — no extra pump needed to drain a microtask. This
      // mirrors `onlineStatusProvider.overrideWithValue(const AsyncData(...))`
      // used elsewhere in the test suite for FutureProvider seeding.
      workoutCountProvider.overrideWithValue(AsyncData(workoutCount)),
      activeWorkoutProvider.overrideWith(
        activeWorkoutNotifier ?? () => _NullActiveWorkoutNotifier(),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Pin to pt so the inlined Portuguese-first labels in ActionHero
      // (Phase 26f decision — single-locale launch) line up with l10n keys
      // like homeActionHeroStartRoutine / homeActionHeroFreeWorkout that
      // still pass through ARB.
      locale: const Locale('pt'),
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Finder _findByIdentifier(String identifier) {
  return find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == identifier,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ActionHero — _StartNextRoutineHero', () {
    testWidgets('shows when bucket has an uncompleted entry', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter(
          plan: _plan(
            routines: [
              _bucket(routineId: 'r-1', order: 1),
              _bucket(routineId: 'r-2', order: 2),
            ],
          ),
          routines: [
            _routine(id: 'r-1', name: 'Push Day'),
            _routine(id: 'r-2', name: 'Pull Day'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // Per-branch identifier is the stable E2E hook.
      expect(
        _findByIdentifier('home-action-hero-start-routine'),
        findsOneWidget,
      );
      // Headline carries the routine name through the l10n template.
      expect(find.text('Iniciar Push Day'), findsOneWidget);
      // Eyebrow label is the inlined uppercase Portuguese stopgap.
      expect(find.text('INICIAR'), findsOneWidget);
      // The other 2 branches are NOT in the tree.
      expect(_findByIdentifier('home-action-hero-free-workout'), findsNothing);
      expect(
        _findByIdentifier('home-action-hero-create-first-routine'),
        findsNothing,
      );
    });

    testWidgets('subline renders exercise count and duration', (tester) async {
      // 6 exercises × 3 sets at 120s rest each — mirrors the legacy
      // "renders stats line" assertion. Subline format comes from
      // exerciseCountDuration ARB template ({count} exercícios · ~{minutes} min).
      final routine = Routine(
        id: 'r-1',
        name: 'Push Day',
        userId: 'user-001',
        isDefault: false,
        exercises: List.generate(
          6,
          (i) => RoutineExercise(
            exerciseId: 'ex-$i',
            setConfigs: List.generate(
              3,
              (_) => const RoutineSetConfig(targetReps: 5, restSeconds: 120),
            ),
          ),
        ),
        createdAt: DateTime(2026),
      );

      await tester.pumpWidget(
        _buildWithRouter(
          plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
          routines: [routine],
        ),
      );
      await tester.pump();
      await tester.pump();

      // pt-BR copy: "{N} exercícios · ~{M} min".
      expect(find.textContaining('6 exercícios'), findsOneWidget);
      expect(find.textContaining('~45 min'), findsOneWidget);
    });

    testWidgets('advances to the next uncompleted routine in bucket order', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWithRouter(
          plan: _plan(
            routines: [
              _bucket(routineId: 'r-1', order: 1, completedWorkoutId: 'wk-1'),
              _bucket(routineId: 'r-2', order: 2),
            ],
          ),
          routines: [
            _routine(id: 'r-1', name: 'Push Day'),
            _routine(id: 'r-2', name: 'Pull Day'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // First routine complete → headline targets the next uncompleted one.
      expect(find.text('Iniciar Pull Day'), findsOneWidget);
      expect(find.text('Iniciar Push Day'), findsNothing);
    });

    testWidgets('tap navigates to /workout/active (start-routine flow)', (
      tester,
    ) async {
      // Routine needs a resolved exercise so startRoutineWorkout proceeds
      // past its empty-exercises guard and reaches context.go('/workout/active').
      // The active-workout notifier is the default _NullActiveWorkoutNotifier
      // whose startFromRoutine is a no-op, so no repo mocks are needed.
      final routine = _routineWithResolvedExercise(id: 'r-1', name: 'Push Day');

      await tester.pumpWidget(
        _buildWithRouter(
          plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
          routines: [routine],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Iniciar Push Day'));
      await tester.pumpAndSettle();

      expect(find.text('Active Workout Screen'), findsOneWidget);
    });
  });

  group('ActionHero — _FreeWorkoutHero', () {
    testWidgets('shows when bucket is fully complete with "Semana completa"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWithRouter(
          plan: _plan(
            routines: [
              _bucket(routineId: 'r-1', order: 1, completedWorkoutId: 'wk-1'),
              _bucket(routineId: 'r-2', order: 2, completedWorkoutId: 'wk-2'),
            ],
          ),
          routines: [
            _routine(id: 'r-1', name: 'Push'),
            _routine(id: 'r-2', name: 'Pull'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        _findByIdentifier('home-action-hero-free-workout'),
        findsOneWidget,
      );
      expect(find.text('TREINO LIVRE'), findsOneWidget);
      expect(find.text('Treino livre'), findsOneWidget);
      expect(find.text('Semana completa'), findsOneWidget);
    });

    testWidgets(
      'shows when user has routines but no plan (no "Semana completa" subline)',
      (tester) async {
        // No plan → isWeekCompleteProvider returns false → free-workout hero
        // shows without the weekly-completion subline. This is the steady-
        // state "has routines but bucket is empty" case (lapsed-style users
        // who haven't created a plan this week).
        await tester.pumpWidget(
          _buildWithRouter(
            plan: null,
            routines: [_routine(id: 'r-1', name: 'X')],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          _findByIdentifier('home-action-hero-free-workout'),
          findsOneWidget,
        );
        expect(find.text('TREINO LIVRE'), findsOneWidget);
        expect(find.text('Treino livre'), findsOneWidget);
        // No week-complete subline when the week is NOT complete.
        expect(find.text('Semana completa'), findsNothing);
        // Not the create-first-routine branch.
        expect(
          _findByIdentifier('home-action-hero-create-first-routine'),
          findsNothing,
        );
      },
    );

    testWidgets('tap → Discard → starts fresh workout and navigates', (
      tester,
    ) async {
      // Carry-forward of the legacy B1 regression test. Seed the
      // active-workout provider with a stale workout. Tapping the
      // free-workout hero surfaces the resume dialog; choosing Discard must
      // (a) clear the stale workout, (b) start a fresh one, and (c) land on
      // /workout/active. Before B1 this silently returned.
      final seededNotifier = _SeededActiveWorkoutNotifier(_seedActiveWorkout());

      await tester.pumpWidget(
        _buildWithRouter(
          plan: null,
          routines: [_routine(id: 'r-1', name: 'X')],
          activeWorkoutNotifier: () => seededNotifier,
        ),
      );
      // Settle so the seeded notifier commits its initial state — otherwise
      // ref.read(activeWorkoutProvider).value returns null at the moment of
      // tap and the dialog never appears.
      await tester.pumpAndSettle();

      // Open the resume dialog via the free-workout hero card.
      await tester.tap(find.text('Treino livre'));
      await tester.pumpAndSettle();

      // Dialog is up — pick Discard. Harness pins locale to pt, so the
      // dialog title and discard button render their Portuguese forms.
      expect(find.text('Retomar sessão?'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      // Discard was called AND a fresh workout was started.
      expect(seededNotifier.discardCount, 1);
      expect(
        seededNotifier.startCount,
        1,
        reason:
            'After Discard the user intended to start fresh. A new workout '
            'must be started, not silently swallowed (B1 regression).',
      );

      // Landed on the active workout screen.
      expect(find.text('Active Workout Screen'), findsOneWidget);
    });
  });

  group('ActionHero — _CreateFirstRoutineHero', () {
    // L1 (visual verification, 2026-05-18): the branch is gated on
    // `workoutCountProvider == 0` — "user has never recorded a workout" —
    // not on `routines.isEmpty`. Default routines ship seeded for every
    // user in production, so the empty-routines gate never fires.
    testWidgets(
      'shows when workoutCount is 0 AND no custom routines (day-0 user)',
      (tester) async {
        // Phase 27 L3 gate: hero fires when day-0 user has not created any
        // custom routines yet. Seed a DEFAULT routine plus a bucket
        // referencing it — the default doesn't count as a user-owned routine
        // (same `!r.isDefault` filter as `_HomeRoutinesList`), so the
        // create-first-routine CTA still wins even with a populated bucket.
        await tester.pumpWidget(
          _buildWithRouter(
            workoutCount: 0,
            plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
            routines: [
              _routine(
                id: 'r-1',
                name: 'Push Day',
                isDefault: true,
                userId: null,
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          _findByIdentifier('home-action-hero-create-first-routine'),
          findsOneWidget,
        );
        expect(find.text('Criar primeira rotina'), findsOneWidget);
        expect(find.text('BEM-VINDO'), findsOneWidget);
        // Other branches not in the tree — day-0 gate wins over the bucket.
        expect(
          _findByIdentifier('home-action-hero-start-routine'),
          findsNothing,
        );
        expect(
          _findByIdentifier('home-action-hero-free-workout'),
          findsNothing,
        );
      },
    );

    testWidgets('tap navigates to /routines/create', (tester) async {
      String? lastPushed;
      await tester.pumpWidget(
        _buildWithRouter(
          workoutCount: 0,
          plan: null,
          routines: const [],
          onRoute: (location) => lastPushed = location,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Criar primeira rotina'));
      await tester.pumpAndSettle();

      expect(lastPushed, '/routines/create');
      expect(find.text('Create Routine Screen'), findsOneWidget);
    });

    testWidgets(
      'falls through to _FreeWorkoutHero when workoutCount > 0 and bucket is empty',
      (tester) async {
        // The exact regression L1 unmasked: a returning user (workoutCount
        // == 1) with seeded default routines but no plan must NOT see the
        // create-first-routine CTA. They should land on free-workout.
        await tester.pumpWidget(
          _buildWithRouter(
            workoutCount: 1,
            plan: null,
            routines: [_routine(id: 'r-1', name: 'Push Day', isDefault: true)],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          _findByIdentifier('home-action-hero-create-first-routine'),
          findsNothing,
        );
        expect(
          _findByIdentifier('home-action-hero-free-workout'),
          findsOneWidget,
        );
        expect(find.text('Treino livre'), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT show when workoutCount == 0 but user has a custom routine (L3 gate)',
      (tester) async {
        // Phase 27 L3 gate tightening: day-0 user who has already created a
        // custom routine should NOT see the create-first-routine CTA. They
        // already have a routine — the hero should fall through to
        // free-workout / start-next so the user can lift, not push them back
        // to /routines/create. Without this gate, the home shows "Criar
        // primeira rotina" duplicated by the routines list's own CTA.
        await tester.pumpWidget(
          _buildWithRouter(
            workoutCount: 0,
            plan: null,
            routines: [
              _routine(id: 'u-1', name: 'My Push', userId: 'user-001'),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          _findByIdentifier('home-action-hero-create-first-routine'),
          findsNothing,
        );
        expect(
          _findByIdentifier('home-action-hero-free-workout'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'still shows when workoutCount == 0 and only default (seeded) routines exist',
      (tester) async {
        // Default routines (`isDefault == true`, `userId == null`) ship for
        // every user. They must NOT satisfy the "user has a routine" gate —
        // otherwise the create-first-routine hero would never fire for any
        // day-0 user. Same `!r.isDefault` filter as `_HomeRoutinesList`.
        await tester.pumpWidget(
          _buildWithRouter(
            workoutCount: 0,
            plan: null,
            routines: [
              _routine(
                id: 'd-1',
                name: 'Full Body',
                isDefault: true,
                userId: null,
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          _findByIdentifier('home-action-hero-create-first-routine'),
          findsOneWidget,
        );
      },
    );
  });

  group('ActionHero — outer home-action-hero identifier', () {
    // The outer wrapper preserves the legacy `home-action-hero` semantics so
    // charter specs that assert "hero exists" keep passing across all three
    // branches without locale-specific text matching.

    testWidgets('present in _StartNextRoutineHero branch', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter(
          plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
          routines: [_routine(id: 'r-1', name: 'Push')],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_findByIdentifier('home-action-hero'), findsOneWidget);
    });

    testWidgets('present in _FreeWorkoutHero branch', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter(
          plan: null,
          routines: [_routine(id: 'r-1', name: 'Push')],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_findByIdentifier('home-action-hero'), findsOneWidget);
    });

    testWidgets('present in _CreateFirstRoutineHero branch', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter(workoutCount: 0, plan: null, routines: const []),
      );
      await tester.pump();
      await tester.pump();
      expect(_findByIdentifier('home-action-hero'), findsOneWidget);
    });
  });
}
