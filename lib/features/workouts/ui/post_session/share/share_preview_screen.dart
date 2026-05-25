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
///   2. Provide a variant toggle (Minimal ↔ Bold). Discreet path locks
///      to the Discreet variant — no photo, no toggle.
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
  /// GlobalKey on the offscreen [RepaintBoundary] for the 1080×1920
  /// render. The visible preview gets a separate scaled-down view; the
  /// captured image is always the offscreen one.
  final GlobalKey _repaintKey = GlobalKey(debugLabel: 'share-preview-repaint');

  /// Active variant. Discreet is locked when [_photo] is null (the user
  /// chose "Sem foto · só a saga" on the bottom sheet). Otherwise toggles
  /// between minimalStrip ↔ fullBleed.
  ShareCardVariant _variant = ShareCardVariant.minimalStrip;

  /// Tap-to-hide state for the XP overlay (mockup §7 affordance). When
  /// `true`, the Variant A/B XP line / Discreet hero stack is hidden.
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

    // While the controller is doing work (render or native sheet), show
    // a progress indicator. Once it lands back in idle / error / cancelled
    // we DO NOT auto-pop — the action handlers (retake + share) are the
    // only callers of [widget.onClose]. Auto-popping from build double-
    // fires when the action handler itself calls onClose AND the state
    // transition triggers the post-frame callback.
    if (state is ShareStateRendering || state is ShareStateSharing) {
      return _scaffold(child: const Center(child: CircularProgressIndicator()));
    }
    if (state is! ShareStatePreview) {
      // Defensive — covers the case where the screen is mounted with no
      // preview state at all (unexpected; the screen-layer caller should
      // open it after a preview transition). Render an empty scaffold.
      //
      // PR 30b Suggestion 7: silent SizedBox.shrink was invisible in dev
      // diagnostics. Use debugPrint (cluster: developer-log-invisible-logcat
      // — developer.log doesn't reach adb logcat on Android) so a stray
      // state landing here surfaces in `flutter run` output.
      debugPrint(
        '[share_preview] unexpected state: ${state.runtimeType} -- '
        'rendering empty scaffold',
      );
      return _scaffold(child: const SizedBox.shrink());
    }

    final photo = state.photo;
    final isDiscreet = photo == null;

    return _scaffold(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'share-preview-screen',
        child: SafeArea(
          child: Column(
            children: [
              // Variant toggle — hidden on the Discreet path (mockup §7:
              // "Sem foto · só a saga" locks the Discreet variant).
              if (!isDiscreet)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _VariantToggle(
                    value: _variant,
                    minimalLabel: widget.l10n.previewMinimal,
                    boldLabel: widget.l10n.previewBold,
                    onChanged: (v) => setState(() => _variant = v),
                  ),
                ),
              const SizedBox(height: 4),

              // Preview body — FittedBox-scaled view of the 1080×1920
              // offscreen render. The captured image is always at the
              // native target size; the visible preview is just a scaled
              // mirror so the user can frame + toggle interactively.
              Expanded(
                child: GestureDetector(
                  onVerticalDragUpdate: isDiscreet
                      ? null
                      : (details) {
                          setState(() {
                            _photoAlignmentY =
                                (_photoAlignmentY + details.primaryDelta! / 200)
                                    .clamp(-1.0, 1.0);
                          });
                        },
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: RepaintBoundary(
                          key: _repaintKey,
                          child: SizedBox(
                            width: 1080,
                            height: 1920,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Photo offset is forwarded into the
                                // renderer so ONLY the photo subtree
                                // translates -- the bottom strip /
                                // collars stay anchored to the 1080x1920
                                // frame. Wrapping the renderer itself in
                                // Transform.translate (the pre-PR-30b-fix
                                // shape) shifted overlay AND photo
                                // together and produced clipping
                                // artifacts at the frame edges on max
                                // drag.
                                ShareCardRenderer(
                                  payload: widget.payload,
                                  variant: _variant,
                                  strings: _stringsWithHidesApplied(),
                                  photo: photo == null
                                      ? null
                                      : FileImage(File(photo.path)),
                                  photoOffset: Offset(0, _photoAlignmentY * 80),
                                ),
                                // Tap-to-hide affordances — invisible tap
                                // surfaces over the XP zone (bottom strip
                                // on A/B, hero on Discreet) and the PR
                                // zone (bottom-strip right slot on A, PR
                                // tag area on B, !! line on Discreet).
                                // Mockup §7: "tap to hide XP / tap to
                                // hide PR" — toggle affordances surfaced
                                // as transparent rectangles.
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 280,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: () =>
                                        setState(() => _xpHidden = !_xpHidden),
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

              // Bottom action row — Retake + Share.
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
                        onPressed: () {
                          ref.read(shareControllerProvider.notifier).reset();
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
                        onPressed: () => _onSharePressed(photo),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Apply the tap-to-hide toggles to the strings bundle by blanking the
  /// relevant slots. Cheaper than introducing per-variant visibility
  /// params on every variant widget — the renderer already treats `null`
  /// slot strings as "render nothing" on the optional slots.
  ShareCardStrings _stringsWithHidesApplied() {
    final s = widget.strings;
    return ShareCardStrings(
      wordmark: s.wordmark,
      variantAXpText: _xpHidden ? '' : s.variantAXpText,
      variantAPrText: _prHidden ? null : s.variantAPrText,
      variantBBpEyebrow: s.variantBBpEyebrow,
      variantBClassName: s.variantBClassName,
      variantBPrTag: _prHidden ? null : s.variantBPrTag,
      variantBLift: _prHidden ? '' : s.variantBLift,
      variantBBpSub: s.variantBBpSub,
      variantBXpSub: _xpHidden ? '' : s.variantBXpSub,
      discreetEyebrow: s.discreetEyebrow,
      discreetHero: _xpHidden ? '' : s.discreetHero,
      discreetHeroSubLabel: _xpHidden ? '' : s.discreetHeroSubLabel,
      discreetPrLine: _prHidden ? null : s.discreetPrLine,
      discreetPrDetail: _prHidden ? null : s.discreetPrDetail,
    );
  }

  bool _hasPrSection() {
    return widget.strings.variantAPrText != null ||
        widget.strings.variantBPrTag != null ||
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
    await controller.sharePreview(repaintKey: _repaintKey);
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

/// Two-pill toggle for Variant A ↔ Variant B (Mínimo / Destaque).
class _VariantToggle extends StatelessWidget {
  const _VariantToggle({
    required this.value,
    required this.minimalLabel,
    required this.boldLabel,
    required this.onChanged,
  });

  final ShareCardVariant value;
  final String minimalLabel;
  final String boldLabel;
  final ValueChanged<ShareCardVariant> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'share-variant-toggle',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToggleChip(
            label: minimalLabel,
            selected: value == ShareCardVariant.minimalStrip,
            onTap: () => onChanged(ShareCardVariant.minimalStrip),
          ),
          const SizedBox(width: 8),
          _ToggleChip(
            label: boldLabel,
            selected: value == ShareCardVariant.fullBleed,
            onTap: () => onChanged(ShareCardVariant.fullBleed),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primaryViolet : AppColors.surface2;
    final fg = selected ? AppColors.textCream : AppColors.textDim;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.label.copyWith(color: fg, fontSize: 11),
          ),
        ),
      ),
    );
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
  final VoidCallback onPressed;

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
