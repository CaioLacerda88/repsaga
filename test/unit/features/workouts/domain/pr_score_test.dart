import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/workouts/domain/pr_score.dart';

/// Pins the shared `prScore` contract used by both
/// `PostSessionChoreographer._buildPrCut` and
/// `SharePayload.fromPostSessionState`. Behavior, not wiring — assert the
/// numerical outputs rather than tracing call sites.
void main() {
  PersonalRecord pr({
    required String exerciseId,
    required double value,
    int? reps,
    RecordType type = RecordType.maxWeight,
  }) {
    return PersonalRecord(
      id: 'pr-$exerciseId',
      userId: 'user-001',
      exerciseId: exerciseId,
      recordType: type,
      value: value,
      achievedAt: DateTime.utc(2026, 5, 24),
      setId: 'set-$exerciseId',
      reps: reps,
    );
  }

  group('prScore', () {
    test('weighted PR scores weight × reps', () {
      expect(prScore(pr(exerciseId: 'bench', value: 95, reps: 5)), 475.0);
      expect(prScore(pr(exerciseId: 'squat', value: 120, reps: 3)), 360.0);
    });

    test('bodyweight PR (null reps) scores 0', () {
      // Bodyweight maxReps PRs carry reps in a different field (the value),
      // but a PR with reps == null must score 0 so it never beats a weighted
      // PR for the hero-PR slot. This is the canonical regression — pre-fix
      // `share_payload.dart` defaulted null to 1 and let bodyweight PRs win.
      expect(
        prScore(
          pr(
            exerciseId: 'pullup',
            value: 0,
            reps: null,
            type: RecordType.maxReps,
          ),
        ),
        0.0,
      );
      // Even a non-zero weight with null reps scores 0 — null reps means
      // the PR isn't a `weight × reps` hero candidate.
      expect(
        prScore(pr(exerciseId: 'odd', value: 80, reps: null)),
        0.0,
      );
    });

    test('reps == 0 scores 0 (weighted PR with zero reps is dominated)', () {
      expect(prScore(pr(exerciseId: 'bench', value: 100, reps: 0)), 0.0);
    });

    test('weighted PR always dominates null-reps PR in mixed sessions', () {
      // The canonical mixed-session case: one weighted PR + one bodyweight
      // PR. The weighted PR must win even when the bodyweight PR's `value`
      // is large (e.g. a 100kg bodyweight athlete doing a max-reps PR).
      final weighted = pr(exerciseId: 'bench', value: 60, reps: 5); // 300
      final bodyweight = pr(
        exerciseId: 'pullup',
        value: 100,
        reps: null,
        type: RecordType.maxReps,
      ); // 0
      expect(prScore(weighted) > prScore(bodyweight), isTrue);
    });

    test('tie-break consistency: choreographer + share payload sort by '
        'identical scores', () {
      // Mirror a multi-PR session where two PRs tie at score 300.
      // Both call sites (choreographer + share payload) MUST agree on the
      // score for any subsequent name-alphabetical tiebreaker to be
      // deterministic across surfaces. This test pins the score equality;
      // the name tiebreaker itself is tested separately in
      // `share_payload_test.dart` + `post_session_choreographer_test.dart`.
      final a = pr(exerciseId: 'squat', value: 100, reps: 3); // 300
      final b = pr(exerciseId: 'deadlift', value: 60, reps: 5); // 300
      expect(prScore(a), prScore(b));
      expect(prScore(a), 300.0);
    });
  });
}
