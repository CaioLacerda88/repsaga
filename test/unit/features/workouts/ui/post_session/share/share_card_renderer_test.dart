import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_renderer.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_discreet.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_variant_a.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_variant_b.dart';

/// Pins the composer: variant dispatch + photo zone vs discreet flood
/// branching + AspectRatio + semantics identifier.
void main() {
  SharePayload payload({
    BodyPart? dominantBp = BodyPart.chest,
    int? rank = 19,
    double rankProgress = 0.5,
    SharePayloadPr? pr,
    bool isClassChange = false,
    bool hasRankUp = false,
    bool hasTitle = false,
  }) {
    return SharePayload(
      tier: RewardTier.thresholdAnticipatory,
      totalXp: 618,
      dominantBodyPart: dominantBp,
      dominantBodyPartRank: rank,
      rankProgressFraction: rankProgress,
      pr: pr,
      characterClassSlug: 'bulwark',
      isClassChange: isClassChange,
      hasTitleUnlock: hasTitle,
      hasRankUp: hasRankUp,
    );
  }

  const strings = ShareCardStrings(
    wordmark: 'REPSAGA',
    variantAXpText: '+618 XP',
    variantAPrText: '95kg × 5 · PR',
    variantBBpEyebrow: 'Peito',
    variantBClassName: 'BULWARK',
    variantBPrTag: '!! Recorde',
    variantBLift: '95kg × 5',
    variantBBpSub: 'Supino · Peito',
    variantBXpSub: '+618 XP',
    discreetEyebrow: 'Peito · Rank 19',
    discreetHero: '+618',
    discreetHeroSubLabel: 'XP NESTA SAGA',
    discreetPrLine: '!! 95kg × 5',
    discreetPrDetail: 'Supino · novo recorde',
  );

  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 270, child: child)),
      ),
    );
  }

  testWidgets(
    'minimalStrip variant renders Variant A + photo placeholder when no photo',
    (tester) async {
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload(),
            variant: ShareCardVariant.minimalStrip,
            strings: strings,
          ),
        ),
      );

      expect(find.byType(ShareCardVariantA), findsOneWidget);
      expect(find.byType(ShareCardVariantB), findsNothing);
      expect(find.byType(ShareCardDiscreet), findsNothing);
      expect(
        find.byKey(const ValueKey('share-card-renderer-photo-placeholder')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'minimalStrip variant renders the photo widget when a photo is supplied',
    (tester) async {
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload(),
            variant: ShareCardVariant.minimalStrip,
            strings: strings,
            photo: const _SolidImageProvider(Color(0xFF666666)),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('share-card-renderer-photo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('share-card-renderer-photo-placeholder')),
        findsNothing,
      );
    },
  );

  testWidgets('fullBleed variant renders Variant B + photo zone', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.fullBleed,
          strings: strings,
        ),
      ),
    );

    expect(find.byType(ShareCardVariantB), findsOneWidget);
    expect(find.byType(ShareCardVariantA), findsNothing);
    expect(find.byType(ShareCardDiscreet), findsNothing);
  });

  testWidgets(
    'discreet variant renders ShareCardDiscreet only — no photo zone',
    (tester) async {
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload(),
            variant: ShareCardVariant.discreet,
            strings: strings,
            // Photo supplied but should be ignored by discreet.
            photo: const _SolidImageProvider(Color(0xFF666666)),
          ),
        ),
      );

      expect(find.byType(ShareCardDiscreet), findsOneWidget);
      expect(find.byType(ShareCardVariantA), findsNothing);
      expect(find.byType(ShareCardVariantB), findsNothing);
      expect(
        find.byKey(const ValueKey('share-card-renderer-photo')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('share-card-renderer-photo-placeholder')),
        findsNothing,
      );
    },
  );

  testWidgets('forwards dominant hue from payload into Variant A overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(dominantBp: BodyPart.back),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
        ),
      ),
    );

    final variantA = tester.widget<ShareCardVariantA>(
      find.byType(ShareCardVariantA),
    );
    expect(variantA.dominantHue, AppColors.bodyPartBack);
  });

  testWidgets(
    'class-change override forwards hotViolet hue into the discreet variant',
    (tester) async {
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload(dominantBp: BodyPart.chest, isClassChange: true),
            variant: ShareCardVariant.discreet,
            strings: strings,
          ),
        ),
      );

      final discreet = tester.widget<ShareCardDiscreet>(
        find.byType(ShareCardDiscreet),
      );
      // Mockup §6 render rule: class change overrides BP hue with hotViolet.
      expect(discreet.dominantHue, AppColors.hotViolet);
    },
  );

  testWidgets('carries a stable share-card-renderer semantics identifier', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
        ),
      ),
    );

    final semantics = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.identifier == 'share-card-renderer',
    );
    expect(semantics, findsOneWidget);
  });

  testWidgets('enforces 9:16 aspect ratio (AspectRatio = 9/16)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
        ),
      ),
    );

    final aspectRatio = tester.widget<AspectRatio>(
      find.descendant(
        of: find.byType(ShareCardRenderer),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(aspectRatio.aspectRatio, 9 / 16);
  });

  // ---------------------------------------------------------------------------
  // PR 30b Important 3 — photoOffset shifts ONLY the photo subtree.
  //
  // Pre-fix: the preview screen wrapped the entire ShareCardRenderer in a
  // Transform.translate, so the drag gesture shifted both the photo AND
  // the overlay strips together. The overlay then clipped at the
  // 1080x1920 boundary, producing edge artifacts in the exported PNG on
  // max drag.
  //
  // Post-fix: ShareCardRenderer takes a photoOffset param that flows into
  // _PhotoZone only. The overlay (ShareCardVariantA / B) sits in the same
  // Stack as the photo zone but never receives the offset.
  // ---------------------------------------------------------------------------

  testWidgets('photoOffset shifts the photo subtree but not the Variant A '
      'overlay (minimalStrip)', (tester) async {
    const offset = Offset(0, 40);
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
          photo: const _SolidImageProvider(Color(0xFF666666)),
          photoOffset: offset,
        ),
      ),
    );

    // Photo subtree IS translated by the offset.
    final photoFinder = find.byKey(const ValueKey('share-card-renderer-photo'));
    final photoTopLeft = tester.getTopLeft(photoFinder);

    // Overlay subtree is NOT translated.
    final overlayFinder = find.byType(ShareCardVariantA);
    final overlayTopLeft = tester.getTopLeft(overlayFinder);

    // Render the same tree with offset zero so we can diff positions.
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
          photo: const _SolidImageProvider(Color(0xFF666666)),
        ),
      ),
    );

    final photoTopLeftZero = tester.getTopLeft(photoFinder);
    final overlayTopLeftZero = tester.getTopLeft(overlayFinder);

    // Photo Y position MOVED by the offset.dy.
    expect(
      photoTopLeft.dy - photoTopLeftZero.dy,
      closeTo(offset.dy, 0.001),
      reason: 'photoOffset.dy should shift the photo subtree by that amount',
    );

    // Overlay Y position did NOT move.
    expect(
      overlayTopLeft.dy,
      closeTo(overlayTopLeftZero.dy, 0.001),
      reason: 'photoOffset must NOT shift the Variant A overlay subtree',
    );
  });

  testWidgets('photoOffset == Offset.zero does not wrap the photo in '
      'Transform.translate (no-op default)', (tester) async {
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
          photo: const _SolidImageProvider(Color(0xFF666666)),
        ),
      ),
    );

    // No Transform.translate ancestor under the photo when offset is zero.
    final transformAncestors = find.ancestor(
      of: find.byKey(const ValueKey('share-card-renderer-photo')),
      matching: find.byType(Transform),
    );
    expect(
      transformAncestors,
      findsNothing,
      reason: 'Offset.zero default should bypass the Transform.translate',
    );
  });

  testWidgets('photoOffset shifts the placeholder when no photo is supplied', (
    tester,
  ) async {
    const offset = Offset(0, -30);
    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
          photoOffset: offset,
        ),
      ),
    );

    final placeholderFinder = find.byKey(
      const ValueKey('share-card-renderer-photo-placeholder'),
    );
    final overlayFinder = find.byType(ShareCardVariantA);
    final placeholderY = tester.getTopLeft(placeholderFinder).dy;
    final overlayY = tester.getTopLeft(overlayFinder).dy;

    await tester.pumpWidget(
      host(
        ShareCardRenderer(
          payload: payload(),
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
        ),
      ),
    );

    final placeholderYZero = tester.getTopLeft(placeholderFinder).dy;
    final overlayYZero = tester.getTopLeft(overlayFinder).dy;

    expect(placeholderY - placeholderYZero, closeTo(offset.dy, 0.001));
    expect(overlayY, closeTo(overlayYZero, 0.001));
  });
}

/// Minimal in-memory `ImageProvider` for tests — paints a solid color
/// without touching the asset bundle. Avoids the Pass-1 fixture-image
/// dependency (mockup §6 placeholder spec).
class _SolidImageProvider extends ImageProvider<_SolidImageProvider> {
  const _SolidImageProvider(this.color);

  final Color color;

  @override
  Future<_SolidImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _SolidImageProvider key,
    ImageDecoderCallback decode,
  ) {
    // We never actually decode an image — _PhotoZone just needs the Image
    // widget to participate in the tree so the find.byKey matches.
    return OneFrameImageStreamCompleter(_emptyImage());
  }

  Future<ImageInfo> _emptyImage() async {
    // 1×1 placeholder is enough for find.byKey assertions.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) =>
      other is _SolidImageProvider && other.color == color;

  @override
  int get hashCode => color.hashCode;
}
