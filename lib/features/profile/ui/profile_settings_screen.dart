import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/profile_providers.dart';
import 'widgets/bodyweight_row.dart';
import 'widgets/crash_reports_toggle.dart';
import 'widgets/identity_card.dart';
import 'widgets/legal_tile.dart';
import 'widgets/logout_button.dart';
import 'widgets/manage_data_tile.dart';
import 'widgets/profile_language_row.dart';
import 'widgets/stats_row.dart';
import 'widgets/weekly_goal_row.dart';
import 'widgets/weight_unit_toggle.dart';

/// Profile settings sub-screen — pushed from the character sheet's gear icon.
///
/// Carries the entire pre-Phase-18b `/profile` content (display name editor,
/// stats row, locale picker, weight unit, weekly goal, manage data, legal,
/// crash reports, sign out). The character sheet (`/profile`) replaced the
/// previous identity surface; this screen preserves all the account/account
/// preferences functionality 1:1 — no behavioural changes intended.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);
    final email = ref.watch(authRepositoryProvider).currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsLabel)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Semantics(
                container: true,
                identifier: 'profile-heading',
                child: Text(
                  l10n.profile,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 24),
              // Identity card
              profileAsync.when(
                data: (profile) => IdentityCard(
                  displayName: profile?.displayName,
                  email: email,
                  onEditName: () => showEditDisplayNameDialog(
                    context,
                    ref,
                    profile?.displayName,
                  ),
                ),
                loading: () => const IdentityCard(
                  displayName: null,
                  email: '',
                  loading: true,
                ),
                error: (_, _) =>
                    const IdentityCard(displayName: null, email: ''),
              ),
              const SizedBox(height: 24),
              // Stats section
              const StatsRow(),
              const SizedBox(height: 32),
              // Weight unit section
              Text(
                l10n.weightUnit,
                // [sectionHeader] — Inter 600 12dp +0.12em tracking.
                // Section labels are eyebrow register, not list-item
                // titles; prior `titleMedium` rendered at 16dp which
                // gave them the same weight as `RoutineCard` titles
                // and broke the section rhythm (Phase 27 L18.4).
                style: AppTextStyles.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) =>
                    WeightUnitToggle(weightUnit: profile?.weightUnit ?? 'kg'),
                loading: () => const WeightUnitToggle(weightUnit: 'kg'),
                error: (_, _) => const WeightUnitToggle(weightUnit: 'kg'),
              ),
              const SizedBox(height: 24),
              // Body weight section (Phase 24c — XP load multiplier for
              // bodyweight exercises like pull-ups, dips, push-ups).
              Text(
                l10n.profileBodyweightLabel,
                style: AppTextStyles.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) => BodyweightRow(profile: profile),
                loading: () => const BodyweightRow(profile: null),
                error: (_, _) => const BodyweightRow(profile: null),
              ),
              const SizedBox(height: 24),
              // Weekly goal section
              Semantics(
                container: true,
                identifier: 'profile-goal-label',
                child: Text(
                  l10n.weeklyGoal,
                  style: AppTextStyles.sectionHeader,
                ),
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) => WeeklyGoalRow(
                  frequency: profile?.trainingFrequencyPerWeek ?? 3,
                ),
                loading: () => const WeeklyGoalRow(frequency: 3),
                error: (_, _) => const WeeklyGoalRow(frequency: 3),
              ),
              const SizedBox(height: 32),
              // Preferences section
              Text(
                l10n.preferences,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              ProfileLanguageRow(locale: ref.watch(localeProvider)),
              const SizedBox(height: 32),
              // Data management section
              Text(
                l10n.dataManagement,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              const ManageDataTile(),
              const SizedBox(height: 24),
              // Legal section
              Text(
                l10n.legal,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              LegalTile(
                title: l10n.privacyPolicy,
                icon: Icons.privacy_tip_outlined,
                onTap: () => context.push('/privacy-policy'),
              ),
              const SizedBox(height: 8),
              LegalTile(
                title: l10n.termsOfService,
                icon: Icons.description_outlined,
                onTap: () => context.push('/terms-of-service'),
              ),
              const SizedBox(height: 24),
              // Privacy section
              Text(
                l10n.privacySection,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              const CrashReportsToggle(),
              const SizedBox(height: 24),
              // Logout button
              const LogoutButton(),
            ],
          ),
        ),
      ),
    );
  }
}
