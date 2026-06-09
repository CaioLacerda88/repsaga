import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Quiet, tappable header affordance that surfaces the source routine's
/// training notes during an active workout (Q2).
///
/// Rendered as the FIRST item of the exercise list, ONLY when the source
/// routine has non-empty notes. For ad-hoc workouts and routines without
/// notes the list shows no strip at all — zero added chrome, identical to a
/// workout with no notes. No card / border / fill; full 48dp tap target;
/// scrolls away with the list content (not sticky chrome).
class RoutineNotesStrip extends StatelessWidget {
  const RoutineNotesStrip({required this.notes, super.key});

  /// The routine's training notes. Assumed non-empty by the caller (the strip
  /// is only inserted when notes exist).
  final String notes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      identifier: 'active-workout-routine-notes',
      label: l10n.routineNotesEyebrow,
      child: InkWell(
        onTap: () => _openSheet(context, notes),
        child: SizedBox(
          height: 48,
          child: Padding(
            // Left-aligned to the list's 16dp edge.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.routineNotesEyebrow,
                  style: AppTextStyles.label.copyWith(color: AppColors.textDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only bottom sheet showing the routine's training notes. Drag-to-dismiss,
/// no action buttons — you don't restructure the routine mid-workout.
Future<void> _openSheet(BuildContext context, String notes) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _RoutineNotesSheet(notes: notes),
  );
}

class _RoutineNotesSheet extends StatelessWidget {
  const _RoutineNotesSheet({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.4,
      minChildSize: 0.25,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDim.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.routineNotesEyebrow,
                style: AppTextStyles.label.copyWith(color: AppColors.textDim),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(
                    notes,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textCream,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
