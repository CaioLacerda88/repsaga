import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the browser online/offline event source.
///
/// Subscribes to the browser's `window.online` and `window.offline` DOM
/// events — the only signal that fires when:
///   * Chrome DevTools / CDP toggles network state (Playwright
///     `context.setOffline(true)`).
///   * The user's browser tab loses connectivity at the application
///     layer (e.g. `navigator.onLine` flips false) without the OS
///     adapter changing.
///
/// `connectivity_plus`'s `onConnectivityChanged` does NOT see these
/// transitions on web — only OS-level adapter events. Without this
/// stream, the [OfflineBanner] never fires under CDP-driven offline.
///
/// Selected by the conditional import in `connectivity_provider.dart`
/// when `dart.library.js_interop` is available (Flutter Web build).
final webOnlineEventsProvider = Provider<Stream<bool>>((ref) {
  final controller = StreamController<bool>.broadcast();

  // No debounce on browser events: the spec
  // (`tasks/active-workout-implementation-plan.md` §329) calls out that
  // Chrome fires online/offline immediately on real disconnect — no
  // flapping to absorb. Pipe events straight through.
  final onlineSub = web.EventStreamProviders.onlineEvent
      .forTarget(web.window)
      .listen((_) {
        if (!controller.isClosed) controller.add(true);
      });
  final offlineSub = web.EventStreamProviders.offlineEvent
      .forTarget(web.window)
      .listen((_) {
        if (!controller.isClosed) controller.add(false);
      });

  ref.onDispose(() {
    onlineSub.cancel();
    offlineSub.cancel();
    controller.close();
  });

  return controller.stream;
});
