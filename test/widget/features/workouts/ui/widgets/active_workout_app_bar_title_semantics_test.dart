/// Family 3 / Family 6 — `ActiveWorkoutAppBarTitle` rename Semantics label.
/// Pre-PR the Semantics label was a hard-coded English literal
/// `'$name. Tap to rename workout.'`. Post-PR it flows through
/// `l10n.workoutNameTapToRenameSemantics(name)` so screen-reader users
/// hear the rename affordance in their own locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/active_workout_app_bar_title.dart';

import '../../../../../helpers/test_material_app.dart';

Widget _buildTitle({
  required String name,
  bool isEditing = false,
  Locale? locale,
}) {
  // ElapsedTimer is a ConsumerWidget — needs a ProviderScope ancestor.
  return ProviderScope(
    child: TestMaterialApp(
      theme: AppTheme.dark,
      locale: locale,
      home: Scaffold(
        appBar: AppBar(
          title: ActiveWorkoutAppBarTitle(
            name: name,
            isEditing: isEditing,
            nameController: TextEditingController(text: name),
            onSubmitName: () {},
            onTapToEdit: () {},
            startedAt: DateTime(2026, 5, 7, 9, 30).toUtc(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ActiveWorkoutAppBarTitle rename Semantics (Family 3/6)', () {
    testWidgets('en: Semantics label is "Push Day. Tap to rename workout."', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTitle(name: 'Push Day'));

      // The merged label includes the visible Text widget's content
      // ("Push Day") concatenated with the Semantics label. Use a regex
      // matcher so the test pins the localized contract without
      // depending on the merge layout.
      expect(
        find.bySemanticsLabel(RegExp(r'Push Day\. Tap to rename workout\.')),
        findsOneWidget,
        reason:
            'Family 3/6: the rename Semantics must be localized via '
            'l10n.workoutNameTapToRenameSemantics(name) and produce the '
            'en literal "Push Day. Tap to rename workout." (post-merge '
            'with the visible Text).',
      );
    });

    testWidgets(
      'pt: Semantics label is "Treino A. Toque para renomear o treino."',
      (tester) async {
        await tester.pumpWidget(
          _buildTitle(name: 'Treino A', locale: const Locale('pt')),
        );

        expect(
          find.bySemanticsLabel(
            RegExp(r'Treino A\. Toque para renomear o treino\.'),
          ),
          findsOneWidget,
          reason:
              'Family 3/6: the pt locale must read the rename affordance '
              'as "Toque para renomear o treino." — not the English literal.',
        );
      },
    );
  });
}
