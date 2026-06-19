/// Widget tests for [CardioField] — the SHARED cardio input slot used by both
/// the active [CardioEntryCard] (compact) and the routine builder (large).
///
/// Pins the Phase 38h opt-in density contract (blast-radius rule): the size is
/// opt-in and defaults to [CardioFieldSize.compact], so the active card's slot
/// is byte-identical to before; the routine builder opts into the taller
/// [CardioFieldSize.large] hero slot + the edit (pencil) affordance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/cardio_field.dart';

import '../../../../../helpers/test_material_app.dart';

Widget _host(CardioField field) => TestMaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: field),
);

CardioField _field({
  CardioFieldSize size = CardioFieldSize.compact,
  bool showEditAffordance = false,
}) => CardioField(
  identifier: 'cf',
  semanticsLabel: 'Target time',
  label: 'TARGET TIME',
  onTap: () {},
  size: size,
  showEditAffordance: showEditAffordance,
  child: const Text('28:00'),
);

void main() {
  group('CardioField density', () {
    testWidgets('default (compact) slot is at least 52dp tall', (tester) async {
      await tester.pumpWidget(_host(_field()));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(CardioField));
      expect(size.height, greaterThanOrEqualTo(52));
    });

    testWidgets('large slot is at least 64dp tall', (tester) async {
      await tester.pumpWidget(_host(_field(size: CardioFieldSize.large)));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(CardioField));
      expect(size.height, greaterThanOrEqualTo(64));
    });

    test('size enum exposes the locked density values', () {
      expect(CardioFieldSize.compact.minHeight, 52);
      expect(CardioFieldSize.compact.valueFontSize, 18);
      expect(CardioFieldSize.large.minHeight, 64);
      expect(CardioFieldSize.large.valueFontSize, 22);
    });
  });

  group('CardioField edit affordance (3a)', () {
    testWidgets('shows the pencil glyph when showEditAffordance is true', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_field(showEditAffordance: true)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('no pencil glyph by default (empty/ghost state)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_field()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsNothing);
    });
  });
}
