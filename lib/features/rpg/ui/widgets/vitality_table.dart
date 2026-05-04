import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_muscle_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/stats_deep_dive_state.dart';
import '../../models/vitality_state.dart';
import '../utils/vitality_state_styles.dart';
import 'body_part_localization.dart';

/// The "live Vitality" section of the stats deep-dive screen — six rows
/// showing each body part's current Vitality % alongside the §8.4 state
/// copy. Tapping a row drives the trend-chart selection above it.
///
/// **Layout primitive (UX critic lock):** rows are raw `Row` widgets inside
/// `Padding(EdgeInsets.symmetric(horizontal: 16, vertical: 12))` inside a
/// `Column` with `Divider(height: 1, color: AppTheme.surface2)` between
/// them. We deliberately avoid `ListTile` — its `minVerticalPadding` (4dp),
/// 72dp min-height, and injected `MergeSemantics` leak Material defaults
/// that drift toward stock-Material register and away from the ledger
/// aesthetic the stats deep-dive lives in.
///
/// **Number-only readout:** the % renders as a Rajdhani 24sp tabularFigures
/// numeral colored by the row's Vitality state. There is no progress bar
/// next to the number (UX critic anti-pattern lock #3) — the number is
/// the quantity.
class VitalityTable extends StatelessWidget {
  const VitalityTable({
    super.key,
    required this.rows,
    required this.selectedBodyPart,
    required this.onSelect,
  });

  final List<VitalityTableRow> rows;

  /// Currently-selected body part. Drives the trend-chart highlighting; we
  /// reflect it here as a subtle row-level pulse so the user can confirm
  /// "yes, I clicked Chest" without drag-dropping focus to the chart.
  final BodyPart selectedBodyPart;

  /// Tap handler — receives the body part of the row that was tapped.
  final ValueChanged<BodyPart> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      children.add(
        _VitalityTableRow(
          row: row,
          isSelected: row.bodyPart == selectedBodyPart,
          onTap: () => onSelect(row.bodyPart),
        ),
      );
      if (i < rows.length - 1) {
        children.add(
          const Divider(height: 1, thickness: 1, color: AppColors.surface2),
        );
      }
    }
    return Semantics(
      container: true,
      identifier: 'vitality-table',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _VitalityTableRow extends StatelessWidget {
  const _VitalityTableRow({
    required this.row,
    required this.isSelected,
    required this.onTap,
  });

  final VitalityTableRow row;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final stateColor = VitalityStateStyles.borderColorFor(row.state);
    // Untested = peak == 0 (never trained). The ewma/peak ratio is
    // mathematically undefined, so we render an em-dash instead of the
    // misleading "0%" that a brand-new account would otherwise see across
    // all six body parts on the stats screen. Dormant (peak > 0, ewma ~ 0)
    // continues to render "0%" — that's a genuine zero ratio.
    final pctText = row.state == VitalityState.untested
        ? '—'
        : '${(row.pct * 100).round()}%';
    final localizedName = localizedBodyPartName(row.bodyPart, l10n);
    final stateCopy = VitalityStateStyles.localizedCopy(row.state, l10n);

    return Semantics(
      container: true,
      identifier: 'vitality-row-${row.bodyPart.dbValue}',
      button: true,
      selected: isSelected,
      label: '$localizedName, $pctText, $stateCopy',
      child: Material(
        // Selected row sits one elevation level higher so it confirms the
        // tap without redrawing the whole table. surface2 vs surface — the
        // existing palette ladder.
        color: isSelected ? AppColors.surface2 : AppColors.abyss,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                AppIcons.render(
                  _muscleAsset(row.bodyPart),
                  color: stateColor,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizedName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stateCopy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textDim,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  pctText,
                  style: GoogleFonts.rajdhani(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: stateColor,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                // 8x8 state-color dot — the chip-form legend per row.
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Map a [BodyPart] to its [AppMuscleIcons] asset path. v1 surfaces six
/// strength tracks; cardio's silhouette is wired here too so a future
/// cardio-track render picks up the same lookup.
String _muscleAsset(BodyPart bodyPart) {
  switch (bodyPart) {
    case BodyPart.chest:
      return AppMuscleIcons.chest;
    case BodyPart.back:
      return AppMuscleIcons.back;
    case BodyPart.legs:
      return AppMuscleIcons.legs;
    case BodyPart.shoulders:
      return AppMuscleIcons.shoulders;
    case BodyPart.arms:
      return AppMuscleIcons.arms;
    case BodyPart.core:
      return AppMuscleIcons.core;
    case BodyPart.cardio:
      return AppMuscleIcons.cardio;
  }
}
