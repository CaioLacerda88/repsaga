import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/constants/supported_locales.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockProfileRepository extends Mock implements ProfileRepository {}

class _MockUser extends Mock implements supabase.User {}

class _MockSession extends Mock implements supabase.Session {}

class _FakeUserAttributes extends Fake implements supabase.UserAttributes {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _userId = 'user-123';

Profile _profile({String? locale}) => Profile(
  id: _userId,
  // Default Profile.locale is 'en' (Freezed default). The tests that want
  // an unset locale pass an explicit null override via the factory below.
  locale: locale ?? 'en',
);

/// Builds a [ProviderContainer] with:
///  - `authStateProvider` overridden to emit a single signed-in [AuthState]
///    (so [ProfileNotifier.build] reaches the `getProfile(...)` line).
///  - `profileRepositoryProvider` overridden to return [profile] from
///    `getProfile`.
///  - `authRepositoryProvider` overridden to expose [user] as `currentUser`
///    and forward `updateUserMetadata` calls to [authRepo].
/// Builds a User mock pre-staged with id + metadata. Stubs are set
/// OUTSIDE any other `when(() => ...)` cascade so we don't trip
/// mocktail's "Cannot call `when` within a stub response" guard.
supabase.User _userMock({
  String id = _userId,
  Map<String, dynamic>? userMetadata,
}) {
  final m = _MockUser();
  when(() => m.id).thenReturn(id);
  when(() => m.userMetadata).thenReturn(userMetadata);
  return m;
}

ProviderContainer _container({
  required _MockAuthRepository authRepo,
  required _MockProfileRepository profileRepo,
  required supabase.User? user,
  required Profile? profile,
}) {
  // currentUser is read by the hydration helper to decide whether
  // user_metadata.locale is already populated.
  when(() => authRepo.currentUser).thenReturn(user);

  // getProfile resolves to the Profile under test.
  when(() => profileRepo.getProfile(any())).thenAnswer((_) async => profile);

  // Default: updateUserMetadata succeeds. Individual tests can re-stub to
  // throw before reading from the container.
  when(() => authRepo.updateUserMetadata(any())).thenAnswer((_) async {});

  // Build the AuthState payload OUTSIDE any other when() — building the
  // Session mock inside another when() cascade trips mocktail's nested
  // stub guard.
  final sessionUser = _userMock();
  final session = _MockSession();
  when(() => session.user).thenReturn(sessionUser);

  final initialAuth = supabase.AuthState(
    supabase.AuthChangeEvent.signedIn,
    session,
  );

  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream<supabase.AuthState>.value(initialAuth),
      ),
      authRepositoryProvider.overrideWithValue(authRepo),
      profileRepositoryProvider.overrideWithValue(profileRepo),
    ],
  );
}

