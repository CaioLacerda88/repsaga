import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/stats_deep_dive_state.dart';
import '../utils/vitality_state_styles.dart';
import 'body_part_localization.dart';

/// Per-body-part Volume + Carga pico block for the stats deep-dive
/// screen (Phase 26c). Two columns:
///   * Left: weekly volume ("X / Y séries") with history-aware delta.
///   * Right: monthly peak EWMA ("N kg" with "30D" badge + delta), OR
///     the generic-tip fallback ("Referência" + 10 séries + estimado)
///     when the user has no personal history for this body part.
///
/// Pure presentation — the [VolumeDeltaView] + [PeakDeltaView] arguments
/// encode the rendering state computed in the model layer.
class VolumePeakBlock extends StatelessWidget {
  const VolumePeakBlock({
    super.key,
    required this.bodyPart,
    required this.row,
    required this.volumeDelta,
    required this.peakDelta,
  });

  final BodyPart bodyPart;
  final VolumePeakRow row;
  final VolumeDeltaView volumeDelta;
  final PeakDeltaView peakDelta;

  /// Schoenfeld 2019 hypertrophy maintenance floor — used as the
  /// generic-tip fallback's "Referência" value when the user has no
  /// personal history for this body part.
  static const int _schoenfeldFloor = 10;

  bool get _useGenericTip => row.weeksOfHistory < 1 && row.peakEwma <= 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dotColor =
        VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.textDim;
    return Semantics(
      container: true,
      identifier: 'volume-peak-block-${bodyPart.dbValue}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: dot + body-part name.
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  localizedBodyPartName(bodyPart, l10n),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Two columns.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _VolumeColumn(
                    l10n: l10n,
                    locale: locale,
                    row: row,
                    delta: volumeDelta,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _useGenericTip
                      ? _ReferenciaColumn(l10n: l10n)
                      : _CargaPicoColumn(
                          l10n: l10n,
                          locale: locale,
                          row: row,
                          delta: peakDelta,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeColumn extends StatelessWidget {
  const _VolumeColumn({
    required this.l10n,
    required this.locale,
    required this.row,
    required this.delta,
  });

  final AppLocalizations l10n;
  final String locale;
  final VolumePeakRow row;
  final VolumeDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = _targetText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.volumePeakBlockVolumeLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: 2),
        // Value row: "12 / 16 séries"  OR  "12 séries" (no target if delta is
        // suppressed / no basis).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              '${row.weeklyVolumeSets}',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textCream,
                height: 1,
              ),
            ),
            if (targetText != null) ...[
              const SizedBox(width: 4),
              Text(
                '/ $targetText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  l10n.volumePeakBlockSeries,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _VolumeDeltaLine(l10n: l10n, delta: delta),
      ],
    );
  }

  /// "{Y} séries" for the displayed target, or null when the basis is
  /// null (suppressed delta — no comparison rendered).
  String? _targetText() {
    switch (delta.basis) {
      case VolumeDeltaBasis.previousWeek:
        return '${row.previousWeekVolumeSets ?? 0} ${l10n.volumePeakBlockSeries}';
      case VolumeDeltaBasis.fourWeekMean:
        return '${(row.fourWeekMeanVolumeSets ?? 0).round()} ${l10n.volumePeakBlockSeries}';
      case null:
        return null;
    }
  }
}

class _VolumeDeltaLine extends StatelessWidget {
  const _VolumeDeltaLine({required this.l10n, required this.delta});

  final AppLocalizations l10n;
  final VolumeDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (delta.state) {
      case VolumeDeltaState.suppressed:
        return Text(
          l10n.volumePeakBlockDeltaNoHistory,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        );
      case VolumeDeltaState.met:
        return Text(
          '● ${_basisLabel()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.vitalityHigh,
          ),
        );
      case VolumeDeltaState.underTarget:
        return Text(
          '▼ ${delta.delta.round()} ${_basisLabel()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.vitalityLow,
          ),
        );
      case VolumeDeltaState.overTarget:
        return Text(
          '▲ +${delta.delta.round()} ${l10n.volumePeakBlockDeltaAboveTarget}',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning),
        );
    }
  }

  String _basisLabel() {
    switch (delta.basis) {
      case VolumeDeltaBasis.previousWeek:
        return l10n.volumePeakBlockDeltaVsPrevWeek;
      case VolumeDeltaBasis.fourWeekMean:
        return l10n.volumePeakBlockDeltaVsFourWeekMean;
      case null:
        return '';
    }
  }
}

class _CargaPicoColumn extends StatelessWidget {
  const _CargaPicoColumn({
    required this.l10n,
    required this.locale,
    required this.row,
    required this.delta,
  });

  final AppLocalizations l10n;
  final String locale;
  final VolumePeakRow row;
  final PeakDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.volumePeakBlockCargaPicoLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              AppNumberFormat.integer(row.peakEwma, locale: locale),
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textCream,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                // Phase 26c v1 fixed-unit; locale-aware unit comes with the
                // future settings work.
                'kg',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _PeakDeltaLine(l10n: l10n, locale: locale, delta: delta),
      ],
    );
  }
}

class _PeakDeltaLine extends StatelessWidget {
  const _PeakDeltaLine({
    required this.l10n,
    required this.locale,
    required this.delta,
  });

  final AppLocalizations l10n;
  final String locale;
  final PeakDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (delta.state) {
      case PeakDeltaState.suppressed:
      case PeakDeltaState.flat:
        return Text(
          l10n.volumePeakBlockDeltaNoHistory,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        );
      case PeakDeltaState.up:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                l10n.volumePeakBlockBadge30D,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textDim,
                  fontSize: 9,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '▲ +${AppNumberFormat.integer(delta.delta, locale: locale)} kg',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.vitalityHigh,
              ),
            ),
          ],
        );
    }
  }
}

class _ReferenciaColumn extends StatelessWidget {
  const _ReferenciaColumn({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.volumePeakBlockReferenciaLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(width: 4),
            // ⓘ marker — currently non-interactive per Phase 26c plan;
            // the bottom-sheet explainer for the Schoenfeld floor is
            // out-of-scope for the minimum-viable block.
            const Icon(Icons.info_outline, size: 11, color: AppColors.textDim),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              '${VolumePeakBlock._schoenfeldFloor}',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textCream,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                l10n.volumePeakBlockSeries,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.volumePeakBlockDeltaEstimated,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }
}
