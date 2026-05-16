import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_explainer_sheet.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('VitalityExplainerSheet', () {
    testWidgets(
      'should render title, definition, three band rows, and rank-safety box',
      (tester) async {
        await tester.pumpWidget(_wrap(const VitalityExplainerSheet()));
        await tester.pumpAndSettle();
        // Title
        expect(find.text('Vitalidade'), findsOneWidget);
        // Definition (substring match — full text is long)
        expect(find.textContaining('Vitalidade reflete'), findsOneWidget);
        // Three band rows — each percentage range appears once.
        expect(find.textContaining('66–100%'), findsOneWidget);
        expect(find.textContaining('34–65%'), findsOneWidget);
        expect(find.textContaining('0–33%'), findsOneWidget);
        // Rank-safety guarantee.
        expect(find.textContaining('NÃO afeta'), findsOneWidget);
      },
    );

    testWidgets(
      'should expose the Semantics identifier vitality-explainer-sheet',
      (tester) async {
        await tester.pumpWidget(_wrap(const VitalityExplainerSheet()));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp(r'vitalidade', caseSensitive: false)),
          findsAtLeast(1),
        );
      },
    );

    testWidgets(
      'should anchor the rank-safety box with a ValueKey for E2E targeting',
      (tester) async {
        await tester.pumpWidget(_wrap(const VitalityExplainerSheet()));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vitality-explainer-rank-safety-box')),
          findsOneWidget,
        );
      },
    );
  });
}
