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

    testWidgets('Confirm button is wired to the rasterize handler', (
      tester,
    ) async {
      final image = await _pumpHostWithImage(tester);

      final confirmButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Use this'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(confirmButton.onPressed, isNotNull);

      image.dispose();
    });

    testWidgets('Cancel button is wired to the cancel handler', (tester) async {
      final image = await _pumpHostWithImage(tester);

      final cancelButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(cancelButton.onPressed, isNotNull);

      image.dispose();
    });
  });
}
