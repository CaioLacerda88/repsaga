import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/rpg_progress_provider.dart';
import 'saga_intro_overlay.dart';

// ---------------------------------------------------------------------------
// BUG-012 (Cluster 3) — saga-intro / celebration sequencing
// ---------------------------------------------------------------------------
//
// Pre-Cluster-3 the saga intro overlay and post-workout celebration
// overlays could collide on the same frame: the intro renders over the
// shell via [SagaIntroGate]'s Stack, while celebrations come up via
// `showDialog` on the root navigator (which paints ABOVE the intro
// Stack). A first workout that produced a rank-up would show both at
// once with the celebration on top, hiding the intro.
//
// **Sequencing contract (locked, PO call 2026-05-02):**
//   1. Saga intro ALWAYS plays first when it would otherwise show.
//   2. Celebration queue drains AFTER the intro dismisses.
//   3. 200ms gap between intro dismissal and the first celebration so
//      the eye doesn't get a hard cut.
//   4. NO event suppression — the intro never absorbs rank-up events.
//
// Implementation: a singleton sequencer keyed by user ID. The gate
// completes the per-user [Completer] on dismiss; the celebration screen
// awaits the future before invoking [`CelebrationPlayer.play`]. If the
// intro is already dismissed (Hive flag set), the future resolves
// immediately — same code path, no special "first-launch" branch.
//
// **Why a global singleton instead of a Riverpod provider:** the
// completer must outlive provider invalidations (the gate could be
// rebuilt mid-await, e.g. on hot reload, without breaking the sequence).
// A static map keyed by userId gives that lifetime without coupling to
// Riverpod's container lifecycle.
class SagaIntroSequencer {
  const SagaIntroSequencer._();

  /// Per-user completer. Lazily created on first read; completed once
  /// either the gate fires [markIntroDismissedForSequencer] OR the gate
  /// detects the Hive `saga_intro_seen` flag was already set on mount
  /// (existing user — intro never showed for them).
  // TODO(multi-account): entries persist for the app-process lifetime; GC'd
  // only on process kill. Fine for single-account use; a future multi-account
  // flow should clear the map (or per-user entries) on sign-out.
  static final Map<String, Completer<void>> _completersByUser = {};

  /// Completer for [userId]. Returns a fresh completer the first time;
  /// subsequent calls return the same one (so multiple awaiters share
  /// the same fate).
  static Completer<void> _completerFor(String userId) {
    return _completersByUser.putIfAbsent(userId, Completer<void>.new);
  }

  /// Future that resolves when the saga intro is no longer in the way
  /// for [userId] — either after dismissal this session OR immediately
  /// if the gate determined the intro was already seen on a prior run.
  static Future<void> waitForIntroDismissed(String userId) {
    return _completerFor(userId).future;
  }

  /// Mark the intro as no longer blocking for [userId]. Called by the
  /// gate from two paths:
  ///   * On mount when `hasSeenSagaIntroForUser(userId)` already returns
  ///     true (the intro never showed — celebrations can fire right away).
  ///   * On user-dismiss (final BEGIN tap or Skip).
  /// Idempotent — only the first call resolves the completer; later
  /// calls are no-ops.
  static void markIntroDismissedForSequencer(String userId) {
    final c = _completerFor(userId);
    if (!c.isCompleted) c.complete();
  }

  /// Reset the completer for [userId] — only used by tests so each test
  /// gets a fresh state. Production code never calls this; the gate
  /// determines when to complete on its own per session.
  @visibleForTesting
  static void resetForTesting() {
    _completersByUser.clear();
  }
}

/// First-launch gate that wraps the authenticated shell and, per user:
///
///   1. Triggers the retroactive RPG backfill exactly once
///      (`backfill_rpg_v1`, idempotent on the server; the Hive flag avoids
///      the round-trip on subsequent launches).
///   2. Renders [SagaIntroOverlay] over [child] when the backfill has
///      completed and the user has not yet dismissed the intro.
///   3. Records dismissal to Hive so the overlay never re-appears.
///
/// The child renders immediately — retro runs asynchronously and the overlay
/// only paints once `rpgProgressProvider` resolves to real data. A per-session
/// guard prevents the overlay from re-mounting after dismissal in the same
/// session (the Hive write is asynchronous; the in-memory flag closes the
/// race).
///
/// **Phase 18-followups rewire (2026-04-29):** the gate previously read
/// from the legacy gamification `xpProvider` and kicked
/// `XpRepository.runRetroBackfill`. Both pointed at the same server-side
/// `backfill_rpg_v1` procedure as `RpgRepository.runBackfill`, so this is
/// a pure consumer-side rewire — the canonical RPG signal
/// (`character_state` view) drives gating + step-3 preview, the gamification
/// dir is gone.
class SagaIntroGate extends ConsumerStatefulWidget {
  const SagaIntroGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SagaIntroGate> createState() => _SagaIntroGateState();
}

