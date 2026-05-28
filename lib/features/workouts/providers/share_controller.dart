// ignore_for_file: invalid_annotation_target

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/device/platform_info.dart';
import '../../analytics/data/models/analytics_event.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/share_image_renderer.dart';
import '../data/share_service.dart';

part 'share_controller.freezed.dart';

/// Share-card pipeline state machine.
///
/// **Linear flow:** idle → (pickingPhoto | preview) → rendering → sharing →
/// idle. Errors land in [ShareState.error]. The user can retake from
/// preview, which returns to idle and re-opens the [ShareSheet] at the
/// screen layer.
///
/// **Why a sealed union and not a plain `int` / enum?** Each state may
/// carry payload (preview holds the chosen `XFile?`; error holds a
/// stable code). A union forces consumers to handle every transition
/// explicitly and prevents the "what does `state == 2` mean" decay.
@freezed
sealed class ShareState with _$ShareState {
  /// Initial state — sheet not yet opened, no photo chosen.
  const factory ShareState.idle() = ShareStateIdle;

  /// Camera or gallery picker is being awaited. The bottom sheet has
  /// dismissed; the platform picker is on screen.
  const factory ShareState.pickingPhoto() = ShareStatePickingPhoto;

  /// Photo chosen (or skipped for discreet path) — preview screen is
  /// the source of truth for variant + framing. [photo] is `null` for
  /// the Discreet path; non-null for Variant A + B.
  const factory ShareState.preview({required XFile? photo}) = ShareStatePreview;

  /// Render is in flight — `ShareImageRenderer.render` has been called
  /// but hasn't returned yet. Transitions to [sharing] on success or
  /// [error] on failure.
  const factory ShareState.rendering() = ShareStateRendering;

  /// Native share sheet is open — `ShareService.share` has been called.
  /// Transitions back to [idle] regardless of whether the user shared
  /// or dismissed (per `share_plus` ShareResult semantics).
  const factory ShareState.sharing() = ShareStateSharing;

  /// User cancelled at the picker step (camera dismissed, gallery
  /// dismissed without selecting). Distinct from [error] because no
  /// recovery copy is shown — the user just falls back to the share
  /// sheet at the screen layer.
  const factory ShareState.cancelled() = ShareStateCancelled;

  /// Terminal-but-recoverable error. [code] is a stable identifier
  /// (e.g. `'camera_permission_denied'`, `'camera_permission_permanently_denied'`,
  /// `'render_failed'`, `'share_failed'`) the screen layer maps to
  /// localized copy. We do not put the raw exception message on the
  /// payload — it leaks platform-channel detail to the UI.
  const factory ShareState.error({required String code}) = ShareStateError;
}

/// Stable error codes — string constants kept in one place so the
/// screen layer's switch doesn't drift from the controller's emissions.
class ShareErrorCodes {
  ShareErrorCodes._();

  /// User denied the camera permission at the OS prompt this session.
  /// The prompt may be re-shown next time (mockup §7 first-denial copy).
  static const String cameraPermissionDenied = 'camera_permission_denied';

  /// User has permanently denied the camera permission (Android: "Don't
  /// ask again" toggled; iOS: status == permanentlyDenied). The screen
  /// routes to `openAppSettings()`.
  static const String cameraPermissionPermanentlyDenied =
      'camera_permission_permanently_denied';

  /// Render captured no bytes, or the temp-file write failed.
  static const String renderFailed = 'render_failed';

  /// Native share sheet returned a non-success / non-dismissed status.
  static const String shareFailed = 'share_failed';
}

/// DI seam for [ShareService]. Overridden in tests via [ProviderContainer]
/// to inject a fake without touching the platform plugin channels.
final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

/// DI seam for [ShareImageRenderer]. Same rationale as
/// [shareServiceProvider] — overridden in tests with a fake renderer.
final shareImageRendererProvider = Provider<ShareImageRenderer>(
  (ref) => ShareImageRenderer(),
);

