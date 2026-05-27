# Post-Phase-30 design exploration — research brief

> Pairs with `docs/post-phase-30-design-exploration.html` (8 visual proposals from ui-ux-critic). This brief is the product-owner research context: competitor patterns + info-hierarchy gap analysis + data-availability flags + anti-thesis-dilution gut-check.

## Section 1 — Competitor pattern survey

**Strava activity card (fitness).** Strava's share image is the activity map + a compact bottom strip: distance, time, pace in that order. The map IS the hero — the strip is a caption. In 2025 Strava introduced Stats Stickers (semi-transparent, draggable stats blocks for Instagram Stories); immediate user backlash called them "HUGE, covering the photo." The tension is documented in Strava's community hub: users wanted small-but-legible, Strava shipped prominent, nobody was happy. RepSaga is at the same crossroads. The strip works when the underlying photo carries emotional weight; when it doesn't, the strip feels like a receipt.

**Apple Fitness+ post-workout (fitness).** After workout completion: time / active calories / total calories / average heart rate / heart rate graph over time. The clincher is the heart-rate graph — it makes the emotional arc of effort visible. No RPG layer, no forward hook. The climactic moment is the rings closing on Apple Watch; the summary is just a receipt. Anti-thesis for RepSaga — technically complete but emotionally flat.

**Persona 5 Royal victory screen (RPG).** The structural lesson is sequencing: spoils arrive one at a time (items clink in, money rolls, then the XP bar for each character fills). The fill animation IS the climax — you watch each character's XP bar advance toward the next level. Level-up triggers a character portrait pop + bubblegum sound effect. Critical insight: the hero treatment goes to the bar fill, not the number. RepSaga's cinematic already does the "number slams" correctly for Beat 1; the summary panel should mirror P5R's bar-fill grammar for per-BP rank progress.

**Octopath Traveler victory screen (RPG).** Simple, clean, anti-climactic by design — and the game's own UI/UX critics note the flaw: "Players are told how much money they earned, but not how much they now have." The delta without the context of current total = no gratification anchor. Maps directly to RepSaga's current summary: "Costas: 47 XP to rank 12" tells the user what's left, but doesn't show how far they came this session. The lesson: show the delta AND the bar, not just the gap.

## Section 2 — Info-hierarchy gap analysis

The gap: after the eyebrow line ("Faltam 168 XP para Peito rank 18"), `PostSessionSummaryPanel` hits `const Spacer()` — everything below is whitespace until the CTAs at the bottom. On a baseline session (no PR, no rank-up), the optional rows are all null → the Spacer is enormous.

**Candidate elements, ranked by RPG-thesis fit:**

1. **Per-BP XP delta rails** — every body part that earned XP this session as a labeled bar with delta fill animated in. Direct RPG-thesis proof: this session's physical work maps to this rank-rail advance. **CRITICAL DATA FLAG:** `bpXpDeltas` and `bpRankAfter` are computed in `PostSessionController._buildInitial()` as local variables but NOT stored in `PostSessionState`. Adding BP rails requires adding `Map<BodyPart, int> bpXpDeltas` and `Map<BodyPart, int> bpRankAfter` fields to the freezed model. One-field addition; data is already computed. **Must-have.**
2. **This session's PR row (static)** — PR already fires in B3 cinematic but disappears when summary mounts. A compact static row ("Supino · 95kg × 5 · PR") lets the user verify the record after the cut ends. `prResult` is already in `PostSessionState`. Zero new data required. **Must-have for PR sessions.**
3. **Closest-rank-up callout (extended)** — current eyebrow does one BP. If the user trained 3 body parts, the other 2 have no callout. A secondary "Also: Costas 47 XP → rank 12" row surfaces the second-closest. Data: `bpXpDeltas` + `bpRankAfter` (needs state storage — see item 1). **Nice-to-have; extends the rails, doesn't replace them.**
4. **Class progress subordinate line** — "Berserker requer equilíbrio. Peito domina." Shows which body parts are pulling the user's class balance. `characterClassSlug` already in `SharePayload`, but the class-balance computation isn't currently exposed post-session. Requires a class-balance read from `rpgProgressProvider` — already in the controller's `ref.read`. Conditionally add: show only when balance is meaningful (not for Initiate). **Medium-priority.**
5. **Title progress (1-2 sessions away)** — "Você está a 1 sessão do título IRON PILLAR." Thesis-clean only if titles are gated by verifiable feats (they are). BUT: requires a title-near-completion query at workout finish — non-trivial. **Flag for v1.1; don't add now.**

**Dropped candidates:**

- **Streak / consistency tally** — not currently exposed on post-session state. Adding it requires a query; more importantly, streak XP is not part of RepSaga's thesis (XP comes from sets, not days). Gamification fluff. **Kill.**
- **Comparison to last session (volume / sets / time delta)** — "previous workout of same type" query is not currently built. Not available in `PostSessionState`. **Flag for v1.1.**

## Section 3 — Share-card overlay presence

**Caption-level (current Variant A minimal strip).** RPG-fitness fit: honest — strip anchors the photo, hue accent and rank bar are real-lift-signal. Competitor closest: Strava's activity card before the Stats Sticker overreach. Sweat-test: reads at distance. Fails on presence — the photo owns the frame, the overlay is a footnote. Users who want to "claim the moment" won't feel claimed.

