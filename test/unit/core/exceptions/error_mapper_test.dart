import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/exceptions/error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('ErrorMapper.mapException', () {
    test('should map PostgrestException to DatabaseException', () {
      const error = supabase.PostgrestException(
        message: 'Row not found',
        code: '404',
      );

      final result = ErrorMapper.mapException(error);

      expect(result, isA<DatabaseException>());
      expect(result.message, 'Row not found');
      expect((result as DatabaseException).code, '404');
    });

    test('should map PostgrestException with null code to "unknown"', () {
      const error = supabase.PostgrestException(message: 'DB error');

      final result = ErrorMapper.mapException(error);

      expect(result, isA<DatabaseException>());
      expect((result as DatabaseException).code, 'unknown');
    });

    test('should map AuthApiException to AuthException', () {
      final error = supabase.AuthApiException(
        'Invalid login',
        statusCode: '401',
      );

      final result = ErrorMapper.mapException(error);

      expect(result, isA<AuthException>());
      expect(result.message, 'Invalid login');
      expect((result as AuthException).code, '401');
    });

    test('should map AuthApiException with null statusCode to "unknown"', () {
      final error = supabase.AuthApiException('Auth error');

      final result = ErrorMapper.mapException(error);

      expect(result, isA<AuthException>());
      expect((result as AuthException).code, 'unknown');
    });

    test('should pass through existing AppException unchanged', () {
      const error = NetworkException('No internet');

      final result = ErrorMapper.mapException(error);

      expect(result, same(error));
    });

    test('should map generic exception to NetworkException', () {
      final error = Exception('Something went wrong');

      final result = ErrorMapper.mapException(error);

      expect(result, isA<NetworkException>());
    });

    test('should map non-Exception errors to NetworkException', () {
      const error = 'raw string error';

      final result = ErrorMapper.mapException(error);

      expect(result, isA<NetworkException>());
    });

    // cluster: jsonb-payload-vs-typed-dart
    // Deserialization failures (a `_TypeError` from a bad `as` cast, a
    // `CastError` from `.cast<T>()`) must reclassify to a DatabaseException
    // with code 'deserialization' so they are NOT retried by Riverpod's
    // default backoff (the mystery slow-load storm). A NetworkException here
    // would defeat Riverpod's `if (error is Error) return null` guard.
    test('should map a _TypeError (bad as cast) to DatabaseException', () {
      // Force a real `_TypeError` (which implements dart:core `TypeError`).
      TypeError? thrown;
      try {
        final dynamic value = <String, dynamic>{'x': 1};
        value as List<int>; // throws _TypeError
      } on TypeError catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);

      final result = ErrorMapper.mapException(thrown!);

      expect(result, isA<DatabaseException>());
      expect((result as DatabaseException).code, 'deserialization');
    });

    test('should map a CastError (.cast<T>) to DatabaseException', () {
      // `.cast<int>()` on a list holding a String throws a CastError, which
      // also implements dart:core `TypeError`.
      TypeError? thrown;
      try {
        final list = <Object>['not-an-int'].cast<int>();
        // The cast is lazy — force the element access that triggers the error.
        // ignore: unused_local_variable
        final first = list.first;
      } on TypeError catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);

      final result = ErrorMapper.mapException(thrown!);

      expect(result, isA<DatabaseException>());
      expect((result as DatabaseException).code, 'deserialization');
    });
  });

  group('ErrorMapper produces safe userMessages', () {
    test('DatabaseException userMessage never contains table names', () {
      // Simulate a Postgres error that leaks table name and column info.
      const error = supabase.PostgrestException(
        message:
            'update or delete on table "sets" violates foreign key constraint '
            '"personal_records_set_id_fkey" on table "personal_records"',
        code: '23503',
      );

      final result = ErrorMapper.mapException(error);

      expect(result, isA<DatabaseException>());
      // The internal message may contain the raw error (for logging),
      // but userMessage must be safe.
      expect(result.userMessage, 'Something went wrong. Please try again.');
      expect(result.userMessage, isNot(contains('sets')));
      expect(result.userMessage, isNot(contains('personal_records')));
      expect(result.userMessage, isNot(contains('foreign key')));
    });

    test('AuthException userMessage never contains internal details', () {
      final error = supabase.AuthApiException(
        'Database error querying schema "auth"."users"',
        statusCode: '500',
      );

      final result = ErrorMapper.mapException(error);

      expect(result, isA<AuthException>());
      expect(result.userMessage, 'Authentication error. Please log in again.');
      expect(result.userMessage, isNot(contains('schema')));
      expect(result.userMessage, isNot(contains('auth')));
      expect(result.userMessage, isNot(contains('users')));
    });

    test('NetworkException userMessage is generic', () {
      final result = ErrorMapper.mapException(
        Exception('SocketException: Connection refused'),
      );

      expect(result, isA<NetworkException>());
      expect(
        result.userMessage,
        'No internet connection. Please check your network.',
      );
      expect(result.userMessage, isNot(contains('Socket')));
    });

    test('ValidationException userMessage exposes the validation text', () {
      const error = ValidationException(
        'Exercise name already exists',
        field: 'name',
      );

      final result = ErrorMapper.mapException(error);

      // ValidationException passes through; its userMessage IS the message.
      expect(result, same(error));
      expect(result.userMessage, 'Exercise name already exists');
    });

    test('unmapped error produces safe generic message', () {
      final result = ErrorMapper.mapException(42);

      expect(result, isA<NetworkException>());
      expect(result.userMessage, isNot(contains('42')));
    });
  });
}
