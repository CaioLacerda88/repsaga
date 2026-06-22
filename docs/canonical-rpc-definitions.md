# Canonical RPC Definitions

Single source of truth for **what RepSaga's two most critical RPCs do _now_** —
`save_workout` and `record_session_xp_batch`. Both are redefined verbatim across
many migrations (7 for `save_workout`, 10 for `record_session_xp_batch` — see the
lineage tables below; audit finding M3: figuring out current behavior is a
git-archaeology exercise). This doc captures the **current** definition so a
future XP / vitality change doesn't need to diff every migration that touched it.

**Accuracy rule:** This doc is derived directly from the LATEST migration body —
not summarized from memory. Every section cites `migration:line-range`. When you
redefine either RPC, update this doc in the same PR (it's part of the lockstep
set — see "When you change this").

> Verified against:
> - `save_workout` → `supabase/migrations/00082_vitality_immediacy_save_time_recompute.sql:272-492`
> - `record_session_xp_batch` → `supabase/migrations/00081_phase38f_cardio_titles_and_vitality_gate.sql:677-1216`

---

## 1. `save_workout` — atomic workout persistence + side-effect orchestrator

Current definition: **`00082_vitality_immediacy_save_time_recompute.sql:272-492`**
(CREATE OR REPLACE; signature unchanged from 00079). Nothing later touches it.

### Signature

```sql
save_workout(
  p_workout   jsonb,
  p_exercises jsonb,
  p_sets      jsonb,
  p_cardio    jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
```

- **Returns** `to_jsonb(workouts row)` — the persisted workout row, unchanged
  shape since the function was first written. The PR-2 vitality-debrief UI reads
  before/after vitality from providers, NOT from this return value
  (`00082:268-269`).
- `p_cardio` defaults to `'[]'` so every pre-cardio 3-arg named-params caller
  still resolves (`00078:130-145` added the 4th param via DROP+CREATE to avoid a
  two-overload ambiguity in PostgREST).

### What it does (current step-by-step, `00082:304-488`)

1. **Extract + authorize** (`305-320`). Reads `id / user_id / routine_id /
   finished_at` from `p_workout`. Raises `42501` if `user_id <> auth.uid()`;
   raises `P0002` if the workout row doesn't exist / isn't owned by the user.
2. **Reversal (idempotent re-save)** (`322-350`). Sums THIS session's
   `xp_events.attribution` over ALL keys (including the `cardio` key) and
   decrements `body_part_progress.total_xp` (floored at 0) + recomputes `rank`
   via `rpg_rank_for_xp`. Then DELETEs this session's `cardio_session` xp_events
   so the cardio earn re-inserts from scratch (BUG-RPG-001). This makes a re-save
   converge instead of double-counting.
3. **Replace child rows** (`352-353`). DELETE `workout_exercises` (cascades to
   `sets`) and `cardio_sessions` for this workout.
4. **Update the workout row** (`355-362`). Sets `name / finished_at /
   duration_seconds / notes`, `is_active = false`.
5. **Insert exercises** (`364-371`) from `p_exercises`.
6. **Insert sets** (`373-384`) from `p_sets` (set_type defaults `'working'`,
   is_completed defaults `false`).
7. **Insert cardio sessions** (`386-397`) from `p_cardio` — RAW inputs only
   (duration / distance_m / rpe); earning columns are computed by
   `record_cardio_session`.
8. **Strength XP batch** (`399`): `PERFORM record_session_xp_batch(workout_id)` —
   see §2.
9. **Cardio earn** (`401-404`): `PERFORM record_cardio_session(workout_id)` —
   runs AFTER the strength batch, in the SAME transaction; earns cardio
   `body_part_progress` + writes `cardio_vo2max`. Cardio stays out of
   `character_state` direct writes here (its char-level contribution is handled
   inside the batch as of 38e).
10. **Save-time vitality recompute** (`406-421`, the 00082 addition): gathers
    `v_touched_bps` = DISTINCT attribution keys on THIS session's xp_events (the
    same set the reversal CTE enumerates), then `PERFORM
    recompute_vitality_for_user(user_id, v_touched_bps)` if non-empty. Runs LAST
    among the XP/vitality steps so the cardio XP-gate (§2 / record_cardio_session)
    still reads PRIOR-day vitality before this steps it forward.
