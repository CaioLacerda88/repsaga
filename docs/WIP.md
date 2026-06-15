# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## ⚠ Environment blocker — WSL2 broken, reboot deferred until an implementation window

**Plan:** keep authoring Phase 38 (Dart/SQL + `dart analyze` + `make test` are
unaffected); **reboot Windows once we reach a natural break**, then batch-run all the
Docker-dependent verification (38a integration test, 38c parity, 38f E2E, migration
push) in that window.

**Symptom (2026-06-12):** `wsl -d Ubuntu echo ok` AND Docker both fail with
`CreateVm/HCS/ERROR_FILE_NOT_FOUND` — system-wide WSL2 VM-creation failure (not
Docker, not this project).

**Diagnosed:** WSL kernel present (`Program Files\WSL\tools\kernel`, 17 MB),
`vmcompute`/`hns` services running, no `.wslconfig`, `wsl --update` says "already
latest" — yet HCS can't create any VM. **68 pending file-rename ops queued for next
boot + ~2.6 days uptime** → a Windows/WSL servicing update staged changes that only a
**reboot** finalizes. Docker's `ext4.vhdx` is fine (byte-identical to its bundle — not
corrupt; do NOT rename it).

**Fix (at the reboot window):** reboot Windows → verify `wsl -d Ubuntu echo ok` →
start Docker Desktop → `docker info`. If still broken after one reboot, run elevated
and reboot again:
`dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart` +
`dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart`.

**Blocks until then:** 38a `make test-integration`, 38c 4-site parity (needs local
Supabase), 38f Playwright E2E, and `npx supabase db push` of new migrations.

---

## Phase 38 — Cardio / Conditioning Track

Per the approved implementation plan (`~/.claude/plans/noble-stirring-scroll.md`)
and `docs/cardio-stat-plan.md` §4–§7 + `docs/cardio-balance-baseline.md` (14/14
panel). 6 sequential PRs (38a–38f). Decisions locked: build now (pre-launch),
manual-only logging, ship strength→cardio cross-credit in v1, teal-cyan hue.

### PR 38a — Save-gate fix (active) — branch `feature/phase38a-cardio-save-gate`

Pre-feature hygiene: branch the XP/save path so a cardio-attributed set can never
enter the weight×reps chain. Closes the latent mis-attribution bug **and** the
running→strength farm vector (`cardio-stat-plan.md` §1 + §2.6). Independent of the
rest of Phase 38; ships on its own.

- [x] Read `00065_phase29_xp_formula_v2.sql` (`record_set_xp` ~L731 gate, `record_session_xp_batch` ~L1360 gate + cardio→7 index map) + `00005_save_workout_rpc.sql` to pick the cleanest gate mechanism
- [x] New migration `00077_phase38a_cardio_save_gate.sql`: redefines **three** writers (writer audit found `_rpg_backfill_chunk` as a third writer of the same invariant) so cardio-attributed sets are excluded from the strength weight×reps path. Verified verbatim vs 00065 — diff is gate lines + comments only; no migration 00066–00076 redefines these functions
- [x] Gate mechanism: **(a) source-query exclusion on `muscle_group='cardio'`** — (b) per-key skip would still emit zero-XP `xp_events` rows. Data audit: all 8 cardio exercises have pure `{"cardio":1.0}` attribution + `muscle_group='cardio'`; no mixed maps; `fn_insert_user_exercise` has no attribution param (NULL fallback = `{muscle_group:1.0}`) → muscle_group gate is complete. `save_workout` needs NO change (persists raw sets, delegates XP to the batch RPC; reversal pattern self-heals pre-gate latent rows). `backfill_rpg_v1` convergence unaffected (visited-underflow check, no precomputed totals)
- [x] Integration test `test/integration/rpg_cardio_save_gate_test.dart` (tag `integration`): zero cardio `body_part_progress`/`xp_events`, zero strength-peak rows for weighted cardio (sled), control-user strength-XP equality + all three writers covered
- [x] `dart format` (0 changed) + `dart analyze --fatal-infos` (no issues) + unit/widget suite green (+3553, 0 failures). Side-find fixed: Makefile `test:` passed `--exclude-tags` twice — package:test is last-wins, so `make test` was silently RUNNING the integration suite; now a single boolean selector `"integration || golden"`
- [ ] `make test-integration` — **BLOCKED by the WSL2/Docker reboot blocker above**; SQL verified by manual trace (all three writers + backfill_rpg_v1 convergence + save_workout reversal). Run in the post-reboot batch window before merge
- [ ] Reviewer → (QA: tooling/DB, no E2E surface) → ship → condense; apply migration to hosted Supabase post-merge

### PR 38b–38f — queued (see plan file)
38b data model + `CardioEntryCard` · 38c earning formula + 4-site parity + est-VO₂max · 38d activation (atomic boundary flip + UI) · 38e titles · 38f E2E + QA + calibration sign-off.
