# Work In Progress

Active branch work. Removed once merged. Empty when no in-flight work exists —
backlog/parked items live in `docs/PROJECT.md` §2.

---

## Phase 39 — Feel-Good / Retention — BUILD SLICE 1 (Bestiary share, server-free)

> ▶ **RESUME HERE (post-compact, 2026-06-26):** Build DONE, reviewed, QA-passed, **VISUAL GATE PASSED**.
> Branch `feature/phase39-bestiary-share` (off main, **uncommitted** — don't commit till user OK).
> **Tree GREEN:** `dart format` clean, `dart analyze --fatal-infos` clean, all 5 custom check_*.sh gates
> clean, full `flutter test` **4134 passed / 0 failed / 5 skipped**. **ONLY remaining step = commit + open
> PR (on user OK) → squash merge.** No migrations this phase.
>
> **Visual gate caught + fixed ONE real blocker:** the shared 7-hue identity rail
> (`share_card_chassis.dart` `_IdentityRail`) rendered **invisible** on a real web build — the `Row`
> defaulted to `CrossAxisAlignment.center`, so each childless `ColoredBox` shrink-wrapped to **height 0**
> (segments measured 51×0). Fix = `crossAxisAlignment: CrossAxisAlignment.stretch`; pinned by new behavior
> test `share_card_chassis_rail_test.dart` (asserts rendered segment height 3/9, was 0.0). Cluster:
> `visual-only-bugs-escape-value-tests` (old tests asserted rail tree-presence + flex, never rendered size).
> Re-rendered web at 320/360/412dp: rail now paints on all cards; base widens dominant (chest 2.2×),
> chimera widens 3 trained parts (1.4×), boss = gold frame + ♛ crown + ⚜ badge, clean-flex 4-stat strip
> no overflow at 320dp. Screenshots surfaced to user in-thread (scratch dir deleted). Throwaway debug
> harness (debug route + allowlist + gallery screen + playwright driver) FULLY REMOVED.

Design is LOCKED (PO + ui-ux, 2026-06-24). Specs: `docs/bestiary-spec.md`,
`docs/bestiary-catalog.md`, mockups `docs/phase-39-share-mockups.html` +
`docs/phase-39-mockups.html`. NO brainstorming — straight to pipeline. NO server, NO
migration (pure-Dart resolver + static JSON assets).

### Slice 1 scope — FINAL (user-locked 2026-06-26)
Both share modes ship, minus the heavy dashboard. IN: shared overlay chassis, toggle/pref,
Bestiary mode (resolver + creature), the SIMPLE serious frame (Clean Flex = PR-hero + 4-stat strip).
OUT (→ Slice 2): six-ring conditioning dashboard, comeback framing, cumulative-tonnage legendaries,
in-app bestiary log.

- **`BestiaryResolver`** (pure Dart, deterministic, unit-testable): `(PostSessionState) → BeastCard`.
  Feed from `PostSessionState` (richest: tonnage, bpXpDeltas, bpRankAfter, prResult, queueResult,
  priorFinishedWorkoutCount). **RANK-PRIMARY** (see §3 / RESOLVED below):
  - **Line** = dominant body part (most session XP).
  - **Tier** = dominant line's **rank league** E[1–4] D[5–10] C[11–20] B[21–35] A[36–55] S[56+].
    (NOT session-XP — that inverts; see finding below.)
  - **Specimen** within league (base / notable / fierce) = session XP vs the league's reference
    median (`tasks/bestiary-tier-calibration.py` rank-bucket medians). Coarse 3-band OK.
  - **Kind** precedence (objective triggers): session-count milestone→legendary > PR/rank-up→boss >
    3+ parts→chimera > else→base. (Comeback + cumulative-tonnage legendary = Slice 2.)
  - **Variant** = `hash(session_id) mod count` + 1-deep "last beast" no-repeat guard (client-side).
  - **Hue** = dominant bp hue; chimera = multi-hue gradient over trained parts. **Phrase** = §6.
- **Static assets** `assets/bestiary/`: `bestiary.json` (84 base = 7 lines × 6 tiers × 2 variants),
  `epithets.json`, `chimeras.json`, `legendaries.json` (session-count only in S1),
  `achievement_phrases.json`. Source = `docs/bestiary-catalog.md`. **Inline `name{en,pt}` JSON**
  (bulk content, not ARB) + a unit parity test asserting en+pt present for every entry.
- **Shared overlay chassis** (per §7): full-bleed photo-hero + scrim + thin 7-hue identity rail +
  wordmark. Both modes render their content block into it.
- **Bestiary mode** overlay = §7 bottom block (eyebrow / beast name / rank·XP·tonnage / phrase),
  boss (gold + laurel) + chimera (multi-hue rail) variants. (Comeback eyebrow = Slice 2.)
- **Clean Flex (simple serious) mode** = PR-hero + 4-stat strip into the same chassis (mock
  `phase-39-share-mockups.html` "Clean Flex" rows). Six-ring conditioning dashboard = Slice 2.
- **Share-mode toggle**: Bestiary (default) vs Clean Flex, in the share sheet + a Hive-backed
  default preference (`HiveService.userPrefs`); new mode enum threaded ShareSheet→preview→renderer,
  orthogonal to the existing `ShareCardVariant` (photo vs discreet).

### ✅ RESOLVED — tier model = RANK-PRIMARY, calibrated via simulation (spec §3, 2026-06-26)
**Hosted DB rejected** (single dirty test user — weird test values; user flagged). Calibrated instead
via a **persona simulation** `tasks/bestiary-tier-calibration.py` (imports the locked XP oracle like
the fixture generator; 14 personas × 52 wk = 2634 sessions). **PARITY-LOCKED**: the script asserts
its per-session XP sums reconstruct the oracle's `weekly_xp` exactly → proves no formula drift. **NO
change to XP/rank/level formula** — bestiary only reads existing values.

**Key finding:** session-XP-driven tiers INVERT over a career (locked formula decays per-session XP as
rank climbs → veterans get SMALLER beasts: elite S→B, advanced A→C across a sim year). So the model is
now **RANK-PRIMARY** (user-locked):
- **TIER = dominant line's rank league:** E[1–4] D[5–10] C[11–20] B[21–35] A[36–55] S[56+]. Rises with
  progression (beginner C→A, advanced B→S). Rank-5 can't field S by construction.
- **Session XP = specimen within league** (base / notable / fierce variant), reference = sim per-rank
  median XP. NOT a tier driver. Coarse 3-band split OK for Slice 1.
- **KIND** (base/boss/chimera/legendary) = existing objective triggers (§4/§5).
- Resolver input: dominant line's `rank` — **confirmed reachable** (`SharePayload.dominantBodyPartRank`,
  share_payload.dart:122). No model/RPC change.
