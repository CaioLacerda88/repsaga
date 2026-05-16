import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global test config, auto-loaded by `flutter test` per package conventions.
///
/// Rajdhani + Inter TTFs are bundled under `assets/fonts/` and declared in
/// `pubspec.yaml`. `google_fonts` resolves these via its asset-manifest
/// lookup first (lib/src/google_fonts_base.dart:148), so tests load fonts
/// from local assets and never touch the network.
///
/// [GoogleFonts.config.allowRuntimeFetching] is hard-off as a belt-and-braces
/// guard: if anyone ever adds a new font variant without bundling it, the
/// failure is loud ("font X not found in assets") instead of a silent network
/// fetch that fails on slow networks / sandboxed CI.
/// Text-bearing goldens diverge across platforms (~0.5–2% on glyph edges)
/// due to Skia text shaping differences (Linux freetype vs Windows
/// DirectWrite). For those tests, install `TolerantGoldenFileComparator`
/// per-file via `setUpAll`/`tearDownAll`. See
/// `test/helpers/tolerant_golden_comparator.dart`. Pure-shape goldens
/// keep the default zero-tolerance comparator.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
