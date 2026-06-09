# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Post-session share-card copy fixes

Branch: `fix/share-class-name`

- [ ] **Item 4 — Untranslated RPG class name on share/picture overlay** _(in-progress)_
  - Bug: `_buildShareCardStrings` in `post_session_screen.dart` rendered the raw
    `characterClassSlug` uppercased instead of the localized class name
    (cluster `slug-rendered-as-display-name`).
  - Fix: map slug → `CharacterClass` enum (fallback `initiate`), localize via
    `localizedClassName(cls, l10n)`, then uppercase. Reuses the existing
    `_buildClassChangeCut` pattern.
  - Render sites updated: achievement-frame class name + discreet-variant
    eyebrow/hero (all derive from the single `className` local).
  - DESPERTOU flag → RESOLVED in-cycle (same one-line change). The discreet
    class-change eyebrow hardcoded the pt literal "DESPERTOU."; swapped to the
    EXISTING localized key `b3ClassSubline` ("AWAKENED." en / "DESPERTOU." pt) —
    the same standalone subline the B3 cinematic cut already renders. No new ARB
    keys. Share card now follows app locale end-to-end (only REPSAGA wordmark is
    brand-constant).
- [ ] Item 5 — _(left intact; not part of this PR)_
