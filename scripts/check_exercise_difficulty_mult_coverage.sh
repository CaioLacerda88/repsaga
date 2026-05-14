#!/usr/bin/env bash
# Phase 24a — enforce that every default-exercise insert in a PR is paired
# with a difficulty_mult assignment for the same slug. Sibling to
# scripts/check_exercise_translation_coverage.sh, which enforces the same
# pairing rule for exercise_translations (en + pt).
#
# Why this gate exists:
#   The exercises.difficulty_mult column has a NOT NULL DEFAULT 1.0 (chosen
#   for user-created rows, where 1.0 is a defensible neutral). For DEFAULT
#   rows (is_default = true), 1.0 is wrong — every default is curated
#   against docs/xp-difficulty-framework.md §3 and assigned a tier-derived
#   composite. Without this gate, a future migration that adds a new default
#   exercise would silently ship at 1.0 (all the assertions in
#   00053_add_exercise_difficulty_mult.sql only look at slugs present in
#   that migration's UPDATE block — they cannot see slugs added by later
#   migrations).
#
# Detection model (analogous to check_exercise_translation_coverage.sh):
#
#   1. Slug introduction: for every changed migration, collect every slug
#      introduced as a default-exercise INSERT. Two shapes:
#        a) `INSERT INTO exercises (..., slug, ..., is_default, ...) VALUES
#           ('barbell_bench_press', ..., true, ...)` — direct slug literal in
#           the column list.
#        b) `INSERT INTO exercises (... is_default ...) SELECT ..., true ...
#           FROM (VALUES ('barbell_bench_press', ...)) v(slug, ...)` — slug
#           in a VALUES sub-table joined onto exercises.
#      Both shapes are recognized by reusing the awk parser from the
#      translation coverage script (post-Stage-4 schema requires `slug` in
#      the column list of any INSERT INTO exercises; the translation script
#      enforces this via the __MISSING_SLUG_COL__ sentinel, which we also
#      respect here).
#
#   2. difficulty_mult coverage: collect every slug covered by either:
#        a) an inline `difficulty_mult` column value in the INSERT itself
#           (column position parsed from the column list, value parsed
#           from each tuple — non-1.0 numeric values count as coverage,
#           literal `1.0` and `default` do not).
#        b) a `UPDATE exercises SET difficulty_mult = <value> WHERE slug =
#           '<slug>'` statement in any of the PR's changed migrations.
#
#   3. Pairing rule: every introduced default slug must appear in the
#      coverage set. Missing slugs are listed; exit nonzero.
#
# Self-test mode (`--self-test`): runs the parser against fixtures under
# scripts/fixtures/diff_mult_*.sql.
#
# Portable POSIX-ish bash. Runs on GitHub Actions Ubuntu runners.
#
# Usage:
#   scripts/check_exercise_difficulty_mult_coverage.sh [BASE_REF]
#   scripts/check_exercise_difficulty_mult_coverage.sh --self-test
#
# BASE_REF defaults to "origin/main". In GitHub PR context, set it to
# "origin/${GITHUB_BASE_REF}" so only the PR's changed migrations are scanned.

set -euo pipefail

# -----------------------------------------------------------------------------
# awk programs
# -----------------------------------------------------------------------------

