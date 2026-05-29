import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_theme.dart';

/// Localized strings for [AvatarCropSheet]. Per
/// `feedback_widget_l10n_parameterization`, the widget never reads
/// `AppLocalizations.of(context)` directly — strings arrive via this
/// payload from the screen layer. ARB-key decisions live in
/// `profile_settings_screen.dart`.
class AvatarCropSheetStrings {
  const AvatarCropSheetStrings({
    required this.title,
    required this.confirm,
    required this.cancel,
  });

  final String title;
  final String confirm;
  final String cancel;
}

/// Sealed result type returned by [AvatarCropSheet.open].
///
/// **Why not `Uint8List?`?** A nullable byte buffer conflated two
/// distinct outcomes — "user cancelled" (no UX needed) and "rasterize
/// failed" (must surface an error snackbar). The orchestrator can't tell
/// them apart and a render failure would silently dismiss. The sealed
/// type forces the orchestrator to switch on every case explicitly.
sealed class AvatarCropResult {
  const AvatarCropResult();
}

/// User dismissed the sheet without confirming. The orchestrator returns
/// silently — no snackbar.
class AvatarCropCancelled extends AvatarCropResult {
  const AvatarCropCancelled();
}

/// Confirm tap rasterized the visible square to PNG bytes. The
/// orchestrator forwards [bytes] to `AvatarRepository.uploadAvatar`.
class AvatarCropSuccess extends AvatarCropResult {
  const AvatarCropSuccess(this.bytes);
  final Uint8List bytes;
}

/// Confirm tap reached the rasterization path but `toImage` / encode
/// threw. The orchestrator surfaces `avatarUploadFailed`. Distinct from
/// [AvatarCropCancelled] so the user sees a useful snackbar instead of
/// a silent dismiss.
class AvatarCropFailed extends AvatarCropResult {
  const AvatarCropFailed();
}

/// Bottom-sheet circular crop UI for an in-memory image.
///
/// **Flow:** the user drops in via a picker (camera / gallery), the
/// source image is wrapped in an [InteractiveViewer] inside a square
/// crop area with a circular mask overlay, the user pinches / drags to
/// reposition, and tapping Confirm rasterizes the visible square via
/// `RepaintBoundary.toImage` → PNG bytes (downsampled to 512×512 max).
/// The sheet returns an [AvatarCropResult] sealed type — Cancel pops
/// [AvatarCropCancelled], Confirm pops [AvatarCropSuccess] (or
/// [AvatarCropFailed] if rasterization throws).
///
/// **PNG output, not JPEG.** Flutter's `dart:ui` exposes a public PNG
/// encoder ([ui.ImageByteFormat.png]) but no public JPEG encoder. Rather
/// than pull in the `image` package just for the encoder, we ship PNG
/// from the crop sheet — the migration 00068 bucket accepts both
/// `image/jpeg` and `image/png`. At 512×512 the typical PNG avatar lands
/// at ~150-300KB, comfortably below the bucket's 512KB ceiling. If
/// future visual-QA flags the size budget, the follow-up is dropping in
/// the `image` package and re-encoding to JPEG at 80%.
///
/// **No external crop dependency.** Built with first-party Flutter
/// primitives ([InteractiveViewer], [CustomPaint] for the mask,
/// [RepaintBoundary], [ui.Image]). Matches the Phase 32 PR 32e "no new
/// dependencies" decision.
class AvatarCropSheet extends StatefulWidget {
  const AvatarCropSheet({
    super.key,
    required this.image,
    required this.strings,
  });

  /// Decoded source image. The caller is responsible for decoding the
  /// raw picker bytes into a [ui.Image] before opening the sheet so the
  /// sheet itself stays sync-build-friendly.
  final ui.Image image;

  /// Localized strings (title + confirm + cancel labels).
  final AvatarCropSheetStrings strings;

