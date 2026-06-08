import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/ui/login_screen.dart';
import 'package:repsaga/shared/widgets/gradient_button.dart';

import '../../../../helpers/test_material_app.dart';

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
