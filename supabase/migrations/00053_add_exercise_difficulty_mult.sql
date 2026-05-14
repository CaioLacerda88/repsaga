-- =============================================================================
-- Phase 24a — Exercise difficulty multiplier
-- Migration: 00053_add_exercise_difficulty_mult
--
-- Adds exercises.difficulty_mult (numeric 0.85–1.25) and curates every
-- is_default = true exercise against the framework documented in
-- docs/xp-difficulty-framework.md.
--
-- Forward-only: xp_events.payload snapshots difficulty_mult at write time;
-- past events are NOT replayed. Phase D (record_set_xp / record_session_xp_batch
-- update) will start consuming this column on next-write.
--
-- Tier framework (docs/xp-difficulty-framework.md §2):
--   T1 (1.25) Olympic / ballistic            — triple extension, peak power
--   T2 (1.15) Foundational compound          — multi-joint, axial load
--   T3 (1.05) Standard compound              — multi-joint, partial support
--   T4 (0.95) Machine compound / cable       — fixed path, low stabilizer
--   T5 (0.85) Single-joint isolation         — minimal coordination
--
-- Composite formula (§6):
--   difficulty_mult = clamp(
--     tier_mult + min(secondary_count, 3) × 0.02,
--     0.85, 1.25
--   )
--
-- Secondary count source: jsonb_object_keys(xp_attribution) − 1 (i.e. number
-- of body parts the exercise engages beyond its primary). The
-- exercises.secondary_muscle_groups column was added in 00040 but never
-- populated for default rows ([] default), so xp_attribution — already curated
-- thoughtfully in 00040 §14 — is the more honest proxy for "how many body
-- parts this movement recruits", which is exactly what the framework's
-- secondary-muscle bump measures (§5).
--
-- Each UPDATE row carries an inline `-- T<N> + <sec> sec → <value>` comment
-- so future audits can reverse-engineer the assignment without re-deriving.
-- Where the assignment is a judgment call (no exact §3 analog), the comment
-- names the closest analog used.
--
-- See docs/xp-difficulty-framework.md §3 for tier-by-name lookup.
-- See PROJECT.md §3 → Phase 24a for the rollout plan.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Column with safe default for user-created exercises.
--    The DEFAULT 1.0 is intentional: user-created rows ship without curation
--    (UX surface to set difficulty is a deferred 24-series item) and the
--    neutral 1.0 is a defensible placeholder. The DO-block at step 4 verifies
--    no is_default = true row is left at this default.
-- ---------------------------------------------------------------------------

ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS difficulty_mult numeric(4,2) NOT NULL DEFAULT 1.0;

-- ---------------------------------------------------------------------------
-- 2. Per-slug curation for every is_default = true exercise.
--    Comments use the form: -- T<N> + <sec> sec → <value>
--    Judgment calls reference the closest §3 analog by name.
-- ---------------------------------------------------------------------------

-- ===== CHEST (18) ==========================================================
-- Free-weight pressing — T3 by §3 ("barbell bench press", "dumbbell bench press").
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'barbell_bench_press';          -- T3 + 2 sec → 1.09 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'incline_barbell_bench_press';  -- T3 + 2 sec → 1.09 (analog: barbell bench)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'decline_barbell_bench_press';  -- T3 + 2 sec → 1.09 (analog: barbell bench)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'dumbbell_bench_press';         -- T3 + 2 sec → 1.09 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'incline_dumbbell_press';       -- T3 + 2 sec → 1.09 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'decline_dumbbell_press';       -- T3 + 2 sec → 1.09 (analog: dumbbell bench)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'landmine_press';               -- T3 + 3 sec → 1.11 (analog: standing dumbbell press, supported)
-- Bodyweight push-ups — T3 by §3 ("push-up"). Bodyweight load handled in 24c.
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'push_up';                      -- T3 + 3 sec → 1.11 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'wide_push_up';                 -- T3 + 3 sec → 1.11 (analog: push-up)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'incline_push_up';              -- T3 + 3 sec → 1.11 (analog: push-up, easier mechanically; same tier)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'decline_push_up';              -- T3 + 3 sec → 1.11 (analog: push-up)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'diamond_push_up';              -- T3 + 3 sec → 1.11 (analog: push-up; tricep emphasis but multi-joint)
-- Cable / machine multi-joint chest — T4 by §3 ("chest press machine", "cable fly when multi-joint").
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'machine_chest_press';          -- T4 + 2 sec → 0.99 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'cable_chest_press';            -- T4 + 2 sec → 0.99 (analog: chest press machine)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'cable_crossover';              -- T4 + 2 sec → 0.99 (§3 cable fly multi-joint)
-- Fly-pattern isolation — T5 (single-joint pec movement).
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'dumbbell_fly';                 -- T5 + 2 sec → 0.89 (analog: rear delt fly, single-joint)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'incline_dumbbell_fly';         -- T5 + 2 sec → 0.89 (analog: dumbbell fly)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'pec_deck';                     -- T5 + 2 sec → 0.89 (analog: rear delt fly machine)

