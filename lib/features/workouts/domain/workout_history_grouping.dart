import '../models/workout.dart';

/// One ISO-week group of workouts surfaced on the History list.
///
/// * [weekStart] — Monday-at-00:00 local time of the week the contained
///   workouts fall into. Always at the local midnight boundary so two
///   workouts in the same calendar week share the same [weekStart] key
///   regardless of the time of day they finished.
/// * [workouts] — the workouts that finished inside this week, preserving
///   the input order (which the History feed sorts most-recent-first).
/// * [totalSets] — sum of set counts across [workouts]. Sourced from the
///   `setCountFor` callback the caller supplies (the [Workout] model
///   doesn't carry a set count on history-list rows; the screen feeds in
///   either a cached `exerciseSummary`-derived count, or — in the
///   simplest current implementation — `0` when no per-workout set count
///   is available yet).
/// * [totalXp] — sum of [Workout.totalXp] across [workouts]. Read directly
///   from the model field (populated by the Phase 32 PR 32f history RPC).
typedef WeekGroup = ({
  DateTime weekStart,
  List<Workout> workouts,
  int totalSets,
  int totalXp,
});

/// Groups a History feed into ISO-week buckets (Monday-start).
///
/// **Algorithm.**
///
///   1. For each workout, derive its "anchor instant" as
///      `(finishedAt ?? startedAt).toLocal()`. The `.toLocal()` step is
///      load-bearing — Supabase stores timestamps as UTC, so a workout
///      finished at 23:00 BRT (UTC-3) serializes as next-day 02:00Z; a
///      UTC-relative week boundary would place that workout in the
///      following week from the lifter's POV. Same cluster as
///      `weekday-utc-vs-local-drift`.
///   2. Compute the Monday-of-that-week (`weekday == 1` per Dart's
///      `DateTime.weekday`) at local-midnight. Workouts finished on
///      Sunday 23:59 local stay in the week that ended on that Sunday.
///   3. Group by [weekStart] preserving input order inside each bucket;
///      sort the resulting groups descending by [weekStart] so the
///      most-recent week renders first (matching the History feed's
///      most-recent-first contract).
///
/// **Locale.**
///
/// ISO 8601 defines week-start as Monday. Every locale RepSaga supports
/// today (en, pt-BR) honors that convention. The [locale] parameter is
/// retained for forward-compat with locales that would prefer Sunday-start
/// (en_US bias) — if such a locale ships, this function is the single
/// place to branch. Until then, Monday-start is universal.
///
/// **Pure function.** No `DateTime.now()` reads, no IO, no provider
/// access. Deterministic for fixed input.
List<WeekGroup> groupByIsoWeek(
  List<Workout> workouts,
  String locale, {
  int Function(Workout)? setCountFor,
}) {
  if (workouts.isEmpty) return const [];

  final counter = setCountFor ?? (_) => 0;

  // Build the buckets keyed by the Monday-of-week local-midnight instant.
  // Using `LinkedHashMap` (the default `Map<>` type) keeps insertion order
  // — which matches the input order — so the workouts inside each bucket
  // render most-recent-first when the input is already sorted that way.
  final byWeek = <DateTime, List<Workout>>{};
  for (final workout in workouts) {
    final anchor = (workout.finishedAt ?? workout.startedAt).toLocal();
    final weekStart = _mondayOfWeek(anchor);
    byWeek.putIfAbsent(weekStart, () => <Workout>[]).add(workout);
  }

  // Materialize WeekGroup records with aggregate totals, then sort
  // descending by weekStart so the most-recent week appears first.
  final groups = byWeek.entries.map((entry) {
    final ws = entry.value;
    final totalSets = ws.fold<int>(0, (sum, w) => sum + counter(w));
    final totalXp = ws.fold<int>(0, (sum, w) => sum + w.totalXp);
    return (
      weekStart: entry.key,
      workouts: ws,
      totalSets: totalSets,
      totalXp: totalXp,
    );
  }).toList();
  groups.sort((a, b) => b.weekStart.compareTo(a.weekStart));
  return groups;
}

/// Returns the Monday-at-00:00 local instant for the week containing
/// [date]. `date` is assumed already-local (the caller is responsible for
/// the `.toLocal()` conversion — see [groupByIsoWeek] for the canonical
/// call site).
///
/// Dart's `DateTime.weekday` returns 1..7 with Monday == 1, so
/// `weekday - 1` is the count of days to subtract. The resulting
/// `DateTime(year, month, day)` discards the time-of-day component,
/// landing on local midnight.
DateTime _mondayOfWeek(DateTime date) {
  final daysSinceMonday = date.weekday - 1;
  final monday = DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: daysSinceMonday));
  return monday;
}