  /// Open the sheet on top of [context] and return an [AvatarCropResult]
  /// — never null. The sealed type forces the caller to handle "user
  /// cancelled" and "rasterize failed" distinctly. The sheet is
  /// full-width and uses the default bottom-sheet shape from [AppTheme].
  static Future<AvatarCropResult> open(
    BuildContext context, {
    required ui.Image image,
    required AvatarCropSheetStrings strings,
  }) async {
    final result = await showModalBottomSheet<AvatarCropResult>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        return AvatarCropSheet(image: image, strings: strings);
      },
    );
    // `null` reaches here when the user drags the sheet down or taps
    // the scrim — same UX as the explicit Cancel button. Collapse to
    // [AvatarCropCancelled] so the caller's switch only handles the
    // three sealed variants, not the legacy nullable contract.
    return result ?? const AvatarCropCancelled();
  }

  @override
  State<AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<AvatarCropSheet> {
  /// Repaint boundary key — the rasterization target. Wraps the square
  /// crop area; `toImage` captures exactly the pixels inside it.
  final GlobalKey _boundaryKey = GlobalKey();

  /// Tracks the in-flight rasterization so the Confirm button shows a
  /// spinner and the second tap is a no-op. Idempotent.
  bool _exporting = false;

  /// Maximum side length of the rasterized output. Stays well under the
  /// bucket's 512KB ceiling for typical avatars even at PNG (lossless).
  static const int _maxOutputDimension = 512;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Crop area sizing — 320dp ceiling matches the typical bottom-sheet
    // visible width; the floor of `screenWidth - 40dp` covers narrow
    // 320dp / 360dp phones where 320dp would overflow.
    final crop = (media.size.width - 40).clamp(0.0, 320.0);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'avatar-crop-sheet',
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
                widget.strings.title,
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.hotViolet,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: crop,
                  height: crop,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The pinch-to-zoom / drag-to-reposition surface.
                        // `boundaryMargin: EdgeInsets.all(crop)` lets
                        // the user pan outside the box on either axis;
                        // `minScale: 1` keeps the image from shrinking
                        // below the crop area so transparent corners
                        // can never appear under the mask.
                        InteractiveViewer(
                          boundaryMargin: EdgeInsets.all(crop),
                          minScale: 1.0,
                          maxScale: 5.0,
                          child: RawImage(
                            image: widget.image,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Circular mask overlay — punches a clear hole
                        // through a dark backdrop so the user sees
                        // exactly which pixels survive the crop.
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _CircularMaskPainter(
                              backdropColor: AppColors.abyss.withValues(
                                alpha: 0.55,
                              ),
                              borderColor: AppColors.hotViolet,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      // `minimumSize: Size(0, 48)` enforces the WCAG /
                      // Material 48dp tap-target baseline. The default
                      // OutlinedButton renders ~41dp tall, below the
                      // threshold; tap-target measurement via
                      // tester.getSize is the only way to catch this
                      // (see `feedback_tap_target_measurement`).
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _exporting
                          ? null
                          : () => Navigator.of(context).pop<AvatarCropResult>(
                              const AvatarCropCancelled(),
                            ),
                      child: Text(widget.strings.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _exporting ? null : _confirm,
                      child: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textCream,
                              ),
                            )
                          : Text(widget.strings.confirm),
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

  /// Rasterize the visible crop area to PNG bytes and pop the sheet
  /// with [AvatarCropSuccess]. Errors during rasterization pop with
  /// [AvatarCropFailed] — distinct from [AvatarCropCancelled] so the
  /// caller surfaces an error snackbar instead of silently dismissing.
  Future<void> _confirm() async {
    setState(() => _exporting = true);
    try {
      final bytes = await _rasterize();
      if (!mounted) return;
      Navigator.of(context).pop<AvatarCropResult>(AvatarCropSuccess(bytes));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop<AvatarCropResult>(const AvatarCropFailed());
    }
  }

  /// Capture the [RepaintBoundary], scale to [_maxOutputDimension] if
  /// larger, and encode as PNG. Returns the raw bytes ready for upload.
  Future<Uint8List> _rasterize() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    // `pixelRatio: 1` captures the boundary at its logical size. We
    // separately downscale to [_maxOutputDimension] below so the final
    // bytes ceiling holds regardless of device DPR.
    final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);

    final longestSide = captured.width > captured.height
        ? captured.width
        : captured.height;
    final scale = _maxOutputDimension / longestSide;
    final ui.Image output = scale < 1
        ? await _resize(captured, scale)
        : captured;

    final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('AvatarCropSheet: rasterize produced no bytes');
    }
    // Dispose intermediate images so the native textures release on
    // the next event-loop tick.
    captured.dispose();
    if (!identical(output, captured)) output.dispose();
    return byteData.buffer.asUint8List();
  }

  /// Downscale [src] to `scale * src.{w,h}` using
  /// [ui.PictureRecorder] + [Canvas.drawImageRect]. Avoids pulling in
  /// the `image` package for a one-line bilinear downscale.
  Future<ui.Image> _resize(ui.Image src, double scale) async {
    final targetW = (src.width * scale).round();
    final targetH = (src.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final resized = await picture.toImage(targetW, targetH);
    picture.dispose();
    return resized;
  }
}

/// Paints a dark backdrop with a circular cut-out + a 1.5dp violet
/// border around the cut-out, so the user sees the exact crop preview
/// rim without a colored ring inside the captured area.
class _CircularMaskPainter extends CustomPainter {
  _CircularMaskPainter({
    required this.backdropColor,
    required this.borderColor,
  });

  final Color backdropColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);

    // Backdrop with circular hole — even-odd fill rule paints
    // everything outside the circle and lets the inner pixels through.
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(path, Paint()..color = backdropColor);

    // Border — drawn just outside the cut-out so the captured pixels
    // are NOT the violet rim.
    canvas.drawCircle(
      center,
      radius - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularMaskPainter old) =>
      old.backdropColor != backdropColor || old.borderColor != borderColor;
}
