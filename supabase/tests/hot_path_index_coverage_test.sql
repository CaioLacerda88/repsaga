-- =============================================================================
-- Hot-path index-coverage gate (Phase 38.9 T2.5)
--
-- PURPOSE
--   Pin — automatically, on every CI run — that the XP / vitality / cardio
--   HOT-PATH tables carry the indexes their hot queries depend on for index
--   scans at scale. This is the #1 perf-regression catcher: a migration that
--   adds or reshapes a hot query but forgets its index, OR drops an existing
--   hot-path index, turns a test RED here deterministically — no timing, no
--   flake.
--
-- WHY THIS SHAPE (not a wall-clock gate)
--   `test/.../rpg_save_workout_perf_test.dart` measures p50/p95/p99 but only
--   LOGS — its own comments note the wall-clock is dominated by the
--   PostgREST/Docker REST round-trip (~400-700ms) which swamps the ~50ms of
--   actual Postgres execution ~10×. A wall-clock CI gate is therefore either
--   too loose to catch a regression or too tight to avoid flaking on a noisy
--   runner. The deterministic perf signal lives INSIDE Postgres — in whether
--   the planner CAN do an index scan — so the gate asserts index EXISTENCE at
--   the schema level instead of measuring latency.
--
-- WHAT GREEN MEANS
--   Every hot query still has the index it was designed around. A RED test
--   here is NOT flaky — it means a migration removed or renamed an index that
--   a hot-path query relies on (or added a hot query without its index). The
--   fix is the migration (restore / add the index), never the assertion —
--   unless the hot query itself was intentionally removed, in which case the
--   matching assertion is retired in the same PR.
--
-- APPROACH
--   pgTAP via `supabase test db` — the SAME harness `rls_isolation_test.sql`
--   uses (run by the `rls-tests` CI job, which invokes bare `supabase test db`
--   with no --file filter, so this file auto-runs alongside the RLS test). No
--   hosted instance, no secrets, no new CI job. Read-only schema introspection
--   wrapped in a transaction that `supabase test db` rolls back.
--
-- INDEX INVENTORY (table → index → which hot query relies on it)
--   Canonical RPC defs: docs/canonical-rpc-definitions.md (00081/00082 batch +
--   vitality; 00078/00079 cardio). Migrations: 00040 (RPG v1 schema),
--   00065 (by_rep_range), 00001 (sets), 00078/00079 (cardio).
--
--   xp_events
--     xp_events_user_set_unique (user_id, set_id) WHERE set_id IS NOT NULL
--       → backs the per-set idempotency `ON CONFLICT (user_id, set_id) DO
--         NOTHING` in record_session_xp_batch (step 8, canonical L179-180).
--     xp_events_user_cardio_session_unique (user_id, session_id)
--       WHERE set_id IS NULL AND event_type = 'cardio_session'
--       → backs the `ON CONFLICT` idempotency in record_cardio_session (00079);
--         cardio has no set_id so it needs its own partial unique key.
--     xp_events_user_occurred_idx (user_id, occurred_at DESC)
--       → backs recompute_vitality's "this user's xp_events in the last 7 days"
--         window scan (canonical L156) and the user_id-scoped history reads.
--     xp_events_session_idx (session_id) WHERE session_id IS NOT NULL
--       → backs the per-session attribution scan in record_cardio_undo /
--         vitality recompute (DISTINCT attribution keys on THIS session).
--
--   body_part_progress
--     body_part_progress_pkey (user_id, body_part)  [PRIMARY KEY]
--       → backs the `ON CONFLICT (user_id, body_part) DO UPDATE` upsert in
--         record_session_xp_batch (step 9, canonical L182-184) AND every
--         per-(user, body_part) read in vitality recompute.
--
--   sets
--     idx_sets_workout_exercise (workout_exercise_id)
--       → backs save_workout / the batch writer joining sets to their parent
--         workout_exercise (the FK the per-workout set fetch keys on).
--
--   exercise_peak_loads
--     exercise_peak_loads_pkey (user_id, exercise_id)  [PRIMARY KEY]
--       → backs the peak-map load (canonical L153, step 4) and the forward-only
--         `ON CONFLICT (user_id, exercise_id) DO UPDATE` upsert (step 10).
--
--   exercise_peak_loads_by_rep_range
--     exercise_peak_loads_by_rep_range_pkey (user_id, exercise_slug, rep_band)
--       [PRIMARY KEY]
--       → backs the per-band `ON CONFLICT (user_id, exercise_slug, rep_band) DO
--         UPDATE` upsert (step 11, canonical L185-187) read by rpg_overload_mult.
--
--   cardio_sessions
--     idx_cardio_sessions_workout_id (workout_id)
--       → backs the RLS owner-scoping (workout join) AND the per-workout cardio
--         fetch in record_session_xp_batch / undo (canonical L58).
--     idx_cardio_sessions_exercise_id (exercise_id)
--       → backs the "last cardio entry for this activity" history lookup (00078).
--
-- DEFERRED (the deeper version — NOT built here, see PROJECT.md §2 T2.5)
--   An `auto_explain` / `EXPLAIN`-based PLAN gate (assert no Seq Scan on a hot
--   table, no new nested-loop, bounded statement count) would additionally
--   catch a per-row subquery / N+1 added INSIDE a plpgsql RPC body. That is
--   harder — plpgsql hides inner statement plans, so it needs auto_explain log
--   parsing or extracted-query EXPLAIN. This index-coverage gate is the easy,
--   zero-flake slice; the plan gate is the documented follow-up.
-- =============================================================================

