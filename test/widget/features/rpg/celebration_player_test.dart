/// Widget tests for [CelebrationPlayer.play] post-Path-A pivot (PR 29.5).
///
/// **Path A contract (this PR):** the player no longer renders UI
/// mid-workout. It is a pass-through that returns
/// [CelebrationPlayResult.notTapped] synchronously for every input. The
/// full celebration migrates to the post-session screen in PR 30a.
///
/// These tests pin the new contract:
///   * Every [CelebrationEvent] variant resolves to `notTapped` without
///     mounting any overlay / dialog / OverlayEntry.
///   * Empty queue → `notTapped`.
///   * Queue WITH overflow payload → still `notTapped` (no overflow
///     card mounts — PR 30a's post-session screen owns that surface).
///   * The deprecated `onEquipTitle` callback is never invoked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/ui/celebration_player.dart';
import 'package:repsaga/features/rpg/ui/overlays/celebration_overflow_card.dart';

import '../../../helpers/test_material_app.dart';

const _chestR5 = rpg.Title.bodyPart(
  slug: 'chest_r5_initiate_of_the_forge',
  bodyPart: BodyPart.chest,
  rankThreshold: 5,
);

void main() {
  group('CelebrationPlayer.play return contract', () {
    testWidgets('returns notTapped for an empty queue', (tester) async {
      late CelebrationPlayResult result;
      await tester.pumpWidget(
        TestMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await CelebrationPlayer.play(
                    context,
                    result: const CelebrationQueueResult(
                      queue: <CelebrationEvent>[],
                    ),
                    catalog: const <rpg.Title>[],
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(result.userTappedOverflow, isFalse);
    });

    testWidgets('returns notTapped when the queue carries an overflow payload '
        '(post-session screen owns the overflow surface in PR 30a)', (
      tester,
    ) async {
      // Path A pivot: the overflow card no longer mounts mid-workout.
      // PR 30a's post-session screen consumes [CelebrationQueueResult]
      // directly and renders the overflow surface as part of the
      // ceremony. This test pins that the mid-workout player NEVER
      // mounts CelebrationOverflowCard, even when overflow data is
      // present.
      late CelebrationPlayResult result;
      await tester.pumpWidget(
        TestMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await CelebrationPlayer.play(
                    context,
                    result: const CelebrationQueueResult(
                      queue: <CelebrationEvent>[],
                      overflow: OverflowPayload(remainingRankUps: 3),
                    ),
                    catalog: const <rpg.Title>[],
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      // No overflow card is mounted (Path A: no mid-workout UI).
      expect(find.byType(CelebrationOverflowCard), findsNothing);
      // Pump for a full second to make sure no late mount races us.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CelebrationOverflowCard), findsNothing);

      expect(result.userTappedOverflow, isFalse);
    });
  });

  group('CelebrationPlayer — variant pass-through contract (Path A)', () {
    testWidgets(
      'every event variant resolves to notTapped without mounting UI',
      (tester) async {
        // Pin the Path A contract: the player accepts every variant the
        // sealed union exposes today and returns `notTapped` without
        // mounting any overlay / dialog / OverlayEntry. A future
        // refactor that re-introduced mid-workout playback would fail
        // this test (no widgets should mount during the play() call).
        final variants = <CelebrationEvent>[
          const CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 5),
          const CelebrationEvent.levelUp(newLevel: 3),
          const CelebrationEvent.firstAwakening(bodyPart: BodyPart.legs),
          const CelebrationEvent.classChange(
            fromClass: CharacterClass.initiate,
            toClass: CharacterClass.bulwark,
          ),
          const CelebrationEvent.titleUnlock(
            slug: 'chest_r5_initiate_of_the_forge',
          ),
          const CelebrationEvent.personalRecord(
            exerciseId: 'abc-123',
            exerciseName: 'Bench Press',
            weight: 100,
            reps: 5,
            repBand: '1-5',
          ),
        ];

        for (final event in variants) {
          late CelebrationPlayResult result;
          await tester.pumpWidget(
            TestMaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      result = await CelebrationPlayer.play(
                        context,
                        result: CelebrationQueueResult(
                          queue: <CelebrationEvent>[event],
                        ),
                        catalog: const <rpg.Title>[_chestR5],
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('go'));
          await tester.pump();
          // Allow any late-mounted widget a frame to surface.
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            find.byType(CelebrationOverflowCard),
            findsNothing,
            reason:
                '${event.runtimeType}: Path A pass-through must NOT mount '
                'CelebrationOverflowCard mid-workout',
          );
          // Dialog routes have a Material barrier; pin none is present.
          expect(
            find.byType(Dialog),
            findsNothing,
            reason:
                '${event.runtimeType}: Path A pass-through must NOT mount '
                'any Dialog mid-workout',
          );
          expect(
            result.userTappedOverflow,
            isFalse,
            reason:
                '${event.runtimeType}: pass-through always returns '
                'userTappedOverflow == false',
          );
        }
      },
    );

    testWidgets('deprecated onEquipTitle callback is never invoked', (
      tester,
    ) async {
      // PR 29.5 retired the title half-sheet's EQUIP CTA. PR 30a
      // moves the affordance to the post-session summary panel. Pin
      // that the mid-workout player NEVER invokes the deprecated
      // callback even when a title-unlock event is in the queue.
      var equipCalls = 0;

      await tester.pumpWidget(
        TestMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  CelebrationPlayer.play(
                    context,
                    result: const CelebrationQueueResult(
                      queue: <CelebrationEvent>[
                        CelebrationEvent.titleUnlock(
                          slug: 'chest_r5_initiate_of_the_forge',
                        ),
                      ],
                    ),
                    catalog: const <rpg.Title>[_chestR5],
                    // ignore: deprecated_member_use_from_same_package
                    // Intentionally passes a non-null callback to
                    // verify the pass-through never invokes it.
                    onEquipTitle: (_) async {
                      equipCalls += 1;
                    },
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(equipCalls, 0);
    });
  });
}
