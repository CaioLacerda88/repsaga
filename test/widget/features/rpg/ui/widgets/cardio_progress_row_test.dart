/// Widget tests for [CardioProgressRow] (Phase 38e).
///
/// Behavior, not wiring: each test asserts what the user sees — the band +
/// eyebrow, a rank numeral / bar for a trained track, the dimmed-teal +
/// em-dash for an untrained track, and that the value group never overflows
/// at 320dp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/rank_up_pulse_provider.dart';
import 'package:repsaga/features/rpg/ui/widgets/ambient_pulse_dot.dart';
import 'package:repsaga/features/rpg/ui/widgets/cardio_progress_row.dart';

class _MockPulseStorage extends Mock implements RankUpPulseLocalStorage {}

BodyPartSheetEntry _cardioEntry({
  int rank = 1,
  double totalXp = 0,
  double xpInRank = 0,
  double xpForNextRank = 60,
  double vitalityEwma = 0,
  double vitalityPeak = 0,
}) {
  return BodyPartSheetEntry(
    bodyPart: BodyPart.cardio,
    rank: rank,
    vitalityEwma: vitalityEwma,
    vitalityPeak: vitalityPeak,
    vitalityState: VitalityStateX.fromVitality(
      vitalityEwma: vitalityEwma,
      vitalityPeak: vitalityPeak,
    ),
    xpInRank: xpInRank,
    xpForNextRank: xpForNextRank,
    totalXp: totalXp,
  );
}

Widget _harness(BodyPartSheetEntry entry, {double width = 360}) {
  final storage = _MockPulseStorage();
  when(() => storage.isPulsing(any())).thenReturn(false);
  return ProviderScope(
    overrides: [rankUpPulseLocalStorageProvider.overrideWithValue(storage)],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: CardioProgressRow(
              entry: entry,
              trackLabel: 'Conditioning',
              eyebrowLabel: 'Cardio',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BodyPart.cardio);
  });

  group('CardioProgressRow — trained', () {
    testWidgets('renders the band eyebrow + uppercase track name + rank', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_cardioEntry(rank: 5, xpInRank: 168, xpForNextRank: 384)),
      );
      await tester.pump();

      // Band eyebrow + the track name, both uppercased.
      expect(find.text('CARDIO'), findsOneWidget);
      expect(find.text('CONDITIONING'), findsOneWidget);
      // Real rank numeral.
      expect(find.text('5'), findsOneWidget);
      // No em-dash on a trained row.
      expect(find.text('—'), findsNothing);
    });

    testWidgets(
      'trained row pulses (AmbientPulseDot) + shows the XP sub-line',
      (tester) async {
        await tester.pumpWidget(
          _harness(_cardioEntry(rank: 5, xpInRank: 168, xpForNextRank: 384)),
        );
        await tester.pump();

        // Alive: the teal dot is an AmbientPulseDot (vs the untrained static
        // Container dot).
        expect(find.byType(AmbientPulseDot), findsOneWidget);
        // XP/XP sub-line present.
        expect(find.textContaining('/384 XP'), findsOneWidget);
      },
    );

    testWidgets('is tappable (Semantics button + InkWell)', (tester) async {
      await tester.pumpWidget(_harness(_cardioEntry(rank: 5)));
      await tester.pump();
      expect(find.byType(InkWell), findsOneWidget);
      // The row carries the stable cardio identifier used by E2E + a11y.
      expect(find.bySemanticsLabel(RegExp('CONDITIONING')), findsOneWidget);
    });
  });

  group('CardioProgressRow — untrained day-zero', () {
    testWidgets('dimmed dot + em-dash, NO bar, NO XP line, NO pulse', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_cardioEntry()));
      await tester.pump();

      // Band still present (invites a first cardio session).
      expect(find.text('CARDIO'), findsOneWidget);
      expect(find.text('CONDITIONING'), findsOneWidget);
      // Em-dash rank, no XP sub-line.
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('XP'), findsNothing);
      // No ambient pulse on an untrained row (the dimmed-teal dot is a plain
      // Container, not an AmbientPulseDot).
      expect(find.byType(AmbientPulseDot), findsNothing);
    });

    testWidgets('the untrained dot keeps cardio identity (dimmed teal)', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_cardioEntry()));
      await tester.pump();

      // Find the 6dp dot Container inside the row and assert its color is a
      // dimmed bodyPartCardio (teal), NOT the grey textDim the strength
      // untrained row uses — the deliberate one-line divergence.
      final dot = tester.widget<Container>(
        find.descendant(
          of: find.byType(CardioProgressRow),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        ),
      );
      final color = (dot.decoration as BoxDecoration).color!;
      // Same RGB channels as bodyPartCardio, just dimmed alpha.
      expect(color.r, closeTo(AppColors.bodyPartCardio.r, 0.001));
      expect(color.g, closeTo(AppColors.bodyPartCardio.g, 0.001));
      expect(color.b, closeTo(AppColors.bodyPartCardio.b, 0.001));
      expect(color.a, lessThan(1.0));
    });
  });

  group('CardioProgressRow — 320dp', () {
    testWidgets('renders without overflow at the smallest breakpoint', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _cardioEntry(rank: 12, xpInRank: 12480, xpForNextRank: 20000),
          width: 320,
        ),
      );
      await tester.pump();
      // No RenderFlex overflow exception was thrown during layout.
      expect(tester.takeException(), isNull);
      expect(find.text('CONDITIONING'), findsOneWidget);
    });
  });
}
