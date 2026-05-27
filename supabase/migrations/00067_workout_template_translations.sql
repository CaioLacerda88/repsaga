-- Phase 32 PR 32a — workout_template_translations.
--
-- Mirrors the Phase 15f exercise_translations pattern: server-side per-locale
-- display names for default workout templates, joined by `template_slug`.
-- Replaces the legacy ARB-keyed `localizedRoutineName()` lookup (which never
-- ran at the render sites — `routine.name` was emitted verbatim). Scales to
-- additional locales without re-shipping the binary.
--
-- Coverage rule (enforced by scripts/check_workout_template_translation_coverage.sh):
-- every default `INSERT INTO workout_templates` MUST be paired with EN + PT
-- rows in `workout_template_translations` within the same PR.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Add `template_slug` to workout_templates.
--
-- Nullable: user-created routines (`user_id IS NOT NULL AND is_default = false`)
-- never carry a slug. Only the 9 seeded default templates use it.
-- ---------------------------------------------------------------------------

ALTER TABLE workout_templates
  ADD COLUMN IF NOT EXISTS template_slug TEXT;

-- One slug per default template — partial unique index on the default subset.
CREATE UNIQUE INDEX IF NOT EXISTS workout_templates_default_slug_uidx
  ON workout_templates (template_slug)
  WHERE is_default = true;

-- Backfill the 9 known default templates by name. Idempotent: only updates
-- rows whose `template_slug` is still NULL.
UPDATE workout_templates SET template_slug = 'push_day'
  WHERE is_default = true AND name = 'Push Day' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'pull_day'
  WHERE is_default = true AND name = 'Pull Day' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'leg_day'
  WHERE is_default = true AND name = 'Leg Day' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'full_body'
  WHERE is_default = true AND name = 'Full Body' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'upper_lower_upper'
  WHERE is_default = true AND name = 'Upper/Lower — Upper' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'upper_lower_lower'
  WHERE is_default = true AND name = 'Upper/Lower — Lower' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = '5x5_strength'
  WHERE is_default = true AND name = '5x5 Strength' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'full_body_beginner'
  WHERE is_default = true AND name = 'Full Body Beginner' AND template_slug IS NULL;
UPDATE workout_templates SET template_slug = 'arms_abs'
  WHERE is_default = true AND name = 'Arms & Abs' AND template_slug IS NULL;

-- ---------------------------------------------------------------------------
-- 2. workout_template_translations.
--
-- Keyed on (template_slug, locale). Service-role writes only; authenticated
-- users read via the SELECT policy below.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS workout_template_translations (
  template_slug TEXT        NOT NULL,
  locale        TEXT        NOT NULL
                            CHECK (locale IN ('en', 'pt')),
  name          TEXT        NOT NULL
                            CHECK (char_length(name) BETWEEN 1 AND 120),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (template_slug, locale)
);

-- Locale-only scans for analytics / coverage queries.
CREATE INDEX IF NOT EXISTS workout_template_translations_locale_idx
  ON workout_template_translations (locale);

-- Reuse the canonical set_updated_at() helper defined in 00023.
DROP TRIGGER IF EXISTS workout_template_translations_set_updated_at
  ON workout_template_translations;
CREATE TRIGGER workout_template_translations_set_updated_at
  BEFORE UPDATE ON workout_template_translations
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE workout_template_translations ENABLE ROW LEVEL SECURITY;

-- SELECT: any authenticated user reads translations. Default templates are
-- universally visible, so their translations are too. No INSERT / UPDATE /
-- DELETE policy → only service_role (which bypasses RLS) can write.
DROP POLICY IF EXISTS workout_template_translations_select
  ON workout_template_translations;
CREATE POLICY workout_template_translations_select
  ON workout_template_translations
  FOR SELECT
  TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 3. Seed en + pt rows for the 9 default templates.
--
-- Two INSERT blocks (one per locale) using `INSERT ... ON CONFLICT DO NOTHING`
-- so re-running the migration is safe.
-- ---------------------------------------------------------------------------

INSERT INTO workout_template_translations (template_slug, locale, name)
SELECT v.template_slug, 'en', v.name
FROM (VALUES
  ('push_day',           'Push Day'),
  ('pull_day',           'Pull Day'),
  ('leg_day',            'Leg Day'),
  ('full_body',          'Full Body'),
  ('upper_lower_upper',  'Upper/Lower — Upper'),
  ('upper_lower_lower',  'Upper/Lower — Lower'),
  ('5x5_strength',       '5x5 Strength'),
  ('full_body_beginner', 'Full Body Beginner'),
  ('arms_abs',           'Arms & Abs')
) AS v(template_slug, name)
ON CONFLICT (template_slug, locale) DO NOTHING;

INSERT INTO workout_template_translations (template_slug, locale, name)
SELECT v.template_slug, 'pt', v.name
FROM (VALUES
  ('push_day',           'Dia de Empurrar'),
  ('pull_day',           'Dia de Puxar'),
  ('leg_day',            'Dia de Pernas'),
  ('full_body',          'Corpo Inteiro'),
  ('upper_lower_upper',  'Superior/Inferior — Superior'),
  ('upper_lower_lower',  'Superior/Inferior — Inferior'),
  ('5x5_strength',       'Força 5x5'),
  ('full_body_beginner', 'Corpo Inteiro Iniciante'),
  ('arms_abs',           'Braços e Abdômen')
) AS v(template_slug, name)
ON CONFLICT (template_slug, locale) DO NOTHING;

COMMIT;
