#!/usr/bin/env python3
"""Bestiary tier-band calibration (Phase 39).

The bestiary tier is a PURE PRESENTATION mapping layered on top of the LOCKED
XP/rank/level formula — it changes nothing in the balance. It reads two values
already produced by the locked system:
  * session XP   (totalXpEarned for one finished workout)  -> xpTier
  * dominant line's rank (body_part_progress.rank, 1-99)   -> rankCap
and renders tier = min(xpTier, rankCap).

We must NOT calibrate against the hosted DB (single user, dirty test rows).
Instead we drive the canonical persona panel (tasks/rpg-xp-simulation.py) and
read its SIMULATED per-session XP + rank trajectories, exactly like
test/fixtures/generate_rpg_fixtures.py imports the same oracle.

This script does NOT edit the oracle. It REPLAYS simulate_persona's loop at
session granularity, then ASSERTS that its per-session XP sums reconstruct the
oracle's own weekly_xp for every persona/week — a parity guard proving the
replay is faithful to the locked formula (no drift).

Usage:  python tasks/bestiary-tier-calibration.py [--weeks N]
"""
from __future__ import annotations
import argparse
import importlib.util
import os
import random
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_PATH = os.path.join(ROOT, 'tasks', 'rpg-xp-simulation.py')


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # dataclass resolution needs the module registered
    spec.loader.exec_module(mod)
    return mod


sim = _load('rpg_xp_simulation', SIM_PATH)


