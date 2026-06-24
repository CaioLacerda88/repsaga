# Work In Progress

Active branch work. Removed once merged. Empty when no in-flight work exists —
backlog/parked items live in `docs/PROJECT.md` §2.

---

## SCOPING (plan node) — Phase Vitality-3: Strength Vitality Gate + recalibration

**Status:** spec/scoping. NOT building. Decisions D1–D6 must be locked with the user first.
Source: 2026-06-24 product-owner science gate + tech-lead calibration scope.

### The mechanic
Gate strength set XP by per-body-part conditioning:
```
vpct  = clamp(vitality_ewma / vitality_ref_peak, 0, 1)     (ref_peak ≤ 0 → 1.0)
vmult = FLOOR + (1 − FLOOR) × vpct
set_xp_gated = (existing 11-multiplier chain) × vmult        ← 12th factor, applied last
```
- **Denominator = `vitality_ref_peak`** (decaying, re-baselines to current sustainable level), NOT the frozen `vitality_peak`. This is what makes it science-consistent (see below).
- **Per body part**, computed ONCE from PRE-session vitality (mirrors the cardio gate timing; non-circular — recompute runs after the XP writes). Applied keyed by attribution body part inside the set loop.
- **Major de-risk:** `vitality_ref_peak` is ALREADY maintained for every strength body part (migration 00083 + the save-time recompute 00082:420). Nothing new to compute server-side — we read existing columns. The cardio gate (00081) is the exact implementation template.

