import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Conditional import: the web variant subscribes to `window.online` /
// `window.offline` DOM events via `package:web`; the native stub returns
// an empty stream so `package:web` is never linked into native builds.
// Tree-shaking + conditional imports together guarantee the Android/iOS
// bundle has no `package:web` symbols.
import 'web_online_events_io.dart'
    if (dart.library.js_interop) 'web_online_events_web.dart';

// Re-export the platform-conditional provider so callers (and tests) can
// override it without knowing which file resolved during compilation.
export 'web_online_events_io.dart'
    if (dart.library.js_interop) 'web_online_events_web.dart';

/// Stream of connectivity_plus adapter events, debounced to absorb the
/// flapping that real OS-level adapter changes can produce.
///
/// Emits `true` once on subscription with the current adapter state
/// (no debounce on the initial value), then debounces subsequent events
/// at 500ms. Errors are caught and surface an optimistic `true` — the
/// listener path will still pick up future emissions.
///
/// Exposed as a top-level provider so unit tests can override it with
/// a fake stream and assert the merge logic in [onlineStatusProvider]
/// in isolation from `connectivity_plus`'s real platform channel.
final nativeOnlineEventsProvider = Provider<Stream<bool>>((ref) {
  final connectivity = Connectivity();
  final controller = StreamController<bool>.broadcast();
  Timer? debounceTimer;

  bool toOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  // Emit current state immediately (no debounce).
  connectivity
      .checkConnectivity()
      .then((results) {
        if (!controller.isClosed) {
          controller.add(toOnline(results));
        }
      })
      .catchError((Object _) {
        if (!controller.isClosed) controller.add(true);
      });

  // Subsequent changes: 500ms debounce.
  final subscription = connectivity.onConnectivityChanged.listen((results) {
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!controller.isClosed) {
        controller.add(toOnline(results));
      }
    });
  });

  ref.onDispose(() {
    debounceTimer?.cancel();
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Streams the device's online/offline status, merging the native
/// `connectivity_plus` adapter events with the browser's
/// `window.online` / `window.offline` DOM events on Flutter Web.
///
/// Merge semantics: **last-wins**. Whichever source emitted most
/// recently dictates the value. This matches the user's mental model:
/// when the browser fires `offline`, the user IS offline (e.g. a CDP
/// `setOffline(true)` from Playwright, or `navigator.onLine === false`
/// from a captive portal) regardless of what the OS adapter reports.
///
/// On native targets the web source resolves to an empty stream
/// (see `web_online_events_io.dart`) so the merge collapses to
/// `connectivity_plus` alone — preserving Android/iOS behaviour.
///
/// The first value on subscription is whatever the native source emits
/// from its initial `checkConnectivity()` resolution, so the cold-launch
/// drain protocol in `sync_service.dart` (which awaits
/// `onlineStatusProvider.future`) still receives a real boolean and not
/// a synthetic optimistic default.
final onlineStatusProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();

  // `ref.watch` here is deliberate (not a typo for `ref.read`): if either
  // source provider is invalidated, this StreamProvider rebuilds, which
  // re-runs this closure and creates fresh subscriptions on the new source
  // streams. The previous invocation's `ref.onDispose` callback fires and
  // cancels the old subscriptions — so subscriptions are not leaked, but
  // disposal is two-phase (old closure tears down after the new closure
  // starts subscribing) rather than a synchronous swap. Replacing this
  // with `ref.read` would freeze the merge to whichever streams existed
  // on first build and miss subsequent invalidations (e.g. test overrides
  // swapping out the web events source).
  final nativeStream = ref.watch(nativeOnlineEventsProvider);
  final webStream = ref.watch(webOnlineEventsProvider);

  StreamSubscription<bool>? nativeSub;
  StreamSubscription<bool>? webSub;

  void emit(bool value) {
    if (!controller.isClosed) controller.add(value);
  }

  nativeSub = nativeStream.listen(
    emit,
    onError: (Object _, StackTrace _) {
      // Stream-level errors fall back to optimistic-online so the
      // cold-launch drain isn't permanently stalled.
      emit(true);
    },
  );
  webSub = webStream.listen(
    emit,
    onError: (Object _, StackTrace _) {
      // Browser event errors are non-fatal — fall back to whatever the
      // native source last reported. We just don't push a value here.
    },
  );

  ref.onDispose(() {
    nativeSub?.cancel();
    webSub?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Synchronous read of the current online status.
///
/// Defaults to `true` (optimistic) when the stream has not yet emitted.
/// This optimistic default interacts with `sync_service.dart`'s
/// cold-launch drain protocol — see comments at `sync_service.dart:36-46`.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(onlineStatusProvider).value ?? true;
});
