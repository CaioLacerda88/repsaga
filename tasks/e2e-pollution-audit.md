# E2E Test-Data Pollution Audit

Generated: 2026-05-04
Branch: fix/e2e-search-rpc-flakes
Context: PR #152 CONFIRMED cross-user-pollution failure surfaced; this audit scans all 23 spec files for similar patterns.

---

## CONFIRMED ADDITIONAL POLLUTION (Read This First)

Beyond the rank-up-celebration:825 case confirmed by the orchestrator, the audit found **one additional CONFIRMED pollution** and **five HIGH-risk pairs**. See Section 3.

The second confirmed pollution:

**`rpg-foundation.spec.ts` — `rpgFreshUser` shared across 5 describe blocks with no ordering guarantee between `rpg-foundation.spec.ts` and `saga.spec.ts`.**

- `saga.spec.ts:63` — "Saga — fresh user character sheet" — asserts `firstSetAwakensBanner` VISIBLE and all body-part rows at zero XP. Its `beforeEach` resets XP but does NOT delete `workouts`.
- `rpg-foundation.spec.ts:258` — "RPG foundation — first-workout XP applied" (18a-E2) — completes a bench press workout, writes XP to `body_part_progress`.
- If alphabetical execution order: `rpg-foundation.spec.ts` runs before `saga.spec.ts`. E2's bench workout creates a `workouts` row. `saga.spec.ts:63` beforeEach deletes `body_part_progress` + `xp_events` but NOT `workouts`. If `save_workout` triggers a `backfill_rpg_v1` re-run on next login (because `backfill_progress` was cleared but the workout row survived), XP re-accumulates before S1 asserts zero. Result: `firstSetAwakensBanner` is absent, test fails.
- This pair is **CONFIRMED-RISK** — the mechanism is identical to the rank-up case: one describe block writes server state that survives into another describe block's supposedly-clean baseline.

---

## Section 1 — User-to-Describe-Block Matrix

Only users that appear in **2+ describe blocks** are listed. Single-describe-block users are omitted (no pollution surface).

### smokePR (e2e-smoke-pr@test.local)

Seeded in global-setup: 100 kg × 5 bench press PR, completed workout "E2E Seed Workout".

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| smokePR | personal-records.spec.ts:69 | Personal records @smoke | 8 |
| smokePR | rank-up-celebration.spec.ts:815 | PR signal inline display @smoke | 1 |

### smokeWorkout (e2e-smoke-workout@test.local)

Seeded in global-setup: minimal profile + one prior workout (lapsed state).

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| smokeWorkout | workouts.spec.ts:30 | Workouts @smoke | 5 |
| smokeWorkout | rank-up-celebration.spec.ts:887 | Active workout chrome (Phase 18c) @smoke | 1 |

### rpgFreshUser (e2e-rpg-fresh@test.local)

Seeded in global-setup: profile row, zero workout history.

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| rpgFreshUser | rpg-foundation.spec.ts:258 | RPG foundation — first-workout XP applied @smoke | 1 |
| rpgFreshUser | rpg-foundation.spec.ts:353 | RPG foundation — re-save no double XP @smoke | 1 |
| rpgFreshUser | rpg-foundation.spec.ts:635 | RPG foundation — compound body-part attribution | 1 |
| rpgFreshUser | rank-up-celebration.spec.ts:531 | First awakening overlay @smoke | 1 |
| rpgFreshUser | saga.spec.ts:63 | Saga — fresh user character sheet @smoke | 1 |
| rpgFreshUser | saga.spec.ts:387 | Saga — stats deep-dive (fresh user) @smoke | 1 |

### rpgFoundationUser (e2e-rpg-foundation@test.local)

Seeded in global-setup: ~12 prior workouts across 6 weeks, multi-body-part XP.

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| rpgFoundationUser | rpg-foundation.spec.ts:150 | RPG foundation — backfill on first login @smoke | 1 |
| rpgFoundationUser | rpg-foundation.spec.ts:525 | RPG foundation — XP accumulates across workouts | 1 |
| rpgFoundationUser | saga.spec.ts:123 | Saga — foundation user character sheet @smoke | 1 |
| rpgFoundationUser | saga.spec.ts:176 | Saga — navigation @smoke | 5 |
| rpgFoundationUser | saga.spec.ts:291 | Saga — stats deep-dive @smoke | 3 |

