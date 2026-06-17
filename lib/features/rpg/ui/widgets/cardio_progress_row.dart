import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/body_part.dart';
import '../../models/character_sheet_state.dart';
import '../../providers/rank_up_pulse_provider.dart';
import 'ambient_pulse_dot.dart';

/// Letter-spacing for the uppercase track name — matches
/// [BodyPartRankRow]'s `_nameLetterSpacing` so the cardio row reads as a
/// peer of the six strength rows.
const double _nameLetterSpacing = 1.2;

/// Background tint + hairline alpha for the grouped-apart cardio band
/// (Phase 38e locked mockup — `bodyPartCardio @ 0.05` fill, `@ 0.16`
/// top/bottom hairlines). Constants live here so the band is the single
/// "this is a different track" cue, applied once.
const double _bandFillAlpha = 0.05;
const double _bandHairlineAlpha = 0.16;

/// Alpha for the untrained cardio dot — a DELIBERATE one-line divergence
/// from [BodyPartRankRow]'s `_UntrainedRow`, which dims its dot to grey
/// (`textDim @ 0.4`). For cardio the dimmed dot stays TEAL so the dormant
/// row keeps cardio identity ("log a run to wake it") instead of reading as
/// generic grey. Everything else in the untrained branch (em-dash rank, no
/// bar, no XP line, 0.4-alpha text) matches the strength skeleton.
const double _untrainedDotAlpha = 0.32;

/// The 7th Saga-rail row: the cardio progression track (Phase 38e).
///
/// Replaces the retired `DormantCardioRow` ("coming soon"). The provider
/// auto-emits a [BodyPartSheetEntry] for [BodyPart.cardio] (it is now in
/// `activeBodyParts`); this widget renders that entry inside a faintly
/// teal-tinted band with a small `CARDIO` eyebrow, grouped apart from the
/// six strength rows by a `surface2` divider + gap (drawn by the caller).
///
/// **Borrows the strength row skeleton verbatim** so it reads as a peer:
///   * Trained: pulsing teal [AmbientPulseDot], UPPERCASE track name,
///     Rajdhani-700 rank numeral, 4dp teal within-rank bar, `XP/XP`
///     sub-line.
///   * Untrained (day-zero — rank 1, totalXp 0, vitalityPeak 0): dimmed-TEAL
///     dot, `—` rank, NO bar, NO XP line.
///
/// The whole row is tappable → `/saga/stats?body_part=cardio`. The track
/// name comes from [trackLabel] (the conditioning STAT label, not the
/// "Cardio" muscle-group label) per Decoupling Rule 2 (l10n-as-param).
class CardioProgressRow extends ConsumerWidget {
  const CardioProgressRow({
    super.key,
    required this.entry,
    required this.trackLabel,
    required this.eyebrowLabel,
  });

  /// The cardio [BodyPartSheetEntry] emitted by `characterSheetProvider`.
  final BodyPartSheetEntry entry;

  /// Localized track name (e.g. "CONDITIONING" / "CONDICIONAMENTO"). Cased
  /// to UPPERCASE by the widget.
  final String trackLabel;

  /// Localized band eyebrow (e.g. "Cardio"). Cased to UPPERCASE.
  final String eyebrowLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch unconditionally (Riverpod convention — stable subscription set);
    // the untrained branch ignores the result (dormant rows never pulse).
    final pulseStorage = ref.watch(rankUpPulseLocalStorageProvider);
    final emphasized =
        !entry.isUntrained && pulseStorage.isPulsing(entry.bodyPart);

    return _CardioBand(
      eyebrowLabel: eyebrowLabel,
      child: entry.isUntrained
          ? _UntrainedCardioRow(trackLabel: trackLabel)
          : _TrainedCardioRow(
              entry: entry,
              trackLabel: trackLabel,
              emphasized: emphasized,
            ),
    );
  }
}

