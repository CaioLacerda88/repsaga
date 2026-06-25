-- =============================================================================
-- vitality_ref_peak — recompute_vitality_for_user decaying reference-peak gate
-- (Phase Vitality-2, 00083)
--
-- PURPOSE
--   `recompute_vitality_for_user` had ZERO pgTAP coverage before this file. It
--   is the single SQL writer of body_part_progress.vitality_* for BOTH the save
--   path and the nightly cron. 00083 adds `vitality_ref_peak` — a DECAYING
--   reference peak (21-day half-life) that is the denominator for the
--   post-session conditioning charge fraction (ewma / ref_peak), distinct from
--   the monotone career-best `vitality_peak`.
--
--   This gate pins the ref_peak contract deterministically (no wall-clock, no
--   network): a regression in the GREATEST(new_ewma, prior_ref_peak * decay)
--   expression, the half-life constant, or the once-per-day guard turns a test
--   RED. A RED here is a real schema/function regression — the fix is the
--   migration, never the assertion.
--
-- WHAT IS COVERED
--   (a) a fresh step on a day-0 bp (with weekly volume) sets
--       ref_peak = new_ewma (the new ewma tops the GREATEST when prior_ref_peak
--       is 0);
--   (b) a DETRAINING step (zero weekly volume → ewma decays) decays ref_peak by
--       exactly the per-day half-life factor, BELOW the monotone vitality_peak;
--   (c) a 2nd same-day recompute with the SAME (unchanged) volume window
--       RE-STEPS from the stored day-base and yields the SAME value (idempotent
--       — Vitality-4 day-base re-step, NOT the old "guard freezes it" no-op);
--   (d) vitality_peak is NEVER decreased by any of this (career-best intact);
--   (e) a 2nd same-day recompute AFTER new volume enters the window RE-STEPS the
--       ewma UP from the day-base — the part is NOT frozen (the Vitality-4
--       regression for the cron-pre-empts-save immediacy bug).
--
-- APPROACH
--   pgTAP via `supabase test db` — same harness as rls_isolation_test.sql,
--   auto-run by the rls-tests CI job (bare `supabase test db`, no --file
--   filter). Transaction-wrapped, rolled back, no hosted instance.
--
--   The function reads xp_events for the 7-day weekly volume. By NOT seeding
--   xp_events we force weekly_volume = 0 → the pure-decay branch, which is the
--   deterministic surface for the detrain + guard assertions. For the "new ewma
--   tops ref_peak" assertion we seed one in-window xp_events row.
--
--   recompute_vitality_for_user is SECURITY DEFINER and uses now() for the UTC
--   day stamp; we seed/read as the bootstrap superuser (bypasses RLS).
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(13);

-- -----------------------------------------------------------------------------
-- Fixed test user. body_part_progress.user_id FKs auth.users(id).
-- -----------------------------------------------------------------------------
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
VALUES
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'refpeak_user@test.local', '', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- The per-day reference-peak decay multiplier — MUST match c_ref_peak_decay in
-- recompute_vitality_for_user (00083): exp(-ln(2)/21), a 21-day half-life.
-- Recomputed here independently so a drift in the function's constant fails.
-- (Stored via a temp table since pgTAP runs are plain SQL, no session vars.)
CREATE TEMP TABLE _k(decay numeric);
INSERT INTO _k VALUES (exp(-ln(2.0) / 21.0));

-- =============================================================================
-- (a) Fresh step with weekly volume → ref_peak = new_ewma (new ewma tops the
--     GREATEST when prior_ref_peak is 0). Day-0 bp: no row yet.
-- =============================================================================

