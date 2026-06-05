// Pins the userId-from-authStateProvider contract on the mutation methods
// of [ProfileNotifier] — `saveOnboardingProfile`, `updateTrainingFrequency`,
// and `toggleWeightUnit`.
//
// Cluster: provider-init-timing. The prior implementation read from
// `currentUserIdProvider`, a `Provider<String?>` documented as
// "not reactive" — but Riverpod caches its first-read value until
// invalidation. At app start the first read returns `null` (Supabase
// auth hasn't restored its session), and the cached null persists for
// the rest of the container's lifetime. Mutation methods reading from
// it silently no-op, leaving the user with a UI that looks like a save
// loop (no upsert call, notifier stays on AsyncData(null), router keeps
// routing to /onboarding).
//
// The fix reads userId from `ref.read(authStateProvider).value?.session
// ?.user.id` — the SAME source [ProfileNotifier.build] watches. These
// tests pin that contract:
//   (1) No session → silent no-op, no upsert call, no exception.
//   (2) Session present → upsert called with the session user's id.
//
// Behavior-not-wiring per CLAUDE.md A2: the assertions check the
// REPOSITORY METHOD INVOCATIONS (the user-visible effect is "a row is
// written to Supabase" — verified at the repository boundary, not by
// asserting on AsyncValue internals). The notifier's reactive userId
// derivation is a load-bearing implementation detail; observing it
// through `verify(() => repo.upsertProfile(...))` pins the contract
// without baking in Riverpod state machinery.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockProfileRepository extends Mock implements ProfileRepository {}

class _MockUser extends Mock implements supabase.User {}

class _MockSession extends Mock implements supabase.Session {}

class _FakeProfile extends Fake implements Profile {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _userId = 'user-session-derived';

Profile _profile({
  String id = _userId,
  String? displayName = 'Existing',
  String weightUnit = 'kg',
  int trainingFrequencyPerWeek = 3,
}) {
  return Profile(
    id: id,
    displayName: displayName,
    weightUnit: weightUnit,
    trainingFrequencyPerWeek: trainingFrequencyPerWeek,
  );
}

/// Build the same kind of override harness used by
/// `profile_notifier_locale_hydration_test.dart`:
///
/// - `authStateProvider` is overridden with a `Stream<AuthState>.value(...)`
///   so [ProfileNotifier.build] sees either a signed-in [AuthState]
///   (yielding [_userId]) or a signed-out [AuthState] (yielding null).
/// - `profileRepositoryProvider` is overridden to expose [profileRepo]
///   so callers can `verify(() => profileRepo.upsertProfile(...))` after
///   the mutation method runs.
/// - `authRepositoryProvider` is overridden too, with a stub
///   `currentUser` getter so the build path's locale-hydration helper
///   doesn't crash on null.
ProviderContainer _container({
  required _MockProfileRepository profileRepo,
  required _MockAuthRepository authRepo,
  required bool signedIn,
}) {
  // Stub currentUser to a minimal user — the locale-hydration helper
  // reads `userMetadata['locale']` and would dereference null otherwise.
  // We return a user with a populated 'locale' so the helper exits at
  // its first guard and never tries to call `updateUserMetadata` (we
  // don't care about that path here).
  if (signedIn) {
    final user = _MockUser();
    when(() => user.id).thenReturn(_userId);
    when(() => user.userMetadata).thenReturn(<String, dynamic>{'locale': 'en'});
    when(() => authRepo.currentUser).thenReturn(user);
  } else {
    when(() => authRepo.currentUser).thenReturn(null);
  }

  // getProfile resolves to a baseline Profile when signed in (so
  // [build] returns non-null and updateTrainingFrequency /
  // toggleWeightUnit have current state to mutate).
  when(
    () => profileRepo.getProfile(any()),
  ).thenAnswer((_) async => signedIn ? _profile() : null);

  // Build the AuthState emitted on the stream.
  final supabase.AuthState initialAuth;
  if (signedIn) {
    final sessionUser = _MockUser();
    when(() => sessionUser.id).thenReturn(_userId);
    final session = _MockSession();
    when(() => session.user).thenReturn(sessionUser);
    initialAuth = supabase.AuthState(
      supabase.AuthChangeEvent.signedIn,
      session,
    );
  } else {
    // Signed-out AuthState with a null session — exactly the shape the
    // bug scenario produces (Supabase hasn't restored a session yet).
    initialAuth = const supabase.AuthState(
      supabase.AuthChangeEvent.signedOut,
      null,
    );
  }

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

/// Drives the stream-emission + microtask queue so
/// `ref.watch(authStateProvider)` resolves to its AsyncData before the
/// mutation method runs. Mirrors the helper in
/// `profile_notifier_locale_hydration_test.dart` — five iterations is
/// the empirical floor for the Stream.value → StreamProvider →
/// AsyncNotifier propagation chain.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Triggers [ProfileNotifier.build] (so it watches authStateProvider)
/// and waits for the stream to resolve. The notifier's first listen
/// kicks off the build; without an explicit listener the build never
/// fires and `ref.watch(authStateProvider)` inside the mutation methods
/// would see `AsyncLoading` instead of the seeded `AuthState`.
Future<Profile?> _readProfile(ProviderContainer container) async {
  // Force authStateProvider to start subscribing first.
  container.listen<AsyncValue<supabase.AuthState>>(
    authStateProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await _settle();
  return container.read(profileProvider.future);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeProfile());
    registerFallbackValue(DateTime(2026));
  });

