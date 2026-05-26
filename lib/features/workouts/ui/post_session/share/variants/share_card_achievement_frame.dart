import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../share_card_typography.dart';

/// D3 Achievement Frame overlay — the single photo-overlay treatment for
/// the share-card photo path (mockup §6 D3 + Phase 31 locked decisions).
///
/// Replaces Variant A (Minimal Strip) + Variant B (Full-Bleed Collars).
/// Renders two trapezoidal `ClipPath` collars (top + bottom) that narrow
/// toward the photo zone, plus two 4dp side bars running the card's full
/// height — left in the dominant-BP hue, right in `hotViolet`. Body-part
/// identity is encoded in the chrome structure (the side bars), not in
/// flat strip backgrounds.
///
/// **Visual contract (mockup §6 D3):**
///
///   * Top collar — `ClipPath` trapezoid sized at `cardHeightDp × 0.13`
///     (~95dp on a 412dp Android viewport; ~250px in the 1080×1920
///     export canvas). Abyss at 92% opacity. Polygon vertices
///     (top→bottom):
///       - `(0.0, 0.0)` — top-left
///       - `(1.0, 0.0)` — top-right
///       - `(0.85, 1.0)` — bottom-right (15% inward slant)
///       - `(0.15, 1.0)` — bottom-left (15% inward slant)
///     Renders the new class name (e.g. "BULWARK") + saga eyebrow
///     (e.g. "SAGA 76", omitted on class-change sessions per Q4 lock).
///
///   * Bottom collar — mirrored trapezoid sized at `cardHeightDp × 0.22`
///     (~161dp on a 412dp viewport; ~422px in the 1080×1920 export
///     canvas). Polygon vertices:
///       - `(0.15, 0.0)` — top-left (mirror of top-collar bottom-left)
///       - `(0.85, 0.0)` — top-right
///       - `(1.0, 1.0)` — bottom-right
///       - `(0.0, 1.0)` — bottom-left
///     Renders XP hero ("+618 XP") + lift detail ("95kg × 5 · Supino" —
///     `heroGold` color when [hasPr] is true) + BP rank ("Peito · Rank 19")
///     + REPSAGA wordmark.
///
///   * Side bars — 4dp wide × full card height, Positioned. Left bar uses
///     [dominantHue]; right bar uses `AppColors.hotViolet`.
///
///   * Class-change override: if [isClassChange] is true, the saga eyebrow
///     line is dropped (top collar shows new class name only — Q4 lock).
///     The left side bar swaps to `AppColors.heroGold` so both side bars
///     don't collapse to the same color visually drained. (Right stays
///     `hotViolet`; left was `dominantHue` which is already `hotViolet`
///     on class-change per [SharePayload.dominantHue].)
///
/// **Decoupling Rule 2.** All visible strings (`className`, `sagaEyebrow`,
/// `xpHero`, `liftDetail`, `bpRank`, `wordmark`) arrive pre-localized via
/// constructor params. NO `AppLocalizations.of(context)` here.
///
/// **Photo offset.** This widget renders the overlay subtree only — the
/// photo zone is stacked behind it by [ShareCardRenderer]. The renderer's
/// `_PhotoZone` applies the `photoOffset` Transform.translate to the photo
/// alone; collars + side bars stay anchored to the card frame (PR 30b
/// Important 3 contract preserved).
class ShareCardAchievementFrame extends StatelessWidget {
  const ShareCardAchievementFrame({
    super.key,
    required this.dominantHue,
    required this.className,
    required this.xpHero,
    required this.bpRank,
    required this.wordmark,
    this.sagaEyebrow,
    this.liftDetail,
    this.hasPr = false,
    this.isClassChange = false,
    this.renderTarget = ShareCardRenderTarget.export,
    this.cardWidthDp = 1080.0,
    this.cardHeightDp = 1920.0,
  });

  /// Dominant body-part hue — drives the left side bar (unless overridden
  /// by class-change rule below) and the BP rank label color.
  ///
  /// Picked by the caller from the SharePayload's `dominantHue` getter.
  /// On class-change sessions this value will already be `hotViolet` per
  /// [SharePayload.dominantHue]'s override rule — the widget's
  /// [isClassChange] flag then swaps the left bar to `heroGold` to keep
  /// chrome visually distinct from the right `hotViolet` bar.
  final Color dominantHue;

  /// Top-collar class name, e.g. "BULWARK". Caller uppercases.
  /// On class-change sessions this is the NEW class name (Q4 lock —
  /// "DESPERTOU" framing stays in the B3 cinematic cut, not on the card).
  final String className;

  /// Top-collar saga eyebrow, e.g. "SAGA 76". Omitted entirely when the
  /// caller passes `null` (typical on class-change sessions — Q4 lock).
  final String? sagaEyebrow;

