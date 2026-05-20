import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity/connectivity_provider.dart';
import '../../core/offline/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../l10n/app_localizations.dart';

/// An in-flow card that surfaces terminal sync failures on the home screen.
///
/// Hidden when there are no terminal failures or when the device is offline
/// (the [OfflineBanner] owns that state). Provides "Retry" and "Dismiss"
/// actions that delegate to [SyncService].
class SyncFailureCard extends ConsumerWidget {
  const SyncFailureCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncServiceProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final count = syncState.terminalFailureCount;

    if (count == 0 || !isOnline) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final label = count == 1
        ? l10n.syncFailureSingular
        : l10n.syncFailurePlural(count);

    return Semantics(
      container: true,
      identifier: 'offline-failure-card',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border(
              left: BorderSide(color: theme.colorScheme.error, width: 4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.title.copyWith(
                        fontSize: 14,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    Semantics(
                      container: true,
                      identifier: 'offline-failure-subtitle',
                      child: Text(
                        l10n.savedLocallyRetry,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                container: true,
                identifier: 'offline-dismiss',
                child: TextButton(
                  onPressed: () => ref
                      .read(syncServiceProvider.notifier)
                      .dismissTerminalItems(),
                  child: Text(
                    l10n.dismiss,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                container: true,
                identifier: 'offline-retry',
                child: TextButton(
                  onPressed: () => _handleRetry(context, ref),
                  child: Text(l10n.retry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleRetry(BuildContext context, WidgetRef ref) {
    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.offlineRetryHint)));
      return;
    }
    ref.read(syncServiceProvider.notifier).retryTerminalItems();
  }
}
