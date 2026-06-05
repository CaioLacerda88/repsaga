import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/notifiers/auth_notifier.dart';
import '../../workouts/providers/workout_history_providers.dart'
    show workoutCountProvider;
import '../providers/data_export_providers.dart';
import '../providers/manage_data_providers.dart';

class ManageDataScreen extends ConsumerWidget {
  const ManageDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final workoutCount = ref.watch(workoutCountProvider);

    final workoutCountValue = workoutCount.value ?? 0;

    final workoutCountText = workoutCount.when(
      data: (v) => '$v',
      loading: () => '...',
      error: (_, _) => '0',
    );

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'manage-data-heading',
          child: Text(l10n.manageDataTitle),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // YOUR DATA section — Legal PR 3 (#TODO-PR url) implements the
            // LGPD Art. 18 V / GDPR Art. 20 portability mechanism the
            // Privacy Policy §6 row promises. Cluster:
            // data-protection-compliance. Sits ABOVE the destructive
            // sections so the read-only export action is the first thing
            // the user sees on Manage Data — discoverable, separated from
            // the "remove" affordances by visual grouping (label color
            // + section gap).
            Text(
              l10n.yourDataSection,
              style: AppTextStyles.sectionHeader.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            _DataManagementTile(
              title: l10n.exportMyData,
              subtitle: l10n.exportMyDataSubtitle,
              onTap: () => _showExportSheet(context, ref),
              semanticsIdentifier: 'manage-data-export',
            ),
            const SizedBox(height: 24),
            // WORKOUT HISTORY section
            Text(
              l10n.workoutHistorySection,
              style: AppTextStyles.sectionHeader.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            _DataManagementTile(
              title: l10n.deleteWorkoutHistory,
              subtitle: l10n.workoutsWillBeRemoved(workoutCountText),
              onTap: () =>
                  _showDeleteHistoryDialog(context, ref, workoutCountValue),
              semanticsIdentifier: 'manage-data-delete-history',
            ),
            const SizedBox(height: 24),
            // DANGER section
            Text(
              l10n.dangerSection,
              style: AppTextStyles.sectionHeader.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            _DataManagementTile(
              title: l10n.resetAllAccountData,
              subtitle: l10n.resetAllSubtitle,
              onTap: () => _showResetAllModal(context, ref),
              semanticsIdentifier: 'manage-data-reset-all',
              danger: true,
              // [AppTextStyles.title] = Inter 600 16dp — the bundled
              // SemiBold. Prior `titleMedium + w700` requested Inter
              // Bold (700), which isn't bundled — google_fonts would
              // nearest-match to w600 silently. Routing through the
              // sanctioned token makes this deterministic.
              titleStyle: AppTextStyles.title,
            ),
            const SizedBox(height: 8),
            _DataManagementTile(
              title: l10n.deleteAccount,
              subtitle: l10n.deleteAccountSubtitle,
              onTap: () => _showDeleteAccountModal(context, ref),
              danger: true,
              // [AppTextStyles.title] = Inter 600 16dp — the bundled
              // SemiBold. Prior `titleMedium + w700` requested Inter
              // Bold (700), which isn't bundled — google_fonts would
              // nearest-match to w600 silently. Routing through the
              // sanctioned token makes this deterministic.
              titleStyle: AppTextStyles.title,
            ),
          ],
        ),
      ),
    );
  }

  /// Drive the JSON export flow.
  ///
  /// **Cluster: `data-protection-compliance`.** This handler is the
  /// in-app implementation of the Privacy Policy §6 Portability row.
  /// Shows a non-dismissible loading dialog (the aggregation queries can
  /// take 2-5s for users with rich history) while
  /// [ExportJobController.exportAndShare] runs; on success, hands the
  /// generated JSON XFile to the native share sheet via `share_plus` and
  /// dismisses with a success snackbar. On failure surfaces a safe error
  /// snackbar (no raw cause leaked — see [ExportException.userMessage]).
  ///
  /// **`persist: false` on both snackbars** (cluster:
  /// `persist-eats-duration`). The snackbar API silently defaults to
  /// `persist = action != null`, so even SnackBars without an explicit
  /// action would survive auto-dismissal if a future refactor adds one.
  /// Setting `persist: false` explicitly pins the four-second timeout.
  Future<void> _showExportSheet(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    // Mirror the delete-account loading-dialog pattern so the user can't
    // tap other destructive tiles while the export runs. PopScope keeps
    // the OS back gesture from dismissing mid-encode.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    l10n.dataExportPreparing,
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await ref.read(exportJobProvider.notifier).exportAndShare(userId);

    if (!context.mounted) return;
    // Dismiss the loading dialog via the rootNavigator so we pop the
    // dialog route rather than the underlying screen — same discipline
    // the delete-account handler uses.
    Navigator.of(context, rootNavigator: true).pop();

    final state = ref.read(exportJobProvider);
    if (!context.mounted) return;

    if (state.hasError) {
      final error = state.error;
      final message = error is AppException
          ? error.userMessage
          : l10n.pleaseTryAgain;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Cluster: persist-eats-duration. Explicit false defends against
          // future refactors that add an action to this snackbar — the
          // SnackBar API silently defaults to `persist = action != null`,
          // so adding any action would otherwise pin the bar on screen
          // until manual dismissal.
          // ignore: avoid_redundant_argument_values
          persist: false,
          duration: const Duration(seconds: 4),
          content: Semantics(
            container: true,
            identifier: 'manage-data-export-failed',
            child: Text(l10n.dataExportFailed(message)),
          ),
        ),
      );
      // Reset so the next tap starts fresh.
      ref.read(exportJobProvider.notifier).reset();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // Cluster: persist-eats-duration. Same rationale as the error
        // path above — explicit `persist: false` survives a future
        // editor adding an action without flipping to indefinite display.
        // ignore: avoid_redundant_argument_values
        persist: false,
        duration: const Duration(seconds: 4),
        content: Semantics(
          container: true,
          identifier: 'manage-data-export-success',
          child: Text(l10n.dataExportSuccess),
        ),
      ),
    );
    ref.read(exportJobProvider.notifier).reset();
  }

  Future<void> _showDeleteHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    int workoutCount,
  ) async {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // First dialog
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l10n.deleteAllHistoryTitle),
          content: Text(l10n.deleteAllHistoryContent(workoutCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            Semantics(
              container: true,
              identifier: 'manage-data-delete-confirm',
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: Text(l10n.deleteHistoryButton),
              ),
            ),
          ],
        );
      },
    );

    if (first != true || !context.mounted) return;

    // Second dialog
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l10n.areYouSure),
          content: Text(l10n.prsRoutinesKept),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            Semantics(
              container: true,
              identifier: 'manage-data-yes-delete',
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: Text(l10n.yesDelete),
              ),
            ),
          ],
        );
      },
    );

    if (second != true || !context.mounted) return;

    HapticFeedback.heavyImpact();
    try {
      await clearWorkoutHistory(ref);
    } on AppException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToClearHistory(e.userMessage))),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(
          container: true,
          identifier: 'manage-data-history-cleared',
          child: Text(l10n.historyCleared),
        ),
      ),
    );
  }

  Future<void> _showResetAllModal(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ResetAllDialog(),
    );

    if (confirmed != true || !context.mounted) return;

    HapticFeedback.heavyImpact();
    try {
      await resetAllAccountData(ref);
    } on AppException catch (e) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToResetData(e.userMessage))),
      );
      return;
    }
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(
          container: true,
          identifier: 'manage-data-account-reset',
          child: Text(l10n.accountDataReset),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountModal(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DeleteAccountDialog(),
    );

    if (confirmed != true || !context.mounted) return;

    HapticFeedback.heavyImpact();

    // Show a non-dismissible loading dialog while the Edge Function call is
    // in flight (1-3s typical). Prevents the user from tapping other
    // destructive actions or navigating away mid-delete.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    await ref.read(authNotifierProvider.notifier).deleteAccount();

    if (!context.mounted) return;
    // Dismiss the loading dialog via the root navigator so we pop the
    // dialog route rather than the underlying screen.
    Navigator.of(context, rootNavigator: true).pop();

    // AsyncValue.guard captures exceptions inside the notifier state, so we
    // inspect it after the call rather than using try/catch.
    final state = ref.read(authNotifierProvider);
    final error = state.error;
    if (error != null) {
      final l10n = AppLocalizations.of(context);
      final message = error is AppException
          ? error.userMessage
          : l10n.pleaseTryAgain;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToDeleteAccount(message))),
      );
      return;
    }
    // Explicitly redirect — the auth state listener should also trigger a
    // redirect, but navigating here avoids race conditions with the loading
    // dialog and stream timing.
    if (context.mounted) {
      try {
        context.go('/login');
      } on FlutterError catch (_) {
        // GoRouter.of throws FlutterError when no GoRouter is in context
        // (widget tests). Auth listener handles the redirect instead.
      }
    }
  }
}

