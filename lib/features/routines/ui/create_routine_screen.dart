import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/models/exercise.dart';
import '../../profile/providers/profile_providers.dart';
import '../../rpg/domain/body_part_hues.dart';
import '../../rpg/models/body_part.dart';
import '../../workouts/ui/widgets/cardio_field.dart';
import '../../workouts/ui/widgets/cardio_target_dialogs.dart';
import '../../workouts/ui/widgets/exercise_picker_sheet.dart';
import '../../workouts/utils/cardio_format.dart';
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

/// DB + UI cap for the routine name.
const _kRoutineNameMaxLength = 80;

/// Show the name counter only once the user is within ~10 of the cap — mirrors
/// the notes-counter pattern so the field chrome stays quiet until it matters.
const _kRoutineNameCounterThreshold = 70;

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
        // A cardio entry persists EXACTLY ONE config carrying the target —
        // `setConfigs.length` is NOT a set count for it, so read the target
        // off the single config instead of treating the list as a set list.
        final isCardio = re.exercise?.muscleGroup == MuscleGroup.cardio;
        final firstCfg = re.setConfigs.isNotEmpty ? re.setConfigs.first : null;
        _exercises.add(
          _RoutineExerciseEntry(
            exerciseId: re.exerciseId,
            exercise: re.exercise,
            setCount: re.setConfigs.isNotEmpty ? re.setConfigs.length : 3,
            restSeconds: firstCfg?.restSeconds ?? 90,
            targetDurationSeconds: isCardio
                ? firstCfg?.targetDurationSeconds
                : null,
            targetDistanceM: isCardio ? firstCfg?.targetDistanceM : null,
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
            // A cardio entry persists EXACTLY ONE config carrying its optional
            // duration/distance target (no set count / reps / weight / rest).
            // Strength + bodyweight keep the per-set rest×count shape.
            setConfigs: e.isCardio
                ? [
                    RoutineSetConfig(
                      targetDurationSeconds: e.targetDurationSeconds,
                      targetDistanceM: e.targetDistanceM,
                    ),
                  ]
                : List.generate(
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

  /// Custom name counter — mirrors [_buildNotesCounter]: returns `null` (fully
  /// collapsing the sub-row) until within ~10 of the cap, then the colored
  /// "{current} / {max}" readout.
  Widget? _buildNameCounter(BuildContext context, int currentLength) {
    if (currentLength < _kRoutineNameCounterThreshold) {
      return null;
    }
    final l10n = AppLocalizations.of(context);
    final remaining = _kRoutineNameMaxLength - currentLength;
    final Color color;
    if (remaining <= 0) {
      color = AppColors.error;
    } else if (remaining <= 5) {
      color = AppColors.warning;
    } else {
      color = AppColors.textDim;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.notesCharCounter(currentLength, _kRoutineNameMaxLength),
        style: AppTextStyles.bodySmall.copyWith(color: color),
      ),
    );
  }

  /// Uppercase section eyebrow above the name / notes fields (Phase 38h 2c).
  Widget _sectionEyebrow(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.sectionHeader.copyWith(color: AppColors.hotViolet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Distance target slot follows the same one unit-system toggle the active
    // cardio card uses — kg → km, lbs → mi (CardioFormat.distanceUnitFor).
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    return Scaffold(
      // The keyboard OVERLAYS the form instead of resizing/reflowing it: tapping
      // the name or notes field (both near the top, always above the IME) just
      // slides the keyboard up over the content below — the screen behind stays
      // put. Without this the body shrinks on focus, the list reflows, and the
      // exercises get shoved under a rising empty band. The only editable fields
      // sit above the keyboard, so nothing the user types is ever covered. If a
      // future editable field is added INSIDE an _ExerciseCard (e.g. per-exercise
      // notes), revisit this — that field would sit below the keyboard with no
      // auto-scroll affordance to reach it.
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
      // The exercise cards below the focused notes field used to stop painting
      // while the keyboard was up — an empty card-shaped void tracking the IME.
      // That was triggered by the keyboard RESIZING the Scaffold body; with
      // `resizeToAvoidBottomInset: false` (above) the body never resizes, so a
      // plain SingleChildScrollView repaints correctly. SingleChildScrollView
      // (not ListView) is deliberate: it builds ALL children eagerly, so every
      // exercise card is in the tree/AOM for E2E + screen readers even when
      // scrolled off — a lazy ListView dropped off-viewport cards from the DOM
      // and broke the routine-create E2E flow.
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionEyebrow(l10n.routineSectionLabel),
            TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              maxLength: _kRoutineNameMaxLength,
              // Custom counter (see _buildNameCounter): hidden until near cap.
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => _buildNameCounter(context, currentLength),
              decoration: InputDecoration(hintText: l10n.routineName),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _sectionEyebrow(l10n.notesSectionLabel),
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
            if (_exercises.isEmpty)
              // RPG-voiced empty-state beat — a center of gravity between the
              // notes field and the add button (Phase 38h 3d) instead of a
              // cold blank gap.
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 30,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 30,
                      color: AppColors.textDim.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.routineEmptyExercises,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              ..._exercises.asMap().entries.map(
                (entry) => _ExerciseCard(
                  entry: entry.value,
                  weightUnit: weightUnit,
                  onSetCountChanged: (count) {
                    setState(() => entry.value.setCount = count);
                  },
                  onRestChanged: (rest) {
                    setState(() => entry.value.restSeconds = rest);
                  },
                  onTargetDurationChanged: (seconds) {
                    setState(() => entry.value.targetDurationSeconds = seconds);
                  },
                  onTargetDistanceChanged: (meters) {
                    setState(() => entry.value.targetDistanceM = meters);
                  },
                  onRemove: () {
                    setState(() => _exercises.removeAt(entry.key));
                  },
                ),
              ),
              // 16dp separation from the last card (Phase 38h 2d).
              const SizedBox(height: 16),
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
      ),
      // Bottom-anchored full-width Save CTA (Phase 38h 2e). The AppBar Save
      // stays as a secondary affordance; this is the primary, thumb-reachable
      // one. SafeArea-floored so it clears the gesture nav bar. Mirrors the
      // AppBar's enabled/disabled gating (_canSave && !_saving). Coexists with
      // `resizeToAvoidBottomInset: false`: the only editable fields sit above
      // the keyboard, so the bar never needs to ride the IME — it stays put.
      bottomNavigationBar: _BottomSaveBar(
        enabled: _canSave && !_saving,
        saving: _saving,
        label: l10n.saveRoutineCta,
        onSave: _save,
      ),
    );
  }
}

/// Bottom Save bar — a full-width primary CTA floored by [SafeArea] so it
/// clears the Android gesture pill. Disabled state mirrors the AppBar Save's
/// gating exactly so the two affordances never disagree.
class _BottomSaveBar extends StatelessWidget {
  const _BottomSaveBar({
    required this.enabled,
    required this.saving,
    required this.label,
    required this.onSave,
  });

  final bool enabled;
  final bool saving;
  final String label;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.abyss,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hair)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Semantics(
              container: true,
              identifier: 'create-routine-save-cta',
              child: FilledButton.icon(
                onPressed: enabled ? onSave : null,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 20),
                label: Text(label),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          ),
        ),
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
    this.targetDurationSeconds,
    this.targetDistanceM,
  });

  final String exerciseId;
  final Exercise? exercise;

  // Strength / bodyweight shape — ignored on a cardio entry.
  int setCount;
  int restSeconds;

  // Cardio target — both null until the user fills a slot. Persisted as the
  // single RoutineSetConfig of a cardio routine entry.
  int? targetDurationSeconds;
  double? targetDistanceM;

  /// Cardio wins over bodyweight (precedence per the type-aware-card spec).
  bool get isCardio => exercise?.muscleGroup == MuscleGroup.cardio;

  /// Only meaningful when [isCardio] is false.
  bool get isBodyweight => exercise?.equipmentType == EquipmentType.bodyweight;
}

