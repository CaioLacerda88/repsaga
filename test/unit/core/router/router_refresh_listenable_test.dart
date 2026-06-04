/// PR 1 review finding 1 — pin the dispose contract on
/// [RouterRefreshListenable].
///
/// Pre-fix, the `ref.listen` subscriptions in the constructor were never
/// closed. On sign-out / hot-restart the GoRouter is rebuilt; the previous
/// listenable goes out of scope but its subscriptions keep firing
/// `notifyListeners()` against a disposed [ChangeNotifier], which throws.
///
/// Contract pinned here:
///   1. Disposing the listenable closes all underlying provider
///      subscriptions, so subsequent emissions on the watched providers
///      do NOT increment `debugNotifyCount`.
///   2. Subsequent emissions also do NOT throw — the
///      `(_, _) => notifyListeners()` handler would call into a disposed
///      [ChangeNotifier] if the subscriptions were still live.
///
/// We override [profileProvider] (the cheaper of the two listened-to
/// providers to drive in a test) and drive emissions through it to count
/// `notifyListeners()` invocations on the listenable. The [authStateProvider]
/// override resolves to a single resolved [AsyncData] value so the
/// StreamProvider does not stay open across the dispose boundary (which
/// causes the container teardown to hang waiting for the source to close).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/router/app_router.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class _NoSessionAuth extends Fake implements supabase.AuthState {
  @override
  supabase.Session? get session => null;
}

/// Re-buildable [ProfileNotifier] stub. Calling `state = AsyncData(...)`
/// from the test propagates to the listenable via `ref.listen` and
/// increments `debugNotifyCount`.
class _ConfigurableProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'u1');

  void emit(Profile? next) {
    state = AsyncData(next);
  }
}

/// Provider that constructs the listenable inside a real `Ref`. The test
/// container reads it once; closing the read subscription tears the element
/// down deterministically and fires the listenable's dispose path.
final _testListenableProvider = Provider.autoDispose<RouterRefreshListenable>((
  ref,
) {
  final listenable = RouterRefreshListenable(ref);
  ref.onDispose(listenable.dispose);
  return listenable;
});

void main() {
  group('RouterRefreshListenable lifecycle', () {
    test('dispose closes provider subscriptions — post-dispose emissions on '
        'profileProvider do NOT propagate to notifyListeners', () async {
      // Resolved auth stream — single event, then close. The listenable
      // does not need a live auth stream for this test (we drive emissions
      // through the profile side).
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<supabase.AuthState>.value(_NoSessionAuth()),
          ),
          profileProvider.overrideWith(_ConfigurableProfileNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      // Hold the listenable alive via a subscription handle. Closing the
      // handle is what triggers the autoDispose tear-down later.
      final sub = container.listen<RouterRefreshListenable>(
        _testListenableProvider,
        (_, _) {},
      );
      final listenable = sub.read();

      // Drain microtasks so build() + initial fan-out settle.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Drive a profile emission WHILE alive — proves the wiring fires.
      // (Without this priming the post-dispose assertion would be vacuous:
      // `count == 0` both before and after dispose.)
      final notifier =
          container.read(profileProvider.notifier)
              as _ConfigurableProfileNotifier;
      notifier.emit(const Profile(id: 'u1', displayName: 'before-dispose'));
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final preDisposeCount = listenable.debugNotifyCount;
      expect(
        preDisposeCount,
        greaterThan(0),
        reason:
            'Subscriptions must fire while the listenable is alive — '
            'otherwise the post-dispose assertion below would be vacuous.',
      );

      // DISPOSE: close the only handle → autoDispose tears down the
      // element → its onDispose calls listenable.dispose → the listenable
      // closes its inner ref.listen subscriptions.
      sub.close();
      // Drain microtasks so autoDispose has actually fired before we
      // emit again. autoDispose schedules the element teardown to the
      // next microtask, NOT synchronously inside `sub.close()`.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Emit AFTER dispose. With the subscriptions closed, this event
      // must NOT propagate. Pre-fix (no dispose implementation), the
      // subscription would still be live and either bump
      // `debugNotifyCount` or throw "A ChangeNotifier was used after
      // being disposed."
      notifier.emit(const Profile(id: 'u1', displayName: 'after-dispose'));
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Exact deterministic outcome per `feedback_engineering_quality_bar`:
      // the count must NOT advance past its pre-dispose value.
      expect(listenable.debugNotifyCount, preDisposeCount);
    });
  });
}
