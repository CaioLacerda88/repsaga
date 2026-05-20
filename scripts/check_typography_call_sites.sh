#!/usr/bin/env bash
# scripts/check_typography_call_sites.sh
#
# CI gate enforcing the "single sanctioned entry point" typography rule
# documented in `lib/core/theme/app_theme.dart > AppTextStyles` and pinned
# by `project_design_language_typography` (auto-memory).
#
# Fails the build (exit 1) when any file under `lib/features/` or
# `lib/shared/` (and in some cases all of `lib/`) violates one of the
# five rules below. The only sanctioned place to define font-family
# literals is `lib/core/theme/app_theme.dart`; every other call site
# MUST route through `AppTextStyles.*` (or `.copyWith(...)` on one).
#
# Gates (Phase 28a):
#   1. Raw `TextStyle(... fontFamily: 'Rajdhani' ...)` outside app_theme.dart
#   2. Raw `TextStyle(... fontFamily: 'Inter' ...)` outside app_theme.dart
#   3. `FontWeight.w800` / `FontWeight.w900` anywhere in `lib/` — these
#      weights are NOT bundled in `pubspec.yaml > flutter.fonts:` (only
#      w400/w500/w600/w700). Flutter silently nearest-matches to w700
#      at runtime, so the override is visual noise that survives review.
#   4. `GoogleFonts.*` calls in `lib/features/` + `lib/shared/` — the
#      async API silently falls back to Inter on real-device release
#      builds (Phase 27 L14 root cause). Sanctioned use is the
#      `GoogleFonts.config.allowRuntimeFetching = false` lockdown in
#      `lib/main.dart`; everywhere else is forbidden.
#   5. `import 'package:google_fonts/google_fonts.dart'` anywhere outside
#      `lib/main.dart` and `lib/core/theme/app_theme.dart`. Importing
#      the package re-introduces the async-loading vector even if the
#      file doesn't currently call `GoogleFonts.*`.
#
# Why: this is the sixth typography sweep on this branch family
# (Phase 27 L15 → L17 → 378a4c3 → L18.2 → L18.4 → Phase 28a). Each sweep
# landed correct call-site swaps; each subsequent commit silently
# re-introduced raw literals in widgets that the sweep didn't reach.
# UX-critic Phase 27 L18.4 recommendation: convert the manual sweep
# into a CI gate. This script is that gate.
#
# Comment exclusion: lines where the violating literal lives inside a
# `//` comment are skipped via the same pattern the original Rajdhani
# gate uses — both standalone `^\s*//` dartdoc lines and trailing
# `code(); // ... 'pattern' ...` comments.
#
# Usage:
#   bash scripts/check_typography_call_sites.sh
#
# Wired into the `analyze` target in `Makefile` so `make ci` runs it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Track whether ANY gate fired. We don't short-circuit on the first
# failure so the developer sees every violation in a single run rather
# than playing whack-a-mole.
FAILED=0

