import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../core/utils/workout_formatters.dart';
import '../../auth/providers/auth_invalidation.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/workout_repository.dart';
import '../models/workout.dart';
import 'workout_providers.dart';

/// Reactive state slice emitted by [WorkoutHistoryNotifier].
///
/// Bundles the paginated `workouts` list with the two pagination flags so
/// `ref.watch(workoutHistoryProvider).whenData((state) => state.isLoadingMore)`
/// is genuinely reactive: a `loadMore()` call assigns a new state value, and
/// every subscriber sees the updated `isLoadingMore`/`hasMore` immediately.
///
/// Pre-PR-#285 the flags lived as private fields on the notifier with
/// public getters, which meant `ref.read(provider.notifier).isLoadingMore`
/// inside a `data:` callback never rebuilt the consumer when the flag
/// flipped — the spinner could miss its window entirely. The state-class
/// design closes that reactivity hole. See PR #285 review (Blocker 2).
typedef WorkoutHistoryState = ({
  List<Workout> workouts,
  bool isLoadingMore,
  bool hasMore,
});

/// Paginated workout history (finished workouts only).
///
/// Emits a [WorkoutHistoryState] (workouts + pagination flags) so consumers
/// that need to react to `isLoadingMore` / `hasMore` transitions can do so
/// through plain `ref.watch`. See [WorkoutHistoryState] for the rationale.
class WorkoutHistoryNotifier extends AsyncNotifier<WorkoutHistoryState> {
  static const _pageSize = 20;

  @override
  FutureOr<WorkoutHistoryState> build() async {
    // BUG-040: drop cached pages when the signed-in user changes so user
    // A's history never bleeds into user B's session after a sign-out →
    // sign-in. AsyncNotifier survives across user switches inside the same
    // process so the explicit listener is required.
    invalidateOnUserIdChange(ref);
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) {
      return (
        workouts: const <Workout>[],
        isLoadingMore: false,
        hasMore: false,
      );
    }
    final locale = ref.watch(localeProvider).languageCode;
    final repo = ref.watch(workoutRepositoryProvider);
    final workouts = await repo.getWorkoutHistory(
      userId,
      locale: locale,
      limit: _pageSize,
    );
    return (
      workouts: workouts,
      isLoadingMore: false,
      hasMore: workouts.length >= _pageSize,
    );
  }

  /// Load the next page and append to the current list.
  ///
  /// State transitions: emits an `isLoadingMore: true` snapshot before
  /// awaiting the RPC, then emits the appended page with
  /// `isLoadingMore: false` once the call settles. The intermediate emit
  /// is what makes the load-more spinner reactive — without it the screen
  /// would only re-render on the final result, not while waiting.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return;
    if (!current.hasMore) return;
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) return;

    state = AsyncData((
      workouts: current.workouts,
      isLoadingMore: true,
      hasMore: current.hasMore,
    ));

    try {
      final repo = ref.read(workoutRepositoryProvider);
      final locale = ref.read(localeProvider).languageCode;
      final more = await repo.getWorkoutHistory(
        userId,
        locale: locale,
        limit: _pageSize,
        offset: current.workouts.length,
      );
      state = AsyncData((
        workouts: [...current.workouts, ...more],
        isLoadingMore: false,
        hasMore: more.length >= _pageSize,
      ));
    } catch (_) {
      // Restore the pre-attempt flags so a transient failure doesn't strand
      // the spinner in the rendered tree. Surfacing the error itself is the
      // screen layer's job via the outer AsyncError branch on the next
      // refresh.
      state = AsyncData((
        workouts: current.workouts,
        isLoadingMore: false,
        hasMore: current.hasMore,
      ));
      rethrow;
    }
  }

  /// Force-refresh from the first page.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Provides paginated workout history.
final workoutHistoryProvider =
    AsyncNotifierProvider<WorkoutHistoryNotifier, WorkoutHistoryState>(
      WorkoutHistoryNotifier.new,
    );

