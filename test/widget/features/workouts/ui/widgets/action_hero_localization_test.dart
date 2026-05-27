/// Widget tests for ActionHero eyebrow localization.
///
/// Phase 32 PR 32a: the three hardcoded uppercase Portuguese eyebrow labels
/// (`INICIAR`, `TREINO LIVRE`, `BEM-VINDO`) are now driven through ARB
/// (`homeActionHeroStartEyebrow`, `homeActionHeroFreeEyebrow`,
/// `homeActionHeroWelcomeEyebrow`). These tests pin the visible eyebrow text
/// across both en and pt locales — if a future change drops the ARB read
/// back to a string literal, the pt variant goes back to leaking
/// Portuguese into the en build (or vice versa) and the wrong assertion
/// fires here.
///
/// Branches under test (one widget test per branch × 2 locales = 6):
///   * `_StartNextRoutineHero`     → suggestedNextProvider != null
///   * `_FreeWorkoutHero`          → suggestedNextProvider == null,
///                                   workoutCount > 0 OR userRoutines non-empty
///   * `_CreateFirstRoutineHero`   → workoutCount == 0 AND no user routines
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/suggested_next_provider.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/action_hero.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

Routine _userRoutine() => Routine(
  id: 'r-user-1',
  userId: 'user-1',
  name: 'My Push Day',
  isDefault: false,
  exercises: const <RoutineExercise>[],
  createdAt: DateTime(2026, 1, 1),
);

BucketRoutine _bucketEntry() => const BucketRoutine(
  routineId: 'r-user-1',
  order: 1,
  completedAt: null,
  completedWorkoutId: null,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _StubRoutineListNotifier extends RoutineListNotifier {
  _StubRoutineListNotifier(this._routines);
  final List<Routine> _routines;
  @override
  Future<List<Routine>> build() async => _routines;
}

/// Build a ProviderScope-wrapped ActionHero driven into the requested branch.
///
/// `workoutCount` + `userRoutines` + `suggestedNext` together determine
/// which branch renders. The harness exposes them as required parameters so
/// each test reads as a self-contained scenario.
Widget _harness({
  required int workoutCount,
  required List<Routine> userRoutines,
  required BucketRoutine? suggestedNext,
  bool weekComplete = false,
  Locale locale = const Locale('en'),
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: ActionHero()),
      ),
      // /routines/create is reachable from the CreateFirstRoutine branch's
      // onTap — registered so a stray tap during pump doesn't crash the
      // navigator with "no matching route".
      GoRoute(
        path: '/routines/create',
        builder: (context, state) =>
            const Scaffold(body: Text('routines-create-route')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      workoutCountProvider.overrideWith((ref) async => workoutCount),
      routineListProvider.overrideWith(
        () => _StubRoutineListNotifier(userRoutines),
      ),
      suggestedNextProvider.overrideWith((ref) => suggestedNext),
      isWeekCompleteProvider.overrideWith((ref) => weekComplete),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ActionHero eyebrow l10n', () {
    // ---------------------------------------------------------------------
    // _CreateFirstRoutineHero — "WELCOME" / "BEM-VINDO"
    // Branch trigger: workoutCount == 0 AND no user-owned non-default routines
    // ---------------------------------------------------------------------
    testWidgets('shows WELCOME eyebrow for day-0 user in en locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          workoutCount: 0,
          userRoutines: const <Routine>[],
          suggestedNext: null,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WELCOME'), findsOneWidget);
      expect(find.text('BEM-VINDO'), findsNothing);
    });

    testWidgets('shows BEM-VINDO eyebrow for day-0 user in pt locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          workoutCount: 0,
          userRoutines: const <Routine>[],
          suggestedNext: null,
          locale: const Locale('pt'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BEM-VINDO'), findsOneWidget);
      expect(find.text('WELCOME'), findsNothing);
    });

    // ---------------------------------------------------------------------
    // _FreeWorkoutHero — "FREE WORKOUT" / "TREINO LIVRE"
    // Branch trigger: workoutCount > 0, no suggested next, no week-complete state
    // ---------------------------------------------------------------------
    testWidgets('shows FREE WORKOUT eyebrow when no bucket entry in en', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          workoutCount: 3,
          userRoutines: <Routine>[_userRoutine()],
          suggestedNext: null,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FREE WORKOUT'), findsOneWidget);
      expect(find.text('TREINO LIVRE'), findsNothing);
    });

    testWidgets('shows TREINO LIVRE eyebrow when no bucket entry in pt', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          workoutCount: 3,
          userRoutines: <Routine>[_userRoutine()],
          suggestedNext: null,
          locale: const Locale('pt'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TREINO LIVRE'), findsOneWidget);
      expect(find.text('FREE WORKOUT'), findsNothing);
    });

    // ---------------------------------------------------------------------
    // _StartNextRoutineHero — "START" / "INICIAR"
    // Branch trigger: suggestedNext != null AND routine resolves in routineListProvider
    // ---------------------------------------------------------------------
    testWidgets('shows START eyebrow when bucket entry resolves in en', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          workoutCount: 3,
          userRoutines: <Routine>[_userRoutine()],
          suggestedNext: _bucketEntry(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('START'), findsOneWidget);
      expect(find.text('INICIAR'), findsNothing);
    });

    testWidgets('shows INICIAR eyebrow when bucket entry resolves in pt', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          workoutCount: 3,
          userRoutines: <Routine>[_userRoutine()],
          suggestedNext: _bucketEntry(),
          locale: const Locale('pt'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('INICIAR'), findsOneWidget);
      expect(find.text('START'), findsNothing);
    });
  });
}
