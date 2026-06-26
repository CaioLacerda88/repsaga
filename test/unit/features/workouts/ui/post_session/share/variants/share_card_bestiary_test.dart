import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/beast_card.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_typography.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_bestiary.dart';

/// Pins the Phase 39 Bestiary-mode overlay. Behavior, not wiring: every
/// assertion checks a rendered Text / color the user actually sees on the
/// §7 bottom block (name, rank/XP/tonnage, phrase, boss eyebrow + sigil,
/// chimera multi-hue rail).
void main() {
  BeastCard beast({
    BodyPart line = BodyPart.chest,
    BeastTier tier = BeastTier.c,
    BeastKind kind = BeastKind.base,
    String name = 'Iron Golem',
    String phrase = 'The bulwark advances.',
    String sigil = '◈',
    List<Color>? hues,
    List<BodyPart>? trainedParts,
  }) {
    return BeastCard(
      line: line,
      tier: tier,
      kind: kind,
      specimen: BeastSpecimen.base,
      name: name,
      slug: 'chest_iron_golem_1',
      hues: hues ?? [BodyPartHues.hueFor(line)],
      trainedParts: trainedParts ?? [line],
      achievementPhrase: phrase,
      sigil: sigil,
      sourceSessionId: 'workout-1',
    );
  }

  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.abyss,
        body: SizedBox(width: 1080, height: 1920, child: child),
      ),
    );
  }

  testWidgets('renders beast name, rank/XP/tonnage stat line, and phrase', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardBestiary(
          card: beast(),
          eyebrow: '⚔ Hoje você abateu',
          rankLabel: 'RANK C',
          xpLabel: '+618 XP',
          tonnageLabel: '8,4 t',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    // The beast name is the hero.
    expect(find.text('Iron Golem'), findsOneWidget);
    // The achievement phrase renders.
    expect(find.text('The bulwark advances.'), findsOneWidget);
    // The stat line carries the diamond rank chip + a rich-text run with
    // rank + XP + tonnage.
    expect(
      find.byKey(const ValueKey('share-card-bestiary-stat')),
      findsOneWidget,
    );
    // The rotated-diamond rank chip holds the tier letter (S4).
    expect(
      find.byKey(const ValueKey('share-card-bestiary-rank-sigil')),
      findsOneWidget,
    );
    final statText = tester
        .widget<Text>(
          find.byKey(const ValueKey('share-card-bestiary-stat-text')),
        )
        .textSpan!
        .toPlainText();
    expect(statText, contains('RANK C'));
    expect(statText, contains('+618 XP'));
    expect(statText, contains('8,4 t'));
    // The eyebrow renders the non-boss copy.
    expect(find.text('⚔ Hoje você abateu'), findsOneWidget);
  });

  testWidgets('boss renders the boss eyebrow + laurel sigil in heroGold', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardBestiary(
          card: beast(
            kind: BeastKind.boss,
            name: 'Ironheart, the Manticore',
            sigil: '⚜',
          ),
          eyebrow: '⚜ Chefe derrotado',
          rankLabel: 'RANK B',
          xpLabel: '+742 XP',
          tonnageLabel: '7,1 t',
          wordmark: 'REPSAGA',
          bossBadgeLabel: '⚜ Chefe derrotado',
        ),
      ),
    );

    // Boss eyebrow copy renders in heroGold.
    final eyebrow = tester.widget<Text>(
      find.byKey(const ValueKey('share-card-bestiary-eyebrow')),
    );
    expect(eyebrow.data, '⚜ Chefe derrotado');
    expect(eyebrow.style!.color, AppColors.heroGold);

    // The rank diamond chip holds the promoted tier letter in heroGold.
    final sigilLetter = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('share-card-bestiary-rank-sigil')),
        matching: find.byType(Text),
      ),
    );
    expect(sigilLetter.data, 'C'); // beast() default tier is C
    expect(sigilLetter.style!.color, AppColors.heroGold);
  });

  testWidgets('chimera widens EVERY trained rail segment (multi-hue, B2)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardBestiary(
          card: beast(
            line: BodyPart.arms,
            kind: BeastKind.chimera,
            name: 'A Quimera Primordial',
            hues: [
              BodyPartHues.hueFor(BodyPart.arms),
              BodyPartHues.hueFor(BodyPart.back),
              BodyPartHues.hueFor(BodyPart.legs),
            ],
            trainedParts: const [BodyPart.arms, BodyPart.back, BodyPart.legs],
          ),
          eyebrow: '⚔ Hoje você enfrentou',
          rankLabel: 'RANK S',
          xpLabel: '+1180 XP',
          tonnageLabel: '12,0 t',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    int flexOf(String part) => tester
        .widget<Expanded>(
          find.ancestor(
            of: find.byKey(ValueKey('share-card-chassis-rail-$part')),
            matching: find.byType(Expanded),
          ),
        )
        .flex;

    final chestFlex = flexOf('chest'); // untrained baseline
    // ALL THREE trained parts widen relative to an untrained part — the
    // pre-fix code only widened the dominant line (arms).
    expect(flexOf('arms'), greaterThan(chestFlex));
    expect(flexOf('back'), greaterThan(chestFlex));
    expect(flexOf('legs'), greaterThan(chestFlex));
    expect(find.text('A Quimera Primordial'), findsOneWidget);
  });

  testWidgets('chimera name renders as a multi-hue gradient (B2)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardBestiary(
          card: beast(
            line: BodyPart.arms,
            kind: BeastKind.chimera,
            name: 'A Quimera Primordial',
            hues: [
              BodyPartHues.hueFor(BodyPart.arms),
              BodyPartHues.hueFor(BodyPart.back),
              BodyPartHues.hueFor(BodyPart.legs),
            ],
            trainedParts: const [BodyPart.arms, BodyPart.back, BodyPart.legs],
          ),
          eyebrow: '⚔ Hoje você enfrentou',
          rankLabel: 'RANK S',
          xpLabel: '+1180 XP',
          tonnageLabel: '12,0 t',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    // A focused beast renders no gradient mask; a chimera wraps the name in a
    // ShaderMask so the multi-hue gradient paints the glyphs.
    expect(
      find.byKey(const ValueKey('share-card-bestiary-name-gradient')),
      findsOneWidget,
    );
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('boss renders the gold frame, crown, and ⚜ CHEFE badge (B1)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ShareCardBestiary(
          card: beast(
            line: BodyPart.arms,
            kind: BeastKind.boss,
            name: 'Ironheart, the Manticore',
            sigil: '⚜',
          ),
          eyebrow: '⚜ Chefe derrotado',
          rankLabel: 'RANK B',
          xpLabel: '+742 XP',
          tonnageLabel: '7,1 t',
          wordmark: 'REPSAGA',
          bossBadgeLabel: '⚜ Chefe derrotado',
        ),
      ),
    );

    // The three boss drama signals are present (spec §4 / mockup col 3).
    expect(
      find.byKey(const ValueKey('share-card-chassis-boss-frame')),
      findsOneWidget,
    );
    expect(find.text('♛'), findsOneWidget); // crown glyph
    final badge = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('share-card-chassis-boss-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(badge.data, '⚜ Chefe derrotado');
    expect(badge.style!.color, AppColors.heroGold);
  });

  testWidgets('standard card paints no boss drama', (tester) async {
    await tester.pumpWidget(
      host(
        ShareCardBestiary(
          card: beast(),
          eyebrow: '⚔ Hoje você abateu',
          rankLabel: 'RANK C',
          xpLabel: '+618 XP',
          tonnageLabel: '8,4 t',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('share-card-chassis-boss-frame')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('share-card-chassis-boss-badge')),
      findsNothing,
    );
    expect(find.text('♛'), findsNothing);
  });

  testWidgets('tallest boss content does not overflow at a 320dp card (N2)', (
    tester,
  ) async {
    // 320dp-wide 9:16 card with the worst case: boss + long epithet + a
    // 2-line name + a 2-line phrase. maxLines:2 + ellipsis must clamp without
    // a RenderFlex overflow.
    const cardW = 320.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.abyss,
          body: Center(
            child: SizedBox(
              width: cardW,
              height: cardW * 16 / 9,
              child: ShareCardBestiary(
                renderTarget: ShareCardRenderTarget.preview,
                card: beast(
                  line: BodyPart.arms,
                  kind: BeastKind.boss,
                  name: 'Coração-de-Ferro, o Senhor Dente-de-Sabre Imortal',
                  phrase:
                      'Uma nova lenda é forjada e o seu nome ecoa pelas eras.',
                  sigil: '⚜',
                ),
                eyebrow: '⚜ Chefe derrotado',
                rankLabel: 'RANK B',
                xpLabel: '+742 XP',
                tonnageLabel: '7,1 t',
                wordmark: 'REPSAGA',
                bossBadgeLabel: '⚜ Chefe derrotado',
              ),
            ),
          ),
        ),
      ),
    );

    // No overflow exception was thrown, and the name clamps to 2 lines.
    expect(tester.takeException(), isNull);
    final name = tester.widget<Text>(
      find.byKey(const ValueKey('share-card-bestiary-name')),
    );
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
  });
}