  /// Bottom-collar XP hero, e.g. "+618 XP". The primary numeric register
  /// of the share card.
  final String xpHero;

  /// Bottom-collar lift detail, e.g. "95kg × 5 · Supino" — rendered in
  /// `heroGold` when [hasPr] is true (the canonical PR reward).
  ///
  /// `null` on baseline / rank-up-only / class-change sessions where no
  /// hero PR landed; the slot collapses (no line rendered).
  ///
  /// Single-line — truncates with ellipsis at the bottom-collar width
  /// minus the XP-hero baseline-aligned column.
  final String? liftDetail;

  /// Bottom-collar BP rank line, e.g. "Peito · Rank 19" / "Costas · Rank 11".
  /// Rendered in [dominantHue] (matches the left side-bar color on non
  /// class-change sessions).
  final String bpRank;

  /// Wordmark string, always non-null. Constant "REPSAGA" today but kept
  /// as a param so future white-label / event-rebrand surfaces can override.
  final String wordmark;

  /// `true` when the session set a hero PR — drives the bottom-collar
  /// lift-detail line to render in `heroGold` (reward accent annotation
  /// lives at the call site below). `false` otherwise.
  final bool hasPr;

  /// `true` when the session crossed a class boundary. Swaps the left
  /// side bar from [dominantHue] to `AppColors.heroGold` so the chrome
  /// reads as "highlighted" rather than "drained" when both bars would
  /// otherwise collapse to `hotViolet`. The top-collar copy doesn't
  /// change (caller passes the NEW class name as [className] per Q4 lock).
  final bool isClassChange;

  /// Whether this widget is the **export** (1080×1920 offscreen) tree
  /// OR the **preview** (device-native dp visible) tree. Drives the
  /// typography sizing — see [ShareCardTypography] for the per-element
  /// pairs. Defaults to [ShareCardRenderTarget.export] so the golden
  /// contract stays correct.
  final ShareCardRenderTarget renderTarget;

  /// Device-native (or canvas-native, on export) card width in dp / px.
  /// Drives the proportional horizontal padding inside the collars so
  /// the gutter scales with the card on small viewports.
  ///
  /// Defaults to `1080.0` so the export tree's golden contract is
  /// preserved without callers touching the param. The preview tree
  /// (`SharePreviewScreen`) wraps the card in a `LayoutBuilder` and
  /// forwards the laid-out constraints — typically 320 / 360 / 412dp.
  final double cardWidthDp;

  /// Device-native card height in dp / px. Drives proportional collar
  /// heights and inner top/bottom padding. Defaults to `1920.0` so the
  /// export tree's golden contract is preserved.
  ///
  /// **Phase 31 device-fix structural change (Bugs A + C):** pre-fix
  /// the variant computed collar heights from a fixed absolute table
  /// (252 / 390 export, 84 / 130 preview) — but the preview tree was
  /// wrapped in a `FittedBox` that shrank the entire 1080-unit subtree
  /// to fit the device width. The preview values were then themselves
  /// scaled down (~0.38× on a 412dp viewport) and the collars all but
  /// disappeared. Post-fix the preview tree no longer FittedBox-scales,
  /// so the variant computes heights from the actual `cardHeightDp` it
  /// was given:
  ///
  ///   * Top collar    = `cardHeightDp × 0.13`
  ///   * Bottom collar = `cardHeightDp × 0.20`
  ///
  /// At 1920px (export) that's 250 / 384 — matches the prior absolute
  /// 252 / 390 within 2px (golden re-baseline is in-spec). At 720dp
  /// (412dp × 16/9 viewport landed inside an `AspectRatio(9/16)`)
  /// that's 94 / 144 — readable collar bodies on the device.
  final double cardHeightDp;

