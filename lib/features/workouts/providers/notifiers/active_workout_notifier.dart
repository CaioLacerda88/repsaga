import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/device/platform_info.dart';
import '../../../../core/exceptions/app_exception.dart' as app;
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/local_storage/cache_service.dart';
import '../../../../core/local_storage/hive_service.dart';
import '../../../../core/offline/pending_action.dart';
import '../../../../core/offline/pending_sync_provider.dart';
import '../../../../core/offline/sync_error_classifier.dart';
import '../../../../core/observability/sentry_report.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../personal_records/models/personal_record.dart';
import '../../../analytics/data/models/analytics_event.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../exercises/models/exercise.dart';
import '../../../exercises/providers/exercise_progress_provider.dart';
import '../../../personal_records/domain/pr_detection_service.dart';
import '../../../personal_records/providers/pr_providers.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../../rpg/domain/celebration_event_builder.dart';
import '../../../rpg/domain/celebration_queue.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/providers/earned_titles_provider.dart';
import '../../../rpg/providers/rpg_progress_provider.dart';
import '../../../weekly_plan/providers/weekly_plan_provider.dart';
import '../../data/workout_local_storage.dart';
import '../../data/workout_repository.dart';
import '../../models/active_workout_state.dart';
import '../../models/cardio_session.dart';
import '../../models/exercise_set.dart';
import '../../models/routine_start_config.dart';
import '../../models/set_type.dart';
import '../../models/weight_unit.dart';
import '../../models/workout_exercise.dart';
import '../../utils/cardio_format.dart';
import '../../utils/set_defaults.dart';
import '../workout_providers.dart';

const _uuid = Uuid();

/// Locales we currently ship ARBs for. Kept local to this file rather than
/// centralized — `lookupAppLocalizations` throws on unrecognized codes, and
/// `_generateWorkoutName` is the only caller that needs to clamp defensively
/// (the rest of the app reads `AppLocalizations.of(context)` which already
/// resolves through Flutter's locale-resolution callback).
const _supportedWorkoutNameLocales = ['en', 'pt'];

/// Outcome of [ActiveWorkoutNotifier.finishWorkout].
///
/// Returned as a record (rather than read off a notifier field) so the
/// caller's data flow is explicit: a single `await finishWorkout()` returns
/// every value the screen needs to react. Restores unidirectional data
/// flow — UI no longer pokes at notifier internals (BUG-039).
///
/// `prResult` is null when PR detection ran but produced no records or
/// failed silently (PR detection is non-essential and never blocks the
/// save). `savedOffline` is `true` iff the network save threw a transient
/// error (offline / 5xx / timeout) and the workout was enqueued for offline
/// sync; UI uses it to render the "Will sync when back online" snackbar.
///
/// `serverErrorQueued` is `true` iff the queued failure was a server-side 5xx
/// (not a connectivity/timeout failure). When set, `savedOffline` is also
/// `true` — it is a discriminator on the queued path so the UI can render a
/// "server error — saved offline, will retry" message instead of the plain
/// "Will sync when back online" copy. Surfaces AW-EX-D-US1-03 (HTTP 500
/// silently treated as offline).
///
/// Terminal errors (4xx / RLS denial / FK violation) do NOT enqueue: they
/// rethrow inside `finishWorkout` so the outer `AsyncValue.guard` lands in
/// `AsyncError` and the coordinator's existing snackbar plumbing surfaces
/// the error. In that case `finishWorkout` itself returns `null` and the
/// notifier state is `AsyncError`.
typedef FinishWorkoutResult = ({
  PRDetectionResult? prResult,
  bool savedOffline,
  bool serverErrorQueued,
  // Phase 32 PR 32g (Bug 1) — surface the durationSeconds the notifier
  // computed against `DateTime.now().toUtc()` so the coordinator doesn't
  // recompute against `DateTime.now()` (local) and disagree by the device
  // UTC offset on every finish. The notifier is authoritative for the
  // workout timeline; downstream consumers read this single source of truth.
  // `null` means the save short-circuited before timing (offline save +
  // pre-commit, or the notifier guard returned null) — callers fall back
  // to 0 in that case.
  // Cluster: `async-caller-broke-snackbar` (extended).
  int? durationSeconds,
});

/// Core state machine for active workouts.
///
/// Manages the full lifecycle: start -> add exercises/sets -> finish or discard.
/// All mutations are persisted to Hive for crash recovery.
class ActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?> {
  late WorkoutRepository _repo;
  late WorkoutLocalStorage _localStorage;

  /// Re-entrance guard for [finishWorkout]. Prevents concurrent saves when
  /// the user double-taps "Finish Workout".
  bool _isFinishing = false;

  /// Re-entrance guard for [discardWorkout]. Prevents concurrent discards
  /// when Android back-button spam triggers multiple calls.
  bool _isDiscarding = false;

  /// Set by [cancelLoading] so that in-flight [finishWorkout] and
  /// [discardWorkout] futures skip the final `state =` assignment when they
  /// complete. Without this, the guard result overwrites the state restored
  /// by [cancelLoading], causing the workout to vanish unexpectedly.
  bool _cancelRequested = false;

  /// Stores the last valid [AsyncData] state so that [cancelLoading] can
  /// restore it if the user gives up waiting for a network operation.
  ActiveWorkoutState? _lastValidState;

  /// PR-4 / M3 — id-keyed map of original set positions captured at
  /// FIRST delete time. Used by [restoreSet] to insert a restored set at
  /// the position it occupied BEFORE any cascading renumbering.
  ///
  /// **Why a map and not a parameter on `restoreSet`:** the swipe-handler
  /// caller (`set_row.dart`'s `Dismissible.onDismissed`) captures the
  /// `ExerciseSet` it just deleted, but the `setNumber` field on that
  /// captured snapshot reflects the position AT TIME OF DELETION — which
  /// is post-renumbering for any cascading delete. Pre-fix, restoring a
  /// 4-set exercise via `delete #2 → delete #3 (renumbered to #2) →
  /// undo → undo` ended up `[1, 4, 3]` instead of `[1, 2, 3, 4]`. Pushing
  /// the original-index bookkeeping into the caller would force every
  /// future caller to re-derive the same map; keeping it on the notifier
  /// means the contract is "the notifier knows where to put it back."
  ///
  /// **Lifecycle:**
  ///   * `deleteSet` records the to-be-deleted set's CURRENT index, OR
  ///     the already-recorded-original-index if that id has been seen
  ///     in an earlier cascading delete (e.g. a set previously
  ///     restored-then-redeleted). This keeps the original position
  ///     stable across delete/undo/delete cycles.
  ///   * `restoreSet` reads the id, inserts at that position (clamped),
  ///     and removes the entry — once restored, future deletes record
  ///     a fresh current index.
  ///   * The map is purely UI-layer state; not persisted to Hive. A
  ///     hot-reload or process restart drops the map, which is fine —
  ///     by then the snackbar's 10s undo window has long since closed
  ///     and the user has moved on.
  final Map<String, int> _originalSetIndices = <String, int>{};

  /// Test-only window into [_originalSetIndices] for verifying lifecycle
  /// clearing (PR #202 review O1). Production code MUST NOT consume this
  /// — the map is internal bookkeeping owned by `deleteSet` / `restoreSet`
  /// and the lifecycle clear-points (`startWorkout`, `startFromRoutine`,
  /// `finishWorkout` post-commit, `discardWorkout` post-commit). Returns
  /// an unmodifiable view to prevent accidental mutation from tests.
  @visibleForTesting
  Map<String, int> get debugOriginalSetIndices =>
      Map<String, int>.unmodifiable(_originalSetIndices);

  @override
  FutureOr<ActiveWorkoutState?> build() {
    _repo = ref.watch(workoutRepositoryProvider);
    _localStorage = ref.watch(workoutLocalStorageProvider);
    return _localStorage.loadActiveWorkout();
  }

  /// Cancel an in-flight loading operation by settling the loading state.
  ///
  /// Used by the loading overlay's cancel button. The underlying network
  /// request continues in the background, but the UI is unblocked so the
  /// user can retry, discard, or navigate away. Resets re-entrance guards
  /// so the user can try again.
  ///
  /// Behavior depends on whether there is a prior valid state to restore:
  ///
  ///   * `_lastValidState != null` (mid-workout finish/discard cancel) →
  ///     restore that state. The user keeps their workout intact.
  ///   * `_lastValidState == null` (cancel during the very first
  ///     start-workout, before any valid state was ever captured) → emit
  ///     `AsyncData(null)`. The active-workout screen at
  ///     `active_workout_screen.dart:68` redirects to /home when the state
  ///     is settled-and-null, giving the user an escape hatch instead of a
  ///     permanent spinner (audit C4).
  ///
  /// `_cancelRequested` is unconditionally set to `true` so that any
  /// in-flight `startWorkout` / `startFromRoutine` / `finishWorkout` /
  /// `discardWorkout` future hits its post-guard cancel check on resume
  /// and skips the final `state = result` overwrite. Without this, a
  /// late-arriving `AsyncData(activeState)` (or `AsyncData(null)`) from
  /// the guard would clobber the state we just settled into here — and
  /// the screen's `postFrameCallback` redirect at
  /// `active_workout_screen.dart:68` only fires on settled-and-null, so
  /// any overwrite would silently suppress the C4 escape-hatch.
  ///
  /// All four call sites (`startWorkout`, `startFromRoutine`,
  /// `finishWorkout`, `discardWorkout`) reset `_cancelRequested` to
  /// `false` immediately after consuming it, so the flag never leaks
  /// across operations.
  void cancelLoading() {
    _isFinishing = false;
    _isDiscarding = false;
    _cancelRequested = true;
    if (_lastValidState != null) {
      // _lastValidState already carries `savedOffline: false` (reset at the
      // top of finishWorkout / discardWorkout) so restoring it naturally
      // resets the offline-queued flag without a separate field.
      state = AsyncData(_lastValidState);
    } else {
      // No valid state to restore → settle into AsyncData(null) so the
      // screen's `displayState == null && !asyncState.isLoading` branch
      // navigates back home (audit C4).
      state = const AsyncData(null);
    }
  }

