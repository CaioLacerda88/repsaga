import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Visual states for a routine chip in the weekly bucket.
enum RoutineChipState {
  /// Completed — success-green tint, checkmark, collapsed width.
  done,

  /// Up next — solid violet, primary CTA, taller.
  next,

  /// Remaining — ghosted, not yet reached in sequence.
  remaining,
}

/// A pill-shaped chip representing a routine in the weekly bucket.
///
/// Three states per spec:
/// - [RoutineChipState.done]: 44dp, success-green checkmark, no name text
/// - [RoutineChipState.next]: 60dp, solid primary violet, Abyss text, secondary exercise count line
/// - [RoutineChipState.remaining]: 48dp, ghosted, sequence number + name at reduced opacity
class RoutineChip extends StatelessWidget {
  const RoutineChip({
    required this.sequenceNumber,
    required this.routineName,
    required this.chipState,
    this.exerciseCount,
    this.onTap,
    super.key,
  });

  final int sequenceNumber;
  final String routineName;
  final RoutineChipState chipState;

  /// Number of exercises in the routine. Shown on the `next` chip as a
  /// secondary line (e.g. "6 exercises").
  final int? exerciseCount;

  final VoidCallback? onTap;

  /// Up-next CTA fill. Violet is the daily interactive color in the Arcane
  /// palette; gold is quarantined to [RewardAccent] for PRs/level-ups.
  static const _nextColor = AppColors.primaryViolet;

  /// Done chip tint + border + checkmark. Success green is intentionally
  /// distinct from the CTA so "completed" never competes with "up next".
  static const _doneAccent = AppColors.success;
  static const _cardColor = AppColors.surface2;

  @override
  Widget build(BuildContext context) {
    return switch (chipState) {
      RoutineChipState.done => _buildDone(context),
      RoutineChipState.next => _buildNext(context),
      RoutineChipState.remaining => _buildRemaining(context),
    };
  }

  Widget _buildDone(BuildContext context) {
    return Container(
      height: 44,
      constraints: const BoxConstraints(minWidth: 44),
      decoration: BoxDecoration(
        color: _doneAccent.withValues(alpha: 0.13),
        border: Border.all(color: _doneAccent, width: 1),
        borderRadius: BorderRadius.circular(kRadiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: const Center(
        child: Icon(Icons.check, color: _doneAccent, size: 20),
      ),
    );
  }

  Widget _buildNext(BuildContext context) {
    final hasExerciseCount = exerciseCount != null && exerciseCount! > 0;

    return Material(
      color: _nextColor,
      borderRadius: BorderRadius.circular(kRadiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusLg),
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  // Sequence-number badge on the violet CTA: a dark overlay on
                  // top of the violet Material. abyss (#0D0319) at ~26% alpha
                  // tints the violet without a full blackout; contrast verified
                  // on both primaryViolet and the prior success-green fill.
                  color: AppColors.abyss.withValues(alpha: 0.26),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                // Sequence numeral — Rajdhani 700 tabular.
                child: Text(
                  '$sequenceNumber',
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 12,
                    color: AppColors.abyss,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routineName,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.abyss,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (hasExerciseCount)
                      Text(
                        AppLocalizations.of(
                          context,
                        ).exercisesCount(exerciseCount!),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.abyss.withValues(alpha: 0.54),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemaining(BuildContext context) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(kRadiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusLg),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.textCream.withValues(alpha: 0.13),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(kRadiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.textCream.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$sequenceNumber',
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 11,
                    color: AppColors.textCream.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  routineName,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textCream.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
