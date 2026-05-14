-- Fixture: introduces ONE default exercise but forgets the difficulty_mult.
-- Should fail.
INSERT INTO exercises (slug, muscle_group, equipment_type, is_default, user_id)
VALUES
  ('test_uncurated_lift', 'arms', 'cable', true, NULL);
