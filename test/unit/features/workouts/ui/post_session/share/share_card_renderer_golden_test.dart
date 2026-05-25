import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_renderer.dart';

import '../../../../../../helpers/tolerant_golden_comparator.dart';

/// Pixel-faithful goldens for the three share-card variants at the
/// shipping 1080×1920 9:16 resolution.
///
/// **Why 1080×1920 exactly?** That's the render target Pass 2's
/// `ShareImageRenderer.toImage(pixelRatio: 3.0)` produces for the export
/// path. The visible preview at 360×640 dp + DPR 3 produces the same
/// pixel grid, so the visual contract here matches what users actually
/// share on WhatsApp/IG.
///
/// **Why text-tolerant comparator?** Skia's text shaping diverges by
/// ~0.5-2% across host platforms even with identical TTFs (Windows
/// DirectWrite-influenced vs Linux freetype). The shared
/// `TolerantGoldenFileComparator` gives a 3% headroom — well above the
/// noise floor, well below any meaningful regression.
///
/// **Pass 1 fixture choice.** The photo zone is a synthetic neutral gray
/// `ColorImageProvider` — no external fixture image dependency. The
/// goldens lock the overlay grammar (strip, collars, slash, content
/// layout) against a fixed background tone; Pass 3 swaps in real photos
/// only at the preview level and they're rendered through the same
/// `ShareCardRenderer` so the overlay never re-references the underlay.
void main() {
  late GoldenFileComparator previousComparator;

  setUpAll(() {
    previousComparator = goldenFileComparator;
    final basedir = (goldenFileComparator as LocalFileComparator).basedir;
    goldenFileComparator = TolerantGoldenFileComparator(
      basedir.resolve('share_card_renderer_golden_test.dart'),
    );
  });

  tearDownAll(() {
    goldenFileComparator = previousComparator;
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget host(Widget child) {
    // The renderer enforces 9:16 via AspectRatio. Inside an unconstrained
    // host (Center), Flutter falls back to the children's intrinsic size
    // which collapses the layout. We wrap in a SizedBox at the exact 9:16
    // pixel ratio of the 1080×1920 target so AspectRatio's contract is
    // satisfied tightly and the variant overlays render at their intended
    // physical-pixel positions.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0D0319),
        body: Center(child: SizedBox(width: 1080, height: 1920, child: child)),
      ),
    );
  }

  Future<void> sizeFor(WidgetTester tester) async {
    // 1080×1920 native pixel target with DPR 1 — gives us 1080dp×1920dp
    // for the widget tree so the golden capture matches the export
    // resolution byte-for-byte without scaling.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  // ---------------------------------------------------------------------------
  // Variant A baseline — no PR, baseline tier, chest dominant
  // ---------------------------------------------------------------------------
  testWidgets('share_card_variant_a_baseline.png', (tester) async {
    await sizeFor(tester);
    const payload = SharePayload(
      tier: RewardTier.baseline,
      totalXp: 320,
      dominantBodyPart: BodyPart.chest,
      dominantBodyPartRank: 12,
      pr: null,
      characterClassSlug: 'bulwark',
      isClassChange: false,
      hasTitleUnlock: false,
      hasRankUp: false,
    );
    const strings = ShareCardStrings(
      wordmark: 'REPSAGA',
      variantAXpText: '+320 XP',
      variantAPrText: null,
      variantBBpEyebrow: 'Peito',
      variantBClassName: 'BULWARK',
      variantBPrTag: null,
      variantBLift: '',
      variantBBpSub: '',
      variantBXpSub: '+320 XP',
      discreetEyebrow: 'Peito · Rank 12',
      discreetHero: '+320',
      discreetHeroSubLabel: 'XP NESTA SAGA',
      discreetPrLine: null,
      discreetPrDetail: null,
    );

    await tester.pumpWidget(
      host(
        const ShareCardRenderer(
          payload: payload,
          variant: ShareCardVariant.minimalStrip,
          strings: strings,
          photo: _ColorImageProvider(Color(0xFF666666)),
        ),
      ),
    );
    // Let the image stream resolve.
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ShareCardRenderer),
      matchesGoldenFile('goldens/share_card_variant_a_baseline.png'),
    );
  });

  // ---------------------------------------------------------------------------
  // Variant B PR — gold-tier PR, back dominant
  // ---------------------------------------------------------------------------
  testWidgets('share_card_variant_b_pr.png', (tester) async {
    await sizeFor(tester);
    const payload = SharePayload(
      tier: RewardTier.thresholdAnticipatory,
      totalXp: 618,
      dominantBodyPart: BodyPart.back,
      dominantBodyPartRank: 19,
      pr: SharePayloadPr(exerciseName: 'Deadlift', weightKg: 160, reps: 3),
      characterClassSlug: 'berserker',
      isClassChange: false,
      hasTitleUnlock: false,
      hasRankUp: false,
    );
    const strings = ShareCardStrings(
      wordmark: 'REPSAGA',
      variantAXpText: '+618 XP',
      variantAPrText: '160kg × 3 · PR',
      variantBBpEyebrow: 'Costas',
      variantBClassName: 'BERSERKER',
      variantBPrTag: '!! Recorde',
      variantBLift: '160kg × 3',
      variantBBpSub: 'Levantamento · Costas',
      variantBXpSub: '+618 XP',
      discreetEyebrow: 'Costas · Rank 19',
      discreetHero: '+618',
      discreetHeroSubLabel: 'XP NESTA SAGA',
      discreetPrLine: '!! 160kg × 3',
      discreetPrDetail: 'Levantamento · novo recorde',
    );

    await tester.pumpWidget(
      host(
        const ShareCardRenderer(
          payload: payload,
          variant: ShareCardVariant.fullBleed,
          strings: strings,
          photo: _ColorImageProvider(Color(0xFF666666)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ShareCardRenderer),
      matchesGoldenFile('goldens/share_card_variant_b_pr.png'),
    );
  });

  // ---------------------------------------------------------------------------
  // Discreet class-change — hotViolet override + "BULWARK DESPERTOU."
  // ---------------------------------------------------------------------------
  testWidgets('share_card_discreet_class_change.png', (tester) async {
    await sizeFor(tester);
    const payload = SharePayload(
      tier: RewardTier.classChangeAnticipatory,
      totalXp: 420,
      dominantBodyPart: BodyPart.chest,
      dominantBodyPartRank: 18,
      pr: null,
      characterClassSlug: 'bulwark',
      isClassChange: true,
      hasTitleUnlock: false,
      hasRankUp: false,
    );
    const strings = ShareCardStrings(
      wordmark: 'REPSAGA',
      variantAXpText: '+420 XP',
      variantAPrText: null,
      variantBBpEyebrow: 'Peito',
      variantBClassName: 'BULWARK',
      variantBPrTag: null,
      variantBLift: '',
      variantBBpSub: '',
      variantBXpSub: '+420 XP',
      discreetEyebrow: 'BULWARK DESPERTOU.',
      discreetHero: '+420',
      discreetHeroSubLabel: 'XP NESTA SAGA',
      discreetPrLine: null,
      discreetPrDetail: null,
    );

    await tester.pumpWidget(
      host(
        const ShareCardRenderer(
          payload: payload,
          variant: ShareCardVariant.discreet,
          strings: strings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ShareCardRenderer),
      matchesGoldenFile('goldens/share_card_discreet_class_change.png'),
    );
  });
}

/// Solid-color ImageProvider for the photo-zone fixture — synthesizes a
/// 4×4 image of the supplied color. BoxFit.cover handles the scale-up to
/// the 1080×1920 render target. Keeps the goldens fixture-image-free
/// (Pass 1 simplicity).
class _ColorImageProvider extends ImageProvider<_ColorImageProvider> {
  const _ColorImageProvider(this.color);

  final Color color;

  @override
  Future<_ColorImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) async {
    return this;
  }

  @override
  ImageStreamCompleter loadImage(
    _ColorImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_paint());
  }

  Future<ImageInfo> _paint() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) =>
      other is _ColorImageProvider && other.color == color;

  @override
  int get hashCode => color.hashCode;
}
