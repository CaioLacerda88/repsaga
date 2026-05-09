/// Widget tests for PlanManagementScreen.
///
/// Covers:
/// - Soft-cap inline text with X/Y counter (Change 2)
/// - Auto-fill button in empty state (Change 1)
/// - "routines planned" counter when below soft cap (Change 2)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/weekly_plan/ui/plan_management_screen.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
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

class _MockUser extends Mock implements User {}

/// No-op analytics repo — prevents tests from touching `Supabase.instance`
/// when `_savePlan` fires `week_plan_saved`.
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

/// Captures every `insertEvent` call so tests can assert firing counts.
class _CapturingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  _CapturingAnalyticsRepository();

  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    events.add(event);
  }
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
// Helper
// ---------------------------------------------------------------------------

Widget _build({
  required WeeklyPlan? plan,
  required List<Routine> routines,
  int trainingFrequency = 3,
  AnalyticsRepository? analytics,
  AuthRepository? auth,
}) {
  // Default: null-user auth mock — `_savePlan` reads `.currentUser?.id` and
  // early-returns when null, short-circuiting analytics inserts without
  // touching Supabase. Tests that want to assert analytics fires must pass
  // their own auth mock with a non-null user.
  final AuthRepository authRepo;
  if (auth != null) {
    authRepo = auth;
  } else {
    final mockAuth = _MockAuthRepository();
    when(() => mockAuth.currentUser).thenReturn(null);
    authRepo = mockAuth;
  }

  return ProviderScope(
    overrides: [
      weeklyPlanProvider.overrideWith(() => _WeeklyPlanStub(plan)),
      routineListProvider.overrideWith(() => _RoutineListStub(routines)),
      profileProvider.overrideWith(() => _ProfileStub(trainingFrequency)),
      workoutHistoryProvider.overrideWith(() => _EmptyHistoryNotifier()),
      authRepositoryProvider.overrideWithValue(authRepo),
      analyticsRepositoryProvider.overrideWithValue(
        analytics ?? const _FakeAnalyticsRepository(),
      ),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      // Wrap in Consumer to eagerly initialise workoutHistoryProvider so
      // the auto-fill loading guard doesn't block on first access.
      home: Consumer(
        builder: (context, ref, _) {
          ref.watch(workoutHistoryProvider);
          return const PlanManagementScreen();
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PlanManagementScreen soft-cap inline text', () {
    testWidgets(
      'shows "X/X planned -- ready to go" text when bucket count >= training frequency',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Training frequency = 2, bucket has 2 routines => at soft cap.
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
          find.textContaining('2/2 planned'),
          findsOneWidget,
          reason:
              'Soft-cap hint should show "2/2 planned — ready to go" at cap',
        );
      },
    );

    testWidgets(
      'shows "X/Y planned this week" when bucket count < training frequency',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Training frequency = 3, bucket has 1 routine => below soft cap.
        final routines = [
          _routine(id: 'r-001', name: 'Push Day'),
          _routine(id: 'r-002', name: 'Pull Day'),
        ];
        final plan = _plan(routines: [_bucket(routineId: 'r-001', order: 1)]);

        await tester.pumpWidget(
          _build(plan: plan, routines: routines, trainingFrequency: 3),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('ready to go'),
          findsNothing,
          reason: 'Soft-cap hint should NOT appear when bucket < frequency',
        );
        expect(
          find.textContaining('1/3 planned this week'),
          findsOneWidget,
          reason: 'Counter should show "1/3 planned this week" below cap',
        );
      },
    );

    testWidgets(
      'shows "X/X planned -- ready to go" text when bucket count exceeds frequency',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Training frequency = 2, bucket has 3 routines => exceeds soft cap.
        // When at soft cap, uses trainingFrequency/trainingFrequency (not bucketCount).
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
          find.textContaining('2/2 planned'),
          findsOneWidget,
          reason:
              'Soft-cap hint should show "2/2 planned — ready to go" when over',
        );
      },
    );

    testWidgets('"Add Routine" button is present alongside soft-cap text', (
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
          _bucket(routineId: 'r-001', order: 1),
          _bucket(routineId: 'r-002', order: 2),
        ],
      );

      await tester.pumpWidget(
        _build(plan: plan, routines: routines, trainingFrequency: 2),
      );
      await tester.pumpAndSettle();

      // Both "Add Routine" and soft-cap text should be present.
      expect(find.text('Add Routine'), findsOneWidget);
      expect(find.textContaining('ready to go'), findsOneWidget);
    });
  });

  group('PlanManagementScreen empty state', () {
    testWidgets('shows Auto-fill button in empty state', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // No plan => empty state.
      final routines = [_routine(id: 'r-001', name: 'Push Day')];

      await tester.pumpWidget(
        _build(plan: null, routines: routines, trainingFrequency: 3),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Auto-fill'),
        findsOneWidget,
        reason: 'Empty state should show the auto-fill button',
      );
      expect(find.byIcon(Icons.repeat), findsOneWidget);
    });

    testWidgets(
      'shows both Add Routines and Auto-fill buttons in empty state',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final routines = [_routine(id: 'r-001', name: 'Push Day')];

        await tester.pumpWidget(
          _build(plan: null, routines: routines, trainingFrequency: 3),
        );
        await tester.pumpAndSettle();

        expect(find.text('Add Routines'), findsOneWidget);
        expect(find.text('Auto-fill'), findsOneWidget);
      },
    );

    testWidgets('Auto-fill button is an OutlinedButton', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final routines = [_routine(id: 'r-001', name: 'Push Day')];

      await tester.pumpWidget(
        _build(plan: null, routines: routines, trainingFrequency: 3),
      );
      await tester.pumpAndSettle();

      // The auto-fill button should be an OutlinedButton (not FilledButton).
      final outlinedButtons = find.byType(OutlinedButton);
      expect(outlinedButtons, findsOneWidget);
    });

    testWidgets('tapping Auto-fill button triggers the auto-fill action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final routines = [_routine(id: 'r-001', name: 'Push Day')];

      await tester.pumpWidget(
        _build(plan: null, routines: routines, trainingFrequency: 3),
      );
      await tester.pumpAndSettle();

      // Tapping should not throw; the auto-fill method handles the logic.
      await tester.tap(find.text('Auto-fill'));
      await tester.pumpAndSettle();

      // After auto-fill with 1 routine and freq=3, we expect 1 routine in the
      // bucket — the empty state should be gone and the routine should appear.
      expect(find.text('Push Day'), findsOneWidget);
      expect(find.text('No routines planned this week'), findsNothing);
    });
  });

  group('PlanManagementScreen edge cases', () {
    testWidgets(
      'trainingFrequency=0 shows "0/0 planned -- ready to go" without crashing',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Profile with trainingFrequencyPerWeek = 0 is a degenerate edge case.
        // The PlanAddRoutineRow counter must not crash (no division by zero).
        final routines = [_routine(id: 'r-001', name: 'Push Day')];
        final plan = _plan(routines: [_bucket(routineId: 'r-001', order: 1)]);

        await tester.pumpWidget(
          _build(plan: plan, routines: routines, trainingFrequency: 0),
        );
        await tester.pumpAndSettle();

        // With frequency=0 and 1 routine in bucket, atSoftCap is true (1 >= 0).
        // Counter shows "0/0 planned — ready to go" — no crash.
        expect(
          find.textContaining('ready to go'),
          findsOneWidget,
          reason:
              'With frequency=0, atSoftCap is always true; no crash expected',
        );
      },
    );

    testWidgets(
      'auto-fill with trainingFrequency=0 produces empty plan without crashing',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // With frequency=0, _autoFill takes 0 routines => empty plan.
        final routines = [_routine(id: 'r-001', name: 'Push Day')];

        await tester.pumpWidget(
          _build(plan: null, routines: routines, trainingFrequency: 0),
        );
        await tester.pumpAndSettle();

        // Tap Auto-fill — should not throw even though count=0.
        await tester.tap(find.text('Auto-fill'));
        await tester.pumpAndSettle();

        // Empty plan result: empty state stays since no routines were added.
        // Auto-fill with freq=0 selects 0 routines, leaving the bucket empty.
        expect(find.text('No routines planned this week'), findsOneWidget);
      },
    );
  });

  group('PlanManagementScreen analytics debouncing', () {
    testWidgets('fires week_plan_saved exactly once for a multi-edit session '
        '(auto-fill + remove + undo) — flushed on dispose', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final routines = [
        _routine(id: 'r-001', name: 'Push Day'),
        _routine(id: 'r-002', name: 'Pull Day'),
      ];

      final mockUser = _MockUser();
      when(() => mockUser.id).thenReturn('user-001');
      final mockAuth = _MockAuthRepository();
      when(() => mockAuth.currentUser).thenReturn(mockUser);

      final capturing = _CapturingAnalyticsRepository();

      // Pump screen in an empty state so we can drive edits.
      await tester.pumpWidget(
        _build(
          plan: null,
          routines: routines,
          trainingFrequency: 2,
          analytics: capturing,
          auth: mockAuth,
        ),
      );
      await tester.pumpAndSettle();

      // Edit 1: auto-fill — this fires _savePlan once.
      await tester.tap(find.text('Auto-fill'));
      await tester.pumpAndSettle();

      // Edit 2 + 3: remove a routine, then undo it. Each tap calls
      // _savePlan internally. Under the old code, this bucket of three
      // edits in a row would fire three week_plan_saved events; under
      // the debounced implementation they all roll up to one.
      await tester.drag(find.text('Push Day'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Undo the remove. Snackbar action label is "UNDO".
      final undoFinder = find.text('UNDO');
      if (undoFinder.evaluate().isNotEmpty) {
        await tester.tap(undoFinder);
        await tester.pumpAndSettle();
      }

      // So far: no analytics event should have been inserted — everything
      // is pending until dispose.
      expect(
        capturing.events,
        isEmpty,
        reason: 'week_plan_saved is debounced — it must not fire during edits',
      );

      // Tear down the screen. The dispose() hook should flush a single
      // event.
      await tester.pumpWidget(const TestMaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      final weekPlanSavedEvents = capturing.events
          .where((e) => e.name == 'week_plan_saved')
          .toList();
      expect(
        weekPlanSavedEvents,
        hasLength(1),
        reason:
            'Exactly one week_plan_saved event should flush at dispose, '
            'regardless of the number of edits in the session',
      );

      // The flushed event should reflect the most-recent session state —
      // used_autofill=true (because we auto-filled at some point in the
      // session) and routine_count equal to the current bucket size.
      final event = weekPlanSavedEvents.single;
      expect(event.props['used_autofill'], true);
    });

    testWidgets(
      'does NOT fire week_plan_saved on dispose when no edits were made',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final routines = [_routine(id: 'r-001', name: 'Push Day')];
        final plan = _plan(routines: [_bucket(routineId: 'r-001', order: 1)]);

        final mockUser = _MockUser();
        when(() => mockUser.id).thenReturn('user-001');
        final mockAuth = _MockAuthRepository();
        when(() => mockAuth.currentUser).thenReturn(mockUser);

        final capturing = _CapturingAnalyticsRepository();

        await tester.pumpWidget(
          _build(
            plan: plan,
            routines: routines,
            trainingFrequency: 3,
            analytics: capturing,
            auth: mockAuth,
          ),
        );
        await tester.pumpAndSettle();

        // No edits — just unmount.
        await tester.pumpWidget(const TestMaterialApp(home: SizedBox()));
        await tester.pumpAndSettle();

        final weekPlanSavedEvents = capturing.events
            .where((e) => e.name == 'week_plan_saved')
            .toList();
        expect(
          weekPlanSavedEvents,
          isEmpty,
          reason: 'No-op view of the plan screen must not fire week_plan_saved',
        );
      },
    );
  });

  // ----------------------------------------------------------------------
  // Fix 1A — Saved confirmation snackbar.
  //
  // The screen autosaves on every reorder/add/remove/undo/auto-fill via
  // `_savePlan`. Persistence is correct; user has no feedback. Show a
  // 1-second SnackBar saying "Saved" after each save, EXCEPT when an
  // undo snackbar is already showing — that affordance must not be
  // destroyed.
  // ----------------------------------------------------------------------
  group('PlanManagementScreen saved-confirmation snackbar (Fix 1A)', () {
    testWidgets(
      'shows "Saved" SnackBar after the debounced save flushes (auto-fill)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final routines = [_routine(id: 'r-001', name: 'Push Day')];

        await tester.pumpWidget(
          _build(plan: null, routines: routines, trainingFrequency: 1),
        );
        await tester.pumpAndSettle();

        // Edit: tap auto-fill, which triggers _savePlan → 300ms debounce →
        // _flushDebouncedSave → upsertPlan → "Saved" snackbar.
        await tester.tap(find.text('Auto-fill'));
        await tester.pump(const Duration(milliseconds: 50));
        // Advance past the debounce.
        await tester.pump(const Duration(milliseconds: 350));
        // Allow the upsertPlan future to resolve and the snackbar to mount.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.text('Saved'),
          findsOneWidget,
          reason:
              'After a successful upsertPlan, a 1s "Saved" SnackBar must appear '
              'so the user has visible feedback that their edit landed.',
        );
      },
    );

    testWidgets('does NOT replace the undo snackbar after _removeRoutine', (
      tester,
    ) async {
      // The undo snack lives 5s; if "Saved" hides+replaces it, the user
      // loses the undo affordance — explicitly forbidden by WIP.md.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final routines = [_routine(id: 'r-001', name: 'Push Day')];
      final plan = _plan(routines: [_bucket(routineId: 'r-001', order: 1)]);

      await tester.pumpWidget(
        _build(plan: plan, routines: routines, trainingFrequency: 3),
      );
      await tester.pumpAndSettle();

      // Trigger remove via swipe-dismiss.
      await tester.drag(find.text('Push Day'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      // The undo snackbar should be visible.
      expect(find.text('UNDO'), findsOneWidget);

      // Now advance past the save debounce. The Saved snackbar must NOT
      // replace the undo snackbar.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(
        find.text('UNDO'),
        findsOneWidget,
        reason:
            'Undo snack must remain visible — Saved snack is suppressed '
            'whenever an undo is active.',
      );
      expect(
        find.text('Saved'),
        findsNothing,
        reason: 'Saved snack must not replace the undo snack.',
      );
    });
  });
}
