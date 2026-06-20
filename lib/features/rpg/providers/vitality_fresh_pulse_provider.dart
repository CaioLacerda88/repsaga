import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/vitality_fresh_pulse_local_storage.dart';

/// Riverpod provider for [VitalityFreshPulseLocalStorage] — overridable in
/// tests (Phase Vitality PR 2). Sibling of [rankUpPulseLocalStorageProvider].
///
/// Production code: returns a default-constructed
/// [VitalityFreshPulseLocalStorage] reading from the Hive box registered in
/// `HiveService`. Tests inject a constructor-supplied test box via
/// [Provider.overrideWithValue].
///
/// **Startup sweep.** On first read the provider fires `sweepExpired()` to
/// clear entries past their 24h window. Fire-and-forget + idempotent — same
/// contract as the rank-up pulse provider.
final vitalityFreshPulseLocalStorageProvider =
    Provider<VitalityFreshPulseLocalStorage>((ref) {
      final storage = VitalityFreshPulseLocalStorage();
      unawaited(storage.sweepExpired());
      return storage;
    });
