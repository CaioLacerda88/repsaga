// AvatarCropSheet widget tests.
//
// **Rasterization contract is on-device.** The Confirm-tap →
// `RepaintBoundary.toImage` → PNG-bytes pipeline does NOT complete under
// `WidgetTester`'s synthetic clock — even when wrapped in
// `tester.runAsync` + a real-time `Future.delayed`, the modal-pop future
// stayed unresolved (`null`) and `pumpAndSettle` deadlocked. Three
// investigation paths were tried:
//   * `tester.runAsync` + staged `pump(Duration)` + `Future.delayed`
//     → result remained null after runAsync's scope exited.
//   * `pumpAndSettle(Duration(seconds: 2))` after `Use this` tap
//     → timed out (the rasterization frame loop never settles).
//   * Direct `findRenderObject().toImage` inside runAsync
//     → boundary not yet laid out at the captured frame.
//
// The widget-layer tests below pin the user-visible structural contract
// (title + buttons render, semantics identifier present, both buttons
// meet 48dp tap target, Cancel pops with AvatarCropCancelled). The
// byte-encoding contract is gated by visual verification on-device per
// the PR #283 body's "visual verification required" section. DO NOT
// downgrade to a wiring assertion (`confirmButton.onPressed != null`) —
// the on-device path remains the canonical gate.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/profile/ui/widgets/avatar_crop_sheet.dart';

import '../../../../../helpers/test_material_app.dart';

/// Generate a tiny 2×2 magenta [ui.Image] via [ui.PictureRecorder].
/// Avoids the codec path entirely — the codec runs natively and is
/// unreliable inside the test harness even when wrapped in
/// `tester.runAsync` (Flutter SDK rev-dependent).
Future<ui.Image> _makeTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = const Color(0xFFFF00FF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  picture.dispose();
  return image;
}

const _strings = AvatarCropSheetStrings(
  title: 'Position your avatar',
  confirm: 'Use this',
  cancel: 'Cancel',
);

Future<ui.Image> _pumpHostWithImage(WidgetTester tester) async {
  final image = await tester.runAsync<ui.Image>(_makeTestImage);
  await tester.pumpWidget(
    TestMaterialApp(
      home: Scaffold(
        body: AvatarCropSheet(image: image!, strings: _strings),
      ),
    ),
  );
  await tester.pump();
  return image;
}

void main() {
  group('AvatarCropSheet', () {
    testWidgets('renders the title + confirm + cancel buttons', (tester) async {
      final image = await _pumpHostWithImage(tester);

      expect(find.text('Position your avatar'), findsOneWidget);
      expect(find.text('Use this'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      image.dispose();
    });

    testWidgets('carries the avatar-crop-sheet semantics identifier', (
      tester,
    ) async {
      final image = await _pumpHostWithImage(tester);

      final hasIdentifier = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any((s) => s.properties.identifier == 'avatar-crop-sheet');
      expect(hasIdentifier, isTrue);

      image.dispose();
    });

    testWidgets('Confirm + Cancel buttons clear the 48dp tap-target floor', (
      tester,
    ) async {
      // `feedback_tap_target_measurement` — Playwright boundingBox and
      // source `minimumSize` both miss Flutter's
      // `MaterialTapTargetSize.padded` default, so we measure via
      // `tester.getSize` against the actual rendered geometry.
      final image = await _pumpHostWithImage(tester);

      final confirmFinder = find.ancestor(
        of: find.text('Use this'),
        matching: find.byType(FilledButton),
      );
      final cancelFinder = find.ancestor(
        of: find.text('Cancel'),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.getSize(confirmFinder).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(cancelFinder).height, greaterThanOrEqualTo(48));

      image.dispose();
    });

    testWidgets('tapping Cancel pops the sheet with AvatarCropCancelled', (
      tester,
    ) async {
      final image = await _makeTestImage();
      AvatarCropResult? result;

      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await AvatarCropSheet.open(
                      context,
                      image: image,
                      strings: _strings,
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isA<AvatarCropCancelled>());

      image.dispose();
    });

    // Confirm rasterization contract is on-device-only — see the
    // header comment for the runAsync investigation summary.
  });
}
