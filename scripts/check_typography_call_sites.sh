#!/usr/bin/env bash
# scripts/check_typography_call_sites.sh
#
# CI gate enforcing the "single sanctioned entry point" typography rule
# documented in `lib/core/theme/app_theme.dart > AppTextStyles` and pinned
# by `project_design_language_typography` (auto-memory).
#
# Fails the build (exit 1) when any file under `lib/features/` or
# `lib/shared/` contains a raw `TextStyle(fontFamily: 'Rajdhani', ...)`
# constructor. The only sanctioned place to define Rajdhani styles is
# `lib/core/theme/app_theme.dart` itself; every other call site MUST
# route through `AppTextStyles.numeric` / `.headline` / `.display` /
# `.titleDisplay` (or `.copyWith(...)` on one of those), so a new
# Rajdhani register can be promoted to a token in ONE place without
# leaving stale call-site literals scattered through the feature tree.
#
# Why: this is the fifth typography sweep on this branch family
# (Phase 27 L15 → L17 → 378a4c3 → L18.2 → L18.4). Each sweep landed
# correct call-site swaps; each subsequent commit silently re-introduced
# raw `fontFamily: 'Rajdhani'` literals in widgets that the sweep
# didn't reach. UX-critic Phase 27 L18.4 recommendation: convert the
# manual sweep into a CI gate. This script is that gate.
#
# Pattern checked: `TextStyle(...fontFamily: 'Rajdhani'...)`. The match
# is line-based — a raw `fontFamily: 'Rajdhani'` literal inside a
# `TextStyle(...)` constructor is the unambiguous violation. Comments
# that REFERENCE the pattern (e.g. dartdoc explaining the rule) are
# skipped via the `^\s*//` exclusion.
#
# Excluded paths:
#   * `lib/core/theme/app_theme.dart` — the sanctioned definition site.
#     This is where `AppTextStyles.numeric` / `.headline` / `.display`
#     INSTANTIATE the raw `TextStyle(fontFamily: 'Rajdhani', ...)`.
#
# Usage:
#   bash scripts/check_typography_call_sites.sh
#
# Wired into the `analyze` target in `Makefile` so `make ci` runs it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Grep for raw Rajdhani TextStyle literals under lib/features and lib/shared.
# `-rn` for recursive line-numbered output; `--include='*.dart'` scopes
# to Dart sources; `-E` for the extended regex.
#
# Pattern: matches a `fontFamily:` assignment to `'Rajdhani'` (single or
# double quote). We additionally exclude lines starting with `//` so
# dartdoc comments that name the literal in prose don't trip the gate.
#
# `|| true` swallows grep's exit-1-on-no-match — we want to evaluate
# the captured output ourselves rather than let grep's status fail
# the script when zero violations exist.
HITS=$(
  grep -rEn "fontFamily:\s*['\"]Rajdhani['\"]" lib/features lib/shared \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:\s*//" \
    || true
)

if [ -n "$HITS" ]; then
  echo "check_typography_call_sites: violations found"
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
  echo "$HITS"
  exit 1
fi

echo "check_typography_call_sites: clean (0 raw \`fontFamily: 'Rajdhani'\` literals under lib/features + lib/shared)."
