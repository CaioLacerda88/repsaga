import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/features/profile/data/avatar_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Fake Supabase Storage infrastructure
// ---------------------------------------------------------------------------

class _FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  _FakeSupabaseClient(this._storage);
  final _FakeSupabaseStorage _storage;

  @override
  supabase.SupabaseStorageClient get storage => _storage;
}

class _FakeSupabaseStorage extends Fake
    implements supabase.SupabaseStorageClient {
  _FakeSupabaseStorage(this._bucket);
  final _FakeStorageBucket _bucket;

  @override
  supabase.StorageFileApi from(String id) {
    _bucket.lastBucketId = id;
    return _bucket;
  }
}

class _FakeStorageBucket extends Fake implements supabase.StorageFileApi {
  _FakeStorageBucket({this.uploadError});

  /// When non-null, `uploadBinary` throws this error.
  final Object? uploadError;

  String? lastBucketId;
  String? lastUploadPath;
  Uint8List? lastUploadBytes;
  supabase.FileOptions? lastFileOptions;
  String? lastSignedPath;
  int? lastSignedExpiresIn;
  int signedUrlCallCount = 0;

  @override
  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    supabase.FileOptions fileOptions = const supabase.FileOptions(),
    int? retryAttempts,
    supabase.StorageRetryController? retryController,
  }) async {
    if (uploadError != null) throw uploadError!;
    lastUploadPath = path;
    lastUploadBytes = data;
    lastFileOptions = fileOptions;
    return path;
  }

  @override
  Future<String> createSignedUrl(
    String path,
    int expiresIn, {
    supabase.TransformOptions? transform,
  }) async {
    signedUrlCallCount++;
    lastSignedPath = path;
    lastSignedExpiresIn = expiresIn;
    // Each call returns a deterministically-different token so tests can
    // pin "regenerate produced a new URL" without time-dependent sleep.
    return 'https://supabase.test/storage/v1/object/sign/avatars/$path?token=sig-$signedUrlCallCount';
  }
}

// ---------------------------------------------------------------------------
// Fake Hive box — only the get/put/delete used by AvatarRepository.
// ---------------------------------------------------------------------------

