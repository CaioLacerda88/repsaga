import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';

void main() {
  group('CharacterSheetState — xpForNextLevel field', () {
    test('exposes xpForNextLevel populated from constructor', () {
      const state = CharacterSheetState(
        characterLevel: 14,
        lifetimeXp: 8420,
        xpForNextLevel: 12000,
        bodyPartProgress: [],
      );
      expect(state.xpForNextLevel, 12000);
    });
  });
}
