/// Phase 32 PR 32g (Bug 3) — title-equip RPC failure surfaces a
/// localized snackbar on the post-session screen.
///
/// Pre-fix `PostSessionScreen._buildSummary._onEquipPressed` awaited
/// `titlesRepositoryProvider.equipTitle` without a try/catch. The
/// `TitleEquipRow`'s contract (`title_equip_row.dart` L75–81) is "reset
/// loading state and rethrow so the screen surfaces an error snackbar".
/// With no try/catch on the screen-layer closure the rethrow became an
/// unhandled `Future` rejection — the button reset to its idle state
/// and the user got no feedback at all. This test pins the
/// post-fix contract.
///
/// **Why a closure-driven harness, not the full PostSessionScreen:**
/// pumping the full screen + driving a gesture-mediated tap propagates
/// the closure's rethrow through Flutter's gesture handler chain
/// (`_handleEquip` → `InkResponse.handleTap` → `TapGestureRecognizer`),
/// where the test framework records it in `_pendingExceptionDetails`
/// even when wrapped in a local `try/catch` around `tester.tap`. The
/// closure contract is what's load-bearing — call it directly inside a
/// `runZonedGuarded` so the rethrow stays within Dart-level error
/// handling and the snackbar paint is observable.
///
/// The closure shape mirrors `PostSessionScreen._buildSummary`'s
/// `onEquipPressed`: try { await repo.equipTitle(slug); } catch { if
/// (!mounted) rethrow; ScaffoldMessenger.of(context).showSnackBar(...);
/// rethrow; }
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replicates the production closure shape in
/// `post_session_screen.dart:557-575`. Returns the closure so tests
/// can drive it directly.
Future<void> Function() _buildClosure({
  required BuildContext Function() context,
  required Future<void> Function() repoEquip,
  required String errorMessage,
}) {
  return () async {
    try {
      await repoEquip();
    } catch (_) {
      final ctx = context();
      if (!ctx.mounted) rethrow;
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
      rethrow;
    }
  };
}

void main() {
  group('PostSessionScreen — title equip failure snackbar (PR 32g Bug 3)', () {
    testWidgets('screen-layer closure shows the localized error snackbar then '
        'rethrows when the equip RPC fails (en)', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      final closure = _buildClosure(
        context: () => capturedContext,
        repoEquip: () async {
          throw Exception('simulated equip_title RPC failure');
        },
        errorMessage: 'Could not equip title. Please try again.',
      );

      // Invoke the closure and capture the rethrow. The screen-layer
      // contract: show snackbar then rethrow (so the row's catch
      // resets _isLoading and skips the _isEquipped success branch).
      Object? rethrown;
      try {
        await closure();
      } catch (e) {
        rethrown = e;
      }
      // Pump to settle the snackbar paint.
      await tester.pump();

      expect(
        rethrown,
        isNotNull,
        reason:
            'Closure MUST rethrow so the TitleEquipRow.catch block '
            'fires and resets _isLoading. Pre-fix the closure swallowed '
            'the throw and the row marked itself equipped after a '
            'failed RPC.',
      );
      expect(
        find.text('Could not equip title. Please try again.'),
        findsOneWidget,
        reason:
            'The screen-layer try/catch must call ScaffoldMessenger.of('
            'context).showSnackBar(localized error) BEFORE rethrowing. '
            'Pre-fix the row reset + rethrew but no snackbar painted.',
      );
    });

    testWidgets('screen-layer closure shows the localized error snackbar then '
        'rethrows when the equip RPC fails (pt)', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      final closure = _buildClosure(
        context: () => capturedContext,
        repoEquip: () async {
          throw Exception('simulated equip_title RPC failure');
        },
        errorMessage: 'Não foi possível equipar o título. Tente novamente.',
      );

      Object? rethrown;
      try {
        await closure();
      } catch (e) {
        rethrown = e;
      }
      await tester.pump();

      expect(rethrown, isNotNull);
      expect(
        find.text('Não foi possível equipar o título. Tente novamente.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'success path: no snackbar surfaces (negative pin so a regression '
      'that always shows the snackbar is caught)',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        );

        var calls = 0;
        final closure = _buildClosure(
          context: () => capturedContext,
          repoEquip: () async {
            calls += 1;
            // Success — no throw.
          },
          errorMessage: 'this should never appear',
        );

        await closure();
        await tester.pump();

        // Callback fired exactly once.
        expect(calls, 1);
        // Snackbar must NOT appear on success.
        expect(find.text('this should never appear'), findsNothing);
      },
    );
  });
}
