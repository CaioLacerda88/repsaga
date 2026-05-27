-- Self-test fixture: a future-shape migration that introduces a NEW default
-- template via INSERT INTO workout_templates (with template_slug set inline)
-- AND has matching en + pt translation rows. Exercises the INSERT branch of
-- the parser (the 00067 backfill UPDATE branch is covered by
-- workout_template_complete.sql). The script must accept this as PASS.

BEGIN;

INSERT INTO workout_templates (id, user_id, name, is_default, exercises, template_slug)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  NULL,
  'Hypertrophy Block',
  true,
  '[]'::jsonb,
  'hypertrophy_block'
);

INSERT INTO workout_template_translations (template_slug, locale, name)
SELECT v.template_slug, 'en', v.name
FROM (VALUES
  ('hypertrophy_block', 'Hypertrophy Block')
) AS v(template_slug, name);

INSERT INTO workout_template_translations (template_slug, locale, name)
SELECT v.template_slug, 'pt', v.name
FROM (VALUES
  ('hypertrophy_block', 'Bloco de Hipertrofia')
) AS v(template_slug, name);

COMMIT;
