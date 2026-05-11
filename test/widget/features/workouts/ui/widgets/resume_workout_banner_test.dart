import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/theme/app_icons.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/resume_workout_banner.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake notifier helpers
// ---------------------------------------------------------------------------

/// A minimal [ActiveWorkoutNotifier] that starts with a fixed state.
/// All mutations are no-ops — we only need state observation in these tests.
class _FakeActiveWorkoutNotifier extends ActiveWorkoutNotifier {
  _FakeActiveWorkoutNotifier(this._initial);

  final ActiveWorkoutState? _initial;

  @override
  Future<ActiveWorkoutState?> build() async => _initial;
}

// ---------------------------------------------------------------------------
// Test fixture helpers
// ---------------------------------------------------------------------------

Workout _makeWorkout({String name = 'Test Workout'}) => Workout(
  id: 'workout-001',
  userId: 'user-001',
  name: name,
  startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
  isActive: true,
  createdAt: DateTime.now().toUtc(),
);

ActiveWorkoutState _makeStateNoExercises({String name = 'Test Workout'}) =>
    ActiveWorkoutState(
      workout: _makeWorkout(name: name),
      exercises: const [],
    );

ActiveWorkoutState _makeStateWithExercises({String name = 'Test Workout'}) =>
    ActiveWorkoutState(
      workout: _makeWorkout(name: name),
      exercises: const [
        ActiveWorkoutExercise(
          workoutExercise: WorkoutExercise(
            id: 'we-001',
            workoutId: 'workout-001',
            exerciseId: 'exercise-001',
            order: 0,
          ),
          sets: [],
        ),
      ],
    );

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget buildBanner(
  ActiveWorkoutState? activeState, {
  Duration elapsed = Duration.zero,
  GoRouter? router,
}) {
  final effectiveRouter =
      router ??
      GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: SingleChildScrollView(
                child: Column(children: [ResumeWorkoutBanner()]),
              ),
            ),
          ),
          GoRoute(
            path: '/workout/active',
            builder: (context, state) =>
                const Scaffold(body: Text('Active Workout')),
          ),
        ],
      );

  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FakeActiveWorkoutNotifier(activeState),
      ),
      // Override elapsed timer so it doesn't start real periodic streams.
      elapsedTimerProvider.overrideWith(
        (ref, startedAt) => Stream.value(elapsed),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark,
      routerConfig: effectiveRouter,
    ),
  );
}

// ---------------------------------------------------------------------------
// Asset finders
// ---------------------------------------------------------------------------

/// Finder for the [AppIcons.lift] SVG asset rendered inside the banner.
/// `flutter_svg`'s `SvgPicture.asset(...)` uses an `ExactAssetPicture`
/// loader keyed by the same path string we passed to [AppIcons.render]; a
/// substring match on `toString()` is the cheapest stable way to assert
/// "this exact asset is mounted" in widget tests without reaching into
/// private SvgPicture internals.
Finder _findLiftSvg() => find.byWidgetPredicate(
  (widget) =>
      widget is SvgPicture &&
      widget.bytesLoader.toString().contains('lift.svg'),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ResumeWorkoutBanner', () {
    group('renders nothing when', () {
      testWidgets('activeWorkoutProvider returns null', (tester) async {
        await tester.pumpWidget(buildBanner(null));
        await tester.pump(); // let async provider settle

        expect(find.byType(GestureDetector), findsNothing);
        expect(_findLiftSvg(), findsNothing);
      });

      testWidgets('active workout has zero exercises', (tester) async {
        await tester.pumpWidget(buildBanner(_makeStateNoExercises()));
        await tester.pump();

        expect(_findLiftSvg(), findsNothing);
        expect(find.text('Test Workout'), findsNothing);
      });
    });

    group('renders banner when active workout has exercises', () {
      testWidgets('shows workout name', (tester) async {
        await tester.pumpWidget(
          buildBanner(_makeStateWithExercises(name: 'Push Day')),
        );
        await tester.pump();

        expect(find.text('Push Day'), findsOneWidget);
      });

      // PR-7 brand-glyph swap: pre-fix this asserted the generic Material
      // `Icons.fitness_center` (typical AI fitness UI). Post-fix the banner
      // renders `AppIcons.lift` — the app's signature Game-Icons silhouette
      // and the same asset used everywhere a workout-in-progress is
      // surfaced (continuity glyph, not a separate Material widget).
      // Regression-pin: also assert `Icons.fitness_center` is gone so a
      // future revert can't silently land.
      testWidgets('shows AppIcons.lift brand glyph (not fitness_center)', (
        tester,
      ) async {
        await tester.pumpWidget(buildBanner(_makeStateWithExercises()));
        await tester.pump();

        expect(_findLiftSvg(), findsOneWidget);
        expect(find.byIcon(Icons.fitness_center), findsNothing);
      });

      testWidgets('shows chevron_right icon', (tester) async {
        await tester.pumpWidget(buildBanner(_makeStateWithExercises()));
        await tester.pump();

        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets('shows elapsed time formatted as MM:SS', (tester) async {
        await tester.pumpWidget(
          buildBanner(
            _makeStateWithExercises(),
            elapsed: const Duration(minutes: 5, seconds: 30),
          ),
        );
        // Pump twice: first to build, second to resolve the StreamProvider.
        await tester.pump();
        await tester.pump();

        expect(find.text('05:30'), findsOneWidget);
      });

      testWidgets(
        'shows elapsed time formatted as H:MM:SS for durations >= 1 hour',
        (tester) async {
          await tester.pumpWidget(
            buildBanner(
              _makeStateWithExercises(),
              elapsed: const Duration(hours: 1, minutes: 2, seconds: 3),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.text('1:02:03'), findsOneWidget);
        },
      );
    });

    group('tap behaviour', () {
      testWidgets('tapping banner navigates to /workout/active', (
        tester,
      ) async {
        await tester.pumpWidget(buildBanner(_makeStateWithExercises()));
        await tester.pump();

        await tester.tap(find.byType(GestureDetector));
        await tester.pumpAndSettle();

        expect(find.text('Active Workout'), findsOneWidget);
      });
    });
  });
}
