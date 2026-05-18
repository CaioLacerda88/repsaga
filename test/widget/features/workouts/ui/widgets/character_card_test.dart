/// Widget tests for [CharacterCard].
///
/// Covers collapsed header (rune + level/class/title + dominant rank chip),
/// closest-rank-up indicator, tap-to-expand animation (chevron rotation +
/// indicator hide), and the expanded body (CharacterXpBar + 6
/// BodyPartRankRow widgets in canonical order, each tappable to
/// `/saga/stats?body_part=<slug>`).
///
/// Tests stub [characterSheetProvider] directly with `AsyncData(...)`
/// (the provider exposes `AsyncValue<CharacterSheetState>`, not an
/// AsyncNotifier — see `character_sheet_provider.dart`).
///
/// The harness wires a real [GoRouter] (with a placeholder `/saga/stats`
/// route) so the body-part-row deep-link push survives — reusing the
/// pattern proven in `body_part_rank_row_test.dart`. The
/// [rankUpPulseLocalStorageProvider] is overridden with a mock that
/// returns `false` for every isPulsing query — without the override the
/// production provider tries to open a Hive box that isn't initialized
/// in the unit-test harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/character_sheet_provider.dart';
import 'package:repsaga/features/rpg/providers/rank_up_pulse_provider.dart';
import 'package:repsaga/features/rpg/ui/widgets/body_part_rank_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/character_xp_bar.dart';
import 'package:repsaga/features/workouts/ui/widgets/character_card.dart';
import 'package:repsaga/l10n/app_localizations.dart';

