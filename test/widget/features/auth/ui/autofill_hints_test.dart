// Phase 32 PR 32b: pin the OS-autofill contract for LoginScreen.
//
// The user-visible behavior is the Android Credential Manager (API 34+) save
// / fill chip — a widget test cannot drive that. The next-best pinning is
// the [TextFormField.autofillHints] value Flutter writes into the platform
// channel: `email` for the email field, `password` for the password field
// in login mode, `newPassword` in signup mode. A regression that drops one
// of these breaks the OS handoff silently — this test fails loud instead.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  Widget buildTestWidget() {
    return ProviderScope(
      child: TestMaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );
  }

  // `TextFormField` does not re-expose `autofillHints` as a getter — it
  // forwards to the underlying `TextField`, which in turn forwards to
  // `EditableText`. Read the resolved value off `EditableText`.
  Iterable<String>? autofillHintsOf(WidgetTester tester, Finder identifier) {
    final editable = tester.widget<EditableText>(
      find.descendant(of: identifier, matching: find.byType(EditableText)),
    );
    return editable.autofillHints;
  }

  group('LoginScreen autofill hints', () {
    testWidgets('email field exposes AutofillHints.email', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final emailField = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == 'auth-email-input',
      );
      expect(emailField, findsOneWidget);

      expect(
        autofillHintsOf(tester, emailField),
        equals(const [AutofillHints.email]),
      );
    });

    testWidgets('login mode: password field exposes AutofillHints.password', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      final passwordField = find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.identifier == 'auth-password-input',
      );
      expect(passwordField, findsOneWidget);

      expect(
        autofillHintsOf(tester, passwordField),
        equals(const [AutofillHints.password]),
      );
    });

    testWidgets(
      'signup mode: password field switches to AutofillHints.newPassword',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Toggle to signup mode. The toggle button is below the fold on the
        // 800x600 test viewport.
        await tester.ensureVisible(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'auth-toggle-signup',
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'auth-toggle-signup',
          ),
        );
        await tester.pump();

        final passwordField = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'auth-password-input',
        );
        expect(passwordField, findsOneWidget);

        expect(
          autofillHintsOf(tester, passwordField),
          equals(const [AutofillHints.newPassword]),
        );
      },
    );

    testWidgets('form is wrapped in an AutofillGroup', (tester) async {
      // The OS only surfaces save/fill prompts when the fields share an
      // AutofillGroup ancestor. Without this, the per-field
      // `autofillHints` are ignored on commit. `find.descendant` pins the
      // wrapping relationship — a regression that pulls the AutofillGroup
      // out of the form (or wraps only one field) fails loud here.
      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(AutofillGroup), findsOneWidget);

      expect(
        find.descendant(
          of: find.byType(AutofillGroup),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.identifier == 'auth-email-input',
          ),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byType(AutofillGroup),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'auth-password-input',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'AutofillGroup has onDisposeAction: cancel (no spurious OS save prompt on abandon)',
      (tester) async {
        // User-visible behavior: navigating away mid-flow (toggling mode,
        // pressing back) must NOT surface an OS "Save credentials?" prompt
        // for the partial or wrong credentials typed so far.
        //
        // The only mechanism that prevents this is
        // `AutofillGroup.onDisposeAction = AutofillContextAction.cancel`.
        // Without it Flutter defaults to `commit`, which asks the OS to save
        // whatever is in the fields at dispose time — including the wrong
        // password a user typed before realising they had the wrong account.
        //
        // This test pins the contract so a future "just clean up the params"
        // refactor cannot silently revert to the default-commit behaviour.
        await tester.pumpWidget(buildTestWidget());

        final group = tester.widget<AutofillGroup>(find.byType(AutofillGroup));
        expect(
          group.onDisposeAction,
          equals(AutofillContextAction.cancel),
          reason:
              'onDisposeAction must be cancel so that abandoning the form '
              'mid-flow (back-press, mode toggle) never triggers the OS '
              'save-credentials prompt with partial or wrong credentials.',
        );
      },
    );
  });
}