- Artifact: `tasks/bestiary-tier-calibration.py` (durable, re-runnable; `--sample` dumps exercise/set
  breakdowns proving session granularity).

### Boundary inventory (Explore, 2026-06-26 — ABOVE the impl checklist per CLAUDE.md)
- **Post-session data model:** rich snapshot = `PostSessionState` (`post_session_state.dart`); share
  layer renders from the pure projection `SharePayload` (`share_payload.dart`).
- **Dominant-line rank — NO GAP.** `SharePayload.dominantBodyPartRank` (share_payload.dart:122) already
  holds the absolute 1–99 rank (`bpRankAfter[dominantBp]`, sourced post-save from `rpgProgressProvider`
  → `body_part_progress.rank`, not the RPC return). Resolver consumes directly. **rankCap is free.**
- **On `PostSessionState` (NOT on `SharePayload`):** `tonnageTons`, `bpXpDeltas` (parts-count + dominant),
  `priorFinishedWorkoutCount`/`sagaNumber` (session-count milestone), `prResult`, `queueResult`
  (rank-up/class/title flags), `bpRankAfter/Before`, `conditioningCharge`. → **Resolver feeds from
  `PostSessionState`** (richest); avoids bloating the pure `SharePayload`.
- **Existing share pipeline:** `ShareController` 6-state machine (`share_controller.dart`); 2 variants today
  (`achievementFrame`, `discreet` — "3 variants" is stale doc wording); `ShareCardRenderer` composes,
  `ShareImageRenderer` does RepaintBoundary→PNG→`ShareService`; host = `ShareSheet.open` + `share_preview_screen`.