/// Type-aware routine-builder exercise card. Branches on the entry's
/// exercise (detection is free — the [Exercise] rides on the entry):
///   * **Cardio** (`muscleGroup == cardio`, wins over bodyweight) — teal
///     identity stripe + CARDIO eyebrow + two optional duration/distance
///     TARGET slots. NO set stepper, NO rest chips.
///   * **Bodyweight** (`equipmentType == bodyweight`) — the strength layout
///     UNCHANGED (set stepper + rest chips) but a neutral BODYWEIGHT tag in
///     place of the violet muscle-group chip (brand-vs-identity rule).
///   * **Strength** (else) — unchanged.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.entry,
    required this.weightUnit,
    required this.onSetCountChanged,
    required this.onRestChanged,
    required this.onTargetDurationChanged,
    required this.onTargetDistanceChanged,
    required this.onRemove,
  });

  final _RoutineExerciseEntry entry;
  final String weightUnit;
  final ValueChanged<int> onSetCountChanged;
  final ValueChanged<int> onRestChanged;
  final ValueChanged<int> onTargetDurationChanged;
  final ValueChanged<double> onTargetDistanceChanged;
  final VoidCallback onRemove;

  static const _restOptions = [30, 60, 90, 120, 180, 240];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;

    if (entry.isCardio) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          // Clip so the 3dp left stripe (a full-bleed child of the Stack)
          // is trimmed to the 12dp rounded corner instead of squaring it off.
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 3dp teal identity stripe — the at-a-glance "this is cardio"
              // cue (matches the active CardioEntryCard).
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
                // +3 left for the stripe; otherwise mirrors the 16 chrome.
                padding: const EdgeInsets.fromLTRB(19, 16, 16, 16),
                child: _buildCardioBody(context),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildStrengthBody(context),
        ),
      ),
    );
  }

  Widget _buildCardioBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final distanceUnit = CardioFormat.distanceUnitFor(weightUnit);

    final hasDuration = entry.targetDurationSeconds != null;
    final hasDistance = entry.targetDistanceM != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          context,
          child: _IdentityPill.cardio(slug: entry.exercise?.slug),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: CardioField(
                identifier: 'create-routine-target-time',
                semanticsLabel: l10n.routineTargetTimeLabel,
                label: l10n.routineTargetTimeLabel,
                // Taller hero slot + edit glyph on a filled value (Phase 38h
                // 2a/3a). The active CardioEntryCard stays on the compact
                // default — the size is opt-in here only.
                size: CardioFieldSize.large,
                showEditAffordance: hasDuration,
                onTap: () async {
                  final seconds = await showCardioDurationDialog(
                    context,
                    initialSeconds:
                        entry.targetDurationSeconds ??
                        kDefaultCardioDurationSeconds,
                  );
                  if (seconds != null) onTargetDurationChanged(seconds);
                },
                child: !hasDuration
                    ? GhostValue(text: l10n.cardioAddValue)
                    : Text(
                        CardioFormat.duration(entry.targetDurationSeconds!),
                        style: AppTextStyles.numeric.copyWith(
                          fontSize: CardioFieldSize.large.valueFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CardioField(
                identifier: 'create-routine-target-distance',
                semanticsLabel: l10n.routineTargetDistanceLabel,
                label: l10n.routineTargetDistanceLabel,
                size: CardioFieldSize.large,
                showEditAffordance: hasDistance,
                onTap: () async {
                  final meters = await showCardioDistanceDialog(
                    context,
                    initialMeters: entry.targetDistanceM,
                    distanceUnit: distanceUnit,
                    locale: locale,
                  );
                  if (meters != null) onTargetDistanceChanged(meters);
                },
                child: !hasDistance
                    ? GhostValue(text: l10n.cardioAddValue)
                    : Text.rich(
                        TextSpan(
                          text: CardioFormat.distanceValue(
                            entry.targetDistanceM!,
                            distanceUnit: distanceUnit,
                            locale: locale,
                          ),
                          style: AppTextStyles.numeric.copyWith(
                            fontSize: CardioFieldSize.large.valueFontSize,
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
          ],
        ),
      ],
    );
  }

  Widget _buildStrengthBody(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          context,
          child: entry.isBodyweight
              ? _IdentityPill.bodyweight(label: l10n.routineBodyweightTag)
              : _IdentityPill.strength(
                  muscleGroup: entry.exercise?.muscleGroup,
                ),
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
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Shared header row: exercise name + an exercise-specific [child] sub-line
  /// (muscle-group / bodyweight tag for strength; CARDIO eyebrow for cardio)
  /// + the remove button.
  Widget _header(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final exerciseName = entry.exercise?.name ?? l10n.unknownExercise;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exerciseName, style: AppTextStyles.title),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
        // Remove ×. Drops `visualDensity: compact` (which silently shrank the
        // rendered hit-box below the 48dp floor — feedback:
        // tap-target-measurement) and pins explicit 48×48 constraints.
        IconButton(
          icon: Icon(Icons.close, color: theme.colorScheme.error, size: 20),
          onPressed: onRemove,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ],
    );
  }
}