# Reuse-friendly version of the translation-coverage parser: extract slugs
# introduced as default-exercise rows, AND in the same pass extract the
# `difficulty_mult` column value when present in the INSERT column list.
#
# Output lines (TAB-separated):
#   SLUG_INTRO\t<slug>                    — a default-exercise slug introduction
#   INLINE_MULT\t<slug>\t<value>          — slug had an inline difficulty_mult
#                                            value in the same tuple
#   __MISSING_SLUG_COL__\t<file>          — sentinel: INSERT missing slug col
read -r -d '' EXTRACT_FROM_INSERT <<'AWK' || true
BEGIN { ins = 0; buf = "" }
function trim(s) {
  sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
}
function has_terminator(s,    n, j, c, in_str) {
  # Same string-aware terminator detection as the translation coverage
  # script. A `;` inside a single-quoted literal must not flush the buffer.
  n = length(s)
  in_str = 0
  for (j = 1; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\x27") {
      if (in_str && substr(s, j + 1, 1) == "\x27") { j++; continue }
      in_str = !in_str
      continue
    }
    if (!in_str && c == ";") return 1
  }
  return 0
}
function parse_columns(text, positions,    op, cp, list, n, i, parts, name) {
  # populates positions[slug|is_default|difficulty_mult] = 1-based index or 0
  positions["slug"] = 0
  positions["is_default"] = 0
  positions["difficulty_mult"] = 0
  op = index(text, "(")
  if (op == 0) return
  cp = index(text, ")")
  if (cp == 0 || cp <= op) return
  list = substr(text, op + 1, cp - op - 1)
  n = split(list, parts, /,/)
  for (i = 1; i <= n; i++) {
    name = trim(parts[i])
    if (name == "slug")            positions["slug"] = i
    if (name == "is_default")      positions["is_default"] = i
    if (name == "difficulty_mult") positions["difficulty_mult"] = i
  }
}
function emit_slugs_from_values(values_text, slug_pos, is_default_pos,
                                mult_pos, file_for_missing,
                                i, n, depth, j, c, in_str, tup) {
  n = length(values_text)
  depth = 0
  in_str = 0
  tup = ""
  for (j = 1; j <= n; j++) {
    c = substr(values_text, j, 1)
    if (in_str) {
      if (c == "\x27") {
        if (substr(values_text, j + 1, 1) == "\x27") {
          tup = tup c "\x27"
          j++
          continue
        }
        in_str = 0
        tup = tup c
        continue
      }
      tup = tup c
      continue
    }
    if (c == "\x27") { in_str = 1; tup = tup c; continue }
    if (c == "(") {
      depth++
      if (depth == 1) { tup = ""; continue }
      tup = tup c
      continue
    }
    if (c == ")") {
      if (depth == 1) {
        emit_slug_from_tuple(tup, slug_pos, is_default_pos, mult_pos,
                             file_for_missing)
        tup = ""
        depth--
        continue
      }
      depth--
      tup = tup c
      continue
    }
    if (depth >= 1) tup = tup c
  }
}
function emit_slug_from_tuple(tup, slug_pos, is_default_pos, mult_pos,
                              file_for_missing,
                              n, depth, j, c, in_str, field, idx, fields,
                              val, isd, mult_val, slug_val) {
  n = length(tup)
  depth = 0
  in_str = 0
  field = ""
  idx = 0
  for (j = 1; j <= n; j++) {
    c = substr(tup, j, 1)
    if (in_str) {
      if (c == "\x27") {
        if (substr(tup, j + 1, 1) == "\x27") {
          field = field c "\x27"
          j++
          continue
        }
        in_str = 0
        field = field c
        continue
      }
      field = field c
      continue
    }
    if (c == "\x27") { in_str = 1; field = field c; continue }
    if (c == "(") { depth++; field = field c; continue }
    if (c == ")") { depth--; field = field c; continue }
    if (c == "," && depth == 0) {
      idx++
      fields[idx] = field
      field = ""
      continue
    }
    field = field c
  }
  idx++
  fields[idx] = field

  # Classify: only is_default = true tuples qualify as "default introductions".
  if (is_default_pos < 1 || is_default_pos > idx) return
  isd = trim(fields[is_default_pos])
  if (isd != "true") return

  # Default-exercise tuple. Slug column MUST be present.
  if (slug_pos < 1) {
    print "__MISSING_SLUG_COL__\t" file_for_missing
    return
  }
  if (slug_pos > idx) return

  # Extract slug literal.
  val = trim(fields[slug_pos])
  if (substr(val, 1, 1) != "\x27") return  # non-literal slug — skip
  slug_val = ""
  n2 = length(val)
  k = 2
  while (k <= n2) {
    cc = substr(val, k, 1)
    if (cc == "\x27") {
      if (substr(val, k + 1, 1) == "\x27") {
        slug_val = slug_val "\x27"
        k += 2
        continue
      }
      break
    }
    slug_val = slug_val cc
    k++
  }
  if (length(slug_val) == 0) return

  print "SLUG_INTRO\t" slug_val

  # Optional inline difficulty_mult value.
  if (mult_pos >= 1 && mult_pos <= idx) {
    mult_val = trim(fields[mult_pos])
    # Strip trailing type cast (`::numeric`) if present.
    sub(/::[^[:space:]]+$/, "", mult_val)
    # An inline value counts as coverage if it's a numeric literal that is
    # NOT exactly `1.0` / `1` / `1.00` (those would mean "shipped at default,
    # uncurated"). Also exclude the keyword `default` for the same reason.
    if (mult_val ~ /^[0-9]+(\.[0-9]+)?$/ \
        && mult_val + 0 != 1.0) {
      print "INLINE_MULT\t" slug_val "\t" mult_val
    }
  }
}
{
  line = $0
  if (ins == 0) {
    if (match(line, /INSERT[[:space:]]+INTO[[:space:]]+exercises[[:space:]]*\(/)) {
      ins = 1
      buf = ""
    }
  }
  if (ins == 1) {
    buf = buf " " line
    if (has_terminator(buf)) {
      delete positions
      parse_columns(buf, positions)
      col_close = index(buf, ")")
      if (col_close > 0) {
        rest = substr(buf, col_close + 1)
        if (match(rest, /VALUES[[:space:]]*/)) {
          values_text = substr(rest, RSTART + RLENGTH)
          emit_slugs_from_values(values_text, positions["slug"],
                                 positions["is_default"],
                                 positions["difficulty_mult"], FILENAME)
        }
      }
      ins = 0
      buf = ""
    }
  }
}
AWK

# Extract slugs covered by `UPDATE exercises SET difficulty_mult = <val>
# WHERE slug = '<slug>'`.
#
# Output lines (TAB-separated):
#   UPDATE_MULT\t<slug>\t<value>
#
# This recognizes the canonical curation pattern used in
# 00053_add_exercise_difficulty_mult.sql: one UPDATE per slug. Multi-row
# UPDATEs (e.g. `UPDATE ... WHERE slug IN (...)`) or value-via-CTE
# (`UPDATE ... FROM (VALUES ...) v ON e.slug = v.slug`) are not parsed —
# the migration convention is one literal UPDATE per slug for inline-comment
# auditability, and we want to enforce that convention by failing the gate
# if a future migration tries to bypass it. If a legitimate need arises for
# a CTE-based curation block, extend this parser at that time.
read -r -d '' EXTRACT_FROM_UPDATE <<'AWK' || true
BEGIN { in_stmt = 0; buf = "" }
function trim(s) {
  sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
}
function has_terminator(s,    n, j, c, in_str) {
  n = length(s)
  in_str = 0
  for (j = 1; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\x27") {
      if (in_str && substr(s, j + 1, 1) == "\x27") { j++; continue }
      in_str = !in_str
      continue
    }
    if (!in_str && c == ";") return 1
  }
  return 0
}
function process_stmt(stmt,    mult_val, slug_val, m) {
  # Match the canonical shape:
  #   UPDATE [public.]exercises SET difficulty_mult = <num> WHERE slug = '<slug>'
  # The numeric value may carry a `::numeric` cast.
  if (!match(stmt, /UPDATE[[:space:]]+(public\.)?exercises[[:space:]]+SET[[:space:]]+difficulty_mult[[:space:]]*=[[:space:]]*[0-9]+(\.[0-9]+)?/)) {
    return
  }
  m = substr(stmt, RSTART, RLENGTH)
  # Extract numeric literal.
  if (!match(m, /[0-9]+(\.[0-9]+)?$/)) return
  mult_val = substr(m, RSTART, RLENGTH)
  # Find slug literal in the WHERE clause.
  if (!match(stmt, /WHERE[[:space:]]+slug[[:space:]]*=[[:space:]]*\x27[^\x27]+\x27/)) return
  m = substr(stmt, RSTART, RLENGTH)
  if (!match(m, /\x27[^\x27]+\x27/)) return
  slug_val = substr(m, RSTART + 1, RLENGTH - 2)
  print "UPDATE_MULT\t" slug_val "\t" mult_val
}
{
  line = $0
  if (in_stmt == 0) {
    if (match(line, /UPDATE[[:space:]]+(public\.)?exercises[[:space:]]+SET[[:space:]]+difficulty_mult/)) {
      in_stmt = 1
      buf = ""
    }
  }
  if (in_stmt == 1) {
    buf = buf " " line
    if (has_terminator(buf)) {
      process_stmt(buf)
      in_stmt = 0
      buf = ""
    }
  }
}
AWK