/// Total count of finished workouts for the current user.
///
/// Uses a server-side `COUNT(*)` query rather than the paginated list length,
/// so it returns the real total regardless of page size.
///
/// `ref.keepAlive()` prevents Riverpod from disposing the provider when the
/// last listener unsubscribes — the count is watched from multiple screens
/// (Home's beginner CTA guard, Profile, Manage Data) and navigating between
/// them would otherwise re-issue the `COUNT(*)` query on every push/pop.
/// Explicit `ref.invalidate(workoutCountProvider)` calls (on workout save,
/// data reset) still force a fresh fetch regardless of keepAlive.
final workoutCountProvider = FutureProvider<int>((ref) {
  ref.keepAlive();
  // BUG-040: keepAlive survives a logout, so without an explicit listener
  // user A's COUNT(*) result would be served to user B after sign-out →
  // sign-in. The listener short-circuits when the user-id slice is
  // unchanged so token refreshes don't re-issue the query.
  invalidateOnUserIdChange(ref);
  final userId = ref.read(authRepositoryProvider).currentUser?.id;
  if (userId == null) return 0;
  final repo = ref.watch(workoutRepositoryProvider);
  return repo.getFinishedWorkoutCount(userId);
});

/// Derived boolean: true iff the user has at least one finished workout.
///
/// Consumer widgets that only need the "has any history?" boolean should
/// watch this instead of [workoutHistoryProvider] — that way they rebuild
/// only on the false→true transition (or back to zero on data reset) and
/// NOT on every `loadMore()` page-append. Also faster to read at cold
/// start since [workoutCountProvider] is `keepAlive` and returns a single
/// integer rather than waiting on the paginated list.
final hasAnyWorkoutProvider = Provider<bool>((ref) {
  final count = ref.watch(workoutCountProvider).value;
  return count != null && count > 0;
});

/// Fetch full workout detail for a specific workout.
///
/// Uses `autoDispose` so the detail is freed when the user navigates away
/// from the workout detail screen. Reads the active locale + signed-in
/// user from providers and forwards both to the repo so exercise names
/// resolve in the user's language.
final workoutDetailProvider = FutureProvider.autoDispose
    .family<WorkoutDetail, String>((ref, workoutId) {
      final repo = ref.watch(workoutRepositoryProvider);
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        throw StateError('workoutDetailProvider requires a signed-in user');
      }
      final locale = ref.watch(localeProvider).languageCode;
      return repo.getWorkoutDetail(workoutId, userId: userId, locale: locale);
    });

/// Data about the user's most recent completed workout.
///
/// Returns the workout name and how long ago it was. Used by the editorial
/// "Last: ..." line on the Home screen. Derives from the already-loaded
/// history.
typedef LastSessionInfo = ({String name, String relativeDate, DateTime date});

// Returns null during loading, on error, or when no workouts exist.
// UI shows "No workouts yet" for all three.
final lastSessionProvider = Provider<LastSessionInfo?>((ref) {
  final history = ref.watch(workoutHistoryProvider).value?.workouts;
  if (history == null || history.isEmpty) return null;
  final workout = history.first;
  final date = workout.finishedAt ?? workout.startedAt;
  return (
    name: workout.name,
    relativeDate: _formatRelativeDate(date),
    date: date,
  );
});

/// Format a date relative to today for stat cell display.
///
/// Normalizes both dates to local time before comparison, so UTC timestamps
/// from Supabase are correctly compared against the user's local "today".
///
/// Delegates to [WorkoutFormatters.formatRelativeDate]. Since providers lack
/// `BuildContext`, the formatter falls back to English when no `l10n` is
/// available. The UI layer (`LastSessionLine`) displays the result as-is;
/// full localization happens when the widget is rebuilt with a locale change.
String _formatRelativeDate(DateTime date) {
  return WorkoutFormatters.formatRelativeDate(date.toLocal());
}
