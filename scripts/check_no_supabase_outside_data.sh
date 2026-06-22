#!/usr/bin/env bash
# Layering gate: fails if any Dart file under `lib/` OUTSIDE a `data/`
# directory contains a Supabase table or RPC call in string-literal form.
#
# Rationale: direct `.from('table')` or `.rpc('fn')` calls belong exclusively
# in repository classes (lib/**/data/). Leaking them into providers, widgets,
# view-models, or domain models bypasses the repository abstraction, makes
# offline/mocking impossible, and fragments the data-access audit trail. This
# gate would have caught the Phase 38.9 T1.1 weekly_engagement leak.
#
# Pattern matched: `.from(` / `.rpc(` followed (across optional whitespace AND
# newlines) by a quote — single OR double. This catches every real Supabase
# call shape, including the codebase's DOMINANT multiline repository style:
#     client.rpc(
#       'save_workout',
#       params: {...},
#     )
# and double-quoted forms `.from("workouts")` (flutter_lints does not enforce
# prefer_single_quotes, so double quotes are lint-legal and must be caught).
#
# It deliberately does NOT match Dart collection / factory constructors, whose
# argument is a variable/expression (no opening quote) — `List.from(xs)`,
# `Set.from(xs)`, `Map.from(m)`, `WeeklyEngagement.from(data)`,
# `ShareLocalizations.from(l10n)` — including their multiline-wrapped forms.
#
# Comment handling: line comments (`//`, `///`) and block comments (`/* */`,
# including multiline) are stripped BEFORE matching, so doc-string references
# like `/// a raw .from('workouts') read` never false-positive.
#
# Allow-list: full relative paths from repo root. One per line. Each entry
# MUST carry a documented justification so the reason surfaces in code review
# and git blame. To add a new exception: append the path with a comment.
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

if ! command -v perl >/dev/null 2>&1; then
  echo "check_no_supabase_outside_data: perl is required but not found." >&2
  exit 2
fi

# ---- Allow-list -------------------------------------------------------
# Relative paths from REPO_ROOT. Add with a # ALLOW: <reason> comment above.

# ALLOW: infra connectivity probe — NOT feature data access. This file fires
# a single `select('id').limit(1)` against `public.users` purely to check
# whether the Supabase endpoint is reachable. It intentionally bypasses the
# repository layer because (a) there is no "users" feature repository (the
# auth tables are managed by Supabase Auth, not the app), and (b) the probe
# must remain available in fully-offline mode before any user-data providers
# have initialized. Routing through a repository would create a circular init
# dependency (HealthCheck -> UserRepository -> Supabase -> HealthCheck).
ALLOW_LIST=(
  "lib/core/offline/health_check_provider.dart"
)

# ---- Scan ---------------------------------------------------------------
# Candidate files: all .dart under lib/ NOT inside a `data/` path segment.
# `/data/` is matched as a full path segment (slashes both sides), so by
# convention ANY `data/` directory IS the repository layer and is exempt
# (`lib/features/<f>/data/`, `lib/core/data/`); substring names like
# `data_export/` or `metadata/` are NOT excluded.
#
# Per file we strip comments then run a multiline, quote-agnostic match,
# reporting the line of each violation.

HITS=""

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  rel="${file#"$REPO_ROOT/"}"

  allowed=false
  for entry in "${ALLOW_LIST[@]}"; do
    if [[ "$rel" == "$entry" ]]; then
      allowed=true
      break
    fi
  done
  $allowed && continue

  # Strip block + line comments, then find `.from(`/`.rpc(` followed (across
  # whitespace/newlines) by a quote. Emit one line number per violation.
  matches="$(
    perl -0777 -ne '
      my $s = $_;
      $s =~ s{/\*.*?\*/}{ }gs;     # block comments (incl. multiline)
      $s =~ s{//[^\n]*}{}g;        # line + doc comments
      while ($s =~ /\.(?:from|rpc)\s*\(\s*["\x27]/g) {
        my $pre = substr($s, 0, pos($s));
        my $ln  = ($pre =~ tr/\n//) + 1;
        print "  line $ln\n";
      }
    ' "$file" 2>/dev/null || true
  )"

  if [[ -n "$matches" ]]; then
    HITS+="$rel:"$'\n'"$matches"$'\n'
  fi
done < <(
  find "$LIB_DIR" -type f -name '*.dart' | grep -v '/data/'
)

if [[ -n "$HITS" ]]; then
  echo "check_no_supabase_outside_data: found Supabase table/RPC calls outside lib/**/data/:" >&2
  echo "" >&2
  echo "$HITS" >&2
  echo "Move .from('…') / .rpc('…') calls into the appropriate repository" >&2
  echo "class under lib/**/data/. If this is a genuine infra probe (not feature" >&2
  echo "data access), add the file path to the ALLOW_LIST in this script with" >&2
  echo "a documented # ALLOW: <reason> comment above the entry." >&2
  exit 1
fi

echo "check_no_supabase_outside_data: clean."
exit 0
