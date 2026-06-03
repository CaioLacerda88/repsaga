import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../models/profile.dart';

class ProfileRepository extends BaseRepository {
  ProfileRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  Future<Profile?> getProfile(String userId) {
    return mapException(() async {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return Profile.fromJson(data);
    });
  }

  Future<Profile> upsertProfile({
    required String userId,
    String? displayName,
    String? fitnessLevel,
    String? weightUnit,
    int? trainingFrequencyPerWeek,
    String? locale,
    double? bodyweightKg,
    Gender? gender,
    String? avatarUrl,
    DateTime? onboardedAt,
  }) {
    return mapException(() async {
      final updates = <String, dynamic>{
        'id': userId,
        // ignore: use_null_aware_elements
        if (displayName != null) 'display_name': displayName,
        // ignore: use_null_aware_elements
        if (fitnessLevel != null) 'fitness_level': fitnessLevel,
        // ignore: use_null_aware_elements
        if (weightUnit != null) 'weight_unit': weightUnit,
        // ignore: use_null_aware_elements
        if (trainingFrequencyPerWeek != null)
          'training_frequency_per_week': trainingFrequencyPerWeek,
        // ignore: use_null_aware_elements
        if (locale != null) 'locale': locale,
        // Phase 24c — only forward when the caller supplied a value. Omitting
        // the key from the upsert payload preserves any prior bodyweight on
        // the row (writing null would clobber it on every unrelated update).
        // ignore: use_null_aware_elements
        if (bodyweightKg != null) 'bodyweight_kg': bodyweightKg,
        // Phase 29 v2 — same omit-on-null discipline as bodyweightKg. The
        // SQL CHECK constraint accepts one of `male` / `female` / `other`
        // or NULL; the enum's @JsonValue annotations serialize to the
        // matching tokens.
        // ignore: use_null_aware_elements
        if (gender != null) 'gender': gender.name,
        // Phase 32 PR 32e — avatar URL. Same omit-on-null discipline:
        // forwarding null would clobber a previously uploaded avatar
        // on every unrelated profile update. The `AvatarRepository`
        // upload flow calls this with the freshly cache-busted URL
        // (`{publicUrl}?v=<timestamp>`) so subsequent reads bypass any
        // stale CDN cache.
        // ignore: use_null_aware_elements
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        // PR 1 — onboarding completion anchor. Same omit-on-null discipline:
        // forwarding null would clobber a previously-set timestamp on every
        // unrelated profile update (settings tweak, weekly-frequency change,
        // avatar upload). `ProfileNotifier.saveOnboardingProfile` stamps
        // `DateTime.now()` exactly once at the end of the onboarding flow.
        if (onboardedAt != null) 'onboarded_at': onboardedAt.toIso8601String(),
      };
      final data = await _client
          .from('profiles')
          .upsert(updates)
          .select()
          .single();
      return Profile.fromJson(data);
    });
  }

  Future<void> updateTrainingFrequency(String userId, int frequency) {
    return mapException(() async {
      await _client
          .from('profiles')
          .update({'training_frequency_per_week': frequency})
          .eq('id', userId);
    });
  }

  Future<void> updateWeightUnit(String userId, String unit) {
    return mapException(() async {
      await _client
          .from('profiles')
          .update({'weight_unit': unit})
          .eq('id', userId);
    });
  }

  Future<void> updateLocale(String userId, String locale) {
    return mapException(() async {
      await _client
          .from('profiles')
          .update({'locale': locale})
          .eq('id', userId);
    });
  }
}
