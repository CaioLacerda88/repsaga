import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device/platform_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/weekday_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar_tap_out_dismiss_scope.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../analytics/data/models/analytics_event.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../routines/models/routine.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../workouts/providers/workout_history_providers.dart';
import '../data/models/weekly_plan.dart';
import '../providers/weekly_engagement_provider.dart';
import '../providers/weekly_plan_provider.dart';
import 'add_routines_sheet.dart';
import 'widgets/bucket_routine_row.dart';
import 'widgets/engagement_explainer_sheet.dart';
import 'widgets/engajamento_section.dart';

/// Weekly plan editor screen at `/plan/week` (Phase 26e rewrite).
///
/// Single-scroll layout:
///   * "Esta semana" header + "N dias treinados" counter pill (unique
///     completion dates across the bucket).
///   * Ordered `BucketRoutineRow` list (planned / done-planned /
///     done-spontaneous states) inside a `ReorderableListView`.
///   * "+ Adicionar treino" CTA (drives [_showAddSheet]).
///   * Soft-cap warning text when the bucket size exceeds
///     `trainingFrequencyPerWeek`.
///   * Hairline + `EngajamentoSection` (6 muscle bars + ⓘ explainer).
///
/// Carries forward the debounce + undo + analytics scaffolding from the
/// previous `PlanManagementScreen` verbatim. The architectural change is
/// the layout, not the persistence path.
class WeekPlanScreen extends ConsumerStatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  ConsumerState<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends ConsumerState<WeekPlanScreen> {
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
  /// on-screen. While true, the "Saved" confirmation snackbar is
  /// suppressed so it can't hide-and-replace the undo affordance.
  bool _undoSnackbarActive = false;

  /// Whether a "Saved" confirmation snackbar is currently in its 1-second
  /// display window. Set true synchronously before `showSnackBar`; cleared
  /// via `controller.closed.whenComplete`. See
  /// `cluster_persist_eats_duration` + `cluster_async_caller_broke_snackbar`.
  bool _savedSnackbarActive = false;

  /// Captured notifier for debounced save. `ref` cannot be used in dispose(),
  /// so we hold the notifier directly, refreshed on each edit.
  WeeklyPlanNotifier? _debouncedPlanNotifier;

  @override
  void dispose() {
    // Flush any pending debounced save before tearing down.
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      // Fire-and-forget — dispose can't await (sync method), and the
      // user already navigated away. The flush logs its own errors via
      // debugPrint, and the `if (mounted)` guard inside short-circuits
      // the Saved-snackbar branch on the now-disposed State.
      unawaited(_flushDebouncedSave());
    }
    // Fire a single analytics event for the entire edit session, capturing
    // the most-recent flags (usedAutofill / replacedExisting).
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
    final engagementAsync = ref.watch(
      weeklyEngagementProvider(
        const WeeklyEngagementArgs(includePlanned: true),
      ),
    );

    final allRoutines = routinesAsync.value ?? [];
    final routineMap = <String, Routine>{for (final r in allRoutines) r.id: r};
    final trainingFrequency = profile.value?.trainingFrequencyPerWeek ?? 3;
    final overSoftCap = _bucketRoutines.length > trainingFrequency;

