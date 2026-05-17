import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';
import '../../auth/providers/auth_providers.dart';
import 'earned_titles_provider.dart';

/// Hive `userPrefs` key marking that the one-shot `earned_titles` backfill
/// has run for [userId] on this device. Set to `true` only after the
/// `backfill_earned_titles(uuid)` RPC returns successfully — a failed call
/// (network down, server error) leaves the key absent so the next session
/// retries.
///
/// Format: `'earned_titles_backfilled_v1_<userId>'`. The user id is suffixed
/// so a multi-account device tracks per-user state independently — signing
/// in to a fresh account on a device where another user already ran the
/// backfill must still run it for the new account.
///
/// Colocated with [earnedTitlesBackfillProvider] (rather than parked on
/// [HiveService]) to mirror [prCacheV2MigratedKey], which lives next to
/// the `prCacheBootstrapProvider` it gates. Keeping the key next to its
/// sole consumer is the established pattern for bootstrap flags.
String earnedTitlesBackfilledV1Key(String userId) =>
    'earned_titles_backfilled_v1_$userId';

/// Calls `backfill_earned_titles(p_user_id uuid)` exactly once per
/// (user, device) on first app open after the detection-time INSERT migration
/// shipped. Idempotent across rebuilds (Riverpod caches the future); gated by
/// a per-user Hive flag so the work is skipped on subsequent launches.
///
/// **Why a separate provider instead of bootstrapping inside the existing
/// [earnedTitlesProvider]:** the latter is a SELECT-only read that runs on
/// every Titles screen entry. Backfill is a write-once side-effect; mixing
/// the two would couple every screen-entry to an RPC call. Following the
/// `prCacheBootstrapProvider` precedent keeps the contract clean: this
/// provider is fired-and-forgotten from the shell via `ref.listen`; the
/// SELECT provider's behaviour is unaffected.
///
/// **Auth source.** We deliberately watch [authStateProvider] (not the
/// synchronous, non-reactive [currentUserIdProvider]) so a sign-out → sign-in
/// transition naturally re-runs this provider with the new user id. The
/// per-user Hive flag (`earnedTitlesBackfilledV1Key(userId)`) ensures the
/// new account gets its own one-shot run regardless of whether the device
/// already ran it for a previous account. `ref.watch(provider.future)` is
/// the canonical Riverpod 2.x pattern for "depend on the latest emission and
/// rebuild on each new emission" — same shape as `prCacheBootstrapProvider`.
///
/// **Failure semantics.** RPC errors are caught, logged at warning level,
/// and SWALLOWED. The Hive flag is NOT set on failure, so the next app open
/// retries. This matches `prCacheBootstrapProvider` — a missed backfill is
/// recoverable on the next launch, while throwing here would crash the shell.
///
/// **Server-side idempotency.** The `backfill_earned_titles` RPC's INSERTs
/// use `ON CONFLICT DO NOTHING`, so even without the per-(user, device)
/// flag, re-running the RPC is safe — the flag is a client-side cost
/// optimisation (skip a no-op network round-trip), not a correctness gate.
final earnedTitlesBackfillProvider = FutureProvider<void>((ref) async {
  // Await `authStateProvider.future` rather than reading `.value` so cold
  // start (auth stream still loading) waits for the first emission instead
  // of short-circuiting against an `AsyncLoading()`. The shell mounts this
  // provider via a no-op `ref.listen` and never blocks on its future.
  final authState = await ref.watch(authStateProvider.future);
  final userId = authState.session?.user.id;
  if (userId == null) {
    // No signed-in user. Returning a resolved future means any consumer
    // awaiting `earnedTitlesBackfillProvider.future` never blocks on auth —
    // and the next signed-in auth emission rebuilds this provider with
    // the new id (the `ref.watch` above pins the subscription).
    return;
  }

  if (!Hive.isBoxOpen(HiveService.userPrefs)) {
    developer.log(
      'userPrefs box is not open — skipping earned_titles backfill',
      name: 'EarnedTitlesBackfill',
    );
    return;
  }

  final prefs = Hive.box<dynamic>(HiveService.userPrefs);
  final key = earnedTitlesBackfilledV1Key(userId);
  if (prefs.get(key) == true) return;

  final repo = ref.read(titlesRepositoryProvider);
  try {
    await repo.backfillEarnedTitles(userId);
    await prefs.put(key, true);
    // Invalidate so the Titles screen and the celebration overlay's
    // already-earned-slugs computation pick up the backfilled rows on the
    // next read. Without this, a session that ran the backfill would still
    // serve the pre-backfill SELECT result until manually refreshed.
    ref.invalidate(earnedTitlesProvider);
  } catch (e, stack) {
    // Best-effort: a network failure here is recoverable. The flag stays
    // unset so the next session retries. Logging at level 900 (warning) so
    // a regression that breaks the backfill is visible in adb logcat /
    // browser dev tools without crashing the shell.
    developer.log(
      'backfill_earned_titles failed (best-effort, will retry next session): $e',
      name: 'EarnedTitlesBackfill',
      level: 900,
      error: e,
      stackTrace: stack,
    );
  }
});
