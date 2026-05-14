-- Fixture: inline difficulty_mult column in the INSERT itself.
-- Should pass (no UPDATE needed).
INSERT INTO exercises (slug, muscle_group, equipment_type, is_default, difficulty_mult, user_id)
VALUES
  ('test_inline_lift', 'back', 'barbell', true, 1.21, NULL);
