/// Widget tests for [CelebrationOverflowCard] (Phase 18c).
///
/// Spec §13 / WIP: non-modal condensed card "N more rank-ups — open Saga".
/// 4s auto-dismiss, tappable to route handler, copy renders pluralized count,
/// muted "tap to continue" hint signals discoverability.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/overlays/celebration_overflow_card.dart';
import 'package:repsaga/features/rpg/ui/overlays/rank_up_overflow_flipbook.dart';

import '../../../../helpers/test_material_app.dart';

Widget _wrap({
  required int count,
  VoidCallback? onTap,
  VoidCallback? onAutoDismiss,
}) => TestMaterialApp(
  home: Scaffold(
    body: Center(
      child: CelebrationOverflowCard(
        overflowCount: count,
        onTap: onTap ?? () {},
        onAutoDismiss: onAutoDismiss ?? () {},
      ),
    ),
  ),
);

void main() {
  group('CelebrationOverflowCard', () {
    testWidgets('renders flipbook label "+{N} ranks" (BUG-013)', (
      tester,
    ) async {
      // BUG-013 (Cluster 3): the text "{N} more rank-ups — open Saga"
      // was replaced with a mini-flipbook (3 cycling muscle sigils) +
      // a Rajdhani 700 24sp "+{N} ranks" label. The "open Saga"
      // affordance moved to the AOM accessible label so existing E2E
      // selectors still find the card by accessible name.
      await tester.pumpWidget(_wrap(count: 2));
      await tester.pump();

      expect(find.text('+2 ranks'), findsOneWidget);
    });

    testWidgets('renders the same "+{N} ranks" label for singular count', (
      tester,
    ) async {
      // English copy ships with a fixed plural form "ranks" — short and
      // gym-vernacular. Singular is rare here (overflow only triggers
      // when 4+ rank-ups fire) but pin the contract: count == 1 still
      // reads cleanly.
      await tester.pumpWidget(_wrap(count: 1));
      await tester.pump();

      expect(find.text('+1 ranks'), findsOneWidget);
    });

    testWidgets('renders muted "Tap to continue" hint for discoverability', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(count: 2));
      await tester.pump();

      expect(find.text('Tap to continue'), findsOneWidget);
    });

    testWidgets('tap invokes onTap callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(count: 2, onTap: () => taps += 1));
      await tester.pump();

      await tester.tap(find.byType(CelebrationOverflowCard));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('auto-dismisses after 4 seconds', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _wrap(count: 2, onAutoDismiss: () => dismissed += 1),
      );
      await tester.pump();
      // Before 4s tick — no fire yet.
      await tester.pump(const Duration(milliseconds: 3900));
      expect(dismissed, 0);
      // After 4s tick — fires once.
      await tester.pump(const Duration(milliseconds: 200));
      expect(dismissed, 1);

      // Settle the widget (it may still be rendering).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'embeds the RankUpOverflowFlipbook with three muscle sigils (BUG-013)',
      (tester) async {
        // The flipbook is the visual hero of the card — three muscle
        // SVG sigils cycling left-to-right. Find by widget type rather
        // than by SVG string so the test survives an asset re-pathing.
        await tester.pumpWidget(_wrap(count: 5));
        await tester.pump();

        expect(find.byType(RankUpOverflowFlipbook), findsOneWidget);
        expect(find.text('+5 ranks'), findsOneWidget);
      },
    );

    testWidgets('does NOT auto-dismiss after unmount', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _wrap(count: 5, onAutoDismiss: () => dismissed += 1),
      );
      await tester.pump();
      // Sanity: timer hasn't fired immediately.
      expect(dismissed, 0);

      // Replace the widget BEFORE the 4s timer elapses — the timer should
      // not invoke onAutoDismiss after the widget is unmounted.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 3000));
      expect(dismissed, 0);
    });
  });
}
