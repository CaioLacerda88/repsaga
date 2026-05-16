import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rank_up_pulse_local_storage.dart';

/// Riverpod provider for [RankUpPulseLocalStorage] — overridable in tests.
///
/// Production code: the provider returns a default-constructed
/// [RankUpPulseLocalStorage] reading from the Hive box registered in
/// `HiveService`. Tests inject a mock or a constructor-supplied test box via
/// [Provider.overrideWithValue].
final rankUpPulseLocalStorageProvider = Provider<RankUpPulseLocalStorage>(
  (ref) => RankUpPulseLocalStorage(),
);
