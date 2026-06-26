import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_clean_flex.dart';

/// Pins the Phase 39 Clean Flex (stats) overlay. Behavior, not wiring:
/// asserts the PR-hero + the four-stat strip the user reads on the card.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.abyss,
        body: SizedBox(width: 1080, height: 1920, child: child),
      ),
    );
  }

  testWidgets('renders the PR hero + four-stat strip', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardCleanFlex(
          eyebrow: 'Bulwark',
          heroValue: '130',
          heroUnit: ' kg × 3',
          heroContext: 'Supino',
          wordmark: 'REPSAGA',
          stats: [
            CleanFlexStat(value: '+618', label: 'XP'),
            CleanFlexStat(value: '8,4 t', label: 'TON'),
            CleanFlexStat(value: '24', label: 'SÉRIES'),
            CleanFlexStat(value: '47 min', label: 'DUR'),
          ],
        ),
      ),
    );

    // The PR hero composes the value + the demoted unit.
    final hero = tester.widget<Text>(
      find.byKey(const ValueKey('share-card-clean-flex-hero')),
    );
    final heroText = hero.textSpan!.toPlainText();
    expect(heroText, contains('130'));
    expect(heroText, contains('kg × 3'));

    // The hero context line renders.
    expect(find.text('Supino'), findsOneWidget);

    // All four stat values + keys are present.
    expect(find.text('+618'), findsOneWidget);
    expect(find.text('8,4 t'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('47 min'), findsOneWidget);
    expect(find.text('XP'), findsOneWidget);
    expect(find.text('TON'), findsOneWidget);
    expect(find.text('SÉRIES'), findsOneWidget);
    expect(find.text('DUR'), findsOneWidget);
  });

  testWidgets('hero context line collapses when null', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardCleanFlex(
          eyebrow: 'Bulwark',
          heroValue: '+540',
          wordmark: 'REPSAGA',
          stats: [
            CleanFlexStat(value: '+540', label: 'XP'),
            CleanFlexStat(value: '7,1 t', label: 'TON'),
            CleanFlexStat(value: '18', label: 'SÉRIES'),
            CleanFlexStat(value: '33 min', label: 'DUR'),
          ],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('share-card-clean-flex-context')),
      findsNothing,
    );
  });
}