### sagaIntroUser (e2e-saga-intro@test.local)

Seeded in global-setup: profile row, zero workout history, saga intro never dismissed.

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| sagaIntroUser | gamification-intro.spec.ts:31 | Gamification intro @smoke | 3 |
| sagaIntroUser | rpg-foundation.spec.ts:593 | RPG foundation — saga intro gate regression | 1 |

### smokeLocalization (e2e-smoke-localization@test.local)

Seeded in global-setup: profile with locale='pt', one prior workout (lapsed state).

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| smokeLocalization | localization.spec.ts:49 | Localization — pt-BR server-seeded boot @smoke | 4 |
| smokeLocalization | localization.spec.ts:312 | Localization — bottom nav no overflow @smoke | 1 |
| smokeLocalization | exercises-localization.spec.ts:35 | Exercise list localization @smoke | 4 |
| smokeLocalization | exercises-localization.spec.ts:247 | Exercise list pt locale filters and search | 3 |
| smokeLocalization | exercises-localization.spec.ts:369 | User-created exercise pt locale | 2 |

### smokeLocalizationEn (e2e-smoke-localization-en@test.local)

Seeded in global-setup: no locale seeded (defaults English), one prior workout.

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| smokeLocalizationEn | localization.spec.ts:220 | Localization — en-default language picker switch @smoke | 2 |
| smokeLocalizationEn | exercises-localization.spec.ts:159 | Exercise detail en locale @smoke | 2 |
| smokeLocalizationEn | workouts-localization.spec.ts:105 | Locale switch during workout | 1 |

### fullExercises (e2e-full-exercises@test.local)

No special seeding; standard profile + no workout history.

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| fullExercises | exercises.spec.ts:627 | Exercise library | ~12 |
| fullExercises | exercises-localization.spec.ts:215 | Exercise list en locale | 3 |
| fullExercises | exercises-localization.spec.ts:369 | User-created exercise pt locale (context B) | G1 only |

### smokeOfflineSync (e2e-smoke-offline-sync@test.local)

Seeded in global-setup: profile + one prior workout (lapsed state).

| user | spec.ts | describe block | tests |
|------|---------|----------------|-------|
| smokeOfflineSync | offline-sync.spec.ts:82 | Offline sync @smoke | 4 |
| smokeOfflineSync | offline-sync.spec.ts:273 | Offline sync — badge interaction | 1 |

---

## Section 2 — State Mutation Classification (Shared-User Describe Blocks Only)

### smokePR

**personal-records.spec.ts:69 — Personal records @smoke**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :80 | Workout-history-creating + PR-creating | 60 kg × 8 bench. May or may not beat seed (60 < 100 seed, so not max_weight PR; volume 480 may set max_volume if first run) |
| :106 | Workout-history-creating + PR-creating | 60 kg × 8, then 80 kg × 5 bench. 80 < 100 seed → no max_weight PR. max_volume for run A = 480 |
| :150 | Workout-history-creating + PR-creating | 60 kg × 8. Same as :80 |
| :172 | Read-only | Navigates to Records screen only |
| :189 | Read-only | Navigates to Records screen only |
| :264 | Workout-history-creating + PR-creating | 110 kg × 5 (workout A) then 130 kg × 5 (workout B). **max_weight escalates to 130 kg** |
| :309 | Workout-history-creating + PR-creating | Single workout: 995 kg × 5 set 1, 999 kg × 5 set 2. **max_weight escalates to 999 kg, max_volume to 4995** |
| :378 | Workout-history-creating + PR-creating | 60 kg × 8 bench |

**rank-up-celebration.spec.ts:815 — PR signal inline display @smoke**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :825 | Workout-history-creating + PR-creating | 105 kg × 5 bench (asserts beats prior PR). **ASSUMES max_weight < 105 kg at test start** |

### smokeWorkout

