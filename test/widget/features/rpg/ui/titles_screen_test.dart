/// Widget tests for [TitlesScreen] — Phase 26d three-region composition.
///
/// The screen reads three async providers (catalog · earned · rpg progress),
/// hands them to [TitlesViewModel.split], and renders three regions:
///
///   * Equipado — the single equipped title in an [EquippedTitleCard].
///   * Conquistados — earned-but-not-equipped titles as [EarnedTitleRow]s,
///     each with an "Equipar" CTA.
///   * Próximos — locked titles, ordered: [CrossBuildCard]s first, then
///     body-part [NextTitleRow]s, then the character-level [NextTitleRow]
///     last.
///
/// These tests assert the region-selection contract end-to-end: which
/// widget types appear, which don't, and the regression case where a row
/// exists server-side with `is_active: false` (the user dismissed the
/// celebration without equipping) must still render in Conquistados with
/// the "Equipar" CTA visible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart'
    show TitlesRepository;
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/rpg/ui/titles_screen.dart';
import 'package:repsaga/features/rpg/ui/widgets/cross_build_card.dart';
import 'package:repsaga/features/rpg/ui/widgets/earned_title_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/equipped_title_card.dart';
import 'package:repsaga/features/rpg/ui/widgets/next_title_row.dart';

import '../../../../helpers/test_material_app.dart';

class _MockTitlesRepository extends Mock implements TitlesRepository {}

const _chestR5 = 'chest_r5_initiate_of_the_forge';
const _chestR10 = 'chest_r10_plate_bearer';
const _chestR15 = 'chest_r15_forge_marked';
const _backR5 = 'back_r5_lattice_touched';
const _ironBound = 'iron_bound';

rpg.Title _bodyPart(String slug, BodyPart bp, int rank) =>
    rpg.Title.bodyPart(slug: slug, bodyPart: bp, rankThreshold: rank);

/// Default catalog used by the screen tests — small enough to keep test
/// expectations focused, large enough to exercise every region.
final List<rpg.Title> _defaultCatalog = <rpg.Title>[
  _bodyPart(_chestR5, BodyPart.chest, 5),
  _bodyPart(_chestR10, BodyPart.chest, 10),
  _bodyPart(_chestR15, BodyPart.chest, 15),
  _bodyPart(_backR5, BodyPart.back, 5),
  const rpg.Title.crossBuild(
    slug: _ironBound,
    triggerId: rpg.CrossBuildTriggerId.ironBound,
  ),
];

EarnedTitleEntry _earned(rpg.Title title, {required bool isActive}) =>
    EarnedTitleEntry(
      title: title,
      earnedAt: DateTime.utc(2026, 4, 26),
      isActive: isActive,
    );

BodyPartProgress _progress(BodyPart bp, int rank) => BodyPartProgress(
  userId: 'u',
  bodyPart: bp,
  totalXp: 1,
  rank: rank,
  vitalityEwma: 0,
  vitalityPeak: 0,
  vitalityRefPeak: 0,
  lastEventAt: null,
  updatedAt: DateTime.utc(2026, 5, 2),
);

RpgProgressSnapshot _snapshot({
  Map<BodyPart, int> ranks = const {},
  int characterLevel = 1,
}) {
  return RpgProgressSnapshot(
    byBodyPart: <BodyPart, BodyPartProgress>{
      for (final entry in ranks.entries)
        entry.key: _progress(entry.key, entry.value),
    },
    characterState: CharacterState(
      userId: 'u',
      characterLevel: characterLevel,
      maxRank: 1,
      minRank: 1,
      lifetimeXp: 0,
    ),
  );
}

