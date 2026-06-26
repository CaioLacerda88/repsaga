import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/beast_card.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_mode.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_renderer.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_localizations.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_bestiary.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_clean_flex.dart';

/// Pins the Phase 39 mode routing in `ShareCardRenderer`: with a resolved
/// beast supplied, `mode` selects which content block renders — and the
/// SAME mode renders for BOTH render targets (so the offscreen export PNG
/// matches the visible preview).
void main() {
  const payload = SharePayload(
    tier: RewardTier.thresholdAnticipatory,
    totalXp: 618,
    dominantBodyPart: BodyPart.chest,
    dominantBodyPartRank: 19,
    rankProgressFraction: 0.5,
    pr: null,
    characterClassSlug: 'bulwark',
    isClassChange: false,
    hasTitleUnlock: false,
    hasRankUp: false,
  );

  const legacyStrings = ShareCardStrings(
    wordmark: 'REPSAGA',
    achievementFrameClassName: 'BULWARK',
    achievementFrameXpHero: '+618 XP',
    achievementFrameBpRank: 'Peito · Rank 19',
    discreetEyebrow: 'Peito · Rank 19',
    discreetHero: '+618',
    discreetHeroSubLabel: 'XP',
  );

  final beast = BeastCard(
    line: BodyPart.chest,
    tier: BeastTier.c,
    kind: BeastKind.base,
    specimen: BeastSpecimen.base,
    name: 'Iron Golem',
    slug: 'chest_iron_golem_1',
    hues: [BodyPartHues.hueFor(BodyPart.chest)],
    trainedParts: const [BodyPart.chest],
    achievementPhrase: 'The bulwark advances.',
    sigil: '◈',
    sourceSessionId: 'workout-1',
  );

  const bestiaryStrings = BestiaryShareStrings(
    wordmark: 'REPSAGA',
    bestiaryEyebrow: '⚔ Hoje você abateu',
    bossEyebrow: '⚜ Chefe derrotado',
    rankLabel: 'RANK C',
    xpLabel: '+618 XP',
    tonnageLabel: '8,4 t',
    cleanFlexEyebrow: 'Bulwark',
    cleanFlexHeroValue: '+618',
    cleanFlexStatValues: ['+618', '8,4 t', '24', '47 min'],
    cleanFlexStatLabels: ['XP', 'TON', 'SÉRIES', 'DUR'],
  );

  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.abyss,
        body: Center(child: SizedBox(width: 270, child: child)),
      ),
    );
  }

  for (final target in ShareCardRenderTarget.values) {
    testWidgets('bestiary mode renders the creature block ($target)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload,
            variant: ShareCardVariant.discreet,
            strings: legacyStrings,
            mode: ShareMode.bestiary,
            beastCard: beast,
            bestiaryStrings: bestiaryStrings,
            renderTarget: target,
          ),
        ),
      );

      expect(find.byType(ShareCardBestiary), findsOneWidget);
      expect(find.byType(ShareCardCleanFlex), findsNothing);
      expect(find.text('Iron Golem'), findsOneWidget);
    });

    testWidgets('clean-flex mode renders the stats block ($target)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload,
            variant: ShareCardVariant.discreet,
            strings: legacyStrings,
            mode: ShareMode.cleanFlex,
            beastCard: beast,
            bestiaryStrings: bestiaryStrings,
            renderTarget: target,
          ),
        ),
      );

      expect(find.byType(ShareCardCleanFlex), findsOneWidget);
      expect(find.byType(ShareCardBestiary), findsNothing);
      // The four-stat strip is present.
      expect(
        find.byKey(const ValueKey('share-card-clean-flex-strip')),
        findsOneWidget,
      );
    });
  }

  for (final target in ShareCardRenderTarget.values) {
    testWidgets('boss beast wires the ⚜ CHEFE badge through the renderer '
        '($target)', (tester) async {
      final bossBeast = BeastCard(
        line: BodyPart.arms,
        tier: BeastTier.b,
        kind: BeastKind.boss,
        specimen: BeastSpecimen.base,
        name: 'Ironheart, the Manticore',
        slug: 'arms_manticore_1',
        epithet: 'Ironheart',
        hues: [BodyPartHues.hueFor(BodyPart.arms)],
        trainedParts: const [BodyPart.arms],
        achievementPhrase: 'A new legend is forged.',
        sigil: '⚜',
        sourceSessionId: 'workout-1',
      );
      await tester.pumpWidget(
        host(
          ShareCardRenderer(
            payload: payload,
            // Photo path so the export tree mounts the full chassis.
            variant: ShareCardVariant.achievementFrame,
            strings: legacyStrings,
            mode: ShareMode.bestiary,
            beastCard: bossBeast,
            bestiaryStrings: bestiaryStrings,
            renderTarget: target,
          ),
        ),
      );

      // The boss drama survives the render path (I2 — boss frame/badge must
      // mount in both preview + export trees).
      expect(
        find.byKey(const ValueKey('share-card-chassis-boss-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('share-card-chassis-boss-frame')),
        findsOneWidget,
      );
      expect(find.text('♛'), findsOneWidget);
    });
  }

  testWidgets('falls back to the legacy path when no beast is supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardRenderer(
          payload: payload,
          variant: ShareCardVariant.discreet,
          strings: legacyStrings,
          mode: ShareMode.bestiary,
          renderTarget: ShareCardRenderTarget.preview,
        ),
      ),
    );

    // No beast → neither Phase 39 block renders; the legacy discreet path
    // owns the frame.
    expect(find.byType(ShareCardBestiary), findsNothing);
    expect(find.byType(ShareCardCleanFlex), findsNothing);
  });
}
