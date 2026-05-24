import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/widgets/empty_session_guard_sheet.dart';

/// Pins the empty-session guard sheet's user-visible behavior:
///   - Tapping "Descartar" returns `EmptySessionGuardResult.discarded`.
///   - Tapping "Continuar treinando" returns `continueTraining`.
///   - Body / title / labels all render exactly as injected (no implicit
///     l10n via context — widget is l10n-harness-free per
///     `feedback_widget_l10n_parameterization`).
///
/// Tests use `showDialog`-style host so they don't need a router setup.
void main() {
  Future<void> openSheet(
    WidgetTester tester,
    Future<EmptySessionGuardResult> Function(BuildContext) trigger,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  // Capture the future the test will await via
                  // `trigger.then(...)` indirectly — we drive it through
                  // the visible button tap so MaterialApp is ready.
                  await trigger(context);
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders injected title / body / labels verbatim', (
    tester,
  ) async {
    await openSheet(tester, (context) async {
      return EmptySessionGuardSheet.show(
        context,
        title: 'CUSTOM TITLE',
        body: 'CUSTOM BODY',
        discardLabel: 'CUSTOM DISCARD',
        continueLabel: 'CUSTOM CONTINUE',
      );
    });
    expect(find.text('CUSTOM TITLE'), findsOneWidget);
    expect(find.text('CUSTOM BODY'), findsOneWidget);
    expect(find.text('CUSTOM DISCARD'), findsOneWidget);
    expect(find.text('CUSTOM CONTINUE'), findsOneWidget);
  });

  testWidgets('tap "Continuar" returns continueTraining', (tester) async {
    EmptySessionGuardResult? captured;
    await openSheet(tester, (context) async {
      final r = await EmptySessionGuardSheet.show(
        context,
        title: 't',
        body: 'b',
        discardLabel: 'discard-label',
        continueLabel: 'continue-label',
      );
      captured = r;
      return r;
    });
    await tester.tap(find.text('continue-label'));
    await tester.pumpAndSettle();
    expect(captured, EmptySessionGuardResult.continueTraining);
  });

  testWidgets('tap "Descartar" returns discarded', (tester) async {
    EmptySessionGuardResult? captured;
    await openSheet(tester, (context) async {
      final r = await EmptySessionGuardSheet.show(
        context,
        title: 't',
        body: 'b',
        discardLabel: 'discard-label',
        continueLabel: 'continue-label',
      );
      captured = r;
      return r;
    });
    await tester.tap(find.text('discard-label'));
    await tester.pumpAndSettle();
    expect(captured, EmptySessionGuardResult.discarded);
  });

  testWidgets(
    'sheet carries a semantics identifier so E2E selectors can target it',
    (tester) async {
      await openSheet(tester, (context) async {
        return EmptySessionGuardSheet.show(
          context,
          title: 't',
          body: 'b',
          discardLabel: 'd',
          continueLabel: 'c',
        );
      });
      expect(find.bySemanticsLabel(RegExp(r'^t$')), findsOneWidget);
      // Verify the identifier is present on the rendered sheet.
      final guarded = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.identifier == 'empty-session-guard-sheet',
      );
      expect(guarded, findsOneWidget);
    },
  );
}
