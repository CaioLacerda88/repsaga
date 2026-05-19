/// Widget tests for [BucketChipRow].
///
/// Covers ten cases:
///   1. Empty bucket: header + Editar plano link, no chip wrap.
///   2. Chip render order: planned (by `order` ascending) → spontaneous
///      appended in completion order.
///   3. Done planned chip shows day-of-week meta.
///   4. Pending chip text uses `AppColors.textDim`.
///   5. Spontaneous chip carries the localized badge text.
///   6. Tap chip opens the existing routine action sheet (the pre-workout
///      preview surface in this codebase).
///   7. Tap "Editar plano →" navigates to `/plan/week`.
///   8. Header progress counts UNIQUE completion days (two chips finished
///      on the same Monday + one on Wednesday → "2 days trained").
///   9. The Editar plano link is present in every state variant
///      (empty, partial, all-complete).
///  10. Chip with completedWorkoutId set but completedAt null renders
///      without crashing and without day-of-week meta (CH1 — I1 fix).
///
/// Harness pattern follows `character_card_test.dart`: real [GoRouter]
/// with placeholder routes for `/plan/week`, [ProviderScope] overrides
/// for `weeklyPlanProvider` + `routineListProvider`. `pumpAndSettle` is
/// safe here — the chip row has no infinite-loop animations.
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
import 'package:repsaga/features/workouts/ui/widgets/bucket_chip_row.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

Routine _routine(String id, String name) => Routine(
  id: id,
  name: name,
  isDefault: false,
  exercises: const <RoutineExercise>[],
  createdAt: DateTime(2026, 1, 1),
);

BucketRoutine _planned(
  String routineId, {
  required int order,
  DateTime? completedAt,
}) => BucketRoutine(
  routineId: routineId,
  order: order,
  completedAt: completedAt,
  completedWorkoutId: completedAt != null ? 'w-$routineId' : null,
);

BucketRoutine _spontaneous(
  String routineId, {
  required int order,
  required DateTime completedAt,
}) => BucketRoutine(
  routineId: routineId,
  order: order,
  completedAt: completedAt,
  completedWorkoutId: 'w-$routineId',
  isSpontaneous: true,
);

