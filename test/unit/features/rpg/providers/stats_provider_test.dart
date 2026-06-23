/// Unit tests for the [statsProvider] pure assembler ([assembleStatsState]).
///
/// We test the assembler directly rather than through a ProviderContainer —
/// the provider's job is wiring (auth + locale + repo lookups), the assembler
/// is the algorithm, and that's where regressions hide. The Riverpod
/// composition is tested separately via the widget-level smoke test on
/// [StatsDeepDiveScreen] which overrides [statsProvider] with a static
/// `AsyncData`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart'
    show CharacterState;
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/models/xp_event.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/rpg/providers/stats_provider.dart';

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

BodyPartProgress _progress({
  required BodyPart bp,
  int rank = 1,
  double totalXp = 0,
  double vitalityEwma = 0,
  double vitalityPeak = 0,
}) {
  return BodyPartProgress(
    userId: 'u1',
    bodyPart: bp,
    totalXp: totalXp,
    rank: rank,
    vitalityEwma: vitalityEwma,
    vitalityPeak: vitalityPeak,
    vitalityRefPeak: vitalityPeak,
    lastEventAt: null,
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

XpEvent _event({
  required DateTime occurredAt,
  required Map<String, double> attribution,
  String setId = 'set-1',
}) {
  return XpEvent(
    id: 'evt-${occurredAt.toIso8601String()}',
    userId: 'u1',
    eventType: 'set',
    setId: setId,
    sessionId: 'sess-1',
    payload: const {},
    attribution: attribution,
    totalXp: attribution.values.fold(0, (a, b) => a + b),
    occurredAt: occurredAt,
    createdAt: occurredAt,
  );
}

void main() {
  // Anchor "now" so all tests are deterministic regardless of when they run.
  final now = DateTime.utc(2026, 4, 30);

  group('assembleStatsState — Vitality table', () {
    test('day-0 user produces six untested rows in canonical order', () {
      // 2026-05-04 untested patch: every body part with peak == 0 maps to
      // VitalityState.untested. The vitality table renders `—` (not `0%`)
      // for these rows; see vitality_table_test.dart for the readout pin.
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: const [],
      );

      // Phase 38e: activeBodyParts is now 7 (cardio joined). The stats
      // surfaces iterate activeBodyParts, so the vitality table auto-extends
      // to a 7th cardio row.
      expect(state.vitalityRows.length, 7);
      expect(
        state.vitalityRows.map((r) => r.bodyPart).toList(),
        activeBodyParts,
      );
      for (final row in state.vitalityRows) {
        expect(row.pct, 0);
        expect(row.state, VitalityState.untested);
        expect(row.rank, 1);
      }
    });

    test('partially-trained user has correct pct + state per body part', () {
      // Chest at 80%, Back at 25%, Legs at 50% — three §8.4 bands sampled.
      final snapshot = RpgProgressSnapshot(
        byBodyPart: {
          BodyPart.chest: _progress(
            bp: BodyPart.chest,
            rank: 5,
            totalXp: 300,
            vitalityEwma: 80,
            vitalityPeak: 100,
          ),
          BodyPart.back: _progress(
            bp: BodyPart.back,
            rank: 3,
            totalXp: 100,
            vitalityEwma: 25,
            vitalityPeak: 100,
          ),
          BodyPart.legs: _progress(
            bp: BodyPart.legs,
            rank: 4,
            totalXp: 200,
            vitalityEwma: 50,
            vitalityPeak: 100,
          ),
        },
        characterState: CharacterState.empty,
      );
      final state = assembleStatsState(
        now: now,
        snapshot: snapshot,
        events: const [],
      );

      final chest = state.vitalityRows.firstWhere(
        (r) => r.bodyPart == BodyPart.chest,
      );
      expect(chest.pct, closeTo(0.80, 1e-9));
      expect(chest.state, VitalityState.radiant);
      expect(chest.rank, 5);

      final back = state.vitalityRows.firstWhere(
        (r) => r.bodyPart == BodyPart.back,
      );
      expect(back.pct, closeTo(0.25, 1e-9));
      expect(back.state, VitalityState.fading);

      final legs = state.vitalityRows.firstWhere(
        (r) => r.bodyPart == BodyPart.legs,
      );
      expect(legs.pct, closeTo(0.50, 1e-9));
      expect(legs.state, VitalityState.active);

      // Untouched body parts (peak == 0) render as untested rows post the
      // 2026-05-04 patch — distinct from dormant which is "trained then
      // fully decayed" (peak > 0, ewma == 0).
      final shoulders = state.vitalityRows.firstWhere(
        (r) => r.bodyPart == BodyPart.shoulders,
      );
      expect(shoulders.state, VitalityState.untested);
      expect(shoulders.pct, 0);
    });
  });

  group('assembleStatsState — hybrid X-axis / window selection', () {
    test('day-0 user defaults to 90-day window with no earliest activity', () {
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: const [],
      );
      expect(state.earliestActivity, isNull);
      expect(state.useNarrowWindow, isFalse);
      expect(state.windowSpanDays, 90);
    });

    test('user with 10 days of history → narrow window mode', () {
      final firstActivity = now.subtract(const Duration(days: 10));
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: [
          _event(occurredAt: firstActivity, attribution: const {'chest': 10.0}),
        ],
      );
      expect(state.earliestActivity, firstActivity);
      expect(state.useNarrowWindow, isTrue);
      expect(state.windowSpanDays, 10);
    });

    test(
      'user with exactly 30 days of history → 90-day window (>=30 cutoff)',
      () {
        // Boundary case from WIP amendment: pick `>= 30` and document.
        final firstActivity = now.subtract(const Duration(days: 30));
        final state = assembleStatsState(
          now: now,
          snapshot: RpgProgressSnapshot.empty,
          events: [
            _event(
              occurredAt: firstActivity,
              attribution: const {'chest': 10.0},
            ),
          ],
        );
        expect(state.useNarrowWindow, isFalse);
        expect(state.windowSpanDays, 90);
      },
    );

    test('user with 100 days of history → 90-day window mode', () {
      final firstActivity = now.subtract(const Duration(days: 100));
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: [
          _event(occurredAt: firstActivity, attribution: const {'chest': 10.0}),
        ],
      );
      expect(state.useNarrowWindow, isFalse);
      expect(state.windowSpanDays, 90);
    });
  });

  group('assembleStatsState — trend reconstruction', () {
    test(
      'untrained body parts produce flat-zero series of consistent length',
      () {
        // No events, no peaks → six flat-zero traces, all the same length.
        final state = assembleStatsState(
          now: now,
          snapshot: RpgProgressSnapshot.empty,
          events: const [],
        );

        final lengths = state.trendByBodyPart.values
            .map((s) => s.length)
            .toSet();
        expect(lengths.length, 1, reason: 'all six series same length');

        for (final series in state.trendByBodyPart.values) {
          expect(series, isNotEmpty);
          for (final pt in series) {
            expect(pt.pct, 0);
          }
        }
      },
    );

    test('trend terminal value matches the persisted current EWMA exactly', () {
      // The chart's last point must align with the live Vitality table —
      // otherwise the visual story breaks (line ends at 50% but the row
      // says 60%). We anchor the terminal via a rescale step.
      final firstActivity = now.subtract(const Duration(days: 60));
      final snapshot = RpgProgressSnapshot(
        byBodyPart: {
          BodyPart.chest: _progress(
            bp: BodyPart.chest,
            rank: 5,
            totalXp: 300,
            vitalityEwma: 60,
            vitalityPeak: 100,
          ),
        },
        characterState: CharacterState.empty,
      );
      final state = assembleStatsState(
        now: now,
        snapshot: snapshot,
        // A handful of events spread across the window so the
        // theoretical EWMA terminal is > 0 (rescale path active).
        events: List.generate(
          12,
          (i) => _event(
            occurredAt: firstActivity.add(Duration(days: i * 5)),
            attribution: const {'chest': 100.0},
            setId: 'set-$i',
          ),
        ),
      );

      final chestSeries = state.trendByBodyPart[BodyPart.chest]!;
      expect(chestSeries, isNotEmpty);
      // pct = ewma/peak = 60/100 = 0.6 — the terminal must equal this.
      expect(chestSeries.last.pct, closeTo(0.60, 1e-6));
    });

    test(
      'trained body part with no events in window shows flat trace at current pct',
      () {
        // User trained earlier but is silent in the window → trace is flat
        // at the persisted current EWMA so the chart still communicates a
        // signal (the path is "in maintenance mode", not "broken").
        final snapshot = RpgProgressSnapshot(
          byBodyPart: {
            BodyPart.chest: _progress(
              bp: BodyPart.chest,
              rank: 5,
              totalXp: 300,
              vitalityEwma: 40,
              vitalityPeak: 100,
            ),
          },
          characterState: CharacterState.empty,
        );
        final state = assembleStatsState(
          now: now,
          snapshot: snapshot,
          events: const [], // zero attribution to chest in window
        );

        final chestSeries = state.trendByBodyPart[BodyPart.chest]!;
        expect(chestSeries.length, greaterThan(1));
        for (final pt in chestSeries) {
          expect(
            pt.pct,
            closeTo(0.40, 1e-6),
            reason: 'flat trace at current pct',
          );
        }
      },
    );
  });

  group('assembleStatsState — Volume + Peak per body part', () {
    test('weeklyVolumeSets counts events in last 7 days only', () {
      // 3 sets in last 7 days, 2 sets older than 7 days. Only the 3 count.
      final events = [
        _event(
          occurredAt: now.subtract(const Duration(days: 1)),
          attribution: const {'chest': 10.0},
          setId: 'r-1',
        ),
        _event(
          occurredAt: now.subtract(const Duration(days: 3)),
          attribution: const {'chest': 10.0},
          setId: 'r-2',
        ),
        _event(
          occurredAt: now.subtract(const Duration(days: 5)),
          attribution: const {'chest': 10.0},
          setId: 'r-3',
        ),
        _event(
          occurredAt: now.subtract(const Duration(days: 14)),
          attribution: const {'chest': 10.0},
          setId: 'old-1',
        ),
        _event(
          occurredAt: now.subtract(const Duration(days: 30)),
          attribution: const {'chest': 10.0},
          setId: 'old-2',
        ),
      ];
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: events,
      );
      expect(state.volumePeakByBodyPart[BodyPart.chest]!.weeklyVolumeSets, 3);
      // Other body parts get 0.
      expect(state.volumePeakByBodyPart[BodyPart.back]!.weeklyVolumeSets, 0);
    });

    test('peakEwma reflects the persisted lifetime peak per body part', () {
      final snapshot = RpgProgressSnapshot(
        byBodyPart: {
          BodyPart.chest: _progress(bp: BodyPart.chest, vitalityPeak: 9850),
        },
        characterState: CharacterState.empty,
      );
      final state = assembleStatsState(
        now: now,
        snapshot: snapshot,
        events: const [],
      );
      expect(state.volumePeakByBodyPart[BodyPart.chest]!.peakEwma, 9850);
      expect(state.volumePeakByBodyPart[BodyPart.back]!.peakEwma, 0);
    });

    test(
      'should populate peakLoadKg + peakLoadKg30dAgo from the repo-supplied maps',
      () {
        // Phase 27 L10: assembler now accepts peak-load lookup tables from
        // the repository (one for the current 7-day window, one for the
        // 30-days-ago snapshot window) and threads the per-body-part value
        // into the VolumePeakRow. The assembler does not itself query
        // Supabase — it merges what the provider passed in.
        final state = assembleStatsState(
          now: now,
          snapshot: RpgProgressSnapshot.empty,
          events: const [],
          peakLoadKgByBodyPart: const {
            BodyPart.chest: 92.5,
            BodyPart.legs: 140,
          },
          peakLoadKgByBodyPart30dAgo: const {
            BodyPart.chest: 87.5,
            BodyPart.legs: 130,
          },
        );
        expect(state.volumePeakByBodyPart[BodyPart.chest]!.peakLoadKg, 92.5);
        expect(
          state.volumePeakByBodyPart[BodyPart.chest]!.peakLoadKg30dAgo,
          87.5,
        );
        expect(state.volumePeakByBodyPart[BodyPart.legs]!.peakLoadKg, 140);
        expect(
          state.volumePeakByBodyPart[BodyPart.legs]!.peakLoadKg30dAgo,
          130,
        );
        // Body parts with no peak-load entry default to 0 / null.
        expect(state.volumePeakByBodyPart[BodyPart.back]!.peakLoadKg, 0);
        expect(
          state.volumePeakByBodyPart[BodyPart.back]!.peakLoadKg30dAgo,
          isNull,
        );
      },
    );

    test(
      'should leave peakLoadKg30dAgo null when the user has < 30 days of history (no baseline)',
      () {
        // The provider only computes the 30-days-ago snapshot when there's
        // a window to compare against. With < 30 days of activity, the
        // baseline map should be empty and the row's peakLoadKg30dAgo
        // should be null — the same gate that already governs
        // peakEwma30dAgo.
        final state = assembleStatsState(
          now: now,
          snapshot: RpgProgressSnapshot.empty,
          events: [
            _event(
              occurredAt: now.subtract(const Duration(days: 5)),
              attribution: const {'chest': 10.0},
            ),
          ],
          peakLoadKgByBodyPart: const {BodyPart.chest: 60.0},
          // Empty 30-days-ago map — provider decided not to fetch it.
          peakLoadKgByBodyPart30dAgo: const {},
        );
        expect(state.volumePeakByBodyPart[BodyPart.chest]!.peakLoadKg, 60.0);
        expect(
          state.volumePeakByBodyPart[BodyPart.chest]!.peakLoadKg30dAgo,
          isNull,
        );
      },
    );
  });

  group('assembleStatsState — VolumePeakRow extended delta fields', () {
    test(
      'should populate previousWeekVolumeSets / fourWeekMean / peakEwma30dAgo / weeksOfHistory for 8-week history',
      () {
        // Anchor: April 30, 2026 (a Thursday). Current ISO-week starts Mon Apr 27.
        // Build 8 distinct weeks of chest events. Spec says fourWeekMean uses
        // the 4 weeks BEFORE the current in-progress week, i.e. weeks -4..-1.
        //   week -7 (Mon Mar 9):    12 events
        //   week -6 (Mon Mar 16):   14 events
        //   week -5 (Mon Mar 23):   16 events
        //   week -4 (Mon Mar 30):   14 events   ← in 4-week-mean window
        //   week -3 (Mon Apr 6):    12 events   ← in 4-week-mean window
        //   week -2 (Mon Apr 13):   14 events   ← in 4-week-mean window
        //   week -1 (Mon Apr 20):   16 events   ← previousWeekVolumeSets
        //   week 0  (Mon Apr 27):    8 events   ← current week
        //
        // Expected: weeklyVolumeSets=8, previousWeek=16,
        //   fourWeekMean=(14+12+14+16)/4 = 14.0, weeksOfHistory=8.
        final events = [
          for (final entry in {
            DateTime.utc(2026, 3, 9): 12,
            DateTime.utc(2026, 3, 16): 14,
            DateTime.utc(2026, 3, 23): 16,
            DateTime.utc(2026, 3, 30): 14,
            DateTime.utc(2026, 4, 6): 12,
            DateTime.utc(2026, 4, 13): 14,
            DateTime.utc(2026, 4, 20): 16,
            DateTime.utc(2026, 4, 27): 8,
          }.entries)
            for (var i = 0; i < entry.value; i++)
              _event(
                occurredAt: entry.key.add(Duration(hours: i)),
                attribution: const {'chest': 1.0},
                setId: 'set-${entry.key.toIso8601String()}-$i',
              ),
        ];
        final snapshot = RpgProgressSnapshot(
          byBodyPart: {
            BodyPart.chest: _progress(
              bp: BodyPart.chest,
              rank: 5,
              totalXp: 1000,
              vitalityEwma: 80.0,
              vitalityPeak: 100.0,
            ),
          },
          characterState: CharacterState.empty,
        );
        final state = assembleStatsState(
          now: now,
          snapshot: snapshot,
          events: events,
        );
        final chestRow = state.volumePeakByBodyPart[BodyPart.chest]!;
        expect(chestRow.weeklyVolumeSets, 8);
        expect(chestRow.previousWeekVolumeSets, 16);
        expect(chestRow.fourWeekMeanVolumeSets, closeTo(14.0, 0.01));
        expect(chestRow.weeksOfHistory, 8);
        expect(chestRow.peakEwma30dAgo, isNotNull);
        // Lower-bound sanity check: with vitalityPeak=100 and earliest well
        // past the 30-day window, the closest-date sample × peak must be > 0.
        // The exact value depends on the trend reconstruction's
        // interpolation, but non-zero is the guarantee the assertion existing
        // was meant to pin.
        expect(chestRow.peakEwma30dAgo, greaterThan(0));
      },
    );

    test(
      'should leave previousWeek / fourWeekMean / peakEwma30dAgo null for 1-week history',
      () {
        // Single-week history for back: just this week's events.
        final events = [
          for (var i = 0; i < 5; i++)
            _event(
              occurredAt: DateTime.utc(2026, 4, 27).add(Duration(hours: i)),
              attribution: const {'back': 1.0},
              setId: 'back-set-$i',
            ),
        ];
        final snapshot = RpgProgressSnapshot(
          byBodyPart: {
            BodyPart.back: _progress(
              bp: BodyPart.back,
              rank: 2,
              totalXp: 100,
              vitalityEwma: 30.0,
              vitalityPeak: 40.0,
            ),
          },
          characterState: CharacterState.empty,
        );
        final state = assembleStatsState(
          now: now,
          snapshot: snapshot,
          events: events,
        );
        final backRow = state.volumePeakByBodyPart[BodyPart.back]!;
        expect(backRow.weeksOfHistory, 1);
        expect(backRow.previousWeekVolumeSets, isNull);
        expect(backRow.fourWeekMeanVolumeSets, isNull);
        expect(backRow.peakEwma30dAgo, isNull, reason: 'history < 30 days');
      },
    );

    test(
      'should return all-null delta fields for body part with zero history',
      () {
        // No events at all. All body parts untrained, peak == 0.
        final state = assembleStatsState(
          now: now,
          snapshot: RpgProgressSnapshot.empty,
          events: const [],
        );
        final legsRow = state.volumePeakByBodyPart[BodyPart.legs]!;
        expect(legsRow.weeksOfHistory, 0);
        expect(legsRow.previousWeekVolumeSets, isNull);
        expect(legsRow.fourWeekMeanVolumeSets, isNull);
        expect(legsRow.peakEwma30dAgo, isNull);
        expect(legsRow.weeklyVolumeSets, 0);
        expect(legsRow.peakEwma, 0);
      },
    );

    test(
      'should fill 4-week-mean using weeks immediately before the current week (off-by-one guard)',
      () {
        // Off-by-one regression guard. Exactly 5 weeks of chest activity:
        //   weeks -4, -3, -2, -1 (each 10 sets) + week 0 (5 sets).
        // weeksOfHistory = 5 → fourWeekMean = (10+10+10+10)/4 = 10.0.
        // If the impl uses weeks -5..-1 or -3..0, the mean diverges. This
        // pins the documented "4 weeks BEFORE current" semantic.
        final events = [
          for (final wkStart in [
            DateTime.utc(2026, 3, 30), // -4
            DateTime.utc(2026, 4, 6), // -3
            DateTime.utc(2026, 4, 13), // -2
            DateTime.utc(2026, 4, 20), // -1
          ])
            for (var i = 0; i < 10; i++)
              _event(
                occurredAt: wkStart.add(Duration(hours: i)),
                attribution: const {'chest': 1.0},
                setId: 'set-${wkStart.toIso8601String()}-$i',
              ),
          for (var i = 0; i < 5; i++)
            _event(
              occurredAt: DateTime.utc(2026, 4, 27).add(Duration(hours: i)),
              attribution: const {'chest': 1.0},
              setId: 'curr-$i',
            ),
        ];
        final snapshot = RpgProgressSnapshot(
          byBodyPart: {
            BodyPart.chest: _progress(
              bp: BodyPart.chest,
              rank: 3,
              totalXp: 500,
              vitalityEwma: 50,
              vitalityPeak: 60,
            ),
          },
          characterState: CharacterState.empty,
        );
        final state = assembleStatsState(
          now: now,
          snapshot: snapshot,
          events: events,
        );
        final chestRow = state.volumePeakByBodyPart[BodyPart.chest]!;
        expect(chestRow.weeksOfHistory, 5);
        expect(chestRow.previousWeekVolumeSets, 10);
        expect(chestRow.fourWeekMeanVolumeSets, closeTo(10.0, 0.01));
      },
    );
  });

  group('StatsDeepDiveState.empty', () {
    test('produces a renderable laid-out state with no nulls', () {
      final empty = StatsDeepDiveState.empty();
      // Phase 38e: cardio joined activeBodyParts → 7 rows/lines across the
      // stats deep-dive empty state.
      expect(empty.vitalityRows.length, 7);
      expect(empty.trendByBodyPart.length, 7);
      expect(empty.volumePeakByBodyPart.length, 7);
      expect(empty.earliestActivity, isNull);
    });
  });
}
