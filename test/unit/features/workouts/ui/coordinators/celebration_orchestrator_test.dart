import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/workouts/ui/coordinators/celebration_orchestrator.dart';

/// A real [RankUpPulseLocalStorage] that injects a write failure for one
/// designated body part — simulating a Hive disk-full / corrupted-box error
/// on a single key while letting every other write land in the real box.
///
/// This lets the failure-isolation test assert the OBSERVABLE outcome: the
/// surviving writes are actually readable via `isPulsing`, not merely that
/// "the mock method was called".
class _FailOnBodyPartStorage extends RankUpPulseLocalStorage {
  _FailOnBodyPartStorage({required this.failOn});

  final BodyPart failOn;

  @override
  Future<void> recordRankUp(BodyPart bodyPart, {DateTime? at}) async {
    if (bodyPart == failOn) {
      throw Exception('simulated hive write failure for ${bodyPart.dbValue}');
    }
    return super.recordRankUp(bodyPart, at: at);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    // Real Hive box on a temp dir (same pattern as
    // rank_up_pulse_local_storage_test.dart). Pure unit tests can't call
    // Hive.initFlutter() — that needs path_provider, which has no host-VM
    // implementation. Cluster: hive-testwidgets (init must precede openBox).
    tempDir = await Directory.systemTemp.createTemp('celebration_orch_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(RankUpPulseLocalStorage.boxName);
    await Hive.box<dynamic>(RankUpPulseLocalStorage.boxName).clear();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('CelebrationOrchestrator.recordRankUpPulses', () {
    // The behavioral contract under test: after recordRankUpPulses runs, the
    // pulse the UI (BodyPartRankRow) reads via isPulsing() is actually
    // present for each ranked-up body part. We assert the surfaced state, not
    // the storage call.
    test(
      'records a readable pulse for every RankUpEvent in the queue',
      () async {
        final storage = RankUpPulseLocalStorage();
        final now = DateTime(2026, 6, 15, 10, 0);

        await CelebrationOrchestrator.recordRankUpPulses(
          queue: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
            CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 3),
            CelebrationEvent.levelUp(newLevel: 12),
          ],
          pulseStorage: storage,
        );

        // The pulses the UI will read are present for both ranked-up parts.
        expect(storage.isPulsing(BodyPart.chest, now: now), isTrue);
        expect(storage.isPulsing(BodyPart.back, now: now), isTrue);
        // The level-up event ranked up nothing, so its incidental body parts
        // do not pulse.
        expect(storage.isPulsing(BodyPart.legs, now: now), isFalse);
      },
    );

    test('records no pulses when the queue has no RankUpEvents', () async {
      final storage = RankUpPulseLocalStorage();
      final now = DateTime(2026, 6, 15, 10, 0);

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

      // No body part surfaces a pulse — nothing in the queue ranked up.
      for (final bodyPart in BodyPart.values) {
        expect(
          storage.isPulsing(bodyPart, now: now),
          isFalse,
          reason: '${bodyPart.dbValue} must not pulse without a RankUpEvent',
        );
      }
    });

    test(
      'overflow rank-ups are NOT pulsed (helper only sees queue, not overflow)',
      () async {
        // Documented limitation: OverflowPayload carries only a count, not
        // body parts. By tightening the signature to take just `queue`, this
        // is structurally enforced — the helper can't see the overflow even
        // if it wanted to. We pin the behavior: a queue with one RankUpEvent
        // surfaces exactly that one body part's pulse, no more.
        final storage = RankUpPulseLocalStorage();
        final now = DateTime(2026, 6, 15, 10, 0);

        await CelebrationOrchestrator.recordRankUpPulses(
          queue: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
          ],
          pulseStorage: storage,
        );

        expect(storage.isPulsing(BodyPart.chest, now: now), isTrue);
        // Every other body part — including any that a hypothetical overflow
        // might have carried — stays unpulsed.
        for (final bodyPart in BodyPart.values) {
          if (bodyPart == BodyPart.chest) continue;
          expect(storage.isPulsing(bodyPart, now: now), isFalse);
        }
      },
    );

    test(
      'a failing recordRankUp does not abort the remaining writes',
      () async {
        // Critical contract: per-iteration try/catch ensures one bad write
        // (Hive disk-full / corrupted box) doesn't skip the remaining body
        // parts. We inject a real write failure on chest and assert the
        // OBSERVABLE survivor: back's pulse is actually readable afterward.
        final storage = _FailOnBodyPartStorage(failOn: BodyPart.chest);
        final now = DateTime(2026, 6, 15, 10, 0);

        // Must not throw — the helper swallows the per-write exception per the
        // fire-and-forget contract.
        await CelebrationOrchestrator.recordRankUpPulses(
          queue: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 4),
            CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 3),
          ],
          pulseStorage: storage,
        );

        // Chest's write failed — no pulse surfaces for it.
        expect(storage.isPulsing(BodyPart.chest, now: now), isFalse);
        // Back came AFTER chest in the queue: the failure did not abort the
        // loop, so back's pulse is present and readable by the UI.
        expect(storage.isPulsing(BodyPart.back, now: now), isTrue);
      },
    );
  });
}
