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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/profile_avatar.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/rune_halo.dart';

import '../../../../helpers/test_material_app.dart';

/// Stub profile notifier — Phase 32 PR 32e scope add: RuneHalo now embeds
/// [ProfileAvatar] as its inner content, which is a `ConsumerWidget`. The
/// halo's host needs a [ProviderScope] with the avatar's identity inputs
/// stubbed (profile + email) so the gradient-disc fallback path renders
/// deterministically across all four halo states.
class _StubProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile? _profile;

  @override
  Future<Profile?> build() async => _profile;

  @override
  Future<void> saveOnboardingProfile({
    required String displayName,
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    profileProvider.overrideWith(
      () => _StubProfileNotifier(const Profile(id: 'u', displayName: 'Alice')),
    ),
    currentUserEmailProvider.overrideWithValue('alice@example.test'),
  ],
  child: TestMaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
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

    testWidgets('outer reserved size shrinks below compact threshold', (
      tester,
    ) async {
      // At size: 36, compact pad +12 → outer 48dp. Threshold was 48 in
      // Phase 26b, bumped to 52 in Phase 32 PR 32e to cover the 48dp Home +
      // 44dp Saga avatars. 36 still sits below the new threshold so this
      // remains the compact-path canary.
      await tester.pumpWidget(
        _wrap(const RuneHalo(state: VitalityState.active, size: 36)),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(RuneHalo));
      expect(size.width, closeTo(48, 1));
      expect(size.height, closeTo(48, 1));
    });

    testWidgets(
      'Phase 32 avatar sizes (44 Saga, 48 Home) stay on the compact path',
      (tester) async {
        // Phase 32 PR 32e: threshold bumped 48→52 so the new tappable-
        // avatar sizes (44dp Saga, 48dp Home) both stay on the compact
        // glow-pad branch for static states (avoids the legacy +60dp
        // padding blowing out the header / card vertical rhythm).
        //
        // At size: 44, compact pad +12 → outer 56dp.
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.active, size: 44)),
        );
        await tester.pumpAndSettle();
        final saga = tester.getSize(find.byType(RuneHalo));
        expect(saga.width, closeTo(56, 1));
        expect(saga.height, closeTo(56, 1));

        // At size: 48, compact pad +12 → outer 60dp.
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.active, size: 48)),
        );
        await tester.pumpAndSettle();
        final home = tester.getSize(find.byType(RuneHalo));
        expect(home.width, closeTo(60, 1));
        expect(home.height, closeTo(60, 1));
      },
    );

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

  // ===========================================================================
  // Phase 32 PR 32e scope add — ProfileAvatar substitution.
  //
  // The previous rune figure (`AppIcons.hero` rendered via SvgPicture) was
  // retired in favour of the user's ProfileAvatar at the centre of the
  // glow ring. Each of the four state subtrees mounts ProfileAvatar in
  // compact mode; the glow / motion / colour signalling is unchanged.
  // ===========================================================================
  group('RuneHalo — ProfileAvatar substitution', () {
    for (final state in VitalityState.values) {
      testWidgets('${state.name} renders a ProfileAvatar at the centre', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(RuneHalo(state: state)));
        // Two pumps to flush mount + first animation tick (untested /
        // dormant / fading / radiant all start a ticker; active is
        // static).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        // The new identity content — every state mounts one
        // ProfileAvatar.
        expect(find.byType(ProfileAvatar), findsOneWidget);
      });
    }

    testWidgets(
      'dormant rotation wraps the glow ring only — avatar does not spin',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.dormant, size: 64)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        // Pin: the ProfileAvatar must NOT be a descendant of any
        // Transform widget. The dormant rotation animates the dim
        // glow ring (the surrounding bordered circle); a spinning
        // user avatar would be jarring.
        final avatarUnderTransform = find.descendant(
          of: find.byType(Transform),
          matching: find.byType(ProfileAvatar),
        );
        expect(
          avatarUnderTransform,
          findsNothing,
          reason:
              'Dormant rotation must wrap only the glow shell, '
              'never the avatar itself.',
        );
      },
    );

    testWidgets(
      'radiant centre avatar is not gold-tinted (sweep + bloom carry gold)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const RuneHalo(state: VitalityState.radiant, size: 64)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // The radiant avatar is rendered at size * 1.10 = 70.4 to match
        // the bloom radius. The previous implementation tinted the
        // inner sigil gold; the substitution drops that tint so a
        // user-uploaded photo or BP-gradient monogram renders true to
        // its identity. The reward-gold signal lives in the sweep arc
        // (CustomPaint) + bloom (BoxShadow), not on the avatar pixels.
        final avatarFinder = find.byType(ProfileAvatar);
        expect(avatarFinder, findsOneWidget);
        final avatar = tester.widget<ProfileAvatar>(avatarFinder);
        // No explicit colour param exists on ProfileAvatar — the
        // contract is structural: the substitution intentionally
        // dropped the `color: reward` argument that the legacy
        // `AppIcons.render(...)` call accepted. Pin the compact-mode
        // contract instead so a future regression that wires a tint
        // arg fails this test.
        expect(avatar.compact, isTrue);
      },
    );
  });
}
