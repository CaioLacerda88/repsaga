import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global test config, auto-loaded by `flutter test` per package conventions.
///
/// **Font loading contract (Phase 27 L14).** [AppTextStyles] now renders
/// Rajdhani + Inter via direct `TextStyle(fontFamily: ...)` calls — NOT via
/// `GoogleFonts.rajdhani(...)`. The package's async asset-manifest lookup
/// was silently falling back to Inter on real-device release builds. The
/// direct approach uses Flutter's synchronous font loader, which in tests
/// requires the TTFs to be explicitly registered via [FontLoader] before
/// any widget that consumes the family is pumped. We register both families
/// here once, globally, so every widget test renders with the actual font
/// metrics instead of the test default — eliminating ~12px overflow
/// regressions in fixed-size overlays (celebration cards, awakening
/// overlays) that were caught during the L14 retest.
///
/// [GoogleFonts.config.allowRuntimeFetching] stays hard-off as defense in
/// depth: if a future caller introduces a `GoogleFonts.*` reference, the
/// failure is loud at debug ("font X not found in assets") instead of a
/// silent network fetch.
///
/// Text-bearing goldens diverge across platforms (~0.5–2% on glyph edges)
/// due to Skia text shaping differences (Linux freetype vs Windows
/// DirectWrite). For those tests, install `TolerantGoldenFileComparator`
/// per-file via `setUpAll`/`tearDownAll`. See
/// `test/helpers/tolerant_golden_comparator.dart`. Pure-shape goldens
/// keep the default zero-tolerance comparator.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await _loadAppFonts();
  await testMain();
}

/// Registers Rajdhani + Inter TTFs with Flutter's runtime font loader so
/// widget tests render text with the correct family metrics. Mirrors the
/// `pubspec.yaml > flutter.fonts:` declaration.
Future<void> _loadAppFonts() async {
  await _loadFamily('Rajdhani', const [
    'assets/fonts/Rajdhani-Medium.ttf',
    'assets/fonts/Rajdhani-SemiBold.ttf',
    'assets/fonts/Rajdhani-Bold.ttf',
  ]);
  await _loadFamily('Inter', const [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
  ]);
}

Future<void> _loadFamily(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(_loadBytes(asset));
  }
  await loader.load();
}

Future<ByteData> _loadBytes(String asset) async {
  return rootBundle.load(asset);
}
