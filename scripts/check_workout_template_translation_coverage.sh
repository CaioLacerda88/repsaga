#!/usr/bin/env bash
# Phase 32 PR 32a — enforce that every default-template insert in a PR is
# paired with `workout_template_translations` rows for BOTH `'en'` AND `'pt'`
# for every template_slug introduced. Mirrors the shape of
# `scripts/check_exercise_translation_coverage.sh`.
#
# Detection model:
#
#   1. Slug introduction: collect every default-template slug introduced by
#      the PR's changed migrations. Two shapes are recognized:
#        a) `UPDATE workout_templates SET template_slug = '<value>' WHERE
#           is_default = true ...` — the canonical backfill pattern for
#           pre-existing default rows (00067).
#        b) `INSERT INTO workout_templates (...)` blocks whose column list
#           includes `template_slug` AND `is_default`. Each VALUES tuple
#           with `is_default = true` and a literal slug emits a slug
#           introduction. (Future default templates will use this form.)
#
#   2. Translation coverage: collect every `(slug, locale)` pair the PR's
#      `INSERT INTO workout_template_translations (...)` blocks cover. We
#      only recognize the explicit `(VALUES ('slug_a', ...), ('slug_b', ...))`
#      pattern — locale comes from a literal `SELECT ..., '<locale>', ...`
#      in the SELECT list.
#
#   3. Pairing rule: every introduced slug must appear in both `'en'` AND
#      `'pt'` translation coverage within the same PR. Missing-locale slugs
#      are listed; exit nonzero.
#
# Self-test mode (`--self-test`): runs the parser against fixtures under
# `scripts/fixtures/workout_template_*.sql` so the script's own correctness
# can be verified independently of any real PR diff.
#
# Usage:
#   scripts/check_workout_template_translation_coverage.sh [BASE_REF]
#   scripts/check_workout_template_translation_coverage.sh --self-test

set -euo pipefail

# -----------------------------------------------------------------------------
# Extract introduced slugs from `UPDATE workout_templates SET template_slug =
# '<value>' WHERE is_default = true ...` — the 00067 backfill pattern.
# -----------------------------------------------------------------------------
read -r -d '' EXTRACT_INTRODUCED_SLUGS_FROM_UPDATE <<'AWK' || true
# Buffer multi-line UPDATE statements so the `WHERE is_default = true` guard
# is visible even when it sits on a different line from the `SET template_slug`
# clause (the 00067 idiomatic layout).
BEGIN { upd = 0; buf = "" }
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
function process_update(stmt,    rest, val, n, j, c) {
  if (!match(stmt, /UPDATE[[:space:]]+workout_templates[[:space:]]+SET[[:space:]]+template_slug[[:space:]]*=[[:space:]]*\x27/)) return
  rest = substr(stmt, RSTART + RLENGTH)
  val = ""
  n = length(rest)
  j = 1
  while (j <= n) {
    c = substr(rest, j, 1)
    if (c == "\x27") {
      if (substr(rest, j + 1, 1) == "\x27") {
        val = val "\x27"
        j += 2
        continue
      }
      break
    }
    val = val c
    j++
  }
  # Only emit slugs from rows guarded by `is_default = true`. Without this
  # guard the row could be a user-template backfill (not a default
  # introduction).
  if (length(val) > 0 && index(stmt, "is_default = true") > 0) {
    print val
  }
}
{
  line = $0
  if (upd == 0) {
    if (match(line, /UPDATE[[:space:]]+workout_templates[[:space:]]+SET[[:space:]]+template_slug/)) {
      upd = 1
      buf = ""
    }
  }
  if (upd == 1) {
    buf = buf " " line
    if (has_terminator(buf)) {
      process_update(buf)
      upd = 0
      buf = ""
    }
  }
}
AWK

