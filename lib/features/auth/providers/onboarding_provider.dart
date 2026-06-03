import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/providers/profile_providers.dart';
import 'auth_providers.dart';

/// PR 1 — derived from the profile row's `onboarded_at` column instead of an
/// in-memory `StateProvider<bool>`. Eliminates the state-machine drift class
/// captured by audit defects D1 / D2 / D11: a process restart no longer wipes
/// the flag and lets a half-onboarded user land on `/home`.
///
/// Derivation:
///   * `false` when no session (we never render the onboarding screen for
///     anonymous users — the redirect chain sends them to `/login` first).
///   * `false` when the profile is still loading (the router parks on
///     `/splash` separately — this provider must NOT flip to `true` mid-load
///     and trigger a spurious `/onboarding` push before the profile arrives).
///   * `false` when the profile row exists and `onboardedAt != null`.
///   * `true`  when the profile row is null OR `onboardedAt == null` — both
///     signal a user who has not completed the flow.
///
/// Cluster: `provider-init-timing`. Watching `profileProvider` directly inside
/// a derived `Provider<bool>` keeps the redirect callback aware of profile
/// arrival — the router's `_RouterRefreshListenable` also listens to
/// `profileProvider` so the redirect re-evaluates when the profile resolves.
final needsOnboardingProvider = Provider<bool>((ref) {
  final session = ref.watch(authStateProvider).value?.session;
  if (session == null) return false;
  final profile = ref.watch(profileProvider);
  // Profile still loading → don't claim onboarding-needed. The router gate
  // parks on /splash separately (see `app_router.dart` redirect). Returning
  // false here keeps this provider monotonically aligned with the actual
  // post-load state — no transient `true → false` flip on profile arrival.
  if (profile.isLoading) return false;
  final value = profile.value;
  if (value == null) return true;
  return value.onboardedAt == null;
});
