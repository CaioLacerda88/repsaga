import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rank_up_pulse_local_storage.dart';

/// Riverpod provider for [RankUpPulseLocalStorage] — overridable in tests.
///
/// Production code: the provider returns a default-constructed
/// [RankUpPulseLocalStorage] reading from the Hive box registered in
/// `HiveService`. Tests inject a mock or a constructor-supplied test box via
/// [Provider.overrideWithValue].
///
/// **Startup sweep.** On first read (typically when the saga screen first
/// builds), the provider fires `sweepExpired()` to clear any entries past
/// their 24h window. Fire-and-forget — a failed sweep just means the box
/// carries a few stale entries until the next session. The behavior is
/// idempotent (no-op if all entries are still in-window).
final rankUpPulseLocalStorageProvider = Provider<RankUpPulseLocalStorage>((
  ref,
) {
  final storage = RankUpPulseLocalStorage();
  unawaited(storage.sweepExpired());
  return storage;
});
