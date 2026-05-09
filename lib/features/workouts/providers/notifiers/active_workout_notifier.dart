import 'dart:async';
import 'dart:developer';
import 'dart:ui' show Locale;

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
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/providers/earned_titles_provider.dart';
import '../../../rpg/providers/rpg_progress_provider.dart';
import '../../../weekly_plan/providers/weekly_plan_provider.dart';
import '../../data/workout_local_storage.dart';
import '../../data/workout_repository.dart';
import '../../models/active_workout_state.dart';
import '../../models/exercise_set.dart';
import '../../models/routine_start_config.dart';
import '../../models/set_type.dart';
import '../../models/weight_unit.dart';
import '../../models/workout_exercise.dart';
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

  @override
  FutureOr<ActiveWorkoutState?> build() {
    _repo = ref.watch(workoutRepositoryProvider);
    _localStorage = ref.watch(workoutLocalStorageProvider);
    return _localStorage.loadActiveWorkout();
  }

  /// Cancel an in-flight loading operation by restoring the last valid state.
  ///
  /// Used by the loading overlay's timeout cancel button. The underlying
  /// network request continues in the background, but the UI is unblocked
  /// so the user can retry or discard. Resets re-entrance guards so the
  /// user can try again.
  void cancelLoading() {
    _cancelRequested = true;
    _isFinishing = false;
    _isDiscarding = false;
    if (_lastValidState != null) {
      // _lastValidState already carries `savedOffline: false` (reset at the
      // top of finishWorkout / discardWorkout) so restoring it naturally
      // resets the offline-queued flag without a separate field.
      state = AsyncData(_lastValidState);
    }
  }

  String get _userId {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      throw const app.AuthException('Not authenticated', code: 'no_session');
    }
    return user.id;
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

  /// Start a new workout session.
  ///
  /// If [name] is omitted a date-based name is generated automatically,
  /// e.g. "Workout — Wed Apr 2".
  Future<void> startWorkout([String? name]) async {
    state = const AsyncLoading();
    _firstAwakeningFiredThisSession = false;
    _lastCelebration = null;
    state = await AsyncValue.guard(() async {
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
        event: const AnalyticsEvent.workoutStarted(
          source: 'empty',
          routineId: null,
          exerciseCount: 0,
        ),
        breadcrumbMessage: 'started empty workout',
        breadcrumbData: {'workout_id': workout.id},
      );
      return activeState;
    });
  }

  /// Start a workout pre-populated from a routine template.
  Future<void> startFromRoutine(RoutineStartConfig config) async {
    state = const AsyncLoading();
    _firstAwakeningFiredThisSession = false;
    _lastCelebration = null;
    state = await AsyncValue.guard(() async {
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

        final previousSets = lastSets[re.exerciseId] ?? [];
        final equipDefaults = defaultSetValues(
          re.exercise.equipmentType,
          weightUnit,
        );
        final sets = List.generate(re.setCount, (setIndex) {
          // Use the matching previous set, or the last previous set if fewer.
          final prev = previousSets.isNotEmpty
              ? previousSets[setIndex < previousSets.length
                    ? setIndex
                    : previousSets.length - 1]
              : null;

          return ExerciseSet(
            id: _uuid.v4(),
            workoutExerciseId: workoutExerciseId,
            setNumber: setIndex + 1,
            weight: prev?.weight ?? equipDefaults.weight,
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
      );
      await _saveToHive(activeState);
      // TODO post-PR: differentiate planned_bucket when config exposes the flag
      _trackWorkoutEvent(
        event: AnalyticsEvent.workoutStarted(
          source: 'routine_card',
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
  Future<void> addExercise(Exercise exercise) async {
    final current = state.value;
    if (current == null) return;

    final workoutExercise = WorkoutExercise(
      id: _uuid.v4(),
      workoutId: current.workout.id,
      exerciseId: exercise.id,
      order: current.exercises.length,
      exercise: exercise,
    );

    final newState = current.copyWith(
      exercises: [
        ...current.exercises,
        ActiveWorkoutExercise(workoutExercise: workoutExercise, sets: const []),
      ],
    );
    state = AsyncData(newState);
    await _saveToHive(newState);
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
          // completed set OR a customized weight; everything from that
          // point on stays as-is.
          if (s.isCompleted) {
            newSets.addAll(e.sets.sublist(i));
            break;
          }
          if ((s.weight ?? 0) != oldWeight) {
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

  /// Delete a set and renumber the remaining sets.
  Future<void> deleteSet(String workoutExerciseId, String setId) async {
    final current = state.value;
    if (current == null) return;

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

  /// Restore a previously deleted set at its original position.
  ///
  /// Inserts the [deletedSet] back into the exercise's set list and
  /// renumbers all sets sequentially. Used for undo-delete functionality.
  Future<void> restoreSet(
    String workoutExerciseId,
    ExerciseSet deletedSet,
  ) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        final sets = [...e.sets];
        // Insert at the original position (clamped to list bounds).
        final insertIndex = (deletedSet.setNumber - 1).clamp(0, sets.length);
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

  /// Fill all incomplete sets after the last completed set with its values.
  Future<void> fillRemainingSets(String workoutExerciseId) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        // Find the last completed set (highest setNumber).
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

        return e.copyWith(
          sets: e.sets.map((s) {
            if (!s.isCompleted && s.setNumber > lastCompleted!.setNumber) {
              return s.copyWith(
                weight: lastCompleted.weight,
                reps: lastCompleted.reps,
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
  Future<void> swapExercise(
    String workoutExerciseId,
    Exercise newExercise,
  ) async {
    final current = state.value;
    if (current == null) return;

    final newState = current.copyWith(
      exercises: current.exercises.map((e) {
        if (e.workoutExercise.id != workoutExerciseId) return e;

        return e.copyWith(
          workoutExercise: e.workoutExercise.copyWith(
            exerciseId: newExercise.id,
            exercise: newExercise,
          ),
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

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await _localStorage.clearActiveWorkout();
      await _repo.discardWorkout(current.workout.id, userId: _userId);

      final elapsedSeconds = DateTime.now()
          .toUtc()
          .difference(current.workout.startedAt)
          .inSeconds;
      final completedSets = current.exercises
          .expand((e) => e.sets)
          .where((s) => s.isCompleted)
          .length;
      // TODO post-PR: differentiate planned_bucket when config exposes the flag
      final source = current.routineId != null ? 'routine_card' : 'empty';
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

    if (_cancelRequested) {
      _cancelRequested = false;
      _isDiscarding = false;
      return;
    }

    state = result;
    _isDiscarding = false;
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
    // Tracked locally inside the guard scope — folded into the returned
    // [FinishWorkoutResult] so the caller reads it through the explicit
    // return value, not via a notifier field. Restores unidirectional
    // Riverpod data flow (BUG-039).
    var savedOffline = false;
    var serverErrorQueued = false;

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
    final exerciseIds = exercises
        .map((e) => e.workoutExercise.exerciseId)
        .toSet()
        .toList();

    state = const AsyncLoading();

    PRDetectionResult? prResult;
    // Hoisted so the analytics event can still report a number (0) when PR
    // detection throws before the count is fetched.
    int workoutCount = 0;

    final result = await AsyncValue.guard(() async {
      final now = DateTime.now().toUtc();
      final durationSeconds = now
          .difference(current.workout.startedAt)
          .inSeconds;

      final workout = current.workout.copyWith(
        finishedAt: now,
        durationSeconds: durationSeconds,
        isActive: false,
        notes: notes,
      );

      final workoutExercises = exercises.map((e) => e.workoutExercise).toList();
      final sets = exercises.expand((e) => e.sets).toList();

      // --- Save workout (online or offline queue) ---
      try {
        await _repo.saveWorkout(
          workout: workout,
          exercises: workoutExercises,
          sets: sets,
        );
      } catch (e) {
        // Classify at the catch site so terminal errors surface to the user
        // (AW-EX-D-US1-03, AW-EX-E-US1-02). Pre-1B every save failure was
        // uniformly enqueued as offline — a 4xx / RLS denial / FK violation
        // produced a "Saved offline" snackbar with no error indication, and
        // the queue then logged a structural failure no user could fix.
        //
        // Contract:
        //   - terminal (4xx, RLS, FK) → rethrow so the outer AsyncValue.guard
        //     lands in AsyncError; the coordinator's `asyncState.hasError`
        //     branch shows the localized "Failed to save workout" snackbar
        //     and the user keeps their unsaved local state.
        //   - transient (offline, timeout, 5xx, unknown) → enqueue.
        //   - 5xx specifically sets `serverErrorQueued = true` so the UI can
        //     pick a "server error — saved offline, will retry" copy variant
        //     (Q1.3 in the impact analysis).
        if (SyncErrorClassifier.isTerminal(e)) {
          log(
            'Terminal save error, surfacing to UI: $e',
            name: 'ActiveWorkoutNotifier',
            level: 1000,
          );
          rethrow;
        }
        log(
          'Network save failed, queueing offline: $e',
          name: 'ActiveWorkoutNotifier',
          level: 900,
        );
        savedOffline = true;
        // 5xx is transient (queue) but distinct from connectivity failure;
        // the queue still retries, but the UI tells the user it was a server
        // problem so a "Pending sync (1)" badge is not misleading.
        // [SyncErrorClassifier.httpCode] recognises both the raw
        // [supabase.PostgrestException] and the [BaseRepository]-mapped
        // [app.DatabaseException] / [app.AuthException] forms — the
        // production catch site sees the wrapped variant, but routing
        // through the canonical helper keeps the discriminator robust if a
        // future repository forgets to wrap or if a new code-bearing shape
        // is added to [SyncErrorClassifier.isTerminal] without updating
        // every call site.
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

        // BUG-003: when a workout references an exercise the user created
        // offline (still queued as PendingCreateExercise), tag this save
        // with `dependsOn: [createExerciseAction.id]` so the drain commits
        // the exercise BEFORE this workout — otherwise replay races the
        // `workout_exercises.exercise_id` FK and the workout fails terminally.
        final referencedExerciseIds = workoutExercises
            .map((e) => e.exerciseId)
            .toSet();
        final pendingActions = ref.read(pendingSyncProvider.notifier).getAll();
        final exerciseDependsOn = <String>[
          for (final a in pendingActions)
            if (a is PendingCreateExercise &&
                referencedExerciseIds.contains(a.exerciseId))
              a.id,
        ];

        await ref
            .read(pendingSyncProvider.notifier)
            .enqueue(
              PendingAction.saveWorkout(
                id: workout.id,
                workoutJson: workoutJson,
                exercisesJson: exercisesJson,
                setsJson: setsJson,
                userId: workout.userId,
                queuedAt: now,
                dependsOn: exerciseDependsOn,
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
          exercises: exercises,
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
                log(
                  'Direct PR upsert failed, falling back to queue: $e',
                  name: 'ActiveWorkoutNotifier',
                  level: 900,
                  error: e,
                  stackTrace: st,
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
                  // notifier. Log loud and move on.
                  log(
                    'Fallback enqueue also failed: $queueErr',
                    name: 'ActiveWorkoutNotifier',
                    level: 1000,
                    error: queueErr,
                    stackTrace: queueSt,
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
        log(
          'PR detection failed: $e',
          name: 'ActiveWorkoutNotifier',
          level: 900,
        );
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

      // Weekly plan: mark matching bucket routine as complete.
      try {
        final matchedRoutineId = current.routineId;
        if (matchedRoutineId != null) {
          final plan = ref.read(weeklyPlanProvider).value;
          if (plan != null && plan.routines.isNotEmpty) {
            final hasBucketMatch = plan.routines.any(
              (r) =>
                  r.routineId == matchedRoutineId &&
                  r.completedWorkoutId == null,
            );
            if (hasBucketMatch) {
              try {
                await ref
                    .read(weeklyPlanProvider.notifier)
                    .markRoutineComplete(
                      routineId: matchedRoutineId,
                      workoutId: workout.id,
                    );
              } catch (e) {
                log(
                  'Weekly plan update failed, queueing offline: $e',
                  name: 'ActiveWorkoutNotifier',
                  level: 900,
                );
                await ref
                    .read(pendingSyncProvider.notifier)
                    .enqueue(
                      PendingAction.markRoutineComplete(
                        id: _uuid.v4(),
                        planId: plan.id,
                        routineId: matchedRoutineId,
                        workoutId: workout.id,
                        queuedAt: now,
                      ),
                    );
              }
            }
          }
        }
      } catch (e) {
        // Weekly plan update failure should NOT fail the workout save.
        log(
          'Weekly plan update failed: $e',
          name: 'ActiveWorkoutNotifier',
          level: 900,
        );
      }

      final totalSets = sets.length;
      final completedSetsCount = sets.where((s) => s.isCompleted).length;
      final incompleteSetsSkipped = totalSets - completedSetsCount;
      final hadPr = prResult?.newRecords.isNotEmpty ?? false;
      // TODO post-PR: differentiate planned_bucket when config exposes the flag
      final source = current.routineId != null ? 'routine_card' : 'empty';
      _trackWorkoutEvent(
        event: AnalyticsEvent.workoutFinished(
          durationSeconds: durationSeconds,
          exerciseCount: exercises.length,
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

    if (_cancelRequested) {
      // User tapped Cancel while we were saving. cancelLoading() already
      // restored the previous state — discard this guard result so we don't
      // overwrite it.
      _cancelRequested = false;
      _isFinishing = false;
      return null;
    }

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
      log(
        'Celebration build failed: $e\n$st',
        name: 'ActiveWorkoutNotifier',
        level: 900,
      );
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
      log(
        'Failed to persist workout to Hive: $e',
        name: 'ActiveWorkoutNotifier',
        level: 900,
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
