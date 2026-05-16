# Phase 26a — Color System Foundation · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 6 new `AppColors` tokens + 1 vitality-ramp helper + 4 l10n changes + 1 CI whitelist update. Surgical foundation that every other Phase 26 sub-phase (26b through 26f) consumes.

**Architecture:** This sub-phase touches only the design-token layer + l10n + a CI script. **No production UI surface changes in 26a** — existing widgets keep their current colors until each later sub-phase rewrites them. The tokens exist so 26b–f can consume them as they ship. The exception: nothing breaks if widgets aren't updated — the new tokens are additive.

**Tech Stack:** Flutter SDK ^3.11.4, Dart, Freezed, Material 3 theming, `flutter_test`, l10n via `flutter_localizations` + ARB files, Bash CI script (`scripts/check_reward_accent.sh`).

**Spec source:** `docs/PROJECT.md §3 Phase 26 → 26a acceptance criteria`. Visual reference: `docs/phase-26-mockups.html` (Tokens section + each screen's color usage).

**Branch:** `feature/26a-color-system-foundation`

---

## File map

**Modified:**
- `lib/core/theme/app_theme.dart` — add 6 new tokens to `AppColors` class
- `lib/features/rpg/ui/utils/vitality_state_styles.dart` — add `vitalityRampColorFor()` helper; update `bodyPartColor` map for chest + back
- `lib/l10n/app_en.arb` — fix `vitalityCopyDormant` copy + add 4 new keys
- `lib/l10n/app_pt.arb` — same set for pt-BR
- `scripts/check_reward_accent.sh` — whitelist `EquippedTitleCard` + `CrossBuildCard` widgets

**Created:**
- `test/unit/core/theme/app_colors_test.dart` — token assertions
- `test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart` — boundary tests for the new helper
- `test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart` — bodyPartColor map mapping tests

**Pre-flight reads (engineer should skim before starting):**
- `lib/core/theme/app_theme.dart` (existing `AppColors` shape + the reward-scarcity rule comment block)
- `lib/features/rpg/ui/utils/vitality_state_styles.dart` (existing `VitalityStateStyles` class + how `bodyPartColor` and `borderColorFor` are consumed today)
- `lib/features/rpg/models/body_part.dart` (the `BodyPart` enum — confirm members are: chest, back, legs, shoulders, arms, core, cardio)
- `scripts/check_reward_accent.sh` (existing whitelist mechanism + `--self-test` mode)
- `docs/PROJECT.md §3 Phase 26 → "Color system"` (the locked-decisions paragraph)

---

## Task 1: Add `bodyPartChest` + `bodyPartBack` + `bodyPartCardio` tokens

**Files:**
- Modify: `lib/core/theme/app_theme.dart` (add 3 static const declarations inside `class AppColors`)
- Create: `test/unit/core/theme/app_colors_test.dart` (new test file)

- [ ] **Step 1: Write the failing test**

Create `test/unit/core/theme/app_colors_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';

void main() {
  group('AppColors body-part tokens (Phase 26a)', () {
    test('bodyPartChest is Tailwind Pink 400 (#F472B6)', () {
      expect(AppColors.bodyPartChest, const Color(0xFFF472B6));
    });

    test('bodyPartBack is Tailwind Sky 400 (#38BDF8)', () {
      expect(AppColors.bodyPartBack, const Color(0xFF38BDF8));
    });

    test('bodyPartCardio is Tailwind Orange 400 (#FB923C)', () {
      expect(AppColors.bodyPartCardio, const Color(0xFFFB923C));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/core/theme/app_colors_test.dart
```

Expected: FAIL with `The getter 'bodyPartChest' isn't defined for the type 'AppColors'.` (and similar for back + cardio).

- [ ] **Step 3: Add the tokens to AppColors**

Open `lib/core/theme/app_theme.dart`. Find the existing token definitions inside `class AppColors` (after `hair`). Add three new tokens just before the `hair` line, with doc comments:

```dart
  /// Pink — chest body-part identity (Phase 26a). Anatomical fit (pec/heart)
  /// and distinct from every other body-part hue + the brand violet stack.
  /// Frees [hotViolet] to be the pure brand-primary (gradients, accents,
  /// character XP) without bleeding into the chest body-part identity.
  static const bodyPartChest = Color(0xFFF472B6);

  /// Sky-blue — back body-part identity (Phase 26a). Replaces the old
  /// [primaryViolet] mapping in `VitalityStateStyles.bodyPartColor[back]`
  /// to resolve the chest/back "two purples" hue collision.
  static const bodyPartBack = Color(0xFF38BDF8);

  /// Orange — cardio body-part identity (Phase 26a).
  ///
  /// **Infrastructure-only for v1.** Token shipped so v1.1+ can introduce
  /// cardio as an active stat without re-touching the palette. NOT exposed
  /// on any UI surface in Phase 26 (rank rail, Saga, Stats, Engajamento
  /// all hide cardio).
  static const bodyPartCardio = Color(0xFFFB923C);

```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/unit/core/theme/app_colors_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart test/unit/core/theme/app_colors_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): add bodyPartChest, bodyPartBack, bodyPartCardio tokens (26a)

