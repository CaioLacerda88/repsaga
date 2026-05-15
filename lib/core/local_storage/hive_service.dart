import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Provides a [HiveService] instance via Riverpod.
final hiveServiceProvider = Provider<HiveService>((ref) {
  return const HiveService();
});

class HiveService {
  const HiveService();

  static const String activeWorkout = 'active_workout';
  static const String offlineQueue = 'offline_queue';
  static const String userPrefs = 'user_prefs';
  static const String exerciseCache = 'exercise_cache';
  static const String routineCache = 'routine_cache';
  static const String prCache = 'pr_cache';
  static const String workoutHistoryCache = 'workout_history_cache';
  static const String lastSetsCache = 'last_sets_cache';

  /// Bundled schema version for the model-shape-dependent caches
  /// (`exerciseCache`, `routineCache`, `prCache`, `workoutHistoryCache`,
  /// `lastSetsCache`, `activeWorkout`). Bump by 1 in the same PR as any
  /// breaking change to a model that gets serialized into one of those
  /// boxes — adding a required field, renaming a JSON key, changing the
  /// type of an enum's underlying string, etc.
  ///
  /// Bumping this constant causes [migrateCacheSchema] to wipe the affected
  /// boxes once on next app launch for users whose persisted version differs.
  /// `userPrefs` (settings + this very version key) and `offlineQueue`
  /// (pending mutations that haven't drained yet) are deliberately preserved.
  ///
  /// Version log:
  /// - 1: initial baseline (Phase 24c — first PR to introduce the mechanism;
  ///   accompanies the addition of `Exercise.usesBodyweightLoad`. Pre-existing
  ///   installs have no version key and are treated as needing the wipe.)
  ///
  /// Adding `usesBodyweightLoad` with `@Default(false)` is technically
  /// backward-compatible at the Freezed level (legacy rows deserialize as
  /// `false`), but we still wipe so the next read repopulates from the
  /// authoritative server flags — leaving stale `false`s in cache would let
  /// the 20 curated bodyweight exercises miss their effective-load math
  /// until the cache TTL fires.
  static const int currentCacheSchemaVersion = 1;

  /// Hive boxes whose contents are model-serialized payloads from Supabase
  /// reads. These are wiped on cache schema version mismatch — the cost is
  /// one extra network round-trip per cache miss, which is negligible.
  ///
  /// `userPrefs` is excluded because it stores user preferences (locale,
  /// crash-report opt-in, the schema version key itself) that must survive.
  /// `offlineQueue` is excluded because it stores pending mutations whose
  /// loss would cause silent data loss on the user's last unsynced session.
  @visibleForTesting
  static const List<String> cacheSchemaBoxes = [
    activeWorkout,
    exerciseCache,
    routineCache,
    prCache,
    workoutHistoryCache,
    lastSetsCache,
  ];

  /// Hive key (in [userPrefs]) where the persisted cache schema version
  /// lives. Reading the key before any cache-fetching code runs is what
  /// makes the migration idempotent across app launches.
  static const String _cacheSchemaVersionKey = 'cache_schema_version';

  /// Canonical list of every Hive box the app uses.
  ///
  /// Public ([visibleForTesting]) so tests can iterate the same set
  /// `init()` does — keeps the recovery test from drifting if a ninth
  /// box is ever added.
  @visibleForTesting
  static const List<String> allBoxNames = [
    activeWorkout,
    offlineQueue,
    userPrefs,
    exerciseCache,
    routineCache,
    prCache,
    workoutHistoryCache,
    lastSetsCache,
  ];

