import 'package:flutter/material.dart';

import '../../../domain/share_payload.dart';
import 'variants/share_card_discreet.dart';
import 'variants/share_card_variant_a.dart';
import 'variants/share_card_variant_b.dart';

/// Pre-localized text bundle for the share card.
///
/// **Why a value object instead of `AppLocalizations`?** Decoupling Rule 2 —
/// the variants themselves take pre-localized strings. The renderer is a
/// pure composer; it picks the variant subtree but does not know about
/// `AppLocalizations`. The caller (Pass 3 `SharePreviewScreen`) formats
/// each string from the payload + the active locale and constructs this
/// bundle. Same `ShareCardRenderer` instance works in pt-BR / en / future
/// locales without touching the renderer.
///
/// **Why not stuff strings on `SharePayload`?** The payload is the
/// data projection of `PostSessionState` — purely numerical + structural.
/// Mixing display strings into it would couple the domain model to
/// `AppLocalizations` and force every call site to re-build the payload
/// when the locale changes.
class ShareCardStrings {
  const ShareCardStrings({
    required this.wordmark,
    required this.variantAXpText,
    required this.variantAPrText,
    required this.variantBBpEyebrow,
    required this.variantBClassName,
    required this.variantBPrTag,
    required this.variantBLift,
    required this.variantBBpSub,
    required this.variantBXpSub,
    required this.discreetEyebrow,
    required this.discreetHero,
    required this.discreetHeroSubLabel,
    required this.discreetPrLine,
    required this.discreetPrDetail,
  });

  /// "REPSAGA" — same across pt + en. Kept as a param so a future
  /// white-label / event-rebrand override is a 1-line change.
  final String wordmark;

  /// Variant A bottom-strip XP text, e.g. "+618 XP".
  final String variantAXpText;

  /// Variant A bottom-strip PR text, e.g. "95kg × 5 · PR". `null` on
  /// non-PR sessions.
  final String? variantAPrText;

  /// Variant B top-collar BP eyebrow, e.g. "Peito" / "Chest".
  final String variantBBpEyebrow;

  /// Variant B top-collar class name, e.g. "BULWARK".
  final String variantBClassName;

  /// Variant B bottom-collar PR tag, e.g. "!! Recorde" / "!! Record".
  /// `null` on non-PR sessions.
  final String? variantBPrTag;

  /// Variant B bottom-collar lift line, e.g. "95kg × 5".
  final String variantBLift;

  /// Variant B bottom-collar BP-sub line, e.g. "Supino · Peito" /
  /// "Bench · Chest".
  final String variantBBpSub;

  /// Variant B bottom-collar XP-sub line, e.g. "+618 XP".
  final String variantBXpSub;

  /// Discreet variant eyebrow, e.g. "Peito · Rank 19" or
  /// "BULWARK DESPERTOU." on class-change.
  final String discreetEyebrow;

  /// Discreet hero text, e.g. "+618" (XP) or "BULWARK" (class change).
  final String discreetHero;

  /// Discreet sub-label below the hero, e.g. "XP NESTA SAGA" /
  /// "XP THIS SAGA".
  final String discreetHeroSubLabel;

  /// Discreet PR line, e.g. "!! 95kg × 5". `null` on non-PR sessions.
  final String? discreetPrLine;

  /// Discreet PR detail body, e.g. "Supino · novo recorde". `null` on
  /// non-PR sessions.
  final String? discreetPrDetail;
}

