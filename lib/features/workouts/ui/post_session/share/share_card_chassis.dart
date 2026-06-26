import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/domain/body_part_hues.dart';
import '../../../../rpg/models/body_part.dart';
import 'share_card_typography.dart';

/// The shared full-bleed overlay chassis both Phase 39 share modes render
/// their content block into (spec §7).
///
/// **Structure (bottom → top in paint order):**
///   1. Photo-hero — the user photo, full-bleed `BoxFit.cover`, OR a dark
///      placeholder surface on the no-photo (discreet) path. The renderer
///      stacks the photo behind this chassis for the photo path; the chassis
///      itself owns the placeholder so a no-photo Bestiary / Clean Flex card
///      still reads as RepSaga.
///   2. Legibility scrim — a bottom-anchored vertical gradient so the bottom
///      content block stays readable over any photo.
///   3. Content block — the mode-specific bottom-anchored subtree ([child]),
///      bottom-left-aligned per the §7 layout.
///   4. 7-hue identity rail — a thin full-width bar along the very bottom
///      edge; one segment per body part in [BodyPartHues] order. [railFlex]
///      lets a mode widen the trained parts' segments (chimera multi-hue
///      emphasis, spec §5).
///   5. Wordmark — bottom-right, small tracked Rajdhani.
///
/// **Boss drama (spec §4 / mockup col 3).** When [isBoss] is true the chassis
/// adds three gold signals so a PR / rank-up session never reads as a Tuesday:
/// an inset gold **frame** (`inset 10`, 1px `heroGold` border), a **crown**
/// glyph (`♛`) floating over the photo, and a top-left **"⚜ CHEFE / BOSS"
/// badge** ([bossBadgeLabel], pre-localized). All three are kind-gated — they
/// only paint for a boss/legendary — so a standard card stays clean.
///
/// **Decoupling Rule 2.** [wordmark] arrives pre-localized; the chassis
/// never calls `AppLocalizations.of(context)`. The photo is supplied as an
/// already-resolved [ImageProvider] (or null) by the renderer.
///
/// **Decoupling Rule 1 (no IO).** Pure presentation — no provider reads, no
/// async. Unit-testable by pumping with a fixed child + flex map.
class ShareCardChassis extends StatelessWidget {
  const ShareCardChassis({
    super.key,
    required this.wordmark,
    required this.child,
    this.photo,
    this.railFlex = const {},
    this.scrimHeightFraction = 0.54,
    this.renderTarget = ShareCardRenderTarget.export,
    this.isBoss = false,
    this.bossBadgeLabel,
  }) : assert(
         !isBoss || bossBadgeLabel != null,
         'a boss chassis needs a localized bossBadgeLabel',
       );

  /// Pre-localized wordmark, e.g. "REPSAGA".
  final String wordmark;

  /// Mode-specific bottom content block (Bestiary block or Clean Flex strip).
  final Widget child;

  /// Optional photo underlay. `null` renders the dark placeholder surface
  /// (no-photo / discreet path).
  final ImageProvider<Object>? photo;

  /// Per-body-part rail segment flex weights. A part absent from the map
  /// gets the default weight of 1. A mode emphasises trained parts by
  /// passing a weight > 1 (e.g. dominant part 2.2, chimera parts 1.4) —
  /// spec §2/§5 "the dominant hue widens on the rail".
  final Map<BodyPart, double> railFlex;

  /// Scrim height as a fraction of card height. Bestiary uses the default
  /// 0.54; Clean Flex passes a shorter scrim so the photo breathes (mockup
  /// "the photo breathes").
  final double scrimHeightFraction;

  /// Export vs preview — forwarded to the wordmark typography.
  final ShareCardRenderTarget renderTarget;

  /// When true, paint the boss drama (inset gold frame + crown glyph +
  /// "⚜ CHEFE" badge). Kind-gated by the caller (Bestiary variant) so the
  /// gold only appears for a boss / legendary encounter (spec §4).
  final bool isBoss;

  /// Pre-localized boss badge copy, e.g. "⚜ Chefe derrotado" / "⚜ Boss
  /// felled". Required (non-null) whenever [isBoss] is true.
  final String? bossBadgeLabel;

  /// Inset for the boss gold frame (mockup `inset:10px` at 300dp ≈ 3.3% of
  /// the card width — scaled to the render target).
  double get _frameInset =>
      renderTarget == ShareCardRenderTarget.preview ? 10.0 : 36.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Photo-hero or placeholder.
        if (photo == null)
          const ColoredBox(
            key: ValueKey('share-card-chassis-photo-placeholder'),
            // ignore: hardcoded_color — no-photo chassis backdrop (deep violet flood, matches the discreet photo-zone surface locked by mockup §6).
            color: Color(0xFF1A1228),
          )
        else
          Image(
            key: const ValueKey('share-card-chassis-photo'),
            image: photo!,
            fit: BoxFit.cover,
          ),

