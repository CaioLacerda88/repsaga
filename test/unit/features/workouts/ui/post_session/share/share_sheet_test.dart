import 'package:flutter/material.dart';
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
import 'package:repsaga/features/workouts/ui/post_session/share/share_localizations.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_sheet.dart';
import 'package:share_plus/share_plus.dart';

/// Pins [ShareSheet] row visibility + tap → controller-dispatch wiring.
///
/// Behavior assertions: presence/absence of rows + observable controller
/// state transitions after each tap (not "method X was called N times").
void main() {
  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  const fakeL10n = ShareLocalizations(
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

  ShareService buildService({
    Future<XFile?> Function(ImageSource source)? imagePicker,
    Future<PermissionStatus> Function(Permission)? permissionRequester,
  }) {
    return ShareService(
      imagePicker: imagePicker ?? (_) async => null,
      fileShareSink: (_, {text}) async =>
          const ShareResult('ok', ShareResultStatus.success),
      permissionRequester:
          permissionRequester ?? (_) async => PermissionStatus.granted,
      permissionStatusReader: (_) async => PermissionStatus.granted,
    );
  }

  Widget host({
    required SharePayload payload,
    required PermissionStatus cameraStatus,
    required ShareService service,
  }) {
    return ProviderScope(
      overrides: [
        shareServiceProvider.overrideWithValue(service),
        shareImageRendererProvider.overrideWithValue(_StubRenderer()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ShareSheet(
            payload: payload,
            l10n: fakeL10n,
            cameraStatus: cameraStatus,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Visibility
  // ---------------------------------------------------------------------------

  testWidgets('shows all three rows when camera permission is granted', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        payload: buildPayload(),
        cameraStatus: PermissionStatus.granted,
        service: buildService(),
      ),
    );

    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Escolher da galeria'), findsOneWidget);
    expect(find.text('Sem foto · só a saga'), findsOneWidget);
  });

  testWidgets('shows camera row when permission is denied (allows re-prompt)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        payload: buildPayload(),
        cameraStatus: PermissionStatus.denied,
        service: buildService(),
      ),
    );

    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Escolher da galeria'), findsOneWidget);
    expect(find.text('Sem foto · só a saga'), findsOneWidget);
  });

  testWidgets('hides camera row when permission is permanently denied — '
      'gallery + discreet remain', (tester) async {
    await tester.pumpWidget(
      host(
        payload: buildPayload(),
        cameraStatus: PermissionStatus.permanentlyDenied,
        service: buildService(),
      ),
    );

    expect(find.text('Tirar foto'), findsNothing);
    expect(find.text('Escolher da galeria'), findsOneWidget);
    expect(find.text('Sem foto · só a saga'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Tap dispatch (behavior — observable controller state)
  // ---------------------------------------------------------------------------

  testWidgets(
    'tapping the camera row dispatches pickFromCamera into the controller',
    (tester) async {
      final fakePhoto = _FakeXFile('/tmp/cam.jpg');
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(
            buildService(
              imagePicker: (_) async => fakePhoto,
              permissionRequester: (_) async => PermissionStatus.granted,
            ),
          ),
          shareImageRendererProvider.overrideWithValue(_StubRenderer()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ShareSheet(
                payload: buildPayload(),
                l10n: fakeL10n,
                cameraStatus: PermissionStatus.granted,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();

      final state = container.read(shareControllerProvider);
      expect(state, isA<ShareStatePreview>());
      expect((state as ShareStatePreview).photo, fakePhoto);
    },
  );

  testWidgets(
    'tapping the gallery row dispatches pickFromGallery into the controller',
    (tester) async {
      final fakePhoto = _FakeXFile('/tmp/lib.jpg');
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(
            buildService(imagePicker: (_) async => fakePhoto),
          ),
          shareImageRendererProvider.overrideWithValue(_StubRenderer()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ShareSheet(
                payload: buildPayload(),
                l10n: fakeL10n,
                cameraStatus: PermissionStatus.granted,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Escolher da galeria'));
      await tester.pumpAndSettle();

      final state = container.read(shareControllerProvider);
      expect(state, isA<ShareStatePreview>());
      expect((state as ShareStatePreview).photo, fakePhoto);
    },
  );

  testWidgets(
    'tapping the discreet row dispatches useDiscreet (preview with null photo)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          shareServiceProvider.overrideWithValue(buildService()),
          shareImageRendererProvider.overrideWithValue(_StubRenderer()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ShareSheet(
                payload: buildPayload(),
                l10n: fakeL10n,
                cameraStatus: PermissionStatus.granted,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Sem foto · só a saga'));
      await tester.pumpAndSettle();

      final state = container.read(shareControllerProvider);
      expect(state, isA<ShareStatePreview>());
      expect((state as ShareStatePreview).photo, isNull);
    },
  );

  testWidgets('carries a stable share-sheet semantics identifier', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        payload: buildPayload(),
        cameraStatus: PermissionStatus.granted,
        service: buildService(),
      ),
    );

    final semantics = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.identifier == 'share-sheet',
    );
    expect(semantics, findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeXFile extends XFile {
  _FakeXFile(super.path);
}

class _StubRenderer implements ShareImageRenderer {
  @override
  Future<XFile> render({
    required GlobalKey repaintKey,
    double pixelRatio = 3.0,
    int jpegQuality = 88,
  }) async {
    throw UnimplementedError('renderer not exercised in share-sheet tests');
  }
}
