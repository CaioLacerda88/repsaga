import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/workouts/ui/coordinators/celebration_orchestrator.dart';

class _MockPulseStorage extends Mock implements RankUpPulseLocalStorage {}

void main() {
  setUpAll(() {
    registerFallbackValue(BodyPart.chest);
  });

  group('CelebrationOrchestrator.recordRankUpPulses', () {
    test('writes one pulse per RankUpEvent in the queue', () async {
      final storage = _MockPulseStorage();
      when(() => storage.recordRankUp(any())).thenAnswer((_) async {});

      await CelebrationOrchestrator.recordRankUpPulses(
        queue: const [
          CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
          CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 3),
          CelebrationEvent.levelUp(newLevel: 12),
        ],
        pulseStorage: storage,
      );

      verify(() => storage.recordRankUp(BodyPart.chest)).called(1);
      verify(() => storage.recordRankUp(BodyPart.back)).called(1);
      verifyNoMoreInteractions(storage);
    });

    test('writes nothing when the queue has no RankUpEvents', () async {
      final storage = _MockPulseStorage();

      await CelebrationOrchestrator.recordRankUpPulses(
        queue: const [
          CelebrationEvent.levelUp(newLevel: 12),
          CelebrationEvent.classChange(
            fromClass: CharacterClass.initiate,
            toClass: CharacterClass.bulwark,
          ),
        ],
        pulseStorage: storage,
      );

      verifyZeroInteractions(storage);
    });

    test(
      'overflow rank-ups are NOT pulsed (helper only sees queue, not overflow)',
      () async {
        // Documented limitation: OverflowPayload carries only a count, not
        // body parts. By tightening the signature to take just `queue`, this
        // is now structurally enforced — the helper can't see the overflow
        // even if it wanted to. Test pins the behavior: passing a queue with
        // 1 RankUpEvent yields exactly 1 pulse write, regardless of what the
        // hypothetical overflow looked like.
        final storage = _MockPulseStorage();
        // Generic stub so the chest call below resolves; overflow body parts
        // never reach the storage (helper iterates only the queue list).
        when(() => storage.recordRankUp(any())).thenAnswer((_) async {});

        await CelebrationOrchestrator.recordRankUpPulses(
          queue: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
          ],
          pulseStorage: storage,
        );

        verify(() => storage.recordRankUp(BodyPart.chest)).called(1);
        verifyNoMoreInteractions(storage);
      },
    );

    test(
      'a failing recordRankUp does not abort the remaining writes',
      () async {
        // Critical contract: per-iteration try/catch ensures one bad write
        // (Hive disk-full / corrupted box) doesn't skip the remaining body
        // parts. The plan called this fire-and-forget; this test pins the
        // behavior so a future refactor can't silently re-introduce the
        // post-workout-flow abort hazard.
        final storage = _MockPulseStorage();
        when(
          () => storage.recordRankUp(BodyPart.chest),
        ).thenThrow(Exception('simulated hive write failure'));
        when(
          () => storage.recordRankUp(BodyPart.back),
        ).thenAnswer((_) async {});

        // Must not throw — the helper swallows the exception per the
        // fire-and-forget contract.
        await CelebrationOrchestrator.recordRankUpPulses(
          queue: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
            CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 3),
          ],
          pulseStorage: storage,
        );

        // Both writes were attempted — the failure on chest did not skip back.
        verify(() => storage.recordRankUp(BodyPart.chest)).called(1);
        verify(() => storage.recordRankUp(BodyPart.back)).called(1);
      },
    );
  });
}
