import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/data/share_image_renderer.dart';

class _FakeUiImage extends Fake implements ui.Image {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

/// Records the `pixelRatio` of every `toImage` invocation and returns a
/// fresh disposable image per call. `Fake` is used over `Mock` to side-step
/// the `RenderObject.toString({DiagnosticLevel minLevel})` override clash
/// that `Mock.toString()` triggers on the analyzer.
class _RecordingBoundary extends Fake implements RenderRepaintBoundary {
  final List<double> pixelRatios = [];

  @override
  Future<ui.Image> toImage({double pixelRatio = 1.0}) async {
    pixelRatios.add(pixelRatio);
    return _FakeUiImage();
  }

  // `RenderObject` widens `toString` with a `minLevel` named parameter;
  // without this override `Object.toString` from `Fake` triggers
  // `invalid_implementation_override`.
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_RecordingBoundary';
}

void main() {
  group('ShareImageRenderer.render', () {
    late Directory tmpRoot;

    setUp(() async {
      tmpRoot = await Directory.systemTemp.createTemp('share_card_test_');
    });

    tearDown(() async {
      if (tmpRoot.existsSync()) {
        await tmpRoot.delete(recursive: true);
      }
    });

    test('calls boundary.toImage with the requested pixelRatio', () async {
      final boundary = _RecordingBoundary();
      final renderer = ShareImageRenderer(
        boundaryResolver: (_) => boundary,
        imageEncoder: (_, {required format}) async =>
            ByteData.view(Uint8List(64).buffer),
        tempDirResolver: () async => tmpRoot,
        nowMillis: () => 1700000000000,
      );

      await renderer.render(repaintKey: GlobalKey(), pixelRatio: 3.0);

      expect(boundary.pixelRatios, [3.0]);
    });

    test('writes the file to the temp dir with a .png suffix', () async {
      final boundary = _RecordingBoundary();
      final renderer = ShareImageRenderer(
        boundaryResolver: (_) => boundary,
        imageEncoder: (_, {required format}) async =>
            ByteData.view(Uint8List(128).buffer),
        tempDirResolver: () async => tmpRoot,
        nowMillis: () => 1700000000000,
      );

      final xfile = await renderer.render(repaintKey: GlobalKey());

      expect(xfile.path, endsWith('.png'));
      expect(xfile.path.contains(tmpRoot.path), isTrue);
      expect(File(xfile.path).existsSync(), isTrue);
    });

    test('uses a deterministic timestamp-based filename', () async {
      final boundary = _RecordingBoundary();
      final renderer = ShareImageRenderer(
        boundaryResolver: (_) => boundary,
        imageEncoder: (_, {required format}) async =>
            ByteData.view(Uint8List(64).buffer),
        tempDirResolver: () async => tmpRoot,
        nowMillis: () => 1234567890,
      );

      final xfile = await renderer.render(repaintKey: GlobalKey());

      expect(xfile.path, endsWith('share_card_1234567890.png'));
    });

    test('returns a non-null XFile', () async {
      final boundary = _RecordingBoundary();
      final renderer = ShareImageRenderer(
        boundaryResolver: (_) => boundary,
        imageEncoder: (_, {required format}) async =>
            ByteData.view(Uint8List(64).buffer),
        tempDirResolver: () async => tmpRoot,
        nowMillis: () => 1700000000000,
      );

      final xfile = await renderer.render(repaintKey: GlobalKey());

      expect(xfile, isNotNull);
    });

    test('retries at pixelRatio 2.0 when first encode exceeds 1.2MB', () async {
      final boundary = _RecordingBoundary();
      var calls = 0;
      final renderer = ShareImageRenderer(
        boundaryResolver: (_) => boundary,
        imageEncoder: (_, {required format}) async {
          calls += 1;
          // First call: oversized (>1.2MB). Second call (retry at 2.0x):
          // small. The renderer must dispatch a second capture at the
          // fallback ratio.
          final size = calls == 1 ? (1300 * 1024) : (200 * 1024);
          return ByteData.view(Uint8List(size).buffer);
        },
        tempDirResolver: () async => tmpRoot,
        nowMillis: () => 1700000000000,
      );

      final xfile = await renderer.render(
        repaintKey: GlobalKey(),
        pixelRatio: 3.0,
      );

      // Two boundary captures: original 3.0 then fallback 2.0.
      expect(boundary.pixelRatios, [3.0, 2.0]);
      // The file on disk is the smaller (200KB) payload, not the oversize
      // initial encode.
      expect(File(xfile.path).lengthSync(), 200 * 1024);
    });

    test(
      'does not retry when the first encode is already under the cap',
      () async {
        final boundary = _RecordingBoundary();
        final renderer = ShareImageRenderer(
          boundaryResolver: (_) => boundary,
          imageEncoder: (_, {required format}) async =>
              ByteData.view(Uint8List(500 * 1024).buffer),
          tempDirResolver: () async => tmpRoot,
          nowMillis: () => 1700000000000,
        );

        await renderer.render(repaintKey: GlobalKey(), pixelRatio: 3.0);

        expect(boundary.pixelRatios, [3.0]);
      },
    );

    test(
      'does not retry below the fallback ratio (no infinite-loop guard)',
      () async {
        // If the host already requested pixelRatio <= 2.0 and the result is
        // still oversized, the renderer must NOT retry — there's no smaller
        // ratio to fall back to that would help.
        final boundary = _RecordingBoundary();
        final renderer = ShareImageRenderer(
          boundaryResolver: (_) => boundary,
          imageEncoder: (_, {required format}) async =>
              ByteData.view(Uint8List(1300 * 1024).buffer),
          tempDirResolver: () async => tmpRoot,
          nowMillis: () => 1700000000000,
        );

        await renderer.render(repaintKey: GlobalKey(), pixelRatio: 2.0);

        expect(boundary.pixelRatios, [2.0]);
      },
    );

    test('throws StateError when key is not attached to a boundary', () async {
      final renderer = ShareImageRenderer(
        boundaryResolver: (_) => null,
        imageEncoder: (_, {required format}) async =>
            ByteData.view(Uint8List(64).buffer),
        tempDirResolver: () async => tmpRoot,
        nowMillis: () => 1700000000000,
      );

      await expectLater(
        renderer.render(repaintKey: GlobalKey()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
