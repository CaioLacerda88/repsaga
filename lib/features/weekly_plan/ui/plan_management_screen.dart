import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/platform_info.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../analytics/data/models/analytics_event.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../routines/models/routine.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../workouts/providers/workout_history_providers.dart';
import '../data/models/weekly_plan.dart';
import '../providers/weekly_plan_provider.dart';
import 'add_routines_sheet.dart';
import 'widgets/plan_add_routine_row.dart';
import 'widgets/plan_empty_state.dart';
import 'widgets/plan_routine_row.dart';

/// Plan management screen at `/plan/week`.
///
/// Allows users to:
/// - View and reorder routines in this week's bucket
/// - Add/remove routines
/// - Clear the week
/// - Auto-fill from most-used routines
class PlanManagementScreen extends ConsumerStatefulWidget {
  const PlanManagementScreen({super.key});

  @override
  ConsumerState<PlanManagementScreen> createState() =>
      _PlanManagementScreenState();
}

class _PlanManagementScreenState extends ConsumerState<PlanManagementScreen> {
  List<BucketRoutine> _bucketRoutines = [];

  /// Tracks whether the user has made local edits (reorder, add, remove).
  /// When true, we no longer sync from the provider to avoid clobbering.
  bool _dirty = false;

  /// Whether we've received the initial provider data at least once.
  bool _seeded = false;

  // --- Analytics debounce state -----------------------------------------
  //
  // `week_plan_saved` must fire at most once per edit session, otherwise
  // every reorder/remove/undo pushes a duplicate event and the funnel is
  // meaningless. The persistence call (`upsertPlan`) still runs on every
  // edit — we debounce ONLY the analytics insert. We fire once per session
  // when the user leaves the screen (dispose), capturing whichever options
  // were most recently in effect.
  //
  // Tracked bits:
  // - `_pendingAnalyticsEvent`: true once the user has made at least one
  //   edit that would have fired `week_plan_saved`
  // - `_lastUsedAutofill` / `_lastReplacedExisting`: latest flags from the
  //   most recent edit, used when we finally fire at dispose
  // - `_debouncedAnalyticsRepo` / `_debouncedAnalyticsUserId`: captured on
  //   the FIRST edit. `ref` cannot be used in dispose() — Riverpod treats
  //   the element as already torn down at that point — so we must hold the
  //   repo and user id directly.
  bool _pendingAnalyticsEvent = false;
  bool _lastUsedAutofill = false;
  bool _lastReplacedExisting = false;
  AnalyticsRepository? _debouncedAnalyticsRepo;
  String? _debouncedAnalyticsUserId;
  int? _debouncedTrainingFrequency;

  /// Debounce timer for [_savePlan]. Prevents rapid-fire Supabase writes
  /// during drag reorder by coalescing multiple calls into one.
  Timer? _saveDebounce;

  /// Whether the undo snackbar from a recent `_removeRoutine` is still
  /// on-screen. While true, the Fix-1A "Saved" confirmation snackbar is
  /// suppressed so it can't hide-and-replace the undo affordance.
  /// Tracked here (rather than poked at the `ScaffoldMessenger` queue)
  /// because the messenger does not expose a public "is anything
  /// showing" predicate.
  bool _undoSnackbarActive = false;

  /// Whether a "Saved" confirmation snackbar is currently in its 1-second
  /// display window. Two slow consecutive edits each fire `upsertPlan` and
  /// chain `_maybeShowSavedSnackbar`; without this guard the second call's
  /// `showSnackBar` REPLACES the still-visible first one, producing a
  /// visible "Saved... Saved..." stutter as the first snack is dismissed
  /// mid-display and a fresh 1-second snack appears in its place.
  ///
  /// Set true synchronously before `showSnackBar`; cleared via
  /// `controller.closed.whenComplete` once the 1-second window elapses
  /// (or another snack pre-empts it). While true, additional `Saved`
  /// requests are suppressed — the existing snack already gives the user
  /// the same signal.
  bool _savedSnackbarActive = false;

  /// Captured notifier for debounced save. `ref` cannot be used in dispose(),
  /// so we hold the notifier directly, refreshed on each edit.
  WeeklyPlanNotifier? _debouncedPlanNotifier;

