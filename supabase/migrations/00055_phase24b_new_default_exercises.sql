-- =============================================================================
-- Phase 24b — adds 50 new default exercises (Olympic platform, bodyweight
-- progressions, specialty barbell, cable / machine gaps, cardio placeholders).
-- Migration: 00055_phase24b_new_default_exercises
--
-- Each exercise ships with:
--   * slug + canonical en/pt names + descriptions + form_tips (translations)
--   * muscle_group + equipment_type + secondary_muscle_groups (= [])
--   * xp_attribution (sums to 1.0; CHECK from 00040 enforces ±0.01)
--   * difficulty_mult (per Phase 24a framework; CHECK from 00053 enforces
--     [0.85, 1.25])
--   * image_start_url + image_end_url where available (28/50 from yuhonas;
--     22/50 NULL — matches existing cable_chest_press / pec_deck precedent;
--     a Phase 24b-followup will source from alt providers)
--
-- Idempotent:
--   * PART A INSERT INTO exercises uses ON CONFLICT (slug) WHERE is_default
--     = true DO NOTHING against the partial unique index from 00030.
--   * PARTS B/C INSERT INTO exercise_translations rely on the
--     (exercise_id, locale) PK from 00031 to prevent duplicates — re-runs
--     after a successful run would unique-violate, which is the intended
--     "do not silently double-seed" behavior.
--
-- Curation source: tasks/phase24b-curation.md §3 (canonical JSON dict).
-- Image manifest source: tasks/phase24b-image-manifest.json.
-- Translation source: tasks/phase24b-translations.md §3.
-- All three working artifacts are deleted in the same PR — this migration is
-- the canonical record going forward.
--
-- See:
--   * docs/xp-difficulty-framework.md — tier table (T1..T5, composite formula)
--   * supabase/migrations/00007_seed_default_exercises.sql — historical seed
--   * supabase/migrations/00033_seed_exercise_translations_pt.sql — pattern
--   * supabase/migrations/00040_rpg_system_v1.sql — xp_attribution invariant
--   * supabase/migrations/00053_add_exercise_difficulty_mult.sql — tier audit
-- =============================================================================

BEGIN;

-- ============================================================================
-- PART A — INSERT INTO exercises
--
-- Direct VALUES tuples (matches scripts/fixtures/fixture_complete.sql shape so
-- the coverage parsers can resolve slug / is_default / difficulty_mult column
-- positions by scanning the column list).
--
-- Inline `-- T<N> + <sec> sec → <value>` audit comments follow the 00053
-- convention. `sec` = jsonb_object_keys(xp_attribution) − 1 (Phase 24a §6).
-- ============================================================================

INSERT INTO exercises (
  slug,
  muscle_group,
  equipment_type,
  is_default,
  user_id,
  image_start_url,
  image_end_url,
  secondary_muscle_groups,
  xp_attribution,
  difficulty_mult
) VALUES

