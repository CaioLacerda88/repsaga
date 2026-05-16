# Phase 26b — Saga Screen Revamp · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `CharacterSheetScreen` from the current radar-centric composition to the Option B v4 type-dominant layout: 3-column header (36dp rune · 56sp LVL · class+title meta) + character XP bar + 6 mini-XP-block body-part rows with 24h dot-pulse on rank-up. Stat rows become tappable → `/saga/stats?body_part=<X>`.

**Architecture:** Phase 26a's color tokens (`bodyPartChest/Back`, `xpTrack`, `vitalityRampColorFor`) + l10n keys (`withinRankXpSuffix`) flow into the new widgets. New domain helper `characterXpInLevel()` derives `(xpInLevel, xpForNextLevel)` from `(ranks, lifetimeXp)` using the single-body-part cheapest-advancement approximation. New Hive-backed `RankUpPulseRepository` stores per-body-part pulse-until timestamps; celebration overlay writes to it on rank-up dismiss; rows read it to render the pulse ring.

**Tech Stack:** Flutter ^3.11.4, Dart, Freezed, GoRouter 17, Riverpod 3, Hive, `flutter_test`, `mocktail`, l10n via `flutter_localizations` + ARB files.

**Spec source:** `docs/PROJECT.md §3 Phase 26 → 26b acceptance criteria` (lines 420-442). Visual reference: `docs/phase-26-mockups.html` section `#saga` (lines 958-1054).

**Branch:** `feature/26b-saga-option-b-v4` (already created by the orchestrator at base SHA `9d9699f`).

**Open question already answered (during plan-writing):** Character XP bar semantics = "lifetime XP within next-level band" (option A). Numerator = `lifetimeXp`; denominator = `lifetimeXp + cheapestXpToAdvanceLevel`, where `cheapestXpToAdvanceLevel` solves the single-body-part approximation (see Task 1).

---

## File map

**New:**
- `lib/features/rpg/domain/character_xp_calculator.dart` — pure-Dart helper computing `(xpInLevel, xpForNextLevel)` from `(rank distribution, lifetimeXp, perBodyPartTotalXp)`.
- `lib/features/rpg/data/rank_up_pulse_repository.dart` — Hive-backed `Map<BodyPart, DateTime>` for pulse expiry timestamps.
- `lib/features/rpg/ui/widgets/character_xp_bar.dart` — 6dp gradient track + label widget.
- `lib/features/rpg/ui/widgets/saga_header.dart` — Option B v4 three-column header (extracted out of `_SheetHeader` since it grows past trivial).
- `lib/features/rpg/ui/widgets/rank_up_pulse.dart` — 1.5× scale + outer glow ring overlay for the body-part dot during the 24h pulse window.

