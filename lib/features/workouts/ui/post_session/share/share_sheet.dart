import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/share_payload.dart';
import '../../../providers/share_controller.dart';
import 'share_localizations.dart';

/// Bottom-sheet picker for the share-card flow (mockup §7 sheet step).
///
/// Three rows: camera, gallery, discreet ("Sem foto · só a saga"). Tapping
/// a row dismisses the sheet and dispatches the matching [ShareController]
/// method. The preview screen (Group D) reacts to the controller's
/// resulting [ShareStatePreview] / [ShareStateError] / [ShareStateCancelled]
/// transition.
///
/// **Camera visibility rule.** The camera row is hidden when the OS reports
/// `PermissionStatus.permanentlyDenied` — there's no way to recover from
/// the sheet (Android requires opening Settings). Mockup §7 spec: camera
/// row shows on `granted` AND `denied` so the user can re-prompt; hidden
/// on `permanentlyDenied` to avoid a dead-end tap.
///
/// **Permission status is read at sheet-mount time.** If the user grants
/// permission while the sheet is open (e.g. via another path), this widget
/// will not react until next open. Acceptable per mockup §7 (the sheet is
/// a single moment of choice; long-lived state is the preview screen's
/// concern).
///
/// **Decoupling Rule 2.** Strings arrive via the [ShareLocalizations]
/// constructor param. The widget never reads `AppLocalizations.of(context)`.
class ShareSheet extends ConsumerWidget {
  const ShareSheet({
    super.key,
    required this.payload,
    required this.l10n,
    required this.cameraStatus,
  });

  /// Pre-composed payload for the share controller's pick-methods.
  /// Forwarded directly into [ShareController.pickFromCamera] etc.
  final SharePayload payload;

  /// Pre-localized strings (Decoupling Rule 2).
  final ShareLocalizations l10n;

  /// Camera permission status snapshot — read by the screen-layer caller
  /// via [ShareController.refreshCameraPermission] BEFORE opening the
  /// sheet, then passed in here so the row visibility computation runs
  /// pure (the sheet itself is sync-build-friendly + unit-testable).
  final PermissionStatus cameraStatus;

  /// Open the sheet against [context]. The screen-layer caller is the
  /// `ShareCtaButton`'s `onPressed`. The sheet's row taps dispatch into
  /// the controller via `ref.read(shareControllerProvider.notifier)`;
  /// this static helper just opens the modal — it does not await any
  /// state transition. The preview screen is the next destination.
  static Future<void> open(
    BuildContext context, {
    required SharePayload payload,
    required ShareLocalizations l10n,
    required PermissionStatus cameraStatus,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        return ShareSheet(
          payload: payload,
          l10n: l10n,
          cameraStatus: cameraStatus,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Camera row is hidden when permanently denied — no recovery path
    // from inside the sheet (would dead-end on tap).
    final showCamera = cameraStatus != PermissionStatus.permanentlyDenied;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'share-sheet',
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                l10n.sheetTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.hotViolet,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              if (showCamera) ...[
                _ShareSheetRow(
                  identifier: 'share-sheet-camera',
                  icon: Icons.camera_alt_outlined,
                  label: l10n.takePhoto,
                  onTap: () {
                    Navigator.of(context).pop();
                    ref
                        .read(shareControllerProvider.notifier)
                        .pickFromCamera(payload: payload);
                  },
                ),
                const SizedBox(height: 8),
              ],
              _ShareSheetRow(
                identifier: 'share-sheet-gallery',
                icon: Icons.photo_library_outlined,
                label: l10n.fromGallery,
                onTap: () {
                  Navigator.of(context).pop();
                  ref
                      .read(shareControllerProvider.notifier)
                      .pickFromGallery(payload: payload);
                },
              ),
              const SizedBox(height: 8),
              _ShareSheetRow(
                identifier: 'share-sheet-discreet',
                icon: Icons.brightness_3_outlined,
                label: l10n.noPhoto,
                onTap: () {
                  Navigator.of(context).pop();
                  ref
                      .read(shareControllerProvider.notifier)
                      .useDiscreet(payload: payload);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single tappable row inside the [ShareSheet]. Material `InkWell` for
/// the splash, leading Material icon (never an emoji glyph per the
/// 2026-05-23 cinematic gate fix), Rajdhani-display label.
class _ShareSheetRow extends StatelessWidget {
  const _ShareSheetRow({
    required this.identifier,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String identifier;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: identifier,
      button: true,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textCream, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textCream,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
