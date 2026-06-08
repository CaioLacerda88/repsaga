import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/l10n/locale_provider.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/auth/providers/notifiers/auth_notifier.dart';
import 'package:repsaga/features/auth/providers/signup_state_provider.dart';
import 'package:repsaga/features/auth/utils/auth_error_messages.dart';
import 'package:repsaga/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../helpers/stub_locale_notifier.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthRepository extends Mock implements AuthRepository {}

class MockHiveService extends Mock implements HiveService {}

class MockGoTrueClient extends Mock implements supabase.GoTrueClient {}

class MockFunctionsClient extends Mock implements supabase.FunctionsClient {}

/// Stand-in for an `AuthResponse` whose `.session` is null — matches the
/// "confirmation email required" path the notifier takes after signUp.
class _FakeAuthResponseNoSession extends Fake implements supabase.AuthResponse {
  @override
  supabase.Session? get session => null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [ProviderContainer] wired up with the mocked repository
/// and [HiveService]. The returned container must be disposed by the caller.
ProviderContainer _createContainer({
  required MockAuthRepository mockRepo,
  required MockHiveService mockHive,
  supabase.Session? initialSession,
}) {
  when(() => mockRepo.currentSession).thenReturn(initialSession);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(mockRepo),
      hiveServiceProvider.overrideWithValue(mockHive),
    ],
  );

  // Force the notifier to build so _repo and _hive are assigned.
  container.read(authNotifierProvider);

  return container;
}

