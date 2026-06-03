import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/auth/providers/onboarding_provider.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class _NoSessionAuth extends Fake implements supabase.AuthState {
  @override
  supabase.Session? get session => null;
}

class _ValidSessionAuth extends Fake implements supabase.AuthState {
  _ValidSessionAuth(this._session);
  final supabase.Session _session;

  @override
  supabase.Session get session => _session;
}

class _FakeSession extends Fake implements supabase.Session {}

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this._value);
  final Profile? _value;

  @override
  Future<Profile?> build() async => _value;
}

class _LoadingForeverProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile?> build() {
    return Completer<Profile?>().future;
  }
}

/// Builds a ProviderContainer with overridden auth + profile providers and
/// pumps the event queue until both providers reach a steady-state
/// (`AsyncData` or `AsyncError` — `isLoading` settled). Mirrors the StreamController + eager-listen
/// StreamController pattern in use across the test tree.
/// `test/unit/features/exercises/providers/exercise_progress_provider_test.dart`.
///
/// Returns the container plus the `needsOnboardingProvider` value at steady
/// state — the post-flush read is the contract surface this test pins.
Future<({ProviderContainer container, bool needsOnboarding})> _buildAndRead({
  required supabase.AuthState authEvent,
  required ProfileNotifier Function() profileNotifierBuilder,
}) async {
  final authController = StreamController<supabase.AuthState>();
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith((ref) => authController.stream),
      profileProvider.overrideWith(profileNotifierBuilder),
    ],
  );
  // Eagerly subscribe before adding the event — Riverpod's StreamProvider
  // subscribes lazily on `ref.watch` / `ref.read`. A non-broadcast
  // StreamController buffers events for the first subscriber, but only
  // if the subscription exists at add-time. The `container.listen` call
  // below primes both providers so the queued event reaches their
  // subscribers in the same microtask round.
  container.listen(authStateProvider, (_, _) {});
  container.listen(profileProvider, (_, _) {});
  authController.add(authEvent);

  // Pump enough microtasks for:
  //   (a) the StreamController to deliver the queued event to the
  //       StreamProvider subscriber,
  //   (b) the AsyncNotifier override's `build` Future to resolve.
  // 5 iterations is generous; in practice both complete within 1-2.
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }

  final needsOnboarding = container.read(needsOnboardingProvider);
  return (container: container, needsOnboarding: needsOnboarding);
}

void main() {
  group('needsOnboardingProvider', () {
    test('returns false when no session', () async {
      final (:container, :needsOnboarding) = await _buildAndRead(
        authEvent: _NoSessionAuth(),
        profileNotifierBuilder: () => _StubProfileNotifier(
          Profile(
            id: 'u1',
            displayName: 'Caio',

            onboardedAt: DateTime(2026, 1, 1),
          ),
        ),
      );
      addTearDown(container.dispose);

      // No session → never claim onboarding-needed; the redirect chain
      // sends anonymous users to /login first.
      expect(needsOnboarding, isFalse);
    });

    test(
      'returns false while profile is still loading (router parks on splash separately)',
      () async {
        final (:container, :needsOnboarding) = await _buildAndRead(
          authEvent: _ValidSessionAuth(_FakeSession()),
          profileNotifierBuilder: _LoadingForeverProfileNotifier.new,
        );
        addTearDown(container.dispose);

        // Loading → must NOT flip to true mid-load. The router's splash gate
        // is the responsible owner of the loading state; this provider stays
        // monotonically aligned with the post-load truth.
        expect(needsOnboarding, isFalse);
      },
    );

    test(
      'returns true when session present and profile is null (row missing)',
      () async {
        final (:container, :needsOnboarding) = await _buildAndRead(
          authEvent: _ValidSessionAuth(_FakeSession()),
          profileNotifierBuilder: () => _StubProfileNotifier(null),
        );
        addTearDown(container.dispose);

        // Profile row doesn't exist yet (fresh signup before the
        // handle_new_user trigger has produced a row) → onboarding required.
        expect(needsOnboarding, isTrue);
      },
    );

    test('returns true when session present and onboardedAt is null', () async {
      final (:container, :needsOnboarding) = await _buildAndRead(
        authEvent: _ValidSessionAuth(_FakeSession()),
        profileNotifierBuilder: () => _StubProfileNotifier(
          const Profile(
            id: 'u1',
            displayName: 'Caio',

            // Half-onboarded user: display_name persisted but the
            // onboarding flow never completed → onboarded_at stays NULL
            // → next launch must route through /onboarding.
          ),
        ),
      );
      addTearDown(container.dispose);

      expect(needsOnboarding, isTrue);
    });

    test(
      'returns false when session present and onboardedAt is non-null',
      () async {
        final (:container, :needsOnboarding) = await _buildAndRead(
          authEvent: _ValidSessionAuth(_FakeSession()),
          profileNotifierBuilder: () => _StubProfileNotifier(
            Profile(
              id: 'u1',
              displayName: 'Caio',
              onboardedAt: DateTime(2026, 1, 1),
            ),
          ),
        );
        addTearDown(container.dispose);

        // Fully-onboarded user → /home is the target; no onboarding push.
        expect(needsOnboarding, isFalse);
      },
    );

    test('process-restart simulation - dispose + rebuild reads persisted '
        'profile shape (no flag-survival bug)', () async {
      // First launch: half-onboarded user lands on /onboarding (true).
      final first = await _buildAndRead(
        authEvent: _ValidSessionAuth(_FakeSession()),
        profileNotifierBuilder: () =>
            _StubProfileNotifier(const Profile(id: 'u1', displayName: 'Caio')),
      );
      expect(first.needsOnboarding, isTrue);
      first.container.dispose();

      // Second launch: same user (same profile shape — display_name set
      // but onboarded_at still NULL because they never finished). The
      // derived provider MUST again return true — proving the state is
      // not lost in transit across the restart boundary.
      final second = await _buildAndRead(
        authEvent: _ValidSessionAuth(_FakeSession()),
        profileNotifierBuilder: () =>
            _StubProfileNotifier(const Profile(id: 'u1', displayName: 'Caio')),
      );
      addTearDown(second.container.dispose);

      // This is the assertion the OLD `StateProvider<bool>` would fail —
      // the bool defaults to `false` on a fresh container, dropping the
      // user back into /home post-restart even though their profile says
      // they never finished onboarding (audit defects D1/D2/D11).
      expect(second.needsOnboarding, isTrue);
    });
  });
}
