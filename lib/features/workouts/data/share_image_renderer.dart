import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Encodes a [ui.Image] to bytes. Hoisted to a top-level typedef so tests
/// can inject a synchronous fake (the real implementation does an async
/// channel hop into the engine).
typedef ImageEncoder =
    Future<ByteData?> Function(
      ui.Image image, {
      required ui.ImageByteFormat format,
    });

/// Resolves a [RenderRepaintBoundary] from a [GlobalKey]. Hoisted so the
/// test can inject a mock boundary without staging the actual widget tree.
typedef BoundaryResolver = RenderRepaintBoundary? Function(GlobalKey key);

/// Returns the OS temp directory the rendered file should be written to.
/// Hoisted so tests can substitute a [Directory.systemTemp] under control.
typedef TempDirResolver = Future<Directory> Function();

/// Provides the wall-clock millis used in the deterministic filename.
/// Hoisted so tests can lock the filename and assert on it.
typedef NowMillis = int Function();

/// Captures the widget under a [RepaintBoundary] and writes it to a
/// temporary image file ready to hand off to `share_plus`.
///
/// **Caller responsibility — tight constraints on the RepaintBoundary.**
/// The [RenderRepaintBoundary] captures whatever size its child laid out
/// at. If the host inserts the boundary into a loose-constraint context
/// (e.g. a scroll view, `Align`, an unconstrained `Column`), the boundary
/// records the child's intrinsic size — not the share-card target size
/// (1080×1920). Wrap the child in a `SizedBox(width: 1080, height: 1920)`
/// (or pass the boundary through an `OverflowBox`+`SizedBox` if the host
/// surface is smaller than the target) so the captured image matches the
/// card design. Pass 1 widget goldens hit this exact trap; the dartdoc is
/// load-bearing for the Pass 3 controller integration.
///
/// **File format.** Ships PNG bytes via `ui.Image.toByteData(PNG)`. JPEG
/// would shrink the file ~5×, but adding the `image` package solely to
/// re-encode a 1080×1920 frame isn't worth the dep surface for Pass 2.
/// TODO(pass-3): if 1080×1920×4-byte PNGs prove too large for share-sheet
/// payloads in practice, add `image: ^4.x` and `img.encodeJpg(...)` here.
///
/// **Fallback retry.** If the rendered byte count exceeds 1.2MB at the
/// requested [pixelRatio], the renderer transparently retries once at
/// `pixelRatio: 2.0` and returns the smaller file. This keeps the share
/// payload under most Android/iOS share-sheet attachment limits while
/// preserving max quality for typical sessions.
class ShareImageRenderer {
  ShareImageRenderer({
    BoundaryResolver? boundaryResolver,
    ImageEncoder? imageEncoder,
    TempDirResolver? tempDirResolver,
    NowMillis? nowMillis,
  }) : _resolveBoundary = boundaryResolver ?? _defaultBoundaryResolver,
       _encodeImage = imageEncoder ?? _defaultImageEncoder,
       _tempDir = tempDirResolver ?? getTemporaryDirectory,
       _nowMillis = nowMillis ?? _defaultNowMillis;

  /// Hard ceiling above which the renderer downsamples once at
  /// `pixelRatio: 2.0`. Sized to the smallest known share-sheet attachment
  /// cap (Android Sharesheet rejects multi-MB images on some OEM skins;
  /// iOS is more permissive). 1.2 MB leaves headroom for any text-payload
  /// the caller appends.
  static const int _maxBytes = 1200 * 1024;

  /// Used when no override is provided. Falls back to `2.0` after a
  /// `_maxBytes` overflow at the requested ratio.
  static const double _fallbackPixelRatio = 2.0;

  final BoundaryResolver _resolveBoundary;
  final ImageEncoder _encodeImage;
  final TempDirResolver _tempDir;
  final NowMillis _nowMillis;

  /// Render the widget under [repaintKey] and return the resulting file.
  ///
  /// Throws [StateError] if the key is not currently attached to a
  /// [RenderRepaintBoundary] (i.e. the host widget tree has been unmounted
  /// or never mounted). Callers are expected to schedule this call inside
  /// a `WidgetsBinding.instance.addPostFrameCallback` so the boundary has
  /// completed its first layout pass.
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    // jpegQuality retained on the signature for forward-compat with the
    // Pass-3 JPEG path documented above. Currently a no-op (PNG output
    // has no quality knob).
    int jpegQuality = 88,
  }) async {
    final bytes = await _captureBytes(
      repaintKey: repaintKey,
      pixelRatio: pixelRatio,
    );

    final Uint8List finalBytes;
    if (bytes.lengthInBytes > _maxBytes && pixelRatio > _fallbackPixelRatio) {
      finalBytes = await _captureBytes(
        repaintKey: repaintKey,
        pixelRatio: _fallbackPixelRatio,
      );
    } else {
      finalBytes = bytes;
    }

    final dir = await _tempDir();
    final filename = 'share_card_${_nowMillis()}.png';
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(finalBytes, flush: true);
    return XFile(file.path);
  }

  Future<Uint8List> _captureBytes({
    required GlobalKey repaintKey,
    required double pixelRatio,
  }) async {
    final boundary = _resolveBoundary(repaintKey);
    if (boundary == null) {
      throw StateError(
        'ShareImageRenderer: repaintKey is not attached to a '
        'RenderRepaintBoundary. Schedule the render() call after the first '
        'frame using WidgetsBinding.instance.addPostFrameCallback.',
      );
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await _encodeImage(
        image,
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw StateError(
          'ShareImageRenderer: ui.Image.toByteData returned null.',
        );
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static RenderRepaintBoundary? _defaultBoundaryResolver(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is RenderRepaintBoundary) return ro;
    return null;
  }

  static Future<ByteData?> _defaultImageEncoder(
    ui.Image image, {
    required ui.ImageByteFormat format,
  }) {
    return image.toByteData(format: format);
  }

  static int _defaultNowMillis() => DateTime.now().millisecondsSinceEpoch;
}
