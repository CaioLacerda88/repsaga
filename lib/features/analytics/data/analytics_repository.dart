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
class AnalyticsRepository extends BaseRepository {
  AnalyticsRepository(this._client);

  final supabase.SupabaseClient _client;

  /// Inserts a single event. Never throws — all errors are caught and
  /// swallowed so a failed insert cannot break the caller's path.
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
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
