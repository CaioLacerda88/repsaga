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
