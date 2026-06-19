import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/weight_stepper.dart';
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

  /// Reorder MODE — toggled from the AppBar hamburger. In this mode every card
  /// COLLAPSES to its header (title + identity pill[s]) and becomes draggable by
  /// grabbing anywhere on it; the full Sets/Rest/target body is hidden so many
  /// cards fit on screen while ordering. Normal mode → full cards, not draggable.
  bool _reorderMode = false;

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
            // Strength/bodyweight target rehydration — read the per-exercise
            // uniform target off the first config (the builder writes the same
            // target into every config). Null for cardio + legacy routines.
            targetReps: isCardio ? null : firstCfg?.targetReps,
            targetWeight: isCardio ? null : firstCfg?.targetWeight,
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
                    // Per-exercise UNIFORM target: the same targetReps /
                    // targetWeight is written into every generated config so
                    // the start seed prefills each set identically.
                    (_) => RoutineSetConfig(
                      restSeconds: e.restSeconds,
                      targetReps: e.targetReps,
                      targetWeight: e.targetWeight,
                    ),
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

    // Duplicates are ALLOWED (a program may legitimately repeat a lift) — but
    // we surface a one-shot soft hint so an accidental re-add is noticed.
    final isDuplicate = _exercises.any((e) => e.exerciseId == exercise.id);

    setState(() {
      _exercises.add(
        _RoutineExerciseEntry(
          exerciseId: exercise.id,
          exercise: exercise,
          setCount: 3,
          restSeconds: 90,
          // Default rep target so the TARGET block reads sensibly on a fresh
          // add; weight stays null until the user dials one in.
          targetReps: 8,
        ),
      );
    });

    if (isDuplicate && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.exerciseAlreadyInRoutine(exercise.name))),
        );
    }
  }

  /// Toggle reorder MODE on/off. Entering collapses every card to its header and
  /// makes the whole card draggable; exiting expands them back to full cards.
  void _toggleReorderMode() {
    setState(() => _reorderMode = !_reorderMode);
  }

  /// Drag-reorder the in-memory exercise list. Mirrors the Weekly Plan editor's
  /// `_onReorder` VERBATIM (incl. the `newIndex--` adjustment ReorderableListView
  /// requires when an item moves DOWN). Order persists via the JSONB array order
  /// through the existing `_save` — no model / migration change.
  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex >= _exercises.length || newIndex > _exercises.length) {
      return;
    }
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final entry = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, entry);
    });
  }

  /// Lift feedback for the dragged card — Material elevation + a subtle
  /// `hotViolet @ 0.4` edge so the picked-up card reads as detached from the
  /// list without any decorative motion. Mirrors the dark-palette card chrome.
  Widget _reorderProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      shadowColor: AppColors.abyss.withValues(alpha: 0.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hotViolet.withValues(alpha: 0.4)),
        ),
        child: child,
      ),
    );
  }

  /// Removes an exercise but keeps it undoable: capture the entry + its index,
  /// then offer an Undo SnackBar that reinserts at the ORIGINAL position.
  /// Cluster-aware: explicit `persist: false` (persist-eats-duration) + a real
  /// [SnackBarAction] (action-not-snackbaraction).
  void _removeExercise(int index) {
    final l10n = AppLocalizations.of(context);
    final removed = _exercises[index];
    final name = removed.exercise?.name ?? l10n.unknownExercise;

    setState(() {
      _exercises.removeAt(index);
      // Reorder mode is only meaningful with >1 card; if a removal drops us to
      // a single exercise (or none), fall back to normal view so the lone card
      // expands and the toggle (now hidden) can't strand the user in a
      // collapsed, undraggable state.
      if (_reorderMode && _exercises.length <= 1) _reorderMode = false;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.exerciseRemovedUndo(name)),
          duration: const Duration(seconds: 4),
          // cluster: persist-eats-duration — SnackBar defaults persist to
          // `action != null`, so with an Undo action it would silently flip
          // persist→true and never auto-dismiss at the 4s duration. Pin false.
          persist: false,
          action: SnackBarAction(
            label: l10n.undoCta,
            onPressed: () {
              setState(() {
                final insertAt = index.clamp(0, _exercises.length);
                _exercises.insert(insertAt, removed);
              });
            },
          ),
        ),
      );
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

  /// Builds one exercise card with all its edit callbacks wired. Shared by the
  /// eager normal-mode [SliverList] and the reorder-mode [SliverReorderableList]
  /// so the two never drift. The [key] rides the card directly in normal mode;
  /// in reorder mode it rides the enclosing [ReorderableDragStartListener] (the
  /// reorder list requires the key on the OUTERMOST per-item widget), so the
  /// card itself is built keyless there.
  Widget _buildExerciseCard(
    _RoutineExerciseEntry entry,
    int index,
    String weightUnit, {
    Key? key,
  }) {
    return _ExerciseCard(
      key: key,
      entry: entry,
      weightUnit: weightUnit,
      reorderMode: _reorderMode,
      onSetCountChanged: (count) {
        setState(() => entry.setCount = count);
      },
      onRestChanged: (rest) {
        setState(() => entry.restSeconds = rest);
      },
      onTargetRepsChanged: (reps) {
        setState(() => entry.targetReps = reps);
      },
      onTargetWeightChanged: (weight) {
        setState(() => entry.targetWeight = weight);
      },
      onTargetDurationChanged: (seconds) {
        setState(() => entry.targetDurationSeconds = seconds);
      },
      onTargetDistanceChanged: (meters) {
        setState(() => entry.targetDistanceM = meters);
      },
      onRemove: () => _removeExercise(index),
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
          // Reorder MODE toggle — collapses the cards to draggable headers
          // (Icons.reorder) and back (Icons.done). Only meaningful with >1
          // exercise, so it's gated on that (a single card can't reorder).
          // Reuses the active-workout reorder l10n.
          if (_exercises.length > 1)
            Semantics(
              container: true,
              explicitChildNodes: true,
              identifier: 'create-routine-reorder-toggle',
              label: _reorderMode
                  ? l10n.exitReorderModeTooltip
                  : l10n.reorderExercisesTooltip,
              child: IconButton(
                onPressed: _toggleReorderMode,
                icon: Icon(_reorderMode ? Icons.done : Icons.reorder),
                tooltip: _reorderMode
                    ? l10n.exitReorderModeTooltip
                    : l10n.reorderExercisesTooltip,
              ),
            ),
        ],
      ),
      // The body is a SINGLE CustomScrollView — the one and only scroll
      // authority on this screen. That is load-bearing for drag auto-scroll:
      // the exercise cards live in a bare SliverReorderableList, whose
      // EdgeDraggingAutoScroller resolves its target via `Scrollable.of(context)`
      // → this CustomScrollView. So dragging a card to the viewport edge scrolls
      // the PAGE. The previous nested `ReorderableListView(shrinkWrap, physics:
      // NeverScrollableScrollPhysics)` inside a SingleChildScrollView broke
      // this: `Scrollable.of(context)` found the inner (non-scrolling) list, so
      // drag-to-edge never scrolled (cards are tall — TARGET + sets + rest — so
      // even 5-6 exercises overflow the viewport).
      //
      // Keyboard contract preserved: `resizeToAvoidBottomInset: false` (above)
      // means the body never resizes for the IME, so the scroll view does not
      // reflow/mis-repaint when the name/notes fields are focused. The keyboard
      // just overlays the content; the CustomScrollView can still scroll a
      // focused field into view if needed.
      //
      // cluster: listview-lazy-build-breaks-e2e — a SliverReorderableList wraps
      // EACH item in its own reorder-semantics container. On Flutter web that
      // container MERGES the card's descendant Text leaves into a single group
      // aria-label (`group "Barbell Bench Press CHEST 8 3"`) — it does NOT
      // reliably emit the standalone `flt-semantics` text leaf for "Barbell
      // Bench Press". Under parallel CanvasKit load (CI runs 4 Playwright
      // workers) the semantics bridge coalesces and drops the leaf entirely, so
      // `page.locator('text=Barbell Bench Press')` finds 0 matches even though
      // the card is fully painted. A serial local run is light enough that the
      // leaf survives — which is exactly why this regression was parallel-ONLY.
      // The old eager `Column` on main never wrapped each card in reorder
      // semantics, so the name was always its own reachable leaf node.
      //
      // Fix: render the cards EAGERLY (plain SliverList, no per-item reorder
      // semantics) in NORMAL mode — every name is a load-independent AOM leaf —
      // and only switch to SliverReorderableList while _reorderMode is true.
      // Add / edit / save E2E flows all read in normal mode; reorder is a
      // transient interaction with no text/identifier lookups during it, so the
      // reorder list is harmless there. The drag auto-scroll + collapse-to-drag
      // UX is fully preserved: the reorder list (when active) is still a bare
      // sliver of THIS CustomScrollView, so the page stays the scroll authority
      // for drag-to-edge auto-scroll.
      //
      // `cacheExtent: 3500` keeps the normal-mode SliverList (still lazy at the
      // sliver level) building realistic routines (≤~12 tall cards) up front, so
      // EVERY card — not just the on-screen ones — stays in the tree/AOM for
      // screen readers and any multi-card E2E reach. The real parallel-CI fix is
      // dropping the per-item reorder-semantics wrapper in normal mode (above);
      // the cacheExtent is the secondary reach guarantee for cards below the
      // fold.
      body: CustomScrollView(
        cacheExtent: 3500,
        slivers: [
          // Header region — ROUTINE/NOTES eyebrows + name + notes fields,
          // hosted unchanged in a sliver. Top + horizontal 16 chrome matches the
          // old SingleChildScrollView padding.
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionEyebrow(l10n.routineSectionLabel),
                  TextField(
                    controller: _nameController,
                    autofocus: !_isEditing,
                    maxLength: _kRoutineNameMaxLength,
                    // Custom counter (see _buildNameCounter): hidden until cap.
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
                  // Q2 routine notes — optional, multiline, flat field on
                  // surface2 (no Card chrome). Below name, above the list.
                  Semantics(
                    container: true,
                    identifier: 'create-routine-notes',
                    child: TextField(
                      controller: _notesController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: _kRoutineNotesMaxLength,
                      // Custom counter (see _buildNotesCounter): hide Material's
                      // default by returning null when below threshold.
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
                ],
              ),
            ),
          ),

          // Exercise cards — the reorderable sliver (drag-to-edge auto-scrolls
          // the page; see the body comment). Empty-state beat renders as its own
          // adapter instead. Horizontal 16 chrome matches the header.
          if (_exercises.isEmpty)
            SliverToBoxAdapter(
              // RPG-voiced empty-state beat — a center of gravity between the
              // notes field and the add button (Phase 38h 3d) instead of a
              // cold blank gap.
              child: Padding(
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
              ),
            )
          else if (_reorderMode)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // REORDER MODE ONLY — the lazy SliverReorderableList. Each card
              // supplies its OWN ReorderableDragStartListener wrapping the whole
              // collapsed card (no buildDefaultDragHandles). Because the list is
              // a direct sliver of the page's CustomScrollView, drag auto-scroll
              // resolves to that scroll view → drag-to-edge scrolls the page.
              // Lazy build is acceptable here: no E2E text/identifier lookups
              // run during the transient reorder interaction (see the body
              // comment / listview-lazy-build-breaks-e2e cluster note above).
              sliver: SliverReorderableList(
                itemCount: _exercises.length,
                onReorder: _onReorder,
                proxyDecorator: _reorderProxyDecorator,
                itemBuilder: (context, index) {
                  final entry = _exercises[index];
                  // Reorder mode: the whole COLLAPSED card is the drag handle —
                  // grabbing anywhere on it starts an immediate drag (the user
                  // already declared intent by entering reorder mode, so no
                  // long-press delay). The ObjectKey rides the OUTERMOST widget
                  // here (the listener), preserving per-entry identity across
                  // the reorder (cluster: missing-key-state-reuse) and serving
                  // as the per-child key the reorder list REQUIRES. The
                  // SliverReorderableList resolves its EdgeDraggingAutoScroller
                  // via the enclosing CustomScrollView, so drag-to-edge
                  // auto-scrolls the page.
                  return ReorderableDragStartListener(
                    key: ObjectKey(entry),
                    index: index,
                    child: _buildExerciseCard(entry, index, weightUnit),
                  );
                },
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // NORMAL MODE — eager SliverList: every card is built up front
              // with NO per-item reorder-semantics wrapper, so each exercise
              // name is its own reachable AOM/DOM text leaf regardless of render
              // load. This is the load-independent reach the old eager `Column`
              // on main gave (cluster: listview-lazy-build-breaks-e2e — see the
              // body comment for why the reorder list dropped the leaf under
              // parallel CI workers). Not draggable in this mode.
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = _exercises[index];
                  // Key by the entry's object identity so each card's State
                  // stays bound to ITS entry across remove / undo / reorder
                  // (cluster: missing-key-state-reuse). ObjectKey stays unique
                  // even with duplicate exercises.
                  return _buildExerciseCard(
                    entry,
                    index,
                    weightUnit,
                    key: ObjectKey(entry),
                  );
                }, childCount: _exercises.length),
              ),
            ),

          // Add-exercise button (+ the 16dp separation from the last card and
          // the bottom 16 chrome). Hosted in its own adapter below the list.
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              _exercises.isEmpty ? 0 : 16,
              16,
              16,
            ),
            sliver: SliverToBoxAdapter(
              child: Semantics(
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
            ),
          ),
        ],
      ),
      // Bottom-anchored full-width Save CTA — the SOLE Save affordance (the
      // redundant AppBar Save was dropped). Thumb-reachable, gated by
      // `_canSave && !_saving`. SafeArea-floored so it clears the gesture nav
      // bar. Coexists with `resizeToAvoidBottomInset: false`: the only editable
      // fields sit above the keyboard, so the bar never needs to ride the IME.
      bottomNavigationBar: _BottomSaveBar(
        enabled: _canSave && !_saving,
        saving: _saving,
        label: l10n.saveRoutineCta,
        onSave: _save,
      ),
    );
  }
}

