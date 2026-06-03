/// Widget tests for [CodexNavRow] — the full-width tappable codex row used
/// for the three secondary navigation entries (Stats / Titles / History) on
/// the character sheet.
///
/// **Locked behaviors:**
///   * Renders the label and a trailing chevron.
///   * Tapping invokes the supplied callback.
///   * When `semanticIdentifier` is supplied the row exposes a stable
///     `Semantics(container: true, explicitChildNodes: true,
///     identifier: ...)` node — the pair-rule that prevents Flutter web's
///     AOM from eliding the `flt-semantics-identifier` on rebuild
///     (cluster: semantics-identifier-pair-rule).
///   * The identifier survives a rebuild — pumping twice does not drop the
///     SemanticsNode (the original failure mode the cluster guards against).
///   * When `semanticIdentifier` is null, no Semantics wrapper is mounted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/codex_nav_row.dart';

import '../../../../../helpers/test_material_app.dart';

void main() {
  group('CodexNavRow', () {
    testWidgets('should render the label and a chevron', (tester) async {
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: CodexNavRow(label: 'Stats', onTap: () {}),
          ),
        ),
      );

      expect(find.text('Stats'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('should invoke onTap when the row is tapped', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: CodexNavRow(label: 'Stats', onTap: () => tapped++),
          ),
        ),
      );

      await tester.tap(find.byType(CodexNavRow));
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('should expose a stable Semantics identifier when supplied', (
      tester,
    ) async {
      // Cluster: semantics-identifier-pair-rule. Pinning the container +
      // explicitChildNodes pair-rule via find.bySemanticsIdentifier
      // (which only matches when the SemanticsNode carries an
      // identifier AND is reachable in the semantics tree). If either
      // flag regressed, the AOM would elide the node and this finder
      // would return zero hits.
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: CodexNavRow(
              label: 'Stats',
              semanticIdentifier: 'codex-nav-stats',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsIdentifier('codex-nav-stats'), findsOneWidget);
    });

    testWidgets('should keep the Semantics identifier across rebuilds', (
      tester,
    ) async {
      // Cluster: semantics-identifier-pair-rule. The original failure
      // mode the cluster guards against: a SemanticsNode is reused
      // across rebuilds but the identifier-only mutation never makes
      // it into the AOM (cluster: flutter-web-identifier-transition-
      // stale). With container:true + explicitChildNodes:true the
      // node is forced as its own scope, so pump-twice cannot drop it.
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: CodexNavRow(
              label: 'Stats',
              semanticIdentifier: 'codex-nav-stats',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsIdentifier('codex-nav-stats'), findsOneWidget);

      // Force a rebuild with the same identifier — the SemanticsNode
      // must still be present.
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: CodexNavRow(
              label: 'Stats',
              semanticIdentifier: 'codex-nav-stats',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsIdentifier('codex-nav-stats'), findsOneWidget);
    });

    testWidgets(
      'should not mount a Semantics identifier when none is supplied',
      (tester) async {
        await tester.pumpWidget(
          TestMaterialApp(
            home: Scaffold(
              body: CodexNavRow(label: 'Stats', onTap: () {}),
            ),
          ),
        );

        expect(find.bySemanticsIdentifier('codex-nav-stats'), findsNothing);
      },
    );
  });
}
