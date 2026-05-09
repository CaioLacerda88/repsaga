import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../data/analytics_repository.dart';

/// Provides the [AnalyticsRepository] singleton.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});
