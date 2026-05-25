/// Widget tests for [PostWorkoutNavigator.navigateAfterFinish] — 3-way branch.
///
/// **Branches under test (post-PR-30c contract):**
///   1. `userTappedOverflow = true`  → context.go('/profile')
///   2. `shouldPrompt = true`        → showAddToPlanPrompt dialog appears
///   3. else (both false)            → context.go('/home')
///
/// Also tests [PostWorkoutNavigator.shouldShowPlanPrompt]:
///   - null routineId → false
///   - routine already in plan → false
///   - routine NOT in plan → true
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/workouts/ui/coordinators/post_workout_navigator.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _routineId = 'routine-abc';
const _routineName = 'My Routine';

WeeklyPlan _planWithoutRoutine() => WeeklyPlan(
  id: 'plan-001',
  userId: 'user-001',
  weekStart: DateTime(2026, 5, 19),
  routines: const [],
  createdAt: DateTime(2026, 5, 19),
  updatedAt: DateTime(2026, 5, 19),
);

WeeklyPlan _planWithRoutine() => WeeklyPlan(
  id: 'plan-001',
  userId: 'user-001',
  weekStart: DateTime(2026, 5, 19),
  routines: const [BucketRoutine(routineId: _routineId, order: 0)],
  createdAt: DateTime(2026, 5, 19),
  updatedAt: DateTime(2026, 5, 19),
);

// ---------------------------------------------------------------------------
// Fake notifier
// ---------------------------------------------------------------------------

class _FakeWeeklyPlanNotifier extends AsyncNotifier<WeeklyPlan?>
    implements WeeklyPlanNotifier {
  _FakeWeeklyPlanNotifier(this._plan);
  final WeeklyPlan _plan;

  @override
  Future<WeeklyPlan?> build() async => _plan;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Harness for navigateAfterFinish Branches 1 and 3
//
// Strategy: trigger navigateAfterFinish from INSIDE the widget tree via a
// button press so the BuildContext passed to it is the live context from
// within the GoRouter subtree. This mirrors the production pattern: the
// coordinator is invoked from an onPressed callback in a ConsumerStateful-
// Widget, not from test code external to the tree.
// ---------------------------------------------------------------------------

/// Parameters fed into navigateAfterFinish by the test harness button.
class _NavigationParams {
  const _NavigationParams({
    required this.userTappedOverflow,
    required this.shouldPrompt,
  });
  final bool userTappedOverflow;
  final bool shouldPrompt;
}

/// Builds the harness. The `/start` route renders a button labelled
/// 'trigger-nav'. Tapping it calls [navigateAfterFinish] with [params].
/// Destination routes render distinctive Text widgets so tests can assert
/// the correct screen appeared.
Widget _buildNavigationHarness(_NavigationParams params) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => _TriggerButton(params: params),
      ),
      GoRoute(
        path: '/home',
        builder: (_, state) => const Scaffold(body: Text('Destination: home')),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, state) =>
            const Scaffold(body: Text('Destination: profile')),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

