import 'dart:async';

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
    if (error is TimeoutException) {
      // Surface as a NetworkException whose message contains the literal
      // word `timeout` so feature-level mappers (e.g.
      // `AuthErrorMessages.fromError`) can substring-match on it and surface
      // the localized "Request timed out" copy. Keep the literal substring
      // `timeout` (not `timed out`) — the matcher does not stem.
      debugPrint('[ErrorMapper] TimeoutException: ${error.message}');
      return const NetworkException('Request timeout.');
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
