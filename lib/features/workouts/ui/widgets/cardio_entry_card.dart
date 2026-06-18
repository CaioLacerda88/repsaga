import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../models/active_workout_state.dart';
import '../../models/cardio_session.dart';
import '../../providers/workout_providers.dart';
import '../../utils/cardio_format.dart';
import 'cardio_field.dart';
import 'cardio_target_dialogs.dart';
import 'duration_stepper.dart';
import 'exercise_card.dart';
import 'exercise_card_header.dart';
import 'exercise_picker_sheet.dart';

/// Card representing one CARDIO entry inside an active workout (Phase 38b).
///
/// Same shell as the strength [ExerciseCard] — Card surface, hair border,
/// [ExerciseCardHeader] — but its own grammar per the locked
/// `docs/phase-38-mockups.html`:
///
///   * a 3dp teal stripe on the card's left edge (the at-a-glance "this is
///     cardio" cue; strength cards have no stripe),
///   * an `<ACTIVITY> · CARDIO` eyebrow in the teal-dim label register,
///   * a [DurationStepper] hero (the ONLY mandatory input),
///   * optional distance (tap-to-type — the value range is too wide for a
///     stepper) and RPE (1–10 picked via a 48dp-floor bottom sheet; the
///     inline pips are display-only) that *invite* with `+ adicionar`,
///     never nag with `0.0 km`,
///   * a "Concluir cardio" CTA. Completing fires a medium haptic and
///     collapses the body to a one-line dim summary with a green ✓ in the
///     header trailing slot. NO rest timer — cardio has no inter-set rest.
///
/// Cardio entries earn nothing yet: the 00077 save gate excludes cardio
/// from the strength XP path and the cardio earning function is Phase 38c.
/// This card only edits `ActiveWorkoutExercise.cardioSession`; persistence
/// happens at finish time via `save_workout`'s `p_cardio` array.
class CardioEntryCard extends ConsumerWidget {
  const CardioEntryCard({
    required this.activeExercise,
    required this.reorderMode,
    required this.isFirst,
    required this.isLast,
    super.key,
  });