# -----------------------------------------------------------------------------
# Core check
# -----------------------------------------------------------------------------
run_check() {
  local files="${1}"
  local label="${2:-PR diff}"
  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" RETURN

  local introduced_slugs="${tmpdir}/introduced.txt"
  local covered_slugs="${tmpdir}/covered.txt"
  local missing_slug_col="${tmpdir}/missing_slug_col.txt"
  local inserter_files="${tmpdir}/inserter_files.txt"
  local update_files="${tmpdir}/update_files.txt"
  : > "${introduced_slugs}"
  : > "${covered_slugs}"
  : > "${missing_slug_col}"
  : > "${inserter_files}"
  : > "${update_files}"

  local f
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    [ -f "${f}" ] || continue

    # 1. INSERT INTO exercises — extract introduced default slugs + any
    #    inline difficulty_mult coverage.
    if grep -q -E "INSERT[[:space:]]+INTO[[:space:]]+exercises[[:space:]]*\(" "${f}"; then
      local insert_out
      insert_out=$(awk "${EXTRACT_FROM_INSERT}" "${f}" || true)
      if [ -n "${insert_out}" ]; then
        local saw_slug=0
        while IFS= read -r line; do
          [ -z "${line}" ] && continue
          case "${line}" in
            __MISSING_SLUG_COL__*)
              echo "${f}" >> "${missing_slug_col}"
              ;;
            SLUG_INTRO*)
              # Strip "SLUG_INTRO\t" prefix.
              echo "${line#SLUG_INTRO	}" >> "${introduced_slugs}"
              saw_slug=1
              ;;
            INLINE_MULT*)
              # Strip "INLINE_MULT\t" prefix → "<slug>\t<value>". Take slug.
              local payload="${line#INLINE_MULT	}"
              local slug="${payload%%	*}"
              echo "${slug}" >> "${covered_slugs}"
              ;;
          esac
        done <<EOF_INS
