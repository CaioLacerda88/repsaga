-- =============================================================================
-- Routine-level training notes (Q2)
-- Migration: 00075_workout_template_notes
--
-- Adds an optional free-text `notes` column to `workout_templates` so a user
-- can attach program intent / form cues / deload schedule to a routine. The
-- notes are editable on the create/edit-routine screen and rendered read-only
-- during an active workout started from that routine.
--
-- Char cap = 600 (UX-locked): routine notes are read mid-set between exercises,
-- so brevity is enforced at the DB layer too — tighter than the generous
-- `workouts.notes` (2000) / `sets.notes` (1000) abuse-ceilings from migration
-- 00021, because this is an ergonomic limit the UI mirrors (`maxLength: 600`),
-- not just a defense-in-depth ceiling.
--
-- `char_length()` (not `length()`) counts characters, not bytes — multi-byte
-- safe for emoji / non-Latin input. NULL passes the CHECK (a routine with no
-- notes), matching the nullable column.
--
-- Constraint naming follows migration 00021: `valid_<table>_<col>_length`.
--
-- Intentionally non-idempotent: `ALTER TABLE ... ADD CONSTRAINT` fails on
-- re-apply. Safe because Supabase's migration runner tracks applied migrations;
-- a normal `db push` never re-runs a migration, and `db reset` rebuilds the DB
-- from scratch first. This matches the established 00021 convention.
--
-- No RPC to update: `workout_templates` rows are written via plain PostgREST
-- insert/update (`RoutineRepository.createRoutine` / `updateRoutine`); RLS
-- gates by `user_id` / `is_default` only and does not whitelist columns, so the
-- new column is writable as soon as the client payload includes it.
-- =============================================================================

ALTER TABLE workout_templates
  ADD COLUMN notes text;

ALTER TABLE workout_templates
  ADD CONSTRAINT valid_workout_templates_notes_length
  CHECK (notes IS NULL OR char_length(notes) <= 600);