/// Reusable tile for data management options.
class _DataManagementTile extends StatelessWidget {
  const _DataManagementTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.titleStyle,
    this.semanticsIdentifier,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final TextStyle? titleStyle;

  /// Optional Semantics identifier for locale-independent E2E selectors.
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = danger
        ? theme.colorScheme.error.withValues(alpha: 0.12)
        : theme.cardTheme.color ?? theme.colorScheme.surface;

    Widget tile = Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: titleStyle),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
    if (semanticsIdentifier != null) {
      tile = Semantics(
        container: true,
        identifier: semanticsIdentifier,
        child: tile,
      );
    }
    return tile;
  }
}

class _ResetAllDialog extends StatefulWidget {
  const _ResetAllDialog();

  @override
  State<_ResetAllDialog> createState() => _ResetAllDialogState();
}

class _ResetAllDialogState extends State<_ResetAllDialog> {
  final _controller = TextEditingController();
  bool _isResetTyped = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // The confirmation keyword "RESET" is intentionally locale-independent.
    // Users must type the exact English word regardless of their locale
    // setting. This is a safety measure — not a localization oversight.
    final typed = _controller.text.trim().toUpperCase() == 'RESET';
    if (typed != _isResetTyped) {
      setState(() => _isResetTyped = typed);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.resetAccountData),
          leading: Semantics(
            container: true,
            identifier: 'manage-data-reset-cancel',
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(false),
              tooltip: l10n.cancel,
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                l10n.resetAccountWarning,
                style: AppTextStyles.body.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.typeResetToConfirm,
                style: AppTextStyles.body.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  // Hint text is intentionally the English keyword — see
                  // _onTextChanged comment above.
                  hintText: 'RESET',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: l10n.resetAccountButton,
                      onPressed: _isResetTyped
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      gradient: AppTheme.destructiveGradient,
                      semanticsIdentifier: 'manage-data-reset-btn',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _isDeleteTyped = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // The confirmation keyword "DELETE" is intentionally locale-independent.
    // Users must type the exact English word regardless of their locale
    // setting. This is a safety measure — not a localization oversight.
    final typed = _controller.text.trim().toUpperCase() == 'DELETE';
    if (typed != _isDeleteTyped) {
      setState(() => _isDeleteTyped = typed);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.deleteAccountButton),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
            tooltip: l10n.cancel,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                l10n.deleteAccountWarning,
                style: AppTextStyles.body.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.typeDeleteToConfirm,
                style: AppTextStyles.body.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  // Hint text is intentionally the English keyword — see
                  // _onTextChanged comment above.
                  hintText: 'DELETE',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: l10n.deleteAccountButton,
                      onPressed: _isDeleteTyped
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      gradient: AppTheme.destructiveGradient,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
