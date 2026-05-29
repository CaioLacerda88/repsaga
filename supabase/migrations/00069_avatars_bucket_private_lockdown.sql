-- Phase 32 PR 32e — flip avatars bucket from public to private per LGPD/GDPR
-- compliance. The original 00068 shipped public:true matching competitor
-- (Strong/Hevy) convention, but user-uploaded photos require signed URLs
-- over a private bucket regardless of social-feed presence. See
-- `feedback_data_protection_compliance` cluster.
--
-- Migration 00068 is intentionally left intact (migration history is
-- append-only — editing a shipped migration would diverge from the hosted
-- instance's recorded migration log). This file is the immutable record of
-- the public→private transition.
--
-- Consumer impact: `AvatarRepository.uploadAvatar` now generates a 1-year
-- signed URL via `createSignedUrl` and stores it on `profiles.avatar_url`.
-- A companion Hive entry tracks the expiry so subsequent reads regenerate
-- the URL once it lapses (rather than serving a dead link). The
-- `getPublicUrl` code path is retired — `public:false` makes that endpoint
-- return 401/403.

UPDATE storage.buckets SET public = false WHERE id = 'avatars';

-- Drop the public-read policy and replace with authenticated-own-prefix.
-- Users can read ONLY their own avatar (no cross-user reads — leaderboard
-- consumers would request signed URLs server-side if/when that surface
-- ships, going through an RPC that has elevated read-any privileges).
DROP POLICY IF EXISTS "Public read avatars" ON storage.objects;

CREATE POLICY "User read own avatar"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- The INSERT / UPDATE / DELETE policies from 00068 stay as-is (already
-- own-prefix gated on `(storage.foldername(name))[1] = auth.uid()::text`).
