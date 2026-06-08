// Option A (full-form signup) widget tests for LoginScreen's signup mode.
//
// Behavior-not-wiring per CLAUDE.md → Testing: every assertion pins a
// user-perceptible outcome — a field/heading the user sees, the strength
// label that appears, the validation error rendered on submit, the legal
// footer's presence/absence, the disabled-CTA helper text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';
import 'package:repsaga/shared/widgets/gradient_button.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  Widget buildTestWidget() {
    return ProviderScope(
      child: TestMaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );
  }

  Finder semanticsId(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> enterSignupMode(WidgetTester tester) async {
    await tester.ensureVisible(find.text("Don't have an account? Sign up"));
    await tester.pump();
    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pump();
  }

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

  group('Signup form — Option A', () {
    testWidgets(
      'shows the CREATE ACCOUNT heading + display-name + confirm-password '
      'fields in signup mode, none of which exist in login mode',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Login mode: no signup-only surfaces.
        expect(find.text('CREATE ACCOUNT'), findsNothing);
        expect(semanticsId('auth-display-name-input'), findsNothing);
        expect(semanticsId('auth-confirm-password-input'), findsNothing);
        expect(semanticsId('auth-password-strength'), findsNothing);

        await enterSignupMode(tester);

        // Signup mode: all four appear.
        expect(find.text('CREATE ACCOUNT'), findsOneWidget);
        expect(semanticsId('auth-display-name-input'), findsOneWidget);
        expect(semanticsId('auth-confirm-password-input'), findsOneWidget);
        expect(semanticsId('auth-password-strength'), findsOneWidget);
      },
    );

    testWidgets('strength bar surfaces the weak label for a 6-char password', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      await fillField(tester, 'auth-password-input', 'abcdef');
      expect(find.text('Weak — add more characters'), findsOneWidget);
    });

    testWidgets(
      'strength bar surfaces the medium label when a digit is added',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        await fillField(tester, 'auth-password-input', 'abcde1');
        expect(find.text('Medium — add numbers or symbols'), findsOneWidget);
      },
    );

    testWidgets(
      'strength bar surfaces the strong label for length+digit+symbol',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        await fillField(tester, 'auth-password-input', 'abcd1234!');
        expect(find.text('Strong password!'), findsOneWidget);
      },
    );

    testWidgets(
      'mismatched confirm-password shows the mismatch error on submit',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        await fillField(tester, 'auth-display-name-input', 'Alice');
        await fillField(tester, 'auth-email-input', 'a@b.com');
        await fillField(tester, 'auth-password-input', 'secret1!');
        await fillField(tester, 'auth-confirm-password-input', 'different1!');

        // Tick the age gate so the CTA is enabled, then submit.
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.ensureVisible(semanticsId('auth-signup-btn'));
        await tester.pump();
        await tester.tap(semanticsId('auth-signup-btn'));
        await tester.pump();

        expect(find.text('Passwords do not match'), findsOneWidget);
      },
    );

    testWidgets('matching confirm-password produces no mismatch error', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      await fillField(tester, 'auth-display-name-input', 'Alice');
      await fillField(tester, 'auth-email-input', 'a@b.com');
      await fillField(tester, 'auth-password-input', 'secret1!');
      await fillField(tester, 'auth-confirm-password-input', 'secret1!');

      // Validate the form by attempting submit (no router/notifier wired —
      // the validators run regardless). The mismatch error must be absent.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(semanticsId('auth-signup-btn'));
      await tester.pump();
      await tester.tap(semanticsId('auth-signup-btn'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsNothing);
    });

    testWidgets(
      'should show mismatch error when password is changed after confirm '
      'was typed',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // Password + confirm initially match.
        await fillField(tester, 'auth-display-name-input', 'Alice');
        await fillField(tester, 'auth-email-input', 'a@b.com');
        await fillField(tester, 'auth-password-input', 'secret1!');
        await fillField(tester, 'auth-confirm-password-input', 'secret1!');

        // Now overwrite ONLY the password field with a different value, leaving
        // the confirm field untouched. `_validateConfirmPassword` must read the
        // password controller's text lazily at validate-time and surface the
        // mismatch.
        await fillField(tester, 'auth-password-input', 'changed9!');

        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.ensureVisible(semanticsId('auth-signup-btn'));
        await tester.pump();
        await tester.tap(semanticsId('auth-signup-btn'));
        await tester.pump();

        expect(find.text('Passwords do not match'), findsOneWidget);
      },
    );

    testWidgets('empty display name shows the required error on submit', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      await fillField(tester, 'auth-email-input', 'a@b.com');
      await fillField(tester, 'auth-password-input', 'secret1!');
      await fillField(tester, 'auth-confirm-password-input', 'secret1!');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(semanticsId('auth-signup-btn'));
      await tester.pump();
      await tester.tap(semanticsId('auth-signup-btn'));
      await tester.pump();

      expect(find.text('Enter a name'), findsOneWidget);
    });

    testWidgets(
      'legal footer is shown in login mode and hidden in signup mode',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Login mode keeps the bottom footer.
        expect(find.text('By continuing, you agree to our '), findsOneWidget);

        await enterSignupMode(tester);

        // Signup mode suppresses the footer — the inline age-gate label
        // satisfies the LGPD disclosure instead.
        expect(find.text('By continuing, you agree to our '), findsNothing);
      },
    );

    testWidgets(
      'disabled-CTA helper text appears until the age checkbox is ticked',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // Before ticking: helper text present AND CTA disabled.
        expect(find.text('Confirm your age to continue'), findsOneWidget);
        expect(
          tester.widget<GradientButton>(find.byType(GradientButton)).onPressed,
          isNull,
        );

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        // After ticking: helper text gone AND CTA enabled.
        expect(find.text('Confirm your age to continue'), findsNothing);
        expect(
          tester.widget<GradientButton>(find.byType(GradientButton)).onPressed,
          isNotNull,
        );
      },
    );
  });
}
