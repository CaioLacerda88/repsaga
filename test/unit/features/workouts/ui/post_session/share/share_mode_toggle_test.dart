import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/domain/share_mode.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_mode_toggle.dart';

/// Pins the Phase 39 share-mode toggle. Behavior: the selected segment is
/// visually highlighted; tapping a segment fires the callback with its mode.
void main() {
  Widget host({required ShareMode mode, required ValueChanged<ShareMode> on}) {
    return MaterialApp(
      home: Scaffold(
        body: ShareModeToggle(
          mode: mode,
          bestiaryLabel: 'Bestiário',
          cleanFlexLabel: 'Stats',
          onChanged: on,
        ),
      ),
    );
  }

  testWidgets('selected segment is highlighted (primaryViolet fill)', (
    tester,
  ) async {
    await tester.pumpWidget(host(mode: ShareMode.bestiary, on: (_) {}));

    // The selected (bestiary) segment's Material reads the selected fill;
    // the unselected (stats) segment is transparent.
    final bestiaryMaterial = tester.widget<Material>(
      find
          .ancestor(of: find.text('Bestiário'), matching: find.byType(Material))
          .first,
    );
    expect(bestiaryMaterial.color, AppColors.primaryViolet);

    final statsMaterial = tester.widget<Material>(
      find
          .ancestor(of: find.text('Stats'), matching: find.byType(Material))
          .first,
    );
    expect(statsMaterial.color, Colors.transparent);
  });

  testWidgets('tapping a segment fires onChanged with its mode', (
    tester,
  ) async {
    ShareMode? picked;
    await tester.pumpWidget(
      host(mode: ShareMode.bestiary, on: (m) => picked = m),
    );

    await tester.tap(find.text('Stats'));
    await tester.pump();

    expect(picked, ShareMode.cleanFlex);
  });
}
