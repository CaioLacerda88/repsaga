import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../models/record_type.dart';
import '../providers/pr_providers.dart';

/// Displays all personal records grouped by exercise.
class PRListScreen extends ConsumerWidget {
  const PRListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPRs = ref.watch(prListWithExercisesProvider);

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'pr-display-title',
          child: Text(l10n.personalRecordsTitle),
        ),
      ),
      body: asyncPRs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            l10n.failedToLoadRecords,
            style: AppTextStyles.body.copyWith(fontSize: 16),
          ),
        ),
        data: (records) {
          if (records.isEmpty) return _EmptyState();
          return _RecordsList(records: records);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
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
              Icons.emoji_events,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              identifier: 'pr-display-empty-title',
              child: Text(
                l10n.noRecordsYetTitle,
                style: AppTextStyles.headline,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              container: true,
              identifier: 'pr-display-empty',
              child: Text(
                l10n.completeWorkoutToTrack,
                style: AppTextStyles.body.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: Text(l10n.startWorkout),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsList extends ConsumerWidget {
  const _RecordsList({required this.records});

  final List<PRWithExercise> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hoist the weightUnit read here so each card does not independently
    // watch profileProvider.
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    // Group by exerciseId.
    final grouped = <String, List<PRWithExercise>>{};
    for (final pr in records) {
      (grouped[pr.record.exerciseId] ??= []).add(pr);
    }

    final exerciseIds = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      itemCount: exerciseIds.length,
      itemBuilder: (context, index) {
        final exerciseRecords = grouped[exerciseIds[index]]!;
        return _ExerciseRecordCard(
          records: exerciseRecords,
          weightUnit: weightUnit,
        );
      },
    );
  }
}

class _ExerciseRecordCard extends StatelessWidget {
  const _ExerciseRecordCard({required this.records, required this.weightUnit});

  final List<PRWithExercise> records;
  final String weightUnit;

  String _formatValue(
    RecordType type,
    double value,
    String weightUnit, {
    int? reps,
  }) {
    return switch (type) {
      RecordType.maxWeight =>
        reps != null
            ? '${_formatWeight(value)} $weightUnit \u00d7 $reps'
            : '${_formatWeight(value)} $weightUnit',
      RecordType.maxReps => '${value.toInt()} reps',
      RecordType.maxVolume => '${_formatWeight(value)} $weightUnit',
    };
  }

  /// Format weight without trailing .0 (e.g. 100.0 → "100", 72.5 → "72.5").
  String _formatWeight(double value) {
    return value == value.roundToDouble() && value.truncateToDouble() == value
        ? value.toInt().toString()
        : value.toString();
  }

  IconData _iconForType(RecordType type) {
    return switch (type) {
      RecordType.maxWeight => Icons.fitness_center,
      RecordType.maxReps => Icons.repeat,
      RecordType.maxVolume => Icons.bar_chart,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final first = records.first;

    return Semantics(
      container: true,
      identifier: 'pr-exercise-card',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusLg),
          onTap: () => context.go('/exercises/${first.record.exerciseId}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.exerciseName,
                  style: AppTextStyles.title.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: records.map((pr) {
                    return _RecordTile(
                      icon: _iconForType(pr.record.recordType),
                      label: pr.record.recordType.localizedName(l10n),
                      value: _formatValue(
                        pr.record.recordType,
                        pr.record.value,
                        weightUnit,
                        reps: pr.record.reps,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            identifier:
                'pr-display-${label.toLowerCase().replaceAll(' ', '-')}',
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // PR value — Rajdhani 700 tabular (numeric register).
          Text(value, style: AppTextStyles.numeric.copyWith(fontSize: 16)),
        ],
      ),
    );
  }
}
