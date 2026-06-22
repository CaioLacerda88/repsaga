# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 Tier 0 — launch-readiness release pipeline (scaffold) — `feature/tier0-launch-release-pipeline`

Per `docs/PROJECT.md` §2 → Phase 38.9 Tier 0 (T0.1 release pipeline + T0.2 Sentry). Scaffold the
real release pipeline; INERT until the user adds GitHub secrets + tags a release. CI/tooling →
reviewer reads, QA skipped.

**Already in place (verified):** `android/app/build.gradle.kts` reads `key.properties` for the
release signing config and falls back to debug-signing when absent — so this scaffolding does NOT
break local/CI builds.

### Checklist
- [x] Rewrite `.github/workflows/release.yml`:
  - Inject the keystore (base64 secret → file) + write `android/key.properties` from secrets.
  - Write the REAL prod `.env` from secrets (SUPABASE_URL, SUPABASE_ANON_KEY, SENTRY_DSN) instead
    of `cp .env.example .env`.
  - `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info` (AAB for
    Play) + keep signed split APKs for the GitHub release direct-download. Upload `build/debug-info`
    as a release artifact (needed to de-obfuscate crash stacks).
  - Upload the AAB to Play (internal track) via a Play-upload action, gated on the service-account
    secret (skip gracefully if absent so a tag without secrets fails loud-but-clear, not silently).
  - Keep the GitHub release step for the signed artifacts.
- [x] Verify `build.gradle.kts` signing path is complete (keystore present → release-signed; absent
    → debug fallback). No change expected; confirmed complete — no changes made.
- [x] **T0.2 Sentry:** SENTRY_DSN injected into the release `.env`. Manual verification procedure
    documented in `docs/release-checklist.md` section 4.
- [x] `docs/release-checklist.md` — the exact secrets the user must add to GitHub repo secrets +
    how to generate each (keytool keystore command, Play service-account steps, Sentry DSN, prod
    Supabase creds) + the release/tag procedure.
- [x] YAML valid (python yaml.safe_load passes); ci.yml untouched; release.yml triggers on `v*` tags only.

_Tiers 1-3 complete. T2.5/T2.6 deferred. This is the last hardening item; needs user secrets to go live._