/// Composes the share card into a single 9:16 widget tree at runtime.
///
/// **Responsibilities:**
///   1. Decide whether to render the photo underlay (A + B) or the
///      Discreet's own background (no photo).
///   2. Stack the chosen variant overlay on top of the underlay.
///   3. Forward the dominant hue from [payload.dominantHue] into the
///      variant so the body-part identity + class-change override are
///      resolved in one place.
///
/// **Pass 1 scope.** No `RepaintBoundary`, no `RenderRepaintBoundary.toImage`
/// — that's Pass 2's [ShareImageRenderer] service. This widget renders
/// the visible preview only.
///
/// **Variant + photo interplay:**
///   * `ShareCardVariant.minimalStrip` — photo is the underlay, Variant A
///     bottom strip is the overlay. If [photo] is null the photo zone is
///     a placeholder dark abyss surface (Pass 3 may wire a "no photo
///     selected" placeholder image).
///   * `ShareCardVariant.fullBleed` — same as above but with Variant B
///     overlay (top + bottom collars).
///   * `ShareCardVariant.discreet` — no photo, Discreet variant owns the
///     full frame with its hue-flood gradient + slash + content. The
///     [photo] param is ignored (the Discreet path is the "no photo"
///     path).
class ShareCardRenderer extends StatelessWidget {
  const ShareCardRenderer({
    super.key,
    required this.payload,
    required this.variant,
    required this.strings,
    this.photo,
  });

  /// Snapshot of the finished workout, projected for the share card.
  /// Source of truth for hue + flags + numeric data.
  final SharePayload payload;

  /// Which variant to render. The Pass 3 preview screen toggles between
  /// `minimalStrip` ↔ `fullBleed` via the "Mínimo" / "Destaque" segmented
  /// control. `discreet` auto-selects on camera-denied / no-photo paths.
  final ShareCardVariant variant;

  /// Pre-localized text bundle. See [ShareCardStrings].
  final ShareCardStrings strings;

  /// Optional photo underlay for Variant A + Variant B. Ignored when
  /// [variant] is [ShareCardVariant.discreet] (that variant owns its own
  /// background).
  final ImageProvider<Object>? photo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'share-card-renderer',
      child: AspectRatio(aspectRatio: 9 / 16, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (variant) {
      case ShareCardVariant.discreet:
        return ShareCardDiscreet(
          dominantHue: payload.dominantHue,
          eyebrow: strings.discreetEyebrow,
          heroText: strings.discreetHero,
          heroSubLabel: strings.discreetHeroSubLabel,
          prLine: strings.discreetPrLine,
          prDetail: strings.discreetPrDetail,
          wordmark: strings.wordmark,
        );
      case ShareCardVariant.minimalStrip:
        return Stack(
          fit: StackFit.expand,
          children: [
            _PhotoZone(photo: photo),
            ShareCardVariantA(
              dominantHue: payload.dominantHue,
              xpText: strings.variantAXpText,
              prText: strings.variantAPrText,
              wordmark: strings.wordmark,
              barFillFraction: payload.rankProgressFraction,
            ),
          ],
        );
      case ShareCardVariant.fullBleed:
        return Stack(
          fit: StackFit.expand,
          children: [
            _PhotoZone(photo: photo),
            ShareCardVariantB(
              dominantHue: payload.dominantHue,
              bpEyebrow: strings.variantBBpEyebrow,
              className: strings.variantBClassName,
              wordmark: strings.wordmark,
              prTag: strings.variantBPrTag,
              lift: strings.variantBLift,
              bpSub: strings.variantBBpSub,
              xpSub: strings.variantBXpSub,
            ),
          ],
        );
    }
  }
}

/// Photo underlay zone. Renders either the supplied [ImageProvider] cropped
/// to BoxFit.cover, OR a placeholder dark surface when no photo is yet
/// selected.
///
/// **Why a separate widget?** Keeps the placeholder + image branch out of
/// `_buildBody`, and gives the composer test a stable `find.byKey` handle.
class _PhotoZone extends StatelessWidget {
  const _PhotoZone({this.photo});

  final ImageProvider<Object>? photo;

  @override
  Widget build(BuildContext context) {
    if (photo == null) {
      return const ColoredBox(
        key: ValueKey('share-card-renderer-photo-placeholder'),
        // ignore: hardcoded_color — discreet-mode photo-zone backdrop (deep violet flood, locked by mockup §6 Discreet render rules).
        color: Color(0xFF1A1228),
      );
    }
    return Image(
      key: const ValueKey('share-card-renderer-photo'),
      image: photo!,
      fit: BoxFit.cover,
    );
  }
}
