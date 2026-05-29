-- Phase 32 PR 32e — Avatars storage bucket + RLS.
--
-- Creates the public `avatars` bucket used by `AvatarRepository.uploadAvatar`
-- to persist user-uploaded profile pictures. The `profiles.avatar_url`
-- column already exists (00001_initial_schema.sql) — this migration only
-- adds storage infrastructure, no `ALTER TABLE` needed.
--
-- File layout: `avatars/{user_id}/avatar.jpg`. The user's UUID is the
-- top-level folder; RLS gates write access to objects whose first folder
-- segment matches `auth.uid()::text`. The nested layout (not a flat
-- `{user_id}.jpg`) is REQUIRED for the RLS predicate to pass:
-- `storage.foldername(name)` returns the slash-delimited path segments
-- MINUS the filename, so:
--   * `'abc/avatar.jpg'` → `['abc']` → `[1] = 'abc'` (auth.uid match ✓)
--   * `'abc.jpg'`         → `[]`      → `[1] = NULL` (auth.uid mismatch ✗)
-- A flat layout would deny every upload at the RLS layer. JPEG + PNG
-- accepted: the v1 client-side `AvatarCropSheet` rasterizes via `dart:ui`
-- which exposes a public PNG encoder only; accepting both mime types lets
-- a future PR drop in a JPEG encoder without a bucket migration. 512KB
-- ceiling comfortably accommodates the 512×512 PNG output (typical
-- ~150-300KB).
--
-- Read access is public so the public URL embedded on the profile row
-- renders directly from any client without an authenticated request.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  524288,
  ARRAY['image/jpeg', 'image/png']
);

-- Anyone (including unauthenticated visitors) can read avatars. Necessary
-- so the embedded public URL on `profiles.avatar_url` renders directly in
-- a future leaderboard / social surface without an auth round-trip.
CREATE POLICY "Public read avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- A signed-in user can upload an object whose first folder segment matches
-- their auth.uid(). `storage.foldername(name)[1]` returns the first segment
-- of the slash-delimited path — for `{user_id}/avatar.jpg` that segment is
-- the literal `{user_id}` UUID, which equals auth.uid()::text.
CREATE POLICY "User upload own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "User update own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "User delete own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