Phase 26a foundation: introduces three new body-part identity tokens.
- bodyPartChest #F472B6 frees hotViolet from chest identity
- bodyPartBack #38BDF8 resolves chest/back hue collision
- bodyPartCardio #FB923C is infrastructure-only for v1, ready for v1.1
EOF
)"
```

---

## Task 2: Add `xpTrack` token

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `test/unit/core/theme/app_colors_test.dart`

- [ ] **Step 1: Write the failing test**

Append to the existing group in `test/unit/core/theme/app_colors_test.dart`:

```dart
    test('xpTrack is violet-tinted 10% alpha (#1AB36DFF)', () {
      // 0x1AB36DFF: 10% alpha (0x1A = 26 ≈ 10.2% of 255) on the
      // hotViolet base color (#B36DFF). Replaces the rgba(255,255,255,0.06)
      // neutral white-alpha track currently used across XP/progress bars.
      expect(AppColors.xpTrack, const Color(0x1AB36DFF));
    });
```

- [ ] **Step 2: Run to verify the new test fails**

```bash
flutter test test/unit/core/theme/app_colors_test.dart --plain-name "xpTrack"
```

Expected: FAIL with `The getter 'xpTrack' isn't defined`.

- [ ] **Step 3: Add the token**

In `lib/core/theme/app_theme.dart`, add immediately after the `bodyPartCardio` token:

```dart
  /// Violet-tinted XP/progress bar track (Phase 26a).
  ///
  /// 10% alpha on [hotViolet]. Replaces the generic
  /// `rgba(255,255,255,0.06)` neutral white-alpha track that progress
  /// bars used pre-Phase-26. Keeps progress infrastructure inside the
  /// Arcane Ascent palette rather than borrowing from a neutral design
  /// system.
  static const xpTrack = Color(0x1AB36DFF);

```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/unit/core/theme/app_colors_test.dart
```

Expected: 4 tests pass (3 from Task 1 + 1 from Task 2).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart test/unit/core/theme/app_colors_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): add xpTrack token (26a)

Violet-tinted 10%-alpha track color. Replaces the rgba(255,255,255,0.06)
neutral wash that all XP/progress bar infrastructure used pre-26.
EOF
)"
```

---

## Task 3: Add `vitalityHigh / vitalityMid / vitalityLow` semantic aliases

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `test/unit/core/theme/app_colors_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/unit/core/theme/app_colors_test.dart`:

```dart
  group('AppColors vitality ramp aliases (Phase 26a)', () {
    test('vitalityHigh aliases success', () {
      expect(AppColors.vitalityHigh, AppColors.success);
    });

    test('vitalityMid aliases warning', () {
      expect(AppColors.vitalityMid, AppColors.warning);
    });

    test('vitalityLow aliases error', () {
      expect(AppColors.vitalityLow, AppColors.error);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/unit/core/theme/app_colors_test.dart --plain-name "vitality ramp"
```

Expected: 3 failures, `getter 'vitalityHigh' isn't defined` (and Mid + Low).

- [ ] **Step 3: Add the aliases**

In `lib/core/theme/app_theme.dart`, immediately after the `xpTrack` token, add a doc-comment block + three aliases:

```dart
  // ─── Vitality ramp (Phase 26a) ──────────────────────────────────────
  //
  // Semantic aliases over success / warning / error. Same hex values;
  // named for self-documenting call sites where the rendered semantic
  // is "vitality HP-drain", not "success" or "error". Used by the new
  // [VitalityStateStyles.vitalityRampColorFor] helper.

  /// Vitality HP-drain — high band (66–100%). Alias of [success].
  static const vitalityHigh = success;

  /// Vitality HP-drain — mid band (34–65%). Alias of [warning].
  static const vitalityMid = warning;

  /// Vitality HP-drain — low band (0–33%). Alias of [error].
  static const vitalityLow = error;

```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/unit/core/theme/app_colors_test.dart
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart test/unit/core/theme/app_colors_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): add vitalityHigh/Mid/Low semantic aliases (26a)

Aliases over success/warning/error for self-documenting call sites
in the HP-drain vitality ramp. No new hex values; pure naming clarity.
EOF
)"
```

---

## Task 4: Add `VitalityStateStyles.vitalityRampColorFor()` helper

**Files:**
- Modify: `lib/features/rpg/ui/utils/vitality_state_styles.dart`
- Create: `test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';

void main() {
  group('VitalityStateStyles.vitalityRampColorFor', () {
    test('returns vitalityHigh at 100% (exact upper bound)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(1.0),
        AppColors.vitalityHigh,
      );
    });

    test('returns vitalityHigh at 66% (high-band lower edge, inclusive)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.66),
        AppColors.vitalityHigh,
      );
    });

    test('returns vitalityMid at 65% (just below high-band cutoff)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.65),
        AppColors.vitalityMid,
      );
    });

    test('returns vitalityMid at 34% (mid-band lower edge, inclusive)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.34),
        AppColors.vitalityMid,
      );
    });

    test('returns vitalityLow at 33% (just below mid-band cutoff)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.33),
        AppColors.vitalityLow,
      );
    });

    test('returns vitalityLow at 0% (lower bound)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.0),
        AppColors.vitalityLow,
      );
    });

    test('returns textDim for null (untested state)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(null),
        AppColors.textDim,
      );
    });

    test('returns textDim for negative values (defensive)', () {
      // Defensive guard: vitality % should never be negative, but if a
      // bug produces one, fall back to the untested band rather than
      // returning the lower-band color (which would mislead the user
      // into thinking they have low conditioning when really the data
      // is malformed).
      expect(
        VitalityStateStyles.vitalityRampColorFor(-0.1),
        AppColors.textDim,
      );
    });

    test('returns textDim for values above 1.0 (defensive)', () {
      // Same defensive guard for the upper bound.
      expect(
        VitalityStateStyles.vitalityRampColorFor(1.5),
        AppColors.textDim,
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart
```

Expected: FAIL with `The method 'vitalityRampColorFor' isn't defined for the type 'VitalityStateStyles'.`

- [ ] **Step 3: Add the helper**

Open `lib/features/rpg/ui/utils/vitality_state_styles.dart`. Inside the `VitalityStateStyles` class (or extension on it — match the existing pattern), add the static method:

```dart
  /// Resolves a vitality percentage to its band color on the HP-drain
  /// ramp (Phase 26a).
  ///
  /// Bands:
  ///   * 66%–100%  → [AppColors.vitalityHigh]
  ///   * 34%–65%   → [AppColors.vitalityMid]
  ///   * 0%–33%    → [AppColors.vitalityLow]
  ///   * null or out of [0,1] → [AppColors.textDim] (untested / malformed)
  ///
  /// Used on the Stats deep-dive vitality table percentage column
  /// (Phase 26c) and any other surface that needs to communicate
  /// conditioning state via color.
  static Color vitalityRampColorFor(double? percentage) {
    if (percentage == null || percentage < 0.0 || percentage > 1.0) {
      return AppColors.textDim;
    }
    if (percentage >= 0.66) return AppColors.vitalityHigh;
    if (percentage >= 0.34) return AppColors.vitalityMid;
    return AppColors.vitalityLow;
  }
```

If `app_theme.dart` isn't already imported in this file, add the import at the top:

```dart
import '../../../../core/theme/app_theme.dart';
```

(Adjust the relative path if the existing imports use a different style.)

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart
```

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/utils/vitality_state_styles.dart \
        test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): add VitalityStateStyles.vitalityRampColorFor helper (26a)

Resolves a vitality % to its HP-drain band color: high (>=66%),
mid (>=34%), low (<34%), textDim (null/oob). Consumed by 26c's
Stats deep-dive vitality table.
EOF
)"
```

---

## Task 5: Update `VitalityStateStyles.bodyPartColor` map for chest + back

**Files:**
- Modify: `lib/features/rpg/ui/utils/vitality_state_styles.dart` (the existing `bodyPartColor` map only — DO NOT touch other entries)
- Create: `test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart`

- [ ] **Step 1: Read the current map shape**

Open `lib/features/rpg/ui/utils/vitality_state_styles.dart` and find the existing `bodyPartColor` Map. Note its exact declaration style (whether it's a `static const` map, a getter, or inline). Confirm current values:
- `BodyPart.chest` → likely `AppColors.hotViolet`
- `BodyPart.back` → likely `AppColors.primaryViolet`
- (others — legs/shoulders/arms/core/cardio — leave untouched in this task)

This step has no test action; it's a read-and-confirm step before the test.

- [ ] **Step 2: Write the failing test**

Create `test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';

void main() {
  group('VitalityStateStyles.bodyPartColor — Phase 26a chest/back update', () {
    test('chest now maps to bodyPartChest (was hotViolet)', () {
      expect(
        VitalityStateStyles.bodyPartColor[BodyPart.chest],
        AppColors.bodyPartChest,
      );
    });

    test('back now maps to bodyPartBack (was primaryViolet)', () {
      expect(
        VitalityStateStyles.bodyPartColor[BodyPart.back],
        AppColors.bodyPartBack,
      );
    });

    // Regression: the other entries should still match their existing
    // tokens. If a later sub-phase rebinds legs/shoulders/arms/core,
    // these expectations get updated then — not now.
    test('legs still maps to success', () {
      expect(
        VitalityStateStyles.bodyPartColor[BodyPart.legs],
        AppColors.success,
      );
    });

    test('shoulders still maps to warning', () {
      expect(
        VitalityStateStyles.bodyPartColor[BodyPart.shoulders],
        AppColors.warning,
      );
    });

    test('arms still maps to error', () {
      expect(
        VitalityStateStyles.bodyPartColor[BodyPart.arms],
        AppColors.error,
      );
    });
  });
}
```

- [ ] **Step 3: Run to verify the first two tests fail**

```bash
flutter test test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart
```

Expected: 2 failures (chest + back), 3 passes (legs, shoulders, arms). The two failing tests confirm chest still binds to `hotViolet` and back to `primaryViolet`.

- [ ] **Step 4: Update the map**

In `lib/features/rpg/ui/utils/vitality_state_styles.dart`, find the `bodyPartColor` map entries for chest and back. Change ONLY those two lines:

```dart
BodyPart.chest: AppColors.bodyPartChest,  // was hotViolet (Phase 26a)
BodyPart.back: AppColors.bodyPartBack,    // was primaryViolet (Phase 26a)
```

Leave every other entry (legs, shoulders, arms, core, cardio) untouched.

- [ ] **Step 5: Run to verify all 5 tests pass**

```bash
flutter test test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 6: Run the full existing test suite to verify nothing else broke**

```bash
flutter test
```

Expected: all tests pass. If any vitality-table or rpg widget test golden-fails because of the color change, that's expected — but in 26a we shouldn't be running goldens that visually depend on chest/back colors yet. If a golden does fail, it indicates an unanticipated dependency; in that case STOP and re-plan: that golden was guarding the old color and needs an explicit update in its own task, not a silent regen.

- [ ] **Step 7: Commit**

```bash
git add lib/features/rpg/ui/utils/vitality_state_styles.dart \
        test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart
git commit -m "$(cat <<'EOF'
feat(rpg): rebind chest+back body-part colors to new tokens (26a)

chest: hotViolet → bodyPartChest (#F472B6 pink)
back:  primaryViolet → bodyPartBack (#38BDF8 sky)

Frees hotViolet from chest identity; resolves chest/back hue collision.
Other body parts (legs/shoulders/arms/core/cardio) unchanged in 26a.
EOF
)"
```

---

## Task 6: Fix `vitalityCopyDormant` l10n + drop stale row-level marginalia keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_pt.arb`
- Regenerate: `lib/l10n/app_localizations*.dart` (auto via `make gen`)

- [ ] **Step 1: Read both ARB files to confirm the current state**

```bash
grep -n "vitalityCopy" lib/l10n/app_en.arb lib/l10n/app_pt.arb
```

You should see entries like:
- `vitalityCopyDormant`: "Awaits your first stride." (en) / "Aguarda seu primeiro passo." (pt)
- `vitalityCopyFading`: "..." / "Condicionamento perdido — retorne ao caminho."
- `vitalityCopyActive`: "..." / "No caminho."
- `vitalityCopyRadiant`: "..." / "Caminho dominado."
- `vitalityCopyUntested`: "..." / "..."

**The bug:** `vitalityCopyDormant`'s current text ("Awaits your first stride." / "Aguarda seu primeiro passo.") matches the **Untested** semantic, not the Dormant one. We're rewriting it to the correct Dormant meaning.

**Stale keys to drop** in this task (row-level marginalia copy retired per Phase 26 locked decisions):
- `vitalityCopyFading` — UI no longer shows row marginalia for fading state
- `vitalityCopyActive` — UI no longer shows row marginalia for active state
- `vitalityCopyRadiant` — UI no longer shows row marginalia for radiant state

Keep `vitalityCopyUntested` — it's the only state where dim gray alone is genuinely ambiguous, so the copy still renders.

- [ ] **Step 2: Update `lib/l10n/app_en.arb`**

Replace the `vitalityCopyDormant` entry:

```json
"vitalityCopyDormant": "Dormant. Train this group to reawaken its path.",
"@vitalityCopyDormant": { "description": "Marginalia copy for a body-part rune in the Dormant state (peak > 0 but EWMA ~ 0 — trained at least once, then fully fallen off the path). Renders as 0–33% on the stats deep-dive screen. Distinct from vitalityCopyUntested which is the never-trained branch." },
```

Remove these three entries entirely (and their `@` description twin entries):
- `vitalityCopyFading` + `@vitalityCopyFading`
- `vitalityCopyActive` + `@vitalityCopyActive`
- `vitalityCopyRadiant` + `@vitalityCopyRadiant`

- [ ] **Step 3: Update `lib/l10n/app_pt.arb`**

Replace the `vitalityCopyDormant` entry:

```json
"vitalityCopyDormant": "Dormente. Treine este grupo para reacender o caminho.",
```

Remove these three entries:
- `vitalityCopyFading`
- `vitalityCopyActive`
- `vitalityCopyRadiant`

- [ ] **Step 4: Regenerate the l10n classes**

```bash
make gen
```

Expected: `lib/l10n/app_localizations*.dart` rebuilds without errors. The four removed `String get` accessors will disappear from the generated classes.

- [ ] **Step 5: Find + remove call sites for the dropped keys**

```bash
grep -rn "vitalityCopyFading\|vitalityCopyActive\|vitalityCopyRadiant" lib/
```

Any remaining call sites will be in `lib/features/rpg/ui/utils/vitality_state_styles.dart` (or wherever `localizedCopy` is built per `VitalityState`). For each call site found, the surrounding code that selected per-state copy needs to be simplified: only the dormant + untested branches return non-empty copy; active/fading/radiant return empty / null. Sketch:

```dart
String? localizedCopy(VitalityState state, AppLocalizations l10n) {
  switch (state) {
    case VitalityState.untested:
      return l10n.vitalityCopyUntested;
    case VitalityState.dormant:
      return l10n.vitalityCopyDormant;
    case VitalityState.fading:
    case VitalityState.active:
    case VitalityState.radiant:
      return null;  // copy retired in Phase 26
  }
}
```

Match the existing function shape (it might return `String` non-null with empty string today; preserve that contract, just return empty for the retired states).

- [ ] **Step 6: Run flutter analyze + tests**

```bash
flutter analyze
flutter test
```

Expected: zero compile errors (the removed keys aren't referenced anywhere after the audit), all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/ lib/features/rpg/ui/utils/vitality_state_styles.dart
git commit -m "$(cat <<'EOF'
fix(l10n): rewrite vitalityCopyDormant + retire active/fading/radiant copy (26a)

vitalityCopyDormant previously said "Awaits your first stride." which
describes the Untested state, not Dormant. Now reads "Dormant. Train
this group to reawaken its path." / pt-BR equivalent.

The active, fading, and radiant marginalia copy strings are retired —
Phase 26 vitality table renders state via color only. Only Untested
keeps its copy (dim gray alone is ambiguous).
EOF
)"
```

---

## Task 7: Add new l10n keys (vitality state-band labels + withinRankXpSuffix)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_pt.arb`
- Regenerate: `lib/l10n/app_localizations*.dart`

- [ ] **Step 1: Add keys to `lib/l10n/app_en.arb`**

Add these four new entries (keep alphabetical / topical ordering consistent with the file):

```json
"vitalityStateBandActive": "Active",
"@vitalityStateBandActive": { "description": "Label for the high band (66–100%) on the vitality HP-drain ramp. Shown inside the vitality explainer bottom sheet (Phase 26c)." },

"vitalityStateBandWaning": "Waning",
"@vitalityStateBandWaning": { "description": "Label for the mid band (34–65%) on the vitality HP-drain ramp. Shown inside the vitality explainer bottom sheet." },

"vitalityStateBandDormant": "Dormant",
"@vitalityStateBandDormant": { "description": "Label for the low band (0–33%) on the vitality HP-drain ramp. Shown inside the vitality explainer bottom sheet." },

"withinRankXpSuffix": "to next rank",
"@withinRankXpSuffix": { "description": "Trailing copy on per-stat XP labels across Saga, Stats deep-dive, Home expanded card, Titles próximos rows. Rendered as 'N XP · M {withinRankXpSuffix}' (e.g., '1,420 XP · 580 to next rank')." },
```

- [ ] **Step 2: Add keys to `lib/l10n/app_pt.arb`**

```json
"vitalityStateBandActive": "Ativo",
"vitalityStateBandWaning": "Esmorecendo",
"vitalityStateBandDormant": "Dormente",
"withinRankXpSuffix": "para o próximo rank",
```

(pt-BR ARB doesn't typically carry `@` descriptions — match the file's existing convention.)

- [ ] **Step 3: Regenerate**

```bash
make gen
```

Expected: `lib/l10n/app_localizations*.dart` gains four new `String get` accessors.

- [ ] **Step 4: Smoke test that the keys exist**

```bash
flutter test --plain-name "AppLocalizations" || true
```

(There may be no existing test covering these keys directly — that's fine. The regeneration is the verification.)

Optional: write a quick localization test asserting the accessors return non-empty strings:

Create `test/unit/l10n/phase_26a_keys_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Future<AppLocalizations> _load(Locale locale) async {
  return AppLocalizations.delegate.load(locale);
}

void main() {
  group('Phase 26a — new l10n keys', () {
    test('en: all four new keys return non-empty strings', () async {
      final l10n = await _load(const Locale('en'));
      expect(l10n.vitalityStateBandActive, isNotEmpty);
      expect(l10n.vitalityStateBandWaning, isNotEmpty);
      expect(l10n.vitalityStateBandDormant, isNotEmpty);
      expect(l10n.withinRankXpSuffix, isNotEmpty);
    });

    test('pt: all four new keys return non-empty strings', () async {
      final l10n = await _load(const Locale('pt'));
      expect(l10n.vitalityStateBandActive, 'Ativo');
      expect(l10n.vitalityStateBandWaning, 'Esmorecendo');
      expect(l10n.vitalityStateBandDormant, 'Dormente');
      expect(l10n.withinRankXpSuffix, 'para o próximo rank');
    });

    test('en: vitalityCopyDormant has been rewritten (no longer Untested copy)', () async {
      final l10n = await _load(const Locale('en'));
      expect(l10n.vitalityCopyDormant, isNot(contains('first stride')));
      expect(l10n.vitalityCopyDormant.toLowerCase(), contains('dormant'));
    });

    test('pt: vitalityCopyDormant has been rewritten', () async {
      final l10n = await _load(const Locale('pt'));
      expect(l10n.vitalityCopyDormant, isNot(contains('primeiro passo')));
      expect(l10n.vitalityCopyDormant.toLowerCase(), contains('dormente'));
    });
  });
}
```

Run:

```bash
flutter test test/unit/l10n/phase_26a_keys_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/ test/unit/l10n/phase_26a_keys_test.dart
git commit -m "$(cat <<'EOF'
feat(l10n): add vitality state-band labels + withinRankXpSuffix (26a)

New keys consumed by 26b (Saga / Home / Titles XP labels) and
26c (vitality explainer bottom sheet):

  vitalityStateBandActive  = Active / Ativo
  vitalityStateBandWaning  = Waning / Esmorecendo
  vitalityStateBandDormant = Dormant / Dormente
  withinRankXpSuffix       = to next rank / para o próximo rank
EOF
)"
```

---

## Task 8: Whitelist `EquippedTitleCard` + `CrossBuildCard` in `check_reward_accent.sh`

**Files:**
- Modify: `scripts/check_reward_accent.sh`

- [ ] **Step 1: Read the existing script and self-test mode**

```bash
cat scripts/check_reward_accent.sh | head -80
./scripts/check_reward_accent.sh --self-test
```

Expected: the script's existing fixture-based self-test passes. Confirm the script uses an allowlist mechanism (likely a `WHITELIST=(...)` or pattern grep) for files/classes permitted to use `heroGold` outside `RewardAccent`.

- [ ] **Step 2: Add the two new allowlist entries**

In `scripts/check_reward_accent.sh`, find the existing whitelist (likely an array or `grep -v` chain). Add two entries:

- File-path pattern: `lib/features/rpg/ui/widgets/equipped_title_card.dart`
- File-path pattern: `lib/features/rpg/ui/widgets/cross_build_card.dart`

These files don't exist yet — they're created in Phase 26d. Adding the whitelist entries now means the script won't false-positive when 26d ships, AND it won't false-negative now (the files aren't present, so the whitelist entry is a no-op).

Add a comment block near the whitelist explaining:

```bash
# Phase 26d will introduce these widgets. They legitimately render
# heroGold (the equipped title card uses a gold gradient as a flex
# surface; cross-build cards in Titles "Próximos" use a gold accent
# because cross-builds are rare achievements). Both are explicit
# exceptions to the reward-scarcity rule. See docs/PROJECT.md §3
# Phase 26 → "heroGold scarcity-rule exceptions".
```

- [ ] **Step 3: Add self-test fixtures**

The script's `--self-test` mode reads fixture files. Add two new fixtures inside the existing self-test fixture folder (likely `scripts/check_reward_accent_fixtures/`):

- `phase26_allowed_equipped.dart`: a fake file at the allowlisted path simulating heroGold use → asserts PASS
- `phase26_allowed_crossbuild.dart`: same for cross-build → asserts PASS
- `phase26_disallowed_other_titles_widget.dart`: a fake file in `lib/features/rpg/ui/widgets/` (NOT one of the two allowed names) using heroGold → asserts FAIL

Match the existing fixture-file conventions exactly (path naming, file shape, assertion comments).

- [ ] **Step 4: Run the self-test**

```bash
./scripts/check_reward_accent.sh --self-test
```

Expected: all fixtures (existing + new) report PASS / FAIL as labeled, and the self-test runner exits 0.

- [ ] **Step 5: Run the live check against the real codebase**

```bash
./scripts/check_reward_accent.sh
```

Expected: exits 0 (no current uses of heroGold outside `RewardAccent` and the new allowlist entries — the allowlisted files don't exist yet, but the entries are no-ops).

- [ ] **Step 6: Commit**

```bash
git add scripts/check_reward_accent.sh scripts/check_reward_accent_fixtures/
git commit -m "$(cat <<'EOF'
ci(reward-accent): whitelist EquippedTitleCard + CrossBuildCard for 26d

Phase 26d's titles screen redesign introduces two widgets that
legitimately use heroGold outside RewardAccent:
- equipped_title_card.dart (identity flex)
- cross_build_card.dart (rare-achievement Próximos card)

Both are explicit exceptions to the reward-scarcity rule. Whitelist
entries added now (no-op until 26d creates the files) + matching
self-test fixtures.
EOF
)"
```

---

## Task 9: Verification + open PR

**Files:** none (verification + PR)

- [ ] **Step 1: Run full CI locally**

```bash
export PATH="/c/flutter/bin:$PATH"
make ci
```

This runs format + gen + analyze + test + android-debug-build per `Makefile`. Expected: all green, ~3-5 min runtime.

If any step fails, STOP and fix the underlying issue. Do not bypass.

- [ ] **Step 2: Read the spec acceptance criteria one more time**

Open `docs/PROJECT.md §3 Phase 26 → 26a acceptance criteria`. Confirm every bullet is satisfied:

- [ ] `flutter analyze` clean ✓ (verified in Step 1)
- [ ] xpTrack token exists ✓ (Task 2)
- [ ] Chest is pink #F472B6 in `bodyPartColor[chest]` ✓ (Task 5)
- [ ] Back is sky #38BDF8 in `bodyPartColor[back]` ✓ (Task 5)
- [ ] Cardio token defined but unused on UI ✓ (Task 1)
- [ ] `vitalityRampColorFor(double pct)` helper with high/mid/low/textDim semantics ✓ (Task 4)
- [ ] `check_reward_accent.sh` whitelist for EquippedTitleCard + CrossBuildCard ✓ (Task 8)
- [ ] L10n: vitalityCopyDormant rewritten ✓ (Task 6)
- [ ] L10n: new keys vitalityStateBandActive/Waning/Dormant + withinRankXpSuffix ✓ (Task 7)
- [ ] Stale row-marginalia keys retired (vitalityCopyFading/Active/Radiant) ✓ (Task 6)
- [ ] Unit tests for `vitalityRampColorFor` boundary cases ✓ (Task 4)

If any bullet is unsatisfied, STOP and add the missing work as a new task before proceeding.

- [ ] **Step 3: Push the branch**

```bash
git push -u origin feature/26a-color-system-foundation
```

- [ ] **Step 4: Open the PR**

```bash
gh pr create --title "feat(rpg): Phase 26a — Color System Foundation" --body "$(cat <<'EOF'
## Summary
- Adds 4 new `AppColors` tokens (`bodyPartChest`, `bodyPartBack`, `bodyPartCardio`, `xpTrack`) + 3 semantic aliases for the HP-drain ramp.
- Adds `VitalityStateStyles.vitalityRampColorFor(double?)` helper.
- Rebinds `bodyPartColor[chest]` → `bodyPartChest`, `bodyPartColor[back]` → `bodyPartBack`. Resolves chest/back hue collision.
- Fixes `vitalityCopyDormant` l10n (was Untested copy); retires `vitalityCopyFading/Active/Radiant` (row marginalia no longer rendered post-26c).
- Adds 4 new l10n keys for 26b/c consumption.
- Whitelists `EquippedTitleCard` + `CrossBuildCard` in `check_reward_accent.sh` for 26d.

**QA pass pending — final coverage + E2E run after code review.**

## Test plan
- [x] Unit: `AppColors` token values pinned (`test/unit/core/theme/app_colors_test.dart`)
- [x] Unit: `vitalityRampColorFor` boundary cases incl. defensive bounds (`test/unit/features/rpg/ui/utils/vitality_ramp_color_test.dart`)
- [x] Unit: `bodyPartColor` chest/back rebinding + regression on other body parts (`test/unit/features/rpg/ui/utils/vitality_body_part_color_test.dart`)
- [x] Unit: l10n new keys + dormant copy rewrite (`test/unit/l10n/phase_26a_keys_test.dart`)
- [x] `check_reward_accent.sh --self-test` passes with new fixtures
- [x] `make ci` clean

## References
- Spec: `docs/PROJECT.md §3 Phase 26 → 26a acceptance criteria`
- Visual: `docs/phase-26-mockups.html` (Tokens section)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Move on per the pipeline**

After the PR opens, the CLAUDE.md pipeline takes over:
- Reviewer agent runs (read-only).
- After reviewer signs off, QA gate (final coverage hole closing + E2E selector check).
- Merge after QA + CI green.
- After merge, condense 26a in PROJECT.md §4 (Completed Phases) and remove the 26a section from WIP.md.
- Re-invoke `superpowers:writing-plans` to draft 26b's plan against the up-to-date codebase.

---

## Self-review notes (pre-handoff)

**Spec coverage:** every acceptance bullet from `docs/PROJECT.md §3 Phase 26 → 26a` is covered by tasks 1–8, verified in task 9.

**Placeholder scan:** no `TODO` / `TBD` / `implement later` / "add error handling" generic instructions. Every code step has actual code.

**Type consistency:** `vitalityRampColorFor(double?)` signature consistent across the test file and the helper definition. `bodyPartColor[BodyPart.X]` access pattern consistent with the existing map shape. `AppColors.X` token names consistent everywhere they appear.

**Out of scope for 26a (deferred to other sub-phases — don't do these here):**
- Updating UI widgets to read from the new tokens (BodyPartRankRow, VitalityTable, VitalityRadar, etc.) — that's 26b/c/d/e/f.
- Updating XP track color in existing widgets — also deferred; each consuming widget gets updated when its sub-phase rewrites it.
- Anything visual on Saga, Stats, Titles, Plan editor, Home — all in their respective sub-phases.

If during 26a you discover a UI widget breaks because the bodyPartColor map change cascades to it, that's a real signal: stop and re-plan whether the cascade is intended (and add a task to update that widget) or whether it should be deferred to the relevant sub-phase.
