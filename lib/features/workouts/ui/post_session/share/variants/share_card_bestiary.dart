import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../../../../../rpg/models/body_part.dart';
import '../../../../domain/beast_card.dart';
import '../share_card_chassis.dart';
import '../share_card_typography.dart';

/// Bestiary-mode share overlay (Phase 39 spec §7) — the generated creature
/// you felled, rendered as the §7 bottom block inside the shared
/// [ShareCardChassis].
///
/// **§7 bottom block:**
/// ```
/// ⚔ HOJE VOCÊ ABATEU            ← eyebrow (tracked, hue; gold "⚜ CHEFE" for bosses)
/// O Golem de Ferro              ← beast name (display hero, line hue)
/// ◈ RANK C · +618 XP · 8,4 t    ← rank sigil + XP + tonnage (Rajdhani numerals)
/// A muralha avança.             ← achievement phrase (italic, dim)
/// ```
///
/// **Boss treatment** ([BeastKind.boss] / [BeastKind.legendary]): the eyebrow
/// + sigil render in `heroGold` and the name stays cream (the gold lives in
/// the accent, not the name) — the laurel sigil "⚜" comes from the resolver.
///
/// **Chimera treatment** ([BeastKind.chimera]): the multi-hue rail is
/// emphasised by widening every trained part's rail segment (the chassis
/// [ShareCardChassis.railFlex] map is built from [BeastCard.hues] here).
///
/// **Decoupling Rule 2.** The beast name + achievement phrase arrive
/// already-localized on [card] (the resolver took a locale). The eyebrow +
/// stat line are pre-formatted localized strings passed in by the screen
/// layer ([eyebrow], [rankLabel], [xpLabel], [tonnageLabel]) — this widget
/// never reads `AppLocalizations.of(context)`.
class ShareCardBestiary extends StatelessWidget {
  const ShareCardBestiary({
    super.key,
    required this.card,
    required this.eyebrow,
    required this.rankLabel,
    required this.xpLabel,
    required this.tonnageLabel,
    required this.wordmark,
    this.bossBadgeLabel,
    this.photo,
    this.renderTarget = ShareCardRenderTarget.export,
  });

  /// The resolved beast (name, phrase, tier, kind, hues, sigil).
  final BeastCard card;

  /// Pre-localized eyebrow, e.g. "⚔ Hoje você abateu" / "⚜ Chefe derrotado".
  final String eyebrow;

  /// Pre-localized rank token, e.g. "RANK C".
  final String rankLabel;

  /// Pre-localized XP fragment, e.g. "+618 XP" (rendered in heroGold).
  final String xpLabel;

  /// Pre-localized tonnage fragment, e.g. "8,4 t".
  final String tonnageLabel;

  /// Pre-localized wordmark, e.g. "REPSAGA".
  final String wordmark;

  /// Pre-localized boss badge copy, e.g. "⚜ Chefe derrotado". Forwarded to
  /// the chassis when [card] is a boss / legendary; `null` on standard cards.
  final String? bossBadgeLabel;

  /// Optional photo underlay (null on the discreet path).
  final ImageProvider<Object>? photo;

  /// Export vs preview target — forwarded to typography + the chassis.
  final ShareCardRenderTarget renderTarget;

  bool get _isBoss =>
      card.kind == BeastKind.boss || card.kind == BeastKind.legendary;

  bool get _isChimera => card.kind == BeastKind.chimera;