  String get _userId {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      throw const app.AuthException('Not authenticated', code: 'no_session');
    }
    return user.id;
  }

  /// Single source of truth for the analytics `source` discriminator on
  /// every workout-lifecycle event (`workout_started`, `workout_finished`,
  /// `workout_discarded`).
  ///
  /// Keeps the four call sites (start / startFromRoutine / discard /
  /// finish) from drifting: a missed update at one site silently produced
  /// inconsistent analytics under the previous inline-ternary pattern.
  /// When a new entry-point lands (e.g. `'barcode_scan'`) it slots in
  /// here once and every event picks it up uniformly.
  ///
  /// Pass the [routineId] from the `ActiveWorkoutState` (or `config`) for
  /// the relevant call site; `null` means an empty / ad-hoc workout.
  String _workoutSource(String? routineId) {
    // TODO post-PR: differentiate `planned_bucket` when config exposes
    // the flag. Centralising the mapping here also centralises that
    // future expansion.
    return routineId != null ? 'routine_card' : 'empty';
  }

  /// Count of sets that are not yet completed.
  int get incompleteSetsCount {
    final current = state.value;
    if (current == null) return 0;
    return current.exercises
        .expand((e) => e.sets)
        .where((s) => !s.isCompleted)
        .length;
  }

  /// Total set count across all exercises — counts ONLY completed sets
  /// post-Bug-B filter (PR #261, reviewer Blocker 2). The empty-session
  /// guard at `finish_workout_coordinator.dart:96` reads this to decide
  /// whether to show State 11 modal vs route forward; the Bug-B save-site
  /// filter (L~1336) drops incomplete sets at persistence time, so
  /// counting planned sets here would let a user who taps Finish without
  /// completing any work bypass the guard and create a ghost history
  /// entry (RPC accepts empty arrays without error).
  ///
  /// Sequence the planned-count semantics broke:
  ///   1. `startFromRoutine` pre-populates `exercises` with all routine
  ///      exercises + planned `setCount` sets (`isCompleted: false`).
  ///   2. User taps "Finish" immediately without completing any set.
  ///   3. Pre-fix: `totalSetsCount` = N planned > 0 → guard does NOT
  ///      fire → coordinator routes forward → `_repo.saveWorkout(...)`
  ///      with `committedExercises = []` → ghost history entry.
  ///   4. Post-fix: `totalSetsCount` = 0 → guard fires → user is asked
  ///      to discard or continue logging.
  ///
  /// If a separate `plannedSetsCount` getter is needed for analytics or
  /// UI surfaces (none currently — grepped 2026-05-24), add it alongside.
  /// This getter pins the guard contract.
  ///
  /// IMPORTANT — lifecycle: returns 0 AFTER `finishWorkout()` is awaited,
  /// because the notifier transitions to `AsyncData(null)` on commit and
  /// this getter short-circuits on `state.value == null`. Callers that
  /// need the pre-finish set count in the post-finish path MUST capture
  /// the value BEFORE the `await notifier.finishWorkout()` call. See
  /// `finish_workout_coordinator.dart` (the `preFinishSetsCount` capture
  /// alongside `priorWorkoutCount`) for the established pattern, and
  /// auto-memory `cluster_async_caller_broke_snackbar.md` for the cluster.
  /// Phase 38b: completed CARDIO entries count as one unit of committable
  /// work each. Without this, a cardio-only session reads 0 and the
  /// empty-session guard blocks the finish — but a completed cardio entry
  /// IS real logged work (it persists to `cardio_sessions`); only its XP
  /// is deferred to 38c. The guard's intent is "did the user do anything
  /// worth saving", not "did the user earn XP".
  int get totalSetsCount {
    final current = state.value;
    if (current == null) return 0;
    final completedSets = current.exercises
        .expand((e) => e.sets)
        .where((s) => s.isCompleted)
        .length;
    final completedCardio = current.exercises
        .where((e) => e.cardioSession?.isCompleted ?? false)
        .length;
    return completedSets + completedCardio;
  }

  /// Start a new workout session.
  ///
  /// If [name] is omitted a date-based name is generated automatically,
  /// e.g. "Workout — Wed Apr 2".
  Future<void> startWorkout([String? name]) async {
    state = const AsyncLoading();
    _firstAwakeningFiredThisSession = false;
    _lastCelebration = null;
    _lastSessionTotalXpDelta = null;
    _lastSessionBpDeltas = const <BodyPart, num>{};
    _cancelRequested = false;
    // PR #202 review O1: clear cross-workout bookkeeping. The notifier
    // is keepAlive-by-default (plain AsyncNotifierProvider, no
    // .autoDispose), so the instance persists across
    // start/finish/discard cycles. Without explicit clearing, the
    // _originalSetIndices map would accumulate stale entries across
    // sessions — unbounded growth + a (UUID-improbable but possible) id
    // collision risk if the same set id ever recurred. Cleared at every
    // lifecycle entry point that opens a fresh workout context.
    _originalSetIndices.clear();
    final result = await AsyncValue.guard(() async {
      final userId = _userId;
      final workout = await _repo.createActiveWorkout(
        userId: userId,
        name: name ?? _generateWorkoutName(),
      );
      final activeState = ActiveWorkoutState(
        workout: workout,
        exercises: const [],
      );
      await _saveToHive(activeState);
      _trackWorkoutEvent(
        event: AnalyticsEvent.workoutStarted(
          // null: no routineId — empty ad-hoc workout, not started from
          // a saved routine. Resolves to source: 'empty'.
          source: _workoutSource(null),
          routineId: null,
          exerciseCount: 0,
        ),
        breadcrumbMessage: 'started empty workout',
        breadcrumbData: {'workout_id': workout.id},
      );
      return activeState;
    });

    if (_cancelRequested) {
      // Audit C4 reinforcement: cancelLoading() fired while the guard
      // future was still in-flight. cancelLoading() already settled the
      // state into AsyncData(null) (start-phase has no _lastValidState
      // to restore). A late-arriving guard success (or AsyncError) would
      // silently overwrite that null, and the screen's
      // postFrameCallback redirect at active_workout_screen.dart:68
      // only fires on settled-and-null, so any overwrite would suppress
      // the C4 escape-hatch.
      _cancelRequested = false;
      state = const AsyncData(null);
      return;
    }

    state = result;
  }

  /// Start a workout pre-populated from a routine template.
  Future<void> startFromRoutine(RoutineStartConfig config) async {
    state = const AsyncLoading();
    _firstAwakeningFiredThisSession = false;
    _lastCelebration = null;
    _lastSessionTotalXpDelta = null;
    _lastSessionBpDeltas = const <BodyPart, num>{};
    _cancelRequested = false;
    // PR #202 review O1: see startWorkout for rationale.
    _originalSetIndices.clear();
    final result = await AsyncValue.guard(() async {
      final userId = _userId;
      final workout = await _repo.createActiveWorkout(
        userId: userId,
        name: config.routineName,
      );

      // Fetch last-workout weights for pre-filling sets.
      final exerciseIds = config.exercises.map((e) => e.exerciseId).toList();
      final lastSets = await _repo.getLastWorkoutSets(exerciseIds);
      final weightUnitStr = ref.read(profileProvider).value?.weightUnit ?? 'kg';
      final weightUnit = WeightUnit.fromString(weightUnitStr);

      // Build exercises with pre-filled sets.
      final exercises = <ActiveWorkoutExercise>[];
      for (var i = 0; i < config.exercises.length; i++) {
        final re = config.exercises[i];
        final workoutExerciseId = _uuid.v4();

        final workoutExercise = WorkoutExercise(
          id: workoutExerciseId,
          workoutId: workout.id,
          exerciseId: re.exerciseId,
          order: i,
          restSeconds: re.restSeconds,
          exercise: re.exercise,
        );

        // Phase 38b — a routine containing a cardio exercise (the picker
        // has listed the 8 default cardio movements since 00014) seeds a
        // default CardioSession instead of `setCount` weight×reps slots.
        if (re.exercise.muscleGroup == MuscleGroup.cardio) {
          exercises.add(
            ActiveWorkoutExercise(
              workoutExercise: workoutExercise,
              sets: const [],
              cardioSession: _seedCardioSession(
                workoutId: workout.id,
                exerciseId: re.exerciseId,
                durationSeconds: re.targetDurationSeconds,
                distanceM: re.targetDistanceM,
              ),
            ),
          );
          continue;
        }

        // PR-4 / M1 — filter previous-session warmups before clamping.
        // Same Q2 contract as `_computeNewSetDefaults` Priority 1
        // (warmup sets are not performance data; FitNotes / Hevy benchmark).
        // Pre-fix the routine-start path indexed `previousSets` directly,
        // so a user whose previous session was `[warmup@40, warmup@60,
        // working@100]` got their routine pre-filled `[40, 60, 100,
        // 100, ...]` — set #1 of the routine started at warmup weight.
        // Filtering here keeps the routine path in lockstep with the
        // ad-hoc add-set path. Edge case: if ALL previous sets were
        // warmups, the filter returns empty so `prev` is null — weight
        // then falls through to the never-done 0 (see seed below) and
        // reps fall through to `equipDefaults.reps`.
        final previousSets = (lastSets[re.exerciseId] ?? const <ExerciseSet>[])
            .where((s) => s.setType != SetType.warmup)
            .toList(growable: false);
        final equipDefaults = defaultSetValues(
          re.exercise.equipmentType,
          weightUnit,
        );
        final sets = List.generate(re.setCount, (setIndex) {
          // Use the matching previous WORKING set, or the last previous
          // working set if fewer. Warmup-only previous sessions short-
          // circuit to equipment defaults via the null-coalescing chain.
          final prev = previousSets.isNotEmpty
              ? previousSets[setIndex < previousSets.length
                    ? setIndex
                    : previousSets.length - 1]
              : null;

          return ExerciseSet(
            id: _uuid.v4(),
            workoutExerciseId: workoutExerciseId,
            setNumber: setIndex + 1,
            // Weight precedence: target → last-lifted → 0. The final 0 (NOT
            // equipDefaults.weight) is deliberate — kill the "nebulous"
            // equipment-default weight for a never-done lift and force a
            // conscious entry (user-approved 2026-06-20). Do not restore
            // equipDefaults.weight here. Reps keep the equipment default
            // (a 0-rep set is a non-set).
            weight: re.targetWeight ?? prev?.weight ?? 0,
            reps: re.targetReps ?? prev?.reps ?? equipDefaults.reps,
            setType: SetType.working,
            isCompleted: false,
            createdAt: DateTime.now().toUtc(),
          );
        });

        exercises.add(
          ActiveWorkoutExercise(workoutExercise: workoutExercise, sets: sets),
        );
      }

      final activeState = ActiveWorkoutState(
        workout: workout,
        exercises: exercises,
        routineId: config.routineId,
        // Q2: carry the source routine's notes onto the state so the
        // active-workout screen renders them read-only. Survives crash-recovery
        // rehydration via the Hive JSON round-trip alongside routineId.
        routineNotes: config.routineNotes,
      );
      await _saveToHive(activeState);
      _trackWorkoutEvent(
        event: AnalyticsEvent.workoutStarted(
          source: _workoutSource(config.routineId),
          routineId: config.routineId,
          exerciseCount: config.exercises.length,
        ),
        breadcrumbMessage: 'started workout from routine',
        breadcrumbData: {
          'workout_id': workout.id,
          'routine_id': config.routineId,
        },
      );
      return activeState;
    });

    if (_cancelRequested) {
      // Mirrors the post-guard check in [startWorkout]. cancelLoading()
      // already settled into AsyncData(null); a late-arriving guard
      // success must not resurrect the workout, otherwise the screen
      // never sees the settled-and-null state needed for the C4
      // postFrameCallback redirect to /home.
      _cancelRequested = false;
      state = const AsyncData(null);
      return;
    }

    state = result;
  }

  /// Rename the active workout in-memory and persist to Hive.
  Future<void> renameWorkout(String name) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(workout: current.workout.copyWith(name: name)),
    );
    await _saveToHive(state.value!);
  }

  /// Generates a default workout name using the user's CURRENT locale.
  ///
  /// Locale is read at GENERATION TIME via `ref.read(localeProvider)` and
  /// then frozen into the persisted workout name \u2014 the name is stored
  /// data, not a display-only string, so it must remain stable regardless
  /// of any LATER locale switch. A user who starts a workout under pt-BR
  /// sees `'Treino \u2014 qua 7 mai'` and continues to see that string forever,
  /// even if they later switch the app to en. Conversely a user on en
  /// gets `'Workout \u2014 Wed May 7'`.
  ///
  /// Pre-fix (Family 6 \u2014 AW-EX-F-BR1-02) the prefix and date format were
  /// hard-coded English: `'Workout \u2014 '` + `DateFormat('EEE MMM d')`. A
  /// pt-BR user starting an empty workout saw English text on the
  /// AppBar \u2014 the most visible i18n leak on the active-workout surface.
  String _generateWorkoutName() {
    final now = DateTime.now();
    final languageCode = ref.read(localeProvider).languageCode;
    // Fallback to en if a future locale slips through before its ARB lands.
    // lookupAppLocalizations throws on unrecognized codes, and we don't want
    // startWorkout to fail silently into AsyncError because of locale state.
    final clampedCode = _supportedWorkoutNameLocales.contains(languageCode)
        ? languageCode
        : 'en';
    final l10n = lookupAppLocalizations(Locale(clampedCode));
    final formatted = DateFormat('EEE MMM d', clampedCode).format(now);
    return l10n.workoutDefaultName(formatted);
  }

  /// Add an exercise to the active workout.
  ///
  /// **Phase 23 D6 — auto-seed set 1** with the user's last-session
  /// working values. Mirrors the routine-start pre-fill (see
  /// [startFromRoutine] above L341-370) so the two entry points are in
  /// lockstep: a user who adds bench press mid-workout gets the same
  /// pre-filled weight/reps they would have gotten from a routine
  /// containing bench press.
  ///
  /// **Fallback chain:**
  ///   1. Previous session's WORKING sets (warmups filtered out per
  ///      Phase 22 Q2 — FitNotes/Hevy treat warmups as non-performance
  ///      data). Take the set with the lowest `setNumber` (the "set 1"
  ///      match); if none, fall back to the LAST working set's values.
  ///   2. Never-done fallback when there's no prior data — or when prior
  ///      data contained ONLY warmups: WEIGHT seeds 0 (kill the nebulous
  ///      equipment default; user-approved 2026-06-20), REPS seed the
  ///      equipment default via [defaultSetValues].
  ///
  /// Bodyweight exercises (`EquipmentType.bodyweight`) skip weight on
  /// the prior-data path (`weight = 0` falls out naturally from the
  /// equipment-defaults table). The seeded set is marked
  /// `setType: working`, `isCompleted: false`, `setNumber: 1`, with a
  /// fresh client UUID.
  ///
  /// **Call-site map** (verified 2026-05-12): `addExercise` is invoked
  /// from EXACTLY ONE place — `_ActiveWorkoutBody._onAddExercise` in
  /// `active_workout_screen.dart`. The routine-start path uses
  /// [startFromRoutine] which has its own pre-fill loop. No double-seed
  /// risk.
  Future<void> addExercise(Exercise exercise) async {
    final current = state.value;
    if (current == null) return;

    final workoutExerciseId = _uuid.v4();
    final workoutExercise = WorkoutExercise(
      id: workoutExerciseId,
      workoutId: current.workout.id,
      exerciseId: exercise.id,
      order: current.exercises.length,
      exercise: exercise,
    );

    // Phase 38b — cardio entries carry no weight×reps sets. Seed a default
    // CardioSession (30:00, no distance, no RPE) instead of a set 1 so the
    // CardioEntryCard renders the locked "Empty (default)" state.
    final ActiveWorkoutExercise newEntry;
    if (exercise.muscleGroup == MuscleGroup.cardio) {
      newEntry = ActiveWorkoutExercise(
        workoutExercise: workoutExercise,
        sets: const [],
        cardioSession: _seedCardioSession(
          workoutId: current.workout.id,
          exerciseId: exercise.id,
        ),
      );
    } else {
      final seededSet = await _seedFirstSetForAddedExercise(
        workoutExerciseId: workoutExerciseId,
        exercise: exercise,
      );
      newEntry = ActiveWorkoutExercise(
        workoutExercise: workoutExercise,
        sets: [seededSet],
      );
    }

    final newState = current.copyWith(
      exercises: [...current.exercises, newEntry],
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Fresh cardio entry (Phase 38b): the mandatory duration starts at
  /// [durationSeconds] (defaults to 30:00 — the locked empty-state); distance
  /// seeds from [distanceM] (null → empty `+ adicionar` ghost), RPE always
  /// starts empty.
  ///
  /// The start-from-routine path passes the routine's cardio target so a
  /// "28:00 / 5km" routine prefills the run; the add-from-picker and
  /// swap paths pass nothing and get the 30:00 default + empty distance.
  CardioSession _seedCardioSession({
    required String workoutId,
    required String exerciseId,
    int? durationSeconds,
    double? distanceM,
  }) {
    return CardioSession(
      id: _uuid.v4(),
      workoutId: workoutId,
      exerciseId: exerciseId,
      durationSeconds: durationSeconds ?? kDefaultCardioDurationSeconds,
      distanceM: distanceM,
      isCompleted: false,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// Builds the auto-seeded set 1 for [addExercise].
  ///
  /// Pure-ish helper: depends on the repository (`getLastWorkoutSets`)
  /// and on the user's current `weightUnit`, but does NOT mutate notifier
  /// state. Returns the [ExerciseSet] the caller should slot into the new
  /// [ActiveWorkoutExercise].
  ///
  /// Failure of the network fetch is treated as "no prior data" — the
  /// never-done fallback kicks in (weight 0, equipment-default reps). We
  /// never block add-exercise on a network failure; the user must always
  /// be able to add an exercise mid-workout even when offline.
  Future<ExerciseSet> _seedFirstSetForAddedExercise({
    required String workoutExerciseId,
    required Exercise exercise,
  }) async {
    final weightUnitStr = ref.read(profileProvider).value?.weightUnit ?? 'kg';
    final weightUnit = WeightUnit.fromString(weightUnitStr);

    Map<String, List<ExerciseSet>> lastSetsByExercise = const {};
    try {
      lastSetsByExercise = await _repo.getLastWorkoutSets([exercise.id]);
    } catch (_) {
      // Pre-fill is a UX nicety, never a blocker. A repo error here
      // (offline, transient 5xx) just falls through to the equipment
      // defaults below.
    }

    final priorWorkingSets =
        (lastSetsByExercise[exercise.id] ?? const [])
            .where((s) => s.setType != SetType.warmup)
            .toList(growable: false)
          // Match routine-start: choose the lowest setNumber as the "set 1"
          // anchor. The repo's natural ordering already does this, but pin
          // it locally so a future repo change can't silently flip the
          // anchor.
          ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

    double? seedWeight;
    int? seedReps;

    if (priorWorkingSets.isNotEmpty) {
      // Priority 1 — the lowest-numbered working set IS the set-1 match.
      // If only set 2+ working data exists (uncommon — implies set 1 was
      // a warmup), the .sort above still picks the smallest available
      // setNumber which is the closest analog to "the first working set
      // I did last time."
      final anchor = priorWorkingSets.first;
      seedWeight = anchor.weight;
      seedReps = anchor.reps;
    }

    if (seedWeight == null || seedReps == null) {
      // Priority 2 — never-done fallback. Covers: no prior data at all,
      // OR prior session was ALL warmups (the .where filter above
      // returned empty). Weight seeds 0; reps seed the equipment default.
      final equipDefaults = defaultSetValues(
        exercise.equipmentType,
        weightUnit,
      );
      // Weight precedence at the add-exercise path: last-lifted → 0 (no routine
      // target on this path). The final 0 (NOT equipDefaults.weight) is
      // deliberate — kill the "nebulous" equipment-default weight for a
      // never-done lift and force a conscious entry (user-approved 2026-06-20).
      // Do not restore equipDefaults.weight here. Reps keep the equipment
      // default (a 0-rep set is a non-set).
      seedWeight ??= 0;
      seedReps ??= equipDefaults.reps;
    }

    return ExerciseSet(
      id: _uuid.v4(),
      workoutExerciseId: workoutExerciseId,
      setNumber: 1,
      weight: seedWeight,
      reps: seedReps,
      setType: SetType.working,
      isCompleted: false,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// Remove an exercise and reorder remaining exercises.
  Future<void> removeExercise(String workoutExerciseId) async {
    final current = state.value;
    if (current == null) return;

    final filtered = current.exercises
        .where((e) => e.workoutExercise.id != workoutExerciseId)
        .toList();

    // Reorder remaining exercises.
    final reordered = filtered.indexed
        .map(
          (entry) => entry.$2.copyWith(
            workoutExercise: entry.$2.workoutExercise.copyWith(order: entry.$1),
          ),
        )
        .toList();

    final newState = current.copyWith(exercises: reordered);
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Undo a just-added exercise (PR-3 H5).
  ///
  /// Mirrors [removeExercise] in shape — takes the [workoutExerciseId] handle
  /// the picker just minted, drops it from the active workout, reorders the
  /// remainder, and persists. Idempotent: if the id is not present (e.g. the
  /// user already removed it manually before tapping Undo) the call is a
  /// no-op so a stale snackbar tap can't corrupt state.
  ///
  /// Scoped to the ADD-from-picker undo path. Swap-from-picker has its own
  /// confirm dialog ([SwapExerciseConfirmDialog]) and shares no state with
  /// this method.
  Future<void> restoreExercise(String workoutExerciseId) async {
    return removeExercise(workoutExerciseId);
  }

  /// Add a new empty set to an exercise.
  ///
  /// Optional [defaultWeight] and [defaultReps] pre-fill the new set
  /// (e.g. from the previous workout session).
  Future<void> addSet(
    String workoutExerciseId, {
    double? defaultWeight,
    int? defaultReps,
  }) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        final newSet = ExerciseSet(
          id: _uuid.v4(),
          workoutExerciseId: workoutExerciseId,
          setNumber: e.sets.length + 1,
          weight: defaultWeight ?? 0,
          reps: defaultReps ?? 0,
          setType: SetType.working,
          isCompleted: false,
          createdAt: DateTime.now().toUtc(),
        );

        return e.copyWith(sets: [...e.sets, newSet]);
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Update fields on a specific set.
  Future<void> updateSet(
    String workoutExerciseId,
    String setId, {
    double? weight,
    int? reps,
    int? rpe,
    SetType? setType,
    String? notes,
  }) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        return e.copyWith(
          sets: e.sets.map((s) {
            if (s.id != setId) return s;
            return s.copyWith(
              weight: weight ?? s.weight,
              reps: reps ?? s.reps,
              rpe: rpe ?? s.rpe,
              setType: setType ?? s.setType,
              notes: notes ?? s.notes,
            );
          }).toList(),
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Update a set's weight AND propagate the change forward to subsequent
  /// not-yet-completed sets that share the OLD weight ("follow the leader
  /// while still in formation").
  ///
  /// Common case the user hits: tapping `+` on set 1 to dial in working
  /// weight from 0 → 20kg, while sets 2 and 3 are still at 0kg. Without
  /// propagation the user has to repeat every tap on each subsequent set.
  /// Propagation walks forward from the leader and updates each follower
  /// whose weight matches the OLD value AND that is not yet completed.
  ///
  /// Contract:
  ///   * The leader set's weight is updated **by this method itself** —
  ///     callers must NOT also call [updateSet] for the same change. Doing
  ///     so produces two sequential emissions instead of one and rebuilds
  ///     every set row in the exercise twice.
  ///   * Sets BEFORE the leader (lower setNumber) are never touched.
  ///   * For each set AFTER the leader: if it is completed → stop the walk
  ///     (completed sets are immutable; we also don't blindly leapfrog them
  ///     because the user explicitly anchored their session at that set).
  ///   * Otherwise: if the set's weight equals the leader's OLD weight,
  ///     update it; if not, the set has been customized — leave it and stop
  ///     the walk (the customization marks the end of the formation).
  ///   * Reps are NEVER touched. Reps come from the routine prescription;
  ///     propagating them would silently overwrite the user's prescription
  ///     across all subsequent sets.
  ///
  /// Emits a single [AsyncData] for the entire update. UI animations that
  /// distinguish "I tapped this" from "the app inferred this" rely on the
  /// caller knowing which set ids were updated; the screen owns that signal
  /// and we keep this method side-effect-free except for the state
  /// emission + Hive persist.
  Future<void> propagateWeight(
    String workoutExerciseId,
    String fromSetId,
    double oldWeight,
    double newWeight,
  ) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        // Locate the leader by id. If absent (deleted between tap and this
        // call), bail without touching anything.
        final leaderIndex = e.sets.indexWhere((s) => s.id == fromSetId);
        if (leaderIndex < 0) return e;

        final newSets = <ExerciseSet>[];
        for (var i = 0; i < e.sets.length; i++) {
          final s = e.sets[i];
          if (i < leaderIndex) {
            // Sets BEFORE the leader are never touched.
            newSets.add(s);
            continue;
          }
          if (i == leaderIndex) {
            // Leader: always updated to the new weight.
            newSets.add(s.copyWith(weight: newWeight));
            continue;
          }
          // After the leader: walk forward. Stop the walk when we hit a
          // completed set OR an UNINITIALIZED follower (`weight: null`)
          // OR a customized weight; everything from that point on stays
          // as-is.
          if (s.isCompleted) {
            newSets.addAll(e.sets.sublist(i));
            break;
          }
          // PR-4 / M2 — distinguish `null` follower weight from `0`. The
          // pre-fix expression `(s.weight ?? 0) != oldWeight` collapsed
          // null to 0, so when `oldWeight == 0` (e.g. the user first
          // dialled in a working weight on the leader) and a follower
          // had `weight: null` (uninitialized — e.g. routine-prefilled
          // with no weight history), the walk overwrote it. That can
          // produce a false PR if the propagated value beats the
          // user's true history. A `null`-weighted follower is
          // semantically "not yet set" / "customized" and ENDS the
          // formation walk. Explicit nullable read makes the contract
          // visible.
          final followerWeight = s.weight;
          if (followerWeight == null) {
            newSets.addAll(e.sets.sublist(i));
            break;
          }
          if (followerWeight != oldWeight) {
            newSets.addAll(e.sets.sublist(i));
            break;
          }
          newSets.add(s.copyWith(weight: newWeight));
        }
        return e.copyWith(sets: newSets);
      }).toList(),
    );

    // SINGLE emission for the entire propagation.
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Toggle the completion status of a set.
  Future<void> completeSet(String workoutExerciseId, String setId) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        return e.copyWith(
          sets: e.sets.map((s) {
            if (s.id != setId) return s;
            return s.copyWith(isCompleted: !s.isCompleted);
          }).toList(),
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Update fields on a cardio entry (Phase 38b).
  ///
  /// Mirrors [updateSet]'s null-coalescing contract: a null parameter means
  /// "leave unchanged" — the UI dialogs always supply a concrete value, so
  /// no clear-to-null sentinel is needed in v1. No-op when the targeted
  /// exercise has no cardio session (defensive — the CardioEntryCard only
  /// renders for entries that carry one).
  Future<void> updateCardioSession(
    String workoutExerciseId, {
    int? durationSeconds,
    double? distanceM,
    int? rpe,
  }) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;
        final session = e.cardioSession;
        if (session == null) return e;
        return e.copyWith(
          cardioSession: session.copyWith(
            durationSeconds: durationSeconds ?? session.durationSeconds,
            distanceM: distanceM ?? session.distanceM,
            rpe: rpe ?? session.rpe,
          ),
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Toggle the completion state of a cardio entry (Phase 38b).
  ///
  /// Mirrors [completeSet]. The card's done CTA completes; tapping the
  /// green ✓ in the collapsed header un-completes (back to editable).
  Future<void> completeCardioEntry(String workoutExerciseId) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;
        final session = e.cardioSession;
        if (session == null) return e;
        return e.copyWith(
          cardioSession: session.copyWith(isCompleted: !session.isCompleted),
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Delete a set and renumber the remaining sets.
  ///
  /// **PR-4 / M3 — original-index bookkeeping.** Before mutating the
  /// list, captures the to-be-deleted set's CURRENT index into
  /// [_originalSetIndices] so a later [restoreSet] can put it back
  /// where it started. If the same id has been seen in an earlier
  /// cascading delete (e.g. a previously restored-then-redeleted set),
  /// the existing original index is preserved — the user's intent for
  /// that set's "home position" is the FIRST position the notifier ever
  /// observed it at, not its position after intermediate renumbering.
  Future<void> deleteSet(String workoutExerciseId, String setId) async {
    final current = state.value;
    if (current == null) return;

    // M3: capture the original index BEFORE renumbering. Look up the
    // current index in the targeted exercise; if we don't already have
    // a recorded original (the common case for a fresh delete) record
    // it now. If we DO have one (the set was previously deleted +
    // restored + re-deleted within this session), keep the older
    // recording — the user's "home position" intent is the first one.
    final exercise = current.exercises
        .where((e) => e.workoutExercise.id == workoutExerciseId)
        .firstOrNull;
    if (exercise != null) {
      final currentIndex = exercise.sets.indexWhere((s) => s.id == setId);
      if (currentIndex >= 0) {
        _originalSetIndices.putIfAbsent(setId, () => currentIndex);
      }
    }

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        final filtered = e.sets.where((s) => s.id != setId).toList();
        final renumbered = filtered.indexed
            .map((entry) => entry.$2.copyWith(setNumber: entry.$1 + 1))
            .toList();

        return e.copyWith(sets: renumbered);
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Restore a previously deleted set at its ORIGINAL position.
  ///
  /// Inserts the [deletedSet] back into the exercise's set list and
  /// renumbers all sets sequentially. Used for undo-delete (the
  /// SnackBar action fired by `set_row.dart`'s `Dismissible.onDismissed`).
  ///
  /// **PR-4 / M3 — restore by original index, not by `deletedSet.setNumber`.**
  /// Pre-fix the insertion position was derived from `deletedSet.setNumber`,
  /// which reflects the position at TIME OF DELETION — already-renumbered
  /// for any cascading delete. So `delete #2 → delete #3 (renumbered to #2)
  /// → undo → undo` ended up `[1, 4, 3]` instead of `[1, 2, 3, 4]`. The
  /// fix is to consult [_originalSetIndices], an id-keyed map that
  /// [deleteSet] populates at first-delete time. The map survives
  /// cascading delete + cascading undo because it's keyed by stable set
  /// id (UUID), not by position.
  ///
  /// Falls back to `(deletedSet.setNumber - 1)` when the id isn't in
  /// the map — preserves the legacy behaviour for any caller that
  /// might restore a set the notifier never saw deleted (e.g. a future
  /// "import set" code path; doesn't exist today). Robust to both
  /// patterns; the production swipe-handler path always populates the
  /// map.
  Future<void> restoreSet(
    String workoutExerciseId,
    ExerciseSet deletedSet,
  ) async {
    final current = state.value;
    if (current == null) return;

    // M3: prefer the originally-recorded position; fall back to the
    // captured setNumber for any caller that didn't go through deleteSet.
    final originalIndex = _originalSetIndices[deletedSet.id];

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        final sets = [...e.sets];
        // Clamp to list bounds in case the exercise has fewer sets
        // than when the original delete happened (e.g. additional
        // deletes after the restore was queued).
        final insertIndex = (originalIndex ?? (deletedSet.setNumber - 1)).clamp(
          0,
          sets.length,
        );
        sets.insert(insertIndex, deletedSet);

        // Renumber all sets sequentially.
        final renumbered = sets.indexed
            .map((entry) => entry.$2.copyWith(setNumber: entry.$1 + 1))
            .toList();

        return e.copyWith(sets: renumbered);
      }).toList(),
    );

    state = AsyncData(newState);
    await _saveToHive(newState);

    // Drop the bookkeeping entry AFTER the Hive persist completes — once
    // restored, future deletes of this id capture a fresh current index.
    //
    // PR #202 review S1: moved this `remove` to AFTER `_saveToHive` so
    // that a Hive write failure leaves the entry intact. If we removed
    // first and persist threw, a subsequent restoreSet on the same id
    // would silently fall back to `deletedSet.setNumber - 1` (the legacy
    // path) — a subtle correctness regression for the delete-restore-
    // -redelete edge case. The post-write removal keeps the map in lock-
    // step with what was actually persisted: if the write failed the
    // user retains the ability to re-attempt the restore against the
    // same recorded original index.
    _originalSetIndices.remove(deletedSet.id);
  }

  /// Copy weight and reps from the previous set into the given set.
  Future<void> copyLastSet(String workoutExerciseId, String setId) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        final targetIndex = e.sets.indexWhere((s) => s.id == setId);
        if (targetIndex <= 0) return e; // no previous set or not found

        final previous = e.sets[targetIndex - 1];
        final updated = e.sets[targetIndex].copyWith(
          weight: previous.weight,
          reps: previous.reps,
        );

        return e.copyWith(
          sets: [
            ...e.sets.sublist(0, targetIndex),
            updated,
            ...e.sets.sublist(targetIndex + 1),
          ],
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Fill ALL incomplete sets with the most-recent completed set's values.
  ///
  /// Option C (First-Complete Trigger): the fill is non-directional — every
  /// `!isCompleted` set is filled,
  /// whether its `setNumber` is above OR below the completed set that supplies
  /// the values. The source values come from the most recent completed set
  /// (highest `setNumber` among completed). This unblocks mid-session restart,
  /// failed-set-1, and out-of-order logging, where the user ticks the last (or
  /// a middle) set first and expects the earlier sets to back-fill.
  Future<void> fillRemainingSets(String workoutExerciseId) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        // Source values: the most recent completed set (highest setNumber).
        ExerciseSet? lastCompleted;
        for (final s in e.sets) {
          if (s.isCompleted) {
            if (lastCompleted == null ||
                s.setNumber > lastCompleted.setNumber) {
              lastCompleted = s;
            }
          }
        }
        if (lastCompleted == null) return e;

        // Bind a final non-nullable local AFTER the guard. `lastCompleted` is a
        // non-final captured variable, so flow-promotion doesn't carry across
        // the inner closure boundary — reading it there would otherwise force a
        // `!` on every access. Promoting once here makes BOTH the weight and
        // reps reads symmetric, non-null, and resilient to future edits that
        // might add another field read (no per-line `!` to remember). The
        // analyzer rejects redundant `!`, so a final local is the explicit-
        // contract way to honour the "don't rely on flow-promotion" intent.
        final source = lastCompleted;

        return e.copyWith(
          sets: e.sets.map((s) {
            // Fill every incomplete set regardless of position — the old
            // `setNumber > lastCompleted.setNumber` directional guard was the
            // bug that hid earlier sets from back-filling.
            if (!s.isCompleted) {
              return s.copyWith(
                weight: source.weight,
                reps: source.reps,
                isCompleted: true,
              );
            }
            return s;
          }).toList(),
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Reorder an exercise by swapping it with its neighbour.
  ///
  /// [direction] must be -1 (move up) or +1 (move down).
  Future<void> reorderExercise(String workoutExerciseId, int direction) async {
    assert(direction == -1 || direction == 1, 'direction must be -1 or 1');
    final current = state.value;
    if (current == null) return;

    final exercises = [...current.exercises];
    final index = exercises.indexWhere(
      (e) => e.workoutExercise.id == workoutExerciseId,
    );
    if (index < 0) return;

    final targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= exercises.length) return;

    // Swap order fields.
    final a = exercises[index];
    final b = exercises[targetIndex];
    exercises[index] = b.copyWith(
      workoutExercise: b.workoutExercise.copyWith(order: index),
    );
    exercises[targetIndex] = a.copyWith(
      workoutExercise: a.workoutExercise.copyWith(order: targetIndex),
    );

    final newState = current.copyWith(exercises: exercises);
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Replace the exercise on a [WorkoutExercise] while keeping all sets.
  ///
  /// **Phase 38b — modality-safe swap.** Strength→strength keeps the sets
  /// (the historical contract); cardio→cardio keeps the in-progress cardio
  /// session (duration/distance/RPE carry over, re-pointed at the new
  /// exercise). CROSS-modality swaps reset the payload: strength→cardio
  /// drops the sets and seeds a fresh default cardio entry; cardio→strength
  /// drops the cardio session and leaves an empty set list (the user adds
  /// sets via the normal Add Set affordance). Without the reset, a stale
  /// `cardioSession` would dangle on a strength card (and be silently
  /// persisted on finish), and stale sets attached to a cardio exercise
  /// would be invisible in the UI yet written to history.
  Future<void> swapExercise(
    String workoutExerciseId,
    Exercise newExercise,
  ) async {
    final current = state.value;
    if (current == null) return;

    final newIsCardio = newExercise.muscleGroup == MuscleGroup.cardio;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        final oldIsCardio =
            e.workoutExercise.exercise?.muscleGroup == MuscleGroup.cardio;
        final swapped = e.workoutExercise.copyWith(
          exerciseId: newExercise.id,
          exercise: newExercise,
        );

        if (newIsCardio) {
          return e.copyWith(
            workoutExercise: swapped,
            sets: const [],
            // Same-modality swap carries the entry over (re-pointed at the
            // new exercise); strength→cardio seeds a fresh default.
            cardioSession: oldIsCardio && e.cardioSession != null
                ? e.cardioSession!.copyWith(exerciseId: newExercise.id)
                : _seedCardioSession(
                    workoutId: current.workout.id,
                    exerciseId: newExercise.id,
                  ),
          );
        }
        return e.copyWith(
          workoutExercise: swapped,
          // cardio→strength: drop the cardio payload; strength→strength:
          // this is already null and the sets carry over untouched.
          cardioSession: null,
        );
      }).toList(),
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
  }

  /// Discard the active workout (deletes from server and clears local state).
  Future<void> discardWorkout() async {
    final current = state.value;
    if (current == null) return;
    if (_isDiscarding) return;
    _isDiscarding = true;
    _lastValidState = current;
    _cancelRequested = false;

    // PR1 review — Fix B: mirrors the C1 saveCommitted pattern. Flipped
    // to `true` immediately after `_repo.discardWorkout(...)` returns
    // success. Used by the post-guard cancel-check below to distinguish
    // pre-commit cancel (cancel wins, state stays restored) from
    // post-commit cancel (commit wins, state lands AsyncData(null) and
    // the screen redirects home). Once the server soft-delete commits
    // we MUST NOT restore the workout client-side — that would surface
    // a "phantom" workout pointing at a deleted server row, leaving the
    // user with a recoverable-looking session the server considers gone.
    var discardCommitted = false;

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      // Audit C2: server FIRST, then Hive. Pre-fix the order was swapped
      // — Hive cleared, then network call. A network failure left the
      // user with an empty Hive box but a server-side workout still alive,
      // so the next read re-hydrated stale server data and the user
      // believed they had lost their session. Swapping the order means a
      // failed discard leaves Hive intact: the workout re-loads from local
      // storage and the user can retry the discard. (Idempotency is fine
      // — `_repo.discardWorkout` is a soft-delete by id and is safe to
      // call twice.)
      await _repo.discardWorkout(current.workout.id, userId: _userId);
      // Fix B: mark the commit so the post-guard cancel-check honors it.
      // Anything below this line that throws still leaves discardCommitted
      // true — the server delete already happened.
      discardCommitted = true;
      await _localStorage.clearActiveWorkout();
      // PR #202 review O1: server delete + local clear are both committed
      // → the workout context is gone. Clear the cross-workout undo map
      // here (post-commit) so a pre-commit failure leaves it intact for
      // a retry against the same workout, but a successful discard
      // doesn't leak stale entries into the next start.
      _originalSetIndices.clear();

      final elapsedSeconds = DateTime.now()
          .toUtc()
          .difference(current.workout.startedAt)
          .inSeconds;
      final completedSets = current.exercises
          .expand((e) => e.sets)
          .where((s) => s.isCompleted)
          .length;
      final source = _workoutSource(current.routineId);
      _trackWorkoutEvent(
        event: AnalyticsEvent.workoutDiscarded(
          elapsedSeconds: elapsedSeconds,
          completedSets: completedSets,
          exerciseCount: current.exercises.length,
          source: source,
        ),
        breadcrumbMessage: 'discarded workout',
        breadcrumbData: {'workout_id': current.workout.id},
      );
      return null;
    });

    if (_cancelRequested && !discardCommitted) {
      // PR1 review — Fix B: pre-commit cancel. The user tapped Cancel
      // while we were still attempting the server delete AND it did NOT
      // commit. cancelLoading() already restored the previous state —
      // discard this guard result so we don't overwrite it.
      //
      // Post-commit cancel is intentionally ignored: once
      // `_repo.discardWorkout` returned successfully, the server-side
      // soft-delete is durable and the discard flow MUST continue
      // normally so the screen navigates to /home. A client-side tap
      // cannot "un-delete" a committed soft-delete.
      _cancelRequested = false;
      _isDiscarding = false;
      return;
    }
    // Reset the flag regardless — if we got here with _cancelRequested
    // still true it was a post-commit cancel that we deliberately ignored;
    // either way it must not leak into the next operation.
    _cancelRequested = false;

    state = result;
    _isDiscarding = false;
  }

  /// Phase 32 PR 32d — emit the `session_zero_xp` analytics event when the
  /// empty-session guard sheet (`FinishWorkoutCoordinator.finish`) opens.
  ///
  /// The coordinator owns the guard UI; the notifier owns analytics
  /// emission (centralized via [_trackWorkoutEvent] so platform/version
  /// plumbing stays in one place). Computes `elapsed_seconds` from the
  /// captured `workout.startedAt` — same source the finish-flow uses for
  /// `workoutFinished.durationSeconds`.
  ///
  /// No-op when there is no active workout (defensive — the coordinator
  /// only calls this after reading `totalSetsCount`, which requires an
  /// active workout, but a concurrent discard could clear state between
  /// the read and this call).
  void recordZeroXpSession() {
    final current = state.value;
    if (current == null) return;
    final elapsedSeconds = DateTime.now()
        .toUtc()
        .difference(current.workout.startedAt)
        .inSeconds;
    _trackWorkoutEvent(
      event: AnalyticsEvent.sessionZeroXp(
        exerciseCount: current.exercises.length,
        elapsedSeconds: elapsedSeconds,
      ),
      breadcrumbMessage: 'finish blocked by zero-XP guard',
      breadcrumbData: {
        'workout_id': current.workout.id,
        'exercise_count': current.exercises.length,
        'elapsed_seconds': elapsedSeconds,
      },
    );
  }

  /// Session-throttle for the first-awakening overlay (Phase 18c, spec §13).
  ///
  /// Reset to `false` when a workout STARTS (not when the app starts, not
  /// when a workout finishes). Set to `true` immediately after the builder
  /// emits a [FirstAwakeningEvent] so any sibling body part that wakes in
  /// the same finish stays silent — the overlay is an onboarding moment,
  /// not a churn event.
  ///
  /// **Why on the notifier and not in the builder:** the throttle is a
  /// session-level invariant the orchestrator owns. Putting it on the
  /// builder would conflate "did we already show this" (notifier state)
  /// with "what events does the diff produce" (pure function). Phase 18b's
  /// rune-state change covers the second-and-later body-part awakenings
  /// silently via the character sheet.
  bool _firstAwakeningFiredThisSession = false;

  /// Result of the most recent online finish's celebration build, or `null`
  /// when the last finish was offline-queued (no overlays play offline) or
  /// produced no events.
  ///
  /// One-shot consumption: the active-workout screen reads this via
  /// [consumeLastCelebration] immediately after `finishWorkout` returns.
  /// The screen is responsible for playing the queue + overflow card; the
  /// notifier does not own playback timing.
  CelebrationQueueResult? _lastCelebration;

  /// Phase 30 PR 30a — total XP delta the user earned in the most recent
  /// online finish (`sum(post.totalXp - pre.totalXp)` across active body
  /// parts). The post-session screen reads this to render the B1 XP slam.
  /// `null` after an offline finish, a zero-set finish, or a discard.
  ///
  /// **Why on the notifier:** the pre/post snapshots are local to
  /// [_buildAndStashCelebration] and shouldn't leak outside the finish
  /// flow. Stashing the precomputed delta here avoids forcing the
  /// coordinator (or the screen) to re-fetch and re-diff snapshots they
  /// don't otherwise need to read.
  num? _lastSessionTotalXpDelta;

  /// Read and clear the last-session XP delta. One-shot — subsequent
  /// calls return `null` until the next finish runs.
  num? consumeLastSessionTotalXpDelta() {
    final v = _lastSessionTotalXpDelta;
    _lastSessionTotalXpDelta = null;
    return v;
  }

  /// Phase 30 PR 30a — per-BP XP deltas for the most recent online
  /// finish. Empty after offline / zero-set / discard. The post-session
  /// screen uses this to drive B2 single/cascade body-part cuts.
  Map<BodyPart, num> _lastSessionBpDeltas = const <BodyPart, num>{};

  Map<BodyPart, num> consumeLastSessionBpDeltas() {
    final v = _lastSessionBpDeltas;
    _lastSessionBpDeltas = const <BodyPart, num>{};
    return v;
  }

  /// Read and clear the queued celebration produced by the last finish.
  ///
  /// One-shot: subsequent calls return `null` until the next finish runs.
  /// This prevents accidental re-play after a hot-reload or a screen
  /// rebuild where the consumer reads the field twice.
  CelebrationQueueResult? consumeLastCelebration() {
    final result = _lastCelebration;
    _lastCelebration = null;
    return result;
  }

  /// Finish the active workout, save to server, detect PRs, and return results.
  ///
  /// When the network save fails, the workout is enqueued for offline sync
  /// and a locally-constructed [Workout] is used for downstream PR detection
  /// and weekly-plan updates. The returned [FinishWorkoutResult.savedOffline]
  /// flag is `true` in that case so the UI can render the offline-queued
  /// snackbar.
  ///
  /// Returns `null` only when there is no active workout in the first place
  /// (state was already null) or when a concurrent finish is in flight
  /// (re-entrance guard). Otherwise the future resolves to a result record
  /// even on PR-detection failure (which is non-essential and never blocks
  /// the save).
  Future<FinishWorkoutResult?> finishWorkout({String? notes}) async {
    final current = state.value;
    if (current == null) return null;
    if (_isFinishing) return null;
    _isFinishing = true;
    _lastValidState = current;
    _cancelRequested = false;
    _lastCelebration = null;
    _lastSessionTotalXpDelta = null;
    _lastSessionBpDeltas = const <BodyPart, num>{};
    // Tracked locally inside the guard scope — folded into the returned
    // [FinishWorkoutResult] so the caller reads it through the explicit
    // return value, not via a notifier field. Restores unidirectional
    // Riverpod data flow (BUG-039).
    var savedOffline = false;
    var serverErrorQueued = false;
    // Audit C1: flipped to `true` immediately after `_repo.saveWorkout(...)`
    // returns. Used by the post-guard cancel-check below to distinguish
    // pre-commit cancel (cancel wins, state stays restored) from
    // post-commit cancel (commit wins, state lands AsyncData(null) and
    // celebration plays). A successful save cannot be reversed by a
    // client-side tap, so once we've crossed that line we MUST NOT block
    // the normal finish flow — otherwise the screen never navigates to
    // /home and the celebration overlay never plays.
    var saveCommitted = false;

    // Capture the pre-finish RPG snapshot + earned-title slug set BEFORE the
    // save call. The post-finish snapshot (read after `record_set_xp`
    // commits inside the same transaction as `save_workout`) is diffed
    // against this to derive rank-up / level-up / first-awakening /
    // title-unlock events. Reading `.value` (which returns `T?` on
    // [AsyncValue]) is safe — these providers are AsyncNotifiers that
    // always have a current snapshot once the user is authenticated, but a
    // brand-new install pre-first-fetch should gracefully fall through to
    // "empty pre" so the very first workout still emits the awakening
    // overlay.
    final preSnapshot =
        ref.read(rpgProgressProvider).value ?? RpgProgressSnapshot.empty;
    final preEarnedSlugs = ref
        .read(earnedTitlesProvider)
        .value
        ?.map((e) => e.title.slug)
        .toSet();

    // Capture workout data BEFORE setting loading state.
    final exercises = current.exercises;

    // Bug B fix 2026-05-24 — save-site filter for planned-vs-committed shape.
    //
    // `ActiveWorkoutState.exercises` carries the PLANNED shape:
    // `startFromRoutine` pre-populates every routine exercise with N
    // pre-filled `ExerciseSet`s (`isCompleted: false`) so the user has
    // editable slots to tap through. Before this filter the finish path
    // forwarded that planned shape verbatim to `save_workout`, so a user
    // completing 2 sets of 1 exercise from a 3-exercise routine saw the
    // entire routine in /history (Bench Press, OHP, Triceps — with all
    // pre-filled sets persisted as `is_completed=false`).
    //
    // `committedExercises` keeps only `isCompleted` sets and drops any
    // exercise that ends up with zero completed sets, then drives every
    // downstream persistence path:
    //   - online save_workout RPC payload (workoutExercises + sets below)
    //   - offline replay payload (exercisesJson + setsJson at L~1430)
    //   - PR detection input (skips empty-set exercises one layer earlier)
    //   - PR cache key (exerciseIds below)
    //
    // Analytics (`exerciseCount`, `totalSets`, `incompleteSetsSkipped`)
    // intentionally keeps reading the PRE-filter `exercises` so the
    // `workoutFinished` event still reports planned-vs-completed deltas
    // — that's what those fields mean.
    //
    // Cluster: planned-shape-persisted-as-actual (new pattern, closest
    // existing match is `optimistic-ui-vs-async-provider`).
    final committedExercises = exercises
        .map(
          (e) => e.copyWith(sets: e.sets.where((s) => s.isCompleted).toList()),
        )
        .where((e) => e.sets.isNotEmpty)
        .toList();

    // Phase 38b — committed cardio entries (the user tapped "Concluir
    // cardio"). Persisted to `cardio_sessions` via save_workout's p_cardio
    // array in the SAME transaction as the workout + sets. Cardio entries
    // deliberately do NOT produce `workout_exercises` rows: they carry no
    // sets (an empty set-table card in history would read as a bug), the
    // `cardio_sessions` row is self-contained (workout_id + exercise_id),
    // and history rendering of cardio is the Phase 38c/38d CardioLiftRow
    // work. They never enter PR detection (no sets) and never call any XP
    // RPC (the 00077 gate is the structural backstop; earning is 38c).
    final committedCardio = exercises
        .where((e) => e.cardioSession?.isCompleted ?? false)
        .map((e) => e.cardioSession!)
        .toList();

    final exerciseIds = committedExercises
        .map((e) => e.workoutExercise.exerciseId)
        .toSet()
        .toList();

    state = const AsyncLoading();

    PRDetectionResult? prResult;
    // Hoisted so the analytics event can still report a number (0) when PR
    // detection throws before the count is fetched.
    int workoutCount = 0;
    // PR 32g (Bug 1) — hoisted out of the guard scope so the return record
    // can surface the same value the notifier persisted. Stays null when
    // the guard short-circuits before computing it (e.g. an exception
    // before the `now/durationSeconds` capture below); caller defaults to 0.
    int? finishDurationSeconds;

    final result = await AsyncValue.guard(() async {
      final now = DateTime.now().toUtc();
      final durationSeconds = now
          .difference(current.workout.startedAt)
          .inSeconds;
      finishDurationSeconds = durationSeconds;

      final workout = current.workout.copyWith(
        finishedAt: now,
        durationSeconds: durationSeconds,
        isActive: false,
        notes: notes,
      );

      // Bug B fix 2026-05-24: built from `committedExercises` (only
      // completed sets, no empty-set exercises) so both the online RPC
      // payload below and the offline replay payload at L~1430 persist
      // the actual workout shape, not the planned routine skeleton.
      final workoutExercises = committedExercises
          .map((e) => e.workoutExercise)
          .toList();
      final sets = committedExercises.expand((e) => e.sets).toList();

      // --- Save workout (online or offline queue) ---
      try {
        await _repo.saveWorkout(
          workout: workout,
          exercises: workoutExercises,
          sets: sets,
          // Phase 38b: completed cardio entries ride the same RPC
          // transaction (p_cardio → cardio_sessions, migration 00078).
          cardio: committedCardio,
          // 26e: source routine for weekly_plans bucket find-or-create
          // (00063). Null for free workouts started ad-hoc — the RPC
          // treats them as spontaneous-append candidates.
          routineId: current.routineId,
        );
        // C1: mark the commit so the post-guard cancel-check honors it.
        // Anything below this line that throws will leave saveCommitted
        // true and the cancel-after-commit semantic still applies — the
        // server-side write has already happened.
        saveCommitted = true;
        // PR #202 review O1: workout is durable server-side → the undo
        // map's contents are no longer relevant. Clear here (post-commit)
        // so the next session starts with a fresh map regardless of
        // whether finishWorkout proceeds normally or short-circuits via
        // the post-guard cancel-check below. Mirrors the discardWorkout
        // placement (server-commit → clear). The offline-queue branch
        // does NOT clear: an offline save is not durable and the user
        // may continue editing the same workout in a degraded state
        // until a retry succeeds.
        _originalSetIndices.clear();
      } catch (e) {
        // Classify at the catch site so terminal errors surface to the user
        // (AW-EX-D-US1-03, AW-EX-E-US1-02). Pre-1B every save failure was
        // uniformly enqueued as offline — a 4xx / RLS denial / FK violation
        // produced a "Saved offline" snackbar with no error indication, and
        // the queue then logged a structural failure no user could fix.
        //
        // Contract:
        //   - terminal (deterministic data/permission failure — malformed
        //     payload 22P02, constraint 235xx, RLS 42501, missing schema
        //     object 42P01/42703, or PGRST* request error) → rethrow so the
        //     outer AsyncValue.guard lands in AsyncError; the coordinator's
        //     `asyncState.hasError` branch shows the localized "Failed to save
        //     workout" snackbar and the user keeps their unsaved local state.
        //     SyncErrorClassifier.isTerminal keys on the SQLSTATE/PGRST code,
        //     NOT an HTTP int (PostgrestException.code is the SQLSTATE).
        //   - transient (offline, timeout, 5xx, serialization/deadlock,
        //     unknown) → enqueue.
        //   - 5xx specifically sets `serverErrorQueued = true` so the UI can
        //     pick a "server error — saved offline, will retry" copy variant
        //     (Q1.3 in the impact analysis).
        if (SyncErrorClassifier.isTerminal(e)) {
          // Cluster: developer-log-invisible-logcat (PR 32g) — adb logcat
          // visibility for terminal save errors on physical-device triage.
          debugPrint(
            '[ActiveWorkoutNotifier] Terminal save error, surfacing to UI: $e',
          );
          rethrow;
        }
        debugPrint(
          '[ActiveWorkoutNotifier] Network save failed, queueing offline: $e',
        );
        savedOffline = true;
        // 5xx is transient (queue) but distinct from connectivity failure;
        // the queue still retries, but the UI tells the user it was a server
        // problem so a "Pending sync (1)" badge is not misleading.
        // [SyncErrorClassifier.httpCode] yields a numeric HTTP status ONLY
        // for shapes that actually carry one — i.e. the [app.AuthException] /
        // [supabase.AuthException] forms whose code is the gotrue HTTP
        // `statusCode`. [PostgrestException]/[app.DatabaseException] carry the
        // SQLSTATE/PGRST code (non-numeric), so this branch never trips for
        // them — which is correct: a real Postgrest 5xx surfaces as a
        // transport-layer Socket/Http exception, not a Postgrest error. This
        // is a copy-variant selector only (no data-correctness impact).
        final code = SyncErrorClassifier.httpCode(e);
        if (code != null && code >= 500 && code < 600) {
          serverErrorQueued = true;
        }

        // Build raw JSON maps matching the RPC shape.
        // Include all required Workout fields so Workout.fromJson succeeds
        // when retrying from the queue.
        final workoutJson = <String, dynamic>{
          'id': workout.id,
          'user_id': workout.userId,
          'name': workout.name,
          'started_at': workout.startedAt.toIso8601String(),
          'finished_at': workout.finishedAt?.toIso8601String(),
          'duration_seconds': workout.durationSeconds,
          'is_active': false,
          'notes': workout.notes,
          'created_at': workout.createdAt.toIso8601String(),
          // 26e: ride the source routine through the offline payload so the
          // drain in pending_sync_provider can replay the same find-or-create
          // semantics the online path uses. The 00063 `save_workout` RPC
          // does the bucket update in the same transaction as the workout
          // insert; persisting `routine_id` here is what replaces the
          // pre-26e `PendingMarkRoutineComplete` sibling enqueue.
          'routine_id': current.routineId,
        };
        final exercisesJson = workoutExercises
            .map(
              (e) => <String, dynamic>{
                'id': e.id,
                'workout_id': e.workoutId,
                'exercise_id': e.exerciseId,
                'order': e.order,
                'rest_seconds': e.restSeconds,
              },
            )
            .toList();
        // BUG-001 fix: use the shared `toRpcJson()` extension so the offline
        // payload always matches the online one. Drift between these two
        // serializers (offline omitting `created_at`) was the root cause of
        // the "type 'Null' is not a subtype of type 'String' in type cast"
        // crash on replay — `_$ExerciseSetFromJson` calls
        // `DateTime.parse(json['created_at'] as String)` unconditionally.
        final setsJson = sets.map((s) => s.toRpcJson()).toList();
        // Phase 38b: shared `toRpcJson()` keeps the offline cardio payload
        // byte-identical to the online one — same BUG-001 drift guard as
        // setsJson above.
        final cardioJson = committedCardio.map((c) => c.toRpcJson()).toList();

        // Phase 32 PR 32h retired the user-create-exercise surface, so a
        // queued workout can no longer depend on an offline exercise create
        // (the `PendingCreateExercise` variant was deleted from the sealed
        // union). All offline workouts reference exercises that already
        // exist server-side (defaults), so the new save needs no parent
        // `dependsOn`. Pre-existing `PendingUpsertRecords` children of THIS
        // workout are wired with the workout's id further down — that
        // ordering is unaffected.
        await ref
            .read(pendingSyncProvider.notifier)
            .enqueue(
              PendingAction.saveWorkout(
                id: workout.id,
                workoutJson: workoutJson,
                exercisesJson: exercisesJson,
                setsJson: setsJson,
                cardioJson: cardioJson,
                userId: workout.userId,
                queuedAt: now,
              ),
            );

        _repo.incrementCachedWorkoutCount(workout.userId);
        _repo.evictHistoryCaches(workout.userId);

        _trackWorkoutEvent(
          event: const AnalyticsEvent.workoutSyncQueued(
            actionType: 'save_workout',
          ),
          breadcrumbMessage: 'workout queued for offline sync',
          breadcrumbData: {'workout_id': workout.id},
        );
      }

      // Invalidate the per-exercise progress chart family so any exercise
      // whose detail sheet is re-opened this session reflects the newly
      // saved sets. Invalidating the whole family is correct — a finished
      // workout may touch any exercise, and the family is small per user.
      //
      // RPG state: `save_workout` RPC awards XP via `record_set_xp` in the
      // same transaction, so by the time we get here `lifetime_xp` and
      // per-body-part rows are durable server-side. We explicitly refresh
      // the snapshot (instead of just invalidating) so the post-snapshot
      // is durable BEFORE we diff against the pre-snapshot to build
      // celebration events. Co-located here with the other post-save
      // invalidations so no future contributor adds a side-effect that
      // forgets to refresh one of them.
      //
      // Offline saves haven't committed XP yet — the queued `save_workout`
      // action will re-trigger this same flow once it flushes (and no
      // celebrations play offline, per spec §13: the user isn't watching).
      if (!savedOffline) {
        _repo.incrementCachedWorkoutCount(_userId);
        ref.invalidate(exerciseProgressProvider);
        await _buildAndStashCelebration(
          preSnapshot: preSnapshot,
          preEarnedSlugs: preEarnedSlugs ?? const <String>{},
        );
      }

      // PR detection: read existing records from local cache (never network),
      // detect new PRs, celebrate immediately, and always enqueue writes.
      // Phase 14d: fully offline-first PR detection.
      try {
        final prService = ref.read(prDetectionServiceProvider);
        final cache = ref.read(cacheServiceProvider);

        // Build the same cache key that PRRepository uses.
        final cacheKey =
            'exercises:${(List<String>.from(exerciseIds)..sort()).join(',')}';

        // Always read from local pr_cache — no network call.
        var existingRecords = cache.read<Map<String, List<PersonalRecord>>>(
          HiveService.prCache,
          cacheKey,
          (json) {
            final map = json as Map<String, dynamic>;
            return map.map(
              (k, v) => MapEntry(
                k,
                (v as List)
                    .map(
                      (e) => PersonalRecord.fromJson(e as Map<String, dynamic>),
                    )
                    .toList(),
              ),
            );
          },
        );

        // If cache misses, fall back to PRRepository (which has its own
        // cache fallback). This covers the first-ever workout before any
        // cache has been populated.
        if (existingRecords == null) {
          final prRepo = ref.read(prRepositoryProvider);
          existingRecords = await prRepo.getRecordsForExercises(exerciseIds);
        }

        // Always use cached workout count — no network call.
        workoutCount = _repo.getCachedWorkoutCount(_userId) ?? 1;

        prResult = prService.detectPRs(
          userId: _userId,
          // Bug B fix: feed `committedExercises` (only completed sets, no
          // empty-set exercises). `detectPRs` already filters via
          // `completedWorkingSets()` and `continue`s on empty exercises, so
          // this is a no-op contract-wise but keeps the persistence layer
          // and the PR-detection layer reading the same shape.
          exercises: committedExercises,
          existingRecords: existingRecords,
          totalFinishedWorkouts: workoutCount,
        );

        if (prResult!.hasNewRecords) {
          // PR upsert path:
          //   - parent saved OFFLINE → enqueue with `dependsOn=[workout.id]`
          //     so the drain holds this upsert until the parent commits
          //     server-side (BUG-002 — without the dependency, the FK on
          //     `personal_records.set_id → sets.id` fires before the parent
          //     ever inserts the rows).
          //   - parent saved ONLINE → try a direct upsert. The sets are
          //     already durable server-side, so the FK resolves immediately
          //     and the user sees their PRs reflected without waiting for a
          //     connectivity transition to drain the queue. Fall back to the
          //     queue on any failure (network drop between save and PR
          //     upsert, server rejection, etc.) so the data is never lost.
          //
          // Why direct-on-online is the right behavior: SyncService only
          // drains on offline→online transitions, so an enqueued action on
          // a steady-online device sits forever waiting for either a manual
          // retry tap or a connectivity blip. That left users staring at a
          // "Pending Sync (1)" badge for PRs they had clearly earned and
          // could see no reason for.
          if (savedOffline) {
            await ref
                .read(pendingSyncProvider.notifier)
                .enqueue(
                  PendingAction.upsertRecords(
                    id: _uuid.v4(),
                    recordsJson: prResult!.newRecords
                        .map((r) => r.toJson())
                        .toList(),
                    userId: _userId,
                    queuedAt: now,
                    dependsOn: <String>[workout.id],
                  ),
                );
          } else {
            // Online: detached upsert. UI navigation must NOT block on what
            // is purely a server-persistence concern — the user has already
            // seen the PR detected on the client (cache write below + the
            // celebration screen). On any failure (network drop, server
            // rejection), fall through to the queue so the data is never
            // lost.
            //
            // Why detached: awaiting here gates `finishWorkout()`'s return
            // on a network roundtrip and on CI we saw the second-workout
            // PR test push past its 60s budget when two upserts happened
            // back-to-back. Persistence is not a UX concern here.
            //
            // Try/catch in an immediately-invoked async block (rather than
            // `.catchError`) so we catch both synchronous throws from the
            // call site and asynchronous failures from the returned Future.
            final prRepo = ref.read(prRepositoryProvider);
            final pendingNotifier = ref.read(pendingSyncProvider.notifier);
            final newRecordsForUpsert = prResult!.newRecords;
            unawaited(() async {
              try {
                await prRepo.upsertRecords(newRecordsForUpsert);
              } catch (e, st) {
                // Cluster: developer-log-invisible-logcat (PR 32g) — adb
                // logcat visibility for the PR-upsert fallback path.
                debugPrint(
                  '[ActiveWorkoutNotifier] Direct PR upsert failed, falling '
                  'back to queue: $e\n$st',
                );
                try {
                  await pendingNotifier.enqueue(
                    PendingAction.upsertRecords(
                      id: _uuid.v4(),
                      recordsJson: newRecordsForUpsert
                          .map((r) => r.toJson())
                          .toList(),
                      userId: _userId,
                      queuedAt: now,
                      dependsOn: const <String>[],
                    ),
                  );
                } catch (queueErr, queueSt) {
                  // The queue itself failing is rare (Hive box write) but
                  // we never want this background task to crash the
                  // notifier. Log loud and move on. Cluster:
                  // developer-log-invisible-logcat (PR 32g).
                  debugPrint(
                    '[ActiveWorkoutNotifier] Fallback enqueue also failed: '
                    '$queueErr\n$queueSt',
                  );
                }
              }
            }());
          }

          // Optimistically update pr_cache so subsequent offline finishes
          // see the new records immediately.
          final merged = Map<String, List<PersonalRecord>>.from(
            existingRecords,
          );
          for (final record in prResult!.newRecords) {
            final list = merged[record.exerciseId] ??= [];
            list.removeWhere((r) => r.recordType == record.recordType);
            list.add(record);
          }
          cache.write(
            HiveService.prCache,
            cacheKey,
            merged.map(
              (k, v) => MapEntry(k, v.map((r) => r.toJson()).toList()),
            ),
          );
        }
      } catch (e, st) {
        // PR detection failure should NOT fail the workout save.
        // BUG-009: capture to Sentry so production rates are visible —
        // this catch historically masked BUG-001 by silently dropping
        // detection-side null casts. Workout still saves; user is not
        // surfaced anything because PRs are non-essential.
        // Cluster: developer-log-invisible-logcat (PR 32g) — adb logcat
        // visibility for swallowed PR-detection failures.
        debugPrint('[ActiveWorkoutNotifier] PR detection failed: $e');
        unawaited(SentryReport.captureException(e, stackTrace: st));
      }

      // XP award: handled server-side inside `save_workout` → `record_set_xp`,
      // which writes `body_part_progress` and `xp_events` rows in the same
      // transaction as the workout. The post-save Dart award path was a
      // Phase 17b leftover that drove the legacy `gamification_xp_state`
      // table; it was deleted in the Phase 18 follow-ups branch when the
      // gamification feature dir was removed (the saga intro overlay no
      // longer depends on the legacy XP roll-up). Phase 18a's per-set RPC
      // is the single writer.

      // Weekly plan: the 00063 `save_workout` RPC owns the bucket
      // find-or-create entirely server-side (26e). The RPC matches an
      // existing uncompleted entry by `routine_id` and stamps
      // `completed_workout_id` + `completed_at` in the same transaction
      // as the workout insert; if no match exists it appends a spontaneous
      // entry. Invalidate the provider so the next read fetches the
      // server-updated row (async-caller-broke-snackbar cluster:
      // invalidate triggers a refetch, it does NOT update `state.value`
      // synchronously — nothing below this line reads weeklyPlanProvider).
      //
      // Offline saves: the queued `PendingSaveWorkout` carries
      // `routine_id` in its JSON payload, so the drain replays the same
      // RPC with the same find-or-create semantics. No separate
      // weekly-plan enqueue is needed; the legacy
      // `PendingMarkRoutineComplete` variant is now a logged no-op in the
      // drain (in case any pre-26e queue entries survived an upgrade).
      ref.invalidate(weeklyPlanProvider);

      // Analytics — mixed planned-vs-committed reads, on purpose:
      //
      // `totalSets` / `completedSets` / `incompleteSetsSkipped` read the
      // PRE-filter `exercises` so `workoutFinished` retains its planned-
      // vs-committed deltas (the delta IS the analytics signal —
      // "how often do users plan more than they execute?"). Using the
      // post-filter `sets` here would make `incompleteSetsSkipped`
      // always 0 and erase the signal.
      //
      // `exerciseCount` reads the POST-filter `committedExercises.length`
      // (PR #261 reviewer Blocker 1). The schema has no paired
      // `completedExercises` field, so consumers couldn't recover the
      // committed count from a planned-count read. This field answers
      // "how many exercises did the user actually perform" — that's the
      // committed shape. If a planned counterpart is ever needed, add a
      // separate `plannedExerciseCount` field on the event rather than
      // silently changing this field's meaning.
      final plannedSets = exercises.expand((e) => e.sets).toList();
      final totalSets = plannedSets.length;
      final completedSetsCount = plannedSets.where((s) => s.isCompleted).length;
      final incompleteSetsSkipped = totalSets - completedSetsCount;
      final hadPr = prResult?.newRecords.isNotEmpty ?? false;
      final source = _workoutSource(current.routineId);
      _trackWorkoutEvent(
        event: AnalyticsEvent.workoutFinished(
          durationSeconds: durationSeconds,
          exerciseCount: committedExercises.length,
          totalSets: totalSets,
          completedSets: completedSetsCount,
          incompleteSetsSkipped: incompleteSetsSkipped,
          hadPr: hadPr,
          source: source,
          workoutNumber: workoutCount,
        ),
        breadcrumbMessage: 'finished workout',
        breadcrumbData: {
          'workout_id': workout.id,
          'workout_number': workoutCount,
          'had_pr': hadPr,
        },
      );

      await _localStorage.clearActiveWorkout();
      return null;
    });

    if (_cancelRequested && !saveCommitted) {
      // C1: pre-commit cancel. The user tapped Cancel while we were still
      // attempting the save (or before the catch decided to enqueue
      // offline) AND the save did NOT commit server-side. cancelLoading()
      // already restored the previous state — discard this guard result
      // so we don't overwrite it.
      //
      // Post-commit cancel is intentionally ignored: once `saveWorkout`
      // returned successfully, the sets and xp_events rows are durable
      // server-side and the finish flow MUST continue normally so the
      // celebration plays and the screen navigates to /home. A client-side
      // tap cannot reverse a committed save.
      _cancelRequested = false;
      _isFinishing = false;
      return null;
    }
    // Reset the flag regardless — if we got here with _cancelRequested
    // still true it was a post-commit cancel that we deliberately ignored;
    // either way it must not leak into the next finish call.
    _cancelRequested = false;

    state = result;
    _isFinishing = false;

    // PR1B: when the catch site rethrew a terminal error, AsyncValue.guard
    // captured it into AsyncError. The result record is meaningless in that
    // case (savedOffline/serverErrorQueued were never flipped because the
    // catch handler short-circuited via rethrow), so return null and let the
    // coordinator route via `state.hasError`. Pre-1B this method returned a
    // record even on AsyncError, which made it impossible for the coordinator
    // to distinguish "saved offline cleanly" from "save failed terminally".
    if (result is AsyncError) {
      return null;
    }

    return (
      prResult: prResult,
      savedOffline: savedOffline,
      serverErrorQueued: serverErrorQueued,
      durationSeconds: finishDurationSeconds,
    );
  }

  /// Refresh the RPG progress + earned-titles providers post-save, then diff
  /// against the captured pre-snapshot to build the celebration queue.
  ///
  /// Stashes the result on [_lastCelebration] for the screen to consume via
  /// [consumeLastCelebration]. Sets [_firstAwakeningFiredThisSession] to
  /// `true` when the queue contains an awakening event so subsequent
  /// finishes in the same session stay silent (PO throttle, spec §13).
  ///
  /// **Why this is a separate private method:** finish-flow celebration is
  /// orthogonal to PR detection, weekly-plan, and analytics. Inlining it
  /// into `finishWorkout`'s already-100-line `AsyncValue.guard` block would
  /// hide the dependency on `preSnapshot`/`preEarnedSlugs` — extracting it
  /// makes the data flow explicit (pre/post snapshots in, queue out) and
  /// keeps the orchestration testable in isolation.
  ///
  /// **Failure handling:** any error here (catalog asset load, snapshot
  /// refresh) is logged and silently swallowed — celebration playback is
  /// non-essential UI polish, NOT a workout-save invariant. The save has
  /// already committed by the time this runs.
  Future<void> _buildAndStashCelebration({
    required RpgProgressSnapshot preSnapshot,
    required Set<String> preEarnedSlugs,
  }) async {
    try {
      // Refresh the snapshot first so the post-state is durable before we
      // diff. `refreshAfterSave` re-fetches both `body_part_progress` and
      // the `character_state` view inside the same call, and returns the
      // fresh snapshot directly to avoid a race where a concurrent in-flight
      // initial build() might overwrite the provider state with pre-save data
      // after refreshAfterSave completes.
      final postSnapshot = await ref
          .read(rpgProgressProvider.notifier)
          .refreshAfterSave();
      ref.invalidate(earnedTitlesProvider);

      // Catalog is asset-only and cached after first load — this future
      // resolves synchronously after the first call.
      final catalog = await ref.read(titleCatalogProvider.future);

      final events = CelebrationEventBuilder.build(
        pre: preSnapshot,
        post: postSnapshot,
        catalog: catalog,
        alreadyEarnedSlugs: preEarnedSlugs,
        suppressFirstAwakening: _firstAwakeningFiredThisSession,
      );

      // Phase 30 PR 30a — compute total + per-BP XP delta for the
      // post-session screen. We do this regardless of whether
      // [events.isEmpty] because the screen renders a baseline cinematic
      // for empty queues too (the B1 XP slam is the user's primary feedback
      // even on a session with no rank-up / no PR).
      num totalDelta = 0;
      final bpDeltas = <BodyPart, num>{};
      for (final bp in activeBodyParts) {
        final preXp = preSnapshot.byBodyPart[bp]?.totalXp ?? 0;
        final postXp = postSnapshot.byBodyPart[bp]?.totalXp ?? 0;
        final delta = postXp - preXp;
        if (delta > 0) {
          bpDeltas[bp] = delta;
          totalDelta += delta;
        }
      }
      _lastSessionTotalXpDelta = totalDelta > 0 ? totalDelta : null;
      _lastSessionBpDeltas = Map.unmodifiable(bpDeltas);

      if (events.isEmpty) {
        _lastCelebration = null;
        return;
      }

      final result = CelebrationQueue.build(events: events);

      // Throttle book-keeping: if the queue contains an awakening, the
      // overlay will play once the screen consumes the result, so flip the
      // flag now to prevent a second awakening in the same session even if
      // the screen never actually renders it (e.g. user backgrounds the
      // app mid-celebration).
      final hasAwakening = result.queue.any((e) => e is FirstAwakeningEvent);
      if (hasAwakening) {
        _firstAwakeningFiredThisSession = true;
      }

      _lastCelebration = result;
    } catch (e, st) {
      // Cluster: developer-log-invisible-logcat (PR 32g) — adb logcat
      // visibility for celebration-build failures on physical devices.
      debugPrint('[ActiveWorkoutNotifier] Celebration build failed: $e\n$st');
      _lastCelebration = null;
    }
  }

  /// Persist the current state to Hive.
  ///
  /// Awaited so IndexedDB (web) flushes before the next state update,
  /// preventing data loss on page reload.
  Future<void> _saveToHive(ActiveWorkoutState activeState) async {
    try {
      await _localStorage.saveActiveWorkout(activeState);
    } catch (e) {
      // Cluster: developer-log-invisible-logcat (PR 32g) — adb logcat
      // visibility for Hive persistence failures on physical devices.
      debugPrint(
        '[ActiveWorkoutNotifier] Failed to persist workout to Hive: $e',
      );
    }
  }

  /// Fire-and-forget insert of a product analytics event plus a matching
  /// Sentry breadcrumb.
  ///
  /// Throws [app.AuthException] via the [_userId] getter if the user is not
  /// authenticated. Safe today because every call site runs inside
  /// `AsyncValue.guard` (which captures the exception into `AsyncError`) and
  /// is only reached after a workout has been started — which itself requires
  /// authentication. Do NOT call this from any code path that might run
  /// without an active session, or wrap the call in a try/catch.
  ///
  /// The underlying [AnalyticsRepository.insertEvent] swallows all errors
  /// itself, so there is nothing to await and nothing to handle here beyond
  /// the `_userId` read.
  void _trackWorkoutEvent({
    required AnalyticsEvent event,
    required String breadcrumbMessage,
    Map<String, Object?>? breadcrumbData,
  }) {
    final analyticsRepo = ref.read(analyticsRepositoryProvider);
    unawaited(
      analyticsRepo.insertEvent(
        userId: _userId,
        event: event,
        platform: currentPlatform(),
        appVersion: currentAppVersion(),
      ),
    );
    SentryReport.addBreadcrumb(
      category: 'workout',
      message: breadcrumbMessage,
      data: breadcrumbData,
    );
  }
}

final activeWorkoutProvider =
    AsyncNotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutState?>(
      ActiveWorkoutNotifier.new,
    );
