import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/weekly_plan/ui/widgets/engagement_explainer_sheet.dart';

void main() {
  testWidgets('should render title + body text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EngagementExplainerSheet(
            title: 'Como contamos os sets',
            body: 'Cada set conta para a parte do corpo de maior atribuição.',
          ),
        ),
      ),
    );
    expect(find.text('Como contamos os sets'), findsOneWidget);
    expect(find.textContaining('atribuição'), findsOneWidget);
  });
}