WeeklyPlan _plan(List<BucketRoutine> routines) => WeeklyPlan(
  id: 'plan-1',
  userId: 'user-1',
  weekStart: DateTime(2026, 5, 18),
  routines: routines,
  createdAt: DateTime(2026, 5, 18),
  updatedAt: DateTime(2026, 5, 18),
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _harness({
  required WeeklyPlan? plan,
  required List<Routine> routines,
  Locale locale = const Locale('en'),
  double width = 360,
  ValueChanged<String>? onRoute,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Center(
            child: SizedBox(width: width, child: const BucketChipRow()),
          ),
        ),
      ),
      GoRoute(
        path: '/plan/week',
        pageBuilder: (context, state) {
          onRoute?.call('/plan/week');
          return const NoTransitionPage(
            child: Scaffold(body: Text('plan-week-route')),
          );
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      weeklyPlanProvider.overrideWith(() => _StubWeeklyPlanNotifier(plan)),
      routineListProvider.overrideWith(
        () => _StubRoutineListNotifier(routines),
      ),
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

class _StubWeeklyPlanNotifier extends WeeklyPlanNotifier {
  _StubWeeklyPlanNotifier(this._plan);
  final WeeklyPlan? _plan;
  @override
  Future<WeeklyPlan?> build() async => _plan;
}

class _StubRoutineListNotifier extends RoutineListNotifier {
  _StubRoutineListNotifier(this._routines);
  final List<Routine> _routines;
  @override
  Future<List<Routine>> build() async => _routines;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BucketChipRow', () {
    testWidgets(
      'empty bucket: shows header + Editar plano link, no chip wrap',
      (tester) async {
        await tester.pumpWidget(
          _harness(plan: _plan(const []), routines: const []),
        );
        await tester.pumpAndSettle();

        // Header rendered (uppercased per mockup CSS).
        expect(find.text('THIS WEEK'), findsOneWidget);
        // Edit plan link rendered.
        expect(find.text('EDIT PLAN →'), findsOneWidget);
        // No chip Wrap rendered.
        expect(find.byType(Wrap), findsNothing);
      },
    );

    testWidgets(
      'renders chips in order: planned (by order asc) then spontaneous '
      'in completion order',
      (tester) async {
        final mon = DateTime(2026, 5, 18, 9); // Monday
        final wed = DateTime(2026, 5, 20, 9); // Wednesday
        final fri = DateTime(2026, 5, 22, 9); // Friday

        final plan = _plan([
          // Out of source order — should sort by `order` ascending.
          _planned('r-pull', order: 2, completedAt: null),
          _planned('r-push', order: 1, completedAt: mon),
          _planned('r-legs', order: 3, completedAt: null),
          // Spontaneous (planned `order` > planned count by convention, but the
          // widget filters by `isSpontaneous` not by order). Two of them — the
          // earlier completion comes first.
          _spontaneous('r-spont-b', order: 5, completedAt: fri),
          _spontaneous('r-spont-a', order: 4, completedAt: wed),
        ]);

        await tester.pumpWidget(
          _harness(
            plan: plan,
            routines: [
              _routine('r-push', 'Push'),
              _routine('r-pull', 'Pull'),
              _routine('r-legs', 'Legs'),
              _routine('r-spont-a', 'Cardio'),
              _routine('r-spont-b', 'Mobility'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Five chips total — each anchored by its routineId-suffixed semantics
        // identifier and rendering the routine name.
        final names = find.descendant(
          of: find.byType(Wrap),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                {'Push', 'Pull', 'Legs', 'Cardio', 'Mobility'}.contains(w.data),
          ),
        );
        final widgets = tester.widgetList<Text>(names).toList();
        // Order: Push (order 1), Pull (order 2), Legs (order 3), then
        // spontaneous by completion order: Cardio (Wed) before Mobility (Fri).
        expect(widgets.map((t) => t.data).toList(), [
          'Push',
          'Pull',
          'Legs',
          'Cardio',
          'Mobility',
        ]);
      },
    );

    testWidgets('done chip shows day-of-week meta', (tester) async {
      // Monday completion → en locale renders "Mon" via DateFormat.E.
      final mon = DateTime(2026, 5, 18, 9);
      final plan = _plan([_planned('r-push', order: 1, completedAt: mon)]);
      await tester.pumpWidget(
        _harness(plan: plan, routines: [_routine('r-push', 'Push')]),
      );
      await tester.pumpAndSettle();

      // Day-of-week meta uppercased per mockup. DateFormat.E in en
      // emits "Mon" for Monday → uppercased "MON".
      expect(find.text('MON'), findsOneWidget);
    });

    testWidgets('pending chip uses textDim for the routine name', (
      tester,
    ) async {
      final plan = _plan([_planned('r-push', order: 1, completedAt: null)]);
      await tester.pumpWidget(
        _harness(plan: plan, routines: [_routine('r-push', 'Push')]),
      );
      await tester.pumpAndSettle();

      final nameText = tester.widget<Text>(find.text('Push'));
      expect(nameText.style?.color, AppColors.textDim);
    });

    testWidgets('spontaneous chip carries localized badge', (tester) async {
      final wed = DateTime(2026, 5, 20, 9);
      final plan = _plan([_spontaneous('r-spont', order: 1, completedAt: wed)]);
      await tester.pumpWidget(
        _harness(plan: plan, routines: [_routine('r-spont', 'Cardio')]),
      );
      await tester.pumpAndSettle();

      // Localized badge text rendered in the chip body (en → "Free").
      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('tap chip opens the routine action sheet', (tester) async {
      final plan = _plan([_planned('r-push', order: 1, completedAt: null)]);
      await tester.pumpWidget(
        _harness(plan: plan, routines: [_routine('r-push', 'Push')]),
      );
      await tester.pumpAndSettle();

      // Tap the chip — finds the InkWell inside the named chip.
      final chipName = find.text('Push');
      expect(chipName, findsOneWidget);
      await tester.tap(chipName);
      await tester.pumpAndSettle();

      // The action sheet opens — for non-default routines, "Edit" + "Delete"
      // list tiles render. Their presence proves the sheet mounted.
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('tap "Editar plano" navigates to /plan/week', (tester) async {
      String? lastRoute;
      final plan = _plan([_planned('r-push', order: 1, completedAt: null)]);
      await tester.pumpWidget(
        _harness(
          plan: plan,
          routines: [_routine('r-push', 'Push')],
          onRoute: (route) => lastRoute = route,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EDIT PLAN →'));
      await tester.pumpAndSettle();

      expect(lastRoute, '/plan/week');
      expect(find.text('plan-week-route'), findsOneWidget);
    });

    testWidgets('header progress shows UNIQUE completion-day count', (
      tester,
    ) async {
      // Two chips on the same Monday + one on Wednesday → 2 unique days.
      final monMorning = DateTime(2026, 5, 18, 8);
      final monEvening = DateTime(2026, 5, 18, 19);
      final wed = DateTime(2026, 5, 20, 9);

      final plan = _plan([
        _planned('r-push', order: 1, completedAt: monMorning),
        _spontaneous('r-spont', order: 2, completedAt: monEvening),
        _planned('r-pull', order: 3, completedAt: wed),
      ]);

      await tester.pumpWidget(
        _harness(
          plan: plan,
          routines: [
            _routine('r-push', 'Push'),
            _routine('r-pull', 'Pull'),
            _routine('r-spont', 'Cardio'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // en plural for count=2: "2 days trained".
      expect(find.text('2 days trained'), findsOneWidget);
      // Sanity: NOT the routine-count form.
      expect(find.text('3 days trained'), findsNothing);
    });

    testWidgets(
      'chip with completedWorkoutId set but completedAt null renders without '
      'crashing (CH1 — I1 fix: server delivers workoutId without timestamp)',
      (tester) async {
        // Edge case pinned by reviewer finding CH1: server can return a
        // BucketRoutine where `completedWorkoutId` is non-null but
        // `completedAt` is null (partial server response / race). The
        // `_BucketChip._isDone` gate is true (workoutId present), which
        // previously crashed when it attempted `_shortDayLabel(null!, ...)`.
        // The I1 fix added an explicit null guard:
        //   `final dayLabel = (_isDone && entry.completedAt != null) ? ...`
        // This test pins that contract so a future refactor cannot re-introduce
        // the crash.
        const buggyEntry = BucketRoutine(
          routineId: 'rid-1',
          order: 0,
          completedWorkoutId: 'wid-1',
          completedAt: null, // explicit null — the edge case
          isSpontaneous: false,
        );
        final plan = _plan([buggyEntry]);

        await tester.pumpWidget(
          _harness(plan: plan, routines: [_routine('rid-1', 'Push')]),
        );
        await tester.pumpAndSettle();

        // Chip renders — the widget didn't throw.
        expect(find.text('Push'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Day-of-week meta NOT present — no label to derive from null timestamp.
        // All three-letter weekday abbreviations (en locale) that could appear:
        const dayAbbrevs = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
        for (final abbrev in dayAbbrevs) {
          expect(
            find.text(abbrev),
            findsNothing,
            reason: 'Day-of-week meta must be absent when completedAt is null',
          );
        }
      },
    );

    testWidgets('Editar plano link is present in every state variant', (
      tester,
    ) async {
      // Variant 1 — empty bucket.
      await tester.pumpWidget(
        _harness(plan: _plan(const []), routines: const []),
      );
      await tester.pumpAndSettle();
      expect(find.text('EDIT PLAN →'), findsOneWidget);

      // Variant 2 — partial (1 done, 1 pending).
      final mon = DateTime(2026, 5, 18, 9);
      await tester.pumpWidget(
        _harness(
          plan: _plan([
            _planned('r-push', order: 1, completedAt: mon),
            _planned('r-pull', order: 2, completedAt: null),
          ]),
          routines: [_routine('r-push', 'Push'), _routine('r-pull', 'Pull')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EDIT PLAN →'), findsOneWidget);

      // Variant 3 — fully complete.
      final wed = DateTime(2026, 5, 20, 9);
      await tester.pumpWidget(
        _harness(
          plan: _plan([
            _planned('r-push', order: 1, completedAt: mon),
            _planned('r-pull', order: 2, completedAt: wed),
          ]),
          routines: [_routine('r-push', 'Push'), _routine('r-pull', 'Pull')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EDIT PLAN →'), findsOneWidget);
    });
  });
}