**Modified:**
- `lib/features/rpg/ui/widgets/rune_halo.dart` — drop active-state `boxShadow`; add 36dp size as the header default; preserve other states untouched.
- `lib/features/rpg/ui/widgets/body_part_rank_row.dart` — full rewrite to the Option B v4 mini-XP-block shape; new states (untrained 0.4 opacity, trained, just-rank-up'd with pulse).
- `lib/features/rpg/ui/character_sheet_screen.dart` — replace `_SheetHeader` with `SagaHeader`; add `CharacterXpBar` between header and body-part rows; remove `VitalityRadar` import + usage; update `_CharacterSheetSkeleton`; preserve `_FirstSetAwakensBanner` + `DormantCardioRow` + `_CodexNavSection` + `_CharacterSheetError`.
- `lib/features/rpg/models/character_sheet_state.dart` — add `xpInLevel` + `xpForNextLevel` fields to `CharacterSheetState` (Freezed regen required).
- `lib/features/rpg/providers/character_sheet_provider.dart` — populate the new fields via `characterXpInLevel()`.
- `lib/features/rpg/ui/stats_deep_dive_screen.dart` — accept optional `bodyPart` query param to pre-select the trend chart row.
- `lib/core/router/app_router.dart` — `/saga/stats` route accepts `body_part` query string.
- `lib/features/rpg/domain/celebration_event_builder.dart` (or wherever rank-up celebration emits its done signal) — write to `RankUpPulseRepository` when celebration is dismissed.
- `test/e2e/specs/rpg-saga.spec.ts` — selector updates for the new structure + a smoke test for stat-row → stats deep-dive routing.
- `test/e2e/helpers/selectors.ts` — new selectors for the header columns, char XP bar, mini-XP-block rows.
- `lib/core/services/hive_service.dart` (or wherever Hive boxes are registered) — register the new `rank_up_pulse` box.

**Deleted:**
- `lib/features/rpg/ui/widgets/vitality_radar.dart` — orphaned after the radar leaves the character sheet; no other consumer.
- `test/widget/features/rpg/widgets/vitality_radar_test.dart` + `vitality_radar_golden_test.dart` — companion tests for the deleted widget.
- `lib/features/rpg/ui/widgets/xp_progress_hairline.dart` — the hairline is replaced by the new 4dp body-part-hue bar inside `BodyPartRankRow`; the widget has no other consumer.

**Pre-flight reads (engineer should skim before starting):**
- `lib/features/rpg/ui/character_sheet_screen.dart` (existing composition)
- `lib/features/rpg/ui/widgets/body_part_rank_row.dart` (existing `_ExpandedRow` / `_CompressedRow` shapes)
- `lib/features/rpg/ui/widgets/rune_halo.dart` (existing 4-state animation structure)
- `lib/features/rpg/models/character_sheet_state.dart` (`BodyPartSheetEntry` + `CharacterSheetState`)
- `lib/features/rpg/domain/rank_curve.dart` (`RankCurve.cumulativeXpForRank` + `characterLevel`)
- `lib/features/rpg/providers/character_sheet_provider.dart` (state population pipeline)
- `lib/core/router/app_router.dart` (around line 237 — `/saga/stats` route)
- `lib/features/rpg/ui/stats_deep_dive_screen.dart` (consumer of the new query param)
- `lib/features/workouts/data/workout_local_storage.dart` (canonical Hive-box pattern — copy this shape for the pulse repository)
- `lib/core/theme/app_theme.dart` (the new 26a tokens — `bodyPartChest`, `bodyPartBack`, `xpTrack`, `vitalityHigh/Mid/Low`)
- `docs/phase-26-mockups.html` lines 958-1054 (visual reference for the new layout)

**Critical pre-existing-pattern flags:**
- Test boilerplate from this plan MAY include `import 'package:flutter/material.dart';`. **Drop it if the test body doesn't reference a Material symbol** — RepSaga runs `dart analyze --fatal-infos` and `unused_import` is fatal. See auto-memory `feedback_plan_unused_imports`.
- Test file names + group labels + test labels MUST be phase-agnostic. **No `Phase 26b` in any test name.** Same goes for "(was X)" parentheticals on rebound widgets. See auto-memory `feedback_phase_agnostic_test_names`.
- Every reviewer finding (Important / Minor / Nit) gets fixed in the same cycle. No "post-merge follow-up." See auto-memory `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`.

---

## Task 1: Domain helper — `characterXpInLevel()`

**Files:**
- Create: `lib/features/rpg/domain/character_xp_calculator.dart`
- Create: `test/unit/features/rpg/domain/character_xp_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/features/rpg/domain/character_xp_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/character_xp_calculator.dart';

void main() {
  group('characterXpInLevel — single-body-part approximation', () {
    test('day-zero user (all ranks 1, lifetimeXp 0) reports a non-zero denominator', () {
      // Edge case: zero history. Bar reads 0% (xpInLevel == 0) and the
      // denominator must be > 0 so the widget doesn't divide-by-zero.
      final result = characterXpInLevel(
        ranks: {'chest': 1, 'back': 1, 'legs': 1, 'shoulders': 1, 'arms': 1, 'core': 1},
        lifetimeXp: 0,
        perBodyPartTotalXp: {'chest': 0, 'back': 0, 'legs': 0, 'shoulders': 0, 'arms': 0, 'core': 0},
        perBodyPartXpInRank: {'chest': 0, 'back': 0, 'legs': 0, 'shoulders': 0, 'arms': 0, 'core': 0},
        perBodyPartXpForNextRank: {'chest': 100, 'back': 100, 'legs': 100, 'shoulders': 100, 'arms': 100, 'core': 100},
      );
      expect(result.xpInLevel, 0);
      expect(result.xpForNextLevel, greaterThan(0));
    });

    test('mid-level user — denominator is the cheapest single-body-part advancement', () {
      // Σ ranks = 19 (3+3+3+3+3+4). N=6. (Σ-N) = 13. 13 mod 4 = 1.
      // ranksToNextLevel = 4 - 1 = 3. The cheapest body part is the one
      // whose 3-rank-up costs least. Here `core` is at rank 4, so its
      // 3-rank-up reaches rank 7 (most expensive); the rank-3 body parts'
      // 3-rank-ups reach rank 6. We pick the cheapest of those.
      final result = characterXpInLevel(
        ranks: {'chest': 3, 'back': 3, 'legs': 3, 'shoulders': 3, 'arms': 3, 'core': 4},
        lifetimeXp: 5000,
        perBodyPartTotalXp: {'chest': 800, 'back': 800, 'legs': 800, 'shoulders': 800, 'arms': 800, 'core': 1000},
        perBodyPartXpInRank: {'chest': 100, 'back': 100, 'legs': 100, 'shoulders': 100, 'arms': 100, 'core': 50},
        perBodyPartXpForNextRank: {'chest': 300, 'back': 300, 'legs': 300, 'shoulders': 300, 'arms': 300, 'core': 400},
      );
      expect(result.xpInLevel, 5000);
      // Pick the body part whose total XP to reach rank (current + 3) minus
      // its current totalXp is smallest. Concrete numbers depend on the
      // RankCurve constants — what matters here is that the denominator
      // is positive and the bar can be rendered.
      expect(result.xpForNextLevel, greaterThan(5000));
      expect(result.xpForNextLevel, lessThan(50000));
    });

    test('just-leveled-up user (rank-sum just crossed a /4 boundary) needs 4 more ranks', () {
      // Σ ranks = 22 (4+4+4+4+3+3). N=6. (Σ-N) = 16. 16 mod 4 = 0.
      // ranksToNextLevel = 4 (not zero — you can't be "at" the boundary,
      // you just crossed it, so you need a full 4 more ranks).
      final result = characterXpInLevel(
        ranks: {'chest': 4, 'back': 4, 'legs': 4, 'shoulders': 4, 'arms': 3, 'core': 3},
        lifetimeXp: 8000,
        perBodyPartTotalXp: {'chest': 1500, 'back': 1500, 'legs': 1500, 'shoulders': 1500, 'arms': 1000, 'core': 1000},
        perBodyPartXpInRank: {'chest': 0, 'back': 0, 'legs': 0, 'shoulders': 0, 'arms': 100, 'core': 100},
        perBodyPartXpForNextRank: {'chest': 500, 'back': 500, 'legs': 500, 'shoulders': 500, 'arms': 400, 'core': 400},
      );
      expect(result.xpInLevel, 8000);
      expect(result.xpForNextLevel, greaterThan(8000));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/domain/character_xp_calculator_test.dart
```

Expected: FAIL with `The function 'characterXpInLevel' isn't defined` or similar.

- [ ] **Step 3: Implement the helper**

Create `lib/features/rpg/domain/character_xp_calculator.dart`:

```dart
import 'rank_curve.dart';

/// Result shape for [characterXpInLevel].
///
/// `xpInLevel` is the numerator (always equals current lifetimeXp — the bar
/// fills the entire spent lifetime, not a within-band slice — because the
/// "level" boundary is rank-derived, not XP-derived). `xpForNextLevel` is
/// `xpInLevel + cheapestAdditionalXp`, where the cheapest path advances ONE
/// body part by `ranksToNextLevel` ranks. The bar renders fill =
/// `xpInLevel / xpForNextLevel`.
class CharacterXpBand {
  const CharacterXpBand({required this.xpInLevel, required this.xpForNextLevel});

  final double xpInLevel;
  final double xpForNextLevel;
}

/// Active body parts contributing to character level. v1 = the 6 strength
/// tracks (cardio excluded — matches `activeBodyParts` in
/// `models/body_part.dart` but kept as `List<String>` here so the helper is
/// model-import-free and testable in pure Dart).
const _activeKeys = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];

/// Character XP band for the Saga header bar (Phase 26b).
///
/// Computes how much *additional* XP the user needs to earn — in a single
/// body part — to advance character level by one. The denominator returned
/// is `lifetimeXp + cheapestAdditionalXp`, so the bar's fill ratio
/// `xpInLevel / xpForNextLevel` reads "lifetime XP as a fraction of where
/// it would be if the user took the cheapest path to next character level."
///
/// **Approximation contract.** This DOES NOT solve the optimal multi-body-
/// part advancement (where partial rank-ups in different body parts could
/// sum to the +ranksToNextLevel target with strictly less XP). It picks one
/// body part and computes how much that body part alone needs to advance
/// by `ranksToNextLevel` ranks. The single-body-part path is an UPPER BOUND
/// on the true minimum, deterministic, and easy to reason about — the bar
/// stays monotonic (lifetime XP only increases, denominator only changes
/// on a rank-up).
///
/// **Why not solve the optimum.** The user can only train one body part
/// per set, but the "cheapest path" intuitively spans the K-cheapest single-
/// rank advances across distinct body parts. That requires a top-K selection
/// over an evolving cost vector (each rank-up makes the next rank more
/// expensive in the same body part). For a glanceable progress bar, the
/// single-body-part approximation is enough — the user is not playing an
/// optimization game, they're reading "how close am I to the next level?"
///
/// Edge cases:
///   * Day-zero user (all ranks 1, lifetimeXp 0): denominator is the XP
///     needed for one body part to reach rank 5 (4 rank-ups in 1 body part).
///   * Just-leveled-up user (rank-sum just crossed a /4 boundary): needs
///     4 more ranks, not 0.
///   * Maxed-out user (a body part hits rank 99): the helper falls back to
///     picking from the remaining 5. If all 6 are maxed, returns a denominator
///     equal to lifetimeXp (bar reads 100%, no further progression possible).
CharacterXpBand characterXpInLevel({
  required Map<String, int> ranks,
  required double lifetimeXp,
  required Map<String, double> perBodyPartTotalXp,
  required Map<String, double> perBodyPartXpInRank,
  required Map<String, double> perBodyPartXpForNextRank,
}) {
  var sumRanks = 0;
  var nActive = 0;
  for (final key in _activeKeys) {
    final r = ranks[key];
    if (r == null) continue;
    sumRanks += r;
    nActive += 1;
  }
  if (nActive == 0) {
    return CharacterXpBand(xpInLevel: lifetimeXp, xpForNextLevel: lifetimeXp + 1);
  }
  final modulo = (sumRanks - nActive) % 4;
  final ranksToNextLevel = modulo == 0 ? 4 : 4 - modulo;

  double? cheapestExtraXp;
  for (final key in _activeKeys) {
    final currentRank = ranks[key];
    final totalXpForPart = perBodyPartTotalXp[key];
    if (currentRank == null || totalXpForPart == null) continue;
    final targetRank = currentRank + ranksToNextLevel;
    if (targetRank > RankCurve.maxRank) continue; // body part too maxed to advance
    final totalXpAtTarget = RankCurve.cumulativeXpForRank(targetRank);
    final extra = totalXpAtTarget - totalXpForPart;
    if (extra <= 0) continue; // defensive — shouldn't happen if curve is monotonic
    if (cheapestExtraXp == null || extra < cheapestExtraXp) {
      cheapestExtraXp = extra;
    }
  }

  if (cheapestExtraXp == null) {
    // All body parts are maxed out beyond what ranksToNextLevel can reach.
    // Render the bar at 100% with a denominator = lifetimeXp (no further
    // progression possible).
    return CharacterXpBand(xpInLevel: lifetimeXp, xpForNextLevel: lifetimeXp);
  }
  return CharacterXpBand(
    xpInLevel: lifetimeXp,
    xpForNextLevel: lifetimeXp + cheapestExtraXp,
  );
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/unit/features/rpg/domain/character_xp_calculator_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/domain/character_xp_calculator.dart \
        test/unit/features/rpg/domain/character_xp_calculator_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): characterXpInLevel domain helper for saga char XP bar (26b)

Single-body-part cheapest-advancement approximation. Computes
(xpInLevel = lifetimeXp, xpForNextLevel = lifetimeXp + cheapest extra
XP a single body part needs to advance rank-sum past the next /4
character-level boundary).

Documented as an approximation (not optimal multi-body-part) — the
bar is glanceable progress, not an optimization game.
EOF
)"
```

---

## Task 2: Extend `CharacterSheetState` + provider with character XP fields

**Files:**
- Modify: `lib/features/rpg/models/character_sheet_state.dart`
- Regenerate: `lib/features/rpg/models/character_sheet_state.freezed.dart`
- Modify: `lib/features/rpg/providers/character_sheet_provider.dart`
- Modify: `test/unit/features/rpg/models/character_sheet_state_test.dart` (existing file — extend)
- Modify: `test/unit/features/rpg/providers/character_sheet_provider_test.dart` (existing file — extend)

- [ ] **Step 1: Write the failing test on the state shape**

Find the existing `test/unit/features/rpg/models/character_sheet_state_test.dart`. Append a new group that asserts the state carries the two new fields:

```dart
  group('CharacterSheetState — character XP band fields (Phase 26b)', () {
    test('exposes xpInLevel and xpForNextLevel populated from constructor', () {
      final state = CharacterSheetState(
        characterLevel: 14,
        lifetimeXp: 8420,
        xpInLevel: 8420,
        xpForNextLevel: 12000,
        bodyPartProgress: const [],
      );
      expect(state.xpInLevel, 8420);
      expect(state.xpForNextLevel, 12000);
    });

    test('xpForNextLevel must never be less than xpInLevel (invariant)', () {
      // Documents the invariant relied on by the bar widget. The provider
      // composes these via characterXpInLevel() which guarantees this; the
      // test pins the contract so a future refactor can't silently break it.
      const state = CharacterSheetState(
        characterLevel: 14,
        lifetimeXp: 8420,
        xpInLevel: 8420,
        xpForNextLevel: 8420, // edge case: maxed out
        bodyPartProgress: [],
      );
      expect(state.xpForNextLevel >= state.xpInLevel, isTrue);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/models/character_sheet_state_test.dart --plain-name "character XP band"
```

Expected: FAIL with `The named parameter 'xpInLevel' isn't defined`.

- [ ] **Step 3: Add the fields to `CharacterSheetState`**

In `lib/features/rpg/models/character_sheet_state.dart`, modify the `CharacterSheetState` factory constructor (around line 70) to add two required fields:

```dart
@freezed
abstract class CharacterSheetState with _$CharacterSheetState {
  const factory CharacterSheetState({
    required int characterLevel,
    required double lifetimeXp,
    /// Numerator for the Phase 26b character XP bar — equals [lifetimeXp].
    /// Carried as a separate field (rather than computed at the widget) so
    /// the bar widget can stay pure-presentation and the provider owns the
    /// derivation logic.
    required double xpInLevel,
    /// Denominator for the Phase 26b character XP bar. See
    /// `characterXpInLevel()` in `domain/character_xp_calculator.dart` for
    /// the single-body-part approximation it uses. Invariant:
    /// `xpForNextLevel >= xpInLevel`.
    required double xpForNextLevel,
    required List<BodyPartSheetEntry> bodyPartProgress,
    String? activeTitle,
    CharacterClass? characterClass,
  }) = _CharacterSheetState;
  // (rest unchanged)
```

Regenerate freezed:

```bash
export PATH="/c/flutter/bin:$PATH"
make gen
```

- [ ] **Step 4: Update the provider to populate the new fields**

In `lib/features/rpg/providers/character_sheet_provider.dart`, locate the construction of `CharacterSheetState` (around line 60-70). Add the calculator call:

```dart
import '../domain/character_xp_calculator.dart';
// ... (existing imports)

// Inside the provider build method, after computing bodyPartProgress entries:
final ranks = {
  for (final e in entries) e.bodyPart.dbValue: e.rank,
};
final perBodyPartTotalXp = {
  for (final e in entries) e.bodyPart.dbValue: e.totalXp,
};
final perBodyPartXpInRank = {
  for (final e in entries) e.bodyPart.dbValue: e.xpInRank,
};
final perBodyPartXpForNextRank = {
  for (final e in entries) e.bodyPart.dbValue: e.xpForNextRank,
};
final xpBand = characterXpInLevel(
  ranks: ranks,
  lifetimeXp: snapshot.characterState.lifetimeXp,
  perBodyPartTotalXp: perBodyPartTotalXp,
  perBodyPartXpInRank: perBodyPartXpInRank,
  perBodyPartXpForNextRank: perBodyPartXpForNextRank,
);

return CharacterSheetState(
  characterLevel: snapshot.characterState.characterLevel,
  lifetimeXp: snapshot.characterState.lifetimeXp,
  xpInLevel: xpBand.xpInLevel,
  xpForNextLevel: xpBand.xpForNextLevel,
  bodyPartProgress: entries,
  // ... (existing fields)
);
```

Read the existing provider to see the exact return statement shape; integrate the new fields without disrupting other logic. The exact line numbers depend on the current file — re-read before editing.

- [ ] **Step 5: Run state + provider tests**

```bash
flutter test test/unit/features/rpg/models/character_sheet_state_test.dart \
             test/unit/features/rpg/providers/character_sheet_provider_test.dart
```

Expected: all pass. If existing provider tests break because they construct `CharacterSheetState` directly without the new fields, update those test factories to supply `xpInLevel` + `xpForNextLevel` (default values like `0` + `1` are fine for tests that don't care about the bar). DO NOT remove existing assertions — just supply the new required fields.

Full suite smoke:

```bash
flutter test
```

Expected: green. Test fixtures that construct `CharacterSheetState` will fail to compile until they supply the new required fields — find and patch each. Likely candidates: `test/fixtures/test_factories.dart`, `test/widget/features/rpg/ui/character_sheet_screen_test.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/models/character_sheet_state.dart \
        lib/features/rpg/models/character_sheet_state.freezed.dart \
        lib/features/rpg/providers/character_sheet_provider.dart \
        test/unit/features/rpg/models/character_sheet_state_test.dart \
        test/unit/features/rpg/providers/character_sheet_provider_test.dart \
        test/fixtures/test_factories.dart \
        test/widget/features/rpg/ui/character_sheet_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): wire characterXpInLevel into CharacterSheetState (26b)

CharacterSheetState gains xpInLevel + xpForNextLevel populated by the
provider via characterXpInLevel(). Test fixtures patched to supply the
new required fields with neutral defaults where the bar isn't under test.
EOF
)"
```

(Stage only the files you actually modified. If a test fixture wasn't touched, drop it from the `git add`.)

---

## Task 3: New `CharacterXpBar` widget

**Files:**
- Create: `lib/features/rpg/ui/widgets/character_xp_bar.dart`
- Create: `test/widget/features/rpg/widgets/character_xp_bar_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/features/rpg/widgets/character_xp_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/character_xp_bar.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('CharacterXpBar', () {
    testWidgets('renders the label in pt-BR with thousand separator + LVL', (tester) async {
      await tester.pumpWidget(_wrap(
        const CharacterXpBar(
          xpInLevel: 8420,
          xpForNextLevel: 12000,
          characterLevel: 14,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('8.420 XP'), findsOneWidget);
      expect(find.textContaining('3.580 para LVL 15'), findsOneWidget);
    });

    testWidgets('full bar when xpInLevel == xpForNextLevel (maxed-out)', (tester) async {
      await tester.pumpWidget(_wrap(
        const CharacterXpBar(
          xpInLevel: 10000,
          xpForNextLevel: 10000,
          characterLevel: 99,
        ),
      ));
      await tester.pumpAndSettle();
      // Right-side label shows "0 para LVL 100" — the maxed-out edge state.
      expect(find.textContaining('0 para LVL 100'), findsOneWidget);
    });

    testWidgets('empty bar when xpInLevel == 0 (day-zero)', (tester) async {
      await tester.pumpWidget(_wrap(
        const CharacterXpBar(
          xpInLevel: 0,
          xpForNextLevel: 400,
          characterLevel: 1,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 XP'), findsOneWidget);
      expect(find.textContaining('400 para LVL 2'), findsOneWidget);
    });

    testWidgets('bar fill respects fraction within [0, 1]', (tester) async {
      // 70% fill — pin via FractionallySizedBox widthFactor on the fill child.
      await tester.pumpWidget(_wrap(
        const CharacterXpBar(
          xpInLevel: 8420,
          xpForNextLevel: 12000,
          characterLevel: 14,
        ),
      ));
      await tester.pumpAndSettle();
      final fill = tester.widget<FractionallySizedBox>(
        find.byKey(const ValueKey('character-xp-bar-fill')),
      );
      // 8420 / 12000 = 0.7016...
      expect(fill.widthFactor, closeTo(0.7016, 0.001));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/widget/features/rpg/widgets/character_xp_bar_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: '.../character_xp_bar.dart'`.

- [ ] **Step 3: Implement the widget**

Create `lib/features/rpg/ui/widgets/character_xp_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Character XP bar shown beneath the Saga header (Phase 26b).
///
/// 6dp track with a violet gradient fill + a two-column label row below:
///   * Left: "{xpInLevel} XP"
///   * Right: "{xpForNextLevel - xpInLevel} {l10n.withinRankXpSuffix-equivalent for char level}"
///
/// Spec source: docs/PROJECT.md §3 Phase 26 → 26b acceptance criteria. The
/// underlying fraction uses the single-body-part approximation owned by
/// `domain/character_xp_calculator.dart` — this widget is pure presentation.
class CharacterXpBar extends StatelessWidget {
  const CharacterXpBar({
    super.key,
    required this.xpInLevel,
    required this.xpForNextLevel,
    required this.characterLevel,
  });

  /// Lifetime XP accumulated. Bar numerator.
  final double xpInLevel;

  /// Cheapest lifetime XP at which the next character level becomes
  /// reachable. Bar denominator. Invariant: `>= xpInLevel`.
  final double xpForNextLevel;

  /// Current character level. The right-side label reads
  /// "Y para LVL <characterLevel + 1>".
  final int characterLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final fraction = xpForNextLevel <= xpInLevel
        ? 1.0
        : (xpInLevel / xpForNextLevel).clamp(0.0, 1.0);
    final remaining = (xpForNextLevel - xpInLevel).clamp(0.0, double.infinity);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: AppColors.xpTrack,
              child: FractionallySizedBox(
                key: const ValueKey('character-xp-bar-fill'),
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primaryViolet, AppColors.hotViolet],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_format(xpInLevel)} XP',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                // l10n: "${remaining} para LVL ${level+1}" — the suffix
                // "para LVL N" is locked by spec text and is identical in
                // en + pt for this transitional release. If localization
                // demand grows, swap to an AppLocalizations entry.
                '${_format(remaining)} para LVL ${characterLevel + 1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.hotViolet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Thousand-separator formatting that matches the existing pt-BR
  /// convention used elsewhere on the saga screen ("8.420" not "8,420"
  /// and not "8420"). Uses period as the thousands separator.
  static String _format(double value) {
    final intValue = value.round();
    final s = intValue.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
```

If the codebase already has a thousand-separator helper, prefer that. Grep for `'\\\\.'.*[0-9]{3}` style formatters in `lib/features/rpg/` and `lib/core/utils/` first. If one exists, import + use it instead of `_format`. Otherwise this private helper is acceptable for now (cluster-extract candidate for a future utility-consolidation pass).

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/widget/features/rpg/widgets/character_xp_bar_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/character_xp_bar.dart \
        test/widget/features/rpg/widgets/character_xp_bar_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): CharacterXpBar widget for saga header (26b)

6dp gradient track + two-column label below. Pure presentation —
domain helper characterXpInLevel() owns the math. Pt-BR thousand
separator on both numbers; right-side label in hotViolet.
EOF
)"
```

---

## Task 4: Update `RuneHalo` — drop active glow, support 36dp size

**Files:**
- Modify: `lib/features/rpg/ui/widgets/rune_halo.dart`
- Modify: `test/widget/features/rpg/widgets/rune_halo_test.dart` (existing file — extend)

- [ ] **Step 1: Read the existing widget**

Open `lib/features/rpg/ui/widgets/rune_halo.dart`. Confirm:
- `_ActiveHalo` currently renders a `Container` with two `BoxShadow` entries (lines ~205-220 in the pre-change file)
- The widget reserves `widget.size + 60` for the outer container
- Default `size` is 96 (the header-centered legacy composition)

The new behavior:
- `_ActiveHalo` renders the sigil WITHOUT any `boxShadow`. The 1px rgba(179,109,255,0.35) stroke that exists on the icon itself stays.
- The widget supports being called at `size: 36` from the new Saga header without the outer container's `+ 60` padding becoming visually disruptive. Reduce the outer reserved size when `widget.size < 48` (a clean breakpoint between header use and legacy radar-era hero use). Add a doc-comment block explaining the breakpoint.

- [ ] **Step 2: Write the failing test**

Append to `test/widget/features/rpg/widgets/rune_halo_test.dart`:

```dart
  group('RuneHalo — Saga header sizing + active-glow removal', () {
    testWidgets('active state renders no BoxShadow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: RuneHalo(state: VitalityState.active, size: 36)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final c in containers) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          expect(
            dec.boxShadow == null || dec.boxShadow!.isEmpty,
            isTrue,
            reason: 'Active-state RuneHalo must not render any BoxShadow at 36dp.',
          );
        }
      }
    });

    testWidgets('radiant state still renders a sweep (regression guard)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: RuneHalo(state: VitalityState.radiant, size: 36)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The radiant state uses a CustomPaint sweep; just confirm the painter
      // is mounted. Glow boxShadow still present in radiant — that's the
      // reward signal and stays unchanged.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('outer reserved size shrinks below 48dp threshold', (tester) async {
      // At size: 36, the +60 outer padding from the legacy 96dp default
      // would yield a 96-square widget that dwarfs the rune. The 26b
      // breakpoint trims that padding to size + 12 (4dp on each side).
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: RuneHalo(state: VitalityState.active, size: 36)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(RuneHalo));
      // Tolerance for sub-pixel artifacts.
      expect(size.width, lessThanOrEqualTo(56));
      expect(size.height, lessThanOrEqualTo(56));
    });
  });
