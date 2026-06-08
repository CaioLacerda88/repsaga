import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../../core/constants/supported_locales.dart';
import '../../../core/local_storage/hive_service.dart';
import '../../../core/observability/sentry_report.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/avatar_repository.dart';
import '../data/profile_repository.dart';
import '../models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Provides the [AvatarRepository] singleton — wires the live Supabase
/// client + the `userPrefs` Hive box for the URL-cache fast-path.
///
/// **Box availability assumption.** [HiveService.init] opens every box
/// (including `userPrefs`) before `runApp()` is called in `main.dart`,
/// so consumers of this provider can assume the box is open. Tests must
/// either open the box in their `setUpAll` (see
/// `profile_screen_test.dart` for the pattern) OR override this
/// provider entirely with a stub.
final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  return AvatarRepository(
    Supabase.instance.client,
    Hive.box<dynamic>(HiveService.userPrefs),
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile?>(
  ProfileNotifier.new,
);

/// Tracks whether an avatar upload is currently in flight. Toggled by the
/// `profile_settings_screen.dart` `openAvatarUploadFlow` orchestrator
/// around the `AvatarRepository.uploadAvatar + ProfileRepository.upsertProfile`
/// pair so the IdentityCard can render a loading overlay on top of the
/// avatar disc — without this, the 3-10s upload window has no visible
/// affordance and the user re-taps thinking the action was dropped.
///
/// Per the architectural separation rule, this lives at the
/// orchestration / provider layer; the leaf widget ([ProfileAvatar]) only
/// reads the flag as a constructor param.
final avatarUploadInProgressProvider = StateProvider<bool>((ref) => false);

class ProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    // Cluster: provider-init-timing — watch authStateProvider, not the
    // synchronous currentUserIdProvider. The latter is documented as
    // non-reactive (auth_providers.dart): it reads `auth.currentUser?.id`
    // ONCE at first watch and caches forever. At app start that read
    // returns null (Supabase auth hasn't restored its session yet), so
    // build() returned `null` and never re-fired on sign-in — leaving
    // profileProvider stuck on `AsyncData(null)` forever. PR 1's router
    // gate (`profileValue == null || onboardedAt == null`) then treated
    // every logged-in user as needs-onboarding, routing them to
    // `/onboarding` instead of `/home`. Surfaced by CI E2E retry loop
    // on `NAV.homeTab` post-login (45-minute timeout cascade across
    // every spec that asserts the home tab is reachable).
    //
    // Watching authStateProvider here makes build re-run on every
    // signedIn / signedOut / tokenRefreshed event — the profile reloads
    // automatically when the user changes.
    final session = ref.watch(authStateProvider).value?.session;
    if (session == null) return null;
    final repo = ref.read(profileRepositoryProvider);
    final profile = await repo.getProfile(session.user.id);

    // PR A2 — fire-and-forget locale-metadata hydration. Closes the two
    // `user_metadata.locale = NULL` populations documented in
    // `docs/auth-email-templates/README.md` → "Known edge cases":
    // legacy users (signed up before PR #300) and Google OAuth users
    // (OAuth flow cannot set user_metadata at authorization time).
    //
    // Placement rationale: build() already runs on every signedIn /
    // signedOut / tokenRefreshed event (cluster `provider-init-timing`),
    // which is exactly the cadence we need. The profile + session are
    // both already loaded here — no need for a second provider chain.
    // The check is self-extinguishing: once user_metadata.locale is
    // populated, subsequent runs short-circuit at the metadata-present
    // branch.
    //
    // Re-entry note. `updateUser` itself fires an `AuthChangeEvent.userUpdated`
    // event which `authStateProvider` forwards without filtering, so
    // build() re-runs after a successful hydration write. GoTrue
    // updates its `_currentSession` BEFORE firing `userUpdated`, so
    // `authRepo.currentUser.userMetadata['locale']` is already populated
    // on that second run and the helper exits at the `metadataLocale !=
    // null` guard. The guard is the load-bearing anti-loop primitive —
    // do not "optimize" it as dead code just because the happy path on
    // first sign-in skips it.
    //
    // Non-blocking: `unawaited` so profile load latency is unaffected.
    // The helper swallows its own errors and only emits a Sentry
    // breadcrumb — a failed metadata write must NOT promote the
    // returned Profile? AsyncValue to AsyncError.
    if (profile != null) {
      unawaited(_hydrateLocaleMetadataIfMissing(profile));
    }
    return profile;
  }

  /// Hydrates `auth.users.raw_user_meta_data.locale` from
  /// `profiles.locale` when the current Supabase user has no locale key
  /// in their `user_metadata` and the profile carries an allowlisted
  /// locale. Documented in detail in [build].
  ///
  /// Visible for the unit-test trail: `unawaited` callers see a
  /// completed Future, never an unhandled error.
  Future<void> _hydrateLocaleMetadataIfMissing(Profile profile) async {
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final user = authRepo.currentUser;
      if (user == null) return;

      // Cluster: jsonb-payload-vs-typed-dart. `user_metadata` is JSONB
      // server-side; the SDK exposes it as `Map<String, dynamic>?`.
      // Guard every dereference — a missing map AND a missing 'locale'
      // key both mean "no locale recorded" and should trigger the
      // backfill.
      final metadataLocale = user.userMetadata?['locale'];
      if (metadataLocale != null) return;

      // Allowlist guard. Refuses to forward an unsupported value into
      // raw_user_meta_data so the email templates' `{{ if eq .Data.locale
      // "<X>" }}` branches never see a value they aren't wired for.
      // Profile.locale is non-nullable (Freezed Default('en')) so this
      // is the only realistic exit short of "already populated".
      if (!kSupportedLocales.contains(profile.locale)) return;

      await authRepo.updateUserMetadata(<String, Object?>{
        'locale': profile.locale,
      });
    } catch (error) {
      // Engineering quality bar: swallow + breadcrumb. The helper is
      // intentionally non-blocking — a failed metadata write must not
      // surface as an AsyncError on profileProvider, and we don't want
      // a transient Supabase blip to spam Sentry as a captured
      // exception. PII policy: `runtimeType.toString()` is a class
      // name only (no email / token / locale-value leakage into the
      // breadcrumb data map).
      SentryReport.addBreadcrumb(
        category: 'auth',
        message: 'hydrate_locale_metadata_failed',
        data: <String, Object?>{'reason': error.runtimeType.toString()},
      );
    }
  }

  /// Reads the signed-in user's id from [authStateProvider] — the SAME
  /// source of truth [build] watches. Returns `null` when no session is
  /// available, so callers can early-return with a silent no-op (the
  /// existing contract on the mutation methods below).
  ///
  /// **Why not `currentUserIdProvider`.** Cluster: `provider-init-timing`.
  /// `currentUserIdProvider` is a `Provider<String?>` documented as
  /// "not reactive" — but Riverpod still caches its first-read value
  /// until the provider is invalidated. At app start, the first read
  /// happens before Supabase restores its session, so the cached value
  /// is `null` forever in that container. Mutation methods reading from
  /// it would silently no-op for the rest of the session, leaving the
  /// user with a UI that looks like a save loop (`saveOnboardingProfile`
  /// returns without firing the upsert, the notifier stays on
  /// `AsyncData(null)`, the router keeps the user on `/onboarding`,
  /// the user re-taps and nothing happens). Reading from
  /// `authStateProvider` — the same stream [build] watches — guarantees
  /// the id reflects the live session, not a stale snapshot.
  String? _currentSessionUserId() {
    return ref.read(authStateProvider).value?.session?.user.id;
  }

  /// Persists the onboarding fitness signals (level + frequency) and stamps
  /// the completion anchor.
  ///
  /// The display name is NOT written here — it is collected on the signup
  /// form and lands on the profile row via the `handle_new_user` trigger
  /// (Option A — full-form signup). Onboarding now only collects fitness
  /// signals, so `upsertProfile` is called WITHOUT `displayName` (the repo
  /// treats it as omit-on-null, so an absent name preserves the trigger-seeded
  /// value rather than clobbering it).
  Future<void> saveOnboardingProfile({
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {
    final userId = _currentSessionUserId();
    if (userId == null) return;
    final repo = ref.read(profileRepositoryProvider);
    state = AsyncData(
      await repo.upsertProfile(
        userId: userId,
        fitnessLevel: fitnessLevel,
        trainingFrequencyPerWeek: trainingFrequencyPerWeek,
        // PR 1 — stamp the onboarding-completion anchor here, exactly
        // once. The router gate reads `profile.onboardedAt` to decide
        // /home vs /onboarding (the derived `needsOnboardingProvider`);
        // `DateTime.now()` survives process restart via the SQL column.
        onboardedAt: DateTime.now(),
      ),
    );
  }

  Future<void> updateTrainingFrequency(int frequency) async {
    final current = state.value;
    if (current == null) return;
    final userId = _currentSessionUserId();
    if (userId == null) return;
    final repo = ref.read(profileRepositoryProvider);
    state = await AsyncValue.guard(() async {
      await repo.updateTrainingFrequency(userId, frequency);
      return current.copyWith(trainingFrequencyPerWeek: frequency);
    });
  }

  Future<void> toggleWeightUnit() async {
    final current = state.value;
    if (current == null) return;
    final userId = _currentSessionUserId();
    if (userId == null) return;
    final newUnit = current.weightUnit == 'kg' ? 'lbs' : 'kg';
    final repo = ref.read(profileRepositoryProvider);
    state = await AsyncValue.guard(() async {
      await repo.updateWeightUnit(userId, newUnit);
      return current.copyWith(weightUnit: newUnit);
    });
  }
}
