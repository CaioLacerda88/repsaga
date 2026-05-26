import 'dart:io';

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/share_payload.dart';
import '../../../providers/share_controller.dart';
import 'share_card_renderer.dart';
import 'share_localizations.dart';

/// Full-screen preview of the share card before the native share-sheet
/// handoff (mockup §7 preview step).
///
/// **Responsibilities:**
///   1. Render the active [ShareCardRenderer] inside a [RepaintBoundary]
///      so [ShareImageRenderer] can capture the rendered tree off-screen
///      at the correct 1080×1920 size.
///   2. Single-variant rendering. D3 Achievement Frame is the photo path;
///      Discreet renders on the no-photo path. Phase 31 retired the
///      Variant A ↔ Variant B segmented toggle — one overlay treatment.
///   3. Wire share + retake CTAs to [ShareController] transitions.
///   4. Tap-to-hide XP / tap-to-hide PR (mockup §7) — local toggles that
///      hide the overlay sections.
///   5. Drag-to-reframe photo — shifts the photo's `Alignment` along the
///      Y axis based on drag delta.
///
/// **Why a separate offscreen 1080×1920 boundary instead of capturing the
/// visible preview tree?** The visible tree is scaled (FittedBox) to fit
/// the device screen. Capturing it at the visible pixelRatio + scale
/// produces a sub-1080-px image with mid-resolution text. The Pass 2
/// dartdoc on [ShareImageRenderer] is load-bearing here: tight 1080×1920
/// constraints on the boundary's child are required for the export to
/// match the design.
///
/// **Decoupling Rule 2.** All visible strings via [ShareLocalizations];
/// the screen never calls `AppLocalizations.of(context)`.
class SharePreviewScreen extends ConsumerStatefulWidget {
  const SharePreviewScreen({
    super.key,
    required this.payload,
    required this.strings,
    required this.l10n,
    required this.onClose,
  });

  /// The pre-composed payload from the post-session state.
  final SharePayload payload;

  /// Pre-localized text bundle for the share card overlay grammar.
  final ShareCardStrings strings;

  /// Pre-localized labels for the preview-screen affordances.
  final ShareLocalizations l10n;

  /// Called when the user taps retake OR after a successful share. The
  /// route container pops the preview off the navigation stack. Kept as
  /// a callback (not a direct `Navigator.pop`) per Decoupling Rule 8 —
  /// the screen is route-agnostic.
  final VoidCallback onClose;

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  /// GlobalKey on the **offscreen** 1080×1920 export tree's
  /// [RepaintBoundary]. This is the boundary that
  /// [ShareImageRenderer.render] captures via `toImage(pixelRatio: 3.0)`.
  ///
  /// **Why a separate offscreen tree?** PR 30c device bug 3 root cause:
  /// pre-fix the visible preview tree (`FittedBox`-scaled) WAS the
  /// boundary. When the user tapped SHARE:
  ///   1. The controller flipped state to [ShareStateRendering] so the
  ///      previous `build()` returned a [CircularProgressIndicator]
  ///      instead of the preview body.
  ///   2. The next frame unmounted the visible preview tree — the
  ///      [RepaintBoundary]'s layer was disposed.
  ///   3. The `await boundary.toImage(...)` in flight finished on a
  ///      disposed layer and threw, surfacing as the "Couldn't render
  ///      the saga card" snackbar on real devices.
  ///
  /// **Post-fix:** the screen mounts BOTH a visible preview tree (with
  /// `renderTarget: preview`) AND an offscreen export tree (with
  /// `renderTarget: export`, positioned at `left: -10000`). The export
  /// tree is the one captured by `toImage` and stays laid out + painted
  /// across the state transition to [ShareStateRendering] because the
  /// screen no longer swaps out its body — it overlays a spinner barrier
  /// on top instead.
  final GlobalKey _exportRepaintKey = GlobalKey(
    debugLabel: 'share-preview-export-repaint',
  );

  /// Active variant. Discreet is locked when the chosen photo is null (the
  /// user picked "Sem foto · só a saga" on the bottom sheet). Otherwise
  /// renders the D3 Achievement Frame (the single overlay treatment —
  /// Phase 31 retired the Variant A ↔ Variant B toggle).
  ShareCardVariant _variant = ShareCardVariant.achievementFrame;

