/// Widget tests for [EncouragementNudge].
///
/// The widget watches five inputs (cross-build title, body-part title,
/// remaining bucket workouts, streak, day-0 sheet) and renders the highest-
/// priority nudge per [selectNudge]. Tests pin the priority resolution at
/// the rendered-text contract — not the resolver wiring — by overriding
/// the upstream providers and asserting on the localized string.
///
/// The TitlesView "next" filter is computed inside the widget by feeding
/// [titleCatalogProvider] + [earnedTitlesProvider] + [rpgProgressProvider]
/// to [TitlesViewModel.split]. Tests drive that pipeline by overriding
/// those three providers (no `titlesViewProvider` exists in v1 — the
/// titles screen also composes inline; see widget docs).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart'
    show CharacterState;
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/providers/character_sheet_provider.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/weekly_plan/providers/suggested_next_provider.dart';
import 'package:repsaga/features/workouts/providers/streak_provider.dart';
import 'package:repsaga/features/workouts/ui/widgets/encouragement_nudge.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

/// Builds a minimal [BodyPartProgress] row at the given rank with the
/// canonical "fresh user" zeros for everything else. Tests use this to
/// seed [rpgProgressProvider] with body-part rank state without touching
/// vitality, lifetime XP, or `lastEventAt`.
BodyPartProgress _progressAt(BodyPart bp, int rank) {
  return BodyPartProgress(
    userId: 't',
    bodyPart: bp,
    totalXp: 0,
    rank: rank,
    vitalityEwma: 0,
    vitalityPeak: 0,
    lastEventAt: null,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// Seeds the upstream RPG snapshot with a custom rank map. Body parts
/// absent from [ranks] use the canonical placeholder (rank 1) via
/// `RpgProgressSnapshot.progressFor`.
RpgProgressSnapshot _snapshotWithRanks(Map<BodyPart, int> ranks) {
  return RpgProgressSnapshot(
    byBodyPart: {
      for (final entry in ranks.entries)
        entry.key: _progressAt(entry.key, entry.value),
    },
    characterState: CharacterState.empty,
  );
}

class _RpgProgressStub extends AsyncNotifier<RpgProgressSnapshot>
    implements RpgProgressNotifier {
  _RpgProgressStub(this.snapshot);
  final RpgProgressSnapshot snapshot;

  @override
  Future<RpgProgressSnapshot> build() async => snapshot;

  @override
  Future<RpgProgressSnapshot> refreshAfterSave() async => snapshot;

  @override
  Future<void> runBackfill() async {}
}

/// Minimal "past day-0" character sheet so the L2 day-0 suppression gate
/// (added 2026-05-18) does not short-circuit the resolver for the
/// priority/streak/title tests. `lifetimeXp > 0` ⇒ `isZeroHistory == false`.
/// Body-part progress is left empty — the tests don't read it directly;
/// they drive title/streak slots through their dedicated provider
/// overrides.
CharacterSheetState _pastDay0Sheet() => const CharacterSheetState(
  characterLevel: 2,
  lifetimeXp: 100,
  xpForNextLevel: 1000,
  bodyPartProgress: [],
);

/// Day-0 sheet for the L2 suppression test. `lifetimeXp == 0` ⇒
/// `isZeroHistory == true`.
CharacterSheetState _dayZeroSheet() => const CharacterSheetState(
  characterLevel: 1,
  lifetimeXp: 0,
  xpForNextLevel: 1000,
  bodyPartProgress: [],
);

/// Wraps [EncouragementNudge] in a minimal scaffold + localizations harness.
/// Caller passes the full override list for the five reactive resolver
/// inputs. The optional [sheet] override controls the L2 day-0 suppression
/// gate — default is `_pastDay0Sheet()` so the resolver runs through to
/// the priority/streak/title slots; the suppression test passes
/// `_dayZeroSheet()` explicitly.
Widget _harness({
  required List<Override> overrides,
  CharacterSheetState? sheet,
}) {
  final resolvedSheet = sheet ?? _pastDay0Sheet();
  return ProviderScope(
    overrides: [
      // Sheet override comes FIRST so test-specified overrides (if any)
      // for `characterSheetProvider` win — Riverpod resolves the latest
      // matching override in the list.
      characterSheetProvider.overrideWith((_) => AsyncData(resolvedSheet)),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Force English so test assertions stay in one locale — the resolver
      // is locale-agnostic; the rendered string just needs to match the
      // ARB we expect.
      locale: const Locale('en'),
      theme: AppTheme.dark,
      home: const Scaffold(body: EncouragementNudge()),
    ),
  );
}

void main() {
  group('EncouragementNudge', () {
    testWidgets(
      'shows first-step fallback for past-day-0 user with no streak / bucket / titles',
      (tester) async {
        // Past day-0 (lifetimeXp > 0 ⇒ suppression gate doesn't fire) but
        // no streak, no bucket entries, no titles within reach — resolver
        // falls through to NudgeFirstStep.
        await tester.pumpWidget(
          _harness(
            overrides: [
              streakProvider.overrideWith((ref) => 0),
              completedCountProvider.overrideWith((ref) => 0),
              totalBucketCountProvider.overrideWith((ref) => 0),
              titleCatalogProvider.overrideWith(
                (ref) async => const <rpg.Title>[],
              ),
              earnedTitlesProvider.overrideWith(
                (ref) async => const <EarnedTitleEntry>[],
              ),
              rpgProgressProvider.overrideWith(
                () => _RpgProgressStub(RpgProgressSnapshot.empty),
              ),
            ],
          ),
        );
        // Two pumps: one for ProviderScope build, one for the FutureProvider
        // resolution (catalog + earned).
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Begin your journey — first set awaits'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'returns empty slot when characterSheet.isZeroHistory == true (L2)',
      (tester) async {
        // L2 (visual verification, 2026-05-18): CharacterCard's fallback
        // already carries the day-0 first-step copy. Surfacing it here
        // duplicated the line on home for brand-new users. The nudge
        // collapses to a layout-preserving SizedBox but keeps the
        // `home-encouragement-nudge` Semantics identifier so the E2E hook
        // stays addressable.
        await tester.pumpWidget(
          _harness(
            sheet: _dayZeroSheet(),
            overrides: [
              streakProvider.overrideWith((ref) => 0),
              completedCountProvider.overrideWith((ref) => 0),
              totalBucketCountProvider.overrideWith((ref) => 0),
              titleCatalogProvider.overrideWith(
                (ref) async => const <rpg.Title>[],
              ),
              earnedTitlesProvider.overrideWith(
                (ref) async => const <EarnedTitleEntry>[],
              ),
              rpgProgressProvider.overrideWith(
                () => _RpgProgressStub(RpgProgressSnapshot.empty),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        // Duplicate first-step copy must NOT render.
        expect(
          find.text('Begin your journey — first set awaits'),
          findsNothing,
        );
        // The semantics container is still mounted at the reserved 24dp
        // height so layout stays stable.
        final identifierFinder = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'home-encouragement-nudge',
        );
        expect(identifierFinder, findsOneWidget);
        // The placeholder SizedBox sits as a direct descendant of the
        // identifier-bearing Semantics node, sized to the widget's
        // reserved height.
        final placeholder = find.descendant(
          of: identifierFinder,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == EncouragementNudge.height,
          ),
        );
        expect(placeholder, findsOneWidget);
      },
    );

    testWidgets('shows streak line when only streak is non-zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            streakProvider.overrideWith((ref) => 3),
            completedCountProvider.overrideWith((ref) => 0),
            totalBucketCountProvider.overrideWith((ref) => 0),
            titleCatalogProvider.overrideWith(
              (ref) async => const <rpg.Title>[],
            ),
            earnedTitlesProvider.overrideWith(
              (ref) async => const <EarnedTitleEntry>[],
            ),
            rpgProgressProvider.overrideWith(
              () => _RpgProgressStub(RpgProgressSnapshot.empty),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('3-day streak'), findsOneWidget);
    });

    testWidgets('shows remaining-workouts when bucket is partially complete '
        '(overrides streak)', (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            streakProvider.overrideWith((ref) => 1),
            completedCountProvider.overrideWith((ref) => 2),
            totalBucketCountProvider.overrideWith((ref) => 4),
            titleCatalogProvider.overrideWith(
              (ref) async => const <rpg.Title>[],
            ),
            earnedTitlesProvider.overrideWith(
              (ref) async => const <EarnedTitleEntry>[],
            ),
            rpgProgressProvider.overrideWith(
              () => _RpgProgressStub(RpgProgressSnapshot.empty),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Need 2 workouts to close the week'), findsOneWidget);
      // Priority guard — streak copy must NOT render alongside.
      expect(find.textContaining('streak'), findsNothing);
    });

    testWidgets(
      'shows body-part title nudge when a next-title row is within 1 rank',
      (tester) async {
        // Chest at rank 19, next title threshold rank 20 → ranksAway == 1.
        // Title slug `chest_r20_iron_chested` resolves to "Iron Chested"
        // via [localizedTitleCopy].
        const catalog = <rpg.Title>[
          rpg.BodyPartTitle(
            slug: 'chest_r20_iron_chested',
            bodyPart: BodyPart.chest,
            rankThreshold: 20,
          ),
        ];

        await tester.pumpWidget(
          _harness(
            overrides: [
              streakProvider.overrideWith((ref) => 2),
              completedCountProvider.overrideWith((ref) => 1),
              totalBucketCountProvider.overrideWith((ref) => 3),
              titleCatalogProvider.overrideWith((ref) async => catalog),
              earnedTitlesProvider.overrideWith(
                (ref) async => const <EarnedTitleEntry>[],
              ),
              rpgProgressProvider.overrideWith(
                () =>
                    _RpgProgressStub(_snapshotWithRanks({BodyPart.chest: 19})),
              ),
            ],
          ),
        );
        // Drain the catalog + earned-titles FutureProvider microtasks
        // before asserting on resolved-data render.
        await tester.pumpAndSettle();

        expect(
          find.text('Chest title within reach: Iron-Chested'),
          findsOneWidget,
        );
        // Priority guard — remaining-workouts copy must NOT render.
        expect(find.textContaining('Need'), findsNothing);
      },
    );

    testWidgets('shows cross-build nudge when a CrossBuildCard is surfaced '
        '(highest priority)', (tester) async {
      // `iron_bound` requires chest>=60, back>=60, legs>=60. Seed ranks
      // 59/59/59 → every condition has gap 1 → view-model surfaces the
      // card. Title localized name "Iron Bound" via [localizedTitleCopy].
      // We ALSO seed a body-part-title row, remaining-workouts > 0, and
      // a non-zero streak — priority must still surface the cross-build
      // copy.
      const catalog = <rpg.Title>[
        rpg.CrossBuildTitle(
          slug: 'iron_bound',
          triggerId: rpg.CrossBuildTriggerId.ironBound,
        ),
        // Decoy body-part title within 1 rank — must be dominated by
        // the cross-build slot.
        rpg.BodyPartTitle(
          slug: 'chest_r60_anvil_forged',
          bodyPart: BodyPart.chest,
          rankThreshold: 60,
        ),
      ];

      await tester.pumpWidget(
        _harness(
          overrides: [
            streakProvider.overrideWith((ref) => 4),
            completedCountProvider.overrideWith((ref) => 1),
            totalBucketCountProvider.overrideWith((ref) => 3),
            titleCatalogProvider.overrideWith((ref) async => catalog),
            earnedTitlesProvider.overrideWith(
              (ref) async => const <EarnedTitleEntry>[],
            ),
            rpgProgressProvider.overrideWith(
              () => _RpgProgressStub(
                _snapshotWithRanks({
                  BodyPart.chest: 59,
                  BodyPart.back: 59,
                  BodyPart.legs: 59,
                }),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Cross-build title within reach: Iron-Bound'),
        findsOneWidget,
      );
      // Priority guards — none of the lower-priority slots should render.
      expect(find.textContaining('Need'), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
    });
  });
}