/// Coordinator for the share-card flow.
///
/// **Layering.** Owns the state machine. Delegates IO to [ShareService]
/// + [ShareImageRenderer]. Knows nothing about widgets / context /
/// localization — those are screen-layer concerns. The screen reads
/// [state], reacts to transitions, and dispatches user intents into
/// the controller's methods.
///
/// **Why a plain [Notifier] and not [AsyncNotifier]?** The state itself
/// is a sealed union with discriminated transitions, not a `Future<T>`.
/// Wrapping it in [AsyncValue] would double-encode the rendering /
/// sharing "in-flight" beats already modelled by [ShareStateRendering]
/// + [ShareStateSharing].
class ShareController extends Notifier<ShareState> {
  @override
  ShareState build() => const ShareState.idle();

  ShareService get _service => ref.read(shareServiceProvider);
  ShareImageRenderer get _renderer => ref.read(shareImageRendererProvider);

  /// User tapped "Tirar foto" on the share sheet.
  ///
  /// Requests camera permission. On denial → emits the matching error
  /// code (the screen surfaces the localized copy + an "abrir
  /// configurações" affordance for the permanently-denied path). On
  /// grant → opens the camera; cancel = [ShareState.cancelled], chosen
  /// photo = [ShareState.preview].
  Future<void> pickFromCamera() async {
    state = const ShareState.pickingPhoto();
    final status = await _service.requestCameraPermission();
    if (status == PermissionStatus.permanentlyDenied) {
      state = const ShareState.error(
        code: ShareErrorCodes.cameraPermissionPermanentlyDenied,
      );
      return;
    }
    if (!status.isGranted) {
      state = const ShareState.error(
        code: ShareErrorCodes.cameraPermissionDenied,
      );
      return;
    }

    final photo = await _service.pickFromCamera();
    if (photo == null) {
      state = const ShareState.cancelled();
      return;
    }
    state = ShareState.preview(photo: photo);
  }

  /// User tapped "Escolher da galeria" on the share sheet. Android 13+
  /// photo picker doesn't need a runtime permission (system-level
  /// chooser); we skip the permission flow on purpose.
  Future<void> pickFromGallery() async {
    state = const ShareState.pickingPhoto();
    final photo = await _service.pickFromGallery();
    if (photo == null) {
      state = const ShareState.cancelled();
      return;
    }
    state = ShareState.preview(photo: photo);
  }

  /// User tapped "Sem foto · só a saga" — discreet path. Skips the
  /// picker entirely and jumps to preview with a null photo. The
  /// preview screen locks the variant to discreet on this path.
  void useDiscreet() {
    state = const ShareState.preview(photo: null);
  }

