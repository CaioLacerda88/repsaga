/// Widget tests for [CharacterSheetScreen] (Phase 18b).
///
/// Verifies the screen renders the right composition for two scenarios:
///   1. Day-0 user (no XP, no rows) — six dormant body-part rows visible,
///      first-set-awakens banner shown, halo collapses to Dormant.
///   2. High-rank user with mixed Vitality — header level numeral matches the
///      provider, no first-set banner.
///
/// We override [characterSheetProvider] directly via [Provider.overrideWith]
/// so the tests don't depend on Supabase / repositories.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/character_sheet_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/providers/rank_up_pulse_provider.dart';
import 'package:repsaga/features/rpg/ui/character_sheet_screen.dart';
import 'package:repsaga/features/rpg/ui/widgets/body_part_rank_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/character_xp_bar.dart';
import 'package:repsaga/features/rpg/ui/widgets/codex_nav_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/dormant_cardio_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/saga_header.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_radar.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// Hive-free stand-in: constructing the real RankUpPulseLocalStorage in a
// widget test would crash because the 'rank_up_pulse' Hive box is never
// opened in the test harness. The mock always returns false for isPulsing,
// so rows never spawn RankUpPulse (which would also hang pumpAndSettle).
class _MockPulseStorage extends Mock implements RankUpPulseLocalStorage {}

BodyPartSheetEntry _entry({
  required BodyPart bp,
  int rank = 1,
  double totalXp = 0,
  double vitalityEwma = 0,
  double vitalityPeak = 0,
  VitalityState? vitalityState,
}) {
  return BodyPartSheetEntry(
    bodyPart: bp,
    rank: rank,
    vitalityEwma: vitalityEwma,
    vitalityPeak: vitalityPeak,
    vitalityState:
        vitalityState ??
        VitalityStateX.fromVitality(
          vitalityEwma: vitalityEwma,
          vitalityPeak: vitalityPeak,
        ),
    xpInRank: 0,
    xpForNextRank: 60,
    totalXp: totalXp,
  );
}

CharacterSheetState _dayZeroState() {
  return CharacterSheetState(
    characterLevel: 1,
    lifetimeXp: 0,
    xpForNextLevel: 1,
    bodyPartProgress: activeBodyParts.map((bp) => _entry(bp: bp)).toList(),
    activeTitle: null,
    characterClass: null,
  );
}

CharacterSheetState _highRankState() {
  return CharacterSheetState(
    characterLevel: 12,
    lifetimeXp: 5400,
    xpForNextLevel: 6000,
    bodyPartProgress: [
      _entry(
        bp: BodyPart.chest,
        rank: 14,
        totalXp: 1200,
        vitalityEwma: 80,
        vitalityPeak: 90,
      ),
      _entry(
        bp: BodyPart.back,
        rank: 12,
        totalXp: 900,
        vitalityEwma: 75,
        vitalityPeak: 85,
      ),
      _entry(
        bp: BodyPart.legs,
        rank: 10,
        totalXp: 700,
        vitalityEwma: 75,
        vitalityPeak: 80,
      ),
      _entry(
        bp: BodyPart.shoulders,
        rank: 9,
        totalXp: 600,
        vitalityEwma: 72,
        vitalityPeak: 80,
      ),
      _entry(
        bp: BodyPart.arms,
        rank: 11,
        totalXp: 800,
        vitalityEwma: 78,
        vitalityPeak: 85,
      ),
      _entry(
        bp: BodyPart.core,
        rank: 8,
        totalXp: 500,
        vitalityEwma: 73,
        vitalityPeak: 80,
      ),
    ],
    activeTitle: null,
    characterClass: null,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const CharacterSheetScreen(),
      ),
      GoRoute(
        path: '/profile/settings',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Settings Placeholder'))),
      ),
      GoRoute(
        path: '/saga/stats',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Stats Placeholder'))),
      ),
      GoRoute(
        path: '/saga/titles',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Titles Placeholder'))),
      ),
      GoRoute(
        path: '/home/history',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('History Placeholder'))),
      ),
    ],
  );
}

Widget _buildApp(CharacterSheetState state) {
  final pulseStorage = _MockPulseStorage();
  when(
    () => pulseStorage.isPulsing(any(), now: any(named: 'now')),
  ).thenReturn(false);
  return ProviderScope(
    overrides: [
      characterSheetProvider.overrideWith((_) => AsyncData(state)),
      rankUpPulseLocalStorageProvider.overrideWithValue(pulseStorage),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router(),
    ),
  );
}