**workouts.spec.ts:30 — Workouts @smoke**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :39 | Workout-history-creating | 60 kg × 8 bench |
| :79 | Read-only | Home screen navigation check |
| :109 | Workout-history-creating | 60 kg × 8 bench |
| :153 | Workout-history-creating | 50 kg × 5 bench |
| :181 | Read-only (discards) | Workout discarded, no server write |

**rank-up-celebration.spec.ts:887 — Active workout chrome @smoke**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :896 | Workout-history-creating + possible-discard | Starts workout, asserts Finish button + FAB. Finishes or discards (finishWorkout called). 60 kg × 8 bench |

### rpgFreshUser

**rpg-foundation.spec.ts:258 — first-workout XP applied**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :259 | Workout-history-creating + RPG-state-creating | Resets RPG, then completes bench 60 kg × 8. Writes xp_events + body_part_progress |

**rpg-foundation.spec.ts:353 — re-save no double XP**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :354 | Workout-history-creating + RPG-state-creating | Resets RPG, inserts workout+sets directly, calls save_workout RPC twice. Writes xp_events + body_part_progress |

**rpg-foundation.spec.ts:635 — compound body-part attribution**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :636 | Workout-history-creating + RPG-state-creating | Resets RPG, inserts squat workout, calls save_workout. Writes xp_events + body_part_progress + workouts |

**rank-up-celebration.spec.ts:531 — First awakening overlay**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :549 | Workout-history-creating + RPG-state-creating | beforeEach calls `reseedRpgFreshUser()` (full delete of workouts/xp/body_part_progress/backfill_progress/weekly_plans). Test completes bench + squat, writes workouts + sets + xp |

**saga.spec.ts:63 — Saga — fresh user character sheet**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :98 | Read-only | Asserts firstSetAwakensBanner visible, body-part rows zero |

beforeEach at :63 deletes xp_events, body_part_progress, exercise_peak_loads, backfill_progress. Does NOT delete workouts or personal_records.

**saga.spec.ts:387 — Saga — stats deep-dive (fresh user)**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :419 | Read-only | Asserts stats deep-dive screen + vitality table |

beforeEach at :387 deletes xp_events, body_part_progress, exercise_peak_loads, backfill_progress. Does NOT delete workouts.

### rpgFoundationUser

**rpg-foundation.spec.ts:150 — backfill on first login**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :151 | RPG-state-creating | Triggers `runRetroBackfill` on login. Writes body_part_progress, xp_events |

**rpg-foundation.spec.ts:525 — XP accumulates across workouts**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :526 | Workout-history-creating + RPG-state-creating | Saves additional bench 60 kg × 8. Adds to body_part_progress |

**saga.spec.ts:123 — Saga — foundation user character sheet**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :136 | Read-only | Asserts Lvl > 1, no firstSetAwakensBanner |

**saga.spec.ts:176 — Saga — navigation**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| all 5 tests | Read-only | Navigation-only: gear icon, re-tap tab, Stats/Titles/History rows |

**saga.spec.ts:291 — Saga — stats deep-dive**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| all 3 tests | Read-only | Navigates to stats deep-dive screen, reads trend data |

### sagaIntroUser

**gamification-intro.spec.ts:31 — Gamification intro @smoke**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :41 | RPG-state-creating (Hive) | Dismisses saga intro, sets Hive `saga_intro_seen` flag |
| :104 | RPG-state-creating (Hive) | Dismisses saga intro, reloads, asserts flag persists |
| :144 | RPG-state-creating (Hive) | Dismisses saga intro, asserts nav renders |

Note: Hive is IndexedDB-backed and isolated per browser context. Cross-test Hive pollution is not possible via Supabase — each Playwright test gets a fresh browser context. Server-side for sagaIntroUser: no workout-creating mutation.

**rpg-foundation.spec.ts:593 — saga intro gate regression**

| test (line) | mutation type | details |
|-------------|--------------|---------|
| :594 | RPG-state-creating | Logs in, optionally dismisses saga intro, reads character sheet. Triggers backfill_rpg_v1 on login (zero workouts → 0 XP). No persistent mutation beyond backfill_progress |

### smokeLocalization

**localization.spec.ts:49, :312 — pt-BR boot + nav overflow**

| tests | mutation type |
|-------|--------------|
| all | Read-only — language display and nav layout checks |

