import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';

/// Repository for user avatar uploads to the Supabase Storage `avatars`
/// bucket plus a Hive-backed cache of the most-recent signed URL for
/// fast-path reads (so the IdentityCard avatar doesn't wait for the next
/// profile-row fetch after the user uploads).
///
/// **Storage layout:** `avatars/{userId}/avatar.jpg`. Migration 00068 created
/// the bucket; migration 00069 flipped it to **private** for LGPD/GDPR
/// compliance — user-uploaded photos are personal content and must be
/// served behind signed URLs. The nested path (NOT a flat `{userId}.jpg`)
/// is required: the bucket RLS predicate gates writes on
/// `(storage.foldername(name))[1] = auth.uid()::text`, and `foldername`
/// returns `[]` for flat filenames — every upload would be denied. The
/// bucket accepts both `image/jpeg` and `image/png` at a 512KB ceiling.
///
/// **Signed URLs only — no public endpoint.** Uploads call
/// [supabase.StorageFileApi.createSignedUrl] with a 1-year expiry. The
/// returned URL embeds a short-lived JWT in the query string; reading it
/// from any device routes through the signed-URL CDN path. The Hive cache
/// tracks the URL alongside an `avatarUrlCacheExpiresAt:<userId>` entry —
/// when the expiry lapses, [getCachedAvatarUrl] returns null and the
/// screen layer calls [regenerateSignedUrl] to mint a fresh token.
///
/// **Cache layering:** the Hive `userPrefs` box holds the URL under
/// `avatarUrlCache:<userId>` and the expiry epoch-ms under
/// `avatarUrlCacheExpiresAt:<userId>`. The persistent source of truth is
/// `profiles.avatar_url`; Hive is just a hop to avoid waiting for the next
/// `profileProvider` refresh after upload. Invalidating the cache is safe
/// — the next read falls back to the profile row.
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

  /// Hive key prefix for the URL-cache expiry companion entry. Stores the
  /// epoch-ms instant at which the signed URL stops working. Public so
  /// tests can prime / inspect the exact key.
  static const String cacheExpiryKeyPrefix = 'avatarUrlCacheExpiresAt:';

  /// Signed-URL lifetime in seconds — 1 year. The signed-URL CDN allows
  /// up to ~7 years; 1 year balances "rarely regenerate" against "stale
  /// token never lives forever in a cache". When the URL expires, the
  /// screen layer calls [regenerateSignedUrl] to mint a fresh one.
  static const int signedUrlExpirySeconds = 365 * 24 * 60 * 60;

  /// Compute the canonical storage path for [userId]'s avatar object.
  /// Public so callers (the future delete-avatar flow) can refer to the
  /// same path without re-deriving the convention.
  ///
  /// **Nested layout required.** Returns `{userId}/avatar.jpg`, not
  /// `{userId}.jpg`. The bucket RLS predicate uses
  /// `(storage.foldername(name))[1] = auth.uid()::text`, which only
  /// matches when the path has at least one slash-delimited folder
  /// segment. A flat filename collapses `foldername` to `[]` and every
  /// write is RLS-rejected — see migration 00068's preamble.
  static String pathFor(String userId) => '$userId/avatar.jpg';

  /// Upload [imageBytes] to the user's avatar object and return a signed
  /// URL with a 1-year expiry. Idempotent: each call overwrites the same
  /// object via the `upsert: true` flag, so the user's
  /// `avatars/{userId}/avatar.jpg` address is stable across uploads.
  ///
  /// [contentType] defaults to `'image/png'` because the v1
  /// `AvatarCropSheet` rasterizes via `dart:ui`'s PNG encoder; pass
  /// `'image/jpeg'` if a future caller ships JPEG bytes (the bucket
  /// allows both per migration 00068).
  ///
  /// Side-effects:
  ///   * Writes the returned URL to Hive `userPrefs` at
  ///     `cacheKeyPrefix + userId` for the fast-path read.
  ///   * Writes the matching expiry instant (now + 1 year, epoch-ms) to
  ///     `cacheExpiryKeyPrefix + userId` so [getCachedAvatarUrl] can
  ///     gate stale reads without a network call.
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
              // cacheControl mirrors the bucket default; the signed
              // URL's JWT changes on every regeneration, so the URL
              // itself defeats any CDN cache holding a prior version
              // (browsers / CDNs key on the full URL including query).
              cacheControl: '3600',
            ),
          );

      final signedUrl = await _client.storage
          .from(_bucket)
          .createSignedUrl(path, signedUrlExpirySeconds);

      await _writeCache(userId: userId, url: signedUrl);
      return signedUrl;
    });
  }

  /// Mint a fresh signed URL for [userId]'s existing avatar object and
  /// update the Hive cache. Called from the screen layer when
  /// [getCachedAvatarUrl] returns null due to expiry — the object is
  /// still in storage, only the token lapsed.
  ///
  /// The screen layer is responsible for forwarding the new URL into
  /// `profiles.avatar_url` so cross-device sessions converge on the
  /// freshest token; without that the next session would still pull the
  /// stale URL from the profile row and have to regenerate again.
  Future<String> regenerateSignedUrl(String userId) {
    return mapException(() async {
      final path = pathFor(userId);
      final signedUrl = await _client.storage
          .from(_bucket)
          .createSignedUrl(path, signedUrlExpirySeconds);
      await _writeCache(userId: userId, url: signedUrl);
      return signedUrl;
    });
  }

  /// Synchronous read of the cached signed URL for [userId]. Returns
  /// `null` if no upload has been performed in this install, the cache
  /// was invalidated (e.g. via [invalidateCache] or a Hive wipe), OR the
  /// stored expiry instant has passed — the screen layer treats null as
  /// "no fast-path; fall back to the profile row or regenerate".
  ///
  /// **Expiry check is structural, not stochastic:** the comparison is
  /// `DateTime.now().millisecondsSinceEpoch > expiry`. The signed URL
  /// itself does not expose its expiry; the Hive companion entry is
  /// authoritative for the local fast-path.
  String? getCachedAvatarUrl(String userId) {
    final value = _userPrefsBox.get('$cacheKeyPrefix$userId');
    if (value is! String) return null;
    final expiry = _userPrefsBox.get('$cacheExpiryKeyPrefix$userId');
    if (expiry is int) {
      if (DateTime.now().millisecondsSinceEpoch > expiry) {
        return null;
      }
    }
    return value;
  }

  /// Remove the cached URL + expiry companion entry for [userId]. Called
  /// after a deliberate cache flush (sign-out, delete-account flow) —
  /// not after every upload (the upload itself overwrites the cache
  /// entries via [_writeCache]).
  Future<void> invalidateCache(String userId) async {
    await _userPrefsBox.delete('$cacheKeyPrefix$userId');
    await _userPrefsBox.delete('$cacheExpiryKeyPrefix$userId');
  }

  /// Stamp the URL + expiry pair atomically (sequentially — Hive's box
  /// API does not expose a batch put). Private so the upload and
  /// regenerate paths share the same key shape.
  Future<void> _writeCache({
    required String userId,
    required String url,
  }) async {
    final expiry = DateTime.now()
        .add(const Duration(seconds: signedUrlExpirySeconds))
        .millisecondsSinceEpoch;
    await _userPrefsBox.put('$cacheKeyPrefix$userId', url);
    await _userPrefsBox.put('$cacheExpiryKeyPrefix$userId', expiry);
  }
}
