import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
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

      const result = CelebrationQueueResult(
        queue: [
          CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
          CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 3),
          CelebrationEvent.levelUp(newLevel: 12),
        ],
        overflow: null,
      );

      await CelebrationOrchestrator.recordRankUpPulses(
        result: result,
        pulseStorage: storage,
      );

      verify(() => storage.recordRankUp(BodyPart.chest)).called(1);
      verify(() => storage.recordRankUp(BodyPart.back)).called(1);
      verifyNoMoreInteractions(storage);
    });

    test('writes nothing when the queue has no RankUpEvents', () async {
      final storage = _MockPulseStorage();

      const result = CelebrationQueueResult(
        queue: [
          CelebrationEvent.levelUp(newLevel: 12),
          CelebrationEvent.classChange(
            fromClass: CharacterClass.initiate,
            toClass: CharacterClass.bulwark,
          ),
        ],
        overflow: null,
      );

      await CelebrationOrchestrator.recordRankUpPulses(
        result: result,
        pulseStorage: storage,
      );

      verifyZeroInteractions(storage);
    });

    test('overflow rank-ups are NOT pulsed (no body part available)', () async {
      // OverflowPayload only carries a count — body parts aren't preserved.
      // Documented limitation: body parts that didn't fit in the queue cap
      // won't pulse. This test pins the known behavior so a future change
      // either preserves it OR adds body-part preservation to OverflowPayload
      // and updates this test deliberately.
      final storage = _MockPulseStorage();
      when(() => storage.recordRankUp(any())).thenAnswer((_) async {});

      const result = CelebrationQueueResult(
        queue: [CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4)],
        overflow: OverflowPayload(remainingRankUps: 4),
      );

      await CelebrationOrchestrator.recordRankUpPulses(
        result: result,
        pulseStorage: storage,
      );

      // Only chest (the one in the queue) was pulsed. The 4 overflow rank-ups
      // do NOT pulse — their body parts aren't recoverable from the overflow
      // payload.
      verify(() => storage.recordRankUp(BodyPart.chest)).called(1);
      verifyNoMoreInteractions(storage);
    });
  });
}
