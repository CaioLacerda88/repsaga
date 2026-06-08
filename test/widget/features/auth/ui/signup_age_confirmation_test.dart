import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/l10n/locale_provider.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/auth/providers/signup_state_provider.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';
import 'package:repsaga/l10n/app_localizations.dart';
import 'package:repsaga/shared/widgets/gradient_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../helpers/stub_locale_notifier.dart';
import '../../../../helpers/test_material_app.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockHiveService extends Mock implements HiveService {}

/// Stand-in for an `AuthResponse` whose `.session` is null — the
/// "confirmation email required" path the notifier takes after signUp,
/// which lifts `signupPendingEmailProvider` and drives navigation.
class _FakeAuthResponseNoSession extends Fake implements supabase.AuthResponse {
  @override
  supabase.Session? get session => null;
}

/// Legal PR 2 (age confirmation) + Option A (inline legal links) widget tests.
///
/// Cluster: `data-protection-compliance`. The Sign Up CTA must remain
/// disabled until the age-confirmation checkbox is ticked (LGPD Art. 14
/// minimum-age compliance). These tests assert what the user SEES — the
/// `GradientButton.onPressed == null` state — not the internal flag,
/// per CLAUDE.md A2 "behavior-not-wiring".
///
/// Option A replaced the `CheckboxListTile` + orphaned chip row with a bare
/// `Checkbox` whose label inlines the Terms + Privacy links via `Text.rich`.
/// The age-gate row carries the `auth-age-confirmation` Semantics identifier;
/// the inline links carry `auth-age-link-terms` / `auth-age-link-privacy`.
void main() {
  Widget buildTestWidget() {
    return ProviderScope(
      child: TestMaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );
  }

  Future<void> enterSignupMode(WidgetTester tester) async {
    await tester.ensureVisible(find.text("Don't have an account? Sign up"));
    await tester.pump();
    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pump();
  }

  /// The age-gate Checkbox lives inside the `auth-age-confirmation` Semantics
  /// row. Tapping the Checkbox directly toggles `_ageConfirmed` (the inline
  /// label is no longer a tappable ListTile title).
  Finder ageCheckbox() => find.byType(Checkbox);

  /// Finds a Semantics node by identifier (locale-independent anchor).
  Finder semanticsId(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  /// Enters text into the field wrapped by the given Semantics identifier.
  Future<void> fillField(
    WidgetTester tester,
    String identifier,
    String text,
  ) async {
    await tester.enterText(
      find.descendant(
        of: semanticsId(identifier),
        matching: find.byType(EditableText),
      ),
      text,
    );
    await tester.pump();
  }

  group('Signup age-confirmation checkbox', () {
    testWidgets('age-gate row + inline legal links are shown in signup mode', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      expect(semanticsId('auth-age-confirmation'), findsOneWidget);
      // Option A — the Privacy + Terms links are inlined into the checkbox
      // label sentence (no separate chip row). Locate them by identifier so
      // the test is robust against copy tweaks.
      expect(semanticsId('auth-age-link-privacy'), findsOneWidget);
      expect(semanticsId('auth-age-link-terms'), findsOneWidget);
    });

    testWidgets('age-gate row is hidden in login mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(semanticsId('auth-age-confirmation'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('sign-up CTA is DISABLED before the checkbox is ticked', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      await tester.ensureVisible(find.byType(GradientButton));
      await tester.pump();

      final btn = tester.widget<GradientButton>(find.byType(GradientButton));
      expect(
        btn.onPressed,
        isNull,
        reason: 'Sign-up CTA must be disabled until age is confirmed',
      );
    });

    testWidgets('sign-up CTA becomes ENABLED once the checkbox is ticked', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      await tester.ensureVisible(ageCheckbox());
      await tester.pump();
      await tester.tap(ageCheckbox());
      await tester.pump();

      await tester.ensureVisible(find.byType(GradientButton));
      await tester.pump();

      final btn = tester.widget<GradientButton>(find.byType(GradientButton));
      expect(
        btn.onPressed,
        isNotNull,
        reason: 'Sign-up CTA must enable once age is confirmed',
      );
    });

    testWidgets('login mode CTA is NOT gated on the (hidden) age checkbox', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      // Pre-condition: login mode, checkbox hidden.
      expect(find.byType(Checkbox), findsNothing);

      await tester.ensureVisible(find.byType(GradientButton));
      await tester.pump();

      final btn = tester.widget<GradientButton>(find.byType(GradientButton));
      expect(
        btn.onPressed,
        isNotNull,
        reason: 'Login CTA must not be gated on the signup-only age flag',
      );
    });

    testWidgets(
      'should NOT sign up via confirm-password keyboard submit while age '
      'checkbox is unticked',
      (tester) async {
        final mockRepo = MockAuthRepository();
        final mockHive = MockHiveService();
        when(() => mockRepo.currentSession).thenReturn(null);
        when(
          () => mockRepo.signUpWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            locale: any(named: 'locale'),
            displayName: any(named: 'displayName'),
          ),
        ).thenAnswer((_) async => _FakeAuthResponseNoSession());

        // A minimal GoRouter so the success-path `context.go('/email-confirmation')`
        // resolves to a real navigation we can assert on (the sentinel below),
        // instead of throwing for lack of a GoRouter ancestor.
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(path: '/', builder: (_, _) => const LoginScreen()),
            GoRoute(
              path: '/email-confirmation',
              builder: (_, _) =>
                  const Scaffold(body: Text('CONFIRMATION SENTINEL')),
            ),
          ],
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(mockRepo),
              hiveServiceProvider.overrideWithValue(mockHive),
              localeProvider.overrideWith(
                () => StubLocaleNotifier(const Locale('en')),
              ),
            ],
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return MaterialApp.router(
                  routerConfig: router,
                  theme: AppTheme.dark,
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                );
              },
            ),
          ),
        );
        await enterSignupMode(tester);

        // Fill every field so the validators would otherwise pass — the ONLY
        // thing blocking submit must be the unticked age checkbox.
        await fillField(tester, 'auth-display-name-input', 'Alice');
        await fillField(tester, 'auth-email-input', 'a@b.com');
        await fillField(tester, 'auth-password-input', 'secret1!');
        await fillField(tester, 'auth-confirm-password-input', 'secret1!');

        // Leave the age checkbox UNTICKED. Trigger the confirm field's
        // keyboard "Done" action (the BLOCKER path: a passive onFieldSubmitted
        // used to call _submit() directly, bypassing the age gate).
        await tester.showKeyboard(
          find.descendant(
            of: semanticsId('auth-confirm-password-input'),
            matching: find.byType(EditableText),
          ),
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump();

        // Behavior, not wiring: no sign-up fired → the user stays on the
        // signup screen (no navigation to the confirmation sentinel), the
        // pending-email state never lifts, and the repo is never called.
        expect(find.text('CONFIRMATION SENTINEL'), findsNothing);
        expect(container.read(signupPendingEmailProvider), isNull);
        verifyNever(
          () => mockRepo.signUpWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            locale: any(named: 'locale'),
            displayName: any(named: 'displayName'),
          ),
        );

        // Now tick the checkbox and repeat — the SAME keyboard submit MUST
        // fire the sign-up and lift the pending-email state.
        await tester.tap(ageCheckbox());
        await tester.pump();
        await tester.showKeyboard(
          find.descendant(
            of: semanticsId('auth-confirm-password-input'),
            matching: find.byType(EditableText),
          ),
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump();

        // User-visible outcome: the same keyboard "Done" now drives the user
        // to the email-confirmation screen.
        await tester.pumpAndSettle();
        expect(find.text('CONFIRMATION SENTINEL'), findsOneWidget);
        expect(container.read(signupPendingEmailProvider), 'a@b.com');
        verify(
          () => mockRepo.signUpWithEmail(
            email: 'a@b.com',
            password: 'secret1!',
            locale: any(named: 'locale'),
            displayName: 'Alice',
          ),
        ).called(1);
      },
    );

    testWidgets(
      'toggling back to Login then to Sign Up resets the checkbox state',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // Tick the checkbox.
        await tester.ensureVisible(ageCheckbox());
        await tester.pump();
        await tester.tap(ageCheckbox());
        await tester.pump();

        // CTA enabled.
        expect(
          tester.widget<GradientButton>(find.byType(GradientButton)).onPressed,
          isNotNull,
        );

        // Toggle back to login.
        await tester.ensureVisible(
          find.text('Already have an account? Log in'),
        );
        await tester.pump();
        await tester.tap(find.text('Already have an account? Log in'));
        await tester.pump();

        // Toggle back to signup.
        await enterSignupMode(tester);

        // CTA disabled again — checkbox was reset.
        await tester.ensureVisible(find.byType(GradientButton));
        await tester.pump();
        expect(
          tester.widget<GradientButton>(find.byType(GradientButton)).onPressed,
          isNull,
          reason: 'Toggling modes must reset the age-confirmation state',
        );
      },
    );
  });
}
