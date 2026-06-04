-- PR 1 — fix(auth): derive onboarding state from profile row.
--
-- Adds `profiles.onboarded_at timestamptz` as the canonical anchor for
-- "did this user finish the onboarding flow". Replaces the in-memory
-- `needsOnboardingProvider` (StateProvider<bool>) which was lost on every
-- process restart — half-onboarded users would land on /home instead of
-- /onboarding on relaunch (audit defects D1, D2, D11).
--
-- The router gate now reads `profile.onboardedAt` directly:
--   * non-null  → user finished onboarding → /home allowed.
--   * null      → user has NOT finished onboarding → redirect to /onboarding.
--
-- Backfill: historical users with a populated `display_name` are treated as
-- already onboarded — set `onboarded_at = created_at` as a proxy. Users
-- without a display_name stay NULL → next launch routes them through
-- /onboarding (desired — closes the user-reported repro of
-- `gihfigueiredo_@hotmail.com` who reached /home with display_name = NULL).
--
-- Live impact at ship time (queried 2026-06-03 against hosted Supabase):
--   * will_backfill = 2  (display_name IS NOT NULL)
--   * stays_null    = 4  (display_name IS NULL → next launch sends them to /onboarding)
--   * total         = 6
--
-- No CHECK constraint, no trigger, no RLS change — the existing
-- `profiles_update_own` policy already covers the new column (a user can
-- update their own row's `onboarded_at` via the standard upsert path).

ALTER TABLE profiles
  ADD COLUMN onboarded_at timestamptz;

UPDATE profiles
  SET onboarded_at = created_at
  WHERE display_name IS NOT NULL;
