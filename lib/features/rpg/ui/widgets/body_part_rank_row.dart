import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/character_sheet_state.dart';
import '../../providers/rank_up_pulse_provider.dart';
import '../utils/vitality_state_styles.dart';
import 'body_part_localization.dart';
import 'rank_up_pulse.dart';

/// Letter-spacing for the uppercase body-part name across trained +
/// untrained rows. Phase 26b Option B v4 type token; matches the 12%
/// tracking used by other UPPERCASE labels in `AppTextStyles.label`.
const double _nameLetterSpacing = 1.2;

/// Single body-part row on the Saga character sheet (Phase 26b Option B v4).
///
/// 48dp min-height tap target. Two-row layout inside:
///   * Top row: 6dp body-part-hue dot · UPPERCASE 10sp name · 20sp
///     Rajdhani-700 tabular rank num (right-aligned).
///   * Middle: 4dp body-part-hue progress bar (within-rank fill on
///     [AppColors.xpTrack] background).
///   * Bottom: 9sp Rajdhani-600 textDim "X XP" + "Y para o próximo rank".
///
/// Untrained rows (`entry.isUntrained` — rank 1, totalXp 0, vitalityPeak 0)
/// render at 0.4 opacity with `—` instead of the rank num, no bar, no
/// label row.
///
/// The whole row is `InkWell` tappable → `/saga/stats?body_part=<dbValue>`
/// so the stats deep-dive opens with the trend chart pre-selected.
///
/// When [RankUpPulseLocalStorage.isPulsing] returns true for this body
/// part, the dot is wrapped in [RankUpPulse] for the 24h glow-ring
/// overlay.
class BodyPartRankRow extends ConsumerWidget {
  const BodyPartRankRow({super.key, required this.entry});

  final BodyPartSheetEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always read the provider first — Riverpod convention is to watch
    // unconditionally so the subscription set is stable across rebuilds.
    // The untrained branch ignores the result (untrained rows never pulse).
    final pulseStorage = ref.watch(rankUpPulseLocalStorageProvider);
    if (entry.isUntrained) {
      return _UntrainedRow(entry: entry);
    }
    final isPulsing = pulseStorage.isPulsing(entry.bodyPart);
    return _TrainedRow(entry: entry, isPulsing: isPulsing);
  }
}

class _TrainedRow extends StatelessWidget {
  const _TrainedRow({required this.entry, required this.isPulsing});

  final BodyPartSheetEntry entry;
  final bool isPulsing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dotColor =
        VitalityStateStyles.bodyPartColor[entry.bodyPart] ?? AppColors.textDim;
    final fraction = entry.xpForNextRank <= 0
        ? 1.0
        : (entry.xpInRank / entry.xpForNextRank).clamp(0.0, 1.0);
    final remaining = (entry.xpForNextRank - entry.xpInRank).clamp(
      0.0,
      double.infinity,
    );

    return InkWell(
      onTap: () =>
          context.push('/saga/stats?body_part=${entry.bodyPart.dbValue}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Dot(color: dotColor, isPulsing: isPulsing),
                  const SizedBox(width: 8),
                  Text(
                    _localizedName(entry.bodyPart, l10n).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textCream,
                      letterSpacing: _nameLetterSpacing,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entry.rank}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textCream,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                key: const ValueKey('body-part-row-bar'),
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 4,
                  color: AppColors.xpTrack,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: dotColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${AppNumberFormat.integer(entry.xpInRank, locale: locale)} XP',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim,
                    ),
                  ),
                  Text(
                    '${AppNumberFormat.integer(remaining, locale: locale)} ${l10n.withinRankXpSuffix}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.isPulsing});

  final Color color;
  final bool isPulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    if (!isPulsing) return dot;
    return RankUpPulse(color: color, child: dot);
  }
}

class _UntrainedRow extends StatelessWidget {
  const _UntrainedRow({required this.entry});

  final BodyPartSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Element-level alpha (0.4) instead of an Opacity wrapper — Opacity
    // creates a compositing layer that the InkWell splash paints THROUGH
    // at full alpha, which reads as a visual defect on tap. Applying alpha
    // per-color lets the splash render at theme strength while the dimmed
    // text + dot stay at 40% saturation.
    final dimmedTextDim = AppColors.textDim.withValues(alpha: 0.4);
    return InkWell(
      onTap: () =>
          context.push('/saga/stats?body_part=${entry.bodyPart.dbValue}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dimmedTextDim,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _localizedName(entry.bodyPart, l10n).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: dimmedTextDim,
                  letterSpacing: _nameLetterSpacing,
                ),
              ),
              const Spacer(),
              Text('—', style: TextStyle(color: dimmedTextDim)),
            ],
          ),
        ),
      ),
    );
  }
}

String _localizedName(BodyPart bodyPart, AppLocalizations l10n) =>
    localizedBodyPartName(bodyPart, l10n);
