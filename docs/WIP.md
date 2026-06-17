# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38e-bis — Cardio stats decay COPY (deferred from 38e split-valve)

Branch `feature/phase38e-bis-cardio-decay-copy`. Per `docs/PROJECT.md` §2. Copy-only
follow-up: the cardio vitality row + 7th trend-chart line already ship (38e); this adds
the EXPLANATORY copy for cardio's faster (3-wk) decay. Design already approved in the
38e mockup Surface 2 — no new mockup/boundary inventory needed.

### Scope (copy + small widget; no migration, no contract change)
- **Per-row decay subtitle** on the cardio vitality table row: "Conditioning fades in
  ~3 weeks" / pt "Condicionamento cai em ~3 semanas" (strength rows keep their normal
  state copy). Lives in the cardio row's subtitle slot in `vitality_table.dart`.
- **One-time stats decay explainer** banner near the table on the stats deep-dive:
  "Cardio conditioning decays faster than strength — train it weekly to hold the line."
  / pt. Slim teal-hairline, dismissible (Hive flag like other one-time notes, e.g.
  the bodyweight/age dismissal pattern). Shows on `stats_deep_dive_screen`.
- **Chart legend cardio chip** label on `vitality_trend_chart` (the 7th line's legend
  entry reads as cardio/teal).
- l10n en+pt (+ `@key` descriptions); `make gen-l10n`; keep `arb_completeness_test` green.

### Checklist
- [ ] tech-lead TDD: subtitle slot (cardio-only) + explainer banner (one-time dismissal
      provider) + chart legend chip; l10n en+pt.
- [ ] Widget tests: cardio row shows subtitle (strength rows don't); explainer one-time/
      dismiss logic; 320dp no-overflow (subtitle is longer than strength state copy).
- [ ] `make gen-l10n` + `dart format` + `dart analyze --fatal-infos` + `make test` green.
- [ ] reviewer → QA (selector-impact only; stats surface) → ship. No migration.
