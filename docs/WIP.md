# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Routine builder — drag-handle reorder (replace #357 arrows)

**Branch:** `feature/routine-builder-drag-reorder`
**Source:** User used #357's arrow reorder and asked for drag instead. ui-ux-critic CORRECTED its earlier
"arrows over drag" rec — drag is feasible without breaking eager-render/E2E (the Weekly Plan editor
already ships it). User chose **drag handle** (not long-press-whole-card — would fight the card's steppers).
**Pipeline:** mockup confirm → tech-lead TDD → reviewer → QA (E2E selector swap + reorder coverage) → visual gate → ship.
**No model/schema/migration** (order = JSONB array order, unchanged).

### Scope
- [x] Replace #357's AppBar reorder toggle + per-card up/down arrows with **always-on drag-handle reorder**.
      Converted the eager `.map` `Column` → a **shrink-wrapped `ReorderableListView.builder`** nested in the existing
      `SingleChildScrollView` (`shrinkWrap: true` + `physics: NeverScrollableScrollPhysics()` → builds ALL children
      eagerly, preserves E2E/a11y reach). Mirrors Weekly Plan + `_onReorder` (incl. the `newIndex--` adjustment) +
      `buildDefaultDragHandles: false`.
- [x] **Drag handle:** `Icons.drag_handle` at the header trailing edge, LEFT of the ×, `textDim`, 48×48
      via `ReorderableDragStartListener(index:)`. Only shows when `_exercises.length > 1`.
      `Semantics(container: true, identifier: 'create-routine-drag-handle', label: dragToReorder)`.
- [x] **proxyDecorator** lift: elevation 8 + subtle `hotViolet @ 0.4` border on the picked-up card (no motion).
- [x] Keys: each item reuses `ObjectKey(entry)` (the #357 key, unique even with dupes).
- [x] **a11y:** relies on `ReorderableListView`'s built-in semantic move-actions; drag handle carries the label.
      No visible arrows.
- [x] **Removed** the #357 `_reorderMode` state usages, `_toggleReorderMode`/`_moveExercise` refs, AppBar reorder
      toggle, per-card arrow branch, reorder-mode border tint + body-collapse. (Prior partial attempt had left these
      referenced-but-undefined → file did not compile; now fully converted.)
- [x] Cardio cards reorder identically (handle in shared `_header`).
- [x] ARB `dragToReorder` ("Drag to reorder"/"Arraste para reordenar") — already present in both ARBs + generated.
- [ ] **E2E (QA):** RE-ADD `create-routine-reorder-toggle` selector; add
      `create-routine-drag-handle`. Rewrite routines.spec.ts:781-851 (drag gesture) — Weekly Plan reorder E2E is the
      template. Flow change → QA re-runs vs fresh build.

### REFINEMENT v3 — reorder MODE + collapsed cards (drag whole card)
The user refined the design AGAIN: keep the CustomScrollView + SliverReorderableList + cacheExtent
auto-scroll foundation, but swap the always-on drag handle for a reorder MODE.
- [x] Remove the always-on `Icons.drag_handle` from the card header (`_header`); normal cards are NOT draggable.
- [x] AppBar action `IconButton` toggling `_reorderMode` (`Icons.reorder` ↔ `Icons.done`), gated `_exercises.length > 1`,
      `create-routine-reorder-toggle` identifier, `reorderExercisesTooltip`/`exitReorderModeTooltip`.
- [x] `_ExerciseCard` gets a `reorderMode` bool: true → header-only collapsed variant (title + pill(s) +
      trailing `Icons.drag_handle` `textDim` affordance, faint `hotViolet @ 0.4` border tint), wrapped in
      `ReorderableDragStartListener(index:)` (whole card draggable, immediate). false → full card, no listener.
- [x] Both cardio + strength/bodyweight collapse to the same header-only shape in reorder mode.
- [x] Collapsed drag affordance: `Semantics(identifier: 'create-routine-drag-handle', label: dragToReorder)`.
- [x] proxyDecorator lift stays for the dragged collapsed card; ObjectKey(entry) keys stay.
- [x] Tests: toggle present >1 / absent ≤1; entering mode collapses (Sets/Rest hidden, title+pill remain);
      done restores; onReorder persists through Save; normal mode = full + not draggable.
- [x] ⚠️ **device check finding (NOW FIXED):** edge-auto-scroll did NOT work with the nested
      `NeverScrollableScrollPhysics` inner list. `SliverReorderableList` resolves its auto-scroll target via
      `Scrollable.of(context)` → the INNER list's own (non-scrolling) Scrollable, never the outer
      `SingleChildScrollView`. **Fix:** the screen body is now a SINGLE `CustomScrollView` (the one scroll
      authority) hosting a bare `SliverReorderableList` for the cards + `SliverToBoxAdapter`s for header/add
      button. `Scrollable.of(context)` from the sliver now resolves to the CustomScrollView itself →
      `EdgeDraggingAutoScroller` drives the page → drag-to-edge auto-scrolls natively.
- [x] **Eager-render reach preserved** via a generous `cacheExtent: 3500` on the CustomScrollView (realistic
      routines ≤~12 cards stay fully built/in the AOM — same reach the old eager Column gave). Cluster:
      listview-lazy-build-breaks-e2e. Very long routines (>cacheExtent) lazy-cull off-screen; E2E uses small
      routines so unaffected.
- [x] Mockup panel update (`docs/phase-38-mockups.html` "Phase 38h-v2" panel 3 → drag handle + lifted state) → user chose handle
- [ ] Visual gate (handle at 320/360/412 — no header overflow with name+pill+[≡][×]; lifted state)
- [x] Tests: drag-handle group (5 tests) + new persistence-through-Save assertion. 51/51 in file, 3837 suite green.

Phase 38 ✅ COMPLETE + post-38 shipped (#352, #353, #355, #357). Open §2: post-launch cardio recalibration.
