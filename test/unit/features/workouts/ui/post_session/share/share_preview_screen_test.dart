import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
///   * D3 Achievement Frame is the single photo overlay; Discreet renders
///     on the no-photo path (Phase 31 retired the A ↔ B segmented toggle).
///   * Retake resets the controller + invokes onClose.
///   * Share dispatches sharePreview into the controller.
///   * Tap-to-hide XP / PR toggles affected strings (best-effort: assert
///     widget-tree visibility of the underlying renderer).
///
/// **Two ShareCardRenderer instances per screen** (PR 30c device bug 3):
/// the screen mounts BOTH a visible preview tree (`renderTarget: preview`)
/// and an offscreen export tree (`renderTarget: export`, positioned at
/// `left: -10000`). Tests probing widget state therefore disambiguate by
/// `renderTarget` — see [visibleRenderer] / [exportRenderer] below.
ShareCardRenderer visibleRenderer(WidgetTester tester) {
  return tester
      .widgetList<ShareCardRenderer>(find.byType(ShareCardRenderer))
      .firstWhere((r) => r.renderTarget == ShareCardRenderTarget.preview);
}

ShareCardRenderer exportRenderer(WidgetTester tester) {
  return tester
      .widgetList<ShareCardRenderer>(find.byType(ShareCardRenderer))
      .firstWhere((r) => r.renderTarget == ShareCardRenderTarget.export);
}

