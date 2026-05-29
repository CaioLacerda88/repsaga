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
class IdentityCard extends ConsumerWidget {
  const IdentityCard({
    super.key,
    required this.displayName,
    required this.email,
    required this.avatarSemanticsLabel,
    this.loading = false,
    this.onEditName,
    this.onAvatarTap,
  });

  final String? displayName;
  final String email;

  /// Pre-localized semantics label for the avatar surface. Resolved at
  /// the screen layer via `l10n.avatarSemanticsLabel(name)` and passed in
  /// — per `feedback_widget_l10n_parameterization` the widget never
  /// reads [AppLocalizations.of] for tunable text.
  final String avatarSemanticsLabel;

  final bool loading;
  final VoidCallback? onEditName;

  /// Tap callback for the avatar (drives the picker → crop → upload flow
  /// on the parent screen). When null the avatar is rendered but not
  /// tappable.
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final name = displayName ?? l10n.gymUser;
    final uploadInProgress = ref.watch(avatarUploadInProgressProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // `ProfileAvatar` carries the monogram / gradient / uploaded-
            // image render path. We forward the display name + email so
            // the monogram derives from the IdentityCard's own props
            // instead of double-reading providers; uploadInProgress drives
            // the loading scrim on top of the disc.
            //
            // cluster: semantics-identifier-pair-rule — `container:true +
            // explicitChildNodes:true` is required for the AOM to surface
            // the identifier as a stable hit target; without
            // `explicitChildNodes` the monogram glyph would merge into
            // the parent's label and break the role.
            Semantics(
              container: true,
              explicitChildNodes: true,
              identifier: 'identity-card-avatar',
              button: onAvatarTap != null,
              child: GestureDetector(
                onTap: onAvatarTap,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatar(
                      size: 64,
                      displayName:
                          displayName ?? (email.isNotEmpty ? email : null),
                      loading: uploadInProgress,
                      semanticsLabel: avatarSemanticsLabel,
                    ),
                    if (onAvatarTap != null)
                      const Positioned(
                        bottom: 0,
                        right: 0,
                        child: _CameraEditBadge(),
                      ),
                  ],
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

/// Small camera-icon badge anchored to the bottom-right of the avatar so
/// the surface reads as tappable. Without this affordance the avatar
/// looks like a passive monogram disc — the gesture detector is
/// invisible to first-time users. The badge persists after the first
/// upload (still tappable to replace the picture).
class _CameraEditBadge extends StatelessWidget {
  const _CameraEditBadge();

  @override
  Widget build(BuildContext context) {
    // 22dp diameter (not 20dp): provides 5dp icon padding instead of 4dp so
    // the camera glyph stays readable on 160dpi devices without looking
    // oversized at the 64dp avatar register.
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface2,
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      child: const Center(
        child: Icon(
          Icons.camera_alt_outlined,
          size: 12,
          color: AppColors.hotViolet,
        ),
      ),
    );
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
