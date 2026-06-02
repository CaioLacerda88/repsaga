import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../core/local_storage/hive_service.dart';
import '../../auth/providers/auth_providers.dart';
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
/// - **Auth-reactive.** The user id is derived from [authStateProvider] (not
///   the synchronous `currentUserIdProvider`). On sign-out → sign-in into a
///   different account, Riverpod observes the userId change and rebuilds the
///   provider — the new user's PRs are seeded; the previous user's per-
///   exercise entries are wiped by the one-shot migration's idempotent
///   re-write contract on next drain. While `authStateProvider` is loading
///   on cold start, the provider returns immediately and waits for the next
///   non-loading emission to seed (avoids deadlocking the shell on auth init).
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
  // Note: this body runs the one-shot Hive migration BEFORE the seed write.
  // Both are side-effects on the prCache box; the migration must complete
  // first so it can never wipe entries we just wrote in the same build.
  //
  // Auth source: we deliberately watch `authStateProvider` instead of
  // `currentUserIdProvider` so a sign-out → sign-in transition naturally
  // re-runs this provider with the new user id. `currentUserIdProvider` is
  // documented as a synchronous, non-reactive read — watching it would not
  // detect auth changes (Riverpod has no way to know its underlying value
  // changed because the provider's body never re-evaluates).
  //
  // We await `authStateProvider.future` rather than reading its synchronous
  // `value` so cold-start (auth stream still loading) waits for the first
  // emission instead of short-circuiting against an `AsyncLoading()`. The
  // shell mounts this provider via a no-op `ref.listen` and never blocks on
  // its future, so waiting here is safe — the only consumers awaiting the
  // future are unit tests and the sync-service reconcile path, both of
  // which want the seed to actually run.
  //
  // `ref.watch(provider.future)` is the canonical Riverpod 2.x pattern for
  // "depend on the latest emission and rebuild on each new emission" — a
  // sign-out → sign-in transition emits a new `AuthState`, the future
  // resolves with the new user, and this provider naturally re-runs.
  final authState = await ref.watch(authStateProvider.future);
  final userId = authState.session?.user.id;
  if (userId == null) {
    // No signed-in user. Returning a resolved future means consumers
    // awaiting `prCacheBootstrapProvider.future` never block on auth — and
    // the next signed-in auth emission rebuilds this provider with the new
    // id (the `ref.watch` above pins the subscription).
    return;
  }

  // One-shot migration: wipe stale prCache entries written by pre-fix code.
  // The flag lives in [HiveService.userPrefs]; if absent we clear the box
  // exactly once, then set the flag so future runs are no-ops.
  await _runOneShotMigrationIfNeeded();

  final repo = ref.read(prRepositoryProvider);
  final locale = ref.read(localeProvider).languageCode;

  try {
    final records = await repo.getRecordsForUser(
      userId: userId,
      locale: locale,
    );
    await repo.seedExerciseCacheEntries(records);
  } catch (e, stack) {
    // Best-effort warmup: a network failure here is recoverable. The
    // read-through cache in `PRRepository` still kicks in on subsequent
    // reads, and a successful drain → invalidation re-runs this provider.
    // Logging via debugPrint so a regression that breaks the warmup is
    // visible in adb logcat / browser dev tools without crashing the shell.
    debugPrint('[PrCacheBootstrap] warmup failed (best-effort): $e\n$stack');
  }
});

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
    debugPrint(
      '[PrCacheBootstrap] userPrefs box is not open — skipping one-shot '
      'prCache migration',
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
      debugPrint(
        '[PrCacheBootstrap] Failed to clear prCache during one-shot '
        'migration: $e',
      );
      // Even if clear failed, set the flag — we only ever want to attempt
      // this wipe once. Honest scope: a leftover stale entry for an
      // exercise still in the user's current PR list will be overwritten
      // by the next seed write; one for an exercise no longer in the
      // user's PR list (e.g. soft-deleted, or a record that was rolled
      // back server-side) will remain until it is naturally evicted by
      // another code path (e.g. `clearAllRecords`, locale switch wipe,
      // or box recovery on corruption).
    }
  }
  await prefs.put(prCacheV2MigratedKey, true);
}
