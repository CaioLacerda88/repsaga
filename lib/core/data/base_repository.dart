import 'dart:async';

import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/exceptions/error_mapper.dart';
import 'package:repsaga/core/observability/sentry_report.dart';

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
}
