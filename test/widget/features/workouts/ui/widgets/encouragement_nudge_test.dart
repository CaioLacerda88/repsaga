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

        // First-step is rendered through Text.rich (single muted span) —
        // `findRichText: true` walks the joined data. The first-step
        // variant is the only one that omits the leading `◆ ` prefix.
        expect(
          find.text(
            'Begin your journey — first set awaits',
            findRichText: true,
          ),
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

        // Duplicate first-step copy must NOT render. Pass
        // `findRichText: true` so the assertion catches the Text.rich
        // rendering path (L11.a wired the nudge through Text.rich); a
        // plain `find.text` would falsely pass even if the line came back.
        expect(
          find.text(
            'Begin your journey — first set awaits',
            findRichText: true,
          ),
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

      // Merged Text.rich exposes the joined line. We use `findRichText: true`
      // so `find.text` walks both `Text` and `Text.rich` widgets — without
      // it the helper only matches plain-data `Text` widgets, missing the
      // L11.a Text.rich rendering path. The leading `◆ ` prefix is part of
      // the rendered phrase and shows up in the joined text.
      expect(find.text('◆ 3-day streak', findRichText: true), findsOneWidget);
    });

    // L11.a — Visual emphasis on numeric nudges.
    //
    // The four numeric nudge variants (cross-build, body-part title, remaining
    // workouts, streak) render their key fragment in `FontWeight.w700`
    // `AppColors.textCream` via `Text.rich`. The rest of the line stays
    // muted (`AppColors.textDim`). A leading `◆ ` diamond prefix is rendered
    // in `AppColors.hotViolet` for every variant that surfaces a real nudge
    // (i.e. anything except `NudgeFirstStep`, which stays static-styled).
    //
    // Tests walk the `Text.rich` TextSpan children to assert that the
    // expected fragment appears in a bold-cream span. This is behavior-
    // not-wiring: a future refactor that changes the helper shape but keeps
    // the same visual contract still passes.
    group('L11.a — bold span + leading diamond on numeric nudges', () {
      /// Collects all leaf TextSpans into a flat list. `Text.rich` may nest
      /// spans arbitrarily — the tests need the leaves' text + style.
      List<TextSpan> flattenSpans(InlineSpan root) {
        final out = <TextSpan>[];
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            if (span.text != null && span.text!.isNotEmpty) out.add(span);
            for (final child in span.children ?? const <InlineSpan>[]) {
              walk(child);
            }
          }
        }

        walk(root);
        return out;
      }

      /// Returns the first leaf span whose joined text contains [fragment].
      /// Asserts via test failure if no leaf carries it.
      TextSpan findSpan(WidgetTester tester, String fragment) {
        final richFinder = find.byWidgetPredicate(
          (w) => w is RichText || w is Text,
        );
        for (final w in tester.widgetList(richFinder)) {
          InlineSpan? root;
          if (w is RichText) root = w.text;
          if (w is Text) root = w.textSpan;
          if (root == null) continue;
          final leaves = flattenSpans(root);
          for (final leaf in leaves) {
            if ((leaf.text ?? '').contains(fragment)) return leaf;
          }
        }
        fail('No TextSpan leaf contained fragment "$fragment"');
      }

      testWidgets('NudgeRemainingWorkouts bolds "{count} workouts"', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(
            overrides: [
              streakProvider.overrideWith((ref) => 1),
              completedCountProvider.overrideWith((ref) => 1),
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

        final span = findSpan(tester, '3 workouts');
        expect(span.style?.fontWeight, FontWeight.w700);
        expect(span.style?.color, AppColors.textCream);

        // Leading diamond rendered in hotViolet.
        final diamond = findSpan(tester, '◆');
        expect(diamond.style?.color, AppColors.hotViolet);
      });

      testWidgets('NudgeStreak bolds "{count}-day streak" core fragment', (
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

        // The whole streak fragment in en is "3-day streak" — bold span
        // wraps it entirely (there's no surrounding sentence).
        final span = findSpan(tester, '3-day streak');
        expect(span.style?.fontWeight, FontWeight.w700);
        expect(span.style?.color, AppColors.textCream);

        final diamond = findSpan(tester, '◆');
        expect(diamond.style?.color, AppColors.hotViolet);
      });

      testWidgets('NudgeBodyPartTitleClose bolds body-part + title fragments', (
        tester,
      ) async {
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
              streakProvider.overrideWith((ref) => 0),
              completedCountProvider.overrideWith((ref) => 0),
              totalBucketCountProvider.overrideWith((ref) => 0),
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
        await tester.pumpAndSettle();

        // Both Chest (body part) AND Iron-Chested (title name) bold.
        final bodyPartSpan = findSpan(tester, 'Chest');
        expect(bodyPartSpan.style?.fontWeight, FontWeight.w700);
        expect(bodyPartSpan.style?.color, AppColors.textCream);

        final titleSpan = findSpan(tester, 'Iron-Chested');
        expect(titleSpan.style?.fontWeight, FontWeight.w700);
        expect(titleSpan.style?.color, AppColors.textCream);
      });

      testWidgets('NudgeCrossBuildClose bolds the title fragment', (
        tester,
      ) async {
        const catalog = <rpg.Title>[
          rpg.CrossBuildTitle(
            slug: 'iron_bound',
            triggerId: rpg.CrossBuildTriggerId.ironBound,
          ),
        ];

        await tester.pumpWidget(
          _harness(
            overrides: [
              streakProvider.overrideWith((ref) => 0),
              completedCountProvider.overrideWith((ref) => 0),
              totalBucketCountProvider.overrideWith((ref) => 0),
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

        final titleSpan = findSpan(tester, 'Iron-Bound');
        expect(titleSpan.style?.fontWeight, FontWeight.w700);
        expect(titleSpan.style?.color, AppColors.textCream);
      });

      testWidgets('NudgeFirstStep stays static (no bold span, no diamond)', (
        tester,
      ) async {
        // Past day-0, no streak/bucket/titles → falls through to first-step
        // copy. First-step variant has no fragment to emphasize; the whole
        // line stays in `AppColors.textDim` w500. We assert this by walking
        // every leaf TextSpan within the nudge widget and confirming none
        // carries `w700`.
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
        await tester.pump();
        await tester.pump();

        // Locate the nudge container by its Semantics identifier and walk
        // the descendant Text widgets — none of them should expose a bold
        // weight on any leaf span.
        final nudgeFinder = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'home-encouragement-nudge',
        );
        expect(nudgeFinder, findsOneWidget);

        final textsInside = find.descendant(
          of: nudgeFinder,
          matching: find.byType(Text),
        );
        for (final w in tester.widgetList<Text>(textsInside)) {
          final root = w.textSpan;
          if (root == null) continue;
          void walk(InlineSpan span) {
            if (span is TextSpan) {
              expect(
                span.style?.fontWeight,
                isNot(FontWeight.w700),
                reason:
                    'First-step variant must not bold any fragment '
                    '(literal "${span.text}" was bolded).',
              );
              for (final child in span.children ?? const <InlineSpan>[]) {
                walk(child);
              }
            }
          }

          walk(root);
        }
        // Also: no leading diamond on first-step.
        expect(find.textContaining('◆'), findsNothing);
      });
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

      // `findRichText: true` walks Text.rich joined data (L11.a uses
      // Text.rich for the bold span). Leading `◆ ` prefix included in the
      // rendered phrase.
      expect(
        find.text('◆ Need 2 workouts to close the week', findRichText: true),
        findsOneWidget,
      );
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
          find.text(
            '◆ Chest title within reach: Iron-Chested',
            findRichText: true,
          ),
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
        find.text(
          '◆ Cross-build title within reach: Iron-Bound',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // Priority guards — none of the lower-priority slots should render.
      expect(find.textContaining('Need'), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
    });
  });
}
