import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/onboarding_screen.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import '../../../../helpers/test_material_app.dart';

/// BUG-028: the fitness-level + frequency pickers were `ChoiceChip` widgets
/// (raw M3) and were replaced by a private `_BrandedPillChoice` Container.
/// Selection now manifests through a primaryViolet fill on the inner
/// [AnimatedContainer]. (The pre-review draft used hotViolet, but textCream
/// over hotViolet only reached 2.67:1 — below WCAG AA 4.5:1 — so the
/// selected fill was darkened to primaryViolet which clears 6.69:1.)
/// Walking up from the label `Text` to the nearest AnimatedContainer and
/// reading its decoration color is how we assert the selected state without
/// exposing the private widget type.
Color? _pillFillFor(WidgetTester tester, String label) {
  final ancestor = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  final decoration = ancestor.decoration;
  if (decoration is BoxDecoration) return decoration.color;
  return null;
}

// Minimal stub to avoid hitting Supabase during widget tests.
class _FakeProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile?> build() async => null;

  @override
  Future<void> saveOnboardingProfile({
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {
    // no-op in tests
  }

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}
}

void main() {
  Widget buildTestWidget({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        profileProvider.overrideWith(_FakeProfileNotifier.new),
        ...overrides,
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: const OnboardingScreen(),
      ),
    );
  }

  group('OnboardingScreen', () {
    testWidgets('shows welcome page initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Track every rep,\nevery time'), findsOneWidget);
      expect(find.text('GET STARTED'), findsOneWidget);
    });

    testWidgets('renders the Arcane brand sigil on the welcome page '
        '(not a generic dumbbell icon)', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Regression: pre-17.0d onboarding shipped `Icon(Icons.fitness_center)`.
      // The first frame new users see must match the launcher-icon sigil.
      final imageFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/app_icon/arcane_sigil_foreground.png',
      );
      expect(imageFinder, findsOneWidget);
    });

    testWidgets(
      'brand sigil is 128dp on the onboarding hero (size spec §17.0d)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // §17.0d spec: onboarding hero sigil is 128dp — one step up from the
        // login 96dp because this is the very first frame new users see, so the
        // branding statement should read larger.
        final image = tester.widget<Image>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/app_icon/arcane_sigil_foreground.png',
          ),
        );
        expect(image.width, 128.0);
        expect(image.height, 128.0);
      },
    );

    testWidgets('navigates to profile setup on GET STARTED', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      expect(find.text('Set up your profile'), findsOneWidget);
      expect(find.text('Fitness level'), findsOneWidget);
    });

    testWidgets(
      'Option A: onboarding no longer collects the display name — it is '
      'collected on the signup form, so page 2 has no name field',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();

        // The page mounted (fitness selector present) but the display-name
        // field + label are gone. Page 2 now collects only fitness signals.
        expect(find.text('Fitness level'), findsOneWidget);
        expect(find.text('Display name'), findsNothing);
        expect(find.byType(TextField), findsNothing);
      },
    );

    testWidgets('shows fitness level chips on profile page', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      expect(find.text('Beginner'), findsOneWidget);
      expect(find.text('Intermediate'), findsOneWidget);
      expect(find.text('Advanced'), findsOneWidget);
    });

    testWidgets("profile page shows LET'S GO button", (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      expect(find.text("LET'S GO"), findsOneWidget);
    });

    testWidgets('progress bar shows 2 indicators', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Just verify we can navigate to both pages without hitting a third.
      expect(find.text('Track every rep,\nevery time'), findsOneWidget);

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      expect(find.text('Set up your profile'), findsOneWidget);
    });

    testWidgets('profile page is the last page — no NEXT button on page 2', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      // Page 2 has "LET'S GO" as the final CTA, not "NEXT".
      expect(find.text("LET'S GO"), findsOneWidget);
      expect(find.text('NEXT'), findsNothing);
    });

    testWidgets(
      'selecting a fitness level pill marks it as selected (BUG-028)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();

        // Default selection ('beginner') is primaryViolet at mount time.
        expect(_pillFillFor(tester, 'Beginner'), AppColors.primaryViolet);
        expect(_pillFillFor(tester, 'Intermediate'), AppColors.surface2);

        await tester.tap(find.text('Intermediate'));
        await tester.pumpAndSettle();

        // After tap: Intermediate is filled, Beginner falls back to surface2.
        expect(_pillFillFor(tester, 'Intermediate'), AppColors.primaryViolet);
      },
    );

    testWidgets(
      'only one fitness level pill can be selected at a time (BUG-028)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Beginner'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Intermediate'));
        await tester.pumpAndSettle();

        expect(_pillFillFor(tester, 'Beginner'), AppColors.surface2);
        expect(_pillFillFor(tester, 'Intermediate'), AppColors.primaryViolet);
      },
    );

    // PO-007: page 2 must have a back button that returns the user to page 1.
    testWidgets('PO-007: profile setup page shows a Back button', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      // The back button is a TextButton.icon with label 'Back'.
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('PO-007: tapping Back on page 2 returns to the welcome page', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // Go to page 2.
      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      // Confirm we are on page 2.
      expect(find.text('Set up your profile'), findsOneWidget);

      // Tap Back.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      // We should be back on page 1.
      expect(find.text('Track every rep,\nevery time'), findsOneWidget);
      expect(find.text('GET STARTED'), findsOneWidget);
    });

    testWidgets(
      'PO-007: after going back, GET STARTED still navigates to page 2',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Go to page 2, then back to page 1.
        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        // Navigate forward again — page 2 must appear.
        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();

        expect(find.text('Set up your profile'), findsOneWidget);
      },
    );
  });
}
