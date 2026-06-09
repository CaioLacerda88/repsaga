import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';
import '../../../../helpers/test_material_app.dart';

void main() {
  Widget buildTestWidget({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: TestMaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );
  }

  group('LoginScreen', () {
    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('shows LOG IN button by default', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('LOG IN'), findsOneWidget);
    });

    testWidgets('toggles to sign up mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // The Arcane brand sigil (96dp) + form pushes the signup toggle below
      // the default 800x600 test viewport, so scroll it into view first.
      await tester.ensureVisible(find.text("Don't have an account? Sign up"));
      await tester.pump();
      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pump();

      expect(find.text('SIGN UP'), findsOneWidget);
      // Option A — the dim "Create your account" subtitle was promoted to a
      // Rajdhani-700 "CREATE ACCOUNT" heading.
      expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    });

    testWidgets('toggles back to login mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.ensureVisible(find.text("Don't have an account? Sign up"));
      await tester.pump();
      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pump();

      await tester.ensureVisible(find.text('Already have an account? Log in'));
      await tester.pump();
      await tester.tap(find.text('Already have an account? Log in'));
      await tester.pump();

      expect(find.text('LOG IN'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('validates empty email', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('LOG IN'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('validates invalid email', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextFormField).first, 'notanemail');
      await tester.tap(find.text('LOG IN'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('validates email without domain extension', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextFormField).first, 'user@domain');
      await tester.tap(find.text('LOG IN'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('accepts valid email', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(
        find.byType(TextFormField).first,
        'user@domain.com',
      );
      await tester.enterText(find.byType(TextFormField).last, '123456');
      await tester.tap(find.text('LOG IN'));
      await tester.pump();

      // No email validation error should appear
      expect(find.text('Enter a valid email'), findsNothing);
      expect(find.text('Email is required'), findsNothing);
    });

    testWidgets('validates empty password', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
      await tester.tap(find.text('LOG IN'));
      await tester.pump();

      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('validates short password', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
      await tester.enterText(find.byType(TextFormField).last, '12345');
      await tester.tap(find.text('LOG IN'));
      await tester.pump();

      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });

    testWidgets('shows Google sign in button', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('shows RepSaga header', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('RepSaga'), findsOneWidget);
    });

    testWidgets(
      'renders the Arcane brand sigil (not a generic dumbbell icon)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // The login hero must render the launcher-icon foreground asset so
        // the first frame matches the phone launcher the user just tapped.
        // Regression: the pre-17.0d build shipped `Icon(Icons.fitness_center)`.
        final imageFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/app_icon/arcane_sigil_foreground.png',
        );
        expect(imageFinder, findsOneWidget);
      },
    );

    testWidgets('brand sigil is 96dp on the login hero (size spec §17.0d)', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // §17.0d spec: login hero sigil is 96dp (up from the 48dp Material
      // icon it replaces). A smaller size would look unbalanced against the
      // 32dp displayMedium wordmark below.
      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/app_icon/arcane_sigil_foreground.png',
        ),
      );
      expect(image.width, 96.0);
      expect(image.height, 96.0);
    });

    testWidgets('shows forgot password link in login mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('hides forgot password in signup mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.ensureVisible(find.text("Don't have an account? Sign up"));
      await tester.pump();
      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pump();

      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('shows password visibility toggle', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Password field should have a visibility toggle icon
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('toggles password visibility', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Initially obscured (visibility_off shown)
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);

      // Tap to show password
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });

    testWidgets('forgot password shows error when email is empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Forgot password?'));
      await tester.pump();

      // Should show inline error asking to enter email first
      expect(
        find.text('Enter your email above, then tap "Forgot password?"'),
        findsOneWidget,
      );
    });

    // Locates the password field's EditableText by walking down from the
    // `auth-password-input` Semantics identifier. Option A added a
    // display-name + confirm-password field, so `find.byType(TextFormField)
    // .last` is no longer the password field in signup mode (it's the confirm
    // field) — target the identifier to stay unambiguous across modes.
    EditableText passwordEditable(WidgetTester tester) {
      return tester.widget<EditableText>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'auth-password-input',
          ),
          matching: find.byType(EditableText),
        ),
      );
    }

    // PO-004: toggling login→signup must clear the password field so a user
    // cannot accidentally carry a password from one mode to the other.
    testWidgets('PO-004: toggling to sign-up mode clears the password field', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // Type a password in login mode (login has only email+password, so the
      // password field is the last TextFormField here).
      await tester.enterText(find.byType(TextFormField).last, 'mySecret123');

      // Switch to sign-up mode.
      await tester.ensureVisible(find.text("Don't have an account? Sign up"));
      await tester.pump();
      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pump();

      // The password field must be empty after the toggle.
      expect(passwordEditable(tester).controller.text, isEmpty);
    });

    testWidgets(
      'PO-004: toggling back to login mode clears the password field',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Navigate to sign-up mode and enter a password (by identifier so we
        // hit the password field, not the confirm field).
        await tester.ensureVisible(find.text("Don't have an account? Sign up"));
        await tester.pump();
        await tester.tap(find.text("Don't have an account? Sign up"));
        await tester.pump();
        await tester.enterText(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.identifier == 'auth-password-input',
            ),
            matching: find.byType(EditableText),
          ),
          'signupPass',
        );

        // Switch back to login mode.
        await tester.ensureVisible(
          find.text('Already have an account? Log in'),
        );
        await tester.pump();
        await tester.tap(find.text('Already have an account? Log in'));
        await tester.pump();

        // The password field must be empty.
        expect(passwordEditable(tester).controller.text, isEmpty);
      },
    );

    testWidgets('shows legal links footer with Terms and Privacy buttons', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // The intro copy plus both link buttons must be present.
      expect(find.text('By continuing, you agree to our '), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('legal footer links are wired to TextButtons', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Both links must be tappable TextButtons (we don't assert navigation
      // here because the login test harness doesn't mount GoRouter).
      expect(
        find.ancestor(
          of: find.text('Terms of Service'),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Privacy Policy'),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
    });
  });
}
