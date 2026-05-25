import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/data/share_image_renderer.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/providers/share_controller.dart';
import 'package:share_plus/share_plus.dart';

/// Pins [ShareController]'s state machine transitions.
///
/// **Behavior, not wiring** (CLAUDE.md Testing). Each test asserts on the
/// observable [ShareState] emitted by the controller — NOT that
/// `_service.foo()` was called N times.
void main() {
  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  SharePayload buildPayload() {
    return SharePayload.fromPostSessionState(
      tier: RewardTier.thresholdAnticipatory,
      queueResult: CelebrationQueue.build(events: const []),
      prResult: null,
      bpXpDeltas: const {BodyPart.chest: 410},
      bpRankAfter: const {BodyPart.chest: 19},
      bpProgressFractionAfter: const {BodyPart.chest: 0.5},
      exerciseNames: const {},
      totalXp: 618,
      characterClassSlug: 'bulwark',
    );
  }

  ShareService buildService({
    Future<XFile?> Function(ImageSource source)? imagePicker,
    Future<ShareResult> Function(List<XFile> files, {String? text})?
    fileShareSink,
    Future<PermissionStatus> Function(Permission)? permissionRequester,
    Future<PermissionStatus> Function(Permission)? permissionStatusReader,
  }) {
    return ShareService(
      imagePicker: imagePicker ?? (_) async => null,
      fileShareSink:
          fileShareSink ??
          (_, {text}) async =>
              const ShareResult('ok', ShareResultStatus.success),
      permissionRequester:
          permissionRequester ?? (_) async => PermissionStatus.granted,
      permissionStatusReader:
          permissionStatusReader ?? (_) async => PermissionStatus.granted,
    );
  }

  ShareImageRenderer buildRenderer({Future<XFile> Function()? onRender}) {
    return _FakeShareImageRenderer(onRender: onRender);
  }

  ProviderContainer makeContainer({
    required ShareService service,
    required ShareImageRenderer renderer,
  }) {
    final container = ProviderContainer(
      overrides: [
        shareServiceProvider.overrideWithValue(service),
        shareImageRendererProvider.overrideWithValue(renderer),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // ---------------------------------------------------------------------------
  // pickFromCamera
  // ---------------------------------------------------------------------------

  test(
    'pickFromCamera happy path transitions idle → pickingPhoto → preview',
    () async {
      final fakePhoto = _FakeXFile('/tmp/cam.jpg');
      final container = makeContainer(
        service: buildService(
          imagePicker: (_) async => fakePhoto,
          permissionRequester: (_) async => PermissionStatus.granted,
        ),
        renderer: buildRenderer(),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      expect(container.read(shareControllerProvider), const ShareState.idle());

      await notifier.pickFromCamera(payload: buildPayload());

      final terminal = container.read(shareControllerProvider);
      expect(terminal, isA<ShareStatePreview>());
      expect((terminal as ShareStatePreview).photo, fakePhoto);
    },
  );

  test(
    'pickFromCamera emits cameraPermissionDenied error when status is denied',
    () async {
      final container = makeContainer(
        service: buildService(
          permissionRequester: (_) async => PermissionStatus.denied,
        ),
        renderer: buildRenderer(),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      await notifier.pickFromCamera(payload: buildPayload());

      final s = container.read(shareControllerProvider);
      expect(s, isA<ShareStateError>());
      expect(
        (s as ShareStateError).code,
        ShareErrorCodes.cameraPermissionDenied,
      );
    },
  );

  test(
    'pickFromCamera emits cameraPermissionPermanentlyDenied error when status '
    'is permanentlyDenied',
    () async {
      final container = makeContainer(
        service: buildService(
          permissionRequester: (_) async => PermissionStatus.permanentlyDenied,
        ),
        renderer: buildRenderer(),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      await notifier.pickFromCamera(payload: buildPayload());

      final s = container.read(shareControllerProvider);
      expect(s, isA<ShareStateError>());
      expect(
        (s as ShareStateError).code,
        ShareErrorCodes.cameraPermissionPermanentlyDenied,
      );
    },
  );

  test(
    'pickFromCamera emits cancelled state when picker returns null after grant',
    () async {
      final container = makeContainer(
        service: buildService(
          permissionRequester: (_) async => PermissionStatus.granted,
          imagePicker: (_) async => null,
        ),
        renderer: buildRenderer(),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      await notifier.pickFromCamera(payload: buildPayload());

      expect(
        container.read(shareControllerProvider),
        const ShareState.cancelled(),
      );
    },
  );

  // ---------------------------------------------------------------------------
  // pickFromGallery
  // ---------------------------------------------------------------------------

  test(
    'pickFromGallery happy path transitions to preview with the chosen photo',
    () async {
      final fakePhoto = _FakeXFile('/tmp/lib.jpg');
      final container = makeContainer(
        service: buildService(imagePicker: (_) async => fakePhoto),
        renderer: buildRenderer(),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      await notifier.pickFromGallery(payload: buildPayload());

      final s = container.read(shareControllerProvider);
      expect(s, isA<ShareStatePreview>());
      expect((s as ShareStatePreview).photo, fakePhoto);
    },
  );

  test('pickFromGallery emits cancelled when picker returns null', () async {
    final container = makeContainer(
      service: buildService(imagePicker: (_) async => null),
      renderer: buildRenderer(),
    );

    final notifier = container.read(shareControllerProvider.notifier);
    await notifier.pickFromGallery(payload: buildPayload());

    expect(
      container.read(shareControllerProvider),
      const ShareState.cancelled(),
    );
  });

  // ---------------------------------------------------------------------------
  // useDiscreet
  // ---------------------------------------------------------------------------

  test('useDiscreet jumps straight to preview with a null photo', () {
    final container = makeContainer(
      service: buildService(),
      renderer: buildRenderer(),
    );

    final notifier = container.read(shareControllerProvider.notifier);
    notifier.useDiscreet(payload: buildPayload());

    final s = container.read(shareControllerProvider);
    expect(s, isA<ShareStatePreview>());
    expect((s as ShareStatePreview).photo, isNull);
  });

  // ---------------------------------------------------------------------------
  // sharePreview
  // ---------------------------------------------------------------------------

  test(
    'sharePreview happy path transitions preview → rendering → sharing → idle',
    () async {
      final renderedFile = _FakeXFile('/tmp/share_card_123.png');
      final container = makeContainer(
        service: buildService(
          fileShareSink: (_, {text}) async =>
              const ShareResult('ok', ShareResultStatus.success),
        ),
        renderer: buildRenderer(onRender: () async => renderedFile),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      // Pre-condition: must be in preview state.
      notifier.useDiscreet(payload: buildPayload());

      await notifier.sharePreview(
        repaintKey: GlobalKey(debugLabel: 'test-repaint'),
        shareText: 'Caption',
      );

      // Terminal state lands on idle (success path resets the machine).
      expect(container.read(shareControllerProvider), const ShareState.idle());
    },
  );

  test('sharePreview emits render_failed error when renderer throws', () async {
    final container = makeContainer(
      service: buildService(),
      renderer: buildRenderer(
        onRender: () async => throw StateError('boundary unmounted'),
      ),
    );

    final notifier = container.read(shareControllerProvider.notifier);
    notifier.useDiscreet(payload: buildPayload());

    await notifier.sharePreview(repaintKey: GlobalKey());

    final s = container.read(shareControllerProvider);
    expect(s, isA<ShareStateError>());
    expect((s as ShareStateError).code, ShareErrorCodes.renderFailed);
  });

  test(
    'sharePreview emits share_failed error when share returns unavailable',
    () async {
      final container = makeContainer(
        service: buildService(
          fileShareSink: (_, {text}) async =>
              const ShareResult('na', ShareResultStatus.unavailable),
        ),
        renderer: buildRenderer(
          onRender: () async => _FakeXFile('/tmp/share_card.png'),
        ),
      );

      final notifier = container.read(shareControllerProvider.notifier);
      notifier.useDiscreet(payload: buildPayload());

      await notifier.sharePreview(repaintKey: GlobalKey());

      final s = container.read(shareControllerProvider);
      expect(s, isA<ShareStateError>());
      expect((s as ShareStateError).code, ShareErrorCodes.shareFailed);
    },
  );

  test('sharePreview is a no-op when state is not preview', () async {
    final container = makeContainer(
      service: buildService(),
      renderer: buildRenderer(
        onRender: () async {
          fail('renderer should not be invoked from non-preview state');
        },
      ),
    );

    final notifier = container.read(shareControllerProvider.notifier);
    // State is idle.
    await notifier.sharePreview(repaintKey: GlobalKey());

    // No transition occurred.
    expect(container.read(shareControllerProvider), const ShareState.idle());
  });

  // ---------------------------------------------------------------------------
  // reset
  // ---------------------------------------------------------------------------

  test('reset returns the state to idle from preview', () {
    final container = makeContainer(
      service: buildService(),
      renderer: buildRenderer(),
    );

    final notifier = container.read(shareControllerProvider.notifier);
    notifier.useDiscreet(payload: buildPayload());
    expect(container.read(shareControllerProvider), isA<ShareStatePreview>());

    notifier.reset();
    expect(container.read(shareControllerProvider), const ShareState.idle());
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeXFile extends XFile {
  _FakeXFile(super.path);
}

/// Renderer fake that lets each test inject a synchronous callback (or
/// thrower). Avoids staging a real `RenderRepaintBoundary` in unit tests.
class _FakeShareImageRenderer implements ShareImageRenderer {
  _FakeShareImageRenderer({this.onRender});

  final Future<XFile> Function()? onRender;

  @override
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    int jpegQuality = 88,
  }) {
    final cb = onRender;
    if (cb == null) {
      throw StateError(
        'fake renderer was invoked but no onRender callback was provided',
      );
    }
    return cb();
  }
}