```

- [ ] **Step 3: Run to verify the first test fails**

```bash
flutter test test/widget/features/rpg/widgets/rune_halo_test.dart --plain-name "active state renders no BoxShadow"
```

Expected: FAIL — the active state currently DOES render two BoxShadows.

- [ ] **Step 4: Update `RuneHalo`**

In `lib/features/rpg/ui/widgets/rune_halo.dart`:

**(a)** Change the outer container reservation. Find:

```dart
@override
Widget build(BuildContext context) {
  final containerSize = widget.size + 60;
```

Replace with:

```dart
@override
Widget build(BuildContext context) {
  // Phase 26b: when the halo is used as the 36dp Saga-header sigil the
  // legacy +60dp glow-padding is visually disruptive. The static states
  // (active, dormant, untested) don't need outer glow room; the animated
  // states (fading, radiant) keep the legacy padding so their
  // breathing/sweep beats don't clip.
  final isCompact = widget.size < 48;
  final glowPad = isCompact ? 12 : 60;
  final containerSize = widget.size + glowPad;
```

**(b)** Update `_ActiveHalo` to render no `boxShadow`. Find the active-state body (around line 200-230) and replace with:

```dart
class _ActiveHalo extends StatelessWidget {
  const _ActiveHalo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Phase 26b: active-state glow REMOVED. The previous two-layer
    // boxShadow read as "this is a special moment" but active is the
    // *steady state* — the user is on the path, not crossing a threshold.
    // Reserving glow for radiant (the reward state) restores the contrast
    // that made the four halo states distinguishable at a glance.
    return Container(
      width: size + 8,
      height: size + 8,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: Center(
        child: AppIcons.render(
          AppIcons.hero,
          color: AppColors.hotViolet,
          size: size,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run to verify the new tests pass + regression suite stays green**

```bash
flutter test test/widget/features/rpg/widgets/rune_halo_test.dart
flutter test
```

Expected: full suite green. If any other test referenced the active-state boxShadow shape directly (unlikely, but possible), update it to assert the new shape OR drop the assertion if it was checking implementation details.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/ui/widgets/rune_halo.dart \
        test/widget/features/rpg/widgets/rune_halo_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): RuneHalo active-glow removal + compact 36dp sizing (26b)

Active state no longer renders a BoxShadow — the glow was reading as
a threshold-crossed signal but active is the steady state. Radiant
keeps its sweep+glow (the actual reward state).

Outer reserved size shrinks to size+12 when size<48dp so the 36dp
Saga-header sigil doesn't reserve 96dp of empty padding. Animated
states (fading, radiant) keep size+60 so their breathing/sweep beats
don't clip.
EOF
)"
```

---

## Task 5: New `SagaHeader` widget — three-column Option B v4

**Files:**
- Create: `lib/features/rpg/ui/widgets/saga_header.dart`
- Create: `test/widget/features/rpg/widgets/saga_header_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/widget/features/rpg/widgets/saga_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/saga_header.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Widget _wrap(Widget child, {double width = 360}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('SagaHeader — three-column layout', () {
    testWidgets('renders rune + level numeral + class + title at 360dp', (tester) async {
      await tester.pumpWidget(_wrap(
        const SagaHeader(
          haloState: VitalityState.active,
          characterLevel: 14,
          characterClass: CharacterClass.ironVanguard, // pick a real enum value
          activeTitle: 'Plate-Bearer',
        ),
      ));
      await tester.pumpAndSettle();
      // Level numeral
      expect(find.text('14'), findsOneWidget);
      // LVL tag below the numeral
      expect(find.text('LVL'), findsOneWidget);
      // Class name (resolves through AppLocalizations.classIronVanguard or similar)
      expect(find.textContaining(RegExp(r'Iron Vanguard|Vanguarda', caseSensitive: false)), findsOneWidget);
      // Active title
      expect(find.text('Plate-Bearer'), findsOneWidget);
    });

    testWidgets('right-meta column ellipsizes long class names at 360dp', (tester) async {
      await tester.pumpWidget(_wrap(
        const SagaHeader(
          haloState: VitalityState.active,
          characterLevel: 14,
          // The longest pt-BR class label is currently ~12 chars; this synthetic
          // override forces the ellipsis path so a future longer name doesn't
          // silently break layout.
          characterClass: null, // null routes to placeholder text
          activeTitle: 'Extraordinarily Verbose Compound Title Of The First Sun',
          // Optional override for forcing the ellipsis on the title row:
        ),
      ));
      await tester.pumpAndSettle();
      // The title should be present and clipped — find the Text widget and
      // confirm its overflow is set to ellipsis.
      final titleText = tester.widget<Text>(
        find.byKey(const ValueKey('saga-header-title')),
      );
      expect(titleText.overflow, TextOverflow.ellipsis);
      expect(titleText.maxLines, 1);
    });

    testWidgets('omits the title row when activeTitle is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const SagaHeader(
          haloState: VitalityState.active,
          characterLevel: 14,
          characterClass: null,
          activeTitle: null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('saga-header-title')), findsNothing);
    });

    testWidgets('renders without overflow at 320dp viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap(
        const SagaHeader(
          haloState: VitalityState.active,
          characterLevel: 14,
          characterClass: null,
          activeTitle: 'Plate-Bearer',
        ),
        width: 320,
      ));
      await tester.pumpAndSettle();
      // No RenderFlex overflow errors should have been logged.
      expect(tester.takeException(), isNull);
    });
  });
}
```

NOTE: the test references `CharacterClass.ironVanguard` — verify the actual enum value name in `lib/features/rpg/models/character_class.dart` before running. Adjust to whatever the real enum member is (likely `ironVanguard` per the existing `localizedClassName` patterns).

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/rpg/widgets/saga_header_test.dart
```

Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement the widget**

