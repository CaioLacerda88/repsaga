import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';
import '../models/active_workout_state.dart';

class WorkoutLocalStorage {
  static const int _currentSchemaVersion = 1;
  static const String _workoutKey = 'current_workout';
  static const String _schemaVersionKey = 'schema_version';

  Box<dynamic> get _box => Hive.box<dynamic>(HiveService.activeWorkout);

  /// Persist the active workout state to Hive.
  Future<void> saveActiveWorkout(ActiveWorkoutState state) async {
    await _box.put(_workoutKey, jsonEncode(state.toJson()));
    await _box.put(_schemaVersionKey, _currentSchemaVersion);
  }

  /// Load the active workout from Hive.
  /// Returns null on: empty box, corrupt JSON, schema version mismatch.
  ActiveWorkoutState? loadActiveWorkout() {
    try {
      final version = _box.get(_schemaVersionKey) as int?;
      if (version != _currentSchemaVersion) {
        if (version != null) {
          // Cluster: developer-log-invisible-logcat (PR 32g) — adb logcat
          // visibility for schema-mismatch fallbacks on physical devices.
          debugPrint(
            '[WorkoutLocalStorage] Schema version mismatch: expected '
            '$_currentSchemaVersion, got $version. Discarding stale workout '
            'data.',
          );
        }
        return null;
      }

      final raw = _box.get(_workoutKey) as String?;
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ActiveWorkoutState.fromJson(json);
    } catch (e) {
      // Cluster: developer-log-invisible-logcat (PR 32g).
      debugPrint(
        '[WorkoutLocalStorage] Failed to load active workout from Hive: $e',
      );
      return null;
    }
  }

  /// Clear the active workout from Hive.
  Future<void> clearActiveWorkout() async {
    await _box.delete(_workoutKey);
    await _box.delete(_schemaVersionKey);
  }

  /// Whether there is an active workout persisted in Hive.
  bool get hasActiveWorkout {
    final version = _box.get(_schemaVersionKey) as int?;
    return version == _currentSchemaVersion && _box.get(_workoutKey) != null;
  }
}
