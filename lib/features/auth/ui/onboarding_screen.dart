import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// `app.TimeoutException` collides with `dart:async`'s `TimeoutException` —
// prefix the import so the typed-dispatch switch below can refer to both
// unambiguously even though only the AppException family is matched.
import '../../../core/exceptions/app_exception.dart' as app;
import '../../../core/device/platform_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../analytics/data/models/analytics_event.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../providers/auth_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Page 2: Profile setup state. The display name is collected on the signup
  // form now (Option A — full-form signup), so onboarding only gathers the
  // fitness signals below.
  String _fitnessLevel = 'beginner';
  int _trainingFrequency = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .saveOnboardingProfile(
            fitnessLevel: _fitnessLevel,
            trainingFrequencyPerWeek: _trainingFrequency,
          );

      // Fire analytics — best-effort, not awaited so it can't block navigation.
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        unawaited(
          ref
              .read(analyticsRepositoryProvider)
              .insertEvent(
                userId: userId,
                event: AnalyticsEvent.onboardingCompleted(
                  fitnessLevel: _fitnessLevel,
                  trainingFrequency: _trainingFrequency,
                ),
                platform: currentPlatform(),
                appVersion: currentAppVersion(),
              ),
        );
      }

      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      _showSaveErrorSnack(e);
    }
  }

  /// Maps the [AppException] subtype thrown by the profile save path to the
  /// localized snackbar copy + optional CTA that gives the user the right
  /// recovery affordance:
  ///
  ///   * [app.NetworkException] / [app.TimeoutException] → "you're offline"
  ///     (retry-after-reconnect is the recovery — no CTA needed).
  ///   * [app.AuthException] → "session expired" + "Sign in" CTA back to
  ///     `/login`. By the time this fires, [BaseRepository.refreshAndRetry]
  ///     has already tried one inline refresh, so re-login is the next
  ///     escalation.
  ///   * [app.DatabaseException] with code `'42501'` → "session expired" +
  ///     "Sign in" CTA back to `/login`. Same recovery shape as the
  ///     [app.AuthException] branch: when the repository's `refreshAndRetry`
  ///     succeeds at the refresh step but the second mutation ALSO surfaces
  ///     `42501`, the bearer-claim resolution is broken in a way the client
  ///     can't fix inline — re-login mints a fresh JWT. See
  ///     `base_repository.dart::refreshAndRetry` for the source-dive note
  ///     on why the second-attempt `42501` is server-side. Other
  ///     [app.DatabaseException] codes (e.g. `23xxx` CHECK violations) fall
  ///     through to the safety net deliberately — they aren't user-fixable
  ///     via re-auth.
  ///   * [app.ValidationException] → field-prefixed hint when the field
  ///     token is recognized, otherwise the generic "check your inputs"
  ///     copy (we deliberately do not leak unmapped field tokens to the UI).
  ///   * Any other shape → the existing `failedToSaveProfile` safety net.
  void _showSaveErrorSnack(Object error) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (error is app.NetworkException || error is app.TimeoutException) {
      // Cluster: persist-eats-duration — explicit `persist: false` on every
      // branch for symmetry with the AuthException branch below, so future
      // editors who attach a `SnackBarAction` to any branch can't trip the
      // silent "action sets persist:true" default that froze prior snacks.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.onboardingErrorOffline), persist: false),
      );
      return;
    }

    if (error is app.AuthException) {
      _showSessionExpiredSnack(messenger, l10n);
      return;
    }

    // Cluster: stale-token-silent-anon-fallback (candidate). When
    // `BaseRepository.refreshAndRetry`'s second attempt also fails with
    // PostgREST `42501` (RLS rejected the bearer's `auth.uid()` claim
    // even after a successful inline refresh), recovery is the same as
    // the [app.AuthException] branch: re-login mints a fresh JWT and
    // onboarding completes on the second attempt. SDK source-dive in
    // `base_repository.dart::refreshAndRetry` rules out a client-side
    // bearer-propagation race, so the bar surfaces the same "session
    // expired" copy + Sign in CTA — the user-recoverable affordance
    // works regardless of whether the underlying server-side cause is
    // ever diagnosed.
    //
    // Other [app.DatabaseException] codes (e.g. `23xxx` CHECK
    // violations) fall through to the safety net deliberately — those
    // aren't fixable by re-auth.
    if (error is app.DatabaseException && error.code == '42501') {
      _showSessionExpiredSnack(messenger, l10n);
      return;
    }

    if (error is app.ValidationException) {
      final fieldLabel = _localizedFieldLabel(error.field, l10n);
      final copy = fieldLabel == null
          ? l10n.onboardingErrorValidationGeneric
          : l10n.onboardingErrorValidationField(fieldLabel, error.message);
      // Cluster: persist-eats-duration — explicit `persist: false` for
      // symmetry with the AuthException branch (see comment above).
      messenger.showSnackBar(SnackBar(content: Text(copy), persist: false));
      return;
    }

    // Safety net — unmapped runtime types (including [app.DatabaseException]
    // and raw runtime errors that ErrorMapper passed through unchanged).
    // Cluster: persist-eats-duration — explicit `persist: false` for symmetry.
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.failedToSaveProfile), persist: false),
    );
  }

  /// Shared "session expired + Sign in CTA" SnackBar shown for both
  /// [app.AuthException] (the gotrue-401 path) and
  /// [app.DatabaseException] with code `'42501'` (the post-retry PostgREST
  /// RLS-rejection path). The two branches have identical recovery
  /// affordance — re-login mints a fresh JWT — so the SnackBar copy +
  /// CTA + dismissal contract is consolidated here. Keeping this as a
  /// single source of truth means a future change to the CTA's behavior
  /// (e.g. swapping `/login` for a soft re-auth modal) lands in one
  /// place, not two.
  ///
  /// Cluster: persist-eats-duration — explicit `persist: false` because
  /// the SnackBar defaults `persist` to true whenever an `action` is
  /// set, which would freeze the bar until manual dismissal. Explicit
  /// `false` keeps the default 4 s duration so the bar self-dismisses
  /// either on CTA press (Material auto-hides on `SnackBarAction.onPressed`)
  /// or after the timeout.
  ///
  /// Cluster: action-not-snackbaraction — uses [SnackBarAction] (not a
  /// bare `TextButton`) so Material's auto-dismiss-on-press behavior is
  /// preserved.
  void _showSessionExpiredSnack(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.onboardingErrorSessionExpired),
        persist: false,
        action: SnackBarAction(
          label: l10n.onboardingErrorSessionExpiredCta,
          onPressed: () {
            // GoRouter.of throws FlutterError when no GoRouter is in
            // context (widget tests). The auth-state listener handles
            // the redirect on the production path; swallowing the error
            // here keeps the action a no-op rather than crashing in
            // test contexts where the router isn't mounted.
            try {
              context.go('/login');
            } on FlutterError catch (_) {
              // Mirror of the `manage_data_screen.dart` pattern.
            }
          },
        ),
      ),
    );
  }

  /// Resolves a `ValidationException.field` token to the localized label
  /// already in use elsewhere on this form. Returning `null` signals "fall
  /// back to the generic validation copy" — we deliberately do not leak
  /// unrecognised raw tokens to the user.
  ///
  /// Today the only field the profile save path can realistically reject is
  /// the display name. New tokens land here when the data layer starts
  /// emitting them; future code reviewers should expand this switch in the
  /// same PR that introduces them.
  String? _localizedFieldLabel(String field, AppLocalizations l10n) {
    return switch (field) {
      'displayName' => l10n.displayName,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: Row(
                children: List.generate(2, (index) {
                  final isActive = index <= _currentPage;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.2,
                              ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                children: [
                  _WelcomePage(onNext: _nextPage),
                  _ProfileSetupPage(
                    fitnessLevel: _fitnessLevel,
                    onFitnessLevelChanged: (level) {
                      setState(() => _fitnessLevel = level);
                    },
                    trainingFrequency: _trainingFrequency,
                    onTrainingFrequencyChanged: (freq) {
                      setState(() => _trainingFrequency = freq);
                    },
                    onFinish: _finishOnboarding,
                    onBack: _previousPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Page 1: Welcome ---

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Wrap passive content in a semantics boundary so it does not
          // merge into the GradientButton's semantics node (which would
          // drop the button's `identifier` in the DOM).
          Semantics(
            container: true,
            child: Column(
              children: [
                // Brand sigil — the Arcane launcher-icon foreground. Sized
                // 128dp for the onboarding hero (one step up from the login
                // 96dp) since this is the very first frame new users see.
                Image.asset(
                  'assets/app_icon/arcane_sigil_foreground.png',
                  width: 128,
                  height: 128,
                ),
                const SizedBox(height: 32),
                Semantics(
                  container: true,
                  identifier: 'onboarding-welcome',
                  child: Text(
                    l10n.onboardingHeadline,
                    style: AppTextStyles.display.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.onboardingSubtitle,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: l10n.getStarted,
              onPressed: onNext,
              semanticsIdentifier: 'onboarding-get-started',
            ),
          ),
        ],
      ),
    );
  }
}

// --- Page 2: Profile Setup ---

class _ProfileSetupPage extends StatelessWidget {
  const _ProfileSetupPage({
    required this.fitnessLevel,
    required this.onFitnessLevelChanged,
    required this.trainingFrequency,
    required this.onTrainingFrequencyChanged,
    required this.onFinish,
    required this.onBack,
  });

  final String fitnessLevel;
  final ValueChanged<String> onFitnessLevelChanged;
  final int trainingFrequency;
  final ValueChanged<int> onTrainingFrequencyChanged;
  final VoidCallback onFinish;
  final VoidCallback onBack;

  static const _fitnessLevels = ['beginner', 'intermediate', 'advanced'];
  static const _frequencyOptions = [2, 3, 4, 5, 6];

  String _fitnessLevelLabel(String level, AppLocalizations l10n) {
    return switch (level) {
      'beginner' => l10n.fitnessLevelBeginner,
      'intermediate' => l10n.fitnessLevelIntermediate,
      'advanced' => l10n.fitnessLevelAdvanced,
      _ => level[0].toUpperCase() + level.substring(1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Text(
            l10n.setupProfile,
            style: AppTextStyles.headline.copyWith(fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tellUsAboutYourself,
            style: AppTextStyles.body.copyWith(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          Text(l10n.fitnessLevel, style: AppTextStyles.title),
          const SizedBox(height: 12),
          // BUG-028: branded pill replacement for the previous M3 ChoiceChip.
          // Uses surface2 (idle) → hotViolet (selected) per Arcane Ascent
          // tokens so onboarding stays inside the brand language already
          // established on the welcome page.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _fitnessLevels.map((level) {
              final isSelected = level == fitnessLevel;
              return Semantics(
                container: true,
                identifier: 'onboarding-$level',
                child: _BrandedPillChoice(
                  label: _fitnessLevelLabel(level, l10n),
                  isSelected: isSelected,
                  onTap: () => onFitnessLevelChanged(level),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text(l10n.howOftenTrain, style: AppTextStyles.title),
          const SizedBox(height: 4),
          Text(
            l10n.weeklyGoalHint,
            style: AppTextStyles.bodySmall.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 12),
          // BUG-028: same branded pill treatment for the weekly frequency
          // selector — keeps both selectors visually consistent.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _frequencyOptions.map((freq) {
              final isSelected = freq == trainingFrequency;
              return Semantics(
                container: true,
                identifier: 'onboarding-freq-$freq',
                child: _BrandedPillChoice(
                  label: '${freq}x',
                  isSelected: isSelected,
                  onTap: () => onTrainingFrequencyChanged(freq),
                ),
              );
            }).toList(),
          ),
          const Spacer(),
          GradientButton(
            label: l10n.letsGo,
            onPressed: onFinish,
            semanticsIdentifier: 'onboarding-lets-go',
          ),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              container: true,
              identifier: 'onboarding-back',
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(l10n.back),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// BUG-028: branded pill replacement for `ChoiceChip`. Idle uses surface2
/// + textCream label; selected uses primaryViolet fill + textCream label,
/// with a hotViolet border in both states (alpha 0.4 idle, full when
/// selected) so the pill reads as a consistent brand element.
///
/// **Selected fill choice (post-review fix):** the original draft used
/// [AppColors.hotViolet] (#B36DFF) as the selected fill, but `textCream`
/// (#EEE7FA) over `hotViolet` only achieves a 2.67:1 contrast ratio — well
/// below WCAG AA's 4.5:1 floor for normal text. Switching the selected fill
/// to [AppColors.primaryViolet] (#6A2FA8) lifts the ratio to ~6.69:1 while
/// preserving the violet brand language. The selected indicator is the
/// fill itself — its 6.69:1 contrast against the surrounding card surface
/// unambiguously conveys selected state. The hotViolet border (full alpha
/// when selected, 0.4 alpha when idle) is a decorative brand element and
/// is not relied on as a non-text UI cue: hotViolet against primaryViolet
/// only reaches 2.53:1, which would not satisfy WCAG 1.4.11's 3:1 floor
/// for non-text components if it were the sole indicator.
///
/// **Sizing:** We deliberately keep this compact (matches the natural
/// `ChoiceChip` footprint, ~32dp tall) so two `Wrap` rows fit on the
/// non-scrollable profile-setup page without overflowing the available
/// height on small viewports / test surfaces. The `InkWell` keeps a 48dp
/// Material tap target via the default [MaterialTapTargetSize.padded]
/// behavior even though the visible pill is ~32dp.
class _BrandedPillChoice extends StatelessWidget {
  const _BrandedPillChoice({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusSm + 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryViolet : AppColors.surface2,
            border: Border.all(
              color: isSelected
                  ? AppColors.hotViolet
                  : AppColors.hotViolet.withValues(alpha: 0.4),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(kRadiusSm + 2),
          ),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: AppColors.textCream,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