-- Seed one in-window xp_events row attributing chest volume so weekly_volume>0.
-- event_type='cardio_session' sidesteps the set-FK CHECK (mirrors the
-- integration test's _seedXpEvent rationale); the worker aggregates attribution
-- regardless of event_type.
INSERT INTO public.xp_events (id, user_id, event_type, set_id, session_id,
                              occurred_at, total_xp, attribution, payload)
VALUES (
  gen_random_uuid(),
  '33333333-3333-3333-3333-333333333333',
  'cardio_session', NULL, NULL,
  now() - interval '1 day',
  500.0, '{"chest": 500.0}'::jsonb, '{"synthetic": true}'::jsonb
);

SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['chest']);

-- new_ewma = α_up * 500 (prior 0) ≈ 0.39346934 * 500 ≈ 196.73. ref_peak must
-- equal new_ewma exactly (GREATEST(new_ewma, 0 * decay) = new_ewma).
SELECT is(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  '(a) fresh step: ref_peak == new_ewma when prior ref_peak is 0');

SELECT cmp_ok(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  '>', 0::numeric,
  '(a) fresh step: ref_peak is positive (ewma flowed in)');

-- last_vitality_date stamped today by the step.
SELECT is(
  (SELECT last_vitality_date FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  (now() AT TIME ZONE 'utc')::date,
  '(a) fresh step: last_vitality_date stamped to today');

-- =============================================================================
-- (b) Detraining step (zero weekly volume) decays ref_peak by exactly the
--     per-day half-life factor, and BELOW the monotone vitality_peak.
--
--     Seed a 'back' row with a high career peak + a known ref_peak, NO xp_events
--     for 'back' → weekly_volume 0 → ewma decays, ref_peak decays.
-- =============================================================================

INSERT INTO public.body_part_progress
  (user_id, body_part, total_xp, rank, vitality_ewma, vitality_peak,
   vitality_ref_peak, last_vitality_date)
VALUES
  ('33333333-3333-3333-3333-333333333333', 'back', 0, 1,
   100.0, 900.0, 800.0, NULL);  -- prior ewma 100, career peak 900, ref_peak 800

SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['back']);

-- Pure decay: new_ewma = (1-α_down_str)*100 ≈ exp(-7/42)*100 ≈ 84.65 (< 800),
-- so ref_peak = GREATEST(84.65, 800 * decay) = 800 * decay ≈ 773.99.
SELECT cmp_ok(
  (SELECT round(vitality_ref_peak, 4) FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '=',
  (SELECT round(800.0 * decay, 4) FROM _k),
  '(b) detrain step: ref_peak = prior_ref_peak * per-day half-life decay');

-- ref_peak must now be strictly below the monotone career peak (the whole point
-- — the denominator forgets so a comeback reads meaningfully).
SELECT cmp_ok(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '<', 900::numeric,
  '(b) detrain step: decayed ref_peak is below the all-time vitality_peak');

-- And above the decayed ewma (it is a *reference ceiling*, not a copy of ewma).
SELECT cmp_ok(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '>',
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '(b) detrain step: ref_peak stays above the decayed ewma (a real ceiling)');

-- =============================================================================
-- (d) vitality_peak is NEVER decreased — career best intact after the decay.
-- =============================================================================

SELECT is(
  (SELECT vitality_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  900.0::numeric(14,4),
  '(d) detrain step: vitality_peak (career best) NOT decreased by ref_peak decay');

-- =============================================================================
-- (c) Same-day idempotency via re-step: a 2nd same-day recompute with the SAME
--     (unchanged) volume window RE-STEPS from the stored day-base and lands on
--     the SAME value. This is NOT the old "guard freezes the row" no-op — the
--     row is recomputed from `vitality_*_day_base`, but because α is applied
--     once from the same base over the same window, the result is identical.
--     A regression that compounded α (re-applied from the already-stepped
--     current value) would move ewma/ref_peak here and turn this RED.
-- =============================================================================

-- Capture post-first-step state for 'back'.
CREATE TEMP TABLE _snap AS
  SELECT vitality_ewma, vitality_ref_peak, vitality_peak
  FROM public.body_part_progress
  WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back';

-- Second same-day recompute — re-steps from the day-base, same window, so it
-- reproduces the first-step result exactly.
SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['back']);

SELECT is(
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  (SELECT vitality_ewma FROM _snap),
  '(c) re-step: 2nd same-day recompute with unchanged window leaves ewma '
  'identical (idempotent re-step from day-base, no compounded α)');

SELECT is(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  (SELECT vitality_ref_peak FROM _snap),
  '(c) re-step: 2nd same-day recompute with unchanged window leaves ref_peak '
  'identical (idempotent re-step from day-base)');

SELECT is(
  (SELECT vitality_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  (SELECT vitality_peak FROM _snap),
  '(c) re-step: 2nd same-day recompute leaves vitality_peak untouched');

-- =============================================================================
-- (e) Re-step UP — the immediacy regression (Vitality-4 bug).
--
--     Reproduces the real failure order: a part is stepped FIRST today (the
--     cron, stamping the day-base), THEN the user trains and saves so NEW
--     in-window volume arrives, and a 2nd same-day recompute must RE-STEP the
--     ewma UP from the day-base — the part is NOT frozen. Under the old guard
--     this 2nd step was skipped and the session's volume vanished ("MANTIDO"
--     with no movement). Here it must move.
--
--     Use a fresh 'legs' bp so it's independent of the 'back'/'chest' state.
-- =============================================================================

-- First step today: seed a modest in-window volume and step legs (this stamps
-- vitality_legs_day_base and last_vitality_date=today).
INSERT INTO public.xp_events (id, user_id, event_type, set_id, session_id,
                              occurred_at, total_xp, attribution, payload)
VALUES (
  gen_random_uuid(),
  '33333333-3333-3333-3333-333333333333',
  'cardio_session', NULL, NULL,
  now() - interval '1 day',
  300.0, '{"legs": 300.0}'::jsonb, '{"synthetic": true}'::jsonb
);

SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['legs']);

