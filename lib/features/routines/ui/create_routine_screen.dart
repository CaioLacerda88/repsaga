import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/models/exercise.dart';
import '../../workouts/ui/widgets/exercise_picker_sheet.dart';
import '../models/routine.dart';
import '../providers/notifiers/routine_list_notifier.dart';

class CreateRoutineScreen extends ConsumerStatefulWidget {
  const CreateRoutineScreen({super.key, this.routine});

  final Routine? routine;

  @override
  ConsumerState<CreateRoutineScreen> createState() =>
      _CreateRoutineScreenState();
}

/// DB + UI cap for routine notes (migration 00075 mirrors this).
const _kRoutineNotesMaxLength = 600;

/// Show the live character counter only once the user is within 100 chars of
/// the cap — keeps the field chrome quiet until brevity actually matters.
const _kRoutineNotesCounterThreshold = 500;

class _CreateRoutineScreenState extends ConsumerState<CreateRoutineScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  final _exercises = <_RoutineExerciseEntry>[];
  bool _saving = false;

  bool get _isEditing => widget.routine != null;

  // Notes are OPTIONAL — they intentionally do not gate _canSave.
  bool get _canSave =>
      _nameController.text.trim().isNotEmpty && _exercises.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.routine?.name ?? '');
    _notesController = TextEditingController(text: widget.routine?.notes ?? '');

    if (widget.routine != null) {
      for (final re in widget.routine!.exercises) {
        _exercises.add(
          _RoutineExerciseEntry(
            exerciseId: re.exerciseId,
            exercise: re.exercise,
            setCount: re.setConfigs.isNotEmpty ? re.setConfigs.length : 3,
            restSeconds: re.setConfigs.isNotEmpty
                ? re.setConfigs.first.restSeconds ?? 90
                : 90,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // The `_saving` flag is set to true synchronously before the first await,
  // so the only double-tap window is a single frame (~16ms). This is not
  // exploitable by human interaction and does not warrant a more complex
  // debounce mechanism.
  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);

    final exercises = _exercises
        .map(
          (e) => RoutineExercise(
            exerciseId: e.exerciseId,
            setConfigs: List.generate(
              e.setCount,
              (_) => RoutineSetConfig(restSeconds: e.restSeconds),
            ),
            exercise: e.exercise,
          ),
        )
        .toList();

    final notesText = _notesController.text.trim();
    final notes = notesText.isEmpty ? null : notesText;

    try {
      final notifier = ref.read(routineListProvider.notifier);
      if (_isEditing) {
        await notifier.updateRoutine(
          id: widget.routine!.id,
          name: _nameController.text.trim(),
          exercises: exercises,
          notes: notes,
        );
      } else {
        await notifier.createRoutine(
          name: _nameController.text.trim(),
          exercises: exercises,
          notes: notes,
        );
      }

      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToSaveRoutine)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addExercise() async {
    final exercise = await ExercisePickerSheet.show(context);
    if (exercise == null || !mounted) return;

    setState(() {
      _exercises.add(
        _RoutineExerciseEntry(
          exerciseId: exercise.id,
          exercise: exercise,
          setCount: 3,
          restSeconds: 90,
        ),
      );
    });
  }

  /// Custom notes counter. Returns `null` (fully collapsing the counter
  /// sub-row, so the field reserves no vertical gap for it) until the user is
  /// within 100 chars of the cap, then "{current} / {max}" colored by
  /// remaining headroom: textDim normally → warning at ≤30 remaining → error
  /// at the cap (≤0). `null` (not `SizedBox.shrink()`) matches the
  /// NotesEditSheet pattern and avoids InputDecorator's counter sub-row
  /// padding entirely while the counter is hidden.
  Widget? _buildNotesCounter(BuildContext context, int currentLength) {
    if (currentLength < _kRoutineNotesCounterThreshold) {
      return null;
    }
    final l10n = AppLocalizations.of(context);
    final remaining = _kRoutineNotesMaxLength - currentLength;
    final Color color;
    if (remaining <= 0) {
      color = AppColors.error;
    } else if (remaining <= 30) {
      color = AppColors.warning;
    } else {
      color = AppColors.textDim;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.notesCharCounter(currentLength, _kRoutineNotesMaxLength),
        style: AppTextStyles.bodySmall.copyWith(color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // The keyboard OVERLAYS the form instead of resizing/reflowing it: tapping
      // the name or notes field (both near the top, always above the IME) just
      // slides the keyboard up over the content below — the screen behind stays
      // put. Without this the body shrinks on focus, the list reflows, and the
      // exercises get shoved under a rising empty band. The only editable fields
      // sit above the keyboard, so nothing the user types is ever covered.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: _isEditing
              ? 'routine-mgmt-edit-title'
              : 'routine-mgmt-create-title',
          child: Text(_isEditing ? l10n.editRoutine : l10n.createRoutine),
        ),
        actions: [
          Semantics(
            container: true,
            identifier: 'create-routine-save',
            child: TextButton(
              onPressed: _canSave && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
          ),
        ],
      ),
      // ListView (not SingleChildScrollView+Column) so the scrollable form
      // body uses a proper lazy viewport: it repaints correctly when the
      // keyboard resizes the Scaffold body. A SingleChildScrollView here left
      // the exercise cards below the focused notes field unpainted while the
      // keyboard was up (an empty card-shaped void that tracked the IME).
      // ListView stretches its children to the cross-axis width, so the fields
      // stay full-width without an explicit CrossAxisAlignment.stretch.
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          TextField(
            controller: _nameController,
            autofocus: !_isEditing,
            maxLength: 80,
            decoration: InputDecoration(hintText: l10n.routineName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          // Q2 routine notes — optional, multiline, flat field on surface2
          // (no Card chrome). Lives below name, above the exercise list.
          Semantics(
            container: true,
            identifier: 'create-routine-notes',
            child: TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              maxLength: _kRoutineNotesMaxLength,
              // Custom counter (see _buildNotesCounter): hide Material's
              // default by returning an empty widget when below threshold.
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => _buildNotesCounter(context, currentLength),
              decoration: InputDecoration(
                hintText: l10n.routineNotesHint,
                filled: true,
                fillColor: AppColors.surface2,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 24),
          if (_exercises.isNotEmpty) ...[
            ..._exercises.asMap().entries.map(
              (entry) => _ExerciseCard(
                entry: entry.value,
                onSetCountChanged: (count) {
                  setState(() => entry.value.setCount = count);
                },
                onRestChanged: (rest) {
                  setState(() => entry.value.restSeconds = rest);
                },
                onRemove: () {
                  setState(() => _exercises.removeAt(entry.key));
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            container: true,
            identifier: 'create-routine-add-exercise',
            child: OutlinedButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add),
              label: Text(l10n.addExercise),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineExerciseEntry {
  _RoutineExerciseEntry({
    required this.exerciseId,
    this.exercise,
    required this.setCount,
    required this.restSeconds,
  });

  final String exerciseId;
  final Exercise? exercise;
  int setCount;
  int restSeconds;
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.entry,
    required this.onSetCountChanged,
    required this.onRestChanged,
    required this.onRemove,
  });

  final _RoutineExerciseEntry entry;
  final ValueChanged<int> onSetCountChanged;
  final ValueChanged<int> onRestChanged;
  final VoidCallback onRemove;

  static const _restOptions = [30, 60, 90, 120, 180, 240];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final exerciseName = entry.exercise?.name ?? l10n.unknownExercise;
    final muscleGroup = entry.exercise?.muscleGroup.localizedName(l10n);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exerciseName, style: AppTextStyles.title),
                        if (muscleGroup != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              muscleGroup,
                              style: AppTextStyles.label.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Set count stepper
              Row(
                children: [
                  Semantics(
                    container: true,
                    identifier: 'create-routine-sets',
                    child: Text(l10n.setsLabel, style: AppTextStyles.body),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 20),
                    onPressed: entry.setCount > 1
                        ? () => onSetCountChanged(entry.setCount - 1)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${entry.setCount}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.numeric.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: entry.setCount < 10
                        ? () => onSetCountChanged(entry.setCount + 1)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Rest time chips
              Semantics(
                container: true,
                identifier: 'create-routine-rest',
                child: Text(l10n.restLabel, style: AppTextStyles.body),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _restOptions.map((seconds) {
                  final isSelected = entry.restSeconds == seconds;
                  final label = seconds >= 60
                      ? '${seconds ~/ 60}m${seconds % 60 > 0 ? ' ${seconds % 60}s' : ''}'
                      : '${seconds}s';
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) => onRestChanged(seconds),
                    selectedColor: theme.colorScheme.primary.withValues(
                      alpha: 0.15,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