11. **Weekly-plan bucket update** (`423-485`). Find-or-create the current-week
    `weekly_plans` row (`FOR UPDATE`); first-completion-wins. If the workout
    matches an uncompleted planned routine slot, stamp
    `completed_workout_id / completed_at`; otherwise append a spontaneous entry
    (`is_spontaneous: true`). No-ops if no plan exists or this workout already
    recorded (`431-443`).
12. **Return** `to_jsonb(workouts row)` (`486-487`).

### Key invariants (do not break)

- **Ownership gate** — `user_id = auth.uid()` check (`310-313`) is the only
  authz; SECURITY DEFINER means the body runs as owner, so this check is
  load-bearing. Never remove it.
- **Idempotent re-save** — the reversal (step 2) + child-row DELETEs (step 3) +
  the cardio-event DELETE make re-saving the SAME workout converge. Any new
  XP/vitality side-effect you add MUST be reversible here or re-saves drift.
- **Vitality ordering** — vitality recompute is the LAST XP step
  (`406-421`), strictly AFTER `record_cardio_session`, because the cardio
  XP-gate reads the body part's PRIOR vitality. Reordering breaks the gate.
- **Per-bp `last_vitality_date` guard** — `recompute_vitality_for_user` only
  steps each body part once per UTC day (first-writer-wins, the
  `body_part_progress.last_vitality_date` column from 00082). save_workout and
  the `vitality-nightly` cron share this guard; it SUPERSEDES `vitality_runs` as
  the dedup authority (`00082:34-41`).
- **Touched-bp set parity** — `v_touched_bps` (`412-417`) and the reversal CTE
  (`325-335`) must enumerate the SAME attribution keys. If they diverge, a part
  gets stepped that wasn't reverted (or vice-versa).
- **SECURITY DEFINER + grant pair** — `REVOKE ... FROM PUBLIC, anon; GRANT ... TO
  authenticated` (`491-492`) must be re-stated verbatim after every CREATE OR
  REPLACE.
- **Return shape** — keep `to_jsonb(workouts row)`. The Dart repository decodes a
  `Workout` from it; the debrief UI does NOT read vitality from here.

### Migration lineage (`save_workout`)

| Migration | Why it (re)defined `save_workout` |
|-----------|-----------------------------------|
| `00005_save_workout_rpc` | Original 3-arg atomic save (workout → exercises → sets in one tx). |
| `00040_rpg_system_v1` | RPG v1: wires in `record_session_xp_batch` call. |
| `00050_save_workout_skip_zero_weight_peak` | Bugfix: bodyweight (weight=0) sets crashed the `exercise_peak_loads` CHECK; skip them. |
| `00063_save_workout_bucket_update` | Phase 26e: extends save to update the current-week `weekly_plans` bucket (find-or-create, first-completion-wins). |
| `00078_phase38b_cardio_sessions` | Phase 38b: **signature change** — DROP+CREATE adds `p_cardio jsonb DEFAULT '[]'`; persists `cardio_sessions`. |
| `00079_phase38c_cardio_earning` | Phase 38c: calls `record_cardio_session` (cardio earning + est-VO₂max). |
| `00082_vitality_immediacy_save_time_recompute` | **CURRENT.** Adds save-time `recompute_vitality_for_user` for touched bps (vitality immediacy). |

---

## 2. `record_session_xp_batch` — per-session strength XP + rank + title writer

Current definition: **`00081_phase38f_cardio_titles_and_vitality_gate.sql:677-1216`**
(CREATE OR REPLACE; body is a verbatim copy of 00080 with the cardio title
VALUES rows + `saga_unending` char-level rung added). 00082 does NOT touch it.

### Signature

```sql
record_session_xp_batch(p_workout_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
```

Side-effect-only (`RETURNS void`). Called by `save_workout` (step 8) inside the
same transaction.

### What it does (current step-by-step, `00081:739-1212`)

1. **Resolve user + raise on missing** (`740-744`). Looks up `workouts.user_id`;
   raises `P0002` if not found.
2. **Read profile** (`746-748`): `bodyweight_kg`, `gender` (feed the
   strength-tier + bodyweight-load math).
3. **Pre-snapshot** (`750-758`): `v_pre_ranks` (per-bp rank map),
   `v_pre_total_xp`, and `v_pre_char_level := rpg_active_body_part_level(user)`
   over the SEVEN active tracks (six strength + cardio; denominator stays 4 —
   38e).
4. **Load peak map** (`760-772`): `exercise_peak_loads.peak_weight` for the
   exercises in this session (completed working sets, reps ≥ 1).
