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

- [ ] `lib/l10n/app_pt.arb:199` — `MINHAS TREINOS` → `MEUS TREINOS`
- [ ] `lib/l10n/app_pt.arb:313` — `MINHAS TREINOS` → `MEUS TREINOS`
- [ ] Add ARB keys to both `app_en.arb` + `app_pt.arb`:
  - `homeActionHeroStartEyebrow` (en: `START`, pt: `INICIAR`)
  - `homeActionHeroFreeEyebrow` (en: `FREE WORKOUT`, pt: `TREINO LIVRE`)
  - `homeActionHeroWelcomeEyebrow` (en: `WELCOME`, pt: `BEM-VINDO`)
- [ ] `make gen` to regen `app_localizations_*.dart`
- [ ] `lib/features/workouts/ui/widgets/action_hero.dart` — replace hardcoded eyebrows at L219/L255/L283 with l10n reads
- [ ] Verify `git grep -E 'TREINO LIVRE|INICIAR|BEM-VINDO|MINHAS TREINOS' lib/` returns zero hits

### Routine translations table

- [ ] Create `supabase/migrations/0006X_workout_template_translations.sql`:
  - `CREATE TABLE workout_template_translations (template_slug TEXT NOT NULL, locale TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY (template_slug, locale))`
  - RLS: SELECT public, INSERT/UPDATE/DELETE service_role only
  - Seed `en` + `pt` rows for the 5 existing templates (slugs from migration 00014)
- [ ] Modify the default-routine fetch path (likely `routine_repository.dart` or a Supabase view) — join on `(template_slug, locale)` with `'en'` fallback
- [ ] Create `scripts/check_workout_template_translation_coverage.sh` mirroring `check_exercise_translation_coverage.sh` shape — fail if any default template seed lacks both en+pt
- [ ] Wire the gate into `.github/workflows/ci.yml`

### Tests

- [ ] Widget test: pump `action_hero.dart` under en + pt; assert resolved eyebrow strings (no hardcoded PT in en render, no hardcoded EN in pt render)
- [ ] Unit test: routine name resolver returns pt for pt locale, en for en, en fallback for unknown
- [ ] E2E: Treinos screen in en shows `MY ROUTINES`, in pt shows `MEUS TREINOS`; fresh user with default routines sees pt names in pt locale
- [ ] CI: verify the new gate script returns non-zero when a seed row lacks pt

### Verification + ship

- [ ] `make ci` green including new gate
- [ ] PR description includes `**QA pass pending — final coverage + E2E run after code review.**`
- [ ] Apply migration to hosted Supabase post-merge per CLAUDE.md step 12
