/// Widget tests for [VitalityTable] — Phase 18d.2.
///
/// The table is the live-Vitality readout on the stats deep-dive screen:
/// six rows, each row a localized body-part name + state copy + percentage
/// numeral + state-color dot. Tapping a row drives the trend chart's
/// selection above it.
///
/// **Layout-primitive locks under test (per UX-critic amendment):**
///   * Rows are NOT [ListTile]s — they're `Padding(EdgeInsets.symmetric(
///     horizontal: 16, vertical: 12))` inside a [Material]+[InkWell].
///   * The selected row sits one elevation level higher (`AppColors.surface2`)
///     vs the unselected baseline (`AppColors.abyss`).
///   * Rows are separated by `Divider(height: 1, color: AppColors.surface2)`
///     — one fewer divider than rows.
///   * The percentage is the only numeric quantity; there is no progress
///     bar next to it (anti-pattern lock #3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_table.dart';

import '../../../../helpers/test_material_app.dart';

VitalityTableRow _row({
  BodyPart bodyPart = BodyPart.chest,
  double pct = 0.5,
  VitalityState state = VitalityState.active,
  int rank = 3,
}) {
  return VitalityTableRow(
    bodyPart: bodyPart,
    pct: pct,
    state: state,
    rank: rank,
  );
}

/// Six canonical rows mirroring [activeBodyParts] order, each in a different
/// state to assert the per-row state-color rendering branches don't collapse.
List<VitalityTableRow> _sixCanonicalRows() {
  return const [
    VitalityTableRow(
      bodyPart: BodyPart.chest,
      pct: 0.92,
      state: VitalityState.radiant,
      rank: 6,
    ),
    VitalityTableRow(
      bodyPart: BodyPart.back,
      pct: 0.55,
      state: VitalityState.active,
      rank: 4,
    ),
    VitalityTableRow(
      bodyPart: BodyPart.legs,
      pct: 0.20,
      state: VitalityState.fading,
      rank: 2,
    ),
    VitalityTableRow(
      bodyPart: BodyPart.shoulders,
      pct: 0,
      state: VitalityState.dormant,
      rank: 1,
    ),
    VitalityTableRow(
      bodyPart: BodyPart.arms,
      pct: 0.40,
      state: VitalityState.active,
      rank: 3,
    ),
    VitalityTableRow(
      bodyPart: BodyPart.core,
      pct: 0.71,
      state: VitalityState.radiant,
      rank: 5,
    ),
  ];
}

Widget _wrap({
  required List<VitalityTableRow> rows,
  required BodyPart selected,
  required ValueChanged<BodyPart> onSelect,
}) {
  return TestMaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: VitalityTable(
          rows: rows,
          selectedBodyPart: selected,
          onSelect: onSelect,
        ),
      ),
    ),
  );
}

