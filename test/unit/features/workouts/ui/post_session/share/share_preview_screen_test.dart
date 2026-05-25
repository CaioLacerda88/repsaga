import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/data/share_image_renderer.dart';
import 'package:repsaga/features/workouts/data/share_service.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/providers/share_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_renderer.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_localizations.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_preview_screen.dart';
import 'package:share_plus/share_plus.dart';

/// Pins [SharePreviewScreen]'s observable behavior:
///   * Variant toggle (A ↔ B) swaps the rendered variant subtree.
///   * Discreet path locks the variant — no toggle visible.
///   * Retake resets the controller + invokes onClose.
///   * Share dispatches sharePreview into the controller.
///   * Tap-to-hide XP / PR toggles affected strings (best-effort: assert
///     widget-tree visibility of the underlying renderer).
void main() {
  const strings = ShareCardStrings(
    wordmark: 'REPSAGA',
    variantAXpText: '+618 XP',
    variantAPrText: '95kg × 5 · PR',
    variantBBpEyebrow: 'Peito',
    variantBClassName: 'BULWARK',
    variantBPrTag: '!! Recorde',
    variantBLift: '95kg × 5',
    variantBBpSub: 'Supino · Peito',
    variantBXpSub: '+618 XP',
    discreetEyebrow: 'Peito · Rank 19',
    discreetHero: '+618',
    discreetHeroSubLabel: 'XP NESTA SAGA',
    discreetPrLine: '!! 95kg × 5',
    discreetPrDetail: 'Supino · novo recorde',
  );

  const l10n = ShareLocalizations(
    sheetTitle: 'Compartilhar saga',
    takePhoto: 'Tirar foto',
    fromGallery: 'Escolher da galeria',
    noPhoto: 'Sem foto · só a saga',
    previewMinimal: 'Mínimo',
    previewBold: 'Destaque',
    previewRetake: 'Refazer',
    previewShare: 'Compartilhar',
    wordmark: 'REPSAGA',
    permissionDenied: 'Permissão negada',
    permissionPermanentlyDenied: 'Permissão bloqueada',
    renderError: 'Erro ao gerar imagem',
    openSettings: 'Abrir configurações',
  );

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

  ShareService stubService() {
    return ShareService(
      imagePicker: (_) async => null,
      fileShareSink: (_, {text}) async =>
          const ShareResult('ok', ShareResultStatus.success),
      permissionRequester: (_) async => PermissionStatus.granted,
      permissionStatusReader: (_) async => PermissionStatus.granted,
    );
  }

  /// Builds the screen with the controller pre-seeded into a state. We use
  /// an `UncontrolledProviderScope` so the test can mutate / read the
  /// controller's state directly.
  Future<({ProviderContainer container, VoidCallback closeSpy})> pumpScreen(
    WidgetTester tester, {
    required SharePayload payload,
    required XFile? previewPhoto,
    _RecordingRenderer? renderer,
  }) async {
    final spy = _CloseSpy();
    final container = ProviderContainer(
      overrides: [
        shareServiceProvider.overrideWithValue(stubService()),
        shareImageRendererProvider.overrideWithValue(
          renderer ?? _RecordingRenderer(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Pre-seed the controller into the preview state so the screen
    // immediately renders its preview body.
    final notifier = container.read(shareControllerProvider.notifier);
    if (previewPhoto != null) {
      notifier.state = ShareState.preview(photo: previewPhoto);
    } else {
      notifier.useDiscreet();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharePreviewScreen(
            payload: payload,
            strings: strings,
            l10n: l10n,
            onClose: spy.call,
          ),
        ),
      ),
    );
    await tester.pump();
    return (container: container, closeSpy: spy.call);
  }

  // ---------------------------------------------------------------------------
  // Variant toggle
  // ---------------------------------------------------------------------------

  testWidgets('starts on minimalStrip variant when a photo is present', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    final renderer = tester.widget<ShareCardRenderer>(
      find.byType(ShareCardRenderer),
    );
    expect(renderer.variant, ShareCardVariant.minimalStrip);
    // Toggle chips visible.
    expect(find.text('MÍNIMO'), findsOneWidget);
    expect(find.text('DESTAQUE'), findsOneWidget);
  });

  testWidgets('tapping the Destaque chip switches to fullBleed variant', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    await tester.tap(find.text('DESTAQUE'));
    await tester.pump();

    final renderer = tester.widget<ShareCardRenderer>(
      find.byType(ShareCardRenderer),
    );
    expect(renderer.variant, ShareCardVariant.fullBleed);
  });

  testWidgets(
    'discreet path (null photo) locks the variant and hides the toggle',
    (tester) async {
      await pumpScreen(tester, payload: buildPayload(), previewPhoto: null);

      final renderer = tester.widget<ShareCardRenderer>(
        find.byType(ShareCardRenderer),
      );
      expect(renderer.variant, ShareCardVariant.discreet);
      expect(find.text('MÍNIMO'), findsNothing);
      expect(find.text('DESTAQUE'), findsNothing);
    },
  );

  // ---------------------------------------------------------------------------
  // Retake
  // ---------------------------------------------------------------------------

  testWidgets('tapping retake resets the controller and invokes onClose', (
    tester,
  ) async {
    var closed = 0;
    final container = ProviderContainer(
      overrides: [
        shareServiceProvider.overrideWithValue(stubService()),
        shareImageRendererProvider.overrideWithValue(_RecordingRenderer()),
      ],
    );
    addTearDown(container.dispose);
    container.read(shareControllerProvider.notifier).state = ShareState.preview(
      photo: _StubXFile('/tmp/photo.jpg'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharePreviewScreen(
            payload: buildPayload(),
            strings: strings,
            l10n: l10n,
            onClose: () => closed += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('REFAZER'));
    await tester.pump();

    expect(closed, 1);
    expect(container.read(shareControllerProvider), const ShareState.idle());
  });

  // ---------------------------------------------------------------------------
  // Share — dispatches sharePreview with the repaint key
  // ---------------------------------------------------------------------------

  testWidgets(
    'tapping share triggers controller.sharePreview with the repaint key',
    (tester) async {
      final renderer = _RecordingRenderer();
      final r = await pumpScreen(
        tester,
        payload: buildPayload(),
        previewPhoto: _StubXFile('/tmp/photo.jpg'),
        renderer: renderer,
      );

      await tester.tap(find.text('COMPARTILHAR'));
      // sharePreview is async — pump until it settles or transitions.
      await tester.pump();
      await tester.pump();

      // Renderer was invoked with a non-null key — observable side effect.
      expect(renderer.renderCalls, 1);
      expect(renderer.lastKey, isNotNull);
      // Controller has transitioned out of preview (rendering / sharing /
      // idle / error — any of these is "share button worked").
      final s = r.container.read(shareControllerProvider);
      expect(s, isNot(isA<ShareStatePreview>()));
    },
  );

  // ---------------------------------------------------------------------------
  // PR 30b Blocker 2 — render/share errors surface a snackbar and keep the
  // preview mounted so the user can retry. Pre-fix the screen called
  // widget.onClose() unconditionally and made the localized error copy dead
  // code.
  // ---------------------------------------------------------------------------

  testWidgets('share-button render failure shows snackbar with renderError '
      'copy and leaves the preview mounted', (tester) async {
    var closed = 0;
    final container = ProviderContainer(
      overrides: [
        shareServiceProvider.overrideWithValue(stubService()),
        shareImageRendererProvider.overrideWithValue(_ThrowingRenderer()),
      ],
    );
    addTearDown(container.dispose);

    final photo = _StubXFile('/tmp/photo.jpg');
    container.read(shareControllerProvider.notifier).state = ShareState.preview(
      photo: photo,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharePreviewScreen(
            payload: buildPayload(),
            strings: strings,
            l10n: l10n,
            onClose: () => closed += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('COMPARTILHAR'));
    // sharePreview is async — pump until it settles.
    await tester.pump();
    await tester.pump();

    // Snackbar copy is the localized renderError.
    expect(find.text('Erro ao gerar imagem'), findsOneWidget);
    // Preview screen is STILL mounted — onClose never fired.
    expect(closed, 0);
    expect(find.byType(SharePreviewScreen), findsOneWidget);
    // Controller reset back to preview with the same photo so the user
    // can retry.
    final post = container.read(shareControllerProvider);
    expect(post, isA<ShareStatePreview>());
    expect((post as ShareStatePreview).photo, photo);
  });

  testWidgets('share-button share failure shows the snackbar and leaves the '
      'preview mounted', (tester) async {
    var closed = 0;
    final container = ProviderContainer(
      overrides: [
        // Service returns "unavailable" => share_failed
        shareServiceProvider.overrideWithValue(
          ShareService(
            imagePicker: (_) async => null,
            fileShareSink: (_, {text}) async =>
                const ShareResult('na', ShareResultStatus.unavailable),
            permissionRequester: (_) async => PermissionStatus.granted,
            permissionStatusReader: (_) async => PermissionStatus.granted,
          ),
        ),
        shareImageRendererProvider.overrideWithValue(_RecordingRenderer()),
      ],
    );
    addTearDown(container.dispose);

    final photo = _StubXFile('/tmp/photo.jpg');
    container.read(shareControllerProvider.notifier).state = ShareState.preview(
      photo: photo,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharePreviewScreen(
            payload: buildPayload(),
            strings: strings,
            l10n: l10n,
            onClose: () => closed += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('COMPARTILHAR'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Erro ao gerar imagem'), findsOneWidget);
    expect(closed, 0);
    expect(find.byType(SharePreviewScreen), findsOneWidget);
  });

  testWidgets(
    'share-button cameraPermissionPermanentlyDenied surfaces snackbar with '
    'Abrir configurações action that calls controller.openAppSettings',
    (tester) async {
      // The `_surfaceError` switch branch for cameraPermissionPermanentlyDenied
      // is the only branch that wires a SnackBarAction with a non-null
      // callback. Production's `sharePreview()` itself never emits this
      // code (it lives on the camera-pick path), so we drive the branch
      // via a controller subclass that re-emits the permanentlyDenied
      // error when `sharePreview` is invoked. This pins the screen-layer
      // contract: matching localized copy + working "Abrir configurações"
      // affordance.
      var openSettingsCalls = 0;
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(
            ShareService(
              imagePicker: (_) async => null,
              fileShareSink: (_, {text}) async =>
                  const ShareResult('ok', ShareResultStatus.success),
              permissionRequester: (_) async => PermissionStatus.granted,
              permissionStatusReader: (_) async => PermissionStatus.granted,
              appSettingsOpener: () async {
                openSettingsCalls += 1;
                return true;
              },
            ),
          ),
          shareImageRendererProvider.overrideWithValue(_RecordingRenderer()),
          shareControllerProvider.overrideWith(
            _PermanentlyDeniedController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      // Pre-seed the controller into preview so the share button renders.
      final photo = _StubXFile('/tmp/photo.jpg');
      container.read(shareControllerProvider.notifier).state =
          ShareState.preview(photo: photo);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SharePreviewScreen(
              payload: buildPayload(),
              strings: strings,
              l10n: l10n,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('COMPARTILHAR'));
      // sharePreview is async — pump until it settles.
      await tester.pump();
      await tester.pump();

      // Snackbar copy is the permanentlyDenied localized message.
      expect(find.text('Permissão bloqueada'), findsOneWidget);
      // The SnackBarAction label is the openSettings localized copy.
      expect(find.text('Abrir configurações'), findsOneWidget);
      // Preview screen still mounted — the snackbar doesn't dismiss the
      // screen (matches the renderFailed / shareFailed branch contract).
      expect(find.byType(SharePreviewScreen), findsOneWidget);

      // Verify the SnackBarAction wires `onPressed` to a non-null
      // callback (the screen's `actionCallback ?? () {}` fallback would
      // silently no-op if `actionCallback` ever became null on the
      // permanentlyDenied branch — this pins it). Invoking
      // `onPressed` directly on the widget is the cleanest seam: the
      // default Material `SnackBar`'s floating bottom-margin positions
      // its action just outside the test viewport's hit-test bounds
      // (warning: "Offset would not hit test on the specified widget"
      // — independent of viewport size, since the snackbar pads itself
      // off the bottom edge). The InkWell-tap mechanics are Material's
      // responsibility; what matters here is that
      // `controller.openAppSettings` reaches the service seam.
      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      action.onPressed();
      // openAppSettings() is async — pump so the microtask drains
      // (controller method awaits the service's async closure).
      await tester.pump();
      await tester.pump();
      expect(openSettingsCalls, 1);
    },
  );

  testWidgets(
    'ShareController.openAppSettings routes through ShareService DI seam',
    (tester) async {
      // Cover the openSettings affordance contract: when the snackbar's
      // action calls controller.openAppSettings(), it forwards to the
      // service's appSettingsOpener seam. The on-screen snackbar wiring
      // for permanentlyDenied is exercised in the renderError + shareError
      // tests above (same _surfaceError code path); this test pins the
      // openAppSettings forwarding contract.
      var openSettingsCalls = 0;
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(
            ShareService(
              imagePicker: (_) async => null,
              fileShareSink: (_, {text}) async =>
                  const ShareResult('ok', ShareResultStatus.success),
              permissionRequester: (_) async => PermissionStatus.granted,
              permissionStatusReader: (_) async => PermissionStatus.granted,
              appSettingsOpener: () async {
                openSettingsCalls += 1;
                return true;
              },
            ),
          ),
          shareImageRendererProvider.overrideWithValue(_RecordingRenderer()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(shareControllerProvider.notifier).openAppSettings();
      expect(openSettingsCalls, 1);
    },
  );

  // ---------------------------------------------------------------------------
  // Tap-to-hide
  // ---------------------------------------------------------------------------

  testWidgets('tap-to-hide XP zone blanks the variant A XP text', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    // Sanity: XP text rendered initially.
    ShareCardRenderer rendered() =>
        tester.widget<ShareCardRenderer>(find.byType(ShareCardRenderer));
    expect(rendered().strings.variantAXpText, '+618 XP');

    // Tap inside the XP hit zone — bottom-strip Positioned overlay.
    // The XP overlay sits at `bottom: 0, height: 280` inside a
    // 1080×1920 stack — tap the bottom of the visible preview.
    final preview = find.byType(ShareCardRenderer);
    final rect = tester.getRect(preview);
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 12));
    await tester.pump();

    expect(rendered().strings.variantAXpText, '');
  });

  // ---------------------------------------------------------------------------
  // Drag-to-reframe — observable behavior: re-renders with new state
  // ---------------------------------------------------------------------------

  testWidgets(
    'vertical drag updates ShareCardRenderer.photoOffset (re-frame gesture)',
    (tester) async {
      await pumpScreen(
        tester,
        payload: buildPayload(),
        previewPhoto: _StubXFile('/tmp/photo.jpg'),
      );

      // The drag-to-reframe gesture flows the offset INTO the renderer
      // (PR 30b Important 3) so that only the photo subtree translates;
      // pre-fix the Transform sat ABOVE the renderer and shifted the
      // overlay too. Probe the renderer's photoOffset prop directly.
      Offset rendererPhotoOffset() {
        return tester
            .widget<ShareCardRenderer>(find.byType(ShareCardRenderer))
            .photoOffset;
      }

      final before = rendererPhotoOffset();
      await tester.drag(find.byType(ShareCardRenderer), const Offset(0, 200));
      await tester.pump();
      final after = rendererPhotoOffset();

      expect(after, isNot(before));
      // Drag down -> positive dy on the photo translation.
      expect(after.dy, greaterThan(before.dy));
    },
  );

  // ---------------------------------------------------------------------------
  // Semantics identifier
  // ---------------------------------------------------------------------------

  testWidgets('carries a stable share-preview-screen semantics identifier', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    final semantics = find.byWidgetPredicate(
      (w) =>
          w is Semantics && w.properties.identifier == 'share-preview-screen',
    );
    expect(semantics, findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Helpers + fakes
// ---------------------------------------------------------------------------

class _StubXFile extends XFile {
  _StubXFile(super.path);
}

class _CloseSpy {
  int _count = 0;
  void call() => _count += 1;
  // ignore: unused_element
  int get count => _count;
}

class _RecordingRenderer implements ShareImageRenderer {
  int renderCalls = 0;
  GlobalKey? lastKey;

  @override
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    int jpegQuality = 88,
  }) async {
    renderCalls += 1;
    lastKey = repaintKey;
    return _StubXFile('/tmp/share_card.png');
  }
}

/// Renderer that always throws — drives the [ShareErrorCodes.renderFailed]
/// path through the controller. Used to verify the preview-screen error
/// surface (PR 30b Blocker 2).
class _ThrowingRenderer implements ShareImageRenderer {
  @override
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    int jpegQuality = 88,
  }) async {
    throw StateError('render failed');
  }
}

/// Controller subclass that overrides `sharePreview` to emit the
/// [ShareErrorCodes.cameraPermissionPermanentlyDenied] error code on
/// every invocation. Production's real `sharePreview` only ever emits
/// `renderFailed` / `shareFailed`; the permanentlyDenied code lives on
/// the camera-pick path. This fake unlocks driving the screen-layer
/// `_surfaceError` permanentlyDenied branch (the only branch that
/// wires a SnackBarAction with a non-null callback) through the
/// preview screen's share-button flow. `openAppSettings()` is
/// inherited so it still forwards to the injected ShareService seam.
class _PermanentlyDeniedController extends ShareController {
  @override
  Future<void> sharePreview({
    required GlobalKey repaintKey,
    String? shareText,
  }) async {
    state = const ShareState.error(
      code: ShareErrorCodes.cameraPermissionPermanentlyDenied,
    );
  }
}
