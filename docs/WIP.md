# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 32 PR 32a — Locale leaks + meus-treinos + routine translations

Per PROJECT.md §3 Phase 32 → PR 32a. Branch: `fix/phase-32a-locale-routine-translations`.

### Grammar + ARB

- [x] `lib/l10n/app_pt.arb` myRoutines / myRoutinesSection — `MINHAS TREINOS` → `MEUS TREINOS`
- [x] Add ARB keys to both `app_en.arb` + `app_pt.arb`:
  - `homeActionHeroStartEyebrow` (en: `START`, pt: `INICIAR`)
  - `homeActionHeroFreeEyebrow` (en: `FREE WORKOUT`, pt: `TREINO LIVRE`)
  - `homeActionHeroWelcomeEyebrow` (en: `WELCOME`, pt: `BEM-VINDO`)
- [x] `make gen` to regen `app_localizations_*.dart`
- [x] `lib/features/workouts/ui/widgets/action_hero.dart` — replace hardcoded eyebrows at L219/L255/L283 with l10n reads
- [x] Verify `git grep -E 'TREINO LIVRE|INICIAR|BEM-VINDO|MINHAS TREINOS' lib/` returns zero hits in `lib/`

### Routine translations table

- [x] Create `supabase/migrations/00067_workout_template_translations.sql`:
  - Adds `template_slug` column to `workout_templates` + backfills 9 default rows
  - `CREATE TABLE workout_template_translations (...)` keyed on (template_slug, locale)
  - RLS: SELECT for `authenticated`, no other policy (service-role bypass for writes)
  - Seeds `en` + `pt` rows for 9 default templates
- [x] `lib/features/routines/data/workout_template_translation_resolver.dart` + wired into `RoutineRepository._applyTemplateTranslations` (en fallback cascade)
- [x] Created `scripts/check_workout_template_translation_coverage.sh` with `--self-test` mode; recognizes UPDATE backfill + INSERT default-template shapes
- [x] Wired the gate into `.github/workflows/ci.yml` as `workout-template-translation-coverage-check` job

### Tests

- [x] Widget test: `test/widget/features/workouts/ui/widgets/action_hero_localization_test.dart` (6 tests, 3 branches × 2 locales)
- [x] Unit test: `test/unit/features/routines/data/template_translation_resolver_test.dart` (6 tests, pt-row / en-row / en-fallback / omit / multi-slug / short-circuit)
- [x] Updated `test/unit/features/routines/data/routine_repository_test.dart` + `routine_repository_cache_test.dart` to inject the new resolver dep
- [x] E2E: extended `test/e2e/specs/routines-localization.spec.ts` with smoke tests for `MY ROUTINES` / `MEUS TREINOS` headers + pt default-template names
- [x] CI gate self-tested: `scripts/check_workout_template_translation_coverage.sh --self-test` PASSes the complete fixture and FAILs the pt-missing fixture

### Verification + ship

- [x] `dart analyze --fatal-infos` clean (0 issues)
- [x] All affected widget + unit tests pass locally
- [ ] `make ci` green including new gate
- [ ] PR description includes `**QA pass pending — final coverage + E2E run after code review.**`
- [ ] Apply migration to hosted Supabase post-merge per CLAUDE.md step 12
