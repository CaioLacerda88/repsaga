import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/saga_header.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child, {double width = 360}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('SagaHeader — three-column layout', () {
    testWidgets('renders rune + level numeral + class + title at 360dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: CharacterClass.bulwark,
            // Pass a real title slug from `earned_titles.title_id` — the
            // header MUST resolve it through `localizedTitleCopy(slug, l10n)`.
            // See `cluster_slug_rendered_as_display_name`.
            activeTitle: 'chest_r5_initiate_of_the_forge',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Level numeral
      expect(find.text('14'), findsOneWidget);
      // LVL tag below the numeral
      expect(find.text('LVL'), findsOneWidget);
      // Class label resolves via localizedClassName; pt locale → "Baluarte",
      // and Phase 26b mockup spec UPPERCASE-tracks earned class names so the
      // class label sits subordinate to the 56sp LVL numeral.
      expect(find.text('BALUARTE'), findsOneWidget);
      // Active title resolves to the pt-locale display name; the raw slug
      // must NOT appear on screen.
      expect(find.text('Iniciado da Forja'), findsOneWidget);
      expect(find.text('chest_r5_initiate_of_the_forge'), findsNothing);
    });

    testWidgets('right-meta column ellipsizes long titles at 360dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: null,
            activeTitle:
                'Extraordinarily Verbose Compound Title Of The First Sun',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The title widget renders within the meta column's 120dp clamp; the
      // ellipsis behavior is implicit if the rendered size doesn't blow up.
      final titleSize = tester.getSize(
        find.byKey(const ValueKey('saga-header-title')),
      );
      expect(
        titleSize.width,
        lessThanOrEqualTo(120),
        reason:
            'Meta column max is 120dp; the title row must clip via ellipsis.',
      );
    });

    testWidgets('omits the title row when activeTitle is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: null,
            activeTitle: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('saga-header-title')), findsNothing);
    });

    testWidgets('renders the day-1 placeholder when characterClass is null', (
      tester,
    ) async {
      // pt: "O ferro lhe dará um nome." (classSlotPlaceholder)
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 1,
            characterClass: null,
            activeTitle: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ferro'), findsOneWidget);
    });

    testWidgets('renders without overflow at 320dp viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: CharacterClass.bulwark,
            activeTitle: 'Plate-Bearer',
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final headerSize = tester.getSize(find.byType(SagaHeader));
      expect(
        headerSize.width,
        lessThanOrEqualTo(320),
        reason: 'Header must fit within a 320dp viewport without overflow.',
      );
    });
  });
}
