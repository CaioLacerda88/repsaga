import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/exceptions/app_exception.dart' as app;
import '../../../core/l10n/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../workouts/providers/share_controller.dart';
import '../providers/profile_providers.dart';
import 'widgets/analytics_toggle.dart';
import 'widgets/age_row.dart';
import 'widgets/avatar_crop_sheet.dart';
import 'widgets/bodyweight_consent_toggle.dart';
import 'widgets/bodyweight_row.dart';
import 'widgets/crash_reports_toggle.dart';
import 'widgets/gender_row.dart';
import 'widgets/identity_card.dart';
import 'widgets/legal_tile.dart';
import 'widgets/logout_button.dart';
import 'widgets/manage_data_tile.dart';
import 'widgets/profile_language_row.dart';
import 'widgets/stats_row.dart';
import 'widgets/weekly_goal_row.dart';
import 'widgets/weight_unit_toggle.dart';

/// Profile settings sub-screen — pushed from the character sheet's gear icon.
///
/// Carries the entire pre-Phase-18b `/profile` content (display name editor,
/// stats row, locale picker, weight unit, weekly goal, manage data, legal,
/// crash reports, sign out). The character sheet (`/profile`) replaced the
/// previous identity surface; this screen preserves all the account/account
/// preferences functionality 1:1 — no behavioural changes intended.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);
    final email = ref.watch(authRepositoryProvider).currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsLabel)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Semantics(
                container: true,
                identifier: 'profile-heading',
                child: Text(l10n.profile, style: AppTextStyles.headline),
              ),
              const SizedBox(height: 24),
              // Identity card
              profileAsync.when(
                data: (profile) {
                  final displayName = profile?.displayName ?? l10n.gymUser;
                  return IdentityCard(
                    displayName: profile?.displayName,
                    email: email,
                    avatarSemanticsLabel: l10n.avatarSemanticsLabel(
                      displayName,
                    ),
                    onEditName: () => showEditDisplayNameDialog(
                      context,
                      ref,
                      profile?.displayName,
                    ),
                    onAvatarTap: () => openAvatarUploadFlow(context, ref),
                  );
                },
                loading: () => IdentityCard(
                  displayName: null,
                  email: '',
                  avatarSemanticsLabel: l10n.avatarSemanticsLabel(l10n.gymUser),
                  loading: true,
                ),
                error: (_, _) => IdentityCard(
                  displayName: null,
                  email: '',
                  avatarSemanticsLabel: l10n.avatarSemanticsLabel(l10n.gymUser),
                ),
              ),
              const SizedBox(height: 24),
              // Stats section
              const StatsRow(),
              const SizedBox(height: 32),
              // Weight unit section
              Text(
                l10n.weightUnit,
                // [sectionHeader] — Inter 600 12dp +0.12em tracking.
                // Section labels are eyebrow register, not list-item
                // titles; prior `titleMedium` rendered at 16dp which
                // gave them the same weight as `RoutineCard` titles
                // and broke the section rhythm (Phase 27 L18.4).
                style: AppTextStyles.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) =>
                    WeightUnitToggle(weightUnit: profile?.weightUnit ?? 'kg'),
                loading: () => const WeightUnitToggle(weightUnit: 'kg'),
                error: (_, _) => const WeightUnitToggle(weightUnit: 'kg'),
              ),
              const SizedBox(height: 24),
              // Body weight section (Phase 24c — XP load multiplier for
              // bodyweight exercises like pull-ups, dips, push-ups).
              Text(
                l10n.profileBodyweightLabel,
                style: AppTextStyles.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) => BodyweightRow(profile: profile),
                loading: () => const BodyweightRow(profile: null),
                error: (_, _) => const BodyweightRow(profile: null),
              ),
              const SizedBox(height: 24),
              // Gender section (Legal PR 2 — `data-protection-compliance`).
              // Sensitive data under LGPD Art. 11 — the editor sheet
              // surfaces a one-time disclosure banner on first open.
              Text(
                l10n.genderLabel,
                style: AppTextStyles.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) => GenderRow(profile: profile),
                loading: () => const GenderRow(profile: null),
                error: (_, _) => const GenderRow(profile: null),
              ),
              const SizedBox(height: 24),
              // Age section (Phase 38d — birth-year capture). LGPD Art. 6
              // consent (like avatars), NOT Art. 11 sensitive — the editor
              // surfaces a point-of-collection disclosure, no consent toggle.
              // Drives cardio scoring against age-decade norms; NULL falls
              // back to the age-35 baseline (never gates cardio XP).
              Text(
                l10n.ageLabel,
                style: AppTextStyles.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) => AgeRow(profile: profile),
                loading: () => const AgeRow(profile: null),
                error: (_, _) => const AgeRow(profile: null),
              ),
              const SizedBox(height: 24),
              // Weekly goal section
              Semantics(
                container: true,
                identifier: 'profile-goal-label',
                child: Text(
                  l10n.weeklyGoal,
                  style: AppTextStyles.sectionHeader,
                ),
              ),
              const SizedBox(height: 12),
              profileAsync.when(
                data: (profile) => WeeklyGoalRow(
                  frequency: profile?.trainingFrequencyPerWeek ?? 3,
                ),
                loading: () => const WeeklyGoalRow(frequency: 3),
                error: (_, _) => const WeeklyGoalRow(frequency: 3),
              ),
              const SizedBox(height: 32),
              // Preferences section
              Text(
                l10n.preferences,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              ProfileLanguageRow(locale: ref.watch(localeProvider)),
              const SizedBox(height: 32),
              // Data management section
              Text(
                l10n.dataManagement,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              const ManageDataTile(),
              const SizedBox(height: 24),
              // Legal section
              Text(
                l10n.legal,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              LegalTile(
                title: l10n.privacyPolicy,
                icon: Icons.privacy_tip_outlined,
                onTap: () => context.push('/privacy-policy'),
              ),
              const SizedBox(height: 8),
              LegalTile(
                title: l10n.termsOfService,
                icon: Icons.description_outlined,
                onTap: () => context.push('/terms-of-service'),
              ),
              const SizedBox(height: 24),
              // Privacy section
              Text(
                l10n.privacySection,
                style: AppTextStyles.sectionHeader.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              const CrashReportsToggle(),
              // Legal PR 2 — analytics opt-out mounted directly below the
              // crash-reports toggle so both PRIVACY-section affordances
              // live together. Mirror of CrashReportsToggle shape.
              const SizedBox(height: 8),
              const AnalyticsToggle(),
              // Legal PR 2 — body-weight sensitive-data consent withdrawal.
              // The save-site dialog is the opt-in surface; this toggle is
              // the documented withdrawal mechanism (LGPD Art. 7(3)).
              const SizedBox(height: 8),
              const BodyweightConsentToggle(),
              const SizedBox(height: 24),
              // Logout button
              const LogoutButton(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 32 PR 32e — Avatar upload orchestration.
//
// The flow lives at the screen layer because it coordinates three
// subsystems: ShareService (picker + camera permission), AvatarCropSheet
// (in-memory image manipulation), and AvatarRepository (Supabase Storage
// upload + Hive cache). Per the architecture rule that "data-fetching
// methods have no side-effects", neither the repository nor the crop
// sheet trigger the next stage — the orchestrator here drives them in
// sequence.
//
// Public so widget tests can call it via a `tester.tap(...)` route that
// surfaces the picker; per `feedback_test_user_visible_behavior` the
// tests assert on snackbar copy + IdentityCard re-render, not on the
// helper being called.
// ---------------------------------------------------------------------------

/// Open the picker sheet → crop sheet → upload pipeline. The IdentityCard
/// `onAvatarTap` callback dispatches into here.
///
/// **Sequencing (per `cluster_async_caller_broke_snackbar`):** every
/// state read between mutations is awaited explicitly. The function
/// captures `context.mounted` at every `await` gap before reading
/// `Navigator` / `ScaffoldMessenger` / `ref`.
Future<void> openAvatarUploadFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final shareService = ref.read(shareServiceProvider);
  // Capture the StateController up-front so the `finally` reset doesn't
  // depend on `ref` still being valid if the user navigates away during
  // the upload. The provider lives at the ProviderScope, not the widget,
  // so the controller reference survives unmount.
  final uploadInProgressCtrl = ref.read(
    avatarUploadInProgressProvider.notifier,
  );

  // 1) Picker sheet (camera / gallery / cancel). Hide camera row when
  //    the OS reports `permanentlyDenied` — no recovery from inside the
  //    sheet, matches share-card behavior.
  final cameraStatus = await shareService.cameraPermissionStatus();
  if (!context.mounted) return;

  final source = await _showPickerSheet(
    context,
    l10n: l10n,
    showCamera: cameraStatus != PermissionStatus.permanentlyDenied,
  );
  if (source == null || !context.mounted) return;

  // 2) Request permission (camera path only) and pick the image.
  XFile? picked;
  if (source == _AvatarPickerSource.camera) {
    final status = await shareService.requestCameraPermission();
    if (!context.mounted) return;
    if (!status.isGranted) {
      // Camera-denied path surfaces a dedicated copy that names the
      // actual cause (instead of the generic `avatarUploadFailed` which
      // implies a network/storage failure). When the OS reports
      // `permanentlyDenied` the user can't re-prompt from inside the
      // app — pair the snackbar with an "Open settings" action so the
      // user can flip the toggle and retry. Re-uses the shareOpenSettings
      // ARB key from Phase 30b for label parity across surfaces.
      final isPermanent = status == PermissionStatus.permanentlyDenied;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cameraPermissionDeniedForAvatar),
          action: isPermanent
              ? SnackBarAction(
                  label: l10n.shareOpenSettings,
                  onPressed: () => shareService.openAppSettings(),
                )
              : null,
        ),
      );
      return;
    }
    picked = await shareService.pickFromCamera();
  } else {
    picked = await shareService.pickFromGallery();
  }
  if (picked == null || !context.mounted) return;

  // 3) Decode the picked bytes into a ui.Image for the crop sheet.
  final ui.Image decoded;
  try {
    final bytes = await picked.readAsBytes();
    decoded = await _decodeImage(bytes);
  } catch (e) {
    debugPrint('[ProfileAvatar] image decode failed: $e');
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.avatarUploadFailed)));
    return;
  }
  if (!context.mounted) return;

  // 4) Open the crop sheet — returns a [CropResult] sealed type so we
  //    distinguish "user cancelled" (no snackbar) from "rasterize
  //    failed" (avatarUploadFailed snackbar). The legacy null-return
  //    contract conflated the two — a render failure presented as a
  //    silent dismiss.
  final cropResult = await AvatarCropSheet.open(
    context,
    image: decoded,
    strings: AvatarCropSheetStrings(
      title: l10n.avatarCropSheetTitle,
      confirm: l10n.avatarCropSheetConfirm,
      cancel: l10n.avatarCropSheetCancel,
    ),
  );
  if (!context.mounted) return;
  final Uint8List croppedBytes;
  switch (cropResult) {
    case AvatarCropCancelled():
      return;
    case AvatarCropFailed():
      messenger.showSnackBar(SnackBar(content: Text(l10n.avatarUploadFailed)));
      return;
    case AvatarCropSuccess(:final bytes):
      croppedBytes = bytes;
  }

  // 5) Upload + profile-row update. Toggle the in-progress flag so the
  //    IdentityCard surfaces a loading scrim on the avatar disc; flip
  //    it back in `finally` so a thrown exception still clears the
  //    overlay.
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.avatarUploadFailed)));
    return;
  }

  uploadInProgressCtrl.state = true;
  try {
    final avatarRepo = ref.read(avatarRepositoryProvider);
    final url = await avatarRepo.uploadAvatar(
      userId: userId,
      imageBytes: croppedBytes,
    );
    await ref
        .read(profileRepositoryProvider)
        .upsertProfile(userId: userId, avatarUrl: url);
    if (!context.mounted) return;
    // Invalidate the profile provider so IdentityCard re-renders with
    // the freshly uploaded URL. The cache-bust query string on the URL
    // defeats any CDN caching, so the new image lands immediately.
    ref.invalidate(profileProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.avatarUploadSuccess)));
  } on app.AppException catch (e) {
    debugPrint('[ProfileAvatar] upload failed: ${e.message}');
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.avatarUploadFailed)));
  } catch (e) {
    debugPrint('[ProfileAvatar] upload unexpected error: $e');
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.avatarUploadFailed)));
  } finally {
    // Idempotent — clears the scrim whether the upload succeeded,
    // failed gracefully, or the widget unmounted mid-upload. The
    // captured controller survives unmount (lives at the ProviderScope).
    uploadInProgressCtrl.state = false;
  }
}