    // Counter pill counts UNIQUE completion days across the bucket. Two
    // bucket entries completed on the same day still count as 1 day
    // trained — matches the "days trained" verbiage and the mockup.
    final uniqueCompletionDays = _bucketRoutines
        .where((r) => r.completedAt != null)
        .map(
          (r) => DateTime(
            r.completedAt!.year,
            r.completedAt!.month,
            r.completedAt!.day,
          ),
        )
        .toSet()
        .length;

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'weekly-plan-title',
          child: Text(l10n.thisWeeksPlan),
        ),
        actions: [
          _OverflowMenu(
            onClear: () => _confirmClear(context),
            onAutoFill: () => _autoFill(allRoutines, trainingFrequency),
          ),
        ],
      ),
      // SnackBarTapOutDismissScope hosts the screen-level Listener that
      // dismisses the routine-removed undo snack when the user taps
      // outside it. See `cluster_async_caller_broke_snackbar` +
      // `cluster_persist_eats_duration`.
      body: SnackBarTapOutDismissScope(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // "ESTA SEMANA" header + N-days-trained pill row.
            _WeekHeaderRow(
              title: l10n.thisWeek,
              counterLabel: l10n.daysTrainedCount(uniqueCompletionDays),
            ),
            // Bucket list — ReorderableListView in shrinkWrap mode so it
            // lives inside the outer ListView with the Engajamento section
            // beneath it.
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _bucketRoutines.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final bucket = _bucketRoutines[index];
                // bucket.routineId is nullable for spontaneous entries (see
                // Bug F / migration 00063). The ValueKey composes
                // routineId + order so two spontaneous entries don't
                // collide on `ValueKey(null)`.
                final routine = bucket.routineId == null
                    ? null
                    : routineMap[bucket.routineId];
                final rowContext = context;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(
                    '${bucket.routineId ?? 'spontaneous'}-${bucket.order}',
                  ),
                  index: index,
                  child: BucketRoutineRow(
                    routineId: bucket.routineId,
                    name: routine?.name ?? l10n.unknownRoutine,
                    isDone: bucket.completedWorkoutId != null,
                    isSpontaneous: bucket.isSpontaneous,
                    completionDayLabel: bucket.completedAt != null
                        ? WeekdayFormatter.shortDayLabel(
                            bucket.completedAt!,
                            l10n.localeName,
                            uppercase: false,
                          )
                        : null,
                    spontaneousLabel: l10n.spontaneousTag,
                    onOverflowTap: bucket.completedWorkoutId != null
                        ? null
                        : () => _removeRoutine(rowContext, index),
                  ),
                );
              },
            ),
            // "+ Adicionar treino" CTA.
            _AddWorkoutCta(
              label: l10n.addWorkout,
              onTap: () => _showAddSheet(allRoutines),
            ),
            // Soft-cap warning — only shown when the bucket count strictly
            // exceeds the user's weekly target. At-cap is the normal
            // steady state and does not need a warning.
            if (overSoftCap)
              _SoftCapWarning(label: l10n.softCapWarning(trainingFrequency)),
            const SizedBox(height: 16),
            // Engajamento section (hairline + 6 bars + ⓘ).
            engagementAsync.when(
              data: (engagement) => EngajamentoSection(
                engagement: engagement,
                headerLabel: l10n.weeklyEngagementHeader,
                infoIconSemanticsLabel: l10n.engagementExplainerTitle,
                legendDoneLabel: l10n.engagementLegendDone,
                legendPlannedLabel: l10n.engagementLegendPlanned,
                onInfoTap: () => EngagementExplainerSheet.show(
                  context,
                  title: l10n.engagementExplainerTitle,
                  body: l10n.engagementExplainerBody,
                ),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
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

  void _removeRoutine(BuildContext rowContext, int index) {
    final removed = _bucketRoutines[index];
    setState(() {
      _dirty = true;
      _bucketRoutines.removeAt(index);
      _renumber();
    });
    _savePlan(usedAutofill: false, replacedExisting: false);

    // Undo snackbar. `rowContext` is from the ReorderableListView's
    // itemBuilder, which sits INSIDE our `SnackBarTapOutDismissScope`
    // — required for `SnackBarTapOutDismissScope.of(...)` to resolve.
    if (rowContext.mounted) {
      final l10n = AppLocalizations.of(rowContext);
      _undoSnackbarActive = true;
      // showCountdownSnackBar pins `persist: false` (avoids the
      // `cluster_persist_eats_duration` trap) and threads the duration
      // through to the countdown widget.
      final controller = SnackBarTapOutDismissScope.of(rowContext)
          .showCountdownSnackBar(
            context: rowContext,
            message: l10n.routineRemoved,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: l10n.undo.toUpperCase(),
              onPressed: () {
                setState(() {
                  final safeIndex = index.clamp(0, _bucketRoutines.length);
                  _bucketRoutines.insert(safeIndex, removed);
                  _renumber();
                });
                _savePlan(usedAutofill: false, replacedExisting: false);
              },
            ),
          );
      controller.closed.whenComplete(() {
        if (mounted) _undoSnackbarActive = false;
      });
    }
  }

  Future<void> _showAddSheet(
    List<Routine> allRoutines, {
    Set<String> preSelectedRoutineIds = const <String>{},
  }) async {
    // PR 32c — picker no longer filters routines already in the bucket.
    // BucketRoutine is keyed on `(routineId, order)` not `routineId` alone,
    // so the data model already supports the same routine appearing on
    // multiple days. The previous filter was a UX gate that blocked users
    // with classic splits (Push Day Mon/Wed/Fri) from re-adding the same
    // routine. The full routine list now goes through; ordering is
    // controlled at the consumer (BucketRoutine.order assigned on insert).
    final result = await showModalBottomSheet<AddRoutinesSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddRoutinesSheet(
        availableRoutines: allRoutines,
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
        // Snapshot ids BEFORE pushing so we can identify the
        // freshly-created routine on return.
        final beforeIds = allRoutines.map((r) => r.id).toSet();
        await context.push<void>('/routines/create');
        if (!mounted) return;
        final refreshed = ref.read(routineListProvider).value ?? allRoutines;
        final newIds = refreshed
            .map((r) => r.id)
            .where((id) => !beforeIds.contains(id))
            .toSet();
        await _showAddSheet(
          refreshed,
          preSelectedRoutineIds: {...previouslySelectedIds, ...newIds},
        );
    }
  }

  /// Auto-fill the bucket with the user's most-started routines.
  Future<void> _autoFill(
    List<Routine> allRoutines,
    int trainingFrequency,
  ) async {
    if (allRoutines.isEmpty) return;

    final historyState = ref.read(workoutHistoryProvider);
    if (historyState.isLoading && !historyState.hasValue) return;

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

    final history = ref.read(workoutHistoryProvider).value?.workouts ?? [];
    final nameFrequency = <String, int>{};
    for (final workout in history) {
      nameFrequency[workout.name] = (nameFrequency[workout.name] ?? 0) + 1;
    }

    final ranked = [...allRoutines]
      ..sort((a, b) {
        final freqA = nameFrequency[a.name] ?? 0;
        final freqB = nameFrequency[b.name] ?? 0;
        if (freqB != freqA) return freqB.compareTo(freqA);
        return a.name.compareTo(b.name);
      });

    final count = trainingFrequency < ranked.length
        ? trainingFrequency
        : ranked.length;
    final selected = ranked.take(count).toList();

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
    // Cancel any pending debounced save BEFORE prompting. Otherwise an
    // edit-then-clear race writes the (now-discarded) bucket back to
    // Postgres ~300ms after the clear lands — the edit wins, the user's
    // "Clear Week" intent is silently overwritten. We also flush the
    // analytics-event flag so the deleted-then-clobbered edit doesn't
    // leave a `week_plan_saved` ghost in the funnel.
    _saveDebounce?.cancel();
    _pendingAnalyticsEvent = false;

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
    // L5 — same invalidate-on-local-mutation contract as `_savePlan`; clear
    // goes through `clearPlan()` instead of `upsertPlan()` so it needs its
    // own invalidate call. Per `cluster_optimistic_ui_vs_async_provider`.
    ref.invalidate(weeklyEngagementProvider);
    await ref.read(weeklyPlanProvider.notifier).clearPlan();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    context.pop();
  }

  /// Persist the current bucket state to Supabase and record that we owe an
  /// analytics event when the user finally leaves the screen.
  ///
  /// Per the analytics-debounce design carried over from PlanManagementScreen:
  /// the persistence call (upsertPlan) runs on every edit (debounced 300 ms),
  /// but the analytics event fires at most once per session at dispose.
  void _savePlan({required bool usedAutofill, required bool replacedExisting}) {
    _saveDebounce?.cancel();
    final notifier = ref.read(weeklyPlanProvider.notifier);
    _debouncedPlanNotifier = notifier;
    // L5.2 — Optimistic provider-state update: push `_bucketRoutines` to
    // `weeklyPlanProvider` SYNCHRONOUSLY so every consumer
    // (`weeklyEngagementProvider`, Home's bucket chips, anything else
    // watching the plan) sees the new bucket on the next frame instead of
    // waiting for the 300ms debounce + Supabase roundtrip (= 400-800ms
    // perceived latency for the bars to update).
    //
    // L5 (original) only invalidated the derived `weeklyEngagementProvider`
    // — but that provider reads `ref.watch(weeklyPlanProvider).value` which
    // hadn't changed yet, so the invalidate just re-fetched against a
    // stale source. The combined fix is "invalidate derived provider
    // + update source provider state". Cluster:
    // `cluster_optimistic_ui_vs_async_provider` — patterns 1 + 2 together.
    notifier.setOptimistic(_bucketRoutines);
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      // Fire-and-forget — Timer callback is synchronous; the flush
      // handles its own errors via debugPrint.
      unawaited(_flushDebouncedSave());
    });
    // Whole-family invalidate so every variant (`includePlanned: true`
    // from the editor + `false` from any future Stats surface) is dirtied
    // uniformly. Redundant for `weeklyEngagementProvider` (the
    // `ref.watch(weeklyPlanProvider)` reactivity above already triggers
    // its rebuild) but kept as defense-in-depth for any future autoDispose
    // variant that may have been disposed between edits.
    ref.invalidate(weeklyEngagementProvider);
    _pendingAnalyticsEvent = true;
    // Sticky-OR: if any edit in the session used autofill or replaced an
    // existing plan, the dispose-time event records that.
    _lastUsedAutofill = _lastUsedAutofill || usedAutofill;
    _lastReplacedExisting = _lastReplacedExisting || replacedExisting;
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
  /// PR 33c finding-009 — async/await + explicit `try/catch` so the
  /// failure path surfaces in `adb logcat` via `debugPrint` instead of
  /// being swallowed silently. The pre-fix `.then().catchError((_) {})`
  /// chain logged nothing, leaving production debugging blind to user
  /// reports of "I edited my plan and nothing saved". The Saved-snackbar
  /// branch retains its own `if (mounted)` guard inside
  /// [_maybeShowSavedSnackbar]; the explicit guard here is belt-and-
  /// braces in case the helper is ever inlined.
  ///
  /// Cluster: `async-caller-broke-snackbar`. Fire-and-forget at every
  /// caller — `dispose()` and the debounce timer both kick this off
  /// without awaiting; the explicit `Future<void>` return type makes
  /// the async-ness visible at the call site for future readers.
  Future<void> _flushDebouncedSave() async {
    final notifier = _debouncedPlanNotifier;
    if (notifier == null) return;
    try {
      await notifier.upsertPlan(_bucketRoutines);
      if (mounted) _maybeShowSavedSnackbar();
    } catch (e) {
      // The offline banner already covers persistence failures from the
      // user's point of view; the log line is so the team can correlate
      // a support report with the underlying Supabase error.
      debugPrint('[WeekPlanScreen] flush save failed: $e');
    }
  }

  /// Shows the "Saved" confirmation snackbar IF still mounted AND no undo
  /// snackbar is active AND no Saved snack is already in its window. See
  /// `cluster_persist_eats_duration` for the persist:false trap and
  /// `cluster_async_caller_broke_snackbar` for the await-before-read rule
  /// (we await `upsertPlan` via `.then` before showing the snack — never
  /// before persistence has actually committed).
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
    controller.closed.whenComplete(() {
      if (mounted) _savedSnackbarActive = false;
    });
  }

  /// Fire the debounced `week_plan_saved` analytics event exactly once.
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

