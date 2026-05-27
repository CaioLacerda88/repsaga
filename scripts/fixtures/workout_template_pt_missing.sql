-- Self-test fixture: introduces TWO default template slugs but only ships en
-- translations — the pt insert covers only `push_day`. The script must
-- detect `pull_day` lacks a pt row and FAIL.

BEGIN;

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
  ('push_day', 'Dia de Empurrar')
) AS v(template_slug, name);

COMMIT;
