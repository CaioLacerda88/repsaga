import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/workouts/data/share_image_renderer.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
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
    _RecordingAnalyticsRepository? analyticsRepo,
    String? userId = 'user-share-001',
  }) {
    final container = ProviderContainer(
      overrides: [
        shareServiceProvider.overrideWithValue(service),
        shareImageRendererProvider.overrideWithValue(renderer),
        if (analyticsRepo != null)
          analyticsRepositoryProvider.overrideWithValue(analyticsRepo),
        currentUserIdProvider.overrideWithValue(userId),
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

      await notifier.pickFromCamera();

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
      await notifier.pickFromCamera();

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
      await notifier.pickFromCamera();

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
      await notifier.pickFromCamera();

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
      await notifier.pickFromGallery();

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
    await notifier.pickFromGallery();

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
    notifier.useDiscreet();

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
      notifier.useDiscreet();

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
    notifier.useDiscreet();

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
      notifier.useDiscreet();

      await notifier.sharePreview(repaintKey: GlobalKey());

      final s = container.read(shareControllerProvider);
      expect(s, isA<ShareStateError>());
      expect((s as ShareStateError).code, ShareErrorCodes.shareFailed);
    },
  );

  // ---------------------------------------------------------------------------
  // sharePreview — Phase 32 PR 32d analytics emit
  // ---------------------------------------------------------------------------

  test(
    'sharePreview emits share_card_exported with variant=discreet on success '
    'without photo',
    () async {
      final analyticsRepo = _RecordingAnalyticsRepository();
      final container = makeContainer(
        service: buildService(
          fileShareSink: (_, {text}) async =>
              const ShareResult('ok', ShareResultStatus.success),
        ),
        renderer: buildRenderer(
          onRender: () async => _FakeXFile('/tmp/share.png'),
        ),
        analyticsRepo: analyticsRepo,
      );

      final notifier = container.read(shareControllerProvider.notifier);
      // No photo selected — discreet path.
      notifier.useDiscreet();

      await notifier.sharePreview(repaintKey: GlobalKey());

      // Assert the exact event payload — behavior, not "was called".
      expect(analyticsRepo.events, [
        const AnalyticsEvent.shareCardExported(
          variant: 'discreet',
          hadCustomPhoto: false,
        ),
      ]);
    },
  );

  test('sharePreview emits share_card_exported with variant=with_photo when a '
      'photo is attached', () async {
    final analyticsRepo = _RecordingAnalyticsRepository();
    final photo = _FakeXFile('/tmp/photo.jpg');
    final container = makeContainer(
      service: buildService(
        fileShareSink: (_, {text}) async =>
            const ShareResult('ok', ShareResultStatus.success),
      ),
      renderer: buildRenderer(
        onRender: () async => _FakeXFile('/tmp/share.png'),
      ),
      analyticsRepo: analyticsRepo,
    );

    final notifier = container.read(shareControllerProvider.notifier);
    notifier.resetToPreview(photo: photo);

    await notifier.sharePreview(repaintKey: GlobalKey());

    expect(analyticsRepo.events, [
      const AnalyticsEvent.shareCardExported(
        variant: 'with_photo',
        hadCustomPhoto: true,
      ),
    ]);
  });

  test(
    'sharePreview does NOT emit share_card_exported on dismissed sheet',
    () async {
      final analyticsRepo = _RecordingAnalyticsRepository();
      final container = makeContainer(
        service: buildService(
          fileShareSink: (_, {text}) async =>
              const ShareResult('na', ShareResultStatus.dismissed),
        ),
        renderer: buildRenderer(
          onRender: () async => _FakeXFile('/tmp/share.png'),
        ),
        analyticsRepo: analyticsRepo,
      );

      final notifier = container.read(shareControllerProvider.notifier);
      notifier.useDiscreet();

      await notifier.sharePreview(repaintKey: GlobalKey());

      // Dismissed transitions back to idle but must NOT fire the funnel
      // event — `share_card_exported` is a confirmed-success-only signal.
      expect(container.read(shareControllerProvider), const ShareState.idle());
      expect(
        analyticsRepo.events,
        isEmpty,
        reason: 'dismissed share-sheet must not record share_card_exported',
      );
    },
  );

  test('sharePreview does NOT emit share_card_exported on share-sheet '
      'unavailable', () async {
    final analyticsRepo = _RecordingAnalyticsRepository();
    final container = makeContainer(
      service: buildService(
        fileShareSink: (_, {text}) async =>
            const ShareResult('na', ShareResultStatus.unavailable),
      ),
      renderer: buildRenderer(
        onRender: () async => _FakeXFile('/tmp/share.png'),
      ),
      analyticsRepo: analyticsRepo,
    );

    final notifier = container.read(shareControllerProvider.notifier);
    notifier.useDiscreet();

    await notifier.sharePreview(repaintKey: GlobalKey());

    // Unavailable transitions to error and must NOT record.
    expect(
      analyticsRepo.events,
      isEmpty,
      reason: 'unavailable share-sheet must not record share_card_exported',
    );
  });

  test(
    'sharePreview does NOT emit share_card_exported on renderer exception',
    () async {
      final analyticsRepo = _RecordingAnalyticsRepository();
      final container = makeContainer(
        service: buildService(),
        renderer: buildRenderer(
          onRender: () async => throw StateError('render blew up'),
        ),
        analyticsRepo: analyticsRepo,
      );

      final notifier = container.read(shareControllerProvider.notifier);
      notifier.useDiscreet();

      await notifier.sharePreview(repaintKey: GlobalKey());

      expect(analyticsRepo.events, isEmpty);
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
    notifier.useDiscreet();
    expect(container.read(shareControllerProvider), isA<ShareStatePreview>());

    notifier.reset();
    expect(container.read(shareControllerProvider), const ShareState.idle());
  });

  // ---------------------------------------------------------------------------
  // resetToPreview — PR 30b Blocker 2 (error retry path)
  // ---------------------------------------------------------------------------

  test('resetToPreview restores the preview state with the supplied photo', () {
    final container = makeContainer(
      service: buildService(),
      renderer: buildRenderer(),
    );
    final notifier = container.read(shareControllerProvider.notifier);
    notifier.state = const ShareState.error(code: ShareErrorCodes.renderFailed);

    final photo = _FakeXFile('/tmp/photo.jpg');
    notifier.resetToPreview(photo: photo);

    final s = container.read(shareControllerProvider);
    expect(s, isA<ShareStatePreview>());
    expect((s as ShareStatePreview).photo, photo);
  });

  test(
    'resetToPreview is idempotent — same photo, no spurious transitions',
    () {
      final container = makeContainer(
        service: buildService(),
        renderer: buildRenderer(),
      );
      final notifier = container.read(shareControllerProvider.notifier);
      final photo = _FakeXFile('/tmp/photo.jpg');

      notifier.resetToPreview(photo: photo);
      final after1 = container.read(shareControllerProvider);

      notifier.resetToPreview(photo: photo);
      final after2 = container.read(shareControllerProvider);

      // Equal values + no-op semantics. The state machine never emitted a
      // duplicate transition because the value comparison short-circuits.
      expect(after1, equals(after2));
      expect((after2 as ShareStatePreview).photo, photo);
    },
  );

  // ---------------------------------------------------------------------------
  // openAppSettings — PR 30b Blocker 2 (permanentlyDenied recovery path)
  // ---------------------------------------------------------------------------

  test('openAppSettings forwards into the ShareService DI seam', () async {
    var settingsCalls = 0;
    final container = makeContainer(
      service: ShareService(
        imagePicker: (_) async => null,
        fileShareSink: (_, {text}) async =>
            const ShareResult('ok', ShareResultStatus.success),
        permissionRequester: (_) async => PermissionStatus.granted,
        permissionStatusReader: (_) async => PermissionStatus.granted,
        appSettingsOpener: () async {
          settingsCalls += 1;
          return true;
        },
      ),
      renderer: buildRenderer(),
    );

    final ok = await container
        .read(shareControllerProvider.notifier)
        .openAppSettings();
    expect(settingsCalls, 1);
    expect(ok, isTrue);
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeXFile extends XFile {
  _FakeXFile(super.path);
}

/// Recording fake — captures every event the controller pushes through
/// [AnalyticsRepository.insertEvent] so tests can assert on the EXACT
/// payload (not just the call count). See
/// `feedback_test_user_visible_behavior` in MEMORY.md.
class _RecordingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    events.add(event);
  }
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