# -----------------------------------------------------------------------------
# Extract introduced slugs from `INSERT INTO workout_templates (...)` blocks.
# Mirrors the exercises-insert parser: walks the column list to find slug +
# is_default positions, then walks the VALUES tuples and emits the slug for
# every `is_default = true` tuple.
# -----------------------------------------------------------------------------
read -r -d '' EXTRACT_INTRODUCED_SLUGS_FROM_INSERT <<'AWK' || true
BEGIN { ins = 0; buf = "" }
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
function parse_columns(text, positions,    op, cp, list, n, i, parts, name) {
  positions["template_slug"] = 0
  positions["is_default"]    = 0
  op = index(text, "(")
  if (op == 0) return
  cp = index(text, ")")
  if (cp == 0 || cp <= op) return
  list = substr(text, op + 1, cp - op - 1)
  n = split(list, parts, /,/)
  for (i = 1; i <= n; i++) {
    name = trim(parts[i])
    if (name == "template_slug") positions["template_slug"] = i
    if (name == "is_default")    positions["is_default"] = i
  }
}
function emit_slugs_from_values(values_text, slug_pos, is_default_pos,
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
        } else {
          in_str = 0
          tup = tup c
          continue
        }
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
        emit_slug_from_tuple(tup, slug_pos, is_default_pos)
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
function emit_slug_from_tuple(tup, slug_pos, is_default_pos,
                              n, depth, j, c, in_str, field, idx, fields,
                              val, isd) {
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
        } else {
          in_str = 0
          field = field c
          continue
        }
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

  if (is_default_pos < 1 || is_default_pos > idx) return
  isd = trim(fields[is_default_pos])
  if (isd != "true") return

  if (slug_pos < 1 || slug_pos > idx) return
  val = trim(fields[slug_pos])
  if (substr(val, 1, 1) != "\x27") return
  val = substr(val, 2)
  out = ""
  n2 = length(val)
  k = 1
  while (k <= n2) {
    cc = substr(val, k, 1)
    if (cc == "\x27") {
      if (substr(val, k + 1, 1) == "\x27") {
        out = out "\x27"
        k += 2
        continue
      }
      break
    }
    out = out cc
    k++
  }
  val = out
  if (length(val) > 0) print val
}
{
  line = $0
  if (ins == 0) {
    if (match(line, /INSERT[[:space:]]+INTO[[:space:]]+workout_templates[[:space:]]*\(/)) {
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
          emit_slugs_from_values(values_text, positions["template_slug"],
                                 positions["is_default"])
        }
      }
      ins = 0
      buf = ""
    }
  }
}
AWK