5. **Weekly volume window** (`774-809`): sums per-bp attribution shares from the
   user's xp_events in the last 7 days EXCLUDING this session, into
   `v_weekly_vol[1..7]` (chest, back, legs, shoulders, arms, core, cardio). Feeds
   the weekly cap.
6. **Per-set loop** (`811-970`) over completed working sets where
   `muscle_group <> 'cardio'` (cardio is earned by `record_cardio_session`, NOT
   here — the 38a save-gate). For each set:
   - Resolve `xp_attribution` (fallback to `{primary_muscle: 1.0}`).
   - Forward-monotonic peak update in `v_peaks_map` (`839-844`).
   - `effective_weight = weight + bodyweight_kg × ratio` when
     `uses_bodyweight_load` (`846-852`).
   - Dominant body part + its current rank (`854-865`).
   - Compute the **11-multiplier chain** (`867-886`): `implied_tier`,
     `tier_diff_mult`, `abs_strength_premium`, `overload_mult`, `frequency_mult`,
     `near_failure` (+0.10 intensity), `base_xp`, `intensity`, `strength_mult`,
     `difficulty_mult`.
   - **Per-attribution-key inner loop** (`893-942`): per bp, `novelty =
     exp(-session_vol/15)`, `cap = 0.3 if weekly_vol ≥ 15 else 1.0`; the per-bp
     XP is `base × intensity × strength × novelty × cap × difficulty ×
     tier_diff × asp × overload × frequency × attr_share` (`923-933`). Maps
     `'chest'..'cardio'` → index 1..7; raises `22023` on an unknown key.
   - Build the per-set `payload` (dominant novelty/cap + all multipliers,
     rounded to 4dp) + `attribution` (`{bp: xp}`) + `total_xp` (`944-969`).
7. **Early-out** if no events (`972`).
8. **Insert xp_events** (`974-982`): one `'set'` event per set,
   `ON CONFLICT (user_id, set_id) WHERE set_id IS NOT NULL DO NOTHING`
   (the per-set idempotency key).
9. **Upsert `body_part_progress`** (`984-1006`): `total_xp += EXCLUDED`, rank
   recomputed via `rpg_rank_for_xp`, `last_event_at` stamped. Inserts a row at 0
   vitality for first-touch parts.
10. **Upsert `exercise_peak_loads`** (`1008-1035`): forward-only
    (`WHERE EXCLUDED.peak_weight > existing`).
11. **Upsert `exercise_peak_loads_by_rep_range`** (`1037-1077`): best
    weight/reps per `(exercise_slug, rep_band)`.
12. **Post-snapshot** (`1079-1086`): `v_post_ranks`, `v_post_total_xp`,
    `v_post_char_level` over the seven active tracks.
13. **Title award — body-part rank crossings** (`1088-1186`): inserts
    `earned_titles` (`is_active = FALSE`) for every rung whose threshold is in
    `(pre_rank, post_rank]` for its body part. The VALUES list carries all six
    strength tracks + the **13 cardio rungs** (38f addition);
    `ON CONFLICT DO NOTHING`.
14. **Title award — character-level crossings** (`1188-1205`): if
    `post_char_level > pre_char_level`, insert level-threshold titles in
    `(pre, post]` — incl. `saga_unending@172` (38f addition).
15. **Title award — cross-build distinctions** (`1207-1211`): inserts whatever
    `evaluate_cross_build_titles_for_user(user)` returns (now cardio-aware —
    `the_forged_wind`, `storm_tempered`, tightened `iron_bound`).

### Key invariants (do not break)

- **Cardio exclusion** — the per-set loop, peak upserts, and rep-band upserts all
  filter `ex.muscle_group::text <> 'cardio'` (`831, 1018, 1049`). Strength XP
  must NEVER earn from cardio sets — that's the 38a save-gate that closed the
  latent mis-attribution bug. Cardio earns via `record_cardio_session`.
- **Per-set idempotency** — `ON CONFLICT (user_id, set_id) ... DO NOTHING`
  (`982`) means re-running the batch for the same sets is a no-op. This is why
  save_workout's reversal (§1 step 2) must run BEFORE re-batching.
- **11-multiplier formula coupling** — the chain at `923-933` is the Phase 29 v2
  + 29.6 LOCKED formula. It is mirrored in the Python sim
  (`docs/` cardio/xp simulations) and the Dart parity helpers, and pinned by the
  integration parity fixtures. Touching ANY factor here = a multi-site formula
  migration (see "When you change this").
