# Active workout set-row — critique, brief, and product pillars

This document grounds the three design directions. It merges the
**ui-ux-critic**'s craft critique (what's broken visually and structurally)
with the **product-owner**'s job-to-be-done critique (what's broken about the
lifter's experience), then states the emotional brief and three product
pillars every direction must satisfy.

---

## First impression (ui-ux-critic)

The set-row block is a plain data table wearing a purple coat. Strip the
colors and it is indistinguishable from Google Fit, Hevy, or any generic M3
exercise tracker generated from a template. Nothing signals *"you are in the
middle of a mythic training log."*

This is the most-used screen in RepSaga. A lifter sees it 30–60 times per
workout. Every friction point compounds. Every undifferentiated pixel is a
missed opportunity to feel like the rest of the product — Arcane Ascent
ranks, gold PR moments, RPG-grade typography.

---

## Six design failures (ui-ux-critic)

1. **The stepper buttons are too small and too ambiguous.** The `—` (minus)
   and `+` buttons on `WeightStepper` have a `minWidth: 32` constraint —
   exactly what BUG-019 flags as broken on 360dp screens. Between sets with
   one sweaty hand, the `—` icon on a 32dp target demands precision the user
   does not have under 90-second rest. The weight value tap area is
   `Flexible` — it will compress. This failure hurts most at the exact
   moment of maximum use: mid-workout, one hand free, 60 seconds left.

2. **The set-number badge teaches nothing.** A number in a faint-purple box
   labeled "T" (`setTypeAbbrWorking`) is not a recognizable affordance. That
   the dotted underline means "tap to copy last set" is invisible until you
   already know it. First-time users scan a mid-set edit and see a numeric
   label — not a control.

3. **The column headers (SÉRIE / PESO / REPS) are wasted chrome.** Three
   tiny uppercase labels in `textDim` color spend precious vertical real
   estate announcing what the user already knows after day one. They
   contribute nothing during a set.

4. **Completion state is invisible at a glance.** A Material `Checkbox` at
   18dp check size against a dark surface reads as either "on" or "off" —
   the state difference between a done set and a pending set is a
   single-pixel check mark. Mid-workout, between sets, a lifter cannot
   glance at the card and know "I have two left" without reading each row.

5. **The PR badge is stranded.** `PrChip` floats inline in the reps column,
   right of the stepper. On an ongoing set, it is rendered adjacent to
   blank reps — exactly when it matters most as motivation — but its
   placement is visually accidental rather than celebratory.

6. **"Adicionar Série" looks disabled.** The hotViolet outline against the
   `surface2` background fails the active-CTA test: it reads as secondary
   rather than the action you want after every set.

**BUG-018/019 explicit:** `Container constraints: minWidth: 40, minHeight:
40` on the set-number cell and `minWidth: 32` on stepper buttons are below
the 48dp Material minimum — confirmed in `set_row.dart:235–238` and
`weight_stepper.dart:142`.

---

## Five product problems (product-owner, JTBD perspective)

**Problem 1 — The completion gesture competes with the logging gesture for
the same thumb zone.** The checkbox (right side, 48×48) and the reps
stepper (center-right) are adjacent. Between sets, 90 seconds on the clock,
the user's right thumb is in the same horizontal band. BUG-019 confirms the
reps stepper buttons can compress to 32dp on 360dp screens (Samsung
A-series, Moto G — extremely common in the Brazilian mid-market). A misfire
on "complete set" when the user meant "+1 rep" ends the set before they're
done adjusting. This is not a tap-target problem alone — it's a *spatial*
conflict that exists even at correct sizes.

**Problem 2 — The set-type badge (N / AQ / D / F) adds visual weight
without being discoverable as interactive.** A user who receives the app
and wants to mark set 2 as a warmup will not discover long-press on the
number unless told. The information is there, but the affordance is hidden.
Intermediate lifters who structure warm-up sets are the exact users who
want this — and they will never find it. This is the kind of feature that
makes an app feel half-built.

**Problem 3 — The previous-session hint ("Anterior: 20kg × 5") disappears
the moment a set is completed.** The code at `set_row.dart:120–135`
deliberately hides the hint when the set is completed (or when current
values match last session). The user gets the hint only *before* they
decide what to lift, not *during* the set when they might want to confirm
"wait, did I do 20 or 22.5 last time?" Between sets with music loud and a
rest timer running, that reference is most useful, not least.

