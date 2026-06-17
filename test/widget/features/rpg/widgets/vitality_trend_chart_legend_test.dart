/// Widget tests for [VitalityTrendChartLegend] — Phase 38e-bis.
///
/// The legend disambiguates the trend chart's seven lines with one chip per
/// active body part. The 7th chip must read as cardio ("Conditioning") in the
/// cardio identity teal, tying the bright teal cardio line to its track.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_trend_chart_legend.dart';

import '../../../../helpers/test_material_app.dart';

Widget _wrap() {
  return const TestMaterialApp(
    home: Scaffold(body: SafeArea(child: VitalityTrendChartLegend())),
  );
}

void main() {
  group('VitalityTrendChartLegend', () {
    testWidgets('renders one chip per active body part', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap());
      await tester.pump();

      // Six strength chips (uppercased) + the cardio chip.
      expect(find.text('CHEST'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.text('LEGS'), findsOneWidget);
      expect(find.text('SHOULDERS'), findsOneWidget);
      expect(find.text('ARMS'), findsOneWidget);
      expect(find.text('CORE'), findsOneWidget);
    });

    testWidgets('cardio chip reads as "CONDITIONING" (the track label)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap());
      await tester.pump();

      // The cardio chip uses the track label, not the "Cardio" muscle group.
      expect(find.text('CONDITIONING'), findsOneWidget);
      expect(find.text('CARDIO'), findsNothing);
    });

    testWidgets('cardio chip swatch uses the cardio identity teal', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap());
      await tester.pump();

      // The cardio chip's swatch is a teal-filled Container. Walk from the
      // CONDITIONING label up to its sibling swatch within the same chip Row.
      final chipRow = find.ancestor(
        of: find.text('CONDITIONING'),
        matching: find.byType(Row),
      );
      final swatch = tester
          .widgetList<Container>(
            find.descendant(
              of: chipRow.first,
              matching: find.byType(Container),
            ),
          )
          .where((c) {
            final dec = c.decoration;
            return dec is BoxDecoration &&
                dec.color == AppColors.bodyPartCardio;
          })
          .toList();
      expect(
        swatch,
        hasLength(1),
        reason: 'cardio chip must carry a teal-filled swatch',
      );
    });

    testWidgets('renders without overflow at 320dp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