# -----------------------------------------------------------------------------
# Extract `(slug, locale)` coverage pairs from
# `INSERT INTO workout_template_translations (...)` blocks.
#
# Recognizes the explicit `(VALUES ('slug_a', ...), ('slug_b', ...))` shape
# with the locale literal in the outer SELECT projection.
# -----------------------------------------------------------------------------
read -r -d '' EXTRACT_TRANSLATION_COVERAGE <<'AWK' || true
BEGIN { ins = 0; buf = "" }
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
function emit_first_quoted(tup, locale,    n, j, c, started, val) {
  n = length(tup)
  j = 1
  started = 0
  val = ""
  while (j <= n) {
    c = substr(tup, j, 1)
    if (!started) {
      if (c == "\x27") { started = 1; j++; continue }
      j++
      continue
    }
    if (c == "\x27") {
      if (substr(tup, j + 1, 1) == "\x27") {
        val = val "\x27"
        j += 2
        continue
      }
      break
    }
    val = val c
    j++
  }
  if (length(val) > 0) print val "\t" locale
}
function emit_explicit_pairs(values_text, locale,    n, j, c, in_str, depth,
                             tup) {
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
        emit_first_quoted(tup, locale)
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
function process_block(text,    locale, sel) {
  # Locale literal: SELECT v.template_slug, '<locale>', ...
  if (match(text, /SELECT[[:space:]]+[^,]+,[[:space:]]*\x27[a-z][a-z]\x27/)) {
    sel = substr(text, RSTART, RLENGTH)
    if (match(sel, /\x27[a-z][a-z]\x27/)) {
      locale = substr(sel, RSTART + 1, 2)
    } else {
      return
    }
  } else {
    return
  }
  if (match(text, /FROM[[:space:]]*\([[:space:]]*VALUES[[:space:]]*/)) {
    vstart = RSTART + RLENGTH
    vt = substr(text, vstart)
    emit_explicit_pairs(vt, locale)
  }
}
{
  line = $0
  if (ins == 0) {
    if (match(line, /INSERT[[:space:]]+INTO[[:space:]]+workout_template_translations[[:space:]]*\(/)) {
      ins = 1
      buf = ""
    }
  }
  if (ins == 1) {
    buf = buf " " line
    if (has_terminator(buf)) {
      process_block(buf)
      ins = 0
      buf = ""
    }
  }
}
AWK

# -----------------------------------------------------------------------------
# Core check function — operates on a list of file paths.
# -----------------------------------------------------------------------------
run_check() {
  local files="${1}"
  local label="${2:-PR diff}"
  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" RETURN

  local introduced_slugs="${tmpdir}/introduced_slugs.txt"
  local en_explicit="${tmpdir}/en_explicit.txt"
  local pt_explicit="${tmpdir}/pt_explicit.txt"
  local inserter_files="${tmpdir}/inserter_files.txt"
  local translation_files="${tmpdir}/translation_files.txt"
  : > "${introduced_slugs}"
  : > "${en_explicit}"
  : > "${pt_explicit}"
  : > "${inserter_files}"
  : > "${translation_files}"

  local f
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    [ -f "${f}" ] || continue

    # 1. UPDATE workout_templates SET template_slug — backfill pattern.
    if grep -q -E "UPDATE[[:space:]]+workout_templates[[:space:]]+SET[[:space:]]+template_slug" "${f}"; then
      local update_out
      update_out=$(awk "${EXTRACT_INTRODUCED_SLUGS_FROM_UPDATE}" "${f}" || true)
      if [ -n "${update_out}" ]; then
        printf '%s\n' "${update_out}" >> "${introduced_slugs}"
        echo "${f}" >> "${inserter_files}"
      fi
    fi

    # 2. INSERT INTO workout_templates — default-template inserts.
    if grep -q -E "INSERT[[:space:]]+INTO[[:space:]]+workout_templates[[:space:]]*\(" "${f}"; then
      local insert_out
      insert_out=$(awk "${EXTRACT_INTRODUCED_SLUGS_FROM_INSERT}" "${f}" || true)
      if [ -n "${insert_out}" ]; then
        printf '%s\n' "${insert_out}" >> "${introduced_slugs}"
        echo "${f}" >> "${inserter_files}"
      fi
    fi

    # 3. INSERT INTO workout_template_translations — coverage rows.
    if grep -q -E "INSERT[[:space:]]+INTO[[:space:]]+workout_template_translations[[:space:]]*\(" "${f}"; then
      local cov_out
      cov_out=$(awk "${EXTRACT_TRANSLATION_COVERAGE}" "${f}" || true)
      if [ -n "${cov_out}" ]; then
        local emitted_any=0
        while IFS= read -r line; do
          [ -z "${line}" ] && continue
          emitted_any=1
          local slug locale
          slug=$(printf '%s' "${line}" | awk -F'\t' '{print $1}')
          locale=$(printf '%s' "${line}" | awk -F'\t' '{print $2}')
          if [ "${locale}" = "en" ]; then echo "${slug}" >> "${en_explicit}"; fi
          if [ "${locale}" = "pt" ]; then echo "${slug}" >> "${pt_explicit}"; fi
        done <<EOF_COV
${cov_out}
EOF_COV
        if [ "${emitted_any}" -eq 1 ]; then
          echo "${f}" >> "${translation_files}"
        fi
      fi
    fi
  done <<EOF
${files}
EOF

  if [ ! -s "${introduced_slugs}" ]; then
    echo "No new default-template slugs in the ${label} — coverage check skipped."
    return 0
  fi

  sort -u "${introduced_slugs}" -o "${introduced_slugs}"
  sort -u "${en_explicit}" -o "${en_explicit}"
  sort -u "${pt_explicit}" -o "${pt_explicit}"

  local missing_en="${tmpdir}/missing_en.txt"
  local missing_pt="${tmpdir}/missing_pt.txt"
  : > "${missing_en}"
  : > "${missing_pt}"

  comm -23 "${introduced_slugs}" "${en_explicit}" > "${missing_en}" || true
  comm -23 "${introduced_slugs}" "${pt_explicit}" > "${missing_pt}" || true

  if [ -s "${missing_en}" ] || [ -s "${missing_pt}" ]; then
    echo "FAIL: introduced default-template slugs lack paired en and/or pt"
    echo "      translations in workout_template_translations within the same ${label}."
    echo ""
    if [ -s "${missing_en}" ]; then
      echo "  missing en translation for slug(s):"
      while IFS= read -r s; do
        [ -n "${s}" ] && echo "    - ${s}"
      done < "${missing_en}"
      echo ""
    fi
    if [ -s "${missing_pt}" ]; then
      echo "  missing pt translation for slug(s):"
      while IFS= read -r s; do
        [ -n "${s}" ] && echo "    - ${s}"
      done < "${missing_pt}"
      echo ""
    fi
    echo "  fix: add INSERT INTO workout_template_translations rows for each"
    echo "       missing slug+locale pair — either in the same migration file"
    echo "       or in a sibling migration in the same PR. See"
    echo "       supabase/migrations/00067_workout_template_translations.sql"
    echo "       for the canonical (VALUES ...) pattern."
    return 1
  fi

  local intro_count
  intro_count=$(wc -l < "${introduced_slugs}" | tr -d ' ')

  echo "OK: introduced default-template slugs paired with en+pt translations."
  echo "  introduced slugs: ${intro_count}"
  echo "  en coverage: $(wc -l < "${en_explicit}" | tr -d ' ') slug(s)"
  echo "  pt coverage: $(wc -l < "${pt_explicit}" | tr -d ' ') slug(s)"
  if [ -s "${inserter_files}" ]; then
    echo "  introductions in:"
    sort -u "${inserter_files}" | sed 's/^/    /'
  fi
  if [ -s "${translation_files}" ]; then
    echo "  translations in:"
    sort -u "${translation_files}" | sed 's/^/    /'
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Self-test mode.
# -----------------------------------------------------------------------------
run_self_test() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local fixture_complete="${script_dir}/fixtures/workout_template_complete.sql"
  local fixture_missing="${script_dir}/fixtures/workout_template_pt_missing.sql"

  if [ ! -f "${fixture_complete}" ] || [ ! -f "${fixture_missing}" ]; then
    echo "FAIL: self-test fixtures missing under ${script_dir}/fixtures/"
    echo "  expected: workout_template_complete.sql + workout_template_pt_missing.sql"
    return 1
  fi

  echo "Self-test: running coverage check against workout_template_complete.sql"
  echo "------------------------------------------------------------------"
  local rc_complete=0
  run_check "${fixture_complete}" "complete fixture" || rc_complete=$?
  echo ""

  echo "Self-test: running coverage check against workout_template_pt_missing.sql"
  echo "------------------------------------------------------------------"
  local rc_missing=0
  run_check "${fixture_missing}" "pt-missing fixture" || rc_missing=$?
  echo ""

  if [ "${rc_complete}" -ne 0 ]; then
    echo "Self-test FAILED: complete fixture should have passed (got rc=${rc_complete})."
    return 1
  fi
  if [ "${rc_missing}" -eq 0 ]; then
    echo "Self-test FAILED: pt-missing fixture should have failed (got rc=0)."
    return 1
  fi
  echo "Self-test: complete passed; pt-missing failed."
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
  echo "No migration changes — coverage check skipped."
  exit 0
fi

run_check "${changed}" "PR diff"