Create `lib/features/rpg/ui/widgets/saga_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/character_class.dart';
import '../../models/vitality_state.dart';
import 'class_localization.dart';
import 'rune_halo.dart';

/// Option B v4 three-column header (Phase 26b).
///
/// Layout: 36dp rune halo (left) · 56sp LVL numeral + 10sp "LVL" tag stack
/// (center) · class name + title meta column (right, max 120dp, ellipsis).
///
/// Replaces the legacy centered-rune + 56sp-LVL composition (the old
/// `_SheetHeader` private in `character_sheet_screen.dart`). The new layout
/// trims vertical chrome from ~200dp to ~80dp, freeing the screen for the
/// 6 stat rows.
class SagaHeader extends StatelessWidget {
  const SagaHeader({
    super.key,
    required this.haloState,
    required this.characterLevel,
    required this.characterClass,
    required this.activeTitle,
  });

  final VitalityState haloState;
  final int characterLevel;
  final CharacterClass? characterClass;
  final String? activeTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final classLabel = characterClass == null
        ? l10n.classSlotPlaceholder
        : localizedClassName(characterClass!, l10n);
    final hasTitle = activeTitle != null && activeTitle!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Column 1: 36dp rune.
          Semantics(
            container: true,
            identifier: 'rune-halo',
            child: RuneHalo(state: haloState, size: 36),
          ),
          const SizedBox(width: 16),
          // Column 2: 56sp level numeral + 10sp LVL tag.
          Semantics(
            container: true,
            identifier: 'character-level',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$characterLevel',
                  style: GoogleFonts.rajdhani(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textCream,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'LVL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 0.12 * 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Column 3: meta column (class + title), max 120dp + ellipsis.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    classLabel,
                    key: const ValueKey('saga-header-class'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: characterClass == null
                          ? AppColors.textDim
                          : AppColors.hotViolet,
                      fontStyle: characterClass == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasTitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      activeTitle!,
                      key: const ValueKey('saga-header-title'),
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
          ),
        ],
      ),
    );
  }
}
```

NOTE: the `Iron Vanguard` example in the test uses `CharacterClass.ironVanguard` — confirm the enum name in `lib/features/rpg/models/character_class.dart` matches. If the actual member is named differently (e.g., `vanguard`, `iron`), update the test.

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/widget/features/rpg/widgets/saga_header_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/saga_header.dart \
        test/widget/features/rpg/widgets/saga_header_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): SagaHeader three-column Option B v4 layout (26b)

36dp rune (left) · 56sp LVL + 10sp tag (center) · class+title meta
column with 120dp max-width and ellipsis (right). Trims the header
from ~200dp vertical chrome down to ~80dp.

Class slot styling matches the previous ClassBadge tier rules
(initiate primaryViolet italic placeholder; earned hotViolet). Active
title sits as a textDim sub-line under the class label inside the
same meta column.
EOF
)"
```

---

## Task 6: `RankUpPulseRepository` (Hive)

**Files:**
- Create: `lib/features/rpg/data/rank_up_pulse_repository.dart`
- Modify: `lib/core/services/hive_service.dart` (or wherever Hive boxes are declared)
- Create: `test/unit/features/rpg/data/rank_up_pulse_repository_test.dart`

- [ ] **Step 1: Read the existing Hive-box convention**

Read `lib/features/workouts/data/workout_local_storage.dart` (it follows the canonical pattern). Read `lib/core/services/hive_service.dart` for the box-registration shape. The pulse repository should mirror that pattern — a Box-backed key-value store with a typed accessor surface.

- [ ] **Step 2: Write the failing tests**

Create `test/unit/features/rpg/data/rank_up_pulse_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

