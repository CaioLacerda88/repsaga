import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../features/auth/providers/auth_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/profile_providers.dart';
import 'profile_avatar.dart';

/// Avatar + display-name + email card at the top of the profile settings
/// screen. Tap on the name opens the rename dialog; tap on the avatar
/// dispatches the [onAvatarTap] callback (typically opening the
/// picker → crop → upload flow on the parent screen).
class IdentityCard extends StatelessWidget {
  const IdentityCard({
    super.key,
    required this.displayName,
    required this.email,
    this.loading = false,
    this.onEditName,
    this.onAvatarTap,
  });

  final String? displayName;
  final String email;
  final bool loading;
  final VoidCallback? onEditName;

  /// Phase 32 PR 32e — tap callback for the avatar (drives the
  /// picker → crop → upload flow on the parent screen). When null the
  /// avatar is rendered but not tappable.
  final VoidCallback? onAvatarTap;

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
            // Phase 32 PR 32e — `ProfileAvatar` replaces the inline
            // `CircleAvatar` + monogram. The widget reads
            // displayName / avatarUrl / dominantBodyPart from
            // current-user providers when no explicit override is
            // passed; here we forward the display name + email so the
            // monogram derives from the IdentityCard's own props
            // instead of double-reading providers.
            Semantics(
              container: true,
              identifier: 'identity-card-avatar',
              button: onAvatarTap != null,
              child: GestureDetector(
                onTap: onAvatarTap,
                behavior: HitTestBehavior.opaque,
                child: ProfileAvatar(
                  size: 64,
                  displayName: displayName ?? (email.isNotEmpty ? email : null),
                  semanticsLabel: 'Profile avatar for $name',
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
                                  style: AppTextStyles.title.copyWith(
                                    fontSize: 20,
                                  ),
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
                            style: AppTextStyles.body.copyWith(
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