/// One unified identity pill grammar for all three exercise types (Phase 38h
/// 2b): filled, identity color at 15% alpha, uppercase [AppTextStyles.label]
/// in the identity color, [kRadiusSm] corners. Only the color varies:
///   * [cardio]     — teal ([AppColors.bodyPartCardio]); renders the resolved
///     "Running · Cardio" activity eyebrow via [CardioEyebrow]'s slug map,
///     never a raw slug.
///   * [strength]   — the muscle group's [BodyPartHues] identity hue (chest
///     pink, back blue, …). MuscleGroup and BodyPart share enum names, so the
///     hue is looked up by name.
///   * [bodyweight] — NEUTRAL (surface2 fill, hair border, textDim label —
///     NO identity color, per the brand-vs-identity rule).
class _IdentityPill extends StatelessWidget {
  const _IdentityPill._({
    required this.label,
    required this.color,
    this.labelColor,
    this.cardioSlug,
    this.neutral = false,
    this.isCardio = false,
  });

  /// Cardio variant — the activity eyebrow (resolved label, never a raw slug).
  /// Background is teal at 15%; the label keeps the teal-dim (0.72 alpha)
  /// register the active card's eyebrow uses so the two read as one family.
  const _IdentityPill.cardio({String? slug})
    : this._(
        label: null,
        color: AppColors.bodyPartCardio,
        cardioSlug: slug,
        isCardio: true,
      );

