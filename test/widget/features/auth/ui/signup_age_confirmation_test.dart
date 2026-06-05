import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';
import 'package:repsaga/shared/widgets/gradient_button.dart';

import '../../../../helpers/test_material_app.dart';

/// Legal PR 2 — Surface 1 (age confirmation) widget tests.
///
/// Cluster: `data-protection-compliance`. The Sign Up CTA must remain
/// disabled until the age-confirmation checkbox is ticked (LGPD Art. 14
/// minimum-age compliance). These tests assert what the user SEES — the
/// `GradientButton.onPressed == null` state — not the internal flag,
/// per CLAUDE.md A2 "behavior-not-wiring".
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

  group('Signup age-confirmation checkbox', () {
    testWidgets('checkbox is shown in signup mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      expect(
        find.text('I confirm I am 18 years of age or older.'),
        findsOneWidget,
      );
      expect(find.text('Read the minimum-age policy.'), findsOneWidget);
    });

    testWidgets('checkbox is hidden in login mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(
        find.text('I confirm I am 18 years of age or older.'),
        findsNothing,
      );
    });

    testWidgets('sign-up CTA is DISABLED before the checkbox is ticked', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await enterSignupMode(tester);

      // Ensure the CTA is on screen, then read its onPressed.
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

      await tester.ensureVisible(
        find.text('I confirm I am 18 years of age or older.'),
      );
      await tester.pump();
      await tester.tap(find.text('I confirm I am 18 years of age or older.'));
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
      expect(
        find.text('I confirm I am 18 years of age or older.'),
        findsNothing,
      );

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
      'toggling back to Login then to Sign Up resets the checkbox state',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await enterSignupMode(tester);

        // Tick the checkbox.
        await tester.ensureVisible(
          find.text('I confirm I am 18 years of age or older.'),
        );
        await tester.pump();
        await tester.tap(find.text('I confirm I am 18 years of age or older.'));
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
