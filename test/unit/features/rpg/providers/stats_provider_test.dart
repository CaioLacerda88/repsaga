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
import 'package:repsaga/features/exercises/models/exercise.dart' as ex;
import 'package:repsaga/features/rpg/data/rpg_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/peak_load.dart';
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

PeakLoad _peak({
  required String exerciseId,
  required double weight,
  int reps = 5,
  DateTime? on,
}) {
  return PeakLoad(
    userId: 'u1',
    exerciseId: exerciseId,
    peakWeight: weight,
    peakReps: reps,
    peakDate: on ?? DateTime.utc(2026, 4, 15),
    updatedAt: on ?? DateTime.utc(2026, 4, 15),
  );
}

ex.Exercise _exercise({
  required String id,
  required String name,
  required ex.MuscleGroup mg,
}) {
  return ex.Exercise(
    id: id,
    name: name,
    muscleGroup: mg,
    equipmentType: ex.EquipmentType.barbell,
    isDefault: true,
    createdAt: DateTime.utc(2026, 1, 1),
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
        peaks: const [],
        exercisesById: const {},
      );

      expect(state.vitalityRows.length, 6);
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
        peaks: const [],
        exercisesById: const {},
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
        peaks: const [],
        exercisesById: const {},
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
        peaks: const [],
        exercisesById: const {},
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
          peaks: const [],
          exercisesById: const {},
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
        peaks: const [],
        exercisesById: const {},
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
          peaks: const [],
          exercisesById: const {},
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
        peaks: const [],
        exercisesById: const {},
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
          peaks: const [],
          exercisesById: const {},
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
        peaks: const [],
        exercisesById: const {},
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
        peaks: const [],
        exercisesById: const {},
      );
      expect(state.volumePeakByBodyPart[BodyPart.chest]!.peakEwma, 9850);
      expect(state.volumePeakByBodyPart[BodyPart.back]!.peakEwma, 0);
    });
  });

  group('assembleStatsState — peak loads grouping', () {
    test('groups peaks by exercise muscle group, sorted by weight desc', () {
      final peaks = [
        _peak(exerciseId: 'bench', weight: 100, reps: 5),
        _peak(exerciseId: 'incline', weight: 80, reps: 8),
        _peak(exerciseId: 'squat', weight: 140, reps: 3),
      ];
      final exercises = {
        'bench': _exercise(
          id: 'bench',
          name: 'Bench Press',
          mg: ex.MuscleGroup.chest,
        ),
        'incline': _exercise(
          id: 'incline',
          name: 'Incline DB Press',
          mg: ex.MuscleGroup.chest,
        ),
        'squat': _exercise(
          id: 'squat',
          name: 'Back Squat',
          mg: ex.MuscleGroup.legs,
        ),
      };
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: const [],
        peaks: peaks,
        exercisesById: exercises,
      );

      // Two muscle groups present.
      expect(state.peakLoadsByBodyPart.keys.toSet(), {
        BodyPart.chest,
        BodyPart.legs,
      });

      // Chest sorted by weight desc.
      final chestPeaks = state.peakLoadsByBodyPart[BodyPart.chest]!;
      expect(chestPeaks.map((r) => r.exerciseName).toList(), [
        'Bench Press',
        'Incline DB Press',
      ]);
      expect(chestPeaks[0].peakWeight, 100);
      expect(chestPeaks[1].peakWeight, 80);

      // Legs has the squat.
      final legPeaks = state.peakLoadsByBodyPart[BodyPart.legs]!;
      expect(legPeaks.length, 1);
      expect(legPeaks[0].peakWeight, 140);
    });

    test('estimated1RM uses Epley formula and is null for zero-rep peaks', () {
      // 100kg × 5 → Epley = 100 × (1 + 5/30) ≈ 116.67
      // 100kg × 1 → exactly the lift weight
      // 100kg × 0 → null (bodyweight / non-loaded)
      final peaks = [
        _peak(exerciseId: 'a', weight: 100, reps: 5),
        _peak(exerciseId: 'b', weight: 100, reps: 1),
        _peak(exerciseId: 'c', weight: 100, reps: 0),
      ];
      final exercises = {
        'a': _exercise(id: 'a', name: 'A', mg: ex.MuscleGroup.chest),
        'b': _exercise(id: 'b', name: 'B', mg: ex.MuscleGroup.chest),
        'c': _exercise(id: 'c', name: 'C', mg: ex.MuscleGroup.chest),
      };
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: const [],
        peaks: peaks,
        exercisesById: exercises,
      );

      final byName = {
        for (final r in state.peakLoadsByBodyPart[BodyPart.chest]!)
          r.exerciseName: r,
      };
      expect(byName['A']!.estimated1RM, closeTo(100 * (1 + 5 / 30), 1e-6));
      expect(byName['B']!.estimated1RM, 100);
      expect(byName['C']!.estimated1RM, isNull);
    });

    test('peaks for unknown exercises silently dropped', () {
      // Defensive: a deleted/foreign exercise won't be in the map. The row
      // is dropped rather than rendered as "Unknown".
      final peaks = [_peak(exerciseId: 'ghost', weight: 50)];
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: const [],
        peaks: peaks,
        exercisesById: const {},
      );
      expect(state.peakLoadsByBodyPart, isEmpty);
    });

    test('empty peaks → empty map (drives empty-state UI)', () {
      final state = assembleStatsState(
        now: now,
        snapshot: RpgProgressSnapshot.empty,
        events: const [],
        peaks: const [],
        exercisesById: const {},
      );
      expect(state.peakLoadsByBodyPart, isEmpty);
    });

    test(
      'peaks for cardio exercises are excluded from peak loads (v1 cardio gate)',
      () {
        // v1 (Phase 18d) does not route cardio peaks through the deep-dive.
        // The mapping `_muscleGroupToBodyPart(cardio)` returns null at the
        // source so cardio rows are dropped before they enter the map —
        // not silently allocated to `BodyPart.cardio` and then dropped
        // downstream by [PeakLoadsTable]'s `activeBodyParts.where(...)`
        // filter (which would silently regress when Phase 19 adds cardio
        // attribution). Mixing in a chest peak proves the bench (other
        // groups still flow).
        final peaks = [
          _peak(exerciseId: 'run', weight: 0, reps: 0),
          _peak(exerciseId: 'bench', weight: 100, reps: 5),
        ];
        final exercises = {
          'run': _exercise(
            id: 'run',
            name: 'Treadmill Run',
            mg: ex.MuscleGroup.cardio,
          ),
          'bench': _exercise(
            id: 'bench',
            name: 'Bench Press',
            mg: ex.MuscleGroup.chest,
          ),
        };
        final state = assembleStatsState(
          now: now,
          snapshot: RpgProgressSnapshot.empty,
          events: const [],
          peaks: peaks,
          exercisesById: exercises,
        );

        // Only chest is in the map — cardio is gated off at `_muscleGroupToBodyPart`.
        expect(state.peakLoadsByBodyPart.keys.toSet(), {BodyPart.chest});
        expect(state.peakLoadsByBodyPart.containsKey(BodyPart.cardio), isFalse);
      },
    );
  });

  group('StatsDeepDiveState.empty', () {
    test('produces a renderable laid-out state with no nulls', () {
      final empty = StatsDeepDiveState.empty();
      expect(empty.vitalityRows.length, 6);
      expect(empty.trendByBodyPart.length, 6);
      expect(empty.volumePeakByBodyPart.length, 6);
      expect(empty.peakLoadsByBodyPart, isEmpty);
      expect(empty.earliestActivity, isNull);
    });
  });
}
