import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/features/rpg/data/vitality_fresh_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    // Pure unit test — Hive.init(tempDir), not initFlutter (no path_provider
    // in the host VM). Matches rank_up_pulse_local_storage_test.
    tempDir = await Directory.systemTemp.createTemp('vitality_fresh_pulse_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(VitalityFreshPulseLocalStorage.boxName);
    await Hive.box<dynamic>(VitalityFreshPulseLocalStorage.boxName).clear();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('VitalityFreshPulseLocalStorage', () {
    test('isPulsing false when no entry exists', () {
      final repo = VitalityFreshPulseLocalStorage();
      expect(
        repo.isPulsing(BodyPart.chest, now: DateTime(2026, 6, 19)),
        isFalse,
      );
    });

    test('recordCharged marks the bp pulsing within the 24h window', () async {
      final repo = VitalityFreshPulseLocalStorage();
      final at = DateTime(2026, 6, 19, 10, 0);
      await repo.recordCharged(BodyPart.chest, at: at);
      expect(
        repo.isPulsing(BodyPart.chest, now: at.add(const Duration(hours: 23))),
        isTrue,
      );
    });

    test('pulse expires after 24h (strict <)', () async {
      final repo = VitalityFreshPulseLocalStorage();
      final at = DateTime(2026, 6, 19, 10, 0);
      await repo.recordCharged(BodyPart.chest, at: at);
      expect(
        repo.isPulsing(BodyPart.chest, now: at.add(const Duration(hours: 24))),
        isFalse,
      );
    });

    test('recordChargedBatch marks every trained bp pulsing', () async {
      final repo = VitalityFreshPulseLocalStorage();
      final at = DateTime(2026, 6, 19, 10, 0);
      await repo.recordChargedBatch(const [
        BodyPart.chest,
        BodyPart.back,
        BodyPart.legs,
      ], at: at);
      final now = at.add(const Duration(hours: 1));
      expect(repo.isPulsing(BodyPart.chest, now: now), isTrue);
      expect(repo.isPulsing(BodyPart.back, now: now), isTrue);
      expect(repo.isPulsing(BodyPart.legs, now: now), isTrue);
      // An untrained bp stays quiet.
      expect(repo.isPulsing(BodyPart.shoulders, now: now), isFalse);
    });

    test('a later save re-arms the full 24h window', () async {
      final repo = VitalityFreshPulseLocalStorage();
      final first = DateTime(2026, 6, 18, 10, 0);
      final second = DateTime(2026, 6, 19, 10, 0);
      await repo.recordCharged(BodyPart.chest, at: first);
      await repo.recordCharged(BodyPart.chest, at: second);
      expect(
        repo.isPulsing(
          BodyPart.chest,
          now: second.add(const Duration(hours: 23)),
        ),
        isTrue,
      );
    });

    test('sweepExpired removes only entries past their 24h window', () async {
      final repo = VitalityFreshPulseLocalStorage();
      final now = DateTime(2026, 6, 19, 10, 0);
      await repo.recordCharged(BodyPart.chest, at: now);
      await repo.recordCharged(
        BodyPart.back,
        at: now.subtract(const Duration(hours: 25)),
      );
      await repo.sweepExpired(now: now);
      expect(repo.isPulsing(BodyPart.chest, now: now), isTrue);
      expect(repo.isPulsing(BodyPart.back, now: now), isFalse);
    });
  });
}
