/// Widget tests for [CharacterCard].
///
/// Covers collapsed header (rune + level/class/title + dominant rank chip),
/// closest-rank-up indicator, tap-to-expand animation (chevron rotation +
/// indicator hide), and the expanded body (CharacterXpBar + 6
/// BodyPartRankRow widgets in canonical order, each tappable to
/// `/saga/stats?body_part=<slug>`).
///
/// CH2: dominant column absent for day-0 user (no trained body parts).
/// CH3: chevron exposes localized accessibility hint.
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
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
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

/// Stub ProfileNotifier for RuneHalo's embedded ProfileAvatar (Phase 32
/// PR 32e scope add). Without this override the avatar's identity
/// resolver pulls `currentUserEmailProvider` which touches
/// `Supabase.instance` — unwound in the unit-test harness.
class _StubProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile? _profile;

  @override
  Future<Profile?> build() async => _profile;

  @override
  Future<void> saveOnboardingProfile({
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}

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
    activeTitle: 'chest_r5_initiate_of_the_forge',
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
      // Phase 32 PR 32e scope add: tapping the halo navigates here. Same
      // NoTransitionPage trick so the route swap lands in one frame
      // without pumpAndSettle (RuneHalo's infinite tickers would hang it).
      GoRoute(
        path: '/profile/settings',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: Scaffold(body: Text('profile-settings-placeholder')),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      characterSheetProvider.overrideWith((_) => AsyncData(sheet)),
      rankUpPulseLocalStorageProvider.overrideWithValue(storage),
      // RuneHalo embeds ProfileAvatar (Phase 32 PR 32e scope add); the
      // avatar's identity resolver reads these providers. Stubbed with
      // a steady-state profile so the gradient + monogram render
      // deterministically across every test in this file.
      profileProvider.overrideWith(
        () =>
            _StubProfileNotifier(const Profile(id: 'u', displayName: 'Alice')),
      ),
      currentUserEmailProvider.overrideWithValue('alice@example.test'),
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
        // Active title resolves through `localizedTitleCopy(slug, l10n)?.name`.
        // The provider chain forwards the raw slug
        // (`chest_r5_initiate_of_the_forge`) from `earned_titles.title_id` —
        // the widget MUST resolve it to the localized display name. Pin both
        // sides: the localized name renders (uppercased by the L12 title
        // pill — mockup `.cc-title-pill { text-transform: uppercase }`), and
        // the raw slug does NOT.
        // See `cluster_slug_rendered_as_display_name`.
        expect(find.text('INITIATE OF THE FORGE'), findsOneWidget);
        expect(find.text('chest_r5_initiate_of_the_forge'), findsNothing);
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

    testWidgets('closest-rank-up indicator bolds body-part name span (L11.b)', (
      tester,
    ) async {
      // Mockup `.cc-closest .indicator strong { color: var(--text-cream); }`
      // — only the body-part name (here "Chest") wears the bold + cream
      // emphasis. The leading `◆ ` diamond stays in the body-part hue;
      // the `· 20 XP for rank 17` suffix stays muted (`AppColors.textDim`).
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      // Walk the indicator's Text.rich span tree and find the leaf whose
      // text equals "Chest" — assert its style.
      final indicatorFinder = find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.identifier == 'home-closest-rank-up',
      );
      expect(indicatorFinder, findsOneWidget);

      TextSpan? boldLeaf;
      final richInside = find.descendant(
        of: indicatorFinder,
        matching: find.byType(RichText),
      );
      for (final w in tester.widgetList<RichText>(richInside)) {
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            if ((span.text ?? '').contains('Chest') &&
                span.style?.fontWeight == FontWeight.w700) {
              boldLeaf = span;
            }
            for (final child in span.children ?? const <InlineSpan>[]) {
              walk(child);
            }
          }
        }

        walk(w.text);
      }
      expect(
        boldLeaf,
        isNotNull,
        reason:
            'Closest-rank-up indicator must wrap the body-part name '
            '("Chest") in a FontWeight.w700 span; mockup '
            '.cc-closest .indicator strong → cream + bold.',
      );
      expect(boldLeaf!.style?.color, AppColors.textCream);
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

    testWidgets('active title renders inside a surface2 pill container (L12)', (
      tester,
    ) async {
      // Mockup `.cc-title-pill` spec:
      //   padding: 3px 8px;
      //   background: var(--surface2);   // #241640 == AppColors.surface2
      //   border-radius: 10px;
      //   display: inline-block;
      //
      // Pins the Container/DecoratedBox wrapper around the resolved title
      // text. Trained sheet's `activeTitle` resolves through
      // `localizedTitleCopy` to "Initiate of the Forge" (en). The wrapper
      // anchors on the same ValueKey we already use for the title text
      // (`character-card-title`) so a future refactor that swaps the
      // wrapper widget but keeps the contract still passes.
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      final titleFinder = find.byKey(const ValueKey('character-card-title'));
      expect(titleFinder, findsOneWidget);

      // Walk ancestors of the title Text widget looking for a Container or
      // DecoratedBox whose decoration has the surface2 fill + 10dp radius.
      final wrapper = find.ancestor(
        of: titleFinder,
        matching: find.byWidgetPredicate((w) {
          if (w is Container) {
            final dec = w.decoration;
            if (dec is BoxDecoration) {
              return dec.color == AppColors.surface2 &&
                  dec.borderRadius == BorderRadius.circular(10);
            }
          }
          return false;
        }),
      );
      expect(
        wrapper,
        findsOneWidget,
        reason:
            'Active title must be wrapped in a Container with '
            'AppColors.surface2 fill and BorderRadius.circular(10) per '
            'mockup .cc-title-pill.',
      );
    });

    testWidgets(
      'no title pill rendered when activeTitle is null (day-0 user) (L12)',
      (tester) async {
        // Day-0 user has no equipped title — the pill must NOT render
        // (the `if (hasTitle)` gate already exists; this test pins it so
        // the empty pill cannot regress into rendering).
        await tester.pumpWidget(_harness(sheet: _dayZeroSheet()));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('character-card-title')),
          findsNothing,
        );
        final emptyPill = find.byWidgetPredicate((w) {
          if (w is Container) {
            final dec = w.decoration;
            if (dec is BoxDecoration) {
              return dec.color == AppColors.surface2 &&
                  dec.borderRadius == BorderRadius.circular(10);
            }
          }
          return false;
        });
        // Header itself uses no surface2/10dp-radius container outside the
        // pill — finding zero matches proves the pill was suppressed.
        expect(emptyPill, findsNothing);
      },
    );

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

    testWidgets(
      'dominant column absent for day-0 user (no trained entries) (CH2)',
      (tester) async {
        // Pins the rendering contract that the right-side dominant rank
        // column does NOT appear when every body part is untrained.
        // `_dominantTrainedEntry` returns null for day-0 users, so the
        // `if (dominant != null)` guard collapses the whole column.
        await tester.pumpWidget(_harness(sheet: _dayZeroSheet()));
        await tester.pump();

        // Card renders — no crash on day-0 data.
        expect(find.byType(CharacterCard), findsOneWidget);

        // Dominant rank column NOT present. Anchored by the ValueKey that the
        // `_DominantColumn` widget stamps on its rank-num Text widget
        // (line 329 of character_card.dart). If the column were accidentally
        // rendered, this key would be findable.
        expect(
          find.byKey(const ValueKey('character-card-dominant-rank')),
          findsNothing,
          reason:
              'Dominant rank column must be absent when every body part '
              'is untrained (day-0 user). Only _HeaderRow._dominantTrainedEntry '
              'returning null gates this correctly.',
        );
        expect(
          find.byKey(const ValueKey('character-card-dominant-name')),
          findsNothing,
        );

        // The first-step fallback IS present — confirms the card renders the
        // correct day-0 copy in the closest-rank-up indicator slot.
        expect(
          find.text('Begin your journey — first set awaits'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping the home avatar navigates to /profile/settings (PR 32e UX)',
      (tester) async {
        // Phase 32 PR 32e scope add: per UX-critic memo the Home halo is
        // a tappable target that pushes `/profile/settings`. Tap routes to
        // Settings (NOT directly to the upload picker) because the halo is
        // a read-anchor RPG signal — not an edit surface — and the upload
        // UI is already purpose-built on IdentityCard. This test pins the
        // user-visible behavior (after tap, the Settings placeholder
        // route's content renders), not the wiring.
        //
        // Behavior-not-wiring: the destination Text widget is the
        // user-perceptible outcome. If the GestureDetector were removed,
        // or the route argument were silently changed, this test would
        // fail with the placeholder absent / wrong.
        await tester.pumpWidget(_harness(sheet: _trainedSheet()));
        await tester.pump();

        final avatarFinder = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'home-character-avatar',
        );
        expect(
          avatarFinder,
          findsOneWidget,
          reason:
              'Home halo must carry the home-character-avatar Semantics '
              'identifier (Phase 32 PR 32e scope add).',
        );

        // Tap the avatar via its GestureDetector. The halo's identifier
        // wraps a GestureDetector → RuneHalo subtree; tapping the
        // Semantics-anchored region routes through the detector.
        await tester.tap(avatarFinder);
        // Pump several frames past the GoRouter transition (NoTransitionPage
        // is synchronous but the framework still needs a frame to commit
        // the route swap + paint the destination). pumpAndSettle would hang
        // on the source route's infinite RuneHalo controllers.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.text('profile-settings-placeholder'),
          findsOneWidget,
          reason:
              'Tapping the home halo must push /profile/settings (per UX-'
              'critic memo: discoverability of upload flow without inviting '
              'accidental taps in workout context).',
        );
      },
    );

    testWidgets(
      'home halo Semantics carries button:true for AOM tappable role',
      (tester) async {
        // cluster_semantics_button_missing: Semantics(container:true)
        // without button:true makes the AOM node passive — Playwright +
        // screen-reader clicks land but don't forward to the GestureDetector
        // as a tap. Pin button:true here so a future refactor can't drop
        // it silently.
        await tester.pumpWidget(_harness(sheet: _trainedSheet()));
        await tester.pump();

        final avatar = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'home-character-avatar',
          ),
        );
        expect(avatar.properties.button, isTrue);
      },
    );

    testWidgets('chevron exposes localized accessibility hint (CH3)', (
      tester,
    ) async {
      // Pins the `Semantics(label: hint)` on `_Chevron` so a future
      // refactor cannot silently drop the `homeCharacterCardChevronHint`
      // accessibility copy. The hint communicates the tap affordance to
      // screen-reader users.
      //
      // Assertion shape: use `find.bySemanticsLabel(RegExp(...))` rather
      // than an exact-string match. Flutter's semantics system merges a
      // `Semantics(label:)` without `container: true` into the ancestor
      // node's label — the resulting merged label is not equal to the
      // isolated hint string but DOES contain it. The Flutter test docs
      // (see `_bySemanticsProperty` source) explicitly recommend regex
      // over exact strings when the framework has combined semantics.
      // The regex still fails if the Semantics wrapper is removed,
      // which is the regression this test guards.
      //
      // NOTE FOR TECH-LEAD: The `_Chevron` Semantics node does NOT
      // carry `container: true`, so its label is merged into the parent
      // header node by the semantics system. A screen reader receives the
      // entire merged text block, not a discrete "Tap to expand character
      // details" announcement. Adding `container: true` to `_Chevron`'s
      // Semantics would isolate the node and allow an exact-string match.
      // This is a tracked accessibility gap — see QA bug report in PR #242.
      await tester.pumpWidget(_harness(sheet: _trainedSheet()));
      await tester.pump();

      final handle = tester.ensureSemantics();

      // Regex matches the partial label within the merged semantics node.
      // The en-locale hint is "Tap to expand character details" — any
      // prefix like "expand" is stable and locale-invariant enough for a
      // widget-level pin. If the Semantics(label: hint) wrapper is removed,
      // no semantics node will carry any form of this text and the test fails.
      expect(
        find.bySemanticsLabel(RegExp('expand character details')),
        findsOneWidget,
        reason:
            'The _Chevron widget must expose `homeCharacterCardChevronHint` '
            'via Semantics(label: hint). If this fails, the label wrapper '
            'was removed from _Chevron. Note: exact-string bySemanticsLabel '
            'does not work here because Flutter merges the label into the '
            'parent header node — use regex per Flutter docs.',
      );

      handle.dispose();
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
