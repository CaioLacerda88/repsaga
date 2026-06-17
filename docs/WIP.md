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
- [x] l10n en+pt: `vitalityCardioDecaySubtitle`, `statsCardioDecayExplainer`,
      `statsCardioDecayExplainerDismiss` (+ `@key` descriptions). Legend reuses
      existing `muscleGroup*` + `cardioTrackLabel`.
- [x] Subtitle slot: cardio-only decay subtitle in `vitality_table.dart` (teal-dim,
      ellipsis, 320dp fit). Strength rows keep §8.4 state copy.
- [x] One-time explainer: `cardio_decay_explainer_dismissal_provider.dart` (Hive
      `userPrefs`, presence==dismissed; clone of age-prompt provider) +
      `CardioDecayExplainerBanner` widget + wire into `stats_deep_dive_screen.dart`.
- [x] Chart legend: `VitalityTrendChartLegend` below the chart — 7 chips, cardio teal.
- [x] Widget tests: cardio row shows subtitle (strength rows don't); explainer
      shows when not-dismissed, hides+persists after dismiss (one-time); 320dp
      no-overflow (subtitle + banner); legend cardio chip present.
- [x] `make gen-l10n` + `dart format` + `dart analyze --fatal-infos` + `make test` green.
- [ ] reviewer → QA (selector-impact only; stats surface) → ship. No migration.

### QA follow-up: cardio TITLE drift (renders "Cardio", should be "Conditioning")
The `cardioTrackLabel` dartdoc names 3 title sites: Saga rail cardio row, vitality
table cardio cell, cardio rank-up celebration eyebrow. Several rendered the generic
`localizedBodyPartName(cardio)` = "Cardio" instead. Fix every cardio TITLE site;
leave muscle-group/picker/exercise-name renders ("Cardio"/"Treadmill") as-is.
- [x] `vitality_table.dart` — cardio row TITLE → `cardioTrackLabel` (the 38e-bis miss).
      Extend the existing `isCardio` branch from the subtitle to the title.
- [x] Saga rail (`character_card.dart` + `character_sheet_screen.dart`) — RESOLVED:
      cardio is filtered OUT of the `BodyPartRankRow` loop and rendered via
      `CardioProgressRow(trackLabel: cardioTrackLabel)` → already "CONDITIONING".
      `body_part_rank_row.dart` never receives cardio → no change needed (38e claim correct).
- [x] Rank-up celebration eyebrow — `post_session_controller.dart` `bodyPartLabels`
      map resolved cardio via `localizedBodyPartName` = "Cardio"; now special-cases
      cardio → `cardioTrackLabel`. Feeds every B2 rank-up/cascade/elevated cut eyebrow.
- [x] Tests pin the regression: vitality table cardio title = "Conditioning" (+ strength
      row keeps muscle-group name); rail row stays correct via CardioProgressRow.
- [x] `dart format` + `dart analyze --fatal-infos` (0) + `flutter test` green.
