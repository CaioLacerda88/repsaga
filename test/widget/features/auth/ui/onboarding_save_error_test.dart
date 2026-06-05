// Typed-error snackbar UX for the onboarding profile save.
//
// Replaces the legacy generic `failedToSaveProfile` snack with one bar per
// `AppException` subtype reaching the catch block, so users can distinguish
// "you're offline" from "session expired" from "input invalid" and pick the
// right recovery affordance (retry-now / re-login / fix-input).
//
// Behavior-not-wiring per `feedback_test_user_visible_behavior`: every case
// asserts the user-perceptible snack copy via `find.text(...)`. Mocking the
// notifier to throw a specific `AppException` subtype is the SETUP — the
// CONTRACT is the rendered surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/onboarding_screen.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';

import '../../../../helpers/test_material_app.dart';

/// Fake [ProfileNotifier] whose `saveOnboardingProfile` throws a configurable
/// [AppException]. Each `testWidgets` block builds the tree with a different
/// fake to exercise one branch of the typed-dispatch matrix.
class _ThrowingProfileNotifier extends ProfileNotifier {
  _ThrowingProfileNotifier(this._toThrow);

  final Object _toThrow;

  @override
  Future<Profile?> build() async => null;

  @override
  Future<void> saveOnboardingProfile({
    required String displayName,
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {
    throw _toThrow;
  }
}

/// Drives the onboarding flow to the LET'S GO tap. Enters a valid display
/// name so the "name required" guard does not short-circuit the save call.
Future<void> _completeOnboardingTap(WidgetTester tester) async {
  await tester.tap(find.text('GET STARTED'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), 'Alice');
  await tester.pumpAndSettle();

  await tester.tap(find.text("LET'S GO"));
  // Two pumps: one for the throwing notifier microtask, one for the
  // setState that mounts the SnackBar widget into the Overlay.
  await tester.pump();
  await tester.pump();
}

Widget _buildTree({required Object toThrow}) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => _ThrowingProfileNotifier(toThrow)),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const OnboardingScreen(),
    ),
  );
}

