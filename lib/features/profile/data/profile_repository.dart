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
