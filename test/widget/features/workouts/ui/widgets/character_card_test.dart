/// Widget tests for [CharacterCard].
///
/// T6 covers the **collapsed** state only — header (40dp rune + level/class/
/// title center column + dominant rank/body-part right column) and the
/// closest-rank-up indicator row. T7 (tap-to-expand animation) and T8
/// (expanded body: character XP bar + 6 stat rows) extend this same file.
///
/// Tests stub [characterSheetProvider] directly with `AsyncData(...)`
/// (the provider exposes `AsyncValue<CharacterSheetState>`, not an
/// AsyncNotifier — see `character_sheet_provider.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/character_sheet_provider.dart';
import 'package:repsaga/features/workouts/ui/widgets/character_card.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

BodyPartSheetEntry _trained(
  BodyPart bp, {
  required int rank,
  required double xpInRank,
  required double xpForNextRank,
}) {
  return BodyPartSheetEntry(
    bodyPart: bp,
    rank: rank,
    vitalityEwma: 100,
    vitalityPeak: 200,
    vitalityState: VitalityState.active,
    xpInRank: xpInRank,
    xpForNextRank: xpForNextRank,
    totalXp: 1000,
  );
}

BodyPartSheetEntry _untrained(BodyPart bp) {
  return BodyPartSheetEntry(
    bodyPart: bp,
    rank: 1,
    vitalityEwma: 0,
    vitalityPeak: 0,
    vitalityState: VitalityState.untested,
    xpInRank: 0,
    xpForNextRank: 100,
    totalXp: 0,
  );
}

/// Steady-state trained sheet: chest is dominant (rank 16) + closest to
/// ranking up (smallest gap), back/legs trained at lower ranks. Other
/// active body parts remain untrained.
CharacterSheetState _trainedSheet() {
  return CharacterSheetState(
    characterLevel: 14,
    lifetimeXp: 8420,
    xpForNextLevel: 12000,
    bodyPartProgress: [
      // Chest: rank 16, gap = 100 - 80 = 20 → smallest gap → closest-rank-up.
      _trained(BodyPart.chest, rank: 16, xpInRank: 80, xpForNextRank: 100),
      _trained(BodyPart.back, rank: 11, xpInRank: 20, xpForNextRank: 100),
      _trained(BodyPart.legs, rank: 9, xpInRank: 18, xpForNextRank: 100),
      _untrained(BodyPart.shoulders),
      _untrained(BodyPart.arms),
      _untrained(BodyPart.core),
    ],
    activeTitle: 'Plate-Bearer',
    characterClass: CharacterClass.bulwark,
  );
}

/// Day-0 sheet — `isZeroHistory` is true (`lifetimeXp <= 0`), every body
/// part untrained.
CharacterSheetState _dayZeroSheet() {
  return CharacterSheetState(
    characterLevel: 1,
    lifetimeXp: 0,
    xpForNextLevel: 1000,
    bodyPartProgress: [for (final bp in activeBodyParts) _untrained(bp)],
    activeTitle: null,
    characterClass: null,
  );
}

Widget _harness({
  required CharacterSheetState sheet,
  double width = 360,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [characterSheetProvider.overrideWith((_) => AsyncData(sheet))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: const CharacterCard()),
        ),
      ),
    ),
  );
}