/// Drains pending microtasks (so the `Stream.value(...)` event delivers
/// to its Riverpod listener) BEFORE the profile build is triggered, so
/// `ref.watch(authStateProvider).value?.session` sees the signed-in
/// session and `ProfileNotifier.build()` reaches the `getProfile(...)`
/// branch — instead of short-circuiting to `return null` on first
/// build while authState is still AsyncLoading.
///
/// The order matters: subscribing to authStateProvider via
/// `container.listen` first, then yielding microtasks for the stream
/// event to propagate, then reading profileProvider. Without the
/// pre-listen, Riverpod treats profileProvider as the first subscriber
/// and starts the build before the stream has fired its initial event.
Future<Profile?> _readProfile(ProviderContainer container) async {
  // Force the StreamProvider to start subscribing now and capture its
  // pending state.
  container.listen<AsyncValue<supabase.AuthState>>(
    authStateProvider,
    (_, _) {},
    fireImmediately: true,
  );
  // Yield several microtasks so Stream.value's onListen callback runs
  // and the event reaches the StreamProvider's AsyncValue state.
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(profileProvider.future);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(_FakeUserAttributes());
  });

  late _MockAuthRepository authRepo;
  late _MockProfileRepository profileRepo;

  setUp(() {
    authRepo = _MockAuthRepository();
    profileRepo = _MockProfileRepository();
  });

  group('ProfileNotifier locale-metadata hydration', () {
    test('writes user_metadata.locale = "pt" when metadata locale is null '
        'and profile.locale is "pt"', () async {
      final user = _userMock(
        userMetadata: <String, dynamic>{
          // Some other metadata is present but locale is missing.
          'full_name': 'Tester',
        },
      );

      final container = _container(
        authRepo: authRepo,
        profileRepo: profileRepo,
        user: user,
        profile: _profile(locale: 'pt'),
      );
      addTearDown(container.dispose);

      final profile = await _readProfile(container);

      // Profile load itself is unaffected — the result reaches the caller.
      expect(profile?.locale, 'pt');

      // Let the fire-and-forget hydration microtask settle.
      await _flush();

      final captured = verify(
        () => authRepo.updateUserMetadata(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      expect(captured.single, <String, Object?>{'locale': 'pt'});
    });

    test('is a no-op when user_metadata.locale is already populated', () async {
      final user = _userMock(userMetadata: <String, dynamic>{'locale': 'en'});

      final container = _container(
        authRepo: authRepo,
        profileRepo: profileRepo,
        user: user,
        profile: _profile(locale: 'pt'),
      );
      addTearDown(container.dispose);

      final profile = await _readProfile(container);
      expect(profile?.id, _userId);

      await _flush();

      verifyNever(() => authRepo.updateUserMetadata(any()));
    });

    test(
      'is a no-op when getProfile returns null (no profile row yet)',
      () async {
        final user = _userMock(
          userMetadata: <String, dynamic>{'full_name': 'Tester'},
        );

        // getProfile returns null — the user authenticated but has no
        // profiles row yet (e.g. fresh OAuth signup that hasn't reached
        // the onboarding upsert). The hydration helper must not fire
        // because there's no profile.locale to read.
        final container = _container(
          authRepo: authRepo,
          profileRepo: profileRepo,
          user: user,
          profile: null,
        );
        addTearDown(container.dispose);

        final profile = await _readProfile(container);
        expect(profile, isNull);

        await _flush();

        verifyNever(() => authRepo.updateUserMetadata(any()));
      },
    );

    test(
      'is a no-op when profile.locale is not in kSupportedLocales',
      () async {
        final user = _userMock(
          userMetadata: <String, dynamic>{'full_name': 'Tester'},
        );

        final container = _container(
          authRepo: authRepo,
          profileRepo: profileRepo,
          user: user,
          // "fr" is not in kSupportedLocales — the helper must refuse to
          // forward an unsupported locale into auth.users.raw_user_meta_data
          // (the email templates only know about 'pt' and 'en'; an unknown
          // value would still fall into the {{ else }} English branch but
          // would pollute the metadata column).
          profile: _profile(locale: 'fr'),
        );
        addTearDown(container.dispose);

        final profile = await _readProfile(container);
        expect(profile?.locale, 'fr');

        await _flush();

        verifyNever(() => authRepo.updateUserMetadata(any()));
      },
    );

    test(
      'updateUserMetadata failure does not crash the profile load',
      () async {
        final user = _userMock(
          userMetadata: <String, dynamic>{'full_name': 'Tester'},
        );

        when(
          () => authRepo.updateUserMetadata(any()),
        ).thenThrow(StateError('network blew up'));

        final container = _container(
          authRepo: authRepo,
          profileRepo: profileRepo,
          user: user,
          profile: _profile(locale: 'pt'),
        );
        addTearDown(container.dispose);

        // User-visible contract: the profile resolves successfully despite
        // the metadata write failing. The fire-and-forget hydration must
        // NOT bubble its error up to the Profile? AsyncValue.
        final profile = await _readProfile(container);
        expect(profile, isNotNull);
        expect(profile?.locale, 'pt');

        await _flush();

        // The helper still attempted the write — verifies we didn't
        // short-circuit BEFORE the call.
        verify(() => authRepo.updateUserMetadata(any())).called(1);

        // And the AsyncValue is still AsyncData, not AsyncError.
        expect(container.read(profileProvider), isA<AsyncData<Profile?>>());
      },
    );

    test('fires for "en" too (proves it is not pt-specific)', () async {
      final user = _userMock(
        userMetadata: <String, dynamic>{'full_name': 'Tester'},
      );

      final container = _container(
        authRepo: authRepo,
        profileRepo: profileRepo,
        user: user,
        profile: _profile(locale: 'en'),
      );
      addTearDown(container.dispose);

      await _readProfile(container);
      await _flush();

      verify(
        () => authRepo.updateUserMetadata(<String, Object?>{'locale': 'en'}),
      ).called(1);
    });
  });

  group('kSupportedLocales contract', () {
    test('matches AppLocalizations.supportedLocales', () {
      // Pin that the supported-locales const stays in sync with the
      // gen-l10n-produced list. If a new locale is added to l10n.yaml,
      // this test fails and forces the agent to update kSupportedLocales,
      // the SQL backfill, and the email templates together.
      final genLocales =
          AppLocalizations.supportedLocales.map((l) => l.languageCode).toList()
            ..sort();
      final constLocales = [...kSupportedLocales]..sort();
      expect(constLocales, equals(genLocales));
    });
  });
}

/// Yields the event loop several times so pending microtasks (the
/// fire-and-forget hydration helper, the `await` inside it, the
/// mocktail completer for `updateUserMetadata`) all settle before the
/// test asserts on the verify trail.
Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
