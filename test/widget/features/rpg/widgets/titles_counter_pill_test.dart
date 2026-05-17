import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/titles_counter_pill.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  testWidgets('should render counter copy in pt locale', (tester) async {
    await tester.pumpWidget(
      const TestMaterialApp(
        locale: Locale('pt'),
        home: Scaffold(body: TitlesCounterPill(earnedCount: 8, totalCount: 90)),
      ),
    );
    expect(find.text('8 / 90 conquistados'), findsOneWidget);
  });

  testWidgets('should render counter copy in en locale', (tester) async {
    await tester.pumpWidget(
      const TestMaterialApp(
        locale: Locale('en'),
        home: Scaffold(body: TitlesCounterPill(earnedCount: 8, totalCount: 90)),
      ),
    );
    expect(find.text('8 / 90 earned'), findsOneWidget);
  });
}