  /// Tap-to-hide state for the XP overlay (mockup §7 affordance). When
  /// `true`, the Achievement Frame XP hero line (or Discreet hero stack)
  /// is hidden.
  bool _xpHidden = false;

  /// Tap-to-hide state for the PR line.
  bool _prHidden = false;

  /// Vertical drag offset for the photo zone (Alignment.y). Clamped to
  /// `[-1.0, 1.0]` to keep the photo edges in frame.
  double _photoAlignmentY = 0.0;

  @override
  void initState() {
    super.initState();
    // Read the controller's current state once at mount to choose the
    // initial variant. Discreet path (photo == null) locks the toggle.
    final state = ref.read(shareControllerProvider);
    if (state is ShareStatePreview && state.photo == null) {
      _variant = ShareCardVariant.discreet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shareControllerProvider);

    // Defensive — when the screen is mounted with no preview state at
    // all (unexpected; the screen-layer caller should open it after a
    // preview transition) render an empty scaffold.
    //
    // PR 30b Suggestion 7: silent SizedBox.shrink was invisible in dev
    // diagnostics. Use debugPrint (cluster: developer-log-invisible-logcat
    // — developer.log doesn't reach adb logcat on Android) so a stray
    // state landing here surfaces in `flutter run` output.
    //
    // ShareStatePreview / ShareStateRendering / ShareStateSharing ALL
    // render the same body tree — the body holds the offscreen export
    // RepaintBoundary that ShareImageRenderer needs. Unmounting it
    // during the rendering transition (the pre-PR-30c shape) disposed
    // the boundary's layer while toImage was mid-flight and threw the
    // "Couldn't render the saga card" snackbar (device bug 3 root
    // cause).
    final ShareStatePreview? preview;
    if (state is ShareStatePreview) {
      preview = state;
    } else if (state is ShareStateRendering || state is ShareStateSharing) {
      // Both states retain the previously-chosen photo on the controller
      // — the controller's last `preview` payload is what we need to
      // keep rendering so the offscreen export tree stays mounted. We
      // can't read that from the sealed union directly, so we use the
      // photo captured on the state machine at the moment SHARE was
      // tapped. The screen's tap handler passes the photo into
      // [_onSharePressed]; we cache the last preview photo across
      // rebuilds via [_lastPreviewPhoto].
      preview = _lastPreviewPhoto == null
          ? null
          : ShareState.preview(photo: _lastPreviewPhoto) as ShareStatePreview;
    } else {
      preview = null;
    }
    if (preview == null) {
      debugPrint(
        '[share_preview] unexpected state: ${state.runtimeType} -- '
        'rendering empty scaffold',
      );
      return _scaffold(child: const SizedBox.shrink());
    }

    // Cache the active preview photo so the rendering / sharing states
    // can keep rendering the same body tree (the offscreen export tree
    // must stay mounted across the toImage async gap — device bug 3).
    _lastPreviewPhoto = preview.photo;

    final photo = preview.photo;
    final isDiscreet = photo == null;
    final isBusy = state is ShareStateRendering || state is ShareStateSharing;

    return _scaffold(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'share-preview-screen',
        child: Stack(
          children: [
            // OFFSCREEN export tree. Mounted at `left: -10000` so it's
            // laid out + painted (required for `RenderRepaintBoundary
            // .toImage` to read the boundary's layer) but invisible to
            // the user. Uses `renderTarget: export` so the typography
            // matches mockup §6 (the locked visual contract for the
            // shipped PNG).
            //
            // `Offstage(offstage: true)` would skip layout + paint and
            // break toImage; `Visibility(visible: false, maintainState:
            // true, maintainSize: true)` does the same. The off-screen
            // Positioned with a tight SizedBox is the canonical pattern.
            Positioned(
              left: -10000,
              top: 0,
              child: SizedBox(
                width: 1080,
                height: 1920,
                child: RepaintBoundary(
                  key: _exportRepaintKey,
                  child: ShareCardRenderer(
                    payload: widget.payload,
                    variant: _variant,
                    strings: _stringsWithHidesApplied(),
                    photo: photo == null ? null : FileImage(File(photo.path)),
                    photoOffset: Offset(0, _photoAlignmentY * 80),
                    renderTarget: ShareCardRenderTarget.export,
                  ),
                ),
              ),
            ),
            // Visible preview tree. Uses `renderTarget: preview` so the
            // typography is scaled up enough to read on a FittedBox-
            // shrunk visible card (device bug 1). The user only ever
            // sees this; the bytes shared are sourced from the offscreen
            // export tree above.
            SafeArea(
              child: Column(
                children: [
                  // Phase 31 retired the Variant A ↔ Variant B toggle.
                  // The Achievement Frame is the single photo overlay;
                  // Discreet still renders on the no-photo path
                  // (auto-selected via [_variant] in `initState` when
                  // `photo == null`).
                  const SizedBox(height: 12),

                  // PR 30c device bug 2: the AspectRatio is wrapped in a
                  // ClipRect so the photoOffset Transform inside the
                  // renderer cannot paint outside the card's 9:16 frame.
                  Expanded(
                    child: GestureDetector(
                      onVerticalDragUpdate: isDiscreet
                          ? null
                          : (details) {
                              setState(() {
                                _photoAlignmentY =
                                    (_photoAlignmentY +
                                            details.primaryDelta! / 200)
                                        .clamp(-1.0, 1.0);
                              });
                            },
                      child: Center(
                        child: ClipRect(
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: 1080,
                                height: 1920,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Photo offset forwarded into the
                                    // renderer so ONLY the photo
                                    // subtree translates -- overlay
                                    // strips / collars stay anchored.
                                    ShareCardRenderer(
                                      payload: widget.payload,
                                      variant: _variant,
                                      strings: _stringsWithHidesApplied(),
                                      photo: photo == null
                                          ? null
                                          : FileImage(File(photo.path)),
                                      photoOffset: Offset(
                                        0,
                                        _photoAlignmentY * 80,
                                      ),
                                      renderTarget:
                                          ShareCardRenderTarget.preview,
                                    ),
                                    // Tap-to-hide affordances — Mockup §7.
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      height: 280,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTap: () => setState(
                                          () => _xpHidden = !_xpHidden,
                                        ),
                                      ),
                                    ),
                                    if (_hasPrSection())
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 320,
                                        height: 120,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTap: () => setState(
                                            () => _prHidden = !_prHidden,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom action row — Retake + Share. Disabled while
                  // busy (rendering / sharing) so taps don't pile up.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PreviewActionButton(
                            identifier: 'share-preview-retake',
                            label: widget.l10n.previewRetake,
                            backgroundColor: AppColors.surface2,
                            foregroundColor: AppColors.textCream,
                            onPressed: isBusy
                                ? null
                                : () {
                                    ref
                                        .read(shareControllerProvider.notifier)
                                        .reset();
                                    widget.onClose();
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _PreviewActionButton(
                            identifier: 'share-preview-share-button',
                            label: widget.l10n.previewShare,
                            backgroundColor: AppColors.primaryViolet,
                            foregroundColor: AppColors.textCream,
                            onPressed: isBusy
                                ? null
                                : () => _onSharePressed(photo),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Busy barrier — covers the visible tree (NOT the offscreen
            // export tree, which sits BELOW this overlay in stack order
            // but is offscreen via Positioned(left: -10000)). Renders a
            // spinner on a translucent scrim while the controller is
            // rendering or sharing. Without IgnorePointer the user
            // could double-tap action buttons under the barrier.
            if (isBusy)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: ColoredBox(
                    color: AppColors.abyss.withValues(alpha: 0.6),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Cached photo from the last `ShareStatePreview` snapshot. Lets the
  /// `rendering` + `sharing` states keep rendering the same body tree —
  /// the offscreen export tree must stay mounted across the toImage
  /// async gap (PR 30c device bug 3). Reset to null when the controller
  /// transitions out of the preview/rendering/sharing lifecycle.
  XFile? _lastPreviewPhoto;

  /// Apply the tap-to-hide toggles to the strings bundle by blanking the
  /// relevant slots. Cheaper than introducing per-variant visibility
  /// params on every variant widget — the renderer already treats `null`
  /// slot strings as "render nothing" on the optional slots.
  ///
  // TODO(perf): allocates a fresh ShareCardStrings on every build. Cheap
  // (11 string copies, no GC pressure measurable in profiling), but
  // could be memoized in a final cached field keyed on (_xpHidden,
  // _prHidden). Skipped until ShareCardStrings grows a copyWith — adding
  // one ad-hoc would inflate this widget by ~20 lines. The allocation
  // isn't a 60fps risk — see PR 30b Nit 8 deferral note.
  ShareCardStrings _stringsWithHidesApplied() {
    final s = widget.strings;
    return ShareCardStrings(
      wordmark: s.wordmark,
      achievementFrameClassName: s.achievementFrameClassName,
      achievementFrameSagaEyebrow: s.achievementFrameSagaEyebrow,
      achievementFrameXpHero: _xpHidden ? '' : s.achievementFrameXpHero,
      achievementFrameLiftDetail: _prHidden
          ? null
          : s.achievementFrameLiftDetail,
      achievementFrameHasPr: _prHidden ? false : s.achievementFrameHasPr,
      achievementFrameBpRank: s.achievementFrameBpRank,
      discreetEyebrow: s.discreetEyebrow,
      discreetHero: _xpHidden ? '' : s.discreetHero,
      discreetHeroSubLabel: _xpHidden ? '' : s.discreetHeroSubLabel,
      discreetPrLine: _prHidden ? null : s.discreetPrLine,
      discreetPrDetail: _prHidden ? null : s.discreetPrDetail,
    );
  }

  bool _hasPrSection() {
    return widget.strings.achievementFrameLiftDetail != null ||
        widget.strings.discreetPrLine != null;
  }

  Widget _scaffold({required Widget child}) {
    return Scaffold(backgroundColor: AppColors.abyss, body: child);
  }

  /// Tap handler for the preview-screen share button.
  ///
  /// Dispatches into the controller. On success the controller lands in
  /// `idle` and we close the preview screen. On error we surface the
  /// matching localized copy via a snackbar AND keep the preview screen
  /// mounted (the `photo` is still cached locally, the user can retry by
  /// tapping share again).
  ///
  /// Pre-fix the screen called `widget.onClose()` unconditionally on
  /// every controller resolution, including [ShareStateError]. The
  /// build()'s `state is! ShareStatePreview` fallback would render an
  /// empty SizedBox.shrink for one frame and then the close fired, so
  /// the user just saw the preview vanish on render/share failure with
  /// no recovery path. `ShareLocalizations.renderError` /
  /// `permissionDenied` / `permissionPermanentlyDenied` were dead code.
  Future<void> _onSharePressed(XFile? photo) async {
    final controller = ref.read(shareControllerProvider.notifier);
    await controller.sharePreview(repaintKey: _exportRepaintKey);
    if (!mounted) return;

    final post = ref.read(shareControllerProvider);
    if (post is ShareStateError) {
      _surfaceError(post, controller, photo);
      return;
    }

    // Success / dismissed / unavailable handled inside the controller
    // landing on idle — close the preview.
    widget.onClose();
  }

  /// Render the failure snackbar + return the controller to preview so
  /// the user can retry. Pure presentation — no IO. Idempotent.
  void _surfaceError(
    ShareStateError post,
    ShareController controller,
    XFile? photo,
  ) {
    final l10n = widget.l10n;
    final String message;
    String? actionLabel;
    VoidCallback? actionCallback;
    switch (post.code) {
      case ShareErrorCodes.cameraPermissionPermanentlyDenied:
        message = l10n.permissionPermanentlyDenied;
        actionLabel = l10n.openSettings;
        actionCallback = () => controller.openAppSettings();
      case ShareErrorCodes.cameraPermissionDenied:
        message = l10n.permissionDenied;
      case ShareErrorCodes.renderFailed:
      case ShareErrorCodes.shareFailed:
      default:
        // Render + share failures share the renderError copy until a
        // dedicated shareError key lands in the ARB (TODO follow-up if
        // the failure modes diverge in user-facing copy).
        message = l10n.renderError;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: actionCallback ?? () {},
              ),
      ),
    );

    // Reset back to preview with the cached photo so the user can
    // retry. resetToPreview is idempotent — safe if called repeatedly.
    controller.resetToPreview(photo: photo);
  }
}

class _PreviewActionButton extends StatelessWidget {
  const _PreviewActionButton({
    required this.identifier,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String identifier;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  /// Tap handler. `null` disables the button (taps no-op, ripple
  /// suppressed). The busy-barrier in the parent still covers the
  /// button, so this is belt-and-braces against missed events.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: identifier,
      button: true,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTextStyles.titleDisplay.copyWith(
                fontSize: 13,
                letterSpacing: 0.04 * 13,
                height: 1.2,
                color: foregroundColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