**Problem 4 — No visual state hierarchy between "completed set" and
"pending set."** A completed row looks almost identical to a pending row —
same row height, same text color, only the checkbox state changes. In a
5-exercise workout with 4 sets each, a lifter glancing at the screen cannot
immediately count how many sets remain. Strong solves this with a full-row
color fill on completion; Hevy uses a green tint on the row background.
RepSaga forces the user to read individual checkboxes. Under gym fatigue,
that cognitive load adds up.

**Problem 5 — The weight stepper requires two taps per increment and has
no visible direct-tap-to-type path.** At 22.5 kg → 25 kg, that is one tap.
But at 22.5 → 60 kg for a drop-set warmup transition, it is 75 taps on
"+". Hevy and Strong both allow tapping the weight value to open a numeric
keyboard. JEFIT also exposes a numeric field directly. `app_pt.arb` has
`enterWeight` / `enterReps` keys suggesting a modal input exists — but the
stepper-first UX hides it. A lifter changing load significantly between
exercises restarts the same grinding sequence every time.

---

## Emotional brief

RepSaga is not a productivity app that happens to live in the gym. It is
an RPG that uses the gym as its world. The active workout screen is the
**dungeon floor** — the place where the character earns XP and advances
rank. The screen should feel like a command interface in an underground
forge: efficient and dark, with the information architecture of a weapon
crafting table, not a spreadsheet.

When a São Paulo intermediate lifter — training 4×/week, probably at a
Smart Fit or a smaller local box, running a PPL split, listening to trap or
heavy metal — opens this screen, they are in execution mode. They do not
want to think. They want:

- the previous session's data presented as **a ready target to beat**;
- the completion gesture to feel like **a deliberate action**, not an
  accident;
- the PR moment, when it happens, to register as **a genuine reward
  signal** that is different from every other interaction in the app.

The screen should communicate: *"you are here to do work, and this
machine is built for exactly that."* Not clean and modern. **Iron and
precise.**

---

## Three product pillars

Every direction (A, B, C) must satisfy all three.

### Pillar 1 — Target state first, confirmation second

The set-row's job is to help the lifter confirm "I matched or beat last
session" *before* they complete the set, not after. The row should render
the previous session's weight and reps as the default starting state —
pre-filled, visible, faintly ghosted — so the user's action is
**edit-then-complete** rather than enter-then-complete.

When the current values match last session exactly, the row should show a
subtle match indicator (**not gold** — that is reserved for PRs per the
heroGold scarcity rule). The completion tap then becomes a *confirmation*,
not a data-entry step. This mirrors Strong's "pre-fill from last session"
behavior, but makes the match state explicit rather than implicit.

### Pillar 2 — Differentiate state at the row level, not the widget level

Completed sets and pending sets must be visually distinct **at the row
level** — meaning the entire row background changes, not just the
checkbox. This needs to use the Arcane Ascent palette correctly:

- **Completed row** — `surface2` background (one tier above `surface`, per
  the three-tier depth system) with a subdued primary-violet left border
  stroke, signaling "this is locked in."
- **Pending row** — default `surface`.
- **PR row** — the one exception: `heroGold` treatment, per the
  reward-scarcity rule. BUG-018/019 acceptance criteria require this
  treatment survives any redesign.

This gives the lifter a scannable vertical list — "three complete, one to
go" without reading anything.

### Pillar 3 — Separate the adjustment zone from the completion zone, spatially

The weight and reps inputs belong to the **left and center** of the row.
The completion action belongs to a **full-height right-side zone** that is
visually distinct from the input zone — not just a checkbox but a
swipe-able or large-tap target that reads as "done with this set."

This mirrors Boostcamp's right-side completion design and Hevy's
row-tap-to-complete pattern, but RPG-flavored: the completion zone uses
the primary-violet active color with a rune-stroke mark rather than a
plain checkbox, so the act of completing a set feels like **striking a
mark**, not filing a form. This spatial separation directly resolves
Problem 1 above and reduces misfire rate on 360dp devices without
requiring tap-target size changes.

---

## Three directions — theses

