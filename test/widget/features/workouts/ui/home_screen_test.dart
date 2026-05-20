/// Phase 26f HomeScreen smoke tests.
///
/// Asserts the canonical block order on Home and verifies the per-state
/// surfaces (collapsed character card, empty-bucket compact chip row,
/// confirmation banner). Deep contracts for each block live in dedicated
/// files (`character_card_test.dart`, `bucket_chip_row_test.dart`,
/// `encouragement_nudge_test.dart`, `home_screen_action_hero_test.dart`,
/// `home_screen_last_session_test.dart`, `home_screen_routines_test.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
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
import 'package:repsaga/shared/widgets/pending_sync_badge.dart';
import 'package:repsaga/shared/widgets/sync_failure_card.dart';
import 'package:repsaga/features/workouts/ui/home_screen.dart';
import 'package:repsaga/features/workouts/ui/widgets/action_hero.dart';
import 'package:repsaga/features/workouts/ui/widgets/bucket_chip_row.dart';
import 'package:repsaga/features/workouts/ui/widgets/character_card.dart';
import 'package:repsaga/features/workouts/ui/widgets/encouragement_nudge.dart';
import 'package:repsaga/features/workouts/ui/widgets/home_greeting.dart';
import 'package:repsaga/features/workouts/ui/widgets/last_session_line.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

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

Workout _workout({
  String id = 'w-001',
  String name = 'Push Day',
  required String finishedAt,
}) => Workout.fromJson(
  TestWorkoutFactory.create(id: id, name: name, finishedAt: finishedAt),
);

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

BodyPartSheetEntry _trained(
  BodyPart bp, {
  required int rank,
  required double xpInRank,
  required double xpForNextRank,
}) => BodyPartSheetEntry(
  bodyPart: bp,
  rank: rank,
  vitalityEwma: 100,
  vitalityPeak: 200,
  vitalityState: VitalityState.active,
  xpInRank: xpInRank,
  xpForNextRank: xpForNextRank,
  totalXp: 1000,
);

