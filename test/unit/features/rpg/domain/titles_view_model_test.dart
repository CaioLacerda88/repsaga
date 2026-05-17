import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/titles_view_model.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/earned_title_entry.dart';
import 'package:repsaga/features/rpg/models/title.dart';

const _bodyPartChestR5 = BodyPartTitle(
  slug: 'chest_r5_initiate_of_the_forge',
  bodyPart: BodyPart.chest,
  rankThreshold: 5,
);
const _bodyPartChestR10 = BodyPartTitle(
  slug: 'chest_r10_plate_bearer',
  bodyPart: BodyPart.chest,
  rankThreshold: 10,
);
const _bodyPartChestR15 = BodyPartTitle(
  slug: 'chest_r15_forge_marked',
  bodyPart: BodyPart.chest,
  rankThreshold: 15,
);

EarnedTitleEntry _earned(Title t, {bool isActive = false}) => EarnedTitleEntry(
  title: t,
  earnedAt: DateTime(2026, 5, 10),
  isActive: isActive,
);

void main() {
  group('TitlesViewModel.split', () {
    test('should put the single active title in equipped region', () {
      final view = TitlesViewModel.split(
        catalog: const [_bodyPartChestR5, _bodyPartChestR10, _bodyPartChestR15],
        earned: [_earned(_bodyPartChestR5, isActive: true)],
        ranks: const {BodyPart.chest: 5},
        characterLevel: 1,
      );
      expect(view.equipped?.title.slug, 'chest_r5_initiate_of_the_forge');
    });

    test('should list earned-non-equipped sorted most-recent-first', () {
      final view = TitlesViewModel.split(
        catalog: const [_bodyPartChestR5, _bodyPartChestR10, _bodyPartChestR15],
        earned: [
          EarnedTitleEntry(
            title: _bodyPartChestR5,
            earnedAt: DateTime(2026, 5, 1),
            isActive: false,
          ),
          EarnedTitleEntry(
            title: _bodyPartChestR10,
            earnedAt: DateTime(2026, 5, 2),
            isActive: false,
          ),
        ],
        ranks: const {BodyPart.chest: 10},
        characterLevel: 1,
      );
      expect(view.earned.map((e) => e.title.slug).toList(), [
        'chest_r10_plate_bearer',
        'chest_r5_initiate_of_the_forge',
      ]);
    });

    test('should surface only the next per-body-part title in nextRows', () {
      // User at chest rank 6 — next chest title is r10 (not r15 too).
      // The splitter iterates every activeBodyPart; the other 5 fall back
      // to rank 1 via the COALESCE in the splitter and produce no
      // candidates because this catalog is chest-only, so the resulting
      // nextRows list collapses to the single chest entry.
      final view = TitlesViewModel.split(
        catalog: const [_bodyPartChestR5, _bodyPartChestR10, _bodyPartChestR15],
        earned: [_earned(_bodyPartChestR5)],
        ranks: const {BodyPart.chest: 6},
        characterLevel: 1,
      );
      expect(view.nextRows.map((r) => r.title.slug).toList(), [
        'chest_r10_plate_bearer',
      ]);
    });

    test(
      'should surface cross-build cards ONLY when within 1 rank of every condition',
      () {
        const ironBound = CrossBuildTitle(
          slug: 'iron_bound',
          triggerId: CrossBuildTriggerId.ironBound,
        );
        // 59/60/60 — within 1 of every condition.
        final viewNear = TitlesViewModel.split(
          catalog: const [ironBound],
          earned: const [],
          ranks: const {
            BodyPart.chest: 59,
            BodyPart.back: 60,
            BodyPart.legs: 60,
          },
          characterLevel: 1,
        );
        expect(viewNear.crossBuildCards.length, 1);
        expect(viewNear.crossBuildCards.first.title.slug, 'iron_bound');

        // 55/60/60 — chest is 5 short, NOT within 1.
        final viewFar = TitlesViewModel.split(
          catalog: const [ironBound],
          earned: const [],
          ranks: const {
            BodyPart.chest: 55,
            BodyPart.back: 60,
            BodyPart.legs: 60,
          },
          characterLevel: 1,
        );
        expect(viewFar.crossBuildCards, isEmpty);
      },
    );
  });
}
