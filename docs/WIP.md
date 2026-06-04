# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

### Fix — home ActionHero stale state after week-plan edit

Branch: `fix/home-action-hero-stale-weekly-plan`

**User-visible symptom:** After onboarding, user opens `/plan/week`, adds
default routines to the bucket, returns to `/home`. The big ActionHero
widget keeps reading "Criar primeira rotina" instead of switching to
"Iniciar <routine name>".

**Phase 1 — Root cause (systematic-debugging).** The branch gate in
`lib/features/workouts/ui/widgets/action_hero.dart` is:

```dart
if (workoutCount == 0 && userRoutines.isEmpty) {
  branch = const _CreateFirstRoutineHero();
}
```

`userRoutines` filters out `isDefault: true` routines. New user post-
onboarding has zero custom routines and only seeded defaults — so the
filter resolves to empty even after the user puts default routines into
the weekly plan. `routineListProvider` does not change when the weekly
plan changes; the gate stays satisfied; the hero stays on day-0 copy.

The Phase 27 L3 widget test at
`test/widget/features/workouts/ui/home_screen_action_hero_test.dart`
line 561 explicitly pinned this behavior ("create-first-routine still
wins even with a populated bucket"). Intent at the time was to dedupe
the day-0 CTA against the routines-list empty state. But it traps users
who actually picked routines for the week — the hero blocks the obvious
next action.

**Phase 2 — Pattern match.** `_HomeRoutinesList` already gates on
`hasActivePlanProvider` (yields when plan has entries). `BucketChipRow`
reactively reads `weeklyPlanProvider`. Both update on `/plan/week` save
because `WeekPlanScreen._savePlan` calls
`weeklyPlanProvider.notifier.setOptimistic(_bucketRoutines)` (line 608)
— same synchronous-state-push pattern. ActionHero's branch logic
doesn't read the plan in branch-1's gate, so the same reactivity is
unused there.

**Phase 3 — Hypothesis (ONE theory).** The L3 gate should ALSO require
"no uncompleted bucket entry" before falling into branch 1. If
`suggestedNextProvider != null`, that's a stronger signal than "user
has no custom routines" — the user has explicitly planned routines for
this week, the start-next-routine branch must win. The widget already
watches `suggestedNextProvider` further down (branch 2 decision); we
just need to hoist that read above the L3 gate.

**Phase 4 — Fix location.**
`lib/features/workouts/ui/widgets/action_hero.dart` —
`ActionHero.build()`. Add the `suggestedNextProvider == null` precondition
to the L3 gate.

Files:

- [x] `lib/features/workouts/ui/widgets/action_hero.dart` — hoist
      `suggestedNextProvider` read, tighten L3 gate to also require
      `next == null` before falling into `_CreateFirstRoutineHero`.
      Class docstring updated to reflect the empty-bucket precondition.
- [x] `test/widget/features/workouts/ui/home_screen_action_hero_test.dart`
      — replaced the obsolete "create-first-routine still wins with
      populated bucket" assertion (it was pinning the bug) with two new
      tests: (1) `_CreateFirstRoutineHero` still fires for day-0 user
      with default-only routines AND empty bucket, (2) `_CreateFirstRoutineHero`
      yields to `_StartNextRoutineHero` when the bucket has any entry.
      Added a reactive-transition test that calls `setOptimistic` on the
      bound `weeklyPlanProvider.notifier` and pumps — mirrors the exact
      path `WeekPlanScreen._savePlan` takes on every edit.

Verification:

- [x] `dart format .` — 0 changes after the fix
- [x] `dart analyze --fatal-infos` — 0 issues
- [x] All four custom analyze scripts (`check_reward_accent`,
      `check_hardcoded_colors`, `check_typography_call_sites`,
      `check_no_developer_log`) — clean
- [x] `flutter test test/widget/features/workouts/ui/home_screen_action_hero_test.dart`
      — 17/17 pass (added 2, modified 1 — all green)
- [x] `flutter test test/widget/features/workouts test/widget/features/weekly_plan`
      — 482/482 pass (verifies no Home / WeekPlan regression elsewhere)
- [x] `flutter test test/widget test/unit` — 3416/3416 pass. The full
      `flutter test` run's 25 failures are integration tests under
      `test/integration/` that require a live local Supabase
      (`npx supabase start`) — not impacted by this fix, not part of
      `make ci` (Makefile excludes them via `--exclude-tags integration`).

---

### PR A2 — locale metadata backfill + client hydration

Branch: `feat/auth-locale-metadata-backfill-and-client-hydration`

Closes the two `user_metadata.locale = NULL` populations documented in PR
#300's `docs/auth-email-templates/README.md` → "Known edge cases" and
explicitly deferred:

1. **Legacy users** — anyone who signed up before PR #300 merged. Their
   `auth.users.raw_user_meta_data` has no `locale` key, so password reset,
   magic link, and email change emails fall into the template's
   `{{ else }}` English branch regardless of `profiles.locale`.
2. **Google OAuth signups** — Supabase's OAuth flow cannot set
   `user_metadata` at authorization time, so OAuth users land in the same
   `{{ else }}` English branch even if their `profiles.locale = 'pt'`.

Two-layer fix:

**SQL migration (bounded, one-shot — covers legacy users):**

- [x] `supabase/migrations/00073_backfill_user_metadata_locale.sql` —
      idempotent UPDATE merging `profiles.locale` into
      `auth.users.raw_user_meta_data` for every user whose metadata locale
      is currently NULL and whose `profiles.locale IN ('en','pt')`.
      `COALESCE(raw_user_meta_data, '{}'::jsonb)` defends against legacy
      rows with NULL metadata.

**Dart client hydration (unbounded, ongoing — covers OAuth + any future
gap):**

- [x] `lib/core/constants/supported_locales.dart` — new const
      `kSupportedLocales = ['en','pt']` shared by `MaterialApp.supportedLocales`,
      the SQL backfill allowlist (comment cross-reference), and the
      hydration helper's allowlist guard.
- [x] `lib/app.dart` — `MaterialApp.supportedLocales` consumes
      `kSupportedLocales.map(Locale.new).toList()` instead of the
      gen-l10n-produced `AppLocalizations.supportedLocales`. A unit test
      pins the two stay in sync.
- [x] `lib/features/auth/data/auth_repository.dart` — new
      `updateUserMetadata(Map<String, Object?> data)` wraps
      `_auth.updateUser(UserAttributes(data:))` with `mapException` +
      `_authTimeout`. Keeps Supabase access inside the repository layer.
- [x] `lib/features/profile/providers/profile_providers.dart` —
      `ProfileNotifier.build()` fires `unawaited(_hydrateLocaleMetadataIfMissing(profile))`
      after `getProfile(...)` resolves. The helper short-circuits when
      `user_metadata.locale` is already populated, when `profile.locale`
      is not in `kSupportedLocales`, or on any caught error (Sentry
      breadcrumb only — never an `AsyncError` on the profile). Placement
      rides on the existing `provider-init-timing` cluster fix so the
      check re-runs on every signedIn / tokenRefreshed event.

**Tests:**

- [x] `test/unit/features/profile/providers/profile_notifier_locale_hydration_test.dart` —
      6 hydration cases + 1 contract test:
  - writes locale = 'pt' when metadata locale is null + profile.locale is 'pt'
  - no-op when user_metadata.locale is already populated
  - no-op when getProfile returns null (no profile row yet)
  - no-op when profile.locale not in `kSupportedLocales` (e.g. 'fr')
  - `updateUserMetadata` failure does not promote profile to AsyncError
  - fires for 'en' too (proves it is not pt-specific)
  - `kSupportedLocales` matches `AppLocalizations.supportedLocales`

**Verification:**

- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean (0 issues)
- [x] 3408 unit + widget tests pass, 1 skipped, 0 failures. 25 integration
      tests fail for environment reasons (no live local Supabase) — same
      baseline as `main`, not regressions.
- [x] `make ci` end-to-end green (format + gen + analyze + test + android
      debug build) — opened PR #303
- [x] PR body includes
      `**QA pass pending — final coverage + E2E run after code review.**`

**Post-merge:** apply migration 00073 to hosted Supabase via
`npx supabase db push` so the legacy-user backfill lands in production.
Verify the email-template "Pre-existing user" verification case from
`docs/auth-email-templates/README.md` flips from `{{ else }}` to `pt` for
a sample legacy `profiles.locale = 'pt'` user.