def replay_sessions(persona_key, weeks, seed=42, gate=True, detail=False):
    """Faithful copy of sim.simulate_persona's loop, capturing per SESSION:
    (week, total_xp, dominant_bp, dominant_rank_after, by_bp). Returns
    (sessions, weekly_xp_by_week) so the caller can parity-check against the
    oracle. RNG draws are issued in the SAME order as the oracle (one per set).

    detail=True also records each session's exercise/set breakdown (the real
    user-experience granularity: which exercise, weight x reps, per-set XP)."""
    rng = random.Random(seed)
    persona = sim.PERSONAS[persona_key]
    nf_rate = persona.nf_rate

    xp_pool = {p: 0.0 for p in sim.BODY_PARTS}
    weights = dict(persona.starting_weights)
    peak_loads = dict(persona.starting_weights)
    best_by_band = {}
    schedule = sim.WEEK_SCHEDULES_PANEL[persona.schedule_key]
    reps_scheme = persona.reps_scheme or sim.DEFAULT_REPS_PANEL
    session_num = 0
    smurf_done = False

    vit_ewma = {bp: 0.0 for bp in sim.ACTIVE_RANKS}
    vit_ref_peak = {bp: 0.0 for bp in sim.ACTIVE_RANKS}
    vol_history = {bp: [] for bp in sim.ACTIVE_RANKS}
    base_recenter = sim.STRENGTH_BASE_RECENTER if gate else 1.0

    sessions = []
    weekly_xp_by_week = {}

    for week in range(1, weeks + 1):
        weekly_count = defaultdict(float)
        weekly_xp = defaultdict(float)
        bp_session = defaultdict(int)
        weekly_vol_per_bp = defaultdict(float)
        prog = (
            sim._tapered_progression(persona.progression_pct, persona.half_life_weeks, week)
            if persona.tapering
            else persona.progression_pct
        )

        if gate:
            vmult_map = {
                bp: sim.strength_vitality_mult(sim.strength_vpct(bp, vit_ewma, vit_ref_peak))
                for bp in sim.ACTIVE_RANKS
            }
        else:
            vmult_map = 1.0

        is_layoff = week in persona.layoff_weeks
        if not is_layoff:
            cap = persona.sessions_per_week_cap
            week_schedule = schedule if cap is None else schedule[:cap]
            for day in week_schedule:
                session_num += 1
                for bp in sim.SESSION_BODY_PARTS.get(day, set()):
                    bp_session[bp] += 1
                novelty_count = defaultdict(float)
                session_xp = defaultdict(float)  # CAPTURE (telemetry only)
                session_detail = []              # CAPTURE exercise/set breakdown

                for exercise, n_sets in sim.DAY_TEMPLATES_PANEL[day]:
                    r = reps_scheme.get(exercise, sim.DEFAULT_REPS_PANEL.get(exercise, 5))
                    diff_m = sim.difficulty_mult_for_alias(exercise)
                    real_slug = sim.SIM_ALIAS_TO_DEFAULT_SLUG.get(exercise, exercise)
                    distribution = sim._attribution_for(exercise)

                    use_smurf = (
                        not smurf_done and session_num == 1
                        and persona.smurf_session
                        and exercise in persona.smurf_session
                    )
                    if use_smurf:
                        sw, sr = persona.smurf_session[exercise]
                        ex_set_xps = []
                        for _ in range(n_sets):
                            cr = {p: sim.rank_for_xp(xp_pool[p]) for p in sim.BODY_PARTS}
                            nf = rng.random() < nf_rate
                            awarded, vol, _comp, best_by_band = sim.compute_set_xp(
                                exercise, sw, sr, novelty_count, weekly_count, peak_loads,
                                difficulty_mult=diff_m,
                                bodyweight_kg=persona.bodyweight_kg,
                                slug=real_slug,
                                current_ranks=cr,
                                best_by_band=best_by_band,
                                bp_session_count=bp_session,
                                near_failure=nf,
                                female=persona.female,
                                vmult=vmult_map,
                                base_recenter=base_recenter,
                            )
                            for bp2, xp in awarded.items():
                                xp_pool[bp2] += xp
                                weekly_xp[bp2] += xp
                                session_xp[bp2] += xp  # CAPTURE
                            for bp2, share in distribution.items():
                                if bp2 in vit_ewma:
                                    weekly_vol_per_bp[bp2] += vol * share
                            ex_set_xps.append(sum(awarded.values()))
                        if detail:
                            session_detail.append((exercise + '*', sw, sr, ex_set_xps))
                        smurf_done = True
                        continue

                    w = weights.get(exercise, 1.0)
                    ex_set_xps = []
                    for _ in range(n_sets):
                        cr = {p: sim.rank_for_xp(xp_pool[p]) for p in sim.BODY_PARTS}
                        nf = rng.random() < nf_rate
                        awarded, vol, _comp, best_by_band = sim.compute_set_xp(
                            exercise, w, r, novelty_count, weekly_count, peak_loads,
                            difficulty_mult=diff_m,
                            bodyweight_kg=persona.bodyweight_kg,
                            slug=real_slug,
                            current_ranks=cr,
                            best_by_band=best_by_band,
                            bp_session_count=bp_session,
                            near_failure=nf,
                            female=persona.female,
                            vmult=vmult_map,
                            base_recenter=base_recenter,
                        )
                        for bp2, xp in awarded.items():
                            xp_pool[bp2] += xp
                            weekly_xp[bp2] += xp
                            session_xp[bp2] += xp  # CAPTURE
                        for bp2, share in distribution.items():
                            if bp2 in vit_ewma:
                                weekly_vol_per_bp[bp2] += vol * share
                        ex_set_xps.append(sum(awarded.values()))
                    if detail:
                        session_detail.append((exercise, w, r, ex_set_xps))

                # End of session — record it (rank AFTER, like SharePayload.bpRankAfter)
                total = sum(session_xp.values())
                if session_xp:
                    dom = max(session_xp, key=session_xp.get)
                    dom_rank = sim.rank_for_xp(xp_pool[dom])
                    nparts = sum(1 for v in session_xp.values() if v > 0)
                    rec = {
                        'week': week, 'session': session_num, 'total_xp': total,
                        'dom': dom, 'dom_rank': dom_rank, 'nparts': nparts,
                        'day': day,
                    }
                    if detail:
                        rec['exercises'] = session_detail
                    sessions.append(rec)

            for ex in weights:
                weights[ex] *= (1.0 + prog)

        if gate:
            for bp in sim.ACTIVE_RANKS:
                vol_history[bp].append(weekly_vol_per_bp.get(bp, 0.0))
                vol_history[bp].extend([0.0] * (sim.DAYS_PER_WEEK - 1))
            sim.advance_vitality_week(vol_history, vit_ewma, vit_ref_peak)

        weekly_xp_by_week[week] = {p: v for p, v in weekly_xp.items()}

    return sessions, weekly_xp_by_week


def parity_check(persona_key, weeks):
    """Assert replay per-session XP reconstructs the oracle's weekly_xp."""
    sessions, weekly = replay_sessions(persona_key, weeks)
    oracle = sim.simulate_persona(persona_key, weeks=weeks, seed=42, gate=True)
    # oracle snapshot weekly_xp is int-truncated per bp; compare on int totals.
    for snap in oracle:
        wk = snap['week']
        o_total = sum(snap['weekly_xp'].values())
        r_total = int(sum(int(v) for v in weekly[wk].values()))
        # oracle truncates per-bp BEFORE summing; mirror that.
        r_total_trunc = sum(int(v) for v in weekly[wk].values())
        if o_total != r_total_trunc:
            return False, f"week {wk}: oracle {o_total} != replay {r_total_trunc}"
    return True, f"{len(sessions)} sessions"


def pct(xs, p):
    if not xs:
        return 0
    s = sorted(xs)
    i = min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))
    return s[i]


