# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 30 — Post-session "after-battle" screen (held — awaiting authorization)

**Status:** Concept B locked + all 11 design questions resolved + 3-PR
decomposition chosen. **User reviewing implementation plan before
tech-lead dispatch.**

**Mockup:** `docs/post-session-screen-mockup.html` (in main since PR #251 swept it in incidentally).

**3-PR decomposition** (when user authorizes):
- PR 30a: post-session screen + state machine + 7 cut widgets (XpCut/BodyPartCut/PRCut/RankUpCut/LevelUpCut/ClassChangeCut/TitleCut/SummaryPanel) + router + finish_workout_coordinator wiring + tests
- PR 30b: share card (offscreen 1080×1920 RepaintBoundary + share_plus 9:16 + golden test)
- PR 30c: deprecate `pr_celebration_screen.dart` + migrate E2E selectors/widget tests

**Resume condition:** User comes back with "dispatch PR 30a" / "adjust X" / "park entirely".
