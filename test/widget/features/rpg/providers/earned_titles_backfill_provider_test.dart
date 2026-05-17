import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_backfill_provider.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockRepo extends Mock implements TitlesRepository {}

/// Builds a synthetic [AuthState] with a session whose user has the given id.
/// Mirrors `_signedInState` in `pr_cache_bootstrap_provider_test.dart` —
/// `Session.fromJson` produces a session whose `.user.id` matches, which is
/// what the bootstrap provider reads via `authStateProvider`.
AuthState _signedInState(String userId) {
  final session = Session.fromJson({
    'access_token': 'fake-access',
    'token_type': 'bearer',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'email': '$userId@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
    },
  })!;
  return AuthState(AuthChangeEvent.signedIn, session);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> prefsBox;
  late _MockRepo repo;
  late StreamController<AuthState> authController;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('titles_backfill_test_');
    Hive.init(tempDir.path);
    prefsBox = await Hive.openBox<dynamic>(HiveService.userPrefs);
    repo = _MockRepo();
    // Broadcast so multiple subscriptions (post-invalidate / ref.listen probes)
    // can each replay the latest emission. Mirrors the pr_cache_bootstrap test
    // harness — a single-subscription stream throws on the second listener.
    authController = StreamController<AuthState>.broadcast();
    when(() => repo.backfillEarnedTitles(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await authController.close();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Builds a container with `authStateProvider` driven by [authController]
  /// and the titles repository overridden with the mock. Pumps the initial
  /// signed-in emission unless `pumpInitial: false`.
  Future<ProviderContainer> makeContainer({
    String userId = 'user-abc',
    bool pumpInitial = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => authController.stream),
        titlesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    if (pumpInitial) {
      // Subscribe so the broadcast-stream emission lands. (Broadcast streams
      // drop events when no listener is attached — same pattern as the
      // pr_cache_bootstrap test harness.)
      container.listen(authStateProvider, (_, _) {});
      authController.add(_signedInState(userId));
      // Yield so the StreamProvider transitions to AsyncData before the
      // bootstrap reads `.future` — without this, the bootstrap's await
      // races the controller's microtask scheduling.
      await Future<void>.delayed(Duration.zero);
    }

    return container;
  }

  group('earnedTitlesBackfillProvider', () {
    test('should call backfill_earned_titles once on first run', () async {
      final container = await makeContainer();

      await container.read(earnedTitlesBackfillProvider.future);

      verify(() => repo.backfillEarnedTitles('user-abc')).called(1);
      // Flag is set on success so the next session no-ops.
      expect(prefsBox.get(earnedTitlesBackfilledV1Key('user-abc')), isTrue);
    });

    test('should not call backfill again after the Hive flag is set', () async {
      await prefsBox.put(earnedTitlesBackfilledV1Key('user-abc'), true);

      final container = await makeContainer();

      await container.read(earnedTitlesBackfillProvider.future);
      verifyNever(() => repo.backfillEarnedTitles(any()));
    });

    test(
      'should swallow backfill RPC errors without crashing the shell',
      () async {
        when(
          () => repo.backfillEarnedTitles(any()),
        ).thenThrow(StateError('network down'));

        final container = await makeContainer();

        // Provider future MUST complete — bootstrap is best-effort.
        await expectLater(
          container.read(earnedTitlesBackfillProvider.future),
          completes,
        );
        // User-perceptible behavior: the Hive flag stays unset on failure,
        // which means the next app open retries the backfill. If the flag
        // were set, a transient network failure at first launch would
        // permanently lock the user out of their backfilled title rows.
        final flag = prefsBox.get(earnedTitlesBackfilledV1Key('user-abc'));
        expect(flag, isNot(true));
      },
    );
  });
}
