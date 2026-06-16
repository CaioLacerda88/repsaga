# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38d — Age capture (birth-year)

Branch `feature/phase38d-age-capture`. Per `docs/PROJECT.md` §2 → "Phase 38 —
remaining stages" + the plan `~/.claude/plans/noble-stirring-scroll.md` → "PR 38d"
+ the product-owner + ui-ux-critic scoping (2026-06-15/16). Net-new user-facing
surface → **ui-ux-critic mockup + user approval BEFORE build, + visual-verification
gate before merge.**

**Goal:** collect birth-year so cardio scores on real age-decade norms instead of
the age-35 fallback. 38c added nullable `profiles.date_of_birth`; this adds the UI
that populates it. Cardio scoring already reads the column server-side.

### Locked decisions (user, this session)
1. **Birth-YEAR granularity** — stored `YYYY-01-01` in the existing
   `profiles.date_of_birth date` column (NO migration change; formula keys on
   age-decade, so year is the minimal stable representation = LGPD data-minimization).
2. **Optional** — age-35 fallback is a valid steady state; **never gates cardio XP**.
3. **Backfill prompt = post-session summary** — one-time dismissible (Hive flag,
   `bodyweight_prompt_coordinator` pattern); fires after a cardio session when DOB
   is NULL; settings row always available regardless.
4. **Privacy = LGPD Art. 6 consent** (like avatars), **NOT Art. 11 sensitive** (unlike
   gender/bodyweight) → point-of-collection disclosure + privacy-policy §2 row +
   data-export inclusion; **NO Hive consent toggle** (do not clone `BodyweightConsentToggle`).
5. **Control = branded birth-year wheel** (`ListWheelScrollView`, years
   `currentYear−18 … currentYear−100`, default rests on `currentYear−35` so
   skip==fallback; ≥18 floor STRUCTURAL — wheel can't represent under-18, never
   re-asks the signup age-gate). NO Material calendar (over-collects month/day).
6. **No onboarding step** (highest friction, zero day-zero payoff — cardio invisible
   until 38e).

### Boundary inventory (filled via Explore — implementation may start)
- **Profile model** `lib/features/profile/models/profile.dart` — Freezed, `@JsonSerializable(fieldRename: snake)`, `Profile.fromJson` (`:30-77`). Add `dateOfBirth DateTime?` (snake `date_of_birth`). ⚠ it's a Postgres `date`, NOT `timestamptz` — the `createdAt`/`onboardedAt` precedent serializes a FULL timestamp (`profile.g.dart:17-19,35`); DOB needs a **date-only `@JsonKey` converter** (`YYYY-MM-DD`), not `.toIso8601String()`.
- **Write path** `profile_repository.dart` `upsertProfile(...)` (`:65-124`, omit-on-null per field) — add `DateTime? dateOfBirth` → `if (dateOfBirth != null) 'date_of_birth': <date-only>`. UI watches `profileProvider` (`profile_providers.dart:41`); editor sheets call `upsertProfile` directly then `ref.invalidate(profileProvider)`.
- **Settings insert point** `profile_settings_screen.dart` — after the Gender section, at `:149` (before Weekly goal). Clone the Gender `profileAsync.when(data/loading/error → GenderRow(profile:))` block (`:144-148`).
- **Row+sheet grammar to clone = `gender_row.dart`** (row `:42-83` id `profile-gender-row`; `showModalBottomSheet<…>(isScrollControlled:true)` `:90-99`; Save→`upsertProfile`→`invalidate`→`pop` `:144-149`; Cancel `:255-262`). Use gender's **inline disclosure banner LOOK** (`:187-226`, `info_outline` + copy) BUT **decision #4 = no consent provider** — DOB is Art. 6, so it's a pure point-of-collection disclosure (show when value==null), NOT a Hive-gated consent toggle. Button styles `core/theme/dialog_button_style.dart`.
- **Post-session prompt** `lib/features/workouts/ui/post_session/post_session_screen.dart` — one-shot analog of `_fireMountAnalytics()` (`:182-221`, `_analyticsFired` flag, post-frame in initState `:130-134`); gate to cardio sessions (`post_session_controller.dart:344/379/389` `bp==BodyPart.cardio`) with NULL DOB. Dismissal: clone `bodyweight_prompt_dismissal_provider.dart` (`Notifier<bool>` over Hive `userPrefs`, presence==dismissed; survives cache wipes). Coordinator pattern: `bodyweight_prompt_coordinator.dart maybeShow(...)` (`:80-113`).
- **l10n** `lib/l10n/app_{en,pt}.arb` + `make gen-l10n`; each key needs a paired `@key` desc; completeness guard `test/unit/core/l10n/arb_completeness_test.dart`. Precedent: `genderLabel`/`genderConsentBanner` (`app_en.arb:2447+`).
- **Data export** `data_export_service.dart` — exports the FULL profile row via `select()` (`:178-185`), so `date_of_birth` is auto-included; **no code change**, just add a test assertion (`data_export_service_test.dart`).
- **Test factories** `test/fixtures/test_factories.dart:73-103` (`TestProfileFactory.create` — add `dateOfBirth` param + `date_of_birth` key); raw `Profile(...)` test constructors at `onboarding_gate_test.dart:162,187` + `router_refresh_listenable_test.dart:45,99,128` (safe — adding optional field). Model tests to extend: `profile_model_test.dart`, `profile_repository_test.dart`.
- **Age-gate coherence** — signup `auth-age-confirmation` (`login_screen.dart:530-566`) is a boolean 18+ checkbox (no year captured); birth-year input is independent but the wheel's min year implies ≥18. Never re-ask the gate.
- **No existing Dart DOB field** (38c added only the SQL column + server read + AGE_FALLBACK=35 mirror in `cardio_xp_calculator.dart:84`).

### Pipeline checklist
- [ ] Boundary Explore → fill the inventory above.
- [ ] ui-ux-critic mockup: add AgeRow + AgeEditorSheet (birth-year wheel) + post-session
      age prompt to `docs/phase-38-mockups.html`; ui-ux-critic critique → **USER APPROVAL**.
- [ ] tech-lead TDD: `Profile.dateOfBirth DateTime?` (model + repo + serialization);
      `AgeRow` + `AgeEditorSheet` (wheel, structural ≥18 floor, clear-to-NULL) in
      profile settings after Gender; post-session one-time prompt (Hive dismissal flag);
      l10n en+pt; privacy-policy §2 DOB row; `DataExportService` includes date_of_birth.
- [ ] Tests: Profile serialization; AgeRow/AgeEditorSheet widget states + ≥18 floor +
      clear-to-NULL + textScaler on wheel; post-session prompt one-time/dismiss logic;
      age-derivation. E2E (flow change): set-age-in-settings + first-cardio-prompt flow.
- [ ] `make gen` + `dart format` + `dart analyze --fatal-infos` + `make test` green.
- [ ] reviewer → fixes → QA gate (E2E flow change → write/update specs, run them).
- [ ] **Visual-verification gate** (new surface): 320/360/412 dp (+ textScaler 1.3 corner)
      vs the mockup; foundation + fresh users.
- [ ] Verify before PR → PR → ship. (No migration → no hosted push.)

### Edge cases (surface in mockup + tests)
Wheel item-extent vs large textScaler (cap visible items / size off scaled metric);
empty "Not set" state reads non-alarming (no warning icon / incomplete-profile nag);
clearing a previously-set value; gender-NULL coherence; never re-ask the 18+ gate.
