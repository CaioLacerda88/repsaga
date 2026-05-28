import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../local_storage/hive_service.dart';
import '../observability/sentry_report.dart';
import 'pending_action.dart';

/// Reads and writes [PendingAction] items to the `offline_queue` Hive box.
///
/// Each action is stored as a JSON string keyed by its `id`. The box is
/// opened during [HiveService.init], so callers must ensure init has
/// completed before accessing this service.
///
/// **BUG-007 contract:** `enqueue`, `dequeue`, and `updateAction` rethrow
/// on Hive failures so callers can surface the issue (without rethrow, a
/// failed enqueue silently loses user data; a failed dequeue causes
/// duplicate replays; a failed updateAction makes retry counters
/// non-monotonic). All catch sites capture to Sentry so production failure
/// rates are visible. `getAll` keeps its skip-corrupt behavior — one bad
/// row must not block the entire queue — but also captures so we see
/// corruption rates.
class OfflineQueueService {
  const OfflineQueueService();

  Box<dynamic> get _box => Hive.box<dynamic>(HiveService.offlineQueue);

  /// Persist a [PendingAction] to the queue.
  ///
  /// Rethrows on Hive failure so callers (typically a notifier in a
  /// `try/catch`) can react. The caller is expected to surface the failure
  /// to the user — losing a queued action silently is the worst outcome.
  Future<void> enqueue(PendingAction action) async {
    try {
      final json = jsonEncode(action.toJson());
      await _box.put(action.id, json);
    } catch (e, st) {
      debugPrint(
        '[OfflineQueueService] Failed to enqueue action ${action.id}: $e',
      );
      unawaited(SentryReport.captureException(e, stackTrace: st));
      rethrow;
    }
  }

  /// Remove a queued action by [id].
  ///
  /// Rethrows on Hive failure so callers can avoid double-dequeue or
  /// duplicate replay scenarios.
  Future<void> dequeue(String id) async {
    try {
      await _box.delete(id);
    } catch (e, st) {
      debugPrint('[OfflineQueueService] Failed to dequeue action $id: $e');
      unawaited(SentryReport.captureException(e, stackTrace: st));
      rethrow;
    }
  }

  /// Read all queued actions, sorted by [PendingAction.queuedAt] ascending.
  ///
  /// Corrupt entries are silently skipped so one bad row cannot block the
  /// entire queue (a single malformed JSON would otherwise stall every
  /// drain). Each skip captures to Sentry so we get production rates on
  /// corruption — historically this masked BUG-001 because the corrupt
  /// entry would loop forever without anyone noticing.
  List<PendingAction> getAll() {
    final actions = <PendingAction>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is! String) continue;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        actions.add(PendingAction.fromJson(decoded));
      } catch (e, st) {
        debugPrint(
          '[OfflineQueueService] Skipping corrupt queue entry "$key": $e',
        );
        unawaited(SentryReport.captureException(e, stackTrace: st));
      }
    }
    actions.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return actions;
  }

  /// Overwrite an existing entry (e.g. to update retryCount / lastError).
  ///
  /// Rethrows on Hive failure so a non-monotonic retry counter (caused by
  /// a silently-swallowed update) doesn't make queued items retry forever
  /// past [SyncService.kMaxSyncRetries].
  Future<void> updateAction(PendingAction action) async {
    try {
      final json = jsonEncode(action.toJson());
      await _box.put(action.id, json);
    } catch (e, st) {
      debugPrint(
        '[OfflineQueueService] Failed to update action ${action.id}: $e',
      );
      unawaited(SentryReport.captureException(e, stackTrace: st));
      rethrow;
    }
  }

  /// Number of items currently in the queue.
  ///
  /// Assumes the box is used exclusively for [PendingAction] JSON strings.
  int get pendingCount => _box.length;

  /// One-shot purge for legacy queue entries whose `kind` discriminator was
  /// removed from the [PendingAction] sealed union.
  ///
  /// At time of writing the only such variant is the retired
  /// `createExercise` kind (Phase 32 PR 32h retired the user-create-exercise
  /// surface entirely). Without this purge, a legacy Hive row from a pre-PR
  /// build would either:
  ///   - throw on [PendingAction.fromJson] because the `type` discriminator
  ///     is unknown to the post-deletion union (Freezed throws on missing
  ///     union key match), OR
  ///   - get silently skipped by [getAll]'s corrupt-row guard but leak
  ///     pendingCount and Sentry breadcrumbs forever.
  ///
  /// String-matches on the raw JSON before deserialization so the purge
  /// itself can't trip the same union-key exhaustiveness it's defending
  /// against. Pre-launch we have no live users — this is cheap insurance
  /// for local-dev Hive boxes that may have queued entries from a pre-PR
  /// build.
  ///
  /// Idempotent and safe to call multiple times: the second call finds no
  /// matching rows and no-ops. Wrapped in try/catch so a corrupt blob can't
  /// break the calling service's init path.
  ///
  /// Returns the number of legacy entries that were dropped.
  ///
  /// Async because [BoxBase.delete] returns `Future<void>` — the disk write
  /// must resolve BEFORE the next [getAll] is called or the legacy entry is
  /// still readable and [PendingAction.fromJson] throws on the unknown union
  /// key. Callers running during cold-launch init MUST `await` this. See
  /// [SyncService._coldLaunchDrain] for the canonical wiring.
  Future<int> purgeRetiredKinds() async {
    var dropped = 0;
    try {
      // Snapshot keys first — modifying the box during iteration is unsafe.
      final keys = _box.keys.toList();
      for (final key in keys) {
        try {
          final raw = _box.get(key);
          if (raw is! String) continue;
          // Cheap pre-check: most entries won't match. The full JSON parse
          // only runs on hits so we don't waste cycles on healthy queues.
          if (!raw.contains('"createExercise"')) continue;
          final decoded = jsonDecode(raw);
          if (decoded is! Map) continue;
          if (decoded['type'] == 'createExercise') {
            await _box.delete(key);
            dropped++;
            debugPrint(
              '[OfflineQueueService] Purged legacy queue entry "$key" '
              '(retired kind: createExercise)',
            );
          }
        } catch (e, st) {
          // Malformed row — mirror getAll's pattern: log locally + capture
          // to Sentry so we get production rates on corruption that the
          // sweep couldn't process. Leaves the row in place for getAll's
          // corrupt-row guard to surface again on the next read.
          debugPrint(
            '[OfflineQueueService] purgeRetiredKinds: skipping unparseable '
            'entry "$key": $e',
          );
          unawaited(SentryReport.captureException(e, stackTrace: st));
        }
      }
    } catch (e) {
      // Box-level failure (closed / missing). Safe to swallow — the purge
      // is best-effort defensive cleanup; the calling service still works
      // if no purge ever runs.
      debugPrint(
        '[OfflineQueueService] purgeRetiredKinds: box read failed: $e',
      );
    }
    return dropped;
  }
}

/// Provides an [OfflineQueueService] instance via Riverpod.
final offlineQueueServiceProvider = Provider<OfflineQueueService>((ref) {
  return const OfflineQueueService();
});
