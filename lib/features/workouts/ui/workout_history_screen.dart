import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/workout_formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/workout_history_grouping.dart';
import '../models/workout.dart';
import '../providers/workout_history_providers.dart';
import 'widgets/history_week_header.dart';

/// Displays paginated workout history with pull-to-refresh.
///
/// Phase 32 PR 32f redesign: replaces the flat `ListView.builder` with a
/// `CustomScrollView` that intersperses sticky [WeekHeaderDelegate]s
/// between [SliverList] bodies — one section per ISO week (Monday-start,
/// locale-aware), the most recent week first. The scroll listener and
/// `RefreshIndicator` are preserved verbatim — slivers respect the same
/// `ScrollController` API and the indicator wraps any `Scrollable`.
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
          final locale = Localizations.localeOf(context).toString();
          final groups = groupByIsoWeek(workouts, locale);

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(workoutHistoryProvider.notifier).refresh(),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                const SliverPadding(padding: EdgeInsets.only(top: 8)),
                for (final group in groups) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: WeekHeaderDelegate(
                      weekLabel: l10n.historyWeekLabel(
                        _formatWeekStart(group.weekStart, locale),
                      ),
                      rollupSetsLabel: l10n.historyWeekRollupSets(
                        group.totalSets,
                      ),
                      xpValue: group.totalXp,
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final workout = group.workouts[index];
                      return _WorkoutHistoryCard(
                        workout: workout,
                        onTap: () => context.go('/home/history/${workout.id}'),
                      );
                    }, childCount: group.workouts.length),
                  ),
                ],
                if (showLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Formats a Monday-of-week local-midnight instant as the date display
  /// used inside the localized `historyWeekLabel` ARB template (e.g.
  /// "May 20" / "20 mai"). Drops the year because the History feed never
  /// surfaces workouts old enough for the year context to matter — the
  /// most-recent-first ordering puts users near the top of their feed at
  /// open.
  String _formatWeekStart(DateTime weekStart, String locale) {
    return DateFormat.MMMd(locale).format(weekStart);
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
    final showPr = workout.prCount > 0;

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
                      // Phase 32 PR 32f eyebrow row: heroGold XP total
                      // anchors each card as a session-completed artifact.
                      // Always renders (even at 0 XP) so the vertical
                      // rhythm holds across the feed.
                      Semantics(
                        container: true,
                        explicitChildNodes: true,
                        identifier: 'history-card-xp-eyebrow',
                        child: Text(
                          l10n.historyCardXpEyebrow(workout.totalXp),
                          style: AppTextStyles.numericSmall.copyWith(
                            color: AppColors.heroGold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
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
                      // PR diamond — rendered only when prCount > 0. Per
                      // UX-critic "no empty placeholders" rule the row
                      // collapses entirely on a zero count rather than
                      // showing "0 PR". Color matches the heroGold XP
                      // eyebrow so the two reward-signal lines read as a
                      // single visual block on PR-bearing sessions.
                      if (showPr) ...[
                        const SizedBox(height: 4),
                        Semantics(
                          container: true,
                          explicitChildNodes: true,
                          identifier: 'history-card-pr-diamond',
                          child: Text(
                            l10n.historyCardPrCount(workout.prCount),
                            style: AppTextStyles.numericSmall.copyWith(
                              color: AppColors.heroGold,
                            ),
                          ),
                        ),
                      ],
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
