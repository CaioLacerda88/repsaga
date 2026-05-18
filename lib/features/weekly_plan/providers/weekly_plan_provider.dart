import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../../core/device/platform_info.dart';
import '../../analytics/data/models/analytics_event.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../personal_records/providers/pr_providers.dart' show prListProvider;
import '../data/models/weekly_plan.dart';
import '../data/weekly_plan_repository.dart';

/// Provides the [WeeklyPlanRepository] singleton.
final weeklyPlanRepositoryProvider = Provider<WeeklyPlanRepository>((ref) {
  return WeeklyPlanRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Computes the ordinal week number since user signup from a Supabase
/// `User.createdAt` string. Returns null when [createdAtIso] is null or
/// cannot be parsed — callers should skip the analytics event entirely in
/// that case (better to omit than ship week_number: 0).
///
/// Formula: `floor(daysSinceSignup / 7) + 1`, so days 0-6 after signup map
/// to week 1, days 7-13 to week 2, etc. A negative result (clock skew)
/// clamps to 1.
int? computeWeekNumberSinceSignup(String? createdAtIso, {DateTime? now}) {
  if (createdAtIso == null || createdAtIso.isEmpty) return null;
  final createdAt = DateTime.tryParse(createdAtIso);
  if (createdAt == null) return null;
  final current = now ?? DateTime.now().toUtc();
  final diff = current.difference(createdAt);
  final days = diff.inDays;
  if (days < 0) return 1; // clock skew — clamp rather than drop the event
  return (days ~/ 7) + 1;
}

/// Private wrapper around [computeWeekNumberSinceSignup] for the notifier.
int? _computeWeekNumberSinceSignup(String? createdAtIso) =>
    computeWeekNumberSinceSignup(createdAtIso);

/// Returns the Monday (ISO week start) for the given date.
DateTime currentWeekMonday([DateTime? now]) {
  final date = now ?? DateTime.now();
  // DateTime.weekday: Monday = 1, Sunday = 7
  final daysFromMonday = date.weekday - 1;
  final monday = DateTime(date.year, date.month, date.day - daysFromMonday);
  return monday;
}

/// Manages the current week's plan state.
class WeeklyPlanNotifier extends AsyncNotifier<WeeklyPlan?> {
  @override
  FutureOr<WeeklyPlan?> build() async {
    // Detect plan-fully-completed transitions and fire week_complete once.
    // Previously this lived inside `markRoutineComplete`; with the 00063
    // `save_workout` RPC owning the server-side bucket update (26e), the
    // notifier no longer mutates the bucket directly — it observes the
    // refetched state after callers `ref.invalidate(weeklyPlanProvider)`.
    // The `!wasAllComplete && isNowAllComplete` guard makes this fire
    // exactly once per transition (idempotent re-fetches that produce the
    // same all-complete state see `wasAllComplete == true` and skip).
    listenSelf((previous, next) {
      final prevPlan = previous?.value;
      final nextPlan = next.value;
      if (nextPlan == null) return;
      final wasAllComplete =
          prevPlan != null &&
          prevPlan.routines.isNotEmpty &&
          prevPlan.routines.every((r) => r.completedWorkoutId != null);
      final isNowAllComplete =
          nextPlan.routines.isNotEmpty &&
          nextPlan.routines.every((r) => r.completedWorkoutId != null);
      if (!wasAllComplete && isNowAllComplete) {
        _fireWeekCompleteEvent(nextPlan);
      }
    });

    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return null;
    final repo = ref.watch(weeklyPlanRepositoryProvider);
    final monday = currentWeekMonday();

    final existing = await repo.getPlanForWeek(userId, monday);
    if (existing != null) return existing;

    // No plan for this week — schedule auto-populate after build completes.
    // We must not perform write side-effects or modify other providers during
    // build() (Riverpod anti-pattern that causes "Cannot modify state during
    // build" errors and infinite rebuilds).
    Future.microtask(() => _tryAutoPopulate(userId, monday));
    return null;
  }

  /// Attempts to auto-populate the current week from the previous week's plan.
  ///
  /// Called via microtask after build() to avoid modifying state during build.
  /// Strips all completion data so the new week starts fresh (BUG-R1).
  /// Filters out spontaneous entries (26e) so only planned routines carry
  /// forward, then renumbers `order` contiguously starting at 1.
  Future<void> _tryAutoPopulate(String userId, DateTime monday) async {
    final repo = ref.read(weeklyPlanRepositoryProvider);
    final previous = await repo.getPreviousWeekPlan(userId, monday);
    if (previous == null || previous.routines.isEmpty) return;

    // Drop spontaneous entries: only planned routines roll forward.
    // Reset completion fields (workoutId / completedAt) by reconstructing
    // each BucketRoutine without them, then renumber so the new week's
    // order is 1, 2, 3, ... (no gaps left by the filtered-out spontaneous
    // entries).
    final resetRoutines = previous.routines
        .where((r) => !r.isSpontaneous)
        .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
        .toList();
    final renumbered = resetRoutines.indexed
        .map((entry) => entry.$2.copyWith(order: entry.$1 + 1))
        .toList();

    // Nothing to roll forward — either every entry was spontaneous, or the
    // previous-week list was empty after the filter. Leave the new week
    // unpopulated; the user starts with an empty bucket.
    if (renumbered.isEmpty) return;

    final plan = await repo.upsertPlan(
      userId: userId,
      weekStart: monday,
      routines: renumbered,
    );

    state = AsyncData(plan);

    // Signal the UI to show the "Same plan this week?" confirmation banner.
    ref.read(weeklyPlanNeedsConfirmationProvider.notifier).state = true;
  }

  /// Create or update the current week's plan with the given routines.
  Future<void> upsertPlan(List<BucketRoutine> routines) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;
    final repo = ref.read(weeklyPlanRepositoryProvider);
    final monday = currentWeekMonday();
    state = await AsyncValue.guard(() async {
      return repo.upsertPlan(
        userId: userId,
        weekStart: monday,
        routines: routines,
      );
    });
  }

  // markRoutineComplete is gone (26e): the 00063 save_workout RPC updates
  // the bucket entry server-side in the same transaction as the workout
  // insert. After saveWorkout, callers `ref.invalidate(weeklyPlanProvider)`
  // to re-fetch the updated row. The week_complete analytics event now
  // fires from the `listenSelf` callback in build() — same payload, same
  // fire-once guard.

  /// Fires the `week_complete` analytics event for a fully-completed plan.
  ///
  /// Extracted from the old `markRoutineComplete` body so the firing site
  /// is the only thing that changed (payload + fire-once guard unchanged).
  void _fireWeekCompleteEvent(WeeklyPlan plan) {
    final authUser = ref.read(authRepositoryProvider).currentUser;
    final userId = authUser?.id;
    if (userId == null) return;
    // NOTE: `weekStart` is the client-local Monday midnight (see
    // currentWeekMonday). A PR achieved in a different timezone near the
    // week boundary could be miscounted here; acceptable for now since
    // SQL can also derive this from pr_celebration_seen events later.
    final weekStart = plan.weekStart;
    final weekEnd = weekStart.add(const Duration(days: 7));
    // Read the PR list without awaiting. On a cold read (never warmed up
    // by the PR list screen or recent PRs widget), this returns null and
    // we fall back to 0 — SQL can correct it from pr_celebration_seen.
    final prsAsync = ref.read(prListProvider);
    final prCountThisWeek =
        prsAsync.value
            ?.where(
              (pr) =>
                  pr.achievedAt.isAfter(weekStart) &&
                  pr.achievedAt.isBefore(weekEnd),
            )
            .length ??
        0;
    // Week number = ordinal week since user signup, computed from
    // auth.users.created_at. Formula: floor(daysSinceSignup / 7) + 1,
    // so the first seven days post-signup = week 1. If created_at is
    // not parseable we skip the event entirely — shipping a
    // known-bad column (week_number: 0) is worse than omitting it.
    final weekNumber = _computeWeekNumberSinceSignup(authUser?.createdAt);
    if (weekNumber == null) return;
    unawaited(
      ref
          .read(analyticsRepositoryProvider)
          .insertEvent(
            userId: userId,
            event: AnalyticsEvent.weekComplete(
              sessionsCompleted: plan.routines
                  .where((r) => r.completedWorkoutId != null)
                  .length,
              prCountThisWeek: prCountThisWeek,
              planSize: plan.routines.length,
              weekNumber: weekNumber,
            ),
            platform: currentPlatform(),
            appVersion: currentAppVersion(),
          ),
    );
  }

  /// Auto-populate from last week's plan (reset completions).
  ///
  /// Filters out spontaneous entries (26e) so only planned routines carry
  /// forward, then renumbers `order` contiguously starting at 1.
  Future<WeeklyPlan?> autoPopulateFromLastWeek() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return null;
    final repo = ref.read(weeklyPlanRepositoryProvider);
    final monday = currentWeekMonday();

    final previous = await repo.getPreviousWeekPlan(userId, monday);
    if (previous == null || previous.routines.isEmpty) return null;

    // Drop spontaneous entries: only planned routines roll forward. Reset
    // completion fields and renumber for a contiguous 1..N order.
    final resetRoutines = previous.routines
        .where((r) => !r.isSpontaneous)
        .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
        .toList();
    final renumbered = resetRoutines.indexed
        .map((entry) => entry.$2.copyWith(order: entry.$1 + 1))
        .toList();
    if (renumbered.isEmpty) return null;

    final plan = await repo.upsertPlan(
      userId: userId,
      weekStart: monday,
      routines: renumbered,
    );
    state = AsyncData(plan);
    return plan;
  }

  /// Add a routine to the current week's plan.
  ///
  /// Returns `true` if the routine was added, `false` if it was already
  /// present or no plan exists to add to.
  Future<bool> addRoutineToPlan(String routineId) async {
    final plan = state.value;
    if (plan == null) return false;

    // Already in plan — nothing to do.
    if (plan.routines.any((r) => r.routineId == routineId)) return false;

    final updatedRoutines = [
      ...plan.routines,
      BucketRoutine(routineId: routineId, order: plan.routines.length + 1),
    ];
    try {
      await upsertPlan(updatedRoutines);
      return !state.hasError;
    } catch (_) {
      return false;
    }
  }

  /// Clear the current week's plan.
  Future<void> clearPlan() async {
    final plan = state.value;
    if (plan == null) return;
    final repo = ref.read(weeklyPlanRepositoryProvider);
    await repo.deletePlan(plan.id);
    state = const AsyncData(null);
  }

  /// Force-refresh from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final weeklyPlanProvider =
    AsyncNotifierProvider<WeeklyPlanNotifier, WeeklyPlan?>(
      WeeklyPlanNotifier.new,
    );

/// Derived boolean: true iff the current week's plan exists AND has at least
/// one routine. Consumer widgets that only need the "is there an active plan?"
/// boolean should watch this instead of `weeklyPlanProvider` — that way they
/// rebuild on transitions (plan created / cleared / all routines removed) and
/// not on every routine-level mutation inside an existing plan (add/remove/
/// mark-complete/rename).
final hasActivePlanProvider = Provider<bool>((ref) {
  final plan = ref.watch(weeklyPlanProvider).value;
  return plan != null && plan.routines.isNotEmpty;
});

/// Whether the current week plan needs confirmation (auto-populated but not
/// explicitly confirmed by the user). True when plan exists and was just
/// created by auto-populate at the start of the week.
///
/// This is a simple client-side state — we track it in memory only.
final weeklyPlanNeedsConfirmationProvider = StateProvider<bool>((ref) => false);
