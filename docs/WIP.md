# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## fix/notes-keyboard-layout — keyboard layout fixes (PR #326)

Two device-verified keyboard-layout bugfixes (root causes confirmed via on-device
`debugPrint`/GlobalKey measurement, not assumption).

**A. History-detail notes edit sheet** — rendered with a keyboard-sized dead gap
+ overflow. Root cause: `showModalBottomSheet(isScrollControlled:true)` already
bounds the sheet to `screen − keyboard`; the code ALSO added `viewInsets.bottom`
as bottom padding → **double-counted the keyboard** (on a real 384×832 device the
Column was squeezed to 79dp). Fix: drop the manual inset; `SingleChildScrollView`
shrink-wraps small / scrolls tall on any device. Cluster `notes-sheet-double-kbd-inset`.

**B. Routine edit screen** — exercise cards below the focused notes field stopped
painting under the keyboard (empty card-shaped band tracking the IME), and the
form reflowed on focus. Root cause: `SingleChildScrollView` body mis-repainted on
keyboard resize. Fix: `ListView` body (lazy viewport repaints) + `resizeToAvoidBottomInset:
false` (keyboard overlays, screen behind untouched — the requested behavior).

- [x] Sheet: remove double keyboard inset, `SingleChildScrollView`, `maxLines:6`
- [x] Sheet test: device-faithful harness (maxH = screen−kbd + viewInsets), proven to FAIL on the bug
- [x] Routine: `ListView` body + `resizeToAvoidBottomInset: false`
- [x] Routine test: keyboard-overlay + ListView contract pins (+ device-verified note)
- [x] On-device verification: History ✅ and Routine ✅ confirmed by user
- [x] Verify gate: format/analyze clean, 3553 tests pass, Android debug build OK
- [x] PR opened (#326), reviewer signed off on the original sheet change
- [ ] Re-review of the corrected sheet fix + routine fix
- [ ] QA gate (E2E selector impact) + merge

Files: `notes_edit_sheet.dart`, `create_routine_screen.dart`,
`notes_edit_sheet_test.dart`, `create_routine_screen_test.dart`
Clusters: `notes-sheet-double-kbd-inset`, `visual-only-bugs-escape-value-tests`