-- ===== BACK (23) ===========================================================
-- T2 foundational pulls (§3: deadlift, sumo deadlift, barbell row, pendlay row).
UPDATE public.exercises SET difficulty_mult = 1.21 WHERE slug = 'deadlift';                     -- T2 + 3 sec → 1.21 (§3 conventional)
UPDATE public.exercises SET difficulty_mult = 1.21 WHERE slug = 'sumo_deadlift';                -- T2 + 3 sec → 1.21 (§3 named; non_primary_keys = 3)
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'barbell_bent_over_row';        -- T2 + 2 sec → 1.19 (§3 barbell row)
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'pendlay_row';                  -- T2 + 2 sec → 1.19 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 't_bar_row';                    -- T2 + 2 sec → 1.19 (analog: barbell row, partial-support but axial load)
UPDATE public.exercises SET difficulty_mult = 1.21 WHERE slug = 'rack_pull';                    -- T2 + 3 sec → 1.21 (analog: deadlift, partial ROM but axial load)
-- Strict bodyweight pulls — T2 by §3 ("strict pull-up*", "strict chin-up*"). Bodyweight load: 24c.
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'pull_up';                      -- T2 + 2 sec → 1.19 (§3 strict pull-up)
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'chin_up';                      -- T2 + 2 sec → 1.19 (§3 strict chin-up)
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'wide_grip_pull_up';            -- T2 + 2 sec → 1.19 (analog: strict pull-up)
-- Dumbbell rows / supported rows — T3 by §3 ("dumbbell row", "single-arm dumbbell row").
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'dumbbell_row';                 -- T3 + 2 sec → 1.09 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'chest_supported_row';          -- T3 + 1 sec → 1.07 (analog: dumbbell row, more support)
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'seal_row';                     -- T3 + 1 sec → 1.07 (analog: chest-supported row)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'kettlebell_row';               -- T3 + 2 sec → 1.09 (analog: dumbbell row)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'inverted_row';                 -- T3 + 2 sec → 1.09 (judgment: bodyweight horizontal pull; between push-up and pull-up)
-- Cable / machine pulls — T4 by §3 ("cable row", "lat pulldown", "seated row").
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'cable_row';                    -- T4 + 2 sec → 0.99 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'machine_row';                  -- T4 + 2 sec → 0.99 (§3 seated row)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'lat_pulldown';                 -- T4 + 2 sec → 0.99 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'close_grip_lat_pulldown';      -- T4 + 2 sec → 0.99 (analog: lat pulldown)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'face_pull';                    -- T4 + 2 sec → 0.99 (§3 named)
-- Hip-hinge supports — RDL-family at T3 by §3.
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'good_morning';                 -- T3 + 2 sec → 1.09 (§3 named)
-- Back-extension / hyperextension family — T5 isolation, body-supported single-joint hip extension.
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'hyperextension';               -- T5 + 2 sec → 0.89 (analog: back extension, body-supported)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'back_extension';               -- T5 + 2 sec → 0.89 (analog: hyperextension)
-- Single-joint cable pulls (T5).
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'straight_arm_pulldown';        -- T5 + 2 sec → 0.89 (single-joint cable pullover)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'band_pull_apart';              -- T5 + 2 sec → 0.89 (analog: rear delt fly, band-resisted)
UPDATE public.exercises SET difficulty_mult = 0.91 WHERE slug = 'dumbbell_pullover';            -- T5 + 3 sec → 0.91 (analog: rear delt fly, single-joint shoulder extension)