  @override
  void dispose() {
    // Flush any pending debounced save before tearing down. This ensures
    // the user's last reorder is persisted even if they leave the screen
    // within the 300ms debounce window.
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      _flushDebouncedSave();
    }
    // Fire a single analytics event for the entire edit session, capturing
    // the most-recent flags (usedAutofill / replacedExisting). This is the
    // funnel-friendly "user saved the plan" signal — intermediate reorders
    // and undos do not fire their own events.
    if (_pendingAnalyticsEvent) {
      _flushAnalyticsEvent();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Listen for the async plan value to resolve (especially on slow
    // connections where the first build fires before data arrives).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(weeklyPlanProvider, (previous, next) {
        // Only seed from provider if user hasn't started editing.
        if (_dirty) return;
        final plan = next.value;
        if (plan != null && !_seeded) {
          setState(() {
            _bucketRoutines = [...plan.routines];
            _seeded = true;
          });
        } else if (!_seeded && plan == null && !next.isLoading) {
          // Provider resolved to null (no plan) — mark as seeded.
          _seeded = true;
        }
      }, fireImmediately: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch these providers so the widget rebuilds when data changes.
    ref.watch(weeklyPlanProvider);
    final routinesAsync = ref.watch(routineListProvider);
    final profile = ref.watch(profileProvider);

    final allRoutines = routinesAsync.value ?? [];
    final routineMap = <String, Routine>{for (final r in allRoutines) r.id: r};
    final trainingFrequency = profile.value?.trainingFrequencyPerWeek ?? 3;

    final atSoftCap = _bucketRoutines.length >= trainingFrequency;

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'weekly-plan-title',
          child: Text(l10n.thisWeeksPlan),
        ),
        actions: [
          Semantics(
            container: true,
            identifier: 'weekly-plan-overflow',
            label: l10n.moreOptions,
            child: PopupMenuButton<String>(
              tooltip: l10n.moreOptions,
              onSelected: (value) {
                if (value == 'clear') _confirmClear(context);
                if (value == 'autofill') {
                  _autoFill(allRoutines, trainingFrequency);
                }
              },
              itemBuilder: (context) {
                final l10n = AppLocalizations.of(context);
                return [
                  PopupMenuItem(value: 'autofill', child: Text(l10n.autoFill)),
                  PopupMenuItem(
                    value: 'clear',
                    child: Semantics(
                      container: true,
                      identifier: 'weekly-plan-clear-week',
                      child: Text(l10n.clearWeek),
                    ),
                  ),
                ];
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _bucketRoutines.isEmpty
                ? PlanEmptyState(
                    onAddRoutines: () => _showAddSheet(allRoutines),
                    onAutoFill: () => _autoFill(allRoutines, trainingFrequency),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _bucketRoutines.length + 1,
                    onReorder: _onReorder,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      if (index == _bucketRoutines.length) {
                        // Add routine row.
                        return PlanAddRoutineRow(
                          key: const ValueKey('add-routine'),
                          atSoftCap: atSoftCap,
                          bucketCount: _bucketRoutines.length,
                          trainingFrequency: trainingFrequency,
                          onTap: () => _showAddSheet(allRoutines),
                        );
                      }

                      final bucket = _bucketRoutines[index];
                      final routine = routineMap[bucket.routineId];
                      final isDone = bucket.completedWorkoutId != null;
                      final name = routine?.name ?? l10n.unknownRoutine;
                      final exerciseCount = routine?.exercises.length ?? 0;

                      return PlanRoutineRow(
                        key: ValueKey(bucket.routineId),
                        index: index,
                        routineId: bucket.routineId,
                        sequenceNumber: bucket.order,
                        name: name,
                        exerciseCount: exerciseCount,
                        isDone: isDone,
                        onDismissed: isDone
                            ? null
                            : () => _removeRoutine(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    // Don't reorder beyond the actual bucket items (skip the add row).
    if (oldIndex >= _bucketRoutines.length ||
        newIndex > _bucketRoutines.length) {
      return;
    }

    setState(() {
      _dirty = true;
      if (newIndex > oldIndex) newIndex--;
      final item = _bucketRoutines.removeAt(oldIndex);
      _bucketRoutines.insert(newIndex, item);
      _renumber();
    });
    _savePlan(usedAutofill: false, replacedExisting: false);
  }

  void _renumber() {
    _bucketRoutines = _bucketRoutines.indexed
        .map((entry) => entry.$2.copyWith(order: entry.$1 + 1))
        .toList();
  }

  void _removeRoutine(int index) {
    final removed = _bucketRoutines[index];
    setState(() {
      _dirty = true;
      _bucketRoutines.removeAt(index);
      _renumber();
    });
    _savePlan(usedAutofill: false, replacedExisting: false);

    // Undo snackbar.
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      _undoSnackbarActive = true;
      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.routineRemoved),
          duration: const Duration(seconds: 5),
          // persist: false — SnackBar defaults to persistent when an action
          // is set (Flutter intentional for "wait for user action"). We
          // want this undo to auto-dismiss at `duration` even if the user
          // ignores Undo. `_undoSnackbarActive` is cleared by the `closed`
          // listener below for ANY close reason, including the timeout
          // path that this opt-out enables.
          // showCloseIcon: true — explicit dismiss affordance (UI/UX
          // 2026-05-13). Material's X icon is the canonical opt-out when
          // `action:` performs work other than dismiss (here: UNDO is
          // destructive vs the user's intent).
          persist: false,
          showCloseIcon: true,
          action: SnackBarAction(
            label: l10n.undo.toUpperCase(),
            onPressed: () {
              setState(() {
                // Clamp to current list length in case reorders or other
                // removals happened between remove and undo.
                final safeIndex = index.clamp(0, _bucketRoutines.length);
                _bucketRoutines.insert(safeIndex, removed);
                _renumber();
              });
              _savePlan(usedAutofill: false, replacedExisting: false);
            },
          ),
        ),
      );
      // Clear the flag when the snackbar closes (timeout, user dismiss,
      // or another snack replaces it). Without this, a subsequent edit
      // long after the undo expired would silently suppress its Saved
      // confirmation.
      controller.closed.whenComplete(() {
        if (mounted) _undoSnackbarActive = false;
      });
    }
  }

  Future<void> _showAddSheet(
    List<Routine> allRoutines, {
    Set<String> preSelectedRoutineIds = const <String>{},
  }) async {
    final existingIds = _bucketRoutines.map((b) => b.routineId).toSet();
    final available = allRoutines
        .where((r) => !existingIds.contains(r.id))
        .toList();

    final result = await showModalBottomSheet<AddRoutinesSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddRoutinesSheet(
        availableRoutines: available,
        preSelectedRoutineIds: preSelectedRoutineIds,
      ),
    );

    if (!mounted || result == null) return;

    switch (result) {
      case AddRoutinesSheetResultSelected(:final routines):
        if (routines.isEmpty) return;
        setState(() {
          _dirty = true;
          for (final routine in routines) {
            _bucketRoutines.add(
              BucketRoutine(
                routineId: routine.id,
                order: _bucketRoutines.length + 1,
              ),
            );
          }
        });
        _savePlan(usedAutofill: false, replacedExisting: false);
      case AddRoutinesSheetResultCreateNew(:final previouslySelectedIds):
        // Snapshot the current routine ids BEFORE pushing so we can
        // identify the freshly-created one on return. Using a diff on ids
        // is robust against the user creating multiple routines in one
        // session and against an unrelated routine sync flushing while
        // the create screen is open.
        final beforeIds = allRoutines.map((r) => r.id).toSet();
        await context.push<void>('/routines/create');
        if (!mounted) return;
        // Re-read the routine list after creation. The provider may have
        // refreshed; either way we want the freshly-created id (if any)
        // pre-selected so the user only has to tap "ADD".
        final refreshed = ref.read(routineListProvider).value ?? allRoutines;
        final newIds = refreshed
            .map((r) => r.id)
            .where((id) => !beforeIds.contains(id))
            .toSet();
        // Merge the user's prior selection (carried through the sentinel)
        // with the freshly-created id(s). If the user had nothing checked
        // (empty-state path or just opened the sheet), `previouslySelectedIds`
        // is empty and the merge collapses to just `newIds`. If the user
        // backed out of creation without saving, `newIds` is empty and the
        // merge preserves the prior selection — the sheet re-opens with the
        // same checks the user had before tapping "Create new routine".
        await _showAddSheet(
          refreshed,
          preSelectedRoutineIds: {...previouslySelectedIds, ...newIds},
        );
    }
  }

  /// Auto-fill the bucket with the user's most-started routines.
  ///
  /// Ranks routines by how often their name appears in workout history.
  /// Fills up to [trainingFrequency] slots. If the bucket already has
  /// routines, shows a confirmation dialog before replacing.
  Future<void> _autoFill(
    List<Routine> allRoutines,
    int trainingFrequency,
  ) async {
    if (allRoutines.isEmpty) return;

    // Don't auto-fill if workout history hasn't loaded yet — frequency
    // ranking would silently fall back to alphabetical order.
    final historyState = ref.read(workoutHistoryProvider);
    if (historyState.isLoading && !historyState.hasValue) return;

    // If bucket already has routines, confirm replacement.
    if (_bucketRoutines.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) {
          final l10n = AppLocalizations.of(dialogCtx);
          return AlertDialog(
            title: Text(l10n.replacePlanTitle),
            content: Text(l10n.replacePlanContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(l10n.replace),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    // Build frequency map from workout history (name -> count).
    final history = ref.read(workoutHistoryProvider).value ?? [];
    final nameFrequency = <String, int>{};
    for (final workout in history) {
      nameFrequency[workout.name] = (nameFrequency[workout.name] ?? 0) + 1;
    }

    // Sort routines by frequency descending, then by name for stability.
    final ranked = [...allRoutines]
      ..sort((a, b) {
        final freqA = nameFrequency[a.name] ?? 0;
        final freqB = nameFrequency[b.name] ?? 0;
        if (freqB != freqA) return freqB.compareTo(freqA);
        return a.name.compareTo(b.name);
      });

    // Take the top N routines up to training frequency.
    final count = trainingFrequency < ranked.length
        ? trainingFrequency
        : ranked.length;
    final selected = ranked.take(count).toList();

    // Capture BEFORE the mutation so we can record whether autofill
    // replaced an existing plan.
    final wasNotEmpty = _bucketRoutines.isNotEmpty;
    setState(() {
      _dirty = true;
      _bucketRoutines = selected.indexed.map((entry) {
        return BucketRoutine(routineId: entry.$2.id, order: entry.$1 + 1);
      }).toList();
    });
    _savePlan(usedAutofill: true, replacedExisting: wasNotEmpty);
  }

  Future<void> _confirmClear(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) {
        final l10n = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          title: Text(l10n.clearWeekTitle),
          content: Text(l10n.clearWeekContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(l10n.cancel),
            ),
            Semantics(
              container: true,
              identifier: 'weekly-plan-clear-confirm',
              child: TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(l10n.clear),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _bucketRoutines = []);
    await ref.read(weeklyPlanProvider.notifier).clearPlan();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    context.pop();
  }

  /// Persist the current bucket state to Supabase and record that we owe an
  /// analytics event when the user finally leaves the screen.
  ///
  /// We deliberately do NOT fire `week_plan_saved` here: a single edit
  /// session (reorder + remove + undo + add routine) calls this method four
  /// or more times in a few seconds. Firing per-call floods the funnel with
  /// duplicate events. Instead we mark that an event is pending and store
  /// the most-recent flags; the actual insert happens once, at dispose,
  /// via [_flushAnalyticsEvent]. The persistence call stays per-edit so
  /// UX stays live.
  ///
  /// We ALSO capture a reference to the analytics repository and the user id
  /// on the first edit — `ref` cannot be used inside `dispose()` (the
  /// ConsumerStatefulElement is already torn down by then), so we must hold
  /// the repo object directly.
  void _savePlan({required bool usedAutofill, required bool replacedExisting}) {
    _saveDebounce?.cancel();
    // Capture the notifier while ref is still alive. The debounce timer
    // (or dispose) may fire after the widget is unmounted, so we must not
    // call ref.read() at that point.
    _debouncedPlanNotifier = ref.read(weeklyPlanProvider.notifier);
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      _flushDebouncedSave();
    });
    _pendingAnalyticsEvent = true;
    // usedAutofill and replacedExisting are "sticky" within a session: if
    // the user first auto-filled then reordered one card, the event that
    // ships at dispose should still say used_autofill=true. So we OR-in
    // any truthy value instead of overwriting.
    _lastUsedAutofill = _lastUsedAutofill || usedAutofill;
    _lastReplacedExisting = _lastReplacedExisting || replacedExisting;
    // Capture repo + user id + training frequency while ref is still alive.
    // Refreshed on every edit so the latest profile value is used at flush.
    _debouncedAnalyticsRepo = ref.read(analyticsRepositoryProvider);
    _debouncedAnalyticsUserId = ref
        .read(authRepositoryProvider)
        .currentUser
        ?.id;
    _debouncedTrainingFrequency =
        ref.read(profileProvider).value?.trainingFrequencyPerWeek ?? 3;
  }

  /// Immediately flush the pending debounced upsert call.
  ///
  /// Called from [dispose] and when the debounce timer fires. Uses the
  /// captured [_debouncedPlanNotifier] instead of `ref.read()` because
  /// `ref` cannot be used after the widget is unmounted.
  ///
  /// Fix 1A — on successful flush we show a 1-second "Saved" SnackBar to
  /// give the user visible feedback that their edit landed. Two suppress
  /// conditions:
  ///
  ///   1. The widget is no longer mounted (e.g. dispose() flush). Showing
  ///      a snackbar after unmount would crash on `ScaffoldMessenger.of`.
  ///   2. An undo snackbar is already showing (after `_removeRoutine`).
  ///      Replacing it would destroy the 5-second undo affordance — the
  ///      remove path is itself evidence the edit registered, so the
  ///      Saved confirmation is redundant there.
  void _flushDebouncedSave() {
    final notifier = _debouncedPlanNotifier;
    if (notifier == null) return;
    final future = notifier.upsertPlan(_bucketRoutines);
    // The persistence call may resolve synchronously (test stubs) or
    // asynchronously (production). Either way, we only show the snackbar
    // after the future settles successfully — we never lie about a save
    // that hasn't actually committed yet.
    future
        .then((_) {
          _maybeShowSavedSnackbar();
        })
        .catchError((_) {
          // Swallow: the offline banner already covers persistence
          // failures, and the analytics layer logs them. Showing a "Saved"
          // snack on a failed save would be a lie.
        });
  }

  /// Shows the "Saved" confirmation snackbar IF the widget is still
  /// mounted AND no other snackbar is currently visible AND no other
  /// Saved snack is already in its 1-second display window. Three
  /// suppression rules:
  ///
  ///   * `!mounted` — showing after dispose would crash on
  ///     `ScaffoldMessenger.of`.
  ///   * `_undoSnackbarActive` — protects the 5-second undo affordance
  ///     shipped from `_removeRoutine`. Replacing it would destroy the
  ///     user's recovery affordance for an action they may have
  ///     triggered by accident.
  ///   * `_savedSnackbarActive` — coalesces consecutive Saved snacks.
  ///     Two slow-but-separate edits (each ≥300ms apart) each fire
  ///     `upsertPlan` and chain back here; the default
  ///     `ScaffoldMessenger.showSnackBar` REPLACES the current snack, so
  ///     without this guard the first Saved is dismissed mid-display
  ///     and a fresh 1-second Saved appears — visible "Saved... Saved..."
  ///     stutter. With the guard the second call no-ops, the user
  ///     continues seeing the still-active Saved snack, and the contract
  ///     ("the last edit was persisted") still holds.
  void _maybeShowSavedSnackbar() {
    if (!mounted) return;
    if (_undoSnackbarActive) return;
    if (_savedSnackbarActive) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    _savedSnackbarActive = true;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.savedConfirmation),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Clear the flag when the snack finishes (timeout, dismiss, or
    // replacement). Without this, a subsequent edit long after the snack
    // expired would silently suppress its own Saved confirmation.
    controller.closed.whenComplete(() {
      if (mounted) _savedSnackbarActive = false;
    });
  }

  /// Fire the debounced `week_plan_saved` analytics event exactly once.
  /// Called from [dispose] when the user leaves the plan screen.
  ///
  /// Must not touch `ref` — the widget element is disposed before this
  /// runs. All data needed to build the event has been captured in the
  /// state fields during earlier edits.
  void _flushAnalyticsEvent() {
    final userId = _debouncedAnalyticsUserId;
    final repo = _debouncedAnalyticsRepo;
    final trainingFrequency = _debouncedTrainingFrequency ?? 3;
    if (userId == null || repo == null) return;
    unawaited(
      repo.insertEvent(
        userId: userId,
        event: AnalyticsEvent.weekPlanSaved(
          routineCount: _bucketRoutines.length,
          atSoftCap: _bucketRoutines.length >= trainingFrequency,
          usedAutofill: _lastUsedAutofill,
          replacedExisting: _lastReplacedExisting,
        ),
        platform: currentPlatform(),
        appVersion: currentAppVersion(),
      ),
    );
  }
}