-- Snapshot the first-step ewma + day-base.
CREATE TEMP TABLE _legs1 AS
  SELECT vitality_ewma, vitality_ewma_day_base
  FROM public.body_part_progress
  WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'legs';

-- Day-base for legs must be 0 (day-0 bp, no prior step today) — the value the
-- re-step computes FROM.
SELECT is(
  (SELECT vitality_ewma_day_base FROM _legs1),
  0::numeric(14,4),
  '(e) first step stamps the legs day-base to the prior value (0, day-0 bp)');

-- The session adds MORE legs volume to the 7-day window (a second in-window
-- event). Now a same-day recompute must re-step UP from the day-base.
INSERT INTO public.xp_events (id, user_id, event_type, set_id, session_id,
                              occurred_at, total_xp, attribution, payload)
VALUES (
  gen_random_uuid(),
  '33333333-3333-3333-3333-333333333333',
  'cardio_session', NULL, NULL,
  now() - interval '2 hours',
  500.0, '{"legs": 500.0}'::jsonb, '{"synthetic": true}'::jsonb
);

SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['legs']);

-- ewma must have STEPPED UP — the window grew (300 → 800) and the re-step
-- applied α_up from the same day-base (0). Old guard would have left it frozen
-- at the first-step value.
SELECT cmp_ok(
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'legs'),
  '>',
  (SELECT vitality_ewma FROM _legs1),
  '(e) re-step UP: a same-day recompute after new in-window volume steps ewma '
  'ABOVE the first step (immediacy restored — part is NOT frozen)');

-- And it equals the closed-form re-step from the day-base over the full window:
-- α_up * 800 (base 0). Confirms the step is from the BASE, not compounded.
SELECT cmp_ok(
  (SELECT round(vitality_ewma, 4) FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'legs'),
  '=',
  (SELECT round((1 - exp(-7.0 / 14.0)) * 800.0, 4)),
  '(e) re-step UP: ewma == α_up * full-window volume from the day-base (0) — '
  'single α from the base, no compounding');

-- -----------------------------------------------------------------------------
SELECT * FROM finish();
ROLLBACK;
