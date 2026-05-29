# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

## Phase 32 PR 32e — Profile avatar default + upload

**Branch:** `feature/phase-32e-profile-avatar`

**Source spec:** `docs/PROJECT.md` §3 Phase 32 → "PR 32e — Profile avatar
default + upload".

**Scope:** Replace the current `CircleAvatar`+monogram in `IdentityCard`
with a distinctive `ProfileAvatar` widget (monogram over dominant-BP-hue
→ `hotViolet` gradient; Day-0 fallback `abyss` → `primaryViolet`). Add
camera/gallery picker + bottom-sheet circular crop + Supabase Storage
upload + Hive optimistic cache. iOS scope out (Android-first launch).

### Boundary inventory (from Explore audit 2026-05-28)

**Target swap site (`CircleAvatar` → `ProfileAvatar`):**
- `lib/features/profile/ui/widgets/identity_card.dart:32-108` — current `CircleAvatar(radius: 32)` (64dp) + `AppTextStyles.headline` monogram + `theme.colorScheme.primary` flat fill. Single swap site for the user avatar — the only OTHER `CircleAvatar` ref in `lib/` is a documentation comment in `reward_accent.dart`.

**Identity surface:**
- `lib/features/profile/ui/profile_settings_screen.dart:28-187` (mounts IdentityCard at L56) — owner of the edit-display-name dialog flow + invalidates `profileRepositoryProvider` on update. ProfileAvatar tap → crop-sheet flow plugs in here.
- Current monogram convention: `displayName![0].toUpperCase()` with `email[0]` fallback (IdentityCard L42-46). Match this exactly.

