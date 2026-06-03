/// Widget tests for `_flushDebouncedSave` in [WeekPlanScreen] —
/// PR 33c finding-009.
///
/// **Pre-fix code:** `_flushDebouncedSave` chained `.then().catchError`:
///
/// ```dart
/// notifier.upsertPlan(...).then((_) {
///   _maybeShowSavedSnackbar();
/// }).catchError((_) {
///   // silent — no log, no trace
/// });
/// ```
///
/// The `.catchError((_) {})` swallowed every save failure with no
/// `debugPrint` trace. Per the audit (cluster `async-caller-broke-snackbar`),
/// silent swallows make production debugging hard — a user reporting
/// "I edited my plan and nothing saved" gives the team no log line to
/// search adb logcat / Sentry against.
///
/// **Post-fix code:**
///
/// ```dart
/// Future<void> _flushDebouncedSave() async {
///   try {
///     await notifier.upsertPlan(...);
///     if (mounted) _maybeShowSavedSnackbar();
///   } catch (e) {
///     debugPrint('[WeekPlanScreen] flush save failed: $e');
///   }
/// }
/// ```
///
/// **Contracts pinned here.**
///   1. `upsertPlan` failures are logged via `debugPrint` with the
///      `[WeekPlanScreen] flush save failed:` prefix. Reverting to
///      `.catchError((_) {})` collapses the trace and this test fails.
///   2. A throw in `upsertPlan` does NOT propagate out of
///      `_flushDebouncedSave` (no uncaught async error reaches the
///      framework).
///   3. When the widget is disposed mid-flight, the in-flight save
///      completes without throwing on a disposed `ScaffoldMessenger` —
///      the `if (mounted)` guard MUST hold the post-await code from
///      touching the BuildContext.
///
/// **Cluster:** `async-caller-broke-snackbar`. The Saved-snackbar branch
/// inside `_maybeShowSavedSnackbar` already gates on `mounted`; this test
/// pins that the OUTER flush method also respects the lifecycle (i.e. the
/// async-refactor doesn't introduce a new disposal hazard).
library;

import 'dart:async';

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
import 'package:repsaga/features/weekly_plan/ui/week_plan_screen.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';

import '../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