**exercises-localization.spec.ts:35 — Exercise list localization @smoke**

| tests | mutation type |
|-------|--------------|
| all | Read-only — list display and search |

**exercises-localization.spec.ts:247 — Exercise list pt locale filters and search**

| tests | mutation type |
|-------|--------------|
| all | Read-only — filter + search result assertions |

**exercises-localization.spec.ts:369 — User-created exercise pt locale**

| test | mutation type | details |
|------|--------------|---------|
| G1 (context A) | Exercise-creating | Creates "Meu Exercício {timestamp}" custom exercise. Persists in exercises table |
| G2 | Exercise-creating | Creates "Levantamento Específico {timestamp}" custom exercise. Persists |

### smokeLocalizationEn

**localization.spec.ts:220 — en language picker switch @smoke**

| tests | mutation type | details |
|-------|--------------|---------|
| all | Profile-modifying | Switches locale from en→pt and back. Updates profiles.locale |

**exercises-localization.spec.ts:159 — Exercise detail en locale @smoke**

| tests | mutation type |
|-------|--------------|
| all | Read-only — exercise detail display |

**workouts-localization.spec.ts:105 — Locale switch during workout**

| test | mutation type | details |
|------|--------------|---------|
| :106 | Profile-modifying + Workout-history-creating | Switches locale mid-workout, saves or discards workout |

### fullExercises

**exercises.spec.ts:627 — Exercise library**

| tests | mutation type | details |
|-------|--------------|---------|
| ~12 tests | Exercise-creating / -modifying | Creates custom exercises, possibly edits/deletes them |

**exercises-localization.spec.ts:215 — Exercise list en locale**

| tests | mutation type |
|-------|--------------|
| all | Read-only — list display in en locale |

**exercises-localization.spec.ts:369 (context B) — User-created exercise pt locale**