class _TriggerButton extends StatelessWidget {
  const _TriggerButton({required this.params});
  final _NavigationParams params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        key: const ValueKey('trigger-nav'),
        onPressed: () {
          const PostWorkoutNavigator().navigateAfterFinish(
            rootContext: context,
            userTappedOverflow: params.userTappedOverflow,
            shouldPrompt: params.shouldPrompt,
            routineId: null,
            routineName: null,
          );
        },
        child: const Text('Trigger'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PostWorkoutNavigator.navigateAfterFinish — 3-way branch', () {
    testWidgets('Branch 1: userTappedOverflow=true → navigates to /profile', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildNavigationHarness(
          const _NavigationParams(
            userTappedOverflow: true,
            shouldPrompt: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger navigateAfterFinish from inside the GoRouter subtree.
      await tester.tap(find.byKey(const ValueKey('trigger-nav')));

      // Drive the addPostFrameCallback + GoRouter route transition.
      await tester.pumpAndSettle();

      expect(
        find.text('Destination: profile'),
        findsOneWidget,
        reason:
            'userTappedOverflow=true MUST route to /profile (Saga). '
            'If this text is missing, the branch did not call '
            'rootContext.go(\'/profile\').',
      );
      expect(
        find.text('Destination: home'),
        findsNothing,
        reason: '/home must NOT be rendered when userTappedOverflow=true.',
      );
    });

    testWidgets(
      'Branch 3 (default): userTappedOverflow=false, shouldPrompt=false '
      '→ navigates to /home',
      (tester) async {
        await tester.pumpWidget(
          _buildNavigationHarness(
            const _NavigationParams(
              userTappedOverflow: false,
              shouldPrompt: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('trigger-nav')));
        await tester.pumpAndSettle();

        expect(
          find.text('Destination: home'),
          findsOneWidget,
          reason:
              'Default branch (both false) MUST route to /home. '
              'Canonical destination for offline finishes and regular sessions '
              'that skip the post-session cinematic.',
        );
        expect(
          find.text('Destination: profile'),
          findsNothing,
          reason: '/profile must NOT be rendered in the default branch.',
        );
      },
    );

    testWidgets(
      'Branch 2: shouldPrompt=true → showAddToPlanPrompt bottom sheet appears',
      (tester) async {
        // Branch 2: showPlanPromptAndGoHome is called fire-and-forget inside
        // the addPostFrameCallback. We test showPlanPromptAndGoHome directly
        // (it's the single-line call in the branch) using a plain MaterialApp
        // context because GoRouter's nested context does not expose the root
        // Material navigator needed by showModalBottomSheet.
        BuildContext? capturedContext;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              weeklyPlanProvider.overrideWith(
                () => _FakeWeeklyPlanNotifier(_planWithoutRoutine()),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) {
                  capturedContext = context;
                  return const Scaffold(body: Text('Home'));
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(capturedContext, isNotNull);

        const nav = PostWorkoutNavigator();
        unawaited(
          nav.showPlanPromptAndGoHome(
            capturedContext!,
            _routineId,
            _routineName,
          ),
        );

        await tester.pumpAndSettle();

        // The ModalBottomSheet must be in the tree.
        expect(
          find.byType(BottomSheet),
          findsOneWidget,
          reason:
              'showPlanPromptAndGoHome must open a ModalBottomSheet. '
              'If not found, the shouldPrompt branch did not call '
              'showModalBottomSheet.',
        );

        // Routine name must appear in the localized prompt string.
        expect(
          find.textContaining(_routineName),
          findsOneWidget,
          reason:
              'The sheet must contain "$_routineName" inside the '
              'localized prompt string.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // shouldShowPlanPrompt
  // ---------------------------------------------------------------------------

  group('PostWorkoutNavigator.shouldShowPlanPrompt', () {
    testWidgets('returns false when routineId is null', (tester) async {
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyPlanProvider.overrideWith(
              () => _FakeWeeklyPlanNotifier(_planWithoutRoutine()),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  key: const ValueKey('probe'),
                  onPressed: () {
                    result = const PostWorkoutNavigator().shouldShowPlanPrompt(
                      ref,
                      null,
                    );
                  },
                  child: const Text('Probe'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('probe')));
      await tester.pump();

      expect(
        result,
        isFalse,
        reason:
            'shouldShowPlanPrompt must return false when routineId is null '
            '(free/spontaneous workout).',
      );
    });

    testWidgets('returns false when the routine is already in the plan', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyPlanProvider.overrideWith(
              () => _FakeWeeklyPlanNotifier(_planWithRoutine()),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  key: const ValueKey('probe'),
                  onPressed: () {
                    result = const PostWorkoutNavigator().shouldShowPlanPrompt(
                      ref,
                      _routineId,
                    );
                  },
                  child: const Text('Probe'),
                );
              },
            ),
          ),
        ),
      );

      // Resolve AsyncNotifier before probing — .value is null during
      // AsyncLoading (shouldShowPlanPrompt returns false prematurely).
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('probe'))),
      );
      await container.read(weeklyPlanProvider.future);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('probe')));
      await tester.pump();

      expect(
        result,
        isFalse,
        reason:
            'shouldShowPlanPrompt must return false when the routine is '
            'already in the weekly plan.',
      );
    });

    testWidgets(
      'returns true when a plan exists and the routine is NOT in the plan',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              weeklyPlanProvider.overrideWith(
                () => _FakeWeeklyPlanNotifier(_planWithoutRoutine()),
              ),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    key: const ValueKey('probe'),
                    onPressed: () {
                      result = const PostWorkoutNavigator()
                          .shouldShowPlanPrompt(ref, _routineId);
                    },
                    child: const Text('Probe'),
                  );
                },
              ),
            ),
          ),
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('probe'))),
        );
        await container.read(weeklyPlanProvider.future);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('probe')));
        await tester.pump();

        expect(
          result,
          isTrue,
          reason:
              'shouldShowPlanPrompt must return true when a plan exists '
              'AND the routine is NOT yet in the plan.',
        );
      },
    );
  });
}
