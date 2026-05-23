#!/usr/bin/env bash
# Fails if any file under `lib/features/` contains an out-of-palette color.
#
# The Arcane Ascent direction (§17.0c) locks all color to the `AppColors`
# tokens in `lib/core/theme/app_theme.dart`:
#   abyss, surface, surface2, primaryViolet, hotViolet, heroGold,
#   textCream, textDim, success, warning, error, hair
#
# Any of the following are considered palette violations:
#
#   1. Raw `Color(0x…)` literals  — new color leaking in without palette review.
#   2. `Colors.black` / `Colors.black12…` / `Colors.black87`, i.e. any
#      `Colors.black*` — `AppColors.abyss` (or `abyss.withValues(alpha:)`)
#      must be used instead. Pure `#000000` is not a palette token.
#   3. `Colors.white` / `Colors.white10…` / `Colors.white70`, i.e. any
#      `Colors.white*` — `AppColors.textCream` (or a `textCream.withValues`
#      overlay) must be used instead.
#
# Explicitly allowed:
#   - `Colors.transparent` — structural, not a color choice.
#
# Opt-out: add `// ignore: hardcoded_color — <reason>` either
# (a) trailing on the same line as the flagged literal, or
# (b) on the line immediately preceding the flagged literal.
# Form (b) exists because `dart format` will sometimes wrap a
# constructor across multiple lines when a trailing comment would push
# the line past 80 cols, leaving the literal and the marker on
# different lines. Placing the marker on the preceding line is the only
# deterministic spot in that case. This mirrors `check_reward_accent.sh`'s
# grammar so the two style gates share the same opt-out form.
#
# When the literal is structurally awkward to annotate (e.g. nested in a
# multi-line `ColoredBox(color: ...withValues(alpha: ...))` constructor
# that the formatter splits), extract the widget into a tiny private
# `_buildXxx()` helper and put the ignore marker on the helper — keeps
# the call site readable while the gate stays satisfied. See
# `b3_pr_cut.dart::_buildFlash` for the canonical pattern.
#
# Every opt-out must carry a brief justification after the em-dash so the
# reason surfaces in code review and git blame.
#
# Usage: bash scripts/check_hardcoded_colors.sh
# Exit: 0 on clean, 1 on any unapproved hit.

set -eu

# Resolve repo root regardless of where the script is invoked from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_DIR="$REPO_ROOT/lib/features"

if [[ ! -d "$SCAN_DIR" ]]; then
  echo "check_hardcoded_colors: $SCAN_DIR does not exist; nothing to scan."
  exit 0
fi

# Combined pattern:
#   - Color(0x…)          raw hex literal
#   - Colors.black(\d+)?  Colors.black, Colors.black12, Colors.black87, …
#   - Colors.white(\d+)?  Colors.white, Colors.white10, Colors.white70, …
# `Colors.transparent` is intentionally excluded (no \b boundary on black/white
# tail means `Colors.blackNNN` matches but `Colors.transparent` does not match
# this pattern at all — the word after `Colors.` is neither `black` nor `white`).
PATTERN='Color\(0x[0-9A-Fa-f]+|Colors\.black[0-9]*|Colors\.white[0-9]*'

# Pass 1: every raw match across `lib/features/`.
# The `--` guards against any path that happens to start with `-`.
RAW_HITS="$(grep -rn --include='*.dart' -E "$PATTERN" -- "$SCAN_DIR" || true)"

# Pre-compute ignore-marker line numbers per file in a single grep per file.
# Stored as a space-separated list of line numbers; later we test both the
# offending line and the immediately preceding line (to cover the dart
# format wrap case described in the header).
declare -A IGNORE_LINES
for f in $(grep -rln --include='*.dart' 'ignore: hardcoded_color' -- "$SCAN_DIR" 2>/dev/null || true); do
  nums="$(grep -n 'ignore: hardcoded_color' -- "$f" | cut -d: -f1 | tr '\n' ' ')"
  IGNORE_LINES["$f"]="$nums"
done

HITS=""
# EDIT_WITH_CARE: matches `check_reward_accent.sh`'s same/preceding-line
# opt-out behavior. Diverging here would force call sites to remember two
# different ignore grammars depending on which gate fired.
if [[ -n "$RAW_HITS" ]]; then
  while IFS= read -r hit; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"

    # Skip if the match line, or the line immediately before, carries an
    # `ignore: hardcoded_color` marker. Both forms (trailing on same line,
    # standalone on preceding line) are legal opt-outs — see header.
    nums=" ${IGNORE_LINES[$file]:-} "
    prev=$((lineno - 1))
    if [[ "$nums" == *" $lineno "* ]] || [[ "$nums" == *" $prev "* ]]; then
      continue
    fi

    HITS+="$hit"$'\n'
  done <<< "$RAW_HITS"
fi

if [[ -n "$HITS" ]]; then
  echo "check_hardcoded_colors: found out-of-palette color literals under lib/features/:" >&2
  echo "$HITS" >&2
  echo "" >&2
  echo "Migrate to an AppColors palette token (use .withValues(alpha: …) for" >&2
  echo "translucent overlays), or annotate the line with" >&2
  echo "'// ignore: hardcoded_color — <reason>' if the literal is intentional." >&2
  echo "(The marker may sit trailing on the offending line OR on the line" >&2
  echo "immediately preceding it — same grammar as check_reward_accent.sh." >&2
  echo "When dart format wrapping awkwardly splits the literal away from" >&2
  echo "the marker, extract the literal into a tiny private _buildXxx()" >&2
  echo "helper and put the ignore on the helper. See header for details.)" >&2
  exit 1
fi

echo "check_hardcoded_colors: clean (0 hits under lib/features/)."
exit 0