  final ActiveWorkoutExercise activeExercise;
  final bool reorderMode;
  final bool isFirst;
  final bool isLast;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final l10n = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          title: Text(l10n.removeExerciseTitle),
          content: Text(
            l10n.removeExerciseContent(
              activeExercise.workoutExercise.exercise?.name ?? '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: dialogTextButtonStyle,
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: dialogTextButtonStyle.copyWith(
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(dialogCtx).colorScheme.error,
                ),
              ),
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref
          .read(activeWorkoutProvider.notifier)
          .removeExercise(activeExercise.workoutExercise.id);
    }
  }

  /// Swap via the picker. Unlike the strength card there is no
  /// completed-set re-attribution to warn about: cardio→cardio carries the
  /// in-progress entry over to the new activity, and cross-modality resets
  /// are the notifier's `swapExercise` contract — so the swap is silent.
  Future<void> _swapExercise(BuildContext context, WidgetRef ref) async {
    final newExercise = await ExercisePickerSheet.show(context);
    if (newExercise == null) return;
    await ref
        .read(activeWorkoutProvider.notifier)
        .swapExercise(activeExercise.workoutExercise.id, newExercise);
  }

  void _complete(WidgetRef ref) {
    // Mirrors SetRow's completion feedback. Deliberately NO rest-timer
    // start — cardio is a continuous effort, not an interval between sets.
    HapticFeedback.mediumImpact();
    ref
        .read(activeWorkoutProvider.notifier)
        .completeCardioEntry(activeExercise.workoutExercise.id);
  }

  void _uncomplete(WidgetRef ref) {
    ref
        .read(activeWorkoutProvider.notifier)
        .completeCardioEntry(activeExercise.workoutExercise.id);
  }

  Future<void> _editDistance(
    BuildContext context,
    WidgetRef ref,
    CardioSession session,
    String distanceUnit,
    String locale,
  ) async {
    final meters = await showCardioDistanceDialog(
      context,
      initialMeters: session.distanceM,
      distanceUnit: distanceUnit,
      locale: locale,
    );
    if (meters == null) return;
    await ref
        .read(activeWorkoutProvider.notifier)
        .updateCardioSession(
          activeExercise.workoutExercise.id,
          distanceM: meters,
        );
  }

  Future<void> _editRpe(
    BuildContext context,
    WidgetRef ref,
    CardioSession session,
  ) async {
    final picked = await _RpePickerSheet.show(context, selected: session.rpe);
    if (picked == null) return;
    await ref
        .read(activeWorkoutProvider.notifier)
        .updateCardioSession(activeExercise.workoutExercise.id, rpe: picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final exercise = activeExercise.workoutExercise.exercise;
    final session = activeExercise.cardioSession;
    // Defensive: the ExerciseList only routes here for cardio entries, and
    // the notifier always seeds a session for those — but a malformed
    // crash-recovery payload must degrade to nothing, not crash the list.
    if (session == null) return const SizedBox.shrink();

    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';
    final distanceUnit = CardioFormat.distanceUnitFor(weightUnit);
    final completed = session.isCompleted;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 3dp teal identity stripe — card-level cardio marker (locked
          // mockup: `.card.cardio::before`). Persists in the completed
          // state; strength cards never render one.
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 3,
                child: ColoredBox(color: AppColors.bodyPartCardio),
              ),
            ),
          ),
          Padding(
            // Mirrors ExerciseCard's 10/16 chrome, +3 left for the stripe.
            padding: const EdgeInsets.fromLTRB(13, 16, 10, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExerciseCardHeader(
                  exercise: exercise,
                  workoutExerciseId: activeExercise.workoutExercise.id,
                  reorderMode: reorderMode,
                  isFirst: isFirst,
                  isLast: isLast,
                  onShowDetail: ExerciseDetailSheet.show,
                  onSwap: (ctx) => _swapExercise(ctx, ref),
                  onConfirmRemove: (ctx) => _confirmRemove(ctx, ref),
                  // Completed: the action cluster collapses to the green ✓
                  // (app-wide done semantics); tapping re-opens for edits.
                  // In reorderMode the ✓ must yield to the up/down arrows —
                  // `trailing` REPLACES the action cluster in the header, so
                  // passing it here would hide the reorder affordance and a
                  // completed cardio card could never be moved (a cardio-only
                  // regression; strength cards have no trailing).
                  trailing: completed && !reorderMode
                      ? Semantics(
                          container: true,
                          explicitChildNodes: true,
                          identifier: 'cardio-uncomplete',
                          label: l10n.cardioUncompleteSemantics,
                          child: IconButton(
                            onPressed: () => _uncomplete(ref),
                            icon: const Icon(
                              Icons.check,
                              color: AppColors.success,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            tooltip: l10n.cardioUncompleteSemantics,
                          ),
                        )
                      : null,
                ),
                CardioEyebrow(slug: exercise?.slug),
                if (completed)
                  _CompletedSummary(
                    session: session,
                    distanceUnit: distanceUnit,
                    locale: locale,
                  )
                else ...[
                  const SizedBox(height: 10),
                  DurationStepper(
                    value: session.durationSeconds,
                    onChanged: (seconds) => ref
                        .read(activeWorkoutProvider.notifier)
                        .updateCardioSession(
                          activeExercise.workoutExercise.id,
                          durationSeconds: seconds,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: CardioField(
                          identifier: 'cardio-distance',
                          semanticsLabel: l10n.cardioDistanceSemantics,
                          label: l10n.cardioDistanceLabel,
                          onTap: () => _editDistance(
                            context,
                            ref,
                            session,
                            distanceUnit,
                            locale,
                          ),
                          child: session.distanceM == null
                              ? GhostValue(text: l10n.cardioAddValue)
                              : Text.rich(
                                  TextSpan(
                                    text: CardioFormat.distanceValue(
                                      session.distanceM!,
                                      distanceUnit: distanceUnit,
                                      locale: locale,
                                    ),
                                    style: AppTextStyles.numeric.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: ' $distanceUnit',
                                        style: AppTextStyles.label.copyWith(
                                          color: AppColors.textDim,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CardioField(
                          identifier: 'cardio-rpe',
                          semanticsLabel: l10n.cardioEffortSemantics,
                          label: session.rpe == null
                              ? l10n.cardioEffortLabel
                              : l10n.cardioEffortShortLabel,
                          onTap: () => _editRpe(context, ref, session),
                          child: session.rpe == null
                              ? GhostValue(text: l10n.cardioAddValue)
                              : _RpePips(value: session.rpe!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Done CTA — same 48dp geometry as the strength card's
                  // Add Set button, in the cardio identity hue.
                  Semantics(
                    container: true,
                    explicitChildNodes: true,
                    identifier: 'cardio-complete',
                    child: OutlinedButton.icon(
                      onPressed: session.durationSeconds > 0
                          ? () => _complete(ref)
                          : null,
                      icon: const Icon(Icons.check, size: 20),
                      label: Text(l10n.completeCardio),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: AppColors.bodyPartCardio,
                        backgroundColor: AppColors.bodyPartCardio.withValues(
                          alpha: 0.12,
                        ),
                        side: BorderSide(
                          color: AppColors.bodyPartCardio.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed one-line summary for the completed state — dim Rajdhani
/// numerals, optional segments only when their value exists:
/// `28:45 min · 5.2 km · esforço 7/10`.
class _CompletedSummary extends StatelessWidget {
  const _CompletedSummary({
    required this.session,
    required this.distanceUnit,
    required this.locale,
  });

  final CardioSession session;
  final String distanceUnit;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final segments = <String>[
      l10n.cardioSummaryDuration(
        CardioFormat.duration(session.durationSeconds),
      ),
      if (session.distanceM != null)
        '${CardioFormat.distanceValue(session.distanceM!, distanceUnit: distanceUnit, locale: locale)} $distanceUnit',
      if (session.rpe != null) l10n.cardioSummaryEffort(session.rpe!),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        // scaleDown keeps the one-line summary from overflowing on 320dp
        // when all three segments are present (`28:45 min · 5.2 km ·
        // effort 7/10`); look is unchanged on 360/412dp where it fits.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            segments.join(' · '),
            textAlign: TextAlign.center,
            style: AppTextStyles.numeric.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Display-only 1–10 pip row reflecting the picked RPE. Sub-48dp by design
/// — precise picking routes through [_RpePickerSheet] (locked mockup:
/// "inline pips are display-only").
class _RpePips extends StatelessWidget {
  const _RpePips({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    // The 10-pip row is ~146dp (10×11dp + 9×4dp) but the RPE field is only
    // ~half the card width — ~140dp at 320dp. scaleDown shrinks the row to
    // fit the field instead of overflowing; it's a no-op on 360/412dp where
    // the row already fits, so the look is unchanged on those widths.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 10; i++) ...[
            if (i > 1) const SizedBox(width: 4),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= value ? AppColors.bodyPartCardio : null,
                border: Border.all(
                  color: i <= value ? AppColors.bodyPartCardio : AppColors.hair,
                  width: 1.5,
                ),
              ),
              child: const SizedBox(width: 11, height: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet picker for RPE 1–10. Every option is a ≥48dp tap target
/// (feedback: tap-target-measurement) laid out 5-per-row so the sheet stays
/// short on 320dp screens. Pops with the picked int, or null on dismiss.
class _RpePickerSheet extends StatelessWidget {
  const _RpePickerSheet({required this.selected});

  final int? selected;

  static Future<int?> show(BuildContext context, {int? selected}) {
    return showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (_) => _RpePickerSheet(selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.rpeSheetTitle, style: AppTextStyles.headline),
          const SizedBox(height: 4),
          Text(l10n.rpeSheetSubtitle, style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // 5 options per row with 8dp gaps; each option spans the
              // available width so the tap target never drops below the
              // 48dp floor even at 320dp.
              final optionWidth = (constraints.maxWidth - 4 * 8) / 5;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var value = 1; value <= 10; value++)
                    _RpeOption(
                      value: value,
                      width: optionWidth,
                      isSelected: value == selected,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RpeOption extends StatelessWidget {
  const _RpeOption({
    required this.value,
    required this.width,
    required this.isSelected,
  });

  final int value;
  final double width;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'cardio-rpe-option-$value',
      label: l10n.rpeOptionSemantics(value),
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected
            ? AppColors.bodyPartCardio.withValues(alpha: 0.18)
            : AppColors.surface2,
        borderRadius: BorderRadius.circular(kRadiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSm),
          onTap: () => Navigator.of(context).pop(value),
          child: Container(
            width: width,
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border.all(
                color: isSelected ? AppColors.bodyPartCardio : AppColors.hair,
              ),
            ),
            child: ExcludeSemantics(
              child: Text(
                '$value',
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 18,
                  color: isSelected
                      ? AppColors.bodyPartCardio
                      : AppColors.textCream,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
