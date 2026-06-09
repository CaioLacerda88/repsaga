import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/number_format.dart';
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
import 'widgets/notes_edit_sheet.dart';

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
                          // Align the WidgetSpan to the surrounding text's
                          // alphabetic baseline so the gold "PRs" digits sit
                          // on the same line as the violet "XP" digits.
                          // `PlaceholderAlignment.middle` (the prior anchor)
                          // mid-centers the child against the line's x-height,
                          // which Rajdhani's tall ascenders push visibly
                          // upward on a real device — caught during PR #285
                          // physical-Android verification.
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: RewardAccent(
                            child: Text(
                              l10n.historyDetailStripPrPart(prCount),
                              // `numericSmallInheriting` is the no-baked-
                              // color sibling of `numericSmall` — see the
                              // token's docstring for why bare
                              // `numericSmall` would override RewardAccent's
                              // heroGold via `Text.style.merge`. Caught in
                              // PR #285 device verification.
                              style: AppTextStyles.numericSmallInheriting,
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
        // Notes section — Q1 (notes-edit-after). Flat layout (no Card chrome),
        // editable in place. Empty → quiet "add note" affordance; present →
        // tappable text. Tapping opens the NotesEditSheet (multiline, 2000-char
        // cap, Save/Cancel) and persists via workoutNotesNotifierProvider.
        SliverToBoxAdapter(
          child: _NotesSection(workoutId: workout.id, notes: workout.notes),
        ),
        // 48dp total-volume strip — mirrors the top XP/PRs strip (lines
        // ~120-160 above) so the screen reads as two anchor bands around
        // the exercise list rather than a free-floating Material icon
        // footnote. `Text.rich` splits the eyebrow label (Barlow
        // Condensed tracked, textDim alpha 0.6) from the numeric value
        // (Rajdhani 700 tabular, textCream) so the value half reads as
        // the load-bearing data point in the same numeric register the
        // top strip's XP/PR spans use. See PR #285 UX-critic memo (Q2).
        SliverToBoxAdapter(
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: 'workout-detail-total-volume-strip',
            child: Container(
              height: 48,
              color: AppColors.surface2,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: l10n.workoutDetailTotalVolumeLabel,
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.textDim.withValues(alpha: 0.6),
                      ),
                    ),
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: l10n.workoutDetailTotalVolumeValue(
                        WorkoutFormatters.formatVolume(
                          totalVolume,
                          weightUnit: weightUnit,
                          locale: locale,
                        ),
                      ),
                      style: AppTextStyles.numeric.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Flat, editable notes section on the workout-detail screen (Q1).
///
/// Renders an eyebrow label (`l10n.notes`, Barlow-Condensed tracked) over
/// either the note body (tappable) or — when empty — a quiet
/// `Icons.edit_note` + `l10n.addNote` affordance. Tapping opens
/// [NotesEditSheet]; saving persists through [workoutNotesNotifierProvider]
/// and the detail provider invalidation re-renders the new value.
class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.workoutId, required this.notes});

  final String workoutId;
  final String? notes;

  bool get _hasNote => notes != null && notes!.isNotEmpty;

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final result = await NotesEditSheet.show(
      context,
      initialNotes: notes,
      title: l10n.notes,
      // Evocative in-field prompt — distinct from the `addNote` affordance
      // label so the empty field invites reflection rather than echoing the
      // button the user just tapped.
      hintText: l10n.addNotesHint,
      saveLabel: l10n.save,
      cancelLabel: l10n.cancel,
      counterFormatter: l10n.notesCharCounter,
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failedMessage = l10n.failedToSaveWorkout;
    try {
      await ref
          .read(workoutNotesNotifierProvider.notifier)
          .save(workoutId, result.notes);
    } on Object {
      // The notifier rethrows the domain exception on a failed write; the
      // detail provider is NOT invalidated in that case, so the prior note
      // stays rendered. Surface a snackbar so the edit isn't silently lost.
      messenger.showSnackBar(SnackBar(content: Text(failedMessage)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'workout-detail-notes',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.notes.toUpperCase(),
              // Same eyebrow register as the NotesEditSheet title — plain
              // AppColors.textDim (no extra alpha) so the section header and
              // the editor header read identically.
              style: AppTextStyles.label.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _openEditor(context, ref),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _hasNote
                    ? Text(
                        notes!,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textCream.withValues(alpha: 0.85),
                        ),
                      )
                    // Empty-state affordance floored at the 48dp tap-target
                    // minimum (the icon + label row alone is ~28dp).
                    : ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.edit_note,
                                size: 16,
                                color: AppColors.textDim,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.addNote,
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
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
                // Gold diamond glyph — matches the per-card PR diamond
                // pattern on the History feed (`history-card-pr-diamond`).
                // Replaces the previous `AppIcons.levelUp` SVG which
                // semantically belongs to the level-up / XP ceremony
                // register (`saga_intro_overlay.dart`) and bled into the
                // PR register here. The set number on PR rows is implicit
                // from row position so the slot stays at 40dp without a
                // numeric prefix. See PR #285 UX-critic memo (Q1).
                ? RewardAccent(
                    child: Text(
                      '◆',
                      // `numericSmallInheriting` is the no-baked-color
                      // sibling of `numericSmall` — see the token's
                      // docstring for the rationale; same fix pattern as
                      // the card PR diamond + detail-strip PR span.
                      // Outer `const` dropped because the getter call
                      // isn't a compile-time constant.
                      style: AppTextStyles.numericSmallInheriting,
                    ),
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
