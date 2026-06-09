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
      'shows the CREATE ACCOUNT heading + display-name field + strength bar '
      'in signup mode, none of which exist in login mode',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Login mode: no signup-only surfaces.
        expect(find.text('CREATE ACCOUNT'), findsNothing);
        expect(semanticsId('auth-display-name-input'), findsNothing);
        expect(semanticsId('auth-password-strength'), findsNothing);

        await enterSignupMode(tester);

        // Signup mode: the signup-only surfaces appear. The confirm-password
        // field was dropped (UX option a — the reveal toggle is the typo-safety
        // net), so there is no `auth-confirm-password-input`.
        expect(find.text('CREATE ACCOUNT'), findsOneWidget);
        expect(semanticsId('auth-display-name-input'), findsOneWidget);
        expect(semanticsId('auth-password-strength'), findsOneWidget);
      },
    );

    testWidgets('strength bar surfaces the weak label for a 6-char password', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      // "abcdef" — len 6, no digit, no symbol → weak tier, highest-priority
      // unmet requirement is length.
      await fillField(tester, 'auth-password-input', 'abcdef');
      expect(find.text('Weak — use 8+ characters'), findsOneWidget);
    });

    testWidgets(
      'strength hint names the missing requirement, not a generic phrase',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // "Test12." already has a digit AND a symbol; it is ONLY short on
        // length (7 chars). The hint must name length, not the stale generic
        // "add numbers or symbols" — the misleading-hint bug this PR fixes.
        await fillField(tester, 'auth-password-input', 'Test12.');
        expect(find.text('Medium — use 8+ characters'), findsOneWidget);
        expect(find.text('Medium — add numbers or symbols'), findsNothing);
      },
    );

    testWidgets(
      'strength hint asks for a number when length is met but no digit',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // "testtest" — len 8, no digit, no symbol → length met, next-priority
        // unmet requirement is number.
        await fillField(tester, 'auth-password-input', 'testtest');
        expect(find.text('Medium — add a number'), findsOneWidget);
      },
    );

    testWidgets(
      'strength hint asks for a symbol when only the symbol is missing',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // "Test12ab" — len 8, has digit, no symbol → only symbol unmet.
        await fillField(tester, 'auth-password-input', 'Test12ab');
        expect(find.text('Medium — add a symbol'), findsOneWidget);
      },
    );

    testWidgets(
      'strength bar surfaces the strong label for length+digit+symbol',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        await fillField(tester, 'auth-password-input', 'Test12.ab');
        expect(find.text('Strong password!'), findsOneWidget);
      },
    );

    testWidgets('empty display name shows the required error on submit', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      await fillField(tester, 'auth-email-input', 'a@b.com');
      await fillField(tester, 'auth-password-input', 'secret1!');

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

    testWidgets(
      'email field stays unobscured after toggling to signup mode while the '
      'password field stays obscured (no sibling State reuse) — regression',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Toggle to signup: this inserts the display-name field ABOVE email,
        // shifting field positions. Before the fix (stable keys +
        // AppTextField.didUpdateWidget syncing _obscured), Flutter reused the
        // password field's State for the email widget and email rendered
        // masked. cluster: missing-key-state-reuse.
        await enterSignupMode(tester);
        await tester.pump();

        EditableText editableFor(String id) => tester.widget<EditableText>(
          find.descendant(
            of: semanticsId(id),
            matching: find.byType(EditableText),
          ),
        );

        // User-perceptible outcome: email shows real characters (not dots),
        // password masks them. (Confirm field dropped — UX option a.)
        expect(
          editableFor('auth-email-input').obscureText,
          isFalse,
          reason: 'Email must never render masked.',
        );
        expect(editableFor('auth-password-input').obscureText, isTrue);
      },
    );

    testWidgets(
      'reveal hint appears in signup mode and dismisses after first eye tap',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);
        await fillField(tester, 'auth-password-input', 'Test12.ab');

        // The ghost hint is the typo-safety education that replaces the
        // dropped confirm field — present before any eye tap.
        expect(find.text('Tap the eye to check your password'), findsOneWidget);

        // Tapping the password reveal eye dismisses the hint permanently.
        await tester.tap(find.byIcon(Icons.visibility_off));
        await tester.pump();

        expect(find.text('Tap the eye to check your password'), findsNothing);
      },
    );
  });
}
