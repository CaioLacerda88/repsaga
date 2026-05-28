// Phase 32 PR 32b coverage gap: a duplicate-email signup must surface the
// `authErrorAlreadyRegistered` string on the inline error banner (the
// LoginScreen routes auth errors through the banner — NOT a SnackBar — even
// though the WIP file name reads `*_snackbar_test`; the contract pinned here
// is what the UI actually does, not what the WIP plan suggested).
//
// Behavior-not-wiring per `feedback_test_user_visible_behavior`:
//   1. Verify the localized error string actually renders.
//   2. Verify the banner is persistent (no auto-dismiss): still visible
//      after 10 simulated seconds. Guards against the
//      `cluster_persist_eats_duration` family — a future refactor that
//      moves the surface to a SnackBar with a non-zero `duration` would
//      break this assertion.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';

import '../../../../helpers/test_material_app.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockHiveService extends Mock implements HiveService {}

void main() {
  late MockAuthRepository mockRepo;
  late MockHiveService mockHive;

  setUp(() {
    mockRepo = MockAuthRepository();
    mockHive = MockHiveService();
    when(() => mockRepo.currentSession).thenReturn(null);
  });

  Widget buildTestWidget() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        hiveServiceProvider.overrideWithValue(mockHive),
      ],
      child: TestMaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );
  }

  group('LoginScreen — duplicate email', () {
    testWidgets(
      'shows authErrorAlreadyRegistered banner when signup hits an existing email',
      (tester) async {
        // The AuthRepository surfaces Supabase's "User already registered"
        // string via the AppException.message — `AuthErrorMessages.fromError`
        // substring-matches that into `l10n.authErrorAlreadyRegistered`.
        when(
          () => mockRepo.signUpWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(Exception('User already registered'));

        await tester.pumpWidget(buildTestWidget());

        // Toggle to signup mode so the SIGN UP button is the active CTA.
        await tester.ensureVisible(find.text("Don't have an account? Sign up"));
        await tester.pump();
        await tester.tap(find.text("Don't have an account? Sign up"));
        await tester.pump();

        // Fill in credentials. Email + password validators both pass.
        await tester.enterText(
          find.byType(TextFormField).first,
          'existing@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).last,
          'TestPassword123!',
        );

        // Trigger signup.
        await tester.tap(find.text('SIGN UP'));
        // Pump twice: once for the listener microtask, once for the setState
        // that lifts the inline banner into the tree.
        await tester.pump();
        await tester.pump();

        // The exact en-US string from app_en.arb keyed by
        // `authErrorAlreadyRegistered`.
        const expectedBanner =
            'An account with this email already exists. Try logging in instead.';
        expect(find.text(expectedBanner), findsOneWidget);
      },
    );

    testWidgets('duplicate-email banner persists past 10s (no auto-dismiss)', (
      tester,
    ) async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(Exception('User already registered'));

      await tester.pumpWidget(buildTestWidget());

      await tester.ensureVisible(find.text("Don't have an account? Sign up"));
      await tester.pump();
      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pump();

      await tester.enterText(
        find.byType(TextFormField).first,
        'existing@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'TestPassword123!',
      );

      await tester.tap(find.text('SIGN UP'));
      await tester.pump();
      await tester.pump();

      const expectedBanner =
          'An account with this email already exists. Try logging in instead.';

      // Banner is up.
      expect(find.text(expectedBanner), findsOneWidget);

      // Advance the synthetic clock by 10s; the banner is rendered by a
      // raw `if (_errorMessage != null)` branch in `LoginScreen.build`, so
      // it MUST still be present — there is no Timer that clears it.
      // (Guards against the `cluster_persist_eats_duration` family if a
      // future refactor migrates the surface to a timed SnackBar.)
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(expectedBanner), findsOneWidget);
    });
  });
}