void main() {
  group('CharacterCard — collapsed', () {
    testWidgets(
      'renders Lvl numeral, class label, and active title for trained user',
      (tester) async {
        await tester.pumpWidget(_harness(sheet: _trainedSheet()));
        // `pump()` (single frame) — NOT `pumpAndSettle()`. The day-0 / fading
        // halo states own infinite-loop AnimationControllers (8s rotation,
        // 3s breathing pulse) in `RuneHalo`. `pumpAndSettle` waits for the
        // tree to be animation-idle and would hang. The collapsed-card
        // assertions don't depend on settled state — a single frame is
        // sufficient to render the header text + closest-rank-up row.
        await tester.pump();

        // Level numeral (Saga-style: bare Arabic digit).
        expect(find.text('14'), findsOneWidget);
        // Bulwark in en uppercases to "BULWARK" (matches SagaHeader treatment).
        expect(find.text('BULWARK'), findsOneWidget);
        // Active title rendered verbatim.
        expect(find.text('Plate-Bearer'), findsOneWidget);
      },
    );

    testWidgets('closest-rank-up indicator shows smallest-gap body part', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      // chest gap = 20 → smallest. l10n template (en):
      //   '◆ {bodyPart} · {xp} XP for rank {rank}'
      // bodyPart = "Chest", xp = 20, rank = 16 + 1 = 17.
      expect(find.text('◆ Chest · 20 XP for rank 17'), findsOneWidget);
    });

    testWidgets('day-0 user (isZeroHistory true) shows first-step fallback', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _dayZeroSheet()));
      await tester.pump();

      // Closest-rank-up returns null on a day-0 sheet → fallback copy.
      expect(
        find.text('Begin your journey — first set awaits'),
        findsOneWidget,
      );
      // Day-1 placeholder class label (no characterClass yet).
      expect(find.text('The iron will name you.'), findsOneWidget);
      // No closest-rank-up indicator rendered alongside the fallback.
      expect(find.textContaining('XP for rank'), findsNothing);
    });

    testWidgets('class+title column ellipsizes on narrow viewport (320dp)', (
      tester,
    ) async {
      // Long title pushes the right column wider than the available space at
      // 320dp; the class/title column must clip via ellipsis so the row
      // does not overflow.
      final sheet = CharacterSheetState(
        characterLevel: 14,
        lifetimeXp: 8420,
        xpForNextLevel: 12000,
        bodyPartProgress: [
          _trained(BodyPart.chest, rank: 16, xpInRank: 80, xpForNextRank: 100),
          for (final bp in activeBodyParts.skip(1)) _untrained(bp),
        ],
        activeTitle: 'Extraordinarily Verbose Compound Title Of The First Sun',
        characterClass: CharacterClass.bulwark,
      );

      await tester.pumpWidget(_harness(sheet: sheet, width: 320));
      await tester.pump();

      // No overflow assertions should fire from rendering at 320dp.
      expect(tester.takeException(), isNull);

      // The title widget renders inside the constrained meta column;
      // confirm its rendered width fits inside the 320dp host.
      final titleSize = tester.getSize(
        find.byKey(const ValueKey('character-card-title')),
      );
      expect(
        titleSize.width,
        lessThanOrEqualTo(320),
        reason:
            'Title row inside a 320dp card must clip via ellipsis, not '
            'overflow the row.',
      );
    });

    testWidgets('dominant rank chip color matches body-part hue', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      // Trained-sheet dominant = chest (rank 16, highest among trained).
      // Chest body-part hue = AppColors.bodyPartChest (pink, Phase 26a).
      // The dominant rank chip renders the rank num and body-part name
      // both in the body-part color — assert via the rank num Text widget
      // anchored by ValueKey.
      final rankNumFinder = find.byKey(
        const ValueKey('character-card-dominant-rank'),
      );
      expect(rankNumFinder, findsOneWidget);

      final rankText = tester.widget<Text>(rankNumFinder);
      expect(rankText.data, '16');
      expect(rankText.style?.color, AppColors.bodyPartChest);
    });
  });

  group('CharacterCard — expand/collapse', () {
    // Animation contract (PROJECT.md §3 26f, lines 476–480):
    //   - tap → 250ms easeOut expand
    //   - chevron rotates 90° (0.25 turns) when expanded
    //   - closest-rank-up indicator hidden during expanded state
    //   - state NOT persisted (always opens collapsed)
    //
    // All assertions use `pump(Duration)` — NOT `pumpAndSettle()`, which would
    // hang on RuneHalo's infinite-loop AnimationControllers (see collapsed-
    // group inline rationale).

    testWidgets('tap toggles AnimatedRotation chevron turns 0 → 0.25', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      AnimatedRotation rotation() => tester.widget<AnimatedRotation>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right),
          matching: find.byType(AnimatedRotation),
        ),
      );

      // Initial collapsed: chevron points right (0 turns).
      expect(rotation().turns, 0);

      // Tap → trigger expand. Pump past 250ms easeOut to settle the
      // AnimatedRotation tween.
      await tester.tap(find.byType(InkWell));
      await tester.pump(const Duration(milliseconds: 300));

      // Expanded: chevron rotated 90° (0.25 turns).
      expect(rotation().turns, 0.25);
    });

    testWidgets('closest-rank-up indicator is hidden when expanded', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      // Collapsed: closest-rank-up line visible.
      expect(find.text('◆ Chest · 20 XP for rank 17'), findsOneWidget);

      // Tap → expand → indicator hidden.
      await tester.tap(find.byType(InkWell));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('◆ Chest · 20 XP for rank 17'), findsNothing);
    });

    testWidgets(
      'tap-tap returns to collapsed state (closest-rank-up re-shown)',
      (tester) async {
        await tester.pumpWidget(_harness(sheet: _trainedSheet()));
        await tester.pump();

        // Tap once → expanded.
        await tester.tap(find.byType(InkWell));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('◆ Chest · 20 XP for rank 17'), findsNothing);

        // Tap again → collapsed.
        await tester.tap(find.byType(InkWell));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('◆ Chest · 20 XP for rank 17'), findsOneWidget);
      },
    );
  });
}