CharacterSheetState _trainedSheet() => CharacterSheetState(
  characterLevel: 14,
  lifetimeXp: 8420,
  xpForNextLevel: 12000,
  bodyPartProgress: [
    _trained(BodyPart.chest, rank: 16, xpInRank: 80, xpForNextRank: 100),
    _trained(BodyPart.back, rank: 11, xpInRank: 20, xpForNextRank: 100),
    _trained(BodyPart.legs, rank: 9, xpInRank: 18, xpForNextRank: 100),
    _untrained(BodyPart.shoulders),
    _untrained(BodyPart.arms),
    _untrained(BodyPart.core),
  ],
  activeTitle: 'Plate-Bearer',
  characterClass: CharacterClass.bulwark,
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

Widget _build({
  WeeklyPlan? plan,
  List<Routine> routines = const [],
  List<Workout> workouts = const [],
  Profile? profile = const Profile(
    id: 'user-001',
    displayName: 'Alex',
    weightUnit: 'kg',
  ),
  int workoutCount = 0,
  bool needsConfirmation = false,
  CharacterSheetState? sheet,
  int streak = 0,
}) {
  final pulseStorage = _MockPulseStorage();
  when(
    () => pulseStorage.isPulsing(any(), now: any(named: 'now')),
  ).thenReturn(false);

  final resolvedSheet = sheet ?? _dayZeroSheet();

  return ProviderScope(
    overrides: [
      weeklyPlanProvider.overrideWith(() => _PlanStub(plan)),
      weeklyPlanNeedsConfirmationProvider.overrideWith(
        (ref) => needsConfirmation,
      ),
      routineListProvider.overrideWith(() => _RoutineStub(routines)),
      workoutHistoryProvider.overrideWith(() => _HistoryStub(workouts)),
      workoutCountProvider.overrideWith((ref) => Future.value(workoutCount)),
      activeWorkoutProvider.overrideWith(() => _NullActiveWorkoutNotifier()),
      profileProvider.overrideWith(() => _ProfileStub(profile)),
      // HomeGreeting (Phase 27 L2) reads `currentUserEmailProvider` for its
      // displayName-fallback. Default to a deterministic test value so the
      // greeting always renders the profile's `displayName`; tests that
      // need to exercise the email-prefix fallback can override locally.
      currentUserEmailProvider.overrideWithValue('test@repsaga.test'),
      pendingSyncProvider.overrideWith(() => _ZeroPendingSyncNotifier()),
      characterSheetProvider.overrideWith((_) => AsyncData(resolvedSheet)),
      rankUpPulseLocalStorageProvider.overrideWithValue(pulseStorage),
      streakProvider.overrideWith((ref) => streak),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: HomeScreen()),
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

  group('HomeScreen - homeReadyProvider skeleton gate', () {
    testWidgets(
      'renders the skeleton (not HomeGreeting / ActionHero / BucketChipRow) '
      'while any critical-path provider is still loading, then swaps to '
      'the real tree on resolution',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Hold `workoutCountProvider` open via a Completer so the
        // `Future.wait` in `homeReadyProvider` cannot resolve.
        // Everything else resolves immediately; only the gate holds.
        final block = Completer<int>();
        final pulseStorage = _MockPulseStorage();
        when(
          () => pulseStorage.isPulsing(any(), now: any(named: 'now')),
        ).thenReturn(false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              weeklyPlanProvider.overrideWith(() => _PlanStub(null)),
              weeklyPlanNeedsConfirmationProvider.overrideWith((ref) => false),
              routineListProvider.overrideWith(() => _RoutineStub(const [])),
              workoutHistoryProvider.overrideWith(() => _HistoryStub(const [])),
              workoutCountProvider.overrideWith((ref) => block.future),
              activeWorkoutProvider.overrideWith(
                () => _NullActiveWorkoutNotifier(),
              ),
              profileProvider.overrideWith(
                () => _ProfileStub(
                  const Profile(
                    id: 'user-001',
                    displayName: 'Alex',
                    weightUnit: 'kg',
                  ),
                ),
              ),
              currentUserEmailProvider.overrideWithValue('test@repsaga.test'),
              pendingSyncProvider.overrideWith(
                () => _ZeroPendingSyncNotifier(),
              ),
              characterSheetProvider.overrideWith(
                (_) => AsyncData(_dayZeroSheet()),
              ),
              rankUpPulseLocalStorageProvider.overrideWithValue(pulseStorage),
              streakProvider.overrideWith((ref) => 0),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: HomeScreen()),
            ),
          ),
        );
        // Drain the resolved stubs but leave the blocked completer pending —
        // this is the user-visible state during cold mount with the slowest
        // critical provider mid-flight.
        await tester.pump();
        await tester.pump();

        // The four real widgets that watch critical providers MUST be
        // absent — they would render the wrong default state without the
        // gate (workoutCount → 0 → false day-0 branch; routines/plan →
        // empty bucket header; profile null → empty greeting name).
        expect(
          find.byType(HomeGreeting),
          findsNothing,
          reason:
              'HomeGreeting must be skeleton-gated; rendering it pre-resolve '
              'shows an empty name slot for ~300-800ms until profile loads.',
        );
        expect(
          find.byType(ActionHero),
          findsNothing,
          reason:
              'ActionHero must be skeleton-gated; pre-resolve `.value ?? 0` '
              'falsely satisfies the day-0 branch for returning users.',
        );
        expect(
          find.byType(BucketChipRow),
          findsNothing,
          reason:
              'BucketChipRow must be skeleton-gated; pre-resolve it renders '
              'an empty bucket under the "ESTA SEMANA" header.',
        );

        // PendingSyncBadge and SyncFailureCard MUST mount even while
        // the gate is loading — they're the offline / sync-failure
        // affordances the user needs precisely when a critical provider
        // is unreachable (network down → Supabase future never resolves
        // → gate hangs forever). QA-found regression (PR #244): the
        // initial skeleton-gate landing put these inside `_HomeBody`
        // which is gated, so going offline meant the user saw the
        // skeleton forever with no way to manage the sync queue.
        expect(
          find.byType(PendingSyncBadge),
          findsOneWidget,
          reason:
              'PendingSyncBadge must be rendered OUTSIDE the skeleton '
              'gate — the offline state IS the gate-hangs state, and '
              'the badge is the affordance the user needs in that '
              'state. Internal `SizedBox.shrink` handles the empty case.',
        );
        expect(
          find.byType(SyncFailureCard),
          findsOneWidget,
          reason:
              'SyncFailureCard must be rendered OUTSIDE the skeleton '
              'gate — same reasoning as PendingSyncBadge.',
        );

        // Resolve the blocked critical provider — `homeReadyProvider`
        // now completes, gate opens, real tree renders.
        block.complete(0);
        await tester.pump();
        await tester.pump();

        expect(find.byType(HomeGreeting), findsOneWidget);
        expect(find.byType(ActionHero), findsOneWidget);
        expect(find.byType(BucketChipRow), findsOneWidget);
        // PendingSyncBadge and SyncFailureCard are still present post-
        // hydrate — they were never removed, just sat above the gated
        // body the whole time.
        expect(find.byType(PendingSyncBadge), findsOneWidget);
        expect(find.byType(SyncFailureCard), findsOneWidget);
      },
    );
  });

  group('HomeScreen - canonical composition', () {
    testWidgets(
      'renders block order: Greeting → CharacterCard → Nudge → ActionHero → BucketChipRow → LastSession → RoutinesList',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        await tester.pumpWidget(
          _build(
            plan: _plan(
              routines: [
                _bucket(routineId: 'r-1', order: 1),
                _bucket(routineId: 'r-2', order: 2),
              ],
            ),
            routines: [
              _routine(id: 'r-1', name: 'Push Day', userId: 'user-001'),
              _routine(id: 'r-2', name: 'Pull Day', userId: 'user-001'),
            ],
            workouts: [_workout(finishedAt: yesterday.toIso8601String())],
            workoutCount: 1,
            sheet: _trainedSheet(),
          ),
        );
        // pump() — NOT pumpAndSettle(). CharacterCard's RuneHalo owns
        // infinite-loop AnimationControllers; pumpAndSettle would hang.
        await tester.pump();
        await tester.pump();

        // Each canonical block is on the tree exactly once.
        expect(find.byType(HomeGreeting), findsOneWidget);
        expect(find.byType(CharacterCard), findsOneWidget);
        expect(find.byType(EncouragementNudge), findsOneWidget);
        expect(find.byType(ActionHero), findsOneWidget);
        expect(find.byType(BucketChipRow), findsOneWidget);
        expect(find.byType(LastSessionLine), findsOneWidget);

        // Order check via vertical position in the rendered tree.
        Offset offsetOf<T extends Widget>() =>
            tester.getTopLeft(find.byType(T));

        final greetDy = offsetOf<HomeGreeting>().dy;
        final cardDy = offsetOf<CharacterCard>().dy;
        final nudgeDy = offsetOf<EncouragementNudge>().dy;
        final heroDy = offsetOf<ActionHero>().dy;
        final chipsDy = offsetOf<BucketChipRow>().dy;
        final lastDy = offsetOf<LastSessionLine>().dy;

        expect(greetDy, lessThan(cardDy));
        expect(cardDy, lessThan(nudgeDy));
        expect(nudgeDy, lessThan(heroDy));
        expect(heroDy, lessThan(chipsDy));
        expect(chipsDy, lessThan(lastDy));
      },
    );

    testWidgets('CharacterCard renders collapsed on first build', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_build(sheet: _trainedSheet()));
      await tester.pump();
      await tester.pump();

      // Chevron in collapsed orientation is on the tree. Expanded body's
      // CharacterXpBar is NOT yet mounted.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets(
      'empty bucket: BucketChipRow renders compact form (header + Editar plano), no chip wrap',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _build(plan: null, routines: const [], sheet: _trainedSheet()),
        );
        await tester.pump();
        await tester.pump();

        // BucketChipRow itself stays on the tree (Editar plano link is
        // always visible per DECISION LOCKED 2026-05-18).
        expect(find.byType(BucketChipRow), findsOneWidget);
        // Compact form: no chip Wrap renders because there are no bucket
        // entries. Asserting via the routine-name text guard.
        expect(find.text('Push Day'), findsNothing);
        expect(find.text('Pull Day'), findsNothing);
      },
    );

    testWidgets('active plan: routines list is hidden', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _build(
          plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
          routines: [
            _routine(id: 'r-1', name: 'Push', userId: 'user-001'),
            _routine(id: 'u-1', name: 'Private', userId: 'user-001'),
          ],
          workoutCount: 1,
          sheet: _trainedSheet(),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The MY ROUTINES section + See all pill are gated on the no-plan
      // branch — when an active plan exists, both must be absent.
      expect(find.text('MY ROUTINES'), findsNothing);
      expect(find.text('See all'), findsNothing);
    });

    testWidgets(
      'no plan + user routines: shows My Routines list (truncated to 3 + See all)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        await tester.pumpWidget(
          _build(
            plan: null,
            routines: [
              _routine(id: 'u-1', name: 'My Push', userId: 'user-001'),
              _routine(id: 'u-2', name: 'My Pull', userId: 'user-001'),
              _routine(id: 'u-3', name: 'My Legs', userId: 'user-001'),
              _routine(id: 'u-4', name: 'My Arms', userId: 'user-001'),
              _routine(id: 'u-5', name: 'My Shoulders', userId: 'user-001'),
            ],
            workouts: [_workout(finishedAt: yesterday.toIso8601String())],
            workoutCount: 1,
            sheet: _trainedSheet(),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Top 3 visible, 4th/5th hidden behind See all.
        expect(find.text('My Push'), findsOneWidget);
        expect(find.text('My Pull'), findsOneWidget);
        expect(find.text('My Legs'), findsOneWidget);
        expect(find.text('My Arms'), findsNothing);
        expect(find.text('My Shoulders'), findsNothing);
        expect(find.text('See all'), findsOneWidget);
      },
    );
  });

  group('HomeScreen - confirmation banner', () {
    testWidgets(
      'renders confirmation banner when weeklyPlanNeedsConfirmation is true',
      (tester) async {
        await tester.pumpWidget(
          _build(
            plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
            routines: [_routine(id: 'r-1', name: 'Push', userId: 'user-001')],
            workoutCount: 1,
            needsConfirmation: true,
            sheet: _trainedSheet(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Same plan this week?'), findsOneWidget);
      },
    );
  });
}
