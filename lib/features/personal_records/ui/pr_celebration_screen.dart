import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/platform_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/reward_accent.dart';
import '../../analytics/data/models/analytics_event.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../weekly_plan/providers/weekly_plan_provider.dart';
import '../../workouts/ui/widgets/add_to_plan_prompt.dart';
import '../domain/pr_detection_service.dart';
import '../models/personal_record.dart';
import '../models/record_type.dart';

/// Full-screen celebration shown after a workout with new personal records.
///
/// First workout: consolidated benchmarks message.
/// Subsequent PRs: bold "NEW PR" banner with spring-animated values.
///
/// Optionally carries plan prompt data ([planPromptRoutineId] and
/// [planPromptRoutineName]) to show an "Add to plan?" prompt when the user
/// taps Continue.
class PRCelebrationScreen extends ConsumerStatefulWidget {
  const PRCelebrationScreen({
    super.key,
    required this.result,
    required this.exerciseNames,
    this.planPromptRoutineId,
    this.planPromptRoutineName,
  });

  final PRDetectionResult result;
  final Map<String, String> exerciseNames;
  final String? planPromptRoutineId;
  final String? planPromptRoutineName;

  @override
  ConsumerState<PRCelebrationScreen> createState() =>
      _PRCelebrationScreenState();
}

