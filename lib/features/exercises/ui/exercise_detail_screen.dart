import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/muscle_group_body_part.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/exercise_image.dart';
import '../../../shared/widgets/exercise_info_sections.dart';
import '../../personal_records/models/record_type.dart';
import '../../personal_records/providers/pr_providers.dart';
import '../../personal_records/ui/widgets/pr_type_icon.dart';
import '../../profile/providers/profile_providers.dart';
import '../models/exercise.dart';
import '../providers/exercise_providers.dart'
    show exerciseByIdProvider, exerciseListProvider, exerciseRepositoryProvider;
import 'widgets/progress_chart_section.dart';

class ExerciseDetailScreen extends ConsumerStatefulWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<ExerciseDetailScreen> createState() =>
      _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends ConsumerState<ExerciseDetailScreen> {
  bool _isDeleting = false;

  Future<void> _deleteExercise(Exercise exercise) async {
    final userId = exercise.userId;
    if (userId == null) return;

    // Capture the GoRouter before any async gap. GoRouter.of(context) reads
    // the router from the widget tree — it works as long as the widget is
    // mounted. We capture it now so we can navigate even if a later rebuild
    // makes the BuildContext stale.
    final router = GoRouter.of(context);

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: dialogTheme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(l10n.deleteExercise),
          content: Semantics(
            container: true,
            identifier: 'exercise-detail-delete-dialog',
            child: Text(l10n.deleteExerciseConfirm(exercise.name)),
          ),
          actions: [
            Semantics(
              container: true,
              identifier: 'exercise-detail-delete-cancel',
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
            ),
            Semantics(
              container: true,
              identifier: 'exercise-detail-delete-confirm',
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: dialogTheme.colorScheme.error,
                ),
                child: Text(l10n.delete),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      final repo = ref.read(exerciseRepositoryProvider);
      await repo.softDeleteExercise(exercise.id, userId: userId);

      // Navigate first, then invalidate. This ensures the route change is
      // queued before provider invalidation triggers widget rebuilds that
      // would try to re-fetch the now-deleted exercise.
      router.go('/exercises');

      // Invalidate caches so the exercise list on the destination screen
      // reflects the deletion.
      ref.invalidate(exerciseByIdProvider(exercise.id));
      ref.invalidate(exerciseListProvider);
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncExercise = ref.watch(exerciseByIdProvider(widget.exerciseId));

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'exercise-detail-title',
          child: Text(l10n.exerciseDetails),
        ),
      ),
      body: asyncExercise.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.failedToLoadExercise,
                style: AppTextStyles.body.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(exerciseByIdProvider(widget.exerciseId)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (exercise) => _ExerciseDetailBody(
          exercise: exercise,
          isDeleting: _isDeleting,
          onDelete: exercise.isDefault ? null : () => _deleteExercise(exercise),
        ),
      ),
    );
  }
}

class _ExerciseDetailBody extends ConsumerWidget {
  const _ExerciseDetailBody({
    required this.exercise,
    required this.isDeleting,
    this.onDelete,
  });

  final Exercise exercise;
  final bool isDeleting;
  final VoidCallback? onDelete;

