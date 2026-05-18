import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/domain/weekly_engagement.dart';
import 'package:repsaga/features/weekly_plan/ui/widgets/engajamento_section.dart';
import 'package:repsaga/l10n/app_localizations.dart';

void main() {
  // Default locale in MaterialApp is `en`, so muscle-group names render as
  // their EN uppercase forms (CHEST, BACK, ...). Pt copy is covered by the
  // visual verification screenshots in Task 14.
  Widget host({required WeeklyEngagement engagement, VoidCallback? onInfoTap}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EngajamentoSection(
          engagement: engagement,
          headerLabel: 'Engajamento da semana',
          infoIconSemanticsLabel: 'Set counting explainer',
          legendDoneLabel: 'Done',
          legendPlannedLabel: 'Planned',
          onInfoTap: onInfoTap ?? () {},
        ),
      ),
    );
  }

  group('EngajamentoSection — body-part bars', () {
    testWidgets(
      'should render 6 bars in canonical body-part order without cardio',
      (tester) async {
        final engagement = WeeklyEngagement.from(
          done: {BodyPart.chest: 5},
          planned: {BodyPart.chest: 10, BodyPart.back: 4, BodyPart.legs: 6},
        );
        await tester.pumpWidget(host(engagement: engagement));

        // Canonical order: chest, back, legs, shoulders, arms, core.
        expect(find.text('CHEST'), findsOneWidget);
        expect(find.text('BACK'), findsOneWidget);
        expect(find.text('LEGS'), findsOneWidget);
        expect(find.text('SHOULDERS'), findsOneWidget);
        expect(find.text('ARMS'), findsOneWidget);
        expect(find.text('CORE'), findsOneWidget);
        expect(find.text('CARDIO'), findsNothing);
      },
    );

    testWidgets('should render the X / Y numeric label per bar', (
      tester,
    ) async {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 5},
        planned: {BodyPart.chest: 10},
      );
      await tester.pumpWidget(host(engagement: engagement));

      // chest: 5 done / 10 planned.
      expect(find.text('5 / 10'), findsOneWidget);
    });
  });

  group('EngajamentoSection — info icon', () {
    testWidgets('should fire onInfoTap when the info icon is tapped', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          engagement: WeeklyEngagement.empty,
          onInfoTap: () => tapped = true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('engagement-info-icon')));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('EngajamentoSection — header has NO total counter', () {
    testWidgets('should not render a sum-of-sets total in the header', (
      tester,
    ) async {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 5, BodyPart.back: 3},
        planned: {BodyPart.chest: 10, BodyPart.back: 4},
      );
      await tester.pumpWidget(host(engagement: engagement));

      // The naive total would be (5+3) / (10+4) = 8 / 14. That string must
      // NOT appear anywhere in the header — total is intentionally dropped
      // (compound-attribution + tie-counting would double-count and
      // mislead; the 6 bars are the truthful surface).
      expect(find.text('8 / 14'), findsNothing);
    });
  });
}
