import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/ui/widgets/class_localization.dart';

void main() {
  group('classTextColor — two-tier prestige rule', () {
    test('null routes to textDim (day-1 placeholder)', () {
      expect(classTextColor(null), AppColors.textDim);
    });
    test('initiate routes to primaryViolet (still-on-the-way)', () {
      expect(classTextColor(CharacterClass.initiate), AppColors.primaryViolet);
    });
    test('all 7 earned classes route to hotViolet', () {
      for (final cls in [
        CharacterClass.berserker,
        CharacterClass.bulwark,
        CharacterClass.sentinel,
        CharacterClass.pathfinder,
        CharacterClass.atlas,
        CharacterClass.anchor,
        CharacterClass.ascendant,
      ]) {
        expect(classTextColor(cls), AppColors.hotViolet);
      }
    });
  });
}
