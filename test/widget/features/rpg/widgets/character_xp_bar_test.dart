import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/character_xp_bar.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('CharacterXpBar', () {
    testWidgets('renders the label in pt-BR with thousand separator + LVL', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CharacterXpBar(
            lifetimeXp: 8420,
            xpForNextLevel: 12000,
            characterLevel: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('8.420 XP'), findsOneWidget);
      expect(find.textContaining('3.580 para LVL 15'), findsOneWidget);
    });

    testWidgets('full bar when lifetimeXp == xpForNextLevel (maxed-out)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CharacterXpBar(
            lifetimeXp: 10000,
            xpForNextLevel: 10000,
            characterLevel: 99,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('0 para LVL 100'), findsOneWidget);
    });

    testWidgets('empty bar when lifetimeXp == 0 (day-zero)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CharacterXpBar(
            lifetimeXp: 0,
            xpForNextLevel: 400,
            characterLevel: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('0 XP'), findsOneWidget);
      expect(find.textContaining('400 para LVL 2'), findsOneWidget);
    });

    testWidgets('bar fill respects fraction within [0, 1]', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CharacterXpBar(
            lifetimeXp: 8420,
            xpForNextLevel: 12000,
            characterLevel: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fill = tester.widget<FractionallySizedBox>(
        find.byKey(const ValueKey('character-xp-bar-fill')),
      );
      // 8420 / 12000 = 0.7016...
      expect(fill.widthFactor, closeTo(0.7016, 0.001));
    });
  });
}
