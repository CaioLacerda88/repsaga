import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../models/profile.dart';

class ProfileRepository extends BaseRepository {
  ProfileRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  /// Tighter budget for the inline refresh attempt than
  /// [AuthRepository]'s top-level 30 s budget. On degraded networks
  /// (captive portal, airplane mode mid-mutation, OEM background-data
  /// throttling) Android's TCP stack holds the coroutine up to ~75 s
  /// before failing the underlying socket. Hanging the user's "Save
  /// profile" tap for >5 s is worse UX than failing fast — the user
  /// can retry, and [refreshAndRetry] surfaces the ORIGINAL 42501 on
  /// the refresh-timeout path so the caller sees the right error
  /// category. 8 s undercuts [AuthRepository]'s top-level
  /// `_defaultAuthTimeout = 30 s` so this fast-path never out-waits
  /// the slow-path.
  static const Duration _refreshTimeout = Duration(seconds: 8);

  /// Shared refresh callback for every mutation method below. Hits the
  /// repository's own client's auth instance (no `Supabase.instance`
  /// singleton coupling — keeps the class testable with a fake
  /// `SupabaseClient`). The `.timeout` budget is intentionally tight
  /// (see [_refreshTimeout]); a `TimeoutException` here is caught by
  /// [BaseRepository.refreshAndRetry]'s refresh-failure branch and
  /// surfaces as the ORIGINAL 42501 — exactly the behavior the helper
  /// tests pin (`refresh() throws → original error rethrows`).
  Future<void> _refreshSession() async {
    await _client.auth.refreshSession().timeout(_refreshTimeout);
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
    DateTime? onboardedAt,
    DateTime? dateOfBirth,
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
        // PR 1 — onboarding completion anchor. Same omit-on-null discipline:
        // forwarding null would clobber a previously-set timestamp on every
        // unrelated profile update (settings tweak, weekly-frequency change,
        // avatar upload). `ProfileNotifier.saveOnboardingProfile` stamps
        // `DateTime.now()` exactly once at the end of the onboarding flow.
        if (onboardedAt != null) 'onboarded_at': onboardedAt.toIso8601String(),
        // Phase 38d — birth date. Same omit-on-null discipline: forwarding
        // null would clobber a previously-set DOB on every unrelated
        // profile update (the AgeEditorSheet's "Prefer not to say" clears
        // the value via a dedicated explicit-null path, not by omission).
        // Serialized as the Postgres `date` wire shape (`YYYY-MM-DD`), NOT
        // `.toIso8601String()` — a full timestamp would be rejected /
        // coerced by the `date` column. Mirrors `Profile._dateToJson`.
        if (dateOfBirth != null)
          'date_of_birth':
              '${dateOfBirth.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth.day.toString().padLeft(2, '0')}',
      };
      final data = await _client
          .from('profiles')
          .upsert(updates)
          .select()
          .single();
      return Profile.fromJson(data);
    });
  }

  /// Explicitly clear the user's birth date (Phase 38d "Prefer not to
  /// say" / clear-a-previously-set-value path).
  ///
  /// [upsertProfile] omits null fields to avoid clobbering unrelated
  /// columns, so it cannot represent an intentional clear. This dedicated
  /// `UPDATE ... SET date_of_birth = NULL` is the only writer that nulls
  /// the column — keeping the destructive intent explicit at the call site
  /// (the AgeEditorSheet's ghost affordance) rather than overloading the
  /// omit-on-null upsert with a magic sentinel.
  Future<void> clearDateOfBirth(String userId) {
    return _withStaleTokenRetry(() async {
      await _client
          .from('profiles')
          .update({'date_of_birth': null})
          .eq('id', userId);
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
