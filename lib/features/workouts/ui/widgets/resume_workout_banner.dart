import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/workout_providers.dart';

/// Prominent banner shown on the home screen when there is an active workout
/// in progress.
///
/// Watches [activeWorkoutProvider] and renders nothing if no active workout
/// exists or if the workout has no exercises yet.
/// Tapping navigates to the active workout screen.
class ResumeWorkoutBanner extends ConsumerWidget {
  const ResumeWorkoutBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncWorkout = ref.watch(activeWorkoutProvider);
    final state = asyncWorkout.value;

    if (state == null) return const SizedBox.shrink();
    if (state.exercises.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final elapsedAsync = ref.watch(
      elapsedTimerProvider(state.workout.startedAt),
    );
    final elapsed = elapsedAsync.value ?? Duration.zero;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          context.go('/workout/active');
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // PR-7 brand-glyph swap: Material `Icons.fitness_center` reads
              // as a generic AI fitness app. `AppIcons.lift` is the
              // Game-Icons silhouette that doubles as the app's signature
              // glyph (see `AppIcons.lift` doc — same asset reused here so
              // the resume banner reads as continuity with the running
              // workout, not a separate Material widget.).
              AppIcons.render(
                AppIcons.lift,
                size: 24,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.workout.name,
                      style: AppTextStyles.title.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDuration(elapsed),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onPrimary),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats [duration] as `MM:SS` when under an hour, or `H:MM:SS` otherwise.
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
