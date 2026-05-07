import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/auth/providers/notifiers/auth_notifier.dart';
import 'package:repsaga/features/auth/utils/auth_error_messages.dart';
import 'package:repsaga/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthRepository extends Mock implements AuthRepository {}

class MockHiveService extends Mock implements HiveService {}

class MockGoTrueClient extends Mock implements supabase.GoTrueClient {}

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

  group('AuthNotifier.signInWithEmail timeout', () {
    // Guards the fix from `fix/auth-timeout`. Without `.timeout()` on the
    // AuthRepository network calls, a silent network black hole (captive
    // portal dropping packets, dead Wi-Fi handoff) leaves the notifier in
    // `AsyncLoading()` forever. With the fix, a never-completing future
    // resolves to `AsyncError(NetworkException('... timed out ...'))` and
    // `AuthErrorMessages.fromError` surfaces the localized timeout copy.
    test('never-completing signInWithPassword future resolves to AsyncError '
        'with a NetworkException whose message contains "timeout"', () async {
      final mockGoTrue = MockGoTrueClient();
      when(() => mockGoTrue.currentSession).thenReturn(null);
      // Return a Future that never completes — simulates a packet-dropping
      // captive portal or dead network. With the timeout fix in place,
      // AuthRepository will throw a TimeoutException which ErrorMapper
      // converts to a NetworkException.
      when(
        () => mockGoTrue.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) => Completer<supabase.AuthResponse>().future);

      // Real AuthRepository with a tight timeout so the test is fast.
      final realRepo = AuthRepository(
        mockGoTrue,
        authTimeout: const Duration(milliseconds: 50),
      );
      final mockHive = MockHiveService();

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(realRepo),
          hiveServiceProvider.overrideWithValue(mockHive),
        ],
      );
      addTearDown(container.dispose);

      // Force the notifier to build.
      container.read(authNotifierProvider);

      await container
          .read(authNotifierProvider.notifier)
          .signInWithEmail(email: 'a@b.com', password: 'pw');

      final state = container.read(authNotifierProvider);
      expect(
        state,
        isA<AsyncError<dynamic>>(),
        reason: 'Notifier must not stay in AsyncLoading on a hung network',
      );
      final error = (state as AsyncError).error;
      expect(error, isA<NetworkException>());
      expect(
        (error as NetworkException).message.toLowerCase(),
        contains('timeout'),
      );

      // The user-facing copy must surface the localized timeout string,
      // not the generic fallback.
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(AuthErrorMessages.fromError(error, l10n), l10n.authErrorTimeout);
    });
  });
}