  late _MockAuthRepository authRepo;
  late _MockProfileRepository profileRepo;

  setUp(() {
    authRepo = _MockAuthRepository();
    profileRepo = _MockProfileRepository();
  });

  group('ProfileNotifier mutation methods read userId from live authState', () {
    test(
      'saveOnboardingProfile is a silent no-op when authStateProvider has no '
      'session — no upsertProfile call, no exception thrown',
      () async {
        // Cluster: provider-init-timing. With no session in the stream,
        // the live-authState read returns null and the mutation method
        // must early-return without invoking the repository. The PRE-FIX
        // behavior also no-op'd in this case (the cached
        // `currentUserIdProvider` would be null), so the contract here
        // pins the SAME observable behavior post-fix — but now driven by
        // a reliable, reactive source instead of a one-shot cache.
        final container = _container(
          profileRepo: profileRepo,
          authRepo: authRepo,
          signedIn: false,
        );
        addTearDown(container.dispose);

        // Profile build returns null (no session → early-return in build).
        final profile = await _readProfile(container);
        expect(profile, isNull);

        // Now call the mutation. It must NOT throw and must NOT call
        // upsertProfile — the repository was never given a chance to
        // succeed or fail.
        await expectLater(
          () => container
              .read(profileProvider.notifier)
              .saveOnboardingProfile(
                displayName: 'Alice',
                fitnessLevel: 'beginner',
              ),
          returnsNormally,
        );

        verifyNever(
          () => profileRepo.upsertProfile(
            userId: any(named: 'userId'),
            displayName: any(named: 'displayName'),
            fitnessLevel: any(named: 'fitnessLevel'),
            weightUnit: any(named: 'weightUnit'),
            trainingFrequencyPerWeek: any(named: 'trainingFrequencyPerWeek'),
            locale: any(named: 'locale'),
            bodyweightKg: any(named: 'bodyweightKg'),
            gender: any(named: 'gender'),
            avatarUrl: any(named: 'avatarUrl'),
            onboardedAt: any(named: 'onboardedAt'),
          ),
        );
      },
    );

    test('saveOnboardingProfile invokes upsertProfile with the session user id '
        'when authStateProvider has a session — pins the live-authState '
        'derivation against a stale cached `currentUserIdProvider`', () async {
      // The CRITICAL contract test for Layer 2's fix. The bug scenario
      // is: app starts → Supabase restores session AFTER
      // `currentUserIdProvider` was first read (cached null) → the
      // mutation reads cached null → silent no-op → user perceives a
      // "save did nothing" loop. Reading from authStateProvider
      // bypasses the stale cache and uses the live session id.
      //
      // We assert the userId forwarded to the repository EQUALS the
      // session's user id — proving the derivation is reactive.

      when(
        () => profileRepo.upsertProfile(
          userId: any(named: 'userId'),
          displayName: any(named: 'displayName'),
          fitnessLevel: any(named: 'fitnessLevel'),
          weightUnit: any(named: 'weightUnit'),
          trainingFrequencyPerWeek: any(named: 'trainingFrequencyPerWeek'),
          locale: any(named: 'locale'),
          bodyweightKg: any(named: 'bodyweightKg'),
          gender: any(named: 'gender'),
          avatarUrl: any(named: 'avatarUrl'),
          onboardedAt: any(named: 'onboardedAt'),
        ),
      ).thenAnswer((_) async => _profile(displayName: 'Alice'));

      final container = _container(
        profileRepo: profileRepo,
        authRepo: authRepo,
        signedIn: true,
      );
      addTearDown(container.dispose);

      await _readProfile(container);

      await container
          .read(profileProvider.notifier)
          .saveOnboardingProfile(
            displayName: 'Alice',
            fitnessLevel: 'beginner',
            trainingFrequencyPerWeek: 4,
          );

      // Verify the userId forwarded to the repository IS the session
      // user id — not a stale cache, not a null sentinel.
      final captured = verify(
        () => profileRepo.upsertProfile(
          userId: captureAny(named: 'userId'),
          displayName: 'Alice',
          fitnessLevel: 'beginner',
          trainingFrequencyPerWeek: 4,
          onboardedAt: captureAny(named: 'onboardedAt'),
        ),
      ).captured;
      expect(captured.first, _userId);
      // onboardedAt was stamped (not null) — PR 1's anchor still fires.
      expect(captured.last, isA<DateTime>());
    });

    test('updateTrainingFrequency invokes updateTrainingFrequency on the repo '
        'with the live session userId', () async {
      // Same contract on the second mutation method — guards against
      // a future refactor accidentally reverting only one call site to
      // `currentUserIdProvider`.
      when(
        () => profileRepo.updateTrainingFrequency(any(), any()),
      ).thenAnswer((_) async {});

      final container = _container(
        profileRepo: profileRepo,
        authRepo: authRepo,
        signedIn: true,
      );
      addTearDown(container.dispose);

      await _readProfile(container);

      await container.read(profileProvider.notifier).updateTrainingFrequency(5);

      verify(() => profileRepo.updateTrainingFrequency(_userId, 5)).called(1);
    });

    test('toggleWeightUnit invokes updateWeightUnit on the repo with the live '
        'session userId', () async {
      when(
        () => profileRepo.updateWeightUnit(any(), any()),
      ).thenAnswer((_) async {});

      final container = _container(
        profileRepo: profileRepo,
        authRepo: authRepo,
        signedIn: true,
      );
      addTearDown(container.dispose);

      await _readProfile(container);

      // Existing weightUnit is 'kg' (see _profile defaults), so toggle
      // flips it to 'lbs' and the repo receives ('user-session-derived',
      // 'lbs') as the argument pair.
      await container.read(profileProvider.notifier).toggleWeightUnit();

      verify(() => profileRepo.updateWeightUnit(_userId, 'lbs')).called(1);
    });

    test('updateTrainingFrequency is a silent no-op when authStateProvider has '
        'no session — guards every mutation method against the cached-null '
        'failure mode', () async {
      final container = _container(
        profileRepo: profileRepo,
        authRepo: authRepo,
        signedIn: false,
      );
      addTearDown(container.dispose);

      await _readProfile(container);

      // build() returned null because no session — the mutation
      // method's `if (current == null) return` short-circuits BEFORE
      // the userId check. Pinning a no-op here guards against a future
      // refactor that reorders the guards and accidentally surfaces an
      // exception instead of silently no-op'ing.
      await expectLater(
        () =>
            container.read(profileProvider.notifier).updateTrainingFrequency(4),
        returnsNormally,
      );

      verifyNever(() => profileRepo.updateTrainingFrequency(any(), any()));
    });
  });
}