| test | mutation type |
|-------|--------------|
| G1 context B | Read-only — RLS verification (must NOT see pt user's exercise) |

### smokeOfflineSync

**offline-sync.spec.ts:82 — Offline sync @smoke**

| tests | mutation type | details |
|-------|--------------|---------|
| OFFLINE-001..004 | Workout-history-creating (queued) | Completes workout with REST blocked. Queues in Hive. Syncs on restore — eventually writes to Supabase |

**offline-sync.spec.ts:273 — Offline sync — badge interaction**

| test | mutation type | details |
|------|--------------|---------|
| OFFLINE-005 | Workout-history-creating (queued) | Same pattern: blocks REST, queues workout |

---

## Section 3 — Pollution Risk Matrix

### User: smokePR

Spec execution order (alphabetical): `personal-records.spec.ts` runs BEFORE `rank-up-celebration.spec.ts`.

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| personal-records.spec.ts:309 | max_weight = 999 kg for barbell_bench_press | rank-up-celebration.spec.ts:825 | max_weight < 105 kg (needs 105 kg to be a new PR) | **CONFIRMED** |
| personal-records.spec.ts:264 | max_weight = 130 kg | rank-up-celebration.spec.ts:825 | max_weight < 105 kg | **CONFIRMED** (same mechanism, :309 would have run first so 130 < 999, moot after :309 runs) |
| personal-records.spec.ts:80 | max_weight may accumulate (60 < 100 seed) | rank-up-celebration.spec.ts:825 | No specific assumption broken | LOW |

### User: smokeWorkout

Spec execution order (alphabetical): `rank-up-celebration.spec.ts` runs AFTER `workouts.spec.ts`.

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| workouts.spec.ts:39 | +1 completed workout, bench 60 kg × 8 | rank-up-celebration.spec.ts:887 | Only assumes lapsed state (has prior workouts) — this is fine | LOW |
| workouts.spec.ts:109 | +1 completed workout | rank-up-celebration.spec.ts:887 | Same — no meaningful state assumption | LOW |

### User: rpgFreshUser

Spec execution order: `rank-up-celebration.spec.ts` (alpha-after `rpg-foundation.spec.ts`) and `saga.spec.ts` (alpha-after `rank-up-celebration.spec.ts`).

| source test (file:line) | mutation left behind | target test (file:line) | state assumed | risk |
|-------------------------|---------------------|-------------------------|---------------|------|
| rpg-foundation.spec.ts:259 (E2) | workouts row + body_part_progress XP | saga.spec.ts:63 beforeEach | Deletes xp/body_part_progress/backfill_progress but NOT workouts; backfill_progress re-cleared means next login may re-trigger backfill and re-write XP from surviving workout row | **CONFIRMED-RISK** |
| rpg-foundation.spec.ts:259 (E2) | workouts row | saga.spec.ts:387 beforeEach | Same gap: deletes xp/body_part_progress but not workouts; save_workout workouts survive | HIGH |
| rpg-foundation.spec.ts:354 (E3) | workouts row + body_part_progress | saga.spec.ts:63 | Same gap | HIGH |
| rpg-foundation.spec.ts:636 (E6) | workouts row + body_part_progress | saga.spec.ts:63 | Same gap | HIGH |
| rank-up-celebration.spec.ts:549 (S3) | workouts row + body_part_progress (reseedRpgFreshUser runs in beforeEach — cleans before each test) | saga.spec.ts:63 | reseedRpgFreshUser DOES delete workouts; it cleans before the S3 test runs. But after S3 runs it leaves a workout behind. saga.spec.ts:63 beforeEach does NOT delete workouts | HIGH |
| saga.spec.ts:387 beforeEach (S11) | Deletes xp/body_part_progress; leaves workouts intact from prior runs | saga.spec.ts:63 beforeEach (S1) | S11 runs before S1 only if Playwright execution order places it first; alphabetical within-file ordering puts S1 (line 63) before S11 (line 387), so this direction is LOW within-file | LOW |

### User: rpgFoundationUser

Spec execution order: `rpg-foundation.spec.ts` before `saga.spec.ts`.

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| rpg-foundation.spec.ts:526 (E4) | Additional bench workout + more XP in body_part_progress | saga.spec.ts:136 (S2) | Asserts Lvl > 1 — more XP only makes this easier to pass | LOW |
| rpg-foundation.spec.ts:151 (E1) | backfill writes body_part_progress | saga.spec.ts:136 (S2) | Asserts Lvl > 1 — same direction, not harmful | LOW |
| saga.spec.ts tests | Navigation-only, no mutation | All other rpgFoundationUser tests | Read-only — no risk | LOW |

### User: sagaIntroUser

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| gamification-intro.spec.ts:41 | Hive `saga_intro_seen` flag (per browser context, isolated) | rpg-foundation.spec.ts:594 | Needs saga intro overlay to appear (or handles absence via try/catch) | LOW |
| rpg-foundation.spec.ts:594 | Possibly triggers backfill_rpg_v1, writes 0 XP (no workouts) | gamification-intro.spec.ts:41 | Needs intro overlay to appear; backfill is a no-op for zero workouts | LOW |

### User: smokeLocalization

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| exercises-localization.spec.ts:369 (G1, G2) | Custom exercise rows in exercises table | localization.spec.ts and exercises-localization.spec.ts:35 filter/search tests | Search tests look for specific known exercises; custom exercises with timestamp names won't pollute search results | LOW |
| exercises-localization.spec.ts:369 (G2) | exercises table row | exercises-localization.spec.ts:247 filter tests | Same — timestamp names isolated | LOW |

### User: smokeLocalizationEn

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| localization.spec.ts:220 | profiles.locale set to 'pt' then reset to 'en' (or left at 'pt' on failure) | exercises-localization.spec.ts:159 (en locale tests) | Assumes locale is 'en'; if localization.spec.ts leaves locale='pt', exercise detail tests see pt content | **MEDIUM** |
| localization.spec.ts:220 | Same | workouts-localization.spec.ts:105 (locale switch test) | Expects a known starting locale; locale='pt' from prior test may confuse the switch direction | MEDIUM |

### User: fullExercises

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| exercises.spec.ts:627 (Exercise library — creates custom exercises) | Custom exercise rows visible in user's list | exercises-localization.spec.ts:215 (en locale list) | Looks for default exercises by name; custom exercises are visible but shouldn't collide with default-exercise assertions | LOW |
| exercises-localization.spec.ts:369 (context B — RLS check) | Read-only, no mutation | exercises.spec.ts:627 | No risk | LOW |

### User: smokeOfflineSync

| source test | mutation left behind | target test | state assumed | risk |
|-------------|---------------------|-------------|---------------|------|
| offline-sync.spec.ts:82 OFFLINE-001..004 | Queued workouts eventually synced to Supabase (workout rows) | offline-sync.spec.ts:273 OFFLINE-005 | Assumes predictable badge state; prior test sync completion within same file is not guaranteed | MEDIUM |

---

## Section 4 — Fix Plan

### A. Helper API — `test/e2e/helpers/test-data-reset.ts`

```typescript
// Functions needed (signatures only — implementation is the separate phase):

// 1. Surgical PR reset for one exercise
resetExerciseHistoryForUser(adminClient, userId, exerciseSlug): Promise<void>
//   DELETE sets WHERE workout_exercise_id IN (workout_exercises WHERE exercise_id = ?)
//   DELETE workout_exercises WHERE workout_id IN (workouts WHERE user_id = ?)
//      AND exercise_id = ?
//   DELETE personal_records WHERE user_id = ? AND exercise_id = ?
//   DELETE workouts WHERE user_id = ? AND id NOT IN (remaining workout_exercises)
//   (Surgical: only removes workouts that had ONLY this exercise)

// 2. Broad reset — all workout history + PRs for one user
resetAllPrsForUser(adminClient, userId): Promise<void>
//   DELETE sets (cascade via workout_exercise_id FK)
//   DELETE workout_exercises (cascade)
//   DELETE workouts WHERE user_id = ?
//   DELETE personal_records WHERE user_id = ?
//   Note: exercise_peak_loads is a separate table — must be cleared too

// 3. Seed a single PR row
seedPrForUser(adminClient, userId, exerciseSlug, weight, reps): Promise<void>
//   INSERT personal_records (user_id, exercise_id via slug lookup, record_type='max_weight', value=weight, reps, achieved_at=now)

// 4. Reset RPG state (workouts + xp + body_part_progress + backfill_progress)
resetRpgStateForUser(adminClient, userId): Promise<void>
//   Identical to the inline resets in rank-up-celebration.spec.ts — centralise them

// 5. (Optional) Reset locale
resetLocaleForUser(adminClient, userId, locale='en'): Promise<void>
//   UPDATE profiles SET locale = ? WHERE id = ?
```

### B. Per-Describe-Block Insertions

**Tier 1 — Ship in PR #152 (CONFIRMED + HIGH risk)**

| describe block | helper(s) to add | where | seed data after reset |
|----------------|-----------------|-------|----------------------|
| rank-up-celebration.spec.ts:815 "PR signal inline display" | `resetExerciseHistoryForUser(admin, userId, 'barbell_bench_press')` + `seedPrForUser(admin, userId, 'barbell_bench_press', 100, 5)` | `beforeEach` | 100 kg × 5 PR (matches global-setup seed contract) |
| saga.spec.ts:63 "Saga — fresh user character sheet" | add `await admin.from('workouts').delete().eq('user_id', userId)` | existing `beforeEach` (after existing xp/body_part_progress deletes) | None |
| saga.spec.ts:387 "Saga — stats deep-dive (fresh user)" | same workouts delete | existing `beforeEach` | None |

**Tier 2 — Follow-up PR (MEDIUM risk)**

| describe block | helper(s) to add | where | priority |
|----------------|-----------------|-------|---------|
| exercises-localization.spec.ts:159 "Exercise detail en locale" | `resetLocaleForUser(admin, userId, 'en')` | `beforeEach` | Prevents locale bleed from localization.spec.ts:220 |
| workouts-localization.spec.ts:105 "Locale switch during workout" | `resetLocaleForUser(admin, userId, 'en')` | `beforeEach` | Same |
| offline-sync.spec.ts:273 "Offline sync — badge interaction" | `resetAllPrsForUser` or targeted workout cleanup | `beforeEach` | Prevents accumulated workout rows from confusing badge state |

**Tier 3 — Deferred (LOW risk, only if a flake surfaces)**

| describe block | concern | action |
|----------------|---------|--------|
| smokeWorkout in rank-up-celebration.spec.ts:887 | More accumulated workouts → longer RPG overlay chains → timing flakes | Add `test.slow()` guard (already present in sibling tests) |
| rpgFoundationUser in all saga.spec.ts blocks | E4 adds a bench workout, incrementally increases XP | Foundation tests already accommodate accumulating XP (assert `>=` not exact values) |

### C. Estimated Implementation Cost

- Helper functions: 5 (including `resetRpgStateForUser` which replaces inline resets in rank-up-celebration.spec.ts)
- Describe blocks requiring `beforeEach` changes: 5 (Tier 1: 3, Tier 2: 2 mandatory + 1 optional)
- CI runtime impact: Tier 1 adds ~3 admin API calls per test × 1 test (S5) = ~1–2 s. Tier 2 adds ~1 call per test × 3 tests = ~2–3 s total. Negligible.
- Risk of cleanup breaking something: LOW. Admin client deletions via service role bypass RLS. FK cascade order (sets → workout_exercises → workouts) is safe. `personal_records.set_id` is NULLABLE (set on insert, nullable on PR-only rows) — no FK block on deleting sets first if `ON DELETE SET NULL` is configured; verify this before implementation.

### D. Recommended Rollout

**Tier 1 — Same PR as #152 e2e fix:**
1. Create `test/e2e/helpers/test-data-reset.ts` with `resetExerciseHistoryForUser` + `seedPrForUser` + `resetRpgStateForUser`.
2. Add `beforeEach` to `rank-up-celebration.spec.ts:815` (PR signal inline display) that calls `resetExerciseHistoryForUser` + `seedPrForUser`.
3. Add `await admin.from('workouts').delete().eq('user_id', userId)` inside existing `beforeEach` at `saga.spec.ts:63` and `saga.spec.ts:387`.
4. Run Stage 1: `FLUTTER_APP_URL= npx playwright test specs/rank-up-celebration.spec.ts specs/saga.spec.ts specs/personal-records.spec.ts --max-failures=1 --retries=0`.

**Tier 2 — Follow-up PR (within 1 sprint):**
1. Add `resetLocaleForUser` to the helper file.
2. Apply to `exercises-localization.spec.ts:159` and `workouts-localization.spec.ts:105`.
3. Apply targeted cleanup to `offline-sync.spec.ts:273`.

**Tier 3 — Deferred (on flake):**
- Monitor `smokeWorkout` accumulated state in rank-up-celebration S6.
- No action until a flake surfaces.

---

## Section 5 — Out-of-Scope Risks

**Hive (IndexedDB) state cannot be reset via admin API.** The `sagaIntroUser` relies on Hive's `saga_intro_seen` flag being absent to show the overlay. Since Playwright creates a fresh browser context per test, Hive is isolated automatically. This works correctly today. If a test ever needs to test "already-seen" state across a real page reload within the same context (which `gamification-intro.spec.ts:104` does), it depends on Playwright's same-context storage persistence — not a Supabase pollution risk, but a hard-to-reset dependency. Not fixable with the helper pattern; must stay as same-context reload tests.

**`exercises.spec.ts` custom exercises accumulate across test runs.** The Exercise library describe block (`fullExercises`) creates custom exercises in some tests. These persist across runs (global teardown only deletes auth users, not their exercises). On re-runs the exercise list grows. Tests searching by name use timestamps or unique strings, so collision is unlikely — but if any test asserts an exact exercise count, it will fail on the second run. Audit found no count assertions, but this should be monitored.

**`manage-data.spec.ts` uses a throwaway user.** The Account deletion describe block creates a fresh user per run via `createThrowawayUser`. This is self-contained and not affected by the helper pattern.

**`personal_records.set_id` FK nullability.** `resetExerciseHistoryForUser` needs to delete sets before workout_exercises. If `personal_records.set_id` has `ON DELETE RESTRICT` (not `SET NULL`), deleting a set that is referenced by a PR row will fail. The global-setup seeds `set_id` into personal_records. Verify the FK constraint before implementing the helper. If `RESTRICT`, the helper must delete `personal_records` before `sets`.
