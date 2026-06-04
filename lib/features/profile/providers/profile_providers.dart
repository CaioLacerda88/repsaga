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
    // Cluster: provider-init-timing — watch authStateProvider, not the
    // synchronous currentUserIdProvider. The latter is documented as
    // non-reactive (auth_providers.dart): it reads `auth.currentUser?.id`
    // ONCE at first watch and caches forever. At app start that read
    // returns null (Supabase auth hasn't restored its session yet), so
    // build() returned `null` and never re-fired on sign-in — leaving
    // profileProvider stuck on `AsyncData(null)` forever. PR 1's router
    // gate (`profileValue == null || onboardedAt == null`) then treated
    // every logged-in user as needs-onboarding, routing them to
    // `/onboarding` instead of `/home`. Surfaced by CI E2E retry loop
    // on `NAV.homeTab` post-login (45-minute timeout cascade across
    // every spec that asserts the home tab is reachable).
    //
    // Watching authStateProvider here makes build re-run on every
    // signedIn / signedOut / tokenRefreshed event — the profile reloads
    // automatically when the user changes.
    final session = ref.watch(authStateProvider).value?.session;
    if (session == null) return null;
    final repo = ref.read(profileRepositoryProvider);
    return repo.getProfile(session.user.id);
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
        // PR 1 — stamp the onboarding-completion anchor here, exactly
        // once. The router gate reads `profile.onboardedAt` to decide
        // /home vs /onboarding (the derived `needsOnboardingProvider`);
        // `DateTime.now()` survives process restart via the SQL column.
        onboardedAt: DateTime.now(),
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