        // 2. Legibility scrim — bottom-anchored gradient.
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: scrimHeightFraction,
            widthFactor: 1,
            child: const DecoratedBox(
              key: ValueKey('share-card-chassis-scrim'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    // ignore: hardcoded_color — scrim is a transparent→abyss legibility gradient (spec §7), authored as alpha stops over the photo.
                    Color(0x00070310),
                    // ignore: hardcoded_color — scrim mid stop.
                    Color(0x80070310),
                    // ignore: hardcoded_color — scrim base (near-opaque abyss).
                    Color(0xF2070310),
                  ],
                  stops: [0.0, 0.42, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Boss drama (spec §4) — painted above the scrim, below the content
        // block / rail / wordmark. Kind-gated: a standard card skips all of it.
        if (isBoss) ...[
          // Inset gold frame (mockup `inset:10px; 1px heroGold border`).
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(_frameInset),
              child: DecoratedBox(
                key: const ValueKey('share-card-chassis-boss-frame'),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  border: Border.all(
                    // ignore: reward_accent — boss frame is the canonical rare-encounter reward; heroGold scarcity contract met (isBoss-gated).
                    color: AppColors.heroGold.withValues(alpha: 0.28),
                    width: renderTarget == ShareCardRenderTarget.preview
                        ? 1.0
                        : 3.0,
                  ),
                ),
              ),
            ),
          ),
          // Crown glyph floating over the photo (mockup `.crown` at top 44%).
          Align(
            alignment: const Alignment(0, -0.12),
            child: Text(
              '♛',
              key: const ValueKey('share-card-chassis-boss-crown'),
              style: ShareCardTypography.bossCrown(renderTarget),
            ),
          ),
          // "⚜ CHEFE" badge, top-left (mockup `.badge`).
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: _badgePadding(),
              child: _BossBadge(
                label: bossBadgeLabel!,
                renderTarget: renderTarget,
              ),
            ),
          ),
        ],

        // 3. Mode content block — bottom-anchored, left-aligned (spec §7).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(padding: _contentPadding(), child: child),
        ),

        // 4. 7-hue identity rail along the bottom edge.
        Align(
          alignment: Alignment.bottomCenter,
          child: _IdentityRail(
            railFlex: railFlex,
            height: renderTarget == ShareCardRenderTarget.preview ? 3.0 : 9.0,
          ),
        ),

        // 5. Wordmark — bottom-right.
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: _wordmarkPadding(),
            child: Text(
              wordmark,
              key: const ValueKey('share-card-chassis-wordmark'),
              style: ShareCardTypography.chassisWordmark(renderTarget),
            ),
          ),
        ),
      ],
    );
  }

  EdgeInsets _contentPadding() {
    // Bottom padding clears the rail + wordmark; horizontal gutter matches
    // the §7 mockup's 22px-at-300dp ≈ 7% of card width.
    final scale = renderTarget == ShareCardRenderTarget.preview ? 1.0 : 3.6;
    return EdgeInsets.fromLTRB(22.0 * scale, 0, 22.0 * scale, 28.0 * scale);
  }

  EdgeInsets _wordmarkPadding() {
    final scale = renderTarget == ShareCardRenderTarget.preview ? 1.0 : 3.6;
    return EdgeInsets.only(right: 14.0 * scale, bottom: 8.0 * scale);
  }

  EdgeInsets _badgePadding() {
    // Mockup badge sits at top:16px left:16px (300dp) — clear of the inset
    // frame so the two gold marks don't collide.
    final scale = renderTarget == ShareCardRenderTarget.preview ? 1.0 : 3.6;
    return EdgeInsets.only(left: 16.0 * scale, top: 16.0 * scale);
  }
}

/// The top-left "⚜ CHEFE / BOSS" badge — a gold-tinted pill over the photo
/// (spec §4 / mockup `.badge`). Pre-localized [label] arrives from the
/// renderer (Decoupling Rule 2).
class _BossBadge extends StatelessWidget {
  const _BossBadge({required this.label, required this.renderTarget});

  final String label;
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    final scale = renderTarget == ShareCardRenderTarget.preview ? 1.0 : 3.6;
    return DecoratedBox(
      key: const ValueKey('share-card-chassis-boss-badge'),
      decoration: BoxDecoration(
        // ignore: reward_accent — boss badge is the canonical rare-encounter reward; heroGold scarcity contract met (isBoss-gated).
        color: AppColors.heroGold.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 9.0 * scale,
          vertical: 4.0 * scale,
        ),
        child: Text(label, style: ShareCardTypography.bossBadge(renderTarget)),
      ),
    );
  }
}

/// The thin 7-hue identity rail — one flex segment per body part in
/// [BodyPartHues.bodyPartColor] iteration order. The rail is the shared
/// "this is RepSaga" signature across both modes (spec §7).
class _IdentityRail extends StatelessWidget {
  const _IdentityRail({required this.railFlex, required this.height});

  final Map<BodyPart, double> railFlex;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('share-card-chassis-rail'),
      height: height,
      child: Row(
        // CrossAxisAlignment.stretch gives each segment a TIGHT vertical
        // constraint = the rail height. Without it the Row defaults to
        // `center`, and a childless ColoredBox (no intrinsic height) under
        // a loose vertical constraint shrink-wraps to height 0 — the rail
        // box stays `width × height` but the hue bands paint at `width × 0`
        // and the rail reads as bare scrim (cluster:
        // visual-only-bugs-escape-value-tests — caught by the Phase 39
        // visual gate, not the flex-weight unit tests).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in BodyPartHues.bodyPartColor.entries)
            Expanded(
              flex: ((railFlex[entry.key] ?? 1.0) * 10).round(),
              child: ColoredBox(
                key: ValueKey('share-card-chassis-rail-${entry.key.dbValue}'),
                color: entry.value,
              ),
            ),
        ],
      ),
    );
  }
}