class _SagaIntroGateState extends ConsumerState<SagaIntroGate> {
  bool _retroKicked = false;
  bool _dismissedThisSession = false;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return widget.child;

    _maybeKickRetro(userId);

    final snapshotAsync = ref.watch(rpgProgressProvider);
    final retroDone = hasRunRetroForUser(userId);
    final alreadySeen = hasSeenSagaIntroForUser(userId);

    // BUG-012 sequencer: complete the per-user "intro is done" Future as
    // soon as we know the intro will NOT be shown for this user. Two
    // cases:
    //   * Already dismissed in a previous session (Hive flag set).
    //   * Dismissed earlier this session (state flag set).
    // The completer is idempotent — duplicate completions are no-ops.
    if (alreadySeen || _dismissedThisSession) {
      SagaIntroSequencer.markIntroDismissedForSequencer(userId);
    }

    final shouldShow =
        !_dismissedThisSession &&
        !alreadySeen &&
        retroDone &&
        snapshotAsync is AsyncData;

    if (!shouldShow) return widget.child;

    final l10n = AppLocalizations.of(context);
    final snapshot = snapshotAsync.value!;
    final level = snapshot.characterState.characterLevel;
    final rankSlug = rankSlugFromLifetimeXp(snapshot.characterState.lifetimeXp);
    final rankLabel = _localizeRankSlug(l10n, rankSlug);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        SagaIntroOverlay(
          startingLevel: level,
          rankLabel: rankLabel,
          onDismiss: () => _dismiss(userId),
        ),
      ],
    );
  }

  void _maybeKickRetro(String userId) {
    if (_retroKicked) return;
    if (hasRunRetroForUser(userId)) {
      _retroKicked = true;
      return;
    }
    _retroKicked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Retro is safe to retry next launch (server is idempotent); swallow
      // errors to avoid blocking the home render on a transient network
      // failure.
      _runBackfill(userId).catchError((Object _) {});
    });
  }

  Future<void> _runBackfill(String userId) async {
    await ref.read(rpgRepositoryProvider).runBackfill();
    await markRetroCompleteForUser(userId);
    ref.invalidate(rpgProgressProvider);
  }

  void _dismiss(String userId) {
    // In-memory flag closes the race so the overlay can't re-mount while
    // the Hive write is in flight; the unawaited persist is durable once
    // flush() lands in markSagaIntroSeenForUser.
    setState(() => _dismissedThisSession = true);
    unawaited(markSagaIntroSeenForUser(userId));
    // BUG-012: release any awaiters in the celebration orchestrator now
    // that the intro has fully dismissed.
    SagaIntroSequencer.markIntroDismissedForSequencer(userId);
  }
}

// ---------------------------------------------------------------------------
// Local-only "has retro run?" + "has seen intro?" flags
// ---------------------------------------------------------------------------
//
// Used by the gate to drive `backfill_rpg_v1` once per user per device.
// `backfill_rpg_v1` is a chunked function looped from
// `RpgRepository.runBackfill` until `out_is_complete=true`. The server-side
// `backfill_progress.completed_at` checkpoint is the source of truth for
// correctness (a re-run on a completed user is a no-op); these flags exist
// only to avoid the cold-start round-trip and to remember dismissal across
// launches.
//
// **Key prefixes preserved from the legacy gamification feature** so
// existing users who already saw the intro pre-rewire don't see it again
// after the deletion.

const String _kRetroKeyPrefix = 'saga_retro_run:';
const String _kSagaIntroSeenPrefix = 'saga_intro_seen:';

/// Whether the retroactive backfill has already been triggered for [userId]
/// from this device.
bool hasRunRetroForUser(String userId) {
  final box = Hive.box<dynamic>(HiveService.userPrefs);
  return (box.get('$_kRetroKeyPrefix$userId') as bool?) ?? false;
}

/// Mark the retro backfill as completed for [userId]. The server is
/// idempotent regardless; this flag is purely a cold-start latency
/// optimization.
///
/// `box.flush()` mirrors [markSagaIntroSeenForUser] for IndexedDB durability
/// on Flutter Web. The server is idempotent so a missed flush is recoverable
/// (re-running `backfill_rpg_v1` is a no-op), but the parity keeps the two
/// per-user gate writes structurally identical and avoids a misleading
/// inconsistency for future maintainers.
Future<void> markRetroCompleteForUser(String userId) async {
  final box = Hive.box<dynamic>(HiveService.userPrefs);
  await box.put('$_kRetroKeyPrefix$userId', true);
  await box.flush();
}

