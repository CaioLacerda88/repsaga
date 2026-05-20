import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rpg_repository.dart';
import '../domain/vitality_calculator.dart';
import '../domain/vitality_state_mapper.dart';
import '../models/body_part.dart';
import '../models/stats_deep_dive_state.dart';
import '../models/xp_event.dart';
import 'rpg_progress_provider.dart';

/// Async provider that composes the `/saga/stats` deep-dive screen state.
///
/// Reads from two sources — the per-body-part progress (via
/// [rpgProgressProvider]) and the user's recent `xp_events` (via
/// [RpgRepository.getRecentXpEvents]). Composition is a pure function
/// ([assembleStatsState]) so unit tests can pin the trend reconstruction +
/// per-body-part volume/peak derivations without touching Supabase.
///
/// **Why a `FutureProvider` not `AsyncNotifier`:** the screen is read-only
/// — there are no actions on this surface that need to mutate state. A
/// `FutureProvider` is the simpler primitive and matches the
/// "data-curious view" intent.
final statsProvider = FutureProvider<StatsDeepDiveState>((ref) async {
  // Wait for the upstream snapshot — drives the live Vitality table + the
  // current per-body-part EWMA values (the terminal point on each trend
  // line).
  final snapshot = await ref.watch(rpgProgressProvider.future);

  final rpgRepo = ref.watch(rpgRepositoryProvider);

  // 90 days of xp_events drives the trend reconstruction. The query is
  // capped at a generous 5000 rows so a 5-set/day power user with 90 days
  // of history (~450 events) is well below the cap. Repository pagination
  // is unnecessary here — the cap is a defensive ceiling, not the expected
  // size.
  final now = DateTime.now().toUtc();
  final since = now.subtract(const Duration(days: 90));
  final events = await _fetchRecentEvents(rpgRepo, since: since);

  // Phase 27 L10: heaviest-weight-per-body-part replaces the prior
  // EWMA-as-kg readout in the "Carga pico" column. Two round trips:
  //   * Current 7-day window — drives the kg value.
  //   * 30-days-ago snapshot (7-day window anchored 30 days back) —
  //     drives the monthly delta + "30D" badge.
  //
  // We only fetch the 30-days-ago snapshot when the user has enough
  // history for a meaningful baseline (earliest activity is older than
  // 30 days). Without this gate, the snapshot would always be empty for
  // fresh accounts and the empty round-trip would still cost a network
  // hop.
  final peakLoadKgByBodyPart = await rpgRepo.getPeakLoadPerBodyPart(
    days: 7,
    endDate: now,
  );
  Map<BodyPart, double> peakLoadKgByBodyPart30dAgo = const <BodyPart, double>{};
  final earliestEvent = events.isEmpty
      ? null
      : events.map((e) => e.occurredAt).reduce((a, b) => a.isBefore(b) ? a : b);
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));
  if (earliestEvent != null && !earliestEvent.isAfter(thirtyDaysAgo)) {
    peakLoadKgByBodyPart30dAgo = await rpgRepo.getPeakLoadPerBodyPart(
      days: 7,
      endDate: thirtyDaysAgo,
    );
  }

  return assembleStatsState(
    now: now,
    snapshot: snapshot,
    events: events,
    peakLoadKgByBodyPart: peakLoadKgByBodyPart,
    peakLoadKgByBodyPart30dAgo: peakLoadKgByBodyPart30dAgo,
  );
});