- **Mode toggle is net-new:** no persisted share-mode pref exists (variant is implicit from photo path).
  Bestiary-vs-Stats = new orthogonal axis → new Hive pref (`HiveService.userPrefs`) + mode enum threaded
  `ShareSheet`→preview→renderer. BeastCard is the Bestiary-mode payload; existing `SharePayload` stays the Stats payload.
- **Assets/l10n:** declare under `pubspec.yaml flutter.assets:`; load via `rootBundle.loadString`+`jsonDecode`
  (mirror `TitlesRepository`). Convention is slug-only JSON + ARB copy — spec §8 wants inline `name{en,pt}`.
  Bestiary catalog is BULK CONTENT (~150 entries × 2 locales), wrong fit for ARB → **go inline JSON +
  add a unit parity test** asserting every entry has en+pt (replaces the ARB parity the tooling gives free).
- **GAPS (need data not yet threaded):** (a) comeback/dormancy — `lastEventAt` is on `BodyPartProgress`
  but NOT captured into `PostSessionState`; (b) cumulative-tonnage milestones — no client source at all
  (only this-session tonnage). Session-count milestones ARE available. ← scope decision below.

### Pipeline status
- ✅ Boundary inventory (Explore) — done (see section above).
- ✅ Calibration → rank-primary model locked (see RESOLVED section above).
- ✅ Sub-task 1: resolver + data model + content assets + 38 tests — DONE & verified.
- ✅ Sub-task 2: chassis + Bestiary overlay + Clean Flex frame + toggle/Hive pref — DONE & verified.
- ✅ ui-ux-critic review → B1 (boss frame/badge/crown) + B2 (chimera multi-hue name + rail via new
  `BeastCard.trainedParts`) + sigil diamond chip + Cinzel→Rajdhani caption fix → ALL FIXED.
- ✅ reviewer (initial + re-review) → I1 rank sentinel + nits FIXED → **SIGNED OFF, clear to QA**.
- ✅ **QA gate — DONE.** +12 coverage tests (export-tree-survives-render incl. boss badge; structural
  catalog guards; `referenceMedianXp` pin map E220/D400/C420/B430/A470/S500). Full workouts tiers
  **1393/1393**. E2E: added `should switch content mode when Bestiary/Stats toggle tapped`
  (`share_flow.spec.ts`, @smoke, asserts `aria-current` flip, no native pickers) — ran live **4/4 green**.
  No bugs, no production code changed.
