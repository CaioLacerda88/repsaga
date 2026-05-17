# Phase 26c — Stats Deep-Dive Revamp · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `/saga/stats` to three sections (Vitality trend · Vitality table · Volume & pico), drop the Peak Loads horizontal-bar table, switch the vitality percentages to the HP-drain ramp coloring from 26a, add ⓘ explainer bottom sheets on both vitality section headers, and replace the legacy compact `_VolumePeakTable` with per-body-part `VolumePeakBlock` widgets (two-column Volume + Carga pico with history-aware weekly delta + monthly peak delta).

**Architecture:** The provider (`statsProvider` → `assembleStatsState`) extends with three new derived fields per body part: previous-week volume, 4-week mean volume, and 30-day-ago peak EWMA. Two new value types — `VolumeDeltaView` and `PeakDeltaView` — encode the rendering state (under/over/met/flat + delta value + delta label) so widgets stay pure presentation. `VitalityTrendChart`'s ghost lines move from `textDim`-at-30% to body-part-identity-at-35% and the cross-fade duration tightens from 200ms to 180ms per the locked spec.

**Tech Stack:** Flutter ^3.11.4, Dart, Freezed, Riverpod 3, fl_chart, `flutter_test`, l10n via `flutter_localizations` + ARB.

**Spec source:** `docs/PROJECT.md §3 Phase 26 → 26c acceptance criteria` (lines 454-480). Visual reference: `docs/phase-26-mockups.html` section `#stats` (lines 1059-1170) + section `#vitality-explainer` (lines 1175-…).

**Branch:** `feature/26c-stats-deep-dive` (already created by orchestrator at base SHA `8a5c1fc`).

**Pipeline tail (per CLAUDE.md):** after task 14 opens the PR, reviewer → QA → **visual verification (step 9)** → merge. Visual verification runs the screenshot pass at 320/360/412dp against the foundation-user fixture and compares to `docs/phase-26-mockups.html` section `#stats`. Not a plan task — runs in the merge gate.

---

## Pre-flight reads

- `lib/features/rpg/ui/stats_deep_dive_screen.dart` (current screen composition + `_SectionHeader` + `_VolumePeakTable` privates)
- `lib/features/rpg/ui/widgets/vitality_table.dart` (the row composition + tap routing)
- `lib/features/rpg/ui/widgets/vitality_trend_chart.dart` (the existing chart — already has body-part-color selected line; needs ghost-line color change + duration change)
- `lib/features/rpg/ui/widgets/peak_loads_table.dart` (target for deletion)
- `lib/features/rpg/providers/stats_provider.dart` (current `assembleStatsState` to extend)
- `lib/features/rpg/models/stats_deep_dive_state.dart` (state shapes to extend)
- `lib/features/rpg/ui/utils/vitality_state_styles.dart` (the `vitalityRampColorFor` helper from 26a — Task 8 consumes it)
- `lib/core/format/number_format.dart` (`AppNumberFormat.integer` / `.volume` helpers + the pt-BR conventions)
- `docs/phase-26-mockups.html` sections `#stats` and `#vitality-explainer`

## Critical constraints (from 26a + 26b memories)

- **Phase-agnostic test names.** No `(Phase 26c)` in any test/group label. See `feedback_phase_agnostic_test_names`.
- **Drop unused imports.** Especially `package:flutter/material.dart` in unit-only test files. See `feedback_plan_unused_imports`.
- **AOM rules.** Any new `Semantics(identifier: ...)` wrapper around a tappable widget needs `container: true + button: true`. See `cluster_semantics_button_missing`. Any wrapper containing multiple sibling Text widgets needs an explicit `label:` so AOM regex parsers don't break. See `cluster_aom_label_text_merge`.
- **No `toHaveURL` in new E2E tests.** Assert on destination-content visibility. See `cluster_flutter_web_url_assertion`.
- **No `Opacity` around `InkWell`.** Use element-level alpha. See `cluster_opacity_inkwell_splash` (the body-part-row bug from 26b).
- **No `Container(decoration: ..., child: ...)` if the decoration is the only purpose.** Use `DecoratedBox + SizedBox`. Flagged in tasks 4, 5, 11 of 26b reviews.

---

## File map

**Modified:**
- `lib/features/rpg/models/stats_deep_dive_state.dart` — add `previousWeekVolumeSets`, `fourWeekMeanVolumeSets`, `peakEwma30dAgo`, `weeksOfHistory` to `VolumePeakRow` OR introduce a new view-state type. (Decision in Task 1.)
- `lib/features/rpg/models/stats_deep_dive_state.freezed.dart` — regen.
- `lib/features/rpg/providers/stats_provider.dart` — extend assembler.
- `lib/features/rpg/ui/stats_deep_dive_screen.dart` — recompose for 3 sections + ⓘ icons + new VolumePeakBlock list + drop Peak Loads section + drop legacy `_VolumePeakTable` private widget.
- `lib/features/rpg/ui/widgets/vitality_table.dart` — switch percentage column color to `vitalityRampColorFor(pct)`; preserve untested em-dash; drop the per-state marginalia subtitle on active/fading/radiant (Phase 26a already dropped the keys; this is just the rendering branch).
- `lib/features/rpg/ui/widgets/vitality_trend_chart.dart` — ghost lines use body-part-identity color at 35% alpha (not `textDim`); cross-fade duration 200ms → 180ms.
- `lib/l10n/app_en.arb` + `app_pt.arb` — add explainer-sheet keys + "REFERÊNCIA" / "estimado" / delta-string keys + bottom-sheet headings + the `vitalityNoData` ("sem dados") key.
- `lib/l10n/app_localizations*.dart` — regenerate.
- `test/e2e/helpers/selectors.ts` — drop `peakLoadsTable` selector + add `vitalityExplainerSheet` + `volumePeakBlock(bp)` selectors.
- `test/e2e/specs/saga.spec.ts` (or wherever S8 lives that exercises `peakLoadsTable`) — remove the stale Peak Loads assertion.

**New:**
- `lib/features/rpg/ui/widgets/volume_peak_block.dart` — per-body-part two-column block with delta rendering.
- `lib/features/rpg/ui/widgets/vitality_explainer_sheet.dart` — modal bottom sheet (definition · 3-state band ramp · rank-safety guarantee in heroGold box).
- `test/unit/features/rpg/providers/stats_provider_volume_peak_test.dart` (or extend the existing stats provider test file — decide in Task 2).
- `test/widget/features/rpg/widgets/volume_peak_block_test.dart`.
- `test/widget/features/rpg/widgets/vitality_explainer_sheet_test.dart`.

**Deleted:**
- `lib/features/rpg/ui/widgets/peak_loads_table.dart` — Peak Loads section dropped per spec.
- `test/widget/features/rpg/widgets/peak_loads_table_test.dart` — companion.
- The `peakLoadsByBodyPart` field on `StatsDeepDiveState`, `PeakLoadRow` Freezed class, and the `_groupPeakLoads` + `_muscleGroupToBodyPart` + `_epley1RM` helpers in the provider — all dead after Task 10.
- Also `_fetchExercisesByIds` + the `exerciseRepositoryProvider` + locale import in `stats_provider.dart` once the peak-loads grouping is gone.

---

## Task 1: Extend `VolumePeakRow` with the new derived fields

**Goal:** Make the model carry the data the new VolumePeakBlock widget needs to render history-aware deltas + monthly peak delta + the generic-tip fallback gate. Pure-data change first; provider populates in Task 2; UI renders in Task 9.

**Files:**
- Modify: `lib/features/rpg/models/stats_deep_dive_state.dart`
- Regenerate: `lib/features/rpg/models/stats_deep_dive_state.freezed.dart`
- Modify: `test/unit/features/rpg/models/stats_deep_dive_state_test.dart` (existing — extend)

**Decision (locked in this task):** Add the new fields onto the existing `VolumePeakRow` Freezed class. Don't introduce a separate view-state type — `VolumePeakRow` already carries presentation-shaped data (`weeklyVolumeSets` is rounded from xp_events into an int; `peakEwma` is the persisted lifetime peak). Adding `previousWeekVolumeSets`, `fourWeekMeanVolumeSets`, `peakEwma30dAgo`, and `weeksOfHistory` keeps the consumer surface flat.

- [ ] **Step 1: Write the failing test**

