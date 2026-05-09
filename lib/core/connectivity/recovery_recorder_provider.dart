import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/base_repository.dart';
import 'connectivity_recovery_provider.dart';

/// Adapter that implements the Riverpod-agnostic
/// [ConnectivityRecoveryRecorder] surface that [BaseRepository] sees, by
/// forwarding to the [connectivityRecoveryProvider] notifier.
///
/// Created by [recoveryRecorderProvider] and injected into every repository
/// provider factory. Repositories construct against the abstract recorder
/// type — they never reach into Riverpod themselves, which keeps
/// `lib/core/data/` decoupled from the provider graph and lets tests
/// instantiate repositories without spinning up a [ProviderContainer].
class _RiverpodConnectivityRecoveryRecorder
    implements ConnectivityRecoveryRecorder {
  _RiverpodConnectivityRecoveryRecorder(this._ref);

  final Ref _ref;

  @override
  void recordSuccess() {
    _ref.read(connectivityRecoveryProvider.notifier).recordSuccess();
  }

  @override
  void recordFailure(Object error) {
    _ref.read(connectivityRecoveryProvider.notifier).recordFailure(error);
  }
}

/// Singleton recorder bound to the [Ref]'s container lifetime. Repositories
/// `ref.watch` this and pass it to [BaseRepository]'s constructor.
final recoveryRecorderProvider = Provider<ConnectivityRecoveryRecorder>((ref) {
  return _RiverpodConnectivityRecoveryRecorder(ref);
});
