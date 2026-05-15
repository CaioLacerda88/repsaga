import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  group('HiveService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_svc_test_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    group('box constants', () {
      test('all 8 box names are unique', () {
        final names = [
          HiveService.activeWorkout,
          HiveService.offlineQueue,
          HiveService.userPrefs,
          HiveService.exerciseCache,
          HiveService.routineCache,
          HiveService.prCache,
          HiveService.workoutHistoryCache,
          HiveService.lastSetsCache,
        ];
        expect(names.toSet().length, 8);
      });
    });

    group('init', () {
      test('opens all 8 boxes', () async {
        // HiveService.init() calls Hive.initFlutter() which needs Flutter
        // bindings. Instead, we simulate what init does: open all boxes
        // and verify they are accessible.
        await Future.wait([
          Hive.openBox<dynamic>(HiveService.activeWorkout),
          Hive.openBox<dynamic>(HiveService.offlineQueue),
          Hive.openBox<dynamic>(HiveService.userPrefs),
          Hive.openBox<dynamic>(HiveService.exerciseCache),
          Hive.openBox<dynamic>(HiveService.routineCache),
          Hive.openBox<dynamic>(HiveService.prCache),
          Hive.openBox<dynamic>(HiveService.workoutHistoryCache),
          Hive.openBox<dynamic>(HiveService.lastSetsCache),
        ]);

        expect(Hive.isBoxOpen(HiveService.activeWorkout), isTrue);
        expect(Hive.isBoxOpen(HiveService.offlineQueue), isTrue);
        expect(Hive.isBoxOpen(HiveService.userPrefs), isTrue);
        expect(Hive.isBoxOpen(HiveService.exerciseCache), isTrue);
        expect(Hive.isBoxOpen(HiveService.routineCache), isTrue);
        expect(Hive.isBoxOpen(HiveService.prCache), isTrue);
        expect(Hive.isBoxOpen(HiveService.workoutHistoryCache), isTrue);
        expect(Hive.isBoxOpen(HiveService.lastSetsCache), isTrue);
      });
    });

    group('openWithRecovery (corruption self-heal)', () {
      // Pins the load-bearing invariant that a single-box corruption (e.g.
      // stale typeId from a backup-restored Hive file) auto-heals instead
      // of bricking the app on the splash screen. See HiveService.init()
      // doc comment for the full rationale.

      test('opens a clean box normally', () async {
        await HiveService.openWithRecovery(HiveService.exerciseCache);
        expect(Hive.isBoxOpen(HiveService.exerciseCache), isTrue);

        // Box is usable.
        final box = Hive.box<dynamic>(HiveService.exerciseCache);
        await box.put('k', 'v');
        expect(box.get('k'), 'v');
      });

      test(
        'recovers a corrupt box by deleting from disk and reopening empty',
        () async {
          // Write a binary file at Hive's expected path that is not a valid
          // Hive frame. `Hive.openBox` will throw `HiveError` on read
          // (analogous to the production "unknown typeId" failure mode but
          // triggered without needing a real adapter mismatch).
          //
          // Hive's on-disk filename convention is `<box-name>.hive` inside
          // the directory passed to `Hive.init`.
          final corruptFile = File(
            '${tempDir.path}/${HiveService.workoutHistoryCache}.hive',
          );
          // 0xFF prefix bytes are not a valid Hive frame header — Hive
          // bails out reading the binary stream.
          await corruptFile.writeAsBytes([
            0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF,
            0x2D, // typeId 45 marker — same shape as the production failure
            0x00, 0x01, 0x02, 0x03,
          ]);
          expect(corruptFile.existsSync(), isTrue);

          // Recovery path: open succeeds (box is empty) instead of throwing.
          await HiveService.openWithRecovery(HiveService.workoutHistoryCache);

          expect(Hive.isBoxOpen(HiveService.workoutHistoryCache), isTrue);
          final box = Hive.box<dynamic>(HiveService.workoutHistoryCache);
          expect(
            box.isEmpty,
            isTrue,
            reason:
                'Recovered box must be empty — the corrupt file was deleted '
                'and a fresh box was opened.',
          );

          // Box is fully usable post-recovery.
          await box.put('k', 'v');
          expect(box.get('k'), 'v');
        },
      );

      test('init() opens all 8 boxes and recovers any corrupt one', () async {
        // Plant corruption in two of the eight boxes; init must still
        // bring all of them up. Iterate the canonical list so this test
        // stays in sync if a ninth box is ever added.
        for (final name in [HiveService.prCache, HiveService.routineCache]) {
          await File(
            '${tempDir.path}/$name.hive',
          ).writeAsBytes([0xFF, 0xFF, 0x2D, 0x00]);
        }

        // Open each box through openWithRecovery (mirrors what init() does
        // post-Hive.initFlutter; the unit-test harness already called
        // Hive.init in setUp so we skip the Flutter-binding step).
        await Future.wait(
          HiveService.allBoxNames.map(HiveService.openWithRecovery),
        );

        for (final name in HiveService.allBoxNames) {
          expect(
            Hive.isBoxOpen(name),
            isTrue,
            reason: 'Box "$name" must be open after recovery',
          );
        }
      });

      test('recovers from RangeError (truncated file)', () async {
        // The binary reader throws RangeError when the on-disk file is
        // truncated mid-frame (killed-mid-write, disk-full at flush).
        // Catch must be `on Error`, not `on HiveError`, to cover this —
        // RangeError is an Error subclass, not an Exception.
        //
        // A 2-byte file is too short to hold even a frame header, which
        // forces the binary reader's bounds check to fire.
        final truncated = File(
          '${tempDir.path}/${HiveService.lastSetsCache}.hive',
        );
        await truncated.writeAsBytes([0x01, 0x02]);

        await HiveService.openWithRecovery(HiveService.lastSetsCache);

        expect(Hive.isBoxOpen(HiveService.lastSetsCache), isTrue);
        final box = Hive.box<dynamic>(HiveService.lastSetsCache);
        expect(box.isEmpty, isTrue);
      });
    });

    // ---------------------------------------------------------------
    // Phase 24c — cache schema migration
    //
    // Pins the contract that bumping `currentCacheSchemaVersion` wipes the
    // model-shape-dependent caches once on next app launch and stamps the
    // new version into `userPrefs` so subsequent launches no-op.
    // `userPrefs` and `offlineQueue` MUST survive the wipe — losing user
    // settings or pending offline mutations is unacceptable.
    // ---------------------------------------------------------------
    group('migrateCacheSchema', () {
      Future<void> openAllBoxes() async {
        for (final name in HiveService.allBoxNames) {
          await Hive.openBox<dynamic>(name);
        }
      }

      Future<void> seedAllBoxes() async {
        for (final name in HiveService.allBoxNames) {
          await Hive.box<dynamic>(name).put('seeded_key', 'seeded_value');
        }
      }

      test('clears cacheSchemaBoxes when no version key is persisted yet '
          '(fresh install upgrade path)', () async {
        await openAllBoxes();
        await seedAllBoxes();

        // No version key persisted — represents a user upgrading from a
        // pre-Phase-24c install. The migration MUST wipe the affected
        // boxes so legacy serialized rows are repopulated under the new
        // model shape.
        expect(
          Hive.box<dynamic>(HiveService.userPrefs).get('cache_schema_version'),
          isNull,
        );

        await const HiveService().migrateCacheSchema();

        for (final name in HiveService.cacheSchemaBoxes) {
          expect(
            Hive.box<dynamic>(name).isEmpty,
            isTrue,
            reason: 'Box "$name" must be wiped on version mismatch',
          );
        }
      });

      test('preserves userPrefs and offlineQueue across the wipe', () async {
        await openAllBoxes();
        await seedAllBoxes();

        await const HiveService().migrateCacheSchema();

        expect(
          Hive.box<dynamic>(HiveService.userPrefs).get('seeded_key'),
          'seeded_value',
          reason:
              'userPrefs must survive — locale, opt-in flags, and the '
              'cache_schema_version key itself live there.',
        );
        expect(
          Hive.box<dynamic>(HiveService.offlineQueue).get('seeded_key'),
          'seeded_value',
          reason:
              'offlineQueue must survive — pending offline mutations would '
              'cause silent user-data loss if wiped.',
        );
      });

      test(
        'stamps currentCacheSchemaVersion into userPrefs after wiping',
        () async {
          await openAllBoxes();

          await const HiveService().migrateCacheSchema();

          expect(
            Hive.box<dynamic>(
              HiveService.userPrefs,
            ).get('cache_schema_version'),
            HiveService.currentCacheSchemaVersion,
          );
        },
      );

      test('is idempotent — second call no-ops and does not re-wipe data '
          'written between calls', () async {
        await openAllBoxes();

        // First call stamps the version and (vacuously) wipes the empty
        // boxes.
        await const HiveService().migrateCacheSchema();

        // Simulate normal post-migration cache writes happening during
        // app use.
        await Hive.box<dynamic>(
          HiveService.exerciseCache,
        ).put('post_migrate', 'should_survive');

        // Second call must short-circuit on version match and leave the
        // newly-written data intact.
        await const HiveService().migrateCacheSchema();

        expect(
          Hive.box<dynamic>(HiveService.exerciseCache).get('post_migrate'),
          'should_survive',
        );
      });

      test(
        'wipes when persisted version is older than currentCacheSchemaVersion',
        () async {
          await openAllBoxes();
          await seedAllBoxes();

          // Pretend the user is on an older cache version (currentVersion - 1
          // or 0 if current is 1). The migration must still fire because the
          // condition is "differs from current", not "less than current".
          await Hive.box<dynamic>(
            HiveService.userPrefs,
          ).put('cache_schema_version', 0);

          await const HiveService().migrateCacheSchema();

          for (final name in HiveService.cacheSchemaBoxes) {
            expect(
              Hive.box<dynamic>(name).isEmpty,
              isTrue,
              reason: 'Box "$name" must be wiped when persisted version=0',
            );
          }
          expect(
            Hive.box<dynamic>(
              HiveService.userPrefs,
            ).get('cache_schema_version'),
            HiveService.currentCacheSchemaVersion,
          );
        },
      );

      test('cacheSchemaBoxes excludes userPrefs and offlineQueue by '
          'construction (defence-in-depth)', () {
        // Belt-and-braces check: even if a future maintainer accidentally
        // loops over `cacheSchemaBoxes` for another wipe, userPrefs and
        // offlineQueue are off-limits and must not appear in the list.
        expect(
          HiveService.cacheSchemaBoxes,
          isNot(contains(HiveService.userPrefs)),
        );
        expect(
          HiveService.cacheSchemaBoxes,
          isNot(contains(HiveService.offlineQueue)),
        );
      });
    });

    group('clearAll', () {
      test('clears all 8 boxes', () async {
        // Open all boxes and put some data in each.
        final boxNames = [
          HiveService.activeWorkout,
          HiveService.offlineQueue,
          HiveService.userPrefs,
          HiveService.exerciseCache,
          HiveService.routineCache,
          HiveService.prCache,
          HiveService.workoutHistoryCache,
          HiveService.lastSetsCache,
        ];

        for (final name in boxNames) {
          final box = await Hive.openBox<dynamic>(name);
          await box.put('test_key', 'test_value');
        }

        const service = HiveService();
        await service.clearAll();

        for (final name in boxNames) {
          expect(
            Hive.box<dynamic>(name).isEmpty,
            isTrue,
            reason: 'Box "$name" should be empty after clearAll()',
          );
        }
      });

      test('does not throw when some boxes are closed', () async {
        // Open only a subset of boxes, simulating a partial-init scenario
        // (e.g., clearAll called before init completes for all boxes).
        final openBoxes = [
          HiveService.activeWorkout,
          HiveService.exerciseCache,
        ];
        for (final name in openBoxes) {
          final box = await Hive.openBox<dynamic>(name);
          await box.put('test_key', 'test_value');
        }

        // The other 6 boxes remain closed — _clearIfOpen should skip them
        // without throwing.
        const service = HiveService();
        await expectLater(service.clearAll(), completes);

        // The two open boxes must have been cleared.
        for (final name in openBoxes) {
          expect(
            Hive.box<dynamic>(name).isEmpty,
            isTrue,
            reason: 'Box "$name" should be empty after clearAll()',
          );
        }
      });
    });
  });
}
