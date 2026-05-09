import 'package:flutter/material.dart';

import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
import '../../routines/models/routine.dart';

/// Result type returned by [showModalBottomSheet] when the user dismisses
/// the [AddRoutinesSheet].
///
/// Two outcomes:
///   * [AddRoutinesSheetResultSelected] — user confirmed a non-empty
///     selection. The parent screen adds these routines to the bucket.
///   * [AddRoutinesSheetResultCreateNew] — user tapped the "Create new
///     routine" affordance (either the bottom action row OR the empty-
///     state button). The parent pops the sheet, navigates to the
///     routine-creation flow, and re-opens the sheet on return with the
///     newly-created routine pre-selected.
///
/// Modeled as a sealed class (Dart 3) so the parent's `switch` is
/// exhaustive — a future third outcome would force every call site to
/// update.
sealed class AddRoutinesSheetResult {
  const AddRoutinesSheetResult();
}

/// User confirmed a non-empty selection via the "ADD N ROUTINES" button.
class AddRoutinesSheetResultSelected extends AddRoutinesSheetResult {
  const AddRoutinesSheetResultSelected(this.routines);

  final List<Routine> routines;
}

/// User tapped the "Create new routine" affordance. The parent should
/// pop the sheet, navigate to the routine-creation flow, then re-invoke
/// `_showAddSheet` with the new routine's id in `preSelectedRoutineIds`.
class AddRoutinesSheetResultCreateNew extends AddRoutinesSheetResult {
  const AddRoutinesSheetResultCreateNew();
}

/// Bottom sheet for selecting routines to add to the weekly bucket.
///
/// Multi-select with checkmarks. Routines already in the plan are
/// filtered out by the caller; the sheet shows only `availableRoutines`.
///
/// Fix 1B (`fix/active-and-plan-ux`):
///   * Adds a "Create new routine" action row at the bottom (above the
///     confirm button). Visually a text-link, NOT a selectable tile —
///     primary-coloured `Icons.add` + label.
///   * The empty state (`availableRoutines.isEmpty`) is now a tappable
///     `TextButton` invoking the same flow, replacing the dead text.
///   * `preSelectedRoutineIds` lets the parent pre-check routines on
///     first build (returning user, post-creation re-open). User must
///     still confirm via the "ADD N ROUTINES" button — pre-selection
///     does NOT auto-add.
class AddRoutinesSheet extends StatefulWidget {
  const AddRoutinesSheet({
    required this.availableRoutines,
    required this.inPlanIds,
    this.preSelectedRoutineIds = const <String>{},
    super.key,
  });

  /// Routines not already in the bucket.
  final List<Routine> availableRoutines;

  /// IDs of routines already in the plan (the parent already filters them
  /// out of `availableRoutines`; the field is retained for callers that
  /// want to know which were excluded). Currently unused inside the
  /// sheet — kept for API stability.
  final Set<String> inPlanIds;

  /// IDs to pre-select on first build. Used by the create-new return
  /// flow: the parent navigates to `/routines/create`, then re-opens the
  /// sheet with the freshly-created routine's id here so the user sees
  /// it already checked. They must still tap "ADD N ROUTINES" to confirm.
  final Set<String> preSelectedRoutineIds;

  @override
  State<AddRoutinesSheet> createState() => _AddRoutinesSheetState();
}

class _AddRoutinesSheetState extends State<AddRoutinesSheet> {
  late final Set<Routine> _selected;

  @override
  void initState() {
    super.initState();
    // Seed the selection with any routines whose id is in
    // [widget.preSelectedRoutineIds]. Doing this in initState (rather
    // than build) ensures the state is established once and respects the
    // contract that pre-selection is a starting point, not a
    // continually-enforced override — the user can uncheck the
    // pre-selected tile if they change their mind.
    _selected = widget.availableRoutines
        .where((r) => widget.preSelectedRoutineIds.contains(r.id))
        .toSet();
  }

  void _emitCreateNew() {
    Navigator.of(context).pop(const AddRoutinesSheetResultCreateNew());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Semantics(
                    container: true,
                    identifier: 'weekly-plan-add-sheet-title',
                    child: Text(
                      l10n.addRoutinesSheet,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const Spacer(),
                  if (widget.availableRoutines.isEmpty)
                    Text(
                      l10n.allRoutinesInPlan,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.availableRoutines.isEmpty
                  ? _EmptyStateCreateNew(onTap: _emitCreateNew)
                  : ListView.builder(
                      controller: scrollController,
                      // +1 for the "Create new routine" trailing action
                      // row. Keeps the action visible at the bottom of
                      // the list (above the confirm button) so a user
                      // who has scrolled to the end of a long list still
                      // sees it.
                      itemCount: widget.availableRoutines.length + 1,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        if (index == widget.availableRoutines.length) {
                          return _CreateNewRoutineRow(onTap: _emitCreateNew);
                        }
                        final routine = widget.availableRoutines[index];
                        final isSelected = _selected.contains(routine);

                        return _RoutineSelectTile(
                          routine: routine,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(routine);
                              } else {
                                _selected.add(routine);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            // Add button.
            if (_selected.isNotEmpty)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      container: true,
                      identifier: 'weekly-plan-add-confirm',
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(
                          AddRoutinesSheetResultSelected(_selected.toList()),
                        ),
                        child: Text(l10n.addCountRoutines(_selected.length)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bottom-of-list "Create new routine" action row. Visually a text-link
/// (primary-coloured `Icons.add` + label), NOT a selectable tile — the
/// surrounding tiles use a card-like Material; this row is intentionally
/// distinct so it does not read as another routine to pick.
class _CreateNewRoutineRow extends StatelessWidget {
  const _CreateNewRoutineRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'weekly-plan-create-new-routine',
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.createNewRoutine,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state replacement for the previous "Create more routines to add
/// them here." dead text. Same visual language as
/// [_CreateNewRoutineRow] (icon + primary text) but centered and sized
/// for a body-of-sheet placement.
class _EmptyStateCreateNew extends StatelessWidget {
  const _EmptyStateCreateNew({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.add, color: theme.colorScheme.primary),
        label: Text(
          l10n.createNewRoutine,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RoutineSelectTile extends StatelessWidget {
  const _RoutineSelectTile({
    required this.routine,
    required this.isSelected,
    required this.onTap,
  });

  final Routine routine;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routine.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.exercisesCount(routine.exercises.length),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary)
                else
                  Icon(
                    Icons.circle_outlined,
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
