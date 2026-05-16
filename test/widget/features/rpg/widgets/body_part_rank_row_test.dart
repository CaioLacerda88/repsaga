/// Widget tests for [BodyPartRankRow] (Phase 26b Option B v4).
///
/// The row is the mini-XP-block per `docs/PROJECT.md` §3 Phase 26 → 26b
/// acceptance criteria:
///   * Trained: 6dp body-part-hue dot · UPPERCASE 10sp name · 20sp
///     Rajdhani rank num · 4dp XP bar · 9sp "X XP / Y to next rank" label.
///   * Untrained: 0.4 opacity, `—` rank, no bar, no label row.
///   * Whole row InkWell-tappable → `/saga/stats?body_part=<dbValue>`.
///   * Dot wrapped in [RankUpPulse] only when storage.isPulsing == true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_local_storage.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/rank_up_pulse_provider.dart';
import 'package:repsaga/features/rpg/ui/widgets/body_part_rank_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/rank_up_pulse.dart';
import 'package:repsaga/l10n/app_localizations.dart';

class _MockPulseStorage extends Mock implements RankUpPulseLocalStorage {}

BodyPartSheetEntry _entry({
  BodyPart bp = BodyPart.chest,
  int rank = 3,
  double xpInRank = 240,
  double xpForNextRank = 800,
  double totalXp = 240,
  double vitalityPeak = 100,
  double vitalityEwma = 80,
  VitalityState state = VitalityState.active,
}) => BodyPartSheetEntry(
  bodyPart: bp,
  rank: rank,
  vitalityEwma: vitalityEwma,
  vitalityPeak: vitalityPeak,
  vitalityState: state,
  xpInRank: xpInRank,
  xpForNextRank: xpForNextRank,
  totalXp: totalXp,
);

Widget _wrap(Widget child, {RankUpPulseLocalStorage? storage}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (context, state) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/saga/stats',
        builder: (context, state) => const Scaffold(body: Text('stats')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      if (storage != null)
        rankUpPulseLocalStorageProvider.overrideWithValue(storage),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BodyPart.chest);
  });

  group('BodyPartRankRow — Option B v4', () {
    testWidgets('trained row renders dot + name + rank num + bar + label', (
      tester,
    ) async {
      final storage = _MockPulseStorage();
      when(
        () => storage.isPulsing(any(), now: any(named: 'now')),
      ).thenReturn(false);
      await tester.pumpWidget(
        _wrap(
          BodyPartRankRow(
            entry: _entry(
              rank: 16,
              xpInRank: 1420,
              xpForNextRank: 2000,
              totalXp: 8000,
            ),
          ),
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      // Rank num.
      expect(find.text('16'), findsOneWidget);
      // Body-part name (pt-BR for chest → "Peito", upper-cased by widget).
      expect(find.text('PEITO'), findsOneWidget);
      // XP-in-rank (formatted thousand-separator, pt locale → 1.420).
      expect(find.textContaining('1.420 XP'), findsOneWidget);
      // Remaining to next rank (580) + pt-BR suffix.
      expect(find.textContaining('580 para o próximo rank'), findsOneWidget);
      // Bar present on trained rows.
      expect(find.byKey(const ValueKey('body-part-row-bar')), findsOneWidget);
    });

    testWidgets(
      'untrained row renders at 0.4 element alpha with "—" rank and no bar',
      (tester) async {
        final storage = _MockPulseStorage();
        when(
          () => storage.isPulsing(any(), now: any(named: 'now')),
        ).thenReturn(false);
        await tester.pumpWidget(
          _wrap(
            BodyPartRankRow(
              entry: _entry(
                rank: 1,
                xpInRank: 0,
                totalXp: 0,
                vitalityPeak: 0,
                vitalityEwma: 0,
                state: VitalityState.untested,
              ),
            ),
            storage: storage,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('—'), findsOneWidget);
        expect(find.byKey(const ValueKey('body-part-row-bar')), findsNothing);
        // Element-level alpha contract: the em-dash Text renders with
        // textDim * 0.4 — NOT wrapped in an Opacity widget (which would
        // create a compositing layer the InkWell splash paints through).
        final dashText = tester.widget<Text>(find.text('—'));
        final alpha = dashText.style?.color?.a;
        expect(alpha, isNotNull);
        expect(alpha!, closeTo(0.4, 0.01));
      },
    );

    testWidgets(
      'renders RankUpPulse overlay when storage.isPulsing returns true',
      (tester) async {
        final storage = _MockPulseStorage();
        when(
          () => storage.isPulsing(any(), now: any(named: 'now')),
        ).thenReturn(false);
        // Specific stub wins on subsequent calls — chest is pulsing here.
        when(
          () => storage.isPulsing(BodyPart.chest, now: any(named: 'now')),
        ).thenReturn(true);
        await tester.pumpWidget(
          _wrap(BodyPartRankRow(entry: _entry()), storage: storage),
        );
        // RankUpPulse runs an infinite AnimationController.repeat() — using
        // pumpAndSettle would time out. A single pump is enough to mount the
        // subtree; bound the second pump to one frame so the controller can
        // advance without hanging the test.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(RankUpPulse), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT render RankUpPulse when storage.isPulsing returns false',
      (tester) async {
        final storage = _MockPulseStorage();
        when(
          () => storage.isPulsing(any(), now: any(named: 'now')),
        ).thenReturn(false);
        await tester.pumpWidget(
          _wrap(BodyPartRankRow(entry: _entry()), storage: storage),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RankUpPulse), findsNothing);
      },
    );

    testWidgets(
      'tapping the trained row navigates to /saga/stats with the body part query',
      (tester) async {
        final storage = _MockPulseStorage();
        when(
          () => storage.isPulsing(any(), now: any(named: 'now')),
        ).thenReturn(false);
        await tester.pumpWidget(
          _wrap(
            BodyPartRankRow(entry: _entry(bp: BodyPart.legs)),
            storage: storage,
          ),
        );
        await tester.pumpAndSettle();
        // Pin that there's exactly one InkWell — if a future change adds a
        // child InkWell (e.g. a nested tap target on the dot), this assertion
        // breaks first instead of the tap finding an ambiguous target.
        expect(find.byType(InkWell), findsOneWidget);
        await tester.tap(find.byType(InkWell));
        await tester.pumpAndSettle();
        // After tap, we should have landed on the /saga/stats route placeholder.
        expect(find.text('stats'), findsOneWidget);
      },
    );

    testWidgets('row min-height is at least 48dp (Material tap-target floor)', (
      tester,
    ) async {
      final storage = _MockPulseStorage();
      when(
        () => storage.isPulsing(any(), now: any(named: 'now')),
      ).thenReturn(false);
      await tester.pumpWidget(
        _wrap(
          SizedBox(width: 360, child: BodyPartRankRow(entry: _entry())),
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(BodyPartRankRow));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
