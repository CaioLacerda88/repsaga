# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

---

## Wire Deno tests into CI (PLAN.md backlog → Architectural follow-ups)

**Branch:** `ci/wire-deno-tests`

Per `PLAN.md` `## Active Backlog` → `### Architectural follow-ups (parked, no urgency)`:

> **Wire Deno tests into CI** — `supabase/functions/**/*.test.ts` files
> exist (notably `vitality-nightly/auth.test.ts` from PR #151) but no
> workflow runs them. A small CI step would catch Edge Function regressions.

### Inventory

Two existing Deno test files (no other Edge Function tests yet):
- `supabase/functions/vitality-nightly/auth.test.ts` — JWT role-claim decoding for the cron handler's authorization gate.
- `supabase/functions/_shared/google_play.test.ts` — Play state→DB state mapping + Pub/Sub JWT verification for the subscription validation pipeline.

Both use `https://deno.land/std@0.224.0/assert/mod.ts`, are run via `deno test --allow-net --allow-env supabase/functions/...`. No `deno.json` / `import_map.json` — straight URL imports.

### Plan

- New `deno-tests` job in `.github/workflows/ci.yml` — installs Deno (denoland/setup-deno@v2), caches `~/.cache/deno`, runs `deno test --allow-net --allow-env supabase/functions/`.
- Wire into existing `ci` aggregator's `needs` list so a failure blocks merge.
- Run in parallel with `analyze` / `test` / `build` (no inter-dep — Deno tests don't need Flutter SDK).

### Checklist

- [ ] Add `deno-tests` job to `.github/workflows/ci.yml`
- [ ] Add `deno-tests` to `ci` job's `needs` + the `if` predicate that fails on any sub-job non-success
- [ ] Reviewer pass on the workflow before push
- [ ] Push → CI green
- [ ] Trim `PLAN.md` `## Active Backlog` → remove the "Wire Deno tests into CI" line
- [ ] Remove this WIP section