class _MockPulseStorage extends Mock implements RankUpPulseLocalStorage {}

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
  RankUpPulseLocalStorage? pulseStorage,
  bool scrollable = true,
}) {
  final storage = pulseStorage ?? _MockPulseStorage();
  // Default stub: nothing is pulsing. Individual tests can pass a pre-stubbed
  // storage if they need different behavior.
  if (pulseStorage == null) {
    when(
      () => storage.isPulsing(any(), now: any(named: 'now')),
    ).thenReturn(false);
  }
  // Real GoRouter (with a placeholder /saga/stats route) so the expanded
  // body's BodyPartRankRow `context.push('/saga/stats?body_part=...')` taps
  // resolve to an asserted destination instead of throwing. Same pattern
  // proven in `body_part_rank_row_test.dart`.
  //
  // `scrollable: true` (default) wraps the card in a SingleChildScrollView
  // so the expanded body doesn't overflow the 600dp default viewport. The
  // navigation test opts OUT (`scrollable: false`) because a ScrollView's
  // Scrollable competes with the row InkWell in the gesture arena and
  // can swallow taps; that test instead resizes the test surface.
  Widget homeChild = SizedBox(width: width, child: const CharacterCard());
  homeChild = Center(child: homeChild);
  if (scrollable) {
    homeChild = SingleChildScrollView(child: homeChild);
  }
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(body: homeChild),
      ),
      GoRoute(
        path: '/saga/stats',
        // pageBuilder + NoTransitionPage so the route change is synchronous
        // — there's no Material transition to pump through. We can't use
        // pumpAndSettle (RuneHalo runs an infinite controller in the
        // source route), so we need the route swap to land in a single
        // microtask + frame.
        pageBuilder: (context, state) {
          final bodyPart = state.uri.queryParameters['body_part'] ?? '';
          return NoTransitionPage(
            child: Scaffold(body: Text('stats:$bodyPart')),
          );
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      characterSheetProvider.overrideWith((_) => AsyncData(sheet)),
      rankUpPulseLocalStorageProvider.overrideWithValue(storage),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

void main() {
  // `mocktail`'s `any()` matcher needs a fallback instance for non-nullable
  // enum types — without it the first `when(...isPulsing(any(), ...))` setup
  // throws StateError. Registered once for the whole file because every
  // group uses `_harness`, which stubs the pulse storage.
  setUpAll(() {
    registerFallbackValue(BodyPart.chest);
  });

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

    // Tap target: the OUTER InkWell — the one wrapping the whole card body.
    // Once the expanded body renders, each BodyPartRankRow has its own
    // InkWell (6 of them), so `find.byType(InkWell)` alone is ambiguous.
    // `.first` resolves to the outer card InkWell because Flutter walks the
    // widget tree depth-first and the card's InkWell is the ancestor.
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
      await tester.tap(find.byType(InkWell).first);
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
      await tester.tap(find.byType(InkWell).first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('◆ Chest · 20 XP for rank 17'), findsNothing);
    });

    testWidgets(
      'tap-tap returns to collapsed state (closest-rank-up re-shown)',
      (tester) async {
        await tester.pumpWidget(_harness(sheet: _trainedSheet()));
        await tester.pump();

        // Tap once → expanded.
        await tester.tap(find.byType(InkWell).first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('◆ Chest · 20 XP for rank 17'), findsNothing);

        // Tap again → collapsed.
        await tester.tap(find.byType(InkWell).first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('◆ Chest · 20 XP for rank 17'), findsOneWidget);
      },
    );
  });

  group('CharacterCard — expanded body', () {
    // Expanded body composition (PROJECT.md §3 26f lines 477–478):
    //   - 1dp hair divider between header section and XP bar.
    //   - CharacterXpBar (reused from Saga — 6dp gradient track + label).
    //   - 6 BodyPartRankRow widgets in canonical order
    //     (chest → back → legs → shoulders → arms → core).
    //   - Each row is `InkWell` tappable → /saga/stats?body_part=<slug>
    //     (the deep-link behavior lives inside BodyPartRankRow; we just
    //     have to render the rows and the contract holds).
    //
    // All animation pumps use `pump(Duration)` — `pumpAndSettle` would hang
    // on RuneHalo's infinite-loop AnimationControllers (same constraint
    // documented in the collapsed group).

    testWidgets('shows CharacterXpBar in expanded state', (tester) async {
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      // Collapsed: XP bar not yet mounted.
      expect(find.byType(CharacterXpBar), findsNothing);

      await tester.tap(find.byType(InkWell).first);
      await tester.pump(const Duration(milliseconds: 300));

      // Expanded: XP bar present and wired to the sheet's level/XP values.
      expect(find.byType(CharacterXpBar), findsOneWidget);
      final xpBar = tester.widget<CharacterXpBar>(find.byType(CharacterXpBar));
      expect(xpBar.lifetimeXp, 8420);
      expect(xpBar.xpForNextLevel, 12000);
      expect(xpBar.characterLevel, 14);
    });

    testWidgets('renders 6 BodyPartRankRow widgets in canonical order', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      // Collapsed: no rows rendered.
      expect(find.byType(BodyPartRankRow), findsNothing);

      await tester.tap(find.byType(InkWell).first);
      await tester.pump(const Duration(milliseconds: 300));

      // 6 rows — one per active body part.
      final rows = tester
          .widgetList<BodyPartRankRow>(find.byType(BodyPartRankRow))
          .toList();
      expect(rows, hasLength(6));
      // Canonical order: chest → back → legs → shoulders → arms → core.
      // `bodyPartProgress` is built in `activeBodyParts` order by the
      // character_sheet_provider, so the rendered rows match without
      // any client-side sort.
      expect(
        rows.map((r) => r.entry.bodyPart).toList(),
        equals(activeBodyParts),
      );
    });

    testWidgets(
      'tapping a body-part row navigates to /saga/stats with body_part query',
      (tester) async {
        // The expanded card is ~625dp tall — bigger than the default 600dp
        // viewport. Resize the test surface so the whole card fits without
        // a scroll view (a scroll view's Scrollable competes with the row
        // InkWell in the gesture arena and swallows the tap). try/finally
        // resets the surface before subsequent tests run.
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        try {
          await tester.pumpWidget(
            _harness(sheet: _trainedSheet(), scrollable: false),
          );
          await tester.pump();

          // Expand the card so the rows are mounted. Pump several frames
          // past the 250ms AnimatedSize duration so:
          // (a) the size animation fully settles and the clip-rect no
          //     longer truncates the body's hit-test region, and
          // (b) the outer InkWell's InkResponse tap-gesture cleanup
          //     completes — leaving its tap recognizer in an idle state
          //     before we issue the second tap on the row.
          await tester.tap(find.byType(InkWell).first);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 100));

          final chestRow = find.byWidgetPredicate(
            (w) => w is BodyPartRankRow && w.entry.bodyPart == BodyPart.chest,
          );
          expect(chestRow, findsOneWidget);
          final chestInkWell = find.descendant(
            of: chestRow,
            matching: find.byType(InkWell),
          );
          expect(chestInkWell, findsOneWidget);
          await tester.tap(chestInkWell);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Lands on the /saga/stats placeholder with the chest slug.
          expect(find.text('stats:chest'), findsOneWidget);
        } finally {
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets('day-0 sheet renders 6 untrained rows in expanded state', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(sheet: _dayZeroSheet()));
      await tester.pump();

      await tester.tap(find.byType(InkWell).first);
      await tester.pump(const Duration(milliseconds: 300));

      // All 6 BodyPartRankRow widgets still render — the row picks the
      // `_UntrainedRow` variant internally based on `entry.isUntrained`
      // (rank 1 + zero XP + zero vitality). Confirms day-0 users don't
      // see an empty body when they expand the card.
      expect(find.byType(BodyPartRankRow), findsNWidgets(6));
      // CharacterXpBar still renders even at lifetimeXp == 0 (denominator
      // is the day-0 xpForNextLevel = 1000, fraction = 0).
      expect(find.byType(CharacterXpBar), findsOneWidget);
    });
  });
}