### Science verdict (product-owner): CONSISTENT (one calibration check)
- Muscle-memory objection (penalizing returners) is **neutralized**: ref_peak decays (~21d half-life) + EWMA rebuilds fast (τ_up≈2wk → ~63% wk2, ~86% wk4) → returner's vmult ≈ 0.64 (wk1) → 0.88 (wk2) → 0.90+ (wk3-4), matching the biology (Halonen 2024 ~5wk full recovery; Cumming 2024 myonuclear permanence).
- **Decisive:** `tier_diff_mult` already gives a strong returner a huge bonus (Diego ≈ 2.76×), so net wk1 = 2.76×0.64 ≈ 1.77× — returner STILL out-earns a consistent lifter. The vmult dip never makes return *punitive*.
- Defended: FLOOR 0.40 (= existing STRENGTH_MULT_FLOOR; sweep 0.50 for muscle-memory), τ_up 2wk, τ_down 6wk. One check: calibrate "Diego-returning" across the full chain so tier_diff × vmult × abs_strength_premium doesn't OVERSHOOT.
- Surfaced (Phase-39 scope, not this gate's burden): ACWR spike-on-return risk → handled by the rest-safety layer.

### Critical finding (the linchpin) + loop stability
- **The 13-persona sim panel models ZERO vitality today** (`simulate_persona` never calls update_vitality). So step 1 is BUILD per-bp EWMA + ref_peak into the panel, THEN gate, THEN re-center. Largest risk; PR 1 is sim-only to validate in isolation.
- **Feedback loop is SEVERED by construction:** vitality EWMA is fed by VOLUME LOAD (share-count `vol×share`), NOT by gated XP. So vmult throttles the rank currency but never the vitality input → no runaway/collapse possible. (Must confirm the sim models EWMA from volume_load, not gated xp — the single most important stability property.)

### Re-centering (the crux)
Adding vmult≤1.0 slows EVERY non-100% persona → 13/13 breaks. Restore steady-state:
1. Build vitality into the panel; read each consistent persona's converged `vpct` over wks 8-12 → define `VPCT_NORMAL` (median of the 6 consistent personas; hypothesis ≈0.92-0.98, measured not asserted).
2. Sweep a global `STRENGTH_BASE_RECENTER` (≈ `1/vmult_normal`) until the 6 consistent personas land on their CURRENT rank timeline (±0.5 rank); only sandbagger/returner diverge. Global base scale, NOT per-rep-tier (preserves the Phase-29 curve shape).

### Acceptance: 15/15 (13 existing + 2 new)
- 13 existing hit their bands post-recenter; the 6 consistent within ±0.5 rank of today; anti-cheese invariants hold.
- **SANDBAGGER** (high rank, light+inconsistent) → vpct ~0.4-0.6 permanent → progresses SLOWER than consistent `advanced`. (Can't coast on past rank.)
- **DETRAINED RETURNER** (was high, 8wk layoff, returns consistent) → vmult recovers to ≥0.90 within 2-4wk; rank NEVER drops during layoff. (Proves ref_peak is the right denominator — frozen peak couldn't produce this curve.)
- 4-site parity (sim↔fixture↔Dart↔SQL @1e-4) on the extended `set_xp_v2` matrix incl. the `vmult` column.

### Decomposition (parity-safe)
- **PR 1 — sim only** (source-of-truth may move ahead): vitality in panel + gate + 2 personas + recenter sweep → 15/15 in sim; `vmult` defaults 1.0 so the existing fixture regenerates byte-identical (parity NOT broken). Update `docs/xp-balance-baseline.md`.
- **PR 2 — atomic consumer adoption**: regen fixture oracle + Dart `xp_calculator` + new migration `00084_phase39_strength_vitality_gate.sql` (gate both RPCs + helper + recentered base) in ONE PR → 4-site parity green within the PR. Apply 00084 local→hosted (no schema change, hot-path RPC redefine → smoke-test).
- **PR 3 (optional)** — "Strength conditioning charged" post-session debrief beat (mirrors cardio). Defer unless wanted this phase.

### Files
sim `tasks/rpg-xp-simulation.py` · `docs/xp-balance-baseline.md` · `test/fixtures/generate_rpg_fixtures.py` + `rpg_xp_fixtures.json` · `lib/features/rpg/domain/xp_calculator.dart` · NEW `supabase/migrations/00084_phase39_strength_vitality_gate.sql`

### DECISIONS — LOCKED (user, 2026-06-24)
- **D6:** ✅ THROTTLE-ONLY — ranks stay monotonic (saga inviolate); vitality slows XP earn-rate only, rank never decays. (Rank-decay rejected — bigger change + loss-aversion risk; would be its own phase.)
- **D1:** ✅ SIM DECIDES — sweep FLOOR ∈ {0.40, 0.50}, pick on returner week-1 feel during PR1.
- **D2:** ✅ re-center via global `base` scale (`STRENGTH_BASE_RECENTER`), keep FLOOR as independent penalty-depth knob.
- **D3:** ✅ VPCT_NORMAL = median converged vpct of the 6 consistent personas (measured in-sim).
- **D4:** ✅ tune sandbagger depth + returner recovery in the sim (returner ≥0.90 vmult by wk2-4 is the fixed target; sandbagger must land below `advanced`).
- **D5:** ✅ MECHANIC-ONLY — gate + recalibration (PR1+PR2). No UI debrief this phase; richer surfaces (Charge Ring / comeback / Rest Validation) become their own follow-up phase.

_Decisions locked — ready for PR1 (sim re-calibration) on user's go._

### Future feel-good UX from this data (product-owner — separate track, mostly Phase 39/display)
Per-bp `ewma` / `ref_peak` / `charge%` / all-time peak / τ rates / recency unlock: **Charge Ring** (readiness HUD), **"Your Body Remembers"** comeback beat (muscle-memory as an awakening moment), **Rest Validation** debrief ("chest is charged — rest is smart"; what Habitica/Duolingo structurally can't say), Conditioning Balance radar, rare "Peaked" badge, Weekly Conditioning Report, opt-in predictive "keep it charged" nudge (needs Phase-39 ToS sign-off). Phase-39 v1 standouts: Charge Ring + Comeback + Rest Validation (zero new data, no ToS revision, all thesis-pure). All must be descriptive, never "train-or-lose-it".

_Scoping — awaiting D1–D6 lock._