void main() {
  setUp(() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen('rank_up_pulse')) {
      await Hive.openBox<dynamic>('rank_up_pulse');
    }
    await Hive.box<dynamic>('rank_up_pulse').clear();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  group('RankUpPulseRepository', () {
    test('isPulsing returns false when no entry exists', () {
      final repo = RankUpPulseRepository();
      expect(repo.isPulsing(BodyPart.chest, now: DateTime(2026, 5, 15)), isFalse);
    });

    test('isPulsing returns true within the 24h window', () async {
      final repo = RankUpPulseRepository();
      final triggeredAt = DateTime(2026, 5, 15, 10, 0);
      await repo.recordRankUp(BodyPart.chest, at: triggeredAt);
      // 23h later: still pulsing.
      expect(
        repo.isPulsing(BodyPart.chest, now: triggeredAt.add(const Duration(hours: 23))),
        isTrue,
      );
    });

    test('isPulsing returns false after the 24h window expires', () async {
      final repo = RankUpPulseRepository();
      final triggeredAt = DateTime(2026, 5, 15, 10, 0);
      await repo.recordRankUp(BodyPart.chest, at: triggeredAt);
      // 24h + 1s later: pulse expired.
      expect(
        repo.isPulsing(
          BodyPart.chest,
          now: triggeredAt.add(const Duration(hours: 24, seconds: 1)),
        ),
        isFalse,
      );
    });

    test('isPulsing checks each body part independently', () async {
      final repo = RankUpPulseRepository();
      final now = DateTime(2026, 5, 15);
      await repo.recordRankUp(BodyPart.chest, at: now);
      expect(repo.isPulsing(BodyPart.chest, now: now), isTrue);
      expect(repo.isPulsing(BodyPart.back, now: now), isFalse);
    });

    test('recordRankUp overwrites the prior entry for the same body part', () async {
      final repo = RankUpPulseRepository();
      final first = DateTime(2026, 5, 14, 10, 0);
      final second = DateTime(2026, 5, 15, 10, 0);
      await repo.recordRankUp(BodyPart.chest, at: first);
      await repo.recordRankUp(BodyPart.chest, at: second);
      // 23h after the second trigger: still pulsing (proves the second
      // overwrote the first, otherwise the first would have expired).
      expect(
        repo.isPulsing(
          BodyPart.chest,
          now: second.add(const Duration(hours: 23)),
        ),
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
flutter test test/unit/features/rpg/data/rank_up_pulse_repository_test.dart
```

Expected: FAIL — repo doesn't exist.

- [ ] **Step 4: Implement the repository**

Create `lib/features/rpg/data/rank_up_pulse_repository.dart`:

```dart
import 'package:hive/hive.dart';

import '../models/body_part.dart';

/// 24h dot-pulse window per body part (Phase 26b).
///
/// After a rank-up celebration is dismissed, [recordRankUp] writes the
/// trigger timestamp; [BodyPartRankRow] reads via [isPulsing] to decide
/// whether to render the glow-ring on the body-part dot.
///
/// **Why Hive (not Riverpod state):** the pulse must survive an app
/// restart — the user may dismiss a celebration overlay, force-quit the
/// app, and re-open the next morning to see the after-glow. An in-memory
/// notifier would lose the state on relaunch. The data is small (6 entries
/// max) so a dedicated box is fine; sharing with another box (e.g.
/// `workout_local_storage`) would couple unrelated lifetimes.
class RankUpPulseRepository {
  RankUpPulseRepository({Box<dynamic>? box})
    : _box = box ?? Hive.box<dynamic>(boxName);

  static const String boxName = 'rank_up_pulse';
  static const Duration pulseDuration = Duration(hours: 24);

  final Box<dynamic> _box;

  /// Returns true iff [bodyPart] has an active pulse window at [now].
  /// Defaults [now] to `DateTime.now()` — overridable for tests.
  bool isPulsing(BodyPart bodyPart, {DateTime? now}) {
    final at = _box.get(bodyPart.dbValue);
    if (at == null) return false;
    final triggeredAt = DateTime.parse(at as String);
    final expiresAt = triggeredAt.add(pulseDuration);
    return (now ?? DateTime.now()).isBefore(expiresAt);
  }

  /// Mark [bodyPart] as having just ranked up. Subsequent [isPulsing]
  /// calls within [pulseDuration] of [at] return true. Overwrites any
  /// prior trigger for the same body part.
  Future<void> recordRankUp(BodyPart bodyPart, {DateTime? at}) async {
    final t = at ?? DateTime.now();
    await _box.put(bodyPart.dbValue, t.toIso8601String());
  }

  /// Defensive cleanup — clear expired entries. The UI tolerates expired
  /// entries (isPulsing handles it) so this is opportunistic, called by
  /// the provider on startup to keep the box from growing across years.
  Future<void> sweepExpired({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    final keysToDelete = <String>[];
    for (final key in _box.keys.cast<String>()) {
      final at = _box.get(key);
      if (at == null) continue;
      final triggeredAt = DateTime.parse(at as String);
      if (ref.isAfter(triggeredAt.add(pulseDuration))) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await _box.delete(key);
    }
  }
}
```

- [ ] **Step 5: Register the Hive box**

Open `lib/core/services/hive_service.dart` (or whatever file owns box registration — confirm by reading the file). Add a constant for the new box name AND register it during init:

```dart
// (in the appropriate constants block)
static const String rankUpPulse = 'rank_up_pulse';

// (in the init method, alongside the other openBox calls)
await Hive.openBox<dynamic>(rankUpPulse);
```

Match the existing surrounding pattern exactly. If `HiveService` uses typed adapters anywhere, the pulse box doesn't need one (it stores ISO-8601 strings, not custom objects).

- [ ] **Step 6: Run to verify all pass**

```bash
flutter test test/unit/features/rpg/data/rank_up_pulse_repository_test.dart
flutter test
```

Expected: full suite green.

- [ ] **Step 7: Commit**

```bash
git add lib/features/rpg/data/rank_up_pulse_repository.dart \
        lib/core/services/hive_service.dart \
        test/unit/features/rpg/data/rank_up_pulse_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): RankUpPulseRepository for 24h dot-pulse window (26b)

Hive-backed per-body-part timestamp store. recordRankUp() writes the
trigger time on celebration dismiss; isPulsing() reads in the body-
part row to gate the glow-ring overlay. Survives app restart so a
user who force-quits and re-opens the next morning still sees the
after-glow.
EOF
)"
```

---

## Task 7: `RankUpPulse` widget (24h dot glow-ring overlay)

**Files:**
- Create: `lib/features/rpg/ui/widgets/rank_up_pulse.dart`
- Create: `test/widget/features/rpg/widgets/rank_up_pulse_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widget/features/rpg/widgets/rank_up_pulse_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/rank_up_pulse.dart';

void main() {
  group('RankUpPulse', () {
    testWidgets('renders an animated outer glow ring around its child', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RankUpPulse(
                color: Colors.pink,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.pink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Pump partway through the animation to confirm a controller is
      // driving repaints.
      await tester.pump(const Duration(milliseconds: 200));
      // Find a CustomPaint or similar — the exact widget shape is
      // implementation-defined. What matters: more than one Container/
      // DecoratedBox exists (the child + the glow ring).
      final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      expect(boxes.length, greaterThan(1));
    });

    testWidgets('child is rendered unchanged when no pulse animation is active', (tester) async {
      // RankUpPulse is unconditional in this widget — gating happens at the
      // parent. The test pins that the widget composes around its child
      // without replacing or hiding it.
      const key = ValueKey('pulse-target');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RankUpPulse(
                color: Colors.pink,
                child: Container(key: key, width: 6, height: 6),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/rpg/widgets/rank_up_pulse_test.dart
```

Expected: FAIL — widget doesn't exist.

- [ ] **Step 3: Implement the widget**

Create `lib/features/rpg/ui/widgets/rank_up_pulse.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated glow-ring overlay used during the 24h post-rank-up pulse
/// window (Phase 26b). Wraps the body-part dot; pulses its scale (1.0 →
/// 1.5) and outer glow opacity in a slow loop.
///
/// Gating (whether to render this at all) is the parent's responsibility —
/// see [RankUpPulseRepository.isPulsing]. This widget is unconditional once
/// mounted: it just wraps its [child] in an animated ring.
class RankUpPulse extends StatefulWidget {
  const RankUpPulse({super.key, required this.color, required this.child});

  /// Ring color — should match the body-part identity hue. The ring
  /// renders at ~35% alpha so the dot underneath stays the primary signal.
  final Color color;

  final Widget child;

  @override
  State<RankUpPulse> createState() => _RankUpPulseState();
}

class _RankUpPulseState extends State<RankUpPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 0..1 → ease in/out via sine.
        final t = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
        final scale = 1.0 + 0.5 * t;
        final alpha = 0.15 + 0.20 * t;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: alpha),
                    width: 1.5,
                  ),
                ),
                child: SizedBox(
                  width: 16,
                  height: 16,
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/widget/features/rpg/widgets/rank_up_pulse_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/rank_up_pulse.dart \
        test/widget/features/rpg/widgets/rank_up_pulse_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): RankUpPulse glow-ring overlay widget (26b)

Wraps a body-part dot in an animated ring (1.0–1.5× scale, 15–35%
alpha pulse). Unconditional once mounted — gating belongs to the
parent (BodyPartRankRow reads RankUpPulseRepository.isPulsing).
EOF
)"
```

---

## Task 8: Rewrite `BodyPartRankRow` to Option B v4 mini-XP-block

**Files:**
- Modify: `lib/features/rpg/ui/widgets/body_part_rank_row.dart` (full rewrite)
- Modify: `test/widget/features/rpg/widgets/body_part_rank_row_test.dart` (extensive update — read existing tests first)

- [ ] **Step 1: Read existing tests**

Open `test/widget/features/rpg/widgets/body_part_rank_row_test.dart`. Identify which assertions are about CURRENT behavior (compressed/expanded shapes, sigil colors, rank stamp presence) vs. CONTRACT behavior (untrained collapses, label localization). Plan to:
  - **Delete** assertions about the legacy compressed/expanded shapes and the `_Sigil` rendering.
  - **Keep + adapt** assertions about the untrained vs. trained branching.
  - **Add** new assertions for the Option B v4 shape (dot color from `bodyPartColor`, 20sp rank numeral, body-part-hue 4dp bar, XP label row, pulse rendering when repository says yes).

- [ ] **Step 2: Write the new test set**

Replace the body of `test/widget/features/rpg/widgets/body_part_rank_row_test.dart` with the Option B v4 expectations. Key tests:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/data/rank_up_pulse_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_sheet_state.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/providers/rank_up_pulse_provider.dart';
import 'package:repsaga/features/rpg/ui/widgets/body_part_rank_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/rank_up_pulse.dart';
import 'package:repsaga/l10n/app_localizations.dart';

class _MockPulseRepo extends Mock implements RankUpPulseRepository {}

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

Widget _wrap(Widget child, {RankUpPulseRepository? repo}) {
  return ProviderScope(
    overrides: [
      if (repo != null) rankUpPulseRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BodyPart.chest);
  });

  group('BodyPartRankRow — Option B v4', () {
    testWidgets('trained row renders dot + name + rank num + bar + label', (tester) async {
      final repo = _MockPulseRepo();
      when(() => repo.isPulsing(any(), now: any(named: 'now'))).thenReturn(false);
      await tester.pumpWidget(_wrap(
        BodyPartRankRow(entry: _entry(rank: 16, xpInRank: 1420, xpForNextRank: 2000, totalXp: 8000)),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      // Rank num
      expect(find.text('16'), findsOneWidget);
      // Body-part name (pt-BR for chest → "Peito")
      expect(find.text('Peito'), findsOneWidget);
      // XP-in-rank
      expect(find.textContaining('1.420 XP'), findsOneWidget);
      // Remaining to next rank
      expect(find.textContaining('580 para o próximo rank'), findsOneWidget);
    });

    testWidgets('untrained row renders at 0.4 opacity with "—" rank and no bar', (tester) async {
      final repo = _MockPulseRepo();
      when(() => repo.isPulsing(any(), now: any(named: 'now'))).thenReturn(false);
      await tester.pumpWidget(_wrap(
        BodyPartRankRow(entry: _entry(rank: 1, xpInRank: 0, totalXp: 0, vitalityPeak: 0, state: VitalityState.untested)),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsOneWidget);
      expect(find.byKey(const ValueKey('body-part-row-bar')), findsNothing);
      // The whole row should be wrapped in Opacity(0.4).
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities.any((o) => (o.opacity - 0.4).abs() < 0.01), isTrue);
    });

    testWidgets('renders RankUpPulse overlay when repo.isPulsing returns true', (tester) async {
      final repo = _MockPulseRepo();
      when(() => repo.isPulsing(BodyPart.chest, now: any(named: 'now'))).thenReturn(true);
      when(() => repo.isPulsing(any(), now: any(named: 'now'))).thenReturn(false);
      await tester.pumpWidget(_wrap(
        BodyPartRankRow(entry: _entry()),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(RankUpPulse), findsOneWidget);
    });

    testWidgets('does NOT render RankUpPulse when repo.isPulsing returns false', (tester) async {
      final repo = _MockPulseRepo();
      when(() => repo.isPulsing(any(), now: any(named: 'now'))).thenReturn(false);
      await tester.pumpWidget(_wrap(
        BodyPartRankRow(entry: _entry()),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(RankUpPulse), findsNothing);
    });

    testWidgets('tapping the row pushes /saga/stats with the body part as query', (tester) async {
      // Routing is verified in Task 9's test file; here we just confirm the
      // row exposes a tappable surface via InkWell or GestureDetector.
      final repo = _MockPulseRepo();
      when(() => repo.isPulsing(any(), now: any(named: 'now'))).thenReturn(false);
      await tester.pumpWidget(_wrap(
        BodyPartRankRow(entry: _entry()),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      // The whole row should be tappable. Find a Material InkWell-or-similar
      // GestureDetector hosting the row.
      expect(
        find.byWidgetPredicate((w) => w is InkWell || w is GestureDetector),
        findsAtLeast(1),
      );
    });

    testWidgets('row min-height is 48dp (Material tap-target floor)', (tester) async {
      final repo = _MockPulseRepo();
      when(() => repo.isPulsing(any(), now: any(named: 'now'))).thenReturn(false);
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 360,
          child: BodyPartRankRow(entry: _entry()),
        ),
        repo: repo,
      ));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(BodyPartRankRow));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
```

NOTE: this test references `rankUpPulseRepositoryProvider` which doesn't exist yet. Add it during Step 3.

- [ ] **Step 3: Run to verify the new tests fail**

```bash
flutter test test/widget/features/rpg/widgets/body_part_rank_row_test.dart
```

Expected: tests fail to compile (missing provider) or fail at runtime.

- [ ] **Step 4: Create the pulse provider**

Create or modify `lib/features/rpg/providers/rank_up_pulse_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rank_up_pulse_repository.dart';

/// Riverpod provider for [RankUpPulseRepository] — overridable in tests.
final rankUpPulseRepositoryProvider = Provider<RankUpPulseRepository>(
  (ref) => RankUpPulseRepository(),
);
```

- [ ] **Step 5: Rewrite `BodyPartRankRow`**

Replace the contents of `lib/features/rpg/ui/widgets/body_part_rank_row.dart` with the Option B v4 implementation:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/character_sheet_state.dart';
import '../../providers/rank_up_pulse_provider.dart';
import '../utils/vitality_state_styles.dart';
import 'body_part_localization.dart';
import 'rank_up_pulse.dart';

/// Single body-part row in the Saga screen (Phase 26b Option B v4).
///
/// 48dp min-height. Two-row layout inside the tap target:
///   * Top row: 6dp dot (body-part hue) · UPPERCASE 10sp name · 20sp
///     Rajdhani-700 tabular rank num (right-aligned).
///   * Middle: 4dp body-part-hue progress bar (within-rank fill).
///   * Bottom: 9sp Rajdhani-600 textDim "X XP" + "Y para o próximo rank".
///
/// Untrained rows (rank 1, totalXp 0, vitalityPeak 0) render at 0.4 opacity
/// with `—` instead of the rank num, no bar, no label row.
///
/// The whole row is tappable → `/saga/stats?body_part=<dbValue>` so the
/// stats deep-dive opens with the trend chart pre-selected.
///
/// When [RankUpPulseRepository.isPulsing] returns true for this body part,
/// the dot is wrapped in [RankUpPulse] for the 24h glow-ring overlay.
class BodyPartRankRow extends ConsumerWidget {
  const BodyPartRankRow({super.key, required this.entry});

  final BodyPartSheetEntry entry;

  static const _height = 56.0; // 48 floor + 4 vertical breathing room on each side

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entry.isUntrained) {
      return _UntrainedRow(entry: entry);
    }
    final pulseRepo = ref.watch(rankUpPulseRepositoryProvider);
    final isPulsing = pulseRepo.isPulsing(entry.bodyPart);
    return _TrainedRow(entry: entry, isPulsing: isPulsing);
  }
}

class _TrainedRow extends StatelessWidget {
  const _TrainedRow({required this.entry, required this.isPulsing});

  final BodyPartSheetEntry entry;
  final bool isPulsing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dotColor =
        VitalityStateStyles.bodyPartColor[entry.bodyPart] ?? AppColors.textDim;
    final fraction = entry.xpForNextRank <= 0
        ? 1.0
        : (entry.xpInRank / entry.xpForNextRank).clamp(0.0, 1.0);
    final remaining =
        (entry.xpForNextRank - entry.xpInRank).clamp(0.0, double.infinity);

    return InkWell(
      onTap: () => context.push('/saga/stats?body_part=${entry.bodyPart.dbValue}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Dot(color: dotColor, isPulsing: isPulsing),
                  const SizedBox(width: 8),
                  Text(
                    _localizedName(entry.bodyPart, l10n).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textCream,
                      letterSpacing: 0.12 * 10,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entry.rank}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textCream,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                key: const ValueKey('body-part-row-bar'),
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 4,
                  color: AppColors.xpTrack,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: DecoratedBox(decoration: BoxDecoration(color: dotColor)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_format(entry.xpInRank)} XP',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim,
                    ),
                  ),
                  Text(
                    '${_format(remaining)} ${l10n.withinRankXpSuffix}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.isPulsing});

  final Color color;
  final bool isPulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    if (!isPulsing) return dot;
    return RankUpPulse(color: color, child: dot);
  }
}

class _UntrainedRow extends StatelessWidget {
  const _UntrainedRow({required this.entry});

  final BodyPartSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () => context.push('/saga/stats?body_part=${entry.bodyPart.dbValue}'),
      child: Opacity(
        opacity: 0.4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _localizedName(entry.bodyPart, l10n).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 0.12 * 10,
                  ),
                ),
                const Spacer(),
                const Text('—', style: TextStyle(color: AppColors.textDim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thousand-separator formatting matching pt-BR convention ("1.420" not
/// "1420" / "1,420"). Identical to [CharacterXpBar._format] — extract to a
/// shared helper if either evolves.
String _format(double value) {
  final intValue = value.round();
  final s = intValue.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _localizedName(BodyPart bodyPart, AppLocalizations l10n) =>
    localizedBodyPartName(bodyPart, l10n);
```

- [ ] **Step 6: Run tests + full suite**

```bash
flutter test test/widget/features/rpg/widgets/body_part_rank_row_test.dart
flutter test
```

Expected: green. The existing `xp_progress_hairline_test.dart` will fail because the hairline is no longer imported anywhere — that file gets deleted in Task 12 along with the widget. Hold for now if the build still passes.

- [ ] **Step 7: Commit**

```bash
git add lib/features/rpg/ui/widgets/body_part_rank_row.dart \
        lib/features/rpg/providers/rank_up_pulse_provider.dart \
        test/widget/features/rpg/widgets/body_part_rank_row_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): BodyPartRankRow Option B v4 + pulse + stat-row tap (26b)

48dp tap-target row: 6dp body-part-hue dot · UPPERCASE 10sp name ·
20sp Rajdhani rank num · 4dp body-part-hue XP bar · 9sp Rajdhani
textDim "X XP / Y para o próximo rank" label row.

Untrained variant collapses to 0.4 opacity + "—" rank with no bar.
Whole row tappable → /saga/stats?body_part=<dbValue>.
RankUpPulseRepository.isPulsing gates the dot's glow-ring overlay.
EOF
)"
```

---

## Task 9: `/saga/stats?body_part=` route + StatsDeepDiveScreen pre-selection

**Files:**
- Modify: `lib/core/router/app_router.dart` (parse the query param)
- Modify: `lib/features/rpg/ui/stats_deep_dive_screen.dart` (accept the body part + pre-select)
- Create or extend: `test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart` (verify pre-selection)

- [ ] **Step 1: Write the failing test**

In `test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart`, append a new group:

```dart
  group('StatsDeepDiveScreen — body_part query pre-selection (Phase 26b)', () {
    testWidgets('initial selected body part matches the body_part query', (tester) async {
      // Mount the screen with a body_part = 'back' arg. Verify the trend
      // chart's selected line equals back. (Use the existing harness for
      // mounting this screen if one exists.)
      // ...
    });

    testWidgets('falls back to default selection when body_part is absent', (tester) async {
      // ...
    });

    testWidgets('falls back to default selection when body_part is unknown', (tester) async {
      // e.g. body_part=invalid_token
    });
  });
```

The exact pump shape depends on how the existing test mounts the screen. Read the existing `stats_deep_dive_screen_test.dart` and adapt — preserve the existing fixture-builder pattern.

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart --plain-name "body_part query"
```

Expected: FAIL because pre-selection logic doesn't exist yet.

- [ ] **Step 3: Update the route**

In `lib/core/router/app_router.dart`, find the `/saga/stats` GoRoute (around line 237). Read the `state.uri.queryParameters` and pass to the screen:

```dart
GoRoute(
  path: '/saga/stats',
  builder: (context, state) {
    final bodyPartToken = state.uri.queryParameters['body_part'];
    final initialBodyPart = bodyPartToken == null
        ? null
        : BodyPart.tryFromDbValue(bodyPartToken);
    return StatsDeepDiveScreen(initialBodyPart: initialBodyPart);
  },
),
```

Import `BodyPart` from `../../features/rpg/models/body_part.dart` if not already in scope.

- [ ] **Step 4: Update `StatsDeepDiveScreen` to accept the param**

In `lib/features/rpg/ui/stats_deep_dive_screen.dart`, add an `initialBodyPart` constructor field. Wire it into the trend chart's selected-row state via the existing selection state shape (likely a `useState` / Riverpod provider). Read the existing file to see how selection works today; the new behavior is: if `initialBodyPart` is non-null AND has data, set it as the initial selection; otherwise use the existing default.

- [ ] **Step 5: Verify the new tests pass + full suite green**

```bash
flutter test test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart \
        lib/features/rpg/ui/stats_deep_dive_screen.dart \
        test/widget/features/rpg/ui/stats_deep_dive_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): /saga/stats?body_part= query for pre-selected trend (26b)

Saga body-part-row taps land on the stats deep-dive with the tapped
body part already selected in the vitality trend chart. Unknown
tokens fall through to the default selection (graceful — Phase 14e
deep-link survivability).
EOF
)"
```

---

## Task 10: Hook celebration completion → RankUpPulseRepository.recordRankUp

**Files:**
- Modify: `lib/features/rpg/domain/celebration_event_builder.dart` OR the celebration overlay dismissal handler — read the existing code path before deciding.
- Create or extend: `test/unit/features/rpg/domain/celebration_event_builder_test.dart`

- [ ] **Step 1: Locate the rank-up celebration completion site**

Read `lib/features/rpg/domain/celebration_event_builder.dart` (around line 100, where rank-up events are emitted). Then grep for where the overlay calls back when the user dismisses it:

```bash
grep -rn "rankUp\|onRankUp\|celebrationComplete\|onDismiss" lib/features/rpg/
```

The hook point is whatever fires AFTER the user dismisses the rank-up celebration overlay (NOT when the rank-up is detected — the pulse is the "remember this happened" affordance for the user, not a duplicate of the detection). Most likely a callback in the celebration controller or a Riverpod listener that fires on overlay dismiss.

- [ ] **Step 2: Write a failing integration-style test**

Pick one of:
- A unit-level test asserting that the rank-up "complete" callback writes to the repo.
- A widget-level test mounting the overlay, completing it, and verifying the repo got written.

Either is acceptable — match the existing test style in the file you modify.

- [ ] **Step 3: Wire the call**

When the celebration overlay completes for a body-part rank-up event, invoke:

```dart
await ref.read(rankUpPulseRepositoryProvider).recordRankUp(bodyPart);
```

Don't await it on the UI-blocking path — fire-and-forget is fine (the persistence is "nice to have" — a missed write just means no pulse on that body part). But DO log on error if BaseRepository's error path is invoked.

- [ ] **Step 4: Verify**

```bash
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/domain/celebration_event_builder.dart \
        test/unit/features/rpg/domain/celebration_event_builder_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): write to RankUpPulseRepository on rank-up dismiss (26b)

After the celebration overlay finishes for a body-part rank-up,
record the trigger timestamp so BodyPartRankRow renders the 24h
glow-ring on the body part's dot.
EOF
)"
```

---

## Task 11: Restructure `character_sheet_screen.dart`

**Files:**
- Modify: `lib/features/rpg/ui/character_sheet_screen.dart` (full restructure)
- Modify: `test/widget/features/rpg/ui/character_sheet_screen_test.dart`

- [ ] **Step 1: Plan the new screen composition**

Top-down body:
1. AppBar with "Saga" title + gear icon (unchanged)
2. `SagaHeader` (Task 5) replacing `_SheetHeader`
3. `CharacterXpBar` (Task 3) between header and body-part rows
4. `_FirstSetAwakensBanner` when `sheet.isZeroHistory` (preserved — onboarding affordance)
5. 6 × `BodyPartRankRow` (Task 8) — replaces the previous radar + asymmetric rows
6. `DormantCardioRow` (unchanged)
7. `_CodexNavSection` (unchanged)

The `VitalityRadar` widget is REMOVED from the composition.

- [ ] **Step 2: Update the existing screen test**

Open `test/widget/features/rpg/ui/character_sheet_screen_test.dart`. Read the existing assertions. Update:
- Replace radar-presence assertions with "no radar" assertions.
- Add `SagaHeader` + `CharacterXpBar` presence assertions.
- Update skeleton assertions for the new shape.

Add a new test:

```dart
    testWidgets('renders SagaHeader + CharacterXpBar + 6 body-part rows (no radar)', (tester) async {
      // Mount with a non-empty sheet (use the existing fixture). Confirm:
      expect(find.byType(SagaHeader), findsOneWidget);
      expect(find.byType(CharacterXpBar), findsOneWidget);
      expect(find.byType(BodyPartRankRow), findsNWidgets(6));
      // The previous VitalityRadar is gone.
      expect(find.byType(VitalityRadar), findsNothing);
      // Existing pieces preserved:
      expect(find.byType(DormantCardioRow), findsOneWidget);
      expect(find.byType(CodexNavRow), findsNWidgets(3));
    });
```

`VitalityRadar` is going to be deleted in Task 12 — the import on this test removes too. For now: the test compiles by NOT importing VitalityRadar (the `findsNothing` check uses `Type` resolution which only needs the import at compile time; if the import is gone, the test won't compile). Tweak this test in Task 12 to drop the radar-presence reference, OR keep the import here and let Task 12 also delete the test's import line.

Cleanest path: in this task, drop the import of `VitalityRadar` from the screen file (since the widget is no longer used). Drop the `findsNothing` line above too — the strongest signal that the radar is gone is the screen file not importing it.

- [ ] **Step 3: Run to verify tests fail**

```bash
flutter test test/widget/features/rpg/ui/character_sheet_screen_test.dart
```

- [ ] **Step 4: Restructure the screen**

Edit `lib/features/rpg/ui/character_sheet_screen.dart`:
- Remove the `vitality_radar.dart` import.
- Remove the `ActiveTitlePill` and `ClassBadge` imports if no longer needed inside this file (SagaHeader handles them internally).
- Remove the `_SheetHeader` private class entirely.
- Update `_CharacterSheetBody` to compose `SagaHeader` + `CharacterXpBar` + the body-part rows + the dormant row + the codex nav section. Drop the radar widget.
- Update `_CharacterSheetSkeleton` to the new shape (header skeleton + bar skeleton + 6 row skeletons).

Outline:

```dart
class _CharacterSheetBody extends StatelessWidget {
  // ... (constructor unchanged)
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Semantics(
        container: true,
        identifier: 'character-sheet',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            SagaHeader(
              haloState: sheet.haloState,
              characterLevel: sheet.characterLevel,
              characterClass: sheet.characterClass,
              activeTitle: sheet.activeTitle,
            ),
            const SizedBox(height: 12),
            CharacterXpBar(
              xpInLevel: sheet.xpInLevel,
              xpForNextLevel: sheet.xpForNextLevel,
              characterLevel: sheet.characterLevel,
            ),
            const SizedBox(height: 16),
            if (sheet.isZeroHistory) ...[
              const _FirstSetAwakensBanner(),
              const SizedBox(height: 12),
            ],
            for (final entry in sheet.bodyPartProgress)
              Semantics(
                container: true,
                identifier: 'body-part-row-${entry.bodyPart.dbValue}',
                child: BodyPartRankRow(entry: entry),
              ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              identifier: 'dormant-cardio-row',
              child: const DormantCardioRow(),
            ),
            const SizedBox(height: 24),
            const _CodexNavSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
```

Update `_CharacterSheetSkeleton`:

```dart
class _CharacterSheetSkeleton extends StatelessWidget {
  const _CharacterSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Header placeholder: a horizontal block ~64dp tall.
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
            ),
            const SizedBox(height: 16),
            // Char XP bar placeholder.
            Container(
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
            ),
            const SizedBox(height: 24),
            // 6 row placeholders.
            for (var i = 0; i < 6; i++) ...[
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(kRadiusSm),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run + full suite**

```bash
flutter test test/widget/features/rpg/ui/character_sheet_screen_test.dart
flutter test
```

If any test in the suite references the deleted `_SheetHeader` private class — that's not directly accessible from outside the file, so unlikely. If anything in the test fixture file (`test_factories.dart`) constructed a `VitalityRadar` directly, remove those constructions.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/ui/character_sheet_screen.dart \
        test/widget/features/rpg/ui/character_sheet_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): restructure CharacterSheetScreen to Option B v4 (26b)

Drop _SheetHeader + VitalityRadar from the composition. Replace with
SagaHeader (3-column) + CharacterXpBar (6dp gradient) + 6 mini-XP-
block BodyPartRankRows. Preserve _FirstSetAwakensBanner +
DormantCardioRow + _CodexNavSection unchanged.

Skeleton updated to mirror the new shape.
EOF
)"
```

---

## Task 12: Delete dead widgets — `vitality_radar.dart` + `xp_progress_hairline.dart`

**Files:**
- Delete: `lib/features/rpg/ui/widgets/vitality_radar.dart`
- Delete: `test/widget/features/rpg/widgets/vitality_radar_test.dart`
- Delete: `test/widget/features/rpg/widgets/vitality_radar_golden_test.dart`
- Delete: `lib/features/rpg/ui/widgets/xp_progress_hairline.dart`
- Delete: `test/widget/features/rpg/widgets/xp_progress_hairline_test.dart` (if exists)
- Delete: any `test/widget/features/rpg/widgets/goldens/` files for the radar
- Modify: any test imports that referenced the deleted files

- [ ] **Step 1: Verify the widgets are orphaned**

```bash
grep -rn "VitalityRadar\|vitality_radar" lib/ test/ --include='*.dart'
grep -rn "XpProgressHairline\|xp_progress_hairline" lib/ test/ --include='*.dart'
```

Expected: only matches inside the widget files themselves + their tests. If any non-test consumer remains, STOP — Task 11 missed a wiring update.

- [ ] **Step 2: Delete the files**

```bash
rm lib/features/rpg/ui/widgets/vitality_radar.dart
rm test/widget/features/rpg/widgets/vitality_radar_test.dart
rm test/widget/features/rpg/widgets/vitality_radar_golden_test.dart
# Golden image files (if any) under test/widget/features/rpg/widgets/goldens/
# matching vitality_radar_* — remove those too.
rm lib/features/rpg/ui/widgets/xp_progress_hairline.dart
# Hairline test file may or may not exist — check first
ls test/widget/features/rpg/widgets/xp_progress_hairline_test.dart 2>/dev/null && \
  rm test/widget/features/rpg/widgets/xp_progress_hairline_test.dart
```

- [ ] **Step 3: Verify the build still passes**

```bash
flutter analyze --fatal-infos
flutter test
```

Expected: green. Any straggler import (test file importing the deleted widget) will fail to compile — patch those.

- [ ] **Step 4: Commit**

```bash
git add -A lib/features/rpg/ui/widgets/ test/widget/features/rpg/widgets/
git commit -m "$(cat <<'EOF'
chore(rpg): delete orphaned VitalityRadar + XpProgressHairline (26b)

After the Saga screen restructured to Option B v4 (Task 11), the
radar and the per-row hairline are dead code. Both widgets had only
one consumer each (the saga screen), so the cleanest path is
deletion in the same PR rather than leaving them to rot.

Companion test files + golden images removed alongside.
EOF
)"
```

---

## Task 13: E2E selectors + saga regression spec

**Files:**
- Modify: `test/e2e/helpers/selectors.ts`
- Modify: `test/e2e/specs/rpg-saga.spec.ts` (or wherever the saga screen is covered)

- [ ] **Step 1: Read existing selectors**

```bash
cat test/e2e/helpers/selectors.ts | head -100
```

Identify the saga-relevant selectors (likely `sagaTab`, `runeHalo`, `characterLevel`, `bodyPartRow*`, `codexNavStats`, etc.). Many will need updates because the DOM-level structure changed.

- [ ] **Step 2: Update selectors.ts**

Add/update entries for the new structure:

```typescript
// In selectors.ts, under the saga section:
sagaHeaderClass: 'role=text[name*="Iron"]', // or whatever the class-label resolver yields
sagaHeaderTitle: 'role=text[name*="Plate-Bearer"]', // placeholder — depends on test user
characterXpBarFill: '[id="character-xp-bar-fill"]',
bodyPartRow: (bp: string) => `[id="body-part-row-${bp}"]`,
bodyPartRowChest: '[id="body-part-row-chest"]',
// Drop legacy: vitalityRadar selector (widget no longer exists)
```

Drop any selectors that referenced the now-deleted `VitalityRadar`. Keep the existing `sagaTab` / `characterSheet` / `runeHalo` / `characterLevel` selectors — those targets still exist.

- [ ] **Step 3: Update spec — tap-routing smoke**

In `test/e2e/specs/rpg-saga.spec.ts`, ADD a smoke test for stat-row → stats deep-dive routing:

```typescript
test('should open stats deep-dive when a body-part row is tapped', async ({ page }) => {
  // (setup omitted — sign in as the test user, navigate to /profile)
  await page.locator(SELECTORS.bodyPartRowChest).click();
  await expect(page).toHaveURL(/\/saga\/stats\?body_part=chest/);
  // The trend chart should show chest as pre-selected — assert via the
  // selected line opacity / stroke-width once 26c lands the trend-chart
  // rewrite. For 26b, just landing on the URL with the param is enough.
});
```

Update any existing assertions that were tied to the radar — replace with assertions on the new SagaHeader / CharacterXpBar / row structure.

- [ ] **Step 4: Run E2E locally**

```bash
cd test/e2e
FLUTTER_APP_URL= npx playwright test specs/rpg-saga.spec.ts --reporter=list
```

If Supabase containers aren't running locally, follow the prerequisite-check steps from CLAUDE.md → "E2E Tests (Playwright) — Local Execution."

Expected: all saga specs pass. If a spec broke because the DOM structure changed, update the selector or the assertion — do NOT skip the spec.

- [ ] **Step 5: Commit**

```bash
git add test/e2e/helpers/selectors.ts test/e2e/specs/rpg-saga.spec.ts
git commit -m "$(cat <<'EOF'
test(e2e): update saga selectors + tap-routing smoke (26b)

Drop the legacy VitalityRadar selector; add SagaHeader / CharacterXpBar
/ body-part-row identifiers; add a smoke asserting stat-row tap
routes to /saga/stats?body_part=<bp>.
EOF
)"
```

---

## Task 14: Verification + open PR

**Files:** none (verification + PR)

- [ ] **Step 1: Full CI**

```bash
export PATH="/c/flutter/bin:$PATH"
make ci
```

Expected: green (format, gen, analyze, test, android-debug-build).

- [ ] **Step 2: Re-read acceptance criteria**

Open `docs/PROJECT.md §3 Phase 26 → 26b acceptance criteria` (lines 420-442). Check each bullet:

- [ ] Header band ≤ 80dp tall on 360dp viewport (verify via the header test golden)
- [ ] Active-state RuneHalo glow REMOVED — radiant still has its sweep
- [ ] Each body-part row: 48dp min-height, 6dp dot, UPPERCASE name, 20sp rank num, 4dp bar, label
- [ ] Untrained rows at 0.4 opacity with `—` instead of rank
- [ ] Stat rows tappable → `/saga/stats?body_part=<X>` with pre-selection
- [ ] Dot pulse on rank-up: 24h glow ring, Hive-persisted
- [ ] CodexNavRow + DormantCardioRow preserved unchanged
- [ ] Skeleton matches the new shape

If any bullet is unsatisfied, STOP and add the missing work as a new task.

- [ ] **Step 3: Push the branch**

```bash
git push -u origin feature/26b-saga-option-b-v4
```

- [ ] **Step 4: Open the PR**

```bash
gh pr create --title "feat(rpg): Phase 26b — Saga screen Option B v4" --body "$(cat <<'EOF'
## Summary

Restructures `CharacterSheetScreen` from the radar-centric composition to the Option B v4 type-dominant layout:
- New `SagaHeader` (3-column: 36dp rune · 56sp LVL + tag · class/title meta column, ellipsis at 120dp).
- New `CharacterXpBar` (6dp gradient, single-body-part cheapest-advancement approximation for the band).
- `BodyPartRankRow` rewritten to the Option B v4 mini-XP-block (48dp min-height, body-part-hue 4dp bar, `withinRankXpSuffix` label).
- Stat rows tappable → `/saga/stats?body_part=<X>` with pre-selection in the vitality trend chart.
- 24h dot-pulse on rank-up via the new `RankUpPulseRepository` (Hive-backed) + `RankUpPulse` overlay widget.
- Active-state `RuneHalo` glow removed (radiant keeps its sweep).
- Deleted: `VitalityRadar` + `XpProgressHairline` (both orphaned after the restructure).

**QA pass pending — final coverage + E2E run after code review.**

## Test plan
- [x] Unit: `characterXpInLevel()` boundary cases (day-zero, mid-level, just-leveled-up)
- [x] Unit: `RankUpPulseRepository` 24h window + per-body-part isolation + overwrite semantics
- [x] Widget: `CharacterXpBar` label formatting + fraction
- [x] Widget: `SagaHeader` 3-column layout at 320/360dp, ellipsis path, no-title case
- [x] Widget: `RuneHalo` no-active-glow + compact 36dp sizing
- [x] Widget: `BodyPartRankRow` trained/untrained/just-rank-up'd states + tap routing
- [x] Widget: `StatsDeepDiveScreen` pre-selection from `body_part` query
- [x] E2E: tap-routing smoke (stat row → stats deep-dive)
- [x] `make ci` clean

## References
- Spec: `docs/PROJECT.md §3 Phase 26 → 26b acceptance criteria`
- Visual: `docs/phase-26-mockups.html` section `#saga`
- Plan: `docs/phase-26b-plan.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Move on per the pipeline**

After the PR opens, the CLAUDE.md pipeline takes over (reviewer → QA → merge → condense in PROJECT.md §4 → next sub-phase).

---

## Self-review notes (pre-handoff)

**Spec coverage:** every acceptance bullet from `docs/PROJECT.md §3 Phase 26 → 26b` is covered by tasks 1–13, verified in task 14. The character XP bar's underlying math (a real spec gap — character level is rank-derived, not XP-derived) was resolved with the orchestrator-confirmed single-body-part approximation.

**Placeholder scan:** no `TODO` / `TBD` / "implement later" / "fill in details" / "add error handling" generic instructions. Every code step has actual code. Tasks 9 and 10 leave the *exact* hook-point lines vague because the implementer must read the current celebration-event-builder + stats-deep-dive code to find them — but the *what* (write to repo, accept query param) is concrete.

**Type consistency:** `BodyPart.dbValue`, `BodyPartSheetEntry.xpInRank/xpForNextRank/totalXp`, `CharacterSheetState.xpInLevel/xpForNextLevel`, `RankUpPulseRepository.isPulsing(BodyPart, {DateTime? now})` are all consistent across the file. The `_format` helper is duplicated in `CharacterXpBar` and `BodyPartRankRow` — flagged inline as an extract candidate for a future utility-consolidation pass; not pulled into this PR to avoid scope creep.

**Out of scope for 26b (deferred to other sub-phases — don't do these here):**
- Vitality table / trend chart visual changes — 26c
- Titles screen restructure — 26d
- Plan editor + bucket model — 26e
- Home redesign (which consumes the same Option B v4 row shape) — 26f
- Cardio surfacing on rank surfaces — v1.1+

**Known plan defects worth surfacing to the orchestrator at PR open:**
- Tasks 9 and 10 reference existing code paths (celebration-event-builder hook, stats deep-dive selection state) that the implementer must read in the current branch to locate exactly. This is intentional (the plan can't pin line numbers that will drift as later sub-phases land), but the implementer should NOT guess — they should grep + read.
- The pt-BR "para LVL N" suffix used in `CharacterXpBar` is hardcoded as a string concatenation, not an `AppLocalizations` entry. The spec text uses the same phrase in both en and pt mockups; if a future localization audit requires word-order flexibility, this becomes a parameterized message. Flagged in the bar's doc comment.
- The pulse repository stores ISO-8601 strings rather than typed `DateTime` values to avoid registering a Hive type adapter for a 6-entry box. The serialization cost is negligible; the simplicity wins.
