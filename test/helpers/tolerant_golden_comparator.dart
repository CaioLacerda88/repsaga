/// A [GoldenFileComparator] that tolerates a small percentage of pixel
/// difference between the test image and the master.
///
/// **Why this exists.** Golden tests that include rasterized text are not
/// byte-exact across host platforms. Even with the same TTF asset (Rajdhani
/// + Inter, bundled via `assets/fonts/`), Skia's text shaping pipeline emits
/// different sub-pixel anti-aliasing on Linux (freetype) vs Windows
/// (DirectWrite-influenced). On the same painted frame, the two platforms
/// diverge on roughly 0.5–2% of pixels in the glyph edges — a noise floor
/// well below any meaningful visual regression (a color flip, a halo blur
/// change, a layout shift would all paint diffs >> 5%).
///
/// The default [LocalFileComparator] has zero tolerance and fails the test
/// for any single-pixel difference. That is too strict for text-bearing
/// golden surfaces.
///
/// **Where to use this.** Only on golden tests where the painted output
/// includes rasterized text. Pure-shape goldens (geometric CustomPainter
/// renderings — polygons, arcs, gradients without external imagery) should
/// keep the default zero-tolerance comparator because they are byte-exact
/// across platforms.
///
/// **Tolerance choice.** [tolerance] is the maximum fraction of pixels that
/// may differ (0.0 = exact, 1.0 = always pass). Default 0.03 (3%) gives
/// ~50% headroom over the worst observed Linux-vs-Windows divergence (2.06%
/// on `title_unlock_sheet_subsequent.png` per CI run 25085542398) while
/// still catching real regressions: a single recolored Text region or a
/// shifted halo paints diffs much greater than 3% of the canvas.
///
/// **Usage.** Install in a test file's `setUpAll` and restore in
/// `tearDownAll`. Note that [LocalFileComparator]'s constructor expects a
/// file URI inside the target directory (it recomputes `basedir` via
/// `dirname()`), so append a dummy filename when forwarding the existing
/// `basedir`:
///
/// ```dart
/// late GoldenFileComparator _previousComparator;
///
/// setUpAll(() {
///   _previousComparator = goldenFileComparator;
///   final basedir = (goldenFileComparator as LocalFileComparator).basedir;
///   goldenFileComparator = TolerantGoldenFileComparator(
///     basedir.resolve('test.dart'),
///     tolerance: 0.03,
///   );
/// });
///
/// tearDownAll(() {
///   goldenFileComparator = _previousComparator;
/// });
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drop-in replacement for [LocalFileComparator] that passes when the
/// pixel-difference fraction is at or below [tolerance].
///
/// Behaves identically to [LocalFileComparator] in every other respect:
/// reads goldens from the test file's directory, writes failure diffs to a
/// `failures/` sibling directory, and supports `--update-goldens` via the
/// inherited [LocalFileComparator.update] implementation.
class TolerantGoldenFileComparator extends LocalFileComparator {
  /// Creates a tolerant comparator rooted at [testBaseDir].
  ///
  /// [LocalFileComparator]'s constructor recomputes `basedir` via
  /// `dirname(testBaseDir)`, so [testBaseDir] must be a file URI inside the
  /// target directory — not the directory URI itself. Append a dummy
  /// filename to the existing comparator's `basedir` when forwarding it:
  ///
  /// ```dart
  /// final basedir = (goldenFileComparator as LocalFileComparator).basedir;
  /// goldenFileComparator = TolerantGoldenFileComparator(
  ///   basedir.resolve('test.dart'),
  /// );
  /// ```
  TolerantGoldenFileComparator(super.testBaseDir, {this.tolerance = 0.03})
    : assert(
        tolerance >= 0.0 && tolerance <= 1.0,
        'tolerance must be in [0.0, 1.0]',
      );

  /// Maximum pixel-difference fraction (0.0 to 1.0) that still passes.
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = await getGoldenBytes(golden);
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      goldenBytes,
    );

    if (result.passed) {
      result.dispose();
      return true;
    }

    if (result.diffPercent <= tolerance) {
      // Within tolerance — accept the frame. We deliberately do NOT write
      // failure images here: the test passed, there is nothing to diff.
      debugPrint(
        'TolerantGoldenFileComparator: golden "$golden" passed within '
        'tolerance (${(result.diffPercent * 100).toStringAsFixed(2)}% '
        '<= ${(tolerance * 100).toStringAsFixed(0)}%).',
      );
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
