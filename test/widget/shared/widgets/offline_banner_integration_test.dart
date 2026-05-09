import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/shared/widgets/offline_banner.dart';
import '../../../helpers/test_material_app.dart';

/// Tests the wiring between [isOnlineProvider] and [OfflineBanner].
///
/// The unit tests in test/unit/core/connectivity/ verify the merge logic
/// of [onlineStatusProvider]. This widget test verifies the layer that the
/// unit tests do NOT cover: that the shell-level conditional
/// `if (!isOnline) const OfflineBanner()` correctly surfaces and hides the
/// banner when [isOnlineProvider] changes.
///
/// We pump a minimal [ConsumerWidget] that replicates the production pattern
/// (watch [isOnlineProvider], render [OfflineBanner] when false) to avoid
/// booting GoRouter and every shell provider. The test focus is the
/// provider-to-widget wiring, not the app_router.dart shell itself.
class _BannerHarness extends ConsumerWidget {
  const _BannerHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    return Scaffold(
      body: Column(
        children: [
          if (!isOnline) const OfflineBanner(),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}

void main() {
  group(
    'OfflineBanner — provider wiring (isOnlineProvider → banner visibility)',
    () {
      testWidgets(
        'OfflineBanner is hidden when isOnlineProvider is true (online)',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [isOnlineProvider.overrideWithValue(true)],
              child: const TestMaterialApp(home: _BannerHarness()),
            ),
          );

          expect(find.byType(OfflineBanner), findsNothing);
        },
      );

      testWidgets(
        'OfflineBanner is visible when isOnlineProvider is false (offline)',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [isOnlineProvider.overrideWithValue(false)],
              child: const TestMaterialApp(home: _BannerHarness()),
            ),
          );

          expect(find.byType(OfflineBanner), findsOneWidget);
        },
      );

      testWidgets(
        'OfflineBanner disappears when isOnlineProvider transitions from false to true',
        (tester) async {
          // Start offline.
          final container = ProviderContainer(
            overrides: [isOnlineProvider.overrideWithValue(false)],
          );
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const TestMaterialApp(home: _BannerHarness()),
            ),
          );

          expect(find.byType(OfflineBanner), findsOneWidget);

          // Go online — update the override value.
          container.updateOverrides([isOnlineProvider.overrideWithValue(true)]);
          await tester.pump();

          expect(find.byType(OfflineBanner), findsNothing);
        },
      );

      testWidgets(
        'OfflineBanner appears when isOnlineProvider transitions from true to false',
        (tester) async {
          // Start online.
          final container = ProviderContainer(
            overrides: [isOnlineProvider.overrideWithValue(true)],
          );
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const TestMaterialApp(home: _BannerHarness()),
            ),
          );

          expect(find.byType(OfflineBanner), findsNothing);

          // Go offline.
          container.updateOverrides([
            isOnlineProvider.overrideWithValue(false),
          ]);
          await tester.pump();

          expect(find.byType(OfflineBanner), findsOneWidget);
        },
      );

      testWidgets(
        'OfflineBanner Semantics identifier is offline-banner when visible',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [isOnlineProvider.overrideWithValue(false)],
              child: const TestMaterialApp(home: _BannerHarness()),
            ),
          );

          // Confirm the Semantics identifier matches the E2E selector
          // OFFLINE.banner = '[flt-semantics-identifier="offline-banner"]'.
          final semanticsNode = tester.getSemantics(find.byType(OfflineBanner));
          expect(semanticsNode.identifier, equals('offline-banner'));
        },
      );
    },
  );
}