-- ---------- T1 — Olympic platform & ballistics (14) -------------------------
('power_clean', 'back', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/power_clean_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/power_clean_end.jpg',
 '[]'::jsonb, '{"back":0.4,"legs":0.35,"shoulders":0.15,"arms":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 named, Olympic pull)

('hang_clean', 'back', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/hang_clean_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/hang_clean_end.jpg',
 '[]'::jsonb, '{"back":0.4,"legs":0.35,"shoulders":0.15,"arms":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 named, hang variant)

('power_snatch', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/power_snatch_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/power_snatch_end.jpg',
 '[]'::jsonb, '{"legs":0.4,"back":0.3,"shoulders":0.2,"arms":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 named, power snatch)

('hang_snatch', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/hang_snatch_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/hang_snatch_end.jpg',
 '[]'::jsonb, '{"legs":0.4,"back":0.3,"shoulders":0.2,"arms":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 named, snatch variant)

('clean_and_jerk', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/clean_and_jerk_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/clean_and_jerk_end.jpg',
 '[]'::jsonb, '{"legs":0.35,"back":0.3,"shoulders":0.25,"arms":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 named, full Olympic lift)

('push_jerk', 'legs', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"shoulders":0.4,"legs":0.3,"arms":0.2,"core":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 jerk family). Image: yuhonas no_match — Phase 24b followup.

('split_jerk', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/split_jerk_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/split_jerk_end.jpg',
 '[]'::jsonb, '{"shoulders":0.4,"legs":0.3,"arms":0.2,"core":0.1}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 jerk family, split-stance receive)

('kettlebell_snatch', 'shoulders', 'kettlebell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/kettlebell_snatch_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/kettlebell_snatch_end.jpg',
 '[]'::jsonb, '{"shoulders":0.4,"back":0.25,"legs":0.2,"core":0.15}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (§3 named, KB snatch)

('dumbbell_snatch', 'shoulders', 'dumbbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"shoulders":0.4,"back":0.25,"legs":0.2,"core":0.15}'::jsonb, 1.25),
-- T1 + 3 sec → 1.27 → clamp 1.25 (analog: KB snatch ballistic). Image: yuhonas no_match — Phase 24b followup.

('medicine_ball_slam', 'core', 'bodyweight', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/medicine_ball_slam_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/medicine_ball_slam_end.jpg',
 '[]'::jsonb, '{"core":0.4,"shoulders":0.25,"back":0.2,"chest":0.1,"arms":0.05}'::jsonb, 1.25),
-- T1 + 4 sec → 1.33 → clamp 1.25 (§3 named, ballistic full-body)

('depth_jump', 'legs', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":0.85,"core":0.15}'::jsonb, 1.25),
-- T1 + 1 sec → 1.27 → clamp 1.25 (§3 named, plyometric). Image: yuhonas no_match — Phase 24b followup.

('broad_jump', 'legs', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":0.85,"core":0.15}'::jsonb, 1.25),
-- T1 + 1 sec → 1.27 → clamp 1.25 (§3 named, horizontal plyo). Image: yuhonas no_match — Phase 24b followup.

('lateral_box_jump', 'legs', 'bodyweight', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/lateral_box_jump_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/lateral_box_jump_end.jpg',
 '[]'::jsonb, '{"legs":0.85,"core":0.15}'::jsonb, 1.25),
-- T1 + 1 sec → 1.27 → clamp 1.25 (§3 box-jump lateral variant)

('single_leg_box_jump', 'legs', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":0.85,"core":0.15}'::jsonb, 1.25),
-- T1 + 1 sec → 1.27 → clamp 1.25 (§3 box-jump unilateral variant). Image: yuhonas no_match — Phase 24b followup.

-- ---------- T2 — Foundational compounds & bodyweight progressions (17) ------
('snatch_grip_deadlift', 'back', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"back":0.45,"legs":0.35,"core":0.1,"arms":0.1}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (§3 deadlift family, wide-grip). Image: yuhonas no_match — Phase 24b followup.

('deficit_deadlift', 'back', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/deficit_deadlift_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/deficit_deadlift_end.jpg',
 '[]'::jsonb, '{"back":0.4,"legs":0.4,"core":0.1,"arms":0.1}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (§3 deadlift family, increased ROM)

('mixed_grip_deadlift', 'back', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"back":0.4,"legs":0.4,"core":0.1,"arms":0.1}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (§3 deadlift family, alternating grip). Image: yuhonas no_match — Phase 24b followup.

('neutral_grip_pull_up', 'back', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"back":0.6,"arms":0.3,"core":0.1}'::jsonb, 1.19),
-- T2 + 2 sec → 1.19 (§3 strict pull-up*, neutral grip). Image: yuhonas no_match — Phase 24b followup.

('muscle_up', 'back', 'bodyweight', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/muscle_up_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/muscle_up_end.jpg',
 '[]'::jsonb, '{"back":0.45,"arms":0.3,"chest":0.15,"core":0.1}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (T2 high-skill pull-to-press)

('zercher_squat', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/zercher_squat_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/zercher_squat_end.jpg',
 '[]'::jsonb, '{"legs":0.55,"core":0.2,"back":0.15,"arms":0.1}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (§3 named, bar in elbow crooks)

('safety_bar_squat', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/safety_bar_squat_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/safety_bar_squat_end.jpg',
 '[]'::jsonb, '{"legs":0.65,"core":0.15,"back":0.15,"arms":0.05}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (analog: §3 back squat, cambered bar)

('paused_squat', 'legs', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/paused_squat_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/paused_squat_end.jpg',
 '[]'::jsonb, '{"legs":0.7,"core":0.15,"back":0.15}'::jsonb, 1.19),
-- T2 + 2 sec → 1.19 — T2 bump from T3 (non-paused barbell_squat → 1.21 in 00053; pause removes stretch reflex, adding neural demand at the same load)

('pistol_squat', 'legs', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":0.8,"core":0.2}'::jsonb, 1.17),
-- T2 + 1 sec → 1.17 (§3 named, bodyweight unilateral). Image: yuhonas no_match — Phase 24b followup.

('handstand_push_up', 'shoulders', 'bodyweight', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/handstand_push_up_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/handstand_push_up_end.jpg',
 '[]'::jsonb, '{"shoulders":0.55,"arms":0.25,"chest":0.1,"core":0.1}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (analog: §3 overhead press, inverted bodyweight)

('archer_push_up', 'chest', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"chest":0.55,"arms":0.25,"shoulders":0.15,"core":0.05}'::jsonb, 1.21),
-- T2 + 3 sec → 1.21 (§3 named, archer push-up*). Image: yuhonas no_match — Phase 24b followup.

('ring_dip', 'chest', 'bodyweight', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/ring_dip_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/ring_dip_end.jpg',
 '[]'::jsonb, '{"chest":0.45,"arms":0.4,"shoulders":0.15}'::jsonb, 1.19),
-- T2 + 2 sec → 1.19 (§3 strict dip*, ring instability)

('paused_bench_press', 'chest', 'barbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/paused_bench_press_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/paused_bench_press_end.jpg',
 '[]'::jsonb, '{"chest":0.65,"shoulders":0.2,"arms":0.15}'::jsonb, 1.19),
-- T2 + 2 sec → 1.19 — T2 bump from T3 (non-paused barbell_bench_press → 1.09 in 00053; pause removes stretch reflex)

('atlas_stone', 'back', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"back":0.35,"legs":0.3,"chest":0.15,"arms":0.1,"core":0.1}'::jsonb, 1.21),
-- T2 + 4 sec → 1.21 (cap-3 bumps; raw 1.23 → cap → 1.21) (§3 named, strongman lift, equipment_type=barbell closest enum). Image: no yuhonas folder — Phase 24b followup.

('l_sit', 'core', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"core":0.7,"arms":0.2,"shoulders":0.1}'::jsonb, 1.19),
-- T2 + 2 sec → 1.19 (T2 bodyweight isometric). Image: yuhonas no_match — Phase 24b followup.

('hanging_windshield_wiper', 'core', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"core":0.7,"back":0.2,"arms":0.1}'::jsonb, 1.19),
-- T2 + 2 sec → 1.19 (T2 bodyweight rotational, distinct from existing T5 floor variant). Image: yuhonas no_match — Phase 24b followup.

('single_leg_glute_bridge_eccentric', 'core', 'bodyweight', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/single_leg_glute_bridge_eccentric_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/single_leg_glute_bridge_eccentric_end.jpg',
 '[]'::jsonb, '{"legs":0.7,"core":0.3}'::jsonb, 1.17),
-- T2 + 1 sec → 1.17 (framework §4 bodyweight progression, slow eccentric)

-- ---------- T3 — Standard compounds (7) -------------------------------------
('single_arm_landmine_row', 'back', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"back":0.7,"arms":0.2,"core":0.1}'::jsonb, 1.09),
-- T3 + 2 sec → 1.09 (analog: §3 dumbbell row, lever-row variant). Image: yuhonas no_match — Phase 24b followup.

('kettlebell_clean', 'back', 'kettlebell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/kettlebell_clean_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/kettlebell_clean_end.jpg',
 '[]'::jsonb, '{"back":0.4,"legs":0.35,"shoulders":0.15,"arms":0.1}'::jsonb, 1.11),
-- T3 + 3 sec → 1.11 (sub-Olympic ballistic, lower skill than barbell)

('kettlebell_high_pull', 'back', 'kettlebell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/kettlebell_high_pull_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/kettlebell_high_pull_end.jpg',
 '[]'::jsonb, '{"back":0.5,"shoulders":0.25,"legs":0.15,"core":0.1}'::jsonb, 1.11),
-- T3 + 3 sec → 1.11 (KB pull pattern with hip drive)

('dumbbell_clean', 'back', 'dumbbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/dumbbell_clean_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/dumbbell_clean_end.jpg',
 '[]'::jsonb, '{"back":0.4,"legs":0.35,"shoulders":0.15,"arms":0.1}'::jsonb, 1.11),
-- T3 + 3 sec → 1.11 (sub-Olympic ballistic, DB lower skill than barbell)

('larsen_press', 'chest', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"chest":0.6,"shoulders":0.25,"arms":0.1,"core":0.05}'::jsonb, 1.11),
-- T3 + 3 sec → 1.11 (bench variant, legs raised — kills leg drive). Image: no yuhonas folder — Phase 24b followup.

('single_arm_landmine_press', 'shoulders', 'barbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"shoulders":0.55,"chest":0.2,"arms":0.15,"core":0.1}'::jsonb, 1.11),
-- T3 + 3 sec → 1.11 (analog: existing landmine_press, unilateral adds anti-rotation). Image: yuhonas no_match — Phase 24b followup.

('suitcase_carry', 'core', 'dumbbell', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"core":0.5,"back":0.25,"arms":0.15,"legs":0.1}'::jsonb, 1.11),
-- T3 + 3 sec → 1.11 (analog: §3 farmers walk, unilateral loaded carry). Image: yuhonas no_match — Phase 24b followup.

-- ---------- T4 — Machine / cable compounds (5) ------------------------------
('belt_squat', 'legs', 'machine', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":0.9,"core":0.1}'::jsonb, 0.97),
-- T4 + 1 sec → 0.97 (machine compound, removes spinal load). Image: yuhonas no_match — Phase 24b followup.

('pendulum_squat', 'legs', 'machine', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":0.9,"core":0.1}'::jsonb, 0.97),
-- T4 + 1 sec → 0.97 (machine compound, guided arc). Image: yuhonas no_match — Phase 24b followup.

('glute_ham_raise', 'legs', 'machine', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/glute_ham_raise_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/glute_ham_raise_end.jpg',
 '[]'::jsonb, '{"legs":0.85,"core":0.1,"back":0.05}'::jsonb, 0.99),
-- T4 + 2 sec → 0.99 (posterior-chain machine compound)

('cable_pullover', 'back', 'cable', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/cable_pullover_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/cable_pullover_end.jpg',
 '[]'::jsonb, '{"back":0.55,"chest":0.3,"arms":0.1,"core":0.05}'::jsonb, 1.01),
-- T4 + 3 sec → 1.01 (cable multi-joint shoulder extension, muscle_group=back for discoverability)

('cable_overhead_extension', 'arms', 'cable', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/cable_overhead_extension_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/cable_overhead_extension_end.jpg',
 '[]'::jsonb, '{"arms":0.95,"shoulders":0.05}'::jsonb, 0.97),
-- T4 + 1 sec → 0.97 (analog: §3 tricep pushdown, overhead position)

-- ---------- T5 — Single-joint isolation & cardio placeholders (7) -----------
('single_leg_calf_raise', 'legs', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"legs":1.0}'::jsonb, 0.85),
-- T5 + 0 sec → 0.85 (analog: §3 calf raise, unilateral). Image: yuhonas no_match — Phase 24b followup.

('seated_dumbbell_calf_raise', 'legs', 'dumbbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/seated_dumbbell_calf_raise_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/seated_dumbbell_calf_raise_end.jpg',
 '[]'::jsonb, '{"legs":1.0}'::jsonb, 0.85),
-- T5 + 0 sec → 0.85 (analog: existing seated_calf_raise, DB loading)

('fat_grip_curl', 'arms', 'dumbbell', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/fat_grip_curl_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/fat_grip_curl_end.jpg',
 '[]'::jsonb, '{"arms":0.85,"back":0.1,"core":0.05}'::jsonb, 0.89),
-- T5 + 2 sec → 0.89 (analog: §3 dumbbell curl, thick-grip implement)

('copenhagen_plank', 'core', 'bodyweight', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"core":0.85,"legs":0.15}'::jsonb, 0.87),
-- T5 + 1 sec → 0.87 (T5 isometric core, adductor-loaded). Image: no yuhonas folder — Phase 24b followup.

('assault_bike', 'cardio', 'machine', true, NULL,
 NULL,
 NULL,
 '[]'::jsonb, '{"cardio":1.0}'::jsonb, 0.85),
-- T5 placeholder (cardio Phase 19 v2 deferral). Image: no yuhonas folder — Phase 24b followup.

('sled_push', 'cardio', 'machine', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/sled_push_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/sled_push_end.jpg',
 '[]'::jsonb, '{"cardio":1.0}'::jsonb, 0.85),
-- T5 placeholder (cardio Phase 19 v2 deferral, likely re-tier in 19v2)

('sled_drag', 'cardio', 'machine', true, NULL,
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/sled_drag_start.jpg',
 'https://dgcueqvqfyuedclkxixz.supabase.co/storage/v1/object/public/exercise-media/sled_drag_end.jpg',
 '[]'::jsonb, '{"cardio":1.0}'::jsonb, 0.85)
-- T5 placeholder (cardio Phase 19 v2 deferral)

ON CONFLICT (slug) WHERE is_default = true DO NOTHING;

-- ============================================================================
-- PART B — INSERT INTO exercise_translations (en)
--
-- Pattern from 00033: VALUES tuple list joined to exercises by slug.
-- Eponyms stay English in pt block (PART C) per docs/pt-glossary.md §2.
-- ============================================================================

INSERT INTO exercise_translations (exercise_id, locale, name, description, form_tips)
SELECT e.id, 'en', v.name, v.description, v.form_tips
FROM (VALUES

  ('power_clean',
   'Power Clean',
   'An Olympic-style pull from the floor to a quarter-squat catch in the front rack — explosive triple extension and a fast turnover.',
   E'Set up over the bar with hips between knees and shoulders, back tight before lift-off.\nPull the bar past the knee, then explode through full hip and knee extension.\nPull yourself UNDER the bar — do not muscle it up with the arms.\nCatch high (above parallel) with elbows fast and forward in the rack.'),

  ('hang_clean',
   'Hang Clean',
   'An Olympic clean started from the hang above the knee — trains the second pull and rack turnover without the floor pull.',
   E'Start standing with the bar in a hang position just above the knee.\nDip at the hips with the bar close, then explode in triple extension.\nPull yourself under the bar fast — do not reverse-curl it.\nCatch in a quarter-squat front rack with elbows forward.'),

  ('power_snatch',
   'Power Snatch',
   'An Olympic snatch caught above parallel — bar travels from the floor to overhead in one explosive movement.',
   E'Set up wide-grip over the bar, back flat and chest up.\nDrive through the floor with the bar close to the body.\nPunch the bar overhead aggressively as you drop into a partial squat.\nLock out with biceps next to the ears and the bar over the mid-foot.'),

  ('hang_snatch',
   'Hang Snatch',
   'A snatch pulled from the hang above the knee — trains the second pull and the bar turnover without the floor pull.',
   E'Stand tall with the bar in a wide-grip hang at mid-thigh.\nDip at the hips with the bar close, then explode in triple extension.\nPunch the bar overhead and drop fast into a partial squat catch.\nLock the elbows hard with the bar stacked over the mid-foot.'),

  ('clean_and_jerk',
   'Clean and Jerk',
   'The full Olympic two-part lift — clean the bar to the shoulders, then jerk it overhead. The heaviest lift in any sport.',
   E'Pull from the floor and catch in a front rack, just like a clean.\nStand fully erect and reset your breath in the rack before the jerk.\nDip and drive with the legs, then punch under the bar overhead.\nLock out with elbows hard and the bar stacked over the mid-foot.'),

  ('push_jerk',
   'Push Jerk',
   'An overhead drive that uses a leg dip-and-push to launch the bar, caught in a partial squat with no second dip.',
   E'Start with the bar in a tight front rack, elbows high.\nDip straight down with the chest tall — no forward lean.\nDrive the legs hard and punch the bar overhead.\nReceive in a partial squat with elbows locked, then stand.'),

  ('split_jerk',
   'Split Jerk',
   'An overhead drive caught in a split stance — front foot forward, back foot back — for a bigger receive window than the push jerk.',
   E'Start with the bar in a tight front rack, elbows high.\nDip straight down and drive the legs hard upward.\nSplit the feet under the bar — front shin vertical, back leg straight.\nLock out the bar overhead, then step the back foot forward to recover.'),

  ('kettlebell_snatch',
   'Kettlebell Snatch',
   'A one-arm Kettlebell pull from between the legs to overhead lockout in one continuous swing — full-body power and grip work.',
   E'Hike the Kettlebell between the legs with one hand.\nDrive the hips through and pull the bell up high and tight.\nPunch the hand through at the top so the bell rolls onto the back of the wrist — no flop.\nLock out the elbow overhead with the bicep by the ear.'),

  ('dumbbell_snatch',
   'Dumbbell Snatch',
   'A one-arm dumbbell pull from the floor to overhead lockout in one move — same pattern as the Kettlebell snatch, with a dumbbell.',
   E'Set up with the dumbbell on the floor between the feet.\nHinge to grab it, then explode through hip and knee extension.\nPull the dumbbell high and punch under it as it rotates overhead.\nLock out the elbow with the dumbbell stacked over the shoulder.'),

  ('medicine_ball_slam',
   'Medicine Ball Slam',
   'An explosive overhead-to-floor throw with a medicine ball — full-body power output and a heavy metabolic hit.',
   E'Stand with feet shoulder-width, ball held overhead with arms extended.\nDrive the ball down hard into the floor in front of you, hinging the hips.\nLet the legs bend naturally and follow through with the whole body.\nCatch the rebound (or pick it up) and reset before the next rep.'),

  ('depth_jump',
   'Depth Jump',
   'A reactive jump performed by stepping off a low box and immediately rebounding straight upward — pure stretch-shortening.',
   E'Step (do not jump) off a 30–60 cm box.\nLand softly on the balls of the feet with knees soft.\nMinimize ground contact time — bounce up immediately.\nJump as high as possible on the rebound, arms swinging up.'),

  ('broad_jump',
   'Broad Jump',
   'A maximal forward jump from a standing start — trains horizontal power and posterior-chain triple extension.',
   E'Stand with feet shoulder-width, arms back in a loaded position.\nSwing the arms forward and drive the hips through explosively.\nReach the legs forward to maximize horizontal distance.\nLand soft with bent knees, absorbing the impact.'),

  ('lateral_box_jump',
   'Lateral Box Jump',
   'A box jump performed sideways onto the box — trains lateral power output and the stabilizers around the hip and ankle.',
   E'Stand sideways to a sturdy box at a height you can clear comfortably.\nDip into a quarter squat and swing the arms.\nJump laterally onto the box, landing soft on both feet.\nStep down (do not jump back) and reset for the next rep.'),

  ('single_leg_box_jump',
   'Single-Leg Box Jump',
   'A box jump performed on one leg — single-leg explosive triple extension with a stable two-foot landing.',
   E'Stand on one leg in front of a low, stable box.\nDip into a quarter squat with arms swinging back.\nDrive off the single leg and jump onto the box.\nLand soft on both feet, then step down to reset.'),

  ('snatch_grip_deadlift',
   'Snatch-Grip Deadlift',
   'A deadlift pulled with a snatch-wide grip — overloads the upper back and lats, and lengthens the bar path.',
   E'Set up over the bar with a wide snatch-grip.\nKeep the back tight and the chest up — hips will sit lower than a normal pull.\nDrive through the floor with the bar close to the body.\nLock out by squeezing the upper back hard at the top.'),

  ('deficit_deadlift',
   'Deficit Deadlift',
   'A deadlift pulled while standing on a 1–4 inch platform — adds bottom-end ROM and overloads the start of the pull.',
   E'Stand on a 2–10 cm platform with the bar over the mid-foot.\nKeep the back tight as you set up — the hips will sit lower than usual.\nDrive through the platform with the bar close to the body.\nFinish by squeezing the glutes hard at lockout.'),

  ('mixed_grip_deadlift',
   'Mixed-Grip Deadlift',
   'A deadlift held with one palm pronated and one supinated — locks the bar in for heavy pulls when grip would otherwise fail.',
   E'Grip the bar with one palm facing you and the other facing away.\nKeep both arms straight and tight to the lats.\nPull as a normal deadlift — drive through the floor with the bar close.\nAlternate which hand is supinated set to set to balance the stress.'),

  ('neutral_grip_pull_up',
   'Neutral-Grip Pull-Up',
   'A pull-up performed on parallel handles with palms facing each other — easier on the elbows and shoulders than wide-grip.',
   E'Grip parallel handles with palms facing each other.\nPull up until the chin clears the handles.\nLower under control to a full hang at the bottom.\nKeep the elbows tracking forward, not flared out.'),

  ('muscle_up',
   'Muscle-Up',
   'A high-skill bodyweight pull that transitions over the bar or rings into a dip — pull, then press, in one move.',
   E'Start in a dead hang with a false grip on bar or rings.\nPull explosively while leaning back to bring the chest to the bar.\nWhip the elbows around fast as the bar passes the chest.\nFinish with a full press to support, then lower with control.'),

  ('zercher_squat',
   'Zercher Squat',
   'A barbell squat with the bar held in the elbow crooks — brutal core demand and a more upright torso.',
   E'Cradle the bar in the crook of the elbows with hands clasped.\nKeep the chest up tall and the elbows held high.\nDescend to at least parallel with the torso staying upright.\nDrive up through the whole foot — the core has to fire hard.'),

  ('safety_bar_squat',
   'Safety Bar Squat',
   'A back squat performed with a cambered safety bar — easier on the shoulders and elbows while still loading the legs heavy.',
   E'Set the safety bar across the upper traps with handles in front.\nGrip the handles lightly — let the bar sit on the back.\nDescend to at least parallel, keeping the chest up.\nDrive up through the whole foot without letting the torso fold forward.'),

  ('paused_squat',
   'Paused Squat',
   'A back squat with a 1–3 second pause at the bottom — kills the stretch reflex and overloads the concentric drive.',
   E'Squat down to your usual depth and stop.\nHold the bottom for 1–3 seconds without losing tension.\nDrive up through the whole foot once the pause ends.\nKeep the chest up and the bar over the mid-foot throughout.'),

  ('pistol_squat',
   'Pistol Squat',
   'A single-leg squat to full depth with the free leg held forward — extreme balance, mobility, and unilateral quad demand.',
   E'Balance on one leg with the other leg held straight in front.\nSit straight down with the working knee tracking over the foot.\nDescend until the hamstring rests on the calf.\nDrive up through the whole foot, keeping the free leg from touching down.'),

  ('handstand_push_up',
   'Handstand Push-Up',
   'An overhead press performed inverted against a wall — extreme demand on the shoulders, triceps, and stabilizers.',
   E'Kick up to a handstand against a wall with hands shoulder-width.\nLower the head to the floor under control, elbows tracking forward.\nPress back to a full handstand without arching the lower back.\nKeep the core braced — no banana shape.'),

  ('archer_push_up',
   'Archer Push-Up',
   'A unilateral push-up where one arm bends and the other stays nearly straight to the side — a key step toward the one-arm push-up.',
   E'Set up wider than a normal push-up, hands well outside the shoulders.\nLower toward one hand while the other arm straightens to the side.\nKeep the core tight and the hips square — no rotation.\nPress back up and alternate sides each rep.'),

  ('ring_dip',
   'Ring Dip',
   'A bodyweight dip on gymnastic rings — the unstable handles add a serious stabilizer demand to the chest and triceps.',
   E'Set the rings at a height where your feet can clear the floor.\nStart in a support hold with arms locked and rings turned out.\nLower under control until the shoulders are below the elbows.\nPress back to the top and turn the rings out at lockout.'),

  ('paused_bench_press',
   'Paused Bench Press',
   'A barbell bench press with a 1–3 second pause on the chest — the powerlifting-spec lift, harder than touch-and-go.',
   E'Lower the bar to mid-chest under control with shoulder blades retracted.\nPause motionless on the chest for 1–3 seconds.\nPress up explosively without bouncing the bar off the chest.\nKeep the feet planted and the upper back tight throughout.'),

  ('atlas_stone',
   'Atlas Stone',
   'A strongman lift in which a heavy round stone is lifted from the floor to a platform — full posterior chain plus a chest cradle.',
   E'Straddle the stone with feet wider than shoulders.\nWrap the arms under the stone and tack it to the chest in the lap.\nDrive the hips through to extend the body and load the stone onto the platform.\nUse tacky on the forearms for grip — and warm the lower back well first.'),

  ('l_sit',
   'L-Sit',
   'A bodyweight isometric where you support yourself on the hands with the legs held straight and parallel to the floor.',
   E'Sit on the floor with hands flat next to the hips.\nPress down through the hands and lift the hips and legs off the floor.\nKeep the legs straight and parallel to the ground.\nHold for time without letting the feet sag toward the floor.'),

  ('hanging_windshield_wiper',
   'Hanging Windshield Wiper',
   'A hanging core rotational drill — legs sweep side to side under control while you hang from the bar.',
   E'Hang from the bar with hands shoulder-width.\nLift the legs straight up to about hip height (or higher).\nRotate the legs side to side like a windshield wiper.\nKeep the upper body still — only the hips and legs move.'),

  ('single_leg_glute_bridge_eccentric',
   'Single-Leg Glute Bridge (Eccentric)',
   'A single-leg glute bridge with a slow 3–5 second eccentric down — overload by tempo, not by load.',
   E'Lie on your back with one knee bent and the other leg straight.\nDrive through the heel to lift the hips into a bridge.\nLower the hips down over a slow 3–5 second count.\nKeep the hips level — do not let the working side dip.'),

  ('single_arm_landmine_row',
   'Single-Arm Landmine Row',
   'A unilateral row using the Landmine — the lever path adds anti-rotation work to the lats and mid-back.',
   E'Straddle the loaded end of the landmine in a staggered stance.\nGrip the bar with one hand near the sleeve.\nPull the bar to the hip, squeezing the lat at the top.\nKeep the hips and shoulders square — no torso rotation.'),

  ('kettlebell_clean',
   'Kettlebell Clean',
   'A sub-Olympic ballistic that swings the Kettlebell to the rack position at the shoulder — power without the barbell skill ceiling.',
   E'Hike the Kettlebell back between the legs.\nDrive the hips through and pull the bell up close to the body.\nGuide the bell around the wrist into the rack position — no banging.\nPause briefly in the rack before the next rep.'),

  ('kettlebell_high_pull',
   'Kettlebell High Pull',
   'A hip-driven pull that brings the Kettlebell to chest height — bridges the swing and the snatch.',
   E'Start in a swing setup with the Kettlebell between the legs.\nDrive the hips through hard.\nPull the Kettlebell up to chest height with the elbow leading.\nLet the bell descend back into the swing path under control.'),

  ('dumbbell_clean',
   'Dumbbell Clean',
   'A dumbbell ballistic clean to the shoulder — easier to learn than the barbell version and great for power circuits.',
   E'Set the dumbbell on the floor between the feet.\nHinge to grab it, then explode through hip and knee extension.\nPull the dumbbell up close to the body and rotate the elbow under fast.\nReceive the dumbbell on the shoulder in a quarter squat.'),

  ('larsen_press',
   'Larsen Press',
   'A bench press performed with the legs held off the floor — kills leg drive and overloads the upper-body push.',
   E'Lie back on the bench with the feet held in the air, knees bent.\nKeep the upper back tight and shoulder blades retracted.\nLower the bar to mid-chest with elbows at about 45 degrees.\nPress up under pure upper-body drive — no leg push.'),

  ('single_arm_landmine_press',
   'Single-Arm Landmine Press',
   'A one-arm overhead press using the Landmine — anti-rotation core demand alongside the shoulder and tricep work.',
   E'Stand in a staggered stance with the bar tip at one shoulder.\nPress the bar up and slightly across the body.\nResist the rotation — the core has to brace hard.\nLower the bar under control back to the shoulder.'),

  ('suitcase_carry',
   'Suitcase Carry',
   'A loaded carry with a single dumbbell at the side — pure anti-lateral-flexion core demand.',
   E'Pick up a heavy dumbbell on one side only.\nStand tall with shoulders level and the core braced.\nWalk a set distance without leaning toward the loaded side.\nSet the weight down with control and switch sides.'),

  ('belt_squat',
   'Belt Squat',
   'A machine squat loaded by a hip belt — heavy quad and glute work without spinal compression.',
   E'Strap the belt around the hips and stand on the platform.\nUnload the safeties and descend to at least parallel.\nDrive up through the whole foot, keeping the chest tall.\nUse the hand rails for balance only — not to push the weight.'),

  ('pendulum_squat',
   'Pendulum Squat',
   'A guided machine squat that travels in a fixed arc — quad-dominant with very low stabilizer demand.',
   E'Set the shoulder pads so the hips sit deep in the cradle.\nPlace the feet shoulder-width on the platform.\nDescend until the thighs pass parallel to the foot platform.\nDrive up through the whole foot to near full extension.'),

  ('glute_ham_raise',
   'Glute Ham Raise',
   'A posterior-chain compound on the GHR bench — combines knee flexion and hip extension into one curl.',
   E'Set the foot plate so the knees sit just behind the pad.\nLock the heels under the rollers with the feet flat.\nLower the body forward by extending the knees, keeping the hips straight.\nCurl back up by pulling the heels into the rollers — hamstrings drive the lift.'),

  ('cable_pullover',
   'Cable Pullover',
   'A standing or kneeling cable pullover that takes the lats through a long arc with constant tension.',
   E'Set a rope or straight bar on a high pulley.\nStep back and hinge slightly with arms held high.\nPull the cable down to the thighs in a wide arc, keeping the elbows locked.\nReturn under control with the lats stretching at the top.'),

  ('cable_overhead_extension',
   'Cable Overhead Extension',
   'An overhead tricep extension on the cable — long-head bias with constant tension through the full ROM.',
   E'Face away from a high pulley with a rope attached.\nHold the rope behind the head with elbows pointing up.\nExtend the elbows fully to lock out the triceps overhead.\nLower under control to a deep stretch behind the head.'),

  ('single_leg_calf_raise',
   'Single-Leg Calf Raise',
   'A bodyweight calf raise on one leg — overloads the calf without needing extra weight.',
   E'Stand on one foot on the edge of a step or plate.\nLet the heel drop below the step for a full stretch.\nRise up onto the ball of the foot as high as possible.\nPause briefly at the top before lowering with control.'),

  ('seated_dumbbell_calf_raise',
   'Seated Dumbbell Calf Raise',
   'A seated calf raise with dumbbells on the knees — isolates the soleus by removing the gastrocnemius from the lift.',
   E'Sit on a bench with the balls of the feet on a low platform.\nRest dumbbells on top of the thighs just above the knees.\nLower the heels for a full stretch.\nRise up onto the toes and pause before the next rep.'),

  ('fat_grip_curl',
   'Fat-Grip Curl',
   'A dumbbell curl performed with thick-grip attachments — taxes the forearms and grip alongside the biceps.',
   E'Wrap Fat Grips around standard dumbbell handles.\nCurl as a normal dumbbell curl, palms up.\nKeep the elbows pinned to the sides — no swinging.\nLower under control all the way to extension.'),

  ('copenhagen_plank',
   'Copenhagen Plank',
   'A side plank with the top leg supported on a bench — punishes the adductors of the down leg.',
   E'Lie on one side with the top leg on a bench, ankle on the bench surface.\nSupport the upper body on the elbow under the shoulder.\nLift the hips so the body forms a straight line, supported by the bench-side ankle.\nHold for time without letting the hips drop.'),

  ('assault_bike',
   'Assault Bike',
   'An air-resistance fan bike — both arms and legs drive against air resistance for a brutal full-body conditioning hit.',
   E'Adjust the seat so the knees have a slight bend at full extension.\nSet the feet on the pedals and the hands on the handles.\nPush and pull with arms and legs at the same time.\nTo go harder, push faster — the resistance scales with effort.'),

  ('sled_push',
   'Sled Push',
   'Pushing a weighted sled across the floor — grinding leg drive and full-body conditioning in one.',
   E'Grip the sled handles low with the body angled forward.\nDrive each foot hard into the floor, alternating fast.\nKeep the back flat and the hips down — no shuffling.\nUse short, powerful steps over the marked distance.'),

  ('sled_drag',
   'Sled Drag',
   'Dragging a weighted sled with straps — versatile full-body conditioning, low impact and forgiving on the joints.',
   E'Attach straps from the sled to a harness or hand-held handles.\nLean into the resistance with the body angled forward.\nDrive the legs in long, powerful steps.\nFor backward drag, stay low with the chest tall and pull through the heels.')

) AS v(slug, name, description, form_tips)
JOIN exercises e ON e.slug = v.slug AND e.is_default = true;

-- ============================================================================
-- PART C — INSERT INTO exercise_translations (pt)
--
-- Same shape as PART B with pt-BR translations. Eponyms preserved English per
-- docs/pt-glossary.md §2 (Power Clean, Hang Clean, Power Snatch, Hang Snatch,
-- Snatch, Clean and Jerk, Push Jerk, Split Jerk, Box Jump, Kettlebell, Sled,
-- Landmine, Pistol Squat, Muscle-Up, L-Sit, Atlas Stone, Larsen Press,
-- Copenhagen, Suitcase Carry, Zercher, Safety Bar, Belt Squat, Pendulum Squat,
-- Glute Ham, Medicine Ball Slam, Assault Bike, Fat Grip).
-- ============================================================================

INSERT INTO exercise_translations (exercise_id, locale, name, description, form_tips)
SELECT e.id, 'pt', v.name, v.description, v.form_tips
FROM (VALUES

  ('power_clean',
   'Power Clean',
   'Puxada olímpica do chão até o apoio em meio agachamento na posição frontal — extensão tripla explosiva e rack rápido.',
   E'Posicione-se sobre a barra, quadril entre joelhos e ombros, com a coluna travada antes de subir.\nPasse a barra do joelho e exploda em extensão total de quadril e joelho.\nPuxe-se PARA BAIXO da barra — não tente subir só com os braços.\nReceba alto (acima da paralela) com cotovelos rápidos e à frente no rack.'),

  ('hang_clean',
   'Hang Clean',
   'Power Clean iniciado a partir do hang (acima do joelho) — treina a segunda puxada e a inversão sem a puxada do chão.',
   E'Comece em pé com a barra em hang, logo acima do joelho.\nFlexione o quadril com a barra colada e exploda em extensão tripla.\nPuxe-se rápido para baixo da barra — não suba como uma rosca.\nReceba em meio agachamento no rack frontal com cotovelos à frente.'),

  ('power_snatch',
   'Power Snatch',
   'Snatch olímpico recebido acima da paralela — a barra vai do chão até overhead em um só movimento explosivo.',
   E'Posicione-se com pegada aberta sobre a barra, costas retas e peito alto.\nEmpurre o chão com a barra colada ao corpo.\nProjete a barra overhead com agressividade enquanto desce em meio agachamento.\nTrave com os bíceps junto às orelhas e a barra sobre o meio do pé.'),

  ('hang_snatch',
   'Hang Snatch',
   'Snatch iniciado a partir do hang (acima do joelho) — treina a segunda puxada e a inversão sem a puxada do chão.',
   E'Fique em pé com a barra em hang, pegada aberta na altura da coxa.\nFlexione o quadril com a barra colada e exploda em extensão tripla.\nProjete a barra overhead e desça rápido em meio agachamento.\nTrave os cotovelos com a barra alinhada sobre o meio do pé.'),

  ('clean_and_jerk',
   'Clean and Jerk',
   'Levantamento olímpico completo em duas partes — Clean da barra até os ombros e depois Jerk overhead. O lift mais pesado de qualquer esporte.',
   E'Puxe a barra do chão e receba no rack frontal, igual a um Clean.\nFique totalmente em pé e respire no rack antes do Jerk.\nFlexione e empurre com as pernas, projetando-se sob a barra.\nTrave com os cotovelos firmes e a barra alinhada sobre o meio do pé.'),

  ('push_jerk',
   'Push Jerk',
   'Empurrada overhead que usa o impulso das pernas para lançar a barra, recebida em meio agachamento sem nova flexão.',
   E'Comece com a barra firme no rack frontal, cotovelos altos.\nFlexione direto para baixo com o peito ereto — sem inclinar à frente.\nEmpurre forte com as pernas e projete a barra acima da cabeça.\nReceba em meio agachamento com cotovelos travados, depois fique em pé.'),

  ('split_jerk',
   'Split Jerk',
   'Empurrada overhead recebida em base afundada (um pé à frente, outro atrás), abrindo mais espaço para receber a barra do que o Push Jerk.',
   E'Comece com a barra firme no rack frontal, cotovelos altos.\nFlexione direto para baixo e empurre as pernas com força.\nAfunde os pés sob a barra — canela da frente vertical, perna de trás reta.\nTrave a barra acima da cabeça e depois recolha o pé de trás para se recuperar.'),

  ('kettlebell_snatch',
   'Kettlebell Snatch',
   'Puxada do Kettlebell de entre as pernas até o lockout overhead em um único movimento — potência total do corpo e pegada.',
   E'Lance o Kettlebell entre as pernas com uma das mãos.\nEmpurre o quadril à frente e puxe o Kettlebell alto e colado.\nGire o punho na ponta para o Kettlebell pousar no dorso da mão — sem bater.\nTrave o cotovelo overhead com o bíceps junto à orelha.'),

  ('dumbbell_snatch',
   'Dumbbell Snatch',
   'Puxada do halter do chão até o lockout overhead em um só movimento — mesmo padrão do Kettlebell Snatch com outro implemento.',
   E'Posicione o halter no chão entre os pés.\nFlexione o quadril para pegá-lo e exploda em extensão de quadril e joelho.\nPuxe o halter alto e empurre-se sob ele enquanto gira overhead.\nTrave o cotovelo com o halter alinhado sobre o ombro.'),

  ('medicine_ball_slam',
   'Medicine Ball Slam',
   'Arremesso explosivo da bola medicinal de cima para o chão — potência total do corpo e forte estímulo metabólico.',
   E'Fique em pé na largura dos ombros, com a bola overhead e os braços estendidos.\nLance a bola com força no chão à sua frente, flexionando o quadril.\nDeixe os joelhos dobrarem naturalmente e acompanhe com o corpo inteiro.\nPegue o rebote (ou apanhe a bola) e reposicione antes da próxima repetição.'),

  ('depth_jump',
   'Depth Jump',
   'Salto reativo em que você desce de uma caixa baixa e quica imediatamente para cima — pliometria pura.',
   E'Desça (não pule) de uma caixa de 30 a 60 cm.\nAterrisse macio na ponta dos pés com os joelhos suaves.\nMinimize o tempo de contato com o chão — quique imediatamente para cima.\nSalte o mais alto possível no rebote, com os braços ajudando.'),

  ('broad_jump',
   'Broad Jump',
   'Salto horizontal máximo a partir de posição parada — treina potência horizontal e extensão tripla da cadeia posterior.',
   E'Fique em pé na largura dos ombros com os braços para trás em posição carregada.\nLance os braços à frente e empurre o quadril com explosão.\nProjete as pernas à frente para maximizar a distância.\nAterrisse macio com os joelhos flexionados para absorver o impacto.'),

  ('lateral_box_jump',
   'Lateral Box Jump',
   'Box Jump em deslocamento lateral — treina potência lateral e os estabilizadores ao redor de quadril e tornozelo.',
   E'Fique de lado para uma caixa firme em altura confortável.\nFaça um agachamento curto e balance os braços.\nSalte lateralmente sobre a caixa, aterrissando macio nos dois pés.\nDesça da caixa (não salte para trás) e reposicione para a próxima rep.'),

  ('single_leg_box_jump',
   'Single-Leg Box Jump',
   'Box Jump em uma perna só — extensão tripla explosiva unilateral com aterrissagem estável nos dois pés.',
   E'Fique em uma perna em frente a uma caixa baixa e firme.\nFaça um agachamento curto com os braços para trás.\nEmpurre a perna de apoio e salte sobre a caixa.\nAterrisse macio nos dois pés e desça da caixa para reposicionar.'),

  ('snatch_grip_deadlift',
   'Snatch-Grip Deadlift',
   'Levantamento terra com pegada larga (snatch) — sobrecarrega trapézio médio e dorsais, e alonga a trajetória da barra.',
   E'Posicione-se sobre a barra com pegada larga (Snatch Grip Deadlift).\nMantenha as costas travadas e o peito alto — o quadril fica mais baixo que no terra normal.\nEmpurre o chão com a barra colada ao corpo.\nFinalize contraindo o trapézio médio com força no topo.'),

  ('deficit_deadlift',
   'Deficit Deadlift',
   'Levantamento terra com os pés sobre uma plataforma baixa — aumenta a amplitude e endurece o início da puxada.',
   E'Fique sobre uma plataforma de 2 a 10 cm com a barra sobre o meio do pé.\nTrave as costas no setup — o quadril fica mais baixo que o normal.\nEmpurre a plataforma com a barra colada ao corpo.\nFinalize contraindo os glúteos com força no lockout.'),

  ('mixed_grip_deadlift',
   'Mixed-Grip Deadlift',
   'Levantamento terra com uma mão pronada e outra supinada — trava a barra em puxadas pesadas que escapariam da pegada normal.',
   E'Segure a barra com uma palma voltada para você e a outra para frente.\nMantenha os dois braços retos e colados ao corpo.\nPuxe como um terra normal — empurre o chão com a barra colada.\nAlterne qual mão fica supinada entre séries para equilibrar a carga.'),

  ('neutral_grip_pull_up',
   'Neutral-Grip Pull-Up',
   'Barra fixa em alças paralelas com as palmas voltadas uma para a outra — mais amigável aos cotovelos e ombros que a pegada aberta.',
   E'Segure alças paralelas com as palmas voltadas uma para a outra.\nSuba até o queixo passar das alças.\nDesça com controle até a extensão total embaixo.\nMantenha os cotovelos apontados à frente, sem abrir.'),

  ('muscle_up',
   'Muscle-Up',
   'Movimento avançado de peso do corpo que combina barra fixa explosiva e mergulho — puxe e depois empurre em um só movimento.',
   E'Comece pendurado com pegada falsa na barra ou nas argolas.\nPuxe explosivamente inclinando-se para trás para levar o peito à barra.\nGire os cotovelos rapidamente para a frente quando a barra passar do peito.\nTermine com um empurrar completo até o apoio e desça com controle.'),

  ('zercher_squat',
   'Zercher Squat',
   'Agachamento com a barra apoiada na dobra dos cotovelos — exigência brutal de core e tronco mais ereto.',
   E'Apoie a barra na dobra dos cotovelos com as mãos entrelaçadas.\nMantenha o peito alto e os cotovelos elevados.\nDesça pelo menos até a paralela com o tronco ereto.\nSuba pelo pé inteiro — o core precisa contrair com força.'),

  ('safety_bar_squat',
   'Safety Bar Squat',
   'Back squat com a Safety Bar (barra cambada) — poupa ombros e cotovelos sem perder carga nas pernas.',
   E'Posicione a Safety Bar sobre o trapézio superior com as alças à frente.\nSegure as alças com leveza — a barra fica apoiada nas costas.\nDesça pelo menos até a paralela, com o peito alto.\nSuba pelo pé inteiro sem deixar o tronco cair à frente.'),

  ('paused_squat',
   'Paused Squat',
   'Back squat com pausa de 1 a 3 segundos no fundo — mata o reflexo de estiramento e sobrecarrega a fase concêntrica.',
   E'Agache até sua profundidade habitual e pare.\nSegure no fundo por 1 a 3 segundos sem perder a tensão.\nSuba pelo pé inteiro assim que a pausa terminar.\nMantenha o peito alto e a barra sobre o meio do pé durante todo o movimento.'),

  ('pistol_squat',
   'Pistol Squat',
   'Agachamento unilateral até a profundidade total com a perna livre estendida à frente — equilíbrio, mobilidade e quadríceps no limite.',
   E'Equilibre-se em uma perna com a outra esticada à frente.\nSente direto para baixo com o joelho de trabalho alinhado com o pé.\nDesça até o posterior encostar na panturrilha.\nSuba pelo pé inteiro, sem deixar a perna livre tocar o chão.'),

  ('handstand_push_up',
   'Handstand Push-Up',
   'Desenvolvimento invertido contra a parede em parada de mão — exigência extrema de ombros, tríceps e estabilizadores.',
   E'Suba em parada de mão contra a parede com as mãos na largura dos ombros.\nDesça a cabeça até o chão com controle, cotovelos à frente.\nEmpurre de volta à parada de mão sem arquear a lombar.\nMantenha o core travado — sem virar banana.'),

  ('archer_push_up',
   'Archer Push-Up',
   'Flexão unilateral em que um braço dobra e o outro fica quase reto ao lado — um passo até a flexão de um braço só.',
   E'Posicione as mãos bem mais abertas que em uma flexão normal.\nDesça em direção a uma das mãos enquanto o outro braço estica para o lado.\nMantenha o core firme e o quadril alinhado — sem rotacionar.\nEmpurre para cima e alterne os lados a cada repetição.'),

  ('ring_dip',
   'Ring Dip',
   'Mergulho nas argolas, em que a instabilidade soma trabalho de estabilização ao peito e ao tríceps.',
   E'Ajuste as argolas a uma altura em que os pés saiam do chão.\nComece em apoio com os braços travados e as argolas viradas para fora.\nDesça com controle até os ombros ficarem abaixo dos cotovelos.\nEmpurre de volta ao topo e gire as argolas para fora no lockout.'),

  ('paused_bench_press',
   'Paused Bench Press',
   'Supino reto com pausa de 1 a 3 segundos no peito — versão de powerlifting, mais difícil que o toca-e-volta.',
   E'Desça a barra até o meio do peito com controle e escápulas contraídas.\nFaça pausa imóvel sobre o peito por 1 a 3 segundos.\nEmpurre para cima com explosão, sem usar o ricochete do peito.\nMantenha os pés plantados e o trapézio firme durante todo o movimento.'),

  ('atlas_stone',
   'Atlas Stone',
   'Lift de strongman em que se ergue uma pedra pesada do chão até uma plataforma, usando cadeia posterior e o apoio no peito.',
   E'Posicione-se sobre a pedra com os pés mais abertos que os ombros.\nEncaixe os braços sob a pedra e prenda-a no peito sobre o colo.\nEmpurre o quadril à frente para estender o corpo e levar a pedra à plataforma.\nUse tacky nos antebraços para pegada — e aqueça bem a lombar antes.'),

  ('l_sit',
   'L-Sit',
   'Isometria de peso do corpo em que você se sustenta nas mãos com as pernas estendidas e paralelas ao chão.',
   E'Sente no chão com as mãos espalmadas ao lado do quadril.\nEmpurre o chão com as mãos e suspenda quadril e pernas.\nMantenha as pernas retas e paralelas ao chão.\nSegure pelo tempo definido sem deixar os pés caírem em direção ao chão.'),

  ('hanging_windshield_wiper',
   'Hanging Windshield Wiper',
   'Drill rotacional de core suspenso na barra fixa — as pernas vão de um lado para o outro sob controle.',
   E'Pendure-se na barra com as mãos na largura dos ombros.\nLevante as pernas estendidas até a altura do quadril (ou mais alto).\nGire as pernas de um lado para o outro como um limpador de para-brisa.\nMantenha o tronco quieto — só quadril e pernas se movem.'),

  ('single_leg_glute_bridge_eccentric',
   'Single-Leg Glute Bridge (Eccentric)',
   'Elevação de quadril unilateral com fase excêntrica lenta de 3 a 5 segundos — sobrecarga pelo tempo, não pela carga.',
   E'Deite de costas com um joelho flexionado e a outra perna estendida.\nEmpurre pelo calcanhar para subir o quadril em ponte.\nDesça o quadril contando devagar de 3 a 5 segundos.\nMantenha o quadril alinhado — sem deixar o lado de trabalho cair.'),

  ('single_arm_landmine_row',
   'Single-Arm Landmine Row',
   'Remada unilateral no Landmine — o arco do braço alavanca soma trabalho anti-rotacional para os dorsais e meio das costas.',
   E'Posicione-se sobre a ponta carregada do Landmine em base escalonada.\nSegure a barra com uma mão perto da manga.\nPuxe a barra até o quadril, contraindo o dorsal no topo.\nMantenha quadril e ombros alinhados — sem rotacionar o tronco.'),

  ('kettlebell_clean',
   'Kettlebell Clean',
   'Movimento balístico sub-olímpico que leva o Kettlebell até a posição de rack no ombro — potência sem o teto técnico da barra.',
   E'Lance o Kettlebell para trás entre as pernas.\nEmpurre o quadril à frente e puxe o Kettlebell colado ao corpo.\nGuie o Kettlebell ao redor do punho até a posição de rack — sem batidas.\nFaça uma pausa breve no rack antes da próxima repetição.'),

  ('kettlebell_high_pull',
   'Kettlebell High Pull',
   'Puxada com impulso de quadril que leva o Kettlebell até a altura do peito — ponte entre o swing e o snatch.',
   E'Comece em postura de swing com o Kettlebell entre as pernas.\nEmpurre o quadril à frente com força.\nPuxe o Kettlebell até a altura do peito liderando com o cotovelo.\nDeixe o Kettlebell descer de volta para a trajetória do swing com controle.'),

  ('dumbbell_clean',
   'Dumbbell Clean',
   'Clean balístico com halter até o ombro — mais fácil de aprender que a versão de barra e ótimo para circuitos de potência.',
   E'Posicione o halter no chão entre os pés.\nFlexione o quadril para pegá-lo e exploda em extensão de quadril e joelho.\nPuxe o halter colado ao corpo e gire o cotovelo para baixo rapidamente.\nReceba o halter no ombro em meio agachamento.'),

  ('larsen_press',
   'Larsen Press',
   'Variação do supino com as pernas elevadas — elimina o impulso das pernas e sobrecarrega o empurrar do tronco superior.',
   E'Deite no banco com os pés no ar e os joelhos flexionados.\nMantenha o trapézio firme e as escápulas contraídas.\nDesça a barra até o meio do peito com cotovelos a cerca de 45 graus.\nEmpurre usando só o tronco superior — sem impulso das pernas.'),

  ('single_arm_landmine_press',
   'Single-Arm Landmine Press',
   'Landmine Press unilateral — soma exigência anti-rotacional do core ao trabalho de ombro e tríceps.',
   E'Fique em base escalonada com a ponta da barra em um dos ombros.\nEmpurre a barra para cima e levemente cruzando o corpo.\nResista à rotação — o core precisa travar com força.\nDesça a barra com controle de volta ao ombro.'),

  ('suitcase_carry',
   'Suitcase Carry',
   'Caminhada carregada com um halter só de um lado — pura exigência anti-flexão lateral do core.',
   E'Pegue um halter pesado em um dos lados.\nFique em pé com os ombros alinhados e o core travado.\nCaminhe uma distância definida sem inclinar para o lado carregado.\nApoie o peso com controle e troque de lado.'),

  ('belt_squat',
   'Belt Squat',
   'Agachamento na máquina carregado por cinturão no quadril — trabalho pesado de pernas sem compressão da coluna.',
   E'Prenda o cinturão no quadril e suba na plataforma.\nDestrave os apoios e desça pelo menos até a paralela.\nSuba pelo pé inteiro mantendo o peito alto.\nUse as alças apenas para equilíbrio — não para empurrar a carga.'),

  ('pendulum_squat',
   'Pendulum Squat',
   'Agachamento guiado em arco fixo na máquina — dominante de quadríceps e baixa exigência de estabilizadores.',
   E'Ajuste as almofadas dos ombros para o quadril ficar fundo no encaixe.\nPosicione os pés na largura dos ombros na plataforma.\nDesça até as coxas passarem da paralela com a plataforma.\nSuba pelo pé inteiro até quase a extensão total.'),

  ('glute_ham_raise',
   'Glute Ham Raise',
   'Movimento posterior na máquina GHR (Glute Ham) — une flexão de joelho e extensão de quadril em uma só repetição.',
   E'Ajuste a plataforma para os joelhos ficarem logo atrás da almofada.\nTrave os calcanhares sob os rolos com os pés apoiados.\nDesça o corpo à frente estendendo os joelhos, com o quadril alinhado.\nVolte puxando os calcanhares contra os rolos — os posteriores fazem o trabalho.'),

  ('cable_pullover',
   'Cable Pullover',
   'Pullover no cabo, em pé ou ajoelhado, que leva os dorsais por um arco amplo com tensão constante.',
   E'Acople uma corda ou barra reta na polia alta.\nDê um passo para trás e incline o quadril levemente com os braços altos.\nPuxe o cabo até as coxas em arco amplo, com os cotovelos travados.\nVolte com controle deixando os dorsais alongarem no topo.'),

  ('cable_overhead_extension',
   'Cable Overhead Extension',
   'Extensão de tríceps no cabo com os braços acima da cabeça — viés para a cabeça longa com tensão constante em toda a amplitude.',
   E'Fique de costas para a polia alta com uma corda acoplada.\nSegure a corda atrás da cabeça com os cotovelos apontados para cima.\nEstenda os cotovelos por completo para travar o tríceps overhead.\nDesça com controle até um bom alongamento atrás da cabeça.'),

  ('single_leg_calf_raise',
   'Single-Leg Calf Raise',
   'Elevação de panturrilha em uma perna só, com peso do corpo — sobrecarrega a panturrilha sem precisar de carga extra.',
   E'Fique em uma perna na beirada de um degrau ou anilha.\nDeixe o calcanhar cair abaixo do degrau para um alongamento total.\nSuba na ponta do pé o mais alto possível.\nPause brevemente no topo antes de descer com controle.'),

  ('seated_dumbbell_calf_raise',
   'Seated Dumbbell Calf Raise',
   'Panturrilha sentado com halteres apoiados nas coxas — isola o sóleo ao retirar o gastrocnêmio do movimento.',
   E'Sente em um banco com a sola dos pés em uma plataforma baixa.\nApoie halteres em cima das coxas, logo acima dos joelhos.\nDesça os calcanhares para um bom alongamento.\nSuba na ponta dos pés e pause antes da próxima repetição.'),

  ('fat_grip_curl',
   'Fat-Grip Curl',
   'Rosca com halteres usando Fat Grips — soma exigência de antebraço e pegada ao trabalho dos bíceps.',
   E'Encaixe os Fat Grips sobre as alças dos halteres comuns.\nFaça a rosca como uma rosca direta com halteres, palmas para cima.\nMantenha os cotovelos colados ao corpo — sem balanço.\nDesça com controle até a extensão total.'),

  ('copenhagen_plank',
   'Copenhagen Plank',
   'Prancha lateral com a perna de cima apoiada em um banco — sobrecarrega os adutores da perna de baixo.',
   E'Deite de lado com a perna de cima sobre um banco, tornozelo apoiado.\nApoie o tronco no cotovelo embaixo do ombro.\nSuba o quadril para o corpo formar uma linha reta, sustentado pelo tornozelo no banco.\nSegure pelo tempo definido sem deixar o quadril cair.'),

  ('assault_bike',
   'Assault Bike',
   'Bicicleta de resistência ao ar — braços e pernas empurram contra um ventilador, em um condicionamento total brutal.',
   E'Ajuste o banco para os joelhos terem leve flexão na extensão total.\nApoie os pés nos pedais e as mãos nas alças.\nEmpurre e puxe com braços e pernas ao mesmo tempo.\nPara aumentar a intensidade, pedale mais rápido — a resistência sobe com o esforço.'),

  ('sled_push',
   'Sled Push',
   'Empurrada do trenó com carga pelo chão — trabalho intenso de pernas e condicionamento total.',
   E'Segure as alças do trenó embaixo com o corpo inclinado à frente.\nEmpurre cada pé com força no chão, alternando rápido.\nMantenha as costas retas e o quadril baixo — sem arrastar os pés.\nUse passos curtos e potentes pela distância marcada.'),

  ('sled_drag',
   'Sled Drag',
   'Puxada do trenó com alças — condicionamento total versátil, de baixo impacto e fácil para as articulações.',
   E'Prenda alças do trenó em um cinto ou em pegadores de mão.\nIncline-se contra a resistência com o corpo angulado à frente.\nDê passos longos e potentes com as pernas.\nPara puxar de costas, fique baixo com o peito alto e empurre pelos calcanhares.')

) AS v(slug, name, description, form_tips)
JOIN exercises e ON e.slug = v.slug AND e.is_default = true;

-- ============================================================================
-- PART D — Sanity asserts
--
-- Defense in depth — the per-row CHECK constraints already enforce
-- xp_attribution sum-to-1.0 (00040) and difficulty_mult range (00053). These
-- DO-blocks add migration-level invariants:
--   D1. Every Phase 24b slug landed in `exercises` (catches typos, dropped
--       rows). 50 inserts → expect 50 rows. The ON CONFLICT path means a
--       duplicate slug shipped in an earlier migration would silently no-op,
--       so this assert verifies row count, not just absence of error.
--   D2. Every Phase 24b slug has both `'en'` and `'pt'` translation rows
--       (the (exercise_id, locale) PK prevents dupes; this counts pairs).
--   D3. No Phase 24b slug stuck at literal difficulty_mult = 1.0 (sentinel
--       from 00053; 1.0 is unreachable by any valid tier+sec combination,
--       so a row at 1.0 is provably an unmapped curation gap).
-- ============================================================================

DO $$
DECLARE
  v_phase24b_slugs text[] := ARRAY[
    'power_clean', 'hang_clean', 'power_snatch', 'hang_snatch',
    'clean_and_jerk', 'push_jerk', 'split_jerk', 'kettlebell_snatch',
    'dumbbell_snatch', 'medicine_ball_slam', 'depth_jump', 'broad_jump',
    'lateral_box_jump', 'single_leg_box_jump',
    'snatch_grip_deadlift', 'deficit_deadlift', 'mixed_grip_deadlift',
    'neutral_grip_pull_up', 'muscle_up', 'zercher_squat', 'safety_bar_squat',
    'paused_squat', 'pistol_squat', 'handstand_push_up', 'archer_push_up',
    'ring_dip', 'paused_bench_press', 'atlas_stone', 'l_sit',
    'hanging_windshield_wiper', 'single_leg_glute_bridge_eccentric',
    'single_arm_landmine_row', 'kettlebell_clean', 'kettlebell_high_pull',
    'dumbbell_clean', 'larsen_press', 'single_arm_landmine_press',
    'suitcase_carry',
    'belt_squat', 'pendulum_squat', 'glute_ham_raise', 'cable_pullover',
    'cable_overhead_extension',
    'single_leg_calf_raise', 'seated_dumbbell_calf_raise', 'fat_grip_curl',
    'copenhagen_plank', 'assault_bike', 'sled_push', 'sled_drag'
  ];
  v_count       int;
  v_missing     text;
BEGIN
  -- D1: 50 rows present in exercises.
  SELECT count(*) INTO v_count
  FROM public.exercises
  WHERE is_default = true
    AND deleted_at IS NULL
    AND slug = ANY(v_phase24b_slugs);

  IF v_count <> 50 THEN
    SELECT string_agg(s, ', ' ORDER BY s) INTO v_missing
    FROM unnest(v_phase24b_slugs) AS s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.exercises e
      WHERE e.slug = s AND e.is_default = true AND e.deleted_at IS NULL
    );
    RAISE EXCEPTION 'Phase 24b D1 invariant: expected 50 default rows, got % (missing: %).',
      v_count, COALESCE(v_missing, '(none — duplicate slug ate the insert)');
  END IF;

  -- D2: every slug has both en + pt translations (50 × 2 = 100 rows).
  SELECT count(*) INTO v_count
  FROM public.exercise_translations t
  JOIN public.exercises e ON e.id = t.exercise_id
  WHERE e.slug = ANY(v_phase24b_slugs)
    AND e.is_default = true
    AND t.locale IN ('en', 'pt');

  IF v_count <> 100 THEN
    SELECT string_agg(s || ':' || loc, ', ' ORDER BY s, loc) INTO v_missing
    FROM unnest(v_phase24b_slugs) AS s
    CROSS JOIN unnest(ARRAY['en', 'pt']::text[]) AS loc
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.exercise_translations t
      JOIN public.exercises e ON e.id = t.exercise_id
      WHERE e.slug = s AND e.is_default = true AND t.locale = loc
    );
    RAISE EXCEPTION 'Phase 24b D2 invariant: expected 100 (50 slugs × 2 locales) translation rows, got % (missing: %).',
      v_count, COALESCE(v_missing, '(unknown — duplicate (exercise_id, locale))');
  END IF;

  -- D3: no Phase 24b slug stuck at literal 1.0 (00053 sentinel).
  SELECT count(*), string_agg(slug, ', ' ORDER BY slug)
    INTO v_count, v_missing
  FROM public.exercises
  WHERE is_default = true
    AND difficulty_mult = 1.0
    AND slug = ANY(v_phase24b_slugs);

  IF v_count > 0 THEN
    RAISE EXCEPTION 'Phase 24b D3 invariant: % new defaults stuck at literal 1.0 (sample: %) — curation gap.',
      v_count, v_missing;
  END IF;
END
$$;

COMMIT;

-- Reload PostgREST schema cache so the new rows become visible to the API
-- layer immediately. The schema itself didn't change (only data inserts), but
-- this is harmless and matches the 00053 epilogue convention.
NOTIFY pgrst, 'reload schema';
