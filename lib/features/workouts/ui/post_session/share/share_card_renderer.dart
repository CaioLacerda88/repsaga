import 'package:flutter/material.dart';

import '../../../domain/share_payload.dart';
import 'share_card_typography.dart';
import 'variants/share_card_achievement_frame.dart';
import 'variants/share_card_discreet.dart';

export 'share_card_typography.dart' show ShareCardRenderTarget;

/// Pre-localized text bundle for the share card.
///
/// **Why a value object instead of `AppLocalizations`?** Decoupling Rule 2 —
/// the variants themselves take pre-localized strings. The renderer is a
/// pure composer; it picks the variant subtree but does not know about
/// `AppLocalizations`. The caller (screen-layer composer in
/// `post_session_screen.dart`) formats each string from the payload + the
/// active locale and constructs this bundle. Same `ShareCardRenderer`
/// instance works in pt-BR / en / future locales without touching the
/// renderer.
///
/// **Why not stuff strings on `SharePayload`?** The payload is the data
/// projection of `PostSessionState` — purely numerical + structural.
/// Mixing display strings into it would couple the domain model to
/// `AppLocalizations` and force every call site to re-build the payload
/// when the locale changes.
class ShareCardStrings {
  const ShareCardStrings({
    required this.wordmark,
    required this.achievementFrameClassName,
    required this.achievementFrameXpHero,
    required this.achievementFrameBpRank,
    required this.discreetEyebrow,
    required this.discreetHero,
    required this.discreetHeroSubLabel,
    this.achievementFrameSagaEyebrow,
    this.achievementFrameLiftDetail,
    this.achievementFrameHasPr = false,
    this.discreetPrLine,
    this.discreetPrDetail,
  });

  /// "REPSAGA" — same across pt + en. Kept as a param so a future
  /// white-label / event-rebrand override is a 1-line change.
  final String wordmark;

  /// Achievement Frame top-collar class name (uppercased), e.g. "BULWARK".
  /// On class-change sessions this is the NEW class name (Q4 lock).
  final String achievementFrameClassName;

  /// Achievement Frame top-collar saga eyebrow, e.g. "SAGA 76". `null`
  /// on class-change sessions per Q4 lock (the top collar reads class
  /// name only when class boundary fires).
  final String? achievementFrameSagaEyebrow;

  /// Achievement Frame bottom-collar XP hero, e.g. "+618 XP". Primary
  /// numeric register of the card.
  final String achievementFrameXpHero;

  /// Achievement Frame bottom-collar lift detail, e.g. "95kg × 5 · Supino".
  /// `null` on baseline / rank-up-only / class-change-only sessions —
  /// the slot collapses entirely. When non-null AND
  /// [achievementFrameHasPr] is `true`, the line renders in `heroGold`
  /// (the canonical PR reward accent).
  final String? achievementFrameLiftDetail;

  /// `true` when the bottom-collar lift detail represents a hero PR —
  /// drives the heroGold reward accent. `false` on non-PR sessions even
  /// when [achievementFrameLiftDetail] is non-null (currently always
  /// null on non-PR; future copy hints could populate this).
  final bool achievementFrameHasPr;

