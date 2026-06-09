import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/routines/providers/routine_hint_provider.dart';

void main() {
  group('RoutineHintNotifier', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_routine_hint_');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>(HiveService.userPrefs);
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    ProviderContainer makeContainer() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('shows the hint on fresh prefs (unseen, zero views)', () {
      final container = makeContainer();
      expect(container.read(routineHintProvider), isTrue);
    });

    test('hides the hint after markSeen flips the seen flag', () async {
      final container = makeContainer();
      expect(container.read(routineHintProvider), isTrue);

      await container.read(routineHintProvider.notifier).markSeen();

      expect(container.read(routineHintProvider), isFalse);
      // Persisted, so a fresh container (cold start) also stays hidden.
      final fresh = makeContainer();
      expect(fresh.read(routineHintProvider), isFalse);
    });

    test(
      'markSeen is idempotent — second call is a value-equal no-op',
      () async {
        final box = Hive.box<dynamic>(HiveService.userPrefs);
        final container = makeContainer();

        await container.read(routineHintProvider.notifier).markSeen();
        expect(box.get(routineHintSeenKey), isTrue);
        // Second call must not throw and must leave the flag true.
        await container.read(routineHintProvider.notifier).markSeen();
        expect(box.get(routineHintSeenKey), isTrue);
        expect(container.read(routineHintProvider), isFalse);
      },
    );

    test('hides the hint once view count reaches the cap (3)', () async {
      final box = Hive.box<dynamic>(HiveService.userPrefs);
      await box.put(routineHintViewCountKey, 3);

      final container = makeContainer();
      expect(container.read(routineHintProvider), isFalse);
    });

    test('still shows below the cap (2 views, unseen)', () async {
      final box = Hive.box<dynamic>(HiveService.userPrefs);
      await box.put(routineHintViewCountKey, 2);

      final container = makeContainer();
      expect(container.read(routineHintProvider), isTrue);
    });

    test('recordView increments and hides on the third view', () async {
      final box = Hive.box<dynamic>(HiveService.userPrefs);
      final container = makeContainer();
      final notifier = container.read(routineHintProvider.notifier);

      await notifier.recordView(); // 1
      expect(box.get(routineHintViewCountKey), 1);
      expect(container.read(routineHintProvider), isTrue);

      await notifier.recordView(); // 2
      expect(box.get(routineHintViewCountKey), 2);
      expect(container.read(routineHintProvider), isTrue);

      await notifier.recordView(); // 3 → hits cap, hides
      expect(box.get(routineHintViewCountKey), 3);
      expect(container.read(routineHintProvider), isFalse);

      // Further views never push the counter past the cap.
      await notifier.recordView();
      expect(box.get(routineHintViewCountKey), 3);
    });

    test('recordView no-ops once the gesture has been discovered', () async {
      final box = Hive.box<dynamic>(HiveService.userPrefs);
      await box.put(routineHintSeenKey, true);

      final container = makeContainer();
      await container.read(routineHintProvider.notifier).recordView();

      // No view counting happens after discovery — the seen flag already
      // retires the hint, so we don't churn the counter.
      expect(box.get(routineHintViewCountKey), isNull);
      expect(container.read(routineHintProvider), isFalse);
    });
  });
}
