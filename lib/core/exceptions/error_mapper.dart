import 'dart:async' as async;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'app_exception.dart';

class ErrorMapper {
  const ErrorMapper._();

  static AppException mapException(Object error) {
    if (error is supabase.PostgrestException) {
      return _mapPostgrestException(error);
    }
    if (error is supabase.AuthException) {
      return _mapAuthException(error);
    }
    if (error is AppException) {
      return error;
    }
    if (error is async.TimeoutException) {
      // Map the SDK timeout to our domain [TimeoutException] so feature-level
      // mappers can branch on the type — no substring matching against
      // runtimeType-prefixed strings.
      debugPrint('[ErrorMapper] TimeoutException: ${error.message}');
      return const TimeoutException();
    }

    // cluster: jsonb-payload-vs-typed-dart
    // A raw deserialization failure — `_TypeError` from a bad `as` cast or a
    // `CastError` from `.cast<T>()` on a drifted JSON row. Both implement the
    // dart:core `TypeError` interface. These are Dart `Error`s (programmer-
    // /schema-error class), NOT transient `Exception`s. Reclassifying them as
    // `DatabaseException` (instead of letting them fall into the
    // `NetworkException` catch-all) is load-bearing: NetworkException is an
    // `Exception`, so it DEFEATS Riverpod's `defaultRetry` guard
    // (`if (error is Error) return null`) and the failed provider retries on a
    // 200ms×2ⁿ backoff (cap 6.4s) — the mystery slow-load storm the cluster
    // documents. `appProviderRetry` (core/data/app_retry.dart) is the other
    // half of the fix; this branch is the correctness half (typed error with a
    // field-bearing message instead of an opaque cast string).
    if (error is TypeError) {
      debugPrint('[ErrorMapper] Deserialization TypeError: $error');
      return DatabaseException(error.toString(), code: 'deserialization');
    }

    // Log the raw error for debugging; return a safe network exception.
    debugPrint('[ErrorMapper] Unmapped error: $error');
    return const NetworkException('An unexpected error occurred.');
  }

  static DatabaseException _mapPostgrestException(
    supabase.PostgrestException error,
  ) {
    // Log the raw Postgres message for developer debugging only.
    debugPrint(
      '[ErrorMapper] PostgrestException: '
      'code=${error.code}, message=${error.message}',
    );

    // Return a sanitized exception — the userMessage getter on
    // DatabaseException provides the user-facing text.
    // We keep the raw message in the internal `message` field for logging,
    // but UI code must always use `userMessage`.
    return DatabaseException(error.message, code: error.code ?? 'unknown');
  }

  static AuthException _mapAuthException(supabase.AuthException error) {
    debugPrint(
      '[ErrorMapper] AuthException: '
      'statusCode=${error.statusCode}, message=${error.message}',
    );

    return AuthException(error.message, code: error.statusCode ?? 'unknown');
  }
}
