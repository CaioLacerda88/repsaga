import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../models/profile.dart';

class ProfileRepository extends BaseRepository {
  ProfileRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  /// Shared refresh callback for every mutation method below. Hits the
  /// repository's own client's auth instance (no `Supabase.instance`
  /// singleton coupling — keeps the class testable with a fake
  /// `SupabaseClient`).
  Future<void> _refreshSession() async {
    await _client.auth.refreshSession();
  }

  /// Wraps an authenticated mutation with [BaseRepository.refreshAndRetry]
  /// AND the standard [BaseRepository.mapException] error-mapping +
  /// connectivity-recorder side effects. The refresh-and-retry layer sits
  /// INSIDE [mapException] so that:
  ///   * The retry sees raw [supabase.PostgrestException] / `AuthException`
  ///     codes (the `42501` / `401` shapes the helper triggers on).
  ///   * If both attempts fail, the original raw error reaches [mapException]
  ///     and gets the normal mapping / Sentry capture / recorder treatment.
  ///   * Read methods (e.g. `getProfile`) deliberately skip this wrapper:
  ///     RLS on a SELECT just returns no rows in practice, so the retry
  ///     adds latency for no UX benefit.
  Future<T> _withStaleTokenRetry<T>(Future<T> Function() action) {
    return mapException(
      () => refreshAndRetry<T>(action: action, refresh: _refreshSession),
    );
  }

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
  }) {
    return _withStaleTokenRetry(() async {
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
    return _withStaleTokenRetry(() async {
      await _client
          .from('profiles')
          .update({'training_frequency_per_week': frequency})
          .eq('id', userId);
    });
  }

  Future<void> updateWeightUnit(String userId, String unit) {
    return _withStaleTokenRetry(() async {
      await _client
          .from('profiles')
          .update({'weight_unit': unit})
          .eq('id', userId);
    });
  }

  Future<void> updateLocale(String userId, String locale) {
    return _withStaleTokenRetry(() async {
      await _client
          .from('profiles')
          .update({'locale': locale})
          .eq('id', userId);
    });
  }
}