/// Bottom Save bar — the full-width primary (and only) Save CTA, floored by
/// [SafeArea] so it clears the Android gesture pill. Disabled when the routine
/// can't be saved (no name / no exercises) or a save is in flight.
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
    this.targetReps,
    this.targetWeight,
    this.targetDurationSeconds,
    this.targetDistanceM,
  });

  final String exerciseId;
  final Exercise? exercise;

  // Strength / bodyweight shape — ignored on a cardio entry.
  int setCount;
  int restSeconds;

  // Per-exercise strength/bodyweight TARGET. One uniform target → written into
  // every generated RoutineSetConfig at save time. `targetReps` defaults to a
  // sensible 8 on a fresh add; `targetWeight` stays null until the user dials
  // one in (null → the start seed falls back to previous/equipment defaults).
  int? targetReps;
  double? targetWeight;

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
class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    super.key,
    required this.entry,
    required this.weightUnit,
    required this.reorderMode,
    required this.onSetCountChanged,
    required this.onRestChanged,
    required this.onTargetRepsChanged,
    required this.onTargetWeightChanged,
    required this.onTargetDurationChanged,
    required this.onTargetDistanceChanged,
    required this.onRemove,
  });

  final _RoutineExerciseEntry entry;

  final String weightUnit;

  /// Reorder MODE: true → collapse to a header-only draggable variant (title +
  /// identity pill[s] + a trailing drag affordance, violet border tint); false
  /// → the full card (steppers / rest / target slots / remove ×).
  final bool reorderMode;
  final ValueChanged<int> onSetCountChanged;
  final ValueChanged<int> onRestChanged;
  final ValueChanged<int> onTargetRepsChanged;
  // Nullable: a cleared / zero weight target is treated as NO target (null) so
  // the start seed falls back to previous/equipment defaults.
  final ValueChanged<double?> onTargetWeightChanged;
  // Nullable: a cleared / zero target (`0:00` time, `0` distance) is treated
  // as NO target (null), identical to leaving the slot empty — never stored as
  // a literal 0. The builder's `onTap` handlers fold the zero case into null
  // before invoking these (the shared `CardioFormat` parsers legitimately keep
  // 0 for the active logging card, so the decision lives here, builder-side).
  final ValueChanged<int?> onTargetDurationChanged;
  final ValueChanged<double?> onTargetDistanceChanged;
  final VoidCallback onRemove;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  static const _restOptions = [30, 60, 90, 120, 180, 240];

  // Bodyweight "+ Add weight" reveal — defaults hidden so a pure-bodyweight
  // card stays lean. Auto-revealed when rehydrating an entry that already has
  // a non-null added-weight target (see initState).
  bool _showAddedWeight = false;

  _RoutineExerciseEntry get entry => widget.entry;

  // A bodyweight entry that already carries an added-weight target shows the
  // stepper immediately (not behind the reveal CTA).
  bool get _entryWantsAddedWeight =>
      entry.isBodyweight && (entry.targetWeight ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (_entryWantsAddedWeight) _showAddedWeight = true;
  }

  @override
  void didUpdateWidget(_ExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If this State got re-associated with a DIFFERENT entry, re-derive the
    // reveal from the new entry so a stale flag can't bleed across (cluster:
    // missing-key-state-reuse). The ObjectKey on the card should prevent reuse;
    // this is the belt-and-suspenders half of the fix template. Same-entry
    // rebuilds (reorder toggle, unit change) preserve a manual reveal.
    if (!identical(oldWidget.entry, widget.entry)) {
      _showAddedWeight = _entryWantsAddedWeight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;

    // Reorder mode tints the card border a faint violet so the rearrangeable
    // state reads at a glance; normal mode is borderless (the picked-up lift
    // feedback is the list's `proxyDecorator`, not a resting border).
    final ShapeBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: widget.reorderMode
          ? BorderSide(color: AppColors.hotViolet.withValues(alpha: 0.4))
          : BorderSide.none,
    );

    // In reorder mode every card — cardio or strength — collapses to the SAME
    // header-only shape: title + identity pill(s) + a trailing drag affordance.
    // The full body (steppers / rest / target slots / remove ×) is hidden so
    // many short cards fit on screen while the user orders the list.
    if (widget.reorderMode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cardColor,
          shape: cardShape,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (entry.isCardio)
                // 3dp teal identity stripe — kept in the collapsed cardio card
                // so the type cue survives reorder mode.
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
                // +3 left for the cardio stripe; otherwise the 16 chrome.
                padding: EdgeInsets.fromLTRB(
                  entry.isCardio ? 19 : 16,
                  16,
                  16,
                  16,
                ),
                child: _collapsedHeader(context),
              ),
            ],
          ),
        ),
      );
    }

    if (entry.isCardio) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cardColor,
          shape: cardShape,
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
        shape: cardShape,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildStrengthBody(context),
        ),
      ),
    );
  }

  /// The collapsed reorder-mode header — exercise title + identity pill(s) on
  /// the left, a [Icons.drag_handle] affordance glyph on the right. The glyph
  /// is purely a visual cue: the WHOLE card is the drag target (the screen
  /// wraps it in a [ReorderableDragStartListener]), so the glyph carries the
  /// "Drag to reorder" semantics but no tap/drag of its own. No Sets stepper,
  /// no rest chips, no cardio target slots, no remove ×.
  /// The exercise-name title, wrapped in an EXPLICIT [Semantics] leaf.
  ///
  /// cluster: aom-label-text-merge / listview-lazy-build-breaks-e2e — a bare
  /// `Text` inside the card's larger semantics subtree is emitted as its own
  /// `flt-semantics` leaf only when Flutter web's semantics bridge has spare
  /// time; under parallel CanvasKit load (CI runs 4 Playwright workers) the
  /// bridge coalesces updates and MERGES the name into the card's group label
  /// (`group "Barbell Bench Press CHEST 8 3"`), dropping the standalone leaf —
  /// so `page.locator('text=Barbell Bench Press')` finds 0 matches even though
  /// the card is fully painted. A serial run is light enough that the leaf
  /// survives, which is why this was parallel-ONLY. An explicit `label:` forces
  /// the AOM to emit a stable, addressable node for the name regardless of
  /// render load — the load-independent guarantee a bare Text can't give.
  Widget _nameTitle(String exerciseName) {
    return Semantics(
      container: true,
      label: exerciseName,
      child: Text(exerciseName, style: AppTextStyles.title),
    );
  }

  Widget _collapsedHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exerciseName = entry.exercise?.name ?? l10n.unknownExercise;
    final pills = entry.isCardio
        ? _IdentityPill.cardio(slug: entry.exercise?.slug)
        : _strengthPills(context);

    return Row(
      children: [
        // Drag affordance glyph — the visual cue that the card is draggable.
        // Leading (before the name) per the locked phase-38 mockup. The drag
        // itself is started by the enclosing ReorderableDragStartListener
        // (whole-card), so this is a passive, semantics-labelled cue only.
        Semantics(
          container: true,
          identifier: 'create-routine-drag-handle',
          label: l10n.dragToReorder,
          child: const SizedBox(
            width: 32,
            height: 40,
            child: Icon(Icons.drag_handle, color: AppColors.textDim, size: 20),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _nameTitle(exerciseName),
              const SizedBox(height: 4),
              pills,
            ],
          ),
        ),
      ],
    );
  }

  /// The strength/bodyweight identity pill(s): a single muscle pill for a
  /// strength exercise, OR two pills (neutral "Bodyweight" + the muscle pill)
  /// for a bodyweight exercise. Shared by the full body and the collapsed
  /// reorder-mode header so the two never drift.
  Widget _strengthPills(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!entry.isBodyweight) {
      return _IdentityPill.strength(muscleGroup: entry.exercise?.muscleGroup);
    }
    // Two pills side by side: neutral grey "Bodyweight" + the muscle pill.
    // A pull-up is still a Back exercise — the muscle identity is preserved.
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _IdentityPill.bodyweight(label: l10n.routineBodyweightTag),
        _IdentityPill.strength(muscleGroup: entry.exercise?.muscleGroup),
      ],
    );
  }

  Widget _buildCardioBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final distanceUnit = CardioFormat.distanceUnitFor(widget.weightUnit);

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
                  // A dialog dismissal returns null → leave the target
                  // untouched. A returned 0 (`0:00`) means "no target" — clear
                  // it to null so the slot reverts to the `+ add` ghost rather
                  // than persisting a meaningless 0s target.
                  if (seconds != null) {
                    widget.onTargetDurationChanged(
                      seconds == 0 ? null : seconds,
                    );
                  }
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
                  // Same zero-is-no-target rule as duration: a returned 0.0
                  // distance clears the target to null (→ `+ add` ghost), not a
                  // stored 0 m.
                  if (meters != null) {
                    widget.onTargetDistanceChanged(meters == 0 ? null : meters);
                  }
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
        const SizedBox(height: 8),
        // One muted line — cardio targets prefill the run but are never
        // required to save the routine.
        Text(
          l10n.targetsOptional,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }

  Widget _buildStrengthBody(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isBodyweight = entry.isBodyweight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, child: _strengthPills(context)),
        const SizedBox(height: 12),

        // TARGET block — the per-exercise uniform target that prefills every
        // started set. Bodyweight leads with reps (the hero) and tucks weight
        // behind a "+ Add weight" reveal; strength shows both inline.
        if (!isBodyweight) ...[
          _targetWeightRow(context, l10n.weightLabel),
          const SizedBox(height: 8),
        ],
        _targetRepsRow(context),
        const SizedBox(height: 8),
        if (isBodyweight) _addedWeightSection(context),

        // Set count stepper
        _stepperRow(
          context,
          identifier: 'create-routine-sets',
          label: l10n.setsLabel,
          value: entry.setCount,
          onDecrement: entry.setCount > 1
              ? () => widget.onSetCountChanged(entry.setCount - 1)
              : null,
          onIncrement: entry.setCount < 10
              ? () => widget.onSetCountChanged(entry.setCount + 1)
              : null,
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
              onSelected: (_) => widget.onRestChanged(seconds),
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

  /// A `label … −/+ value` stepper row matching the existing set-count idiom.
  /// Used for both Reps and Sets so the two read identically.
  Widget _stepperRow(
    BuildContext context, {
    required String identifier,
    required String label,
    required int value,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    return Row(
      children: [
        Semantics(
          container: true,
          identifier: identifier,
          child: Text(label, style: AppTextStyles.body),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove, size: 20),
          onPressed: onDecrement,
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTextStyles.numeric.copyWith(fontSize: 18),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 20),
          onPressed: onIncrement,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// Target reps row (bounds 1-50), mirroring the set-count stepper idiom.
  Widget _targetRepsRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reps = entry.targetReps ?? 8;
    return _stepperRow(
      context,
      identifier: 'create-routine-target-reps',
      label: l10n.repsLabel,
      value: reps,
      onDecrement: reps > 1 ? () => widget.onTargetRepsChanged(reps - 1) : null,
      onIncrement: reps < 50
          ? () => widget.onTargetRepsChanged(reps + 1)
          : null,
    );
  }

  /// Target weight row — a keyboard-safe [WeightStepper] (exact entry is its
  /// own modal dialog, so the screen's `resizeToAvoidBottomInset:false` holds).
  /// A 0 value is treated as "no target" → null at the entry, so the start
  /// seed falls back to previous/equipment defaults.
  Widget _targetWeightRow(BuildContext context, String label) {
    return Row(
      children: [
        Semantics(
          container: true,
          identifier: 'create-routine-target-weight',
          child: Text(label, style: AppTextStyles.body),
        ),
        const Spacer(),
        SizedBox(
          width: 150,
          child: WeightStepper(
            value: entry.targetWeight ?? 0,
            unit: widget.weightUnit,
            onChanged: (w) => widget.onTargetWeightChanged(w == 0 ? null : w),
          ),
        ),
      ],
    );
  }

  /// Bodyweight added-weight section — a "+ Add weight" reveal (default
  /// hidden so a pure-bodyweight card stays lean) that expands the weight
  /// stepper labelled "Added weight" (belt / assist).
  Widget _addedWeightSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_showAddedWeight) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            container: true,
            identifier: 'create-routine-add-weight-cta',
            button: true,
            child: TextButton(
              onPressed: () => setState(() => _showAddedWeight = true),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(l10n.addWeightCta),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _targetWeightRow(context, l10n.addedWeightLabel),
    );
  }

  /// Shared full-card header row: exercise name + an exercise-specific [child]
  /// sub-line (muscle-group / bodyweight tag for strength; CARDIO eyebrow for
  /// cardio) + the remove button. Full cards are NOT draggable — reordering is
  /// a distinct MODE (see [_collapsedHeader]), so no drag handle here.
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
              _nameTitle(exerciseName),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
        // Remove ×. Always present, even at a single exercise. Drops
        // `visualDensity: compact` (which silently shrank the rendered hit-box
        // below the 48dp floor — feedback: tap-target-measurement) and pins
        // explicit 48×48 constraints.
        Semantics(
          container: true,
          identifier: 'create-routine-remove-exercise',
          label: l10n.removeExercise,
          child: IconButton(
            icon: Icon(Icons.close, color: theme.colorScheme.error, size: 20),
            onPressed: widget.onRemove,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
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
    final resolvedLabelColor = isCardio ? color.withValues(alpha: 0.72) : color;

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
/// slug-rendered-as-display-name). Delegates the slug→activity lookup to
/// [CardioEyebrow.activityLabel] (the single source) so the builder pill and
/// the active-card eyebrow can't drift.
abstract final class _CardioPillLabel {
  static String resolve(String? slug, AppLocalizations l10n) {
    final activity = CardioEyebrow.activityLabel(slug, l10n);
    return activity != null
        ? l10n.cardioEyebrow(activity)
        : l10n.cardioEyebrowGeneric;
  }
}
