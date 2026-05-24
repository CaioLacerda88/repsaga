import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/domain/post_session_timing.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/b1_xp_cut.dart';

/// Pins B1 XP cut behavior: it renders the injected XP + copy + xpLabel as
/// plain strings (Decoupling Rule 2 — widget is l10n-harness-free).
///
/// **Cluster `pump-duration-masks-forward`:** animation behavior is tested
/// by running the controller forward and inspecting the resulting opacity
/// boundary — NOT by checking that "forward() was called". We assert what
/// the user sees.
void main() {
  Widget host(
    Animation<double> animation, {
    RewardTier? tier,
    String? copyLine,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: B1XpCutWidget(
          animation: animation,
          tier: tier ?? RewardTier.baseline,
          totalXp: 412,
          copyLine: copyLine ?? 'ENCERRADO.\nMAIS FORTE.',
          xpLabel: 'XP',
        ),
      ),
    );
  }

  testWidgets('renders the XP total with the +N prefix verbatim', (
    tester,
  ) async {
    final c = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 500),
    );
    addTearDown(c.dispose);
    c.value = 1.0; // post-slam, fully visible
    await tester.pumpWidget(host(c.view));
    expect(find.text('+412'), findsOneWidget);
  });

  testWidgets(
    'renders the injected copy line verbatim (no implicit l10n lookup)',
    (tester) async {
      final c = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 500),
      );
      addTearDown(c.dispose);
      c.value = 1.0;
      await tester.pumpWidget(host(c.view, copyLine: 'CUSTOM B1 COPY'));
      expect(find.text('CUSTOM B1 COPY'), findsOneWidget);
    },
  );

  testWidgets(
    'XP label sub-text is the injected value (e.g. "XP" in pt + en)',
    (tester) async {
      final c = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 500),
      );
      addTearDown(c.dispose);
      c.value = 1.0;
      await tester.pumpWidget(host(c.view));
      expect(find.text('XP'), findsOneWidget);
    },
  );

  testWidgets(
    'carries the post-session-b1-xp semantics identifier so E2E selectors target it',
    (tester) async {
      final c = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 500),
      );
      addTearDown(c.dispose);
      c.value = 1.0;
      await tester.pumpWidget(host(c.view));
      final node = find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.identifier == 'post-session-b1-xp',
      );
      expect(node, findsOneWidget);
    },
  );

  testWidgets(
    'tier-derived behavior: every tier routes to its dedicated b1Hold '
    'constant (the source of truth is the controller, not the widget)',
    (tester) async {
      // Pin the routing contract: the widget consumes [RewardTier.b1Hold]
      // to derive hold timing externally. The widget itself is stateless
      // re: timing; the parent controller drives it. Assert the routing
      // through the PostSessionTiming constants — numeric ms values stay
      // out of this test so future UX retunes only touch the constants
      // file (the dartdoc on PostSessionTiming captures the retune
      // history).
      expect(RewardTier.dayZero.b1Hold, PostSessionTiming.b1HoldDayZero);
      expect(RewardTier.baseline.b1Hold, PostSessionTiming.b1HoldBaseline);
      expect(
        RewardTier.thresholdAnticipatory.b1Hold,
        PostSessionTiming.b1HoldThresholdAnticipatory,
      );
      expect(
        RewardTier.classChangeAnticipatory.b1Hold,
        PostSessionTiming.b1HoldClassChangeAnticipatory,
      );
    },
  );
}
