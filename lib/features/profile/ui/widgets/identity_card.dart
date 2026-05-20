import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../features/auth/providers/auth_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/profile_providers.dart';

/// Avatar + display-name + email card at the top of the profile settings
/// screen. Tap on the name opens the rename dialog.
class IdentityCard extends StatelessWidget {
  const IdentityCard({
    super.key,
    required this.displayName,
    required this.email,
    this.loading = false,
    this.onEditName,
  });

  final String? displayName;
  final String email;
  final bool loading;
  final VoidCallback? onEditName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final name = displayName ?? l10n.gymUser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                (displayName?.isNotEmpty == true
                        ? displayName![0]
                        : email.isNotEmpty
                        ? email[0]
                        : '?')
                    .toUpperCase(),
                // [AppTextStyles.headline] = Rajdhani 600 24dp — the
                // bundled SemiBold weight. Prior `headlineMedium +
                // FontWeight.bold` requested Rajdhani 700, which IS
                // bundled but the call site mixed token + raw weight
                // override; routing through the token directly avoids
                // unbundled-weight risk and reads cleaner.
                style: AppTextStyles.headline.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: loading
                  ? const _LoadingPlaceholder()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: onEditName,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              if (onEditName != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 16, child: LinearProgressIndicator());
  }
}

/// Opens the rename dialog and, on submit, persists the new display name
/// via the profile repository and invalidates `profileProvider`.
Future<void> showEditDisplayNameDialog(
  BuildContext context,
  WidgetRef ref,
  String? currentName,
) async {
  final controller = TextEditingController(text: currentName ?? '');
  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final dialogTheme = Theme.of(ctx);
      final l10n = AppLocalizations.of(ctx);
      return AlertDialog(
        backgroundColor: dialogTheme.cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLg),
        ),
        title: Text(l10n.editDisplayName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.enterYourName),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      );
    },
  );

  if (newName == null || newName.isEmpty || !context.mounted) return;

  final user = ref.read(authRepositoryProvider).currentUser;
  if (user == null) return;

  await ref
      .read(profileRepositoryProvider)
      .upsertProfile(userId: user.id, displayName: newName);
  ref.invalidate(profileProvider);
}
