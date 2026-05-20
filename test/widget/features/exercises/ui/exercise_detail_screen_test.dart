import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/l10n/locale_provider.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/exercises/providers/exercise_providers.dart';
import 'package:repsaga/features/exercises/ui/exercise_detail_screen.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/shared/widgets/exercise_image.dart';
import 'package:repsaga/shared/widgets/exercise_info_sections.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/stub_locale_notifier.dart';
import '../../../../helpers/test_material_app.dart';

class MockExerciseRepository extends Mock implements ExerciseRepository {}

void main() {
  late MockExerciseRepository mockRepo;

  setUp(() {
    mockRepo = MockExerciseRepository();
  });

  Widget buildTestWidget({required String exerciseId}) {
    return ProviderScope(
      overrides: [
        exerciseRepositoryProvider.overrideWithValue(mockRepo),
        currentUserIdProvider.overrideWithValue('user-001'),
        localeProvider.overrideWith(
          () => StubLocaleNotifier(const Locale('en')),
        ),
        // Prevent PR section from touching real Supabase.
        exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: ExerciseDetailScreen(exerciseId: exerciseId),
      ),
    );
  }

  /// Pumps widget and waits for the FutureBuilder to resolve.
  /// Uses pump() instead of pumpAndSettle() because CachedNetworkImage's
  /// placeholder animation (LinearProgressIndicator) never settles in tests.
  Future<void> pumpAndResolve(WidgetTester tester) async {
    await tester.pump(); // Schedule microtask
    await tester.pump(); // Resolve future
    await tester.pump(); // Build with data
  }

  group('ExerciseDetailScreen image section', () {
    testWidgets(
      'shows image row when both imageStartUrl and imageEndUrl are present',
      (tester) async {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            imageStartUrl: 'https://example.com/start.jpg',
            imageEndUrl: 'https://example.com/end.jpg',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('Start'), findsOneWidget);
        expect(find.text('End'), findsOneWidget);
        expect(find.byType(ExerciseImage), findsNWidgets(2));
      },
    );

    testWidgets('shows only start image when imageEndUrl is null', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          imageStartUrl: 'https://example.com/start.jpg',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsNothing);
      expect(find.byType(ExerciseImage), findsOneWidget);
    });

    testWidgets('shows only end image when imageStartUrl is null', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(imageEndUrl: 'https://example.com/end.jpg'),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('Start'), findsNothing);
      expect(find.text('End'), findsOneWidget);
      expect(find.byType(ExerciseImage), findsOneWidget);
    });

    testWidgets('image section collapses entirely when both URLs are null', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(TestExerciseFactory.create());
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await tester.pumpAndSettle();

      expect(find.text('Start'), findsNothing);
      expect(find.text('End'), findsNothing);
      expect(find.byType(ExerciseImage), findsNothing);
    });

    testWidgets('semantics labels are correct for start and end positions', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          name: 'Barbell Curl',
          imageStartUrl: 'https://example.com/start.jpg',
          imageEndUrl: 'https://example.com/end.jpg',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      // Verify semantics nodes with image labels exist
      expect(
        find.bySemanticsLabel('Barbell Curl start position'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Barbell Curl end position'),
        findsOneWidget,
      );
    });

    testWidgets('tapping an image opens full-screen dialog', (tester) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          imageStartUrl: 'https://example.com/start.jpg',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      // Find the GestureDetector wrapping the ExerciseImage and tap it
      final gestureFinder = find.ancestor(
        of: find.byType(ExerciseImage),
        matching: find.byType(GestureDetector),
      );
      expect(gestureFinder, findsOneWidget);

      await tester.tap(gestureFinder.first);
      await tester.pump(); // Trigger dialog
      await tester.pump(); // Animate dialog

      // A dialog should be open -- there should now be a second Scaffold
      // (the full-screen dialog uses a Scaffold with scrim background)
      expect(find.byType(Scaffold), findsNWidgets(2));
    });

    testWidgets('full-screen dialog dismisses via close button', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          imageStartUrl: 'https://example.com/start.jpg',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      // Open dialog
      final gestureFinder = find.ancestor(
        of: find.byType(ExerciseImage),
        matching: find.byType(GestureDetector),
      );
      await tester.tap(gestureFinder.first);
      await tester.pump();
      await tester.pump();

      // Verify dialog is open (2 Scaffolds)
      expect(find.byType(Scaffold), findsNWidgets(2));

      // Tap the close button in the dialog AppBar
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog should be dismissed (back to 1 Scaffold)
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows loading indicator while exercise is being fetched', (
      tester,
    ) async {
      // Use a Completer that never completes to simulate a pending load
      final completer = Completer<Exercise>();
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to avoid pending timer warnings
      completer.complete(Exercise.fromJson(TestExerciseFactory.create()));
      await tester.pump();
    });

    testWidgets('shows error message when exercise fails to load', (
      tester,
    ) async {
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => throw Exception('Network error'));

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load exercise'), findsOneWidget);
    });

    testWidgets('both CachedNetworkImage widgets receive the correct URLs', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          imageStartUrl: 'https://cdn.example.com/chest/bench-start.jpg',
          imageEndUrl: 'https://cdn.example.com/chest/bench-end.jpg',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      final cachedImages = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .toList();
      expect(cachedImages.length, 2);

      final urls = cachedImages.map((img) => img.imageUrl).toSet();
      expect(urls, contains('https://cdn.example.com/chest/bench-start.jpg'));
      expect(urls, contains('https://cdn.example.com/chest/bench-end.jpg'));
    });
  });

  group('ExerciseDetailScreen description and form tips sections', () {
    testWidgets('renders ABOUT section when exercise has a description', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          description: 'A compound push movement targeting the chest.',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('ABOUT'), findsOneWidget);
      expect(
        find.text('A compound push movement targeting the chest.'),
        findsOneWidget,
      );
    });

    testWidgets('omits ABOUT section when description is null', (tester) async {
      final exercise = Exercise.fromJson(TestExerciseFactory.create());
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('ABOUT'), findsNothing);
    });

    testWidgets('renders FORM TIPS section when exercise has formTips', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          formTips: 'Keep elbows at 45 degrees\nDrive through heels',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('FORM TIPS'), findsOneWidget);
      expect(find.text('Keep elbows at 45 degrees'), findsOneWidget);
      expect(find.text('Drive through heels'), findsOneWidget);
    });

    testWidgets('omits FORM TIPS section when formTips is null', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(TestExerciseFactory.create());
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('FORM TIPS'), findsNothing);
    });

    testWidgets(
      'renders both ABOUT and FORM TIPS when both fields are present',
      (tester) async {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            description: 'Targets hamstrings and glutes.',
            formTips: 'Hinge at hips\nKeep back flat',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('ABOUT'), findsOneWidget);
        expect(find.text('FORM TIPS'), findsOneWidget);
        expect(find.byType(ExerciseDescriptionSection), findsOneWidget);
        expect(find.byType(ExerciseFormTipsSection), findsOneWidget);
      },
    );

    testWidgets(
      'renders description but omits FORM TIPS when only description is set',
      (tester) async {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(description: 'Only description, no tips.'),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('ABOUT'), findsOneWidget);
        expect(find.text('FORM TIPS'), findsNothing);
      },
    );
  });

  group('ExerciseDetailScreen Phase 15f locale-resolved content', () {
    Widget buildPtWidget({required String exerciseId}) {
      return ProviderScope(
        overrides: [
          exerciseRepositoryProvider.overrideWithValue(mockRepo),
          currentUserIdProvider.overrideWithValue('user-001'),
          localeProvider.overrideWith(
            () => StubLocaleNotifier(const Locale('pt')),
          ),
          exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
        ],
        child: TestMaterialApp(
          theme: AppTheme.dark,
          home: ExerciseDetailScreen(exerciseId: exerciseId),
        ),
      );
    }

    testWidgets(
      'renders pt description from resolved Exercise when localeProvider is pt',
      (tester) async {
        // The Exercise model carries the already-resolved localized text.
        // The repository (or RPC) resolves the locale server-side; the widget
        // just renders whatever the repo returns. This test verifies the widget
        // correctly displays content from the Exercise regardless of locale.
        final ptExercise = Exercise.fromJson(
          TestExerciseFactory.create(
            id: 'exercise-001',
            name: 'Supino Reto com Barra',
            slug: 'barbell_bench_press',
            description:
                'O rei do empurrar de membros superiores. Trabalha peito, '
                'deltoide anterior e tríceps com a barra no banco reto.',
            formTips:
                'Plante os pés no chão e contraia as escápulas.\n'
                'Desça a barra até o meio do peito com cotovelos a cerca de 45 graus.',
          ),
        );

        when(
          () => mockRepo.getExerciseById(
            locale: 'pt',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => ptExercise);

        await tester.pumpWidget(buildPtWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        // The pt name must be visible.
        expect(find.text('Supino Reto com Barra'), findsOneWidget);

        // The ABOUT section must render with the pt description text.
        expect(find.text('ABOUT'), findsOneWidget);
        expect(find.textContaining('O rei do empurrar'), findsOneWidget);

        // The FORM TIPS section must render with pt tips split on newline.
        expect(find.text('FORM TIPS'), findsOneWidget);
        expect(
          find.text('Plante os pés no chão e contraia as escápulas.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Desça a barra até o meio do peito com cotovelos a cerca de 45 graus.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('repository called with locale:pt when localeProvider is pt', (
      tester,
    ) async {
      final ptExercise = Exercise.fromJson(
        TestExerciseFactory.create(
          id: 'exercise-001',
          name: 'Supino Reto com Barra',
          slug: 'barbell_bench_press',
        ),
      );

      when(
        () => mockRepo.getExerciseById(
          locale: 'pt',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => ptExercise);

      await tester.pumpWidget(buildPtWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      // Verify the repo was called with locale:'pt' exactly once.
      verify(
        () => mockRepo.getExerciseById(
          locale: 'pt',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).called(1);

      // It must NOT have been called with locale:'en'.
      verifyNever(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      );
    });

    testWidgets(
      'en detail shows en content when localeProvider is en (cross-locale guard)',
      (tester) async {
        final enExercise = Exercise.fromJson(
          TestExerciseFactory.create(
            id: 'exercise-001',
            name: 'Barbell Bench Press',
            slug: 'barbell_bench_press',
            description: 'The king of upper-body pressing.',
            formTips:
                'Plant feet flat on the floor.\nLower the bar to mid-chest.',
          ),
        );

        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => enExercise);

        // Using the default en buildTestWidget from the outer scope.
        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('Barbell Bench Press'), findsOneWidget);
        expect(
          find.textContaining('The king of upper-body pressing.'),
          findsOneWidget,
        );
        expect(find.text('FORM TIPS'), findsOneWidget);
        expect(find.text('Plant feet flat on the floor.'), findsOneWidget);
      },
    );
  });

  group('ExerciseDetailScreen _DetailChip (Phase 27 L18.4)', () {
    // L18.4 added an optional `iconColor` param to _DetailChip.
    // The muscle-group chip passes `exercise.muscleGroup.hueColor` (a non-null
    // body-part hue for the 6 strength pillars); the equipment chip passes
    // null (neutral). The user-visible contract is that BOTH chips render
    // their labels regardless of whether iconColor is null or non-null.
    testWidgets(
      'muscle-group chip renders label for a strength-pillar muscle group',
      (tester) async {
        // chest → hueColor is non-null (bodyPartChest) — exercises the
        // iconColor != null branch introduced in L18.4.
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            muscleGroup: 'chest',
            equipmentType: 'barbell',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        // 'Chest' is the localized label for MuscleGroup.chest in en.
        expect(find.text('Chest'), findsOneWidget);
      },
    );

    testWidgets(
      'equipment chip renders label alongside the muscle-group chip',
      (tester) async {
        // equipment chip passes iconColor: null — exercises the null branch.
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            muscleGroup: 'back',
            equipmentType: 'dumbbell',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('Back'), findsOneWidget);
        expect(find.text('Dumbbell'), findsOneWidget);
      },
    );

    testWidgets(
      'muscle-group chip renders for cardio (hueColor is null — neutral fallback)',
      (tester) async {
        // cardio has no identity hue in v1 (hueColor returns null) — exercises
        // the iconColor-null fallback path inside _DetailChip even when a
        // muscle group IS present. Confirms the null guard doesn't crash.
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(muscleGroup: 'cardio'),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('Cardio'), findsOneWidget);
      },
    );
  });

  group('ExerciseDetailScreen P9 hierarchy', () {
    testWidgets('Created <date> line is no longer rendered', (tester) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          createdAt: '2026-02-15T10:00:00Z',
          description: 'Primary body copy.',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      // The pre-P9 detail body rendered "Created February 15, 2026" above
      // the description. After P9 that line is gone from the main flow.
      expect(
        find.textContaining('Created '),
        findsNothing,
        reason: 'P9 dropped the Created <date> line from the detail body.',
      );
    });

    testWidgets(
      'description renders above muscle/equipment chips (P9 reorder)',
      (tester) async {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            description: 'The description goes before the chips.',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        final descTopLeft = tester.getTopLeft(
          find.byType(ExerciseDescriptionSection),
        );
        // Find the muscle-group chip by its display label.
        final chipTopLeft = tester.getTopLeft(find.text('Chest'));

        expect(
          descTopLeft.dy,
          lessThan(chipTopLeft.dy),
          reason: 'Description section must sit above the chip row.',
        );
      },
    );

    testWidgets('form tips section renders below the chip row', (tester) async {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          description: 'Primary body copy.',
          formTips: 'Tip one\nTip two',
        ),
      );
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      final formTipsTopLeft = tester.getTopLeft(
        find.byType(ExerciseFormTipsSection),
      );
      final chipTopLeft = tester.getTopLeft(find.text('Chest'));

      expect(
        formTipsTopLeft.dy,
        greaterThan(chipTopLeft.dy),
        reason: 'Form tips section must sit below the chip row.',
      );
    });

    testWidgets(
      'custom exercise shows "Custom exercise" label directly under title',
      (tester) async {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            name: 'My Home Press',
            isDefault: false,
            userId: 'user-001',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => exercise);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        expect(find.text('Custom exercise'), findsOneWidget);

        final titleTopLeft = tester.getTopLeft(find.text('My Home Press'));
        final labelTopLeft = tester.getTopLeft(find.text('Custom exercise'));

        expect(labelTopLeft.dy, greaterThan(titleTopLeft.dy));
        // And the label sits above the description/chip area.
        final chipTopLeft = tester.getTopLeft(find.text('Chest'));
        expect(labelTopLeft.dy, lessThan(chipTopLeft.dy));
      },
    );

    testWidgets('default exercise omits the "Custom exercise" label', (
      tester,
    ) async {
      final exercise = Exercise.fromJson(TestExerciseFactory.create());
      when(
        () => mockRepo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        ),
      ).thenAnswer((_) async => exercise);

      await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
      await pumpAndResolve(tester);

      expect(find.text('Custom exercise'), findsNothing);
    });

    testWidgets(
      'no orphan 16dp gap between title and chips when description is null '
      '(P9 review fix)',
      (tester) async {
        // Render the null-description layout in a fresh ProviderScope and
        // measure the vertical distance between the title and the chip row.
        // The ExerciseDescriptionSection collapses to SizedBox.shrink when
        // description is null, so the only thing that should sit between
        // the title and the chips is Flutter's natural column spacing —
        // there should be NO 16 dp orphan spacer.
        //
        // The pre-fix layout had an unconditional SizedBox(height: 16)
        // between the description section and the chip Wrap. With that
        // spacer in place, the null-desc gap would include 16 dp of
        // unexplained whitespace. We assert an upper bound small enough to
        // catch that regression.
        final withoutDesc = Exercise.fromJson(
          TestExerciseFactory.create(name: 'Paired Press', description: null),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => withoutDesc);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        final titleBottom = tester.getBottomLeft(find.text('Paired Press')).dy;
        final chipTop = tester.getTopLeft(find.text('Chest')).dy;
        final gap = chipTop - titleBottom;

        // With Flutter's default line-height metrics, the gap between the
        // text baseline bottom and the next sibling widget's visual top is
        // a small amount of typographic descender padding. An unguarded
        // SizedBox(16) would add a clear 16 dp. Allow a generous ceiling
        // that still catches a regression of that magnitude.
        expect(
          gap,
          lessThan(16),
          reason:
              'Null-description layout must not inject a 16 dp orphan '
              'spacer between the title and the chip row. Measured gap '
              'was $gap dp. If this test fails at exactly or above 16 dp, '
              'the P9 review fix for the orphan SizedBox regressed.',
        );
      },
    );

    testWidgets(
      'description adds vertical space between title and chips when present',
      (tester) async {
        // Companion to the above: when description IS set, the ABOUT
        // section (with its internal 24 dp top padding, label, and body
        // text) must visibly push the chip row further down the layout.
        final withDesc = Exercise.fromJson(
          TestExerciseFactory.create(
            name: 'Paired Press',
            description: 'A compound push movement that loads the chest.',
          ),
        );
        when(
          () => mockRepo.getExerciseById(
            locale: 'en',
            userId: 'user-001',
            id: 'exercise-001',
          ),
        ).thenAnswer((_) async => withDesc);

        await tester.pumpWidget(buildTestWidget(exerciseId: 'exercise-001'));
        await pumpAndResolve(tester);

        final titleBottom = tester.getBottomLeft(find.text('Paired Press')).dy;
        final chipTop = tester.getTopLeft(find.text('Chest')).dy;
        final gap = chipTop - titleBottom;

        // The ABOUT section contributes at least the 24 dp internal top
        // gap plus the label and body text — comfortably above 40 dp.
        expect(
          gap,
          greaterThan(40),
          reason:
              'Description-present layout must render the ABOUT section '
              'between the title and the chip row, producing a large '
              'vertical gap. Measured gap was $gap dp.',
        );
      },
    );
  });
}
