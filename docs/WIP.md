# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

## Phase 32 PR 32j — Peak-load attribution: primary-only semantics

**Branch:** `feature/phase-32j-peak-load-primary-only`

**Source spec:** Decided live during PR 32f device verification.
User caught their stats deep-dive showing shoulders + arms both at
240 kg — multi-BP exercises with secondary attribution were bleeding
their top weight into every touched body-part. Pre-launch, no live
users → destructive replacement of the existing RPC, no sibling.

### Why this exists (locked decision)

Phase 27 L10's `peak_load_per_body_part` RPC (migration 00064) counts
any non-zero attribution toward a body-part's peak. So if a barbell
shoulder press has `xp_attribution = {shoulders: 0.7, arms: 0.3}` and
the user's top set is 30 kg, the same 30 kg shows up as the peak load
for BOTH shoulders AND arms. That's why the user sees
shoulders + arms = 240 kg (a barbell exercise's top weight leaks
into the secondary BP).

User's expectation: peak load = "heaviest single set the user pushed
where this body-part was the **primary** engagement." Pre-launch the
existing values can be destroyed without a backfill story. Migration
00064's docstring even foresaw this:

> "If a future 'strictly primary' variant is wanted, it becomes a
> sibling RPC, not a tweak to this one."

Locked decision: not a sibling. Replace the function body. The Dart
consumer at `rpg_repository.dart:217` continues calling the same
`peak_load_per_body_part(uuid, int, timestamptz)` signature — no
client-side change needed. UI surfaces (Carga pico column) just
re-renders against the new numbers on next load.

### Boundary inventory

**Current RPC** — `supabase/migrations/00064_peak_load_per_body_part.sql:85-118`:
- Signature: `peak_load_per_body_part(p_user_id, p_days, p_end_date) RETURNS TABLE(body_part text, peak_load_kg numeric)`
- Attribution rule: `WHERE share_text::numeric > 0` (any non-zero share counts)
- This is the bug — multi-BP exercises bleed into every touched BP

**Dart consumer** (no changes needed):
- `lib/features/rpg/data/rpg_repository.dart:194-228` — wraps `_client.rpc('peak_load_per_body_part', params: ...)`. Returns `Map<BodyPart, num>`. The return shape stays identical post-swap.
- `lib/features/rpg/providers/stats_provider.dart` — composes the map into `StatsDeepDiveState`
- `lib/features/rpg/models/stats_deep_dive_state.dart` — domain model
- `lib/features/rpg/ui/widgets/volume_peak_block.dart` — the "Carga pico" UI column

**Tests touching the RPC:**
- `test/integration/peak_load_per_body_part_test.dart` — pins the current contract. Will need new test cases for the primary-only semantics; the existing "any non-zero counts" assertions are now wrong and need replacement.

### Decisions locked

- **Replace, don't add a sibling RPC.** Pre-launch, no live users; the existing values can be destroyed without backfill or migration churn. Migration `00071_peak_load_primary_only.sql` runs `CREATE OR REPLACE FUNCTION public.peak_load_per_body_part(...)` with the new body.
- **Signature unchanged.** Same `(uuid, int, timestamptz)` params and same `TABLE(body_part text, peak_load_kg numeric)` return shape. Dart consumer untouched.
- **Primary = the body-part(s) with the MAX `xp_attribution` share for that exercise.** Ties broken by inclusion of all max-share BPs (e.g., if a hypothetical exercise had `{chest: 0.5, back: 0.5}`, the top weight counts toward BOTH). In practice no default exercise has a tied-primary split — every catalog entry has a single dominant BP per `00065_phase29_xp_formula_v2.sql` calibration.
- **Zero-attribution exercises stay excluded.** Same as today — `xp_attribution = NULL` or empty map → not reflected. The `share > 0` filter still applies after primary selection.
- **Window semantics unchanged.** Half-open `(end_date - days, end_date]` on `COALESCE(w.started_at, w.finished_at)` — the same lock-step alignment with Volume column from 00064 stays load-bearing.
- **No backfill, no data cleanup.** The function is pure-read; replacing its body affects nothing in storage.
- **Apply migration mid-PR.** Same pattern as 32e/32f — applying 00071 to hosted Supabase before merge lets the user device-verify the new column values on the stats screen. The user already authorized this pattern on prior PRs.
- **Per `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`:** all reviewer findings fix in cycle.

### Files to create

- [ ] `supabase/migrations/00071_peak_load_primary_only.sql` — `CREATE OR REPLACE FUNCTION` overwriting 00064's body. Same signature, new aggregation:
  1. CTE 1: per-set, per-attribution-entry tuple
     `(set_weight, exercise_id, body_part, share::numeric)`
  2. CTE 2: per-exercise max share
     `SELECT exercise_id, MAX(share) AS max_share FROM cte1 GROUP BY exercise_id`
  3. CTE 3: join CTE 1 ↔ CTE 2 on `exercise_id AND share = max_share AND share > 0`
  4. Final: `SELECT body_part, MAX(weight) GROUP BY body_part`
  - `SECURITY INVOKER`, `STABLE`, GRANT TO authenticated — mirror 00064 exactly
  - Add a comment block at the top documenting the semantic change + linking to PR 32f's device-verification discovery as motivation
  - Include a brief explanatory note: replacing 00064's body rather than adding a sibling RPC is the locked pre-launch decision per the user

### Files to modify

(None on the Dart side — RPC contract unchanged.)

### Tests

- [ ] **Integration test** — `test/integration/peak_load_per_body_part_test.dart`
  - REPLACE the existing "any non-zero counts" assertions with primary-only semantics
  - Add a test case for the user's specific bug: seed a multi-BP exercise (shoulder press with shoulders=0.7 + arms=0.3), insert a 30 kg set, an arms-only exercise (curl, arms=1.0) with a 20 kg set → assert `peak_load_per_body_part` returns `{shoulders: 30, arms: 20}` (the 30 kg does NOT bleed into arms)
  - Add a test case for a tie: hypothetical exercise with `{chest: 0.5, back: 0.5}` at 40 kg → both BPs should show 40 kg (max-share inclusion is not exclusive)
  - Add a test case for zero attribution: `xp_attribution = NULL` set at 50 kg → empty result for all BPs
  - Add a test case for the window: workout at exactly `end_date - days` → out; workout at exactly `end_date` → in (half-open window unchanged)

### Verification

- `make ci` green (the integration test re-runs against the new RPC against local Supabase)
- Apply migration 00071 to hosted Supabase mid-PR (same pattern as 32e/32f)
- Physical-Android verification: open stats deep-dive, scroll to Carga pico — verify shoulders/arms values are NOT identical now (the bug fix). User caught the bug at `shoulders + arms = 240 kg`; post-fix they should diverge.
- Skip widget tests — UI just re-renders the map; no widget-tier contract changed.

### Out of scope

- Backfill of historical `peak_load_per_body_part` snapshots into a stored column. The RPC is pure-read; no precomputed cache exists.
- Sibling RPC `peak_load_per_body_part_any_attribution` — explicitly rejected; pre-launch destruction is fine.
- Stats screen UI changes (color, label, layout) — out of scope; the Carga pico column re-renders against the new numbers without any visual rework.
- iOS scope (Android-first launch).
