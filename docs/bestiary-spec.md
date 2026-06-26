# The Bestiary — "Session as Conquest" (Phase 39)

Every finished session is rendered as **a creature you felled** — a generated "feat"
for the photo-hero share overlay (and, later, a collectible hunt-log in-app). The beast
is chosen **deterministically** from the session's real data, so the same session always
yields the same creature, but the catalog is large enough that sessions feel varied and
collectible. Voice: JRPG bestiary / Monster-Hunter hunt-log / Solo-Leveling gate-boss.

**Thesis + safety:** every beast is *earned from a real logged session*; copy is
descriptive, past-tense ("you felled"), never prescriptive / loss-aversion. This is the
feel-good Phase 39 — the quest/overtraining-safety track is the separate Phase 40.

**IP caution:** the reference *voices* inspire the vibe; all shipped names/lore are
**original** mythic-generic (no "Bahamut" / "Persona" / trademarked names).

---

## 1. Inputs (all already on the post-session summary — no new server data)

| Input | Source | Drives |
|---|---|---|
| Dominant body part (most XP this session) | `bpXpDeltas` | creature **LINE** |
| Dominant line's **rank** (1–99) | `body_part_progress.rank` (post-session) | **TIER** (rank league, §3) |
| Session **XP** earned | `totalXpEarned` | **specimen** within league (base/notable/fierce, §3) |
| Tonnage (kg moved) | `tonnageTons` | flavor stat shown |
| PR set? / rank-up? | `prResult` / rank deltas | **BOSS** upgrade |
| # body parts trained significantly | `bpXpDeltas` | **CHIMERA** (combination) |
| Comeback (dominant part dormant N+ days) | `last_trained` + charge delta | special **framing** |
| Session-count / tonnage milestones | history | **LEGENDARY** boss |

**Why XP drives the tier, not tonnage:** XP is already normalized across body parts +
difficulty (Phase-29 formula + the Vitality-3 gate), so a hard arm day and a heavy leg
day are comparable. Raw tonnage swings 5–10× by body part and would make leg days
*always* the biggest beast. Rank by XP; **show** tonnage as flavor.

---

## 2. Creature lines (dominant body part → family)

Each line scales **E → D → C → B → A → S**. (en / pt)

| BP | Line | E | D | C | B | A | S (apex) |
|---|---|---|---|---|---|---|---|
| **Chest** | Golems (force/bulwark) | Clay Golem / Golem de Argila | Stone Golem / Golem de Pedra | Iron Golem / Golem de Ferro | Obsidian Golem / Golem de Obsidiana | Adamant Golem / Golem de Adamante | **The Colossus / O Colosso** |
| **Back** | Drakes (wings/pull) | Cave Drake / Dragonete das Cavernas | Crag Wyvern / Serpe da Falésia | Storm Wyvern / Serpe da Tempestade | Elder Wyrm / Wyrm Ancião | Skybreaker Dragon / Dragão Corta-Céu | **The World Serpent / A Serpente do Mundo** |
| **Legs** | Behemoths (foundation) | Wild Ox / Boi Selvagem | Razorback / Dorso-de-Lâmina | Behemoth / Beemote | Earthshaker / Treme-Terra | Mountain Titan / Titã da Montanha | **Gigas, the Unmoved / Gigas, o Imóvel** |
| **Shoulders** | Atlas/Sentinels (carry) | Gargoyle / Gárgula | Stone Sentinel / Sentinela de Pedra | Bronze Atlas / Atlas de Bronze | Iron Atlas / Atlas de Ferro | Titan Sentinel / Sentinela Titã | **Atlas Eternal / Atlas Eterno** |
| **Arms** | Manticores (sword arm/claws) | Jackal / Chacal | Dire Wolf / Lobo Atroz | Manticore / Mantícora | Chimera-Claw / Garra-Quimera | Sabertooth Lord / Senhor Dente-de-Sabre | **The Ripper King / O Rei Estraçalhador** |
| **Core** | Hydras (coil/spine) | Pit Serpent / Serpe do Fosso | Cave Wyrm / Wyrm das Cavernas | Hydra / Hidra | Basilisk / Basilisco | Leviathan Spawn / Cria do Leviatã | **The World Coil / A Espiral do Mundo** |
| **Cardio** | Tempests (wind/swift) | Will-o'-Wisp / Fogo-Fátuo | Wraith / Espectro | Storm Phantom / Fantasma da Tempestade | Tempest Shade / Sombra Tempestuosa | Galewraith / Vendaval Espectral | **The Howling Tempest / A Tempestade Uivante** |

= **7 lines × 6 tiers = 42 base creatures.** Each gets a one-line lore string (en/pt) + a
sigil glyph.

---

## 3. Tier ladder (RANK-PRIMARY — beast tier = your dominant line's rank league)

Solo-Leveling E→S ladder. **The base tier is your dominant line's RANK league**, not the
session's raw XP:

```
beastTier  = rankLeague(dominantLineRank)        # the base creature's tier
specimen   = sessionXP relative to your league   # base vs notable vs fierce variant
kind       = objective triggers (§4/§5)          # PR/rank-up→boss, 3+parts→chimera, milestone→legendary
```

- The beast's **line** = the session's dominant body part; the tier reads **that body part's
  rank** (1–99 from `body_part_progress.rank`). Your Chest line's beasts grow as your Chest
  rank grows — the progression *rises* with you.
- A rank-5 player's league is **C**; they **cannot** field an S beast by construction — no
  separate "gate" needed. The apex is earned by reaching the apex rank.

**Why rank-primary, not session-XP** (calibration finding, 2026-06-26): the LOCKED XP formula
intentionally *decays* per-session XP as rank climbs (tier-diff normalization). A session-XP-driven
tier therefore **inverts** over a career — veterans earn *smaller* beasts than in month one
(elite: S→B, advanced: A→C across a sim year). Rank-primary makes the ladder rise instead.
**Nothing in the XP/rank/level formula changes** — the bestiary only *reads* the locked rank.

### Rank leagues (the locked bands)

Calibrated against the **persona simulation** (`tasks/bestiary-tier-calibration.py`, 14 personas ×
52 wk = 2634 simulated sessions; the hosted DB was rejected as a single dirty test user). Bands
spread the 6 tiers across the reachable rank range so casual users live C–B–A for a long time and
S is a committed-veteran apex.

| Tier | Dominant-line rank league | Who lives here (sim) |
|---|---|---|
| E | rank 1–4 | day-zero / a brand-new line |
| D | rank 5–10 | first weeks |
| C | rank 11–20 | the broad early-mid plateau |
| B | rank 21–35 | a committed lifter's strong line |
| A | rank 36–55 | advanced; dedicated mid-game |
| S | rank 56+ | veteran apex (advanced/elite late-game) |

**Simulated journey** (rises with progression): beginner C→B/A · female-int C→A/S · advanced
B/A→S · elite A/S→S. Casual real users climb slower than these dedicated personas, so most spend a
long time in C–B; S is genuinely earned.

### Specimen size (session XP *within* your league)

Session XP no longer sets the tier — it sets the **specimen** within your rank league: a routine
session → the base creature; a big-for-your-level session → a *notable/fierce* variant (descriptor +
art emphasis, NOT a tier jump). Reference = the league's typical session XP from the sim
(`tasks/bestiary-tier-calibration.py` rank-bucket medians). This keeps "a huge session feels bigger"
without the inversion. (Precise thresholds finalized at build time from the per-rank reference; a
coarse 3-band split — base / notable / fierce — is fine for Slice 1.)

A **humble session still gets a creature** (the base creature of your league), rendered with grace,
never as failure.

---

## 4. Bosses (special encounters — override the base creature)

A boss is the dominant line's tier creature, **promoted one tier + given a unique gold
epithet + boss styling** (laurel/crown glyph, gold accent, "CHEFE / BOSS" tag).

| Trigger | Boss |
|---|---|
| **PR set** | Named elite of the dominant line — `[Epithet], the [Creature]`. Epithet pool (gold): *Ironheart / the Unbroken / the Sovereign / Dawnbreaker / the Undying / Stormcrown* (en) · *Coração-de-Ferro / o Inquebrável / o Soberano / Quebra-Aurora / o Imortal* (pt). |
| **Rank-up** | The next-tier creature of that line, framed "a greater foe rose." |
| **S-league line** | When the dominant line is at S league (rank 56+), the line's **apex** (The Colossus, etc.) is the base creature; a PR/rank-up there promotes to the named apex boss. |
| **Milestone** (50th/100th session, tonnage totals) | A fixed **legendary** with its own name + lore (a small curated set, e.g. *The First Wyrm / O Primeiro Wyrm* at session 100). |

Priority if multiple fire: Legendary > PR-named > S-apex > rank-up.

---

## 5. Chimeras (combinations — 3+ parts trained significantly)

When a session spreads XP across **3+ body parts** (a full-body / push-pull-legs raid),
the beast becomes a **Chimera** fusing the trained lines — rewards balanced training with
a rarer creature.

- **Full-body (5+ parts)** → `The Primordial Chimera / A Quimera Primordial` (S-tier feel).
- **3–4 parts** → a named hybrid drawing the two highest-XP lines, e.g. arms+back →
  `The Winged Ripper / O Estraçalhador Alado`; chest+legs → `The Walking Bastion /
  O Bastião Ambulante`. Curate ~8–10 two-line hybrids for v1; fall back to
  `A Three-Fanged Chimera / A Quimera de Três Presas` when no curated pair matches.