/// Whether the first-run [SagaIntroOverlay] has been dismissed for [userId].
bool hasSeenSagaIntroForUser(String userId) {
  final box = Hive.box<dynamic>(HiveService.userPrefs);
  return (box.get('$_kSagaIntroSeenPrefix$userId') as bool?) ?? false;
}

/// Persist that [userId] has dismissed the saga intro overlay.
///
/// `box.put` awaits the IndexedDB write (on Flutter Web) but the browser
/// can race a page-reload against the transaction. `box.flush()` forces the
/// write to complete before returning, ensuring the flag survives an
/// immediate restart (e.g., explicit page.reload in E2E tests or a rapid
/// app restart on mobile after tapping BEGIN).
Future<void> markSagaIntroSeenForUser(String userId) async {
  final box = Hive.box<dynamic>(HiveService.userPrefs);
  await box.put('$_kSagaIntroSeenPrefix$userId', true);
  await box.flush();
}

// ---------------------------------------------------------------------------
// Lifetime XP → rank slug + localized label
// ---------------------------------------------------------------------------
//
// The Phase 17b coarse rank ladder (rookie → diamond) is a UI-only
// progression signal separate from the per-body-part rank curve. It exists
// so the saga intro overlay's "LVL N — RANK" preview reflects the lifter's
// current state rather than always rendering "LVL 1 — ROOKIE" for users with
// real history. After deleting the gamification feature, the thresholds and
// localization keys live here — the only consumer is the intro overlay.
//
// Threshold table (locked, mirrors PROJECT.md §17b):
//   * 250_000    → DIAMOND
//   * 125_000    → PLATINUM
//   *  60_000    → GOLD
//   *  25_000    → SILVER
//   *  10_000    → COPPER
//   *   2_500    → IRON
//   *       0    → ROOKIE
//
// The ladder is stored as a `List` of `(minXp, slug)` records sorted
// **descending by `minXp`** so a single forward walk finds the first match.
// Earlier revisions used a `Map<String, double>` and called
// `.entries.toList().reversed` per lookup — correct, but it allocated a
// throwaway list on every overlay rebuild and obscured intent. The list
// shape makes ordering structural (not derived) and the lookup zero-alloc.

const List<({double minXp, String slug})> _rpgIntroRankLadder = [
  (minXp: 250000, slug: 'diamond'),
  (minXp: 125000, slug: 'platinum'),
  (minXp: 60000, slug: 'gold'),
  (minXp: 25000, slug: 'silver'),
  (minXp: 10000, slug: 'copper'),
  (minXp: 2500, slug: 'iron'),
  (minXp: 0, slug: 'rookie'),
];

/// Resolve a rank slug from `character_state.lifetime_xp` against the
/// Phase 17b coarse ladder.
///
/// Walks [_rpgIntroRankLadder] top-down (descending `minXp`) and returns the
/// first slug whose threshold the lifter has crossed. With a `0` floor entry
/// (`rookie`), every non-negative XP matches; the final-fallback return on
/// the last entry's slug guards against an empty ladder + negative XP and
/// keeps the function total.
///
/// Public + `@visibleForTesting` so the unit suite can pin threshold edges
/// without spinning up a localized widget tree.
@visibleForTesting
String rankSlugFromLifetimeXp(double lifetimeXp) {
  for (final entry in _rpgIntroRankLadder) {
    if (lifetimeXp >= entry.minXp) return entry.slug;
  }
  return _rpgIntroRankLadder.last.slug;
}

/// Map a rank [slug] (from [rankSlugFromLifetimeXp]) to its localized label
/// via the bundled `sagaRank*` ARB keys. Unknown slugs fall back to ROOKIE
/// — the ladder is closed, so this is defensive only.
String _localizeRankSlug(AppLocalizations l10n, String slug) {
  return switch (slug) {
    'diamond' => l10n.sagaRankDiamond,
    'platinum' => l10n.sagaRankPlatinum,
    'gold' => l10n.sagaRankGold,
    'silver' => l10n.sagaRankSilver,
    'copper' => l10n.sagaRankCopper,
    'iron' => l10n.sagaRankIron,
    'rookie' => l10n.sagaRankRookie,
    _ => l10n.sagaRankRookie,
  };
}
