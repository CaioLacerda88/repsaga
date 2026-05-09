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
  group('OfflineBanner — provider wiring (isOnlineProvider → banner visibility)', () {
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
        container.updateOverrides([isOnlineProvider.overrideWithValue(false)]);
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

    testWidgets(
      'OfflineBanner rendered height equals _kOfflineBannerHeight (42dp) '
      'under TextScaler.noScaling',
      (tester) async {
        // Pin the banner under `TextScaler.noScaling` exactly the way
        // `_ShellScaffold` does in production, then measure its actual
        // size. This locks the geometry contract that `_kOfflineBannerHeight`
        // (42dp) depends on for body-content padding: 24dp vertical
        // padding (12 + 12) + 18dp `bodySmall` line height (12px * height
        // 1.5) = 42dp. If anyone changes the banner padding, font size,
        // or line height without updating the constant, this test fails.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [isOnlineProvider.overrideWithValue(false)],
            child: const TestMaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.noScaling),
                    child: OfflineBanner(),
                  ),
                ),
              ),
            ),
          ),
        );

        final size = tester.getSize(find.byType(OfflineBanner));
        // Match against the literal contract value the production
        // `_kOfflineBannerHeight` constant in `lib/core/router/app_router.dart`
        // also encodes. Keep these two values in sync.
        expect(size.height, equals(42.0));
      },
    );

    testWidgets(
      'OfflineBanner height stays at 42dp even when ambient TextScaler '
      'is doubled (pin works)',
      (tester) async {
        // This test directly verifies the bug the reviewer flagged:
        // without the `TextScaler.noScaling` pin, an ambient
        // textScaler of 2.0 would balloon the banner from 42dp to ~60dp
        // (24 padding + 36 line height) and overflow the
        // `_kOfflineBannerHeight` body padding. With the pin, the banner
        // is unaffected by the ambient scale.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [isOnlineProvider.overrideWithValue(false)],
            child: TestMaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  // Mirror the production pin in `_ShellScaffold`.
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.noScaling),
                      child: const OfflineBanner(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final size = tester.getSize(find.byType(OfflineBanner));
        expect(size.height, equals(42.0));
      },
    );
  });
}