class _FakeHiveBox extends Fake implements Box<dynamic> {
  final Map<String, dynamic> _store = <String, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    return _store[key as String] ?? defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _store[key as String] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _store.remove(key);
  }

  // Test-only inspection helpers.
  bool containsKey_(String key) => _store.containsKey(key);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AvatarRepository _makeRepo({_FakeStorageBucket? bucket, _FakeHiveBox? box}) {
  final actualBucket = bucket ?? _FakeStorageBucket();
  final actualBox = box ?? _FakeHiveBox();
  return AvatarRepository(
    _FakeSupabaseClient(_FakeSupabaseStorage(actualBucket)),
    actualBox,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AvatarRepository.uploadAvatar', () {
    test(
      'uploads to avatars/{userId}/avatar.jpg with the supplied bytes',
      () async {
        final bucket = _FakeStorageBucket();
        final repo = _makeRepo(bucket: bucket);
        final bytes = Uint8List.fromList(List.filled(128, 0xAA));

        await repo.uploadAvatar(userId: 'user-123', imageBytes: bytes);

        expect(bucket.lastBucketId, 'avatars');
        // Nested layout — flat 'user-123.jpg' would fail the bucket's
        // RLS predicate `(storage.foldername(name))[1] = auth.uid()`.
        expect(bucket.lastUploadPath, 'user-123/avatar.jpg');
        expect(bucket.lastUploadBytes, bytes);
      },
    );

    test('upserts (does not error on second upload)', () async {
      final bucket = _FakeStorageBucket();
      final repo = _makeRepo(bucket: bucket);

      await repo.uploadAvatar(userId: 'u', imageBytes: Uint8List(4));

      expect(bucket.lastFileOptions?.upsert, isTrue);
    });

    test('forwards the supplied contentType (defaults to image/png)', () async {
      final bucket = _FakeStorageBucket();
      final repo = _makeRepo(bucket: bucket);

      await repo.uploadAvatar(userId: 'u', imageBytes: Uint8List(4));
      expect(bucket.lastFileOptions?.contentType, 'image/png');

      await repo.uploadAvatar(
        userId: 'u',
        imageBytes: Uint8List(4),
        contentType: 'image/jpeg',
      );
      expect(bucket.lastFileOptions?.contentType, 'image/jpeg');
    });

    test('returns a signed URL minted via createSignedUrl', () async {
      final bucket = _FakeStorageBucket();
      final repo = _makeRepo(bucket: bucket);

      final url = await repo.uploadAvatar(
        userId: 'user-123',
        imageBytes: Uint8List(8),
      );

      // The signed URL comes from the fake's createSignedUrl path —
      // proves the public-URL endpoint is NOT used. Migration 00069
      // flipped the bucket to private; getPublicUrl would 401/403.
      expect(url, contains('/object/sign/'));
      expect(url, contains('token='));
      expect(bucket.lastSignedPath, 'user-123/avatar.jpg');
      expect(
        bucket.lastSignedExpiresIn,
        AvatarRepository.signedUrlExpirySeconds,
      );
      expect(bucket.signedUrlCallCount, 1);
    });

    test('caches the returned URL under the Hive cacheKeyPrefix', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);

      final url = await repo.uploadAvatar(
        userId: 'user-abc',
        imageBytes: Uint8List(8),
      );

      expect(box.get('avatarUrlCache:user-abc'), url);
    });

    test('stamps the matching expiry instant in Hive', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);
      final beforeUpload = DateTime.now().millisecondsSinceEpoch;

      await repo.uploadAvatar(userId: 'user-abc', imageBytes: Uint8List(8));

      final expiry = box.get('avatarUrlCacheExpiresAt:user-abc') as int;
      const lifetimeMs = AvatarRepository.signedUrlExpirySeconds * 1000;
      // Expiry should be ~now + 1 year. Tolerate the millisecond gap
      // between `DateTime.now()` captures (test setup vs. repo
      // internals) by asserting on a small window.
      expect(expiry, greaterThanOrEqualTo(beforeUpload + lifetimeMs - 1000));
      expect(expiry, lessThanOrEqualTo(beforeUpload + lifetimeMs + 5000));
    });

    test('maps Supabase StorageException to AppException', () async {
      final repo = _makeRepo(
        bucket: _FakeStorageBucket(
          uploadError: const supabase.StorageException('rls denied'),
        ),
      );

      expect(
        () => repo.uploadAvatar(userId: 'user-1', imageBytes: Uint8List(4)),
        throwsA(isA<app.AppException>()),
      );
    });
  });

  group('AvatarRepository.getCachedAvatarUrl', () {
    test('returns the cached URL when present and unexpired', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);
      await repo.uploadAvatar(userId: 'u', imageBytes: Uint8List(4));

      final cached = repo.getCachedAvatarUrl('u');

      expect(cached, isNotNull);
      // The signed URL replaces the legacy `?v=<timestamp>` cache-bust
      // suffix — assertion shifts to the JWT-bearing signed-URL path.
      expect(cached, contains('/object/sign/'));
    });

    test('returns null when the cached URL has expired', () async {
      // Prime the cache with an URL whose expiry instant is already
      // in the past. The contract: getCachedAvatarUrl filters expired
      // entries so the screen layer doesn't render a dead URL.
      final box = _FakeHiveBox();
      await box.put('avatarUrlCache:u', 'https://stale.test/sign');
      await box.put(
        'avatarUrlCacheExpiresAt:u',
        DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );

      final repo = _makeRepo(box: box);

      expect(repo.getCachedAvatarUrl('u'), isNull);
    });

    test('returns null when no entry exists for the user', () {
      final repo = _makeRepo();

      expect(repo.getCachedAvatarUrl('never-uploaded'), isNull);
    });
  });

  group('AvatarRepository.regenerateSignedUrl', () {
    test('writes a new URL + expiry pair to the cache', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);
      final beforeRegen = DateTime.now().millisecondsSinceEpoch;

      final url = await repo.regenerateSignedUrl('user-xyz');

      expect(url, contains('/object/sign/'));
      expect(box.get('avatarUrlCache:user-xyz'), url);
      final expiry = box.get('avatarUrlCacheExpiresAt:user-xyz') as int;
      const lifetimeMs = AvatarRepository.signedUrlExpirySeconds * 1000;
      expect(expiry, greaterThanOrEqualTo(beforeRegen + lifetimeMs - 1000));
      expect(expiry, lessThanOrEqualTo(beforeRegen + lifetimeMs + 5000));
    });

    test('mints a different token than the previous upload', () async {
      final bucket = _FakeStorageBucket();
      final repo = _makeRepo(bucket: bucket);

      final first = await repo.uploadAvatar(
        userId: 'u',
        imageBytes: Uint8List(4),
      );
      final regenerated = await repo.regenerateSignedUrl('u');

      // Fake increments the counter on each createSignedUrl call —
      // proves the regenerate call hit the storage layer, not just
      // returned the cached value.
      expect(regenerated, isNot(equals(first)));
      expect(bucket.signedUrlCallCount, 2);
    });
  });

  group('AvatarRepository.invalidateCache', () {
    test('removes BOTH the URL and the expiry companion entry', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);
      await repo.uploadAvatar(userId: 'u', imageBytes: Uint8List(4));
      expect(box.containsKey_('avatarUrlCache:u'), isTrue);
      expect(box.containsKey_('avatarUrlCacheExpiresAt:u'), isTrue);

      await repo.invalidateCache('u');

      expect(box.containsKey_('avatarUrlCache:u'), isFalse);
      expect(box.containsKey_('avatarUrlCacheExpiresAt:u'), isFalse);
      expect(repo.getCachedAvatarUrl('u'), isNull);
    });

    test('is idempotent — calling on a missing key does not throw', () async {
      final repo = _makeRepo();

      await expectLater(() => repo.invalidateCache('nobody'), returnsNormally);
    });
  });

  group('AvatarRepository.pathFor', () {
    test('returns nested {userId}/avatar.jpg layout', () {
      // Critical RLS contract: the bucket policy is
      // `(storage.foldername(name))[1] = auth.uid()::text`. A flat
      // `{userId}.jpg` would collapse foldername to [] and every write
      // would be RLS-rejected. See migration 00068 preamble.
      expect(AvatarRepository.pathFor('user-123'), 'user-123/avatar.jpg');
    });
  });
}