${insert_out}
EOF_INS
        if [ "${saw_slug}" -eq 1 ]; then
          echo "${f}" >> "${inserter_files}"
        fi
      fi
    fi

    # 2. UPDATE exercises SET difficulty_mult — extract coverage.
    if grep -q -E "UPDATE[[:space:]]+(public\.)?exercises[[:space:]]+SET[[:space:]]+difficulty_mult" "${f}"; then
      local update_out
      update_out=$(awk "${EXTRACT_FROM_UPDATE}" "${f}" || true)
      if [ -n "${update_out}" ]; then
        local saw_update=0
        while IFS= read -r line; do
          [ -z "${line}" ] && continue
          case "${line}" in
            UPDATE_MULT*)
              local payload="${line#UPDATE_MULT	}"
              local slug="${payload%%	*}"
              echo "${slug}" >> "${covered_slugs}"
              saw_update=1
              ;;
          esac
        done <<EOF_UPD
${update_out}
EOF_UPD
        if [ "${saw_update}" -eq 1 ]; then
          echo "${f}" >> "${update_files}"
        fi
      fi
    fi
  done <<EOF
${files}
EOF

  # ---- No insert / update activity? Skip. ---------------------------------
  if [ ! -s "${inserter_files}" ] && [ ! -s "${introduced_slugs}" ]; then
    echo "No default-exercise inserts in the ${label} — difficulty_mult coverage check skipped."
    return 0
  fi

  # ---- Hard fail: any INSERT INTO exercises missing slug column. ----------
  if [ -s "${missing_slug_col}" ]; then
    echo "FAIL: INSERT INTO exercises is missing the slug column."
    echo ""
    echo "  Post-15f schema requires every default-exercise insert to include"
    echo "  the slug column in its column list (slug is NOT NULL on the table"
    echo "  and is the join key for translations + difficulty_mult curation)."
    echo ""
    echo "  offending file(s):"
    sort -u "${missing_slug_col}" | sed 's/^/    /'
    return 1
  fi

  sort -u "${introduced_slugs}" -o "${introduced_slugs}"
  sort -u "${covered_slugs}" -o "${covered_slugs}"

  if [ ! -s "${introduced_slugs}" ]; then
    echo "No new default-exercise slugs in the ${label} — difficulty_mult coverage check skipped."
    return 0
  fi

  # ---- Pairing check: every introduced slug needs difficulty_mult coverage.
  local missing="${tmpdir}/missing.txt"
  comm -23 "${introduced_slugs}" "${covered_slugs}" > "${missing}" || true

  if [ -s "${missing}" ]; then
    echo "FAIL: introduced default-exercise slugs lack difficulty_mult"
    echo "      coverage in the same ${label}."
    echo ""
    echo "  missing difficulty_mult assignment for slug(s):"
    while IFS= read -r s; do
      [ -n "${s}" ] && echo "    - ${s}"
    done < "${missing}"
    echo ""
    echo "  fix: pair each new is_default = true insert with either an inline"
    echo "       difficulty_mult column value in the INSERT itself, or a"
    echo "       follow-up 'UPDATE exercises SET difficulty_mult = <val>"
    echo "       WHERE slug = ''<slug>''' statement — in the same migration"
    echo "       file or a sibling migration in the same PR."
    echo ""
    echo "  framework: docs/xp-difficulty-framework.md §3 (tier table)"
    echo "  reference: supabase/migrations/00053_add_exercise_difficulty_mult.sql"
    echo "  rule: CLAUDE.md → Exercise difficulty multiplier coverage rule"
    return 1
  fi

  local intro_count
  intro_count=$(wc -l < "${introduced_slugs}" | tr -d ' ')

  echo "OK: introduced default-exercise slugs paired with difficulty_mult coverage."
  echo "  introduced slugs: ${intro_count}"
  echo "  coverage entries: $(wc -l < "${covered_slugs}" | tr -d ' ')"
  if [ -s "${inserter_files}" ]; then
    echo "  introductions in:"
    sort -u "${inserter_files}" | sed 's/^/    /'
  fi
  if [ -s "${update_files}" ]; then
    echo "  difficulty_mult assignments in:"
    sort -u "${update_files}" | sed 's/^/    /'
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Self-test mode.
# -----------------------------------------------------------------------------
run_self_test() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local fixtures_dir="${script_dir}/fixtures"
  local fixture_complete="${fixtures_dir}/diff_mult_complete.sql"
  local fixture_missing="${fixtures_dir}/diff_mult_missing.sql"
  local fixture_inline="${fixtures_dir}/diff_mult_inline.sql"

  # Create fixtures on the fly so they live alongside the script in repo.
  mkdir -p "${fixtures_dir}"

  cat > "${fixture_complete}" <<'SQL'