class _PRCelebrationScreenState extends ConsumerState<PRCelebrationScreen>
    with SingleTickerProviderStateMixin {
  double _flashOpacity = 0.3;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Start the green flash fade-out after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _flashOpacity = 0.0);
        _scaleController.forward();
        // Second haptic pulse for extra punch.
        Future.delayed(const Duration(milliseconds: 300), () {
          HapticFeedback.mediumImpact();
        });
        _logCelebrationSeen();
      }
    });
  }

  /// Fires the `pr_celebration_seen` analytics event fire-and-forget.
  void _logCelebrationSeen() {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;
    final recordTypes = widget.result.newRecords
        .map((r) => r.recordType.toSnakeCase)
        .toList();
    unawaited(
      ref
          .read(analyticsRepositoryProvider)
          .insertEvent(
            userId: userId,
            event: AnalyticsEvent.prCelebrationSeen(
              isFirstWorkout: widget.result.isFirstWorkout,
              prCount: widget.result.newRecords.length,
              recordTypes: recordTypes,
            ),
            platform: currentPlatform(),
            appVersion: currentAppVersion(),
          ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final routineId = widget.planPromptRoutineId;
    final routineName = widget.planPromptRoutineName;

    if (routineId != null && routineName != null) {
      final shouldAdd = await showAddToPlanPrompt(
        context,
        routineName: routineName,
      );
      if (!mounted) return;
      _logAddToPlanResponse(routineId: routineId, shouldAdd: shouldAdd);
      if (shouldAdd == true) {
        await ref.read(weeklyPlanProvider.notifier).addRoutineToPlan(routineId);
      }
      if (!mounted) return;
    }
    context.go('/home');
  }

  /// Fires the `add_to_plan_prompt_responded` analytics event fire-and-forget.
  ///
  /// `shouldAdd == true`  -> `added`
  /// `shouldAdd == false` -> `skipped`
  /// `shouldAdd == null`  -> `dismissed` (user tapped outside the sheet)
  void _logAddToPlanResponse({
    required String routineId,
    required bool? shouldAdd,
  }) {
    final action = shouldAdd == true
        ? 'added'
        : shouldAdd == false
        ? 'skipped'
        : 'dismissed';
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;
    unawaited(
      ref
          .read(analyticsRepositoryProvider)
          .insertEvent(
            userId: userId,
            event: AnalyticsEvent.addToPlanPromptResponded(
              action: action,
              trigger: 'pr_celebration_continue',
              routineId: routineId,
            ),
            platform: currentPlatform(),
            appVersion: currentAppVersion(),
          ),
    );
  }

  String _formatValue(PersonalRecord record, String weightUnit) {
    return switch (record.recordType) {
      RecordType.maxWeight =>
        record.reps != null
            ? '${_formatWeight(record.value)} $weightUnit \u00d7 ${record.reps}'
            : '${_formatWeight(record.value)} $weightUnit',
      RecordType.maxReps => '${record.value.toInt()} reps',
      RecordType.maxVolume => '${_formatWeight(record.value)} $weightUnit',
    };
  }

  /// Format weight without trailing .0 (e.g. 100.0 -> "100", 72.5 -> "72.5").
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
    final theme = Theme.of(context);
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    return Scaffold(
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  if (widget.result.isFirstWorkout)
                    _buildFirstWorkoutContent(theme, weightUnit)
                  else
                    _buildPRContent(theme, weightUnit),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      container: true,
                      identifier: 'pr-continue-btn',
                      child: ElevatedButton(
                        onPressed: _onContinue,
                        child: Text(AppLocalizations.of(context).continueLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Gold PR flash per §17.0c palette spec. Reads the reward color
          // from [RewardAccent.color] (the sanctioned heroGold static) so
          // `scripts/check_reward_accent.sh` stays clean. The full-screen
          // flash is not a widget subtree we can wrap in RewardAccent (the
          // color is a raw `Container.color` value, not an icon/text), which
          // is why the static read is the right API here.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flashOpacity,
              duration: const Duration(milliseconds: 400),
              // Full-screen flash can't host a widget subtree; Container.color
              // is a raw Color parameter, so the static alias is the
              // sanctioned API per reward_accent.dart.
              // ignore: reward_accent — full-screen flash; no widget-subtree host for RewardAccent
              child: Container(color: RewardAccent.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirstWorkoutContent(ThemeData theme, String weightUnit) {
    final l10n = AppLocalizations.of(context);
    // Group records by exercise.
    final grouped = <String, List<PersonalRecord>>{};
    for (final record in widget.result.newRecords) {
      final name =
          widget.exerciseNames[record.exerciseId] ?? l10n.unknownExercise;
      (grouped[name] ??= []).add(record);
    }

    return Column(
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Icon(
            Icons.emoji_events,
            size: 72,
            color: theme.colorScheme.primary,
            shadows: [
              Shadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                blurRadius: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          identifier: 'pr-first-workout',
          child: Text(
            l10n.firstWorkoutComplete,
            style: theme.textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.startingBenchmarks,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ...grouped.entries.map(
          (entry) => _ExerciseRecordGroup(
            exerciseName: entry.key,
            records: entry.value,
            formatValue: (r) => _formatValue(r, weightUnit),
            iconForType: _iconForType,
          ),
        ),
      ],
    );
  }

  Widget _buildPRContent(ThemeData theme, String weightUnit) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Semantics(
            container: true,
            identifier: 'pr-new-heading',
            child: Text(
              l10n.newPrHeading,
              // Phase 28a forbid-w900 gate: dropped `fontWeight: w900`.
              // displayMedium is already Rajdhani 700 (the heaviest weight
              // bundled in pubspec.yaml > flutter.fonts); w900 was a silent
              // nearest-match to w700 at runtime.
              style: theme.textTheme.displayMedium?.copyWith(
                color: theme.colorScheme.primary,
                shadows: [
                  Shadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...widget.result.newRecords.map((record) {
          final name =
              widget.exerciseNames[record.exerciseId] ?? l10n.unknownExercise;
          return _AnimatedRecordCard(
            exerciseName: name,
            record: record,
            formattedValue: _formatValue(record, weightUnit),
            icon: _iconForType(record.recordType),
          );
        }),
      ],
    );
  }
}

class _ExerciseRecordGroup extends StatelessWidget {
  const _ExerciseRecordGroup({
    required this.exerciseName,
    required this.records,
    required this.formatValue,
    required this.iconForType,
  });

  final String exerciseName;
  final List<PersonalRecord> records;
  final String Function(PersonalRecord) formatValue;
  final IconData Function(RecordType) iconForType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exerciseName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ...records.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      iconForType(r.recordType),
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.recordType.localizedName(AppLocalizations.of(context)),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    Text(
                      formatValue(r),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedRecordCard extends StatelessWidget {
  const _AnimatedRecordCard({
    required this.exerciseName,
    required this.record,
    required this.formattedValue,
    required this.icon,
  });

  final String exerciseName;
  final PersonalRecord record;
  final String formattedValue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exerciseName, style: theme.textTheme.titleMedium),
                  Text(
                    record.recordType.localizedName(
                      AppLocalizations.of(context),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Text(
                formattedValue,
                // Phase 28a: the PR value is numeric data, so the canonical
                // token is `AppTextStyles.numeric` (Rajdhani 700 with tabular
                // figures) rather than the `headline` text register. 24sp
                // sizes it as a headline-tier emphasis; w900 was a silent
                // nearest-match to w700 against the bundled Rajdhani assets
                // (see `scripts/check_typography_call_sites.sh` gate 3).
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 24,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
