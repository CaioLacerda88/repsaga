import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class _TestRepository extends BaseRepository {
  const _TestRepository();
}

/// Test recorder that captures every recorded call so tests can assert
/// against the [BaseRepository.mapException] success / failure side effects.
class _RecordingRecorder implements ConnectivityRecoveryRecorder {
  int successCount = 0;
  final List<Object> failures = [];

  @override
  void recordSuccess() {
    successCount++;
  }

  @override
  void recordFailure(Object error) {
    failures.add(error);
  }
}

class _RepoWithRecorder extends BaseRepository {
  const _RepoWithRecorder({super.recoveryRecorder});
}

void main() {
  const repo = _TestRepository();

  group('BaseRepository.mapException', () {
    test('returns the result of a successful action', () async {
      final result = await repo.mapException(() async => 42);

      expect(result, 42);
    });

    test('rethrows AppException subtypes unchanged', () async {
      final exceptions = <AppException>[
        const AuthException('Unauthorized', code: '401'),
        const DatabaseException('Row not found', code: '404'),
        const NetworkException('No internet'),
        const ValidationException('Required', field: 'name'),
      ];

      for (final exception in exceptions) {
        await expectLater(
          () => repo.mapException(() async => throw exception),
          throwsA(same(exception)),
        );
      }
    });

    test('converts PostgrestException to DatabaseException', () async {
      const error = supabase.PostgrestException(
        message: 'Unique constraint violation',
        code: '23505',
      );

      await expectLater(
        () => repo.mapException(() async => throw error),
        throwsA(
          isA<DatabaseException>()
              .having(
                (e) => e.message,
                'message',
                'Unique constraint violation',
              )
              .having((e) => e.code, 'code', '23505'),
        ),
      );
    });

    test('converts AuthApiException to AuthException', () async {
      final error = supabase.AuthApiException(
        'Invalid credentials',
        statusCode: '401',
      );

      await expectLater(
        () => repo.mapException(() async => throw error),
        throwsA(
          isA<AuthException>()
              .having((e) => e.message, 'message', 'Invalid credentials')
              .having((e) => e.code, 'code', '401'),
        ),
      );
    });

    test('converts unknown exception to NetworkException', () async {
      final error = Exception('Something went wrong');

      await expectLater(
        () => repo.mapException(() async => throw error),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            'An unexpected error occurred.',
          ),
        ),
      );
    });
  });

  group('BaseRepository recovery recorder integration', () {
    test('recordSuccess fires on a successful action', () async {
      final recorder = _RecordingRecorder();
      final repo = _RepoWithRecorder(recoveryRecorder: recorder);

      await repo.mapException(() async => 1);
      await repo.mapException(() async => 2);

      expect(recorder.successCount, 2);
      expect(recorder.failures, isEmpty);
    });

    test(
      'recordFailure receives the wrapped AppException for already-mapped errors',
      () async {
        final recorder = _RecordingRecorder();
        final repo = _RepoWithRecorder(recoveryRecorder: recorder);

        const wrapped = NetworkException('no connection');
        await expectLater(
          () => repo.mapException(() async => throw wrapped),
          throwsA(same(wrapped)),
        );

        expect(recorder.successCount, 0);
        expect(recorder.failures, [same(wrapped)]);
      },
    );

    test('recordFailure receives the raw error before mapping', () async {
      // Raw transport-level errors carry richer type information than
      // their mapped forms (the mapper collapses SocketException →
      // NetworkException with a generic message). Forward the raw shape
      // so the classifier can branch on the specific runtime type.
      final recorder = _RecordingRecorder();
      final repo = _RepoWithRecorder(recoveryRecorder: recorder);

      const rawError = SocketException('refused');
      await expectLater(
        () => repo.mapException(() async => throw rawError),
        throwsA(isA<NetworkException>()),
      );

      expect(recorder.failures, [same(rawError)]);
    });

    test('null recorder leaves all paths working (no crash)', () async {
      // Without an injected recorder, both the success and failure paths
      // must remain unchanged — recording is strictly additive.
      const repo = _RepoWithRecorder();

      expect(await repo.mapException(() async => 5), 5);
      await expectLater(
        () => repo.mapException(() async => throw Exception('boom')),
        throwsA(isA<NetworkException>()),
      );
    });

    test('PostgrestException records the raw error before mapping', () async {
      final recorder = _RecordingRecorder();
      final repo = _RepoWithRecorder(recoveryRecorder: recorder);

      const error = supabase.PostgrestException(
        message: 'Service Unavailable',
        code: '503',
      );

      await expectLater(
        () => repo.mapException(() async => throw error),
        throwsA(isA<DatabaseException>()),
      );

      expect(recorder.failures, [same(error)]);
    });
  });
}
