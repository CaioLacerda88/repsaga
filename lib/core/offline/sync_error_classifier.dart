import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../exceptions/app_exception.dart' as app;

/// Classifies sync errors as transient (retry-worthy) or terminal (give up).
///
/// Terminal errors are client-side mistakes (4xx) that will never succeed on
/// retry. Transient errors are server-side (5xx), network, or auth-token
/// issues that may resolve on their own.
///
/// **Why both raw and wrapped types are recognised:** repository call sites
/// run through `BaseRepository.mapException`, which converts
/// [supabase.PostgrestException] into [app.DatabaseException] (preserving
/// the HTTP status in the `code` field) and SDK [TimeoutException] into
/// [app.TimeoutException]. The active-workout notifier's catch site (PR1B,
/// AW-EX-D-US1-03) sees the wrapped form; the sync-service drain loop sees
/// the raw form (mocked tests pin both shapes). Classifying both keeps the
/// catch sites correct regardless of where in the stack the exception is
/// observed.
abstract final class SyncErrorClassifier {
  static const _terminalCodes = {400, 403, 404, 409, 422};

  /// Returns `true` if [error] is a terminal error that should not be retried.
  static bool isTerminal(Object error) {
    if (error is supabase.PostgrestException) {
      final code = int.tryParse(error.code ?? '');
      return code != null && _terminalCodes.contains(code);
    }
    if (error is app.DatabaseException) {
      // ErrorMapper preserves the raw Postgrest code on DatabaseException.code
      // — same numeric set determines terminal vs transient.
      final code = int.tryParse(error.code);
      return code != null && _terminalCodes.contains(code);
    }
    // Network, timeout, and auth-token errors are transient. Both raw
    // (dart:async / dart:io / supabase) and wrapped (app.*) variants land
    // in the same bucket.
    if (error is SocketException) return false;
    if (error is TimeoutException) return false;
    if (error is supabase.AuthException) return false;
    if (error is app.AuthException) return false;
    if (error is app.NetworkException) return false;
    if (error is app.TimeoutException) return false;
    // Unknown errors default to transient so the queue retries them.
    return false;
  }
}
