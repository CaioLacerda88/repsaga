import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../share_card_chassis.dart';
import '../share_card_typography.dart';

/// One cell of the Clean Flex four-stat strip — a value over a key label.
class CleanFlexStat {
  const CleanFlexStat({required this.value, required this.label});

  /// Pre-formatted numeric value, e.g. "+618", "8,4 t", "24", "47 min".
  final String value;

  /// Pre-localized key, e.g. "XP", "TONELAGEM", "SÉRIES", "DURAÇÃO".
  final String label;
}

/// Clean Flex (simple serious) share overlay (Phase 39 spec §7 Stats mode,
/// Slice 1) — the data-forward, no-fantasy card rendered into the same
/// shared [ShareCardChassis] as the Bestiary mode.
///
/// **Layout (mockup "Clean Flex" rows):**
/// ```
/// BULWARK · NÍVEL 9            ← eyebrow (class · character level, hotViolet)
/// 130 kg × 3                   ← PR hero (Rajdhani numeral; "Supino" context below)
/// Supino · Peito 18 → 19       ← hero context line (lift name + engaged-muscle delta)
/// ┌──────┬──────┬──────┬──────┐
/// │ +618 │ 8,4t │  24  │ 47min│   ← four-stat strip (XP / tonnage / sets / duration)
/// │  XP  │ TONS │ SETS │ DUR  │
/// └──────┴──────┴──────┴──────┘
/// ```
///
/// The six-ring conditioning dashboard is Slice 2 — Slice 1 ships the
/// four-stat strip only (WIP Slice 1 scope).
///
/// **Decoupling Rule 2.** Every string ([eyebrow], [heroValue],
/// [heroContext], [stats]) arrives pre-localized + pre-formatted from the
/// screen layer. This widget never reads `AppLocalizations.of(context)`.
class ShareCardCleanFlex extends StatelessWidget {
  const ShareCardCleanFlex({
    super.key,
    required this.eyebrow,
    required this.heroValue,
    required this.stats,
    required this.wordmark,
    this.heroUnit,
    this.heroContext,
    this.photo,
    this.renderTarget = ShareCardRenderTarget.export,
  });

  /// Pre-localized eyebrow, e.g. "Bulwark · Nível 9".
  final String eyebrow;

  /// Pre-formatted hero value, e.g. "130" (the leading numeral). The unit
  /// suffix ("kg × 3") is [heroUnit] so it can render at a demoted size.
  final String heroValue;

  /// Optional hero unit suffix, e.g. " kg × 3". `null` when the hero is a
  /// standalone numeral (e.g. a tonnage-fallback hero).
  final String? heroUnit;

  /// Optional hero context line, e.g. "Supino · Peito 18 → 19". `null`
  /// collapses the line (mockup "adaptive — no change, no clutter").
  final String? heroContext;

  /// The four stat cells (XP / tonnage / sets / duration). Rendered as an
  /// even strip above the rail.
  final List<CleanFlexStat> stats;

  /// Pre-localized wordmark, e.g. "REPSAGA".
  final String wordmark;

  /// Optional photo underlay (null on the discreet path).
  final ImageProvider<Object>? photo;

  /// Export vs preview target — forwarded to typography + the chassis.
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    return ShareCardChassis(
      wordmark: wordmark,
      photo: photo,
      // The Clean Flex card "breathes" — a shorter scrim than Bestiary
      // (mockup: less ink on the photo).
      scrimHeightFraction: 0.42,
      renderTarget: renderTarget,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            key: const ValueKey('share-card-clean-flex-eyebrow'),
            style: ShareCardTypography.cleanFlexEyebrow(
              renderTarget,
              color: AppColors.hotViolet,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: _gap(6)),
          _Hero(value: heroValue, unit: heroUnit, renderTarget: renderTarget),
          if (heroContext != null) ...[
            SizedBox(height: _gap(7)),
            Text(
              heroContext!,
              key: const ValueKey('share-card-clean-flex-context'),
              style: ShareCardTypography.cleanFlexStatKey(
                renderTarget,
              ).copyWith(color: AppColors.textDimAA),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: _gap(14)),
          _StatStrip(stats: stats, renderTarget: renderTarget),
        ],
      ),
    );
  }

  double _gap(double base) =>
      base * (renderTarget == ShareCardRenderTarget.preview ? 1.0 : 3.6);
}

/// PR hero — a large leading numeral with a demoted unit suffix.
class _Hero extends StatelessWidget {
  const _Hero({required this.value, this.unit, required this.renderTarget});

  final String value;
  final String? unit;
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: ShareCardTypography.cleanFlexHero(renderTarget),
          ),
          if (unit != null)
            TextSpan(
              text: unit,
              style: ShareCardTypography.cleanFlexHeroUnit(renderTarget),
            ),
        ],
      ),
      key: const ValueKey('share-card-clean-flex-hero'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The even four-stat strip with a top hairline divider.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.stats, required this.renderTarget});

  final List<CleanFlexStat> stats;
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    final pad = renderTarget == ShareCardRenderTarget.preview ? 12.0 : 43.0;
    return Container(
      key: const ValueKey('share-card-clean-flex-strip'),
      padding: EdgeInsets.only(top: pad),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            // ignore: hardcoded_color — hairline divider over the photo scrim (white at low alpha, mockup "Clean Flex" strip rule).
            color: Color(0x21FFFFFF),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final stat in stats)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stat.value,
                    style: ShareCardTypography.cleanFlexStatValue(renderTarget),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                    height: renderTarget == ShareCardRenderTarget.preview
                        ? 3.0
                        : 11.0,
                  ),
                  Text(
                    stat.label,
                    style: ShareCardTypography.cleanFlexStatKey(renderTarget),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
