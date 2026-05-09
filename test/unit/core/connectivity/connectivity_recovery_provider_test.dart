import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/connectivity/connectivity_recovery_provider.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;

void main() {
  group('ConnectivityRecoveryNotifier', () {
    late ProviderContainer container;
    late ConnectivityRecoveryNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      notifier = container.read(connectivityRecoveryProvider.notifier);
    });

    test('initial tick is 0', () {
      expect(container.read(connectivityRecoveryProvider), 0);
    });

    test(
      'recordSuccess WITHOUT a recent failure does not increment the tick',
      () {
        // No failure recorded — success is a no-op.
        notifier.recordSuccess();
        notifier.recordSuccess();

        expect(container.read(connectivityRecoveryProvider), 0);
      },
    );

    test(
      'recordSuccess after recordFailure within 5min increments the tick',
      () {
        withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
          notifier.recordFailure(const SocketException('refused'));
        });

        // 30s later — well within the 5-min window.
        withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 30)), () {
          notifier.recordSuccess();
        });

        expect(container.read(connectivityRecoveryProvider), 1);
      },
    );

    test('recordSuccess after stale (5min+) failure does not increment', () {
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
        notifier.recordFailure(const SocketException('refused'));
      });

      // 6 minutes later — the failure is stale.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 6, 0)), () {
        notifier.recordSuccess();
      });

      expect(container.read(connectivityRecoveryProvider), 0);
    });

    test(
      'recordSuccess at exactly 5min boundary still fires (window inclusive)',
      () {
        // Pins the strict-greater-than (`>`) check in `recordSuccess`. A future
        // refactor flipping to `>=` would silently change boundary semantics
        // (T+5min would become stale instead of valid) — this test catches
        // that drift.
        withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
          notifier.recordFailure(const SocketException('refused'));
        });
        withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 5, 0)), () {
          notifier.recordSuccess();
        });
        expect(container.read(connectivityRecoveryProvider), 1);
      },
    );

    test('two recordSuccess calls within 5s only fire once (cooldown)', () {
      // Failure at T0.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
        notifier.recordFailure(const SocketException('refused'));
      });

      // First success — fires.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 10)), () {
        notifier.recordSuccess();
      });
      expect(container.read(connectivityRecoveryProvider), 1);

      // A new failure to set up the second potential trigger.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 12)), () {
        notifier.recordFailure(const SocketException('refused'));
      });

      // Second success 3s after the first trigger — within cooldown.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 13)), () {
        notifier.recordSuccess();
      });

      expect(container.read(connectivityRecoveryProvider), 1);
    });

    test('after cooldown elapses a new success fires again', () {
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
        notifier.recordFailure(const SocketException('refused'));
      });
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 10)), () {
        notifier.recordSuccess();
      });
      expect(container.read(connectivityRecoveryProvider), 1);

      // New failure at T+12s.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 12)), () {
        notifier.recordFailure(const SocketException('refused'));
      });
      // 6 seconds after the first trigger — cooldown elapsed.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 16)), () {
        notifier.recordSuccess();
      });

      expect(container.read(connectivityRecoveryProvider), 2);
    });

    test('domain (non-network) errors are not recorded as failures', () {
      // A 400 / 422 / validation failure must NOT be treated as a recent
      // network failure. If the next successful call is unrelated, it must
      // not falsely trigger the recovery hook.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
        notifier.recordFailure(
          const app.ValidationException('Required', field: 'name'),
        );
        notifier.recordFailure(
          const app.DatabaseException('Bad Request', code: '400'),
        );
      });

      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 30)), () {
        notifier.recordSuccess();
      });

      expect(container.read(connectivityRecoveryProvider), 0);
    });

    test('5xx and timeout errors are recorded as failures', () {
      // Server-class and timeout are network-class — they ARE failures.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
        notifier.recordFailure(const app.DatabaseException('ISE', code: '500'));
      });
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 5)), () {
        notifier.recordSuccess();
      });
      expect(container.read(connectivityRecoveryProvider), 1);

      // Reset for a second probe.
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 1, 0)), () {
        notifier.recordFailure(TimeoutException('timed out'));
      });
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 1, 5)), () {
        notifier.recordSuccess();
      });
      expect(container.read(connectivityRecoveryProvider), 2);
    });

    test('suppression flag prevents recording from re-entrant drain calls', () {
      // While SyncService is mid-drain its own repository requests would
      // otherwise feed back into the recorder, causing a storm. The
      // suppression flag, set by SyncService around its drain loop, must
      // make both recordSuccess and recordFailure no-ops.
      notifier.setRecordingSuppressed(true);

      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 0)), () {
        notifier.recordFailure(const SocketException('refused'));
      });
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 10)), () {
        notifier.recordSuccess();
      });

      expect(container.read(connectivityRecoveryProvider), 0);

      // Re-enabling restores normal behaviour.
      notifier.setRecordingSuppressed(false);
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 11)), () {
        notifier.recordFailure(const SocketException('refused'));
      });
      withClock(Clock.fixed(DateTime.utc(2026, 1, 1, 12, 0, 20)), () {
        notifier.recordSuccess();
      });
      expect(container.read(connectivityRecoveryProvider), 1);
    });
  });
}
