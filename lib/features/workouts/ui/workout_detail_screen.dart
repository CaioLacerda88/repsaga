import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/number_format.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/workout_formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/reward_accent.dart';
import '../../personal_records/providers/pr_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../data/workout_repository.dart';
import '../models/exercise_set.dart';
import '../models/set_type.dart';
import '../models/workout_exercise.dart';
import '../providers/workout_history_providers.dart';

/// Read-only detail view of a completed workout.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({required this.workoutId, super.key});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDetail = ref.watch(workoutDetailProvider(workoutId));

    final l10n = AppLocalizations.of(context);
    return asyncDetail.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.workout)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.failedToLoadWorkout, style: AppTextStyles.title),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(workoutDetailProvider(workoutId)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
      data: (detail) => Scaffold(body: _WorkoutDetailBody(detail: detail)),
    );
  }
}

class _WorkoutDetailBody extends ConsumerWidget {
  const _WorkoutDetailBody({required this.detail});

  final WorkoutDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final workout = detail.workout;
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';
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

    // Calculate total volume across all exercises.
    final allSets = detail.setsByExercise.values.expand((s) => s).toList();
    final totalVolume = WorkoutFormatters.calculateVolume(allSets);

    // PR count comes from `workout.prCount` (set by the `get_workout_xp`
    // RPC during the detail fetch) — single source of truth shared with
    // the History feed's per-card diamond, so the two surfaces never
    // disagree on the value. The gold-ring on individual set rows still
    // uses `workoutPRSetIdsProvider` for which-set-was-the-PR resolution,
    // but the aggregate count for the strip reads from the workout model
    // directly. See PR #285 Important 8.
    final prCount = workout.prCount;

    // Hide the strip when both aggregates are zero — a "+0 XP · 0 PRs"
    // line on an incomplete or warm-up-only session reads as negative
    // confirmation, not steady-state rhythm. See PR #285 Important 7.
    final showStrip = workout.totalXp > 0 || prCount > 0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(workout.name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$dateText  ·  $durationText',
                style: AppTextStyles.body.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
        // 48dp summary strip — `surface2` background sits flush against the
        // AppBar's bottom edge. Color split via Text.rich: XP digits in
        // `hotViolet` (daily-driver register), PR digits routed through
        // RewardAccent (heroGold scarcity register). Hidden entirely when
        // the session produced neither XP nor PRs. See PR #285 Important 7.
        if (showStrip)
          SliverToBoxAdapter(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              identifier: 'history-detail-strip',
              child: Container(
                height: 48,
                color: AppColors.surface2,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: l10n.historyDetailStripXpPart(workout.totalXp),
                        style: AppTextStyles.numericSmall.copyWith(
                          color: AppColors.hotViolet.withValues(alpha: 0.85),
                        ),
                      ),
                      if (prCount > 0) ...[
                        TextSpan(
                          text: ' · ',
                          style: AppTextStyles.numericSmall.copyWith(
                            color: AppColors.textDim.withValues(alpha: 0.5),
                          ),
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: RewardAccent(
                            child: Text(
                              l10n.historyDetailStripPrPart(prCount),
                              style: AppTextStyles.numericSmall,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Exercise cards
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final exercise = detail.exercises[index];
            final sets = detail.setsByExercise[exercise.id] ?? [];
            return _ReadOnlyExerciseCard(
              exercise: exercise,
              sets: sets,
              workoutId: detail.workout.id,
              weightUnit: weightUnit,
            );
          }, childCount: detail.exercises.length),
        ),
        // Notes section
        if (workout.notes != null && workout.notes!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.notes, style: AppTextStyles.title),
                      const SizedBox(height: 8),
                      Text(
                        workout.notes!,
                        style: AppTextStyles.body.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Total volume footer
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fitness_center,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.totalVolume(
                    WorkoutFormatters.formatVolume(
                      totalVolume,
                      weightUnit: weightUnit,
                      locale: locale,
                    ),
                  ),
                  style: AppTextStyles.title.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyExerciseCard extends ConsumerWidget {
  const _ReadOnlyExerciseCard({
    required this.exercise,
    required this.sets,
    required this.workoutId,
    required this.weightUnit,
  });

  final WorkoutExercise exercise;
  final List<ExerciseSet> sets;
  final String workoutId;
  final String weightUnit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final prSetIds = ref.watch(workoutPRSetIdsProvider(workoutId)).value ?? {};

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise.exercise?.name ?? l10n.exerciseGeneric,
              style: AppTextStyles.title,
            ),
            if (sets.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Column headers
              _SetColumnHeaders(theme: theme),
              const Divider(height: 1),
              ...sets.map(
                (s) => _ReadOnlySetRow(
                  set: s,
                  isPR: prSetIds.contains(s.id),
                  weightUnit: weightUnit,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetColumnHeaders extends StatelessWidget {
  const _SetColumnHeaders({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Data-table eyebrow: 11dp tracked label. Drop tracking very slightly
    // (0.6 vs the default 0.12em) — see _SetColumnHeaders in
    // `exercise_card.dart` for the same kerning constraint at 360dp.
    final style = AppTextStyles.label.copyWith(
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(l10n.setColumnSet, style: style)),
          Expanded(
            child: Text(
              l10n.setColumnWeight,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              l10n.setColumnReps,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              l10n.setColumnType,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlySetRow extends StatelessWidget {
  const _ReadOnlySetRow({
    required this.set,
    required this.weightUnit,
    this.isPR = false,
  });

  final ExerciseSet set;
  final bool isPR;
  final String weightUnit;

  String _typeLabel(AppLocalizations l10n) => switch (set.setType) {
    SetType.working => l10n.setTypeAbbrWorking,
    SetType.warmup => l10n.setTypeAbbrWarmupShort,
    SetType.dropset => l10n.setTypeAbbrDropset,
    SetType.failure => l10n.setTypeAbbrFailure,
  };

  Color _typeColor(ThemeData theme) => switch (set.setType) {
    SetType.working => theme.colorScheme.primary,
    SetType.warmup => theme.colorScheme.secondary,
    SetType.dropset => theme.colorScheme.tertiary,
    SetType.failure => theme.colorScheme.error,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Set-number cell — Inter body register (set number used as label, not
    // as a glanced-at performance datum here since the row reads as a list
    // entry, not a live stepper). Weight + reps cells route to the numeric
    // (Rajdhani 700 tabular) register so the column reads as data.
    final labelStyle = AppTextStyles.body;
    final dataStyle = AppTextStyles.numeric.copyWith(fontSize: 14);
    final locale = Localizations.localeOf(context).languageCode;
    final weightText = set.weight == null
        ? '- $weightUnit'
        : AppNumberFormat.weightWithUnit(
            set.weight!,
            locale: locale,
            unit: weightUnit,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: isPR
                ? RewardAccent(
                    child: AppIcons.render(AppIcons.levelUp, size: 18),
                  )
                : Text(
                    '${set.setNumber}.',
                    style: labelStyle.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              weightText,
              style: dataStyle,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '${set.reps ?? '-'}',
              style: dataStyle,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 48,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _typeColor(theme).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _typeLabel(AppLocalizations.of(context)),
                  style: AppTextStyles.label.copyWith(
                    color: _typeColor(theme),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
