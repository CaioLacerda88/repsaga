import 'package:repsaga/features/rpg/data/vitality_fresh_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

/// No-op [VitalityFreshPulseLocalStorage] for widget tests that mount
/// `PostSessionScreen` (which records the fresh-today pulse on mount via
/// `vitalityFreshPulseLocalStorageProvider`). The real storage opens a Hive
/// box that isn't available under `flutter test`, so harnesses not exercising
/// the pulse contract override the provider with this fake.
///
/// The actual record→isPulsing behavior is pinned by
/// `test/widget/features/workouts/ui/post_session/post_session_screen_fresh_pulse_test.dart`.
class FakeFreshPulseStorage implements VitalityFreshPulseLocalStorage {
  @override
  bool isPulsing(BodyPart bodyPart, {DateTime? now}) => false;

  @override
  Future<void> recordCharged(BodyPart bodyPart, {DateTime? at}) async {}

  @override
  Future<void> recordChargedBatch(
    Iterable<BodyPart> bodyParts, {
    DateTime? at,
  }) async {}

  @override
  Future<void> sweepExpired({DateTime? now}) async {}
}