-- ===== LEGS (32) ===========================================================
-- T2 foundational squats / hinges (§3: back squat, front squat).
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'barbell_squat';                -- T2 + 2 sec → 1.19 (§3 back squat)
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'front_squat';                  -- T2 + 2 sec → 1.19 (§3 named)
-- Hinges — §3 lists RDL at T3.
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'romanian_deadlift';            -- T3 + 2 sec → 1.09 (§3 named)
-- Lunges & unilateral compound — T3 by §3 ("dumbbell lunge", "walking lunge", "goblet squat").
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'dumbbell_lunges';              -- T3 + 1 sec → 1.07 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'walking_lunges';               -- T3 + 1 sec → 1.07 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'reverse_lunges';               -- T3 + 1 sec → 1.07 (analog: walking lunges)
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'bulgarian_split_squat';        -- T3 + 1 sec → 1.07 (analog: lunges, unilateral compound)
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'step_up';                      -- T3 + 1 sec → 1.07 (analog: lunges)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'goblet_squat';                 -- T3 + 2 sec → 1.09 (§3 named)
-- Glute / hip thrust pattern (§3 hip_thrust at T3).
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'hip_thrust';                   -- T3 + 1 sec → 1.07 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'glute_bridge';                 -- T5 + 1 sec → 0.87 (analog: hip thrust bodyweight, single-joint hip extension)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'single_leg_glute_bridge';      -- T5 + 1 sec → 0.87 (analog: glute bridge unilateral)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'donkey_kick';                  -- T5 + 1 sec → 0.87 (analog: cable kickback isolation)
-- Bodyweight squats (T3 by §3 "bodyweight squat"). Bodyweight load: 24c.
UPDATE public.exercises SET difficulty_mult = 1.07 WHERE slug = 'bodyweight_squat';             -- T3 + 1 sec → 1.07 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'wall_sit';                     -- T5 + 1 sec → 0.87 (isometric leg hold, analog: plank for legs)
-- Plyometrics — §3 lists box jump at T1 ballistic.
UPDATE public.exercises SET difficulty_mult = 1.25 WHERE slug = 'box_jump';                     -- T1 + 1 sec → 1.27, clamped → 1.25 (§3 named)
-- Machine compound — T4 by §3 (leg press), T3 by §3 (hack squat loaded plate-style).
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'leg_press';                    -- T4 + 1 sec → 0.97 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'single_leg_leg_press';         -- T4 + 1 sec → 0.97 (analog: leg press)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'hack_squat';                   -- T3 + 2 sec → 1.09 (§3 named loaded plate-style)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'reverse_hyperextension';       -- T4 + 2 sec → 0.99 (analog: machine-supported hip extension)
-- Single-joint leg isolation — T5 by §3 ("leg curl", "leg extension", "calf raise").
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'leg_curl';                     -- T5 + 0 sec → 0.85 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'leg_extension';                -- T5 + 0 sec → 0.85 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'leg_abductor';                 -- T5 + 0 sec → 0.85 (analog: leg curl/extension isolation)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'leg_adductor';                 -- T5 + 0 sec → 0.85 (analog: leg curl/extension isolation)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'calf_raise';                   -- T5 + 0 sec → 0.85 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'seated_calf_raise';            -- T5 + 0 sec → 0.85 (analog: calf raise)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'dumbbell_calf_raise';          -- T5 + 0 sec → 0.85 (analog: calf raise)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'nordic_curl';                  -- T5 + 1 sec → 0.87 (analog: leg curl, eccentric-bodyweight)
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'cable_glute_kickback';         -- T4 + 1 sec → 0.97 (single-joint hip extension, cable path-fixed; T4 over T5 for stack resistance)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'cable_pull_through';           -- T4 + 2 sec → 0.99 (cable hip hinge, low spinal load)
-- Bands (judgment: equivalent to T4 cable for resistance shape).
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'band_squat';                   -- T4 + 1 sec → 0.97 (analog: leg press, band-resisted; lower stabilizer than barbell)
-- Kettlebell ballistic / compound.
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'kettlebell_swing';             -- T3 + 3 sec → 1.11 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'kettlebell_goblet_squat';      -- T3 + 2 sec → 1.09 (analog: goblet squat)
UPDATE public.exercises SET difficulty_mult = 1.21 WHERE slug = 'kettlebell_deadlift';          -- T2 + 3 sec → 1.21 (analog: conventional deadlift, kettlebell load)

