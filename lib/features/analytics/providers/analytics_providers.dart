import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/base_repository.dart';
import '../data/analytics_repository.dart';
import '../data/models/analytics_event.dart';

/// Provides the [AnalyticsRepository] singleton.
///
/// **Fault-tolerant by construction.** Reading `Supabase.instance.client`
/// throws if Supabase hasn't been initialised — which is the production
/// bootstrap state for the first few frames AND the steady state in test
/// harnesses that don't override this provider. The "analytics must never
/// break the user's flow" contract lives at this layer: if the client
/// can't be obtained, fall back to [_NoOpAnalyticsRepository] so every
/// downstream call site can safely do
/// `ref.read(analyticsRepositoryProvider).insertEvent(...)` without
/// defensive try/catch wrappers.
///
/// Note: the recovery recorder is intentionally NOT injected here — see
/// the rationale in [AnalyticsRepository]'s class doc. Analytics is
/// fire-and-forget and must not feed the recovery state machine.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  try {
    return AnalyticsRepository(Supabase.instance.client);
  } catch (_) {
    // Supabase not initialised in this context (test harness without an
    // override, or a pre-bootstrap read). Return a no-op so call sites
    // don't need to know the difference.
    return _NoOpAnalyticsRepository();
  }
});

/// No-op analytics repository used as the fallback when Supabase isn't
/// available. Every method completes silently — same observable behavior
/// as the production repository in its swallow-on-error path.
class _NoOpAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    // Intentionally empty — analytics is fire-and-forget.
  }
}