void main() {
  group('OnboardingScreen typed save-error snackbars', () {
    testWidgets('should show offline copy with no CTA for NetworkException', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTree(toThrow: const app.NetworkException('offline')),
      );

      await _completeOnboardingTap(tester);

      expect(
        find.text("You're offline. Check your connection and try again."),
        findsOneWidget,
      );
      // Generic snack must NOT show — typed dispatch supersedes it.
      expect(
        find.text('Failed to save profile. Please try again.'),
        findsNothing,
      );
      // No SnackBarAction in the network branch.
      expect(find.byType(SnackBarAction), findsNothing);
    });

    testWidgets('should show offline copy with no CTA for TimeoutException', (
      tester,
    ) async {
      // TimeoutException is a sibling of NetworkException — both surface as
      // "you're offline" because the practical recovery (retry-on-network)
      // is identical from the user's perspective inside the onboarding form.
      await tester.pumpWidget(
        _buildTree(toThrow: const app.TimeoutException()),
      );

      await _completeOnboardingTap(tester);

      expect(
        find.text("You're offline. Check your connection and try again."),
        findsOneWidget,
      );
    });

    testWidgets(
      'should show session-expired copy with Sign in CTA for AuthException',
      (tester) async {
        await tester.pumpWidget(
          _buildTree(
            toThrow: const app.AuthException('JWT expired', code: '401'),
          ),
        );

        await _completeOnboardingTap(tester);

        expect(
          find.text('Your session expired. Sign in again.'),
          findsOneWidget,
        );
        // The CTA is a Material SnackBarAction — locating it via its label
        // keeps the test resilient to internal Material refactors.
        expect(find.widgetWithText(SnackBarAction, 'Sign in'), findsOneWidget);

        // Behavior contract on CTA tap: Material's SnackBarAction auto-hides
        // the bar before invoking onPressed. The router isn't mounted in this
        // widget test so the onPressed swallow-path runs (production redirect
        // is covered by E2E) — the bar dismissal is what the user perceives,
        // so we pin that. Per CLAUDE.md Testing → "behavior, not wiring".
        //
        // `pumpAndSettle` once before the tap so the SnackBar's enter
        // animation (kSnackBarTransitionDuration = 250 ms) finishes — without
        // it the action lives at an off-stage offset and `tap()` misses.
        // `pumpAndSettle` again after the tap so the hide animation
        // completes before the `findsNothing` assertion.
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SnackBarAction, 'Sign in'));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'should show field-prefixed copy with no CTA for ValidationException with known field',
      (tester) async {
        await tester.pumpWidget(
          _buildTree(
            toThrow: const app.ValidationException(
              'Display name is too short',
              field: 'displayName',
            ),
          ),
        );

        await _completeOnboardingTap(tester);

        // The mapper renders `<localized field name>: <message>` when the
        // field is recognized; `displayName` resolves to the same label used
        // on the input itself ("Display name") so the user can locate the
        // offending field visually.
        expect(
          find.text('Display name: Display name is too short'),
          findsOneWidget,
        );
        expect(find.byType(SnackBarAction), findsNothing);
      },
    );

    testWidgets(
      'should show generic validation copy for ValidationException with unknown field',
      (tester) async {
        await tester.pumpWidget(
          _buildTree(
            toThrow: const app.ValidationException(
              'something invalid',
              field: 'unknownToken',
            ),
          ),
        );

        await _completeOnboardingTap(tester);

        // Unknown / unmapped field tokens fall back to the catch-all
        // validation copy rather than leaking a raw token to the user.
        expect(find.text('Please check your inputs.'), findsOneWidget);
      },
    );

    testWidgets(
      'should show session-expired copy with Sign in CTA for DatabaseException '
      'code 42501 (post-retry RLS-rejection path)',
      (tester) async {
        // Cluster: stale-token-silent-anon-fallback (candidate). When
        // `BaseRepository.refreshAndRetry` succeeds at the refresh step
        // but the second `upsertProfile` ALSO surfaces PostgREST 42501,
        // the repository rethrows the ORIGINAL 42501 → wrapped as
        // `DatabaseException(code: '42501')` → reaches this catch block.
        // The user-recoverable affordance is the same as the
        // AuthException branch: re-login mints a fresh JWT and onboarding
        // completes on the second attempt. Pinning the exact copy + CTA
        // ensures the same user-perceptible recovery shape for both
        // entry points.
        await tester.pumpWidget(
          _buildTree(
            toThrow: const app.DatabaseException(
              'permission denied for table profiles',
              code: '42501',
            ),
          ),
        );

        await _completeOnboardingTap(tester);

        expect(
          find.text('Your session expired. Sign in again.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, 'Sign in'), findsOneWidget);
        // Generic safety-net copy must NOT show — the 42501 branch
        // supersedes it.
        expect(
          find.text('Failed to save profile. Please try again.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'should show generic save-failed copy for DatabaseException with a '
      'non-42501 code (e.g. 23514 CHECK violation) — safety net',
      (tester) async {
        // Discrimination test for the new typed-dispatch branch. Only
        // PostgREST `42501` (RLS rejection) routes through the
        // "Sign in" recovery — other DatabaseException codes
        // (`23xxx` integrity violations, `500` internal errors, etc.)
        // continue to fall through to the safety-net copy because they
        // are NOT user-fixable via re-auth. Pinning a 23514 here guards
        // against accidental broadening of the 42501 branch to "any
        // DatabaseException".
        await tester.pumpWidget(
          _buildTree(
            toThrow: const app.DatabaseException(
              'check constraint failed',
              code: '23514',
            ),
          ),
        );

        await _completeOnboardingTap(tester);

        expect(
          find.text('Failed to save profile. Please try again.'),
          findsOneWidget,
        );
        // Session-expired branch must NOT fire for non-42501 codes — no
        // Sign in CTA should be visible.
        expect(find.byType(SnackBarAction), findsNothing);
      },
    );

    testWidgets(
      'should show generic save-failed copy for DatabaseException 500 as '
      'safety net (unmapped internal error)',
      (tester) async {
        // Internal-server-error class — falls through to the safety net
        // because re-auth doesn't fix it and we don't want to mislead
        // the user with a "session expired" recovery affordance.
        await tester.pumpWidget(
          _buildTree(
            toThrow: const app.DatabaseException('500 internal', code: '500'),
          ),
        );

        await _completeOnboardingTap(tester);

        expect(
          find.text('Failed to save profile. Please try again.'),
          findsOneWidget,
        );
      },
    );
  });
}
