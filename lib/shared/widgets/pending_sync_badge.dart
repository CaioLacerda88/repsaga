import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/pending_sync_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../l10n/app_localizations.dart';
import 'pending_sync_sheet.dart';

/// A slim full-width tappable row that shows the number of pending sync items.
///
/// Renders nothing when the queue is empty. Tapping opens a modal bottom
/// sheet with retry controls for each queued action.
class PendingSyncBadge extends ConsumerWidget {
  const PendingSyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingSyncProvider);

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final label = count == 1
        ? l10n.pendingSyncBadgeSingular
        : l10n.pendingSyncBadgePlural(count);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: count == 0
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Padding(
              key: const ValueKey('badge'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                container: true,
                identifier: 'offline-pending-badge',
                // BUG-021: Semantics label was hardcoded English. Composed
                // through `pendingSyncBadgeSemantics(label)` so the localized
                // visible string flows into the localized hint suffix.
                label: l10n.pendingSyncBadgeSemantics(label),
                button: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kRadiusMd),
                    onTap: () => _showSyncSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(kRadiusMd),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 20,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              style: AppTextStyles.label.copyWith(
                                fontSize: 13,
                                letterSpacing: 0.12 * 13,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  void _showSyncSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PendingSyncSheet(),
    );
  }
}
