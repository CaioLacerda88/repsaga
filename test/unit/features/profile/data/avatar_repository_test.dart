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
  String? lastPublicUrlPath;

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
  String getPublicUrl(String path, {supabase.TransformOptions? transform}) {
    lastPublicUrlPath = path;
    return 'https://supabase.test/storage/v1/object/public/avatars/$path';
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

    test('returns a URL with a `?v=<millis>` cache-bust suffix', () async {
      final repo = _makeRepo();

      final url = await repo.uploadAvatar(
        userId: 'user-123',
        imageBytes: Uint8List(8),
      );

      expect(url, contains('?v='));
      final query = Uri.parse(url).queryParameters['v'];
      expect(query, isNotNull);
      expect(int.tryParse(query!), isNotNull);
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
    test('returns the cached URL when present', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);
      await repo.uploadAvatar(userId: 'u', imageBytes: Uint8List(4));

      final cached = repo.getCachedAvatarUrl('u');

      expect(cached, isNotNull);
      expect(cached, contains('?v='));
    });

    test('returns null when no entry exists for the user', () {
      final repo = _makeRepo();

      expect(repo.getCachedAvatarUrl('never-uploaded'), isNull);
    });
  });

  group('AvatarRepository.invalidateCache', () {
    test('removes the cache entry for the user', () async {
      final box = _FakeHiveBox();
      final repo = _makeRepo(box: box);
      await repo.uploadAvatar(userId: 'u', imageBytes: Uint8List(4));
      expect(repo.getCachedAvatarUrl('u'), isNotNull);

      await repo.invalidateCache('u');

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
