# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 31 — Post-Phase-30 overlay + summary refinement

> Canonical spec: `docs/post-phase-30-design-exploration.html` (8 proposals, 4 per surface) + `docs/post-phase-30-research.md` (product-owner research brief). Locked directions:
>
> - **Overlay → D3 Achievement Frame.** Diagonal `ClipPath` collars top + bottom cut into the photo. 4dp side bars: left in dominant-BP hue, right in `hotViolet`. Body-part identity encoded in chrome structure. Replaces Variant A (Minimal Strip) + Variant B (Full-Bleed Collars) as the single photo-overlay treatment.
> - **Post-battle summary → S2 Mission Debrief.** Named lift rows (top exercises by XP contribution) + segmented XP-by-BP bar + per-BP rank delta + next-target callout. Fills the `Spacer()` gap at `post_session_summary_panel.dart:212` (the empty real estate the user flagged after the cinematic).
>
> Source: locked picks `2026-05-25` (post Phase 30 ship at `f5ce0a1`).

### Locked decisions (2026-05-25)

1. **Variant toggle retired.** D3 Achievement Frame is the single overlay treatment for the photo path. Retire `ShareCardVariantA` + `ShareCardVariantB` + their tests + 3 goldens + the `share-variant-toggle` E2E selector + the `SegmentedButton` on `SharePreviewScreen`. Discreet path (no-photo) stays unchanged.
2. **Top-K lift rows = 4 + footer.** S2 Mission Debrief renders top 4 lifts by XP contribution desc (tiebreak alphabetical by exercise name, mirroring `PostSessionChoreographer._buildPrCut`). On 5+ exercise sessions: "+N outros exercícios" footer row in textDim.
3. **Phase numbering = Phase 31 standalone.** Gets its own §3 In-flight entry; eventual §4 Completed Phases entry. Treated as a discrete pre-Launch UI refinement phase.
4. **Class-change top-collar = new class name only.** D3 top collar reads "BULWARK" (or whichever new class slug). The "DESPERTOU" cinematic framing stays in the B3 Class-Change Cut. Left side bar swaps to `heroGold` (avoids both bars collapsing to `hotViolet` — the right bar is already `hotViolet`, so reusing it on the left would erase the dual-bar identity contract).

### Code impact summary

**Files created:**
- `lib/features/workouts/ui/post_session/share/variants/share_card_achievement_frame.dart` — the new D3 overlay widget. Replaces Variant A + Variant B in role.
- `lib/features/workouts/ui/post_session/summary/mission_debrief_section.dart` — the new S2 summary section. Composes lift rows + segmented XP bar + per-BP rank deltas.
- `lib/features/workouts/ui/post_session/summary/widgets/lift_row.dart` — single-row component for the debrief table. Reusable.
- `lib/features/workouts/ui/post_session/summary/widgets/xp_segmented_bar.dart` — the proportional segmented horizontal bar (one segment per BP, width ∝ XP delta share).
- `lib/features/workouts/domain/session_lift_summary.dart` — Freezed model. Carries `(exerciseId, exerciseName, bodyPart, hue, peakWeightKg, peakReps, xpContribution, isPR)`. Drives `MissionDebriefSection`.
- `test/unit/features/workouts/ui/post_session/share/variants/share_card_achievement_frame_test.dart`
- `test/unit/features/workouts/ui/post_session/summary/mission_debrief_section_test.dart`
- `test/unit/features/workouts/ui/post_session/summary/widgets/lift_row_test.dart`
- `test/unit/features/workouts/ui/post_session/summary/widgets/xp_segmented_bar_test.dart`
- `test/unit/features/workouts/domain/session_lift_summary_test.dart`

**Files modified:**
- `lib/features/workouts/ui/post_session/post_session_state.dart` — add 3 fields:
  - `Map<BodyPart, int> bpXpDeltas` (already computed in `PostSessionController._buildInitial()` lines ~100-107 per PO research; needs persistence)
  - `Map<BodyPart, int> bpRankAfter` (same)
  - `List<SessionLiftSummary> topLifts` (new — projection of session's exercises by XP contribution; computed in controller's `_buildInitial`)
