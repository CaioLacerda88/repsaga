import 'dart:async';

import 'package:flutter/foundation.dart' show protected;
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/exceptions/error_mapper.dart';
import 'package:repsaga/core/observability/sentry_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Riverpod-agnostic interface that [BaseRepository] uses to feed signals
/// into the connectivity recovery state machine. The production
/// implementation (`_RiverpodConnectivityRecoveryRecorder` in
/// `recovery_recorder_provider.dart`) forwards to
/// `connectivityRecoveryProvider`. Tests pass `null` (default) to keep
/// fixtures unchanged.
///
/// Living here, alongside [BaseRepository], avoids a circular import between
/// the data and connectivity layers. The connectivity-side notifier remains
/// the source of truth; this interface is just the call surface.
abstract class ConnectivityRecoveryRecorder {
  /// Record a repository success. Safe to call on every successful call —
  /// implementations are responsible for filtering down to actual recovery
  /// signals (the failure-window + cooldown live in the implementation).
  void recordSuccess();

  /// Record a repository failure. Implementations are responsible for
  /// classifying the error — only network-class failures should arm the
  /// recovery window.
  void recordFailure(Object error);
}

abstract class BaseRepository {
  const BaseRepository({this.recoveryRecorder});

  /// Optional hook into the connectivity recovery state machine. Provider
  /// factories wire a real recorder; tests pass `null` (the default) and
  /// the success/failure side-effects become no-ops.
  final ConnectivityRecoveryRecorder? recoveryRecorder;

  /// Wraps a Supabase call and maps exceptions to [AppException] types.
  ///
  /// [AppException]s are rethrown unchanged (they are expected domain errors
  /// — double-reporting them to Sentry would flood the tracker). Unexpected
  /// errors (raw Supabase/network/system) are fire-and-forget captured to
  /// Sentry before being mapped and thrown as an AppException subclass.
  ///
  /// **Recovery side-effects.** A successful call calls
  /// [ConnectivityRecoveryRecorder.recordSuccess] (which is a no-op without
  /// a recent recorded failure). A failed call forwards the underlying error
  /// to [ConnectivityRecoveryRecorder.recordFailure] — including ALL
  /// [AppException] subtypes (validation, database, network, timeout, auth).
  /// The recorder is the single canonical filter: its
  /// `SyncErrorClassifier.isNetworkClass` check decides which shapes
  /// actually arm the recovery window. Domain errors (`ValidationException`,
  /// `DatabaseException` with 4xx code) reach the recorder but are dropped
  /// by that filter, so they never trigger a false recovery signal. This
  /// keeps the classification logic in one place — `mapException` does not
  /// duplicate or pre-filter it.
  Future<T> mapException<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      recoveryRecorder?.recordSuccess();
      return result;
    } on AppException catch (e) {
      // Forward to the recorder so it can filter on the wrapped shape
      // (e.g. app.DatabaseException with code: '500' is network-class;
      // app.ValidationException is not). The recorder's classifier is
      // the single canonical filter — never duplicate logic here.
      recoveryRecorder?.recordFailure(e);
      rethrow;
    } catch (e, st) {
      // Raw / unmapped error — record before mapping so the classifier
      // can branch on the raw runtime type if it's more specific than the
      // mapped form (e.g. SocketException → app.NetworkException loses the
      // socket-level detail; we want to record on the richer shape).
      recoveryRecorder?.recordFailure(e);
      unawaited(SentryReport.captureException(e, stackTrace: st));
      throw ErrorMapper.mapException(e);
    }
  }

  /// Runs [action] and, on a SINGLE failure shape (PostgREST `42501` /
  /// `AuthException` `401`), calls [refresh] once and retries [action] one
  /// time. Bounded — exactly one retry, no exponential backoff, no queue.
  ///
  /// On the retry-success branch, emits a Sentry breadcrumb
  /// `auth.session_refreshed_inline` so the trail records that this user
  /// dodged an RLS rejection without surfacing the failure to the UI.
  ///
  /// **Original-error semantics.** If the retried action ALSO fails, the
  /// ORIGINAL error (not the retry's error) is rethrown — callers want to
  /// see the first failure shape, not a derivative one. If [refresh] itself
  /// throws, the original error rethrows likewise (refresh failure is
  /// strictly internal to the helper).
  ///
  /// **Cluster reference.** This helper closes a close analog of the
  /// `async-caller-broke-snackbar` cluster (PROJECT.md §0 Cluster Ledger):
  /// an auth-state mutation (token expiry) that lands between caller-await
  /// and side-effect read. The retry is a structural guarantee — no
  /// `_hasRetried` boolean flag — because [refreshAndRetry] only invokes
  /// the inner refresh+retry path once per call to itself, and never
  /// recurses. A successor cluster `stale-token-silent-anon-fallback` may
  /// emerge if the broken-deep-link scenario recurs across other flows;
  /// the auto-memory entry would document the pattern + grep handle.
  ///
  /// Trigger is intentionally narrow:
  ///   * [supabase.PostgrestException] with `code == '42501'`
  ///     (RLS row rejected — the row-level security policy didn't see
  ///     the user's JWT, usually because the bearer was stale / anon).
  ///   * [supabase.AuthException] with `statusCode == '401'`
  ///     (gotrue rejected the bearer outright — JWT expired or revoked).
  /// Every other shape (e.g. PostgREST `23505` unique violation) is
  /// rethrown immediately with no retry and no refresh attempt.
  @protected
  Future<T> refreshAndRetry<T>({
    required Future<T> Function() action,
    required Future<void> Function() refresh,
  }) async {
    try {
      return await action();
    } catch (originalError, originalStack) {
      if (!_isStaleTokenFailure(originalError)) {
        Error.throwWithStackTrace(originalError, originalStack);
      }
      try {
        await refresh();
      } catch (_) {
        // refresh failed → surface ORIGINAL error, not the refresh error.
        // The caller is interested in the action's failure shape, not the
        // refresh helper's internals.
        Error.throwWithStackTrace(originalError, originalStack);
      }
      try {
        final retried = await action();
        SentryReport.addBreadcrumb(
          category: 'auth',
          message: 'session_refreshed_inline',
        );
        return retried;
      } catch (_) {
        // Retry attempt failed too → surface the ORIGINAL error so the
        // caller sees the first failure shape (no double-wrap, no
        // derivative-error confusion).
        Error.throwWithStackTrace(originalError, originalStack);
      }
    }
  }

  /// Whether [error] matches the stale-token shape that warrants a single
  /// refresh-and-retry attempt. Pinned narrowly — PostgREST `42501` (RLS
  /// rejection) and gotrue `401` (JWT outright rejected) — to keep the
  /// retry trigger structurally bounded.
  bool _isStaleTokenFailure(Object error) {
    if (error is supabase.PostgrestException && error.code == '42501') {
      return true;
    }
    if (error is supabase.AuthException && error.statusCode == '401') {
      return true;
    }
    return false;
  }
}