**Stamp-level: diagonal brand mark overlapping center-right.** RPG-fitness fit: strong if the stamp carries a real number (rank, total XP, PR) rather than a logo. Competitor closest: custom third-party Strava overlays that use large-glyph stats with the map small. Risk: if the diagonal is just a logo, it reads as a watermark. If it's the XP number at 48sp Rajdhani, it reads as a claim.

**Frame-level: achievement card frame, photo inside.** RPG-fitness fit: medium — the frame signals "this is a trophy card", which is RPG-native. But the photo shrinks, which weakens the "I actually lifted this" signal. Competitor closest: Hevy's social tiles, which Phase 30 decisions explicitly cited as "emotionally flat." The framing moves emphasis from the gym moment to the app. **Con outweighs pro for pure framing.**

**Diegetic: scoreboard / locker-tag / graffiti treatment.** RPG-fitness fit: high if executed — a scoreboard aesthetic says "this gym has a leaderboard, and you just moved on it." No competitor does this. Hardest to execute without looking corny. If the graffiti reads as a sticker kit, it fails. If it reads as a film-still prop (a score on a locker-room chalkboard, a rank badge burned into the corner), it succeeds. Solo Leveling reference: System notifications read as if the world itself posted the score.

## Section 4 — Recommended design directions

**Overlay directions (4):**

- **A. Rank-number stamp** — Large Rajdhani number (current rank of dominant BP, e.g. "RANK 18") diagonally centered-right at 80% opacity abyss backing, hue-tinted border. Photo visible behind. The rank IS the claim. Closest to diegetic without requiring illustration work.
- **B. Expanded collar (Variant B+)** — Widen the existing Variant B collars: top collar grows from 72dp to 120dp, bottom from 100dp to 160dp. Photo shrinks but becomes a letterbox center zone. Collars carry more information (class + rank + XP delta + PR).
- **C. Full-bleed XP flood** — For max-combo sessions (PR + rank + level + class), the photo desaturates and the hue floods from the dominant BP color at 30% overlay — the entire card glows the BP color. The number (e.g. "+618 XP") renders at 64sp Rajdhani center-frame. Hero cinematic energy, not caption energy.
- **D. Rank badge burn** — A hexagonal or octagonal rank badge appears bottom-center, overlapping the photo at 100% opacity. Inside: current rank number. Below: "RANK {N} · {BODY PART}." Photo gets cropped top-center (portrait) to keep the gym subject visible. The badge claims the bottom third.

**Summary panel directions (4):**

- **E. BP rank rails grid** — All body parts trained this session rendered as labeled rank rails with delta fill animated in. Each rail: BP label left, "RANK N" right, hue-colored bar with this-session's fill darker than existing progress. 48dp height per rail, vertically stacked. Replaces the Spacer gap entirely.
- **F. Session dossier** — Compact table: rows for each body part trained (BP name / XP delta / rank / progress fraction). Presented as a mission debrief — "RELATÓRIO DE SESSÃO" eyebrow, rows beneath. Rajdhani 700 for rank numbers, Barlow for labels. Feels like an after-action report, not a receipt.
- **G. PR permanence row** — For sessions with a PR: a static gold-tinted row below the next-step hook showing the PR that B3 cinematic revealed. Gives the user a moment to savor before tapping CONTINUE. Zero new data needed — `prResult` is already in state.
- **H. Closest-next callout pair** — Instead of one next-step hook, show the top 2 closest rank completions across all trained BPs. Two forward hooks instead of one. Urgency increases because the user sees two races, not one.

## Section 5 — Anti-thesis-dilution gut-check

| Direction | Pins RPG-real-lift contract? |
|---|---|
| A. Rank-number stamp | Y — rank is a real-lift-signal |
| B. Expanded collar | Y — info added is all real-lift-derived |
| C. Full-bleed XP flood | Y — XP earned from sets, hue from dominant BP |
| D. Rank badge burn | Y — badge displays the rank number earned |
| E. BP rank rails grid | Y — each rail traces to actual sets logged |
| F. Session dossier | Y — all rows are real-lift outputs |
| G. PR permanence row | Y — PR is a verifiable feat |
| H. Closest-next callout pair | Y — rank thresholds earned via real XP |

All 8 survive. None introduce cosmetic RPG without a real-lift signal underneath.

## Implementation data-availability summary

- **Directions E, F, H** require `bpXpDeltas` and `bpRankAfter` added to `PostSessionState` (two `Map<BodyPart, int>` fields). Already computed in `PostSessionController._buildInitial()` (lines ~100-107) — just not persisted to state.
- **Direction G** requires zero new data — `prResult` is already in `PostSessionState`.
- **Directions A-D** are visual-only changes to the share pipeline.

## Relevant files

- `lib/features/workouts/ui/post_session/summary/post_session_summary_panel.dart` — the underwhelming panel; `const Spacer()` at line 212 is the gap
- `lib/features/workouts/ui/post_session/post_session_state.dart` — missing `bpXpDeltas` + `bpRankAfter` fields
- `lib/features/workouts/ui/post_session/post_session_controller.dart` — `_buildInitial()` already computes both maps
- `lib/features/workouts/domain/share_payload.dart` — share card data model; overlay rendering starts here
- `lib/features/workouts/ui/post_session/share/variants/share_card_variant_a.dart` + `share_card_variant_b.dart` + `share_card_discreet.dart` — overlay renderers to modify for directions A-D
- `docs/post-session-screen-mockup-v2.html` § 6 + § 7 — locked share design, now up for revision
- `docs/post-phase-30-design-exploration.html` — UX-critic's 8 visual proposals (paired output)
