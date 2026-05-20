import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/character_sheet_state.dart';
import '../../providers/rank_up_pulse_provider.dart';
import '../utils/vitality_state_styles.dart';
import 'ambient_pulse_dot.dart';
import 'body_part_localization.dart';

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
/// Every trained dot renders an [AmbientPulseDot] — subtle baseline pulse
/// (Phase 27 L8) so the row reads as "this body part is active". When
/// [RankUpPulseLocalStorage.isPulsing] returns true (24h post-rank-up
/// window — Phase 26b), the same widget is mounted with `emphasized: true`
/// for a bigger/faster pulse as additive emphasis.
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
    final emphasized = pulseStorage.isPulsing(entry.bodyPart);
    return _TrainedRow(entry: entry, emphasized: emphasized);
  }
}

class _TrainedRow extends StatelessWidget {
  const _TrainedRow({required this.entry, required this.emphasized});

  final BodyPartSheetEntry entry;

  /// `true` when the body part is in its 24h post-rank-up window — drives
  /// the [AmbientPulseDot]'s `emphasized` flag. `false` still renders the
  /// dot with the subtle ambient pulse (Phase 27 L8).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
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

    // Semantics MUST wrap the InkWell directly (single build method, no
    // intervening widget boundaries) so Flutter merges them into one
    // SemanticsNode. When the wrapper sat in the parent for-loop in
    // character_sheet_screen.dart, two widget layers (ConsumerWidget +
    // private _TrainedRow) separated the SemanticsNode from the gesture
    // detector — Flutter web's AOM dispatched Playwright's click to the
    // outer node which had no GestureDetector, so onTap never fired. The
    // proven-working pattern in `vitality_table.dart` is Semantics →
    // (Material →) InkWell as direct neighbors in one build method.
    // Cluster: semantics-identifier-pair-rule.
    return Semantics(
      container: true,
      button: true,
      identifier: 'body-part-row-${entry.bodyPart.dbValue}',
      child: InkWell(
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
                    _Dot(color: dotColor, emphasized: emphasized),
                    const SizedBox(width: 8),
                    Text(
                      _localizedName(entry.bodyPart, l10n).toUpperCase(),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 10,
                        letterSpacing: _nameLetterSpacing,
                        color: AppColors.textCream,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${entry.rank}',
                      // [AppTextStyles.numeric] = Rajdhani 700 20dp
                      // tabular figures — exactly what was being
                      // built by hand. Routing through the token so
                      // the typography call-site CI gate
                      // (`scripts/check_typography_call_sites.sh`)
                      // can lock raw `fontFamily: 'Rajdhani'` literals
                      // out of `lib/features/`.
                      style: AppTextStyles.numeric,
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
                      // Phase 28a: collapsed the 5-property override stack
                      // (`numeric.copyWith(fontSize: 11, w600, textDim,
                      // letterSpacing: 0.04 * 11)`) into the canonical
                      // [AppTextStyles.numericSmall] token. Same rendered
                      // pixels, one named contract for the sub-bar XP register.
                      style: AppTextStyles.numericSmall,
                    ),
                    Text(
                      '${AppNumberFormat.integer(remaining, locale: locale)} ${l10n.withinRankXpSuffix}',
                      style: AppTextStyles.numericSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.emphasized});

  final Color color;

  /// Forwarded to [AmbientPulseDot.emphasized]. Trained dots ALWAYS pulse
  /// (Phase 27 L8) — the flag only escalates the amplitude/period for the
  /// 24h post-rank-up window.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return AmbientPulseDot(color: color, size: 6, emphasized: emphasized);
  }
}

class _UntrainedRow extends StatelessWidget {
  const _UntrainedRow({required this.entry});

  final BodyPartSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Element-level alpha (0.4) instead of an Opacity wrapper — Opacity
    // creates a compositing layer that the InkWell splash paints THROUGH
    // at full alpha, which reads as a visual defect on tap. Applying alpha
    // per-color lets the splash render at theme strength while the dimmed
    // text + dot stay at 40% saturation.
    final dimmedTextDim = AppColors.textDim.withValues(alpha: 0.4);
    // Same single-build-method Semantics→InkWell pattern as _TrainedRow.
    // Untrained rows are still tappable (they navigate to the stats deep-
    // dive with body_part pre-filtered), so they need the same routing
    // contract and the same identifier shape so the E2E selector
    // `body-part-row-<slug>` works for every slug regardless of train state.
    return Semantics(
      container: true,
      button: true,
      identifier: 'body-part-row-${entry.bodyPart.dbValue}',
      child: InkWell(
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
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    letterSpacing: _nameLetterSpacing,
                    color: dimmedTextDim,
                  ),
                ),
                const Spacer(),
                Text(
                  '—',
                  // The em-dash sits in the same slot the trained rows
                  // render their Rajdhani rank numeral. Render it in
                  // [AppTextStyles.numeric] so the rank column has one
                  // consistent typeface across trained + untrained rows
                  // (previously fell back to Material's default Inter,
                  // creating a row-by-row typeface flicker).
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

String _localizedName(BodyPart bodyPart, AppLocalizations l10n) =>
    localizedBodyPartName(bodyPart, l10n);
