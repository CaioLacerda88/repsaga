#!/usr/bin/env bash
# scripts/check_no_developer_log.sh
#
# CI gate enforcing the cluster `developer-log-invisible-logcat`: NO
# `dart:developer.log` calls anywhere in `lib/`. `developer.log` is
# INVISIBLE to `adb logcat` — it writes to the Dart VM developer
# stream (DevTools / `flutter run`) only.
#
# When this gate fires, the offending file logged something with
# developer.log but the message never reaches `adb logcat` — making a
# user-report of a physical-device bug impossible to triage. Use
# `debugPrint` instead: it routes to the platform print sink (stdout
# on Android → adb logcat).
#
# Scope: all of `lib/`. After PR 33b, the entire app uses
# `debugPrint('[Scope] msg')` instead of `dart:developer.log`. Pre-33b
# the gate scoped only `lib/features/workouts/` + `lib/features/rpg/`
# (the active-workout / celebration hot paths); 33b migrated the
# remaining 5 files in `lib/core/` + `lib/features/personal_records/`
# and widened the gate to lock in zero-regression for the entire app.
#
# Gates (order matches the script body below):
#   1. `import 'dart:developer'` (with optional `as <alias>`) inside
#      the scoped paths.
#   2. Qualified `developer.log(` calls (when the import is aliased).
#   3. Bare `log(` calls preceded by a non-identifier character (so
#      `RouteSettings.log(` / `_log.log(` / similar accessor calls do
#      NOT trigger). The contract is "use a stable prefixed
#      `debugPrint('[Scope] msg')` instead", so the gate fires the
#      moment a `log(` literal reappears.
#
# Comment exclusion: lines where the violating literal lives inside a
# `//` comment are skipped. Mirrors the pattern from
# `scripts/check_typography_call_sites.sh`.
#
# Usage:
#   bash scripts/check_no_developer_log.sh
#
# Wired into `.github/workflows/ci.yml` as a step in the `analyze` job.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCOPE=(lib)
FAILED=0

# ─── Gate 1: `import 'dart:developer'` (with or without `as` alias) ──
HITS_IMPORT=$(
  grep -rEn "^\s*import\s+'dart:developer'" "${SCOPE[@]}" \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:\s*//" \
    || true
)

if [ -n "$HITS_IMPORT" ]; then
  FAILED=1
  echo "check_no_developer_log: 'dart:developer' import in lib/"
  echo
  echo "Cluster: developer-log-invisible-logcat. \`dart:developer.log\`"
  echo "is INVISIBLE on \`adb logcat\` — it writes to the Dart VM developer"
  echo "stream only (DevTools / \`flutter run\`). On a physical Android"
  echo "device a user-report of 'save failed' / 'celebration silent' is"
  echo "impossible to triage."
  echo
  echo "Replace each call site with:"
  echo "    debugPrint('[ScopeTag] message')"
  echo
  echo "Import \`debugPrint\` from package:flutter/foundation.dart"
  echo "(or via \`package:flutter/material.dart\`)."
  echo
  echo "Violations:"
  echo "$HITS_IMPORT"
  echo
fi

# ─── Gate 2: qualified `developer.log(` calls (aliased import) ───────
HITS_QUALIFIED=$(
  grep -rEn "developer\.log\(" "${SCOPE[@]}" \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:(\s*//|.*//[^'\"]*developer\.log\()" \
    || true
)

if [ -n "$HITS_QUALIFIED" ]; then
  FAILED=1
  echo "check_no_developer_log: qualified developer.log(...) calls"
  echo
  echo "Cluster: developer-log-invisible-logcat. Replace with"
  echo "    debugPrint('[ScopeTag] message')"
  echo
  echo "Violations:"
  echo "$HITS_QUALIFIED"
  echo
fi

# ─── Gate 3: bare `log(` calls at statement start ────────────────────
#
# Matches `log(` preceded by start-of-line whitespace or a non-identifier
# character that is NOT a `.` (i.e. `foo.log(` is fine — it's a method
# call on a custom object, not the dart:developer free function).
# The regex `[^A-Za-z0-9_.]log\(` excludes `obj.log(` but catches:
#   * `log(...)`           (top-level call)
#   * `  log(...)`         (statement-leading whitespace)
#   * `(log(...)`          (used as an argument)
#   * `?log(...)`          (ternary)
#
# The leading anchor `(^|[^A-Za-z0-9_.])` ensures the start of the
# match isn't inside an identifier.
HITS_BARE=$(
  grep -rEn "(^|[^A-Za-z0-9_.])log\(" "${SCOPE[@]}" \
    --include='*.dart' \
    | grep -vE "^[^:]+:[0-9]+:(\s*//|.*//[^'\"]*log\()" \
    || true
)

if [ -n "$HITS_BARE" ]; then
  FAILED=1
  echo "check_no_developer_log: bare log(...) calls"
  echo
  echo "Cluster: developer-log-invisible-logcat. The bare \`log\` symbol"
  echo "resolves to \`dart:developer.log\` when that package is imported."
  echo "Replace with:"
  echo "    debugPrint('[ScopeTag] message')"
  echo
  echo "If a hit here is a method call on a custom object (e.g. a logger"
  echo "instance), rename the method — the gate must stay false-positive-"
  echo "free so the contract is enforceable."
  echo
  echo "Violations:"
  echo "$HITS_BARE"
  echo
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "check_no_developer_log: clean (0 'dart:developer' imports, 0 log(...) calls in lib/)."