/// Source selected by the user in the picker sheet.
enum _AvatarPickerSource { camera, gallery }

/// Bottom-sheet that surfaces the camera / gallery options. Single-file
/// helper because it's only ever opened from this screen — promoting it
/// to a top-level widget would scatter the orchestration.
Future<_AvatarPickerSource?> _showPickerSheet(
  BuildContext context, {
  required AppLocalizations l10n,
  required bool showCamera,
}) {
  return showModalBottomSheet<_AvatarPickerSource>(
    context: context,
    backgroundColor: AppColors.surface,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (sheetContext) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'avatar-picker-sheet',
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.avatarPickerSheetTitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.hotViolet,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                if (showCamera) ...[
                  _PickerRow(
                    identifier: 'avatar-picker-camera',
                    icon: Icons.camera_alt_outlined,
                    label: l10n.avatarPickerCamera,
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_AvatarPickerSource.camera),
                  ),
                  const SizedBox(height: 8),
                ],
                _PickerRow(
                  identifier: 'avatar-picker-gallery',
                  icon: Icons.photo_library_outlined,
                  label: l10n.avatarPickerGallery,
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_AvatarPickerSource.gallery),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.avatarPickerCancel),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
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

/// Decode [bytes] into a `dart:ui` image via the platform codec.
/// Centralized so the orchestrator and any future caller share the same
/// "raw bytes → ui.Image" path.
Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