/// Pump the [TitlesScreen] with provider overrides. Inline (no helper file)
/// per the plan correction — keeps the test wiring visible in the file
/// that's exercising it.
Future<void> _pumpTitlesScreen(
  WidgetTester tester, {
  required List<rpg.Title> catalog,
  required List<EarnedTitleEntry> earned,
  required RpgProgressSnapshot snapshot,
  _MockTitlesRepository? repo,
  Locale locale = const Locale('pt'),
}) async {
  // Generous physical size — the screen is a tall ListView and we want
  // every region in the viewport so `find.byType` queries don't miss
  // off-screen rows.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        titlesRepositoryProvider.overrideWithValue(
          repo ?? _MockTitlesRepository(),
        ),
        titleCatalogProvider.overrideWith((_) async => catalog),
        earnedTitlesProvider.overrideWith((_) async => earned),
        rpgProgressProvider.overrideWith(
          () => _StubRpgProgressNotifier(snapshot),
        ),
      ],
      child: TestMaterialApp(locale: locale, home: const TitlesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ─── Empty state ─────────────────────────────────────────────────────────
  testWidgets(
    'should render the equipped region empty when no title is active',
    (tester) async {
      await _pumpTitlesScreen(
        tester,
        catalog: _defaultCatalog,
        earned: const [],
        snapshot: _snapshot(ranks: const {BodyPart.chest: 1}),
      );

      expect(find.byType(EquippedTitleCard), findsNothing);
      expect(find.byType(EarnedTitleRow), findsNothing);
      // Próximos still shows next-per-body-part rows.
      expect(find.byType(NextTitleRow), findsAtLeastNWidgets(1));
    },
  );

  // ─── One-earned-active state ─────────────────────────────────────────────
  testWidgets(
    'should render the equipped card and no earned rows when only one earned is active',
    (tester) async {
      await _pumpTitlesScreen(
        tester,
        catalog: _defaultCatalog,
        earned: [
          _earned(_bodyPart(_chestR5, BodyPart.chest, 5), isActive: true),
        ],
        snapshot: _snapshot(ranks: const {BodyPart.chest: 5}),
      );

      expect(find.byType(EquippedTitleCard), findsOneWidget);
      expect(find.byType(EarnedTitleRow), findsNothing);
    },
  );

  // ─── Many-earned state ───────────────────────────────────────────────────
  testWidgets('should list earned-non-active rows below the equipped card', (
    tester,
  ) async {
    await _pumpTitlesScreen(
      tester,
      catalog: _defaultCatalog,
      earned: [
        _earned(_bodyPart(_chestR5, BodyPart.chest, 5), isActive: true),
        _earned(_bodyPart(_chestR10, BodyPart.chest, 10), isActive: false),
        _earned(_bodyPart(_chestR15, BodyPart.chest, 15), isActive: false),
      ],
      snapshot: _snapshot(ranks: const {BodyPart.chest: 15}),
    );

    expect(find.byType(EquippedTitleCard), findsOneWidget);
    expect(find.byType(EarnedTitleRow), findsNWidgets(2));
  });

  // ─── No cross-build near ─────────────────────────────────────────────────
  testWidgets(
    'should not render any cross-build cards when none is within 1 rank',
    (tester) async {
      await _pumpTitlesScreen(
        tester,
        catalog: _defaultCatalog,
        earned: const [],
        snapshot: _snapshot(
          ranks: const {BodyPart.chest: 5, BodyPart.back: 5, BodyPart.legs: 5},
        ),
      );

      expect(find.byType(CrossBuildCard), findsNothing);
    },
  );

  // ─── Cross-build near ────────────────────────────────────────────────────
  testWidgets(
    'should render the cross-build card when within 1 rank of every condition',
    (tester) async {
      // iron_bound = chest >= 60 AND back >= 60 AND legs >= 60. Setting all
      // three to 59 puts every condition exactly 1 rank short of its floor.
      await _pumpTitlesScreen(
        tester,
        catalog: _defaultCatalog,
        earned: const [],
        snapshot: _snapshot(
          ranks: const {
            BodyPart.chest: 59,
            BodyPart.back: 59,
            BodyPart.legs: 59,
          },
        ),
      );

      expect(find.byType(CrossBuildCard), findsOneWidget);
      // "Especial" / "Special" badge — pt locale.
      expect(find.text('Especial'), findsOneWidget);
    },
  );

  // ─── Regression: dismiss-then-reopen (RPC ensured row exists) ────────────
  //
  // Post-26d, the rank-up overlay's INSERT runs server-side regardless of
  // whether the user dismissed or equipped from the celebration. If they
  // dismissed, the row exists with `is_active: false`. The Titles screen
  // MUST render it in the Conquistados region with the "Equipar" CTA so
  // they can flip it on later. This was the day-zero regression vector
  // surfaced during 26d planning.
  testWidgets(
    'should show the earned row even when celebration was dismissed without equip',
    (tester) async {
      await _pumpTitlesScreen(
        tester,
        catalog: _defaultCatalog,
        earned: [
          _earned(_bodyPart(_chestR5, BodyPart.chest, 5), isActive: false),
        ],
        snapshot: _snapshot(ranks: const {BodyPart.chest: 5}),
      );

      expect(find.byType(EarnedTitleRow), findsOneWidget);
      expect(find.text('Equipar'), findsOneWidget);
    },
  );
}

/// Minimal AsyncNotifier stub so [TitlesScreen] can read a
/// [RpgProgressSnapshot] without standing up a Supabase client. Production
/// notifier reads from `RpgRepository` which depends on `Supabase.instance`.
class _StubRpgProgressNotifier extends RpgProgressNotifier {
  _StubRpgProgressNotifier(this._snapshot);
  final RpgProgressSnapshot _snapshot;

  @override
  Future<RpgProgressSnapshot> build() async => _snapshot;
}
