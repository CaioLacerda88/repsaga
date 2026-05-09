import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';

/// Tests the web-side seam: when the browser emits `online`/`offline`
/// DOM events, [onlineStatusProvider] must reflect those changes — not
/// just `connectivity_plus`'s OS-level adapter events.
///
/// The seam is [webOnlineEventsProvider] (a [Provider] that exposes a
/// `Stream<bool>` of browser online/offline events). Native builds resolve
/// it to an empty stream via conditional import; web builds resolve it to
/// a real DOM-event subscription. Tests inject a [StreamController] so we
/// can drive the merge logic deterministically without booting a browser.
///
/// The native [connectivity_plus] side is also overridden via
/// [nativeOnlineEventsProvider] so we can assert the merge in isolation
/// from real platform channels.
void main() {
  group('onlineStatusProvider — merged native + web sources', () {
    late StreamController<bool> webEvents;
    late StreamController<bool> nativeEvents;

    setUp(() {
      webEvents = StreamController<bool>.broadcast();
      nativeEvents = StreamController<bool>.broadcast();
    });

    tearDown(() async {
      await webEvents.close();
      await nativeEvents.close();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          webOnlineEventsProvider.overrideWith((ref) => webEvents.stream),
          nativeOnlineEventsProvider.overrideWith((ref) => nativeEvents.stream),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'browser offline event drives onlineStatusProvider to false',
      () async {
        final container = makeContainer();
        // Subscribe so the StreamProvider becomes active and starts merging.
        final sub = container.listen<AsyncValue<bool>>(
          onlineStatusProvider,
          (_, _) {},
        );
        addTearDown(sub.close);

        // Native says online (initial).
        nativeEvents.add(true);
        // Allow stream microtasks to flush.
        await Future<void>.delayed(Duration.zero);
        expect(container.read(onlineStatusProvider).value, isTrue);

        // Browser fires `offline` event — the user IS offline regardless
        // of what the OS adapter reports (CDP setOffline scenario).
        webEvents.add(false);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(onlineStatusProvider).value, isFalse);
      },
    );

    test('browser online event drives onlineStatusProvider to true', () async {
      final container = makeContainer();
      final sub = container.listen<AsyncValue<bool>>(
        onlineStatusProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      // Browser fires offline first.
      webEvents.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onlineStatusProvider).value, isFalse);

      // Browser fires online — provider must recover.
      webEvents.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onlineStatusProvider).value, isTrue);
    });

    test('native connectivity_plus stream still drives onlineStatusProvider '
        '(native path preserved)', () async {
      final container = makeContainer();
      final sub = container.listen<AsyncValue<bool>>(
        onlineStatusProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      nativeEvents.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onlineStatusProvider).value, isTrue);

      nativeEvents.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onlineStatusProvider).value, isFalse);

      nativeEvents.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onlineStatusProvider).value, isTrue);
    });

    test(
      'last-wins merge: most recent emission from either source dictates state',
      () async {
        final container = makeContainer();
        final sub = container.listen<AsyncValue<bool>>(
          onlineStatusProvider,
          (_, _) {},
        );
        addTearDown(sub.close);

        // Native online, then browser fires offline → offline wins.
        nativeEvents.add(true);
        await Future<void>.delayed(Duration.zero);
        webEvents.add(false);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(onlineStatusProvider).value, isFalse);

        // Native re-asserts online → most recent wins → online.
        nativeEvents.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(onlineStatusProvider).value, isTrue);
      },
    );

    test(
      'native-only path (web stream silent) behaves like single-source',
      () async {
        // Simulates the native build where webOnlineEventsProvider is the
        // empty stream — onlineStatusProvider must still emit based on
        // connectivity_plus alone.
        final container = ProviderContainer(
          overrides: [
            webOnlineEventsProvider.overrideWith(
              (ref) => const Stream<bool>.empty(),
            ),
            nativeOnlineEventsProvider.overrideWith(
              (ref) => nativeEvents.stream,
            ),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen<AsyncValue<bool>>(
          onlineStatusProvider,
          (_, _) {},
        );
        addTearDown(sub.close);

        nativeEvents.add(false);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(onlineStatusProvider).value, isFalse);

        nativeEvents.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(onlineStatusProvider).value, isTrue);
      },
    );
  });
}
