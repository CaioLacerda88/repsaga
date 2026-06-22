import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../exceptions/app_exception.dart' as app;

/// Classifies sync errors as transient (retry-worthy) or terminal (give up).
///
/// Terminal errors are deterministic data/permission failures that will fail
/// IDENTICALLY on replay (malformed payload, constraint violation, RLS
/// denial, missing schema object, malformed PostgREST request). Transient
/// errors are server-side (5xx), network, lock/serialization conflicts, or
/// auth-token issues that may resolve on their own.
///
/// **Code shape (important — this is what the original classifier got
/// wrong):** [supabase.PostgrestException.code] (and the
/// [app.DatabaseException.code] that `ErrorMapper` copies verbatim from it)
/// is the **Postgres SQLSTATE** (`22P02`, `23505`, `42501`, …) or a
/// **`PGRST*`** code — NEVER a parseable HTTP integer. The earlier
/// implementation did `int.tryParse(error.code)` against an HTTP-code set
/// `{400,403,404,409,422}`; in production that parse is always `null`, so
/// every real structural error was mis-classified TRANSIENT and the terminal
/// fast-path was dead (broken actions retried up to `kMaxSyncRetries` before
/// the retry-count ceiling dropped them). The unit tests passed only because
/// they injected mock `PostgrestException(code:'409')` shapes that never
/// occur in production. cluster: classifier-keyed-on-http-not-sqlstate.
///
/// **Why a dedicated SQLSTATE allow-set and NOT
/// `SyncErrorMapper.classifyCategory`:** that mapper tags ALL
/// Postgrest/DatabaseException as `structural` for UI-CTA purposes, which is
/// too coarse for terminal-ness — a `40001` serialization conflict, a `40P01`
/// deadlock, or a 5xx wrapped as `DatabaseException` is `structural`-category
/// but MUST keep retrying. Deriving terminal from `structural` would start
/// dropping actions that currently succeed on retry. So `errorCategory` stays
/// the UI concern; this allow-set is the single source of terminal-ness.
///
/// **Conservative invariant:** any code not in [_terminalSqlStates] (and any
/// unrecognised error shape) stays TRANSIENT — we only add terminal
/// classification for codes that deterministically fail on identical replay.
/// This guarantees the fix never newly-drops an action that the old behavior
/// would have eventually committed.
///
/// **Why both raw and wrapped types are recognised:** repository call sites
/// run through `BaseRepository.mapException`, which converts
/// [supabase.PostgrestException] into [app.DatabaseException] (copying the
/// SQLSTATE/PGRST code into the `code` field) and SDK [TimeoutException] into
/// [app.TimeoutException]. The active-workout notifier's catch site (PR1B,
/// AW-EX-D-US1-03) sees the wrapped form; the sync-service drain loop sees
/// the raw form. Classifying both keeps the catch sites correct regardless of
/// where in the stack the exception is observed.
abstract final class SyncErrorClassifier {
  /// SQLSTATE / sentinel codes that are TERMINAL — an identical replay will
  /// always fail, so retrying wastes round-trips. Each is justified inline.
  static const _terminalSqlStates = <String>{
    '22P02', // invalid_text_representation (e.g. malformed UUID in payload)
    '23502', // not_null_violation — required column missing in payload
    '23503', // foreign_key_violation — referenced row doesn't/won't exist
    '23505', // unique_violation — duplicate key; replay collides identically
    '23514', // check_violation — payload breaks a CHECK invariant
    '42501', // insufficient_privilege — RLS rejected the row; won't self-heal
    '42P01', // undefined_table — schema object missing; deploy-time error
    '42703', // undefined_column — payload targets a column that doesn't exist
    // ErrorMapper sentinel: a Dart TypeError during deserialization is a
    // malformed-payload / schema-drift bug — the same bytes won't reshape on
    // retry. (ErrorMapper sets DatabaseException(code: 'deserialization').)
    'deserialization',
  };

  /// `true` when [code] is a PostgREST request/schema-cache error
  /// (`PGRST100`, `PGRST202`, `PGRST204`, …). These are deterministic
  /// malformed-request / missing-RPC / stale-schema-cache failures — an
  /// identical replay reproduces them, so they are terminal.
  static bool _isTerminalPgrst(String code) => code.startsWith('PGRST');

  static bool _isTerminalCode(String code) =>
      _terminalSqlStates.contains(code) || _isTerminalPgrst(code);

  /// Extracts the HTTP-style status code from an error shape that actually
  /// carries one, returning `null` otherwise.
  ///
  /// **Only [app.AuthException] / [supabase.AuthException] carry a real HTTP
  /// code** — `ErrorMapper` copies gotrue's `statusCode` (`'401'`, `'400'`,
  /// …) into the wrapped form. [supabase.PostgrestException] /
  /// [app.DatabaseException] carry the SQLSTATE/PGRST code (NOT an HTTP int),
  /// so this returns `null` for them — callers that want terminal-ness must
  /// use [isTerminal], not this helper. Kept as the single canonical place
  /// for HTTP-code extraction (the 5xx copy variant + the recovery-window
  /// 401 check) so those call sites don't reimplement the parse.
  static int? httpCode(Object error) {
    if (error is supabase.PostgrestException) {
      // SQLSTATE/PGRST, never an HTTP int — int.tryParse yields null, which
      // is the correct answer: a Postgrest error has no HTTP-status meaning
      // for the 5xx-copy / recovery-window consumers.
      return int.tryParse(error.code ?? '');
    }
    if (error is app.DatabaseException) return int.tryParse(error.code);
    if (error is app.AuthException) return int.tryParse(error.code);
    return null;
  }

  /// Returns `true` if [error] is a terminal error that should not be retried.
  ///
  /// Conservative: only codes in [_terminalSqlStates] / `PGRST*` are terminal;
  /// every other code and every unrecognised shape is transient.
  static bool isTerminal(Object error) {
    if (error is supabase.PostgrestException) {
      final code = error.code;
      return code != null && _isTerminalCode(code);
    }
    if (error is app.DatabaseException) {
      // ErrorMapper copies the raw SQLSTATE/PGRST code onto
      // DatabaseException.code — same allow-set determines terminal.
      return _isTerminalCode(error.code);
    }
    // Network, timeout, and auth-token errors are transient. Both raw
    // (dart:async / dart:io / supabase) and wrapped (app.*) variants land
    // in the same bucket — auth-401 self-heals via SDK token refresh,
    // network/timeout resolve when connectivity returns.
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
    // Auth-token refresh class — only 401 ("JWT expired" / unauthenticated).
    // The SDK refreshes the session and the next call typically succeeds,
    // so trip recovery on retry. Permanent domain errors (invalid creds:
    // 400, email-not-confirmed: 400/403, weak password: 422, rate-limited:
    // 429, ...) MUST NOT arm the window — they will never self-heal and
    // would cause every login attempt to falsely trigger a drain after a
    // network blip.
    //
    // gotrue's [supabase.AuthException] exposes [statusCode] (String?) for
    // the HTTP code; the wrapped [app.AuthException] stores it on [code].
    if (error is supabase.AuthException) {
      return error.statusCode == '401';
    }
    if (error is app.AuthException) {
      return error.code == '401';
    }
    // Server-class HTTP failures (5xx, including 502/503 captive-portal
    // recovery shapes). 4xx are domain errors — explicitly excluded.
    final code = httpCode(error);
    if (code != null && code >= 500 && code < 600) return true;
    return false;
  }
}
