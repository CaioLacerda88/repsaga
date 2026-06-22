#!/usr/bin/env bash
# Layering gate: fails if any Dart file under `lib/` OUTSIDE a `data/`
# directory contains a Supabase table or RPC call in string-literal form.
#
# Rationale: direct `.from('table')` or `.rpc('fn')` calls belong exclusively
# in repository classes (lib/**/data/). Leaking them into providers, widgets,
# view-models, or domain models bypasses the repository abstraction, makes
# offline/mocking impossible, and fragments the data-access audit trail.
#
# Pattern matched: `\.(from|rpc)\('`
#   This matches `.from('workouts')`, `.rpc('save_workout')` etc. — the
#   string-literal form where the argument is a quoted table/function name.
#
#   It deliberately does NOT match:
#     - `List.from(x)`  — `from(x)` receives a variable/expression, no quote
#     - `Set.from(x)`   — same
#     - `Map.from(x)`   — same
#     - `.from(l10n)`   — same (ShareLocalizations.from, WeeklyEngagement.from…)
#     - Comments containing `.from('…')` — grep -v'#' would be fragile;
#       instead we let comment hits through and handle them in ALLOW_LIST below.
#       In practice, the only comment hits are doc-string references to
#       "raw .from('workouts') reads" in workout.dart / workout.freezed.dart
#       which are in the data/ subtree anyway.
#
# Allow-list: full relative paths from repo root. One per line. Each entry
# MUST carry a documented justification so the reason surfaces in code review
# and git blame. To add a new exception: append the path here with a comment.
#
# Usage: bash scripts/check_no_supabase_outside_data.sh
# Exit:  0 on clean, 1 on any unapproved violation.

set -eu

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_ROOT/lib"

if [[ ! -d "$LIB_DIR" ]]; then
  echo "check_no_supabase_outside_data: $LIB_DIR does not exist; nothing to scan."
  exit 0
fi

# ---- Allow-list -------------------------------------------------------
# Relative paths from REPO_ROOT. Add with // ALLOW: <reason> inline above.

# ALLOW: infra connectivity probe — NOT feature data access. This file fires
# a single `select('id').limit(1)` against `public.users` purely to check
# whether the Supabase endpoint is reachable. It intentionally bypasses the
# repository layer because (a) there is no "users" feature repository (the
# auth tables are managed by Supabase Auth, not the app), and (b) the probe
# must remain available in fully-offline mode before any user-data providers
# have initialized. Routing through a repository would create a circular init
# dependency (HealthCheck → UserRepository → Supabase → HealthCheck).
ALLOW_LIST=(
  "lib/core/offline/health_check_provider.dart"
)

# ---- Scan ---------------------------------------------------------------
# Find all .dart files under lib/ that are NOT inside a data/ directory.
# We use find + grep rather than a single ripgrep invocation so we can
# filter by path before doing the pattern match.
#
# Comment-filtering: we exclude lines whose code portion (after the grep -n
# `lineno:` prefix) consists only of a Dart comment (`//` or `*` block lines).
# This avoids false positives from doc-strings referencing the pattern, e.g.
# `/// raw .from('workouts') reads`. The `grep -n` output format is
# `<lineno>:<content>`, so we must skip the prefix before matching `^\s*(//|\*)`.
# We do that by stripping the `<digits>:` prefix with sed before testing.

COMMENT_PATTERN='^\s*(//|\*)'

HITS=""

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Convert to relative path for allow-list comparison.
  rel="${file#"$REPO_ROOT/"}"

  # Check allow-list.
  allowed=false
  for entry in "${ALLOW_LIST[@]}"; do
    if [[ "$rel" == "$entry" ]]; then
      allowed=true
      break
    fi
  done

  if $allowed; then
    continue
  fi

  # Grep for the pattern, then exclude lines that are Dart comments.
  # `grep -n` output is `lineno:content`; we strip the `<digits>:` prefix
  # with `sed` before testing `^\s*(//|\*)` so the comment test applies to
  # the actual code content, not the line-number prefix.
  matches="$(
    grep -n -E "\.(from|rpc)\('" "$file" 2>/dev/null \
      | while IFS= read -r hit; do
          content="${hit#*:}"   # strip leading `lineno:`
          if echo "$content" | grep -q -E "$COMMENT_PATTERN"; then
            continue
          fi
          echo "$hit"
        done \
    || true
  )"

  if [[ -n "$matches" ]]; then
    HITS+="$file:"$'\n'"$matches"$'\n\n'
  fi
done < <(
  find "$LIB_DIR" -type f -name '*.dart' \
    | grep -v '/data/'
)

if [[ -n "$HITS" ]]; then
  echo "check_no_supabase_outside_data: found Supabase table/RPC calls outside lib/**/data/:" >&2
  echo "" >&2
  echo "$HITS" >&2
  echo "Move .from('…') / .rpc('…') calls into the appropriate repository" >&2
  echo "class under lib/**/data/. If this is a genuine infra probe (not feature" >&2
  echo "data access), add the file path to the ALLOW_LIST in this script with" >&2
  echo "a documented // ALLOW: <reason> comment above the entry." >&2
  exit 1
fi

echo "check_no_supabase_outside_data: clean."
exit 0
