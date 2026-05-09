import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../../core/local_storage/cache_service.dart';
import '../../exercises/providers/exercise_providers.dart';
import '../data/routine_repository.dart';

export 'notifiers/routine_list_notifier.dart';

/// Provides the [RoutineRepository] singleton.
final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return RoutineRepository(
    Supabase.instance.client,
    ref.watch(cacheServiceProvider),
    ref.watch(exerciseRepositoryProvider),
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});
