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
- [x] Reviewer — **zero findings** (independently re-verified the verbatim-diff, gate completeness, exactly-three-writers, test quality). `dart format`/`analyze`/`make test` (+3553) green. **PR #335 open**, CI running.
- [ ] `make test-integration` — **BLOCKED by the WSL2/Docker reboot blocker above**; SQL verified by manual trace + reviewer's independent diff. Run in the post-reboot batch window **before merge** (held).

### PR 38b — Cardio data model + logging surface (active) — branch `feature/phase38b-cardio-logging` (stacked on 38a)

Net-new `cardio_sessions` table + `CardioEntryCard` input. Cardio entries persist
but earn nothing yet (cardio still excluded from `activeBodyParts`). Manual-only
logging (decision): activity type + duration (mandatory) + optional distance + RPE.

- [x] **ui-ux-critic design direction** + mockup `docs/phase-38-mockups.html` (4 states: empty/filled/completed/mixed-session) — **user-approved as-is**. Teal locked `#22D3EE`; duration-as-hero stepper; distance=tap-to-type, RPE=1–10 via sheet; optional fields invite (`+ adicionar`) not nag; card-level teal stripe (strength cards untouched)
- [x] Migration `00078`: `cardio_sessions` (raw inputs only — `duration_seconds` NOT NULL CHECK>0, `distance_m?` CHECK>=0, `rpe?` 1–10; the computed `met`/`met_minutes`/`est_met` columns are DEFERRED to 38c per the PR brief) + RLS via parent workout ownership + explicit grants (cluster `supabase-cli-latest-grant-drift`) + `save_workout` gains `p_cardio jsonb DEFAULT '[]'` (drop 3-arg, recreate 4-arg — old clients calling with 3 named params still resolve via the default; RPC re-pins `workout_id` server-side; DELETE+INSERT idempotent re-save)
- [x] `CardioSession` Freezed model (`toRpcJson`/`fromJson` mirroring `ExerciseSet`); threaded as `ActiveWorkoutExercise.cardioSession?` (nullable field, discriminated by `exercise.muscleGroup == cardio`) → survives Hive crash-recovery like routineNotes
- [x] Notifier: cardio seed in `addExercise`/`startFromRoutine` (default 30:00, no set-1 seed), `updateCardioSession` + `completeCardioEntry` mutations, modality-safe `swapExercise`, `totalSetsCount` counts completed cardio entries (finish guard unblocks cardio-only sessions), `finishWorkout` builds committed-cardio payload (online RPC + offline `PendingSaveWorkout.cardioJson`). Cardio entries do NOT produce `workout_exercises`/`sets` rows (history rendering = 38c/38d CardioLiftRow)
- [x] `CardioEntryCard` (4 mockup states) + `DurationStepper` (mm:ss, 30s steps, 40-wide ± at the real 48dp rendered floor — no `visualDensity: compact`, which silently shrinks WeightStepper's rendered buttons to 40×40) + distance tap-to-type dialog (km/mi by profile weight unit) + RPE bottom sheet (48dp floor; inline pips display-only); shared `ExerciseCardHeader` extracted from `exercise_card.dart` (gains `trailing` slot for the completed ✓); `ExerciseDetailSheet` promoted public so both card types share the detail surface
- [x] `ExerciseList` branches `CardioEntryCard` vs `ExerciseCard`; teal token retune `AppColors.bodyPartCardio` orange→`0xFF22D3EE` (dead token, safe; `body_part_hues.dart` untouched — 38d)
- [x] l10n keys (en+pt): eyebrow activity labels per default cardio slug (keyed on new `Exercise.slug` field returned by `fn_exercises_localized`; Hive cache schema v4→v5 one-shot wipe), field labels, dialogs, semantics
- [x] Unit tests (CardioSession round-trip + rpc shape; CardioFormat duration/distance; notifier cardio lifecycle incl. swap modality + finish payloads — 35 tests) + widget tests (card states, stepper, dialogs, RPE sheet, ≥48dp tap targets via `tester.getSize` — 20 tests) — green locally
- [ ] Integration test `test/integration/cardio_save_roundtrip_test.dart` (tag `integration`): cardio row persists + NO `xp_events`/`body_part_progress[cardio]` + re-save idempotency + legacy 3-arg call + RLS — **written but NOT RUN (WSL2/Docker reboot blocker)**; run `flutter test --tags integration test/integration/cardio_save_roundtrip_test.dart` in the post-reboot batch window (also apply 00077+00078 to local first)
- [x] `make gen` + `dart format` + `dart analyze --fatal-infos` + full unit/widget suite + CI token gates (typography/colors/reward-accent) green
- [x] ui-ux-critic design-match review — **DISTINCTIVE, mockup-faithful**; flagged RPE-pips/summary 320dp clip risk (fixed defensively below)
- [x] reviewer code review — contract checks (save_workout 3→4-arg boundary, mocktail, Hive wipe, legacy offline replay) all SOUND; 2 Important + 2 Suggestions
- [x] review fixes (all same-cycle): (1) completed cardio ✓ no longer hides reorder arrows in reorderMode; (2) `FittedBox(scaleDown)` on RPE pips + completed summary (320dp no-overflow); (3) DurationStepper floors at 30s (invariant ">0 by construction" now literally true); (4) legacy offline-map (no `cardio_json` key) → `cardioJson == []` test. 0-XP cinematic finding **owner-decided: accept interim** (guard unchanged). +tests; gate green (3617)
- [ ] PR open (merge held) → `make test-integration` in reboot window before merge

### PR 38c–38f — queued (see plan file)
38c earning formula + 4-site parity + est-VO₂max · 38d activation (atomic boundary flip + UI) · 38e titles · 38f E2E + QA + calibration sign-off. **Reboot to batch-verify 38a+38b and unblock 38c.**