void main() {
  setUpAll(() {
    // any()/any(named:) for BodyPart needs a registered fallback so mocktail
    // can build matchers for the positional arg in isPulsing(BodyPart).
    registerFallbackValue(BodyPart.chest);
  });

  group('CharacterSheetScreen', () {
    testWidgets(
      'day-0 state renders six body-part rows and the first-set-awakens banner',
      (tester) async {
        // Tall canvas so all rows fit.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp(_dayZeroState()));
        await tester.pump();
        await tester.pump();

        // First-set-awakens banner copy is visible.
        expect(find.text('Your first set awakens this path.'), findsOneWidget);

        // Class slot placeholder.
        expect(find.text('The iron will name you.'), findsOneWidget);

        // Six body-part rows. Option B v4 upper-cases the label inline; use
        // a case-insensitive regex so the test stays robust to display-case
        // tweaks at the row layer.
        expect(
          find.bySemanticsLabel(RegExp('chest', caseSensitive: false)),
          findsAtLeastNWidgets(1),
        );

        // Six untrained body-part rows render (Option B v4 — no per-row
        // RankStamp; rank glyph collapses to "—" inside the row).
        expect(find.byType(BodyPartRankRow), findsNWidgets(6));
        // Untrained rows show the em-dash placeholder instead of a rank num.
        // Scope to BodyPartRankRow descendants so stray em-dashes elsewhere
        // on the screen don't bleed into the count.
        expect(
          find.descendant(
            of: find.byType(BodyPartRankRow),
            matching: find.text('—'),
          ),
          findsNWidgets(6),
        );
      },
    );

    testWidgets(
      'high-rank state renders the level numeral, no day-0 banner, six RankStamps',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp(_highRankState()));
        await tester.pump();
        await tester.pump();

        // Phase 26b Option B v4: SagaHeader splits the level into a bare
        // 56sp numeral + a separate 10sp "LVL" tag (rather than the legacy
        // "Lvl 12" single text). Assert on the numeral inside SagaHeader.
        expect(
          find.descendant(
            of: find.byType(SagaHeader),
            matching: find.text('12'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(SagaHeader),
            matching: find.text('LVL'),
          ),
          findsOneWidget,
        );

        // No first-set-awakens banner when the user has lifetime XP.
        expect(find.text('Your first set awakens this path.'), findsNothing);

        // Six trained rows (Option B v4 — each row owns its 20sp rank
        // numeral inline; no separate RankStamp widget).
        expect(find.byType(BodyPartRankRow), findsNWidgets(6));
      },
    );

    testWidgets('day-zero renders banner above the XP bar', (tester) async {
      // Phase 26b reorder: on day-zero the user must read the welcoming
      // banner BEFORE the empty XP bar so the narrative is "welcome →
      // first set will awaken → goal (the bar)" rather than seeing the
      // empty 0-XP track first. Pinned via getCenter.dy comparison so the
      // ordering survives layout refactors that swap explicit positions
      // for IntrinsicHeight / Wrap-style containers.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildApp(_dayZeroState()));
      await tester.pump();
      await tester.pump();

      final bannerCenter = tester.getCenter(
        find.text('Your first set awakens this path.'),
      );
      final barCenter = tester.getCenter(find.byType(CharacterXpBar));

      expect(
        bannerCenter.dy,
        lessThan(barCenter.dy),
        reason:
            'Day-zero: welcoming banner must render above the XP bar so '
            'the user reads the message before the empty progress indicator.',
      );
    });

    testWidgets(
      'composition is SagaHeader + CharacterXpBar + 6 rows + DormantCardioRow + 3 CodexNavRows (no VitalityRadar)',
      (tester) async {
        // Phase 26b Option B v4 pins the post-refactor composition: the
        // legacy VitalityRadar is gone, SagaHeader + CharacterXpBar are
        // composed at the top, and the six body-part rows + cardio row +
        // three codex nav rows are preserved.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp(_highRankState()));
        await tester.pump();
        await tester.pump();

        expect(find.byType(SagaHeader), findsOneWidget);
        expect(find.byType(CharacterXpBar), findsOneWidget);
        expect(find.byType(BodyPartRankRow), findsNWidgets(6));
        expect(find.byType(DormantCardioRow), findsOneWidget);
        expect(find.byType(CodexNavRow), findsNWidgets(3));
        // VitalityRadar is removed from the composition entirely.
        expect(find.byType(VitalityRadar), findsNothing);
      },
    );

    testWidgets(
      'sentinel: zero numeric Vitality % readouts leak onto the character sheet',
      (tester) async {
        // Phase 18d.2 contract: the character sheet is the *rune* face — runes
        // and rank stamps drive the visual state. Numeric Vitality percentages
        // (e.g. "80%", "75%") are deliberately confined to /saga/stats. If a
        // refactor accidentally surfaces a `%` glyph on the character sheet,
        // this test fails — protecting the rune-face/number-face split.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp(_highRankState()));
        await tester.pump();
        await tester.pump();

        // Sweep every Text widget in the tree. None should contain a `%`
        // glyph — the high-rank state has Vitality EWMA values 72..80 that
        // would render as "72%".."80%" if a regression piped them in.
        final percentTexts = tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => (t.data ?? '').contains('%'))
            .map((t) => t.data)
            .toList();
        expect(
          percentTexts,
          isEmpty,
          reason:
              'character sheet must not surface numeric Vitality percentages '
              '— those belong on /saga/stats. Found: $percentTexts',
        );
      },
    );
  });
}
