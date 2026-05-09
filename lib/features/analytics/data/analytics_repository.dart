import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import 'models/analytics_event.dart';

/// Fire-and-forget repository for the first-party product analytics events
/// table. Errors are swallowed — analytics must never break the user's flow.
class AnalyticsRepository extends BaseRepository {
  AnalyticsRepository(this._client, {super.recoveryRecorder});

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
