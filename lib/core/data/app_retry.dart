import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../exceptions/app_exception.dart' as app;
import '../offline/sync_error_classifier.dart';

/// Global Riverpod retry predicate.
///
/// cluster: jsonb-payload-vs-typed-dart
///
/// **Why a custom predicate exists.** Riverpod's [ProviderContainer.defaultRetry]
/// retries any thrown value that is NOT a Dart `Error` (its guard is
/// `if (error is ProviderException || error is Error) return null`). Every
/// failure that crosses [BaseRepository.mapException] is reclassified into an
/// [app.AppException] — which `implements Exception`, NOT `Error`. So under the
/// bare default, a transient `NetworkException` AND a permanent
/// `DatabaseException`/`ValidationException`/`AuthException` are ALL retried on
/// the 200ms×2ⁿ (cap 6.4s) backoff. For a deserialization failure (a drifted
/// JSON row that will never parse) that produces the "mystery slow-load" storm
/// the cluster documents: the same broken read retried up to 10× before
/// surfacing the error.
///
/// This predicate inverts the policy to opt-IN: retry ONLY genuinely transient
/// transport/timeout/5xx failures, and decline everything else (return `null`
/// → no retry, error surfaces immediately). The backoff curve itself is still
/// owned by Riverpod — once we've decided a failure is retry-worthy we delegate
/// to [ProviderContainer.defaultRetry] so the delay/maxRetries policy stays in
/// one place.
///
/// Signature matches Riverpod's `Retry = Duration? Function(int retryCount,
/// Object error)`; wired via `ProviderScope(retry: appProviderRetry, ...)` in
/// `main.dart`.
Duration? appProviderRetry(int retryCount, Object error) {
  // Transient = network-class (transport, 5xx, 401 token-refresh) OR an
  // explicit timeout. [SyncErrorClassifier.isNetworkClass] already treats
  // [app.TimeoutException] as network-class, but we name it explicitly so the
  // intent reads clearly and so a future narrowing of `isNetworkClass` can't
  // silently drop timeout retries.
  final transient =
      error is app.TimeoutException ||
      SyncErrorClassifier.isNetworkClass(error);
  if (!transient) return null;

  // Delegate the actual backoff/maxRetries policy to Riverpod's default.
  return ProviderContainer.defaultRetry(retryCount, error);
}