  /// Looks up the all-time max-weight PR for [exerciseId] and returns its
  /// value. Returns `null` when the provider is loading/errored or no PR
  /// of type `maxWeight` exists — the chart gracefully falls back to the
  /// in-window peak in that case.
  double? _maxWeightPRValue(WidgetRef ref, String exerciseId) {
    final records = ref.watch(exercisePRsProvider(exerciseId)).value;
    if (records == null) return null;
    for (final r in records) {
      if (r.recordType == RecordType.maxWeight) return r.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final l10n = AppLocalizations.of(context);

    // P9 hierarchy: name -> [custom label] -> description -> chips -> images
    // -> form tips -> PRs -> delete. "Created <date>" was dropped — it was a
    // data-model leak with no user value. The custom-exercise label moves up
    // from below chips to just under the title so non-default exercises are
    // identified before users scan the content.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.name,
            style: AppTextStyles.headline.copyWith(fontSize: 28),
          ),
          if (!exercise.isDefault) ...[
            const SizedBox(height: 4),
            Semantics(
              container: true,
              identifier: 'exercise-detail-custom-badge',
              child: Text(
                l10n.customExercise,
                style: AppTextStyles.label.copyWith(
                  fontSize: 12,
                  letterSpacing: 0.12 * 12,
                  color: primary.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
          ExerciseDescriptionSection(description: exercise.description),
          // P9 review fix: only render the spacer when the section above it
          // actually rendered something. ExerciseDescriptionSection collapses
          // to SizedBox.shrink() when description is null/empty, but this
          // SizedBox(16) would still paint — leaving 16 dp of orphan
          // whitespace between the title block and the chips on most
          // user-created custom exercises.
          if (exercise.description != null &&
              exercise.description!.trim().isNotEmpty)
            const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DetailChip(
                svgIcon: exercise.muscleGroup.svgIcon,
                label: exercise.muscleGroup.localizedName(l10n),
                // Muscle-group chip carries the body-part hue on the icon
                // so the detail screen matches the list-screen `_InfoChip`
                // identity affordance (Phase 27 L18.4). Equipment chip
                // stays neutral — equipment is taxonomy, not identity.
                iconColor: exercise.muscleGroup.hueColor,
              ),
              _DetailChip(
                svgIcon: exercise.equipmentType.svgIcon,
                label: exercise.equipmentType.localizedName(l10n),
              ),
            ],
          ),
          if (exercise.imageStartUrl != null ||
              exercise.imageEndUrl != null) ...[
            const SizedBox(height: 16),
            _ExerciseImageRow(exercise: exercise),
          ],
          ExerciseFormTipsSection(formTips: exercise.formTips),
          const SizedBox(height: 24),
          _PRSection(
            exerciseId: exercise.id,
            equipmentType: exercise.equipmentType,
          ),
          const SizedBox(height: 24),
          // Thread the all-time max-weight PR into the chart. The PR
          // section above already watches `exercisePRsProvider`; watching
          // it here too is cheap (Riverpod caches by exerciseId). When
          // loading/error/absent → `null` → chart falls back to in-window
          // peak for the gold ring anchor, which is the correct behaviour
          // per acceptance #5.
          ProgressChartSection(
            exerciseId: exercise.id,
            prValue: _maxWeightPRValue(ref, exercise.id),
          ),
          if (onDelete != null) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                container: true,
                identifier: 'exercise-detail-delete-btn',
                label: l10n.deleteExerciseSemantics,
                child: OutlinedButton.icon(
                  onPressed: isDeleting ? null : onDelete,
                  icon: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text(isDeleting ? l10n.deleting : l10n.deleteExercise),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.svgIcon,
    required this.label,
    this.iconColor,
  });

  /// Inline-SVG glyph string from [AppMuscleIcons] / [AppEquipmentIcons] (or
  /// the reused [AppIcons.lift] for barbell).
  final String svgIcon;
  final String label;

  /// Optional tint for the leading icon. When `null`, falls back to the
  /// neutral `onSurface @ 75% alpha` used for taxonomy chips (equipment
  /// type). Body-part chips pass the corresponding hue from
  /// `MuscleGroup.hueColor` so the chip carries identity in the same way
  /// the list-screen `_InfoChip` does — Phase 27 L18.4.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcons.render(
            svgIcon,
            size: 18,
            color:
                iconColor ??
                theme.colorScheme.onSurface.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 6),
          // Inter 600 12dp chip register — matches the list-screen
          // `_InfoChip` exactly so the chip language reads as one design
          // across browse + detail (prior `bodyMedium + w600` rendered
          // at 14dp, breaking parity). `letterSpacing` is recomputed
          // for 12dp (`0.12 * 12 = 1.44`) — `AppTextStyles.label`'s
          // base `letterSpacing` derives from its 11dp default, so
          // copying just `fontSize` leaves tracking under-scaled.
          // Same pattern `AppTextStyles.sectionHeader` uses.
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              fontSize: 12,
              letterSpacing: 0.12 * 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseImageRow extends StatelessWidget {
  const _ExerciseImageRow({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final labelStyle = AppTextStyles.bodySmall.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );

    return SizedBox(
      height: 160,
      child: Row(
        children: [
          if (exercise.imageStartUrl != null)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _TappableImage(
                      imageUrl: exercise.imageStartUrl,
                      label: '${exercise.name} start position',
                      fallbackIcon: Icons.fitness_center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.imageStart, style: labelStyle),
                ],
              ),
            ),
          if (exercise.imageStartUrl != null && exercise.imageEndUrl != null)
            const SizedBox(width: 8),
          if (exercise.imageEndUrl != null)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _TappableImage(
                      imageUrl: exercise.imageEndUrl,
                      label: '${exercise.name} end position',
                      fallbackIcon: Icons.fitness_center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.imageEnd, style: labelStyle),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PRSection extends ConsumerWidget {
  const _PRSection({required this.exerciseId, required this.equipmentType});

  final String exerciseId;
  final EquipmentType equipmentType;

  String _formatValue(
    RecordType type,
    double value,
    String weightUnit,
    AppLocalizations l10n,
  ) {
    return switch (type) {
      RecordType.maxWeight => '$value $weightUnit',
      RecordType.maxReps => l10n.repsUnit(value.toInt()),
      RecordType.maxVolume => '$value $weightUnit',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final asyncRecords = ref.watch(exercisePRsProvider(exerciseId));
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    return asyncRecords.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, _) => _emptyPRRow(theme, l10n),
      data: (records) {
        if (records.isEmpty) return _emptyPRRow(theme, l10n);

        // For bodyweight exercises, skip maxWeight and maxVolume if absent.
        final filtered = equipmentType == EquipmentType.bodyweight
            ? records.where((r) => r.recordType == RecordType.maxReps).toList()
            : records;

        if (filtered.isEmpty) return _emptyPRRow(theme, l10n);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.personalRecords, style: AppTextStyles.sectionHeader),
            const SizedBox(height: 8),
            ...filtered.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    PRTypeIcon(
                      type: r.recordType,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.recordType.localizedName(l10n),
                      style: AppTextStyles.body,
                    ),
                    const Spacer(),
                    Text(
                      _formatValue(r.recordType, r.value, weightUnit, l10n),
                      style: AppTextStyles.numeric,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyPRRow(ThemeData theme, AppLocalizations l10n) {
    return Row(
      children: [
        Icon(
          Icons.emoji_events_rounded,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 4),
        Text(
          l10n.noRecordsYet,
          style: AppTextStyles.body.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

class _TappableImage extends StatelessWidget {
  const _TappableImage({
    required this.imageUrl,
    required this.label,
    required this.fallbackIcon,
  });

  final String? imageUrl;
  final String label;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      image: true,
      child: GestureDetector(
        onTap: imageUrl != null
            ? () => _showFullScreen(context, imageUrl!, label, fallbackIcon)
            : null,
        child: ExerciseImage(
          imageUrl: imageUrl,
          fallbackIcon: fallbackIcon,
          height: 136,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static void _showFullScreen(
    BuildContext context,
    String imageUrl,
    String label,
    IconData fallbackIcon,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final l10n = AppLocalizations.of(ctx);
        return Scaffold(
          backgroundColor: theme.colorScheme.scrim,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              tooltip: l10n.close,
            ),
          ),
          body: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Semantics(
                label: label,
                image: true,
                child: ExerciseImage(
                  imageUrl: imageUrl,
                  fallbackIcon: fallbackIcon,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
