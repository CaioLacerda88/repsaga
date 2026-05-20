import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/enum_l10n.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/routine.dart';

class RoutineCard extends StatelessWidget {
  const RoutineCard({
    super.key,
    required this.routine,
    required this.onTap,
    this.onLongPress,
  });

  final Routine routine;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  String _buildSubtitle(AppLocalizations l10n) {
    final muscleGroups = <String>{};
    for (final re in routine.exercises) {
      if (re.exercise != null) {
        muscleGroups.add(re.exercise!.muscleGroup.localizedName(l10n));
      }
    }
    if (muscleGroups.isNotEmpty) {
      return muscleGroups.join(' \u00b7 ');
    }
    return l10n.exercisesCount(routine.exercises.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        routine.name,
                        // [titleDisplay] = Rajdhani 600 at the 16dp list-
                        // title slot. Routines are action surfaces (tap →
                        // starts a workout), not reference content — they
                        // earn the Arcane Ascent register that Inter [title]
                        // doesn't carry. Per UX-critic Phase 27 L18.4
                        // verdict: Routines change to Rajdhani, Exercises
                        // (a reference library surface) stay on [title].
                        style: AppTextStyles.titleDisplay,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _buildSubtitle(l10n),
                        style: AppTextStyles.body.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
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
