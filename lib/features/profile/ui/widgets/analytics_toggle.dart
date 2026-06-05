import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/analytics_enabled_provider.dart';

/// Privacy-section toggle that opts the user in/out of product analytics
/// (`analytics_events` table writes).
///
/// Cluster: `data-protection-compliance`. Mirror of [CrashReportsToggle].
/// Mounted directly below the crash-reports toggle so both privacy
/// affordances live together in Profile → Settings → PRIVACY.
class AnalyticsToggle extends ConsumerWidget {
  const AnalyticsToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.sendUsageAnalytics),
          subtitle: Text(l10n.usageAnalyticsSubtitle),
          value: ref.watch(analyticsEnabledProvider),
          onChanged: (value) {
            ref.read(analyticsEnabledProvider.notifier).setEnabled(value);
          },
        ),
      ),
    );
  }
}
