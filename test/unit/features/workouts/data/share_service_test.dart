import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
import 'package:share_plus/share_plus.dart';

class _FakeXFile extends XFile {
  _FakeXFile(super.path);
}

void main() {
  group('ShareService.pickFromCamera', () {
    test('invokes the picker with ImageSource.camera', () async {
      final calls = <ImageSource>[];
      final fake = _FakeXFile('/tmp/cam.jpg');
      final svc = ShareService(
        imagePicker: (src) async {
          calls.add(src);
          return fake;
        },
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async => PermissionStatus.granted,
        permissionStatusReader: (_) async => PermissionStatus.granted,
      );

      final result = await svc.pickFromCamera();

      expect(calls, [ImageSource.camera]);
      expect(result, fake);
    });

    test('returns null when the picker reports cancel', () async {
      final svc = ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async => PermissionStatus.granted,
        permissionStatusReader: (_) async => PermissionStatus.granted,
      );

      expect(await svc.pickFromCamera(), isNull);
    });
  });

  group('ShareService.pickFromGallery', () {
    test('invokes the picker with ImageSource.gallery', () async {
      final calls = <ImageSource>[];
      final svc = ShareService(
        imagePicker: (src) async {
          calls.add(src);
          return _FakeXFile('/tmp/lib.jpg');
        },
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async => PermissionStatus.granted,
        permissionStatusReader: (_) async => PermissionStatus.granted,
      );

      await svc.pickFromGallery();

      expect(calls, [ImageSource.gallery]);
    });

    test('returns null when the user dismisses the gallery picker', () async {
      final svc = ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async => PermissionStatus.granted,
        permissionStatusReader: (_) async => PermissionStatus.granted,
      );

      expect(await svc.pickFromGallery(), isNull);
    });
  });

  group('ShareService.share', () {
    test(
      'hands the single XFile to the share sink with the supplied text',
      () async {
        final captured = <({List<XFile> files, String? text})>[];
        final svc = ShareService(
          imagePicker: (_) async => null,
          fileShareSink: (files, {text}) async {
            captured.add((files: files, text: text));
            return const ShareResult('ok', ShareResultStatus.success);
          },
          permissionRequester: (_) async => PermissionStatus.granted,
          permissionStatusReader: (_) async => PermissionStatus.granted,
        );
        final f = _FakeXFile('/tmp/card.png');

        await svc.share(f, text: 'Caption');

        expect(captured.length, 1);
        expect(captured.first.files, [f]);
        expect(captured.first.text, 'Caption');
      },
    );

    test('omitting text forwards null to the share sink', () async {
      String? observedText;
      bool sinkCalled = false;
      final svc = ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (files, {text}) async {
          sinkCalled = true;
          observedText = text;
          return const ShareResult('ok', ShareResultStatus.success);
        },
        permissionRequester: (_) async => PermissionStatus.granted,
        permissionStatusReader: (_) async => PermissionStatus.granted,
      );

      await svc.share(_FakeXFile('/tmp/card.png'));

      expect(sinkCalled, isTrue);
      expect(observedText, isNull);
    });
  });

  group('ShareService.requestCameraPermission', () {
    test(
      'requests Permission.camera and returns the post-prompt status',
      () async {
        final requested = <Permission>[];
        final svc = ShareService(
          imagePicker: (_) async => null,
          fileShareSink: (_, {text}) async => throw UnimplementedError(),
          permissionRequester: (p) async {
            requested.add(p);
            return PermissionStatus.granted;
          },
          permissionStatusReader: (_) async => PermissionStatus.denied,
        );

        final status = await svc.requestCameraPermission();

        expect(requested, [Permission.camera]);
        expect(status, PermissionStatus.granted);
      },
    );

    test('propagates denial status without throwing', () async {
      final svc = ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async => PermissionStatus.denied,
        permissionStatusReader: (_) async => PermissionStatus.denied,
      );

      expect(await svc.requestCameraPermission(), PermissionStatus.denied);
    });

    test('propagates permanentlyDenied without throwing', () async {
      final svc = ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async => PermissionStatus.permanentlyDenied,
        permissionStatusReader: (_) async => PermissionStatus.permanentlyDenied,
      );

      expect(
        await svc.requestCameraPermission(),
        PermissionStatus.permanentlyDenied,
      );
    });
  });

  group('ShareService.cameraPermissionStatus', () {
    test('reads Permission.camera status without invoking request', () async {
      final readCalls = <Permission>[];
      var requestCalls = 0;
      final svc = ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (_, {text}) async => throw UnimplementedError(),
        permissionRequester: (_) async {
          requestCalls += 1;
          return PermissionStatus.granted;
        },
        permissionStatusReader: (p) async {
          readCalls.add(p);
          return PermissionStatus.denied;
        },
      );

      final status = await svc.cameraPermissionStatus();

      expect(readCalls, [Permission.camera]);
      expect(requestCalls, 0);
      expect(status, PermissionStatus.denied);
    });
  });
}
