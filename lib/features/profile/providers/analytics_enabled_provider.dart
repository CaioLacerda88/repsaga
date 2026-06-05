import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';
import '../../analytics/data/analytics_repository.dart';

const _hiveKey = 'analytics_enabled';

/// Notifier for the "Send usage analytics" user preference. Backed by the
/// `user_prefs` Hive box. Defaults to `true` (opt-out, not opt-in — the
/// Privacy Policy §4a "legitimate interest" basis for product analytics
/// requires only that the user can opt out, not that they pre-opt-in).
///
/// Setting the value persists immediately and updates
/// [AnalyticsRepository] so the change takes effect for all subsequent
/// `insertEvent` calls.
///
/// Cluster: `data-protection-compliance`. Mirrors
/// [CrashReportsEnabledNotifier] exactly — same Hive key shape, same
/// build-time sync, same runtime gate. New runtime-gated subsystems should
/// follow the same pattern.
class AnalyticsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box(HiveService.userPrefs);
    final value = box.get(_hiveKey, defaultValue: true) as bool;
    // Keep the static AnalyticsRepository flag in sync with the Hive-backed
    // state so invalidation/rebuild (hot reload, future ref.invalidate)
    // cannot diverge the runtime gate from the persisted preference.
    AnalyticsRepository.setEnabled(value);
    return value;
  }

  Future<void> setEnabled(bool enabled) async {
    final box = Hive.box(HiveService.userPrefs);
    await box.put(_hiveKey, enabled);
    AnalyticsRepository.setEnabled(enabled);
    state = enabled;
  }
}

final analyticsEnabledProvider =
    NotifierProvider<AnalyticsEnabledNotifier, bool>(
      AnalyticsEnabledNotifier.new,
    );