- **Forward-monotonic peaks** — `exercise_peak_loads` upsert is guarded
  `WHERE EXCLUDED.peak_weight > existing` (`1035`); peaks never regress.
- **Attribution vs payload columns** — `xp_events.attribution` is the canonical
  `{body_part: xp}` map that save_workout's reversal + vitality steps READ;
  `xp_events.payload` is the diagnostic multiplier breakdown, NOT read back. Keep
  the reversal-relevant truth in `attribution`.
- **Seven active tracks / denom 4** — char-level snapshots (`758, 1086`) use
  `rpg_active_body_part_level` over six strength + cardio. Don't silently change
  the active-track set.
- **Title rows are append-only** — all three title inserts are
  `is_active = FALSE` + `ON CONFLICT DO NOTHING`. Never DELETE/revoke an earned
  title from here (the 38f `iron_bound` tightening is FUTURE-awards-only —
  `00081:24-28`).
- **SECURITY DEFINER + grant pair** — `REVOKE ... FROM PUBLIC, anon; GRANT ... TO
  authenticated` (`1215-1216`) re-stated after CREATE OR REPLACE.

### Migration lineage (`record_session_xp_batch`)

| Migration | Why it (re)defined `record_session_xp_batch` |
|-----------|----------------------------------------------|
| `00040_rpg_system_v1` | Original RPG v1 batch writer (per-set xp_events + body_part_progress). |
| `00050_save_workout_skip_zero_weight_peak` | Skip weight=0 sets from peak upserts. |
| `00054_record_xp_with_difficulty_mult` | Phase 24a: fetch + apply `exercises.difficulty_mult` as final multiplier. |
| `00057_record_xp_with_bodyweight_load` | Phase 24c: `effective_weight = bodyweight + load` for bodyweight exercises. |
| `00059_phase24d_calibration_propagation` | Phase 24d: propagate the six-archetype balance sign-off constants. |
| `00060_titles_award_at_detection` | Phase 26d: INSERT `earned_titles` at threshold-crossing time. |
| `00065_phase29_xp_formula_v2` | Phase 29 v2 + 29.6: wholesale rewrite to the LOCKED 11-multiplier chain. |
| `00077_phase38a_cardio_save_gate` | Phase 38a: gate cardio sets OUT of the strength XP path (`muscle_group <> 'cardio'`). |
| `00080_phase38e_cardio_in_character_level` | Phase 38e: cardio joins the active track set for Character Level. |
| `00081_phase38f_cardio_titles_and_vitality_gate` | **CURRENT.** Adds the 13 cardio body-part title rungs + `saga_unending@172`. |

---

## 3. When you change either RPC — move these in lockstep

Both RPCs participate in the **`pr-decomposition-parity-invariant`** discipline
(MEMORY → `feedback_pr_decomposition_parity_invariant.md`). The XP/vitality
formula lives in three mirrored places; a change to one without the others is a
parity break:

1. **The SQL** (this RPC) — the production writer.
2. **The Python simulation** (`docs/` XP / cardio sims) — the source-of-truth
   that may move AHEAD of consumers in a decomposed PR.
3. **The Dart parity helpers** (`lib/features/rpg/domain/...`,
   `VitalityCalculator`, `cross_build_title_evaluator.dart`) — read-only mirrors
   for display + client-side preview.
4. **The integration parity fixtures + tests** (`test/integration/`, the
   record_set_xp / vitality parity oracles) — pin SQL ↔ Dart ↔ fixture to 1e-4.

**Rules from the parity invariant:**

- The oracle (fixture) must move **atomically with the consumers** (Dart + SQL).
  The source-of-truth (Python sim) may lead. Skipping parity tests across a PR
  boundary is a code smell (Phase 29 PR-1 reverted a wrong-direction fixture
  regen for exactly this).
- Vitality additionally couples save_workout ↔ `recompute_vitality_for_user`
  (SQL) ↔ the `vitality-nightly` Edge Function ↔ `VitalityCalculator` (Dart).
  The formula constants (τ_up=14d, τ_down strength=42d / cardio=21d, 7-day
  window, α derivations, peak-monotonic) are RELOCATED, not re-tuned, and pinned
  byte-for-byte across all four (`00082:21-25`).
- After any change: re-run the FULL integration suite and diff against main
  (the suite is red on main for unrelated reasons — gate is "no NEW failures",
  MEMORY → `project_integration_suite_red_on_main.md`).
- Re-state the `REVOKE/GRANT` pair verbatim and re-update THIS doc's cited
  `migration:line` ranges in the same PR.