Full mockups in the sibling `direction-*.html` files. Open them in a
browser at desktop width — each renders the phone frame at 390×844 (iPhone
14 dimensions).

### Direction A — Runic Codex

Each exercise card is a scroll entry in a training grimoire. Set rows are
numbered runes inscribed in sequence. Completion is not checking a box —
it is **sealing the inscription**: the entire row background animates from
`surface` to a `surface2`-with-primary-left-bar state, and a brief
gold-to-cream shimmer fires on the numerals (uses `heroGold` exactly once,
scarce, meaningful). Tap-to-numpad input via inline bottom sheet — no
context switch. Most distinctive direction; closest to mythic identity.

### Direction B — Tactile Data Table *(designer recommendation)*

Preserves all-sets-visible density that intermediate-to-advanced lifters
actually want. The stepper buttons become `flex:1` of the full column
width — on a 390dp screen the weight column's minus/plus zones are each
~44dp wide and 56dp tall, **definitively fixing BUG-018 and BUG-019**
without any workaround. PR badge sits **above** the reps value (scannable
in under a second). Completed-row left border gives state legibility from
two meters away. Trade-off: leans closer to Hevy's vocabulary than to
pure Arcane Ascent mythos. RPG identity lives in the palette and
typography, not the layout.

### Direction C — One-Thumb Focus Mode

Radical simplification: one set hero at a time, completed sets compressed
into a strip above. 64px Rajdhani for the active set's weight and reps.
Swipe-to-adjust on the active values. 72dp impossible-to-miss complete
button. Most ambitious; fragments the muscle memory of lifters who scan
all sets simultaneously to track progression and decide whether to push
harder.

---

## Recommendation

Ship **Direction B (Tactile Data Table)**.

> Direction A is the most distinctive and the closest to the product's
> mythic identity, but it makes a risky bet: removing the steppers
> entirely and replacing interaction with a tap-to-numpad model means a
> lifter mid-set cannot make a quick weight correction with one thumb —
> they have to open a bottom sheet. That adds 1–2 seconds and a modal
> context switch on every adjustment. For a screen used 30–60 times per
> workout, that friction compounds badly.
>
> Direction C is genuinely innovative, but it fragments muscle memory —
> experienced lifters scan all sets simultaneously to track their
> progression and decide whether to push the next set harder. Hiding
> completed sets in a strip and showing one set at a time is a design
> imposition that fights how strong lifters actually think.
>
> Direction B does the thing that matters most: it makes the input
> targets physically impossible to miss. The PR badge above the reps
> value is scannable in under a second. The completed-row left border
> gives state legibility from two meters away. It preserves
> all-sets-visible density, which is what lifters actually want. The
> trade-off you accept: it leans closer to Hevy's vocabulary than to pure
> Arcane Ascent mythos. The RPG identity lives in the color palette and
> typography, not the layout. That is the right trade-off for the
> most-used screen in the app — identity belongs in celebrations and
> character progression, not in the friction of basic data entry.
>
> — ui-ux-critic, 2026-05-01

The product pillars (target-state-first, row-level state diff, spatial
separation of adjustment vs. completion) all map cleanly onto Direction B
and partially onto A. Direction C satisfies them in spirit but at the
cost of density — a worthwhile prototype to keep on the shelf if user
testing reveals one-handed use is dominant on Brazilian mid-market
devices.

---

## Files relevant to implementation

- `lib/features/workouts/ui/widgets/set_row.dart` — the widget under review
  (spatial layout: lines 203–374; hidden `_RpeIndicator`: lines 389–446)
- `lib/shared/widgets/weight_stepper.dart` — stepper constraints to fix
  (BUG-019: raise `minWidth` on step buttons from 32 to 40dp minimum;
  full-column-width zones eliminate the problem structurally in Dir B)
- `lib/core/theme/app_theme.dart` — palette tokens
  (`abyss`/`surface`/`surface2`/`heroGold`/`primaryViolet` at lines 25–66);
  three-tier surface depth + heroGold scarcity rule both apply
- `BUGS.md` — BUG-018 (set number 40dp), BUG-019 (stepper compression at
  360dp), BUG-020 (Finish button one-handed reach) at lines 419–447
- `lib/l10n/app_pt.arb` — all "Rotina/rotina" keys to rename per
  `naming-treinos-vs-rotinas.md` (lines 6, 175–178, 287–295, 300–303,
  366–383, 493–511)

