import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/date_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../personal_records/providers/pr_providers.dart'
    show prCountProvider;
import '../../../workouts/providers/workout_history_providers.dart'
    show workoutCountProvider;
import '../../providers/profile_providers.dart';

/// Three-up stats row (workouts, PRs, member-since) shown beneath the
/// identity card. Workouts and PR cards are tappable and route to the
/// history / records screens respectively; member-since is read-only.
///
/// Self-contained data fetch: this widget watches `profileProvider` directly
/// for `createdAt` rather than receiving it through the constructor. The
/// parent screen also watches `profileProvider` (for `displayName` and
/// `trainingFrequencyPerWeek` which it must pass to other section widgets),
/// so there are two independent watches on the same provider — but Riverpod
/// dedupes the underlying subscription and `const StatsRow()` insulates this
/// widget from parent rebuilds. Keeping the read local avoids threading
/// `memberSince` through the screen just for one section.
class StatsRow extends ConsumerWidget {
  const StatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final workoutCountAsync = ref.watch(workoutCountProvider);
    final prCountAsync = ref.watch(prCountProvider);
    final profile = ref.watch(profileProvider);

    final workoutCount = workoutCountAsync.value ?? 0;
    final prCount = prCountAsync.value ?? 0;
    final memberSince = profile.value?.createdAt;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: l10n.workouts,
            value: '$workoutCount',
            icon: Icons.fitness_center,
            theme: theme,
            onTap: () => context.go('/home/history'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: l10n.prsLabel,
            value: '$prCount',
            icon: Icons.emoji_events,
            theme: theme,
            onTap: () => context.go('/records'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: l10n.memberSince,
            value: memberSince != null
                ? AppDateFormat.monthYear(
                    memberSince,
                    locale: Localizations.localeOf(context).languageCode,
                  )
                : '--',
            icon: Icons.calendar_today,
            theme: theme,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.theme,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final ThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;

    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            // Stat values ("42 workouts", "8 PRs", "Jan 24") are
            // data-display numerals — Rajdhani-tabular per the design
            // language. `titleMedium + w700` was Inter promoted to a
            // non-bundled weight, which read as "form field" rather
            // than "scoreboard" (UX-critic Phase 27 L18.4 ranked this
            // the biggest identity gap on the settings screen).
            style: AppTextStyles.numeric.copyWith(fontSize: 16),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: child,
      );
    }

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