  /// Open every box, recovering from any single-box corruption by
  /// deleting that box from disk and re-opening empty.
  ///
  /// **Why this exists:** Hive can throw on `openBox` when the on-disk
  /// binary doesn't match the current adapter set or is structurally
  /// damaged. The two failure modes we've seen / planned for:
  /// - `HiveError: unknown typeId: N` — adapter for typeId N was dropped
  ///   or renumbered between the version that wrote the file and the one
  ///   reading it
  /// - `RangeError: Not enough bytes available` — file truncated by
  ///   killed-mid-write or disk-full at flush time
  ///
  /// Both are `Error` subclasses (not `Exception`), so the catch widens
  /// to `on Error` — narrower `on HiveError` would let `RangeError`
  /// propagate and brick the app.
  ///
  /// Without recovery the error escapes through `main()`, `runApp()`
  /// never fires, and the user is stuck on the native splash screen —
  /// a bricked app on first launch (observed live on a Galaxy S25 Ultra,
  /// May 2026).
  ///
  /// On Android specifically the typeId variant can happen even on a
  /// fresh install: auto-backup restores the prior install's Hive files
  /// (typeId set frozen at backup time) into a new APK whose adapters
  /// have moved on. We also disable `android:allowBackup` defensively
  /// (see AndroidManifest.xml), but this code-side recovery is the
  /// primary guarantee — it catches corruption from any source and
  /// self-heals.
  ///
  /// The cost of recovery is one box's worth of cached data (history,
  /// PRs, exercise list, etc.). Cached read-through data is re-fetched
  /// from Supabase on next read, so the user-visible impact is one
  /// extra network round-trip. The `activeWorkout` box is the one
  /// case that genuinely loses state on recovery: an in-progress
  /// session not yet persisted to Supabase is gone. We accept that
  /// trade — losing one in-flight workout vs. a permanently bricked
  /// app is the right call.
  ///
  /// Sentry is intentionally NOT notified here: this code runs before
  /// `main()` reads the user's `crash_reports_enabled` opt-in (the
  /// preference itself lives in one of the boxes we're trying to open).
  /// The `developer.log` call ensures the event is in `adb logcat` for
  /// dev diagnosis without violating opt-out for end users.
  Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait(allBoxNames.map(openWithRecovery));
    // Cache schema migration runs AFTER every box is open: it reads the
    // persisted version from `userPrefs` and wipes [cacheSchemaBoxes] in
    // place when the version differs. The wipe is idempotent on subsequent
    // launches because we stamp the bumped version into `userPrefs` once
    // the wipe completes — version-equal launches no-op.
    await migrateCacheSchema();
  }

  /// Compare persisted cache schema version against
  /// [currentCacheSchemaVersion]; clear [cacheSchemaBoxes] and stamp the
  /// new version when they differ.
  ///
  /// Public for tests so the migration contract can be pinned without
  /// standing up the full Flutter binding harness `init()` requires.
  /// Production callers go through [init].
  ///
  /// Idempotent — calling repeatedly with the version stamped no-ops.
  /// Safe to call before any cache reads happen because [init] sequences
  /// `openWithRecovery` ahead of this method (the boxes are guaranteed
  /// open when this runs).
  @visibleForTesting
  Future<void> migrateCacheSchema() async {
    final prefs = Hive.box<dynamic>(userPrefs);
    final persisted = prefs.get(_cacheSchemaVersionKey) as int?;
    if (persisted == currentCacheSchemaVersion) return;

    developer.log(
      'Cache schema version mismatch (persisted=$persisted, '
      'current=$currentCacheSchemaVersion) — clearing model-shape-dependent '
      'caches. Pending offline mutations and user preferences are preserved.',
      name: 'HiveService',
    );

    for (final boxName in cacheSchemaBoxes) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<dynamic>(boxName).clear();
      }
    }
    await prefs.put(_cacheSchemaVersionKey, currentCacheSchemaVersion);
  }

  /// Open one box, recovering by deleting+reopening on `Error`.
  ///
  /// Public for tests so the corruption-recovery contract can be pinned
  /// without standing up the full Flutter binding harness `init()` requires.
  /// Production callers go through [init] which iterates [allBoxNames].
  @visibleForTesting
  static Future<void> openWithRecovery(String name) async {
    try {
      await Hive.openBox<dynamic>(name);
    } on Error catch (e, stack) {
      // `on Error` covers both `HiveError` (typeId mismatch / format
      // version) and `RangeError` (truncated file). See [init] doc for
      // the rationale on why we don't catch `Exception` instead.
      developer.log(
        'Hive box "$name" failed to open — deleting and re-opening empty. '
        'This typically means stale data from a prior app version or a '
        'truncated file. Error: $e',
        name: 'HiveService',
        error: e,
        stackTrace: stack,
      );
      // Best-effort: a failed open can leave the box partially registered.
      // Try to delete from disk regardless. A FileSystemException here
      // usually just means the file already wasn't there — fine.
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (deleteError, deleteStack) {
        developer.log(
          'deleteBoxFromDisk("$name") during recovery raised; proceeding '
          'with openBox anyway. Error: $deleteError',
          name: 'HiveService',
          error: deleteError,
          stackTrace: deleteStack,
        );
      }
      await Hive.openBox<dynamic>(name);
    }
  }

  Future<void> clearAll() async {
    await Future.wait([
      _clearIfOpen(activeWorkout),
      _clearIfOpen(offlineQueue),
      _clearIfOpen(userPrefs),
      _clearIfOpen(exerciseCache),
      _clearIfOpen(routineCache),
      _clearIfOpen(prCache),
      _clearIfOpen(workoutHistoryCache),
      _clearIfOpen(lastSetsCache),
    ]);
  }

  Future<void> _clearIfOpen(String name) async {
    if (Hive.isBoxOpen(name)) {
      await Hive.box<dynamic>(name).clear();
    }
  }
}
