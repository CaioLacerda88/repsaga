/// Unit tests for the per-variant slot policy attached to [CelebrationEvent].
///
/// The policy enum names what the queue already does today and is what the
/// post-session screen (PR 30a) will read against when dispatching events
/// across cut beats. Pinning each assignment as a behavior-not-wiring test
/// ensures a future variant added to the union has to make an explicit
/// policy choice (compile error from the exhaustive switch) rather than
/// silently inheriting a default.
///
///   * `serialize` — the event holds its own slot; if multiple slots are
///     available the variant fills them in order. First-awakening,
///     class-change, rank-up, title-unlock, personal-record all serialize.
///   * `coalesce` — the event collapses into a summary surface when the
///     visible cap is exceeded. Rank-up additionally has this fallback
///     for spillover-beyond-cap (rendered via the overflow card flipbook).
///   * `drop` — silently absorbed when no slot is available; not surfaced
///     to the user during this finish. Level-up uses this because the
///     character level is re-derivable on the saga screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';

void main() {
  group('slotPolicyFor — per-variant assignment', () {
    test('first-awakening events serialize (bypass cap, head of queue)', () {
      // First-awakening is the onboarding moment — narratively precedes
      // rank-up. Throttled to one per session upstream, so it always has
      // a slot. Pinning the policy means a future refactor cannot
      // silently demote awakening to drop/coalesce.
      const event = CelebrationEvent.firstAwakening(bodyPart: BodyPart.chest);
      expect(slotPolicyFor(event), SlotPolicy.serialize);
    });

    test('class-change events serialize (slot 1 reservation)', () {
      // Class change is the rarest progression beat in the entire loop —
      // typically once per ~3 months for an active lifter. Always
      // surfaced; never dropped.
      const event = CelebrationEvent.classChange(
        fromClass: CharacterClass.initiate,
        toClass: CharacterClass.bulwark,
      );
      expect(slotPolicyFor(event), SlotPolicy.serialize);
    });

    test(
      'rank-up events serialize (top rank-up reserved; overflow coalesces)',
      () {
        // Rank-up always reserves slot 2 (top rank-up), and additional
        // rank-ups serialize into the spillover area. Beyond cap-at-3, the
        // overflow card flipbook coalesces the remainder — but the per-event
        // policy is still serialize; coalesce is the queue's overflow
        // strategy, not a per-event policy on rank-up itself.
        const event = CelebrationEvent.rankUp(
          bodyPart: BodyPart.chest,
          newRank: 5,
        );
        expect(slotPolicyFor(event), SlotPolicy.serialize);
      },
    );

    test('title-unlock events serialize (third closer slot)', () {
      // BUG-017 invariant — title is the crown. When both title and
      // level-up vie for the last closer slot, title wins.
      const event = CelebrationEvent.titleUnlock(slug: 'chest_r5_initiate');
      expect(slotPolicyFor(event), SlotPolicy.serialize);
    });

    test('personal-record events serialize (mid-workout flash placement)', () {
      // The thin-flash personal-record variant (mockup §4½ variant 5)
      // fires mid-workout the moment the set's XP write detects a PR.
      // Slot policy serialize lets it queue alongside rank-ups during the
      // post-finish playback path that 30b will wire.
      const event = CelebrationEvent.personalRecord(
        exerciseId: 'abc-123',
        exerciseName: 'Bench Press',
        weight: 100,
        reps: 5,
        repBand: '1-5',
        priorBest: 95,
      );
      expect(slotPolicyFor(event), SlotPolicy.serialize);
    });

    test('level-up events drop (silently absorbed when cap is full)', () {
      // Character level is a pure function of body-part ranks — always
      // re-derivable on the saga screen. Dropping it costs less
      // narrative continuity than dropping a rank-up, title, class
      // change, or PR. BUG-013 + BUG-017 lock this in queue tests; the
      // policy enum makes the rationale explicit.
      const event = CelebrationEvent.levelUp(newLevel: 5);
      expect(slotPolicyFor(event), SlotPolicy.drop);
    });
  });

  group('slot policy ↔ queue behavior (integration)', () {
    test(
      'serialize policy: 1 rank-up + 1 title fit into 3-slot cap without overflow',
      () {
        // Both are serialize. Cap=3, 2 events → 2 slots used, 1 idle.
        // No drop, no coalesce.
        final result = CelebrationQueue.build(
          events: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 5),
            CelebrationEvent.titleUnlock(slug: 'chest_r5_initiate'),
          ],
        );
        expect(result.queue, hasLength(2));
        expect(result.overflow, isNull);
      },
    );

    test(
      'drop policy: level-up + 3 rank-ups → level-up drops, no overflow card',
      () {
        // Level-up is drop. Cap=3 filled by 3 rank-ups; level-up vanishes
        // without surfacing on the overflow card. This pins the
        // "level-up is silently absorbed" invariant against future
        // refactors (BUG-013 was the original locking; this test is
        // policy-named).
        final result = CelebrationQueue.build(
          events: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 20),
            CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 15),
            CelebrationEvent.rankUp(bodyPart: BodyPart.legs, newRank: 10),
            CelebrationEvent.levelUp(newLevel: 4),
          ],
        );
        expect(result.queue, hasLength(3));
        expect(result.queue.whereType<LevelUpEvent>(), isEmpty);
        expect(
          result.overflow,
          isNull,
          reason: 'overflow card surfaces trimmed rank-ups only, not level-up',
        );
      },
    );

    test(
      'coalesce policy: 5 rank-ups → top 3 serialize, remainder coalesces into overflow card',
      () {
        // The "coalesce" semantic surfaces as the overflow card's
        // remainingRankUps count. Per-event policy is serialize; the
        // queue's overflow strategy coalesces the cap-trimmed rank-ups.
        final result = CelebrationQueue.build(
          events: const [
            CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 25),
            CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 20),
            CelebrationEvent.rankUp(bodyPart: BodyPart.legs, newRank: 15),
            CelebrationEvent.rankUp(bodyPart: BodyPart.shoulders, newRank: 10),
            CelebrationEvent.rankUp(bodyPart: BodyPart.arms, newRank: 5),
          ],
        );
        expect(result.queue, hasLength(3));
        expect(result.overflow, isNotNull);
        expect(result.overflow!.remainingRankUps, 2);
      },
    );
  });
}