-- ===== SHOULDERS (19) ======================================================
-- Foundational T2 (§3: overhead press); push press at T1 ballistic per §3.
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'overhead_press';               -- T2 + 2 sec → 1.19 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.25 WHERE slug = 'push_press';                   -- T1 + 3 sec → 1.31, clamped → 1.25 (§3 named)
-- Standard compound dumbbell pressing — T3 by §3 ("dumbbell shoulder press").
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'dumbbell_shoulder_press';      -- T3 + 2 sec → 1.09 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'arnold_press';                 -- T3 + 2 sec → 1.09 (analog: dumbbell shoulder press)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'kettlebell_press';             -- T3 + 2 sec → 1.09 (analog: dumbbell shoulder press)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'landmine_shoulder_press';      -- T3 + 3 sec → 1.11 (analog: dumbbell shoulder press, supported lever)
-- Machine pressing — T4.
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'machine_shoulder_press';       -- T4 + 2 sec → 0.99 (analog: chest press machine)
-- Single-joint deltoid raises — T5 by §3 ("lateral raise", "cable lateral raise", "rear delt fly").
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'lateral_raise';                -- T5 + 2 sec → 0.89 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'cable_lateral_raise';          -- T5 + 2 sec → 0.89 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'front_raise';                  -- T5 + 2 sec → 0.89 (analog: lateral raise)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'cable_front_raise';            -- T5 + 2 sec → 0.89 (analog: lateral raise)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'rear_delt_fly';                -- T5 + 2 sec → 0.89 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'cable_rear_delt_fly';          -- T5 + 2 sec → 0.89 (analog: rear delt fly)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'reverse_pec_deck';             -- T5 + 2 sec → 0.89 (analog: rear delt fly machine)
-- Cable face pulls — §3 lists "face pull" at T4 (cable multi-joint).
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'cable_face_pull';              -- T4 + 2 sec → 0.99 (§3 face pull)
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'band_face_pull';               -- T4 + 2 sec → 0.99 (analog: face pull, band-resisted)
-- Upright row (judgment: cable-style multi-joint shoulder/trap).
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'upright_row';                  -- T4 + 2 sec → 0.99 (judgment: multi-joint shoulder/trap, low stabilizer; analog: face pull)
-- Shrugs — T5 isolation (single-joint scapular elevation).
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'barbell_shrug';                -- T5 + 2 sec → 0.89 (judgment: single-joint scapular elevation, analog: lateral raise)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'dumbbell_shrug';               -- T5 + 2 sec → 0.89 (analog: barbell shrug)