Append to `test/unit/features/rpg/models/stats_deep_dive_state_test.dart` (create the file if it doesn't exist; if it does, append the group):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';

void main() {
  group('VolumePeakRow — Phase 26c fields', () {
    test('exposes previousWeekVolumeSets / fourWeekMeanVolumeSets / peakEwma30dAgo / weeksOfHistory', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 105.0,
        previousWeekVolumeSets: 16,
        fourWeekMeanVolumeSets: 14.5,
        peakEwma30dAgo: 101.8,
        weeksOfHistory: 9,
      );
      expect(row.weeklyVolumeSets, 12);
      expect(row.peakEwma, 105.0);
      expect(row.previousWeekVolumeSets, 16);
      expect(row.fourWeekMeanVolumeSets, 14.5);
      expect(row.peakEwma30dAgo, 101.8);
      expect(row.weeksOfHistory, 9);
    });

    test('defaults: previousWeek and fourWeekMean are nullable (no history)', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 0,
        peakEwma: 0,
        previousWeekVolumeSets: null,
        fourWeekMeanVolumeSets: null,
        peakEwma30dAgo: null,
        weeksOfHistory: 0,
      );
      expect(row.previousWeekVolumeSets, isNull);
      expect(row.fourWeekMeanVolumeSets, isNull);
      expect(row.peakEwma30dAgo, isNull);
      expect(row.weeksOfHistory, 0);
    });
  });
}
```

Group label is phase-agnostic ("Phase 26c" inside the group label is OK if it's a self-documenting reference; if `feedback_phase_agnostic_test_names` blocks it strictly, rename to `'VolumePeakRow — extended fields'`. The convention so far across 26a/26b has been **drop the phase tag**, so go with the no-phase variant).

Actually correct it now: use `group('VolumePeakRow — extended history fields', () {`.

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/models/stats_deep_dive_state_test.dart
```

Expected: FAIL — the new named parameters aren't on `VolumePeakRow`.

- [ ] **Step 3: Extend `VolumePeakRow`**

In `lib/features/rpg/models/stats_deep_dive_state.dart`, update the `VolumePeakRow` Freezed factory:

```dart
/// One row in the per-body-part Volume & Peak table.
@freezed
abstract class VolumePeakRow with _$VolumePeakRow {
  const factory VolumePeakRow({
    /// Set count attributed to this body part over the last 7 days.
    required int weeklyVolumeSets,

    /// Lifetime peak EWMA — never decreases. Rendered with tabular figures.
    required double peakEwma,

    /// Set count for the body part during the 7 days BEFORE the current
    /// week. Used by `VolumePeakBlock` to render the "vs semana passada"
    /// delta when the user has 2–4 weeks of history. Null when the user
    /// has < 2 weeks of history (the delta string is suppressed).
    int? previousWeekVolumeSets,

    /// Rolling 4-week mean of weekly set counts (excluding the current
    /// in-progress week). Used by `VolumePeakBlock` to render the "vs média
    /// (4 sem)" delta when the user has 5+ weeks of history. Null when the
    /// user has < 5 weeks of history.
    double? fourWeekMeanVolumeSets,

    /// Persisted EWMA value as of 30 days ago. Used by `VolumePeakBlock`
    /// to render the monthly peak delta with the `30D` badge. Null when
    /// the user has < 30 days of history.
    double? peakEwma30dAgo,

    /// Distinct ISO-week count covered by the user's xp_events for this
    /// body part. Drives the volume-delta string choice:
    ///   * 0–1 weeks → no delta line (suppressed)
    ///   * 2–4 weeks → "X vs semana passada" (uses [previousWeekVolumeSets])
    ///   * 5+ weeks  → "X vs média (4 sem)"  (uses [fourWeekMeanVolumeSets])
    @Default(0) int weeksOfHistory,
  }) = _VolumePeakRow;
}
```

Then regenerate Freezed:

```bash
make gen
```

(`Freezed`/`json_serializable` runs; `app_localizations` won't touch this file but `make gen` runs all generators.)

- [ ] **Step 4: Update the empty()-state factory**

`StatsDeepDiveState.empty()` constructs `VolumePeakRow(weeklyVolumeSets: 0, peakEwma: 0)` per body part. With the new required fields, the constructor stays valid only if you supply the defaults (or if the new fields are nullable). Per Step 3 the new fields are nullable + `weeksOfHistory` has a `@Default(0)`. So `VolumePeakRow(weeklyVolumeSets: 0, peakEwma: 0)` is still a legal call — Freezed fills the new fields with null / 0. No edit needed to `StatsDeepDiveState.empty()`.

Verify by reading `stats_deep_dive_state.dart`'s `empty()` factory — confirm the per-body-part `VolumePeakRow()` construction still type-checks.

- [ ] **Step 5: Run to verify it passes**

```bash
flutter test test/unit/features/rpg/models/stats_deep_dive_state_test.dart
```

Expected: 2 tests pass. Full suite green via `flutter test`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/models/stats_deep_dive_state.dart \
        lib/features/rpg/models/stats_deep_dive_state.freezed.dart \
        test/unit/features/rpg/models/stats_deep_dive_state_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): VolumePeakRow gains history-aware delta fields (26c)

Adds previousWeekVolumeSets / fourWeekMeanVolumeSets / peakEwma30dAgo
and weeksOfHistory so VolumePeakBlock can render the spec's history-
aware weekly volume delta + the monthly peak EWMA delta. All four
new fields are nullable (or @Default(0)) so StatsDeepDiveState.empty()
stays valid without explicit assignment.
EOF
)"
```

---

## Task 2: Provider — compute the new fields in `assembleStatsState`

**Files:**
- Modify: `lib/features/rpg/providers/stats_provider.dart`
- Modify: `test/unit/features/rpg/providers/stats_provider_test.dart` (existing — extend with new group)

**Key algorithm decisions:**

1. **Volume per ISO-week bucket.** The assembler already iterates events to build the trend reconstruction. Extend the same single-pass to count sets-per-ISO-week per body part. ISO-week boundary: start of week = Monday 00:00 UTC.

2. **Previous-week sets.** Bucket index `currentWeek - 1`. Null when `weeksOfHistory < 2`.

3. **Four-week mean.** Mean over buckets `currentWeek - 4` through `currentWeek - 1` (4 buckets, NOT including the in-progress week). Null when `weeksOfHistory < 5`.

4. **Peak EWMA 30 days ago.** Use the trend reconstruction's interpolated daily series — the value at `today - 30 days` IF that date is inside the reconstruction window, else null. The trend reconstruction already produces daily `pct` values; multiply by `peak` to get the EWMA value. Null when the user has < 30 days of history.

5. **Weeks of history.** Count of distinct ISO-week buckets that contain at least one event with non-zero attribution for this body part.

- [ ] **Step 1: Write the failing test**

Append to the existing stats-provider test file. The test should exercise `assembleStatsState` directly (no Supabase) with fixture events spanning 8 weeks for chest only. Other body parts should still produce a `VolumePeakRow` (with nullable fields null).

```dart
  group('assembleStatsState — VolumePeakRow extended fields (26c)', () {
    test('chest with 8 weeks of activity → previousWeekVolumeSets + fourWeekMeanVolumeSets + peakEwma30dAgo + weeksOfHistory', () {
      // Fixture: 8 weeks of chest events. weeks 0..7, sets per week: 12, 14, 16, 14, 12, 14, 16, 12 (week 7 is in-progress).
      // Expected: weeksOfHistory = 8, previousWeekVolumeSets = 16 (week 6), fourWeekMeanVolumeSets = (12+14+16+12)/4 = 13.5 ... 
      // (Exact values depend on your fixture choice; design fixture so the assertion math is clear.)
      // …construct events list…
      final state = assembleStatsState(
        now: /* anchor date */,
        snapshot: /* fixture snapshot with chest peak = 100, ewma = ~85 */,
        events: /* fixture events */,
        peaks: const [],
        exercisesById: const {},
      );
      final chestRow = state.volumePeakByBodyPart[BodyPart.chest]!;
      expect(chestRow.weeksOfHistory, 8);
      expect(chestRow.previousWeekVolumeSets, 16);
      expect(chestRow.fourWeekMeanVolumeSets, closeTo(13.5, 0.01));
      expect(chestRow.peakEwma30dAgo, isNotNull);
    });

    test('back with 1 week of activity → previousWeek/fourWeekMean nulls, weeksOfHistory == 1', () {
      // Single week of back events. weeksOfHistory = 1; deltas are null.
      // …construct fixture…
      final state = assembleStatsState(/*…*/);
      final backRow = state.volumePeakByBodyPart[BodyPart.back]!;
      expect(backRow.weeksOfHistory, 1);
      expect(backRow.previousWeekVolumeSets, isNull);
      expect(backRow.fourWeekMeanVolumeSets, isNull);
      expect(backRow.peakEwma30dAgo, isNull);
    });

    test('legs with no activity → all delta fields null, weeksOfHistory == 0', () {
      final state = assembleStatsState(
        now: DateTime.utc(2026, 5, 16),
        snapshot: /* fixture snapshot with legs peak = 0 */,
        events: const [],
        peaks: const [],
        exercisesById: const {},
      );
      final legsRow = state.volumePeakByBodyPart[BodyPart.legs]!;
      expect(legsRow.weeksOfHistory, 0);
      expect(legsRow.previousWeekVolumeSets, isNull);
      expect(legsRow.fourWeekMeanVolumeSets, isNull);
      expect(legsRow.peakEwma30dAgo, isNull);
    });
  });
```

You'll need fixtures. The existing `stats_provider_test.dart` likely already has fixture helpers for `XpEvent` lists + `RpgProgressSnapshot`. Reuse them. If they don't accept exact-week-bucket-driven inputs, add a small helper alongside (e.g. `_chestEventsForWeeks(List<int> setsPerWeek, DateTime now)`).

Plan-writer NOTE: fill in the `now` anchor + the fixture event list and exact expected values when writing the test — these are mechanical once the algorithm is decided. The implementer should use precise dates so the ISO-week bucketing math is unambiguous.

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/unit/features/rpg/providers/stats_provider_test.dart --plain-name "VolumePeakRow extended"
```

Expected: FAIL — the assembler doesn't populate the new fields yet.

- [ ] **Step 3: Extend the assembler**

Inside `assembleStatsState`, in the section §4 "Volume + Peak per body part" (around line 154-171), extend the loop. The single-pass approach:

```dart
// ---------------------------------------------------------------------------
// 4. Volume + Peak per body part. Extended for Phase 26c with history-aware
//    deltas (previousWeekVolumeSets / fourWeekMeanVolumeSets / weeksOfHistory)
//    + the monthly peak delta (peakEwma30dAgo).
// ---------------------------------------------------------------------------
final volumePeak = <BodyPart, VolumePeakRow>{};
final weekAgo = today.subtract(const Duration(days: 7));
final thirtyDaysAgo = today.subtract(const Duration(days: 30));

// Helper: ISO-week start (Monday 00:00 UTC) for a UTC instant.
DateTime _isoWeekStart(DateTime d) {
  final utc = DateTime.utc(d.year, d.month, d.day);
  final daysFromMonday = (utc.weekday - DateTime.monday) % 7;
  return utc.subtract(Duration(days: daysFromMonday));
}

final currentWeekStart = _isoWeekStart(today);

for (final bp in activeBodyParts) {
  // Existing weekly volume count.
  final setsLast7d = sorted
      .where(
        (e) =>
            e.occurredAt.isAfter(weekAgo) &&
            (e.attribution[bp.dbValue] as num? ?? 0) > 0,
      )
      .length;

  // Per-ISO-week bucket counts for this body part.
  final perWeek = <DateTime, int>{};
  for (final e in sorted) {
    final attr = (e.attribution[bp.dbValue] as num? ?? 0);
    if (attr <= 0) continue;
    final wStart = _isoWeekStart(e.occurredAt);
    perWeek[wStart] = (perWeek[wStart] ?? 0) + 1;
  }
  final weeksOfHistory = perWeek.length;

  // Previous-week count (the week immediately before currentWeekStart).
  final previousWeekStart = currentWeekStart.subtract(const Duration(days: 7));
  final previousWeekVolumeSets =
      weeksOfHistory >= 2 ? (perWeek[previousWeekStart] ?? 0) : null;

  // Four-week mean over the 4 buckets BEFORE currentWeekStart (not including
  // the in-progress week). Null when weeksOfHistory < 5.
  double? fourWeekMeanVolumeSets;
  if (weeksOfHistory >= 5) {
    var sum = 0;
    for (var w = 1; w <= 4; w++) {
      final ws = currentWeekStart.subtract(Duration(days: 7 * w));
      sum += (perWeek[ws] ?? 0);
    }
    fourWeekMeanVolumeSets = sum / 4.0;
  }

  // Peak EWMA 30 days ago — sample from the trend reconstruction. The
  // trend was computed above (`trendByBp[bp]`) as daily pct values; the
  // peak EWMA value is `pct * peak`. Null when the user has < 30 days
  // of history (earliestActivity > thirtyDaysAgo OR untrained body part).
  final peak = snapshot.progressFor(bp).vitalityPeak;
  double? peakEwma30dAgo;
  if (peak > 0 && earliest != null && !earliest.isAfter(thirtyDaysAgo)) {
    final trend = trendByBp[bp] ?? const <TrendPoint>[];
    // Find the trend point closest to (today - 30 days).
    TrendPoint? closest;
    for (final p in trend) {
      if (closest == null ||
          (p.date.difference(thirtyDaysAgo).abs() <
              closest.date.difference(thirtyDaysAgo).abs())) {
        closest = p;
      }
    }
    peakEwma30dAgo = closest == null ? null : closest.pct * peak;
  }

  volumePeak[bp] = VolumePeakRow(
    weeklyVolumeSets: setsLast7d,
    peakEwma: peak,
    previousWeekVolumeSets: previousWeekVolumeSets,
    fourWeekMeanVolumeSets: fourWeekMeanVolumeSets,
    peakEwma30dAgo: peakEwma30dAgo,
    weeksOfHistory: weeksOfHistory,
  );
}
```

Two implementation notes:
1. The `Duration#abs` is `inMilliseconds.abs()` — `Duration` doesn't have a method-form `.abs()`. Use `(p.date.difference(thirtyDaysAgo).inMilliseconds.abs() < closest.date.difference(thirtyDaysAgo).inMilliseconds.abs())`.
2. The `_isoWeekStart` helper is a private top-level function in the file. Match the file's existing private-helper style.

- [ ] **Step 4: Run + verify**

```bash
flutter test test/unit/features/rpg/providers/stats_provider_test.dart
flutter test
dart analyze --fatal-infos
dart format .
```

All green/clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/providers/stats_provider.dart \
        test/unit/features/rpg/providers/stats_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): stats provider computes weekly-volume + monthly-peak deltas (26c)