/// The teal-tinted band wrapper carrying the `CARDIO` eyebrow.
class _CardioBand extends StatelessWidget {
  const _CardioBand({required this.eyebrowLabel, required this.child});

  final String eyebrowLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bodyPartCardio.withValues(alpha: _bandFillAlpha),
        border: Border(
          top: BorderSide(
            color: AppColors.bodyPartCardio.withValues(
              alpha: _bandHairlineAlpha,
            ),
          ),
          bottom: BorderSide(
            color: AppColors.bodyPartCardio.withValues(
              alpha: _bandHairlineAlpha,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 2),
            child: Text(
              eyebrowLabel.toUpperCase(),
              style: AppTextStyles.label.copyWith(
                fontSize: 10,
                letterSpacing: 1.6,
                color: AppColors.bodyPartCardio.withValues(alpha: 0.72),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _TrainedCardioRow extends StatelessWidget {
  const _TrainedCardioRow({
    required this.entry,
    required this.trackLabel,
    required this.emphasized,
  });

  final BodyPartSheetEntry entry;
  final String trackLabel;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final fraction = entry.xpForNextRank <= 0
        ? 1.0
        : (entry.xpInRank / entry.xpForNextRank).clamp(0.0, 1.0);

    // Same single-build-method Semantics → InkWell pattern as
    // BodyPartRankRow (cluster: semantics-identifier-pair-rule) so Flutter
    // web's AOM dispatches the tap to the gesture detector.
    return Semantics(
      container: true,
      button: true,
      identifier: 'body-part-row-${entry.bodyPart.dbValue}',
      child: InkWell(
        onTap: () =>
            context.push('/saga/stats?body_part=${entry.bodyPart.dbValue}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AmbientPulseDot(
                      color: AppColors.bodyPartCardio,
                      size: 6,
                      emphasized: emphasized,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trackLabel.toUpperCase(),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 10,
                        letterSpacing: _nameLetterSpacing,
                        color: AppColors.textCream,
                      ),
                    ),
                    const Spacer(),
                    Text('${entry.rank}', style: AppTextStyles.numeric),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  key: const ValueKey('cardio-row-bar'),
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 4,
                    color: AppColors.xpTrack,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.bodyPartCardio,
                        ),
                      ),
                    ),
                  ),
                ),
                if (entry.xpForNextRank > 0) ...[
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: AppTextStyles.numericSmall,
                      children: [
                        TextSpan(
                          text: AppNumberFormat.integer(
                            entry.xpInRank,
                            locale: locale,
                          ),
                          style: const TextStyle(color: AppColors.textCream),
                        ),
                        TextSpan(
                          text:
                              '/${AppNumberFormat.integer(entry.xpForNextRank, locale: locale)} XP',
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UntrainedCardioRow extends StatelessWidget {
  const _UntrainedCardioRow({required this.trackLabel});

  final String trackLabel;

  @override
  Widget build(BuildContext context) {
    // Element-level alpha on the text (not an Opacity wrapper — see
    // BodyPartRankRow._UntrainedRow) so the InkWell splash renders at full
    // strength. The DOT alpha is the deliberate cardio override: dimmed TEAL
    // (`_untrainedDotAlpha`), not the grey `textDim @ 0.4` the strength
    // skeleton uses — keeps cardio identity while dormant.
    final dimmedTextDim = AppColors.textDim.withValues(alpha: 0.4);
    return Semantics(
      container: true,
      button: true,
      identifier: 'body-part-row-cardio',
      child: InkWell(
        onTap: () => context.push('/saga/stats?body_part=cardio'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bodyPartCardio.withValues(
                      alpha: _untrainedDotAlpha,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trackLabel.toUpperCase(),
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    letterSpacing: _nameLetterSpacing,
                    color: dimmedTextDim,
                  ),
                ),
                const Spacer(),
                Text(
                  '—',
                  style: AppTextStyles.numeric.copyWith(color: dimmedTextDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