-- ===== ARMS (25) ===========================================================
-- Bicep curls — T5 by §3 ("barbell curl", "dumbbell curl", "hammer curl", "preacher curl").
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'barbell_curl';                 -- T5 + 1 sec → 0.87 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'ez_bar_curl';                  -- T5 + 1 sec → 0.87 (analog: barbell curl)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'dumbbell_curl';                -- T5 + 1 sec → 0.87 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'incline_dumbbell_curl';        -- T5 + 1 sec → 0.87 (analog: dumbbell curl)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'hammer_curl';                  -- T5 + 1 sec → 0.87 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'cable_hammer_curl';            -- T5 + 1 sec → 0.87 (analog: hammer curl)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'concentration_curl';           -- T5 + 1 sec → 0.87 (analog: dumbbell curl)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'cable_curl';                   -- T5 + 1 sec → 0.87 (analog: barbell curl, cable)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'preacher_curl';                -- T5 + 1 sec → 0.87 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'spider_curl';                  -- T5 + 1 sec → 0.87 (analog: preacher curl)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'zottman_curl';                 -- T5 + 1 sec → 0.87 (analog: dumbbell curl)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'reverse_curl';                 -- T5 + 1 sec → 0.87 (analog: barbell curl, supinator emphasis)
-- Wrist isolation.
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'wrist_curl';                   -- T5 + 1 sec → 0.87 (single-joint wrist flexion)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'reverse_wrist_curl';           -- T5 + 1 sec → 0.87 (single-joint wrist extension)
-- Tricep isolation — §3 lists "tricep pushdown" at T4 (cable, path-fixed).
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'tricep_pushdown';              -- T4 + 1 sec → 0.97 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'rope_pushdown';                -- T4 + 1 sec → 0.97 (analog: tricep pushdown)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'skull_crusher';                -- T5 + 1 sec → 0.87 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'overhead_tricep_extension';    -- T5 + 1 sec → 0.87 (§3 tricep extension)
UPDATE public.exercises SET difficulty_mult = 0.87 WHERE slug = 'dumbbell_tricep_extension';    -- T5 + 1 sec → 0.87 (§3 tricep extension)
-- Compound tricep work — close-grip bench / push-up variants (multi-joint).
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'close_grip_bench_press';       -- T3 + 2 sec → 1.09 (analog: barbell bench, tricep emphasis)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'jm_press';                     -- T3 + 2 sec → 1.09 (analog: close-grip bench)
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'close_grip_push_up';           -- T3 + 3 sec → 1.11 (analog: push-up, tricep emphasis)
-- Bodyweight dips & bench dips (§3 lists "strict dip*" at T2; bench dip is far easier).
UPDATE public.exercises SET difficulty_mult = 1.19 WHERE slug = 'dips';                         -- T2 + 2 sec → 1.19 (§3 strict dip; bodyweight load — see 24c)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'bench_dip';                    -- T3 + 2 sec → 1.09 (analog: dip but bench-supported, far less stabilizer)
-- Loaded carry — §3 farmers walk T3.
UPDATE public.exercises SET difficulty_mult = 1.11 WHERE slug = 'farmer_s_walk';                -- T3 + 3 sec → 1.11 (§3 named)

-- ===== CORE (24) ===========================================================
-- §3 lists plank at T5 (isometric, single "joint pattern" by accounting convention).
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'plank';                        -- T5 + 2 sec → 0.89 (§3 named)
UPDATE public.exercises SET difficulty_mult = 0.89 WHERE slug = 'side_plank';                   -- T5 + 2 sec → 0.89 (analog: plank)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'plank_up_down';                -- T3 + 2 sec → 1.09 (judgment: dynamic plank with shoulder articulation, multi-joint)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'hollow_body_hold';             -- T5 + 0 sec → 0.85 (analog: plank, isometric)
-- Hanging leg raise — T3 by §3.
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'hanging_leg_raise';            -- T3 + 2 sec → 1.09 (§3 named)
-- Crunch family — T5 single-joint trunk flexion.
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'crunches';                     -- T5 + 0 sec → 0.85 (single-joint trunk flexion)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'sit_up';                       -- T5 + 0 sec → 0.85 (analog: crunch, larger ROM)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'reverse_crunch';               -- T5 + 0 sec → 0.85 (analog: crunch)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'leg_raise';                    -- T5 + 0 sec → 0.85 (analog: hanging leg raise, floor variant)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'flutter_kick';                 -- T5 + 0 sec → 0.85 (analog: leg raise, dynamic)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'bicycle_crunch';               -- T5 + 0 sec → 0.85 (analog: crunch)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'v_up';                         -- T5 + 0 sec → 0.85 (analog: crunch + leg raise)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'toe_touch';                    -- T5 + 0 sec → 0.85 (analog: crunch)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'heel_touch';                   -- T5 + 0 sec → 0.85 (analog: crunch, oblique)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'windshield_wiper';             -- T5 + 0 sec → 0.85 (analog: leg raise, rotational)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'russian_twist';                -- T5 + 0 sec → 0.85 (analog: crunch, oblique)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'dead_bug';                     -- T5 + 0 sec → 0.85 (single-joint anti-extension)
UPDATE public.exercises SET difficulty_mult = 0.95 WHERE slug = 'cable_crunch';                 -- T4 + 0 sec → 0.95 (§3 named, cable single-joint trunk flexion)
-- Multi-joint / cable-resisted core (woodchop, mountain climber, ab rollout).
UPDATE public.exercises SET difficulty_mult = 0.99 WHERE slug = 'cable_woodchop';               -- T4 + 2 sec → 0.99 (cable multi-joint, rotational power)
UPDATE public.exercises SET difficulty_mult = 0.97 WHERE slug = 'pallof_press';                 -- T4 + 1 sec → 0.97 (cable anti-rotation, single-joint trunk)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'mountain_climber';             -- T3 + 2 sec → 1.09 (judgment: dynamic plank with hip articulation, multi-joint)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'ab_rollout';                   -- T3 + 2 sec → 1.09 (judgment: anti-extension multi-joint; analog: hanging leg raise)
-- Kettlebell complex movements.
UPDATE public.exercises SET difficulty_mult = 1.21 WHERE slug = 'kettlebell_turkish_get_up';    -- T2 + 3 sec → 1.21 (§3 named)
UPDATE public.exercises SET difficulty_mult = 1.09 WHERE slug = 'kettlebell_windmill';          -- T3 + 2 sec → 1.09 (judgment: overhead-loaded hip hinge, stabilizer-heavy)