-- Fixture: introduces TWO default exercises and pairs both with UPDATEs.
-- Should pass.
INSERT INTO exercises (slug, muscle_group, equipment_type, is_default, user_id)
VALUES
  ('test_new_lift_a', 'chest', 'barbell', true, NULL),
  ('test_new_lift_b', 'legs', 'dumbbell', true, NULL);

UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'test_new_lift_a'; -- T3 + 2 → 1.09
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'test_new_lift_b'; -- T5 + 1 → 0.87
SQL

  cat > "${fixture_missing}" <<'SQL'
-- Fixture: introduces ONE default exercise but forgets the difficulty_mult.
-- Should fail.
INSERT INTO exercises (slug, muscle_group, equipment_type, is_default, user_id)
VALUES
  ('test_uncurated_lift', 'arms', 'cable', true, NULL);
SQL

  cat > "${fixture_inline}" <<'SQL'
-- Fixture: inline difficulty_mult column in the INSERT itself.
-- Should pass (no UPDATE needed).
INSERT INTO exercises (slug, muscle_group, equipment_type, is_default, difficulty_mult, user_id)
VALUES
  ('test_inline_lift', 'back', 'barbell', true, 1.21, NULL);
SQL

  echo "Self-test: complete fixture (should pass)"
  echo "------------------------------------------------------------------"
  local rc_complete=0
  run_check "${fixture_complete}" "complete fixture" || rc_complete=$?
  echo ""

  echo "Self-test: missing fixture (should fail)"
  echo "------------------------------------------------------------------"
  local rc_missing=0
  run_check "${fixture_missing}" "missing fixture" || rc_missing=$?
  echo ""

  echo "Self-test: inline fixture (should pass)"
  echo "------------------------------------------------------------------"
  local rc_inline=0
  run_check "${fixture_inline}" "inline fixture" || rc_inline=$?
  echo ""

  if [ "${rc_complete}" -ne 0 ]; then
    echo "Self-test FAILED: complete fixture should have passed (got rc=${rc_complete})."
    return 1
  fi
  if [ "${rc_missing}" -eq 0 ]; then
    echo "Self-test FAILED: missing fixture should have failed (got rc=0)."
    return 1
  fi
  if [ "${rc_inline}" -ne 0 ]; then
    echo "Self-test FAILED: inline fixture should have passed (got rc=${rc_inline})."
    return 1
  fi
  echo "Self-test: all three fixtures behaved as expected."
  return 0
}

# -----------------------------------------------------------------------------
# Entry point.
# -----------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

BASE_REF="${1:-origin/main}"
MIGRATIONS_DIR="supabase/migrations"

if git rev-parse --verify --quiet "${BASE_REF}" >/dev/null 2>&1; then
  changed=$(git diff --name-only --diff-filter=AM "${BASE_REF}"...HEAD -- "${MIGRATIONS_DIR}" || true)
else
  echo "warn: base ref ${BASE_REF} not found, scanning all migrations" >&2
  changed=$(ls "${MIGRATIONS_DIR}"/*.sql 2>/dev/null || true)
fi

if [ -z "${changed}" ]; then
  echo "No migration changes — difficulty_mult coverage check skipped."
  exit 0
fi

run_check "${changed}" "PR diff"
