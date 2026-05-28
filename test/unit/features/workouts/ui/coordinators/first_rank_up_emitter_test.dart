import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/workouts/ui/coordinators/finish_workout_coordinator.dart';

/// Pins the Phase 32 PR 32d idempotency contract for [FirstRankUpEmitter].
///
/// **Behavior, not wiring** (CLAUDE.md Testing). Each test asserts on the
/// captured `AnalyticsEvent` value the recording repo received — NOT just
/// that `insertEvent()` was called N times. The captured events are
/// `==`-compared against the canonical [AnalyticsEvent.firstRankUp]
/// payload, so a future refactor that changes the prop shape will fail
/// here loudly instead of silently shipping a broken funnel signal.
///
/// The Hive cache is exercised through the public emitter surface
/// (`emitForRankUps`) so the contract is "what happens when a celebration
/// is fed in twice", not "what bytes get written to the box". The latter
/// is covered indirectly by reading the cache back with [readFiredSlugs]
/// after each emit pass.
void main() {
  group('FirstRankUpEmitter', () {
    late Directory tempDir;
    late _RecordingAnalyticsRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('first_rank_up_test_');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>(HiveService.userPrefs);
      repo = _RecordingAnalyticsRepository();
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test(
      'first emit for (user, chest) records event + writes the slug',
      () async {
        await FirstRankUpEmitter.emitForRankUps(
          userId: 'user-1',
          analyticsRepo: repo,
          rankUps: const [RankUpEvent(bodyPart: BodyPart.chest, newRank: 2)],
        );

        expect(repo.events, [
          const AnalyticsEvent.firstRankUp(bodyPart: 'chest', newRank: 2),
        ]);
        expect(FirstRankUpEmitter.readFiredSlugs('user-1'), ['chest']);
      },
    );

    test('second emit for same (user, chest) is a no-op', () async {
      // Seed the cache as if a prior session already fired for chest.
      await FirstRankUpEmitter.writeFiredSlugs('user-1', ['chest']);

      await FirstRankUpEmitter.emitForRankUps(
        userId: 'user-1',
        analyticsRepo: repo,
        rankUps: const [RankUpEvent(bodyPart: BodyPart.chest, newRank: 3)],
      );

      expect(
        repo.events,
        isEmpty,
        reason: 'second emit for same body part must not record',
      );
      expect(
        FirstRankUpEmitter.readFiredSlugs('user-1'),
        ['chest'],
        reason: 'cache must not duplicate the slug',
      );
    });

    test('different body part fires independently', () async {
      await FirstRankUpEmitter.writeFiredSlugs('user-1', ['chest']);

      await FirstRankUpEmitter.emitForRankUps(
        userId: 'user-1',
        analyticsRepo: repo,
        rankUps: const [RankUpEvent(bodyPart: BodyPart.back, newRank: 1)],
      );

      expect(repo.events, [
        const AnalyticsEvent.firstRankUp(bodyPart: 'back', newRank: 1),
      ]);
      // Cache now contains BOTH slugs — chest was already there, back
      // joined it. Order reflects insertion order (chest first).
      expect(FirstRankUpEmitter.readFiredSlugs('user-1'), ['chest', 'back']);
    });

    test('different user has an independent cache', () async {
      await FirstRankUpEmitter.writeFiredSlugs('user-1', ['chest']);

      await FirstRankUpEmitter.emitForRankUps(
        userId: 'user-2',
        analyticsRepo: repo,
        rankUps: const [RankUpEvent(bodyPart: BodyPart.chest, newRank: 2)],
      );

      expect(repo.events, [
        const AnalyticsEvent.firstRankUp(bodyPart: 'chest', newRank: 2),
      ], reason: 'user-2 has never fired for chest — must emit');
      expect(
        FirstRankUpEmitter.readFiredSlugs('user-1'),
        ['chest'],
        reason: 'user-1 cache must remain untouched',
      );
      expect(FirstRankUpEmitter.readFiredSlugs('user-2'), ['chest']);
    });

    test(
      'multi-rank-up batch fires once per body part on cold cache',
      () async {
        await FirstRankUpEmitter.emitForRankUps(
          userId: 'user-1',
          analyticsRepo: repo,
          rankUps: const [
            RankUpEvent(bodyPart: BodyPart.chest, newRank: 2),
            RankUpEvent(bodyPart: BodyPart.back, newRank: 1),
            RankUpEvent(bodyPart: BodyPart.legs, newRank: 1),
          ],
        );

        expect(repo.events, const [
          AnalyticsEvent.firstRankUp(bodyPart: 'chest', newRank: 2),
          AnalyticsEvent.firstRankUp(bodyPart: 'back', newRank: 1),
          AnalyticsEvent.firstRankUp(bodyPart: 'legs', newRank: 1),
        ]);
        expect(FirstRankUpEmitter.readFiredSlugs('user-1'), [
          'chest',
          'back',
          'legs',
        ]);
      },
    );

    test('empty rank-up list is a no-op (no Hive write, no insert)', () async {
      await FirstRankUpEmitter.emitForRankUps(
        userId: 'user-1',
        analyticsRepo: repo,
        rankUps: const [],
      );

      expect(repo.events, isEmpty);
      expect(FirstRankUpEmitter.readFiredSlugs('user-1'), isEmpty);
    });

    test(
      'insertEvent throwing leaves the slug OUT of the fired cache so the '
      'next session retries (PR #277 review fix — ordering invariant)',
      () async {
        // Production [AnalyticsRepository.insertEvent] swallows internally,
        // but the emitter's per-event `on Object` catch is a belt against
        // future signature changes. A throw must NOT poison the cache —
        // otherwise a single transient outage permanently marks the body
        // part as "fired" on this device and the event never lands.
        final throwingRepo = _ThrowingAnalyticsRepository();

        await FirstRankUpEmitter.emitForRankUps(
          userId: 'user-1',
          analyticsRepo: throwingRepo,
          rankUps: const [RankUpEvent(bodyPart: BodyPart.chest, newRank: 2)],
        );

        expect(
          FirstRankUpEmitter.readFiredSlugs('user-1'),
          isEmpty,
          reason:
              'failed insertEvent must leave the slug unrecorded so a '
              'subsequent finish can retry',
        );

        // The next emit with a working repo lands the event.
        await FirstRankUpEmitter.emitForRankUps(
          userId: 'user-1',
          analyticsRepo: repo,
          rankUps: const [RankUpEvent(bodyPart: BodyPart.chest, newRank: 2)],
        );
        expect(repo.events, [
          const AnalyticsEvent.firstRankUp(bodyPart: 'chest', newRank: 2),
        ]);
        expect(FirstRankUpEmitter.readFiredSlugs('user-1'), ['chest']);
      },
    );

    test(
      'mixed throw + success in one batch caches only the succeeded slug',
      () async {
        final partialRepo = _ThrowOnSlugAnalyticsRepository(throwOn: 'chest');

        await FirstRankUpEmitter.emitForRankUps(
          userId: 'user-1',
          analyticsRepo: partialRepo,
          rankUps: const [
            RankUpEvent(bodyPart: BodyPart.chest, newRank: 2),
            RankUpEvent(bodyPart: BodyPart.back, newRank: 1),
          ],
        );

        // Only `back` made it through — `chest` threw, so it stays unrecorded.
        expect(partialRepo.events, [
          const AnalyticsEvent.firstRankUp(bodyPart: 'back', newRank: 1),
        ]);
        expect(FirstRankUpEmitter.readFiredSlugs('user-1'), ['back']);
      },
    );
  });
}

/// Recording fake — captures every event the emitter pushes through
/// [AnalyticsRepository.insertEvent] so tests can assert on the EXACT
/// payload (not just the call count).
class _RecordingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    events.add(event);
  }
}

/// Always-throwing fake — production `insertEvent` swallows internally,
/// but the emitter's per-event `on Object` catch must defend against a
/// future signature change. Used to pin the "failed insert leaves the
/// fired-cache untouched" ordering invariant.
class _ThrowingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    throw StateError('synthetic insert failure');
  }
}

/// Throws when [insertEvent] is called for a specific body-part slug,
/// records the event otherwise. Used to assert mixed-success batches
/// only persist the succeeded slugs.
class _ThrowOnSlugAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  _ThrowOnSlugAnalyticsRepository({required this.throwOn});

  final String throwOn;
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    final maybeSlug = event.props['body_part'];
    if (maybeSlug == throwOn) {
      throw StateError('synthetic insert failure for $throwOn');
    }
    events.add(event);
  }
}
