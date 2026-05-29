/// Widget tests for the editorial Last Session line on Home.
///
/// Per PLAN W8: replaces the old two-cell stat grid. It is a single-line
/// editorial text - no card chrome - that reads
/// "Last: {routineName}, {relativeDate}" and navigates to /home/history
/// on tap. Hidden when no workout history exists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/last_session_line.dart';

import '../../../../fixtures/test_factories.dart';
import 'package:repsaga/l10n/app_localizations.dart';

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

Workout _workout({required String name, required String finishedAt}) =>
    Workout.fromJson(
      TestWorkoutFactory.create(name: name, finishedAt: finishedAt),
    );

Widget _buildWithRouter({required List<Workout> workouts}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, _) => const Scaffold(body: LastSessionLine()),
        routes: [
          GoRoute(
            path: 'history',
            builder: (ctx, _) =>
                const Scaffold(body: Center(child: Text('History Screen'))),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      workoutHistoryProvider.overrideWith(() => _HistoryStub(workouts)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

void main() {
  group('LastSessionLine - hidden when no history', () {
    testWidgets('collapses to SizedBox.shrink with no workouts', (
      tester,
    ) async {
      await tester.pumpWidget(_buildWithRouter(workouts: const []));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Last:'), findsNothing);
      expect(find.textContaining('Last session'), findsNothing);
    });
  });

  group('LastSessionLine - shows routine + relative date', () {
    testWidgets('renders "Last: {name}, {relativeDate}" for a recent workout', (
      tester,
    ) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        _buildWithRouter(
          workouts: [
            _workout(name: 'Push Day', finishedAt: yesterday.toIso8601String()),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // The line renders in a single Text widget; look for the full format.
      expect(find.textContaining('Last:'), findsOneWidget);
      expect(find.textContaining('Push Day'), findsOneWidget);
      expect(find.textContaining('Yesterday'), findsOneWidget);
    });

    testWidgets('uses "Today" for same-day workout', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        _buildWithRouter(
          workouts: [
            _workout(name: 'Leg Day', finishedAt: now.toIso8601String()),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Today'), findsOneWidget);
      expect(find.textContaining('Leg Day'), findsOneWidget);
    });

    testWidgets('uses "3 days ago" for older workouts', (tester) async {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      await tester.pumpWidget(
        _buildWithRouter(
          workouts: [
            _workout(
              name: 'Pull Day',
              finishedAt: threeDaysAgo.toIso8601String(),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('3 days ago'), findsOneWidget);
    });
  });

  group('LastSessionLine - navigation', () {
    testWidgets('tapping navigates to /home/history via push', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        _buildWithRouter(
          workouts: [
            _workout(name: 'Push', finishedAt: yesterday.toIso8601String()),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byType(LastSessionLine));
      await tester.pumpAndSettle();

      expect(find.text('History Screen'), findsOneWidget);

      // Verify push semantics - home is still below history in the stack.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      expect(nav.canPop(), isTrue);
    });
  });
}