- `lib/features/workouts/ui/post_session/post_session_controller.dart` — `_buildInitial()` projects `topLifts` from the in-progress workout's exercises + sets + XP attribution. Persists the 2 maps that were previously local-only.
- `lib/features/workouts/ui/post_session/summary/post_session_summary_panel.dart` — replace `Spacer()` at line 212 with `MissionDebriefSection`. The eyebrow + next-step hook above the new section becomes the section's first row (consolidate).
- `lib/features/workouts/ui/post_session/share/share_card_renderer.dart` — drop Variant A / Variant B dispatch; dispatch is `{ achievementFrame, discreet }`.
- `lib/features/workouts/ui/post_session/share/share_preview_screen.dart` — remove A↔B `SegmentedButton`. Single-variant header. Discreet path still toggles when "Sem foto" picked.
- `lib/features/workouts/domain/share_payload.dart` — `ShareCardVariant` enum: `{ achievementFrame, discreet }`. Drop `minimalStrip` + `fullBleed`. Update `ShareCardCta`/`SharePayloadCta` extensions accordingly.
- `lib/features/workouts/ui/post_session/summary/share_cta_button.dart` — no behavioral change; verify the share-sheet open path still references the new enum values.
- `lib/features/workouts/ui/post_session/share/share_card_typography.dart` — drop `variantAPreview` / `variantAExport` typography maps; add `achievementFramePreview` / `achievementFrameExport` maps (see §4 below).
- `lib/l10n/app_en.arb` + `app_pt.arb` — new keys:
  - `postSessionDebriefEyebrow` ("SESSION REPORT" / "RELATÓRIO DA SESSÃO")
  - `postSessionLiftMore` (n-aware: "+1 more exercise" / "+N more exercises" / "+1 outro exercício" / "+N outros exercícios")
  - `postSessionRankUpEyebrow` (the existing `nextStepEyebrow` may need a sibling for the secondary callout if Q1 #2 confirms the "top 2 closest rank-ups" extension)
  - Verify whether `shareCardMinimal` / `shareCardBold` ARB keys are referenced anywhere; delete if not.
- `test/e2e/helpers/selectors.ts` — drop `shareVariantToggle` selector (toggle UI removed).
- `test/e2e/specs/share_flow.spec.ts` — remove the variant-toggle test (already `test.skip` on web for picker-harness reasons; now obsolete entirely).
- `test/e2e/specs/post_session.spec.ts` — add assertions for Mission Debrief section presence + lift-row content.

**Files deleted:**
- `lib/features/workouts/ui/post_session/share/variants/share_card_variant_a.dart`
- `lib/features/workouts/ui/post_session/share/variants/share_card_variant_b.dart`
- `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_a_test.dart`
- `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_b_test.dart`
- Their two existing goldens at `test/unit/features/workouts/ui/post_session/share/goldens/share_card_variant_a_baseline.png` + `share_card_variant_b_pr.png` + `share_card_variant_a_max_drag_offset.png` (the QA-added max-drag golden). 3 goldens deleted.

### Typography decisions

Two render trees, same source-of-truth file (`share_card_typography.dart`). Export typography is for the 1080×1920 JPEG (social-feed target); preview typography is what the user sees on the phone at 360dp.

**D3 Achievement Frame — EXPORT (1080×1920):**

| Element | Font | Size | Weight | Tracking | Color |
|---|---|---|---|---|---|
| Top-collar class name (e.g. "BULWARK") | Rajdhani | 36px | 700 | +0.04em | textCream |
| Top-collar saga eyebrow ("SAGA 76") | Barlow Condensed | 20px | 600 | +0.22em | textDim |
| Bottom-collar XP hero ("+618 XP") | Rajdhani | 64px | 700 | -0.02em | textCream |
| Bottom-collar lift detail ("95kg × 5 · Supino") | Rajdhani | 28px | 700 | +0.04em | textCream (heroGold if PR) |
| Bottom-collar BP rank ("Peito · Rank 18") | Barlow Condensed | 20px | 600 | +0.22em | dominantHue |
| Wordmark "REPSAGA" | Rajdhani | 18px | 700 | +0.24em | textDim |
| Side bars | n/a | 12px (4dp × 3.0pixelRatio) | n/a | n/a | dominantHue (left) / hotViolet (right) |

**D3 Achievement Frame — PREVIEW (360dp screen):**

| Element | Size | Notes |
|---|---|---|
| Top-collar class name | 24sp | Rajdhani 700 +0.04em |
| Top-collar saga eyebrow | 11sp | Barlow Condensed 600 +0.22em |
| Bottom-collar XP hero | 38sp | Rajdhani 700 -0.02em |
| Bottom-collar lift detail | 16sp | Rajdhani 700 +0.04em |
| Bottom-collar BP rank | 12sp | Barlow Condensed 600 +0.22em |
| Wordmark | 11sp | Rajdhani 700 +0.24em |
| Side bars | 4dp | absolute |

Top collar height: **84dp preview / 252px export**. Bottom collar height: **130dp preview / 390px export**. Photo letterbox: remaining ~38% of card height. (Numbers tuned so collars don't overcrowd the photo on a 9:16 card.)

**S2 Mission Debrief — summary panel (360dp screen, abyss background):**

| Element | Size | Notes |
|---|---|---|
| Section eyebrow ("RELATÓRIO DA SESSÃO") | 11sp | Barlow Condensed 600 +0.22em, textDim |
| Lift-row exercise name | 14sp | Barlow body, textCream |
| Lift-row weight × reps | 16sp | Rajdhani 700 -0.02em, textCream (heroGold if PR) |
| Lift-row "PR" flag | 11sp | Rajdhani 700 +0.04em, heroGold, +6dp left of weight |
| Lift-row BP hue dot | 8dp | filled circle, dominantHue, left-anchored |
| XP segmented bar | 6dp height | full panel-width minus side padding |
| Segment label (BP name under segment) | 10sp | Barlow Condensed 600 +0.20em, hue-colored |
| Per-BP rank delta row ("Costas · Rank 11 → 12") | 13sp | Barlow Condensed 600 (BP name) + Rajdhani 700 (numbers) |
| Next-target callout | 14sp (label) + 16sp (numeric) | Barlow + Rajdhani mix; primaryViolet hue |
| "+N more exercises" footer | 11sp | Barlow Condensed 600 +0.20em, textDim, centered |

### Screen real-estate plan

Common Android viewports we must support (per CLAUDE.md):

| Width | Device class | D3 collar heights | Debrief vertical budget |
|---|---|---|---|
| 320dp | Galaxy A05 / older budget | Top 76dp / Bottom 116dp (compressed 10%) | ~360dp between cinematic exit + CTAs |
| 360dp | Galaxy A mid / Pixel 6a | Top 84dp / Bottom 130dp (nominal) | ~400dp |
| 412dp | Galaxy S22+ / Pixel 6+ | Top 84dp / Bottom 130dp (no scale-up; absolute) | ~440dp |

D3 collar geometry uses `ClipPath` with proportional vertices (relative to card height), so the collars scale naturally. The bars stay at absolute 4dp regardless of screen.

Mission Debrief vertical budget (sum of rows at 360dp):
- Section eyebrow: 11sp + 12dp gap = ~22dp
- 4 lift rows × 32dp each = 128dp
- "+N more" footer: 11sp + 6dp gap = ~22dp (only on 5+ exercise sessions)
- XP segmented bar: 6dp + 16dp segment labels = ~22dp
- Per-BP rank delta block (3 rows on average): 3 × 24dp + 8dp gap = ~80dp
- Next-target callout: 16sp + 6dp gap = ~28dp

**Total ~280-302dp**, leaving ~100dp of breathing space above the share + continue CTAs on a 360dp viewport. On 320dp the lift-row count compresses to 3 (footer captures the rest), bringing the budget to ~250dp.

### Edge cases — Overlay (D3 Achievement Frame)

| Case | Handling |
|---|---|
| No photo (user tapped "Sem foto · só a saga") | Routes to Discreet variant (unchanged). |
| Class-change session | Top collar shows new class name (e.g. "BULWARK"); no "DESPERTOU" suffix (Q4 above). LEFT side bar swaps to `heroGold` (right bar is `hotViolet`; reusing it on the left would collapse the dual-bar identity contract). |
| Multiple PRs | Bottom-collar lift detail shows the HERO PR (`shared prScore` helper from PR 30c). Other PRs surface in S2 debrief, not on the share card. |
| Dominant BP null (no XP earned — pathological) | Left side bar falls back to `hotViolet` (existing pattern in `share_payload.dart:dominantHue`). |
| Long exercise name in lift detail | Truncate with ellipsis at `bottom-collar width minus XP-number width`. Lift detail is single-line. |
| Long class slug (rare; class names are short) | Truncate with ellipsis if exceeds top-collar width. Class slugs are ≤ 10 chars by spec. |
| 320dp viewport | Collars compress 10% vertically; typography sizes unchanged (still readable per UX-critic typography map). |
| Photo drag-to-reframe at extreme offset | Existing `ClipRect` from PR 30c bug fix clamps photo to card bounds — confirmed already wired. |
| Mystery glyph from PR 30c device verification | The Variant A baseline golden showed a top-right glyph artifact in CanvasKit. D3 has no top-right text (top collar is class name centered) — this artifact category should naturally disappear. Re-verify on device. |

### Edge cases — Mission Debrief (S2)

| Case | Handling |
|---|---|
| Baseline session (no PR, no rank-up, single BP) | Render: eyebrow, 1-3 lift rows, single-segment XP bar (1 hue block), single per-BP rank delta row showing progress fraction within rank (no rank-up). Next-target callout shows the existing single hook. No PR flags. Section still feels substantive — fills the void. |
| Single-exercise session | XP bar is 1 segment (full width, dominant-BP hue). 1 lift row. Per-BP rank delta is 1 row. |
| 5+ exercises trained | Top 4 by XP contribution; "+N more exercises" footer row. (Q2 default.) |
| All XP on 1 BP | XP segmented bar is 1 color block (no segmentation visible). Single BP rank delta row. |
| Multiple PRs | Lift rows tagged with PR flag (heroGold) per row that had a PR. Hero PR is the row at the top by XP contribution. |
| No PR + no rank-up + 0 closest-rank-up | Next-target callout uses the existing `dominantXpToNextRank` field (always populated when the user has at least 1 active BP, which is always true post-onboarding). |
| Closest-rank-up at exactly 0 XP from threshold (post-session rank-up just fired) | The B3 RankUp cut already played in cinematic. Mission Debrief shows the achieved rank in the per-BP delta row ("Costas · Rank 11 → 12 ✓"). Next-target callout points to the NEXT closest rank, not the one just achieved. |
| BP rank delta row count = 0 (impossible — at least 1 BP earned XP if `setsCount > 0`) | If somehow 0, hide the delta block entirely; lean on next-target callout. |
| Long Brazilian exercise names ("Levantamento Terra Romeno") | Lift row wraps to 2 lines if name doesn't fit at 14sp Barlow. Row height grows from 32dp → 48dp. Truncate at 2 lines max. |
| 320dp viewport | Lift row count drops from 4 to 3; "+N more exercises" footer absorbs the rest. Per-BP rank delta rows wrap their text to 2 lines if BP name + rank-number is too wide (unlikely; BP names short). |
| Empty-session guard (0 sets — already gated by post-session screen entry) | Mission Debrief never renders; screen short-circuits to the empty-session sheet (existing PR 30a behavior). |

### Implementation passes (commit groups for overload prevention)

#### Pass 1 — Domain layer + state plumbing
1. Add `bpXpDeltas`, `bpRankAfter`, `topLifts` to `PostSessionState`. Freezed regen.
2. `PostSessionController._buildInitial()` projects all 3 from in-progress workout (the 2 maps are already local — just persist; `topLifts` is new — project from session's sets via existing XP attribution path).
3. New `SessionLiftSummary` Freezed model + 5-case unit tests (single exercise / multiple / all-PR / no-PR / 5+ exercises with "more").
4. Update `SharePayload.fromPostSessionState` if needed — does the overlay's lift-detail need a new field on `SharePayload`? It currently has `pr: SharePayloadPr` which carries `(exerciseName, weightKg, reps)`. That's enough for D3's bottom-collar lift detail row. **No SharePayload signature change.**
5. Existing tests that build `PostSessionState` fixtures need fixture updates for the 3 new fields. Track the broken tests + update.

Commit: `feat(workouts): persist per-BP XP/rank deltas + topLifts on PostSessionState (Phase 31 Pass 1)`.

#### Pass 2 — D3 Achievement Frame overlay
1. New `share_card_achievement_frame.dart`. Two collars (`ClipPath` with diagonal polygon vertices) + photo letterbox + 4dp side bars. Composes content via `ShareCardStrings` (l10n-parameterized per existing pattern).
2. Update `share_card_typography.dart` — add `achievementFramePreview` + `achievementFrameExport` maps per §typography above.
3. Update `ShareCardRenderer` to dispatch on the new `ShareCardVariant.achievementFrame` value.
4. Update `ShareCardVariant` enum: `{ achievementFrame, discreet }`.
5. Delete `share_card_variant_a.dart` + `share_card_variant_b.dart` + their tests + 3 goldens.
6. Update `SharePreviewScreen`: remove A↔B `SegmentedButton`. Single header.
7. Update E2E selector + spec (drop variant-toggle test).
8. New goldens for D3 Achievement Frame: 3 cases (baseline / PR / class-change) at 1080×1920.
9. Widget tests for the new variant (8-10 cases mirroring Variant A's coverage: hue accent, PR conditional, class-change override, side-bar positioning, ClipPath geometry, drag-offset preservation).

Commit: `feat(workouts): D3 Achievement Frame share-card overlay (Phase 31 Pass 2)`.

#### Pass 3 — S2 Mission Debrief summary section
1. New `lift_row.dart` widget. Constructor: `(exerciseName, weightKg, reps, hue, isPR, l10n)`. 32dp default height; 48dp when name wraps. Widget tests for: render, PR flag, BP hue dot, long-name wrap, 320dp viewport.
2. New `xp_segmented_bar.dart`. Constructor: `(segments: List<({BodyPart bp, int xp, Color hue})>)`. Proportional widths, labels under each segment. Widget tests for: 1-segment / 2-segment / 4-segment / 0-segment defensive / total-zero defensive.
3. New `mission_debrief_section.dart`. Composes: eyebrow + lift rows + segmented bar + per-BP rank delta rows + next-target callout. Constructor takes `(state: PostSessionState, l10n)`. Widget tests for: baseline session / PR session / multi-PR / rank-up / 5+ exercises (footer) / 1-BP all-XP / class-change.
4. Update `post_session_summary_panel.dart`: replace `Spacer()` at line 212 with `MissionDebriefSection(state: …, l10n: …)`. Move the existing eyebrow + hook + prDetailRow / classChangeRow / rankUpOverflow / titleEquipRow into the debrief section OR keep them above and let the debrief section render below (decide during implementation — leaning toward consolidating the next-step hook INTO the debrief and dropping the separate `prDetailRow` etc. since the debrief surfaces all that data structurally).
5. ARB keys added.
6. E2E spec `post_session.spec.ts` assertions for the debrief section.

Commit: `feat(workouts): S2 Mission Debrief summary section (Phase 31 Pass 3)`.

#### Pass 4 — Final gates + visual verification

> **Pass 4 closeout: deferred to ship gate.** Visual verification + final `make ci` + physical-device pass run as part of the ship sequence (CLAUDE.md pipeline steps 9-11), NOT as a discrete commit on the branch. There is no `chore(workouts): Phase 31 closeout` commit — the gates below are the orchestrator's responsibility once code review + QA have signed off.

Gates run by the orchestrator:

1. `dart format .`
2. `dart analyze --fatal-infos`
3. 3 style scripts clean
4. `flutter test test/unit test/widget --exclude-tags golden` green (expected delta: + ~30-40 new tests; - ~30 deleted Variant A/B tests; net roughly even)
5. `flutter build apk --debug`
6. Web visual capture at 320 / 360 / 412dp (rerun `visual_30b.spec.ts` adapted to PR 30b's preview → now 31's preview + Mission Debrief)
7. Physical-device verification on Samsung S25 Ultra (the same device that surfaced the PR 30c bugs):
   - D3 overlay reads as "present" on the photo at arm's length, gym lighting
   - Mission Debrief fills the post-cinematic void; no awkward empty space
   - Lift rows readable; XP segmented bar reads as a meaningful info graphic
   - PR row gold flag visible
   - 320dp emulator pass (if user runs an emulator) OR document the 320dp risk if device-only

### Boundary inventory — completed 2026-05-25 (Explore agent dispatch)

#### Boundary 1 — `PostSessionState` field additions (additive; minimal churn)

- **Direct construction sites:** none. `PostSessionState` is built only inside `PostSessionController._buildInitial()`.
- **Carrier of the soon-to-be-persisted maps:** `PostSessionParams` → `FinishWorkoutCoordinator:395-421` reads `bpDeltas` (already exists); test harness in `test/widget/.../post_session_screen_routing_test.dart:61-74` accepts `bpXpDeltas`.
- **Controller:** `post_session_controller.dart:100-120` — `bpXpDeltas` already a local; `bpRankAfter` constructed at lines 100-107; both passed to `PostSessionChoreographer.build()` at 117-118. Persistence to state = trivial Freezed addition.
- **Test fixtures updating `SharePayload.fromPostSessionState(...)`** (must pass `bpRankAfter` on top of existing `bpXpDeltas`):
  - `test/unit/features/workouts/domain/share_payload_test.dart` — 10 test cases (lines 56, 90, 131-370)
  - `test/unit/features/workouts/ui/post_session/share/share_preview_screen_test.dart:77-88`
  - `test/unit/features/workouts/ui/post_session/summary/post_session_summary_panel_test.dart:55`
  - `test/widget/features/workouts/ui/post_session/summary/post_session_summary_panel_golden_test.dart:172`
- **`topLifts` field is brand-new** — no existing consumers; rendering surface is the S2 Mission Debrief (Pass 3). Project from raw set logs in controller's `_buildInitial()`.

**Action: 4 test files updated for `bpRankAfter` (+1 file for `topLifts` once the field is rendered). No production widget rewrites needed for Boundary 1.**

#### Boundary 2 — `ShareCardVariant` enum reshape

`enum ShareCardVariant { minimalStrip, fullBleed, discreet }` → `enum ShareCardVariant { achievementFrame, discreet }`.

- **Definition:** `lib/features/workouts/domain/share_payload.dart:30` — update enum + docstrings.
- **Switch sites:**
  - `lib/features/workouts/ui/post_session/share/share_card_renderer.dart:184-226` — master switch. Delete `minimalStrip` case (line 196-210, instantiates Variant A). Delete `fullBleed` case (line 211-225, instantiates Variant B). Add `achievementFrame` case for the new widget.
  - `lib/features/workouts/ui/post_session/share/share_preview_screen.dart:97-117, 530-537` — `_variant` init, segmented-button equality checks, `onChanged` callbacks.
- **Test sites:** `share_card_renderer_test.dart` — 2-3 tests reference `.minimalStrip` / `.fullBleed`. Update.

**Action: 3 source files + 1 test file edited. Clean migration.**

#### Boundary 3 — Variant A + B widget removal

- **Delete (4 files):**
  - `lib/features/workouts/ui/post_session/share/variants/share_card_variant_a.dart` (70 lines)
  - `lib/features/workouts/ui/post_session/share/variants/share_card_variant_b.dart` (~230 lines)
  - `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_a_test.dart`
  - `test/unit/features/workouts/ui/post_session/share/variants/share_card_variant_b_test.dart`
- **Delete (3 goldens):**
  - `test/unit/features/workouts/ui/post_session/share/goldens/share_card_variant_a_baseline.png`
  - `test/unit/features/workouts/ui/post_session/share/goldens/share_card_variant_a_max_drag_offset.png`
  - `test/unit/features/workouts/ui/post_session/share/goldens/share_card_variant_b_pr.png`
- **Imports to drop:** `share_card_renderer.dart` (Variant A + B imports at top of file).
- **E2E:**
  - `test/e2e/helpers/selectors.ts:1488` — drop `variantToggle: '[flt-semantics-identifier="share-variant-toggle"]'`.
  - Spot-grep E2E specs (`history-localization.spec.ts`, share-flow, etc.) for any `variantToggle` reference; remove the test logic.
- **ARB cleanup:**
  - `lib/l10n/app_pt.arb:892-893` — delete `sharePreviewMinimal` ("Mínimo") + `sharePreviewBold` ("Destaque").
  - `lib/l10n/app_en.arb` — same keys (corresponding lines).
  - Re-run `flutter gen-l10n` to regenerate `app_localizations*.dart` without the two getters.
- **`ShareLocalizations` struct in `share_preview_screen.dart:60-75`** — drop `previewMinimal` + `previewBold` fields if present.
- **Doc comment updates:** `share_preview_screen_test.dart:18-21` ("Variant toggle (A ↔ B) swaps the rendered variant subtree.") → rewrite for single-variant world.

**Action: 4 file deletes + 3 golden deletes + 2 ARB keys + 1 E2E selector + spec spot-audit. Highest-risk surface = `share_preview_screen.dart` toggle state machine** — the camera-permission-denied auto-select-discreet path (line 117) must still land on `discreet` even with the toggle UI removed (handled via the existing permission-deny code path; SegmentedButton removal is pure visual).

#### Migration summary

| Surface | Files edited | Files deleted | Risk |
|---|---|---|---|
| Boundary 1 (state additions) | 1 lib + 4 tests | 0 | LOW (additive) |
| Boundary 2 (enum reshape) | 3 lib + 1 test | 0 | LOW (clean rename + delete) |
| Boundary 3 (widget removal) | 4 lib + 2 tests + 2 ARB | 4 src + 3 goldens | MEDIUM (toggle state machine + l10n + E2E audit) |

### Boundary-trigger ripple inventory (per CLAUDE.md) — historical reference

This change crosses 3 boundaries:

1. **Provider state shape** — `PostSessionState` gains 3 fields. Any widget / test / cinematic cut that watches `postSessionControllerProvider` rebuilds.
2. **Public model signature** — `ShareCardVariant` enum loses 2 cases. Anything switching on `ShareCardVariant` must be updated. (Currently: `ShareCardRenderer`, `SharePreviewScreen`, the variant widgets themselves, the controller. Should be small.)
3. **Symbol removal** — `ShareCardVariantA`, `ShareCardVariantB` widgets deleted. Any direct import / test / E2E selector must be migrated.

**Action:** dispatch `Explore` agent at Pass-1 start to produce a "Boundary inventory" section in `WIP.md` enumerating every caller / reader / test / l10n key / E2E selector touching the 3 boundaries. Implementation can't start until that section is filled — per CLAUDE.md.

### Migration / data shape changes

- **Freezed regen** required after `PostSessionState` field additions and `ShareCardVariant` enum change.
- **No SQL migrations.** No backend changes.
- **No Hive box version bumps.** The state is in-memory only; no persistence.

### Risks + mitigations

| Risk | Mitigation |
|---|---|
| Adding 3 fields to `PostSessionState` breaks every existing fixture that builds it directly | Track + update in Pass 1. Estimate ~10-15 test files affected based on grep. |
| `topLifts` projection requires reading the in-progress workout's exercises + sets + per-set XP. The XP attribution may not be exposed in a directly-iterable form at finish time. | Investigate during Pass 1 — if the data isn't trivially available, decide between (a) projecting in the controller from raw set logs, (b) adding a new repository method, or (c) deferring the lift-detail rows and shipping S2 without the named-lift section in this phase (just the XP bar + rank deltas + next-target). |
| Variant retirement breaks E2E specs that reference the toggle | Already retired the deprecated overlay selectors in PR 30c. New variant selector is `share-preview-screen` only (no per-variant identifier needed since there's one). Update specs. |
| Goldens — deleting 3 + adding 3 changes the regression surface | Re-baseline cleanly in Pass 2. Document in PR. |
| 320dp screen unreadable / overflows | Pass 4 explicit 320dp screenshot via Playwright `browser_resize({width: 320})`. Block ship if rows overflow or text becomes unreadable. |
| Class-change top-collar copy decision (Q4) might affect cinematic continuity | If the user picks "BULWARK DESPERTOU." framing on share card, the cinematic B3 cut copy needs review. Current default (just class name) decouples cinematic copy from share card copy — safer. |

### CI considerations

| Gate | Status | Where |
|---|---|---|
| `scripts/check_typography_call_sites.sh` | EXISTING · enforced | New widgets use `AppTextStyles.*` getters; CI catches raw `TextStyle(fontFamily:)`. |
| `scripts/check_reward_accent.sh` | EXISTING · enforced | PR-row heroGold uses needs `// ignore: reward_accent — <reason>` annotation per the established PR 30b pattern. |
| `scripts/check_hardcoded_colors.sh` | EXISTING · enforced | Side-bar hues use `AppColors.bodyPart*` + `AppColors.hotViolet` — no raw hex. |
| `dart analyze --fatal-infos` | EXISTING · enforced | Standard. |
| Golden tests | UPDATED · 3 deleted (variant A/B + max-drag) + 3 new (Achievement Frame baseline / PR / class-change) | `test/unit/features/workouts/ui/post_session/share/goldens/` |
| E2E smoke gate | UPDATED · variant-toggle test removed | Existing smoke tests for share-flow and post-session remain. |

### Estimated commits + LOC

| Pass | Commits | Net LOC |
|---|---|---|
| 1 — State plumbing | 1 (or 2 if `topLifts` needs a separate model commit) | +200 / -10 (mostly state field additions + tests) |
| 2 — D3 overlay | 2 (one for widget + tests; one for variant retirement + selector cleanup) | +600 / -800 (deletes A/B; adds Achievement Frame) |
| 3 — S2 Mission Debrief | 3 (lift_row + xp_segmented_bar + mission_debrief_section) | +900 / -50 |
| 4 — Closeout | 1 | +20 / -20 |

**Total: ~7 commits, +1,720 / -880 ≈ +840 net LOC.** Smaller than PR 30b's +2,800 — manageable for a 3-pass dispatch.

### Acceptance criteria

1. D3 Achievement Frame renders correctly at 320dp / 360dp / 412dp viewports, photo + collars + side bars all on-screen with no clipping artifacts.
2. Bottom collar XP hero reads as the design's primary numeric (38sp preview / 64px export).
3. Class-change session: top collar shows new class name; left side bar swaps to `heroGold` (avoids both bars collapsing to `hotViolet`).
4. PR session: lift-detail row shows `heroGold` weight × reps; bottom-collar lift detail truncates with ellipsis on long exercise names.
5. Discreet path (no-photo) unchanged from PR 30c shape.
6. Mission Debrief renders below the existing eyebrow + hook (or consolidated as Pass 3 decides):
   - 4 lift rows on 4+ exercise session; "+N more" footer on 5+ session.
   - Single-segment XP bar on 1-BP session; multi-segment proportional bar on multi-BP session.
   - Per-BP rank delta rows for every BP that earned XP.
   - heroGold PR flag on rows with a PR set.
   - Next-target callout points to closest-rank-up (or 2 closest if Q1 #2 expands).
7. No 320dp overflow / unreadable text.
8. `dart analyze --fatal-infos` clean.
9. All 3 style gates clean.
10. New + updated tests pass; old Variant A/B tests deleted.
11. E2E smoke + share_flow + post_session specs green.
12. Device-verification PASS (S25 Ultra physical pass per PR 30c precedent).

### Dependencies + critical path

- Pass 1 must land before Pass 2 (overlay reads new fields).
- Pass 1 must land before Pass 3 (debrief reads new fields).
- Pass 2 + Pass 3 are independent and could run in parallel agents, BUT — per `cluster_parallel_agents_shared_working_tree_thrash` — DON'T. Sequential.
- Pass 4 is closeout after both Pass 2 + Pass 3 merge to the branch.

### Compact-restore checklist

When restoring after `/compact`:

1. Re-read this WIP.md FIRST — Phase 31 plan is the canonical spec.
2. Phase 30 is FULLY SHIPPED (PRs #255, #259, #263, #265 all merged). No Phase 30 state to track.
3. Read `docs/post-phase-30-design-exploration.html` § D3 + S2 (the locked design picks).
4. Read `docs/post-phase-30-research.md` (the PO research context).
5. Last commit on `main` from Phase 30: `f5ce0a1` (PR 30c).
6. If actively in Pass N: check task list for the in-progress task; read the relevant Pass section above.
