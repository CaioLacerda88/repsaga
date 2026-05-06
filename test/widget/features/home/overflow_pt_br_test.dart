/// Overflow regression test for the bottom navigation bar at a 320dp wide
/// viewport rendered in Portuguese (pt).
///
/// The pt labels (`Início`, `Exercícios`, `Treinos`, `Perfil`) are the longest
/// we currently ship. Phase 15e adds this as a safety net so future label
/// changes or style tweaks cannot silently regress the critical bottom nav.
///
/// We pump a minimal replica of the app's `NavigationBar` (same destinations,
/// same `AppLocalizations` keys) inside a 320 x 640 logical-pixel viewport with
/// `Locale('pt')` and assert that no `RenderFlex` overflow exception was thrown
/// AND that each label is visible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/l10n/app_localizations.dart';

import '../../../helpers/test_material_app.dart';

/// Minimal replica of `_ShellScaffold`'s bottom navigation. We can't import
/// the private shell directly, so we mirror its structure (same labels,
/// identical NavigationBar + NavigationDestination composition).
class _ShellNavReplica extends StatelessWidget {
  const _ShellNavReplica();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home),
            label: l10n.navHome,
            tooltip: '',
          ),
          NavigationDestination(
            icon: const Icon(Icons.fitness_center),
            label: l10n.navExercises,
            tooltip: '',
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_today),
            label: l10n.navRoutines,
            tooltip: '',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person),
            label: l10n.navProfile,
            tooltip: '',
          ),
        ],
      ),
    );
  }
}

void main() {
  group('Bottom nav overflow at 320dp pt-BR', () {
    testWidgets('does not overflow and renders all four labels', (
      tester,
    ) async {
      // 320 logical pixels is the narrowest realistic phone width (small
      // Androids, iPhone SE 1st gen). Pair with devicePixelRatio 1.0 so
      // logical and physical pixels match for predictable layout.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const TestMaterialApp(locale: Locale('pt'), home: _ShellNavReplica()),
      );
      await tester.pumpAndSettle();

      // No overflow exceptions were captured during layout/paint.
      expect(tester.takeException(), isNull);

      // All four localized labels are present and on-screen.
      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Exercícios'), findsOneWidget);
      expect(find.text('Treinos'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);
    });

    testWidgets('also holds at 360dp pt-BR', (tester) async {
      // 360dp is the most common Android phone width (Pixel, Galaxy S series).
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const TestMaterialApp(locale: Locale('pt'), home: _ShellNavReplica()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Exercícios'), findsOneWidget);
      expect(find.text('Treinos'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);
    });
  });
}
