-- Self-test fixture: a migration that introduces TWO default template slugs
-- via UPDATE (the canonical 00067 backfill shape) AND has matching en + pt
-- translation rows for both. The script must accept this as PASS.

BEGIN;

ALTER TABLE workout_templates
  ADD COLUMN IF NOT EXISTS template_slug TEXT;

UPDATE workout_templates SET template_slug = 'push_day'
  WHERE is_default = true AND name = 'Push Day';
UPDATE workout_templates SET template_slug = 'pull_day'
  WHERE is_default = true AND name = 'Pull Day';

INSERT INTO workout_template_translations (template_slug, locale, name)
SELECT v.template_slug, 'en', v.name
FROM (VALUES
  ('push_day', 'Push Day'),
  ('pull_day', 'Pull Day')
) AS v(template_slug, name);

INSERT INTO workout_template_translations (template_slug, locale, name)
SELECT v.template_slug, 'pt', v.name
FROM (VALUES
  ('push_day', 'Dia de Empurrar'),
  ('pull_day', 'Dia de Puxar')
) AS v(template_slug, name);

COMMIT;