def dump_sample_sessions(persona_keys, weeks, n_each=3):
    """Prove the exercise/set granularity: print full session breakdowns
    (exercise, weight x reps x sets, per-set XP, session total, dominant rank)
    for the first n_each sessions of each persona. * = smurf fake-1RM set."""
    print("\n=== SAMPLE SESSIONS (exercise/set granularity — real user experience) ===")
    for pk in persona_keys:
        sess, _ = replay_sessions(pk, weeks, detail=True)
        p = sim.PERSONAS[pk]
        print(f"\n  --- {pk} :: {p.name} (bw {p.bodyweight_kg}kg{', F' if p.female else ''}) ---")
        for s in sess[:n_each]:
            print(f"   wk{s['week']} session#{s['session']} [{s['day']}]  "
                  f"-> TOTAL {s['total_xp']:.0f}xp  dom={s['dom']} rank{s['dom_rank']}  "
                  f"parts={s['nparts']}")
            for (ex, w, r, set_xps) in s.get('exercises', []):
                xps = " ".join(f"{x:.0f}" for x in set_xps)
                print(f"        {ex:<16} {w:>6.1f}kg x{r:>2}  "
                      f"x{len(set_xps)}sets  setXP=[{xps}]  (sum {sum(set_xps):.0f})")


def eval_model(all_sessions, xp_bands, rank_caps, label):
    TIERS = ['E', 'D', 'C', 'B', 'A', 'S']

    def xp_tier(x):
        for i, b in enumerate(xp_bands):
            if x < b:
                return i
        return 5

    def rank_cap(r):
        t = 0
        for i, minr in enumerate(rank_caps, start=1):
            if r >= minr:
                t = i
        return t

    n = len(all_sessions)
    rows = {}
    for mode, gated in [("xp-only", False), ("gated", True)]:
        c = defaultdict(int)
        capped = 0
        for s in all_sessions:
            xt = xp_tier(s['total_xp'])
            if gated:
                rc = rank_cap(s['dom_rank'])
                ft = min(xt, rc)
                if rc < xt:
                    capped += 1
            else:
                ft = xt
            c[TIERS[ft]] += 1
        rows[mode] = (dict(c), capped)
    print(f"\n  [{label}]  XP_BANDS={xp_bands}  RANK_CAPS={rank_caps}")
    for mode in ("xp-only", "gated"):
        c, capped = rows[mode]
        line = " ".join(f"{t}:{100*c.get(t,0)//n:>2}%" for t in TIERS)
        extra = f"  capped={capped} ({100*capped//n}%)" if mode == "gated" else ""
        print(f"     {mode:<8}: {line}{extra}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--weeks', type=int, default=52)
    ap.add_argument('--sample', action='store_true', help='dump exercise/set breakdowns')
    args = ap.parse_args()
    W = args.weeks

    panel = list(sim.PANEL_ORDER)
    print(f"=== Parity guard (replay per-session sums == oracle weekly_xp), weeks={W} ===")
    all_sessions = []
    per_persona = {}
    ok_all = True
    for pk in panel:
        ok, msg = parity_check(pk, W)
        flag = "OK " if ok else "FAIL"
        if not ok:
            ok_all = False
        print(f"  [{flag}] {pk:<22} {msg}")
        sess, _ = replay_sessions(pk, W)
        per_persona[pk] = sess
        all_sessions.extend(sess)
    print(f"  => parity {'PASS' if ok_all else 'FAIL'}; total sessions={len(all_sessions)}")
    if not ok_all:
        print("  ABORT: replay drifted from oracle — bands not trustworthy.")
        return

    xps = [s['total_xp'] for s in all_sessions]
    print(f"\n=== Global session-XP distribution ({len(xps)} sims, weeks={W}) ===")
    print(f"  min={min(xps):.0f} max={max(xps):.0f} mean={sum(xps)/len(xps):.0f}")
    for p in [5, 10, 25, 33, 50, 60, 66, 75, 80, 85, 90, 95, 98, 99, 100]:
        print(f"   p{p:>3}: {pct(xps, p):.0f}")

    print("\n=== Per-persona (final avg active rank @ wk{}, session-XP p10/50/90) ===".format(W))
    for pk in panel:
        sess = per_persona[pk]
        if not sess:
            continue
        xs = [s['total_xp'] for s in sess]
        oracle = sim.simulate_persona(pk, weeks=W, seed=42, gate=True)
        avg_rank = sim_avg_rank(oracle[-1])
        print(f"  {pk:<22} avgRank={avg_rank:4.1f}  n={len(xs):>3}  "
              f"p10={pct(xs,10):>4.0f} p50={pct(xs,50):>4.0f} p90={pct(xs,90):>5.0f} max={max(xs):>5.0f}")

    print("\n=== Session XP bucketed by DOMINANT-LINE RANK (drives rankCap design) ===")
    by_rank = defaultdict(list)
    for s in all_sessions:
        by_rank[s['dom_rank']].append(s['total_xp'])
    buckets = [(1, 1), (2, 4), (5, 9), (10, 15), (16, 24), (25, 39), (40, 99)]
    print(f"  {'rankBucket':<12} {'n':>5} {'p25':>6} {'p50':>6} {'p75':>6} {'p90':>6} {'max':>7}")
    for lo, hi in buckets:
        xs = [x for r, lst in by_rank.items() if lo <= r <= hi for x in lst]
        if not xs:
            print(f"  {f'{lo}-{hi}':<12} {0:>5}")
            continue
        print(f"  {f'{lo}-{hi}':<12} {len(xs):>5} {pct(xs,25):>6.0f} {pct(xs,50):>6.0f} "
              f"{pct(xs,75):>6.0f} {pct(xs,90):>6.0f} {max(xs):>7.0f}")

    # Candidate models — tier = min(xpTier, rankCap). XP bands target the
    # SIMULATED distribution (median ~430); rank caps gate top tiers behind
    # progression so a low-rank fluke session can't mint an S beast.
    print("\n=== Candidate model sweep: tier = min(xpTier, rankCap) ===")
    # A: original spec placeholders (xpTier) + a moderate rank gate
    eval_model(all_sessions, [150, 300, 500, 750, 1100], [1, 5, 11, 20, 38], "A: spec-placeholder xp + rank gate")
    # B: slightly compressed top so A/S a touch more attainable
    eval_model(all_sessions, [160, 320, 520, 780, 1150], [1, 6, 12, 22, 40], "B: compressed-top + later gate")
    # C: xp-only (no rank gate) for contrast
    eval_model(all_sessions, [150, 300, 500, 750, 1100], [1, 1, 1, 1, 1], "C: xp-only (no rank gate)")

    # D: STEEP gate — S reserved for true veterans (closer to the "rank ~80" instinct)
    eval_model(all_sessions, [150, 300, 500, 750, 1100], [1, 6, 14, 30, 55], "D: steep veteran gate")

    # Journey view: tier mix EARLY (wk1-12) vs LATE (wk40-52) under moderate vs steep
    print("\n=== JOURNEY (real user experience): tier mix early(wk1-12) vs late(wk40-52) ===")
    print("  NOTE: XP-driven tiers INVERT over a career — per-session XP DECAYS as rank")
    print("  climbs (tier_diff normalization), so veterans earn SMALLER beasts. Watch it:")
    journey(per_persona, [150, 300, 500, 750, 1100], [1, 5, 11, 20, 38], "XP-driven + moderate gate", rank_primary=False)
    print("\n  RANK-PRIMARY (beast tier = your dominant line's rank league; XP picks the")
    print("  boss/variant WITHIN it) — progression RISES with rank, the RPG fantasy:")
    journey(per_persona, None, [5, 11, 21, 36, 56], "rank-primary", rank_primary=True)

    if args.sample:
        dump_sample_sessions(["beginner", "advanced", "elite", "female_intermediate"], W)


def journey(per_persona, xp_bands, rank_caps, label, rank_primary=False):
    TIERS = ['E', 'D', 'C', 'B', 'A', 'S']

    def rank_tier(r):
        # rank_caps = min rank to ENTER tiers D,C,B,A,S
        t = 0
        for i, minr in enumerate(rank_caps, start=1):
            if r >= minr:
                t = i
        return t

    def tier_of(s):
        if rank_primary:
            return TIERS[rank_tier(s['dom_rank'])]
        x = s['total_xp']
        xt = 5
        for i, b in enumerate(xp_bands):
            if x < b:
                xt = i
                break
        return TIERS[min(xt, rank_tier(s['dom_rank']))]

    print(f"  -- {label} --")
    for pk in ["beginner", "female_intermediate", "advanced", "elite"]:
        sess = per_persona[pk]
        for tag, lo, hi in [("early wk1-12 ", 1, 12), ("late  wk40-52", 40, 52)]:
            sub = [s for s in sess if lo <= s['week'] <= hi]
            if not sub:
                continue
            c = defaultdict(int)
            for s in sub:
                c[tier_of(s)] += 1
            n = len(sub)
            line = " ".join(f"{t}:{100*c.get(t,0)//n:>2}%" for t in TIERS)
            print(f"     {pk:<20} {tag}: {line}")


def sim_avg_rank(snapshot):
    return sum(snapshot['ranks'][bp] for bp in sim.ACTIVE_RANKS) / len(sim.ACTIVE_RANKS)


if __name__ == '__main__':
    main()
