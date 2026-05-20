import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/workout_formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../models/workout.dart';
import '../providers/workout_history_providers.dart';

/// Displays paginated workout history with pull-to-refresh.
class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() =>
      _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final notifier = ref.read(workoutHistoryProvider.notifier);
    if (!notifier.hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Load more when within 200px of the bottom.
    if (currentScroll >= maxScroll - 200) {
      notifier.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncWorkouts = ref.watch(workoutHistoryProvider);

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'history-heading',
          child: Text(l10n.history),
        ),
      ),
      body: asyncWorkouts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.failedToLoadHistory, style: AppTextStyles.title),
              const SizedBox(height: 8),
              Semantics(
                container: true,
                identifier: 'history-retry',
                child: FilledButton(
                  onPressed: () =>
                      ref.read(workoutHistoryProvider.notifier).refresh(),
                  child: Text(l10n.retry),
                ),
              ),
            ],
          ),
        ),
        data: (workouts) {
          if (workouts.isEmpty) {
            return _EmptyHistoryBody(onStartWorkout: () => context.go('/home'));
          }

          final notifier = ref.read(workoutHistoryProvider.notifier);
          final showLoadingMore = notifier.isLoadingMore || notifier.hasMore;

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(workoutHistoryProvider.notifier).refresh(),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              itemCount: workouts.length + (showLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= workouts.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _WorkoutHistoryCard(
                  workout: workouts[index],
                  onTap: () =>
                      context.go('/home/history/${workouts[index].id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyHistoryBody extends StatelessWidget {
  const _EmptyHistoryBody({required this.onStartWorkout});

  final VoidCallback onStartWorkout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              identifier: 'history-empty',
              child: Text(
                l10n.noWorkoutsYet,
                style: AppTextStyles.title.copyWith(
                  fontSize: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.completedWorkoutsAppear,
              style: AppTextStyles.body.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              container: true,
              identifier: 'history-empty-cta',
              child: FilledButton.icon(
                onPressed: onStartWorkout,
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.startFirstWorkout),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutHistoryCard extends StatelessWidget {
  const _WorkoutHistoryCard({required this.workout, required this.onTap});

  final Workout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final dateText = WorkoutFormatters.formatWorkoutDate(
      workout.finishedAt ?? workout.startedAt,
      l10n: l10n,
      locale: locale,
    );
    final durationText = WorkoutFormatters.formatDuration(
      workout.durationSeconds,
      l10n: l10n,
    );

    return Semantics(
      label: '${workout.name}, $dateText, $durationText',
      button: true,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workout.name,
                        style: AppTextStyles.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (workout.exerciseSummary != null &&
                          workout.exerciseSummary!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          workout.exerciseSummary!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        durationText,
                        style: AppTextStyles.body.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  dateText,
                  style: AppTextStyles.body.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
