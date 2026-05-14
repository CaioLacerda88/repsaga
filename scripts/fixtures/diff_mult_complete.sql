-- Fixture: introduces TWO default exercises and pairs both with UPDATEs.
-- Should pass.
INSERT INTO exercises (slug, muscle_group, equipment_type, is_default, user_id)
VALUES
  ('test_new_lift_a', 'chest', 'barbell', true, NULL),
  ('test_new_lift_b', 'legs', 'dumbbell', true, NULL);

UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'test_new_lift_a'; -- T3 + 2 → 1.09
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'test_new_lift_b'; -- T5 + 1 → 0.87