  /// Achievement Frame bottom-collar BP-rank line, e.g. "Peito · Rank 19".
  /// Rendered in the dominant-BP hue to mirror the left side bar.
  final String achievementFrameBpRank;

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
///   1. Decide whether to render the photo underlay (Achievement Frame)
///      or the Discreet's own background (no photo).
///   2. Stack the chosen variant overlay on top of the underlay.
///   3. Forward the dominant hue from [payload.dominantHue] into the
///      variant so the body-part identity + class-change override are
///      resolved in one place.
///
/// **Variant + photo interplay:**
///   * `ShareCardVariant.achievementFrame` — photo is the underlay,
///     [ShareCardAchievementFrame] is the overlay (two trapezoidal
///     `ClipPath` collars + 4dp side bars). If [photo] is null the
///     photo zone is a placeholder dark abyss surface.
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
    this.photoOffset = Offset.zero,
    this.renderTarget = ShareCardRenderTarget.export,
    this.cardWidthDp = 1080.0,
    this.cardHeightDp = 1920.0,
  });

  /// Snapshot of the finished workout, projected for the share card.
  /// Source of truth for hue + flags + numeric data.
  final SharePayload payload;

  /// Which variant to render. `achievementFrame` is the default photo
  /// path; `discreet` auto-selects on camera-denied / no-photo paths.
  final ShareCardVariant variant;

  /// Pre-localized text bundle. See [ShareCardStrings].
  final ShareCardStrings strings;

  /// Optional photo underlay for the Achievement Frame. Ignored when
  /// [variant] is [ShareCardVariant.discreet] (that variant owns its own
  /// background).
  final ImageProvider<Object>? photo;

  /// Translation applied to the photo underlay ONLY (the collars + side
  /// bars always stay aligned to the 1080×1920 frame).
  ///
  /// Driven by the preview screen's drag-to-reframe gesture. Defaults to
  /// [Offset.zero] (no shift). The translate is applied inside [_PhotoZone]
  /// so it cannot leak onto the overlay subtree — wrapping the entire
  /// renderer in `Transform.translate` (the pre-fix shape from PR 30b)
  /// shifted overlay AND photo together and produced clipping artifacts
  /// at the 1080×1920 edge on max drag.
  final Offset photoOffset;

  /// Whether this widget is the **export** (1080×1920 offscreen) tree OR
  /// the **preview** (FittedBox-scaled visible) tree. Forwarded to the
  /// active variant subtree which routes the value to
  /// [ShareCardTypography] for per-element sizing. Defaults to
  /// [ShareCardRenderTarget.export] so the golden contract (which captures
  /// the 1080×1920 export bytes) stays correct without callers touching
  /// the param.
  ///
  /// **The preview screen mounts two `ShareCardRenderer` instances** —
  /// a visible one with `renderTarget: preview` so the user can read the
  /// typography on-screen, and an offscreen one (`Positioned(left: -10000)`)
  /// with `renderTarget: export` that's the source for the
  /// `RepaintBoundary` capture. See PR 30c device bug 1 / bug 3.
  final ShareCardRenderTarget renderTarget;

  /// Card width in dp / px — forwarded to the variant subtree so the
  /// chrome (collars, side bars, paddings) computes proportional to the
  /// laid-out card. Defaults to `1080.0` (matches the export tree
  /// 1080×1920 canvas). The preview screen forwards the
  /// `LayoutBuilder.constraints.maxWidth` from the `AspectRatio(9/16)`
  /// host so the visible card renders at device-native dp (see
  /// `share_card_typography.dart` `ShareCardRenderTarget` dartdoc for
  /// the Phase 31 architecture rationale).
  final double cardWidthDp;

  /// Card height in dp / px — forwarded to the variant subtree.
  /// Defaults to `1920.0` (export 9:16 canvas). Drives collar heights
  /// (top × 0.13, bottom × 0.20) inside the Achievement Frame.
  final double cardHeightDp;

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
          renderTarget: renderTarget,
          cardWidthDp: cardWidthDp,
          cardHeightDp: cardHeightDp,
        );
      case ShareCardVariant.achievementFrame:
        return Stack(
          fit: StackFit.expand,
          children: [
            _PhotoZone(photo: photo, offset: photoOffset),
            ShareCardAchievementFrame(
              dominantHue: payload.dominantHue,
              className: strings.achievementFrameClassName,
              sagaEyebrow: strings.achievementFrameSagaEyebrow,
              xpHero: strings.achievementFrameXpHero,
              liftDetail: strings.achievementFrameLiftDetail,
              hasPr: strings.achievementFrameHasPr,
              bpRank: strings.achievementFrameBpRank,
              wordmark: strings.wordmark,
              isClassChange: payload.isClassChange,
              renderTarget: renderTarget,
              cardWidthDp: cardWidthDp,
              cardHeightDp: cardHeightDp,
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
/// Also owns the drag-to-reframe [Transform.translate] so the offset
/// shifts ONLY the photo, never the overlay (PR 30b Important 3).
class _PhotoZone extends StatelessWidget {
  const _PhotoZone({this.photo, this.offset = Offset.zero});

  final ImageProvider<Object>? photo;

  /// Translation applied to the photo subtree (and only the photo subtree).
  /// Zero by default — drag-to-reframe is a preview-only affordance.
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (photo == null) {
      child = const ColoredBox(
        key: ValueKey('share-card-renderer-photo-placeholder'),
        // ignore: hardcoded_color — discreet-mode photo-zone backdrop (deep violet flood, locked by mockup §6 Discreet render rules).
        color: Color(0xFF1A1228),
      );
    } else {
      child = Image(
        key: const ValueKey('share-card-renderer-photo'),
        image: photo!,
        fit: BoxFit.cover,
      );
    }
    if (offset == Offset.zero) return child;
    return Transform.translate(offset: offset, child: child);
  }
}
