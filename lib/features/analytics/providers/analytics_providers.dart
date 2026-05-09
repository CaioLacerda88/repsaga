import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/analytics_repository.dart';

/// Provides the [AnalyticsRepository] singleton.
///
/// Note: the recovery recorder is intentionally NOT injected here — see
/// the rationale in [AnalyticsRepository]'s class doc. Analytics is
/// fire-and-forget and must not feed the recovery state machine.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(Supabase.instance.client);
});
