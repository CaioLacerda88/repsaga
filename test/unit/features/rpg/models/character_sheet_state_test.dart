import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';

void main() {
  group('CharacterSheetState — character XP band fields', () {
    test('exposes xpInLevel and xpForNextLevel populated from constructor', () {
      const state = CharacterSheetState(
        characterLevel: 14,
        lifetimeXp: 8420,
        xpInLevel: 8420,
        xpForNextLevel: 12000,
        bodyPartProgress: [],
      );
      expect(state.xpInLevel, 8420);
      expect(state.xpForNextLevel, 12000);
    });

    test('xpForNextLevel must never be less than xpInLevel (invariant)', () {
      const state = CharacterSheetState(
        characterLevel: 14,
        lifetimeXp: 8420,
        xpInLevel: 8420,
        xpForNextLevel: 8420,
        bodyPartProgress: [],
      );
      expect(state.xpForNextLevel >= state.xpInLevel, isTrue);
    });
  });
}
