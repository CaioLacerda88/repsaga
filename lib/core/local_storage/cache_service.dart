import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Generic cache service for reading/writing JSON to Hive boxes.
///
/// All operations are safe: they log errors and never throw. This makes
/// the cache layer a best-effort fallback that cannot crash the app.
class CacheService {
  const CacheService();

  /// Reads a value from [boxName] at [key], deserializing via [fromJson].
  ///
  /// Returns `null` when the key is missing, the box is not open,
  /// or the stored JSON is corrupt.
  T? read<T>(String boxName, String key, T Function(dynamic) fromJson) {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        debugPrint(
          '[CacheService] Box "$boxName" is not open — returning null for key "$key"',
        );
        return null;
      }
      final raw = Hive.box<dynamic>(boxName).get(key);
      if (raw == null) return null;
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      return fromJson(decoded);
    } catch (e, st) {
      debugPrint(
        '[CacheService] Failed to read "$key" from "$boxName": $e\n$st',
      );
      return null;
    }
  }

  /// Writes [value] as a JSON string to [boxName] at [key].
  ///
  /// Logs errors but never throws.
  Future<void> write(String boxName, String key, dynamic value) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        debugPrint(
          '[CacheService] Box "$boxName" is not open — skipping write for key "$key"',
        );
        return;
      }
      final encoded = jsonEncode(value);
      await Hive.box<dynamic>(boxName).put(key, encoded);
    } catch (e, st) {
      debugPrint(
        '[CacheService] Failed to write "$key" to "$boxName": $e\n$st',
      );
    }
  }

  /// Deletes [key] from [boxName].
  ///
  /// Logs errors but never throws.
  Future<void> delete(String boxName, String key) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        debugPrint(
          '[CacheService] Box "$boxName" is not open — skipping delete for key "$key"',
        );
        return;
      }
      await Hive.box<dynamic>(boxName).delete(key);
    } catch (e, st) {
      debugPrint(
        '[CacheService] Failed to delete "$key" from "$boxName": $e\n$st',
      );
    }
  }

  /// Clears all entries in [boxName].
  ///
  /// Logs errors but never throws.
  Future<void> clearBox(String boxName) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        debugPrint(
          '[CacheService] Box "$boxName" is not open — skipping clearBox',
        );
        return;
      }
      await Hive.box<dynamic>(boxName).clear();
    } catch (e, st) {
      debugPrint('[CacheService] Failed to clear box "$boxName": $e\n$st');
    }
  }
}

/// Provides a [CacheService] instance via Riverpod.
final cacheServiceProvider = Provider<CacheService>((ref) {
  return const CacheService();
});