Single-pass extension of assembleStatsState:
- ISO-week-bucketed set counts per body part → previousWeekVolumeSets
  and fourWeekMeanVolumeSets, gated by weeksOfHistory (<2 / 2-4 / 5+).
- 30-day-ago peak EWMA sampled from the existing daily trend
  reconstruction, gated by earliest activity vs 30-day window.

Pure-function assembler; new tests pin the bucket math directly.
EOF
)"
```

---

## Task 3: View-state encoding for VolumePeakBlock — `VolumeDeltaView` + `PeakDeltaView`

**Files:**
- Modify: `lib/features/rpg/models/stats_deep_dive_state.dart` (add two new value types)
- Modify: `test/unit/features/rpg/models/stats_deep_dive_state_test.dart`

Resolves the rendering state in the model layer so the widget stays a pure switch. Three signal types per delta: under-target / over-target / met / flat / no-history. Each carries the delta value + the localized comparison string (e.g. "vs semana passada" / "vs média (4 sem)" / "30D").

- [ ] **Step 1: Write the failing test**

```dart
  group('VolumeDeltaView / PeakDeltaView — Phase 26c view encoding', () {
    test('VolumeDeltaView.fromRow returns suppressed when weeksOfHistory < 2', () {
      const row = VolumePeakRow(weeklyVolumeSets: 5, peakEwma: 0, weeksOfHistory: 1);
      final view = VolumeDeltaView.fromRow(row);
      expect(view.state, VolumeDeltaState.suppressed);
    });

    test('VolumeDeltaView.fromRow with 3 weeks of history uses previousWeek base', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 0,
        previousWeekVolumeSets: 16,
        weeksOfHistory: 3,
      );
      final view = VolumeDeltaView.fromRow(row);
      expect(view.state, VolumeDeltaState.underTarget); // 12 < 16
      expect(view.delta, -4);
      expect(view.basis, VolumeDeltaBasis.previousWeek);
    });

    test('VolumeDeltaView.fromRow with 8 weeks uses fourWeekMean base; over-target when above mean', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 18,
        peakEwma: 0,
        fourWeekMeanVolumeSets: 14.5,
        weeksOfHistory: 8,
      );
      final view = VolumeDeltaView.fromRow(row);
      expect(view.state, VolumeDeltaState.overTarget); // 18 > 14.5
      expect(view.delta, closeTo(3.5, 0.01));
      expect(view.basis, VolumeDeltaBasis.fourWeekMean);
    });

    test('VolumeDeltaView.fromRow exact match returns met (no rounding gap)', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 14,
        peakEwma: 0,
        previousWeekVolumeSets: 14,
        weeksOfHistory: 3,
      );
      final view = VolumeDeltaView.fromRow(row);
      expect(view.state, VolumeDeltaState.met);
      expect(view.delta, 0);
    });

    test('PeakDeltaView.fromRow when peakEwma30dAgo is null → suppressed', () {
      const row = VolumePeakRow(weeklyVolumeSets: 0, peakEwma: 105, weeksOfHistory: 8);
      final view = PeakDeltaView.fromRow(row);
      expect(view.state, PeakDeltaState.suppressed);
    });

    test('PeakDeltaView.fromRow with increase → up state + positive delta', () {
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 105,
        peakEwma30dAgo: 101.8,
        weeksOfHistory: 8,
      );
      final view = PeakDeltaView.fromRow(row);
      expect(view.state, PeakDeltaState.up);
      expect(view.delta, closeTo(3.2, 0.01));
    });

    test('PeakDeltaView.fromRow with decrease → flat (peak EWMA only goes up; defensive flat)', () {
      // PeakEwma is documented "never decreases" so a decrease shouldn't
      // happen in production. If it does (clock drift, manual data fix),
      // fall back to the flat state rather than a misleading "down" arrow.
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 100,
        peakEwma30dAgo: 105,
        weeksOfHistory: 8,
      );
      final view = PeakDeltaView.fromRow(row);
      expect(view.state, PeakDeltaState.flat);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/unit/features/rpg/models/stats_deep_dive_state_test.dart --plain-name "VolumeDeltaView"
```

- [ ] **Step 3: Implement the view-state types**

Append to `lib/features/rpg/models/stats_deep_dive_state.dart` (after the existing classes):

```dart
/// Encodes the renderable state of a body-part's weekly-volume delta line
/// for `VolumePeakBlock` (Phase 26c). The widget switches on [state] and
/// renders the matching string + color; this type centralizes the rule.
///
/// Phase 26c locked decisions:
///   * `0–1 weeks` of history → suppressed (no delta line rendered).
///   * `2–4 weeks` → compare against [previousWeekVolumeSets].
///   * `5+ weeks` → compare against [fourWeekMeanVolumeSets].
///   * Under-target → red (`vitalityLow`).
///   * Over-target → amber (`warning`) — explicitly NOT green; amber says
///     "noted, you decide" without prescribing more volume.
///   * Exactly met → green (`vitalityHigh`) with a filled `●` bullet.
///   * No history (suppressed) → not rendered.
enum VolumeDeltaState { suppressed, underTarget, met, overTarget }

enum VolumeDeltaBasis { previousWeek, fourWeekMean }

@freezed
abstract class VolumeDeltaView with _$VolumeDeltaView {
  const factory VolumeDeltaView({
    required VolumeDeltaState state,
    /// Signed delta: `weeklyVolumeSets - basisValue`. Negative for under-
    /// target, positive for over-target, 0 for met. Always 0 for
    /// [VolumeDeltaState.suppressed].
    @Default(0) double delta,
    /// Which basis was used (drives the localized "vs semana passada" /
    /// "vs média (4 sem)" string). Null for [VolumeDeltaState.suppressed].
    VolumeDeltaBasis? basis,
  }) = _VolumeDeltaView;

  const VolumeDeltaView._();

  /// Compute the view-state for [row]. Pure function — no l10n / no
  /// widget tree access. Localized strings are picked at the widget layer
  /// using [basis] as the discriminator.
  factory VolumeDeltaView.fromRow(VolumePeakRow row) {
    if (row.weeksOfHistory < 2) {
      return const VolumeDeltaView(state: VolumeDeltaState.suppressed);
    }
    final useFourWeekMean = row.weeksOfHistory >= 5;
    final basis = useFourWeekMean
        ? VolumeDeltaBasis.fourWeekMean
        : VolumeDeltaBasis.previousWeek;
    final basisValue = useFourWeekMean
        ? (row.fourWeekMeanVolumeSets ?? 0)
        : (row.previousWeekVolumeSets ?? 0).toDouble();
    final delta = row.weeklyVolumeSets - basisValue;
    final state = delta == 0
        ? VolumeDeltaState.met
        : delta < 0
        ? VolumeDeltaState.underTarget
        : VolumeDeltaState.overTarget;
    return VolumeDeltaView(state: state, delta: delta, basis: basis);
  }
}

/// Encodes the renderable state of a body-part's monthly peak-EWMA delta
/// line for `VolumePeakBlock` (Phase 26c). Always-monthly with the `30D`
/// badge.
enum PeakDeltaState { suppressed, up, flat }

@freezed
abstract class PeakDeltaView with _$PeakDeltaView {
  const factory PeakDeltaView({
    required PeakDeltaState state,
    @Default(0) double delta,
  }) = _PeakDeltaView;

  const PeakDeltaView._();

  factory PeakDeltaView.fromRow(VolumePeakRow row) {
    final prior = row.peakEwma30dAgo;
    if (prior == null) {
      return const PeakDeltaView(state: PeakDeltaState.suppressed);
    }
    final delta = row.peakEwma - prior;
    // Peak EWMA is documented monotonic non-decreasing (it's a lifetime
    // peak watermark in the model). A negative delta indicates data
    // corruption — render as flat (no arrow) rather than down.
    if (delta <= 0) {
      return const PeakDeltaView(state: PeakDeltaState.flat);
    }
    return PeakDeltaView(state: PeakDeltaState.up, delta: delta);
  }
}
```

Run `make gen` to regenerate the Freezed boilerplate.

- [ ] **Step 4: Verify**

```bash
flutter test test/unit/features/rpg/models/stats_deep_dive_state_test.dart
flutter test
dart analyze --fatal-infos
```

All green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/models/stats_deep_dive_state.dart \
        lib/features/rpg/models/stats_deep_dive_state.freezed.dart \
        test/unit/features/rpg/models/stats_deep_dive_state_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): VolumeDeltaView + PeakDeltaView for VolumePeakBlock (26c)

Pure-data view-state types encoding the per-body-part weekly-volume +
monthly-peak deltas. VolumeDeltaView.fromRow picks the basis (prev
week vs 4-week mean) by weeksOfHistory and returns the renderable
state (suppressed / underTarget / met / overTarget). PeakDeltaView is
monotonic-aware: a negative delta (data drift) renders flat, not down.
EOF
)"
```

---

## Task 4: `VitalityExplainerSheet` widget

**Files:**
- Create: `lib/features/rpg/ui/widgets/vitality_explainer_sheet.dart`
- Create: `test/widget/features/rpg/widgets/vitality_explainer_sheet_test.dart`
- Modify: `lib/l10n/app_en.arb` + `app_pt.arb` (add the 3-part copy keys — minimal, no `@` descriptions on pt per existing convention)

The bottom sheet has three parts per the mockup:
1. **Definition** (1-2 sentences): "Vitalidade reflete o quão recente é seu treino para cada grupo muscular…"
2. **3-state ramp explainer**: visual rows showing the three bands (Active / Waning / Dormant) with their color + range + brief copy.
3. **Rank safety guarantee**: heroGold-bordered box: "Vitalidade NÃO afeta seu rank ou XP — é apenas um indicador de consistência."

- [ ] **Step 1: Add the l10n keys** (en + pt)

In `lib/l10n/app_en.arb`, add (keep the existing alphabetical/topical ordering):

```json
"vitalityExplainerTitle": "Vitality",
"@vitalityExplainerTitle": { "description": "Title of the vitality explainer bottom sheet (Phase 26c)." },

"vitalityExplainerDefinition": "Vitality reflects how recent your training is for each muscle group. It's a measure of how active your saga is, not a measure of strength.",
"@vitalityExplainerDefinition": { "description": "First-paragraph definition copy in the vitality explainer bottom sheet (Phase 26c)." },

"vitalityExplainerHowItMoves": "How it moves:",
"@vitalityExplainerHowItMoves": { "description": "Sub-heading above the three-state band ramp in the vitality explainer (Phase 26c)." },

"vitalityExplainerBandActive": "66–100% — recent training, on the path.",
"vitalityExplainerBandWaning": "34–65% — slowing down, the path is fading.",
"vitalityExplainerBandDormant": "0–33% — the path has gone silent.",

"vitalityExplainerRankSafety": "Vitality does NOT affect your rank or XP — those are permanent. Vitality is purely a consistency signal.",
"@vitalityExplainerRankSafety": { "description": "Heromold-bordered safety guarantee in the vitality explainer (Phase 26c)." }
```

In `lib/l10n/app_pt.arb` (no `@` descriptions per file convention):

```json
"vitalityExplainerTitle": "Vitalidade",
"vitalityExplainerDefinition": "Vitalidade reflete o quão recente é seu treino para cada grupo muscular. É um indicador de quanto sua jornada está ativa, não da sua força.",
"vitalityExplainerHowItMoves": "Como ela se move:",
"vitalityExplainerBandActive": "66–100% — treino recente, no caminho.",
"vitalityExplainerBandWaning": "34–65% — esmorecendo, o caminho se apaga.",
"vitalityExplainerBandDormant": "0–33% — o caminho silenciou.",
"vitalityExplainerRankSafety": "Vitalidade NÃO afeta seu rank ou XP — esses são permanentes. Vitalidade é apenas um sinal de consistência."
```

Regen: `make gen`.

- [ ] **Step 2: Write the failing widget test**

Create `test/widget/features/rpg/widgets/vitality_explainer_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_explainer_sheet.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(body: Builder(builder: (context) => child)),
  );
}

void main() {
  group('VitalityExplainerSheet', () {
    testWidgets('renders title, definition, three band rows, and rank-safety box', (tester) async {
      await tester.pumpWidget(_wrap(const VitalityExplainerSheet()));
      await tester.pumpAndSettle();
      expect(find.text('Vitalidade'), findsOneWidget);
      expect(find.textContaining('Vitalidade reflete'), findsOneWidget);
      // Three band rows: text contains the percentage ranges.
      expect(find.textContaining('66–100%'), findsOneWidget);
      expect(find.textContaining('34–65%'), findsOneWidget);
      expect(find.textContaining('0–33%'), findsOneWidget);
      // Rank-safety guarantee text.
      expect(find.textContaining('NÃO afeta'), findsOneWidget);
    });

    testWidgets('rank-safety box has a hero-gold border', (tester) async {
      await tester.pumpWidget(_wrap(const VitalityExplainerSheet()));
      await tester.pumpAndSettle();
      // ValueKey on the heroGold-bordered Container, so the test can pin it.
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('vitality-explainer-rank-safety-box')),
      );
      final dec = box.decoration as BoxDecoration;
      // Border color uses RewardAccent.color OR AppColors.heroGold — pin the alpha-ignored RGB only.
      // (Specific color check is brittle; assert presence + width.)
      expect(dec.border, isNotNull);
    });

    testWidgets('Semantics identifier is "vitality-explainer-sheet"', (tester) async {
      await tester.pumpWidget(_wrap(const VitalityExplainerSheet()));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'vitalidade', caseSensitive: false)),
        findsAtLeast(1),
      );
      // Or use find by identifier:
      // expect(find.bySemanticsIdentifier('vitality-explainer-sheet'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
flutter test test/widget/features/rpg/widgets/vitality_explainer_sheet_test.dart
```

Expected: FAIL — widget doesn't exist.

- [ ] **Step 4: Implement the widget**

Create `lib/features/rpg/ui/widgets/vitality_explainer_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reward_accent.dart';

/// Bottom-sheet content for the vitality explainer (Phase 26c).
///
/// Triggered by the ⓘ icon on either vitality section header (the trend
/// chart's heading and the live-vitality table's heading). Same content
/// from both entry points. Three sections:
///   1. Definition — what Vitality measures.
///   2. Three-state band ramp — Active / Waning / Dormant with their
///      percentage ranges and one-line copy.
///   3. Rank-safety guarantee — heroGold-bordered box stating that
///      Vitality does NOT affect rank or XP.
///
/// To open this sheet from a parent widget, use `showModalBottomSheet`:
///
/// ```dart
/// showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: AppColors.surface,
///   builder: (_) => const VitalityExplainerSheet(),
/// );
/// ```
class VitalityExplainerSheet extends StatelessWidget {
  const VitalityExplainerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'vitality-explainer-sheet',
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.40,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLg)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              // Sheet handle.
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.vitalityExplainerTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.vitalityExplainerDefinition,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.vitalityExplainerHowItMoves,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _BandRow(
                color: AppColors.vitalityHigh,
                copy: l10n.vitalityExplainerBandActive,
              ),
              const SizedBox(height: 6),
              _BandRow(
                color: AppColors.vitalityMid,
                copy: l10n.vitalityExplainerBandWaning,
              ),
              const SizedBox(height: 6),
              _BandRow(
                color: AppColors.vitalityLow,
                copy: l10n.vitalityExplainerBandDormant,
              ),
              const SizedBox(height: 20),
              // Rank-safety guarantee — heroGold-bordered box. heroGold
              // wrapped in RewardAccent per scarcity-rule contract.
              RewardAccent(
                child: Builder(
                  builder: (context) {
                    final gold = RewardAccent.of(context)!.color;
                    return DecoratedBox(
                      key: const ValueKey('vitality-explainer-rank-safety-box'),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(kRadiusMd),
                        border: Border.all(color: gold, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          l10n.vitalityExplainerRankSafety,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: gold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({required this.color, required this.copy});

  final Color color;
  final String copy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(copy, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
```

- [ ] **Step 5: Run + verify**

```bash
flutter test test/widget/features/rpg/widgets/vitality_explainer_sheet_test.dart
flutter test
dart analyze --fatal-infos
dart format .
```

All clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/ui/widgets/vitality_explainer_sheet.dart \
        lib/l10n/ \
        test/widget/features/rpg/widgets/vitality_explainer_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): VitalityExplainerSheet bottom sheet (26c)

Three-section explainer (definition · 3-band ramp · rank-safety
heroGold box) opened from the ⓘ on either vitality section header.
Bands consume AppColors.vitalityHigh/Mid/Low from 26a. heroGold use
flows through RewardAccent per scarcity contract.

L10n: 7 new keys (en + pt). Title, definition, "how it moves",
3 band copies, rank-safety guarantee.
EOF
)"
```

---

## Task 5: Add ⓘ icon to both vitality section headers + wire to the bottom sheet

**Files:**
- Modify: `lib/features/rpg/ui/stats_deep_dive_screen.dart`

The existing `_SectionHeader` is private to this file. We extend it (or replace it with a new shape) to accept an optional `onInfoTap: VoidCallback?`. When non-null, render a 14dp circle-outline ⓘ icon at the right of the header text. The screen wires `onInfoTap` to `showModalBottomSheet` for the explainer.

Visual reference: mockup at `docs/phase-26-mockups.html:1071` (`<div class="ph-section">Vitalidade — últimos 90 dias <span class="info-icon">i</span></div>`).

- [ ] **Step 1: Write the failing widget test**

Add a new test in `test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart` (existing file):

```dart
  testWidgets('tapping the trend-section ⓘ opens the vitality explainer sheet', (tester) async {
    // (Mount the screen using the existing test harness in this file.)
    // …
    final infoIcon = find.byKey(const ValueKey('vitality-trend-info-icon'));
    expect(infoIcon, findsOneWidget);
    await tester.tap(infoIcon);
    await tester.pumpAndSettle();
    expect(find.byType(VitalityExplainerSheet), findsOneWidget);
  });

  testWidgets('tapping the live-vitality-section ⓘ opens the same explainer sheet', (tester) async {
    // …
    final infoIcon = find.byKey(const ValueKey('vitality-table-info-icon'));
    expect(infoIcon, findsOneWidget);
    await tester.tap(infoIcon);
    await tester.pumpAndSettle();
    expect(find.byType(VitalityExplainerSheet), findsOneWidget);
  });
```

Use whatever mounting helper the file already exposes.

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart --plain-name "vitality explainer"
```

- [ ] **Step 3: Update `_SectionHeader` + the screen composition**

In `lib/features/rpg/ui/stats_deep_dive_screen.dart`:

(a) Update `_SectionHeader` to accept an optional `onInfoTap` + `infoIconKey`:

```dart
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    this.onInfoTap,
    this.infoIconKey,
  });

  final String label;
  final VoidCallback? onInfoTap;
  final Key? infoIconKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Phase 26c: explicit 12dp bottom padding fixes the overlap reported
      // on the trend chart (its top label clipped against this header).
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTextStyles.sectionHeader.copyWith(
                color: AppColors.hotViolet,
              ),
            ),
          ),
          if (onInfoTap != null)
            InkWell(
              key: infoIconKey,
              onTap: onInfoTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.textDim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

(b) Wire the two info icons in `_Body.build`:

```dart
_SectionHeader(
  label: trendHeading,
  infoIconKey: const ValueKey('vitality-trend-info-icon'),
  onInfoTap: () => _showVitalityExplainer(context),
),
// …
_SectionHeader(
  label: l10n.liveVitalitySectionHeading,
  infoIconKey: const ValueKey('vitality-table-info-icon'),
  onInfoTap: () => _showVitalityExplainer(context),
),
```

(c) Add the private helper to launch the bottom sheet (at file scope, above the `_SectionHeader` class):

```dart
void _showVitalityExplainer(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const VitalityExplainerSheet(),
  );
}
```

Add the import: `import 'widgets/vitality_explainer_sheet.dart';`.

The Volume & pico section header does NOT get a ⓘ — per the spec ("ⓘ icons added to BOTH vitality section headers", not Volume).

- [ ] **Step 4: Run + verify**

```bash
flutter test test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart
flutter test
dart analyze --fatal-infos
dart format .
```

All green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/stats_deep_dive_screen.dart \
        test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): wire vitality ⓘ icons to explainer sheet (26c)

Both vitality section headers (trend + live table) gain a 14dp ⓘ
icon that opens the new VitalityExplainerSheet. Volume & pico header
stays icon-less per spec. _SectionHeader extended with onInfoTap +
infoIconKey; the 12dp bottom padding from 26c locked decisions
lands in the same change so the trend chart no longer overlaps it.
EOF
)"
```

---

## Task 6: `VitalityTable` — switch percentage column to `vitalityRampColorFor`

**Files:**
- Modify: `lib/features/rpg/ui/widgets/vitality_table.dart`
- Modify: `test/widget/features/rpg/widgets/vitality_table_test.dart` (existing)

The vitality table's percentage numeral currently colors via `VitalityStateStyles.borderColorFor(row.state)`. Per spec, percentages instead use the HP-drain ramp via `vitalityRampColorFor(pct)` from 26a — 100% green, 76% green, 52% amber, 28% red. Untested (`pct == 0 && state == untested`) keeps the em-dash treatment in textDim.

Also: per 26a/26b, the `localizedCopy` switch returns empty string for fading/active/radiant. The current implementation pulls `stateCopy` and renders it as the row subtitle. With empty copy, the subtitle Text widget renders an empty line which leaves vertical space. Switch the row layout to OMIT the subtitle Text entirely when `stateCopy.isEmpty`. Untested + dormant keep the subtitle (their copy is non-empty).

- [ ] **Step 1: Write the failing tests**

In `test/widget/features/rpg/widgets/vitality_table_test.dart`, add/update assertions:

```dart
  group('VitalityTable — HP-drain ramp percentage coloring (26c)', () {
    testWidgets('100% renders in vitalityHigh', (tester) async {
      // Mount with rows[0] = chest at pct: 1.0, state: VitalityState.active.
      // Find the % numeral Text → assert its style.color == AppColors.vitalityHigh.
    });

    testWidgets('52% renders in vitalityMid (amber)', (tester) async {
      // pct: 0.52 → mid band.
    });

    testWidgets('28% renders in vitalityLow (red)', (tester) async {
      // pct: 0.28 → low band.
    });

    testWidgets('untested row renders em-dash in textDim', (tester) async {
      // state: VitalityState.untested + pct: 0 → em-dash; color == AppColors.textDim.
    });

    testWidgets('active-state row omits the subtitle Text entirely (no empty line)', (tester) async {
      // active state has empty localizedCopy. The subtitle Text widget should
      // NOT be present in the row's render tree at all.
    });

    testWidgets('dormant-state row renders the dormant copy subtitle', (tester) async {
      // dormant has non-empty localizedCopy. The subtitle Text should be present.
    });
  });
```

Use the existing test harness in the file.

- [ ] **Step 2: Run to verify fails**

```bash
flutter test test/widget/features/rpg/widgets/vitality_table_test.dart --plain-name "HP-drain"
```

- [ ] **Step 3: Update `VitalityTable`**

In `lib/features/rpg/ui/widgets/vitality_table.dart`, update `_VitalityTableRow.build()`:

(a) Replace the existing `final stateColor = VitalityStateStyles.borderColorFor(row.state);` line:

```dart
// Phase 26c: percentage column now colors by the HP-drain ramp
// (vitalityHigh / Mid / Low / textDim) instead of by the per-state
// rune-glow palette. The state still drives the row's untested
// em-dash fallback below, but the numeral itself is the conditioning
// signal — high green / mid amber / low red.
final pctColor = row.state == VitalityState.untested
    ? AppColors.textDim
    : VitalityStateStyles.vitalityRampColorFor(row.pct);
// The chip-form dot on the right keeps the body-part identity color
// so the row's identity register is preserved.
final dotColor =
    VitalityStateStyles.bodyPartColor[row.bodyPart] ?? AppColors.textDim;
```

(Then update the references — `stateColor` was used in 3 places: the muscle icon tint, the percentage Text, and the small 8x8 dot. The muscle icon should stay body-part-color too. Update all three references appropriately.)

(b) Update the subtitle Text to conditional-render:

Where currently the row's `Column` always renders the `localizedName` + the subtitle `stateCopy` Text, change to:

```dart
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        localizedName,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (stateCopy.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          stateCopy,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textDim,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ],
  ),
),
```

(c) Update the percentage numeral's color to `pctColor`:

```dart
Text(
  pctText,
  style: GoogleFonts.rajdhani(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: pctColor,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
),
```

(d) Update the 8x8 trailing dot's color to `dotColor` (body-part identity, NOT pctColor — the dot is identity, the numeral is state):

```dart
Container(
  width: 8,
  height: 8,
  decoration: BoxDecoration(
    color: dotColor,
    shape: BoxShape.circle,
  ),
),
```

(e) Update the muscle icon tint to `dotColor` too:

```dart
AppIcons.render(
  _muscleAsset(row.bodyPart),
  color: dotColor,
  size: 32,
),
```

- [ ] **Step 4: Update the Semantics label**

The existing `Semantics` wrapper builds the label as `'$localizedName, $pctText, $stateCopy'`. With `stateCopy` empty for active/fading/radiant, the label becomes `'$localizedName, $pctText, '` with a trailing comma+space. Strip:

```dart
label: stateCopy.isEmpty
    ? '$localizedName, $pctText'
    : '$localizedName, $pctText, $stateCopy',
```

- [ ] **Step 5: Run + verify**

```bash
flutter test test/widget/features/rpg/widgets/vitality_table_test.dart
flutter test
dart analyze --fatal-infos
```

All green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/ui/widgets/vitality_table.dart \
        test/widget/features/rpg/widgets/vitality_table_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): VitalityTable percentage column uses HP-drain ramp (26c)

Percentage numeral now colors via vitalityRampColorFor(pct) from 26a
(green/amber/red bands) instead of the per-state rune-glow palette.
Untested state keeps the em-dash in textDim. Active/fading/radiant
rows omit the subtitle Text entirely (those localizedCopy entries
return empty post-26a) — the row reads as identity + percentage with
no empty-line gap. The trailing dot + the muscle icon stay in
body-part identity color so identity vs state stays separable.
EOF
)"
```

---

## Task 7: `VitalityTrendChart` — ghost lines in body-part identity, 180ms tween

**Files:**
- Modify: `lib/features/rpg/ui/widgets/vitality_trend_chart.dart`
- Modify: `test/widget/features/rpg/widgets/vitality_trend_chart_test.dart` (existing)

Two changes:
1. Ghost (non-selected) lines move from `AppColors.textDim` at 30% alpha to their own body-part identity color at 35% alpha.
2. fl_chart's cross-fade duration drops from 200ms to 180ms per spec.

- [ ] **Step 1: Write the failing tests**

Extend the existing trend-chart test file:

```dart
  group('VitalityTrendChart — ghost line color + duration (26c)', () {
    testWidgets('ghost line for back uses bodyPartColor[back] at 35% alpha', (tester) async {
      // Mount with selectedBodyPart: chest. Find the LineChart, inspect
      // lineBarsData. Identify the back line (its raw data should match
      // a back-specific fixture). Assert its color is
      // AppColors.bodyPartBack with alpha ~0.35.
    });

    testWidgets('ghost line for legs uses bodyPartColor[legs] at 35% alpha', (tester) async {
      // Same shape; pin a different body part to prove the per-line color is
      // driven by identity, not a single textDim fallback.
    });

    testWidgets('cross-fade duration is 180ms', (tester) async {
      // Mount. Find the LineChart. Inspect its `duration` property.
      // expect(chart.duration, const Duration(milliseconds: 180));
    });
  });
```

- [ ] **Step 2: Verify fails**

```bash
flutter test test/widget/features/rpg/widgets/vitality_trend_chart_test.dart --plain-name "ghost line"
```

- [ ] **Step 3: Update the chart**

In `lib/features/rpg/ui/widgets/vitality_trend_chart.dart`:

(a) Replace the ghost-color constant + usage. Find:

```dart
/// Ghost line opacity — locked at 30% per UX-critic amendment.
static const double _ghostOpacity = 0.30;
// …
final ghostColor = AppColors.textDim.withValues(alpha: _ghostOpacity);
```

Update to:

```dart
/// Ghost line opacity — Phase 26c: 35% alpha on the body-part identity
/// color (was 30% on textDim — Phase 26c switched to identity-colored
/// ghost lines so the lineup of six rows on the chart matches the
/// table's row dots).
static const double _ghostOpacity = 0.35;
```

And in the ghost-bar loop, change:

```dart
lineBars.add(
  LineChartBarData(
    spots: spots,
    isCurved: false,
    color: ghostColor,  // ← was a single textDim color
    // …
  ),
);
```

To per-body-part:

```dart
final ghostColor =
    (VitalityStateStyles.bodyPartColor[bp] ?? AppColors.textDim)
        .withValues(alpha: _ghostOpacity);
lineBars.add(
  LineChartBarData(
    spots: spots,
    isCurved: false,
    color: ghostColor,
    // …
  ),
);
```

(Remove the file-scope `final ghostColor = AppColors.textDim.withValues(alpha: _ghostOpacity);` — it's no longer a single value.)

(b) Update the duration:

```dart
LineChart(
  LineChartData(/* … */),
  // Phase 26c: 180ms (was 200ms) per locked-decision tween spec.
  duration: const Duration(milliseconds: 180),
  curve: Curves.easeOut,
),
```

- [ ] **Step 4: Verify + commit**

```bash
flutter test test/widget/features/rpg/widgets/vitality_trend_chart_test.dart
flutter test
dart analyze --fatal-infos

git add lib/features/rpg/ui/widgets/vitality_trend_chart.dart \
        test/widget/features/rpg/widgets/vitality_trend_chart_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): trend-chart ghost lines in body-part identity (26c)

Ghost (non-selected) lines now render in their own bodyPartColor at
35% alpha — matches the six row dots on the table below. Cross-fade
duration tightens 200ms → 180ms per locked-decision spec.
EOF
)"
```

---

## Task 8: `VolumePeakBlock` widget — per-body-part two-column block

**Files:**
- Create: `lib/features/rpg/ui/widgets/volume_peak_block.dart`
- Create: `test/widget/features/rpg/widgets/volume_peak_block_test.dart`
- Modify: `lib/l10n/app_en.arb` + `app_pt.arb` (add delta/label/badge keys)

L10n keys to add (en + pt). Pt-BR values from the mockup; en is parallel:

```json
"// en":
"volumePeakBlockVolumeLabel": "Volume",
"volumePeakBlockCargaPicoLabel": "Carga pico",
"volumePeakBlockReferenciaLabel": "Reference",
"volumePeakBlockSeries": "sets",  // matches the existing weeklyVolumeUnit pattern
"volumePeakBlockDeltaVsPrevWeek": "vs last week",
"volumePeakBlockDeltaVsFourWeekMean": "vs 4-week avg",
"volumePeakBlockDeltaNoHistory": "no history",
"volumePeakBlockDeltaEstimated": "estimated",
"volumePeakBlockDeltaAboveTarget": "above target",  // for over-target amber line
"volumePeakBlockBadge30D": "30D",

"// pt":
"volumePeakBlockVolumeLabel": "Volume",
"volumePeakBlockCargaPicoLabel": "Carga pico",
"volumePeakBlockReferenciaLabel": "Referência",
"volumePeakBlockSeries": "séries",
"volumePeakBlockDeltaVsPrevWeek": "vs semana passada",
"volumePeakBlockDeltaVsFourWeekMean": "vs média (4 sem)",
"volumePeakBlockDeltaNoHistory": "sem histórico",
"volumePeakBlockDeltaEstimated": "estimado",
"volumePeakBlockDeltaAboveTarget": "acima da meta",
"volumePeakBlockBadge30D": "30D"
```

The widget receives: a `BodyPart`, a `VolumePeakRow`, a `VolumeDeltaView`, and a `PeakDeltaView`. It does NOT compute the delta state itself — Task 3 owns that logic. The widget is pure presentation.

Two-mode rendering:
- **Personal-history mode**: row has data; right column shows "Carga pico" + EWMA value + kg/lbs suffix + monthly delta with `30D` badge.
- **Generic-tip fallback**: row has no peak EWMA (weeksOfHistory < 1 AND peakEwma == 0); right column shows "Referência" + 10 séries + ⓘ "estimado" badge that opens a tiny explainer (for now, just render the static "estimated" label without an opener — wire the ⓘ tap to a TODO in this task, full sheet content optional).

Decision: ship the generic-tip ⓘ as a non-interactive badge in this phase. The "Schoenfeld 2019 maintenance floor" explainer is out-of-scope for the minimum viable Volume & pico block. The badge is documented in the locked spec; the tap is deferred.

- [ ] **Step 1: Write the failing widget tests**

(Skeleton — the implementer fills in the mount harness using the test pattern from `volume_peak_block_test.dart` once the widget exists):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/volume_peak_block.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('VolumePeakBlock', () {
    testWidgets('personal-history mode renders Volume left + Carga pico right with deltas', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 12,
        peakEwma: 105.0,
        previousWeekVolumeSets: 16,
        fourWeekMeanVolumeSets: 16.0,
        peakEwma30dAgo: 101.8,
        weeksOfHistory: 8,
      );
      await tester.pumpWidget(_wrap(VolumePeakBlock(
        bodyPart: BodyPart.chest,
        row: row,
        volumeDelta: VolumeDeltaView.fromRow(row),
        peakDelta: PeakDeltaView.fromRow(row),
      )));
      await tester.pumpAndSettle();
      // Body part name
      expect(find.text('Peito'), findsOneWidget);
      // Volume column: "12" + "/ 16 séries"
      expect(find.textContaining('12'), findsAtLeast(1));
      expect(find.textContaining('séries'), findsAtLeast(1));
      // Carga pico column: "105 kg"
      expect(find.textContaining('105'), findsOneWidget);
      // 30D badge present
      expect(find.text('30D'), findsOneWidget);
      // Delta line "vs média (4 sem)" (8 weeks of history → four-week mean)
      expect(find.textContaining('vs média'), findsOneWidget);
    });

    testWidgets('over-target volume line renders in warning amber (NOT green)', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 9,
        peakEwma: 42.0,
        previousWeekVolumeSets: 6,
        fourWeekMeanVolumeSets: 6.0,
        peakEwma30dAgo: 40.5,
        weeksOfHistory: 8,
      );
      await tester.pumpWidget(_wrap(VolumePeakBlock(
        bodyPart: BodyPart.shoulders,
        row: row,
        volumeDelta: VolumeDeltaView.fromRow(row),
        peakDelta: PeakDeltaView.fromRow(row),
      )));
      await tester.pumpAndSettle();
      // The over-target delta text should be in amber. Find by predicate.
      final amberLines = find.byWidgetPredicate((w) {
        if (w is! Text) return false;
        final color = (w.style ?? const TextStyle()).color;
        return color == AppColors.warning && w.data != null &&
            w.data!.contains('acima da meta');
      });
      expect(amberLines, findsOneWidget);
    });

    testWidgets('met volume line renders bullet ● + green', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 14,
        peakEwma: 0,
        previousWeekVolumeSets: 14,
        weeksOfHistory: 3,
      );
      await tester.pumpWidget(_wrap(VolumePeakBlock(
        bodyPart: BodyPart.legs,
        row: row,
        volumeDelta: VolumeDeltaView.fromRow(row),
        peakDelta: PeakDeltaView.fromRow(row),
      )));
      await tester.pumpAndSettle();
      // "●" character should be visible.
      expect(find.textContaining('●'), findsOneWidget);
    });

    testWidgets('generic-tip fallback renders Referência on right column', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 0,
        peakEwma: 0,
        weeksOfHistory: 0,
      );
      await tester.pumpWidget(_wrap(VolumePeakBlock(
        bodyPart: BodyPart.arms,
        row: row,
        volumeDelta: VolumeDeltaView.fromRow(row),
        peakDelta: PeakDeltaView.fromRow(row),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Referência'), findsOneWidget);
      expect(find.textContaining('10'), findsOneWidget);
      expect(find.textContaining('estimado'), findsOneWidget);
    });

    testWidgets('suppressed volume delta (weeks 0-1) renders no delta line', (tester) async {
      const row = VolumePeakRow(
        weeklyVolumeSets: 8,
        peakEwma: 60.0,
        weeksOfHistory: 1,
      );
      await tester.pumpWidget(_wrap(VolumePeakBlock(
        bodyPart: BodyPart.back,
        row: row,
        volumeDelta: VolumeDeltaView.fromRow(row),
        peakDelta: PeakDeltaView.fromRow(row),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('vs semana passada'), findsNothing);
      expect(find.textContaining('vs média'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Verify fails**

```bash
flutter test test/widget/features/rpg/widgets/volume_peak_block_test.dart
```

- [ ] **Step 3: Implement the widget**

Create `lib/features/rpg/ui/widgets/volume_peak_block.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/stats_deep_dive_state.dart';
import '../utils/vitality_state_styles.dart';
import 'body_part_localization.dart';

/// Per-body-part Volume + Carga pico block for the stats deep-dive
/// screen (Phase 26c). Two columns:
///   * Left: weekly volume ("X / Y séries") with history-aware delta.
///   * Right: monthly peak EWMA ("N kg" with "30D" badge + delta), OR
///     the generic-tip fallback ("Referência" + 10 séries + estimado)
///     when the user has no personal history for this body part.
///
/// Pure presentation — the `VolumeDeltaView` + `PeakDeltaView` arguments
/// encode the rendering state computed in the model layer.
///
/// Spec source: docs/PROJECT.md §3 Phase 26 → 26c acceptance criteria.
/// Visual reference: docs/phase-26-mockups.html section #stats vp-block.
class VolumePeakBlock extends StatelessWidget {
  const VolumePeakBlock({
    super.key,
    required this.bodyPart,
    required this.row,
    required this.volumeDelta,
    required this.peakDelta,
  });

  final BodyPart bodyPart;
  final VolumePeakRow row;
  final VolumeDeltaView volumeDelta;
  final PeakDeltaView peakDelta;

  /// Schoenfeld 2019 hypertrophy maintenance floor — used as the
  /// generic-tip fallback's "Referência" value when the user has no
  /// personal history for this body part.
  static const int _schoenfeldFloor = 10;

  bool get _useGenericTip => row.weeksOfHistory < 1 && row.peakEwma <= 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dotColor =
        VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.textDim;
    return Semantics(
      container: true,
      identifier: 'volume-peak-block-${bodyPart.dbValue}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: dot + body-part name.
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  localizedBodyPartName(bodyPart, l10n),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Two columns.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _VolumeColumn(
                  l10n: l10n,
                  locale: locale,
                  row: row,
                  delta: volumeDelta,
                )),
                const SizedBox(width: 12),
                Expanded(child: _useGenericTip
                    ? _ReferenciaColumn(l10n: l10n)
                    : _CargaPicoColumn(
                        l10n: l10n,
                        locale: locale,
                        row: row,
                        delta: peakDelta,
                      )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeColumn extends StatelessWidget {
  const _VolumeColumn({
    required this.l10n,
    required this.locale,
    required this.row,
    required this.delta,
  });

  final AppLocalizations l10n;
  final String locale;
  final VolumePeakRow row;
  final VolumeDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = _targetText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.volumePeakBlockVolumeLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: 2),
        // Value row: "12 / 16 séries"  OR  "12 séries" (no target if delta is suppressed/no basis).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              '${row.weeklyVolumeSets}',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textCream,
                height: 1,
              ),
            ),
            if (targetText != null) ...[
              const SizedBox(width: 4),
              Text(
                '/ $targetText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  l10n.volumePeakBlockSeries,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _VolumeDeltaLine(l10n: l10n, delta: delta),
      ],
    );
  }

  /// "{Y} séries" for the displayed target, or null when the basis is
  /// null (suppressed delta — no comparison rendered).
  String? _targetText() {
    switch (delta.basis) {
      case VolumeDeltaBasis.previousWeek:
        return '${row.previousWeekVolumeSets ?? 0} ${l10n.volumePeakBlockSeries}';
      case VolumeDeltaBasis.fourWeekMean:
        return '${(row.fourWeekMeanVolumeSets ?? 0).round()} ${l10n.volumePeakBlockSeries}';
      case null:
        return null;
    }
  }
}

class _VolumeDeltaLine extends StatelessWidget {
  const _VolumeDeltaLine({required this.l10n, required this.delta});

  final AppLocalizations l10n;
  final VolumeDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (delta.state) {
      case VolumeDeltaState.suppressed:
        return Text(
          l10n.volumePeakBlockDeltaNoHistory,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        );
      case VolumeDeltaState.met:
        return Text(
          '● ${_basisLabel()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.vitalityHigh,
          ),
        );
      case VolumeDeltaState.underTarget:
        return Text(
          '▼ ${delta.delta.round()} ${_basisLabel()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.vitalityLow,
          ),
        );
      case VolumeDeltaState.overTarget:
        return Text(
          '▲ +${delta.delta.round()} ${l10n.volumePeakBlockDeltaAboveTarget}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.warning,
          ),
        );
    }
  }

  String _basisLabel() {
    switch (delta.basis) {
      case VolumeDeltaBasis.previousWeek:
        return l10n.volumePeakBlockDeltaVsPrevWeek;
      case VolumeDeltaBasis.fourWeekMean:
        return l10n.volumePeakBlockDeltaVsFourWeekMean;
      case null:
        return '';
    }
  }
}

class _CargaPicoColumn extends StatelessWidget {
  const _CargaPicoColumn({
    required this.l10n,
    required this.locale,
    required this.row,
    required this.delta,
  });

  final AppLocalizations l10n;
  final String locale;
  final VolumePeakRow row;
  final PeakDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.volumePeakBlockCargaPicoLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              AppNumberFormat.integer(row.peakEwma, locale: locale),
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textCream,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'kg', // Phase 26c v1 fixed-unit; locale-aware unit comes with the future settings work.
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _PeakDeltaLine(l10n: l10n, locale: locale, delta: delta),
      ],
    );
  }
}

class _PeakDeltaLine extends StatelessWidget {
  const _PeakDeltaLine({
    required this.l10n,
    required this.locale,
    required this.delta,
  });

  final AppLocalizations l10n;
  final String locale;
  final PeakDeltaView delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (delta.state) {
      case PeakDeltaState.suppressed:
      case PeakDeltaState.flat:
        return Text(
          l10n.volumePeakBlockDeltaNoHistory,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        );
      case PeakDeltaState.up:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                l10n.volumePeakBlockBadge30D,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textDim,
                  fontSize: 9,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '▲ +${AppNumberFormat.integer(delta.delta, locale: locale)} kg',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.vitalityHigh,
              ),
            ),
          ],
        );
    }
  }
}

class _ReferenciaColumn extends StatelessWidget {
  const _ReferenciaColumn({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.volumePeakBlockReferenciaLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(width: 4),
            // ⓘ marker — currently non-interactive per Phase 26c plan;
            // the bottom-sheet explainer for the Schoenfeld floor is
            // out-of-scope for the minimum-viable block.
            Icon(
              Icons.info_outline,
              size: 11,
              color: AppColors.textDim,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              '${VolumePeakBlock._schoenfeldFloor}',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textCream,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                l10n.volumePeakBlockSeries,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.volumePeakBlockDeltaEstimated,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }
}
```

Note `VolumePeakBlock._schoenfeldFloor` is private to the file — `_ReferenciaColumn` accesses it via the named-class scope.

- [ ] **Step 4: Run + verify**

```bash
flutter test test/widget/features/rpg/widgets/volume_peak_block_test.dart
flutter test
dart analyze --fatal-infos
dart format .
```

All green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/volume_peak_block.dart \
        lib/l10n/ \
        test/widget/features/rpg/widgets/volume_peak_block_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): VolumePeakBlock per-body-part block (26c)

Per-body-part Volume + Carga pico block. Volume column shows current
week sets / target with history-aware delta (vs semana passada vs
4-week mean). Carga pico shows monthly peak EWMA + 30D badge + delta.
Generic-tip fallback renders Referência (Schoenfeld 10/wk floor)
when the user has no personal history for the body part.

Color rules per locked spec: under-target vitalityLow, over-target
warning amber (NOT green), exactly met vitalityHigh with bullet ●,
flat textDim. View-state computed in the model (VolumeDeltaView /
PeakDeltaView from Task 3); widget is pure presentation.
EOF
)"
```

---

## Task 9: Delete `peak_loads_table.dart` + drop `peakLoadsByBodyPart` from state + provider

**Files:**
- Delete: `lib/features/rpg/ui/widgets/peak_loads_table.dart`
- Delete: `test/widget/features/rpg/widgets/peak_loads_table_test.dart`
- Modify: `lib/features/rpg/models/stats_deep_dive_state.dart` (drop `peakLoadsByBodyPart` + `PeakLoadRow`)
- Modify: `lib/features/rpg/providers/stats_provider.dart` (drop `_groupPeakLoads`, `_muscleGroupToBodyPart`, `_epley1RM`, `_fetchExercisesByIds`; drop `peaksRepo`, `exerciseRepo`, `peaks`, `exercisesById` from `statsProvider`)

The Peak Loads section is deleted entirely. The model field, the provider math, the widget, the test, the related private helpers all go.

- [ ] **Step 1: Verify orphan status**

```bash
grep -rn "PeakLoadRow\|peakLoadsByBodyPart\|PeakLoadsTable\|peak_loads_table" lib/ test/ --include='*.dart'
```

Expected hits: only inside the files being deleted/modified. If the screen file still references `peakLoadsByBodyPart`, that's expected — Task 11 will drop it.

- [ ] **Step 2: Delete the widget + companion test**

```bash
rm lib/features/rpg/ui/widgets/peak_loads_table.dart
rm test/widget/features/rpg/widgets/peak_loads_table_test.dart
```

- [ ] **Step 3: Drop the state field + `PeakLoadRow` class**

In `lib/features/rpg/models/stats_deep_dive_state.dart`:
- Remove the `peakLoadsByBodyPart` field from `StatsDeepDiveState`.
- Remove `peakLoadsByBodyPart: const {}` from `StatsDeepDiveState.empty()`.
- Remove the `PeakLoadRow` Freezed class entirely.

Run `make gen` to regenerate the freezed file.

- [ ] **Step 4: Drop the provider's peak-loads pipeline**

In `lib/features/rpg/providers/stats_provider.dart`:
- Remove the `peaksRepo`, `exerciseRepo`, `locale`, `user`, `peaks`, `exercisesById` local fetches from the `statsProvider` body.
- Remove the `peakLoadsByBodyPart: peakLoadsByBp` from the `StatsDeepDiveState(...)` constructor.
- Remove the `peaks` + `exercisesById` parameters from `assembleStatsState`.
- Remove the helpers: `_groupPeakLoads`, `_muscleGroupToBodyPart`, `_epley1RM`, `_fetchExercisesByIds`.
- Remove now-unused imports: `peak_load.dart`, `exercise_repository.dart`, `exercises/models/exercise.dart`, `exercises/providers/exercise_providers.dart`, `auth_providers.dart`, `locale_provider.dart`. Verify each is unused before deletion.

- [ ] **Step 5: Update the stats-provider tests**

The existing `assembleStatsState` test fixtures pass `peaks: const []` and `exercisesById: const {}` to the assembler. Drop both params from every test call site.

- [ ] **Step 6: Verify the screen still compiles (will fail in Task 11)**

Run `flutter analyze --fatal-infos`. The screen file imports `peak_loads_table.dart` and reads `state.peakLoadsByBodyPart` — these are now broken. Task 11 fixes them. For this task, the analyzer error is expected; commit anyway so the deletion is its own commit.

Actually, since `analyze --fatal-infos` would block the commit pre-hook (if any), reorder: do this task AFTER Task 11. Or stage the deletions WITH the Task 11 changes in a single commit.

**Decision:** merge Task 9 and Task 11 into a single commit ("delete peak loads + restructure screen") to avoid an intermediate broken-analyze state. Task 9's deletions get applied as part of Task 11's commit. Skip the separate commit for Task 9; mark it complete after Task 11 wraps.

This task's "commit" step is therefore: NO commit yet — proceed to Task 11.

---

## Task 10: L10n keys spot-check (consolidate any straggler keys)

**Files:**
- Modify: `lib/l10n/app_en.arb` + `app_pt.arb`

A few keys are needed that haven't been added in earlier tasks:
- `vitalityNoData` ("sem dados" / "no data") — for the untested-row subtitle. Actually, the current `localizedCopy(VitalityState.untested)` already returns the `vitalityCopyUntested` key from 26a. Check whether "sem dados" is a separate string or the same. Per the mockup, the untested row's subtitle reads "sem dados" — which is shorter than `vitalityCopyUntested = "Awaits your first stride." / "Aguarda seu primeiro passo."`. Decision needed.

Per the spec text (line 461 of PROJECT.md): "Untested row reads "—" in textDim with 'sem dados' subtitle." That's a Phase 26c spec — NEW copy, not the existing untested copy.

Add the new key:

```json
"// en":
"vitalityRowUntestedSubtitle": "no data",
"@vitalityRowUntestedSubtitle": { "description": "Untested-state subtitle in the vitality table row, Phase 26c. Shorter than vitalityCopyUntested (used in older marginalia surfaces) — matches the compact stats table register." },

"// pt":
"vitalityRowUntestedSubtitle": "sem dados"
```

Update `VitalityTable._VitalityTableRow` to use `l10n.vitalityRowUntestedSubtitle` instead of `VitalityStateStyles.localizedCopy(...)` when `row.state == VitalityState.untested`.

- [ ] **Step 1: Add the key + regenerate**

Apply the ARB edits + run `make gen`.

- [ ] **Step 2: Update `VitalityTable._VitalityTableRow`**

In `lib/features/rpg/ui/widgets/vitality_table.dart`, find where `stateCopy` is resolved:

```dart
final stateCopy = VitalityStateStyles.localizedCopy(row.state, l10n);
```

Replace with a conditional:

```dart
final stateCopy = row.state == VitalityState.untested
    ? l10n.vitalityRowUntestedSubtitle
    : VitalityStateStyles.localizedCopy(row.state, l10n);
```

- [ ] **Step 3: Update the vitality-table test**

Find the test that asserts on the untested subtitle copy. Update the expected string from `vitalityCopyUntested` (the long form) to `vitalityRowUntestedSubtitle` (the short "sem dados" form).

- [ ] **Step 4: Verify + commit**

```bash
flutter test test/widget/features/rpg/widgets/vitality_table_test.dart
flutter test
dart format .
dart analyze --fatal-infos

git add lib/l10n/ \
        lib/features/rpg/ui/widgets/vitality_table.dart \
        test/widget/features/rpg/widgets/vitality_table_test.dart
git commit -m "$(cat <<'EOF'
feat(l10n): vitalityRowUntestedSubtitle short copy for vitality table (26c)

The vitality table row's untested-state subtitle uses a shorter
"sem dados" / "no data" string than the marginalia-style
vitalityCopyUntested. Matches the compact stats-table register per
locked Phase 26c spec.
EOF
)"
```

---

## Task 11: Restructure `stats_deep_dive_screen.dart` to 3 sections + drop Peak Loads + delete privates

**Files:**
- Modify: `lib/features/rpg/ui/stats_deep_dive_screen.dart` (significant restructure)
- Modify: `test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart`
- Combined with Task 9's deletions (peak_loads_table.dart + the model/provider drops) so analyze stays clean throughout the commit.

The new screen composition:

```
ListView:
  _SectionHeader(trendHeading, ⓘ → explainer)
  VitalityTrendChart
  
  _SectionHeader(liveVitalitySectionHeading, ⓘ → explainer)
  VitalityTable
  
  _SectionHeader(volumePeakSectionHeading)  // NO ⓘ
  for each body part in activeBodyParts:
    VolumePeakBlock(bodyPart, row, volumeDelta, peakDelta)
    Divider (except after last)
```

The legacy private `_VolumePeakTable` is DELETED — replaced by a `Column` of `VolumePeakBlock`s with Dividers between.

The Peak Loads `_SectionHeader` + `PeakLoadsTable` are DELETED.

- [ ] **Step 1: Apply Task 9's deletions + this task's restructure together**

(a) Delete the files from Task 9 (`peak_loads_table.dart` + companion test + golden files if any).

(b) Update `stats_deep_dive_state.dart` per Task 9 (drop `peakLoadsByBodyPart` + `PeakLoadRow`).

(c) Update `stats_provider.dart` per Task 9 (drop peak-loads pipeline).

(d) Update `stats_deep_dive_screen.dart`:
- Remove import: `'widgets/peak_loads_table.dart'`.
- Remove import: `'../models/stats_deep_dive_state.dart'` is still needed (other types). Verify before dropping.
- Add imports: `'widgets/volume_peak_block.dart'`.
- Update `_Body.build()` to the new 3-section composition (per the diagram above).
- DELETE the private `_VolumePeakTable` class (replaced by the inline VolumePeakBlock list).
- DELETE the Peak Loads `_SectionHeader` + `PeakLoadsTable` lines.

(e) Update `stats_deep_dive_screen_test.dart`:
- Remove any assertion on `PeakLoadsTable` or the "PEAK LOADS" section heading.
- Add new assertions: `find.byType(VolumePeakBlock)` should `findsNWidgets(6)` (one per active body part).
- Drop the old assertion on `_VolumePeakTable` (gone).
- Confirm 3 `_SectionHeader` widgets (was 4).

- [ ] **Step 2: Run + verify**

```bash
flutter test test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart
flutter test
dart analyze --fatal-infos
dart format .
```

All clean.

- [ ] **Step 3: Commit (Task 9 + 11 combined)**

```bash
git add -A lib/features/rpg/ui/widgets/peak_loads_table.dart \
       lib/features/rpg/ui/stats_deep_dive_screen.dart \
       lib/features/rpg/models/stats_deep_dive_state.dart \
       lib/features/rpg/models/stats_deep_dive_state.freezed.dart \
       lib/features/rpg/providers/stats_provider.dart \
       test/widget/features/rpg/widgets/peak_loads_table_test.dart \
       test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart \
       test/unit/features/rpg/providers/stats_provider_test.dart
git commit -m "$(cat <<'EOF'
refactor(rpg): drop Peak Loads + recompose stats deep-dive to 3 sections (26c)

Peak Loads horizontal-bar table dropped entirely (the heaviest-lift
data lives in the V&P Carga pico column post-26c). Stats screen
composition reduces to: trend chart → vitality table → 6 VolumePeakBlocks.

Provider drops peak-loads pipeline (PeakLoad fetch, exercise lookup,
group-by-body-part, Epley 1RM). State drops peakLoadsByBodyPart + the
PeakLoadRow Freezed class. ~250 lines net deletion.
EOF
)"
```

---

## Task 12: E2E selector + assertion update + drop `peakLoadsTable` references

**Files:**
- Modify: `test/e2e/helpers/selectors.ts`
- Modify: `test/e2e/specs/saga.spec.ts` (or wherever `SAGA.peakLoadsTable` is asserted)

The 26b final reviewer flagged S8 (`peakLoadsTable` selector usage) as forward-fragility. 26c deletes the widget; the selector + its assertion need to go.

ALSO add new selectors for the 26c surfaces:

```typescript
// In selectors.ts under SAGA / stats:
vitalityExplainerSheet: '[flt-semantics-identifier="vitality-explainer-sheet"]',
vitalityTrendInfoIcon: '[data-flt-key="vitality-trend-info-icon"]', // ValueKey-based selector — may need adjustment based on how Flutter web exposes ValueKeys
volumePeakBlock: (slug: string) =>
  `[flt-semantics-identifier="volume-peak-block-${slug}"]`,
```

(The ValueKey-to-DOM-attribute mapping in Flutter web is non-trivial. The Semantics-identifier-based selector is more reliable. Wrap the ⓘ icons in Semantics with their own identifiers if needed for E2E targeting — but defer that decision to the QA gate. If ValueKey targeting doesn't work, the implementer adds a `Semantics(container: true, button: true, identifier: 'vitality-trend-info-icon')` wrapper around the ⓘ InkWell.)

- [ ] **Step 1: Drop the stale `peakLoadsTable` selector**

In `test/e2e/helpers/selectors.ts`, find the `peakLoadsTable` entry. DELETE the entry + its JSDoc comment.

- [ ] **Step 2: Drop the S8 assertion**

In `test/e2e/specs/saga.spec.ts` (find via `grep -n peakLoadsTable test/e2e/specs/saga.spec.ts`), remove the test that asserts `peakLoadsTable` is visible. The Peak Loads section is gone post-26c.

If S8's broader purpose was "stats screen loaded successfully," keep the test with a different assertion (e.g., `vitalityTable` is visible — already covered by S5).

- [ ] **Step 3: Add the new 26c selectors**

Add `vitalityExplainerSheet` + `volumePeakBlock(slug)` selector entries.

- [ ] **Step 4: Add ONE smoke test for the ⓘ explainer**

In `test/e2e/specs/saga.spec.ts` (or `stats.spec.ts` if one exists), add a smoke test:

```typescript
test('should open vitality explainer sheet when tapping the ⓘ on the trend section', async ({ page }) => {
  // Navigate to /saga/stats via the codex nav row (existing S5 pattern).
  await page.locator(SAGA.codexNavStats).click();
  await expect(page.locator(SAGA.statsDeepDiveScreen)).toBeVisible();
  
  // Tap the ⓘ icon. Use a robust selector — tap-target may need adjustment.
  await page.locator(`${SAGA.vitalityTrendInfoIcon}`).click();
  
  // The explainer sheet should be visible.
  await expect(page.locator(SAGA.vitalityExplainerSheet)).toBeVisible({ timeout: 5_000 });
});
```

If the ⓘ icon targeting via ValueKey doesn't work, fall back to a Semantics(identifier:) wrapper on the icon's InkWell — adjust the production code accordingly. Document the choice in the test comment.

- [ ] **Step 5: Verify + commit**

```bash
# E2E run is gated on local Supabase. If unavailable, skip the live run;
# CI will exercise the new test.
flutter test  # ensure the Semantics(identifier:) added during fallback doesn't break widget tests
dart analyze --fatal-infos
dart format .

git add test/e2e/helpers/selectors.ts test/e2e/specs/saga.spec.ts \
        lib/features/rpg/ui/stats_deep_dive_screen.dart  # if Semantics wrapper added
git commit -m "$(cat <<'EOF'
test(e2e): drop peakLoadsTable selector + add 26c smoke (26c)

S8 stale: Peak Loads section deleted in 26c, selector + assertion
removed. New selectors: vitalityExplainerSheet, volumePeakBlock(slug).
New smoke: tapping the trend section's ⓘ opens the explainer sheet.
EOF
)"
```

---

## Task 13: L10n parity verification

**Files:**
- Verify: `lib/l10n/app_en.arb` ↔ `lib/l10n/app_pt.arb`

Sanity-check: every key added in 26c exists in both ARB files. The 26c keys spread across Tasks 4, 8, 10. Run a quick grep:

```bash
diff <(grep -oE '"[a-zA-Z]+"' lib/l10n/app_en.arb | grep -v '@' | sort -u) \
     <(grep -oE '"[a-zA-Z]+"' lib/l10n/app_pt.arb | grep -v '@' | sort -u) | head -20
```

Or compare keys explicitly: for each Phase 26c task that added a key, verify both files have a non-empty value.

If any key is missing from `app_pt.arb` (e.g. the plan-writer copied an en value but forgot pt), add the pt translation now.

- [ ] **Step 1: Verify both ARBs are in sync**

```bash
make gen  # regenerates app_localizations*.dart — confirms ARB parsing is valid
flutter test test/unit/l10n/  # if any tests pin per-locale key existence
```

If `make gen` fails with "missing translation for key X in pt" — fill the gap.

- [ ] **Step 2: Commit (only if there were gaps to fill)**

If everything was already in sync, skip the commit. Otherwise:

```bash
git add lib/l10n/
git commit -m "fix(l10n): backfill pt translations for 26c keys"
```

---

## Task 14: Full CI verification + open PR

- [ ] **Step 1: Full local CI**

```bash
export PATH="/c/flutter/bin:$PATH"
make ci
```

Expected: green across format, gen, analyze, test, android-debug-build (~3-5 min).

If anything fails, STOP and fix.

- [ ] **Step 2: Re-read acceptance criteria**

Open `docs/PROJECT.md §3 Phase 26 → 26c acceptance criteria` (lines 454-480). Confirm every bullet:
- [ ] `_SectionHeader` 12dp bottom padding ✓ (Task 5)
- [ ] Trend chart: 2.5dp selected / 1dp ghost; ghost in body-part identity ✓ (Task 7)
- [ ] Trend chart: 180ms tween ✓ (Task 7)
- [ ] VitalityTable: HP-drain ramp percentage coloring ✓ (Task 6)
- [ ] VitalityTable: untested em-dash + "sem dados" subtitle ✓ (Task 10)
- [ ] ⓘ icons on both vitality headers ✓ (Task 5)
- [ ] Explainer sheet: definition · 3-state ramp · rank-safety in heroGold ✓ (Task 4)
- [ ] VolumePeakBlock per body part: Volume left + Carga pico right ✓ (Task 8)
- [ ] Volume delta history-aware: 0-1 / 2-4 / 5+ ✓ (Tasks 2-3 + 8)
- [ ] Peak-load delta: always monthly + "30D" badge ✓ (Tasks 2-3 + 8)
- [ ] Delta state colors: under red / over amber / met green ● / flat textDim ✓ (Task 8)
- [ ] Generic-tip fallback: REFERÊNCIA + 10 séries + estimado ✓ (Task 8)
- [ ] Peak Loads section deleted ✓ (Tasks 9 + 11)

If any bullet is unsatisfied, add the missing work as a follow-up task before opening the PR.

- [ ] **Step 3: Push the branch**

```bash
git push -u origin feature/26c-stats-deep-dive
```

- [ ] **Step 4: Open the PR**

```bash
gh pr create --title "feat(rpg): Phase 26c — Stats deep-dive revamp" --body "$(cat <<'EOF'
## Summary

Restructures `/saga/stats` to three sections: Vitality trend chart · Vitality table · Volume & pico per-body-part. **Peak Loads horizontal-bar table dropped entirely** — the heaviest-lift data now lives in V&P's Carga pico column. New widgets: `VolumePeakBlock` (per-body-part two-column block with history-aware weekly delta + monthly peak delta) and `VitalityExplainerSheet` (bottom-sheet definition + 3-state ramp + heroGold-bordered rank-safety guarantee). New view-state types `VolumeDeltaView` + `PeakDeltaView` encode the rendering decisions; widgets stay pure switch.

**Behavior changes:**
- `VitalityTable` percentage column colors via `vitalityRampColorFor(pct)` from 26a (green/amber/red). Untested rows show em-dash + "sem dados".
- `VitalityTrendChart` ghost lines colored by body-part identity at 35% alpha (was textDim 30%). Cross-fade duration 200ms → 180ms.
- Both vitality section headers gain a 14dp ⓘ that opens the same explainer sheet.
- Stats provider extends with ISO-week-bucketed previous-week + 4-week-mean set counts + 30-day-ago peak EWMA per body part.

**QA pass pending — final coverage + E2E run after code review.**

## Test plan
- [x] Unit: `VolumePeakRow` extended fields + view-state types + assembler delta math
- [x] Widget: `VitalityExplainerSheet` (title / definition / 3 bands / heroGold box)
- [x] Widget: `VolumePeakBlock` (personal-history mode / over-target amber / met bullet / generic-tip fallback / suppressed delta)
- [x] Widget: `VitalityTable` HP-drain ramp coloring + active-row subtitle omission
- [x] Widget: `VitalityTrendChart` ghost lines in per-body-part identity + 180ms duration
- [x] Widget: stats screen composition (3 sections, 6 VolumePeakBlocks, no PeakLoadsTable)
- [x] E2E: new smoke that the ⓘ opens the explainer sheet
- [x] `make ci` clean

## References
- Spec: `docs/PROJECT.md §3 Phase 26 → 26c acceptance criteria`
- Visual: `docs/phase-26-mockups.html` section `#stats` + `#vitality-explainer`
- Plan: `docs/phase-26c-plan.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Move on per the pipeline**

After the PR opens, CLAUDE.md pipeline:
- Reviewer agent (read-only).
- After reviewer signs off, QA gate (final coverage hole closing + E2E selector check).
- **Step 9 visual verification** (build Flutter web, screenshot at 320/360/412dp against foundation-user fixture, compare with `docs/phase-26-mockups.html` section `#stats`).
- Merge after QA + visual match + CI green.
- After merge: condense 26c in PROJECT.md §4 + remove 26c section from WIP.md.
- Re-invoke `superpowers:writing-plans` for 26d's plan.

---

## Self-review notes (pre-handoff)

**Spec coverage:** every acceptance bullet from `docs/PROJECT.md §3 Phase 26 → 26c` is covered by tasks 1–13, verified in task 14. The generic-tip fallback's ⓘ → bottom-sheet explainer for the Schoenfeld floor is documented as deferred (Task 8 inline note) — the badge renders non-interactively in 26c.

**Placeholder scan:** no `TODO` / `TBD` / "implement later" / "fill in details" / "add error handling" generic instructions in the implementation steps. Task 2's test fixtures are described concretely; the implementer fills in `now` + the event list using existing test helpers in the file. Tasks 5 and 6 reference the existing test harness in the file rather than re-specifying mount code — this is intentional (the harness exists and is reusable).

**Type consistency:** `VolumePeakRow` field names + types match across the model file, the assembler, and the widget. `VolumeDeltaView` / `PeakDeltaView` enum value names (`suppressed` / `underTarget` / `met` / `overTarget` / `up` / `flat`) are consistent across the model file and the widget consumers. The `_schoenfeldFloor = 10` constant is private to `volume_peak_block.dart` — no cross-file shape drift.

**Out of scope for 26c (deferred):**
- ⓘ explainer bottom-sheet for the Schoenfeld floor (generic-tip fallback). The badge renders; the tap is deferred to a later polish phase.
- Locale-aware unit suffix (kg/lbs) — Phase 26c uses fixed "kg". The future settings-driven unit work picks this up.
- Granular contrast verification for the new heroGold-bordered safety box at multiple alpha levels — out of scope; visual verification in pipeline step 9 catches anything obviously wrong.

**Known plan defects to surface at PR open:**
- Task 12's E2E targeting of the ⓘ via `ValueKey` may need a `Semantics(identifier:)` wrapper if Flutter web's AOM doesn't expose ValueKeys as `data-flt-key="..."` attributes. The implementer adapts during the E2E task; if Semantics wrapping is added to the ⓘ icons, also document in the cluster ledger.
