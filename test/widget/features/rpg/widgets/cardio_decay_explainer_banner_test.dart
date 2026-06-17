/// Widget tests for [CardioDecayExplainerBanner] — Phase 38e-bis.
///
/// The banner is a pure presentation surface: it renders the supplied message
/// + dismiss affordance and fires [onDismiss] when the X is tapped. One-time
/// gating lives at the call site (the stats screen), not here — these tests
/// pin the rendering + dismiss-callback contract only. Strings are passed in
/// as params (per `feedback_widget_l10n_parameterization`), so no l10n harness
/// is needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/cardio_decay_explainer_banner.dart';

import '../../../../helpers/test_material_app.dart';

const _message =
    'Cardio conditioning decays faster than strength — train it weekly to '
    'hold the line.';

Widget _wrap({VoidCallback? onDismiss}) {
  return TestMaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: CardioDecayExplainerBanner(
          message: _message,
          dismissLabel: 'Dismiss',
          onDismiss: onDismiss ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('CardioDecayExplainerBanner', () {
    testWidgets('renders the supplied message', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text(_message), findsOneWidget);
    });

    testWidgets('tapping the X fires onDismiss', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(_wrap(onDismiss: () => dismissed++));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dismissed, 1);
    });

    testWidgets('renders without overflow at 320dp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The long message wraps across lines rather than overflowing.
      expect(find.text(_message), findsOneWidget);
    });

    testWidgets('exposes the cardio-decay-explainer Semantics identifier', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final semantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.identifier == 'cardio-decay-explainer')
          .toList();
      expect(semantics.length, 1);
    });
  });
}
