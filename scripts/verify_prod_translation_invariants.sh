#!/usr/bin/env bash
# Phase 15f Stage 5 — manual healthcheck for the four schema invariants
# defined in §14.1 of the design spec
# (docs/PROJECT.md §4 Phase 15f):
#
#   1. Every `exercises` row has an `'en'` translation.
#   2. Every default exercise has a `'pt'` translation.
#   3. No `exercises` row has NULL or empty slug.
#   4. The legacy `name`/`description`/`form_tips` columns no longer exist
#      on `public.exercises`.
#
# This script is NOT wired into GitHub Actions (per spec §13). It ships as
# a manual tool for staging/prod cut-over verification (spec §15 step 3
# and §14.1 acceptance criterion).
#
# Usage:
#   DATABASE_URL="postgresql://..." scripts/verify_prod_translation_invariants.sh
#   scripts/verify_prod_translation_invariants.sh "postgresql://..."
#
# Each query's result is printed with a clear PASS/FAIL label. Final exit is
# 0 only if all four pass; nonzero with a summary if any fail.

set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "FAIL: psql not found on PATH. Install postgresql-client or run via"
  echo "      \`npx supabase db ...\` on a host with psql available." >&2
  exit 2
fi

DB_URL="${DATABASE_URL:-${1:-}}"
if [ -z "${DB_URL}" ]; then
  echo "FAIL: no database URL provided." >&2
  echo "      Set \$DATABASE_URL or pass it as the first argument:" >&2
  echo "        DATABASE_URL=\"postgresql://...\" scripts/verify_prod_translation_invariants.sh" >&2
  echo "        scripts/verify_prod_translation_invariants.sh \"postgresql://...\"" >&2
  exit 2
fi

run_invariant() {
  local label="${1}"
  local sql="${2}"
  local expected="${3}"
  # Capture stderr to a temp file so connection/auth/syntax errors surface
  # legibly. Piping stdout through `tr` to trim whitespace would otherwise
  # swallow them and leave `actual` empty (which compares falsely to "0").
  local err_file
  err_file=$(mktemp)
  local actual_raw
  # -A: unaligned, -t: tuples-only, -X: skip psqlrc.
  if ! actual_raw=$(psql "${DB_URL}" -A -t -X -c "${sql}" 2>"${err_file}"); then
    echo "FAIL: ${label}"
    echo "      ERROR: psql failed:"
    sed 's/^/        /' "${err_file}"
    echo "      query: ${sql}"
    rm -f "${err_file}"
    return 1
  fi
  rm -f "${err_file}"
  local actual
  actual=$(printf '%s' "${actual_raw}" | tr -d '[:space:]')
  if [ "${actual}" = "${expected}" ]; then
    echo "PASS: ${label}  (got ${actual}, expected ${expected})"
    return 0
  fi
  echo "FAIL: ${label}  (got ${actual}, expected ${expected})"
  echo "      query: ${sql}"
  return 1
}

echo "Phase 15f translation invariants — verifying against:"
# Strip the password from the URL for the banner — show only host/db.
sanitized=$(printf '%s' "${DB_URL}" | sed -E 's#://[^@]+@#://***@#')
echo "  ${sanitized}"
echo ""

failures=0

# 1. Every exercise has an 'en' translation. Count rows missing one.
run_invariant \
  "every exercise has an 'en' translation" \
  "SELECT COUNT(*) FROM exercises WHERE NOT EXISTS (SELECT 1 FROM exercise_translations t WHERE t.exercise_id = exercises.id AND t.locale = 'en');" \
  "0" \
  || failures=$((failures + 1))

# 2. Every default exercise has a 'pt' translation. Count default rows
#    missing one.
run_invariant \
  "every default exercise has a 'pt' translation" \
  "SELECT COUNT(*) FROM exercises WHERE is_default = true AND NOT EXISTS (SELECT 1 FROM exercise_translations t WHERE t.exercise_id = exercises.id AND t.locale = 'pt');" \
  "0" \
  || failures=$((failures + 1))

# 3. Every exercise has a non-empty slug.
run_invariant \
  "no exercise has NULL or empty slug" \
  "SELECT COUNT(*) FROM exercises WHERE slug IS NULL OR slug = '';" \
  "0" \
  || failures=$((failures + 1))

# 4. The legacy monolingual columns are gone from public.exercises.
run_invariant \
  "legacy name/description/form_tips columns dropped from public.exercises" \
  "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'exercises' AND column_name IN ('name','description','form_tips');" \
  "0" \
  || failures=$((failures + 1))

echo ""
if [ "${failures}" -eq 0 ]; then
  echo "All four invariants PASSED."
  exit 0
fi
echo "${failures} invariant(s) FAILED — schema is not in the post-Stage-4 state."
exit 1