  @override
  Widget build(BuildContext context) {
    final lineHue = card.hues.isNotEmpty
        ? card.hues.first
        : AppColors.hotViolet;
    // ignore: reward_accent — boss/legendary is the canonical rare-encounter reward; heroGold scarcity contract met (kind-gated accent).
    final accentHue = _isBoss ? AppColors.heroGold : lineHue;
    final nameHue = _isBoss ? AppColors.textCream : lineHue;

    return ShareCardChassis(
      wordmark: wordmark,
      photo: photo,
      railFlex: _railFlex(),
      renderTarget: renderTarget,
      isBoss: _isBoss,
      bossBadgeLabel: bossBadgeLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            key: const ValueKey('share-card-bestiary-eyebrow'),
            style: ShareCardTypography.bestiaryEyebrow(
              renderTarget,
              color: accentHue,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: _gap(7)),
          _BeastName(
            name: card.name,
            style: ShareCardTypography.bestiaryName(
              renderTarget,
              color: nameHue,
            ),
            // A chimera paints the name as a gradient across the trained
            // parts' hues (spec §5 / mockup col 4). A single hue would read
            // like a focused beast — the gradient IS the "many at once" cue.
            gradientHues: _isChimera && card.hues.length >= 2
                ? card.hues
                : null,
          ),
          SizedBox(height: _gap(9)),
          _StatLine(
            tierLabel: card.tier.label,
            rankLabel: rankLabel,
            xpLabel: xpLabel,
            tonnageLabel: tonnageLabel,
            accentHue: accentHue,
            renderTarget: renderTarget,
          ),
          SizedBox(height: _gap(11)),
          Text(
            card.achievementPhrase,
            key: const ValueKey('share-card-bestiary-phrase'),
            style: ShareCardTypography.bestiaryPhrase(
              renderTarget,
              // ignore: reward_accent — boss phrase echoes the gold accent (kind-gated, scarcity contract met); non-boss uses dim.
              color: _isBoss ? AppColors.heroGold : AppColors.textDimAA,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  double _gap(double base) =>
      base * (renderTarget == ShareCardRenderTarget.preview ? 1.0 : 3.6);

  /// Widen the trained parts' rail segments (the chassis keys flex by
  /// [BodyPart]). For a chimera EVERY trained part widens (spec §5
  /// "emphasised multi-hue rail") — driven by [BeastCard.trainedParts], which
  /// the resolver populates with all significantly-trained parts (B2 root-
  /// cause fix: previously only [card.line] widened because the card carried
  /// hues but not the parts). For a focused beast only the dominant line
  /// widens (spec §2 "the dominant hue widens on the rail").
  Map<BodyPart, double> _railFlex() {
    if (_isChimera) {
      return {for (final part in card.trainedParts) part: 1.4};
    }
    return {card.line: 2.2};
  }
}

/// The beast name — a single-hue [Text] for focused/boss beasts, or a
/// multi-hue gradient via [ShaderMask] for a chimera (spec §5 / mockup col 4).
///
/// **Why a ShaderMask, not a gradient TextStyle?** Flutter has no gradient
/// fill on `TextStyle`; the sanctioned pattern is a `ShaderMask` with
/// [BlendMode.srcIn] over a normally-styled (white-ink) Text so the shader
/// paints only the glyph coverage.
class _BeastName extends StatelessWidget {
  const _BeastName({
    required this.name,
    required this.style,
    this.gradientHues,
  });

  final String name;
  final TextStyle style;

  /// Trained-part hues for the chimera gradient (dominant first). `null`
  /// renders the name in the [style]'s solid color.
  final List<Color>? gradientHues;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      key: const ValueKey('share-card-bestiary-name'),
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final hues = gradientHues;
    if (hues == null) return text;
    return ShaderMask(
      key: const ValueKey('share-card-bestiary-name-gradient'),
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: hues,
      ).createShader(bounds),
      child: text,
    );
  }
}

/// The rank-sigil · XP · tonnage stat line — a rotated-diamond rank chip
/// (spec §4 / mockup `.sig`) followed by the rank/XP/tonnage rich-text run.
/// Extracted so the bestiary build() stays under the 50-line widget-extraction
/// threshold and the diamond + gold-XP composition is isolated.
class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.tierLabel,
    required this.rankLabel,
    required this.xpLabel,
    required this.tonnageLabel,
    required this.accentHue,
    required this.renderTarget,
  });

  /// The tier letter rendered inside the diamond chip, e.g. "C" / "S".
  final String tierLabel;
  final String rankLabel;
  final String xpLabel;
  final String tonnageLabel;
  final Color accentHue;
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    final base = ShareCardTypography.bestiaryStat(renderTarget);
    final xpStyle = ShareCardTypography.bestiaryStatXp(renderTarget);
    final sep = base.copyWith(color: AppColors.textDim);
    return Row(
      key: const ValueKey('share-card-bestiary-stat'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _RankSigilChip(
          tierLabel: tierLabel,
          color: accentHue,
          renderTarget: renderTarget,
        ),
        SizedBox(width: renderTarget == ShareCardRenderTarget.preview ? 9 : 32),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: rankLabel, style: base),
                TextSpan(text: '  ·  ', style: sep),
                TextSpan(text: xpLabel, style: xpStyle),
                TextSpan(text: '  ·  ', style: sep),
                TextSpan(text: tonnageLabel, style: base),
              ],
            ),
            key: const ValueKey('share-card-bestiary-stat-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The rotated-diamond rank chip (spec §4 / mockup `.sig`): a 19×19 square
/// (at 300dp) with a 1.5px `currentColor` border rotated 45°, holding the
/// tier letter counter-rotated so it reads upright. Replaces the previous
/// bare `◈` sigil glyph.
class _RankSigilChip extends StatelessWidget {
  const _RankSigilChip({
    required this.tierLabel,
    required this.color,
    required this.renderTarget,
  });

  final String tierLabel;
  final Color color;
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    final preview = renderTarget == ShareCardRenderTarget.preview;
    final box = preview ? 19.0 : 34.0;
    final border = preview ? 1.5 : 2.7;
    return SizedBox(
      width: box,
      height: box,
      child: Transform.rotate(
        // The chip square rotates 45° into a diamond.
        angle: 0.7853981633974483, // π/4
        child: DecoratedBox(
          key: const ValueKey('share-card-bestiary-rank-sigil'),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: border),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
          child: Center(
            child: Transform.rotate(
              // Counter-rotate the letter so it reads upright.
              angle: -0.7853981633974483,
              child: Text(
                tierLabel,
                style: ShareCardTypography.bestiaryRankSigil(
                  renderTarget,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
