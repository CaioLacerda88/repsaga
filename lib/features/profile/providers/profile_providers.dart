import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../../core/local_storage/hive_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/avatar_repository.dart';
import '../data/profile_repository.dart';
import '../models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Provides the [AvatarRepository] singleton — wires the live Supabase
/// client + the `userPrefs` Hive box for the URL-cache fast-path.
///
/// **Box availability assumption.** [HiveService.init] opens every box
/// (including `userPrefs`) before `runApp()` is called in `main.dart`,
/// so consumers of this provider can assume the box is open. Tests must
/// either open the box in their `setUpAll` (see
/// `profile_screen_test.dart` for the pattern) OR override this
/// provider entirely with a stub.
final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  return AvatarRepository(
    Supabase.instance.client,
    Hive.box<dynamic>(HiveService.userPrefs),
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile?>(
  ProfileNotifier.new,
);

/// Tracks whether an avatar upload is currently in flight. Toggled by the
/// `profile_settings_screen.dart` `openAvatarUploadFlow` orchestrator
/// around the `AvatarRepository.uploadAvatar + ProfileRepository.upsertProfile`
/// pair so the IdentityCard can render a loading overlay on top of the
/// avatar disc — without this, the 3-10s upload window has no visible
/// affordance and the user re-taps thinking the action was dropped.
///
/// Per the architectural separation rule, this lives at the
/// orchestration / provider layer; the leaf widget ([ProfileAvatar]) only
/// reads the flag as a constructor param.
final avatarUploadInProgressProvider = StateProvider<bool>((ref) => false);

class ProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return null;
    final repo = ref.read(profileRepositoryProvider);
    return repo.getProfile(userId);
  }

  Future<void> saveOnboardingProfile({
    required String displayName,
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final repo = ref.read(profileRepositoryProvider);
    state = AsyncData(
      await repo.upsertProfile(
        userId: userId,
        displayName: displayName,
        fitnessLevel: fitnessLevel,
        trainingFrequencyPerWeek: trainingFrequencyPerWeek,
      ),
    );
  }

  Future<void> updateTrainingFrequency(int frequency) async {
    final current = state.value;
    if (current == null) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final repo = ref.read(profileRepositoryProvider);
    state = await AsyncValue.guard(() async {
      await repo.updateTrainingFrequency(userId, frequency);
      return current.copyWith(trainingFrequencyPerWeek: frequency);
    });
  }

  Future<void> toggleWeightUnit() async {
    final current = state.value;
    if (current == null) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final newUnit = current.weightUnit == 'kg' ? 'lbs' : 'kg';
    final repo = ref.read(profileRepositoryProvider);
    state = await AsyncValue.guard(() async {
      await repo.updateWeightUnit(userId, newUnit);
      return current.copyWith(weightUnit: newUnit);
    });
  }
}
