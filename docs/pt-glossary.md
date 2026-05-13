# Phase 15f — pt-BR Translation Glossary

**Status:** DRAFT — awaiting user approval before Stage 3 (`supabase/migrations/00033_seed_exercise_translations_pt.sql`).

**Purpose.** This document is the authoritative reference for all pt-BR translations seeded into `exercise_translations` in Phase 15f. It covers two scopes:

1. **Names** — already shipped via ARB in Phase 15c (PR #86–#91) and refined in PR #109 (Core/Bands as English loanwords). Stage 3 reuses these 150 names verbatim. Names are stable; the glossary documents _why_ each convention won so future locales (es-ES, fr-FR) can extend the pattern.
2. **Descriptions + form tips** — net-new content for Stage 3. EN already exists in DB (Phase 12). pt-BR drafts must be generated under the style rules in §5 below.

**User approval is required on §1–§4 before Stage 3 begins.** §5 (style guide) governs Stage 3's AI-drafted descriptions; user reviews the full 150-row seed during Stage 8 staging verification.

---

## 1. Term glossary (recurring nouns/verbs)

Drawn from the 150 already-shipped names in `lib/l10n/app_pt.arb`. Every Stage 3 description must use these terms consistently.

### Equipment

| English                 | pt-BR                              | Notes                                                                                   |
| ----------------------- | ---------------------------------- | --------------------------------------------------------------------------------------- |
| barbell                 | barra                              | "com Barra" suffix when implement is named explicitly                                   |
| dumbbell                | halteres / halter                  | plural for bilateral, singular for unilateral exercises                                 |
| cable                   | cabo                               | "no Cabo" preposition                                                                   |
| machine                 | máquina                            | "na Máquina"                                                                            |
| bodyweight              | livre / corporal / (peso do corpo) | usually implied; "Agachamento Livre" = bodyweight squat                                 |
| kettlebell              | **Kettlebell**                     | loanword, capitalized                                                                   |
| bands / resistance band | **Bands** / faixa                  | loanword for category, but "com Faixa" when used in name (e.g. "Agachamento com Faixa") |
| EZ bar                  | barra W                            | "Rosca com Barra W"                                                                     |
| smith machine           | smith                              | loanword                                                                                |

### Movement verbs / patterns

| English                     | pt-BR                                 | Notes                                                                                               |
| --------------------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------- |
| press (bench)               | supino                                | only for chest press; never for shoulder                                                            |
| press (overhead/shoulder)   | desenvolvimento                       | shoulder press = "Desenvolvimento"                                                                  |
| press (technique loanwords) | press                                 | for "Push Press", "Arnold Press", "Landmine Press", "Pallof Press" — kept English                   |
| row                         | remada                                | "Remada Curvada" (bent-over), "Remada Cavalinho" (T-bar), "Remada Alta" (upright)                   |
| pull (lat pulldown)         | puxada                                | "Puxada na Polia Alta"                                                                              |
| pull-up                     | barra fixa                            | "Barra Fixa Pegada Aberta" (wide-grip), "Barra Fixa Supinada" (chin-up = supinated grip)            |
| squat                       | agachamento                           | "Agachamento com Barra", "Agachamento Búlgaro", "Agachamento Livre" (bodyweight)                    |
| deadlift                    | levantamento terra                    | "Levantamento Terra Romeno" (RDL), "Levantamento Terra Sumo"                                        |
| lunge                       | afundo                                | "Afundo com Halteres", "Afundo Reverso", "Afundo Caminhando"                                        |
| curl (biceps)               | rosca                                 | "Rosca Direta" (straight bar), "Rosca Martelo", "Rosca Scott" (preacher)                            |
| extension (triceps)         | extensão de tríceps                   | for cable/dumbbell triceps work                                                                     |
| extension (legs)            | (none)                                | leg extension = "Cadeira Extensora" (named by machine)                                              |
| curl (legs)                 | (none)                                | leg curl = "Mesa Flexora" (named by machine)                                                        |
| raise (lateral/front)       | elevação                              | "Elevação Lateral", "Elevação Frontal"                                                              |
| raise (calf)                | elevação de panturrilha / panturrilha | both forms in use; prefer "Elevação de Panturrilha" for primary, "Panturrilha Sentado" for variants |
| fly                         | crucifixo                             | "Crucifixo com Halteres", "Crucifixo Invertido" (rear delt), "Crucifixo Inclinado"                  |
| crunch                      | abdominal                             | "Abdominal Bicicleta", "Abdominal no Cabo", "Abdominal Reverso"                                     |
| plank                       | prancha                               | "Prancha Lateral", "Prancha Sobe e Desce"                                                           |
| dip                         | mergulho / paralelas                  | "Mergulho no Banco" (bench dip); "Paralelas" (parallel bar dips, generic)                           |
| pushdown                    | (na polia / na corda)                 | "Tríceps na Polia" (cable pushdown), "Tríceps na Corda" (rope)                                      |
| hip thrust                  | elevação de quadril                   | "Elevação de Quadril com Barra"; bodyweight = "Elevação de Quadril"                                 |
| shrug                       | encolhimento                          | "Encolhimento com Barra" / "com Halteres"                                                           |
| pullover                    | pullover                              | loanword                                                                                            |
| crossover                   | crossover                             | loanword (chest cable work)                                                                         |
| pulldown (straight-arm)     | puxada com braços estendidos          |                                                                                                     |
| good morning                | **Good Morning**                      | loanword                                                                                            |

### Body parts & muscles

| English    | pt-BR                            |
| ---------- | -------------------------------- |
| chest      | peito                            |
| back       | costas                           |
| legs       | pernas                           |
| shoulders  | ombros                           |
| arms       | braços                           |
| core       | **core** (loanword, per PR #109) |
| biceps     | bíceps                           |
| triceps    | tríceps                          |
| quads      | quadríceps                       |
| hamstrings | posteriores / isquiotibiais      |
| glutes     | glúteos                          |
| calves     | panturrilhas                     |
| lats       | dorsais / latíssimo              |
| traps      | trapézio                         |
| delts      | deltoides                        |
| pecs       | peitorais                        |
| abs        | abdômen / abdominais             |

### Grip & position modifiers

| English                    | pt-BR                                                                     |
| -------------------------- | ------------------------------------------------------------------------- |
| close-grip                 | pegada fechada                                                            |
| wide-grip                  | pegada aberta                                                             |
| neutral grip               | pegada neutra                                                             |
| overhand / pronated        | pronada                                                                   |
| underhand / supinated      | supinada                                                                  |
| incline (bench angle up)   | inclinado                                                                 |
| decline (bench angle down) | declinado                                                                 |
| flat                       | reto                                                                      |
| seated                     | sentado                                                                   |
| standing                   | em pé                                                                     |
| single-leg / unilateral    | unilateral                                                                |
| reverse                    | inverso / reverso (verb-dependent — "Rosca Inversa" but "Afundo Reverso") |

---

## 2. Loanwords kept in English (rationale)

The Brazilian fitness vernacular has absorbed several English terms wholesale. Translating them sounds clinical or wrong to gym-goers. Confirmed via PR #109 (Core / Bands) and during Phase 15c.

### Always English

- **Push Press** — technique term, fixed in coaching literature
- **Arnold Press** — eponym
- **Landmine Press** / **Landmine Shoulder Press** — equipment-specific
- **Pallof Press** — eponym
- **Hack Squat** — machine name
- **Hip Thrust** (when discussing the bodyweight category) — but the named exercise is "Elevação de Quadril"; check existing ARB before committing
- **Leg Press** — machine name, universally English
- **Pec Deck** — machine name
- **JM Press** — eponym
- **Step-Up** — fitness vernacular
- **Face Pull** — coaching term
- **Rack Pull** — coaching term
- **Good Morning** — exercise name as proper noun
- **Pendlay Row** — eponym (though the existing ARB renders it as "Remada Pendlay" — note: the eponym attaches to "Remada", not full English)
- **Seal Row** — recent loanword, no settled translation
- **Hollow Body Hold** — gymnastics carryover
- **V-Up** — abbreviation, no clean Portuguese form
- **Flutter Kick** — fitness vernacular
- **Nordic Curl** — eponym (region-named technique)
- **Zottman Curl** — eponym
- **Spider Curl** — already in pt as "Rosca Aranha"; loanword version rejected
- **Kettlebell Swing** — full English (the implement name + verb form)
- **Pull-Through** (cable) — kept as loan in compound: "Pull-Through no Cabo"
- **Dead Bug** — fitness vernacular
- **JM Press** — coaching loanword

### Categories kept English

- **Core** (per PR #109) — Brazilian gym usage
- **Bands** (per PR #109) — equipment category UI label

### Borderline cases (decision needed if any new exercise added)

If a future new exercise's name is a niche English coaching term with no settled translation, default to keeping it English. Better to leave it untranslated than coin a clinical-sounding direct translation. Example: "Cossack Squat" should ship as "Cossack Squat", not "Agachamento Cossaco".

---

## 3. Implement name conventions

When the exercise's primary distinguishing feature is the implement, the convention is `<Movement> com <Implement>` or `<Movement> no <Implement>`:

- "Supino Reto **com Barra**" — Barbell Bench Press (with-suffix when implement adds variant)
- "Supino Reto **com Halteres**" — Dumbbell Bench Press
- "Supino **na Máquina**" — Machine Chest Press (na = on the / at the)
- "Supino **no Cabo**" — Cable Chest Press (no = at the / on the)
- "Levantamento Terra **com Kettlebell**"

When the implement defines a fundamentally different exercise (machine variants), the implement's category-name takes over:

- "**Cadeira Extensora**" (leg extension — the chair is the exercise)
- "**Mesa Flexora**" (leg curl — the table is the exercise)
- "**Leg Press**" (machine name = exercise name; English)

---

## 4. Variant-naming patterns

| Variant              | English suffix     | pt-BR suffix                     |
| -------------------- | ------------------ | -------------------------------- |
| Incline              | Incline X          | X Inclinado                      |
| Decline              | Decline X          | X Declinado                      |
| Flat (default bench) | (omitted) / Flat X | X Reto                           |
| Close-grip           | Close-Grip X       | X Pegada Fechada                 |
| Wide-grip            | Wide-Grip X        | X Pegada Aberta                  |
| Single-leg           | Single-Leg X       | X Unilateral                     |
| Seated               | Seated X           | X Sentado                        |
| Standing             | Standing X         | X em Pé                          |
| Reverse              | Reverse X          | X Reverso (or Inversa for Rosca) |
| Side                 | Side X             | X Lateral                        |

Place modifier **after** the head noun in pt-BR (matches Romance language adjective order):

- "Incline Bench Press" → "Supino **Inclinado**" (modifier follows)
- "Reverse Crunch" → "Abdominal **Reverso**"
- "Lateral Plank" → "Prancha **Lateral**"

---

## 5. Style guide — descriptions + form tips (for Stage 3 AI drafting)

### 5.1 Voice & register

- **Use `você` (informal you), not `o praticante` or `o aluno`.** Gym-context Portuguese is direct.
- Imperative mood for cues ("Mantenha", "Empurre", "Inspire") — same register as a personal trainer giving cues at the rack.
- No academic/clinical jargon. Avoid: "execução biomecânica", "padrão motor", "sinergista". Prefer: "movimento", "como fazer", "músculos auxiliares".
- Reference the EN description as the primary source of truth for _content_ — translate intent, not word-for-word. EN says "Lie back on the bench"; pt should say "Deite no banco" not "Deite-se de costas no banco para iniciar".

### 5.2 Description structure

Mirror the EN structure already shipped (`exercises.description` populated in migrations 00010, 00015, 00018, 00021, 00026):

> [Setup] — 1 sentence on equipment / start position.
> [Execution] — 1 sentence on the actual movement.
> [Targeting/cue] — 1 sentence on what it works or the dominant cue.

Length target: 80–160 characters in pt-BR (slightly longer than EN due to Portuguese being ~10–15% wordier).

### 5.3 form_tips structure

Match the EN convention: 2–4 short imperative bullets joined by `\n` (newline). Each bullet starts with a verb in imperative form. Examples that pass:

- "Mantenha o core firme.\nEmpurre os ombros para trás.\nNão trave os cotovelos."
- "Inspire ao descer.\nExpire ao empurrar.\nControle a fase excêntrica."

Length target: 60–140 characters total.

### 5.4 Vocabulary table for description/form_tips

| EN concept              | pt-BR (preferred)                       | Reject                                           |
| ----------------------- | --------------------------------------- | ------------------------------------------------ |
| reps                    | repetições / reps                       | "movimentos"                                     |
| set                     | série                                   | "round"                                          |
| weight                  | carga / peso                            | (synonyms OK)                                    |
| rest                    | descanso                                | "intervalo" (use only for rest-pause)            |
| range of motion (ROM)   | amplitude                               | "intervalo de movimento" (too literal)           |
| eccentric phase         | fase excêntrica                         | (technical OK)                                   |
| concentric phase        | fase concêntrica                        |                                                  |
| spotter                 | parceiro / spotter                      | both acceptable                                  |
| failure                 | falha                                   |                                                  |
| warm-up set             | aquecimento                             |                                                  |
| working set             | série de trabalho                       |                                                  |
| superset                | bi-set                                  | "supersérie" (less common in BR gyms)            |
| tempo                   | tempo / cadência                        |                                                  |
| breathing               | respiração                              |                                                  |
| brace your core         | contraia o core / mantenha o core firme | "tense seu núcleo"                               |
| neutral spine           | coluna neutra                           |                                                  |
| hip hinge               | padrão de flexão do quadril / hip hinge | both used; prefer hip hinge for advanced lifters |
| knees track over toes   | joelhos alinhados com os pés            |                                                  |
| chest up                | peito para cima                         |                                                  |
| shoulders down and back | ombros para trás e para baixo           |                                                  |
| drive through heels     | empurre pelos calcanhares               |                                                  |
| squeeze                 | contraia                                |                                                  |

### 5.5 Numerical & unit conventions

- Use comma as decimal separator if numbers appear: "2,5 kg" not "2.5 kg".
- Use `kg`, never "quilos" in body content.
- "x" between sets and reps: "3x10" or "3 séries de 10".
- Tempo notation `2-1-2` is fine, no need to translate.

### 5.6 What NOT to translate

- Eponyms in form_tips: if a tip says "Romanian Deadlift hip hinge", keep "Romanian Deadlift" (the exercise is already called "Levantamento Terra Romeno" but the form-cue use stays English when referencing the canonical movement pattern).
- Brand-name machines: "Smith", "Hammer Strength", "Cybex".
- Exercise names that are themselves loanwords (per §2): never translate inside body text.

### 5.7 Quality bar (pre-merge gate)

User reads all 150 (name, description, form_tips) tuples on staging before merge:

- **Hard rejects:** factually wrong cues; awkward/clinical phrasing; inconsistent term use vs. §1; missing description on a row that has EN content.
- **Soft flags:** stylistic preference (single-pass fix-up acceptable).

Effort budget: ~30 seconds per row × 150 = ~75 minutes of focused review.

---

## 6. Stage 3 generation procedure

The implementer of Stage 3 (tech-lead) follows this:

1. **Read this glossary in full.**
2. For each of the 150 default exercises:
   - Pull `name` from `lib/l10n/app_pt.arb` (`exerciseName_<slug>` key) — these are pre-approved.
   - Read EN `description` and `form_tips` from current `exercises` row.
   - Draft pt-BR `description` and `form_tips` per §5 style rules and §1 term conventions.
3. Cross-check every drafted row against §1 vocabulary — search-replace any deviation.
4. Verify spelling with a Portuguese spell-checker pass.
5. Emit single `INSERT ... SELECT FROM (VALUES ...)` JOINed on `exercises.slug` (pattern in PLAN.md Stage 3).
6. Commit; orchestrator triggers spec compliance + code quality reviews; user does the 75-min skim during Stage 8 staging verification.

---

## 7. Out of scope for this glossary

- Translation of UI strings (already complete in Phase 15c).
- Translation of routine names (kept ARB-localized — `localizedRoutineName()` stays in `exercise_l10n.dart`).
- es-ES, fr-FR, or any third locale (future phases will derive their glossaries from this one as the template).

---

## 8. Approval log

- DRAFT created: 2026-04-24 by orchestrator (Claude / Opus 4.7).
- pt-BR conventions sourced from: `lib/l10n/app_pt.arb` (Phase 15c, PR #86–#91), PR #109 (loanwords), and Brazilian gym vernacular as established in popular coaching literature (e.g., `Treino Mestre`, `Hipertrofia.org`).
- **User approval (required before Stage 3):** APPROVED 2026-04-24 — sections 1–4 confirmed; §5 style guide accepted as guidance for Stage 3 drafting; user reviews full 150-row content during Stage 8 staging skim.