/// [WeeklyPlanNotifier] stub whose `upsertPlan` honors a per-call
/// completer. The test resolves the completer with an error to simulate
/// a Supabase failure, or with a value to simulate success-after-dispose.
class _FlushableWeeklyPlanStub extends AsyncNotifier<WeeklyPlan?>
    implements WeeklyPlanNotifier {
  _FlushableWeeklyPlanStub(this.plan);
  final WeeklyPlan? plan;

  /// Captured calls to `upsertPlan` — one entry per debounced flush.
  /// The test resolves each entry to drive the in-flight save's outcome.
  final List<Completer<void>> upsertCompleters = <Completer<void>>[];

  /// Captured calls to `setOptimistic` so the test can assert the
  /// optimistic-update path still runs even when the eventual save
  /// fails. Today the production code calls it once per edit; this is
  /// not strictly required for the disposal/log contract but keeps the
  /// stub semantically accurate.
  int setOptimisticCalls = 0;

  @override
  Future<WeeklyPlan?> build() async => plan;

  @override
  Future<void> upsertPlan(List<BucketRoutine> routines) {
    final completer = Completer<void>();
    upsertCompleters.add(completer);
    return completer.future;
  }

  @override
  void setOptimistic(List<BucketRoutine> routines) {
    setOptimisticCalls++;
  }

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

class _EmptyHistoryNotifier extends AsyncNotifier<WorkoutHistoryState>
    implements WorkoutHistoryNotifier {
  @override
  Future<WorkoutHistoryState> build() async =>
      (workouts: const <Workout>[], isLoadingMore: false, hasMore: false);

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

BucketRoutine _bucket({required String routineId, required int order}) {
  return BucketRoutine(routineId: routineId, order: order);
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

/// Builds the screen inside a routable shell that the test can swap out
/// (to "dispose" the screen). The [routerRefresh] notifier flips the
/// active route from `WeekPlanScreen` to a placeholder, which disposes
/// the screen's State while an in-flight `upsertPlan` is still pending.
Widget _build({
  required WeeklyPlan? plan,
  required List<Routine> routines,
  required _FlushableWeeklyPlanStub planStub,
  int trainingFrequency = 3,
}) {
  final mockAuth = _MockAuthRepository();
  when(() => mockAuth.currentUser).thenReturn(null);

  return ProviderScope(
    overrides: [
      weeklyPlanProvider.overrideWith(() => planStub),
      routineListProvider.overrideWith(() => _RoutineListStub(routines)),
      profileProvider.overrideWith(() => _ProfileStub(trainingFrequency)),
      workoutHistoryProvider.overrideWith(() => _EmptyHistoryNotifier()),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
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
  group('WeekPlanScreen — _flushDebouncedSave async refactor (finding-009)', () {
    testWidgets(
      'should log via debugPrint when upsertPlan throws (no silent swallow)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Capture debugPrint calls. Pre-fix the `.catchError((_) {})` arm
        // logged nothing — this list stays empty and the assertion below
        // fails with "Expected: contains a string starting with [WeekPlanScreen]
        // ... Actual: []".
        //
        // NOTE: must restore `debugPrint` BEFORE the test body returns —
        // `TestWidgetsFlutterBinding._verifyInvariants` asserts every
        // foundation debug variable is unset post-test. `addTearDown`
        // runs AFTER `_verifyInvariants`, so it's too late. We restore
        // inline + use a `try`/`finally` to keep the restore on the
        // assertion-failure path too.
        final printed = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? msg, {int? wrapWidth}) {
          if (msg != null) printed.add(msg);
        };

        try {
          final planStub = _FlushableWeeklyPlanStub(
            _plan(routines: [_bucket(routineId: 'r-001', order: 1)]),
          );
          final routines = [
            _routine(id: 'r-001', name: 'Push Day'),
            _routine(id: 'r-002', name: 'Pull Day'),
          ];

          await tester.pumpWidget(
            _build(plan: planStub.plan, routines: routines, planStub: planStub),
          );
          await tester.pumpAndSettle();

          // Drive an edit so the debounce + upsertPlan path fires. The
          // simplest path that survives the L5 invalidate dance is
          // "+ Add workout" → tap the second routine → confirm. The
          // resulting upsertPlan call lands in `planStub.upsertCompleters`
          // and stays pending until the test resolves it.
          await tester.tap(find.text('+ Add workout'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Pull Day'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.textContaining(RegExp(r'^ADD ', caseSensitive: true)),
          );
          await tester.pumpAndSettle();

          // The 300 ms debounce timer must fire for the flush to run.
          // Pump past it.
          await tester.pump(const Duration(milliseconds: 400));

          expect(
            planStub.upsertCompleters,
            isNotEmpty,
            reason:
                'The debounced flush must reach `upsertPlan` after the 300 ms '
                'debounce. If empty, the edit path failed to schedule the '
                'flush at all.',
          );

          // Resolve the in-flight upsertPlan with a Supabase-like error.
          // Pre-fix the `.catchError((_) {})` arm runs and the printed
          // list stays empty. Post-fix the explicit `catch (e)` branch
          // runs `debugPrint('[WeekPlanScreen] flush save failed: $e')`.
          planStub.upsertCompleters.last.completeError(
            StateError('supabase 500: simulated failure'),
          );
          await tester.pump();
          await tester.pumpAndSettle();

          expect(
            printed.any(
              (line) => line.startsWith('[WeekPlanScreen] flush save failed:'),
            ),
            isTrue,
            reason:
                'Save failures inside `_flushDebouncedSave` MUST surface via '
                '`debugPrint(\'[WeekPlanScreen] flush save failed: \$e\')`. '
                'The pre-fix `.catchError((_) {})` arm swallowed every '
                'failure with no trace, leaving production debugging blind '
                'to user reports of "I edited my plan and nothing saved". '
                'Cluster: async-caller-broke-snackbar.\n'
                'Captured debugPrint lines:\n${printed.join("\n")}',
          );
        } finally {
          debugPrint = originalDebugPrint;
        }
      },
    );

    testWidgets('should not throw when the widget is disposed mid-flight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final planStub = _FlushableWeeklyPlanStub(
        _plan(routines: [_bucket(routineId: 'r-001', order: 1)]),
      );
      final routines = [
        _routine(id: 'r-001', name: 'Push Day'),
        _routine(id: 'r-002', name: 'Pull Day'),
      ];

      await tester.pumpWidget(
        _build(plan: planStub.plan, routines: routines, planStub: planStub),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ Add workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pull Day'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining(RegExp(r'^ADD ', caseSensitive: true)),
      );
      await tester.pumpAndSettle();

      // Let the debounce fire so `upsertPlan` is in flight.
      await tester.pump(const Duration(milliseconds: 400));
      expect(planStub.upsertCompleters, isNotEmpty);

      // Capture the pending completer BEFORE the widget unmounts —
      // after unmount the stub is GC-eligible and the reference would
      // be brittle. Resolve AFTER the dispose to reproduce the
      // disposal race: in production the user navigates away
      // (`context.pop()` / `context.go(...)`) while the Supabase
      // round-trip is still in flight, then the future resolves
      // against a disposed State.
      final pending = planStub.upsertCompleters.last;

      // Replace the running widget with a bare placeholder. This is
      // the test analog of `context.pop()` — the WeekPlanScreen's
      // `_WeekPlanScreenState` is taken out of the tree and disposed,
      // which is the disposal contract the `if (mounted)` guard must
      // honor.
      //
      // Also flushes the dispose-time `_flushDebouncedSave` (line 99
      // of week_plan_screen.dart) which fires another upsertPlan via
      // `_debouncedPlanNotifier`. That additional pending completer
      // gets resolved alongside the original one in the loop below.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      // Resolve every still-pending upsertPlan with success. The
      // post-await `_maybeShowSavedSnackbar` call MUST short-circuit
      // via its `if (!mounted) return;` guard — otherwise the
      // `ScaffoldMessenger.of(context)` lookup against a disposed
      // State throws a `NoScaffoldMessenger` exception that propagates
      // out of the async caller.
      for (final completer in [pending, ...planStub.upsertCompleters]) {
        if (!completer.isCompleted) completer.complete();
      }
      // Pump once to let the awaited future resume + the mounted
      // check + the catch block (if any) run. A second pumpAndSettle
      // drains microtask + frame work without timing out.
      await tester.pump();
      await tester.pumpAndSettle();

      // Negative-space behavioral assertion: no SnackBar appears on
      // the destination Scaffold. The placeholder MaterialApp has
      // exactly one Scaffold (the SizedBox.shrink() host) — a SnackBar
      // posted to the disposed ScaffoldMessenger would not appear
      // here, but a *thrown* exception during the post-await branch
      // would propagate to the test runner and fail the test before
      // we got here.
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason:
            'After the widget is disposed mid-flight, the flush\'s '
            'post-await `_maybeShowSavedSnackbar` call MUST short-circuit '
            '(via `if (!mounted) return;`) — no Saved-snackbar should '
            'appear on the destination screen, and the in-flight save '
            'must complete without throwing on the disposed '
            'BuildContext.',
      );

      // Sanity — the optimistic-update path ran at least once (the
      // edit was real), proving the test exercise reached the
      // debounced flush; without this we could be asserting against
      // a no-op path.
      expect(
        planStub.setOptimisticCalls,
        greaterThan(0),
        reason:
            '`setOptimistic` should run on every edit. If 0, the test '
            'never actually drove the flush path.',
      );
    });
  });
}
