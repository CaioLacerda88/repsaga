#!/usr/bin/env bash
# Coverage floor gate: parses coverage/lcov.info produced by
# `flutter test --coverage` and fails if overall line coverage
# drops below COVERAGE_FLOOR.
#
# This gate is self-contained — no external service or secret is required.
# It runs in the `test` CI job immediately after `flutter test --coverage`,
# using the lcov.info file that job already generates.
#
# How to raise the floor:
#   1. Run `flutter test --coverage` locally.
#   2. Run this script; note the reported %.
#   3. Bump COVERAGE_FLOOR below to the new value rounded DOWN (never set it
#      higher than the current %; that would immediately red the pipeline).
#   4. Commit alongside the tests that raised the coverage.
#
# History:
#   2026-06-22  Initial floor set to 77 (measured: 78.4% on 16555/21104 lines,
#               after Phase 38b; rounded down for a ~1% safety margin so minor
#               test-count fluctuations in concurrent branches don't trip it).
#
# Usage: bash scripts/check_coverage_floor.sh [path/to/lcov.info]
# Exit:  0 if coverage >= floor, 1 if below floor, 2 if lcov.info not found.

set -eu

COVERAGE_FLOOR=77

LCOV_FILE="${1:-coverage/lcov.info}"

# Resolve relative path from the repo root so the script is runnable from
# any directory (CI runs from repo root; callers may differ).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$LCOV_FILE" != /* ]]; then
  LCOV_FILE="$REPO_ROOT/$LCOV_FILE"
fi

if [[ ! -f "$LCOV_FILE" ]]; then
  echo "check_coverage_floor: lcov.info not found at $LCOV_FILE" >&2
  echo "Run 'flutter test --coverage' first to generate it." >&2
  exit 2
fi

# Sum LH (lines hit) and LF (lines found) across all source files.
# `printf "%d %d"` with `+0` coercion guarantees two space-separated integers
# even when a field never appears (uninitialized awk vars → 0), so `read`
# can never column-shift on a degenerate lcov.info (fail-closed via the
# LINES_FOUND == 0 check below).
read -r LINES_HIT LINES_FOUND < <(
  awk -F: '
    /^LH:/ { lh += $2 }
    /^LF:/ { lf += $2 }
    END    { printf "%d %d\n", lh+0, lf+0 }
  ' "$LCOV_FILE"
)

if [[ "$LINES_FOUND" -eq 0 ]]; then
  echo "check_coverage_floor: lcov.info has no LF records — coverage data is empty." >&2
  exit 2
fi

# Compute integer percentage (truncated, not rounded — conservative).
COVERAGE_PCT=$(( (LINES_HIT * 100) / LINES_FOUND ))

echo "check_coverage_floor: $LINES_HIT / $LINES_FOUND lines = ${COVERAGE_PCT}% (floor: ${COVERAGE_FLOOR}%)"

if [[ "$COVERAGE_PCT" -lt "$COVERAGE_FLOOR" ]]; then
  echo "" >&2
  echo "check_coverage_floor: FAIL — coverage ${COVERAGE_PCT}% is below the ${COVERAGE_FLOOR}% floor." >&2
  echo "" >&2
  echo "To fix: write tests for the uncovered paths, then re-run" >&2
  echo "'flutter test --coverage' and verify the % is at or above the floor." >&2
  echo "To raise the floor: bump COVERAGE_FLOOR in scripts/check_coverage_floor.sh" >&2
  echo "in the same commit that adds the tests." >&2
  exit 1
fi

echo "check_coverage_floor: OK."
exit 0
