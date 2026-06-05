import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/bodyweight_consent_provider.dart';

/// Privacy-section toggle that surfaces the body-weight sensitive-data
/// consent state. Flipping the switch off is the documented withdrawal
/// path (LGPD Art. 11 / GDPR Art. 7(3) right to withdraw consent).
///
/// Cluster: `data-protection-compliance`. Mirrors [CrashReportsToggle]
/// shape; the underlying provider semantics differ — see
/// [BodyweightConsentNotifier] for the opt-in default rationale.
class BodyweightConsentToggle extends ConsumerWidget {
  const BodyweightConsentToggle({super.key});

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
          title: Text(l10n.bodyweightConsentToggleTitle),
          subtitle: Text(l10n.bodyweightConsentToggleSubtitle),
          value: ref.watch(bodyweightConsentProvider),
          onChanged: (value) {
            ref.read(bodyweightConsentProvider.notifier).setEnabled(value);
          },
        ),
      ),
    );
  }
}
