-- =============================================================================
-- Bug A fix — fn_exercises_localized (and its three siblings) didn't include
-- `xp_attribution` in their RETURNS TABLE projection. The column was added
-- to `exercises` in migration 00065 (Phase 29 v2 XP formula), but because
-- the four localized RPCs explicitly enumerate columns in their RETURNS
-- TABLE shape, the new column never reached the Dart layer. The Freezed
-- `Exercise` model deserialized `xpAttribution` as `null` for every
-- RPC-fetched row, which made `WeeklyEngagementProvider` fall back to its
-- `{primaryMuscle: 1.0}` safety-net attribution for every exercise reached
-- via `RoutineRepository._resolveExercises → ExerciseRepository
-- .getExercisesByIds`.
--
-- Symptom that surfaced this bug:
--   User reported 2026-05-23: "After adding a full body exercise routine to
--   an existing completed week, I see only core being added at the totals
--   below, not the whole thing." Full-body routines (which should attribute
--   across chest/back/legs/shoulders/arms/core) counted only their primary
--   muscle per exercise. Combined with WeeklyEngagement.from's
--   max(done, planned) invariant at weekly_engagement.dart:62-67, body
--   parts already trained masked the underflow — the user saw only the
--   unique-to-this-routine BP (core) visibly grow.
--
-- Fix scope (mirrors 00058's bodyweight-load fix):
--   For each of the four exercise RPCs we re-issue `CREATE OR REPLACE
--   FUNCTION` with `xp_attribution JSONB` appended to the RETURNS TABLE
--   shape and `e.xp_attribution` appended to the SELECT projection. Every
--   other line — signature, security, validation, LATERAL cascade,
--   ORDER BY — is preserved verbatim from 00058 (which is the latest
--   in-tree definition for all four functions).
--
-- Append-only — DO NOT edit 00058 in place. Migrations are immutable once
-- shipped; the only correct way to evolve a function is to replace it
-- forward.
--
-- Forward-compatibility:
--   * RETURNS TABLE column ORDER changes are an implicit contract change
--     for positional consumers. The Dart side reads RPC results as JSON
--     keyed by column name (Freezed `fromJson`), so positional ordering
--     is irrelevant for our consumers. Adding a trailing column is the
--     safest possible projection diff.
--   * Function signatures (parameter list) are UNCHANGED for all four
--     RPCs. Existing GRANTs survive automatically; we re-emit them
--     defensively so a fresh `db reset` materializes the right grants
--     even if the prior GRANTs were dropped by an out-of-band schema
--     wipe.
--   * fn_insert_user_exercise and fn_update_user_exercise compose with
--     fn_exercises_localized via `SELECT * FROM public.fn_exercises_localized(...)`
--     at the end of their bodies. Adding the column to the leaf without
--     adding it to the wrappers would produce a "structure of query does
--     not match function result type" error at runtime (PG SQLSTATE 42804).
--     All four RPCs must move together.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Drop the prior overloads.
--
-- `CREATE OR REPLACE FUNCTION` cannot change the RETURNS TABLE shape
-- (PostgreSQL rejects with SQLSTATE 42P13: "cannot change return type of
-- existing function. Row type defined by OUT parameters is different").
-- Adding `xp_attribution` to the projection IS such a shape change, so
-- we must DROP first, then CREATE fresh.
--
-- Drop order: composing callers (fn_insert_user_exercise and
-- fn_update_user_exercise both `SELECT * FROM public.fn_exercises_localized(...)`
-- at the end of their bodies) MUST be dropped BEFORE the leaf so the new
-- RETURNS TABLE shape can land — otherwise PG rejects with SQLSTATE 42P13
-- when the wrappers' row-type no longer matches the leaf's.
--
-- fn_search_exercises_localized is NOT a composing caller — it has its own
-- standalone implementation (CTE + LATERAL projection, no SELECT * delegation
-- to fn_exercises_localized). We drop it in the same batch purely for symmetry
-- and to keep the four-function RPC family at a consistent schema version
-- (any future caller-of-search migration sees one coherent shape, not a
-- mid-migration mix).
--
-- CASCADE is intentionally NOT used: any unexpected dependency outside this
-- migration (e.g. a view we forgot about) should fail loudly here, not
-- silently vanish under CASCADE.
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.fn_insert_user_exercise(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID
);
DROP FUNCTION IF EXISTS public.fn_update_user_exercise(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT
);
DROP FUNCTION IF EXISTS public.fn_search_exercises_localized(
  TEXT, TEXT, UUID, TEXT, TEXT
);
DROP FUNCTION IF EXISTS public.fn_exercises_localized(
  TEXT, UUID, TEXT, TEXT, UUID[], TEXT
);

-- =============================================================================
-- 1. fn_exercises_localized — list/lookup RPC (00058 §1)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_exercises_localized(
  p_locale         TEXT,
  p_user_id        UUID,
  p_muscle_group   TEXT  DEFAULT NULL,
  p_equipment_type TEXT  DEFAULT NULL,
  p_ids            UUID[] DEFAULT NULL,
  p_order          TEXT  DEFAULT 'name'
)
RETURNS TABLE (
  id                   UUID,
  name                 TEXT,
  muscle_group         muscle_group,
  equipment_type       equipment_type,
  is_default           BOOLEAN,
  description          TEXT,
  form_tips            TEXT,
  image_start_url      TEXT,
  image_end_url        TEXT,
  user_id              UUID,
  deleted_at           TIMESTAMPTZ,
  created_at           TIMESTAMPTZ,
  slug                 TEXT,
  uses_bodyweight_load BOOLEAN,
  xp_attribution       JSONB  -- Bug A fix
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Validate p_order up front so the SELECT body can branch safely.
  IF p_order IS NULL OR p_order NOT IN ('name', 'created_at_desc') THEN
    RAISE EXCEPTION 'invalid p_order: %, expected one of (name, created_at_desc)', p_order
      USING ERRCODE = '22023';
  END IF;

  -- Hard cap on batch size. array_length is NULL for empty arrays so we
  -- guard with COALESCE.
  IF p_ids IS NOT NULL AND COALESCE(array_length(p_ids, 1), 0) > 500 THEN
    RAISE EXCEPTION 'p_ids too large: %, max 500', array_length(p_ids, 1)
      USING ERRCODE = '22023';
  END IF;

  -- Resolution cascade implemented as LEFT JOIN LATERAL: one subquery per
  -- exercise row resolves all three localized fields (name, description,
  -- form_tips) at once, instead of running 9 correlated subqueries (3 fields
  -- x 3 cascade tiers) plus a 10th for ORDER BY. The lateral output is
  -- referenced both in the projection and ORDER BY, so name resolution is
  -- computed exactly once per row.
  RETURN QUERY
  SELECT
    e.id,
    resolved.name,
    e.muscle_group,
    e.equipment_type,
    e.is_default,
    resolved.description,
    resolved.form_tips,
    e.image_start_url,
    e.image_end_url,
    e.user_id,
    e.deleted_at,
    e.created_at,
    e.slug,
    e.uses_bodyweight_load,
    e.xp_attribution  -- Bug A fix
  FROM exercises e
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(t_locale.name,        t_en.name,        t_any.name)        AS name,
      COALESCE(t_locale.description, t_en.description, t_any.description) AS description,
      COALESCE(t_locale.form_tips,   t_en.form_tips,   t_any.form_tips)   AS form_tips
    FROM (SELECT 1) dummy
    LEFT JOIN exercise_translations t_locale
      ON t_locale.exercise_id = e.id AND t_locale.locale = p_locale
    LEFT JOIN exercise_translations t_en
      ON t_en.exercise_id = e.id AND t_en.locale = 'en'
    LEFT JOIN exercise_translations t_any
      ON t_any.exercise_id = e.id
     AND NOT EXISTS (
       SELECT 1 FROM exercise_translations t2
       WHERE t2.exercise_id = e.id AND t2.locale IN (p_locale, 'en')
     )
    LIMIT 1
  ) AS resolved ON TRUE
  WHERE e.deleted_at IS NULL
    AND (e.is_default = true OR e.user_id = p_user_id)
    AND (
      -- Batch mode: filter by id set only, ignore muscle/equipment.
      (p_ids IS NOT NULL AND COALESCE(array_length(p_ids, 1), 0) > 0
        AND e.id = ANY(p_ids))
      OR
      -- Non-batch mode: optional muscle/equipment filters.
      (
        (p_ids IS NULL OR COALESCE(array_length(p_ids, 1), 0) = 0)
        AND (p_muscle_group IS NULL
             OR e.muscle_group::text = p_muscle_group)
        AND (p_equipment_type IS NULL
             OR e.equipment_type::text = p_equipment_type)
      )
    )
  -- Order: only applied in non-batch mode. In batch mode the caller is
  -- typically rebuilding a Map<id, Exercise> and order is irrelevant.
  -- Both ORDER BY branches reference lateral output / table columns directly,
  -- so no additional resolution work is performed here.
  ORDER BY
    CASE WHEN p_order = 'name'
              AND (p_ids IS NULL OR COALESCE(array_length(p_ids, 1), 0) = 0)
         THEN resolved.name
    END ASC,
    CASE WHEN p_order = 'created_at_desc'
              AND (p_ids IS NULL OR COALESCE(array_length(p_ids, 1), 0) = 0)
         THEN e.created_at
    END DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_exercises_localized(
  TEXT, UUID, TEXT, TEXT, UUID[], TEXT
) TO authenticated;


-- =============================================================================
-- 2. fn_search_exercises_localized — trigram search RPC (00058 §2)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_search_exercises_localized(
  p_query          TEXT,
  p_locale         TEXT,
  p_user_id        UUID,
  p_muscle_group   TEXT DEFAULT NULL,
  p_equipment_type TEXT DEFAULT NULL
)
RETURNS TABLE (
  id                   UUID,
  name                 TEXT,
  muscle_group         muscle_group,
  equipment_type       equipment_type,
  is_default           BOOLEAN,
  description          TEXT,
  form_tips            TEXT,
  image_start_url      TEXT,
  image_end_url        TEXT,
  user_id              UUID,
  deleted_at           TIMESTAMPTZ,
  created_at           TIMESTAMPTZ,
  slug                 TEXT,
  uses_bodyweight_load BOOLEAN,
  xp_attribution       JSONB  -- Bug A fix
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  -- As in fn_exercises_localized: resolve all three localized text columns
  -- via a single LEFT JOIN LATERAL per matched row, then order by lateral
  -- output. This replaces 9 correlated subqueries plus an ORDER BY recompute
  -- with a single subquery per row.
  RETURN QUERY
  WITH matches AS (
    -- One row per exercise — collapse cross-locale duplicates by keeping the
    -- best similarity score across locales. DISTINCT ON requires ORDER BY
    -- prefix matching the DISTINCT key.
    SELECT DISTINCT ON (e.id)
      e.id,
      e.muscle_group,
      e.equipment_type,
      e.is_default,
      e.image_start_url,
      e.image_end_url,
      e.user_id,
      e.deleted_at,
      e.created_at,
      e.slug,
      e.uses_bodyweight_load,
      e.xp_attribution,  -- Bug A fix — propagate through CTE
      similarity(t.name, p_query) AS score
    FROM exercises e
    JOIN exercise_translations t ON t.exercise_id = e.id
    WHERE e.deleted_at IS NULL
      AND (e.is_default = true OR e.user_id = p_user_id)
      AND t.locale IN (p_locale, 'en')
      AND t.name % p_query
      AND (p_muscle_group IS NULL
           OR e.muscle_group::text = p_muscle_group)
      AND (p_equipment_type IS NULL
           OR e.equipment_type::text = p_equipment_type)
    ORDER BY e.id, similarity(t.name, p_query) DESC
  )
  SELECT
    m.id,
    resolved.name,
    m.muscle_group,
    m.equipment_type,
    m.is_default,
    resolved.description,
    resolved.form_tips,
    m.image_start_url,
    m.image_end_url,
    m.user_id,
    m.deleted_at,
    m.created_at,
    m.slug,
    m.uses_bodyweight_load,
    m.xp_attribution  -- Bug A fix
  FROM matches m
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(t_locale.name,        t_en.name,        t_any.name)        AS name,
      COALESCE(t_locale.description, t_en.description, t_any.description) AS description,
      COALESCE(t_locale.form_tips,   t_en.form_tips,   t_any.form_tips)   AS form_tips
    FROM (SELECT 1) dummy
    LEFT JOIN exercise_translations t_locale
      ON t_locale.exercise_id = m.id AND t_locale.locale = p_locale
    LEFT JOIN exercise_translations t_en
      ON t_en.exercise_id = m.id AND t_en.locale = 'en'
    LEFT JOIN exercise_translations t_any
      ON t_any.exercise_id = m.id
     AND NOT EXISTS (
       SELECT 1 FROM exercise_translations t2
       WHERE t2.exercise_id = m.id AND t2.locale IN (p_locale, 'en')
     )
    LIMIT 1
  ) AS resolved ON TRUE
  -- ORDER BY safe to skip 'any' tier: 00032 guarantees every exercise has an 'en' row.
  ORDER BY m.score DESC,
           resolved.name ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_search_exercises_localized(
  TEXT, TEXT, UUID, TEXT, TEXT
) TO authenticated;


-- =============================================================================
-- 3. fn_insert_user_exercise — create user-owned exercise (00058 §3,
--    8-arg variant: signature MUST match 00058 to keep the prior overload
--    drop sentinel happy and to keep the offline-replay `p_id` parameter).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_insert_user_exercise(
  p_user_id        UUID,
  p_locale         TEXT,
  p_name           TEXT,
  p_muscle_group   TEXT,
  p_equipment_type TEXT,
  p_description    TEXT DEFAULT NULL,
  p_form_tips      TEXT DEFAULT NULL,
  p_id             UUID DEFAULT NULL
)
RETURNS TABLE (
  id                   UUID,
  name                 TEXT,
  muscle_group         muscle_group,
  equipment_type       equipment_type,
  is_default           BOOLEAN,
  description          TEXT,
  form_tips            TEXT,
  image_start_url      TEXT,
  image_end_url        TEXT,
  user_id              UUID,
  deleted_at           TIMESTAMPTZ,
  created_at           TIMESTAMPTZ,
  slug                 TEXT,
  uses_bodyweight_load BOOLEAN,
  xp_attribution       JSONB  -- Bug A fix
)
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new_id    UUID;
  v_new_slug  TEXT;
BEGIN
  -- Authorization. NULL auth.uid() means anonymous caller.
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'unauthorized: caller does not own p_user_id'
      USING ERRCODE = '42501';
  END IF;

  -- Duplicate-name check across the user's owned, non-deleted exercises in
  -- any locale. Replaces the dropped `idx_exercises_unique_name` functional
  -- index (which keyed on lower(name) for `exercises.name`).
  IF EXISTS (
    SELECT 1
    FROM exercise_translations t
    JOIN exercises e ON e.id = t.exercise_id
    WHERE e.user_id = p_user_id
      AND e.deleted_at IS NULL
      AND lower(t.name) = lower(p_name)
  ) THEN
    RAISE EXCEPTION 'duplicate exercise name for user: %', p_name
      USING ERRCODE = '23505';
  END IF;

  -- Compute slug inline (byte-for-byte parity with Dart `exerciseSlug()`):
  --   lower → replace non-alphanum with `_` → trim leading/trailing `_`.
  v_new_slug := trim(both '_' from regexp_replace(lower(p_name), '[^a-z0-9]+', '_', 'g'));

  -- A purely punctuation/whitespace name would slug to empty — reject loudly
  -- since the trigger would too, and a clearer message helps diagnosis.
  IF v_new_slug = '' THEN
    RAISE EXCEPTION 'exercise name produced empty slug: %', p_name
      USING ERRCODE = '22023';
  END IF;

  -- Insert exercise row. When the caller provided `p_id`, use it verbatim so
  -- offline-replayed rows keep the same PK the local Hive cache and any
  -- workout_exercises.exercise_id references already wrote. Otherwise fall
  -- back to a server-allocated UUID (online path).
  --
  -- Note: we do NOT set uses_bodyweight_load here — the column has a
  -- DEFAULT FALSE (00056) which is the correct value for any user-created
  -- exercise (curation is the database team's call, not the user's). We
  -- also do NOT set xp_attribution — user-created exercises legitimately
  -- have no attribution map (server-side curation only), so consumers
  -- correctly fall back to `{muscle_group: 1.0}` for those rows. Both
  -- columns appear in the RETURNS TABLE so the post-insert SELECT below
  -- carries their values back to the client.
  INSERT INTO exercises (
    id, user_id, is_default, muscle_group, equipment_type, slug
  )
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_user_id,
    false,
    p_muscle_group::muscle_group,
    p_equipment_type::equipment_type,
    v_new_slug
  )
  RETURNING exercises.id INTO v_new_id;

  -- Insert the single translation row. RLS policy
  -- `exercise_translations_insert_own` allows it because we just inserted
  -- the parent with `user_id = p_user_id = auth.uid()`.
  INSERT INTO exercise_translations (
    exercise_id, locale, name, description, form_tips
  )
  VALUES (
    v_new_id, p_locale, p_name, p_description, p_form_tips
  );

  -- Return the localized view. Single-row case: just call the list RPC with
  -- p_ids = ARRAY[v_new_id]. fn_exercises_localized now projects
  -- xp_attribution (Bug A fix above), so this composition transparently
  -- surfaces the new column.
  RETURN QUERY
  SELECT * FROM public.fn_exercises_localized(
    p_locale,
    p_user_id,
    NULL, NULL,
    ARRAY[v_new_id]::UUID[],
    'name'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_insert_user_exercise(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID
) TO authenticated;


-- =============================================================================
-- 4. fn_update_user_exercise — edit user-owned exercise (00058 §4)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_update_user_exercise(
  p_exercise_id    UUID,
  p_name           TEXT DEFAULT NULL,
  p_muscle_group   TEXT DEFAULT NULL,
  p_equipment_type TEXT DEFAULT NULL,
  p_description    TEXT DEFAULT NULL,
  p_form_tips      TEXT DEFAULT NULL
)
RETURNS TABLE (
  id                   UUID,
  name                 TEXT,
  muscle_group         muscle_group,
  equipment_type       equipment_type,
  is_default           BOOLEAN,
  description          TEXT,
  form_tips            TEXT,
  image_start_url      TEXT,
  image_end_url        TEXT,
  user_id              UUID,
  deleted_at           TIMESTAMPTZ,
  created_at           TIMESTAMPTZ,
  slug                 TEXT,
  uses_bodyweight_load BOOLEAN,
  xp_attribution       JSONB  -- Bug A fix
)
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_id   UUID;
  v_is_default BOOLEAN;
  v_locale     TEXT;
BEGIN
  -- Look up ownership + default flag in one shot. Single row by PK.
  SELECT e.user_id, e.is_default
    INTO v_owner_id, v_is_default
  FROM exercises e
  WHERE e.id = p_exercise_id;

  -- "Not found" and "found-but-not-owned" both surface as 42501 on purpose:
  -- leaking existence of another user's row would let a caller probe for
  -- valid IDs. Message reflects this dual meaning.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'exercise not found or not owned by caller: %', p_exercise_id
      USING ERRCODE = '42501';
  END IF;

  -- Authorization: caller must own AND target must not be a default.
  IF v_is_default OR v_owner_id IS NULL OR v_owner_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: cannot edit default or non-owned exercise'
      USING ERRCODE = '42501';
  END IF;

  -- Locate the single translation row (§10 invariant: exactly one row per
  -- user-created exercise). Capture its locale so we update in place without
  -- changing the locale tag.
  SELECT t.locale INTO v_locale
  FROM exercise_translations t
  WHERE t.exercise_id = p_exercise_id
  LIMIT 1;

  IF v_locale IS NULL THEN
    RAISE EXCEPTION 'exercise has no translation row: %', p_exercise_id
      USING ERRCODE = '22023';
  END IF;

  -- Duplicate-name check. Only fires when p_name is non-NULL and does not
  -- match the current name (case-insensitive). Skipping the self-row keeps
  -- a no-op rename from spuriously raising 23505.
  IF p_name IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM exercise_translations t
      JOIN exercises e ON e.id = t.exercise_id
      WHERE e.user_id = v_owner_id
        AND e.deleted_at IS NULL
        AND e.id <> p_exercise_id
        AND lower(t.name) = lower(p_name)
    ) THEN
      RAISE EXCEPTION 'duplicate exercise name for user: %', p_name
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Update metadata if any changed. CASE form keeps the existing value when
  -- the parameter is NULL without forcing a NULL-cast through the enum type.
  -- uses_bodyweight_load + xp_attribution are intentionally NOT touched
  -- here — same rationale as fn_insert_user_exercise above (curation flags,
  -- not user-editable).
  UPDATE exercises e
  SET
    muscle_group   = CASE WHEN p_muscle_group   IS NULL THEN e.muscle_group
                          ELSE p_muscle_group::muscle_group     END,
    equipment_type = CASE WHEN p_equipment_type IS NULL THEN e.equipment_type
                          ELSE p_equipment_type::equipment_type END
  WHERE e.id = p_exercise_id;

  -- Update the single translation row in place. Each column updates only if
  -- its parameter is non-NULL.
  UPDATE exercise_translations t
  SET
    name        = COALESCE(p_name,        t.name),
    description = COALESCE(p_description, t.description),
    form_tips   = COALESCE(p_form_tips,   t.form_tips)
  WHERE t.exercise_id = p_exercise_id
    AND t.locale = v_locale;

  -- Return the localized view at the row's preserved locale. Composes with
  -- fn_exercises_localized which now projects xp_attribution.
  RETURN QUERY
  SELECT * FROM public.fn_exercises_localized(
    v_locale,
    v_owner_id,
    NULL, NULL,
    ARRAY[p_exercise_id]::UUID[],
    'name'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_update_user_exercise(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT
) TO authenticated;


-- =============================================================================
-- Sanity asserts — every replaced function must have xp_attribution in its
-- return type. A future drive-by edit that accidentally rolls back the
-- projection should fail at migration time, not at first failing E2E.
-- Mirrors the 00058 uses_bodyweight_load sentinel.
-- =============================================================================
DO $$
DECLARE
  v_fn TEXT;
  v_has_col BOOLEAN;
  v_fns TEXT[] := ARRAY[
    'fn_exercises_localized',
    'fn_search_exercises_localized',
    'fn_insert_user_exercise',
    'fn_update_user_exercise'
  ];
BEGIN
  FOREACH v_fn IN ARRAY v_fns LOOP
    -- Inspect the function's declared TABLE-return columns. pg_proc.proargnames
    -- contains every parameter name (IN + OUT + TABLE columns), and
    -- proargmodes is a parallel array of per-arg modes ('i' IN, 'o' OUT,
    -- 'b' INOUT, 'v' VARIADIC, 't' TABLE). We unnest the two arrays in
    -- lock-step with WITH ORDINALITY and filter to mode = 't'.
    SELECT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN LATERAL (
        SELECT name, mode
        FROM unnest(p.proargnames, p.proargmodes) AS t(name, mode)
      ) args ON TRUE
      WHERE n.nspname = 'public'
        AND p.proname = v_fn
        AND args.mode = 't'
        AND args.name = 'xp_attribution'
    )
    INTO v_has_col;

    IF NOT v_has_col THEN
      RAISE EXCEPTION
        'Bug A fix invariant violated: function public.% does not project xp_attribution. Re-check the RETURNS TABLE shape.',
        v_fn;
    END IF;
  END LOOP;
END
$$;

COMMIT;

-- Force PostgREST schema cache reload so the new column is visible to the
-- Dart layer immediately after `db push` lands. Without this, the first
-- `select()` on the RPC would still see the cached column list and the
-- weekly-engagement attribution path would stay broken until the next idle
-- cache refresh (up to 10 minutes).
NOTIFY pgrst, 'reload schema';