  @override
  Widget build(BuildContext context) {
    // Proportional collar heights — see [cardHeightDp] for the rationale.
    //   * Top collar: 13% of card height. Holds class name + optional
    //     saga eyebrow (1-2 lines of typography, light vertical content).
    //   * Bottom collar: 22% of card height. Holds XP hero + optional
    //     lift detail + BP rank + wordmark (4 lines, heaviest content).
    final topCollarHeight = cardHeightDp * 0.13;
    final bottomCollarHeight = cardHeightDp * 0.22;
    // Horizontal padding inside the collars — proportional to card width
    // so small viewports keep gutters in scale with content.
    final hPad = cardWidthDp * 0.04;
    // Top-of-collar inner padding — proportional to collar height so
    // the class name + saga eyebrow stack sits well-centered.
    final topInnerPad = topCollarHeight * 0.16;
    // Bottom-collar inner top-padding (above XP hero) — proportional to
    // collar height. Slightly less than topInnerPad because the bottom
    // collar packs more vertical content and the main XP hero needs
    // visual breathing space, not extra padding.
    final bottomInnerTopPad = bottomCollarHeight * 0.12;
    final bottomInnerBottomPad = bottomCollarHeight * 0.08;
    // Inter-text gaps within each collar — proportional to collar
    // height so vertical rhythm scales with the chrome.
    final topGap = topCollarHeight * 0.05;
    final bottomGap = bottomCollarHeight * 0.04;
    // Side-bar width — 4dp absolute regardless of viewport on preview,
    // 12px on export (mockup §6 — 4dp at the 3.0 pixelRatio capture).
    // The bar is a chrome detail, NOT a layout proportion. Keep
    // absolute.
    final sideBarWidth = renderTarget == ShareCardRenderTarget.preview
        ? 4.0
        : 12.0;
    // Class-change left-bar swap — keeps the chrome from collapsing both
    // bars to a single hue (would read as drained, not highlighted).
    // ignore: reward_accent — class-change is the canonical class identity reward; heroGold scarcity contract met (class-change-only render).
    final leftBarColor = isClassChange ? AppColors.heroGold : dominantHue;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Top collar — trapezoidal `ClipPath`, narrows toward photo.
        Align(
          alignment: Alignment.topCenter,
          child: ClipPath(
            clipper: const _TopCollarClipper(),
            child: Container(
              key: const ValueKey('share-card-achievement-frame-top-collar'),
              height: topCollarHeight,
              color: AppColors.abyss.withValues(alpha: 0.92),
              padding: EdgeInsets.fromLTRB(hPad, topInnerPad, hPad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    className,
                    style: ShareCardTypography.achievementFrameClassName(
                      renderTarget,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sagaEyebrow != null) ...[
                    SizedBox(height: topGap),
                    Text(
                      sagaEyebrow!,
                      style: ShareCardTypography.achievementFrameSagaEyebrow(
                        renderTarget,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Bottom collar — mirrored trapezoid, holds XP hero + lift + rank.
        Align(
          alignment: Alignment.bottomCenter,
          child: ClipPath(
            clipper: const _BottomCollarClipper(),
            child: Container(
              key: const ValueKey('share-card-achievement-frame-bottom-collar'),
              height: bottomCollarHeight,
              color: AppColors.abyss.withValues(alpha: 0.92),
              padding: EdgeInsets.fromLTRB(
                hPad,
                bottomInnerTopPad,
                hPad,
                bottomInnerBottomPad,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    xpHero,
                    style: ShareCardTypography.achievementFrameXpHero(
                      renderTarget,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                  if (liftDetail != null) ...[
                    SizedBox(height: bottomGap),
                    // ignore: reward_accent — PR is the canonical reward; heroGold scarcity contract met (only renders when hasPr is true via achievementFrameLiftDetail).
                    Text(
                      liftDetail!,
                      style: ShareCardTypography.achievementFrameLiftDetail(
                        renderTarget,
                        isPr: hasPr,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  SizedBox(height: bottomGap),
                  Text(
                    bpRank,
                    style: ShareCardTypography.achievementFrameBpRank(
                      renderTarget,
                      hue: dominantHue,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                  SizedBox(height: bottomGap),
                  Text(
                    wordmark,
                    style: ShareCardTypography.achievementFrameWordmark(
                      renderTarget,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Left side bar — dominant hue (or heroGold on class-change).
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: sideBarWidth,
          child: ColoredBox(
            key: const ValueKey('share-card-achievement-frame-left-bar'),
            color: leftBarColor,
          ),
        ),
        // Right side bar — always hotViolet (brand anchor).
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: sideBarWidth,
          child: const ColoredBox(
            key: ValueKey('share-card-achievement-frame-right-bar'),
            color: AppColors.hotViolet,
          ),
        ),
      ],
    );
  }
}

/// Top collar shape — trapezoid narrowing toward the photo zone.
///
/// Polygon vertices (in clockwise order from top-left):
///   `(0.0, 0.0) → (1.0, 0.0) → (0.85, 1.0) → (0.15, 1.0)`
///
/// The 15% inward slant on each side at the bottom edge mirrors the
/// cinematic slash grammar (`paintCutSlash`) — the diagonal cut reads as
/// "the photo is cut from the chrome" rather than overlaid on top.
class _TopCollarClipper extends CustomClipper<Path> {
  const _TopCollarClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.85, size.height)
      ..lineTo(size.width * 0.15, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// Bottom collar shape — mirrored trapezoid widening toward the bottom.
///
/// Polygon vertices (in clockwise order from top-left):
///   `(0.15, 0.0) → (0.85, 0.0) → (1.0, 1.0) → (0.0, 1.0)`
///
/// Mirror of the top collar so the two collars frame the photo zone
/// symmetrically — the narrow ends meet the photo at the same 15% inset
/// on each side.
class _BottomCollarClipper extends CustomClipper<Path> {
  const _BottomCollarClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(size.width * 0.15, 0)
      ..lineTo(size.width * 0.85, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
