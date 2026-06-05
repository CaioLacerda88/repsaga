import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import 'models/analytics_event.dart';

/// Fire-and-forget repository for the first-party product analytics events
/// table. Errors are swallowed — analytics must never break the user's flow.
///
/// **Why no `recoveryRecorder`.** Analytics intentionally opts out of the
/// connectivity-recovery state machine. Two reasons: (a) analytics writes
/// are silent / non-user-facing, so a failure here doesn't represent the
/// user's effective network state — promoting it to a "network failed"
/// signal would be misleading. (b) a Supabase outage hitting the
/// analytics_events table would otherwise spam `recordFailure` and arm
/// the recovery window every time a real user action also failed,
/// potentially compounding into drain triggers. The class-level swallow
/// in [insertEvent] also catches errors before [BaseRepository.mapException]
/// runs, so even if the recorder were injected it would be unreachable —
/// keeping the constructor surface honest about that.
///
/// **Opt-out gating.** Legal PR 2 (`data-protection-compliance` cluster)
/// adds a static `_enabled` flag mirrored from the user's `analytics_enabled`
/// Hive preference. [insertEvent] short-circuits when the flag is false so
/// no rows reach `analytics_events` while the user has opted out. The flag
/// is initialised to `true` (legitimate-interest opt-out per Privacy Policy
/// §4a) and synced on every notifier rebuild via
/// [AnalyticsEnabledNotifier.build] so the static flag and persisted Hive
/// value cannot diverge across hot reloads / `ref.invalidate`.
class AnalyticsRepository extends BaseRepository {
  AnalyticsRepository(this._client);

  final supabase.SupabaseClient _client;

  static bool _enabled = true;

  /// Whether analytics inserts are currently enabled.
  static bool get isEnabled => _enabled;

  /// Enable or disable analytics sends at runtime. Mirrors the persisted
  /// `analytics_enabled` Hive preference; called from
  /// [AnalyticsEnabledNotifier.build] (sync on rebuild) and
  /// [AnalyticsEnabledNotifier.setEnabled] (sync on flip).
  static void setEnabled(bool value) {
    _enabled = value;
  }

  /// Test-only reset. Returns the gate to the production default (`true`)
  /// so tests don't leak opt-out state across cases. Not for production
  /// callers — production code should go through [AnalyticsEnabledNotifier].
  @visibleForTesting
  static void debugResetEnabled() {
    _enabled = true;
  }

  /// Inserts a single event. Never throws — all errors are caught and
  /// swallowed so a failed insert cannot break the caller's path.
  ///
  /// Returns immediately without writing when [isEnabled] is `false`
  /// (analytics opt-out). The check happens before any I/O so an
  /// opted-out user generates zero `analytics_events` rows.
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    if (!_enabled) return;
    try {
      await _client.from('analytics_events').insert({
        'user_id': userId,
        'name': event.name,
        'props': event.props,
        'platform': platform,
        'app_version': appVersion,
      });
    } catch (_) {
      // Best-effort: analytics failures are silent. We do NOT capture these
      // to Sentry — a Supabase outage would flood the error tracker.
    }
  }
}
