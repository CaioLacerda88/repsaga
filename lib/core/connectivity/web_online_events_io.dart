import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native (non-web) stub for the browser online/offline event source.
///
/// Returns an empty stream so the merge logic in [onlineStatusProvider]
/// has nothing to react to from the "web" branch — `connectivity_plus`'s
/// adapter stream is the sole signal on Android/iOS/desktop.
///
/// This file is selected by the conditional import in
/// `connectivity_provider.dart` whenever `dart.library.js_interop` is
/// NOT available (i.e. all native targets), preventing `package:web`
/// from being linked into the native bundle.
final webOnlineEventsProvider = Provider<Stream<bool>>((ref) {
  return const Stream<bool>.empty();
});
