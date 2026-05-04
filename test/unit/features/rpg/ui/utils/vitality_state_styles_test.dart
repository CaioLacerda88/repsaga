import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';
import 'package:repsaga/l10n/app_localizations.dart';

/// UI-side resolution tests for [VitalityStateStyles] + the
/// [VitalityStateColor] extension on [VitalityState].
///
/// **Why these moved out of the mapper test (BUG-035).** Color resolution
/// + [AppLocalizations] lookup used to live on `VitalityStateMapper` in
/// the domain layer, which forced the mapper's tests to import
/// `package:flutter/painting.dart` (Color) and the gen-l10n
/// `AppLocalizations`. The split moved both concerns to a UI helper —
/// these tests follow them. The mapper's pure boundary tests now live
/// in a sibling file at `test/unit/features/rpg/domain/`.
void main() {
  group('VitalityStateStyles — palette per state', () {
    test('borderColorFor pins to the canonical AppColors tokens', () {
      // Untested + dormant both resolve to textDim by design — the
      // 2026-05-04 untested patch reuses the dim/grey token so the new
      // state cannot widen the heroGold reward surface. The visual
      // differentiation between never-trained and decayed lives in the
      // pct readout (`—` vs `0%`) + marginalia copy, not the border.
      expect(
        VitalityStateStyles.borderColorFor(VitalityState.untested),
        AppColors.textDim,
      );
      expect(
        VitalityStateStyles.borderColorFor(VitalityState.dormant),
        AppColors.textDim,
      );
      expect(
        VitalityStateStyles.borderColorFor(VitalityState.fading),
        AppColors.primaryViolet,
      );
      expect(
        VitalityStateStyles.borderColorFor(VitalityState.active),
        AppColors.hotViolet,
      );
      expect(
        VitalityStateStyles.borderColorFor(VitalityState.radiant),
        AppColors.heroGold,
      );
    });

    test(
      'borderColorFor returns distinct colors except untested == dormant',
      () {
        // Reward-scarcity contract: heroGold is reserved for radiant alone.
        // Untested deliberately reuses the dim/grey token used by dormant —
        // see [borderColorFor] doc comment. The other four states remain
        // pairwise distinct.
        final allColors = VitalityState.values
            .map(VitalityStateStyles.borderColorFor)
            .toSet();
        // Five distinct colors across five "non-untested" states; untested
        // shares with dormant so the deduplicated set has exactly four.
        // Total enum values is 5 (untested, dormant, fading, active, radiant).
        expect(allColors.length, VitalityState.values.length - 1);
        expect(
          VitalityStateStyles.borderColorFor(VitalityState.untested),
          VitalityStateStyles.borderColorFor(VitalityState.dormant),
        );
      },
    );

    test('haloColorFor and progressBarColorFor align with borderColorFor', () {
      // Locked single-source-of-truth contract: halo, border, progress bar
      // all read from the same per-state palette. Splitting them would
      // re-introduce the drift the styles helper exists to prevent.
      for (final s in VitalityState.values) {
        expect(
          VitalityStateStyles.haloColorFor(s),
          VitalityStateStyles.borderColorFor(s),
        );
        expect(
          VitalityStateStyles.progressBarColorFor(s),
          VitalityStateStyles.borderColorFor(s),
        );
      }
    });
  });

  group('VitalityStateStyles.bodyPartColor — locked palette', () {
    test('all 7 body parts (6 v1 + cardio) have a color assignment', () {
      for (final bp in BodyPart.values) {
        expect(
          VitalityStateStyles.bodyPartColor.containsKey(bp),
          true,
          reason: 'body part ${bp.dbValue} missing from bodyPartColor map',
        );
      }
    });

    test('all 6 active (v1) body parts have distinct colors', () {
      // The trend chart in §13.3 puts six body-part lines on the same
      // canvas — they must be visually distinguishable. We don't assert
      // contrast metrics here (UX-critic / design pass), but at minimum
      // no two body parts can share an identical color.
      final v1Colors = activeBodyParts
          .map((bp) => VitalityStateStyles.bodyPartColor[bp])
          .whereType<Color>()
          .toSet();
      expect(v1Colors.length, activeBodyParts.length);
    });

    test('cardio uses a desaturated tone (v2 placeholder)', () {
      // Cardio is intentionally muted until earnable in v2 — same `hair`
      // hairline tone as the dormant cardio row.
      expect(
        VitalityStateStyles.bodyPartColor[BodyPart.cardio],
        AppColors.hair,
      );
    });

    test('heroGold is reserved (not used as a body-part color)', () {
      // Reward-scarcity contract: heroGold is only the radiant rune signal
      // and reward-only token, never a per-body-part identity color.
      for (final color in VitalityStateStyles.bodyPartColor.values) {
        expect(
          color,
          isNot(AppColors.heroGold),
          reason: 'heroGold leaked into bodyPartColor — reward scarcity broken',
        );
      }
    });
  });

  group('VitalityStateColor extension — borderColor', () {
    test('delegates to VitalityStateStyles.borderColorFor for every state', () {
      // Compatibility shim — the property-style read used by rank stamps,
      // halos, vitality-radar vertex dots, and the xp progress hairline
      // must stay in lock-step with the canonical palette resolver.
      for (final s in VitalityState.values) {
        expect(s.borderColor, VitalityStateStyles.borderColorFor(s));
      }
    });
  });

  group('VitalityStateStyles.localizedCopy', () {
    // localizedCopy requires an AppLocalizations instance which is only
    // available inside a widget tree that pumps the localization delegates,
    // so these tests use `testWidgets` (not pure-Dart `test`). We resolve
    // l10n once via a Builder, run the assertions inside it, and return a
    // SizedBox.shrink() — no rendering needed.

    testWidgets('returns distinct strings per state', (tester) async {
      String? collected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) {
              final l10n = AppLocalizations.of(ctx);
              final lines = VitalityState.values
                  .map((s) => VitalityStateStyles.localizedCopy(s, l10n))
                  .toSet();
              expect(
                lines.length,
                VitalityState.values.length,
                reason:
                    'Each VitalityState must map to a unique copy line — '
                    'collisions would silently merge two visual states.',
              );
              collected = lines.join('|');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Sanity: Builder ran (catches the case where the test passes
      // vacuously because the inner expects never executed).
      expect(collected, isNotNull);
    });

    testWidgets('returns the canonical English copy per state', (tester) async {
      // Pin the actual ARB strings so a regression in app_en.arb (e.g.
      // someone editing the copy without re-running gen-l10n) fails here
      // rather than silently shipping the wrong text. Trailing periods
      // come straight from app_en.arb and matter — design wants the
      // marginalia to read as full sentences.
      bool ran = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) {
              final l10n = AppLocalizations.of(ctx);
              expect(
                VitalityStateStyles.localizedCopy(VitalityState.untested, l10n),
                'Uncharted — log a set to begin.',
              );
              expect(
                VitalityStateStyles.localizedCopy(VitalityState.dormant, l10n),
                'Awaits your first stride.',
              );
              expect(
                VitalityStateStyles.localizedCopy(VitalityState.fading, l10n),
                'Conditioning lost — return to the path.',
              );
              expect(
                VitalityStateStyles.localizedCopy(VitalityState.active, l10n),
                'On the path.',
              );
              expect(
                VitalityStateStyles.localizedCopy(VitalityState.radiant, l10n),
                'Path mastered.',
              );
              ran = true;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(ran, isTrue);
    });
  });
}
