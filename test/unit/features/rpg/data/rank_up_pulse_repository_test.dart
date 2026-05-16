import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    // Use Hive.init(tempDir) — pure unit tests can't call Hive.initFlutter()
    // because it depends on path_provider, which has no implementation in
    // the host VM (matches the pattern used in hive_service_test.dart).
    tempDir = await Directory.systemTemp.createTemp('rank_up_pulse_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(RankUpPulseRepository.boxName);
    await Hive.box<dynamic>(RankUpPulseRepository.boxName).clear();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('RankUpPulseRepository', () {
    test('isPulsing returns false when no entry exists', () {
      final repo = RankUpPulseRepository();
      expect(
        repo.isPulsing(BodyPart.chest, now: DateTime(2026, 5, 15)),
        isFalse,
      );
    });

    test('isPulsing returns true within the 24h window', () async {
      final repo = RankUpPulseRepository();
      final triggeredAt = DateTime(2026, 5, 15, 10, 0);
      await repo.recordRankUp(BodyPart.chest, at: triggeredAt);
      expect(
        repo.isPulsing(
          BodyPart.chest,
          now: triggeredAt.add(const Duration(hours: 23)),
        ),
        isTrue,
      );
    });

    test('isPulsing returns false after the 24h window expires', () async {
      final repo = RankUpPulseRepository();
      final triggeredAt = DateTime(2026, 5, 15, 10, 0);
      await repo.recordRankUp(BodyPart.chest, at: triggeredAt);
      expect(
        repo.isPulsing(
          BodyPart.chest,
          now: triggeredAt.add(const Duration(hours: 24, seconds: 1)),
        ),
        isFalse,
      );
    });

    test('isPulsing checks each body part independently', () async {
      final repo = RankUpPulseRepository();
      final now = DateTime(2026, 5, 15);
      await repo.recordRankUp(BodyPart.chest, at: now);
      expect(repo.isPulsing(BodyPart.chest, now: now), isTrue);
      expect(repo.isPulsing(BodyPart.back, now: now), isFalse);
    });

    test(
      'recordRankUp overwrites the prior entry for the same body part',
      () async {
        final repo = RankUpPulseRepository();
        final first = DateTime(2026, 5, 14, 10, 0);
        final second = DateTime(2026, 5, 15, 10, 0);
        await repo.recordRankUp(BodyPart.chest, at: first);
        await repo.recordRankUp(BodyPart.chest, at: second);
        expect(
          repo.isPulsing(
            BodyPart.chest,
            now: second.add(const Duration(hours: 23)),
          ),
          isTrue,
        );
      },
    );

    test('sweepExpired removes only entries past their 24h window', () async {
      final repo = RankUpPulseRepository();
      final now = DateTime(2026, 5, 15, 10, 0);
      // Chest: well within the window (just-triggered).
      await repo.recordRankUp(BodyPart.chest, at: now);
      // Back: 25h ago (expired).
      await repo.recordRankUp(
        BodyPart.back,
        at: now.subtract(const Duration(hours: 25)),
      );
      await repo.sweepExpired(now: now);
      expect(repo.isPulsing(BodyPart.chest, now: now), isTrue);
      expect(repo.isPulsing(BodyPart.back, now: now), isFalse);
    });
  });
}