---

## Post-Phase-20 validation audit — 2026-05-06

Phase 20 (PR #152) + three polish PRs (#158 pt-BR rename, #159 match
indicator, #160 set-type micro-label) were audited against this critique
and the five problems and three pillars from the original brief. The
audit was code-state only; the visual on-device pass is deferred to the
user's manual walkthrough.

### Status by original finding

| Problem / Pillar | Status | Resolution |
|---|---|---|
| Problem 1 — stepper/done spatial conflict | Resolved | `_DoneCell` 52dp fixed column, steppers in separate flex columns; structurally cannot compress into each other |
| Problem 2 — set-type badge undiscoverable | Partial | Persistent `tinyAbbr` micro-label (PR #160) signals type exists; long-press affordance still requires accidental discovery or tooltip |
| Problem 3 — hint vanishes after completion | Deferred | Suppressed on completed rows pending layout-stable fixed-height placeholder; root cause documented in `set_row.dart` `_shouldShowHint` doc comment |
| Problem 4 — no row-level state hierarchy | Resolved | 5-state stripe + done-col tint + value dim gives scannable at-a-glance differentiation |
| Problem 5 — no direct numpad path | Resolved | Value-zone tap opens `AlertDialog` with autofocus `TextField` on both steppers |
| Pillar 1 — target-state first | Resolved | Pre-fill from previous session + match indicator |
| Pillar 2 — row-level state diff | Resolved | 5-state matrix fully implemented |
| Pillar 3 — spatial separation | Resolved | Structurally enforced via column geometry |

### Net-new findings requiring follow-up

**Finding A — Bodyweight row renders a meaningless weight column [redesign-input]**

For `EquipmentType.bodyweight` exercises, the `_WeightStepperCell` renders
unconditionally, showing `0` in a 26sp primary-violet numeral occupying
flex-3 (60% of the input width). The resolver correctly excludes weight from
PR detection in bodyweight mode (`pr_row_state_resolver.dart` `isBodyweightOnly`
branch), but the row layout does not reflect this. The weight stepper is
noise the user must actively ignore; the reps column — the only meaningful
input — gets 40% of the space.

Recommended fix: pass an `isBodyweight` flag into `SetRow` (derivable from
the `equipmentType` on the parent exercise). When true, hide the
`_WeightStepperCell` and the weight column header, and expand the reps
column to `Expanded(flex: 1)`. The set-num cell and done-cell stay
unchanged.

**Finding B — Pending failure (FL) set label color reads as error state [redesign-input]**

`_setTypeLabelColor(SetType.failure)` returns
`AppColors.error.withValues(alpha: 0.55)` — the same error-red token used
for destructive actions. On a pending to-failure set the `FL` micro-label
renders in faded red, which conflicts with the gym-floor emotional register:
red = something wrong, not "this is a to-failure set." The effective color
clears on completion (dimmed to `onSurface.withValues(alpha: 0.45)`) so
the issue is pending-state only.

Recommended fix: use `AppColors.warning.withValues(alpha: 0.6)` for
`SetType.failure` on pending rows. Warning amber (`#FFB84D`) is tonally
distinct from heroGold (scarcity unaffected), distinct from the
success-green used for dropsets, and distinct from the error-red used for
destructive actions. It reads as "intense/max-effort" without signaling
breakage.

### Parked

**[v2-park] "Add set" OutlinedButton reads as secondary.** The button uses
`theme.colorScheme.primary.withValues(alpha: 0.3)` for the border (30%
violet), which is even quieter than the pre-Phase-20 design. Structurally
correct (full-width, 48dp tap floor, `isNew` lock prevents misfire) but the
visual weight says "optional" rather than "expected next step." Tolerable
for v1; revisit post-launch with telemetry on `sets per exercise` vs
`add-set taps`.

### Out of scope (deferred to user's manual on-device walkthrough)

- Pixel-perfect spacing on a real Brazilian-mid-market 360dp screen
  (Samsung A-series, Moto G).
- Haptic feedback timing on completion / set-type cycle.
- Animation curves on the celebration sequence.
- Real-thumb misfire rates between adjacent buttons under sweat.

These are the kinds of issues this code-state audit can't catch and need
human eyes on a real device.
