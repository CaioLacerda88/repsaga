import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/workout_formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/reward_accent.dart';
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
    final hasMore = ref.read(workoutHistoryProvider).value?.hasMore ?? false;
    if (!hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Load more when within 200px of the bottom.
    if (currentScroll >= maxScroll - 200) {
      ref.read(workoutHistoryProvider.notifier).loadMore();
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
        data: (historyState) {
          final workouts = historyState.workouts;
          if (workouts.isEmpty) {
            return _EmptyHistoryBody(onStartWorkout: () => context.go('/home'));
          }

          // Reactively derived from the emitted state class so the load-more
          // spinner reflects flag transitions without a separate ref.read.
          // See PR #285 Blocker 2.
          final showLoadingMore =
              historyState.isLoadingMore || historyState.hasMore;
          final locale = Localizations.localeOf(context).toString();
          // Per-workout set count comes from `Workout.setCount`, populated
          // by the `get_workout_history_with_aggregates` RPC's `set_count`
          // aggregate. Plumbing it through `setCountFor` is what makes the
          // week-header roll-up render real numbers in production instead
          // of always-zero. See PR #285 Nit 16.
          final groups = groupByIsoWeek(
            workouts,
            locale,
            setCountFor: (w) => w.setCount,
          );
          // Current-ISO-week Monday-anchor for the "This Week" header
          // treatment. Read via `package:clock` so tests can pin a
          // deterministic now via `withClock(Clock.fixed(...), ...)` —
          // same pattern as `streakProvider`.
          final currentWeekStart = _mondayOfWeek(clock.now().toLocal());

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
                      weekLabel: group.weekStart == currentWeekStart
                          ? l10n.historyWeekLabelCurrent
                          : l10n.historyWeekLabel(
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

  /// Returns the Monday-at-00:00 local instant for the week containing
  /// [date]. Pure-copy of `workout_history_grouping.dart`'s same helper
  /// so the screen's "is this group the current ISO week?" check
  /// computes the exact same anchor the grouping function used — the two
  /// values are compared by equality, so divergence in either would
  /// silently break the "This Week" label.
  DateTime _mondayOfWeek(DateTime date) {
    final daysSinceMonday = date.weekday - 1;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: daysSinceMonday));
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
                      // XP eyebrow — `hotViolet` (daily-driver progress
                      // register), NOT `heroGold` (reserved for variable-
                      // ratio rewards via RewardAccent). The eyebrow
                      // renders on every card in the feed, so painting it
                      // gold would erode the reward-scarcity contract that
                      // `scripts/check_reward_accent.sh` enforces. See PR
                      // #285 UX-critic memo (Blocker 4) — XP is an expected
                      // outcome of every workout, mapping it to the
                      // structural-accent color keeps the gold signal rare.
                      Semantics(
                        container: true,
                        explicitChildNodes: true,
                        identifier: 'history-card-xp-eyebrow',
                        child: Text(
                          l10n.historyCardXpEyebrow(workout.totalXp),
                          style: AppTextStyles.numericSmall.copyWith(
                            color: AppColors.hotViolet.withValues(alpha: 0.85),
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
                      // PR diamond — rendered only when prCount > 0 (UX
                      // "no empty placeholders" rule). Wrapped in
                      // `RewardAccent` so the heroGold color is emitted
                      // through the sanctioned scope rather than a raw
                      // `AppColors.heroGold` reference — this keeps the
                      // reward-scarcity contract auditable
                      // (`scripts/check_reward_accent.sh`) and visually
                      // separates the PR signal from the violet XP
                      // eyebrow. See PR #285 UX-critic memo (Blocker 5).
                      if (showPr) ...[
                        const SizedBox(height: 4),
                        Semantics(
                          container: true,
                          explicitChildNodes: true,
                          identifier: 'history-card-pr-diamond',
                          child: RewardAccent(
                            child: Text(
                              l10n.historyCardPrCount(workout.prCount),
                              // Compose an inheriting TextStyle WITHOUT a
                              // color — `numericSmall` bakes `color:
                              // AppColors.textDim` which would override
                              // RewardAccent's heroGold via
                              // `DefaultTextStyle.merge`'s explicit-wins
                              // semantics. Omitting `color:` lets the
                              // ambient `DefaultTextStyle` (heroGold from
                              // RewardAccent) win. See PR #285 device-
                              // verification finding and Fix 2 in the
                              // workout_detail_screen pair.
                              style: const TextStyle(
                                fontFamily: 'Rajdhani',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                letterSpacing: 0.04 * 11,
                                height: 1.4,
                              ),
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