void main() {
  group('VitalityTable', () {
    testWidgets('renders one row per supplied row + (n-1) dividers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          rows: _sixCanonicalRows(),
          selected: BodyPart.chest,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      // Six body-part names show.
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Legs'), findsOneWidget);
      expect(find.text('Shoulders'), findsOneWidget);
      expect(find.text('Arms'), findsOneWidget);
      expect(find.text('Core'), findsOneWidget);

      // n-1 dividers between rows.
      expect(find.byType(Divider), findsNWidgets(5));
    });

    testWidgets('renders the percentage as `(pct*100).round()%`', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          rows: _sixCanonicalRows(),
          selected: BodyPart.chest,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      // 0.92 → 92%, 0.55 → 55%, 0.20 → 20%, 0 → 0%, 0.40 → 40%, 0.71 → 71%.
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('55%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('71%'), findsOneWidget);
    });

    testWidgets('renders the localized state copy per row', (tester) async {
      // Phase 26: marginalia copy was retired for fading/active/radiant —
      // those states are now communicated via color only. Only untested
      // and dormant retain a copy line (their dim/grey palette alone is
      // ambiguous; the copy carries the differentiation). The retired
      // states return an empty string from `localizedCopy`, which collapses
      // visually inside the row's bodySmall Text slot.
      await tester.pumpWidget(
        _wrap(
          rows: _sixCanonicalRows(),
          selected: BodyPart.chest,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      // Retired marginalia strings must not appear anywhere on screen.
      // (Negative-only guards: pinned in case a future copy edit ever
      // reintroduces these literal strings as a "zombie paste".)
      expect(find.text('Path mastered.'), findsNothing);
      expect(find.text('On the path.'), findsNothing);
      expect(
        find.text('Conditioning lost — return to the path.'),
        findsNothing,
      );

      // One dormant row (Shoulders) still renders the dormant copy.
      expect(
        find.text('Dormant. Train this group to reawaken its path.'),
        findsOneWidget,
      );

      // Positive assertion (in addition to the negative-only guards
      // above): 5 retired-state rows (radiant×2 + active×2 + fading×1)
      // have NO marginalia Text slot at all (Task 6 collapsed the empty
      // render — the row's bodySmall Text widget is now conditionally
      // rendered only when `localizedCopy` returns a non-empty string).
      // Only the dormant row keeps its non-empty subtitle Text. The
      // collapsed rows contribute zero `Text(data: '')` instances; the
      // dormant row contributes a non-empty Text. So the empty-data
      // Text count is exactly zero. If a future copy edit ever
      // reintroduces non-empty marginalia for any retired state, that
      // doesn't change this count (the new Text would have non-empty
      // data) — the negative-only guards above plus the regex
      // anchoring in the Semantics-identifier test are the
      // belt-and-suspenders against re-injection.
      final emptyTextCount = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data == '')
          .length;
      expect(
        emptyTextCount,
        0,
        reason:
            'Task 6 collapse: retired-state rows must NOT render an empty '
            'marginalia Text slot — the subtitle is omitted entirely.',
      );
    });

    testWidgets('tapping a row fires onSelect with that row\'s body part', (
      tester,
    ) async {
      final tapped = <BodyPart>[];
      await tester.pumpWidget(
        _wrap(
          rows: _sixCanonicalRows(),
          selected: BodyPart.chest,
          onSelect: tapped.add,
        ),
      );
      await tester.pump();

      // Tap the row that contains "Legs".
      await tester.tap(find.text('Legs'));
      await tester.pump();

      expect(tapped, [BodyPart.legs]);

      // Tap a second row.
      await tester.tap(find.text('Arms'));
      await tester.pump();

      expect(tapped, [BodyPart.legs, BodyPart.arms]);
    });

    testWidgets(
      'selected row sits on AppColors.surface2; siblings sit on AppColors.abyss',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            rows: _sixCanonicalRows(),
            selected: BodyPart.legs,
            onSelect: (_) {},
          ),
        );
        await tester.pump();

        // Each row has its own [Material] node — there are six. The selected
        // one should be `surface2`; the others `abyss`. We scan only the
        // Materials descended from the [VitalityTable] itself (excluding the
        // Scaffold/MaterialApp ancestor Materials that have a `null` or
        // theme-default color, not our palette tokens).
        final rowMaterials = tester
            .widgetList<Material>(
              find.descendant(
                of: find.byType(VitalityTable),
                matching: find.byType(Material),
              ),
            )
            .where(
              (m) =>
                  m.color == AppColors.surface2 || m.color == AppColors.abyss,
            )
            .toList();

        expect(rowMaterials.length, 6);

        final surface2Count = rowMaterials
            .where((m) => m.color == AppColors.surface2)
            .length;
        final abyssCount = rowMaterials
            .where((m) => m.color == AppColors.abyss)
            .length;

        // Exactly one row painted surface2 (the selected one);
        // the other five abyss.
        expect(surface2Count, 1);
        expect(abyssCount, 5);
      },
    );

    testWidgets('does not use ListTile (UX critic anti-pattern lock)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          rows: _sixCanonicalRows(),
          selected: BodyPart.chest,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets(
      'each row exposes a Semantics identifier of vitality-row-<bodyPart>',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            rows: _sixCanonicalRows(),
            selected: BodyPart.chest,
            onSelect: (_) {},
          ),
        );
        await tester.pump();

        // The container Semantics node carries the table identifier;
        // each child row carries its per-body-part identifier composed of
        // localized name + percentage + state copy. We sample two rows
        // (radiant + dormant) to cover both ends of the state range.
        //
        // Phase 26 + Task 6: radiant marginalia retired → the Chest
        // row's semantic label uses the conditional formatting from
        // `_VitalityTableRow.build`: when `stateCopy` is empty (as for
        // radiant/active/fading rows after Phase 26), the trailing
        // `, $stateCopy` is omitted entirely, so the composed prefix is
        // exactly `"Chest, 92%"` — no trailing `, `. That prefix is
        // followed by a `\n` and the descendant Text nodes that the
        // row's Semantics container merges in (name + percentage).
        //
        // Anchored with `^` + the trailing `\n` so a future regression
        // that re-injects content where the empty copy slot used to be
        // — e.g. `"Chest, 92%, Path mastered.\nChest\n92%"` — cannot
        // pass by merely containing the prefix substring. The `\n`
        // boundary structurally pins "nothing between `92%` and the
        // merged-descendant block".
        expect(find.bySemanticsLabel(RegExp(r'^Chest, 92%\n')), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Shoulders, 0%, Dormant\\. Train this group to reawaken its path\\.',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders without overflow at narrow widths', (tester) async {
      // 320 dp — the historical narrowest target. Rows must lay out inside
      // a Column without an unbounded-width crash or rendering exception.
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          rows: _sixCanonicalRows(),
          selected: BodyPart.chest,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders single-row tables without dividers', (tester) async {
      await tester.pumpWidget(
        _wrap(
          rows: [_row(bodyPart: BodyPart.core, pct: 0.5)],
          selected: BodyPart.core,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      // n-1 = 0 dividers when n = 1.
      expect(find.byType(Divider), findsNothing);
      expect(find.text('Core'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2026-05-04 untested patch — render `—` for never-trained body parts
    // -------------------------------------------------------------------------
    //
    // A brand-new account opens Stats and sees six body-part rows. Before the
    // patch every row read `0% / "Awaits your first stride."` which was ambiguous
    // (is this a failure grade?). After the patch:
    //
    //   * peak == 0  → state = untested → readout `—` + "Uncharted — log a set
    //                  to begin." copy.
    //   * peak > 0 && ewma == 0 → state = dormant → readout `0%` + the dormant
    //                              copy "Dormant. Train this group to reawaken
    //                              its path." (rewritten in Phase 26 — the
    //                              original copy "Awaits your first stride."
    //                              was Untested-state copy mislabeled as
    //                              Dormant). Regression pin: peak > 0 must NOT
    //                              route to untested.
    testWidgets('renders `—` (em-dash) and untested copy for an untested row', (
      tester,
    ) async {
      const untestedRow = VitalityTableRow(
        bodyPart: BodyPart.chest,
        pct: 0,
        state: VitalityState.untested,
        rank: 1,
      );

      await tester.pumpWidget(
        _wrap(
          rows: const [untestedRow],
          selected: BodyPart.chest,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      // Untested readout: `—`, NOT `0%`.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
      // Untested marginalia copy.
      expect(find.text('Uncharted — log a set to begin.'), findsOneWidget);
    });

    testWidgets('still renders `0%` and dormant copy for a fully-decayed row '
        '(regression pin)', (tester) async {
      // peak > 0, pct == 0 → dormant. The 2026-05-04 patch must not bleed
      // into this case — a body part the user trained once and has fully
      // decayed on still reads as a genuine 0%, not as untested.
      const dormantRow = VitalityTableRow(
        bodyPart: BodyPart.legs,
        pct: 0,
        state: VitalityState.dormant,
        rank: 2,
      );

      await tester.pumpWidget(
        _wrap(
          rows: const [dormantRow],
          selected: BodyPart.legs,
          onSelect: (_) {},
        ),
      );
      await tester.pump();

      expect(find.text('0%'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(
        find.text('Dormant. Train this group to reawaken its path.'),
        findsOneWidget,
      );
      expect(find.text('Uncharted — log a set to begin.'), findsNothing);
    });

    group('HP-drain ramp percentage coloring (Task 6)', () {
      testWidgets('should color the 100% numeral in vitalityHigh', (
        tester,
      ) async {
        const high = VitalityTableRow(
          bodyPart: BodyPart.chest,
          pct: 1.0,
          state: VitalityState.active,
          rank: 6,
        );
        await tester.pumpWidget(
          _wrap(rows: const [high], selected: BodyPart.chest, onSelect: (_) {}),
        );
        await tester.pump();

        final pctText = tester.widget<Text>(find.text('100%'));
        expect(pctText.style?.color, AppColors.vitalityHigh);
      });

      testWidgets('should color the 52% numeral in vitalityMid', (
        tester,
      ) async {
        const mid = VitalityTableRow(
          bodyPart: BodyPart.back,
          pct: 0.52,
          state: VitalityState.active,
          rank: 3,
        );
        await tester.pumpWidget(
          _wrap(rows: const [mid], selected: BodyPart.back, onSelect: (_) {}),
        );
        await tester.pump();

        final pctText = tester.widget<Text>(find.text('52%'));
        expect(pctText.style?.color, AppColors.vitalityMid);
      });

      testWidgets('should color the 28% numeral in vitalityLow', (
        tester,
      ) async {
        const low = VitalityTableRow(
          bodyPart: BodyPart.legs,
          pct: 0.28,
          state: VitalityState.fading,
          rank: 2,
        );
        await tester.pumpWidget(
          _wrap(rows: const [low], selected: BodyPart.legs, onSelect: (_) {}),
        );
        await tester.pump();

        final pctText = tester.widget<Text>(find.text('28%'));
        expect(pctText.style?.color, AppColors.vitalityLow);
      });

      testWidgets('should color the untested em-dash in textDim', (
        tester,
      ) async {
        const untested = VitalityTableRow(
          bodyPart: BodyPart.shoulders,
          pct: 0,
          state: VitalityState.untested,
          rank: 1,
        );
        await tester.pumpWidget(
          _wrap(
            rows: const [untested],
            selected: BodyPart.shoulders,
            onSelect: (_) {},
          ),
        );
        await tester.pump();

        final pctText = tester.widget<Text>(find.text('—'));
        expect(pctText.style?.color, AppColors.textDim);
      });

      testWidgets(
        'should OMIT the subtitle Text entirely for active-state rows '
        '(no empty-line gap)',
        (tester) async {
          const active = VitalityTableRow(
            bodyPart: BodyPart.chest,
            pct: 0.55,
            state: VitalityState.active,
            rank: 4,
          );
          await tester.pumpWidget(
            _wrap(
              rows: const [active],
              selected: BodyPart.chest,
              onSelect: (_) {},
            ),
          );
          await tester.pump();

          // No Text widget with empty `data` exists in the row.
          final emptyTexts = tester
              .widgetList<Text>(find.byType(Text))
              .where((t) => t.data == '')
              .toList();
          expect(emptyTexts, isEmpty);
        },
      );

      testWidgets('should KEEP the subtitle Text for dormant-state rows '
          '(non-empty copy line)', (tester) async {
        const dormant = VitalityTableRow(
          bodyPart: BodyPart.shoulders,
          pct: 0,
          state: VitalityState.dormant,
          rank: 1,
        );
        await tester.pumpWidget(
          _wrap(
            rows: const [dormant],
            selected: BodyPart.shoulders,
            onSelect: (_) {},
          ),
        );
        await tester.pump();

        expect(
          find.text('Dormant. Train this group to reawaken its path.'),
          findsOneWidget,
        );
      });
    });
  });
}
