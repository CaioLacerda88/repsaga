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
