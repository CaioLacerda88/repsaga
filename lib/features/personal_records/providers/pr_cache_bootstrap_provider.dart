import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../core/local_storage/cache_service.dart';
import '../../../core/local_storage/hive_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/personal_record.dart';
import 'pr_providers.dart';

/// Hive `userPrefs` key that records whether the one-shot stale-prCache
/// migration has run on this device. Set to `true` after the first successful
/// bootstrap; never re-set to `false`.
///
/// **Why this exists.** Before AW-EX-D-US1-01 was fixed, the prCache box could
/// hold polluted multi-id subset entries (e.g. a workout where the in-session
/// detector falsely awarded a PR). Those stale entries would otherwise leak
/// into the post-fix bootstrap path. We wipe the box exactly once on first
/// post-fix launch, then trust the bootstrap to keep the cache fresh.
const String prCacheV2MigratedKey = 'pr_cache_v2_migrated';

/// Eagerly seeds [HiveService.prCache] with the signed-in user's PR records
/// so the in-session PR-display resolver and the finish-workout PR detector
/// have a correct baseline to compare against from the moment the shell
/// mounts — never against an empty cache.
///
/// **Root cause this provider fixes (AW-EX-D-US1-01, BLOCKER).** Previously
/// the prCache only filled lazily on the first call to
/// `PRRepository.getRecordsForExercises()` inside `finishWorkout`. On a fresh
/// session with no warmup, `exercisePRsProvider(id)` initially returned an
/// empty list (loading), and the row resolver projected the very first
/// completed working set as a "new PR" — even when the underlying historical
/// record clearly beat it.
///
/// **Contract.**
/// - On first build: fetch all of the user's PRs via
///   [PRRepository.getRecordsForUser] (one round trip), then write per-
///   exercise-id cache entries via [PRRepository.seedExerciseCacheEntries].
///   The keys produced match the shape `getRecordsForExercises([id])` writes
///   to, so downstream consumers hit the cache directly.
/// - Idempotent across rebuilds: Riverpod caches the FutureProvider result;
///   subsequent reads do not refetch unless the provider is invalidated.
/// - `ref.invalidate(prCacheBootstrapProvider)` triggers a re-seed. This is
///   the canonical way to re-sync after server-side PR truth changes (used by
///   `SyncService._reconcilePrCache` post successful upsertRecords drain).
/// - Auth-aware: when no user is signed in, the provider returns immediately
///   without making network calls. Sign-in transitions invalidate the
///   provider via the auth path so a fresh user always sees their own PRs.
/// - Best-effort: a failed warmup (network down, server error) does NOT
///   throw. The existing read-through caching in
///   [PRRepository.getRecordsForExercises] still serves subsequent reads;
///   the bootstrap simply skipped the eager-seed optimisation this session.
///
/// **One-shot Hive migration.** On first run after this provider ships, the
/// existing prCache may contain polluted entries written under the old buggy
/// detector. The first build wipes the box once and persists a flag in
/// [HiveService.userPrefs] so the wipe never repeats.
final prCacheBootstrapProvider = FutureProvider<void>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    // No signed-in user — bootstrap has nothing to seed. Returning a
    // resolved future means consumers awaiting `prCacheBootstrapProvider.future`
    // never block on auth.
    return;
  }

  // One-shot migration: wipe stale prCache entries written by pre-fix code.
  // The flag lives in [HiveService.userPrefs]; if absent we clear the box
  // exactly once, then set the flag so future runs are no-ops.
  await _runOneShotMigrationIfNeeded();

  final repo = ref.read(prRepositoryProvider);
  final cache = ref.read(cacheServiceProvider);
  final locale = ref.read(localeProvider).languageCode;

  try {
    final records = await repo.getRecordsForUser(
      userId: userId,
      locale: locale,
    );
    await _seedPerExerciseEntries(cache, records);
  } catch (e, stack) {
    // Best-effort warmup: a network failure here is recoverable. The
    // read-through cache in `PRRepository` still kicks in on subsequent
    // reads, and a successful drain → invalidation re-runs this provider.
    // Logging at level 900 (warning) so a regression that breaks the
    // warmup is visible in adb logcat / browser dev tools without crashing
    // the shell.
    developer.log(
      'prCacheBootstrap warmup failed (best-effort): $e',
      name: 'PRCacheBootstrap',
      level: 900,
      error: e,
      stackTrace: stack,
    );
  }
});

/// Group records by `exerciseId` and write one cache entry per exercise
/// under the canonical `'exercises:<id>'` key shape that
/// [PRRepository.getRecordsForExercises] reads on its per-exercise fallback
/// path.
///
/// Idempotent — overwrites existing entries. Empty input is a no-op.
///
/// Why this lives here rather than on `PRRepository`: the bootstrap depends
/// only on a `CacheService` and the records it just fetched, so keeping the
/// write helper in this file lets unit tests verify the seeding contract by
/// mocking the repository's `getRecordsForUser` and observing real writes
/// to the underlying box. Routing the writes through the repository would
/// require a partial-mock pattern that mocktail doesn't support cleanly.
Future<void> _seedPerExerciseEntries(
  CacheService cache,
  List<PersonalRecord> records,
) async {
  if (records.isEmpty) return;

  final byExerciseId = <String, List<PersonalRecord>>{};
  for (final record in records) {
    (byExerciseId[record.exerciseId] ??= []).add(record);
  }

  for (final entry in byExerciseId.entries) {
    await cache.write(HiveService.prCache, 'exercises:${entry.key}', {
      entry.key: entry.value.map((r) => r.toJson()).toList(),
    });
  }
}

/// One-shot wipe of pre-fix polluted entries in [HiveService.prCache].
///
/// Returns immediately if the [prCacheV2MigratedKey] flag is already set.
/// Otherwise clears the prCache box once, then sets the flag so the wipe
/// never repeats.
///
/// Safe to call multiple times: the flag check makes this idempotent.
/// Tolerates a closed box gracefully (logs and returns) — the bootstrap
/// path runs after [HiveService.init] in production, so the boxes are
/// expected to be open, but a test harness that hasn't opened them must
/// not crash.
Future<void> _runOneShotMigrationIfNeeded() async {
  if (!Hive.isBoxOpen(HiveService.userPrefs)) {
    developer.log(
      'userPrefs box is not open — skipping one-shot prCache migration',
      name: 'PRCacheBootstrap',
    );
    return;
  }
  final prefs = Hive.box<dynamic>(HiveService.userPrefs);
  final alreadyMigrated = prefs.get(prCacheV2MigratedKey) == true;
  if (alreadyMigrated) return;

  if (Hive.isBoxOpen(HiveService.prCache)) {
    try {
      await Hive.box<dynamic>(HiveService.prCache).clear();
    } catch (e) {
      developer.log(
        'Failed to clear prCache during one-shot migration: $e',
        name: 'PRCacheBootstrap',
        level: 900,
      );
      // Even if clear failed, set the flag — we only ever want to attempt
      // this wipe once. A leftover stale entry will be overwritten on the
      // next per-exercise seed write.
    }
  }
  await prefs.put(prCacheV2MigratedKey, true);
}
