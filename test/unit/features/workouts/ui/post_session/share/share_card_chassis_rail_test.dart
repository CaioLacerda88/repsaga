import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_chassis.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_typography.dart';

/// Pins that the 7-hue identity rail (spec §7) actually PAINTS — every hue
/// segment must have a real, non-zero RENDERED size, not merely the tree
/// presence + `Expanded.flex` weight the existing chassis tests assert.
///
/// Cluster: `visual-only-bugs-escape-value-tests` — the prior rail tests
/// checked `Expanded.flex` + `find.byKey`, never `tester.getSize`. The Row
/// hosting the segments defaulted to `CrossAxisAlignment.center`, so each
/// `ColoredBox` segment (no intrinsic height) shrink-wrapped to **height 0**
/// under the loose vertical constraint. The rail SizedBox stayed 360×3, but
/// the colored bands were 360×0 — invisible. The Phase 39 visual gate caught
/// it at 360dp (bottom 6 device-px rendered as bare scrim, no hues).
void main() {
  /// The §7 chassis sits in a bounded card. We assert the rail at the same
  /// preview render target the visible preview tree uses.
  Widget host(Widget child, {double width = 360}) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.abyss,
        body: Center(
          child: SizedBox(width: width, height: width * 16 / 9, child: child),
        ),
      ),
    );
  }

  testWidgets(
    'every identity-rail hue segment paints at the rail height (not 0-tall)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardChassis(
            wordmark: 'REPSAGA',
            renderTarget: ShareCardRenderTarget.preview,
            child: SizedBox.shrink(),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // The rail container spans the full card width and the preview height.
      final railSize = tester.getSize(
        find.byKey(const ValueKey('share-card-chassis-rail')),
      );
      expect(railSize.width, closeTo(360, 0.5));
      expect(railSize.height, closeTo(3, 0.01));

      // EVERY hue segment must fill the rail height — this is the actual
      // bug: pre-fix each ColoredBox segment was 0-tall (center cross-align
      // + no intrinsic height) so no color ever painted.
      var totalSegWidth = 0.0;
      for (final part in BodyPartHues.bodyPartColor.keys) {
        final seg = find.byKey(
          ValueKey('share-card-chassis-rail-${part.dbValue}'),
        );
        final segSize = tester.getSize(seg);
        expect(
          segSize.height,
          closeTo(3, 0.01),
          reason:
              'segment ${part.dbValue} must paint at the full rail height, '
              'not collapse to 0',
        );
        expect(segSize.width, greaterThan(0));
        totalSegWidth += segSize.width;
      }

      // The seven segments tile the full rail width (no gaps).
      expect(totalSegWidth, closeTo(360, 1.0));
    },
  );

  testWidgets('rail segments paint at the export height (9) too', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardChassis(wordmark: 'REPSAGA', child: SizedBox.shrink()),
        width: 1080,
      ),
    );

    expect(tester.takeException(), isNull);

    final firstPart = BodyPartHues.bodyPartColor.keys.first;
    final segSize = tester.getSize(
      find.byKey(ValueKey('share-card-chassis-rail-${firstPart.dbValue}')),
    );
    // Export rail height is 9 logical px.
    expect(segSize.height, closeTo(9, 0.01));
    expect(segSize.width, greaterThan(0));
  });
}