- Chimeras render the **multi-hue** rail emphasized (the trained parts' colors).

---

## 6. Achievement phrases (the "your sword arm is improving" line)

One short flavor line, **highest-priority applicable** trait wins. (en / pt)

| Trait (priority order) | Phrase |
|---|---|
| PR | A new legend is forged. / Uma nova lenda é forjada. |
| Comeback (dormant part returned) | The dormant beast stirs. / A fera adormecida desperta. |
| S-rank | Few have felled its equal. / Poucos abateram algo assim. |
| Chimera / full-body | You faced many at once. / Você enfrentou muitos de uma vez. |
| High volume (top-decile sets) | Relentless — the horde fell. / Implacável — a horda tombou. |
| Arms dominant | Your sword arm sharpens. / Seu braço de espada se afia. |
| Legs dominant | Your foundation deepens. / Sua base se aprofunda. |
| Back dominant | Iron wings unfold. / Asas de ferro se abrem. |
| Chest dominant | The bulwark advances. / A muralha avança. |
| Shoulders dominant | You carry the sky. / Você carrega o céu. |
| Core dominant | The coil tightens. / A espiral se aperta. |
| Cardio dominant | Swift as the storm. / Veloz como a tempestade. |

---

## 7. Overlay layout (photo-hero — the locked direction)

**Two share modes (user-selectable, toggle in the share sheet + a default preference):**
- **Bestiary** (default, playful) — the generated creature below. For most users.
- **Stats** (clean, serious) — no fantasy: PR-hero + a four-stat strip (S1), or the
  six charge-ring "conditioning dashboard" + rank delta (S2). For the serious lifter /
  data-nerd persona. Same photo-hero rule + the same 7-hue identity rail, so both read as
  RepSaga. (Mocks: `docs/phase-39-share-mockups.html`.)

### Bestiary-mode layout

Full-bleed photo, no collars. Bottom block only + a thin 7-hue identity rail + small
wordmark. Bottom-anchored, over a subtle scrim for legibility:

```
⚔ HOJE VOCÊ ABATEU            ← eyebrow (Rajdhani, tracked, gold; "⚜ CHEFE" for bosses)
O Golem de Ferro              ← beast name (Rajdhani display, hero, cream; Cinzel rejected per §17.0c — Rajdhani display is the sanctioned hero register)
◈ RANK C · +618 XP · 8,4 t    ← rank-sigil diamond chip (rotated square, tier letter) + XP + tonnage (Rajdhani numerals)
A muralha avança.             ← achievement phrase (italic, dimAA)
▬▬▬▬▬▬▬ (7-hue rail)          RepSaga
```

Boss = gold accent + laurel/crown glyph; Chimera = emphasized multi-hue rail; Comeback =
eyebrow swaps to "A FERA ADORMECIDA DESPERTA".

---

## 8. Data model

**Static versioned asset, not a DB table** — the bestiary is read-only content, resolved
**client-side** from the post-session summary (which already carries XP, tonnage, dominant
part, PR flag, rank deltas, body-part spread). No query, no new server data, no migration.

- `assets/bestiary/bestiary.json` — `{ slug, line(bodyPart), tier(E–S), kind(standard|boss|chimera|legendary), name{en,pt}, sigil, lore{en,pt} }[]`
- `assets/bestiary/epithets.json` + `chimeras.json` + `achievement_phrases.json`.
- A pure Dart `BestiaryResolver` (unit-testable, deterministic): `(SessionSummary) → BeastCard`. Mirrors a Python catalog-gen if we want a single source, but no SQL parity needed (no server involvement).

---

## 9. Collectible meta (future phase — not v1)

A **Bestiary screen**: the log of creatures felled, with gaps to fill ("you've never
felled a Cardio S-rank," "3 chimeras discovered / 10"). This is the retention multiplier —
it turns variety-of-training into collection. The share overlay is v1; the in-app log +
collection is a fast-follow. (Stays descriptive — a record of what you did, never a
checklist of what you *must* do.)

---

## 10. Open decisions (for the user)

- **Catalog scope for v1:** 42 base + ~6 epithets + ~10 chimeras + 12 phrases + ~3
  legendaries ≈ a tight, shippable set. Expand later.
- ~~**Tier thresholds:** calibrate to the real session-XP histogram before locking §3.~~
  **RESOLVED 2026-06-26** — hosted DB rejected (single dirty test user); calibrated against the
  **persona simulation** (`tasks/bestiary-tier-calibration.py`, parity-locked to the canonical
  XP oracle). Finding: session-XP-driven tiers INVERT as rank climbs (formula decays per-session
  XP), so the model is now **RANK-PRIMARY** — tier = dominant line's rank league (user-locked),
  session XP picks the specimen within the league. NO formula change. See §3.
- **Where the beast appears:** share overlay only (v1) — or also a small post-session
  "beast felled" beat + the collectible log (more scope)?
- **Verb framing:** "felled / abateu" (slayer) vs "hunted / caçou" (hunter) vs
  "encountered / enfrentou". Affects the whole voice.
