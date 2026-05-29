import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';

/// Repository for user avatar uploads to the Supabase Storage `avatars`
/// bucket plus a Hive-backed cache of the most-recent public URL for
/// fast-path reads (so the IdentityCard avatar doesn't wait for the next
/// profile-row fetch after the user uploads).
///
/// **Storage layout:** `avatars/{userId}.jpg`. Migration 00068 created the
/// bucket with read-public + write-own-user-prefix RLS — the user can only
/// overwrite their own object. The bucket is configured for `image/jpeg`
/// only at a 512KB ceiling.
///
/// **Cache-busting:** uploads return a URL with a `?v=<timestamp>` suffix
/// stamped at upload time. Subsequent reads on the same user route through
/// the new URL, bypassing any browser / CDN cache holding the prior
/// version. The suffix is part of the URL persisted on `profiles.avatar_url`
/// — not a per-render runtime concatenation — so reads from any surface
/// (IdentityCard now, a future leaderboard) consume the same bust token.
///
/// **Cache layering:** the Hive `userPrefs` box holds the URL under
/// `avatarUrlCache:<userId>` for the fast-path read. The persistent source
/// of truth is `profiles.avatar_url`; Hive is just a hop to avoid waiting
/// for the next `profileProvider` refresh after upload. Invalidating the
/// cache is safe — the next read falls back to the profile row.
class AvatarRepository extends BaseRepository {
  AvatarRepository(this._client, this._userPrefsBox, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;
  final Box<dynamic> _userPrefsBox;

  /// Bucket name — must match the literal in migration 00068.
  static const String _bucket = 'avatars';

  /// Hive key prefix for the URL-cache fast-path. The full key shape is
  /// `avatarUrlCache:<userId>` so multiple user sessions on the same
  /// device don't collide. Public so tests can pin the exact key.
  static const String cacheKeyPrefix = 'avatarUrlCache:';

  /// Compute the canonical storage path for [userId]'s avatar object.
  /// Public so callers (the future delete-avatar flow) can refer to the
  /// same path without re-deriving the convention.
  static String pathFor(String userId) => '$userId.jpg';

  /// Upload [imageBytes] to the user's avatar object and return the
  /// public URL with a `?v=<DateTime.now().millisecondsSinceEpoch>`
  /// cache-bust suffix. Idempotent: each call overwrites the same
  /// object via the `upsert: true` flag, so the user's
  /// `avatars/{userId}.jpg` address is stable across uploads.
  ///
  /// [contentType] defaults to `'image/png'` because the v1
  /// `AvatarCropSheet` rasterizes via `dart:ui`'s PNG encoder; pass
  /// `'image/jpeg'` if a future caller ships JPEG bytes (the bucket
  /// allows both per migration 00068).
  ///
  /// Side-effects:
  ///   * Writes the returned URL to Hive `userPrefs` at
  ///     `cacheKeyPrefix + userId` for the fast-path read.
  ///   * The caller is responsible for forwarding the URL into
  ///     `ProfileRepository.upsertProfile(avatarUrl:)` so the durable
  ///     source of truth (the profile row) tracks the upload.
  ///
  /// Storage exceptions are caught by [BaseRepository.mapException]
  /// and surfaced as `NetworkException` to the UI (the user message is
  /// the generic "no connection" copy — appropriate for a transient
  /// upload failure that the user can retry).
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List imageBytes,
    String contentType = 'image/png',
  }) {
    return mapException(() async {
      final path = pathFor(userId);
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            imageBytes,
            fileOptions: supabase.FileOptions(
              contentType: contentType,
              // upsert: true — the user's avatar lives at a stable
              // address; uploads replace the prior object. Without
              // upsert the second upload errors with a duplicate-
              // object response.
              upsert: true,
              // cacheControl mirrors the bucket default; the URL-level
              // `?v=<timestamp>` query string is what actually defeats
              // the cache after an overwrite. Browsers / CDNs key on
              // the full URL including query, so a fresh `?v=` makes
              // the new object's response uncached.
              cacheControl: '3600',
            ),
          );

      final publicUrl = _client.storage.from(_bucket).getPublicUrl(path);
      final cacheBusted =
          '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await _userPrefsBox.put('$cacheKeyPrefix$userId', cacheBusted);
      return cacheBusted;
    });
  }

  /// Synchronous read of the cached public URL for [userId]. Returns
  /// `null` if no upload has been performed in this install OR the cache
  /// was invalidated (e.g. via [invalidateCache] or a Hive wipe).
  ///
  /// The caller falls back to `profile.avatarUrl` when this returns null
  /// — the persistent source of truth is the profile row, not Hive.
  String? getCachedAvatarUrl(String userId) {
    final value = _userPrefsBox.get('$cacheKeyPrefix$userId');
    return value is String ? value : null;
  }

  /// Remove the cached URL for [userId]. Called after a deliberate cache
  /// flush (sign-out, delete-account flow) — not after every upload (the
  /// upload itself overwrites the cache entry).
  Future<void> invalidateCache(String userId) async {
    await _userPrefsBox.delete('$cacheKeyPrefix$userId');
  }
}
