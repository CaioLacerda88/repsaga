/// Widget tests for [RuneHalo] (Phase 18b).
///
/// The halo collapses Vitality % into one of four §8.4 visual states. These
/// tests verify:
///   1. All four states render without throwing.
///   2. Switching state at runtime tears down the prior animation controller
///      and starts a new one (no leaked tickers).
///   3. The Active state owns no controller (static — pure box-shadow).
///   4. Disposing the widget tears down the controller cleanly.
///
/// We can't trivially read the private [State] to assert controller identity,
/// so the controller-rotation test relies on `pumpAndSettle` returning without
/// timing out — a leaked-on-rebuild ticker would deadlock the test pump.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/rune_halo.dart';

import '../../../../helpers/test_material_app.dart';

Widget _wrap(Widget child) => TestMaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('RuneHalo', () {
    testWidgets('renders without throwing for every VitalityState', (
      tester,
    ) async {
      for (final state in VitalityState.values) {
        await tester.pumpWidget(_wrap(RuneHalo(state: state)));
        // Pump twice — once to mount, once for any first animation tick.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(RuneHalo), findsOneWidget);
      }
    });

    testWidgets(
      'state switch tears down prior controller and rebuilds cleanly',
      (tester) async {
        // Start in Dormant (rotating ticker), transition through every state
        // back to Active (static, no controller) — exercises the
        // didUpdateWidget rotation path on every transition.
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.dormant)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.fading)),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.radiant)),
        );
        await tester.pump(const Duration(milliseconds: 200));

        // Final transition: into the static Active state. If a previous
        // controller leaks, the test framework will report a pending timer
        // when the widget is unmounted in tearDown.
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.active)),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(RuneHalo), findsOneWidget);
      },
    );

    testWidgets('disposes cleanly when removed from the tree', (tester) async {
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.radiant)),
      );
      await tester.pump();

      // Replace with an empty container — this unmounts the halo.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();

      expect(find.byType(RuneHalo), findsNothing);
      // No `expectAsyncEvents` needed — pendingTimers throw via tester teardown
      // if the controller leaked.
    });

    testWidgets('reserves size + 60 dp on each axis (no clipping)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.active, size: 96)),
      );
      await tester.pump();

      // The widget's outer SizedBox should reserve size + 60 = 156.
      final renderBox = tester.renderObject<RenderBox>(find.byType(RuneHalo));
      expect(renderBox.size.width, 156);
      expect(renderBox.size.height, 156);
    });

    // -----------------------------------------------------------------------
    // §8.4 haptic contract — Radiant first paint fires HapticFeedback.lightImpact
    // exactly once per transition into Radiant.
    //
    // We intercept the `flutter/platform` channel and count
    // `HapticFeedback.vibrate` invocations with `HapticFeedbackType.light`,
    // which is what `HapticFeedback.lightImpact()` posts under the hood.
    //
    // Per design spec §8.4: "single haptic on first paint of Radiant state".
    // Implementation contract: `_RadiantHalo` is a StatefulWidget whose
    // initState fires the haptic. The parent `_RuneHaloState` disposes and
    // rebuilds `_RadiantHalo` on every transition INTO Radiant, so the
    // haptic naturally fires once per transition without an explicit
    // `_didFire` boolean to maintain.
    // -----------------------------------------------------------------------
    group('Radiant haptic (§8.4)', () {
      late int hapticLightCount;

      setUp(() {
        hapticLightCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              // HapticFeedback.lightImpact() invokes 'HapticFeedback.vibrate'
              // on flutter/platform with the argument string
              // 'HapticFeedbackType.lightImpact' (see Flutter SDK
              // services/haptic_feedback.dart line 40-45).
              if (call.method == 'HapticFeedback.vibrate' &&
                  call.arguments == 'HapticFeedbackType.lightImpact') {
                hapticLightCount++;
              }
              return null;
            });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      testWidgets('fires lightImpact exactly once on first paint of Radiant', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.radiant)),
        );
        await tester.pump();

        expect(hapticLightCount, 1);
      });

      testWidgets(
        'does not fire when entering non-Radiant states (Active / Fading / Dormant)',
        (tester) async {
          for (final state in [
            // 2026-05-04 untested patch — included so the haptic contract
            // pin covers the new variant explicitly. Untested shares the
            // dormant treatment (no controller for haptic, no glow) so it
            // must remain silent.
            VitalityState.untested,
            VitalityState.dormant,
            VitalityState.fading,
            VitalityState.active,
          ]) {
            await tester.pumpWidget(_wrap(RuneHalo(state: state)));
            await tester.pump();
          }

          expect(hapticLightCount, 0);
        },
      );

      testWidgets(
        'fires once per transition INTO Radiant, not on every rebuild '
        'within Radiant',
        (tester) async {
          // Start in Active (no haptic).
          await tester.pumpWidget(
            _wrap(const RuneHalo(state: VitalityState.active)),
          );
          await tester.pump();
          expect(hapticLightCount, 0);

          // Transition into Radiant — exactly one haptic.
          await tester.pumpWidget(
            _wrap(const RuneHalo(state: VitalityState.radiant)),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(hapticLightCount, 1);

          // Stay in Radiant for several frames — no additional haptics.
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(seconds: 1));
          expect(hapticLightCount, 1);
        },
      );

      testWidgets(
        'fires again when re-entering Radiant after leaving (e.g. Active → '
        'Radiant → Active → Radiant)',
        (tester) async {
          // Active (no haptic).
          await tester.pumpWidget(
            _wrap(const RuneHalo(state: VitalityState.active)),
          );
          await tester.pump();

          // → Radiant (haptic 1).
          await tester.pumpWidget(
            _wrap(const RuneHalo(state: VitalityState.radiant)),
          );
          await tester.pump();
          expect(hapticLightCount, 1);

          // → Active (no haptic).
          await tester.pumpWidget(
            _wrap(const RuneHalo(state: VitalityState.active)),
          );
          await tester.pump();
          expect(hapticLightCount, 1);

          // → Radiant again (haptic 2).
          await tester.pumpWidget(
            _wrap(const RuneHalo(state: VitalityState.radiant)),
          );
          await tester.pump();
          expect(hapticLightCount, 2);
        },
      );
    });
  });

  group('RuneHalo — Saga header sizing + active-glow removal', () {
    testWidgets('active state renders no BoxShadow', (tester) async {
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.active, size: 36)),
      );
      await tester.pumpAndSettle();
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final c in containers) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          expect(
            dec.boxShadow == null || dec.boxShadow!.isEmpty,
            isTrue,
            reason:
                'Active-state RuneHalo must not render any BoxShadow at 36dp.',
          );
        }
      }
    });

    testWidgets('radiant state still renders a sweep (regression guard)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.radiant, size: 36)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The radiant state uses a CustomPaint sweep; just confirm the painter
      // is mounted. Glow boxShadow still present in radiant — that's the
      // reward signal and stays unchanged.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('outer reserved size shrinks below 48dp threshold', (
      tester,
    ) async {
      // At size: 36, compact pad +12 → outer 48dp.
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.active, size: 36)),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(RuneHalo));
      expect(size.width, closeTo(48, 1));
      expect(size.height, closeTo(48, 1));
    });

    testWidgets('radiant state at 36dp keeps legacy padding (no sweep clip)', (
      tester,
    ) async {
      // The Critical-fix regression: radiant must NOT use the compact pad,
      // because _RadiantHalo paints a sweep arc into size + 60. If the
      // outer container shrinks to 48dp, the arc clips.
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.radiant, size: 36)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final size = tester.getSize(find.byType(RuneHalo));
      // Expected: 36 + 60 = 96dp outer. closeTo for sub-pixel safety.
      expect(size.width, closeTo(96, 1));
      expect(size.height, closeTo(96, 1));
    });
  });
}