/// Pure assembler — extracted so unit tests can pin the algorithm without
/// spinning up a ProviderContainer or mocking Supabase.
///
/// Inputs:
///   * [now] — the "today" anchor; injected so tests can drive the hybrid
///     X-axis at exact day boundaries.
///   * [snapshot] — current EWMA + peak per body part.
///   * [events] — last 90 days of `xp_events` for this user, newest-first
///     order is fine; the assembler re-sorts by [XpEvent.occurredAt].
///
/// Output: a fully-derived [StatsDeepDiveState] ready for direct
/// `ref.read` consumption by the screen.
StatsDeepDiveState assembleStatsState({
  required DateTime now,
  required RpgProgressSnapshot snapshot,
  required List<XpEvent> events,
  Map<BodyPart, double> peakLoadKgByBodyPart = const <BodyPart, double>{},
  Map<BodyPart, double> peakLoadKgByBodyPart30dAgo = const <BodyPart, double>{},
}) {
  // ---------------------------------------------------------------------------
  // 1. Earliest activity + window selection.
  // ---------------------------------------------------------------------------
  // Re-sort events by occurrence ascending so the earliest is at index 0 and
  // the trend reconstruction can stream forward in time.
  final sorted = [...events]
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final earliest = sorted.isEmpty ? null : sorted.first.occurredAt;

  final today = DateTime.utc(now.year, now.month, now.day);
  // Hybrid X-axis: <30d of history → narrow window starting at earliest
  // activity. ≥30d → rolling 90-day window. Boundary day-30 falls into the
  // 90-day case (>=) per the WIP amendment.
  final useNarrow = earliest != null && today.difference(earliest).inDays < 30;
  final windowStart = useNarrow
      ? DateTime.utc(earliest.year, earliest.month, earliest.day)
      : today.subtract(const Duration(days: 90));

  // ---------------------------------------------------------------------------
  // 2. Live Vitality table — six rows, canonical order.
  // ---------------------------------------------------------------------------
  final vitalityRows = <VitalityTableRow>[];
  for (final bp in activeBodyParts) {
    final progress = snapshot.progressFor(bp);
    final pct = VitalityCalculator.percentage(
      ewma: progress.vitalityEwma,
      peak: progress.vitalityPeak,
    );
    vitalityRows.add(
      VitalityTableRow(
        bodyPart: bp,
        pct: pct,
        state: VitalityStateMapper.fromVitality(
          ewma: progress.vitalityEwma,
          peak: progress.vitalityPeak,
        ),
        rank: progress.rank,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Trend reconstruction — daily series per body part.
  // ---------------------------------------------------------------------------
  // We aggregate `attribution[bp]` into ISO-week buckets (the same cadence
  // the EWMA stepper expects per `VitalityCalculator.samplePeriodDays`),
  // run the stepper week-by-week starting from EWMA 0 + the persisted
  // peak, then linearly interpolate the weekly samples down to daily
  // granularity.
  final trendByBp = _reconstructTrends(
    sorted: sorted,
    windowStart: windowStart,
    windowEnd: today,
    snapshot: snapshot,
  );

  // ---------------------------------------------------------------------------
  // 4. Volume + Peak per body part. Phase 26c: extended with history-aware
  //    weekly delta (previousWeekVolumeSets / fourWeekMeanVolumeSets /
  //    weeksOfHistory) + the monthly peak delta (peakEwma30dAgo).
  //
  //    Three passes per body part over `sorted` (the existing 7-day rolling
  //    count, the new per-ISO-week bucket, and the trend reconstruction
  //    above) — O(n×|bp|) where n = ~450 events for a 90-day power user.
  //    ~8k ops total; intentional for readability over micro-optimisation.
  // ---------------------------------------------------------------------------
  final volumePeak = <BodyPart, VolumePeakRow>{};
  final weekAgo = today.subtract(const Duration(days: 7));
  final thirtyDaysAgo = today.subtract(const Duration(days: 30));
  final currentWeekStart = _isoWeekStart(today);

  for (final bp in activeBodyParts) {
    // Existing weekly volume count (last 7 days, not ISO-week-aligned).
    final setsLast7d = sorted
        .where(
          (e) =>
              e.occurredAt.isAfter(weekAgo) &&
              (e.attribution[bp.dbValue] as num? ?? 0) > 0,
        )
        .length;

    // Per-ISO-week bucket counts for this body part. Drives both the
    // previousWeek and fourWeekMean fields below.
    final perWeek = <DateTime, int>{};
    for (final e in sorted) {
      final attr = (e.attribution[bp.dbValue] as num? ?? 0);
      if (attr <= 0) continue;
      final wStart = _isoWeekStart(e.occurredAt);
      perWeek[wStart] = (perWeek[wStart] ?? 0) + 1;
    }
    final weeksOfHistory = perWeek.length;

    // Previous-week count (the ISO-week immediately before currentWeekStart).
    // Null when there's only one week of history — comparison wouldn't be
    // meaningful and the UI hides the delta row entirely.
    final previousWeekStart = currentWeekStart.subtract(
      const Duration(days: 7),
    );
    final previousWeekVolumeSets = weeksOfHistory >= 2
        ? (perWeek[previousWeekStart] ?? 0)
        : null;

    // Four-week mean over the 4 buckets BEFORE currentWeekStart (NOT
    // including the in-progress week — comparing against a partial week
    // would mislead). Null when weeksOfHistory < 5.
    //
    // Note: weeksOfHistory >= 5 is a proxy for "has 4 prior weeks of data" —
    // the individual weekly buckets may still be 0 (a user with activity in
    // weeks -7 and 0 only would qualify; the mean would be 0.0). Acceptable
    // per spec; the consuming UI's delta state handles 0/met-target gracefully.
    double? fourWeekMeanVolumeSets;
    if (weeksOfHistory >= 5) {
      var sum = 0;
      for (var w = 1; w <= 4; w++) {
        final ws = currentWeekStart.subtract(Duration(days: 7 * w));
        sum += (perWeek[ws] ?? 0);
      }
      fourWeekMeanVolumeSets = sum / 4.0;
    }

    // Peak EWMA 30 days ago — sample from the daily trend reconstruction by
    // closest-date lookup. Null when (a) untrained body part (peak == 0),
    // (b) earliest activity is within the 30-day window (no "30 days ago"
    // baseline yet), or (c) the trend is empty (defensive).
    final peak = snapshot.progressFor(bp).vitalityPeak;
    double? peakEwma30dAgo;
    if (peak > 0 && earliest != null && !earliest.isAfter(thirtyDaysAgo)) {
      final trend = trendByBp[bp] ?? const <TrendPoint>[];
      if (trend.isNotEmpty) {
        TrendPoint? closest;
        var bestDistance = double.infinity;
        for (final p in trend) {
          final dist = p.date
              .difference(thirtyDaysAgo)
              .inMilliseconds
              .abs()
              .toDouble();
          if (dist < bestDistance) {
            bestDistance = dist;
            closest = p;
          }
        }
        if (closest != null) {
          peakEwma30dAgo = closest.pct * peak;
        }
      }
    }

    // Phase 27 L10: heaviest single-set weight in kg per body part.
    // The repo returns only body parts that had non-zero-weight sets in
    // the window — absent body parts default to 0 (untrained). The
    // 30-days-ago snapshot is `null` when the map is empty (caller
    // decided the user has insufficient history to have a baseline) OR
    // when the body part is missing from a populated map (user is
    // trained but didn't lift this body part 30 days ago).
    final peakLoadKg = peakLoadKgByBodyPart[bp] ?? 0.0;
    final peakLoadKg30dAgo = peakLoadKgByBodyPart30dAgo.isEmpty
        ? null
        : peakLoadKgByBodyPart30dAgo[bp];

    volumePeak[bp] = VolumePeakRow(
      weeklyVolumeSets: setsLast7d,
      peakEwma: peak,
      peakLoadKg: peakLoadKg,
      peakLoadKg30dAgo: peakLoadKg30dAgo,
      previousWeekVolumeSets: previousWeekVolumeSets,
      fourWeekMeanVolumeSets: fourWeekMeanVolumeSets,
      peakEwma30dAgo: peakEwma30dAgo,
      weeksOfHistory: weeksOfHistory,
    );
  }

  return StatsDeepDiveState(
    vitalityRows: vitalityRows,
    trendByBodyPart: trendByBp,
    volumePeakByBodyPart: volumePeak,
    earliestActivity: earliest,
    windowStart: windowStart,
    windowEnd: today,
  );
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// Aggregate xp_events into weekly buckets per body part, run the EWMA
/// stepper, and interpolate to daily granularity.
///
/// The end-of-trace per body part is anchored to the persisted current
/// EWMA (the live value from `body_part_progress`). This keeps the chart's
/// terminal point in lock-step with the table row above it — the line
/// always lands exactly where the % readout says it should.
Map<BodyPart, List<TrendPoint>> _reconstructTrends({
  required List<XpEvent> sorted,
  required DateTime windowStart,
  required DateTime windowEnd,
  required RpgProgressSnapshot snapshot,
}) {
  final out = <BodyPart, List<TrendPoint>>{};
  final spanDays = windowEnd.difference(windowStart).inDays;
  if (spanDays < 1) {
    for (final bp in activeBodyParts) {
      out[bp] = const <TrendPoint>[];
    }
    return out;
  }

  // Number of weekly sample points spanning the window. We always include
  // both endpoints (windowStart and windowEnd) so the trace lands exactly
  // on the visible chart edges.
  final weekCount = math.max(2, (spanDays / 7).ceil() + 1);

  for (final bp in activeBodyParts) {
    final progress = snapshot.progressFor(bp);
    final peak = progress.vitalityPeak;
    if (peak <= 0) {
      // Untrained body part — flat-zero series, but we still emit a series
      // of the same length as the others so the chart can render six lines
      // without per-line empty-state branching.
      out[bp] = [
        for (var i = 0; i < weekCount; i++)
          TrendPoint(
            date: _interpDate(windowStart, windowEnd, i, weekCount),
            pct: 0,
          ),
      ];
      continue;
    }

    // Bucket events by week index relative to windowStart.
    final weeklyVolume = List<double>.filled(weekCount, 0);
    for (final e in sorted) {
      final attr = (e.attribution[bp.dbValue] as num?)?.toDouble() ?? 0;
      if (attr <= 0) continue;
      if (e.occurredAt.isBefore(windowStart) ||
          e.occurredAt.isAfter(windowEnd)) {
        continue;
      }
      final dayOffset = e.occurredAt.difference(windowStart).inDays;
      final wIdx = (dayOffset / 7).floor().clamp(0, weekCount - 1);
      weeklyVolume[wIdx] += attr;
    }

    // Run the EWMA stepper week-by-week from 0. The terminal value is
    // *theoretical* — driven only by what the events imply for this
    // window. We then apply a single rescale at the end so the terminal
    // matches the persisted current EWMA exactly.
    final weeklyEwma = List<double>.filled(weekCount, 0);
    var ewma = 0.0;
    for (var i = 0; i < weekCount; i++) {
      final s = VitalityCalculator.step(
        priorEwma: ewma,
        priorPeak: peak,
        weeklyVolume: weeklyVolume[i],
      );
      ewma = s.ewma;
      weeklyEwma[i] = ewma;
    }

    // Anchor the terminal to the persisted current EWMA. If the
    // theoretical terminal is zero (the user trained earlier but no events
    // in this window), fall back to the persisted EWMA as a flat trace.
    final theoreticalTerminal = weeklyEwma.last;
    final actualTerminal = progress.vitalityEwma;
    final scale = theoreticalTerminal > 0
        ? actualTerminal / theoreticalTerminal
        : 0.0;
    if (scale > 0) {
      for (var i = 0; i < weekCount; i++) {
        weeklyEwma[i] *= scale;
      }
    } else if (actualTerminal > 0) {
      // No events in window but EWMA is nonzero — flat trace at the
      // current value. Trace the user's "carried-over" conditioning.
      for (var i = 0; i < weekCount; i++) {
        weeklyEwma[i] = actualTerminal;
      }
    }

    // Interpolate weekly samples to daily granularity. We keep the daily
    // resolution for the chart so smooth curves render without bunching.
    // Length: spanDays + 1 (inclusive endpoints).
    final dayCount = spanDays + 1;
    final dailyPct = List<double>.filled(dayCount, 0);
    for (var d = 0; d < dayCount; d++) {
      final tWeek = (d / spanDays) * (weekCount - 1);
      final lo = tWeek.floor().clamp(0, weekCount - 1);
      final hi = math.min(lo + 1, weekCount - 1);
      final frac = tWeek - lo;
      final value = weeklyEwma[lo] * (1 - frac) + weeklyEwma[hi] * frac;
      dailyPct[d] = (value / peak).clamp(0, 1).toDouble();
    }

    out[bp] = [
      for (var d = 0; d < dayCount; d++)
        TrendPoint(
          date: windowStart.add(Duration(days: d)),
          pct: dailyPct[d],
        ),
    ];
  }

  return out;
}

DateTime _interpDate(DateTime start, DateTime end, int i, int count) {
  final t = count <= 1 ? 0.0 : i / (count - 1);
  final spanMs = end.difference(start).inMilliseconds;
  return start.add(Duration(milliseconds: (spanMs * t).round()));
}

/// Returns the Monday-00:00-UTC start of the ISO week containing [d].
///
/// `DateTime.weekday` is 1 (Monday) through 7 (Sunday). Subtracting
/// `(weekday - 1)` days lands on Monday; the additional `DateTime.utc`
/// truncation strips the time component so the bucket key is stable
/// across same-week events at different hours.
DateTime _isoWeekStart(DateTime d) {
  final utc = DateTime.utc(d.year, d.month, d.day);
  final daysFromMonday = (utc.weekday - DateTime.monday) % 7;
  return utc.subtract(Duration(days: daysFromMonday));
}

// ---------------------------------------------------------------------------
// Repository helpers — kept private; callers consume [statsProvider].
// ---------------------------------------------------------------------------

/// Fetch `xp_events` since [since], paginating up to a hard cap to avoid an
/// unbounded query for outlier accounts. The repository returns newest-first;
/// we paginate via the `olderThan` cursor until exhausted or the cap is hit.
Future<List<XpEvent>> _fetchRecentEvents(
  RpgRepository repo, {
  required DateTime since,
}) async {
  const pageSize = 500;
  const hardCap = 5000;
  final out = <XpEvent>[];
  DateTime? cursor;
  while (out.length < hardCap) {
    final page = await repo.getRecentXpEvents(
      limit: pageSize,
      olderThan: cursor,
    );
    if (page.isEmpty) break;
    final filtered = page
        .where((e) => !e.occurredAt.isBefore(since))
        .toList(growable: false);
    out.addAll(filtered);
    if (filtered.length < page.length) break;
    cursor = page.last.occurredAt;
    if (page.length < pageSize) break;
  }
  return out;
}
