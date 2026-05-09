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

  /// Extracts the HTTP-style code from a known error shape, returning
  /// `null` if the error type isn't recognised or the code can't be
  /// parsed. Recognises both raw [supabase.PostgrestException] and the
  /// wrapped [app.DatabaseException] / [app.AuthException] forms — the
  /// same set of code-bearing shapes that [isTerminal] discriminates,
  /// keeping a single canonical place for HTTP-code extraction so call
  /// sites don't drift if a new wrapped form is added later.
  static int? httpCode(Object error) {
    if (error is supabase.PostgrestException) {
      return int.tryParse(error.code ?? '');
    }
    if (error is app.DatabaseException) return int.tryParse(error.code);
    if (error is app.AuthException) return int.tryParse(error.code);
    return null;
  }

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

  /// Returns `true` if [error] looks like a network/transport/server-class
  /// failure rather than a domain (4xx) error.
  ///
  /// Used by [ConnectivityRecoveryNotifier] to decide whether a repository
  /// failure should arm the recovery signal. A 4xx domain error means the
  /// server WAS reachable enough to return a structured response — the
  /// network is healthy; recording it as a network failure would falsely
  /// trigger a drain on the next successful unrelated call.
  ///
  /// Conservative for unknown shapes: defaults to `false` so an unrecognised
  /// exception type cannot accidentally trigger the recovery hook and start
  /// a retry storm.
  static bool isNetworkClass(Object error) {
    // Raw transport-layer errors.
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    // Wrapped equivalents emitted by [BaseRepository.mapException].
    if (error is app.NetworkException) return true;
    if (error is app.TimeoutException) return true;
    // Auth-token refresh class — 401 / "JWT expired" — is transient and
    // generally clears once the SDK refreshes the session. Treat as network
    // class so a successful retry trips recovery.
    if (error is supabase.AuthException) return true;
    if (error is app.AuthException) return true;
    // Server-class HTTP failures (5xx, including 502/503 captive-portal
    // recovery shapes). 4xx are domain errors — explicitly excluded.
    final code = httpCode(error);
    if (code != null && code >= 500 && code < 600) return true;
    return false;
  }
}