/// AppBar overflow menu — "Auto-fill" + "Clear week" actions. The screen wires
/// the two callbacks; this widget only presents the menu.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.onClear, required this.onAutoFill});

  final VoidCallback onClear;
  final VoidCallback onAutoFill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'weekly-plan-overflow',
      label: l10n.moreOptions,
      child: PopupMenuButton<String>(
        tooltip: l10n.moreOptions,
        onSelected: (value) {
          if (value == 'clear') onClear();
          if (value == 'autofill') onAutoFill();
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
    );
  }
}

/// "ESTA SEMANA" header row — the uppercase week label on the left and the
/// N-days-trained [_CounterPill] on the right. Both strings are resolved by
/// the screen layer and passed in.
class _WeekHeaderRow extends StatelessWidget {
  const _WeekHeaderRow({required this.title, required this.counterLabel});

  final String title;
  final String counterLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: AppTextStyles.label.copyWith(
              letterSpacing: 1.2,
              color: AppColors.textDim,
            ),
          ),
          const Spacer(),
          _CounterPill(label: counterLabel),
        ],
      ),
    );
  }
}

/// Left-aligned "+ Adicionar treino" CTA below the bucket list.
class _AddWorkoutCta extends StatelessWidget {
  const _AddWorkoutCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          button: true,
          identifier: 'weekly-plan-add-workout',
          child: InkWell(
            key: const ValueKey('weekly-plan-add-workout'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.hotViolet,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft-cap warning shown when the bucket count strictly exceeds the user's
/// weekly training target. The composed warning string is resolved by the
/// screen layer and passed in.
class _SoftCapWarning extends StatelessWidget {
  const _SoftCapWarning({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Semantics(
        container: true,
        identifier: 'weekly-plan-soft-cap-warning',
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.warning),
        ),
      ),
    );
  }
}

/// Right-aligned counter pill at the top of the plan editor. Shows the
/// "N dias treinados" copy resolved by the screen layer (so this widget
/// stays presentation-pure).
class _CounterPill extends StatelessWidget {
  const _CounterPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      identifier: 'weekly-plan-counter',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            fontSize: 10,
            letterSpacing: 0.12 * 10,
            color: AppColors.textCream,
          ),
        ),
      ),
    );
  }
}
