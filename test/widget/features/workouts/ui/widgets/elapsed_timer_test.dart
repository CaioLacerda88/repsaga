/// PR-5 M7 — WCAG AA contrast pin for [ElapsedTimer].
///
/// Pre-fix the timer used `theme.colorScheme.primary` (primaryViolet
/// #6A2FA8) on the abyss (#0D0319) background — ~2.6:1 contrast ratio,
/// failing AA's 4.5:1 floor for body text. Post-fix the color is
/// [AppColors.hotViolet] (#B36DFF, ~5.9:1, passes AA).
///
/// This test reads the rendered Text widget's resolved style and asserts
/// the color is hotViolet. A future refactor that swaps the color back to
/// `theme.colorScheme.primary` (or any other lower-contrast token) flips
/// this pin and the AA regression is caught at unit-test time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/elapsed_timer.dart';

import '../../../../../helpers/test_material_app.dart';

Widget _host(DateTime startedAt) {
  return ProviderScope(
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: ElapsedTimer(startedAt: startedAt)),
    ),
  );
}

void main() {
  group('ElapsedTimer', () {
    testWidgets(
      'M7 (PR-5) — text color is AppColors.hotViolet (~5.9:1 contrast '
      'against abyss, passes WCAG AA)',
      (tester) async {
        // The provider stream emits the first tick asynchronously; the
        // initial frame shows the "loading" placeholder "00:00". Either
        // text is fine for the color assertion — both flow through the
        // same `style.color` parameter.
        await tester.pumpWidget(_host(DateTime.now().toUtc()));
        await tester.pump();

        final timer = tester.widget<Text>(find.byType(Text));
        expect(
          timer.style?.color,
          AppColors.hotViolet,
          reason:
              'M7 (PR-5): elapsed timer must render in hotViolet for AA '
              'contrast. Swapping back to theme.colorScheme.primary '
              '(primaryViolet) drops the ratio to ~2.6:1 and fails AA. '
              'Do not regress without verifying contrast against the '
              'active background.',
        );
      },
    );
  });
}