void main() {
  const strings = ShareCardStrings(
    wordmark: 'REPSAGA',
    achievementFrameClassName: 'BULWARK',
    achievementFrameSagaEyebrow: 'SAGA 76',
    achievementFrameXpHero: '+618 XP',
    achievementFrameLiftDetail: '95kg × 5 · Supino',
    achievementFrameHasPr: true,
    achievementFrameBpRank: 'Peito · Rank 19',
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
  // Variant selection — Phase 31: D3 Achievement Frame is the single
  // photo overlay; Discreet renders on the no-photo path. No A ↔ B toggle.
  // ---------------------------------------------------------------------------

  testWidgets('renders D3 Achievement Frame variant when a photo is present', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    expect(visibleRenderer(tester).variant, ShareCardVariant.achievementFrame);
    // No toggle UI on the photo path post-Phase-31.
    expect(find.text('MÍNIMO'), findsNothing);
    expect(find.text('DESTAQUE'), findsNothing);
  });

  testWidgets('discreet path (null photo) renders the Discreet variant', (
    tester,
  ) async {
    await pumpScreen(tester, payload: buildPayload(), previewPhoto: null);

    expect(visibleRenderer(tester).variant, ShareCardVariant.discreet);
    // Same no-toggle invariant.
    expect(find.text('MÍNIMO'), findsNothing);
    expect(find.text('DESTAQUE'), findsNothing);
  });

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

  testWidgets('tap-to-hide XP zone blanks the Achievement Frame XP hero text', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    // Sanity: XP text rendered initially on the visible preview tree.
    expect(visibleRenderer(tester).strings.achievementFrameXpHero, '+618 XP');

    // Tap inside the XP hit zone — bottom Positioned overlay over the
    // bottom 280px of the card. The offscreen export renderer (at
    // `left: -10000`) sits outside the viewport so taps land on the
    // visible one only.
    final visible = find.byWidgetPredicate(
      (w) =>
          w is ShareCardRenderer &&
          w.renderTarget == ShareCardRenderTarget.preview,
    );
    final rect = tester.getRect(visible);
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 12));
    await tester.pump();

    // Both renderers share the same `strings` reference, so checking
    // either one reflects the tap-to-hide state. We probe the visible
    // one for consistency with the rest of the suite.
    expect(visibleRenderer(tester).strings.achievementFrameXpHero, '');
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
      // overlay too. Probe the visible renderer's photoOffset prop
      // directly (post-PR-30c there's also an offscreen export renderer
      // — both receive the same offset value so either probe works, but
      // we use the visible one for consistency).
      Offset rendererPhotoOffset() => visibleRenderer(tester).photoOffset;

      final before = rendererPhotoOffset();
      final visible = find.byWidgetPredicate(
        (w) =>
            w is ShareCardRenderer &&
            w.renderTarget == ShareCardRenderTarget.preview,
      );
      await tester.drag(visible, const Offset(0, 200));
      await tester.pump();
      final after = rendererPhotoOffset();

      expect(after, isNot(before));
      // Drag down -> positive dy on the photo translation.
      expect(after.dy, greaterThan(before.dy));
    },
  );

  // ---------------------------------------------------------------------------
  // PR 30c device bug 2 — ClipRect contains the drag-to-reframe overflow
  //
  // Pre-fix: drag-to-reframe applied a Transform.translate to the photo
  // subtree. The card's AspectRatio host had no clipping ancestor, so the
  // translated pixels could overflow the 9:16 outer bounds and paint
  // outside the card frame. On a real device the user saw the photo
  // creeping out of the card during an upward drag.
  //
  // Post-fix: a ClipRect wraps the AspectRatio. The card's outer paint
  // bounds clamp to the AspectRatio's bounds regardless of the inner
  // Transform.
  // ---------------------------------------------------------------------------
  testWidgets('photo cannot paint outside the card frame after max upward drag '
      '(ClipRect contract — PR 30c device bug 2)', (tester) async {
    await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
    );

    // Drive the drag past the natural reframe band. The clamp inside
    // the screen caps _photoAlignmentY at -1.0 (yielding photoOffset.dy
    // = -80 in renderer units), but the gesture itself fires deltas
    // far beyond that. The ClipRect must hold the visible paint bounds
    // inside the AspectRatio regardless of how aggressive the drag is.
    final visibleCard = find.byWidgetPredicate(
      (w) =>
          w is ShareCardRenderer &&
          w.renderTarget == ShareCardRenderTarget.preview,
    );
    await tester.drag(visibleCard, const Offset(0, -2000));
    await tester.pump();

    // The screen-layer ClipRect sits between Center and AspectRatio
    // (outer card frame). The renderer also has its own AspectRatio
    // descendant, so two AspectRatio widgets exist under the ClipRect —
    // we want the outer one (the direct child of the ClipRect).
    final clipRectFinder = find.descendant(
      of: find.byType(SharePreviewScreen),
      matching: find.byType(ClipRect),
    );
    expect(
      clipRectFinder,
      findsOneWidget,
      reason:
          'AspectRatio must be wrapped in a ClipRect '
          '(PR 30c device bug 2 fix)',
    );

    // The outer AspectRatio is the first AspectRatio descendant of the
    // ClipRect.
    final outerAspectRatio = find
        .descendant(of: clipRectFinder, matching: find.byType(AspectRatio))
        .first;
    final aspectRect = tester.getRect(outerAspectRatio);
    final clipRect = tester.getRect(clipRectFinder);
    expect(
      clipRect,
      aspectRect,
      reason:
          'ClipRect bounds must equal the AspectRatio bounds — '
          'photo overflow cannot escape the card frame',
    );
  });

  // ---------------------------------------------------------------------------
  // PR 30c device bug 3 — offscreen export tree stays mounted across the
  // rendering / sharing state transitions so RenderRepaintBoundary.toImage
  // can capture a still-painted boundary.
  //
  // Pre-fix: the screen returned a CircularProgressIndicator-only body
  // when state transitioned to ShareStateRendering. The next frame
  // unmounted the (visible) RepaintBoundary while toImage was mid-flight,
  // throwing on a disposed layer and surfacing the "Couldn't render the
  // saga card" snackbar to the user.
  //
  // Post-fix: the screen ALWAYS mounts the same body tree across
  // preview / rendering / sharing — an offscreen export tree at
  // `Positioned(left: -10000)` and a visible preview tree side-by-side
  // inside a Stack. Busy states just overlay a barrier + spinner on top.
  // ---------------------------------------------------------------------------

  testWidgets(
    'mounts both visible preview and offscreen export ShareCardRenderer '
    'in preview state (device bug 3 dual-tree setup)',
    (tester) async {
      await pumpScreen(
        tester,
        payload: buildPayload(),
        previewPhoto: _StubXFile('/tmp/photo.jpg'),
      );

      // Both renderers are present.
      expect(find.byType(ShareCardRenderer), findsNWidgets(2));
      expect(
        visibleRenderer(tester).renderTarget,
        ShareCardRenderTarget.preview,
      );
      expect(exportRenderer(tester).renderTarget, ShareCardRenderTarget.export);
    },
  );

  testWidgets('offscreen export tree stays mounted across the rendering state '
      'transition so toImage captures a painted boundary (device bug 3 fix)', (
    tester,
  ) async {
    final renderer = _RecordingRenderer();
    final container = ProviderContainer(
      overrides: [
        shareServiceProvider.overrideWithValue(stubService()),
        shareImageRendererProvider.overrideWithValue(renderer),
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
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Sanity: both trees mounted before the share tap.
    expect(find.byType(ShareCardRenderer), findsNWidgets(2));

    // Manually transition the controller into rendering (the share
    // tap is async; we simulate the intermediate frame the bug
    // reproduced on).
    container.read(shareControllerProvider.notifier).state =
        const ShareState.rendering();
    await tester.pump();

    // Post-fix invariant: the export tree IS still mounted while the
    // controller is in the rendering state. Pre-fix the body
    // returned only a CircularProgressIndicator and both renderers
    // were gone — toImage would race against a disposed boundary.
    expect(find.byType(ShareCardRenderer), findsNWidgets(2));
    expect(exportRenderer(tester).renderTarget, ShareCardRenderTarget.export);

    // The busy barrier is visible — observable user-facing affordance.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('sharePreview passes the offscreen export RepaintBoundary key '
      '(NOT the visible preview tree) — device bug 3 contract', (tester) async {
    final renderer = _RecordingRenderer();
    final r = await pumpScreen(
      tester,
      payload: buildPayload(),
      previewPhoto: _StubXFile('/tmp/photo.jpg'),
      renderer: renderer,
    );

    await tester.tap(find.text('COMPARTILHAR'));
    await tester.pump();
    await tester.pump();

    // The renderer was called with the offscreen export tree's
    // GlobalKey. We assert the captured key points at a
    // RepaintBoundary that's currently a RenderRepaintBoundary in the
    // tree — proving the export boundary is mounted at the moment
    // toImage would normally be called.
    expect(renderer.lastKey, isNotNull);
    // The key's currentContext resolves to a real element, and that
    // element's render object is a RepaintBoundary.
    final ctx = renderer.lastKey!.currentContext;
    // After the share completes the screen would call onClose, but
    // the _RecordingRenderer returns synchronously without an XFile
    // disposal step — the screen has already advanced through the
    // success branch. We use the captured key to assert the boundary
    // shape mattered at the moment the share button fired.
    // Defensive: skip the assertion if the screen has already torn
    // down (idle state).
    if (ctx != null) {
      expect(ctx.findRenderObject(), isA<RenderRepaintBoundary>());
    }

    // The container's lastKey doesn't directly tell us which tree it
    // was — but the screen only EVER passes the offscreen key. We
    // assert it by checking renderer.lastKey is exactly the global
    // key the screen attached to the offscreen RepaintBoundary. We
    // can't access the State's private field directly, so we verify
    // a weaker invariant: the captured key is NOT a placeholder
    // empty GlobalKey() and HAS a debug label matching the export
    // key (which is set with `debugLabel: 'share-preview-export-repaint'`
    // in the State).
    expect(
      renderer.lastKey.toString(),
      contains('share-preview-export-repaint'),
      reason:
          'sharePreview must use the offscreen export tree key, '
          'not the visible preview tree key',
    );
    // Suppress the unused `r` lint — keeps the helper signature in line
    // with other share tests that DO assert on the returned record.
    addTearDown(() {
      r.container; // touch
    });
  });

  // ---------------------------------------------------------------------------
  // Defensive mount — non-preview states at mount time
  //
  // PR 30b Suggestion 7: when the screen is mounted with an unexpected state
  // (ShareStateError / ShareStateCancelled / ShareStateIdle) the build()
  // defensive branch renders an empty scaffold + fires debugPrint. The
  // screen must not crash — the scaffold must be present and onClose must
  // NOT have been called (no auto-pop from a stray state transition).
  // ---------------------------------------------------------------------------

  testWidgets(
    'mounts without crashing when initial controller state is ShareStateError',
    (tester) async {
      var closeCalls = 0;
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(stubService()),
          shareImageRendererProvider.overrideWithValue(_RecordingRenderer()),
        ],
      );
      addTearDown(container.dispose);

      // Seed the controller into an error state — simulates the edge case
      // where the caller opens the preview screen after a stale error in
      // the pipeline (e.g. camera permission was denied before the sheet
      // even opened, state never transitioned to preview).
      container.read(shareControllerProvider.notifier).state =
          const ShareState.error(code: ShareErrorCodes.renderFailed);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SharePreviewScreen(
              payload: buildPayload(),
              strings: strings,
              l10n: l10n,
              onClose: () => closeCalls += 1,
            ),
          ),
        ),
      );
      await tester.pump();

      // Screen mounts — Scaffold is present, no exception thrown.
      expect(find.byType(SharePreviewScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      // The defensive branch must NOT auto-pop (onClose is the only legal
      // caller of the pop path — initiating it here would skip user intent).
      expect(closeCalls, 0);
      // The preview body (variant toggle, retake, share) must be absent:
      // the defensive SizedBox.shrink renders nothing interactive.
      expect(find.text('REFAZER'), findsNothing);
      expect(find.text('COMPARTILHAR'), findsNothing);
    },
  );

  testWidgets(
    'mounts without crashing when initial controller state is ShareStateCancelled',
    (tester) async {
      var closeCalls = 0;
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(stubService()),
          shareImageRendererProvider.overrideWithValue(_RecordingRenderer()),
        ],
      );
      addTearDown(container.dispose);

      container.read(shareControllerProvider.notifier).state =
          const ShareState.cancelled();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SharePreviewScreen(
              payload: buildPayload(),
              strings: strings,
              l10n: l10n,
              onClose: () => closeCalls += 1,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SharePreviewScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(closeCalls, 0);
      expect(find.text('REFAZER'), findsNothing);
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
