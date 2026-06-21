import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/data/app_retry.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;

void main() {
  group('appProviderRetry', () {
    test('retries a NetworkException (transient transport failure)', () {
      const error = app.NetworkException('offline');

      final delay = appProviderRetry(0, error);

      expect(delay, isNotNull);
    });

    test('retries an app.TimeoutException', () {
      const error = app.TimeoutException();

      final delay = appProviderRetry(0, error);

      expect(delay, isNotNull);
    });

    test('retries a 5xx DatabaseException (server-class network failure)', () {
      // SyncErrorClassifier.isNetworkClass treats 5xx codes as network-class.
      const error = app.DatabaseException('upstream down', code: '503');

      final delay = appProviderRetry(0, error);

      expect(delay, isNotNull);
    });

    test('does NOT retry a deserialization DatabaseException', () {
      // cluster: jsonb-payload-vs-typed-dart — the storm fix. A drifted JSON
      // row that will never parse must surface immediately, not retry 10×.
      const error = app.DatabaseException(
        'type Null is not a subtype of String',
        code: 'deserialization',
      );

      final delay = appProviderRetry(0, error);

      expect(delay, isNull);
    });

    test('does NOT retry a 4xx DatabaseException (domain error)', () {
      const error = app.DatabaseException('not found', code: '404');

      final delay = appProviderRetry(0, error);

      expect(delay, isNull);
    });

    test('does NOT retry a ValidationException', () {
      const error = app.ValidationException('name taken', field: 'name');

      final delay = appProviderRetry(0, error);

      expect(delay, isNull);
    });

    test('does NOT retry an AuthException (non-401)', () {
      const error = app.AuthException('invalid creds', code: '400');

      final delay = appProviderRetry(0, error);

      expect(delay, isNull);
    });

    test('does NOT retry a raw Dart Error', () {
      final error = ArgumentError('bad arg');

      final delay = appProviderRetry(0, error);

      expect(delay, isNull);
    });

    test('delegates the backoff curve to ProviderContainer.defaultRetry for '
        'transient errors', () {
      // The first-retry delay for a retry-worthy error must match Riverpod's
      // default backoff exactly — proving we delegate the curve rather than
      // inventing our own.
      const error = app.NetworkException('offline');

      final ours = appProviderRetry(0, error);
      final theirs = ProviderContainer.defaultRetry(0, error);

      expect(ours, theirs);
      expect(ours, isNotNull);
    });
  });
}