  /// Strength variant — colored by the muscle group's identity hue.
  factory _IdentityPill.strength({required MuscleGroup? muscleGroup}) {
    final bodyPart = muscleGroup == null
        ? null
        : BodyPart.tryFromDbValue(muscleGroup.name);
    return _IdentityPill._(
      label: muscleGroup,
      color: bodyPart == null
          ? AppColors.hotViolet
          : BodyPartHues.hueFor(bodyPart),
    );
  }

  /// Bodyweight variant — neutral, no identity color.
  const _IdentityPill.bodyweight({required String label})
    : this._(label: label, color: AppColors.textDim, neutral: true);

  /// Either a [String] (bodyweight literal) or a [MuscleGroup] (strength), or
  /// null for the cardio variant (which renders [cardioSlug] instead).
  final Object? label;
  final Color color;
  final Color? labelColor;
  final String? cardioSlug;
  final bool neutral;
  final bool isCardio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final String text;
    if (isCardio) {
      // Resolved activity eyebrow inside the pill shell (never a raw slug).
      text = _CardioPillLabel.resolve(cardioSlug, l10n);
    } else if (label is MuscleGroup) {
      text = (label as MuscleGroup).localizedName(l10n).toUpperCase();
    } else {
      text = (label as String).toUpperCase();
    }

    // Cardio keeps the teal-dim (0.72) label register the active card uses;
    // strength/bodyweight render the label at the full identity color.
    final resolvedLabelColor =
        labelColor ?? (isCardio ? color.withValues(alpha: 0.72) : color);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: neutral ? AppColors.surface2 : color.withValues(alpha: 0.15),
        border: neutral ? Border.all(color: AppColors.hair) : null,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Text(
        text,
        style: AppTextStyles.label.copyWith(color: resolvedLabelColor),
      ),
    );
  }
}

/// Resolves the cardio pill's text — `<ACTIVITY> · CARDIO` or the generic
/// `CARDIO` fallback (never a raw slug — cluster:
/// slug-rendered-as-display-name). Mirrors [CardioEyebrow]'s slug map so the
/// builder pill and the active-card eyebrow stay in lockstep.
abstract final class _CardioPillLabel {
  static String resolve(String? slug, AppLocalizations l10n) {
    final activity = switch (slug) {
      'treadmill' => l10n.cardioActivityRunning,
      'rowing_machine' => l10n.cardioActivityRowing,
      'stationary_bike' || 'assault_bike' => l10n.cardioActivityCycling,
      'jump_rope' => l10n.cardioActivityJumpRope,
      'elliptical' => l10n.cardioActivityElliptical,
      'sled_push' || 'sled_drag' => l10n.cardioActivitySled,
      _ => null,
    };
    return activity != null
        ? l10n.cardioEyebrow(activity)
        : l10n.cardioEyebrowGeneric;
  }
}
