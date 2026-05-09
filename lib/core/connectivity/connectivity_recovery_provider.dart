import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/sync_error_classifier.dart';

/// How long a recorded network-class failure stays "recent". After this
/// window elapses, success is no longer interpreted as recovery.
const _kFailureWindow = Duration(minutes: 5);

/// Minimum gap between two recovery-signal triggers from this notifier.
/// Other drain paths ([SyncService] connectivity-listener, cold-launch)
/// have their own reentrancy guards and do NOT route through this cooldown.
const _kRecoveryCooldown = Duration(seconds: 5);

/// Tracks recent network-class failures and emits a monotonically-increasing
/// "tick" whenever a repository success likely indicates the network has
/// recovered.
///
/// `SyncService` listens to this provider; each tick triggers `_drain()`
/// (subject to its existing `_draining` guard).
///
/// **Why a counter instead of a stream:** a `Notifier<int>` integrates
/// cleanly with `ref.listen` semantics — every state change fires the
/// listener regardless of debounced equality. It's testable without async
/// setup (no `StreamController`, no microtask pumping) and the value itself
/// (`state`) doubles as a debug breadcrumb (n triggers since startup).
///
/// **Domain errors are NOT failures.** A 4xx response means the server was
/// reachable enough to return a structured payload — the network was fine.
/// Recording such an error would falsely arm the recovery signal and cause
/// the next successful unrelated call to trigger a drain. Only network-class
/// errors (transport, timeout, 5xx, auth-refresh) feed [recordFailure].
///
/// **Suppression during drain.** `SyncService._drain` calls
/// [setRecordingSuppressed] for the duration of its loop so the drain's own
/// repository requests don't feed back into this recorder. Without this
/// suppression, a transient drain failure -> drain success could ping-pong
/// the tick counter and burn through the cooldown.
class ConnectivityRecoveryNotifier extends Notifier<int> {
  /// Timestamp of the most recent network-class failure, or `null` if either
  /// no failure has been recorded or the previous one was already consumed.
  DateTime? _lastFailure;

  /// Timestamp of the most recent emitted tick. Drives the [_kRecoveryCooldown]
  /// gate so back-to-back successes don't stampede.
  DateTime? _lastTrigger;

  /// While `true`, [recordFailure] / [recordSuccess] are no-ops. Used by
  /// `SyncService` to suppress feedback from its own drain loop.
  bool _recordingSuppressed = false;

  @override
  int build() => 0;

  /// Mark the recording side as suppressed (or restore it). Idempotent.
  void setRecordingSuppressed(bool suppressed) {
    _recordingSuppressed = suppressed;
  }

  /// Record a repository failure. No-op for non-network-class errors and
  /// while suppression is active.
  void recordFailure(Object error) {
    if (_recordingSuppressed) return;
    if (!SyncErrorClassifier.isNetworkClass(error)) return;
    _lastFailure = clock.now();
  }

  /// Record a repository success. Increments [state] (firing listeners) iff
  /// (a) suppression is off, (b) a recent network-class failure exists
  /// inside the [_kFailureWindow], and (c) the [_kRecoveryCooldown] has
  /// elapsed since the last trigger.
  ///
  /// On a successful trigger the recorded failure is consumed (`_lastFailure
  /// = null`) so a single failure cannot re-trigger across multiple
  /// successes — the window must be re-armed by another failure first.
  void recordSuccess() {
    if (_recordingSuppressed) return;

    final lastFailure = _lastFailure;
    if (lastFailure == null) return;

    final now = clock.now();
    if (now.difference(lastFailure) > _kFailureWindow) {
      // Stale — forget it. Avoids resurrecting recovery signals from old
      // offline sessions.
      _lastFailure = null;
      return;
    }

    final lastTrigger = _lastTrigger;
    if (lastTrigger != null &&
        now.difference(lastTrigger) < _kRecoveryCooldown) {
      // Within cooldown — drop without consuming the failure so a later
      // success past the cooldown can still fire.
      return;
    }

    _lastTrigger = now;
    _lastFailure = null;
    state = state + 1;
  }
}

/// Provides the [ConnectivityRecoveryNotifier]. Watch the int state to
/// react to recovery signals — each value change is one trigger.
final connectivityRecoveryProvider =
    NotifierProvider<ConnectivityRecoveryNotifier, int>(
      ConnectivityRecoveryNotifier.new,
    );
