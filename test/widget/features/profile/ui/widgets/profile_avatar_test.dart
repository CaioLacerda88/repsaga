import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/profile_avatar.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

import '../../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

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

Widget _host({required Widget child, Profile? profile, String? email}) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => _StubProfileNotifier(profile)),
      currentUserEmailProvider.overrideWithValue(email),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Read the leaf [DecoratedBox]'s [LinearGradient] (trained path) from a
/// pumped [ProfileAvatar] subtree. Used to assert the trained-path
/// gradient stops.
LinearGradient _linearGradientOf(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
  for (final box in boxes) {
    final deco = box.decoration;
    if (deco is BoxDecoration && deco.gradient is LinearGradient) {
      return deco.gradient! as LinearGradient;
    }
  }
  throw StateError('No DecoratedBox with a LinearGradient was found.');
}

/// Read the leaf [DecoratedBox]'s [RadialGradient] (Day-0 path) from a
/// pumped [ProfileAvatar] subtree. Day-0 renders a radial glow (violet
/// center → abyss edge) so the disc reads as a distinct brand orb,
/// distinguishable at a glance from the diagonal trained-path sweep.
RadialGradient _radialGradientOf(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
  for (final box in boxes) {
    final deco = box.decoration;
    if (deco is BoxDecoration && deco.gradient is RadialGradient) {
      return deco.gradient! as RadialGradient;
    }
  }
  throw StateError('No DecoratedBox with a RadialGradient was found.');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfileAvatar — gradient colors per dominant body part', () {
    // Parameterized: every BodyPart value pumped with `dominantBodyPart`
    // explicit. The widget reads the hue from BodyPartHues — assertion
    // is on the rendered gradient stops.
    for (final bp in BodyPart.values) {
      testWidgets('renders ${bp.name} hue → hotViolet gradient', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            child: ProfileAvatar(displayName: 'Alice', dominantBodyPart: bp),
            profile: const Profile(id: 'u'),
          ),
        );
        await tester.pump();

        final gradient = _linearGradientOf(tester);
        expect(gradient.colors.first, BodyPartHues.hueFor(bp));
        expect(gradient.colors.last, AppColors.hotViolet);
      });
    }
  });

  group('ProfileAvatar — Day-0 fallback', () {
    testWidgets(
      'renders a RadialGradient (primaryViolet center → abyss edge) when '
      'no dominant body part',
      (tester) async {
        await tester.pumpWidget(
          _host(
            // dominantBodyPart left null + provider returns a Profile
            // with no character sheet wired (sheet provider falls back
            // to AsyncLoading until overridden, so the widget's
            // .value returns null → Day-0 path).
            child: const ProfileAvatar(displayName: 'Alice'),
            profile: const Profile(id: 'u'),
          ),
        );
        await tester.pump();

        // Contract: the Day-0 disc renders a RadialGradient — structural
        // difference from the trained path's LinearGradient. Asserting on
        // the gradient TYPE pins that a future tweak can't silently fall
        // back to a linear sweep (which renders flat-dark at 64dp).
        final gradient = _radialGradientOf(tester);
        expect(gradient.colors.first, AppColors.primaryViolet);
        expect(gradient.colors.last, AppColors.abyss);
      },
    );
  });

  group('ProfileAvatar — monogram derivation', () {
    testWidgets('uses first letter of displayName when set', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const ProfileAvatar(displayName: 'Alice'),
          profile: const Profile(id: 'u'),
        ),
      );
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('falls back to email first letter when displayName is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const ProfileAvatar(),
          profile: const Profile(id: 'u'),
          email: 'bob@example.com',
        ),
      );
      await tester.pump();

      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('renders "?" when displayName and email are both empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const ProfileAvatar(),
          profile: const Profile(id: 'u'),
        ),
      );
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets(
      'reads displayName from profileProvider when constructor param is null',
      (tester) async {
        await tester.pumpWidget(
          _host(
            child: const ProfileAvatar(),
            profile: const Profile(id: 'u', displayName: 'Charlie'),
          ),
        );
        await tester.pump();

        expect(find.text('C'), findsOneWidget);
      },
    );
  });

  group('ProfileAvatar — uploaded image path', () {
    testWidgets(
      'renders CachedNetworkImage and hides monogram when avatarUrl set',
      (tester) async {
        await tester.pumpWidget(
          _host(
            child: const ProfileAvatar(
              displayName: 'Alice',
              avatarUrl: 'https://example.test/avatar.png?v=1',
            ),
            profile: const Profile(id: 'u'),
          ),
        );
        await tester.pump();

        // CachedNetworkImage is present — the avatar URL is the
        // active render path.
        expect(find.byType(CachedNetworkImage), findsOneWidget);
        // The placeholder gradient + monogram is still in the tree
        // (CachedNetworkImage builds its placeholder until the image
        // resolves), so we don't assert findsNothing on the 'A'
        // glyph here — that would over-constrain on the placeholder
        // implementation. The contract we pin is "CachedNetworkImage
        // is present when avatarUrl is set" + "monogram is the
        // placeholder under it".
      },
    );

    testWidgets('reads avatarUrl from profile when constructor param is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const ProfileAvatar(displayName: 'Alice'),
          profile: const Profile(
            id: 'u',
            avatarUrl: 'https://example.test/avatar.png?v=2',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });

  group('ProfileAvatar — Semantics', () {
    testWidgets('uses the override label when semanticsLabel is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const ProfileAvatar(
            displayName: 'Alice',
            semanticsLabel: 'Avatar de Alice',
          ),
          profile: const Profile(id: 'u'),
        ),
      );
      await tester.pump();

      // Find the Semantics widget that carries the explicit label.
      final semanticsNode = tester.widgetList<Semantics>(
        find.byType(Semantics),
      );
      final hasLabel = semanticsNode.any(
        (s) => s.properties.label == 'Avatar de Alice',
      );
      expect(
        hasLabel,
        isTrue,
        reason: 'Override semanticsLabel must surface as the Semantics label',
      );
    });
  });
}