# ─── Gate 1: raw `fontFamily: 'Rajdhani'` literals ───────────────────
HITS_RAJDHANI=$(
  grep -rEn "fontFamily:\s*['\"]Rajdhani['\"]" lib/features lib/shared \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:(\s*//|.*//[^'\"]*fontFamily:\s*['\"]Rajdhani['\"])" \
    || true
)

if [ -n "$HITS_RAJDHANI" ]; then
  FAILED=1
  echo "check_typography_call_sites: raw 'Rajdhani' literals"
  echo
  echo "Raw \`TextStyle(fontFamily: 'Rajdhani', ...)\` literals are forbidden"
  echo "outside \`lib/core/theme/app_theme.dart\`. Route through one of:"
  echo "  * AppTextStyles.numeric  (Rajdhani 700 tabular)"
  echo "  * AppTextStyles.headline (Rajdhani 600 24dp)"
  echo "  * AppTextStyles.display  (Rajdhani 700 32dp)"
  echo "  * AppTextStyles.titleDisplay (Rajdhani 600 16dp — routine names)"
  echo
  echo "Override per-site sizing/color/weight via \`.copyWith(...)\`."
  echo
  echo "Violations:"
  echo "$HITS_RAJDHANI"
  echo
fi

# ─── Gate 2: raw `fontFamily: 'Inter'` literals ──────────────────────
HITS_INTER=$(
  grep -rEn "fontFamily:\s*['\"]Inter['\"]" lib/features lib/shared \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:(\s*//|.*//[^'\"]*fontFamily:\s*['\"]Inter['\"])" \
    || true
)

if [ -n "$HITS_INTER" ]; then
  FAILED=1
  echo "check_typography_call_sites: raw 'Inter' literals"
  echo
  echo "Raw \`fontFamily: 'Inter'\` outside app_theme.dart bypasses the"
  echo "AppTextStyles token contract. Route through AppTextStyles.body /"
  echo ".title / .bodySmall / .label / .sectionHeader (or .copyWith)."
  echo
  echo "Violations:"
  echo "$HITS_INTER"
  echo
fi

# ─── Gate 3: forbidden FontWeight.w800 / w900 ────────────────────────
#
# Scope is all of `lib/` (including app_theme.dart) — these weights are
# never bundled, period. Comment exclusion identical to the family
# gates.
HITS_WEIGHTS=$(
  grep -rEn "FontWeight\.w(800|900)" lib \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:(\s*//|.*//[^'\"]*FontWeight\.w(800|900))" \
    || true
)

if [ -n "$HITS_WEIGHTS" ]; then
  FAILED=1
  echo "check_typography_call_sites: forbidden FontWeight.w800/w900"
  echo
  echo "FontWeight.w800/w900 are not in the bundled font assets — silent"
  echo "nearest-match to w700 at runtime. Use w700 or add weights to"
  echo "pubspec.yaml > flutter.fonts."
  echo
  echo "Violations:"
  echo "$HITS_WEIGHTS"
  echo
fi

# ─── Gate 4: `GoogleFonts.*` call sites ──────────────────────────────
#
# Scope is `lib/features/` + `lib/shared/`. The sanctioned use is the
# `GoogleFonts.config.allowRuntimeFetching = false` lockdown in
# `lib/main.dart`, which is outside this scope.
HITS_GF_CALLS=$(
  grep -rEn "GoogleFonts\.[a-zA-Z]" lib/features lib/shared \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:(\s*//|.*//[^'\"]*GoogleFonts\.[a-zA-Z])" \
    || true
)

if [ -n "$HITS_GF_CALLS" ]; then
  FAILED=1
  echo "check_typography_call_sites: GoogleFonts.* call sites"
  echo
  echo "GoogleFonts.* calls use the async API which silently falls back"
  echo "to Inter on real-device release builds (Phase 27 L14). Use"
  echo "direct fontFamily strings against bundled assets, or"
  echo "AppTextStyles.* getters."
  echo
  echo "Violations:"
  echo "$HITS_GF_CALLS"
  echo
fi

# ─── Gate 5: `package:google_fonts` import outside main.dart + app_theme ─
HITS_GF_IMPORT=$(
  grep -rEn "import.*package:google_fonts" lib \
    --include='*.dart' \
    | grep -vE "^lib/main\.dart:" \
    | grep -vE "^lib/core/theme/app_theme\.dart:" \
    | grep -vE "^[^:]+:[0-9]+:\s*//" \
    || true
)

if [ -n "$HITS_GF_IMPORT" ]; then
  FAILED=1
  echo "check_typography_call_sites: google_fonts import"
  echo
  echo "google_fonts import outside main.dart/app_theme.dart re-introduces"
  echo "the async-loading vector. Use bundled-asset fontFamily references"
  echo "via AppTextStyles."
  echo
  echo "Violations:"
  echo "$HITS_GF_IMPORT"
  echo
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "check_typography_call_sites: clean (0 raw 'Rajdhani'/'Inter' literals; 0 FontWeight.w800/w900; 0 GoogleFonts.* calls; 0 stray google_fonts imports)."
