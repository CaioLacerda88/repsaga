import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/l10n/locale_provider.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/exercises/providers/exercise_providers.dart';
import 'package:repsaga/features/exercises/ui/exercise_list_screen.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/stub_locale_notifier.dart';
import '../../../../helpers/test_material_app.dart';

void main() {
  final testExercises = [
    Exercise.fromJson(TestExerciseFactory.create()),
    Exercise.fromJson(
      TestExerciseFactory.create(
        id: 'exercise-002',
        name: 'Squat',
        muscleGroup: 'legs',
        equipmentType: 'barbell',
      ),
    ),
    Exercise.fromJson(
      TestExerciseFactory.create(
        id: 'exercise-003',
        name: 'Pull Up',
        muscleGroup: 'back',
        equipmentType: 'bodyweight',
      ),
    ),
  ];

  Widget buildTestWidget({
    AsyncValue<List<Exercise>> exerciseValue = const AsyncLoading(),
  }) {
    return ProviderScope(
      overrides: [
        filteredExerciseListProvider.overrideWith((ref) => exerciseValue),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: const ExerciseListScreen(),
      ),
    );
  }

  group('ExerciseListScreen', () {
    testWidgets('renders exercise list with names visible', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(testExercises)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('Pull Up'), findsOneWidget);
    });

    testWidgets('renders muscle group filter buttons (All + 6 groups)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(testExercises)),
      );
      await tester.pumpAndSettle();

      // All button + 6 muscle groups
      expect(find.text('All'), findsOneWidget);
      for (final group in MuscleGroup.values) {
        expect(find.text(group.displayName), findsWidgets);
      }
    });

    testWidgets('renders equipment filter chips', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(testExercises)),
      );
      await tester.pumpAndSettle();

      for (final type in EquipmentType.values) {
        expect(find.text(type.displayName), findsWidgets);
      }
    });

    testWidgets('renders search field', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(testExercises)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search exercises...'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('renders FAB for creating exercises', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(testExercises)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('shows empty state without filters', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: const AsyncData([])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your exercises will appear here'), findsOneWidget);
      expect(find.text('Create Exercise'), findsOneWidget);
    });

    testWidgets('shows filtered empty state with Clear Filters button', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filteredExerciseListProvider.overrideWith(
              (ref) => const AsyncData(<Exercise>[]),
            ),
            selectedMuscleGroupProvider.overrideWith(
              (ref) => MuscleGroup.chest,
            ),
          ],
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: const ExerciseListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No exercises match your filters'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
    });

    // PO-016: exercise list must be wrapped in a RefreshIndicator so users can
    // pull-to-refresh to reload the exercise catalogue.
    testWidgets('PO-016: exercise list is wrapped in a RefreshIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(testExercises)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('ExerciseListScreen Phase 15f pt locale', () {
    // PT locale exercises — names come from exercise_translations (pt).
    final ptExercises = [
      Exercise.fromJson(
        TestExerciseFactory.create(
          id: 'exercise-pt-001',
          name: 'Supino Reto com Barra',
          muscleGroup: 'chest',
          equipmentType: 'barbell',
          slug: 'barbell_bench_press',
        ),
      ),
      Exercise.fromJson(
        TestExerciseFactory.create(
          id: 'exercise-pt-002',
          name: 'Agachamento com Barra',
          muscleGroup: 'legs',
          equipmentType: 'barbell',
          slug: 'barbell_squat',
        ),
      ),
      Exercise.fromJson(
        TestExerciseFactory.create(
          id: 'exercise-pt-003',
          name: 'Levantamento Terra',
          muscleGroup: 'back',
          equipmentType: 'barbell',
          slug: 'deadlift',
        ),
      ),
    ];

    testWidgets(
      'renders pt exercise names when localeProvider is overridden to pt',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              filteredExerciseListProvider.overrideWith(
                (ref) => AsyncData(ptExercises),
              ),
              localeProvider.overrideWith(
                () => StubLocaleNotifier(const Locale('pt')),
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ExerciseListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // All three pt names must render.
        expect(find.text('Supino Reto com Barra'), findsOneWidget);
        expect(find.text('Agachamento com Barra'), findsOneWidget);
        expect(find.text('Levantamento Terra'), findsOneWidget);

        // No English names should appear in the list.
        expect(find.text('Barbell Bench Press'), findsNothing);
        expect(find.text('Barbell Squat'), findsNothing);
        expect(find.text('Deadlift'), findsNothing);
      },
    );

    testWidgets(
      'renders en exercise names when localeProvider is overridden to en',
      (tester) async {
        final enExercises = [
          Exercise.fromJson(
            TestExerciseFactory.create(
              id: 'exercise-en-001',
              name: 'Barbell Bench Press',
              muscleGroup: 'chest',
              equipmentType: 'barbell',
              slug: 'barbell_bench_press',
            ),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              filteredExerciseListProvider.overrideWith(
                (ref) => AsyncData(enExercises),
              ),
              localeProvider.overrideWith(
                () => StubLocaleNotifier(const Locale('en')),
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ExerciseListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Barbell Bench Press'), findsOneWidget);
        expect(find.text('Supino Reto com Barra'), findsNothing);
      },
    );
  });

  group('ExerciseListScreen P9 custom-exercise accent', () {
    BoxDecoration? cardDecoration(WidgetTester tester, String exerciseName) {
      // Walk up from the exercise name Text to find the card's outer
      // Container (the one carrying the Border decoration).
      final textFinder = find.text(exerciseName);
      expect(textFinder, findsOneWidget);
      final containers = tester
          .widgetList<Container>(
            find.ancestor(of: textFinder, matching: find.byType(Container)),
          )
          .toList();
      for (final c in containers) {
        final d = c.decoration;
        if (d is BoxDecoration && d.border != null) {
          return d;
        }
      }
      return null;
    }

    testWidgets('custom exercise card has a primary left-border accent', (
      tester,
    ) async {
      final customExercises = [
        Exercise.fromJson(
          TestExerciseFactory.create(
            id: 'exercise-custom-001',
            name: 'My Home Press',
            isDefault: false,
            userId: 'user-001',
          ),
        ),
      ];

      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(customExercises)),
      );
      await tester.pumpAndSettle();

      final deco = cardDecoration(tester, 'My Home Press');
      expect(deco, isNotNull);
      final border = deco!.border! as Border;
      expect(
        border.left.width,
        3,
        reason: 'custom cards should have a 3dp left accent',
      );
      expect(border.left.style, isNot(equals(BorderStyle.none)));
    });

    testWidgets('default exercise card has no left-border accent', (
      tester,
    ) async {
      final defaultExercises = [
        Exercise.fromJson(TestExerciseFactory.create(name: 'Bench Press')),
      ];

      await tester.pumpWidget(
        buildTestWidget(exerciseValue: AsyncData(defaultExercises)),
      );
      await tester.pumpAndSettle();

      final deco = cardDecoration(tester, 'Bench Press');
      expect(deco, isNotNull);
      final border = deco!.border! as Border;
      expect(
        border.left.style,
        BorderStyle.none,
        reason: 'default cards should have no left accent',
      );
    });
  });

  // ----------------------------------------------------------------------
  // Body-part hue tokens on muscle-group filter buttons + info chips
  //
  // The Phase 26a body-part hue tokens (`bodyPartChest` pink, `bodyPartBack`
  // sky, etc.) must flow into the Exercises tab. Pre-fix, both surfaces
  // rendered icons in neutral grey, breaking the body-part identity that
  // Saga/Stats/Engajamento all surface. See feedback_design_token_sweep_on_
  // new_tokens — propagation sweep for the Exercises surface.
  // ----------------------------------------------------------------------

  group('ExerciseListScreen body-part hue tokens', () {
    /// Walks down from the filter button identifier to the [IconTheme] that
    /// drives the SVG icon color (the icon delegates to
    /// `IconTheme.of(context).color` when no `color:` is passed). The first
    /// IconTheme below the filter button identifier is the per-button
    /// override; ambient IconThemes from MaterialApp/Theme sit higher.
    Color? filterIconColor(WidgetTester tester, String identifier) {
      final scope = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == identifier,
      );
      expect(scope, findsOneWidget, reason: 'filter $identifier not found');
      final iconThemes = tester
          .widgetList<IconTheme>(
            find.descendant(of: scope, matching: find.byType(IconTheme)),
          )
          .toList();
      expect(iconThemes, isNotEmpty, reason: 'no IconTheme under $identifier');
      return iconThemes.first.data.color;
    }

    /// Reads the [SvgPicture.colorFilter] for the muscle-group info chip
    /// inside the card whose title matches [exerciseName]. The muscle-group
    /// chip is the first SvgPicture under the card subtree; the equipment-
    /// type chip is the second.
    ///
    /// Equality is via `toString()` because [ColorFilter] exposes no public
    /// getters for the embedded color/mode. Round-tripping through the
    /// constructor + `toString` is stable for the renderer-side surface
    /// (which is what the user perceives).
    ColorFilter? muscleChipColorFilter(WidgetTester tester, String name) {
      final titleFinder = find.text(name);
      expect(titleFinder, findsOneWidget);
      final svgs = tester
          .widgetList<SvgPicture>(
            find.descendant(
              of: find.ancestor(
                of: titleFinder,
                matching: find.byType(Material),
              ),
              matching: find.byType(SvgPicture),
            ),
          )
          .toList();
      expect(svgs, isNotEmpty, reason: 'no SvgPicture under $name');
      return svgs.first.colorFilter;
    }

    testWidgets(
      'muscle-group button: chest filter uses bodyPartChest hue when selected',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              filteredExerciseListProvider.overrideWith(
                (ref) => const AsyncData(<Exercise>[]),
              ),
              selectedMuscleGroupProvider.overrideWith(
                (ref) => MuscleGroup.chest,
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ExerciseListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final color = filterIconColor(tester, 'exercise-filter-chest');
        expect(
          color,
          VitalityStateStyles.bodyPartColor[BodyPart.chest],
          reason: 'selected chest filter must render at full bodyPartChest hue',
        );
      },
    );

    testWidgets(
      'muscle-group button: chest filter uses bodyPartChest hue at reduced alpha when unselected',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              filteredExerciseListProvider.overrideWith(
                (ref) => const AsyncData(<Exercise>[]),
              ),
              // selected = null → chest filter is unselected.
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ExerciseListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final color = filterIconColor(tester, 'exercise-filter-chest');
        expect(color, isNotNull);
        final expected = VitalityStateStyles.bodyPartColor[BodyPart.chest]!;
        // Hue matches the body-part token (same RGB) but with reduced alpha.
        expect(
          color!.r,
          expected.r,
          reason: 'unselected chest filter must keep the chest hue (R)',
        );
        expect(color.g, expected.g);
        expect(color.b, expected.b);
        expect(
          color.a,
          lessThan(1.0),
          reason: 'unselected chest filter must be at reduced alpha',
        );
      },
    );

    testWidgets(
      'muscle-group button: cardio (non-mapped) falls back to neutral onSurface',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              filteredExerciseListProvider.overrideWith(
                (ref) => const AsyncData(<Exercise>[]),
              ),
              selectedMuscleGroupProvider.overrideWith(
                (ref) => MuscleGroup.cardio,
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ExerciseListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final color = filterIconColor(tester, 'exercise-filter-cardio');
        final theme = AppTheme.dark;
        // cardio has no body-part identity — falls back to the existing
        // "primary when selected" neutral behaviour (theme primary color).
        expect(
          color,
          theme.colorScheme.primary,
          reason:
              'cardio is not a v1 body-part identity — selected falls back to '
              'theme.primary, not a hue token',
        );
      },
    );

    testWidgets(
      'info chip: back muscle group renders icon in bodyPartBack hue',
      (tester) async {
        final exercises = [
          Exercise.fromJson(
            TestExerciseFactory.create(
              id: 'exercise-back-001',
              name: 'Pull Up',
              muscleGroup: 'back',
              equipmentType: 'bodyweight',
            ),
          ),
        ];

        await tester.pumpWidget(
          buildTestWidget(exerciseValue: AsyncData(exercises)),
        );
        await tester.pumpAndSettle();

        final filter = muscleChipColorFilter(tester, 'Pull Up');
        final expected = ColorFilter.mode(
          VitalityStateStyles.bodyPartColor[BodyPart.back]!,
          BlendMode.srcIn,
        );
        expect(
          filter.toString(),
          expected.toString(),
          reason:
              'back muscle-group chip icon must render at the bodyPartBack hue',
        );
      },
    );

    testWidgets(
      'info chip: cardio (non-mapped) falls back to neutral onSurface tint',
      (tester) async {
        final exercises = [
          Exercise.fromJson(
            TestExerciseFactory.create(
              id: 'exercise-cardio-001',
              name: 'Treadmill',
              muscleGroup: 'cardio',
              equipmentType: 'machine',
              slug: 'treadmill',
            ),
          ),
        ];

        await tester.pumpWidget(
          buildTestWidget(exerciseValue: AsyncData(exercises)),
        );
        await tester.pumpAndSettle();

        final filter = muscleChipColorFilter(tester, 'Treadmill');
        // cardio has no v1 identity hue — chip falls back to the neutral
        // 0.75-alpha onSurface tint. Pinning the exact neutral via a
        // round-trip through the same ColorFilter constructor keeps the
        // expectation stable against any future Color toString format
        // change while still asserting on a fixed numeric value.
        final neutral = AppTheme.dark.colorScheme.onSurface.withValues(
          alpha: 0.75,
        );
        final expected = ColorFilter.mode(neutral, BlendMode.srcIn);
        expect(
          filter.toString(),
          expected.toString(),
          reason: 'cardio chip must use the neutral onSurface@0.75 fallback',
        );
        // And: must NOT match any body-part hue identity token.
        for (final bp in BodyPart.values) {
          final h = VitalityStateStyles.bodyPartColor[bp]!;
          if (h == AppColors.textDim) continue; // core uses textDim — neutral
          final hueFilter = ColorFilter.mode(h, BlendMode.srcIn);
          expect(
            filter.toString(),
            isNot(hueFilter.toString()),
            reason: 'cardio chip must NOT render as ${bp.name} body-part hue',
          );
        }
      },
    );
  });
}
