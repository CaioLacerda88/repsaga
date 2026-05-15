#!/usr/bin/env bash
# Fails if any file under `lib/` references the heroGold reward color
# outside the two files where it is legitimately defined / consumed.
#
# RepSaga's Arcane Ascent palette (§17.0c) runs a reward-scarcity framework:
# violet is the daily structural accent, gold is the variable-ratio reward
# signal. Scattering gold across features dilutes the dopamine payoff the
# palette is engineered to deliver, so gold rendering is quarantined to a
# single widget (`RewardAccent`).
#
# Violations (patterns matched):
#   1. Any reference to `AppColors.heroGold` outside the allowed files.
#   2. Any reference to `RewardAccent.color` (the static alias) outside the
#      allowed files. This closes the loophole where callers bypass the
#      widget-tree contract by reading the color constant directly.
#   3. Any raw gold hex literal (`0xFFFFB800`, `0xFFFFC107`, `0xFFFFD54F`)
#      outside the allowed files. These are the three "Material yellow
#      reads as gold" hexes that could sneak in during a palette refresh.
#
# Allowed files:
#   - lib/core/theme/app_theme.dart       (token definition)
#   - lib/shared/widgets/reward_accent.dart (the ONLY widget that emits it)
#
# Opt-out: add the marker `// ignore: reward_accent — <reason>` either
# (a) trailing on the same line as the flagged reference, or
# (b) on the line immediately preceding the flagged reference.
# Form (b) exists because dart format sometimes wraps the expression
# `RewardAccent\n    .color` across two lines when the trailing comment
# would push the line past 80 cols, making form (a) impossible to place
# deterministically. Opt-outs are for the narrow cases where the widget
# tree ancestor is structurally impossible, specifically:
#   - Custom painters / FlDotPainter callbacks (no BuildContext available)
#   - SvgPicture / IconTheme-less renderers taking an explicit `color:` param
#   - Test-only fixtures or in-progress migrations
# Every opt-out must carry a brief justification after the em-dash so the
# reason surfaces in code review and git blame.
#
# Usage: bash scripts/check_reward_accent.sh
# Exit: 0 on clean, 1 on any unapproved hit.

set -eu

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_DIR="$REPO_ROOT/lib"

if [[ ! -d "$SCAN_DIR" ]]; then
  echo "check_reward_accent: $SCAN_DIR does not exist; nothing to scan."
  exit 0
fi

# Allowed files — these are the single source of truth for the gold token.
# Stored as repo-relative paths so the grep output (which is absolute) can
# be filtered against them uniformly on Windows (bash) and POSIX alike.
ALLOWED_PATHS=(
  "lib/core/theme/app_theme.dart"
  "lib/shared/widgets/reward_accent.dart"

  # ─── Phase 26d widget exceptions ─────────────────────────────────────
  # Phase 26d title-screen widgets. They legitimately render
  # heroGold (the equipped title card uses a gold gradient as a flex
  # surface; cross-build cards in Titles "Próximos" use a gold accent
  # because cross-builds are rare achievements). Both are explicit
  # exceptions to the reward-scarcity rule. See docs/PROJECT.md §3
  # Phase 26 → "heroGold scarcity-rule exceptions".
  # Note: the path match is a substring check (see ALLOWED_PATHS loop
  # below) — test files like `equipped_title_card_test.dart` that share
  # the leaf name are covered by the same exemption.
  "lib/features/rpg/ui/widgets/equipped_title_card.dart"
  "lib/features/rpg/ui/widgets/cross_build_card.dart"
)

# heroGold symbol, the RewardAccent.color static alias, and the three
# gold-range raw hex literals. `RewardAccent\.color` is included so the
# scarcity contract can't be bypassed by calling the alias directly — every
# gold render must go through a widget-tree `RewardAccent` ancestor.
#
# Note on comment lines. We explicitly filter out lines whose first non-
# whitespace run is `//` or `///` so dartdoc prose that *mentions* the
# token (e.g. "see [AppColors.heroGold]") does not trip the gate. The
# quarantine applies to code references, not documentation.
PATTERN='heroGold|RewardAccent\.color|0xFFFFB800|0xFFFFC107|0xFFFFD54F'

# Pass 1: every raw match across `lib/`.
RAW_HITS="$(grep -rn --include='*.dart' -E "$PATTERN" -- "$SCAN_DIR" || true)"

# Build a map: file -> list of line numbers carrying an `ignore: reward_accent`
# marker. We use this to opt-out BOTH the same line and the line
# immediately following, because `dart format` will sometimes wrap a long
# `const x = RewardAccent.color;` statement onto two lines, pushing the
# `.color` onto the next line. Placing the marker on the preceding line
# (the one containing `RewardAccent`) is the only deterministic spot in
# that case.
declare -A IGNORE_LINES
if [[ -n "$RAW_HITS" ]]; then
  while IFS= read -r hit; do
    # grep -rn output: <path>:<lineno>:<content>
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    # Not used further in this loop; see the walk below.
    :
  done <<< "$RAW_HITS"
fi

# Pre-compute ignore-marker line numbers per file in a single grep per file.
for f in $(grep -rln --include='*.dart' 'ignore: reward_accent' -- "$SCAN_DIR" 2>/dev/null || true); do
  # Store as space-separated list of line numbers.
  nums="$(grep -n 'ignore: reward_accent' -- "$f" | cut -d: -f1 | tr '\n' ' ')"
  IGNORE_LINES["$f"]="$nums"
done

HITS=""
# EDIT_WITH_CARE: no regression test covers the whitelist loop below.
# Changes to ALLOWED_PATHS matching, ignore-marker handling, or the
# comment-line filter should be hand-verified against fixtures via
# a temporary scratch heroGold reference before merging.
if [[ -n "$RAW_HITS" ]]; then
  while IFS= read -r hit; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"

    # Skip allowed files.
    skip=false
    for allowed in "${ALLOWED_PATHS[@]}"; do
      if [[ "$file" == *"$allowed"* ]]; then
        skip=true
        break
      fi
    done
    [[ "$skip" == true ]] && continue

    # Skip pure comment lines (dartdoc `///` or line comment `//`).
    # `content` retains leading whitespace; strip it first.
    trimmed="${content#"${content%%[![:space:]]*}"}"
    if [[ "$trimmed" == //* ]]; then
      continue
    fi

    # Skip if the match line, or the line immediately before, carries an
    # `ignore: reward_accent` marker. Both forms (trailing on same line,
    # standalone on preceding line) are legal opt-outs.
    nums=" ${IGNORE_LINES[$file]:-} "
    prev=$((lineno - 1))
    if [[ "$nums" == *" $lineno "* ]] || [[ "$nums" == *" $prev "* ]]; then
      continue
    fi

    HITS+="$hit"$'\n'
  done <<< "$RAW_HITS"
fi

if [[ -n "$HITS" ]]; then
  echo "check_reward_accent: found unauthorized reward-accent references under lib/:" >&2
  echo "$HITS" >&2
  echo "" >&2
  echo "Wrap reward-bearing widgets in RewardAccent (lib/shared/widgets/reward_accent.dart)" >&2
  echo "instead of referencing AppColors.heroGold directly. If the literal is intentional," >&2
  echo "annotate the line with '// ignore: reward_accent — <reason>', either trailing on the" >&2
  echo "same line or as a standalone comment on the line immediately above." >&2
  exit 1
fi

echo "check_reward_accent: clean (0 unauthorized references under lib/)."
exit 0
