import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/pending_action.dart';
import '../../core/offline/pending_sync_provider.dart';
import '../../core/offline/sync_error_mapper.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../l10n/app_localizations.dart';

/// Modal bottom sheet listing all pending offline actions with retry controls.
///
/// Each row shows the action type, timestamp, and a CTA whose label and
/// behavior depend on the action's last classified error category
/// (BUG-008): transient / network / unknown errors get "Retry"; only
/// structural and session errors that retry definitively won't fix get
/// "Dismiss" (which dequeues the item). On first display (no prior error)
/// the CTA is always "Retry".
///
/// `unknown` is intentionally permissive — a genuinely unfamiliar exception
/// class might be a one-off plugin crash that retry resolves; if the
/// underlying issue IS structural, the next attempt will surface a more
/// specific exception class that gets routed to [SyncErrorCategory.structural]
/// and switches the CTA to "Dismiss" on its own. Forcing terminal here
/// would strip the user's only recovery path with no diagnostic upside.
class PendingSyncSheet extends ConsumerStatefulWidget {
  const PendingSyncSheet({super.key});

  @override
  ConsumerState<PendingSyncSheet> createState() => _PendingSyncSheetState();
}

class _PendingSyncSheetState extends ConsumerState<PendingSyncSheet> {
  /// Per-item loading states keyed by action ID.
  final _retrying = <String>{};

  /// Per-item error messages keyed by action ID.
  final _errors = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Watch the count so the sheet rebuilds when items are dequeued.
    final count = ref.watch(pendingSyncProvider);
    final actions = count > 0
        ? ref.read(pendingSyncProvider.notifier).getAll()
        : const <PendingAction>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  l10n.pendingSyncTitle,
                  style: AppTextStyles.title.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.itemCount(actions.length),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: actions.isEmpty
                ? Center(
                    child: Text(
                      l10n.allSynced,
                      style: AppTextStyles.body.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: actions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) => _ActionRow(
                      action: actions[index],
                      isRetrying: _retrying.contains(actions[index].id),
                      error: _errors[actions[index].id],
                      onRetry: () => _retry(actions[index].id),
                      onDismiss: () => _dismiss(actions[index].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _retry(String id) async {
    setState(() {
      _retrying.add(id);
      _errors.remove(id);
    });

    try {
      await ref.read(pendingSyncProvider.notifier).retryItem(id);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.syncedSuccessfully)));
      }
    } catch (e) {
      // BUG-042: never surface raw exception strings. The mapper
      // localizes by exception class (PostgrestException -> generic retry
      // copy, AuthException -> session expired, etc.) and the raw error
      // goes to developer.log + Sentry inside the mapper.
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        final userMessage = SyncErrorMapper.toUserMessage(l10n, e);
        setState(() {
          _errors[id] = userMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _retrying.remove(id);
        });
      }
    }
  }

  /// BUG-008: dequeue a structurally-failed action without retrying.
  Future<void> _dismiss(String id) async {
    await ref.read(pendingSyncProvider.notifier).dismissItem(id);
    if (mounted) {
      setState(() {
        _errors.remove(id);
        _retrying.remove(id);
      });
    }
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.isRetrying,
    required this.error,
    required this.onRetry,
    required this.onDismiss,
  });

  final PendingAction action;
  final bool isRetrying;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  IconData get _icon => switch (action) {
    PendingSaveWorkout() => Icons.fitness_center,
    PendingUpsertRecords() => Icons.emoji_events,
    PendingMarkRoutineComplete() => Icons.check_circle_outline,
    PendingCreateExercise() => Icons.add_circle_outline,
  };

  String _label(AppLocalizations l10n) => switch (action) {
    PendingSaveWorkout() => l10n.pendingActionSaveWorkout,
    PendingUpsertRecords() => l10n.pendingActionUpdateRecords,
    PendingMarkRoutineComplete() => l10n.pendingActionMarkComplete,
    PendingCreateExercise() => l10n.pendingActionCreateExercise,
  };

  /// BUG-008: the CTA depends on the last classified error category. Only
  /// errors retry definitively cannot fix — structural (FK / RLS / cast)
  /// and session (expired token) — show "Dismiss". Everything else,
  /// including [SyncErrorCategory.unknown], keeps the retry CTA so the
  /// user has a recovery path; structural errors that initially classify
  /// as `unknown` will surface a more specific exception class on the next
  /// attempt and flip to "Dismiss" then.
  bool get _isStructural => switch (action.errorCategory) {
    SyncErrorCategory.structural || SyncErrorCategory.session => true,
    SyncErrorCategory.none ||
    SyncErrorCategory.network ||
    SyncErrorCategory.transient ||
    SyncErrorCategory.unknown => false,
  };

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final structural = _isStructural;

    // The body shown beneath the row: prefer the (already-localized) live
    // retry error from the parent state; otherwise, if the persisted
    // error category is structural, show the canned structural copy so the
    // user understands why "Dismiss" replaced "Retry".
    final bodyError =
        error ?? (structural ? l10n.syncErrorStructuralBody : null);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(l10n),
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${l10n.queuedAt(_formatTime(action.queuedAt))}'
                      '${action.retryCount > 0 ? ' · ${l10n.retryCount(action.retryCount)}' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isRetrying)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.tonal(
                  onPressed: structural ? onDismiss : onRetry,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: Text(structural ? l10n.syncDismissAction : l10n.retry),
                ),
            ],
          ),
          if (bodyError != null) ...[
            const SizedBox(height: 4),
            Text(
              bodyError,
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