BEGIN;

-- pgTAP is installed transiently by `supabase test db`; create it defensively
-- so the file is also runnable via `psql -f` for local iteration.
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

-- One assertion per hot-path index documented above.
SELECT plan(10);

-- ---------------------------------------------------------------------------
-- xp_events — per-set / per-cardio idempotency + user-scoped window scans
-- ---------------------------------------------------------------------------
SELECT has_index(
  'public', 'xp_events', 'xp_events_user_set_unique',
  'xp_events: (user_id, set_id) unique idempotency index backs the per-set '
  || 'ON CONFLICT DO NOTHING in record_session_xp_batch'
);
SELECT has_index(
  'public', 'xp_events', 'xp_events_user_cardio_session_unique',
  'xp_events: (user_id, session_id) partial unique index backs the cardio '
  || 'ON CONFLICT idempotency in record_cardio_session (no set_id)'
);
SELECT has_index(
  'public', 'xp_events', 'xp_events_user_occurred_idx',
  'xp_events: (user_id, occurred_at DESC) backs the vitality 7-day window scan '
  || 'and user-scoped history reads'
);
SELECT has_index(
  'public', 'xp_events', 'xp_events_session_idx',
  'xp_events: (session_id) partial index backs the per-session attribution scan '
  || 'in cardio undo / vitality recompute'
);

-- ---------------------------------------------------------------------------
-- body_part_progress — per-(user, body_part) upsert + read
-- ---------------------------------------------------------------------------
SELECT has_index(
  'public', 'body_part_progress', 'body_part_progress_pkey',
  'body_part_progress: PK (user_id, body_part) backs the ON CONFLICT DO UPDATE '
  || 'upsert in record_session_xp_batch and per-body-part vitality reads'
);

-- ---------------------------------------------------------------------------
-- sets — FK to workout_exercises (per-workout set fetch)
-- ---------------------------------------------------------------------------
SELECT has_index(
  'public', 'sets', 'idx_sets_workout_exercise',
  'sets: (workout_exercise_id) FK index backs save_workout / the batch writer '
  || 'joining sets to their parent workout_exercise'
);

-- ---------------------------------------------------------------------------
-- exercise_peak_loads (+ _by_rep_range) — strength_mult / overload inputs
-- ---------------------------------------------------------------------------
SELECT has_index(
  'public', 'exercise_peak_loads', 'exercise_peak_loads_pkey',
  'exercise_peak_loads: PK (user_id, exercise_id) backs the peak-map load and '
  || 'the forward-only ON CONFLICT DO UPDATE upsert in record_session_xp_batch'
);
SELECT has_index(
  'public', 'exercise_peak_loads_by_rep_range',
  'exercise_peak_loads_by_rep_range_pkey',
  'exercise_peak_loads_by_rep_range: PK (user_id, exercise_slug, rep_band) backs '
  || 'the per-band ON CONFLICT DO UPDATE upsert read by rpg_overload_mult'
);

-- ---------------------------------------------------------------------------
-- cardio_sessions — workout-join (RLS + batch) hot key
-- ---------------------------------------------------------------------------
SELECT has_index(
  'public', 'cardio_sessions', 'idx_cardio_sessions_workout_id',
  'cardio_sessions: (workout_id) backs the RLS owner-scoping workout join and '
  || 'the per-workout cardio fetch in record_session_xp_batch / undo'
);
SELECT has_index(
  'public', 'cardio_sessions', 'idx_cardio_sessions_exercise_id',
  'cardio_sessions: (exercise_id) backs the "last cardio entry for this '
  || 'activity" per-exercise history lookup'
);

-- ---------------------------------------------------------------------------
SELECT * FROM finish();
ROLLBACK;