- **Branch:** `feature/phase39-bestiary-share` (created off main 2026-06-26; 47 files uncommitted, NOT yet committed — commit on user OK).
- ✅ **Visual gate (step 9) — PASSED 2026-06-26.** Rendered real `flutter build web` at 320/360/412dp via a
  throwaway `/debug/bestiary` route + Playwright (both since deleted). Caught + fixed the invisible-rail
  blocker (see RESUME HERE above). All states match `phase-39-share-mockups.html` (Rajdhani-not-Cinzel name
  is the locked deviation, not a bug; "RANK X" text always matches the tier sigil via `rankToken =
  'RANK ${card.tier.label}'`, the harness's "RANK C"-vs-tier-A mismatch was harness-only).
- ⏭ **NEXT: commit + open PR (on user OK), then squash merge.** No migrations.
- 〰 (historical) visual-gate how-to, kept for reference:
  - `flutter build web` from this branch (`export PATH="/c/flutter/bin:$PATH"`).
  - **Challenge:** boss (PR/rank-up) + chimera (3+ parts) + each tier are HARD to trigger via a real
    logged session, and the share preview also normally needs a photo. The pragmatic path is a
    **temporary debug-only `GoRoute`** (e.g. `/debug/bestiary`) that constructs representative
    `BeastCard`s — base/boss/chimera at a couple tiers + a Clean-Flex `SharePayload` — and renders
    `ShareCardRenderer` (mode=bestiary & cleanFlex) at fixed card size. Screenshot via Playwright
    (serve `build/web`, port 4200, `FLUTTER_APP_URL=` empty) or Chrome DevTools MCP at **320/360/412**.
    **DELETE the debug route before commit.** (Alt: extend the existing golden test
    `share_card_renderer_golden_test.dart` to emit PNGs — but goldens use the test renderer, which can
    miss CanvasKit/Skia masking+gradient+scrim artifacts the web gate is designed to catch; cluster
    `visual-only-bugs-escape-value-tests`. Prefer the real web render.)
  - **Verify against `docs/phase-39-share-mockups.html`:** boss = gold inset frame
    (`share-card-chassis-boss-frame`) + `♛` crown (`...-boss-crown`) + ⚜ CHEFE badge (`...-boss-badge`);
    chimera = multi-hue name gradient (`share-card-bestiary-name-gradient`) + ALL trained segments
    widened in the 7-hue rail; rank diamond chip (`share-card-bestiary-rank-sigil`); scrim legibility
    over a bright photo (esp. core/cardio hued eyebrow — ui-ux N1); Bestiary vs Clean-Flex read as one
    family. Beast name is Rajdhani `display` (Cinzel rejected — locked, NOT a bug).
  - Surface screenshots in-thread (drag-drop or `gh pr comment`). Bug → tech-lead → re-render. Don't merge till visuals match.
- ⏭ Then: final `make ci` + E2E green → commit + open PR (user OK) → squash merge. NO migrations this phase.

### Slice 2 backlog (deferred, recorded)
- Comeback eyebrow ("a fera adormecida desperta") — needs dormancy signal (`lastEventAt`) threaded into PostSessionState.
- Clean-Flex eyebrow character level — `bpRankAfter` is partial (only parts that earned XP); char level needs all 7 ranks. Not reconstructable at the share seam → needs a payload thread.
- Cumulative-tonnage legendaries; six-ring conditioning dashboard; in-app bestiary log.
- Boss badge could carry terser copy (⚜ CHEFE/BOSS) distinct from the full-phrase eyebrow (currently share `bossEyebrow` string).
- Named-epithet boss eyebrow (mockup shows the epithet in the eyebrow; Slice 1 uses the generic boss eyebrow).

### SLICE 1 · SUB-TASK 1 — resolver + content + tests (pure Dart, NO UI) — ✅ DONE (verified)
Branch: `feature/phase38b-cardio-logging` (current). Per WIP Slice 1 scope + spec §1/§3/§4/§5/§6/§8.

- [x] Static assets `assets/bestiary/` (inline `name{en,pt}` JSON):
  - [x] `bestiary.json` — 84 base = 7 lines × 6 tiers × 2 variants (catalog §1), slug+line+tier+variant+name{en,pt}
  - [x] `epithets.json` — 8 boss epithets (catalog §2), name{en,pt}
  - [x] `chimeras.json` — fusion lexicon (7 lines) + 7 curated 2-part hybrids ×2 + 3/4-part ×2 + full-body ×3 (catalog §3)
  - [x] `legendaries.json` — session-count milestones only this slice: 50/100/250 (catalog §4 rows 1-3), name{en,pt}
  - [x] `achievement_phrases.json` — spec §6 (12 traits), name{en,pt}
  - [x] Declare all five under `pubspec.yaml flutter.assets:`
- [x] `BeastCard` Freezed model — `lib/features/workouts/domain/beast_card.dart` (+ BeastTier/BeastKind/BeastSpecimen enums)
- [x] `BestiaryCatalog` + entry models — `lib/features/workouts/domain/bestiary_catalog.dart` (mirror TitlesRepository: rootBundle+jsonDecode, injectable AssetBundle, in-process cache; pure `parse()` test seam)
- [x] `BestiaryResolver` — `lib/features/workouts/domain/bestiary_resolver.dart` (pure, deterministic; `(PostSessionState, {sessionId, locale, lastBeastSlug}) → BeastCard`; FNV-1a hash for stable variant pick)
- [x] `make gen` for Freezed
- [x] Tests `test/unit/features/workouts/domain/`: determinism, rank-league boundaries, line selection, kind precedence, specimen bands, variant no-repeat, locale, catalog en+pt parity + counts (84 base). 38/38 pass.
- [x] `dart format` + `dart analyze --fatal-infos` (clean) + `flutter test` (green)

### SLICE 1 · SUB-TASK 2 — share overlay chassis + Bestiary overlay + Clean Flex + toggle/pref (tech-lead) — ✅ DONE (verified)
Branch: `feature/phase38b-cardio-logging`. Per WIP Slice 1 scope + spec §7 + `phase-39-share-mockups.html`.

- [x] `BestiaryCatalog` async provider — `lib/features/workouts/providers/bestiary_catalog_provider.dart` (FutureProvider mirroring `titleCatalogProvider` → `BestiaryCatalog.load()`)
- [x] `ShareMode { bestiary, cleanFlex }` enum (`domain/share_mode.dart`) + Hive-backed default pref provider (`share_mode_provider.dart`, mirrors `agePromptDismissalProvider`; default = bestiary; persisted in `HiveService.userPrefs`)
- [x] `lastBeastSlug` Hive pref provider (read before, write after a share) — `last_beast_slug_provider.dart`
- [x] Shared overlay chassis widget — `share/share_card_chassis.dart` (full-bleed photo-hero + scrim + 7-hue rail w/ per-part flex + wordmark; both modes render a content block into it)
- [x] Bestiary-mode overlay — `share/variants/share_card_bestiary.dart` (eyebrow / beast name / rank·XP·tonnage / phrase; boss gold+laurel; chimera widened rail)
- [x] Clean Flex frame — `share/variants/share_card_clean_flex.dart` (PR-hero + 4-stat strip into the same chassis)
- [x] Bestiary + chassis + clean-flex typography in `share_card_typography.dart` (sanctioned AppTextStyles entry points)
- [x] `BestiaryShareStrings` pre-localized bundle (chassis eyebrow + Clean-Flex stat labels) in `share_localizations.dart`; beast name/phrase pre-localized by resolver. New ARB keys (en+pt): `shareModeBestiary/CleanFlex`, `shareBestiaryEyebrow`, `shareBossEyebrow`, `shareStatXp/Tonnage/Sets/Duration`
- [x] Threaded `ShareMode` ShareSheet → SharePreviewScreen → ShareCardRenderer; renders selected mode in BOTH visible preview + offscreen export tree
- [x] Wired BeastCard at the post-session seam: real `workoutId` (route path param `/workout/finish/:workoutId` → `PostSessionScreen.workoutId`) as `sessionId`, current locale, Hive `lastBeastSlug` read before / written after a (non-error) share
- [x] Mode toggle control (`share/share_mode_toggle.dart`) on the preview screen (shown only when a beast resolved) + persists default on change
- [x] Widget/provider tests (16 new): bestiary overlay (name/rank/XP/tonnage/phrase, boss eyebrow+laurel+gold, chimera widened rail); clean-flex (PR-hero + 4 stats, collapsing context); renderer mode routing (both targets + legacy fallback); toggle (selected fill + tap callback); Hive mode-default read+persist; last-beast-slug read+persist
- [x] `dart format` + `dart analyze --fatal-infos` (clean) + `flutter test` (workouts suite 1371 green; full project analyze clean)

**Deviation:** Cinzel serif beast name → rendered in `AppTextStyles.display` (Rajdhani hero); no serif family bundled (separate font task). Clean-Flex eyebrow = class name only (character-level numeral not projected onto PostSessionState in Slice 1).

**Deviation flagged:** mockup uses Cinzel serif for beast names; RepSaga bundles NO serif family. Beast name renders in `AppTextStyles.display` (Rajdhani hero) — closest sanctioned register. Bundling Cinzel is a separate font task (out of this sub-task's scope; no asset-bundling in scope).

**Specimen thresholds (pinned):** per-league reference median (from calibration p50, rounded) → ratio = sessionXP / median; ≥2.2×→fierce, ≥1.4×→notable, else base. Coarse 3-band per spec §3.

### DONE TODAY (2026-06-25, shipped+live — for context)
- Vitality-4 (#412, mig 00085 live) — save-time immediacy via day-base re-step (conditioning charge
  now moves at save; cron no longer pre-empts). On-device confirmed working.
- last-lifted-seed fix (#411) — routine prefill grabs the most-recent session's weight (PostgREST
  embedded-vs-parent ordering bug). On-device confirmed working.