**Dominant-BP derivation (already exists — consume don't reinvent):**
- `lib/features/workouts/ui/widgets/character_card.dart:312-319` — `_dominantTrainedEntry()` iterates `sheet.bodyPartProgress`, skips untrained, returns highest-ranked entry. Tie-break by canonical order: chest → back → legs → shoulders → arms → core.
- Source provider: `characterSheetProvider` at `lib/features/rpg/providers/character_sheet_provider.dart:38-50`.
- Day-0 case: no `dominantTrained` → null → fall to `abyss → primaryViolet` gradient.

**Color tokens (already exist):**
- `lib/features/rpg/domain/body_part_hues.dart:49-69` — `BodyPartHues.bodyPartColor` Map + `hueFor(BodyPart)` accessor (falls back to `AppColors.hotViolet` for null/unknown). chest=pink, back=sky, legs=green, shoulders=amber, arms=red, core=muted, cardio=hair.
- `AppColors.abyss` (#0D0319), `AppColors.primaryViolet` (#6A2FA8), `AppColors.hotViolet` (#B36DFF) at `lib/core/theme/app_theme.dart:26,37,41`.

**Typography:**
- `AppTextStyles.headline` (Rajdhani 600 24dp) — copyWith to size + weight for the monogram. No new style needed; the existing `IdentityCard` monogram uses the same pattern.

**Image picker / camera (Phase 30b infrastructure — reuse):**
- `lib/features/workouts/data/share_service.dart:41-174` — DI-injected `ShareService` with `pickFromCamera()`, `pickFromGallery()`, `requestCameraPermission()`, `cameraPermissionStatus()`, `openAppSettings()`. Web bypass via `kIsWeb`. The avatar flow REUSES this service unchanged — no new picker plumbing.
- `pubspec.yaml:45,47` — `image_picker: ^1.1.2`, `permission_handler: ^11.3.1`.

**Storage bucket precedent:**
- `supabase/migrations/00003_exercise_images.sql:10-36` — `exercise-media` bucket + RLS pattern (`INSERT INTO storage.buckets ...` + `CREATE POLICY ON storage.objects ...`). The avatars bucket follows the same shape with read-public + write-own-user-prefix RLS.

**No existing crop widget** — `AvatarCropSheet` is genuinely new. Per spec: bottom-sheet modal with circular crop mask + pinch-to-zoom + drag-to-reposition + Confirm. Build with `InteractiveViewer` + `ClipPath` circular overlay + confirm pill. No new crop dependency (custom widget keeps the bundle lean and matches the design-token-first convention).

**Hive cache:**
- `lib/core/local_storage/hive_service.dart` — `userPrefs` box is the right home for the cached avatar URL (matches lightweight scalar pattern, doesn't trigger schema-version bump). New entry: `avatarUrlCache:<user_id>` → `String` (URL with `?v=<timestamp>` cache-bust suffix).

**Profile model + repository:**
- `lib/features/profile/models/profile.dart` — Freezed model. **Missing `avatarUrl` field** (DB column exists at `profiles.avatar_url` per `00001_initial_schema.sql:50`). Add `String? avatarUrl` with `@JsonKey(name: 'avatar_url')`.
- `lib/features/profile/data/profile_repository.dart` — `upsertProfile()` needs an optional `avatarUrl` parameter forwarded to the upsert payload.

**Schema audit:**
- Next migration number: `00068` (last is `00067_workout_template_translations.sql`)
- `profiles.avatar_url text` column ALREADY EXISTS — no `ALTER TABLE` needed
- `profiles` RLS policies (select_own/insert_own/update_own) untouched
- The migration ONLY adds the `avatars` storage bucket + RLS on `storage.objects`

### Decisions locked

- **No new dependency.** Custom `AvatarCropSheet` widget built with first-party Flutter primitives (`InteractiveViewer`, `ClipPath`, `MediaQuery` for sheet sizing). Avoid `image_cropper` (native Android plugin adds size + brittleness).
- **Cache pattern: scalar URL in `userPrefs` box.** New entry key: `avatarUrlCache:<user_id>` → `String`. URL embeds `?v=<timestamp>` cache-busting query param so CDN/network revalidates after upload. Avoid binary-blob caching (heavier, fragile on schema bumps).
- **Future-proof constructor.** `ProfileAvatar` takes optional `displayName` + `avatarUrl` + `dominantBodyPart` params (defaulting to current-user values from providers). This unblocks any future leaderboard / social surface without a re-architect.
- **Onboarding stays untouched.** Avatar is post-onboarding optional. Day-0 fallback (`abyss → primaryViolet`) handles the "no avatar yet" state cleanly. New users land on home with the default gradient avatar visible in IdentityCard.
- **Camera permission strings.** Reuse existing share-card camera-permission ARB keys if they exist; otherwise add `cameraPermissionAvatar` localized variant (do NOT inline English). Verify the ARB during impl.
- **Onboarding gate verification.** Spec says avatar is optional post-onboarding. Verify `onboarding_screen.dart` does NOT require avatar before continuing — if it does, that's a separate issue OUT of this PR's scope (flag in PR body).
- **Day-0 gradient.** When `dominantTrained == null` (no trained body parts yet), gradient = `abyss → primaryViolet`. When `dominantTrained` resolves, gradient = `<bodyPartHue> → hotViolet`. The two states are visually distinct enough to signal "Day 0" vs "trained".
- **Per `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`:** all reviewer findings fix in cycle.

### Files to create

- [x] `lib/features/profile/ui/widgets/profile_avatar.dart` — `ProfileAvatar` widget (gradient + monogram + CachedNetworkImage path; defensive provider reads).
  - 64dp default size, `size` constructor param
  - `displayName` constructor param (or pulled from current `userProfileProvider`)
  - `avatarUrl` constructor param (or pulled from cache + profile)
  - `dominantBodyPart` constructor param (or pulled from `characterSheetProvider`)
  - Renders `CachedNetworkImage` if `avatarUrl != null`, else gradient + monogram
  - Gradient: `LinearGradient` from `BodyPartHues.hueFor(dominantBodyPart)` → `AppColors.hotViolet` (Day-0 fallback: `abyss` → `primaryViolet`)
  - Monogram: Rajdhani 700 white, sized to `size * 0.4`, `displayName![0].toUpperCase()` (fallback to `email[0]`, then `?`)
- [x] `lib/features/profile/ui/widgets/avatar_crop_sheet.dart` — `AvatarCropSheet`:
  - Bottom-sheet modal, full-width
  - Circular mask via `ClipPath` (square crop area surrounded by darkened backdrop)
  - `InteractiveViewer` for pinch-to-zoom + drag-to-reposition (constrained to keep image filling the circle)
  - Cancel + Confirm buttons in a thumb-reachable bottom bar
  - Returns the cropped JPEG bytes (compressed to ~80% quality, max 512×512) via `Navigator.pop`
- [x] `lib/features/profile/data/avatar_repository.dart` — `AvatarRepository`:
  - `uploadAvatar({required String userId, required Uint8List jpegBytes}) → Future<String avatarUrl>`
    - Uploads to Supabase Storage at path `avatars/{userId}.jpg`
    - Returns public URL with cache-bust suffix `?v=<DateTime.now().millisecondsSinceEpoch>`
    - Caches URL in `userPrefs` Hive box under key `avatarUrlCache:<userId>`
  - `getCachedAvatarUrl(String userId) → String?` — reads from Hive cache (fast-path for IdentityCard)
  - `invalidateCache(String userId) → Future<void>` — clears the cache entry (called from `ProfileRepository.upsertProfile` when avatar updates)
- [x] `supabase/migrations/00068_avatars_storage_bucket.sql`:
  - `INSERT INTO storage.buckets` for `avatars` bucket (public read, `file_size_limit: 524288` = 512KB, `allowed_mime_types: ['image/jpeg']`)
  - `CREATE POLICY "Public read avatars"` on `storage.objects FOR SELECT USING (bucket_id = 'avatars')`
  - `CREATE POLICY "User upload own avatar"` on `storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1])`
  - `CREATE POLICY "User update own avatar"` on `storage.objects FOR UPDATE` (USING + WITH CHECK with same predicate)
  - `CREATE POLICY "User delete own avatar"` on `storage.objects FOR DELETE` (USING with same predicate)
  - No `ALTER TABLE profiles` — column already exists

### Files to modify

- [x] `lib/features/profile/models/profile.dart`
  - Add `String? avatarUrl` field with `@JsonKey(name: 'avatar_url')`
  - Regen freezed via `make gen`
- [x] `lib/features/profile/data/profile_repository.dart`
  - `upsertProfile()` adds optional `String? avatarUrl` param + forwards to the upsert payload
- [x] `lib/features/profile/ui/widgets/identity_card.dart`
  - Swap `CircleAvatar(radius: 32)` → `ProfileAvatar(size: 64)` at L37
  - Wrap in `GestureDetector` with `onTap: () => _openAvatarCropFlow(context, ref)` (new method that drives picker → crop sheet → upload)
  - Remove the inline monogram-rendering block (now lives in ProfileAvatar)
- [x] `lib/features/profile/ui/profile_settings_screen.dart`
  - Add `_openAvatarCropFlow` driver: picker (camera/gallery sheet via existing pattern) → `AvatarCropSheet` → `AvatarRepository.uploadAvatar` → invalidate `profileRepositoryProvider`
  - Surface error snackbars on upload failure (reuse share-card error pattern)
- [x] `lib/l10n/app_en.arb` + `app_pt.arb` (add only if missing — first verify with grep)
  - `avatarPickerSheetTitle`, `avatarPickerCamera`, `avatarPickerGallery`, `avatarPickerCancel`
  - `avatarCropSheetTitle`, `avatarCropSheetConfirm`, `avatarCropSheetCancel`
  - `avatarUploadSuccess`, `avatarUploadFailed`

### Tests to add

- [x] **Widget tests** for `ProfileAvatar` (15 tests — 7 BodyPart gradients, Day-0 fallback, monogram fallback chain, CachedNetworkImage path, semantics override):
  - Renders monogram with correct gradient for each of 6 dominant body parts (parameterized loop)
  - Renders Day-0 fallback gradient (`abyss → primaryViolet`) when `dominantBodyPart == null`
  - Renders `CachedNetworkImage` (mocked) when `avatarUrl != null` — monogram NOT visible
  - Renders fallback monogram when `displayName` is empty but `email` is set
  - Renders `?` glyph when both `displayName` and `email` are empty
- [x] **Widget test** for `AvatarCropSheet` (4 tests — structure + button wiring + semantics):
  - Renders circular mask + Confirm + Cancel buttons
  - Tapping Confirm returns the JPEG bytes (smoke pin — bytes is non-empty, no full pixel assertion)
  - Tapping Cancel returns `null`
- [x] **Unit tests** for `AvatarRepository` (11 tests — upload path/bytes/upsert/contentType/cache-bust/Hive cache/error mapping + getter/invalidate idempotency):
  - Happy path: upload returns URL with cache-bust suffix
  - Cache fast-path: `getCachedAvatarUrl` returns Hive entry without network call
  - Invalidation: `invalidateCache` clears the entry
  - Error path: Storage upload failure surfaces as `StorageException` (or repo's equivalent)
- [~] **Integration test** skipped — unit + widget tests pin the contract; Supabase not local during PR dev (per CLAUDE.md step 12, migration applies post-merge). End-to-end picker → crop → upload is OS-level and covered by visual verification on physical Android.
  - Pump `IdentityCard` → tap avatar → mock picker returns bytes → confirm crop sheet → assert `uploadAvatar` called + profile updated
- [x] **E2E spec** for `identity-card-avatar` selector visibility (smoke) added to `test/e2e/specs/profile.spec.ts` with the new `PROFILE.identityCardAvatar` selector. Don't drive the upload flow in E2E (camera/gallery picker is OS-level, not Playwright-driveable).

### Verification

- `make ci` green
- E2E smoke green (the new identity-card-avatar selector + existing profile flow)
- **Visual verification on physical Android REQUIRED** (CLAUDE.md step 9):
  - Build APK + install on physical Android
  - Sign in as fresh user → verify Day-0 gradient avatar (`abyss → primaryViolet`) renders in IdentityCard
  - Sign in as foundation user (with trained body parts) → verify dominant-BP-hue gradient renders
  - Tap avatar → verify picker sheet appears → cancel
  - Tap avatar → camera/gallery → crop sheet → confirm → verify upload + IdentityCard re-renders with the uploaded image
  - Sign out / sign back in → verify uploaded avatar persists (Hive cache fast-path + Storage URL)
  - Screenshot each step; attach to PR thread

### Out of scope

- iOS-side UX work (Android-first launch)
- Crop sheet animation polish (basic enter/exit transitions only; no custom Hero animations)
- Avatar history / re-crop UI (only "upload new" supported; old avatar at the Storage path is overwritten)
- Leaderboard / social surfaces consuming `ProfileAvatar(userId:)` — the constructor is future-proofed but no caller exists yet
- `image_cropper` package — building custom per "no new deps" decision