-- ===== CARDIO (5) ==========================================================
-- Cardio is a Phase 19 v2 deferral (no XP earning paths in v1; xp_attribution
-- is set to {"cardio":1.00} for forward compat). For 24a we assign T5 (0.85)
-- as a conservative placeholder — when cardio earning paths land in 19v2,
-- the multiplier framework will likely change shape (HR / METs based) and
-- these values may be revisited then. T5 here prevents accidental
-- XP-earning path from over-rewarding cardio entries before the model exists.
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'treadmill';                    -- T5 placeholder (cardio v2 deferred — see Phase 19)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'rowing_machine';               -- T5 placeholder (cardio v2 deferred)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'stationary_bike';              -- T5 placeholder (cardio v2 deferred)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'jump_rope';                    -- T5 placeholder (cardio v2 deferred; note: jump rope arguably ballistic — revisit in 19v2)
UPDATE public.exercises SET difficulty_mult = 0.85 WHERE slug = 'elliptical';                   -- T5 placeholder (cardio v2 deferred)

-- ---------------------------------------------------------------------------
-- 3. Constraint enforcing the framework's hard cap.
-- ---------------------------------------------------------------------------

ALTER TABLE public.exercises
  ADD CONSTRAINT chk_difficulty_mult_range
    CHECK (difficulty_mult BETWEEN 0.85 AND 1.25);

-- ---------------------------------------------------------------------------
-- 4. Sanity assert: every is_default = true row must have been mapped above.
--    The column DEFAULT 1.0 silently absorbs typo'd slugs (the UPDATE no-ops);
--    this assert catches misses by failing if any default row still has the
--    literal default value. 1.0 is intentionally OUTSIDE every per-slug
--    curated value (no curated row uses 1.0 — they all bake in a tier+sec
--    bump that produces a non-1.0 value), so this signal is reliable.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_unmapped_count int;
  v_sample_slugs text;
BEGIN
  SELECT count(*), string_agg(slug, ', ' ORDER BY slug)
    INTO v_unmapped_count, v_sample_slugs
  FROM (
    SELECT slug FROM public.exercises
    WHERE is_default = true AND difficulty_mult = 1.0
    LIMIT 10
  ) sub;

  IF v_unmapped_count > 0 THEN
    RAISE EXCEPTION 'Phase 24a curation gap: % default exercises still at the literal 1.0 default (sample: %). Curate them in this migration before deploying.',
      v_unmapped_count, v_sample_slugs;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 5. Sanity assert: every curated value must respect the framework cap.
--    The CHECK constraint above enforces this at INSERT/UPDATE time; this
--    block re-confirms the curated state before COMMIT (defense in depth).
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_out_of_range int;
BEGIN
  SELECT count(*) INTO v_out_of_range
  FROM public.exercises
  WHERE difficulty_mult < 0.85 OR difficulty_mult > 1.25;
  IF v_out_of_range > 0 THEN
    RAISE EXCEPTION 'Phase 24a invariant violation: % rows with difficulty_mult outside [0.85, 1.25]', v_out_of_range;
  END IF;
END
$$;

COMMIT;

-- Reload PostgREST schema cache so the new column becomes visible to the
-- API layer immediately (no impact on Dart yet — Phase C consumes it).
NOTIFY pgrst, 'reload schema';
