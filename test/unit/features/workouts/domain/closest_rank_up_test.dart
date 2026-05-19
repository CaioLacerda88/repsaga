/// Unit tests for [closestRankUp].
///
/// The helper picks the [BodyPartSheetEntry] with the smallest absolute XP
/// gap to its next rank, used by the Home character-card collapsed-state
/// indicator. Locked semantics:
///   - Untrained entries (`isUntrained == true`) are excluded — they have no
///     meaningful "next rank" target yet.
///   - Max-rank entries (`xpForNextRank == 0`) are excluded — no next rank
///     exists, so the gap is undefined.
///   - Returns null when no eligible entry exists (day-0 user, or every
///     active part is at max rank).
///   - Ties broken by canonical [BodyPart] enum order so the result is
///     deterministic across rebuilds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/workouts/domain/closest_rank_up.dart';

BodyPartSheetEntry _trainedEntry(
  BodyPart bodyPart, {
  required int rank,
  required double xpInRank,
  required double xpForNextRank,
}) {
  return BodyPartSheetEntry(
    bodyPart: bodyPart,
    rank: rank,
    vitalityEwma: 100, // any non-zero value avoids untrained
    vitalityPeak: 200, // any non-zero value avoids untrained
    vitalityState: VitalityState.active,
    xpInRank: xpInRank,
    xpForNextRank: xpForNextRank,
    totalXp: 1000, // any positive value avoids untrained
  );
}

BodyPartSheetEntry _untrainedEntry(BodyPart bodyPart) {
  return BodyPartSheetEntry(
    bodyPart: bodyPart,
    rank: 1,
    vitalityEwma: 0,
    vitalityPeak: 0,
    vitalityState: VitalityState.untested,
    xpInRank: 0,
    xpForNextRank: 100,
    totalXp: 0,
  );
}

void main() {
  group('closestRankUp', () {
    test('returns null when entries is empty', () {
      expect(closestRankUp(const []), isNull);
    });

    test('returns null when every entry is untrained', () {
      final entries = [for (final bp in activeBodyParts) _untrainedEntry(bp)];
      expect(closestRankUp(entries), isNull);
    });

    test('returns the only trained entry when one body part has progress', () {
      final entries = <BodyPartSheetEntry>[
        _trainedEntry(
          BodyPart.chest,
          rank: 2,
          xpInRank: 40,
          xpForNextRank: 100,
        ),
        _untrainedEntry(BodyPart.back),
        _untrainedEntry(BodyPart.legs),
        _untrainedEntry(BodyPart.shoulders),
        _untrainedEntry(BodyPart.arms),
        _untrainedEntry(BodyPart.core),
      ];
      final result = closestRankUp(entries);
      expect(result, isNotNull);
      expect(result!.bodyPart, BodyPart.chest);
    });

    test('returns the smallest-gap entry across multiple trained parts', () {
      // chest gap = 100 - 10 = 90
      // back  gap = 100 - 80 = 20
      // legs  gap = 100 - 40 = 60
      final entries = <BodyPartSheetEntry>[
        _trainedEntry(
          BodyPart.chest,
          rank: 2,
          xpInRank: 10,
          xpForNextRank: 100,
        ),
        _trainedEntry(BodyPart.back, rank: 2, xpInRank: 80, xpForNextRank: 100),
        _trainedEntry(BodyPart.legs, rank: 2, xpInRank: 40, xpForNextRank: 100),
      ];
      final result = closestRankUp(entries);
      expect(result, isNotNull);
      expect(result!.bodyPart, BodyPart.back);
    });

    test('ties broken by canonical BodyPart order', () {
      // Three entries with identical gap = 80. Iteration order in the input
      // list deliberately differs from enum order to prove the function
      // doesn't accidentally rely on input order.
      final entries = <BodyPartSheetEntry>[
        _trainedEntry(BodyPart.legs, rank: 2, xpInRank: 20, xpForNextRank: 100),
        _trainedEntry(
          BodyPart.chest,
          rank: 2,
          xpInRank: 20,
          xpForNextRank: 100,
        ),
        _trainedEntry(BodyPart.back, rank: 2, xpInRank: 20, xpForNextRank: 100),
      ];
      final result = closestRankUp(entries);
      expect(result, isNotNull);
      // BodyPart.values order = [chest, back, legs, shoulders, arms, core,
      // cardio]. Chest comes first among the three tied parts.
      expect(result!.bodyPart, BodyPart.chest);
    });

    test('excludes max-rank entries (xpForNextRank == 0)', () {
      final entries = <BodyPartSheetEntry>[
        // Chest sits at the rank ceiling — no next rank to reach.
        _trainedEntry(BodyPart.chest, rank: 10, xpInRank: 0, xpForNextRank: 0),
        // Back has a real gap of 30 — it should win.
        _trainedEntry(BodyPart.back, rank: 3, xpInRank: 70, xpForNextRank: 100),
      ];
      final result = closestRankUp(entries);
      expect(result, isNotNull);
      expect(result!.bodyPart, BodyPart.back);
    });

    test('returns null when every trained entry is max-rank', () {
      final entries = <BodyPartSheetEntry>[
        _trainedEntry(BodyPart.chest, rank: 10, xpInRank: 0, xpForNextRank: 0),
        _trainedEntry(BodyPart.back, rank: 10, xpInRank: 0, xpForNextRank: 0),
      ];
      expect(closestRankUp(entries), isNull);
    });
  });
}