/// Waits for the notifier's state to settle past [AsyncLoading].
Future<void> _waitForSettled(ProviderContainer container) async {
  // Pump micro-tasks so AsyncValue.guard completes.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockAuthRepository mockRepo;
  late MockHiveService mockHive;

  setUp(() {
    mockRepo = MockAuthRepository();
    mockHive = MockHiveService();
  });

  group('AuthNotifier.signUpWithEmail', () {
    // Round 4.5 — locale-routed email templates.
    //
    // Two assertions per test, both required to pin the contract:
    //
    //  1. **Wiring trace** (`verify(... locale: 'pt')`): the notifier MUST
    //     forward the app locale through the repo. Without this, a future
    //     refactor that drops the forwarding line would still pass the
    //     user-visible assertion below (because `signupPendingEmailProvider`
    //     transitions whether locale is forwarded or not), but the email
    //     templates would silently fall back to English for Brazilian users.
    //
    //  2. **User-visible state** (`signupPendingEmailProvider == 'a@b.com'`):
    //     the notifier MUST reach the post-await branch that sets the
    //     pending-email state — the surface the "check your email" screen
    //     reads. Without this, a future refactor that throws inside the
    //     locale read or short-circuits the AsyncValue.guard could leave
    //     `signupPendingEmailProvider == null` while still recording a call
    //     to the mock — the verify alone wouldn't catch it.
    //
    // Behavior-not-wiring per CLAUDE.md → Testing: the verify guards the
    // forwarding hook, the state-pin guards the surfaced UX. Both must hold.
    test('forwards the app locale to the repository as locale:', () async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          locale: any(named: 'locale'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => _FakeAuthResponseNoSession());

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepo),
          hiveServiceProvider.overrideWithValue(mockHive),
          localeProvider.overrideWith(
            () => StubLocaleNotifier(const Locale('pt')),
          ),
        ],
      );
      when(() => mockRepo.currentSession).thenReturn(null);
      container.read(authNotifierProvider);
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signUpWithEmail(email: 'a@b.com', password: 'pw');
      await _waitForSettled(container);

      verify(
        () => mockRepo.signUpWithEmail(
          email: 'a@b.com',
          password: 'pw',
          locale: 'pt',
          displayName: any(named: 'displayName'),
        ),
      ).called(1);

      // User-visible outcome: the notifier reached the post-signup branch
      // that lifts the pending email into the surface the "check your
      // inbox" screen watches. A null here would mean the notifier
      // short-circuited (e.g. swallowed an exception in AsyncValue.guard).
      expect(container.read(signupPendingEmailProvider), 'a@b.com');
    });

    test('forwards "en" when the app locale is English', () async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          locale: any(named: 'locale'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => _FakeAuthResponseNoSession());

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepo),
          hiveServiceProvider.overrideWithValue(mockHive),
          localeProvider.overrideWith(
            () => StubLocaleNotifier(const Locale('en')),
          ),
        ],
      );
      when(() => mockRepo.currentSession).thenReturn(null);
      container.read(authNotifierProvider);
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signUpWithEmail(email: 'a@b.com', password: 'pw');
      await _waitForSettled(container);

      verify(
        () => mockRepo.signUpWithEmail(
          email: 'a@b.com',
          password: 'pw',
          locale: 'en',
          displayName: any(named: 'displayName'),
        ),
      ).called(1);

      // User-visible outcome — same contract as the 'pt' path: the post-
      // signup state-lift to `signupPendingEmailProvider` must fire so the
      // "check your inbox" screen has an email to display.
      expect(container.read(signupPendingEmailProvider), 'a@b.com');
    });

    // Option A (full-form signup): the display name collected on the signup
    // form must be forwarded to the repository so `handle_new_user` can seed
    // the profile row. Two assertions, both required (behavior-not-wiring):
    //   1. the captured `displayName` equals what the caller passed (the
    //      forwarding hook), AND
    //   2. the post-signup pending-email state lifts (the surfaced UX) —
    //      proving the notifier reached the post-await branch with the name
    //      threaded through, not swallowed.
    test('forwards the display name collected at signup', () async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          locale: any(named: 'locale'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => _FakeAuthResponseNoSession());

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepo),
          hiveServiceProvider.overrideWithValue(mockHive),
          localeProvider.overrideWith(
            () => StubLocaleNotifier(const Locale('pt')),
          ),
        ],
      );
      when(() => mockRepo.currentSession).thenReturn(null);
      container.read(authNotifierProvider);
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signUpWithEmail(
            email: 'a@b.com',
            password: 'pw',
            displayName: 'Joao',
          );
      await _waitForSettled(container);

      final captured = verify(
        () => mockRepo.signUpWithEmail(
          email: 'a@b.com',
          password: 'pw',
          locale: any(named: 'locale'),
          displayName: captureAny(named: 'displayName'),
        ),
      ).captured;
      expect(captured.single, 'Joao');

      // User-visible outcome: the pending-email state lifted, so the
      // notifier reached the post-signup branch with the name threaded.
      expect(container.read(signupPendingEmailProvider), 'a@b.com');
    });
  });

  group('AuthNotifier.signOut', () {
    test('signs out then clears Hive caches', () async {
      when(() => mockHive.clearAll()).thenAnswer((_) async {});
      when(() => mockRepo.signOut()).thenAnswer((_) async {});

      final container = _createContainer(
        mockRepo: mockRepo,
        mockHive: mockHive,
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signOut();
      await _waitForSettled(container);

      verifyInOrder([() => mockRepo.signOut(), () => mockHive.clearAll()]);
      expect(
        container.read(authNotifierProvider),
        isA<AsyncData<dynamic>>().having((d) => d.value, 'value', isNull),
      );
    });

    test('propagates error if signOut fails', () async {
      when(() => mockHive.clearAll()).thenAnswer((_) async {});
      when(
        () => mockRepo.signOut(),
      ).thenThrow(const NetworkException('No connection'));

      final container = _createContainer(
        mockRepo: mockRepo,
        mockHive: mockHive,
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signOut();
      await _waitForSettled(container);

      expect(container.read(authNotifierProvider), isA<AsyncError<dynamic>>());
    });

    test('signs out successfully even if clearAll throws', () async {
      when(() => mockRepo.signOut()).thenAnswer((_) async {});
      when(() => mockHive.clearAll()).thenThrow(Exception('Hive I/O error'));

      final container = _createContainer(
        mockRepo: mockRepo,
        mockHive: mockHive,
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signOut();
      await _waitForSettled(container);

      verify(() => mockRepo.signOut()).called(1);
      expect(
        container.read(authNotifierProvider),
        isA<AsyncData<dynamic>>().having((d) => d.value, 'value', isNull),
      );
    });
  });

  group('AuthNotifier.deleteAccount', () {
    test('clears Hive caches on successful delete', () async {
      when(
        () => mockRepo.deleteAccount(
          platform: any(named: 'platform'),
          appVersion: any(named: 'appVersion'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockHive.clearAll()).thenAnswer((_) async {});
      when(() => mockRepo.signOut()).thenAnswer((_) async {});

      final container = _createContainer(
        mockRepo: mockRepo,
        mockHive: mockHive,
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).deleteAccount();
      await _waitForSettled(container);

      verify(() => mockHive.clearAll()).called(1);
      // State ends as AsyncData(null) — session cleared.
      expect(
        container.read(authNotifierProvider),
        isA<AsyncData<dynamic>>().having((d) => d.value, 'value', isNull),
      );
    });

    test('does NOT clear caches when deleteAccount fails', () async {
      when(
        () => mockRepo.deleteAccount(
          platform: any(named: 'platform'),
          appVersion: any(named: 'appVersion'),
        ),
      ).thenThrow(const DatabaseException('Delete failed', code: 'PGRST000'));
      when(() => mockHive.clearAll()).thenAnswer((_) async {});

      final container = _createContainer(
        mockRepo: mockRepo,
        mockHive: mockHive,
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).deleteAccount();
      await _waitForSettled(container);

      verifyNever(() => mockHive.clearAll());
      expect(container.read(authNotifierProvider), isA<AsyncError<dynamic>>());
    });

    test(
      'swallows signOut error after successful delete (best-effort sign-out)',
      () async {
        // The account is gone server-side. Even if the local signOut() call
        // throws (e.g. token already invalid), the state must still resolve
        // to AsyncData(null) — the delete succeeded and the session is gone.
        when(
          () => mockRepo.deleteAccount(
            platform: any(named: 'platform'),
            appVersion: any(named: 'appVersion'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockHive.clearAll()).thenAnswer((_) async {});
        when(
          () => mockRepo.signOut(),
        ).thenThrow(const NetworkException('Already signed out'));

        final container = _createContainer(
          mockRepo: mockRepo,
          mockHive: mockHive,
        );
        addTearDown(container.dispose);

        await container.read(authNotifierProvider.notifier).deleteAccount();
        await _waitForSettled(container);

        // clearAll was called (account successfully deleted).
        verify(() => mockHive.clearAll()).called(1);
        // State resolves to AsyncData(null), not AsyncError — the sign-out
        // error must be swallowed per the documented intent.
        expect(
          container.read(authNotifierProvider),
          isA<AsyncData<dynamic>>().having((d) => d.value, 'value', isNull),
        );
      },
    );
  });

  group('AuthNotifier timeout — public methods', () {
    // Guards the fix from `fix/auth-timeout`. Without `.timeout()` on the
    // AuthRepository network calls, a silent network black hole (captive
    // portal dropping packets, dead Wi-Fi handoff) leaves the notifier in
    // `AsyncLoading()` forever. With the fix, a never-completing future
    // resolves to `AsyncError(TimeoutException)` and
    // `AuthErrorMessages.fromError` surfaces the localized timeout copy.
    //
    // Pinned across every public AuthNotifier method that wraps an
    // AuthRepository call in `AsyncValue.guard`, so a future regression on
    // any individual method is caught.

    /// Builds a real [AuthRepository] (with a 50ms auth timeout and a 50ms
    /// signOut timeout) wired to a fresh mocked [supabase.GoTrueClient] /
    /// [supabase.FunctionsClient]. Returns the constructed pieces so the
    /// caller can stub specific methods on the GoTrue/Functions mocks.
    ({
      ProviderContainer container,
      MockGoTrueClient mockGoTrue,
      MockFunctionsClient mockFunctions,
    })
    buildContainerWithRealRepo() {
      final mockGoTrue = MockGoTrueClient();
      when(() => mockGoTrue.currentSession).thenReturn(null);
      final mockFunctions = MockFunctionsClient();

      final realRepo = AuthRepository(
        mockGoTrue,
        functions: mockFunctions,
        authTimeout: const Duration(milliseconds: 50),
        signOutTimeout: const Duration(milliseconds: 50),
      );
      final mockHive = MockHiveService();
      when(() => mockHive.clearAll()).thenAnswer((_) async {});

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(realRepo),
          hiveServiceProvider.overrideWithValue(mockHive),
          // `signUpWithEmail` now reads `localeProvider` to forward the
          // locale into Supabase user_metadata (Round 4.5 — locale-routed
          // email templates). The production `LocaleNotifier.build()`
          // touches Hive, which the test harness has not booted — so we
          // override with a Hive-free stub locale. The actual locale value
          // is irrelevant here; the tests assert TimeoutException, not
          // metadata shape.
          localeProvider.overrideWith(
            () => StubLocaleNotifier(const Locale('en')),
          ),
        ],
      );
      // Force the notifier to build.
      container.read(authNotifierProvider);

      return (
        container: container,
        mockGoTrue: mockGoTrue,
        mockFunctions: mockFunctions,
      );
    }

    /// Asserts the post-action state is `AsyncError(TimeoutException)` and
    /// that `AuthErrorMessages.fromError` resolves to the localized timeout
    /// copy.
    void expectTimedOut(ProviderContainer container) {
      final state = container.read(authNotifierProvider);
      expect(
        state,
        isA<AsyncError<dynamic>>(),
        reason: 'Notifier must not stay in AsyncLoading on a hung network',
      );
      final error = (state as AsyncError).error;
      expect(
        error,
        isA<TimeoutException>(),
        reason:
            'ErrorMapper must surface a domain TimeoutException so '
            'AuthErrorMessages can dispatch by type, not by substring',
      );

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(AuthErrorMessages.fromError(error, l10n), l10n.authErrorTimeout);
    }

    test('signInWithEmail — never-completing call resolves to AsyncError('
        'TimeoutException)', () async {
      final pieces = buildContainerWithRealRepo();
      addTearDown(pieces.container.dispose);
      when(
        () => pieces.mockGoTrue.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) => Completer<supabase.AuthResponse>().future);

      await pieces.container
          .read(authNotifierProvider.notifier)
          .signInWithEmail(email: 'a@b.com', password: 'pw');

      expectTimedOut(pieces.container);
    });

    test('signUpWithEmail — never-completing call resolves to AsyncError('
        'TimeoutException)', () async {
      registerFallbackValue(<String, dynamic>{});
      final pieces = buildContainerWithRealRepo();
      addTearDown(pieces.container.dispose);
      when(
        () => pieces.mockGoTrue.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          // Match regardless of the `data:` locale payload — see Round 4.5.
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) => Completer<supabase.AuthResponse>().future);

      await pieces.container
          .read(authNotifierProvider.notifier)
          .signUpWithEmail(email: 'a@b.com', password: 'pw');

      expectTimedOut(pieces.container);
    });

    test('resetPassword — never-completing call resolves to AsyncError('
        'TimeoutException)', () async {
      final pieces = buildContainerWithRealRepo();
      addTearDown(pieces.container.dispose);
      when(
        () => pieces.mockGoTrue.resetPasswordForEmail(any()),
      ).thenAnswer((_) => Completer<void>().future);

      await pieces.container
          .read(authNotifierProvider.notifier)
          .resetPassword('a@b.com');

      expectTimedOut(pieces.container);
    });

    test('signOut — never-completing call resolves to AsyncError('
        'TimeoutException) under the tighter signOutTimeout', () async {
      final pieces = buildContainerWithRealRepo();
      addTearDown(pieces.container.dispose);
      when(
        () => pieces.mockGoTrue.signOut(),
      ).thenAnswer((_) => Completer<void>().future);

      await pieces.container.read(authNotifierProvider.notifier).signOut();

      expectTimedOut(pieces.container);
    });

    test('deleteAccount — never-completing FunctionsClient.invoke resolves '
        'to AsyncError(TimeoutException)', () async {
      registerFallbackValue(<String, dynamic>{});
      final pieces = buildContainerWithRealRepo();
      addTearDown(pieces.container.dispose);
      when(
        () => pieces.mockFunctions.invoke(any(), body: any(named: 'body')),
      ).thenAnswer((_) => Completer<supabase.FunctionResponse>().future);

      await pieces.container
          .read(authNotifierProvider.notifier)
          .deleteAccount();

      expectTimedOut(pieces.container);
    });
  });
}