  /// User tapped "Compartilhar" on the preview screen.
  ///
  /// Renders the share card under [repaintKey] (via [ShareImageRenderer])
  /// then hands the resulting PNG to the native share sheet (via
  /// [ShareService]). Returns to [ShareState.idle] on success or
  /// dismiss; emits [ShareState.error] on any render/share failure.
  ///
  /// The caller must ensure [repaintKey] is currently attached to a
  /// [RenderRepaintBoundary] (post-first-frame) — the renderer's
  /// `StateError` for an unmounted key surfaces as `render_failed`.
  Future<void> sharePreview({
    required GlobalKey repaintKey,
    String? shareText,
  }) async {
    // Guard: only valid from preview. Defensive — the UI gates the
    // button visibility, but a stale tap could fire after a navigator
    // pop. Silently no-op rather than crashing.
    final previewState = state;
    if (previewState is! ShareStatePreview) return;

    // Phase 32 PR 32d — capture the photo state BEFORE the rendering /
    // sharing transitions so analytics can read it on the success branch
    // below. After `state = ShareState.rendering()` the union variant
    // changes and the photo isn't accessible from `state` anymore.
    final hadCustomPhoto = previewState.photo != null;

    state = const ShareState.rendering();
    final XFile file;
    try {
      file = await _renderer.render(repaintKey: repaintKey);
    } catch (_) {
      state = const ShareState.error(code: ShareErrorCodes.renderFailed);
      return;
    }

    state = const ShareState.sharing();
    try {
      final result = await _service.share(file, text: shareText);
      // `ShareResult.success` and `ShareResult.dismissed` both return
      // to idle — the sheet is gone either way and we don't surface a
      // confirmation toast (mockup §7: success is silent).
      if (result.status == ShareResultStatus.unavailable) {
        state = const ShareState.error(code: ShareErrorCodes.shareFailed);
        return;
      }
      // Phase 32 PR 32d — `share_card_exported` fires only on the
      // confirmed-success branch. `dismissed` (user backed out of the
      // sheet without picking a target) and `unavailable` (above) /
      // exception (below) all skip the emit. v1 emits `discreet` vs
      // `with_photo` only; A vs B granularity is deferred to Launch
      // Phase if the signal proves load-bearing.
      if (result.status == ShareResultStatus.success) {
        _recordShareExported(hadCustomPhoto: hadCustomPhoto);
      }
      state = const ShareState.idle();
    } catch (_) {
      state = const ShareState.error(code: ShareErrorCodes.shareFailed);
    }
  }

  /// Phase 32 PR 32d — record the `share_card_exported` analytics event.
  ///
  /// Fire-and-forget. The "analytics must never break the user's flow"
  /// contract is enforced at [analyticsRepositoryProvider]: when Supabase
  /// is uninitialised the provider hands back a no-op repository, so this
  /// call site is free of defensive wrapping. The missing-user-id edge
  /// no-ops silently (no logged-out user should ever reach this code
  /// path, but the gate is cheap defense-in-depth).
  void _recordShareExported({required bool hadCustomPhoto}) {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final analyticsRepo = ref.read(analyticsRepositoryProvider);
    unawaited(
      analyticsRepo.insertEvent(
        userId: userId,
        event: AnalyticsEvent.shareCardExported(
          variant: hadCustomPhoto ? 'with_photo' : 'discreet',
          hadCustomPhoto: hadCustomPhoto,
        ),
        platform: currentPlatform(),
        appVersion: currentAppVersion(),
      ),
    );
  }

  /// Read the current camera-permission status without prompting. Used
  /// by [ShareSheet] to decide whether to render the camera row at
  /// all (hidden on permanentlyDenied per mockup §7).
  Future<PermissionStatus> refreshCameraPermission() {
    return _service.cameraPermissionStatus();
  }

  /// Open the platform app-settings screen. The preview-screen error
  /// snackbar surfaces this affordance on the `cameraPermissionPermanentlyDenied`
  /// path so the user can flip the toggle and retry.
  Future<bool> openAppSettings() => _service.openAppSettings();

  /// Reset to idle. Called by [SharePreviewScreen]'s retake button so
  /// the screen layer can dismiss the preview and re-open the sheet.
  void reset() {
    state = const ShareState.idle();
  }

  /// Reset back to the preview state with the previously-chosen photo.
  /// The preview-screen error handler calls this after surfacing the
  /// snackbar so the user can retry the share without losing the photo
  /// they framed.
  ///
  /// **Idempotent.** Safe to call multiple times — a no-op when state is
  /// already a `preview` with the same photo. The state machine only emits
  /// when the value actually changes, so the UI's `ref.listen` callbacks
  /// fire exactly once.
  void resetToPreview({required XFile? photo}) {
    final next = ShareState.preview(photo: photo);
    if (state == next) return;
    state = next;
  }
}

/// Top-level provider — [Notifier]-based per riverpod 3 conventions.
final shareControllerProvider = NotifierProvider<ShareController, ShareState>(
  ShareController.new,
);
